--[[
Checks that the seasonal filter follows the game's calendar from login on: the addon asks for the
calendar's events, redraws an open map when they arrive, and keeps an out-of-season pin hidden.

Loads the addon's own files with stand-ins for the WoW API and drives the real event handler, filter
and map pin code. The calendar stand-in behaves as WoW: Forever's did on 9 October 2026: it starts on
November 2004, holds no events until C_Calendar.OpenCalendar() has asked the server for them, and
fires CALENDAR_UPDATE_EVENT_LIST at once whenever its month is set. Today is a quiet October day
with Hallow's End due on the 18th, and the Lunar Festival isn't running.

The pin checked is the first one in the data whose quests all belong to the Lunar Festival.

Usage, from the repository root (Lua 5.1, the version WoW runs):
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-SeasonalCalendar.lua
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-SeasonalCalendar.lua QuestCompletist QuestCompletist_Camelot.toc
Prints each check and exits with 1 if one fails. Run it for both games' TOCs.
]]

local ADDON_DIR = arg and arg[1] or "QuestCompletist"
local TOC_FILE = arg and arg[2] or "QuestCompletist.toc"

--[[ Lua 5.1 has no bit library; WoW's masks here are all non-negative and under 2^32. ]]--
local function bitop(a, b, both)
	local result, place = 0, 1
	while a > 0 or b > 0 do
		local x, y = a % 2, b % 2
		if (both and x == 1 and y == 1) or (not both and (x == 1 or y == 1)) then
			result = result + place
		end
		a, b, place = (a - x) / 2, (b - y) / 2, place * 2
	end
	return result
end
local bit = {
	band = function(a, b) return bitop(a, b, true) end,
	bor = function(a, b) return bitop(a, b, false) end,
}

local dummy
dummy = setmetatable({}, {
	__index = function() return dummy end,
	__call = function() return dummy end,
	__newindex = function() end,
	__concat = function() return "" end,
})
local function stubTable(t)
	return setmetatable(t, {__index = function() return dummy end})
end

local function readFile(path)
	local handle = assert(io.open(path, "rb"))
	local text = handle:read("*a")
	handle:close()
	return text
end

--[[ Today, and the calendar's events around it ]]--
local NOW = {year = 2026, month = 10, monthDay = 9, weekday = 6, hour = 14, minute = 30}
local function at(month, day, hour)
	return {year = 2026, month = month, monthDay = day, hour = hour or 0, minute = 0}
end
local function holiday(eventID, title, startTime, endTime)
	return {calendarType = "HOLIDAY", eventID = eventID, title = title, startTime = startTime, endTime = endTime}
end
local function quietOctober()
	return {
		holiday(324, "Hallow's End", at(10, 18, 4), at(11, 2, 4)),
		holiday(301, "Stranglethorn Fishing Extravaganza", at(10, 11, 14), at(10, 11, 16)),
	}
end
local LUNAR_FESTIVAL = holiday(327, "Lunar Festival", at(10, 2, 6), at(10, 16, 6))

local function dayValue(t) return (t.year * 100 + t.month) * 100 + t.monthDay end
local function daysInMonth(year, month)
	return os.date("*t", os.time{year = year, month = month + 1, day = 0, hour = 12}).day
end

--[[ The calendar stand-in; fire is set once the addon is loaded ]]--
local function newCalendar(events)
	local calendar = {shown = {year = 2004, month = 11}, events = events, requested = false, delivered = false,
		openCalls = 0, monthCalls = 0, windowOpen = false}
	local function dayEvents(day)
		local out = {}
		if not calendar.delivered then return out end
		local today = (calendar.shown.year * 100 + calendar.shown.month) * 100 + day
		for _, event in ipairs(calendar.events) do
			if today >= dayValue(event.startTime) and today <= dayValue(event.endTime) then out[#out + 1] = event end
		end
		return out
	end
	calendar.api = {
		SetAbsMonth = function(month, year)
			calendar.monthCalls = calendar.monthCalls + 1
			calendar.shown = {year = year, month = month}
			calendar.fire()
		end,
		GetMonthInfo = function()
			return {year = calendar.shown.year, month = calendar.shown.month,
				numDays = daysInMonth(calendar.shown.year, calendar.shown.month), firstWeekday = 1}
		end,
		GetNumDayEvents = function(_, day) return #dayEvents(day) end,
		GetDayEvent = function(_, day, index) return dayEvents(day)[index] end,
		OpenCalendar = function()
			calendar.openCalls = calendar.openCalls + 1
			calendar.requested = true
		end,
	}
	-- The server's reply, which only comes to a request.
	function calendar.reply()
		if not calendar.requested then return false end
		calendar.delivered = true
		calendar.fire()
		return true
	end
	return calendar
end

--[[ Load the addon in TOC order, reaching the core's file-local helpers through a trailing return ]]--
local function load(events)
	local ctx = {calendar = newCalendar(events), timers = {}, redraws = 0, chat = {}}
	local env = {
		bit = bit,
		print = function(...) ctx.chat[#ctx.chat + 1] = table.concat({...}, " ") end,
		GetLocale = function() return "enUS" end,
		GetText = function(key) return key end,
		wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
		tinsert = table.insert, tremove = table.remove,
		strupper = string.upper, strlower = string.lower, strfind = string.find, strsub = string.sub,
		strlen = string.len, format = string.format, strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
		floor = math.floor, ceil = math.ceil, max = math.max, min = math.min, abs = math.abs,
		date = os.date, time = os.time,
		CreateFromMixins = function() return {} end,
		C_Calendar = setmetatable({}, {__index = function(_, key) return ctx.calendar.api[key] or dummy end}),
		C_DateAndTime = stubTable({GetCurrentCalendarTime = function() return NOW end}),
		C_Timer = {After = function(_, fn) ctx.timers[#ctx.timers + 1] = fn end},
		UnitFactionGroup = function() return "Alliance", "Alliance" end,
		UnitRace = function() return "NightElf", "NightElf" end,
		UnitClass = function() return "DRUID", "DRUID" end,
		UnitLevel = function() return 1000 end,
		UnitQuestTrivialLevelRange = function() return 5 end,
		GetProfessions = function() return end,
		GetProfessionInfo = function() return end,
		C_Covenants = stubTable({GetActiveCovenantID = function() return 0 end}),
		C_MajorFactions = stubTable({GetCurrentRenownLevel = function() return 1000 end}),
		C_SkillInfo = stubTable({GetSkillLineInfoByID = function() return {rank = 1000, modifier = 0} end}),
		C_QuestLog = stubTable({
			GetLogIndexForQuestID = function() return nil end,
			IsQuestFlaggedCompleted = function() return false end,
			IsQuestFlaggedCompletedOnAccount = function() return false end,
			GetTitleForQuestID = function() return nil end,
			RequestLoadQuestByID = function() end,
		}),
		C_TaskQuest = stubTable({GetQuestInfoByQuestID = function() return nil end}),
		C_TooltipInfo = stubTable({GetHyperlink = function() return nil end}),
		IsInInstance = function() return false end,
	}
	setmetatable(env, {__index = function(_, key)
		if key == "CalendarFrame" then return ctx.calendarFrame end
		local value = _G[key]
		if value ~= nil then return value end
		return dummy
	end})

	local addonTable = {}
	for line in readFile(ADDON_DIR .. "/" .. TOC_FILE):gmatch("[^\r\n]+") do
		local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
		if file and file:sub(1, 4) ~= "Libs" then
			local source = readFile(ADDON_DIR .. "/" .. file)
			if file == "qcCore.lua" then
				source = source .. [[

return {Holidays = qcHolidays, Handler = qcEventHandler, Print = qcPrintHolidays,
	Active = function() return qcActiveHolidays end, Why = function() return qcCalendarWhy end}]]
			end
			local chunk = assert(loadstring(source, "@" .. ADDON_DIR .. "/" .. file))
			setfenv(chunk, env)
			local result = chunk("QuestCompletist", addonTable)
			if file == "qcCore.lua" then ctx.core = result end
		end
	end
	assert(ctx.core and ctx.core.Handler, "qcEventHandler not found in qcCore.lua")
	ctx.env = env

	-- A map that keeps what was drawn on it, as the player sees it.
	local map = {drawn = {}}
	function map:GetMapID() return self.mapId end
	function map:RemoveAllPinsByTemplate() self.drawn = {} end
	function map:AcquirePin(_, pinData) self.drawn[#self.drawn + 1] = pinData end
	local provider = env.qcMapDataProvider
	provider.GetMap = function() return map end
	local draw = provider.RefreshAllData
	provider.RefreshAllData = function(self) ctx.redraws = ctx.redraws + 1 return draw(self) end
	ctx.map = map

	ctx.calendar.fire = function() ctx.core.Handler(nil, "CALENDAR_UPDATE_EVENT_LIST") end
	function ctx.flush()
		local timers = ctx.timers
		ctx.timers = {}
		for _, fn in ipairs(timers) do fn() end
	end
	function ctx.login() return pcall(ctx.core.Handler, nil, "PLAYER_ENTERING_WORLD", true, false) end
	function ctx.openMap()
		ctx.map.mapId = ctx.pin.mapId
		ctx.provider = provider
		provider:RefreshAllData()
	end
	function ctx.pinShown()
		for _, pinData in ipairs(ctx.map.drawn) do
			for _, questId in ipairs(pinData[6]) do
				if questId == ctx.pin.questId then return true end
			end
		end
		return false
	end
	function ctx.active()
		local mask = ctx.core.Active()
		return mask == nil and "nil" or tostring(mask)
	end

	-- Only the seasonal filter on, so the pin is shown or hidden by the calendar alone.
	env.qcSettings = {}
	env.qcCheckSettings()
	for key in pairs(env.qcSettings) do
		if key:match("^QC_.*HIDE") then env.qcSettings[key] = 0 end
	end
	env.qcSettings.QC_M_HIDE_SEASONAL = 1
	env.qcSettings.QC_M_SHOW_ICONS = 1
	env.qcCharacterCompletions = {}

	-- The first pin whose quests are all the Lunar Festival's.
	local lunarFlag
	for _, entry in ipairs(ctx.core.Holidays) do
		if entry.name == "Lunar Festival" then lunarFlag = entry.flag end
	end
	local mapIds = {}
	for mapId in pairs(env.qcPinDB) do mapIds[#mapIds + 1] = mapId end
	table.sort(mapIds)
	for _, mapId in ipairs(mapIds) do
		for _, pin in ipairs(env.qcPinDB[mapId]) do
			local allLunar = #pin[6] > 0
			for _, questId in ipairs(pin[6]) do
				if env.qcQuestHoliday[questId] ~= lunarFlag or not env.qcQuestDatabase[questId] then allLunar = false end
			end
			if allLunar and not ctx.pin then ctx.pin = {mapId = mapId, questId = pin[6][1], name = pin[3]} end
		end
	end
	assert(ctx.pin, "no pin of the Lunar Festival's quests in the data")
	return ctx
end

--[[ Checks ]]--
local failures = 0
local function check(label, passed, detail)
	if not passed then failures = failures + 1 end
	print(string.format("  [%s] %s%s", passed and "ok" or "FAIL", label, detail and (" (" .. detail .. ")") or ""))
end

local first = load(quietOctober())
print(string.format("%s, %s: pin of %s, quest %d, map %d", ADDON_DIR, TOC_FILE, tostring(first.pin.name),
	first.pin.questId, first.pin.mapId))

print("Fresh login, a calendar that stays empty until it's asked, then the server replies")
do
	local ctx = load(quietOctober())
	local ok, err = ctx.login()
	check("login is handled", ok, err and tostring(err))
	check("the calendar is asked for its events", ctx.calendar.openCalls == 1, "OpenCalendar calls: " .. ctx.calendar.openCalls)
	ctx.openMap()
	check("a map opened before the answer shows the pin", ctx.pinShown(), "answer: " .. ctx.active() .. ", " .. tostring(ctx.core.Why()))
	local redrawsBefore = ctx.redraws
	check("the server replies", ctx.calendar.reply())
	ctx.flush()
	check("no holiday of ours is running", ctx.active() == "0", "answer: " .. ctx.active())
	check("the open map redraws once, by itself", ctx.redraws == redrawsBefore + 1, "redraws: " .. (ctx.redraws - redrawsBefore))
	check("the pin is gone from it", not ctx.pinShown())
	redrawsBefore = ctx.redraws
	ctx.calendar.fire()
	ctx.flush()
	check("the same answer again redraws nothing", ctx.redraws == redrawsBefore)
	ctx.openMap()
	check("a map opened later keeps it hidden", not ctx.pinShown())
end

print("Until the calendar has answered, seasonal pins are shown")
do
	local ctx = load(quietOctober())
	ctx.openMap()
	ctx.openMap()
	check("the pin stays on every draw", ctx.pinShown())
	check("the server answers only a request", not ctx.calendar.reply())
end

print("The server replies while Blizzard's calendar window is open on another month")
do
	local ctx = load(quietOctober())
	ctx.calendar.requested = true
	ctx.calendar.delivered = true
	ctx.calendar.shown = {year = 2026, month = 12}
	ctx.calendarFrame = {IsShown = function() return true end}
	local redrawsBefore = ctx.redraws
	ctx.calendar.fire()
	ctx.flush()
	check("there's no answer, and it says why", ctx.active() == "nil" and ctx.core.Why() == "its window is open on another month",
		"answer: " .. ctx.active() .. ", " .. tostring(ctx.core.Why()))
	check("the window's month is left alone", ctx.calendar.shown.month == 12 and ctx.calendar.monthCalls == 0)
	check("nothing is redrawn", ctx.redraws == redrawsBefore)
end

print("/qc holidays")
do
	local ctx = load(quietOctober())
	ctx.core.Print()
	check("it says why the calendar hasn't answered", (ctx.chat[1] or ""):find("hasn't answered yet (it has no events this month)", 1, true) ~= nil,
		ctx.chat[1])
	check("the scan sets the month 15 times: the read, 13 months, and back", ctx.calendar.monthCalls == 15,
		"month changes: " .. ctx.calendar.monthCalls)
	check("it leaves the calendar on the current month", ctx.calendar.shown.month == NOW.month and ctx.calendar.shown.year == NOW.year)
end

print("The calendar says the Lunar Festival is running")
do
	local ctx = load({LUNAR_FESTIVAL})
	ctx.login()
	ctx.openMap()
	ctx.calendar.reply()
	ctx.flush()
	check("the pin stays", ctx.pinShown(), "answer: " .. ctx.active())
end

print(failures == 0 and "All checks passed." or (failures .. " check(s) failed."))
os.exit(failures == 0 and 0 or 1)
