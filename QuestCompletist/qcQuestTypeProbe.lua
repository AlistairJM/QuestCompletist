--[[ Diagnostic, run with /qc typecheck. Asks the game client how it classifies the addon's quests,
to settle which quests typed daily (4), repeatable (2) or 128 (world quest or weekly) really recur.
The client can tell a recurring quest from a one-time one by quest ID, but not daily from weekly:
frequency is only exposed for quests in the log.

Every quest is asked once as it stands ("cold"). Quests typed 2, 4 or 128, plus every 20th other
quest as a control, are then loaded with C_QuestLog.RequestLoadQuestByID and asked again ("warm"),
in case an answer depends on the quest's data being cached.

Writes qcQuestTypeProbeResults; /reload afterwards to flush it to disk. Each quest is one string:
  ourType | classification,repeatable,worldQuest,task,tagID,haveData | classification,repeatable,load
with 1/0 for booleans, "-" for no answer, and load 1 (loaded), 0 (failed) or t (timed out). The
warm part is empty for quests outside the second pass.

Delete this file once the answer has been acted on. ]]--

local REQUESTS_PER_TICK = 20
local TICK_SECONDS = 0.1
local COLD_PER_FRAME = 1500
local TIMEOUT_SECONDS = 20
local CONTROL_EVERY = 20

local running = false

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

local function isRecurringType(questType)
	return bit.band(questType, 2 + 4 + 128) ~= 0
end

function qcQuestTypeProbe()
	if running then
		print("|cFFFFD100Quest Completist:|r the type check is already running.")
		return
	end
	if not classify then
		print("|cFFFF0000Quest Completist:|r this client has no C_QuestInfoSystem.GetQuestClassification, so the type check can't run.")
		return
	end
	running = true

	local version, build = GetBuildInfo()
	local results = {
		client = string.format("%s.%s", tostring(version), tostring(build)),
		locale = GetLocale(),
		generated = date("%Y-%m-%d %H:%M:%S"),
		api = {
			GetQuestClassification = classify ~= nil,
			IsRepeatableQuest = C_QuestLog.IsRepeatableQuest ~= nil,
			IsWorldQuest = C_QuestLog.IsWorldQuest ~= nil,
			IsQuestTask = C_QuestLog.IsQuestTask ~= nil,
			GetQuestTagInfo = C_QuestLog.GetQuestTagInfo ~= nil,
			RequestLoadQuestByID = C_QuestLog.RequestLoadQuestByID ~= nil,
		},
		quests = {},
	}
	qcQuestTypeProbeResults = results

	local ids = {}
	for questId in pairs(qcQuestDatabase) do
		table.insert(ids, questId)
	end
	table.sort(ids)

	local cold, warm = {}, {}
	local toLoad, pending = {}, {}
	local loaded, failed, timedOut = 0, 0, 0

	local function finish()
		for questId in pairs(pending) do
			warm[questId] = warmAnswer(questId, "t")
			timedOut = timedOut + 1
		end
		for _, questId in ipairs(ids) do
			results.quests[questId] = string.format("%d|%s|%s", qcQuestDatabase[questId][6], cold[questId], warm[questId] or "")
		end
		results.counts = { quests = #ids, warm = #toLoad, loaded = loaded, failed = failed, timedOut = timedOut }
		running = false
		print(string.format("|cFFFFD100Quest Completist:|r type check done - %d quests asked, %d loaded, %d failed, %d timed out. /reload to save the results.", #ids, loaded, failed, timedOut))
	end

	local listener = CreateFrame("Frame")
	listener:SetScript("OnEvent", function(self, event, questId, success)
		if pending[questId] then
			pending[questId] = nil
			warm[questId] = warmAnswer(questId, success and "1" or "0")
			if success then loaded = loaded + 1 else failed = failed + 1 end
		end
	end)

	local function loadPass()
		if not C_QuestLog.RequestLoadQuestByID then
			finish()
			return
		end
		listener:RegisterEvent("QUEST_DATA_LOAD_RESULT")
		local nextIndex, lastSent = 1, GetTime()
		local ticker
		ticker = C_Timer.NewTicker(TICK_SECONDS, function()
			local sent = 0
			while nextIndex <= #toLoad and sent < REQUESTS_PER_TICK do
				local questId = toLoad[nextIndex]
				nextIndex = nextIndex + 1
				if HaveQuestData(questId) then
					warm[questId] = warmAnswer(questId, "1")
					loaded = loaded + 1
				else
					pending[questId] = true
					C_QuestLog.RequestLoadQuestByID(questId)
					sent = sent + 1
					lastSent = GetTime()
				end
				if nextIndex % 1000 == 0 then
					print(string.format("|cFFFFD100Quest Completist:|r type check loading %d / %d...", nextIndex, #toLoad))
				end
			end
			if nextIndex > #toLoad and (next(pending) == nil or GetTime() - lastSent > TIMEOUT_SECONDS) then
				ticker:Cancel()
				listener:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
				finish()
			end
		end)
	end

	local coldIndex = 1
	local function coldPass()
		local stop = math.min(coldIndex + COLD_PER_FRAME - 1, #ids)
		for i = coldIndex, stop do
			local questId = ids[i]
			cold[questId] = coldAnswer(questId)
			if isRecurringType(qcQuestDatabase[questId][6]) or i % CONTROL_EVERY == 0 then
				table.insert(toLoad, questId)
			end
		end
		coldIndex = stop + 1
		if coldIndex <= #ids then
			C_Timer.After(0, coldPass)
		else
			print(string.format("|cFFFFD100Quest Completist:|r type check asked all %d quests; now loading %d of them to ask again (about %d seconds).", #ids, #toLoad, math.ceil(#toLoad / (REQUESTS_PER_TICK / TICK_SECONDS))))
			loadPass()
		end
	end

	print("|cFFFFD100Quest Completist:|r type check started.")
	coldPass()
end
