--[[
Checks that every quest and map pin in the addon can actually be displayed by some character.

Loads the addon's own files with stand-ins for the WoW API, then drives the real list filter
(qcBuildQuestFilter) and the real map pin pipeline (qcMapDataProvider:RefreshAllData). Nothing is
re-implemented here, so the check can't drift from what the addon does.

Two settings tiers are checked:
  all filters off  - anything hidden here can never be displayed, whatever the settings.
  identity filters - faction, race/class, profession, covenant, seasonal, no-data and
                     requirements-not-met on; everything else off. Anything hidden here is hidden
                     from every possible character, which means contradictory data.
Progress is best case: max level, every prerequisite done, max renown, nothing completed, and the
character has every profession.

The calendar is a stand-in that shows no holiday, then each of qcHolidays in turn.

Trying every race, class, covenant and holiday together is ~28k combinations per map, far too slow.
Each filter group only reads its own part of the character (faction and race/class read race,
faction and class; covenant reads the covenant; seasonal reads the calendar), so each group is swept on
its own, and anything every group lets through is confirmed with all of them on at once.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-QuestReachability.lua
Writes the full report to tools\reachability-report.txt and a summary to the console.
tools\UiMap.csv, if present, is used to flag pins on map IDs the client doesn't have.
]]

local ADDON_DIR = arg and arg[1] or "QuestCompletist"
local TOOLS_DIR = arg and arg[2] or "tools"
local REPORT_FILE = TOOLS_DIR .. "/reachability-report.txt"
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
	UnitLevel = function() return 1000 end,
	UnitQuestTrivialLevelRange = function() return 5 end,
	GetProfessions = function() return unpack(PROFESSION_INDEXES) end,
	GetProfessionInfo = function(index) return nil, nil, nil, nil, nil, nil, PROFESSION_SKILLS[index] end,
	C_Covenants = stubTable({GetActiveCovenantID = function() return P.covenant end}),
	C_MajorFactions = stubTable({GetCurrentRenownLevel = function() return 1000 end}),
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

local function runFile(name, trailer)
	local path = ADDON_DIR .. "/" .. name
	local chunk = assert(loadstring(readFile(path) .. (trailer or ""), "@" .. path))
	setfenv(chunk, env)
	return chunk()
end

--[[ Load the addon in TOC order, reaching the core's file-local helpers through a trailing return ]]--
for line in readFile(ADDON_DIR .. "/QuestCompletist.toc"):gmatch("[^\r\n]+") do
	local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
	if file and file ~= "qcCore.lua" then runFile(file) end
end
local core = runFile("qcCore.lua",
	"\nreturn {BuildQuestFilter = function() return qcBuildQuestFilter(QC_LIST_FILTER) end, Holidays = qcHolidays}")
assert(type(core.BuildQuestFilter) == "function", "qcBuildQuestFilter not found in qcCore.lua")

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
	{name = "faction/race/class", filters = {"QC_ML_HIDE_FACTION", "QC_ML_HIDE_RACECLASS"},
		profiles = identityProfiles, reads = {"race", "faction", "class"}},
	{name = "covenant", filters = {"QC_ML_HIDE_COVENANTS"}, profiles = covenantProfiles, reads = {"covenant"}},
	{name = "seasonal", filters = {"QC_M_HIDE_SEASONAL"}, profiles = holidayProfiles, reads = {"holiday"}},
	{name = "profession", filters = {"QC_L_HIDE_PROFESSION", "QC_M_HIDE_PROFESSION"}, profiles = {profile()}, reads = {}},
	{name = "no data", filters = {"QC_M_HIDE_NODATA"}, profiles = {profile()}, reads = {}},
	{name = "requirements not met", filters = {"QC_M_HIDE_REQUIREMENTSNOTMET"}, profiles = {profile()}, reads = {}},
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
			local ok, filter = pcall(core.BuildQuestFilter)
			if not ok then
				recordError(filter, "list filter, " .. profileText())
			else
				for id in pairs(remainingList) do
					local passed, result = pcall(filter, id, QUESTS[id])
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
	local handle = io.open(TOOLS_DIR .. "/UiMap.csv", "rb")
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
note(string.format("%d pins hidden from every possible character by the identity filters",
	section("Pins hidden from every possible character by the identity filters", minus(openPins, identityPins), pinLabel,
		function(key) return reasonText(nil, pairsByPin[key]) end)))

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

local handle = assert(io.open(REPORT_FILE, "wb"))
handle:write(table.concat(lines, "\n"), "\n")
handle:close()

realPrint()
for _, text in ipairs(summary) do realPrint("  " .. text) end
realPrint()
realPrint("Full report: " .. REPORT_FILE)
