-- Reports what the Forever probe's map pass gathered (/qcprobe maps; docs/plans/game-api-review.md,
-- recommendation 3): the quest offers, points of interest, events, quest hubs and dungeon entrances
-- the game lists for each map, checked against the addon's quests and pins.
-- usage: lua tools/Report-MapOffers.lua <QCForeverProbe.lua> <addon folder> [report.tsv]
--   addon folder: QuestCompletist\Forever for the beta's file, QuestCompletist for retail's.
-- Prints the summary, and writes one TSV row per offer, point of interest, event, hub and entrance:
--   map  mapName  kind  id  name  x  y  details  inData  pinOnMap  nearestPin  pinNpc  anyPin
-- An offer's pin columns say whether the quest is in the addon's data, whether a pin on that map
-- carries it, how far (in map points) the nearest such pin is and whose it is, and whether the
-- quest has a pin on any map.

local savedFile, addonDir, tsvFile = arg[1], arg[2], arg[3]
if not savedFile or not addonDir then
	io.stderr:write("usage: lua tools/Report-MapOffers.lua <QCForeverProbe.lua> <addon folder> [report.tsv]\n")
	os.exit(2)
end

dofile(savedFile)
local db = QCForeverProbeDB or error("no QCForeverProbeDB in " .. savedFile)
dofile(addonDir .. "/qcQuestData.lua")
dofile(addonDir .. "/qcPinDB.lua")
local quests = qcQuestDatabase or error("no qcQuestDatabase in " .. addonDir)
local pinDB = qcPinDB or error("no qcPinDB in " .. addonDir)

local pinsByQuest = {}
for mapID, pins in pairs(pinDB) do
	for _, pin in ipairs(pins) do
		for _, questID in ipairs(pin[6] or {}) do
			pinsByQuest[questID] = pinsByQuest[questID] or {}
			table.insert(pinsByQuest[questID], {map = mapID, x = pin[4], y = pin[5], npc = pin[2], name = pin[3]})
		end
	end
end

local function sortedKeys(t)
	local keys = {}
	for key in pairs(t or {}) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function text(value)
	if value == nil then return "" end
	if type(value) == "boolean" then return value and "yes" or "no" end
	return (tostring(value):gsub("[\t\r\n]", " "))
end

local function flags(entry, names)
	local on = {}
	for _, name in ipairs(names) do
		if entry[name] then on[#on + 1] = name end
	end
	return table.concat(on, " ")
end

local function nearestPin(questID, mapID, x, y)
	local nearest, distance
	for _, pin in ipairs(pinsByQuest[questID] or {}) do
		if pin.map == mapID and x and y then
			local d = math.sqrt((pin.x - x) ^ 2 + (pin.y - y) ^ 2)
			if not distance or d < distance then nearest, distance = pin, d end
		end
	end
	return nearest, distance
end

local rows = {}
local function row(mapID, mapName, kind, id, name, x, y, details, questID)
	local inData, pinOnMap, nearest, pinNpc, anyPin = "", "", "", "", ""
	if questID then
		inData = quests[questID] and "yes" or "no"
		anyPin = pinsByQuest[questID] and "yes" or "no"
		local pin, distance = nearestPin(questID, mapID, x, y)
		pinOnMap = pin and "yes" or "no"
		if pin then
			nearest = string.format("%.1f", distance)
			pinNpc = pin.name or (pin.npc and tostring(pin.npc)) or ""
		end
	end
	rows[#rows + 1] = table.concat({text(mapID), text(mapName), kind, text(id), text(name), text(x), text(y), text(details),
		inData, pinOnMap, nearest, pinNpc, anyPin}, "\t")
	return inData, pinOnMap, nearest, anyPin
end

local function timeText(epoch)
	if type(epoch) ~= "number" then return "" end
	return os.date("!%Y-%m-%d %H:%M", epoch)
end

local function presetText(preset)
	if preset == 0 then return "Classic" elseif preset == 1 then return "Modern" elseif preset == nil then return "none" end
	return tostring(preset)
end

-- The runs
local runs = {}
for _, r in ipairs(db.runs or {}) do
	if r.kind == "maps" then runs[#runs + 1] = r end
end
if #runs == 0 and not next(db.maps or {}) then
	print("No map pass in " .. savedFile .. ": run /qcprobe maps in the game first.")
	os.exit(0)
end
for _, r in ipairs(runs) do
	print(string.format("Map pass on %s (%s), %s, %s level %s, preset %s%s, wait %s s: %d maps asked, %d answered (%s) in %d s%s.",
		text(r.build), text(r.locale), timeText(r.time), text(r.character), text(r.level), presetText(r.preset),
		r.hardcore and ", hardcore" or "", text(r.waitSeconds), r.asked or 0, r.answered or 0,
		(function() local parts = {} for _, k in ipairs(sortedKeys(r.counts)) do parts[#parts + 1] = k .. " " .. r.counts[k] end return table.concat(parts, ", ") end)(),
		r.seconds or 0, r.stopped and ", stopped early" or ""))
	local function recorded(value) return value == nil and "not recorded" or text(value) end
	print(string.format("  Settings: quest points of interest (questPOI) %s; tracking trivial quests %s, account-completed quests %s, quest POIs on the minimap %s.",
		recorded(r.questPoiSetting), text(r.trackingHidden), text(r.trackingAccountDone), recorded(r.trackingQuestPois)))
	local s = r.scheduler
	if not s then
		print("  Events schedule: not read.")
	elseif s.missing then
		print("  Events schedule: the client has no C_EventScheduler.")
	else
		print(string.format("  Events schedule (%s): has data %s, can show %s, continent %s; %d ongoing, %d scheduled.",
			r.schedulerEvent and "answered" or "no update event", text(s.hasData), text(s.canShow), text(s.continent),
			#(s.ongoing or {}), #(s.scheduled or {})))
		for _, e in ipairs(s.ongoing or {}) do
			print(string.format("    ongoing: POI %s %s in %s (map %s)", text(e.areaPoiID), text(e.name), text(e.zone), text(e.map)))
		end
		for _, e in ipairs(s.scheduled or {}) do
			print(string.format("    scheduled: event %s POI %s %s in %s (map %s), %s to %s", text(e.eventID), text(e.areaPoiID),
				text(e.name), text(e.zone), text(e.map), timeText(e.startTime), timeText(e.endTime)))
		end
	end
end

-- The maps
local totals = {maps = 0, byResult = {}, offers = 0, offersInData = 0, offersNoData = {}, offersNoPin = {}, within = 0,
	near = 0, far = 0, elsewhere = 0, forced = 0, tasks = 0, logQuests = 0, pois = 0, namedPois = 0, events = 0, hubs = 0,
	entrances = 0, levels = 0, waypoint = 0, otherMapStart = 0}
local mapTypeNames = {[0] = "cosmic", "world", "continent", "zone", "dungeon", "micro", "orphan"}

for _, mapID in ipairs(sortedKeys(db.maps)) do
	local m = db.maps[mapID]
	totals.maps = totals.maps + 1
	totals.byResult[m.result or "?"] = (totals.byResult[m.result or "?"] or 0) + 1
	local lines, forced, tasks, logQuests = m.questLines or {}, m.forceVisible or {}, m.tasks or {}, m.logQuests or {}
	local pois, events, hubs, entrances = m.pois or {}, m.events or {}, m.hubs or {}, m.entrances or {}
	local parts = {}
	if #lines > 0 then parts[#parts + 1] = #lines .. " offers" end
	if #forced > 0 then parts[#parts + 1] = #forced .. " forced" end
	if #tasks > 0 then parts[#parts + 1] = #tasks .. " tasks" end
	if #logQuests > 0 then parts[#parts + 1] = #logQuests .. " log quests" end
	if #pois > 0 then parts[#parts + 1] = #pois .. " POIs" end
	if #events > 0 then parts[#parts + 1] = #events .. " events" end
	if #hubs > 0 then parts[#parts + 1] = #hubs .. " hubs" end
	if #entrances > 0 then parts[#parts + 1] = #entrances .. " entrances" end
	print(string.format("map %s %s (%s, parent %s): %s%s%s; levels %s; waypoint %s; %s.", text(mapID), text(m.name),
		mapTypeNames[m.mapType] or text(m.mapType), text(m.parent), text(m.result), m.ms and (" in " .. m.ms .. " ms") or "",
		(m.requests or 0) > 1 and (", " .. m.requests .. " requests") or "",
		m.levels and (m.levels[1] .. "-" .. m.levels[2]) or "none", text(m.waypoint),
		#parts > 0 and table.concat(parts, ", ") or "nothing"))
	if m.levels then totals.levels = totals.levels + 1 end
	if m.waypoint then totals.waypoint = totals.waypoint + 1 end
	for _, q in ipairs(lines) do
		totals.offers = totals.offers + 1
		local details = string.format("storyline %s %s; start map %s; %s", text(q.questLineID), text(q.questLineName),
			text(q.startMapID), flags(q, {"hidden", "accountDone", "inProgress", "campaign", "important", "legendary", "daily", "meta", "localStory", "questStart"}))
		local inData, pinOnMap, nearest, anyPin = row(mapID, m.name, "offer", q.questID, q.questName, q.x, q.y, details, q.questID)
		local note
		if inData == "yes" then
			totals.offersInData = totals.offersInData + 1
			if pinOnMap == "yes" then
				local d = tonumber(nearest)
				if d <= 1.5 then totals.within = totals.within + 1; note = "pin within 1.5"
				elseif d <= 3 then totals.near = totals.near + 1; note = "pin " .. nearest .. " away"
				else totals.far = totals.far + 1; note = "pin " .. nearest .. " away" end
			elseif anyPin == "yes" then
				totals.elsewhere = totals.elsewhere + 1; note = "pins on other maps only"
			else
				table.insert(totals.offersNoPin, q.questID); note = "NO PIN"
			end
		else
			table.insert(totals.offersNoData, q.questID); note = "NOT IN DATA"
		end
		if q.startMapID and q.startMapID ~= mapID then totals.otherMapStart = totals.otherMapStart + 1 end
		print(string.format("  offer %s %s at %s, %s: %s (%s)", text(q.questID), text(q.questName), text(q.x), text(q.y), note, details))
	end
	for _, questID in ipairs(forced) do
		totals.forced = totals.forced + 1
		row(mapID, m.name, "forced", questID, quests[questID] and quests[questID][1], nil, nil, "", questID)
		print(string.format("  forced %s %s", text(questID), quests[questID] and quests[questID][1] or "(not in data)"))
	end
	for _, q in ipairs(tasks) do
		totals.tasks = totals.tasks + 1
		row(mapID, m.name, "task", q.questID, quests[q.questID] and quests[q.questID][1], q.x, q.y,
			flags(q, {"questStart", "inProgress", "daily", "meta", "indicator"}), q.questID)
		print(string.format("  task %s %s at %s, %s", text(q.questID), quests[q.questID] and quests[q.questID][1] or "(not in data)", text(q.x), text(q.y)))
	end
	for _, q in ipairs(logQuests) do
		totals.logQuests = totals.logQuests + 1
		row(mapID, m.name, "log", q.questID, quests[q.questID] and quests[q.questID][1], q.x, q.y, flags(q, {"questStart", "inProgress"}), q.questID)
	end
	local eventSet = {}
	for _, id in ipairs(events) do eventSet[id] = true end
	local hubSet = {}
	for _, id in ipairs(hubs) do hubSet[id] = true end
	for _, p in ipairs(pois) do
		totals.pois = totals.pois + 1
		if p.name then totals.namedPois = totals.namedPois + 1 end
		local kind = eventSet[p.areaPoiID] and "event" or hubSet[p.areaPoiID] and "hub" or "poi"
		local details = string.format("%s%s%s%s%s", text(p.atlas), p.factionID and ("; faction " .. p.factionID) or "",
			p.linkedMap and ("; linked map " .. p.linkedMap) or "", p.timed and ("; timed" .. (p.secondsLeft and (", " .. p.secondsLeft .. " s left") or "")) or "",
			p.currentEvent and "; current event" or "")
		row(mapID, m.name, kind, p.areaPoiID, p.name, p.x, p.y, details)
		print(string.format("  %s %s %s at %s, %s%s", kind, text(p.areaPoiID), text(p.name), text(p.x), text(p.y), details ~= "" and (" (" .. details .. ")") or ""))
	end
	totals.events = totals.events + #events
	totals.hubs = totals.hubs + #hubs
	for _, e in ipairs(entrances) do
		totals.entrances = totals.entrances + 1
		row(mapID, m.name, "entrance", e.areaPoiID, e.name, e.x, e.y, "journal instance " .. text(e.journalInstanceID))
		print(string.format("  entrance %s %s at %s, %s (journal instance %s)", text(e.areaPoiID), text(e.name), text(e.x), text(e.y), text(e.journalInstanceID)))
	end
end

print("")
local resultParts = {}
for _, k in ipairs(sortedKeys(totals.byResult)) do resultParts[#resultParts + 1] = k .. " " .. totals.byResult[k] end
print(string.format("%d maps (%s); %d with a level range, %d allow a user waypoint.", totals.maps, table.concat(resultParts, ", "),
	totals.levels, totals.waypoint))
print(string.format("%d quest offers (%d start on another map), %d forced quests, %d task quests, %d log quests.", totals.offers,
	totals.otherMapStart, totals.forced, totals.tasks, totals.logQuests))
print(string.format("Of the offers, %d are quests in the addon's data: %d have a pin on that map within 1.5 points, %d within 3, %d further, %d have pins on other maps only, and %d have no pin at all.",
	totals.offersInData, totals.within, totals.near, totals.far, totals.elsewhere, #totals.offersNoPin))
if #totals.offersNoPin > 0 then print("  No pin: " .. table.concat(totals.offersNoPin, ", ")) end
if #totals.offersNoData > 0 then print(string.format("  %d offers are quests not in the data: %s", #totals.offersNoData, table.concat(totals.offersNoData, ", "))) end
print(string.format("%d points of interest (%d named), %d events, %d quest hubs, %d dungeon entrances.", totals.pois, totals.namedPois,
	totals.events, totals.hubs, totals.entrances))

if tsvFile then
	local f = assert(io.open(tsvFile, "w"))
	f:write("map\tmapName\tkind\tid\tname\tx\ty\tdetails\tinData\tpinOnMap\tnearestPin\tpinNpc\tanyPin\n")
	for _, line in ipairs(rows) do f:write(line, "\n") end
	f:close()
	print(string.format("Wrote %d rows to %s.", #rows, tsvFile))
end
