-- Prints Blizzard's generated API documentation as tab-separated lines, for Compare-ApiDocs.ps1.
-- The files in Interface\AddOns\Blizzard_APIDocumentationGenerated are Lua tables handed to
-- APIDocumentation:AddDocumentationTable, so this stands in for that object and loads every file.
-- usage: lua Read-ApiDocs.lua <folder of *Documentation.lua files> <file1> <file2> ...
-- Each line: kind (F function, E event, T structure or enumeration), system, namespace (empty for
-- a global), name, arguments, returns (or an event's payload, or a table's fields), notes.
-- Arguments and fields are "name:type", with ? for nilable, =value for a default or enum value.
-- Files that don't load (constants files that refer to Enum tables) are reported on lines starting
-- with #, as is the final count, so the caller needs no stderr.
local dir = arg[1]

local function describe(list)
	if not list then return "" end
	local parts = {}
	for _, f in ipairs(list) do
		local s = (f.Name or "?") .. ":" .. tostring(f.Type or "?")
		if f.InnerType then s = s .. "<" .. tostring(f.InnerType) .. ">" end
		if f.Nilable then s = s .. "?" end
		if f.Default ~= nil then s = s .. "=" .. tostring(f.Default) end
		if f.EnumValue ~= nil then s = s .. "=" .. tostring(f.EnumValue) end
		parts[#parts + 1] = s
	end
	return table.concat(parts, ", ")
end

local function clean(value)
	return (tostring(value == nil and "" or value):gsub("[\t\r\n]", " "))
end

local function line(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = clean((select(i, ...))) end
	io.write(table.concat(parts, "\t"), "\n")
end

local function notes(entry)
	local out = {}
	if entry.SecretArguments then out[#out + 1] = "SecretArguments=" .. tostring(entry.SecretArguments) end
	if entry.SecretReturns then out[#out + 1] = "SecretReturns" end
	if entry.MayReturnNothing then out[#out + 1] = "MayReturnNothing" end
	if entry.HasRestrictions then out[#out + 1] = "HasRestrictions" end
	if entry.Documentation then out[#out + 1] = table.concat(entry.Documentation, " ") end
	return table.concat(out, "; ")
end

APIDocumentation = {}
function APIDocumentation:AddDocumentationTable(t)
	local system, namespace = t.Name or "?", t.Namespace or ""
	for _, f in ipairs(t.Functions or {}) do
		line("F", system, namespace, f.Name, describe(f.Arguments), describe(f.Returns), notes(f))
	end
	for _, e in ipairs(t.Events or {}) do
		line("E", system, namespace, e.LiteralName or e.Name, describe(e.Payload), "", notes(e))
	end
	for _, tb in ipairs(t.Tables or {}) do
		line("T", system, namespace, (tb.Name or "?") .. " (" .. tostring(tb.Type) .. ")", describe(tb.Fields), "", notes(tb))
	end
end

local failed = 0
for i = 2, #arg do
	local ok, err = pcall(dofile, dir .. "/" .. arg[i])
	if not ok then
		failed = failed + 1
		io.write("# ", arg[i], ": ", clean(err), "\n")
	end
end
io.write(string.format("# %d files, %d failed to load\n", #arg - 1, failed))
