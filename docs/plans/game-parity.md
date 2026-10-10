# Retail and WoW: Forever: what differs, and why

## Goal

The addon runs on two games from one set of code, and the user's rule (7 October 2026) is that a
feature or a check built for one of them goes to every game the addon supports, unless a game
can't support it; and that where the games differ because one lacks an API or a table, the sweep
watches for the gap closing, so the change gets shared when it can be. In the user's words: "If we
are doing checks on an API for one version of the game, I would hope we would also be adding those
features\checks into all versions we support, and I want that to happen unless some versions of
the game simply don't support them."

This audit lists every place the code, the data and the tools treat retail and WoW: Forever
differently, says why in each case, and what sharing would take. Its trigger was the profession
skill check, Forever's alone because of a gate on `C_SkillInfo.GetSkillLineInfoByID`, a function
retail's documentation lacks; it turned out the gate was in the wrong place and the real
difference was data (below). Each row's reason is one of four: **nature** (the game hasn't got
the content), **API** (the game's client lacks a function; the sweep watches these), **data**
(no source for that game yet; the source to re-check is named), or **process** (the two games
reach the same end by different tools).

Numbers are from 8 October 2026 (master 8d96e42 with the pin changes of that day): retail 35,023
quests and 15,202 pins; Forever 5,081 quests and 1,706 pins.

## The games by their nature

- **Retail has, Forever hasn't:** covenants, renown and major factions, warbands and account-wide
  completions, world quests and task quests, the Dungeon Journal and achievements, Chromie Time,
  storylines in the client's tables (Forever's `QuestLine` has 3 rows), expansions to group the menu
  by, Blizzard's web API, TrinityCore for the old content, a quest-giver table in the client
  (`CollectableSourceQuestSparse`, retail alone).
- **Forever has, retail hasn't:** Classic's professions as one skill line each, with a rank the
  quests ask for; its own quest log headings (Camping, The High Order, Nightmare Incursions); the
  Skyborne; the Scourge Invasion and the Ahn'Qiraj War Effort as events; CMaNGOS as a source; a
  quest cache the probe fills on purpose (retail's cache holds the same records; see tools, "cache
  reader").
- **Both have:** the same API for everything the addon calls, bar one function (below); the same
  client tables for maps, areas, headings, holidays and factions; the same addon code, filters,
  tooltips, pins, names in the player's language and waypoints.

## The code (shared Lua)

| Place | Game | Why | Could the other have it? | Recommendation |
|---|---|---|---|---|
| Profession skill requirement: `qcSkillRank` in `qcCore.lua` | both (was Forever's alone) | **API, now handled; the real gap is data.** `qcSkillRank` used to return "can't say" on a client without `C_SkillInfo.GetSkillLineInfoByID`, so the required level was never checked on retail. Since 7 October 2026 it prefers `C_SkillInfo` and otherwise reads the professions in `qcProfessionBits` through `GetProfessions` and `GetProfessionInfo`, which the addon already calls for the profession filter. `qcQuestSkillRequirements` still has 141 Forever quests from CMaNGOS and none for retail | Yes, by data. Retail's sources: the client's `QuestV2CliTask` skill filters (410 task quests, client-tables review) and TrinityCore's 78 old quests. Retail splits each profession by expansion, so the requirement's skill line must be the expansion's, and the profession list reports the base line (offline: Blizzard's profession book hands that one to its unlearn dialog, and 464 of the 524 task quests with a skill filter name an expansion line; the retail API that may read one, `C_TradeSkillUI.GetProfessionInfoBySkillLineID`, is for the two-line check in open-items.md); until then a line outside `qcProfessionBits`, an expansion's included, answers "can't say" | Fallback done. Before the data, check in game what `GetProfessionInfo` reports and whether `C_TradeSkillUI.GetProfessionInfoBySkillLineID` reads an expansion's line (recommendation 3) |
| Campaign line in the quest tooltip: `qcTooltips.lua` asks `C_CampaignInfo` and prints the game's `QUEST_CLASSIFICATION_CAMPAIGN` | retail | nature: Forever has no campaign tables, so `GetCampaignID` should answer 0 there (to confirm once on the beta); the game's word and the API are both in its client | No | Keep |
| Renown requirements: `qcRenownLevelRequirements` (96 quests) and the `C_MajorFactions` guard in `qcTooltips.lua` | retail | nature: Forever has no major factions (the functions exist and answer nothing) | No | Keep |
| Covenants: the covenant filter and `qcQuestCovenant` (777 quests) | retail | nature | No | Keep |
| Warband filter: `IsQuestFlaggedCompletedOnAccount` | both | the function is documented on both; Forever has no warbands, so it presumably answers false | Check once on the beta that a quest done on one character isn't flagged on another | Keep; a line in the next beta check |
| Converting the old completions format (`qcCompletedQuests`, retail's TOC only) | retail | nature: Forever never had the old format | No | Keep until April 2027, as planned |
| Holidays: `qcHolidays` carries both games' IDs; Forever's Scourge Invasion and War Effort have none | both | data: the two events aren't on Forever's calendar (nor its events schedule, 7 October) | When Blizzard adds them, step 2b's holiday check reports the IDs | Keep |
| Quests no longer available: the flag file and the filter | both | process: retail flags 218 quests from a review; Forever's importer leaves refused quests out instead, and flags none | A Forever review of hidden and test quests after launch, by the same method | Later, after launch |
| Minimap button: `qcMinimap.lua` on LibDBIcon-1.0 | both | shared. Forever's minimap is retail's frame (`MinimapCluster.MinimapContainer.Minimap`, 198 wide, round mask; its `Camelot` skin only changes the art), so one button serves both; both TOCs list the libraries and the file, and both save `qcMinimapIcon` | Done for both | Check the button's distance from the ring on the beta |
| Addon compartment entry: `qcMinimap.lua` calls `AddButtonToCompartment` whether or not the button shows | both | API: `AddonCompartmentFrame` is in retail's client and in Forever's (`Blizzard_Minimap`'s TOC counts `camelot` as `mainline`; the user saw the compartment on the beta, 8 October 2026); the library does nothing on a client without the frame, so an edition that lacks it needs no gate | Done for both | Keep; confirm the entry's click and tooltip on the beta |
| Zone icons on continent maps (planned): `qcContinentPins.lua`, [continent-pins.md](continent-pins.md) | both | shared: the same C_Map calls are documented on both clients and Blizzard's map code is the same; Forever has no level range (`GetMapLevels` answers 0) and Zephras Isle hangs off the world map only | Done for both when built | Build for both in one pull request; watch `Enum.UIMapType` in step 2b |
| Everything else: the 15 filters, tooltips, pins, quest and NPC names from the game, categories' client names, waypoints, the settings grid | both | shared | – | – |

So the code's one gate is fixed, and no other divergence is anything but the games' nature.

## The data

| Field or table | Retail | Forever | Why | Share? |
|---|---|---|---|---|
| Storylines (`storyline`, `qcQuestLines`) | 16,950 quests, 1,474 storylines | 11 quests, 1 storyline | **data:** Forever's client `QuestLine` has 3 rows, and no other source has storylines | Watch the table: have the importer's summary print `QuestLine` and `QuestLineXQuest` row counts, as it prints start points |
| Covenant | 777 | 0 | nature | No |
| Profession | 1,742 | 142 | both; retail's task quests from `QuestV2CliTask` | – |
| Holiday | 1,095 (9 October 2026; it grows as quests are tagged) | 322 | both; retail's is hand data in `data\quests.jsonl` (no tool writes it; the record is [quest-holiday-decisions.csv](quest-holiday-decisions.csv)), Forever's comes from CMaNGOS's events | – |
| Prerequisites | 8,306 | 2,307 (2,297 before the quest line rule) | both; retail's from Blizzard's API, the client's task-quest tables and TrinityCore, Forever's from CMaNGOS, the cache's follow-ups and, for 10 quests, the quest line order | No: retail keeps the API's (recommendation 13) |
| Breadcrumbs, "only one of these" | 279 and 249 lines | 93 and 257 | both | – |
| Reputation rewards | 11,035 | 1,837 quests | both; API against the quest cache | – |
| Renown requirements | 96 | none | nature | No |
| Minimum level: `qcQuestMinLevel` | none (empty table) | 4,180 | **data:** retail's `level` is already read as the minimum: it is meant to be the API's, and equals the API's today for 28,455 of the 30,066 quests whose API record gives one (94.6%; 1,611 differ). Forever's is the quest's own level, with the minimum from its quest cache or CMaNGOS. The readers take `qcQuestMinLevel[id] or level`, whichever game | Shared code, no gate on the game. Refreshing retail's levels from the API is a separate decision |
| Skill requirements | none | 141 | **data** (the code row above) | Yes: `QuestV2CliTask` and TrinityCore |
| Unavailable flags | 218 | 0 | process (above) | Later |
| Pins with an NPC ID | 10,564 of 15,202 | 1,503 of 1,706 | both; retail's IDs from TrinityCore and the client's giver table (#208), Forever's from CMaNGOS | – |
| Pins with neither ID nor name | 4,301 | 4 | retail's are popups, items, ship decks and the quests TrinityCore's start points place with no starter standing there; Forever has 23 start points in its client | **data** on Forever's side: the importer counts the start points every run | – |
| Pickup sources for pins | the client's `QuestPOIBlob` start points (point 32), TrinityCore's `quest_poi` start points for the quests the client lists none for, the client's giver table, TrinityCore's starters and spawns, and the addon's recorder once files exist (step 6d) | CMaNGOS's creature and object givers with their spawns, the recorder's spots, the hand list, the client's 23 start points | **data:** CMaNGOS's `quest_poi` has no point 32 (its -1 is the hand-in), Forever's client lists 23 start points, and its 197 item-started quests stay pinless where retail pins them at their start point; **nature:** Forever has no world quests to leave out and no client giver table; **process:** retail pins every place of a quest, Forever merges quests starting at one spot into one nameless pin (11 quests on 4 pins) | Watch Forever's side: the importer's start-point count, the map pass's offers (0 on build 70245), and whether CMaNGOS or its client gains a point-32 table |
| Quest types | retail: probe, API and `QuestV2` | CMaNGOS and the cache's flags, `QuestV2` | process; neither game's probe can say "repeatable" | – |
| Category names in the player's language | all from the client since #207 | all from the client | both | – |

## The tools and the sweep's steps

| Step or tool | Retail | Forever | Why | Share? |
|---|---|---|---|---|
| 1 faction, race and class against Blizzard's API | `Audit-QuestAccuracy.ps1` | the importer takes the cache's race masks over CMaNGOS's | the API has no Forever | equivalent |
| 1b second source for race and class | `Get-WagoQuestRequirements.ps1` | – | `QuestV2CliTask` is retail's alone | nature |
| 1c quest names | from the API | from the cache | – | equivalent |
| 1d professions of task quests | `Sync-QuestProfessions.ps1` | – | `QuestV2CliTask` is retail's alone; Forever's come from CMaNGOS | nature |
| 2 reputation | API compare and backfill, then a pass that checks the quest cache's rewards against ours and the API's | the cache, in the importer | – | equivalent |
| 2b the tables kept by hand (`Audit-QuestTables.ps1`) | yes | the consistency part, `-Game forever` (9 October 2026) | Forever's tables are generated, so the "hand error" checks don't apply, but its consistency checks do: a one-time quest requiring a recurring one, a recurring quest in a breadcrumb or "only one of these" pair, a pair naming a quest not in the data, a quest listed twice | done: step 10 runs it; the API, TrinityCore and client-table parts stay retail's (`-OwnDataOnly` skips them) |
| 2c prerequisites | API, the client's task quests (`QuestV2CliTask`) and TrinityCore | CMaNGOS, in the importer | – | equivalent |
| 2d holiday tags (`Audit-QuestHolidays.ps1`) | yes | **no** | Forever's tags aren't hand data: the importer derives them from CMaNGOS's events on every step-10 run, so a check against the same tables would only repeat it. The one thing it could find, a CMaNGOS event with quests that the importer maps to no holiday, is two events and four quests today (New Year's Eve, 8860 and 8861; Winter Veil: Gifts, 8827 and 8828), all tagged Winter Veil in Forever's data (9 October 2026) | equivalent |
| 3 quest types | `Retype-*.ps1` with the probe | the importer | – | equivalent |
| 4 storylines | `Build-QuestLines.ps1` | `Build-ForeverMenu.ps1` reads the same table | data (3 rows) | watched |
| 5 zone table and client names | three tools | `Build-ForeverMenu.ps1` | – | equivalent |
| 6 pins | the pipeline from `QuestPOIBlob` and TrinityCore's `quest_poi` | the importer from CMaNGOS, the recorder and the client's start points | the same rule, a pin at every place a source puts the pickup, from each game's sources (the data row above) | equivalent |
| 6 duplicate quests on nearby pins (`Remove-DuplicatePinQuests.ps1`) | yes | `-Game forever` (9 October 2026) | it had never been pointed at Forever's folders; retail's start points (`quest_locations.csv`) have no Forever counterpart, so only its half-point rule applies | done: step 10 runs it after the import |
| 6d the addon's recorder merged into the pins | `Import-RecordedGivers.ps1`: blank NPC IDs and names filled, pins for quests no source places; the ledger and the lists, retail's and Forever's | the ledger and the lists only; Forever's pins are rebuilt by step 10, which does not read the ledger yet | Forever's importer does not read the ledger | **Yes:** the importer reads the ledger and merges recorded spots at 1.5 points (plan item 5) |
| 6c NPC IDs for named pins | TrinityCore (`Fill-PinNpcIds.ps1`), and the client's giver table with TrinityCore's starters, which also move a quest to its giver's pin (`Apply-ClientQuestGivers.ps1`) | CMaNGOS gives the IDs, from each quest's starter, so there is no neighbour's identity to correct | `CollectableSourceQuestSparse` is retail's alone | equivalent; nature |
| 7 quests no longer obtainable | `Find-UnavailableQuestCandidates.ps1` | the importer's refused-quest rule | process | later, after launch |
| 8 dungeons against the Dungeon Journal | `Audit-DungeonCategories.ps1` | – | **data:** Forever's client has no `JournalInstance` (nor any `Journal*` table: 612 tables on builds 70205 and 70245, checked 9 October 2026); its menu takes instance types from the map table, and `DungeonEncounter` and `LFGDungeons` are all it has near the journal | watched: `Compare-ClientTables.ps1` flags a `Journal` table as quest-related when one appears, and the audit is then pointed at it |
| 9 reachability | yes | yes | – | shared |
| The client-tables check, the API check, the holiday check, the localization test | both | both | – | shared |
| The quest probe | `/qc typecheck` (#42's branch): recurrence and tags | `/qcprobe quests`: the same and more (level, elite, group size, title) | process: two probes for one job; the Forever probe's TOC loads on retail too | **Yes:** one probe for both games. Give `Build-ProbeLists.ps1` a retail mode (the quests from `data\quests.jsonl` with `QuestV2`), retire #42's probe, and add the quest-facts pass (API review, recommendation 2) once |
| The NPC-name check | once, in #112, for the 6,468 IDs then; the probe's list now holds the 8,418 NPC IDs on retail's pins (built 9 October 2026) | every build, `/qcprobe npcs` | process | **Yes:** run each sweep (about 5 minutes), and compared with the pins by `Compare-PinNpcNames.ps1` (both games, report-only) |
| The recorder | shared since 8 October 2026 (`qcRecorder.lua`, on by default; not yet tried in game); merged into retail's pins by `Import-RecordedGivers.ps1` (step 6d, 9 October 2026) | the probe's, until the addon's has run one sweep; then the addon's; step 6d keeps Forever's ledger and the importer will read it | Forever's importer does not read the ledger yet | **Yes:** API review, recommendation 1; [quest-giver-recorder.md](quest-giver-recorder.md) |
| The map pass | done (7 October) | done (7 October) | – | run on both each sweep (maintenance.md, step 4b) |
| The quest cache reader (`Read-QuestCache.ps1`) | step 2e, with `Compare-QuestCache.ps1` | every sweep | process: retail's `questcache.wdb` holds the same server records for the 31,425 quests the type probe loaded (localized-quest-names.md), in the same layout the reader checks | **Done 9 October 2026** ([retail-quest-cache.md](retail-quest-cache.md)): it gives retail the quest sort and, as a content tuning, the level the server asks for (`minLevel`, which Forever's `qcQuestMinLevel` is made from; retail's `level` was taken from the API's minimum and differs from it today for 1,611 quests: see maintenance.md, "The quest and pin data files"); the start item turned out to be the item the quest hands over when accepted, not the one that begins it, so it is no prize. The reader read retail's layout (TrinityCore's, with two numbers fewer), and `Compare-QuestCache.ps1` watches it against Blizzard's own data |
| Hand lists | `pin-npc-id-decisions.csv` | `forever-quest-givers.csv`, `forever-quest-zones.csv` | – | equivalent |
| Release | one ZIP, both TOCs | – | shared |

## The sweep watches the gaps

- **API gaps.** `tools\Compare-ApiDocs.ps1` (step 2b) lists the functions the addon calls, and the
  events it listens for, that one game documents and the other doesn't, today only
  `C_SkillInfo.GetSkillLineInfoByID` on Forever, and compares both games' secrecy flags the same way,
  and exits with 1 when such a function turns up in the documentation of a game that lacked it in
  the earlier list: the game has gained it, so check that the code reads it as its fallback did,
  and share any feature gated on it. Checked
  with an older Forever list doctored to lack `C_SkillInfo`. `qcSkillRank` prefers `C_SkillInfo`
  where the client has it, so when retail gains it the profession-list fallback becomes the second
  route and the expansion lines can be read directly.
- **Data gaps**, each with the place that watches it: Forever's storylines (`QuestLine` rows; the
  importer's "Storylines:" line) and start points (`QuestPOIBlob`; the importer's
  summary); a quest-giver field in Forever's quest records (the importer's summary); a Forever
  namespace in Blizzard's web API (forever.md, phase 5); `QuestV2CliTask` appearing on Forever
  (step 2b's new-table flag); the Scourge Invasion and War Effort on Forever's calendar (step 2b's
  holiday check) or its events schedule (the map pass).
- **Pickup data.** Retail: `tools\quest_locations_tdb_review.csv` after step 6 lists what the
  TrinityCore rules held back. Forever: the importer's start-point count and its pinless quests by
  cause (step 10), the map pass's offers, and whether CMaNGOS or Forever's client gains a start table.

## Recommendations, most valuable first

| # | What | Effort | Notes |
|---|---|---|---|
| 1 | The recorder on retail (API review, recommendation 1) | small in the addon (built 8 October 2026), medium for the merge tool (built 9 October 2026) | the one check Forever has that retail lacks outright; the in-game session and the first real ingest are left |
| 2 | One probe for both games: a retail mode for `Build-ProbeLists.ps1`, the quest-facts pass built once, the NPC pass run on retail each sweep, #42's probe retired | medium | ends the two-probes split; the Forever probe already loads on retail |
| 3 | Profession skill requirements on retail: the `GetProfessionInfo` fallback (done 7 October 2026), then the in-game check of the expansion lines, then the data from `QuestV2CliTask` and TrinityCore | small code (done), medium data | the case that started this; the fallback makes the code the same on both, and changes nothing in game until retail has requirement data |
| 4 | `Audit-QuestTables.ps1`'s consistency checks on Forever's generated tables, in step 10 | medium | done 9 October 2026 (`-Game forever`, `-OwnDataOnly`): 6 findings, five kept and one fixed |
| 5 | `Remove-DuplicatePinQuests.ps1` on Forever's pins, in step 10 | small | done 9 October 2026 (`-Game forever`): it did find something, 11 pins |
| 6 | Retail's quest cache through `Read-QuestCache.ps1` | medium | done 9 October 2026: the layout is TrinityCore's, 120 fixed numbers; the start items are not what the recommendation took them for ([retail-quest-cache.md](retail-quest-cache.md)) |
| 7 | The importer prints `QuestLine` and `QuestLineXQuest` row counts | small | done 9 October 2026: the "Storylines:" line (3 and 22 rows on build 70205) |
| 8 | The retail map pass | a run | the pin comparison; done 7 October 2026 (game-api-review.md, "Map-offers probe: retail run") |
| 9 | `JournalInstance` on Forever, and the dungeon audit if it's there | small check | done 9 October 2026: it isn't there, so there is no audit to point (row 8) |
| 10 | A Forever review of hidden and test quests | later | after launch |
| 11 | One rule for nameless pins in both games: a pin per quest and place (retail) or per spot (Forever) | small | decide, then align the tool that differs |
| 12 | Name retail's pins after the object or item that starts the quest, as Forever's are | small | `gameobject_queststarter` and `gameobject_template` give 62 object-started quests; 120 start from an item alone |
| 13 | Prerequisites from the quest line order, on retail as on Forever | decided: Forever only | built for Forever on 10 October 2026, where it is the only source (`QuestLines.ps1`, `Import-ForeverData.ps1`). Retail has Blizzard's own prerequisites, and measured on its tables (12.1.0.69933 quest lines, 12.1.5 map points) the rule would add one to 8,654 of its 16,093 chained steps, 8,697 counting the steps whose places differ: where retail does have one, the previous step is it 93% of the time, so about 1 in 14 of those additions would be wrong, and a wrong prerequisite hides a quest the player can take. **Decided by the user, 10 October 2026: retail keeps using Blizzard's API for its prerequisites, for now.** The rule is not applied there. To reopen it, the measure above is the evidence to start from, and the cheaper form is to use it only for steps the API lists no prerequisite for, each listed for review |

## Decisions (agreed 7 October 2026)

1. **The rule**, in the user's words above: a feature or check built for one game goes to all the
   games the addon supports, unless a game can't support it.
2. **The sweep watches the gaps:** the API check names the one-game functions and fails when a gap
   closes; the data gaps are listed here with what watches each.

3. **The order of work**, one pull request each: the skill fallback (3, code half); the retail map
   pass (8), a run in game that should come before 12.1.5 so that sweep has a baseline; the
   recorder on retail with one probe for both games (1 and 2); the table checks on Forever (4 and
   5); the retail skill data (3, data half); the journal check on Forever (9); the retail quest
   cache reader (6); the importer's row counts (7); the hidden and test quest review after launch
   (10). Behind it: 12.1.5 goes live on 13 or 14 October and Forever launches on 4 November.
4. **Prerequisites from the quest line order are Forever's only** (the user, 10 October 2026). Forever has no
   other source for its ten "Toxic Soil" steps; retail keeps Blizzard's API, for now (recommendation 13).

## Status

- 2026-10-07: audit written; `Compare-ApiDocs.ps1` extended with the one-game list and the
  gap-closing failure. Nothing else changed.
- 2026-10-07: the order agreed (decision 3). Recommendation 3's code half built: `qcSkillRank`
  falls back to the character's profession list on a client without `C_SkillInfo`, for the
  professions in `qcProfessionBits`; checked with stand-ins for both clients. Retail has no
  requirement data yet, so nothing changes in game until the data half.
- 2026-10-07: retail's task quests got their professions (410) and prerequisites (687 new, 90
  changed) from `QuestV2CliTask`, as the client-tables review's recommendation 5. The skill
  levels in the same table are still recommendation 3 above.
- 2026-10-07: recommendation 8 done: the user ran the map pass on retail (1,961 maps, five
  minutes). It compared the game's offers with our pins and found the pipeline reads a quest's
  turn-in point as its giver (game-api-review.md, decision 8); it is now in the retail sweep
  with Forever's.
- 2026-10-08: pins at the start. Retail's pipeline places a quest at its client start point
  (`ObjectiveIndex 32`), then its own point (-1); Forever's importer reads the same two, in the same
  order, from its own client tables (quest-location-data-pipeline.md, "October 2026, pins at the
  start"). Forever's data takes it at the next import.
- 2026-10-08: pins from every pickup source. Retail's pipeline now places the quests the client lists
  no point for from TrinityCore's `quest_poi` (1,453 quests, 1,778 places; quest-location-data-pipeline.md,
  "pins from TrinityCore"), and the rule that a normal quest gets a pin wherever a source puts its
  pickup, with or without an NPC, is written in the runbook for both games (steps 6 and 10).
  Forever already applies it to every source it has; what it lacks is data (data row "Pickup
  sources for pins").
- 2026-10-08: the minimap button (`qcMinimap.lua`, LibDBIcon-1.0) is in both games' TOCs from the
  start, so the code row above needed no gate. Checked with stand-ins for the client's frames; the
  button's look and distance from the ring on each game are for the in-game check.
- 2026-10-08: the addon compartment entry turned on for both games, at the user's request.
- 2026-10-08: recommendation 1: the recorder is shared code (`qcRecorder.lua` in both TOCs, one
  account-wide saved variable, so each game keeps its own file), built and tested with stand-ins;
  the game's answers to its open questions come from one in-game session on each
  ([quest-giver-recorder.md](quest-giver-recorder.md)). The merge tool is next.
- 2026-10-09: recommendation 1, the merge tool: `Import-RecordedGivers.ps1` (step 6d) fills retail pins'
  missing NPC IDs and adds pins for quests no source places, from the ledger
  `recorded-quest-givers.csv`, for both games' files; Forever only gets its ledger, as its pins are
  rebuilt by step 10. The pickup rule of the data row "Pickup sources for pins" now has the recorder as a
  source on both games once files exist ([quest-giver-recorder.md](quest-giver-recorder.md), "The merge tool").
- 2026-10-09: the API check compares secrecy flags and the events the addon listens for, on both games
  (the same code, `Compare-ApiDocs.ps1`); the recorder's events are documented in both, its quest-window
  globals in neither.
- 2026-10-09: recommendations 4 and 5, the table checks on Forever (step 10, items 8 and 9 of the runbook):
  `Audit-QuestTables.ps1 -Game forever` (and `-OwnDataOnly` on either game) and
  `Remove-DuplicatePinQuests.ps1 -Game forever`, with `Test-ForeverChecks.ps1`. The audit found 6 things in
  Forever's data: five are kept in `forever-quest-table-decisions.csv` (three prerequisites that name the
  other faction's quest, two that name a repeatable one), and quest 92727's own record in the game names
  itself as its next quest, which the importer took as its previous quest, so the quest could never show
  (fixed in the importer and the data). The removal took quest 2933 off 10 "Venom Bottle" pins and quest
  926 off one "Flawed Power Stones" pin (11 pins): CMaNGOS has several object entries of one name. It also
  found a bug that had been in the tool since it was written, in retail's copy too: a spot whose only
  pin was the first in the file read as empty, so that pin was never merged (retail's output is unchanged).
- 2026-10-09: recommendation 6: `Read-ForeverQuestCache.ps1` is now `Read-QuestCache.ps1` and reads retail's
  cache (32,713 quests) as well as Forever's, from one walker and a table of positions for each game.
  `Compare-QuestCache.ps1` (step 2e) checks it against the API and the client's task table: nothing
  differs. Eight comparisons of the cache with our data are in [retail-quest-cache.md](retail-quest-cache.md);
  the start item is the item handed over on accept, which retires "Starts from" as recommendation 13
  had it. Forever's output is the old reader's plus `flagsEx`, `questType` and `scheduler`; its
  `recurs` takes a daily from flags Ex too (none of Forever's differ).
- 2026-10-09: recommendation 9: Forever's client carries no `JournalInstance` or any other `Journal*` table (the
  lists of client tables for builds 70205 and 70245), so the dungeon audit has nothing to read there. The
  watch is step 2b's table list.
- 2026-10-10: the continent icons are planned for both games in one pull request
  ([continent-pins.md](continent-pins.md)); nothing differs by nature but Zephras Isle and the level range.
