-- Reports what the probe's geometry pass gathered (/qcprobe geometry, or the end of /qcprobe maps;
-- docs/plans/continent-pins.md): for each continent, world and cosmic map, the child maps the game lists,
-- where each sits on it, what the game's hit test names at each centre and over a grid, and which
-- zone icons would crowd each other.
-- usage: lua tools/Report-ContinentGeometry.lua <QCForeverProbe.lua> [rows.csv] [build]
--   rows.csv   one row per child map: Game, Build, Continent, ContinentName, MapID, Name, MapType, Flags,
--              NavBar, Group, MinX, MaxX, MinY, MaxY, HitID, HitName, Cells, CentroidX, CentroidY
--   build      which build's rows to read; the one with most maps in the file when left out
-- Under Lua 5.1: & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Report-ContinentGeometry.lua <file>

local ASPECT = 2 / 3
local CLOSE_PIXELS = 24
local WIDTHS = {700, 1000, 1500}
local CENTROID_POINTS = 3
local ZONE = 3

local function sortedKeys(t)
	local keys = {}
	for key in pairs(t or {}) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function set(list)
	local s = {}
	for _, id in ipairs(list or {}) do s[id] = true end
	return s
end

local function idList(ids)
	local parts = {}
	for _, id in ipairs(ids) do parts[#parts + 1] = tostring(id) end
	return table.concat(parts, ", ")
end

local function field(value)
	if value == nil then return "" end
	if type(value) == "string" then return '"' .. value:gsub('"', '""') .. '"' end
	return tostring(value)
end

local HEADER = "Game,Build,Continent,ContinentName,MapID,Name,MapType,Flags,NavBar,Group,MinX,MaxX,MinY,MaxY,HitID,HitName,Cells,CentroidX,CentroidY"

-- One child map of a continent, the shape the rows file keeps it in.
local function recordLine(r)
	local rect = r.rect or {}
	return table.concat({field(r.game), field(r.build), field(r.continent), field(r.continentName), field(r.mapId), field(r.name),
		field(r.mapType), field(r.flags), field(r.navBar), field(r.group), field(rect[1]), field(rect[2]), field(rect[3]), field(rect[4]),
		field(r.hitId), field(r.hitName), field(r.cells), field(r.cx), field(r.cy)}, ",")
end

-- The rows file read back into records: numbers are numbers, an empty field is nothing.
local function parseCsv(text)
	local records = {}
	local first = true
	for line in text:gmatch("[^\r\n]+") do
		if first then
			first = false
		else
			local fields, position = {}, 1
			while position <= #line + 1 do
				local value
				if line:sub(position, position) == '"' then
					local parts, from = {}, position + 1
					while true do
						local quote = line:find('"', from, true)
						if line:sub(quote + 1, quote + 1) == '"' then
							parts[#parts + 1] = line:sub(from, quote)
							from = quote + 2
						else
							parts[#parts + 1] = line:sub(from, quote - 1)
							position = quote + 2
							break
						end
					end
					value = table.concat(parts)
				else
					local comma = line:find(",", position, true) or (#line + 1)
					value = line:sub(position, comma - 1)
					position = comma + 1
				end
				fields[#fields + 1] = value
			end
			local function number(i) return fields[i] ~= "" and tonumber(fields[i]) or nil end
			local rect
			if fields[11] ~= "" then rect = {tonumber(fields[11]), tonumber(fields[12]), tonumber(fields[13]), tonumber(fields[14])} end
			local navBar
			if fields[9] == "true" then navBar = true elseif fields[9] == "false" then navBar = false end
			records[#records + 1] = {game = fields[1], build = fields[2], continent = number(3), continentName = fields[4], mapId = number(5),
				name = fields[6], mapType = number(7), flags = number(8), navBar = navBar,
				group = number(10), rect = rect, hitId = number(15), hitName = fields[16] ~= "" and fields[16] or nil,
				cells = number(17), cx = number(18), cy = number(19)}
		end
	end
	return records
end

local function label(child)
	return string.format("%s (%s)", child.name or "?", tostring(child.mapID))
end

local function fullestBuild(geometry)
	local counts, best = {}, nil
	for _, row in pairs(geometry) do counts[row.build] = (counts[row.build] or 0) + 1 end
	for build, n in pairs(counts) do
		if not best or n > counts[best] or (n == counts[best] and build > best) then best = build end
	end
	return best
end

local function viewsOf(db, build)
	local found = {}
	for _, run in ipairs(db.runs or {}) do
		if run.build == build and run.view then found[#found + 1] = run.view end
	end
	return found
end

local function centre(rect)
	return (rect[1] + rect[2]) / 2, (rect[3] + rect[4]) / 2
end

local function validRect(rect)
	return rect and rect[2] > rect[1] and rect[4] > rect[3]
end

local function report(db, wanted)
	local lines, csv, records = {}, {}, {}
	local function out(format, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(format, ...) or format end
	local geometry = db.geometry or {}
	local build = wanted or fullestBuild(geometry)
	if not build then
		out("No geometry in the file. Type /qcprobe geometry in the game, log out fully and copy the file again.")
		return lines, csv, records
	end
	local rows, empty = {}, {}
	for _, mapID in ipairs(sortedKeys(geometry)) do
		local row = geometry[mapID]
		if row.build == build then
			if #row.children > 0 then rows[#rows + 1] = mapID else empty[#empty + 1] = mapID end
		end
	end
	local first = geometry[rows[1] or empty[1] or next(geometry)]
	local game = first and first.toc == "camelot" and "forever" or "retail"
	out("Geometry on %s (%s): %d maps with children, %d without (%s).", build, game, #rows, #empty, idList(empty))
	local widths, aspect = {unpack(WIDTHS)}, ASPECT
	for _, view in ipairs(viewsOf(db, build)) do
		out("Map window when read: map %s, %s, %s x %s, canvas %s x %s at scale %s, %s zoom levels, UI scale %s.",
			tostring(view.mapID), view.maximized and "maximised" or "windowed", tostring(view.width), tostring(view.height),
			tostring(view.childWidth), tostring(view.childHeight), tostring(view.canvasScale), tostring(view.zoomLevels), tostring(view.uiScale))
		if view.width and view.height and view.width > 0 then
			widths[#widths + 1] = view.width
			aspect = view.height / view.width
		end
	end

	for _, mapID in ipairs(rows) do
		local row = geometry[mapID]
		local byType = {}
		for _, child in ipairs(row.children) do byType[child.mapType or 0] = (byType[child.mapType or 0] or 0) + 1 end
		local types = {}
		for _, mapType in ipairs(sortedKeys(byType)) do types[#types + 1] = string.format("%d of type %d", byType[mapType], mapType) end
		out("")
		out("%d %s (type %s, parent %s): %d children (%s); zone filter lists %d, with descendants %d.",
			mapID, row.name or "?", tostring(row.mapType), tostring(row.parent), #row.children, table.concat(types, ", "),
			#row.zoneCall, #row.zoneTree)

		local zones, zoneIds = {}, {}
		for _, child in ipairs(row.children) do
			if child.mapType == ZONE then
				zones[#zones + 1] = child
				zoneIds[#zoneIds + 1] = child.mapID
			end
		end
		local called, typed = set(row.zoneCall), set(zoneIds)
		local onlyCall, onlyType = {}, {}
		for id in pairs(called) do if not typed[id] then onlyCall[#onlyCall + 1] = id end end
		for id in pairs(typed) do if not called[id] then onlyType[#onlyType + 1] = id end end
		table.sort(onlyCall)
		table.sort(onlyType)
		if #onlyCall == 0 and #onlyType == 0 then
			out("  The zone filter is exact: its answer is the direct children of type zone.")
		else
			out("  The zone filter DIFFERS from the direct children of type zone: only in the call %s; only among the children %s.",
				idList(onlyCall), idList(onlyType))
		end
		local direct = set(zoneIds)
		local deeper = {}
		for _, id in ipairs(row.zoneTree) do if not direct[id] then deeper[#deeper + 1] = id end end
		out("  With descendants the call lists %d more.", #deeper)

		local noRect, bad, outside = {}, {}, {}
		for _, child in ipairs(row.children) do
			if child.noRect then
				noRect[#noRect + 1] = label(child)
			elseif not validRect(child.rect) then
				bad[#bad + 1] = label(child)
			elseif child.rect[1] < -0.001 or child.rect[2] > 1.001 or child.rect[3] < -0.001 or child.rect[4] > 1.001 then
				outside[#outside + 1] = label(child)
			end
		end
		if #noRect > 0 then out("  No rectangle: %s.", table.concat(noRect, ", ")) end
		if #bad > 0 then out("  A rectangle with no width or height: %s.", table.concat(bad, ", ")) end
		if #outside > 0 then out("  A rectangle that leaves the map: %s.", table.concat(outside, ", ")) end

		local byName, twins = {}, {}
		for _, child in ipairs(zones) do
			byName[child.name or "?"] = byName[child.name or "?"] or {}
			table.insert(byName[child.name or "?"], child)
		end
		for _, name in ipairs(sortedKeys(byName)) do
			local group = byName[name]
			if #group > 1 then
				local parts = {}
				for _, child in ipairs(group) do
					parts[#parts + 1] = string.format("%d (navbar %s, flags %s)", child.mapID, tostring(child.navBar), tostring(child.flags))
				end
				twins[#twins + 1] = name .. ": " .. table.concat(parts, ", ")
			end
		end
		if #twins > 0 then out("  Zones listed under one name: %s.", table.concat(twins, "; ")) end
		local invalid = {}
		for _, child in ipairs(zones) do
			if child.navBar == false then invalid[#invalid + 1] = label(child) end
		end
		if #invalid > 0 then out("  Zones the nav bar does not list: %s.", table.concat(invalid, ", ")) end

		local others, unseen, shifted = {}, {}, {}
		local cells = row.grid and row.grid.cells or {}
		for _, child in ipairs(zones) do
			if child.hit and child.hit.mapID ~= child.mapID then
				others[#others + 1] = string.format("%s -> %s (%s)", label(child), child.hit.name or "?", tostring(child.hit.mapID))
			end
			local cell = cells[child.mapID]
			if not cell then
				unseen[#unseen + 1] = label(child)
			elseif validRect(child.rect) then
				local cx, cy = centre(child.rect)
				local dx, dy = cell.x - cx * 100, cell.y - cy * 100
				local distance = math.sqrt(dx * dx + dy * dy)
				if distance > CENTROID_POINTS then
					shifted[#shifted + 1] = string.format("%s %.1f points", label(child), distance)
				end
			end
		end
		if #others > 0 then out("  The hit test at a zone's rectangle centre names another map: %s.", table.concat(others, "; ")) end
		if #unseen > 0 then out("  Zones the hit test never names on the %d x %d grid: %s.", row.grid and row.grid.columns or 0, row.grid and row.grid.rows or 0, table.concat(unseen, ", ")) end
		if #shifted > 0 then out("  The grid's centre of a zone is over %d map points from its rectangle's: %s.", CENTROID_POINTS, table.concat(shifted, "; ")) end

		local placed = {}
		for _, child in ipairs(zones) do
			if validRect(child.rect) then
				local cx, cy = centre(child.rect)
				placed[#placed + 1] = {child = child, x = cx, y = cy}
			end
		end
		for index, width in ipairs(widths) do
			local height = width * aspect
			local pairsClose = {}
			for i = 1, #placed do
				for j = i + 1, #placed do
					local dx, dy = (placed[i].x - placed[j].x) * width, (placed[i].y - placed[j].y) * height
					local distance = math.sqrt(dx * dx + dy * dy)
					if distance < CLOSE_PIXELS then
						pairsClose[#pairsClose + 1] = string.format("%s / %s %.0f px", placed[i].child.name or "?", placed[j].child.name or "?", distance)
					end
				end
			end
			if #pairsClose > 0 then
				out("  At %d px wide, %d zone icon pairs are closer than %d px%s", width, #pairsClose, CLOSE_PIXELS,
					index == 1 and ": " .. table.concat(pairsClose, "; ") .. "." or ".")
			end
		end

		for _, child in ipairs(row.children) do
			local cell = cells[child.mapID]
			local record = {game = game, build = build, continent = mapID, continentName = row.name, mapId = child.mapID, name = child.name,
				mapType = child.mapType, flags = child.flags, navBar = child.navBar, group = child.group, rect = child.rect,
				hitId = child.hit and child.hit.mapID, hitName = child.hit and child.hit.name, cells = cell and cell.n or 0,
				cx = cell and cell.x, cy = cell and cell.y}
			records[#records + 1] = record
			csv[#csv + 1] = recordLine(record)
		end
	end
	return lines, csv, records
end

if (...) == "module" then return report, parseCsv, recordLine, HEADER end

local savedFile, csvFile, wanted = arg[1], arg[2], arg[3]
if not savedFile then
	io.stderr:write("usage: lua tools/Report-ContinentGeometry.lua <QCForeverProbe.lua> [rows.csv] [build]\n")
	os.exit(2)
end
dofile(savedFile)
local db = QCForeverProbeDB or error("no QCForeverProbeDB in " .. savedFile)
local lines, csv = report(db, wanted)
for _, line in ipairs(lines) do print(line) end
if csvFile and #csv > 0 then
	local f = assert(io.open(csvFile, "w"))
	f:write(HEADER, "\n")
	for _, row in ipairs(csv) do f:write(row, "\n") end
	f:close()
	print(string.format("Wrote %d rows to %s.", #csv, csvFile))
end
