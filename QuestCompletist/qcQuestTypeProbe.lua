--[[ Diagnostic, run with /qc typecheck. Asks the game client how it classifies the addon's quests,
to settle which quests typed daily (4), repeatable (2) or 128 (world quest or weekly) really recur.
The client can tell a recurring quest from a one-time one by quest ID, but not daily from weekly:
frequency is only exposed for quests in the log.

Every quest is asked once as it stands ("cold"). A cold "Recurring" or "WorldQuest" can be trusted,
but a cold "Normal" can't: for a quest whose data isn't cached, Normal is what the client answers
by default. So every quest is then loaded with C_QuestLog.RequestLoadQuestByID and asked again
("warm"), the ones that matter most first - see loadPriority.

The server stops answering load requests sent in a burst, so only a few are in flight at a time;
one that gets no answer is retried once, then marked timed out. Every answer is written as it
arrives: /qc typecheck again resumes, /qc typecheck stop pauses, and /reload saves the results.

qcQuestTypeProbeResults holds one string per quest:
  ourType | classification,repeatable,worldQuest,task,tagID,haveData | classification,repeatable,load
with 1/0 for booleans, "-" for no answer, and load 1 (loaded), 0 (failed) or t (timed out). The
warm part is empty for quests that haven't been through the loading pass.

Delete this file once the answer has been acted on. ]]--

local MAX_IN_FLIGHT = 4
local REQUEST_TIMEOUT = 10
local MAX_ATTEMPTS = 2
local TICK_SECONDS = 0.1
local COLD_PER_FRAME = 1500
local PROGRESS_EVERY = 500

local running, stopRequested = false, false

local function say(message)
	print("|cFFFFD100Quest Completist:|r " .. message)
end

local function flag(value)
	if value == nil then return "-" end
	return value and "1" or "0"
end

local function num(value)
	if value == nil then return "-" end
	return tostring(value)
end

local function ask(fn, ...)
	if not fn then return nil end
	local ok, result = pcall(fn, ...)
	if ok then return result end
	return nil
end

local classify = C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification

local function coldAnswer(questId)
	local tagInfo = ask(C_QuestLog.GetQuestTagInfo, questId)
	return table.concat({
		num(ask(classify, questId)),
		flag(ask(C_QuestLog.IsRepeatableQuest, questId)),
		flag(ask(C_QuestLog.IsWorldQuest, questId)),
		flag(ask(C_QuestLog.IsQuestTask, questId)),
		num(tagInfo and tagInfo.tagID),
		flag(ask(HaveQuestData, questId)),
	}, ",")
end

local function warmAnswer(questId, loadResult)
	return table.concat({
		num(ask(classify, questId)),
		flag(ask(C_QuestLog.IsRepeatableQuest, questId)),
		loadResult,
	}, ",")
end

local function clientVersion()
	local version, build = GetBuildInfo()
	return string.format("%s.%s", tostring(version), tostring(build))
end

-- Every quest that hasn't loaded or definitively failed in an earlier run is loaded, most useful
-- first, so a run stopped early still holds the answers that matter:
--   1. typed 2, 4 or 128, uncached, and not already answering Recurring (5) or WorldQuest (10)
--   2. the rest typed 2, 4 or 128
--   3. everything else
local function loadPriority(row)
	local ourType, cold, warm = row:match("^(%d+)|([^|]*)|([^|]*)$")
	local loadResult = warm:sub(-1)
	if loadResult == "1" or loadResult == "0" then return nil end
	if bit.band(tonumber(ourType), 2 + 4 + 128) == 0 then return 3 end
	local classification, haveData = cold:match("^([^,]+)"), cold:sub(-1)
	if classification == "5" or classification == "10" or haveData == "1" then return 2 end
	return 1
end

local function loadPass(results)
	if not C_QuestLog.RequestLoadQuestByID then
		say("this client has no C_QuestLog.RequestLoadQuestByID, so only the quick pass ran.")
		running = false
		return
	end

	local queue, priority = {}, {}
	for questId, row in pairs(results.quests) do
		priority[questId] = loadPriority(row)
		if priority[questId] then table.insert(queue, questId) end
	end
	table.sort(queue, function(a, b)
		if priority[a] ~= priority[b] then return priority[a] < priority[b] end
		return a < b
	end)
	local total = #queue
	if total == 0 then
		say("type check finished - nothing left to load. /reload to save the results.")
		running = false
		return
	end

	local function record(questId, loadResult)
		local ourType, cold = results.quests[questId]:match("^(%d+)|([^|]*)|")
		results.quests[questId] = string.format("%s|%s|%s", ourType, cold, warmAnswer(questId, loadResult))
	end

	local inFlight, inFlightCount, attempts = {}, 0, {}
	local answered, failed, timedOut, nextIndex = 0, 0, 0, 1
	local started = GetTime()

	local function progress()
		local done = answered + failed + timedOut
		local elapsed = GetTime() - started
		local perMinute = (elapsed > 0) and (done / elapsed * 60) or 0
		local left = (perMinute > 0) and math.ceil((total - done) / perMinute) or 0
		say(string.format("type check %d / %d (%d loaded, %d failed, %d timed out) - about %d min left.", done, total, answered, failed, timedOut, left))
	end

	local listener = CreateFrame("Frame")
	listener:RegisterEvent("QUEST_DATA_LOAD_RESULT")
	listener:SetScript("OnEvent", function(self, event, questId, success)
		if not inFlight[questId] then return end
		inFlight[questId] = nil
		inFlightCount = inFlightCount - 1
		record(questId, success and "1" or "0")
		if success then answered = answered + 1 else failed = failed + 1 end
	end)
	local lastReported = 0

	say(string.format("type check loading %d quests, %d at a time. /qc typecheck stop pauses it; running it again resumes.", total, MAX_IN_FLIGHT))

	local ticker
	ticker = C_Timer.NewTicker(TICK_SECONDS, function()
		local now = GetTime()
		for questId, sentAt in pairs(inFlight) do
			if now - sentAt > REQUEST_TIMEOUT then
				inFlight[questId] = nil
				inFlightCount = inFlightCount - 1
				if attempts[questId] < MAX_ATTEMPTS then
					table.insert(queue, questId)
				else
					record(questId, "t")
					timedOut = timedOut + 1
				end
			end
		end

		while not stopRequested and inFlightCount < MAX_IN_FLIGHT and nextIndex <= #queue do
			local questId = queue[nextIndex]
			nextIndex = nextIndex + 1
			if HaveQuestData(questId) then
				record(questId, "1")
				answered = answered + 1
			else
				attempts[questId] = (attempts[questId] or 0) + 1
				inFlight[questId] = now
				inFlightCount = inFlightCount + 1
				C_QuestLog.RequestLoadQuestByID(questId)
			end
		end

		local done = answered + failed + timedOut
		if done - lastReported >= PROGRESS_EVERY then
			lastReported = done
			progress()
		end

		if stopRequested or (nextIndex > #queue and inFlightCount == 0) then
			ticker:Cancel()
			listener:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
			running, stopRequested = false, false
			progress()
			say("type check " .. ((nextIndex > #queue and inFlightCount == 0) and "finished." or "paused.") .. " /reload to save the results.")
		end
	end)
end

function qcQuestTypeProbe(command)
	if command == "stop" then
		if running then
			stopRequested = true
			say("type check pausing...")
		else
			say("the type check isn't running.")
		end
		return
	end
	if running then
		say("the type check is already running.")
		return
	end
	if not classify then
		say("this client has no C_QuestInfoSystem.GetQuestClassification, so the type check can't run.")
		return
	end
	running = true

	local results = qcQuestTypeProbeResults
	if results and results.client == clientVersion() and results.quests then
		say("type check resuming from the saved results.")
		loadPass(results)
		return
	end

	results = {
		client = clientVersion(),
		locale = GetLocale(),
		generated = date("%Y-%m-%d %H:%M:%S"),
		quests = {},
	}
	qcQuestTypeProbeResults = results

	local ids = {}
	for questId in pairs(qcQuestDatabase) do
		table.insert(ids, questId)
	end
	table.sort(ids)

	local coldIndex = 1
	local function coldPass()
		local stop = math.min(coldIndex + COLD_PER_FRAME - 1, #ids)
		for i = coldIndex, stop do
			local questId = ids[i]
			results.quests[questId] = string.format("%d|%s|", qcQuestDatabase[questId][6], coldAnswer(questId))
		end
		coldIndex = stop + 1
		if coldIndex <= #ids then
			C_Timer.After(0, coldPass)
		else
			say(string.format("type check asked all %d quests.", #ids))
			loadPass(results)
		end
	end

	say("type check started.")
	coldPass()
end
