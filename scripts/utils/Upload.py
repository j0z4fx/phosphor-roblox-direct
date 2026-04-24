import argparse
import json
import time
from pathlib import Path

import requests


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--name", required=True)
    parser.add_argument("--description", default="")
    parser.add_argument("--auth", required=True)
    parser.add_argument("--creator-id", required=True)
    parser.add_argument("--creator-type", default="User", choices=["User", "Group"])
    args = parser.parse_args()

    file_path = Path(args.path)
    if not file_path.exists():
        raise FileNotFoundError(file_path)

    request_payload = {
        "assetType": "Image",
        "displayName": args.name,
        "description": args.description,
        "creationContext": {
            "creator": {
                args.creator_type.lower() + "Id": args.creator_id,
            }
        },
    }

    files = {
        "request": (None, json.dumps(request_payload), "application/json"),
        "fileContent": (file_path.name, file_path.read_bytes(), "image/png"),
    }

    headers = {"x-api-key": args.auth}
    res = requests.post("https://apis.roblox.com/assets/v1/assets", headers=headers, files=files, timeout=120)
    res.raise_for_status()

    operation = res.json()
    operation_path = operation.get("path") or operation.get("operationPath")
    if not operation_path:
        print(operation.get("assetId") or operation.get("assetId".lower()))
        return

    op_url = f"https://apis.roblox.com/assets/v1/{operation_path}"
    for _ in range(120):
        check = requests.get(op_url, headers=headers, timeout=60)
        check.raise_for_status()
        data = check.json()
        if data.get("done"):
            response = data.get("response", {})
            asset_id = response.get("assetId") or response.get("assetId".lower())
            if asset_id:
                print(f"rbxassetid://{asset_id}")
                return
            print(json.dumps(data))
            return
        time.sleep(1)

    raise TimeoutError("Timed out waiting for Roblox asset upload operation.")


if __name__ == "__main__":
    main()
