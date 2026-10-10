# Open items and calls kept

What was decided on 7 and 8 October 2026, and what is left to come back to. Each item points at the
document that has the detail. When one is done, change its line here and say so in that document's
status.

## Calls kept

The user agreed all of these ("keep all of these calls", 8 October 2026):

- **A normal quest gets a pin wherever a source puts where it is picked up, with or without an NPC,
  and never a world quest; the same for every game that has the data, and the steps are in the
  runbook for every sweep.** Retail: [maintenance.md](../maintenance.md) steps 5 and 6;
  Forever: step 10; the rule and its limits per game are in
  [game-parity.md](game-parity.md), data row "Pickup sources for pins".
- **No quest leaves the data unseen, and a missed answer doesn't remove one** (10 October 2026). The
  importer stops and lists any quest it would drop, with ID, name and zone, and waits for a KEEP or
  REMOVE row in `quest-removal-decisions.csv`; `Show-RemovedQuests.ps1` does the same for either game
  before a pull request. The beta's API sometimes doesn't return quests it has (Christmas quests among
  them), so Forever's importer keeps a quest's last record until it has missed 10 runs in a row, and
  then asks. Kept by the user: 79482, 79483, 79492, 79495, 93188 and 93196
  ([forever.md](forever.md), "The beta's answers differ between runs").
- **A pin stands where a quest starts (`QuestPOIBlob` point 32), never at the hand-in.**
  [quest-location-data-pipeline.md](quest-location-data-pipeline.md), "pins at the start".
- **A quest that starts in several places gets a pin at each, up to six** (class and race quests
  start in several cities, as in the client's own data); more go to
  `tools\quest_locations_tdb_review.csv`.
- **A nameless pin is fine; a wrong NPC name is not.** A quest joins a neighbour's identity only if
  that NPC starts it, and by-hand names go in `pin-giver-decisions.csv`, each read on Wowhead.
- **Untested changes wait** unless the user says to ship them: a pull request that changes the addon
  and hasn't been tried in game is not in the release ([releasing.md](../releasing.md), step 1).
  #223 and #224 went out in 112.5 on the user's word.
- **Continent maps get one icon per zone** (10 October 2026, "go with your picks"): the quests left
  to do in the zone, counted from the quest list's categories with the map's filters and without
  daily, weekly and repeatable quests, hovered for counts and progress, opened with a click, with a
  child option of "Show Map Icons" that is on by default. Capitals fold into their host zone, and the
  continents inside a continent (Quel'Thalas, Argus) get an icon on the outer map that opens them. Built
  in eight pull requests, the first of them the probe's geometry pass
  ([continent-pins.md](continent-pins.md)).
- **A check stays in the sweep even while it finds nothing**, and every feature or check built for
  one game goes to both unless a game can't support it
  ([game-parity.md](game-parity.md)).
- **Every change and sweep uses the newest version of every data source**: the client's files, the
  in-game probes and the external databases (9 October 2026). The beta moved from 70245 to 70291 to
  70338 in three days while the tables and the probe list stayed behind. `Get-LatestBuilds.ps1` is
  step 0 of the sweep and is run again before each in-game session
  ([maintenance.md](../maintenance.md), "Before a sweep").

## To try in game

Keep the manual checking small. The user has said (9 October 2026) that long in-game test sheets are
too much to ask. The code and the data are checked offline (the real addon files under stand-in APIs,
counts recomputed a second way, the repo's test tools), so ask for in-game testing only for what the
game alone can answer, such as what an API call returns or how retail and Forever differ, as a few
lines per game and a few minutes in all, and say what was verified offline instead of asking for it
again.

- **The continent icons** (built, untried; the probe's geometry pass is built too): both games'
  dumps were read on 10 October and are the baseline (`continent-geometry-baseline.csv`, sweep step
  2f); retail's next dump comes with its map pass once 12.1.5 is live, plus `/qcprobe geometry`
  with the world map open on a continent, windowed and then maximised. One
  look at the icons on each game, five observations in about three minutes ([continent-pins.md](continent-pins.md), "To try in game").
- **The pins of #223 and #224** (193 quests with only a start point, and 1,453 more from
  TrinityCore's start points) shipped in 112.5 without an in-game check: the user, shown a list of
  spots to check, said it was too much to check by hand and to go ahead (8 October 2026). When
  convenient, look at a few, and at these: quest 1036 "Avast Ye, Scallywag" (its pin is where the
  client puts its end, not at "Pretty Boy" Duncan), the class quests at Orgrimmar's and Stormwind's
  hubs, the Silithus sigil quests (45749 to 45762, which may be retired), and the pins on the Caverns
  of Time.
- **The pins moved to quest starts (#219)** are checked by the user for a sample, not for every
  zone.
- **The menu review (#251, released in 112.7 untried; the starter areas only).** The offline checks cover the menus: every category with
  quests has a menu entry and a zone row, none is empty, and the reachability run leaves no quest out.
  What only the game can show is the four starter areas, whose quests are filed under their parent
  zone: walk into Camp Narache, Shadowglen, Valley of Trials and New Tinkertown and see the list follow
  Mulgore, Teldrassil, Durotar and Dun Morogh ([menu-review.md](menu-review.md)).
- **The calendar window's filters, on both games (#243, released in 112.6 on 9 October 2026).** The
  seasonal filter treats a holiday whose filter is unticked as running, on the reading of Blizzard's
  source that the game then leaves its events out of the calendar. Nobody has seen that in game.
  The whole check is seven lines per game, entered one at a time (a pasted block is joined into one
  chat line), in a city with the calendar window shut:

  ```text
  /qc holidays
  /run function QCL(c) local t,s={},"" for d=1,c.GetMonthInfo(0).numDays do for i=1,c.GetNumDayEvents(0,d) do local e=c.GetDayEvent(0,d,i) local k=e.calendarType:sub(1,6)..(e.eventID or 0) if not t[k] then t[k]=1 s=s..k.." " end end end print(s) end
  /run QCL(C_Calendar)
  /run print(SetCVar("calendarShowHolidays","0"),GetCVar("calendarShowHolidays"))
  /run QCL(C_Calendar)
  /qc holidays
  /run print(SetCVar("calendarShowHolidays","1"),GetCVar("calendarShowHolidays"))
  ```

  Paste back the first `/qc holidays` (it also lists the other calendar holidays), the two lists, the
  two read-backs (`nil 0` and `nil 1`, or `true` for `nil`) and the filter line of the second
  `/qc holidays`.
  - `HOLIDA324`, and `HOLIDA1405` on retail, are in the first list and missing from the second: the
    game drops an unticked filter's events, and the handling is needed. In both lists: the game keeps
    them, the handling is harmless but unneeded, and the user decides whether to keep it. Anything
    else (another ID gone, an error, a read-back that did not change): the table `qcHolidays` or the
    CVars need another look.
  - It leaves unseen, on purpose: that Darkmoon and the fishing contest sit under their filters (the
    table is the client's own `CalendarFilterType`, and the handling fails open, so an unticked
    filter shows the quests), whether ticking a box fires `CVAR_UPDATE` (the map notices at its next
    draw; a listener was left out), and the map with a filter unticked (tested offline). The longer
    experiment is in [maintenance.md](../maintenance.md), "Holidays", for a puzzling result only.
  - The user decided on 9 October 2026 to go with #243 without this check, and to deal with any
    problem when it shows, so it shipped in 112.6. The seven lines stay for whoever wants to
    run them. When they have been run, change the "not yet seen in game" wording in maintenance.md
    ("Holidays") and in the C_Calendar section of [game-api-review.md](game-api-review.md), and take
    this item off the list.

- **Which API reads an expansion's profession skill, on retail (two lines, retail only).** Retail's
  skill requirements are on expansion skill lines: of the 524 task quests with a skill filter, 464
  name one ("Legion Mining" 2566, "Kul Tiran Herbalism" 2549, "Legion Skinning" 2558, whose parents
  in `SkillLine.csv` are the base professions 186, 182 and 393) and 60 a base line (Fishing 356 x44,
  Jewelcrafting 755 x12, Tailoring 197 x4). Offline, Blizzard's own profession book
  (`Blizzard_ProfessionsBook`) reads `GetProfessionInfo` as rank and maximum of a line it titles
  with the 11th value `skillLineName`, with a base `skillLine` in the 7th (it hands that one to the
  unlearn dialog); that the line is the newest known one is an inference from that code, not seen.
  So the fallback in `qcSkillRank` can answer for the base lines and for nothing else, which is why
  it says "can't say" for the rest. The API that may answer for an expansion line is
  `C_TradeSkillUI.GetProfessionInfoBySkillLineID`; what the game alone can say is whether it works
  with the professions window shut and returns the character's level. On a retail character with a
  profession, best one with an older expansion's skill, in a city, window shut, entered one at a
  time:

  ```text
  /run for _,i in pairs({GetProfessions()}) do print(GetProfessionInfo(i)) end
  /run for _,l in ipairs(C_TradeSkillUI.GetAllProfessionTradeSkillLines()) do local i=C_TradeSkillUI.GetProfessionInfoBySkillLineID(l) if i and (i.skillLevel or 0)>0 then print(l,i.professionName,i.skillLevel,i.maxSkillLevel) end end
  ```

  Paste back both outputs.
  - The second lists expansion lines (2566 and the like) with the character's levels: the API reads
    them with the window shut, and `qcSkillRank` can use it on a client without `C_SkillInfo`, then
    the data from `QuestV2CliTask` and TrinityCore (recommendation 3 of
    [game-parity.md](game-parity.md)). Nothing, a Lua error, or only base lines: it needs the window,
    and an expansion line stays "can't say" on retail; the data then covers the base lines only.
  - The first shows whether the 7th value is a base line (164, 186 ...) and the rank the newest
    line's, as read above.
  - No offline test can answer this: the stand-ins for the client only return what they are given.
- **The recorder** (#228, released in 112.7 untried), on both games: a full WoW restart, then the list in
  [quest-giver-recorder.md](quest-giver-recorder.md) ("To try in game"): the order of the events,
  whether the game hides who is speaking, whether the popup hook fires, what the options panel
  looks like in the longest language. It went out in 112.7 on the user's word, without this session
  (9 October 2026), so the session now checks what players already have.
- **The probe on both games** (`tools/ForeverProbe`): **run and read** on 9 October (retail 12.1.0.69933:
  35,023 quests, 8,418 NPCs, 1,961 maps; the Forever beta, 70291) and 10 October (Forever, 70338); the
  results are in `tools\retail_probe_69933\` and `tools\forever_probe_70338\`. Pin names: 10,562 of
  10,564 retail pins and 1,503 of 1,503 Forever pins are the game's own. The map totals are those of 7
  October (retail 439 offers; Forever none, 16 points of interest). All twelve fact functions exist on
  both clients, `GetQuestExpansion`, `IsBreadcrumbQuest` and `IsStoryQuest` among them, but Forever
  returns inert values for most (every expansion -2, no tasks, campaigns or story quests). Still open:
  whether `GetQuestLineInfo` answers for a quest the server refused, and whether `IsAccountQuest` needs
  loaded data. The probe now tallies every fact function on the quests it is refused (`refusedFacts` in
  the quest run's row) and records the character and level of every run, so the next run answers both,
  and says whether the beta's answers follow the character: copy the probe folder into the AddOns
  folders again first, then read the file with `Read-ForeverProbe.lua <file> facts`. The next run is
  retail's, once 12.1.5 is live (13 or 14 October): run `Get-LatestBuilds.ps1` first, then the same
  three commands, so the 9 October results are the baseline.

## Decisions waiting for the user

| # | Decision | Recommendation | Detail |
|---|---|---|---|
| 1 | Add the about 535 player-facing task quests the database lacks (decision 9), with no pins | yes, as an inflow step from `QuestV2CliTask` that skips hidden trackers | [game-api-review.md](game-api-review.md), "Decisions to take" |
| 2 | Pin any of the 4,082 task quests already in the data that have a start (1,387 are world quests) | no for world quests; the NPC-started ones need a rule first | quest-location-data-pipeline.md, "pins for quests with only a start point" |
| 3 | 82449 "The Call of the Worldsoul", a task-table quest | a hand entry on the Worldsoul pins | same |
| 4 | Item-started quests with a start point but no NPC (about 13% of all pins) | keep pinning them, as before | quest-location-data-pipeline.md, "pins from TrinityCore" |
| 5a | What a creature's offer lets a quest have a pin for ([quest-giver-recorder.md](quest-giver-recorder.md), "The merge tool", Adds): the holds on a quest that no creature offers (not in `QuestV2`, a task of another kind than world, bonus or hidden, Landfall, holiday, profession, a quest type other than 0, 1, 2, 4 and 128) are waived when a creature offers it; system categories, unavailable and internal-name quests stay held | keep: an NPC offering a quest is the best proof it is a real pickup; the report counts the quests by class. This settles decisions 2 and 5 case by case for NPC-offered quests. To undo a class, edit `$isPinnable` in `Import-RecordedGivers.ps1`, or add a `KEEP` row for the quest | the plan, "Adds" |
| 5b | Which system category (Garrison Support, Torghast, Prey, Delves ...) may get pins from an offer | none until you say; the report lists them by category, and `$allowedSystemCategories` in `Import-RecordedGivers.ps1` is the switch | the plan, "Adds" |
| 5 | The Landfall dailies (31 without a pin, 29 with one already) and the Silithus sigil quests (10), which look retired | flag them in `unavailable-quest-decisions.csv` after a look at the evidence | unavailable-quests.md |
| 6 | The remaining decisions 1 to 7 of the API review (recorder on retail and the probe additions are agreed and built; scaling-aware levels, text from the game, waypoints, tracking toggles) | see that document | game-api-review.md |
| 7 | Pin-per-quest (retail) or pin-per-spot (Forever) for nameless pins | decide, then align the tool that differs | game-parity.md, recommendation 11 |
| 8 | Refresh retail's levels from the API: 1,611 quests differ from it (large blocks in Zaralek Cavern, Mechagon Island and the Emerald Dream, where the API gives a much lower minimum than we store), 4,955 have no API record, 246 are 0 | yes, from the API, after a look at those zones; a campaign or Chromie Time may gate some | client-tables-review.md (the note on `level`); maintenance.md, the data files |
| 9 | Scaling quests: the list bracket and the low-level filter read a scaling range's floor, so they judge a quest low level too early | probe first: what `IsQuestTrivial` and `GetQuestDifficultyLevel` return in game on both clients, then decide | game-api-review.md, recommendation 4 |
| 10 | Holiday flags for the retail events `qcHolidays` has none for: the four Dragonriding cups (16 quests, 12 with pins, so those pins show all year), Secrets of Azeroth, WoW Anniversary, Dastardly Duos, the weekly bonus events, and the 54 Ahn'Qiraj War Effort and Scourge Invasion quests | a flag per event, tied to the calendar ID that `/qc holidays` lists under "Other calendar holidays" while it runs; one flag per cup or one shared is the user's call | `quest-holiday-decisions.csv`, the PENDING rows |
| 11 | Two quests of the holiday record: 56322 "Contained Alemental" (Wowhead lists Event: Brewfest) and the 12 "Bar Tab Barrel" quests, tagged Brewfest but still filed under the Dragon Isles zones, unlike the ten already under Brewfest | tag 56322; refile the Barrels | `quest-holiday-decisions.csv` |
| 12 | Forever's 29 untagged seasonal quests (none has a pin: 12 Children's Week and 6 Winter Veil by a hand list, 9 Scourge Invasion and 2 Ahn'Qiraj War Effort by an importer rule), and its calendar gaps: no dates for Children's Week or the Darkmoon Faire on the beta, and a nameless Winter Veil-like Holidays row, 1879, that the date decode puts from 15 November (not confirmed in game) | tag them in the importer; run `/qc holidays` on the beta before 15 November and add 1879 to Winter Veil's IDs if it reports it | forever.md; maintenance.md, "Holidays" |
| 13 | A level of 0 or below reads as a level: 246 retail and 12 Forever quests show "[0]" in the list and count as low level for everyone | treat it as no level in the two readers | `qcCore.lua`, the list row and the low-level filter |
| 14 | Retail's gate level from the content tuning (the other way to row 8, which uses the API's minimum): `level` stays the row's own and `qcQuestMinLevel` carries the gate, as on Forever; 1,828 quests change | yes | [retail-quest-cache.md](retail-quest-cache.md), "Level"; the other way to row 8 |
| 15 | Backfill reputation rewards from the cache for the 2,043 quests the API has no record of that reward a visible faction | yes, after in-game checks of five quests | same, "Reputation"; the quests are the `cache-only` rows of `quest_reputation_compare.csv` (`Compare-QuestReputation.ps1`) |
| 16 | Type changes the cache shows: 37 daily that are weekly, 92 repeatable that Blizzard calls daily or weekly, 4 that recur and are ticked for ever, 17 repeatable by the Darkmoon-deck rule, 38 one-time task quests, 21 test or deprecated titles | class by class | same, "Recurrence and flags" |
| 17 | Race changes: the two outright contradictions (quest 2, 27675), 19 stale masks, 49 starting-race narrowings, 28 where we show a quest to races the server denies | the contradictions and stale masks yes; the narrowings are a call; the 28 class by class | same, "Races" |
| 18 | Sort fixes: 98 Uncategorized quests whose sort names one category, 27 profession misfiles | yes | same, "Sort" |
| 19 | "Starts from" only from `ItemSparse.StartQuestID` or `QUEST_DETAIL`, never from the cache's `startItem` | yes | same, "Start item" |
| 20 | The 22 placeholder-named quests that still show in default lists (menu review R08) fail the step-7 evidence rules: flag them anyway? | yes, the 22 that show; the same call as 5 October on the 19 internal entries | [menu-review.md](menu-review.md), question 20 |
| 21 | One submenu shape for every expansion (R28) | Main Zones and Other Categories for Draenor and The Broken Isles; Outland, Northrend and The Maelstrom stay flat | [menu-review.md](menu-review.md), question 21 |
| 22 | Midnight: move Founder's Point and Razorwind Shores into Other Categories (R27) | yes | [menu-review.md](menu-review.md), question 22 |
| 23 | Split Lordaeron into Lordaeron, Quel'Thalas, Gilneas and Tol Barad (R26) | yes, named from the client's maps | [menu-review.md](menu-review.md), question 23 |
| 24 | Merge Darkmoon Island into Darkmoon Faire and four one-quest entries into their zones (R15, R31) | yes, in one pass, because a category merge changes how the sweep tools file new quests | [menu-review.md](menu-review.md), question 24 |
| 25 | Names that repeat, groups and categories that share a name, Forever's "Invasion" (R17 to R21, R25, F03) | leave; if it matters, show the menu path in the list header (no new text) | [menu-review.md](menu-review.md), question 25 |
| 26 | Entries empty by default and tiny entries (R29, R30, R39, F06, F07, F09) | keep them, and have an empty list say how many quests the filters hide | [menu-review.md](menu-review.md), question 26 |
| 27 | Rated PvP, 86 of 87 quests unavailable (R06) | keep | [menu-review.md](menu-review.md), question 27 |
| 28 | Class Quests has no Evoker (R05) | leave | [menu-review.md](menu-review.md), question 28 |
| 29 | Ordering rule for Retail's lists (R33) | keep the hand order | [menu-review.md](menu-review.md), question 29 |
| 30 | Forever: split Seasonal, and Deeprun Tram and Special loose (F04, F05) | leave until after the 4 November launch | [menu-review.md](menu-review.md), question 30 |
| 31 | Remove the 83 unused category definitions (R32) | yes, in a pass of its own, after 24 | [menu-review.md](menu-review.md), question 31 |

## Data to finish

- **Names for about 20 pet-battle tutorial quests** that stand nameless on their trainers' pins
  (Narzak, Ansel Fincap, Grady Bannson, Valeena, Will Larsons, Matty, Jarson Everlong, Lehna): one
  Wowhead check per city, then `FILL` rows in `pin-giver-decisions.csv`.
- **Names the TrinityCore pass left**: the Chromie Time breadcrumbs ("Onward to Adventure", 11
  quests), 41852 and 41853 under Brewer Almai, 41627 and 26149 beside pins of their twins that carry
  an object's name, and six stacks where a new pin names an NPC whose sibling quests sit on nameless
  old pins (Neeka Bloodscar, Merda Stronghoof, Keeper Remulos, Captain Verne, Bodrick Grey, Griff).
- **Three holiday quests with no holiday tag** that were pinned: 47430 (Moonkin), 79178 and 79694
  (Hearthstone anniversary). They want their holiday value.
- **The 157 quests in `quest_locations_tdb_review.csv`**: placeholder starts (raid-wing quests, the
  Draenor garrison points, Mechagon, Nerub-ar Palace), starts outside every map, more than six
  places. Look through it after every run of step 6.
- **2,766 quests TrinityCore has a start for that the database lacks**: a list to look through for
  the step that adds quests the database lacks (`Fetch-GapQuestData.ps1`).
- **Forever's 1,414 pinless quests** have no pickup data in any source; the recorder is the way
  ([forever.md](forever.md)). About 60 of the new retail pins are for quests started by an object and about 120 by an
  item alone, and have no name; Forever names its pins after the object or item (game-parity.md, recommendation 12).
- **Pins and where they came from**: a pin does not record its source, and a new rule takes no pin
  away. A removal route (a decisions file like the unavailable quests') is open.
- **Uncategorized after the Infinite Research refile**: a plain
  `Place-UncategorisedQuests.ps1 -Refile 0` would move 30 more (28 by pin's map, 2 by storyline);
  look through them with `-WhatIf` ([menu-review.md](menu-review.md)).
- **272 quest IDs on pins or prerequisites with no quest row** (267 on pins only, 5 prerequisites
  only: 30490, 54130, 59174, 89285, 91799): parked since phase 2 of
  [data-cleanup.md](data-cleanup.md); the menu review found nothing new.

## Code to finish

- **`qcMergeStackedPins`** (`qcMapPins.lua`) should let a named pin anchor a stack. In 53 stacks a
  new nameless pin now sorts first, so a click sets a waypoint titled with a quest's name, not the
  NPC's.
- **One quest on the edge of a map**: 26064 sits at the top of Mulgore, where its other points say
  Stonetalon. A start within about one map point of an edge should prefer the map its other
  points are on.
- **A start on a disabled map** is held back; 79085 and 81640 want hand entries on Hallowfall's map.
- **README** says retail has "over 15,000" quest-giver pins and Forever "around 1,700"; check both at
  each release.
- **`Build-CategoryClientNames.ps1`** still lists two expected differences, for categories 1221 and
  1430, that the spelling fixes made stale.

## The agreed order of work

From [game-parity.md](game-parity.md), decision 3, with what is done:

1. Profession skill fallback: **done** (#216).
2. Retail map pass: **done** (#219 carries its record).
3. **Built, waiting for the game:** the recorder on retail, with one probe for both games
   (recommendations 1 and 2). The addon half (#228) is released (112.7, untried) and waits for its in-game session;
   the merge tool (step 6d) waits for a real recording
   ([quest-giver-recorder.md](quest-giver-recorder.md)); the secrecy watch of step 2b is built; the
   probe is on master as a dev-only addon (#232 to #237), and both games' first runs are in (9 and 10
   October; see "To try in game").
4. The consistency checks of `Audit-QuestTables.ps1` and `Remove-DuplicatePinQuests.ps1` on Forever's
   data (recommendations 4 and 5): **done** (#238).
5. Retail's profession skill data, after one in-game check of what `GetProfessionInfo` reports for an
   expansion's skill line (recommendation 3): the two lines are under "To try in game".
6. The dungeon journal on Forever (**done**, #241: the client has no Journal tables), the quest cache
   reader on retail (**done**, #246, [retail-quest-cache.md](retail-quest-cache.md)), the importer's
   `QuestLine` row counts (**done**, #239) (recommendations 9, 6, 7).
7. A review of Forever's hidden and test quests, after its launch on 4 November (recommendation 10).

8. The continent icons ([continent-pins.md](continent-pins.md)): the plan, then the probe's geometry
   pass before retail's 12.1.5 map pass, then the counting and the icons.

Also: the 12.1.5 sweep when the patch is live (13 or 14 October; the TOC lists both interface
numbers), a Warband-filter check on the Forever beta, and the dated change of 1 April 2027
(releasing.md).

After the retail run of the 12.1.5 sweep has been read, and #262 (the probe's geometry pass) has merged, and
before Forever's launch on 4 November: **rename the probe** from `QCForeverProbe` to `QCProbe`, as one pull
request with local steps after it ([probe-rename.md](probe-rename.md), planned 10 October 2026, target the
week of 19 October). Nothing is renamed before then.
