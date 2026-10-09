-- Prints the quest giver notes in a saved-variables file as tab-separated lines for
-- Import-RecordedGivers.ps1. usage: lua Read-RecordedGivers.lua <QuestCompletist.lua> [tag]
--
-- The file may come from a player, and a saved-variables file is Lua code, so this never runs it as
-- it stands. It is read as text first and refused unless it is nothing but assignments of tables,
-- strings, numbers and true, false or nil to names: no call, no operator, no function, no long
-- string, no name used as a value. What passes is then loaded with no globals at all. The file may
-- not be larger than 8 MB or nest tables deeper than 24. A refused file ends the run with exit code 2
-- and one line, "refused", a tab and the reason, as the whole of the output.
--
-- Two kinds of notes are read: qcQuestRecorder, the addon's own (schema 1; qcRecorder.lua has the
-- layout), and QCForeverProbeDB, the Forever probe's, which kept the same facts in tables.
--   file     tag  kind (recorder or probe)  schema  game  records  odd-records
--   build    build number  version
--   giver    kind  id  name  build  flags
--   spot     kind  id  map  x  y  visits  build
--   offer    kind  id  questId
--   turnin   kind  id  questId
--   quest    questId  build  frequency  repeatable  accepted  offered  faction  race  class  heading
--   start    questId  kind  item  map  x  y  build
--   diag     key  count
--   flagged  questId  how  build
--   bad      table  key  why
-- A frequency or repeatable the game never said is empty. The positions are the player's, in percent
-- of the map, -1 when the game gave none. A start of kind 0 is the probe's, which kept every giverless
-- window, including ones that opened wherever the player was.

local MAX_BYTES = 8 * 1024 * 1024
local MAX_DEPTH = 24
local MAX_ID = 9999999

-- The most the addon's recorder keeps (qcRecorder.lua); a file with more was not written by it. The
-- probe kept everything, so its limits are only there to bound the work.
local MAX_GIVERS, MAX_QUESTS, MAX_STARTS, MAX_SPOTS, MAX_LIST = 2500, 5000, 500, 4, 60
local MAX_PROBE_ENTRIES, MAX_PROBE_PARTS = 20000, 1000
local MAX_INSTRUCTIONS = 50000000

local function readAll(path)
	local f, err = io.open(path, "rb")
	if not f then return nil, "can't open: " .. tostring(err) end
	local size = f:seek("end")
	if not size then
		f:close()
		return nil, "can't read it"
	end
	if size > MAX_BYTES then
		f:close()
		return nil, "larger than 8 MB"
	end
	f:seek("set", 0)
	local text = f:read("*a")
	f:close()
	if not text then return nil, "can't read it" end
	return text
end

-- Reads the text the way the game writes it and refuses everything else. Returns nil and a reason.
local function checkPlainData(text)
	local pos, len = 1, #text
	local line = 1
	local token, tokenValue

	local function fail(why)
		error({why = why .. " (line " .. line .. ")"}, 0)
	end

	local function countLines(from, to)
		local _, n = text:sub(from, to):gsub("\n", "")
		line = line + n
	end

	local function nextToken()
		while true do
			local s, e = text:find("^[ \t\r\n]+", pos)
			if s then
				countLines(s, e)
				pos = e + 1
			elseif text:find("^%-%-", pos) then
				if text:find("^%-%-%[=*%[", pos) then fail("a long comment") end
				local e2 = text:find("[\r\n]", pos) or len + 1
				pos = e2
			else
				break
			end
		end
		if pos > len then token, tokenValue = "eof", nil return end
		local c = text:sub(pos, pos)
		if c == "{" or c == "}" or c == "]" or c == "," or c == ";" then
			token, tokenValue = c, nil
			pos = pos + 1
		elseif c == "[" then
			if text:find("^%[[=%[]", pos) then fail("a long string") end
			token, tokenValue = "[", nil
			pos = pos + 1
		elseif c == "=" then
			if text:sub(pos + 1, pos + 1) == "=" then fail("an operator") end
			token, tokenValue = "=", nil
			pos = pos + 1
		elseif c == '"' or c == "'" then
			local from = pos + 1
			while true do
				local at = text:find("[\\\n" .. c .. "]", from)
				if not at then fail("an unfinished string") end
				local found = text:sub(at, at)
				if found == c then
					pos = at + 1
					break
				elseif found == "\n" then
					fail("a string across lines")
				else
					from = at + 2
					if from > len + 1 then fail("an unfinished string") end
				end
			end
			token, tokenValue = "string", nil
		elseif c:find("[%d%-%.]") then
			local s, e = text:find("^%-?0[xX]%x+", pos)
			if not s then s, e = text:find("^%-?%d+%.?%d*", pos) end
			if not s then s, e = text:find("^%-?%.%d+", pos) end
			if not s then fail("a stray '" .. c .. "'") end
			local s2, e2 = text:find("^[eE][+-]?%d+", e + 1)
			if s2 then e = e2 end
			if text:find("^[%w_.#]", e + 1) then fail("a number followed by more") end
			pos = e + 1
			token, tokenValue = "number", nil
		elseif c:find("[%a_]") then
			local s, e = text:find("^[%a_][%w_]*", pos)
			tokenValue = text:sub(s, e)
			pos = e + 1
			token = "name"
		else
			fail("the character '" .. c .. "'")
		end
	end

	local parseValue

	local function parseTable(depth)
		if depth > MAX_DEPTH then fail("tables nested too deep") end
		nextToken()
		while token ~= "}" do
			if token == "[" then
				nextToken()
				if token ~= "string" and token ~= "number" then fail("a key that isn't text or a number") end
				nextToken()
				if token ~= "]" then fail("a key without its bracket") end
				nextToken()
				if token ~= "=" then fail("a key without a value") end
				nextToken()
				parseValue(depth)
				nextToken()
			elseif token == "name" then
				local name = tokenValue
				nextToken()
				if token == "=" then
					nextToken()
					parseValue(depth)
					nextToken()
				elseif name ~= "true" and name ~= "false" and name ~= "nil" then
					fail("the name '" .. name .. "' used as a value")
				end
			else
				parseValue(depth)
				nextToken()
			end
			if token == "," or token == ";" then
				nextToken()
			elseif token ~= "}" then
				fail("a table that isn't closed")
			end
		end
	end

	-- Reads one value starting at the current token; leaves the token on its last part.
	function parseValue(depth)
		if token == "{" then
			parseTable(depth + 1)
		elseif token == "string" or token == "number" then
			return
		elseif token == "name" and (tokenValue == "true" or tokenValue == "false" or tokenValue == "nil") then
			return
		else
			fail("something that isn't a value")
		end
	end

	local ok, err = pcall(function()
		nextToken()
		while token ~= "eof" do
			if token ~= "name" then fail("a line that doesn't start with a name") end
			nextToken()
			if token ~= "=" then fail("a name without a value") end
			nextToken()
			parseValue(0)
			nextToken()
			if token == ";" then nextToken() end
		end
	end)
	if ok then return true end
	if type(err) == "table" then return nil, err.why end
	return nil, tostring(err)
end

local function loadPlainData(path)
	local text, err = readAll(path)
	if not text then return nil, err end
	if #text > MAX_BYTES then return nil, "larger than 8 MB" end
	if #text == 0 then return nil, "empty" end
	if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end
	local ok, why = checkPlainData(text)
	if not ok then return nil, "not plain saved variables: " .. why end
	local chunk, loadError = loadstring(text, "=saved")
	if not chunk then return nil, "doesn't load: " .. tostring(loadError) end
	local env = {}
	setfenv(chunk, env)
	-- Nothing that passed the check can run for long; if something did, it is cut off.
	debug.sethook(function() error("runs too long", 2) end, "", MAX_INSTRUCTIONS)
	local ran, runError = pcall(chunk)
	debug.sethook()
	if not ran then return nil, "doesn't run: " .. tostring(runError) end
	return env
end

local function clean(value)
	return (tostring(value == nil and "" or value):gsub("[%c]", " "))
end

-- A name or heading the game gave whole; anything else is nothing. A leading = + @ or - is what a
-- spreadsheet takes for a formula, and "|" is how the addon's own records are cut.
local function safeText(text)
	if #text > 64 or text:find("[|%c]") or text:find("^[=+@%-]") then return "" end
	return text
end

-- Positions to four places, so nothing prints in exponent notation or as -0.
local function tidy(n)
	return math.floor(n * 10000 + 0.5) / 10000
end

local function whole(v, low, high)
	return type(v) == "number" and v == v and v == math.floor(v) and v >= low and v <= high
end

local function split(text, sep)
	local parts, from = {}, 1
	while true do
		local at = text:find(sep, from, true)
		if not at then
			parts[#parts + 1] = text:sub(from)
			return parts
		end
		parts[#parts + 1] = text:sub(from, at - 1)
		from = at + 1
	end
end

local function sortedKeys(t)
	local list = {}
	for key in pairs(t) do list[#list + 1] = key end
	table.sort(list, function(a, b)
		if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
		return tostring(a) < tostring(b)
	end)
	return list
end

local function count(t)
	local n = 0
	if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
	return n
end

local function readRecorder(db, out, tag)
	local bad = 0
	local function reject(which, key, why)
		bad = bad + 1
		out[#out + 1] = {"bad", which, clean(key), why}
	end
	local function ids(text)
		local list = {}
		if text == "" then return list end
		for _, part in ipairs(split(text, ",")) do
			local n = tonumber(part)
			if not whole(n, 1, MAX_ID) or #list >= MAX_LIST then return nil end
			list[#list + 1] = n
		end
		return list
	end
	local function coordinate(text)
		local n = tonumber(text)
		if type(n) ~= "number" or n ~= n then return nil end
		if n == -1 then return -1 end
		if n >= 0 and n <= 100 then return tidy(n) end
		return nil
	end

	local builds = {}
	if type(db.bv) == "table" then
		for _, build in ipairs(sortedKeys(db.bv)) do
			if whole(build, 1, 1e9) and type(db.bv[build]) == "string" and #db.bv[build] <= 20 and not db.bv[build]:find("[%c|\t]") then
				builds[build] = db.bv[build]
				out[#out + 1] = {"build", build, db.bv[build]}
			end
		end
	end

	local records = 0
	if type(db.g) == "table" then
		for _, key in ipairs(sortedKeys(db.g)) do
			local record = db.g[key]
			records = records + 1
			local kind, id = nil, nil
			if type(key) == "string" then kind, id = key:match("^(%a+):(%d+)$") end
			id = tonumber(id)
			local f = type(record) == "string" and split(record, "|") or nil
			if not (kind and (kind == "Creature" or kind == "GameObject" or kind == "Vehicle") and whole(id, 1, MAX_ID)) then
				reject("giver", key, "key")
			elseif not f or #f ~= 7 then
				reject("giver", key, "fields")
			else
				local build, flags = tonumber(f[2]), tonumber(f[7])
				local offers, turns = ids(f[5]), ids(f[6])
				local spots, spotsOk = {}, true
				if f[4] ~= "" then
					local parts = split(f[4], ";")
					if #parts > MAX_SPOTS then spotsOk = false end
					for _, part in ipairs(parts) do
						local map, x, y, visits = part:match("^(%d+) (%-?[%d.]+) (%-?[%d.]+) (%d+)$")
						map, visits = tonumber(map), tonumber(visits)
						x, y = coordinate(x), coordinate(y)
						if whole(map, 1, 1e6) and x and y and whole(visits, 1, 999) then
							spots[#spots + 1] = {map, x, y, visits}
						else
							spotsOk = false
						end
					end
				end
				if not (whole(build, 1, 1e9) and whole(flags, 0, 7) and offers and turns and spotsOk) then
					reject("giver", key, "values")
				else
					local name = f[1]
					name = safeText(name)
					out[#out + 1] = {"giver", kind, id, name, build, flags}
					for _, spot in ipairs(spots) do
						out[#out + 1] = {"spot", kind, id, spot[1], spot[2], spot[3], spot[4], build}
					end
					for _, quest in ipairs(offers) do out[#out + 1] = {"offer", kind, id, quest} end
					for _, quest in ipairs(turns) do out[#out + 1] = {"turnin", kind, id, quest} end
				end
			end
		end
	end

	if type(db.q) == "table" then
		for _, key in ipairs(sortedKeys(db.q)) do
			local record = db.q[key]
			records = records + 1
			local f = type(record) == "string" and split(record, "|") or nil
			if not whole(key, 1, MAX_ID) then
				reject("quest", key, "key")
			elseif not f or #f ~= 7 then
				reject("quest", key, "fields")
			else
				local build, flags, faction, race, class = tonumber(f[1]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
				if not (whole(build, 1, 1e9) and whole(flags, 0, 127) and whole(faction, 0, 7) and whole(race, 0, 2^31) and whole(class, 0, 2^31)) then
					reject("quest", key, "values")
				else
					local frequency = (flags % 2 >= 1) and (math.floor(flags / 2) % 4) or ""
					local repeatable = (flags % 128 >= 64) and ((flags % 16 >= 8) and 1 or 0) or ""
					local heading = f[7]
					heading = safeText(heading)
					out[#out + 1] = {"quest", key, build, frequency, repeatable, (flags % 32 >= 16) and 1 or 0, (flags % 64 >= 32) and 1 or 0,
						faction, race, class, heading}
				end
			end
		end
	end

	if type(db.s) == "table" then
		for _, key in ipairs(sortedKeys(db.s)) do
			local record = db.s[key]
			records = records + 1
			local f = type(record) == "string" and split(record, "|") or nil
			if not whole(key, 1, MAX_ID) then
				reject("start", key, "key")
			elseif not f or #f ~= 7 then
				reject("start", key, "fields")
			else
				local kind, item, map, x, y, build = tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), coordinate(f[4]), coordinate(f[5]), tonumber(f[6])
				if not (whole(kind, 1, 2) and whole(item, 0, 1e9) and whole(map, 0, 1e6) and x and y and whole(build, 1, 1e9)) then
					reject("start", key, "values")
				else
					out[#out + 1] = {"start", key, kind, item, map, x, y, build}
				end
			end
		end
	end

	if type(db.d) == "table" then
		for _, key in ipairs(sortedKeys(db.d)) do
			local n = db.d[key]
			if type(key) == "string" and #key <= 64 and not key:find("[%c|\t]") and whole(n, 0, 1e9) then
				out[#out + 1] = {"diag", key, n}
			end
		end
	end

	local schema = db.v
	return records, bad, schema, builds
end

local function buildNumber(text)
	return tonumber(tostring(text):match("(%d+)$"))
end

local function readProbe(db, out)
	local bad = 0
	local function reject(which, key, why)
		bad = bad + 1
		out[#out + 1] = {"bad", which, clean(key), why}
	end
	local seenBuilds = {}
	local function noteBuild(text)
		local build = buildNumber(text)
		if build and not whole(build, 1, 1e9) then return nil end
		local version = type(text) == "string" and text:match("^(%d+%.%d+%.%d+)%.") or nil
		if build and version and not seenBuilds[build] then
			seenBuilds[build] = version
			out[#out + 1] = {"build", build, version}
		end
		return build
	end
	local records = 0
	local function coordinate(v)
		if type(v) == "number" and v == v and v >= 0 and v <= 100 then return tidy(v) end
	end

	if type(db.givers) == "table" then
		for _, key in ipairs(sortedKeys(db.givers)) do
			local giver = db.givers[key]
			records = records + 1
			if type(giver) ~= "table" or not (giver.kind == "Creature" or giver.kind == "GameObject" or giver.kind == "Vehicle")
				or not whole(giver.id, 1, MAX_ID) or count(giver.spots) > MAX_PROBE_PARTS or count(giver.offers) > MAX_PROBE_PARTS
				or count(giver.turnIns) > MAX_PROBE_PARTS then
				reject("giver", key, "shape")
			else
				local build = noteBuild(giver.build)
				if not build then
					reject("giver", key, "build")
				else
					local name = type(giver.name) == "string" and safeText(giver.name) or ""
					out[#out + 1] = {"giver", giver.kind, giver.id, name, build, 0}
					if type(giver.spots) == "table" then
						for _, spotKey in ipairs(sortedKeys(giver.spots)) do
							local map, x, y = tostring(spotKey):match("^(%d+) (%-?[%d.]+) (%-?[%d.]+)$")
							map, x, y = tonumber(map), coordinate(tonumber(x)), coordinate(tonumber(y))
							local visits = giver.spots[spotKey]
							if whole(map, 1, 1e6) and x and y and whole(visits, 1, 1e9) then
								out[#out + 1] = {"spot", giver.kind, giver.id, map, x, y, math.min(visits, 999), build}
							end
						end
					end
					if type(giver.offers) == "table" then
						for _, quest in ipairs(sortedKeys(giver.offers)) do
							if whole(quest, 1, MAX_ID) then
								out[#out + 1] = {"offer", giver.kind, giver.id, quest}
								local info = giver.offers[quest]
								if type(info) == "table" then
									local frequency = info.frequency
									if not whole(frequency, 0, 3) then frequency = "" end
									local repeatable = info.repeatable
									if type(repeatable) == "boolean" then repeatable = repeatable and 1 or 0 else repeatable = "" end
									if frequency ~= "" or repeatable ~= "" then
										out[#out + 1] = {"quest", quest, build, frequency, repeatable, 0, 1, 0, 0, 0, ""}
									end
								end
							end
						end
					end
					if type(giver.turnIns) == "table" then
						for _, quest in ipairs(sortedKeys(giver.turnIns)) do
							if whole(quest, 1, MAX_ID) then out[#out + 1] = {"turnin", giver.kind, giver.id, quest} end
						end
					end
				end
			end
		end
	end
	if type(db.accepted) == "table" then
		for _, quest in ipairs(sortedKeys(db.accepted)) do
			local row = db.accepted[quest]
			records = records + 1
			local build = type(row) == "table" and noteBuild(row.build)
			if whole(quest, 1, MAX_ID) and build then
				local heading = type(row.heading) == "string" and safeText(row.heading) or ""
				out[#out + 1] = {"quest", quest, build, "", "", 1, 0, 0, 0, 0, heading}
			else
				reject("quest", quest, "shape")
			end
		end
	end
	if type(db.started) == "table" then
		for _, quest in ipairs(sortedKeys(db.started)) do
			local row = db.started[quest]
			records = records + 1
			local build = type(row) == "table" and noteBuild(row.build)
			if whole(quest, 1, MAX_ID) and build then
				local map, x, y = row.map, coordinate(row.x), coordinate(row.y)
				if not whole(map, 1, 1e6) then map, x, y = 0, -1, -1 end
				out[#out + 1] = {"start", quest, 0, whole(row.item, 0, 1e9) and row.item or 0, map, x or -1, y or -1, build}
			else
				reject("start", quest, "shape")
			end
		end
	end
	return records, bad, "probe", seenBuilds
end

local function gameOf(builds)
	local game
	for _, version in pairs(builds) do
		local major = tonumber(version:match("^(%d+)%."))
		local thisGame = (major == 12 and "retail") or (major == 1 and "forever") or "unknown"
		if game and game ~= thisGame then return "mixed" end
		game = thisGame
	end
	return game or "unknown"
end

-- Every line the file holds, as lists of fields, or nil and the reason the file was refused.
local function readFile(path, tag)
	local env, err = loadPlainData(path)
	if not env then return nil, err end
	local out, records, bad, schema, builds, kind = {}, 0, 0, nil, {}, nil
	if type(env.qcQuestRecorder) == "table" then
		kind = "recorder"
		local db = env.qcQuestRecorder
		if count(db.g) > MAX_GIVERS or count(db.q) > MAX_QUESTS or count(db.s) > MAX_STARTS then
			return nil, "more records than the addon keeps"
		end
		records, bad, schema, builds = readRecorder(db, out, tag)
		if schema ~= 1 then return nil, "schema " .. tostring(schema) .. ", which this reads no further than 1" end
	elseif type(env.QCForeverProbeDB) == "table" then
		kind = "probe"
		local db = env.QCForeverProbeDB
		if count(db.givers) > MAX_PROBE_ENTRIES or count(db.accepted) > MAX_PROBE_ENTRIES or count(db.started) > MAX_PROBE_ENTRIES then
			return nil, "more records than the probe could have kept"
		end
		records, bad, schema, builds = readProbe(db, out)
	else
		return nil, "no qcQuestRecorder or QCForeverProbeDB in it"
	end
	if type(env.qcFlaggedButSeen) == "table" then
		for _, quest in ipairs(sortedKeys(env.qcFlaggedButSeen)) do
			local row = env.qcFlaggedButSeen[quest]
			if whole(quest, 1, MAX_ID) and type(row) == "table" and (row.how == "accepted" or row.how == "turned in") then
				out[#out + 1] = {"flagged", quest, row.how, whole(row.build, 0, 1e9) and row.build or ""}
			end
		end
	end
	table.insert(out, 1, {"file", tag or "", kind, schema, gameOf(builds), records, bad})
	return out
end

local function main()
	local path, tag = arg[1], arg[2]
	if not path then
		io.write("refused\tno file named; usage: lua Read-RecordedGivers.lua <QuestCompletist.lua> [tag]\n")
		os.exit(2)
	end
	local lines, err = readFile(path, tag)
	if not lines then
		io.write("refused\t", clean(err), "\n")
		os.exit(2)
	end
	local parts = {}
	for _, fields in ipairs(lines) do
		for i = 1, #fields do fields[i] = clean(fields[i]) end
		parts[#parts + 1] = table.concat(fields, "\t")
	end
	io.write(table.concat(parts, "\n"), "\n")
end

if RECORDED_GIVERS_AS_LIBRARY then
	return {readFile = readFile, checkPlainData = checkPlainData}
end
main()
