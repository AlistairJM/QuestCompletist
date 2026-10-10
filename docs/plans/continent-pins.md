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
  centre. These counts are for the 24-unit icon; at the 29 units the icon is now on the user's screen
  the windowed map has 14 pairs closer than an icon on retail (Eastern Kingdoms 13, Kalimdor 1) and 6 on
  Forever, and the maximised one 1 on retail (Tol Barad's two, which have no quests) and none on Forever.
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
  Zephras Isle (112 quests) hangs off the world map only. Since then the hubs (but not Mardum), the nested
  continents and the sub-zones except Garrison Support have an icon or count in their zone's, see Design.

### What the game said (10 October 2026)

The probe's geometry pass was run on retail (12.1.0.69933, 15 continent maps, 434 child rows, 442 rows in the baseline with the maps the hit test names that are no child) and on
Forever (1.60.1.70338, 53 rows), and the dumps were read through the real counting code.

- **The type filter is exact.** `GetMapChildrenInfo(id, Zone)` returns only Zone maps, so the zone list
  needs no second check.
- **The hit test at a zone's centre names the zone itself,** except where a city sits next to its host:
  there it names the neighbour. The capital folds (decision 4) cover those rows.
- **Phased twins arrive with flat rectangles** (zero width and height), not missing ones, so a twin is
  one point and folds into its category's icon.
- **Forever gives 20 icons on Kalimdor and 22 on Eastern Kingdoms.** On the windowed map Eastern Kingdoms
  still has pairs closer than an icon (24 units then, 29 now on the user's screen) after the folds.
- **The map's canvas** is 3840 x 2560 with 8 zoom levels on retail and 1002 x 668 with 4 on Forever; the
  window shows 697 x 465 windowed and 1698 x 1131 maximised.
- **The rectangle's centre is not always the middle of the zone.** The game's hit test names the zone at the
  centre of its rectangle for every one of them (the dump's `HitID`), but the cells that name it can lie
  well to one side. At the maximised map (1,698 px wide) 13 of the 135 retail icons with a hit area sit 50 px
  or more from the centre of the cells that name their zone:
  Tiragarde Sound 167 px, Thaldraszus 107, Gorgrond 106, The Jade Forest 95, Townlong Steppes 92, The
  Coiled Isle 85, Hallowfall 84, Dread Wastes 82, Shadowmoon Valley 66, Stormheim 57, Spires of Arak 54,
  Stormsong Valley 54, Durotar 51; on Forever 1 of 42 (Stranglethorn Vale, 55 px). The user saw the first at
  the first look at the finished icons and asked for it to move right, which is `QC_ZONE_ICON_AT` below.
  The others are candidates, not changes. Tiragarde Sound's new place is about 326 px from the nearest icon
  on Kul Tiras (Drustvar) at that width, 134 px windowed, and 0.574, 0.631 is the cells' centre, not a cell:
  that it lies on a Tiragarde cell is not in the dump and is for the look (`/dump
  C_Map.GetMapInfoAtPosition(876, 0.574, 0.631).name` says).
- **What the first version left out** (checked against the quest list): Quel'Thalas, a Continent-type
  child of Eastern Kingdoms, holds 929 quests (870 on its own map's six icons) and Argus, a Continent-type
  child of Broken Isles, 147 (both now get an icon on the outer map, see Design); the alternate Arathi map
  2372, whose category 1409 holds 24 quests that Arathi Highlands' icon missed (now an extra). With those,
  Eastern Kingdoms counts 2,326 quests on 27 icons (it was 1,432 on 26) and the Broken Isles 1,012 on 8 (it
  was 865 on 7). The user's first look then found the hubs missing: Oribos (58 quests), Dalaran (87),
  Undermine (218), Nazjatar (107, on both Zandalar's and Kul Tiras' maps) and Ahn'Qiraj: The Fallen Kingdom
  (4) each stand on a continent map without being a zone of it, and Korthia (115), Valdrakken (65), Dornogal
  (47), City of Threads (12), the Shrine of the Storm (2) and two sub-zones of Quel'Thalas (59) have no place
  of their own (all now counted, see Design), and so are the Druid class hall's Dreamgrove (79). On
  retail, of the 14,708 quests in a zone category, 13,459 are in an icon (12,606 before the hubs and
  sub-zones, which added 853: 474 and 379) and 1,249 are in none; the largest of those (the test prints them each
  run) are Lunarfall Excavation 154, Razorwind Shores 55, Founder's Point 52, Chamber of Heart 46, Siren
  Isle 45, Exile's Reach 34, Manaforge Omega 28, Queen's Conservatory 28 and The Deaths of Chromie 24:
  zones with no rectangle that the hit test never names, garrisons, scenarios and starter areas with no place
  on a continent map. On Forever 1,657 of 1,810 are in an icon (Zephras Isle 90, Alterac Valley 26 and the
  other battlegrounds are most of the rest).
- **What the icon art can bear** (the client's atlas tables, build 12.1.0.69933). The "!" is the atlas
  member `QuestNormal`, 64 x 64 pixels drawn at 32; the ready "?" is `QuestTurnin`, 32 x 32; the grey "?" for
  quests in the log is the file `Interface\GossipFrame\IncompleteQuestIcon`, 16 x 16. The user's screen is
  1440p at UI scale 0.64 (the probe's `uiScale`), so one UI unit is 1.2 screen pixels; the 24-unit icon was
  29 pixels, a little under the "?" art (shrunk) and almost twice the grey file's 16. `QuestTurnin` has no
  64-pixel twin; the nearest is `ui-questpoi-questbangturnin-2x` (64 x 72, drawn for the quest-number disc
  family, its "?" only about 25 x 38 pixels inside the frame), which would want a frame well over 32 units and
  was not tried. The campaign, legendary, important, recurring and wrapper kinds have `-2x` atlases too.

## Decisions

The user said to go with the recommendations (10 October 2026), so the calls below are taken as
agreed until they say otherwise.

| # | Decision | Why |
|---|---|---|
| 1 | The numbers come from the quest list's zone categories, not the pins | reproduces the list's own "x/y Complete", no double counting, no roll-up; the pin gap is data work that is under way |
| 2 | Counted: a quest in the zone's categories that passes the **map's** filter built for counting, and is not daily, weekly or repeatable (type bits 2, 4 and 128, forced out whatever the filter boxes say). Holiday and profession quests follow the map's filters | the icon is a map element; the map's boxes default to showing dailies, so the exclusion cannot lean on them |
| 3 | The icon shows when something is outstanding (counted and not done). It is bright when a quest is ready to hand in or can be taken now, and dim when only locked quests are left (the grey "?" for quests only in the log is grey already, so it is not dimmed again). No icon when nothing is outstanding | the dim state keeps the signal on a low-level character, as `qcPinGreyed` does for a pin |
| 4 | Capitals are folded into their host zone's icon through a small keyed table, with a sub-line in the tooltip. Phased twins are one icon, deduplicated by category. Every other zone keeps its own icon | removes most crowding and the clash with Blizzard's capital markers without hiding a city's quests; the rows are chosen from the geometry dump |
| 5 | First version: the direct Zone children of each continent map, the continents the game lists inside one (Quel'Thalas on Eastern Kingdoms, Argus on the Broken Isles), each as one icon counting its own map's zones, and the hubs of a continent map (Oribos, Dalaran, Undermine, Nazjatar, Ahn'Qiraj: The Fallen Kingdom) as icons at the place the hit test gives them, a click opening that map; sub-zones count in the zone they lie in (changed 10 October, after the dump and the user's first look: those quests would otherwise be invisible). Zones with no place on the map and Zephras Isle come later | what the client enumerates by itself; the rest wants a look |
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
category. The icon sits at the rectangle's centre, or at the place `QC_ZONE_ICON_AT` gives the zone (see "The
sparse table"). Two children with the same category are one icon,
the one with a rectangle. The zone list is read on every refresh, not cached: the call is dynamic
(scenario maps appear as children during quests).

**Continents inside a continent.** `GetMapChildrenInfo(continentId, Enum.UIMapType.Continent)` lists them
(retail only today: Quel'Thalas 2537 on Eastern Kingdoms, Argus 905 on the Broken Isles; Forever has
none). One of them is an icon like a zone, at the centre of its rectangle on the outer map, counting the
categories of its own map's icons (the dump's 6 zones for Quel'Thalas, 3 for Argus) plus its own category
if it has one, less any the outer map's zones count already, so nothing is counted twice. A click opens
that continent, whose own map draws its zone icons as it would any continent's. Such a continent is not
looked into further.

**Hubs and sub-zones.** Two more keyed tables in `qcContinentPins.lua`, from the dump and the client's
`UiMap` table. `QC_CONTINENT_HUBS` (by continent, then map) gives the maps that stand on a continent map
without being a zone of it an icon at a place of their own, the centre of the cells the hit test names them
on (`CentroidX` and `CentroidY` of their row in `docs/plans/continent-geometry-baseline.csv`, over 100;
`Test-ContinentPins.lua` checks each against that file): Oribos 1670 on the Shadowlands, Dalaran 627 on the
Broken Isles, Undermine 2346 on Khaz Algar, Nazjatar 1355 on Zandalar and on Kul Tiras, Ahn'Qiraj: The
Fallen Kingdom 327 on Kalimdor. The map's name is the game's, its quests are those of its category, and
the click opens it. `QC_SUBZONE_HOST` files a sub-zone's category under the icon of the zone the client
says it lies in, as a city's is: Korthia 1961 in The Maw, Valdrakken 2112 in Thaldraszus, Dornogal 2339 in
the Isle of Dorn, both levels of City of Threads 2213 and 2216 in Azj-Kahet, Silvermoon City 2393 and
Slayer's Rise 2444 in the zones of Quel'Thalas that hold them, the Shrine of the Storm 1039 in Stormsong
Valley; it applies where the zone has an icon. A hub whose category the map's zones count already gets no
second icon, a map the game doesn't know gets none, and quests are counted once on a continent (Nazjatar's
are on both its maps, as the banner is). These are retail's maps; Forever has none of them. The report
(`Report-ContinentGeometry.lua`) lists the maps the hit test names that are not children, and the
baseline holds a row for each, so a hub that moves is noticed at the sweep.

**The sparse table.** One keyed table in `qcContinentPins.lua`, with both games' map IDs (they don't
collide: Forever's are mostly 14xx), holds what the client can't tell us: a zone's extra categories
(Stranglethorn Vale 224 gets categories 147 and 214; Vashj'ir 203 gets 117, 182, 264 and 1; Arathi
Highlands 14 gets 1409, the category of its other map 2372, which the game gives no rectangle) and a
folded city's host (retail's Stormwind City 84 into Elwynn Forest 37, Ironforge 87 into Dun Morogh 27,
Undercity 90 into Tirisfal Glades 18, Silvermoon City 110 into Eversong Woods 94, Thunder Bluff 88 into
Mulgore 7, Darnassus 89 into Teldrassil 57, the Exodar 103 into Azuremyst Isle 97; Forever's Stormwind
1453, Ironforge 1455, Thunder Bluff 1456, Darnassus 1457 and Undercity 1458 into their zones). Orgrimmar
sits far from Durotar's icon and is left out until the geometry dump says otherwise. The rows come from
the offline analysis, and the dump confirms or trims them. If they pass about 25 per game, they become
a decisions CSV that a tool turns into a generated file, as `qcUnavailableQuests.lua` is.

A second keyed table, `QC_ZONE_ICON_AT`, gives a zone's icon a place of its own (map fractions) where the
centre of its rectangle looked wrong on the map. It holds Tiragarde Sound (895) at 0.574, 0.631, the centre
of the grid cells that name it: its rectangle's centre, 0.476, 0.645, is one the game's hit test also names
Tiragarde Sound at, but sits in the sea off Drustvar's edge, 98 px left of it at 1,000 px wide. Darkshore
(62 and Forever's 1439) and Felwood (77 and 1448) are nudged 0.01 to 0.012 left by eye, at the user's asking
on both games. A row for a hit-cell centre is read from the zone's `CentroidX` and `CentroidY` in
`docs/plans/continent-geometry-baseline.csv` (over 100); the report's "centre of a zone is over 3 map points"
line only names the zone and its distance. A row applies only while the game gives the zone a rectangle, and
`Compare-ContinentGeometry.lua` flags a hit area that moved over a point or changed by 15% of its cells, so
a stale row is noticed at the sweep. The report's other candidates wait for the user's eye, as no pin moves
without it.

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

**The pin.** `qcContinentPinTemplate` (a texture and a count) and `qcContinentPinMixin`, scaling limits (1, 1, 1), frame level `PIN_FRAME_LEVEL_AREA_POI` like
the zone pins and HandyNotes (the tie against Blizzard's capital markers, which
the folding mostly removes, is settled at the look; the other candidates are the map-highlight and
dig-site levels). The icon is the existing "?" for ready, "!" for takeable, "!" at half shade for
locked and the grey "?" for in the log only (not dimmed again: it is grey already), with the count of the
winning state in the icon's shade. No new art, but the grey "?" is the ready "?" with the texture
desaturated, because the game's own grey file is 16 pixels. The size follows the screen
(`qcContinentIconSize`): the 32-pixel art is drawn at no more than 1.1 screen pixels to a pixel, where
a UI unit is the UI scale times the screen's height over 768 pixels, never below the old 24 units
and never above 32, and the count's font steps up with it (`NumberFontNormalSmall`, `NumberFontNormal`,
`NumberFontNormalLarge`, which are vector fonts and don't pixelate). On the user's 1440p screen that is
29 units, 35 pixels; on 1080p 32; on a 4K screen at the same UI scale it stays 24, which is already 43
pixels there, since a bigger one would only be blurrier. An unreadable screen keeps 24.
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
   and 1500 px; 32 units since PR 6d) and writes a row per child; the first dump becomes
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
   - `docs/plans/continent-geometry-baseline.csv`, the two dumps above (retail 434 rows, 442 since PR 6d, Forever 53);
   - `Compare-ApiDocs.ps1 -Tables` (default `UIMapType`, `UiMapDetails`), the first structures whose
     contents it compares, with `Test-ApiDocs.ps1` at 258 checks; both are documented the same on live
     and Forever today;
   - sweep step 2f and the step 3b instructions in `maintenance.md`, a row in `game-parity.md`.
6b. **Nested continents and the Arathi extra** (decision 5 changed): `qcContinentZones` also lists the
   continents inside a continent, each counting its own map's zones (`qcChildrenOfType` is the shared
   child lookup), and Arathi Highlands 14 counts category 1409 through the extras table.
   `Test-ContinentPins.lua` plays the made-up cases (an icon at the rectangle's centre, its name, the
   categories in order, the ones the outer zones own left out, one with a category of its own, one with
   no quests left, one with no rectangle, one inside it left alone, a click opening it) and, on the
   client's own table, that each continent inside another gets an icon counting what its map's icons
   count.
6d. **Hubs, sub-zones and a larger icon** (the first look): `QC_CONTINENT_HUBS` and `QC_SUBZONE_HOST`
   with their tests (a hub at its place with the game's name and its category, a sub-zone in its zone's
   icon and in none of its own, one whose zone is not on the map counted nowhere, a hub whose category
   a zone counts already, a map the game doesn't know, Nazjatar on two continents, a click opening a
   hub; on the client's own table, that every hub shows on its continent with quests and every sub-zone's
   category is in its zone's icon and its zone is its parent in the client's table, that the tables hold
   exactly the rows they should, that each hub is at the baseline's centre, and, with the baseline's own
   children and rectangles in place of made-up ones, 13,459 quests on retail with none counted twice and
   which are in no icon); the pin's size, count font and grey art with their tests (every size from 24 to 32,
   a 1440p, a 1080p and a 2160p screen, an unreadable one, the 1.1 promise over a grid of screens, each look
   `qcZoneLook` gives, the font resetting the colour as the game's does); `Report-ContinentGeometry.lua` lists
   the maps the hit test names that are not children, the baseline holds them (8 rows), the probe keeps their
   names, and its crowding limit is 32 units, the largest icon. The Dreamgrove (747 in Val'sharah) went in
   after an independent review found its 79 quests in no icon.
6c. **Icon places** (the first look): `QC_ZONE_ICON_AT` with Tiragarde Sound, then Darkshore and Felwood
   on both games, and their tests (the icon at the table's place, another zone's at its rectangle's centre,
   no icon when the game gives no usable rectangle, whatever the table says; the Tiragarde checks run on
   retail only, the nudges on whichever game has the zone). `Compare-ContinentGeometry.lua` also compares
   a map's hit area (its cells and their centre).
7. **The release PR**: README (a bullet under "Quest givers on your world map", naming the option as
   the game shows it), a **New** bullet in the changelog, and the restart-WoW line.

PRs 3 to 6d are stacked; retarget each to master before deleting its base.

## Tests

Offline, under `C:\Program Files (x86)\Lua\5.1\lua.exe` (the `lua` on the path is 5.4 and lacks
`loadstring` and `setfenv`):

- **`tools\Test-ContinentPins.lua`**, for both TOCs: a synthetic map world (continent, zones with
  rectangles, a nil and a zero rectangle, twins, a folded city, Stranglethorn's, Vashj'ir's and Arathi's
  extras, continents inside the continent); a daily in
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
  rectangle, what Eastern Kingdoms lists for Quel'Thalas), whether each centre falls on its own
  zone, and where each zone really lies. The real canvas size needs one more step on each game:
  open the world map on Kalimdor, type `/qcprobe geometry`, then maximise the map and type it again.
- **One look at the finished icons, on each game** (about three minutes, five observations):
  1. The icons sit on their zones, not in the sea or on a neighbour, and nothing stacks (on the maximised
     map; on the windowed one about 13 pairs on Eastern Kingdoms overlap at the larger size, by design of
     the size, and are the thing to judge: if they bother, the size could step down on a small window, which
     is not built). On retail,
     Eastern Kingdoms has an icon on Quel'Thalas and the Broken Isles one on Argus; the Shadowlands has
     one on Oribos, the Broken Isles on Dalaran, Khaz Algar on Undermine, Zandalar and Kul Tiras on
     Nazjatar, and Kalimdor on Ahn'Qiraj: The Fallen Kingdom, each where its art is. The icons are
     crisp, not soft, at their new size (29 units on the user's screen); if they are soft, `QC_ICON_ART_PIXELS`
     times its 1.1 comes down.
  2. Hovering shows the tooltip, and its totals are close to the list's header for that zone.
  3. A left click opens the zone (or, on those two, the continent); a right click zooms out.
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
- Zones with no place on a continent map are counted nowhere (above, about 1,250 quests on retail): the
  continent icons are the list's zone counter for the zones the map shows, not a total.
- Eastern Kingdoms may show different zone sets by character (Quel'Thalas). The client gates Argus (905,
  player condition 143958) and Quel'Thalas the same way; a character the game doesn't list them for sees
  no icon for them, so their quests count nowhere on that character's continent maps.
- A new Lua file: an error at load would break both games, and players must restart WoW.
- 12.1.5 changes six maps and no zone relations; the tree is re-read from the client at run time.

## Left for later

The world map; hub maps; a level range in the
tooltip on retail; a toggle in the map's filter menu; `/qc continent`; Shift-click opening the list
at the zone's category; zones with no place on the continent map (Founder's Point, Razorwind Shores, Siren Isle).

## Status

- 2026-10-10: investigated; this plan written and the decisions above taken. Nothing built.
- 2026-10-10: PR 2 built (the probe's geometry pass, `Report-ContinentGeometry.lua`, 804 checks in `Test-Probe.lua`); not yet run in game.
- 2026-10-10: PR 3 built (the map tooltip's helpers in `qcTooltips.lua` as `QC.qcMapTip`, `Test-MapTooltip.lua`): the reachability reports of both games and a record of 400-odd tooltip calls are identical to master's; not yet tried in game.
- 2026-10-10: PR 4 built (`qcGetZoneQuests`, `qcContinentPins.lua`, `Test-ContinentPins.lua`): every category counts as many quests as the list's zone counter says (485 retail, 113 Forever); retail's 15 continents give 139 icons and Forever's 2 give 42, with no quest in two icons; a continent pass takes 6 ms at most offline; not yet in game, and nothing draws yet.
- 2026-10-10: PR 5 built (`qcContinentPinTemplate`, `qcContinentPinMixin`, `qcContinentDataProvider`, `qcRefreshMapProviders`, the `QC_M_SHOW_CONTINENT` option and its two strings, `Test-Settings.lua`): the reachability reports of both games and the zone pins' tooltip record are unchanged; the continent pin's tooltip, click, provider and the page's layout (33 px to spare) are checked offline only; not yet tried in game.
- 2026-10-10: both games' geometry dumps read (see "What the game said"). PR 6 built (`Compare-ContinentGeometry.lua`, the baseline CSV, `Compare-ApiDocs.ps1 -Tables`, sweep step 2f): `Test-Probe.lua` 985 checks and `Test-ApiDocs.ps1` 258 pass; each game compares clean against its baseline.
- 2026-10-10: PR 6b built (continents inside a continent, the Arathi extra, decision 5 changed): on the dump's geometry, retail's Eastern Kingdoms counts 2,326 quests on 27 icons (Quel'Thalas 870, Arathi's 24 more) and the Broken Isles 1,012 on 8 (Argus 147); Forever has none inside another and is unchanged (Kalimdor 20 icons, Eastern Kingdoms 22); no new pair of icons under 24 px; `Test-ContinentPins.lua` passes on both TOCs, each new check fails when its code is taken out; not yet tried in game.
- 2026-10-10: PR 6c built after the user's first look (retail, maximised Kul Tiras): `QC_ZONE_ICON_AT` moves Tiragarde Sound's icon from its rectangle's centre (0.476, 0.645, in the sea off Drustvar's edge) to the centre of the cells that name it (0.574, 0.631), 98 px right of where it was at 1,000 px wide, and Darkshore's and Felwood's a little left on both games. `Test-ContinentPins.lua` passes on both TOCs (Tiragarde's checks on retail only) and each of Tiragarde's fails when its code is taken out; `Test-Probe.lua` 991 checks. Twelve more retail zones and one Forever zone sit 50 px or more from their hit area's centre at 1,698 px (see "What the game said") and are left for the user's eye. An independent review of the first commit found the wording "off the zone" unsupported (the hit test names the zone at the old point too), and that a moved hit area went unnoticed: both fixed here.
- 2026-10-10: PR 6d built after more of the user's first look (retail Kalimdor, Eastern Kingdoms, Khaz Algar, the Shadowlands, Kul Tiras; Forever Eastern Kingdoms): the user's saved variables, replayed through the real counting code as an Alliance Human mage with the calendar quiet, give their screenshots' counts to within one on every zone. So no icon on Thousand Needles, Un'Goro Crater and Winterspring (all done), Durotar (only Trial of Style quests, hidden by the seasonal filter), and on every Eastern Kingdoms zone without one on retail (all done, or no quests) is as designed, and Forever's Eastern Kingdoms has all 22 it should (Deadwind Pass has no category). The real gaps were hubs and sub-zones: `QC_CONTINENT_HUBS` (6) and `QC_SUBZONE_HOST` (8), after which retail counts 13,459 of its 14,708 zone-category quests in an icon (853 more, 1,249 left in none: no place on a continent map), none twice, and the Dreamgrove (79) went in with them after the review. The icon is larger where its art allows (29 units on the user's screen, 24 where it would only blur) and the grey "?" is the ready one desaturated (the game's own is 16 pixels). `Test-ContinentPins.lua` passes on both TOCs, `Test-Probe.lua` 1,142 checks; an independent review of the commit found 27 confirmed points (counted once each, mostly wording and gaps in the tests), all fixed here; not yet tried in game.
