# E1a: creatures, objects and items (retail 12.1.5.70391, Forever 1.60.1.70374, Era 1.15.9.70003)

All numbers below were measured by scripts in `$A\work\E1a_creatures_objects_items\` against `data\quests.jsonl` / `data\pins.jsonl` (retail) and `data\forever\*` (Forever). Retail has 35,544 quests and 16,084 pins (25,776 quests pinned); Forever has 5,097 quests and 1,701 pins (3,675 pinned).

## Summary

1. No client table in this cluster says which NPC or object offers a quest. `Creature` is a partial name list for what the client UI needs, `GameObjects` holds zone-label and decoration objects, and the gossip tables carry no creature id. The only quest-giver table in the whole database is `CollectableSourceQuestSparse` (other cluster): the earlier review's claim holds. It covers 2,070 of our quests and all 2,070 already have pins.
2. `ItemSparse.StartQuestID` is the one real opportunity here: it names the item that starts a quest. Retail: 1,790 items / 1,755 quests, 1,430 of them ours. Forever: 555 items / 548 quests, 408 ours. 1,061 of the 1,430 retail quests and all 408 Forever quests have no pin, because an item starts them: that explains 11 percent of retail's and 29 percent of Forever's unpinned quests. Today the item is used only for its class limit (25 retail / 15 Forever quests).
3. The same item row carries limits our quest rows lack: faction (162 retail quests, 4 wrong in ours), race (3 retail, 2 Forever), reputation rank (14 retail, 3 Forever), skill (41 retail, 28 with no profession tag), level (Forever: 152 of 336 above our minLevel), holiday (3), instance (7).
4. 325 retail quests (231 in QuestV2) and 140 Forever quests (123 in QuestV2) are started by items but are not in our data; lists in `E1a_creatures_objects_items-startitem-quests-not-in-our-data-*.csv` (review before adding: many are removed or deprecated content).
5. `Creature` gives Blizzard's own names for 855 of 8,440 retail pin NPC ids (10 percent; all 855 equal ours) plus a title for 321 of them; for Forever it matches 0 of 1,433 pin ids (Forever's 180 rows are pets).

Contradictions with `docs\plans\client-tables-review.md` and `data-sources-review.md` are in the last section.

## Verdict table

143 tables in the cluster; every row with its games and a line is in `E1a_creatures_objects_items-verdicts.csv`. Tables that matter:

| Table | Games (rows) | Verdict | One line |
|---|---|---|---|
| ItemSparse | R 175,747 / F 19,248 / E 24,442 | USE | StartQuestID plus the item's use limits |
| Item | R 213,908 / F 31,847 / E 24,973 | USE | ClassID 12 Quest, 13 Key; start items are 1,592 of 1,790 class 12 |
| Creature | R 23,140 / F 180 / E 1 | USE (small) | names for 855 pin NPCs, titles for 321; not a giver list |
| CreatureDifficulty | R 23,905 / F 180 / E 1 | NO | 1:1 with Creature, level/faction template/content tuning, 9 flag words CANT-DECODE |
| GameObjects | R 31,950 / F 1,520 / E 864 | NO | 98.9 percent type 5 area-label objects; no quest givers or posters |
| GossipNPCOption (and 7 siblings) | R 7,632 / F 1,558 / E 1,028 | NO | enum of option kinds, no creature or quest id |
| Lock, LockType | R 2,008 and 108 | NO | item key / skill / spell cases; lockboxes and gathering |
| CreatureXContribution | R 9 | NO | war-effort NPCs, none in Creature |
| ItemSearchName | R 104,384 / F 6,626 / E 13,085 | NO | copy of requirement columns, no StartQuestID |
| everything else (presentation, scaling, bonus lists, sounds, vehicles, crafting orders) | | NO | dismissed in one line each in the CSV |

There are no Loot*, Vendor* or NPC*-giver tables in the client (the client has no loot tables; `ItemDisenchantLoot`, `ItemSalvageLoot` and `CreatureDifficultyTreasure` are not quest loot). Vendor placement is in `CollectableSourceVendorSparse` (other cluster).

## ItemSparse

### Quest-bearing columns (full list in `-columns.csv`)

| Column | Meaning (evidence, confidence) | Read today | Use |
|---|---|---|---|
| StartQuestID | quest begun by the item (TC struct; 77 percent of DONT_DESTROY_ON_QUEST_ACCEPT items carry it; PROVEN) | Find-MissingQuests, Get-WagoQuestRequirements, Import-ForeverData | "Starts from" |
| AllowableClass | 1 << (ChrClasses.ID-1), -1/0 any (25 of 25 retail quests agree with ours; PROVEN) | yes | done |
| AllowableRaces_0/_1 (Forever AllowableRace_0/_1) | 64-bit mask over ChrRaces.PlayableRaceBit (our conversion matches 51 of 54; PROVEN) | no | 3 + 2 quests |
| Flags_1 bits 0/1 | Horde-only / Alliance-only (all 19,522 retail items with an OppositeFactionItemID have exactly one; PROVEN) | no | 162 retail quests, 4 corrections |
| MinFactionID + MinReputation | reputation needed to use the item (FK Faction 142 of 142; rank scale 0..7 LIKELY) | no | 14 retail + 3 Forever |
| RequiredSkill + RequiredSkillRank | skill and points (FK SkillLine 162 of 163; LIKELY) | RequiredSkill in Sync-QuestProfessions | 28 untagged retail quests |
| RequiredLevel | level to use the item (LIKELY) | no | Forever minLevel |
| RequiredHoliday, InstanceBound, ZoneBound_0/_1, RequiredAbility | see columns csv | no | 3, 7, 1, 0 quests |
| Bonding | 4 = quest-bound (13,122 of 13,436 are ClassID 12; PROVEN) | no | none |

### Flag words (every set bit decoded in `-bits.csv`)

`Flags_0..Flags_3` are TrinityCore's ItemFlags, ItemFlags2, ItemFlags3 and ItemFlags4; `Flags_4` is a fifth word with no TrinityCore name (bits 0,2,3,5,7,11 in retail, small counts). There is no "starts a quest" flag; "quest item" is `Item.ClassID = 12` and `Bonding = 4`. Facts that were tested, not just named:

- Account bound (Flags_0 bit 27) and BNet-trade-ok (Flags_1 bit 17) are set on exactly the same 14,344 retail items (PROVEN). Forever has 10 and 7: the word means something else or is nearly unused there.
- Horde/Alliance (Flags_1 bits 0/1): 19,522 of 19,522 twin items carry exactly one (PROVEN).
- DONT_DESTROY_ON_QUEST_ACCEPT (Flags_2 bit 0): 301 retail rows, 231 start a quest, 266 are class 12; Forever 197, 188 start a quest (PROVEN).
- HAS_QUEST_GLOW (Flags_0 bit 24): 376 rows, 181 start a quest; MULTI_DROP (bit 11): 795 of 1,790 start items against 5.7 percent of all items (LIKELY).
- Flags_1 bit 13 (TC "SHOW_BEFORE_DISCOVERED") is set on 100 percent of rows in both games: constant, no information.
- Forever's Flags_1 differs from retail: bit 2 is on 14,842 of 19,248 (retail: 0 rows), bit 14 on 87 percent. Do not apply retail meanings to Forever's Flags_1 without a test (GUESS).
- Unique/carry limit lives in MaxCount (=1 on 13,979 rows) and LimitCategory, not in a flag; ITEM_FLAG_UNIQUE_EQUIPPABLE (Flags_0 bit 19) is gear only (6,406 rows, 36 with MaxCount 1).

### Start items against our data

| | Retail | Forever |
|---|---|---|
| items with StartQuestID | 1,790 | 555 (Era 366) |
| distinct quests | 1,755 (1,458 in QuestV2) | 548 (123 of the 140 not-ours are in QuestV2) |
| our quests started by an item | 1,430 (1,458 items; 9 quests have 2+ items; 33931 has 21) | 408 (413 items) |
| of those with a pin today | 369 | 0 |
| item class: 12 Quest / 0-8 consumable other / 15 misc | 1,592 / 64 / 126 | 345 / 155 / 50 |
| class-limited | 25 quests | 15 |
| race-limited | 54 (3 where our row is wider) | 2 (both wider) |
| faction-flagged | 162 (4 disagree: 11002, 38202, 38194, 56071) | 2 |
| needs a faction rank | 14 | 3 |
| needs a skill | 41 (28 untagged) | 3 (already in skills.jsonl) |
| item RequiredLevel above our minLevel | 24 of 90 with minLevel | 152 of 336 |
| RequiredHoliday | 3 (693; ours says 524288) | 0 |
| quests not in our data | 325 quests (231 in QuestV2) | 140 (123 in QuestV2) |
| pins named exactly like their start item | 100 | 0 |

The probe's `startItem` (what the server hands over on accept, per `retail-quest-cache.md`) is a different link: of the 698 Forever probe records that carry one, only 68 equal an ItemSparse start item for the same quest. That confirms the earlier warning that it must not be shown as "starts from".

### Relationships

- `StartQuestID -> QuestV2.ID`: declared, but only 1,458 of 1,755 distinct values resolve (83 percent); 297 point at quests QuestV2 does not list, so QuestV2 is not a complete quest list.
- `OppositeFactionItemID -> Item` 100 percent. `MinFactionID -> Faction` 100 percent. `RequiredSkill -> SkillLine` 162 of 163. `LockID -> Lock` 100 percent. `RequiredHoliday -> Holidays` 27 of 28. `InstanceBound -> Map` 28 of 29. `ZoneBound -> AreaTable` 100 percent.
- Join to a quest: `ItemSparse.StartQuestID = quests.id`; to a pin: through the quest id (item-started quests have no giver; 100 retail pins are named after the item).
- Retail uses `AllowableRaces_0/_1`; Forever/Era name them `AllowableRace_0/_1` (the Forever schema; same layout).

## Creature (and the question "is there any table of quest givers?")

`Creature` columns: ID, Name_lang, NameAlt_lang (13 rows), Title_lang (3,350 rows), TitleAlt_lang (1), Classification, CreatureType, CreatureFamily, StartAnimState, DisplayID_0..3, DisplayProbability_0..3, AlwaysItem_0..2. Retail 23,140 rows (IDs 3..276,385), Forever 180, Era 1.

Why it is a partial list: the rows are creatures the client has to name or draw outside the world: 3,004 battle-pet species, garrison followers and encounters, Soulbind, the encounter journal, collections. Only 6,519 of the 23,140 rows are referenced by the client tables I could follow (BattlePetSpecies, GarrFollower, GarrEncounter, CollectableSource*, QuestObjective, Soulbind, ...); the other 16,621 (e.g. 186129 Wrathion, 245162 Jayaan) are creatures the client was handed names for without a table pointing at them. The sample of a pin NPC in the table is overwhelmingly humanoid (1,125 of 1,281).

Measured against pins: 855 of 8,440 retail pin NPC ids are Creature rows (1,281 pins, 2,300 quests), names equal on 855 of 855; titles on 321. 337 retail pins have a name but no npc id and 0 of those names occur in Creature; 5,159 pins have neither name nor npc id (4,650 quests) and no table in this cluster can place a name on them. The 1,846 distinct `CollectableSourceQuestSparse` givers resolve to a Creature row for only 77 (4 percent), so names for them must come from TrinityCore. Forever: 0 of 1,433 pin ids are in Creature; the 180 rows are pets (Snapjaws, Furbolgs, Murlocs, class dolls) and a Diablo mini.

Every other column or table that carries a creature id or a position, checked by header scan of all 1,104 retail tables plus `refs.csv`: `CollectableSourceQuestSparse` (quest givers, 15,172 rows), `CollectableSourceVendorSparse` (vendor creature + item + position, 97,535 rows), `QuestObjective.ObjectID` (kill/talk targets: 8,170 creature objectives of our quests, 389 ids in Creature, 10 are pin NPCs), `QuestPOIBlob/Point`, `TaxiNodes` (flight points, MountCreatureID), `AreaPOI`, `Vignette`, `JournalInstanceEntrance`, `Soulbind.CreatureID`, `GarrFollower`, `GarrEncounter`, `BattlePetSpecies`, `CreatureXContribution`, `HouseDecor/NeighborhoodPlot` (GameObjectID). Only `CollectableSourceQuestSparse` ties a quest to a giver. Forever has none of the CollectableSource tables. Era has Creature with 1 row.

`CreatureDifficulty` is 1:1 with Creature (CreatureID FK 100 percent): level delta, FactionTemplateID, ContentTuningID, and flag words `Flags_0..8` for which TrinityCore keeps a commented-out struct, so they cannot be decoded.

## GameObjects

31,950 rows (Forever 1,520, Era 864): Name_lang, Pos_0..2, Rot_0..3, ID, OwnerID (FK Map), DisplayID, Flags, Scale, TypeID, Phase columns, PropValue_0..7. TypeID values (TrinityCore GameobjectTypes): 5 GENERIC 31,626; 38 GARRISON_BUILDING 177; 39 GARRISON_PLOT 79; 48 UI_LINK 60 (Bulletin Board, plot cornerstones, Shred-Master); 60 CLIENT_MODEL 5; 3 CHEST 1; 40 CLIENT_CREATURE 1; 41 CLIENT_ITEM 1. Type 2 (QUESTGIVER) has no row in any game; the earlier review's "no wanted posters or quest objects" holds (0 names match wanted/bounty/notice/poster; 92 hits are Conquest Hold, Mailbox, Bulletin Board, Earthmother's Bounty). The type 5 rows are named after zones and subzones (5,782 of 30,782 named rows equal an AreaTable name; for example `Northshire Abbey`, `Stormwind City` at the same coordinates, display 26): area-label objects, not decorations in the usual sense, and not usable for giver positions. 5 retail pin names equal a GameObjects name (Broken Barrel, Boots, Captain's Log ...) and 131 pin NPC ids equal a GameObjects ID number (separate id spaces; not name-checked). PropValue is just the first 8 of the server's per-type fields. TypeID 5's PropValue_0/1 are 0 or 1.

## Lock, LockType, Gossip, Vehicle, Loot, Vendor

- `Lock`: up to 8 cases (`_Index`, `Skill`, `Type`, `Action`); Type 1 = item key (Index is an ItemID such as 6208, 6210, 29750, 31752, 35746), 2 = lock type with required skill rank (row 2: LockType 1, 5, 6 with Skill 5), 3 = spell (WoWDBDefs comments and row shapes; LIKELY). Only 49 ItemSparse rows use a lock (48 are class 15 lockboxes). Nothing connects a lock to a quest or to a GameObjects row in the client.
- `LockType`: names such as Lockpicking, Herbalism, Mining, Open; presentation for gathering.
- `GossipNPCOption`: `GossipNpcOption` is an enum 0..67 (Blizzard `GossipConstants.GossipNpcOption`), not a bitmask: the catalogue's per-bit counts for it are meaningless. The rows name option kinds (Vendor, Taxinode, Trainer, ...) with links to trainers, shipments, UiMap and talent trees. No column names an NPC, a menu or a quest, so it cannot say who offers what. `GossipXUIDisplayInfo`/`GossipUIDisplayInfoCondition` are Torghast layer texts.
- Vehicle/VehicleSeat/VehiclePOIType/VehicleUIIndicator: control and attachment data; presentation.
- There are no client loot or vendor-stock tables; drop and vendor sources of start items are not recoverable from the client.

## Opportunities, ranked

| # | Opportunity | Measured | Games |
|---|---|---|---|
| 1 | "Starts from: item" field from ItemSparse.StartQuestID (open-items row 19 already taken; add the counts) and use it to mark item-started quests as expected-without-pin | 1,430 retail + 408 Forever quests; removes 1,061 retail and 408 Forever quests from the no-pin worry list; 100 retail pins already carry the item's name | both |
| 2 | Start-item quests missing from our data: review lists | 325 retail quests (308 ordinary names, 231 in QuestV2); 140 Forever (137, 123 in QuestV2). Samples: 361 A Letter to Yvette, 1642 Tome of Divinity, 5841 Kharanos Gift Voucher; Forever 66281 Book of Deathstones series, 79945 Orders from the Grand Crusader | both |
| 3 | Profession tags from RequiredSkill of start items | 28 of 41 retail start-item quests with a skill have no profession tag: 10 fishing (55299-55313, skill 356), Draenor garrison profession quests (36176, 36205, 36236, 36239, 36255, 36286, 36301, 36308, 36309, 36314, 36408, 36435, 36505, 36589), 27675, 32295, 35058, 35342. Sync-QuestProfessions reads this column yet leaves them: check whether that is deliberate | retail |
| 4 | Faction from ITEM_FLAG2 faction bits | 4 quests where our faction is 3: 11002, 38202, 38194, 56071 | retail |
| 5 | Item RequiredLevel as a lower bound for minLevel on item-only quests | Forever 152 of 336; retail 24 of 90 | both |
| 6 | Reputation rank of the item as a requirement | 14 retail (Netherwing 11041/11081, Rustbolt 55072/56086/56087/56145/56165, Wild Hunt/Court of Night/Marasmius 62423-62438, Hand of the Prophet/Vol'jin's 39358/39359), 3 Forever | both |
| 7 | Race masks of start items | 3 retail (42978, 42985, 56071) + 2 Forever (79358, 96135) | both |
| 8 | Creature names and titles as a second source for pin NPCs | 855 names (all agree), 321 titles | retail |
| 9 | 11 quests whose CollectableSourceQuestSparse giver is known but the pin has no npc id (8 also nameless) | 11 | retail |

Not opportunities: Lock, GossipNPCOption, GameObjects, CreatureDifficulty, CreatureXContribution, ItemSearchName, Vehicle, loot (no quest data).

## Things that look like they should exist but do not

- A creature-to-quest table, an NPC spawn table, a creature position table.
- Quest-giver GameObjects (type 2) and wanted-poster objects.
- A gossip menu that names an NPC.
- Loot or drop tables for quest items; vendor stock tables for start items.
- Forever has none of the CollectableSource tables, so no client giver positions at all.

## Open questions and in-game tests

1. Do the 4 faction-mismatched start items really bar the other faction from the quest? On an off-faction character, use the item (or call `C_Item`'s quest info) for 56071, 38202.
2. Does an item's `RequiredLevel` block the quest start (the item cannot be used)? Test on a low-level character with a Forever item such as 7495's item (level 60).
3. `MinReputation` scale 0..7: check the item tooltip against the numeric rank for one Netherwing item.
4. `RequiredHoliday` 693 versus our holiday bit 524288: compare `Holidays.csv` and the calendar.
5. Forever Flags_1 bit 2 (14,842 rows) and bit 14: meaning unknown; nothing in the addon depends on it.
6. Why Sync-QuestProfessions leaves 28 skill-gated start-item quests untagged.

## Contradictions with the earlier reviews

- `client-tables-review.md` says Creature has 23,074 rows (retail) and 179 (Forever), GameObjects 31,736 / 1,520: the build in `$A` has 23,140 / 180 and 31,950 / 1,520; the substance (partial names, decorations only) is confirmed, with the correction that the type 5 rows are area-label objects.
- It (and `data-sources-review.md` D-rows) says only AllowableClass is read from ItemSparse and RequiredSkill is unread. In fact `Sync-QuestProfessions.ps1` (line 256) reads `RequiredSkill`; AllowableRaces, MinFactionID, MinReputation, RequiredLevel, RequiredHoliday, the faction flag bits and the bound columns are unread. `ReadBy` for Import-ForeverData.ps1 on RequiredSkill is a false positive (the name appears in a comment about CMaNGOS).
- The declared FK `ItemSparse.StartQuestID -> QuestV2.ID` resolves for 83 percent only.
- `data-sources-review.md` line 195 mentions 99 pins named exactly after a starting item: measured 100 retail, 0 Forever.
- The catalogue's bit table for `GossipNPCOption.GossipNpcOption` (bits 0-6 with counts) is an artefact of treating an enum as a mask.

Supporting files: `E1a_creatures_objects_items-verdicts.csv`, `-columns.csv`, `-bits.csv`, and the two `-startitem-quests-not-in-our-data-*.csv` lists (columns Game, Quest, Item, ItemName, InQuestV2, RequiredLevel, AllowableClass; 332 retail and 142 Forever item rows).
