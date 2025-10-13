--!strict
--[[
    ASTRALIS 🌠
    
    Fetches icon sets from Iconify, converts them to PNG sprites, packs them into
    atlas textures, and generates metadata for use in Iconvault.
    
    Pipeline:
    1. Fetch icon data from Iconify GitHub repository
    2. Generate SVG files with normalized colors
    3. Convert SVGs to PNGs using resvg
    4. Pack PNGs into sprite atlases using libGDX TexturePacker
    5. Apply alpha-bleeding to final spritesheets to fix dark edges
    6. Compress spritesheets with oxipng
    7. Upload spritesheets to Roblox as decal assets
    8. Generate metadata JSON mapping icons to atlas positions with asset IDs
    9. Clean up intermediate files, leaving only icons.json

	Credits to tools used:
	- "alpha-bleed" by https:/github.com/EgoMoose © MIT
	- "LibGDX TexturePacker" by https:/github.com/libgdx/libgdx © Apache 2.0
	- "resvg" by https:/github.com/RazrFalcon/resvg © MIT
	- "oxipng" by https:/github.com/oxipng/oxipng © MIT
	- "rbxcloud" by https:/github.com/Sleitnick/rbxcloud © MIT
--]]

--═══════════════════════════════════════════════════════════
-- DEPENDENCIES
--═══════════════════════════════════════════════════════════
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local net = require("@lune/net")
local process = require("@lune/process")
local task = require("@lune/task")

--═══════════════════════════════════════════════════════════
-- ANSI FORMATTING
--═══════════════════════════════════════════════════════════
local ANSI = {
	RED = "\27[31m",
	GREEN = "\27[32m",
	YELLOW = "\27[33m",
	CYAN = "\27[36m",
	BLUE = "\27[34m",
	PINK = "\27[95m",
	BG_RED = "\27[41m",
	BG_GREEN = "\27[42m",
	BG_YELLOW = "\27[43m",
	BOLD = "\27[1m",
	DIM = "\27[2m",
	RESET = "\27[0m",
}

--═══════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
--═══════════════════════════════════════════════════════════
type IconData = {
	body: string,
	width: number,
	height: number,
	left: number,
	top: number,
	rotate: number?,
	hFlip: boolean?,
	vFlip: boolean?,
}

type IconPositionData = {
	x: number,
	y: number,
}

type IconsetMetadata = {
	name: string,
	iconCount: number,
	author: string,
	license: {
		name: string,
		spdx: string,
	},
	samples: { string },
	lastRefreshed: number,
	lastUpdated: number,
	icons: { [string]: { [string]: IconPositionData } }, -- decalNumber -> iconName -> {x, y}
}

type ConfigConditions = {
	fetchIconData: boolean,
	generateSVG: boolean,
	convertToPNG: boolean,
	packSprites: boolean,
	alphaBleed: boolean,
	compressImages: boolean,
	uploadToRoblox: boolean,
	generateMetadata: boolean,
}

type Config = {
	packedRes: number,
	iconRes: number,
	defaultColor: string,
	iconsets: { string },
	conditions: ConfigConditions,
}

type CompressionStats = {
	compressed: number,
	failed: number,
	totalSaved: number,
}

--═══════════════════════════════════════════════════════════
-- CONFIGURATION
--═══════════════════════════════════════════════════════════
local ICONSET_BASE_URL = "https://raw.githubusercontent.com/iconify/icon-sets/refs/heads/master/json/%s.json"
local START_TIMESTAMP = os.time()

-- Environment variables
local RBLX_API_KEY = process.env.RBLX_API_KEY
local HOLDER_USER_ID = process.env.HOLDER_USER_ID

local config: Config = {
	packedRes = 1024, -- Spritesheet resolution (1024x1024)
	iconRes = 128, -- Individual icon resolution (128x128)
	defaultColor = "#FFFFFF", -- White base for runtime recoloring
	iconsets = { "tabler", "majesticons" },

	-- Step conditions: Enable/disable specific pipeline steps
	conditions = {
		fetchIconData = true,
		generateSVG = true,
		convertToPNG = true,
		packSprites = true,
		alphaBleed = true,
		compressImages = true,
		uploadToRoblox = true,
		generateMetadata = true,
	},
}

--═══════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
--═══════════════════════════════════════════════════════════

--- Validates that icons can be evenly packed into spritesheets
local function validateConfig(cfg: Config)
	if cfg.packedRes % cfg.iconRes ~= 0 then
		error(`{ANSI.BG_RED} ERROR {ANSI.RESET} iconRes must divide packedRes exactly for even packing`)
	end
end

--- Validates API key is present
local function validateApiKey()
	if not RBLX_API_KEY or RBLX_API_KEY == "" then
		error(
			`{ANSI.BG_RED} ERROR {ANSI.RESET} RBLX_API_KEY environment variable is not set.\n`
				.. `  Please set it with your Roblox Open Cloud API key.`
		)
	end
end

--- Fetches and decodes JSON from a URL
local function fetchJson(url: string): any
	local response = net.request(url)

	if not response.ok then
		error(`{ANSI.BG_RED} ERROR {ANSI.RESET} HTTP {response.statusCode}: {response.statusMessage}`)
	end

	return serde.decode("json", response.body)
end

--- Creates necessary directory structure for an iconset
local function ensureDirectories(iconsetName: string)
	local dirs = {
		"svg",
		`svg/{iconsetName}`,
		"png",
		`png/{iconsetName}`,
	}

	for _, dir in dirs do
		if not fs.isDir(dir) then
			fs.writeDir(dir)
		end
	end
end

--- Counts entries in a dictionary
local function countKeys(tbl: { [any]: any }): number
	local count = 0
	for _ in pairs(tbl) do
		count += 1
	end
	return count
end

--- Loads existing icons.json if it exists
local function loadExistingMetadata(): { [string]: IconsetMetadata }?
	if fs.isFile("icons.json") then
		local content = fs.readFile("icons.json")
		return serde.decode("json", content)
	end
	return nil
end

--═══════════════════════════════════════════════════════════
-- ICON DATA PROCESSING
--═══════════════════════════════════════════════════════════

--- Resolves icon properties with fallback to root defaults
local function resolveIconDefaults(icon: any, rootDefaults: any): IconData
	return {
		body = icon.body,
		width = icon.width or rootDefaults.width or 16,
		height = icon.height or rootDefaults.height or 16,
		left = icon.left or rootDefaults.left or 0,
		top = icon.top or rootDefaults.top or 0,
		rotate = icon.rotate or 0,
		hFlip = if icon.hFlip ~= nil then icon.hFlip else false,
		vFlip = if icon.vFlip ~= nil then icon.vFlip else false,
	}
end

--- Resolves alias references according to Iconify specification
--- Handles transformations (rotate, flip) and property inheritance
local function resolveAlias(aliasName: string, aliasData: any, iconsData: any, rootDefaults: any): IconData?
	local parent = iconsData[aliasData.parent]
	if not parent then
		print(`{ANSI.YELLOW}⚠ {ANSI.RESET}Alias {ANSI.DIM}{aliasName}{ANSI.RESET} references missing parent`)
		return nil
	end

	local resolved = resolveIconDefaults(parent, rootDefaults)

	-- Apply transformations (Iconify spec: combine via XOR for flips, add for rotate)
	if aliasData.rotate then
		resolved.rotate = (resolved.rotate + aliasData.rotate) % 4
	end
	if aliasData.hFlip ~= nil then
		resolved.hFlip = resolved.hFlip ~= aliasData.hFlip
	end
	if aliasData.vFlip ~= nil then
		resolved.vFlip = resolved.vFlip ~= aliasData.vFlip
	end

	-- Override dimensions if specified
	resolved.width = aliasData.width or resolved.width
	resolved.height = aliasData.height or resolved.height
	resolved.left = aliasData.left or resolved.left
	resolved.top = aliasData.top or resolved.top

	return resolved
end

--═══════════════════════════════════════════════════════════
-- SVG/PNG CONVERSION
--═══════════════════════════════════════════════════════════

--- Generates SVG markup from icon data
local function generateSVG(iconData: IconData, defaultColor: string): string
	local body = string.gsub(iconData.body, "currentColor", defaultColor)
	local viewBox = `{iconData.left} {iconData.top} {iconData.width} {iconData.height}`

	return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="{viewBox}" width="{iconData.width}" height="{iconData.height}">{body}</svg>`
end

--- Writes SVG content to disk
local function writeSVGFile(iconsetName: string, iconName: string, svgContent: string)
	fs.writeFile(`svg/{iconsetName}/{iconName}.svg`, svgContent)
end

--- Converts SVG to PNG using resvg rasterizer
local function convertSVGtoPNG(iconsetName: string, iconName: string, iconRes: number): boolean
	local svgPath = `svg/{iconsetName}/{iconName}.svg`
	local pngPath = `png/{iconsetName}/{iconName}.png`

	local result = process.exec("resvg", {
		"--width",
		tostring(iconRes),
		"--height",
		tostring(iconRes),
		svgPath,
		pngPath,
	})

	if not result.ok then
		print(`{ANSI.RED}✗ {ANSI.RESET}Failed to convert {ANSI.DIM}{iconName}{ANSI.RESET} (code {result.code})`)
		return false
	end

	return true
end

--═══════════════════════════════════════════════════════════
-- SPRITE PACKING
--═══════════════════════════════════════════════════════════

--- Creates libGDX TexturePacker configuration file
local function createPackConfig(iconsetName: string)
	local packConfig = {
		pot = false,
		paddingX = 0,
		paddingY = 0,
		bleed = false,
		edgePadding = false,
		rotation = false,
		minWidth = config.iconRes,
		minHeight = config.iconRes,
		maxWidth = config.packedRes,
		maxHeight = config.packedRes,
		square = false,
		stripWhitespaceX = false,
		stripWhitespaceY = false,
		alphaThreshold = 0,
		filterMin = "Nearest",
		filterMag = "Nearest",
		wrapX = "ClampToEdge",
		wrapY = "ClampToEdge",
		format = "RGBA8888",
		alias = true,
		outputFormat = "png",
		jpegQuality = 0.9,
		ignoreBlankImages = true,
		fast = false,
		debug = false,
		combineSubdirectories = false,
		flattenPaths = false,
		premultiplyAlpha = false,
		useIndexes = false,
		limitMemory = true,
		grid = true,
		atlasExtension = ".atlas",
		prettyPrint = true,
		legacyOutput = false,
	}

	fs.writeFile(`png/{iconsetName}/pack.json`, serde.encode("json", packConfig))
end

--- Packs PNG icons into sprite atlas using libGDX TexturePacker
local function packIconsetSprites(iconsetName: string): boolean
	print(`\n{ANSI.CYAN}▸ {ANSI.BOLD}Packing Sprites{ANSI.RESET}`)
	print(`  {ANSI.DIM}Creating sprite atlas...{ANSI.RESET}`)

	-- Ensure output directory exists
	local spritesheetPath = `spritesheets/{iconsetName}`
	if not fs.isDir("spritesheets") then
		fs.writeDir("spritesheets")
	end
	if not fs.isDir(spritesheetPath) then
		fs.writeDir(spritesheetPath)
	end

	createPackConfig(iconsetName)

	local result = process.exec("java", {
		"-cp",
		"runnable-texturepacker.jar",
		"com.badlogic.gdx.tools.texturepacker.TexturePacker",
		`png/{iconsetName}`,
		spritesheetPath,
		iconsetName,
	})

	if not result.ok then
		print(`  {ANSI.RED}✗{ANSI.RESET} Packing failed (code {result.code})`)
		return false
	end

	print(`  {ANSI.GREEN}✓{ANSI.RESET} Atlas created`)
	return true
end

--- Applies alpha-bleeding to final spritesheets to fix dark edges
local function alphaBleedSpritesheets(iconsetName: string): boolean
	print(`\n{ANSI.CYAN}▸ {ANSI.BOLD}Alpha-Bleeding Spritesheets{ANSI.RESET}`)

	local spritesheetDir = `spritesheets/{iconsetName}`
	local bleedCount = 0
	local failCount = 0

	for _, file in fs.readDir(spritesheetDir) do
		if string.match(file, "%.png$") then
			local filePath = `{spritesheetDir}/{file}`
			local result = process.exec("alpha-bleed", { filePath, filePath })

			if result.ok then
				bleedCount += 1
				print(`  {ANSI.GREEN}✓{ANSI.RESET} {file}`)
			else
				failCount += 1
				print(`  {ANSI.RED}✗{ANSI.RESET} Failed: {file}`)
			end
		end
	end

	if failCount > 0 then
		print(
			`  {ANSI.YELLOW}⚠{ANSI.RESET} Alpha-bled {ANSI.BOLD}{bleedCount}{ANSI.RESET} {ANSI.RED}({failCount} failed){ANSI.RESET}`
		)
		return false
	else
		print(`  {ANSI.GREEN}✓{ANSI.RESET} Alpha-bled {ANSI.BOLD}{bleedCount}{ANSI.RESET} spritesheet(s)`)
		return true
	end
end

--- Compresses spritesheets using oxipng (lossless optimization)
local function compressSpritesheets(iconsetName: string): CompressionStats
	print(`\n{ANSI.CYAN}▸ {ANSI.BOLD}Optimizing Images{ANSI.RESET}`)

	local spritesheetDir = `spritesheets/{iconsetName}`
	local stats: CompressionStats = {
		compressed = 0,
		failed = 0,
		totalSaved = 0,
	}

	for _, file in fs.readDir(spritesheetDir) do
		if string.match(file, "%.png$") then
			local filePath = `{spritesheetDir}/{file}`
			local originalSize = #fs.readFile(filePath)

			local result = process.exec("oxipng", {
				"-o",
				"4",
				"--strip",
				"safe",
				"--alpha",
				filePath,
			})

			if result.ok then
				local newSize = #fs.readFile(filePath)
				local saved = originalSize - newSize
				stats.totalSaved += saved
				stats.compressed += 1

				local savedPercent = math.floor((saved / originalSize) * 100 + 0.5)
				local savedKB = math.floor(saved / 1024 * 10 + 0.5) / 10
				print(`  {ANSI.GREEN}✓{ANSI.RESET} {file} {ANSI.DIM}→ {savedPercent}% ({savedKB} KB){ANSI.RESET}`)
			else
				stats.failed += 1
				print(`  {ANSI.RED}✗{ANSI.RESET} Failed: {file}`)
			end
		end
	end

	return stats
end

--- Parses libGDX atlas file to extract icon positions and spritesheet assignments
local function parseAtlasFile(atlasPath: string): { [string]: { filename: string, x: number, y: number } }
	local atlasContent = fs.readFile(atlasPath)
	local iconData: { [string]: { filename: string, x: number, y: number } } = {}
	local currentSpritesheet: string? = nil
	local lastIconName: string? = nil

	for line in string.gmatch(atlasContent, "[^\r\n]+") do
		local isIndented = string.match(line, "^%s")
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string

		if not isIndented then
			if string.match(trimmed, "%.png$") then
				currentSpritesheet = trimmed
			elseif trimmed ~= "" and currentSpritesheet then
				lastIconName = trimmed
				iconData[trimmed] = {
					filename = currentSpritesheet,
					x = 0,
					y = 0,
				}
			end
		elseif string.match(trimmed, "^bounds:") and lastIconName then
			local x, y = string.match(trimmed, "bounds:%s*(%d+),%s*(%d+)")
			if x and y then
				local iconName = lastIconName :: string
				iconData[iconName].x = tonumber(x) :: number
				iconData[iconName].y = tonumber(y) :: number
			end
		end
	end

	return iconData
end

--═══════════════════════════════════════════════════════════
-- ROBLOX ASSET UPLOAD
--═══════════════════════════════════════════════════════════

--- Uploads a spritesheet to Roblox and returns the asset ID
local function uploadSpritesheetToRoblox(filepath: string, displayName: string, metadata: IconsetMetadata): string
	print(`  {ANSI.DIM}Uploading {filepath}...{ANSI.RESET}`)

	local description = `Iconset spreadsheet uploaded for use in Iconvault.\n`
		.. `Name: {metadata.name}\n`
		.. `Made by {metadata.author} and licensed under {metadata.license.name}.`

	local createResult = process.exec("rbxcloud", {
		"assets",
		"create",
		"--asset-type",
		"decal-png",
		"--display-name",
		displayName,
		"--description",
		description,
		"--creator-id",
		tostring(HOLDER_USER_ID),
		"--creator-type",
		"user",
		"--filepath",
		filepath,
		"--api-key",
		RBLX_API_KEY,
	})

	if not createResult.ok then
		error(`{ANSI.BG_RED} ERROR {ANSI.RESET} Failed to upload {filepath}:\n{createResult.stderr}`)
	end

	-- Extract operation ID from response
	local responseData = serde.decode("json", createResult.stdout)
	local operationPath = responseData.path or responseData.name or responseData.operation

	if not operationPath then
		error(`{ANSI.BG_RED} ERROR {ANSI.RESET} No operation path returned from upload`)
	end

	local operationId = string.match(operationPath, "operations/(.+)") :: string or operationPath

	print(`  {ANSI.DIM}Waiting for upload to complete...{ANSI.RESET}`)

	-- Poll for completion
	local maxAttempts = 60
	local attempts = 0
	local assetId: string? = nil

	while attempts < maxAttempts do
		task.wait(2.5)
		attempts += 1

		local statusResult = process.exec("rbxcloud", {
			"assets",
			"get-operation",
			"--operation-id",
			operationId,
			"--api-key",
			RBLX_API_KEY,
		})

		if not statusResult.ok then
			error(`{ANSI.BG_RED} ERROR {ANSI.RESET} Failed to check operation status:\n{statusResult.stderr}`)
		end

		local status = serde.decode("json", statusResult.stdout)

		if status.done then
			if status.error then
				error(`{ANSI.BG_RED} ERROR {ANSI.RESET} Asset upload failed:\n{serde.encode("json", status.error)}`)
			end

			assetId = status.response and status.response.assetId

			if not assetId then
				error(`{ANSI.BG_RED} ERROR {ANSI.RESET} No asset ID returned from completed operation`)
			end

			print(`  {ANSI.GREEN}✓{ANSI.RESET} Uploaded as asset ID: {ANSI.BOLD}{assetId}{ANSI.RESET}`)
			break
		end
	end

	if not assetId then
		error(`{ANSI.BG_RED} ERROR {ANSI.RESET} Upload timed out after {maxAttempts * 2.5} seconds`)
	end

	return tostring(assetId)
end

--- Uploads all spritesheets for processed iconsets and returns filename -> assetId mapping
local function uploadAllSpritesheets(
	iconsetNames: { string },
	iconsetData: { [string]: IconsetMetadata }
): { [string]: string }
	print(`\n{ANSI.CYAN}{ANSI.BOLD}▸ Uploading Spritesheets to Roblox{ANSI.RESET}`)

	local assetIdMap: { [string]: string } = {}

	for _, iconsetName in iconsetNames do
		local spritesheetDir = `spritesheets/{iconsetName}`

		if not fs.isDir(spritesheetDir) then
			print(`  {ANSI.YELLOW}⚠{ANSI.RESET} Skipping {iconsetName} (no spritesheet directory found)`)
			continue
		end

		for _, file in fs.readDir(spritesheetDir) do
			if string.match(file, "%.png$") then
				local filepath = `{spritesheetDir}/{file}`
				local filenameWithoutExt = string.match(file, "^(.+)%.png$") or file
				local displayName = `{filenameWithoutExt}_{START_TIMESTAMP}`

				print(`{ANSI.BOLD}{file}{ANSI.RESET}`)

				local metadata = iconsetData[iconsetName]
				if not metadata then
					error(`{ANSI.BG_RED} ERROR {ANSI.RESET} No metadata found for {iconsetName}`)
				end

				local success, assetId = pcall(uploadSpritesheetToRoblox, filepath, displayName, metadata)

				if not success then
					error(`{ANSI.BG_RED} ERROR {ANSI.RESET} Upload failed for {file}:\n{assetId}`)
				end

				assetIdMap[file] = assetId
			end
		end
	end

	local totalUploaded = countKeys(assetIdMap)
	print(`\n{ANSI.GREEN}✓{ANSI.RESET} Uploaded {ANSI.BOLD}{totalUploaded}{ANSI.RESET} spritesheet(s) successfully\n`)

	return assetIdMap
end

--═══════════════════════════════════════════════════════════
-- ICONSET PROCESSING
--═══════════════════════════════════════════════════════════

--- Fetches iconset from Iconify and processes all icons
local function processIconset(
	iconsetName: string,
	existingMetadata: { [string]: IconsetMetadata }?
): (IconsetMetadata?, boolean)
	print(`\n{ANSI.BOLD}{ANSI.BLUE}▸ Processing:{ANSI.RESET} {ANSI.CYAN}{ANSI.BOLD}{iconsetName}{ANSI.RESET}`)

	local data, info, allIcons, metadata

	-- Step 1: Fetch icon data from Iconify
	if config.conditions.fetchIconData then
		local url = string.format(ICONSET_BASE_URL, iconsetName)
		data = fetchJson(url)

		-- Check if this iconset needs updating
		if existingMetadata and existingMetadata[iconsetName] then
			local existing = existingMetadata[iconsetName]
			local remoteLastModified = data.lastModified or 0

			if type(remoteLastModified) == "number" and existing.lastUpdated == remoteLastModified then
				print(`  {ANSI.YELLOW}⚠{ANSI.RESET} Iconset is up-to-date (last modified: {remoteLastModified})`)
				print(`  {ANSI.DIM}Skipping processing...{ANSI.RESET}`)
				return nil, true
			end
		end

		info = data.info

		print(`\n{ANSI.YELLOW}★ {ANSI.BOLD}Iconset Details{ANSI.RESET}`)
		print(`  Name:    {ANSI.BOLD}{info.name}{ANSI.RESET}`)
		print(`  Author:  {info.author.name}`)
		print(`  License: {info.license.title} {ANSI.DIM}({info.license.spdx}){ANSI.RESET}`)
		print(`  Icons:   {ANSI.BOLD}{info.total}{ANSI.RESET}`)

		-- Extract root-level defaults for icon dimensions
		local rootDefaults = {
			width = data.width,
			height = data.height,
			left = data.left,
			top = data.top,
		}

		-- Process all icons and aliases into a unified table
		allIcons = {}

		if data.icons then
			for name, iconData in pairs(data.icons) do
				allIcons[name] = resolveIconDefaults(iconData, rootDefaults)
			end
		end

		if data.aliases then
			for aliasName, aliasData in pairs(data.aliases) do
				local resolved = resolveAlias(aliasName, aliasData, data.icons, rootDefaults)
				if resolved then
					allIcons[aliasName] = resolved
				end
			end
		end
	else
		print(`  {ANSI.YELLOW}⚠{ANSI.RESET} Skipped fetching icon data (disabled)`)
		allIcons = {}
		info = {
			name = iconsetName,
			total = 0,
			author = { name = "Unknown" },
			license = { title = "Unknown", spdx = "Unknown" },
			samples = {},
		}
		data = { lastModified = 0 }
	end

	ensureDirectories(iconsetName)

	-- Step 2: Generate SVG files for all icons
	if config.conditions.generateSVG and config.conditions.fetchIconData then
		print(`\n{ANSI.CYAN}▸ {ANSI.BOLD}Generating SVG Files{ANSI.RESET}`)
		for iconName, iconData in pairs(allIcons) do
			local svgContent = generateSVG(iconData, config.defaultColor)
			writeSVGFile(iconsetName, iconName, svgContent)
		end
		local svgCount = countKeys(allIcons)
		print(`  {ANSI.GREEN}✓{ANSI.RESET} Generated {ANSI.BOLD}{svgCount}{ANSI.RESET} SVG files`)
	elseif not config.conditions.generateSVG then
		print(`\n{ANSI.YELLOW}⚠{ANSI.RESET} Skipped SVG generation (disabled)`)
	end

	-- Step 3: Convert SVG to PNG
	if config.conditions.convertToPNG and config.conditions.generateSVG then
		print(`\n{ANSI.CYAN}▸ {ANSI.BOLD}Converting to PNG{ANSI.RESET}`)
		print(`  {ANSI.DIM}Resolution: {config.iconRes}x{config.iconRes}px{ANSI.RESET}`)

		local pngCount = 0
		local pngFailedCount = 0

		for iconName in pairs(allIcons) do
			if convertSVGtoPNG(iconsetName, iconName, config.iconRes) then
				pngCount += 1
			else
				pngFailedCount += 1
			end
		end

		local svgCount = countKeys(allIcons)
		if pngFailedCount > 0 then
			print(
				`  {ANSI.YELLOW}⚠{ANSI.RESET} Converted {ANSI.BOLD}{pngCount}/{svgCount}{ANSI.RESET} {ANSI.RED}({pngFailedCount} failed){ANSI.RESET}`
			)
		else
			print(`  {ANSI.GREEN}✓{ANSI.RESET} Converted all {ANSI.BOLD}{pngCount}{ANSI.RESET} files`)
		end

		-- Clean up SVG files after conversion
		if fs.isDir(`svg/{iconsetName}`) then
			fs.removeDir(`svg/{iconsetName}`)
			print(`  {ANSI.DIM}🗑️  Cleaned up SVG files{ANSI.RESET}`)
		end
	elseif not config.conditions.convertToPNG then
		print(`\n{ANSI.YELLOW}⚠{ANSI.RESET} Skipped PNG conversion (disabled)`)
	end

	-- Build metadata structure
	local lastModified = data.lastModified or 0
	if type(lastModified) ~= "number" then
		lastModified = 0
	end

	metadata = {
		name = info.name,
		iconCount = info.total,
		author = info.author.name,
		license = {
			name = info.license.title,
			spdx = info.license.spdx,
		},
		samples = info.samples,
		lastRefreshed = START_TIMESTAMP,
		lastUpdated = lastModified,
		icons = {},
	}

	return metadata, false
end

--- Processes multiple iconsets and generates sprite atlases
local function processAllIconsets(
	iconsetNames: { string },
	existingMetadata: { [string]: IconsetMetadata }?
): { [string]: IconsetMetadata }
	local results = {}

	for i, iconsetName in iconsetNames do
		print(`\n{ANSI.DIM}[{i}/{#iconsetNames}]{ANSI.RESET}`)

		local success, metadata, skipped = pcall(processIconset, iconsetName, existingMetadata)

		if not success then
			print(`{ANSI.RED}✗{ANSI.RESET} Failed: {iconsetName}`)
			print(`  {ANSI.DIM}{metadata}{ANSI.RESET}\n`)
			continue
		end

		-- If iconset was skipped (up-to-date), preserve existing metadata
		if skipped then
			if existingMetadata and existingMetadata[iconsetName] then
				results[iconsetName] = existingMetadata[iconsetName]
			end
			continue
		end

		if not metadata then
			print(`{ANSI.RED}✗{ANSI.RESET} Failed: {iconsetName} (no metadata returned)`)
			continue
		end

		local iconsetMetadata = metadata :: IconsetMetadata

		-- Pack sprites into atlas
		if config.conditions.packSprites then
			if not packIconsetSprites(iconsetName) then
				print(`  {ANSI.RED}✗{ANSI.RESET} Packing failed`)
				continue
			end

			-- Clean up PNG files after packing
			if fs.isDir(`png/{iconsetName}`) then
				fs.removeDir(`png/{iconsetName}`)
				print(`  {ANSI.DIM}🗑️  Cleaned up PNG files{ANSI.RESET}`)
			end
		else
			print(`\n{ANSI.YELLOW}⚠{ANSI.RESET} Skipped sprite packing (disabled)`)
		end

		-- Apply alpha-bleeding
		if config.conditions.alphaBleed then
			alphaBleedSpritesheets(iconsetName)
		else
			print(`\n{ANSI.YELLOW}⚠{ANSI.RESET} Skipped alpha-bleeding (disabled)`)
		end

		-- Compress spritesheets
		if config.conditions.compressImages then
			local stats = compressSpritesheets(iconsetName)

			if stats.failed > 0 then
				print(
					`  {ANSI.YELLOW}⚠{ANSI.RESET} Optimized {ANSI.BOLD}{stats.compressed}{ANSI.RESET} {ANSI.RED}({stats.failed} failed){ANSI.RESET}`
				)
			else
				local totalKB = math.floor(stats.totalSaved / 1024 * 10 + 0.5) / 10
				print(`  {ANSI.GREEN}✓{ANSI.RESET} Saved {ANSI.BOLD}{totalKB} KB{ANSI.RESET} total`)
			end
		else
			print(`\n{ANSI.YELLOW}⚠{ANSI.RESET} Skipped image compression (disabled)`)
		end

		results[iconsetName] = iconsetMetadata
		print(`\n{ANSI.GREEN}{ANSI.BOLD}✓ {iconsetMetadata.name} processed!{ANSI.RESET}\n`)
	end

	return results
end

--═══════════════════════════════════════════════════════════
-- METADATA FINALIZATION
--═══════════════════════════════════════════════════════════

--- Finalizes metadata by parsing atlas files and associating icons with asset IDs
local function finalizeMetadata(
	processedIconsets: { string },
	iconsetData: { [string]: IconsetMetadata },
	spritesheetAssetIds: { [string]: string }
)
	print(`\n{ANSI.CYAN}{ANSI.BOLD}▸ Finalizing Metadata{ANSI.RESET}\n`)

	for _, iconsetName in processedIconsets do
		local metadata = iconsetData[iconsetName]
		local atlasPath = `spritesheets/{iconsetName}/{iconsetName}.atlas`

		if not fs.isFile(atlasPath) then
			print(`  {ANSI.YELLOW}⚠{ANSI.RESET} Atlas file not found for {iconsetName}`)
			continue
		end

		print(`{ANSI.BOLD}{iconsetName}{ANSI.RESET}`)
		local atlasData = parseAtlasFile(atlasPath)

		local updatedCount = 0

		for iconName, iconInfo in atlasData do
			local spritesheetFilename = iconInfo.filename
			local decalNumber: string

			if config.conditions.uploadToRoblox then
				local assetId = spritesheetAssetIds[spritesheetFilename]
				if not assetId then
					print(`  {ANSI.YELLOW}⚠{ANSI.RESET} No asset ID found for {spritesheetFilename}`)
					continue
				end
				decalNumber = assetId
			else
				-- Use filename as placeholder when not uploading
				decalNumber = spritesheetFilename
			end

			-- Initialize decal entry if it doesn't exist
			if not metadata.icons[decalNumber] then
				metadata.icons[decalNumber] = {}
			end

			-- Add icon position data
			metadata.icons[decalNumber][iconName] = {
				x = iconInfo.x,
				y = iconInfo.y,
			}

			updatedCount += 1
		end

		print(`  {ANSI.GREEN}✓{ANSI.RESET} Mapped {ANSI.BOLD}{updatedCount}{ANSI.RESET} icons`)
	end
end

--- Cleans up intermediate files after processing
local function cleanupIntermediateFiles(processedIconsets: { string })
	print(`\n{ANSI.CYAN}▸ {ANSI.BOLD}Cleaning Up{ANSI.RESET}`)

	for _, iconsetName in processedIconsets do
		if fs.isDir(`spritesheets/{iconsetName}`) then
			fs.removeDir(`spritesheets/{iconsetName}`)
		end
	end

	-- Remove empty parent directories
	for _, dir in { "svg", "png", "spritesheets" } do
		if fs.isDir(dir) and #fs.readDir(dir) == 0 then
			fs.removeDir(dir)
		end
	end

	print(`  {ANSI.GREEN}✓{ANSI.RESET} Removed all intermediate files`)
end

--═══════════════════════════════════════════════════════════
-- MAIN ENTRY POINT
--═══════════════════════════════════════════════════════════

local function main()
	local divider = string.rep("═", 48)

	print(`{ANSI.DIM}{divider}{ANSI.RESET}`)
	print(`{ANSI.BOLD}{ANSI.PINK}🌠 ASTRALIS{ANSI.RESET}`)
	print(
		`{ANSI.DIM}Automates converting icon sets from Iconify into PNG spreadsheets for use in Iconvault.{ANSI.RESET}`
	)
	print(`{ANSI.DIM}{divider}{ANSI.RESET}`)

	-- Validate configuration and API key
	validateConfig(config)

	if config.conditions.uploadToRoblox then
		validateApiKey()
		print(`{ANSI.GREEN}✓{ANSI.RESET} API key detected`)
	end

	print(`{ANSI.GREEN}✓{ANSI.RESET} Configuration validated`)

	-- Load existing metadata
	local existingMetadata = loadExistingMetadata()
	if existingMetadata then
		local existingCount = countKeys(existingMetadata)
		print(`{ANSI.CYAN}ℹ{ANSI.RESET} Loaded existing metadata ({ANSI.BOLD}{existingCount}{ANSI.RESET} iconset(s))`)
	end

	-- Display queued iconsets
	print(`\n{ANSI.BOLD}Queued Iconsets{ANSI.RESET} {ANSI.DIM}({#config.iconsets} total){ANSI.RESET}`)
	for i, iconset in config.iconsets do
		print(`  {ANSI.DIM}{i}.{ANSI.RESET} {iconset}`)
	end

	-- Process all iconsets
	local iconsetData = processAllIconsets(config.iconsets, existingMetadata)

	-- Merge with existing metadata to preserve skipped iconsets
	if existingMetadata then
		for iconsetName, metadata in existingMetadata do
			if not iconsetData[iconsetName] then
				iconsetData[iconsetName] = metadata
			end
		end
	end

	-- Get list of newly processed iconsets (not skipped)
	local processedIconsets = {}
	for iconsetName, metadata in iconsetData do
		if metadata.lastRefreshed == START_TIMESTAMP then
			table.insert(processedIconsets, iconsetName)
		end
	end

	-- Upload spritesheets
	local spritesheetAssetIds = {}
	if config.conditions.uploadToRoblox and #processedIconsets > 0 then
		spritesheetAssetIds = uploadAllSpritesheets(processedIconsets, iconsetData)
	elseif #processedIconsets == 0 then
		print(`\n{ANSI.YELLOW}⚠{ANSI.RESET} No new iconsets to upload (all up-to-date)`)
	else
		print(`\n{ANSI.YELLOW}⚠{ANSI.RESET} Skipped Roblox upload (disabled)`)
	end

	-- Finalize metadata
	if config.conditions.generateMetadata and #processedIconsets > 0 then
		finalizeMetadata(processedIconsets, iconsetData, spritesheetAssetIds)

		-- Clean up intermediate files
		if config.conditions.uploadToRoblox then
			cleanupIntermediateFiles(processedIconsets)
		end
	else
		print(`\n{ANSI.YELLOW}⚠{ANSI.RESET} Skipped metadata generation (disabled or no new iconsets)`)
	end

	-- Display final summary
	print(`\n{ANSI.DIM}{divider}{ANSI.RESET}`)

	local totalIconsets = countKeys(iconsetData)
	local processedCount = #processedIconsets
	local skippedCount = #config.iconsets - processedCount

	if processedCount == #config.iconsets then
		print(
			`{ANSI.BG_GREEN}{ANSI.BOLD} ✓ SUCCESS {ANSI.RESET} {ANSI.GREEN}Processed all {ANSI.BOLD}{processedCount}{ANSI.RESET} {ANSI.GREEN}iconsets{ANSI.RESET}`
		)
	elseif processedCount > 0 then
		print(
			`{ANSI.BG_GREEN}{ANSI.BOLD} ✓ SUCCESS {ANSI.RESET} {ANSI.GREEN}Processed {ANSI.BOLD}{processedCount}{ANSI.RESET} {ANSI.GREEN}iconset(s){ANSI.RESET}`
		)
		print(`{ANSI.CYAN}ℹ{ANSI.RESET} Skipped {ANSI.BOLD}{skippedCount}{ANSI.RESET} up-to-date iconset(s)`)
	else
		print(`{ANSI.BG_YELLOW}{ANSI.BOLD} ⚠ UP-TO-DATE {ANSI.RESET} {ANSI.YELLOW}All iconsets are current{ANSI.RESET}`)
	end

	-- Save metadata to JSON
	if totalIconsets > 0 and config.conditions.generateMetadata then
		fs.writeFile("icons.json", serde.encode("json", iconsetData))
		print(
			`{ANSI.GREEN}✓{ANSI.RESET} Saved metadata to {ANSI.BOLD}icons.json{ANSI.RESET} ({ANSI.BOLD}{totalIconsets}{ANSI.RESET} total iconset(s))`
		)
	end

	print(`{ANSI.DIM}{divider}{ANSI.RESET}\n`)
end

main()