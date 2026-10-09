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
- **A check stays in the sweep even while it finds nothing**, and every feature or check built for
  one game goes to both unless a game can't support it
  ([game-parity.md](game-parity.md)).

## To try in game

Keep the manual checking small. The user has said (9 October 2026) that long in-game test sheets are
too much to ask. The code and the data are checked offline (the real addon files under stand-in APIs,
counts recomputed a second way, the repo's test tools), so ask for in-game testing only for what the
game alone can answer, such as what an API call returns or how retail and Forever differ, as a few
lines per game and a few minutes in all, and say what was verified offline instead of asking for it
again.

- **The pins of #223 and #224** (193 quests with only a start point, and 1,453 more from
  TrinityCore's start points) shipped in 112.5 without an in-game check: the user, shown a list of
  spots to check, said it was too much to check by hand and to go ahead (8 October 2026). When
  convenient, look at a few, and at these: quest 1036 "Avast Ye, Scallywag" (its pin is where the
  client puts its end, not at "Pretty Boy" Duncan), the class quests at Orgrimmar's and Stormwind's
  hubs, the Silithus sigil quests (45749 to 45762, which may be retired), and the pins on the Caverns
  of Time.
- **The pins moved to quest starts (#219)** are checked by the user for a sample, not for every
  zone.
- **The calendar window's filters, on both games (#243, merged 9 October 2026, not released).** The
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
    problem when it shows, so it is in the next release. The seven lines stay for whoever wants to
    run them. When they have been run, change the "not yet seen in game" wording in maintenance.md
    ("Holidays") and in the C_Calendar section of [game-api-review.md](game-api-review.md), and take
    this item off the list.

## Decisions waiting for the user

| # | Decision | Recommendation | Detail |
|---|---|---|---|
| 1 | Add the about 535 player-facing task quests the database lacks (decision 9), with no pins | yes, as an inflow step from `QuestV2CliTask` that skips hidden trackers | [game-api-review.md](game-api-review.md), "Decisions to take" |
| 2 | Pin any of the 4,082 task quests already in the data that have a start (1,387 are world quests) | no for world quests; the NPC-started ones need a rule first | quest-location-data-pipeline.md, "pins for quests with only a start point" |
| 3 | 82449 "The Call of the Worldsoul", a task-table quest | a hand entry on the Worldsoul pins | same |
| 4 | Item-started quests with a start point but no NPC (about 13% of all pins) | keep pinning them, as before | quest-location-data-pipeline.md, "pins from TrinityCore" |
| 5 | The Landfall dailies (31 without a pin, 29 with one already) and the Silithus sigil quests (10), which look retired | flag them in `unavailable-quest-decisions.csv` after a look at the evidence | unavailable-quests.md |
| 6 | The remaining decisions 1 to 7 of the API review (recorder on retail, probe additions, scaling-aware levels, text from the game, waypoints, tracking toggles) | see that document | game-api-review.md |
| 7 | Pin-per-quest (retail) or pin-per-spot (Forever) for nameless pins | decide, then align the tool that differs | game-parity.md, recommendation 11 |
| 8 | Refresh retail's levels from the API: 1,611 quests differ from it (large blocks in Zaralek Cavern, Mechagon Island and the Emerald Dream, where the API gives a much lower minimum than we store), 4,955 have no API record, 246 are 0 | yes, from the API, after a look at those zones; a campaign or Chromie Time may gate some | client-tables-review.md (the note on `level`); maintenance.md, the data files |
| 9 | Scaling quests: the list bracket and the low-level filter read a scaling range's floor, so they judge a quest low level too early | probe first: what `IsQuestTrivial` and `GetQuestDifficultyLevel` return in game on both clients, then decide | game-api-review.md, recommendation 4 |
| 10 | Holiday flags for the retail events `qcHolidays` has none for: the four Dragonriding cups (16 quests, 12 with pins, so those pins show all year), Secrets of Azeroth, WoW Anniversary, Dastardly Duos, the weekly bonus events, and the 54 Ahn'Qiraj War Effort and Scourge Invasion quests | a flag per event, tied to the calendar ID that `/qc holidays` lists under "Other calendar holidays" while it runs; one flag per cup or one shared is the user's call | `quest-holiday-decisions.csv`, the PENDING rows |
| 11 | Two quests of the holiday record: 56322 "Contained Alemental" (Wowhead lists Event: Brewfest) and the 12 "Bar Tab Barrel" quests, tagged Brewfest but still filed under the Dragon Isles zones, unlike the ten already under Brewfest | tag 56322; refile the Barrels | `quest-holiday-decisions.csv` |
| 12 | Forever's 29 untagged seasonal quests (none has a pin: 12 Children's Week and 6 Winter Veil by a hand list, 9 Scourge Invasion and 2 Ahn'Qiraj War Effort by an importer rule), and its calendar gaps: no dates for Children's Week or the Darkmoon Faire on the beta, and a nameless Winter Veil-like Holidays row, 1879, that the date decode puts from 15 November (not confirmed in game) | tag them in the importer; run `/qc holidays` on the beta before 15 November and add 1879 to Winter Veil's IDs if it reports it | forever.md; maintenance.md, "Holidays" |
| 13 | A level of 0 or below reads as a level: 246 retail and 12 Forever quests show "[0]" in the list and count as low level for everyone | treat it as no level in the two readers | `qcCore.lua`, the list row and the low-level filter |
| 14 | Retail's gate level from the content tuning (the other way to row 8, which uses the API's minimum): `level` stays the row's own and `qcQuestMinLevel` carries the gate, as on Forever; 1,828 quests change | yes | [retail-quest-cache.md](retail-quest-cache.md), "Level"; the other way to row 8 |
| 15 | Backfill reputation rewards from the cache for the 2,043 quests the API has no record of that reward a visible faction | yes, after in-game checks of five quests | same, "Reputation" |
| 16 | Type changes the cache shows: 37 daily that are weekly, 92 repeatable that Blizzard calls daily or weekly, 4 that recur and are ticked for ever, 17 repeatable by the Darkmoon-deck rule, 38 one-time task quests, 21 test or deprecated titles | class by class | same, "Recurrence and flags" |
| 17 | Race changes: the two outright contradictions (quest 2, 27675), 19 stale masks, 49 starting-race narrowings, 28 where we show a quest to races the server denies | the contradictions and stale masks yes; the narrowings are a call; the 28 class by class | same, "Races" |
| 18 | Sort fixes: 98 Uncategorized quests whose sort names one category, 27 profession misfiles | yes | same, "Sort" |
| 19 | "Starts from" only from `ItemSparse.StartQuestID` or `QUEST_DETAIL`, never from the cache's `startItem` | yes | same, "Start item" |

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

## Code to finish

- **`qcMergeStackedPins`** (`qcMapPins.lua`) should let a named pin anchor a stack. In 53 stacks a
  new nameless pin now sorts first, so a click sets a waypoint titled with a quest's name, not the
  NPC's.
- **One quest on the edge of a map**: 26064 sits at the top of Mulgore, where its other points say
  Stonetalon. A start within about one map point of an edge should prefer the map its other
  points are on.
- **A start on a disabled map** is held back; 79085 and 81640 want hand entries on Hallowfall's map.
- **README** says the addon "places nearly 15,000 quest-giver pins"; check it at each release.

## The agreed order of work

From [game-parity.md](game-parity.md), decision 3, with what is done:

1. Profession skill fallback: **done** (#216).
2. Retail map pass: **done** (#219 carries its record).
3. **Next:** the recorder on retail, with one probe for both games (recommendations 1 and 2).
4. The consistency checks of `Audit-QuestTables.ps1` and `Remove-DuplicatePinQuests.ps1` on Forever's
   data (recommendations 4 and 5).
5. Retail's profession skill data, after one in-game check of what `GetProfessionInfo` reports for an
   expansion's skill line (recommendation 3).
6. The dungeon journal on Forever, the quest cache reader on retail (done 9 October 2026,
   [retail-quest-cache.md](retail-quest-cache.md)), the importer's `QuestLine` row counts
   (recommendations 9, 6, 7).
7. A review of Forever's hidden and test quests, after its launch on 4 November (recommendation 10).

Also: the 12.1.5 sweep when the patch is live (13 or 14 October; the TOC lists both interface
numbers), a Warband-filter check on the Forever beta, and the dated change of 1 April 2027
(releasing.md).
