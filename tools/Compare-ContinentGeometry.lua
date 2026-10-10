-- Compares what the probe's geometry pass gathered (docs/plans/continent-pins.md) with the baseline kept in
-- docs/plans/continent-geometry-baseline.csv, so a sweep notices a zone that moved, appeared or went on a
-- continent map, a map whose type, flags, group or nav-bar listing changed, or one the game's hit test now
-- names differently or over other cells. A change in a zone's place is a prompt to look at the zone icons (and
-- at the rows of QC_ZONE_ICON_AT in qcContinentPins.lua, which are read from the hit cells' centres), not a
-- failure of the addon: it reads the places from the game each time.
-- usage: lua tools/Compare-ContinentGeometry.lua <QCForeverProbe.lua> <baseline.csv> [--update] [build]
--   Compares the game the file is from (its build, or the one given) with that game's rows in the baseline.
--   Exit 0: the same. Exit 1: something differs, or the baseline has no rows for the game. Exit 2: no geometry.
--   --update replaces that game's rows in the baseline with the file's, keeping the other game's, and exits 0;
--   run it after reading the differences. The rows are those of tools/Report-ContinentGeometry.lua.
-- Under Lua 5.1: & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Compare-ContinentGeometry.lua <file> <baseline.csv>

local TOLERANCE = 0.0005
local CENTROID_POINTS = 1
local CELLS_SHARE = 0.15
local FIELDS = {"name", "mapType", "flags", "navBar", "group", "hitId"}

local here = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local report, parseCsv, recordLine, HEADER = assert(loadfile(here .. "/Report-ContinentGeometry.lua"))("module")

local function key(r) return r.game .. "|" .. r.continent .. "|" .. r.mapId end

local function describe(r)
	return string.format("%s (%d): %s (%d)", r.continentName or "?", r.continent, r.name or "?", r.mapId)
end

local function rectText(rect)
	return rect and string.format("%.4f %.4f %.4f %.4f", rect[1], rect[2], rect[3], rect[4]) or "none"
end

local function rectsDiffer(a, b)
	if (a == nil) ~= (b == nil) then return true end
	if not a then return false end
	for i = 1, 4 do
		if math.abs(a[i] - b[i]) > TOLERANCE then return true end
	end
	return false
end

-- The cells of the probe's grid that the game's hit test names a map on: how many, and their centre in map
-- percent. It differs when the count changes by more than 15% (and 2 cells) or the centre moves over a point.
local function hitAreaDiffers(a, b)
	local was, now = a.cells or 0, b.cells or 0
	if math.abs(was - now) > math.max(2, was * CELLS_SHARE) then return true end
	if was > 0 and now > 0 and a.cx and a.cy and b.cx and b.cy then
		return math.abs(a.cx - b.cx) > CENTROID_POINTS or math.abs(a.cy - b.cy) > CENTROID_POINTS
	end
	return false
end

local function hitAreaText(r)
	if (r.cells or 0) == 0 then return "none" end
	return string.format("%d cells at %.1f, %.1f", r.cells, r.cx or 0, r.cy or 0)
end

-- What changed from the baseline's records to the current ones: the lines to print, and how many.
local function compare(current, baseline)
	local old, new = {}, {}
	for _, r in ipairs(baseline) do old[key(r)] = r end
	for _, r in ipairs(current) do new[key(r)] = r end
	local added, removed, changed = {}, {}, {}
	for k, r in pairs(new) do
		local o = old[k]
		if not o then
			added[#added + 1] = "added:   " .. describe(r) .. string.format(" (type %s)", tostring(r.mapType))
		else
			local diffs = {}
			for _, field in ipairs(FIELDS) do
				if o[field] ~= r[field] then diffs[#diffs + 1] = string.format("%s %s -> %s", field, tostring(o[field]), tostring(r[field])) end
			end
			if rectsDiffer(o.rect, r.rect) then diffs[#diffs + 1] = string.format("rectangle %s -> %s", rectText(o.rect), rectText(r.rect)) end
			if hitAreaDiffers(o, r) then diffs[#diffs + 1] = string.format("hit area %s -> %s", hitAreaText(o), hitAreaText(r)) end
			if #diffs > 0 then changed[#changed + 1] = "changed: " .. describe(r) .. ": " .. table.concat(diffs, "; ") end
		end
	end
	for k, o in pairs(old) do
		if not new[k] then removed[#removed + 1] = "removed: " .. describe(o) end
	end
	table.sort(added)
	table.sort(removed)
	table.sort(changed)
	local lines = {}
	for _, list in ipairs({added, removed, changed}) do
		for _, line in ipairs(list) do lines[#lines + 1] = line end
	end
	return lines
end

local function sortRecords(records)
	table.sort(records, function(a, b)
		if a.game ~= b.game then return a.game < b.game end
		if a.continent ~= b.continent then return a.continent < b.continent end
		return a.mapId < b.mapId
	end)
end

if (...) == "module" then return compare, sortRecords end

local savedFile, baselineFile = arg[1], arg[2]
local update, wanted = false, nil
for i = 3, #arg do
	if arg[i] == "--update" then update = true else wanted = arg[i] end
end
if not savedFile or not baselineFile then
	io.stderr:write("usage: lua tools/Compare-ContinentGeometry.lua <QCForeverProbe.lua> <baseline.csv> [--update] [build]\n")
	os.exit(2)
end
dofile(savedFile)
local db = QCForeverProbeDB or error("no QCForeverProbeDB in " .. savedFile)
local _, _, current = report(db, wanted)
if #current == 0 then
	print("No geometry in " .. savedFile .. ": type /qcprobe geometry in the game, log out fully and copy the file again.")
	os.exit(2)
end
local game, build = current[1].game, current[1].build

local kept, baselineOfGame = {}, {}
local handle = io.open(baselineFile, "rb")
if handle then
	for _, r in ipairs(parseCsv(handle:read("*a"))) do
		if r.game == game then baselineOfGame[#baselineOfGame + 1] = r else kept[#kept + 1] = r end
	end
	handle:close()
end

if update then
	if #current < #baselineOfGame then
		print(string.format("Warning: %d fewer %s rows than the baseline had (%d against %d): is the dump complete?",
			#baselineOfGame - #current, game, #current, #baselineOfGame))
	end
	for _, r in ipairs(current) do kept[#kept + 1] = r end
	sortRecords(kept)
	local out = assert(io.open(baselineFile, "wb"))
	out:write(HEADER, "\r\n")
	for _, r in ipairs(kept) do out:write(recordLine(r), "\r\n") end
	out:close()
	print(string.format("Baseline updated: %d %s rows of build %s (%d rows in all) in %s.", #current, game, build, #kept, baselineFile))
	os.exit(0)
end

if #baselineOfGame == 0 then
	print(string.format("Continent geometry on %s (%s): the baseline has no %s rows. Read the report, then run again with --update.", build, game, game))
	os.exit(1)
end
local lines = compare(current, baselineOfGame)
local baselineBuild = baselineOfGame[1].build
if #lines == 0 then
	print(string.format("Continent geometry on %s (%s): %d child maps, the same as the baseline of build %s.", build, game, #current, baselineBuild))
	os.exit(0)
end
print(string.format("Continent geometry on %s (%s): %d child maps against the baseline of build %s, %d differences:", build, game, #current, baselineBuild, #lines))
for _, line in ipairs(lines) do print("  " .. line) end
print("Look at the zone icons on the continents named above (docs/plans/continent-pins.md), then --update.")
os.exit(1)
