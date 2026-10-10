--[[ The probe for Quest Completist's tools (docs/maintenance.md, "In the game"), for WoW: Forever and
retail. A dev-only addon, not part of Quest Completist and never shipped: copy this folder to the
game's Interface\AddOns\QCForeverProbe (_classic_beta_ or the live Forever folder, or _retail_).

/qcprobe quests [in flight]   asks the server about every quest in the game's list (QuestIDs_*.lua) that hasn't
                              answered yet on this build: the client's quest list, which leaves out
                              repeatable quests, and the CMaNGOS quests it lacks. The beta only
                              answers quests up to about level 40, so rerun it when the beta opens
                              higher levels.
/qcprobe quests all           asks about every quest again
                              A quest the game already has data for (HaveQuestData, or a title) is
                              not asked; one that gets no answer in 5 seconds is asked once more.
/qcprobe npcs [in flight]     names the NPCs in the game's list (NpcIDs_*.lua): the NPC of every pin, and on Forever CMaNGOS's givers
/qcprobe npcs all             names every NPC again
/qcprobe maps [wait seconds]  asks the server for each map's quest offers (the storyline starts
                              Blizzard's map draws), points of interest, events, quest hubs and
                              dungeon entrances, and once for the events schedule
                              (docs/plans/game-api-review.md, recommendation 3). It waits the given
                              seconds, 2 by default, for each map's answer. Runs on retail too.
/qcprobe stop                 stops the run in progress
/qcprobe status               what's been gathered on this build
/qcprobe record on|off        the recorder, on by default
In flight defaults to 4. Run the NPC pass outside instances: they hide names.

Asking about a quest also puts the server's full record of it into the game's cache
(Cache\WDB\enUS\questcache.wdb), which holds its zone and minimum level. Naming an NPC does the same
in creaturecache.wdb. Log out fully after a run, so the game writes the results and both caches.

The recorder notes, while you play, which quests each NPC or object offers and takes in, where you
stood, the quest log heading of each quest you accept, and quests started from items.

QCForeverProbeDB holds:
  quests[id]    build, result (ok, fail, timeout, late or cached), ms, title, level, tagID, tagName,
                tagElite, elite, repeatable, questType, groupSize, classification, and the
                facts of docs/plans/game-api-review.md, recommendation 2: isTask, isWorld, taskZone
                (task quests), accountQuest, factionGroup, important, meta, questLineID, campaignID,
                expansion, breadcrumb, story. Only a quest that loaded has facts, and a fact the client
                does not answer is left out. The quest run's row (runs) has facts: for each, the
                function that answered, or false when this client has none, and refusedFacts: for
                each function, how many refused quests it was asked about (asked), how many it
                answered anything for (answered), how many with true, a number above 0 or a
                string (positive), and the first five of those (examples).
  npcs[id]      build, result (now, event, poll, late or none), ms, name, lines (tooltip lines 2-4)
  givers[key]   key "Creature:id" or "GameObject:id": kind, id, name, build, spots ("map x y" = times
                seen), offers (questId = level, frequency, repeatable, lowestPlayerLevel, seenBy),
                turnIns (questId = true)
  started[id]   quests offered by no NPC or object: build, item, map, x, y, by
  accepted[id]  build, heading, map, x, y, by, level
  maps[mapID]   build, preset (Forever's experience preset: 0 Classic, 1 Modern, nil on retail),
                result (event: QUESTLINE_UPDATE came; noevent: it didn't within the wait; unanswered:
                the game kept asking for another request), ms, requests, name, mapType, parent,
                questLines (the offers, each with its quest, storyline, x, y, startMapID and flags),
                forceVisible, tasks, logQuests, pois, events, hubs, entrances, levels, waypoint.
                Positions are map percentages, like the recorder's spots.
  runs          one row per run, with the character (faction, race and class, never a name) and its
                level; a map run also keeps the tracking toggles and the events schedule. logins: one row per build and TOC seen at login ]]--

local ADDON_NAME, probe = ...

local DEFAULT_IN_FLIGHT = 4
local REQUEST_TIMEOUT_MS = 5000
local MAX_ATTEMPTS = 2
local LATE_ANSWER_WAIT_MS = 10000
local POLL_MS = 1000
local TICK_SECONDS = 0.05
local PROGRESS_EVERY = 500
local DEFAULT_MAP_WAIT_SECONDS = 2
local MAP_PROGRESS_EVERY = 20
local MAX_MAP_ID = 5000
local MAX_MAP_REQUESTS = 3

local db, build, run

local function say(message)
	print("|cFFFFD100QC Forever probe:|r " .. message)
end

local function secret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function try(func, ...)
	if not func then return nil end
	local ok, result = pcall(func, ...)
	if ok then return result end
end

local function countsText(counts)
	local keys = {}
	for key in pairs(counts) do keys[#keys + 1] = key end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do parts[#parts + 1] = string.format("%s %d", key, counts[key]) end
	return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

local function character()
	local _, race = UnitRace("player")
	local _, class = UnitClass("player")
	return string.format("%s %s %s", UnitFactionGroup("player") or "?", race or "?", class or "?")
end

local function where()
	local mapId = C_Map.GetBestMapForUnit("player")
	if not mapId or secret(mapId) then return nil end
	local position = C_Map.GetPlayerMapPosition(mapId, "player")
	if not position then return mapId end
	local x, y = position:GetXY()
	if not x or secret(x) or secret(y) then return mapId end
	return mapId, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

local function minutesLeft(r)
	local elapsed = debugprofilestop() - r.startedMs
	if r.done == 0 or elapsed <= 0 then return nil end
	return math.ceil((r.total - r.done) / (r.done / elapsed) / 60000)
end

local function count(r, result)
	r.counts[result] = (r.counts[result] or 0) + 1
	r.done = r.done + 1
	if r.done % (r.progressEvery or PROGRESS_EVERY) == 0 then
		local left = minutesLeft(r)
		say(string.format("%s: %d of %d (%s)%s.", r.label, r.done, r.total, countsText(r.counts),
			left and string.format(", about %d min left", left) or ""))
	end
end

local function recount(r, from, to)
	r.counts[from] = r.counts[from] - 1
	r.counts[to] = (r.counts[to] or 0) + 1
end

local function finish(stopped)
	local r = run
	run = nil
	r.ticker:Cancel()
	local seconds = math.floor((debugprofilestop() - r.startedMs) / 1000 + 0.5)
	local row = {kind = r.kind, build = build, locale = GetLocale(), inFlight = r.maxInFlight,
		asked = r.total, answered = r.done, counts = r.counts, seconds = seconds, stopped = stopped or nil,
		time = time(), character = character(), level = UnitLevel("player")}
	for key, value in pairs(r.extra or {}) do row[key] = value end
	table.insert(db.runs, row)
	say(string.format("%s the %s: %d of %d in %d s (%s). Log out fully to save the results and the game's cache.",
		stopped and "Stopped" or "Finished", r.label, r.done, r.total, seconds, countsText(r.counts)))
end

local function tick()
	local r = run
	if not r then return end
	local now = debugprofilestop()
	for id, started in pairs(r.inFlight) do
		if now - started > (r.timeoutMs or REQUEST_TIMEOUT_MS) then
			r.inFlight[id] = nil
			r.inFlightCount = r.inFlightCount - 1
			r.timedOut[id] = started
			r.timeout(id)
		elseif r.poll and now - (r.lastAsked[id] or started) >= POLL_MS then
			r.poll(id)
		end
	end
	while r.inFlightCount < r.maxInFlight and r.nextIndex <= #r.queue do
		local id = r.queue[r.nextIndex]
		r.nextIndex = r.nextIndex + 1
		r.send(id)
	end
	if r.inFlightCount == 0 and r.nextIndex > #r.queue then
		if next(r.timedOut) and not r.lateWaitUntil then
			r.lateWaitUntil = now + LATE_ANSWER_WAIT_MS
		end
		if not next(r.timedOut) or now > r.lateWaitUntil then
			if r.lastLook then r.lastLook() end
			finish(false)
		end
	end
end

local function begin(kind, label, queue, inFlight)
	run = {kind = kind, label = label, queue = queue, total = #queue, nextIndex = 1, inFlight = {},
		inFlightCount = 0, timedOut = {}, lastAsked = {}, byInstance = {}, counts = {}, done = 0,
		maxInFlight = inFlight, startedMs = debugprofilestop()}
	return run
end

local function go(r)
	say(string.format("%s: asking about %d, %d at a time...", r.label, r.total, r.maxInFlight))
	r.ticker = C_Timer.NewTicker(TICK_SECONDS, tick)
end

-- What else is asked of a loaded quest (docs/plans/game-api-review.md, recommendation 2): each fact
-- comes from the first of its functions this client has, and which that was goes in the run's row,
-- so a function the client lacks is told apart from one that answers nothing.
local FACTS = {
	{key = "isTask", names = {"C_QuestLog.IsQuestTask"}},
	{key = "isWorld", names = {"C_QuestLog.IsWorldQuest"}},
	{key = "accountQuest", names = {"C_QuestLog.IsAccountQuest"}},
	{key = "factionGroup", names = {"C_QuestLog.GetQuestFactionGroup", "GetQuestFactionGroup"}},
	{key = "important", names = {"C_QuestLog.IsImportantQuest"}},
	{key = "meta", names = {"C_QuestLog.IsMetaQuest"}},
	{key = "questLineID", names = {"C_QuestLine.GetQuestLineInfo"}, field = "questLineID"},
	{key = "campaignID", names = {"C_CampaignInfo.GetCampaignID"}},
	{key = "taskZone", names = {"C_TaskQuest.GetQuestZoneID"}, when = "isTask"},
	{key = "expansion", names = {"C_QuestLog.GetQuestExpansion", "GetQuestExpansion"}},
	{key = "breadcrumb", names = {"C_QuestLog.IsBreadcrumbQuest", "IsBreadcrumbQuest"}},
	{key = "story", names = {"C_QuestLog.IsStoryQuest", "IsStoryQuest"}},
}
local factCalls = {}

local function resolveFacts()
	local calls, found = {}, {}
	for _, spec in ipairs(FACTS) do
		found[spec.key] = false
		for _, name in ipairs(spec.names) do
			local value = _G
			for part in name:gmatch("[^.]+") do
				value = type(value) == "table" and value[part] or nil
			end
			if type(value) == "function" then
				calls[spec.key] = value
				found[spec.key] = name
				break
			end
		end
	end
	return calls, found
end

local function askFacts(facts, questId)
	for _, spec in ipairs(FACTS) do
		local call = factCalls[spec.key]
		if call and (not spec.when or facts[spec.when]) then
			local value = try(call, questId)
			if spec.field and type(value) == "table" then value = value[spec.field] end
			local kind = type(value)
			if (kind == "boolean" or kind == "number" or kind == "string") and not secret(value) then facts[spec.key] = value end
		end
	end
end

-- A refused quest has no data, so no facts are kept for it, but the functions are still asked: for each,
-- how many refused quests it was asked about, how many answered anything, how many with true, a number
-- above 0 or a string, and the first five of those. That says whether a function needs a loaded quest.
local refusedFacts

local function tallyRefused(questId)
	local facts = {}
	askFacts(facts, questId)
	for _, spec in ipairs(FACTS) do
		if factCalls[spec.key] and (not spec.when or facts[spec.when]) then
			local t = refusedFacts[spec.key]
			if not t then
				t = {asked = 0, answered = 0, positive = 0, examples = {}}
				refusedFacts[spec.key] = t
			end
			t.asked = t.asked + 1
			local value = facts[spec.key]
			if value ~= nil then
				t.answered = t.answered + 1
				if value == true or (type(value) == "number" and value > 0) or (type(value) == "string" and value ~= "") then
					t.positive = t.positive + 1
					if #t.examples < 5 then t.examples[#t.examples + 1] = questId end
				end
			end
		end
	end
end

local function questFacts(questId, result, ms)
	local facts = {build = build, result = result, ms = ms and math.floor(ms + 0.5) or nil}
	if result == "fail" and refusedFacts then tallyRefused(questId) end
	if result == "fail" or result == "timeout" then return facts end
	local title = try(C_QuestLog.GetTitleForQuestID, questId)
	if title ~= "" then facts.title = title end
	facts.level = try(C_QuestLog.GetQuestDifficultyLevel, questId)
	local tag = try(C_QuestLog.GetQuestTagInfo, questId)
	if type(tag) == "table" then facts.tagID, facts.tagName, facts.tagElite = tag.tagID, tag.tagName, tag.isElite end
	facts.elite = try(C_QuestLog.IsEliteQuest, questId)
	facts.repeatable = try(C_QuestLog.IsRepeatableQuest, questId)
	facts.questType = try(C_QuestLog.GetQuestType, questId)
	facts.groupSize = try(C_QuestLog.GetSuggestedGroupSize, questId)
	facts.classification = try(C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification, questId)
	askFacts(facts, questId)
	return facts
end

local function haveQuestData(questId)
	if HaveQuestData then
		local ok, have = pcall(HaveQuestData, questId)
		if ok and have then return true end
	end
	local title = try(C_QuestLog.GetTitleForQuestID, questId)
	return title ~= nil and title ~= ""
end

local function startQuests(all, inFlight)
	if probe.questBuild ~= build then
		say(string.format("the quest list is from build %s, and this is %s. Rebuild it with tools/ForeverProbe/Build-ProbeLists.ps1 -Game retail or forever.",
			probe.questBuild, build))
	end
	local queue = {}
	for _, questId in ipairs(probe.questIds) do
		local facts = db.quests[questId]
		if all or not facts or facts.build ~= build or (facts.result ~= "ok" and facts.result ~= "cached") then
			queue[#queue + 1] = questId
		end
	end
	if #queue == 0 then
		say("every quest is answered on this build. /qcprobe quests all asks again.")
		return
	end
	local r = begin("quests", "quest pass", queue, inFlight)
	local found
	factCalls, found = resolveFacts()
	refusedFacts = {}
	r.extra = {facts = found, refusedFacts = refusedFacts}
	local attempts = {}
	r.send = function(questId)
		if haveQuestData(questId) then
			db.quests[questId] = questFacts(questId, "cached")
			count(r, "cached")
			return
		end
		attempts[questId] = (attempts[questId] or 0) + 1
		r.inFlight[questId] = debugprofilestop()
		r.inFlightCount = r.inFlightCount + 1
		C_QuestLog.RequestLoadQuestByID(questId)
	end
	r.timeout = function(questId)
		if attempts[questId] < MAX_ATTEMPTS then
			r.timedOut[questId] = nil
			r.queue[#r.queue + 1] = questId
			return
		end
		db.quests[questId] = questFacts(questId, "timeout")
		count(r, "timeout")
	end
	r.answered = function(questId, success)
		local started = r.inFlight[questId]
		if started then
			r.inFlight[questId] = nil
			r.inFlightCount = r.inFlightCount - 1
			local result = success and "ok" or "fail"
			db.quests[questId] = questFacts(questId, result, debugprofilestop() - started)
			count(r, result)
		elseif r.timedOut[questId] then
			started = r.timedOut[questId]
			r.timedOut[questId] = nil
			db.quests[questId] = questFacts(questId, "late", debugprofilestop() - started)
			recount(r, "timeout", "late")
		end
	end
	go(r)
end

local function isPlaceholder(text)
	return text == RETRIEVING_DATA or text == RETRIEVING_ITEM_INFO or text == UNKNOWN or text == UNKNOWNOBJECT
end

local function askNpc(npcId)
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, string.format("unit:Creature-0-0-0-0-%d-0000000000", npcId))
	if not ok or type(data) ~= "table" then return nil end
	local lines = data.lines
	local name = lines and lines[1] and lines[1].leftText
	if not name or secret(name) or name == "" or isPlaceholder(name) then return nil, nil, data.dataInstanceID end
	local more = {}
	for i = 2, math.min(#lines, 4) do
		local text = lines[i].leftText
		if text and not secret(text) and text ~= "" then more[#more + 1] = text end
	end
	return name, table.concat(more, " / "), data.dataInstanceID
end

local function startNpcs(all, inFlight)
	local queue = {}
	for _, npcId in ipairs(probe.npcIds) do
		local facts = db.npcs[npcId]
		if all or not facts or facts.build ~= build or facts.result == "none" then queue[#queue + 1] = npcId end
	end
	if #queue == 0 then
		say("every NPC is named on this build. /qcprobe npcs all asks again.")
		return
	end
	local r = begin("npcs", "NPC pass", queue, inFlight)
	local function named(npcId, result, name, lines)
		local started = r.inFlight[npcId] or r.timedOut[npcId]
		db.npcs[npcId] = {build = build, result = result, name = name, lines = lines ~= "" and lines or nil,
			ms = started and math.floor(debugprofilestop() - started + 0.5) or nil}
		if r.inFlight[npcId] then
			r.inFlight[npcId] = nil
			r.inFlightCount = r.inFlightCount - 1
			count(r, result)
		elseif r.timedOut[npcId] then
			r.timedOut[npcId] = nil
			recount(r, "none", "late")
		else
			count(r, result)
		end
	end
	local function look(npcId, result)
		local name, lines, instance = askNpc(npcId)
		r.lastAsked[npcId] = debugprofilestop()
		if instance then r.byInstance[instance] = npcId end
		if name then named(npcId, result, name, lines) end
	end
	r.send = function(npcId)
		local name, lines, instance = askNpc(npcId)
		if name then
			named(npcId, "now", name, lines)
			return
		end
		local now = debugprofilestop()
		r.inFlight[npcId] = now
		r.lastAsked[npcId] = now
		r.inFlightCount = r.inFlightCount + 1
		if instance then r.byInstance[instance] = npcId end
	end
	r.poll = function(npcId) look(npcId, "poll") end
	r.timeout = function(npcId)
		db.npcs[npcId] = {build = build, result = "none"}
		count(r, "none")
	end
	r.lastLook = function()
		for npcId in pairs(r.timedOut) do look(npcId, "late") end
	end
	r.tooltipUpdate = function(instance)
		local npcId = r.byInstance[instance]
		if not npcId or not (r.inFlight[npcId] or r.timedOut[npcId]) then return end
		r.byInstance[instance] = nil
		look(npcId, r.inFlight[npcId] and "event" or "late")
	end
	go(r)
end

local function plain(value)
	if value == nil or secret(value) then return nil end
	return value
end

local function flag(value)
	return plain(value) == true or nil
end

local function percent(value)
	value = plain(value)
	if type(value) ~= "number" then return nil end
	return math.floor(value * 1000 + 0.5) / 10
end

local function pointOf(position)
	if type(position) ~= "table" then return nil end
	if position.GetXY then
		local ok, x, y = pcall(position.GetXY, position)
		if ok then return percent(x), percent(y) end
		return nil
	end
	return percent(position.x), percent(position.y)
end

local function listOf(func, ...)
	local list = try(func, ...)
	return type(list) == "table" and list or {}
end

local function keep(list)
	return #list > 0 and list or nil
end

local function idsOf(func, ...)
	local ids = {}
	for _, id in ipairs(listOf(func, ...)) do ids[#ids + 1] = plain(id) end
	return keep(ids)
end

local function poiFacts(mapID, areaPoiID)
	local p = try(C_AreaPoiInfo.GetAreaPOIInfo, mapID, areaPoiID)
	if type(p) ~= "table" then return {areaPoiID = areaPoiID} end
	local x, y = pointOf(p.position)
	local facts = {areaPoiID = plain(p.areaPoiID) or areaPoiID, name = plain(p.name), description = plain(p.description),
		x = x, y = y, atlas = plain(p.atlasName), textureIndex = plain(p.textureIndex), factionID = plain(p.factionID),
		linkedMap = plain(p.linkedUiMapID), currentEvent = flag(p.isCurrentEvent), primary = flag(p.isPrimaryMapForPOI),
		flightMap = flag(p.isAlwaysOnFlightmap), glow = flag(p.shouldGlow)}
	if flag(try(C_AreaPoiInfo.IsAreaPOITimed, areaPoiID)) then
		facts.timed = true
		facts.secondsLeft = plain(try(C_AreaPoiInfo.GetAreaPOISecondsLeft, areaPoiID))
	end
	return facts
end

local function mapFacts(mapID, r, result, ms)
	local facts = {build = build, preset = r.extra.preset, result = result, ms = ms and math.floor(ms + 0.5) or nil,
		requests = r.requests, time = time()}
	local info = try(C_Map.GetMapInfo, mapID)
	if type(info) == "table" then
		facts.name, facts.mapType, facts.parent = plain(info.name), plain(info.mapType), plain(info.parentMapID)
	end
	local lines = {}
	for _, q in ipairs(listOf(C_QuestLine.GetAvailableQuestLines, mapID)) do
		lines[#lines + 1] = {questLineID = plain(q.questLineID), questLineName = plain(q.questLineName),
			questID = plain(q.questID), questName = plain(q.questName), x = percent(q.x), y = percent(q.y),
			startMapID = plain(q.startMapID), floor = plain(q.floorLocation), hidden = flag(q.isHidden),
			accountDone = flag(q.isAccountCompleted), inProgress = flag(q.inProgress), campaign = flag(q.isCampaign),
			important = flag(q.isImportant), legendary = flag(q.isLegendary), daily = flag(q.isDaily),
			meta = flag(q.isMeta), localStory = flag(q.isLocalStory), questStart = flag(q.isQuestStart)}
	end
	facts.questLines = keep(lines)
	facts.forceVisible = idsOf(C_QuestLine.GetForceVisibleQuests, mapID)
	local function poiQuests(func)
		local list = {}
		for _, q in ipairs(listOf(func, mapID)) do
			list[#list + 1] = {questID = plain(q.questID), x = percent(q.x), y = percent(q.y), mapID = plain(q.mapID),
				questStart = flag(q.isQuestStart), inProgress = flag(q.inProgress), daily = flag(q.isDaily),
				meta = flag(q.isMeta), objectives = plain(q.numObjectives), tagType = plain(q.questTagType),
				childDepth = plain(q.childDepth), indicator = flag(q.isMapIndicatorQuest)}
		end
		return keep(list)
	end
	facts.tasks = poiQuests(C_TaskQuest and C_TaskQuest.GetQuestsOnMap)
	facts.logQuests = poiQuests(C_QuestLog.GetQuestsOnMap)
	if C_AreaPoiInfo then
		local pois = {}
		for _, areaPoiID in ipairs(listOf(C_AreaPoiInfo.GetAreaPOIForMap, mapID)) do
			pois[#pois + 1] = poiFacts(mapID, plain(areaPoiID))
		end
		facts.pois = keep(pois)
		facts.events = idsOf(C_AreaPoiInfo.GetEventsForMap, mapID)
		facts.hubs = idsOf(C_AreaPoiInfo.GetQuestHubsForMap, mapID)
	end
	local entrances = {}
	for _, e in ipairs(listOf(C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap, mapID)) do
		local x, y = pointOf(e.position)
		entrances[#entrances + 1] = {areaPoiID = plain(e.areaPoiID), name = plain(e.name), x = x, y = y,
			atlas = plain(e.atlasName), journalInstanceID = plain(e.journalInstanceID)}
	end
	facts.entrances = keep(entrances)
	local ok, minLevel, maxLevel = pcall(C_Map.GetMapLevels, mapID)
	if ok and plain(minLevel) and plain(maxLevel) and (minLevel > 0 or maxLevel > 0) then
		facts.levels = {minLevel, maxLevel}
	end
	facts.waypoint = plain(try(C_Map.CanSetUserWaypointOnMap, mapID))
	return facts
end

local function schedulerFacts()
	if not C_EventScheduler then return {missing = true} end
	local s = {hasData = plain(try(C_EventScheduler.HasData)), canShow = plain(try(C_EventScheduler.CanShowEvents)),
		continent = plain(try(C_EventScheduler.GetActiveContinentName)), ongoing = {}, scheduled = {}}
	local function place(entry, areaPoiID)
		entry.zone = plain(try(C_EventScheduler.GetEventZoneName, areaPoiID))
		entry.map = plain(try(C_EventScheduler.GetEventUiMapID, areaPoiID))
		local poi = areaPoiID and try(C_AreaPoiInfo.GetAreaPOIInfo, entry.map, areaPoiID)
		if type(poi) == "table" then entry.name = plain(poi.name) end
	end
	for _, e in ipairs(listOf(C_EventScheduler.GetOngoingEvents)) do
		local entry = {areaPoiID = plain(e.areaPoiID), rewardsClaimed = flag(e.rewardsClaimed)}
		place(entry, entry.areaPoiID)
		s.ongoing[#s.ongoing + 1] = entry
	end
	for _, e in ipairs(listOf(C_EventScheduler.GetScheduledEvents)) do
		local entry = {eventKey = plain(e.eventKey), eventID = plain(e.eventID), areaPoiID = plain(e.areaPoiID),
			startTime = plain(e.startTime), endTime = plain(e.endTime), duration = plain(e.duration)}
		place(entry, entry.areaPoiID)
		s.scheduled[#s.scheduled + 1] = entry
	end
	return s
end

local function startMaps(waitSeconds)
	local queue = {}
	for mapID = 1, MAX_MAP_ID do
		local info = try(C_Map.GetMapInfo, mapID)
		if type(info) == "table" and info.mapID then queue[#queue + 1] = mapID end
	end
	if #queue == 0 then
		say("the client lists no maps.")
		return
	end
	local r = begin("maps", "map pass", queue, 1)
	r.timeoutMs = waitSeconds * 1000
	r.progressEvery = MAP_PROGRESS_EVERY
	r.extra = {waitSeconds = waitSeconds, character = character(), level = UnitLevel("player"),
		preset = plain(try(C_GameRules and C_GameRules.GetForeverExperiencePreset)),
		hardcore = flag(try(C_GameRules and C_GameRules.IsHardcoreActive)),
		trackingHidden = plain(try(C_Minimap and C_Minimap.IsTrackingHiddenQuests)),
		trackingAccountDone = plain(try(C_Minimap and C_Minimap.IsTrackingAccountCompletedQuests))}
	local filtered = try(function() return C_Minimap.IsFilteredOut(Enum.MinimapTrackingFilter.QuestPOIs) end)
	if filtered ~= nil then r.extra.trackingQuestPois = not filtered end
	local questPoi = try(function() return C_CVar.GetCVarBool("questPOI") end)
	if questPoi ~= nil then r.extra.questPoiSetting = questPoi end
	r.send = function(mapID)
		r.inFlight[mapID] = debugprofilestop()
		r.inFlightCount = r.inFlightCount + 1
		r.requests = pcall(C_QuestLine.RequestQuestLinesForMap, mapID) and 1 or 0
	end
	r.questLineUpdate = function(requestRequired)
		local mapID, started = next(r.inFlight)
		if not mapID or r.requests == 0 then return end
		if requestRequired and r.requests < MAX_MAP_REQUESTS then
			r.requests = r.requests + 1
			pcall(C_QuestLine.RequestQuestLinesForMap, mapID)
			return
		end
		r.inFlight[mapID] = nil
		r.inFlightCount = r.inFlightCount - 1
		local result = requestRequired and "unanswered" or "event"
		db.maps[mapID] = mapFacts(mapID, r, result, debugprofilestop() - started)
		count(r, result)
	end
	r.timeout = function(mapID)
		local started = r.timedOut[mapID]
		r.timedOut[mapID] = nil
		db.maps[mapID] = mapFacts(mapID, r, "noevent", started and debugprofilestop() - started or nil)
		count(r, "noevent")
	end
	r.schedulerUpdate = function()
		r.extra.scheduler = schedulerFacts()
		r.extra.schedulerEvent = true
	end
	r.lastLook = function()
		if not r.extra.scheduler then r.extra.scheduler = schedulerFacts() end
	end
	if C_EventScheduler then pcall(C_EventScheduler.RequestEvents) end
	go(r)
end

local function giverKey()
	local guid = UnitGUID("npc")
	if not guid or secret(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	id = tonumber(id)
	if not id or (kind ~= "Creature" and kind ~= "GameObject" and kind ~= "Vehicle") then return nil end
	return kind .. ":" .. id, kind, id
end

local function giver()
	local key, kind, id = giverKey()
	if not key then return nil end
	local entry = db.givers[key]
	if not entry then
		entry = {kind = kind, id = id, spots = {}, offers = {}, turnIns = {}}
		db.givers[key] = entry
	end
	local name = UnitName("npc")
	if name and not secret(name) then entry.name = name end
	entry.build = build
	local mapId, x, y = where()
	if mapId then
		local spot = x and string.format("%d %.1f %.1f", mapId, x, y) or tostring(mapId)
		entry.spots[spot] = (entry.spots[spot] or 0) + 1
	end
	return entry
end

local function offered(entry, questId, info)
	local offer = entry.offers[questId]
	if not offer then
		offer = {seenBy = {}}
		entry.offers[questId] = offer
	end
	offer.seenBy[character()] = true
	local level = UnitLevel("player")
	if level and (not offer.lowestPlayerLevel or level < offer.lowestPlayerLevel) then offer.lowestPlayerLevel = level end
	if info then
		offer.level = info.questLevel or offer.level
		offer.frequency = info.frequency
		offer.repeatable = info.repeatable
	end
end

local function questList(available, active)
	if #available == 0 and #active == 0 then return end
	local entry = giver()
	if not entry then return end
	for _, info in ipairs(available) do offered(entry, info.questID, info) end
	for _, questId in ipairs(active) do entry.turnIns[questId] = true end
end

local recorder = {}

function recorder.GOSSIP_SHOW()
	local available, active = {}, {}
	for _, info in ipairs(try(C_GossipInfo.GetAvailableQuests) or {}) do
		if info.questID then available[#available + 1] = info end
	end
	for _, info in ipairs(try(C_GossipInfo.GetActiveQuests) or {}) do
		if info.questID then active[#active + 1] = info.questID end
	end
	questList(available, active)
end

function recorder.QUEST_GREETING()
	local available, active = {}, {}
	for i = 1, GetNumAvailableQuests() or 0 do
		local _, frequency, isRepeatable, _, questId = GetAvailableQuestInfo(i)
		if questId then available[#available + 1] = {questID = questId, frequency = frequency, repeatable = isRepeatable} end
	end
	for i = 1, GetNumActiveQuests() or 0 do
		local questId = GetActiveQuestID(i)
		if questId then active[#active + 1] = questId end
	end
	questList(available, active)
end

function recorder.QUEST_DETAIL(questStartItemID)
	local questId = GetQuestID()
	if not questId or questId == 0 then return end
	local entry = giver()
	if entry then
		offered(entry, questId)
		return
	end
	local mapId, x, y = where()
	db.started[questId] = {build = build, item = questStartItemID ~= 0 and questStartItemID or nil, map = mapId,
		x = x, y = y, by = character()}
end

function recorder.QUEST_COMPLETE()
	local questId = GetQuestID()
	if not questId or questId == 0 then return end
	local entry = giver()
	if entry then entry.turnIns[questId] = true end
end

function recorder.QUEST_ACCEPTED(questId)
	local heading
	local index = try(C_QuestLog.GetLogIndexForQuestID, questId)
	for i = index or 0, 1, -1 do
		local info = C_QuestLog.GetInfo(i)
		if info and info.isHeader then
			heading = info.title
			break
		end
	end
	local mapId, x, y = where()
	db.accepted[questId] = {build = build, heading = heading, map = mapId, x = x, y = y, by = character(),
		level = UnitLevel("player")}
end

local recorderFailed = false

local function record(event, ...)
	local ok, message = pcall(recorder[event], ...)
	if not ok and not recorderFailed then
		recorderFailed = true
		say(string.format("the recorder hit an error on %s (shown once): %s", event, tostring(message)))
	end
end

local function status()
	local quests, npcs = {}, {}
	local questCount, npcCount = 0, 0
	for _, facts in pairs(db.quests) do
		if facts.build == build then
			quests[facts.result] = (quests[facts.result] or 0) + 1
			questCount = questCount + 1
		end
	end
	for _, facts in pairs(db.npcs) do
		if facts.build == build then
			npcs[facts.result] = (npcs[facts.result] or 0) + 1
			npcCount = npcCount + 1
		end
	end
	local givers, offers, accepted = 0, 0, 0
	for _, entry in pairs(db.givers) do
		givers = givers + 1
		for _ in pairs(entry.offers) do offers = offers + 1 end
	end
	for _ in pairs(db.accepted) do accepted = accepted + 1 end
	say(string.format("on %s: %d of %d quests answered (%s); %d of %d NPCs (%s). The recorder is %s: %d givers offering %d quests, and %d quests accepted.",
		build, questCount, #probe.questIds, countsText(quests), npcCount, #probe.npcIds, countsText(npcs),
		db.recording and "on" or "off", givers, offers, accepted))
	local maps, mapOffers, pois, events, hubs, entrances = 0, 0, 0, 0, 0, 0
	for _, facts in pairs(db.maps) do
		if facts.build == build then
			maps = maps + 1
			mapOffers = mapOffers + #(facts.questLines or {}) + #(facts.forceVisible or {}) + #(facts.tasks or {})
			pois = pois + #(facts.pois or {})
			events = events + #(facts.events or {})
			hubs = hubs + #(facts.hubs or {})
			entrances = entrances + #(facts.entrances or {})
		end
	end
	say(string.format("Maps on %s: %d asked, with %d quest offers, %d points of interest, %d events, %d quest hubs and %d dungeon entrances.",
		build, maps, mapOffers, pois, events, hubs, entrances))
	if run then say(string.format("Running: the %s, %d of %d.", run.label, run.done, run.total)) end
end

local function onLogin()
	local toc = try(C_AddOns.GetAddOnMetadata, ADDON_NAME, "X-Probe-TOC") or "?"
	local last = db.logins[#db.logins]
	if not last or last.build ~= build or last.toc ~= toc then
		table.insert(db.logins, {build = build, locale = GetLocale(), toc = toc, time = time()})
	end
	say(string.format("loaded from the %s TOC on %s. Type /qcprobe for commands; the recorder is %s.",
		toc, build, db.recording and "on" or "off"))
end

local function init()
	QCForeverProbeDB = QCForeverProbeDB or {}
	db = QCForeverProbeDB
	for _, key in ipairs({"quests", "npcs", "givers", "started", "accepted", "maps", "runs", "logins"}) do
		db[key] = db[key] or {}
	end
	if db.recording == nil then db.recording = true end
	local version, buildNumber = GetBuildInfo()
	build = string.format("%s.%s", tostring(version), tostring(buildNumber))
end

local frame = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "QUEST_DATA_LOAD_RESULT", "TOOLTIP_DATA_UPDATE",
	"QUESTLINE_UPDATE", "EVENT_SCHEDULER_UPDATE", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_COMPLETE",
	"QUEST_ACCEPTED"}) do
	pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON_NAME then init() end
	elseif not db then
		return
	elseif event == "PLAYER_LOGIN" then
		onLogin()
	elseif event == "QUEST_DATA_LOAD_RESULT" then
		if run and run.answered then run.answered(...) end
	elseif event == "TOOLTIP_DATA_UPDATE" then
		if run and run.tooltipUpdate then run.tooltipUpdate(...) end
	elseif event == "QUESTLINE_UPDATE" then
		if run and run.questLineUpdate then run.questLineUpdate(...) end
	elseif event == "EVENT_SCHEDULER_UPDATE" then
		if run and run.schedulerUpdate then run.schedulerUpdate() end
	elseif db.recording then
		record(event, ...)
	end
end)

SLASH_QCFOREVERPROBE1 = "/qcprobe"
SlashCmdList.QCFOREVERPROBE = function(argument)
	local command, option = strsplit(" ", strtrim(argument or ""):lower())
	if command == "quests" or command == "npcs" then
		if run then
			say(string.format("the %s is running. /qcprobe stop first.", run.label))
			return
		end
		local inFlight = tonumber(option) or DEFAULT_IN_FLIGHT
		if command == "quests" then startQuests(option == "all", inFlight) else startNpcs(option == "all", inFlight) end
	elseif command == "maps" then
		if run then
			say(string.format("the %s is running. /qcprobe stop first.", run.label))
			return
		end
		startMaps(tonumber(option) or DEFAULT_MAP_WAIT_SECONDS)
	elseif command == "stop" then
		if run then finish(true) else say("nothing is running.") end
	elseif command == "status" then
		status()
	elseif command == "record" and (option == "on" or option == "off") then
		db.recording = option == "on"
		say("the recorder is " .. option .. ".")
	else
		say("/qcprobe quests [all | in flight], npcs [all | in flight], maps [wait seconds], stop, status, record on|off.")
	end
end
