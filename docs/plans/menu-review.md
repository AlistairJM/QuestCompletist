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
| R08 | No change to what is hidden: 56 `KEEP` rows in `unavailable-quest-decisions.csv` (decision 5). On 11 October 2026 the user decided to flag the 22 of them that still show (question 20): all 22 are flagged now (20 with reason 1, the 2 task quests with reason 3). |

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
5. **Placeholder quests (R08) are not flagged without the evidence step 7 of the runbook asks for,
   unless the user says so.** None of the 56 unflagged ones passes: 48 are still served by Blizzard's
   API and known to the server, and the other 8 are in the latest PTR's `QuestV2` (7 of them task
   quests, which `Build-UnavailableQuests.ps1` will not flag). Each got a `KEEP` row with the evidence
   (the file then had 218 `FLAG` and 503 `KEEP` rows). 34 of the 56 are hidden by default by their
   quest type; 22 still showed in default lists, and on 11 October 2026 the user decided to flag
   those 22 (question 20). All 22 are flagged: 20 with reason 1, and 86645 and 94815 ("[DNT]" hidden quests in
   Eversong Woods), which are client task quests, with reason 3, the builder's override for a task quest.
   The file now has 240 `FLAG` and 481 `KEEP` rows.
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
- **R32, the 83 unused category definitions** were harmless. Removing them cascades into the locale
  files (`Remove-ConvertedLocaleKeys.ps1`), so it was a pass of its own: 82 went on 11 October 2026 and
  one stays (question 31).
- **R35, R36, R38 to R40 and F08 to F10** are information rows with nothing to change.

## Decisions waiting for the user

Also in the table in [open-items.md](open-items.md), as decisions 20 to 31. The recommendation is the
one the report author would take.

| # | Finding | Decision | Recommendation |
|---|---|---|---|
| 20 | R08 | The 22 placeholder-named quests that still show in default lists (63947 and 63948, "[PH]" quests in 9.1 Campaign, among them): flag them in `unavailable-quest-decisions.csv` although they fail the step-7 evidence rules? | **yes, 11 October 2026, done**: the same call as on 5 October for the internal and test entries (25 rows reviewed with the user). Flagged (reason 1, the decision in each row's evidence): 42905, 50384, 52052, 58328, 60227, 60228, 60559, 60937, 61636, 62828, 62987, 63947, 63948, 64231, 76021, 77094, 84832, 85017, 85044 and 90087; `qcUnavailableQuests.lua` gains those 20 and 86645 and 94815, which are among the 22 but are client task quests, so they are flagged with reason 3, which `Build-UnavailableQuests.ps1` accepts only for a task quest: 240 in all. The other 34 of the 56 are hidden already by their quest type and stay `KEEP`. 63947 and 63948 were the only quests of 9.1 Campaign, so that entry opens an empty list by default now (like question 27's Rated PvP) |
| 21 | R28 | One shape for every expansion's submenu | **yes, 11 October 2026, done**: Draenor and The Broken Isles each have Main Zones and Other Categories, in the shape of Pandaria's (the same two `qcL` keys, no new text); Outland, Northrend and The Maelstrom stay flat. Draenor, Main Zones (7): Frostfire Ridge, Gorgrond, Tanaan Jungle, Spires of Arak, Talador, Shadowmoon Valley - Draenor, Nagrand - Draenor; Other Categories (6): Garrison Campaign, Garrison Support, Ashran, Assault on the Dark Portal, Stormshield, Warspear. The Broken Isles, Main Zones (13): Eye of Azshara, Azsuna, Broken Shore, Dalaran, Thunder Totem, Highmountain, Helheim, Stormheim, Suramar, Val'sharah, Krokuun, Antoran Wastes, Mac'Aree; Other Categories (11): the eight class halls the call named (The Dreamgrove, Hall of the Guardian, Mardum, Netherlight Temple, Skyhold, The Heart of Azeroth, The Wandering Isle, Trueshot Lodge), and the three entries it did not name: the two class halls Dreadscar Rift (Warlock, 1017) and Acherus: The Ebon Hold (Death Knight, 1021), and Legion Uncategorized (1050), put there too: the first two are class halls like the eight, and the third is a catch-all, not a zone. Every entry keeps its place relative to the others in its group |
| 22 | R27 | Midnight: Founder's Point (57 quests) and Razorwind Shores (58) sit in Main Zones with the story zones | **yes, 10 October 2026, done**: Founder's Point and Razorwind Shores sit in Other Categories with Prey, in alphabetical order |
| 23 | R26 | Lordaeron has 21 entries and also holds Quel'Thalas, Gilneas and Tol Barad | **yes, 10 October 2026, done**: Lordaeron keeps its 11 entries; Quel'Thalas (Eversong Woods, Ghostlands, Isle of Quel'Danas, Silvermoon City, Sunstrider Isle), Gilneas (Gilneas, Gilneas City, Ruins of Gilneas) and Tol Barad (Tol Barad, Tol Barad Peninsula) follow it, named by the client's maps 2537, 179 and 244. Retail only: Forever's Lordaeron holds just its ten original zones |
| 24 | R15, R31 | Merge categories: Darkmoon Island (10 quests) into Darkmoon Faire (59), and four one-quest entries (Brewmoon Festival 32, Greenstone Village 86, Unga Ingoo 257, Thunder Totem 1049) into their zones | **yes, 11 October 2026, done**: in one pass, as recommended. Refiled and deleted: Brewmoon Festival 32 (31611) to Kun-Lai Summit 120, Greenstone Village 86 (31613) to The Jade Forest 221, Unga Ingoo 257 (31058) to Krasarang Wilds 119, Thunder Totem 1049 (48435) to Highmountain 1005, and Darkmoon Island 316 (ten Warlock quests, 75538 to 76430) to Darkmoon Faire 46, which now has 69 quests. The zone rows of maps 448, 450, 452 and 750 name the targets, the five menu entries are gone, and no locale key was left to remove. Quest by quest under "Question 24" below |
| 25 | R17 to R21, R25, F03 | Names that repeat: nine names appear twice (Eversong Woods in two expansions, for example), a group and a category share a name (Covenant Sanctum, Professions, Battlegrounds, Vashj'ir, Miscellaneous), and Forever's heading is "Invasion" | leave. Each rename needs a new string in every language, and Forever's heading is the client's own (QuestSort 368). If it matters, show the menu path in the list header when a name repeats: one line of code, no new text |
| 26 | R29, R30, R39, F06, F07, F09 | Entries that are empty by default (all their quests repeatable or retired) or hold one or two quests | **yes, 11 October 2026, done**: every entry stays (none removed, no quest moved), and an empty list now says "Quests hidden by your filters: N", on both games; entry by entry under "Question 26" below |
| 27 | R06 | Rated PvP: 86 of 87 quests are flagged unavailable, so the entry opens an empty list | keep: removing it would leave 87 quests in no menu, and they show with "Show unavailable quests" on |
| 28 | R05 | Class Quests has no Evoker | leave: 37 of the 45 Evoker-only quests are the Forbidden Reach start, filed by zone |
| 29 | R33 | Ordering rule: Retail's hand order, or alphabetical everywhere | keep the hand order (Monk is fixed); Forever sorts alphabetically in its generator already |
| 30 | F04, F05 | Forever: Seasonal lumps Winter Veil (37), Love is in the Air (21), Hallow's End (7) and Harvest Festival (2); Deeprun Tram and Special stand loose | leave until after the 4 November launch, then look again |
| 31 | R32 | Remove the 83 unused category definitions | **yes, 11 October 2026, done**: in a pass of its own, after question 24. 82 definitions removed with the table rows and the 12 locale keys that went with them; Island Expeditions (1130) stays, because two tools still name it. Detail under "Question 31" below |

## Question 24: what the merge changed

R15 (Darkmoon Island, 10 quests) and R31 (four categories of one quest each) are done, in one pass, on
the user's word of 11 October 2026. Each quest went where its pins sit: the three brewing quests'
givers stand on the maps of the zones they went to (379, 371 and 418), the Thunder Totem quest's one
pin is on map 750, which the zone table now gives to Highmountain, and six of the ten Darkmoon Island
quests have a pin on the island's own map (407), which already named Darkmoon Faire (the other four
start in Stormwind City and Orgrimmar). A per-quest comparison of `data\quests.jsonl` with master
(35,023 records) finds exactly these 14 changed, and only in `category` and `zone`; the zone text is
the one the target's other quests carry. Every other field is as it was. The ten Darkmoon Island
quests have no holiday tag and keep none: they are `KEEP` rows of
[quest-holiday-decisions.csv](quest-holiday-decisions.csv), untagged on purpose.

| Quest | Name | Category before | Category after | Zone text before | Zone text after |
|---|---|---|---|---|---|
| 31611 | The Kun-Lai Kicker | 32 Brewmoon Festival | 120 Kun-Lai Summit | Brewmoon Festival | Kun-Lai Summit |
| 31613 | Volatile Greenstone Brew | 86 Greenstone Village | 221 The Jade Forest | Greenstone Village | The Jade Forest |
| 31058 | The Funky Monkey Brew | 257 Unga Ingoo | 119 Krasarang Wilds | Unga Ingoo | Krasarang Wilds |
| 48435 | The Spiritwalkers | 1049 Thunder Totem | 1005 Highmountain | (none) | Highmountain |
| 75538 | Beginning Impositions | 316 Darkmoon Island | 46 Darkmoon Faire | Darkmoon Island | Darkmoon Faire |
| 75539 | Some Wicked Things This Way Come | 316 Darkmoon Island | 46 Darkmoon Faire | Darkmoon Island | Darkmoon Faire |
| 75540 | Hermetic Insurance | 316 Darkmoon Island | 46 Darkmoon Faire | Darkmoon Island | Darkmoon Faire |
| 75541 | Those Who Hesitate | 316 Darkmoon Island | 46 Darkmoon Faire | Darkmoon Island | Darkmoon Faire |
| 75542 | Curses & Cultists | 316 Darkmoon Island | 46 Darkmoon Faire | Darkmoon Island | Darkmoon Faire |
| 75639 | Fel Suspicions | 316 Darkmoon Island | 46 Darkmoon Faire | Darkmoon Island | Darkmoon Faire |
| 76155 | A Wolf Among Sheep | 316 Darkmoon Island | 46 Darkmoon Faire | Darkmoon Island | Darkmoon Faire |
| 76410 | A Dark Summons | 316 Darkmoon Island | 46 Darkmoon Faire | Darkmoon Island | Darkmoon Faire |
| 76427 | A Dark Summons | 316 Darkmoon Island | 46 Darkmoon Faire | Darkmoon Island | Darkmoon Faire |
| 76430 | Beginning Impositions | 316 Darkmoon Island | 46 Darkmoon Faire | Darkmoon Island | Darkmoon Faire |

What else changed, all in `QuestCompletist\qcQuest.lua`, `qcMenu.lua` and the regenerated
`qcQuestData.lua` (retail only):

- `qcQuestCategories` has 563 rows instead of 568: 32, 86, 257, 316 and 1049 are gone. 480 categories
  hold quests (485), and 83 hold none, as before.
- `qcAreaIDToCategoryID`: four rows re-pointed, so walking into those maps switches the list to the
  zone: map 448 (Greenstone Village) from 86 to 221, 450 (Unga Ingoo) from 257 to 119, 452 (Brewmoon
  Festival) from 32 to 120 and 750 (Thunder Totem) from 1049 to 1005. No row named 316: Darkmoon
  Island's maps (407 and 408) already named 46. No row names an undefined category, as before.
- `qcCategoryUiMapID` (376 rows to 373: 32, 257, 1049) and `qcCategoryClientName` (113 to 111: 86, 316)
  came out through `Build-CategoryUiMapIDs.ps1` and `Build-CategoryClientNames.ps1`, which give
  master's two tables byte for byte from master's own inputs, so the only change is the deleted rows.
- `qcMenu.lua`: the five entries are gone (`Remove-EmptyMenuEntries.ps1`): Brewmoon Festival, Greenstone
  Village and Unga Ingoo from Pandaria's Other Categories (Unga Ingoo closed the submenu, so Pandaren
  Campaign took over its closing brackets), Thunder Totem from The Broken Isles' Main Zones and
  Darkmoon Island from World Events. A Lua dump of the menu before and after shows nothing else moved
  (562 items to 557).
- No locale key to delete: the client names all five categories, so none had a key in
  `Localization.*.lua`, and their entries had no label. `Remove-ConvertedLocaleKeys.ps1 -WhatIf` says
  0 lines.
- Forever: none of the five IDs is a category, a zone row or a quest's category there (Forever numbers
  its categories by zone), so its files are untouched and `Build-ForeverMenu.ps1 -Check` still finds
  them up to date.

What files a new quest of those zones. The tools read the categories, the zone rows and the menu from
the Lua files, and nothing in `tools\` or the addon names the five IDs. What they matched on was the
categories' English names and the zone rows: `Place-UncategorisedQuests.ps1` matched a quest's API area
to a category of the same name, then went through the zone table. With the categories gone, the area
rule falls to "the zone containing the API area", which reaches the re-pointed rows. To prove it, the 14
quests were put back in category 0 with their old zone text in a scratch copy of the data, and
`Place-UncategorisedQuests.ps1 -WhatIf -Explain` was run on master's tables and on the branch's. Master
files them in 32, 86, 257, 1049 and (ten of them) 316. The branch files all 14 in the five targets of
the table (12 by the zone containing the API area, 2 by the pin's map); the other 30 quests it would
place, and the 745 it leaves, are the same on both.

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
Elf Death Knight at the default settings 61 of retail's 480 categories and 15 of Forever's 113 open
empty; the reachability report lists them.

## Question 31: what the removal changed

R32 is done, on the user's word of 11 October 2026, in a pass after question 24. A category definition
counted as unused when no quest in `data\quests.jsonl` carries it, no menu entry names it (`arg1`), no
row of `qcAreaIDToCategoryID` has it as a value, and nothing else names it: not `qcCategoryClientName`,
not `QC_ZONE_EXTRA_CATEGORIES` in `qcContinentPins.lua`, and not the category numbers in the scripts of
`tools\` (the 16 that `Place-UncategorisedQuests.ps1` names in its hand-kept rules are all in
use; `Audit-QuestHolidays.ps1`, `Build-ForeverMenu.ps1` and `Audit-DungeonCategories.ps1` name none). The five
categories of question 24 held quests, so none of them was among the 83: on that branch 563 definitions
were left, 480 of them holding quests.

**One of the 83 stays: Island Expeditions (1130).** `Build-QuestLocationData.ps1` and
`Import-RecordedGivers.ps1` list it in `$systemCategories`, the categories whose quests they skip, and
`Test-RecordedGivers.ps1` repeats the list. No quest is filed under it, so the definition is harmless, but
the call was to keep what something still names, so the row stays with its locale key `ISLANDEXPEDITIONS`.
Forever is untouched: it numbers its own categories, all 113 hold quests, and the six IDs it shares with the
83 (4, 8, 38, 44, 405 and 406) are Blasted Lands, Swamp of Sorrows, Loch Modan, Redridge Mountains,
Desolace and Stonetalon Mountains there, each in use.

The 82 removed:

| ID | Name | ID | Name | ID | Name |
|---|---|---|---|---|---|
| 4 | Ahn'Qiraj War | 286 | Cragplume Cauldron | 429 | Acherus: The Ebon Hold |
| 8 | Ammen Vale | 294 | Logging | 500 | Stranglethorn Vale |
| 34 | Camp Narache | 296 | Pickpocketing | 501 | The Barrens |
| 35 | Cataclysm | 297 | Ruins of the First Bastion | 1043 | Argus |
| 38 | Chill Breeze Valley | 300 | Spire of Light | 1048 | Emerald Dreamway |
| 41 | Coldridge Valley | 303 | Stormshield Stronghold | 1066 | Mechagon City |
| 44 | Dalaran City | 304 | Tailthrasher Basin | 1106 | Siege of Zuldazar |
| 48 | Darkspear Strand | 307 | Teluuna Observatory | 1110 | Uldir |
| 56 | Designer Island | 309 | The Forgotten Caves | 1131 | The Great Sea |
| 73 | Epic | 310 | The Howling Crag | 1208 | Zereth Mortis Campaign |
| 75 | Eye of the Storm | 313 | Warspear Outpost | 1290 | Shadowlands Uncategorized Quests |
| 99 | Hillsbrad | 317 | Garrison | 1411 | Tazavesh |
| 109 | Invasion | 403 | The Battle for Gilneas | 1422 | Dhar Bandar |
| 111 | Isle of Conquest | 404 | Twin Peaks | 1423 | Earthen |
| 123 | Legendary | 405 | Silvershard Mines | 1424 | Mourning Rise |
| 144 | New Tinkertown | 406 | Temple of Kotmogu | 1504 | Neighborhood |
| 160 | Redridge Canyons | 409 | The Black Morass | 1507 | Storm Fileds |
| 162 | Reputation | 412 | Terrace of Endless Spring | 1701 | Heart of the Forest |
| 167 | Ruins of Uldum | 415 | The Maelstrom | 1705 | Spires of Ascension |
| 178 | Shadowglen | 416 | Mogu'shan Vaults | 1709 | Mists of Tirna Scithe |
| 189 | Skettis | 418 | Blackwing Lair | 1722 | Uldaman: Legacy of Tyr |
| 196 | Strand of the Ancients | 421 | Brawl'gar Arena | 1724 | The Stonevault |
| 210 | The Barrier Hills | 422 | Isle of Giants | 1726 | Ara-Kara, City of Echoes |
| 234 | The Thunder Forges | 423 | Plaguelands: The Scarlet Enclave | 1727 | The Rookery |
| 263 | Valley of Trials | 424 | Onyxia's Lair | 1728 | Darkflame Cleft |
| 268 | Warsong Gulch | 425 | Firelands | 1731 | Operation: Floodgate |
| 282 | Beastwatch | 426 | Theramore's Fall |  |  |
| 284 | Bloodmane Pridelands | 428 | Serpentshrine Cavern |  |  |

What else changed:

- `qcQuestCategories` has 481 rows instead of 563, and `qcCategoryUiMapID` 337 instead of 373 (36 of the
  82 took their name from a map; `Build-CategoryUiMapIDs.ps1` drops those rows). `qcCategoryClientName`
  stays at 111: `Build-CategoryClientNames.ps1` only names categories that hold quests, so it never had
  a row for one of the 82. `qcAreaIDToCategoryID` (1,109 rows) and `qcMenu.lua` named none of them and
  are as they were. A Lua dump of retail's menu before and after is identical (557 items), a dump of
  `qcQuestCategories` shows exactly the 82 rows gone and the other 481 in their old order, and
  `data\quests.jsonl` and the generated Lua data files are byte for byte what they were: the 480
  categories that hold quests are the same.
- Locale files: 12 keys go from all 11 (`THEBARRENS` is in English only), 122 lines: `DHARBANDAR`,
  `EARTHEN`, `MOURNINGRISE`, `NEIGHBORHOOD`, `SIEGEOFZULDAZAR`, `SKETTIS`, `SPIREOFLIGHT`,
  `STORMSHIELDSTRONGHOLD`, `STRANGLETHORNVALE`, `THEBARRENS`, `WARSPEAROUTPOST` and
  `ZERETHMORTISCAMPAIGN`. Three more of the 82 had a key that something else still needs, so it stays:
  `AHNQIRAJWAR` and `INVASION` are what Forever's own "Ahn'Qiraj War" and "Invasion" fall back to, and
  `THEMAELSTROM` is the fallback of the heading the client names. The other 67 never had one.
  `Test-Localization.lua` counts 159 keys of English's own (171) and 130 of each other language's (141).
- `Remove-ConvertedLocaleKeys.ps1` found only 2 of the 12 (`STRANGLETHORNVALE` and `THEBARRENS`, whose names
  categories of Forever's still carry). It skipped every other key that no category, heading or code named,
  as the addon's own text, and the key of a category that has just been deleted is exactly that, so
  `Test-Localization.lua` called the other 10 unused and the tool left them. It now removes an English key
  nothing uses (`maintenance.md` already said it did), counting any string literal of capitals as a use so
  that keys picked through a table, such as `UNAVAILABLEACCEPTED`, stay. On the branch's base it still
  reports 0 lines, and on the branch it reports 0 after the run.
- `Add-ZoneTableMaps.ps1`: its header used two of the removed categories as examples (500 "Stranglethorn
  Vale", empty, and 429, Acherus); reworded. Its `-WhatIf` gives the same result as before (one map to
  add, 2162 Alterac Valley, found before too).
- `maintenance.md`: the key example under "Text in other languages" (`STRANGLETHORNVALE` is gone), the
  list of what `Remove-ConvertedLocaleKeys.ps1` removes (step 5), and a paragraph on unused definitions
  beside the one on merging categories (step 6).

What the tools say now:

- `Place-UncategorisedQuests.ps1 -WhatIf -Explain` on the branch and on its base: both would place 30
  quests (28 by the pin's map, 2 by storyline) and leave 745. The CSV differs in one cell: quest 53131's pin
  on map 1156 "The Great Sea" used to name category 1131 (by the map's name; no menu entry reaches it) and
  names none now. A quest whose category is not defined still goes to Uncategorized, as the note on category
  287 says: with quest 9319 put in category 4 (removed) in a scratch copy of the data, the tool would place 31
  quests, the extra one by "undefined category, to Uncategorized".
- `Audit-DungeonCategories.ps1`: the same 55 lines but two. The Black Morass (409) and Firelands (425)
  were "not in the menu" and are "no category" now, with the same 3 and 1 tied quests filed elsewhere. The 16
  instances whose unused category went (Blackwing Lair, Uldir and the like) no longer list one in the CSV.

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
  stops on any task `FLAG` (since 11 October 2026 reason 3 is the override).
- `Audit-DungeonCategories.ps1` reported "not in the menu" for The Black Morass (409) and Firelands
  (425), two empty categories whose zone rows were among the deletions. Question 31 removed both, and it
  says "no category" for them now.
- The runbook's step-10 reachability example uses `tools\UiMap-<build>.csv`. Only the 70205 map file
  is in `tools\`, while the docs name 70245 as the current beta build.
- Docs, updated with this change: `maintenance.md` step 6 (the name-prefix list of
  `Place-UncategorisedQuests.ps1`), `unavailable-quests.md` (503 `KEEP` rows, 218 `FLAG`) and
  `forever.md` (Camping under Professions, no rows for undefined zones). Nothing else writes down
  Timerunning's place (`maintenance.md` only names it as an example), and no Dungeon Journal audit
  baseline names Scarlet Halls.
- Quest 31611 has a second pin, on map 433 (The Veiled Stair, category 236), next to its pin on
  Kun-Lai Summit's map; both are Brewmaster Boof's. The quest is filed under Kun-Lai Summit as the
  call named it, and the pin stays where it was.
- `Audit-QuestHolidays.ps1` reads the heading a quest is filed under as a signal. The ten Darkmoon
  Island quests, now under "Darkmoon Faire", are untagged on purpose, so the audit lists ten more
  findings (67, against master's 57) and every one is covered by its `KEEP` row (0 new). The rows'
  evidence text still says "category 316"; it is a dated record and was left as it is.
- Quest 38934 ("Silas' Secret Stash", Darkmoon Faire since before this change) still has "Darkmoon
  Island" as its zone text, where the other 68 quests of category 46 say "Darkmoon Faire". Left alone:
  the call named 14 quests.

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
- 2026-10-11: question 20 approved by the user and done on `data/flag-placeholder-quests`: the 22 placeholder-named quests that still showed are flagged (20 with reason 1, the 2 task quests with the builder's new reason 3, added in a second commit). Checked offline: `luac -p` is silent on all 44 Lua files; `Build-AddonData.ps1 -Check` passes; `qcUnavailableQuests.lua` gains exactly the 20 IDs; `Test-QuestReachability.lua` (both games) gives a report identical to master's, because it sweeps with every hide filter off, "Hide quests that are no longer available" included; with the default list settings the 20 are hidden for a character that has not done them and shown for one that has, or has them in its log, and the count of quests passing the default list falls from 18,052 to 18,033 for a Horde Blood Elf Death Knight (one of the 20 is Alliance-only); `Test-Localization.lua`, `Test-Settings.lua`, `Test-MapTooltip.lua`, `Test-SeasonalCalendar.lua` and `Test-ContinentPins.lua` (all both games) pass, and the continent icons count 9 fewer quests on Retail (13,447 to 13,438). Not tried in game: that the 20 are gone from the list, the map and the zone counters, and that the 9.1 Campaign entry opens empty. The numbers above were measured for the first 20; the second commit only adds 86645 and 94815 to the Lua file and changes its header line.
- 2026-10-11: question 26 approved by the user and done, on branch `feat/empty-list-hidden-count` (cut from master 956ef50): an empty quest list says "Quests hidden by your filters: N" (`qcShowHiddenQuests` in `qcCore.lua`, a text `qcHiddenQuests` in `QuestCompletist.xml`, the new key `QUESTSHIDDEN` in all 11 locale files, the ten translations marked `-- Needs review`); every entry stays and no quest moved. Checked offline: `luac -p` is silent on all 27 addon Lua files, `Test-Localization.lua` says "No problems", `Test-QuestReachability.lua` (both games) has 0 Lua errors and a report equal to master's apart from its new section, whose checks (1,036 on retail, 292 on Forever) all pass and fail 82 and 37 of them on master's code, `Test-Settings.lua`, `Test-MapTooltip.lua`, `Test-ContinentPins.lua` and `Test-SeasonalCalendar.lua` (both games) say "All checks passed.", `Test-Recorder.lua` says "0 failed", and `Build-AddonData.ps1 -Check` says all four files are up to date. Not tried in game: how the line looks in the list (a centred line over the first rows).
- 2026-10-11: question 24 approved by the user and done, on branch `feat/merge-small-categories` (cut from master 847ffda): Darkmoon Island and the four one-quest categories merged into their zones, 14 quests refiled, five categories deleted with their menu entries and client-name rows, four zone rows re-pointed (the detail is under "Question 24" above). Checked offline: a per-quest comparison of `data\quests.jsonl` with master (35,023 records, exactly the 14 differ, only in `category` and `zone`); a Lua dump of retail's menu before and after (only the five entries gone, 562 items to 557, nothing else moved); `qcQuestCategories` 568 rows to 563, `qcCategoryUiMapID` 376 to 373, `qcCategoryClientName` 113 to 111; `luac -p` is silent on all 48 Lua files; `Build-AddonData.ps1 -Check` passes; `Test-Localization.lua` says "No problems"; `Test-Settings.lua`, `Test-MapTooltip.lua`, `Test-ContinentPins.lua` and `Test-SeasonalCalendar.lua` (both games) say "All checks passed." (the continent icons count 4 more quests on retail, 13,436 to 13,440, because the four one-quest categories' quests now count in their zone's icon); `Test-QuestReachability.lua` (both games: 0 Lua errors, 0 quests in categories the list can't browse to) gives Forever's report as master's, and retail's as master's apart from the category count (485 to 480) and the empty-list checks (1,036 to 1,026, with the same 61 categories empty by default); `Remove-EmptyMenuEntries.ps1 -WhatIf` and `Remove-ConvertedLocaleKeys.ps1 -WhatIf` report 0; `Build-ForeverMenu.ps1 -Check` says Forever's three files are up to date; `Audit-DungeonCategories.ps1` gives master's result to the byte; `Audit-QuestHolidays.ps1` lists 67 findings against master's 57, none new (the ten more are the Darkmoon Island quests, covered by their `KEEP` rows, see "Noticed along the way"); the two generators reproduce master's tables byte for byte from master's inputs; and the 14 quests put back in category 0 file under the five targets on the branch and under the old IDs on master. Not tried in game: that the five entries are gone from the menu, that the 14 quests list under their zones, and that entering the maps of Greenstone Village, Unga Ingoo, Brewmoon Festival and Thunder Totem switches the list to their zones.
- 2026-10-11: question 31 approved by the user and done, on branch `chore/remove-unused-categories` (stacked on `feat/merge-small-categories`, which must merge first): 82 of the 83 unused category definitions removed with their `qcCategoryUiMapID` rows and 12 locale keys; Island Expeditions (1130) kept because `Build-QuestLocationData.ps1` and `Import-RecordedGivers.ps1` name it (the detail is under "Question 31" above). Checked offline: `data\quests.jsonl` and the generated Lua data files byte for byte unchanged; a Lua dump of retail's menu before and after identical (557 items); `qcQuestCategories` 563 rows to 481, exactly the 82 gone, the rest in their order; `qcCategoryUiMapID` 373 to 337, `qcCategoryClientName` 111 as before; `luac -p` is silent on all 48 Lua files; `Build-AddonData.ps1 -Check` and `Build-ForeverMenu.ps1 -Check` pass; `Test-Localization.lua` says "No problems" (English 171 keys to 159, the others 141 to 130); `Test-Settings.lua`, `Test-MapTooltip.lua`, `Test-ContinentPins.lua` and `Test-SeasonalCalendar.lua` (both games) say "All checks passed.", and the first three print what the base's print (apart from the continent pass's timing line, and the tooltip's call record is identical too); `Test-QuestReachability.lua` (both games: 0 Lua errors, 0 quests never shown) gives reports byte for byte equal to the base's; `Remove-EmptyMenuEntries.ps1 -WhatIf` and `Remove-ConvertedLocaleKeys.ps1 -WhatIf` report 0; both generators reproduce the branch's tables byte for byte; `Audit-QuestHolidays.ps1` finds the same 67 (0 new); `Audit-DungeonCategories.ps1` and `Place-UncategorisedQuests.ps1` give the base's result but for the lines under "What the tools say now". Not tried in game: nothing visible changes, so what matters is that the menus and the lists load without a Lua error.
