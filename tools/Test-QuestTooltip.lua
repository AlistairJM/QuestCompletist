--[[
Checks the quest list's information tooltip (qcUpdateTooltip in qcTooltips.lua): the storyline's name,
which comes from the game when the game names the line the list shows, and the type line, which gives
the game's own words for a quest's classification and tag.

Loads the addon's own files with stand-ins for the WoW API. The stand-ins for the game's quest calls
answer what a check tells them to, so each case says exactly what the game said: the same line as ours,
another line, nothing, an error, a secret value, or no such function at all. The tooltip stand-in keeps
every line it is given, and the checks read those.

Then every quest of a profession that has a quest to do first, for a character with that profession and no
other: with every quest it could do done, the list's filter (requirements and profession on) keeps it, and
with nothing done, its "Required Quest" lines name no quest of another profession.

With a third argument, the lines of each case are written to that file, so one run on the code before a
change and one after can be compared line by line.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-QuestTooltip.lua
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-QuestTooltip.lua QuestCompletist QuestCompletist_Camelot.toc lines.txt
Prints each check and exits with 1 if one fails. Run it for both games' TOCs.
]]

local ADDON_DIR = arg and arg[1] or "QuestCompletist"
local TOC_FILE = arg and arg[2] or "QuestCompletist.toc"
local RECORD_FILE = arg and arg[3]

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

--[[ What the game says, set by each case ]]--
local SECRET = "<secret>"
local ctx = {
	frames = {}, inLog = {},
	lineInfo = nil, lineCalls = {},
	classification = 7, classificationCalls = 0,
	tag = nil,
	campaign = nil,
	absent = {},
}

local Enum = {
	QuestClassification = {Important = 0, Legendary = 1, Campaign = 2, Calling = 3, Meta = 4, Recurring = 5,
		Questline = 6, Normal = 7, BonusObjective = 8, Threat = 9, WorldQuest = 10},
	QuestTag = {Group = 1, PvP = 41, Raid = 62, Dungeon = 81, Legendary = 83, Heroic = 85, Raid10 = 88, Raid25 = 89,
		Scenario = 98, Account = 102, CombatAlly = 266, Delve = 288},
	QuestTagType = {Dungeon = 6, Raid = 8},
}

local STRINGS = {
	STAT_FORMAT = "%s:", TYPE = "Type",
	QUEST_CLASSIFICATION_CALLING = "Calling", QUEST_CLASSIFICATION_IMPORTANT = "Important",
	QUEST_CLASSIFICATION_CAMPAIGN = "Campaign", QUEST_CLASSIFICATION_LEGENDARY = "Legendary",
	QUEST_CLASSIFICATION_META = "Meta", QUEST_CLASSIFICATION_RECURRING = "Repeatable",
	QUEST_CLASSIFICATION_QUESTLINE = "Storyline",
}

local env
local function stringsInto(target, strings)
	for key, value in pairs(strings) do target[key] = value end
end

local function classificationTable()
	local c = Enum.QuestClassification
	return {
		[c.Campaign] = {text = env.QUEST_CLASSIFICATION_CAMPAIGN, atlas = "CampaignAvailableQuestIcon", size = 16},
		[c.Calling] = {text = env.QUEST_CLASSIFICATION_CALLING, atlas = "CampaignAvailableDailyQuestIcon", size = 16},
		[c.Important] = {text = env.QUEST_CLASSIFICATION_IMPORTANT, atlas = "importantavailablequesticon", size = 16},
		[c.Legendary] = {text = env.QUEST_CLASSIFICATION_LEGENDARY, atlas = "legendaryavailablequesticon", size = 16},
		[c.Meta] = {text = env.QUEST_CLASSIFICATION_META, atlas = "Wrapperavailablequesticon", size = 16},
		[c.Recurring] = {text = env.QUEST_CLASSIFICATION_RECURRING, atlas = "Recurringavailablequesticon", size = 16},
		[c.Questline] = {text = env.QUEST_CLASSIFICATION_QUESTLINE, atlas = "questlog-storylineicon", size = 20},
	}
end

-- Constants.lua's QUEST_TAG_ATLAS and WORLD_QUEST_TYPE_ATLAS, and QuestUtils.lua's QuestUtils_GetQuestTagAtlas.
local QUEST_TAG_ATLAS = {
	COMPLETED = "questlog-questtypeicon-quest", DAILY = "questlog-questtypeicon-daily",
	[Enum.QuestTag.Dungeon] = "questlog-questtypeicon-dungeon", [98] = "questlog-questtypeicon-scenario",
	[Enum.QuestTag.Group] = "questlog-questtypeicon-group", [Enum.QuestTag.PvP] = "questlog-questtypeicon-pvp",
	[Enum.QuestTag.Heroic] = "questlog-questtypeicon-heroic", [Enum.QuestTag.Raid] = "questlog-questtypeicon-raid",
	[Enum.QuestTag.Raid10] = "questlog-questtypeicon-raid", [Enum.QuestTag.Raid25] = "questlog-questtypeicon-raid",
	[Enum.QuestTag.Delve] = "questlog-questtypeicon-delves",
}
local WORLD_QUEST_TYPE_ATLAS = {
	[Enum.QuestTagType.Dungeon] = "questlog-questtypeicon-dungeon", [Enum.QuestTagType.Raid] = "questlog-questtypeicon-raid",
}
local function questUtilsGetQuestTagAtlas(tagID, worldQuestType)
	if worldQuestType ~= nil then return WORLD_QUEST_TYPE_ATLAS[worldQuestType] end
	return tagID and QUEST_TAG_ATLAS[tagID]
end

--[[ The tooltip stand-in keeps every line ]]--
local counters = {}
local function newRecorder(kind)
	counters[kind] = (counters[kind] or 0) + 1
	local name = kind .. counters[kind]
	return setmetatable({__name = name}, {__index = function(_, method)
		if not method:match("^%u") then return nil end
		return function(_, ...)
			if method:sub(1, 6) == "Create" then return newRecorder(method:sub(7):lower()) end
		end
	end})
end

local function newTooltip(name)
	local tooltip = newRecorder("tooltip")
	tooltip.lines, tooltip.entries, tooltip.shown, tooltip.hyperlinks = 0, {}, false, {}
	local function addLine(self, left, right)
		self.lines = self.lines + 1
		self.entries[self.lines] = {left = left, right = right}
		for _, side in ipairs({"Left", "Right"}) do
			local key = name .. "Text" .. side .. self.lines
			if rawget(env, key) == nil then env[key] = newRecorder(side:lower()) end
		end
	end
	tooltip.AddLine = function(self, text) addLine(self, text, nil) end
	tooltip.AddDoubleLine = function(self, left, right) addLine(self, left, right) end
	tooltip.SetHyperlink = function(self, link) self.hyperlinks[#self.hyperlinks + 1] = link end
	tooltip.ClearLines = function(self) self.lines, self.entries, self.hyperlinks = 0, {}, {} end
	tooltip.NumLines = function(self) return self.lines end
	tooltip.Show = function(self) self.shown = true end
	tooltip.Hide = function(self) self.shown = false end
	tooltip.IsShown = function(self) return self.shown end
	return tooltip
end

--[[ Load the addon in TOC order ]]--
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
		HookScript = function() end, GetCanvas = function() return {GetSize = function() return 1000, 700 end} end,
		GetScale = function() return 1 end, AddDataProvider = function() end,
	},
	GameTooltip = newRecorder("gametooltip"),
	GameTooltipText = {__name = "GameTooltipText"},
	GameTooltipTextSmall = {__name = "GameTooltipTextSmall"},
	GameTooltipHeaderText = {__name = "GameTooltipHeaderText"},
	NORMAL_FONT_COLOR = {GetRGB = function() return 1, 0.82, 0 end},
	IsShiftKeyDown = function() return false end,
	IsModifierKeyDown = function() return false end,
	IsInInstance = function() return false end,
	HaveQuestData = function() return true end,
	C_AddOns = {IsAddOnLoaded = function() return false end},
	UnitFactionGroup = function() return "Alliance", "Alliance" end,
	UnitRace = function() return "NightElf", "NightElf" end,
	UnitClass = function() return "DRUID", "DRUID" end,
	UnitLevel = function() return 1000 end,
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
	C_MajorFactions = stubTable({GetCurrentRenownLevel = function() return 1000 end, GetMajorFactionData = function() return nil end}),
	C_SkillInfo = stubTable({GetSkillLineInfoByID = function() return {rank = 1000, modifier = 0} end}),
	C_QuestLog = stubTable({
		GetLogIndexForQuestID = function(questId) return ctx.inLog[questId] end,
		IsComplete = function() return false end,
		IsQuestFlaggedCompleted = function() return false end,
		IsQuestFlaggedCompletedOnAccount = function() return false end,
		GetTitleForQuestID = function() return nil end,
		RequestLoadQuestByID = function() end,
		IsWorldQuest = function() return false end,
		GetQuestTagInfo = function(questId)
			local tag = ctx.tag
			if type(tag) == "function" then return tag(questId) end
			return tag
		end,
	}),
	C_TaskQuest = stubTable({GetQuestInfoByQuestID = function() return nil end}),
	C_TooltipInfo = stubTable({GetHyperlink = function() return nil end}),
	C_DateAndTime = stubTable({GetCurrentCalendarTime = function() return {year = 2026, month = 10, monthDay = 11, hour = 14, minute = 30} end}),
	C_Reputation = stubTable({GetFactionDataByID = function() return nil end}),
	C_Map = stubTable({GetBestMapForUnit = function() return nil end, GetMapInfo = function() return {name = "A Zone"} end}),
	C_ClassColor = {GetClassColor = function(class)
		local hex = ({DRUID = "ff7d0a", HUNTER = "aad372", MAGE = "3fc7eb"})[class] or "ffffff"
		return {GenerateHexColorMarkup = function() return "|cff" .. hex end}
	end},
	C_QuestLine = {
		GetQuestLineQuests = function() return {} end,
		GetQuestLineInfo = function(...)
			ctx.lineCalls[#ctx.lineCalls + 1] = {...}
			local answer = ctx.lineInfo
			if type(answer) == "function" then return answer(...) end
			return answer
		end,
	},
	C_QuestInfoSystem = {
		GetQuestClassification = function(...)
			ctx.classificationCalls = ctx.classificationCalls + 1
			local answer = ctx.classification
			if type(answer) == "function" then return answer(...) end
			return answer
		end,
	},
	C_CampaignInfo = {
		GetCampaignID = function() return ctx.campaign and ctx.campaign.id or 0 end,
		GetCampaignInfo = function() return ctx.campaign and {name = ctx.campaign.name} or nil end,
		GetChapterIDs = function() return ctx.campaign and ctx.campaign.chapters or {} end,
	},
	Enum = Enum,
	QUEST_TAG_ATLAS = QUEST_TAG_ATLAS,
	WORLD_QUEST_TYPE_ATLAS = WORLD_QUEST_TYPE_ATLAS,
	QuestUtils_GetQuestTagAtlas = questUtilsGetQuestTagAtlas,
	issecretvalue = function(value) return value == SECRET end,
}
stringsInto(env, STRINGS)
env.QuestUtil = {GetQuestClassificationInfo = function(classification) return classificationTable()[classification] end}
env._G = env
-- A name the stand-ins don't define answers with the do-anything dummy, unless a case lists it as missing.
setmetatable(env, {__index = function(_, key)
	if ctx.absent[key] then return nil end
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
env.qcCharacterCompletions = {}

--[[ Quests from the addon's own data: one in a storyline of three or more, one in none, one that comes back daily ]]--
local QUESTS = env.qcQuestDatabase
local ids = {}
for questId in pairs(QUESTS) do ids[#ids + 1] = questId end
table.sort(ids)
local storyQuest, plainQuest, dailyQuest
for _, questId in ipairs(ids) do
	local quest = QUESTS[questId]
	local line = quest[8] and env.qcQuestLines[quest[8]]
	if not storyQuest and line and #line.quests >= 3 and quest[4] == 1 and line.name ~= "" then
		storyQuest = questId
	elseif not plainQuest and not quest[8] and quest[4] == 1 then
		plainQuest = questId
	elseif not dailyQuest and not quest[8] and quest[4] == 4 then
		dailyQuest = questId
	end
end
assert(storyQuest and plainQuest and dailyQuest, "the data has no storyline, plain and daily quest")
local STORYLINE_ID = QUESTS[storyQuest][8]
local STORED_NAME = env.qcQuestLines[STORYLINE_ID].name
local GAME_NAME = "Der Name Aus Dem Spiel"
local OTHER_ID = STORYLINE_ID + 1000000

--[[ Drawing a tooltip, and reading it ]]--
env.qcMenuButton1 = {QuestID = nil}
env.qcQuestInformationTooltipSetup()
local tooltip = env.qcQuestInformationTooltip

local STANDINS = {
	C_QuestLine = env.C_QuestLine, C_QuestInfoSystem = env.C_QuestInfoSystem, Enum = Enum,
	QuestUtils_GetQuestTagAtlas = questUtilsGetQuestTagAtlas,
}
local CALLS = {
	lineInfo = env.C_QuestLine.GetQuestLineInfo, classification = env.C_QuestInfoSystem.GetQuestClassification,
	tagInfo = env.C_QuestLog.GetQuestTagInfo,
}

local function reset()
	ctx.lineInfo, ctx.lineCalls = nil, {}
	ctx.classification, ctx.classificationCalls = Enum.QuestClassification.Normal, 0
	ctx.tag, ctx.campaign, ctx.absent = nil, nil, {}
	stringsInto(env, STRINGS)
	for name, standin in pairs(STANDINS) do env[name] = standin end
	env.QuestUtil = {GetQuestClassificationInfo = function(classification) return classificationTable()[classification] end}
	env.C_QuestLine.GetQuestLineInfo = CALLS.lineInfo
	env.C_QuestInfoSystem.GetQuestClassification = CALLS.classification
	env.C_QuestLog.GetQuestTagInfo = CALLS.tagInfo
end

local function missing(name)
	env[name] = nil
	ctx.absent[name] = true
end

local function currentLines()
	local lines = {}
	for i, entry in ipairs(tooltip.entries) do
		lines[i] = entry.right and (entry.left .. " | " .. entry.right) or entry.left
	end
	return lines, tooltip.qcDividersUsed or 0
end

local function draw(questId)
	env.qcMenuButton1.QuestID = questId
	env.qcUpdateTooltip(1)
	return currentLines()
end

local function find(lines, text)
	for i, line in ipairs(lines) do
		if line:find(text, 1, true) then return i, line end
	end
end

local function typeRows(lines)
	local rows = {}
	local label = env.STAT_FORMAT:format(env.TYPE)
	for i, line in ipairs(lines) do
		if line:sub(1, #label + 3) == label .. " | " then
			rows[#rows + 1] = line:sub(#label + 4)
			local nextLine = lines[i + 1]
			while nextLine and nextLine:sub(1, 8) == "  | |cff" do
				rows[#rows + 1] = nextLine:sub(5)
				i = i + 1
				nextLine = lines[i + 1]
			end
			break
		end
	end
	return rows
end

local function sameLines(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do if a[i] ~= b[i] then return false end end
	return true
end

local function textOf(row)
	return row:match("|cff%x%x%x%x%x%x(.-)|r") or row:match("^[^|]*") or row
end

local failures = 0
local function check(label, passed, detail)
	if not passed then failures = failures + 1 end
	print(string.format("  [%s] %s%s", passed and "ok" or "FAIL", label, detail and (" (" .. detail .. ")") or ""))
end

local recordLines = {}
local function recordCase(label, lines)
	recordLines[#recordLines + 1] = "== " .. label
	for _, line in ipairs(lines) do recordLines[#recordLines + 1] = line end
end

print(string.format("Quests: %d in storyline %d (%s), %d in none, %d daily in none", storyQuest, STORYLINE_ID, STORED_NAME, plainQuest, dailyQuest))

local function storylineText(lines)
	local _, line = find(lines, env.STAT_FORMAT:format(env.QUEST_CLASSIFICATION_QUESTLINE) .. " | ")
	return line
end

print("The storyline's name")
reset()
local baseline = draw(storyQuest)
local baselineLine = storylineText(baseline)
check("the tooltip has a storyline line", baselineLine ~= nil)
check("the game, with no answer, leaves our name and position", baselineLine and baselineLine:find(STORED_NAME, 1, true) ~= nil
	and baselineLine:find("(%d+ of %d+)") ~= nil, baselineLine)
check("the game was asked once, about the hovered quest", #ctx.lineCalls == 1 and ctx.lineCalls[1][1] == storyQuest and ctx.lineCalls[1][2] == nil,
	#ctx.lineCalls .. " calls")
recordCase("storyline, the game says nothing", baseline)

reset()
ctx.lineInfo = {questLineID = STORYLINE_ID, questLineName = GAME_NAME}
local named, namedDividers = draw(storyQuest)
local namedLine = storylineText(named)
check("the game names our line: its name is shown", namedLine and namedLine:find(GAME_NAME, 1, true) ~= nil, namedLine)
check("and ours is not", namedLine and namedLine:find(STORED_NAME, 1, true) == nil, namedLine)
check("the position, the bar and the list under it are the same", baselineLine and namedLine
	and namedLine:gsub(GAME_NAME, STORED_NAME) == baselineLine and #named == #baseline and namedDividers >= 1)
recordCase("storyline, the game names our line", named)

reset()
ctx.lineInfo = {questLineID = OTHER_ID, questLineName = GAME_NAME}
local other = draw(storyQuest)
check("the game names another line: ours is shown", storylineText(other) == baselineLine and not find(other, GAME_NAME), storylineText(other))
recordCase("storyline, the game names another line", other)

reset()
ctx.lineInfo = function() return nil end
check("the game answers nothing: ours is shown", storylineText((draw(storyQuest))) == baselineLine)

reset()
ctx.lineInfo = function() error("boom") end
local erroring = draw(storyQuest)
check("the game's call errors: ours is shown and the tooltip is whole", storylineText(erroring) == baselineLine and #erroring == #baseline and tooltip.shown)

reset()
ctx.lineInfo = {questLineID = STORYLINE_ID, questLineName = GAME_NAME}
env.C_QuestLine.GetQuestLineInfo = nil
check("the function is missing: ours is shown", storylineText((draw(storyQuest))) == baselineLine)
reset()
ctx.lineInfo = {questLineID = STORYLINE_ID, questLineName = GAME_NAME}
missing("C_QuestLine")
check("the whole namespace is missing: ours is shown", storylineText((draw(storyQuest))) == baselineLine)

for _, case in ipairs({
	{"an empty name", {questLineID = STORYLINE_ID, questLineName = ""}},
	{"no name", {questLineID = STORYLINE_ID}},
	{"a number for a name", {questLineID = STORYLINE_ID, questLineName = 42}},
	{"a secret name", {questLineID = STORYLINE_ID, questLineName = SECRET}},
	{"no line ID", {questLineName = GAME_NAME}},
	{"an answer that is not a table", "text"},
	{"an answer that errors when read", setmetatable({}, {__index = function() error("secret") end})},
}) do
	reset()
	ctx.lineInfo = case[2]
	check("the game gives " .. case[1] .. ": ours is shown", storylineText((draw(storyQuest))) == baselineLine)
end

reset()
ctx.lineInfo = {questLineID = STORYLINE_ID, questLineName = GAME_NAME}
local noLine = draw(plainQuest)
check("a quest with no storyline of ours never asks the game", #ctx.lineCalls == 0 and storylineText(noLine) == nil and not find(noLine, GAME_NAME))

print("A redraw when the quest's data arrives takes the game's answer")
reset()
check("the line shows ours", storylineText((draw(storyQuest))) == baselineLine)
ctx.lineInfo = {questLineID = STORYLINE_ID, questLineName = GAME_NAME}
QC.RedrawQuestTooltip()
local late = storylineText((currentLines()))
check("then the game's name, once the quest is loaded", late ~= nil and late:find(GAME_NAME, 1, true) ~= nil)

print("The type line: what the game classifies")
local C = Enum.QuestClassification
local label = env.STAT_FORMAT:format(env.TYPE)

reset()
local plain, plainDividers = draw(plainQuest)
check("a normal quest has no type line", #typeRows(plain) == 0 and not find(plain, label))
recordCase("plain quest, the game says Normal", plain)

for _, case in ipairs({{"Important", C.Important}, {"Legendary", C.Legendary}, {"Calling", C.Calling}, {"Meta", C.Meta}}) do
	reset()
	ctx.classification = case[2]
	local lines, dividers = draw(plainQuest)
	local rows = typeRows(lines)
	check(case[1] .. " is a type line, in the game's word", #rows == 1 and textOf(rows[1]) == case[1], table.concat(rows, "; "))
	check("with a divider after it", dividers == plainDividers + 1, dividers .. " against " .. plainDividers)
	recordCase("plain quest, " .. case[1], lines)
end

for _, case in ipairs({{"Normal", C.Normal}, {"BonusObjective", C.BonusObjective}, {"Threat", C.Threat}, {"WorldQuest", C.WorldQuest}, {"a classification not yet in the game's list", 99}}) do
	reset()
	ctx.classification = case[2]
	local lines, dividers = draw(plainQuest)
	check(case[1] .. " is not a type line the game names", #typeRows(lines) == 0 and sameLines(lines, plain) and dividers == plainDividers)
end

print("What the tooltip says already is left out")
reset()
ctx.classification = C.Campaign
ctx.campaign = {id = 77, name = "A Campaign", chapters = {STORYLINE_ID}}
local campaignLines = draw(storyQuest)
check("Campaign, with the campaign line drawn: no type line", find(campaignLines, env.STAT_FORMAT:format(env.QUEST_CLASSIFICATION_CAMPAIGN) .. " | ") ~= nil
	and #typeRows(campaignLines) == 0)
ctx.campaign = nil
local noCampaignLines = draw(plainQuest)
check("Campaign, with no campaign line: the game's word is shown", (function() local rows = typeRows(noCampaignLines) return #rows == 1 and textOf(rows[1]) == "Campaign" end)())

reset()
ctx.classification = C.Questline
local questlineStory = draw(storyQuest)
check("Storyline, with the storyline drawn: no type line", storylineText(questlineStory) ~= nil and #typeRows(questlineStory) == 0)
local questlinePlain = draw(plainQuest)
check("Storyline, with none of ours drawn: the game's word is shown", (function() local rows = typeRows(questlinePlain) return #rows == 1 and textOf(rows[1]) == "Storyline" end)())

reset()
ctx.classification = C.Recurring
local recurringDaily = draw(dailyQuest)
check("Repeatable, on a quest whose type icon says so: no type line", #typeRows(recurringDaily) == 0)
local recurringPlain = draw(plainQuest)
check("Repeatable, on a quest that is typed one-time: the game's word is shown", (function() local rows = typeRows(recurringPlain) return #rows == 1 and textOf(rows[1]) == "Repeatable" end)())

print("The type line: the game's tag")
local Tag = Enum.QuestTag
local function tagOf(tagID, tagName, worldQuestType) return {tagID = tagID, tagName = tagName, worldQuestType = worldQuestType} end
for _, case in ipairs({
	{"Dungeon", tagOf(Tag.Dungeon, "Dungeon")}, {"Group", tagOf(Tag.Group, "Group")}, {"Raid", tagOf(Tag.Raid, "Raid")},
	{"Raid (25)", tagOf(Tag.Raid25, "Raid (25)")}, {"PvP", tagOf(Tag.PvP, "PvP")}, {"Heroic", tagOf(Tag.Heroic, "Heroic")},
	{"Scenario", tagOf(Tag.Scenario, "Scenario")}, {"Delve", tagOf(Tag.Delve, "Delve")},
	{"Elite, which Forever names on its group tag", tagOf(Tag.Group, "Elite")},
	{"a dungeon world quest", tagOf(137, "Dungeon World Quest", Enum.QuestTagType.Dungeon)},
}) do
	reset()
	ctx.tag = case[2]
	local lines, dividers = draw(plainQuest)
	local rows = typeRows(lines)
	check(case[1] .. " is shown, as the game names it", #rows == 1 and textOf(rows[1]) == case[2].tagName, table.concat(rows, "; "))
	check("with a divider after it", dividers == plainDividers + 1)
	recordCase("plain quest, tag " .. case[1], lines)
end
for _, case in ipairs({
	{"Artifact", tagOf(107, "Artifact")}, {"Class", tagOf(21, "Class")}, {"Legendary", tagOf(Tag.Legendary, "Legendary")},
	{"Meta Quest", tagOf(284, "Meta Quest")}, {"a world quest", tagOf(109, "World Quest", 2)}, {"no tag", nil},
	{"a tag with no ID", {tagName = "Nameless"}},
}) do
	reset()
	ctx.tag = case[2]
	local lines = draw(plainQuest)
	check(case[1] .. " is not a tag the game gives an icon: no type line", #typeRows(lines) == 0 and sameLines(lines, plain))
end

reset()
ctx.classification = C.Legendary
ctx.tag = tagOf(Tag.Dungeon, "Dungeon")
local both, bothDividers = draw(plainQuest)
local bothRows = typeRows(both)
check("a classification and a tag share the line's label, one row each", #bothRows == 2 and textOf(bothRows[1]) == "Legendary" and textOf(bothRows[2]) == "Dungeon",
	table.concat(bothRows, "; "))
check("and one divider", bothDividers == plainDividers + 1)
local firstLabelIndex = find(both, label .. " | ")
check("the second row has no label of its own", firstLabelIndex ~= nil and both[firstLabelIndex + 1]:sub(1, 8) == "  | |cff")
recordCase("plain quest, Legendary and Dungeon", both)

reset()
ctx.classification = C.Important
ctx.tag = tagOf(Tag.Dungeon, "Important")
check("the same word twice is said once", #typeRows((draw(plainQuest))) == 1)

reset()
ctx.classification = C.Important
ctx.campaign = {id = 77, name = "A Campaign", chapters = {}}
local withCampaign, withCampaignDividers = draw(plainQuest)
local campaignIndex, typeIndex = find(withCampaign, env.STAT_FORMAT:format(env.QUEST_CLASSIFICATION_CAMPAIGN) .. " | "), find(withCampaign, label .. " | ")
check("beside a campaign line the type line comes first, and both share one divider", typeIndex and campaignIndex and typeIndex < campaignIndex
	and withCampaignDividers == plainDividers + 1)

reset()
ctx.classification = C.Important
local storyWithType = draw(storyQuest)
local _, storyBaseDividers = (function() reset() return draw(storyQuest) end)()
check("in a storyline's quest the type line comes before the storyline and adds no divider", (find(storyWithType, label .. " | ") or math.huge) < find(storyWithType, env.STAT_FORMAT:format(env.QUEST_CLASSIFICATION_QUESTLINE) .. " | ")
	and select(2, (function() reset() ctx.classification = C.Important return draw(storyQuest) end)()) == storyBaseDividers)

print("The game's words, in the player's language")
reset()
stringsInto(env, {STAT_FORMAT = "%s :", TYPE = "Typ", QUEST_CLASSIFICATION_LEGENDARY = "Legendaer"})
ctx.classification = C.Legendary
ctx.tag = tagOf(Tag.Dungeon, "Verlies")
local german = draw(plainQuest)
check("the label, the classification and the tag are the game's", find(german, "Typ : | |cff") ~= nil and find(german, "Legendaer") ~= nil and find(german, "Verlies") ~= nil
	and not find(german, "Type"))

print("A missing, failing or secret call leaves the tooltip as it was")
local function leavesTagAlone(label, setup)
	reset()
	ctx.tag = tagOf(Tag.Dungeon, "Dungeon")
	setup()
	local lines = draw(plainQuest)
	check(label, sameLines(lines, plain) and tooltip.shown, #typeRows(lines) .. " type rows")
end
local function leavesClassificationAlone(label, setup)
	reset()
	ctx.classification = C.Legendary
	setup()
	local lines = draw(plainQuest)
	check(label, sameLines(lines, plain) and tooltip.shown, #typeRows(lines) .. " type rows")
end

leavesClassificationAlone("QuestUtil is missing", function() missing("QuestUtil") end)
leavesClassificationAlone("QuestUtil.GetQuestClassificationInfo is missing", function() env.QuestUtil = {} end)
leavesClassificationAlone("QuestUtil.GetQuestClassificationInfo errors", function() env.QuestUtil = {GetQuestClassificationInfo = function() error("boom") end} end)
leavesClassificationAlone("C_QuestInfoSystem is missing", function() missing("C_QuestInfoSystem") end)
leavesClassificationAlone("GetQuestClassification is missing", function() env.C_QuestInfoSystem.GetQuestClassification = nil end)
leavesClassificationAlone("GetQuestClassification errors", function() ctx.classification = function() error("boom") end end)
leavesClassificationAlone("Enum is missing", function() missing("Enum") end)
leavesClassificationAlone("Enum.QuestClassification is missing", function() env.Enum = {} end)
leavesClassificationAlone("the classification's text is a secret value", function()
	env.QuestUtil = {GetQuestClassificationInfo = function() return {text = SECRET} end}
end)
leavesClassificationAlone("the classification's text is empty", function()
	env.QuestUtil = {GetQuestClassificationInfo = function() return {text = ""} end}
end)
leavesClassificationAlone("the classification's info has no text", function()
	env.QuestUtil = {GetQuestClassificationInfo = function() return {} end}
end)
leavesTagAlone("GetQuestTagInfo is missing", function() env.C_QuestLog.GetQuestTagInfo = nil end)
leavesTagAlone("GetQuestTagInfo errors", function() ctx.tag = function() error("boom") end end)
leavesTagAlone("QuestUtils_GetQuestTagAtlas is missing", function() missing("QuestUtils_GetQuestTagAtlas") end)
leavesTagAlone("QuestUtils_GetQuestTagAtlas errors", function() env.QuestUtils_GetQuestTagAtlas = function() error("boom") end end)
leavesTagAlone("the tag's name is a secret value", function() ctx.tag = tagOf(Tag.Dungeon, SECRET) end)
leavesTagAlone("the tag's name is empty", function() ctx.tag = tagOf(Tag.Dungeon, "") end)
leavesTagAlone("the tag's name is a number", function() ctx.tag = tagOf(Tag.Dungeon, 81) end)
leavesTagAlone("the tag reads as an error", function() ctx.tag = setmetatable({}, {__index = function() error("secret") end}) end)

reset()
ctx.classification = C.Legendary
ctx.tag = tagOf(Tag.Dungeon, "Dungeon")
missing("QuestUtil")
local tagOnly = typeRows((draw(plainQuest)))
check("one call missing leaves the other's line: the tag without the classification", #tagOnly == 1 and textOf(tagOnly[1]) == "Dungeon")
reset()
ctx.classification = C.Legendary
ctx.tag = function() error("boom") end
local classificationOnly = typeRows((draw(plainQuest)))
check("and the classification without the tag", #classificationOnly == 1 and textOf(classificationOnly[1]) == "Legendary")

reset()
ctx.classification, ctx.tag = C.Legendary, tagOf(Tag.Dungeon, "Dungeon")
ctx.lineInfo = {questLineID = STORYLINE_ID, questLineName = GAME_NAME}
for _, name in ipairs({"QuestUtil", "QuestUtils_GetQuestTagAtlas", "C_QuestLine", "C_QuestInfoSystem", "Enum"}) do missing(name) end
env.C_QuestLog.GetQuestTagInfo = nil
local bareStory, bareDaily = draw(storyQuest), draw(dailyQuest)
reset()
check("with every one of the game's calls missing, a storyline quest's tooltip is the plain one", sameLines(bareStory, baseline))
check("and so is a daily quest's", sameLines(bareDaily, (draw(dailyQuest))))

print("A profession quest's requirement, for a character with that profession and no other")
reset()
local professionOf, done = env.qcQuestProfession, {}
local skillOf, flags = {}, {}
for skillLine, flag in pairs(env.qcProfessionBits) do
	if not skillOf[flag] then skillOf[flag] = skillLine; flags[#flags + 1] = flag end
end
table.sort(flags)
local realCompleted, realTitle = env.C_QuestLog.IsQuestFlaggedCompleted, env.C_QuestLog.GetTitleForQuestID
local realProfessions, realProfessionInfo, realInLog = env.GetProfessions, env.GetProfessionInfo, ctx.inLog
env.C_QuestLog.IsQuestFlaggedCompleted = function(questId) return done[questId] == true end
env.C_QuestLog.GetTitleForQuestID = function(questId) return "#" .. questId end
env.GetProfessions = function() return 1 end
ctx.inLog = setmetatable({}, {__index = function() return 1 end})
env.qcSettings.QC_L_HIDE_REQUIREMENTSNOTMET, env.qcSettings.QC_L_HIDE_PROFESSION = 1, 1

local checked, unmet = 0, {}
for _, flag in ipairs(flags) do
	env.GetProfessionInfo = function() return nil, nil, 1000, nil, nil, nil, skillOf[flag], 0 end
	for _, questId in ipairs(ids) do
		done[questId] = not professionOf[questId] or bit.band(professionOf[questId], flag) ~= 0
	end
	local keep = QC.qcBuildViewFilter("L")
	for _, questId in ipairs(ids) do
		local mask = professionOf[questId]
		if mask and bit.band(mask, flag) ~= 0 and env.qcQuestPrereq[questId] then
			checked = checked + 1
			if not keep(questId) then unmet[#unmet + 1] = questId .. " (" .. flag .. ")" end
		end
	end
end
check(string.format("all %d are met once the character has done every quest it could", checked), checked > 0 and #unmet == 0,
	#unmet > 0 and (#unmet .. " not: " .. table.concat(unmet, ", ", 1, math.min(#unmet, 10))) or nil)

done = {}
local crossed, drawn = {}, 0
for _, questId in ipairs(ids) do
	local mask = professionOf[questId]
	if mask and env.qcQuestPrereq[questId] then
		drawn = drawn + 1
		draw(questId)
		local listing = false
		for _, entry in ipairs(tooltip.entries) do
			if entry.left == env.qcLocalize.REQUIREDQUEST then listing = true
			elseif entry.left ~= " " or entry.right == " " then listing = false end
			for other in (listing and entry.right or ""):gmatch("#(%d+)") do
				local otherMask = professionOf[tonumber(other)]
				if otherMask and bit.band(otherMask, mask) == 0 then crossed[#crossed + 1] = questId .. " <- " .. other end
			end
		end
	end
end
check(string.format("none of their %d tooltips names another profession's quest to do first", drawn), drawn > 0 and #crossed == 0,
	#crossed > 0 and (#crossed .. ": " .. table.concat(crossed, ", ", 1, math.min(#crossed, 10))) or nil)

env.C_QuestLog.IsQuestFlaggedCompleted, env.C_QuestLog.GetTitleForQuestID = realCompleted, realTitle
env.GetProfessions, env.GetProfessionInfo, ctx.inLog = realProfessions, realProfessionInfo, realInLog
env.qcSettings.QC_L_HIDE_REQUIREMENTSNOTMET, env.qcSettings.QC_L_HIDE_PROFESSION = 0, 0

if RECORD_FILE then
	local out = assert(io.open(RECORD_FILE, "wb"))
	for _, line in ipairs(recordLines) do out:write(line, "\n") end
	out:close()
end

print(failures == 0 and "All checks passed." or (failures .. " checks failed."))
os.exit(failures == 0 and 0 or 1)
