--[[
Checks how quest givers' names in the client's language are asked for (docs/plans/localized-npc-names.md):
opening a map asks for none of them, a hovered pin asks for its own givers, and a name that arrives is
drawn on the pin's tooltip, also when the game's update event comes before the name can be read, as it
usually does. Users reported that opening a large map froze the game the first time while the addon asked
for every giver on it.

Loads the addon's own files with stand-ins for the WoW API, a clock that only moves when told, and a game
that answers a creature it hasn't cached with nothing, then 0.1 s later fires TOOLTIP_DATA_UPDATE with no
ID and makes the name readable a set time after that (never, for an ID that isn't a creature).

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-NpcNames.lua
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-NpcNames.lua QuestCompletist QuestCompletist_Camelot.toc
Prints each check and exits with 1 if one fails. Run it for both games' TOCs.
]]

local ADDON_DIR = arg and arg[1] or "QuestCompletist"
local TOC_FILE = arg and arg[2] or "QuestCompletist.toc"

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

--[[ The clock: timers run, in order, only when it is moved on ]]--
local now, timers = 0, {}
local function after(delay, fn)
	timers[#timers + 1] = {at = now + delay, fn = fn, order = #timers}
end
local function advance(seconds)
	local stop = now + seconds
	while true do
		local nextIndex
		for i, timer in ipairs(timers) do
			if timer.at <= stop and (not nextIndex or timer.at < timers[nextIndex].at) then nextIndex = i end
		end
		if not nextIndex then break end
		local timer = table.remove(timers, nextIndex)
		now = math.max(now, timer.at)
		timer.fn()
	end
	now = stop
end

--[[ The game: creatures it has cached, creatures it is fetching, and every question asked ]]--
local game = {cached = {}, fetching = {}, never = {}, readableAfter = 0, instance = false, asked = {}, calls = 0}
local onEvent, eventFrame
local function fireEvent(event, ...)
	onEvent(eventFrame, event, ...)
end
local function clientName(npcId) return "Client " .. npcId end
local function getHyperlink(link)
	local npcId = tonumber(link:match("^unit:Creature%-0%-0%-0%-0%-(%d+)%-"))
	game.calls = game.calls + 1
	game.asked[npcId] = (game.asked[npcId] or 0) + 1
	if game.cached[npcId] and not game.instance then
		return {lines = {{leftText = clientName(npcId)}, {leftText = "Level 70"}}}
	end
	if not game.fetching[npcId] and not game.never[npcId] then
		game.fetching[npcId] = true
		local lag = game.readableAfter
		after(0.1, function()
			if lag == 0 then game.cached[npcId] = true end
			fireEvent("TOOLTIP_DATA_UPDATE", nil)
			if lag > 0 then after(lag, function() game.cached[npcId] = true end) end
		end)
	end
	return nil
end

--[[ Frames and what they make: any method does nothing, one that makes something hands back another such
stand-in, and a field is empty until set. The tooltip also keeps what its lines say. ]]--
local function newObject(fields)
	return setmetatable(fields or {}, {__index = function(_, key)
		if type(key) ~= "string" or not key:match("^%u") then return nil end
		if key:sub(1, 6) == "Create" then return function() return newObject() end end
		return function() end
	end})
end

local function newTooltip()
	local tooltip = newObject({lines = {}, shown = false})
	tooltip.AddLine = function(self, text) self.lines[#self.lines + 1] = tostring(text) end
	tooltip.AddDoubleLine = function(self, left) self.lines[#self.lines + 1] = tostring(left) end
	tooltip.ClearLines = function(self) self.lines = {} end
	tooltip.NumLines = function(self) return #self.lines end
	tooltip.Show = function(self) self.shown = true end
	tooltip.Hide = function(self) self.shown = false end
	tooltip.IsShown = function(self) return self.shown end
	return tooltip
end

local env
local function newPin(pinData)
	local pin = {PinData = pinData}
	pin.GetCenter = function() return 100, 100 end
	pin.GetMap = function() return {GetMapID = function() return 84 end} end
	return setmetatable(pin, {__index = function(_, key) return env.qcPinMixin[key] end})
end

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
			local tooltip = newTooltip()
			if name then env[name] = tooltip end
			return tooltip
		end
		return newObject()
	end,
	C_Timer = {After = after},
	UIParent = newObject(),
	WorldMapFrame = {
		HookScript = function() end,
		GetCanvas = function() return {GetSize = function() return 1000, 700 end} end,
		GetScale = function() return 1 end,
		AddDataProvider = function() end,
	},
	IsShiftKeyDown = function() return false end,
	IsModifierKeyDown = function() return false end,
	IsInInstance = function() return game.instance end,
	issecretvalue = function() return false end,
	C_AddOns = {IsAddOnLoaded = function() return false end},
	UnitFactionGroup = function() return "Alliance", "Alliance" end,
	UnitRace = function() return "NightElf", "NightElf" end,
	UnitClass = function() return "DRUID", "DRUID" end,
	UnitLevel = function() return 1000 end,
	UnitName = function() return "Tester" end,
	UnitQuestTrivialLevelRange = function() return 5 end,
	GetProfessions = function() return end,
	GetProfessionInfo = function() return end,
	TOOLTIP_UNIT_LEVEL = "Level %s",
	ITEM_REQ_ALLIANCE = "Alliance", ITEM_REQ_HORDE = "Horde", ITEM_RACES_ALLOWED = "Races: %s",
	ITEM_CLASSES_ALLOWED = "Classes: %s", ITEM_MIN_LEVEL = "Requires Level %d", ITEM_REQ_SKILL = "Requires %s",
	ITEM_REQ_REPUTATION = "Requires %s - %s", ITEM_MIN_SKILL = "Requires %s (%d)", RENOWN_LEVEL_LABEL = "Renown %d",
	UNKNOWN = "Unknown",
	C_Covenants = stubTable({GetActiveCovenantID = function() return 0 end}),
	C_MajorFactions = stubTable({GetCurrentRenownLevel = function() return 1000 end}),
	C_SkillInfo = stubTable({GetSkillLineInfoByID = function() return {rank = 1000, modifier = 0} end}),
	C_QuestLog = stubTable({
		GetLogIndexForQuestID = function() return nil end,
		IsComplete = function() return false end,
		IsQuestFlaggedCompleted = function() return false end,
		IsQuestFlaggedCompletedOnAccount = function() return false end,
		GetTitleForQuestID = function() return nil end,
		RequestLoadQuestByID = function() end,
		IsWorldQuest = function() return false end,
	}),
	C_TaskQuest = stubTable({GetQuestInfoByQuestID = function() return nil end}),
	C_TooltipInfo = stubTable({GetHyperlink = getHyperlink}),
	C_Map = stubTable({GetBestMapForUnit = function() return nil end, GetMapInfo = function() return nil end}),
	C_DateAndTime = stubTable({GetCurrentCalendarTime = function() return {year = 2026, month = 10, monthDay = 16, hour = 14, minute = 30} end}),
}
env._G = env
setmetatable(env, {__index = function(_, key)
	local value = _G[key]
	if value ~= nil then return value end
	return dummy
end})

--[[ Load the addon in TOC order, then let it register its events ]]--
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

eventFrame = stubTable({})
eventFrame.RegisterEvent = function() end
eventFrame.SetScript = function(_, script, fn) if script == "OnEvent" then onEvent = fn end end
env.qcQuestCompletistUI_OnLoad(eventFrame)
assert(onEvent, "the addon set no OnEvent script")
local tooltip = env.qcMapTooltip
assert(tooltip, "no map tooltip was made")

--[[ Checks ]]--
local failures = 0
local function check(label, passed, detail)
	if not passed then failures = failures + 1 end
	print(string.format("  [%s] %s%s", passed and "ok" or "FAIL", label, detail and (" (" .. detail .. ")") or ""))
end

local function says(text)
	for _, line in ipairs(tooltip.lines) do
		if line:find(text, 1, true) then return true end
	end
	return false
end

-- The map whose pins name the most givers, and a pin of it with one.
local bestMap, bestCount = nil, 0
for mapId, pins in pairs(env.qcPinDB) do
	local ids, n = {}, 0
	for _, pin in ipairs(pins) do
		if pin[3] and pin[2] ~= 0 and not ids[pin[2]] then ids[pin[2]], n = true, n + 1 end
	end
	if n > bestCount or (n == bestCount and mapId < bestMap) then bestMap, bestCount = mapId, n end
end
local givers, seen = {}, {}
for _, pin in ipairs(env.qcPinDB[bestMap]) do
	if pin[3] and pin[2] ~= 0 and #pin[6] > 0 and not seen[pin[2]] then
		seen[pin[2]] = true
		givers[#givers + 1] = pin
	end
end
assert(#givers >= 4, "the largest map has fewer than four named givers")
local function pinOf(index)
	local pin = givers[index]
	return {pin[1], pin[2], pin[3], pin[4], pin[5], pin[6]}
end

local function reset()
	game.cached, game.fetching, game.never, game.asked, game.calls = {}, {}, {}, {}, 0
	game.readableAfter, game.instance = 0, false
end

print(string.format("Opening map %d, whose pins name %d givers, none of them cached", bestMap, bestCount))
reset()
local drawn = 0
local map = {}
function map:GetMapID() return bestMap end
function map:RemoveAllPinsByTemplate() end
function map:AcquirePin() drawn = drawn + 1 end
env.qcMapDataProvider.GetMap = function() return map end
env.qcMapDataProvider:RefreshAllData()
advance(10)
check("the map draws its pins", drawn > 0, drawn .. " drawn")
check("and asks the game for none of its givers' names", game.calls == 0, game.calls .. " asked")

print("Hovering a pin asks for its giver, and the tooltip takes the name when it can be read")
reset()
local first = pinOf(1)
local pin = newPin(first)
pin:OnMouseEnter()
check("the tooltip shows our name while the game's is loading", says(first[3]))
check("the giver is asked for once", game.asked[first[2]] == 1, tostring(game.asked[first[2]]))
advance(0.2)
check("the name, readable at the update event, is drawn", says(clientName(first[2])))
local settled = game.calls
advance(10)
check("and nothing more is asked once it has come", game.calls == settled, (game.calls - settled) .. " more")
pin:OnMouseLeave()

print("A name readable only after its update event, with nothing else loading, is drawn shortly after")
reset()
game.readableAfter = 0.1
local second = pinOf(2)
pin = newPin(second)
pin:OnMouseEnter()
advance(0.15)
check("the update event alone doesn't bring it", not says(clientName(second[2])))
advance(0.5)
check("a look shortly after does", says(clientName(second[2])))
settled = game.calls
advance(10)
check("and the looking stops once it has come", game.calls == settled, (game.calls - settled) .. " more")
pin:OnMouseLeave()

print("A giver the game never names is looked at until the timeout, then left")
reset()
local third = pinOf(3)
game.never[third[2]] = true
pin = newPin(third)
pin:OnMouseEnter()
advance(5.1)
local byTimeout = game.asked[third[2]] or 0
check("it is asked no more than about four times a second", byTimeout <= 1 + 5 / 0.25, byTimeout .. " times")
check("and the tooltip keeps our name", says(third[3]))
advance(30)
check("after the timeout it is not asked again", (game.asked[third[2]] or 0) == byTimeout, (game.asked[third[2]] or 0) .. " times")
pin:OnMouseLeave()

print("Inside an instance nothing is asked; the name is asked for after leaving")
reset()
game.instance = true
local fourth = pinOf(4)
pin = newPin(fourth)
pin:OnMouseEnter()
advance(1)
check("hovering inside an instance asks the game nothing", game.calls == 0, game.calls .. " asked")
pin:OnMouseLeave()
game.instance = false
fireEvent("PLAYER_ENTERING_WORLD", false, false)
advance(1)
check("leaving asks for the giver hovered inside", (game.asked[fourth[2]] or 0) >= 1, tostring(game.asked[fourth[2]]))
pin = newPin(fourth)
pin:OnMouseEnter()
check("and the next hover shows its name", says(clientName(fourth[2])))
pin:OnMouseLeave()

if failures > 0 then
	print(string.format("%d check%s failed.", failures, failures == 1 and "" or "s"))
	os.exit(1)
end
print("All checks passed.")
