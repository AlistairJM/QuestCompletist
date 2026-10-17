# H1_rest: 133 leftover tables (A-D range), sweep for missed quest content

## Summary

The sweep found nothing the themed researchers missed. Of 133 tables, 131 are NO and 2 are CHECK, and neither CHECK table adds quest data. No table in the cluster has a quest column. Screening: every `refs.csv` row for the cluster (retail, Forever, Era), all header greps (Quest, Condition, Holiday, Faction, Map, Area, Zone, Expansion, Race, Class, Skill, NPC, Creature, Achievement, Level, Gossip, Choice) and every undeclared `Field_*` column.

- The only quest-sized links are `CharShipment.TreasureID` (85 of 101 distinct values are QuestV2 ids; meaning unproven, Garrison/Dragonflight shipment tracking) and `AreaConditionalData.PlayerConditionID` (6 rows gate on PrevQuestID). Neither is a filter input.
- The earlier review (`client-tables-review.md`) lists none of these tables; nothing in it contradicts this sweep. One correction to the catalogue: `Contribution` shows ReadBy `Build-QuestLocationData.ps1` and `Import-RecordedGivers.ps1`, a false positive. Those scripts only contain the text `Warfront Contribution` (a quest InfoName pattern); no tool reads the Contribution table.
- Names that hide quest content were all checked: no PlayerChoice, Gossip, Scene, Mission, Adventure or ActionBar quest tables fall in this range. Artifact*, Azerite*, Contribution, ConversationLine, CharShipment* and BonusRoll look quest-adjacent but are not (details below).
- Forever-only tables: AuctionHouseRedirect (16 rows), AvailableSuperDistrict (5 realm rulesets: PvP, Normal, Roleplay, Hardcore, CN Beta Event). Both NO.
- Retail-only in this cluster: Artifact*, Azerite*, AltMinimap*, AreaConditionalData (Forever has 2 rows), BonusRoll, Contribution*, CharShipment*, ConversationLine (Forever 625, Era 3), Crafting*, DelvesSeason, DisplaySeason, EncounterEvent.

## Verdicts

All 133 rows with games and one-line summaries are in `H1_rest-verdicts.csv`. Counts: NO 131, CHECK 2 (AreaConditionalData, BattlemasterList). USE 0, CANT-DECODE 0.

Row counts per game are in the CSV (`Games` column, e.g. `retail(114) forever(2)`).

## Per-table notes (the ones with any link)

### AreaConditionalData (retail 114, Forever 2, Era 0)
Maps an AreaID (AreaTable, 92 distinct) to an overriding subzone name shown while a PlayerCondition holds. Of 114 rows: "The Rift" x34 (all PlayerCondition 91308 -> ModifierTree 167629), Anduin's Wrath, Dawnsailor, Tiffin's Melody, The Lionheart (PCs 67138-67141, PrevQuestID 54852-54855, areas 10454/10455), Chamber of Lost Light and Light of the Loa (68604 PrevQuest 49426/53719 with race mask; 68603 PrevQuest 53719). Quests 49426 "The King's Gambit" and 53719 "Allegiance of the Zandalari" are in `quests.jsonl` (Zuldazar). The rest gate on auras. It is area renaming: it tells that a subzone appears only after a quest, but we already have the prerequisites from PlayerCondition via the quest tables. No opportunity measured; verdict CHECK only because it shows how the client decides area labels.

### BattlemasterList (retail 133, Forever 10, Era 4) and BattlemasterListXMap
Flags decoded in `H1_rest-bits.csv` from TrinityCore `BattlemasterListFlags` (InternalOnly 0x1 ... IsEpic 0x80); IsEpic is proven by data (the 5 rows typed "Epic Battleground"). `HolidayWorldState` links BG holiday weekends to WorldStates (AV 1941, WSG 1942, AB 1943, EotS 2851...). Forever differs from Era: it adds Darkspear Islands (id 1157, levels 30-60, HolidayWorldState 29784), Battle for Gilneas (1159), Hyjal Crater (1168), Mak'gora Arena (1169), Random Battleground/Epic and Battle for Blackrock; Era has AV, WSG, AB and Battle for Blackrock. 122 retail quests are in zones named like a BG (Ashran 58, Alterac Valley 44, Slayer's Rise 13, Arathi Basin 3, Seething Shore 2, Korrak's Revenge 1, Deephaul Ravine 1); the addon already flags PvP from quest flags, so this adds nothing for quests. Possible use for the calendar: confirm BG holiday weekends and Forever's new 29784 world state.

### Contribution / ContributionStyle (retail only)
Donation UIs (Legion order hall, Arathi/Darkshore war effort, Wax Collection). Through ManagedWorldStateInput.QuestID only 4 quests are tied (46277 Mage Tower, 46735 Command Center, 46736 Nether Disruptor, 82994 Wax Contribution), all in our data. Tied to nothing the addon lacks.

### CharShipment / CharShipmentContainer (retail only)
`TreasureID` 85 of 101 distinct non-zero values are QuestV2 ids; 110 of 243 rows resolve to quests in `quests.jsonl` (e.g. 55994 "Do Not Drink", 66017 "Clan Ohn'ir", 66013 "Investigate the Door"). Value not proven (GUESS: the tracking quest tied to unlocking the shipment). Schema comment on `CharShipmentContainer.GarrBuildingType`: also used to map to a hardcoded list of quests. Garrison/Order hall/Dragonflight feature; no filter use. `Duration` -> QuestV2 in refs.csv is a coincidence (seconds).

### CharacterLoadout
`RaceMasks_0/1` are Blizzard's race mask in two 32-bit words; 1309324210 / -1440044374 is the exact pair in PlayerCondition 68604, and -1/-1 (12 rows) means all races. Supports the project's note that Blizzard masks need 34+ bits.

### Everything else
CharStartKit/CharBaseInfo (race-class matrix and start-zone label, Forever 57/56 rows), CharTitles (736 retail, 41 Forever, Mask_ID title bit), AlliedRace (14 races; unlock achievement 9 "Level 40" on 10 races, 40899 Earthen, 62620 Haranir), DelvesSeason (faction ids "Delves: Season N"), AssistedCombatRule (ConditionValue2 -> ContentTuning is small-number coincidence: 104 of 157 values are 10), BroadcastText (59 rows with PlayerCondition, text only), Artifact*/Azerite* (Legion/BfA systems with PlayerCondition links on appearances), Curve/CurvePoint (generic curves, ContentTuning scaling), and 100+ presentation, store, UI and effect tables have no quest, map, NPC, holiday, faction or skill link and are dismissed in the verdict file.

## Opportunities (ranked)

None worth building from this cluster.
1. Calendar sanity check (low): BattlemasterList.HolidayWorldState lists the BG-weekend world states, including Forever's new 29784 (Darkspear Islands); use as a cross-check in the calendar sweep, not as quest data.
2. Garrison tracking quests (very low): CharShipment.TreasureID names 110 quests in our data; only worth knowing if someone investigates why those hidden-looking quests exist.
3. Area labels (very low): AreaConditionalData shows subzones that change names after quests; cosmetic.

## Things that should exist and do not
Nothing new beyond the other clusters' findings: no table here carries quest starter/ender, type or breadcrumb data.

## Open questions
- `CharShipment.TreasureID`: an in-game test would be to complete or look up quest 55994 and see whether it is a hidden tracking quest set when the "Do Not Drink" shipment unlocks.
- Forever world state 29784 (Darkspear Islands holiday): check the calendar on the live Forever client when the event is active.
