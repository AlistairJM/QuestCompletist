--[[
Checks what the zone icons on the continent maps are built from (docs/plans/continent-pins.md): the zones a
continent map gets an icon for, the categories each counts, and what is left to do in it.

Loads the addon's own files with stand-ins for the WoW API and drives the real zone list, counting and
filters. The zone list is checked against a made-up continent, with the cases the game can give: no
rectangle, a rectangle of nothing, twins, a city beside its zone, a zone filed under other zones' categories,
a child that is not a zone, and no answer at all. The counting is checked on a character built step by
step: quests done, in the log, ready, locked by level and done on another character, and the daily and
weekly quests that must never count. Then, with the client's UiMap table (tools\UiMap.csv for retail,
tools\UiMap-1.60.1.70338.csv for Forever, if present), every continent of the game gets its zones, the
sum over zones is checked against the quest list's own zone counter, and one continent pass is timed.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-ContinentPins.lua
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-ContinentPins.lua QuestCompletist QuestCompletist_Camelot.toc tools\UiMap-1.60.1.70338.csv
Prints each check and exits with 1 if one fails. Run it for both games' TOCs.
]]

local ADDON_DIR = arg and arg[1] or "QuestCompletist"
local TOC_FILE = arg and arg[2] or "QuestCompletist.toc"
local UIMAP_FILE = arg and arg[3] or (TOC_FILE == "QuestCompletist.toc" and "tools/UiMap.csv" or "tools/UiMap-1.60.1.70338.csv")
local FOREVER = TOC_FILE ~= "QuestCompletist.toc"

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

--[[ The map tree the stand-in game answers from: S.children[parent] is a list of {mapID, name, mapType}, S.rects[child]
holds the rectangle {minX, maxX, minY, maxY} on a continent, S.nothing[parent] makes the game list nothing ]]--
local S = {children = {}, rects = {}, nothing = {}, types = {}, level = 1000, inLog = {}, logComplete = {}, accountDone = {},
	modifier = false}
local ZONE, DUNGEON, CONTINENT = 3, 4, 2

local env = {
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
	debugprofilestop = function() return os.clock() * 1000 end,
	CreateFromMixins = function() return {} end,
	CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end,
	Enum = {UIMapType = {Cosmic = 0, World = 1, Continent = CONTINENT, Zone = ZONE, Dungeon = DUNGEON}},
	C_Map = {
		GetMapChildrenInfo = function(mapID, mapType)
			if S.nothing[mapID] then return nil end
			local list = {}
			for _, child in ipairs(S.children[mapID] or {}) do
				if mapType == nil or child.mapType == mapType then list[#list + 1] = child end
			end
			return list
		end,
		GetMapRectOnMap = function(childID)
			local rect = S.rects[childID]
			if rect then return rect[1], rect[2], rect[3], rect[4] end
		end,
		GetMapInfo = function(mapID) return {mapID = mapID, mapType = S.types[mapID] or ZONE} end,
	},
	C_CreatureInfo = {GetRaceInfo = function() return nil end},
	LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, {__index = function(_, token) return token end}),
	UIParent = dummy,
	WorldMapFrame = {HookScript = function() end, AddDataProvider = function() end},
	IsShiftKeyDown = function() return false end,
	IsModifierKeyDown = function() return S.modifier end,
	IsInInstance = function() return false end,
	C_AddOns = {IsAddOnLoaded = function() return false end},
	UnitFactionGroup = function() return "Alliance", "Alliance" end,
	UnitRace = function() return "NightElf", "NightElf" end,
	UnitClass = function() return "DRUID", "DRUID" end,
	UnitLevel = function() return S.level end,
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
		GetLogIndexForQuestID = function(questId) return S.inLog[questId] end,
		IsComplete = function(questId) return S.logComplete[questId] == true end,
		IsQuestFlaggedCompleted = function() return false end,
		IsQuestFlaggedCompletedOnAccount = function(questId) return S.accountDone[questId] == true end,
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
local code
for line in readFile(ADDON_DIR .. "/" .. TOC_FILE):gmatch("[^\r\n]+") do
	local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
	if file and file:sub(1, 4) ~= "Libs" then
		local source = readFile(ADDON_DIR .. "/" .. file)
		if file == "qcContinentPins.lua" then
			source = source .. [[

return {Zones = qcContinentZones, Numbers = qcZoneNumbers, Look = qcZoneLook, Kind = qcQuestKind,
	Icons = qcContinentIcons}]]
		end
		local chunk = assert(loadstring(source, "@" .. ADDON_DIR .. "/" .. file))
		setfenv(chunk, env)
		local result = chunk("QuestCompletist", QC)
		if file == "qcContinentPins.lua" then code = result end
	end
end
assert(code and code.Zones, "qcContinentPins.lua is not in the TOC")

local QUESTS = env.qcQuestDatabase
local BY_AREA = env.qcAreaIDToCategoryID

local function settings(overrides)
	env.qcSettings = {}
	env.qcCheckSettings()
	env.qcSettings.QC_M_HIDE_SEASONAL = 0
	for key, value in pairs(overrides or {}) do env.qcSettings[key] = value end
end
settings()
env.qcCharacterCompletions = {}

local failures = 0
local function check(label, passed, detail)
	if not passed then failures = failures + 1 end
	print(string.format("  [%s] %s%s", passed and "ok" or "FAIL", label, detail and (" (" .. detail .. ")") or ""))
end

local function listOf(t)
	local parts = {}
	for _, v in ipairs(t) do parts[#parts + 1] = tostring(v) end
	return table.concat(parts, ",")
end

--[[ Categories by quest, and which of them have an ordinary quest ]]--
local categories = {}
for questId, e in pairs(QUESTS) do
	categories[e[3]] = categories[e[3]] or {}
	table.insert(categories[e[3]], questId)
end
for _, list in pairs(categories) do table.sort(list) end
local function isRecurring(questId) return bit.band(QUESTS[questId][4], 2 + 4 + 128) ~= 0 end

--[[ A made-up continent of this game's own zones ]]--
local function mapIdsWithCategory()
	local ids = {}
	for mapId in pairs(BY_AREA) do ids[#ids + 1] = mapId end
	table.sort(ids)
	return ids
end
local ids = mapIdsWithCategory()
local function nextWith(predicate, after)
	for _, mapId in ipairs(ids) do
		if mapId > (after or 0) and predicate(mapId) then return mapId end
	end
end
local function notSpecial(mapId)
	return mapId ~= 224 and mapId ~= 203
end
local CITY, HOST = 84, 37
if FOREVER then CITY, HOST = 1453, 1429 end
local EXTRA = (not FOREVER) and 224 or nil
-- Each plain zone has a category of its own, so none is another's twin.
local usedCategories = {[BY_AREA[HOST]] = true, [BY_AREA[CITY]] = true}
local function plainZone(after)
	local mapId = nextWith(function(m) return notSpecial(m) and not usedCategories[BY_AREA[m]] end, after)
	usedCategories[BY_AREA[mapId]] = true
	return mapId
end
local p1 = plainZone()
local p2 = plainZone(p1)
local p3 = plainZone(p2)
local p4 = plainZone(p3)
-- Two map IDs sharing a category: the lower has no rectangle, the higher has one.
local twinLow, twinHigh
local used = {}
for _, mapId in ipairs({p1, p2, p3, p4, CITY, HOST}) do used[BY_AREA[mapId]] = true end
for _, a in ipairs(ids) do
	for _, b in ipairs(ids) do
		if not twinLow and a < b and BY_AREA[a] == BY_AREA[b] and not used[BY_AREA[a]] and notSpecial(a) and notSpecial(b) then
			twinLow, twinHigh = a, b
		end
	end
end
local CONT = 7777
local function zone(mapId, name, mapType) return {mapID = mapId, name = name, mapType = mapType or ZONE} end
S.children[CONT] = {
	zone(HOST, "Host"), zone(CITY, "City"), zone(p1, "One"), zone(p2, "Two (no rectangle)"), zone(p3, "Three (flat)"),
	zone(p4, "Four (wrong type)", DUNGEON), zone(990001, "No category"), zone(twinHigh or 990002, "Twin high"), zone(twinLow or 990003, "Twin low"),
}
if EXTRA then table.insert(S.children[CONT], zone(EXTRA, "Stranglethorn")) end
S.rects[HOST] = {0.30, 0.40, 0.50, 0.60}
S.rects[CITY] = {0.33, 0.37, 0.53, 0.57}
S.rects[p1] = {0.10, 0.20, 0.10, 0.30}
S.rects[p3] = {0.50, 0.50, 0.10, 0.20}
S.rects[p4] = {0.60, 0.70, 0.60, 0.70}
S.rects[990001] = {0.80, 0.90, 0.10, 0.20}
if twinHigh then S.rects[twinHigh] = {0.60, 0.70, 0.10, 0.20} end
if EXTRA then S.rects[EXTRA] = {0.70, 0.80, 0.30, 0.50} end

print("The zone list of a made-up continent")
local zones = code.Zones(CONT)
local byId = {}
for _, z in ipairs(zones) do byId[z.mapId] = z end
check("the zones are in map ID order", (function() for i = 2, #zones do if zones[i - 1].mapId >= zones[i].mapId then return false end end return true end)())
check("a zone with a rectangle and a category has an icon", byId[p1] ~= nil)
check("it sits at the rectangle's centre", byId[p1] and math.abs(byId[p1].x - 0.15) < 1e-9 and math.abs(byId[p1].y - 0.20) < 1e-9)
check("with its name from the game", byId[p1] and byId[p1].name == "One")
check("and the zone's own category", byId[p1] and byId[p1].categories[1] == BY_AREA[p1] and #byId[p1].categories == 1)
check("a zone the game gives no rectangle has no icon", byId[p2] == nil)
check("nor does one whose rectangle has no width", byId[p3] == nil)
check("nor a child that is not a zone", byId[p4] == nil)
check("nor a zone with no category", byId[990001] == nil)
if twinHigh then
	check("twins share one icon, the one with a rectangle", byId[twinHigh] ~= nil and byId[twinLow] == nil)
else
	print("  (no two maps share a category in this game's data: twins are not checked)")
end
check("a city is folded into its zone: no icon of its own", byId[CITY] == nil)
check("the zone's icon counts both categories", byId[HOST] and #byId[HOST].categories == 2 and byId[HOST].categories[1] == BY_AREA[HOST]
	and byId[HOST].categories[2] == BY_AREA[CITY], byId[HOST] and listOf(byId[HOST].categories))
if EXTRA then
	check("a zone filed under its parts' categories counts them", byId[EXTRA] and listOf(byId[EXTRA].categories) == "147,214", byId[EXTRA] and listOf(byId[EXTRA].categories))
	local vashjir = {zone(203, "Vashj'ir")}
	S.children[CONT + 1] = vashjir
	S.rects[203] = {0.1, 0.2, 0.1, 0.2}
	local v = code.Zones(CONT + 1)[1]
	check("Vashj'ir counts its own category and its three parts'", v and listOf(v.categories) == "264,117,182,1", v and listOf(v.categories))
end

S.children[CONT + 2] = {zone(CITY, "City")}
S.rects[CITY] = {0.33, 0.37, 0.53, 0.57}
local alone = code.Zones(CONT + 2)
check("a city whose zone is not on the map keeps its own icon", #alone == 1 and alone[1].mapId == CITY and listOf(alone[1].categories) == tostring(BY_AREA[CITY]))
S.children[CONT + 3] = {zone(CITY, "City"), zone(HOST, "Host")}
S.rects[HOST] = nil
local noHostRect = code.Zones(CONT + 3)
check("nor does a city whose zone has no rectangle lose its quests", #noHostRect == 1 and noHostRect[1].mapId == CITY)
S.rects[HOST] = {0.30, 0.40, 0.50, 0.60}
local after = nextWith(function(m) return notSpecial(m) and m > CITY and not usedCategories[BY_AREA[m]] end)
if after then
	S.children[CONT + 6] = {zone(after, "After"), zone(CITY, "City")}
	S.rects[after] = {0.10, 0.20, 0.10, 0.20}
	local ordered = code.Zones(CONT + 6)
	check("a city that keeps its own icon is in map ID order too", #ordered == 2 and ordered[1].mapId == CITY and ordered[2].mapId == after)
end
S.nothing[CONT + 4] = true
check("a continent the game lists nothing for has no zones", #code.Zones(CONT + 4) == 0)
check("nor one with no children", #code.Zones(CONT + 5) == 0)

print("What counts in a zone")
local function counted(categoryIds, keep)
	return env.qcGetZoneQuests(categoryIds, keep or QC.qcBuildViewFilter("M"))
end
-- The category with the most ordinary quests, and one with daily quests as well.
local bigCategory, bigCount = nil, 0
local recurringCategory
for categoryId, list in pairs(categories) do
	local n, hasRecurring = 0, false
	for _, questId in ipairs(list) do
		if isRecurring(questId) then hasRecurring = true else n = n + 1 end
	end
	if n > bigCount or (n == bigCount and n > 0 and categoryId < bigCategory) then bigCategory, bigCount = categoryId, n end
	if hasRecurring and n >= 5 and (not recurringCategory or categoryId < recurringCategory) then recurringCategory = categoryId end
end
local keep = QC.qcBuildViewFilter("M")
local list = counted({bigCategory}, keep)
check("quests come from the categories named", #list > 0)
local allIn = true
for _, questId in ipairs(list) do if QUESTS[questId][3] ~= bigCategory then allIn = false end end
check("and only from them", allIn)
local otherCategory
for categoryId, members in pairs(categories) do
	if categoryId ~= bigCategory and #members >= 5 and (not otherCategory or categoryId < otherCategory) then otherCategory = categoryId end
end
local inBig = {}
for _, questId in ipairs(list) do inBig[questId] = true end
local shared = 0
for _, questId in ipairs(counted({otherCategory}, keep)) do if inBig[questId] then shared = shared + 1 end end
check("each quest is in one category, so two categories never count the same quest", shared == 0 and #counted({bigCategory, otherCategory}, keep) == #list + #counted({otherCategory}, keep))

settings({QC_M_HIDE_DAILYQUEST = 0, QC_M_HIDE_REPEATABLEQUEST = 0, QC_M_HIDE_WORLDQUEST = 0})
keep = QC.qcBuildViewFilter("M")
local withDaily = counted({recurringCategory}, keep)
local anyRecurring = false
for _, questId in ipairs(withDaily) do if isRecurring(questId) then anyRecurring = true end end
check("daily, weekly and repeatable quests never count, with their filters off", not anyRecurring and #withDaily > 0)
local recurringId
for _, questId in ipairs(categories[recurringCategory]) do if isRecurring(questId) then recurringId = questId end end
S.inLog[recurringId] = 1
local numbers = code.Numbers({categories = {recurringCategory}}, keep, false)
check("a daily in the log is no quest in progress", numbers.progress == 0 and numbers.total == #withDaily)
S.inLog[recurringId] = nil
settings()

print("Zone counts follow the quest list's own zone counter")
local listKeep = QC.qcBuildViewFilter("L")
local mismatches, checked = {}, 0
for categoryId in pairs(categories) do
	local _, total = env.qcGetZoneCompletionStats(categoryId)
	local mine = #counted({categoryId}, listKeep)
	checked = checked + 1
	if total ~= mine then mismatches[#mismatches + 1] = categoryId end
end
table.sort(mismatches)
check("each category counts as many quests as the list's counter says, with the list's own filter, " .. checked .. " categories",
	#mismatches == 0, #mismatches .. " differ: " .. listOf(mismatches))

print("Numbers for a character, step by step")
S.level = 1000
env.qcCharacterCompletions = {}
local zoneNumbers = {categories = {bigCategory}}
local base = code.Numbers(zoneNumbers, keep, false)
check("a new character has nothing done, ready or in the log", base.done == 0 and base.ready == 0 and base.progress == 0)
check("every counted quest is available or locked", base.available + base.locked == base.total and base.total > 0, tostring(base.total))
check("and some can be taken", base.available > 0)
local counted1 = counted({bigCategory}, keep)
table.sort(counted1)
local sample = {}
for _, questId in ipairs(counted1) do
	if code.Kind(questId, false) == "available" and #sample < 6 then sample[#sample + 1] = questId end
end
check("six quests that can be taken were found", #sample == 6)
for i = 1, 3 do env.qcCharacterCompletions[sample[i]] = 1 end
local afterDone = code.Numbers(zoneNumbers, keep, false)
check("three quests done", afterDone.done == 3 and afterDone.total == base.total)
check("and no longer available", afterDone.available == base.available - 3)
S.inLog[sample[4]] = 1
S.inLog[sample[5]] = 1
S.logComplete[sample[5]] = true
local afterLog = code.Numbers(zoneNumbers, keep, false)
check("a quest in the log is in progress", afterLog.progress == 1)
check("one ready to hand in is ready", afterLog.ready == 1)
check("both leave the available ones", afterLog.available == base.available - 5)
check("the numbers add up", afterLog.done + afterLog.ready + afterLog.progress + afterLog.locked + afterLog.available == afterLog.total)
S.accountDone[sample[6]] = true
check("another character's completion is not this one's, unless the warband filter counts it", code.Numbers(zoneNumbers, keep, false).done == 3)
check("with it, it is", code.Numbers(zoneNumbers, keep, true).done == 4)
S.accountDone[sample[6]] = nil
S.level = 1
local lowLevel = code.Numbers(zoneNumbers, keep, false)
check("at level 1 more quests are locked", lowLevel.locked > afterLog.locked and lowLevel.available < afterLog.available)
check("in the same total", lowLevel.total == afterLog.total)
check("what is done stays done, and the log stays the log", lowLevel.done == 3 and lowLevel.ready == 1 and lowLevel.progress == 1)
S.level = 1000

print("Which icon a zone gets, and the count on it")
env.qcCharacterCompletions = {}
S.inLog, S.logComplete = {}, {}
local NORMAL, READY, PROGRESS = QC.QC_ICON_NORMAL, QC.QC_ICON_READY, QC.QC_ICON_PROGRESS
local function lookOf()
	local numbers = code.Numbers(zoneNumbers, keep, false)
	local icon, count, dim = code.Look(numbers)
	return icon, count, dim, numbers
end
local function finishAllBut(questId)
	env.qcCharacterCompletions = {}
	for _, id in ipairs(counted1) do
		if id ~= questId then env.qcCharacterCompletions[id] = 1 end
	end
end
local icon, count, dim, fresh = lookOf()
check("a zone with quests to take gets the quest icon, bright, with their count", icon == NORMAL and not dim and count == fresh.available and count > 0)
finishAllBut(nil)
check("a zone with everything done gets no icon", lookOf() == nil)
local takeable = sample[1]
finishAllBut(takeable)
icon, count, dim = lookOf()
check("a zone with one quest left to take counts it", icon == NORMAL and count == 1 and not dim)
S.inLog[takeable] = 1
icon, count, dim = lookOf()
check("a zone with only a quest in the log gets the log's icon", icon == PROGRESS and count == 1 and not dim)
S.logComplete[takeable] = true
icon, count, dim = lookOf()
check("a quest ready to hand in gets its icon", icon == READY and count == 1 and not dim)
finishAllBut(nil)
S.inLog, S.logComplete = {}, {}
local ready, taken = counted1[1], counted1[2]
env.qcCharacterCompletions = {}
for _, id in ipairs(counted1) do if id ~= ready and id ~= taken then env.qcCharacterCompletions[id] = 1 end end
S.inLog[ready], S.logComplete[ready] = 1, true
icon, count = lookOf()
check("a ready quest outranks one to take, and the count is the ready ones", icon == READY and count == 1)
S.inLog, S.logComplete = {}, {}
S.level = 1
local locked
for _, questId in ipairs(counted1) do
	if not locked and code.Kind(questId, false) == "locked" then locked = questId end
end
check("a quest locked at level 1 was found", locked ~= nil)
finishAllBut(locked)
icon, count, dim = lookOf()
check("a zone with only a locked quest left gets the quest icon, dimmed", icon == NORMAL and count == 1 and dim == true)
S.level = 1000
env.qcCharacterCompletions = {}

print("One pass over a continent")
local icons = code.Icons(CONT)
local iconIds = {}
for _, icon in ipairs(icons) do iconIds[#iconIds + 1] = icon.zone.mapId end
check("each zone with something to do gets an icon", #icons == #zones, #icons .. " icons for " .. #zones .. " zones")
check("with its zone, its icon, its count and its shade", icons[1] and icons[1].zone.mapId == zones[1].mapId and icons[1].look ~= nil
	and icons[1].count > 0 and type(icons[1].dim) == "boolean")
for _, icon in ipairs(icons) do
	for _, categoryId in ipairs(icon.zone.categories) do
		for _, questId in ipairs(categories[categoryId] or {}) do env.qcCharacterCompletions[questId] = 1 end
	end
end
check("a zone with all its quests done is left out", #code.Icons(CONT) == 0)
env.qcCharacterCompletions = {}

print("The provider draws a continent's icons")
S.types[CONT] = CONTINENT
local map = {mapId = CONT, pins = {}, removed = {}}
function map:GetMapID() return self.mapId end
function map:RemoveAllPinsByTemplate(template) self.removed[#self.removed + 1] = template; self.pins = {} end
function map:AcquirePin(template, data) self.pins[#self.pins + 1] = {template = template, data = data} end
local provider = env.qcContinentDataProvider
check("the provider exists", provider ~= nil and type(provider.RefreshAllData) == "function")
provider.GetMap = function() return map end
provider:RefreshAllData()
local expected = #code.Icons(CONT)
check("a continent's map gets a pin for each icon", expected > 0 and #map.pins == expected, #map.pins .. " pins for " .. expected .. " icons")
check("of the continent pin's template", map.pins[1] and map.pins[1].template == "qcContinentPinTemplate")
check("having first cleared that template and no other", #map.removed == 1 and map.removed[1] == "qcContinentPinTemplate")
check("each pin is handed its icon", map.pins[1] and map.pins[1].data.zone ~= nil and map.pins[1].data.look ~= nil)
provider:RefreshAllData()
check("a second refresh draws them again, not twice", #map.pins == expected and #map.removed == 2)
map.mapId = p1
S.children[p1] = S.children[CONT]
provider:RefreshAllData()
check("a zone's map gets none of them, whatever it lists as children", #map.pins == 0)
S.children[p1] = nil
map.mapId = CONT
settings({QC_M_SHOW_ICONS = 0})
provider:RefreshAllData()
check("with the map icons off it gets none", #map.pins == 0)
settings({QC_M_SHOW_CONTINENT = 0})
provider:RefreshAllData()
check("with the continent icons off it gets none", #map.pins == 0)
settings()
check("the continent icons are on by default", env.qcSettings.QC_M_SHOW_CONTINENT == 1)
provider:RefreshAllData()
check("and back on they return", #map.pins == expected)
for _, pinned in ipairs(map.pins) do
	for _, categoryId in ipairs(pinned.data.zone.categories) do
		for _, questId in ipairs(categories[categoryId] or {}) do env.qcCharacterCompletions[questId] = 1 end
	end
end
provider:RefreshAllData()
check("a continent with everything done gets none", #map.pins == 0)
env.qcCharacterCompletions = {}
provider.GetMap = function() return nil end
check("a provider on no map does nothing", pcall(provider.RefreshAllData, provider))
provider.GetMap = function() return map end

print("A continent pin takes its icon, and a click opens the zone")
local mixin = env.qcContinentPinMixin
local function newPin()
	local pin = {log = {}}
	local function put(line) pin.log[#pin.log + 1] = line end
	pin.UseFrameLevelType = function(_, name) put("level " .. name) end
	pin.SetScalingLimits = function(_, ...) put("scaling " .. table.concat({...}, ",")) end
	pin.SetPosition = function(_, x, y) put(string.format("position %.4f %.4f", x, y)) end
	pin.SetSize = function(_, w, h) put("size " .. w .. "x" .. h) end
	pin.Texture = {SetTexCoord = function() end, SetAtlas = function(_, atlas) pin.atlas = atlas end,
		SetTexture = function(_, file) pin.file = file end, SetVertexColor = function(_, r) pin.shade = r end}
	pin.Count = {SetText = function(_, t) pin.count = t end, SetTextColor = function(_, r) pin.countShade = r end}
	pin.GetMap = function() return pin.map end
	return setmetatable(pin, {__index = mixin})
end
local pin = newPin()
pin:OnLoad()
check("a pin is made at the area marker level, at a size that doesn't scale", pin.log[1] == "level PIN_FRAME_LEVEL_AREA_POI" and pin.log[2] == "scaling 1,1,1", table.concat(pin.log, "; "))
local zoneA = zones[1]
local bright = {zone = zoneA, look = NORMAL, count = 7, dim = false}
pin = newPin()
pin:OnAcquired(bright)
check("its level is set before its position", pin.log[1] == "level PIN_FRAME_LEVEL_AREA_POI" and pin.log[2]:find("^position"), table.concat(pin.log, "; "))
check("it sits at the zone's centre", pin.log[2] == string.format("position %.4f %.4f", zoneA.x, zoneA.y))
check("at 24 by 24", pin.log[3] == "size 24x24")
check("with the icon's art", (NORMAL.file and pin.file == NORMAL.file) or (NORMAL.atlas and pin.atlas == NORMAL.atlas))
check("and its count, at full shade", pin.count == 7 and pin.shade == 1 and pin.countShade == 1)
pin:OnAcquired({zone = zoneA, look = PROGRESS, count = 12, dim = true})
check("a pin used again takes the new icon's count and shade", pin.count == 12 and pin.shade == 0.5 and pin.countShade == 0.5)
check("and its zone", pin.Icon.zone == zoneA)
local opened
pin.map = {SetMapID = function(_, mapId) opened = mapId end}
pin:OnMouseClickAction("RightButton")
check("a right click does not open the zone", opened == nil)
S.modifier = true
pin:OnMouseClickAction("LeftButton")
check("nor does a left click with a modifier", opened == nil)
S.modifier = false
pin:OnMouseClickAction("LeftButton")
check("a left click opens the zone's map", opened == zoneA.mapId)
pin.map = nil
check("a click on a pin with no map does nothing", pcall(pin.OnMouseClickAction, pin, "LeftButton"))
env.qcCharacterCompletions = {}

--[[ The game's own continents, from its UiMap table ]]--
print("Every continent of the game")
local handle = io.open(UIMAP_FILE, "rb")
if not handle then
	print("  (no " .. UIMAP_FILE .. ": the real continents are not checked)")
else
	local header = handle:read("*l")
	local columns = {}
	local index = 0
	for column in header:gmatch('[^,]+') do index = index + 1; columns[column:gsub('"', ""):gsub("\r", "")] = index end
	local rows = {}
	for line in handle:lines() do
		local fields, position = {}, 1
		line = line:gsub("\r$", "")
		while position <= #line + 1 do
			local value
			if line:sub(position, position) == '"' then
				local closing = line:find('"', position + 1, true)
				value = line:sub(position + 1, closing - 1)
				position = closing + 2
			else
				local comma = line:find(",", position, true) or (#line + 1)
				value = line:sub(position, comma - 1)
				position = comma + 1
			end
			fields[#fields + 1] = value
		end
		rows[#rows + 1] = {id = tonumber(fields[columns.ID]), name = fields[columns.Name_lang], parent = tonumber(fields[columns.ParentUiMapID]),
			mapType = tonumber(fields[columns.Type]), system = tonumber(fields[columns.System])}
	end
	handle:close()
	S.children, S.rects = {}, {}
	local continents = {}
	for _, row in ipairs(rows) do
		if row.mapType == ZONE and row.parent and row.parent ~= 0 then
			S.children[row.parent] = S.children[row.parent] or {}
			table.insert(S.children[row.parent], {mapID = row.id, name = row.name, mapType = ZONE})
		end
		if row.mapType == CONTINENT and row.system == 0 then continents[#continents + 1] = row end
	end
	table.sort(continents, function(a, b) return a.id < b.id end)
	-- Every zone gets a rectangle of its own on its continent, so only the grouping is tested here.
	local n = 0
	for _, children in pairs(S.children) do
		for i, child in ipairs(children) do
			n = n + 1
			S.rects[child.mapID] = {0.001 * (i % 500), 0.001 * (i % 500) + 0.0005, 0.001 * (i % 300), 0.001 * (i % 300) + 0.0005}
		end
	end
	local owner, total, groups, withZones = {}, 0, 0, 0
	local doubled = {}
	for _, continent in ipairs(continents) do
		local zonesOf = code.Zones(continent.id)
		if #zonesOf > 0 then withZones = withZones + 1 end
		for _, z in ipairs(zonesOf) do
			groups = groups + 1
			for _, categoryId in ipairs(z.categories) do
				if owner[categoryId] and owner[categoryId] ~= z.mapId then doubled[#doubled + 1] = categoryId end
				owner[categoryId] = z.mapId
			end
		end
	end
	check(string.format("%d continents give %d icons for zones with a category", withZones, groups), groups > 0)
	check("no category belongs to two icons", #doubled == 0, #doubled .. " do")
	-- The sum of what the icons count, with the list's filter, against the distinct quests: nothing counted twice.
	local distinct, sum = {}, 0
	for _, continent in ipairs(continents) do
		for _, z in ipairs(code.Zones(continent.id)) do
			local quests = counted(z.categories, listKeep)
			sum = sum + #quests
			for _, questId in ipairs(quests) do distinct[questId] = true end
		end
	end
	local distinctCount = 0
	for _ in pairs(distinct) do distinctCount = distinctCount + 1 end
	check("no quest is counted in two icons, " .. sum .. " quests", sum == distinctCount, sum .. " counted, " .. distinctCount .. " distinct")
	-- A pass over each continent, timed.
	local worst, worstId = 0, nil
	local started = os.clock()
	for _, continent in ipairs(continents) do
		local before = os.clock()
		code.Icons(continent.id)
		local took = (os.clock() - before) * 1000
		if took > worst then worst, worstId = took, continent.id end
	end
	print(string.format("  (every continent in %.0f ms; the slowest, map %s, %.1f ms)", (os.clock() - started) * 1000, tostring(worstId), worst))
end

print(failures == 0 and "All checks passed." or (failures .. " checks failed."))
os.exit(failures == 0 and 0 or 1)
