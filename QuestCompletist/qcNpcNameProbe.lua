--[[ Diagnostic, run with /qc npccheck. Measures what showing quest givers' names in the client's
language needs (docs/plans/localized-npc-names.md, phase 1):
  - how many pin NPCs C_TooltipInfo.GetHyperlink can name straight away;
  - for the rest, whether TOOLTIP_DATA_UPDATE brings the name, how long it takes, and how many never
    come, with a limited number in flight and a 5 s timeout;
  - what the reply looks like before the name is there;
  - whether combat or an instance changes any of that;
  - the name the client gives, to compare with ours in qcPinDB;
  - whether creatures sharing an English name share the translated one (/qc npccheck names).

/qc npccheck                        the NPCs on the pins of the map you're on
/qc npccheck <map ID> [in flight]   the NPCs on that map's pins
/qc npccheck all [in flight]        every NPC on any pin
/qc npccheck names [in flight]      every creature ID the client has for six names with several
/qc npccheck stop                   stops the run in progress
In flight defaults to 4.

Each run is appended to qcNpcNameProbeResults, which /reload (or logging out) saves. One row per NPC:
  result | ms | lines | first reply | name | ours
result: now (named straight away), event (named on TOOLTIP_DATA_UPDATE), poll (named on a re-check
with no event), late (named after the timeout), none (never named); ms: time to the name; lines:
the number of tooltip lines when named; first reply: what the first reply held when it had no name.

Delete this file once phase 1 is done. ]]--

local DEFAULT_IN_FLIGHT = 4
local REQUEST_TIMEOUT_MS = 5000
local POLL_MS = 1000
local LATE_ANSWER_WAIT_MS = 10000
local TICK_SECONDS = 0.05

-- From the client's Creature table (wago.tools, build 12.1.0.69933): every creature with that name.
local SAME_NAME_IDS = {
	["Archmage Khadgar"] = {72874,75805,77184,78288,78423,78558,78559,78560,78561,78562,78563,78813,
		79657,80142,80146,81130,81191,81420,82164,83823,83863,84702,85591,85616,86380,90115,90137,90233,
		92213,97296,97978,101159,102988,112130,113686,114909,115039,115102,115367,115375,115464,115504,
		115510,116740,122087,153223,154055,183556,186301,186688,186779,187718,187720,189996,191542,192091,
		192322,193837,197931,198327,203522,206521,215693,215695,216208,218281,227436,227437,228966,229844,
		233239,241740,241743,242299,242581,242585},
	["Thrall"] = {68025,68059,70859,71149,71344,75186,76242,76488,76588,76622,77107,78553,80209,82851,
		82919,84928,84953,90711,96527,109791,152155,152977,155787,157537,158316,162409,167021,167675,
		167926,173113,173253,173583,174850,176532,179151,179225,181232,181282,181394,181785,184099,184599,
		201620,214919,216167,223722,228456,229041,229321,253222,256547},
	["Draka"] = {72230,72543,72651,74593,74651,75808,75863,76485,76721,77018,77278,82233,82337,86401,
		86517,88649,89822,90481,157575,160217,199249},
	["Durotan"] = {74163,74594,75188,75806,76484,77017,77280,77485,78272,81186,81414,81415,84443,84729,
		84731,90311,92401,199243},
	["Garrosh Hellscream"] = {39605,64629,67867,68882,71865,72349,73462,81165,87405,140199,178922},
	["Grand Magister Rommath"] = {16800,130128,130193,235483,236583,241043,242413,245587,250395,256913,
		264066,264070,264956},
}

local run = nil

local function say(message)
	print("|cFFFFD100Quest Completist:|r " .. message)
end

local function isPlaceholder(text)
	return text == RETRIEVING_DATA or text == RETRIEVING_ITEM_INFO or text == UNKNOWN or text == UNKNOWNOBJECT
end

-- Returns the name (or nil), the number of lines, what the reply held when it had no name, and the
-- reply's dataInstanceID.
local function ask(npcId)
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, string.format("unit:Creature-0-0-0-0-%d-0000000000", npcId))
	if not ok then return nil, 0, "error: " .. tostring(data) end
	if not data then return nil, 0, "no data" end
	if issecretvalue and issecretvalue(data) then return nil, 0, "secret data" end
	local instance = data.dataInstanceID
	local lines = data.lines
	if not lines or #lines == 0 then return nil, 0, "no lines", instance end
	local text = lines[1].leftText
	if issecretvalue and issecretvalue(text) then return nil, #lines, "secret text", instance end
	if text == nil then return nil, #lines, "no text", instance end
	if text == "" then return nil, #lines, "empty text", instance end
	if isPlaceholder(text) then return nil, #lines, "placeholder: " .. text, instance end
	return text, #lines, nil, instance
end

local function row(result, ms, lines, firstReply, name, ours)
	return table.concat({result, ms and string.format("%d", ms) or "-", tostring(lines or 0),
		firstReply or "-", name or "", ours or ""}, "|")
end

local function topCounts(counts, limit)
	local keys = {}
	for key in pairs(counts) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return counts[a] > counts[b] end)
	local parts = {}
	for i = 1, math.min(limit, #keys) do parts[#parts + 1] = string.format("%s %d", keys[i], counts[keys[i]]) end
	return table.concat(parts, ", ")
end

local function finish(stopped)
	local r = run
	run = nil
	r.ticker:Cancel()
	local record = r.record
	record.finished = time()
	record.stopped = stopped or nil
	record.seconds = (debugprofilestop() - r.startedMs) / 1000

	local counts = {now = 0, event = 0, poll = 0, late = 0, none = 0}
	local firstReplies = {}
	local namedMs, maxMs, named = 0, 0, 0
	local differ, examples = 0, {}
	local byEnglish = {}
	for npcId, line in pairs(record.npcs) do
		local result, ms, _, firstReply, name, ours = strsplit("|", line, 6)
		if counts[result] then counts[result] = counts[result] + 1 end
		if firstReply ~= "-" then firstReplies[firstReply] = (firstReplies[firstReply] or 0) + 1 end
		if result == "event" or result == "poll" then
			local value = tonumber(ms) or 0
			namedMs, named = namedMs + value, named + 1
			if value > maxMs then maxMs = value end
		end
		if name ~= "" and ours ~= "" and name ~= ours then
			differ = differ + 1
			if #examples < 5 then examples[#examples + 1] = string.format("  [%d] ours %q, client %q", npcId, ours, name) end
		end
		if record.mode == "names" and name ~= "" then
			byEnglish[ours] = byEnglish[ours] or {}
			byEnglish[ours][name] = (byEnglish[ours][name] or 0) + 1
		end
	end

	say(string.format("%s %s: %d NPCs in %.1f s (%d in flight%s%s). %d named straight away, %d on the event, %d on a re-check, %d after the timeout, %d never. Requested ones took %d ms on average, %d ms at most. %d names differ from ours.",
		stopped and "Stopped" or "Finished", record.label, r.total, record.seconds, record.inFlight,
		record.instanceType ~= "none" and (", in an instance: " .. tostring(record.instanceType)) or "",
		record.requestsInCombat > 0 and string.format(", %d requested in combat", record.requestsInCombat) or "",
		counts.now, counts.event, counts.poll, counts.late, counts.none,
		named > 0 and math.floor(namedMs / named) or 0, maxMs, differ))
	if next(firstReplies) then say("First replies without a name: " .. topCounts(firstReplies, 8)) end
	say(string.format("Events: %d named an NPC, %d came without a name, %d were for other tooltips.",
		record.eventsNamed, record.eventsWithoutName, record.otherEvents))
	for _, line in ipairs(examples) do print(line) end
	if record.mode == "names" then
		for english, names in pairs(byEnglish) do say(string.format("%s -> %s", english, topCounts(names, 5))) end
	end
	say("/reload to save the results.")
end

local function named(npcId, result, name, lines)
	local r = run
	local started = r.inFlight[npcId] or r.timedOut[npcId]
	r.record.npcs[npcId] = row(result, debugprofilestop() - started, lines, r.firstReply[npcId], name, r.ours[npcId])
	if r.inFlight[npcId] then
		r.inFlight[npcId] = nil
		r.inFlightCount = r.inFlightCount - 1
	end
	r.timedOut[npcId] = nil
end

local function send(npcId)
	local r = run
	local now = debugprofilestop()
	if InCombatLockdown() then r.record.requestsInCombat = r.record.requestsInCombat + 1 end
	local name, lines, firstReply, instance = ask(npcId)
	if name then
		r.record.npcs[npcId] = row("now", nil, lines, nil, name, r.ours[npcId])
		return
	end
	r.firstReply[npcId] = firstReply
	r.inFlight[npcId] = now
	r.lastAsked[npcId] = now
	r.inFlightCount = r.inFlightCount + 1
	if instance then r.byInstance[instance] = npcId end
end

local function recheck(npcId, result)
	local r = run
	local name, lines, _, instance = ask(npcId)
	r.lastAsked[npcId] = debugprofilestop()
	if instance then r.byInstance[instance] = npcId end
	if name then named(npcId, result, name, lines) end
	return name
end

local function tick()
	local r = run
	if not r then return end
	local now = debugprofilestop()
	for npcId, started in pairs(r.inFlight) do
		if now - started > REQUEST_TIMEOUT_MS then
			r.inFlight[npcId] = nil
			r.inFlightCount = r.inFlightCount - 1
			r.timedOut[npcId] = started
			r.record.npcs[npcId] = row("none", nil, 0, r.firstReply[npcId], nil, r.ours[npcId])
		elseif now - r.lastAsked[npcId] >= POLL_MS then
			recheck(npcId, "poll")
		end
	end
	while r.inFlightCount < r.record.inFlight and r.nextIndex <= #r.queue do
		local npcId = r.queue[r.nextIndex]
		r.nextIndex = r.nextIndex + 1
		send(npcId)
	end
	if r.inFlightCount == 0 and r.nextIndex > #r.queue then
		if next(r.timedOut) and not r.lateWaitUntil then
			r.lateWaitUntil = now + LATE_ANSWER_WAIT_MS
		end
		if r.lateWaitUntil and now > r.lateWaitUntil then
			for npcId in pairs(r.timedOut) do recheck(npcId, "late") end
		end
		if not next(r.timedOut) or now > r.lateWaitUntil then
			finish(false)
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("TOOLTIP_DATA_UPDATE")
events:SetScript("OnEvent", function(_, _, dataInstanceID)
	local r = run
	if not r then return end
	local npcId = dataInstanceID and r.byInstance[dataInstanceID]
	if not npcId or not (r.inFlight[npcId] or r.timedOut[npcId]) then
		r.record.otherEvents = r.record.otherEvents + 1
		return
	end
	r.byInstance[dataInstanceID] = nil
	if recheck(npcId, r.inFlight[npcId] and "event" or "late") then
		r.record.eventsNamed = r.record.eventsNamed + 1
	else
		r.record.eventsWithoutName = r.record.eventsWithoutName + 1
	end
end)

local function pinNpcs(mapId)
	local ours = {}
	for pinMapId, pins in pairs(qcPinDB) do
		if not mapId or pinMapId == mapId then
			for _, pin in ipairs(pins) do
				if (pin[2] or 0) ~= 0 and not ours[pin[2]] then ours[pin[2]] = pin[3] or "" end
			end
		end
	end
	return ours
end

local function start(mode, mapId, inFlight)
	local ours, label = {}, nil
	if mode == "names" then
		for english, ids in pairs(SAME_NAME_IDS) do
			for _, npcId in ipairs(ids) do ours[npcId] = english end
		end
		label = "same-name creatures"
	elseif mode == "all" then
		ours = pinNpcs(nil)
		label = "every pin NPC"
	else
		ours = pinNpcs(mapId)
		local info = C_Map.GetMapInfo(mapId)
		label = string.format("%s (%d)", info and info.name or "?", mapId)
	end
	local queue = {}
	for npcId in pairs(ours) do queue[#queue + 1] = npcId end
	table.sort(queue)
	if #queue == 0 then
		say("no NPCs to check for " .. label .. ".")
		return
	end

	qcNpcNameProbeResults = qcNpcNameProbeResults or {}
	local version, build = GetBuildInfo()
	local inInstance, instanceType = IsInInstance()
	local record = {mode = mode, map = mapId, label = label, inFlight = inFlight, locale = GetLocale(),
		build = string.format("%s.%s", tostring(version), tostring(build)), started = time(),
		combatAtStart = InCombatLockdown() or nil, instanceType = inInstance and instanceType or "none",
		requestsInCombat = 0, eventsNamed = 0, eventsWithoutName = 0, otherEvents = 0, npcs = {}}
	table.insert(qcNpcNameProbeResults, record)

	run = {record = record, ours = ours, total = #queue, queue = queue, nextIndex = 1, inFlight = {},
		inFlightCount = 0, timedOut = {}, lastAsked = {}, firstReply = {}, byInstance = {},
		startedMs = debugprofilestop()}
	say(string.format("NPC name check: %s, %d NPCs, %d in flight...", label, #queue, inFlight))
	run.ticker = C_Timer.NewTicker(TICK_SECONDS, tick)
end

function qcNpcNameProbe(argument)
	local first, second = strsplit(" ", strtrim(argument or ""))
	if first == "stop" then
		if run then finish(true) else say("no NPC name check is running.") end
		return
	end
	if run then
		say("an NPC name check is already running; /qc npccheck stop first.")
		return
	end
	local inFlight = tonumber(second) or DEFAULT_IN_FLIGHT
	if first == "all" or first == "names" then
		start(first, nil, inFlight)
		return
	end
	local mapId = tonumber(first)
	if not mapId then
		mapId = C_Map.GetBestMapForUnit("player")
		if not mapId then
			say("can't tell which map you're on; give one: /qc npccheck <map ID>.")
			return
		end
	end
	start("map", mapId, inFlight)
end
