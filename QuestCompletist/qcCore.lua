local TableInsert = table.insert;
local StringFormat = string.format;
local ToString = tostring;
local BitBand = bit.band

local qcL = qcLocalize

local qcCurrentCategoryID = 0
local qcCurrentSearchText = nil
local qcCurrentCategoryQuestCount = 0
local qcCategoryQuests = {}

--[[ Vars ]]--
local qcCurrentScrollPosition = 1
local qcTooltipIndex = nil
local qcTooltipQuestId = nil
-- Quests the server has already answered for. Without this a redraw would request again, get
-- another QUEST_DATA_LOAD_RESULT, and redraw forever.
local qcQuestDataLoaded = {}
local qcMapTooltip = nil
local qcQuestInformationTooltip = nil
local qcToastTooltip = nil
local qcNewDataAlertTooltip = nil
local qcMutuallyExclusiveAlertTooltip = nil

--[[ Constants ]]--
local QCADDON_VERSION = 110.9
local QCADDON_PURGE = true
local QCADDON_CHAT_TITLE = "|CFF9482C9Quest Completist:|r "


local COLOUR_DEATHKNIGHT = "|cFFC41F3B"
local COLOUR_DEMONHUNTER = "|cFFA330C9"
local COLOUR_DRUID = "|cFFFF7D0A"
local COLOUR_HUNTER = "|cFFABD473"
local COLOUR_MAGE = "|cFF69CCF0"
local COLOUR_PALADIN = "|cFFF58CBA"
local COLOUR_PRIEST = "|cFFFFFFFF"
local COLOUR_ROGUE = "|cFFFFF569"
local COLOUR_SHAMAN = "|cFF0070DE"
local COLOUR_WARLOCK = "|cFF9482C9"
local COLOUR_WARRIOR = "|cFFC79C6E"

local QC_ICON_NORMAL = {atlas="QuestNormal"}
local QC_ICON_READY = {atlas="QuestTurnin"}
local QC_ICON_PROGRESS = {file="Interface\\GossipFrame\\IncompleteQuestIcon"}
local QC_ICON_DAILY = {atlas="QuestDaily"}
local QC_ICON_REPEATABLE = {atlas="QuestRepeatableTurnin"}
local QC_ICON_WORLD = {atlas="worldquest-icon"}
local QC_ICON_WEEKLY = {atlas="questlog-questtypeicon-weekly"}
local QC_ICON_MONTHLY = {atlas="questlog-questtypeicon-monthly"}
local QC_ICON_SPECIAL = {atlas="QuestLegendary"}
local QC_ICON_CLASS = {atlas="questlog-questtypeicon-class"}
local QC_ICON_COMPLETE = {atlas="common-icon-checkmark"}
local QC_ICON_UNATTAINABLE = {atlas="common-icon-redx"}
local QC_ICON_ALLIANCE = {atlas="poi-alliance"}
local QC_ICON_HORDE = {atlas="poi-horde"}
-- The client has no green or skull quest marker, so these still come from our own sheet, as does
-- the profession icon for quests that don't name exactly one profession.
local QC_ICON_SHEET = "Interface\\Addons\\QuestCompletist\\Images\\QCIcons"
local QC_ICON_SEASONAL = {file=QC_ICON_SHEET, coords={0,0.125,0.5,0.75}}
local QC_ICON_KILL = {file=QC_ICON_SHEET, coords={0.25,0.375,0,0.25}}
local QC_ICON_PROFESSION = {file=QC_ICON_SHEET, coords={0.625,0.75,0,0.25}}
-- Keyed by the qcProfessionBits value, so a quest's profession field indexes it directly.
local QC_ICON_BY_PROFESSION_BIT = {
	[1]={atlas="worldquest-icon-alchemy"},
	[2]={atlas="worldquest-icon-blacksmithing"},
	[4]={atlas="worldquest-icon-enchanting"},
	[8]={atlas="worldquest-icon-engineering"},
	[16]={atlas="worldquest-icon-inscription"},
	[32]={atlas="worldquest-icon-jewelcrafting"},
	[64]={atlas="worldquest-icon-leatherworking"},
	[128]={atlas="worldquest-icon-tailoring"},
	[256]={atlas="worldquest-icon-herbalism"},
	[512]={atlas="worldquest-icon-mining"},
	[1024]={atlas="worldquest-icon-skinning"},
	[2048]={atlas="worldquest-icon-archaeology"},
	[4096]={atlas="worldquest-icon-firstaid"},
	[8192]={atlas="worldquest-icon-cooking"},
	[16384]={atlas="worldquest-icon-fishing"},
	[32768]={atlas="worldquest-icon-engineering"},
}
local QC_FULL_TEXCOORDS = {0,1,0,1}
-- Map pin icon types from qcPinDB. Type 3 (profession) is resolved per pin from its quests.
local QC_PIN_ICONS = {
	[1]=QC_ICON_NORMAL, [2]=QC_ICON_REPEATABLE, [4]=QC_ICON_DAILY, [5]=QC_ICON_SEASONAL,
	[6]=QC_ICON_SPECIAL, [7]=QC_ICON_WEEKLY, [8]=QC_ICON_MONTHLY, [9]=QC_ICON_CLASS,
	[10]=QC_ICON_KILL, [11]=QC_ICON_SPECIAL,
}
-- Which icon a merged pin shows: a specific one-time quest, then a plain one, then a recurring one
-- (unranked). A completionist is after the one-time quests, and Blizzard's NPC markers agree.
local QC_PIN_ICON_RANK = {
	[QC_ICON_SPECIAL]=3, [QC_ICON_CLASS]=3, [QC_ICON_KILL]=3, [QC_ICON_SEASONAL]=3,
	[QC_ICON_PROFESSION]=3, [QC_ICON_NORMAL]=2,
}
for _, icon in pairs(QC_ICON_BY_PROFESSION_BIT) do
	QC_PIN_ICON_RANK[icon] = 3
end

local function qcProfessionIcon(professionMask)
	return QC_ICON_BY_PROFESSION_BIT[professionMask] or QC_ICON_PROFESSION
end

-- Type 128 holds both world quests and weeklies, since both reset weekly; the client knows which.
local function qcType128Icon(questId)
	if C_QuestLog.IsWorldQuest(questId) then
		return QC_ICON_WORLD
	end
	return QC_ICON_WEEKLY
end

-- The icon a recurring quest type draws with, or nil for a type a normal pin already fits.
local function qcRecurringQuestIcon(questId, questType)
	if questType == 4 then
		return QC_ICON_DAILY
	elseif questType == 2 then
		return QC_ICON_REPEATABLE
	elseif questType == 128 then
		return qcType128Icon(questId)
	end
	return nil
end

-- A pin stored as a plain quest takes a recurring icon when every quest on it agrees on one, so
-- it matches the tooltip; the pin types were often recorded as normal for dailies and weeklies.
local function qcNormalPinIcon(questIds)
	local shared
	for _, questId in ipairs(questIds) do
		local quest = qcQuestDatabase[questId]
		if quest then
			local icon = qcRecurringQuestIcon(questId, quest[4])
			if not icon or (shared and icon ~= shared) then
				return QC_ICON_NORMAL
			end
			shared = icon
		end
	end
	return shared or QC_ICON_NORMAL
end

-- Textures are reused between quests and keep their texcoords. An atlas drawn over leftover
-- texcoords shows only a corner of the icon - usually transparent - so both paths reset them.
local function qcSetIcon(texture, icon)
	if icon.atlas then
		texture:SetTexCoord(unpack(QC_FULL_TEXCOORDS))
		texture:SetAtlas(icon.atlas, false, nil, true)
	else
		texture:SetTexture(icon.file)
		texture:SetTexCoord(unpack(icon.coords or QC_FULL_TEXCOORDS))
	end
end

local qcCategoryDropDownMenu = CreateFrame("Frame", "qcCategoryDropDownMenu")

--[[ Bitwise Values ]]--
qcFactionBits = {
	["ALLIANCE"]=1,["HORDE"]=2,["NEUTRAL"]=4,
}
qcRaceBits = {
	["HUMAN"]=1,["ORC"]=2,["DWARF"]=4,["NIGHTELF"]=8,
	["SCOURGE"]=16,["TAUREN"]=32,["GNOME"]=64,["TROLL"]=128,
	["GOBLIN"]=256,["BLOODELF"]=512,["DRAENEI"]=1024,["WORGEN"]=2048,
	["PANDAREN"]=4096,["VOIDELF"]=8192,["NIGHTBORNE"]=16384,
	["HIGHMOUNTAINTAUREN"]=32768,["LIGHTFORGEDDRAENEI"]=65536,
	["DARKIRONDWARF"]=131072,["MAGHARORC"]=262144,
	["ZANDALARITROLL"]=524288,["KULTIRAN"]=1048576,
	["VULPERA"]=2097152,["MECHAGNOME"]=4194304,["DRACTHYR"]=8388608,["EARTHENDWARF"]=16777216,
	["HARRONIR"]=33554432,
}
qcClassBits = {
	["WARRIOR"]=1,["PALADIN"]=2,["HUNTER"]=4,["ROGUE"]=8,["PRIEST"]=16,
	["DEATHKNIGHT"]=32,["SHAMAN"]=64,["MAGE"]=128,["WARLOCK"]=256,["DRUID"]=512,
	["MONK"]=1024,["DEMONHUNTER"]=2048,["EVOKER"]=4096
}
qcProfessionBits = {
	[171]=1,		-- Alchemy
	[164]=2,		-- Blacksmithing
	[333]=4,		-- Enchanting
	[202]=8,		-- Engineering
	[773]=16,		-- Inscription
	[755]=32,		-- Jewelcrafting
	[165]=64,		-- Leatherworking
	[197]=128,		-- Tailoring
	[182]=256,		-- Herbalism
	[186]=512,		-- Mining
	[393]=1024,		-- Skinning
    [794]=2048,   	-- Archaeology
	[129]=4096,		-- First Aid
	[185]=8192,		-- Cooking
	[356]=16384,	-- Fishing
	[20222]=32768  	-- Gnomish Engineering
}	
qcCovenantsBits = {
	[0]=1,		-- None
	[1]=2,		-- Kyrian
	[2]=4,		-- Venthyr
	[3]=8,		-- NightFae
	[4]=16,		-- Necrolord
}
qcSubQuestCatagoryBits = {
	["Warfront"]=1,
	["Bonus"]=2,
	["Legion Assault"]=4,
	["Assault"]=8,
}
qcQuestFactionLevelBits = {
	["Hated"]=1,
	["NEUTRAL"]=2,
	["Friendly"]=4,
	["Honored"]=8,
	["Revered"]=16,
	["Exalted"]=32,
}
--[[ Holidays, as the game's calendar reports them ]]--
-- Each holiday value in the quest database, with the IDs of the game's Holidays table that its
-- calendar event can carry.
local qcHolidays = {
	{flag=1, name="Brewfest", eventIDs={372}},
	{flag=2, name="Children's Week", eventIDs={201}},
	{flag=4, name="Day of the Dead", eventIDs={409}},
	{flag=8, name="Feast of Winter Veil", eventIDs={141}},
	{flag=16, name="Hallow's End", eventIDs={324, 1405}},
	{flag=32, name="Harvest Festival", eventIDs={321}},
	{flag=64, name="Love is in the Air", eventIDs={423, 335}},
	{flag=128, name="Lunar Festival", eventIDs={327}},
	{flag=256, name="Midsummer Fire Festival", eventIDs={341}},
	{flag=512, name="Noblegarden", eventIDs={181}},
	{flag=1024, name="Pilgrim's Bounty", eventIDs={404}},
	{flag=2048, name="Pirates' Day", eventIDs={398}},
	{flag=4096, name="Trial of Style", eventIDs={691}},
	{flag=8192, name="Darkmoon Faire", eventIDs={479}},
}
local qcHolidayFlagByEventID = {}
local qcKnownHolidayFlags = {}
for _, holiday in ipairs(qcHolidays) do
	qcKnownHolidayFlags[holiday.flag] = true
	for _, eventID in ipairs(holiday.eventIDs) do qcHolidayFlagByEventID[eventID] = holiday.flag end
end

-- The holiday flags running now; nil until the calendar has answered, which restricts nothing.
local qcActiveHolidays = nil

local function qcCalendarTimeValue(t)
	return (((t.year * 100 + t.month) * 100 + t.monthDay) * 100 + t.hour) * 100 + t.minute
end

local function qcFormatCalendarTime(t)
	return string.format("%04d-%02d-%02d %02d:%02d", t.year, t.month, t.monthDay, t.hour, t.minute)
end

local function qcCalendarFrameOpen()
	return CalendarFrame ~= nil and CalendarFrame:IsShown()
end

-- The calendar only has events around the month it's set to, and at login that's November 2004.
-- Blizzard's calendar sets the current month whenever it opens, so doing the same is safe while
-- it's closed. While it's open the player may be looking at another month, so that's left alone.
local function qcSetCalendarMonth(month, year)
	local shown = C_Calendar.GetMonthInfo(0)
	if (shown.month == month and shown.year == year) then return true end
	if qcCalendarFrameOpen() then return false end
	C_Calendar.SetAbsMonth(month, year)
	return true
end

-- nil when the calendar can't answer. A day with no events at all means it isn't ready, not that
-- no holiday is running.
local function qcReadActiveHolidays()
	local now = C_DateAndTime.GetCurrentCalendarTime()
	if not qcSetCalendarMonth(now.month, now.year) then return nil end
	local numEvents = C_Calendar.GetNumDayEvents(0, now.monthDay)
	if (numEvents == 0) then return nil end
	local nowValue = qcCalendarTimeValue(now)
	local active = 0
	for index = 1, numEvents do
		local event = C_Calendar.GetDayEvent(0, now.monthDay, index)
		local flag = event and event.calendarType == "HOLIDAY" and qcHolidayFlagByEventID[event.eventID]
		if flag and qcCalendarTimeValue(event.startTime) <= nowValue and nowValue < qcCalendarTimeValue(event.endTime) then
			active = bit.bor(active, flag)
		end
	end
	return active
end

-- Keeps the last answer when the calendar can't be read, e.g. during chat lockdown.
local function qcUpdateActiveHolidays()
	local ok, active = pcall(qcReadActiveHolidays)
	if (ok and active) then qcActiveHolidays = active end
	return qcActiveHolidays
end

-- /qc holidays: what the seasonal filter sees, and when each holiday next runs. Reading ahead
-- steps the calendar through the months, then sets it back to the current one.
local function qcScanCalendarHolidays()
	local now = C_DateAndTime.GetCurrentCalendarTime()
	local nextByFlag, untracked = {}, {}
	for step = 0, 12 do
		local monthIndex = now.month - 1 + step
		C_Calendar.SetAbsMonth(monthIndex % 12 + 1, now.year + math.floor(monthIndex / 12))
		local firstDay = (step == 0) and now.monthDay or 1
		for monthDay = firstDay, C_Calendar.GetMonthInfo(0).numDays do
			for index = 1, C_Calendar.GetNumDayEvents(0, monthDay) do
				local event = C_Calendar.GetDayEvent(0, monthDay, index)
				if event and event.calendarType == "HOLIDAY" then
					local flag = qcHolidayFlagByEventID[event.eventID]
					if flag then
						nextByFlag[flag] = nextByFlag[flag] or event
					elseif not untracked[event.eventID] then
						untracked[event.eventID] = event.title
					end
				end
			end
		end
	end
	C_Calendar.SetAbsMonth(now.month, now.year)
	return nextByFlag, untracked
end

local function qcPrintHolidays()
	if qcCalendarFrameOpen() then
		print(QCADDON_CHAT_TITLE .. "Close the calendar first. Reading ahead moves it through the months.")
		return
	end
	local active = qcUpdateActiveHolidays()
	local ok, nextByFlag, untracked = pcall(qcScanCalendarHolidays)
	if not ok then
		print(QCADDON_CHAT_TITLE .. "The calendar can't be read right now: " .. tostring(nextByFlag))
		return
	end
	if not active then
		print(QCADDON_CHAT_TITLE .. "The calendar hasn't answered yet, so seasonal quests are all shown.")
	end
	print(QCADDON_CHAT_TITLE .. "Seasonal quests follow these calendar holidays:")
	for _, holiday in ipairs(qcHolidays) do
		local event = nextByFlag[holiday.flag]
		local running = active and bit.band(active, holiday.flag) ~= 0
		if event then
			print(string.format("  %s%s (%d): %s to %s", running and "|cff00ff00Running|r " or "", event.title,
				event.eventID, qcFormatCalendarTime(event.startTime), qcFormatCalendarTime(event.endTime)))
		else
			print(string.format("  %s: not on the calendar in the next 12 months", holiday.name))
		end
	end
	local ids = {}
	for eventID in pairs(untracked) do ids[#ids + 1] = eventID end
	table.sort(ids)
	if #ids > 0 then
		print("  Other calendar holidays, not tied to any quest:")
		for _, eventID in ipairs(ids) do print(string.format("    %s (%d)", untracked[eventID], eventID)) end
	end
end

--[[ Constants for the Key Bindings & Slash Commands ]]--
BINDING_HEADER_QCQUESTCOMPLETIST = "Quest Completist";
BINDING_NAME_QCTOGGLEFRAME = qcL.TOGGLEFRAME;
SLASH_QUESTCOMPLETIST1 = "/qc"
SLASH_QUESTCOMPLETIST2 = "/questc"

SlashCmdList["QUESTCOMPLETIST"] = function(msg, editbox)
	if (strtrim(msg or ""):lower() == "holidays") then
		qcPrintHolidays()
		return
	end
	ShowUIPanel(qcQuestCompletistUI)
end


function qcUpdateCurrentCategoryText(categoryId)
	qcQuestCompletistUI.qcSelectedCategory:SetText(qcCategoryName(categoryId) or "#")
end

local qcRecurringTypes = 2 + 4 + 128

local function qcIsRecurringQuest(questId)
	return bit.band(qcQuestDatabase[questId][4], qcRecurringTypes) ~= 0
end

local function qcUpdateMutuallyExclusiveCompletedQuest(qcQuestID)
	if (qcMutuallyExclusive[qcQuestID]) then
		for qcMutuallyExclusiveIndex, qcMutuallyExclusiveEntry in pairs(qcMutuallyExclusive[qcQuestID]) do
			if (qcQuestDatabase[qcMutuallyExclusiveEntry]) and not qcIsRecurringQuest(qcMutuallyExclusiveEntry) then
				qcCharacterCompletions[qcMutuallyExclusiveEntry] = 1
			end
		end
	end
end

local function qcUpdateSkippedBreadcrumbQuest(qcQuestID)
	if (qcBreadcrumbQuests[qcQuestID]) then
		for qcBreadcrumbIndex, qcBreadcrumbEntry in pairs(qcBreadcrumbQuests[qcQuestID]) do
			if (qcQuestDatabase[qcBreadcrumbEntry]) and not qcIsRecurringQuest(qcBreadcrumbEntry) then
				qcCharacterCompletions[qcBreadcrumbEntry] = 1
			end
		end
	end
end

local qcCategoryIndex = nil
local qcQuestNameUpperCache = nil

-- A quest's row in qcQuestDatabase (qcQuestData.lua) is {name, level, category, type, faction, race,
-- class, storyline}; profession, holiday, covenant and prereq are in their own tables, keyed by ID.
local function qcBuildQuestIndexes()
    qcCategoryIndex = {}
    for questId, e in pairs(qcQuestDatabase) do
        local categoryId = e[3]
        if not qcCategoryIndex[categoryId] then
            qcCategoryIndex[categoryId] = {}
        end
        table.insert(qcCategoryIndex[categoryId], questId)
    end
end

-- Upper-cased English names, built on the first search: the list itself never needs them.
local function qcEnglishNamesForSearch()
    if not qcQuestNameUpperCache then
        qcQuestNameUpperCache = {}
        for questId, e in pairs(qcQuestDatabase) do
            qcQuestNameUpperCache[questId] = string.upper(e[1])
        end
    end
    return qcQuestNameUpperCache
end

--[[ Quest names in the client's language ]]--
-- The client names a quest in its own language once it has the quest's data. It keeps that data on
-- disk per language, but a player has met only a few percent of all quests, so missing names are
-- loaded while the English name stands in. The server stops answering bursts of requests, so only a
-- few are in flight; answers that take longer than the timeout have always come without a name.
local QC_MAX_QUEST_LOADS = 4
local QC_QUEST_LOAD_TIMEOUT = 5
local QC_QUEST_LOAD_RETRY_DELAY = 30
local QC_QUEST_LOAD_ATTEMPTS = 2

local qcQuestLoadQueue = {}
local qcQuestLoadQueued = {}
local qcQuestLoadInFlight = {}
local qcQuestLoadInFlightCount = 0
local qcQuestLoadAttempts = {}
local qcQuestLoadScheduled = false
local qcClientNameUpperCache = nil
-- Quests whose names an open tooltip is still waiting for, so it can be redrawn when they load.
local qcQuestTooltipWaiting = {}
local qcMapTooltipWaiting = {}
local qcMapTooltipPin = nil

local function qcClientQuestName(questId)
	local title = C_TaskQuest.GetQuestInfoByQuestID(questId)
	if not title or title == "" then
		title = C_QuestLog.GetTitleForQuestID(questId)
	end
	if title and title ~= "" then return title end
end

local qcSendQuestLoads, qcQuestLoadEnded, qcRequestQuestData

function qcSendQuestLoads()
	while qcQuestLoadInFlightCount < QC_MAX_QUEST_LOADS and #qcQuestLoadQueue > 0 do
		-- Newest first: whatever is on screen now asked last.
		local questId = table.remove(qcQuestLoadQueue)
		qcQuestLoadQueued[questId] = nil
		local attempt = (qcQuestLoadAttempts[questId] or 0) + 1
		qcQuestLoadAttempts[questId] = attempt
		qcQuestLoadInFlight[questId] = attempt
		qcQuestLoadInFlightCount = qcQuestLoadInFlightCount + 1
		C_QuestLog.RequestLoadQuestByID(questId)
		C_Timer.After(QC_QUEST_LOAD_TIMEOUT, function()
			if qcQuestLoadInFlight[questId] == attempt then
				qcQuestLoadEnded(questId, false)
			end
		end)
	end
end

-- Frees the request's slot. A quest that failed or got no answer is tried once more later, as some
-- failures have been seen to load another time.
function qcQuestLoadEnded(questId, success)
	if qcQuestLoadInFlight[questId] then
		qcQuestLoadInFlight[questId] = nil
		qcQuestLoadInFlightCount = qcQuestLoadInFlightCount - 1
		if not success and qcQuestLoadAttempts[questId] < QC_QUEST_LOAD_ATTEMPTS then
			C_Timer.After(QC_QUEST_LOAD_RETRY_DELAY, function() qcRequestQuestData(questId) end)
		end
	end
	qcSendQuestLoads()
end

function qcRequestQuestData(questId)
	if qcQuestDataLoaded[questId] or qcQuestLoadQueued[questId] or qcQuestLoadInFlight[questId]
		or (qcQuestLoadAttempts[questId] or 0) >= QC_QUEST_LOAD_ATTEMPTS then
		return
	end
	qcQuestLoadQueued[questId] = true
	table.insert(qcQuestLoadQueue, questId)
	-- Sent on the next frame, so everything a redraw asks for is queued first and the rows it ends
	-- on go first; a list can draw a page it then scrolls away from within one update.
	if not qcQuestLoadScheduled then
		qcQuestLoadScheduled = true
		C_Timer.After(0, function()
			qcQuestLoadScheduled = false
			qcSendQuestLoads()
		end)
	end
end

-- The quest's name in the client's language, or the English name from the database until the
-- client has it. waiting, if given, collects the quests still loading.
local function qcQuestName(questId, waiting)
	local name = qcClientQuestName(questId)
	if name then return name end
	qcRequestQuestData(questId)
	if waiting then waiting[questId] = true end
	local entry = qcQuestDatabase[questId]
	return entry and entry[1]
end

-- Upper-cased client names for search: built on the first search, then kept up to date as names
-- load. Only names that differ from the English one are kept, as search checks that anyway; on an
-- English client that's a handful. string.upper folds only A-Z, so other letters match in case.
local function qcClientNamesForSearch()
	if not qcClientNameUpperCache then
		local englishNames = qcEnglishNamesForSearch()
		qcClientNameUpperCache = {}
		for questId in pairs(qcQuestDatabase) do
			local name = qcClientQuestName(questId)
			local upper = name and string.upper(name)
			if upper and upper ~= englishNames[questId] then
				qcClientNameUpperCache[questId] = upper
			end
		end
	end
	return qcClientNameUpperCache
end

local function qcIsQuestCompleted(questId)
	local mark = qcCharacterCompletions[questId]
	return mark == 1 or mark == 2
end

local function qcIsQuestCompletedOnAccount(questId)
	return C_QuestLog.IsQuestFlaggedCompletedOnAccount(questId)
end

-- A quest flagged in qcUnavailableQuests.lua that this character hasn't completed and doesn't have.
-- A character who has it is proof the flag is wrong, so the quest shows for them as normal.
local function qcIsUnavailable(questId)
	if not qcUnavailableQuests[questId] or qcIsQuestCompleted(questId) then return false end
	local logIndex = C_QuestLog.GetLogIndexForQuestID(questId)
	return not (logIndex and logIndex > 0)
end

-- 0 means the database has no data for the field, so it restricts nothing.
local function qcMaskAllows(mask, flag)
	return mask == 0 or bit.band(mask, flag) ~= 0
end

-- GetProfessions returns both primaries, then Archaeology, Fishing and Cooking; any can be nil.
local function qcPlayerProfessionMask()
	local mask = 0
	for _, index in pairs({GetProfessions()}) do
		local skillLine = select(7, GetProfessionInfo(index))
		mask = bit.bor(mask, qcProfessionBits[skillLine] or 0)
	end
	return mask
end

-- The list and the map each have their own low-level and profession settings; only the list hides
-- quests by type. Faction, race/class and covenant are shared.
local QC_LIST_FILTER = {lowLevel = "QC_L_HIDE_LOWLEVEL", profession = "QC_L_HIDE_PROFESSION", types = true}
local QC_MAP_FILTER = {lowLevel = "QC_M_HIDE_LOWLEVEL", profession = "QC_M_HIDE_PROFESSION"}

-- Every quest filter that reads only the quest's data, not whether it's done. The completion
-- counter shares the list's, so the counter's total is always the quests the list can show.
local function qcBuildQuestFilter(scope)
	local BitBand = bit.band
	local stringUpper = string.upper

	local hiddenTypes = 0
	if scope.types then
		if (qcSettings.QC_L_HIDE_DAILYQUEST == 1) then hiddenTypes = hiddenTypes + 4 end
		if (qcSettings.QC_L_HIDE_REPEATABLEQUEST == 1) then hiddenTypes = hiddenTypes + 2 end
		if (qcSettings.QC_L_HIDE_WORLDQUEST == 1) then hiddenTypes = hiddenTypes + 128 end
	end

	local greenCutoff
	if (qcSettings[scope.lowLevel] == 1) then
		greenCutoff = UnitLevel("player") - UnitQuestTrivialLevelRange("player")
	end

	local professionBitmask
	if (qcSettings[scope.profession] == 1) then
		professionBitmask = qcPlayerProfessionMask()
	end

	local factionFlag
	if (qcSettings.QC_ML_HIDE_FACTION == 1) then
		local playerFaction = UnitFactionGroup("player")
		factionFlag = qcFactionBits[stringUpper(playerFaction)]
	end

	local raceFlag, classFlag
	if (qcSettings.QC_ML_HIDE_RACECLASS == 1) then
		local _, playerRace = UnitRace("player")
		local _, playerClass = UnitClass("player")
		raceFlag = qcRaceBits[stringUpper(playerRace)]
		classFlag = qcClassBits[stringUpper(playerClass)]
	end

	local covenantBit
	if (qcSettings.QC_ML_HIDE_COVENANTS == 1) then
		covenantBit = qcCovenantsBits[C_Covenants.GetActiveCovenantID()] or 0
	end

	local professions, covenants = qcQuestProfession, qcQuestCovenant
	return function(questId, e)
		if (BitBand(e[4], hiddenTypes) ~= 0) then return false end
		if greenCutoff and (e[2] or 0) < greenCutoff then return false end
		local profession = professions[questId]
		if professionBitmask and profession and BitBand(profession, professionBitmask) == 0 then return false end
		if factionFlag and not qcMaskAllows(e[5], factionFlag) then return false end
		if raceFlag and not qcMaskAllows(e[6], raceFlag) then return false end
		if classFlag and not qcMaskAllows(e[7], classFlag) then return false end
		local covenant = covenants[questId]
		if covenantBit and covenant and BitBand(covenant, covenantBit) == 0 then return false end
		return true
	end
end

local function qcGetCategoryQuests(categoryId, searchText)
    local tableInsert = table.insert
    local tableSort = table.sort
    -- The list holds quest IDs.
    local holdingTable = {}

    if (searchText) then
        local stringfind = string.find
        local englishNames = qcEnglishNamesForSearch()
        local clientNames = qcClientNamesForSearch()
        for questId in pairs(qcQuestDatabase) do
            local clientName = clientNames[questId]
            if (stringfind(englishNames[questId], searchText, 1, true))
                or (clientName and stringfind(clientName, searchText, 1, true)) then
                tableInsert(holdingTable, questId)
            end
        end
        qcCategoryQuests = holdingTable
        return nil
    end

    if not qcCategoryIndex then
        qcBuildQuestIndexes()
    end

    local passesFilters = qcBuildQuestFilter(QC_LIST_FILTER)
    local hideCompleted = (qcSettings.QC_L_HIDE_COMPLETED == 1)
    local hideWarband = (qcSettings.QC_ML_HIDE_WARBANDS == 1)
    local hideUnavailable = (qcSettings.QC_ML_HIDE_UNAVAILABLE == 1)
    for _, questId in ipairs(qcCategoryIndex[categoryId] or {}) do
        if passesFilters(questId, qcQuestDatabase[questId])
            and not (hideCompleted and qcIsQuestCompleted(questId))
            and not (hideWarband and qcIsQuestCompletedOnAccount(questId))
            and not (hideUnavailable and qcIsUnavailable(questId)) then
            tableInsert(holdingTable, questId)
        end
    end
    qcCategoryQuests = holdingTable

    -- Sorting quests. An entry with no level sorts as 0 rather than erroring out of the sort and
	-- leaving the list empty. Names are the ones shown now; names that load later don't re-sort the
	-- list until it's next rebuilt, so rows don't jump while being read.
	local sortName, sortLevel = {}, {}
	for _, questId in ipairs(qcCategoryQuests) do
		local e = qcQuestDatabase[questId]
		sortName[questId] = qcClientQuestName(questId) or e[1]
		sortLevel[questId] = e[2] or 0
	end
	local function byLevel(a,b)
		local levelA, levelB = sortLevel[a], sortLevel[b]
		return (levelA<levelB or (levelA == levelB and sortName[a]<sortName[b]))
	end
	if (qcSettings.SORT == 1) then
		tableSort(qcCategoryQuests,byLevel)
	elseif (qcSettings.SORT == 2) then
		tableSort(qcCategoryQuests,function(a,b) return sortName[a]<sortName[b] end)
	else
		tableSort(qcCategoryQuests,byLevel)
	end
end

--Beta Reset Daily and Weekly Start
-- Initialize saved variables if needed
QC_LastDailyReset = QC_LastDailyReset or 0
QC_LastWeeklyReset = QC_LastWeeklyReset or 0
qcCharacterCompletions = qcCharacterCompletions or {}

-- Clears completions of a given type flag (4 = daily, 128 = weekly); unattainable marks (2) never expire
local function ResetQCCompletedQuests(flag)
    for questId, mark in pairs(qcCharacterCompletions) do
        local questData = qcQuestDatabase[questId]
        if questData and mark ~= 2 and bit.band(questData[4], flag) ~= 0 then
            qcCharacterCompletions[questId] = nil
        end
    end
end

-- Completions used to be saved as qcCompletedQuests, one {["C"] = mark} table per quest. They're now
-- the mark itself (1 completed, 2 unattainable, 0 marked not done) in qcCharacterCompletions. The old
-- variable is emptied, so an older version of the addon finds nothing rather than a format it can't
-- read; the TOC keeps declaring it so the old data can still be loaded here.
local function qcMigrateCompletions()
    if type(qcCompletedQuests) == "table" then
        for questId, record in pairs(qcCompletedQuests) do
            local mark = type(record) == "table" and record["C"]
            if type(mark) == "number" and qcCharacterCompletions[questId] == nil then
                qcCharacterCompletions[questId] = mark
            end
        end
    end
    qcCompletedQuests = nil
end

-- Event handler
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(self, event)
    local now = time()

    -- Daily reset
    if now > QC_LastDailyReset then
        QC_LastDailyReset = now + GetQuestResetTime()
        ResetQCCompletedQuests(4)
    end

    -- Weekly reset
    if now > QC_LastWeeklyReset then
        QC_LastWeeklyReset = now + C_DateAndTime.GetSecondsUntilWeeklyReset()
        ResetQCCompletedQuests(128)
    end
end)

local function simulateExclusiveCompletions(groupTable)
    local simulatedCompleted = {}

    for _, group in ipairs(groupTable) do
        local completedCount = 0
        local remaining = {}

        for _, questID in ipairs(group.quests) do
            local qID = tonumber(questID)
            if qID then
                local isCompleted = qcIsQuestCompleted(qID)
                local isAccepted = C_QuestLog.GetLogIndexForQuestID(qID) and C_QuestLog.GetLogIndexForQuestID(qID) > 0

                if isCompleted or isAccepted then
                    completedCount = completedCount + 1
                else
                    table.insert(remaining, qID)
                end
            end
        end

        if completedCount >= group.max then
            for _, qID in ipairs(remaining) do
                simulatedCompleted[qID] = true
                -- Debug print
               -- print("Override completed quest:", qID)
            end
        end
    end

    return simulatedCompleted
end

--Beta Reset Daily and Weekly End


-- Completed quests still count towards both numbers when the list is hiding them; otherwise
-- turning on "hide completed" would pin the counter at 0/N. Another character's completion
-- counts only while the warband filter treats it as done; otherwise the list shows the quest as
-- still to do.
function qcGetZoneCompletionStats(areaId)
	local total = 0
	local completed = 0

	if not qcCategoryIndex then
		qcBuildQuestIndexes()
	end

	local passesFilters = qcBuildQuestFilter(QC_LIST_FILTER)
	local countWarband = (qcSettings.QC_ML_HIDE_WARBANDS == 1)
	-- A quest nobody can get would hold the percentage below 100 for ever.
	local hideUnavailable = (qcSettings.QC_ML_HIDE_UNAVAILABLE == 1)
	for _, questId in ipairs(qcCategoryIndex[areaId] or {}) do
		if passesFilters(questId, qcQuestDatabase[questId]) and not (hideUnavailable and qcIsUnavailable(questId)) then
			total = total + 1
			if qcIsQuestCompleted(questId) or (countWarband and qcIsQuestCompletedOnAccount(questId)) then
				completed = completed + 1
			end
		end
	end

	return completed, total
end

function qcUpdateQuestList(categoryId, startIndex, searchText) -- *
	if not (qcQuestCompletistUI:IsVisible()) then return nil end
	local stringFormat = string.format
	if (categoryId) then
		qcCurrentCategoryID = categoryId
		qcCurrentSearchText = nil
		qcUpdateCurrentCategoryText(categoryId)
		qcGetCategoryQuests(categoryId)
		qcCurrentCategoryQuestCount = (#qcCategoryQuests)
		if (qcCurrentCategoryQuestCount < 16) then
			qcMenuSlider:SetMinMaxValues(1, 1)
		else
			qcMenuSlider:SetMinMaxValues(1, qcCurrentCategoryQuestCount - 15)
		end
		qcMenuSlider:SetValue(startIndex)
		startIndex = qcMenuSlider:GetValue()

		local completedInZone, totalInZone = qcGetZoneCompletionStats(categoryId)
		local completionPercent = (totalInZone > 0) and math.floor((completedInZone / totalInZone) * 100) or 0
		qcQuestCompletistUI.qcCurrentCategoryQuestCount:SetText(stringFormat(qcL.PROGRESS, completedInZone, totalInZone, completionPercent))
	else
		if (searchText) then
			qcCurrentSearchText = searchText
			qcGetCategoryQuests(nil, searchText)
			qcCurrentCategoryQuestCount = (#qcCategoryQuests)
			qcQuestCompletistUI.qcSelectedCategory:SetText(qcL.SEARCHRESULTS)
			if (qcCurrentCategoryQuestCount < 16) then
				qcMenuSlider:SetMinMaxValues(1, 1)
			else
				qcMenuSlider:SetMinMaxValues(1, qcCurrentCategoryQuestCount - 15)
			end
			qcMenuSlider:SetValue(startIndex)
			startIndex = qcMenuSlider:GetValue()
			qcQuestCompletistUI.qcCurrentCategoryQuestCount:SetText(stringFormat(qcL.QUESTSFOUND, qcCurrentCategoryQuestCount))
		end
	end
	for i = 1, 16 do
		local offset = ((i + startIndex) - 1)
		local questRecord = _G["qcMenuButton" .. i]
		if (qcCurrentCategoryQuestCount >= offset) then
			local questId = qcCategoryQuests[offset]
			local e = qcQuestDatabase[questId]
			local questType = e[4]
			local questFaction = e[5]
			questRecord.QuestName:SetText(stringFormat("[%d] %s",e[2],qcQuestName(questId)))
			questRecord.QuestID = questId
			-- TODO: Possible to reduce code with call to _G[]?
			if (questType == 1) then
				qcSetIcon(questRecord.QuestIcon, QC_ICON_NORMAL)
				questRecord.QuestName:SetTextColor(1.0, 1.0, 1.0, 1.0)
			elseif (questType == 2) then
				qcSetIcon(questRecord.QuestIcon, QC_ICON_REPEATABLE)
				questRecord.QuestName:SetTextColor(0.0941176470588235, 0.6274509803921569, 0.9411764705882353, 1.0)
			elseif (questType == 4) then
				qcSetIcon(questRecord.QuestIcon, QC_ICON_DAILY)
				questRecord.QuestName:SetTextColor(0.0941176470588235, 0.6274509803921569, 0.9411764705882353, 1.0)
			elseif (questType == 8) then
				qcSetIcon(questRecord.QuestIcon, QC_ICON_SPECIAL)
				questRecord.QuestName:SetTextColor(1.0, 0.6156862745098039, 0.0862745098039216, 1.0)
			elseif (questType == 16) then
				qcSetIcon(questRecord.QuestIcon, QC_ICON_NORMAL)
				questRecord.QuestName:SetTextColor(1.0, 1.0, 1.0, 1.0)
			elseif (questType == 32) then
				qcSetIcon(questRecord.QuestIcon, qcProfessionIcon(qcQuestProfession[questId] or 0))
				questRecord.QuestName:SetTextColor(1.0, 1.0, 1.0, 1.0)
			elseif (questType == 64) then
				qcSetIcon(questRecord.QuestIcon, QC_ICON_SEASONAL)
				questRecord.QuestName:SetTextColor(1.0, 1.0, 1.0, 1.0)
			elseif (questType == 128) then
				qcSetIcon(questRecord.QuestIcon, qcType128Icon(questId))
				questRecord.QuestName:SetTextColor(0.0941176470588235, 0.6274509803921569, 0.9411764705882353, 1.0)
			else
				qcSetIcon(questRecord.QuestIcon, QC_ICON_NORMAL)
				questRecord.QuestName:SetTextColor(1.0, 1.0, 1.0, 1.0)
			end
			questRecord.QuestIcon:Show()
			if ((questFaction == 0) or (questFaction == 3)) then
				questRecord.FactionIcon:Hide()
			elseif (questFaction == 1) then
				qcSetIcon(questRecord.FactionIcon, QC_ICON_ALLIANCE)
				questRecord.FactionIcon:Show()
			elseif(questFaction == 2) then
				qcSetIcon(questRecord.FactionIcon, QC_ICON_HORDE)
				questRecord.FactionIcon:Show()
			else
				questRecord.FactionIcon:Hide()
			end
            if not (C_QuestLog.GetLogIndexForQuestID(questId) == nil) then
                local isComplete = C_QuestLog.IsComplete(questId)
                if (isComplete) then
                    qcSetIcon(questRecord.QuestIcon, QC_ICON_READY)
                    questRecord.QuestName:SetTextColor(1.0, 0.8196078431372549, 0.0, 1.0)
                elseif (isComplete == false) then
                    qcSetIcon(questRecord.QuestIcon, QC_ICON_PROGRESS)
                    questRecord.QuestName:SetTextColor(0.5803921568627451, 0.5882352941176471, 0.5803921568627451, 1.0)
                else
                    qcSetIcon(questRecord.QuestIcon, QC_ICON_NORMAL)
                    questRecord.QuestName:SetTextColor(0.9372549019607843, 0.1490196078431373, 0.0627450980392157, 1.0)
                end
            end	
			local mark = qcCharacterCompletions[questId]
			if (mark) then
				if not ((questType == 2) or (questType == 4) or (questType == 128)) then
					if (mark == 1) then
						qcSetIcon(questRecord.QuestIcon, QC_ICON_COMPLETE)
						questRecord.QuestName:SetTextColor(0.0, 1.0, 0.0, 1.0)
					elseif (mark == 2) then
						qcSetIcon(questRecord.QuestIcon, QC_ICON_UNATTAINABLE)
						questRecord.QuestName:SetTextColor(0.77, 0.12, 0.23, 1.0)
					end
				end
			end
			questRecord:Show()
			questRecord:Enable()
		else
			questRecord.QuestName:SetText("#")
			questRecord:Hide()
			questRecord:Disable()
		end
	end
end

-- Rebuilds whatever the list is showing from current state, keeping its scroll position.
local function qcRefreshQuestList()
	if qcCurrentSearchText then
		qcUpdateQuestList(nil, qcMenuSlider:GetValue(), qcCurrentSearchText)
	else
		qcUpdateQuestList(qcCurrentCategoryID, qcMenuSlider:GetValue())
	end
end

local QC_REDRAW_ROWS = 1
local QC_REBUILD_LIST = 2
local qcPendingListRefresh = 0
local qcPendingMapRefresh = false
local qcRefreshScheduled = false

local function qcFlushRefresh()
	local list, map = qcPendingListRefresh, qcPendingMapRefresh
	qcPendingListRefresh, qcPendingMapRefresh, qcRefreshScheduled = 0, false, false
	if list == QC_REBUILD_LIST then
		qcRefreshQuestList()
	elseif list == QC_REDRAW_ROWS then
		qcUpdateQuestList(nil, qcMenuSlider:GetValue())
	end
	if map and WorldMapFrame:IsShown() then
		qcMapDataProvider:RefreshAllData()
	end
end

-- Quest events arrive in bursts, so they're collected and applied once on the next frame. A hidden
-- list or map is left alone; each is rebuilt when it's shown.
local function qcRequestRefresh(list, map)
	qcPendingListRefresh = math.max(qcPendingListRefresh, list or 0)
	qcPendingMapRefresh = qcPendingMapRefresh or map or false
	if not qcRefreshScheduled then
		qcRefreshScheduled = true
		C_Timer.After(0, qcFlushRefresh)
	end
end

local qcNameRedrawScheduled = false
local qcNameRedrawTooltip = false
local qcNameRedrawPin = false

local function qcRedrawLoadedNames()
	local tooltip, pin = qcNameRedrawTooltip, qcNameRedrawPin
	qcNameRedrawScheduled, qcNameRedrawTooltip, qcNameRedrawPin = false, false, false
	-- The list may have scrolled since the tooltip opened.
	if tooltip and qcTooltipIndex and _G["qcMenuButton" .. qcTooltipIndex].QuestID == qcTooltipQuestId then
		qcUpdateTooltip(qcTooltipIndex)
	end
	if pin and qcMapTooltipPin and qcMapTooltip:IsShown() then
		qcMapTooltipPin:OnMouseEnter()
	end
end

local function qcScheduleNameRedraw()
	if (qcNameRedrawTooltip or qcNameRedrawPin) and not qcNameRedrawScheduled then
		qcNameRedrawScheduled = true
		C_Timer.After(0, qcRedrawLoadedNames)
	end
end

-- A quest's data arrived, from our request or anyone's: redraw whatever shows its name, once per frame.
local function qcQuestDataArrived(questId, success)
	qcQuestLoadEnded(questId, success)
	if not success then return end
	qcQuestDataLoaded[questId] = true
	if qcClientNameUpperCache then
		local name = qcClientQuestName(questId)
		local upper = name and string.upper(name)
		qcClientNameUpperCache[questId] = (upper ~= qcQuestNameUpperCache[questId]) and upper or nil
	end
	for i = 1, 16 do
		local row = _G["qcMenuButton" .. i]
		if row:IsShown() and row.QuestID == questId then
			qcRequestRefresh(QC_REDRAW_ROWS)
			break
		end
	end
	if questId == qcTooltipQuestId or qcQuestTooltipWaiting[questId] then qcNameRedrawTooltip = true end
	if qcMapTooltipWaiting[questId] then qcNameRedrawPin = true end
	qcScheduleNameRedraw()
end

--[[ Quest givers' names in the client's language ]]--
-- A creature's tooltip data names it in the client's language. For a creature the client hasn't
-- cached, the reply is empty and TOOLTIP_DATA_UPDATE fires when the name arrives; an empty reply has
-- no ID to match that event to, so every name still awaited is checked again. Inside an instance the
-- game hides creature names, so nothing is asked there. A pin with no NPC ID keeps its stored name.
local QC_MAX_NPC_LOADS = 16
local QC_NPC_LOAD_TIMEOUT = 5

local qcNpcNames = {}
local qcNpcLoadQueue = {}
local qcNpcLoadQueued = {}
local qcNpcLoadInFlight = {}
local qcNpcLoadInFlightCount = 0
local qcNpcLoadTried = {}
local qcNpcLoadScheduled = false
-- NPCs whose names an open tooltip is still waiting for.
local qcNpcTooltipWaiting = {}
local qcNpcMapTooltipWaiting = {}

local function qcClientNpcName(npcId)
	local data = C_TooltipInfo.GetHyperlink(string.format("unit:Creature-0-0-0-0-%d-0000000000", npcId))
	local line = data and data.lines and data.lines[1]
	local name = line and line.leftText
	if name and not (issecretvalue and issecretvalue(name)) and name ~= "" then
		qcNpcNames[npcId] = name
		return name
	end
end

local function qcNpcNameArrived(npcId)
	if qcNpcTooltipWaiting[npcId] then qcNameRedrawTooltip = true end
	if qcNpcMapTooltipWaiting[npcId] then qcNameRedrawPin = true end
	qcScheduleNameRedraw()
end

local qcSendNpcLoads

-- Asking for a creature the client hasn't cached sends the request; it's tracked from then until the
-- name arrives or the timeout passes.
local function qcNpcLoadStarted(npcId)
	local token = {}
	qcNpcLoadTried[npcId] = true
	qcNpcLoadInFlight[npcId] = token
	qcNpcLoadInFlightCount = qcNpcLoadInFlightCount + 1
	C_Timer.After(QC_NPC_LOAD_TIMEOUT, function()
		if qcNpcLoadInFlight[npcId] ~= token then return end
		qcNpcLoadInFlight[npcId] = nil
		qcNpcLoadInFlightCount = qcNpcLoadInFlightCount - 1
		-- Names an instance hid aren't a failure: ask again after leaving.
		if IsInInstance() then qcNpcLoadTried[npcId] = nil end
		qcSendNpcLoads()
	end)
end

-- Only the pins of an opened map wait in the queue; a hovered pin asks straight away.
function qcSendNpcLoads()
	if IsInInstance() then return end
	while qcNpcLoadInFlightCount < QC_MAX_NPC_LOADS and #qcNpcLoadQueue > 0 do
		-- Newest first: the map opened last goes first.
		local npcId = table.remove(qcNpcLoadQueue)
		qcNpcLoadQueued[npcId] = nil
		if not (qcNpcNames[npcId] or qcNpcLoadInFlight[npcId] or qcNpcLoadTried[npcId]) then
			if qcClientNpcName(npcId) then
				qcNpcNameArrived(npcId)
			else
				qcNpcLoadStarted(npcId)
			end
		end
	end
end

local function qcQueueNpcName(npcId)
	if qcNpcNames[npcId] or qcNpcLoadQueued[npcId] or qcNpcLoadInFlight[npcId] or qcNpcLoadTried[npcId] then
		return
	end
	qcNpcLoadQueued[npcId] = true
	table.insert(qcNpcLoadQueue, npcId)
	if not qcNpcLoadScheduled then
		qcNpcLoadScheduled = true
		C_Timer.After(0, function()
			qcNpcLoadScheduled = false
			qcSendNpcLoads()
		end)
	end
end

local function qcNpcDataUpdated()
	if qcNpcLoadInFlightCount == 0 or IsInInstance() then return end
	local arrived = {}
	for npcId in pairs(qcNpcLoadInFlight) do
		if qcClientNpcName(npcId) then arrived[#arrived + 1] = npcId end
	end
	for _, npcId in ipairs(arrived) do
		qcNpcLoadInFlight[npcId] = nil
		qcNpcLoadInFlightCount = qcNpcLoadInFlightCount - 1
		qcNpcNameArrived(npcId)
	end
	if #arrived > 0 then qcSendNpcLoads() end
end

-- A pin's quest giver in the client's language, or the stored name until the client has it.
-- waiting, if given, collects the NPCs still loading.
local function qcNpcName(pinData, waiting)
	local npcId, stored = pinData[2], pinData[3]
	if not stored or npcId == 0 then return stored end
	local name = qcNpcNames[npcId]
	if name then return name end
	if IsInInstance() then
		qcQueueNpcName(npcId)
	else
		name = qcClientNpcName(npcId)
		if name then return name end
		if not (qcNpcLoadInFlight[npcId] or qcNpcLoadTried[npcId]) then qcNpcLoadStarted(npcId) end
	end
	if waiting then waiting[npcId] = true end
	return stored
end

-- The pins a map draws ask for their givers' names, so they're there before a pin is hovered.
local function qcRequestPinNpcNames(pins)
	if IsInInstance() then return end
	for _, pinData in ipairs(pins) do
		if pinData[3] and pinData[2] ~= 0 then qcQueueNpcName(pinData[2]) end
	end
end

-- Search function start

-- The box shows the game's own word for "Search" until something is typed.
local QC_SEARCH_PLACEHOLDER = SEARCH or "Search"

local function qcResetSearchBox()
	local searchBox = qcQuestCompletistUI.qcSearchBox
	searchBox:SetText(QC_SEARCH_PLACEHOLDER)
	searchBox:SetTextColor(0.5, 0.5, 0.5)
	if searchBox.Instructions then
		searchBox.Instructions:SetText(QC_SEARCH_PLACEHOLDER)
	end
end

-- Function to handle when the search box gains focus
function qcSearchBox_OnEditFocusGained(self)
    if self:GetText() == QC_SEARCH_PLACEHOLDER then
        self:SetText("")
        self:SetTextColor(1, 1, 1)  -- Set text color to normal
    end
    if self.Instructions then
        self.Instructions:SetText(QC_SEARCH_PLACEHOLDER)
    end
end

-- Function to handle when the search box loses focus
function qcSearchBox_OnEditFocusLost(self)
    if self:GetText() == "" then
        self:SetText(QC_SEARCH_PLACEHOLDER)
        self:SetTextColor(0.5, 0.5, 0.5)  -- Set text color to grey to indicate placeholder
        if self.Instructions then
            self.Instructions:SetText(QC_SEARCH_PLACEHOLDER)
        end
    end

    local searchText = string.upper(self:GetText())
    if not (searchText == "") and searchText ~= string.upper(QC_SEARCH_PLACEHOLDER) then
        qcUpdateQuestList(nil, 1, searchText)
    else
        qcUpdateQuestList(qcCurrentCategoryID, 1)
    end
end

-- Function to handle when the text in the search box changes
function qcSearchBox_OnTextChanged(self, userInput)
    if userInput == true then
        self.Instructions:SetText("")
        local searchText = string.upper(self:GetText())
        if not (searchText == "") and searchText ~= string.upper(QC_SEARCH_PLACEHOLDER) then
            qcUpdateQuestList(nil, 1, searchText)
        else
            qcUpdateQuestList(qcCurrentCategoryID, 1)
        end
    end
end

-- Event handler for ADDON_LOADED to initialize the search box
local function OnAddonLoaded(self, event, addonName)
    if addonName == "QuestCompletist" then
        local qcSearchBox = _G["qcSearchBox"]
        if qcSearchBox then
            qcSearchBox:SetText(QC_SEARCH_PLACEHOLDER)
            qcSearchBox:SetTextColor(0.5, 0.5, 0.5)
            if qcSearchBox.Instructions then
                qcSearchBox.Instructions:SetText(QC_SEARCH_PLACEHOLDER)
            end
            qcSearchBox:HookScript("OnEditFocusGained", qcSearchBox_OnEditFocusGained)
            qcSearchBox:HookScript("OnEditFocusLost", qcSearchBox_OnEditFocusLost)
            qcSearchBox:HookScript("OnTextChanged", qcSearchBox_OnTextChanged)

            -- Create wipe button
            local wipeButton = CreateFrame("Button", nil, qcSearchBox, "UIPanelCloseButton")
            wipeButton:SetSize(20, 20) -- small size
            wipeButton:SetPoint("RIGHT", qcSearchBox, "RIGHT", 20, 0) -- adjust offset as needed
            wipeButton:SetScript("OnClick", function()
                qcResetSearchBox()
                qcUpdateQuestList(qcCurrentCategoryID, 1)
            end)
            wipeButton:Hide() -- hidden until there’s text

            -- Show/hide the wipe button depending on text content
            qcSearchBox:HookScript("OnTextChanged", function(self)
                if self:GetText() ~= "" and self:GetText() ~= QC_SEARCH_PLACEHOLDER then
                    wipeButton:Show()
                else
                    wipeButton:Hide()
                end
            end)
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end

-- Create a frame to listen for the ADDON_LOADED event
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", OnAddonLoaded)


-- Search function end

function qcScrollUpdate(value) -- *
	if not (qcCurrentScrollPosition == value) then
		qcCurrentScrollPosition = value
		qcUpdateQuestList(nil, value)
	end
end

local function qcRecordServerCompletion(qcIndex)
	if qcIsRecurringQuest(qcIndex) then return false end
	local qcIsNew = (qcCharacterCompletions[qcIndex] == nil)
	qcCharacterCompletions[qcIndex] = 1
	qcUpdateMutuallyExclusiveCompletedQuest(qcIndex)
	qcUpdateSkippedBreadcrumbQuest(qcIndex)
	return qcIsNew
end

local function qcQueryQuestFlaggedComplete()

	local qcFound = 0
	local qcNewFlagged = 0

	for qcIndex in pairs(qcQuestDatabase) do
		if (C_QuestLog.IsQuestFlaggedCompleted(qcIndex)) then
			qcFound = (qcFound + 1)
			if qcRecordServerCompletion(qcIndex) then
				qcNewFlagged = (qcNewFlagged + 1)
			end
		end
	end

	return qcFound, qcNewFlagged
end

local function qcQuestQueryCompleted(qcAlwaysReport)

	local qcFound = 0
	local qcNewFlagged = 0
	local qcCompletedIDs = C_QuestLog.GetAllCompletedQuestIDs()

	if not (qcCompletedIDs) or (#qcCompletedIDs == 0) then
		qcFound, qcNewFlagged = qcQueryQuestFlaggedComplete()
	else
		for _, qcIndex in ipairs(qcCompletedIDs) do
			if not (qcQuestDatabase[qcIndex] == nil) then
				qcFound = (qcFound + 1)
				if qcRecordServerCompletion(qcIndex) then
					qcNewFlagged = (qcNewFlagged + 1)
				end
			end
		end
	end

	if (qcNewFlagged > 0) then
		qcRequestRefresh(QC_REBUILD_LIST, true)
	end
	if (qcNewFlagged > 0) or (qcAlwaysReport) then
		print(QCADDON_CHAT_TITLE .. string.format(qcL.SERVERQUERYRESULT, qcFound, qcNewFlagged))
	end

end

local function qcClearUpdateCache()
	wipe(qcCharacterCompletions)
	print(QCADDON_CHAT_TITLE .. qcL.CACHECLEARED)
	qcRequestRefresh(QC_REBUILD_LIST, true)
end

local function qcPurgeCollectedCache()
	if (qcCollectedQuests == nil) then qcCollectedQuests = {} end
	if (qcProgressComplete == nil) then qcProgressComplete = {} end
	wipe(qcCollectedQuests)
	wipe(qcProgressComplete)
	print(string.format("%sCollected Cache Purged.",QCADDON_CHAT_TITLE))
end

function qcMenuMouseWheel(self, delta) -- *
	local position = qcMenuSlider:GetValue()
	if (delta < 0) and (position < qcCurrentCategoryQuestCount) then
		qcMenuSlider:SetValue(position + 2)
	elseif (delta > 0) and (position > 1) then
		qcMenuSlider:SetValue(position - 2)
	end
end

function qcCategoryDropdown_Initialize(self, level, menuList)

	local stringformat = string.format
	local qcMenuData = {}
	
	if (level == 1) then
		for qcMenuIndex, qcMenuEntry in ipairs(qcCategoryMenu) do
			if (qcMenuEntry[3]) then
				qcMenuData = {text=stringformat("   %s",qcMenuEntry[2]),isTitle=false,notCheckable=true,hasArrow=true,value=qcMenuEntry[1]}
			else
				qcMenuData = {text=qcMenuEntry[2],isTitle=true,notCheckable=true,hasArrow=false}
			end
			UIDropDownMenu_AddButton(qcMenuData, level)
		end
	elseif (level == 2) then
		local qcParentValue = UIDROPDOWNMENU_MENU_VALUE
		for qcMenuIndex, qcMenuEntry in ipairs(qcCategoryMenu) do
			if (qcMenuEntry[1] == qcParentValue) then
				for qcSubmenuIndex, qcSubmenuEntry in ipairs(qcMenuEntry[3]) do
					if (qcSubmenuEntry[3]) then
						qcMenuData = {text=stringformat("   %s",qcSubmenuEntry[2]),isTitle=false,notCheckable=true,hasArrow=true,value=qcSubmenuEntry[1]}
					else
						if (tonumber(qcSubmenuEntry[1])) then
							qcMenuData = {text=qcSubmenuEntry[2],isTitle=false,notCheckable=false,hasArrow=false,value=qcSubmenuEntry[1],arg1=qcSubmenuEntry[1],func=function(button,arg1) qcQuestCompletistUI.qcSearchBox:SetText("");qcUpdateQuestList(arg1,1);CloseDropDownMenus();end}
						else
							qcMenuData = {text=qcSubmenuEntry[2],isTitle=false,notCheckable=false,hasArrow=false,value=qcSubmenuEntry[1],arg1=qcSubmenuEntry[1],func=function(button,arg1) qcProcessMenuAction(button,arg1);end}
						end
					end
					UIDropDownMenu_AddButton(qcMenuData, level)
				end
				break
			end
		end
	elseif (level == 3) then
		local qcParentValue = UIDROPDOWNMENU_MENU_VALUE
		for qcMenuIndex, qcMenuEntry in ipairs(qcCategoryMenu) do
			if (qcMenuEntry[3]) then
				for qcSubmenuIndex, qcSubmenuEntry in ipairs(qcMenuEntry[3]) do
					if (qcSubmenuEntry[1] == qcParentValue) then
						if (tonumber(qcSubmenuEntry[1])) then
							qcMenuData = {text=qcSubmenuEntry[2],isTitle=false,notCheckable=false,hasArrow=false,value=qcSubmenuEntry[1],arg1=qcSubmenuEntry[1],func=function(button,arg1) qcQuestCompletistUI.qcSearchBox:SetText("");qcUpdateQuestList(arg1,1);CloseDropDownMenus();end}
						else
							qcMenuData = {text=qcSubmenuEntry[2],isTitle=false,notCheckable=false,hasArrow=false,value=qcSubmenuEntry[1],arg1=qcSubmenuEntry[1],func=function(button,arg1) qcProcessMenuAction(button,arg1);end}
						end
						UIDropDownMenu_AddButton(qcMenuData, level)
					end
					break
				end
			else
				qcMenuData = {text=qcMenuEntry[2],isTitle=true,notCheckable=true,hasArrow=false}
			end
		end
	end

end
-- Assuming qcMenu is defined somewhere in qccore.lua as the list of menu items
-- Function to initialize the dropdown menu
local function InitializeCategoryDropDownMenu(self, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    local menu = menuList or qcMenu
    
    for _, item in ipairs(menu) do
        -- A numeric arg1 is a category id; its name comes from qcCategoryName rather than the
        -- qcL string baked into qcMenu. Headings may be named by the client too.
        local categoryName = type(item.arg1) == "number" and qcCategoryName(item.arg1)
        info.text = categoryName and ((item.text or ""):match("^%s*") .. categoryName) or qcMenuHeadingText(item)
        info.arg1 = item.arg1
        info.func = item.func
        info.notCheckable = true
        info.hasArrow = item.hasArrow
        info.menuList = item.menuList
        UIDropDownMenu_AddButton(info, level)
    end
end

-- Function to handle the dropdown button click
function qcCategoryDropdownButton_OnClick(self, button, down)
    local dropdown = CreateFrame("Frame", "qcCategoryDropDownMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(dropdown, InitializeCategoryDropDownMenu, "MENU")
    ToggleDropDownMenu(1, nil, dropdown, self, 0, 0)
end

-- Function to load the dropdown menu
function qcCategoryDropdown_OnLoad(self)
    UIDropDownMenu_Initialize(self, InitializeCategoryDropDownMenu)
end

-- Function to process menu actions
function qcProcessMenuAction(button, arg1)
    if (arg1 == "PERFORMSERVERQUERY") then
        print(string.format("%s%s", QCADDON_CHAT_TITLE, qcL.QUERYREQUESTED))
        qcQuestQueryCompleted(true)
        CloseDropDownMenus()
    elseif (arg1 == "CLEARUPDATECACHE") then
        print(QCADDON_CHAT_TITLE .. qcL.CLEARINGCACHE)
        qcClearUpdateCache()
        CloseDropDownMenus()
    elseif (arg1 == "SORTLEVEL") then
        qcSettings.SORT = 1
        qcQuestCompletistUI.qcSearchBox:SetText("")
        qcUpdateQuestList(qcCurrentCategoryID, qcMenuSlider:GetValue())
        CloseDropDownMenus()
    elseif (arg1 == "SORTALPHA") then
        qcSettings.SORT = 2
        qcQuestCompletistUI.qcSearchBox:SetText("")
        qcUpdateQuestList(qcCurrentCategoryID, qcMenuSlider:GetValue())
        CloseDropDownMenus()
    end
end

function qcProcessMenuSelection(self, arg1)
    qcQuestCompletistUI.qcSearchBox:SetText("")
    qcUpdateQuestList(arg1, 1)
    CloseDropDownMenus()
end

-- The category of the zone the player is in. The list follows the player while it's hidden, or
-- while it's showing that zone with no search; someone browsing elsewhere is left where they are.
-- The first zone after loading is always followed: the window starts out shown.
local qcZoneCategoryID = nil

local function qcZoneChangedNewArea() -- *
	local categoryId = qcAreaIDToCategoryID[C_Map.GetBestMapForUnit("player")]
	if not categoryId or categoryId == qcZoneCategoryID then return end
	local following = (qcZoneCategoryID == nil) or not qcQuestCompletistUI:IsVisible()
		or (qcCurrentCategoryID == qcZoneCategoryID and not qcCurrentSearchText)
	qcZoneCategoryID = categoryId
	if not following then return end
	if qcCurrentSearchText then
		qcResetSearchBox()
	end
	qcCurrentCategoryID = categoryId
	qcCurrentSearchText = nil
	qcUpdateQuestList(categoryId, 1)
end

-- Start Tooltip when mouse over quest name
-- Ensure the necessary tables from qcQuest.lua are loaded
local qcAreaIDToCategoryID = qcAreaIDToCategoryID or {} -- Maps zone ID to internal category ID
local qcQuestCategories = qcQuestCategories or {} -- Maps internal category ID to zone name

-- Category names come from the client where qcCategoryUiMapID knows a map for them, so they need
-- no translation of ours. Everything else falls back to qcLocalize, then to the English name in
-- qcQuestCategories.
local qcCategoryLocaleKey, qcCategoryEnglishName = {}, {}
for _, categoryData in ipairs(qcQuestCategories) do
	qcCategoryLocaleKey[categoryData[1]] = (categoryData[2]:gsub("[^%a%d]", "")):upper()
	qcCategoryEnglishName[categoryData[1]] = categoryData[2]
end

local function qcClientName(source)
	local kind, id = source[1], source[2]
	local name
	if (kind == "map") then
		local info = C_Map.GetMapInfo(id)
		name = info and info.name
	elseif (kind == "area") then
		name = C_Map.GetAreaInfo(id)
	elseif (kind == "instance") then
		name = EJ_GetInstanceInfo(id)
	elseif (kind == "class") then
		local info = C_CreatureInfo.GetClassInfo(id)
		name = info and info.className
	elseif (kind == "covenant") then
		local data = C_Covenants.GetCovenantData(id)
		name = data and data.name
	elseif (kind == "skill") then
		name = C_TradeSkillUI.GetTradeSkillDisplayName(id)
	elseif (kind == "achievementcategory") then
		name = GetCategoryInfo(id)
	elseif (kind == "faction") then
		local data = C_Reputation.GetFactionDataByID(id)
		name = data and data.name
	elseif (kind == "string") then
		name = _G[id]
	elseif (kind == "format") then
		local parts = {}
		for i = 3, #source do
			local part = qcClientName(source[i])
			if (not part) then return nil end
			parts[#parts + 1] = part
		end
		name = string.format(id, unpack(parts))
	end
	if (type(name) == "string" and name ~= "") then return name end
end

-- The category's name as the client has it, in the player's language, or nil.
function qcClientCategoryName(categoryId)
	local uiMapId = qcCategoryUiMapID and qcCategoryUiMapID[categoryId]
	local name = uiMapId and qcClientName({"map", uiMapId})
	if (name) then return name end
	local source = qcCategoryClientName and qcCategoryClientName[categoryId]
	return source and qcClientName(source)
end

-- A menu heading's text, from the client where qcMenu says how (clientName), keeping its indent.
function qcMenuHeadingText(item)
	local name = item.clientName and item.text and qcClientName(item.clientName)
	if (name) then return item.text:match("^%s*") .. name end
	return item.text
end

function qcCategoryName(categoryId)
	local clientName = qcClientCategoryName(categoryId)
	if (clientName) then return clientName end

	local key = qcCategoryLocaleKey[categoryId]
	if (key and qcL[key]) then return qcL[key] end

	return qcCategoryEnglishName[categoryId]
end

-- Function to get the zone name from a zone ID with enhanced handling for array-style lookup
-- The name of the category a map belongs to, else the map's own name from the client (a class hall
-- or a city floor qcAreaIDToCategoryID doesn't list).
function GetZoneNameFromZoneID(zoneId)
    local categoryID = qcAreaIDToCategoryID[zoneId]
    local zoneName = categoryID and qcCategoryName(categoryID)
    if zoneName and zoneName ~= "" then return zoneName end
    local info = C_Map.GetMapInfo(zoneId)
    if info and info.name and info.name ~= "" then return info.name end
    return qcL.UNKNOWNZONE
end

-- Every pin that offers a quest, with its map, found on first use. An index of all quests would
-- cost several MB; only the quests whose tooltips or waypoints are used get a list.
local qcPinsOfQuest = {}
local function qcQuestPins(questId)
	local found = qcPinsOfQuest[questId]
	if not found then
		found = {}
		for mapId, pins in pairs(qcPinDB) do
			for _, pin in ipairs(pins) do
				for _, pinQuestId in ipairs(pin[6] or {}) do
					if pinQuestId == questId then
						found[#found + 1] = {mapId, pin}
						break
					end
				end
			end
		end
		qcPinsOfQuest[questId] = found
	end
	return found
end

-- A quest can have several pins (offered in more than one place, or by an NPC who moves around a
-- map). Pick one: the nearest on the player's current map, otherwise the one on the lowest map ID.
local function qcFindPinForQuest(questId)
	local playerMap = C_Map.GetBestMapForUnit("player")
	local playerPos = playerMap and C_Map.GetPlayerMapPosition(playerMap, "player")
	local px, py
	if playerPos then
		px, py = playerPos:GetXY()
		px, py = px * 100, py * 100
	end
	local bestMap, bestPin, bestDist, bestOnPlayerMap
	for _, found in ipairs(qcQuestPins(questId)) do
		local mapId, pin = found[1], found[2]
		if mapId == playerMap and px then
			local dist = (pin[4] - px) ^ 2 + (pin[5] - py) ^ 2
			if not bestOnPlayerMap or dist < bestDist then
				bestMap, bestPin, bestDist, bestOnPlayerMap = mapId, pin, dist, true
			end
		elseif not bestOnPlayerMap and (not bestMap or mapId < bestMap) then
			bestMap, bestPin = mapId, pin
		end
	end
	return bestMap, bestPin
end

local QC_STORYLINE_WINDOW = 15

-- The faction's name in the player's language, or the English one from qcFactions.
local function qcFactionName(factionId)
	local data = C_Reputation.GetFactionDataByID(factionId)
	if data and data.name and data.name ~= "" then return data.name end
	return qcFactions[factionId]
end

-- Function to update the quest tooltip
function qcUpdateTooltip(index)
    local stringFormat = string.format
    local questId = _G["qcMenuButton" .. index].QuestID
    local att_HookBackup

    if questId then
        -- SetHyperlink below renders nothing until the server has sent the quest's data, so ask
        -- for it and redraw when it lands (see qcQuestDataArrived).
        qcTooltipIndex = index
        qcTooltipQuestId = questId
        wipe(qcQuestTooltipWaiting)
        wipe(qcNpcTooltipWaiting)
        qcRequestQuestData(questId)

        -- Temporarily disable ATT's quest tooltip hook so it can't add its own ID
        if C_AddOns.IsAddOnLoaded("AllTheThings") and GameTooltip.OnTooltipSetQuest then
            att_HookBackup = GameTooltip.OnTooltipSetQuest
            GameTooltip.OnTooltipSetQuest = function() end
        end

        -- Setup tooltip
        qcQuestInformationTooltip:SetOwner(qcQuestCompletistUI, "ANCHOR_BOTTOMRIGHT", -30, 500)
        qcQuestInformationTooltip:ClearLines()
        -- Without the quest's data, SetHyperlink leaves the tooltip unable to show at all, even the
        -- lines added after it, so name the quest ourselves until the data arrives.
        if HaveQuestData(questId) then
            qcQuestInformationTooltip:SetHyperlink(stringFormat("quest:%d", questId))
        else
            qcQuestInformationTooltip:AddLine(qcQuestName(questId), 1, 1, 1)
            qcQuestInformationTooltip:AddLine(qcL.NODETAILS, 0.5, 0.5, 0.5)
        end
        qcQuestInformationTooltip:AddLine(" ")
        qcQuestInformationTooltip:AddDoubleLine(qcL.QUESTID, stringFormat("|cFF69CCF0%d|r", questId))
        qcQuestInformationTooltip:AddLine(" ")

        -- Restore ATT hook if we temporarily replaced it
        if att_HookBackup then
            GameTooltip.OnTooltipSetQuest = att_HookBackup
            att_HookBackup = nil
        end

        -- Storyline information. qcQuestLines holds each storyline's quests in Blizzard's order;
        -- a whole-zone storyline runs to 200+ quests, so only a window around this one is shown.
        local storylineId = qcQuestDatabase[questId][8]
        local storyline = storylineId and qcQuestLines[storylineId]
        if storyline then
            -- Older zones share one storyline between both factions; follow the list's faction filter.
            local factionFlag = (qcSettings.QC_ML_HIDE_FACTION == 1) and qcFactionBits[string.upper(UnitFactionGroup("player") or "")]
            local lineQuests = {}
            for _, lineQuestId in ipairs(storyline.quests) do
                local lineQuest = qcQuestDatabase[lineQuestId]
                if lineQuest and (lineQuestId == questId or not factionFlag or qcMaskAllows(lineQuest[5], factionFlag)) then
                    table.insert(lineQuests, lineQuestId)
                end
            end
            local position = 1
            for i, lineQuestId in ipairs(lineQuests) do
                if lineQuestId == questId then
                    position = i
                    break
                end
            end
            qcQuestInformationTooltip:AddDoubleLine(qcL.STORYLINE, stringFormat("%s%s|r |cFF808080%s|r", COLOUR_HUNTER, storyline.name, stringFormat(qcL.STORYLINEPOSITION, position, #lineQuests)))
            qcQuestInformationTooltip:AddLine(" ")

            local first = math.max(1, position - math.floor(QC_STORYLINE_WINDOW / 2))
            local last = math.min(#lineQuests, first + QC_STORYLINE_WINDOW - 1)
            first = math.max(1, last - QC_STORYLINE_WINDOW + 1)
            if first > 1 then
                qcQuestInformationTooltip:AddLine("|cFF808080   " .. stringFormat(qcL.EARLIERQUESTS, first - 1) .. "|r")
            end
            for i = first, last do
                local lineQuestId = lineQuests[i]
                local questData = qcQuestDatabase[lineQuestId]
                if questData then
                    local questStatus
                    if C_QuestLog.IsOnQuest(lineQuestId) then
                        questStatus = "|cFFFFFF00" .. qcL.ONQUEST .. "|r"
                    else
                        questStatus = C_QuestLog.IsQuestFlaggedCompleted(lineQuestId) and ("|cFF00FF00" .. qcL.COMPLETED .. "|r") or ("|cFFFF0000" .. qcL.NOTCOMPLETED .. "|r")
                    end
                    qcQuestInformationTooltip:AddDoubleLine(((lineQuestId == questId) and " > " or " - ") .. qcQuestName(lineQuestId, qcQuestTooltipWaiting), questStatus)
                end
            end
            if last < #lineQuests then
                qcQuestInformationTooltip:AddLine("|cFF808080   " .. stringFormat(qcL.LATERQUESTS, #lineQuests - last) .. "|r")
            end

            qcQuestInformationTooltip:AddLine(" ")
        end

        -- Prerequisite quest logic
        local prereqQuestId = qcQuestPrereq[questId]
        if prereqQuestId and prereqQuestId ~= 0 then
            local prereqQuestName = qcQuestName(prereqQuestId, qcQuestTooltipWaiting) or qcL.UNKNOWNQUEST
            local prereqQuestStatus = C_QuestLog.IsQuestFlaggedCompleted(prereqQuestId) and ("|cFF00FF00" .. qcL.COMPLETED .. "|r") or ("|cFFFF0000" .. qcL.NOTCOMPLETED .. "|r")
            qcQuestInformationTooltip:AddDoubleLine(qcL.REQUIREDQUEST, string.format("%s - %s", prereqQuestName, prereqQuestStatus))
            qcQuestInformationTooltip:AddLine(" ")
        end
		-- Renown and Faction requirements Start
        local renownInfo = qcRenownLevelRequirements[questId]

        if renownInfo then
            if type(renownInfo) == "table" then
                local factionId = renownInfo[1]
                local requiredRenownLevel = renownInfo[2]
                local factionName = qcFactionName(factionId) or qcL.UNKNOWNFACTION
                local currentRenownLevel = C_MajorFactions.GetCurrentRenownLevel(factionId)

                qcQuestInformationTooltip:AddDoubleLine(qcL.REQUIREDFACTION, string.format("%s%s", COLOUR_DRUID, factionName))

                if currentRenownLevel then
                    if currentRenownLevel >= requiredRenownLevel then
                        qcQuestInformationTooltip:AddDoubleLine(qcL.REQUIREDRENOWN, "|cFF00FF00" .. string.format(qcL.RENOWNMET, requiredRenownLevel) .. "|r")
                    else
                        qcQuestInformationTooltip:AddDoubleLine(qcL.REQUIREDRENOWN, "|cFFFF0000" .. string.format(qcL.RENOWNNOTMET, requiredRenownLevel) .. "|r")
                    end
                else
                    qcQuestInformationTooltip:AddDoubleLine(qcL.REQUIREDRENOWN, "|cFFFF0000" .. qcL.DATAUNAVAILABLE .. "|r")
                end
            elseif type(renownInfo) == "number" then
                local factionName = qcFactionName(renownInfo) or qcL.UNKNOWNFACTION
                qcQuestInformationTooltip:AddDoubleLine(qcL.REQUIREDFACTION, string.format("%s%s", COLOUR_DRUID, factionName))
            end

            qcQuestInformationTooltip:AddLine(" ")
        end
		-- Renown and Faction requirements End

        -- Quest Giver Information from qcPinDB.lua: the pin a TomTom waypoint would go to
        local giverMapId, giverPin = qcFindPinForQuest(questId)
        if giverPin then
            qcQuestInformationTooltip:AddDoubleLine(
                qcL.QUESTGIVER,
                string.format("%s (%s, %.1f, %.1f)", qcNpcName(giverPin, qcNpcTooltipWaiting) or qcL.UNKNOWNNPC,
                    GetZoneNameFromZoneID(giverMapId), giverPin[4] or 0, giverPin[5] or 0)
            )
        else
            qcQuestInformationTooltip:AddDoubleLine(qcL.QUESTGIVER, qcL.NOQUESTGIVER)
        end

        -- Faction and reputation information
        local reputationEntries = qcQuestReputation[questId]
        local hasReputation = false
        local factionIds = {}

        if reputationEntries then
            for factionId, repValue in pairs(reputationEntries) do
                if repValue ~= 0 then
                    hasReputation = true
                end
                factionIds[#factionIds + 1] = factionId
            end
            table.sort(factionIds)
        end

        if hasReputation then
            qcQuestInformationTooltip:AddLine(" ")
            qcQuestInformationTooltip:AddLine(GetText("COMBAT_TEXT_SHOW_REPUTATION_TEXT"))

            for _, factionId in ipairs(factionIds) do
                qcQuestInformationTooltip:AddDoubleLine(
                    "  " .. (qcFactionName(factionId) or tostring(factionId)),
                    COLOUR_DRUID .. stringFormat(qcL.REPAMOUNT, reputationEntries[factionId])
                )
            end
        end

        -- Make sure the main tooltip is shown
        qcQuestInformationTooltip:Show()
    end
end

-- End Tooltip when mouse over quest name


function qcQuestClick(qcButtonIndex)
	local qcQuestID = _G["qcMenuButton" .. qcButtonIndex].QuestID
	if (IsLeftShiftKeyDown()) then --[[ User wants to toggle the completed status of a quest ]]--
		-- Completed becomes marked not done (0); anything else becomes completed.
		qcCharacterCompletions[qcQuestID] = (qcCharacterCompletions[qcQuestID] == 1) and 0 or 1
	elseif (IsLeftAltKeyDown()) then --[[ User wants to toggle the unattainable status of a quest ]]--
		-- Unattainable becomes marked not done (0); anything else becomes unattainable.
		qcCharacterCompletions[qcQuestID] = (qcCharacterCompletions[qcQuestID] == 2) and 0 or 2
  else
		-- print(string.format("%sLooking for Tom Tom.",QCADDON_CHAT_TITLE))
    if (C_AddOns.IsAddOnLoaded('TomTom')) then
        local mapId, pin = qcFindPinForQuest(qcQuestID)
        if (mapId) then
            TomTom:AddWaypoint(mapId, pin[4] / 100, pin[5] / 100, {title = qcNpcName(pin) or qcQuestName(qcQuestID)})
            TomTom:SetClosestWaypoint()
        end
    end
end

	-- The list only redraws, so a quest marked by mistake stays on screen to unmark.
	qcRequestRefresh(QC_REDRAW_ROWS, true)

end


function qcFilterButton_OnClick(self, button, down) --TWW changed
Settings.OpenToCategory(qcInterfaceOptions.category:GetID())
end


function qcCloseTooltip()
	qcTooltipIndex = nil
	qcTooltipQuestId = nil
	qcQuestInformationTooltip:Hide()
end

local function qcUpdateCompletedQuest(questId) -- *
	if (qcQuestDatabase[questId]) and qcIsRecurringQuest(questId) then
		return nil
	end
	if not (qcCharacterCompletions[questId]) then qcCharacterCompletions[questId] = 1 end
end

local function qcNewDataChecks(questId) -- *
	if ((questId == nil) or (questId == 0)) then return nil end
	if not (qcQuestDatabase[questId]) then
		qcNewDataAlert.New = true
		qcNewDataAlert.Faction = false
		qcNewDataAlert.Race = false
		qcNewDataAlert.Class = false
		qcNewDataAlert:Show()
	else
		qcNewDataAlert:Hide()
		qcNewDataAlert.New = false
		qcNewDataAlert.Faction = false
		qcNewDataAlert.Race = false
		qcNewDataAlert.Class = false
		local factionFlag, raceFlag, classFlag = 0, 0, 0
		local playerFaction, _ = UnitFactionGroup("player")
		local _, playerRace = UnitRace("player")
		local _, playerClass = UnitClass("player")
		factionFlag = qcFactionBits[string.upper(playerFaction)]
		if (bit.band(factionFlag,qcQuestDatabase[questId][5]) == 0) then
			qcNewDataAlert.Faction = true
		end
		raceFlag = qcRaceBits[string.upper(playerRace)]
		if (bit.band(raceFlag,qcQuestDatabase[questId][6]) == 0) then
			qcNewDataAlert.Race = true
		end
		classFlag = qcClassBits[string.upper(playerClass)]
		if (bit.band(classFlag,qcQuestDatabase[questId][7]) == 0) then
			qcNewDataAlert.Class = true
		end
		if ((qcNewDataAlert.Faction) or (qcNewDataAlert.Race) or (qcNewDataAlert.Class)) then
			qcNewDataAlert:Show()
		end
	end
end

function qcNewDataAlert_OnEnter(self) -- *
	qcNewDataAlertTooltip:SetOwner(qcNewDataAlert, "ANCHOR_CURSOR")
	qcNewDataAlertTooltip:ClearLines()
	qcNewDataAlertTooltip:AddLine("Quest Completist")
	qcNewDataAlertTooltip:AddLine(COLOUR_HUNTER .. qcL.NEWDATAINTRO, nil, nil, nil, true)
	if (qcNewDataAlert.New) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. qcL.NEWDATAQUEST, nil, nil, nil, true)
		qcNewDataAlertTooltip:Show()
	end
	if (qcNewDataAlert.Faction) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. qcL.NEWDATAFACTION, nil, nil, nil, true)
	end
	if (qcNewDataAlert.Race) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. qcL.NEWDATARACE, nil, nil, nil, true)
	end
	if (qcNewDataAlert.Class) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. qcL.NEWDATACLASS, nil, nil, nil, true)
	end
	if ((qcNewDataAlert.New) or (qcNewDataAlert.Faction) or (qcNewDataAlert.Race) or (qcNewDataAlert.Class)) then
		qcNewDataAlertTooltip:Show()
	end
end

function qcNewDataAlert_OnLeave(self) -- *
	qcNewDataAlertTooltip:Hide()
end

local function qcBreadcrumbChecks(qcQuestID)

	if (qcQuestID == nil) or (qcQuestID == 0) then return nil end

	if (qcBreadcrumbQuests[qcQuestID] == nil) then
		qcToast.QuestID = nil
		qcToast:Hide()
	else
		qcToast.QuestID = qcQuestID
		local qcCount = 0
		for qcBreadcrumbIndex, qcBreadcrumbEntry in pairs(qcBreadcrumbQuests[qcQuestID]) do
			if (qcCharacterCompletions[qcBreadcrumbEntry] == nil) then
				qcCount = (qcCount + 1)
			else
				if not (qcCharacterCompletions[qcBreadcrumbEntry] == 1) then
					qcCount = (qcCount + 1)
				end
			end
		end
		if (qcCount == 0) then
			qcToast.QuestID = nil
			qcToast:Hide()
		else
			if (qcCount == 1) then
				qcToastText:SetText(qcL.BREADCRUMBAVAILABLE)
			else
				qcToastText:SetText(string.format(qcL.BREADCRUMBSAVAILABLE, qcCount))
			end
			qcToast:Show()
		end
	end

end

local function qcMutuallyExclusiveChecks(qcQuestID)

	if (qcQuestID == nil) or (qcQuestID == 0) then return nil end

	if (qcMutuallyExclusive[qcQuestID] == nil) then
		qcMutuallyExclusiveAlert.QuestID = nil
		qcMutuallyExclusiveAlert:Hide()
	else
		qcMutuallyExclusiveAlert.QuestID = qcQuestID
		qcMutuallyExclusiveAlert:Show()
	end

end

function qcMapTooltipSetup() -- *
	qcMapTooltip = CreateFrame("GameTooltip", "qcMapTooltip", UIParent, "GameTooltipTemplate")
	qcMapTooltip:SetFrameStrata("TOOLTIP")
	WorldMapFrame:HookScript("OnSizeChanged",
		function(self)
			qcMapTooltip:SetScale(1/self:GetScale())
		end
	)
end

function qcQuestInformationTooltipSetup() -- *
	qcQuestInformationTooltip = CreateFrame("GameTooltip", "qcQuestInformationTooltip", qcQuestCompletistUI, "GameTooltipTemplate")
	qcQuestInformationTooltip:SetFrameStrata("TOOLTIP")
end

function qcToastTooltipSetup() -- *
	qcToastTooltip = CreateFrame("GameTooltip", "qcToastTooltip", qcToast, "GameTooltipTemplate")
	qcToastTooltip:SetFrameStrata("TOOLTIP")
end

function qcNewDataAlertTooltipSetup() -- *
	qcNewDataAlertTooltip = CreateFrame("GameTooltip", "qcNewDataAlertTooltip", qcNewDataAlert, "GameTooltipTemplate")
	qcNewDataAlertTooltip:SetFrameStrata("TOOLTIP")
end

function qcMutuallyExclusiveAlertTooltipSetup() -- *
	qcMutuallyExclusiveAlertTooltip = CreateFrame("GameTooltip", "qcMutuallyExclusiveAlertTooltip", qcMutuallyExclusiveAlert, "GameTooltipTemplate")
	qcMutuallyExclusiveAlertTooltip:SetFrameStrata("TOOLTIP")
end

function qcGetToastQuestInformation(questId) -- *
	if (questId) then
		if (qcQuestDatabase[questId]) then
			return qcQuestName(questId)
		end
	end
end

function qcToast_OnEnter(self)

	if (self.QuestID == nil) then
		qcToastTooltip:Hide()
	else
		qcToastTooltip:SetOwner(qcToast, "ANCHOR_CURSOR")
		qcToastTooltip:ClearLines()
		qcToastTooltip:AddLine(qcL.BREADCRUMBQUESTS)
		for qcBreadcrumbIndex, qcBreadcrumbEntry in pairs(qcBreadcrumbQuests[self.QuestID]) do
			if (qcCharacterCompletions[qcBreadcrumbEntry] == nil) then
				local qcQuestName = qcGetToastQuestInformation(qcBreadcrumbEntry)
				if (qcQuestName and qcBreadcrumbEntry) then qcToastTooltip:AddLine(tostring(COLOUR_DRUID .. qcQuestName .. COLOUR_MAGE .. " [" .. qcBreadcrumbEntry .. "]")) end
			else
				if not (qcCharacterCompletions[qcBreadcrumbEntry] == 1) then
				local qcQuestName = qcGetToastQuestInformation(qcBreadcrumbEntry)
				if (qcQuestName and qcBreadcrumbEntry) then qcToastTooltip:AddLine(tostring(COLOUR_DRUID .. qcQuestName .. " [" .. qcBreadcrumbEntry .. "]")) end
				end
			end
		end
		qcToastTooltip:Show()
	end

end

function qcToast_OnLeave(self) -- *
	qcToastTooltip:Hide()
end

function qcMutuallyExclusiveQuestInformation(qcQuestID)

	if (qcQuestID) then
		if (qcQuestDatabase[qcQuestID]) then
			return qcQuestName(qcQuestID)
		end
	end

	return nil

end

function qcMutuallyExclusiveAlert_OnEnter(self)

	if (self.QuestID == nil) then
		qcMutuallyExclusiveAlertTooltip:Hide()
	else
		qcMutuallyExclusiveAlertTooltip:SetOwner(qcMutuallyExclusiveAlert, "ANCHOR_BOTTOMRIGHT")
		qcMutuallyExclusiveAlertTooltip:ClearLines()
		qcMutuallyExclusiveAlertTooltip:AddLine("Quest Completist")
		qcMutuallyExclusiveAlertTooltip:AddLine(COLOUR_MAGE .. qcL.MUTUALLYEXCLUSIVE, nil, nil, nil, true)
		for qcMutuallyExclusiveIndex, qcMutuallyExclusiveEntry in pairs(qcMutuallyExclusive[self.QuestID]) do
			if (qcQuestDatabase[qcMutuallyExclusiveEntry] == nil) then
				qcMutuallyExclusiveAlertTooltip:AddLine(string.format("%s<%s> [%d]|r", COLOUR_DRUID, qcL.NOTINDATABASE, qcMutuallyExclusiveEntry))
			else
				local qcQuestName = qcMutuallyExclusiveQuestInformation(qcMutuallyExclusiveEntry)
				if (qcQuestName and qcMutuallyExclusiveEntry) then qcMutuallyExclusiveAlertTooltip:AddLine(string.format("%s%s [%d]|r",COLOUR_DRUID,qcQuestName,qcMutuallyExclusiveEntry)) end
			end
		end
		qcMutuallyExclusiveAlertTooltip:Show()
	end
end

function qcMutuallyExclusiveAlert_OnLeave(self)

	qcMutuallyExclusiveAlertTooltip:Hide()

end

--[[ ##### MAP PINS START ##### ]]--
-- Coloured quest name function
local function qcColouredQuestName(questId)
    if not questId or not qcQuestDatabase[questId] then return nil end
    local questData = qcQuestDatabase[questId]
    local questName = qcQuestName(questId, qcMapTooltipWaiting)
    if questData[4] == 4 or questData[4] == 2 then
        return string.format("|cff178ed5%s|r", questName)
    elseif not qcCharacterCompletions[questId] then
        return string.format("|cffffffff%s|r", questName)
    elseif qcIsQuestCompleted(questId) then
        return string.format("|cff00ff00%s|r", questName)
    else
        return string.format("|cffffffff%s [U]|r", questName)
    end
end

qcPinMixin = CreateFromMixins(MapCanvasPinMixin)

function qcPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1.0, 1.0)
end

local function qcSinglePinIcon(pinData)
    local icon = pinData[1]
    if icon == 3 then
        local professionMask = 0
        for _, questId in ipairs(pinData[6]) do
            local quest = qcQuestDatabase[questId]
            if quest then
                professionMask = bit.bor(professionMask, qcQuestProfession[questId] or 0)
            end
        end
        return qcProfessionIcon(professionMask)
    elseif icon == 1 then
        return qcNormalPinIcon(pinData[6])
    end
    return QC_PIN_ICONS[icon] or QC_ICON_NORMAL
end

local function qcPinIcon(pinData)
    if not pinData.stack then
        return qcSinglePinIcon(pinData)
    end
    local best, bestRank
    for _, member in ipairs(pinData.stack) do
        local icon = qcSinglePinIcon(member)
        local rank = QC_PIN_ICON_RANK[icon] or 1
        if not best or rank > bestRank then
            best, bestRank = icon, rank
        end
    end
    return best
end

function qcPinMixin:OnAcquired(pinData)
    self.PinData = pinData
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetPosition(pinData[4] / 100, pinData[5] / 100)
    self:SetSize(24, 24)

    qcSetIcon(self.Texture, qcPinIcon(pinData))

    -- Initialize isGrey as true, and turn it to false if ANY quest is available
    local isGrey = true
    local playerLevel = UnitLevel("player")
    for _, questId in ipairs(pinData[6]) do
        if questId and qcQuestDatabase[questId] then
            local prereqQuestId = qcQuestPrereq[questId] or 0
            local requiredLevel = qcQuestDatabase[questId][2]
            if playerLevel >= (requiredLevel or 0) then
                if prereqQuestId == 0 or (prereqQuestId and C_QuestLog.IsQuestFlaggedCompleted(prereqQuestId)) then
                    isGrey = false
                    break
                end
            end
        end
    end
    if isGrey then
        self.Texture:SetVertexColor(0.5, 0.5, 0.5)
    else
        self.Texture:SetVertexColor(1, 1, 1)
    end
end

local function qcPinGiverName(pinData)
    if pinData[3] then
        return qcNpcName(pinData, qcNpcMapTooltipWaiting)
    elseif pinData[2] ~= 0 or pinData[7] then
        return string.format("%s |cff69ccf0%s|r", UnitName("player"), qcL.YOURSELF)
    end
end

local function qcHideTooltipIcons()
    qcMapTooltip.qcIcons = qcMapTooltip.qcIcons or {}
    for _, icon in ipairs(qcMapTooltip.qcIcons) do
        icon:Hide()
    end
    qcMapTooltip.qcIconsUsed = 0
end

local function qcAcquireTooltipIcon()
    qcMapTooltip.qcIconsUsed = qcMapTooltip.qcIconsUsed + 1
    local icon = qcMapTooltip.qcIcons[qcMapTooltip.qcIconsUsed]
    if not icon then
        icon = qcMapTooltip:CreateTexture(nil, "OVERLAY")
        icon:SetSize(16, 16)
        qcMapTooltip.qcIcons[qcMapTooltip.qcIconsUsed] = icon
    end
    return icon
end

local function qcAddGiverToTooltip(pinData, name)
    if pinData[2] == 0 then
        qcMapTooltip:AddLine(name)
    else
        qcMapTooltip:AddDoubleLine(name, string.format("|cffff7d0a[%d]|r", pinData[2]))
    end
end

local function qcAddPinQuestsToTooltip(pinData)
    for _, qcEntry in ipairs(pinData[6]) do
        local questData = qcQuestDatabase[qcEntry]
        if questData then
            qcMapTooltip:AddDoubleLine("    " .. qcColouredQuestName(qcEntry), string.format("|cffff7d0a[%d]|r", qcEntry))
            local line = _G["qcMapTooltipTextLeft" .. qcMapTooltip:NumLines()]
            if line then
                local lineIcon = qcRecurringQuestIcon(qcEntry, questData[4])
                if not lineIcon then
                    if qcIsQuestCompleted(qcEntry) then
                        lineIcon = QC_ICON_COMPLETE
                    else
                        lineIcon = QC_ICON_NORMAL
                    end
                end
                local icon = qcAcquireTooltipIcon()
                qcSetIcon(icon, lineIcon)
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", line, "LEFT", -6, 0)
                icon:Show()
            end
        else
            qcMapTooltip:AddDoubleLine("    |cff808080" .. qcL.NOTINDATABASE .. "|r", string.format("|cffff7d0a[%d]|r", qcEntry))
        end
    end

    if pinData[7] then
        qcMapTooltip:AddLine(string.format("|cffabd473%s|r", pinData[7]), nil, nil, nil, true)
    end
end

function qcPinMixin:OnMouseEnter()
    local pinData = self.PinData
    if not pinData then return end
    qcMapTooltipPin = self
    wipe(qcMapTooltipWaiting)
    wipe(qcNpcMapTooltipWaiting)

    local mapWidth, mapHeight = WorldMapFrame:GetCanvas():GetSize()
    local x, y = self:GetCenter()
    local anchorPoint = "ANCHOR_RIGHT"
    if x and mapWidth and x > mapWidth * 0.75 then
        anchorPoint = "ANCHOR_LEFT"
    end
    if y and mapHeight and y > mapHeight * 0.75 then
        anchorPoint = "ANCHOR_BOTTOM"
    end

    qcMapTooltip:SetOwner(self, anchorPoint)
    qcMapTooltip:ClearLines()
    qcHideTooltipIcons()

    -- Pins with no quest giver name are listed last under one heading, as their quests needn't
    -- belong to the giver above them; pins sharing a name are listed as one giver.
    local givers, giverByName, others = {}, {}, {}
    for _, member in ipairs(pinData.stack or {pinData}) do
        local name = qcPinGiverName(member)
        if not name then
            table.insert(others, member)
        elseif giverByName[name] then
            table.insert(giverByName[name].pins, member)
        else
            giverByName[name] = {name = name, pins = {member}}
            table.insert(givers, giverByName[name])
        end
    end

    for index, giver in ipairs(givers) do
        if index > 1 then
            qcMapTooltip:AddLine(" ")
        end
        qcAddGiverToTooltip(giver.pins[1], giver.name)
        for _, member in ipairs(giver.pins) do
            qcAddPinQuestsToTooltip(member)
        end
    end
    if #others > 0 and #givers > 0 then
        qcMapTooltip:AddLine(" ")
        qcMapTooltip:AddLine("|cff808080" .. qcL.OTHERQUESTS .. "|r")
    end
    for _, member in ipairs(others) do
        qcAddPinQuestsToTooltip(member)
    end

    qcMapTooltip:Show()
end

function qcPinMixin:OnMouseLeave()
    qcMapTooltipPin = nil
    qcMapTooltip:Hide()
    qcHideTooltipIcons()
end

-- Pins drawn within half a map point of each other overlap at any zoom, and only the top one can be
-- hovered. After the filters have run, pins within that distance of a group's first pin join it,
-- and each group gets a single pin standing in for them all. Measuring from the first pin, not any
-- member, stops a row of pins chaining into one group. qcPinDB itself keeps one pin per quest giver.
local QC_PIN_MERGE_DISTANCE = 0.5
local function qcMergeStackedPins(pins)
    local merged = {}
    local limit = QC_PIN_MERGE_DISTANCE * QC_PIN_MERGE_DISTANCE
    for _, pinData in ipairs(pins) do
        local stack
        for _, candidate in ipairs(merged) do
            local first = candidate[1]
            if (first[4] - pinData[4]) ^ 2 + (first[5] - pinData[5]) ^ 2 <= limit then
                stack = candidate
                break
            end
        end
        if stack then
            table.insert(stack, pinData)
        else
            table.insert(merged, {pinData})
        end
    end
    for i, stack in ipairs(merged) do
        if #stack == 1 then
            merged[i] = stack[1]
        else
            local first, quests = stack[1], {}
            for _, member in ipairs(stack) do
                for _, questId in ipairs(member[6]) do
                    table.insert(quests, questId)
                end
            end
            merged[i] = {first[1], first[2], first[3], first[4], first[5], quests, stack = stack}
        end
    end
    return merged
end

local function qcIsQuestInLog(questId)
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questId)
    return logIndex ~= nil and logIndex > 0
end

-- Decides one pin quest at a time; a pin is drawn while any of its quests is kept. A quest with no
-- data passes every check that reads the database.
local function qcBuildMapQuestFilter()
    local passesFilters = qcBuildQuestFilter(QC_MAP_FILTER)
    local hideNoData = (qcSettings.QC_M_HIDE_NODATA == 1)
    local hideCompleted = (qcSettings.QC_M_HIDE_COMPLETED == 1)
    local hideInProgress = (qcSettings.QC_M_HIDE_INPROGRESS == 1)
    local hideWarband = (qcSettings.QC_ML_HIDE_WARBANDS == 1)
    local hideUnavailable = (qcSettings.QC_ML_HIDE_UNAVAILABLE == 1)
    local activeHolidays = (qcSettings.QC_M_HIDE_SEASONAL == 1) and qcUpdateActiveHolidays()
    local playerLevel = (qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET == 1) and UnitLevel("player")

    local overrideCompleted = {}
    if hideCompleted or hideInProgress then
        overrideCompleted = simulateExclusiveCompletions(qcOverrideDailyExclusiveQuest)
        for questId in pairs(simulateExclusiveCompletions(qcOverrideWeeklyExclusiveQuest)) do
            overrideCompleted[questId] = true
        end
    end

    local function requirementsMet(questId, e)
        if (e[2] or 0) > playerLevel then return false end
        local prereqId = qcQuestPrereq[questId] or 0
        if prereqId > 0 and not C_QuestLog.IsQuestFlaggedCompleted(prereqId) then return false end
        local renown = qcRenownLevelRequirements[questId]
        if renown and C_MajorFactions.GetCurrentRenownLevel(renown[1]) < renown[2] then return false end
        return true
    end

    return function(questId)
        local e = qcQuestDatabase[questId]
        if not e and hideNoData then return false end
        if hideCompleted and (qcIsQuestCompleted(questId) or overrideCompleted[questId]) then return false end
        if hideInProgress and (qcIsQuestInLog(questId) or overrideCompleted[questId]) then return false end
        if hideWarband and qcIsQuestCompletedOnAccount(questId) then return false end
        if hideUnavailable and qcIsUnavailable(questId) then return false end
        if not e then return true end
        if not passesFilters(questId, e) then return false end
        -- A holiday value we don't know restricts nothing, like any other field with no data.
        local holiday = qcQuestHoliday[questId]
        if activeHolidays and holiday and qcKnownHolidayFlags[holiday] and BitBand(activeHolidays, holiday) == 0 then return false end
        if playerLevel and not requirementsMet(questId, e) then return false end
        return true
    end
end

qcMapDataProvider = CreateFromMixins(MapCanvasDataProviderMixin)

function qcMapDataProvider:RemoveAllData()
    if self:GetMap() then
        self:GetMap():RemoveAllPinsByTemplate("qcPinTemplate")
    end
end

function qcMapDataProvider:RefreshAllData()
    if not self:GetMap() then return end
    self:RemoveAllData()

    if qcSettings.QC_M_SHOW_ICONS == 0 then return end

    local UiMapID = self:GetMap():GetMapID()
    if not UiMapID or not qcPinDB[UiMapID] then return end

    local keepQuest = qcBuildMapQuestFilter()
    local pins = {}
    for _, pin in ipairs(qcPinDB[UiMapID]) do
        local quests = {}
        for _, questId in ipairs(pin[6]) do
            if keepQuest(questId) then TableInsert(quests, questId) end
        end
        if #quests > 0 then
            local pinData = {}
            for key, value in pairs(pin) do pinData[key] = value end
            pinData[6] = quests
            TableInsert(pins, pinData)
        end
    end

    qcRequestPinNpcNames(pins)
    for _, pinData in ipairs(qcMergeStackedPins(pins)) do
        self:GetMap():AcquirePin("qcPinTemplate", pinData)
    end
end

WorldMapFrame:AddDataProvider(qcMapDataProvider)

-- Ensure qcQuestCompletistUI_OnLoad is properly defined
function qcQuestCompletistUI_OnLoad(self)
    -- Your initialization code here
end
--[[ ##### MAP PINS END ##### ]]--

--[[ ##### INTERFACE OPTIONS START ##### ]]--

-- Initialize qcSettings if it is not already set
qcSettings = qcSettings or {}

-- Function to check and set default settings
function qcCheckSettings()
    qcSettings = qcSettings or {}

    if (qcSettings.SORT == nil) then
        qcSettings.SORT = 1
    end
    if (qcSettings.PURGED == nil) then
        qcSettings.PURGED = 0
    end
    if (qcSettings.QC_M_SHOW_ICONS == nil) then
        qcSettings.QC_M_SHOW_ICONS = 1
    end
    if (qcSettings.QC_M_HIDE_COMPLETED == nil) then
        qcSettings.QC_M_HIDE_COMPLETED = 0
    end
    if (qcSettings.QC_M_HIDE_LOWLEVEL == nil) then
        qcSettings.QC_M_HIDE_LOWLEVEL = 0
    end
    if (qcSettings.QC_M_HIDE_PROFESSION == nil) then
        qcSettings.QC_M_HIDE_PROFESSION = 1
    end
    if (qcSettings.QC_M_HIDE_SEASONAL == nil) then
        qcSettings.QC_M_HIDE_SEASONAL = 1
    end
    if (qcSettings.QC_M_HIDE_INPROGRESS == nil) then
        qcSettings.QC_M_HIDE_INPROGRESS = 0
    end
    if (qcSettings.QC_M_HIDE_NODATA == nil) then
        qcSettings.QC_M_HIDE_NODATA = 1
    end
    if (qcSettings.QC_L_HIDE_COMPLETED == nil) then
        qcSettings.QC_L_HIDE_COMPLETED = 0
    end
    if (qcSettings.QC_L_HIDE_LOWLEVEL == nil) then
        qcSettings.QC_L_HIDE_LOWLEVEL = 0
    end
    if (qcSettings.QC_L_HIDE_PROFESSION == nil) then
        qcSettings.QC_L_HIDE_PROFESSION = 1
    end
    if (qcSettings.QC_L_HIDE_DAILYQUEST == nil) then
        qcSettings.QC_L_HIDE_DAILYQUEST = 1
    end
    if (qcSettings.QC_L_HIDE_REPEATABLEQUEST == nil) then
        qcSettings.QC_L_HIDE_REPEATABLEQUEST = 1
    end
    if (qcSettings.QC_L_HIDE_WORLDQUEST == nil) then
        qcSettings.QC_L_HIDE_WORLDQUEST = 1
    end
    if (qcSettings.QC_ML_HIDE_FACTION == nil) then
        qcSettings.QC_ML_HIDE_FACTION = 1
    end
    if (qcSettings.QC_ML_HIDE_RACECLASS == nil) then
        qcSettings.QC_ML_HIDE_RACECLASS = 1
    end
    if (qcSettings.QC_ML_HIDE_COVENANTS == nil) then
        qcSettings.QC_ML_HIDE_COVENANTS = 1
    end
	if (qcSettings.QC_ML_HIDE_WARBANDS == nil) then
        qcSettings.QC_ML_HIDE_WARBANDS = 1
    end
    if (qcSettings.QC_ML_HIDE_UNAVAILABLE == nil) then
        qcSettings.QC_ML_HIDE_UNAVAILABLE = 1
    end
	if (qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET == nil) then
        qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET = 1
    end
    if (qcSettings.QC_SERVER_QUERY_COMPLETE == nil) then
        qcSettings.QC_SERVER_QUERY_COMPLETE = 0
    end
end

function qcApplySettings()
    if (qcSettings.QC_M_SHOW_ICONS == 0) then
        qcIO_M_SHOW_ICONS:SetChecked(false)
    else
        qcIO_M_SHOW_ICONS:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_COMPLETED == 0) then
        qcIO_M_HIDE_COMPLETED:SetChecked(false)
    else
        qcIO_M_HIDE_COMPLETED:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_LOWLEVEL == 0) then
        qcIO_M_HIDE_LOWLEVEL:SetChecked(false)
    else
        qcIO_M_HIDE_LOWLEVEL:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_PROFESSION == 0) then
        qcIO_M_HIDE_PROFESSION:SetChecked(false)
    else
        qcIO_M_HIDE_PROFESSION:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_SEASONAL == 0) then
        qcIO_M_HIDE_SEASONAL:SetChecked(false)
    else
        qcIO_M_HIDE_SEASONAL:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_INPROGRESS == 0) then
        qcIO_M_HIDE_INPROGRESS:SetChecked(false)
    else
        qcIO_M_HIDE_INPROGRESS:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_NODATA == 0) then
        qcIO_M_HIDE_NODATA:SetChecked(false)
    else
        qcIO_M_HIDE_NODATA:SetChecked(true)
    end
    if (qcSettings.QC_L_HIDE_COMPLETED == 0) then
        qcIO_L_HIDE_COMPLETED:SetChecked(false)
    else
        qcIO_L_HIDE_COMPLETED:SetChecked(true)
    end
    if (qcSettings.QC_L_HIDE_LOWLEVEL == 0) then
        qcIO_L_HIDE_LOWLEVEL:SetChecked(false)
    else
        qcIO_L_HIDE_LOWLEVEL:SetChecked(true)
    end
    if (qcSettings.QC_L_HIDE_PROFESSION == 0) then
        qcIO_L_HIDE_PROFESSION:SetChecked(false)
    else
        qcIO_L_HIDE_PROFESSION:SetChecked(true)
    end
    if (qcSettings.QC_L_HIDE_DAILYQUEST == 0) then
        qcIO_L_HIDE_DAILYQUEST:SetChecked(false)
    else
        qcIO_L_HIDE_DAILYQUEST:SetChecked(true)
    end
    if (qcSettings.QC_L_HIDE_REPEATABLEQUEST == 0) then
        qcIO_L_HIDE_REPEATABLEQUEST:SetChecked(false)
    else
        qcIO_L_HIDE_REPEATABLEQUEST:SetChecked(true)
    end

    if (qcSettings.QC_L_HIDE_WORLDQUEST == 0) then
        qcIO_L_HIDE_WORLDQUEST:SetChecked(false)
    else
        qcIO_L_HIDE_WORLDQUEST:SetChecked(true)
    end

    if (qcSettings.QC_ML_HIDE_COVENANTS == 0) then
        qcIO_ML_HIDE_COVENANTS:SetChecked(false)
    else
        qcIO_ML_HIDE_COVENANTS:SetChecked(true)
    end

    if (qcSettings.QC_ML_HIDE_WARBANDS == 0) then
        qcIO_ML_HIDE_WARBANDS:SetChecked(false)
    else
        qcIO_ML_HIDE_WARBANDS:SetChecked(true)
    end

    qcIO_ML_HIDE_UNAVAILABLE:SetChecked(qcSettings.QC_ML_HIDE_UNAVAILABLE ~= 0)

    if (qcSettings.QC_ML_HIDE_FACTION == 0) then
        qcIO_ML_HIDE_FACTION:SetChecked(false)
    else
        qcIO_ML_HIDE_FACTION:SetChecked(true)
    end
    if (qcSettings.QC_ML_HIDE_RACECLASS == 0) then
        qcIO_ML_HIDE_RACECLASS:SetChecked(false)
    else
        qcIO_ML_HIDE_RACECLASS:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET == 0) then
        qcIO_M_HIDE_REQUIREMENTSNOTMET:SetChecked(false)
    else
        qcIO_M_HIDE_REQUIREMENTSNOTMET:SetChecked(true)
    end
end

function qcWelcomeMessage()
    print(QCADDON_CHAT_TITLE .. qcL.WELCOME)
end

function qcInterfaceOptions_OnLoad(self)
    self.name = "Quest Completist"
    self.okay = function(self) qcInterfaceOptions_Okay(self) end
    self.cancel = function(self) qcInterfaceOptions_Cancel(self) end

    local category = Settings.RegisterCanvasLayoutCategory(self, self.name)
    Settings.RegisterAddOnCategory(category)
    self.category = category
end

function qcApplyFilterChange()
    qcRefreshQuestList()
    qcMapDataProvider:RefreshAllData()
end

function qcInterfaceOptions_Okay(self)
    qcApplyFilterChange()
end

function qcInterfaceOptions_Cancel(self)
    -- Do nothing for now
end

function qcInterfaceOptions_OnShow(self)
    local qcL = qcLocalize

    qcConfigTitle = self:CreateFontString("qcConfigTitle", "ARTWORK", "GameFontNormalLarge")
    qcConfigTitle:SetPoint("TOPLEFT", 16, -16)
    qcConfigTitle:SetText(qcL.CONFIGTITLE)

    qcConfigSubtitle = self:CreateFontString("qcConfigSubtitle", "ARTWORK", "GameFontHighlightSmall")
    qcConfigSubtitle:SetHeight(22) -- Height from top to put the checkbox in filters
    qcConfigSubtitle:SetPoint("TOPLEFT", qcConfigTitle, "BOTTOMLEFT", 0, -8)
    qcConfigSubtitle:SetPoint("RIGHT", self, -32, 0)
    qcConfigSubtitle:SetNonSpaceWrap(true)
    qcConfigSubtitle:SetJustifyH("LEFT")
    qcConfigSubtitle:SetJustifyV("TOP")
    qcConfigSubtitle:SetText(qcL.CONFIGSUBTITLE)

    qcMapFiltersTitle = self:CreateFontString("qcMapFiltersTitle", "ARTWORK", "GameFontNormal")
    qcMapFiltersTitle:SetPoint("TOPLEFT", qcConfigSubtitle, "BOTTOMLEFT", 16, -4)
    qcMapFiltersTitle:SetText(qcL.MAPFILTERS)

    qcIO_M_SHOW_ICONS = CreateFrame("CheckButton", "qcIO_M_SHOW_ICONS", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_SHOW_ICONS:SetPoint("TOPLEFT", qcMapFiltersTitle, "BOTTOMLEFT", 16, -6)
    _G[qcIO_M_SHOW_ICONS:GetName().."Text"]:SetText(qcL.SHOWMAPICONS)
    qcIO_M_SHOW_ICONS:SetScript("OnClick", function(self)
        if (qcIO_M_SHOW_ICONS:GetChecked() == false) then
            qcSettings.QC_M_SHOW_ICONS = 0
        else
            qcSettings.QC_M_SHOW_ICONS = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_M_HIDE_COMPLETED = CreateFrame("CheckButton", "qcIO_M_HIDE_COMPLETED", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_COMPLETED:SetPoint("TOPLEFT", qcIO_M_SHOW_ICONS, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_COMPLETED:GetName().."Text"]:SetText(qcL.HIDECOMPLETEDQUESTS)
    qcIO_M_HIDE_COMPLETED:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_COMPLETED:GetChecked() == false) then
            qcSettings.QC_M_HIDE_COMPLETED = 0
        else
            qcSettings.QC_M_HIDE_COMPLETED = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_M_HIDE_LOWLEVEL = CreateFrame("CheckButton", "qcIO_M_HIDE_LOWLEVEL", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_LOWLEVEL:SetPoint("TOPLEFT", qcIO_M_HIDE_COMPLETED, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_LOWLEVEL:GetName().."Text"]:SetText(qcL.HIDELOWLEVELQUESTS)
    qcIO_M_HIDE_LOWLEVEL:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_LOWLEVEL:GetChecked() == false) then
            qcSettings.QC_M_HIDE_LOWLEVEL = 0
        else
            qcSettings.QC_M_HIDE_LOWLEVEL = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_M_HIDE_PROFESSION = CreateFrame("CheckButton", "qcIO_M_HIDE_PROFESSION", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_PROFESSION:SetPoint("TOPLEFT", qcIO_M_HIDE_LOWLEVEL, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_PROFESSION:GetName().."Text"]:SetText(qcL.HIDEOTHERPROFESSIONQUESTS)
    qcIO_M_HIDE_PROFESSION:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_PROFESSION:GetChecked() == false) then
            qcSettings.QC_M_HIDE_PROFESSION = 0
        else
            qcSettings.QC_M_HIDE_PROFESSION = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_M_HIDE_SEASONAL = CreateFrame("CheckButton", "qcIO_M_HIDE_SEASONAL", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_SEASONAL:SetPoint("TOPLEFT", qcIO_M_HIDE_PROFESSION, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_SEASONAL:GetName().."Text"]:SetText(qcL.HIDENONACTIVESEASONALQUESTS)
    qcIO_M_HIDE_SEASONAL:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_SEASONAL:GetChecked() == false) then
            qcSettings.QC_M_HIDE_SEASONAL = 0
        else
            qcSettings.QC_M_HIDE_SEASONAL = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_M_HIDE_INPROGRESS = CreateFrame("CheckButton", "qcIO_M_HIDE_INPROGRESS", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_INPROGRESS:SetPoint("TOPLEFT", qcIO_M_HIDE_SEASONAL, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_INPROGRESS:GetName().."Text"]:SetText(qcL.HIDEINPROGRESSQUESTS)
    qcIO_M_HIDE_INPROGRESS:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_INPROGRESS:GetChecked() == false) then
            qcSettings.QC_M_HIDE_INPROGRESS = 0
        else
            qcSettings.QC_M_HIDE_INPROGRESS = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_M_HIDE_NODATA = CreateFrame("CheckButton", "qcIO_M_HIDE_NODATA", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_NODATA:SetPoint("TOPLEFT", qcIO_M_HIDE_INPROGRESS, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_NODATA:GetName().."Text"]:SetText(qcL.HIDENODATA)
    qcIO_M_HIDE_NODATA:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_NODATA:GetChecked() == false) then
            qcSettings.QC_M_HIDE_NODATA = 0
        else
            qcSettings.QC_M_HIDE_NODATA = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_M_HIDE_REQUIREMENTSNOTMET = CreateFrame("CheckButton", "qcIO_M_HIDE_REQUIREMENTSNOTMET", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_REQUIREMENTSNOTMET:SetPoint("TOPLEFT", qcIO_M_HIDE_NODATA, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_REQUIREMENTSNOTMET:GetName().."Text"]:SetText(qcL.HIDEREQUIREMENTSNOTMET)
    qcIO_M_HIDE_REQUIREMENTSNOTMET:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_REQUIREMENTSNOTMET:GetChecked() == false) then
            qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET = 0
        else
            qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET = 1
        end
    qcApplyFilterChange()
    end)	

    --- Quest List Filters Start ---
    qcListFiltersTitle = self:CreateFontString("qcListFiltersTitle", "ARTWORK", "GameFontNormal")
    qcListFiltersTitle:SetPoint("TOPLEFT", qcMapFiltersTitle, "TOPLEFT", 380, 0)
    qcListFiltersTitle:SetText(qcL.QUESTLISTFILTERS)

    qcIO_L_HIDE_COMPLETED = CreateFrame("CheckButton", "qcIO_L_HIDE_COMPLETED", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_L_HIDE_COMPLETED:SetPoint("TOPLEFT", qcListFiltersTitle, "BOTTOMLEFT", 16, -6)
    _G[qcIO_L_HIDE_COMPLETED:GetName().."Text"]:SetText(qcL.HIDECOMPLETEDQUESTS)
    qcIO_L_HIDE_COMPLETED:SetScript("OnClick", function(self)
        if (qcIO_L_HIDE_COMPLETED:GetChecked() == false) then
            qcSettings.QC_L_HIDE_COMPLETED = 0
        else
            qcSettings.QC_L_HIDE_COMPLETED = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_L_HIDE_LOWLEVEL = CreateFrame("CheckButton", "qcIO_L_HIDE_LOWLEVEL", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_L_HIDE_LOWLEVEL:SetPoint("TOPLEFT", qcIO_L_HIDE_COMPLETED, "BOTTOMLEFT", 0, 0)
    _G[qcIO_L_HIDE_LOWLEVEL:GetName().."Text"]:SetText(qcL.HIDELOWLEVELQUESTS)
    qcIO_L_HIDE_LOWLEVEL:SetScript("OnClick", function(self)
        if (qcIO_L_HIDE_LOWLEVEL:GetChecked() == false) then
            qcSettings.QC_L_HIDE_LOWLEVEL = 0
        else
            qcSettings.QC_L_HIDE_LOWLEVEL = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_L_HIDE_PROFESSION = CreateFrame("CheckButton", "qcIO_L_HIDE_PROFESSION", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_L_HIDE_PROFESSION:SetPoint("TOPLEFT", qcIO_L_HIDE_LOWLEVEL, "BOTTOMLEFT", 0, 0)
    _G[qcIO_L_HIDE_PROFESSION:GetName().."Text"]:SetText(qcL.HIDEOTHERPROFESSIONQUESTS)
    qcIO_L_HIDE_PROFESSION:SetScript("OnClick", function(self)
        if (qcIO_L_HIDE_PROFESSION:GetChecked() == false) then
            qcSettings.QC_L_HIDE_PROFESSION = 0
        else
            qcSettings.QC_L_HIDE_PROFESSION = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_L_HIDE_DAILYQUEST = CreateFrame("CheckButton", "qcIO_L_HIDE_DAILYQUEST", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_L_HIDE_DAILYQUEST:SetPoint("TOPLEFT", qcIO_L_HIDE_LOWLEVEL, "BOTTOMLEFT", 0, -25)
    _G[qcIO_L_HIDE_DAILYQUEST:GetName().."Text"]:SetText(qcL.HIDEDAILYQUEST .. COLOUR_DEATHKNIGHT .. " ")
    qcIO_L_HIDE_DAILYQUEST:SetScript("OnClick", function(self)
        if (qcIO_L_HIDE_DAILYQUEST:GetChecked() == false) then
            qcSettings.QC_L_HIDE_DAILYQUEST = 0
        else
            qcSettings.QC_L_HIDE_DAILYQUEST = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_L_HIDE_REPEATABLEQUEST = CreateFrame("CheckButton", "qcIO_L_HIDE_REPEATABLEQUEST", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_L_HIDE_REPEATABLEQUEST:SetPoint("TOPLEFT", qcIO_L_HIDE_LOWLEVEL, "BOTTOMLEFT", 0, -50)
    _G[qcIO_L_HIDE_REPEATABLEQUEST:GetName().."Text"]:SetText(qcL.HIDEREPEATABLEQUEST .. COLOUR_DEATHKNIGHT .. " ")
    qcIO_L_HIDE_REPEATABLEQUEST:SetScript("OnClick", function(self)
        if (qcIO_L_HIDE_REPEATABLEQUEST:GetChecked() == false) then
            qcSettings.QC_L_HIDE_REPEATABLEQUEST = 0
        else
            qcSettings.QC_L_HIDE_REPEATABLEQUEST = 1
        end
    qcApplyFilterChange()
    end)

	qcIO_L_HIDE_WORLDQUEST = CreateFrame("CheckButton", "qcIO_L_HIDE_WORLDQUEST", self, "InterfaceOptionsCheckButtonTemplate")
	qcIO_L_HIDE_WORLDQUEST:SetPoint("TOPLEFT", qcIO_L_HIDE_LOWLEVEL, "BOTTOMLEFT", 0, -75)
	_G[qcIO_L_HIDE_WORLDQUEST:GetName().."Text"]:SetText(qcL.HIDEWORLDQUEST .. COLOUR_DEATHKNIGHT .. " ")
	qcIO_L_HIDE_WORLDQUEST:SetScript("OnClick", function(self)
		if (qcIO_L_HIDE_WORLDQUEST:GetChecked() == false) then
			qcSettings.QC_L_HIDE_WORLDQUEST = 0
		else
			qcSettings.QC_L_HIDE_WORLDQUEST = 1
		end
	qcApplyFilterChange()
	end)

    qcCombinedFiltersTitle = self:CreateFontString("qcCombinedFiltersTitle", "ARTWORK", "GameFontNormal")
    qcCombinedFiltersTitle:SetPoint("TOPLEFT", qcConfigSubtitle, "BOTTOMLEFT", 16, -235)
    qcCombinedFiltersTitle:SetText(qcL.COMBINEDMAPANDQUESTFILTERS)

    qcIO_ML_HIDE_FACTION = CreateFrame("CheckButton", "qcIO_ML_HIDE_FACTION", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_ML_HIDE_FACTION:SetPoint("TOPLEFT", qcCombinedFiltersTitle, "BOTTOMLEFT", 16, -6)
    _G[qcIO_ML_HIDE_FACTION:GetName().."Text"]:SetText(qcL.HIDEOTHERFACTIONQUESTS)
    qcIO_ML_HIDE_FACTION:SetScript("OnClick", function(self)
        if (qcIO_ML_HIDE_FACTION:GetChecked() == false) then
            qcSettings.QC_ML_HIDE_FACTION = 0
        else
            qcSettings.QC_ML_HIDE_FACTION = 1
        end
    qcApplyFilterChange()
    end)

    qcIO_ML_HIDE_RACECLASS = CreateFrame("CheckButton", "qcIO_ML_HIDE_RACECLASS", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_ML_HIDE_RACECLASS:SetPoint("TOPLEFT", qcIO_ML_HIDE_FACTION, "BOTTOMLEFT", 0, 0)
    _G[qcIO_ML_HIDE_RACECLASS:GetName().."Text"]:SetText(qcL.HIDEOTHERRACEANDCLASSQUESTS)
    qcIO_ML_HIDE_RACECLASS:SetScript("OnClick", function(self)
        if (qcIO_ML_HIDE_RACECLASS:GetChecked() == false) then
            qcSettings.QC_ML_HIDE_RACECLASS = 0
        else
            qcSettings.QC_ML_HIDE_RACECLASS = 1
        end
    qcApplyFilterChange()
    end)

	qcIO_ML_HIDE_COVENANTS = CreateFrame("CheckButton", "qcIO_ML_HIDE_COVENANTS", self, "InterfaceOptionsCheckButtonTemplate")
	qcIO_ML_HIDE_COVENANTS:SetPoint("TOPLEFT", qcIO_ML_HIDE_FACTION, "BOTTOMLEFT", 0, -25)
	_G[qcIO_ML_HIDE_COVENANTS:GetName().."Text"]:SetText(qcL.HIDEOTHERCOVENANTQUESTS)
	qcIO_ML_HIDE_COVENANTS:SetScript("OnClick", function(self)
		if (qcIO_ML_HIDE_COVENANTS:GetChecked() == false) then
			qcSettings.QC_ML_HIDE_COVENANTS = 0
		else
			qcSettings.QC_ML_HIDE_COVENANTS = 1
		end
		qcApplyFilterChange()
	end)

	qcIO_ML_HIDE_WARBANDS = CreateFrame("CheckButton", "qcIO_ML_HIDE_WARBANDS", self, "InterfaceOptionsCheckButtonTemplate")
	qcIO_ML_HIDE_WARBANDS:SetPoint("TOPLEFT", qcIO_ML_HIDE_FACTION, "BOTTOMLEFT", 0, -50)
	_G[qcIO_ML_HIDE_WARBANDS:GetName().."Text"]:SetText(qcL.HIDEWARBANDS)
	qcIO_ML_HIDE_WARBANDS:SetScript("OnClick", function(self)
		if (qcIO_ML_HIDE_WARBANDS:GetChecked() == false) then
			qcSettings.QC_ML_HIDE_WARBANDS = 0
		else
			qcSettings.QC_ML_HIDE_WARBANDS = 1
		end
		qcApplyFilterChange()
	end)

	qcIO_ML_HIDE_UNAVAILABLE = CreateFrame("CheckButton", "qcIO_ML_HIDE_UNAVAILABLE", self, "InterfaceOptionsCheckButtonTemplate")
	qcIO_ML_HIDE_UNAVAILABLE:SetPoint("TOPLEFT", qcIO_ML_HIDE_FACTION, "BOTTOMLEFT", 0, -75)
	_G[qcIO_ML_HIDE_UNAVAILABLE:GetName().."Text"]:SetText(qcL.HIDEUNAVAILABLE)
	qcIO_ML_HIDE_UNAVAILABLE:SetScript("OnClick", function(self)
		qcSettings.QC_ML_HIDE_UNAVAILABLE = self:GetChecked() and 1 or 0
		qcApplyFilterChange()
	end)

    self:SetScript("OnShow", qcConfigRefresh)
    qcConfigRefresh(self)
end

function qcConfigRefresh(self)
    if not (self:IsVisible()) then return end
    -- Set control values here
    qcApplySettings()
end
-- Initialize settings when the addon is loaded
qcCheckSettings()

-- Accepting or turning in a quest flagged in qcUnavailableQuests.lua proves the flag wrong. It's kept
-- in qcFlaggedButSeen (account-wide) for the flag list's review, and mentioned in chat once.
local QC_SEEN_MESSAGE = {accepted = "UNAVAILABLEACCEPTED", ["turned in"] = "UNAVAILABLETURNEDIN"}
local function qcNoteUnavailableQuestSeen(questId, how)
	if not qcUnavailableQuests[questId] or qcFlaggedButSeen[questId] then return end
	qcFlaggedButSeen[questId] = {how = how, time = time(), build = select(4, GetBuildInfo())}
	print(QCADDON_CHAT_TITLE .. string.format(qcL[QC_SEEN_MESSAGE[how]], questId, qcQuestName(questId) or "?"))
end

-- Blizzard writes the quest giver's name into the quest frame's title each time it shows a quest
-- page; the quest's ID goes after it. The greeting page lists several quests and has no ID. A
-- missing function (renamed in a patch) costs only the ID, not the whole addon.
if QuestFrame_SetPortrait then
	hooksecurefunc("QuestFrame_SetPortrait", function()
		local questId = GetQuestID()
		if questId and questId ~= 0 then
			QuestFrame:SetTitle(string.format("%s [%d]", UnitName("questnpc") or "", questId))
		end
	end)
end

local function qcEventHandler(self, event, ...)
	if (event == "TOOLTIP_DATA_UPDATE") then
		qcNpcDataUpdated()
	elseif (event == "QUEST_DATA_LOAD_RESULT") then
		qcQuestDataArrived(...)
	elseif (event == "ADVENTURE_MAP_OPEN") then
		qcMapDataProvider:RefreshAllData()
	elseif (event == "UNIT_QUEST_LOG_CHANGED") then
		if (... == "player") then qcRequestRefresh(QC_REDRAW_ROWS) end
	elseif (event == "ZONE_CHANGED_NEW_AREA") then
		qcZoneChangedNewArea()		--				
	elseif (event == "ZONE_CHANGED") then
		qcZoneChangedNewArea()
	elseif (event == "QUEST_DETAIL") then
		local qcQuestID = GetQuestID()
		qcBreadcrumbChecks(qcQuestID)
		qcNewDataChecks(qcQuestID)
		qcMutuallyExclusiveChecks(qcQuestID)
	elseif (event == "QUEST_ACCEPTED") or (event == "QUEST_REMOVED") then
		if (event == "QUEST_ACCEPTED") then qcNoteUnavailableQuestSeen(..., "accepted") end
		qcRequestRefresh(QC_REDRAW_ROWS, true)
	elseif (event == "QUEST_PROGRESS") or (event == "QUEST_COMPLETE") then
		local qcQuestID = GetQuestID()
		if not (qcQuestID == 0) then
			qcBreadcrumbChecks(qcQuestID)
			qcNewDataChecks(qcQuestID)
			qcMutuallyExclusiveChecks(qcQuestID)
		end
	elseif (event == "QUEST_TURNED_IN") then
		local qcQuestID = ...
		qcNoteUnavailableQuestSeen(qcQuestID, "turned in")
		qcUpdateCompletedQuest(qcQuestID)
		qcUpdateMutuallyExclusiveCompletedQuest(qcQuestID)
		qcUpdateSkippedBreadcrumbQuest(qcQuestID)
		qcRequestRefresh(QC_REBUILD_LIST, true)
	elseif (event == "PLAYER_ENTERING_WORLD") then
			local isInitialLogin, isReloadingUi = ...
			if (isInitialLogin or isReloadingUi) then
				qcQuestQueryCompleted()
			end
			qcZoneChangedNewArea()
			qcSendNpcLoads()
	elseif (event == "ADDON_LOADED") then
		if (... == "QuestCompletist") then
			if not (qcCharacterCompletions) then qcCharacterCompletions = {} end
			qcMigrateCompletions()
			if not (qcWorkingDB) then qcWorkingDB = {} end
			if not (qcWorkingLog) then qcWorkingLog = {} end
			if not (qcFlaggedButSeen) then qcFlaggedButSeen = {} end
			qcCheckSettings()
			qcApplySettings()
			qcWelcomeMessage()
			qcZoneChangedNewArea()
			qcMenuSlider:SetValueStep(1);
			qcMenuSlider:SetObeyStepOnDrag(true);
		end
	end

end

function qcQuestCompletistUI_OnShow(self)
	if (qcSettings) then
		qcRefreshQuestList()
	end
end

function qcQuestCompletistUI_OnLoad(self)
--SetPortraitToTexture(self.qcPortrait, "Interface\\ICONS\\TRADE_ARCHAEOLOGY_DRAENEI_TOME")
	self.qcTitleText:SetText(string.format("Quest Completist v%s", QCADDON_VERSION))
	self.qcCategoryDropdownButton:SetText(GetText("CATEGORIES"))
	self.qcOptionsButton:SetText(GetText("FILTERS"))
	qcNewDataAlert.qcNewDataAlertText:SetText(qcL.NEWDATAALERT)
	self:RegisterForDrag("LeftButton")
	self:RegisterEvent("QUEST_COMPLETE")
	--self:RegisterEvent("QUEST_FINISHED") -- Cant be used for marking quest complette sinze it marks it done before its turned in 
	self:RegisterEvent("QUEST_TURNED_IN")
	self:RegisterEvent("QUEST_DETAIL")
	self:RegisterEvent("QUEST_PROGRESS")
	self:RegisterEvent("QUEST_ACCEPTED")
	self:RegisterEvent("QUEST_REMOVED")
	self:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA") -- 
	self:RegisterEvent("ZONE_CHANGED")
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("ADVENTURE_MAP_OPEN")
	self:RegisterEvent("QUEST_DATA_LOAD_RESULT")
	self:RegisterEvent("TOOLTIP_DATA_UPDATE")
	self:SetScript("OnEvent", qcEventHandler)
	qcQuestInformationTooltipSetup()
	qcMapTooltipSetup()
	qcToastTooltipSetup()
	qcNewDataAlertTooltipSetup()
	qcMutuallyExclusiveAlertTooltipSetup()
end