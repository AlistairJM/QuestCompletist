--[[ Quest giver pins on the world map: the map's data provider, the pins and their tooltip. What it
needs from qcCore.lua and qcTooltips.lua comes through the addon's own table. ]]--
local QC = select(2, ...)
local TableInsert = table.insert
local BitBand = bit.band
local qcL = qcLocalize
local QC_ICON_NORMAL, QC_ICON_COMPLETE = QC.QC_ICON_NORMAL, QC.QC_ICON_COMPLETE
local QC_PIN_ICONS, QC_PIN_ICON_RANK = QC.QC_PIN_ICONS, QC.QC_PIN_ICON_RANK
local qcSetIcon, qcProfessionIcon, qcNormalPinIcon = QC.qcSetIcon, QC.qcProfessionIcon, QC.qcNormalPinIcon
local qcRecurringQuestIcon, qcIsQuestCompleted, qcIsQuestCompletedOnAccount = QC.qcRecurringQuestIcon, QC.qcIsQuestCompleted, QC.qcIsQuestCompletedOnAccount
local qcIsUnavailable, qcQuestName = QC.qcIsUnavailable, QC.qcQuestName
local qcKnownHolidayFlags, qcUpdateActiveHolidays = QC.qcKnownHolidayFlags, QC.qcUpdateActiveHolidays
local QC_MAP_FILTER, qcBuildQuestFilter, simulateExclusiveCompletions = QC.QC_MAP_FILTER, QC.qcBuildQuestFilter, QC.simulateExclusiveCompletions
local qcNpcName, qcRequestPinNpcNames = QC.qcNpcName, QC.qcRequestPinNpcNames
local qcMapTooltipWaiting, qcNpcMapTooltipWaiting = QC.qcMapTooltipWaiting, QC.qcNpcMapTooltipWaiting
local qcQuestStatus, qcTooltipBar = QC.qcQuestStatus, QC.qcTooltipBar

local qcMapTooltip
-- The pin under the mouse, so names arriving later can redraw its tooltip.
local qcMapTooltipPin

function qcMapTooltipSetup() -- *
	qcMapTooltip = CreateFrame("GameTooltip", "qcMapTooltip", UIParent, "GameTooltipTemplate")
	qcMapTooltip:SetFrameStrata("TOOLTIP")
	WorldMapFrame:HookScript("OnSizeChanged",
		function(self)
			qcMapTooltip:SetScale(1/self:GetScale())
		end
	)
end

--[[ ##### MAP PINS START ##### ]]--
-- The map's quest filter from its last refresh, for the tooltip's progress count.
local qcPinProgressFilter

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

local function qcHideTooltipDecorations()
    qcMapTooltip.qcIcons = qcMapTooltip.qcIcons or {}
    for _, icon in ipairs(qcMapTooltip.qcIcons) do
        icon:Hide()
    end
    qcMapTooltip.qcIconsUsed = 0
    qcTooltipBar.HideAll(qcMapTooltip)
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

-- The pin tooltip's width with a progress bar, and how many done quests fold into one line unless
-- Shift is held.
local QC_PIN_TOOLTIP = {barMinWidth = 180, foldDone = 2}

-- Every line sets the fonts of both its sides: the tooltip reuses its lines, keeping the last font.
local function qcAddMapTooltipLine(left, right, leftFont, wrap)
    if right then
        qcMapTooltip:AddDoubleLine(left, right)
    elseif wrap then
        qcMapTooltip:AddLine(left, nil, nil, nil, true)
    else
        qcMapTooltip:AddLine(left)
    end
    local line = qcMapTooltip:NumLines()
    local leftText, rightText = _G["qcMapTooltipTextLeft" .. line], _G["qcMapTooltipTextRight" .. line]
    if leftText then leftText:SetFontObject(leftFont or GameTooltipText) end
    if rightText then rightText:SetFontObject(GameTooltipTextSmall) end
    return leftText, rightText
end

local function qcSetMapTooltipLineIcon(leftText, icon)
    if not leftText then return end
    local texture = qcAcquireTooltipIcon()
    qcSetIcon(texture, icon)
    texture:ClearAllPoints()
    texture:SetPoint("LEFT", leftText, "LEFT", -6, 0)
    texture:Show()
end

local function qcAddPinQuestLine(questId, state)
    local icon, colour = qcQuestStatus.Look(questId, state)
    local leftText = qcAddMapTooltipLine(string.format("    |cff%s%s|r", colour, qcQuestName(questId, qcMapTooltipWaiting)),
        string.format("|cff808080%d|r", questId))
    qcSetMapTooltipLineIcon(leftText, icon)
end

-- One giver's quests: a progress bar when there are two or more to count, then the quests to do
-- first. Recurring quests are never done, so the progress leaves them out. It counts the quests the
-- map hides for being done or in the log, as the list's total does.
local function qcAddPinQuestsToTooltip(pins)
    local countWarband = (qcSettings.QC_ML_HIDE_WARBANDS == 1)
    local done, total, seen = 0, 0, {}
    for _, pinData in ipairs(pins) do
        for _, questId in ipairs(pinData.allQuests or pinData[6]) do
            local questData = qcQuestDatabase[questId]
            if questData and not seen[questId] and not qcRecurringQuestIcon(questId, questData[4])
                    and (not qcPinProgressFilter or qcPinProgressFilter(questId, true)) then
                seen[questId] = true
                total = total + 1
                if qcIsQuestCompleted(questId) or (countWarband and qcIsQuestCompletedOnAccount(questId)) then
                    done = done + 1
                end
            end
        end
    end
    if total >= 2 then
        local leftText, rightText = qcAddMapTooltipLine(" ", string.format("|cffc8c8c8%d/%d|r", done, total))
        if leftText and rightText then
            qcTooltipBar.Show(qcMapTooltip, leftText, rightText, done, total)
        end
    end

    local byState, noData = {{}, {}, {}, {}, {}}, {}
    wipe(seen)
    for _, pinData in ipairs(pins) do
        for _, questId in ipairs(pinData[6]) do
            if not seen[questId] then
                seen[questId] = true
                local questData = qcQuestDatabase[questId]
                if questData then
                    table.insert(byState[qcQuestStatus.Of(questId, questData)], questId)
                else
                    table.insert(noData, questId)
                end
            end
        end
    end
    for state = qcQuestStatus.READY, qcQuestStatus.RECURRING do
        for _, questId in ipairs(byState[state]) do
            qcAddPinQuestLine(questId, state)
        end
    end
    local finished = byState[qcQuestStatus.DONE]
    if #finished >= QC_PIN_TOOLTIP.foldDone and not IsShiftKeyDown() then
        local leftText = qcAddMapTooltipLine(string.format("    |cff7fbf7f%s|r", string.format(qcL.PINDONE, #finished)),
            "|cff808080" .. qcL.PINSHOWDONE .. "|r")
        qcSetMapTooltipLineIcon(leftText, QC_ICON_COMPLETE)
    else
        for _, questId in ipairs(finished) do
            qcAddPinQuestLine(questId, qcQuestStatus.DONE)
        end
    end
    for _, questId in ipairs(noData) do
        qcAddMapTooltipLine("    |cff808080" .. qcL.NOTINDATABASE .. "|r", string.format("|cff808080%d|r", questId))
    end

    for _, pinData in ipairs(pins) do
        if pinData[7] then
            qcAddMapTooltipLine(string.format("|cffabd473%s|r", pinData[7]), nil, nil, true)
        end
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
    qcHideTooltipDecorations()

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
            qcAddMapTooltipLine(" ")
        end
        local npcId = giver.pins[1][2]
        qcAddMapTooltipLine(giver.name, npcId ~= 0 and string.format("|cff808080%d|r", npcId) or nil, GameTooltipHeaderText)
        qcAddPinQuestsToTooltip(giver.pins)
    end
    if #others > 0 then
        if #givers > 0 then
            qcAddMapTooltipLine(" ")
            qcAddMapTooltipLine("|cff808080" .. qcL.OTHERQUESTS .. "|r")
        end
        qcAddPinQuestsToTooltip(others)
    end

    qcMapTooltip:SetMinimumWidth(qcMapTooltip.qcBarsUsed > 0 and QC_PIN_TOOLTIP.barMinWidth or 0)
    qcMapTooltip:Show()
end

function qcPinMixin:OnMouseLeave()
    qcMapTooltipPin = nil
    qcMapTooltip:Hide()
    qcHideTooltipDecorations()
end

-- Pressing or letting go of Shift lists or folds the done quests of the pin under the mouse.
local qcShiftWatcher = CreateFrame("Frame")
qcShiftWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
qcShiftWatcher:SetScript("OnEvent", function(_, _, key)
    if (key == "LSHIFT" or key == "RSHIFT") and qcMapTooltipPin and qcMapTooltip:IsShown() then
        qcMapTooltipPin:OnMouseEnter()
    end
end)

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
-- data passes every check that reads the database. With forProgress it ignores the filters on what
-- the character has done or has in the log, so the tooltip's progress counts those quests too.
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

    return function(questId, forProgress)
        local e = qcQuestDatabase[questId]
        if not e and hideNoData then return false end
        if not forProgress then
            if hideCompleted and (qcIsQuestCompleted(questId) or overrideCompleted[questId]) then return false end
            if hideInProgress and (qcIsQuestInLog(questId) or overrideCompleted[questId]) then return false end
            if hideWarband and qcIsQuestCompletedOnAccount(questId) then return false end
        end
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
    qcPinProgressFilter = keepQuest
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
            pinData.allQuests = pin[6]
            TableInsert(pins, pinData)
        end
    end

    qcRequestPinNpcNames(pins)
    for _, pinData in ipairs(qcMergeStackedPins(pins)) do
        self:GetMap():AcquirePin("qcPinTemplate", pinData)
    end
end

WorldMapFrame:AddDataProvider(qcMapDataProvider)

--[[ ##### MAP PINS END ##### ]]--


-- For qcCore.lua, when quest or NPC names arrive: redraw the tooltip of the pin under the mouse.
function QC.RedrawMapTooltip()
    if qcMapTooltipPin and qcMapTooltip:IsShown() then
        qcMapTooltipPin:OnMouseEnter()
    end
end
