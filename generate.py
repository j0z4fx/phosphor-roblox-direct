"""
phosphor-roblox-direct: upload spritesheets and generate source.lua
"""
import argparse
import json
import os
import re
import shutil
import time
from pathlib import Path

import requests
from dotenv import load_dotenv

load_dotenv()

ROBLOX_API_TOKEN = os.environ["ROBLOX_API_TOKEN"]
ROBLOX_CREATOR_ID = os.environ["ROBLOX_CREATOR_ID"]
PHOSPHOR_WEIGHTS = ["thin", "light", "regular", "bold", "fill", "duotone"]
OUTPUT_SIZE = 48

# ── paths ──────────────────────────────────────────────────────────────────────
ROOT = Path(__file__).parent
TARMAC_DEBUG_DIR = ROOT / ".tarmac-debug"
SPRITESHEETS_DIR = ROOT / "spritesheets"
MAPPINGS_FILE = ROOT / "build" / "outputs" / "mappings.lua"
TEMPLATE_FILE = ROOT / "scripts" / "assets" / "template.luau"
SOURCE_FILE = ROOT / "source.lua"

# ── build date ─────────────────────────────────────────────────────────────────
from datetime import date
BUILD_VERSION = date.today().isoformat()


def upload_image(png_path: Path, name: str, description: str = "") -> str:
    """Upload a PNG to Roblox Assets API, return 'rbxassetid://XXXXXXX'."""
    payload = {
        "assetType": "Image",
        "displayName": name,
        "description": description,
        "creationContext": {
            "creator": {
                "userId": ROBLOX_CREATOR_ID,
            }
        },
    }
    files = {
        "request": (None, json.dumps(payload), "application/json"),
        "fileContent": (png_path.name, png_path.read_bytes(), "image/png"),
    }
    headers = {"x-api-key": ROBLOX_API_TOKEN}

    res = requests.post(
        "https://apis.roblox.com/assets/v1/assets",
        headers=headers,
        files=files,
        timeout=120,
    )
    res.raise_for_status()
    operation = res.json()

    # Handle async operation response
    op_path = operation.get("path") or operation.get("operationPath")
    if not op_path:
        asset_id = operation.get("assetId")
        if asset_id:
            return f"rbxassetid://{asset_id}"
        raise RuntimeError(f"Unexpected response: {operation}")

    op_url = f"https://apis.roblox.com/assets/v1/{op_path}"
    for attempt in range(120):
        time.sleep(1)
        check = requests.get(op_url, headers=headers, timeout=60)
        check.raise_for_status()
        data = check.json()
        if data.get("done"):
            response = data.get("response", {})
            asset_id = response.get("assetId")
            if asset_id:
                return f"rbxassetid://{asset_id}"
            raise RuntimeError(f"Upload done but no assetId: {data}")
    raise TimeoutError(f"Timed out waiting for upload of {png_path.name}")


def parse_mappings_lua(lua_text: str) -> dict:
    """
    Parse Tarmac's mappings.lua into a Python dict.
    Returns { "packed_name": {"Image": "rbxassetid://N", "ImageRectOffset": [x,y], "ImageRectSize": [w,h]} }
    """
    mappings = {}
    # Each entry looks like:
    #   ["weight__iconname.png"] = {Image = "rbxassetid://1234", ImageRectOffset = Vector2.new(0, 0), ImageRectSize = Vector2.new(48, 48)},
    pattern = re.compile(
        r'\["([^"]+)"\]\s*=\s*\{[^}]*Image\s*=\s*"([^"]+)"[^}]*'
        r'ImageRectOffset\s*=\s*Vector2\.new\(([^)]+)\)[^}]*'
        r'ImageRectSize\s*=\s*Vector2\.new\(([^)]+)\)',
        re.DOTALL,
    )
    for m in pattern.finditer(lua_text):
        packed_name = m.group(1)
        image = m.group(2)
        offset = [float(v.strip()) for v in m.group(3).split(",")]
        size = [float(v.strip()) for v in m.group(4).split(",")]
        mappings[packed_name] = {
            "Image": image,
            "ImageRectOffset": offset,
            "ImageRectSize": size,
        }
    return mappings


def lua_encode(value) -> str:
    """Minimal Lua table serialiser."""
    if isinstance(value, str):
        return json.dumps(value)  # produces "..." with proper escaping
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(int(value)) if value == int(value) else str(value)
    if isinstance(value, list):
        parts = [lua_encode(v) for v in value]
        return "{" + ",".join(parts) + "}"
    if isinstance(value, dict):
        parts = []
        for k, v in value.items():
            if isinstance(k, str) and re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', k):
                parts.append(f"{k}={lua_encode(v)}")
            else:
                parts.append(f"[{lua_encode(k)}]={lua_encode(v)}")
        return "{" + ",".join(parts) + "}"
    raise TypeError(f"Unsupported type: {type(value)}")


def main():
    # ── Step 1: Copy spritesheets from .tarmac-debug ───────────────────────────
    if SPRITESHEETS_DIR.exists():
        shutil.rmtree(SPRITESHEETS_DIR)
    SPRITESHEETS_DIR.mkdir()

    spritesheet_files = sorted(TARMAC_DEBUG_DIR.iterdir())
    print(f"Found {len(spritesheet_files)} spritesheets to upload.")

    # ── Step 2: Upload each spritesheet, collect real IDs ─────────────────────
    # Tarmac uses temporary local IDs (small integers like 1, 2, 3...)
    # We map temp_id -> real rbxassetid
    temp_to_real = {}  # e.g. {"rbxassetid://1": "rbxassetid://1234567890"}
    num_spritesheets = len(spritesheet_files)

    for i, src in enumerate(spritesheet_files, 1):
        dest = SPRITESHEETS_DIR / f"{src.name}.png"
        shutil.copy(src, dest)

        print(f"[{i}/{num_spritesheets}] Uploading {dest.name}...")
        real_id = upload_image(
            dest,
            name=f"Phosphor Spritesheet {src.name}",
            description=f"Phosphor Icons spritesheet. Built {BUILD_VERSION}.",
        )
        print(f"  -> {real_id}")
        # Tarmac debug IDs are just the filename (e.g. "1", "2")
        temp_to_real[f"rbxassetid://{src.name}"] = real_id

    # ── Step 3: Parse Tarmac mappings ─────────────────────────────────────────
    print("\nParsing Tarmac mappings...")
    mappings_text = MAPPINGS_FILE.read_text(encoding="utf-8")
    tarmac_mappings = parse_mappings_lua(mappings_text)
    print(f"  {len(tarmac_mappings)} icon entries found.")

    # ── Step 4: Build icon data tables ────────────────────────────────────────
    icon_names = []
    icon_name_to_index = {}
    weight_names = PHOSPHOR_WEIGHTS
    weight_name_to_index = {w: i + 1 for i, w in enumerate(weight_names)}

    image_assets = []
    image_asset_to_index = {}
    rect_info_by_weight = {i + 1: {} for i in range(len(weight_names))}

    for packed_name, data in tarmac_mappings.items():
        # packed_name format: "weight__iconname.png"
        m = re.match(r'^([^_]+)__(.+)$', packed_name)
        if not m:
            continue
        weight, icon_file = m.group(1), m.group(2)
        icon_name = re.sub(r'\.png$', '', icon_file)

        if weight not in weight_name_to_index:
            continue

        # Register icon name
        if icon_name not in icon_name_to_index:
            icon_names.append(icon_name)
            icon_name_to_index[icon_name] = len(icon_names)
        icon_index = icon_name_to_index[icon_name]

        # Swap temp ID with real uploaded ID
        temp_image = data["Image"]
        real_image = temp_to_real.get(temp_image, temp_image)

        # Register image asset
        if real_image not in image_asset_to_index:
            image_assets.append(real_image)
            image_asset_to_index[real_image] = len(image_assets)
        image_index = image_asset_to_index[real_image]

        weight_index = weight_name_to_index[weight]
        rect_info_by_weight[weight_index][icon_index] = [
            image_index,
            data["ImageRectSize"],
            data["ImageRectOffset"],
        ]

    icon_data = [
        icon_names,
        weight_names,
        image_assets,
        {OUTPUT_SIZE: rect_info_by_weight},
    ]
    serialized = lua_encode(icon_data)

    # ── Step 5: Read template and write source.lua ─────────────────────────────
    template = TEMPLATE_FILE.read_text(encoding="utf-8")
    source = template \
        .replace("= VERSION", f'= "{BUILD_VERSION}"') \
        .replace("DATA_SPRITESHEETS", str(num_spritesheets)) \
        .replace("DATA_ICON_MAPPINGS", serialized)

    SOURCE_FILE.write_text(source, encoding="utf-8")
    print(f"\nDone! source.lua written to {SOURCE_FILE}")
    print(f"  Icons: {len(icon_names)}, Weights: {len(weight_names)}, Spritesheets: {num_spritesheets}")


if __name__ == "__main__":
    main()
