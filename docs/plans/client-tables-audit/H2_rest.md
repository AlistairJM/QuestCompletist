# H2_rest: alphabetical remainder (133 tables, EntryTemplate to PvpTalent)

## Summary
Screened all 133 tables with refs.csv (declared and undeclared), fks.csv, header greps and the repo tools (grep of tools\*.ps1 finds none of the notable tables read). Result: 1 USE, 4 CHECK, 120 NO, 8 CANT-DECODE. Almost the whole cluster is presentation, combat scaling, housing, crafting, PvP and node-graph data. The undeclared strong references in refs.csv (GameParameter.Max->ChrRaces, PaperDollItemFrame.SlotIconFileID->ModifierTree, GlyphProperties.SpellID->Item/ModifierTree, PvpScalingEffect.SpecializationID) all have ByChance above 0.05 or are file/spell ids, so they are chance matches, not relationships.

Hidden-name check (PlayerChoice, Gossip, Conversation, Scene, Mission, Adventure, Challenge Mode, Pet battles, Pvp): none of the first six exist in this cluster. Pvp* tables carry QuestIDs only in PVPBracketTypes (all 0) and PvpBrawl (1 row).

## Findings, ranked
1. LoreTextPublic (retail only, 1,469 rows) is the campaign recap chapter list. ConditionID -> PlayerCondition, and 932 of the conditions name a quest (PrevQuestID/CurrQuestID) that reveals the chapter: 575 distinct quests across 69 campaigns, 569 in our quests.jsonl, 565 in QuestLineXQuest. Six of our quests have a campaign chapter but no questline: 60500 Halls of Atonement: Medallion of Pride, 69888 Unusual Suspects, 64816 Reality's Doorstep, 46253 Pillars of Creation, 54282 Battle of Dazar'alor, 57185 Dutybound. Six quests (57692, 51403, 88918, 93420, 95533, 72402) are not in ours. Evidence: Blizzard C_LoreText documentation and CampaignOverview.lua (campaign recap), counted from the CSVs. Value: cross-check of campaign chapter order and race/class variants (PlayerCondition RaceMasks on 22 rows, ClassMask 2, CovenantID 1, ModifierTreeID 522). Modest. LoreText itself has 11 rows (text arrives from the server).
2. GroupFinderActivity: Forever fills MinLevel/MaxLevelSuggestion (108 of 109 rows) and its category 116 "Quests & Zones" lists 41 zone level ranges (Elwynn 1-14, Westfall 8-24, Stranglethorn 28-50, Mount Hyjal 55-60...). Retail leaves them 0 on all 1,350 rows. We hold no zone level range today. Our Forever quest levels sit in these ranges at the median (Durotar median 8 in 1-14, Tanaris median 60 vs 38-54 is an outlier of our data). Names only (AreaID 0, MapID 0/1), so join by zone name.
3. Hotfixes (retail and Era): the client's own list of 3,105 server patches (116 tables). It names QUESTV2 (10 rows), QUESTPOIBLOB 18, HOLIDAYS 12 (ids 1880-1891), PLAYERCONDITION 60, QUESTGIVERXQUEST 2. Five hotfixed quest ids (98831, 98834, 98836, 99306, 99585) are in QuestV2 but not in our quests.jsonl. Use as a new-data watch for step 2, not as quest data.
4. ManagedWorldStateInput: QuestID on 4 of 8 rows (46277, 46735, 46736 Legion Contribute quests; 82994 Wax Contribution). Explains event-stage gating for 4 quests. Tiny.
5. Locale: client language list (13/13/12 rows) to confirm which name languages exist.

## Nothing found
PVPBracketTypes.WeeklyQuestID_0-3 are declared QuestV2 FKs but 24 of 24 values are 0. PvpBrawl.RewardsQuestID is set on one row (Korrak's Revenge 63953, already in ours). PvpSeason/PrestigeLevelInfo reference achievements only for PvP seasons. GroupFinderActivity.PlayerConditionID: 247 distinct conditions, 1 with a quest term, none with MinLevel. LivingWorldObjectTemplate.WorldStateExpressionID is 0 on all 7 rows. Location has no map id so its 142,162 rows cannot give positions. No table in this cluster holds quest-giver, flag, faction, race or class limits beyond PlayerCondition conditions already counted.

## Games
Retail only: LoreTextPublic, LoreText, Exterior*, Flight*, Glide*, Glyph*, MythicPlus*, ModifiedCrafting*, ProfTrait*, Node graph tables, Occluder*, PvpBrawl, PVPBracketTypes. Forever only (with Era): FFTTile (Forever, Era), PetLoyalty, PetPersonality, LevelExperience (Forever 123 rows). Shared by all three: GroupFinderActivity (1,350 / 109 / 98), GameTips, MailTemplate, GameParameter, Locale. Hotfixes: retail 3,105, Era 501, none in Forever.

## Per-table detail
See H2_rest-verdicts.csv (every table), H2_rest-columns.csv (analysed columns), H2_rest-bits.csv (decoded bits; GroupFinderActivity.Flags bits 0x1,0x2,0x4,0x20,0x40,0x80,0x100,0x200,0x400 are set but I found no Blizzard enum, so unknown). The LoreTextPublic.ParentID entries in bits.csv are a false positive: it is an id column.

## Open questions and tests
- In game on Forever: run C_LFGList.GetActivityInfoTable on the 41 category 116 activities to confirm the zone level ranges appear (probe).
- Is a LoreTextPublic chapter shown the moment its quest is complete? Check the Campaign Overview on a character mid-campaign.
- What does Hotfixes Flags 0x1 mean (179 rows)? Needs wowdev or a client trace.
