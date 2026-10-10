--[[ Zone icons on the continent maps (docs/plans/continent-pins.md): the zones a continent map gets an icon
for, the quest list's categories each one counts, and what is left to do in it. What it needs from the other
files comes through the addon's own table. ]]--
local QC = select(2, ...)
local qcQuestStatus, qcZoneQuests, qcPinQuestNeeds = QC.qcQuestStatus, QC.qcZoneQuests, QC.qcPinQuestNeeds
local qcIsQuestCompletedOnAccount = QC.qcIsQuestCompletedOnAccount
local qcBuildViewFilter, qcHides = QC.qcBuildViewFilter, QC.qcHides
local qcMapTip, qcSetIcon = QC.qcMapTip, QC.qcSetIcon
local QC_ICON_NORMAL, QC_ICON_READY, QC_ICON_PROGRESS = QC.QC_ICON_NORMAL, QC.QC_ICON_READY, QC.QC_ICON_PROGRESS

-- Zones whose quests the list files under the categories of their parts, as well as under their own, if
-- they have one. Both games' map IDs: retail's are Stranglethorn Vale (Northern Stranglethorn, The Cape of
-- Stranglethorn), Vashj'ir (Kelp'thar Forest, Shimmering Expanse, Abyssal Depths) and Arathi Highlands
-- (its other map, 2372, which the game gives no rectangle).
local QC_ZONE_EXTRA_CATEGORIES = {
	[224] = {147, 214},
	[203] = {117, 182, 1},
	[14] = {1409},
}

-- A city's map and the zone it sits in, which get one icon between them: Stormwind City and Elwynn Forest,
-- Ironforge and Dun Morogh, Undercity and Tirisfal Glades, Silvermoon City and Eversong Woods, Thunder
-- Bluff and Mulgore, Darnassus and Teldrassil, the Exodar and Azuremyst Isle; Forever's Stormwind,
-- Ironforge, Undercity, Thunder Bluff and Darnassus. A city with no such zone on the map keeps its own icon.
local QC_CITY_HOST = {
	[84] = 37, [87] = 27, [90] = 18, [110] = 94, [88] = 7, [89] = 57, [103] = 97,
	[1453] = 1429, [1455] = 1426, [1458] = 1420, [1456] = 1412, [1457] = 1438,
}

-- Zones whose icon sits somewhere of its own rather than at the centre of its rectangle, because that centre
-- looked wrong on the map. Tiragarde Sound's is the centre of the cells the game's hit test names it on (the
-- CentroidX and CentroidY of its row in docs/plans/continent-geometry-baseline.csv, over 100); its rectangle
-- takes in sea off Drustvar's edge, 0.476, 0.645. Darkshore's and Felwood's on both games are nudged left by eye.
local QC_ZONE_ICON_AT = {
	[895] = {0.574, 0.631},
	[62] = {0.458, 0.254}, [77] = {0.485, 0.289},
	[1439] = {0.463, 0.271}, [1448] = {0.485, 0.309},
}

-- Maps that stand on a continent map without being one of its zones, each with the icon's place: the centre of
-- the cells the game's hit test names it on (CentroidX and CentroidY of its row in
-- docs/plans/continent-geometry-baseline.csv, over 100). Retail's Oribos (a hub city of the Shadowlands) and
-- Dalaran (of the Broken Isles), Undermine (a map the client links in at the Ringing Deeps' side of Khaz Algar),
-- Nazjatar (linked in on both Zandalar and Kul Tiras) and Ahn'Qiraj: The Fallen Kingdom (an orphan map on
-- Kalimdor). Keyed by continent, then by the map; the click opens that map.
local QC_CONTINENT_HUBS = {
	[12] = {[327] = {0.414, 0.895}},
	[619] = {[627] = {0.458, 0.650}},
	[875] = {[1355] = {0.867, 0.150}},
	[876] = {[1355] = {0.867, 0.150}},
	[1550] = {[1670] = {0.467, 0.488}},
	[2274] = {[2346] = {0.800, 0.750}},
}

-- Sub-zones with no icon of their own, whose quests count in the icon of the zone they lie in, as a city's do:
-- Korthia in The Maw, Valdrakken in Thaldraszus, Dornogal in the Isle of Dorn, both levels of City of Threads
-- in Azj-Kahet, Silvermoon City and Slayer's Rise in the zones of Quel'Thalas that hold them, the Shrine of
-- the Storm in Stormsong Valley, the Druid class hall's Dreamgrove in Val'sharah. Each is a descendant of the
-- continent the game lists, not a child.
local QC_SUBZONE_HOST = {
	[1961] = 1543, [2112] = 2025, [2339] = 2248, [2213] = 2255, [2216] = 2255, [2393] = 2395, [2444] = 2405, [1039] = 942,
	[747] = 641,
}

local function qcSortedKeys(t)
	local keys = {}
	for key in pairs(t) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end
local QC_SUBZONES = qcSortedKeys(QC_SUBZONE_HOST)

local function qcRectCentre(zoneId, continentId)
	local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(zoneId, continentId)
	if type(minX) == "number" and type(maxX) == "number" and type(minY) == "number" and type(maxY) == "number"
			and maxX > minX and maxY > minY then
		return (minX + maxX) / 2, (minY + maxY) / 2
	end
end

-- What the game lists as children of a map, of one type, in map ID order. The game may list nothing.
local function qcChildrenOfType(mapId, mapType)
	local listed = C_Map.GetMapChildrenInfo(mapId, mapType)
	if type(listed) ~= "table" then return {} end
	local children = {}
	for _, child in ipairs(listed) do
		if child.mapType == mapType then children[#children + 1] = child end
	end
	table.sort(children, function(a, b) return a.mapID < b.mapID end)
	return children
end

-- The icons a continent map gets, in map ID order: {mapId, name, x, y, categories} for each zone the game
-- lists as a child of the continent, with a rectangle on it and a category. The game may list nothing, or
-- a rectangle of nothing. Zones sharing a category are one icon: the first with a rectangle. A city in
-- QC_CITY_HOST adds its categories to its zone's icon, and a sub-zone in QC_SUBZONE_HOST to its zone's. A map in
-- QC_CONTINENT_HUBS gets an icon at its place. A continent the game lists inside this one (Quel'Thalas on
-- Eastern Kingdoms, Argus on the Broken Isles) gets an icon too, counting the zones of its own map, less any
-- this map's zones count already; it is not looked into further (inside is set for it).
local function qcContinentZones(continentId, inside)
	local children = qcChildrenOfType(continentId, Enum.UIMapType.Zone)

	local zones, byId, owned, cities = {}, {}, {}, {}
	local function addZone(child, categories, place)
		local x, y
		if place then x, y = place[1], place[2] else x, y = qcRectCentre(child.mapID, continentId) end
		if not x or owned[categories[1]] then return end
		local at = not place and QC_ZONE_ICON_AT[child.mapID]
		if at then x, y = at[1], at[2] end
		local zone = {mapId = child.mapID, name = child.name, x = x, y = y, categories = categories}
		zones[#zones + 1] = zone
		byId[child.mapID] = zone
		for _, categoryId in ipairs(categories) do owned[categoryId] = true end
	end
	local function categoriesOf(mapId)
		local categories = {}
		if qcAreaIDToCategoryID[mapId] then categories[1] = qcAreaIDToCategoryID[mapId] end
		for _, categoryId in ipairs(QC_ZONE_EXTRA_CATEGORIES[mapId] or {}) do categories[#categories + 1] = categoryId end
		return categories
	end
	for _, child in ipairs(children) do
		local categories = categoriesOf(child.mapID)
		if #categories > 0 then
			if QC_CITY_HOST[child.mapID] then
				cities[#cities + 1] = {child = child, categories = categories}
			else
				addZone(child, categories)
			end
		end
	end
	for _, city in ipairs(cities) do
		local host = byId[QC_CITY_HOST[city.child.mapID]]
		if host then
			for _, categoryId in ipairs(city.categories) do
				if not owned[categoryId] then
					host.categories[#host.categories + 1] = categoryId
					owned[categoryId] = true
				end
			end
		else
			addZone(city.child, city.categories)
		end
	end
	for _, subZone in ipairs(QC_SUBZONES) do
		local host = byId[QC_SUBZONE_HOST[subZone]]
		if host then
			for _, categoryId in ipairs(categoriesOf(subZone)) do
				if not owned[categoryId] then
					host.categories[#host.categories + 1] = categoryId
					owned[categoryId] = true
				end
			end
		end
	end
	local hubs = QC_CONTINENT_HUBS[continentId]
	if hubs then
		for _, mapId in ipairs(qcSortedKeys(hubs)) do
			local info, categories = C_Map.GetMapInfo(mapId), categoriesOf(mapId)
			if info and #categories > 0 then addZone(info, categories, hubs[mapId]) end
		end
	end
	if not inside then
		for _, continent in ipairs(qcChildrenOfType(continentId, Enum.UIMapType.Continent)) do
			local categories, counted = {}, {}
			local function take(categoryId)
				if not owned[categoryId] and not counted[categoryId] then
					counted[categoryId] = true
					categories[#categories + 1] = categoryId
				end
			end
			for _, categoryId in ipairs(categoriesOf(continent.mapID)) do take(categoryId) end
			for _, zone in ipairs(qcContinentZones(continent.mapID, true)) do
				for _, categoryId in ipairs(zone.categories) do take(categoryId) end
			end
			if #categories > 0 then addZone(continent, categories) end
		end
	end
	table.sort(zones, function(a, b) return a.mapId < b.mapId end)
	return zones
end

-- How one counted quest stands: "done" (this character's, or another's while the warband filter counts it),
-- "ready" to hand in, "progress" in the log, "locked" behind a level, a quest or a requirement, or
-- "available".
local function qcQuestKind(questId, countWarband)
	local state = qcQuestStatus.Of(questId, qcQuestDatabase[questId])
	if state == qcQuestStatus.READY then return "ready" end
	if state == qcQuestStatus.PROGRESS then return "progress" end
	if state == qcQuestStatus.DONE or (countWarband and qcIsQuestCompletedOnAccount(questId)) then return "done" end
	if qcPinQuestNeeds(questId, state, true) then return "locked" end
	return "available"
end

-- What is left to do in a zone: total, done, ready, progress, locked and available, from the quests that
-- count (qcZoneQuests) and a filter built once for the whole map.
local function qcZoneNumbers(zone, keepQuest, countWarband)
	local numbers = {total = 0, done = 0, ready = 0, progress = 0, locked = 0, available = 0}
	for _, questId in ipairs(qcZoneQuests(zone.categories, keepQuest)) do
		local kind = qcQuestKind(questId, countWarband)
		numbers.total = numbers.total + 1
		numbers[kind] = numbers[kind] + 1
	end
	return numbers
end

-- The icon a zone gets from what is left to do in it, and the count on it: the quests ready to hand in, else
-- the ones that can be taken, else the locked ones (dimmed), else the ones in the log. Nothing is returned when
-- nothing is left.
local function qcZoneLook(numbers)
	if numbers.ready > 0 then return QC_ICON_READY, numbers.ready, false end
	if numbers.available > 0 then return QC_ICON_NORMAL, numbers.available, false end
	if numbers.locked > 0 then return QC_ICON_NORMAL, numbers.locked, true end
	if numbers.progress > 0 then return QC_ICON_PROGRESS, numbers.progress, false end
end

-- The icons a continent map draws now: each zone with something left to do, with its look, count and shade.
local function qcContinentIcons(continentId)
	local keepQuest, countWarband = qcBuildViewFilter("M"), qcHides("M", "WARBANDS")
	local icons = {}
	for _, zone in ipairs(qcContinentZones(continentId)) do
		local look, count, dim = qcZoneLook(qcZoneNumbers(zone, keepQuest, countWarband))
		if look then icons[#icons + 1] = {zone = zone, look = look, count = count, dim = dim} end
	end
	return icons
end

-- How large the icon is drawn, in UI units. Its art is the quest atlas's 32-pixel "?" (the "!" is a 64-pixel one, the
-- grey "?" the game files separately only 16), so it is drawn at no more than 1.1 screen pixels to a pixel of
-- art, where the screen allows: a unit is the UI scale times the screen's height over 768 pixels. The old 24
-- stays on a screen that needs it, and where the screen can't be read.
local QC_ICON_MIN, QC_ICON_MAX, QC_ICON_ART_PIXELS = 24, 32, 32
local function qcContinentIconSize()
	local _, height = GetPhysicalScreenSize()
	local scale = UIParent:GetEffectiveScale()
	if type(height) ~= "number" or height <= 0 or type(scale) ~= "number" or scale <= 0 then return QC_ICON_MIN end
	local size = math.floor(QC_ICON_ART_PIXELS * 1.1 * 768 / (scale * height))
	return math.max(QC_ICON_MIN, math.min(QC_ICON_MAX, size))
end

qcContinentPinMixin = CreateFromMixins(MapCanvasPinMixin)

function qcContinentPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.0)
end

function qcContinentPinMixin:OnAcquired(icon)
	self.Icon = icon
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetPosition(icon.zone.x, icon.zone.y)
	local size = qcContinentIconSize()
	self:SetSize(size, size)
	local progress = icon.look == QC_ICON_PROGRESS
	qcSetIcon(self.Texture, progress and QC_ICON_READY or icon.look)
	self.Texture:SetDesaturated(progress)
	local shade = icon.dim and 0.5 or 1
	self.Texture:SetVertexColor(shade, shade, shade)
	self.Count:SetFontObject(size >= 30 and "NumberFontNormalLarge" or size >= 26 and "NumberFontNormal" or "NumberFontNormalSmall")
	self.Count:SetText(icon.count)
	self.Count:SetTextColor(shade, shade, shade)
end

-- The rows of the tooltip, in order: what each says, in the game's words, with its colour and icon.
local QC_CONTINENT_ROWS = {
	{key = "ready", text = QUEST_WATCH_QUEST_READY, colour = "ffd100", icon = QC_ICON_READY},
	{key = "available", text = AVAILABLE_QUESTS, colour = "ffffff", icon = QC_ICON_NORMAL},
	{key = "locked", text = UNAVAILABLE, colour = "9d9d9d", icon = QC_ICON_NORMAL, dim = true},
	{key = "progress", text = IN_PROGRESS, colour = "949694", icon = QC_ICON_PROGRESS},
}

-- The zone's name, what is done of it, a row for each state with quests in it, and what a click does. The
-- numbers are counted now, not when the icon was drawn: a quest changes state without the map refreshing.
function qcContinentPinMixin:OnMouseEnter()
	local icon = self.Icon
	if not icon then return end
	local zone = icon.zone
	local anchorPoint = "ANCHOR_RIGHT"
	if zone.x > 0.75 then anchorPoint = "ANCHOR_LEFT" end
	if zone.y > 0.75 then anchorPoint = "ANCHOR_BOTTOM" end
	qcMapTip.Open(self, anchorPoint)
	local numbers = qcZoneNumbers(zone, qcBuildViewFilter("M"), qcHides("M", "WARBANDS"))
	qcMapTip.Line(zone.name, nil, GameTooltipHeaderText)
	if numbers.total >= 2 then
		local leftText, rightText = qcMapTip.Line(" ", string.format("|cffc8c8c8%d/%d|r", numbers.done, numbers.total))
		if leftText and rightText then
			qcMapTip.Bar(leftText, rightText, numbers.done, numbers.total)
		end
	end
	for _, row in ipairs(QC_CONTINENT_ROWS) do
		local count = numbers[row.key]
		if count > 0 then
			local leftText = qcMapTip.Line(string.format("    |cff%s%s|r", row.colour, row.text),
				string.format("|cff%s%d|r", row.colour, count))
			qcMapTip.LineIcon(leftText, row.icon, row.dim)
		end
	end
	qcMapTip.Line("|cff808080" .. FLIGHT_MAP_CLICK_TO_ZOOM_IN .. "|r", nil, GameTooltipTextSmall)
	qcMapTip.Finish()
end

function qcContinentPinMixin:OnMouseLeave()
	qcMapTip.Close()
end

-- A left click opens the zone's map. The map hands a pin's clicks to OnMouseClickAction and its right-clicks
-- to itself, to zoom out.
function qcContinentPinMixin:OnMouseClickAction(button)
	if button ~= "LeftButton" or IsModifierKeyDown() then return end
	local icon, map = self.Icon, self:GetMap()
	if icon and map then
		map:SetMapID(icon.zone.mapId)
	end
end

qcContinentDataProvider = CreateFromMixins(MapCanvasDataProviderMixin)

function qcContinentDataProvider:RemoveAllData()
	if self:GetMap() then
		self:GetMap():RemoveAllPinsByTemplate("qcContinentPinTemplate")
	end
end

-- Zone icons on a continent's map, when the map icons and this kind of them are on.
function qcContinentDataProvider:RefreshAllData()
	if not self:GetMap() then return end
	self:RemoveAllData()

	if qcSettings.QC_M_SHOW_ICONS == 0 or qcSettings.QC_M_SHOW_CONTINENT == 0 then return end

	local mapId = self:GetMap():GetMapID()
	local info = mapId and C_Map.GetMapInfo(mapId)
	if not (info and info.mapType == Enum.UIMapType.Continent) then return end

	for _, icon in ipairs(qcContinentIcons(mapId)) do
		self:GetMap():AcquirePin("qcContinentPinTemplate", icon)
	end
end

WorldMapFrame:AddDataProvider(qcContinentDataProvider)
