--[[
Checks how the addon reads the level of a quest whose content tuning a redirect can move
(docs/plans/quest-scaling-redirects.md, option E). A quest on a tuning of qcTuningSample reads the game's level for a
sample of that tuning the client holds, else its stored level: its own, or for a quest that scales the character's,
raised to its minimum and held down at its maxLevel. Only the quest list's category build asks the server for a
sample: one per tuning at a time, and only for a tuning with a quest stored below the character's level. An answer
that changes a level the list read rebuilds the list once a batch, and never the map. The maps, the continent icons,
their tooltips and search ask for nothing.

Loads the addon's own files with stand-ins for the WoW API, a clock that only moves when told, and a game that holds
only the quests it is told to hold or has been asked for: GetQuestDifficultyLevel is 0 for any other, and a request
is answered 0.2 s later. Its levels follow a redirect state, from the client's ConditionalContentTuning and
ContentTuning tables (<tables>\ConditionalContentTuning-<build>.csv and <tables>\ContentTuning-<build>.csv, as step
2j keeps them): a tuning takes the row of highest OrderIndex whose RedirectEnum bit is on, as TrinityCore does. Where
that is the row the probe's character took (bits 1, 5, 14 and 33), the level is the probe's: the tuning's level in
data\tunings.jsonl, raised to the minimum the data gives its scaling quests. Elsewhere it is the character's level
held in the range the ContentTuning table gives the tuning it lands on: MinLevelSquish and MaxLevelSquish, each plus
the base its scaling offset picks (0, 1, the cap of 90 or the 80 before it), as TrinityCore's GetContentTuningData
reads them and QuestLevels.ps1 reads the minimum. The states: the probe's; Nazmir with the character's Endeavor on
(bit 34 as well), where the user read ten quests on 16 October 2026; and Chromie Time (bit 0 alone).

The checks, each printed:
- the ten readings of 16 October, in Nazmir and in Silvermoon City, from held samples;
- the probe's state with every sample held, at levels 1, 10, 30, 60 and 90: every quest reads its stored level,
  except the quests at their tuning's minimum whose own level isn't it, listed, which read their tuning's level; the
  low-level filter of the list and the map and the list's rows follow;
- Nazmir at 90: until its samples are held its quests read their stored levels, the map asks for nothing and the
  low-level filter hides them; the list asks for one sample of each tuning that needs one, and once answered the
  quests on tunings bit 34 moves read 90, are kept, show [90] and are drawn on the map, and the others keep theirs;
- Chromie Time at 40: Elwynn Forest's quests read 40 once a sample is held, and their stored level until then;
- requests: every map's pins drawn and hovered, a continent of every zone drawn and hovered, and search ask the game
  nothing; answers that agree with the stored levels rebuild nothing; a sample that fails twice gives way to the next,
  never two of one tuning at once, one list rebuild a batch; the zone, the level and the redirect bits changing make
  the levels be read again;
- WoW: Forever (its TOC): the tables are empty, every quest reads its stored level, and nothing is read or asked.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-QuestScaling.lua
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-QuestScaling.lua QuestCompletist QuestCompletist_Camelot.toc
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-QuestScaling.lua QuestCompletist QuestCompletist.toc <tables> <build>
The tables' folder is tools when left out, and the build the newest of its ConditionalContentTuning-<build>.csv.
Pointed at an addon without qcTuningSample (before option E), it checks only that the maps, the continent icons and
search ask for nothing. Exits with 1 if a check fails. Run it for both games' TOCs.
]]

local ADDON_DIR = arg and arg[1] or "QuestCompletist"
local TOC_FILE = arg and arg[2] or "QuestCompletist.toc"
local TABLES_DIR = arg and arg[3] or "tools"
local BUILD = arg and arg[4]
local FOREVER = TOC_FILE ~= "QuestCompletist.toc"

local PROBE_BITS = {[1] = true, [5] = true, [14] = true, [33] = true}
local NAZMIR_BITS = {[1] = true, [5] = true, [14] = true, [33] = true, [34] = true}
local CHROMIE_BITS = {[0] = true}
local LEVEL_CAP = 90
local LEVEL_BASE = {[0] = 0, [1] = 1, [2] = 90, [3] = 80}
local ANSWER_DELAY = 0.2
local NAZMIR_MAP, NAZMIR_CATEGORY, ELWYNN_CATEGORY = 863, 1080, 70
local READINGS = {
	nazmir = {[11] = 90, [26024] = 90, [26042] = 90, [7781] = 90, [28713] = 10, [78642] = 90, [78126] = 80, [60514] = 90, [94871] = 90, [54] = 10},
	silvermoon = {[11] = 30, [26024] = 30, [26042] = 30, [7781] = 30, [28713] = 10, [78642] = 80, [78126] = 80, [60514] = 90, [94871] = 90, [54] = 10},
}

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

local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

local function sortedKeys(t)
	local keys = {}
	for key in pairs(t) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

local function idList(t, limit)
	local keys = sortedKeys(t)
	local parts = {}
	for i = 1, math.min(#keys, limit or 12) do parts[i] = tostring(keys[i]) end
	return table.concat(parts, ", ") .. (#keys > (limit or 12) and ", ..." or "")
end

--[[ Checks ]]--
local failures = 0
local function check(label, passed, detail)
	if not passed then failures = failures + 1 end
	print(string.format("  [%s] %s%s", passed and "ok" or "FAIL", label, detail and (" (" .. detail .. ")") or ""))
end

--[[ The clock: timers run, in order, only when it is moved on ]]--
local now, timers = 0, {}
local function after(delay, fn)
	timers[#timers + 1] = {at = now + delay, fn = fn}
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

--[[ The client's tables ]]--
local function readCsv(path)
	local handle = io.open(path, "rb")
	if not handle then return nil end
	local header, rows = nil, {}
	for line in handle:lines() do
		line = line:gsub("\r$", "")
		if not header then
			header = {}
			for name in line:gsub("^\239\187\191", ""):gmatch("[^,]+") do header[#header + 1] = name end
		elseif line ~= "" then
			local row, i = {}, 0
			for value in (line .. ","):gmatch("([^,]*),") do
				i = i + 1
				if header[i] then row[header[i]] = tonumber(value) or value end
			end
			rows[#rows + 1] = row
		end
	end
	handle:close()
	return rows
end

local function newestBuild()
	local newest, newestKey
	local pipe = io.popen(package.config:sub(1, 1) == "\\" and ('dir /b "' .. TABLES_DIR:gsub("/", "\\") .. '" 2>nul') or ('ls "' .. TABLES_DIR .. '" 2>/dev/null'))
	if not pipe then return nil end
	for name in pipe:lines() do
		local build = name:match("^ConditionalContentTuning%-([%d%.]+)%.csv$")
		if build then
			local parts = {}
			for part in build:gmatch("%d+") do parts[#parts + 1] = string.format("%08d", tonumber(part)) end
			local key = table.concat(parts, ".")
			if not newestKey or key > newestKey then newest, newestKey = build, key end
		end
	end
	pipe:close()
	return newest
end

local redirects, ranges = {}, {}
local function loadTables(build)
	local rows = readCsv(TABLES_DIR .. "/ConditionalContentTuning-" .. build .. ".csv")
	local tunings = readCsv(TABLES_DIR .. "/ContentTuning-" .. build .. ".csv")
	if not rows or not tunings then return false end
	for _, row in ipairs(rows) do
		local parent = row.ParentContentTuningID
		redirects[parent] = redirects[parent] or {}
		table.insert(redirects[parent], {order = row.OrderIndex, target = row.RedirectContentTuningID, bit = row.RedirectEnum})
	end
	for _, list in pairs(redirects) do table.sort(list, function(a, b) return a.order > b.order end) end
	local function clampLevel(value) return math.max(1, math.min(LEVEL_CAP, value)) end
	for _, row in ipairs(tunings) do
		local lowBase, highBase = LEVEL_BASE[row.MinLevelScalingOffset], LEVEL_BASE[row.MaxLevelScalingOffset]
		if lowBase and highBase then
			ranges[row.ID] = {low = clampLevel(lowBase + row.MinLevelSquish), high = clampLevel(highBase + row.MaxLevelSquish)}
		end
	end
	return true
end

local function landsOn(tuning, bits)
	for _, row in ipairs(redirects[tuning] or {}) do
		if bits[row.bit] then return row.target end
	end
	return tuning
end

--[[ The data, from the first load of the addon ]]--
local QUESTS, QUEST_TUNING, TUNING_SAMPLE, MIN_LEVEL, MAX_LEVEL
local SAMPLE_TUNING = {}
local tuningLevel, tuningMinimum, tuningSplit = {}, {}, {}

local function storedLevel(questId, level)
	local e = QUESTS[questId]
	local ceiling = MAX_LEVEL[questId]
	if not ceiling then return e[2] end
	return math.max(MIN_LEVEL[questId] or e[2] or 0, math.min(level, ceiling))
end

local function probeLevel(tuning, level)
	local minimum = tuningMinimum[tuning]
	if not minimum then return tuningLevel[tuning] end
	return math.max(minimum, math.min(level, tuningLevel[tuning]))
end

local function rangeLevel(tuning, level)
	local range = ranges[tuning]
	if not range then return 0 end
	if level >= range.low then return math.min(level, range.high) end
	return range.low
end

-- The game's level for a quest on a tuning, for a character with these bits at this level.
local function gameLevel(tuning, bits, level)
	local landed = landsOn(tuning, bits)
	if landed == landsOn(tuning, PROBE_BITS) then return probeLevel(tuning, level) end
	return rangeLevel(landed, level)
end

-- The level each quest should read: its tuning's in the game while a sample is held, else its stored one.
local function expectedLevel(questId, bits, level, tuningHeld)
	local tuning = QUEST_TUNING[questId]
	if tuning and tuningHeld[tuning] then return gameLevel(tuning, bits, level) end
	return storedLevel(questId, level)
end

--[[ The game ]]--
local game, env, core, eventFrame, onEvent, counts, fakeMap

local function fireEvent(event, ...)
	onEvent(eventFrame, event, ...)
end

local function difficulty(questId)
	game.difficultyCalls = game.difficultyCalls + 1
	if not game.held[questId] then return 0 end
	local tuning = SAMPLE_TUNING[questId] or QUEST_TUNING[questId]
	if not tuning then return QUESTS[questId] and QUESTS[questId][2] or 0 end
	return gameLevel(tuning, game.bits, game.level)
end

local function request(questId)
	game.asked[questId] = (game.asked[questId] or 0) + 1
	game.askLog[#game.askLog + 1] = {quest = questId, at = now}
	local tuning = SAMPLE_TUNING[questId]
	if tuning then
		game.loading[tuning] = game.loading[tuning] or {}
		game.loading[tuning][questId] = true
		if count(game.loading[tuning]) > 1 then game.overlap[tuning] = true end
	end
	after(ANSWER_DELAY, function()
		if tuning then game.loading[tuning][questId] = nil end
		local failing = game.fail[questId] or 0
		if failing > 0 then
			game.fail[questId] = failing - 1
			game.answerLog[#game.answerLog + 1] = {quest = questId, at = now, success = false}
			fireEvent("QUEST_DATA_LOAD_RESULT", questId, false)
		else
			game.held[questId] = true
			game.answerLog[#game.answerLog + 1] = {quest = questId, at = now, success = true}
			fireEvent("QUEST_DATA_LOAD_RESULT", questId, true)
		end
	end)
end

local function askedTotal()
	local n = 0
	for _, times in pairs(game.asked) do n = n + times end
	return n
end

--[[ Frames: any method does nothing, one that makes something hands back another such stand-in, and a field is
empty until set. The tooltip also keeps what its lines say. ]]--
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

-- A pin of the map's: the mixin's methods, and nothing done for the map's own.
local function newPin(mixin)
	local pin = {Texture = newObject(), Count = newObject()}
	pin.GetCenter = function() return 100, 100 end
	pin.GetMap = function() return fakeMap end
	return setmetatable(pin, {__index = function(_, key)
		local method = mixin[key]
		if method ~= nil then return method end
		if type(key) == "string" and key:match("^%u") then return function() end end
	end})
end

local function newRow()
	local row = newObject({QuestName = newObject({SetText = function(self, text) self.text = text end}),
		QuestIcon = newObject(), FactionIcon = newObject(), shown = false})
	row.Show = function(self) self.shown = true end
	row.Hide = function(self) self.shown = false end
	row.IsShown = function(self) return self.shown end
	return row
end

local STRINGS = {
	TOOLTIP_UNIT_LEVEL = "Level %s", ITEM_REQ_ALLIANCE = "Alliance", ITEM_REQ_HORDE = "Horde", ITEM_RACES_ALLOWED = "Races: %s",
	ITEM_CLASSES_ALLOWED = "Classes: %s", ITEM_MIN_LEVEL = "Requires Level %d", ITEM_REQ_SKILL = "Requires %s",
	ITEM_REQ_REPUTATION = "Requires %s - %s", ITEM_MIN_SKILL = "Requires %s (%d)", RENOWN_LEVEL_LABEL = "Renown %d",
	UNKNOWN = "Unknown", SEARCH = "Search", SPELLBOOK_SEARCH_HEADER_RESULTS = "Search results",
	QUEST_WATCH_QUEST_READY = "Ready", AVAILABLE_QUESTS = "Available", UNAVAILABLE = "Unavailable", IN_PROGRESS = "In progress",
	FLIGHT_MAP_CLICK_TO_ZOOM_IN = "Click to zoom in", SERVICES_CONJUNCTION_OR = "or",
}

local function makeEnv()
	local e = {
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
		C_Timer = {After = after},
		UIParent = newObject(),
		WorldMapFrame = {
			HookScript = function() end,
			GetCanvas = function() return {GetSize = function() return 1000, 700 end} end,
			GetScale = function() return 1 end,
			AddDataProvider = function() end,
			IsShown = function() return true end,
		},
		IsShiftKeyDown = function() return false end,
		IsModifierKeyDown = function() return false end,
		IsLeftShiftKeyDown = function() return false end,
		IsLeftAltKeyDown = function() return false end,
		IsInInstance = function() return false end,
		issecretvalue = function() return false end,
		C_AddOns = {IsAddOnLoaded = function() return false end},
		UnitFactionGroup = function() return "Alliance", "Alliance" end,
		UnitRace = function() return "Human", "Human" end,
		UnitClass = function() return "MAGE", "MAGE" end,
		UnitLevel = function() return game.level end,
		UnitName = function() return "Tester" end,
		UnitQuestTrivialLevelRange = function() return 5 end,
		GetProfessions = function() return end,
		GetProfessionInfo = function() return end,
		Enum = {UIMapType = {Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4}},
		C_Covenants = stubTable({GetActiveCovenantID = function() return 0 end}),
		C_MajorFactions = stubTable({GetCurrentRenownLevel = function() return 1000 end}),
		C_SkillInfo = stubTable({GetSkillLineInfoByID = function() return {rank = 1000, modifier = 0} end}),
		C_QuestLog = stubTable({
			GetLogIndexForQuestID = function() return nil end,
			IsComplete = function() return false end,
			IsQuestFlaggedCompleted = function() return false end,
			IsQuestFlaggedCompletedOnAccount = function() return false end,
			GetTitleForQuestID = function(questId) return game.titles and ("Client " .. questId) or nil end,
			RequestLoadQuestByID = request,
			GetQuestDifficultyLevel = difficulty,
			IsWorldQuest = function() return false end,
		}),
		C_TaskQuest = stubTable({GetQuestInfoByQuestID = function() return nil end}),
		C_TooltipInfo = stubTable({GetHyperlink = function() return nil end}),
		C_CreatureInfo = {GetRaceInfo = function() return nil end, GetClassInfo = function() return nil end},
		LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, {__index = function(_, token) return token end}),
		C_Map = stubTable({
			GetBestMapForUnit = function() return game.mapId end,
			GetMapInfo = function(mapId) return {mapID = mapId, name = "Map " .. mapId, mapType = game.mapTypes[mapId] or 3} end,
			GetMapChildrenInfo = function(mapId, mapType)
				local list = {}
				for _, child in ipairs(game.children[mapId] or {}) do
					if mapType == nil or child.mapType == mapType then list[#list + 1] = child end
				end
				return list
			end,
			GetMapRectOnMap = function(childId)
				local rect = game.rects[childId]
				if rect then return rect[1], rect[2], rect[3], rect[4] end
			end,
			GetPlayerMapPosition = function() return nil end,
		}),
		C_DateAndTime = stubTable({GetCurrentCalendarTime = function() return {year = 2026, month = 10, monthDay = 16, hour = 14, minute = 30} end}),
	}
	for key, value in pairs(STRINGS) do e[key] = value end
	e.CreateFrame = function(kind, name)
		if kind == "GameTooltip" then
			local tooltip = newTooltip()
			if name then e[name] = tooltip end
			return tooltip
		end
		return newObject()
	end
	for i = 1, 16 do e["qcMenuButton" .. i] = newRow() end
	e.qcMenuSlider = newObject({SetValue = function(self, value) self.value = value end, GetValue = function(self) return self.value or 1 end})
	e.qcQuestCompletistUI = newObject({IsVisible = function() return game.listShown end, qcSelectedCategory = newObject(),
		qcCurrentCategoryQuestCount = newObject(), qcHiddenQuests = newObject(), qcSearchBox = newObject()})
	e._G = e
	return setmetatable(e, {__index = function(_, key)
		local value = _G[key]
		if value ~= nil then return value end
		return dummy
	end})
end

local TRAILER = "\nreturn {Shown = qcShownQuestLevel, Stored = qcStoredQuestLevel, Tuning = qcTuning, Filter = qcBuildViewFilter}"

--[[ A fresh load of the addon, with a game that holds nothing ]]--
local function boot()
	now, timers = 0, {}
	game = {held = {}, bits = PROBE_BITS, level = LEVEL_CAP, titles = true, fail = {}, asked = {}, askLog = {}, answerLog = {},
		loading = {}, overlap = {}, difficultyCalls = 0, mapId = nil, listShown = false, children = {}, rects = {}, mapTypes = {},
		registered = {}}
	counts = {listBuilds = 0, mapRefreshes = 0}
	env = makeEnv()
	local QC = {}
	for line in readFile(ADDON_DIR .. "/" .. TOC_FILE):gmatch("[^\r\n]+") do
		local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
		if file and file:sub(1, 4) ~= "Libs" then
			local source = readFile(ADDON_DIR .. "/" .. file)
			if file == "qcCore.lua" then source = source .. TRAILER end
			local chunk = assert(loadstring(source, "@" .. ADDON_DIR .. "/" .. file))
			setfenv(chunk, env)
			local result = chunk("QuestCompletist", QC)
			if file == "qcCore.lua" then core = result end
		end
	end
	eventFrame = stubTable({})
	eventFrame.RegisterEvent = function(_, event) game.registered[event] = true end
	eventFrame.RegisterUnitEvent = function(_, event, unit) game.registered[event] = unit end
	eventFrame.SetScript = function(_, script, fn) if script == "OnEvent" then onEvent = fn end end
	env.qcQuestCompletistUI_OnLoad(eventFrame)
	assert(onEvent, "the addon set no OnEvent script")

	local updateList = env.qcUpdateQuestList
	env.qcUpdateQuestList = function(categoryId, ...)
		if categoryId then counts.listBuilds = counts.listBuilds + 1 end
		return updateList(categoryId, ...)
	end
	fakeMap = {mapId = nil, quests = {}, pins = {}}
	function fakeMap:GetMapID() return self.mapId end
	function fakeMap:RemoveAllPinsByTemplate() self.quests, self.pins = {}, {} end
	function fakeMap:AcquirePin(template, data)
		local pin = newPin(template == "qcContinentPinTemplate" and env.qcContinentPinMixin or env.qcPinMixin)
		pin:OnAcquired(data)
		self.pins[#self.pins + 1] = pin
		if type(data[6]) == "table" then
			for _, questId in ipairs(data[6]) do self.quests[questId] = true end
		end
	end
	for _, name in ipairs({"qcMapDataProvider", "qcContinentDataProvider"}) do
		local provider = env[name]
		provider.GetMap = function() return fakeMap end
		local refresh = provider.RefreshAllData
		provider.RefreshAllData = function(self, ...)
			counts.mapRefreshes = counts.mapRefreshes + 1
			return refresh(self, ...)
		end
	end
end

local function settings(on)
	env.qcSettings = {}
	env.qcCheckSettings()
	for key in pairs(env.qcSettings) do
		if key:match("^QC_.*HIDE") then env.qcSettings[key] = 0 end
	end
	for key in pairs(on or {}) do env.qcSettings[key] = 1 end
	env.qcSettings.QC_M_SHOW_ICONS, env.qcSettings.QC_M_SHOW_CONTINENT = 1, 1
	env.qcCharacterCompletions = {}
end

local LOW_LEVEL = {QC_L_HIDE_LOWLEVEL = true, QC_M_HIDE_LOWLEVEL = true}

local function isLow(level, character)
	return level > 0 and level < character - 5
end

local function forget()
	core.Tuning.Forget()
end

local function holdSamples(tunings)
	for tuning in pairs(tunings) do
		for _, questId in ipairs(TUNING_SAMPLE[tuning]) do game.held[questId] = true end
	end
end

local function allTunings()
	local all = {}
	for tuning in pairs(TUNING_SAMPLE) do all[tuning] = true end
	return all
end

local categories = {}
local function questsOf(categoryId) return categories[categoryId] or {} end

--[[ The first load, and what the data says ]]--
boot()
local HAS_TUNINGS = rawget(env, "qcTuningSample") ~= nil and type(core.Stored) == "function"
QUESTS, MIN_LEVEL, MAX_LEVEL = env.qcQuestDatabase, env.qcQuestMinLevel, env.qcQuestMaxLevel
QUEST_TUNING, TUNING_SAMPLE = rawget(env, "qcQuestTuning") or {}, rawget(env, "qcTuningSample") or {}
for questId, e in pairs(QUESTS) do
	categories[e[3]] = categories[e[3]] or {}
	table.insert(categories[e[3]], questId)
end
for tuning, samples in pairs(TUNING_SAMPLE) do
	for _, questId in ipairs(samples) do SAMPLE_TUNING[questId] = tuning end
end
local SAMPLED = next(TUNING_SAMPLE) ~= nil

print(string.format("%s, %s: %d quests, %d with a sampled tuning, %d tunings with samples", ADDON_DIR, TOC_FILE, count(QUESTS),
	count(QUEST_TUNING), count(TUNING_SAMPLE)))

--[[ The requests no view but the list may make: every map, a continent of every zone, their tooltips, search ]]--
local function checkViewsAskNothing(bits, label)
	print("Drawing every map and a continent of every zone, and hovering them, " .. label)
	boot()
	game.bits, game.level, game.titles = bits, FOREVER and 60 or LEVEL_CAP, false
	local maps = sortedKeys(env.qcPinDB)
	local hovered = 0
	for _, filters in ipairs({{on = LOW_LEVEL, label = "with the low-level filter on"}, {label = "with every filter off"}}) do
		settings(filters.on)
		local drawn = 0
		for _, mapId in ipairs(maps) do
			fakeMap.mapId = mapId
			env.qcMapDataProvider:RefreshAllData()
			drawn = drawn + #fakeMap.pins
		end
		advance(60)
		check(string.format("drawing the pins of all %d maps (%d pins) %s asks the game nothing", #maps, drawn, filters.label),
			askedTotal() == 0, askedTotal() .. " asked")
	end
	settings(LOW_LEVEL)
	local continent = 1000000
	game.mapTypes[continent] = 2
	game.children[continent] = {}
	for index, mapId in ipairs(sortedKeys(env.qcAreaIDToCategoryID)) do
		table.insert(game.children[continent], {mapID = mapId, name = "Zone " .. mapId, mapType = 3})
		local x, y = (index % 40) / 40, math.floor(index / 40) / 40
		game.rects[mapId] = {x, x + 0.01, y, y + 0.01}
	end
	fakeMap.mapId = continent
	env.qcContinentDataProvider:RefreshAllData()
	local icons = #fakeMap.pins
	for _, pin in ipairs(fakeMap.pins) do
		pin:OnMouseEnter()
		pin:OnMouseLeave()
	end
	advance(60)
	check(string.format("drawing and hovering a continent of every zone (%d icons) asks the game nothing", icons),
		icons > 0 and askedTotal() == 0, askedTotal() .. " asked")
	game.titles = true
	settings()
	fakeMap.mapId = SAMPLED and NAZMIR_MAP or maps[1]
	env.qcMapDataProvider:RefreshAllData()
	for _, pin in ipairs(fakeMap.pins) do
		pin:OnMouseEnter()
		pin:OnMouseLeave()
		hovered = hovered + 1
	end
	advance(60)
	check(string.format("hovering the %d pins of map %d asks the game nothing", hovered, fakeMap.mapId), hovered > 0 and askedTotal() == 0,
		askedTotal() .. " asked")
	game.listShown = true
	env.qcUpdateQuestList(nil, 1, "THE")
	advance(60)
	check("a search asks the game nothing", askedTotal() == 0, askedTotal() .. " asked")
	check("and none of it rebuilt the list or redrew a map by itself", counts.listBuilds == 0, counts.listBuilds .. " list builds")
end

checkViewsAskNothing(PROBE_BITS, "nothing held")

if not HAS_TUNINGS then
	print("This addon has no qcTuningSample: only the requests were checked.")
	if failures > 0 then
		print(string.format("%d check%s failed.", failures, failures == 1 and "" or "s"))
		os.exit(1)
	end
	print("All checks passed.")
	return
end

if not SAMPLED then
	print("No tuning has samples (WoW: Forever's data): every quest reads its stored level, and nothing is read or asked")
	boot()
	game.titles, game.listShown = true, true
	check("qcQuestTuning is empty too", next(QUEST_TUNING) == nil, count(QUEST_TUNING) .. " quests")
	local wrong = {}
	for _, level in ipairs({1, 10, 30, 60}) do
		game.level = level
		for questId, e in pairs(QUESTS) do
			if core.Shown(questId, e, level) ~= storedLevel(questId, level) then wrong[questId] = true end
		end
	end
	check("every quest reads its stored level at levels 1, 10, 30 and 60", next(wrong) == nil, count(wrong) .. ": " .. idList(wrong))
	settings(LOW_LEVEL)
	for _, categoryId in ipairs(sortedKeys(categories)) do env.qcUpdateQuestList(categoryId, 1) end
	advance(60)
	check("building every category's list asks the game nothing", askedTotal() == 0, askedTotal() .. " asked")
	check("and no quest's level is asked of the game", game.difficultyCalls == 0, game.difficultyCalls .. " asked")
	local builds = counts.listBuilds
	fireEvent("UNIT_CTR_OPTIONS", "player")
	fireEvent("PLAYER_LEVEL_UP", 61)
	advance(1)
	check("a change of redirect bits or level rebuilds nothing", counts.listBuilds == builds, (counts.listBuilds - builds) .. " builds")
	if failures > 0 then
		print(string.format("%d check%s failed.", failures, failures == 1 and "" or "s"))
		os.exit(1)
	end
	print("All checks passed.")
	return
end

--[[ Retail: the client's tables and the tunings' levels ]]--
BUILD = BUILD or newestBuild()
if not (BUILD and loadTables(BUILD)) then
	print(string.format("FAIL: %s has no ConditionalContentTuning-<build>.csv and ContentTuning-<build>.csv%s; give the folder that has them (step 2j downloads them).",
		TABLES_DIR, BUILD and (" for " .. BUILD) or ""))
	os.exit(1)
end
print(string.format("The game's levels follow the %s tables in %s", BUILD, TABLES_DIR))

do
	local handle = io.open(ADDON_DIR .. "/../data/tunings.jsonl", "rb")
	if handle then
		for line in handle:lines() do
			local id, level = line:match('^{"id":(%d+),"level":(%d+)')
			if id then tuningLevel[tonumber(id)] = tonumber(level) end
		end
		handle:close()
	end
end
local noLevel, wrongCeiling = {}, {}
for tuning in pairs(TUNING_SAMPLE) do
	if not tuningLevel[tuning] then noLevel[tuning] = true end
end
for questId, tuning in pairs(QUEST_TUNING) do
	if MAX_LEVEL[questId] then
		local minimum = MIN_LEVEL[questId] or QUESTS[questId][2] or 0
		if tuningMinimum[tuning] and tuningMinimum[tuning] ~= minimum then tuningSplit[tuning] = true end
		tuningMinimum[tuning] = math.min(tuningMinimum[tuning] or minimum, minimum)
		if MAX_LEVEL[questId] ~= tuningLevel[tuning] then wrongCeiling[questId] = true end
	end
end
check("every sampled tuning has its level in data\\tunings.jsonl", next(noLevel) == nil, count(noLevel) .. ": " .. idList(noLevel))
check("each sampled tuning's scaling quests share one minimum", next(tuningSplit) == nil, count(tuningSplit) .. ": " .. idList(tuningSplit))
check("and a scaling quest's maxLevel is its tuning's level", next(wrongCeiling) == nil, count(wrongCeiling) .. ": " .. idList(wrongCeiling))

--[[ The readings of 16 October 2026 ]]--
print("The ten quests read on 16 October 2026, at level 90, from held samples")
boot()
for state, bits in pairs({nazmir = NAZMIR_BITS, silvermoon = PROBE_BITS}) do
	game.bits, game.level = bits, LEVEL_CAP
	holdSamples(allTunings())
	forget()
	local wrong = {}
	for questId, reading in pairs(READINGS[state]) do
		local level = core.Shown(questId, QUESTS[questId], LEVEL_CAP)
		if level ~= reading then wrong[#wrong + 1] = string.format("%d reads %s, read %d", questId, tostring(level), reading) end
	end
	check(string.format("in %s each reads what the user read", state == "nazmir" and "Nazmir" or "Silvermoon City"), #wrong == 0,
		table.concat(wrong, "; "))
end

--[[ The probe's state, every sample held ]]--
print("The probe's redirect bits, every sample held: the stored levels, but for the quests at their tuning's minimum")
boot()
game.bits, game.titles, game.listShown = PROBE_BITS, true, true
holdSamples(allTunings())
local everyTuning = allTunings()
local PVP_MARK = "|A:questlog-questtypeicon-pvp:14:14|a "
local otherThanStored, notAtMinimum = {}, {}
for _, level in ipairs({1, 10, 30, 60, 90}) do
	game.level = level
	forget()
	local wrong, other = {}, {}
	for questId, e in pairs(QUESTS) do
		local got, want = core.Shown(questId, e, level), expectedLevel(questId, PROBE_BITS, level, everyTuning)
		if got ~= want then wrong[questId] = true end
		if got ~= storedLevel(questId, level) then
			other[questId] = true
			local tuning = QUEST_TUNING[questId]
			if MAX_LEVEL[questId] or tuningMinimum[tuning] or e[2] == tuningLevel[tuning] then notAtMinimum[questId] = true end
			otherThanStored[questId] = true
		end
	end
	settings(LOW_LEVEL)
	local filterWrong = {}
	for _, view in ipairs({"L", "M"}) do
		local keep = core.Filter(view)
		for questId in pairs(QUESTS) do
			local want = not isLow(expectedLevel(questId, PROBE_BITS, level, everyTuning) or 0, level)
			if keep(questId) ~= want then filterWrong[view .. questId] = true end
		end
	end
	settings()
	local rowWrong, orderWrong = {}, {}
	for categoryId in pairs(categories) do
		env.qcUpdateQuestList(categoryId, 1)
		local previousShown, previousOwn = -math.huge, -math.huge
		for i = 1, 16 do
			local row = env["qcMenuButton" .. i]
			if not row.shown then break end
			local questId = row.QuestID
			local shown, own = expectedLevel(questId, PROBE_BITS, level, everyTuning) or 0, QUESTS[questId][2] or 0
			local name = ((env.qcQuestPvP and env.qcQuestPvP[questId]) and PVP_MARK or "") .. "Client " .. questId
			if row.QuestName.text ~= (shown > 0 and string.format("[%d] %s", shown, name) or name) then rowWrong[questId] = true end
			if shown < previousShown or (shown == previousShown and own < previousOwn) then orderWrong[questId] = true end
			previousShown, previousOwn = shown, own
		end
	end
	check(string.format("level %d: every quest reads its tuning's level from a sample, or its stored one; %d read other than stored", level, count(other)),
		next(wrong) == nil, count(wrong) .. " wrong: " .. idList(wrong))
	check(string.format("level %d: the low-level filter of the list and the map follows", level), next(filterWrong) == nil, count(filterWrong) .. " wrong")
	check(string.format("level %d: the list's rows show it, in order (first 16 rows of each category)", level), next(rowWrong) == nil and next(orderWrong) == nil,
		count(rowWrong) .. " rows, " .. count(orderWrong) .. " out of order")
end
check(string.format("the %d quests read other than stored are all at their tuning's minimum with an own level that isn't it: %s",
	count(otherThanStored), idList(otherThanStored, 60)), next(notAtMinimum) == nil, count(notAtMinimum) .. " are not: " .. idList(notAtMinimum))
check("and with every sample held the list asked the game nothing", askedTotal() == 0, askedTotal() .. " asked")

--[[ A list's category build, and its answers ]]--
-- The tunings of a category's quests that a list build should ask about: those with a quest stored below the
-- character's level and no sample held.
local function neededTunings(categoryId, level)
	local need = {}
	for _, questId in ipairs(questsOf(categoryId)) do
		local tuning = QUEST_TUNING[questId]
		if tuning and (storedLevel(questId, level) or 0) < level then
			local held = false
			for _, sample in ipairs(TUNING_SAMPLE[tuning]) do held = held or game.held[sample] end
			if not held then need[tuning] = true end
		end
	end
	return need
end

-- What the game was asked since the addon was last loaded: by tuning, the samples asked for and how often.
local function askedByTuning()
	local byTuning, others = {}, {}
	for questId, times in pairs(game.asked) do
		local tuning = SAMPLE_TUNING[questId]
		if tuning then
			byTuning[tuning] = byTuning[tuning] or {}
			byTuning[tuning][questId] = times
		else
			others[questId] = times
		end
	end
	return byTuning, others
end

local function sameSet(a, b)
	for key in pairs(a) do if not b[key] then return false end end
	for key in pairs(b) do if not a[key] then return false end end
	return true
end

-- The quests a map's pins draw: every quest on them the filter keeps, as the level each should read decides.
local function expectedMapQuests(mapId, bits, level, tuningHeld)
	local quests = {}
	for _, pin in ipairs(env.qcPinDB[mapId] or {}) do
		for _, questId in ipairs(pin[6]) do
			if not QUESTS[questId] or not isLow(expectedLevel(questId, bits, level, tuningHeld) or 0, level) then quests[questId] = true end
		end
	end
	return quests
end

local function rowsShown()
	local rows = {}
	for i = 1, 16 do
		local row = env["qcMenuButton" .. i]
		if row.shown then rows[#rows + 1] = row end
	end
	return rows
end

local function heldTunings()
	local held = {}
	for questId in pairs(game.held) do
		if SAMPLE_TUNING[questId] then held[SAMPLE_TUNING[questId]] = true end
	end
	return held
end

print("Nazmir at level 90 with the Endeavor on (bit 34): stored levels until the list's samples are answered, then the game's")
boot()
game.bits, game.level, game.titles, game.mapId = NAZMIR_BITS, LEVEL_CAP, true, NAZMIR_MAP
local nazmirQuests = questsOf(NAZMIR_CATEGORY)
local moved, movedQuests = {}, {}
for _, questId in ipairs(nazmirQuests) do
	local tuning = QUEST_TUNING[questId]
	if tuning and landsOn(tuning, NAZMIR_BITS) ~= landsOn(tuning, PROBE_BITS) then
		moved[tuning], movedQuests[questId] = true, true
	end
end
check(string.format("bit 34 moves %d of Nazmir's tunings, %d of its %d quests: %s", count(moved), count(movedQuests), #nazmirQuests, idList(moved)),
	count(moved) > 0)
local wrong, lowBefore = {}, {}
forget()
for _, questId in ipairs(nazmirQuests) do
	if core.Shown(questId, QUESTS[questId], LEVEL_CAP) ~= storedLevel(questId, LEVEL_CAP) then wrong[questId] = true end
	if movedQuests[questId] and isLow(storedLevel(questId, LEVEL_CAP) or 0, LEVEL_CAP) then lowBefore[questId] = true end
end
check("until a sample is held, each of Nazmir's quests reads its stored level", next(wrong) == nil, count(wrong) .. " do not")
settings(LOW_LEVEL)
local keep = core.Filter("L")
local keptBefore = 0
for questId in pairs(lowBefore) do if keep(questId) then keptBefore = keptBefore + 1 end end
check(string.format("and the low-level filter hides the %d of them on a moved tuning stored below level 85", count(lowBefore)),
	count(lowBefore) > 0 and keptBefore == 0, keptBefore .. " kept")
fakeMap.mapId = NAZMIR_MAP
env.qcMapDataProvider:RefreshAllData()
advance(10)
check("Nazmir's map draws the quests its stored levels keep, asking the game nothing",
	sameSet(fakeMap.quests, expectedMapQuests(NAZMIR_MAP, NAZMIR_BITS, LEVEL_CAP, {})) and askedTotal() == 0,
	count(fakeMap.quests) .. " quests drawn, " .. askedTotal() .. " asked")
local need = neededTunings(NAZMIR_CATEGORY, LEVEL_CAP)
game.listShown = true
local builds, refreshes = counts.listBuilds, counts.mapRefreshes
env.qcUpdateQuestList(NAZMIR_CATEGORY, 1)
advance(10)
local byTuning, others = askedByTuning()
local firstOnly = true
for tuning, asked in pairs(byTuning) do
	if count(asked) ~= 1 or asked[TUNING_SAMPLE[tuning][1]] ~= 1 then firstOnly = false end
end
check(string.format("the list asked for the first sample of each of the %d tunings with a quest stored below level 90, once", count(need)),
	sameSet(byTuning, need) and firstOnly and next(others) == nil, string.format("%d tunings asked about, %d other quests", count(byTuning), count(others)))
check("the answers rebuilt the list once", counts.listBuilds - builds == 2, (counts.listBuilds - builds - 1) .. " rebuilds")
check("and redrew no map", counts.mapRefreshes == refreshes, (counts.mapRefreshes - refreshes) .. " redraws")
forget()
local held = heldTunings()
local wrongAfter, notNinety, keptAfter = {}, {}, 0
for _, questId in ipairs(nazmirQuests) do
	local level = core.Shown(questId, QUESTS[questId], LEVEL_CAP)
	if level ~= expectedLevel(questId, NAZMIR_BITS, LEVEL_CAP, held) then wrongAfter[questId] = true end
	if movedQuests[questId] and level ~= 90 then notNinety[questId] = true end
end
check("once answered, each of Nazmir's quests reads its tuning's level from the sample", next(wrongAfter) == nil, count(wrongAfter) .. " do not")
check(string.format("the %d on a tuning bit 34 moves read 90", count(movedQuests)), next(notNinety) == nil, count(notNinety) .. " do not")
settings(LOW_LEVEL)
keep = core.Filter("L")
for questId in pairs(lowBefore) do if keep(questId) then keptAfter = keptAfter + 1 end end
check("and the low-level filter keeps them", keptAfter == count(lowBefore), keptAfter .. " of " .. count(lowBefore) .. " kept")
env.qcUpdateQuestList(NAZMIR_CATEGORY, 1)
local rows, rowsWrong, ninety = rowsShown(), 0, 0
for _, row in ipairs(rows) do
	local level = expectedLevel(row.QuestID, NAZMIR_BITS, LEVEL_CAP, held) or 0
	local name = "Client " .. row.QuestID
	if row.QuestName.text ~= (level > 0 and string.format("[%d] %s", level, name) or name) then rowsWrong = rowsWrong + 1 end
	if movedQuests[row.QuestID] and row.QuestName.text == string.format("[90] %s", name) then ninety = ninety + 1 end
end
check(string.format("the list's rows show them as [90] (%d of its first %d rows)", ninety, #rows), #rows > 0 and rowsWrong == 0 and ninety > 0,
	rowsWrong .. " rows wrong")
advance(10)
local asked = askedTotal()
env.qcMapDataProvider:RefreshAllData()
advance(10)
check("Nazmir's map now draws the quests the game's levels keep, asking the game nothing",
	sameSet(fakeMap.quests, expectedMapQuests(NAZMIR_MAP, NAZMIR_BITS, LEVEL_CAP, held)) and askedTotal() == asked,
	count(fakeMap.quests) .. " quests drawn, " .. (askedTotal() - asked) .. " asked")

print("Chromie Time (bit 0 alone) at level 40, in Elwynn Forest")
boot()
game.bits, game.level, game.titles, game.mapId, game.listShown = CHROMIE_BITS, 40, true, 37, true
local riverpaw = 11
forget()
check(string.format("until a sample is held, %d reads its stored level, %s", riverpaw, tostring(storedLevel(riverpaw, 40))),
	core.Shown(riverpaw, QUESTS[riverpaw], 40) == storedLevel(riverpaw, 40))
settings(LOW_LEVEL)
check("and the low-level filter hides it", isLow(storedLevel(riverpaw, 40), 40) and not core.Filter("L")(riverpaw))
need = neededTunings(ELWYNN_CATEGORY, 40)
builds = counts.listBuilds
env.qcUpdateQuestList(ELWYNN_CATEGORY, 1)
advance(10)
byTuning, others = askedByTuning()
check(string.format("the list asked for one sample of each of the %d tunings with a quest stored below level 40", count(need)),
	sameSet(byTuning, need) and next(others) == nil, count(byTuning) .. " tunings asked about")
forget()
local chromieLevel = gameLevel(QUEST_TUNING[riverpaw], CHROMIE_BITS, 40)
check(string.format("once answered, %d reads the game's %d", riverpaw, chromieLevel), chromieLevel == 40 and core.Shown(riverpaw, QUESTS[riverpaw], 40) == 40)
check("is kept by the low-level filter", core.Filter("L")(riverpaw))
local shownAt40 = false
for _, row in ipairs(rowsShown()) do
	if row.QuestID == riverpaw then shownAt40 = row.QuestName.text == "[40] Client " .. riverpaw end
end
check("and shows as [40] on the rebuilt list", shownAt40 and counts.listBuilds - builds == 2, (counts.listBuilds - builds - 1) .. " rebuilds")
held = heldTunings()
wrong = {}
for _, questId in ipairs(questsOf(ELWYNN_CATEGORY)) do
	if core.Shown(questId, QUESTS[questId], 40) ~= expectedLevel(questId, CHROMIE_BITS, 40, held) then wrong[questId] = true end
end
check("each of Elwynn Forest's quests reads its tuning's level from the sample", next(wrong) == nil, count(wrong) .. " do not")

print("Answers that agree with the stored levels: the probe's bits, in Elwynn Forest at level 90")
boot()
game.bits, game.level, game.titles, game.mapId, game.listShown = PROBE_BITS, LEVEL_CAP, true, 37, true
settings()
need = neededTunings(ELWYNN_CATEGORY, LEVEL_CAP)
builds = counts.listBuilds
env.qcUpdateQuestList(ELWYNN_CATEGORY, 1)
advance(10)
byTuning = askedByTuning()
check(string.format("the list asked about the %d tunings with a quest stored below level 90", count(need)), sameSet(byTuning, need) and count(need) > 0)
check("and, the answers agreeing, rebuilt nothing", counts.listBuilds - builds == 1, (counts.listBuilds - builds - 1) .. " rebuilds")
forget()
wrong = {}
for _, questId in ipairs(questsOf(ELWYNN_CATEGORY)) do
	if core.Shown(questId, QUESTS[questId], LEVEL_CAP) ~= storedLevel(questId, LEVEL_CAP) then wrong[questId] = true end
end
check("Elwynn Forest's quests keep their stored levels", next(wrong) == nil, count(wrong) .. " do not")

print("Every category's list built in turn, Nazmir's bits at level 90, nothing held")
boot()
game.bits, game.level, game.titles, game.listShown = NAZMIR_BITS, LEVEL_CAP, true, true
settings()
local needAll = {}
builds, refreshes = counts.listBuilds, counts.mapRefreshes
for _, categoryId in ipairs(sortedKeys(categories)) do
	for tuning in pairs(neededTunings(categoryId, LEVEL_CAP)) do needAll[tuning] = true end
	env.qcUpdateQuestList(categoryId, 1)
end
advance(60)
byTuning, others = askedByTuning()
local twice, several = {}, {}
for tuning, askedFor in pairs(byTuning) do
	if count(askedFor) > 1 then several[tuning] = true end
	for questId, times in pairs(askedFor) do if times > 1 then twice[questId] = true end end
end
check(string.format("%d builds asked about the %d tunings that needed it, each for one sample, once", count(categories), count(needAll)),
	sameSet(byTuning, needAll) and next(twice) == nil and next(several) == nil and next(others) == nil,
	string.format("%d tunings, %d asked twice, %d for several samples, %d other quests", count(byTuning), count(twice), count(several), count(others)))
check("never two samples of one tuning at once", next(game.overlap) == nil, count(game.overlap) .. " tunings")
check("the answers rebuilt the list at most once", counts.listBuilds - builds - count(categories) <= 1, (counts.listBuilds - builds - count(categories)) .. " rebuilds")
check("and redrew no map", counts.mapRefreshes == refreshes, (counts.mapRefreshes - refreshes) .. " redraws")

print("A sample that fails twice gives way to the next")
boot()
game.bits, game.level, game.titles, game.listShown = NAZMIR_BITS, LEVEL_CAP, true, true
settings()
local failing
for _, tuning in ipairs(sortedKeys(neededTunings(NAZMIR_CATEGORY, LEVEL_CAP))) do
	if moved[tuning] and #TUNING_SAMPLE[tuning] >= 2 and not failing then failing = tuning end
end
local first, second = TUNING_SAMPLE[failing][1], TUNING_SAMPLE[failing][2]
game.fail[first] = 2
builds, refreshes = counts.listBuilds, counts.mapRefreshes
env.qcUpdateQuestList(NAZMIR_CATEGORY, 1)
advance(5)
check(string.format("tuning %d: its first sample %d failed, and its second, %d, is not asked while the first waits for its second try", failing, first, second),
	game.asked[first] == 1 and not game.asked[second])
check("the other answers rebuilt the list once without waiting for it", counts.listBuilds - builds == 2, (counts.listBuilds - builds - 1) .. " rebuilds")
advance(60)
local secondFailedAt, secondAskedAt
for _, answer in ipairs(game.answerLog) do
	if answer.quest == first and not answer.success then secondFailedAt = answer.at end
end
for _, entry in ipairs(game.askLog) do
	if entry.quest == second then secondAskedAt = entry.at end
end
check("the first was tried again, failed again, and only then was the second asked, once",
	game.asked[first] == 2 and game.asked[second] == 1 and secondAskedAt and secondFailedAt and secondAskedAt >= secondFailedAt,
	string.format("first asked %s times, second asked at %s, first's last failure at %s", tostring(game.asked[first]), tostring(secondAskedAt), tostring(secondFailedAt)))
check("never two samples of one tuning at once", next(game.overlap) == nil)
forget()
check(string.format("its quests then read the second sample's level, %d", gameLevel(failing, NAZMIR_BITS, LEVEL_CAP)),
	core.Tuning.Level(failing) == gameLevel(failing, NAZMIR_BITS, LEVEL_CAP))
check("and that answer rebuilt the list once more, a batch of its own", counts.listBuilds - builds == 3, (counts.listBuilds - builds - 1) .. " rebuilds")
check("no map was redrawn", counts.mapRefreshes == refreshes)

print("The zone, the level and the redirect bits changing make the levels be read again")
boot()
game.titles = true
check("the addon listens for the player's CtrOptions", game.registered.UNIT_CTR_OPTIONS == "player")
check("and for its level", game.registered.PLAYER_LEVEL_UP == true)
holdSamples({[QUEST_TUNING[riverpaw]] = true})
game.bits, game.level = PROBE_BITS, LEVEL_CAP
forget()
local before = core.Shown(riverpaw, QUESTS[riverpaw], LEVEL_CAP)
game.bits = NAZMIR_BITS
local cached = core.Shown(riverpaw, QUESTS[riverpaw], LEVEL_CAP)
fireEvent("ZONE_CHANGED_NEW_AREA")
local afterZone = core.Shown(riverpaw, QUESTS[riverpaw], LEVEL_CAP)
check(string.format("%d reads %d, keeps it until the zone changes, then reads %d", riverpaw, before, afterZone), before == 30 and cached == 30 and afterZone == 90)
game.bits, game.level = CHROMIE_BITS, 40
fireEvent("UNIT_CTR_OPTIONS", "player")
local atForty = core.Shown(riverpaw, QUESTS[riverpaw], 40)
game.level = 41
cached = core.Shown(riverpaw, QUESTS[riverpaw], 41)
fireEvent("PLAYER_LEVEL_UP", 41)
check("in Chromie Time it reads 40 at level 40, keeps it until the level changes, then 41",
	atForty == 40 and cached == 40 and core.Shown(riverpaw, QUESTS[riverpaw], 41) == 41)
game.listShown = true
env.qcUpdateQuestList(ELWYNN_CATEGORY, 1)
advance(10)
builds, refreshes = counts.listBuilds, counts.mapRefreshes
fireEvent("UNIT_CTR_OPTIONS", "player")
advance(1)
check("a change of the CtrOptions rebuilds the list once, and redraws no map", counts.listBuilds - builds == 1 and counts.mapRefreshes == refreshes,
	(counts.listBuilds - builds) .. " builds, " .. (counts.mapRefreshes - refreshes) .. " redraws")
game.level = 42
check("and a view built reads them again", core.Filter("L") and core.Shown(riverpaw, QUESTS[riverpaw], 42) == 42)

if failures > 0 then
	print(string.format("%d check%s failed.", failures, failures == 1 and "" or "s"))
	os.exit(1)
end
print("All checks passed.")
