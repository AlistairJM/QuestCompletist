--[[ Zone icons on the continent maps (docs/plans/continent-pins.md): the zones a continent map gets an icon
for, the quest list's categories each one counts, and what is left to do in it. What it needs from the other
files comes through the addon's own table. ]]--
local QC = select(2, ...)
local qcQuestStatus, qcZoneQuests, qcPinQuestNeeds = QC.qcQuestStatus, QC.qcZoneQuests, QC.qcPinQuestNeeds
local qcIsQuestCompletedOnAccount = QC.qcIsQuestCompletedOnAccount
local qcBuildViewFilter, qcHides = QC.qcBuildViewFilter, QC.qcHides

-- Zones whose quests the list files under the categories of their parts, as well as under their own, if
-- they have one. Both games' map IDs: retail's are Stranglethorn Vale (Northern Stranglethorn, The Cape of
-- Stranglethorn) and Vashj'ir (Kelp'thar Forest, Shimmering Expanse, Abyssal Depths).
local QC_ZONE_EXTRA_CATEGORIES = {
	[224] = {147, 214},
	[203] = {117, 182, 1},
}

-- A city's map and the zone it sits in, which get one icon between them: Stormwind City and Elwynn Forest,
-- Ironforge and Dun Morogh, Undercity and Tirisfal Glades, Silvermoon City and Eversong Woods, Thunder
-- Bluff and Mulgore, Darnassus and Teldrassil, the Exodar and Azuremyst Isle; Forever's Stormwind,
-- Ironforge, Undercity, Thunder Bluff and Darnassus. A city with no such zone on the map keeps its own icon.
local QC_CITY_HOST = {
	[84] = 37, [87] = 27, [90] = 18, [110] = 94, [88] = 7, [89] = 57, [103] = 97,
	[1453] = 1429, [1455] = 1426, [1458] = 1420, [1456] = 1412, [1457] = 1438,
}

local function qcRectCentre(zoneId, continentId)
	local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(zoneId, continentId)
	if type(minX) == "number" and type(maxX) == "number" and type(minY) == "number" and type(maxY) == "number"
			and maxX > minX and maxY > minY then
		return (minX + maxX) / 2, (minY + maxY) / 2
	end
end

-- The icons a continent map gets, in map ID order: {mapId, name, x, y, categories} for each zone the game
-- lists as a child of the continent, with a rectangle on it and a category. The game may list nothing, or
-- a rectangle of nothing. Zones sharing a category are one icon: the first with a rectangle. A city in
-- QC_CITY_HOST adds its categories to its zone's icon.
local function qcContinentZones(continentId)
	local listed = C_Map.GetMapChildrenInfo(continentId, Enum.UIMapType.Zone)
	if type(listed) ~= "table" then return {} end
	local children = {}
	for _, child in ipairs(listed) do
		if child.mapType == Enum.UIMapType.Zone then children[#children + 1] = child end
	end
	table.sort(children, function(a, b) return a.mapID < b.mapID end)

	local zones, byId, owned, cities = {}, {}, {}, {}
	local function addZone(child, categories)
		local x, y = qcRectCentre(child.mapID, continentId)
		if not x or owned[categories[1]] then return end
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

-- Whether a zone gets an icon, and how bright it is: nil when nothing is left to do, true when a quest is
-- ready to hand in or can be taken, false when only quests in the log or locked ones are left.
local function qcZoneBrightness(zone, keepQuest, countWarband)
	local left = false
	for _, questId in ipairs(qcZoneQuests(zone.categories, keepQuest)) do
		local kind = qcQuestKind(questId, countWarband)
		if kind == "ready" or kind == "available" then return true end
		if kind ~= "done" then left = true end
	end
	if left then return false end
	return nil
end

-- The icons a continent map draws now: each zone with something left to do, and whether it is bright.
local function qcContinentIcons(continentId)
	local keepQuest, countWarband = qcBuildViewFilter("M"), qcHides("M", "WARBANDS")
	local icons = {}
	for _, zone in ipairs(qcContinentZones(continentId)) do
		local bright = qcZoneBrightness(zone, keepQuest, countWarband)
		if bright ~= nil then icons[#icons + 1] = {zone = zone, bright = bright} end
	end
	return icons
end
