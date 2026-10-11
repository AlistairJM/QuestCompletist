# Menu review: sensible, valid, and nothing left out

## Goal

On 9 October 2026 the user asked for a review of the menu of every game the addon supports (Retail,
and WoW: Forever, which loads through `QuestCompletist_Camelot.toc`): are the entries still sensible
and valid, and does any quest appear in no menu at all? The report has 50 findings, numbered R01 to
R40 for Retail and F01 to F10 for Forever; the project's `menu-review.xlsx` holds their evidence and
a Decision column. The user answered "just go with your recommendations". This file records what that
changed, what was left alone and why, and what is waiting for the user. The IDs are the report's.

## Where things stand (measured 2026-10-09, on master a288b24 before the changes)

| | Retail | WoW: Forever |
|---|---|---|
| Quests | 35,023 | 5,081 |
| Quests in no menu (before, after) | 1, 0 | 0, 0 |
| Quest IDs on pins or prerequisites with no quest row | 272 (267 on pins only, 5 prerequisites only) | 0 |
| Hidden by the default filters | 9,072 | 754 |
| Zone auto-switch rows pointing at an empty or undefined category (before, after) | 83, 0 | 2, 0 |

Both menus were sound in structure: every entry has a definition and a handler, none was empty, and
Retail covers every expansion from Classic to Midnight. The trouble was in Retail's hand-edited menu
(wrong parents, stale entries), in the zone auto-switch table, and in the catch-all categories. The
one quest in no menu was 60474, a Blizzard test quest in a "Development Land" category.
`tools\Test-QuestReachability.lua` (8 October) agreed: one quest never shown on Retail, none on
Forever.

## What changed (9 October 2026, branch `chore/menu-review`)

| Finding | Change |
|---|---|
| R01 | Quest 60474 to category 0 (one row of `data\quests.jsonl`, `qcQuestData.lua` regenerated); category 287 "Development Land" removed from `qcQuestCategories`. Its unavailable flag stays. The quest row is kept (decision 4). |
| R03 | The seven Battle for Azeroth campaign categories (1090, 1091, 1092, 1132, 1133, 1134, 1064; 753 quests) moved from Continents, Miscellaneous to a new "Other Categories" group in Battle For Azeroth (the heading is `qcL.OTHERCATEGORIES`, as in the newer expansions). |
| R04, R07 | Timerunning (427) moved from Pandaria, Other Categories to the end of World Events (decision 1). The 114 "Infinite Research" quests in Uncategorized (storyline 5902) went into it, through a new name-prefix rule in `Place-UncategorisedQuests.ps1` so later sweeps repeat it. |
| R09, R10, F01 | Zone auto-switch: 76 Retail rows deleted and 7 re-pointed (decision 2). Forever's generator no longer writes a row for a category it does not define (maps 1430 and 2482). |
| R12 | Elemental Bonds (69), Firelands Invasion (78) and Molten Front (136) moved next to Mount Hyjal, in Kalimdor, Northern Kalimdor. |
| R13 | Scarlet Halls (168) moved from Mists of Pandaria to Classic, before Scarlet Monastery (decision 6). |
| R22, R24, R37 | English spelling in `qcQuestCategories`: 1221 "Necrolord " to "Necrolord", 1430 "Delvers Headquarters" to "Delver's Headquarters", 426 "Theramore`s  Fall" to "Theramore's Fall". Locale keys are made from letters and digits only, so none changed. |
| R33 (part) | Monk moved to its alphabetical place in the class list (it was last). |
| R34 | The three commented-out lines in Retail's `qcMenu.lua` deleted (`EMERALDGARDENS`, `HARVESTFESTIVAL`, `NEWYEARSEVE`). |
| F04 (part) | Forever: Camping (-666) moved under Professions, in `Build-ForeverMenu.ps1`. |
| R08 | No change to what is hidden: 56 `KEEP` rows in `unavailable-quest-decisions.csv` (decision 5). |

Files: `qcMenu.lua`, `qcQuest.lua`, `qcQuestData.lua`, `Forever\qcMenu.lua`, `Forever\qcQuest.lua`,
`data\quests.jsonl`, `docs\plans\unavailable-quest-decisions.csv`, `tools\Place-UncategorisedQuests.ps1`
and `tools\Build-ForeverMenu.ps1`. `qcUnavailableQuests.lua` is byte-identical. Checks after the
change: `Build-AddonData.ps1 -Check` passes; the reachability report's "never shown" is 0 on Retail
(was 1) and 0 on Forever, and every other count is as before; `Test-Localization.lua` is unchanged;
the dungeon audit only lost its Scarlet Halls issue; `Remove-EmptyMenuEntries.ps1 -WhatIf` reports
nothing; `Build-ForeverMenu.ps1` reruns byte for byte; `luac -p` is silent on all 26 Lua files.
A separate script compared the menus, categories and quests before and after: the only quests that
moved are the 115 above, and no category with quests lacks a menu entry or zone row, and no menu
entry or zone row points at an undefined or empty category.

## Decisions (agreed 2026-10-09)

The user's word was "just go with your recommendations". Where a call below differs from the
report's recommendation, it says so.

1. **Timerunning goes with the events, not with Legion.** The report (R04) said The Broken Isles.
   Category 427 holds the quests of both Remixes: about 19 from Pandaria Remix (IDs 78893 to 80380)
   and 45 from Legion Remix (89404 to 93120). Neither expansion fits, and Timerunning is a
   limited-time event. **Recommendation:** World Events, as done; it is one menu entry to move back.
2. **A zone with no quests gets no auto-switch row.** The list stays where it is when the player
   enters a dungeon, raid or battleground, instead of switching to an empty one, and
   `Place-UncategorisedQuests.ps1` falls to its "zone above the pin's map" rule for pins there. Four
   starter areas, whose quests are filed under their parent zone, were re-pointed to it (Camp Narache
   462 to Mulgore, Shadowglen 460 to Teldrassil, Valley of Trials 461 to Durotar, New Tinkertown 469 to
   Dun Morogh). Alterac Valley's new map (1537) points at Alterac Valley (7), and both Serpentshrine
   Cavern maps (332, 1554) at Coilfang Reservoir (39), the hub the dungeon audit accepts.
   **Recommendation:** as done. The report's other option, a guard in `qcZoneChangedNewArea` that skips
   empty categories, is not needed while the table holds no such row.
3. **Only changes that need no new translated text and no new category were made.** The user is
   cutting down manual localization, so a new heading uses an existing `qcL` key or a client string,
   and no category was merged, split, added or removed (apart from 287). That is why the items under
   "Decisions waiting for the user" are waiting. **Recommendation:** keep this rule for menu work.
4. **Category 287 is removed and its one quest kept, in Uncategorized** (the report said delete the
   quest). An API sweep would add the quest back if its row were deleted, and with 287 undefined the
   placement tool already files such a quest under 0. It stays flagged unavailable, so players do not
   see it.
5. **Placeholder quests (R08) are not flagged without the evidence step 7 of the runbook asks for.**
   None of the 56 unflagged ones passes: 48 are still served by Blizzard's API and known to the
   server, and the other 8 are in the latest PTR's `QuestV2` (7 of them task quests, which
   `Build-UnavailableQuests.ps1` will not flag). Each got a `KEEP` row with the evidence (the file now
   has 218 `FLAG` and 503 `KEEP` rows). 22 of them still show in default lists; see question 20.
6. **Scarlet Halls goes with Classic**, where the Dungeon Journal lists it first and where
   `Audit-DungeonCategories.ps1` expects it. The Journal also lists it in its Mists of Pandaria tier,
   so either place is defensible. **Recommendation:** Classic, so the audit is clean.

## Left alone on purpose

- **R02, the 267 pin-only quest IDs, and R11, the 5 prerequisite-only IDs** (30490, 54130, 59174,
  89285, 91799): parked since phase 2 of [data-cleanup.md](data-cleanup.md). A prerequisite taken out
  of the data would come back with the next API sweep, and a missing row is not proof the quest is
  dead.
- **R14 Legion Uncategorized** stays (agreed 30 September).
- **R16 Tournament** is in Northrend and in World Events; both open the same list and it is an
  event, so both stay.
- **R23 Amirdrassil** (zone and raid) keep the in-game names.
- **R32, the 83 unused category definitions** are harmless. Removing them cascades into the locale
  files (`Remove-ConvertedLocaleKeys.ps1`), so it is a pass of its own (question 31).
- **R35, R36, R38 to R40 and F08 to F10** are information rows with nothing to change.

## Decisions waiting for the user

Also in the table in [open-items.md](open-items.md), as decisions 20 to 31. The recommendation is the
one the report author would take.

| # | Finding | Decision | Recommendation |
|---|---|---|---|
| 20 | R08 | The 22 placeholder-named quests that still show in default lists (63947 and 63948, "[PH]" quests in 9.1 Campaign, among them): flag them in `unavailable-quest-decisions.csv` although they fail the step-7 evidence rules? | yes, the 22 that show: the same call as on 5 October for the 19 internal entries. The rest are hidden already by their quest type |
| 21 | R28 | One shape for every expansion's submenu | **yes, 11 October 2026, done**: Draenor and The Broken Isles each have Main Zones and Other Categories, in the shape of Pandaria's (the same two `qcL` keys, no new text); Outland, Northrend and The Maelstrom stay flat. Draenor, Main Zones (7): Frostfire Ridge, Gorgrond, Tanaan Jungle, Spires of Arak, Talador, Shadowmoon Valley - Draenor, Nagrand - Draenor; Other Categories (6): Garrison Campaign, Garrison Support, Ashran, Assault on the Dark Portal, Stormshield, Warspear. The Broken Isles, Main Zones (13): Eye of Azshara, Azsuna, Broken Shore, Dalaran, Thunder Totem, Highmountain, Helheim, Stormheim, Suramar, Val'sharah, Krokuun, Antoran Wastes, Mac'Aree; Other Categories (11): the eight class halls the call named (The Dreamgrove, Hall of the Guardian, Mardum, Netherlight Temple, Skyhold, The Heart of Azeroth, The Wandering Isle, Trueshot Lodge), and the three entries it did not name: the two class halls Dreadscar Rift (Warlock, 1017) and Acherus: The Ebon Hold (Death Knight, 1021), and Legion Uncategorized (1050), put there too: the first two are class halls like the eight, and the third is a catch-all, not a zone. Every entry keeps its place relative to the others in its group |
| 22 | R27 | Midnight: Founder's Point (57 quests) and Razorwind Shores (58) sit in Main Zones with the story zones | **yes, 10 October 2026, done**: Founder's Point and Razorwind Shores sit in Other Categories with Prey, in alphabetical order |
| 23 | R26 | Lordaeron has 21 entries and also holds Quel'Thalas, Gilneas and Tol Barad | **yes, 10 October 2026, done**: Lordaeron keeps its 11 entries; Quel'Thalas (Eversong Woods, Ghostlands, Isle of Quel'Danas, Silvermoon City, Sunstrider Isle), Gilneas (Gilneas, Gilneas City, Ruins of Gilneas) and Tol Barad (Tol Barad, Tol Barad Peninsula) follow it, named by the client's maps 2537, 179 and 244. Retail only: Forever's Lordaeron holds just its ten original zones |
| 24 | R15, R31 | Merge categories: Darkmoon Island (10 quests) into Darkmoon Faire (59), and four one-quest entries (Brewmoon Festival 32, Greenstone Village 86, Unga Ingoo 257, Thunder Totem 1049) into their zones | yes, in one pass: refile, delete the category, point its map's zone row at the target, remove the menu entry and its locale key. Not done now because a merge changes how the sweep tools file new quests |
| 25 | R17 to R21, R25, F03 | Names that repeat: nine names appear twice (Eversong Woods in two expansions, for example), a group and a category share a name (Covenant Sanctum, Professions, Battlegrounds, Vashj'ir, Miscellaneous), and Forever's heading is "Invasion" | leave. Each rename needs a new string in every language, and Forever's heading is the client's own (QuestSort 368). If it matters, show the menu path in the list header when a name repeats: one line of code, no new text |
| 26 | R29, R30, R39, F06, F07, F09 | Entries that are empty by default (all their quests repeatable or retired) or hold one or two quests | **yes, 11 October 2026, done**: every entry stays (none removed, no quest moved), and an empty list now says "Quests hidden by your filters: N", on both games; entry by entry under "Question 26" below |
| 27 | R06 | Rated PvP: 86 of 87 quests are flagged unavailable, so the entry opens an empty list | keep: removing it would leave 87 quests in no menu, and they show with "Show unavailable quests" on |
| 28 | R05 | Class Quests has no Evoker | leave: 37 of the 45 Evoker-only quests are the Forbidden Reach start, filed by zone |
| 29 | R33 | Ordering rule: Retail's hand order, or alphabetical everywhere | keep the hand order (Monk is fixed); Forever sorts alphabetically in its generator already |
| 30 | F04, F05 | Forever: Seasonal lumps Winter Veil (37), Love is in the Air (21), Hallow's End (7) and Harvest Festival (2); Deeprun Tram and Special stand loose | leave until after the 4 November launch, then look again |
| 31 | R32 | Remove the 83 unused category definitions | yes, in a pass of its own with `Remove-ConvertedLocaleKeys.ps1`, after question 24 |

## Question 26: what the entries do now

An empty list used to open blank, with only the header's "0/0 Complete (0%)" or the like. When the
filters hid every quest of the selected category it now has one more line, centred over the list's
first rows: "Quests hidden by your filters: N" (`qcL.QUESTSHIDDEN`, the only new string; the ten other
languages have a translation marked `-- Needs review`). A category with no quests, a list with rows
and a search show no line, and the header's count and the rows are as before. `qcShowHiddenQuests` in
`qcCore.lua` counts only for an empty list, and the list is empty only when the filters hid all of
its category, so the number is the category's size; a list with rows does no extra work. The code is
shared, so it is the same on both games. The line is `qcHiddenQuests`, a text in `QuestCompletist.xml`.
`Test-QuestReachability.lua` checks it (see [maintenance.md](../maintenance.md), step 9).

The entries of the question, by what the review found (quest counts as of 11 October 2026):

- **R29, retail, 8 entries whose 1 to 3 quests are all daily, weekly or repeatable:** Alterac Mountains
  (6, 1 quest), Coilfang Reservoir (39, 1), Dalaran Crater (45, 2), Hellfire Citadel (95, 1), The
  Obsidian Sanctum (225, 1), Trial of the Crusader (251, 1), Assault on Violet Hold (1036, 3) and
  Deephaul Ravine (1421, 1). Each stays and opens an empty list that says how many quests the filters
  hide; unticking the daily, repeatable and world filters shows them.
- **R39, retail, 11 entries whose quests are all recurring:** Jade Temple Grounds (114, 7), Landfall
  (121, 73), Tol Barad (246, 26), Tol Barad Peninsula (247, 44), Wintergrasp (273, 27), Highmaul (318, 6),
  the four covenant callings Kyrian, Necrolord, Night Fae and Venthyr (1220 to 1223, 25 each) and Weekly
  Events (1735, 52). The same.
- **R30, retail, 10 entries of 1 or 2 quests:** Hrothgar's Landing (103, 1), Peak of Serenity (152, 1),
  Riding (163, 2), Stormwind Harbor (195, 1), The Exodar (216, 2), Northshire (295, 2), Eye of Azshara
  (1004, 1), 9.1 Campaign (1240, 2), Keeper's Respite (1242, 1) and Awakening the Machine (1420, 1).
  None is recurring or retired, so each list shows its quests. Where the character can't take them the
  filters hide them and the list says so: Peak of Serenity's quest is a Monk's and Stormwind Harbor's
  an Alliance quest, so both open empty for a Horde Death Knight.
- **F06, Forever:** Onyxia's Lair (2159), whose one quest is recurring: stays, with the line.
- **F07, Forever, 5 entries of 1 or 2 quests:** Alchemy (-181, 1), Herbalism (-24, 1), Thoradin's Wall
  (293, 1), Deeprun Tram (2257, 2) and Riverglades (16591, 1). Each shows its quests; Deeprun Tram's two
  are Alliance quests, so the list is empty, with the line, for a Horde character.
- **F09, Forever:** Crafting (16941), 150 quests, all recurring: stays, with the line.

The line also helps every other category that opens empty, such as Rated PvP (question 27: 86 of 87
quests unavailable) and any class, faction or race category the character can't use. For a Horde Blood
Elf Death Knight at the default settings 60 of retail's 485 categories and 15 of Forever's 113 open
empty; the reachability report lists them.

## Noticed along the way

- A plain `Place-UncategorisedQuests.ps1 -Refile 0` would now move 30 more quests out of
  Uncategorized (28 by their pin's map, 2 by storyline: 91437 and 92430). They were left where they
  are; run it with `-WhatIf` to see the list.
- `Build-CategoryClientNames.ps1` listed two expected differences (categories 1221 and 1430) that
  the spelling fixes made stale. Removed on 10 October 2026: the client's names now agree with ours,
  and the one difference left is category 1420 ("Awakening The Machine" in the client, "Awakening
  the Machine" here). With the entries gone the script runs clean and `qcQuest.lua` and `qcMenu.lua`
  regenerate byte-identically.
- Six categories (3, 248, 1244, 1344, 1402 and 1425) each appear twice in Retail's menu. They did
  already at master. Not touched.
- Retail's `qcAreaIDToCategoryID` has duplicate keys: 219, 221 and 1670 (the same value twice) and
  2372 (10, then 1409, so 1409 wins and the first is dead). Not touched.
- In the review's working file `zone-auto-switch-targets.csv` (not in the repo), the Uldir row says 10
  maps but names 6; maps 1154, 1155, 1381 and 1382 are missing from it. All four are in the table and
  were handled.
- `Build-UnavailableQuests.ps1` and [unavailable-quests.md](unavailable-quests.md) disagree: the doc
  says a task quest can be flagged if a decision row overrides, but the script has no override and
  stops on any task `FLAG`.
- `Audit-DungeonCategories.ps1` still reports "not in the menu" for The Black Morass (409) and
  Firelands (425). Both categories are empty, as before, and the zone rows for both were among the
  deletions.
- The runbook's step-10 reachability example uses `tools\UiMap-<build>.csv`. Only the 70205 map file
  is in `tools\`, while the docs name 70245 as the current beta build.
- Docs, updated with this change: `maintenance.md` step 6 (the name-prefix list of
  `Place-UncategorisedQuests.ps1`), `unavailable-quests.md` (503 `KEEP` rows, 218 `FLAG`) and
  `forever.md` (Camping under Professions, no rows for undefined zones). Nothing else writes down
  Timerunning's place (`maintenance.md` only names it as an example), and no Dungeon Journal audit
  baseline names Scarlet Halls.

## Status

- 2026-10-09: reviewed (50 findings), then the changes above made on branch `chore/menu-review`, cut
  from master at a288b24.
- 2026-10-09: committed, then master merged in (it had moved 62 commits: the quest giver recorder, the
  probe, the Forever table checks, the quest cache). The one conflict was `open-items.md`: master's own
  decisions 8 to 19 (levels, holidays, the quest cache) kept their numbers, so the menu questions
  above are 20 to 31 there and here. The checks above were rerun on the merged tree: `luac -p` is
  silent on all 26 Lua files, `Build-AddonData.ps1 -Check`, `Build-ForeverMenu.ps1 -Check`,
  `Test-Localization.lua` and `Remove-EmptyMenuEntries.ps1 -WhatIf` pass, and the reachability run
  shows 0 quests never shown and 0 Lua errors on Retail and on Forever.
- Not tried in game. The menus are checked offline; what only the game can show is the four starter
  areas following their parent zone (see "To try in game" in [open-items.md](open-items.md)).
- Five release zips (`QuestCompletistv112.2.zip` to `v112.6.zip`) sit untracked in the repo root and
  were left alone.
- 2026-10-09 (later): merged (#251) and released in 112.7, untried in game, on the user's word.
- 2026-10-10: questions 22 and 23 done on the user's word. `luac -p` is silent on every Lua file, `Test-Localization.lua`, `Test-Settings.lua` (both games), `Test-QuestReachability.lua`, `Test-MapTooltip.lua`, `Audit-DungeonCategories.ps1` (same result as master) and `Remove-EmptyMenuEntries.ps1 -WhatIf` pass. Not tried in game: the three new submenus and Midnight's Other Categories.
- 2026-10-11: question 21 approved by the user and done: Draenor and The Broken Isles each split into Main Zones and Other Categories, in Pandaria's code shape (`qcMenu.lua` only, no new text). Checked offline: `luac -p` is silent on all 27 Lua files, and `Test-Localization.lua`, `Test-Settings.lua` (both games), `Test-QuestReachability.lua` (both games: 0 quests in categories the list can't browse to; Retail's report equals master's), `Test-MapTooltip.lua` (both games), `Remove-EmptyMenuEntries.ps1 -WhatIf` (0 entries), `Remove-ConvertedLocaleKeys.ps1 -WhatIf` (0 lines) and `Build-ForeverMenu.ps1 -Check` (Forever's three files up to date; its menu has no Draenor or Legion) pass. `Audit-DungeonCategories.ps1` finds the same issues as master; its one difference is Eye of Azshara's menu path, now ending in "Main Zones". A Lua dump of the menu before and after shows nothing else moved and every group keeps its entries' order. Not tried in game: the two new submenu layouts.
- 2026-10-11: question 26 approved by the user and done, on branch `feat/empty-list-hidden-count` (cut from master 956ef50): an empty quest list says "Quests hidden by your filters: N" (`qcShowHiddenQuests` in `qcCore.lua`, a text `qcHiddenQuests` in `QuestCompletist.xml`, the new key `QUESTSHIDDEN` in all 11 locale files, the ten translations marked `-- Needs review`); every entry stays and no quest moved. Checked offline: `luac -p` is silent on all 27 addon Lua files, `Test-Localization.lua` says "No problems", `Test-QuestReachability.lua` (both games) has 0 Lua errors and a report equal to master's apart from its new section, whose checks (1,036 on retail, 292 on Forever) all pass and fail 82 and 37 of them on master's code, `Test-Settings.lua`, `Test-MapTooltip.lua`, `Test-ContinentPins.lua` and `Test-SeasonalCalendar.lua` (both games) say "All checks passed.", `Test-Recorder.lua` says "0 failed", and `Build-AddonData.ps1 -Check` says all four files are up to date. Not tried in game: how the line looks in the list (a centred line over the first rows).