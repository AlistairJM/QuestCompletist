--[[
Checks the map's tooltip: what a quest giver's pin draws on it when the mouse enters, how it is cleared
when the mouse leaves, and how it is redrawn when names arrive or Shift changes. It also clicks pins and
quests in the list, with TomTom and without, and checks which waypoint they set and where the game's own
is refused.

Loads the addon's own files with stand-ins for the WoW API, and gives the tooltip, its lines, its bars,
dividers and icons stand-ins that write down every call they get. The checks read that record, and
with a third argument it is written to a file, so one run of the code before a change and one after
can be compared line by line.

The pins hovered are the first ones in the data that give two givers with quests in each state: done,
in the log, and still to do.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-MapTooltip.lua
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-MapTooltip.lua QuestCompletist QuestCompletist_Camelot.toc record.txt
Prints each check and exits with 1 if one fails. Run it for both games' TOCs.
]]

local ADDON_DIR = arg and arg[1] or "QuestCompletist"
local TOC_FILE = arg and arg[2] or "QuestCompletist.toc"
local RECORD_FILE = arg and arg[3]

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

--[[ The record of every call the tooltip and what hangs on it get ]]--
local record = {}
local function put(text) record[#record + 1] = text end

local function show(value)
	if type(value) == "table" then return rawget(value, "__name") or "table" end
	return tostring(value)
end

local function joined(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = show((select(i, ...))) end
	return table.concat(parts, ",")
end

local counters = {}
-- Any method is written down; a method that makes something (CreateTexture, CreateMaskTexture) hands
-- back another such object.
local function newRecorder(kind)
	counters[kind] = (counters[kind] or 0) + 1
	local name = kind .. counters[kind]
	return setmetatable({__name = name}, {__index = function(_, method)
		if not method:match("^%u") then return nil end
		return function(_, ...)
			put(string.format("%s:%s(%s)", name, method, joined(...)))
			if method:sub(1, 6) == "Create" then return newRecorder(method:sub(7):lower()) end
		end
	end})
end

local env
local function newTooltip(name)
	local tooltip = newRecorder("tooltip")
	tooltip.lines, tooltip.shown = 0, false
	local function addLine(self)
		self.lines = self.lines + 1
		for _, side in ipairs({"Left", "Right"}) do
			local key = name .. "Text" .. side .. self.lines
			if rawget(env, key) == nil then env[key] = newRecorder(side:lower()) end
		end
	end
	tooltip.AddLine = function(self, text, _, _, _, wrap)
		put(string.format("%s:AddLine(%s,%s)", self.__name, tostring(text), tostring(wrap)))
		addLine(self)
	end
	tooltip.AddDoubleLine = function(self, left, right)
		put(string.format("%s:AddDoubleLine(%s,%s)", self.__name, tostring(left), tostring(right)))
		addLine(self)
	end
	tooltip.ClearLines = function(self) put(self.__name .. ":ClearLines()"); self.lines = 0 end
	tooltip.NumLines = function(self) return self.lines end
	tooltip.Show = function(self) put(self.__name .. ":Show()"); self.shown = true end
	tooltip.Hide = function(self) put(self.__name .. ":Hide()"); self.shown = false end
	tooltip.IsShown = function(self) return self.shown end
	return tooltip
end

local function newPin(pinData, x, y)
	local pin = {__name = "pin" .. (counters.pin or 0) + 1, PinData = pinData}
	counters.pin = (counters.pin or 0) + 1
	pin.GetCenter = function() return x or 100, y or 100 end
	pin.GetMap = function() return {GetMapID = function() return 84 end} end
	return setmetatable(pin, {__index = function(_, key) return env.qcPinMixin[key] end})
end

--[[ Load the addon in TOC order ]]--
local ctx = {frames = {}, hooks = {}, scale = 2, shift = false, level = 1000, inLog = {}, logComplete = {}}
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
	CreateFrame = function(kind, name)
		if kind == "GameTooltip" then
			local tooltip = newTooltip(name)
			put(string.format("CreateFrame(GameTooltip,%s)", name))
			env[name] = tooltip
			return tooltip
		end
		local frame = newRecorder(kind:lower())
		frame.events, frame.scripts = {}, {}
		frame.RegisterEvent = function(self, event) self.events[event] = true end
		frame.SetScript = function(self, script, fn) self.scripts[script] = fn end
		ctx.frames[#ctx.frames + 1] = frame
		return frame
	end,
	UIParent = newRecorder("uiparent"),
	WorldMapFrame = {
		__name = "worldmap",
		HookScript = function(_, script, fn) put("worldmap:HookScript(" .. script .. ")"); ctx.hooks[script] = fn end,
		GetCanvas = function() return {GetSize = function() return 1000, 700 end} end,
		GetScale = function() return ctx.scale end,
		AddDataProvider = function() end,
	},
	GameTooltipText = {__name = "GameTooltipText"},
	GameTooltipTextSmall = {__name = "GameTooltipTextSmall"},
	GameTooltipHeaderText = {__name = "GameTooltipHeaderText"},
	NORMAL_FONT_COLOR = {GetRGB = function() return 1, 0.82, 0 end},
	IsShiftKeyDown = function() return ctx.shift end,
	IsModifierKeyDown = function() return false end,
	IsInInstance = function() return false end,
	C_AddOns = {IsAddOnLoaded = function() return false end},
	UiMapPoint = {},
	UnitFactionGroup = function() return "Alliance", "Alliance" end,
	UnitRace = function() return "NightElf", "NightElf" end,
	UnitClass = function() return "DRUID", "DRUID" end,
	UnitLevel = function() return ctx.level end,
	UnitName = function() return "Tester" end,
	UnitQuestTrivialLevelRange = function() return 5 end,
	GetProfessions = function() return end,
	GetProfessionInfo = function() return end,
	ITEM_REQ_ALLIANCE = "Alliance", ITEM_REQ_HORDE = "Horde", ITEM_RACES_ALLOWED = "Races: %s",
	ITEM_CLASSES_ALLOWED = "Classes: %s", ITEM_MIN_LEVEL = "Requires Level %d", ITEM_REQ_SKILL = "Requires %s",
	ITEM_REQ_REPUTATION = "Requires %s - %s", ITEM_MIN_SKILL = "Requires %s (%d)", RENOWN_LEVEL_LABEL = "Renown %d",
	UNKNOWN = "Unknown",
	QUEST_WATCH_QUEST_READY = "Ready for turn-in", AVAILABLE_QUESTS = "Available Quests", IN_PROGRESS = "In Progress",
	UNAVAILABLE = "Unavailable", FLIGHT_MAP_CLICK_TO_ZOOM_IN = "<Click to Zoom In>",
	C_Covenants = stubTable({GetActiveCovenantID = function() return 0 end}),
	C_MajorFactions = stubTable({GetCurrentRenownLevel = function() return 1000 end}),
	C_SkillInfo = stubTable({GetSkillLineInfoByID = function() return {rank = 1000, modifier = 0} end}),
	C_QuestLog = stubTable({
		GetLogIndexForQuestID = function(questId) return ctx.inLog[questId] end,
		IsComplete = function(questId) return ctx.logComplete[questId] == true end,
		IsQuestFlaggedCompleted = function() return false end,
		IsQuestFlaggedCompletedOnAccount = function() return false end,
		GetTitleForQuestID = function() return nil end,
		RequestLoadQuestByID = function() end,
		IsWorldQuest = function() return false end,
	}),
	C_TaskQuest = stubTable({GetQuestInfoByQuestID = function() return nil end}),
	C_TooltipInfo = stubTable({GetHyperlink = function() return nil end}),
	C_DateAndTime = stubTable({GetCurrentCalendarTime = function() return {year = 2026, month = 10, monthDay = 9, hour = 14, minute = 30} end}),
}
env._G = env
setmetatable(env, {__index = function(_, key)
	local value = _G[key]
	if value ~= nil then return value end
	return dummy
end})

local QC = {}
for line in readFile(ADDON_DIR .. "/" .. TOC_FILE):gmatch("[^\r\n]+") do
	local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
	if file and file:sub(1, 4) ~= "Libs" then
		local chunk = assert(loadstring(readFile(ADDON_DIR .. "/" .. file), "@" .. ADDON_DIR .. "/" .. file))
		setfenv(chunk, env)
		chunk("QuestCompletist", QC)
	end
end

env.qcSettings = {}
env.qcCheckSettings()
for key in pairs(env.qcSettings) do
	if key:match("^QC_.*HIDE") then env.qcSettings[key] = 0 end
end
env.qcSettings.QC_M_SHOW_ICONS = 1
env.qcCharacterCompletions = {}

--[[ The pins: the first ones whose quests are all plain, one with three quests and one with another giver's ]]--
local QUESTS = env.qcQuestDatabase
local function plain(pin)
	if #pin[6] == 0 or not pin[3] or pin[2] == 0 then return false end
	for _, questId in ipairs(pin[6]) do
		local e = QUESTS[questId]
		if not e or bit.band(e[4], 2 + 4 + 128) ~= 0 then return false end
		if not (QC.qcMaskAllows(e[5], env.qcFactionBits.ALLIANCE) and QC.qcMaskAllows(e[6], env.qcRaceBits.NIGHTELF) and QC.qcMaskAllows(e[7], env.qcClassBits.DRUID)) then return false end
		if QC.qcPrereq.Parts(questId) or (env.qcRenownLevelRequirements or {})[questId] or (env.qcQuestSkillRequirements or {})[questId] then return false end
	end
	return true
end
local mapIds = {}
for mapId in pairs(env.qcPinDB) do mapIds[#mapIds + 1] = mapId end
table.sort(mapIds)
local pinA, pinB
for _, mapId in ipairs(mapIds) do
	for _, pin in ipairs(env.qcPinDB[mapId]) do
		if plain(pin) then
			if not pinA and #pin[6] >= 3 then
				pinA = pin
			elseif pinA and not pinB and pin[3] ~= pinA[3] and #pin[6] == 1 and ((env.qcQuestMinLevel or {})[pin[6][1]] or QUESTS[pin[6][1]][2] or 0) > 1 then
				local shared = false
				for _, a in ipairs(pinA[6]) do for _, b in ipairs(pin[6]) do if a == b then shared = true end end end
				if not shared then pinB = pin end
			end
		end
	end
end
assert(pinA and pinB, "no two plain pins in the data")

-- A's first two quests are done, its third is in the log; B's are all still to do.
env.qcCharacterCompletions[pinA[6][1]] = 1
env.qcCharacterCompletions[pinA[6][2]] = 1
ctx.inLog[pinA[6][3]] = 1

local stack = {pinA, pinB}
local quests = {}
for _, member in ipairs(stack) do for _, questId in ipairs(member[6]) do quests[#quests + 1] = questId end end
local stackData = {pinA[1], pinA[2], pinA[3], pinA[4], pinA[5], quests, stack = stack}
local singleData = {pinB[1], pinB[2], pinB[3], pinB[4], pinB[5], pinB[6]}

--[[ Checks ]]--
local failures = 0
local function check(label, passed, detail)
	if not passed then failures = failures + 1 end
	print(string.format("  [%s] %s%s", passed and "ok" or "FAIL", label, detail and (" (" .. detail .. ")") or ""))
end

local function count(pattern, from)
	local n = 0
	for i = from or 1, #record do
		if record[i]:find(pattern, 1, true) then n = n + 1 end
	end
	return n
end

local function shiftWatcher()
	for _, frame in ipairs(ctx.frames) do
		if frame.events.MODIFIER_STATE_CHANGED then return frame.scripts.OnEvent end
	end
end

print(string.format("Pins: %s with %d quests (%d done, 1 in the log), and %s with one quest to do", pinA[3], #pinA[6], 2, pinB[3]))
print("The tooltip is made once, and follows the map's scale")
record = {}
env.qcMapTooltipSetup()
local tooltip = env.qcMapTooltip
check("a game tooltip is named qcMapTooltip", tooltip ~= nil and record[1] == "CreateFrame(GameTooltip,qcMapTooltip)")
check("it sits on the tooltip strata", count(tooltip.__name .. ":SetFrameStrata(TOOLTIP)") == 1)
check("it hooks the map's size change", ctx.hooks.OnSizeChanged ~= nil)
ctx.hooks.OnSizeChanged(env.WorldMapFrame)
check("and takes the map's scale back, so it keeps its size", record[#record] == tooltip.__name .. ":SetScale(0.5)", record[#record])

print("A pin's tooltip is opened, filled and shown")
record = {}
local pin = newPin(stackData)
pin:OnMouseEnter()
check("it opens on the pin, to its right", record[1] == tooltip.__name .. ":SetOwner(" .. pin.__name .. ",ANCHOR_RIGHT)", record[1])
check("it clears its lines next", record[2] == tooltip.__name .. ":ClearLines()", record[2])
check("it ends by showing itself", record[#record] == tooltip.__name .. ":Show()", record[#record])
check("a giver's name heads its quests", count(":AddDoubleLine(" .. pinA[3] .. ",") == 1 and count(":AddDoubleLine(" .. pinB[3] .. ",") == 1)
check("a divider sits between the two givers", count("tooltip1:CreateTexture(nil,OVERLAY)") >= 1 and count(":SetHeight(1)") == 1)
check("the first giver's progress is drawn as a bar", count("statusbar1:SetMinMaxValues(0," .. #pinA[6] .. ")") == 1)
check("the bar says 2 are done", count("|cffc8c8c8" .. 2 .. "/" .. #pinA[6] .. "|r") == 1)
check("the bar widens the tooltip", count(":SetMinimumWidth(180)") == 1)
check("done quests fold into one line", count(":AddDoubleLine(    |cff7fbf7f") == 1)
check("each quest line has an icon beside it", count(":SetPoint(LEFT,") >= 3)
local firstHover = #record
local texturesAfterFirst = count("tooltip1:CreateTexture(")

print("Shift lists the done quests")
ctx.shift = true
record = {}
local watcher = shiftWatcher()
check("the watcher is registered", watcher ~= nil)
watcher(nil, "MODIFIER_STATE_CHANGED", "LCTRL")
check("another key redraws nothing", #record == 0, tostring(#record))
watcher(nil, "MODIFIER_STATE_CHANGED", "LSHIFT")
check("Shift redraws the tooltip of the pin under the mouse", record[1] == tooltip.__name .. ":SetOwner(" .. pin.__name .. ",ANCHOR_RIGHT)", record[1])
check("with the done quests listed one by one", count(":AddDoubleLine(    |cff7fbf7f") == 0 and count("|cff00ff00") >= 2)
check("and the first hover's lines and decorations reused", count("tooltip1:CreateTexture(") <= texturesAfterFirst)
ctx.shift = false

print("Names arriving redraw it, and leaving closes it")
record = {}
pin:OnMouseEnter()
local reused = #record
record = {}
QC.RedrawMapTooltip()
check("a redraw runs the pin's own tooltip again", #record == reused and reused > 0, tostring(#record) .. " calls against " .. tostring(reused))
check("and its lines come from what the first hover made", reused < firstHover, tostring(reused) .. " against " .. tostring(firstHover))
record = {}
pin:OnMouseLeave()
check("leaving hides the tooltip", record[1] == tooltip.__name .. ":Hide()", record[1])
check("and its bars, icons and dividers", count(":Hide()") >= 4, tostring(count(":Hide()")))
record = {}
QC.RedrawMapTooltip()
watcher(nil, "MODIFIER_STATE_CHANGED", "LSHIFT")
check("after that nothing is redrawn, by names or by Shift", #record == 0, tostring(#record))

print("A pin with no giver data draws nothing, and the anchor follows the corner")
record = {}
newPin(nil):OnMouseEnter()
check("a pin without data leaves the tooltip alone", #record == 0)
record = {}
newPin(singleData, 900, 100):OnMouseEnter()
check("a pin near the right edge opens to its left", record[1]:find(",ANCHOR_LEFT)", 1, true) ~= nil, record[1])
record = {}
newPin(singleData, 100, 600):OnMouseEnter()
check("a pin near the top opens below it", record[1]:find(",ANCHOR_BOTTOM)", 1, true) ~= nil, record[1])
check("a giver with a single quest draws no bar", count(":SetMinMaxValues(") == 0)
check("and narrows the tooltip back", count(":SetMinimumWidth(0)") == 1)
check("a quest the character can take is not dimmed", count(":SetVertexColor(0.5,0.5,0.5)") == 0)

print("A quest that can't be taken yet is dimmed")
ctx.level = 1
record = {}
newPin(singleData):OnMouseEnter()
check("its icon is dimmed", count(":SetVertexColor(0.5,0.5,0.5)") == 1, tostring(count(":SetVertexColor(")))
check("and its line says what it needs", count("|cff808080(Requires Level") == 1)
ctx.level = 1000

print("A tooltip hidden by something else is not redrawn")
local hidden = newPin(singleData)
hidden:OnMouseEnter()
tooltip:Hide()
record = {}
QC.RedrawMapTooltip()
check("a redraw leaves it hidden", #record == 0, tostring(#record))

if RECORD_FILE then
	-- The whole record again, from the start, for comparing one version of the code with another.
	local out = assert(io.open(RECORD_FILE, "wb"))
	record = {}
	env.qcMapTooltipSetup()
	ctx.hooks.OnSizeChanged(env.WorldMapFrame)
	local pins = {newPin(stackData), newPin(singleData, 900, 100), newPin(singleData, 100, 600)}
	for _, p in ipairs(pins) do
		p:OnMouseEnter()
		ctx.shift = true
		watcher(nil, "MODIFIER_STATE_CHANGED", "RSHIFT")
		ctx.shift = false
		QC.RedrawMapTooltip()
		p:OnMouseLeave()
	end
	ctx.level = 1
	local dimmed = newPin(singleData)
	dimmed:OnMouseEnter()
	dimmed:OnMouseLeave()
	ctx.level = 1000
	for _, line in ipairs(record) do out:write(line, "\n") end
	out:close()
end

print("A stack of pins is named for its first named giver")
local realPinDB = env.qcPinDB
local provider = env.qcMapDataProvider
local stackMap = {drawn = {}}
stackMap.mapId = 84
function stackMap:GetMapID() return self.mapId end
function stackMap:RemoveAllPinsByTemplate() self.drawn = {} end
function stackMap:AcquirePin(_, data) self.drawn[#self.drawn + 1] = data end
provider.GetMap = function() return stackMap end
local waypoints
env.C_AddOns.IsAddOnLoaded = function(name) return name == "TomTom" end
env.TomTom = {
	AddWaypoint = function(_, mapId, x, y, options) waypoints[#waypoints + 1] = {mapId = mapId, x = x, y = y, title = options.title} end,
	SetClosestWaypoint = function() end,
}
local function draw(pins)
	env.qcPinDB = {[84] = pins}
	provider:RefreshAllData()
	return stackMap.drawn
end
local function click(data)
	waypoints = {}
	local clicked = newPin(data)
	clicked.GetMap = function() return stackMap end
	clicked:OnMouseClickAction("LeftButton")
	return waypoints[1]
end
local function firstHeading(data)
	record = {}
	local hovered = newPin(data)
	hovered:OnMouseEnter()
	hovered:OnMouseLeave()
	for _, line in ipairs(record) do
		if line:find(":AddDoubleLine(", 1, true) then return line end
	end
end
local otherQuests = env.qcLocalize.OTHERQUESTS

local nameless = {1, 0, nil, 50, 50, {pinA[6][3]}}
local namelessNear = {1, 0, nil, 50.2, 50, {pinA[6][1]}}
local namedA = {pinA[1], pinA[2], pinA[3], 50.3, 50.2, {pinA[6][1], pinA[6][2]}}
local namedB = {pinB[1], pinB[2], pinB[3], 50.1, 50.4, pinB[6]}

local drawn = draw({nameless, namedA})
check("a nameless pin and a named one, 0.36 points apart, are one pin", #drawn == 1 and drawn[1].stack ~= nil and #drawn[1].stack == 2)
check("the nameless pin is still the group's first, which decides who joins", drawn[1].stack[1][3] == nil and drawn[1].stack[2][3] == pinA[3])
check("the pin takes the named giver's NPC and name", drawn[1][2] == pinA[2] and drawn[1][3] == pinA[3])
check("and stays at the first pin's point", drawn[1][4] == 50 and drawn[1][5] == 50)
check("it holds the quests of both", #drawn[1][6] == 3)
local waypoint = click(drawn[1])
check("a click's waypoint is titled with the named giver, not a quest", waypoint and waypoint.title == pinA[3], waypoint and waypoint.title)
check("and sits at the first pin's point on the map's ID", waypoint and waypoint.mapId == 84 and waypoint.x == 0.5 and waypoint.y == 0.5)
local heading = firstHeading(drawn[1])
check("the tooltip's first heading is the same giver", heading and heading:find(":AddDoubleLine(" .. pinA[3] .. ",", 1, true) ~= nil, heading)
check("and the nameless pin's quests follow under the other quests", count(otherQuests, 1) == 1)
local npcIdText, questIdText = "|cff808080" .. pinA[2] .. "|r", "|cff808080" .. pinA[6][3] .. "|r"
check("the heading shows the giver's NPC ID, and a quest line its quest ID", heading:find(npcIdText, 1, true) ~= nil and count(questIdText, 1) >= 1)
env.qcSettings.QC_SHOW_QUEST_IDS = 0
firstHeading(draw({nameless, namedA})[1])
check("with quest IDs off the tooltip still names the giver and the quest", count(pinA[3], 1) >= 1 and count("Home Sweet Gnome", 1) == 1)
check("but shows no NPC ID", count(npcIdText, 1) == 0)
check("and no quest ID", count(questIdText, 1) == 0)
env.qcSettings.QC_SHOW_QUEST_IDS = nil
env.qcQuestPvP = {[pinA[6][3]] = 1}
firstHeading(draw({nameless, namedA})[1])
check("a PvP quest's line has the crossed swords before its name", count("|A:questlog-questtypeicon-pvp:14:14|a |cff", 1) == 1 and count("Home Sweet Gnome", 1) == 1)
env.qcQuestPvP = {}
firstHeading(draw({nameless, namedA})[1])
check("a quest that is not in the PvP table has none", count("questlog-questtypeicon-pvp", 1) == 0)
local function pinAtlas(data)
	local atlas
	local pin = newPin(data)
	pin.UseFrameLevelType, pin.SetPosition, pin.SetSize = function() end, function() end, function() end
	pin.Texture = {SetAtlas = function(_, name) atlas = name end, SetTexture = function() end, SetTexCoord = function() end, SetVertexColor = function() end}
	pin:OnAcquired(data)
	return atlas
end
local pvpAtlas = "questlog-questtypeicon-pvp"
env.qcQuestPvP = {[pinA[6][1]] = 1, [pinA[6][2]] = 1}
check("a pin whose quests are all PvP draws the PvP icon", pinAtlas({pinA[1], pinA[2], pinA[3], 50.3, 50.2, {pinA[6][1], pinA[6][2]}}) == pvpAtlas)
check("one with a quest that is not PvP keeps its own icon", pinAtlas({pinA[1], pinA[2], pinA[3], 50.3, 50.2, {pinA[6][1], pinA[6][2], pinA[6][3]}}) ~= pvpAtlas)
check("and so does one with no quests", pinAtlas({pinA[1], pinA[2], pinA[3], 50.3, 50.2, {}}) ~= pvpAtlas)
env.qcQuestPvP = {}
check("a pin with no PvP quest keeps its icon", pinAtlas({pinA[1], pinA[2], pinA[3], 50.3, 50.2, {pinA[6][1], pinA[6][2]}}) ~= pvpAtlas)

drawn = draw({namedA, nameless})
check("a stack whose first pin is named stays named for it", drawn[1][3] == pinA[3] and drawn[1][4] == 50.3 and drawn[1][5] == 50.2)
check("its waypoint is titled with that giver", click(drawn[1]).title == pinA[3])

drawn = draw({nameless, namedB, namedA})
check("of two named givers the first in the stack gives the name", drawn[1][3] == pinB[3] and drawn[1][2] == pinB[2])
check("and its waypoint is titled with that one", click(drawn[1]).title == pinB[3])
drawn = draw({nameless, namedA, namedB})
check("in the other order the other one does", drawn[1][3] == pinA[3] and click(drawn[1]).title == pinA[3])

drawn = draw({nameless, namelessNear})
check("a stack with no named pin takes its first pin's fields", drawn[1][2] == 0 and drawn[1][3] == nil and drawn[1][1] == nameless[1])
check("and its waypoint takes the name of its first quest", click(drawn[1]).title == QC.qcQuestName(nameless[6][1]), click(drawn[1]).title)

drawn = draw({nameless, {1, pinB[2], pinB[3], 50.4, 50, {pinB[6][1]}}, {1, pinA[2], pinA[3], 50.8, 50, {pinA[6][2]}}})
check("a pin out of reach of the first stays out, so a row doesn't chain", #drawn == 2 and #drawn[1].stack == 2 and drawn[2].stack == nil)
check("the first two are named for the named one", drawn[1][3] == pinB[3] and click(drawn[1]).title == pinB[3])
check("the pin on its own keeps its own name", drawn[2][3] == pinA[3] and click(drawn[2]).title == pinA[3])

drawn = draw({nameless})
check("a single nameless pin is titled with its quest", #drawn == 1 and drawn[1].stack == nil and click(drawn[1]).title == QC.qcQuestName(nameless[6][1]))
drawn = draw({namedA})
check("a single named pin is titled with its giver", drawn[1].stack == nil and click(drawn[1]).title == pinA[3])

env.qcPinDB = realPinDB
local stacks, firstNameless, unnamed = 0, 0, 0
for _, mapId in ipairs(mapIds) do
	stackMap.mapId = mapId
	provider:RefreshAllData()
	for _, data in ipairs(stackMap.drawn) do
		if data.stack then
			stacks = stacks + 1
			local named
			for _, member in ipairs(data.stack) do
				if member[3] and not named then named = member end
			end
			if named and not data.stack[1][3] then firstNameless = firstNameless + 1 end
			if named and not (data[2] == named[2] and data[3] == named[3] and click(data).title == named[3]) then
				unnamed = unnamed + 1
			end
		end
	end
end
stackMap.mapId = 84
check("every stack in the data with a named pin is named for its first one", unnamed == 0,
	string.format("%d stacks, %d with a nameless first pin", stacks, firstNameless))

print("Without TomTom, a click sets the game's own waypoint")
local tomtom = env.TomTom
local function setTomTom(loaded, standIn)
	env.C_AddOns.IsAddOnLoaded = function(name) return loaded and name == "TomTom" end
	env.TomTom = loaded and (standIn or tomtom) or nil
end
local PIN_RULE = 1234
local WAYPOINT_FUNCTIONS = {CanSetUserWaypointOnMap = true, SetUserWaypoint = true}
local game
local function installGameApi()
	game = {allowed = {[84] = true}, ruleActive = false, setResult = true, calls = {}}
	local function note(text) game.calls[#game.calls + 1] = text end
	local api = {
		GetBestMapForUnit = function() return nil end,
		GetPlayerMapPosition = function() return nil end,
		CanSetUserWaypointOnMap = function(mapId) note("can " .. tostring(mapId)); return game.allowed[mapId] == true end,
		SetUserWaypoint = function(point) note("set"); game.waypoint = point; return game.setResult end,
	}
	env.C_Map = setmetatable({}, {__index = function(_, key)
		if api[key] ~= nil or WAYPOINT_FUNCTIONS[key] then return api[key] end
		return dummy
	end})
	env.C_SuperTrack = {SetSuperTrackedUserWaypoint = function(on) note("track " .. tostring(on)); game.superTracked = on end}
	env.C_GameRules = {IsGameRuleActive = function(rule) return game.ruleActive and rule == PIN_RULE end}
	env.Enum = {GameRule = {WorldMapTrackingPinDisabled = PIN_RULE}}
	env.UiMapPoint = {CreateFromCoordinates = function(mapId, x, y) return {uiMapID = mapId, position = {x = x, y = y}} end}
	return api
end
local function clickPin(data)
	waypoints = {}
	local clicked = newPin(data)
	clicked.GetMap = function() return stackMap end
	return pcall(clicked.OnMouseClickAction, clicked, "LeftButton")
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-9 end
local function calls() return table.concat(game.calls, ",") end
local function gameWaypointIs(mapId, x, y)
	local point = game.waypoint
	return point ~= nil and point.uiMapID == mapId and near(point.position.x, x) and near(point.position.y, y)
end

local dataA = {pinA[1], pinA[2], pinA[3], 50.3, 50.2, {pinA[6][1]}}
local dataB = {pinB[1], pinB[2], pinB[3], 20.5, 70.25, pinB[6]}

installGameApi()
setTomTom(true)
local ok = clickPin(dataA)
check("with TomTom loaded a click sets TomTom's waypoint", ok and #waypoints == 1 and waypoints[1].title == pinA[3] and near(waypoints[1].x, 0.503))
check("and nothing of the game's own", calls() == "" and game.waypoint == nil, calls())

setTomTom(false)
ok = clickPin(dataA)
check("without TomTom the click asks the game about the map, sets the waypoint and makes it the arrow's", ok and calls() == "can 84,set,track true", calls())
check("the point is on that map, in the game's 0 to 1", gameWaypointIs(84, 0.503, 0.502))
check("TomTom's list stays empty", #waypoints == 0)
ok = clickPin(dataB)
check("a second click replaces the first waypoint", ok and calls() == "can 84,set,track true,can 84,set,track true" and gameWaypointIs(84, 0.205, 0.7025), calls())

local before = game.waypoint
game.calls = {}
game.allowed[84] = false
ok = clickPin(dataA)
check("a map the game refuses sets nothing and raises no error", ok and calls() == "can 84" and game.waypoint == before, calls())
game.allowed[84], game.ruleActive = true, true
game.calls = {}
ok = clickPin(dataA)
check("so does one where the game's rule turns the map pin off", ok and calls() == "" and game.waypoint == before, calls())
game.ruleActive, game.setResult = false, false
ok = clickPin(dataA)
check("a waypoint the game doesn't set is not made the arrow's", ok and calls() == "can 84,set", calls())

local api = installGameApi()
api.CanSetUserWaypointOnMap = function() error("restricted") end
ok = clickPin(dataA)
check("a map check that raises an error is no error and sets nothing", ok and calls() == "", calls())
api = installGameApi()
api.SetUserWaypoint = function() error("restricted") end
ok = clickPin(dataA)
check("a waypoint call that raises an error is no error and makes nothing the arrow's", ok and calls() == "can 84", calls())

installGameApi().SetUserWaypoint = nil
ok = clickPin(dataA)
check("a client without SetUserWaypoint does nothing and raises no error", ok and calls() == "", calls())
installGameApi().CanSetUserWaypointOnMap = nil
ok = clickPin(dataA)
check("one without CanSetUserWaypointOnMap does nothing and raises no error", ok and calls() == "" and game.waypoint == nil, calls())
installGameApi()
env.C_SuperTrack = {}
ok = clickPin(dataA)
check("one without SetSuperTrackedUserWaypoint does nothing and raises no error", ok and calls() == "" and game.waypoint == nil, calls())
installGameApi()
env.C_SuperTrack = false
ok = clickPin(dataA)
check("one without C_SuperTrack does nothing and raises no error", ok and calls() == "" and game.waypoint == nil, calls())
installGameApi()
env.UiMapPoint = {}
ok = clickPin(dataA)
check("one without UiMapPoint.CreateFromCoordinates does nothing and raises no error", ok and calls() == "" and game.waypoint == nil, calls())
installGameApi()
env.C_Map = false
ok = clickPin(dataA)
check("one without C_Map does nothing and raises no error", ok and calls() == "", calls())
installGameApi()
env.C_GameRules, env.Enum = false, false
ok = clickPin(dataA)
check("one without the game rules still sets the waypoint", ok and calls() == "can 84,set,track true", calls())
installGameApi()
setTomTom(true, {})
ok = clickPin(dataA)
check("a TomTom without AddWaypoint is no TomTom: the game's waypoint is set", ok and calls() == "can 84,set,track true" and #waypoints == 0, calls())
setTomTom(false)

print("A pin's tooltip says a click sets a waypoint only where one will be set")
local function waypointLine()
	record = {}
	newPin(singleData):OnMouseEnter()
	return count("Click to set a waypoint")
end
installGameApi()
check("on a map the game allows it does", waypointLine() == 1)
check("and the line doesn't name TomTom", count("TomTom") == 0)
game.allowed[84] = false
check("on a map the game refuses it doesn't", waypointLine() == 0)
game.allowed[84], game.ruleActive = true, true
check("nor while the game's rule turns the map pin off", waypointLine() == 0)
installGameApi()
env.C_SuperTrack = {}
check("nor on a client without the arrow", waypointLine() == 0)
installGameApi()
setTomTom(true)
game.allowed[84] = false
check("with TomTom loaded it does, whatever the game says", waypointLine() == 1)
setTomTom(false)

print("Clicking a quest in the list sets the waypoint the same way")
local listQuest = pinA[6][1]
env.qcMenuButton1 = {QuestID = listQuest}
env.IsLeftShiftKeyDown = function() return false end
env.IsLeftAltKeyDown = function() return false end
installGameApi()
local listMap, listPin = QC.qcFindPinForQuest(listQuest)
check("the quest has a pin to go to", listMap ~= nil and listPin ~= nil)
game.allowed[listMap] = true
setTomTom(true)
waypoints = {}
ok = pcall(env.qcQuestClick, 1)
check("with TomTom loaded the click sets TomTom's waypoint, titled as before", ok and #waypoints == 1 and waypoints[1].mapId == listMap
	and near(waypoints[1].x, listPin[4] / 100) and near(waypoints[1].y, listPin[5] / 100)
	and waypoints[1].title == (QC.qcNpcName(listPin) or QC.qcQuestName(listQuest)), waypoints[1] and waypoints[1].title)
check("and nothing of the game's own", calls() == "", calls())
setTomTom(false)
waypoints = {}
ok = pcall(env.qcQuestClick, 1)
check("without TomTom it asks the game, sets the waypoint at the pin and makes it the arrow's", ok and calls() == "can " .. listMap .. ",set,track true", calls())
check("on the pin's map, in the game's 0 to 1", gameWaypointIs(listMap, listPin[4] / 100, listPin[5] / 100))
check("and TomTom's list stays empty", #waypoints == 0)
game.calls, game.allowed[listMap] = {}, false
before = game.waypoint
ok = pcall(env.qcQuestClick, 1)
check("a map the game refuses sets nothing and raises no error", ok and calls() == "can " .. listMap and game.waypoint == before, calls())
installGameApi()
env.C_SuperTrack = false
ok = pcall(env.qcQuestClick, 1)
check("a client without the functions does nothing and raises no error", ok and calls() == "", calls())

env.C_Map, env.C_SuperTrack, env.C_GameRules, env.Enum = nil, nil, nil, nil
env.UiMapPoint = {}
env.qcMenuButton1, env.IsLeftShiftKeyDown, env.IsLeftAltKeyDown = nil, nil, nil
setTomTom(false)

-- The zone icons on a continent map are a second kind of pin on the same tooltip. The code before this one
-- has no such pin, so the record above stays comparable with it.
if rawget(env, "qcContinentPinMixin") then
	print("A continent pin's tooltip, through the same kit")
	local function newContinentPin(icon)
		counters.pin = (counters.pin or 0) + 1
		local pin = {__name = "pin" .. counters.pin, Icon = icon}
		return setmetatable(pin, {__index = function(_, key) return env.qcContinentPinMixin[key] end})
	end
	local tooltip = env.qcMapTooltip
	local zoneCategory = QUESTS[pinA[6][3]][3]
	local zone = {mapId = 12, name = "Test Zone", x = 0.4, y = 0.4, categories = {zoneCategory}}
	local icon = {zone = zone, look = QC.QC_ICON_NORMAL, count = 3, dim = false}
	local continentPin = newContinentPin(icon)
	record = {}
	continentPin:OnMouseEnter()
	check("it opens on the pin, to its right", record[1] == tooltip.__name .. ":SetOwner(" .. continentPin.__name .. ",ANCHOR_RIGHT)", record[1])
	check("it clears its lines next", record[2] == tooltip.__name .. ":ClearLines()", record[2])
	check("the zone's name heads it", count(":AddLine(Test Zone,") == 1)
	check("what is done of it is a bar", count(":SetMinMaxValues(0,") == 1 and count("|cffc8c8c8") == 1)
	check("the quests in the log are a row", count("In Progress|r") == 1)
	check("the quests to take are a row", count("Available Quests|r") == 1)
	check("a row with nothing in it is left out", count("Ready for turn-in") == 0)
	check("the last line says what a click does", count("<Click to Zoom In>") == 1)
	check("the bar widens it", count(":SetMinimumWidth(180)") == 1)
	check("it ends by showing itself", record[#record] == tooltip.__name .. ":Show()", record[#record])
	local first = #record
	record = {}
	QC.RedrawMapTooltip()
	check("a redraw runs this pin's tooltip, now the one under the mouse", record[1] == tooltip.__name .. ":SetOwner(" .. continentPin.__name .. ",ANCHOR_RIGHT)" and #record <= first, tostring(#record))
	record = {}
	ctx.shift = true
	shiftWatcher()(nil, "MODIFIER_STATE_CHANGED", "LSHIFT")
	ctx.shift = false
	check("Shift redraws it too", record[1] == tooltip.__name .. ":SetOwner(" .. continentPin.__name .. ",ANCHOR_RIGHT)")
	record = {}
	continentPin:OnMouseLeave()
	check("leaving hides it", record[1] == tooltip.__name .. ":Hide()", record[1])
	record = {}
	QC.RedrawMapTooltip()
	check("and nothing is redrawn after", #record == 0, tostring(#record))
	record = {}
	newContinentPin({zone = {mapId = 13, name = "Far", x = 0.8, y = 0.2, categories = {zoneCategory}}, look = QC.QC_ICON_NORMAL, count = 1}):OnMouseEnter()
	check("a zone near the right edge opens to its left", record[1]:find(",ANCHOR_LEFT)", 1, true) ~= nil, record[1])
	record = {}
	newContinentPin({zone = {mapId = 14, name = "Low", x = 0.2, y = 0.8, categories = {zoneCategory}}, look = QC.QC_ICON_NORMAL, count = 1}):OnMouseEnter()
	check("one near the bottom opens below it", record[1]:find(",ANCHOR_BOTTOM)", 1, true) ~= nil, record[1])
	record = {}
	newContinentPin(nil):OnMouseEnter()
	check("a pin with no icon leaves the tooltip alone", #record == 0)
	do
		local before = env.qcCharacterCompletions
		local done = {}
		for questId, entry in pairs(QUESTS) do
			if entry[3] == zoneCategory then done[questId] = 1 end
		end
		local inLog = ctx.inLog
		env.qcCharacterCompletions, ctx.inLog = done, {}
		record = {}
		newContinentPin({zone = zone, look = QC.QC_ICON_COMPLETE, dim = false}):OnMouseEnter()
		check("a completed zone's tooltip is its name and a bar, no row, and what a click does", count(":AddLine(Test Zone,") == 1
			and count(":SetMinMaxValues(0,") == 1 and count("Available Quests|r") == 0 and count("In Progress|r") == 0
			and count("<Click to Zoom In>") == 1)
		env.qcCharacterCompletions, ctx.inLog = before, inLog
	end
end

print(failures == 0 and "All checks passed." or (failures .. " checks failed."))
os.exit(failures == 0 and 0 or 1)
