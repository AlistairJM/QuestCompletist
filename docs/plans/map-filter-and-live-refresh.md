# Map pin filtering and live refresh

## Goal

Two linked pieces of work in `QuestCompletist/qcCore.lua`, one PR each:

1. **One filter for the map and the list.** The map pins run their own copy of the quest filters.
   Make them share the list's filter, and filter each pin once instead of 11 times.
2. **Keep the map and list current, and stop the list jumping.** Quest events should update what's
   on screen, and walking into a new subzone shouldn't reset what the player is looking at.

PR 1 is a pure refactor: the map must draw exactly what it draws today. PR 2 changes behaviour and
needs checking in game. PR 2 starts from master after PR 1 merges (not stacked).

## PR 1: one filter for the map and the list

### What's there today

`qcMapDataProvider:RefreshAllData` (qcCore.lua:1964, ~250 lines):

- Deep-copies the map's pins (`qcCopyTable(qcPinDB[UiMapID])`), then runs 11 passes over them (no data,
  low level, completed, faction, race/class, seasonal, in progress, covenant, warband, requirements
  not met, profession). Each pass removes quests with `table.remove`, which shifts the rest of the list,
  and then removes any pin that's left empty.
- Calls `UnitLevel`, `UnitQuestTrivialLevelRange`, `UnitFactionGroup`, `UnitRace`, `UnitClass` and
  `string.upper` once per quest inside the loops. `GetLogIndexForQuestID` is called twice per quest.
- Re-implements the faction, race/class, covenant, profession and low-level rules that
  `qcBuildQuestFilter` (qcCore.lua:456) already has for the list. The two copies have drifted apart before
  (PR #77).

The busiest maps have 185–241 pins (862, 680, 895, 627, 2022).

### Why one pass gives the same result

Every map filter decides one quest at a time from the character's state and the quest's own data.
None of them looks at the other quests on the pin. The daily/weekly "one of these" groups
(`simulateExclusiveCompletions`) are worked out from the quest log and completions, not from pin
contents. So running all the checks together on each quest, then dropping empty pins, gives the same
quests as running the passes one after another. Keeping the surviving pins in their `qcPinDB` order keeps
`qcMergeStackedPins` (which depends on order) the same.

Measured on master, and needed for the shared filter to match the map's current checks exactly:
- No quest has a nil level (field 3), so `(e[3] or 0)` in the list filter and the map's direct read agree.
- Covenant (field 12) is 0 on 34,246 quests and positive on 777. None is nil or negative, so the list's
  `~= 0` and the map's `> 0` agree.
- No pin has fields beyond 1–6 today, but the code reads a note from `pinData[7]`, so the copy must
  carry every field except the quest list.

### Design

1. **Give `qcBuildQuestFilter` a scope.** `qcBuildQuestFilter("list")` / `qcBuildQuestFilter("map")`
   picks which settings to read:

   | Check | List setting | Map setting |
   |---|---|---|
   | Low level | `QC_L_HIDE_LOWLEVEL` | `QC_M_HIDE_LOWLEVEL` |
   | Profession | `QC_L_HIDE_PROFESSION` | `QC_M_HIDE_PROFESSION` |
   | Daily / repeatable / world type | `QC_L_HIDE_*QUEST` | not used |
   | Faction, race/class, covenant | `QC_ML_*` | `QC_ML_*` |

   The list's completion and warband checks stay outside the filter, as they are now, because the
   completion counter depends on that (see the comment above `qcBuildQuestFilter`).

2. **Add a map-only check built once per refresh**, `qcBuildMapQuestFilter()`. It calls the shared
   filter, then applies the map-only checks: completed (plus the "one of these" groups), in progress
   (plus the groups), seasonal (active holidays read once), warband, and requirements not met (player
   level read once). Anything that reads the character (level, cutoff, faction/race/class bits,
   covenant, professions, holidays, "one of these" groups) is looked up once, not per quest.

3. **Handle quests with no data the way the map does today.** If a pin's quest isn't in
   `qcQuestDatabase`:
   - hide it when `QC_M_HIDE_NODATA` is on;
   - also hide it when `QC_M_HIDE_LOWLEVEL` is on (the current low-level pass does this);
   - otherwise keep it: the identity, profession, seasonal, covenant and requirements checks all skip
     quests with no data. The completed, in-progress and warband checks run on the quest ID, so they
     still apply.

   Hiding no-data quests under the low-level filter looks accidental. It's out of scope here and
   listed under "Found along the way".

4. **Rewrite `RefreshAllData`:**
   ```
   local keep = qcBuildMapQuestFilter()
   local pins = {}
   for _, pin in ipairs(qcPinDB[UiMapID]) do
       local quests = {}
       for _, questId in ipairs(pin[6]) do
           if keep(questId) then quests[#quests + 1] = questId end
       end
       if #quests > 0 then
           local copy = {}               -- shallow: every field except the quest list
           for k, v in pairs(pin) do copy[k] = v end
           copy[6] = quests
           pins[#pins + 1] = copy
       end
   end
   for _, pinData in ipairs(qcMergeStackedPins(pins)) do map:AcquirePin("qcPinTemplate", pinData) end
   ```
   `qcPinDB` is never changed. The reachability check depends on this, and so do later refreshes.
   The module-level `qcPins` table goes away.

5. **Keep the list's behaviour the same.** `qcGetCategoryQuests` and `qcGetZoneCompletionStats` call
   `qcBuildQuestFilter("list")`.

### Verification

1. **Reachability report, byte-identical.** Run
   `& "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-QuestReachability.lua` on master and on the
   branch, then diff `tools/reachability-report.txt`. It drives the real `RefreshAllData` with every
   filter off, and with the identity, profession, seasonal, no-data and requirements filters on.
   The harness returns `qcBuildQuestFilter` through a trailer. If its signature changes, the harness
   must still get the list filter (`BuildQuestFilter = function() return qcBuildQuestFilter("list") end`),
   and that change goes in the same PR.
2. **Old-vs-new comparison (scratch script, not committed).** The reachability check never varies
   completions, the quest log, level or renown, so it doesn't cover the completed, in-progress,
   warband, low-level and "one of these" paths. Load master's `qcCore.lua` and the branch's into two
   separate environments using the harness's stand-ins. Then draw every map with both and compare the
   drawn pins: same keys, same quest lists, same order, same stacks. Combinations to cover:
   - settings: all off, all on, each map filter on alone, and ~50 random combinations;
   - characters: a few faction/race/class/covenant profiles, level 30 and max, random completion sets
     (including C = 2 marks), random quest-log contents, renown 0 and max, warband completions.

   Any difference is a bug in the new code unless it's shown to be one in the old code. In that case,
   stop and raise it; don't fix it silently.
3. **Timing in game.** Add a temporary `debugprofilestop()` around `RefreshAllData` (not committed).
   Open maps 862 and 2022 with all map filters on and record ms before and after.
4. **Smoke test in game.** Open a few zones, toggle each map filter, and check the pins and tooltips.
   `luac -p` passes.

## PR 2: keep the map and list current

### What the code does today (confirm each in game first)

Each item below comes from reading the code. Step 0 of the PR is to reproduce each one in game. Drop
any that doesn't reproduce.

| # | Symptom | Cause |
|---|---|---|
| a | A quest turned in or accepted with the map open keeps its pin until you change maps. | `RefreshAllData` only runs when Blizzard's map opens or changes map, on `ADVENTURE_MAP_OPEN`, and when a filter changes. No quest event triggers it. |
| b | With "hide completed" on, a quest you just turned in stays in the list with a green tick, and the "x/y Complete" counter doesn't move until you pick the category again. | The quest events call `qcUpdateQuestList(nil, pos)`. With no category, that only redraws the 16 rows from the list already built, so nothing is filtered again and the counter isn't recomputed. |
| c | Crossing a subzone boundary while browsing another category jumps the list back to your zone, scrolls to the top, and **clears the search box**. | `ZONE_CHANGED` (every subzone) → `qcZoneChangedNewArea` → `qcUpdateQuestList(zoneCategory, 1)`, which also does `qcSearchBox:SetText("")`. |
| d | Work repeated for no benefit. | `QUEST_LOG_UPDATE` repeats the breadcrumb, new-data and exclusive checks that `QUEST_DETAIL`/`QUEST_PROGRESS` already ran. The 2026-09-30 probe showed `GetQuestID()` is 0 there once the quest window closes. `QUEST_COMPLETE` is registered but has no handler. |

To reproduce in game:
- (a) windowed map open, then auto-complete a quest from the objective tracker; accept a quest; abandon one.
- (b) turn on "hide completed" in the list, keep the window open, and turn in a quest from it.
- (c) keep the window open on another zone's category (or with a search typed), and walk across a subzone.

### Design

1. **Separate choosing what to show from refreshing it.** As built, this is a lighter split than first
   planned. `qcUpdateQuestList` keeps its three modes (pick a category, search, redraw rows) but no
   longer clears the search box itself; the menu actions already did that. It now records
   `qcCurrentSearchText`, and draws rows from the slider's clamped value, so a list that shrinks under
   the scroll position still fills all 16 rows. The new `qcRefreshQuestList()` rebuilds the current
   view (category or search) at the current scroll position. Events, filter changes and opening the
   window call it.

2. **Batch refreshes: at most one per frame.** `qcRequestRefresh(list, map)` sets flags and schedules
   one `C_Timer.After(0, qcFlushRefresh)`. The flush rebuilds the list if the window is shown, and calls
   `qcMapDataProvider:RefreshAllData()` if `WorldMapFrame:IsShown()`. If a window is hidden, nothing
   runs; it gets rebuilt when it's opened.

3. **Event → refresh:**

   | Event | List | Map |
   |---|---|---|
   | `QUEST_TURNED_IN` (after recording) | rebuild | yes |
   | `QUEST_ACCEPTED`, `QUEST_REMOVED` (abandon) | rows | yes (in progress, "one of these" groups) |
   | `UNIT_QUEST_LOG_CHANGED` ("player") | rows | no |
   | server completion sync with new marks | rebuild | yes |
   | filter change (`qcApplyFilterChange`) | rebuild, keep scroll | yes |
   | "clear update cache" menu action | rebuild | yes |
   | shift/alt-click to mark a quest by hand | rows | yes |
   | `QUEST_LOG_UPDATE` | nothing (stop listening; drop the handler) | no |
   | `QUEST_COMPLETE` | handled like `QUEST_PROGRESS` | — |

   Keep the quest ID shown in the NPC frame title. `QUEST_DETAIL`, `QUEST_PROGRESS` and
   `QUEST_ITEM_UPDATE` already do that without `QUEST_LOG_UPDATE`. On the **reward page**, though,
   `QUEST_LOG_UPDATE` was the only thing setting the title and running the breadcrumb, new-data and
   exclusive checks. `QUEST_COMPLETE` was registered but had no handler, so it now does what
   `QUEST_PROGRESS` does.

   Marking a quest by hand only redraws the rows, even with "hide completed" on. That way a quest
   marked by mistake stays on screen to be unmarked. The counter catches up on the next rebuild.

4. **Zone following.** Keep track of the category the player's current zone maps to (`qcZoneCategoryID`).
   On `ZONE_CHANGED_NEW_AREA` / `ZONE_CHANGED`:
   - work out the new zone's category; if it's unchanged, do nothing (this fixes the scroll reset on
     subzone changes within the same zone);
   - if the list is **hidden**, always follow, so opening it shows where you are (as today);
   - if it's **shown**, follow only when it's showing the old zone's category and no search is typed.
     If the player went off to another category or typed a search, leave it alone.

5. **Harness.** Nothing in the reachability check drives events, and `C_Timer` resolves to its dummy
   stand-in, so it should load unchanged. Rerun it anyway; the report should be byte-identical.

### Verification

- Before and after, in game, the reproduction steps above for (a), (b) and (c).
- A burst of quest events (turning in several quests quickly, or accepting a chain) gives one map
  refresh per frame, not one per event. Check with a temporary counter print, not committed.
- Filter change: the list stays where it was scrolled, and the map updates.
- Search: typing, then walking across subzones and zones, leaves the search results in place.
- Reachability report byte-identical; `luac -p` passes.

## Decisions

- **Zone following when the window is open** (agreed 2026-09-30): follow your zone only if you haven't
  gone to another category or typed a search; always follow while the window is hidden. The
  alternative, never switching while the window is open, was turned down.

## Status

- PR 1 done on `refactor/map-quest-filter`. The reachability report is identical to master's (only
  the timestamp line differs). The old-vs-new comparison ran 1,500 random scenarios (3 seeds × 500,
  ~720k map draws, 1.2M pins each) with 0 differences, and `qcPinDB` stayed unchanged. Six deliberate
  breakages of the new code were each caught. Offline timing on maps 862/680/2022 with the map
  filters on: ~0.65 ms → ~0.25 ms per refresh (the stand-in `bit` library is pure Lua, so only the
  ratio means anything). Merged as #95 after the user's in-game check.
- PR 2 on `fix/live-refresh`. A scratch simulation stubs the list UI (slider, rows, search box, map
  visibility, `C_Timer`) and plays the same event sequences through master and the branch. Master
  showed every symptom: (a) 0 map refreshes on turn-in, accept or abandon; (b) the turned-in quest
  stayed listed with the counter unchanged; (c) subzone scroll reset, browsing and search overridden;
  (d) no quest ID on the reward page. The branch fixed all of them, and a burst of 7 events gave 1 map
  refresh. `QUEST_REMOVED` and `QUEST_COMPLETE` were checked against Blizzard's live UI source. The
  reachability report is unchanged. Not yet tested in game.

## Found along the way (not in scope; separate PRs if wanted)

- With the map's low-level filter on, quests with no data are hidden even when "hide quests with no data"
  is off. Probably accidental; changing it changes what's drawn, so it doesn't belong in PR 1.
- `QC_M_HIDE_WORLDQUEST` and `QC_M_HIDE_DAILYREPEATABLE` get defaults in `qcCheckSettings` but have no
  checkbox and nothing reads them.
- `qcPinMixin:OnAcquired` compares `playerLevel >= requiredLevel` with no `or 0`. Safe today (no quest
  has a nil level) but it would error if a pipeline run ever added one.
