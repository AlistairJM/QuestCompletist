local TableInsert = table.insert;
local TableRemove = table.remove;
local StringFormat = string.format;
local ToString = tostring;
local BitBand = bit.band

local qcL = qcLocalize

local qcPins = {}

local qcCurrentCategoryID = 0
local qcCurrentCategoryQuestCount = 0
local qcCategoryQuests = {}

--[[ Vars ]]--
local qcCurrentScrollPosition = 1
local qcTooltipIndex = nil
local qcTooltipQuestId = nil
local qcQuestDataRequested = {}
-- Quests the server has already answered for. Without this the refresh below would request
-- again, get another QUEST_DATA_LOAD_RESULT, and refresh forever.
local qcQuestDataLoaded = {}
local qcMapTooltip = nil
local qcQuestInformationTooltip = nil
local qcToastTooltip = nil
local qcNewDataAlertTooltip = nil
local qcMutuallyExclusiveAlertTooltip = nil

--[[ Constants ]]--
local QCADDON_VERSION = 110.4
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
-- Classic has no IsWorldQuest, and no world quests either.
local function qcType128Icon(questId)
	if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questId) then
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
			local icon = qcRecurringQuestIcon(questId, quest[6])
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
}
local qcHolidayFlagByEventID = {}
local qcKnownHolidayFlags = {}
for _, holiday in ipairs(qcHolidays) do
	qcKnownHolidayFlags[holiday.flag] = true
	for _, eventID in ipairs(holiday.eventIDs) do qcHolidayFlagByEventID[eventID] = holiday.flag end
end

-- The holiday flags running now; nil until the calendar has loaded, which restricts nothing.
local qcActiveHolidays = nil
local qcCalendarLoaded = false

local function qcCalendarTimeValue(t)
	return (((t.year * 100 + t.month) * 100 + t.monthDay) * 100 + t.hour) * 100 + t.minute
end

local function qcFormatCalendarTime(t)
	return string.format("%04d-%02d-%02d %02d:%02d", t.year, t.month, t.monthDay, t.hour, t.minute)
end

-- The calendar counts months from the one it's showing, which its own frame moves.
local function qcCalendarMonthOffset(month, year)
	local shown = C_Calendar.GetMonthInfo(0)
	return (year - shown.year) * 12 + (month - shown.month)
end

local function qcReadActiveHolidays()
	local now = C_DateAndTime.GetCurrentCalendarTime()
	local offset = qcCalendarMonthOffset(now.month, now.year)
	local nowValue = qcCalendarTimeValue(now)
	local active = 0
	for index = 1, C_Calendar.GetNumDayEvents(offset, now.monthDay) do
		local event = C_Calendar.GetDayEvent(offset, now.monthDay, index)
		local flag = event and event.calendarType == "HOLIDAY" and qcHolidayFlagByEventID[event.eventID]
		if flag and qcCalendarTimeValue(event.startTime) <= nowValue and nowValue < qcCalendarTimeValue(event.endTime) then
			active = bit.bor(active, flag)
		end
	end
	return active
end

-- Keeps the last answer when the calendar can't be read, e.g. during chat lockdown.
local function qcUpdateActiveHolidays()
	if qcCalendarLoaded then
		local ok, active = pcall(qcReadActiveHolidays)
		if ok then qcActiveHolidays = active end
	end
	return qcActiveHolidays
end

local qcCalendarFrame = CreateFrame("Frame")
qcCalendarFrame:RegisterEvent("PLAYER_LOGIN")
qcCalendarFrame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
qcCalendarFrame:SetScript("OnEvent", function(self, event)
	if (event == "PLAYER_LOGIN") then
		C_Calendar.OpenCalendar()
		return
	end
	qcCalendarLoaded = true
	local before = qcActiveHolidays
	if (qcUpdateActiveHolidays() ~= before) then
		qcMapDataProvider:RefreshAllData()
	end
end)

-- /qc holidays: what the seasonal filter sees, and when each holiday next runs.
local function qcScanCalendarHolidays()
	local now = C_DateAndTime.GetCurrentCalendarTime()
	local firstOffset = qcCalendarMonthOffset(now.month, now.year)
	local nextByFlag, untracked = {}, {}
	for monthOffset = firstOffset, firstOffset + 12 do
		local firstDay = (monthOffset == firstOffset) and now.monthDay or 1
		for monthDay = firstDay, C_Calendar.GetMonthInfo(monthOffset).numDays do
			for index = 1, C_Calendar.GetNumDayEvents(monthOffset, monthDay) do
				local event = C_Calendar.GetDayEvent(monthOffset, monthDay, index)
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
	return nextByFlag, untracked
end

local function qcPrintHolidays()
	if not qcCalendarLoaded then
		print(QCADDON_CHAT_TITLE .. "The calendar hasn't loaded yet, so seasonal quests are all shown.")
		return
	end
	local active = qcUpdateActiveHolidays()
	local ok, nextByFlag, untracked = pcall(qcScanCalendarHolidays)
	if not ok then
		print(QCADDON_CHAT_TITLE .. "The calendar can't be read right now: " .. tostring(nextByFlag))
		return
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
BINDING_NAME_QCTOGGLEFRAME = "Toggle Frame";
SLASH_QUESTCOMPLETIST1 = "/qc"
SLASH_QUESTCOMPLETIST2 = "/questc"

SlashCmdList["QUESTCOMPLETIST"] = function(msg, editbox)
	if (strtrim(msg or ""):lower() == "holidays") then
		qcPrintHolidays()
		return
	end
	ShowUIPanel(qcQuestCompletistUI)
end

function qcCopyTable(qcTable)
	if not (qcTable) then return nil end
	if not (type(qcTable) == "table") then return nil end
	local qcNewTable = {}
	for qcKey, qcValue in pairs(qcTable) do
		if (type(qcValue) == "table") then
			qcNewTable[qcKey] = qcCopyTable(qcValue)
		else
			qcNewTable[qcKey] = qcValue
		end
	end
	return qcNewTable
end

function qcUpdateCurrentCategoryText(categoryId)
	qcQuestCompletistUI.qcSelectedCategory:SetText(qcCategoryName(categoryId) or "#")
end

local qcRecurringTypes = 2 + 4 + 128

local function qcIsRecurringQuest(questId)
	return bit.band(qcQuestDatabase[questId][6], qcRecurringTypes) ~= 0
end

local function qcUpdateMutuallyExclusiveCompletedQuest(qcQuestID)
	if (qcMutuallyExclusive[qcQuestID]) then
		for qcMutuallyExclusiveIndex, qcMutuallyExclusiveEntry in pairs(qcMutuallyExclusive[qcQuestID]) do
			if (qcQuestDatabase[qcMutuallyExclusiveEntry]) and not qcIsRecurringQuest(qcMutuallyExclusiveEntry) then
				qcCompletedQuests[qcMutuallyExclusiveEntry] = {["C"]=1}
			end
		end
	end
end

local function qcUpdateSkippedBreadcrumbQuest(qcQuestID)
	if (qcBreadcrumbQuests[qcQuestID]) then
		for qcBreadcrumbIndex, qcBreadcrumbEntry in pairs(qcBreadcrumbQuests[qcQuestID]) do
			if (qcQuestDatabase[qcBreadcrumbEntry]) and not qcIsRecurringQuest(qcBreadcrumbEntry) then
				qcCompletedQuests[qcBreadcrumbEntry] = {["C"]=1}
			end
		end
	end
end

local qcCategoryIndex = nil
local qcQuestNameUpperCache = nil

local function qcBuildQuestIndexes()
    qcCategoryIndex = {}
    qcQuestNameUpperCache = {}
    for questId, e in pairs(qcQuestDatabase) do
        local categoryId = e[5]
        if not qcCategoryIndex[categoryId] then
            qcCategoryIndex[categoryId] = {}
        end
        table.insert(qcCategoryIndex[categoryId], e)
        qcQuestNameUpperCache[questId] = string.upper(e[2])
    end
end

local function qcIsQuestCompleted(questId)
	local record = qcCompletedQuests[questId]
	return record ~= nil and (record["C"] == 1 or record["C"] == 2)
end

local function qcIsQuestCompletedOnAccount(questId)
	return C_QuestLog.IsQuestFlaggedCompletedOnAccount ~= nil and C_QuestLog.IsQuestFlaggedCompletedOnAccount(questId)
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

-- Every quest list filter except the two that hide a quest for being done. The completion counter
-- shares it, so the counter's total is always the quests the list can show.
local function qcBuildQuestFilter()
	local BitBand = bit.band
	local stringUpper = string.upper

	local hiddenTypes = 0
	if (qcSettings.QC_L_HIDE_DAILYQUEST == 1) then hiddenTypes = hiddenTypes + 4 end
	if (qcSettings.QC_L_HIDE_REPEATABLEQUEST == 1) then hiddenTypes = hiddenTypes + 2 end
	if (qcSettings.QC_L_HIDE_WORLDQUEST == 1) then hiddenTypes = hiddenTypes + 128 end

	local greenCutoff
	if (qcSettings.QC_L_HIDE_LOWLEVEL == 1) then
		greenCutoff = UnitLevel("player") - UnitQuestTrivialLevelRange("player")
	end

	local professionBitmask
	if (qcSettings.QC_L_HIDE_PROFESSION == 1) then
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
	if (qcSettings.QC_ML_HIDE_COVENANTS == 1) and C_Covenants and C_Covenants.GetActiveCovenantID then
		covenantBit = qcCovenantsBits[C_Covenants.GetActiveCovenantID()] or 0
	end

	return function(e)
		if (BitBand(e[6], hiddenTypes) ~= 0) then return false end
		if greenCutoff and (e[3] or 0) < greenCutoff then return false end
		if professionBitmask and e[10] ~= 0 and BitBand(e[10], professionBitmask) == 0 then return false end
		if factionFlag and not qcMaskAllows(e[7], factionFlag) then return false end
		if raceFlag and not qcMaskAllows(e[8], raceFlag) then return false end
		if classFlag and not qcMaskAllows(e[9], classFlag) then return false end
		if covenantBit and e[12] ~= 0 and BitBand(e[12], covenantBit) == 0 then return false end
		return true
	end
end

local function qcGetCategoryQuests(categoryId, searchText)
    local tableInsert = table.insert
    local tableSort = table.sort
    local holdingTable = {}
    wipe(qcCategoryQuests)

    if not qcCategoryIndex then
        qcBuildQuestIndexes()
    end

    if (searchText) then
        local stringfind = string.find
        for i, e in pairs(qcQuestDatabase) do
            if (stringfind(qcQuestNameUpperCache[e[1]], searchText, 1, true)) then
                tableInsert(holdingTable, e)
            end
        end
        qcCategoryQuests = qcCopyTable(holdingTable)
        return nil
    end

    local passesFilters = qcBuildQuestFilter()
    local hideCompleted = (qcSettings.QC_L_HIDE_COMPLETED == 1)
    local hideWarband = (qcSettings.QC_ML_HIDE_WARBANDS == 1)
    for _, e in ipairs(qcCategoryIndex[categoryId] or {}) do
        local questId = e[1]
        if passesFilters(e)
            and not (hideCompleted and qcIsQuestCompleted(questId))
            and not (hideWarband and qcIsQuestCompletedOnAccount(questId)) then
            tableInsert(holdingTable, e)
        end
    end
    qcCategoryQuests = qcCopyTable(holdingTable)

    -- Sorting quests. An entry with no level sorts as 0 rather than erroring out of the sort and
	-- leaving the list empty.
	local function byLevel(a,b)
		local levelA, levelB = a[3] or 0, b[3] or 0
		return (levelA<levelB or (levelA == levelB and a[2]<b[2]))
	end
	if (qcSettings.SORT == 1) then
		tableSort(qcCategoryQuests,byLevel)
	elseif (qcSettings.SORT == 2) then
		tableSort(qcCategoryQuests,function(a,b) return a[2]<b[2] end)
	else
		tableSort(qcCategoryQuests,byLevel)
	end
end

--Beta Reset Daily and Weekly Start
-- Initialize saved variables if needed
QC_LastDailyReset = QC_LastDailyReset or 0
QC_LastWeeklyReset = QC_LastWeeklyReset or 0
qcCompletedQuests = qcCompletedQuests or {}

-- Clears completions of a given type flag (4 = daily, 128 = weekly); unattainable marks (C = 2) never expire
local function ResetQCCompletedQuests(flag)
    for questId, record in pairs(qcCompletedQuests) do
        local questData = qcQuestDatabase[questId]
        if questData and record["C"] ~= 2 and bit.band(questData[6], flag) ~= 0 then
            qcCompletedQuests[questId] = nil
        end
    end
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
                local isCompleted = qcCompletedQuests[qID] and (qcCompletedQuests[qID]["C"] == 1 or qcCompletedQuests[qID]["C"] == 2)
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
-- turning on "hide completed" would pin the counter at 0/N.
function qcGetZoneCompletionStats(areaId)
	local total = 0
	local completed = 0

	if not qcCategoryIndex then
		qcBuildQuestIndexes()
	end

	local passesFilters = qcBuildQuestFilter()
	for _, questEntry in ipairs(qcCategoryIndex[areaId] or {}) do
		if passesFilters(questEntry) then
			local questId = questEntry[1]
			total = total + 1
			if qcIsQuestCompleted(questId) or qcIsQuestCompletedOnAccount(questId) then
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
		qcQuestCompletistUI.qcSearchBox:SetText("")
		qcCurrentCategoryID = categoryId
		qcUpdateCurrentCategoryText(categoryId)
		qcGetCategoryQuests(categoryId)
		qcCurrentCategoryQuestCount = (#qcCategoryQuests)
		if (qcCurrentCategoryQuestCount < 16) then
			qcMenuSlider:SetMinMaxValues(1, 1)
		else
			qcMenuSlider:SetMinMaxValues(1, qcCurrentCategoryQuestCount - 15)
		end
		qcMenuSlider:SetValue(startIndex)

		local completedInZone, totalInZone = qcGetZoneCompletionStats(categoryId)
		local completionPercent = (totalInZone > 0) and math.floor((completedInZone / totalInZone) * 100) or 0
		qcQuestCompletistUI.qcCurrentCategoryQuestCount:SetText(stringFormat("%d/%d Complete (%d%%)", completedInZone, totalInZone, completionPercent))
	else
		if (searchText) then
			qcGetCategoryQuests(nil, searchText)
			qcCurrentCategoryQuestCount = (#qcCategoryQuests)
			qcQuestCompletistUI.qcSelectedCategory:SetText("Search Results")
			if (qcCurrentCategoryQuestCount < 16) then
				qcMenuSlider:SetMinMaxValues(1, 1)
			else
				qcMenuSlider:SetMinMaxValues(1, qcCurrentCategoryQuestCount - 15)
			end
			qcMenuSlider:SetValue(startIndex)
			qcQuestCompletistUI.qcCurrentCategoryQuestCount:SetText(stringFormat("%d Quests Found", qcCurrentCategoryQuestCount))
		end
	end
	for i = 1, 16 do
		local offset = ((i + startIndex) - 1)
		local questRecord = _G["qcMenuButton" .. i]
		if (qcCurrentCategoryQuestCount >= offset) then
			local e = qcCategoryQuests[offset]
			local questId = e[1]
			local questType = e[6]
			local questFaction = e[7]
			questRecord.QuestName:SetText(stringFormat("[%d] %s",e[3],e[2]))
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
				qcSetIcon(questRecord.QuestIcon, qcProfessionIcon(e[10]))
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
			if (qcCompletedQuests[questId]) then
				if not ((questType == 2) or (questType == 4) or (questType == 128)) then
					if (qcCompletedQuests[questId]["C"] == 1) then
						qcSetIcon(questRecord.QuestIcon, QC_ICON_COMPLETE)
						questRecord.QuestName:SetTextColor(0.0, 1.0, 0.0, 1.0)
					elseif (qcCompletedQuests[questId]["C"] == 2) then
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

-- Search function start

-- Function to handle when the search box gains focus
function qcSearchBox_OnEditFocusGained(self)
    if self:GetText() == "Search" then
        self:SetText("")
        self:SetTextColor(1, 1, 1)  -- Set text color to normal
    end
    if self.Instructions then
        self.Instructions:SetText("Search")
    end
end

-- Function to handle when the search box loses focus
function qcSearchBox_OnEditFocusLost(self)
    if self:GetText() == "" then
        self:SetText("Search")
        self:SetTextColor(0.5, 0.5, 0.5)  -- Set text color to grey to indicate placeholder
        if self.Instructions then
            self.Instructions:SetText("Search")
        end
    end

    local searchText = string.upper(self:GetText())
    if not (searchText == "") and searchText ~= "SEARCH" then
        qcUpdateQuestList(nil, 1, searchText)
    else
        qcUpdateQuestList(qcCurrentCategoryID, 1)
    end
end

-- Function to handle when the text in the search box changes
function qcSearchBox_OnTextChanged(self, userInput)
    if userInput == true then
        local searchText = self:GetText()
        self.Instructions:SetText("")
        -- Clear placeholder text when the user starts typing
        if searchText == "S" or searchText == "s" or searchText:sub(1, 1):upper() ~= "S" then
            if self:GetText() == "Search" then
                self:SetText("")
                self:SetTextColor(1, 1, 1)  -- Set text color to normal
                searchText = ""
            end
        end

        searchText = string.upper(self:GetText())
        if not (searchText == "") and searchText ~= "SEARCH" then
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
            qcSearchBox:SetText("Search")
            qcSearchBox:SetTextColor(0.5, 0.5, 0.5)
            if qcSearchBox.Instructions then
                qcSearchBox.Instructions:SetText("Search")
            end
            qcSearchBox:HookScript("OnEditFocusGained", qcSearchBox_OnEditFocusGained)
            qcSearchBox:HookScript("OnEditFocusLost", qcSearchBox_OnEditFocusLost)
            qcSearchBox:HookScript("OnTextChanged", qcSearchBox_OnTextChanged)

            -- Create wipe button
            local wipeButton = CreateFrame("Button", nil, qcSearchBox, "UIPanelCloseButton")
            wipeButton:SetSize(20, 20) -- small size
            wipeButton:SetPoint("RIGHT", qcSearchBox, "RIGHT", 20, 0) -- adjust offset as needed
            wipeButton:SetScript("OnClick", function()
                qcSearchBox:SetText("Search")
                qcSearchBox:SetTextColor(0.5, 0.5, 0.5)
                if qcSearchBox.Instructions then
                    qcSearchBox.Instructions:SetText("Search")
                end
                qcUpdateQuestList(qcCurrentCategoryID, 1)
            end)
            wipeButton:Hide() -- hidden until there’s text

            -- Show/hide the wipe button depending on text content
            qcSearchBox:HookScript("OnTextChanged", function(self)
                if self:GetText() ~= "" and self:GetText() ~= "Search" then
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
	local qcIsNew = (qcCompletedQuests[qcIndex] == nil)
	qcCompletedQuests[qcIndex] = {["C"]=1}
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

local function qcGetCompletedQuestIDs()
	if (C_QuestLog.GetAllCompletedQuestIDs) then
		return C_QuestLog.GetAllCompletedQuestIDs()
	end
	if (GetQuestsCompleted) then
		local qcCompletedIDs = {}
		for qcQuestID in pairs(GetQuestsCompleted()) do
			qcCompletedIDs[#qcCompletedIDs + 1] = qcQuestID
		end
		return qcCompletedIDs
	end
end

local function qcQuestQueryCompleted(qcAlwaysReport)

	local qcFound = 0
	local qcNewFlagged = 0
	local qcCompletedIDs = qcGetCompletedQuestIDs()

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
		qcUpdateQuestList(nil,qcMenuSlider:GetValue())
	end
	if (qcNewFlagged > 0) or (qcAlwaysReport) then
		print(string.format("%sThe server reports %d completed quest(s) known to Quest Completist, %d of them newly marked as completed.",QCADDON_CHAT_TITLE,qcFound,qcNewFlagged))
	end

end

local function qcClearUpdateCache()
	wipe(qcCompletedQuests)
	print(string.format("%sCache Cleared.",QCADDON_CHAT_TITLE))
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
        print(string.format("%s%s", QCADDON_CHAT_TITLE, "Clearing your update Cache..."))
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

local function qcZoneChangedNewArea() -- *
--	SetMapToCurrentZone()
	local id = C_Map.GetBestMapForUnit("player")
	if (qcAreaIDToCategoryID[id]) then
		qcCurrentCategoryID = qcAreaIDToCategoryID[id]
		qcUpdateQuestList(qcCurrentCategoryID,1)
	end
end

-- Start Tooltip when mouse over quest name
-- Ensure the necessary tables from qcQuest.lua are loaded
local qcAreaIDToCategoryID = qcAreaIDToCategoryID or {} -- Maps zone ID to internal category ID
local qcQuestCategories = qcQuestCategories or {} -- Maps internal category ID to zone name

-- Category names come from the client where qcCategoryUiMapID knows a map for them, so they need
-- no translation of ours. Everything else falls back to qcLocalize, then to the English name in
-- qcQuestCategories.
local qcCategoryLocaleKey = {}
for _, categoryData in ipairs(qcQuestCategories) do
	qcCategoryLocaleKey[categoryData[1]] = (categoryData[2]:gsub("[^%a%d]", "")):upper()
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
			parts[#parts + 1] = qcClientName(source[i])
			if (not parts[#parts]) then return nil end
		end
		name = string.format(id, unpack(parts))
	end
	if (type(name) == "string" and name ~= "") then return name end
end

-- The category's name as the client has it, in the player's language, or nil. Classic lacks some
-- of these APIs, and the pcall lets those categories fall back to our own strings.
function qcClientCategoryName(categoryId)
	local uiMapId = qcCategoryUiMapID and qcCategoryUiMapID[categoryId]
	if (uiMapId) then
		local ok, name = pcall(qcClientName, {"map", uiMapId})
		if (ok and name) then return name end
	end
	local source = qcCategoryClientName and qcCategoryClientName[categoryId]
	if (source) then
		local ok, name = pcall(qcClientName, source)
		if (ok and name) then return name end
	end
end

-- A menu heading's text, from the client where qcMenu says how (clientName), keeping its indent.
function qcMenuHeadingText(item)
	if (item.clientName and item.text) then
		local ok, name = pcall(qcClientName, item.clientName)
		if (ok and name) then return item.text:match("^%s*") .. name end
	end
	return item.text
end

function qcCategoryName(categoryId)
	local clientName = qcClientCategoryName(categoryId)
	if (clientName) then return clientName end

	local key = qcCategoryLocaleKey[categoryId]
	if (key and qcL[key]) then return qcL[key] end

	for _, categoryData in ipairs(qcQuestCategories) do
		if (categoryData[1] == categoryId) then return categoryData[2] end
	end

	return nil
end

-- Function to get the zone name from a zone ID with enhanced handling for array-style lookup
function GetZoneNameFromZoneID(zoneId)
    -- First, check if the zoneId is present in qcAreaIDToCategoryID
    local categoryID = qcAreaIDToCategoryID[zoneId]
    if not categoryID then
        -- Fall back to a default message if the mapping is missing
        return "Unknown Zone (Invalid Area ID)"
    end

    local zoneName = qcCategoryName(categoryID)

    if not zoneName or zoneName == "" then
        -- Handle cases where the zone name is missing or empty
        return "Unknown Zone (No Zone Name)"
    end

    -- Return the valid zone name if all checks passed
    return zoneName
end

local QC_STORYLINE_WINDOW = 15


-- Function to update the quest tooltip
function qcUpdateTooltip(index)
    local stringFormat = string.format
    local questId = _G["qcMenuButton" .. index].QuestID
    local att_HookBackup

    if questId then
        -- SetHyperlink below renders nothing until the server has sent the quest's data, so ask
        -- for it and redraw when it lands (see QUEST_DATA_LOAD_RESULT in qcEventHandler).
        qcTooltipIndex = index
        qcTooltipQuestId = questId
        if (C_QuestLog and C_QuestLog.RequestLoadQuestByID and not qcQuestDataLoaded[questId] and not qcQuestDataRequested[questId]) then
            qcQuestDataRequested[questId] = true
            C_QuestLog.RequestLoadQuestByID(questId)
        end

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
            qcQuestInformationTooltip:AddLine(qcQuestDatabase[questId][2], 1, 1, 1)
            qcQuestInformationTooltip:AddLine("Quest details not available from the game", 0.5, 0.5, 0.5)
        end
        qcQuestInformationTooltip:AddLine(" ")
        qcQuestInformationTooltip:AddDoubleLine("Quest ID:", stringFormat("|cFF69CCF0%d|r", questId))
        qcQuestInformationTooltip:AddLine(" ")

        -- Restore ATT hook if we temporarily replaced it
        if att_HookBackup then
            GameTooltip.OnTooltipSetQuest = att_HookBackup
            att_HookBackup = nil
        end

        -- Storyline information. qcQuestLines holds each storyline's quests in Blizzard's order;
        -- a whole-zone storyline runs to 200+ quests, so only a window around this one is shown.
        local storylineId = qcQuestDatabase[questId][13]
        local storyline = storylineId and qcQuestLines[storylineId]
        if storyline then
            -- Older zones share one storyline between both factions; follow the list's faction filter.
            local factionFlag = (qcSettings.QC_ML_HIDE_FACTION == 1) and qcFactionBits[string.upper(UnitFactionGroup("player") or "")]
            local lineQuests = {}
            for _, lineQuestId in ipairs(storyline.quests) do
                local lineQuest = qcQuestDatabase[lineQuestId]
                if lineQuest and (lineQuestId == questId or not factionFlag or qcMaskAllows(lineQuest[7], factionFlag)) then
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
            qcQuestInformationTooltip:AddDoubleLine("Storyline:", stringFormat("%s%s|r |cFF808080(%d of %d)|r", COLOUR_HUNTER, storyline.name, position, #lineQuests))
            qcQuestInformationTooltip:AddLine(" ")

            local first = math.max(1, position - math.floor(QC_STORYLINE_WINDOW / 2))
            local last = math.min(#lineQuests, first + QC_STORYLINE_WINDOW - 1)
            first = math.max(1, last - QC_STORYLINE_WINDOW + 1)
            if first > 1 then
                qcQuestInformationTooltip:AddLine(stringFormat("|cFF808080   ... %d earlier|r", first - 1))
            end
            for i = first, last do
                local lineQuestId = lineQuests[i]
                local questData = qcQuestDatabase[lineQuestId]
                if questData then
                    local questStatus
                    if C_QuestLog.IsOnQuest(lineQuestId) then
                        questStatus = "|cFFFFFF00You are on this quest|r"
                    else
                        questStatus = C_QuestLog.IsQuestFlaggedCompleted(lineQuestId) and "|cFF00FF00Completed|r" or "|cFFFF0000Not Completed|r"
                    end
                    qcQuestInformationTooltip:AddDoubleLine(((lineQuestId == questId) and " > " or " - ") .. questData[2], questStatus)
                end
            end
            if last < #lineQuests then
                qcQuestInformationTooltip:AddLine(stringFormat("|cFF808080   ... %d more|r", #lineQuests - last))
            end

            qcQuestInformationTooltip:AddLine(" ")
        end

        -- Prerequisite quest logic
        local prereqQuestId = qcQuestDatabase[questId][14]
        if prereqQuestId and prereqQuestId ~= 0 then
            local prereqQuestInfo = qcQuestDatabase[prereqQuestId]
            local prereqQuestName = prereqQuestInfo and prereqQuestInfo[2] or "Unknown Quest"
            local prereqQuestStatus = C_QuestLog.IsQuestFlaggedCompleted(prereqQuestId) and "|cFF00FF00Completed|r" or "|cFFFF0000Not Completed|r"
            qcQuestInformationTooltip:AddDoubleLine("Prerequired Completed Quest:", string.format("%s - %s", prereqQuestName, prereqQuestStatus))
            qcQuestInformationTooltip:AddLine(" ")
        end
		-- Renown and Faction requirements Start
        -- Only handle renown/major faction requirements where the Major Factions API exists
        if C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel then
            local renownInfo = qcRenownLevelRequirements[questId]

            if renownInfo then
                if type(renownInfo) == "table" then
                    local factionId = renownInfo[1]
                    local requiredRenownLevel = renownInfo[2]
                    local factionName = qcFactions[factionId] or "Unknown Faction"
                    local currentRenownLevel = C_MajorFactions.GetCurrentRenownLevel(factionId)

                    qcQuestInformationTooltip:AddDoubleLine("Required Faction:", string.format("%s%s", COLOUR_DRUID, factionName))

                    if currentRenownLevel then
                        if currentRenownLevel >= requiredRenownLevel then
                            qcQuestInformationTooltip:AddDoubleLine("Required Renown Level:", string.format("|cFF00FF00%d (Requirement Fulfilled)|r", requiredRenownLevel))
                        else
                            qcQuestInformationTooltip:AddDoubleLine("Required Renown Level:", string.format("|cFFFF0000%d (Requirement Not Fulfilled)|r", requiredRenownLevel))
                        end
                    else
                        qcQuestInformationTooltip:AddDoubleLine("Required Renown Level:", "|cFFFF0000Data Unavailable|r")
                    end
                elseif type(renownInfo) == "number" then
                    local factionName = qcFactions[renownInfo] or "Unknown Faction"
                    qcQuestInformationTooltip:AddDoubleLine("Required Faction:", string.format("%s%s", COLOUR_DRUID, factionName))
                end

                qcQuestInformationTooltip:AddLine(" ")
            end
        end
		-- Renown and Faction requirements End

        -- Quest Giver Information from qcPinDB.lua
        local questGiverInfoFound = false
        for zoneId, npcs in pairs(qcPinDB) do
            -- Retrieve the zone name for the current zone ID
            local zoneName = GetZoneNameFromZoneID(zoneId)

            for _, npcData in ipairs(npcs) do
                local npcId = npcData[3]
                local npcName = npcData[4]
                local xCoord = npcData[5]
                local yCoord = npcData[6]
                local quests = npcData[7]

                if type(quests) == "table" then
                    for _, quest in ipairs(quests) do
                        if quest == questId then
                            qcQuestInformationTooltip:AddDoubleLine(
                                "Quest Giver:",
                                string.format("%s (%s, %.1f, %.1f)", npcName or "Unknown NPC", zoneName, xCoord or 0, yCoord or 0)
                            )
                            questGiverInfoFound = true
                            break
                        end
                    end
                end

                if questGiverInfoFound then break end
            end

            if questGiverInfoFound then break end
        end

        -- Handle case where quest giver information isn't found
        if not questGiverInfoFound then
            qcQuestInformationTooltip:AddDoubleLine("Quest Giver:", "Unknown or Auto-Accepted Quest")
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
                    "  " .. (qcFactions[factionId] or tostring(factionId)),
                    stringFormat("%s%d rep", COLOUR_DRUID, reputationEntries[factionId])
                )
            end
        end

        -- Make sure the main tooltip is shown
        qcQuestInformationTooltip:Show()
    end
end

-- End Tooltip when mouse over quest name


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
	for mapId, pins in pairs(qcPinDB) do
		for _, pin in ipairs(pins) do
			for _, pinQuestId in ipairs(pin[7] or {}) do
				if pinQuestId == questId then
					if mapId == playerMap and px then
						local dist = (pin[5] - px) ^ 2 + (pin[6] - py) ^ 2
						if not bestOnPlayerMap or dist < bestDist then
							bestMap, bestPin, bestDist, bestOnPlayerMap = mapId, pin, dist, true
						end
					elseif not bestOnPlayerMap and (not bestMap or mapId < bestMap) then
						bestMap, bestPin = mapId, pin
					end
					break
				end
			end
		end
	end
	return bestMap, bestPin
end

function qcQuestClick(qcButtonIndex)
	local qcQuestID = _G["qcMenuButton" .. qcButtonIndex].QuestID
	if (IsLeftShiftKeyDown()) then --[[ User wants to toggle the completed status of a quest ]]--
	  --print(string.format("%sLeft shift key is down",QCADDON_CHAT_TITLE))
		if (qcCompletedQuests[qcQuestID] == nil) then
			qcCompletedQuests[qcQuestID] = {["C"] = 1}
		else
			if (qcCompletedQuests[qcQuestID]["C"] == nil) then
				qcCompletedQuests[qcQuestID]["C"] = 1
			else
				if (qcCompletedQuests[qcQuestID]["C"] == 1) then
					qcCompletedQuests[qcQuestID]["C"] = 0
				elseif (qcCompletedQuests[qcQuestID]["C"] == 0) then
					qcCompletedQuests[qcQuestID]["C"] = 1
				elseif (qcCompletedQuests[qcQuestID]["C"] == 2) then
					qcCompletedQuests[qcQuestID]["C"] = 1
				end
			end
		end
	elseif (IsLeftAltKeyDown()) then --[[ User wants to toggle the unattainable status of a quest ]]--
	  --print(string.format("%sLeft alt key is down",QCADDON_CHAT_TITLE))
		if (qcCompletedQuests[qcQuestID] == nil) then
			qcCompletedQuests[qcQuestID] = {["C"] = 2}
		else
			if (qcCompletedQuests[qcQuestID]["C"] == nil) then
				qcCompletedQuests[qcQuestID]["C"] = 2
			else
				if (qcCompletedQuests[qcQuestID]["C"] == 2) then
					qcCompletedQuests[qcQuestID]["C"] = 0
				elseif (qcCompletedQuests[qcQuestID]["C"] == 0) then
					qcCompletedQuests[qcQuestID]["C"] = 2
				elseif (qcCompletedQuests[qcQuestID]["C"] == 1) then
					qcCompletedQuests[qcQuestID]["C"] = 2
				end
			end
		end
  else
		-- print(string.format("%sLooking for Tom Tom.",QCADDON_CHAT_TITLE))
    if (C_AddOns.IsAddOnLoaded('TomTom')) then
        local mapId, pin = qcFindPinForQuest(qcQuestID)
        if (mapId) then
            local quest = qcQuestDatabase[qcQuestID]
            TomTom:AddWaypoint(mapId, pin[5] / 100, pin[6] / 100, {title = pin[4] or (quest and quest[2])})
            TomTom:SetClosestWaypoint()
        end
    end
end

  --print(string.format("%sUpdating quest list",QCADDON_CHAT_TITLE))
	qcUpdateQuestList(nil, qcMenuSlider:GetValue())

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
	if not (qcCompletedQuests[questId]) then qcCompletedQuests[questId] = {["C"]=1} end
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
		if (bit.band(factionFlag,qcQuestDatabase[questId][7]) == 0) then
			qcNewDataAlert.Faction = true
		end
		raceFlag = qcRaceBits[string.upper(playerRace)]
		if (bit.band(raceFlag,qcQuestDatabase[questId][8]) == 0) then
			qcNewDataAlert.Race = true
		end
		classFlag = qcClassBits[string.upper(playerClass)]
		if (bit.band(classFlag,qcQuestDatabase[questId][9]) == 0) then
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
	qcNewDataAlertTooltip:AddLine(COLOUR_HUNTER .. "Quest Completist was not aware of the following information. Please help improve the accuracy of the addon by submiting a post or new issue over at curse", nil, nil, nil, true)
	if (qcNewDataAlert.New) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. " - Quest does not exist in the database.", nil, nil, nil, true)
		qcNewDataAlertTooltip:Show()
	end
	if (qcNewDataAlert.Faction) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. " - QC was not aware your FACTION could complete this quest.", nil, nil, nil, true)
	end
	if (qcNewDataAlert.Race) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. " - QC was not aware your RACE could complete this quest.", nil, nil, nil, true)
	end
	if (qcNewDataAlert.Class) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. " - QC was not aware your CLASS could complete this quest.", nil, nil, nil, true)
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
			if (qcCompletedQuests[qcBreadcrumbEntry] == nil) then
				qcCount = (qcCount + 1)
			else
				if not (qcCompletedQuests[qcBreadcrumbEntry]["C"] == 1) then
					qcCount = (qcCount + 1)
				end
			end
		end
		if (qcCount == 0) then
			qcToast.QuestID = nil
			qcToast:Hide()
		else
			if (qcCount == 1) then
				qcToastText:SetText("1 Breadcrumb Available!")
			else
				qcToastText:SetText(string.format("%d Breadcrumbs Available!",qcCount))
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
			return tostring(qcQuestDatabase[questId][2] or nil)
		end
	end
end

function qcToast_OnEnter(self)

	if (self.QuestID == nil) then
		qcToastTooltip:Hide()
	else
		qcToastTooltip:SetOwner(qcToast, "ANCHOR_CURSOR")
		qcToastTooltip:ClearLines()
		qcToastTooltip:AddLine("Breadcrumb Quests")
		for qcBreadcrumbIndex, qcBreadcrumbEntry in pairs(qcBreadcrumbQuests[self.QuestID]) do
			if (qcCompletedQuests[qcBreadcrumbEntry] == nil) then
				local qcQuestName = qcGetToastQuestInformation(qcBreadcrumbEntry)
				if (qcQuestName and qcBreadcrumbEntry) then qcToastTooltip:AddLine(tostring(COLOUR_DRUID .. qcQuestName .. COLOUR_MAGE .. " [" .. qcBreadcrumbEntry .. "]")) end
			else
				if not (qcCompletedQuests[qcBreadcrumbEntry]["C"] == 1) then
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
			local qcQuestName = tostring(qcQuestDatabase[qcQuestID][2] or nil)
			return qcQuestName
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
		qcMutuallyExclusiveAlertTooltip:AddLine(COLOUR_MAGE .. "This quest is mutually exclusive with others, meaning you can only complete one of them. The other quests are:", nil, nil, nil, true)
		for qcMutuallyExclusiveIndex, qcMutuallyExclusiveEntry in pairs(qcMutuallyExclusive[self.QuestID]) do
			if (qcQuestDatabase[qcMutuallyExclusiveEntry] == nil) then
				qcMutuallyExclusiveAlertTooltip:AddLine(string.format("%s<Quest Not Found In DB> [%d]|r",COLOUR_DRUID,qcMutuallyExclusiveEntry))
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
    local questName = questData[2]
    if questData[6] == 4 or questData[6] == 2 then
        return string.format("|cff178ed5%s|r", questName)
    elseif not qcCompletedQuests[questId] then
        return string.format("|cffffffff%s|r", questName)
    elseif qcCompletedQuests[questId]["C"] == 1 or qcCompletedQuests[questId]["C"] == 2 then
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
    local icon = pinData[2]
    if icon == 3 then
        local professionMask = 0
        for _, questId in ipairs(pinData[7]) do
            local quest = qcQuestDatabase[questId]
            if quest then
                professionMask = bit.bor(professionMask, quest[10])
            end
        end
        return qcProfessionIcon(professionMask)
    elseif icon == 1 then
        return qcNormalPinIcon(pinData[7])
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
    self:SetPosition(pinData[5] / 100, pinData[6] / 100)
    self:SetSize(24, 24)

    qcSetIcon(self.Texture, qcPinIcon(pinData))

    -- Initialize isGrey as true, and turn it to false if ANY quest is available
    local isGrey = true
    local playerLevel = UnitLevel("player")
    for _, questId in ipairs(pinData[7]) do
        if questId and qcQuestDatabase[questId] then
            local prereqQuestId = qcQuestDatabase[questId][14]
            local requiredLevel = qcQuestDatabase[questId][3]
            if playerLevel >= requiredLevel then
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
    if pinData[4] then
        return pinData[4]
    elseif pinData[3] ~= 0 or pinData[8] then
        return string.format("%s %s", UnitName("player"), "|cff69ccf0<Yourself>|r")
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
    if pinData[3] == 0 then
        qcMapTooltip:AddLine(name)
    else
        qcMapTooltip:AddDoubleLine(name, string.format("|cffff7d0a[%d]|r", pinData[3]))
    end
end

local function qcAddPinQuestsToTooltip(pinData)
    for _, qcEntry in ipairs(pinData[7]) do
        local questData = qcQuestDatabase[qcEntry]
        if questData then
            qcMapTooltip:AddDoubleLine("    " .. qcColouredQuestName(qcEntry), string.format("|cffff7d0a[%d]|r", qcEntry))
            local line = _G["qcMapTooltipTextLeft" .. qcMapTooltip:NumLines()]
            if line then
                local lineIcon = qcRecurringQuestIcon(qcEntry, questData[6])
                if not lineIcon then
                    if qcCompletedQuests[qcEntry] and (qcCompletedQuests[qcEntry]["C"] == 1 or qcCompletedQuests[qcEntry]["C"] == 2) then
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
            qcMapTooltip:AddDoubleLine("    |cff808080Quest Missing in DB|r", string.format("|cffff7d0a[%d]|r", qcEntry))
        end
    end

    if pinData[8] then
        qcMapTooltip:AddLine(string.format("|cffabd473%s|r", pinData[8]), nil, nil, nil, true)
    end
end

function qcPinMixin:OnMouseEnter()
    local pinData = self.PinData
    if not pinData then return end

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
        qcMapTooltip:AddLine("|cff808080Other quests|r")
    end
    for _, member in ipairs(others) do
        qcAddPinQuestsToTooltip(member)
    end

    qcMapTooltip:Show()
end

function qcPinMixin:OnMouseLeave()
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
            if first[1] == pinData[1] and (first[5] - pinData[5]) ^ 2 + (first[6] - pinData[6]) ^ 2 <= limit then
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
                for _, questId in ipairs(member[7]) do
                    table.insert(quests, questId)
                end
            end
            merged[i] = {first[1], first[2], first[3], first[4], first[5], first[6], quests, stack = stack}
        end
    end
    return merged
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
    local mapLevel = 0
    if not UiMapID or not qcPinDB[UiMapID] then return end

    wipe(qcPins)
    qcPins = qcCopyTable(qcPinDB[UiMapID])

    for i = #qcPins, 1, -1 do
        if qcPins[i][1] ~= mapLevel then
            table.remove(qcPins, i)
        end
    end
		--[[ Map No Data ]]--
	if qcSettings.QC_M_HIDE_NODATA == 1 then
		for i = #qcPins, 1, -1 do
			for questIndex = #qcPins[i][7], 1, -1 do
				local questId = qcPins[i][7][questIndex]
				if not qcQuestDatabase[questId] then
					table.remove(qcPins[i][7], questIndex)
				end
			end
			if #qcPins[i][7] == 0 then
				table.remove(qcPins, i)
			end
		end
	end
		--[[ Map Low Level ]]--
    if qcSettings.QC_M_HIDE_LOWLEVEL == 1 then
        for i = #qcPins, 1, -1 do
            for questIndex = #qcPins[i][7], 1, -1 do
                local questId = qcPins[i][7][questIndex]
                if qcQuestDatabase[questId] then
                    local questLevel = qcQuestDatabase[questId][3] or 0
					local greenCutoff = (UnitLevel("player") -  UnitQuestTrivialLevelRange("player"))
                    if questLevel < greenCutoff then
                        table.remove(qcPins[i][7], questIndex)
                    end
                else
                    table.remove(qcPins[i][7], questIndex)
                end
            end
            if #qcPins[i][7] == 0 then
                table.remove(qcPins, i)
            end
        end
    end
local overrideCompleted = {}

if qcSettings["QC_M_HIDE_COMPLETED"] == 1 or qcSettings["QC_M_HIDE_INPROGRESS"] == 1 then
    overrideCompleted = simulateExclusiveCompletions(qcOverrideDailyExclusiveQuest)
    for questID, _ in pairs(simulateExclusiveCompletions(qcOverrideWeeklyExclusiveQuest)) do
        overrideCompleted[questID] = true
    end
end

		--[[ Map Completed ]]--
	if qcSettings["QC_M_HIDE_COMPLETED"] == 1 then
		for i = #qcPins, 1, -1 do
			for j = #qcPins[i][7], 1, -1 do
				local questID = qcPins[i][7][j]
				if (qcCompletedQuests[questID] and (qcCompletedQuests[questID]["C"] == 1 or qcCompletedQuests[questID]["C"] == 2))
					or overrideCompleted[questID] then
					table.remove(qcPins[i][7], j)
				end
			end
			if #qcPins[i][7] == 0 then
				table.remove(qcPins, i)
			end
		end
	end

		--[[ Map and Quest Faction ]]--
	if (qcSettings["QC_ML_HIDE_FACTION"] == 1) then
		for i = #qcPins, 1, -1 do
			for qcQuestIndex = #qcPins[i][7], 1, -1 do
				local qcQuestID = qcPins[i][7][qcQuestIndex]
				local qcCurrentPlayerFaction, _S = UnitFactionGroup("player")
				local qcCurrentFaction = qcFactionBits[string.upper(qcCurrentPlayerFaction)]
				if (qcQuestDatabase[qcQuestID]) and not qcMaskAllows(qcQuestDatabase[qcQuestID][7], qcCurrentFaction) then
					TableRemove(qcPins[i][7], qcQuestIndex)
				end
			end
			if (#qcPins[i][7] == 0) then
				TableRemove(qcPins, i)
			end
		end
	end

		--[[  Map and Quest Race\Class ]]--
	if (qcSettings["QC_ML_HIDE_RACECLASS"] == 1) then
		for i = #qcPins, 1, -1 do
			for qcQuestIndex = #qcPins[i][7], 1, -1 do
				local qcQuestID = qcPins[i][7][qcQuestIndex]
				local _S, qcCurrentPlayerRace = UnitRace("player")
				local qcCurrentRace = qcRaceBits[string.upper(qcCurrentPlayerRace)]
				local _S, qcCurrentPlayerClass = UnitClass("player")
				local qcCurrentClass = qcClassBits[string.upper(qcCurrentPlayerClass)]
				if (qcQuestDatabase[qcQuestID]) and not qcMaskAllows(qcQuestDatabase[qcQuestID][8], qcCurrentRace) then
					TableRemove(qcPins[i][7], qcQuestIndex)
				elseif (qcQuestDatabase[qcQuestID]) and not qcMaskAllows(qcQuestDatabase[qcQuestID][9], qcCurrentClass) then
					TableRemove(qcPins[i][7], qcQuestIndex)
				end
			end
			if (#qcPins[i][7] == 0) then
				TableRemove(qcPins, i)
			end
		end
	end
		--[[ Map Seasonal ]]--
	local qcActive = (qcSettings["QC_M_HIDE_SEASONAL"] == 1) and qcUpdateActiveHolidays()
	if qcActive then
		for i = #qcPins, 1, -1 do
			for qcQuestIndex = #qcPins[i][7], 1, -1 do
				local qcQuestID = qcPins[i][7][qcQuestIndex]
				-- A holiday value we don't know restricts nothing, like any other field with no data.
				local qcHoliday = qcQuestDatabase[qcQuestID] and qcQuestDatabase[qcQuestID][11]
				if qcKnownHolidayFlags[qcHoliday] and BitBand(qcActive, qcHoliday) == 0 then
					TableRemove(qcPins[i][7], qcQuestIndex)
				end
			end
			if (#qcPins[i][7] == 0) then
				TableRemove(qcPins, i)
			end
		end
	end

		--[[ Map In progress ]]--
	if qcSettings["QC_M_HIDE_INPROGRESS"] == 1 then
		for i = #qcPins, 1, -1 do
			for j = #qcPins[i][7], 1, -1 do
				local questID = qcPins[i][7][j]
				local isAccepted = C_QuestLog.GetLogIndexForQuestID(questID) and C_QuestLog.GetLogIndexForQuestID(questID) > 0
				if isAccepted or overrideCompleted[questID] then
					table.remove(qcPins[i][7], j)
				end
			end
			if #qcPins[i][7] == 0 then
				table.remove(qcPins, i)
			end
		end
	end

		--[[ Map Covenants ]]--
	if C_Covenants and C_Covenants.GetActiveCovenantID then -- Only run where the Covenants API exists
		if (qcSettings["QC_ML_HIDE_COVENANTS"] == 1) then
			local playerCovenantID = C_Covenants.GetActiveCovenantID()
			local playerCovenantBit = qcCovenantsBits[playerCovenantID] or 0

			for i = #qcPins, 1, -1 do
				for qcQuestIndex = #qcPins[i][7], 1, -1 do
					local qcQuestID = qcPins[i][7][qcQuestIndex]
					if qcQuestDatabase[qcQuestID] and qcQuestDatabase[qcQuestID][12] then
						local questCovenant = qcQuestDatabase[qcQuestID][12]
						if questCovenant > 0 and BitBand(questCovenant, playerCovenantBit) == 0 then
							TableRemove(qcPins[i][7], qcQuestIndex)
						end
					end
				end
				if #qcPins[i][7] == 0 then
					TableRemove(qcPins, i)
				end
			end
		end
	end
		--[[ Map Warbands ]]--
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompletedOnAccount then -- Only run where account-wide (Warband) quest tracking exists
		if (qcSettings["QC_ML_HIDE_WARBANDS"] == 1) then
			for i = #qcPins, 1, -1 do
				for qcQuestIndex = #qcPins[i][7], 1, -1 do
					local qcQuestID = qcPins[i][7][qcQuestIndex]
					if C_QuestLog.IsQuestFlaggedCompletedOnAccount(qcQuestID) then
						TableRemove(qcPins[i][7], qcQuestIndex)
					end
				end
				if #qcPins[i][7] == 0 then
					TableRemove(qcPins, i)
				end
			end
		end
	end
		--[[ Map Prerequisites Not Met ]] --
	if (qcSettings["QC_M_HIDE_REQUIREMENTSNOTMET"] == 1) then
		local playerLevel = UnitLevel("player")
		local playerFaction, _ = UnitFactionGroup("player")

		for i = #qcPins, 1, -1 do
			for qcQuestIndex = #qcPins[i][7], 1, -1 do
				local qcQuestID = qcPins[i][7][qcQuestIndex]
				local questData = qcQuestDatabase[qcQuestID]

				if questData then
					local questLevel = questData[3] or 0  -- Assuming quest level is at index 3
					local prequestID = questData[14] or 0 -- Assuming prequest ID is at index 14

					-- Check if the player's level is below the required quest level
					local belowRequiredLevel = questLevel > playerLevel

					-- Check if a prerequisite quest is not completed
					local prequestNotCompleted = prequestID > 0 and not C_QuestLog.IsQuestFlaggedCompleted(prequestID)

					-- Check faction standing from qcRenownLevelRequirements (Retail only)
					local factionStandingTooLow = false
					if C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel then -- Only check faction/renown requirements where the API exists
						local renownRequirement = qcRenownLevelRequirements[qcQuestID]
						if renownRequirement then
							local factionID = renownRequirement[1]  -- First value is faction ID
							local requiredRenown = renownRequirement[2]  -- Second value is required renown level
							local currentRenown = C_MajorFactions.GetCurrentRenownLevel(factionID)

							-- If player's renown is lower than required, mark the quest for removal
							factionStandingTooLow = currentRenown < requiredRenown
						end
					end

					-- Remove the quest if any of the requirements are not met
					if belowRequiredLevel or prequestNotCompleted or factionStandingTooLow then
						TableRemove(qcPins[i][7], qcQuestIndex)
					end
				end
			end
			if #qcPins[i][7] == 0 then
				TableRemove(qcPins, i)
			end
		end
	end

		--[[ Map Professions ]]--
	if qcSettings.QC_M_HIDE_PROFESSION == 1 then
		local professionBitwise = qcPlayerProfessionMask()

    -- Iterate through pins and filter out quests based on profession bitwise flag
    for i = #qcPins, 1, -1 do
        for questIndex = #qcPins[i][7], 1, -1 do
            local questId = qcPins[i][7][questIndex]
            if qcQuestDatabase[questId] then
                local questProfessionFlag = qcQuestDatabase[questId][10]
                if questProfessionFlag and questProfessionFlag ~= 0 then
                    -- Check if the quest's profession flag matches any of the player's professions
                    if bit.band(questProfessionFlag, professionBitwise) == 0 then
                        -- If no match, remove the quest
                        table.remove(qcPins[i][7], questIndex)
                    end
                end
            end
        end
        -- Clean up any empty pins
        if #qcPins[i][7] == 0 then
            table.remove(qcPins, i)
        end
    end
end

    for _, pinData in ipairs(qcMergeStackedPins(qcPins)) do
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
    if (qcSettings.QC_M_HIDE_WORLDQUEST == nil) then
        qcSettings.QC_M_HIDE_WORLDQUEST = 1
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
	if (qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET == nil) then
        qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET = 1
    end
    if (qcSettings.QC_SERVER_QUERY_COMPLETE == nil) then
        qcSettings.QC_SERVER_QUERY_COMPLETE = 0
    end
    if (qcSettings.QC_M_HIDE_DAILYREPEATABLE == nil) then
        qcSettings.QC_M_HIDE_DAILYREPEATABLE = 0
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

    -- Only handle qcIO_ML_HIDE_COVENANTS where the checkbox exists (created only where the Covenants API exists)
    if qcIO_ML_HIDE_COVENANTS then
        if (qcSettings.QC_ML_HIDE_COVENANTS == 0) then
            qcIO_ML_HIDE_COVENANTS:SetChecked(false)
        else
            qcIO_ML_HIDE_COVENANTS:SetChecked(true)
        end
    end

    -- Only handle qcIO_ML_HIDE_WARBANDS where the checkbox exists (created only where account-wide quest tracking exists)
    if qcIO_ML_HIDE_WARBANDS then
        if (qcSettings.QC_ML_HIDE_WARBANDS == 0) then
            qcIO_ML_HIDE_WARBANDS:SetChecked(false)
        else
            qcIO_ML_HIDE_WARBANDS:SetChecked(true)
        end
    end

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
    print(string.format("%sThanks for using Quest Completist. Spot a quest inaccuracy? Please report it on Curse.", QCADDON_CHAT_TITLE))
    print(string.format("%sMap Pins are back. There are some hickups still, see bug list on CF", QCADDON_CHAT_TITLE))
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
    qcUpdateQuestList(qcCurrentCategoryID, 1)
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
    qcListFiltersTitle:SetPoint("TOPLEFT", qcConfigSubtitle, "BOTTOMLEFT", 16, -235)
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
    qcCombinedFiltersTitle:SetPoint("TOPLEFT", qcConfigSubtitle, "BOTTOMLEFT", 16, -425)
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

	-- Create Covenant Checkbox where the Covenants API exists
	if C_Covenants and C_Covenants.GetActiveCovenantID then
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
	end

	-- Create Warband Checkbox where account-wide (Warband) quest tracking exists
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompletedOnAccount then
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
	end
	
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

local function qcEventHandler(self, event, ...)
	if (event == "QUEST_DATA_LOAD_RESULT") then
		local questId, success = ...
		qcQuestDataRequested[questId] = nil
		if (success) then
			qcQuestDataLoaded[questId] = true
			-- Only redraw if this is still the quest being hovered; the list may have scrolled.
			if (questId == qcTooltipQuestId and qcTooltipIndex and _G["qcMenuButton" .. qcTooltipIndex].QuestID == questId) then
				qcUpdateTooltip(qcTooltipIndex)
			end
		end
	elseif (event == "ADVENTURE_MAP_OPEN") then
		qcMapDataProvider:RefreshAllData()
	elseif (event == "UNIT_QUEST_LOG_CHANGED") then
		if (... == "player") then qcUpdateQuestList(nil, qcMenuSlider:GetValue()) end
	elseif (event == "ZONE_CHANGED_NEW_AREA") then
		qcZoneChangedNewArea()		--				
	elseif (event == "ZONE_CHANGED") then
		qcZoneChangedNewArea()
	elseif (event == "QUEST_ITEM_UPDATE") then
--		if (QuestFrame:IsShown() and QuestFrame.TopTileStreaks) then QuestFrame.TopTileStreaks:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 10.X replacemnt from beta?
--		if (QuestFrame:IsShown()) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end  9.xx Soltion
		if (QuestFrame:IsShown() and QuestFrameNpcNameText) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end
	elseif (event == "QUEST_DETAIL") then
		local qcQuestID = GetQuestID()
--		if (QuestFrame:IsShown() and QuestFrame.TopTileStreaks) then QuestFrame.TopTileStreaks:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 10.X replacemnt from beta?
--		if (QuestFrame:IsShown()) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 9.xx Soltion
		if (QuestFrame:IsShown() and QuestFrameNpcNameText) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end
		qcBreadcrumbChecks(qcQuestID)
		qcNewDataChecks(qcQuestID)
		qcMutuallyExclusiveChecks(qcQuestID)
	elseif (event == "QUEST_ACCEPTED") then
		qcUpdateQuestList(nil, qcMenuSlider:GetValue())
	elseif (event == "QUEST_PROGRESS") then
		local qcQuestID = GetQuestID()
--		if (QuestFrame:IsShown() and QuestFrame.TopTileStreaks) then QuestFrame.TopTileStreaks:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 10.X replacemnt from beta?
--		if (QuestFrame:IsShown()) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 9.xx Soltion
		if (QuestFrame:IsShown() and QuestFrameNpcNameText) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end
		if not (qcQuestID == 0) then
			qcBreadcrumbChecks(qcQuestID)
			qcNewDataChecks(qcQuestID)
			qcMutuallyExclusiveChecks(qcQuestID)
		end
	elseif (event == "QUEST_LOG_UPDATE") then
		local qcQuestID = GetQuestID()
	--	if (QuestFrame:IsShown() and QuestFrame.TopTileStreaks) then QuestFrame.TopTileStreaks:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 10.X replacemnt from beta?
	--	if (QuestFrame:IsShown()) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 9.xx Soltion
	if (QuestFrame:IsShown() and QuestFrameNpcNameText) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end
		if not (qcQuestID == 0) then
			qcBreadcrumbChecks(qcQuestID)
			qcNewDataChecks(qcQuestID)
			qcMutuallyExclusiveChecks(qcQuestID)
			qcUpdateQuestList(nil, qcMenuSlider:GetValue())
		end
	elseif (event == "QUEST_TURNED_IN") then
		local qcQuestID = ...
		qcUpdateCompletedQuest(qcQuestID)
		qcUpdateMutuallyExclusiveCompletedQuest(qcQuestID)
		qcUpdateSkippedBreadcrumbQuest(qcQuestID)
		qcUpdateQuestList(nil, qcMenuSlider:GetValue())
	elseif (event == "PLAYER_ENTERING_WORLD") then
			local isInitialLogin, isReloadingUi = ...
			if (isInitialLogin or isReloadingUi) then
				qcQuestQueryCompleted()
			end
			qcZoneChangedNewArea()
	elseif (event == "ADDON_LOADED") then
		if (... == "QuestCompletist") then
			if not (qcCompletedQuests) then qcCompletedQuests = {} end
			if not (qcWorkingDB) then qcWorkingDB = {} end
			if not (qcWorkingLog) then qcWorkingLog = {} end
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
		qcUpdateQuestList(qcCurrentCategoryID,qcMenuSlider:GetValue())
	end
end

function qcQuestCompletistUI_OnLoad(self)
--SetPortraitToTexture(self.qcPortrait, "Interface\\ICONS\\TRADE_ARCHAEOLOGY_DRAENEI_TOME")
	self.qcTitleText:SetText(string.format("Quest Completist v%s", QCADDON_VERSION))
	self.qcCategoryDropdownButton:SetText(GetText("CATEGORIES"))
	self.qcOptionsButton:SetText(GetText("FILTERS"))
	self:RegisterForDrag("LeftButton")
	self:RegisterEvent("QUEST_COMPLETE")
	--self:RegisterEvent("QUEST_FINISHED") -- Cant be used for marking quest complette sinze it marks it done before its turned in 
	self:RegisterEvent("QUEST_TURNED_IN")
	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("QUEST_DETAIL")
	self:RegisterEvent("QUEST_PROGRESS")
	self:RegisterEvent("QUEST_ACCEPTED")
	self:RegisterEvent("QUEST_ITEM_UPDATE")
	self:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA") -- 
	self:RegisterEvent("ZONE_CHANGED")
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("ADVENTURE_MAP_OPEN")
	-- Retail only; the event doesn't exist on the Classic interface the TOC also lists.
	if (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then
		pcall(self.RegisterEvent, self, "QUEST_DATA_LOAD_RESULT")
	end
	self:SetScript("OnEvent", qcEventHandler)
	qcQuestInformationTooltipSetup()
	qcMapTooltipSetup()
	qcToastTooltipSetup()
	qcNewDataAlertTooltipSetup()
	qcMutuallyExclusiveAlertTooltipSetup()
end