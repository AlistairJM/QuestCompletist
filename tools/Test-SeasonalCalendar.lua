--[[
Checks that the seasonal filter follows the game's calendar from login on: the addon asks for the
calendar's events, redraws an open map when they arrive, and keeps an out-of-season pin hidden. And
that it shows every seasonal quest it can't judge: when the calendar hasn't answered, and for a
holiday whose filter is unticked in Blizzard's calendar window.

Loads the addon's own files with stand-ins for the WoW API and drives the real event handler, filter
and map pin code. The calendar stand-in behaves as WoW: Forever's did on 9 October 2026: it starts on
November 2004, holds no events until C_Calendar.OpenCalendar() has asked the server for them, and
fires CALENDAR_UPDATE_EVENT_LIST at once whenever its month is set. Today is a quiet October day
with Hallow's End due on the 18th, and the Lunar Festival isn't running. It leaves out the events of
a filter whose CVar is false, the way Blizzard's window needs the game to (its checkboxes only set the
CVar and redraw from the day lists); whether the game really does hasn't been seen in game.

The pins checked are the first ones in the data whose quests all belong to the Lunar Festival, and to
the Darkmoon Faire, and on retail to WoW's Anniversary, which must follow its yearly row (1808, "WoW's
22nd Anniversary") and not a per-region row named plain "WoW's Anniversary" (1587, region 4's), which
the calendar didn't serve when it was checked in game on 11 October 2026 (and so must the pin of
83825, a Guest Relations quest of the 20th anniversary), and to the Skyriding Cups, whose one flag must
follow any cup's row (the Kalimdor Cup, 1395, and the Northrend Cup, 1429), and to The Great
Gnomeregan Run (696) and Dastardly Duos, whose pins must follow any of its three rows (the stand-in
calendar has no regions; 1689 is region 4's and 1599 another region's), and to Call of the Scarab
(638), whose turn-ins' pins must show only while it runs.

/qc holidays must list each ID of an entry that the calendar has in its 12 months, soonest first and
once each, so a sweep can confirm every ID in game: Hallow's End's 324 and 1405, the Darkmoon Faire's
479 in two months, and on retail the Kalimdor and Eastern Kingdoms Cups (1395 and 1400).

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
local function holiday(eventID, title, startTime, endTime, cvar)
	return {calendarType = "HOLIDAY", eventID = eventID, title = title, startTime = startTime, endTime = endTime,
		cvar = cvar or "calendarShowHolidays"}
end
local function quietOctober()
	return {
		holiday(324, "Hallow's End", at(10, 18, 4), at(11, 2, 4)),
		holiday(301, "Stranglethorn Fishing Extravaganza", at(10, 11, 14), at(10, 11, 16), "calendarShowWeeklyHolidays"),
	}
end
local LUNAR_FESTIVAL = holiday(327, "Lunar Festival", at(10, 2, 6), at(10, 16, 6))
local ANNIVERSARY = "WoW's Anniversary"
local GUEST_RELATIONS = 83825
local CUPS = "Skyriding Cups"
local GNOMEREGAN_RUN = "The Great Gnomeregan Run"
local DUOS = "Dastardly Duos"
local SCARAB = "Call of the Scarab"
local RAID_LOCKOUT = {calendarType = "RAID_LOCKOUT", eventID = 0, title = "Molten Core", startTime = at(10, 14, 0),
	endTime = at(10, 14, 0), cvar = "calendarShowLockouts"}
local function withLockout(events)
	events[#events + 1] = RAID_LOCKOUT
	return events
end

local FILTER_NAMES = {CALENDAR_FILTER_HOLIDAYS = "Holidays", CALENDAR_FILTER_DARKMOON = "Darkmoon Faire",
	CALENDAR_FILTER_WEEKLY_HOLIDAYS = "Weekly Holidays"}
for name, text in pairs(FILTER_NAMES) do _G[name] = text end

local function dayValue(t) return (t.year * 100 + t.month) * 100 + t.monthDay end
local function daysInMonth(year, month)
	return os.date("*t", os.time{year = year, month = month + 1, day = 0, hour = 12}).day
end

--[[ The calendar stand-in; fire is set once the addon is loaded ]]--
local function newCalendar(events, cvars)
	local calendar = {shown = {year = 2004, month = 11}, events = events, requested = false, delivered = false,
		openCalls = 0, monthCalls = 0, windowOpen = false}
	local function dayEvents(day)
		local out = {}
		if not calendar.delivered then return out end
		local today = (calendar.shown.year * 100 + calendar.shown.month) * 100 + day
		for _, event in ipairs(calendar.events) do
			if cvars[event.cvar] ~= false and today >= dayValue(event.startTime) and today <= dayValue(event.endTime) then
				out[#out + 1] = event
			end
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
	local ctx = {timers = {}, redraws = 0, chat = {}, cvarWrites = 0}
	ctx.cvars = {calendarShowHolidays = true, calendarShowDarkmoon = true, calendarShowWeeklyHolidays = true,
		calendarShowBattlegrounds = true, calendarShowLockouts = true}
	ctx.calendar = newCalendar(events, ctx.cvars)
	local function setCVar() ctx.cvarWrites = ctx.cvarWrites + 1 end
	local env = {
		GetCVarBool = function(name) return ctx.cvars[name] end,
		SetCVar = setCVar,
		C_CVar = {SetCVar = setCVar, SetCVarBitfield = setCVar},
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
		C_Map = stubTable({GetMapInfo = function() return {mapType = 3} end}),
		Enum = {UIMapType = {Continent = 2, Zone = 3}},
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

return {Holidays = qcHolidays, Print = qcPrintHolidays,
	Active = function() return qcActiveHolidays end, Why = function() return qcCalendarWhy end}]]
			end
			local chunk = assert(loadstring(source, "@" .. ADDON_DIR .. "/" .. file))
			setfenv(chunk, env)
			local result = chunk("QuestCompletist", addonTable)
			if file == "qcCore.lua" then ctx.core = result end
		end
	end
	assert(ctx.core and ctx.core.Print, "qcPrintHolidays not found in qcCore.lua")
	ctx.env = env

	-- Events go through the handler the addon's own frame registers, so one it never registered never arrives.
	local frame = setmetatable({}, {__index = function() return dummy end})
	ctx.registered = {}
	function frame:RegisterEvent(event) ctx.registered[event] = true end
	function frame:SetScript(name, fn) if name == "OnEvent" then ctx.onEvent = fn end end
	env.qcQuestCompletistUI_OnLoad(frame)
	assert(ctx.onEvent, "the addon's frame sets no OnEvent script")
	function ctx.dispatch(event, ...)
		if ctx.registered[event] then return pcall(ctx.onEvent, frame, event, ...) end
		return true
	end

	-- A map that keeps what was drawn on it, as the player sees it.
	local map = {drawn = {}}
	function map:GetMapID() return self.mapId end
	function map:RemoveAllPinsByTemplate(template)
		if template == "qcPinTemplate" then self.drawn = {} end
	end
	function map:AcquirePin(template, pinData)
		if template == "qcPinTemplate" then self.drawn[#self.drawn + 1] = pinData end
	end
	local provider = env.qcMapDataProvider
	provider.GetMap = function() return map end
	env.qcContinentDataProvider.GetMap = function() return map end
	local draw = provider.RefreshAllData
	provider.RefreshAllData = function(self) ctx.redraws = ctx.redraws + 1 return draw(self) end
	ctx.map = map

	ctx.calendar.fire = function() ctx.dispatch("CALENDAR_UPDATE_EVENT_LIST") end
	function ctx.flush()
		local timers = ctx.timers
		ctx.timers = {}
		for _, fn in ipairs(timers) do fn() end
	end
	function ctx.login() return ctx.dispatch("PLAYER_ENTERING_WORLD", true, false) end
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

	-- The first pin whose quests are all one holiday's.
	local flags = {}
	for _, entry in ipairs(ctx.core.Holidays) do flags[entry.name] = entry.flag end
	local mapIds = {}
	for mapId in pairs(env.qcPinDB) do mapIds[#mapIds + 1] = mapId end
	table.sort(mapIds)
	ctx.pins = {}
	for _, holidayName in ipairs({"Lunar Festival", "Darkmoon Faire", ANNIVERSARY, CUPS, GNOMEREGAN_RUN, DUOS, SCARAB}) do
		for _, mapId in ipairs(mapIds) do
			for _, pin in ipairs(env.qcPinDB[mapId]) do
				local allOfIt = #pin[6] > 0
				for _, questId in ipairs(pin[6]) do
					if env.qcQuestHoliday[questId] ~= flags[holidayName] or not env.qcQuestDatabase[questId] then allOfIt = false end
				end
				if allOfIt and not ctx.pins[holidayName] then
					ctx.pins[holidayName] = {mapId = mapId, questId = pin[6][1], name = pin[3]}
				end
			end
		end
		local probe = ({[ANNIVERSARY] = 47254, [CUPS] = 79125, [GNOMEREGAN_RUN] = 47709, [DUOS] = 86503, [SCARAB] = 45747})[holidayName]
		assert(flags[holidayName], "qcHolidays has no entry named " .. holidayName)
		assert(ctx.pins[holidayName] or (probe and not env.qcQuestDatabase[probe]), "no pin of the " .. holidayName .. "'s quests in the data")
	end
	for _, mapId in ipairs(mapIds) do
		for _, pin in ipairs(env.qcPinDB[mapId]) do
			if pin[6][1] == GUEST_RELATIONS and not ctx.pins.guestRelations then
				ctx.pins.guestRelations = {mapId = mapId, questId = pin[6][1], name = pin[3]}
			end
		end
	end
	assert(ctx.pins.guestRelations or not env.qcQuestDatabase[GUEST_RELATIONS], "no pin of quest " .. GUEST_RELATIONS .. " in the data")
	ctx.pin = ctx.pins["Lunar Festival"]
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
	check("the addon listens for the calendar's event", ctx.registered.CALENDAR_UPDATE_EVENT_LIST == true)
	local ok, err = ctx.login()
	check("login is handled", ok, err and tostring(err))
	check("the calendar is asked for its events", ctx.calendar.openCalls == 1, "OpenCalendar calls: " .. ctx.calendar.openCalls)
	ctx.dispatch("PLAYER_ENTERING_WORLD", false, false)
	check("a zone change doesn't ask again", ctx.calendar.openCalls == 1, "OpenCalendar calls: " .. ctx.calendar.openCalls)
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
	check("the event redraws nothing", ctx.redraws == redrawsBefore)
	ctx.openMap()
	check("a map drawn meanwhile has no answer, and says why", ctx.active() == "nil" and ctx.core.Why() == "its window is open on another month",
		"answer: " .. ctx.active() .. ", " .. tostring(ctx.core.Why()))
	check("the window's month is left alone", ctx.calendar.shown.month == 12 and ctx.calendar.monthCalls == 0)
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

print("Another addon sets the calendar's month with Blizzard's window closed")
do
	local ctx = load(quietOctober())
	ctx.login()
	ctx.calendar.reply()
	ctx.openMap()
	ctx.flush()
	check("the answer is known", ctx.active() == "0", "answer: " .. ctx.active())
	local monthCallsBefore, redrawsBefore = ctx.calendar.monthCalls, ctx.redraws
	ctx.calendar.api.SetAbsMonth(12, 2026)
	ctx.flush()
	check("the event doesn't move the month back", ctx.calendar.shown.month == 12 and ctx.calendar.monthCalls == monthCallsBefore + 1,
		"month " .. ctx.calendar.shown.month .. ", month changes by the addon: " .. (ctx.calendar.monthCalls - monthCallsBefore - 1))
	check("and redraws nothing", ctx.redraws == redrawsBefore)

	local early = load(quietOctober())
	early.calendar.api.SetAbsMonth(12, 2026)
	check("before the first answer the event still doesn't move the month", early.calendar.shown.month == 12 and early.calendar.monthCalls == 1,
		"month " .. early.calendar.shown.month .. ", month changes: " .. early.calendar.monthCalls)
	check("it asks for a redraw, which reads", early.timers[1] ~= nil)
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

print("The Holidays filter is unticked, the Lunar Festival is running and the month has a raid lockout")
do
	local ctx = load(withLockout({LUNAR_FESTIVAL}))
	ctx.cvars.calendarShowHolidays = false
	ctx.login()
	ctx.openMap()
	ctx.calendar.reply()
	ctx.flush()
	check("the calendar shows the lockout and not the holiday", ctx.calendar.shown.month == NOW.month and
		ctx.calendar.api.GetNumDayEvents(0, 14) == 1 and ctx.calendar.api.GetNumDayEvents(0, 5) == 0)
	check("the pin of the running holiday is shown", ctx.pinShown(), "answer: " .. ctx.active())
	ctx.core.Print()
	local said = table.concat(ctx.chat, "\n")
	local noted = said:match("The calendar window's \"Holidays\" filter is unticked, so the calendar can't show these holidays and their quests are all shown: ([^\n]*)%.")
	local rightHolidays = noted ~= nil and noted:find("Lunar Festival", 1, true) ~= nil and noted:find("Darkmoon", 1, true) == nil
	check("/qc holidays says which filter hides which holidays", rightHolidays, not rightHolidays and (noted or said) or nil)
	check("and doesn't list them as missing from the calendar", said:find("Lunar Festival: not on the calendar", 1, true) == nil)
	local neverOnCalendar = 0
	for _, entry in ipairs(ctx.core.Holidays) do
		if #entry.eventIDs == 0 then neverOnCalendar = bit.bor(neverOnCalendar, entry.flag) end
	end
	check("a holiday that is never on the calendar stays hidden", neverOnCalendar > 0 and bit.band(ctx.core.Active(), neverOnCalendar) == 0,
		"answer: " .. ctx.active())
	check("the addon changed no setting", ctx.cvarWrites == 0, "writes: " .. ctx.cvarWrites)
end

print("The Holidays filter is unticked and the month has nothing else")
do
	local ctx = load({LUNAR_FESTIVAL})
	ctx.cvars.calendarShowHolidays = false
	ctx.login()
	ctx.openMap()
	ctx.calendar.reply()
	ctx.flush()
	check("the calendar has no answer, and says why", ctx.active() == "nil" and ctx.core.Why() == "it has no events this month",
		"answer: " .. ctx.active() .. ", " .. tostring(ctx.core.Why()))
	check("the pin is shown", ctx.pinShown())
end

print("The player unticks and ticks the Holidays filter after the calendar has answered")
do
	local ctx = load(withLockout(quietOctober()))
	ctx.login()
	ctx.openMap()
	ctx.calendar.reply()
	ctx.flush()
	check("the pin is hidden: the Lunar Festival isn't running", not ctx.pinShown(), "answer: " .. ctx.active())
	local redrawsBefore = ctx.redraws
	ctx.cvars.calendarShowHolidays = false
	ctx.calendar.fire()
	ctx.flush()
	check("unticking redraws the open map once", ctx.redraws == redrawsBefore + 1, "redraws: " .. (ctx.redraws - redrawsBefore))
	check("the pin is shown", ctx.pinShown(), "answer: " .. ctx.active())
	redrawsBefore = ctx.redraws
	ctx.calendar.fire()
	ctx.flush()
	check("the same answer again redraws nothing", ctx.redraws == redrawsBefore)
	ctx.cvars.calendarShowHolidays = true
	ctx.calendar.fire()
	ctx.flush()
	check("ticking redraws it once more", ctx.redraws == redrawsBefore + 1, "redraws: " .. (ctx.redraws - redrawsBefore))
	check("the pin is hidden again", not ctx.pinShown(), "answer: " .. ctx.active())
	check("the addon changed no setting", ctx.cvarWrites == 0, "writes: " .. ctx.cvarWrites)
end

print("The Holidays filter holds the whole month's events, and is unticked and ticked again")
do
	local ctx = load({holiday(324, "Hallow's End", at(10, 18, 4), at(11, 2, 4))})
	ctx.login()
	ctx.openMap()
	ctx.calendar.reply()
	ctx.flush()
	check("the pin is hidden: the Lunar Festival isn't running", not ctx.pinShown(), "answer: " .. ctx.active())
	ctx.cvars.calendarShowHolidays = false
	ctx.calendar.fire()
	ctx.flush()
	check("unticking leaves the month empty, and shows the pin", ctx.pinShown(), "answer: " .. ctx.active())
	ctx.cvars.calendarShowHolidays = true
	ctx.calendar.fire()
	ctx.flush()
	check("ticking hides it again", not ctx.pinShown(), "answer: " .. ctx.active())
end

print("The filter is ticked again while Blizzard's calendar window is open on another month")
do
	local ctx = load(withLockout(quietOctober()))
	ctx.cvars.calendarShowHolidays = false
	ctx.login()
	ctx.openMap()
	ctx.calendar.reply()
	ctx.flush()
	check("the pin is shown while it's unticked", ctx.pinShown(), "answer: " .. ctx.active())
	ctx.cvars.calendarShowHolidays = true
	ctx.calendar.shown = {year = 2026, month = 12}
	ctx.calendarFrame = {IsShown = function() return true end}
	ctx.openMap()
	check("the read can't be made, and the answer taken while it was unticked isn't trusted", ctx.pinShown(), "answer: " .. ctx.active())
end

print("Only the Darkmoon Faire filter is unticked")
do
	local ctx = load(withLockout(quietOctober()))
	ctx.cvars.calendarShowDarkmoon = false
	ctx.login()
	ctx.calendar.reply()
	ctx.flush()
	ctx.pin = ctx.pins["Darkmoon Faire"]
	ctx.openMap()
	check("a Darkmoon Faire pin is shown", ctx.pinShown(), "answer: " .. ctx.active())
	ctx.pin = ctx.pins["Lunar Festival"]
	ctx.openMap()
	check("a Lunar Festival pin is still hidden out of season", not ctx.pinShown(), "answer: " .. ctx.active())
	ctx.cvars.calendarShowDarkmoon = true
	ctx.pin = ctx.pins["Darkmoon Faire"]
	ctx.openMap()
	check("ticked again, the Darkmoon Faire isn't running, so its pin is hidden", not ctx.pinShown(), "answer: " .. ctx.active())
end

print("WoW's Anniversary: its yearly row shows its pins, a per-region row doesn't")
if not first.pins[ANNIVERSARY] then
	print("  no pin of WoW's Anniversary's quests in this game's data: skipped")
else
	local anniversary = {
		yearly = holiday(1808, "WoW's 22nd Anniversary", at(10, 5, 10), at(10, 26, 10)),
		perRegion = holiday(1587, "WoW's Anniversary", at(10, 5, 10), at(10, 26, 10)),
	}
	for _, case in ipairs({{nil, false, "out of season"}, {"perRegion", false, "with only the per-region row 1587 running"},
		{"yearly", true, "with the yearly row 1808 running"}}) do
		local events = quietOctober()
		if case[1] then events[#events + 1] = anniversary[case[1]] end
		local ctx = load(withLockout(events))
		ctx.login()
		ctx.calendar.reply()
		ctx.flush()
		for _, which in ipairs({ANNIVERSARY, "guestRelations"}) do
			ctx.pin = ctx.pins[which]
			if ctx.pin then
				ctx.openMap()
				check(string.format("%s, the anniversary's pin of quest %d is %s", case[3], ctx.pin.questId, case[2] and "shown" or "hidden"),
					ctx.pinShown() == case[2], "answer: " .. ctx.active())
			end
		end
	end
end

print("The Skyriding Cups: one flag, so a cup's pin shows while any cup runs")
if not first.pins[CUPS] then
	print("  no pin of the Skyriding Cups' quests in this game's data: skipped")
else
	for _, case in ipairs({{nil, false, "out of season"},
		{holiday(1395, "Kalimdor Cup", at(10, 6, 0), at(10, 20, 0)), true, "with the Kalimdor Cup (1395) running"},
		{holiday(1429, "Northrend Cup", at(10, 6, 0), at(10, 20, 0)), true, "with the Northrend Cup (1429) running"}}) do
		local events = quietOctober()
		if case[1] then events[#events + 1] = case[1] end
		local ctx = load(withLockout(events))
		ctx.login()
		ctx.calendar.reply()
		ctx.flush()
		ctx.pin = ctx.pins[CUPS]
		ctx.openMap()
		check(string.format("%s, the cups' pin of quest %d is %s", case[3], ctx.pin.questId, case[2] and "shown" or "hidden"),
			ctx.pinShown() == case[2], "answer: " .. ctx.active())
		if case[1] then
			ctx.core.Print()
			local said = table.concat(ctx.chat, "\n")
			local found = said:find(string.format("Running|r %s (%d)", case[1].title, case[1].eventID), 1, true) ~= nil
			check("/qc holidays lists it as running, under the cup's own name and ID", found, not found and said or nil)
		end
	end
end

for _, entry in ipairs({
	{name = GNOMEREGAN_RUN, title = "The Great Gnomeregan Run: its pin shows only while row 696 runs", running = {
		holiday(696, GNOMEREGAN_RUN, at(10, 9, 0), at(10, 11, 0))}},
	{name = DUOS, title = "Dastardly Duos: its pins show while any of its rows runs", running = {
		holiday(1689, DUOS, at(10, 6, 8), at(10, 20, 8)), holiday(1599, DUOS, at(10, 5, 8), at(10, 19, 8))}},
	{name = SCARAB, title = "Call of the Scarab: its turn-ins' pins show only while row 638 runs", running = {
		holiday(638, SCARAB, at(10, 9, 0), at(10, 12, 0))}},
}) do
	print(entry.title)
	if not first.pins[entry.name] then
		print("  no pin of the quests of " .. entry.name .. " in this game's data: skipped")
	else
		local cases = {{nil, false, "out of season"}}
		for _, event in ipairs(entry.running) do
			cases[#cases + 1] = {event, true, string.format("with %s (%d) running", event.title, event.eventID)}
		end
		for _, case in ipairs(cases) do
			local events = quietOctober()
			if case[1] then events[#events + 1] = case[1] end
			local ctx = load(withLockout(events))
			ctx.login()
			ctx.calendar.reply()
			ctx.flush()
			ctx.pin = ctx.pins[entry.name]
			ctx.openMap()
			check(string.format("%s, the pin of quest %d is %s", case[3], ctx.pin.questId, case[2] and "shown" or "hidden"),
				ctx.pinShown() == case[2], "answer: " .. ctx.active())
			if case[1] then
				ctx.core.Print()
				local said = table.concat(ctx.chat, "\n")
				local found = said:find(string.format("Running|r %s (%d)", case[1].title, case[1].eventID), 1, true) ~= nil
				check("/qc holidays lists it as running, under its own name and ID", found, not found and said or nil)
			end
		end
	end
end

print("/qc holidays lists every ID of an entry the calendar has in the next 12 months, soonest first, each once")
do
	local function on(year, month, day) return {year = year, month = month, monthDay = day, hour = 0, minute = 0} end
	local events = quietOctober()
	events[#events + 1] = holiday(1405, "Hallow's End", on(2027, 7, 25), on(2027, 8, 8))
	events[#events + 1] = holiday(1400, "Eastern Kingdoms Cup", on(2027, 8, 24), on(2027, 9, 7))
	events[#events + 1] = holiday(1395, "Kalimdor Cup", on(2027, 2, 23), on(2027, 3, 9))
	for month = 11, 12 do
		events[#events + 1] = holiday(479, "Darkmoon Faire", on(2026, month, 1), on(2026, month, 7), "calendarShowDarkmoon")
	end
	local ctx = load(withLockout(events))
	ctx.login()
	ctx.calendar.reply()
	ctx.flush()
	ctx.core.Print()
	local said = "\n" .. table.concat(ctx.chat, "\n") .. "\n"
	local hallows = said:find("\n  Hallow's End (324): 2026-10-18 04:00 to 2026-11-02 04:00\n    Hallow's End (1405): 2027-07-25 00:00 to 2027-08-08 00:00\n", 1, true) ~= nil
	check("Hallow's End's second ID, 1405, has a line of its own under 324's", hallows, not hallows and said or nil)
	local _, faires = said:gsub("Darkmoon Faire %(479%)", "")
	check("the Darkmoon Faire's 479, on the calendar in two months, has one line", faires == 1, faires ~= 1 and ("lines: " .. faires) or nil)
	local cupsFlag, cupsInUse = nil, false
	for _, entry in ipairs(ctx.core.Holidays) do if entry.name == CUPS then cupsFlag = entry.flag end end
	for _, flag in pairs(ctx.env.qcQuestHoliday) do if flag == cupsFlag then cupsInUse = true end end
	if cupsInUse then
		local cups = said:find("\n  Kalimdor Cup (1395): 2027-02-23 00:00 to 2027-03-09 00:00\n    Eastern Kingdoms Cup (1400): 2027-08-24 00:00 to 2027-09-07 00:00\n", 1, true) ~= nil
		check("the cups' two IDs in the 12 months each have a line, the soonest first", cups, not cups and said or nil)
	else
		print("  no quest of this game has the Skyriding Cups' flag: the cups' lines skipped")
	end
	local others = said:match("Other calendar holidays, not tied to any quest:\n(.*)$") or ""
	local apart = not others:find("(1405)", 1, true) and not others:find("(479)", 1, true) and not (cupsInUse and others:find("(1400)", 1, true))
	check("none of the entries' IDs is among the other calendar holidays", apart, not apart and others or nil)
end

print("The game has none of the filters' CVars")
do
	local ctx = load(withLockout(quietOctober()))
	for name in pairs(ctx.cvars) do ctx.cvars[name] = nil end
	ctx.login()
	ctx.openMap()
	ctx.calendar.reply()
	ctx.flush()
	check("nothing counts as unticked: the pin is hidden out of season", not ctx.pinShown(), "answer: " .. ctx.active())
	ctx.core.Print()
	check("/qc holidays names no filter", not table.concat(ctx.chat, "\n"):find("unticked", 1, true))
end

print(failures == 0 and "All checks passed." or (failures .. " check(s) failed."))
os.exit(failures == 0 and 0 or 1)
