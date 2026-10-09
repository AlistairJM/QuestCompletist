--[[
Checks the quest giver recorder (QuestCompletist/qcRecorder.lua) offline, with stand-ins for the WoW
API that play out the real event sequences and look at the table the game would save.

What it covers: every event the recorder reads, the three states of the giver's identity (readable,
hidden by the game, not a creature), giverless starts, positions (missing, hidden, merged), English
and other-language clients, the size caps and what they evict, that nothing identifying is stored,
that the saved table survives being written out and read back, errors, and that the report
prints in every language. What it can't: whether the game really answers as these stand-ins do.
docs/plans/quest-giver-recorder.md lists what has to be tried in game.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-Recorder.lua
]]

local ADDON_DIR = arg and arg[1] or "QuestCompletist"
local LOCALES = {"enUS", "ptBR", "frFR", "deDE", "itIT", "koKR", "esMX", "ruRU", "zhCN", "esES", "zhTW"}

local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

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

-- The bit values the quest data uses, taken from the addon itself so they can't drift.
local coreText = readFile(ADDON_DIR .. "/qcCore.lua")
local bitTables = {}
for _, name in ipairs({"qcFactionBits", "qcRaceBits", "qcClassBits"}) do
	local body = assert(coreText:match("\n" .. name .. " = (%b{})"), name .. " not found in qcCore.lua")
	bitTables[name] = assert(loadstring("return " .. body))()
end

-- A hidden value in the game keeps its type but raises on anything done with it. A userdata raises on
-- arithmetic, comparison other than == and concatenation, indexing and the length operator; the type
-- the game would report comes from the replaced type(). Lua 5.1 can't trap == or use as a table key, so
-- those are covered by reading the source for the order of the guards.
local SECRET_STRING, SECRET_NUMBER, SECRET_TABLE, SECRET_BOOLEAN = newproxy(), newproxy(), newproxy(), newproxy()
local SECRET_TYPE = {[SECRET_STRING] = "string", [SECRET_NUMBER] = "number", [SECRET_TABLE] = "table", [SECRET_BOOLEAN] = "boolean"}
local SECRET = SECRET_STRING
local function isSecret(v) return SECRET_TYPE[v] ~= nil end

local function guid(kind, id)
	return string.format("%s-0-3770-1-2000-%d-0000ABCD12", kind, id)
end

-- A world: the API stand-ins, the state they answer from (w.S), and the recorder loaded into them.
local function newWorld(options)
	options = options or {}
	local w = {printed = {}, calls = {}, hooks = {}}
	local S = {
		time = 1000, locale = options.locale or "enUS", map = 84, pos = {0.45349, 0.67812},
		guid = {}, name = {}, faction = "Alliance", race = "NightElf", class = "DRUID",
		available = {}, active = {}, greetingAvailable = {}, greetingActive = {}, questId = 0,
		auto = false, trigger = false, adventure = false, inInstance = false, near = true,
		logIndex = {}, log = {}, worldQuests = {},
	}
	w.S = S
	local env = setmetatable({}, {__index = _G})
	w.env = env
	env.qcFactionBits, env.qcRaceBits, env.qcClassBits = bitTables.qcFactionBits, bitTables.qcRaceBits, bitTables.qcClassBits
	env.bit = {bor = function(a, b)
		local result, power = 0, 1
		while a > 0 or b > 0 do
			if a % 2 == 1 or b % 2 == 1 then result = result + power end
			a, b, power = math.floor(a / 2), math.floor(b / 2), power * 2
		end
		return result
	end}
	env.print = function(text) w.printed[#w.printed + 1] = text end
	env.GetLocale = function() return S.locale end
	env.GetBuildInfo = function() return unpack(options.build or {"12.1.0", "69933", "Oct 1 2026", 120100}) end
	env.GetTime = function() return S.time end
	env.issecretvalue = isSecret
	env.type = function(v) return SECRET_TYPE[v] or type(v) end
	env.tostring = function(v)
		if isSecret(v) then error("tostring of a hidden value") end
		return tostring(v)
	end
	env.RETRIEVING_DATA, env.UNKNOWN, env.UNKNOWNOBJECT = "Retrieving data...", "Unknown", "Unknown"
	env.VIDEO_OPTIONS_ENABLED, env.VIDEO_OPTIONS_DISABLED = "Enabled", "Disabled"
	env.IsInInstance = function() return S.inInstance, "party" end
	env.InCombatLockdown = function() return S.combat end
	env.CheckInteractDistance = function() return S.near end
	env.UnitGUID = function(token)
		w.calls.UnitGUID = (w.calls.UnitGUID or 0) + 1
		w.calls["UnitGUID:" .. tostring(token)] = true
		if S.guidError then error("UnitGUID failed") end
		return S.guid[token]
	end
	env.UnitName = function(token)
		w.calls["UnitName:" .. tostring(token)] = true
		if token == "player" then return "Zzqtest" end
		return S.name[token]
	end
	env.UnitFactionGroup = function() return S.faction end
	env.UnitRace = function() return "Night Elf", S.race end
	env.UnitClass = function() return "Druid", S.class end
	env.C_Map = {
		GetBestMapForUnit = function() return S.map end,
		GetPlayerMapPosition = function()
			if not S.pos then return nil end
			return {GetXY = function() return S.pos[1], S.pos[2] end}
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
	env.GetQuestID = function()
		if S.questIdError then error("GetQuestID failed") end
		return S.questId
	end
	env.QuestIsFromAdventureMap = function() return S.adventure end
	env.QuestGetAutoAccept = function() return S.auto end
	env.QuestIsFromAreaTrigger = function() return S.trigger end
	env.C_QuestLog = {
		GetLogIndexForQuestID = function(q) return S.logIndex[q] end,
		GetInfo = function(i) return S.log[i] end,
		IsWorldQuest = function(q) return S.worldQuests[q] end,
	}
	env.qcLocalize = {}
	for _, locale in ipairs(LOCALES) do
		local chunk = assert(loadstring(readFile(ADDON_DIR .. "/Localization." .. locale .. ".lua"), "@" .. locale))
		setfenv(chunk, env)
		chunk()
	end
	env.CreateFrame = function()
		local frame = {events = {}, scripts = {}}
		function frame:RegisterEvent(event) self.events[event] = true end
		function frame:UnregisterEvent(event) self.events[event] = nil end
		function frame:SetScript(name, fn) self.scripts[name] = fn end
		w.frame = frame
		return frame
	end
	env.hooksecurefunc = function(tbl, name, fn)
		local original = tbl[name]
		tbl[name] = function(...)
			local result = original(...)
			fn(...)
			return result
		end
	end
	if options.tracker ~= false then
		env.QuestObjectiveTracker = {AddAutoQuestPopUp = function() end}
	end
	env.qcSettings = options.settings or {QC_RECORD_GIVERS = 1}
	env.qcApplySettings = function() if env.qcRecorderApply then env.qcRecorderApply() end end
	env.qcQuestRecorder = options.saved
	local QC = {CHAT_TITLE = "QC: "}
	local chunk = assert(loadstring(readFile(ADDON_DIR .. "/qcRecorder.lua"), "@qcRecorder.lua"))
	setfenv(chunk, env)
	chunk("QuestCompletist", QC)

	function w.fire(event, ...)
		if w.frame.events[event] then w.frame.scripts.OnEvent(w.frame, event, ...) end
	end
	function w.login()
		w.fire("ADDON_LOADED", "QuestCompletist")
		w.fire("PLAYER_LOGIN")
	end
	function w.giver(token, kind, id, name)
		S.guid[token] = guid(kind, id)
		S.name[token] = name
	end
	function w.db() return env.qcQuestRecorder end
	function w.fields(record) 
		local parts, from = {}, 1
		while true do
			local at = record:find("|", from, true)
			if not at then parts[#parts + 1] = record:sub(from) break end
			parts[#parts + 1] = record:sub(from, at - 1)
			from = at + 1
		end
		return parts
	end
	function w.advance(seconds) S.time = S.time + seconds end
	return w
end

local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

local function lines(w)
	return table.concat(w.printed, "\n")
end

-- 1. Setup, the setting, the first-run notice.
do
	local w = newWorld()
	w.login()
	local db = w.db()
	equal(db.v, 1, "a new table has the schema number")
	equal(db.bv[69933], "12.1.0", "the build is noted against its version")
	for _, event in ipairs({"GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED"}) do
		check(w.frame.events[event], event .. " is registered while recording is on")
	end
	equal(#w.printed, 1, "the first login prints one line")
	check(w.printed[1]:find("/qc report", 1, true) ~= nil, "the notice names /qc report")
	check(db.noticed, "the notice is remembered")
	check(not w.frame.scripts.OnUpdate, "the recorder has no OnUpdate script")

	w.env.qcRecorderCommand("off")
	equal(w.env.qcSettings.QC_RECORD_GIVERS, 0, "/qc record off sets the setting")
	check(w.frame.events.ADDON_LOADED and w.frame.events.PLAYER_LOGIN, "the login events stay")
	check(not w.frame.events.GOSSIP_SHOW and not w.frame.events.QUEST_DETAIL, "recording events are unregistered while off")
	w.giver("questnpc", "Creature", 3701, "Guard")
	w.S.questId = 100
	w.fire("QUEST_DETAIL")
	equal(count(db.g), 0, "nothing is recorded while off")
	w.env.qcRecorderCommand("on")
	check(w.frame.events.QUEST_DETAIL, "/qc record on registers again")
	w.fire("QUEST_DETAIL")
	equal(count(db.g), 1, "recording resumes")
	w.env.qcRecorderCommand("clear")
	equal(count(db.g) + count(db.q) + count(db.s), 0, "/qc record clear empties the notes")
	equal(db.v, 1, "clearing keeps the schema number")
	check(db.noticed, "clearing keeps the notice flag")

	local second = newWorld({saved = db})
	second.login()
	equal(#second.printed, 0, "the notice is shown once only")
end

-- 2. A single-quest NPC: window, accept, nothing but the heading from the accept.
do
	local w = newWorld()
	w.login()
	w.giver("questnpc", "Creature", 3701, "Guard Roberts")
	w.S.questId = 100
	w.fire("QUEST_DETAIL")
	local db = w.db()
	local giver = db.g["Creature:3701"]
	check(giver ~= nil, "the giver is recorded under kind:id")
	local f = w.fields(giver)
	equal(#f, 7, "a giver record has seven fields")
	equal(f[1], "Guard Roberts", "the giver's name")
	equal(f[2], "69933", "the build")
	equal(f[4], "84 45.3 67.8 1", "the player's place, to a tenth, with one visit")
	equal(f[5], "100", "the quest it offered")
	equal(f[6], "", "no turn-ins yet")
	local q = w.fields(db.q[100])
	equal(#q, 7, "a quest record has seven fields")
	equal(q[3], "32", "offered, nothing known about recurrence")
	equal(q[4], "1", "Alliance")
	equal(q[5], "8", "Night Elf")
	equal(q[6], "1024", "Druid")

	w.S.logIndex[100] = 3
	w.S.log[1] = {isHeader = true, title = "Teldrassil"}
	w.S.log[2] = {isHeader = false, title = "Other quest"}
	w.S.log[3] = {isHeader = false, title = "This quest", frequency = 1}
	w.fire("QUEST_ACCEPTED", 100)
	q = w.fields(db.q[100])
	equal(q[7], "Teldrassil", "the heading above the quest in the log")
	equal(q[3], tostring(1 + 2 + 16 + 32), "accepted, daily, offered")
	equal(db.g["Creature:3701"], giver, "an accept doesn't touch the giver")
end

-- 3. A gossip NPC with several quests, a hand-in, a vendor, a giver the game hides.
do
	local w = newWorld()
	w.login()
	local db = w.db()
	w.giver("npc", "Creature", 500, "Innkeeper Ann")
	w.S.available = {{questID = 100}, {questID = 101, frequency = 1, repeatable = true}}
	w.S.active = {{questID = 102}}
	w.fire("GOSSIP_SHOW")
	local f = w.fields(db.g["Creature:500"])
	equal(f[5], "100,101", "both offered quests")
	equal(f[6], "102", "the quest it takes in")
	equal(w.fields(db.q[101])[3], tostring(1 + 2 + 8 + 32 + 64), "a repeatable daily from the list")
	check(db.q[102] == nil, "a quest only taken in is not a quest note")

	w.advance(100)
	w.S.available = {{questID = 100}, {questID = 103}}
	w.fire("GOSSIP_SHOW")
	f = w.fields(db.g["Creature:500"])
	equal(f[5], "100,101,103", "offers add, never repeat")
	equal(f[4], "84 45.3 67.8 2", "a second visit at the same place")

	w.S.available, w.S.active = {}, {}
	w.giver("npc", "Creature", 501, "Vendor Bob")
	w.fire("GOSSIP_SHOW")
	check(db.g["Creature:501"] == nil, "a vendor with no quests is not recorded")

	w.S.guid.npc = SECRET
	w.S.available = {{questID = 200, frequency = 2}}
	w.fire("GOSSIP_SHOW")
	check(db.q[200] ~= nil, "a hidden giver still leaves the quest's facts")
	equal(count(db.g), 1, "and no giver")
	equal(db.err.n, 0, "a hidden giver is no error")
	check((db.d["rd:GOSSIP_SHOW:npc:hid:w"] or 0) >= 1, "the hidden identity is counted")

	-- A hand-in: progress, then complete, from the same NPC.
	w.S.guid.npc, w.S.guid.questnpc = nil, guid("Creature", 502)
	w.S.name.questnpc = "Captain Dee"
	w.S.questId = 300
	w.fire("QUEST_PROGRESS")
	w.S.questId = 301
	w.fire("QUEST_COMPLETE")
	f = w.fields(db.g["Creature:502"])
	equal(f[6], "300,301", "hand-ins from progress and complete windows")
	equal(f[5], "", "a hand-in is not an offer")
	-- The chain follow-up from the same NPC afterwards.
	w.S.questId = 302
	w.fire("QUEST_DETAIL")
	f = w.fields(db.g["Creature:502"])
	equal(f[5], "302", "the follow-up is an offer of the same giver")
	equal(f[6], "300,301", "and the hand-ins stay")

	-- Auto-complete from the tracker has no NPC.
	w.S.guid.questnpc = nil
	w.S.questId = 303
	local before = count(db.g)
	w.fire("QUEST_COMPLETE")
	equal(count(db.g), before, "a completion with no NPC records nothing")
end

-- 4. A greeting NPC through the older globals, and one that's missing.
do
	local w = newWorld()
	w.login()
	local db = w.db()
	w.giver("npc", "Creature", 600, "Old Man")
	w.S.greetingAvailable = {{id = 400, frequency = 0, repeatable = false}, {id = 401, frequency = 2, repeatable = true}}
	w.S.greetingActive = {402}
	w.fire("QUEST_GREETING")
	local f = w.fields(db.g["Creature:600"])
	equal(f[5], "400,401", "the greeting's offers")
	equal(f[6], "402", "the greeting's turn-in")
	equal(w.fields(db.q[401])[3], tostring(1 + 4 + 8 + 32 + 64), "weekly and repeatable from the greeting")
	w.env.GetAvailableQuestInfo = nil
	w.env.GetActiveQuestID = nil
	w.giver("npc", "Creature", 601, "Other Man")
	w.fire("QUEST_GREETING")
	equal(db.err.n, 0, "a missing greeting function is no error")
end

-- 5. Objects, vehicles, and identities that aren't givers.
do
	local w = newWorld()
	w.login()
	local db = w.db()
	w.giver("questnpc", "GameObject", 175320, "WANTED: Murkdeep!")
	w.S.questId = 700
	w.fire("QUEST_DETAIL")
	check(db.g["GameObject:175320"] ~= nil, "a notice board is a giver")
	w.giver("questnpc", "Vehicle", 900, "Siege Engine")
	w.S.questId = 701
	w.fire("QUEST_DETAIL")
	check(db.g["Vehicle:900"] ~= nil, "a vehicle is a giver")
	for _, kind in ipairs({"Player", "Pet", "Item"}) do
		w.S.guid.questnpc = kind .. "-3770-0000ABCD12"
		w.S.questId = 702
		local before = count(db.g) + count(db.s)
		w.fire("QUEST_DETAIL")
		equal(count(db.g) + count(db.s), before, "a " .. kind .. " GUID makes no giver and no start")
	end
	w.S.guid.questnpc = "garbage"
	w.fire("QUEST_DETAIL")
	equal(db.err.n, 0, "a malformed GUID is no error")
end

-- 6. Quests that start away from any giver.
do
	local w = newWorld()
	w.login()
	local db = w.db()
	-- An item: Blizzard's own handler has closed the window, so our ID may be 0; the popup hook has it.
	w.S.questId = 0
	w.fire("QUEST_DETAIL", 5555)
	equal(count(db.s), 0, "no quest ID, no start from the window")
	w.env.QuestObjectiveTracker:AddAutoQuestPopUp(800, "OFFER", 5555)
	local s = w.fields(db.s[800])
	equal(#s, 7, "a start record has seven fields")
	equal(s[1] .. "|" .. s[2], "1|5555", "an item start names the item")
	equal(s[3] .. " " .. s[4] .. " " .. s[5], "84 45.3 67.8", "and the place")
	-- The popup is clicked far away later: the first place stands.
	w.S.pos = {0.1, 0.2}
	w.S.questId = 800
	w.fire("QUEST_DETAIL")
	equal(db.s[800], table.concat(s, "|"), "a later giverless window changes nothing")
	w.env.QuestObjectiveTracker:AddAutoQuestPopUp(800, "OFFER", 5555)
	equal(db.s[800], table.concat(s, "|"), "the same popup offered again from elsewhere changes nothing")
	-- An area trigger.
	w.S.pos = {0.5, 0.5}
	w.env.QuestObjectiveTracker:AddAutoQuestPopUp(801, "OFFER")
	equal(w.fields(db.s[801])[1], "2", "an area trigger is kind 2")
	w.env.QuestObjectiveTracker:AddAutoQuestPopUp(802, "COMPLETE")
	check(db.s[802] == nil, "a completion popup is not a start")
	-- Through the window events when the quest ID is still there.
	w.S.questId, w.S.auto, w.S.trigger = 803, true, true
	w.fire("QUEST_DETAIL")
	equal(w.fields(db.s[803])[1], "2", "auto-accept from a trigger, through the window")
	w.S.auto, w.S.trigger = false, false
	w.S.questId = 804
	w.fire("QUEST_DETAIL", 6666)
	equal(w.fields(db.s[804])[2], "6666", "an item start, through the window")
	-- A splash screen or clicked popup: no giver, no item, no trigger.
	w.S.questId = 805
	w.fire("QUEST_DETAIL")
	check(db.s[805] == nil, "a plain giverless window records no position")
	-- An adventure map quest.
	w.S.questId, w.S.adventure = 806, true
	w.fire("QUEST_DETAIL")
	check(db.q[806] == nil, "an adventure map quest is skipped")
	equal(db.err.n, 0, "no errors")

	local bare = newWorld({tracker = false})
	bare.login()
	equal(bare.db().d["hook:none"], 1, "a missing tracker is counted")
end

-- 7. Quests that arrive without a window; the ones that are not recorded.
do
	local w = newWorld()
	w.login()
	local db = w.db()
	w.S.logIndex[900] = 1
	w.S.log[1] = {isHeader = false, title = "Shared quest"}
	w.fire("QUEST_ACCEPTED", 900)
	local q = w.fields(db.q[900])
	equal(q[3], "16", "accepted, nothing else known")
	equal(q[7], "", "no heading found")
	equal(count(db.g), 0, "no giver from an accept")
	w.S.worldQuests[901] = true
	w.fire("QUEST_ACCEPTED", 901)
	check(db.q[901] == nil, "a world quest is skipped")
	w.S.logIndex[902], w.S.log[2] = 2, {isTask = true}
	w.fire("QUEST_ACCEPTED", 902)
	check(db.q[902] == nil, "a bonus objective is skipped")
	w.S.logIndex[903], w.S.log[3] = 3, {isHidden = true}
	w.fire("QUEST_ACCEPTED", 903)
	check(db.q[903] == nil, "a hidden quest is skipped")
	w.fire("QUEST_ACCEPTED", -4)
	w.fire("QUEST_ACCEPTED", 1.5)
	w.fire("QUEST_ACCEPTED", SECRET_NUMBER)
	w.fire("QUEST_ACCEPTED", 10000000)
	equal(db.err.n, 0, "bad quest IDs are ignored without error")
	equal(count(db.q), 1, "and leave nothing")
end

-- 8. Positions.
do
	local w = newWorld()
	w.login()
	local db = w.db()
	w.giver("questnpc", "Creature", 1000, "Walker")
	w.S.questId = 1
	w.S.map = nil
	w.fire("QUEST_DETAIL")
	equal(w.fields(db.g["Creature:1000"])[4], "", "no map, no spot")
	check((db.d["pos:nomap"] or 0) >= 1, "and it is counted")
	w.S.map, w.S.pos = 84, false
	w.fire("QUEST_DETAIL")
	equal(w.fields(db.g["Creature:1000"])[4], "84 -1 -1 1", "no position gives -1 -1")
	w.S.pos = {SECRET_NUMBER, 0.5}
	w.advance(100)
	w.fire("QUEST_DETAIL")
	equal(w.fields(db.g["Creature:1000"])[4], "84 -1 -1 2", "a hidden coordinate gives -1 -1")
	equal(db.err.n, 0, "no errors from hidden coordinates")
	w.S.pos = {2, 0.5}
	w.advance(100)
	w.fire("QUEST_DETAIL")
	equal(w.fields(db.g["Creature:1000"])[4], "84 -1 -1 3", "an out-of-range coordinate gives -1 -1")

	local v = newWorld()
	v.login()
	v.giver("questnpc", "Creature", 1001, "Stander")
	v.S.questId = 1
	v.S.pos = {0.45349, 0.67812}
	v.fire("QUEST_DETAIL")
	v.S.pos = {0.459, 0.678}
	v.fire("QUEST_DETAIL")
	equal(v.fields(v.db().g["Creature:1001"])[4], "84 45.3 67.8 1", "a second window within 30 s is the same visit")
	v.advance(31)
	v.fire("QUEST_DETAIL")
	equal(v.fields(v.db().g["Creature:1001"])[4], "84 45.3 67.8 2", "after 30 s it is a new visit, in the first spot")
	v.advance(31)
	v.S.pos = {0.60, 0.678}
	v.fire("QUEST_DETAIL")
	equal(v.fields(v.db().g["Creature:1001"])[4], "84 45.3 67.8 2;84 60.0 67.8 1", "a place 14 points away is a second spot")
	for i = 1, 5 do
		v.advance(31)
		v.S.pos = {0.1 * i / 10 + 0.7, 0.9}
		v.fire("QUEST_DETAIL")
	end
	local spots = 0
	for _ in v.fields(v.db().g["Creature:1001"])[4]:gmatch("[^;]+") do spots = spots + 1 end
	equal(spots, 4, "at most four spots")

	local i = newWorld()
	i.login()
	i.S.inInstance = true
	i.giver("questnpc", "Creature", 1002, "Dungeon NPC")
	i.S.questId = 2
	i.S.pos = false
	i.fire("QUEST_DETAIL")
	equal(i.fields(i.db().g["Creature:1002"])[4], "84 -1 -1 1", "an instance giver is recorded with no position")
	check((i.db().d["rd:QUEST_DETAIL:questnpc:ok:i"] or 0) >= 1, "and counted as read in an instance")
end

-- 9. Names, headings and other-language clients.
do
	local w = newWorld()
	w.login()
	local db = w.db()
	local function nameOf(id) return w.fields(db.g["Creature:" .. id])[1] end
	local function offer(id, name)
		w.giver("questnpc", "Creature", id, name)
		w.S.questId = 1
		w.advance(100)
		w.fire("QUEST_DETAIL")
	end
	offer(2001, "Fine Name")
	equal(nameOf(2001), "Fine Name", "an ordinary name")
	offer(2002, "Retrieving data...")
	equal(nameOf(2002), "", "a placeholder is no name")
	offer(2003, "Bad|Name")
	equal(nameOf(2003), "", "a name with the field separator is dropped")
	offer(2004, string.rep("x", 65))
	equal(nameOf(2004), "", "a long name is dropped")
	offer(2005, "Tab\tName")
	equal(nameOf(2005), "", "a name with a control character is dropped")
	offer(2006, SECRET)
	equal(nameOf(2006), "", "a hidden name is dropped")
	offer(2007, nil)
	equal(nameOf(2007), "", "no name")
	offer(2001, "Different Name")
	equal(nameOf(2001), "Fine Name", "the first name stands")
	equal(tonumber(w.fields(db.g["Creature:2001"])[7]) % 2, 1, "and a different one is flagged")
	offer(2001, nil)
	equal(nameOf(2001), "Fine Name", "a missing name keeps the old one")
	equal(db.err.n, 0, "no errors")

	local de = newWorld({locale = "deDE"})
	de.login()
	de.giver("questnpc", "Creature", 3001, "Wache")
	de.S.questId = 5
	de.fire("QUEST_DETAIL")
	local f = de.fields(de.db().g["Creature:3001"])
	equal(f[1], "", "no name from a German client")
	equal(f[5], "5", "the offer is still recorded")
	equal(f[4], "84 45.3 67.8 1", "and the place")
	de.S.logIndex[5] = 2
	de.S.log[1], de.S.log[2] = {isHeader = true, title = "Teldrassil"}, {title = "q"}
	de.fire("QUEST_ACCEPTED", 5)
	equal(de.fields(de.db().q[5])[7], "", "no heading from a German client")
end

-- 10. Who: union of masks over characters, unknown tokens.
do
	local w = newWorld()
	w.login()
	local db = w.db()
	w.giver("questnpc", "Creature", 4001, "Anyone")
	w.S.questId = 7
	w.fire("QUEST_DETAIL")
	w.S.faction, w.S.race, w.S.class = "Horde", "Orc", "WARRIOR"
	w.fire("QUEST_DETAIL")
	local q = w.fields(db.q[7])
	equal(q[4], "3", "both factions")
	equal(q[5], tostring(8 + 2), "both races")
	equal(q[6], tostring(1024 + 1), "both classes")
	w.S.race = "MadeUpRace"
	w.fire("QUEST_DETAIL")
	check((db.d["bit:unk"] or 0) >= 1, "an unknown race token is counted")
	equal(w.fields(db.q[7])[5], tostring(8 + 2), "and adds nothing")
	check(not w.calls["UnitName:player"], "the character's name is never read")
	check(not w.calls["UnitGUID:player"], "the character's GUID is never read")
end

-- 11. Caps and eviction.
do
	local w = newWorld()
	w.login()
	local db = w.db()
	for i = 1, 6000 do
		w.S.time = w.S.time + 100
		w.giver("npc", "Creature", i, "Giver " .. i)
		w.S.available = {{questID = i}, {questID = i + 100000}}
		w.S.map, w.S.pos = 84 + i % 50, {(i % 100) / 100, ((i * 7) % 100) / 100}
		w.fire("GOSSIP_SHOW")
	end
	check(count(db.g) <= 2500, "givers stay within the cap (" .. count(db.g) .. ")")
	check(count(db.g) > 2200, "and only the oldest tenth goes (" .. count(db.g) .. ")")
	check(count(db.q) <= 5000, "quests stay within the cap (" .. count(db.q) .. ")")
	check(db.ev > 0, "evictions are counted")
	check(db.g["Creature:6000"] ~= nil, "the newest giver is kept")
	check(db.g["Creature:1"] == nil, "the oldest giver is gone")
	for i = 1, 700 do
		w.S.time = w.S.time + 100
		w.S.pos = {(i % 100) / 100, 0.5}
		w.env.QuestObjectiveTracker:AddAutoQuestPopUp(500000 + i, "OFFER", 9000 + i)
	end
	check(count(db.s) <= 500 and count(db.s) > 400, "starts stay within the cap (" .. count(db.s) .. ")")
	-- A full table still updates a giver it already has.
	local known = next(db.g)
	local id = tonumber(known:match(":(%d+)"))
	w.giver("npc", "Creature", id, "Giver")
	w.S.available = {{questID = 7777777}}
	local before = count(db.g)
	w.fire("GOSSIP_SHOW")
	equal(count(db.g), before, "an existing giver updates without eviction")
	check(w.fields(db.g[known])[5]:find("7777777", 1, true) ~= nil, "and gets the new offer")
	equal(db.err.n, 0, "no errors at the caps")

	-- The size the game would write.
	local function serialize(v, out)
		if type(v) == "table" then
			out[#out + 1] = "{"
			for k, x in pairs(v) do
				out[#out + 1] = type(k) == "number" and ("[" .. k .. "]=") or ("[" .. string.format("%q", k) .. "]=")
				serialize(x, out)
				out[#out + 1] = ","
			end
			out[#out + 1] = "}"
		elseif type(v) == "string" then
			out[#out + 1] = string.format("%q", v)
		else
			out[#out + 1] = tostring(v)
		end
		return out
	end
	local text = table.concat(serialize(db, {}))
	check(#text < 600 * 1024, "the saved table at the caps is under 600 KB (" .. math.floor(#text / 1024) .. " KB)")
	check(loadstring("return " .. text) ~= nil, "and it loads back")
end

-- 12. What is saved holds nothing identifying, and survives being written and read back.
do
	local w = newWorld()
	w.login()
	local db = w.db()
	w.giver("questnpc", "Creature", 8001, "Somebody")
	w.S.questId = 11
	w.fire("QUEST_DETAIL")
	w.S.logIndex[11] = 2
	w.S.log[1], w.S.log[2] = {isHeader = true, title = "Zone"}, {title = "Quest"}
	w.fire("QUEST_ACCEPTED", 11)
	w.env.QuestObjectiveTracker:AddAutoQuestPopUp(12, "OFFER", 4444)
	local function serialize(v, out)
		if type(v) == "table" then
			out[#out + 1] = "{"
			for k, x in pairs(v) do
				out[#out + 1] = type(k) == "number" and ("[" .. k .. "]=") or ("[" .. string.format("%q", k) .. "]=")
				serialize(x, out)
				out[#out + 1] = ","
			end
			out[#out + 1] = "}"
		elseif type(v) == "string" then
			out[#out + 1] = string.format("%q", v)
		elseif type(v) == "number" then
			check(v == v and v ~= math.huge and v ~= -math.huge, "a saved number is finite")
			out[#out + 1] = string.format("%.17g", v)
		else
			out[#out + 1] = tostring(v)
		end
		return out
	end
	local text = table.concat(serialize(db, {}))
	for _, forbidden in ipairs({"Zzqtest", "Zzrealm", "Player-", "Creature-", "GameObject-", "-0000"}) do
		check(not text:find(forbidden, 1, true), "the saved table has no " .. forbidden)
	end
	check(not text:find("%c"), "the saved table has no control character")
	for key, record in pairs(db.g) do equal(#w.fields(record), 7, "giver " .. key .. " has seven fields") end
	for key, record in pairs(db.q) do equal(#w.fields(record), 7, "quest " .. key .. " has seven fields") end
	for key, record in pairs(db.s) do equal(#w.fields(record), 7, "start " .. key .. " has seven fields") end
	local restored = assert(loadstring("return " .. text))()
	local again = newWorld({saved = restored})
	again.login()
	local function dump(v)
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		local out = {}
		for _, k in ipairs(keys) do
			local x = v[k] or v[tonumber(k)]
			out[#out + 1] = k .. "=" .. (type(x) == "table" and dump(x) or tostring(x))
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	equal(dump(again.db().g), dump(db.g), "givers survive a save and a load")
	equal(dump(again.db().q), dump(db.q), "quests survive")
	equal(dump(again.db().s), dump(db.s), "starts survive")

	local source = readFile(ADDON_DIR .. "/qcRecorder.lua")
	source = source:gsub("%-%-%[%[.-%]%]%-%-", "")
	-- Lua 5.1 can't trap == or ~= on a hidden value, which the game does: so the order is read here.
	local guard = source:find("if ok and secret%(guid%) then")
	local comparison = source:find("guid ~= nil", 1, true)
	check(guard and comparison and guard < comparison, "a hidden GUID is asked about before it is compared with nil")
	for _, pattern in ipairs({"SendAddonMessage", "SendChatMessage", "C_ChatInfo", "C_Timer", "GetRealmName", "GetNormalizedRealmName",
			"GetServerTime", "UnitFullName", "UnitGUID%(\"player\"", "UnitName%(\"player\"", "[^%w_]time%(", "[^%w_]date%(",
			"BNGet", "GetGuildInfo", "GetUnitName"}) do
		check(not source:find(pattern), "qcRecorder.lua never uses " .. pattern)
	end
end

-- 13. A damaged or newer table, and handlers that fail.
do
	local damaged = newWorld({saved = {v = 1, g = "junk", q = {[5] = 5, abc = "x", [6] = "1|2|3|0|0|0|"}, s = {[1] = {}}, seq = "x", d = 3}})
	damaged.login()
	local db = damaged.db()
	equal(type(db.g), "table", "a damaged table is replaced")
	check(db.q[5] == nil and db.q.abc == nil, "records of the wrong shape are dropped")
	check(db.q[6] ~= nil, "a right-shaped record stays")
	equal(count(db.s), 0, "a start that isn't a string is dropped")
	equal(db.seq, 0, "the sequence number is repaired")
	damaged.giver("questnpc", "Creature", 1, "Someone")
	damaged.S.questId = 6
	damaged.fire("QUEST_DETAIL")
	equal(db.err.n, 0, "a record of the wrong field count is replaced without error")
	equal(#damaged.fields(db.q[6]), 7, "and is whole again")

	local newer = newWorld({saved = {v = 2, g = {}}})
	newer.login()
	check(not newer.frame.events.QUEST_DETAIL, "a newer schema is left alone")
	equal(newer.env.qcQuestRecorder.v, 2, "and untouched")

	local w = newWorld()
	w.login()
	local db2 = w.db()
	w.giver("questnpc", "Creature", 1, "Someone")
	w.S.questIdError = true
	for i = 1, 3 do w.fire("QUEST_DETAIL") end
	equal(db2.err.n, 3, "failures are counted")
	check(db2.err.last:find("GetQuestID failed", 1, true) ~= nil, "and the last message kept")
	local errorLines = 0
	for _, line in ipairs(w.printed) do if line:find("GetQuestID failed", 1, true) then errorLines = errorLines + 1 end end
	equal(errorLines, 1, "the player is told once")
	check(not w.frame.events.QUEST_DETAIL, "three failures stop the recorder for the session")
	equal(count(db2.g), 0, "nothing half-written")
	w.env.qcRecorderCommand("on")
	check(w.frame.events.QUEST_DETAIL, "/qc record on starts it again")

	local u = newWorld()
	u.login()
	u.S.guidError = true
	u.giver("questnpc", "Creature", 1, "Someone")
	u.S.questId = 1
	u.fire("QUEST_DETAIL")
	equal(u.db().err.n, 0, "a failing UnitGUID is read as no giver")
	check(u.db().q[1] ~= nil, "and the quest is still noted")
end

-- 14. The report, in every language.
do
	for _, locale in ipairs(LOCALES) do
		local w = newWorld({locale = locale})
		w.login()
		w.giver("npc", "Creature", 1, "Someone")
		w.S.available = {{questID = 1}}
		w.fire("GOSSIP_SHOW")
		w.S.guid.npc = SECRET
		w.fire("GOSSIP_SHOW")
		w.db().ev = 3
		w.db().err = {n = 2, last = "oops"}
		w.printed = {}
		w.env.qcRecorderReport()
		local text = lines(w)
		equal(#w.printed, 6, locale .. ": the report has six lines")
		check(not text:find("%%[ds]"), locale .. ": no placeholder is left in the report")
		check(text:find("QuestCompletist.lua", 1, true) ~= nil, locale .. ": the report names the file")
		check(text:find("SavedVariables", 1, true) ~= nil, locale .. ": and its folder")
		w.printed = {}
		w.env.qcRecorderCommand("")
		equal(#w.printed, 1, locale .. ": the status is one line")
		check(w.printed[1]:find("Enabled", 1, true) ~= nil, locale .. ": the status says it is on")
		w.env.qcRecorderCommand("off")
		check(w.printed[#w.printed]:find("Disabled", 1, true) ~= nil, locale .. ": and then off")
	end
end

-- 15. Hidden values, in every place the recorder reads one.
do
	local function fresh()
		local w = newWorld()
		w.login()
		return w, w.db()
	end
	local function noErrors(w, what)
		equal(w.db().err.n, 0, what .. ": no handler failed")
	end

	local w, db = fresh()
	w.S.map = SECRET_NUMBER
	w.giver("questnpc", "Creature", 1, "Someone")
	w.S.questId = 1
	w.fire("QUEST_DETAIL")
	noErrors(w, "a hidden map")
	equal(w.fields(db.g["Creature:1"])[4], "", "a hidden map leaves no spot")

	w, db = fresh()
	w.giver("questnpc", "Creature", 1, "Someone")
	w.S.questId = 1
	w.env.C_Map.GetPlayerMapPosition = function() return SECRET_TABLE end
	w.fire("QUEST_DETAIL")
	noErrors(w, "a hidden position")
	equal(w.fields(db.g["Creature:1"])[4], "84 -1 -1 1", "a hidden position gives -1 -1")

	w, db = fresh()
	w.giver("questnpc", "Creature", 1, "Someone")
	w.S.questId = 1
	w.S.pos = {0.5, SECRET_NUMBER}
	w.fire("QUEST_DETAIL")
	noErrors(w, "a hidden y")
	equal(w.fields(db.g["Creature:1"])[4], "84 -1 -1 1", "a hidden y gives -1 -1")

	w, db = fresh()
	w.giver("questnpc", "Creature", 1, SECRET_STRING)
	w.S.questId = 1
	w.fire("QUEST_DETAIL")
	noErrors(w, "a hidden name")
	equal((db.d["name:hid"] or 0), 1, "a hidden name is counted as hidden")

	w, db = fresh()
	w.S.questId = SECRET_NUMBER
	w.giver("questnpc", "Creature", 1, "Someone")
	w.fire("QUEST_DETAIL")
	w.fire("QUEST_COMPLETE")
	noErrors(w, "a hidden quest ID")
	equal(count(db.g) + count(db.q), 0, "a hidden quest ID records nothing")

	w, db = fresh()
	w.S.questId = 5
	w.giver("questnpc", "Creature", 1, "Someone")
	w.fire("QUEST_DETAIL", SECRET_NUMBER)
	noErrors(w, "a hidden item")
	equal(count(db.s), 0, "a giver's quest with a hidden item makes no start")
	w.S.guid.questnpc = nil
	w.S.questId = 6
	w.fire("QUEST_DETAIL", SECRET_NUMBER)
	noErrors(w, "a hidden item with no giver")
	equal(count(db.s), 0, "a hidden item makes no start")
	w.env.QuestObjectiveTracker:AddAutoQuestPopUp(SECRET_NUMBER, "OFFER", 5)
	w.env.QuestObjectiveTracker:AddAutoQuestPopUp(7, "OFFER", SECRET_NUMBER)
	noErrors(w, "hidden popup arguments")
	equal(w.fields(db.s[7])[1], "2", "a popup with a hidden item is not taken for an item start")

	w, db = fresh()
	w.S.guid.questnpc = SECRET_STRING
	w.S.questId = 8
	w.fire("QUEST_DETAIL", 5555)
	noErrors(w, "a hidden giver with an item")
	equal(count(db.s), 0, "a hidden giver is not a giverless start")
	check(db.q[8] ~= nil, "but the quest's facts are kept")
	w.S.guid.questnpc = "Player-3770-0000ABCD12"
	w.S.questId = 9
	w.fire("QUEST_DETAIL", 5555)
	equal(count(db.s), 0, "a player is not a giverless start")

	w, db = fresh()
	w.giver("npc", "Creature", 1, "Someone")
	w.S.available = SECRET_TABLE
	w.S.active = {{questID = 3}}
	w.fire("GOSSIP_SHOW")
	noErrors(w, "a hidden offers list")
	equal(w.fields(db.g["Creature:1"])[6], "3", "the other list is still read")
	w.S.available, w.S.active = {{questID = 4}}, SECRET_TABLE
	w.fire("GOSSIP_SHOW")
	noErrors(w, "a hidden active list")
	w.S.available = {SECRET_TABLE, {questID = SECRET_NUMBER}, {questID = 5, frequency = SECRET_NUMBER, repeatable = SECRET_BOOLEAN}}
	w.S.active = {}
	w.fire("GOSSIP_SHOW")
	noErrors(w, "hidden entries")
	equal(w.fields(db.q[5])[3], "32", "a hidden frequency and repeatable flag are not read")
	equal(w.fields(db.g["Creature:1"])[5], "4,5", "only the readable entries are offers")

	w, db = fresh()
	w.giver("npc", "Creature", 1, "Someone")
	w.S.available = {{questID = 4}}
	w.S.near = SECRET_BOOLEAN
	w.S.inInstance = SECRET_BOOLEAN
	w.S.combat = SECRET_BOOLEAN
	w.fire("GOSSIP_SHOW")
	noErrors(w, "hidden booleans")
	check(not db.d["near:true"] and not db.d["near:false"], "a hidden distance is not counted")
	check(db.d["rd:GOSSIP_SHOW:npc:ok:w"] == 1, "hidden instance and combat flags read as the open world")

	w, db = fresh()
	w.giver("npc", "Creature", 1, "Someone")
	w.S.available = {{questID = 4}}
	w.S.combat = true
	w.fire("GOSSIP_SHOW")
	w.S.combat, w.S.inInstance = false, true
	w.fire("GOSSIP_SHOW")
	check(db.d["rd:GOSSIP_SHOW:npc:ok:c"] == 1 and db.d["rd:GOSSIP_SHOW:npc:ok:i"] == 1, "combat and an instance are told apart")

	w, db = fresh()
	w.S.logIndex[10], w.S.log[1] = 1, SECRET_TABLE
	w.fire("QUEST_ACCEPTED", 10)
	noErrors(w, "a hidden log entry")
	check(db.q[10] ~= nil, "a hidden log entry still leaves the accept")
	w.S.logIndex[11], w.S.log[2] = 2, {isHidden = SECRET_BOOLEAN, isInternalOnly = SECRET_BOOLEAN, isTask = SECRET_BOOLEAN, title = "q"}
	w.S.log[1] = SECRET_TABLE
	w.fire("QUEST_ACCEPTED", 11)
	noErrors(w, "hidden log flags")
	check(db.q[11] ~= nil, "hidden flags are not a skip")
	w.S.worldQuests[12] = SECRET_BOOLEAN
	w.fire("QUEST_ACCEPTED", 12)
	check(db.q[12] ~= nil, "a hidden world quest flag is not a skip")
	w.S.logIndex[13] = 4
	w.S.log[3] = {isHeader = true, title = SECRET_STRING}
	w.S.log[4] = {title = "q"}
	w.S.log[1], w.S.log[2] = nil, nil
	w.fire("QUEST_ACCEPTED", 13)
	noErrors(w, "a hidden heading")
	equal(w.fields(db.q[13])[7], "", "a hidden heading is not kept")
	w.S.logIndex[14], w.S.log[5] = 5, {title = "q"}
	w.S.log[4] = {isHeader = SECRET_BOOLEAN, title = "Not a header"}
	w.S.log[3] = nil
	w.fire("QUEST_ACCEPTED", 14)
	equal(w.fields(db.q[14])[7], "", "a hidden header flag is not a header")
	w.S.adventure = SECRET_BOOLEAN
	w.S.questId = 15
	w.giver("questnpc", "Creature", 1, "Someone")
	w.fire("QUEST_DETAIL")
	check(db.q[15] ~= nil, "a hidden adventure map flag is not a skip")
end

-- 16. Rules the other sections leave unproven.
do
	-- The lists are capped at 60 and the giver says so.
	local w = newWorld()
	w.login()
	local db = w.db()
	w.giver("npc", "Creature", 1, "Busy")
	w.S.available = {}
	for i = 1, 70 do w.S.available[i] = {questID = i} end
	w.S.active = {}
	for i = 101, 170 do w.S.active[#w.S.active + 1] = {questID = i} end
	w.fire("GOSSIP_SHOW")
	local f = w.fields(db.g["Creature:1"])
	local _, offers = f[5]:gsub(",", ",")
	local _, turns = f[6]:gsub(",", ",")
	equal(offers + 1, 60, "60 offers kept")
	equal(turns + 1, 60, "60 turn-ins kept")
	equal(tonumber(f[7]), 6, "both lists marked full")
	equal(count(db.q), 70, "every offered quest still has its facts")

	-- Spots: a different map, a different y, the same place.
	w = newWorld()
	w.login()
	db = w.db()
	w.giver("questnpc", "Creature", 2, "Mover")
	w.S.questId = 1
	w.S.pos = {0.5, 0.5}
	w.fire("QUEST_DETAIL")
	w.S.map = 85
	w.fire("QUEST_DETAIL")
	w.S.map, w.S.pos = 84, {0.5, 0.52}
	w.fire("QUEST_DETAIL")
	w.S.pos = {0.52, 0.5}
	w.fire("QUEST_DETAIL")
	local spots = 0
	for _ in w.fields(db.g["Creature:2"])[4]:gmatch("[^;]+") do spots = spots + 1 end
	equal(spots, 4, "another map, a second y and a second x are all separate spots")

	-- A visit counts when the giver changes, though the time hasn't.
	w = newWorld()
	w.login()
	db = w.db()
	w.S.questId = 1
	w.giver("questnpc", "Creature", 10, "A")
	w.fire("QUEST_DETAIL")
	w.giver("questnpc", "Creature", 11, "B")
	w.fire("QUEST_DETAIL")
	w.giver("questnpc", "Creature", 10, "A")
	w.fire("QUEST_DETAIL")
	equal(w.fields(db.g["Creature:10"])[4], "84 45.3 67.8 2", "going back to a giver is a new visit")

	-- Frequency learnt once is kept when a later window doesn't say.
	w = newWorld()
	w.login()
	db = w.db()
	w.giver("npc", "Creature", 12, "Daily Giver")
	w.S.available = {{questID = 20, frequency = 2, repeatable = true}}
	w.fire("GOSSIP_SHOW")
	w.S.available = {{questID = 20}}
	w.fire("GOSSIP_SHOW")
	w.S.questId = 20
	w.giver("questnpc", "Creature", 12, "Daily Giver")
	w.fire("QUEST_DETAIL")
	equal(w.fields(db.q[20])[3], tostring(1 + 4 + 8 + 32 + 64), "a later offer without a frequency keeps what was learnt")

	-- A hidden quest, by its internal-only flag.
	w.S.logIndex[21], w.S.log[1] = 1, {isInternalOnly = true}
	w.fire("QUEST_ACCEPTED", 21)
	check(db.q[21] == nil, "an internal-only quest is skipped")

	-- Which token wins, event by event.
	local function tokens(event, expected)
		local t = newWorld()
		t.login()
		t.S.guid.npc, t.S.guid.questnpc = guid("Creature", 1), guid("Creature", 2)
		t.S.available = {{questID = 3}}
		t.S.greetingAvailable = {{id = 3}}
		t.S.questId = 3
		t.fire(event)
		check(t.db().g["Creature:" .. expected] ~= nil, event .. " reads the " .. (expected == 1 and "npc" or "questnpc") .. " token first")
	end
	tokens("GOSSIP_SHOW", 1)
	tokens("QUEST_GREETING", 2)
	tokens("QUEST_DETAIL", 2)
	tokens("QUEST_PROGRESS", 2)
	tokens("QUEST_COMPLETE", 2)

	-- The oldest tenth goes when a table is full, no more.
	w = newWorld()
	w.login()
	db = w.db()
	for i = 1, 2501 do
		w.S.time = w.S.time + 100
		w.giver("npc", "Creature", i, "G")
		w.S.available = {{questID = 1}}
		w.fire("GOSSIP_SHOW")
	end
	equal(count(db.g), 2251, "2,501 givers leave 2,250 and the new one")
	equal(db.ev, 250, "250 evicted")
	check(db.g["Creature:250"] == nil and db.g["Creature:251"] ~= nil, "the 250 oldest went")

	-- Builds: no more than eight, and the current one stays.
	w = newWorld({saved = {v = 1, bv = {[1] = "a", [2] = "b", [3] = "c", [4] = "d", [5] = "e", [6] = "f", [7] = "g", [8] = "h", [90000] = "z"}},
		build = {"12.1.0", "50", "d", 1}})
	w.login()
	db = w.db()
	equal(count(db.bv), 8, "eight builds kept")
	equal(db.bv[50], "12.1.0", "the current build among them")
	equal(db.bv[90000], "z", "the highest stays")

	-- A table with junk in the counters and builds still loads.
	w = newWorld({saved = {v = 1, d = {x = "y", [5] = 1, ok = 2}, bv = {a = "b", [1] = 2}, err = {n = 1, last = 5}}})
	w.login()
	db = w.db()
	check(db.d.x == nil and db.d[5] == nil and db.d.ok == 2, "junk counters are dropped")
	check(db.bv.a == nil and db.bv[1] == nil, "junk builds are dropped")
	equal(db.err.last, nil, "a junk last error is dropped")
	w.giver("questnpc", "Creature", 1, "Someone")
	w.S.questId = 1
	w.fire("QUEST_DETAIL")
	equal(db.err.n, 1, "and the recorder still works")

	-- The checkbox and the command start a stopped recorder again.
	w = newWorld()
	w.login()
	w.S.questIdError = true
	w.giver("questnpc", "Creature", 1, "Someone")
	for i = 1, 3 do w.fire("QUEST_DETAIL") end
	check(not w.frame.events.QUEST_DETAIL, "stopped after three failures")
	w.S.questIdError = nil
	w.env.qcRecorderSetEnabled(false)
	w.env.qcRecorderSetEnabled(true)
	check(w.frame.events.QUEST_DETAIL, "ticking the box again starts it")
end

-- 17. The /qc command in qcCore.lua, run as it is written there.
do
	local body = coreText:match('(SlashCmdList%["QUESTCOMPLETIST"%] = function.-\r?\nend)\r?\n')
	check(body ~= nil, "the slash handler is found in qcCore.lua")
	local w = newWorld()
	w.login()
	local shown, holidays, minimap = 0, 0, 0
	w.env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	w.env.SlashCmdList = {}
	w.env.ShowUIPanel = function() shown = shown + 1 end
	w.env.qcQuestCompletistUI = {}
	w.env.qcPrintHolidays = function() holidays = holidays + 1 end
	w.env.qcShowMinimapButton = function() minimap = minimap + 1 end
	local chunk = assert(loadstring(body, "@slash"))
	setfenv(chunk, w.env)
	chunk()
	local run = w.env.SlashCmdList["QUESTCOMPLETIST"]
	w.printed = {}
	run("report")
	equal(#w.printed, 3, "/qc report prints the status, the counts and the file")
	w.printed = {}
	run("  REPORT  ")
	equal(#w.printed, 3, "and ignores case and spaces")
	run("record off")
	equal(w.env.qcSettings.QC_RECORD_GIVERS, 0, "/qc record off")
	run("Record On")
	equal(w.env.qcSettings.QC_RECORD_GIVERS, 1, "/qc record on")
	run("record clear")
	check(w.printed[#w.printed]:find("cleared", 1, true) ~= nil, "/qc record clear says so")
	equal(shown, 0, "none of them opens the window")
	run("")
	run("holidays")
	run("minimap")
	equal(shown, 1, "/qc alone opens the window")
	equal(holidays, 1, "/qc holidays is still there")
	equal(minimap, 1, "/qc minimap is still there")
	w.env.qcRecorderReport, w.env.qcRecorderCommand = nil, nil
	run("report")
	run("record on")
	equal(shown, 1, "a missing recorder is no error and opens nothing")
end

print(string.format("%d checks passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
