# Cluster B_conditions: the client's "who may see or do this" machinery

Researcher output for the client-table audit. Retail = 12.1.5.70391, Forever = 1.60.1.70374, Era = 1.15.9.70003. Scratch scripts and raw results are in `work\B_conditions\`. Supplementary files in this folder: `B_conditions-modifiertree-types.csv` (every ModifierTree type 0..446 with name, row counts per game, what TrinityCore says Asset/SecondaryAsset/TertiaryAsset hold), `B_conditions-criteria-types.csv` (every Criteria type), plus the three required files `B_conditions-verdicts.csv`, `-columns.csv`, `-bits.csv`.

Evidence tags used throughout: (a) Blizzard's own source, (b) TrinityCore code (fetched from GitHub master: `ConditionMgr.cpp` `IsPlayerMeetingCondition`, `CriteriaHandler.cpp` `ModifierSatisfied`, `DB2Stores.cpp` `GetContentTuningData`, `DBCEnums.h`), (c) wowdev wiki (the ModifierTree page had no content), (d) empirical count, (e) agreement with our data. Confidence PROVEN / LIKELY / GUESS as the brief defines.

## 1. Summary

1. **PlayerCondition is fully decodable, and the repo reads about 8 of its 160 columns.** The evaluation order, the meaning of every `*Logic` field, every set bit of `Flags` and which columns are populated per game are below. The logic rule (PROVEN, TrinityCore `PlayerConditionLogic` and our rows): result slot i is the test for entry i; bits 16+i invert slot i; each two-bit pair (bits 2(i-1)..) says how slot i joins the answer so far (1 AND, 2 OR, 0 or 3 = the entry is ignored). `QuestConditions.ps1` and `Sync-QuestPrerequisites.ps1` implement this correctly for `PrevQuestID`.
2. **ModifierTree is a decodable expression tree.** Operator 2 = leaf that must be true, 3 = leaf that must be false, 4 = all children, 8 = at least `Amount` children (PROVEN: TrinityCore `ModifierTreeSatisfied`; counts in section 5). `Type` is TrinityCore's `ModifierTreeType` enum; retail uses 383 distinct types; TrinityCore's enum names 344 of them, and 39 types (1,785 rows, among them 395 and 396 which hold quest IDs) are not in TrinityCore master and are listed as undocumented. The tool decodes 3 of those types (110, 2, 289).
3. **The gap, measured on our 35,544 quests.** 12,518 of our quests reach at least one PlayerCondition through `QuestPOIBlob`, `QuestV2CliTask`, `QuestLine`, `Campaign`, `CampaignXCondition`. Of the conditions behind `QuestLine.PlayerConditionID` (29 conditions, 1,240 of our quests) only 6 are fully readable with the tool's rules and 1,146 of the quests carry something the tool reads as "met" (world state, completed-or-on-quest, content-tuning level, aura, achievement). For task quests (`QuestV2CliTask.ConditionID`, 5,056 of ours) the tool reads the condition's `PrevQuestID` only and never its ModifierTree: 1,624 task quests have a positive "completed quest" leaf in that tree, 1,448 of them with no prerequisite in our data (caveat: a leaf may be one branch of an OR).
4. **Four things the client holds that the addon lacks.** (i) Achievement gates: 329 of our quests sit behind an achievement (e.g. "8.0 WQ Unlock - Horde/Alliance" 147 each, "7.0 WQ Unlock" 66, "Argus - Block 1 Unlock" 40). (ii) Blizzard's own "why not" text: 4,332 of our quests reach a condition with `Failure_description_lang` or `CampaignXCondition.FailureReason_lang` ("Reach level 30 to continue your Order Hall campaign."). (iii) Content-tuning level conditions: 155 quests on quest-line conditions need a higher level than our gate. (iv) Forever's battleground brackets from `PVPDifficulty` (72 Warsong Gulch / Arathi Basin quests get a maximum level; decision 25 of data-sources-review).
5. **Contradiction with the earlier review (client-tables-review.md) and with refs.csv.** `ModifierTree.TertiaryAsset` does NOT hold quest IDs: 3,588 of its 3,791 non-zero values are below 1,000 (levels, counts, amounts) and the "358 quests" of refs.csv are chance hits on QuestV2's low IDs (310 distinct values below 1,000). The earlier review's "297 point at a ModifierTree, which no table decodes" is out of date: TrinityCore's enum decodes it (section 5). Its row counts (48,043 conditions) are for an older build; 12.1.5 has 48,491.

## 2. Verdict table

| Table | Games (retail / Forever / Era rows) | Verdict | One line |
|---|---|---|---|
| PlayerCondition | 48,491 / 1,901 / 481 | USE | The game's own "may this character" record; same 162 columns in retail and Forever (Era has MovementFlags split in two). |
| ModifierTree | 317,468 / 2,824 / 1,189 | USE | Expression tree under PlayerCondition and Criteria; 3 of 383 types decoded today. |
| Criteria | 66,663 / 3,279 / 215 | USE (small) | Type 27 = complete quest (14,201 criteria, 7,809 of our quests): "this quest is real" signal, already used by Find-UnavailableQuestCandidates. |
| CriteriaTree | 121,817 / 6,742 / 360 | USE (small) | Joins Criteria to Achievement; Operator/Flags decoded. |
| CriteriaTreeXEffect | 6,783 / - / - | NO | Criteria tree to WorldEffect (visual effect). |
| Achievement | 14,136 / 436 / 34 | CHECK | Gates 329 of our quests through PlayerCondition/ModifierTree; Forever's 436 gate nothing. |
| Achievement_Category | 243 / 56 / 13 | NO | Names already read by Build-CategoryClientNames.ps1. |
| ContentTuning | 2,950 / 100 / 4 | USE | Level-range formula verified at 100.0% (29,134 quests); already used (QuestLevels.ps1). |
| ContentTuningXDifficulty | 980 / - / - | NO | Dungeon-difficulty tuning; no quest link. |
| ContentTuningXExpected | 1,147 / 29 / - | NO | Combat stat scaling (ExpectedStatMod, Mythic+ seasons). |
| ContentTuningXLabel | 199 / - / - | CANT-DECODE | Six label IDs (1742-1747) with no name table; 195 tunings. |
| ConditionalContentTuning | 2,564 / - / - | CHECK | Redirects a tuning per player mode; meaning of RedirectEnum unknown; the game's API applies it. |
| GlobalGameContentTuning | 11 / - / - | NO | Default tuning per expansion. |
| ContentRestrictionRule | 42 / - / - | NO | Map/area/achievement restriction rules (PvP, solo shuffle, mage tower); no quests. |
| ContentRestrictionRuleSet | 13 / - / - | NO | AND/OR combiner of the rules. |
| WorldStateExpression | 42,808 / 3,971 / 3,314 | CANT-DECODE usefully | Bytecode decoded fully (0 parse errors) but it compares world states that no client table names. |
| LFGDungeons | 1,906 / 71 / 67 | NO | Dungeon-finder entries; not quest data. |
| LFGDungeonGroup, LfgDungeonsGroupingMap, LFGRoleRequirement | 68 / 6 / 21 | NO | Dungeon-finder grouping. |
| Difficulty | 60 / 22 / 18 | NO | Instance difficulty names; only decodes ModifierTree types 20 and 68. |
| Phase, PhaseXPhaseGroup | 26,575 / 105 / 54; 2,462 / 7 / 3 | NO | Phasing; only 13 of our quests touch a phase condition. |
| PhaseShiftZoneSounds, WorldStateZoneSounds | 461 / -; 1,499 / 42 / 12 | NO | Zone music per phase or world state. |
| PVPDifficulty | 354 / 25 / 14 | USE | Battleground level brackets per map; Forever has the Classic ones (WSG 489, AB 529, AV 30). |
| UnitCondition | 8,147 / 356 / 282 | NO | Unit (creature) combat conditions. |
| ConditionalChrModel | 31 / 5 / - | NO | Character model variants by condition. |
| WorldStateUI | - / - / 13 | NO | Era only, UI for world states. |

## 3. PlayerCondition

### 3.1 How the game evaluates one (TrinityCore `ConditionMgr::IsPlayerMeetingCondition`, PROVEN against our rows)

A condition fails if any enabled test fails; tests run in this order: Flags Disabled (passes at once) / IsAtMaxExpansionLevel; ContentTuning level; RaceMask; ClassMask; Gender; NativeGender; Power; spec; skills; language; reputation; PvP faction; PvP medal; movement; weapon; group status; PrevQuest; CurrQuest; CurrentCompletedQuest; Spell; Item; Currency; Explored; Aura; Time; WorldStateExpression; Weather; Achievement; Lfg; Area; expansion; phase; QuestKill; item levels; ModifierTree; Covenant; TraitNodeEntry. Finally `Flags & 0x8 (Invert)` negates the whole result (never set in retail or Forever).

**The `*Logic` fields** (SkillLogic, ReputationLogic, PrevQuestLogic, CurrQuestLogic, CurrentCompletedQuestLogic, SpellLogic, ItemLogic, AuraSpellLogic, AchievementLogic, AreaLogic, LfgLogic, CurrencyLogic, QuestKillLogic, TraitNodeEntryLogic): slot i (0..3, or 0..5 for QuestKill, 0..3 for reputation = three minimums plus the maximum) is true when entry i is met, and an empty entry (0) counts as met. `results ^= (logic >> 16)` inverts slots; then `for i >= 1: (logic >> 2(i-1)) & 3` is 1 = AND slot i, 2 = OR slot i, 0 or 3 = slot i ignored; the first slot always starts the answer. Examples from our rows: 65536 = not #0 ("has NOT done quest"); 1 = #0 and #1; 2 = #0 or #1; 5 = #0 and #1 and #2; 10 = #0 or #1 or #2; 131073 = #0 and not #1; 196609 = not #0 and not #1; 458757 = none of three; 983082 = all four inverted and OR-ed. A Logic of 0 with a second ID set ignores the second ID: 85 PrevQuest conditions, 58 CurrQuest, 54 CurrentCompleted do that in retail (2 in Forever), and the repo's reader skips them the same way. **5,293 of the 9,337 conditions with a PrevQuest carry a negated slot** ("quest must not be done"); the repo already treats those as no prerequisite.

**Skills:** slot true when `skill value > MinSkill && < MaxSkill` (strict), so MinSkill 1 means "has the skill"; MaxSkill 10000 is the usual open end (12 of 17 rows).

**ReputationLogic:** the four slots are MinFactionID_0..2 (rank at least MinReputation_i) and slot 3 = MaxFactionID (rank at most MaxReputation). Ranks follow TrinityCore's `ReputationRank`: 0 Hated .. 7 Exalted (the value 8 occurs in a handful of min slots, unexplained).

### 3.2 Flags (bits.csv has one row per decoded bit)

Retail counts from the catalogue; "x/y" are tests I ran (awk over the CSV) of how often the bit sits on rows that populate the column TrinityCore says it modifies.

| Bit | TrinityCore name | Rows | Evidence | Confidence |
|---|---|---|---|---|
| 0x1 | ClientExecutable | 45,124 | set on 93%; the 3,721 rows without it include no pattern I could name | LIKELY (name only) |
| 0x2 | CheckAchievementsOnAllChars | 818 | 558 of 812 rows have an Achievement set, against 2.3% of all rows | PROVEN |
| 0x4 | ComparePowerToMax | 1 | the one row has PowerType set | LIKELY |
| 0x8 | Invert | 0 | never set in any game | unverifiable |
| 0x10 | IsAtMaxExpansionLevel | 14 | 12 of 14 have quest columns, all 14 a world state expression | LIKELY |
| 0x20 | WithinOrAboveRecord (ignore the tuning's maximum) | 17,704 | 2,415 of the 2,789 conditions with a ContentTuningID have it (87%) | LIKELY |
| 0x40 | UseEffectiveLevel | 174 | 173 of 174 have a ContentTuningID | PROVEN |
| 0x80 | InvertContentTuning | 12 | 12 of 12 have a ContentTuningID | PROVEN |
| 0x100 | Disabled | 9 | 5 of 9 have a ModifierTree; the rest are empty | LIKELY |
| 0x200 | InvertModifierTree | 937 | 920 of 937 have a ModifierTreeID | PROVEN |
| 0x400 | NotRecentlyTransferred | 0 | no rows | unverifiable |
| 0x800 | IncludeLevelDelta | 30 | 28 of 30 have a ContentTuningID | PROVEN |
| 0x1000 | CheckAccountCombinedQuests (account-wide quest completion; TrinityCore marks it NYI) | 962 | 951 of 954 rows have PrevQuest/CurrQuest/CurrentCompleted IDs | PROVEN |

Forever uses only 0x1 (1,828 of 1,901), 0x20 (13) and 0x200 (13). **0x1000 matters for the addon**: 962 retail conditions count quests completed on any character of the account. The addon's per-character `qcCharacterCompletions` does not model that; the game itself says an account-wide quest is done on every character (open-items.md, 12 October).

### 3.3 Columns, group by group (columns.csv has one row per column)

Population = rows non-default of 48,491 retail / 1,901 Forever / 481 Era. "Used" = read by a repo tool (grep of `tools\`, which corrects ReadBy: `Time_0/1` is a false positive).

- **Identity:** `ID`; `Failure_description_lang` (7,390 retail, 97 Forever, 2 Era: the text the game shows when the condition fails: "Requires Rogue", "Classes: Hunter, Shaman", "Granted at Renown 48 with your covenant", and for campaigns see 3.5). Not used. Localized by the client, so it gives the addon player text in every language for free.
- **Level:** `MinLevel`/`MaxLevel` are 0 in all 48,491 retail rows (and in Era) and non-zero in 21 / 16 Forever rows: retail moved the level test to `ContentTuningID` (3,162 rows; Forever 20). The tuning's range is used with Flags 0x20/0x40/0x80/0x800 (3.2). Not used.
- **Race / class / gender / spec:** `ClassMask` (1,657 rows; bit = 1 << (ClassID - 1), PROVEN by `Player::GetClassMask` and the repo's own "class bits match Blizzard"), `RaceMasks_0/_1` (1,818 / 989 rows; a 64-bit mask over two int32 indexed by ChrRaces.PlayableRaceBit, as `Get-WagoQuestRequirements.ps1` converts it and as TrinityCore's `RaceMask<int32,2>` does; LIKELY), `Gender` (-1 any, 0 male 221 rows, 1 female 206), `NativeGender` (18 + 18 rows), `ChrSpecializationIndex` (OrderIndex of the player's primary spec: 0..3; 2 = 122 rows) and `ChrSpecializationRole` (0 tank, 1 healer, 2 damage per ChrSpecialization.Role; 16 rows). Used: ClassMask and RaceMasks for quest-giver POIs only. Forever: ClassMask 337 rows, RaceMasks 408.
- **Quest columns:** `PrevQuestID_0..3` + `PrevQuestLogic` = completed (9,279 conditions; Forever 154; used for task quests, quest lines and campaigns); `CurrQuestID_0..3` + `CurrQuestLogic` = quest is in the log (3,292; Forever 60; **not used**); `CurrentCompletedQuestID_0..3` + logic = quest status Complete, i.e. ready to turn in (921; Forever 22; **not used**); `QuestKillID` + `QuestKillMonster_0..5` + `QuestKillLogic` = the player's progress on that quest's kill objectives (133; not used). Of the three groups, only PrevQuest is read, so "in the log" gates (102 of our quests through POI blobs, 101 through task quests) and "ready to turn in" gates (46 POI-blob quests) are not modelled.
- **Skill:** `SkillID_0..3`, `MinSkill_0..3`, `MaxSkill_0..3`, `SkillLogic` (592 conditions; Forever 62). Only 2 of our quests reach one directly (Riding, Fishing); the 524 task quests with `QuestV2CliTask.FiltMinSkillID` already give the profession (not my cluster).
- **Reputation:** `MinFactionID_0..2` + `MinReputation_0..2` + `MaxFactionID`/`MaxReputation` + `ReputationLogic` (411 conditions; Forever 85). 128 of our quests reach one, mostly BfA war-front standing ("Dominance Offensive" 44, "Operation: Shieldwall" 43). Not used.
- **Spells, items, auras, currencies, areas:** `SpellID_0..3`+`SpellLogic` (player knows spell; 730; Forever 1,002 because Forever's conditions are mostly spell/item/skill tests), `ItemID_0..3`/`ItemCount_0..3`/`ItemFlags`/`ItemLogic` (1,720; ItemFlags 1 = include bank, 2 = ignore inventory; values seen 1 (1,107 rows), 2 (26), 5 (8, bit 4 is not read by TrinityCore)), `AuraSpellID_0..3`/`AuraStacks_0..3`/`AuraSpellLogic` (6,454; aura present, or at least N stacks), `CurrencyID_0..3`/`CurrencyCount_0..3`/`CurrencyLogic` (1,010; at least count), `Explored_0/1` (6; AreaTable explored), `AreaID_0..3`/`AreaLogic` (1,651; player in area or its sub-area). None used. Aura and area dominate quest-reachable conditions (the POI-blob conditions: Area 471 quests, Aura 327): they control which map blob shows in which place, not whether a quest is offered.
- **Expansion:** `MinExpansionLevel`/`MaxExpansionLevel` (account's expansion; -1 = no test; retail 48,490 / 48,491 rows are non-default only by the -1 convention, real values on 183 / 205 rows; 9 and 11 dominate); `MinExpansionTier`/`MaxExpansionTier` are -1 in every row of every game (unused column). 2,145 of our quests sit behind a campaign condition with an expansion test.
- **Time and world:** `Time_0/1` (7 rows; packed date range), `WorldStateExpressionID` (7,124 conditions, see section 8), `WeatherID` (1 row), `PhaseUseFlags`/`PhaseID`/`PhaseGroupID` (PhaseGroupID is 0 everywhere; PhaseID 160 rows), `PartyStatus` (79 rows; value v means GroupStatus v-1: 1 not in group, 2 in group, 3 in group but not raid, 4 in raid, 5 not in group or not in raid), `LfgStatus/Compare/Value_0..3` + `LfgLogic` (2 rows; status 1 = in LFG dungeon; compare 1..6 = ==, !=, >, >=, <, <=).
- **Item level and gear:** `MinAvgItemLevel`/`MaxAvgItemLevel`/`MinAvgEquippedItemLevel`/`MaxAvgEquippedItemLevel` (120/95/5/3 rows), `WeaponSubclassMask` (41; bit = 1 << main-hand subclass), `PowerType`/`PowerTypeComp`/`PowerTypeValue` (10 rows), `MovementFlags` (21; Era splits it in two columns).
- **Unused in every row of every game (a reliable "dead column" list):** `PvpMedal`, `LanguageID`/`MinLanguage`/`MaxLanguage`, `LifetimeMaxPVPRank`, `MinPVPRank`/`MaxPVPRank`, `MinGuildLevel`/`MaxGuildLevel`, `MinExpansionTier`/`MaxExpansionTier`, `PhaseGroupID`, `MaxSkill_1..3`, `Explored_1`, `LfgStatus_1..3`, `QuestKillMonster_5`, `TraitNodeEntryID_2/3`, `MinLevel`/`MaxLevel` (retail).
- **Others:** `CurrentPvpFaction` (52 rows; TrinityCore compares `value-1` to the player's team, so 1 = Horde, 2 = Alliance; LIKELY), `CovenantID` (369 rows; player's covenant; Forever 0), `Achievement_0..3`/`AchievementLogic` (1,638; Forever 3), `TraitNodeEntryID_0..3` + min/max rank + logic (10 rows).

### 3.4 Which game fills what

Retail and Forever share one 162-column layout. Forever's 1,901 rows are almost all Classic-style tests (ClassMask 337, RaceMasks 408, spell/skill/item/faction/area) and the 154 PrevQuest / 60 CurrQuest / 22 CurrentCompleted rows are only reachable through the tables that do reference PlayerCondition in Forever (AreaPOI, Mount, GlobalPlayerCondition, WorldEffect, SpellXSpellVisual, UiWidget, CooldownSet...), **and no Forever quest table references PlayerCondition**: Forever's `QuestLine` has 3 rows with PlayerConditionID 0, `QuestPOIBlob` has 54 rows with PlayerConditionID 0, and `Campaign`, `QuestV2CliTask`, `CampaignXCondition` do not exist. So Forever gets nothing from PlayerCondition about quest availability (its prerequisites stay CMaNGOS-derived). Era: 481 rows, same idea.

### 3.5 Relationships (verified against the data)

Declared foreign keys all confirmed (fks.csv): ModifierTreeID -> ModifierTree 100%, ContentTuningID -> ContentTuning 100%, PrevQuestID_* -> QuestV2 99.9-100%, Achievement_* -> Achievement 98-100%, SkillID -> SkillLine 98.6%, MinFactionID -> Faction 100%, CovenantID -> Covenant, WorldStateExpressionID -> WorldStateExpression, PhaseID -> Phase. Undeclared: `Achievement_3` also resolves to AreaTable 83% (chance, ignore). **How to join a PlayerCondition to a quest** (retail), measured on our quests:

| Source | Our quests | Distinct conditions | What it controls |
|---|---|---|---|
| `QuestV2CliTask.ConditionID` | 5,056 | 1,052 (78 ids missing from the table) | whether a task quest (world quest, bonus objective, calling...) is offered |
| `QuestLine.PlayerConditionID` (via QuestLineXQuest) | 1,240 | 29 | whether a quest line shows |
| `QuestLine.CompletionPlayerConditionID` | 1,306 | 72 (11 missing from the table) | when a line counts as complete (61 fully readable by the tool's rules) |
| `Campaign.Prerequisite` (via CampaignXQuestLine) | 6,066 | 86 | whether a campaign opens |
| `Campaign.Stalled` / `Completed` / `SortAsNormalQuest` / `UseMinimalHeader` | 6,052 / 5,333 / 1,334 / 3,381 | 85 / 68 / 5 / 8 | campaign display states |
| `CampaignXCondition.PlayerConditionID` | 5,273 | 170 | a chapter's own gates, with player text (3.3) |
| `QuestPOIBlob.PlayerConditionID` | 1,899 | 1,992 | which map blob shows for which character state (areas, auras, "on the quest"), plus race/class variants |
| `QuestPOIBlob.NavigationPlayerConditionID` | 58 | 79 | navigation arrow visibility |

All together 12,518 of our quests reach a condition. Campaign and CampaignXCondition conditions apply to the chapter, so counting every quest of the campaign overstates the number actually gated.

### 3.6 The gap between `QuestConditions.ps1` and the data

What the tools decode: PlayerCondition `PrevQuestID_*` + `PrevQuestLogic` and `ModifierTreeID`; ModifierTree types 110 (completed quest), 2 (nested condition) and 289 (read as off), operators 4 and 8-with-Amount-1; negated leaves read as met; only for the current expansion's quest lines and campaigns; for task quests the condition's PrevQuest only; ClassMask/RaceMasks for giver POIs. What the quests' conditions carry that is read as "met" (our quests, "extras" in `a4_out.txt`):

| Source | Our quests | Fully readable conditions | Quests with an unread part | Largest unread parts (quests) |
|---|---|---|---|---|
| QuestLine.PlayerConditionID | 1,240 | 6 of 29 | 1,146 | world state expression (284), completed-or-on-quest type 271 (382), tuning level (187), aura 8 (150), achievement 86 (145), on-quest 84 (98), between-quests 369 (94), completed-questline 241 (84), expansion 92 (50) |
| Campaign.Prerequisite | 6,066 | 0 of 86 | 6,061 | Chromie Time 300 (3,571), aura (3,626), expansion test (2,145), tuning level (1,975), race masks (1,620), Chromie/expansion maps |
| CliTask.ConditionID | 5,056 | 57 of 1,052 | 4,693 | world state expression (1,627), aura (1,165), area 17 (871), tuning level (492 + 803 via type 272), on-quest 84 (511), covenant (116), achievement (224), in-log (101) |
| CampaignXCondition | 5,273 | 28 of 170 | 5,072 | tuning level (2,542), world state 67 (1,509), completed questline 241 (1,259), covenant (465), currency (55) |
| POIBlob.PlayerConditionID | 1,899 | 105 of 1,992 | 1,702 | area (471), aura (327), on-quest 84 (260), objective 112 (180) |

Concrete additions the data supports (for decisions, not built):

- **Quest-typed ModifierTree leaves**: the tree holds 16,381 distinct quest IDs across types 110 (11,359), 84 (9,193), 111 (4,115), 174 "can accept" (3,370), 271 (2,596), 382 "completed on account" (516), 392 (455), 395/396 (undocumented, quest IDs); 12,167 of our quests appear in at least one. Task quests: 1,624 have a positive type-110 leaf in their condition, 1,448 of them without a prerequisite in `quests.jsonl`; 1,735 have a positive "completed-style" leaf (110, 111, 174, 271, 369, 382, 392, 241) and 1,537 no prerequisite. These are candidates only (OR groups).
- **Level**: for quests on `QuestLine.PlayerConditionID` the condition's ContentTuning level exceeds our gate (`minLevel`, else `level`) for 155 of 187 (e.g. 58184 "Antiquated Methodology" needs 50, ours 10); on `CampaignXCondition` 1,749 of 2,542 (e.g. 32391 "The Ruins of Korune" 30 vs our 15); on task quests 19 of 479. **Caution:** these conditions are often one branch of an OR (Chromie Time, 300/301), so apply only after evaluating the tree, then confirm in game with a character at low level.
- **Achievement gates**: 329 of our quests; top: 12608 / 12609 "8.0 WQ Unlock" (147 each, Alliance/Horde), 11473 "7.0 WQ Unlock" (66), 12082 "Argus - Block 1 Unlock" (40), 6570 "All Growns Up!" (20), 16326 account campaign complete (18). The addon can ask the game (`GetAchievementInfo`) whether the character has it. Most are world quests, hidden by default.
- **Covenant**: 592 quests are covenant-gated by the client; 556 of them carry `covenant` in our data (we hold 777 in total), so 36 are missing and 221 of ours have no client confirmation. Check the 36.
- **Race/class**: 1,849 quests reach a race or class mask; 1,342 of them already have a narrower race or class than "all" in `quests.jsonl`; 507 do not (GUESS: many are allied-race display gates, not offers; needs the per-quest look the existing audits do for giver POIs only).
- **Failure text**: 4,332 of our quests (4,057 via CampaignXCondition, 465 via Campaign.Stalled, 230 task quests, 50 POI blobs). `CampaignXCondition.FailureReason_lang` has 165 non-empty rows (91 distinct), e.g. "Reach level 30 to continue your Order Hall campaign." (12 rows), "Complete the quest ""Champions of Legionfall"" in Broken Shore to continue the campaign." (12).

## 4. ContentTuning and friends

Retail and Forever share the 19-column layout (`Flags`, `ExpansionID`, 4 scaling curve IDs, 2 primary-stat scaling columns, `MinLevelSquish`, `MaxLevelSquish`, `MinLevelScalingOffset`, `MaxLevelScalingOffset`, `AllowedMinOffset`, `AllowedMaxOffset`, `LfgMinLevel`, `LfgMaxLevel`, `ILevel`, `XpMultQuest`). The column positions equal TrinityCore's struct (MinLevel, MaxLevel, MinLevelType, MaxLevelType, TargetLevelDelta, TargetLevelMaxDelta, TargetLevelMin, TargetLevelMax, MinItemLevel, QuestXpMultiplier), which is how the names map. Era has 4 rows and 14 columns.

**The level formula (PROVEN).** I tested 29,134 quests that have both an API record (`tools\quest_api_cache`, `min_character_level` / `max_character_level`) and a tuning in the repo's retail quest cache against the 12.1.5 table:

- `API min = MinLevelSquish + base(MinLevelScalingOffset)`: **29,134 of 29,134 (100.0%)**; offset 0 adds 0 (28,904 quests), 1 adds 1 (219), 2 adds the expansion maximum level 90 (7), 3 the previous expansion's maximum 80 (4). TrinityCore's `ContentTuningCalcType` names these None, MinLevel(+1), MaxLevel (current expansion cap), PrevExpansionMaxLevel.
- `API max = MaxLevelSquish + base(MaxLevelScalingOffset)`: **29,131 of 29,134 (100.0%)** (the three misses are in the tuning table's newer build vs the API's older one).
- `AllowedMinOffset` (-1, -2, -4 on 311 tunings; 2,522 tested quests) is NOT in the API's minimum: adding it matches 0 of 2,522, and 91.3% overall. TrinityCore's `GetQuestMinLevel` uses `MinLevelWithDelta = MinLevel + TargetLevelDelta`, so the server-side accept check may use the lowered value; **which one the client enforces is open** (see section 9). The repo's choice (API minimum) is therefore the displayed value; it agrees with `docs\plans\retail-quest-cache.md`.
- The tuning's max is a scaling ceiling, not an offer limit: TrinityCore's `GetQuestLevel` returns `min(playerLevel, maxLevel)`. A quest is never hidden for being too high a level. `AllowedMaxOffset` 255 (127 tunings) means no cap; other values 10 and 1 (once each) are small adjustments (GUESS; DBD comment "add to effective MaxLevelSquish to get LfgMaxLevel").
- The other-faction rule: a tuning flagged Horde (0x8) or Alliance (0x10) gives the opposite-faction player the maximum instead of the minimum (TrinityCore). It applies to 6 + 2 tunings and to **0** quests in the cache, so it affects no quest.

Flags (bits.csv): 0x2 add the expansion's max to MaxLevelSquish (8 tunings; DBD comment, not used by TrinityCore; our test cannot tell it apart because the same 100% holds with or without it, so LIKELY), 0x4 DisabledForItem (92 tunings; TrinityCore), 0x8 Horde and 0x10 Alliance (TrinityCore), 0x1 (99), 0x20 (280), 0x40 (309), 0x80 (105) unknown. `LfgMinLevel`/`LfgMaxLevel` (173 / 172 distinct) are the dungeon-finder range; `XpMultQuest` (2,933 tunings 1.0, 17 others 1.1-2.0) is the quest XP multiplier (TrinityCore name); `ILevel` is 0 in every row.

**ConditionalContentTuning** (2,564 rows): `ParentContentTuningID` -> `RedirectContentTuningID` chosen by `RedirectFlag`/`RedirectEnum` (values 0..40; 34 = 772 rows, 0 = 638, 13 = 498). TrinityCore reads the player's "ConditionalFlags" but never sets them, so the code never redirects. In the data **28,348 of the 33,123 quests in the retail quest cache sit on a tuning that has a redirect, and for 27,446 of them the redirected tuning has a different minimum level** (26,691 a different maximum). Meaning of the modes is unknown (GUESS: Chromie Time / timewalking / expansion-squish modes). The game's own `C_QuestLog.GetQuestDifficultyLevel` and `IsQuestTrivial` already apply it, which is why the probe's `IsQuestTrivial` facts pass (open-items row 9) is the right test, not a static decode.

**ContentTuningXExpected** (ExpectedStatModID, Mythic+ season bounds, 1,147 rows), **ContentTuningXDifficulty** (980), **GlobalGameContentTuning** (11) carry combat scaling and per-difficulty tunings: no quest use. **ContentTuningXLabel** (199 rows, LabelID 1742..1747 on 195 tunings): no label name table, CANT-DECODE. **ContentRestrictionRule/RuleSet** (42/13): the DBD comment lists the rule types (map is PvP, area bit, mage tower, solo shuffle, expansion...), none quest related.

Forever's ContentTuning has 100 rows: it carries `AreaTable.ContentTuningID` (20 areas), `LFGDungeons` (25), `MapDifficulty` (26) and `PlayerCondition` (18) ranges but no quest or task table references it (no QuestV2CliTask), so Forever's quest levels come only from the quest cache `level`/`minLevel`.

## 5. ModifierTree

`B_conditions-modifiertree-types.csv` is the dictionary. Facts:

- **Operator** (PROVEN: TrinityCore `ModifierTreeOperator` and the CriteriaHandler switch): 2 SingleTrue and 3 SingleFalse are leaves with a Type (152,945 and 62,785 rows); 4 All and 8 Some are group nodes with Type 0 (75,841 and 25,892; no group node carries a type, no leaf has Type 0 except 21 rows); Some needs `max(Amount, 1)` children true: 25,242 have Amount <= 1 (any one), **650 need 2 or more (a group the repo reads as met)**. Operator 0 = 5 rows. Forever: 1,615 / 392 / 568 / 249; Era: 721 / 188 / 190 / 90.
- **Parent** links a leaf to its group; the roots are referenced by `PlayerCondition.ModifierTreeID` (23,707 rows), `Criteria.Modifier_tree_ID` (22,373), `ItemCondition`.
- **Asset / SecondaryAsset / TertiaryAsset / Amount:** for each type TrinityCore's `ModifierSatisfied` names what each holds; the CSV records which types read SecondaryAsset or TertiaryAsset. Asset is the main reference (quest, faction, skill, area, item, spell, achievement, level...); SecondaryAsset is a second reference or a value (reputation standing for type 95, skill level for 99, objective progress value for 158/159, second quest for 369); TertiaryAsset is a third parameter only used by a handful of types (134, 367, 381, 390, 391, 445 with small values). `Amount` is the child count for operator 8 and otherwise 1 (316,437 of 317,468 rows).
- **TertiaryAsset and quests:** refs.csv shows 358 quest IDs. I count 3,791 non-zero values, 3,588 below 1,000 and only 203 above (types 390: 86, 381: 80, 318: 14, 391: 11, 446: 10). The 358 distinct values (310 below 1,000) resolve into QuestV2 because QuestV2 holds almost every small ID; the column holds counts, levels and masks, not quests. Same artefact for UiMap and ContentTuning.
- **Type usage in retail (rows):** 110 completed quest 34,472; 84 on quest 29,851; 112 completed quest objective 24,299 (Asset = QuestObjective ID, but only 5.5% of those IDs exist in the QuestObjective table, so the objective is mostly not resolvable); 2 nested PlayerCondition 12,899; 8 has aura 8,913; 111 ready to turn in 8,820; 67 world state expression 7,536; 200 transmog 6,050; 174 can accept quest 6,012; 271 completed or on quest 5,951; 19 item 4,824; 73 nested ModifierTree 4,025; 114 item incl. bank 3,420; 25 race 1,656; 26 class 1,579; 17 in area 1,554; 32 map 1,176; 241 completed questline 740... 79 types occur in Forever, 383 in retail.
- **Types that point at quests** (Asset is a QuestV2 ID, FK 99-100%): 110, 84, 111, 174, 271, 382 (completed on account), 392 (completed or ready to turn in), 395 and 396 (undocumented in TrinityCore master, Asset is a quest; 106 and 90 rows), 369 (between two quests: Asset and SecondaryAsset), 112/158/159 (QuestObjective), 206 (QuestInfo ID, FK 100%), 236/240/241/242/243 and 383/384 (QuestLine IDs: 241's Asset resolves into QuestLine 100%), 388 (campaign). **Reputation:** 95 (Asset Faction 100%, Secondary = standing), 94/254 (friendship reaction), 221/218 (paragon), 85 (exalted). **Skill:** 99 (Asset SkillLine 99%, Secondary level). **Level:** 69, 71, 39 (Asset = level), 268/272 (Asset ContentTuning 100%). **Zone/map:** 17 (AreaTable 100%), 41, 32 (Map 99%), 113. **Achievement:** 86 account (1,343 rows), 87 character (678). **Holiday/time:** 289 HasTimeEventPassed (1,197 rows; Asset is a TimeEvent ID: only 5 TimeEventData rows exist, so the IDs are not resolvable client-side), 109 TimeBetween (12). **Expansion:** 92, 106, 264. **Chromie Time:** 300 (Asset UIChromieTimeExpansionInfo), 301. **Covenant:** 288. **Spec/race/class/gender:** 279 / 25 / 26 / 97.
- **Undocumented types** (not in TrinityCore master, 420+ or gaps; listed in the CSV with counts): 339 (490 rows, no asset), 381 (265), 427 (301; Asset resolves to Spell 71%), 418 (123), 395/396 (quest), 399, 412, 445, 446. Retail uses types beyond TrinityCore's enum, so the dictionary is a lower bound; `Asset` meanings for those are GUESS.

## 6. Criteria, CriteriaTree, Achievement

- **Criteria.Type** is TrinityCore's `CriteriaType` (full list in the CSV): 243 distinct types in retail (99 in Forever); the commonest: 27 CompleteQuest 14,201, 0 KillCreature 10,169, 8 EarnAchievement 5,968, 165 DefeatDungeonEncounter 4,376, 92 scenario game event 3,745, 29 CastSpell 2,995, 158 WinPetBattle 2,034, 43 RevealWorldMapOverlay 1,932. `Asset` for type 27 is a quest ID (PROVEN, FK). **Criteria type 27: 14,201 criteria name 11,690 distinct quests, 7,809 of our retail quests (22%)**; 6,182 of ours are inside an achievement tree (1,482 achievements have quest criteria). The biggest: "Variety is the Spice of Life" (967 quests, 892 ours), "Wide World of Quests" (849, 827), "The World Beyond" (210, 209), the Draenor treasure-hunter chain (309 each, 0 ours: treasure quests). Quest-count types: 9 CompleteQuestsCount (13), 11 CompleteQuestsInZone (641; Asset AreaTable), 14 CompleteDailyQuest (34), 203 CompleteAnyWorldQuest (179). Forever: 109 type-27 criteria, 84 quests, 32 ours, none in an achievement of ours (the 13 achievements are Cooking/Fishing dailies, gear, honor): the earlier review's count is confirmed.
- **Criteria.Flags** (TrinityCore `CriteriaFlags`): 0x1 FailAchievement (195), 0x2 ResetOnStart (326), 0x8 AlwaysSaveToDB (1,088), 0x10 AllowCriteriaDecrement (89), **0x20 IsForQuest (10,616: set on 2,662 CompleteQuest criteria and 1,320 KillCreature criteria, the quest objective kinds)**, 0x40 (11) and 0x80 (30) unknown, **0x100 (19,691) unknown but 9,880 of the 14,201 CompleteQuest criteria carry it and almost no other type** (PROVEN association, name unknown, GUESS "account-wide progress").
- **CriteriaTree**: `Operator` TrinityCore `CriteriaTreeOperator` (0 Complete 93,203; 4 CompleteAll 21,020... in the data 4: 21,020, 8 CompleteAtLeast 4,764, 5 Sum 2,080, 9 ProgressBar 647); `Flags` TrinityCore `CriteriaTreeFlags`: 0x1 ProgressBar, 0x2 DoNotDisplay (29,976), 0x8 IsMoney, 0x10 ToastOnComplete, 0x20 UseObjectsDescription, 0x40 ShowFactionSpecificChild, 0x80 DisplayAllChildren, 0x100 AwardBonusRep, 0x200 AllianceOnly (425), 0x400 HordeOnly (206), 0x800 DisplayAsFraction, **0x1000 IsForQuest (3,248)**; 0x2000 (2,717), 0x4000, 0x8000 unknown. `CriteriaID` joins to Criteria (FK 100%); `Amount` is the target count (up to 2,000,000,000: money in copper under IsMoney).
- **Achievement**: columns decoded in columns.csv. `Faction` (-1 both, 0 Horde, 1 Alliance), `Category` -> Achievement_Category, `Criteria_tree` -> CriteriaTree root (FK 99.8%), `Supercedes`, `Shares_criteria`, `CovenantID` (8 rows), `HiddenBeforeDisplaySeason`, `LegacyAfterTimeEvent`. `Flags` bits are TrinityCore's `AchievementFlags`, checked against titles in bits.csv: bit 0 Counter = the "Statistics" rows ("Alterac Valley victories"), bits 8/9 realm first ("Realm First! ..."), bit 17 account-wide ("2000 Quests Completed"), bits 12-16 guild flags. Quest-related achievements that **gate quests**: the "WQ Unlock" family above, 329 of our quests in total. Forever has 436 achievements (statistics, PvP ranks, dungeons, professions); none gates a quest and none is in our quest data.
- **Achievement_Category** (243 / 56 / 13): `Parent`, `Ui_order`, `Name_lang`; used for names already.

## 7. PVPDifficulty (Forever brackets)

Columns `RangeIndex`, `MinLevel`, `MaxLevel`, `MapID`. Forever (25 rows): map 489 Warsong Gulch 10-19, 20-29, 30-39, 40-49, 50-59, 60; map 529 Arathi Basin 20-29, 30-39, 40-49, 50-59, 60; map 30 Alterac Valley 51-60; plus maps 2777, 2995, 2997, 3005 that exist only in Forever (brackets down to 10-19 / 20-29, and a 1-60 row on 2995; map names not checked). Retail: 354 rows (mostly one bracket at the level cap per map). **This is the data behind data-sources-review decision 25:** Forever's `quests.jsonl` has 44 Warsong Gulch, 54 Arathi Basin and 86 Alterac Valley zone quests; 32 WSG quests carry a `minLevel` of 10/20/30/40/50 (bracket minimums) and 40 AB quests one of 20/25/30/35/40/45/50 (bracket minimums or half-brackets), so those 72 get a maximum from the bracket containing their minimum (WSG minLevel 20 -> 29); the Alterac Valley quests (minLevel 51 or 55 on 84 of 86) already sit in the only bracket 51-60 and need no cap. The 12 WSG and 14 AB quests without a `minLevel` need a look. (The in-game test in decision 25 still stands.)

## 8. WorldStateExpression

`Expression` is hex bytecode: enabled byte, then relational expressions joined by a logic byte (0 none, 1 and, 2 or, 3 xor). Each value is a type byte (0 none, 1 constant int32, 2 world state ID int32, 3 function u32 + two values), an optional operator (1 sum, 2 minus, 3 times, 4 divide, 5 remainder) and a comparison (1 ==, 2 !=, 3 <, 4 <=, 5 >, 6 >=). Source: TrinityCore `IsMeetingWorldStateExpression`. I wrote a decoder (`a6_wse.ps1`): **all 42,808 retail expressions parse with 0 errors and no trailing bytes** (so the format is PROVEN), using 19,159 distinct world state IDs and 3,136 expressions with no world state at all; the commonest functions are 22 WORLD_STATE_EXPRESSION (2,823 expressions, nesting), 37 UI_WIDGET_DATA (936), 15 DIFFICULTY_ID (475), 38 TIME_EVENT_PASSED (190), 1 RANDOM (187), 10 HOLIDAY_ACTIVE (only 1). **The world state IDs have no client table** (`WorldState` is not a DB2; `WorldStateUI` exists only in Era with 13 rows), so the addon cannot tell what "world state 19436 == 1" means or evaluate it. Quest use: `QuestV2CliTask.WorldStateExpressionID` is set for 4,321 of 6,258 task rows (4,302 ours; 3,819 distinct expressions): these are the weekly/seasonal availability switches of world quests. Their functions: WORLD_STATE_EXPRESSION 69, DIFFICULTY_ID 38, WAR_MODE_ACTIVE 1, TIME_EVENT_PASSED 1; none uses HOLIDAY_ACTIVE (so no task quest's holiday can be read from it; our 1,319 `holiday` quests come from elsewhere). `PlayerCondition.WorldStateExpressionID` (7,124 conditions) and ModifierTree type 67 (7,536 rows) reference the same expressions. Verdict: not usable for filtering; usable only as a marker "this task quest rotates" (4,302 quests).

## 9. Opportunities, ranked

1. **Task quests' conditions: read the ModifierTree too** (retail). 1,624 task quests have a positive completed-quest leaf under their `QuestV2CliTask.ConditionID`; 1,448 have no prerequisite in our data today. Needs the OR/Some handling `QuestConditions.ps1` already has; extend `Sync-QuestPrerequisites.ps1` step 2c from QuestLine/Campaign to CliTask conditions. World quests are hidden by default, so the value is mostly correctness of the filtered view. Also types 111 (ready to turn in) and 174 (can accept).
2. **Player-facing requirement text** (both languages of the client): 4,332 of our quests reach a condition with Blizzard's own failure text. For campaigns it is `CampaignXCondition.FailureReason_lang` (165 rows, 91 distinct texts: "Reach level 30 to continue your Order Hall campaign.", the two "Complete the quest ... in Dalaran/Broken Shore" texts); for others `PlayerCondition.Failure_description_lang` (7,390 rows). Fits the owner's "Blizzard's data beats third-party" rule and the requirements tooltip. Retail only.
3. **Achievement requirement** (retail): 329 of our quests; the game can answer. CHECK in game that `GetAchievementInfo` on the WQ-unlock achievements matches what the character sees.
4. **Level gate from the condition**: 155 quest-line quests (and 1,749 chapter quests) have a higher level in their condition than our gate. Only after decoding the Chromie Time alternatives; CHECK in game on a level-10 character (one Shadowlands quest-line quest, e.g. 58184).
5. **Forever battleground brackets** from PVPDifficulty: 72 WSG/AB quests gain a maximum level (decision 25), no other source for it.
6. **Account-wide completion (PlayerCondition flag 0x1000, ModifierTree 382/383)**: 962 conditions and 1,069 + 97 tree rows say "completed on any character"; confirms the open-items finding that account-wide quests count everywhere, and says which quests are account-wide (516 distinct quests in type 382, 249 ours) beyond the quest flag.
7. **Reputation requirement text for BfA war fronts** (128 quests): small.
8. **Covenant**: the client names 592 covenant-gated quests, we hold 777: reconcile the 36 the client has and we do not, and review the 221 only we have.
9. **ConditionalContentTuning**: not a decode job; run the probe's `IsQuestTrivial`/`GetQuestDifficultyLevel` on a Chromie Time character to see whether the redirected minimum differs from the API's.
10. Not worth doing: Phase, UnitCondition, LFGDungeons for quests, ContentRestrictionRule, WorldStateExpression decoding, ModifierTree type 112 (QuestObjective IDs mostly absent).

## 10. Things that look like they should exist but do not

- A table of world state IDs and names (the key to every WorldStateExpression and to the task quests' availability).
- Names for `ContentTuningXLabel.LabelID` and for `ConditionalContentTuning.RedirectEnum` modes.
- A quest-to-prerequisite table: the only quest requirements in the client are in conditions (PlayerCondition/ModifierTree) and the CliTask `FiltCompletedQuest` columns; ordinary quests have none (QuestV2 has 3 columns), which is why API / TrinityCore / CMaNGOS stay needed.
- Any quest condition in Forever (QuestLine and QuestPOIBlob carry no condition IDs; no Campaign, no CliTask).
- TimeEvent names (only 5 TimeEventData rows for type 289's 2,394 uses).

## 11. Open questions and the in-game test that settles each

1. Does the client enforce `AllowedMinOffset` on a quest's minimum level (TrinityCore says `MinLevel + TargetLevelDelta`)? Test: a character one level under the API minimum but within the offset, at a giver whose quest has a tuning with AllowedMinOffset -2 (2,522 of the 29,134 tested quests, e.g. read `C_QuestLog.GetQuestInfo(...)` and try to accept).
2. What are the ConditionalContentTuning modes (RedirectEnum)? Test: the probe's `GetQuestDifficultyLevel` for one quest before and after picking a Chromie Time expansion.
3. What is Criteria flag 0x100? Test: look at whether quests under it are account-wide with `C_QuestLog.IsQuestFlaggedCompletedOnAccount`.
4. Are the WQ-unlock achievements checked per character (`GetAchievementInfo` of 12608/12609/11473)?
5. Do level conditions on QuestLine.PlayerConditionID (e.g. 86994 "Dirty Jobs", 180 quests) really hide the line below the tuning level, or is the Chromie branch always true?

## 12. Method notes

All numbers come from the three CSV folders, `quests.jsonl`, the repo's `tools\quest_api_cache` and `retail_quest_cache_12.1.0.69933.jsonl` (read only), and TrinityCore master. Flag counts from awk over `PlayerCondition.csv` use a CSV-aware field pattern and can be off by about 0.1% (embedded newlines in text columns); `bits.csv` counts are exact. ModifierTree resolves "Asset into table" tests only count where ID columns exist; types with small asset values match every table by chance and are not evidence.
