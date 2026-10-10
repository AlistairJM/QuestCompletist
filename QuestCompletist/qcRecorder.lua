--[[ A note of the quest givers the player meets, kept on this computer, for improving the map's data.
Nothing here is sent anywhere. It stores no character, realm or account name, no time, and no
GUID: a giver is its kind and ID, a quest is its ID. Both games run it. docs/plans/quest-giver-recorder.md
has the reasoning; tools\Test-Recorder.lua runs it offline.

qcQuestRecorder (account-wide) holds one packed string per record, because a table per record cost three
times the memory at the caps:
  g[kind:id] = name|build|seq|spots|offers|turnins|flags       a giver
  q[questId] = build|seq|flags|faction|race|class|heading      a quest
  s[questId] = kind|item|map|x|y|build|seq                     a quest started away from any giver
Spots are "map x y visits" joined by ";", where x and y are the player's map position in percent, not the
giver's. Offers and turn-ins are quest IDs joined by ",". A name or heading is kept only from an English
client, and only if the game gave it whole: a wrong name is worse than none. ]]--
local QC = select(2, ...)
local qcL = qcLocalize
local CHAT_TITLE = QC.CHAT_TITLE

local SCHEMA = 1
local MAX_GIVERS, MAX_QUESTS, MAX_STARTS = 5000, 10000, 4000
local MAX_SPOTS, MAX_LIST, MAX_BUILDS, MAX_QUEST_ID = 4, 60, 8, 9999999
local NAME_MAX, SPOT_MERGE, VISIT_GAP, EVICT_FRACTION = 64, 1.0, 30, 0.1
local MAX_FAILURES, MAX_HEADING_WALK = 3, 200

local EVENTS = {"GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED"}
local KINDS = {Creature = true, GameObject = true, Vehicle = true}
local CAPS = {g = MAX_GIVERS, q = MAX_QUESTS, s = MAX_STARTS}
-- Where the sequence number sits in each kind of record; eviction goes by it.
local SEQ_PATTERN = {
	g = "^[^|]*|[^|]*|(%d+)|",
	q = "^[^|]*|(%d+)|",
	s = "^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(%d+)$",
}

local ENGLISH = GetLocale() == "enUS"
local issecretvalue = issecretvalue
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local db, build, apply, setup, login
local counts = {g = 0, q = 0, s = 0}
local failures, stopped, errorShown = 0, false, false
local lastKey, lastTime
local frame = CreateFrame("Frame")
local handlers = {}

local function secret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function enabled()
	return db ~= nil and not stopped and (qcSettings == nil or qcSettings.QC_RECORD_GIVERS ~= 0)
end

local function note(key)
	local d = db.d
	d[key] = min((d[key] or 0) + 1, 1e9)
end

local function split(text, sep)
	local parts, n, from = {}, 0, 1
	while true do
		local at = text:find(sep, from, true)
		n = n + 1
		if not at then
			parts[n] = text:sub(from)
			return parts
		end
		parts[n] = text:sub(from, at - 1)
		from = at + 1
	end
end

local function nextSeq()
	db.seq = db.seq + 1
	return db.seq
end

local function hasBit(flags, value)
	return flags % (2 * value) >= value
end

local function setBit(flags, value)
	return hasBit(flags, value) and flags or flags + value
end

local function wholeNumber(v, low, high)
	return not secret(v) and type(v) == "number" and v == floor(v) and v >= low and v <= high
end

-- A true the game gave plainly: a hidden value is never a yes.
local function isSet(v)
	return not secret(v) and v == true
end

local function validQuestId(v)
	return wholeNumber(v, 1, MAX_QUEST_ID)
end

-- Text the game gave whole and in English; anything else is not worth keeping. The "|" splits fields.
local function cleanText(text)
	if not ENGLISH or secret(text) or type(text) ~= "string" or text == "" or #text > NAME_MAX
		or text:find("[|%c]") or text == RETRIEVING_DATA or text == UNKNOWN or text == UNKNOWNOBJECT then
		return nil
	end
	return text
end

local function context()
	local ok, inInstance = pcall(IsInInstance)
	if ok and isSet(inInstance) then return "i" end
	return InCombatLockdown and isSet(InCombatLockdown()) and "c" or "w"
end

local function round(v)
	return floor(v * 1000 + 0.5) / 10
end

local function coordinate(v)
	return v < 0 and "-1" or string.format("%.1f", v)
end

-- The player's place on the map the game would show. Inside an instance there is often no position.
local function readWhere()
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok or not wholeNumber(map, 1, 1e6) then
		note("pos:nomap")
		return nil
	end
	local x, y = -1, -1
	local gotPosition, position = pcall(C_Map.GetPlayerMapPosition, map, "player")
	if gotPosition and type(position) == "table" and not secret(position) then
		local gotXY, px, py = pcall(position.GetXY, position)
		if gotXY and not secret(px) and not secret(py) and type(px) == "number" and type(py) == "number"
			and px >= 0 and px <= 1 and py >= 0 and py <= 1 then
			x, y = round(px), round(py)
		end
	end
	note(x < 0 and "pos:nil" or "pos:ok")
	return map, x, y
end

-- Which tokens the game answers for, and in what state, is learnt in play and counted in d.
local GUID_PATTERN = "^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)%-"

local function readGiver(event, tokens)
	local state, key, token = "none"
	for _, name in ipairs(tokens) do
		local ok, guid = pcall(UnitGUID, name)
		local result = "none"
		if ok and secret(guid) then
			result = "hid"
		elseif ok and guid ~= nil then
			local kind, id
			if type(guid) == "string" then kind, id = guid:match(GUID_PATTERN) end
			id = tonumber(id)
			if KINDS[kind] and id and id > 0 and id <= 1e9 then
				result, key = "ok", kind .. ":" .. id
			else
				result = "oth"
			end
		end
		note("rd:" .. event .. ":" .. name .. ":" .. result .. ":" .. context())
		if result ~= "none" then
			state, token = result, name
			break
		end
	end
	return state, key, token
end

local function readName(token)
	if not ENGLISH then
		note("name:loc")
		return ""
	end
	local ok, name = pcall(UnitName, token)
	if ok and secret(name) then
		note("name:hid")
		return ""
	end
	name = ok and cleanText(name)
	note(name and "name:ok" or "name:bad")
	return name or ""
end

-- Whoever played the quest: the same bit values the quest data uses, one number each.
local function readWho()
	local faction = qcFactionBits[string.upper(UnitFactionGroup("player") or "")]
	local _, race = UnitRace("player")
	local _, class = UnitClass("player")
	race = race and qcRaceBits[string.upper(race)]
	class = class and qcClassBits[class]
	if not (faction and race and class) then note("bit:unk") end
	return faction or 0, race or 0, class or 0
end

-- Room for one more record: when a table is full, its oldest tenth goes.
local function makeRoom(which)
	if counts[which] < CAPS[which] then return end
	local records, pattern, seqs = db[which], SEQ_PATTERN[which], {}
	for _, record in pairs(records) do
		seqs[#seqs + 1] = tonumber(record:match(pattern)) or 0
	end
	table.sort(seqs)
	local cut = seqs[max(1, floor(#seqs * EVICT_FRACTION))]
	local removed = 0
	for key, record in pairs(records) do
		if (tonumber(record:match(pattern)) or 0) <= cut then
			records[key] = nil
			removed = removed + 1
		end
	end
	counts[which] = counts[which] - removed
	db.ev = db.ev + removed
end

local function addIds(list, ids)
	local padded, size, full = "," .. list .. ",", list == "" and 0 or select(2, list:gsub(",", ",")) + 1, false
	for _, id in ipairs(ids) do
		if not padded:find("," .. id .. ",", 1, true) then
			if size >= MAX_LIST then
				full = true
			else
				list = list == "" and tostring(id) or list .. "," .. id
				padded = padded .. id .. ","
				size = size + 1
			end
		end
	end
	return list, full
end

local function addSpot(spots, map, x, y, newVisit)
	local list, found = {}
	for m, sx, sy, n in spots:gmatch("(%d+) (%-?[%d.]+) (%-?[%d.]+) (%d+)") do
		local spot = {tonumber(m), tonumber(sx), tonumber(sy), tonumber(n)}
		list[#list + 1] = spot
		if spot[1] == map and ((spot[2] < 0 and x < 0)
			or (spot[2] >= 0 and x >= 0 and abs(spot[2] - x) <= SPOT_MERGE and abs(spot[3] - y) <= SPOT_MERGE)) then
			found = spot
		end
	end
	if found then
		if newVisit then found[4] = min(found[4] + 1, 999) end
	elseif #list < MAX_SPOTS then
		list[#list + 1] = {map, x, y, 1}
	end
	for i, spot in ipairs(list) do
		list[i] = string.format("%d %s %s %d", spot[1], coordinate(spot[2]), coordinate(spot[3]), spot[4])
	end
	return table.concat(list, ";")
end

local function touchGiver(key, name, where, offered, taken)
	local record = db.g[key]
	local f = record and split(record, "|")
	if not f or #f ~= 7 then
		f = {"", "", "", "", "", "", "0"}
		if not record then
			makeRoom("g")
			counts.g = counts.g + 1
		end
	end
	local flags = tonumber(f[7]) or 0
	if name ~= "" then
		if f[1] == "" then
			f[1] = name
		elseif f[1] ~= name then
			flags = setBit(flags, 1)
		end
	end
	f[2], f[3] = build, nextSeq()
	if where then
		local now = GetTime()
		local newVisit = key ~= lastKey or not lastTime or now - lastTime >= VISIT_GAP
		lastKey, lastTime = key, now
		f[4] = addSpot(f[4], where.map, where.x, where.y, newVisit)
	end
	local full
	f[5], full = addIds(f[5], offered)
	if full then flags = setBit(flags, 2) end
	f[6], full = addIds(f[6], taken)
	if full then flags = setBit(flags, 4) end
	f[7] = tostring(flags)
	db.g[key] = table.concat(f, "|")
end

-- What the game says about a quest, whoever offered it: how it recurs, who it was offered to, where
-- the log files it. A value the game didn't give leaves what was there.
local function noteQuest(questId, frequency, repeatable, accepted, heading)
	local record = db.q[questId]
	local f = record and split(record, "|")
	if not f or #f ~= 7 then
		f = {"", "", "0", "0", "0", "0", ""}
		if not record then
			makeRoom("q")
			counts.q = counts.q + 1
		end
	end
	local flags = tonumber(f[3]) or 0
	local freqKnown, freq = hasBit(flags, 1), floor(flags / 2) % 4
	local isRepeatable, wasAccepted, listed, repeatableKnown = hasBit(flags, 8), hasBit(flags, 16), hasBit(flags, 32), hasBit(flags, 64)
	if wholeNumber(frequency, 0, 3) then
		freqKnown, freq = true, frequency
	end
	if not secret(repeatable) and type(repeatable) == "boolean" then
		repeatableKnown, isRepeatable = true, repeatable
	end
	if accepted then wasAccepted = true else listed = true end
	f[1], f[2] = build, nextSeq()
	f[3] = tostring((freqKnown and 1 or 0) + freq * 2 + (isRepeatable and 8 or 0) + (wasAccepted and 16 or 0) + (listed and 32 or 0)
		+ (repeatableKnown and 64 or 0))
	local faction, race, class = readWho()
	f[4], f[5], f[6] = tostring(bit.bor(tonumber(f[4]) or 0, faction)), tostring(bit.bor(tonumber(f[5]) or 0, race)),
		tostring(bit.bor(tonumber(f[6]) or 0, class))
	if heading then f[7] = heading end
	db.q[questId] = table.concat(f, "|")
end

-- A quest begun by an item or a trigger has no giver; the first place it was seen stands, because the
-- window the player clicks later opens wherever they are.
local function addStart(questId, kind, item)
	if db.s[questId] then return end
	makeRoom("s")
	local map, x, y = readWhere()
	counts.s = counts.s + 1
	db.s[questId] = table.concat({kind, item, map or 0, coordinate(x or -1), coordinate(y or -1), build, nextSeq()}, "|")
end

-- Notes the giver the window belongs to and what it offers and takes in. Returns what the game let it
-- read of the giver: ok, hid (the game hid who it is), oth (not a creature or object) or none.
local function visit(event, tokens, offered, taken)
	local state, key, token = readGiver(event, tokens)
	local ids = {}
	for i, o in ipairs(offered) do
		noteQuest(o.id, o.frequency, o.repeatable)
		ids[i] = o.id
	end
	if state == "ok" then
		local name = readName(token)
		local map, x, y = readWhere()
		if CheckInteractDistance then
			local ok, near = pcall(CheckInteractDistance, token, 3)
			if ok and not secret(near) then note(near and "near:true" or "near:false") end
		end
		touchGiver(key, name, map and {map = map, x = x, y = y}, ids, taken)
	end
	return state
end

local function questEntry(info)
	if type(info) == "table" and not secret(info) and validQuestId(info.questID) then
		return {id = info.questID, frequency = info.frequency, repeatable = info.repeatable}
	end
end

function handlers.GOSSIP_SHOW()
	local offered, taken = {}, {}
	local gotOffered, available = pcall(C_GossipInfo.GetAvailableQuests)
	local gotTaken, active = pcall(C_GossipInfo.GetActiveQuests)
	if gotOffered and type(available) == "table" and not secret(available) then
		for _, info in ipairs(available) do offered[#offered + 1] = questEntry(info) end
	end
	if gotTaken and type(active) == "table" and not secret(active) then
		for _, info in ipairs(active) do
			local entry = questEntry(info)
			if entry then taken[#taken + 1] = entry.id end
		end
	end
	if #offered == 0 and #taken == 0 then return end
	visit("GOSSIP_SHOW", {"npc", "questnpc"}, offered, taken)
end

function handlers.QUEST_GREETING()
	local offered, taken = {}, {}
	if type(GetAvailableQuestInfo) == "function" then
		for i = 1, min(GetNumAvailableQuests() or 0, 50) do
			local _, frequency, repeatable, _, questId = GetAvailableQuestInfo(i)
			if validQuestId(questId) then offered[#offered + 1] = {id = questId, frequency = frequency, repeatable = repeatable} end
		end
	else
		note("api:greeting")
	end
	if type(GetActiveQuestID) == "function" then
		for i = 1, min(GetNumActiveQuests() or 0, 50) do
			local questId = GetActiveQuestID(i)
			if validQuestId(questId) then taken[#taken + 1] = questId end
		end
	end
	if #offered == 0 and #taken == 0 then return end
	visit("QUEST_GREETING", {"questnpc", "npc"}, offered, taken)
end

function handlers.QUEST_DETAIL(itemId)
	local questId = GetQuestID()
	if not validQuestId(questId) then
		note("skip:noid")
		return
	end
	if QuestIsFromAdventureMap and isSet(QuestIsFromAdventureMap()) then
		note("skip:adv")
		return
	end
	local state = visit("QUEST_DETAIL", {"questnpc", "npc"}, {{id = questId}}, {})
	if state == "none" then
		if wholeNumber(itemId, 1, 1e9) then
			addStart(questId, 1, itemId)
		elseif QuestGetAutoAccept and QuestIsFromAreaTrigger and isSet(QuestGetAutoAccept()) and isSet(QuestIsFromAreaTrigger()) then
			addStart(questId, 2, 0)
		end
	end
end

local function handIn(event)
	local questId = GetQuestID()
	if validQuestId(questId) then
		visit(event, {"questnpc", "npc"}, {}, {questId})
	end
end

function handlers.QUEST_PROGRESS()
	handIn("QUEST_PROGRESS")
end

function handlers.QUEST_COMPLETE()
	handIn("QUEST_COMPLETE")
end

function handlers.QUEST_ACCEPTED(questId)
	if not validQuestId(questId) then return end
	local gotIndex, index = pcall(C_QuestLog.GetLogIndexForQuestID, questId)
	local info = gotIndex and wholeNumber(index, 1, 1e6) and C_QuestLog.GetInfo(index)
	if secret(info) then info = nil end
	if (C_QuestLog.IsWorldQuest and isSet(C_QuestLog.IsWorldQuest(questId))) or (info and isSet(info.isTask)) then
		note("skip:task")
		return
	end
	if info and (isSet(info.isHidden) or isSet(info.isInternalOnly)) then
		note("skip:hidden")
		return
	end
	local heading
	if not ENGLISH then
		note("head:loc")
	elseif info then
		for i = index, max(1, index - MAX_HEADING_WALK), -1 do
			local row = C_QuestLog.GetInfo(i)
			if row and not secret(row) and isSet(row.isHeader) then
				heading = cleanText(row.title)
				break
			end
		end
	end
	if ENGLISH then note(heading and "head:ok" or "head:none") end
	noteQuest(questId, info and info.frequency, nil, true, heading)
end

-- Records are rebuilt whole before they are stored, so a failure leaves nothing half-written.
-- Three failures in a session stop the recorder for it.
local function fail(message)
	if not db then return end
	message = tostring(message):gsub("%c", " "):sub(1, 200)
	db.err.n, db.err.last = min(db.err.n + 1, 1e9), message
	failures = failures + 1
	if not errorShown then
		errorShown = true
		print(CHAT_TITLE .. string.format(qcL.RECORDERERRORS, db.err.n, message))
	end
	if failures >= MAX_FAILURES then
		stopped = true
		apply()
	end
end

local function onEvent(_, event, ...)
	if event == "ADDON_LOADED" then
		if (...) == "QuestCompletist" then setup() end
	elseif event == "PLAYER_LOGIN" then
		login()
	elseif enabled() then
		local ok, err = pcall(handlers[event], ...)
		if ok then note("ev:" .. event) else fail(err) end
	end
end

function apply()
	if not db then return end
	local on = enabled()
	for _, event in ipairs(EVENTS) do
		if on then pcall(frame.RegisterEvent, frame, event) else pcall(frame.UnregisterEvent, frame, event) end
	end
end

-- The saved table comes from a file a player may have edited or an older version wrote: keep only
-- what has the right shape.
function setup()
	local ok = pcall(function()
		if type(qcQuestRecorder) ~= "table" then qcQuestRecorder = {} end
		db = qcQuestRecorder
		if type(db.v) ~= "number" then db.v = SCHEMA end
		if db.v > SCHEMA then
			db = nil
			return
		end
		for _, name in ipairs({"g", "q", "s", "d", "bv", "err"}) do
			if type(db[name]) ~= "table" then db[name] = {} end
		end
		for _, name in ipairs({"seq", "ev"}) do
			if type(db[name]) ~= "number" then db[name] = 0 end
		end
		if type(db.err.n) ~= "number" then db.err.n = 0 end
		if type(db.err.last) ~= "string" then db.err.last = nil end
		for key, n in pairs(db.d) do
			if type(key) ~= "string" or type(n) ~= "number" then db.d[key] = nil end
		end
		for key, value in pairs(db.bv) do
			if type(key) ~= "number" or type(value) ~= "string" then db.bv[key] = nil end
		end
		for _, which in ipairs({"g", "q", "s"}) do
			counts[which] = 0
			for key, record in pairs(db[which]) do
				if type(record) == "string" and type(key) == (which == "g" and "string" or "number") then
					counts[which] = counts[which] + 1
				else
					db[which][key] = nil
				end
			end
		end
		local version
		version, build = GetBuildInfo()
		build = tonumber(build) or 0
		db.bv[build] = version
		local builds = {}
		for buildNumber in pairs(db.bv) do builds[#builds + 1] = buildNumber end
		table.sort(builds)
		local excess = #builds - MAX_BUILDS
		for _, buildNumber in ipairs(builds) do
			if excess <= 0 then break end
			if buildNumber ~= build then
				db.bv[buildNumber] = nil
				excess = excess - 1
			end
		end
	end)
	if not ok then
		db = nil
		return
	end
	apply()
end

function login()
	if QuestObjectiveTracker and type(QuestObjectiveTracker.AddAutoQuestPopUp) == "function" then
		hooksecurefunc(QuestObjectiveTracker, "AddAutoQuestPopUp", function(_, questId, popUpType, itemId)
			if db and enabled() and popUpType == "OFFER" and validQuestId(questId) then
				local fromItem = wholeNumber(itemId, 1, 1e9)
				local ok, err = pcall(addStart, questId, fromItem and 1 or 2, fromItem and itemId or 0)
				if ok then note("ev:POPUP") else fail(err) end
			end
		end)
	elseif db then
		note("hook:none")
	end
	if db and enabled() and not db.noticed then
		db.noticed = true
		print(CHAT_TITLE .. qcL.RECORDERNOTICE)
	end
end

local function status()
	print(CHAT_TITLE .. string.format(qcL.RECORDERSTATUS, enabled() and VIDEO_OPTIONS_ENABLED or VIDEO_OPTIONS_DISABLED))
end

function qcRecorderReport()
	status()
	if not db then return end
	print(CHAT_TITLE .. string.format(qcL.RECORDERCOUNTS, counts.g, counts.q, counts.s))
	if db.ev > 0 then print(CHAT_TITLE .. string.format(qcL.RECORDERFULL, db.ev)) end
	if db.err.n > 0 then print(CHAT_TITLE .. string.format(qcL.RECORDERERRORS, db.err.n, db.err.last or "")) end
	local hidden = 0
	for key, n in pairs(db.d) do
		if type(key) == "string" and key:find(":hid:", 1, true) and type(n) == "number" then hidden = hidden + n end
	end
	if hidden > 0 then print(CHAT_TITLE .. string.format(qcL.RECORDERHIDDEN, hidden)) end
	print(CHAT_TITLE .. qcL.RECORDERFILE)
end

function qcRecorderSetEnabled(on)
	qcSettings.QC_RECORD_GIVERS = on and 1 or 0
	if on then failures, stopped, errorShown = 0, false, false end
	qcApplySettings()
end

function qcRecorderCommand(text)
	text = text or ""
	if text == "on" or text == "off" then
		qcRecorderSetEnabled(text == "on")
	elseif text == "clear" and db then
		db.g, db.q, db.s, db.d, db.ev, db.err = {}, {}, {}, {}, 0, {n = 0}
		counts.g, counts.q, counts.s = 0, 0, 0
		print(CHAT_TITLE .. qcL.RECORDERCLEARED)
		return
	end
	status()
end

qcRecorderApply = apply
frame:SetScript("OnEvent", onEvent)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
