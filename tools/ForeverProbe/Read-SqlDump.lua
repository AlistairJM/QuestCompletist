-- Prints chosen columns of one table in a MySQL dump as tab-separated lines, one per row.
-- usage: lua Read-SqlDump.lua <dump.sql> <table> <column,column,...>   (1-based column numbers)
local path, tableName, columnList = arg[1], arg[2], arg[3]
local columns = {}
for column in columnList:gmatch("%d+") do columns[#columns + 1] = tonumber(column) end
local prefix = "INSERT INTO `" .. tableName .. "` VALUES "

local function emit(fields)
	local parts = {}
	for i, column in ipairs(columns) do parts[i] = (fields[column] or ""):gsub("[\t\r\n]", " ") end
	io.stdout:write(table.concat(parts, "\t"), "\n")
end

local function parse(line, position)
	local length = #line
	while position <= length do
		if line:sub(position, position) == "(" then
			local fields = {}
			position = position + 1
			while true do
				if line:sub(position, position) == "'" then
					local pieces = {}
					position = position + 1
					while true do
						local stop = line:find("[\\']", position)
						pieces[#pieces + 1] = line:sub(position, stop - 1)
						if line:sub(stop, stop) == "\\" then
							pieces[#pieces + 1] = line:sub(stop + 1, stop + 1)
							position = stop + 2
						else
							position = stop + 1
							break
						end
					end
					fields[#fields + 1] = table.concat(pieces)
				else
					local stop = line:find("[,)]", position)
					fields[#fields + 1] = line:sub(position, stop - 1)
					position = stop
				end
				local separator = line:sub(position, position)
				position = position + 1
				if separator == ")" then break end
			end
			emit(fields)
		else
			position = position + 1
		end
	end
end

for line in io.lines(path) do
	if line:sub(1, #prefix) == prefix then parse(line, #prefix + 1) end
end
