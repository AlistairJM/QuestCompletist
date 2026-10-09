--[[
Checks the probe (tools/ForeverProbe/QCForeverProbe) offline, with stand-ins for the WoW API that play
out a run on a clock of their own and look at the table the game would save.

What it covers: the quest pass (answered, failed, never answered, late, already cached, the number in
flight, rerun and "all", stopping), the NPC pass (named at once, on a re-check, late, never; placeholders
and hidden names), the map pass (answered, not answered, asked again, Forever's and retail's differences),
the recorder (every event it reads, a giver that is hidden or not a creature, a start without a giver),
the commands and the saved table surviving being written out and read back. What it can't: whether
the game really answers as these stand-ins do. docs/maintenance.md, "In the game", is the run to try.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-Probe.lua
]]

local PROBE_DIR = arg and arg[1] or "tools/ForeverProbe/QCForeverProbe"
local TICK_MS = 50

local failed, passed = 0, 0
local function check(condition, message)
	if condition then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. message)
	end
end

local function equal(actual, expected, message)
	check(actual == expected, message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

local function contains(text, part, message)
	check(type(text) == "string" and text:find(part, 1, true) ~= nil, message .. " (no '" .. part .. "' in: " .. tostring(text) .. ")")
end

local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

local source = readFile(PROBE_DIR .. "/QCForeverProbe.lua")

local SECRET = newproxy()

-- A world: the API stand-ins, what the game and the server answer (w.S), and the probe loaded into them.
local function newWorld(options)
	options = options or {}
	local w = {printed = {}, tickers = {}, requests = {}, calls = {}, handlers = {}}
	local S = {
		ms = 100000, locale = "enUS", map = 84, pos = {0.45349, 0.67812},
		quests = {}, cached = {}, loaded = {}, answer = {}, sequence = {}, npcs = {}, npcCalls = 0,
		guid = {}, names = {}, available = {}, active = {}, greetingAvailable = {}, greetingActive = {},
		questId = 0, logIndex = {}, log = {}, maps = {}, lines = {}, mapAnswers = {}, level = 12,
		faction = "Alliance", race = "NightElf", class = "ROGUE",
	}
	w.S = S
	local env = setmetatable({}, {__index = _G})
	w.env = env
	env.print = function(text) w.printed[#w.printed + 1] = text end
	env.debugprofilestop = function() return S.ms end
	env._G = env
	env.GetLocale = function() return S.locale end
	env.GetBuildInfo = function() return unpack(options.build or {"1.60.1", "70245", "Oct 5 2026", 160001}) end
	env.time = function() return 1790000000 end
	env.issecretvalue = function(v) return v == SECRET end
	env.strsplit = function(delimiter, text)
		local parts, start = {}, 1
		while true do
			local from, to = text:find(delimiter, start, true)
			if not from then parts[#parts + 1] = text:sub(start); break end
			parts[#parts + 1] = text:sub(start, from - 1)
			start = to + 1
		end
		return unpack(parts)
	end
	env.strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
	env.RETRIEVING_DATA, env.RETRIEVING_ITEM_INFO, env.UNKNOWN, env.UNKNOWNOBJECT =
		"Retrieving data...", "Retrieving item information", "Unknown", "Unknown Entity"
	env.SlashCmdList = {}
	env.UnitLevel = function() return S.level end
	env.UnitFactionGroup = function() return S.faction end
	env.UnitRace = function() return "Night Elf", S.race end
	env.UnitClass = function() return "Rogue", S.class end
	env.UnitGUID = function(token)
		if w.guidError then error("UnitGUID failed") end
		return S.guid[token]
	end
	env.UnitName = function(token) return S.names[token] end
	env.C_AddOns = {GetAddOnMetadata = function() return options.toc or "camelot" end}
	env.C_Map = {
		GetBestMapForUnit = function() return S.map end,
		GetPlayerMapPosition = function()
			if not S.pos then return nil end
			return {GetXY = function() return S.pos[1], S.pos[2] end}
		end,
		GetMapInfo = function(mapID)
			local m = S.maps[mapID]
			if not m then return nil end
			return {mapID = mapID, name = m.name, mapType = m.mapType or 3, parentMapID = m.parent or 0}
		end,
		GetMapLevels = function(mapID)
			local m = S.maps[mapID]
			if m and m.levels then return m.levels[1], m.levels[2] end
			return 0, 0
		end,
		CanSetUserWaypointOnMap = function() return true end,
	}
	env.C_Timer = {
		NewTicker = function(_, callback)
			local ticker = {callback = callback, active = true}
			ticker.Cancel = function(self) self.active = false end
			w.tickers[#w.tickers + 1] = ticker
			return ticker
		end,
	}
	env.C_GossipInfo = {
		GetAvailableQuests = function() return S.available end,
		GetActiveQuests = function() return S.active end,
	}
	env.GetNumAvailableQuests = function() return #S.greetingAvailable end
	env.GetAvailableQuestInfo = function(i)
		local q = S.greetingAvailable[i]
		return false, q.frequency, q.repeatable, false, q.id
	end
	env.GetNumActiveQuests = function() return #S.greetingActive end
	env.GetActiveQuestID = function(i) return S.greetingActive[i] end
	env.GetQuestID = function() return S.questId end

	local function fact(questId, key) local q = S.quests[questId]; return q and q[key] end
	env.C_QuestLog = {
		GetTitleForQuestID = function(questId)
			if S.cached[questId] or S.loaded[questId] then return fact(questId, "title") or "A quest" end
			return ""
		end,
		RequestLoadQuestByID = function(questId)
			w.requests[#w.requests + 1] = {id = questId, sentAt = S.ms}
			w.calls.RequestLoadQuestByID = (w.calls.RequestLoadQuestByID or 0) + 1
			local sentAt = S.ms
			local concurrent = 0
			for _, r in ipairs(w.requests) do
				if not r.answered and S.ms - r.sentAt <= 5000 then concurrent = concurrent + 1 end
			end
			w.maxConcurrent = math.max(w.maxConcurrent or 0, concurrent)
			local answer = S.answer[questId] or "ok"
			if S.sequence[questId] then answer = table.remove(S.sequence[questId], 1) or "ok" end
			if answer == "never" then return end
			local delay, success = 300, true
			if answer == "fail" then success = false end
			if answer == "late" then delay = 12000 end
			w.pending = w.pending or {}
			w.pending[#w.pending + 1] = {at = sentAt + delay, id = questId, success = success, request = w.requests[#w.requests]}
		end,
		GetQuestDifficultyLevel = function(questId) return fact(questId, "level") end,
		GetQuestTagInfo = function(questId) return fact(questId, "tag") end,
		IsEliteQuest = function(questId) return fact(questId, "elite") end,
		IsRepeatableQuest = function(questId) return fact(questId, "repeatable") end,
		GetQuestType = function(questId) return fact(questId, "questType") end,
		GetSuggestedGroupSize = function(questId) return fact(questId, "group") end,
		GetLogIndexForQuestID = function(questId) return S.logIndex[questId] end,
		GetInfo = function(i) return S.log[i] end,
		GetQuestsOnMap = function(mapID) return S.mapAnswers[mapID] and S.mapAnswers[mapID].logQuests or {} end,
	}
	env.C_QuestInfoSystem = {GetQuestClassification = function(questId) return fact(questId, "class") end}
	env.C_QuestLine = {
		RequestQuestLinesForMap = function(mapID)
			w.calls.RequestQuestLinesForMap = (w.calls.RequestQuestLinesForMap or 0) + 1
			w.mapRequests = w.mapRequests or {}
			w.mapRequests[mapID] = (w.mapRequests[mapID] or 0) + 1
			local plan = S.mapAnswers[mapID] or {}
			if plan.never then return end
			w.mapPending = w.mapPending or {}
			local asked = w.mapRequests[mapID]
			local needed = plan.requestRequired or 0
			w.mapPending[#w.mapPending + 1] = {at = S.ms + 200, requestRequired = asked <= needed}
		end,
		GetAvailableQuestLines = function(mapID) return S.lines[mapID] or {} end,
		GetForceVisibleQuests = function(mapID) return S.mapAnswers[mapID] and S.mapAnswers[mapID].forceVisible or {} end,
	}
	env.C_TaskQuest = {GetQuestsOnMap = function(mapID) return S.mapAnswers[mapID] and S.mapAnswers[mapID].tasks or {} end}
	env.C_TooltipInfo = {
		GetHyperlink = function(link)
			S.npcCalls = S.npcCalls + 1
			local npcId = tonumber(link:match("Creature%-0%-0%-0%-0%-(%d+)%-"))
			if not npcId then return nil end
			local npc = S.npcs[npcId]
			local lines = {{leftText = env.RETRIEVING_DATA}}
			if npc and S.ms >= npc.at then
				lines = {{leftText = npc.name}}
				for _, text in ipairs(npc.more or {}) do lines[#lines + 1] = {leftText = text} end
			end
			return {lines = lines, dataInstanceID = 1000 + npcId}
		end,
	}
	if options.forever then
		env.C_GameRules = {GetForeverExperiencePreset = function() return 0 end, IsHardcoreActive = function() return false end}
	end
	env.CreateFrame = function()
		local frame = {events = {}}
		frame.RegisterEvent = function(self, event) self.events[event] = true end
		frame.SetScript = function(self, name, handler) if name == "OnEvent" then w.onEvent = handler end end
		w.frame = frame
		return frame
	end

	w.chunk = assert(loadstring(source, "QCForeverProbe.lua"))
	setfenv(w.chunk, env)
	w.probe = {questBuild = options.questBuild or "1.60.1.70245", questIds = options.questIds or {}, npcIds = options.npcIds or {}}

	function w.fire(event, ...) w.onEvent(w.frame, event, ...) end
	function w.boot()
		w.chunk("QCForeverProbe", w.probe)
		w.fire("ADDON_LOADED", "QCForeverProbe")
		w.fire("PLAYER_LOGIN")
	end
	function w.slash(text) env.SlashCmdList.QCFOREVERPROBE(text) end
	function w.say() return w.printed[#w.printed] end
	function w.said(part)
		for _, line in ipairs(w.printed) do if line:find(part, 1, true) then return true end end
		return false
	end
	function w.running()
		for _, t in ipairs(w.tickers) do if t.active then return true end end
		return false
	end
	function w.step()
		S.ms = S.ms + TICK_MS
		for i = #(w.pending or {}), 1, -1 do
			local p = w.pending[i]
			if S.ms >= p.at then
				table.remove(w.pending, i)
				p.request.answered = true
				if p.success then S.loaded[p.id] = true end
				w.fire("QUEST_DATA_LOAD_RESULT", p.id, p.success)
			end
		end
		for i = #(w.mapPending or {}), 1, -1 do
			local p = w.mapPending[i]
			if S.ms >= p.at then
				table.remove(w.mapPending, i)
				w.fire("QUESTLINE_UPDATE", p.requestRequired)
			end
		end
		for _, t in ipairs(w.tickers) do
			if t.active then t.callback() end
		end
	end
	function w.run(maxSeconds)
		local steps = 0
		while w.running() and steps < (maxSeconds or 3600) * 1000 / TICK_MS do
			w.step()
			steps = steps + 1
		end
		return steps * TICK_MS / 1000
	end
	function w.db() return env.QCForeverProbeDB end
	return w
end

local function quests(n, from)
	local ids = {}
	for i = 0, n - 1 do ids[#ids + 1] = (from or 1000) + i end
	return ids
end

-- The saved table is written out and read back the way the game does it: plain data only.
local function serialize(value, out, seen)
	local kind = type(value)
	if kind == "table" then
		check(not seen[value], "the saved table has no loops")
		seen[value] = true
		out[#out + 1] = "{"
		for k, v in pairs(value) do
			out[#out + 1] = "["
			serialize(k, out, seen)
			out[#out + 1] = "]="
			serialize(v, out, seen)
			out[#out + 1] = ","
		end
		out[#out + 1] = "}"
		seen[value] = nil
	elseif kind == "string" then
		out[#out + 1] = string.format("%q", value)
	elseif kind == "number" or kind == "boolean" then
		out[#out + 1] = tostring(value)
	else
		check(false, "the saved table holds a " .. kind)
	end
end

local function roundTrips(db, message)
	local out = {}
	serialize(db, out, {})
	local text = table.concat(out)
	local back = assert(loadstring("return " .. text))()
	check(type(back) == "table" and next(back) ~= nil, message .. ": the saved table reads back")
	return back
end

-- 1. Starting up -----------------------------------------------------------------------------------

do
	local w = newWorld({toc = "camelot"})
	w.boot()
	local db = w.db()
	check(db ~= nil, "S1: the saved variable is made")
	for _, key in ipairs({"quests", "npcs", "givers", "started", "accepted", "maps", "runs", "logins"}) do
		check(type(db[key]) == "table", "S1: " .. key .. " is a table")
	end
	equal(db.recording, true, "S1: the recorder is on by default")
	equal(#db.logins, 1, "S1: one login row")
	equal(db.logins[1].build, "1.60.1.70245", "S1: with the build as version.number")
	equal(db.logins[1].toc, "camelot", "S1: and the TOC")
	equal(db.logins[1].loadTest, nil, "S1: and no load test (it is retired)")
	check(w.said("loaded from the camelot TOC on 1.60.1.70245"), "S1: the login line says where it loaded from")
	w.fire("PLAYER_LOGIN")
	equal(#db.logins, 1, "S1: the same build and TOC again adds no row")
	local w2 = newWorld({toc = "plain", build = {"12.1.0", "69933", "Oct 1 2026", 120100}})
	w2.boot()
	equal(w2.db().logins[1].build, "12.1.0.69933", "S1: retail's build")
	w2.slash("")
	check(w2.said("/qcprobe quests"), "S1: an empty command prints the usage")
	w2.slash("nonsense")
	check(w2.said("/qcprobe quests"), "S1: and so does an unknown one")
	w2.slash("stop")
	equal(w2.say(), "|cFFFFD100QC Forever probe:|r nothing is running.", "S1: stop with nothing running")
end

-- 2. The quest pass --------------------------------------------------------------------------------

do
	local w = newWorld({questIds = quests(8)})
	w.S.quests[1000] = {title = "Plains", level = 5, tag = {tagID = 1, tagName = "Group", isElite = true}, elite = true,
		repeatable = false, questType = 0, group = 3, class = 2}
	for i = 1001, 1007 do w.S.quests[i] = {title = "Quest " .. i, level = 10 + (i - 1000)} end
	w.S.answer[1001] = "fail"
	w.S.answer[1002] = "never"
	w.S.answer[1003] = "late"
	w.S.cached[1004] = true
	w.boot()
	w.slash("quests")
	check(w.running(), "Q1: the pass starts")
	check(w.said("quest pass: asking about 8, 4 at a time"), "Q1: and says what it asks")
	w.run(120)
	check(not w.running(), "Q1: and ends")
	local db = w.db()
	equal(db.quests[1000].result, "ok", "Q1: an answered quest is ok")
	equal(db.quests[1000].build, "1.60.1.70245", "Q1: with the build")
	equal(db.quests[1000].title, "Plains", "Q1: its title")
	equal(db.quests[1000].level, 5, "Q1: its level")
	equal(db.quests[1000].tagID, 1, "Q1: its tag")
	equal(db.quests[1000].tagName, "Group", "Q1: its tag name")
	equal(db.quests[1000].tagElite, true, "Q1: its tag elite flag")
	equal(db.quests[1000].elite, true, "Q1: its elite flag")
	equal(db.quests[1000].repeatable, false, "Q1: its repeatable answer, false kept")
	equal(db.quests[1000].questType, 0, "Q1: its quest type")
	equal(db.quests[1000].groupSize, 3, "Q1: its group size")
	equal(db.quests[1000].classification, 2, "Q1: its classification")
	check(db.quests[1000].ms and db.quests[1000].ms >= 250 and db.quests[1000].ms <= 400, "Q1: and how long the server took")
	equal(db.quests[1001].result, "fail", "Q1: a refused quest is fail")
	equal(db.quests[1001].title, nil, "Q1: and has no facts but the result")
	equal(db.quests[1002].result, "timeout", "Q1: one never answered is a timeout")
	equal(db.quests[1003].result, "late", "Q1: one answered after the timeout is late")
	equal(db.quests[1003].title, "Quest 1003", "Q1: and has its facts")
	equal(db.quests[1004].result, "cached", "Q1: one the game already had is cached")
	equal(db.quests[1004].ms, nil, "Q1: with no time")
	check(w.maxConcurrent <= 4, "Q1: never more than 4 in flight (" .. tostring(w.maxConcurrent) .. ")")
	equal(w.calls.RequestLoadQuestByID, 9, "Q1: a request for each but the cached one, and a second for the two that got no answer in time")
	local run = db.runs[#db.runs]
	equal(run.kind, "quests", "Q1: the run row is a quest run")
	equal(run.asked, 8, "Q1: asked")
	equal(run.answered, 8, "Q1: answered")
	equal(run.counts.ok, 4, "Q1: four ok")
	equal(run.counts.fail, 1, "Q1: one failed")
	equal(run.counts.late, 1, "Q1: one late")
	equal(run.counts.timeout, 1, "Q1: one still timed out, and the timeout turned late is not counted twice")
	equal(run.counts.cached, 1, "Q1: one cached")
	equal(run.inFlight, 4, "Q1: in flight, 4")
	equal(run.stopped, nil, "Q1: not stopped")
	check(w.said("Finished the quest pass: 8 of 8"), "Q1: the closing line")
	check(w.said("quest pass: asking about 8, 4 at a time"), "Q1: asked about 8 though two were asked twice")
	roundTrips(db, "Q1")

	-- a rerun asks only about what has not answered
	local before = w.calls.RequestLoadQuestByID
	w.S.answer[1001], w.S.answer[1002] = nil, nil
	w.slash("quests")
	w.run(120)
	equal(w.calls.RequestLoadQuestByID - before, 2, "Q2: a rerun asks the failed and the timed-out quests, and no more")
	equal(db.quests[1001].result, "ok", "Q2: the failed quest answers now")
	equal(db.quests[1002].result, "ok", "Q2: and the timed-out one")
	equal(db.quests[1003].result, "cached", "Q2: a late one is asked again, and the game has it by now")
	w.slash("quests")
	check(w.said("every quest is answered on this build"), "Q2: nothing to ask once all answered")
	check(not w.running(), "Q2: and no run starts")
	before = w.calls.RequestLoadQuestByID
	w.slash("quests all")
	w.run(120)
	equal(w.calls.RequestLoadQuestByID - before, 0, "Q2: 'all' asks every quest again, and the game answers each from its cache")
	equal(db.quests[1004].result, "cached", "Q2: so every row reads cached")
	equal(db.quests[1000].result, "cached", "Q2: even the ones that were ok")
	equal(db.quests[1000].title, "Plains", "Q2: with their facts kept")

	-- a new build asks everything again
	local w3 = newWorld({questIds = quests(3), build = {"1.60.1", "70300", "Oct 20 2026", 160001}, questBuild = "1.60.1.70245"})
	w3.boot()
	w3.slash("quests")
	check(w3.said("the quest list is from build 1.60.1.70245, and this is 1.60.1.70300"), "Q3: a list from another build is flagged")
	w3.run(60)
	w3.db().quests[1000].build = "1.60.1.70245"
	w3.slash("quests")
	w3.run(60)
	equal(w3.db().quests[1000].build, "1.60.1.70300", "Q3: and an answer from another build is asked again")
end

do
	local w = newWorld({questIds = quests(40)})
	for i = 1000, 1039 do w.S.quests[i] = {title = "Q" .. i} end
	w.boot()
	w.slash("quests 2")
	w.run(300)
	check(w.maxConcurrent <= 2, "Q4: 'quests 2' keeps 2 in flight (" .. tostring(w.maxConcurrent) .. ")")
	equal(w.db().runs[#w.db().runs].inFlight, 2, "Q4: and the run row says 2")
	w.slash("quests all 3")
	check(w.running() or w.said("quest pass"), "Q4: a pass with 'all' starts")
	w.run(300)

	-- stop in the middle
	local w2 = newWorld({questIds = quests(40)})
	for i = 1000, 1039 do w2.S.quests[i] = {title = "Q" .. i} end
	w2.boot()
	w2.slash("quests")
	for _ = 1, 40 do w2.step() end
	w2.slash("quests")
	check(w2.said("the quest pass is running. /qcprobe stop first."), "Q5: a second pass is refused while one runs")
	w2.slash("maps")
	check(w2.said("the quest pass is running. /qcprobe stop first."), "Q5: and so is a map pass")
	w2.slash("stop")
	check(not w2.running(), "Q5: stop ends the pass")
	local row = w2.db().runs[#w2.db().runs]
	equal(row.stopped, true, "Q5: the run row says stopped")
	check(row.answered < 40, "Q5: before the end")
	check(w2.said("Stopped the quest pass"), "Q5: and the closing line says so")
	w2.slash("quests")
	w2.run(300)
	local done = 0
	for _, f in pairs(w2.db().quests) do if f.result == "ok" then done = done + 1 end end
	equal(done, 40, "Q5: the rerun finishes the rest")
end

do
	local w = newWorld({questIds = quests(1200)})
	for i = 1000, 2199 do w.S.quests[i] = {title = "Q"} end
	w.boot()
	w.slash("quests 4")
	w.run(3600)
	local progress = 0
	for _, line in ipairs(w.printed) do if line:find("|r quest pass: %d+ of 1200 %(") then progress = progress + 1 end end
	equal(progress, 2, "Q6: a progress line every 500 quests")
end

-- A quest that gets no answer is asked a second time; one that answers late after both is late.
do
	local w = newWorld({questIds = quests(3)})
	for i = 1000, 1002 do w.S.quests[i] = {title = "Q" .. i} end
	w.S.sequence[1000] = {"never", "ok"}
	w.S.sequence[1001] = {"never", "never"}
	w.S.sequence[1002] = {"never", "never", "ok"}
	w.boot()
	w.slash("quests")
	w.run(300)
	local db = w.db()
	equal(db.quests[1000].result, "ok", "Q7: a quest that answers the second time is ok")
	equal(db.quests[1001].result, "timeout", "Q7: one that gets no answer twice is a timeout")
	equal(db.quests[1002].result, "timeout", "Q7: and a third try is not made")
	equal(w.calls.RequestLoadQuestByID, 6, "Q7: six requests for three quests")
	local run = db.runs[#db.runs]
	equal(run.asked, 3, "Q7: three asked")
	equal(run.answered, 3, "Q7: and three answered")
	equal(run.counts.ok, 1, "Q7: one ok")
	equal(run.counts.timeout, 2, "Q7: two timeouts")
end

-- HaveQuestData answers for a quest the game has, with no title yet
do
	local w = newWorld({questIds = quests(2)})
	w.S.quests[1000] = {title = "Has data"}
	w.S.quests[1001] = {title = "Does not"}
	w.env.HaveQuestData = function(questId) return questId == 1000 end
	w.boot()
	w.slash("quests")
	w.run(60)
	equal(w.db().quests[1000].result, "cached", "Q8: a quest the game has data for is cached without a request")
	equal(w.db().quests[1001].result, "ok", "Q8: another is asked")
	equal(w.calls.RequestLoadQuestByID, 1, "Q8: one request")
	local w2 = newWorld({questIds = quests(1)})
	w2.S.quests[1000] = {title = "x"}
	w2.env.HaveQuestData = function() error("HaveQuestData failed") end
	w2.boot()
	w2.slash("quests")
	w2.run(60)
	equal(w2.db().quests[1000].result, "ok", "Q8: a HaveQuestData that errors is as if it said no")
end

-- The progress line says how long is left
do
	local w = newWorld({questIds = quests(600)})
	for i = 1000, 1599 do w.S.quests[i] = {title = "Q"} end
	w.boot()
	w.slash("quests")
	w.run(3600)
	local line
	for _, text in ipairs(w.printed) do if text:find("|r quest pass: 500 of 600", 1, true) then line = text end end
	check(line ~= nil and line:find(", about %d+ min left%.$") ~= nil, "Q9: the progress line gives the minutes left (" .. tostring(line) .. ")")
end

-- 3. The NPC pass ----------------------------------------------------------------------------------

do
	local w = newWorld({npcIds = {196, 197, 198, 199, 200, 201, 202}})
	local S = w.S
	S.npcs[196] = {name = "Kobold Worker", at = 0, more = {"Level 1", "Miner", "Extra", "Fifth"}}
	S.npcs[197] = {name = "Late Namer", at = S.ms + 2500}
	S.npcs[198] = {name = "Way Late", at = S.ms + 7000}
	S.npcs[199] = {name = "Unknown", at = 0}
	S.npcs[200] = {name = "", at = 0}
	-- 201 is never named, 202 has no entry at all
	S.npcs[201] = {name = "Retrieving data...", at = 0}
	w.boot()
	w.slash("npcs")
	check(w.running(), "N1: the NPC pass starts")
	w.run(300)
	local db = w.db()
	equal(db.npcs[196].result, "now", "N1: a name there at once is now")
	equal(db.npcs[196].name, "Kobold Worker", "N1: its name")
	equal(db.npcs[196].lines, "Level 1 / Miner / Extra", "N1: tooltip lines 2 to 4")
	equal(db.npcs[197].result, "poll", "N1: a name that comes on a re-check is poll")
	equal(db.npcs[197].name, "Late Namer", "N1: its name")
	check(db.npcs[197].ms and db.npcs[197].ms >= 2000 and db.npcs[197].ms < 4000, "N1: and how long it took")
	equal(db.npcs[198].result, "late", "N1: a name after the timeout is late")
	equal(db.npcs[198].name, "Way Late", "N1: its name")
	equal(db.npcs[199].result, "none", "N1: the game's 'Unknown' is not a name")
	equal(db.npcs[199].name, nil, "N1: and none is kept")
	equal(db.npcs[200].result, "none", "N1: an empty name is not a name")
	equal(db.npcs[201].result, "none", "N1: a placeholder is not a name")
	equal(db.npcs[202].result, "none", "N1: an NPC the game never names is none")
	local run = db.runs[#db.runs]
	equal(run.kind, "npcs", "N1: the run row is an NPC run")
	equal(run.asked, 7, "N1: asked")
	equal(run.counts.now, 1, "N1: one now")
	equal(run.counts.poll, 1, "N1: one poll")
	equal(run.counts.late, 1, "N1: one late")
	equal(run.counts.none, 4, "N1: four none")
	check(w.said("Finished the NPC pass: 7 of 7"), "N1: the closing line")
	roundTrips(db, "N1")

	local calls = S.npcCalls
	w.slash("npcs")
	w.run(300)
	check(S.npcCalls - calls > 0, "N2: a rerun asks the NPCs that never answered")
	equal(db.npcs[196].result, "now", "N2: and leaves the named ones alone")
	calls = S.npcCalls
	for id = 199, 202 do db.npcs[id] = {build = "1.60.1.70245", result = "now", name = "x"} end
	db.npcs[196].result, db.npcs[197].result, db.npcs[198].result = "now", "poll", "late"
	w.slash("npcs")
	check(w.said("every NPC is named on this build"), "N2: nothing left to ask")
	w.slash("npcs all")
	w.run(300)
	check(S.npcCalls > calls, "N2: 'npcs all' asks every NPC again")

	-- a hidden name is not kept
	local w2 = newWorld({npcIds = {500}})
	w2.S.npcs[500] = {name = SECRET, at = 0}
	w2.boot()
	w2.slash("npcs")
	w2.run(120)
	equal(w2.db().npcs[500].result, "none", "N3: a name the game hides is not a name")
	equal(w2.db().npcs[500].name, nil, "N3: and is not kept")
end

-- 4. The map pass ----------------------------------------------------------------------------------

do
	local w = newWorld({forever = true})
	local S = w.S
	S.maps = {[1] = {name = "Teldrassil", levels = {1, 10}}, [2] = {name = "Darkshore", parent = 1}, [3] = {name = "Silent"}, [4] = {name = "Stubborn"}}
	S.lines[1] = {{questLineID = 7, questLineName = "Line", questID = 99, questName = "Quest", x = 0.5, y = 0.25, startMapID = 1,
		isHidden = false, isCampaign = true}}
	S.mapAnswers[1] = {forceVisible = {55}, tasks = {{questID = 12, x = 0.1, y = 0.2, mapID = 1, isQuestStart = true}}}
	S.mapAnswers[3] = {never = true}
	S.mapAnswers[4] = {requestRequired = 5}
	w.boot()
	w.slash("maps")
	check(w.running(), "M1: the map pass starts")
	w.run(300)
	local db = w.db()
	equal(db.maps[1].result, "event", "M1: an answered map is event")
	equal(db.maps[1].name, "Teldrassil", "M1: its name")
	equal(db.maps[1].preset, 0, "M1: Forever's experience preset")
	equal(db.maps[1].questLines[1].questLineID, 7, "M1: the offers")
	equal(db.maps[1].questLines[1].x, 50, "M1: positions are map percentages")
	equal(db.maps[1].questLines[1].y, 25, "M1: both of them")
	equal(db.maps[1].questLines[1].campaign, true, "M1: flags kept")
	equal(db.maps[1].questLines[1].hidden, nil, "M1: and false flags left out")
	equal(db.maps[1].forceVisible[1], 55, "M1: the forced quests")
	equal(db.maps[1].tasks[1].questID, 12, "M1: the tasks")
	equal(db.maps[1].tasks[1].x, 10, "M1: with percentages")
	equal(db.maps[1].levels[2], 10, "M1: the map's levels")
	equal(db.maps[2].parent, 1, "M1: the parent map")
	equal(db.maps[3].result, "noevent", "M1: a map that sends no update is noevent")
	equal(db.maps[4].result, "unanswered", "M1: a map that keeps asking for another request is unanswered")
	equal(db.maps[4].requests, 3, "M1: after three requests")
	equal(w.mapRequests[1], 1, "M1: one request for a map that answers")
	local run = db.runs[#db.runs]
	equal(run.kind, "maps", "M1: the run row is a map run")
	equal(run.asked, 4, "M1: asked")
	equal(run.counts.event, 2, "M1: two answered")
	equal(run.counts.noevent, 1, "M1: one not")
	equal(run.counts.unanswered, 1, "M1: one unanswered")
	equal(run.waitSeconds, 2, "M1: the wait is 2 seconds by default")
	equal(run.preset, 0, "M1: the run row keeps the preset")
	equal(run.character, "Alliance NightElf ROGUE", "M1: and the character")
	check(run.scheduler ~= nil and run.scheduler.missing, "M1: no events scheduler is noted as missing")
	roundTrips(db, "M1")

	local w2 = newWorld({})
	w2.S.maps = {[1] = {name = "Elwynn"}}
	w2.boot()
	w2.slash("maps 1")
	w2.run(120)
	equal(w2.db().maps[1].preset, nil, "M2: retail has no experience preset")
	equal(w2.db().runs[#w2.db().runs].waitSeconds, 1, "M2: 'maps 1' waits 1 second")
	local w3 = newWorld({})
	w3.boot()
	w3.slash("maps")
	check(w3.said("the client lists no maps."), "M3: a client with no maps says so")
	check(not w3.running(), "M3: and runs nothing")
end

-- 5. The recorder ----------------------------------------------------------------------------------

do
	local w = newWorld({})
	local S = w.S
	w.boot()
	S.guid.npc = "Creature-0-3770-1-2000-3702-0000ABCD12"
	S.names.npc = "Stable Master Gil"
	S.available = {{questID = 102, questLevel = 8, frequency = 0, repeatable = false}, {questID = 103, questLevel = 9, frequency = 1, repeatable = true}}
	S.active = {{questID = 104}}
	w.fire("GOSSIP_SHOW")
	local giver = w.db().givers["Creature:3702"]
	check(giver ~= nil, "R1: a gossip window records the giver")
	equal(giver.name, "Stable Master Gil", "R1: with its name")
	equal(giver.kind, "Creature", "R1: and its kind")
	equal(giver.id, 3702, "R1: and its ID")
	check(giver.offers[102] ~= nil and giver.offers[103] ~= nil, "R1: its offers")
	equal(giver.offers[102].level, 8, "R1: the quest's level")
	equal(giver.offers[103].repeatable, true, "R1: the repeatable flag")
	equal(giver.offers[103].frequency, 1, "R1: and the frequency")
	equal(giver.offers[102].lowestPlayerLevel, 12, "R1: the lowest player level")
	check(giver.offers[102].seenBy["Alliance NightElf ROGUE"], "R1: who saw it")
	check(giver.turnIns[104], "R1: the quests it takes in")
	local spots = 0
	for spot, n in pairs(giver.spots) do
		spots = spots + 1
		equal(spot, "84 45.3 67.8", "R1: the spot is map and percentages")
		equal(n, 1, "R1: seen once")
	end
	equal(spots, 1, "R1: one spot")
	w.fire("GOSSIP_SHOW")
	local seen
	for _, n in pairs(giver.spots) do seen = n end
	equal(seen, 2, "R1: and seen twice")

	S.greetingAvailable = {{id = 110, frequency = 0, repeatable = false}}
	S.greetingActive = {111}
	S.guid.npc = "GameObject-0-3770-1-2000-2001-0000ABCD12"
	w.fire("QUEST_GREETING")
	check(w.db().givers["GameObject:2001"] ~= nil, "R2: a greeting window records an object")
	check(w.db().givers["GameObject:2001"].offers[110] ~= nil, "R2: its offer")
	check(w.db().givers["GameObject:2001"].turnIns[111], "R2: and its turn-in")

	S.guid.npc = "Creature-0-3770-1-2000-3702-0000ABCD12"
	S.questId = 120
	w.fire("QUEST_DETAIL", 0)
	check(giver.offers[120] ~= nil, "R3: a quest window adds its offer to the giver")
	S.questId = 121
	S.guid.npc = nil
	w.fire("QUEST_DETAIL", 6948)
	check(w.db().started[121] ~= nil, "R3: a quest with no giver is a start")
	equal(w.db().started[121].item, 6948, "R3: with the item that started it")
	equal(w.db().started[121].map, 84, "R3: and where")
	S.guid.npc = "Creature-0-3770-1-2000-3702-0000ABCD12"
	S.questId = 104
	w.fire("QUEST_COMPLETE")
	check(giver.turnIns[104], "R3: a completed quest is a turn-in")

	S.logIndex[300] = 3
	S.log = {{isHeader = true, title = "Darkshore"}, {isHeader = false, title = "x"}, {isHeader = false, title = "y"}}
	w.fire("QUEST_ACCEPTED", 300)
	equal(w.db().accepted[300].heading, "Darkshore", "R4: an accepted quest keeps the log heading above it")
	equal(w.db().accepted[300].level, 12, "R4: and the player's level")

	S.guid.npc = SECRET
	local count = 0
	for _ in pairs(w.db().givers) do count = count + 1 end
	w.fire("GOSSIP_SHOW")
	local after = 0
	for _ in pairs(w.db().givers) do after = after + 1 end
	equal(after, count, "R5: a giver the game hides is not recorded")
	S.guid.npc = "Player-3770-0ABCDEF"
	w.fire("GOSSIP_SHOW")
	after = 0
	for _ in pairs(w.db().givers) do after = after + 1 end
	equal(after, count, "R5: nor a player")
	w.guidError = true
	S.guid.npc = "Creature-0-3770-1-2000-3702-0000ABCD12"
	w.fire("GOSSIP_SHOW")
	w.fire("GOSSIP_SHOW")
	local errors = 0
	for _, line in ipairs(w.printed) do if line:find("the recorder hit an error on GOSSIP_SHOW", 1, true) then errors = errors + 1 end end
	equal(errors, 1, "R5: an error in the recorder is said once")
	w.guidError = nil

	w.slash("record off")
	check(w.said("the recorder is off."), "R6: record off says so")
	equal(w.db().recording, false, "R6: and turns it off")
	S.questId = 130
	w.fire("QUEST_DETAIL", 0)
	check(giver.offers[130] == nil, "R6: nothing is recorded while it is off")
	w.slash("record on")
	equal(w.db().recording, true, "R6: record on turns it back on")
	roundTrips(w.db(), "R6")
end

-- 6. Status and a position that is not there --------------------------------------------------------

do
	local w = newWorld({questIds = quests(3), npcIds = {1, 2}})
	for i = 1000, 1002 do w.S.quests[i] = {title = "Q"} end
	w.boot()
	w.slash("quests")
	w.run(60)
	w.slash("status")
	check(w.said("on 1.60.1.70245: 3 of 3 quests answered (ok 3); 0 of 2 NPCs (nothing)"), "T1: status counts quests and NPCs")
	check(w.said("Maps on 1.60.1.70245: 0 asked"), "T1: and maps")
	w.S.pos = nil
	w.S.guid.npc = "Creature-0-3770-1-2000-3702-0000ABCD12"
	w.S.available = {{questID = 1}}
	w.fire("GOSSIP_SHOW")
	local spot = next(w.db().givers["Creature:3702"].spots)
	equal(spot, "84", "T2: with no position only the map is kept")
end

print(string.format("%d checks passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
