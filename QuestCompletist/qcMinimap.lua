local qcL = qcLocalize
local qcDBIcon = LibStub("LibDBIcon-1.0")

local QC_MINIMAP_NAME = "QuestCompletist"
local QC_MINIMAP_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

local function qcMinimapClick(_, button)
	if button == "RightButton" then
		Settings.OpenToCategory(qcInterfaceOptions.category:GetID())
	elseif qcQuestCompletistUI:IsShown() then
		qcQuestCompletistUI:Hide()
	else
		qcQuestCompletistUI:Show()
	end
end

local function qcMinimapTooltip(tooltip)
	tooltip:AddLine("Quest Completist", 1, 0.82, 0)
	tooltip:AddLine(qcL.MINIMAPLEFTCLICK, 1, 1, 1)
	tooltip:AddLine(qcL.MINIMAPRIGHTCLICK, 1, 1, 1)
	tooltip:AddLine(qcL.MINIMAPDRAG, 1, 1, 1)
end

-- qcMinimapIcon is saved per character and holds the button's angle; whether the button shows is
-- one account-wide setting, copied into it for the library.
function qcCreateMinimapButton()
	qcMinimapIcon = qcMinimapIcon or {}
	qcMinimapIcon.hide = qcSettings.QC_MINIMAP_SHOW == 0
	local dataObject = LibStub("LibDataBroker-1.1"):NewDataObject(QC_MINIMAP_NAME, {
		type = "launcher",
		text = "Quest Completist",
		icon = QC_MINIMAP_ICON,
		OnClick = qcMinimapClick,
		OnTooltipShow = qcMinimapTooltip,
	})
	qcDBIcon:Register(QC_MINIMAP_NAME, dataObject, qcMinimapIcon)
	qcDBIcon:AddButtonToCompartment(QC_MINIMAP_NAME)
end

function qcShowMinimapButton(shown)
	qcSettings.QC_MINIMAP_SHOW = shown and 1 or 0
	qcMinimapIcon.hide = not shown
	qcDBIcon:Refresh(QC_MINIMAP_NAME)
end
