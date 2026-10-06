--[[
Checks the addon's translations. Loads the Localization files the way the game does, once for each
client language, and reports:
  - a key the code uses (qcL.KEY) that has no text, even in English;
  - a translation whose placeholders (%d, %s) differ from the English: string.format stops with an
    error when a translation asks for more values than the code passes;
  - a translation that doesn't format, and a missing key that doesn't fall back to English;
  - a key English has that nothing uses: no code names it, either game's, and it isn't a category's
    name, which a category the client can't name falls back to;
  - a key a translation has that English doesn't.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-Localization.lua
]]

local ADDON_DIR = arg and arg[1] or "QuestCompletist"
local locales = {"enUS", "ptBR", "frFR", "deDE", "itIT", "koKR", "esMX", "ruRU", "zhCN", "esES", "zhTW"}

local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

-- Keys the code uses, in every Lua file either game's TOC loads apart from the translations
-- themselves. qcL[...] with a computed key is listed by hand. The strings in the code count as uses
-- too, as a computed key comes from one, such as a settings row's text.
local used = {UNAVAILABLEACCEPTED = true, UNAVAILABLETURNEDIN = true}
local quoted = {}
for _, toc in ipairs({"QuestCompletist.toc", "QuestCompletist_Camelot.toc"}) do
	for tocLine in readFile(ADDON_DIR .. "/" .. toc):gmatch("[^\r\n]+") do
		local file = tocLine:match("^%s*([^#%s][^%s]*%.lua)%s*$")
		if file and not file:match("^Localization%.") then
			local code = readFile(ADDON_DIR .. "/" .. (file:gsub("\\", "/")))
			code = code:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
			for key in code:gmatch("qcL%.([A-Z0-9_]+)") do used[key] = true end
			for key in code:gmatch("\"([A-Z][A-Z0-9_]*)\"") do quoted[key] = true end
		end
	end
end

-- A category the client can't name falls back to the key made of its English name's letters and
-- digits, upper-cased (qcCategoryName in qcCore.lua).
local categoryKeys = {}
for _, file in ipairs({"qcQuest.lua", "Forever/qcQuest.lua"}) do
	local data = {}
	local chunk = assert(loadstring(readFile(ADDON_DIR .. "/" .. file), "@" .. file))
	setfenv(chunk, data)
	chunk()
	for _, category in ipairs(data.qcQuestCategories) do
		categoryKeys[(category[2]:gsub("[^%a%d]", "")):upper()] = true
	end
end

local function placeholders(s)
	local found = {}
	for p in s:gmatch("%%[-0-9.]*[%a%%]") do found[#found + 1] = p end
	return table.concat(found, " ")
end

local samples = {d = 7, s = "Name", f = 1.5}
local function formats(s)
	local args = {}
	for kind in s:gmatch("%%[-0-9.]*(%a)") do args[#args + 1] = samples[kind] or 1 end
	return pcall(string.format, s, unpack(args))
end

local problems = 0
local function problem(text)
	problems = problems + 1
	print(text)
end

for _, client in ipairs(locales) do
	GetLocale = function() return client end
	qcLocalize = nil
	local english
	for _, locale in ipairs(locales) do
		dofile(ADDON_DIR .. "/Localization." .. locale .. ".lua")
		if locale == "enUS" then english = qcLocalize end
	end
	local L, own = qcLocalize, 0
	for key in pairs(used) do
		if type(L[key]) ~= "string" then problem(client .. ": " .. key .. " has no text") end
	end
	for key in pairs(L) do
		if L == english then
			if not (used[key] or quoted[key] or categoryKeys[key]) then
				problem(client .. ": " .. key .. " isn't used: no code names it, and no category has its name")
			end
		elseif english[key] == nil then
			problem(client .. ": " .. key .. " isn't in English")
		end
	end
	for key, value in pairs(english) do
		local translated = rawget(L, key)
		if translated == nil then
			if L[key] ~= value then problem(client .. ": " .. key .. " doesn't fall back to English") end
		else
			own = own + 1
			if placeholders(translated) ~= placeholders(value) then
				problem(string.format("%s: %s has placeholders '%s', English '%s'", client, key, placeholders(translated), placeholders(value)))
			end
			local ok, err = formats(translated)
			if not ok then problem(client .. ": " .. key .. " doesn't format: " .. err) end
		end
	end
	print(string.format("%s: %d keys of its own", client, own))
end
print(problems == 0 and "No problems" or (problems .. " problems"))
os.exit(problems == 0 and 0 or 1)
