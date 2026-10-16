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

On 12 October 2026 a fuller review, [data-sources-review.md](data-sources-review.md), went field by field through
every source both games have. Several rows below that said "equivalent" turned out to hide different rules; those
rows now say so and point to the review's defect (D) or recommendation number.

Numbers are from 8 October 2026 (master 8d96e42 with the pin changes of that day): retail 35,023
quests (35,529 since 11 October, when step 6b added the task quests) and 15,202 pins; Forever 5,081
quests and 1,706 pins.

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
| Profession skill requirement: `qcSkillRank` in `qcCore.lua` | both (was Forever's alone) | **API, now handled; the real gap is data.** `qcSkillRank` used to return "can't say" on a client without `C_SkillInfo.GetSkillLineInfoByID`, so the required level was never checked on retail. Since 7 October 2026 it prefers `C_SkillInfo` and otherwise reads the professions in `qcProfessionBits` through `GetProfessions` and `GetProfessionInfo`, which the addon already calls for the profession filter. `qcQuestSkillRequirements` still has 141 Forever quests from CMaNGOS and none for retail | Yes, by data. Retail's sources: the client's `QuestV2CliTask` skill filters (524 task quests, 334 of them above level 1) and TrinityCore's 60 profession levels above 1 (the 78 counted earlier included 18 Riding). TrinityCore's values above 300 are on the old cumulative scale and must be converted to the expansion's line before use (data-sources-review.md, recommendation 28). Retail splits each profession by expansion, so the requirement's skill line must be the expansion's, and the profession list reports the base line (offline: Blizzard's profession book hands that one to its unlearn dialog, and 464 of the 524 task quests with a skill filter name an expansion line; the retail API that may read one, `C_TradeSkillUI.GetProfessionInfoBySkillLineID`, is for the two-line check in open-items.md); until then a line outside `qcProfessionBits`, an expansion's included, answers "can't say" | Fallback done. Before the data, check in game what `GetProfessionInfo` reports and whether `C_TradeSkillUI.GetProfessionInfoBySkillLineID` reads an expansion's line (recommendation 3) |
| Campaign line in the quest tooltip: `qcTooltips.lua` asks `C_CampaignInfo` and prints the game's `QUEST_CLASSIFICATION_CAMPAIGN` | retail | nature: Forever has no campaign tables, so `GetCampaignID` should answer 0 there (to confirm once on the beta); the game's word and the API are both in its client | No | Keep |
| Storyline name and "Type:" row in the quest tooltip: `qcTooltips.lua` asks `C_QuestLine.GetQuestLineInfo`, `C_QuestInfoSystem.GetQuestClassification`, `QuestUtil.GetQuestClassificationInfo`, `C_QuestLog.GetQuestTagInfo` and `QuestUtils_GetQuestTagAtlas` | both | shared: the first, second and fourth are documented on both clients and the other two are FrameXML on both branches (`[Family]\QuestUtils.lua`, the same text). Each is asked only if the function exists, in a `pcall`, with our stored name as the fallback, so nothing is gated on the game. Forever's answers are thin today: 11 quests in one quest line (the game's ID is ours for all 11), a classification that is only Normal or Recurring (no classification rows), and 249 of 2,877 loaded quests with a tag (Dungeon 134, Elite 99, PvP 14, Raid 2) | Done for both | Keep; when a Forever build fills `QuestLine` or classifies more quests, the rows follow with no change |
| Renown requirements: `qcRenownLevelRequirements` (96 quests) and the `C_MajorFactions` guard in `qcTooltips.lua` | retail | nature: Forever has no major factions (the functions exist and answer nothing) | No | Keep |
| Covenants: the covenant filter and `qcQuestCovenant` (777 quests) | retail | nature | No | Keep |
| Warband filter: `IsQuestFlaggedCompletedOnAccount` | both | the function is documented on both; Forever has no warbands, so it presumably answers false | Check once on the beta that a quest done on one character isn't flagged on another | Keep; a line in the next beta check |
| Converting the old completions format (`qcCompletedQuests`, retail's TOC only) | retail | nature: Forever never had the old format | No | Keep until April 2027, as planned |
| Dropping the ticks that removed "only one of these" links gave (`qcFormerlyExclusive`, at login, until April 2027) | both | data: the code is shared. Both games' links have been corrected (retail's on 6 October 2026, 28 pairs; Forever's in `forever-quest-link-decisions.csv`, 11 October 2026), but retail's list is empty, so 10 quests can keep ticks the server doesn't confirm, for players who handed in a removed partner on 109.97 to 111.x (data-sources-review.md, D13) | Yes: seed retail's list, and build both from the difference between the released link tables and the new ones, both link types | Keep until April 2027 ([releasing.md](../releasing.md), "Dated changes") |
| Holidays: `qcHolidays` carries both games' IDs; the Scourge Invasion and War Effort have none (Forever's entries, which retail's 11 and 43 quests of the two events have carried too since 12 October 2026, #314); the Moonkin Festival, Hearthstone's 10th Anniversary, WoW's Anniversary, the Skyriding Cups, Dastardly Duos, The Great Gnomeregan Run and Call of the Scarab (#315) are retail's only | both | data: the two events aren't on either game's calendar (nor Forever's events schedule, 7 October), and Forever's Holidays tables have no row for the seven retail events (none of the three builds has an anniversary, cup, Dastardly Duos, Gnomeregan Run or Call of the Scarab row, 11 and 12 October 2026; Forever has no Dragonriding) | When Blizzard adds them, step 2b's holiday check reports the IDs; its pattern checks for WoW's Anniversary and the cups read both games' tables, and step 2h's calendar review lists any new dated event in either game | Keep |
| Quests no longer available: the flag file and the filter | both | process: retail flags 240 quests from a review; Forever's importer leaves refused quests out instead, and flags none | A Forever review of hidden and test quests after launch, by the same method | Later, after launch |
| Minimap button: `qcMinimap.lua` on LibDBIcon-1.0 | both | shared. Forever's minimap is retail's frame (`MinimapCluster.MinimapContainer.Minimap`, 198 wide, round mask; its `Camelot` skin only changes the art), so one button serves both; both TOCs list the libraries and the file, and both save `qcMinimapIcon` | Done for both | Check the button's distance from the ring on the beta |
| Addon compartment entry: `qcMinimap.lua` calls `AddButtonToCompartment` whether or not the button shows | both | API: `AddonCompartmentFrame` is in retail's client and in Forever's (`Blizzard_Minimap`'s TOC counts `camelot` as `mainline`; the user saw the compartment on the beta, 8 October 2026); the library does nothing on a client without the frame, so an edition that lacks it needs no gate | Done for both | Keep; confirm the entry's click and tooltip on the beta |
| Zone icons on continent maps (`qcContinentPins.lua`, built, not yet tried in game): [continent-pins.md](continent-pins.md) | both | shared: the same C_Map calls are documented on both clients and Blizzard's map code is the same; Forever has no level range (`GetMapLevels` answers 0), Zephras Isle hangs off the world map only, and no continent lists another inside it (retail's Quel'Thalas and Argus get an icon on their outer map; the code asks the game, so Forever gets one the day it lists one); the hub and sub-zone tables (Oribos, Undermine, Korthia and the rest) hold retail's maps only, Forever's continent maps have none of them, and the icon's size, count font and grey art follow the screen on both, as does the green check on a finished zone while the map shows completed quests | Done for both when built | Build for both in one pull request; watch `Enum.UIMapType` in step 2b |
| Waypoints: `QC.qcSetWaypoint` in `qcMapPins.lua`, for a pin click and a list click | both | shared, gated on capability, not on the game: TomTom where it's loaded (as before), else `C_Map.SetUserWaypoint` after `CanSetUserWaypointOnMap`, with `C_SuperTrack.SetSuperTrackedUserWaypoint` and `UiMapPoint`, all documented on both clients, and the game rule `WorldMapTrackingPinDisabled` that Blizzard's own map checks. A client lacking any of them does what it did without TomTom: nothing. The same kinds of map refuse on both (orphan and dungeon-type: 259 of retail's 541 pin maps; Forever's Alterac Valley), and Forever allows it on its zones (56 of 60 maps, probe of 7 October) | Done for both | Try both in game with TomTom off (open-items.md); the API check (step 2b) watches the four functions |
| Everything else: the 15 filters, tooltips, pins, quest and NPC names from the game, categories' client names, the settings grid | both | shared | – | – |

So the code's one gate is fixed, and no other divergence is anything but the games' nature.

## The data

| Field or table | Retail | Forever | Why | Share? |
|---|---|---|---|---|
| Storylines (`storyline`, `qcQuestLines`) | 17,009 quests, 1,476 storylines (15 October 2026, 12.1.5) | 11 quests, 1 storyline | **data:** Forever's client `QuestLine` has 3 rows, and no other source has storylines | Watch the table: have the importer's summary print `QuestLine` and `QuestLineXQuest` row counts, as it prints start points |
| Class | from Blizzard's API, checked against the client's tables (step 1b) | 888 quests for some classes only (11 October 2026): from class headings, the items that start a quest (`ItemSparse`), CMaNGOS, a hand list ([forever-quest-class-decisions.csv](forever-quest-class-decisions.csv), 3 quests) and, down a chain, a quest's only prerequisite | **data:** Forever's quest records carry no class (checked against CMaNGOS's over 391 quests), and it has no API; both clients say which classes may use an item that starts a quest (retail's 25 such quests we have agree with ours) | Done for both where the client says it. But retail's step-1 reader takes an API list naming Adventurer as "all classes" (21 quests, D3), and retail reads neither TrinityCore's classes (data-sources-review.md, recommendation 7) nor the class heading Forever uses (D17) |
| Covenant | 777 | 0 | nature | No |
| Profession | 1,954 (12 October 2026) | 142 | both; retail's from the client's task table, Blizzard's profession headings (API and quest cache), the knowledge a quest rewards and a hand list ([quest-profession-decisions.csv](quest-profession-decisions.csv)); Forever's from CMaNGOS's RequiredSkill (141 quests), then the game's heading (one quest, 384 Beer Basted Boar Ribs) | Partly: retail doesn't read TrinityCore's RequiredSkillID, the twin of the CMaNGOS column Forever uses; neither game reads the items that need a skill to start a quest yet (data-sources-review.md, recommendations 16 and 23) |
| Holiday | 1,304 (12 October 2026; it grows as quests are tagged) | 351 (11 October 2026) | both; retail's is hand data in `data\quests.jsonl` (no tool writes it, except that step 6b gives a new task quest its namesakes' tag; the record is [quest-holiday-decisions.csv](quest-holiday-decisions.csv)), Forever's comes from CMaNGOS's events, the game's and CMaNGOS's headings and the spawn rule, and from a hand list of 18 quests ([forever-quest-holiday-decisions.csv](forever-quest-holiday-decisions.csv)) | Process: hand data with an audit on retail, generated on Forever. A smaller retail resolver, Blizzard's heading first, is data-sources-review.md recommendation 20 |
| Prerequisites | 9,376 (8,306 before the 12 October rules, 7,992 before the cache's follow-ups) | 2,399 (2,287 before the quest line rule, 2,297 before CMaNGOS's next quests and conditions; 11 October 2026) | both; retail's from Blizzard's API, the client's task-quest tables, the client's conditions on the current expansion's quest lines and campaigns, that campaign's chapter order, the quest cache's follow-ups where TrinityCore agrees, TrinityCore, and for 45 a hand list ([quest-link-decisions.csv](quest-link-decisions.csv)), Forever's from CMaNGOS's requirement (previous and next quests, negative groups, conditions that ask for quests handed in), the cache's follow-ups, for 10 quests the quest line order and for 18 a hand list, which also removes 15 ([forever-quest-link-decisions.csv](forever-quest-link-decisions.csv)) | Partly: both read their own quest cache's follow-ups, retail only where TrinityCore agrees (1,384 quests, 12 October 2026; retail-quest-cache.md, "Next quest"), as a cache-only follow-up is often a re-offer. Retail keeps the API's where it speaks (recommendation 13). TrinityCore's negative groups and in-log links, which retail's tools don't read, are left. The rules differ more than "partly" said: Forever's cache follow-ups have none of retail's filters, so 29 Forever quests need their own breadcrumb (data-sources-review.md, D6, recommendation 10); and retail reads TrinityCore's previous quests, next-quest dependents and conditions narrowly where Forever reads CMaNGOS's in full (recommendations 7 and 9), mostly by the user's 6 October rule (quest-table-checks.md, decisions 3 and 4), which the review's decision 1 puts back to the user. #320's follow-ups also gave 25 retail quests a board quest as prerequisite (D1) |
| Breadcrumbs, "only one of these" | 279 and 249 lines | 157 and 255 | both; Forever's from CMaNGOS (its breadcrumbs, and the quests a next quest in the chain closes), with the links a hand list adds and less those it removes | Process: retail's are legacy hand data that step 2b audits, Forever's are generated at each import. A generator would add no sourced link the audited hand table lacks, only chain-rule and TrinityCore-group pairs that would mostly hide quests, so both games get the same consistency checks instead (data-sources-review.md, recommendation 38). The chain-closing rule is Forever's alone and untried in game (recommendation 39) |
| Quests offered only while another is in the log (`qcQuestNeedsInLog`) | 0 | 35 (11 October 2026) | both read it; Forever's from CMaNGOS's negative `PrevQuestId` and `NextQuestId` | Yes, from TrinityCore: 20 negative previous quests that name a quest in our data, and 19 single-branch in-log conditions, each reviewed (data-sources-review.md, recommendation 7). Not from the client's `PlayerCondition.CurrQuestID`: on every condition our task quests use, it means "not while that quest is in the log" |
| Reputation rewards | 11,777 quests (16 October 2026: 11,039 from the API, 738 from the quest cache) | 1,855 quests (12 October 2026) | both; retail takes the API, checks the quest cache against it and takes the cache's for the quests the API has no record of, Forever takes the cache | Process, partly nature (Forever has no API): Forever's rewards are checked against nothing; a CMaNGOS check with a baseline is data-sources-review.md recommendation 15 |
| Renown requirements | 96 | none | nature | No. Retail's 96 are hand data from 109.97 with no source; the client's own task conditions give 65 more and confirm 4 (data-sources-review.md, recommendation 17) |
| Reputation standing (Honored with X) | none | none | process, unbuilt in both: Blizzard's API (469 retail quests; TrinityCore 247, 44 of them beyond the API) and CMaNGOS (212 Forever quests) have it, and no tool reads it | Yes, both (data-sources-review.md, recommendation 24) |
| Minimum level: `qcQuestMinLevel` | 1,627 (11 October 2026; was an empty table) | 4,194 (12 October 2026) | **both:** each game holds the gate in the table and keeps `level` as the quest's own. Retail's is the API's `min_character_level`, else the client's `ContentTuning` range for the quest's tuning from its quest cache and task table (`Apply-QuestMinLevels.ps1`, runbook step 2g; the user took option C of rows 14 and 8 on 11 October 2026: the stored level is unchanged). Forever's comes from its quest cache or CMaNGOS, at each import. The readers take `qcQuestMinLevel[id] or level`, whichever game | Shared code, no gate on the game. Forever's client has a `ContentTuning` table too, but its quest cache gives the minimum directly, so the formula isn't needed there |
| Scaling ceiling: `qcQuestMaxLevel` | 27,637 (16 October 2026) | none | **nature:** Forever's quests don't scale. Its probe of 14 October 2026 (1.60.1.70374, level 16) gave each of the 2,964 quests of ours it loaded its stored level, and the low-level rule agreed with `IsQuestTrivial` on 2,963 (the other is 8856, level 0). Retail's ceiling is each content tuning's level at the cap, from its probe (`Apply-QuestScaling.ps1`, runbook step 2j) | Shared code (`qcShownQuestLevel`), no gate on the game: a quest with no ceiling reads its own level, so Forever reads as before. `Apply-QuestScaling.ps1 -Game forever` (runbook step 10) is Forever's check: it fails if a quest the probe loads stops having its stored level, and compares the low-level rule with `IsQuestTrivial` as retail's run does |
| Skill requirements | none | 141 | **data** (the code row above) | Yes: `QuestV2CliTask` and TrinityCore |
| Unavailable flags | 240 | 0 | process (above) | Later |
| Pins with an NPC ID | 10,588 of 13,547 (16 October 2026, after the nameless pins went one per spot; of 16,084 on 12 October) | 1,506 of 1,699 | both; retail's IDs from TrinityCore and the client's giver table (#208), Forever's from CMaNGOS | Process: retail never re-examines a nameless pin (372 stand at a TrinityCore starter of their quest), and when starts moved to another map on 8 October it copied the old map's NPC (45174 has 12 pins named Allari); Forever recomputes identity at each import (data-sources-review.md, D10, recommendation 31) |
| Pins with neither ID nor name | 2,622 (16 October 2026, after the nameless pins went one per spot; 5,159 on 12 October) | 4 | retail's are mostly task quests and quests no source names a starter for, besides popups, items, ship decks and the quests TrinityCore's start points place with no starter standing there: on 16 October 706 of the 2,622 hold a task quest (624 hold only task quests; 1,012 task quests in all) and 1,916 hold none; on 12 October, before the merge, the breakdown was 829 for the task quests (the start points added on 11 October) and about 2,766 for the quests with no named starter; Forever has 23 start points in its client | **data** on Forever's side: the importer counts the start points every run | – |
| Pickup sources for pins | the client's `QuestPOIBlob` start points (point 32; task quests too, except world quests, bonus objectives, threat wrappers and callings, 11 October 2026), TrinityCore's `quest_poi` start points for the quests the client lists none for, the client's giver table, TrinityCore's starters and spawns, and the addon's recorder once files exist (step 6d) | CMaNGOS's creature and object givers with their spawns, the recorder's places (from the ledger), the hand list, the client's 23 start points | **data:** CMaNGOS's `quest_poi` has no point 32 (its -1 is the hand-in), Forever's client lists 23 start points, and its 200 item-started quests stay pinless, while retail pins an item-started quest only where a start point exists (945 of its 1,061 unpinned ones have none); **nature:** Forever has no world quests to leave out and no client giver table; **process:** retail pins every place of a quest, Forever merges quests starting at one spot into one nameless pin (11 quests on 4 pins), and since 16 October 2026 both games' tools give nameless pins one pin per 1.5-point spot (recommendation 11), which retail's pin data took on 16 October 2026 (16,084 to 13,547 pins, 2,746 nameless pins merged); retail's TrinityCore pass holds holiday, profession and not-in-QuestV2 quests that Forever pins from the same kind of source, and never moves the legacy pins of the 6,612 quests only TrinityCore places (data-sources-review.md, recommendations 29 and 30) | Watch Forever's side: the importer's start-point count, the map pass's offers (0 on build 70245), and whether CMaNGOS or its client gains a point-32 table |
| Quest types | retail: probe, API and `QuestV2` | the server's flags (quest cache), then CMaNGOS's SpecialFlags | process; the probe's per-quest `IsRepeatableQuest` answers false for every quest on both games, so only an offer's flag says "repeatable" | Process: retail never compares its types with the server's flags, which Forever uses (96.7% agree, 185 would change; data-sources-review.md, recommendation 12); 86 retail world quests are typed one-time (D12) |
| Category names in the player's language | all from the client since #207, except our own text for Mac'Aree, Time Rift, Weekly Events, Legion Uncategorized, Warfront Contribution and 9.1 Campaign | all from the client | both | Renaming the first three to Blizzard's names is data-sources-review.md decision 8 |
| Category placement | legacy data, then `Place-UncategorisedQuests.ps1` (the API's area) and rules inside it | the game's sort, then CMaNGOS's, with a hand zone list | process: retail reads only the zone half of the game's sort, through the API's area; the heading half, the quest cache's copy and any check of quests already filed are unread | Partly: the sort placement (open-items row 18) and a report-only audit (data-sources-review.md, recommendation 19) |

## The tools and the sweep's steps

| Step or tool | Retail | Forever | Why | Share? |
|---|---|---|---|---|
| 1 faction, race and class against Blizzard's API | `Audit-QuestAccuracy.ps1` | the importer takes the cache's race masks over CMaNGOS's | the API has no Forever | not equivalent: Forever takes CMaNGOS's faction for 1,336 quests whose record lists no races, with no review row, retail reads no emulator race data, and neither has its race check (step 1e) yet (data-sources-review.md, recommendation 7) |
| 1b second source for race and class | `Get-WagoQuestRequirements.ps1`: `QuestV2CliTask`, start-point conditions, and `ItemSparse`'s items that start a quest | the importer reads the same `ItemSparse` columns (11 October 2026) | `QuestV2CliTask` is retail's alone; the starting items' classes are in both clients | the item part: done for both |
| 1c quest names | from the API, else the newest quest cache, else the task table (`Sync-QuestNamesFromApi.ps1`), never a title starting `[DEPRECATED]` | from the cache | – | equivalent since 16 October 2026, when retail's quests with no API record took the cache's or the task table's titles (data-sources-review.md, D16) |
| 1d professions | `Sync-QuestProfessions.ps1`: task quests, profession headings, knowledge rewards, hand decisions, and the quests filed under another profession's heading | the last check alone, `-Game forever` (step 10, item 10; 12 October 2026: 114 quests under its nine profession headings, none under another's) | `QuestV2CliTask` is retail's alone and Forever's quests reward no profession knowledge, so Forever's professions come from CMaNGOS in the importer | the heading check: done for both; the passes: nature, except TrinityCore's RequiredSkillID, which retail doesn't read though Forever reads its CMaNGOS twin, and the items that need a skill to start a quest, which neither game reads yet (data-sources-review.md, recommendations 16 and 23) |
| 6b task quests the client lists and the data lacks | `Add-TaskQuests.ps1` (11 October 2026): the 506 player-facing rows of `QuestV2CliTask`, with no pins | – | `QuestV2CliTask` is retail's alone: Forever's client lists no task table (613 tables on build 70338, none of them a task or bounty table) and its map pass found no task quests; nor has it world quests or bonus objectives to fill one | nature; watched: step 2b's new-table flag names a `QuestV2CliTask` appearing on Forever, and then the tool needs that game's data and category files |
| 2 reputation | API compare and backfill, then a pass that checks the quest cache's rewards against ours and the API's | the cache, in the importer | Forever has no API (nature) | process, partly nature: retail takes the API and checks the cache, Forever takes the cache and checks it against nothing; a CMaNGOS check with a baseline is data-sources-review.md recommendation 15 |
| 2b the tables kept by hand (`Audit-QuestTables.ps1`) | yes | the consistency part, `-Game forever` (9 October 2026) | Forever's tables are generated, so the "hand error" checks don't apply, but its consistency checks do: a one-time quest requiring a recurring one, a recurring quest in a breadcrumb or "only one of these" pair, a pair naming a quest not in the data, a prerequisite of another profession (12 October 2026), a quest listed twice | done: step 10 runs it; the API, TrinityCore and client-table parts stay retail's (`-OwnDataOnly` skips them) |
| 2c prerequisites | API, the client's task quests (`QuestV2CliTask`), its quest line and campaign conditions (`QuestConditions.ps1`), the map pass's offers, TrinityCore, and a hand list (quest-link-decisions.csv) | CMaNGOS, in the importer | the line and campaign conditions are retail's (Forever has no campaigns); the offers check waits for a Forever map pass that offers anything | not equivalent: retail reads TrinityCore narrowly where Forever reads CMaNGOS in full (by the user's 6 October rule, quest-table-checks.md decisions 3 and 4, which the review's decision 1 puts back to the user), and Forever's cache follow-ups have none of retail's filters (data-sources-review.md, recommendations 7, 9 and 10) |
| 2d holiday tags (`Audit-QuestHolidays.ps1`) | yes | **no** | Forever's tags aren't hand data: the importer derives them on every step-10 run from CMaNGOS's events, the game's and CMaNGOS's headings and the spawn rule (54, 119, 63 and 68 of its 351 tags, 12 October 2026; the spawn rule should count a spawn in several holidays' events as no evidence, data-sources-review.md D19), so a check against the same tables would only repeat it. The 18 quests of its small hand list (`forever-quest-holiday-decisions.csv`, 11 October 2026) are the exception, and the importer reads that file and reviews any row another source disagrees with. The one thing the audit could find, a CMaNGOS event with quests that the importer maps to no holiday, is two events and four quests today (New Year's Eve, 8860 and 8861; Winter Veil: Gifts, 8827 and 8828), all tagged Winter Veil in Forever's data (9 October 2026) | equivalent |
| 2h the calendar (`Review-Calendar.ps1`) | yes, live and the PTR | yes | – | shared (12 October 2026): one review reads both games' Holidays tables, one baseline (its three files) and one decisions file hold both, and the sweep asks for one `/qc holidays` per game |
| 3 quest types | `Retype-*.ps1` with the probe | the importer | – | not equivalent: Forever recomputes types from the server's flags and CMaNGOS at each import; retail retypes one way, from the API, the probe and QuestV2 (data-sources-review.md, recommendation 12) |
| 4 storylines | `Build-QuestLines.ps1` | `Build-ForeverMenu.ps1` reads the same table | data (3 rows) | watched; the two tools also choose a quest's line by different rules (data-sources-review.md, recommendation 41) |
| 5 zone table and client names | three tools | `Build-ForeverMenu.ps1` | – | process: Forever's zone table is generated from the client, retail's is kept by hand and leaves 98 pinned maps unrouted (data-sources-review.md, recommendation 19) |
| 6 pins | the pipeline from `QuestPOIBlob` and TrinityCore's `quest_poi` | the importer from CMaNGOS, the recorder and the client's start points | the same rule, a pin at every place a source puts the pickup, from each game's sources (the data row above) | not equivalent: retail's TrinityCore pass holds quests Forever pins, never places from spawns and never moves legacy pins (data-sources-review.md, recommendations 29 and 30) |
| 6 duplicate quests on nearby pins (`Remove-DuplicatePinQuests.ps1`) | yes | `-Game forever` (9 October 2026) | it had never been pointed at Forever's folders; retail's start points (`quest_locations.csv`) have no Forever counterpart, so only its half-point rule applies | done: the importer applies its rule before it writes (12 October 2026), and step 10 runs it as a check |
| 6d the addon's recorder merged into the pins | `Import-RecordedGivers.ps1`: blank NPC IDs and names filled, pins for quests no source places; the ledger and the lists, retail's and Forever's | the ledger and the lists only; Forever's pins are rebuilt by step 10, which reads the ledger for its recorded givers and stops if it is stale (since 11 October 2026) | process: a fill into Forever's pins would be overwritten at the next import, so the ledger is the importer's input instead | **Done 11 October 2026:** the importer reads the ledger and merges recorded places at 1.5 points ([quest-giver-recorder.md](quest-giver-recorder.md), "Forever's importer") |
| 6c NPC IDs for named pins | TrinityCore (`Fill-PinNpcIds.ps1`), and the client's giver table with TrinityCore's starters, which also move a quest to its giver's pin (`Apply-ClientQuestGivers.ps1`) | CMaNGOS gives the IDs, from each quest's starter, so there is no neighbour's identity to correct | `CollectableSourceQuestSparse` is retail's alone | nature for the giver table; process for the rest: retail never revisits a nameless pin and skips nameless copies of a quest that has an NPC pin, where Forever recomputes identity at each import (data-sources-review.md, recommendation 31) |
| 7 quests no longer obtainable | `Find-UnavailableQuestCandidates.ps1` | the importer's refused-quest rule | process | later, after launch |
| 8 dungeons against the Dungeon Journal | `Audit-DungeonCategories.ps1` | – | **data:** Forever's client has no `JournalInstance` (nor any `Journal*` table: 612 tables on builds 70205 and 70245, checked 9 October 2026); its menu takes instance types from the map table, and `DungeonEncounter` and `LFGDungeons` are all it has near the journal | watched: `Compare-ClientTables.ps1` flags a `Journal` table as quest-related when one appears, and the audit is then pointed at it |
| 9 reachability | yes | yes | – | shared |
| The client-tables check, the API check, the holiday check, the localization test | both | both | – | shared |
| The quest probe | `/qc typecheck` (#42's branch): recurrence and tags | `/qcprobe quests`: the same and more (level, elite, group size, title) | process: two probes for one job; the Forever probe's TOC loads on retail too | **Done 9 October 2026:** one probe for both games (#232-#237). Retail's list is the quests in `data\quests.jsonl`, QuestV2 not asked (the user's call that day); the facts pass has run on both games but no tool reads it yet (data-sources-review.md, recommendation 4); adding the missing-quest candidates to retail's list is its decision 12 |
| The NPC-name check | once, in #112, for the 6,468 IDs then; the probe's list now holds the 8,418 NPC IDs on retail's pins (built 9 October 2026) | every build, `/qcprobe npcs` | process | **Yes:** run each sweep (about 7 minutes on Forever; on retail about 9 when the game has most of the names, 37 after a patch), and compared with the pins by `Compare-PinNpcNames.ps1` (both games, report-only) |
| The recorder | shared since 8 October 2026 (`qcRecorder.lua`, on by default; not yet tried in game); merged into retail's pins by `Import-RecordedGivers.ps1` (step 6d, 9 October 2026) | the probe's and the addon's, both through the ledger (step 6d, then the importer, since 11 October 2026); both are kept and what they saw is combined (the user, 11 October 2026) | – | **Yes:** API review, recommendation 1; [quest-giver-recorder.md](quest-giver-recorder.md) |
| The map pass | done (7 October) | done (7 October) | – | run on both each sweep (maintenance.md, step 4b) |
| Continent geometry (the probe's map pass, `Compare-ContinentGeometry.lua`, step 2f) | the baseline of 12.1.0.69933 (442 rows, 10 October 2026) | the baseline of 1.60.1.70338 (53 rows) | the same tool and file for both games; the two games' maps differ by nature (retail has 15 continent maps with children, Forever 2) | shared |
| The quest cache reader (`Read-QuestCache.ps1`) | step 2e, with `Compare-QuestCache.ps1` | every sweep | process: retail's `questcache.wdb` holds the same server records for the 31,425 quests the type probe loaded (localized-quest-names.md), in the same layout the reader checks | **Done 9 October 2026** ([retail-quest-cache.md](retail-quest-cache.md)): it gives retail the quest sort and, as a content tuning, the level the server asks for (`minLevel`, which Forever's `qcQuestMinLevel` is made from; retail's `level` was taken from the API's minimum and differed from it for 1,398 quests, whose API minimum now sits in `qcQuestMinLevel` too, with the client's level ranges for the quests the API has no record of: see maintenance.md, "The quest and pin data files" and step 2g); the start item turned out to be the item the quest hands over when accepted, not the one that begins it, so it is no prize. The reader read retail's layout (TrinityCore's, with two numbers fewer), and `Compare-QuestCache.ps1` watches it against Blizzard's own data |
| Hand lists | `pin-npc-id-decisions.csv`, `pin-giver-decisions.csv`, `quest-link-decisions.csv`, `quest-profession-decisions.csv`, `quest-holiday-decisions.csv`, `quest-accuracy-manual-decisions.csv`, `quest-table-decisions.csv`, `unavailable-quest-decisions.csv`, the hand rows of the zone table, and category rules kept inside `Place-UncategorisedQuests.ps1`, among others | `forever-quest-givers.csv`, `forever-quest-zones.csv`, `forever-quest-holiday-decisions.csv`, `forever-quest-link-decisions.csv`, `forever-quest-class-decisions.csv`, `forever-quest-table-decisions.csv`, among others | – | equivalent, except that retail's link file can only SET a prerequisite and its category rules sit in a script (data-sources-review.md, recommendation 40) |
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
| 1 | The recorder on retail (API review, recommendation 1) | small in the addon (built 8 October 2026), medium for the merge tool (built 9 October 2026) | the one check Forever has that retail lacks outright; the in-game session and retail's first ingest are left (Forever's file was ingested on 11 October 2026: the ledger only, as the tool writes no Forever pins) |
| 2 | One probe for both games: a retail mode for `Build-ProbeLists.ps1`, the quest-facts pass built once, the NPC pass run on retail each sweep, #42's probe retired | medium | done 9 October 2026 (#232-#237); the facts it saves are read by no tool yet (data-sources-review.md, recommendation 4) |
| 3 | Profession skill requirements on retail: the `GetProfessionInfo` fallback (done 7 October 2026), then the in-game check of the expansion lines, then the data from `QuestV2CliTask` and TrinityCore | small code (done), medium data | the case that started this; the fallback makes the code the same on both, and changes nothing in game until retail has requirement data |
| 4 | `Audit-QuestTables.ps1`'s consistency checks on Forever's generated tables, in step 10 | medium | done 9 October 2026 (`-Game forever`, `-OwnDataOnly`): 6 findings, five kept and one fixed |
| 5 | `Remove-DuplicatePinQuests.ps1` on Forever's pins, in step 10 | small | done 9 October 2026 (`-Game forever`): it did find something, 11 pins |
| 6 | Retail's quest cache through `Read-QuestCache.ps1` | medium | done 9 October 2026: the layout is TrinityCore's, 120 fixed numbers; the start items are not what the recommendation took them for ([retail-quest-cache.md](retail-quest-cache.md)) |
| 7 | The importer prints `QuestLine` and `QuestLineXQuest` row counts | small | done 9 October 2026: the "Storylines:" line (3 and 22 rows on build 70205) |
| 8 | The retail map pass | a run | the pin comparison; done 7 October 2026 (game-api-review.md, "Map-offers probe: retail run") |
| 9 | `JournalInstance` on Forever, and the dungeon audit if it's there | small check | done 9 October 2026: it isn't there, so there is no audit to point (row 8) |
| 10 | A Forever review of hidden and test quests | later | after launch |
| 11 | One rule for nameless pins in both games: a pin per quest and place (retail) or per spot (Forever) | small | done in the tools, 16 October 2026: per spot in both games, the spot 1.5 map points (the user, 13 and 15 October; open-items row 7). `tools\PinRules.ps1` holds the grouping rule, the order a pin's giver is chosen in, the icon from a pin's quests and what happens when a giver turns up for a quest of a shared nameless pin; `Assemble-PinDB.ps1`, `Import-ForeverData.ps1`, `Apply-ClientQuestGivers.ps1` and `RecordedGivers.ps1` use it, as both games use `DuplicatePins.ps1`. Retail's carry-over stays its own. Applied to retail's pin data on 16 October 2026: 2,746 nameless pins merged, 16,084 pins to 13,547 (quest-location-data-pipeline.md, "October 2026, one pin per spot", "Applied") |
| 12 | Name retail's pins after the object or item that starts the quest | small | 12 October 2026: 151 pin-quest pairs on 109 nameless pins belong to object-started quests (59 pairs, on 45 pins, stand within 1.5 points of their object), and 99 pins are named exactly after a starting item. Forever names its object pins from CMaNGOS but no pin after an item: its 200 item-started quests are pinless. Now data-sources-review.md recommendations 16 and 31 |
| 13 | Prerequisites from the quest line order, on retail as on Forever | decided: Forever only | built for Forever on 10 October 2026, where it is the only source (`QuestLines.ps1`, `Import-ForeverData.ps1`). Retail has Blizzard's own prerequisites, and measured on its tables (12.1.0.69933 quest lines, 12.1.5 map points) the rule would add one to 8,654 of its 16,093 chained steps, 8,697 counting the steps whose places differ: where retail does have one, the previous step is it 93% of the time, so about 1 in 14 of those additions would be wrong, and a wrong prerequisite hides a quest the player can take. **Decided by the user, 10 October 2026: retail keeps using Blizzard's API for its prerequisites, for now.** The rule is not applied there. To reopen it, the measure above is the evidence to start from, and the cheaper form is to use it only for steps the API lists no prerequisite for, each listed for review. **12 October 2026, still not applied:** the retail map pass offered 67 of 165 later steps together with the step before, so the order alone would hide quests the game offers. For the "unfinished requirements" reports (open-items.md) the user chose narrower Blizzard rules instead, in `Sync-QuestPrerequisites.ps1` (step 2c). Each chapter of the current expansion's campaign (270) needs the chapter before. The client's conditions on that expansion's quest lines and campaigns are applied, the hidden quest 90806 included. A required quest the game offered together with its quest is dropped, as is a recurring quest's recurring requirement Blizzard doesn't name. Forever has no campaigns, line conditions or map offers yet (its beta offered none); its recurring links come from CMaNGOS, the server's own data, so they stay |

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
   On 12 October 2026 the user added narrower Blizzard rules for retail's current expansion instead of the
   order (recommendation 13's row).

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
- 2026-10-11: step 6b, `Add-TaskQuests.ps1` (decision 9 of [game-api-review.md](game-api-review.md), decision 1
  of [open-items.md](open-items.md)), is retail's alone, by nature: Forever's client has no task table, and
  with no world quests, bonus objectives or world events there is nothing for one to carry. Nothing was
  built for Forever; the sweep's step 2b names the table if it appears.
- 2026-10-11: recommendation 1, the last piece on Forever's side: `Import-ForeverData.ps1` reads the recorder ledger
  for its recorded givers, places and offers (the addon's notes now reach Forever's pins), with the recorded-place
  radius at 1.5 map points, and stops when the probe's file holds notes the ledger lacks. Retail is untouched.
  What the next import would move is in [forever.md](forever.md), "The importer reads the ledger". The same day
  the user kept both recorders ("yes, keep both, go ahead"): the probe's is not retired, and the ledger combines
  its notes with the addon's.
- 2026-10-11: waypoints without TomTom (game-api-review.md, recommendation 6) built for both games in
  one change, gated on the functions and the game's answer for the map; checked with stand-ins for a
  client with the functions, one without, and a map that refuses; the in-game look is for both games.
- 2026-10-12: step 1d, `Sync-QuestProfessions.ps1`, reads Blizzard's profession headings and the knowledge a quest
  rewards besides the task table, and a hand list; its new check of quests filed under another profession's heading
  runs on Forever too (`-Game forever`, step 10's item 10), which found nothing. The passes stay retail's: Forever has
  no task table, and its quests reward no profession knowledge.
- 2026-10-12: Forever's importer applies `Remove-DuplicatePinQuests.ps1`'s rule itself before it writes (the rule is
  in `DuplicatePins.ps1`, which both use), so a rerun writes `pins.jsonl` as committed and step 10's item 9 is a
  check that takes nothing off. Retail's runs of the tool print the same as before (checked on the pins of
  4 October, before its first run: 67 quests off 30 pins, and on today's).
- 2026-10-12: retail's "unfinished requirements" filter (open-items.md): `Sync-QuestPrerequisites.ps1` takes the
  client's conditions on Midnight's quest lines and campaigns (`QuestConditions.ps1`) and campaign 270's chapter
  order, and drops required quests the map pass saw offered together with their quest and recurring links
  Blizzard doesn't name (recommendation 13's row). `qcPrereq.Text` leaves out a quest the data has no row for,
  in both games' code. Forever needed nothing more: its importer has read CMaNGOS's next quests since #308 (291 of
  293 links in its data; 7141 and 7142 are REMOVE rows).
- 2026-10-12: retail reads its own quest cache's follow-ups (`RewardNextQuest`) in step 2c, as Forever's importer
  does: 1,384 quests get the quests whose hand-in offers them, where TrinityCore's requirement agrees and the
  quest isn't one the follow-up is a breadcrumb into; the
  2,727 links it doesn't repeat are often re-offers and are not taken (retail-quest-cache.md, "Next quest").
- 2026-10-12: the field-by-field review of every source ([data-sources-review.md](data-sources-review.md)) found
  that several rows here hid different rules behind "equivalent": prerequisites (2c), quest types (3), pins (6 and
  6c), the zone table (5), step 1's faction source, the links and holidays (hand data on retail, generated on
  Forever), and reputation's checks. Those rows now say so and give the review's numbers; the review's source
  order table is meant to join this document once the user adopts it (its recommendation 42). Nothing in the data,
  the addon or the tools changed.
- 2026-10-16: recommendation 11 in retail's data: its nameless pins are one per spot, as Forever's are (16,084 pins
  to 13,547; quest-location-data-pipeline.md, "October 2026, one pin per spot", "Applied"). Forever's pins did not
  change.
