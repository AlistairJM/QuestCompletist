--[[
Checks the addon's saved settings and its options panel: the defaults a fresh or an old install gets, the
boxes the panel builds and what a click on one of them saves and redraws, and where the panel's lowest
control ends, since the panel is a fixed canvas that doesn't scroll.

Loads the addon's own files with stand-ins for the WoW API, and gives the frames the panel makes a
stand-in that keeps their anchors and heights, so the layout can be worked out the way the game would
place it. The heights are those of the game's fonts and of its check button template; the check is of
the vertical room, and widths aren't judged. Whether the panel really looks right, in the longest
language, is the look in game that docs/plans/open-items.md lists.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-Settings.lua
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-Settings.lua QuestCompletist QuestCompletist_Camelot.toc
Prints each check and exits with 1 if one fails. Run it for both games' TOCs.
]]

local ADDON_DIR = arg and arg[1] or "QuestCompletist"
local TOC_FILE = arg and arg[2] or "QuestCompletist.toc"

-- The canvas the game gives an addon's options page: Blizzard's settings window is 724 tall, and the page
-- sits between its category list's top and bottom (docs/plans/continent-pins.md, "The option").
local CANVAS_HEIGHT = 601
local MARGIN = 20
local HEIGHTS = {GameFontNormalLarge = 16, GameFontNormal = 14, GameFontNormalSmall = 12, GameFontHighlightSmall = 12, check = 26}

--[[ Lua 5.1 has no bit library; WoW's masks here are all non-negative and under 2^32. ]]--
local function bitop(a, b, both)
	local result, place = 0, 1
	while a > 0 or b > 0 do
		local x, y = a % 2, b % 2
		if (both and x == 1 and y == 1) or (not both and (x == 1 or y == 1)) then
			result = result + place
		end
		a, b, place = (a - x) / 2, (b - y) / 2, place * 2
	end
	return result
end
local bit = {
	band = function(a, b) return bitop(a, b, true) end,
	bor = function(a, b) return bitop(a, b, false) end,
}

local dummy
dummy = setmetatable({}, {
	__index = function() return dummy end,
	__call = function() return dummy end,
	__newindex = function() end,
	__concat = function() return "" end,
})
local function stubTable(t)
	return setmetatable(t, {__index = function() return dummy end})
end

local function readFile(path)
	local handle = assert(io.open(path, "rb"))
	local text = handle:read("*a")
	handle:close()
	return text
end

local env

--[[ Frames that keep their anchors and heights ]]--
local newFrame
local allFrames = {}
local function addMethods(frame)
	function frame:SetPoint(point, a, b, c, d)
		local rel, relPoint, x, y
		if type(a) == "table" then
			if type(b) == "string" then rel, relPoint, x, y = a, b, c or 0, d or 0 else rel, relPoint, x, y = a, point, b or 0, c or 0 end
		else
			rel, relPoint, x, y = nil, point, a or 0, b or 0
		end
		self.points[#self.points + 1] = {point = point, rel = rel, relPoint = relPoint, x = x, y = y}
	end
	function frame:SetHeight(height) self.height = height end
	function frame:GetName() return self.name end
	function frame:SetScript(script, fn) self.scripts[script] = fn end
	function frame:SetChecked(value) self.checked = value and true or false end
	function frame:GetChecked() return self.checked end
	function frame:SetText(text) self.text = text end
	function frame:GetStringWidth() return #(self.text or "") * 6 end
	function frame:CreateFontString(name, _, template)
		local fontString = newFrame("FontString", name, self)
		fontString.height = HEIGHTS[template] or 12
		return fontString
	end
	return frame
end
newFrame = function(kind, name, parent, template)
	local frame = {kind = kind, name = name, parent = parent, template = template, points = {}, scripts = {}, height = 0, checked = false}
	if kind == "CheckButton" then frame.height = HEIGHTS.check end
	addMethods(frame)
	allFrames[#allFrames + 1] = frame
	setmetatable(frame, {__index = function() return function() end end})
	if name then
		env[name] = frame
		if kind == "CheckButton" then env[name .. "Text"] = newFrame("FontString", name .. "Text", frame) end
	end
	return frame
end

-- Where a frame's top edge is, from the anchors it was given: 0 is the top of the page.
local panel
local function bottomOf(frame) return nil end
local function topOf(frame)
	local anchor
	for _, p in ipairs(frame.points) do
		if p.point:find("TOP", 1, true) then anchor = p break end
	end
	anchor = anchor or frame.points[1]
	if not anchor then return nil end
	local relTop = 0
	local rel = anchor.rel
	local relY
	if not rel or rel == panel then
		relY = 0
		if anchor.relPoint:find("BOTTOM", 1, true) then relY = -CANVAS_HEIGHT end
	else
		local relTopY = topOf(rel)
		if not relTopY then return nil end
		if anchor.relPoint:find("BOTTOM", 1, true) then
			relY = relTopY - rel.height
		elseif anchor.relPoint:find("TOP", 1, true) then
			relY = relTopY
		else
			relY = relTopY - rel.height / 2
		end
	end
	local y = relY + anchor.y
	if anchor.point:find("BOTTOM", 1, true) then return y + frame.height end
	if anchor.point:find("TOP", 1, true) then return y end
	return y + frame.height / 2
end

local state = {settings = {}, refreshed = {zone = 0, continent = 0}, tooltip = {}}
env = {
	bit = bit,
	print = function() end,
	GetLocale = function() return "enUS" end,
	GetText = function(key) return key end,
	wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
	tinsert = table.insert, tremove = table.remove,
	strupper = string.upper, strlower = string.lower, strfind = string.find, strsub = string.sub,
	strlen = string.len, format = string.format, strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
	floor = math.floor, ceil = math.ceil, max = math.max, min = math.min, abs = math.abs,
	date = os.date, time = os.time,
	CreateFromMixins = function() return {} end,
	CreateFrame = function(kind, name, parent, template) return newFrame(kind, name, parent, template) end,
	Settings = {RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end},
	WORLD_MAP = "Map",
	GameTooltip = {
		SetOwner = function() end,
		SetText = function(_, text) state.tooltip.text = text end,
		Show = function() state.tooltip.shown = true end,
	},
	GameTooltip_Hide = function() state.tooltip.shown = false end,
	qcQuestCompletistUI = {IsVisible = function() return false end},
	qcMenuSlider = {GetValue = function() return 1 end},
	WorldMapFrame = {HookScript = function() end, AddDataProvider = function() end, IsShown = function() return true end},
	IsInInstance = function() return false end,
	C_AddOns = {IsAddOnLoaded = function() return false end},
	UnitFactionGroup = function() return "Alliance", "Alliance" end,
	UnitRace = function() return "NightElf", "NightElf" end,
	UnitClass = function() return "DRUID", "DRUID" end,
	UnitLevel = function() return 1000 end,
	C_Map = stubTable({GetMapInfo = function() return {mapType = 3} end}),
	Enum = {UIMapType = {Continent = 2, Zone = 3}},
	C_QuestLog = stubTable({}),
	C_Covenants = stubTable({GetActiveCovenantID = function() return 0 end}),
}
env._G = env
setmetatable(env, {__index = function(_, key)
	local value = _G[key]
	if value ~= nil then return value end
	return dummy
end})
panel = newFrame("Frame", "qcInterfaceOptions")

local QC = {}
for line in readFile(ADDON_DIR .. "/" .. TOC_FILE):gmatch("[^\r\n]+") do
	local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
	if file and file:sub(1, 4) ~= "Libs" then
		local chunk = assert(loadstring(readFile(ADDON_DIR .. "/" .. file), "@" .. ADDON_DIR .. "/" .. file))
		setfenv(chunk, env)
		chunk("QuestCompletist", QC)
	end
end

-- The two kinds of pin's providers count their redraws.
env.qcMapDataProvider.RefreshAllData = function() state.refreshed.zone = state.refreshed.zone + 1 end
env.qcContinentDataProvider.RefreshAllData = function() state.refreshed.continent = state.refreshed.continent + 1 end

local failures = 0
local function check(label, passed, detail)
	if not passed then failures = failures + 1 end
	print(string.format("  [%s] %s%s", passed and "ok" or "FAIL", label, detail and (" (" .. detail .. ")") or ""))
end

print("Defaults")
env.qcSettings = {}
env.qcCheckSettings()
check("a fresh install shows the zone icons on continent maps", env.qcSettings.QC_M_SHOW_CONTINENT == 1)
check("and the map icons", env.qcSettings.QC_M_SHOW_ICONS == 1)
check("the settings are at version 2, as they were", env.qcSettings.QC_SETTINGS_VERSION == 2)
env.qcSettings = {QC_SETTINGS_VERSION = 2, QC_M_SHOW_CONTINENT = 0}
env.qcCheckSettings()
check("a continent setting of 0 is kept", env.qcSettings.QC_M_SHOW_CONTINENT == 0)
env.qcSettings = {QC_SETTINGS_VERSION = 2, QC_M_SHOW_ICONS = 0}
env.qcCheckSettings()
check("an install that had the map icons off gets the continent icons on: the setting is its own", env.qcSettings.QC_M_SHOW_CONTINENT == 1 and env.qcSettings.QC_M_SHOW_ICONS == 0)
env.qcSettings = {QC_ML_HIDE_FACTION = 1}
env.qcCheckSettings()
check("a setting from before the map and the list had their own moves across as it did", env.qcSettings.QC_M_HIDE_FACTION == 1 and env.qcSettings.QC_L_HIDE_FACTION == 1 and env.qcSettings.QC_SETTINGS_VERSION == 2)
check("without turning the continent icons off", env.qcSettings.QC_M_SHOW_CONTINENT == 1)
check("the setting's name is not one of the hide filters", ("QC_M_SHOW_CONTINENT"):find("HIDE", 1, true) == nil)

print("The panel")
env.qcSettings = {}
env.qcCheckSettings()
env.qcInterfaceOptions_OnShow(panel)
local icons, continent, minimap, recorder = env.qcIO_M_SHOW_ICONS, env.qcIO_M_SHOW_CONTINENT, env.qcIO_MINIMAP_SHOW, env.qcIO_RECORD_GIVERS
check("the page has the map icons box and the continent box", icons ~= nil and continent ~= nil)
check("and the minimap and recorder boxes", minimap ~= nil and recorder ~= nil)
check("the continent box's label is its text", env.qcIO_M_SHOW_CONTINENTText.text == env.qcLocalize.SHOWCONTINENTICONS)
check("which says what it is, in English", env.qcLocalize.SHOWCONTINENTICONS == "Show Zone Icons on Continent Maps")
check("it sits under the map icons box, indented", continent.points[1].rel == icons and continent.points[1].relPoint == "BOTTOMLEFT" and continent.points[1].x == 16)
local firstLabelAnchor
for _, child in ipairs(allFrames) do
	if child.kind == "FontString" and child.points[1] and child.points[1].rel == continent then firstLabelAnchor = child end
end
check("the filter grid starts under the continent box", firstLabelAnchor ~= nil)
env.qcApplySettings()
check("the boxes show the settings: both ticked", icons.checked and continent.checked)
env.qcSettings.QC_M_SHOW_CONTINENT = 0
env.qcApplySettings()
check("a continent setting of 0 unticks its box", not continent.checked and icons.checked)
env.qcSettings.QC_M_SHOW_CONTINENT = 1

print("A click")
state.refreshed = {zone = 0, continent = 0}
continent.checked = false
continent.scripts.OnClick(continent)
check("unticking saves 0", env.qcSettings.QC_M_SHOW_CONTINENT == 0)
check("and redraws both kinds of pin once", state.refreshed.zone == 1 and state.refreshed.continent == 1, state.refreshed.zone .. " and " .. state.refreshed.continent)
continent.checked = true
continent.scripts.OnClick(continent)
check("ticking saves 1", env.qcSettings.QC_M_SHOW_CONTINENT == 1)
check("and the map icons box still saves its own setting", (function() icons.checked = false; icons.scripts.OnClick(icons); return env.qcSettings.QC_M_SHOW_ICONS == 0 end)())
icons.checked = true
icons.scripts.OnClick(icons)
check("and redraws both kinds of pin too", state.refreshed.continent == 4, tostring(state.refreshed.continent))
continent.scripts.OnEnter(continent)
check("hovering the box shows its tip", state.tooltip.text == env.qcLocalize.SHOWCONTINENTICONSTIP and state.tooltip.shown == true)
check("which says daily, weekly and repeatable quests aren't counted", state.tooltip.text:find("Daily, weekly and repeatable", 1, true) ~= nil)
check("leaving hides it again", continent.scripts.OnLeave == env.GameTooltip_Hide)

print("The page's lowest control")
local lowest, lowestName = 0, nil
for name, frame in pairs(env) do
	if type(name) == "string" and type(frame) == "table" and frame.points and frame.kind == "CheckButton" then
		local top = topOf(frame)
		if top then
			local bottom = top - frame.height
			if bottom < lowest then lowest, lowestName = bottom, name end
		end
	end
end
check("the recorder box is the lowest", lowestName == "qcIO_RECORD_GIVERS", tostring(lowestName))
local spare = CANVAS_HEIGHT + lowest
check(string.format("it ends %d px from the top of a %d px page, %d px to spare", -lowest, CANVAS_HEIGHT, spare), spare >= MARGIN)
check("the continent box follows the map icons box closely", topOf(continent) == topOf(icons) - icons.height - 2)

print(failures == 0 and "All checks passed." or (failures .. " checks failed."))
os.exit(failures == 0 and 0 or 1)
