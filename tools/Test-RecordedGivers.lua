--[[
Checks Read-RecordedGivers.lua, which reads saved-variables files that may come from players. It must
read the addon's own notes and the Forever probe's, and refuse anything that is not plain data.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-RecordedGivers.lua
The importer's rules (trust, filters, what changes a pin) are checked by Test-RecordedGivers.ps1.
]]

RECORDED_GIVERS_AS_LIBRARY = true
local reader = dofile("tools/Read-RecordedGivers.lua")
local lua = arg and arg[-1] or "lua"

local passed, failed = 0, 0
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

local files = {}
local function write(text)
	local path = os.tmpname()
	files[#files + 1] = path
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
	return path
end

local function refused(text, why, message)
	local lines, err = reader.readFile(write(text), "t")
	check(lines == nil, message .. ": refused")
	if why and err then check(err:find(why, 1, true) ~= nil, message .. ": says " .. why .. " (got " .. err .. ")") end
end

local function kinds(lines)
	local counts = {}
	for _, fields in ipairs(lines) do counts[fields[1]] = (counts[fields[1]] or 0) + 1 end
	return counts
end

local function find(lines, kind, ...)
	local want = {...}
	for _, fields in ipairs(lines) do
		if fields[1] == kind then
			local ok = true
			for i, value in ipairs(want) do
				if tostring(fields[i + 1]) ~= tostring(value) then ok = false end
			end
			if ok then return fields end
		end
	end
end

-- A file the way the game writes one.
local recorder = [[
qcQuestRecorder = {
	["bv"] = {
		[69933] = "12.1.0",
		[69000] = "12.0.7",
	},
	["v"] = 1,
	["seq"] = 12,
	["ev"] = 0,
	["noticed"] = true,
	["err"] = {
		["n"] = 0,
	},
	["d"] = {
		["rd:GOSSIP_SHOW:npc:ok:w"] = 4,
		["pos:nil"] = 1,
	},
	["g"] = {
		["Creature:3701"] = "Guard Roberts|69933|9|84 45.3 67.8 3;84 60.1 22.0 1|100,101|102|0",
		["GameObject:175320"] = "WANTED: Murkdeep!|69933|10|1 10.0 20.0 1||100|0",
		["Creature:42"] = "|69933|11|84 -1 -1 1|7||0",
	},
	["q"] = {
		[100] = "69933|9|32|1|8|1024|Teldrassil",
		[101] = "69933|9|107|3|40|1|",
		[103] = "69933|12|16|2|2|4|Durotar",
	},
	["s"] = {
		[800] = "1|5555|84|45.3|67.8|69933|7",
		[801] = "2|0|84|-1|-1|69933|8",
	},
}
qcFlaggedButSeen = {
	[1234] = {
		["how"] = "accepted",
		["time"] = 1791388314,
		["build"] = 120100,
	},
}
qcSettings = {
	["QC_RECORD_GIVERS"] = 1,
}
]]

do
	local lines, err = reader.readFile(write(recorder), "p01")
	check(lines ~= nil, "a file the game wrote is read (" .. tostring(err) .. ")")
	if lines then
		local file = lines[1]
		equal(file[1] .. "|" .. file[2] .. "|" .. file[3] .. "|" .. file[4] .. "|" .. file[5], "file|p01|recorder|1|retail", "the header names the tag, kind, schema and game")
		equal(file[7], 0, "no odd records")
		local count = kinds(lines)
		equal(count.giver, 3, "three givers")
		equal(count.spot, 4, "four spots")
		equal(count.offer, 3, "three offers")
		equal(count.turnin, 2, "two turn-ins")
		equal(count.quest, 3, "three quests")
		equal(count.start, 2, "two starts")
		equal(count.build, 2, "two builds")
		equal(count.diag, 2, "two counters")
		equal(count.flagged, 1, "one flagged quest")
		check(find(lines, "giver", "Creature", 3701, "Guard Roberts", 69933, 0), "the giver's name and build")
		check(find(lines, "spot", "Creature", 3701, 84, 45.3, 67.8, 3, 69933), "a spot with its visits")
		check(find(lines, "spot", "Creature", 42, 84, -1, -1, 1, 69933), "a spot with no position")
		check(find(lines, "giver", "GameObject", 175320, "WANTED: Murkdeep!"), "an object giver")
		check(find(lines, "giver", "Creature", 42, ""), "a giver with no name")
		check(find(lines, "quest", 100, 69933, "", "", 0, 1, 1, 8, 1024, "Teldrassil"), "a quest with no recurrence known")
		check(find(lines, "quest", 101, 69933, 1, 1, 0, 1, 3, 40, 1, ""), "a daily repeatable quest with its masks")
		check(find(lines, "quest", 103, 69933, "", "", 1, 0, 2, 2, 4, "Durotar"), "an accepted quest")
		check(find(lines, "start", 800, 1, 5555, 84, 45.3, 67.8, 69933), "an item start")
		check(find(lines, "start", 801, 2, 0, 84, -1, -1, 69933), "a trigger start")
		check(find(lines, "flagged", 1234, "accepted", 120100), "a flagged quest without its time")
		for _, fields in ipairs(lines) do
			for _, value in ipairs(fields) do
				check(not tostring(value):find("[\t\r\n]"), "no field holds a tab or a newline")
			end
		end
	end
end

-- Records of the wrong shape are counted, not trusted.
do
	local lines = reader.readFile(write([[
qcQuestRecorder = {
	["v"] = 1,
	["bv"] = {[69933] = "12.1.0"},
	["g"] = {
		["Creature:1"] = "Fine|69933|1|84 1.0 2.0 1|5||0",
		["Creature:2"] = "Too few|69933",
		["Creature:abc"] = "x|69933|1||||0",
		["Player:3"] = "x|69933|1||||0",
		["Creature:4"] = "Bad spot|69933|1|84 150.0 2.0 1|||0",
		["Creature:5"] = "Bad list|69933|1||1,x||0",
		["Creature:6"] = "Bad build|x|1||||0",
		["Creature:99999999"] = "Big id|69933|1||||0",
		["Creature:7"] = 5,
		["Creature:8"] = "A very long name that goes on and on and on and on and on and on and on and on|69933|1||1||0",
		["Creature:9"] = "Tab" .. "|69933|1||1||0",
	},
	["q"] = {[0] = "69933|1|32|1|1|1|", [5] = "69933|1|32|1|1|1", [6] = "69933|1|200|1|1|1|", [7] = "69933|1|32|9|1|1|"},
}
]]), "p")
	-- the concatenation above makes the file refuse; see below. This block only runs if it didn't.
	check(lines == nil, "a concatenation refuses the whole file")
end

do
	local lines = reader.readFile(write([[
qcQuestRecorder = {
	["v"] = 1,
	["bv"] = {[69933] = "12.1.0"},
	["g"] = {
		["Creature:1"] = "Fine|69933|1|84 1.0 2.0 1|5||0",
		["Creature:2"] = "Too few|69933",
		["Creature:abc"] = "x|69933|1||||0",
		["Player:3"] = "x|69933|1||||0",
		["Creature:4"] = "Bad spot|69933|1|84 150.0 2.0 1|||0",
		["Creature:5"] = "Bad list|69933|1||1,x||0",
		["Creature:6"] = "Bad build|x|1||||0",
		["Creature:99999999"] = "Big id|69933|1||||0",
		["Creature:7"] = 5,
		["Creature:8"] = "A very long name that goes on and on and on and on and on and on and on and on|69933|1||1||0",
	},
	["q"] = {[0] = "69933|1|32|1|1|1|", [5] = "69933|1|32|1|1|1", [6] = "69933|1|200|1|1|1|", [7] = "69933|1|32|9|1|1|"},
	["s"] = {[3] = "3|0|84|1|1|69933|1", [4] = "1|0|84|101|1|69933|1"},
}
]]), "p")
	check(lines ~= nil, "a file with odd records is still read")
	if lines then
		local count = kinds(lines)
		equal(count.giver, 2, "only the sound givers (the fine one and the one with a long name)")
		equal(count.bad, 14, "fourteen odd records counted: 8 givers, 4 quests and 2 starts")
		check(find(lines, "giver", "Creature", 8, ""), "a name over 64 characters is dropped, the giver kept")
		equal(lines[1][7], count.bad, "the header says how many")
	end
end

-- The Forever probe's file.
do
	local lines, err = reader.readFile(write([[
QCForeverProbeDB = {
	["recording"] = true,
	["givers"] = {
		["Creature:3595"] = {
			["kind"] = "Creature", ["id"] = 3595, ["name"] = "Shanda", ["build"] = "1.60.1.70245",
			["spots"] = {["1438 56.3 59.9"] = 4, ["1438 10.0 20.0"] = 1},
			["offers"] = {[97979] = {["frequency"] = 2, ["repeatable"] = false, ["lowestPlayerLevel"] = 1}, [5] = {}},
			["turnIns"] = {[97979] = true},
		},
		["Vehicle:9"] = {["kind"] = "Vehicle", ["id"] = 9, ["build"] = "1.60.1.70245"},
		["Creature:bad"] = {["kind"] = "Creature", ["id"] = "x", ["build"] = "1.60.1.70245"},
	},
	["accepted"] = {[97979] = {["build"] = "1.60.1.70245", ["heading"] = "Teldrassil", ["map"] = 1438, ["x"] = 56.3, ["y"] = 59.9}},
	["started"] = {[8000] = {["build"] = "1.60.1.70245", ["item"] = 6000, ["map"] = 1438, ["x"] = 1.5, ["y"] = 2.5}},
	["quests"] = {[1] = {["build"] = "1.60.1.70245", ["result"] = "x"}},
}
]]), "own")
	check(lines ~= nil, "the probe's file is read (" .. tostring(err) .. ")")
	if lines then
		equal(lines[1][3] .. "|" .. lines[1][5], "probe|forever", "its header says probe and Forever")
		check(find(lines, "build", 70245, "1.60.1"), "its build and version")
		check(find(lines, "giver", "Creature", 3595, "Shanda", 70245, 0), "its giver")
		check(find(lines, "spot", "Creature", 3595, 1438, 56.3, 59.9, 4, 70245), "its spot")
		check(find(lines, "quest", 97979, 70245, 2, 0, 0, 1), "its offer's frequency and repeatable")
		check(find(lines, "quest", 97979, 70245, "", "", 1, 0, 0, 0, 0, "Teldrassil"), "its accepted heading")
		check(find(lines, "start", 8000, 0, 6000, 1438, 1.5, 2.5, 70245), "its start, of unknown kind")
		equal(kinds(lines).bad, 1, "its giver with an ID of text is counted")
	end
end

-- What is refused.
refused("", "empty", "an empty file")
refused("nothing here", nil, "text that isn't Lua")
refused("x = 1\n", "no qcQuestRecorder", "another variable")
refused("qcQuestRecorder = {v = 2}\n", "schema 2", "a newer schema")
refused("qcQuestRecorder = {v = 1", nil, "a table left open")
refused("qcQuestRecorder = {v = 1}}", nil, "a table closed twice")
refused("qcQuestRecorder = {v = 1, g = os.execute(\"echo hi\")}\n", nil, "a call")
refused("os.execute(\"echo hi\")\n", nil, "a call on its own line")
refused("while true do end\n", nil, "a loop")
refused("qcQuestRecorder = {v = 1}\nwhile true do end\n", nil, "a loop after good data")
refused("x = (\"x\"):rep(1e9)\n", nil, "a string method")
refused("x = io.open(\"a\")\n", nil, "a file call")
refused("qcQuestRecorder = {v = 1, g = \"a\" .. \"b\"}\n", nil, "a concatenation")
refused("qcQuestRecorder = {v = 1 + 1}\n", nil, "arithmetic")
refused("qcQuestRecorder = {v = -(1)}\n", nil, "a negated bracket")
refused("qcQuestRecorder = {v = y}\n", nil, "a name used as a value")
refused("qcQuestRecorder = {v = function() end}\n", nil, "a function")
refused("local qcQuestRecorder = {v = 1}\n", nil, "a local")
refused("qcQuestRecorder = {v = 1, [1+1] = 2}\n", nil, "a computed key")
refused("qcQuestRecorder = {v = 1, [{}] = 2}\n", "a key that isn't", "a table as a key")
refused("qcQuestRecorder = {v = 1, g = [[long]]}\n", "a long string", "a long string")
refused("qcQuestRecorder = {v = 1, g = [=[long]=]}\n", "a long string", "a long string with levels")
refused("--[[ comment ]] qcQuestRecorder = {v = 1}\n", "a long comment", "a long comment")
refused("qcQuestRecorder = {v = 1, g = ...}\n", nil, "varargs")
refused("qcQuestRecorder = {v = 1}; qcQuestRecorder.v = 2\n", nil, "a field assignment")
refused("qcQuestRecorder = {v = 1 == 1}\n", nil, "a comparison")
refused("qcQuestRecorder = {v = -1.#IND}\n", "a number followed", "a number the game can't write")
refused("qcQuestRecorder = {v = 1.#INF}\n", "a number followed", "an infinite number")
refused("qcQuestRecorder = {v = nan}\n", nil, "nan")
refused("qcQuestRecorder = {v = \"unfinished}\n", nil, "an unfinished string")
refused("qcQuestRecorder = {v = \"two\nlines\"}\n", "across lines", "a string across lines")
refused("qcQuestRecorder = {v = 0x}\n", nil, "a bad hex number")
refused(string.dump(function() end), nil, "precompiled code")
refused("\27Lua" .. string.rep("x", 100), nil, "precompiled code with a header")
refused(("qcQuestRecorder = " .. ("{"):rep(40) .. ("}"):rep(40) .. "\n"), "too deep", "tables nested too deep")
refused("qcQuestRecorder = {" .. string.rep("{}, ", 10) .. string.rep("x", 9 * 1024 * 1024) .. "}", "larger than 8 MB", "a file over 8 MB")
refused("\0\1\2\3\4", nil, "binary rubbish")
refused("qcQuestRecorder = {v = 1}\n$(rm -rf)", nil, "shell-looking text")
refused("qcQuestRecorder = {v = 1} @", nil, "a stray character")

-- What is let through, though it looks odd.
do
	local function readable(text, message)
		local lines, err = reader.readFile(write(text), "t")
		check(lines ~= nil, message .. " (" .. tostring(err) .. ")")
		return lines
	end
	readable("\239\187\191qcQuestRecorder = {v = 1, bv = {}}\n", "a file with a byte order mark")
	readable("qcQuestRecorder = {v = 1, bv = {}} -- a comment\r\n", "a comment and CRLF")
	readable("qcQuestRecorder = {\n[\"v\"] = 1, -- [1]\n[\"x\"] = {1, 2.5, -3, 1e+100, 0x10, true, false, nil,},\n}\n", "numbers and literals")
	readable("qcQuestRecorder = {v = 1; bv = {};};\nqcSettings = {};\n", "semicolons")
	readable("qcQuestRecorder = {v = 1, bv = {}, note = 'single \\' quoted \\\\ \"x\"'}\n", "single quotes and escapes")
	readable("qcQuestRecorder = {v = 1, g = {[\"Creature:1\"] = \"\\195\\169|69933|1||||0\"}, bv = {[69933] = \"12.1.0\"}}\n", "escaped bytes")
	local deep = ("{"):rep(20) .. ("}"):rep(20)
	readable("qcQuestRecorder = {v = 1, bv = {}, deep = " .. deep .. "}\n", "tables 20 deep")
end

-- A name with a control character is dropped.
do
	local lines = reader.readFile(write([[
qcQuestRecorder = {v = 1, bv = {[69933] = "12.1.0"}, g = {["Creature:1"] = "Tab\tName|69933|1||1||0"}}
]]), "t")
	if check(lines ~= nil, "a name with a tab is read") and lines then end
	check(lines and find(lines, "giver", "Creature", 1, ""), "and the name is dropped")
end

-- The command line: the exit code and what is printed.
do
	local good = write(recorder)
	local bad = write("os.execute('echo hi')\n")
	local out = write("")
	local function run(arguments) return os.execute('""' .. lua .. '" tools/Read-RecordedGivers.lua ' .. arguments .. ' > "' .. out .. '" 2>&1"') end
	local status = run('"' .. good .. '" p01')
	equal(status, 0, "a good file exits 0")
	local f = io.open(out, "rb"); local text = f:read("*a"); f:close()
	check(text:find("^file\tp01\trecorder\t1\tretail"), "and prints its lines")
	status = run('"' .. bad .. '" p01')
	equal(status, 2, "a refused file exits 2")
	f = io.open(out, "rb"); text = f:read("*a"); f:close()
	check(text:find("^refused\t"), "and says why, as its only output")
	check(not text:find("\n[a-z]+\t"), "and prints no data lines")
	status = run('')
	equal(status, 2, "no file name exits 2")
	status = run('"' .. good .. '.missing"')
	equal(status, 2, "a missing file exits 2")
end

-- What the review of 9 October 2026 found: a bare CR ends a Lua 5.1 line comment, builds and positions
-- print in forms PowerShell can't read, no cap on what a file may hold, and what a spreadsheet takes for a formula.
do
	refused("qcQuestRecorder = {v = 1} -- x\rfor i = 1, 10 do end\n", "without a value", "code after a comment that ends with a bare CR")
	refused("qcQuestRecorder = {v = 1, bv = {}} -- x\rwhile true do end\n", nil, "a loop after a comment ended by a bare CR")
	refused("qcQuestRecorder = {v = 1, bv = {}} -- x\rqcQuestRecorder.g = {}\n", nil, "an assignment after a bare CR")
	local function readable(text, message)
		local lines, err = reader.readFile(write(text), "t")
		check(lines ~= nil, message .. " (" .. tostring(err) .. ")")
		return lines
	end
	readable("qcQuestRecorder = {v = 1, bv = {}} -- a comment\rqcSettings = {}\n", "a bare CR after a comment, then plain data")

	-- A build that is not a number the tool can use.
	local function probe(build, extra)
		return reader.readFile(write(string.format([[
QCForeverProbeDB = {
	["givers"] = {
		["Creature:1"] = {["kind"] = "Creature", ["id"] = 1, ["name"] = "Bob", ["build"] = %q, ["spots"] = {["1438 %s 59.9"] = 1}},
	},
}
]], build, extra or "56.3")), "t")
	end
	local lines = probe("1.60.1.99999999999")
	check(lines ~= nil and not find(lines, "build"), "a probe build over a billion is no build")
	check(lines ~= nil and kinds(lines).bad == 1, "and the giver with it is odd")
	lines = probe("1.60.1.1234567890123456")
	check(lines ~= nil and not find(lines, "giver"), "a 16-digit build gives no giver")
	lines = probe("1.60.1.70245", "0.00001")
	check(lines ~= nil and find(lines, "spot", "Creature", 1, 1438, 0, 59.9, 1, 70245), "a position that would print as 1e-005 is 0")
	lines = probe("1.60.1.70245", "-0")
	check(lines ~= nil and find(lines, "spot", "Creature", 1, 1438, 0, 59.9, 1, 70245), "and so is -0")
	for _, fields in ipairs(lines or {}) do
		for _, value in ipairs(fields) do check(not tostring(value):find("e[+-]"), "no number prints in exponent notation") end
	end

	-- A recorder file with exponents in a position.
	lines = reader.readFile(write([[
qcQuestRecorder = {v = 1, bv = {[69933] = "12.1.0"}, g = {["Creature:1"] = "Bob|69933|1|84 0.00001 5.0 3;84 -0 5 1||1|0"}}
]]), "t")
	check(lines ~= nil and find(lines, "spot", "Creature", 1, 84, 0, 5, 3, 69933), "a recorder position that would print as 1e-005 is 0")
	check(lines ~= nil and find(lines, "spot", "Creature", 1, 84, 0, 5, 1, 69933), "-0 is the same place as 0")

	-- What the addon cannot write is refused or odd.
	local many = {}
	for i = 1, 61 do many[#many + 1] = tostring(i) end
	lines = reader.readFile(write("qcQuestRecorder = {v = 1, bv = {[69933] = \"12.1.0\"}, g = {[\"Creature:1\"] = \"Bob|69933|1|84 1.0 2.0 1|" .. table.concat(many, ",") .. "||0\"}}\n"), "t")
	check(lines ~= nil and kinds(lines).bad == 1 and not find(lines, "giver"), "a giver with 61 offers is odd")
	lines = reader.readFile(write("qcQuestRecorder = {v = 1, bv = {[69933] = \"12.1.0\"}, g = {[\"Creature:1\"] = \"Bob|69933|1|84 1.0 2.0 1;84 5.0 5.0 1;84 9.0 9.0 1;84 13.0 13.0 1;84 17.0 17.0 1||1|0\"}}\n"), "t")
	check(lines ~= nil and kinds(lines).bad == 1, "and a giver with five spots")
	local function giverText(n)
		local records = {}
		for i = 1, n do records[#records + 1] = string.format("[\"Creature:%d\"] = \"Bob|69933|1||1||0\",", i) end
		return "qcQuestRecorder = {v = 1, bv = {[69933] = \"12.1.0\"}, g = {" .. table.concat(records) .. "}}\n"
	end
	local function questText(n)
		local records = {}
		for i = 1, n do records[#records + 1] = string.format("[%d] = \"69933|1|32|1|1|1|\",", i) end
		return "qcQuestRecorder = {v = 1, bv = {[69933] = \"12.1.0\"}, q = {" .. table.concat(records) .. "}}\n"
	end
	local function startText(n)
		local records = {}
		for i = 1, n do records[#records + 1] = string.format("[%d] = \"1|5|84|1.0|2.0|69933|1\",", i) end
		return "qcQuestRecorder = {v = 1, bv = {[69933] = \"12.1.0\"}, s = {" .. table.concat(records) .. "}}\n"
	end
	lines = reader.readFile(write(giverText(5000)), "t")
	check(lines ~= nil and kinds(lines).giver == 5000, "a file with 5,000 givers, the addon's cap, is read")
	refused(giverText(5001), "more records than the addon keeps", "a file with 5,001 givers")
	lines = reader.readFile(write(questText(10000)), "t")
	check(lines ~= nil and kinds(lines).quest == 10000, "a file with 10,000 quests is read")
	refused(questText(10001), "more records than the addon keeps", "a file with 10,001 quests")
	lines = reader.readFile(write(startText(4000)), "t")
	check(lines ~= nil and kinds(lines).start == 4000, "a file with 4,000 starts is read")
	refused(startText(4001), "more records than the addon keeps", "a file with 4,001 starts")

	-- A name or heading a spreadsheet would run, or that carries the field separator.
	for _, bad in ipairs({"=HYPERLINK(1)", "+1+1", "@SUM(1)", "-1+1", "a|b", "|cffff0000Free Gold|r"}) do
		local text = string.format("QCForeverProbeDB = {givers = {[\"Creature:1\"] = {kind = \"Creature\", id = 1, name = %q, build = \"1.60.1.70245\"}}, accepted = {[5] = {build = \"1.60.1.70245\", heading = %q}}}\n", bad, bad)
		lines = reader.readFile(write(text), "t")
		check(lines ~= nil and find(lines, "giver", "Creature", 1, ""), "a probe name " .. bad .. " is dropped")
		check(lines ~= nil and find(lines, "quest", 5, 70245, "", "", 1, 0, 0, 0, 0, ""), "and so is the heading")
	end
	for _, bad in ipairs({"=1", "+1", "@x", "-x", "a|b"}) do
		lines = reader.readFile(write("qcQuestRecorder = {v = 1, bv = {[69933] = \"12.1.0\"}, g = {[\"Creature:1\"] = \"" .. bad:gsub("|", "\\124") .. "|69933|1||1||0\"}, q = {[5] = \"69933|1|16|0|0|0|" .. bad:gsub("|", "\\124") .. "\"}}\n"), "t")
		check(lines ~= nil and find(lines, "giver", "Creature", 1, "") or (lines ~= nil and kinds(lines).bad >= 1), "a recorder name " .. bad .. " is dropped or odd")
	end
	lines = reader.readFile(write("qcQuestRecorder = {v = 1, bv = {[69933] = \"12.1.0\"}, g = {[\"Creature:1\"] = \"Dash-Name|69933|1||1||0\", [\"Creature:2\"] = \"Don't|69933|1||1||0\"}}\n"), "t")
	check(lines ~= nil and find(lines, "giver", "Creature", 1, "Dash-Name") and find(lines, "giver", "Creature", 2, "Don't"), "an ordinary name with a dash or an apostrophe stays")

	-- A directory, a missing file and a file too big to read are refused, not crashed on.
	local lines2, err = reader.readFile(".", "t")
	check(lines2 == nil, "a directory is refused (" .. tostring(err) .. ")")
end

-- The real probe file from the Forever beta, if it's here.
do
	local f = io.open("tools/forever_probe_70245/QCForeverProbe.lua", "rb")
	if f then
		f:close()
		local lines, err = reader.readFile("tools/forever_probe_70245/QCForeverProbe.lua", "own")
		check(lines ~= nil, "the beta's file is read (" .. tostring(err) .. ")")
		if lines then
			local count = kinds(lines)
			equal(count.giver, 18, "18 givers")
			equal(count.offer, 20, "20 offers")
			equal(count.turnin, 6, "6 turn-ins")
			equal(count.spot, 18, "18 spots")
			equal(count.bad or 0, 0, "nothing odd")
		end
	end
end

-- Further checks of the reader: its ranges, caps, tokenizer corners and what it does with a probe's file.
local function addResults(p, f) passed = passed + p; failed = failed + f end
do
local passed, failed = 0, 0
local function check(condition, message)
	if condition then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end
local function equal(actual, expected, message)
	check(actual == expected, message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

local files = {}
local function write(text)
	local path = os.tmpname()
	files[#files + 1] = path
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
	return path
end
-- A hostile file that hangs must fail the test, not stop it: an instruction budget turns a loop into an error.
local function read(text)
	local path = write(text)
	debug.sethook(function() error("the reader ran for too long", 0) end, "", 5000000)
	local ok, lines, err = pcall(reader.readFile, path, "t")
	debug.sethook()
	if not ok then return nil, "HANG: " .. tostring(lines) end
	return lines, err
end
local function counts(lines)
	local c = {}
	for _, fields in ipairs(lines) do c[fields[1]] = (c[fields[1]] or 0) + 1 end
	return c
end
local function find(lines, kind, ...)
	local want = {...}
	for _, fields in ipairs(lines) do
		if fields[1] == kind then
			local ok = true
			for i, value in ipairs(want) do if tostring(fields[i + 1]) ~= tostring(value) then ok = false end end
			if ok then return fields end
		end
	end
end
-- A file with one record of a kind in an otherwise sound recorder table.
local function recorder(g, q, s, bv)
	return 'qcQuestRecorder = {["v"] = 1, ["bv"] = ' .. (bv or '{[69933] = "12.1.0"}') .. ', ["g"] = {' .. (g or '') .. '}, ["q"] = {' .. (q or '') .. '}, ["s"] = {' .. (s or '') .. '}}\n'
end
local function odd(g, q, s) local lines = read(recorder(g, q, s)); return lines and counts(lines).bad or "refused" end
local function good(g, q, s) local lines = read(recorder(g, q, s)); return lines and (counts(lines).bad or 0) == 0 end

-- Hostile files must be refused by the checker itself, not merely fail to run in the empty sandbox: with
-- the checker off, a call fails in the sandbox ("attempt to index global 'os'") and still reads as refused.
local function byChecker(text, message)
	local lines, err = read(text)
	check(lines == nil and err and err:find("not plain saved variables", 1, true) ~= nil, message .. ": refused by the checker (got " .. tostring(err) .. ")")
end
byChecker("qcQuestRecorder = {v = 1, g = os.execute(\"echo hi\")}\n", "a call")
byChecker("qcQuestRecorder = {v = 1 + 1}\n", "arithmetic")
byChecker("qcQuestRecorder = {v = 1, g = \"a\" .. \"b\"}\n", "a concatenation")
byChecker("qcQuestRecorder = {v = 1}\nwhile true do end\n", "a loop after good data")
byChecker("x = (\"x\"):rep(1e9)\n", "a string method")
byChecker("qcQuestRecorder = {v = 1}; qcQuestRecorder.v = 2\n", "a field assignment")
byChecker("qcQuestRecorder = {v = 1}\nx == 1\n", "a comparison statement")
check(select(2, read("qcQuestRecorder = {v = 1}\nx == 1\n")):find("an operator", 1, true), "== says an operator")
check(select(2, read("qcQuestRecorder = {v = 1, x = {y}}\n")):find("used as a value", 1, true), "a name inside a table is not a value")

-- The sandbox: a file may not touch the reader's own globals.
do
	local before = math.floor
	local lines = read('qcQuestRecorder = {v = 1, bv = {}}\nmath = 1\nstring = 2\ntostring = 3\n')
	check(type(math) == "table" and math.floor == before and type(string) == "table" and type(tostring) == "function", "a file's assignments stay out of the reader's globals")
end

-- Depth: 24 nested tables pass, 25 do not.
local function nested(n) return "qcQuestRecorder = " .. ("{x="):rep(n - 1) .. "{}" .. ("}"):rep(n - 1) .. "\n" end
check(((select(2, read(nested(25)))) or ""):find("too deep", 1, true) ~= nil, "25 nested tables are too deep")
check(not (select(2, read(nested(24))) or ""):find("too deep", 1, true), "24 nested tables are not refused as too deep")

-- Whole numbers and ranges.
check(good('["Creature:5"] = "n|69933|1||1,2||0"'), "a sound giver")
equal(odd('["Creature:5"] = "n|69933|1||1.5||0"'), 1, "a quest ID with a fraction is odd")
equal(odd('["Creature:5"] = "n|69933|1||1,2||8"'), 1, "giver flags over 7 are odd")
equal(odd('["Creature:5"] = "n|69933|1|||5,x|0"'), 1, "a turn-in list with text is odd")
equal(odd('["Creature:5"] = "n|0|1||||0"'), 1, "build 0 is odd")
equal(odd('["Creature:5"] = "n|69933|1||||0|extra"'), 1, "a giver with eight fields is odd")
equal(odd('["Creature:5x"] = "n|69933|1||||0"'), 1, "an ID with trailing text is odd")
equal(odd('["Creature:0"] = "n|69933|1||||0"'), 1, "ID 0 is odd")
check(good('["Vehicle:5"] = "n|69933|1||||0"'), "a vehicle giver is read")
check(good('["GameObject:5"] = "n|69933|1||||0"'), "an object giver is read")
-- spots
check(good('["Creature:5"] = "n|69933|1|84 0.0 0.0 1;84 100.0 100.0 999;84 -1 -1 1|||0"'), "0, 100 and -1 are coordinates, 999 visits is fine")
equal(odd('["Creature:5"] = "n|69933|1|84 -0.5 5.0 1|||0"'), 1, "-0.5 is not a coordinate")
equal(odd('["Creature:5"] = "n|69933|1|84 100.5 5.0 1|||0"'), 1, "100.5 is not a coordinate")
equal(odd('["Creature:5"] = "n|69933|1|84 5.0 5.0 0|||0"'), 1, "0 visits is odd")
equal(odd('["Creature:5"] = "n|69933|1|84 5.0 5.0 1000|||0"'), 1, "1000 visits is odd")
equal(odd('["Creature:5"] = "n|69933|1|84 5.0 5.0 1 junk|||0"'), 1, "text after a spot is odd")
equal(odd('["Creature:5"] = "n|69933|1|x84 5.0 5.0 1|||0"'), 1, "text before a spot is odd")
equal(odd('["Creature:5"] = "n|69933|1|0 5.0 5.0 1|||0"'), 1, "map 0 is odd for a spot")
-- quests
check(good(nil, '[5] = "69933|1|96|1|2147483648|8191|"'), "race 2^31 is read")
equal(odd(nil, '[5] = "69933|1|96|1|2147483649|8191|"'), 1, "a race above 2^31 is odd")
equal(odd(nil, '[5] = "69933|1|96|1|-1|8191|"'), 1, "a negative race is odd")
equal(odd(nil, '[5] = "69933|1|96|1|1|99999999999999|"'), 1, "an enormous class is odd")
equal(odd(nil, '[5] = "69933|1|128|1|1|1|"'), 1, "quest flags over 127 are odd")
do
	local function q(flags) local lines = read(recorder(nil, '[5] = "69933|1|' .. flags .. '|0|0|0|"')); return find(lines, "quest", 5) end
	local f = q(1);  equal(f[4] .. "/" .. f[5], "0/", "known frequency 0, repeatability unknown")
	f = q(7);        equal(f[4], 3, "frequency 3")
	f = q(5);        equal(f[4], 2, "frequency 2")
	f = q(96);       equal(f[4] .. "/" .. f[5], "/0", "repeatability known and not repeatable")
	f = q(104);      equal(f[5], 1, "known and repeatable")
end
-- starts
check(good(nil, nil, '[5] = "1|0|0|-1|-1|69933|3"'), "a start on no map is read")
equal(odd(nil, nil, '[5] = "0|0|84|1|1|69933|3"'), 1, "a start of kind 0 is odd in the recorder's file")
equal(odd(nil, nil, '[5] = "1|-5|84|1|1|69933|3"'), 1, "a negative item is odd")
equal(odd(nil, nil, '[5] = "1|10000000000|84|1|1|69933|3"'), 1, "an enormous item is odd")
-- builds
do
	local lines = read(recorder(nil, nil, nil, '{[69933] = "12.1.0", [1] = "a version string over twenty characters long", [2] = "12.\t1"}'))
	equal(counts(lines).build, 1, "a build with a long or control-character version is left out")
end
check(counts(read(recorder(nil, nil, nil, '{[0] = "12.1.0", [1.5] = "12.1.0"}'))).build == nil, "a build number must be a whole number of at least 1")
-- the file header and flagged quests
do
	local lines = read(recorder(nil, nil, nil, '{[69933] = "12.1.0", [70245] = "1.60.1"}'))
	equal(lines[1][5], "mixed", "retail and Forever builds in one file are 'mixed'")
	lines = read(recorder() .. 'qcFlaggedButSeen = {[5] = {how = "turned in"}, [6] = {how = "accepted"}, [7] = {how = "other"}}\n')
	equal(counts(lines).flagged, 2, "flagged: accepted and turned in count, anything else does not")
end
-- diag counters
do
	local lines = read('qcQuestRecorder = {v = 1, bv = {}, d = {["ok"] = 5, ["neg"] = -5, ["huge"] = 2000000000, ["tab\\tkey"] = 1, ["frac"] = 0.5}}\n')
	equal(counts(lines).diag, 1, "only a counter that is a whole number from 0 to a billion, under a clean key, is kept")
end
-- the probe's file
do
	local lines = read('QCForeverProbeDB = {givers = {["Creature:1"] = {kind = "Creature", id = 1, build = "1.60.1.70245", spots = {["1438 5.0 5.0"] = 5000, ["1438 -5.0 5.0"] = 3}, offers = {[7] = {frequency = 7}, [8] = {frequency = 2}}}}, started = {[9] = {build = "1.60.1.70245", map = 0, x = 5, y = 5}}}\n')
	check(find(lines, "spot", "Creature", 1, 1438, 5, 5, 999, 70245), "a probe spot's visits are capped at 999")
	equal(counts(lines).spot, 1, "a probe spot with a negative coordinate is dropped")
	check(find(lines, "quest", 8, 70245, 2) and not find(lines, "quest", 7), "an offer with a frequency of 7 says nothing about frequency")
	check(find(lines, "start", 9, 0, 0, 0, -1, -1, 70245), "a probe start without a map has no position")
end

for _, path in ipairs(files) do os.remove(path) end
addResults(passed, failed)
end

for _, path in ipairs(files) do os.remove(path) end
print(string.format("%d checks passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
