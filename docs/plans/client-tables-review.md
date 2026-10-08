# Client tables review

## Goal

The game client's own tables (wago.tools' CSV exports of its DB2 files, pinned to a build) feed
the map pins, the storylines, the category names, Forever's start points and most of Forever's
database, but the 26 tables the tools read were picked as each need came up. On 7 October 2026 the
user asked that every sweep check the tables for schema changes and for new tables or columns the
addon could use ([maintenance.md](../maintenance.md), step 2b), and whether anyone had ever looked
through all of them. Nobody had. This is that review, for both games: every table whose name or
columns could bear on quests, quest givers, map pins, zones, holidays, requirements, storylines,
reputation or the menu, what each holds, and whether it gives the addon anything the game's own
API and Blizzard's web API don't. Nothing was changed; the recommendations at the end are for the
user to choose from.

## What was reviewed (7 October 2026)

- **Builds:** retail 12.1.0.69933 (1,104 tables) and WoW: Forever beta 1.60.1.70245 (612), the
  builds step 2b listed that day. The 12.1.5 PTR (70077) has 1,105: SpellAuraNames and
  SpellEffectNames added, Hotfixes gone, nothing new for quests. Its QuestV2 has 66,545 rows against
  66,420, QuestPOIBlob 72,732 against 72,381, and UiMap 1,967 against 1,960.
- **Which tables:** every name that suggests quests, givers, points of interest, maps, areas,
  holidays, campaigns, content tuning, waypoints, collectables, scenarios, reputation, renown,
  creatures, objects or labels: 90 downloaded for retail and 55 for Forever, into a scratch folder
  (one request at a time, a second apart; nothing new was kept in `tools\`). Each was read for its
  columns and a sample of rows, then measured against `data\quests.jsonl` (35,023 quests),
  `data\pins.jsonl` (14,923 pins), the hand-kept tables in `qcQuest.lua`, the client's start points
  in `QuestPOIBlob`, and the Blizzard API cache from the last sweep (30,068 quest records, and
  5,182 quests the API doesn't know).
- **Which game has which:** of the quest-named tables, Forever has AreaPOI, AreaPOIState,
  ContentTuning, ContentTuningXExpected, Holidays, HolidayNames, HolidayDescriptions,
  QuestFactionReward, QuestInfo, QuestLabel, QuestLine, QuestLineXQuest, QuestMoneyReward,
  QuestPOIBlob, QuestPOIPoint, QuestSort, QuestV2, QuestXP, UIMapPinInfo and the UiMap tables.
  Retail alone has AdventureMapPOI, Campaign and its X tables, CollectableSourceQuest and
  CollectableSourceQuestSparse, ContentTuningXDifficulty and XLabel, HolidayXTimeEvent, QuestHub,
  QuestObjective, QuestPackageItem, QuestV2CliTask, QuestXGroupActivity, QuestXUiWidgetSet, the
  UiMapGroup tables and the Waypoint tables. The 32 tables Forever has and retail lacks
  (LevelExperience, RaceStat, SkillLineCategory, the SuperDistrict realm tables, PetLoyalty and
  the rest) have nothing to do with quests.
- **Forever's beta builds:** 70245's quest and map tables have the same row counts as 70205's
  (QuestV2 6,609, QuestPOIBlob 54, QuestLine 3, QuestLineXQuest 22, AreaTable 1,371, UiMap 60,
  UiMapAssignment 61, Map 73), so step 10 needs no rerun for it.

## What the addon already gets elsewhere

A table only earns a place where it gives something these don't, or gives it offline for every
quest at once.

- **Blizzard's web API,** one record per quest in the sweep (step 1), has the area for 21,008 of
  the 30,068 records, a minimum and maximum character level for all of them, a category for 8,666,
  a type (dungeon, raid, world quest and so on) for 1,885, daily, weekly or repeatable flags for
  3,090, 586 and 500, required quests for 910, a reputation requirement for 398, races for 747 and
  classes for 1,927, and reputation rewards for 11,095. It never names a quest giver or a position,
  a breadcrumb, a group of which only one can be done, a holiday, or a profession skill level (its
  `trade_skill_spell`, on 56 quests, is a reward).
- **The game, at runtime:** the quest line a quest is in (`C_QuestLine.GetQuestLineInfo`), its
  campaign and chapter (`C_CampaignInfo.GetCampaignID`, `GetCampaignInfo`,
  `GetCampaignChapterInfo`), a map's level range (`C_Map.GetMapLevels`), a map's floors
  (`C_Map.GetMapGroupMembersInfo`), the emissary bounties on a map
  (`C_QuestLog.GetBountiesForMapID`), a quest's tag and difficulty level, and the calendar's
  holidays, which the seasonal filter already reads. No function names a quest log heading
  (`QuestSort`) by its ID.
- **The other sources the sweep reads:** TrinityCore's database for NPC IDs, breadcrumbs, groups
  and previous quests (steps 2b, 2c and 6c), and CMaNGOS's for Forever (step 10).

## The tables the tools read, and the columns they don't

- **QuestV2CliTask** (6,242 rows; 5,230 of its quests are ours: 3,282 world quests, 779 dailies,
  1,068 one-time) is the client's own copy of the task quests: world quests, callings, bonus
  objectives and the like. Step 1b reads only its race and class masks. It also has:
  - **Prerequisites:** `FiltCompletedQuest` names required quests for 787 (731 ours), and
    `ConditionID` points into `PlayerCondition`, whose `PrevQuestID` is set for 2,296 of them
    (2,114 ours: 1,866 world quests, 137 dailies, 105 one-time). The API knows only 124 of those
    2,296, and names required quests for none of them, so the client is the only source. The addon
    hides world quests by default, so the value is small.
  - **Profession skill levels:** `FiltMinSkillID` for 524 (507 ours), nearly all Legion, Kul Tiran
    and Shadowlands gathering and crafting world quests, against the expansion's own skill line
    (Legion Mining 25, Kul Tiran Herbalism 1, Fishing 75). Only 97 of them carry a profession in
    our data; `SkillLine.ParentSkillLineID` maps each line to its base profession's bit. Retail has
    no quest skill requirements otherwise ([forever.md](forever.md), "Profession skill
    requirements").
  - **StartItem** for 198 (191 ours, 42 with a pin), **QuestInfoID** (World Quest, Rare World
    Quest, Battle Pet World Quest, Calling Quest and so on) and **ContentTuningID** for 5,961.
  - **BreadCrumbID** is set for 11, and the pairs are unrelated quests ("Fashion Week" to a Battle
    for Azeroth work order), so it's unusable.
- **QuestPOIBlob.PlayerConditionID:** 1,390 of the 17,855 start points carry a condition (546
  distinct). Step 1b reads the 15 with races and the 19 with classes. 55 name a previous quest (69
  quests, 21 of which already have a prerequisite), and 297 point at a ModifierTree, which no table
  decodes. Nothing to take.
- **QuestV2** has three columns: ID, UniqueBitFlag and UiQuestDetailsThemeID. It carries no
  ContentTuningID: a quest's level range is the server's, and the API has it.
- **QuestLine** (PlayerConditionID, CompletionPlayerConditionID, QuestID), **UiMap**
  (ContentTuningID, BountySetID) and **AreaTable** (ContentTuningID, FactionGroupMask): unused
  columns that the API or the game cover.
- **Faction:** step 2b reads its renown, friendship and paragon columns. There is no MajorFaction
  table in 12.x: the renown tracks are rows of **Covenant** (34, from Kyrian to Preyhunter's
  Journey, each with its FactionID), which step 5 reads for the covenants' names.
- **PlayerCondition** on its own (48,043 rows; 9,231 with a previous quest, 592 with a skill) only
  speaks through the tables that point at one of its rows.
- **Achievement.csv and JournalEncounter.csv** in `tools\` are left over from earlier work: no tool
  reads them, and step 2b checks their columns for nothing.

## The decision table

Rows are retail / Forever; a dash means the game lacks the table. "Measured" is against our data
on 7 October 2026.

| Table | Rows | What it holds | Measured | Verdict |
|---|---|---|---|---|
| CollectableSourceQuestSparse (with CollectableSourceQuest and CollectableSourceInfo) | 15,172 / – | For each quest whose reward has a transmog appearance: the quest, its giver's creature ID, the instance and the giver's world position | 2,074 quests (2,070 ours), 165 with two or more givers. Against the pins: the same NPC ID for 1,758, another for 76, no ID for 133; 103 quests have no pin, and none of those has a start point in QuestPOIBlob. The positions are the giver's spawns: one for 1,510 quests, two for 318, five or more for 75. The nearest spawn is within 0.5 points of our pin for 1,381 of the 1,758, within 1.5 for 1,461, over 3 for 238 (other spawns of the same NPC), and on another map for 24. Of the 133 without an ID, 96 have a spawn within 1.5 points. Of the 76, 47 have one within 1.5: Blizzard's ID is another copy of the character (Locus-Keeper Mnemis 167034 for our 167035). | **Use:** a Blizzard source of NPC IDs and spawns for step 6c, ahead of TrinityCore |
| QuestSort | 199 / 39 | The quest log's headings, in every language | Forever's menu already takes its headings from it (step 10). On retail, 32 categories with quests are still named by our own text; 27 match a heading exactly (Alliance and Horde War Campaign, Garrison Campaign and Garrison Support, Heritage, Tournament, Timerunning, The Harbinger, Warbands and the rest), 2 nearly (Time Rift and Time Rifts, Weekly Events and Weekly Event), and 3 don't (Legion Uncategorized, Mac'Aree, Warfront Contribution) | **Use:** their translations, as Forever's, since no runtime function names a heading |
| UiMapGroupMember (with UiMapGroup) | 836 / – | The floors of each multi-floor map, with their names | 9 groups are partly in the zone table and 28 of their floors aren't: Black Temple's 7, Dawn of the Infinite's 8, Firelands' 2, Mardum's 2, the Exodar's 3, the Stockade, Greymane Manor's main floor and Tazavesh's Aggramar's Vault | **Use:** a rule for `Add-ZoneTableMaps.ps1` (step 5) |
| Holidays, HolidayNames | 799, 160 / 22, 16 | Every calendar holiday with its name, dates and durations | Every ID in `qcHolidays` is there under its name; Hallow's End's second ID, 1405, is the kind of thing that has been found by hand in game. Forever's 22 rows include four new ones ("Call to Arms: Darkspear Islands") and still neither the Scourge Invasion nor the Ahn'Qiraj War Effort | **Use:** an offline check of `qcHolidays` in step 2b |
| QuestV2CliTask (the columns above) | 6,242 / – | The task quests | Skill levels for 410 world quests that have no profession in our data; prerequisites for 2,114 task quests | **Used:** the profession of 410 quests and prerequisites for 850, steps 1d and 2c (Status); the skill level waits for [game-parity.md](game-parity.md) |
| Campaign, CampaignXQuestLine, CampaignXCondition | 181, 809, 258 / – | Campaigns (titles, localized), their quest lines in chapter order, and the conditions between chapters | 145 campaigns hold 740 of our 1,474 storylines and 5,946 quests. The game gives a quest's campaign at runtime | **Maybe:** a feature (a campaign line in the tooltip, or campaigns in the menu), not data the addon lacks |
| ContentTuning (with ContentTuningXExpected, XDifficulty, XLabel, ConditionalContentTuning, GlobalGameContentTuning) | 2,929 / 100 | Level ranges and scaling | Only task quests, areas and maps carry a ContentTuningID; the API gives every quest's range, and `C_Map.GetMapLevels` a map's | No |
| AdventureMapPOI | 514 / – | Points on the Legion, Battle for Azeroth and Torghast adventure maps | 500 name a quest, 475 ours, 30 with a pin. 420 are 12.1's Prey hunts, with no position; the 25 others are placed at the zone chosen, not at a giver | No |
| QuestHub | 107 / – | A quest's hub, as an AreaPOI | 104 ours, 97 with a pin | No |
| Bounty, BountySet | 135, 9 / – | The emissary quests | 134 ours, all recurring already (96 daily, 38 world quests); 96890 isn't in our data | No |
| ParagonReputation | 79 / – | The paragon cache quests | 59 ours, all typed 128; the rest are hidden quests | No |
| RenownRewards | 1,388 / 22 | Rewards by renown level; Forever's are PvP rank rewards | 435 rows name a quest (123 quests): unlock-tracking quests, none ours and none in `qcRenownLevelRequirements` | No |
| QuestObjective | 10,762 / – | The objectives of 4,431 task quests | All in QuestV2CliTask, and the game shows objectives itself | No |
| QuestLabel | 1,912 / 2 | Content labels on quests | The labels have no names in any table (6036 is the Prey hunts, 2703 the dragonriding races) | No |
| AreaPOI, AreaPOIState | 3,909, 1,070 / 372, 20 | Named landmarks with world positions, and their states | Only QuestHub links a quest to one | No |
| Creature | 23,074 / 179 | Names of the creatures the client needs (pets, mounts, the journal) | 1,368 of our 11,473 pin IDs, mostly with no name; none of the 363 ID-less pin names | No |
| GameObjects | 31,736 / 1,520 | Client-side objects with positions: doors, transports, decorations | 31,412 are decorations; no wanted posters or quest objects | No |
| FriendshipReputation, FriendshipRepReaction | 110, 902 / 1, – | Friendship ranks and their names | The game gives them at runtime | No |
| Vignette | 7,226 / 2 | Rares and treasures, with their tracking quests | Hidden tracking quests | No |
| Scenario, ScenarioStep, QuestDrivenScenario | 1,483, 4,647, 65 / – | Scenarios and their steps | The steps' reward quests are hidden | No |
| ZoneStory | 169 / – | A zone's story achievement and map | Achievements, which the addon doesn't track | No |
| The Waypoint tables | 574 nodes, 371 edges, 467 locations, 11 volumes / – | The navigation system's portals and routes | Not quests | No |
| UIMapPinInfo, UiMapLink | 5, 62 / 4, – | Pin textures, links between maps | Art | No |
| QuestXP, QuestMoneyReward, QuestFactionReward | 130, 130, 2 / 100, 100, 2 | Rewards by quest level and difficulty | QuestFactionReward is read for Forever's reputation; the others are rewards | No |
| QuestPackageItem, QuestXUiWidgetSet, QuestXUIQuestDetailsTheme, UiQuestDetailsTheme, QuestFeedbackEffect, QuestXGroupActivity | 13,368, 117, 476, 72, 1,167, 101 / –, –, –, –, 255, – | Reward packages, UI widgets, quest window themes, interaction effects, group finder links | UI | No |
| HolidayDescriptions, HolidayXTimeEvent, TimeEventData, EventSchedulerEvent, ScheduledInterval | 280, 1, 5, 43, 295 / 27, –, –, –, 36 | Holiday texts and the calendar's clockwork | The calendar answers at runtime | No |
| LFGDungeons, DungeonEncounter, AreaTrigger, AreaGroupMember, TaxiNodes, LoreText, InvasionClientData, WorldBossLockout, ContentRestrictionRule | various | The dungeon finder, bosses, triggers, flight points, lore, invasions, lockouts, content gates | Not quest data, or hidden quests | No |
| Forever's Achievement, Achievement_Category, Criteria, CriteriaTree | – / 434, 56, 3,277, 6,621 | Forever has achievement tables: statistics, PvP, dungeons; 109 criteria of type 27 (complete a quest) for 84 quests, 32 of them ours | Identical in 70205 and 70245. [forever.md](forever.md) says the client has no achievement categories; the table has "Dungeons & Raids" (14807). Whether the game answers `GetCategoryInfo` for it is for an in-game check | Check in game; otherwise no |
| Forever's Covenant, RenownRewards, FriendshipReputation | – / 2, 22, 1 | Forever reuses renown for its PvP ranks ("1.60.0 PvP Rank", "Rank Points") | Not quests | No |
| QuestInfo | 83 / 7 | Quest type names | Forever's 7: Elite, Life, PvP, Raid, Dungeon, World Event, Legendary. ID 21 is "Life" where retail's is "Class". The cache reader reads it | Read already |

Also looked at and set aside: PerksActivityXHolidays and TransmogHoliday (the Trading Post and
transmog), UIChromieTimeExpansionInfo and UIExpansionDisplayInfo (expansion art, and names the game
already supplies), Profession and ProfessionExpansion (the crafting systems), SkillRaceClassInfo
(which races and classes can learn a skill), Phase, LoreTextPublic, LabelXContentRestrictRuleSet,
FactionGroup and FactionTemplate, and Forever's LevelExperience, SkillLineCategory, MapDifficulty
and Cfg_TimeEventRegionGroup.

## Recommendations, most valuable first

1. **NPC IDs and spawns from CollectableSourceQuestSparse** (step 6c, retail). A tool like
   `Fill-PinNpcIds.ps1` that gives an ID-less pin the client's giver when one of its spawns stands
   within 1.5 points (96 pins), lists the 76 pins that name another NPC for review with the
   spawn's distance (the 47 within 1.5 points are the same spot under another ID), and offers the
   103 quests with no pin their giver and spawn as new pins. It would also serve as a Blizzard
   check on the 1,758 that agree. **Effort:** medium, about a day: the conversion is the pin
   pipeline's, and the review list is the usual kind. **Risk:** low to medium: a giver has several
   spawns, so a quest with a pin keeps its position and only the nearest spawn is compared, and an
   NPC Blizzard names under another ID stays as it is unless reviewed. Blizzard's data over
   TrinityCore's wherever both speak.
2. **Retail category names from QuestSort** (step 5). Give the 29 categories the client's own
   heading in each language, as Forever's categories have had since #183: by hand once, as Forever's
   were, or by a tool that reads the table per locale and writes the keys, which a sweep could then
   rerun. That covers about 2,300 quests' categories, among them the ones maintenance.md lists
   under "Still in English" ("Timerunning", "The Harbinger"). The three that match nothing stay
   ours. **Effort:** small. **Risk:** low: a heading's wording can differ from a zone's, so the
   mapping is by hand, like the other kinds in `Build-CategoryClientNames.ps1`.
3. **Floors from UiMapGroupMember** (step 5). `Add-ZoneTableMaps.ps1` adds a floor when it has the
   same name and parent as a listed map; a group's other members would add the 28 named floors
   above, so the quest list follows the character into them. **Effort:** small. **Risk:** none
   worth naming.
4. **An offline holiday check** (step 2b). For each holiday in `qcHolidays`, compare its IDs with
   every Holidays row of that name, in both games, so a new ID (as 1405 was) shows up in the sweep
   rather than in game. **Effort:** small. **Risk:** none.
5. **Task quests' skill levels and prerequisites from QuestV2CliTask** (steps 1b and 2c). The
   profession bit for 410 world quests, and prerequisites for 2,114 task quests through
   PlayerCondition. **Effort:** small for the bits, medium for the conditions, whose logic fields
   combine several quests. **Risk:** low. **Value:** small, as world quests are hidden by default
   in both views.
6. **Campaigns** (a feature, the user's call). A "Campaign: name, chapter n" line in the tooltip
   needs no data, only `C_CampaignInfo` at runtime; campaign headings in the menu would need
   Campaign and CampaignXQuestLine in `Build-QuestLines.ps1`. **Effort:** small for the tooltip,
   medium for the menu. **Risk:** low.
7. **Housekeeping.** Delete `tools\Achievement.csv` and `tools\JournalEncounter.csv`, which nothing
   reads, so step 2b stops checking them; and check Forever's achievement categories in game before
   the next change to its menu.

Not recommended: everything marked No above. ContentTuning in particular adds nothing to the API's
level ranges, though measuring it raised a data question worth its own note: our `level` is the
API's minimum, and the low-level filter compares it with the character's level, so a quest that
scales up to 30 can count as low level long before the game greys it. The API's maximum would fix
that; it isn't a table question.

## Decisions

1. **Recommendations 1 to 4 go ahead** (2026-10-07, the user), one pull request each, in the
   order 4, 3, 2, 1. Campaigns (6) and the task quests' columns (5) wait.
2. **Recommendation 5 goes ahead too** (2026-10-07, the user, though its value is small: world quests
   are hidden by default). Campaigns (6) still wait.

## Status

- 2026-10-07: review done, for retail 12.1.0.69933 and Forever 1.60.1.70245; nothing changed in
  data or tools. maintenance.md's step 2b points here.
- 2026-10-07: the holiday check (recommendation 4) is part of step 2b, in
  `Compare-ClientTables.ps1` (#205): for each entry in `qcHolidays`, the Holidays rows of its name
  in each build given, through HolidayNames, against the IDs it lists. On the same builds, 15 of
  the 17 holidays match and the two Forever events have no row, as expected.
- 2026-10-07: floors from UiMapGroupMember (recommendation 3), a rule in `Add-ZoneTableMaps.ps1`
  (#206): 25 floors joined the zone table (Black Temple's 7, Dawn of the Infinite's 8,
  Amirdrassil's 3 boughs, the Exodar's 3, Mardum's 2, Greymane Manor's main floor, Tazavesh's
  Aggramar's Vault). Firelands' 2 didn't, as its category holds no quests, which the tool now
  never gives a map to; nor did the Stockade, named like its own category. The reachability check
  is unchanged.
- 2026-10-07: retail category names from QuestSort (recommendation 2), through a new tool,
  `Sync-QuestSortNames.ps1` (#207), which writes the client's heading in each of the 11 languages
  into the Localization files for the 26 retail categories whose heading is worded exactly as the
  category, and Forever's six, which it reproduces byte for byte from the hand-made translations
  that came before it. 227 keys changed or were added; "Rated Pvp" and "World Pvp" took
  Blizzard's capitalisation. Left as they are, as judgement calls for the user: "Time Rift" (the
  game says "Time Rifts"), "Weekly Events" ("Weekly Event") and "9.1 Campaign", whose key can't
  be a Lua name.
- 2026-10-07: the client's quest givers (recommendation 1), through a new tool,
  `Apply-ClientQuestGivers.ps1` (#208), step 6c ahead of the TrinityCore fill: 94 nameless pins
  got the client's giver and its name, 98 pins were added and 10 joined for the 103 quests with no
  pin, the 76 pins naming another NPC are listed for review, and the pipeline rerun merged 27
  pins of newly identified NPCs (quest-location-data-pipeline.md, "October 2026, the client's own
  quest givers"). 14,994 pins. All four chosen recommendations are done.
- 2026-10-07: task quests' professions and prerequisites (recommendation 5):
  - **Professions,** through a new tool, `Sync-QuestProfessions.ps1` (step 1d): 410 task quests
    got the profession their `FiltMinSkillID` names through `SkillLine`'s parent, which their
    quest type's profession (`QuestInfo`) confirms on all 506 quests that have both; 97 had it
    already, and no quest of ours differs. 25 of the 410 have a pin (work orders in Suramar,
    Zuldazar and Nazjatar), so "Hide Other Profession Quests" now hides them from characters without
    the profession.
  - **Prerequisites,** through a third source in `Sync-QuestPrerequisites.ps1` (step 2c): the
    `FiltCompletedQuest` list and the `PlayerCondition` of each task quest, both required, read
    with the logic fields the way TrinityCore reads a PlayerCondition's (bit 16+n turns the nth
    answer round, two bits per slot say and, or or ignore; no row uses both an and and an or).
    687 quests gained a prerequisite (345 world quests and weeklies, 187 one-time, 155 daily)
    and 90 changed: for 75 ours stays, and for 15 the client's replaces ours (11 of them Twilight
    Highlands quests, "Don't Bring That Here" to "Bloodeye Prisoners", where ours chained each to
    the one before and the client gates them all on "Cult It Out"). 73 already matched. 8,306
    quests have a prerequisite now.
  - **The review's 2,114 was an overcount of what can be shown:** of the 3,588 quest slots the
    client's lists fill for our task quests, 2,495 name one of 54 quests we hold no data for, hidden
    tracking quests with no name to show, and 133 name a quest that must not be done. They are left
    out of a list, and out of a whole choice, so 850 of the 2,748 task quests with a list end up
    with one. The tool counts the hidden quests.
  - The skill level (`FiltMinSkillValue`) isn't kept: it goes with retail's skill requirements,
    recommendation 3 of [game-parity.md](game-parity.md).
  - Checked: the data files and Lua agree; the reachability report is identical to master's; a
    second run of both tools changes nothing; the table check found one new finding, a Horde
    quest ("Assault on Skold-Ashil") whose client list names the Alliance's "To Skold-Ashil",
    kept like the two before it.
- 2026-10-07: the pin review (the 76 pins naming another NPC, the 37 without an ID, and four odd
  ones), in quest-location-data-pipeline.md, "October 2026, the pin review", and
  `Apply-ClientQuestGivers.ps1` (step 6c), which now gives a quest to the giver standing at the
  pin on the client's table or TrinityCore's word (123 quests moved, 7 pins named, 10 emptied pins
  gone; 15,054 pins) and reads `docs/plans/pin-giver-decisions.csv` for the 48 cases that stay.
  It found that the client's quest-giver points are mostly turn-in points: of 2,622 quests whose
  TrinityCore starters and enders differ, the point is at an ender for 1,354 and at a starter for
  31. Moving those pins to where the quests start was done on 8 October, by the client's own start
  points (`ObjectiveIndex 32`): "October 2026, pins at the start" in the same plan.
