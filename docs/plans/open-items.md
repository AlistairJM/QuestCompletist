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
- **The menu review changes** (branch `chore/menu-review`, not committed): open the category menu
  and look at Battle For Azeroth, Other Categories (the seven campaigns), World Events,
  Timerunning, Kalimdor, Northern Kalimdor (Elemental Bonds, Firelands Invasion, Molten Front after
  Mount Hyjal), Dungeons and Raids, Classic (Scarlet Halls), and Class Quests (Monk); then walk into
  Camp Narache, Shadowglen, Valley of Trials and New Tinkertown and see the list follow the parent
  zone ([menu-review.md](menu-review.md)).

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
| 8 | The 22 placeholder-named quests that still show in default lists (menu review R08) fail the step-7 evidence rules: flag them anyway? | yes, the 22 that show; the same call as 5 October on the 19 internal entries | [menu-review.md](menu-review.md), question 8 |
| 9 | One submenu shape for every expansion (R28) | Main Zones and Other Categories for Draenor and The Broken Isles; Outland, Northrend and The Maelstrom stay flat | [menu-review.md](menu-review.md), question 9 |
| 10 | Midnight: move Founder's Point and Razorwind Shores into Other Categories (R27) | yes | [menu-review.md](menu-review.md), question 10 |
| 11 | Split Lordaeron into Lordaeron, Quel'Thalas, Gilneas and Tol Barad (R26) | yes, named from the client's maps | [menu-review.md](menu-review.md), question 11 |
| 12 | Merge Darkmoon Island into Darkmoon Faire and four one-quest entries into their zones (R15, R31) | yes, in one pass, because a category merge changes how the sweep tools file new quests | [menu-review.md](menu-review.md), question 12 |
| 13 | Names that repeat, groups and categories that share a name, Forever's "Invasion" (R17 to R21, R25, F03) | leave; if it matters, show the menu path in the list header (no new text) | [menu-review.md](menu-review.md), question 13 |
| 14 | Entries empty by default and tiny entries (R29, R30, R39, F06, F07, F09) | keep them, and have an empty list say how many quests the filters hide | [menu-review.md](menu-review.md), question 14 |
| 15 | Rated PvP, 86 of 87 quests unavailable (R06) | keep | [menu-review.md](menu-review.md), question 15 |
| 16 | Class Quests has no Evoker (R05) | leave | [menu-review.md](menu-review.md), question 16 |
| 17 | Ordering rule for Retail's lists (R33) | keep the hand order | [menu-review.md](menu-review.md), question 17 |
| 18 | Forever: split Seasonal, and Deeprun Tram and Special loose (F04, F05) | leave until after the 4 November launch | [menu-review.md](menu-review.md), question 18 |
| 19 | Remove the 83 unused category definitions (R32) | yes, in a pass of its own, after 12 | [menu-review.md](menu-review.md), question 19 |

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
- **README** says the addon "places nearly 15,000 quest-giver pins"; check it at each release.
- **`Build-CategoryClientNames.ps1`** still lists two expected differences, for categories 1221 and
  1430, that the spelling fixes made stale.

## The agreed order of work

From [game-parity.md](game-parity.md), decision 3, with what is done:

1. Profession skill fallback: **done** (#216).
2. Retail map pass: **done** (#219 carries its record).
3. **Next:** the recorder on retail, with one probe for both games (recommendations 1 and 2).
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
