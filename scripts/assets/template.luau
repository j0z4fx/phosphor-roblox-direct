local Phosphor = {}

local VERSION_STRING = VERSION
local REMOTE_SPRITESHEET_BASE = "https://raw.githubusercontent.com/j0z4fx/phosphor-roblox-direct/refs/heads/main/spritesheets"

local IS_GETCUSTOMASSET_BROKEN = false

if writefile and isfile and isfolder and makefolder and getcustomasset then
	if not isfolder("phosphor-icons") then
		makefolder("phosphor-icons")
	end

	if not isfile("phosphor-icons/version.txt") then
		writefile("phosphor-icons/version.txt", VERSION_STRING)
	end

	local ShouldUpdate = readfile("phosphor-icons/version.txt") ~= VERSION_STRING

	if ShouldUpdate then
		writefile("phosphor-icons/version.txt", VERSION_STRING)
	end

	for spritesheet = 1, DATA_SPRITESHEETS do
		local path = `phosphor-icons/{spritesheet}.png`

		if isfile(path) and not ShouldUpdate then
			continue
		end

		writefile(path, game:HttpGet(`{REMOTE_SPRITESHEET_BASE}/{spritesheet}.png`))
	end

	local Success = pcall(function()
		return getcustomasset("phosphor-icons/1.png")
	end)

	IS_GETCUSTOMASSET_BROKEN = not Success
end

local icons = DATA_ICON_MAPPINGS

local iconNames: { string } = icons[1]
local weightNames: { string } = icons[2]
local imageAssets: { string } = icons[3]
local iconRegistry: { [number]: { [number]: { { number | { number } } } } } = icons[4]

Phosphor.Icons = iconNames
Phosphor.Weights = weightNames

function Phosphor.GetAsset(name: string, weight: string?)
	weight = weight or "regular"

	local size = 48
	local iconIndex = table.find(iconNames, name)
	local weightIndex = table.find(weightNames, weight)

	if not iconIndex or not weightIndex then
		return nil
	end

	local currentDifference = math.huge
	local currentSize = size

	for registrySize in iconRegistry do
		local diff = math.abs(size - registrySize)

		if diff < currentDifference then
			currentDifference = diff
			currentSize = registrySize
		end
	end

	local byWeight = iconRegistry[currentSize][weightIndex]
	if not byWeight then
		return nil
	end

	local icon = byWeight[iconIndex]
	if icon then
		return {
			IconName = name,
			Weight = weight,
			Url = imageAssets[icon[1]],
			ImageRectSize = Vector2.new(icon[2][1], icon[2][2]),
			ImageRectOffset = Vector2.new(icon[3][1], icon[3][2]),
		}
	end

	return nil
end

return Phosphor
