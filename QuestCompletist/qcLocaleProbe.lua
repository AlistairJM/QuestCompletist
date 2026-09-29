--[[ Diagnostic, run with /qc localecheck. Measures how much of qcLocalize the game client could
supply instead of our own locale files, and which candidate global strings exist for the tooltip
labels that are currently hardcoded English. Writes the full result to the qcLocaleProbeResults
saved variable; delete this file once the answer has been acted on.

The keys of qcAreaIDToCategoryID are UiMap ids, so names come from C_Map.GetMapInfo. They are not
AreaTable ids: C_Map.GetAreaInfo answers for every one of them, with the wrong zone. ]]--

local candidateGlobals = {
	"FACTION", "REPUTATION", "SEARCH", "ID", "ZONE", "LEVEL", "CLASS", "RACE", "CONTINENT",
	"QUESTS_LABEL", "QUEST_LOG", "OBJECTIVES_LABEL", "REQUIREMENTS", "DAILY", "WEEKLY",
	"COMPLETE", "AVAILABLE", "DUNGEONS", "RAIDS", "BATTLEGROUNDS", "OPTIONS", "CLOSE",
	"PROFESSIONS_COOKING", "PROFESSIONS_FISHING", "PROFESSIONS_ARCHAEOLOGY",
	"PROFESSIONS_FIRST_AID", "TRADE_SKILLS", "QUEST_ID", "STORYLINE", "RENOWN_LEVEL_LABEL",
	"LOCALIZED_CLASS_NAMES_MALE",
}

local function qcNormalizeLocaleKey(name)
	return (name:gsub("[^%a%d]", "")):upper()
end

function qcLocaleProbe()
	if not (C_Map and C_Map.GetMapInfo) then
		print("|cFFFF0000Quest Completist:|r C_Map.GetMapInfo is unavailable on this client.")
		return
	end

	local results = {
		locale = GetLocale(),
		generated = date("%Y-%m-%d %H:%M:%S"),
		globals = {},
		categories = {},
		counts = {},
	}

	for _, name in ipairs(candidateGlobals) do
		local value = _G[name]
		if (type(value) == "string") then
			results.globals[name] = value
		elseif (type(value) == "table") then
			results.globals[name] = "<table>"
		else
			results.globals[name] = false
		end
	end

	local ourName = {}
	results.duplicateCategoryIds = {}
	for _, e in ipairs(qcQuestCategories) do
		if ourName[e[1]] then
			table.insert(results.duplicateCategoryIds, string.format("%d: %s / %s", e[1], ourName[e[1]], e[2]))
		end
		ourName[e[1]] = e[2]
	end

	local areasByCat = {}
	for areaId, catId in pairs(qcAreaIDToCategoryID) do
		areasByCat[catId] = areasByCat[catId] or {}
		local info = C_Map.GetMapInfo(areaId)
		table.insert(areasByCat[catId], { id = areaId, name = (info and info.name) or false })
	end

	local counts = {
		categories = 0, noLocaleKey = 0, noArea = 0, areaUnresolved = 0,
		exact = 0, mismatch = 0, ambiguous = 0,
	}
	local mismatches = {}

	for catId, english in pairs(ourName) do
		counts.categories = counts.categories + 1
		local localized = qcLocalize[qcNormalizeLocaleKey(english)]
		local row = { id = catId, english = english, localized = localized or false, areas = {} }
		if not localized then counts.noLocaleKey = counts.noLocaleKey + 1 end

		local areas = areasByCat[catId]
		if not areas then
			counts.noArea = counts.noArea + 1
			row.verdict = "no-area"
		else
			local distinct, distinctCount, resolved, exact = {}, 0, false, false
			for _, a in ipairs(areas) do
				table.insert(row.areas, { id = a.id, name = a.name })
				if a.name then
					resolved = true
					if not distinct[a.name] then distinct[a.name] = true; distinctCount = distinctCount + 1 end
					if (a.name == english) or (localized and a.name == localized) then exact = true end
				end
			end
			row.distinctNames = distinctCount
			if not resolved then
				counts.areaUnresolved = counts.areaUnresolved + 1
				row.verdict = "area-unresolved"
			elseif exact then
				-- Usable, but a category fed by several differently-named areas still needs one picked.
				if distinctCount > 1 then counts.ambiguous = counts.ambiguous + 1; row.verdict = "exact-ambiguous"
				else counts.exact = counts.exact + 1; row.verdict = "exact" end
			else
				counts.mismatch = counts.mismatch + 1
				row.verdict = "mismatch"
				if #mismatches < 200 then
					table.insert(mismatches, string.format("%s -> %s", english, row.areas[1] and tostring(row.areas[1].name) or "?"))
				end
			end
		end
		table.insert(results.categories, row)
	end

	results.counts = counts
	qcLocaleProbeResults = results

	print("|cFF69CCF0Quest Completist locale probe|r (" .. results.locale .. ")")
	print(string.format("  categories: %d   exact match: %d   exact but several area names: %d",
		counts.categories, counts.exact, counts.ambiguous))
	print(string.format("  mismatched: %d   no area id: %d   area id unresolved: %d   no locale key: %d",
		counts.mismatch, counts.noArea, counts.areaUnresolved, counts.noLocaleKey))
	local missingGlobals = 0
	for _, name in ipairs(candidateGlobals) do
		if not results.globals[name] then missingGlobals = missingGlobals + 1 end
	end
	print(string.format("  candidate globals: %d of %d exist", #candidateGlobals - missingGlobals, #candidateGlobals))
	for _, d in ipairs(results.duplicateCategoryIds) do print("   |cFFFF0000duplicate category id|r " .. d) end
	for i = 1, math.min(10, #mismatches) do print("   ~ " .. mismatches[i]) end
	if (#mismatches > 10) then print(string.format("   ...and %d more", #mismatches - 10)) end
	print("  Full results saved to qcLocaleProbeResults - /reload to write them to disk.")
end
