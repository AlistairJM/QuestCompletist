# H3_rest: alphabetical remainder (131 tables)

## Summary

Screen: all 925 retail columns of the cluster were checked against refs.csv, declared foreign keys and name patterns (Quest, Condition, Holiday, Faction, Map, Area, Zone, Expansion, Race, Class, Skill, Creature, Level, Spec). Result: 121 NO, 5 CHECK, 5 CANT-DECODE. No Field_* column is tied to quests or conditions by refs.csv (RandPropPoints Epic_3/4 hit ModifierTree only by chance, ByChance 0.218). The cluster is almost entirely art, audio, housing, archaeology, Shadowlands soulbinds, UI atlases and widgets. Full per-table verdicts are in H3_rest-verdicts.csv.

Tables unique to one game: retail only (housing Room*, Soulbind*, Research*, UIChromieTimeExpansionInfo, World_PVP_Area, UiQuestDetailsTheme, RafActivity, SeamlessSite, TieredEntrance ...), Forever only (SuperDistrictSet, SuperDistrictSetCollection, SuperDistrictSetXAvailableSD, SuperDistrictTransfer), Era only (ScalingStatValues, WorldLayerMapSet), Forever+Era (StableSlotPrices). Quest-looking names that hide nothing: no PlayerChoice, Gossip, Conversation, Scene, Mission or Adventure table is in this cluster.

## Verdict table

See H3_rest-verdicts.csv (131 rows). The CHECK ones: RafActivity, ResearchSite, UIChromieTimeExpansionInfo, UiQuestDetailsTheme, World_PVP_Area. CANT-DECODE: the four SuperDistrict tables (Forever, one unnamed column, parent table AvailableSuperDistrict not exported) and TieredEntrance (retail).

## Relevant tables

### UiQuestDetailsTheme (72 rows, retail only) and QuestV2.UiQuestDetailsThemeID
- Columns: Signature_lang (9 rows set, e.g. King Varian Wrynn, Warchief Vol'jin), BackgroundTexture (64), SealTexture (11), PoiIcon (6), UiMapPinInfo (1, id 8): all are quest-window art references (declared FKs). Blizzard API has GetQuestDetailsTheme; our tools never read it.
- QuestV2.UiQuestDetailsThemeID: 465 of 66,546 quests have a non-zero theme (42 distinct); 450 of them are in our quests.jsonl. QuestXUIQuestDetailsTheme holds 476 rows and agrees on all 465 (11 extra rows only there).
- Measured: theme 42 = Inscription profession quests (Specialized Secrets: Inscription, Dragon Isles Inscription, Inscription Services Requested ...), theme 40 = Enchanting (same pattern), theme 17 = Kyrian callings (24 quests, zone "Kyrian Callings"), theme 76 = 94 Prey quests, theme 52 = Trading Post quests. So the theme is a grouping hint (profession, covenant, campaign), LIKELY, not a restriction.
- Opportunity: cross-check profession and covenant tags for ~450 quests. Our zone/category data already puts them in "Kyrian Callings" and "Professions", so the gain is verification, not new data.

### UIChromieTimeExpansionInfo (9 rows, retail only)
- ShowPlayerConditionID resolves to PlayerConditions whose ModifierTree child is type 300 with Asset = the row ID (rows 143499/143501/207493/284967). TrinityCore names type 300 PlayerIsInChromieTime (PROVEN, two kinds of evidence).
- Across the whole client 222 PlayerConditions test Chromie Time. Among tables with a PlayerCondition column, uses: AdventureJournal 181, LFGDungeons 32, QuestPOIBlob 15 (4 quests: 51443 and 60361 "Battle for Azeroth: Mission Statement", 46727 "Battle for Azeroth: Tides of War", all warfront intro quests), ContentPush 6, JournalTier 8. So Chromie Time has no real quest gating in the client tables; QuestV2CliTask.ContentTuningID never uses the chromie tunings (0 quests).
- ExpansionMask bits decoded in H3_rest-bits.csv.

### World_PVP_Area (3 rows, retail)
Area 4197 Wintergrasp, 5095 Tol Barad, 6941 Ashran, level 50. Could mark the three PvP zones, nothing more.

### ResearchSite (453 rows, retail)
QuestPOIBlobID resolves 453/453 but all blobs have QuestID 0: digsite outlines in the quest-POI store. Archaeology only; a QuestPOIBlob reader must ignore blobs with QuestID 0.

### RafActivity (3 rows)
Reward quests 57850, 57852, 57853, all present in our data; identifies them as Recruit-A-Friend rewards.

## Opportunities (ranked)
1. UiQuestDetailsTheme grouping as a profession/covenant cross-check, 450 quests (CHECK, retail only).
2. Chromie Time decoding for any future "needs Chromie Time" rule: 15 QuestPOIBlob rows, 4 quests only; not worth building.
3. RAF reward quests (3) and World_PVP_Area (3 zones): tiny.

## Nothing missing found here
No table in this cluster holds quest givers, prerequisites, breadcrumbs, holiday dates or removed-quest data.

## Contradicts or adds to the earlier review
Not checked against client-tables-review.md beyond the above counts; none of these tables was assessed there as useful and my counts agree with NO.

## Open questions / in-game tests
- Does GetQuestDetailsTheme return the QuestV2 theme for a given quest? In game: /run print(C_QuestLog.GetQuestDetailsTheme(70188)) should show Inscription's theme 42 values.
- The Cataclysm mask 9 (bit 0 set): unknown; compare in game with C_ChromieTime.GetChromieTimeExpansionOptions.
- SuperDistrict* on Forever: need the AvailableSuperDistrict table or UI Lua use; none found.
