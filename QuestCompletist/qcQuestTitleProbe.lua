--[[ Diagnostic, run with /qc titlecheck. Measures what showing quest names in the client's language
needs (docs/plans/localized-quest-names.md, phase 1):
  - how many quest titles the client can give straight away, before any request;
  - for the rest, how C_QuestLog.RequestLoadQuestByID answers with 4 requests in flight: loaded,
    failed, or no answer within 5 seconds (and whether a late answer still arrives);
  - the title the client gives, to compare with the English name in qcQuestDatabase.

/qc titlecheck             the category of the zone you're in
/qc titlecheck <category>  a category by ID
/qc titlecheck stop        stops the run in progress

Each run is appended to qcQuestTitleProbeResults, which /reload (or logging out) saves. One row per
quest:
  immediate | fromTask | haveData | result | ms | title
immediate/fromTask/haveData are 1/0; result is ok, fail, timeout, late (answered after the timeout)
or - (not requested, the title was already there); ms is how long the request took.

Delete this file once phase 1 is done. ]]--

local MAX_IN_FLIGHT = 4
local REQUEST_TIMEOUT_MS = 5000
local LATE_ANSWER_WAIT_MS = 10000
local TICK_SECONDS = 0.05

local run = nil
local runsThisSession = 0

local function say(message)
	print("|cFFFFD100Quest Completist:|r " .. message)
end

local function clientTitle(questId)
	local taskTitle = C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID and C_TaskQuest.GetQuestInfoByQuestID(questId)
	if taskTitle and taskTitle ~= "" then return taskTitle, true end
	local title = C_QuestLog.GetTitleForQuestID(questId)
	if title and title ~= "" then return title, false end
	return nil, false
end

local function row(immediate, fromTask, haveData, result, ms, title)
	return table.concat({immediate and "1" or "0", fromTask and "1" or "0", haveData and "1" or "0",
		result, ms and string.format("%d", ms) or "-", title or ""}, "|")
end

local function finish(stopped)
	local r = run
	run = nil
	r.ticker:Cancel()
	local counts = {ok = 0, fail = 0, timeout = 0, late = 0}
	local immediate, differ, totalMs, maxMs = 0, 0, 0, 0
	local examples = {}
	for questId, line in pairs(r.record.quests) do
		local isImmediate, _, _, result, ms, title = strsplit("|", line, 6)
		if isImmediate == "1" then immediate = immediate + 1 end
		if counts[result] then counts[result] = counts[result] + 1 end
		if result == "ok" then
			local value = tonumber(ms) or 0
			totalMs = totalMs + value
			if value > maxMs then maxMs = value end
		end
		local ours = qcQuestDatabase[questId] and qcQuestDatabase[questId][2]
		if title ~= "" and ours and title ~= ours then
			differ = differ + 1
			if #examples < 5 then examples[#examples + 1] = string.format("  [%d] ours %q, client %q", questId, ours, title) end
		end
	end
	r.record.finished = time()
	r.record.stopped = stopped or nil
	say(string.format("%s %s (%d): %d quests. %d named straight away; %d requested: %d loaded, %d failed, %d no answer (%d answered late). Loaded in %d ms on average, %d ms at most. %d names differ from ours.",
		stopped and "Stopped" or "Finished", r.record.categoryName, r.record.category, r.total, immediate,
		r.total - immediate, counts.ok, counts.fail, counts.timeout + counts.late, counts.late,
		counts.ok > 0 and math.floor(totalMs / counts.ok) or 0, maxMs, differ))
	for _, line in ipairs(examples) do print(line) end
	say("/reload to save the results.")
end

local function tick()
	local r = run
	if not r then return end
	local now = debugprofilestop()
	for questId, started in pairs(r.inFlight) do
		if now - started > REQUEST_TIMEOUT_MS then
			r.inFlight[questId] = nil
			r.inFlightCount = r.inFlightCount - 1
			r.timedOut[questId] = started
			r.record.quests[questId] = row(false, false, false, "timeout", nil, nil)
		end
	end
	while r.inFlightCount < MAX_IN_FLIGHT and r.nextIndex <= #r.queue do
		local questId = r.queue[r.nextIndex]
		r.nextIndex = r.nextIndex + 1
		r.inFlight[questId] = debugprofilestop()
		r.inFlightCount = r.inFlightCount + 1
		C_QuestLog.RequestLoadQuestByID(questId)
	end
	if r.inFlightCount == 0 and r.nextIndex > #r.queue then
		if next(r.timedOut) and not r.lateWaitUntil then
			r.lateWaitUntil = now + LATE_ANSWER_WAIT_MS
		end
		if not next(r.timedOut) or now > r.lateWaitUntil then
			finish(false)
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function(_, _, questId, success)
	local r = run
	if not r then return end
	local started, late = r.inFlight[questId], false
	if started then
		r.inFlight[questId] = nil
		r.inFlightCount = r.inFlightCount - 1
	elseif r.timedOut[questId] then
		started, late = r.timedOut[questId], true
		r.timedOut[questId] = nil
	else
		return
	end
	local title, fromTask = clientTitle(questId)
	local result = late and "late" or (success and "ok" or "fail")
	r.record.quests[questId] = row(false, fromTask, HaveQuestData(questId), result, debugprofilestop() - started, title)
end)

local function start(categoryId)
	local quests = {}
	for questId, entry in pairs(qcQuestDatabase) do
		if entry[5] == categoryId then quests[#quests + 1] = questId end
	end
	table.sort(quests)
	if #quests == 0 then
		say(string.format("no quests in category %d.", categoryId))
		return
	end

	qcQuestTitleProbeResults = qcQuestTitleProbeResults or {}
	local version, build = GetBuildInfo()
	local record = {category = categoryId, categoryName = qcCategoryName(categoryId) or "?", locale = GetLocale(),
		build = string.format("%s.%s", tostring(version), tostring(build)), started = time(),
		runInUiSession = runsThisSession + 1, quests = {}}
	runsThisSession = runsThisSession + 1
	table.insert(qcQuestTitleProbeResults, record)

	local queue = {}
	for _, questId in ipairs(quests) do
		local title, fromTask = clientTitle(questId)
		if title then
			record.quests[questId] = row(true, fromTask, HaveQuestData(questId), "-", nil, title)
		else
			queue[#queue + 1] = questId
		end
	end

	run = {record = record, total = #quests, queue = queue, nextIndex = 1, inFlight = {}, inFlightCount = 0,
		timedOut = {}}
	say(string.format("title check: %s (%d), %d quests, %d already named, requesting %d...", record.categoryName,
		categoryId, #quests, #quests - #queue, #queue))
	run.ticker = C_Timer.NewTicker(TICK_SECONDS, tick)
end

function qcQuestTitleProbe(argument)
	if argument == "stop" then
		if run then finish(true) else say("no title check is running.") end
		return
	end
	if run then
		say("a title check is already running; /qc titlecheck stop first.")
		return
	end
	local categoryId = tonumber(argument)
	if not categoryId then
		local mapId = C_Map.GetBestMapForUnit("player")
		categoryId = mapId and qcAreaIDToCategoryID[mapId]
		if not categoryId then
			say("this zone has no category; give one: /qc titlecheck <category>.")
			return
		end
	end
	start(categoryId)
end
