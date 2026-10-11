--[[
Checks the quests the addon ticks for a character (qcCharacterCompletions): what the login sync and
a hand-in tick, and the clean-up of the ticks that links since removed gave (qcFormerlyExclusive,
until 1 April 2027).

Loads the addon's own files with stand-ins for the WoW API and for a server whose completed quests
each check sets, then fires PLAYER_ENTERING_WORLD and QUEST_TURNED_IN through the addon's own event
handler. The clean-up is checked on one of the game's groups of quests of which only one can be done,
listed in place of the real list, as retail's list is empty. On WoW: Forever's TOC it also walks the
quests whose links were found wrong on 11 October 2026 (docs/plans/forever-quest-link-decisions.csv):
the level 10 rogue quests, and Guard Thomas's Bounty on Murlocs. Retail has only Snatch and Grab
and Bounty on Murlocs of them, neither with the quest it needs on Forever.

It also checks breadcrumbs: the map hides one still to do while the quest it leads to is in the log, as
the game stops offering it, and a hand-in ticks the breadcrumbs leading to breadcrumbs as well. Both
games' data give a case of the second; retail's also has quests listed as each other's breadcrumb, and
the breadcrumbs Blizzard's API says close only once their quest is done (qcClosedOnceDone), which the map
keeps meanwhile. Forever's has the level 16 rogue quests, where SI:7 showed at Keryn Sylvius though she no
longer offered it.

On WoW: Forever's TOC it also walks the level 10 warrior and mage quests, whose links the decisions file
corrected on 11 October 2026 from Questie's issues and Wowhead's comments: the lead-ins no longer shut each
other out, the quests they lead to do, and each of those closes every lead-in. With them, Securing the
Supply Lines and its breadcrumbs, the two first steps of the shamans' Call of Earth, Iron Coral's
prerequisite, and the eight quests that no longer need their breadcrumb.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-Completions.lua
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-Completions.lua QuestCompletist QuestCompletist_Camelot.toc
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

--[[ The map tooltip writes down its lines, so a pin's quests can be read back ]]--
local lines = {}
local function newTooltip()
	local tooltip = stubTable({count = 0})
	tooltip.AddLine = function(self, text) lines[#lines + 1] = tostring(text); self.count = self.count + 1 end
	tooltip.AddDoubleLine = function(self, left) lines[#lines + 1] = tostring(left); self.count = self.count + 1 end
	tooltip.ClearLines = function(self) self.count = 0 end
	tooltip.NumLines = function(self) return self.count end
	tooltip.IsShown = function() return false end
	return tooltip
end

--[[ Load the addon in TOC order ]]--
local ctx = {server = {}, inLog = {}, race = "Human", class = "ROGUE", level = 16}
local env
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
			env[name] = newTooltip()
			return env[name]
		end
		return stubTable({RegisterEvent = function() end, SetScript = function() end})
	end,
	WorldMapFrame = stubTable({GetCanvas = function() return {GetSize = function() return 1000, 700 end} end, GetScale = function() return 1 end}),
	IsShiftKeyDown = function() return false end,
	IsModifierKeyDown = function() return false end,
	IsInInstance = function() return false end,
	C_AddOns = {IsAddOnLoaded = function() return false end},
	UnitFactionGroup = function() return "Alliance", "Alliance" end,
	UnitRace = function() return ctx.race, ctx.race end,
	UnitClass = function() return ctx.class, ctx.class end,
	UnitLevel = function() return ctx.level end,
	UnitName = function() return "Tester" end,
	UnitQuestTrivialLevelRange = function() return 5 end,
	GetQuestResetTime = function() return 3600 end,
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
		IsComplete = function() return false end,
		IsQuestFlaggedCompleted = function(questId) return ctx.server[questId] == true end,
		IsQuestFlaggedCompletedOnAccount = function() return false end,
		GetAllCompletedQuestIDs = function()
			local ids = {}
			for questId in pairs(ctx.server) do ids[#ids + 1] = questId end
			table.sort(ids)
			return ids
		end,
		GetTitleForQuestID = function() return nil end,
		RequestLoadQuestByID = function() end,
		IsWorldQuest = function() return false end,
	}),
	C_TaskQuest = stubTable({GetQuestInfoByQuestID = function() return nil end}),
	C_TooltipInfo = stubTable({GetHyperlink = function() return nil end}),
	C_DateAndTime = stubTable({GetCurrentCalendarTime = function() return {year = 2026, month = 10, monthDay = 11, hour = 14, minute = 30} end}),
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

local ui = stubTable({})
ui.SetScript = function(self, _, handler) self.handler = handler end
env.qcQuestCompletistUI_OnLoad(ui)
assert(ui.handler, "the main frame's OnLoad set no event handler")

--[[ Checks ]]--
local failures = 0
local function check(label, passed, detail)
	if not passed then failures = failures + 1 end
	print(string.format("  [%s] %s%s", passed and "ok" or "FAIL", label, detail and (" (" .. detail .. ")") or ""))
end

local function fire(event, ...)
	local ok, err = pcall(ui.handler, ui, event, ...)
	if not ok then check(event .. " runs", false, tostring(err)) end
end

-- A character whose server has done the quests given, and whose saved ticks are those given.
local function character(race, done, ticks)
	ctx.race, ctx.server, ctx.inLog = race, {}, {}
	for _, questId in ipairs(done) do ctx.server[questId] = true end
	env.qcCharacterCompletions = {}
	for questId, mark in pairs(ticks) do env.qcCharacterCompletions[questId] = mark end
end

local function login() fire("PLAYER_ENTERING_WORLD", true, false) end

local function turnIn(questId)
	ctx.inLog[questId] = nil
	ctx.server[questId] = true
	fire("QUEST_TURNED_IN", questId)
end

local QUESTS = env.qcQuestDatabase
local function oneTime(questId) return QUESTS[questId] and bit.band(QUESTS[questId][4], 2 + 4 + 128) == 0 end
local function sortedKeys(t)
	local keys = {}
	for key in pairs(t) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

print("The list of quests whose links were removed")
local listed, twice, missing = {}, false, {}
check("qcFormerlyExclusive is a list", type(env.qcFormerlyExclusive) == "table")
for _, questId in ipairs(env.qcFormerlyExclusive) do
	if listed[questId] then twice = true end
	listed[questId] = true
	if not QUESTS[questId] then missing[#missing + 1] = questId end
end
check("it names each quest once", not twice)
check("every quest it names is in the data", #missing == 0, table.concat(missing, ", "))

-- X and Y shut each other out; W is a quest whose completion ticks nothing else.
local X, Y, W
for _, questId in ipairs(sortedKeys(env.qcMutuallyExclusive)) do
	local other = env.qcMutuallyExclusive[questId][1]
	if oneTime(questId) and oneTime(other) then X, Y = questId, other; break end
end
for _, questId in ipairs(sortedKeys(QUESTS)) do
	if oneTime(questId) and questId ~= X and questId ~= Y and not env.qcMutuallyExclusive[questId] and not env.qcBreadcrumbQuests[questId] then W = questId; break end
end
assert(X and Y and W, "no group of two one-time quests in the data")

print(string.format("The clean-up, with %d listed (%d shuts it out; %d ticks nothing else)", X, Y, W))
local realList = env.qcFormerlyExclusive
env.qcFormerlyExclusive = {X}
character("Human", {W}, {[X] = 1})
login()
check("a tick the server doesn't confirm goes", env.qcCharacterCompletions[X] == nil, tostring(env.qcCharacterCompletions[X]))
character("Human", {W, X}, {[X] = 1})
login()
check("a tick the server confirms stays", env.qcCharacterCompletions[X] == 1)
character("Human", {Y}, {[X] = 1})
login()
check("a tick a remaining link gives comes back", env.qcCharacterCompletions[X] == 1, tostring(env.qcCharacterCompletions[X]))
for _, mark in ipairs({0, 2}) do
	character("Human", {W}, {[X] = mark})
	login()
	check("a hand mark of " .. mark .. " stays", env.qcCharacterCompletions[X] == mark, tostring(env.qcCharacterCompletions[X]))
end
character("Human", {W}, {[Y] = 1})
login()
check("a quest not listed keeps a tick the server doesn't confirm", env.qcCharacterCompletions[Y] == 1)
character("Human", {}, {[X] = 1})
login()
check("with no completed quests from the server, nothing goes", env.qcCharacterCompletions[X] == 1)
character("Human", {}, {})
turnIn(X)
check("handing in a quest still ticks the rest of its group", env.qcCharacterCompletions[X] == 1 and env.qcCharacterCompletions[Y] == 1)
env.qcFormerlyExclusive = realList

if not QUESTS[2205] then
	print("Forever's corrected links: not in this game's data")
else
	local SEEK, SNATCH, ROAD, APPLE, DESTINY = 2205, 2206, 2218, 2241, 2242

	print("The level 10 rogue quests' links")
	check("the three cities' lead-ins no longer shut each other out",
		not env.qcMutuallyExclusive[SEEK] and not env.qcMutuallyExclusive[ROAD] and not env.qcMutuallyExclusive[APPLE])
	check("and are all listed for the clean-up", listed[SEEK] and listed[ROAD] and listed[APPLE])
	check("Snatch and Grab needs Seek out SI: 7", env.qcQuestPrereq[SNATCH] == SEEK)
	check("Destiny Calls needs The Apple Falls", env.qcQuestPrereq[DESTINY] == APPLE)

	print("Rothro, a Night Elf rogue who did The Apple Falls, Destiny Calls, then Seek out SI: 7")
	character("NightElf", {SEEK, APPLE, DESTINY}, {[SEEK] = 1, [ROAD] = 1, [APPLE] = 1, [DESTINY] = 1})
	login()
	check("the addon's tick on Road to Salvation goes", env.qcCharacterCompletions[ROAD] == nil, tostring(env.qcCharacterCompletions[ROAD]))
	check("so it shows as still to do", QC.qcQuestStatus.Of(ROAD, QUESTS[ROAD]) == QC.qcQuestStatus.TODO)
	check("the three he did stay ticked", env.qcCharacterCompletions[SEEK] == 1 and env.qcCharacterCompletions[APPLE] == 1 and env.qcCharacterCompletions[DESTINY] == 1)
	character("NightElf", {APPLE, DESTINY}, {[SEEK] = 1, [ROAD] = 1, [APPLE] = 1, [DESTINY] = 1})
	login()
	check("before Seek out SI: 7, its tick went too", env.qcCharacterCompletions[SEEK] == nil and env.qcCharacterCompletions[ROAD] == nil)

	local shaw
	for _, mapId in ipairs(sortedKeys(env.qcPinDB)) do
		for _, pin in ipairs(env.qcPinDB[mapId]) do
			for _, questId in ipairs(pin[6]) do
				if pin[2] == 332 and questId == SNATCH then shaw = pin end
			end
		end
	end
	local function snatchLine()
		lines = {}
		setmetatable({PinData = shaw, GetCenter = function() return 100, 100 end}, {__index = env.qcPinMixin}):OnMouseEnter()
		for _, text in ipairs(lines) do
			if text:find("Snatch and Grab", 1, true) then return text end
		end
	end

	print("A new Human rogue at Master Mathias Shaw's pin")
	check("Shaw has a pin with Snatch and Grab", shaw ~= nil)
	character("Human", {}, {})
	login()
	local before = shaw and snatchLine()
	check("Snatch and Grab is grey, needing Seek out SI: 7", before ~= nil and before:find("|cff9d9d9dSnatch and Grab|r |cff808080(Requires Seek out SI: 7)|r", 1, true) ~= nil, before)
	check("Destiny Calls needs The Apple Falls", QC.qcPinQuestNeeds(DESTINY, QC.qcQuestStatus.Of(DESTINY, QUESTS[DESTINY])) == "Requires The Apple Falls")
	turnIn(SEEK)
	check("handing in Seek out SI: 7 ticks it", env.qcCharacterCompletions[SEEK] == 1)
	check("and neither Road to Salvation nor The Apple Falls", env.qcCharacterCompletions[ROAD] == nil and env.qcCharacterCompletions[APPLE] == nil)
	local after = shaw and snatchLine()
	check("then Snatch and Grab can be taken", after ~= nil and not after:find("Requires", 1, true), after)

	local REPORT, MURLOCS = 39, 46
	local thomas
	for _, mapId in ipairs(sortedKeys(env.qcPinDB)) do
		for _, pin in ipairs(env.qcPinDB[mapId]) do
			for _, questId in ipairs(pin[6]) do
				if pin[2] == 261 and questId == MURLOCS then thomas = pin end
			end
		end
	end
	local function pinLine(pin, name)
		lines = {}
		setmetatable({PinData = pin, GetCenter = function() return 100, 100 end}, {__index = env.qcPinMixin}):OnMouseEnter()
		for _, text in ipairs(lines) do
			if text:find(name, 1, true) then return text end
		end
	end

	print("A level 16 Human at Guard Thomas's pin")
	check("Bounty on Murlocs needs Deliver Thomas' Report", env.qcQuestPrereq[MURLOCS] == REPORT)
	check("Guard Thomas has a pin with Bounty on Murlocs", thomas ~= nil)
	character("Human", {}, {})
	login()
	local murlocs = thomas and pinLine(thomas, "Bounty on Murlocs")
	check("Bounty on Murlocs is grey, needing Deliver Thomas' Report", murlocs ~= nil and murlocs:find("|cff9d9d9dBounty on Murlocs|r |cff808080(Requires Deliver Thomas' Report)|r", 1, true) ~= nil, murlocs)
	turnIn(REPORT)
	murlocs = thomas and pinLine(thomas, "Bounty on Murlocs")
	check("then Bounty on Murlocs can be taken", murlocs ~= nil and not murlocs:find("Requires", 1, true), murlocs)
end

-- Whether the map keeps a quest, hiding quests in the log, or with hideDone, hiding done ones instead.
local function mapKeeps(questId, hideDone)
	local key = hideDone and "QC_M_HIDE_COMPLETED" or "QC_M_HIDE_INPROGRESS"
	env.qcSettings[key] = 1
	local keeps = QC.qcBuildViewFilter("M")(questId)
	env.qcSettings[key] = 0
	return keeps
end

local function listedUnder(target, questId)
	for _, listed in pairs(env.qcBreadcrumbQuests[target] or {}) do
		if listed == questId then return true end
	end
	return false
end

-- A one-time quest T with a breadcrumb B that has a breadcrumb A of its own, A only reaching T through B,
-- and none of them leading back to another.
local A, B, T
for _, target in ipairs(sortedKeys(env.qcBreadcrumbQuests)) do
	for _, breadcrumb in pairs(env.qcBreadcrumbQuests[target]) do
		for _, first in pairs(env.qcBreadcrumbQuests[breadcrumb] or {}) do
			if not T and first ~= target and oneTime(target) and oneTime(breadcrumb) and oneTime(first)
					and not env.qcBreadcrumbQuests[first] and not listedUnder(target, first) then
				A, B, T = first, breadcrumb, target
			end
		end
	end
end
if not T then
	print("Breadcrumbs leading to breadcrumbs: none in this game's data")
else
	print(string.format("Breadcrumbs leading to breadcrumbs: %d leads to %d, which leads to %d", A, B, T))
	character("Human", {}, {})
	login()
	check("before the quest is taken, the map keeps both breadcrumbs", mapKeeps(A) and mapKeeps(B))
	ctx.inLog[T] = 1
	check("while it's in the log, the map hides both", not mapKeeps(A) and not mapKeeps(B))
	check("without ticking them", env.qcCharacterCompletions[A] == nil and env.qcCharacterCompletions[B] == nil)
	ctx.inLog[T] = nil
	check("once it leaves the log again, the map keeps both", mapKeeps(A) and mapKeeps(B))
	character("Human", {A}, {[A] = 1})
	ctx.inLog[T], ctx.inLog[B] = 1, 1
	check("a done breadcrumb stays on a map hiding only quests in the log", mapKeeps(A))
	check("one in the log stays on a map hiding only done quests", mapKeeps(B, true))
	ctx.inLog[B] = nil
	turnIn(T)
	check("handing it in ticks both", env.qcCharacterCompletions[A] == 1 and env.qcCharacterCompletions[B] == 1)
end

-- Retail's breadcrumbs that Blizzard's API says close once their quest is done (qcClosedOnceDone): the
-- game still offers them, and the map keeps them, while that quest is in the log.
local GRULLOC, MOGDORG = 10995, 10983
local notBreadcrumbs = {}
for _, questId in ipairs(sortedKeys(env.qcClosedOnceDone)) do
	local found = false
	for target in pairs(env.qcBreadcrumbQuests) do
		if listedUnder(target, questId) then found = true end
	end
	if not found then notBreadcrumbs[#notBreadcrumbs + 1] = questId end
end
check("every quest qcClosedOnceDone names is a breadcrumb", #notBreadcrumbs == 0, table.concat(notBreadcrumbs, ", "))
if not (QUESTS[GRULLOC] and QUESTS[MOGDORG]) then
	print("Breadcrumbs the API closes once their quest is done: none in this game's data")
else
	print("Breadcrumbs the API closes once their quest is done: Grulloc Has Two Skulls and Mog'dorg the Wizened")
	check("Mog'dorg the Wizened is still Grulloc's breadcrumb, so the quest window warns", listedUnder(GRULLOC, MOGDORG))
	character("Human", {}, {})
	login()
	ctx.inLog[GRULLOC] = 1
	check("with Grulloc Has Two Skulls in the log, the map keeps Mog'dorg the Wizened", mapKeeps(MOGDORG))
	turnIn(GRULLOC)
	check("handing it in ticks Mog'dorg the Wizened", env.qcCharacterCompletions[MOGDORG] == 1)
end

-- Two quests each listed as a breadcrumb of the other.
local P, Q
for _, questId in ipairs(sortedKeys(env.qcBreadcrumbQuests)) do
	for _, other in pairs(env.qcBreadcrumbQuests[questId]) do
		for _, back in pairs(env.qcBreadcrumbQuests[other] or {}) do
			if not P and back == questId and oneTime(questId) and oneTime(other) then P, Q = questId, other end
		end
	end
end
if not P then
	print("Breadcrumbs of each other: none in this game's data")
else
	print(string.format("Breadcrumbs of each other: %d and %d", P, Q))
	character("Human", {}, {})
	login()
	ctx.inLog[P] = 1
	check("with one in the log, the map hides the other, and the walk ends", not mapKeeps(Q))
	turnIn(P)
	check("handing one in ticks the other", env.qcCharacterCompletions[Q] == 1)
end

if not QUESTS[2281] then
	print("The level 16 rogue quests: not in this game's data")
else
	local SHADEWHISPER, BEHEST, REDRIDGE, SHAKEDOWN, HULFDAN, SI7 = 2259, 2260, 2281, 2298, 2299, 2300
	local leadIns = {SHADEWHISPER, BEHEST, SHAKEDOWN, HULFDAN, SI7}

	print("Rothro, a Night Elf rogue who did Erion Shadewhisper and Erion's Behest, then took Redridge Rendezvous")
	character("NightElf", {SHADEWHISPER, BEHEST}, {})
	login()
	check("before he takes it, the map keeps SI:7 at Keryn Sylvius", mapKeeps(SI7))
	ctx.inLog[REDRIDGE] = 1
	local shown = {}
	for _, questId in ipairs({SI7, SHAKEDOWN, HULFDAN}) do
		if mapKeeps(questId) then shown[#shown + 1] = questId end
	end
	check("with it in the log, the map hides SI:7, Kingly Shakedown and To Hulfdan!", #shown == 0, table.concat(shown, ", "))
	check("and keeps the two he did, Erion Shadewhisper and Erion's Behest", mapKeeps(SHADEWHISPER) and mapKeeps(BEHEST))
	turnIn(REDRIDGE)
	local unticked = {}
	for _, questId in ipairs(leadIns) do
		if env.qcCharacterCompletions[questId] ~= 1 then unticked[#unticked + 1] = questId end
	end
	check("handing it in ticks all five lead-ins, To Hulfdan! included", #unticked == 0, table.concat(unticked, ", "))
end

if not QUESTS[1679] then
	print("The level 10 warrior and mage quests: not in this game's data")
else
	local TRAINING, BARTLEBY, BEAT, VEJREK, MUREN, TORMUS, IRONBAND, VORLUS, ELANARIA, ELURA = 1638, 1639, 1640, 1678, 1679, 1680, 1681, 1683, 1684, 1686
	local PATH, THUNGRIM, UZZEK, DILLINGER, ULAG = 1498, 1502, 1505, 1818, 1819
	local JENNEA, MIRROR, BINK, GIZMONITOR, BALNIR, JUJU = 1860, 1861, 1879, 1880, 1882, 1884
	local SILITHUS_A, SILITHUS_H, SUPPLY_LINES, EARTH_DUROTAR, EARTH_DUROTAR_2, EARTH_MULGORE = 8275, 8276, 8280, 1516, 1517, 1519
	local leadIns = {TRAINING, MUREN, ELANARIA}
	local function needs(questId) return QC.qcPinQuestNeeds(questId, QC.qcQuestStatus.Of(questId, QUESTS[questId])) end
	local function unticked(list)
		local missing = {}
		for _, questId in ipairs(list) do
			if env.qcCharacterCompletions[questId] ~= 1 then missing[#missing + 1] = questId end
		end
		return table.concat(missing, ", ")
	end
	local faction = env.UnitFactionGroup
	local function horde(on) env.UnitFactionGroup = on and function() return "Horde", "Horde" end or faction end
	env.SERVICES_CONJUNCTION_OR = "or"

	print("The level 10 warrior quests' links")
	check("the three cities' lead-ins no longer shut each other out",
		not env.qcMutuallyExclusive[TRAINING] and not env.qcMutuallyExclusive[MUREN] and not env.qcMutuallyExclusive[ELANARIA])
	check("and are all listed for the clean-up", listed[TRAINING] and listed[MUREN] and listed[ELANARIA])

	print("A new Human warrior")
	ctx.class, ctx.level = "WARRIOR", 10
	character("Human", {}, {})
	login()
	check("Bartleby the Drunk, Vejrek and Vorlus Vilehoof can be taken without a lead-in",
		not needs(BARTLEBY) and not needs(VEJREK) and not needs(VORLUS), needs(BARTLEBY) or needs(VEJREK) or needs(VORLUS))
	local tormus = needs(TORMUS)
	check("Tormus Deepforge needs any of the three", tormus == "Requires Bartleby the Drunk or Vejrek or Vorlus Vilehoof", tormus)
	turnIn(TRAINING)
	check("handing in A Warrior's Training ticks neither Muren Stormpike nor Elanaria",
		env.qcCharacterCompletions[MUREN] == nil and env.qcCharacterCompletions[ELANARIA] == nil)
	ctx.inLog[BARTLEBY] = 1
	check("with Bartleby the Drunk in the log, the map hides the other two lead-ins", not mapKeeps(MUREN) and not mapKeeps(ELANARIA))
	ctx.inLog[BARTLEBY] = nil
	turnIn(VEJREK)
	check("handing in Vejrek ticks Bartleby the Drunk and Vorlus Vilehoof",
		env.qcCharacterCompletions[BARTLEBY] == 1 and env.qcCharacterCompletions[VORLUS] == 1)
	check("and the lead-ins still to do", unticked(leadIns) == "", unticked(leadIns))
	local blocked = {}
	for _, questId in ipairs({BEAT, TORMUS, IRONBAND, ELURA}) do
		if needs(questId) then blocked[#blocked + 1] = questId .. ": " .. needs(questId) end
	end
	check("then Beat Bartleby, Tormus Deepforge, Ironband's Compound and The Shade of Elura can all be taken", #blocked == 0, table.concat(blocked, "; "))
	turnIn(IRONBAND)
	check("handing in Ironband's Compound ticks Tormus Deepforge", env.qcCharacterCompletions[TORMUS] == 1)

	print("A Dwarf warrior with the old lead-in group's ticks")
	character("Dwarf", {MUREN}, {[TRAINING] = 1, [MUREN] = 1, [ELANARIA] = 1})
	login()
	check("before Vejrek, the ticks on the other two lead-ins go",
		env.qcCharacterCompletions[TRAINING] == nil and env.qcCharacterCompletions[ELANARIA] == nil and env.qcCharacterCompletions[MUREN] == 1)
	character("Dwarf", {MUREN, VEJREK}, {[TRAINING] = 1, [MUREN] = 1, [ELANARIA] = 1})
	login()
	check("after Vejrek, all three stay ticked, as it closes them", unticked(leadIns) == "", unticked(leadIns))

	print("A Tauren warrior who did Speak with Dillinger and Ulag the Cleaver")
	horde(true)
	character("Tauren", {DILLINGER, ULAG}, {})
	login()
	check("Path of Defense is ticked, as Ulag the Cleaver shuts it out", env.qcCharacterCompletions[PATH] == 1)
	check("and Veteran Uzzek, which it closes", env.qcCharacterCompletions[UZZEK] == 1)
	check("Thun'grim Firegaze can be taken", not needs(THUNGRIM), needs(THUNGRIM))

	print("Mages")
	ctx.class = "MAGE"
	check("The Balnir Farmstead and Ju-Ju Heaps shut each other out", env.qcMutuallyExclusive[BALNIR] and env.qcMutuallyExclusive[BALNIR][1] == JUJU)
	horde(false)
	character("Gnome", {BINK, GIZMONITOR}, {[JENNEA] = 1})
	login()
	check("a Gnome who did Speak with Bink loses the old group's tick on Speak with Jennea", env.qcCharacterCompletions[JENNEA] == nil)
	check("and Mage-tastic Gizmonitor ticks Mirror Lake", env.qcCharacterCompletions[MIRROR] == 1)

	print("Securing the Supply Lines")
	ctx.class, ctx.level = "WARRIOR", 60
	character("Human", {SILITHUS_A}, {[SUPPLY_LINES] = 1})
	login()
	check("the tick Taking Back Silithus gave Securing the Supply Lines goes", env.qcCharacterCompletions[SUPPLY_LINES] == nil)
	turnIn(SUPPLY_LINES)
	check("handing it in ticks both breadcrumbs", env.qcCharacterCompletions[SILITHUS_A] == 1 and env.qcCharacterCompletions[SILITHUS_H] == 1)

	print("An Orc shaman's Call of Earth")
	ctx.class, ctx.level = "SHAMAN", 4
	horde(true)
	character("Orc", {}, {})
	login()
	turnIn(EARTH_MULGORE)
	check("handing in Mulgore's ticks Durotar's", env.qcCharacterCompletions[EARTH_DUROTAR] == 1)
	check("and Durotar's second step can be taken", not needs(EARTH_DUROTAR_2), needs(EARTH_DUROTAR_2))
	horde(false)

	print("Prerequisites")
	ctx.class, ctx.level = "WARRIOR", 30
	character("Human", {}, {})
	login()
	local coral = needs(1708)
	check("for a Human, Iron Coral needs Furen's Armor, not the Dwarf and Gnome breadcrumb", coral == "Requires Furen's Armor", coral)
	local kept = {}
	for _, questId in ipairs({364, 429, 455, 639, 1275, 1302, 1920, 1944}) do
		if env.qcQuestPrereq[questId] then kept[#kept + 1] = questId end
	end
	check("the eight quests that don't need their breadcrumb have no prerequisite", #kept == 0, table.concat(kept, ", "))
	ctx.class, ctx.level = "ROGUE", 16
end

print(failures == 0 and "All checks passed." or (failures .. " checks failed."))
os.exit(failures == 0 and 0 or 1)
