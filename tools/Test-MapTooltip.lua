--[[
Checks the map's tooltip: what a quest giver's pin draws on it when the mouse enters, how it is cleared
when the mouse leaves, and how it is redrawn when names arrive or Shift changes.

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

print(failures == 0 and "All checks passed." or (failures .. " checks failed."))
os.exit(failures == 0 and 0 or 1)
