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
	-- The map tree and where each child sits on its parent: S.maps[id] has parent, mapType (3, a zone, when
	-- left out), flags, group, navBarInvalid and rects[parentID] = {minX, maxX, minY, maxY}. The hit test
	-- names the smallest rectangle holding a point, the first of equals.
	local function childrenOf(mapID, mapType, allDescendants, into)
		into = into or {}
		local ids = {}
		for id, m in pairs(S.maps) do
			if (m.parent or 0) == mapID then ids[#ids + 1] = id end
		end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local m = S.maps[id]
			if mapType == nil or (m.mapType or 3) == mapType then
				into[#into + 1] = {mapID = id, name = m.name, mapType = m.mapType or 3, parentMapID = mapID, flags = m.flags or 0}
			end
			if allDescendants then childrenOf(id, mapType, true, into) end
		end
		return into
	end
	if not options.noChildrenApi then
		env.C_Map.GetMapChildrenInfo = function(mapID, mapType, allDescendants) return childrenOf(mapID, mapType, allDescendants) end
		env.C_Map.GetMapRectOnMap = function(childID, topID)
			local m = S.maps[childID]
			local rect = m and m.rects and m.rects[topID]
			if rect == "secret" then return SECRET, SECRET, SECRET, SECRET end
			if rect then return rect[1], rect[2], rect[3], rect[4] end
		end
		env.C_Map.GetMapInfoAtPosition = function(mapID, x, y)
			local best, bestArea
			for _, child in ipairs(childrenOf(mapID)) do
				local rect = S.maps[child.mapID].rects and S.maps[child.mapID].rects[mapID]
				if type(rect) == "table" and x >= rect[1] and x <= rect[2] and y >= rect[3] and y <= rect[4] then
					local area = (rect[2] - rect[1]) * (rect[4] - rect[3])
					if not best or area < bestArea then best, bestArea = child, area end
				end
			end
			return best
		end
		env.C_Map.IsMapValidForNavBarDropdown = function(mapID) return not (S.maps[mapID] and S.maps[mapID].navBarInvalid) end
		env.C_Map.GetMapGroupID = function(mapID) return S.maps[mapID] and S.maps[mapID].group end
	end
	env.Enum = {UIMapType = {Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6}}
	if options.worldMap then
		local shown = options.worldMap
		env.UIParent = {GetEffectiveScale = function() return 0.64 end}
		env.WorldMapFrame = {
			ScrollContainer = {
				GetSize = function() return 697, 465 end,
				Child = {GetSize = function() return 3840, 2560 end},
				GetCanvasScale = function() return 0.1815 end,
				zoomLevels = {{}, {}, {}, {}, {}, {}, {}, {}},
			},
			GetMapID = function() return 12 end,
			IsShown = function() return shown ~= "hidden" end,
			IsMaximized = function() return false end,
		}
	end
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
	-- The facts pass: each function exists unless the options say the client lacks it.
	local function defineFacts()
		local missing = options.missing or {}
		local function answer(key) return function(questId)
			if w.factError == key then error(key .. " failed") end
			if w.factHidden == key then return SECRET end
			return fact(questId, key)
		end end
		local function put(owner, name, key) if not missing[key] then owner[name] = answer(key) end end
		put(env.C_QuestLog, "IsQuestTask", "isTask")
		put(env.C_QuestLog, "IsWorldQuest", "isWorld")
		put(env.C_QuestLog, "IsAccountQuest", "accountQuest")
		put(env.C_QuestLog, "IsImportantQuest", "important")
		put(env.C_QuestLog, "IsMetaQuest", "meta")
		env.C_QuestLine = env.C_QuestLine or {}
		if not missing.questLineID then
			env.C_QuestLine.GetQuestLineInfo = function(questId) local id = fact(questId, "questLineID"); return id and {questLineID = id, questLineName = "A line"} or nil end
		end
		if not missing.campaignID then env.C_CampaignInfo = {GetCampaignID = answer("campaignID")} end
		if not missing.taskZone then env.C_TaskQuest = env.C_TaskQuest or {}; env.C_TaskQuest.GetQuestZoneID = answer("taskZone") end
		if options.factionGlobal then env.GetQuestFactionGroup = answer("factionGroup") end
		if options.factionNamespaced then env.C_QuestLog.GetQuestFactionGroup = answer("factionGroup") end
		if options.undocumented then
			env.GetQuestExpansion = answer("expansion")
			env.IsBreadcrumbQuest = answer("breadcrumb")
			env.IsStoryQuest = answer("story")
		end
	end
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
	defineFacts()
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

-- The facts pass
do
	local w = newWorld({questIds = quests(6), factionGlobal = true, undocumented = true})
	local S = w.S
	S.quests[1000] = {title = "Task", isTask = true, isWorld = true, taskZone = 1234, accountQuest = false, important = true, meta = false,
		factionGroup = 1, questLineID = 77, campaignID = 5, expansion = 9, breadcrumb = false, story = true}
	S.quests[1001] = {title = "Plain", isTask = false, isWorld = false, taskZone = 99}
	S.quests[1002] = {title = "Fails"}
	S.quests[1003] = {title = "Never"}
	S.quests[1004] = {title = "Cached", accountQuest = true}
	S.answer[1002] = "fail"
	S.answer[1003] = "never"
	S.cached[1004] = true
	S.quests[1005] = {title = "Odd", isTask = true, taskZone = {1}, expansion = "ten"}
	w.boot()
	w.slash("quests")
	w.run(300)
	local db = w.db()
	local q = db.quests[1000]
	equal(q.isTask, true, "F1: IsQuestTask")
	equal(q.isWorld, true, "F1: IsWorldQuest")
	equal(q.taskZone, 1234, "F1: the zone of a task quest")
	equal(q.accountQuest, false, "F1: IsAccountQuest, false kept")
	equal(q.important, true, "F1: IsImportantQuest")
	equal(q.meta, false, "F1: IsMetaQuest, false kept")
	equal(q.factionGroup, 1, "F1: the faction group, from the global")
	equal(q.questLineID, 77, "F1: the quest line's ID, out of the table GetQuestLineInfo returns")
	equal(q.campaignID, 5, "F1: the campaign")
	equal(q.expansion, 9, "F1: the expansion, from an undocumented global")
	equal(q.breadcrumb, false, "F1: IsBreadcrumbQuest")
	equal(q.story, true, "F1: IsStoryQuest")
	equal(db.quests[1001].isTask, false, "F1: a quest that is no task")
	equal(db.quests[1001].taskZone, nil, "F1: is not asked for a zone")
	equal(db.quests[1001].questLineID, nil, "F1: a quest in no line has none")
	equal(db.quests[1001].campaignID, nil, "F1: nor a campaign")
	equal(db.quests[1002].accountQuest, nil, "F1: a failed quest has no facts")
	equal(db.quests[1003].accountQuest, nil, "F1: nor a timed-out one")
	equal(db.quests[1004].result, "cached", "F1: a cached quest")
	equal(db.quests[1004].accountQuest, true, "F1: has its facts")
	equal(db.quests[1005].taskZone, nil, "F1: an answer that is a table is not kept")
	equal(db.quests[1005].expansion, "ten", "F1: a string is")
	local found = db.runs[#db.runs].facts
	equal(found.accountQuest, "C_QuestLog.IsAccountQuest", "F2: the run row says which function answered")
	equal(found.factionGroup, "GetQuestFactionGroup", "F2: the faction group's came from the global")
	equal(found.questLineID, "C_QuestLine.GetQuestLineInfo", "F2: the quest line's")
	equal(found.campaignID, "C_CampaignInfo.GetCampaignID", "F2: the campaign's")
	equal(found.taskZone, "C_TaskQuest.GetQuestZoneID", "F2: the task zone's")
	equal(found.expansion, "GetQuestExpansion", "F2: an undocumented global that exists is named")
	roundTrips(db, "F2")

	local w2 = newWorld({questIds = quests(2), missing = {accountQuest = true, expansion = true, questLineID = true, campaignID = true}, factionNamespaced = true})
	w2.S.quests[1000] = {title = "A", accountQuest = true, important = true, factionGroup = 2, expansion = 3}
	w2.S.quests[1001] = {title = "B", meta = true}
	w2.boot()
	w2.slash("quests")
	w2.run(120)
	local found2 = w2.db().runs[#w2.db().runs].facts
	equal(found2.accountQuest, false, "F3: a function the client lacks is false in the run row")
	equal(found2.expansion, false, "F3: and so is an undocumented one that isn't there")
	equal(found2.breadcrumb, false, "F3: and the other two")
	equal(found2.questLineID, false, "F3: and a namespace without it")
	equal(found2.campaignID, false, "F3: and a missing namespace")
	equal(found2.factionGroup, "C_QuestLog.GetQuestFactionGroup", "F3: the namespaced faction function comes first")
	equal(w2.db().quests[1000].accountQuest, nil, "F3: so there is no answer in the rows")
	equal(w2.db().quests[1000].important, true, "F3: the others are kept")
	equal(w2.db().quests[1000].factionGroup, 2, "F3: the namespaced faction group")
	equal(w2.db().quests[1001].meta, true, "F3: another quest's")

	local w3 = newWorld({questIds = quests(2)})
	w3.S.quests[1000] = {title = "A", important = true, meta = true}
	w3.S.quests[1001] = {title = "B", important = true, meta = true}
	w3.factError = "important"
	w3.boot()
	w3.slash("quests")
	w3.run(120)
	equal(w3.db().quests[1000].important, nil, "F4: a fact whose function errors is left out")
	equal(w3.db().quests[1000].meta, true, "F4: and the rest are asked")
	equal(w3.db().quests[1000].result, "ok", "F4: and the quest still answers")
	local w4 = newWorld({questIds = quests(1)})
	w4.S.quests[1000] = {title = "A", important = true, meta = true}
	w4.factHidden = "important"
	w4.boot()
	w4.slash("quests")
	w4.run(60)
	equal(w4.db().quests[1000].important, nil, "F5: a fact the game hides is left out")
	equal(w4.db().quests[1000].meta, true, "F5: and the rest are kept")
end

-- Refused quests: no facts are kept, but each function is tallied on them
do
	local w = newWorld({questIds = quests(4), factionGlobal = true})
	local S = w.S
	S.quests[1000] = {title = "Loads", questLineID = 3, accountQuest = true}
	S.quests[1001] = {title = "Refused", questLineID = 5, accountQuest = false, important = true, isTask = true, taskZone = 7}
	S.quests[1002] = {title = "Refused too", accountQuest = false, isTask = false}
	S.quests[1003] = {title = "Never", questLineID = 9}
	S.answer[1001] = "fail"
	S.answer[1002] = "fail"
	S.answer[1003] = "never"
	w.boot()
	w.slash("quests")
	w.run(300)
	local db = w.db()
	local row = db.runs[#db.runs]
	local t = row.refusedFacts
	equal(db.quests[1001].questLineID, nil, "R1: a refused quest keeps no facts")
	equal(db.quests[1001].result, "fail", "R1: only its result")
	equal(t.questLineID.asked, 2, "R1: each function is asked about every refused quest")
	equal(t.questLineID.answered, 1, "R1: how many answered anything")
	equal(t.questLineID.positive, 1, "R1: and how many with something other than no")
	equal(t.questLineID.examples[1], 1001, "R1: the first of them are named")
	equal(t.accountQuest.answered, 2, "R2: a false is an answer")
	equal(t.accountQuest.positive, 0, "R2: but not a positive one")
	equal(#t.accountQuest.examples, 0, "R2: and has no example")
	equal(t.important.asked, 2, "R3: asked of both")
	equal(t.important.positive, 1, "R3: true counts")
	equal(t.taskZone.asked, 1, "R4: a task zone is asked only where the quest is a task")
	equal(t.taskZone.positive, 1, "R4: and a number above 0 counts")
	equal(t.factionGroup.asked, 2, "R5: the faction group's function is there")
	equal(t.factionGroup.answered, 0, "R5: and answered nothing")
	equal(t.expansion, nil, "R6: a function the client lacks is not tallied")
	equal(t.questLineID.asked + 0, 2, "R6: and a timed-out quest is not counted as refused")
	roundTrips(db, "R7")

	local w2 = newWorld({questIds = quests(2)})
	for i = 1000, 1001 do w2.S.quests[i] = {title = "Q" .. i} end
	w2.S.answer[1000] = "fail"
	w2.boot()
	w2.slash("quests")
	w2.run(120)
	local row2 = w2.db().runs[#w2.db().runs]
	check(type(row2.character) == "string" and row2.character ~= "", "C1: a quest run's row says which character ran it")
	equal(row2.level, w2.S.level, "C1: and its level")
	check(not row2.character:find("%d%d%d"), "C1: and nothing that names it")
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

-- 4b. The geometry pass ----------------------------------------------------------------------------

local function geometryMaps()
	return {
		[947] = {name = "Azeroth", mapType = 1},
		[12] = {name = "Kalimdor", mapType = 2, parent = 947, rects = {[947] = {0.1, 0.5, 0.2, 0.8}}},
		[1] = {name = "Durotar", parent = 12, rects = {[12] = {0.5, 0.7, 0.4, 0.6}}},
		[3] = {name = "Orgrimmar", parent = 1, rects = {[1] = {0.1, 0.2, 0.1, 0.2}}},
		[7] = {name = "Mulgore", parent = 12, rects = {[12] = {0.3, 0.55, 0.5, 0.75}}},
		[88] = {name = "Thunder Bluff", parent = 12, rects = {[12] = {0.40, 0.45, 0.60, 0.65}}},
		[249] = {name = "Uldum", parent = 12, flags = 0, group = 5, rects = {[12] = {0.2, 0.3, 0.1, 0.2}}},
		[1527] = {name = "Uldum", parent = 12, flags = 524288, group = 5, navBarInvalid = true, rects = {[12] = {0.2, 0.3, 0.1, 0.2}}},
		[2] = {name = "Lost Isle", parent = 12},
		[4] = {name = "Hidden Isle", parent = 12, rects = {[12] = "secret"}},
		[627] = {name = "Dalaran", mapType = 4, parent = 12, rects = {[12] = {0.8, 0.85, 0.8, 0.85}}},
		[2537] = {name = "Quel'Thalas", mapType = 2, parent = 12, rects = {[12] = {0.6, 0.9, 0.0, 0.1}}},
		[8] = {name = "Flat", parent = 12, rects = {[12] = {0.9, 0.9, 0.5, 0.6}}},
	}
end

local function childOf(row, mapID)
	for _, child in ipairs(row.children) do
		if child.mapID == mapID then return child end
	end
end

local function join(list)
	local parts = {}
	for _, v in ipairs(list) do parts[#parts + 1] = tostring(v) end
	return table.concat(parts, ",")
end

do
	local w = newWorld({forever = true, worldMap = true})
	w.S.maps = geometryMaps()
	w.boot()
	w.slash("geometry")
	check(w.said("geometry on 1.60.1.70245: 3 continent, world and cosmic maps with 11 child maps, 8 of them zones; 2 have no rectangle, and 2 have a centre the game assigns to another map."),
		"G1: the command says what it found")
	check(not w.running(), "G1: and runs nothing in the background")
	local db = w.db()
	local row = db.geometry[12]
	check(row ~= nil, "G1: a continent has a row")
	equal(row.name, "Kalimdor", "G1: its name")
	equal(row.mapType, 2, "G1: its type")
	equal(row.parent, 947, "G1: its parent")
	equal(row.build, "1.60.1.70245", "G1: its build")
	equal(row.toc, "camelot", "G1: the TOC, which says the game")
	equal(row.preset, 0, "G1: Forever's preset")
	equal(#row.children, 10, "G1: every direct child of any type")
	equal(join(row.zoneCall), "1,2,4,7,8,88,249,1527", "G1: the zone filter's answer")
	equal(join(row.zoneTree), "1,3,2,4,7,8,88,249,1527", "G1: and with descendants, which adds the nested zone")
	local durotar = childOf(row, 1)
	equal(join(durotar.rect), "0.5,0.7,0.4,0.6", "G1: a child's rectangle")
	equal(durotar.hit.mapID, 1, "G1: the hit test at its centre names it")
	equal(durotar.navBar, true, "G1: the nav bar lists it")
	equal(childOf(row, 7).hit.mapID, 88, "G1: a zone whose centre lies in a smaller zone is named for that one")
	equal(childOf(row, 7).hit.name, "Thunder Bluff", "G1: with the name")
	equal(childOf(row, 1527).navBar, false, "G1: a map the nav bar leaves out")
	equal(childOf(row, 1527).flags, 524288, "G1: its flags")
	equal(childOf(row, 1527).group, 5, "G1: its map group")
	equal(childOf(row, 1527).hit.mapID, 249, "G1: and its twin, which has the same rectangle, takes its centre")
	equal(childOf(row, 2).noRect, true, "G1: a child with no rectangle")
	equal(childOf(row, 2).rect, nil, "G1: has none kept")
	equal(childOf(row, 4).noRect, true, "G1: a rectangle the game hides is no rectangle")
	equal(childOf(row, 8).rect[1], 0.9, "G1: a flat rectangle is kept")
	equal(childOf(row, 8).hit, nil, "G1: but its centre is not tested")
	equal(childOf(row, 8).noHit, nil, "G1: and not counted as a miss")
	equal(childOf(row, 627).mapType, 4, "G1: a dungeon child is kept")
	equal(childOf(row, 2537).mapType, 2, "G1: and a nested continent")
	equal(row.grid.columns, 60, "G1: the grid's columns")
	equal(row.grid.rows, 40, "G1: and rows")
	local cell = row.grid.cells[1]
	check(cell and cell.n > 50, "G1: the grid sees Durotar in many cells")
	check(cell and math.abs(cell.x - 60) < 1.5 and math.abs(cell.y - 50) < 1.5, "G1: and puts its centre near the rectangle's")
	check(row.grid.none > 0, "G1: cells over no child count as none")
	equal(row.grid.cells[3], nil, "G1: a nested zone is not on the grid")
	equal(db.geometry[947].children[1].mapID, 12, "G1: the world map lists the continent")
	equal(join(db.geometry[947].children[1].rect), "0.1,0.5,0.2,0.8", "G1: with its rectangle")
	check(db.geometry[2537] ~= nil and #db.geometry[2537].children == 0, "G1: a continent with no children has a row with none")
	equal(db.geometry[2537].grid, nil, "G1: and no grid")
	equal(db.geometry[1], nil, "G1: a zone has no row")
	local run = db.runs[#db.runs]
	equal(run.kind, "geometry", "G1: the run row is a geometry run")
	equal(run.geometry.continents, 3, "G1: it counts the continents")
	equal(run.geometry.children, 11, "G1: the children")
	equal(run.geometry.zones, 8, "G1: the zones")
	equal(run.geometry.noRect, 2, "G1: the ones with no rectangle")
	equal(run.geometry.hitsOther, 2, "G1: and the centres another map takes")
	equal(run.view.width, 697, "G1: the map window's width")
	equal(run.view.childWidth, 3840, "G1: the canvas's width")
	equal(run.view.zoomLevels, 8, "G1: the zoom levels")
	equal(run.view.maximized, false, "G1: whether it is maximised")
	equal(run.view.mapID, 12, "G1: the map it showed")
	equal(run.view.canvasScale, 0.1815, "G1: the canvas scale")
	equal(run.view.uiScale, 0.64, "G1: the UI scale")
	roundTrips(db, "G1")
	w.slash("status")
	check(w.said("Geometry on 1.60.1.70245: 3 continent, world and cosmic maps with 11 child maps."), "G1: status counts it")

	local w2 = newWorld({toc = "plain"})
	w2.S.maps = geometryMaps()
	w2.boot()
	w2.slash("geometry")
	equal(w2.db().geometry[12].toc, "plain", "G2: retail's TOC")
	equal(w2.db().geometry[12].preset, nil, "G2: and no preset")
	equal(w2.db().runs[#w2.db().runs].view, nil, "G2: no map window, no view")
	check(w2.said("The map window could not be read."), "G2: and it says so")

	local w3 = newWorld({forever = true, worldMap = true, noChildrenApi = true})
	w3.S.maps = geometryMaps()
	w3.boot()
	w3.slash("geometry")
	equal(#w3.db().geometry[12].children, 0, "G3: a client without the child call gives no children")
	equal(#w3.db().geometry[12].zoneCall, 0, "G3: nor a zone list")
	equal(w3.db().geometry[12].grid, nil, "G3: and no grid is sampled for a map with no children")
	equal(w3.db().runs[#w3.db().runs].geometry.children, 0, "G3: the run row counts none")

	local w4 = newWorld({forever = true, worldMap = true})
	w4.S.maps = geometryMaps()
	w4.boot()
	w4.slash("maps 1")
	w4.run(3600)
	check(w4.db().geometry[12] ~= nil, "G4: a map pass takes the geometry at its end")
	local mapRun = w4.db().runs[#w4.db().runs]
	equal(mapRun.kind, "maps", "G4: the run row is the map run's")
	equal(mapRun.geometry.continents, 3, "G4: with the geometry's counts")
	equal(mapRun.view.width, 697, "G4: and the view")
	w4.db().geometry[12].time = 0
	w4.slash("maps 1")
	w4.slash("stop")
	equal(w4.db().geometry[12].time, 0, "G4: a map pass stopped early takes no geometry")

	local w5 = newWorld({forever = true})
	w5.S.maps = geometryMaps()
	w5.boot()
	w5.db().geometry = nil
	w5.slash("maps 1")
	w5.run(3600)
	check(not w5.running(), "G4: a geometry that fails does not stop the map pass from finishing")
	local failedRun = w5.db().runs[#w5.db().runs]
	equal(failedRun.kind, "maps", "G4: the map run is recorded")
	check(type(failedRun.geometryError) == "string", "G4: with the geometry's error")
	equal(failedRun.geometry, nil, "G4: and no counts")
end

-- The report reads what the pass saved.
do
	local report = assert(loadfile("tools/Report-ContinentGeometry.lua"))("module")
	local w = newWorld({forever = true, worldMap = true})
	w.S.maps = geometryMaps()
	w.boot()
	w.slash("geometry")
	local lines, csv = report(w.db())
	local text = table.concat(lines, "\n")
	contains(text, "Geometry on 1.60.1.70245 (forever): 2 maps with children, 1 without (2537).", "G5: the summary line")
	contains(text, "Map window when read: map 12, windowed, 697 x 465, canvas 3840 x 2560 at scale 0.1815, 8 zoom levels, UI scale 0.64.", "G5: the map window")
	contains(text, "12 Kalimdor (type 2, parent 947): 10 children (1 of type 2, 8 of type 3, 1 of type 4); zone filter lists 8, with descendants 9.", "G5: a continent's header")
	contains(text, "The zone filter is exact", "G5: the filter is exact in this world")
	contains(text, "With descendants the call lists 1 more.", "G5: and the tree's extra")
	contains(text, "No rectangle: Lost Isle (2), Hidden Isle (4).", "G5: no rectangle")
	contains(text, "A rectangle with no width or height: Flat (8).", "G5: a flat one")
	contains(text, "Zones listed under one name: Uldum: 249 (navbar true, flags 0), 1527 (navbar false, flags 524288).", "G5: the twins")
	contains(text, "Zones the nav bar does not list: Uldum (1527).", "G5: the nav bar")
	contains(text, "names another map: Mulgore (7) -> Thunder Bluff (88); Uldum (1527) -> Uldum (249).", "G5: the hit test")
	contains(text, "Zones the hit test never names on the 60 x 40 grid: Lost Isle (2), Hidden Isle (4), Flat (8), Uldum (1527).", "G5: zones the grid never names, a twin of equal size among them")
	contains(text, "At 700 px wide, 2 zone icon pairs are closer than 24 px: Mulgore / Thunder Bluff 0 px; Uldum / Uldum 0 px.", "G5: crowding")
	contains(text, "At 697 px wide, 2 zone icon pairs are closer than 24 px.", "G5: and at the window's width")
	equal(#csv, 11, "G5: a row for each child")
	local prefix = '"forever","1.60.1.70245",12,"Kalimdor",1,"Durotar",3,0,true,,0.5,0.7,0.4,0.6,1,"Durotar",'
	equal(csv[1]:sub(1, #prefix), prefix, "G5: a row's columns")
	check(csv[1]:match(',%d+,[%d%.]+,[%d%.]+$') ~= nil, "G5: ending in the grid's cells and centre")

	local back = roundTrips(w.db(), "G5")
	back.geometry[12].zoneCall[#back.geometry[12].zoneCall + 1] = 999
	local text2 = table.concat((report(back)), "\n")
	contains(text2, "The zone filter DIFFERS from the direct children of type zone: only in the call 999; only among the children .", "G5: a filter that is not exact is said so")

	local back3 = roundTrips(w.db(), "G5")
	table.insert(back3.runs, {kind = "geometry", build = "1.60.1.70245", view = {mapID = 12, maximized = true, width = 1517, height = 1011}})
	local text3 = table.concat((report(back3)), "\n")
	contains(text3, "Map window when read: map 12, windowed, 697 x 465", "G5: every map window is listed, the first")
	contains(text3, "Map window when read: map 12, maximised, 1517 x 1011", "G5: and the second")
	contains(text3, "At 1517 px wide, 2 zone icon pairs are closer than 24 px.", "G5: with its width used")

	local lines3 = report({geometry = {}, runs = {}})
	contains(lines3[1], "No geometry in the file.", "G5: an empty file says what to do")
	local back2 = roundTrips(w.db(), "G5")
	back2.geometry[12].build = "1.60.1.70001"
	local text4 = table.concat((report(back2)), "\n")
	contains(text4, "Geometry on 1.60.1.70245 (forever): 1 maps with children", "G5: with two builds the one with most maps is read")
	local text5 = table.concat((report(back2, "1.60.1.70001")), "\n")
	contains(text5, "Geometry on 1.60.1.70001", "G5: and a build can be asked for")
end

-- The baseline: the rows the report writes, read back, and what a sweep compares them with.
do
	local report, parseCsv, recordLine, HEADER = assert(loadfile("tools/Report-ContinentGeometry.lua"))("module")
	local compare = assert(loadfile("tools/Compare-ContinentGeometry.lua"))("module")
	local w = newWorld({forever = true, worldMap = true})
	w.S.maps = geometryMaps()
	w.boot()
	w.slash("geometry")
	local _, csv, records = report(w.db())
	local parsed = parseCsv(HEADER .. "\r\n" .. table.concat(csv, "\r\n") .. "\r\n")
	equal(#parsed, #records, "B1: every row reads back")
	local function find(list, continent, mapId)
		for _, r in ipairs(list) do if r.continent == continent and r.mapId == mapId then return r end end
	end
	local back = find(parsed, 12, 1527)
	equal(back.navBar, false, "B1: a nav bar answer of false stays false, not nothing")
	equal(find(parsed, 12, 1).navBar, true, "B1: and true stays true")
	equal(find(parsed, 947, 12).group, nil, "B1: an empty field is nothing")
	equal(back.flags, 524288, "B1: numbers are numbers")
	equal(back.name, "Uldum", "B1: names are names")
	equal(find(parsed, 12, 2).rect, nil, "B1: a child with no rectangle has none")
	equal(find(parsed, 12, 1).rect[2], 0.7, "B1: a rectangle's numbers")
	equal(find(parsed, 12, 1).hitId, 1, "B1: the hit test's map")
	equal(find(parsed, 12, 1).game, "forever", "B1: the game")
	equal(#compare(records, parsed), 0, "B1: the rows compared with themselves read back differ in nothing")

	local function copy()
		return parseCsv(HEADER .. "\r\n" .. table.concat(csv, "\r\n") .. "\r\n")
	end
	local function one(changeFn, expected, message)
		local now = copy()
		changeFn(now)
		local lines = compare(now, parsed)
		equal(#lines, 1, message .. ": one difference")
		contains(lines[1], expected, message)
	end
	one(function(rows) find(rows, 12, 1).rect[1] = 0.55 end, "changed: Kalimdor (12): Durotar (1): rectangle 0.5000 0.7000 0.4000 0.6000 -> 0.5500 0.7000 0.4000 0.6000", "B2: a zone that moved")
	do
		local now = copy()
		find(now, 12, 1).rect[1] = 0.5001
		equal(#compare(now, parsed), 0, "B2: a move under a twentieth of a map point is not a difference")
	end
	one(function(rows) find(rows, 12, 1).mapType = 4 end, "mapType 3 -> 4", "B2: a map whose type changed")
	one(function(rows) find(rows, 12, 1527).navBar = true end, "navBar false -> true", "B2: the nav bar listing")
	one(function(rows) find(rows, 12, 1527).flags = 0 end, "flags 524288 -> 0", "B2: its flags")
	one(function(rows) find(rows, 12, 7).hitId = 7 end, "hitId 88 -> 7", "B2: what the hit test names")
	one(function(rows) find(rows, 12, 2).rect = {0.1, 0.2, 0.1, 0.2} end, "rectangle none -> 0.1000 0.2000 0.1000 0.2000", "B2: a zone that gained a rectangle")
	one(function(rows) find(rows, 12, 1).name = "Durotar!" end, "name Durotar -> Durotar!", "B2: a name")
	local without = copy()
	for i, r in ipairs(without) do if r.continent == 12 and r.mapId == 627 then table.remove(without, i) break end end
	local lines = compare(without, parsed)
	check(#lines == 1 and lines[1]:find("removed: Kalimdor (12): Dalaran (627)", 1, true), "B2: a child that went")
	lines = compare(parsed, without)
	check(#lines == 1 and lines[1]:find("added:   Kalimdor (12): Dalaran (627) (type 4)", 1, true), "B2: a child that came")

	-- The command line, on files written to the temp folder: its exit status is what a sweep reads.
	local dir = os.getenv("TEMP") or "."
	local stamp = tostring(os.time()) .. tostring(math.random(1000, 9999))
	local savedFile, otherFile, emptyFile, baselineFile = dir .. "\\qcgeo-" .. stamp .. "-a.lua", dir .. "\\qcgeo-" .. stamp .. "-b.lua",
		dir .. "\\qcgeo-" .. stamp .. "-c.lua", dir .. "\\qcgeo-" .. stamp .. ".csv"
	local function save(file, db)
		local out = {}
		serialize(db, out, {})
		local h = assert(io.open(file, "wb"))
		h:write("QCForeverProbeDB = " .. table.concat(out))
		h:close()
	end
	save(savedFile, w.db())
	local retail = newWorld({toc = "plain", worldMap = true})
	retail.S.maps = geometryMaps()
	retail.boot()
	retail.slash("geometry")
	save(otherFile, retail.db())
	save(emptyFile, {geometry = {}, runs = {}})
	local lua = '"' .. (arg and arg[-1] or "lua") .. '"'
	local function run(args)
		return os.execute(lua .. " tools/Compare-ContinentGeometry.lua " .. args .. " > NUL 2>&1")
	end
	local function rowsOf(game)
		local h = assert(io.open(baselineFile, "rb"))
		local rows = parseCsv(h:read("*a"))
		h:close()
		local n = 0
		for _, r in ipairs(rows) do if r.game == game then n = n + 1 end end
		return n
	end
	equal(run(savedFile .. " " .. baselineFile), 1, "B3: with no baseline the exit status is 1")
	equal(run(savedFile .. " " .. baselineFile .. " --update"), 0, "B3: --update makes it, exit 0")
	equal(rowsOf("forever"), #records, "B3: with a row for each child map")
	equal(run(savedFile .. " " .. baselineFile), 0, "B3: the same file compares as the same, exit 0")
	local h = assert(io.open(baselineFile, "rb")); local baselineText = h:read("*a"); h:close()
	local moved = baselineText:gsub("0%.5,0%.7,0%.4,0%.6", "0.5,0.7,0.4,0.61", 1)
	check(moved ~= baselineText, "B3: a zone is moved in the baseline")
	h = assert(io.open(baselineFile, "wb")); h:write(moved); h:close()
	equal(run(savedFile .. " " .. baselineFile), 1, "B3: a rectangle that differs gives exit 1")
	equal(run(savedFile .. " " .. baselineFile .. " --update"), 0, "B3: --update takes it in")
	equal(run(savedFile .. " " .. baselineFile), 0, "B3: and the next comparison is clean")
	equal(run(otherFile .. " " .. baselineFile), 1, "B3: the other game has no rows yet, exit 1")
	local function textOf(game)
		local handle = assert(io.open(baselineFile, "rb"))
		local rows = {}
		for line in handle:read("*a"):gmatch("[^\r\n]+") do
			if line:sub(1, #game + 3) == '"' .. game .. '",' then rows[#rows + 1] = line end
		end
		handle:close()
		return table.concat(rows, "\n")
	end
	local foreverBefore = textOf("forever")
	check(#foreverBefore > 0, "B3: the first game's rows are in the file")
	equal(run(otherFile .. " " .. baselineFile .. " --update"), 0, "B3: --update adds them")
	equal(textOf("forever"), foreverBefore, "B3: and leaves the first game's rows as they were, byte for byte")
	equal(rowsOf("retail") > 0 and rowsOf("forever") == #records, true, "B3: and keeps the first game's rows")
	equal(run(savedFile .. " " .. baselineFile), 0, "B3: each game still compares as the same")
	equal(run(otherFile .. " " .. baselineFile), 0, "B3: both of them")
	do
		local handle = assert(io.open(baselineFile, "rb"))
		local rows = parseCsv(handle:read("*a"))
		handle:close()
		local extra = {}
		for _, r in ipairs(rows) do
			if r.game == "forever" then for k, v in pairs(r) do extra[k] = v end break end
		end
		extra.mapId = 999999
		rows[#rows + 1] = extra
		local lines = {HEADER}
		for _, r in ipairs(rows) do lines[#lines + 1] = recordLine(r) end
		handle = assert(io.open(baselineFile, "wb"))
		handle:write(table.concat(lines, "\r\n"), "\r\n")
		handle:close()
		local pipe = assert(io.popen(lua .. " tools/Compare-ContinentGeometry.lua " .. savedFile .. " " .. baselineFile .. " --update 2>&1"))
		local said = pipe:read("*a")
		pipe:close()
		contains(said, "1 fewer forever rows", "B3: --update says when the baseline loses rows")
		equal(run(savedFile .. " " .. baselineFile), 0, "B3: and the baseline is the dump's again")
	end
	equal(select(2, pcall(parseCsv, HEADER .. "\r\n" .. "\"forever\",\"1.60\r\n")):find("is not closed", 1, true) ~= nil, true, "B3: a row with an unclosed quote is named, not a crash on nil")
	equal(run(emptyFile .. " " .. baselineFile), 2, "B3: a file with no geometry gives exit 2")
	equal(run(""), 2, "B3: no arguments give exit 2")
	for _, file in ipairs({savedFile, otherFile, emptyFile, baselineFile}) do os.remove(file) end
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
