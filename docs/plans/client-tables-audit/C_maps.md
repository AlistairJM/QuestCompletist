# Cluster C_maps: geography tables (83 tables)

Builds: retail 12.1.5.70391, Forever 1.60.1.70374, Era 1.15.9.70003. Companion files: `C_maps-verdicts.csv` (83 rows), `C_maps-columns.csv` (117 column rows), `C_maps-bits.csv` (98 decoded bits/enums). Scratch scripts: `work\C_maps\m*.ps1`. Evidence tags: (a) Blizzard API docs / UI Lua, (b) TrinityCore source (fetched `DBCEnums.h`, `DB2Stores.cpp`, saved in `work\C_maps`), (d) empirical count, (e) agreement with our data.

## Summary

- 83 tables: 11 USE, 7 CHECK, 65 NO (art, light, audio, transport, waypoint, journal loot and ability text).
- **Geography cannot give NPC/giver positions.** No client table holds creature spawns. What it gives: the maths to turn any world coordinate into a UiMap point (`UiMapAssignment`), dungeon/raid door positions, zone trees and flags.
- The one real gap it fills: **dungeon and raid entrance points**. Retail has them twice (`JournalInstanceEntrance` 203 rows, `AreaPOI` with `PoiDataType` 1 = 202 rows; together 208 of 216 journal instances). Forever has no Journal tables, but `Map.Corpse_0/1` + `CorpseMapID` is the door position (26 of 50 dungeon/raid maps), and it agrees with retail's entrance table (83 of 100 within 100 yd, median 9.5 yd). Our unpinned quests in instances with such a point: **444 retail** (of 476 unpinned in 174 instance categories, 1,267 quests), **132 Forever** (of 142 unpinned in 16 instance categories, 342 quests).
- **Faction verifier:** `AreaTable.FactionGroupMask` (2 Alliance, 4 Horde, 6 both) agrees with our quest faction in 22,550 checked quests: mask 2 zones hold 345 Alliance-only vs 11 Horde-only quests, mask 4 hold 344 Horde-only vs 9 Alliance-only. 54 retail and 109 Forever quests our data calls "both" sit in a faction zone; unused today.
- **Phase gating:** `UiMap.VisibilityPlayerConditionID` gates 36 maps; 21 of them carry **1,003 of our 16,084 pins (1,381 quests)** (old/new Eversong, Teldrassil, Uldum, Maw...). Never read.
- **Blizzard's world-to-UiMap algorithm** is fully readable (TrinityCore `GetUiMapPosition`, documented below). Our pipeline relies on the blob's own UiMapID; the proper selection matters for any source without one.
- Forever UiMap = Era's 54 maps + 6 new (Mount Hyjal, Zephras Isle x2, Darkspear Islands, Riverglades, Shen'dralas): 50 zones + 1 taxi map, **no dungeon maps at all** (retail has 897 dungeon-type maps). All 1,701 Forever pins are on those maps.

## Verdict table

See `C_maps-verdicts.csv` for one line per table. Compact list:

USE: AreaPOI, AreaTable, JournalInstance, JournalInstanceEntrance, JournalTier, JournalTierXInstance, Map, UiMap, UiMapAssignment, UiMapGroup, UiMapGroupMember.
CHECK: DungeonEncounter, MapDifficulty, MapDifficultyXCondition, UiMapLink, UiMapXMapArt, WMOAreaTable, WorldMapOverlay.
NO (65): AreaGroupMember, AreaPOIState, AreaPOIUiWidgetSet, AreaTrigger family (7), JournalEncounter family (6) and the other Journal loot/section tables, Light* (9), Liquid* (3), MapCelestialBody, MapChallengeMode*, MapDifficultyRedirect, MapLoadingScreen, MapRenderScale, Positioner*, TaxiNodes/TaxiPath/TaxiPathNode, Transport*, UiMapArt, UiMapArtStyleLayer, UiMapArtTile, UiMapFogOfWar*, UIMapPinInfo, Waypoint* (4), WmoMaxScale, WMOMinimapTexture, WorldEffect, WorldMapOverlayTile, ZoneIntroMusicTable, ZoneLight*, ZoneMusic, ZoneStory.

Games: UiMap, UiMapAssignment, UiMapXMapArt, Map, AreaTable, AreaPOI, AreaTrigger, TaxiNodes, MapDifficulty, DungeonEncounter, WorldMapOverlay exist in all three. Retail only: all Journal*, UiMapGroup*, UiMapLink, Waypoint*, ZoneStory, MapChallengeMode*, AreaPOIUiWidgetSet. Forever has UiMapArtStyleLayer, MapRenderScale, MapDifficultyRedirect, LiquidTypeXFFTTile, LightDataGlobalVolumeFog, WorldMapOverlay. Header differences: Forever's UiMap/UiMapAssignment headers equal retail's exactly (so Forever has `VisibilityPlayerConditionID`, `ContentTuningID`, `BountySetID` columns, all zero); Era's UiMap has `LevelRangeMin/Max` instead (0 rows set) and lacks `ContentTuningID`; Forever/Era `AreaTable` have `ExplorationLevel` (706 and 639 non-zero, subzones only, GUESS meaning); Era `AreaTable` lacks `ContentTuningID`; Forever's `Map` has `OceanLiquidTypeID`, Era's lacks `Corpse_0/1` (no entrance points on Era).

## UiMap

Rows: retail 1,967, Forever 60, Era 54. Retail has 1 Cosmic, 1 World (947), 46 Continent, 350 Zone, 897 Dungeon, 257 Micro, 415 Orphan. System: 1,730 World, 8 Taxi, 144 Adventure, 85 Minimap. Blizzard's `Enum.UIMapSystem` names 3 as Minimap (the dbd comment stops at 2); all 85 are Orphan-type. Retail and Forever clients ship identical UIMapFlag/UIMapType/UIMapSystem enums (checked in both `MapConstantsDocumentation.lua`).

- **ParentUiMapID** forms a clean forest: 0 orphan references, 0 cycles, depth 0..7 (retail), roots 81. Forever depth 0..3, Era 0..2.
- **Flags**: 22 flags named by Blizzard (bits file). Flag 0x200 is `DoNotTranslateBranches` in Blizzard's enum (dbd and TrinityCore call it Deprecated); no retail row sets it. Retail counts: ShowOverlays 366, ShowTaxiNodes 268, ShowTaskObjectives 246, DoNotShowOnNavbar 41, ForceAllOverlayExplored 19, AlwaysAllowTaxiPathing 15, NoWorldPositions 9. Forever sets only ShowOverlays (45); Era only ShowTaxiNodes (51), so the flags are not comparable between the games' clients.
- Our pins by type: Zone 13,468, Dungeon 1,210, Orphan 1,001, Micro 384, Continent 21; all are System 0. 1,001 pins on Orphan maps are a worthwhile sweep audit (not a defect by itself).
- **VisibilityPlayerConditionID** (36 maps) is the client's "which version of this zone does this player see" switch. Each gated map has same-name siblings (Eversong Woods 94 gated by 145692; siblings 1267, 2395, 2567, 2594). Not proven which side a given character sees: LIKELY on structure, GUESS on direction.
- **ContentTuningID** (182 retail maps, 0 Forever): `ContentTuning.MinLevelSquish..MaxLevelSquish` (the dbd names; offsets apply). Of 19,657 quests whose zone name equals a unique zone map with a tuning, 17,350 (88%) have a level inside the range; the 2,307 outside are scaling zones (Zul'Aman 83-88 vs our level 90, etc.). A sanity source, not a quest-level source. Note the earlier review's "ContentTuning ... gives a ContentTuningID only to task quests, areas and maps" holds; zone level ranges are API `C_Map.GetMapLevels` anyway.
- BountySetID, BountyDisplayLocation, HelpTextPosition, BkgAtlasID, AlternateUiMapGroup, AdventureMapTextureKitID, MapArtZoneTextPosition: art/bounty UI; not useful (see columns file).

## UiMapAssignment: how a world point becomes a map point

Columns: `Region_0..2` = world box minimum (X north, Y west, Z), `Region_3..5` = maximum; Z uses +-1,000,000 sentinels (unbounded) on 17,235 / 22,690 rows. `UiMin_0/1`, `UiMax_0/1` = the part of the UiMap (0..1) the box covers (a zone covers only a part of its continent map). `MapID` = the world map; `AreaID` restricts to a subzone subtree (864 retail rows, 54 Forever); `WMODoodadPlacementID` / `WMOGroupID` restrict to interiors (20,175 / 21,685 retail rows, none in Forever); `OrderIndex` breaks ties within one UiMap. Source (b), TrinityCore `DB2Stores.cpp`:

```
relX = (worldX - Region_0) / (Region_3 - Region_0)       (north)
relY = (worldY - Region_1) / (Region_4 - Region_1)       (west)
ui.x = relY*UiMin_0 + (1-relY)*UiMax_0                    (so ui.x grows eastwards)
ui.y = relX*UiMin_1 + (1-relX)*UiMax_1                    (ui.y grows southwards)
```
This is identical to `Convert-WorldToMapPercent` in `Build-QuestLocationData.ps1` (e: 11,154 of the 11,725 pins that have a start/own blob on their own map reproduce to within 0.05 map points, 533 more within 1.5, 38 beyond; the other 4,359 pins have no blob on their UiMap, they come from other sources). Choosing the row for a point: TrinityCore sorts candidates by, in order: inside box; OrderIndex (same UiMap); WMO match; AreaPriority (steps up `AreaTable.ParentAreaID` from the position's area to the row's AreaID; a row with an AreaID the chain never reaches is rejected); MapPriority (0 same map, 1 `Map.ParentMapID`, 2 `Map.CosmeticParentMapID`); height; the box's world-units-per-UI-unit scale (smaller wins); distance to box centre. To get a position on the continent, repeat through `UiMap.ParentUiMapID` using the parent's assignment (or `UiMapLink` rectangles, which override).

**QuestPOIBlob vs UiMapAssignment** (e): of 72,736 blobs, 72,719 have a UiMapID in `UiMap`; 72,659 (99.9%) have a UiMapID whose assignments include the blob's `MapID`; 72,575 (99.8%) have their first point inside an assignment box of that UiMap; 72,520 inside one with the same MapID. 18 blobs sit on a UiMap with no assignment. So the blob's UiMapID is trustworthy and the pipeline's "first containing region on the blob's UiMap" is safe; ambiguity only arises when a source gives world coordinates without a UiMap (CollectableSourceQuestSparse, recorded positions, entrances). Example of the naive pick failing: choosing the smallest containing zone box put the Maw of Souls door on Suramar (84, 0.3, off the edge) and Eye of Azshara on Suramar; the TrinityCore ordering with the entrance's own AreaTable chain resolves 190 of 203 entrances, and 187 of those land on a UiMap whose name appears in the entrance's area chain (the remaining three: Battle of Dazar'alor in Boralus, and two City of Threads doors, are legitimate city-floor maps).

## Map

Columns decoded in the bits file. Key ones: `InstanceType` (0..8, TrinityCore `MapTypes` + dbd), `ExpansionID` (Blizzard `Enum.ExpansionLevel`: Midnight = 11; continents 0..10 as expected; retail counts 0:130, 1:25, 2:44, 3:46, 4:64, 5:257, 6:188, 7:174, 8:63, 9:54, 10:84, 11:58), `ParentMapID` (phased copies: 86 maps, `Flags_0 0x20000` UseParentMapFlightBounds), `CosmeticParentMapID`, `CorpseMapID`/`Corpse_0/1` (door), `MapType` (1 standard 762, 2 old instances 35, 3 transports 112, 4 garrison buildings 278: GUESS from names), flags. Flags validated against named rows: Garrison 0x4000000 = 24 'Garrison Level' maps; ProvingGrounds; FlexibleRaidLocking (old raids); NoRaceChangeOnThisMap (starter-phase maps); PVP (Flags_1 0x40: Ashran, Slayer's Rise); IsDelve (Flags_2 0x100: 37 Delve maps). Forever Map: 71 rows (15 world, 37 party, 13 raid, 5 pvp, 1 arena); 26 of its 50 dungeon/raid maps carry a corpse point, 28 a CorpseMapID.

## AreaTable

10,046 retail rows (Forever 1,373, Era 1,212). `ParentAreaID` + `IsSubzone` (0x40000000): the flag is on 8,774 rows and every one has a parent (8,826 rows have a parent; 52 do without the flag): PROVEN (b, d). `FactionGroupMask`: PROVEN by names and by our quests (above). Examples and counts are in the bits file; the other flags are TrinityCore's names, checked on a few (AllowResting = capitals, FreeForAllPvP = arenas, NoPvP = Shattrath/Dalaran). `0x10000` (198 rows) is TrinityCore's NoChatChannels: battlegrounds, arenas and also Dustwallow Marsh and Kun-Lai Summit (agrees with the earlier PvP finding that it is not a PvP flag). Retail `ContentTuningID` on 9,131 rows (zone scaling range; same family as UiMap's).

Which zone a quest belongs to: no geography table assigns a quest to an area. A point can only be placed in a UiMap (boxes), not in an AreaTable row (that needs ADT data the client does not store in DB2). The category headers of our quests are QuestSort/our own ids, not area ids, so pin map vs category disagree in 8,092 of 26,892 pin/quest pairs (map's category differs from the quest's header, as expected for headers such as "Tournament", "Professions", "Covenant Sanctum").

## Dungeon and raid entrances

- `JournalInstance` (216) -> `JournalInstanceEntrance` (203 rows, 185 instances) with world `Position_0..2`, `MapID`, `AreaTableID`. Not read by any tool today (step 8 reads JournalInstance, JournalTier, JournalTierXInstance).
- `AreaPOI` `PoiDataType` 1: `PoiData` is a JournalInstanceID in 202 of 202 rows (197 names identical), 198 instances; with the entrance table the union is 208 of 216 instances. `PoiDataType` 3: `PoiData` is a UiMapID in 592 of 592 rows (room/floor POIs). Blizzard exposes the same data as `C_EncounterJournal.GetDungeonEntrancesForMap(uiMapID)` (retail and Forever API docs both list it); an in-game check on Forever is needed to see whether it returns anything.
- Forever and Era have no Journal tables and AreaPOI names only 6 of 50 Forever instance maps; `Map.Corpse_0/1` is the door there. Era has no corpse columns at all.
- Match with our data: instance categories whose name equals a JournalInstance name: 174 of 216; they hold 1,267 quests, 476 without a pin, 444 of those in instances with an entrance row. Largest: The Nighthold 25, Tomb of Sargeras 24, Antorus 22, Liberation of Undermine 17, Ulduar 16, Emerald Nightmare 12, Manaforge Omega 12, Blackrock Foundry 11. Forever: Ahn'Qiraj Temple 52 of 79 unpinned, Dire Maul 27 of 37, Zul'Gurub 14 of 86, Gnomeregan 13 of 27.
- Caution: whether a pin at the door is right is a design decision (the giver stands inside; the existing rule is "pin every normal quest we can place from pickup data"). Those quests have no pickup data, which is why they are unpinned; an entrance pin would be a different pin kind.

## Other tables worth a line

- `UiMapGroup`/`UiMapGroupMember`: 239 groups, 840 floors. Against `qcAreaIDToCategoryID`, 176 groups touch a mapped floor and only 1 floor of those groups is missing (the Stockade, deliberate). The earlier review's "28 floors missing" is out of date (rule added since). Flags: only `ShowIconsAcrossFloors`.
- `UiMapLink` (62): per TrinityCore these rectangles override assignment-derived child positions on the parent (so they are geometry, not only art as the earlier review says).
- `UiMapXMapArt.PhaseID` (33 maps, all maps our pins use): art variants by phase. `WorldMapOverlay.AreaID_0..3` + `UiMapXMapArt` link 3,326 areas to UiMaps; 96.8% of 5,066 (area, zone-UiMap) pairs agree with the AreaTable ancestor chain, so no new zones come out of it.
- `TaxiNodes` (1,485), `TaxiPath`, `AreaTrigger` (3,663): no quest links; the 51 `QuestObjective` rows of type 19 (area trigger enter) have ObjectIDs that are not AreaTrigger IDs (0 resolve). NO.
- `AdventureMapPOI` (not my cluster, found while tracing `AreaTable` references): 500 rows have a QuestID and world position; 475 are ours, 443 unpinned, but 420 of those are task quests (type 128) and the rest invitation/foothold quests: small.
- `MapDifficulty` (1,915): `MaxPlayers`, `ResetInterval`, `ContentTuningID`, entry text; `MapDifficultyXCondition` gates entry by PlayerCondition. No quest-level use.
- `AreaConditionalData` (114 rows, retail and Forever, other cluster): area visibility by PlayerCondition (phasing); the geography counterpart of the UiMap gate.

## Opportunities, ranked

1. **Entrance pins for instance quests** (retail 444, Forever 132 quests). Needs a decision (pin kind), then `JournalInstanceEntrance` + `UiMapAssignment` (retail) or `Map.Corpse` (Forever, 26 maps; 132 of the 142 unpinned Forever instance quests are in instances with a point). Verification measured: 187/190 retail entrances resolve to the right zone; corpse vs entrance 83/100 within 100 yd.
2. **Faction cross-check** by `AreaTable.FactionGroupMask`: retail 54 quests (23 in Alliance zones, 31 in Horde zones, faction 3), Forever 109 (61 + 48), plus conflicting ones (retail faction-2 quests in mask-2 zones: 11; faction-1 quests in mask-4 zones: 9). Examples: 9177 Journey to Undercity, 301 Report to Ironforge, 746 Dwarven Digging, 53172 Venture Co. Business Plan. Our memory rule is to trust only API-asserted faction limits, so these are review candidates (some are legitimately both-faction, e.g. dungeons, event quests such as 42235 Invasion: Westfall).
3. **Gated map versions** (`UiMap.VisibilityPlayerConditionID`): 21 pin maps, 1,003 pins, 1,381 quests. Needs an in-game test of which version each character sees and whether our pin map ids exist for that character.
4. **A correct world-to-UiMap function** for sources with only world coordinates (QuestSort, recorder, NPC lookups). Measured need: naive "first/smallest box" picks the wrong zone for 4 of the first 14 entrances I inspected (Eye of Azshara, Maw of Souls, Neltharion's Lair, Assault on Violet Hold); TrinityCore's ordering reaches 187 of 190.
5. **Category table drift check**: 1,600 of 41,683 start/own blobs (3.8%) sit on 108 UiMaps that are not keys of `qcAreaIDToCategoryID`; 1,165 of them reach a mapped map through `ParentUiMapID`. The biggest unmapped ones: Frostwall 217, Seat of the Primus 129, Plaguelands: The Scarlet Enclave 109, Elysian Hold 108, Kalimdor 69, Acherus 69+43, Tazavesh 65, Naigtal 61. A sweep check "blobs on unmapped maps" costs nothing.
6. `Map.ExpansionID` verifies the menu's expansion placement of continents and instances (Blizzard enum, 1,057 maps non-zero).
7. `UiMap.Flags & ShowTaskObjectives` (246 maps) and `NoWorldPositions` (9 maps) mark where a map is meant to show task quests and where world conversion is impossible; useful only as sanity checks.

## Things that do not exist

- No table with quest giver or creature positions (spawns are server data); only per-quest POIs (QuestPOIBlob), loot-source positions (CollectableSourceQuestSparse) and adventure-map POIs.
- No table maps a world coordinate to an AreaTable row, so no DB2-only zone assignment for a point.
- No per-quest link to a dungeon's entrance (only names, as step 8 does).
- No Journal tables on Forever, no dungeon UiMaps on Forever or Era (so no floors, no blob pins inside dungeons on those clients).
- Forever has no UiMapGroup, UiMapLink; fewer than a handful of AreaPOIs name dungeons.

## Open questions and in-game tests

1. `C_EncounterJournal.GetDungeonEntrancesForMap(1411)` and a Forever dungeon-bearing zone (e.g. 1427 Searing Gorge) on the Forever beta: does it return entrances, and do they match `Map.Corpse`?
2. On a retail character that has and one that has not met condition 145692 (Eversong): `C_Map.GetMapInfo(94)` versus 1267, and `C_Map.GetBestMapForUnit("player")` in Eversong; do our 64 pins on map 94 appear? (Same for Teldrassil 57/1308, Uldum 249/1527.)
3. Compare `C_Map.GetMapPosFromWorldPos` with the formula for three entrances whose zone boxes overlap (Eye of Azshara, Maw of Souls, Neltharion's Lair) to settle the selection order.
4. Whether `UiMap.ContentTuningID` ranges equal `C_Map.GetMapLevels` for a handful of zones.
