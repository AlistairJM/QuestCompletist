--[[ The quest list's tooltip, and the quest status and progress bar helpers it shares with the map
pins' tooltip in qcMapPins.lua. What it needs from qcCore.lua comes through the addon's own table. ]]--
local QC = select(2, ...)
local qcL = qcLocalize
local COLOUR_DRUID, COLOUR_HUNTER = QC.COLOUR_DRUID, QC.COLOUR_HUNTER
local QC_ICON_NORMAL, QC_ICON_READY, QC_ICON_PROGRESS = QC.QC_ICON_NORMAL, QC.QC_ICON_READY, QC.QC_ICON_PROGRESS
local QC_ICON_COMPLETE, QC_ICON_UNATTAINABLE = QC.QC_ICON_COMPLETE, QC.QC_ICON_UNATTAINABLE
local QC_FULL_TEXCOORDS = QC.QC_FULL_TEXCOORDS
local qcRecurringQuestIcon, qcIsQuestCompleted, qcIsQuestCompletedOnAccount = QC.qcRecurringQuestIcon, QC.qcIsQuestCompleted, QC.qcIsQuestCompletedOnAccount
local qcMaskAllows, qcQuestName, qcRequestQuestData = QC.qcMaskAllows, QC.qcQuestName, QC.qcRequestQuestData
local qcNpcName, qcFindPinForQuest = QC.qcNpcName, QC.qcFindPinForQuest
local qcQuestTooltipWaiting, qcNpcTooltipWaiting = QC.qcQuestTooltipWaiting, QC.qcNpcTooltipWaiting

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
        qcTooltipBar.HideAll(qcQuestInformationTooltip)
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
            -- Older zones share one storyline between both factions, and a class's quests sit
            -- beside every other class's: follow the list's faction and race/class filters. The
            -- progress counts like the map's, leaving out recurring quests.
            local factionFlag = (qcSettings.QC_ML_HIDE_FACTION == 1) and qcFactionBits[string.upper(UnitFactionGroup("player") or "")]
            local raceFlag, classFlag
            if (qcSettings.QC_ML_HIDE_RACECLASS == 1) then
                local _, playerRace = UnitRace("player")
                local _, playerClass = UnitClass("player")
                raceFlag = qcRaceBits[string.upper(playerRace)]
                classFlag = qcClassBits[string.upper(playerClass)]
            end
            local countWarband = (qcSettings.QC_ML_HIDE_WARBANDS == 1)
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
            qcQuestInformationTooltip:AddDoubleLine(qcL.STORYLINE, stringFormat("%s%s|r |cFF808080%s|r", COLOUR_HUNTER, storyline.name, stringFormat(qcL.STORYLINEPOSITION, position, #lineQuests)))
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

            qcQuestInformationTooltip:AddLine(" ")
        end

        -- Prerequisite quest logic
        local prereqQuestId = qcQuestPrereq[questId]
        if prereqQuestId and prereqQuestId ~= 0 then
            local prereqQuestName = qcQuestName(prereqQuestId, qcQuestTooltipWaiting) or qcL.UNKNOWNQUEST
            local prereqData = qcQuestDatabase[prereqQuestId]
            local icon, colour
            if prereqData then
                icon, colour = qcQuestStatus.Look(prereqQuestId, qcQuestStatus.Of(prereqQuestId, prereqData))
            elseif C_QuestLog.IsQuestFlaggedCompleted(prereqQuestId) then
                icon, colour = QC_ICON_COMPLETE, "00ff00"
            else
                icon, colour = QC_ICON_NORMAL, "ffffff"
            end
            qcQuestInformationTooltip:AddDoubleLine(qcL.REQUIREDQUEST, stringFormat("%s |cff%s%s|r", qcQuestStatus.IconText(icon, 14), colour, prereqQuestName))
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
QC.qcTooltipBar = qcTooltipBar
