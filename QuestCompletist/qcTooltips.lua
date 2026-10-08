--[[ The quest list's tooltip, and the quest status and progress bar helpers it shares with the map
pins' tooltip in qcMapPins.lua. What it needs from qcCore.lua comes through the addon's own table. ]]--
local QC = select(2, ...)
local qcL = qcLocalize
local COLOUR_DRUID, COLOUR_HUNTER, COLOUR_MAGE = QC.COLOUR_DRUID, QC.COLOUR_HUNTER, QC.COLOUR_MAGE
local QC_ICON_NORMAL, QC_ICON_READY, QC_ICON_PROGRESS = QC.QC_ICON_NORMAL, QC.QC_ICON_READY, QC.QC_ICON_PROGRESS
local QC_ICON_COMPLETE, QC_ICON_UNATTAINABLE = QC.QC_ICON_COMPLETE, QC.QC_ICON_UNATTAINABLE
local QC_FULL_TEXCOORDS = QC.QC_FULL_TEXCOORDS
local qcRecurringQuestIcon, qcIsQuestCompleted, qcIsQuestCompletedOnAccount = QC.qcRecurringQuestIcon, QC.qcIsQuestCompleted, QC.qcIsQuestCompletedOnAccount
local qcMaskAllows, qcQuestName, qcRequestQuestData, qcPrereq = QC.qcMaskAllows, QC.qcQuestName, QC.qcRequestQuestData, QC.qcPrereq
local qcNpcName, qcFindPinForQuest = QC.qcNpcName, QC.qcFindPinForQuest
local qcQuestTooltipWaiting, qcNpcTooltipWaiting = QC.qcQuestTooltipWaiting, QC.qcNpcTooltipWaiting
local qcHides, qcFactionLevel = QC.qcHides, QC.qcFactionLevel
local qcSkillRank, qcSkillName = QC.qcSkillRank, QC.qcSkillName

local qcQuestInformationTooltip
-- The list row the tooltip belongs to, and its quest, so names arriving later can redraw it.
local qcTooltipIndex, qcTooltipQuestId

local QC_STORYLINE_WINDOW = 15

--[[ Shared with the map pins' tooltip, which takes the two tables from the addon's own table (the end
of this file). ]]--

-- How a quest stands for this character, with the quest list's order, icons and colours.
local qcQuestStatus = {READY = 1, PROGRESS = 2, TODO = 3, RECURRING = 4, DONE = 5}

function qcQuestStatus.Of(questId, questData)
	if C_QuestLog.GetLogIndexForQuestID(questId) then
		return C_QuestLog.IsComplete(questId) and qcQuestStatus.READY or qcQuestStatus.PROGRESS
	end
	if qcRecurringQuestIcon(questId, questData[4]) then return qcQuestStatus.RECURRING end
	if qcIsQuestCompleted(questId) then return qcQuestStatus.DONE end
	return qcQuestStatus.TODO
end

function qcQuestStatus.Look(questId, state)
	if state == qcQuestStatus.READY then return QC_ICON_READY, "ffd100" end
	if state == qcQuestStatus.PROGRESS then return QC_ICON_PROGRESS, "949694" end
	if state == qcQuestStatus.RECURRING then
		return qcRecurringQuestIcon(questId, qcQuestDatabase[questId][4]), "18a0f0"
	end
	if state == qcQuestStatus.DONE then
		if qcCharacterCompletions[questId] == 2 then return QC_ICON_UNATTAINABLE, "c41f3b" end
		return QC_ICON_COMPLETE, "00ff00"
	end
	return QC_ICON_NORMAL, "ffffff"
end

-- An icon written into a line's text: an atlas by name, a file with its texture coordinates.
function qcQuestStatus.IconText(icon, size)
	if icon.atlas then
		return string.format("|A:%s:%d:%d|a", icon.atlas, size, size)
	end
	local coords = icon.coords or QC_FULL_TEXCOORDS
	return string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t", icon.file, size, size,
		coords[1] * 64, coords[2] * 64, coords[3] * 64, coords[4] * 64)
end

-- A progress bar on a tooltip line whose right text is the count, filled with Blizzard's own bar
-- fill. Its ends are round: a circle of the bar's fill or background centred on each end, so half
-- of it sticks out.
local qcTooltipBar = {height = 6, fill = "ui-frame-bar-fill-green", left = {0.2, 0.2, 0.25}}

function qcTooltipBar.Paint(cap, filled)
	if filled then
		cap:SetAtlas(qcTooltipBar.fill)
	else
		cap:SetColorTexture(unpack(qcTooltipBar.left))
	end
end

function qcTooltipBar.HideAll(tooltip)
	tooltip.qcBars = tooltip.qcBars or {}
	for _, bar in ipairs(tooltip.qcBars) do
		bar:Hide()
	end
	tooltip.qcBarsUsed = 0
end

function qcTooltipBar.Cap(bar, point)
	local cap = bar:CreateTexture(nil, "ARTWORK")
	cap:SetSize(qcTooltipBar.height, qcTooltipBar.height)
	cap:SetPoint("CENTER", bar, point)
	local mask = bar:CreateMaskTexture()
	mask:SetAtlas("CircleMaskScalable")
	mask:SetAllPoints(cap)
	cap:AddMaskTexture(mask)
	return cap
end

function qcTooltipBar.Show(tooltip, leftText, rightText, done, total)
	tooltip.qcBarsUsed = tooltip.qcBarsUsed + 1
	local bar = tooltip.qcBars[tooltip.qcBarsUsed]
	if not bar then
		bar = CreateFrame("StatusBar", nil, tooltip)
		bar:SetHeight(qcTooltipBar.height)
		bar:SetStatusBarTexture(qcTooltipBar.fill)
		local background = bar:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints()
		background:SetColorTexture(unpack(qcTooltipBar.left))
		bar.leftCap = qcTooltipBar.Cap(bar, "LEFT")
		bar.rightCap = qcTooltipBar.Cap(bar, "RIGHT")
		tooltip.qcBars[tooltip.qcBarsUsed] = bar
	end
	bar:ClearAllPoints()
	bar:SetPoint("LEFT", leftText, "LEFT", qcTooltipBar.height / 2, 0)
	bar:SetPoint("RIGHT", rightText, "LEFT", -8 - qcTooltipBar.height / 2, 0)
	bar:SetMinMaxValues(0, total)
	bar:SetValue(done)
	qcTooltipBar.Paint(bar.leftCap, done > 0)
	qcTooltipBar.Paint(bar.rightCap, done >= total)
	bar:Show()
end

-- A thin line across a tooltip line, between sections. The caller adds the line with a right text, so
-- both ends of the divider sit on it.
local qcTooltipDivider = {colour = {0.6, 0.6, 0.6, 0.35}}

function qcTooltipDivider.HideAll(tooltip)
	tooltip.qcDividers = tooltip.qcDividers or {}
	for _, divider in ipairs(tooltip.qcDividers) do
		divider:Hide()
	end
	tooltip.qcDividersUsed = 0
end

function qcTooltipDivider.Show(tooltip, leftText, rightText)
	tooltip.qcDividersUsed = tooltip.qcDividersUsed + 1
	local divider = tooltip.qcDividers[tooltip.qcDividersUsed]
	if not divider then
		divider = tooltip:CreateTexture(nil, "OVERLAY")
		divider:SetHeight(1)
		divider:SetColorTexture(unpack(qcTooltipDivider.colour))
		tooltip.qcDividers[tooltip.qcDividersUsed] = divider
	end
	divider:ClearAllPoints()
	divider:SetPoint("LEFT", leftText, "LEFT")
	divider:SetPoint("RIGHT", rightText, "RIGHT")
	divider:Show()
end

-- The faction's name in the player's language, or the English one from qcFactions.
local function qcFactionName(factionId)
	local data = C_Reputation.GetFactionDataByID(factionId)
	if data and data.name and data.name ~= "" then return data.name end
	return qcFactions[factionId]
end

-- A renown faction's emblem, written into a line's text and followed by a space; empty for other
-- factions, and in a game without renown.
local function qcFactionIconText(factionId)
	local data = C_MajorFactions and C_MajorFactions.GetMajorFactionData(factionId)
	if not (data and data.textureKit) then return "" end
	return string.format("|A:majorfactions_icons_%s512:16:16|a ", data.textureKit)
end

local function qcAddQuestTooltipDivider()
	qcQuestInformationTooltip:AddDoubleLine(" ", " ")
	local line = qcQuestInformationTooltip:NumLines()
	local leftText = _G["qcQuestInformationTooltipTextLeft" .. line]
	local rightText = _G["qcQuestInformationTooltipTextRight" .. line]
	if leftText and rightText then
		qcTooltipDivider.Show(qcQuestInformationTooltip, leftText, rightText)
	end
end

-- A quest to do first, with the icon and colour the storyline would give it.
local function qcPrereqQuestText(questId)
    local data = qcQuestDatabase[questId]
    local icon, colour
    if data then
        icon, colour = qcQuestStatus.Look(questId, qcQuestStatus.Of(questId, data))
    elseif C_QuestLog.IsQuestFlaggedCompleted(questId) then
        icon, colour = QC_ICON_COMPLETE, "00ff00"
    else
        icon, colour = QC_ICON_NORMAL, "ffffff"
    end
    return string.format("%s |cff%s%s|r", qcQuestStatus.IconText(icon, 14), colour, qcQuestName(questId, qcQuestTooltipWaiting) or UNKNOWN)
end

-- The campaign a quest belongs to and, when it can be told, the quest's chapter among the campaign's
-- chapters, which are quest lines. A quest's storyline is the smallest quest line that holds it, and
-- not always the chapter, so when it isn't one the chapters' own quests are searched. WoW: Forever has
-- no campaigns; the game answers 0 there.
local function qcCampaignOf(questId, storylineId)
    if not (QUEST_CLASSIFICATION_CAMPAIGN and C_CampaignInfo and C_CampaignInfo.GetCampaignID) then return nil end
    local campaignId = C_CampaignInfo.GetCampaignID(questId)
    local info = campaignId and campaignId ~= 0 and C_CampaignInfo.GetCampaignInfo(campaignId)
    if not (info and info.name and info.name ~= "") then return nil end
    local chapters = C_CampaignInfo.GetChapterIDs(campaignId) or {}
    local chapter
    for i, chapterId in ipairs(chapters) do
        if chapterId == storylineId then
            chapter = i
            break
        end
    end
    if not chapter and C_QuestLine and C_QuestLine.GetQuestLineQuests then
        for i, chapterId in ipairs(chapters) do
            for _, lineQuestId in ipairs(C_QuestLine.GetQuestLineQuests(chapterId) or {}) do
                if lineQuestId == questId then
                    chapter = i
                    break
                end
            end
            if chapter then break end
        end
    end
    return info.name, chapter, #chapters
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
        qcTooltipBar.HideAll(qcQuestInformationTooltip)
        qcTooltipDivider.HideAll(qcQuestInformationTooltip)
        -- Without the quest's data, SetHyperlink leaves the tooltip unable to show at all, even the
        -- lines added after it, so name the quest ourselves until the data arrives.
        if HaveQuestData(questId) then
            qcQuestInformationTooltip:SetHyperlink(stringFormat("quest:%d", questId))
        else
            qcQuestInformationTooltip:AddLine(qcQuestName(questId), 1, 1, 1)
            qcQuestInformationTooltip:AddLine(qcL.NODETAILS, 0.5, 0.5, 0.5)
        end
        qcAddQuestTooltipDivider()
        qcQuestInformationTooltip:AddDoubleLine(qcL.QUESTID, stringFormat("%s%d|r", COLOUR_MAGE, questId))
        qcAddQuestTooltipDivider()

        -- Restore ATT hook if we temporarily replaced it
        if att_HookBackup then
            GameTooltip.OnTooltipSetQuest = att_HookBackup
            att_HookBackup = nil
        end

        local storylineId = qcQuestDatabase[questId][8]
        local campaignName, chapter, chapterCount = qcCampaignOf(questId, storylineId)
        if campaignName then
            local place = chapter and stringFormat(" |cFF808080%s|r", stringFormat(qcL.CAMPAIGNCHAPTER, chapter, chapterCount)) or ""
            qcQuestInformationTooltip:AddDoubleLine(stringFormat(STAT_FORMAT, QUEST_CLASSIFICATION_CAMPAIGN), stringFormat("%s%s|r%s", COLOUR_HUNTER, campaignName, place))
        end

        -- Storyline information. qcQuestLines holds each storyline's quests in Blizzard's order;
        -- a whole-zone storyline runs to 200+ quests, so only a window around this one is shown.
        local storyline = storylineId and qcQuestLines[storylineId]
        if storyline then
            -- Older zones share one storyline between both factions, and a class's quests sit
            -- beside every other class's: follow the list's faction and race/class filters. The
            -- progress counts like the map's, leaving out recurring quests.
            local factionFlag = qcHides("L", "FACTION") and qcFactionBits[string.upper(UnitFactionGroup("player") or "")]
            local raceFlag, classFlag
            if qcHides("L", "RACECLASS") then
                local _, playerRace = UnitRace("player")
                local _, playerClass = UnitClass("player")
                raceFlag = qcRaceBits[string.upper(playerRace)]
                classFlag = qcClassBits[string.upper(playerClass)]
            end
            local countWarband = qcHides("L", "WARBANDS")
            local lineQuests, position, done, total = {}, 1, 0, 0
            for _, lineQuestId in ipairs(storyline.quests) do
                local lineQuest = qcQuestDatabase[lineQuestId]
                if lineQuest and (lineQuestId == questId or ((not factionFlag or qcMaskAllows(lineQuest[5], factionFlag))
                        and (not raceFlag or qcMaskAllows(lineQuest[6], raceFlag))
                        and (not classFlag or qcMaskAllows(lineQuest[7], classFlag)))) then
                    table.insert(lineQuests, lineQuestId)
                    if lineQuestId == questId then
                        position = #lineQuests
                    end
                    if not qcRecurringQuestIcon(lineQuestId, lineQuest[4]) then
                        total = total + 1
                        if qcIsQuestCompleted(lineQuestId) or (countWarband and qcIsQuestCompletedOnAccount(lineQuestId)) then
                            done = done + 1
                        end
                    end
                end
            end
            qcQuestInformationTooltip:AddDoubleLine(stringFormat(STAT_FORMAT, QUEST_CLASSIFICATION_QUESTLINE), stringFormat("%s%s|r |cFF808080%s|r", COLOUR_HUNTER, storyline.name, stringFormat(qcL.STORYLINEPOSITION, position, #lineQuests)))
            if total >= 2 then
                qcQuestInformationTooltip:AddDoubleLine(" ", stringFormat("|cffc8c8c8%d/%d|r", done, total))
                local line = qcQuestInformationTooltip:NumLines()
                local leftText = _G["qcQuestInformationTooltipTextLeft" .. line]
                local rightText = _G["qcQuestInformationTooltipTextRight" .. line]
                if leftText and rightText then
                    qcTooltipBar.Show(qcQuestInformationTooltip, leftText, rightText, done, total)
                end
            end
            qcQuestInformationTooltip:AddLine(" ")

            local first = math.max(1, position - math.floor(QC_STORYLINE_WINDOW / 2))
            local last = math.min(#lineQuests, first + QC_STORYLINE_WINDOW - 1)
            first = math.max(1, last - QC_STORYLINE_WINDOW + 1)
            if first > 1 then
                qcQuestInformationTooltip:AddLine("|cFF808080   " .. stringFormat(qcL.EARLIERQUESTS, first - 1) .. "|r")
            end
            for i = first, last do
                local lineQuestId = lineQuests[i]
                local icon, colour = qcQuestStatus.Look(lineQuestId, qcQuestStatus.Of(lineQuestId, qcQuestDatabase[lineQuestId]))
                local text = stringFormat(" %s |cff%s%s|r", qcQuestStatus.IconText(icon, 14), colour, qcQuestName(lineQuestId, qcQuestTooltipWaiting))
                if lineQuestId == questId then
                    qcQuestInformationTooltip:AddDoubleLine(text, "|cff808080" .. qcL.THISQUEST .. "|r")
                else
                    qcQuestInformationTooltip:AddLine(text)
                end
            end
            if last < #lineQuests then
                qcQuestInformationTooltip:AddLine("|cFF808080   " .. stringFormat(qcL.LATERQUESTS, #lineQuests - last) .. "|r")
            end

            qcAddQuestTooltipDivider()
        elseif campaignName then
            qcAddQuestTooltipDivider()
        end

        -- The quests to do first, a line each; a choice of them shares a line.
        local prereqParts = qcPrereq.Parts(questId)
        if prereqParts then
            for i, part in ipairs(prereqParts) do
                qcQuestInformationTooltip:AddDoubleLine(i == 1 and qcL.REQUIREDQUEST or " ", qcPrereq.Text(part, qcPrereqQuestText, false))
            end
            qcAddQuestTooltipDivider()
        end
		-- Renown and Faction requirements Start
        local renownInfo = qcRenownLevelRequirements[questId]

        if renownInfo then
            if type(renownInfo) == "table" then
                local factionId = renownInfo[1]
                local requiredRenownLevel = renownInfo[2]
                local factionName = qcFactionName(factionId) or UNKNOWN
                local currentRenownLevel, isRank = qcFactionLevel(factionId)
                local levelLabel = isRank and qcL.REQUIREDRANK or qcL.REQUIREDRENOWN

                qcQuestInformationTooltip:AddDoubleLine(qcL.REQUIREDFACTION, string.format("%s%s%s", qcFactionIconText(factionId), COLOUR_DRUID, factionName))

                if currentRenownLevel then
                    local met = currentRenownLevel >= requiredRenownLevel
                    qcQuestInformationTooltip:AddDoubleLine(levelLabel, string.format("|A:%s:14:14|a |cff%s%d|r",
                        met and "common-icon-checkmark" or "common-icon-redx", met and "00ff00" or "ff2020", requiredRenownLevel))
                else
                    qcQuestInformationTooltip:AddDoubleLine(levelLabel, tostring(requiredRenownLevel))
                end
            elseif type(renownInfo) == "number" then
                local factionName = qcFactionName(renownInfo) or UNKNOWN
                qcQuestInformationTooltip:AddDoubleLine(qcL.REQUIREDFACTION, string.format("%s%s%s", qcFactionIconText(renownInfo), COLOUR_DRUID, factionName))
            end

            qcAddQuestTooltipDivider()
        end
		-- Renown and Faction requirements End

        -- The profession a quest needs, and the skill in it unless any will do.
        local skill = qcQuestSkillRequirements[questId]
        if skill then
            local skillText = skill[2] > 1 and string.format("%s (%d)", qcSkillName(skill[1]), skill[2]) or qcSkillName(skill[1])
            local rank = qcSkillRank(skill[1])
            if rank then
                local met = rank >= skill[2]
                qcQuestInformationTooltip:AddDoubleLine(qcL.REQUIREDSKILL, string.format("|A:%s:14:14|a |cff%s%s|r",
                    met and "common-icon-checkmark" or "common-icon-redx", met and "00ff00" or "ff2020", skillText))
            else
                qcQuestInformationTooltip:AddDoubleLine(qcL.REQUIREDSKILL, skillText)
            end
            qcAddQuestTooltipDivider()
        end

        -- Quest Giver Information from qcPinDB.lua: the pin a TomTom waypoint would go to
        local giverMapId, giverPin = qcFindPinForQuest(questId)
        if giverPin then
            qcQuestInformationTooltip:AddDoubleLine(
                qcL.QUESTGIVER,
                string.format("%s (%s, %.1f, %.1f)", qcNpcName(giverPin, qcNpcTooltipWaiting) or UNKNOWN,
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
            qcAddQuestTooltipDivider()
            qcQuestInformationTooltip:AddLine(GetText("COMBAT_TEXT_SHOW_REPUTATION_TEXT"))

            for _, factionId in ipairs(factionIds) do
                qcQuestInformationTooltip:AddDoubleLine(
                    "  " .. qcFactionIconText(factionId) .. (qcFactionName(factionId) or tostring(factionId)),
                    COLOUR_DRUID .. stringFormat(qcL.REPAMOUNT, reputationEntries[factionId])
                )
            end
        end

        -- Make sure the main tooltip is shown
        qcQuestInformationTooltip:Show()
    end
end

-- End Tooltip when mouse over quest name

function qcCloseTooltip()
	qcTooltipIndex = nil
	qcTooltipQuestId = nil
	qcQuestInformationTooltip:Hide()
end

function qcQuestInformationTooltipSetup() -- *
	qcQuestInformationTooltip = CreateFrame("GameTooltip", "qcQuestInformationTooltip", qcQuestCompletistUI, "GameTooltipTemplate")
	qcQuestInformationTooltip:SetFrameStrata("TOOLTIP")
end


-- For qcCore.lua, when quest or NPC names arrive: redraw the tooltip if its row still shows its quest.
function QC.RedrawQuestTooltip()
	if qcTooltipIndex and _G["qcMenuButton" .. qcTooltipIndex].QuestID == qcTooltipQuestId then
		qcUpdateTooltip(qcTooltipIndex)
	end
end

function QC.IsTooltipQuest(questId)
	return questId == qcTooltipQuestId
end

QC.qcQuestStatus = qcQuestStatus
QC.qcTooltipBar, QC.qcTooltipDivider = qcTooltipBar, qcTooltipDivider
QC.qcFactionName = qcFactionName
