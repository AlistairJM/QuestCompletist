# Zone icons on the continent maps

## Goal

The user, 10 October 2026: "At the moment quest pins only appear when you are in each zone's map; you
see nothing when you are on a continent map (eg Eastern Kingdom/Kalimdor), or the world map (where
you see both continents). I am not as concerned about the world map, but on the continent maps,
would it be possible to display an icon, centred on each zone, that lets you see at a glance if you
have outstanding quests in that zone? Maybe some stats when you hover over the icon to give you
counts/progress info. I would want a new option in the options screen to switch off the continent
pins, as some people might not like them. I would probably want daily/weekly/repeatable quests not
counted for the purpose of these new pins."

## What was found

Nine read-only investigations on 10 October 2026, each re-checked by a second reader against the
sources. They read Blizzard's UI code (Gethe/wow-ui-source, branches `live` and `forever`), the local
API docs, the client tables in `tools\`, the installed addons (HandyNotes and others) and our own
code and data under Lua 5.1 stand-ins. **Nothing was run in the game.** Facts below are from source
unless they say otherwise.

- **Why the continents are empty.** Blizzard draws no quest offers, hubs or quest blobs on World,
  Continent and Cosmic maps (`MapUtil.ShouldMapTypeShowQuests`, `MapUtil.lua:29-31`; only the
  super-tracked quest and world quests still show, `QuestDataProvider.lua:181-185`). Our provider is
  refreshed on every map change, a continent included, and returns early because `qcPinDB` has no
  entry for it ([qcMapPins.lua:494](../../QuestCompletist/qcMapPins.lua)).
- **Blizzard already does the same thing elsewhere.** The Adventure Map's zone summary
  (`Blizzard_AdventureMap/AM_ZoneSummaryDataProvider.lua`) takes `C_Map.GetMapChildrenInfo`, puts a
  pin at the centre of `C_Map.GetMapRectOnMap`, shows "Quests Available" and navigates on click;
  `ZoneLabelDataProvider` centres on the same rectangle. `MapLinkPinMixin` navigates with
  `self:GetMap():SetMapID(id)`, which two installed addons also do from their pins.
- **Both games run the same machinery.** Every C_Map function the feature needs is documented
  identically on retail and Forever, and the map code differs only in gamepad lines and one highlight
  test. One code path serves both; no capability gate is needed.
- **Two continents already carry real pins:** Broken Isles (619, 12 pins, Legion Remix) and Zandalar
  (875, 2 pins).
- **Counting from categories matches the list.** The quest list's zone counter (`qcGetZoneCompletionStats`)
  gives the same total as counting the category's quests, for all 145 retail and 47 Forever groups.
  Each quest sits in one category, so nothing is counted twice. Counting from pins instead disagrees
  with the list by about 16% each way (retail, default filters, Alliance human: 12,516 quests by
  category, 12,697 by pin, 10,560 in both), double-counts 1.3% (retail) to 4.0% (Forever) of quests
  across zones, and needs a roll-up from sub-maps to zones that the addon doesn't have.
- **The cost of categories:** about 10% of retail quests (17.5% on Forever) have no pin, so after a
  click the zone map shows fewer pins than the icon counted. The sweep's "pin every normal quest"
  rule shrinks that over time.
- **Speed.** A whole continent counts in 0.1 to 1.7 ms offline (Eastern Kingdoms 1.3, Kalimdor 1.2),
  so about 2 to 5 ms in game. No cache is needed; it is recounted on each map refresh and on hover.
- **Crowding.** On the minimised map (about 697 x 465) Eastern Kingdoms has 8 icon pairs closer than
  24 px and Kalimdor 4; maximised, 1 to 3. Almost all are a capital against its host zone (Mulgore and
  Thunder Bluff, Dun Morogh and Ironforge, Tirisfal and Undercity, Elwynn and Stormwind, Teldrassil and
  Darnassus, Azuremyst and the Exodar, Eversong and Silvermoon), plus a southern Eastern Kingdoms
  cluster and Darkshore/Felwood. Blizzard's own capital markers sit 1 to 9 px from a city zone's
  centre.
- **Rectangles overlap.** A zone's rectangle is a bounding box: Mulgore sits inside The Barrens'
  box on Forever, and on retail's Kalimdor 22 of 28 centres land inside another zone's box (an
  offline model). Blizzard uses the
  centre as the trigger point of its zone-name banner, which doesn't prove it is a good icon spot.
  Only the game can say where the centre falls.
- **Alternate maps.** Some zones have more than one map ID (Uldum 249/1527, Vale of Eternal Blossoms
  390/1530, The Maw 1543/1960, Azj-Kahet 2255/2256, Arathi 2372/2451, Tirisfal 2070); they share a
  category and a centre. Quel'Thalas (2537) is a Continent-type child of Eastern Kingdoms, gated by a
  player condition, beside the old Eversong and Ghostlands zones, so the zones Eastern Kingdoms
  shows may depend on the character.
- **Gaps in a first version that takes direct zone children.** Dungeon-typed hubs (Dalaran,
  Oribos, Mardum), nested continents and orphan starter maps hold the rest of the quests; sub-zone
  categories (Undermine, Korthia, Garrison Support) under-report by about 770 quests (6%). Forever's
  Zephras Isle (112 quests) hangs off the world map only.

### What the game said (10 October 2026)

The probe's geometry pass was run on retail (12.1.0.69933, 15 continent maps, 434 child rows) and on
Forever (1.60.1.70338, 53 rows), and the dumps were read through the real counting code.

- **The type filter is exact.** `GetMapChildrenInfo(id, Zone)` returns only Zone maps, so the zone list
  needs no second check.
- **The hit test at a zone's centre names the zone itself,** except where a city sits next to its host:
  there it names the neighbour. The capital folds (decision 4) cover those rows.
- **Phased twins arrive with flat rectangles** (zero width and height), not missing ones, so a twin is
  one point and folds into its category's icon.
- **Forever gives 20 icons on Kalimdor and 22 on Eastern Kingdoms.** On the windowed map Eastern Kingdoms
  still has pairs closer than 24 px after the folds.
- **The map's canvas** is 3840 x 2560 with 8 zoom levels on retail and 1002 x 668 with 4 on Forever; the
  window shows 697 x 465 windowed and 1698 x 1131 maximised.
- **What the first version leaves out** (checked against the quest list): Quel'Thalas, a Continent-type
  child of Eastern Kingdoms, holds 929 quests and Argus, a Continent-type child of Broken Isles, 147;
  sub-zone categories (Undermine 218, Korthia 115, Valdrakken 65, Dornogal 47); zones that arrive with
  no rectangle (Founder's Point 52, Razorwind 55, Siren Isle 45); and the alternate Arathi map 2372,
  whose category 1409 holds 24 quests that Arathi Highlands' icon misses.

## Decisions

The user said to go with the recommendations (10 October 2026), so the calls below are taken as
agreed until they say otherwise.

| # | Decision | Why |
|---|---|---|
| 1 | The numbers come from the quest list's zone categories, not the pins | reproduces the list's own "x/y Complete", no double counting, no roll-up; the pin gap is data work that is under way |
| 2 | Counted: a quest in the zone's categories that passes the **map's** filter built for counting, and is not daily, weekly or repeatable (type bits 2, 4 and 128, forced out whatever the filter boxes say). Holiday and profession quests follow the map's filters | the icon is a map element; the map's boxes default to showing dailies, so the exclusion cannot lean on them |
| 3 | The icon shows when something is outstanding (counted and not done). It is bright when a quest is ready to hand in or can be taken now, and dim when only locked quests are left (the grey "?" for quests only in the log is grey already, so it is not dimmed again). No icon when nothing is outstanding | the dim state keeps the signal on a low-level character, as `qcPinGreyed` does for a pin |
| 4 | Capitals are folded into their host zone's icon through a small keyed table, with a sub-line in the tooltip. Phased twins are one icon, deduplicated by category. Every other zone keeps its own icon | removes most crowding and the clash with Blizzard's capital markers without hiding a city's quests; the rows are chosen from the geometry dump |
| 5 | First version: the direct Zone children of each continent map. Hub maps, nested continents (Quel'Thalas, Argus), orphan starter maps and Zephras Isle come later | what the client enumerates by itself; the rest wants the dump and a look |
| 6 | A child option of "Show Map Icons", on by default, saved as `QC_M_SHOW_CONTINENT`. The master switch hides the continent icons too | the user wants an off switch; an off-by-default feature would not be seen |
| 7 | A left click without a modifier opens the zone's map; a right click still zooms out | what Blizzard's own pins and the map's own click do |
| 8 | A new file `qcContinentPins.lua` in both TOCs, with its own data provider, template and mixin; the shared map tooltip helpers move to `qcTooltips.lua` | `qcPinMixin` differs in every method (position units, tooltip, click, template), and the repo prefers structure over a pile of `if continent` branches. The cost is the "restart WoW" line in the changelog |
| 9 | The world map is out of scope; the provider switches on the map's type, so it could be added | the user is not concerned about it |
| 10 | The 14 existing pins on Broken Isles and Zandalar stay | they are real pins, and `qcMapDataProvider` is not touched |

## Design

**Which zones.** `C_Map.GetMapChildrenInfo(continentId, Enum.UIMapType.Zone)`, from the game, with
nothing precomputed. A child is kept when its `mapType` is Zone, its rectangle on the continent is
real (`C_Map.GetMapRectOnMap` gives four numbers with `maxX > minX` and `maxY > minY`; it may give
nothing or zeros, and the calls are `MayReturnNothing`) and `qcAreaIDToCategoryID[mapId]` names a
category. The icon sits at the rectangle's centre. Two children with the same category are one icon,
the one with a rectangle. The zone list is read on every refresh, not cached: the call is dynamic
(scenario maps appear as children during quests).

**The sparse table.** One keyed table in `qcContinentPins.lua`, with both games' map IDs (they don't
collide: Forever's are mostly 14xx), holds what the client can't tell us: a zone's extra categories
(Stranglethorn Vale 224 gets categories 147 and 214; Vashj'ir 203 gets 117, 182, 264 and 1) and a
folded city's host (retail's Stormwind City 84 into Elwynn Forest 37, Ironforge 87 into Dun Morogh 27,
Undercity 90 into Tirisfal Glades 18, Silvermoon City 110 into Eversong Woods 94, Thunder Bluff 88 into
Mulgore 7, Darnassus 89 into Teldrassil 57, the Exodar 103 into Azuremyst Isle 97; Forever's Stormwind
1453, Ironforge 1455, Thunder Bluff 1456, Darnassus 1457 and Undercity 1458 into their zones). Orgrimmar
sits far from Durotar's icon and is left out until the geometry dump says otherwise. The rows come from
the offline analysis, and the dump confirms or trims them. If they pass about 25 per game, they become
a decisions CSV that a tool turns into a generated file, as `qcUnavailableQuests.lua` is.

**Counting.** Two halves, split by where the code lives (the load order is `qcCore.lua`,
`qcTooltips.lua`, `qcMapPins.lua`, then the new file).
- `qcCore.lua` gets one small global function beside `qcGetZoneCompletionStats`, exported through
  `QC`, because `qcCategoryIndex`, `qcBuildQuestIndexes` and `qcIsRecurringQuest` are file-local there
  and the file has few local slots left. It takes a list of categories and a filter, and hands back
  the zone's counted quests: those in the categories that are not recurring (the type bits are tested
  first, so a daily in the log never counts) and pass the filter with `forCount`. The filter is built
  once per refresh with `qcBuildViewFilter("M")`, not once per zone: it reads the calendar and may
  call `C_Calendar.SetAbsMonth`.
- `qcContinentPins.lua` sorts those quests into total, done, ready, in the log, available now and
  locked, with `qcQuestStatus.Of` and `qcPinQuestNeeds(..., true)`; PR 3 exports the second from
  `qcMapPins.lua`, where it is file-local. Done follows the pin bar: `qcIsQuestCompleted`, or another
  character's completion while the warband filter is on. The icon's look and count are worked out at each
  refresh from those numbers (a continent takes 12 ms offline at most, so perhaps 25 to 35 in game: to be
  timed at the look); the tooltip's numbers are read live on hover, because objective changes don't
  refresh the map.

**The pin.** `qcContinentPinTemplate` (24 x 24, a texture and a count in `NumberFontNormalSmall`)
and `qcContinentPinMixin`, scaling limits (1, 1, 1), frame level `PIN_FRAME_LEVEL_AREA_POI` like
the zone pins and HandyNotes (the tie against Blizzard's capital markers, which
the folding mostly removes, is settled at the look; the other candidates are the map-highlight and
dig-site levels). The icon is the existing "?" for ready, "!" for takeable, "!" at half shade for
locked and the grey "?" for in the log only (not dimmed again: it is grey already), with the count of the
winning state in the icon's shade. No new art.
`UseFrameLevelType` goes before `SetPosition`, as in `qcPinMixin:OnAcquired`, and every field is
reset on acquire, because pins are pooled. Right-click passthrough is left as Blizzard sets it, so
a right click still zooms out; the left click is handled in `OnMouseClickAction` with
`self:GetMap():SetMapID(zoneMapId)`, so it doesn't depend on which zone is under the cursor.

**The tooltip.** The shared `qcMapTooltip` and its helpers: the zone's name from
`C_Map.GetMapInfo(id).name`, the progress bar (`qcTooltipBar`, done/total, when the total is 2 or
more), then a row with the status icon for each of ready, available, in progress and locked, none
for a zero, and a hint line. Text is the client's wherever it has one (`QUEST_WATCH_QUEST_READY`,
`AVAILABLE_QUESTS`, `IN_PROGRESS`, the click-to-zoom hint, the existing `qcL.PROGRESS`); only the
option's label and its tooltip are new text. It needs no quest or NPC names. A folded city shows as
a sub-line. The anchor is worked out from the pin's normalised position, not by comparing
`GetCenter()` with the canvas size, as `qcPinMixin:OnMouseEnter` does. The current-pin variable that
`QC.RedrawMapTooltip` and the Shift watcher use points at a continent pin only if the pin has an
`OnMouseEnter` of the same shape.

**The option.** `qcIO_M_SHOW_CONTINENT` under `qcIO_M_SHOW_ICONS`, indented 16, with the grid's
labels re-anchored to it ([qcCore.lua:2148](../../QuestCompletist/qcCore.lua)); the panel has room
for this one box (the canvas is about 601 px tall and the stack ends near 541) and not a second.
The default is set in `qcCheckSettings` as `1`, read as "off only when 0", so no
`QC_SETTINGS_VERSION` change and no new saved variable. A click saves and refreshes both providers;
the box is not greyed when the master switch is off, and its tooltip says the master must be ticked
and that daily, weekly and repeatable quests aren't counted. The name starts `QC_M_SHOW_`, not
`QC_M_HIDE_`, so the filter grid and the harness's blanket HIDE sweeps ignore it. Two keys,
`SHOWCONTINENTICONS` and `SHOWCONTINENTICONSTIP`, go into all 11 `Localization` files, translations
marked `-- Needs review`, worded after each language's `SHOWMAPICONS`.

**Refresh.** One function refreshes both providers and replaces the direct calls at
`qcCore.lua:1206`, `:2116` and `:2237`. Blizzard refreshes every provider when the map opens or its
map changes, so browsing up to a continent draws the icons. `qcMapDataProvider` is not changed, so
the reachability report stays byte-identical. A small separate change would also refresh the map on
`PLAYER_LEVEL_UP`, `FACTION_STANDING_CHANGED`, `MAJOR_FACTION_RENOWN_LEVEL_CHANGED`,
`SKILL_LINES_CHANGED` and `COVENANT_CHOSEN` (the API review's proposal), which would fix the zone
pins' staleness too.

**Both games.** The same file in both TOCs. On Forever there is no level range
(`GetMapLevels` answers 0), Zephras Isle gets no icon, and the zone highlight turns off while the
cursor is over an icon (cosmetic, Forever only). `game-parity.md` gets a row for the feature.

## What changes

- New: `QuestCompletist/qcContinentPins.lua`; `QuestCompletist.xml` gets the template; both TOCs list
  the file; 11 `Localization` files get 2 keys.
- `qcCore.lua`: the zone-quests function and its export, the setting's default and `qcApplySettings`
  line, the checkbox and its re-anchoring, the one refresh function.
- `qcTooltips.lua` takes the map tooltip helpers out of `qcMapPins.lua` (its frame, its lines, icons,
  dividers and bar); `qcMapPins.lua` exports `qcPinQuestNeeds`.
- `tools\`: `Test-ContinentPins.lua`, `Test-Settings.lua`, the probe's geometry pass,
  `Report-ContinentGeometry.lua`; `.gitignore` lists the new tests.
- `docs\`: this plan, `open-items.md`, `game-parity.md`, `game-api-review.md`, `maintenance.md`,
  `settings-grid.md`, `README.md` (release PR).

## Pull requests, in order

1. **This plan** and its notes in the other documents.
2. **The probe's geometry pass** (dev-only, ships nothing, so it can merge at once). For every
   cosmic, world and continent map it saves each child of any type with its map type, flags,
   nav-bar validity, map group and rectangle; a hit test (`GetMapInfoAtPosition` at the
   rectangle's centre: does it name the zone itself?); the zone IDs `GetMapChildrenInfo` gives with
   the type filter and with `allDescendants`, which settles whether the filter is exact; and a 60 x
   40 grid of the hit test, which gives each zone's real centre where hovering and clicking land.
   With the world map showing it also notes the window's and the canvas's size. It ends every
   `/qcprobe maps` pass, which each sweep already runs, and `/qcprobe geometry` takes it alone.
   `tools\Report-ContinentGeometry.lua` reads the saved file, lists what is odd on each continent
   (no or flat rectangle, twins, a centre another map takes, icons closer than 24 px at 700, 1000
   and 1500 px) and writes a row per child; the first dump becomes
   `docs/plans/continent-geometry-baseline.csv`. `Test-Probe.lua` covers it with stand-in maps.
   Merge it before the retail 12.1.5 run (13 or 14 October) so one session captures retail;
   Forever's comes with its next session.
3. **The tooltip helpers move** to `qcTooltips.lua`, with the exports. No behaviour change: the
   reachability report must come out byte-identical, and so must a record of every call a pin's
   tooltip makes (`Test-MapTooltip.lua`, run on the code before and after). Done as `QC.qcMapTip`:
   `Open`, `Close`, `Finish`, `Redraw`, `Line`, `LineIcon`, `Divider` and `Bar` over the one
   `qcMapTooltip` frame, with `qcMapTooltipSetup` and `QC.RedrawMapTooltip` beside it; `qcPinMixin`
   keeps its anchor rule, and `qcMapPins.lua` exports `qcPinQuestNeeds`.
4. **Counting and the zone list**, with `Test-ContinentPins.lua`. Nothing visible yet. Done as
   `qcGetZoneQuests` in `qcCore.lua` (exported as `QC.qcZoneQuests`) and the new
   `qcContinentPins.lua` (in both TOCs, after `qcMapPins.lua`): `qcContinentZones`, `qcQuestKind`,
   `qcZoneNumbers`, `qcZoneBrightness` (PR 5 replaced it with `qcZoneLook`) and `qcContinentIcons`.
   Nothing called them in the game until PR 5 added the provider and the pin.
5. **Icons and the option**: template, mixin, provider, the checkbox, the localization keys,
   `Test-Settings.lua`, the documents. Done as:
   - `qcContinentPinTemplate` in `QuestCompletist.xml` (24 x 24, the art and a count in
     `NumberFontNormalSmall`) and, in `qcContinentPins.lua`, `qcContinentPinMixin` (position, art, count and
     shade; the tooltip through `QC.qcMapTip`; a left click opens the zone) and `qcContinentDataProvider`
     (continent maps only, and only with both switches on), added to `WorldMapFrame`;
   - `qcZoneLook` in place of `qcZoneBrightness`: the icon and count come from the same numbers the tooltip
     shows, so the count of the winning state is on the icon;
   - `qcRefreshMapProviders` in `qcCore.lua` refreshes both kinds of pin, and replaces the three direct
     calls to `qcMapDataProvider:RefreshAllData()`;
   - `QC_M_SHOW_CONTINENT` (default 1), its checkbox under "Show Map Icons", the filter grid re-anchored
     to it, and the two keys `SHOWCONTINENTICONS` and `SHOWCONTINENTICONSTIP` in all 11 locale files.
6. **Sweep integration**: the geometry baseline compared on each sweep, `Compare-ApiDocs.ps1` watching
   the values of `Enum.UIMapType` and the fields of `UiMapDetails` (it compares neither), and the
   runbook step. Done as:
   - `Report-ContinentGeometry.lua` returns its rows (and reads them back from a CSV), and
     `Compare-ContinentGeometry.lua <saved variables> <baseline>` lists the zones that came, went or
     moved (more than 0.05 of a map point) and the maps whose type, flags, group, nav-bar listing or
     hit-test answer changed; exit 1 on any, `--update` replaces that game's rows and keeps the other's;
   - `docs/plans/continent-geometry-baseline.csv`, the two dumps above (retail 434 rows, Forever 53);
   - `Compare-ApiDocs.ps1 -Tables` (default `UIMapType`, `UiMapDetails`), the first structures whose
     contents it compares, with `Test-ApiDocs.ps1` at 258 checks; both are documented the same on live
     and Forever today;
   - sweep step 2f and the step 3b instructions in `maintenance.md`, a row in `game-parity.md`.
7. **The release PR**: README (a bullet under "Quest givers on your world map", naming the option as
   the game shows it), a **New** bullet in the changelog, and the restart-WoW line.

PRs 3 to 6 are stacked; retarget each to master before deleting its base.

## Tests

Offline, under `C:\Program Files (x86)\Lua\5.1\lua.exe` (the `lua` on the path is 5.4 and lacks
`loadstring` and `setfenv`):

- **`tools\Test-ContinentPins.lua`**, for both TOCs: a synthetic map world (continent, zones with
  rectangles, a nil and a zero rectangle, twins, a folded city, Stranglethorn's extras); a daily in
  the log doesn't count; unticking "hide completed" doesn't light a zone; with the list's own filter
  the totals equal `qcGetZoneCompletionStats` for every group of both games, and with the map's they
  differ only by what its seasonal filter hides; a real-data pass with the icon and quest counts per
  continent and its timing. The reachability harness needs no stand-ins: the new file stays inert at
  load, because the harness runs files against a catch-all dummy with no `pcall`, and it never calls the
  continent provider; its report is unchanged. `Test-SeasonalCalendar.lua` does call it (through
  `qcRefreshMapProviders`), so it got `C_Map` and `Enum.UIMapType` stand-ins and a map that keeps the
  two kinds of pin apart. PR 5 adds the provider's gates, the pin's art, shade, count and click, and
  `Test-MapTooltip.lua` plays the continent pin's tooltip through the same kit as a zone pin's.
- **`tools\Test-Settings.lua`** (the "90 checks" harness of `settings-grid.md` was never committed):
  defaults on a fresh table, an explicit 0 kept, the migration untouched, the panel builds on both
  TOCs, the box's click saves and redraws both kinds of pin, its tip, and the panel's lowest edge: 568 px
  down a 601 px page, 33 px to spare, worked out from the anchors and the game's font heights. (That the
  keys exist in all 11 files is `Test-Localization.lua`'s.)
- `Test-Localization.lua` must say "No problems".

## To try in game

Only what the game alone can answer, a few lines per game.

- **The probe's dump** (PR 2): it comes with the map pass of the next sweep. It answers what
  `GetMapChildrenInfo` and `GetMapRectOnMap` return for each continent (nil, zeros, which twin has a
  rectangle, what Eastern Kingdoms shows for Quel'Thalas), whether each centre falls on its own
  zone, and where each zone really lies. The real canvas size needs one more step on each game:
  open the world map on Kalimdor, type `/qcprobe geometry`, then maximise the map and type it again.
- **One look at the finished icons, on each game** (about three minutes, five observations):
  1. The icons sit on their zones, not in the sea or on a neighbour, and nothing stacks.
  2. Hovering shows the tooltip, and its totals are close to the list's header for that zone.
  3. A left click opens the zone; a right click zooms out.
  4. Unticking the option removes the icons at once; the options panel is intact in French, the
     widest language (its filter grid has never been seen in game).
  5. Opening a continent map once in combat raises no error (`/console scriptErrors 1`). Setting
     a pin's pass-through buttons is restricted in combat; our zone pins share the exposure and
     have shown no problem, so this is a check, not a known fault. If it fails: skip pins while
     `InCombatLockdown()` and redraw on `PLAYER_REGEN_ENABLED`.
- To settle at the look: the frame level against Blizzard's markers, the icon's size on the minimised
  map (a smaller icon or Blizzard's pin nudging if pairs stay too close), and the wording of the
  "locked" row (the client's `UNAVAILABLE` collides with the addon's "no longer available"; a few
  Korean, Chinese and Russian client strings for ready and in progress read oddly).

## Risks

- The geometry is unobserved: a rectangle's centre can fall on a neighbour or the sea, and retail
  places about 13 zones through links the client resolves itself. Hence the dump before the code.
- The icon counts quests that have no pin (above), and quests whose requirements the character
  doesn't meet. A level 10 character sees many dim icons; the switch is the answer.
- Counts depend on the curated quest type. A one-time quest wrongly typed daily is left out of every
  count; the exclusion is a pure function of the stored type, so later retypes flow through.
- Sub-zone categories under-report (above); the 773 quests are the price of keeping the list's
  parity.
- Eastern Kingdoms may show different zone sets by character (Quel'Thalas).
- A new Lua file: an error at load would break both games, and players must restart WoW.
- 12.1.5 changes six maps and no zone relations; the tree is re-read from the client at run time.

## Left for later

The world map; hub maps and nested continents; a level range in the
tooltip on retail; a toggle in the map's filter menu; `/qc continent`; Shift-click opening the list
at the zone's category; adding Dalaran-style hubs to the groups table.

## Status

- 2026-10-10: investigated; this plan written and the decisions above taken. Nothing built.
- 2026-10-10: PR 2 built (the probe's geometry pass, `Report-ContinentGeometry.lua`, 804 checks in `Test-Probe.lua`); not yet run in game.
- 2026-10-10: PR 3 built (the map tooltip's helpers in `qcTooltips.lua` as `QC.qcMapTip`, `Test-MapTooltip.lua`): the reachability reports of both games and a record of 400-odd tooltip calls are identical to master's; not yet tried in game.
- 2026-10-10: PR 4 built (`qcGetZoneQuests`, `qcContinentPins.lua`, `Test-ContinentPins.lua`): every category counts as many quests as the list's zone counter says (485 retail, 113 Forever); retail's 15 continents give 139 icons and Forever's 2 give 42, with no quest in two icons; a continent pass takes 6 ms at most offline; not yet in game, and nothing draws yet.
- 2026-10-10: PR 5 built (`qcContinentPinTemplate`, `qcContinentPinMixin`, `qcContinentDataProvider`, `qcRefreshMapProviders`, the `QC_M_SHOW_CONTINENT` option and its two strings, `Test-Settings.lua`): the reachability reports of both games and the zone pins' tooltip record are unchanged; the continent pin's tooltip, click, provider and the page's layout (33 px to spare) are checked offline only; not yet tried in game.
- 2026-10-10: both games' geometry dumps read (see "What the game said"). PR 6 built (`Compare-ContinentGeometry.lua`, the baseline CSV, `Compare-ApiDocs.ps1 -Tables`, sweep step 2f): `Test-Probe.lua` 980 checks and `Test-ApiDocs.ps1` 258 pass; each game compares clean against its baseline.
