# phosphor-roblox-direct

Standalone Roblox/Luau icon module generator for Phosphor Icons.

This is modeled after `lucide-roblox-direct`: it converts upstream SVG icons into PNGs, packs them into Roblox spritesheets with Tarmac, uploads those spritesheets to Roblox, and writes a single `source.lua` module that returns ImageLabel-ready asset data.

## What it generates

`source.lua` exports:

```lua
local Phosphor = loadstring(game:HttpGet(".../source.lua"))()

local icon = Phosphor.GetAsset("ghost", "regular")
ImageLabel.Image = icon.Url
ImageLabel.ImageRectSize = icon.ImageRectSize
ImageLabel.ImageRectOffset = icon.ImageRectOffset
```

Supported weights:

```lua
thin, light, regular, bold, fill, duotone
```

## Requirements

Install:

- Python 3
- Inkscape
- ImageMagick
- Rokit

Then:

```bash
rokit install
pip install -r requirements.txt
```

Create `.env`:

```bash
ROBLOX_API_TOKEN=your_open_cloud_api_key
ROBLOX_CREATOR_ID=your_user_or_group_id
```

Your token needs asset upload permissions.

## Build

```bash
sh scripts/update.sh
```

This creates:

- `spritesheets/*.png`
- `source.lua`

## Important config

In `scripts/assets/template.luau`, change:

```lua
local REMOTE_SPRITESHEET_BASE = "https://raw.githubusercontent.com/YOUR_USERNAME/phosphor-roblox-direct/refs/heads/main/spritesheets"
```

to your actual GitHub raw path.
