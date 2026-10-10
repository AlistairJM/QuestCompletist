--[[
Checks that every quest and map pin in the addon can actually be displayed by some character.

Loads the addon's own files with stand-ins for the WoW API, then drives the real list filter
(qcBuildViewFilter("L")) and the real map pin pipeline (qcMapDataProvider:RefreshAllData). Nothing
is re-implemented here, so the check can't drift from what the addon does.

Two settings tiers are checked:
  all filters off  - anything hidden here can never be displayed, whatever the settings.
  identity filters - faction, race/class, profession, covenant, seasonal, no-data and
                     requirements-not-met on; everything else off. Anything hidden here is hidden
                     from every possible character, which means contradictory data.
Progress is best case: max level, every prerequisite done, max renown, nothing completed, and the
character has every profession, at the highest skill.

The calendar is a stand-in that shows no holiday, then each of qcHolidays in turn. An event the calendar
never shows, such as the Scourge Invasion, can't be on, so its pins get a section of their own.

The minimum level is checked at character levels 1, 10, 30 and 60: the tooltip's "Requires Level" line,
the grey pins and the requirements filter must follow each quest's minLevel (else its level) in the data
file qcQuestData.lua was built from, while the low-level filter and the bracket and sort of the list (its
first 16 rows in each category) must still follow its level. A level of 0 or below is no level: the
row prints the bare name and the low-level filter keeps the quest, which made-up quests check apart from
the data. Any wrong reading fails the run (exit status 1).

Trying every race, class, covenant and holiday together is ~28k combinations per map, far too slow.
Each filter group only reads its own part of the character (faction and race/class read race,
faction and class; covenant reads the covenant; seasonal reads the calendar), so each group is swept on
its own, and anything every group lets through is confirmed with all of them on at once.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-QuestReachability.lua
Writes the full report to tools\reachability-report.txt and a summary to the console.
tools\UiMap.csv, if present, is used to flag pins on map IDs the client doesn't have.
For WoW: Forever, name its TOC and its client's UiMap table (the report gets the TOC's name):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-QuestReachability.lua QuestCompletist tools QuestCompletist_Camelot.toc tools\UiMap-1.60.1.70205.csv
]]

local ADDON_DIR = arg and arg[1] or "QuestCompletist"
local TOOLS_DIR = arg and arg[2] or "tools"
local TOC_FILE = arg and arg[3] or "QuestCompletist.toc"
local UIMAP_FILE = arg and arg[4] or (TOOLS_DIR .. "/UiMap.csv")
local REPORT_FILE = TOOLS_DIR .. "/reachability-report" .. (TOC_FILE == "QuestCompletist.toc" and "" or ("-" .. TOC_FILE:gsub("%.toc$", ""))) .. ".txt"
local realPrint = print

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

--[[ Stand-ins for the WoW API ]]--
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

local P = {}
local PROFESSION_SKILLS = {}
local PROFESSION_INDEXES = {}

-- Today's calendar: an event no quest follows, plus the profile's holiday if it has one.
local NOW = {year = 2026, month = 6, monthDay = 15, weekday = 2, hour = 12, minute = 0}
local function todayEvent(eventID)
	return {calendarType = "HOLIDAY", eventID = eventID, title = "event " .. eventID,
		startTime = {year = NOW.year, month = NOW.month, monthDay = 1, hour = 0, minute = 0},
		endTime = {year = NOW.year, month = NOW.month, monthDay = 30, hour = 0, minute = 0}}
end
local calendar = stubTable({
	SetAbsMonth = function() end,
	GetMonthInfo = function() return {year = NOW.year, month = NOW.month, numDays = 30, firstWeekday = 1} end,
	GetNumDayEvents = function() return (P.holiday or 0) ~= 0 and 2 or 1 end,
	GetDayEvent = function(_, _, index) return todayEvent(index == 1 and 0 or P.holiday) end,
})

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
	date = os.date,
	time = os.time,
	CreateFromMixins = function() return {} end,
	C_Calendar = calendar,
	C_DateAndTime = stubTable({GetCurrentCalendarTime = function() return NOW end}),
	UnitFactionGroup = function() return P.faction, P.faction end,
	UnitRace = function() return P.race, P.race end,
	UnitClass = function() return P.class, P.class end,
	UnitLevel = function() return P.level or 1000 end,
	ITEM_MIN_LEVEL = "Requires Level %d",
	UnitQuestTrivialLevelRange = function() return 5 end,
	GetProfessions = function() return unpack(PROFESSION_INDEXES) end,
	GetProfessionInfo = function(index) return nil, nil, nil, nil, nil, nil, PROFESSION_SKILLS[index] end,
	C_Covenants = stubTable({GetActiveCovenantID = function() return P.covenant end}),
	C_MajorFactions = stubTable({GetCurrentRenownLevel = function() return 1000 end}),
	C_SkillInfo = stubTable({GetSkillLineInfoByID = function() return {rank = 1000, modifier = 0} end}),
	C_QuestLog = stubTable({
		GetLogIndexForQuestID = function() return nil end,
		IsQuestFlaggedCompleted = function() return true end,
		IsQuestFlaggedCompletedOnAccount = function() return false end,
		-- No client names, so a stand-in table is never taken for a quest name.
		GetTitleForQuestID = function() return nil end,
		RequestLoadQuestByID = function() end,
	}),
	C_TaskQuest = stubTable({GetQuestInfoByQuestID = function() return nil end}),
	-- No client NPC names either, and not in an instance.
	C_TooltipInfo = stubTable({GetHyperlink = function() return nil end}),
	IsInInstance = function() return false end,
}
setmetatable(env, {__index = function(_, key)
	local value = _G[key]
	if value ~= nil then return value end
	return dummy
end})

local function readFile(path)
	local handle = assert(io.open(path, "rb"))
	local text = handle:read("*a")
	handle:close()
	return text
end

-- The addon's own table, which WoW gives every file of the addon as its second argument.
local ADDON_TABLE = {}

local function runFile(name, trailer)
	local path = ADDON_DIR .. "/" .. name
	local chunk = assert(loadstring(readFile(path) .. (trailer or ""), "@" .. path))
	setfenv(chunk, env)
	return chunk("QuestCompletist", ADDON_TABLE)
end

--[[ Load the addon in TOC order, reaching the core's file-local helpers through a trailing return ]]--
local core, pinCode, questDataFile
for line in readFile(ADDON_DIR .. "/" .. TOC_FILE):gmatch("[^\r\n]+") do
	local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
	if file == "qcCore.lua" then
		core = runFile(file,
			"\nreturn {BuildListFilter = function() return qcBuildViewFilter(\"L\") end, BuildMapFilter = function() return qcBuildViewFilter(\"M\") end, Holidays = qcHolidays}")
	elseif file == "qcMapPins.lua" then
		pinCode = runFile(file, "\nreturn {Needs = qcPinQuestNeeds, Greyed = qcPinGreyed}")
	elseif file and file:sub(1, 4) ~= "Libs" then
		if file:match("qcQuestData%.lua$") then questDataFile = file end
		runFile(file)
	end
end
assert(core and type(core.BuildListFilter) == "function", "qcBuildViewFilter not found in qcCore.lua")
assert(pinCode and type(pinCode.Needs) == "function" and type(pinCode.Greyed) == "function", "qcPinQuestNeeds not found in qcMapPins.lua")
assert(questDataFile, "qcQuestData.lua is not in the TOC")

local QUESTS = env.qcQuestDatabase
local PIN_DB = env.qcPinDB
local provider = env.qcMapDataProvider

for skillLine in pairs(env.qcProfessionBits) do
	PROFESSION_SKILLS[#PROFESSION_SKILLS + 1] = skillLine
	PROFESSION_INDEXES[#PROFESSION_INDEXES + 1] = #PROFESSION_SKILLS
end

--[[ Settings: every hide filter off except the ones named ]]--
local function applySettings(keepOn)
	env.qcSettings = {}
	env.qcCheckSettings()
	for key in pairs(env.qcSettings) do
		if key:match("^QC_.*HIDE") then env.qcSettings[key] = keepOn[key] and 1 or 0 end
	end
	env.qcSettings.QC_M_SHOW_ICONS = 1
	env.qcCharacterCompletions = {}
end

--[[ Character profiles ]]--
local ALLIANCE_ONLY = {HUMAN=1, DWARF=1, NIGHTELF=1, GNOME=1, DRAENEI=1, WORGEN=1, VOIDELF=1,
	LIGHTFORGEDDRAENEI=1, DARKIRONDWARF=1, KULTIRAN=1, MECHAGNOME=1}
local HORDE_ONLY = {ORC=1, SCOURGE=1, TAUREN=1, TROLL=1, GOBLIN=1, BLOODELF=1, NIGHTBORNE=1,
	HIGHMOUNTAINTAUREN=1, MAGHARORC=1, ZANDALARITROLL=1, VULPERA=1}

local function sortedKeys(t)
	local keys = {}
	for key in pairs(t) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

local identities = {}
for _, race in ipairs(sortedKeys(env.qcRaceBits)) do
	if not HORDE_ONLY[race] then identities[#identities + 1] = {race = race, faction = "Alliance"} end
	if not ALLIANCE_ONLY[race] then identities[#identities + 1] = {race = race, faction = "Horde"} end
	if race == "PANDAREN" then identities[#identities + 1] = {race = race, faction = "Neutral"} end
end
local classes = sortedKeys(env.qcClassBits)
local covenants = sortedKeys(env.qcCovenantsBits)

-- No holiday running, then each holiday's calendar event in turn.
local holidayEvents = {0}
for _, holiday in ipairs(core.Holidays) do holidayEvents[#holidayEvents + 1] = holiday.eventIDs[1] end

local DEFAULT_PROFILE = {holiday = 0, race = identities[1].race, faction = identities[1].faction,
	class = classes[1], covenant = covenants[1]}
local function profile(fields)
	local p = {}
	for key, value in pairs(DEFAULT_PROFILE) do p[key] = value end
	for key, value in pairs(fields or {}) do p[key] = value end
	return p
end

local identityProfiles, covenantProfiles, holidayProfiles = {}, {}, {}
for _, identity in ipairs(identities) do
	for _, class in ipairs(classes) do
		identityProfiles[#identityProfiles + 1] = profile({race = identity.race, faction = identity.faction, class = class})
	end
end
for _, covenant in ipairs(covenants) do covenantProfiles[#covenantProfiles + 1] = profile({covenant = covenant}) end
for _, eventID in ipairs(holidayEvents) do holidayProfiles[#holidayProfiles + 1] = profile({holiday = eventID}) end

local FILTER_GROUPS = {
	{name = "faction/race/class", filters = {"QC_M_HIDE_FACTION", "QC_L_HIDE_FACTION", "QC_M_HIDE_RACECLASS",
		"QC_L_HIDE_RACECLASS"}, profiles = identityProfiles, reads = {"race", "faction", "class"}},
	{name = "covenant", filters = {"QC_M_HIDE_COVENANTS", "QC_L_HIDE_COVENANTS"}, profiles = covenantProfiles,
		reads = {"covenant"}},
	{name = "seasonal", filters = {"QC_M_HIDE_SEASONAL"}, profiles = holidayProfiles, reads = {"holiday"}},
	{name = "profession", filters = {"QC_L_HIDE_PROFESSION", "QC_M_HIDE_PROFESSION"}, profiles = {profile()}, reads = {}},
	{name = "no data", filters = {"QC_M_HIDE_NODATA"}, profiles = {profile()}, reads = {}},
	{name = "requirements not met", filters = {"QC_M_HIDE_REQUIREMENTSNOTMET", "QC_L_HIDE_REQUIREMENTSNOTMET"},
		profiles = {profile()}, reads = {}},
}

--[[ Where each quest can be browsed to in the list: the category menu or the zone auto-switch ]]--
local browsable = {}
local function collectMenu(menu)
	for _, item in ipairs(menu) do
		if type(item.arg1) == "number" then browsable[item.arg1] = true end
		if item.menuList then collectMenu(item.menuList) end
	end
end
collectMenu(env.qcMenu)
for _, categoryId in pairs(env.qcAreaIDToCategoryID) do browsable[categoryId] = true end

--[[ Errors raised by addon code, grouped by message ]]--
local errors, errorOrder = {}, {}
local function recordError(message, context)
	message = tostring(message):gsub("^.-QuestCompletist[/\\]", "")
	if not errors[message] then
		errors[message] = {count = 0, contexts = {}}
		errorOrder[#errorOrder + 1] = message
	end
	local entry = errors[message]
	entry.count = entry.count + 1
	if #entry.contexts < 5 and not entry.contexts[context] then
		entry.contexts[#entry.contexts + 1] = context
		entry.contexts[context] = true
	end
end
local function profileText()
	return string.format("%s %s %s covenant %s holiday %s", P.faction, P.race, P.class, tostring(P.covenant),
		tostring(P.holiday))
end

--[[ Pin identity survives the copies RefreshAllData makes ]]--
local function pinKey(mapId, pin)
	return string.format("%s|%s|%s|%s|%s|%s", mapId, tostring(pin[1]), tostring(pin[2]), tostring(pin[3]),
		tostring(pin[4]), tostring(pin[5]))
end
local function pairKey(key, questId)
	return key .. "#" .. questId
end

local fakeMap = {mapId = nil, drawn = nil}
function fakeMap:GetMapID() return self.mapId end
function fakeMap:RemoveAllPinsByTemplate() end
-- A pin placed outside 0-100 lands off the map's edge, so it isn't really drawn.
local function onMap(pin)
	return pin[4] >= 0 and pin[4] <= 100 and pin[5] >= 0 and pin[5] <= 100
end
function fakeMap:AcquirePin(_, pinData)
	for _, member in ipairs(pinData.stack or {pinData}) do
		if onMap(member) then self.drawn[#self.drawn + 1] = member end
	end
end
provider.GetMap = function() return fakeMap end

local errorMaps = {}
-- Draws one map through the real pipeline; returns the pins drawn, or nil if it raised an error.
local function drawMap(mapId, pinDb)
	env.qcPinDB = pinDb
	fakeMap.mapId, fakeMap.drawn = mapId, {}
	local ok, message = pcall(provider.RefreshAllData, provider)
	if not ok then
		recordError(message, "map " .. mapId .. ", " .. profileText())
		errorMaps[mapId] = true
		return nil
	end
	return fakeMap.drawn
end

--[[ One sweep: which list quests and pin quests some profile can display ]]--
-- The map filters decide quest by quest and a pin is drawn while any of its quests is left, so the
-- map is tracked per pin quest: "pin key#quest ID".
-- candidates: {listQuests = {id=true}, pinQuests = {pairKey=true}}.
-- Returns the same shape, mapping each item seen to the first profile that showed it.
local function sweep(keepOn, candidates, profiles)
	applySettings(keepOn)
	local seen = {listQuests = {}, pinQuests = {}}
	local remainingList, remainingPairs = {}, {}
	for id in pairs(candidates.listQuests) do remainingList[id] = true end
	for key in pairs(candidates.pinQuests) do remainingPairs[key] = true end

	local function reducedPinDb()
		local db, any = {}, false
		for mapId, pins in pairs(PIN_DB) do
			for _, pin in ipairs(pins) do
				local key = pinKey(mapId, pin)
				for _, questId in ipairs(pin[6]) do
					if remainingPairs[pairKey(key, questId)] then
						db[mapId] = db[mapId] or {}
						table.insert(db[mapId], pin)
						any = true
						break
					end
				end
			end
		end
		return any and db or nil
	end

	local pinDb = reducedPinDb()
	for _, current in ipairs(profiles) do
		if not next(remainingList) and not pinDb then break end
		for key, value in pairs(current) do P[key] = value end
		if next(remainingList) then
			local ok, filter = pcall(core.BuildListFilter)
			if not ok then
				recordError(filter, "list filter, " .. profileText())
			else
				for id in pairs(remainingList) do
					local passed, result = pcall(filter, id)
					if not passed then
						recordError(result, "list quest " .. id .. ", " .. profileText())
					elseif result then
						seen.listQuests[id], remainingList[id] = current, nil
					end
				end
			end
		end
		if pinDb then
			local changed = false
			for mapId in pairs(pinDb) do
				for _, pin in ipairs(drawMap(mapId, pinDb) or {}) do
					local key = pinKey(mapId, pin)
					for _, questId in ipairs(pin[6]) do
						local pair = pairKey(key, questId)
						if remainingPairs[pair] then
							seen.pinQuests[pair], remainingPairs[pair], changed = current, nil, true
						end
					end
				end
			end
			if changed then pinDb = reducedPinDb() end
		end
	end
	return seen
end

--[[ Everything the addon has ]]--
local allQuests, browsableQuests, allPairs, allPins, pinInfo, pairInfo = {}, {}, {}, {}, {}, {}
local pairsByPin, pairsByQuest = {}, {}
for id, entry in pairs(QUESTS) do
	allQuests[id] = true
	if browsable[entry[3]] then browsableQuests[id] = true end
end
for mapId, pins in pairs(PIN_DB) do
	for _, pin in ipairs(pins) do
		local key = pinKey(mapId, pin)
		allPins[key] = true
		pinInfo[key] = {mapId = mapId, pin = pin}
		for _, questId in ipairs(pin[6]) do
			local pair = pairKey(key, questId)
			allPairs[pair] = true
			pairInfo[pair] = {pin = key, quest = questId}
			pairsByPin[key] = pairsByPin[key] or {}
			table.insert(pairsByPin[key], pair)
			pairsByQuest[questId] = pairsByQuest[questId] or {}
			table.insert(pairsByQuest[questId], pair)
		end
	end
end

local function minus(a, b)
	local out = {}
	for key in pairs(a) do if not b[key] then out[key] = true end end
	return out
end
local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end
-- The pins drawn and the database quests shown on the map, given the pin quests seen.
local function mapView(pairsSeen)
	local pins, quests = {}, {}
	for pair in pairs(pairsSeen) do
		local info = pairInfo[pair]
		pins[info.pin] = true
		if QUESTS[info.quest] then quests[info.quest] = true end
	end
	return pins, quests
end

realPrint("Sweeping with all filters off...")
local open = sweep({}, {listQuests = browsableQuests, pinQuests = allPairs}, {profile()})
local openPins, openMap = mapView(open.pinQuests)
local openList = open.listQuests
local KINDS = {"listQuests", "pinQuests"}

-- Each group on its own: what it denies every character is that group's doing.
local blame = {listQuests = {}, pinQuests = {}}
local passedBy = {}
local allIdentityFilters = {}
for _, group in ipairs(FILTER_GROUPS) do
	realPrint(string.format("Sweeping the %s filters over %d characters...", group.name, #group.profiles))
	local keep = {}
	for _, key in ipairs(group.filters) do keep[key], allIdentityFilters[key] = true, true end
	passedBy[group] = sweep(keep, open, group.profiles)
	for _, kind in ipairs(KINDS) do
		for key in pairs(open[kind]) do
			if not passedBy[group][kind][key] then
				blame[kind][key] = blame[kind][key] or {}
				table.insert(blame[kind][key], group.name)
			end
		end
	end
end

-- Everything no single group hides: build a character from each group's passing profile and
-- confirm with every identity filter on at once.
realPrint("Confirming with every identity filter on...")
local confirmBatches = {}
for _, kind in ipairs(KINDS) do
	for key in pairs(open[kind]) do
		if not blame[kind][key] then
			local fields = {}
			for _, group in ipairs(FILTER_GROUPS) do
				for _, field in ipairs(group.reads) do fields[field] = passedBy[group][kind][key][field] end
			end
			local p = profile(fields)
			local batchKey = string.format("%s|%s|%s|%s|%s", p.holiday, p.race, p.faction, p.class, tostring(p.covenant))
			local batch = confirmBatches[batchKey]
			if not batch then
				batch = {profile = p, candidates = {listQuests = {}, pinQuests = {}}}
				confirmBatches[batchKey] = batch
			end
			batch.candidates[kind][key] = true
		end
	end
end
local identity = {listQuests = {}, pinQuests = {}}
for _, batch in pairs(confirmBatches) do
	local seen = sweep(allIdentityFilters, batch.candidates, {batch.profile})
	for _, kind in ipairs(KINDS) do
		for key in pairs(batch.candidates[kind]) do
			if seen[kind][key] then
				identity[kind][key] = true
			else
				blame[kind][key] = {"only the combination of filters"}
			end
		end
	end
end
local identityPins, identityMap = mapView(identity.pinQuests)

-- Why a quest or pin is hidden: the reasons behind each of its entries that showed with filters off.
local function reasonText(listQuest, pairList)
	local reasons, seenReason = {}, {}
	local function add(list)
		for _, reason in ipairs(list or {}) do
			if not seenReason[reason] then
				seenReason[reason] = true
				reasons[#reasons + 1] = reason
			end
		end
	end
	if listQuest then add(blame.listQuests[listQuest]) end
	for _, pair in ipairs(pairList or {}) do
		if open.pinQuests[pair] then
			add(blame.pinQuests[pair])
			if errorMaps[pinInfo[pairInfo[pair].pin].mapId] then add({"a Lua error on the map"}) end
		end
	end
	if #reasons == 0 then return nil end
	table.sort(reasons)
	return "hidden by: " .. table.concat(reasons, ", ")
end

--[[ Static checks ]]--
local knownMaps
do
	local handle = io.open(UIMAP_FILE, "rb")
	if handle then
		knownMaps = {}
		handle:read("*l")
		for line in handle:lines() do
			local id = line:match('^"[^"]*",(%d+),') or line:match("^[^,]*,(%d+),")
			if id then knownMaps[tonumber(id)] = true end
		end
		handle:close()
	end
end

local knownHolidays, unknownHolidays = {}, {}
for _, holiday in ipairs(core.Holidays) do knownHolidays[holiday.flag] = true end
for id, entry in pairs(QUESTS) do
	local holiday = env.qcQuestHoliday[id]
	if holiday and holiday ~= 0 and not knownHolidays[holiday] then
		unknownHolidays[holiday] = unknownHolidays[holiday] or {}
		table.insert(unknownHolidays[holiday], id)
	end
end

--[[ Report ]]--
local lines = {}
local function out(text) lines[#lines + 1] = text or "" end
local function questLabel(id)
	local e = QUESTS[id]
	return string.format("%d %q (category %s, faction %s, race %s, class %s, profession %s, holiday %s)",
		id, e[1], tostring(e[3]), tostring(e[5]), tostring(e[6]), tostring(e[7]), tostring(env.qcQuestProfession[id] or 0), tostring(env.qcQuestHoliday[id] or 0))
end
local function pinLabel(key)
	local info = pinInfo[key]
	local pin = info.pin
	local quests = {}
	for _, id in ipairs(pin[6]) do quests[#quests + 1] = tostring(id) end
	return string.format("map %d NPC %s %q at %s,%s quests {%s}",
		info.mapId, tostring(pin[2]), tostring(pin[3]), tostring(pin[4]), tostring(pin[5]),
		table.concat(quests, ","))
end
local function sortedNumbers(t)
	local keys = {}
	for key in pairs(t) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end
local function section(title, items, label, reason)
	local keys = sortedNumbers(items)
	out(string.format("== %s: %d", title, #keys))
	for _, key in ipairs(keys) do
		local why = reason and reason(key)
		out("  " .. label(key) .. (why and ("  <- " .. why) or ""))
	end
	out()
	return #keys
end

local neverShown = minus(minus(allQuests, openList), openMap)
local neverShownIdentity = minus(minus(minus(allQuests, identity.listQuests), identityMap), neverShown)

local summary = {}
local function note(text) summary[#summary + 1] = text end

out("Quest Completist reachability report, " .. os.date("%Y-%m-%d %H:%M"))
local rawPins = 0
for _, pins in pairs(PIN_DB) do rawPins = rawPins + #pins end
out(string.format("%d quests, %d pins (%d once identical pins at the same spot, which the map stacks, count as one)",
	count(allQuests), rawPins, count(allPins)))
out(string.format("%d race/faction/class combinations, %d covenants, %d holiday states",
	#identityProfiles, #covenantProfiles, #holidayProfiles))
out("Search finds every quest in the database by name; 'shown' below means browsing the list or the map.")
out()

out(string.format("== Errors raised by addon code: %d distinct", #errorOrder))
for _, message in ipairs(errorOrder) do
	local entry = errors[message]
	out(string.format("  %s  (x%d)", message, entry.count))
	for _, context in ipairs(entry.contexts) do out("      e.g. " .. context) end
end
out()
note(string.format("%d distinct Lua errors raised by addon code", #errorOrder))

note(string.format("%d quests never shown anywhere, even with every filter off",
	section("Quests never shown anywhere, even with every filter off", neverShown, questLabel)))
note(string.format("%d quests hidden from every possible character by the identity filters",
	section("Quests hidden from every possible character by the identity filters", neverShownIdentity, questLabel,
		function(id) return reasonText(id, pairsByQuest[id]) end)))

local unbrowsable = minus(allQuests, browsableQuests)
local unbrowsableByCategory = {}
for id in pairs(unbrowsable) do
	local categoryId = QUESTS[id][3]
	unbrowsableByCategory[categoryId] = (unbrowsableByCategory[categoryId] or 0) + 1
end
out(string.format("== Quests in categories the list can't browse to: %d, by category", count(unbrowsable)))
for _, categoryId in ipairs(sortedNumbers(unbrowsableByCategory)) do
	out(string.format("  category %d: %d quests", categoryId, unbrowsableByCategory[categoryId]))
end
out()
note(string.format("%d quests in categories the list can't browse to (%d of them also have no drawable pin)",
	count(unbrowsable), count(minus(unbrowsable, openMap))))

local undrawn = minus(allPins, openPins)
note(string.format("%d pins never drawn, even with every filter off",
	section("Pins never drawn, even with every filter off", undrawn, pinLabel, function(key)
		local info = pinInfo[key]
		if not onMap(info.pin) then return "coordinates outside the map" end
		if knownMaps and not knownMaps[info.mapId] then return "map ID not in UiMap.csv" end
		local anyKnown = false
		for _, id in ipairs(info.pin[6]) do if QUESTS[id] then anyKnown = true end end
		if not anyKnown then return "no quest in the database" end
		return nil
	end)))
-- A pin all of whose quests only the seasonal filter hides, for events the calendar never shows, is
-- hidden as it should be.
local offCalendar = {}
for _, holiday in ipairs(core.Holidays) do
	if #holiday.eventIDs == 0 then offCalendar[holiday.flag] = true end
end
local hiddenPins, offCalendarPins = minus(openPins, identityPins), {}
for key in pairs(hiddenPins) do
	local expected = true
	for _, pair in ipairs(pairsByPin[key]) do
		if open.pinQuests[pair] then
			local reasons = blame.pinQuests[pair] or {}
			local holiday = env.qcQuestHoliday[pairInfo[pair].quest]
			if not (#reasons == 1 and reasons[1] == "seasonal" and holiday and offCalendar[holiday]) then expected = false end
		end
	end
	if expected then offCalendarPins[key] = true end
end
note(string.format("%d pins hidden from every possible character by the identity filters",
	section("Pins hidden from every possible character by the identity filters", minus(hiddenPins, offCalendarPins), pinLabel,
		function(key) return reasonText(nil, pairsByPin[key]) end)))
note(string.format("%d pins of events the calendar doesn't show, hidden while the seasonal filter is on",
	section("Pins of events the calendar doesn't show, hidden while the seasonal filter is on", offCalendarPins, pinLabel)))

if knownMaps then
	local unknown = {}
	for mapId in pairs(PIN_DB) do if not knownMaps[mapId] then unknown[mapId] = true end end
	note(string.format("%d pin maps not in UiMap.csv",
		section("Pin maps not in UiMap.csv (the retail client can't open them)", unknown,
			function(id) return string.format("map %d: %d pins", id, #PIN_DB[id]) end)))
else
	out("== tools/UiMap.csv not found; map IDs weren't checked")
	out()
end

out("== Holiday values with no calendar holiday in qcHolidays")
for _, holiday in ipairs(sortedNumbers(unknownHolidays)) do
	local ids = {}
	for _, id in ipairs(unknownHolidays[holiday]) do ids[#ids + 1] = tostring(id) end
	out(string.format("  holiday %d: quests %s", holiday, table.concat(ids, ", ")))
end
out()
note(string.format("%d holiday values with no calendar holiday in qcHolidays", count(unknownHolidays)))

--[[ Minimum level ]]--
-- A quest's minimum level is its minLevel in the data file qcQuestData.lua was built from, else its
-- level. The tooltip's "Requires Level" line, the grey pins and the requirements filter must follow it
-- at any character level. The character here has no faction, race or class, and has done every quest
-- to do first, so nothing else stands between it and a quest. The list's bracket and sort and the
-- low-level filter must still follow the quest's own level, its level in the data file.
local minimumLevels, ownLevels = {}, {}
do
	local source = readFile(ADDON_DIR .. "/" .. questDataFile):match("^%-%- Generated from (.-) by tools")
	local handle = source and io.open(ADDON_DIR .. "/../" .. (source:gsub("\\", "/")), "rb")
	if handle then
		for line in handle:lines() do
			local id, level = line:match('^{"id":(%d+),.-,"level":(-?%d+),"zone"')
			if id then
				ownLevels[tonumber(id)] = tonumber(level)
				minimumLevels[tonumber(id)] = tonumber(line:match('[,{]"minLevel":(%d+)')) or tonumber(level)
			end
		end
		handle:close()
	end
end

local buttons = {}
for i = 1, 16 do
	buttons[i] = stubTable({QuestName = stubTable({SetText = function(self, text) self.text = text end})})
	_G["qcMenuButton" .. i] = buttons[i]
end
env.qcMenuSlider = stubTable({SetValue = function(self, value) self.value = value end, GetValue = function(self) return self.value end})

local levelProblems = 0
if next(minimumLevels) then
	local todo = ADDON_TABLE.qcQuestStatus.TODO
	local function ids(set)
		local list = sortedNumbers(set)
		return string.format("%d%s", #list, #list > 0 and (": " .. table.concat(list, ", ", 1, math.min(#list, 20)) .. (#list > 20 and ", ..." or "")) or "")
	end
	local function withPins(set)
		local n = 0
		for id in pairs(set) do if pairsByQuest[id] then n = n + 1 end end
		return n
	end
	local categories = {}
	for _, e in pairs(QUESTS) do categories[e[3]] = true end
	for _, level in ipairs({1, 10, 30, 60}) do
		P.level, P.faction, P.race, P.class = level, nil, nil, nil
		applySettings({QC_L_HIDE_REQUIREMENTSNOTMET = true})
		local filter = core.BuildListFilter()
		local told, missed, otherLevel, hidden, shown, notInData = {}, {}, {}, {}, {}, {}
		for id in pairs(QUESTS) do
			local minimum = minimumLevels[id]
			if not minimum then
				notInData[id] = true
			else
				local needed = minimum > level
				local line = pinCode.Needs(id, todo)
				local expected = needed and string.format(env.ITEM_MIN_LEVEL, minimum) or nil
				if line ~= expected then
					if line and not needed then told[id] = true
					elseif needed and not line then missed[id] = true
					else otherLevel[id] = true end
				end
				local passes = filter(id)
				if passes and needed then shown[id] = true
				elseif not passes and not needed then hidden[id] = true end
			end
		end
		local greyWrongly, plainWrongly = {}, {}
		for mapId, pins in pairs(PIN_DB) do
			for index, pin in ipairs(pins) do
				local expected = true
				for _, questId in ipairs(pin[6]) do
					if QUESTS[questId] and (minimumLevels[questId] or 0) <= level then expected = false break end
				end
				local grey = pinCode.Greyed(pin)
				if grey and not expected then greyWrongly[mapId * 100000 + index] = true
				elseif not grey and expected then plainWrongly[mapId * 100000 + index] = true end
			end
		end
		local lowLevel, bracket, order = {}, {}, {}
		applySettings({QC_L_HIDE_LOWLEVEL = true})
		local lowLevelFilter = core.BuildListFilter()
		for id, own in pairs(ownLevels) do
			if QUESTS[id] and lowLevelFilter(id) == (own > 0 and own < level - env.UnitQuestTrivialLevelRange()) then lowLevel[id] = true end
		end
		applySettings({})
		for categoryId in pairs(categories) do
			env.qcUpdateQuestList(categoryId, 1)
			local previous = -math.huge
			for _, button in ipairs(buttons) do
				local id, text = button.QuestID, button.QuestName.text
				local own = ownLevels[id]
				if text == "#" then break end
				if own and text ~= (own > 0 and string.format("[%d] %s", own, QUESTS[id][1]) or QUESTS[id][1]) then bracket[id] = true end
				if own and own < previous then order[id] = true end
				previous = own or previous
			end
		end
		local needWrong, noneWrong = {}, {}
		for id in pairs(told) do needWrong[id] = true end
		for id in pairs(hidden) do needWrong[id] = true end
		for id in pairs(missed) do noneWrong[id] = true end
		for id in pairs(shown) do noneWrong[id] = true end
		out(string.format("== Minimum level, character level %d", level))
		out("  tooltip says a level is needed that the character has: " .. ids(told))
		out("  tooltip says none is needed when one is: " .. ids(missed))
		out("  tooltip gives another level than the minimum: " .. ids(otherLevel))
		out("  requirements filter hides a quest the character has the level for: " .. ids(hidden))
		out("  requirements filter shows a quest the character lacks the level for: " .. ids(shown))
		out(string.format("  pins greyed although a quest on them can be taken: %d; not greyed although none can: %d",
			count(greyWrongly), count(plainWrongly)))
		out("  low-level filter not following the quest's own level (a level of 0 or below is never low): " .. ids(lowLevel))
		out("  list row not '[level] name', or not the bare name for a level of 0 or below (first 16 rows of each category): " .. ids(bracket))
		out("  list sort not by the quest's own level (first 16 rows of each category): " .. ids(order))
		out("  quests in qcQuestData.lua that the data file lacks: " .. ids(notInData))
		out()
		note(string.format("character level %d: %d quests (%d with pins) wrongly need a level, %d (%d) wrongly need none, %d need another; %d pins wrongly grey, %d wrongly not; %d wrong low-level, %d bracket, %d sort",
			level, count(needWrong), withPins(needWrong), count(noneWrong), withPins(noneWrong), count(otherLevel),
			count(greyWrongly), count(plainWrongly), count(lowLevel), count(bracket), count(order)))
		levelProblems = levelProblems + count(needWrong) + count(noneWrong) + count(otherLevel) + count(greyWrongly) +
			count(plainWrongly) + count(lowLevel) + count(bracket) + count(order) + count(notInData)
	end
	P.level = nil
else
	out("== Minimum level: not checked, the data file qcQuestData.lua was built from wasn't found")
	out()
	note("minimum level not checked: the data file qcQuestData.lua was built from wasn't found")
	levelProblems = 1
end

--[[ A level of 0 or below is no level ]]--
-- Made-up quests, apart from the data: a level of 0 or below prints the bare name and is never low, in the
-- list and on the map, and asks for no minimum level; a quest with a level is still bracketed and hidden once low.
local noLevelChecks, noLevelWrong = 0, 0
do
	local BASE, CHARACTER, SEARCH, MINIMUM = 4000000000, 80, "ZZ LEVEL TEST", 50
	local LEVELS, MINIMUM_ID = {0, -1, 1, 74, 75, 80}, 4000000100
	local questIds = {}
	for index, level in ipairs(LEVELS) do
		questIds[index] = BASE + index
		QUESTS[questIds[index]] = {"zz level test " .. level, level, 99999, 1, 0, 0, 0}
	end
	QUESTS[MINIMUM_ID] = {"zz level test minimum " .. MINIMUM, 0, 99999, 1, 0, 0, 0}
	env.qcQuestMinLevel[MINIMUM_ID] = MINIMUM
	local noLevelIds = {questIds[1], questIds[2]}
	local function kept(value) return value and "kept" or "hidden" end

	local function check(ok, text)
		noLevelChecks = noLevelChecks + 1
		if not ok then
			noLevelWrong = noLevelWrong + 1
			out("  wrong: " .. text)
		end
	end

	out("== A level of 0 or below is no level (made-up quests)")
	P.level, P.faction, P.race, P.class = CHARACTER, nil, nil, nil
	applySettings({QC_L_HIDE_LOWLEVEL = true, QC_M_HIDE_LOWLEVEL = true})
	local lowBelow = CHARACTER - env.UnitQuestTrivialLevelRange()
	for _, view in ipairs({{"list", core.BuildListFilter}, {"map", core.BuildMapFilter}}) do
		local filter = view[2]()
		for index, level in ipairs(LEVELS) do
			local got, want = filter(questIds[index]), level <= 0 or level >= lowBelow
			check(got == want, string.format("low-level filter, %s, character level %d, quest level %d: %s, should be %s",
				view[1], CHARACTER, level, kept(got), kept(want)))
		end
		local got = filter(MINIMUM_ID)
		check(got == true, string.format("low-level filter, %s, character level %d, quest level 0 with minimum %d: %s, should be kept",
			view[1], CHARACTER, MINIMUM, kept(got)))
	end

	local todo = ADDON_TABLE.qcQuestStatus.TODO
	for _, character in ipairs({1, MINIMUM}) do
		P.level = character
		applySettings({QC_L_HIDE_REQUIREMENTSNOTMET = true})
		local filter = core.BuildListFilter()
		for _, id in ipairs(noLevelIds) do
			local got, line = filter(id), pinCode.Needs(id, todo)
			check(got == true, string.format("requirements filter, character level %d, quest level %d: %s, should be kept",
				character, QUESTS[id][2], kept(got)))
			check(line == nil, string.format("'Requires Level' line, character level %d, quest level %d: %s, should be none",
				character, QUESTS[id][2], tostring(line)))
		end
		local needed = character < MINIMUM
		local got, line = filter(MINIMUM_ID), pinCode.Needs(MINIMUM_ID, todo)
		check(got == not needed, string.format("requirements filter, character level %d, quest level 0 with minimum %d: %s, should be %s",
			character, MINIMUM, kept(got), kept(not needed)))
		local want = needed and string.format(env.ITEM_MIN_LEVEL, MINIMUM) or nil
		check(line == want, string.format("'Requires Level' line, character level %d, quest level 0 with minimum %d: %s, should be %s",
			character, MINIMUM, tostring(line), tostring(want)))
	end

	P.level = CHARACTER
	applySettings({})
	env.qcUpdateQuestList(nil, 1, SEARCH)
	local rowText = {}
	for _, button in ipairs(buttons) do
		if button.QuestName.text ~= "#" then rowText[button.QuestID] = button.QuestName.text end
	end
	for index, level in ipairs(LEVELS) do
		local id = questIds[index]
		local name = QUESTS[id][1]
		local want = level > 0 and string.format("[%d] %s", level, name) or name
		check(rowText[id] == want, string.format("list row, quest level %d: %s, should be %s", level, tostring(rowText[id]), want))
	end
	local name = QUESTS[MINIMUM_ID][1]
	check(rowText[MINIMUM_ID] == name, string.format("list row, quest level 0 with minimum %d: %s, should be %s",
		MINIMUM, tostring(rowText[MINIMUM_ID]), name))

	for _, id in ipairs(questIds) do QUESTS[id] = nil end
	QUESTS[MINIMUM_ID], env.qcQuestMinLevel[MINIMUM_ID] = nil, nil
	P.level = nil
	out(string.format("  %d checks, %d wrong", noLevelChecks, noLevelWrong))
	out()
	note(string.format("level 0 or below, made-up quests: %d of %d checks wrong", noLevelWrong, noLevelChecks))
	levelProblems = levelProblems + noLevelWrong
end

local handle = assert(io.open(REPORT_FILE, "wb"))
handle:write(table.concat(lines, "\n"), "\n")
handle:close()

realPrint()
for _, text in ipairs(summary) do realPrint("  " .. text) end
realPrint()
realPrint("Full report: " .. REPORT_FILE)
if levelProblems > 0 then
	realPrint(string.format("FAILED: the level checks found %d problems", levelProblems))
	os.exit(1)
end
