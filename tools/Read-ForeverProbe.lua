-- Prints the probe's saved variables (QCForeverProbe.lua) as tab-separated lines for
-- Import-ForeverData.ps1 and ProbeResults.ps1. usage: lua Read-ForeverProbe.lua <QCForeverProbe.lua> [facts]
--   quest    id  build  result  classification
--   fact     id  name  value                     (only with "facts": every other field of a quest's row)
--   npc      id  build  result  name
--   spot     kind  id  name  "map x y"  times seen
--   offer    kind  id  questId
--   turnin   kind  id  questId
--   accepted questId  heading  map  x  y
--   started  questId  item  map  x  y
--   run          n  kind  build  time  character  level  answered  asked          (only with "facts")
--   refusedfact  n  function  asked  answered  positive  examples                 (only with "facts": the n-th run's
--                                                                                  tally of what a function says for refused quests)
dofile(arg[1])
local db = QCForeverProbeDB or error("no QCForeverProbeDB in " .. arg[1])

local function clean(value)
	return (tostring(value == nil and "" or value):gsub("[\t\r\n]", " "))
end

local function line(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = clean((select(i, ...))) end
	io.write(table.concat(parts, "\t"), "\n")
end

local function keys(t)
	local list = {}
	for key in pairs(t or {}) do list[#list + 1] = key end
	table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
	return list
end

for _, id in ipairs(keys(db.quests)) do
	local quest = db.quests[id]
	line("quest", id, quest.build, quest.result, quest.classification)
	if arg[2] == "facts" then
		for _, name in ipairs(keys(quest)) do
			if name ~= "build" and name ~= "result" then line("fact", id, name, quest[name]) end
		end
	end
end
for _, id in ipairs(keys(db.npcs)) do
	local npc = db.npcs[id]
	line("npc", id, npc.build, npc.result, npc.name)
end
for _, key in ipairs(keys(db.givers)) do
	local giver = db.givers[key]
	for _, spot in ipairs(keys(giver.spots)) do line("spot", giver.kind, giver.id, giver.name, spot, giver.spots[spot]) end
	for _, questId in ipairs(keys(giver.offers)) do line("offer", giver.kind, giver.id, questId) end
	for _, questId in ipairs(keys(giver.turnIns)) do line("turnin", giver.kind, giver.id, questId) end
end
for _, id in ipairs(keys(db.accepted)) do
	local accepted = db.accepted[id]
	line("accepted", id, accepted.heading, accepted.map, accepted.x, accepted.y)
end
for _, id in ipairs(keys(db.started)) do
	local started = db.started[id]
	line("started", id, started.item, started.map, started.x, started.y)
end
if arg[2] == "facts" then
	for i, run in ipairs(db.runs or {}) do
		line("run", i, run.kind, run.build, run.time, run.character, run.level, run.answered, run.asked)
		for _, key in ipairs(keys(run.refusedFacts)) do
			local tally = run.refusedFacts[key]
			line("refusedfact", i, key, tally.asked, tally.answered, tally.positive, table.concat(tally.examples or {}, ","))
		end
	end
end
