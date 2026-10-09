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

- **The pins of #223 and #224** (193 quests with only a start point, and 1,453 more from
  TrinityCore's start points) shipped in 112.5 without an in-game check: the user, shown a list of
  spots to check, said it was too much to check by hand and to go ahead (8 October 2026). When
  convenient, look at a few, and at these: quest 1036 "Avast Ye, Scallywag" (its pin is where the
  client puts its end, not at "Pretty Boy" Duncan), the class quests at Orgrimmar's and Stormwind's
  hubs, the Silithus sigil quests (45749 to 45762, which may be retired), and the pins on the Caverns
  of Time.
- **The pins moved to quest starts (#219)** are checked by the user for a sample, not for every
  zone.
- **The recorder**, on a branch, on both games: a full WoW restart, then the list in
  [quest-giver-recorder.md](quest-giver-recorder.md) ("To try in game"): the order of the events,
  whether the game hides who is speaking, whether the popup hook fires, what the options panel
  looks like in the longest language. It ships only after that.

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
| 6 | The remaining decisions 1 to 7 of the API review (recorder on retail, taken as agreed on 8 October 2026 and built; probe additions, scaling-aware levels, text from the game, waypoints, tracking toggles) | see that document | game-api-review.md |
| 7 | Pin-per-quest (retail) or pin-per-spot (Forever) for nameless pins | decide, then align the tool that differs | game-parity.md, recommendation 11 |

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
3. **In progress:** the recorder on retail, with one probe for both games (recommendations 1 and 2).
   The addon half (#228) waits for its in-game session, and the merge tool (step 6d, `tools/recorded-givers`)
   is built and waits for a real recording ([quest-giver-recorder.md](quest-giver-recorder.md)); the
   secrecy watch of step 2b is built; the probe comes next.
4. The consistency checks of `Audit-QuestTables.ps1` and `Remove-DuplicatePinQuests.ps1` on Forever's
   data (recommendations 4 and 5).
5. Retail's profession skill data, after one in-game check of what `GetProfessionInfo` reports for an
   expansion's skill line (recommendation 3).
6. The dungeon journal on Forever, the quest cache reader on retail, the importer's `QuestLine` row
   counts (recommendations 9, 6, 7).
7. A review of Forever's hidden and test quests, after its launch on 4 November (recommendation 10).

Also: the 12.1.5 sweep when the patch is live (13 or 14 October; the TOC lists both interface
numbers), a Warband-filter check on the Forever beta, and the dated change of 1 April 2027
(releasing.md).
