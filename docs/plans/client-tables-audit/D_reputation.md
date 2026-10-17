# D_reputation: factions, reputation tracks, currencies, garrisons, traits, housing, guilds

Cluster of 134 tables, retail 12.1.5.70391, WoW: Forever 1.60.1.70374, Classic Era 1.15.9.70003 as a reference.
Evidence tags: [TC] TrinityCore source (ReputationMgr.cpp, ConditionMgr.cpp, DBCEnums.h, RaceMask.h), [API] Blizzard API documentation or UI Lua,
[DATA] a count I made over the CSVs, [OUR] agreement with our own data (quests.jsonl, pins.jsonl, qcQuest.lua tables, data\forever\*.jsonl).
Working scripts are in `work\D_reputation\` (decode2.ps1, lib.ps1 and others). Nothing in the repo was changed.

## Summary

1. **Only 9 of the 134 tables matter** (Faction, FriendshipReputation, FriendshipRepReaction, ParagonReputation, RenownRewards, Covenant, CurrencyTypes, plus CHECK for FactionTemplate and TraitCond). The other 125 tables (Garr*, Trait*, Housing, Guild, Perks, Warband, PvpTier, currency categories and containers) have no column that names one of our quests, a quest giver, a map or an availability rule; every one is NO.
2. **The "4 reputation-standing thresholds" are four SLOTS, not thresholds.** Each slot is a (race mask, class mask, base, max, flags) tuple. The game takes the first slot whose race mask is empty or holds the character's race and whose class mask is empty or holds the class [TC GetFactionDataIndexForRaceAndClass]. The rank thresholds themselves (Hated -42000, Hostile -6000, Unfriendly -3000, Neutral 0, Friendly 3000, Honored 9000, Revered 21000, Exalted 42000) are in no table: they are code [TC ReputationRankThresholds], the client only returns them at run time (FactionData.currentReactionThreshold [API]). Friendship tracks are the one exception: their thresholds are rows of FriendshipRepReaction.
3. **Faction reachability can be generated for every race and class.** Of the 437 retail factions that keep a standing, 336 are open to both sides, 51 only to the Alliance, 49 only to the Horde and 1 (Clan Ukhel, a locked placeholder) to nobody; Forever has 75: 45 both, 15 and 15. A side lock is a slot whose base and max are both the same negative number (-42000, hated and at war, flags 6 or 14). Our data: of the 11,965 reward rows in qcQuestReputation, 385 sit on quests open to both sides but reward a faction one side cannot earn (231 quests), and 40 rows contradict the quest's own side (21 Horde-only quests rewarding Alliance factions, 19 the other way: for instance 50338 The G-Team rewards Gnomeregan, 53148 Boulderfist Beatdown rewards both 7th Legion and The Honorbound). Forever: 7 rows nobody can earn (8266 and 8268 Ribbons of Sacrifice, 92415, 92579, 93791, 93797, 93835).
4. **Compare-QuestReputation's "shown" rule is wrong for 498 reward rows (4.2 percent).** It reads ReputationFlags_0 only. Slot 0 of Warsong Offensive, Hellscream's Reach and Wintersaber Trainers is the opposing side's locked, hidden slot, so 193 reward rows on real, visible factions count as hidden; and "Horde" and "Alliance" (flags 25: Visible, Header, Peaceful, no HeaderShowsBar) count as shown on 305 rows although [TC SetVisible] never makes a header without its own bar visible. The rule needs the slot for the character's race and class, and the header test.
5. **Renown, friendship and paragon are keyed three different ways.** Renown level = the character's quantity of `Faction.RenownCurrencyID`, cap = that currency's `MaxQty` (25, 30, 20 ...), standing per level = `ReputationMax` of the slot (2500, 2100, 4200, 4000) [TC GetRenownLevel, GetRenownMaxLevel, GetRenownLevelThreshold]. Friendship rank = 0-based position in `FriendshipRepReaction` sorted by threshold. Paragon = `Faction.ParagonFactionID` names a shell faction whose `ParagonReputation` row holds the threshold and the reward quest. PlayerCondition's reputation columns use the 0-based rank index for both ordinary and friendship factions; its currency columns carry renown (751 conditions, 21 task quests, all ours; confirms data-sources-review rec 17). Our 96 hand renown rows are all valid: every faction has a renown currency or friendship track and no level exceeds the cap.
6. **59 of our quests are paragon cache quests** that the game adds to the log by itself [TC AddQuestAndCheckCompletion]: no giver, no pin (0 of 61). They are typed 128 (29), 2 (26) and 4 (4); the earlier review said all 59 are typed 128. Two more exist that we lack: 93798 (Zul'jarra's Forces) and 95391 (Ritual Sites), both 12.1 Midnight.
7. **Things the earlier review got wrong**: RenownRewards "none ours" (3 are ours: 64508, 64131, 64138, all hidden tracking quests); ParagonReputation "all typed 128" (see 6); "no MajorFaction table in 12.x, the renown tracks are rows of Covenant" is right and I confirm it with the full column decode (Covenant is the track table: FactionID, CurrencyTypesID, BountySetID).
8. **Unused but worthless**: QuestV2CliTask's Filt*Faction columns are all 0 in 6258 rows; RenownFactionID is 0 in all games; GarrMission has no quest link; TraitCond.QuestID names 230 quests of which only 12 are ours (7 hidden "Unlock Ability" tracking quests, 5 Midnight).
9. **Forever reuses the same machinery**: Covenant 46 (PvP Rank, currency 3473, 14 levels) and 48 (Legacy Rank, currency 3485, 90 levels) with 22 RenownRewards rows; faction 2800 "PvP Rank Points" is a renown faction whose per-level standing comes from curve 103650 (0, 750, 900, 1050 ...) through the Forever-only column `RenownThresholdCurveID`, and it also has FriendshipReputation 513 (Rank Points) but no FriendshipRepReaction rows (that table is absent from Forever). Forever and Era cap Exalted at 42999 (Forever 55 slots, Era 44), retail at 42000 (325 slots, 0 at 42999).

## Verdict table (all 134 tables)


Counts: USE 7, CHECK 2, NO 125, CANT-DECODE 0. Games column: rows in each game (retail, Forever, Era); a missing game means the table is absent there.

| Table | Games | Verdict | What it is and why |
|---|---|---|---|
| Faction | retail 870; forever 253; era 209 | USE | Reputation standing slots: ReputationBase, ReputationMax, ReputationFlags and the class and race masks of each of 4 slots decide the start standing, cap and visibility of a faction for each race and class; Flags, ParentFactionMod and ParentFactionCap give spillover; FriendshipRepID, ParagonFactionID and RenownCurrencyID say which track a faction uses. All 186 factions in qcQuestReputation and all 268 names in qcFactions are in it and the names match exactly. Retail 870 rows (437 with a standing), Forever 253 (75), Era 209 (56). |
| FactionTemplate | retail 1865; forever 453; era 367 | CHECK | Creature-side faction (Faction, FactionGroup bitmask 1 Player 2 Alliance 4 Horde 8 Monster, FriendGroup, EnemyGroup, up to 8 enemy and friend factions). Would tell which side a quest giver belongs to, but only 1281 of our 10588 NPC pins reach it through a CreatureDifficulty row; of the 2243 quest rows it can judge only 2 clash with the quest side. Retail 1865 rows, Forever 453, Era 367. |
| FactionGroup | retail 4; forever 4; era 4 | NO | Four-row lookup (Player, Alliance, Horde, Monster) whose ID minus 1 is the bit used by FactionTemplate.FactionGroup; MaskID is an unrelated 0 to 3 index. Needed only to read FactionTemplate. Identical in all three games. |
| FriendshipReputation | retail 103; forever 1 | USE | One row per friendship track (103 retail, 1 Forever): FactionID is the faction (102 of 102 agree with Faction.FriendshipRepID), Flags are text and effect switches (TrinityCore names), the three texts are the standing messages. Gives the link from a faction to its rank list. |
| FriendshipRepReaction | retail 907 | USE | Ranks of every friendship track, 907 rows in 103 tracks: Reaction_lang is the rank name and ReactionThreshold the standing it starts at. PlayerCondition.MinReputation for a friendship faction is the 0-based position in this list sorted by threshold. Retail only; Forever's single track (Rank Points) has no reaction rows. |
| ParagonReputation | retail 79 | USE | Paragon reward quest per paragon shell faction: 79 rows, 61 name a quest, 59 of them are in our data (29 typed 128, 26 typed 2, 4 typed 4, so the earlier review's all typed 128 is wrong), none has a pin. FactionID is the shell faction that the host's Faction.ParagonFactionID names (62 of 63 hosts). LevelThreshold 10000, 7500 or 2500 standing per reward. Retail only. |
| RenownRewards | retail 1398; forever 22 | USE | Rewards per renown level of each track (CovenantID is the track, Level, name, reward ids, Flags, display type in Field_12_0_0_63534_016). 435 rows name a quest (123 quests) as the earlier review said but 3 of those quests ARE in our data (64508 a DNT conduit quest, 64131 and 64138 Tracking Quest), all hidden. 208 rows have a PlayerConditionID (44 conditions; the six commonest, 43 rows, are profession skill gates for crafting knowledge). Forever has 22 rows for its PvP rank and legacy rank tracks. |
| Covenant | retail 35; forever 2 | USE | Despite the name this is the table of renown tracks: ID is the track, FactionID the faction (34 of 35), CurrencyTypesID the renown currency (34), BountySetID the world quest bounty set, RequiredPlayerConditionID the unlock condition. Retail 35 rows from Kyrian to Prey; Forever 2 (PvP Rank 46, Legacy Rank 48). |
| CurrencyTypes | retail 1528; forever 9 | USE | Renown level is the character's quantity of Faction.RenownCurrencyID and the level cap is CurrencyTypes.MaxQty of that currency (25, 30, 20 and so on; none of our 96 hand renown rows exceeds it). AwardConditionID, FactionID (106 rows, none a renown pair) and Flags_0 and Flags_1 (TrinityCore names, include IsAllianceOnly 0x10000000, IsHordeOnly 0x20000000, AccountWide 0x1000000) are the rest. Retail 1528 rows, Forever 9. |
| CurrencyCategory | retail 41; forever 6 | NO | UI grouping of currencies by expansion (ExpansionID, ParentCategoryID, Flags). Presentation only; category 142 Hidden holds the renown and war-campaign currencies. |
| CurrencyContainer | retail 135 | NO | 135 commendation or cache containers (a currency amount range turned into a named reward). Rewards only, no quest link. |
| DecorCategory | retail 10 | NO | Housing decor catalogue category (10 rows). Presentation. |
| DecorDyeSlot | retail 683 | NO | Dye slots of housing decor (683). Presentation. |
| DecorSubcategory | retail 31 | NO | Housing decor subcategory (31). Presentation. |
| DecorXDecorSubcategory | retail 3530 | NO | Decor to subcategory join (3530). Presentation. |
| GarrAbility | retail 833 | NO | Garrison follower abilities (833); no quest link. |
| GarrAbilityCategory | retail 11 | NO | Follower ability categories (11). |
| GarrAbilityEffect | retail 1035 | NO | Follower ability effects (1035). |
| GarrAutoCombatant | retail 363 | NO | Shadowlands auto-combat units (363). |
| GarrAutoSpell | retail 374 | NO | Auto-combat spells (374). |
| GarrAutoSpellEffect | retail 473 | NO | Auto-combat spell effects (473). |
| GarrBuilding | retail 76 | NO | Garrison buildings (76); GameObject ids of the buildings, not quest givers. |
| GarrBuildingDoodadSet | retail 52 | NO | Building doodad sets (52). Art. |
| GarrBuildingPlotInst | retail 598 | NO | Building plot instances (598). |
| GarrClassSpec | retail 273 | NO | Follower class and spec names (273). |
| GarrClassSpecPlayerCond | retail 70 | NO | Class spec to PlayerCondition (70); all 70 conditions are missing from PlayerCondition. |
| GarrEncounter | retail 2626 | NO | Mission encounter creatures (2626). |
| GarrEncounterSetXEncounter | retail 541 | NO | Encounter set join (541). |
| GarrEncounterXMechanic | retail 2992 | NO | Encounter mechanics join (2992). |
| GarrFollItemSetMember | retail 558 | NO | Follower item sets (558). |
| GarrFollower | retail 1053 | NO | Garrison followers (1053): creature ids of followers, CovenantID, class; followers are not quest givers. |
| GarrFollowerLevelXP | retail 85 | NO | Follower XP curve (85). |
| GarrFollowerQuality | retail 36 | NO | Follower quality (36). |
| GarrFollowerSetXFollower | retail 12 | NO | Follower sets (12). |
| GarrFollowerType | retail 5 | NO | Follower types (5). |
| GarrFollowerUICreature | retail 1819 | NO | Follower UI creatures (1819). Art. |
| GarrFollowerXAbility | retail 3202 | NO | Follower to ability join (3202). |
| GarrFollSupportSpell | retail 66 | NO | Follower support spells (66). |
| GarrItemLevelUpgradeData | retail 18 | NO | Follower item upgrades (18). |
| GarrMechanic | retail 104 | NO | Mission mechanics (104). |
| GarrMechanicSetXMechanic | retail 68 | NO | Mechanic sets (68). |
| GarrMechanicType | retail 89 | NO | Mechanic types (89). |
| GarrMission | retail 1757 | NO | 1757 garrison and command-table missions (offered with a PlayerConditionID, a cost currency and a duration). They are not quests: no column names a QuestV2 id, a creature giver or a UiMap; MapPos is the mission's table position. |
| GarrMissionSet | retail 205 | NO | Mission sets (205). |
| GarrMissionTexture | retail 26 | NO | Mission art (26). |
| GarrMissionType | retail 78 | NO | Mission types (78). |
| GarrMissionXEncounter | retail 4141 | NO | Mission encounter join (4141). |
| GarrMissionXFollower | retail 24 | NO | Mission follower join (24). |
| GarrMssnBonusAbility | retail 23 | NO | Mission bonus abilities (23). |
| GarrPlot | retail 8 | NO | Garrison plots (8). |
| GarrPlotBuilding | retail 75 | NO | Plot to building (75). |
| GarrPlotInstance | retail 15 | NO | Plot instances (15). |
| GarrPlotUICategory | retail 3 | NO | Plot UI categories (3). |
| GarrSiteLevel | retail 30 | NO | Garrison site levels (30) with the MapID of the garrison; not quest data. |
| GarrSiteLevelPlotInst | retail 40 | NO | Site level plot join (40). |
| GarrSpecialization | retail 26 | NO | Building specialisations (26). |
| GarrString | retail 78 | NO | Flavour strings (78). |
| GarrTalent | retail 951 | NO | Order hall and sanctum talents (951); PlayerConditionID on 623 rows (12 rows use faction conditions); not quests. |
| GarrTalentCost | retail 2782 | NO | Talent costs (2782). |
| GarrTalentMapPOI | retail 24 | NO | Talent map points (24). |
| GarrTalentRank | retail 1034 | NO | Talent ranks (1034). |
| GarrTalentRankGroupEntry | retail 9 | NO | Rank group entries (9). |
| GarrTalentRankGroupResearchMod | retail 9 | NO | Research modifiers (9). |
| GarrTalentResearch | retail 20 | NO | Talent research (20). |
| GarrTalentSocketProperties | retail 3 | NO | Talent sockets (3). |
| GarrTalentTree | retail 91 | NO | Talent trees of orders and sanctums (91); CurrencyID and a PlayerConditionID; not quests. |
| GarrTalTreeXGarrTalResearch | retail 20 | NO | Join (20). |
| GarrType | retail 4 | NO | Four garrison types (WoD, Legion, BfA, Shadowlands) with currencies and maps. |
| GarrUiAnimClassInfo | retail 93 | NO | Follower animation art (93). |
| GarrUiAnimRaceInfo | retail 64 | NO | Follower animation art (64). |
| GuildColorBackground | retail 51; forever 51 | NO | Guild tabard colours (51 retail and Forever). Art. |
| GuildColorBorder | retail 17; forever 17 | NO | Guild tabard colours (17). Art. |
| GuildColorEmblem | retail 17; forever 17 | NO | Guild tabard colours (17). Art. |
| GuildEmblem | retail 196; forever 196; era 196 | NO | Guild emblem files (196 in all three games). Art. |
| GuildPerkSpells | retail 5 | NO | Five guild perk spells. No quest link. |
| GuildShirtBackground | retail 459; forever 459 | NO | Guild shirt art (459). |
| GuildShirtBorder | retail 459; forever 459 | NO | Guild shirt art (459). |
| GuildTabardBackground | retail 306; forever 306; era 306 | NO | Guild tabard art (306). |
| GuildTabardBorder | retail 916; forever 916; era 916 | NO | Guild tabard art (916). |
| GuildTabardEmblem | retail 6664; forever 6664; era 6664 | NO | Guild tabard art (6664). |
| House | retail 1; era 1 | NO | Player housing: one row in retail and in Era, a name and unnamed fields. |
| HouseDecor | retail 3158 | NO | 3158 housing decor items (GameObjectID, ItemID, weight cost, first-time XP). Decor is not a quest; the quests that grant decor sit in RetroactiveDecorReward (136 quests, 135 ours, all typed 1; outside this cluster) and are ordinary quests. |
| HouseDecorMaterial | retail 1080 | NO | Decor materials (1080). Art. |
| HouseDecorThemeSet | retail 3 | NO | Decor themes (3). |
| HouseExteriorWmoData | retail 8 | NO | House exterior models (8) with an unlock item. |
| HouseLevelRewardInfo | retail 12 | NO | Rewards for house levels (12); the level table HouseLevelData (outside this cluster) names 5 quests, 2 ours. |
| HouseRoom | retail 41 | NO | House rooms (41). |
| HouseTheme | retail 17 | NO | House themes (17). |
| NeighborhoodInitiative | retail 17 | NO | Neighbourhood initiatives (17); its tasks name 7 quests (InitiativeTask, outside this cluster), 5 ours. |
| NeighborhoodMap | retail 4 | NO | Four neighbourhood maps (Map ids 2640 to 2783). |
| NeighborhoodNameGen | retail 39 | NO | Name generator (39). |
| NeighborhoodPlot | retail 114 | NO | Neighbourhood plots (114): plot and cornerstone GameObjects. |
| PerksUITheme | retail 11 | NO | Trading post UI themes (11). |
| PerksVendorCategory | retail 6 | NO | Trading post categories (6). |
| PerksVendorItem | retail 1382 | NO | Trading post items (1382); item sales, not quests. |
| PerksVendorItemUIGroup | retail 37 | NO | Trading post UI (37). |
| PerksVendorItemUIInfo | retail 6 | NO | Trading post UI (6). |
| PerksVendorItemXInterval | retail 1963 | NO | Trading post intervals (1963). |
| PvpTier | retail 45 | NO | PvP rating tiers (45 retail): MinRating, MaxRating, Rank, BracketID. Rating bands, no quest link. |
| RenownRewardsPlunderstorm | retail 52 | NO | Plunderstorm event renown rewards (52, track 23); event over. |
| TraitCond | retail 10971; forever 172 | CHECK | Conditions that unlock talent nodes. QuestID is set on 1400 rows for 230 quests, only 12 of them ours: 7 are the Unlock Ability 1 to 7 quests (typed 1, category 0, level 80, tracking quests by name) and 5 are Midnight quests (95549, 95550, 95552, 95553, 97321) that unlock an ability. Useful only to prove the 7 are hidden tracking quests. Forever has 172 rows with no quest. |
| TraitCondAccountElement | retail 438 | NO | Account-wide talent conditions (438). No quest ids. |
| TraitCost | retail 1511; forever 11 | NO | Talent costs (1511). |
| TraitCurrency | retail 1361; forever 2 | NO | Talent currencies (1361). |
| TraitDefinition | retail 17042; forever 658; era 9 | NO | Talent definitions (17042): spell and names. |
| TraitDefinitionEffectPoints | retail 1408; forever 644 | NO | Talent effect points (1408). |
| TraitEdge | retail 7280; forever 98 | NO | Talent graph edges (7280). |
| TraitNode | retail 11878; forever 558; era 9 | NO | Talent nodes (11878). |
| TraitNodeEntry | retail 17150; forever 659; era 9 | NO | Talent node entries (17150). |
| TraitNodeEntryXTraitCond | retail 545 | NO | Node entry to condition (545). |
| TraitNodeEntryXTraitCost | retail 1863 | NO | Node entry to cost (1863). |
| TraitNodeGroup | retail 2544; forever 368; era 3 | NO | Talent node groups (2544). |
| TraitNodeGroupDisplayInfo | forever 27 | NO | Forever only: display info (27) with SkillLineID. |
| TraitNodeGroupXTraitCond | retail 2438; forever 171 | NO | Group to condition (2438). |
| TraitNodeGroupXTraitCost | retail 130 | NO | Group to cost (130). |
| TraitNodeGroupXTraitNode | retail 19076; forever 2150; era 9 | NO | Group to node join (19076). |
| TraitNodeXTraitCond | retail 8026; forever 1 | NO | Node to condition (8026). |
| TraitNodeXTraitCost | retail 226 | NO | Node to cost (226). |
| TraitNodeXTraitNodeEntry | retail 14127; forever 561; era 9 | NO | Node to entry join (14127). |
| TraitSubTree | retail 87 | NO | Hero talent sub trees (87). |
| TraitSystem | retail 33; forever 2 | NO | Trait systems (33 retail, 2 Forever). |
| TraitTree | retail 196; forever 17; era 1 | NO | Trait trees (196 retail, 17 Forever: Forever has class talent trees). Skyriding is tree 672. |
| TraitTreeLoadout | retail 78 | NO | Talent loadouts (78). |
| TraitTreeLoadoutEntry | retail 4531 | NO | Loadout entries (4531). |
| TraitTreeXTraitCost | retail 2; forever 13 | NO | Tree to cost (2 retail, 13 Forever). |
| TraitTreeXTraitCurrency | retail 1307; forever 13 | NO | Tree to currency (1307 retail, 13 Forever). |
| WarbandPlacementDisplayInfo | retail 10 | NO | Warband scene art (10). |
| WarbandScene | retail 14 | NO | Warband scene settings (14). |
| WarbandSceneAnimation | retail 48; forever 1 | NO | Scene animations (48 retail, 1 Forever). |
| WarbandSceneAnimChrSpec | retail 55 | NO | Scene animation specs (55). |
| WarbandScenePlacement | retail 113 | NO | Scene placements (113). |
| WarbandScenePlacementFilterReq | retail 6 | NO | Placement filters by race mask (6). |
| WarbandScenePlacementOption | retail 115 | NO | Placement options (115). |
| WarbandSceneSourceInfo | retail 5 | NO | Scene sources (5). |

## Per-table sections

### Faction (retail 870 rows, Forever 253, Era 209; same 31-column layout in all three, Forever adds RenownThresholdCurveID)

Layout [WoWDBDefs, TC FactionEntry]: ID, Name, Description, ReputationIndex, ParentFactionID, Expansion, FriendshipRepID, Flags, ParagonFactionID, RenownFactionID, RenownCurrencyID, and four-element arrays ReputationClassMask, ReputationFlags, ReputationBase, ReputationMax, two-element ParentFactionMod and ParentFactionCap, and four race masks of two int32 each (`ReputationRaceMasks{slot}_{0|1}` = low and high 32 bits of a 64-bit mask). Column by column detail, evidence and confidence are in `D_reputation-columns.csv`; every set bit is in `D_reputation-bits.csv`; every faction with a standing decoded into readable slots is in `D_reputation-faction-slots.csv` (retail 437 rows and Forever 75, with a side-reachability class).

**What "has a standing" means.** `ReputationIndex >= 0` [TC CanHaveReputation]: 437 of 870 retail rows, 75 of 253 Forever, 56 of 209 Era; the values are unique. The other 433 retail rows are creature-template factions that never hold a standing (monsters, test rows, "Friendly, Hidden").

**Slot rule [TC GetFactionDataIndexForRaceAndClass].** For i = 0 to 3 take slot i if (its race mask is empty or has the character's race bit) and (its class mask is 0 or has the class bit). First hit wins; no hit means no standing. The race bit is `ChrRaces.PlayableRaceBit` (Human 0 ... Draenei 10, Dark Iron 11, Vulpera 12, Mag'har 13, Mechagnome 14, Dracthyr Horde 15 and Alliance 16, Earthen Horde 17 and Alliance 18, Haranir Horde 19 and Alliance 20, Worgen 21, Pandaren neutral 23, Pandaren Alliance 24 and Horde 25, Nightborne 26 ... Kul Tiran 31; Forever also High Order Skyborne 32 and Windshaper Skyborne 33) [TC RaceMask::GetRaceBit, ChrRaces]. The class bit is class id minus 1 [TC], the same convention as our qcClassBits. Mask 0, or class mask -1, means everybody. The Alliance mask is `0x55155555B1354C4D` and the Horde mask `0xAA2AAAAA4E0AB3B2` in both games (the high word carries Skyborne in Forever). Two quirks: an empty trailing slot matches everybody, so neutral Pandaren (bit 23, in neither side mask) fall into it and get base 0, max 0, flags 0 on side-locked factions; and slot flags differ per slot, so "is this faction hidden" has no single answer.

**Slot contents.** Standing = Base + stored standing [TC GetReputation]; Max is the cap [TC GetMaxReputation]; a slot whose Base equals Max and is negative (-42000/-42000, flags 6 or 14) is a lock: the faction of the other side, hated and at war, no gain possible. Patterns measured over all 437 retail factions (145 signatures, top ones):

| Pattern | Factions | Meaning |
|---|---|---|
| all races, base 0, max 42000, flags 16 | 145 | an ordinary faction (one signature of 145 distinct ones) |
| all races, base 0, max 2500, flags 16 | 17 | a Dragonflight or War Within renown track: Max is the standing per renown level |
| one side open, the other side locked (-42000/-42000, flags 6 or 14) | 100 (51 Alliance, 49 Horde) | a one-side faction |
| race-specific slot 2 (the racial leader's own people) | 23 | Stormwind: Alliance 3100, Human and Kul Tiran 4000, Horde locked; Orgrimmar: Horde 3100, Orc and Mag'har 4000, Undead and Blood Elf 500; Aldor: Draenei 3500, Blood Elf -3500 and Scryers the mirror; Gnomeregan: Gnome and Mechagnome 4000; Kul Tiras factions: Kul Tiran 9000 |
| capital-city flag 0x100 (flags 273 = 0x100 + 0x10 + 0x1) | 18 | the racial capitals and their kin |
| a class mask other than all | 5 | Knights of the Ebon Blade: Death Knight 3200; Kirin Tor: Mage 3000; Cenarion Circle: Druid 2000; Illidari: Demon Hunter 3000; Hozen |
| header: 0x8 without 0x80 (never visible) | 22 | Horde, Alliance, Steamwheedle Cartel, Shattrath City, the expansion group rows |
| header with its own bar: 0x8 with 0x80 | 14 | The Tillers, The Anglers, Valdrakken Accord, The Severed Threads and others |
| three or more filled slots | 25 | the racial and class cases above |

Of the 437 standing factions, 266 are plain, 102 use a friendship track, 32 a renown currency and 62 are paragon hosts (the groups overlap: The Weaver is friendship and paragon at once).

Consequence for a "requires reputation" filter: a Neutral (0) requirement is met on day one only where the slot base is 0 or more (Timbermaw Hold starts at -2900, Blood Elves start Aldor at -3500); a requirement above the slot's Max can never be met (18 retail standard factions are capped below Exalted: ten profession-specialisation factions at 3000 such as "Engineering - Gnome", Akama's Trust at 1000 and so on; none of them is in retail's reward data and Forever's reward data has three such rows: 551 Engineering - Gnome twice and 550 Engineering - Goblin once); a requirement on a faction whose slot is locked for the character's side can never be met and can be reported as "needs the other faction". The Forever counts are 13 capped standard factions.

**ReputationFlags (per slot).** Decoded in the bits file. The commonly relevant ones: Hidden 0x4, Header 0x8 without HeaderShowsBar 0x80 (never visible), Peaceful 0x10, CapitalCityForRaceChange 0x100 (18 rows), 0x400 GarrisonInvasion (7 rows), and 0x800 and 0x1000 which only appear in retail (clan reputations and expansion headers; meaning is a guess).

**Faction.Flags (retail 7 bits, Forever 5 rows).** Only 0x4 has a plausible meaning (probably account-wide/warband standing: 186 rows, none with an ID below 1815, plus the test faction "Test Account Wide Stormwind"); the others are guesses. They do not change a quest filter.

**Parent and spillover.** ParentFactionID points at a header that exists (0 orphans). ParentFactionMod[1] is the share of its own gain a faction gives its sister factions (0.25 for capital cities, 0.5 for Warsong Offensive and Valiance Expedition), ParentFactionMod[0] the share the receiver takes, ParentFactionCap[0] the highest rank at which it still takes it [TC SetReputation]. Our 11,965 reward rows include 4,073 (3,781 quests, 30 factions) on factions that spill over: Stormwind 478, Orgrimmar 472, Darnassus 316, Undercity 296, Bilgewater Cartel 264, Valiance Expedition 263.

**Relationships (verified).** ParentFactionID, ParagonFactionID, RenownFactionID to Faction; FriendshipRepID to FriendshipReputation (102 of 102 agree both ways); RenownCurrencyID to CurrencyTypes (33 of 33 resolve); Covenant.FactionID, CurrencyTypes.FactionID, ItemSparse.MinFactionID, PlayerCondition.MinFactionID and MaxFactionID, FactionTemplate.Faction and Friend and Enemies columns point back. Undeclared ones worth noting: refs.csv adds only noise (TraitCond.SpentAmountRequired and similar, ByChance high). Contradicted declared FK: none in this cluster; GarrClassSpecPlayerCond.PlayerConditionID is declared but 0 of 70 values exist (a stale table).

**Differences between games.** Forever: 75 standing factions, no Expansion (all 0), no friendship ranks table, Faction rows for the Skyborne (2778 Windshapers, 2779 High Order, both racial leaders with base 3100), commerce factions 2586 and 2587, the PvP rank track 2800 and the legacy track 2802, Exalted cap 42999. Era has the same columns with the new-track columns all zero (Era race masks are the old 8-bit values such as 255, 77, 178 and its Exalted cap is 42999). The 4 slots and the high race word work the same way in Forever (their high word holds the Skyborne bits).

### Renown, friendship, paragon: how ranks are keyed

* **Renown** [TC IsRenownReputation, GetRenownLevel, GetRenownMaxLevel, GetRenownLevelThreshold]: level is the character's quantity of `Faction.RenownCurrencyID` (33 retail rows, 2 Forever); cap is that currency's `CurrencyTypes.MaxQty` (Maruuk Centaur 25, Valdrakken Accord 30, Cartels of Undermine 20); standing per level is the slot's `ReputationMax` (2500, 4200 for delves, 4000 for Prey, 2100 for the Labyrinth). The faction's `Covenant` row (the track: FactionID, CurrencyTypesID, BountySetID) holds the rewards through `RenownRewards(CovenantID, Level)`. The currency does not point back (`CurrencyTypes.FactionID` is set on 106 currencies, none of them a renown pair).
* **Friendship** [TC ReputationToRank, GetReputationRankName]: the track's `FriendshipRepReaction` rows sorted by threshold; rank index is the position (0-based) and the name is `Reaction_lang`. Tracks seen: 6 ranks (Stranger to Best Friend, thresholds 0, 8400 ... 42000), 9 for The Weaver, The General, The Vizier (0, 2500 ... 20000, Stranger to Mastermind), 100 levels for Brann Bronzebeard, 80 for Valeera Sanguinar, 30 for the Nazjatar allies.
* **Paragon** [TC GetMaxReputation, CanGainParagonReputationForFaction, SetReputation]: host `Faction.ParagonFactionID` names a shell faction; the shell's `ParagonReputation` row has `LevelThreshold` and the reward `QuestID`; the quest is given automatically each time standing / threshold increases; the host must be at Exalted or max renown. Shells have flags 16 and a small or zero max (0, 2500, 7500).
* **PlayerCondition** [TC ConditionMgr.cpp 3019 to 3058]: `MinFactionID_n` with `MinReputation_n` is a faction and the minimum rank index (ordinary factions 0 to 7; friendship factions the 0-based position, so The Weaver 7 is Conspirator and 8 Mastermind), `MaxFactionID` with `MaxReputation` a maximum rank (values 0 to 3), `ReputationLogic` combines the four results (two bits per link, 1 AND and 2 OR in the low 16 bits, the high 16 bits invert operands: value 65536 on 42 rows is NOT). `CurrencyID_n` with `CurrencyCount_n` is a renown level when the currency is a renown currency (751 retail conditions; 21 task quests through QuestV2CliTask.ConditionID, all 21 ours). Four conditions use a rank index equal to or above the track's rank count (Chromie 7 of 7, Ve'nari 6 and 7 of 6): they can never be met or the track was shortened. Counts of faction-related conditions: retail 422 conditions use a faction (411 have MinFactionID_0 naming 97 distinct factions, 26 have MaxFactionID), Forever 97 faction slots in 85 conditions; 8 task quests use a faction condition (94796 to 94806 family, faction 2773 Captain Tokka rank 1), and `QuestV2CliTask.FiltMinFactionID/FiltMaxFactionID` are zero on all 6258 rows.
* **ModifierTree faction types** [TC CriteriaHandler]: 62 guild reputation (201 rows, Asset = raw standing), 88 Cloud Serpent (38), 94 friendship reaction met (193, Asset = FriendshipRepReaction id), 95 reputation with Faction Asset at least SecondaryAsset raw standing (440 retail, 16 Forever; thresholds 3000, 9000, 21000, 42000 dominate), 119 currency held (1186, 279 on a renown currency), 221 paragon level (74), 254 friendship reaction exactly (5). They belong to B_conditions; the counts are only to show the same keys appear there.

### FriendshipReputation, FriendshipRepReaction

103 tracks, 907 reactions in retail; 1 track and no reactions in Forever (Rank Points, faction 2800, flags 0); absent from Era. `FriendshipReputation.Flags` is [TC FriendshipReputationFlags]: 0x1 NoFXOnReactionChange, 0x2 NoLogTextOnRepGain, 0x4 NoLogTextOnReactionChange, 0x8 ShowRepGainandReactionChangeForHiddenFaction, 0x10 NoRepGainModifiers. Today only the live API supplies rank names (the addon calls `C_GossipInfo.GetFriendshipReputationRanks`). The table would give the English rank names for a rank requirement without a hand table, but the client already localises them at run time, so the value is verification only: 0 of our 96 hand renown rows needs it.

### ParagonReputation

79 rows: 61 name a reward quest, 16 have no faction (14 with threshold 10000, 2 with 0: unused rows), 18 have no quest (those 16 and two shell rows, Clan Nokhud and Keg Leg's Crew paragons). 59 of the 61 quests are ours; 0 have pins; 2 are missing (93798 Zul'jarra's Forces and 95391 Ritual Sites, both rows added for 12.1 Midnight). Host expansion split: Legion and earlier 33, Dragonflight 6, War Within 16, Midnight 6. The 62nd host (2063 "Arne Test - Paragon Reputation Stormwind") has no row. No Forever or Era rows.

### RenownRewards, Covenant, RenownRewardsPlunderstorm

`Covenant` is the renown track table (35 retail rows: 1 to 4 the Shadowlands covenants, 12 to 23 Dragonflight, 24 to 35 War Within and its seasons, 36 to 55 Midnight, delve and prey seasons; Forever 46 PvP Rank and 48 Legacy Rank). `RenownRewards` (1398 rows) holds the reward per level; `Field_12_0_0_63534_016` is the reward display type, proven against the API enum (1 Item co-occurs with ItemID on 130 of 172 rows, 2 Spell 24 of 24, 3 Mount 36 of 36, 5 TransmogSet 65 of 68, 7 Title 19 of 19, 8 follower 37 of 37) [API Enum.RenownRewardDisplayType]. 435 rows name a quest (123 quests; 288 rows are 64508 "[DNT] Conduit Energy"); 3 of the 123 are ours, all hidden. `PlayerConditionID` on 208 rows (class bits, race bits, profession skill). This is the only table that names the renown level at which Dragonflight/War Within crafting knowledge unlocks (43 rows on six profession skill conditions), which is what data-sources-review already planned.

### CurrencyTypes, CurrencyCategory, CurrencyContainer

Flags decoded [TC CurrencyTypesFlags and B]: 0x2 AppearsInLootWindow (323), 0x80 TrackQuantity (66), 0x40000 DynamicMaximum (75, includes the renown currencies), 0x1000000 AccountWide (85), 0x10000000 IsAllianceOnly (7th Legion Service Medal 1717, Operation: Shieldwall 2909), 0x20000000 IsHordeOnly (Honorbound Service Medal 1716, Dominance Offensive 2908). Currencies matter to us only as renown levels (PlayerCondition currency columns) and as the cap of those levels. `CurrencyContainer` is a reward wrapper (commendations); `CurrencyCategory` groups by expansion for the UI.

### FactionTemplate, FactionGroup

FactionTemplate (retail 1865, Forever 453, Era 367) is the creature faction. `FactionGroup` is a bitmask: 1 Player, 2 Alliance, 4 Horde, 8 Monster (FactionGroup table rows 1 to 4, bit = 1 shifted by ID minus 1); FriendGroup and EnemyGroup use the same bits. Reaching it from a quest giver needs `CreatureDifficulty.FactionTemplateID`, which exists for 23,140 retail creatures but only 1,281 of our 10,588 NPC pins (12 percent): of the 2,243 quest-pin rows that can be judged, 2 contradict the quest's side (npc 100866 Lady Sylvanas Windrunner for 56982 and npc 122370 Cyrus Crestfall for 52184). Forever's CreatureDifficulty has 11 KB: unusable. Verdict CHECK, low value.

### TraitCond and the other Trait tables

`TraitCond.QuestID` is set on 1,400 rows (230 quests; Forever none): talent nodes that unlock when a quest is done. Of the 230, 12 are in our data: 92087 to 92093 "Unlock Ability 1 - Level 2" to "7 - Level 8" (typed 1, category 0, level 80, names say tracking) and five Midnight quests 95549, 95550, 95552, 95553 and 97321 (category 1512, level 90). The other 218 are not in our data (hidden unlock quests). Trait trees are talents (Skyriding is tree 672; Forever has 17 trees, 9 of them on trait system 10). No other Trait* column touches quests, maps or availability.

### Garrison, housing, guild, perks, warband

GarrMission (1,757 missions) has PlayerConditionID, a cost currency, a duration and AreaID but no quest, giver or UiMap column; GarrFollower has creature ids of followers; GarrTalent and GarrTalentTree have conditions on talents. Housing: the decor and house tables carry items, game objects and art; the quest links live outside this cluster (RetroactiveDecorReward 136 quests, 135 ours, all typed 1; InitiativeTask 7 quests, 5 ours; HouseLevelData 5 quests, 2 ours). Guild tables are tabard art (Forever and Era share them), Perks is the trading post item list, Warband is scene art. AdventureMapPOI and AdventureJournal (outside this cluster, in my brief) name 151 and 341 quests, 144 and 298 ours; the 54 normal ones of AdventureMapPOI are the Legion zone intro quests (31 already pinned): no new position data for Midnight.

## Opportunities, ranked

1. **Hide or mark reward rows the character cannot earn (retail and Forever).** Retail: 385 rows (231 quests, 28 factions: Horde 87 and Alliance 87, Dark Talons 56, Obsidian Warders 55, Undercity 15, Council of Exarchs 13, Storm's Wake 11, Vol'jin's Spear 7 ...) plus 40 contradictions list a faction that one side or race cannot earn, with the tooltip showing it to everybody. Fix: a small generated table of the 100 side-locked factions (51 Alliance, 49 Horde; 59 of them occur in our reward data) or the slot test at run time, and a review of the 40 contradictions (file `D_reputation-side-mismatch.csv`, every row with quest, quest side bits, faction, amount). Forever: 589 of 2,333 rows are not earnable by every race the quest allows (both-faction rows on both-side quests), 7 by none. Needs no in-game test for the retail rows with an ordinary Alliance or Horde faction; the 40 contradictions need a look at which side is wrong.
2. **Correct the reputation "shown" rule** in Compare-QuestReputation.ps1 (and Test-CompareQuestReputation): use the slot of the faction's earnable slots, not ReputationFlags_0, and treat a header without bit 0x80 as not shown. Affects 193 + 305 = 498 reward rows (Warsong Offensive 153, Hellscream's Reach 34, Wintersaber Trainers 6 become shown; Horde 153 and Alliance 152 become not shown). Retail only, because Forever's equivalent is Horde 64 and Alliance 60 rows. Needs one in-game look: does a Horde character see a "Horde" reputation row after a Silvermoon quest? (Blizzard's rep pane will tell.)
3. **Generate renown and friendship requirements** (data-sources-review rec 17; confirmed): PlayerCondition currency columns on renown currencies (751 conditions) reach 21 task quests, all ours; the hand table (96 rows, 8 factions) is internally valid (0 levels above the cap) but lacks the Midnight and later factions: Amani Tribe 2696, Hara'ti 2704, Silvermoon Court 2710, The Singularity 2699, Zul'jarra's Forces 2772, Ritual Sites 2792 and the delve and prey seasons; Seven Dragonflight renown factions (Maruuk 2503, Dragonscale 2507, Valdrakken 2510, Iskaara 2511, Loamm Niffen 2564, Dream Wardens 2574, Keg Leg 2593) are absent from the hand table too.
4. **Mark the 59 paragon cache quests** (29 typed 128, 26 typed 2, 4 typed 4) as automatic: no giver, no pin, available only at Exalted or max renown (host from `Faction.ParagonFactionID`), and add the two missing Midnight ones (93798, 95391). A one-line tooltip "Given automatically at Exalted with X" for each; 0 pins now, so nothing disappears from the map.
5. **Static start-standing and cap check for future standing requirements** (rec 24): a requirement value at or below the character's slot base is met from the start; above the slot's Max (18 retail and 13 Forever standard factions are capped below Exalted) can never be met. Needs the slot base per race (available now, retail 437 and Forever 75 rows in the slots file). No requirement data exists yet in the repo to measure against, so I cannot count quests.
6. **Spillover line in the reward tooltip**: 4,073 reward rows (3,781 quests) on 30 spilling factions. Display-only; no in-game proof that the 25 percent applies in 12.1.5 (TrinityCore code only), so a probe line would settle it.
7. **Hidden tracking quest proof**: TraitCond names 92087 to 92093 as unlock quests; 7 quests in our data. Review before removal (user rule), no other value.

## Things that look like they should exist but do not

* A table of the rank thresholds (-42000 ... 42000): code only; only `C_Reputation.GetFactionDataByID` gives them at run time.
* A table of reputation requirements per quest: the client DB has none; `QuestV2CliTask.Filt*Faction` is empty. Quest min and max reputation live only in the quest cache or the server (data-sources-review rec 24).
* A per-quest reputation reward amount: not in this cluster (QuestFactionReward is read for Forever already).
* A race reputation bonus (Human Diplomacy): in spells, not here.
* MajorFaction table: the client has none; Covenant is the track table.
* Standing for header factions without a bar: stored but never visible.

## Open questions and the in-game test that settles each

1. Does a Horde character see a standing row for "Horde" / "Alliance" (flags 25, no HeaderShowsBar) after a quest reward? `/run local d=C_Reputation.GetFactionDataByID(67) print(d and d.name, d and d.isHeader, d and d.isHeaderWithRep)` on a Horde and an Alliance character (both games), and read the rep pane.
2. Which quest side is wrong in the 40 contradictions: open one quest on each side (53148 and 53146 are the clear pair); the quest log's reputation line decides.
3. Is Faction.Flags 0x4 account-wide? `/run print(C_Reputation.IsAccountWideReputation(2503), C_Reputation.IsAccountWideReputation(72))` against a few ids with and without the bit (1828 has it, 72 does not).
4. Does the 25 percent spillover hold in 12.1.5? Do a Stormwind quest and read the other Alliance cities' standing before and after.
5. Neutral Pandaren: before level 10 they match no slot on side-locked factions (empty trailing slot, base 0 and max 0); check one new character's standing with Stormwind via the pane.
6. Are 93798 and 95391 live in 12.1.5 or PTR only? (They sit in a table with the other 12.1 rows; a recorder hit would show.)

