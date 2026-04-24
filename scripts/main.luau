--!strict

--// Lune services
local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

type UploadAssetOptions = {
	path: string,
	name: string,
	description: string?,
}

local BUILD_VERSION = DateTime.now():toIsoDate()
local ROBLOX_API_TOKEN = process.env["ROBLOX_API_TOKEN"]
local ROBLOX_CREATOR_ID = process.env["ROBLOX_CREATOR_ID"]

local PHOSPHOR_REPO = "https://github.com/phosphor-icons/core.git"
local PHOSPHOR_WEIGHTS = { "thin", "light", "regular", "bold", "fill", "duotone" }
local OUTPUT_SIZE = 48

local function LuaString(value: string): string
	return string.format("%q", value)
end

local function IsArray(t: { [any]: any }): boolean
	local count = 0
	for k in t do
		if type(k) ~= "number" then
			return false
		end
		count += 1
	end
	for i = 1, count do
		if t[i] == nil then
			return false
		end
	end
	return true
end

local function LuaEncode(value: any): string
	local valueType = typeof(value)

	if valueType == "string" then
		return LuaString(value)
	elseif valueType == "number" or valueType == "boolean" then
		return tostring(value)
	elseif valueType == "table" then
		local parts = {}
		local array = IsArray(value)

		table.insert(parts, "{")

		if array then
			for i = 1, #value do
				table.insert(parts, LuaEncode(value[i]))
				table.insert(parts, ",")
			end
		else
			for k, v in value do
				local key
				if type(k) == "string" and k:match("^[A-Za-z_][A-Za-z0-9_]*$") then
					key = k
				else
					key = "[" .. LuaEncode(k) .. "]"
				end
				table.insert(parts, key .. "=" .. LuaEncode(v) .. ",")
			end
		end

		table.insert(parts, "}")
		return table.concat(parts)
	else
		error(`Unsupported type for LuaEncode: {valueType}`)
	end
end

local function ReplaceScriptGlobals(script: string, replacements: { [string]: string }): string
	for key, value in replacements do
		script = script:gsub(key, value)
	end

	return script
end

local function RunCommand(cmd: string, cwd: string?, check: boolean?): any
	local checkFlag = if check == nil then true else check
	local options = {}

	if cwd then
		options.cwd = cwd
	end

	local result = process.exec("sh", { "-c", cmd }, options)

	if checkFlag and not result.ok then
		stdio.ewrite(`Error running command: {cmd}\n`)
		stdio.ewrite(`Exit code: {result.code}\nOutput:{result.stdout}\n{result.stderr}\n`)
		process.exit(result.code)
	end

	return result
end

local function UploadImageAssetToRoblox(options: UploadAssetOptions): string
	assert(ROBLOX_API_TOKEN, "ROBLOX_API_TOKEN environment variable is not set")
	assert(ROBLOX_CREATOR_ID, "ROBLOX_CREATOR_ID environment variable is not set")

	local result = RunCommand(
		`python scripts/utils/Upload.py {options.path} --name "{options.name}" --description "{options.description or ""}" --auth "{ROBLOX_API_TOKEN}" --creator-id {ROBLOX_CREATOR_ID}`,
		nil,
		true
	)

	if not result.ok then
		stdio.ewrite(`Failed to upload image asset: {result.stderr}\n`)
		process.exit(1)
	end

	return result.stdout:gsub("\n", ""):gsub("\r", ""):gsub(" ", "")
end

local function SetupDirectories()
	print("Setting up directories...")

	if not fs.isDir("build") then
		fs.writeDir("build")
	end

	if fs.isDir(".tarmac-debug") then
		fs.removeDir(".tarmac-debug")
	end

	if fs.isDir("build/outputs") then
		fs.removeDir("build/outputs")
	end

	fs.writeDir("build/outputs")
	fs.writeDir("build/outputs/formatted_icons")
end

local function SetupPhosphor()
	if not fs.isDir("build/phosphor") then
		print("Cloning Phosphor core repository...")
		RunCommand(`git clone --filter=blob:none --sparse {PHOSPHOR_REPO} phosphor`, "build")
	end

	RunCommand("git sparse-checkout set --no-cone assets", "build/phosphor")
	RunCommand("git pull origin main", "build/phosphor")
end

local function ConvertSvgsToPngs()
	print("Converting Phosphor SVG files to PNG...")

	local svgJobs = {}

	for _, weight in PHOSPHOR_WEIGHTS do
		local weightDir = `build/phosphor/assets/{weight}`

		if fs.isDir(weightDir) then
			for _, file in fs.readDir(weightDir) do
				if file:match("%.svg$") then
					table.insert(svgJobs, {
						weight = weight,
						input = `{weightDir}/{file}`,
						output = `build/outputs/formatted_icons/{weight}__{file:gsub("%.svg$", ".png")}`,
					})
				end
			end
		end
	end

	print(`Found {#svgJobs} SVG files to convert.`)

	local completed = 0
	local lastCompleted = false

	for i, job in ipairs(svgJobs) do
		task.spawn(function()
			local cmd = `inkscape "{job.input}" --export-type="png" --export-filename="{job.output}" --export-width={OUTPUT_SIZE} --export-height={OUTPUT_SIZE} --export-background-opacity=0`
			local result = RunCommand(cmd, nil, false)

			completed += 1
			if i == #svgJobs then
				lastCompleted = true
			end

			if result.ok then
				print(`[{completed}/{#svgJobs}] ✓ {job.weight}/{job.input:match("[^/]+$")}`)
			else
				print(`[{completed}/{#svgJobs}] ✗ {job.input}: {result.stderr}`)
			end
		end)

		if i % 10 == 0 then
			task.wait(0.4)
		end
	end

	repeat
		task.wait(0.1)
	until lastCompleted
end

local function ProcessPngs()
	print("Processing PNGs with ImageMagick...")

	local pngFiles = {}

	for _, file in fs.readDir("build/outputs/formatted_icons") do
		if file:match("%.png$") then
			table.insert(pngFiles, `build/outputs/formatted_icons/{file}`)
		end
	end

	local completed = 0
	local lastCompleted = false

	for i, pngFile in ipairs(pngFiles) do
		task.spawn(function()
			-- Force black source icons into white alpha-safe icons.
			local cmd = `magick "{pngFile}" -channel RGB -negate +channel -alpha on -type TrueColorAlpha -colorspace sRGB -define png:color-type=6 "{pngFile}"`
			local result = RunCommand(cmd, nil, false)

			completed += 1
			if i == #pngFiles then
				lastCompleted = true
			end

			if result.ok then
				print(`[{completed}/{#pngFiles}] ✓ {pngFile:match("[^/]+$")}`)
			else
				print(`[{completed}/{#pngFiles}] ✗ {pngFile}: {result.stderr}`)
			end
		end)

		if i % 100 == 0 then
			task.wait(0.65)
		end
	end

	repeat
		task.wait(0.1)
	until lastCompleted
end

print("Starting Phosphor Roblox Direct build...")

SetupDirectories()
SetupPhosphor()
ConvertSvgsToPngs()
ProcessPngs()

print("Creating spritesheets with Tarmac...")
local spritesheetResult = RunCommand("tarmac sync --target debug")

if not spritesheetResult.ok then
	print("Error occurred while creating spritesheet via Tarmac.")
	process.exit(1)
end

local tarmacIconMappings = {}
do
	local vector2Library = [[
local Vector2 = {}
function Vector2.new(x: number, y: number)
	return { x, y }
end
]]

	local mappingsSource = fs.readFile("build/outputs/mappings.lua")
	tarmacIconMappings = luau.load(vector2Library .. "\n" .. mappingsSource)()["formatted_icons"]
end

local spritesheetFiles = fs.readDir(".tarmac-debug")

if fs.isDir("spritesheets") then
	fs.removeDir("spritesheets")
end

fs.writeDir("spritesheets")

for _, file in spritesheetFiles do
	fs.copy(`.tarmac-debug/{file}`, `spritesheets/{file}.png`)
end

local iconNames = {}
local iconNameToIndex = {}

local weightNames = PHOSPHOR_WEIGHTS
local weightNameToIndex = {}

for i, weight in ipairs(weightNames) do
	weightNameToIndex[weight] = i
end

local imageAssets = {}
local imageAssetToIndex = {}
local insertedIds = {}
local rectInfoByWeight = {}

for weightIndex = 1, #weightNames do
	rectInfoByWeight[weightIndex] = {}
end

for packedName, data in tarmacIconMappings do
	local weight, iconName = packedName:match("^([^_]+)__(.+)$")
	iconName = iconName and iconName:gsub("%.png$", "") or nil

	if weight and iconName then
		local iconIndex = iconNameToIndex[iconName]
		if not iconIndex then
			table.insert(iconNames, iconName)
			iconIndex = #iconNames
			iconNameToIndex[iconName] = iconIndex
		end

		local image = data.Image
		local tempId = tonumber(image:gsub("rbxassetid://", ""))

		local imageIndex = imageAssetToIndex[image]
		if not imageIndex then
			table.insert(imageAssets, image)
			imageIndex = #imageAssets
			imageAssetToIndex[image] = imageIndex
		end

		insertedIds[tempId] = true

		local weightIndex = weightNameToIndex[weight]
		rectInfoByWeight[weightIndex][iconIndex] = {
			imageIndex,
			data.ImageRectSize,
			data.ImageRectOffset,
		}
	end
end

local iconData = {
	iconNames,
	weightNames,
	imageAssets,
	{
		[OUTPUT_SIZE] = rectInfoByWeight,
	},
}

local serializedData = LuaEncode(iconData)

local realRobloxContentId = {}

for id in insertedIds do
	local assetId = UploadImageAssetToRoblox({
		path = `spritesheets/{id}.png`,
		name = `Phosphor Spritesheet {id}`,
		description = `Spritesheet for Phosphor Icons. Built at {BUILD_VERSION}.`,
	})

	print("Successfully uploaded a Phosphor spritesheet:", assetId)
	realRobloxContentId[id] = assetId
end

for id in insertedIds do
	local oldAssetLiteral = `"rbxassetid://{id}"`
	local replacement = `if getcustomasset and not IS_GETCUSTOMASSET_BROKEN then getcustomasset("phosphor-icons/{id}.png") else "{realRobloxContentId[id]}"`
	serializedData = serializedData:gsub(oldAssetLiteral, replacement)
end

local template = fs.readFile("scripts/assets/template.luau")

fs.writeFile(
	"source.lua",
	ReplaceScriptGlobals(template, {
		["VERSION"] = `"{BUILD_VERSION}"`,
		["DATA_SPRITESHEETS"] = tostring(#spritesheetFiles),
		["DATA_ICON_MAPPINGS"] = serializedData,
	})
)

print("Phosphor Roblox Direct build completed successfully.")
