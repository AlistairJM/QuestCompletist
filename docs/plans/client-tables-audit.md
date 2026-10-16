# Client tables audit: every table, both games

## Goal

On 14 October 2026 the user asked why the addon uses so little of the game client's own database: for
example `BreadCrumbID` in `QuestV2CliTask`, `SortAsNormalQuest` in `Campaign` and `Modifiers` in `QuestInfo`. They
asked for every table that exists to be audited, taking into account which tables each version of the game has and how
they differ, working out the relationships and what the bitmasks mean, and saying why we aren't using everything
possible. [client-tables-review.md](client-tables-review.md) (7 October) was narrower: it judged 90 tables by name
and by whether they gave something the API and the game don't, and it never went through the columns of the
tables we already download. This audit does, for all of them.

## Method

- **Builds, resolved from the source on 14 October 2026** ([maintenance.md](../maintenance.md), "Before a sweep"):
  retail live 12.1.5.70391, WoW: Forever beta 1.60.1.70374, and Classic Era 1.15.9.70003 as a third reference.
  Every table of each was downloaded as wago.tools' CSV: 1,104 (retail), 611 (Forever) and 420 (Era). Only
  `DeclinedWord` and `DeclinedWordCases`, two name-declension tables, are refused by wago.tools. 1,143 distinct tables
  in all, and every one has a verdict.
- **`tools\Audit-ClientTables.ps1`** measures every column of every table (rows, non-empty, non-zero, distinct,
  range, commonest values), reads the schema of [wowdev/WoWDBDefs](https://github.com/wowdev/WoWDBDefs) for each
  column's type, declared foreign key and comment, finds which of our tools mention the table and the column, lists
  every set bit of every flag-like column with example rows, checks every declared foreign key against the
  target's IDs, and tests every integer column against the IDs of 33 key tables to find the relationships the
  schema doesn't declare (with a chance baseline: a column of small numbers "matches" `QuestV2` by luck). It takes
  about two minutes for retail once the tables are downloaded (`-Download` fetches them, 600 ms apart), and its
  output is `catalogue-<game>-{tables,columns,fks,refs}.csv` in [client-tables-audit/](client-tables-audit/).
- **Meanings come from evidence, never from a name.** Eleven researchers (one per theme, each told the
  evidence rules: Blizzard's own UI source and API documentation first, then TrinityCore's code, the wowdev wiki,
  an empirical test with the counts, or agreement with our data, with a confidence of PROVEN, LIKELY or GUESS) took
  their tables column by column. Their reports are the `<cluster>.md` files in the folder; the merged
  [verdicts.csv](client-tables-audit/verdicts.csv) (1,143 tables), [columns.csv](client-tables-audit/columns.csv)
  (861 columns analysed) and [bits.csv](client-tables-audit/bits.csv) (621 decoded bits: 186 PROVEN, 288 LIKELY, 143
  GUESS) hold the detail.
- **Checked by hand afterwards:** the two claims below marked (re-checked), the shared completion slot and the
  spell-started quests, were recomputed from the raw tables, and so were the `AreaTable.FactionGroupMask` values (101
  zones with 6, 88 with 4, 59 with 2). The other counts are the researchers', not recomputed.

## The short answer: why wasn't it used?

1. **Each tool was written for one job and read the columns that job needed.** `Sync-QuestProfessions.ps1` took
   `FiltMinSkillID`, `Compare-QuestLevels.ps1` took the level columns, and so on. Nothing ever asked what the rest
   of a table held, so 1,143 tables were never listed and the columns of the ~25 we download were never read in full.
2. **Most flag columns had no documentation anywhere.** The schema comments cover a handful. TrinityCore documents
   some, Blizzard's UI source names others. The rest had to be decoded from the data. 621 bits are decoded now
   (bits.csv), which makes them usable.
3. **A lot of what looks like a gap is noise.** `BreadCrumbID` has 12 non-zero values on retail, 3 are not quest IDs and the
   other 9 are what chance gives; none is a lead-in. `ModifierTree.TertiaryAsset` looked like 358 quest IDs in the
   relationship scan, but 3,588 of its 3,791 values are under 1,000, so they are small numbers that happen to be quest
   IDs. Hidden tracking quests, art, sound, animation and lore tables carry nothing the addon can show.
4. **No table says what we most want.** None gives a quest giver, a next quest, a breadcrumb or an exclusive group
   directly. The nearest are in the opportunities below. The client leaves the rest to the server.

## What exists where

- **Retail and Forever share 581 tables; Forever has 30 retail lacks, retail 523 that Forever lacks.** The
  Forever-only ones are realm rules (SuperDistrict), pet loyalty, `LevelExperience`, `RaceStat` and similar. Only 20 of the 581 shared tables
  differ in their columns, and none of the differences is a quest table's: `AreaTable.ExplorationLevel`,
  `Faction.RenownThresholdCurveID`, `Map.OceanLiquidTypeID`, `SkillLineAbility` and a few like them.
- **What Forever lacks that matters to us:** `QuestV2CliTask`, `Campaign`, `CampaignXQuestLine`, `CampaignXCondition`,
  `UiMapGroup`, the Journal tables, `AdventureMapPOI`, `Vignette`-era quest links, `CollectableSourceQuest*`,
  `ContentTuning` rows for quests, and any quest `PlayerCondition` reference (its 1,901 `PlayerCondition` rows are
  referenced by no quest table). Its `QuestPOIBlob` has 54 rows and its `QuestLine` 3.
- **What Forever has that retail lacks:** its own playable-race rows (Skyborne Alliance 95, Horde 96), `SkillLineCategory`,
  Forever-only `GroupFinderActivity` level ranges for 41 zones, 82 quest-starting spells, its own tier-4 profession
  skill lines (2937-2948) that its `PlayerCondition` rows already require.
- **Era** is for reference only: 420 tables, almost all a subset of Forever's.

## How the tables relate

Verified by data, not names (`catalogue-*-fks.csv` has every declared key with its resolve rate, `catalogue-*-refs.csv`
every undeclared strong match):

- **A quest** (`QuestV2.ID`) is referenced by 46 declared columns on retail (8 on Forever). The ones that matter:
  `PlayerCondition` (previous, current, completed quest slots), `QuestLineXQuest`, `QuestPOIBlob`,
  `QuestV2CliTask` (itself, and `FiltCompletedQuest_0..2`), `ItemSparse.StartQuestID`, `SpellEffect` (effect 150 and 16 through
  `EffectMiscValue_0`), `QuestObjective`, `QuestHub`, `QuestLabel`, `CollectableSourceQuestSparse`, `Vignette`,
  `TransmogSet.TrackingQuestID`, `LoreTextPublic` (through its condition). `QuestV2` itself has three columns.
- **`PlayerCondition` is the hub of availability.** `QuestLine`, `QuestPOIBlob`, `QuestV2CliTask`, `Campaign` (all six of
  its ID-looking columns), `CampaignXCondition`, `UiMap.VisibilityPlayerConditionID`, `Mount`, `MapDifficultyXCondition`,
  `AreaConditionalData` and `LoreTextPublic` point at it. It holds the quest, reputation, skill, level, race, class,
  covenant, achievement and spell requirements, and a `ModifierTree` for anything richer. 12,518 of our quests reach one.
- **`ModifierTree` and `Criteria`/`CriteriaTree`/`Achievement`** are the expression layer under conditions and
  achievements: 383 modifier types on retail (TrinityCore names 344; 39 more are undocumented), and criteria type 27 is
  "complete a quest" (11,690 quests named, 7,809 ours).
- **Maps:** `UiMap` (parent chain) -> `UiMapAssignment` (world box) -> `Map` / `AreaTable`; `QuestPOIBlob` carries a `UiMapID` that
  agrees with `UiMapAssignment` for 99.8% to 99.9% of 72,736 blobs; `UiMapGroup`/`UiMapGroupMember` give floors;
  `AreaPOI` data type 1 names a `JournalInstance`, type 3 a `UiMap`.
- **Reputation:** `Faction` (4 race-and-class slots, flags) -> `FriendshipReputation` -> `FriendshipRepReaction`;
  `Faction.RenownCurrencyID` -> `CurrencyTypes`; `Faction.ParagonFactionID` -> a shell faction -> `ParagonReputation`
  (the paragon cache quest); `Covenant` is the renown-track table (there is no `MajorFaction`).
- **Declared keys the data weakens:** `ItemSparse.StartQuestID` resolves for 1,458 of 1,755 values (83%);
  `ScenarioStep.RewardQuestID` for 44 of 259; `QuestDrivenScenario.QuestID` for 50 of 65. A quest missing from `QuestV2`
  is not a missing quest, since repeatables and tracking quests are left out of it (see below).

## Bitmasks that were opaque, now decoded

The full list is bits.csv. The ones that change what we can do (confidence in brackets):

- **`PlayerCondition` `*Logic` columns** [PROVEN]: bits 0-9 are five slot pairs (1 = AND, 2 = OR, 0 or 3 = ignore) and
  bits 16 and up invert slot 0, 1, 2... The repo's decoder already does this for previous quests. `Flags` bit 12
  (0x1000, `CheckAccountCombinedQuests`) means "completed on any character of the account": set on 962 conditions.
- **`QuestV2CliTask.Flags_0`** [PROVEN]: 0x400 tracking (never in the quest log), 0x1000 daily, 0x8000 weekly;
  **`Flags_1`**: 0x8000 display as daily, 0x80 account-level (198 rows), 0x20000 internal-build only (14 rows, 13 of them test titles);
  `Flags_0` 0x4000000 is on 100 of the 101 Calling Quest rows [LIKELY].
- **`QuestInfo.Modifiers`** [PROVEN for 0-2 and 9-11]: bit 0 Rare, 1 Elite, 2 Epic, 9 completion toast (not "bonus
  objective": Forever's Legendary type has it), 10 Important, 11 Meta. `Type` equals Blizzard's `QuestTagType` exactly.
- **`UiMap.Flags`** [PROVEN, Blizzard's own enum]: 22 bits, 0x200 is `DoNotTranslateBranches` (the schema comment and
  TrinityCore say "Deprecated"); `UiMap.System` 3 is Minimap (85 maps).
- **`ChrRaces`** [PROVEN]: `PlayableRaceBit` is a bit index (0-33, 22 unused), every client race mask is two int32
  words (bits 0-31, 32-63), proven by `SkillRaceClassInfo` (the Dwarf racial mask is Dwarf plus Dark Iron, the
  Common-language mask is exactly the 16 Alliance races). `NPCOnly` (flag bit 0) separates playable from non-playable
  races on all three games; the `0x400000` bit `Read-QuestCache.ps1` uses picks the same rows on Forever and Era but is
  set on 19 unrelated retail rows. Class bit = `1 << (ID - 1)`, ours, confirmed by Forever's `TalentTab.ClassMask`.
- **`Holidays.Flags`** [PROVEN, Blizzard enum]: bit 32 `DurationUseMinutes` (Era only today) and bit 128
  `StagesUseDatetimes` (in Forever's client enum) change how `Duration` and `Date` are read; no retail or Forever row
  sets them yet, so a row that does would break the date reader silently.
- **`ItemSparse.Flags`** [PROVEN]: `Flags_0` bit 27 account bound and `Flags_1` bit 17 BNet account trade are on the same
  14,344 items; `Flags_1` bits 0 and 1 are the faction bits (exactly one per item on all 19,522 items with an
  opposite-faction twin); `Flags_2` bit 0 (don't destroy on quest accept) is on 301 items, 231 of which start a quest.
  Forever's `Flags_1` is not retail's.
- **`BattlemasterList.Flags`** 0x80 epic battleground, 0x20 brawl (from TrinityCore, 0x80 confirmed on exactly the 5
  "Epic Battleground" rows). **`GossipNPCOption`** is an enum 0 to 67, not a bitmask, so the catalogue's bit counts for it
  mean nothing.
- **`Campaign`** is not flags at all: `Prerequisite`, `Stalled`, `Completed`, `OnlyStallIf`, `SortAsNormalQuest` and
  `UseMinimalHeader` are `PlayerCondition` IDs (the schema declares it; the values only looked like quest or theme IDs).
- **Not decoded:** `GroupFinderActivity.Flags`, `Hotfixes.Flags` bit 1, `ConditionalContentTuning`'s redirect modes (0 to 40),
  `WorldStateExpression`'s world states (they have no client table), `ContentTuningXLabel` and `CreatureLabel` label IDs,
  `QuestLabel` IDs (6036 is the Prey hunts, 2703 the dragonriding races, as before), and the node-graph tables.

## Your three examples, answered

- **`BreadCrumbID`:** 12 non-zero values, all on task quests; 3 are not quest IDs and the rest resolve by chance. No
  lead-in. Verdict NO. No table anywhere lists breadcrumbs, next quests or exclusive groups (all 1,104 retail headers
  were scanned); the closest client signal is the shared completion slot below.
- **`Campaign.SortAsNormalQuest`:** a `PlayerCondition` ID (see above); with the other five columns it forms the
  campaign's gating, which we read only through `Prerequisite`.
- **`QuestInfo.Modifiers`:** decoded above; the type itself, which we read, already carries most of it.

## Corrections to earlier documents

- client-tables-review.md says `BreadCrumbID` is set for 11 (12 now) and `QuestV2CliTask` has 6,242 rows (6,258 in
  12.1.5); its `PlayerCondition` count of 48,043 is the older build's (48,491); its "297 point at a ModifierTree,
  which no table decodes" is out of date (TrinityCore's enum decodes it; the dictionary is
  [B_conditions-modifiertree-types.csv](client-tables-audit/B_conditions-modifiertree-types.csv)).
- It says 28 floors of `UiMapGroupMember` are missing from the zone table; only the Stockade's is missing, deliberately
  (#206). `UiMapLink` is map geometry in TrinityCore, not just art. `AreaPOI` links to more than `QuestHub` (journal instances, maps).
- `ParagonReputation` quests are not all typed 128: 29 are, 26 are typed 2 and 4 are typed 4. `RenownRewards`: 3 of its 123
  quests are ours, all hidden (counts of rows and quests hold). `ItemSparse.RequiredSkill` is read
  (`Sync-QuestProfessions.ps1`). `QuestSort.Flags` and `UiOrderIndex` are read by no tool; the catalogue's mark for them
  comes from an unrelated "Flags" in `Build-ForeverMenu.ps1`; the same for `Contribution` and two scripts. Treat the
  catalogue's `ReadBy` as "mentioned in the same file": a false positive is possible, a miss is not.
- The earlier note that `QuestV2.UiQuestDetailsThemeID` was a new column: it duplicates `QuestXUIQuestDetailsTheme`
  (465 of 465 agree; that table has 11 more).
- Forever's `Flags` bits and `PlayableRaceBit` use: see above. Retail meanings must never be assumed on Forever or Era.

## Opportunities, most valuable first

Numbers are on retail (12.1.5.70391) and Forever (1.60.1.70374) as of 14 October 2026, measured against `data\quests.jsonl`
(35,544 quests), `data\forever\quests.jsonl` (5,097) and `data\pins.jsonl` (16,084). "In game" means a test the game alone can answer.

1. **Quests that share one completion slot** (`QuestV2.UniqueBitFlag`, both games). The index into the character's
   completed-quest bit vector; quests with the same value cannot both be completed, so they are alternatives or a
   quest and its replacement. (Re-checked: 30470 and 30471 share slot 13219; 2,687 groups hold 7,191 quests.) 549
   groups hold 2 or more of our quests that one character can meet: 1,882 quests, 4,556 pairs, of which only 78 are in
   `qcMutuallyExclusive`. Agreement with what we know: 46% of our 194 retail exclusive pairs and 84% (260 of 311) of
   Forever's CMaNGOS pairs share a slot; Forever has 43 groups and 283 pairs (120 known). Rotating dailies share slots
   too: only non-recurring types qualify. *In game:* complete 30470, then `IsQuestFlaggedCompleted(30471)`. This is the
   client's own answer to what TrinityCore's `exclusive group` gave for the old world only.
2. **Item-started quests** (`ItemSparse.StartQuestID`, both games). 1,790 retail items start 1,430 of our quests, and
   1,061 of them have no pin (11% of retail's unpinned quests); on Forever 555 items start 408 quests and none has a
   pin (29% of unpinned). The item also carries limits our quest rows lack: faction (162 quests, 4 wrong in our data:
   11002, 38202, 38194, 56071), skill (41 quests; 28 have no profession tag), reputation rank (14 and 3), race (3 and 2), and
   on Forever an item level above our minimum for 152 of 336 quests. 325 retail and 140 Forever start-item quests are not in our
   data at all (lists in the folder); many are removed or deprecated content, so each needs a look first.
   *In game:* the faction limit, whether the item's level blocks the start, the 0 to 7 reputation rank scale.
3. **Quests started by a spell** (`SpellEffect` effect 150, `EffectMiscValue_0` = quest; retail). (Re-checked: 1,177 rows,
   1,108 resolve; names confirm: "Launch Quest", "Start Quest: X".) 907 of our quests are started this way and 868 of those
   by a spell that is on no item; 429 have no pin: Meta quests 121, Azj-Kahet 36, Torghast 33. So "no giver" is by design
   for 4.4% of our unpinned quests, and a "Started by" line could say so. Forever: 82 start spells, 61 of their quests not
   in our data, 54 of them "Deputize: Ashenvale/Hinterlands/Feralas Mission I to XVIII" (81768 to 81874) where we hold
   only Duskwood's 18. *In game* before adding them.
4. **Conditions the tools decode in part** (`PlayerCondition`, `ModifierTree`, `Criteria`, both games where present).
   12,518 of our quests reach a condition. Of the 29 conditions on `QuestLine.PlayerConditionID` (1,240 of our quests),
   only 6 are fully readable by `QuestConditions.ps1`'s rules. For task quests the `ModifierTree` under the condition
   is never read: 1,624 have a positive "quest completed" leaf and 1,448 of those have no prerequisite in our data (some
   leaves are one branch of an OR). 329 quests sit behind an achievement (mostly the "WQ Unlock" family); 4,332 reach the
   game's own failure text ("Reach level 30 to continue your Order Hall campaign."); 155 quest-line quests have a condition
   level above our gate; 72 Forever Warsong Gulch and Arathi Basin quests get a maximum level from `PVPDifficulty`
   (data-sources-review decision 25). The ModifierTree and Criteria type dictionaries make all of it readable.
5. **Reputation rewards the viewer can't earn** (`Faction`, retail and Forever). Each faction has 4 slots of (race
   mask, class mask, base, max, flags); the first matching slot wins, and base = max < 0 is a side lock. 385 rows
   (231 quests) of `qcQuestReputation` sit on both-side quests whose faction only one side can earn, 40 more contradict
   the quest's own side (53148 against 53146, 50338 "The G-Team"), and Forever has 7 nobody can earn
   (`D_reputation-side-mismatch.csv`). `Compare-QuestReputation`'s "shown" rule reads `ReputationFlags_0` only and is
   wrong for 498 reward rows (4.2%): Warsong Offensive, Hellscream's Reach and Wintersaber Trainers (193 rows) count as
   hidden, and 305 rows of bar-less "Horde" and "Alliance" headers count as shown. Five Midnight renown factions (Amani
   Tribe 2696, Hara'ti 2704, Silvermoon Court 2710, The Singularity 2699, Zul'jarra's Forces 2772) and seven Dragonflight
   ones are missing from the hand renown table; the 96 rows we have all validate. Rank keying is decoded (renown = quantity
   of the faction's currency, friendship = position in `FriendshipRepReaction`, paragon via `ParagonFactionID`).
6. **Zone faction** (`AreaTable.FactionGroupMask`: 2 Alliance, 4 Horde, 6 both). Proven against 22,550 of our quests:
   mask-2 zones hold 345 Alliance-only and 11 Horde-only quests, mask-4 zones 344 Horde-only and 9 Alliance-only. Unused.
   54 retail and 109 Forever quests we call both-faction sit in faction zones (9177, 301, 746 among them). Under the
   rule "trust only API-asserted restrictions" these are review rows, not changes.
7. **Campaign gating** (`CampaignXCondition`, `Campaign`, `LoreTextPublic`; retail). 257 chapter gates across 71 campaigns
   and 5,349 quests, 165 with the game's "why stalled" text, 161 through `ModifierTree`. `LoreTextPublic` (the recap chapters)
   names the quest that reveals each chapter for 575 quests in 69 campaigns (569 in our data, 565 in `QuestLineXQuest`): a
   cross-check of campaign order; six of our quests have a chapter but no questline (60500, 69888, 64816, 46253, 54282,
   57185) and six are not in our data (57692, 51403, 88918, 93420, 95533, 72402).
8. **Dungeon and raid doors** (`JournalInstanceEntrance` 203 rows and `AreaPOI` type 1 for 208 of 216 instances; retail).
   With TrinityCore's row-selection order 190 of 203 doors resolve to a zone map and 187 land on the right zone (a naive
   smallest-box pick misplaces 4 of 14). Forever has no Journal tables, but `Map.CorpseMapID` and its corpse position give the
   door for 26 of 50 dungeon and raid maps (83 of 100 within 100 yd of retail's, median 9.5 yd). 444 of 476 unpinned
   retail quests in instance categories have a door (132 of 142 on Forever). Whether a door pin is right is the user's
   call: those quests have no pickup data.
9. **Race and class masks** (both games). Our race bits match Blizzard's for bits 0 to 10 (Human to Draenei) and
   differ from bit 11; five races are faction-split in Blizzard's masks (Pandaren, Dracthyr, Earthen, Haranir,
   Skyborne) and merged into one bit in ours. Keeping our own 32-bit order is a standing decision and nothing here
   changes it; the new facts are the playable-race flag (`NPCOnly`, which would replace `0x400000`) and Forever's
   rows (10 playable, Skyborne 95 and 96).
10. **Levels** (both games). The API minimum equals `MinLevelSquish` plus the scaling offset base for 29,134 of 29,134
    quests (the maximum for 29,131); `AllowedMinOffset` is not in it (0 of 2,522), which is the formula behind
    open-items decision 9 (minimum or maximum), and not a decision. `ConditionalContentTuning` redirects 28,348 of 33,123 cached quests to another tuning with a different
    minimum in 27,446 cases; its modes are unknown, so *in game* before reading it. Forever's `GroupFinderActivity` has
    suggested ranges for 41 zones ("Quests and Zones", e.g. Elwynn 1-14), joinable by zone name only; we hold no zone ranges.
11. **The sweep's new-data watch** (retail). `Hotfixes` lists the server's post-build patches by table (QuestV2 10, QuestPOIBlob 18,
    Holidays 12, PlayerCondition 60); five hotfixed quests exist in `QuestV2` and not in our data (98831, 98834, 98836, 99306,
    99585). Two holiday-linked quests (43471, 52991) and two Midnight paragon quests (93798, 95391) are in the client but not
    ours; Forever's class mounts gated by quests include 94971 and 97185. "A Greedy Emissary" ran in July 2025 and our
    91283 and 91392 look event-only and untagged.
12. **Smaller:** `QuestV2` is not a roster: 1,301 of our retail quests (3.7%) and 568 of Forever's 5,097 (11%, real Vanilla
    quests such as Alterac Valley and the Ahn'Qiraj war effort) are absent; 81 repeatable-typed quests are in it and 66
    one-time quests are not (review candidates). `UiMap.VisibilityPlayerConditionID` gates 36 maps (21 carry 1,003 of our pins; *in
    game*). 1,600 of our 41,683 start or own blobs (3.8%) are on 108 UiMaps missing from `qcAreaIDToCategoryID` (1,165 reach
    a mapped map through the parent chain). `UiQuestDetailsTheme` groups ~450 quests by profession and covenant, a cross-check. Any reader of
    `QuestPOIBlob` must skip blobs whose `QuestID` is 0: `ResearchSite`'s 453 dig sites resolve there. The 59 paragon cache
    quests have no giver and no pin by design. 11 pins of the 2,070 `CollectableSourceQuestSparse` quests have no NPC ID.
    `Creature` names only 10% of our pin NPCs on retail (all agree) and none on Forever.

## What no table gives

A quest giver (nothing beyond `CollectableSourceQuestSparse`), an NPC's position, a next quest, a breadcrumb, an exclusive group
other than the shared slot, `WorldStateExpression`'s world states (no table), and a link from a recipe, mount, toy or pet to its quest
(only free text in `SourceText`). These stay with TrinityCore, CMaNGOS, the recorder and the probe.

## Decisions waiting for the user

1. **Take items 1 to 6 as work?** Each would be its own pull request (a sweep step, a tool and a table check), shown
   first, in the order above; items 1, 2 and 5 touch what the player sees.
2. **Door pins (item 8):** give instance quests with no pickup data the dungeon door, or leave them pinless?
3. **Item-started quests (item 2):** "Starts from" is decided (open-items row 19); should the item's limits join the quest rows?
4. **Keep `Audit-ClientTables.ps1` in the sweep** (baseline compare each sweep: new tables, new columns, new set bits,
   foreign keys whose resolve rate drops), per "check everything every sweep"?

## In game, in a few lines

- Completed slot: complete 30470, then `/run print(C_QuestLog.IsQuestFlaggedCompleted(30471))` (item 1).
- An item-started quest with a faction or level limit: does the game refuse or hide it for the wrong side (item 2, 4 quests named above)?
- `UiMap` visibility conditions: one character that sees Teldrassil's old and new maps (item 12).
- `ConditionalContentTuning`: does `C_QuestLog.GetQuestDifficultyLevel` follow its redirect (item 10)?

## Status

- 2026-10-14: audit done for retail 12.1.5.70391, Forever 1.60.1.70374 and Era 1.15.9.70003. Nothing in the data or the addon
  changed; this pull request adds the tool, its test, this document and the folder.
- The catalogue is the baseline: a later run compares itself with it. Run `Audit-ClientTables.ps1 -Download` per game, then
  diff `fks`, `refs` and `tables`. `Test-AuditClientTables.ps1` tests the tool on a made-up client (25 checks).
- 2026-10-16: before this pull request, Forever's beta moved to 1.60.1.70425, so its catalogue files are on that build
  (retail 70391 and Era 70003 were still the newest). The researchers' Forever counts above are on 70374; the build
  changed no table's columns, but it added 4 tables (`CatalogShopGameTitleInfo`, `Particulate`, `ParticulateSound`,
  `UIExpansionDisplayInfoIcon`: none about quests) and rows to the quest tables: `QuestV2` 6,610 to 6,614 (99582, 99600,
  99602 and 99670, none in our Forever data), `QuestPOIBlob` 54 to 57, `QuestPOIPoint` 99 to 121, `PlayerCondition` 1,901 to
  1,943, `ModifierTree` 2,824 to 2,845, `Criteria` 3,279 to 3,297, `Achievement` 436 to 441, `Map` 71 to 73 (two Skycuter
  maps, Dalaran and Mulgore), `WorldStateExpression` +6. Forever's probe results and quest cache are still on 70374, so the
  next Forever sweep (step 10) starts with a rerun on 70425.
- 2026-10-16: the user went through the opportunities one at a time. **Opportunity 1 is done** in #377, as sweep step 2k
  (maintenance.md). The in-game test wasn't needed: the saved completions of the user's characters showed the game
  reporting every one of 780 retail and 16 Forever shared-switch groups whole, none in part. So the game already ticks
  partners itself, and the links' worth is the "only one of these" warning before a player chooses. Counted per pair,
  with the filters the step uses (different names, not recurring, one character could be offered both), retail had
  650 unlinked pairs, not the 4,556 estimated above: 145 were added and 502 skipped, and the Gilneas trio waits for the
  user; Forever had none. The probe now saves each character's completed list, which a sweep needs to prove one of
  our links wrong. Four findings it turned up are in open-items.md. Opportunities 2 on are next.
