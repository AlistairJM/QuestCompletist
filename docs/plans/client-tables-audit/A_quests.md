# Cluster A_quests: quest records, storylines, campaigns and the tables that point at quests

Builds: retail 12.1.5.70391, WoW: Forever 1.60.1.70374, Classic Era 1.15.9.70003. Measured against
data\quests.jsonl (35,544 retail quests) and data\forever\quests.jsonl (5,097). Scratch scripts and
intermediate lists are in `$A\work\A_quests\`. "Ours" means in our data.

## Summary

1. **QuestV2.UniqueBitFlag is the biggest unused fact.** TrinityCore's `Player::SetQuestCompletedBit` shows it is
   the index into the character's quest-completed bit vector, so quests that share a value share ONE completion
   slot. 2,687 retail groups (7,191 quests) share a value; 549 groups hold 2 or more of our quests that one
   character can meet (1,882 quests, 4,556 pairs), and only 78 of those pairs are already in
   `qcMutuallyExclusive`. Independent check: of our 194 retail exclusive pairs 90 (46%) share a bit, and of
   WoW: Forever's 311 CMaNGOS `exclusiveWith` pairs 260 (84%) do. Faction twins, class/covenant variants and
   rotating daily pools are in there too, so it is "same slot", not strictly "exclusive": see opportunity 1.
2. **QuestV2CliTask is the only table with per-quest flags, and nothing like it exists for ordinary quests.** It is
   the client's copy of the 6,258 task quests (retail only; Forever and Era have no such table). Its three Flags
   columns are the server's quest flag words (Flags, FlagsEx, FlagsEx2): 3 bit positions are confirmed by the
   schema's own comments (isQuestStart [2].9, hide-from-GetTaskInfo [2].13, isDaily [0].12/[0].15/[1].15), the rest
   fit TrinityCore's enums and are checked below. Findings: 14 rows are `INTERNAL_BUILDS_ONLY` (13 of 14 are
   plainly test titles), 198 are account-level quests (F1 0x80; 67 ours), 127 carry 0x4000000 of which 100 are
   exactly the 101 "Calling Quest" rows.
3. **BreadCrumbID is not usable and the earlier review's count was one short.** 12 rows are non-zero (the review
   said 11). 3 of the 12 values are not quest IDs at all, 9 resolve, which is what chance gives (ByChance 0.67),
   and none is a lead-in for its row's quest ("Fashion Week" -> "Work Order: Sea Mist Potion"). NO.
4. **No table lists next quest, exclusive group or breadcrumb.** I scanned every retail header (1,104 tables) for
   such columns. The only quest-to-quest links in the client are `PlayerCondition.PrevQuestID_0..3/CurrQuestID/
   CurrentCompletedQuestID` (someone else's cluster), `QuestV2CliTask.FiltCompletedQuest_0..2` + `Logic`
   (already decoded by `Sync-QuestPrerequisites.ps1`, including the NOT bits), `QuestLineXQuest.OrderIndex`, and
   shared `UniqueBitFlag`. `ItemSparse.StartQuestID` (1,790 retail, 555 Forever, 366 Era) is the only
   quest-starter link (item), already read by three tools.
5. **Campaign's "ID-looking" columns are PlayerCondition IDs, as the schema already declares** (Prerequisite,
   Stalled, Completed, OnlyStallIf, SortAsNormalQuest, UseMinimalHeader; FK confirmed 100% by fks.csv). The client
   evaluates them to booleans (`C_CampaignInfo.SortAsNormalQuest` returns bool; `CampaignState` Complete/InProgress/
   Stalled). We read only Prerequisite. `Campaign.Flags` bits are isWarCampaign / isContainerCampaign /
   (hideFutureChapters or usesNormalQuestIcons): see bits.

Corrections of `client-tables-review.md`: QuestV2CliTask has 6,258 rows today (6,242 then); BreadCrumbID has 12
non-zero values, not 11; `FiltRaceMasks` is the only race column (there is no `FiltRaces` in retail's CSV);
QuestSort.Flags and QuestSort.UiOrderIndex are NOT read by any tool (columns.csv lists them under ReadBy only because
`Build-ForeverMenu.ps1` mentions "Flags" for GlobalStrings); the review's claim that QuestV2 "has three columns" is
right, but its UiQuestDetailsThemeID duplicates QuestXUIQuestDetailsTheme exactly (465 of 465 agree; the table has
11 more quests).

## Verdict table

See `A_quests-verdicts.csv` (all 69 tables of the cluster). Short form: USE: QuestV2 (UniqueBitFlag), QuestV2CliTask,
QuestInfo, QuestSort, QuestLine, QuestLineXQuest, Campaign, CampaignXQuestLine, CampaignXCondition,
QuestPOIBlob/Point, CollectableSourceQuestSparse (all already used in part). CHECK: shared UniqueBitFlag groups,
CampaignXCondition chapter gates, QuestInfo.Modifiers quality bits, F1 ACCOUNT flag. NO for rewards, art,
housing, Trading Post, vignettes, scenarios, transmog, traits and the hidden-tracker tables.

## Per-table notes

### QuestV2 (retail 66,546 rows; Forever 6,610; Era 4,807)
- `ID`: quest. `UniqueBitFlag`: completed-bit index (TrinityCore Player.cpp lines 16487-16511; PROVEN with the
  empirical tests below). Dense: 62,042 distinct values over 66,546 rows, none zero, max 72,567.
- `UiQuestDetailsThemeID` (retail and Forever columns; Era lacks it): the quest's window theme (UiQuestDetailsTheme:
  signature, seal, POI icon). 465 non-zero retail rows, all duplicated in QuestXUIQuestDetailsTheme; Forever: 0.
  `QuestUtil.GetWorldQuestAtlasInfo` falls back to the theme's `poiIcon`, so this is where per-quest-kind map icons
  come from for 450 of our quests.
- Membership is NOT a roster. It omits quests with no persistent completion (repeatables): 914 of our 995
  repeatable-typed quests are absent (92%), but also 1,301 of our 35,544 retail quests (3.7%) and 568 of our 5,097
  Forever quests (11%; real Vanilla quests: Alterac Valley, Ahn'Qiraj War Effort, Argent Dawn invasion). Forever's
  QuestV2 also holds 2,081 IDs we lack, the ones checked are `<UNUSED>`, `REUSE`, `[DNT]`. Candidates: 81 of our
  repeatable-typed quests ARE listed (Karazhan "... No More" 11031-11034, Seal of Wartorn Fate 52834-52837), and 66 one-time
  quests are absent (Legion 110 A, Internal: Default Invasion Reward): retype/removal review items, not facts.
- Shared UniqueBitFlag: retail 2,687 groups (sizes 2:2,212, 3:180, 4:134, up to 76), Forever 321 groups (1,086
  quests, mostly new 'Camping 101: *' and 'Buying Friendship: *'), Era 236 (760).

### QuestV2CliTask (retail only, 6,258 rows)
Row = task quest (world quests, bonus objectives, callings, trackers). 5,740 are in our data; 518 are not: 471
carry the tracking flag, 6 are "Hidden Quest", and 11 look real (Hallow's End 2026 "Sugar Run" 92498/93400/95826,
"Candy Crafting" 97219/98421/98422, "Community Candy Crawl" 98801, "A Haunted Home" 93898, "Voices of Stone" 97241,
"Ancient Depths, Ancient Venom" 98379, "Ascending with Venomstones" 98390): new since our data, `Add-TaskQuests.ps1`
covers them.
Columns (full list in -columns.csv):
- `QuestTitle_lang`, `BulletText_lang` (40 rows, objective text "Honor the Bonfire in ..."), `ID`.
- `UniqueBitFlag` equals QuestV2's in all 6,181 rows that are in both (77 rows are not in QuestV2).
- `ConditionID` -> PlayerCondition (5,070 non-zero): general gate (prev quests, reputation, skill, level...), read
  for PrevQuestID only.
- `FiltActiveQuest`: all 0. `FiltNonActiveQuest`: 2 rows (52798 needs 52129 NOT active; 79333 needs 84367 NOT
  active): "not while X is in the log"; too rare to matter. `FiltMin/MaxFactionID/Value`, `CovenantID`: all 0 in 6,258
  rows: dead in this build; reputation and covenant gates live in the PlayerCondition (`ConditionID`).
- `FiltClasses`: -1 for 6,207 rows (all classes); 51 rows restrict (e.g. 2048 = bit 11). `FiltRaceMasks_0/_1`: 64-bit
  race mask as two int32; 4,905 all, 689 Alliance (hi word 0x55155555 = allied races), 656 Horde, 8 single races.
  Both read by `Get-WagoQuestRequirements.ps1` and `Add-TaskQuests.ps1`.
- `FiltCompletedQuest_0..2` + `FiltCompletedQuestLogic`: Logic = TrinityCore `PlayerConditionLogic`: bits 2(i-1)..
  give term i's join (1 AND, 2 OR), bits 16+i invert term i. Values: 1 (283), 131073 (46), 2 (24), 5 (20), 65536 (9),
  131077 (3). 58 rows use a NOT; `Sync-QuestPrerequisites.ps1` drops inverted terms (never treats NOT as met).
- `FiltMinSkillID/Value`: 524 rows (skill levels 25: 290, 1: 190, 75: 44), retail's `qcQuestSkillRequirements` is
  still empty; professions are filled from it, levels are not.
- `BreadCrumbID`: see summary 3. `StartItem`: 198 rows (item handed over on accept; the review is right that it is
  not the starter). `WorldStateExpressionID`: 4,321 non-zero (3,819 distinct), 4,302 of ours: bytecode like
  `0102EC4B0000000301030000000000` (world state 0x4BEC compared with a value); no WorldState table exists in the
  CSV set, so the gates (events, Prey, "Forbidden Reach 1/x") can't be named offline: CANT-DECODE without
  TrinityCore's expression reader plus world-state names.
- `QuestInfoID` -> QuestInfo (56 distinct), `ContentTuningID` (224). `Field_9_0_2_36206_022` (0..3; 4,927 are 3, 1,003 are 2,
  328 are 0): unknown; 3 and 2 are high in WQ rows, 0 never occurs in tracking rows: GUESS (task kind).
- `Flags_0/1/2`: see bits file. `Flags_0` bits above 31 in bits.csv are sign extension (52 rows have 0x80000000).

### QuestInfo (retail 84, Forever 7, Era 7)
`Type` equals Blizzard's `Enum.QuestTagType` (0..19): every name fits (Profession 1: all "<profession> World Quest";
PvP 3, PetBattle 4, Bounty 5, Dungeon 6, Invasion 7, Raid 8, Contribution 9, RatedReward 10, InvasionWrapper 11,
FactionAssault 12, Islands 13, Threat 14, CovenantCalling 15, DragonRiderRacing 16, Capstone 17, WorldBoss 18, Prey
19). PROVEN (names + enum). `Profession` -> SkillLine (15 rows). The row IDs are `QuestTag` ids (Group 1, PvP 41,
Raid 62, Dungeon 81, Legendary 83, Heroic 85, ...).
`Modifiers` decoded in the bits file: b0 Rare, b1 Elite, b2 Epic are the `GetQuestTagInfo` `quality`/`isElite` fields
(Blizzard's `QuestUtil` line 95 identifies "world boss the old way" as Normal + isElite + Epic, and row 112 "Epic Elite
World Quest" is exactly b1+b2). Forever has the same IDs but 21 = "Life" (retail "Class") and Legendary there has
Modifiers 512, where retail's 512 is "Bonus Objective with Completion Toast" (so b9 is "completion toast", not
"bonus objective").

### QuestSort (retail 199, Forever 39, Era 36)
Heading names (11 languages via the language CSVs) and category IDs: negative QuestSort ID = our `category`. Retail
Flags bit 0 is on 'Legendary' (344), 'Meta Quests' (645) and 'Neighborhood' (655): the headings that match the Legendary and
Meta classifications and housing: LIKELY "has its own classification/section". `UiOrderIndex`: Tournament 3, Battle
Pets 2, Meta Quests 10. Neither is read. Forever: 39 rows, Flags column exists but is all 0; includes 'REUSE - old ...'
placeholders (21, 23, 25, 41, 241).

### QuestLine / QuestLineXQuest (retail 1,694 / 21,150; Forever 3 / 22; Era none)
Verified FKs (QuestLineXQuest.QuestID 99.6% real quests, QuestLine.QuestID 100%). `Flags` of QuestLine: b3 (8) is on 1,483 of
1,505 lines (default); b4 (16) 121 lines, 92 of them inside a campaign (Legion launch events, Vault of the Wardens);
b6 (64) 208 lines, average 5.7 quests, only 1 in a campaign, 43 with a PlayerCondition; b7 (128) 15 lines, 12 in
campaigns, the "Lorewalking: ..." chapters. `QuestLineInfo` fields are isHidden, isLegendary, isCampaign (+
`QuestLineIgnoresAccountCompletedFiltering`): the bits are among those but I cannot assign them: GUESS, in-game test:
`C_QuestLine.GetQuestLineInfo` for one line of each flag value. `QuestLineXQuest.Flags` bit0 on 272 rows in 154 lines
(no Blizzard field; name unknown). `PlayerConditionID` on 158 lines (used by `QuestConditions.ps1`);
`CompletionPlayerConditionID` on 74 lines (unused); `QuestLine.QuestID` is set for 40 lines (the quest that
starts the line). Forever's 3 lines are all-zero columns: PvP Season Journey (6293, 10 quests), Toxic Soil (6026, 11) and To Have Loved and Lost (5963, 1).

### Campaign (182), CampaignXQuestLine (812), CampaignXCondition (257), retail only
- `Title_lang`, `Description_lang` (86; 'Hidden campaign' x4, '{DNT} - Hidden Complete'), `UiTextureKitID`,
  `UiQuestDetailsThemeID` (115), `DisplayPriority`, `RewardQuestID` (1 row: 52262).
- `Prerequisite` (174 non-zero), `Stalled` (171), `Completed` (87), `OnlyStallIf` (11), `SortAsNormalQuest` (29),
  `UseMinimalHeader` (64): all PlayerCondition IDs. PlayerConditions 5703, 34450, 49081, 21439 and 5793 are empty
  or world-state-only (always true), so the common values mean "unconditional". Only Prerequisite is read.
- Semantics: Completed true -> `CampaignState.Complete`; Stalled true -> Stalled (text from CampaignXCondition);
  SortAsNormalQuest/UseMinimalHeader -> the booleans of `QuestInfo`/`CampaignInfo` (Blizzard docs, QuestMapFrame
  line 1874). PROVEN by the API shapes plus FK.
- `CampaignXCondition`: 257 rows, 71 campaigns, `PlayerConditionID` (161 go through ModifierTree, 31 name a previous
  quest, 62 other), `FailureReason_lang` on 165 rows (91 distinct: "Reach level 30 to continue your Order Hall campaign.",
  "Earn Renown 11 to continue the campaign."). Covers 5,349 quests in the campaigns' lines (2,923 ours). Read by no
  tool. Value: the player-facing reason a chapter is locked and the quests it hides; needs ModifierTree decoding for
  the 161 (another cluster).
- `CampaignXQuestLine`: campaign -> lines in chapter order (33 chapters max); used.

### QuestPOIBlob / QuestPOIPoint (retail 72,736 / 172,724; Forever 54 / 99)
`ObjectiveIndex`: 32 (23,795 blobs, 21,206 quests: the start point; 1 point in 23,768), -1 (17,888 blobs, 16,346
quests: own point, mostly the turn-in), 0..30 (30,594: objectives, `ObjectiveID` -> QuestObjective for 25,997),
31 (459 blobs, 116 with 12 points: unknown, GUESS "area/zone blob"). 15,922 quests have both 32 and -1. 3,814 blobs
have QuestID 0. `Flags`: 0 (48,167), 2 (15,126), 1 (7,476), 3, 7, 4098, 8192, ...: no Blizzard name; bit 0 appears
on -1 and objective blobs (3,593 of the -1 blobs) and never on index 32 except 7 and 5: GUESS "quest-end/objective
marker". `PlayerConditionID` on 6,782 blobs (1,356 start points, 1,395 turn-ins): the game's own offer conditions.
`NavigationPlayerConditionID`: 105 rows. Forever: 54 blobs of 22 quests, 23 index-32 and 23 index -1, flags and
conditions all 0 except two blobs.

### QuestObjective (10,771 retail)
`Type` is TrinityCore's `QuestObjectiveType` (0..21 observed). `Flags` bits are TrinityCore's `QuestObjectiveFlags`
(b2 Optional 4,420; b3 Hidden 4,658; b4 HideCreditMsg; b6 PartOfProgressBar 3,852; the common value 92 = 64+16+8+4
is the hidden progress objective of world quests): LIKELY. Not needed: the game shows objectives itself.

### QuestLabel (1,935 rows, Forever 2)
`LabelID` is a generic tag shared with Spell/GameObject/Creature/ContentTuning label tables; no table names a label.
84 labels, 1,791 quests (1,594 ours). Largest: 6036 Prey hunts (98), 2751 Bar Tab Barrel (87), 5672 Mechagon (85),
3285/3286 Isle of Thunder (81 each), 4785 Death Knight campaign champions (77), 4063 Secrets of Azeroth (70), 4784
Suramar/Stormheim (65), 6009 Snail Mail (52), 2703 Felwood Flyover races (48). They group quests that the game
treats as a set (replayable families, rotating pools). Not found in ContentTuningXLabel or LabelXContentRestrictRuleSet
(0 of 84). Could group repeat families but needs names: NO for now.

### Reward/UI tables (one line each)
QuestXP/QuestMoneyReward/QuestFactionReward: reward by level x difficulty (Forever's reputation reader already uses
QuestFactionReward); QuestPackageItem 13,368 reward package rows; QuestFeedbackEffect 1,177 interact cursors, minimap
atlas, spell; QuestXUiWidgetSet 117; QuestXUIQuestDetailsTheme 476. All NO.

### Tables that point at quests (counts from our data)
Measured with `$A\work\A_quests\refs.ps1`. QuestV2 references with hidden-tracker share: CraftingData.FirstCraftFlagQuestID
1,721 distinct, 0 ours (hidden); TransmogSet.TrackingQuestID 2,181 distinct, 16 ours; Vignette.VisibleTrackingQuestID 3,761,
291 ours, 228 flagged tracking; WorldBossLockout 14, 3 ours; ScenarioStep.RewardQuestID 259, 57 ours; InvasionClientData.WorldQuestID 19, 3 ours;
TraitCurrencySource 12, 1 ours. Real-quest references: AdventureJournal 341 (298 ours; "Warchief's Command: ..."
suggestions with PlayerConditions, 700 of 702 rows), AdventureMapPOI 151 (144), Bounty 135 (134, 96 are dailies),
CollectableSourceQuestSparse 2,074 (2,070; giver creature + position, used by `Apply-ClientQuestGivers.ps1`),
ContentPush 91 (83), HouseLevelData 5, InitiativeTask 7, QuestHub 107 (104), QuestXGroupActivity 101 (98: 65 are WQ, link
to GroupFinderActivity), QuestDrivenScenario 65 (56), RetroactiveDecorReward 136 (135), UISplashScreen 16 (15).

## Opportunities, ranked

1. **Shared `QuestV2.UniqueBitFlag` -> same-slot groups** (USE after an in-game test; both games).
   Measured: retail 549 groups, 1,882 of our quests (type 1: 1,024; daily 702; weekly 108; repeatable-ish rest),
   4,556 pairs, 78 already in `qcMutuallyExclusive`; 223 of the groups have different quest names (real alternates:
   "Patchwork Command"/"Mathias' Command"; "The Fate of Tuurem"/"Concerns About Tuurem"; 'Netherwing' drakes 11109-11114;
   'Defiler's Basic/Standard/Advanced Care Package' 8263-8265), 326 have identical names (covenant/class/faction
   copies, "Report to the Trading Post"). Forever: 43 groups, 283 pairs, 120 already in `exclusiveWith`; 84% of the
   311 existing pairs share a bit, so the signal is strong where we already know the answer. Caveat: rotating daily
   pools ("A Gift For ..." 30470-30479, "Aiding the Accord" x13) share a slot but each can be done on its own day, so
   restrict to non-recurring types, and the TrinityCore function only proves "one completion bit". In-game test
   (one line): on a character that completed 30470, run `/run print(C_QuestLog.IsQuestFlaggedCompleted(30471))`;
   expected true if the bit is shared (and then the game itself already answers for all of them, so the addon's tick
   scan agrees without data).
2. **Account-wide quests: FlagsEx 0x80** (198 task rows, 67 ours: "Cryptkeeper Kassir's Best Friend" ...). Blizzard's
   `QuestTag.Account` (102) exists, so completion is account-wide; the addon's per-character ticks could use
   `C_QuestLog.IsQuestFlaggedCompletedOnAccount`. CHECK, small.
3. **Retail skill levels for 524 task quests** (`FiltMinSkillValue`, 507 ours per the earlier review): parity item,
   value small because world quests are hidden by default.
4. **Campaign chapter gates** (CampaignXCondition + Campaign.Stalled/Completed): 71 campaigns, 5,349 quests, 165 rows of
   player-facing text; needs ModifierTree decoding for 161 of 257. Low-medium.
5. **QuestInfo bits for the quest tooltip**: quality (b0/b2) and elite (b1) for the 84 tags, `Type` as QuestTagType: the game
   already answers `GetQuestTagInfo` at runtime, offline value only for quests the client has not loaded.
6. **Absent/listed QuestV2 checks**: 81 repeatable-typed quests listed in QuestV2, 66 one-time quests absent: review lists
   (not facts).
7. **QuestLabel families** (1,791 quests, 84 sets): grouping only; no names.

## Things that look like they should exist but do not
- A next-quest / exclusive-group / breadcrumb table: none in 1,104 retail tables (only the PlayerCondition quest lists and the
  shared completion bit). Retail's breadcrumb knowledge therefore stays TrinityCore (pre-MoP) plus what the game says at runtime.
- Quest giver or turn-in NPC IDs for ordinary quests: only CollectableSourceQuestSparse (2,074 quests with transmog rewards) and
  the QuestPOIBlob positions (no NPC).
- Any quest table at all in Era beyond QuestV2 (4,807 rows with UniqueBitFlag), QuestInfo, QuestSort: no QuestPOIBlob/QuestLine
  in Era; Forever has QuestPOIBlob/Line only for its 22 new quests.
- Names of QuestLabel IDs, names of WorldState values, and per-quest minimum level for ordinary quests (ContentTuningID lives in
  CliTask only; the quest cache supplies it).

## Open questions and the in-game test that settles each
- Do shared-bit quests answer `IsQuestFlaggedCompleted` true for the others? (opportunity 1; one line).
- Which QuestLine.Flags bits are isHidden/isLegendary/isCampaign? `/run for _,id in ipairs({319,90,5673}) do local i=C_QuestLine.GetQuestLineInfo(<a quest of line>) print(id, i and i.isHidden, i and i.isLegendary, i and i.isCampaign) end`
  on a quest of each line.
- Is `Modifiers` bit 3 (8) "displayExpiration"? Compare `C_QuestLog.GetQuestTagInfo(q).displayExpiration` for 109 vs 296 vs 111 tag quests.
- Do QuestPOIBlob index-31 blobs mean something visible? Open the map on one of the 459 blobs' quests.
