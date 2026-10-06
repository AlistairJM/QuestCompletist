--[[
Checks the addon's translations. Loads the Localization files the way the game does, once for each
client language, and reports:
  - a key the code uses (qcL.KEY) that has no text, even in English;
  - a translation whose placeholders (%d, %s) differ from the English: string.format stops with an
    error when a translation asks for more values than the code passes;
  - a translation that doesn't format, and a missing key that doesn't fall back to English;
  - a key English has that nothing uses: no code names it, either game's, no menu heading shows it,
    and no category the client can't name falls back to it;
  - a translation of a key only menu headings the client names (clientName) show. The client
    names them in every language; the English stays, in case it ever doesn't;
  - a label on a category's menu entry: the menu names the category through qcCategoryName, so the
    entry's text only gives its indent;
  - a key a translation has that English doesn't.
Remove-ConvertedLocaleKeys.ps1 removes the text the last four find redundant.

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

local function loadData(file, env)
	local chunk = assert(loadstring(readFile(ADDON_DIR .. "/" .. file), "@" .. file))
	setfenv(chunk, env)
	chunk()
	return env
end

local problems = 0
local function problem(text)
	problems = problems + 1
	print(text)
end

-- Keys the code uses, in every Lua file either game's TOC loads apart from the translations and the
-- menus. qcL[...] with a computed key is listed by hand, or is a settings row's text.
local used = {UNAVAILABLEACCEPTED = true, UNAVAILABLETURNEDIN = true}
local menus = {}
for _, toc in ipairs({"QuestCompletist.toc", "QuestCompletist_Camelot.toc"}) do
	for tocLine in readFile(ADDON_DIR .. "/" .. toc):gmatch("[^\r\n]+") do
		local file = tocLine:match("^%s*([^#%s][^%s]*%.lua)%s*$")
		file = file and (file:gsub("\\", "/"))
		if file and file:match("qcMenu%.lua$") then
			menus[file] = true
		elseif file and not file:match("^Localization%.") then
			local code = readFile(ADDON_DIR .. "/" .. file)
			code = code:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
			for key in code:gmatch("qcL%.([A-Z0-9_]+)") do used[key] = true end
			for key in code:gmatch("text%s*=%s*\"([A-Z][A-Z0-9_]*)\"") do used[key] = true end
		end
	end
end

-- The menus, loaded with a qcLocalize that marks each key it hands out, so each entry's text shows
-- the keys in it. A heading the client names (clientName) only falls back to its key.
local clientHeadings = {}
for file in pairs(menus) do
	local marks = setmetatable({}, {__index = function(_, key) return "\1" .. key .. "\2" end})
	local menu = loadData(file, setmetatable({qcLocalize = marks, GetText = function(key) return key end}, {__index = _G})).qcMenu
	local function walk(list)
		for _, item in ipairs(list) do
			for key in tostring(item.text or ""):gmatch("\1([A-Z0-9_]+)\2") do
				if type(item.arg1) == "number" then
					problem(string.format("%s: category %d's entry has a label nothing shows: qcL.%s", file, item.arg1, key))
				elseif item.clientName then
					clientHeadings[key] = true
				else
					used[key] = true
				end
			end
			if item.menuList then walk(item.menuList) end
		end
	end
	walk(menu)
end

-- A category the client can't name falls back to the key made of its English name's letters and
-- digits, upper-cased (qcCategoryName in qcCore.lua). One the client names needs no key.
local categoryKeys = {}
for _, file in ipairs({"qcQuest.lua", "Forever/qcQuest.lua"}) do
	local data = loadData(file, {})
	for _, category in ipairs(data.qcQuestCategories) do
		local id = category[1]
		if not ((data.qcCategoryUiMapID or {})[id] or (data.qcCategoryClientName or {})[id]) then
			categoryKeys[(category[2]:gsub("[^%a%d]", "")):upper()] = true
		end
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

for _, client in ipairs(locales) do
	GetLocale = function() return client end
	qcLocalize = nil
	local english
	for _, locale in ipairs(locales) do
		dofile(ADDON_DIR .. "/Localization." .. locale .. ".lua")
		if locale == "enUS" then english = qcLocalize end
	end
	local L, own = qcLocalize, 0
	for _, keys in ipairs({used, clientHeadings}) do
		for key in pairs(keys) do
			if type(L[key]) ~= "string" then problem(client .. ": " .. key .. " has no text") end
		end
	end
	for key in pairs(L) do
		if L == english then
			if not (used[key] or clientHeadings[key] or categoryKeys[key]) then
				problem(client .. ": " .. key .. " isn't used: no code or menu heading shows it, and no category the client can't name falls back to it")
			end
		elseif english[key] == nil then
			problem(client .. ": " .. key .. " isn't in English")
		elseif clientHeadings[key] and not (used[key] or categoryKeys[key]) then
			problem(client .. ": " .. key .. " needn't be translated: the client names every menu heading that shows it")
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
