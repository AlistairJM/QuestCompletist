-- Prints Blizzard's generated API documentation as tab-separated lines, for Compare-ApiDocs.ps1.
-- The files in Interface\AddOns\Blizzard_APIDocumentationGenerated are Lua tables handed to
-- APIDocumentation:AddDocumentationTable, so this stands in for that object and loads every file.
-- usage: lua Read-ApiDocs.lua <folder of *Documentation.lua files> <file1> <file2> ...
-- Each line: kind (F function, E event, T structure or enumeration), system, namespace (empty for
-- a global; the system's name for the methods of a script object; a function's own Namespace wins), name, arguments, returns (or an
-- event's payload, or a table's fields), notes, secrecy.
-- Arguments and fields are "name:type", with ? for nilable, =value for a default or enum value.
-- Secrecy is every flag whose name contains "Secret" or that SecretPredicatesDocumentation.lua
-- declares (RequiresUnitAuraAccess ...): the entry's own (SecretArguments=AllowedWhenUntainted,
-- SecretReturns, SecretWhenInCombat, SecretPayloads ...), each argument's, return's, payload field's
-- and structure field's (NeverSecret, ConditionalSecret, SecretValue ...) as "arg name:Flag",
-- "return name:Flag", "payload name:Flag" or "field name:Flag", and the same for the fields of every
-- structure or callback type those lead to, as "Structure.field:Flag". The items are separated by
-- "; ", in the order they are found, so a caller compares them as a set.
-- Files that don't load (constants files and the widget-method files, which refer to Enum and
-- Constants tables) are reported on lines starting with #, as is the final count, so the caller
-- needs no stderr.
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
	if entry.MayReturnNothing then out[#out + 1] = "MayReturnNothing" end
	if entry.HasRestrictions then out[#out + 1] = "HasRestrictions" end
	if entry.Documentation then out[#out + 1] = table.concat(entry.Documentation, " ") end
	return table.concat(out, "; ")
end

local predicates = {}

local function flagText(key, value)
	if value == true then return key end
	if type(value) == "table" then
		local parts = {}
		for _, v in ipairs(value) do
			local kind = type(v)
			if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then error("flag " .. key .. " holds a " .. kind) end
			parts[#parts + 1] = tostring(v)
		end
		if #parts == 0 and next(value) ~= nil then error("flag " .. key .. " holds a table that is not a list") end
		return key .. "=[" .. table.concat(parts, ",") .. "]"
	end
	return key .. "=" .. tostring(value)
end

local function flagsOf(entry)
	local keys = {}
	for key in pairs(entry) do
		if type(key) == "string" and (key:lower():find("secret", 1, true) or predicates[key]) then keys[#keys + 1] = key end
	end
	table.sort(keys)
	local out = {}
	for _, key in ipairs(keys) do out[#out + 1] = flagText(key, entry[key]) end
	return out
end

local structures = {}
local records = {}
local FIELD_LISTS = { { "Arguments", "arg" }, { "Returns", "return" }, { "Payload", "payload" }, { "Fields", "field" } }

local function addFieldItems(items, entry, prefix, seen)
	for _, spec in ipairs(FIELD_LISTS) do
		local list = entry[spec[1]]
		if type(list) == "table" then
			for _, f in ipairs(list) do
				local flags = flagsOf(f)
				if #flags > 0 then
					items[#items + 1] = prefix(spec[2], f.Name or "?") .. ":" .. table.concat(flags, ",")
				end
			end
			for _, f in ipairs(list) do
				for _, typeName in ipairs({ f.Type or false, f.InnerType or false }) do
					local structure = typeName and structures[typeName]
					if structure and not seen[typeName] then
						seen[typeName] = true
						local own = flagsOf(structure)
						if #own > 0 then items[#items + 1] = typeName .. ":" .. table.concat(own, ",") end
						addFieldItems(items, structure, function(_, name) return typeName .. "." .. name end, seen)
					end
				end
			end
		end
	end
end

local function secrecy(entry)
	local items = flagsOf(entry)
	local seen = {}
	if (entry.Type == "Structure" or entry.Type == "CallbackType") and entry.Name then seen[entry.Name] = true end
	addFieldItems(items, entry, function(kind, name) return kind .. " " .. name end, seen)
	return table.concat(items, "; ")
end

APIDocumentation = {}
function APIDocumentation:AddDocumentationTable(t)
	local system, namespace = t.Name or "?", t.Namespace or ""
	if namespace == "" and t.Type == "ScriptObject" then namespace = system end
	for _, p in ipairs(t.Predicates or {}) do
		if p.Name then predicates[p.Name] = true end
	end
	for _, f in ipairs(t.Functions or {}) do
		records[#records + 1] = { "F", system, f.Namespace or namespace, f.Name, describe(f.Arguments), describe(f.Returns), notes(f), f }
	end
	for _, e in ipairs(t.Events or {}) do
		records[#records + 1] = { "E", system, namespace, e.LiteralName or e.Name, describe(e.Payload), "", notes(e), e }
	end
	for _, tb in ipairs(t.Tables or {}) do
		if (tb.Type == "Structure" or tb.Type == "CallbackType") and tb.Name then structures[tb.Name] = tb end
		records[#records + 1] = { "T", system, namespace, (tb.Name or "?") .. " (" .. tostring(tb.Type) .. ")", describe(tb.Fields), "", notes(tb), tb }
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
for _, r in ipairs(records) do
	local ok, text = pcall(secrecy, r[8])
	if not ok then error(r[2] .. " " .. r[3] .. " " .. tostring(r[4]) .. ": " .. tostring(text), 0) end
	line(r[1], r[2], r[3], r[4], r[5], r[6], r[7], text)
end
io.write(string.format("# %d files, %d failed to load\n", #arg - 1, failed))
