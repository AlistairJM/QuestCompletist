--[[ Forever beta probe for Quest Completist (docs/plans/forever.md, phase 1). A separate addon, not
part of Quest Completist: copy this folder to _classic_beta_\Interface\AddOns\QCForeverProbe.

/qcprobe quests [in flight]   asks the server about every quest in QuestIDs.lua that hasn't
                              answered yet on this build: the client's quest list, which leaves out
                              repeatable quests, and the CMaNGOS quests it lacks. The beta only
                              answers quests up to about level 40, so rerun it when the beta opens
                              higher levels.
/qcprobe quests all           asks about every quest again
/qcprobe npcs [in flight]     names the quest givers from CMaNGOS and our old Classic pins (NpcIDs.lua)
/qcprobe npcs all             names every NPC again
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
                tagElite, elite, repeatable, questType, groupSize, classification
  npcs[id]      build, result (now, event, poll, late or none), ms, name, lines (tooltip lines 2-4)
  givers[key]   key "Creature:id" or "GameObject:id": kind, id, name, build, spots ("map x y" = times
                seen), offers (questId = level, frequency, repeatable, lowestPlayerLevel, seenBy),
                turnIns (questId = true)
  started[id]   quests offered by no NPC or object: build, item, map, x, y, by
  accepted[id]  build, heading, map, x, y, by, level
  runs          one row per run; logins: one row per build, TOC and load test seen at login ]]--

local ADDON_NAME, probe = ...

local DEFAULT_IN_FLIGHT = 4
local REQUEST_TIMEOUT_MS = 5000
local LATE_ANSWER_WAIT_MS = 10000
local POLL_MS = 1000
local TICK_SECONDS = 0.05
local PROGRESS_EVERY = 500

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

local function count(r, result)
	r.counts[result] = (r.counts[result] or 0) + 1
	r.done = r.done + 1
	if r.done % PROGRESS_EVERY == 0 then
		say(string.format("%s: %d of %d (%s).", r.label, r.done, r.total, countsText(r.counts)))
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
	table.insert(db.runs, {kind = r.kind, build = build, locale = GetLocale(), inFlight = r.maxInFlight,
		asked = r.total, answered = r.done, counts = r.counts, seconds = seconds, stopped = stopped or nil,
		time = time()})
	say(string.format("%s the %s: %d of %d in %d s (%s). Log out fully to save the results and the game's cache.",
		stopped and "Stopped" or "Finished", r.label, r.done, r.total, seconds, countsText(r.counts)))
end

local function tick()
	local r = run
	if not r then return end
	local now = debugprofilestop()
	for id, started in pairs(r.inFlight) do
		if now - started > REQUEST_TIMEOUT_MS then
			r.inFlight[id] = nil
			r.inFlightCount = r.inFlightCount - 1
			r.timedOut[id] = started
			r.timeout(id)
		elseif r.poll and now - (r.lastAsked[id] or started) >= POLL_MS then
			r.poll(id)
		end
	end
	while r.inFlightCount < r.maxInFlight and r.nextIndex <= r.total do
		local id = r.queue[r.nextIndex]
		r.nextIndex = r.nextIndex + 1
		r.send(id)
	end
	if r.inFlightCount == 0 and r.nextIndex > r.total then
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

local function questFacts(questId, result, ms)
	local facts = {build = build, result = result, ms = ms and math.floor(ms + 0.5) or nil}
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
	return facts
end

local function startQuests(all, inFlight)
	if probe.questBuild ~= build then
		say(string.format("the quest list is from build %s, and this is %s. Rebuild it with tools/ForeverProbe/Build-ProbeLists.ps1 to include new quests.",
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
	r.send = function(questId)
		local title = try(C_QuestLog.GetTitleForQuestID, questId)
		if title and title ~= "" then
			db.quests[questId] = questFacts(questId, "cached")
			count(r, "cached")
			return
		end
		r.inFlight[questId] = debugprofilestop()
		r.inFlightCount = r.inFlightCount + 1
		C_QuestLog.RequestLoadQuestByID(questId)
	end
	r.timeout = function(questId)
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
	if run then say(string.format("Running: the %s, %d of %d.", run.label, run.done, run.total)) end
end

local function onLogin()
	local toc = try(C_AddOns.GetAddOnMetadata, ADDON_NAME, "X-Probe-TOC") or "?"
	local loaded = {}
	for key in pairs(probe.loadTest or {}) do loaded[#loaded + 1] = key end
	table.sort(loaded)
	local loadTest = table.concat(loaded, ", ")
	local last = db.logins[#db.logins]
	if not last or last.build ~= build or last.toc ~= toc or last.loadTest ~= loadTest then
		table.insert(db.logins, {build = build, locale = GetLocale(), toc = toc, loadTest = loadTest, time = time()})
	end
	say(string.format("loaded from the %s TOC on %s. Files loaded by game type: %s. Type /qcprobe for commands; the recorder is %s.",
		toc, build, loadTest ~= "" and loadTest or "none", db.recording and "on" or "off"))
end

local function init()
	QCForeverProbeDB = QCForeverProbeDB or {}
	db = QCForeverProbeDB
	for _, key in ipairs({"quests", "npcs", "givers", "started", "accepted", "runs", "logins"}) do
		db[key] = db[key] or {}
	end
	if db.recording == nil then db.recording = true end
	local version, buildNumber = GetBuildInfo()
	build = string.format("%s.%s", tostring(version), tostring(buildNumber))
end

local frame = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "QUEST_DATA_LOAD_RESULT", "TOOLTIP_DATA_UPDATE",
	"GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_ACCEPTED"}) do
	frame:RegisterEvent(event)
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
	elseif command == "stop" then
		if run then finish(true) else say("nothing is running.") end
	elseif command == "status" then
		status()
	elseif command == "record" and (option == "on" or option == "off") then
		db.recording = option == "on"
		say("the recorder is " .. option .. ".")
	else
		say("/qcprobe quests [all | in flight], npcs [all | in flight], stop, status, record on|off.")
	end
end
