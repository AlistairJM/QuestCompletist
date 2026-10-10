# In-game API review

## Goal

The first systematic look at the Lua API the two clients offer addons, retail (12.1.0) and WoW:
Forever (1.60.1), for functions and events Quest Completist doesn't call that could give better
quest data, quest givers and pins, availability, text in the player's language, or anything else
useful for maintaining the addon. The review is the deliverable: nothing in the addon or the tools
changes with it. Each candidate is weighed against what the sweep already gets offline
([maintenance.md](../maintenance.md), "Where the data comes from"): an API earns a place only where
it gives something those sources don't, or gives it live for the player's own character.

The client's own data tables get a review of their own, `client-tables-review.md` (#203), written
alongside this one. Where a table covers the same ground as a function, the table is named here and
the details left to that review.

## What was checked (7 October 2026)

- **Blizzard's generated API documentation** in the UI source, from the Gethe/wow-ui-source branches
  `live` (12.1.0.69933) and `forever` (1.60.1.70245), folder
  `Interface/AddOns/Blizzard_APIDocumentationGenerated/`. The files are Lua tables, so a 40-line Lua
  script loaded every one with a stand-in `APIDocumentation` and wrote one line per function, event
  and structure, with arguments, returns and the `Documentation` strings.

  | Branch | Files | Functions in `C_` namespaces | Namespaces | Functions without a namespace | Events |
  |---|---|---|---|---|---|
  | `live` 12.1.0.69933 | 613 | 4,204 | 246 | 1,451 | 1,782 |
  | `forever` 1.60.1.70245 | 641 | 4,390 | 261 | 1,513 | 1,804 |

  26 files on live and 27 on Forever didn't load, as they refer to `Enum` tables the stand-in
  doesn't define: widget and constants files (calendar constants, currency constants, the Simple*
  frame APIs), none about quests, maps or NPCs. (forever.md's 6,306 against 6,048 counted by another
  method.) The functions without a namespace are the `Unit`, `Expansion`, `Instance` and frame
  systems: `UnitGUID`, `UnitPosition` and `UnitQuestTrivialLevelRange` are documented there.
- **Blizzard's own UI code** on the same branches, to see how it uses each candidate: the map's quest
  offer provider (`Blizzard_SharedMapDataProviders/QuestOfferDataProvider.lua`, byte-identical on
  both branches), the quest log (`QuestMapFrame.lua`), the quest window (`QuestFrame.lua`),
  `QuestUtils.lua`, and the `Blizzard_Deprecated` shims for 12.0.1 to 12.1.0, which mention no quest
  function (their one map entry aliases a waypoint function to `C_Navigation`).
- **The old global functions,** which the generated documentation leaves out (`GetQuestID`,
  `GetAvailableQuestInfo`, `GetQuestFactionGroup` and the rest): warcraft.wiki.gg's API list, 872 KB
  of wikitext, kept from dumps of the live client's globals, so a function on it exists in the
  client, though not every one has a page saying what it returns. Those without a page are marked
  "untested" below.
- **What the addon and the probes call today** (next section), and **our data** for the gaps a
  candidate would fill (the section after).
- **Not done:** anything in game. Everything marked "check" is a call to try in the next probe run.

Reading the tables: **Game** says which client documents the function (both, retail or Forever).
**Addon** says who calls it today: the addon, the retail quest-type probe (#42), the NPC-name probe
(#112), the quest-title probe (#99) or the Forever probe and its recorder (#139). **Use** is the
verdict: *have* (used already), *no*, *addon* (a runtime feature: filters, tooltips, pins), *probe*
(a run that saves facts for the offline tools, like the type probe), *recorder* (saves what the
player meets while playing, like the Forever recorder), *check* (try in game first) or *later* (a
feature idea outside the current plans). Nearly every function is marked
`SecretArguments = "AllowedWhenUntainted"`, which is no obstacle for arguments the addon builds
itself (the NPC-name work found the same); `SecretReturns = true` is, and is called out where it
matters.

## What the addon and the probes call today

**The addon** (`QuestCompletist/*.lua`, 36 functions in 16 namespaces):

| Namespace | Functions |
|---|---|
| `C_QuestLog` | GetAllCompletedQuestIDs, GetLogIndexForQuestID, GetTitleForQuestID, IsComplete, IsQuestFlaggedCompleted, IsQuestFlaggedCompletedOnAccount, IsWorldQuest, RequestLoadQuestByID |
| `C_Map` | GetAreaInfo, GetBestMapForUnit, GetMapInfo, GetPlayerMapPosition |
| `C_Calendar` | GetDayEvent, GetMonthInfo, GetNumDayEvents, SetAbsMonth |
| `C_TooltipInfo` | GetHyperlink (NPC names) |
| `C_TaskQuest` | GetQuestInfoByQuestID (task quest names) |
| `C_Reputation` | GetFactionDataByID, IsMajorFaction |
| `C_MajorFactions` | GetCurrentRenownLevel, GetMajorFactionData |
| `C_GossipInfo` | GetFriendshipReputation, GetFriendshipReputationRanks |
| `C_Covenants` | GetActiveCovenantID, GetCovenantData |
| `C_CreatureInfo` | GetClassInfo, GetRaceInfo |
| `C_SkillInfo` | GetSkillLineInfoByID (Forever) |
| `C_TradeSkillUI`, `C_ClassColor`, `C_DateAndTime`, `C_Timer`, `C_AddOns` | GetTradeSkillDisplayName; GetClassColor; GetCurrentCalendarTime, GetSecondsUntilWeeklyReset; After; IsAddOnLoaded |
| Globals | GetQuestID, GetQuestResetTime, UnitName, UnitLevel, UnitRace, UnitClass, UnitFactionGroup, UnitQuestTrivialLevelRange, GetProfessions, GetProfessionInfo, GetLocale, IsInInstance, GetBuildInfo, issecretvalue |

Events: QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE, QUEST_TURNED_IN, QUEST_ACCEPTED, QUEST_REMOVED,
UNIT_QUEST_LOG_CHANGED, QUEST_DATA_LOAD_RESULT, TOOLTIP_DATA_UPDATE, ZONE_CHANGED,
ZONE_CHANGED_NEW_AREA, PLAYER_ENTERING_WORLD, PLAYER_LOGIN, ADDON_LOADED, ADVENTURE_MAP_OPEN and
MODIFIER_STATE_CHANGED. The map pins come through `WorldMapFrame:AddDataProvider`, not events.

**The probes:**

| Probe | Calls |
|---|---|
| Quest types, retail (#42) | RequestLoadQuestByID, HaveQuestData, C_QuestInfoSystem.GetQuestClassification, IsRepeatableQuest, GetQuestTagInfo, IsWorldQuest, IsQuestTask; QUEST_DATA_LOAD_RESULT |
| Quest titles (#99) | GetTitleForQuestID, C_TaskQuest.GetQuestInfoByQuestID |
| NPC names (#112) | C_TooltipInfo.GetHyperlink; TOOLTIP_DATA_UPDATE |
| Forever probe, quest pass (#139) | RequestLoadQuestByID, GetQuestClassification, GetQuestTagInfo, IsRepeatableQuest, GetQuestDifficultyLevel, GetQuestType, IsEliteQuest, GetSuggestedGroupSize, GetTitleForQuestID |
| Forever probe, NPC pass | GetHyperlink, as #112 |
| Forever recorder | GOSSIP_SHOW with C_GossipInfo.GetAvailableQuests and GetActiveQuests; QUEST_GREETING with GetNumAvailableQuests, GetAvailableQuestInfo (whose fifth return is the quest ID), GetNumActiveQuests, GetActiveQuestID; QUEST_DETAIL with GetQuestID and the event's start-item payload; QUEST_COMPLETE for turn-ins; QUEST_ACCEPTED with the quest log heading from C_QuestLog.GetInfo; UnitGUID("npc") split into kind and ID, UnitName("npc"), C_Map.GetBestMapForUnit and GetPlayerMapPosition, UnitLevel |

So on Forever a quest-giver recorder of the kind this review was asked to look for already exists.
Retail has none.

## The gaps the game could fill (data as of master 39561d8)

| | Retail | Forever |
|---|---|---|
| Quests | 35,023 | 5,081 |
| Pins | 14,923 | 1,706 |
| Pins with an NPC ID | 11,473 | 1,503 |
| Pins with a name and no ID (objects, and givers never given an ID) | 363 | 199 |
| Pins with neither (popups, items, ship decks, unknown givers) | 3,087 | 4 |
| Quests with no pin at all | 12,110 | 1,414 |
| Quests whose only pins are nameless | 2,711 | 11 |
| Quests flagged unavailable | 218 | 0 |

Counted again on 9 October 2026 (master a288b24), retail: pins 15,202; with an NPC ID 10,564; with
neither 4,301; quests with no pin at all 10,361; quests whose only pins are nameless 3,696 counting
every quest ID a pin lists, as the table does (3,600 counting only quests we hold).

Fields no offline source gives: whether a quest is account-wide (done once per warband), the
expansion of a quest (the menus group by expansion by hand), a zone's level range, the item a quest
starts from (not shipped), and the NPC a quest is handed in to (not shipped). Text still in English
on other clients: storyline names (`qcQuestLines`), the names of object pins ("Wanted Poster"),
about 20 retail category names, and our own strings, translated by us.

## Namespace by namespace

### C_QuestLog (90 functions on live, 93 on Forever; 17 events)

| Functions | Game | Addon | What they give | Use |
|---|---|---|---|---|
| GetAllCompletedQuestIDs, IsQuestFlaggedCompleted, IsQuestFlaggedCompletedOnAccount, IsComplete, GetLogIndexForQuestID, GetTitleForQuestID, RequestLoadQuestByID, IsWorldQuest | both | addon | completions, the log, titles, data loads | have |
| GetInfo(logIndex) | both | Forever recorder | a `QuestInfo` for a quest in the log: title, questID, campaignID, level, difficultyLevel, suggestedGroup, frequency, isHeader, isStory, isScaling, isHidden, isAutoComplete, isInternalOnly, questClassification | recorder: the heading already; frequency and campaign of accepted quests could join it |
| IsOnQuest, ReadyForTurnIn, IsFailed, GetNumQuestLogEntries, GetQuestIDForLogIndex, GetTitleForLogIndex, GetHeaderIndexForQuest, GetSelectedQuest, SetSelectedQuest, GetMaxNumQuests, GetMaxNumQuestsCanAccept, UpdateCampaignHeaders | both | – | the quest log's own bookkeeping | no |
| IsAccountQuest(questID) | both | – | whether the quest is account-wide, so one character's completion ends it for the warband (the quest log's "Account" legend) | probe: a new data field; addon: the completion counter and filters |
| IsImportantQuest, IsMetaQuest, IsQuestCalling, IsQuestBounty, IsQuestInvasion, IsThreatQuest, IsQuestTask, IsQuestFromContentPush, QuestIgnoresAccountCompletedFiltering | both | type probe (IsQuestTask) | flags of the quest's record | probe: Important and Meta for an icon, if wanted; the rest no |
| IsRepeatableQuest | both | both probes | said no to every quest Blizzard's API flags repeatable (quest-types.md) | no |
| IsQuestTrivial(questID) | both | – | whether the quest is grey for this character, with scaling and Chromie Time taken into account; Blizzard's map hides trivial offers with it | addon: the low-level filter, which today compares our stored level with `UnitQuestTrivialLevelRange` |
| GetQuestDifficultyLevel, GetSuggestedGroupSize, GetQuestType, GetQuestTagInfo | both | Forever probe (all), type probe (tag info) | the quest's level as scaled for the player; the group size; the tag ID; `QuestTagInfo` (tagName in the player's language, tagID, worldQuestType, quality, tradeskillLineID, isElite, displayExpiration) | addon: the scaled level, and a tag line ("Dungeon", "Group") in tooltips; probe: have |
| GetQuestDetailsTheme | both | – | the quest window's art | no |
| GetQuestsOnMap(uiMapID) | both | – | `QuestPOIMapInfo` for the player's own log quests on a map: questID, x, y, mapID, isQuestStart, inProgress, isDaily, isMeta, questTagType, numObjectives, childDepth, isMapIndicatorQuest. Not offers: those are `C_QuestLine`'s | no |
| IsOnMap, GetMapForQuestPOIs, SetMapForQuestPOIs, GetQuestAdditionalHighlights, GetNextWaypoint, GetNextWaypointForMap, GetNextWaypointText, GetDistanceSqToQuest | both | – | the map's routing for log quests | no |
| GetZoneStoryInfo(uiMapID) | both | – | the zone's story achievement and its map (the quest log's "zone story" header) | later: a zone's story progress from the achievement's criteria; retail only, as Forever has no achievements |
| GetBountiesForMapID, GetBountySetInfoForMapID, IsQuestCriteriaForBounty, GetActiveThreatMaps, HasActiveThreats, GetActivePreyQuest | both | – | emissaries, N'Zoth threats, the current Prey quest | no |
| GetQuestLogMajorFactionReputationRewards, DoesQuestAwardReputationWithFaction, QuestContainsFirstTimeRepBonusForPlayer, GetQuestRewardCurrencies, GetQuestRewardCurrencyInfo, ShouldShowQuestRewards, GetRequiredMoney | both | – | rewards of a loaded quest | no: Blizzard's API has retail's reputation (all 11,035 of ours matched), and Forever's comes from the quest cache |
| QuestCanHaveWarModeBonus, QuestHasWarModeBonus, QuestHasQuestSessionBonus | both | – | bonuses | no |
| GetTimeAllowed, ShouldDisplayTimeRemaining, GetQuestObjectives, GetNumQuestObjectives | both | – | timers and objectives | no |
| GetQuestLogPortraitGiver | both | – | the model and name of the giver shown beside the quest log, for the selected quest | no: the recorder has the giver's GUID |
| AddQuestWatch, AddWorldQuestWatch, RemoveQuestWatch, RemoveWorldQuestWatch, GetNumQuestWatches, GetNumWorldQuestWatches, GetQuestIDForQuestWatchIndex, GetQuestIDForWorldQuestWatchIndex, GetQuestWatchType, SortQuestWatches | both | – | the objective tracker | no |
| IsUnitOnQuest, UnitIsRelatedToActiveQuest, IsPushableQuest, IsQuestDisabledForSession, IsQuestReplayable, IsQuestReplayedRecently | both | – | party and party sync | no. A party sync replay fires QUEST_TURNED_IN for a quest already done; the addon records a completion it already has, harmlessly |
| AbandonQuest, SetAbandonQuest, GetAbandonQuest, GetAbandonQuestItems, CanAbandonQuest | both | – | abandoning | no |
| GetQuestTimers, GetTrivialRange, IsEliteQuest | Forever | Forever probe (IsEliteQuest) | Classic's timed quests, the trivial level range, the elite flag | no more than the probe has |

Events: QUEST_ACCEPTED, QUEST_COMPLETE, QUEST_DATA_LOAD_RESULT, QUEST_DETAIL, QUEST_REMOVED and
QUEST_TURNED_IN are used. QUEST_DETAIL carries `questStartItemID`, the item a quest was started
from, which the Forever recorder saves and the addon ignores. QUESTLINE_UPDATE (a map's storylines
arrived; see `C_QuestLine`) and WORLD_QUEST_COMPLETED_BY_SPELL are the only others of interest;
QUEST_LOG_UPDATE, QUEST_POI_UPDATE, QUEST_AUTOCOMPLETE, QUEST_LOG_CRITERIA_UPDATE,
QUEST_WATCH_LIST_CHANGED, QUEST_WATCH_UPDATE, TASK_PROGRESS_UPDATE, TREASURE_PICKER_CACHE_FLUSH and
WAYPOINT_UPDATE are not.

### C_QuestLine (7 functions, both games)

| Function | Addon | What it gives | Use |
|---|---|---|---|
| GetAvailableQuestLines(uiMapID) | – | the storyline starts the server offers this character on a map, as `QuestLineInfo`: questLineID, questLineName, questID, questName, x, y, startMapID, floorLocation, isHidden (trivial), isAccountCompleted, inProgress, isCampaign, isImportant, isLegendary, isDaily, isMeta, isLocalStory. With GetForceVisibleQuests and `C_TaskQuest.GetQuestsOnMap`, this is everything Blizzard's map draws as an available quest (`QuestOfferDataProvider.lua`) | probe: on Forever, whether the server sends any; on retail, how the positions compare with our pins. addon: availability now, for the quests it lists |
| GetForceVisibleQuests(uiMapID) | – | quests Blizzard forces onto a map's offers | with the above |
| GetQuestLineInfo(questID, uiMapID?, displayableOnly?) | – | the quest's storyline: its ID, its name in the player's language, and where it starts on the given map. Blizzard's quest log calls it with no map for its "Storyline: X" text | addon: the tooltip's storyline name in the player's language (English from `qcQuestLines` today); probe: a second source for which storyline a quest is in |
| GetQuestLineQuests(questLineID) | – | a storyline's quests in order | no: the same client table the sweep reads (`QuestLineXQuest`) |
| IsComplete(questLineID) | – | whether the storyline is done | no: the addon counts the quests itself, with its filters |
| QuestLineIgnoresAccountCompletedFiltering(uiMapID, questLineID) | – | storylines shown even when the warband did them | with GetAvailableQuestLines |
| RequestQuestLinesForMap(uiMapID) | – | asks the server for a map's storylines; QUESTLINE_UPDATE says when they're there | needed before GetAvailableQuestLines for a map that isn't open |

### C_QuestInfoSystem (9 functions, both games)

| Function | Addon | What it gives | Use |
|---|---|---|---|
| GetQuestClassification(questID, questInfoID?) | both probes | Important, Legendary, Campaign, Calling, Meta, Recurring, Questline, Normal, BonusObjective, Threat or WorldQuest. Recurring is proven reliable, Normal isn't (quest-types.md) | probe: have; addon: a line or icon per classification through `QuestUtil.GetQuestClassificationInfo`, which gives Blizzard's text and atlas |
| GetQuestRewardCurrencies, HasQuestRewardCurrencies, GetQuestRewardSpells, GetQuestRewardSpellInfo, HasQuestRewardSpells, GetQuestLogRewardFavor, GetQuestHasShortExpirationWarning, GetQuestShouldToastCompletion | – | rewards and toasts | no |

### C_QuestOffer (4 functions, 5 events) and the quest window's globals

| Functions | Game | Addon | What they give | Use |
|---|---|---|---|---|
| C_QuestOffer.GetQuestOfferMajorFactionReputationRewards, GetQuestRewardCurrencyInfo, GetQuestRequiredCurrencyInfo, GetHideRequiredItems | both | – | the rewards shown in the open quest window | no |
| GetQuestID | both | addon, recorder | the quest in the open window | have |
| GetNumAvailableQuests, GetAvailableTitle, GetAvailableLevel, GetAvailableQuestInfo(index) → isTrivial, frequency, isRepeatable, isLegendary, questID, isImportant, isMeta, questInfoID; IsAvailableQuestTrivial | both | Forever recorder | the quests an NPC offers in a greeting (an NPC with several quests and no gossip menu). The quest ID has been returned since 9.0.1, so Forever has it too | recorder |
| GetNumActiveQuests, GetActiveTitle, GetActiveLevel, GetActiveQuestID, IsActiveQuestTrivial, GetGreetingText | both | Forever recorder | the quests the NPC takes in | recorder: hand-in NPCs |
| GetQuestPortraitGiver, GetQuestPortraitTurnIn | both | – | the giver's model and name in the quest window | no: the GUID is better |
| QuestIsDaily, QuestIsWeekly, QuestGetAutoAccept, QuestGetAutoLaunched, QuestIsFromAreaTrigger, QuestIsFromAdventureMap, QuestFlagsPVP, IsQuestCompletable, IsCurrentQuestFailed | both | – | facts about the quest in the open window | recorder: a quest that came from an area trigger or a popup has no giver, and the player's position when it opened is where its pin belongs (the 3,087 nameless pins are such quests) |
| GetTitleText, GetQuestText, GetObjectiveText, GetRewardText, GetProgressText, GetQuestBackgroundMaterial, GetCriteriaSpell | both | – | the window's texts | no |
| AcceptQuest, DeclineQuest, CompleteQuest, CloseQuest, SelectAvailableQuest, SelectActiveQuest, ConfirmAcceptQuest, GetQuestReward, QuestChooseRewardError, ShowQuestOffer, ShowQuestComplete | both | – | driving the window | no |
| GetRewardXP, GetRewardMoney, GetRewardHonor, GetRewardArtifactXP, GetRewardTitle, GetRewardSkillPoints, GetRewardSkillLineID, GetRewardNumSkillUps, GetQuestItemInfo, GetQuestItemLink, GetQuestItemInfoLootType, GetNumQuestItems, GetNumQuestRewards, GetNumQuestChoices, GetNumQuestCurrencies, GetQuestCurrencyID, GetQuestMoneyToGet, GetMaxRewardCurrencies, GetNumQuestItemDrops | both | – | the window's rewards | no |
| Auto-accept popups: AddAutoQuestPopUp, GetAutoQuestPopUp, GetNumAutoQuestPopUps, RemoveAutoQuestPopUp, AcknowledgeAutoAcceptQuest, ClearAutoAcceptQuestSound, PlayAutoAcceptQuestSound | both | – | the popups for quests that start without a giver | no |

Events: QUEST_PROGRESS is used; QUEST_GREETING is the recorder's; QUEST_FINISHED was tried and
rejected for completions (it fires before the hand-in); QUEST_ACCEPT_CONFIRM and QUEST_ITEM_UPDATE
no.

### C_QuestHub (2 functions, new in 12.x, both games)

`C_QuestHub.IsQuestCurrentlyRelatedToHub(questID, hubAreaPoiID)` and
`IsAreaPOICurrentlyRelatedToHub` go with `C_AreaPoiInfo.GetQuestHubsForMap`: a hub is an area POI
with a name and a position that Blizzard's map shows in place of the single offers under it when
zoomed out. Use: probe, to see which hubs exist and where; otherwise no.

### C_TaskQuest (12 functions, both games)

| Function | Addon | What it gives | Use |
|---|---|---|---|
| GetQuestInfoByQuestID | addon | a task quest's name | have |
| GetQuestsOnMap(uiMapID) | – | the task quests (world quests, bonus objectives) on a map, with positions | no: the addon doesn't pin world quests |
| GetQuestZoneID(questID) | – | the map a task quest belongs to | probe: the game's own zone for task quests still in Uncategorized |
| GetQuestLocation, GetQuestTimeLeftMinutes, GetQuestTimeLeftSeconds, GetQuestProgressBarInfo, IsActive, RequestPreloadRewardData, GetThreatQuests, DoesMapShowTaskQuestObjectives, GetQuestUIWidgetSetByType | – | world quest timers, positions and widgets | no |

### C_GossipInfo (20 functions, 7 events, both games)

| Function | Addon | What it gives | Use |
|---|---|---|---|
| GetAvailableQuests, GetActiveQuests | Forever recorder | every quest the NPC in front of you offers to, or takes from, this character, as `GossipQuestUIInfo`: questID, title, questLevel, isTrivial, frequency, repeatable, isComplete, isLegendary, isIgnored, isImportant, isMeta, questInfoID | recorder, on retail too |
| GetNumAvailableQuests, GetNumActiveQuests | – | the counts | with the above |
| GetFriendshipReputation, GetFriendshipReputationRanks | addon | friendship ranks | have |
| GetOptions, GetText, GetPoiForUiMapID, GetPoiInfo, GetOptionUIWidgetSetsAndTypesByOptionID, GetCompletedOptionDescriptionString, GetCustomGossipDescriptionString, RefreshOptions, ForceGossip, CloseGossip, SelectOption, SelectOptionByIndex, SelectActiveQuest, SelectAvailableQuest | – | the gossip menu and its points of interest | no |

Events: GOSSIP_SHOW is the recorder's; GOSSIP_CLOSED, GOSSIP_OPTIONS_REFRESHED, GOSSIP_CONFIRM,
GOSSIP_CONFIRM_CANCEL, GOSSIP_ENTER_CODE and DYNAMIC_GOSSIP_POI_UPDATED no.

### C_Map (40 functions, 7 events, both games)

| Functions | Addon | What they give | Use |
|---|---|---|---|
| GetMapInfo, GetAreaInfo, GetBestMapForUnit, GetPlayerMapPosition | addon, recorder | map names, area names, the player's map and position | have |
| GetMapLevels(uiMapID) | – | the zone's player level range | addon: level ranges on zone categories, as the map shows them. Check Forever answers |
| GetMapInfoAtPosition(uiMapID, x, y) | – | the child map under a point of a parent map | addon or tool: which zone a continent-level pin belongs to (42 of Durotar's 109 quests have only Kalimdor points) |
| GetMapPosFromWorldPos(continentID, worldPos, overrideUiMapID?), GetWorldPosFromMapPos(uiMapID, mapPos) | – | the client's own conversion between world and map coordinates, which `UiMapAssignment` approximates offline; without an override it also chooses the map | probe: check the pin pipeline's and the Forever importer's conversion and map choice (98.2% on the old-pin key) against the client's |
| GetMapRectOnMap(uiMapID, topUiMapID) | – | where a zone sits on its parent map | later: zone pins on continent maps |
| GetMapChildrenInfo, GetMapGroupID, GetMapGroupMembersInfo, GetMapLinksForMap, GetMapBannersForMap, IsCityMap, IsMapValidForNavBarDropdown, MapHasArt, GetFallbackWorldMapID, GetMapWorldSize, GetMapDisplayInfo | – | the map tree, floors and links | no: `UiMap.csv` has it offline |
| GetMapArtID, GetMapArtLayers, GetMapArtLayerTextures, GetMapArtBackgroundAtlas, GetMapArtHelpTextPosition, GetMapArtZoneTextPosition, GetMapHighlightInfoAtPosition, GetMapHighlightPulseInfo, RequestPreloadMap | – | drawing | no |
| SetUserWaypoint(point), ClearUserWaypoint, HasUserWaypoint, GetUserWaypoint, GetUserWaypointPositionForMap, GetUserWaypointFromHyperlink, GetUserWaypointHyperlink, CanSetUserWaypointOnMap | – | the game's own map pin, the one players place with a click | addon: a waypoint to one of our pins without TomTom (with `C_SuperTrack.SetSuperTrackedUserWaypoint`). Check Forever allows it |
| GetBountySetMaps, OpenWorldMap, CloseWorldMapInteraction | – | – | no |

Events: ZONE_CHANGED and ZONE_CHANGED_NEW_AREA are used. PLAYER_MAP_CHANGED(oldMapID, newMapID) says
exactly when the player's map changes, which the list's zone switching could use instead of the two
zone events; WORLD_MAP_OPEN, USER_WAYPOINT_UPDATED, ZONE_CHANGED_INDOORS and NEW_WMO_CHUNK no.

### C_MapExplorationInfo (2 functions, both games)

`GetExploredMapTextures` and `GetExploredAreaIDsAtPosition`: the fog of war. No.

### C_AreaPoiInfo (8 functions, 1 event, both games)

| Function | What it gives | Use |
|---|---|---|
| GetAreaPOIForMap(uiMapID), GetAreaPOIInfo(uiMapID, areaPoiID) | the points of interest on a map, as `AreaPOIInfo`: name and description in the player's language, position, atlasName, factionID, linkedUiMapID, isCurrentEvent, isPrimaryMapForPOI, widget sets. Holiday camps and portals, invasions, hubs | probe: what Forever has, if anything; the client's `AreaPOI` table has retail's offline (client-tables review) |
| GetEventsForMap(uiMapID), GetAreaPOISecondsLeft, IsAreaPOITimed | the timed world events running on a map now, and their time left | addon, later: "running now" on pins of event quests, once a quest is linked to its event |
| GetQuestHubsForMap(uiMapID) | the quest hubs (see `C_QuestHub`) | probe |
| GetDelvesForMap, GetDragonridingRacesForMap | delves and races | no |

Event: AREA_POIS_UPDATED.

### C_SuperTrack (20 functions, 2 events, both games)

`SetSuperTrackedUserWaypoint(true)` turns the user waypoint into the on-screen arrow;
`SetSuperTrackedMapPin(Enum.SuperTrackingMapPinType.QuestOffer, questID)` does the same for a quest
offer Blizzard's map shows, and the AreaPOI, TaxiNode, DigSite and HousingPlot types for those.
`SetSuperTrackedQuestID`, `SetSuperTrackedVignette`, `SetSuperTrackedContent`, the `Clear*`, `Get*`
and `Is*` functions manage the rest. Use: addon, with the user waypoint above, so players without
TomTom get an arrow to a pin. Events SUPER_TRACKING_CHANGED and SUPER_TRACKING_PATH_UPDATED no. The
arrow itself is `C_Navigation` (7 functions on both games: `GetNextWaypointForMap`, `GetDistance`,
`GetTargetState` and the rest), which reads whatever is super-tracked; nothing to call there.

### C_Minimap (23 functions, 4 events, both games)

`IsTrackingAccountCompletedQuests()` and `IsTrackingHiddenQuests()` (with `IsFilteredOut`,
`GetDefaultTrackingValue`, `GetTrackingInfo`, `GetTrackingFilter`, `GetNumTrackingTypes`,
`SetTracking`, `ClearAllTracking`) read the minimap's tracking menu: "Account Completed Quests" and
"Trivial Quests" (Forever's menu also has class trainers and ammunition). Blizzard's offer provider
follows both toggles. Use: addon, if the warband and low-level filters should follow the game's own
toggles (a decision below). `IsInsideQuestBlob`, `GetNumQuestPOIWorldEffects`,
`GetPOITextureCoords`, `GetUiMapID`, `GetViewRadius`, `ShouldUseHybridMinimap`,
`SetMinimapInsetInfo`, `ClearMinimapInsetInfo`, `GetDrawGroundTextures`, `SetDrawGroundTextures`,
`IsRotateMinimapIgnored`, `SetIgnoreRotateMinimap`, `CanTrackBattlePets` and `IsTrackingBattlePets`
no. Event MINIMAP_UPDATE_TRACKING goes with the toggles; the other three no.

### C_VignetteInfo (6 functions, 2 events, both games)

`GetVignettes()` and `GetVignetteInfo(guid)` give the rares and treasures near the player, as
`VignetteInfo`: name, objectGUID, vignetteID, type (Normal, PvPBounty, Torghast, Treasure,
FyrakkFlight), onWorldMap, onMinimap, isDead and `rewardQuestID`, the hidden quest that records the
treasure or kill. `GetVignettePosition(guid, uiMapID)` places it; `FindBestUniqueVignette`,
`GetHealthPercent` and `GetRecommendedGroupSize` no. Use: later. A recorder could name and place
the hidden tracking quests the addon flags as unavailable, for a treasures-and-rares feature that
isn't planned. Events VIGNETTES_UPDATED and VIGNETTE_MINIMAP_UPDATED with it.

### C_EncounterJournal (22 functions, 3 events, both games)

`GetDungeonEntrancesForMap(uiMapID)` gives a zone map's dungeon entrances with name, position and
journalInstanceID. Use: later, a pin at the entrance for quests whose givers stand inside, which
have no pin on Forever (forever.md counted 110 on the first import and 79 more among the
repeatable quests). Check that Forever's client returns any. `GetInstanceForGameMap`
and `GetEncountersOnMap` duplicate the `JournalInstance` tables the dungeon audit reads; the other
19 (loot, difficulties, sections, tabs) no. The old `EJ_*` globals aren't documented and aren't
needed.

### C_TooltipInfo (82 functions, 3 events, both games)

`GetHyperlink` names NPCs today. `GetUnit(unit)` gives the tooltip of the NPC in front of the
player, `GetWorldCursor()` whatever is under the mouse in the world with its GUID, and
`GetMinimapMouseover()` a minimap blip's tooltip: a recorder could learn creature IDs from them, but
not what those creatures offer, so no. `GetQuestItem`, `GetQuestLogItem`, `GetQuestCurrency`,
`GetQuestLogCurrency`, `GetQuestLogSpecialItem` and `GetQuestPartyProgress` are reward and progress
tooltips; the other 72 are items, spells, auras, mail, trade and recipes. No. Events:
TOOLTIP_DATA_UPDATE is used; SHOW_HYPERLINK_TOOLTIP and HIDE_HYPERLINK_TOOLTIP no.

### C_CreatureInfo (8 functions) and the Unit globals

| Function | Game | Addon | What it gives | Use |
|---|---|---|---|---|
| C_CreatureInfo.GetClassInfo, GetRaceInfo | both | addon | class and race names | have |
| C_CreatureInfo.GetFactionInfo(raceID) | both | – | a race's faction tag and name | no |
| C_CreatureInfo.GetCreatureID(guid), UnitCreatureID(unit) | both | – | the creature ID without splitting the GUID string, as the Forever recorder does | recorder: simpler |
| C_CreatureInfo.GetCreatureFamilyIDs, GetCreatureFamilyInfo, GetCreatureTypeIDs, GetCreatureTypeInfo | both | – | beast families and creature types | no |
| UnitGUID, UnitName | both | recorder, addon | the NPC's GUID (Creature, GameObject or Vehicle, with its ID) and name | recorder |
| UnitLevel, UnitRace, UnitClass, UnitFactionGroup, UnitQuestTrivialLevelRange | both | addon | the character | have |
| UnitQuestTrivialLevelRangeScaling | both | – | the trivial range for scaling quests | addon: pairs with `IsQuestTrivial`, which already allows for it |
| UnitClassification(unit), UnitIsQuestBoss, UnitCreatureType, UnitExists | both | – | elite, rare, quest boss | no |
| UnitPosition(unit) | both | – | world coordinates, for the player and party members only, not NPCs | no: the recorder stands beside the giver and takes the player's map position |
| ClosestUnitPosition(creatureID), ClosestGameObjectPosition(objectID) | both | – | the nearest creature or object of that ID, which would place quest givers by ID, but the returns are secret values (`SecretReturns = true`), so an addon can neither read nor save them | no |

### C_PlayerInfo (39 functions on live, 40 on Forever)

`GetContentDifficultyQuestForPlayer(questID)` gives Trivial, Easy, Fair, Difficult or Impossible,
the colour the quest log paints a quest for this character, scaling included. Use: addon, for the
list's and tooltips' quest colours and levels. `IsPlayerInChromieTime` and
`CanPlayerEnterChromieTime` say whether the character is levelling in one chosen expansion, which
changes what it's offered: a note at most. `IsPlayerNPERestricted`, `IsPlayerEligibleForNPE` and its
v2 are Exile's Reach; `GetInstancesUnlockedAtLevel`, `GetContentDifficultyCreatureForPlayer` and the
other 31 (banks, mounts, Mythic+, the Trading Post, names from a `PlayerLocation`, `GUIDIsPlayer`) no.
Forever adds `ShouldDisplaySurname`: no.

### C_CampaignInfo (10 functions, both games)

`GetCampaignID(questID)`, `IsCampaignQuest`, `GetCampaignInfo(campaignID)` (name and description in
the player's language, isWarCampaign), `GetChapterIDs`, `GetCampaignChapterInfo` (name,
description, rewardQuestID), `GetCurrentChapterID`, `GetState`, `GetFailureReason`,
`GetAvailableCampaigns`, `SortAsNormalQuest`. A campaign is the grouping above storylines. Use:
probe, the campaign of every quest (the client's campaign tables are the offline side: the
client-tables review counts 145 campaigns holding 740 of our 1,474 storylines); addon, "Campaign: X"
in the player's language. Retail only in practice.

### C_ContentTracking (18 functions, 5 events, both games)

Tracking of appearances, mounts and pets to their sources. `GetCurrentTrackingTarget(type, id)` can
name a quest as a tracked collectable's source, but only per collectable, never per quest; the rest
(`StartTracking`, `GetTrackablesOnMap`, waypoints, titles) no.

### C_Calendar (90 functions, 13 events, both games)

`SetAbsMonth`, `GetMonthInfo`, `GetNumDayEvents`, `GetDayEvent` and `OpenCalendar` are used, and `GetDayEvent`'s
`title` already names a holiday in the player's language. `GetHolidayInfo(monthOffset, day, index)`
adds the description and texture; `SetMonth`, `GetMinDate`, `GetMaxCreateDate`, `GetRaidInfo`,
`GetEventIndex` and `GetClubCalendarEvents` no; the other 78 create, invite and manage events. No
new data. `OpenCalendar` asks the server for the calendar's events, and event CALENDAR_UPDATE_EVENT_LIST
says they've arrived: the addon calls the one at login and redraws the open map on the other
(maintenance.md, "Holidays"). The other 12 events no. The calendar window's filters are CVars
(`calendarShowHolidays`, `calendarShowDarkmoon`, `calendarShowWeeklyHolidays`, and three more for
battlegrounds, raid lockouts and, on Forever, raid resets), and its Lua filters nothing itself, so
the game must leave an unticked filter's events out of the day lists. The addon reads the three that
hold its holidays with `GetCVarBool` (documented the same in both games, nil for a CVar the game
doesn't have) and shows the quests of a holiday whose filter is unticked, since the calendar can't
say whether it is running. Read from the source, not yet seen in game (maintenance.md, "Holidays",
has the lines to try). The CVAR_UPDATE event exists in both games and isn't used.

### C_EventScheduler (11 functions, 1 event, both games)

`GetOngoingEvents()` and `GetScheduledEvents()` give the map's events schedule (the Theater Troupe
and its kind): areaPoiID, start and end times, display info; `GetEventUiMapID` and
`GetEventZoneName` place them; `CanShowEvents`, `HasData`, `RequestEvents` and the reminders manage
it. Use: probe on Forever, whether it lists the fishing contest, the Darkmoon Faire or an invasion,
which the calendar doesn't (forever.md, open questions); addon, later, event times on event pins.
Event EVENT_SCHEDULER_UPDATE with it.

### C_Reputation (27 functions, 1 event, both games)

`GetFactionDataByID` and `IsMajorFaction` are used. `GetFactionParagonInfo(factionID)` returns the
paragon cache's `rewardQuestID`, which names the "Supplies from X" quests' factions live; the
client's `ParagonReputation` table has the same offline (client-tables review).
`IsAccountWideReputation`, `IsFactionParagon`, `IsFactionParagonForCurrentPlayer`, `GetNumFactions`,
`GetFactionDataByIndex`, `GetWatchedFactionData`, `GetGuildFactionData` and the 17 that sort,
collapse, watch and set at war: no. Event FACTION_STANDING_CHANGED: addon, to refresh pins gated by
friendship ranks when the standing changes.

### C_MajorFactions (12 functions on live, 14 on Forever; 4 events)

`GetMajorFactionData` and `GetCurrentRenownLevel` are used. `GetMajorFactionIDs(expansionID)`,
`GetRenownLevels`, `GetMajorFactionRenownInfo`, `HasMaximumRenown`, `IsWeeklyRenownCapped`,
`GetRenownRewardsForLevel`, `GetRenownNPCFactionID`, `IsMajorFactionHiddenFromExpansionPage`,
`ShouldDisplayMajorFactionAsJourney`, `ShouldUseJourneyRewardTrack`, and Forever's
`GetMajorFactionProgressionInfo` and `GetTotalReputationForRenownLevel`: no new data. Events
MAJOR_FACTION_RENOWN_LEVEL_CHANGED and MAJOR_FACTION_UNLOCKED: addon, to refresh renown-gated pins
live; MAJOR_FACTION_INTERACTION_STARTED and _ENDED no.

### C_Covenants (3 functions, 1 event)

`GetActiveCovenantID` and `GetCovenantData` are used; `GetCovenantIDs` no. COVENANT_CHOSEN would
redraw an open map when the covenant changes; the filter already reads the covenant each time it's
built.

### C_GameRules (22 functions on live, 29 on Forever)

Game modes: `GetActiveGameMode`, `IsStandard`, `IsPlunderstorm`, `IsWoWHack`,
`GetCurrentGameModeRecordID`, `GetCurrentGameModeDisplayInfo`, `IsGameRuleActive`,
`GetGameRuleAsFloat` and the rest. Forever only: `GetForeverExperiencePreset()`, Classic or Modern
(the login screen calls it Enhanced): the "Choose Your Experience Preset" screen shown once before
the character list, a starting-settings choice. Its Classic option means standard-definition
models, quest points of interest and objective blobs off, one bag off and transmog off, and the
settings can be changed later; Forever's UI also uses it for nameplate and graphics defaults;
`SetForeverExperiencePreset`, `IsHardcoreActive`, `IsSelfFoundAllowed`, `AccountHasSDEnabled`,
`IsSDHDToggleEnabled`, `SetSDHDToggleValue`, and the event GAME_RULES_CHANGED. Use: a runtime way to
tell the games apart (`C_GameRules.GetForeverExperiencePreset ~= nil`) should the two TOCs ever
become one; and check whether the Modern preset changes what the quest UI shows.

### C_SkillInfo (none on live, 8 on Forever; 1 event)

`GetSkillLineInfoByID` is used for the profession skill requirements, with a fallback through
`GetProfessions` and `GetProfessionInfo` on a client without it (docs/plans/game-parity.md).
`GetNumSkillLines`,
`GetSkillLineInfo(index)` (the whole skill list as `SkillLineAttributes`), `AbandonSkill` and the
header and selection functions: no. Event SKILL_LINES_CHANGED: addon, to refresh skill-gated pins
when a skill goes up.

### C_DateAndTime (10 functions on live, 11 on Forever)

`GetCurrentCalendarTime` and `GetSecondsUntilWeeklyReset` are used. `GetSecondsUntilDailyReset`
duplicates the global `GetQuestResetTime` the addon calls; `GetWeeklyResetStartTime`,
`GetServerTimeLocal`, `GetCalendarTimeFromEpoch`, the `AdjustTimeBy*` functions,
`CompareCalendarTime` and Forever's `IsDayTime` no.

### The rest, in a line each

- **C_QuestSession** (14 functions, 8 events): party sync. No.
- **C_ScenarioInfo** (10, 9 events): scenario steps. No.
- **C_AdventureMap** (2 on live, 5 on Forever, where `GetNumQuestOffers` and `GetNumZoneChoices` are
  leftovers of the garrison table): no. The addon registers ADVENTURE_MAP_OPEN only to stay out of
  that map's way.
- **C_TaxiMap** (3), **C_LoreText** (1), **C_ContributionCollector.GetRewardQuestID** (a war effort
  contribution's reward quest), **C_IslandsQueue.GetIslandsWeeklyQuestID**,
  **C_Garrison.GetTalentUnlockWorldQuest**, **C_LFGList.CanCreateQuestGroup** and
  **SetSearchToQuestID**: no.
- **Quest facts globals on the wiki's list, not in the documentation:** `GetQuestFactionGroup(questID)`
  returns 1 for Alliance, 2 for Horde and nil for both; Blizzard's `QuestUtils.lua` uses it for the
  account-quest legend's faction icon (probe: a third source for our faction field).
  `GetQuestExpansion(questID)`, `IsBreadcrumbQuest(questID)`, `IsStoryQuest(questID)`,
  `IsQuestSequenced` and `QuestHasPOIInfo` have no page and no caller in Blizzard's code: untested.
  If `IsBreadcrumbQuest` answers, it's the only server-asserted breadcrumb flag retail offers for
  quests after Mists of Pandaria, where TrinityCore stops. `GetQuestLink`, `GetQuestUiMapID`,
  `GetQuestPOIs`, `GetQuestPOIBlobCount`, `GetQuestPOILeaderBoard`, `QuestMapUpdateAllQuests`,
  `QuestPOIUpdateIcons`, `GetTaskInfo`, `GetTaskPOIs`, `GetTasksTable`, `GetDailyQuestsCompleted`,
  `GetQuestProgressBarPercent`, `IsQuestIDValidSpellTarget`, `HaveQuestRewardData`: no;
  `HaveQuestData` the probes have.
- **Quest log globals:** `GetQuestLogQuestText`, `GetQuestLogCompletionText`,
  `GetQuestLogLeaderBoard`, `GetNumQuestLeaderBoards`, `GetQuestObjectiveInfo`, the reward functions
  (`GetQuestLogRewardInfo`, `GetQuestLogRewardMoney`, `GetQuestLogRewardXP`, `GetQuestLogRewardHonor`,
  `GetQuestLogRewardArtifactXP`, `GetQuestLogRewardTitle`, `GetQuestLogRewardSkillPoints`,
  `GetNumQuestLogRewards`, `GetNumQuestLogChoices`, `GetQuestLogChoiceInfo`,
  `GetQuestLogChoiceInfoLootType`, `GetNumQuestLogRewardFactions`, `GetQuestLogRewardFactionInfo`,
  `ProcessQuestLogRewardFactions`, the treasure picker), the special item functions, `GetQuestLogItemLink`,
  `GetQuestLogItemDrop`, `GetQuestLogCriteriaSpell`, `GetQuestLogTimeLeft`, `GetQuestLogQuestType`,
  `GetQuestLogPortraitTurnIn`, `QuestLogShouldShowPortrait`, `QuestLogPushQuest`, `GetQuestSortIndex`,
  `GetNumQuestLogTasks`, `SortQuests`, `SortQuestSortTypes`, `ExpandQuestHeader`,
  `CollapseQuestHeader`: no. Reputation rewards for quests in the log duplicate what the API and the
  Forever quest cache give.
- **Zone text globals** `GetZoneText`, `GetSubZoneText`, `GetRealZoneText`, `GetMinimapZoneText`: the
  recorder keeps map and position instead. No.
- **Expansion system** (23 functions: `GetExpansionLevel`, `GetAccountExpansionLevel`,
  `GetMaximumExpansionLevel`, `GetServerExpansionLevel`, `GetExpansionForLevel`,
  `GetMaxLevelForExpansionLevel`, `GetMaxLevelForPlayerExpansion`, `GetMaxLevelForLatestExpansion`,
  `GetNumExpansions`, `GetExpansionDisplayInfo`, `GetMinimumExpansionLevel`, and the trial and upgrade
  functions): nothing per quest. No.
- **Instance system** (18): `IsInInstance` is used; `GetInstanceInfo` and the difficulty functions no.

## The functions the brief asked about

1. **`C_QuestLog.GetQuestsForPlayerByMapID`** doesn't exist: not in either branch's documentation,
   not in Blizzard's UI code (the only "ForPlayerByMapID" is a local helper for area POIs), not on
   the wiki's list, and not in the `classic_era` branch either. Its job is split in two.
   `C_QuestLog.GetQuestsOnMap` gives the player's own log quests' points. The quests the player can
   pick up are `C_QuestLine.GetAvailableQuestLines` with `GetForceVisibleQuests` and
   `C_TaskQuest.GetQuestsOnMap`, which is what Blizzard's map draws (`QuestOfferDataProvider.lua`),
   each with its questID, x, y and startMapID. On retail those positions are presumably the same
   QuestPOI data the pin pipeline reads offline, which a probe can confirm; what's new live is the
   availability: the server lists an offer only for a character that qualifies, with
   isAccountCompleted, inProgress and isHidden. On Forever the client's `QuestLine` table has 3
   rows, so whether its server sends offers at all is the first thing to ask.
2. **`C_GossipInfo.GetAvailableQuests` with `UnitGUID`:** the Forever recorder does exactly this,
   and more (the greeting's `GetAvailableQuestInfo`, the quest window's start item, turn-ins, the
   quest log heading). Retail has no recorder. Recommendation 1.
3. **`C_QuestInfoSystem.GetQuestClassification` and `C_QuestLog.GetQuestTagInfo`:** both probes
   call them. Recurring is trusted and Normal isn't (quest-types.md); the tag gives dungeon, raid,
   group, PvP and elite, with a name in the player's language and the profession of profession
   quests. New use: a tag or classification line in tooltips (recommendation 5).
4. **`C_QuestLine`:** storyline names in the player's language (`GetQuestLineInfo` with no map, as
   Blizzard's quest log calls it) and the offers above.
5. **`C_AreaPoiInfo`:** holiday and event camps, hubs and timed events, with names, positions and
   time left; the calendar stays the right source for which holiday runs. Probe first, on Forever.
6. **`C_QuestLog.GetZoneStoryInfo`:** the zone story achievement; retail only; later.
7. **`GetQuestExpansion`:** on the wiki's list, undocumented, uncalled by Blizzard: try it in the
   next probe run. If it answers, it's the per-quest link the menus' expansion groups lack.
8. **`C_QuestLog.GetSuggestedGroupSize`:** both probes have it, and Forever's quest cache gives the
   same; a "Group (3)" tooltip line is the only new use.
9. **`C_QuestLog.IsQuestTrivial`:** the scaling-aware low-level test (recommendation 4).
10. **`C_QuestHub` (12.x):** hubs are named map POIs grouping offers; a probe can list them; no
    other use yet.

## Compared with the offline sources

| Field or feature | Offline today | What the game adds live | Verdict |
|---|---|---|---|
| Quest names | Blizzard's API; names from the client in the player's language since #100 | – | done |
| NPC names | `C_TooltipInfo.GetHyperlink` since #114 | objects stay English: no API names an object by ID | done |
| Level | old data, the API; Forever's cache | `GetQuestDifficultyLevel`, `IsQuestTrivial`, `GetContentDifficultyQuestForPlayer`: scaled for this character | addon |
| Zone and category | the API's area, client points, pins, storylines; Forever's cache | the quest log heading on accept (Forever recorder has it); `C_TaskQuest.GetQuestZoneID` for task quests | recorder, probe |
| Type (recurrence) | the API's flags, the type probe's classification, `QuestV2`; CMaNGOS | the giver's offer says daily, weekly or repeatable for the quests actually met (the Forever recorder saves it; the importer doesn't read it yet) | recorder |
| Faction | the API, `QuestV2CliTask` and `PlayerCondition`, CMaNGOS; Forever's cache | `GetQuestFactionGroup` for every loaded quest | probe |
| Race and class | the same | nothing per quest; an offer seen by a character of a race and class is positive evidence only | – |
| Profession and skill level | the client's `QuestV2CliTask` for task quests, the profession only (retail), CMaNGOS (Forever), TrinityCore | `QuestTagInfo.tradeskillLineID` for profession tags | no |
| Holiday and events | the calendar; CMaNGOS's events | `C_AreaPoiInfo.GetEventsForMap`, `C_EventScheduler`: which events run now, where, for how long | probe, then addon |
| Storylines | `QuestLine` and `QuestLineXQuest` | `GetQuestLineInfo`: the name in the player's language, and a second source for membership; `C_CampaignInfo`: campaigns | addon, probe |
| Prerequisites, breadcrumbs, "only one of these" | the API, the client's task-quest tables, TrinityCore, CMaNGOS, hand tables | `IsBreadcrumbQuest` if it works; the offer list shows which step is available now | check |
| Reputation rewards | the API (retail), the quest cache (Forever) | the same figures, for loaded quests | no |
| Renown and friendship requirements | hand table | nothing; `IsQuestFlaggedCompletedOnAccount` and the offer list are the only live availability | – |
| Pins: giver and position | client points, TrinityCore's start points and starters, old pins (retail); CMaNGOS, recorder, hand lists (Forever) | the giver's GUID, name and position at every quest window, on retail too; popups and area triggers placed where they open; hand-in NPCs | recorder |
| Pins: which map | `UiMapAssignment` by our rules | the client's own `GetMapPosFromWorldPos` | probe |
| Availability (obsolete, hidden) | the API's 404s, `QuestV2`, the probe's loads | the offer list per map; `QuestIgnoresAccountCompletedFiltering`; `IsAccountQuest` | probe, addon |
| Account-wide quests | nothing | `IsAccountQuest` | probe → data → addon |
| Expansion | hand menus | `GetQuestExpansion` if it works | check |
| Zone level ranges | nothing | `C_Map.GetMapLevels` | addon |
| Starting item | not shipped (CMaNGOS's `item_template.startquest` has it for old content; the `StartItem` of TrinityCore, the quest cache and `QuestV2CliTask` is the item handed over on accept, not the item that begins the quest: [retail-quest-cache.md](retail-quest-cache.md)) | `C_Item.GetItemNameByID` names it in the player's language; QUEST_DETAIL's payload records it | later |
| Waypoints | TomTom | `C_Map.SetUserWaypoint` and `C_SuperTrack` | addon |
| Treasures and rares | not planned | `C_VignetteInfo` rewardQuestID | later |

## Recommendations, most valuable first

| # | What | Where | Gives | Effort | Risk |
|---|---|---|---|---|---|
| 1 | **A quest-giver recorder on retail too.** Move the Forever recorder's logic into the shared code of the addon, for both games: on GOSSIP_SHOW, QUEST_GREETING, QUEST_DETAIL, QUEST_COMPLETE and QUEST_ACCEPTED, save the giver's kind, ID (`UnitCreatureID` or the GUID) and name, the map and position, the quests offered with their frequency and repeatable flag, the quests taken in, the quest log heading, the start item, and for popups and area triggers the position where the window opened. Add `/qc report`, which says what's gathered and where the file is; a tools script merges a saved-variables file into the pin pipeline the way `Import-ForeverData.ps1` reads the probe's: filling IDs and names, adding pins only for quests that have none, listing every disagreement with an existing pin for review, never moving a pin on its own | addon (shared), tool | NPC IDs for the 363 named and 3,087 nameless pins as they're met, positions for the 12,110 quests without a pin, hand-in NPCs, the server's own recurrence per quest, Forever's new zones faster | small in the addon (the code exists), medium for the merge tool | fills in only from the maintainer's characters and from players who send their file; the saved variable grows with play (cap it); nothing leaves the machine |
| 2 | **A quest-facts probe pass** in the next retail type-probe run and the next Forever quest pass: for every loaded quest also save `IsAccountQuest`, `GetQuestFactionGroup`, `IsImportantQuest`, `IsMetaQuest`, `GetQuestDifficultyLevel`, `GetSuggestedGroupSize`, `GetQuestLineInfo` (questLineID), `C_CampaignInfo.GetCampaignID`, `C_TaskQuest.GetQuestZoneID` for task quests, and try `GetQuestExpansion`, `IsBreadcrumbQuest` and `IsStoryQuest` | probe (#42 and #139), then data and addon | an account-wide field, so the counter and filters can treat a quest another character finished as done for all; a third source for faction; a check of storylines; the campaign; zones for task quests; and whether three undocumented globals answer | small: the probes exist, one 2-hour run on retail | a probe answers only for quests the server still serves (31,425 of 35,023 on 29 September) |
| 3 | **A map-offers probe:** for every map in `UiMap`, `RequestQuestLinesForMap`, then after QUESTLINE_UPDATE save `GetAvailableQuestLines`, `GetForceVisibleQuests`, `C_TaskQuest.GetQuestsOnMap`, `GetQuestHubsForMap`, `GetAreaPOIForMap` with `GetAreaPOIInfo`, `GetEventsForMap`, and once `C_EventScheduler.GetOngoingEvents` and `GetScheduledEvents`; on Forever with the quest points of interest setting on, which the Classic experience preset turns off | probe (both games) | on Forever: whether the server sends offer positions at all (Zephras Isle has pins only from the recorder), what POIs and events exist, whether an invasion or the fishing contest shows up; on retail: how the offers' x, y compare with our pins, and which hubs and events there are | small | the offer list is per character: it shows what this character qualifies for, not every quest |
| 4 | **Scaling-aware levels:** the low-level filter asks `IsQuestTrivial`, and list rows, tooltips and grey pins take `GetQuestDifficultyLevel` and `GetContentDifficultyQuestForPlayer`, for quests whose data is loaded (the quest-name queue already loads what's on screen), falling back to the stored level | addon (both games) | the right "low level" answer for scaling quests and Chromie Time; Blizzard's own colours | medium | needs the quest's data, so the map's pins would queue loads like the NPC names do |
| 5 | **Text from the game:** the storyline name from `GetQuestLineInfo(questID, nil, false)`, the campaign from `C_CampaignInfo`, and a classification or tag line from `QuestUtil.GetQuestClassificationInfo` and `GetQuestTagInfo` (Dungeon, Raid, Group, Elite, Important, Campaign), all in the player's language | addon | the last English storyline names gone; Blizzard's own labels | small | as with names, an English client shows Blizzard's wording where ours differed |
| 6 | **Waypoints without TomTom:** on a pin click, `C_Map.SetUserWaypoint` on the pin and `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`, when TomTom isn't loaded or as an option; `SetSuperTrackedMapPin(QuestOffer, questID)` where the game lists the offer | addon | an arrow to a pin for everyone | small | `CanSetUserWaypointOnMap` must be checked per map, and on Forever at all |
| 7 | **Live refresh on more events:** MAJOR_FACTION_RENOWN_LEVEL_CHANGED, FACTION_STANDING_CHANGED, SKILL_LINES_CHANGED, COVENANT_CHOSEN and PLAYER_LEVEL_UP redraw an open map and list the way the quest events do (map-filter-and-live-refresh.md); CALENDAR_UPDATE_EVENT_LIST already does, for the seasonal filter | addon | gated pins change the moment the requirement is met | small | none |
| 8 | **Follow the game's tracking toggles:** read `C_Minimap.IsTrackingAccountCompletedQuests` and `IsTrackingHiddenQuests` as the defaults of the warband and low-level filters, or as a "follow the minimap" option | addon | one setting instead of two | small | a design decision: the addon's filters have their own defaults and a settings grid |
| 9 | **Availability from the offers:** with the map open, mark the quests `GetAvailableQuestLines` lists as offered to this character now, in progress, or done by the warband, on our pins and in tooltips | addon | the server's own word on availability, for storyline starts, forced quests and tasks | medium | covers only what the game lists; depends on what probe 3 finds |
| 10 | **Conversion check:** run the Forever importer's spawns through `C_Map.GetMapPosFromWorldPos` without an override, and retail's pins through `GetWorldPosFromMapPos` and back, and compare with the tools' results | probe, tool | the client's own map choice for overlapping frames (the importer's rules reach 98.2%); a check of the pipeline's formula | small to medium: the probe needs the world coordinates in its lists | none |
| 11 | **An API check every sweep:** a tool that downloads both branches' documentation for the current builds, lists the functions and events of the namespaces the addon uses, and reports what was added or removed since the saved list, as `Compare-ClientTables.ps1` does for tables (step 2b). The Lua loader written for this review is its core | tool | no silent loss of a function the addon calls at a patch; new functions noticed | small | none |
| 12 | **Zone level ranges** from `C_Map.GetMapLevels` on zone categories | addon | "Westfall (10–15)" in menus or tooltips | small | check Forever answers |
| 13 | **Starting items:** a data field from `ItemSparse`'s `StartQuestID`, CMaNGOS's `item_template.startquest` (Forever) and what the recorder sees, shown as "Starts from: <item>" through `C_Item.GetItemNameByID`. Not from the `StartItem` of TrinityCore, the quest cache or the task table: that is the item handed over on accept ([retail-quest-cache.md](retail-quest-cache.md)) | data, addon | where many of the 2,711 retail quests whose only pins are nameless, and Forever's item-started quests (123 on the first import), come from | medium | the item's name loads like a quest's |
| 14 | **Dungeon entrance pins** from `C_EncounterJournal.GetDungeonEntrancesForMap` for quests whose givers stand inside | addon | pins for the instance quests that have none on Forever, and retail's | medium | later |
| 15 | **Treasures and rares** from `C_VignetteInfo` | recorder, addon | names and places for hidden tracking quests | medium | a new feature, not planned |

## Map-offers probe: first run (7 October 2026, beta build 1.60.1.70245)

Run by the user with `/qcprobe maps` on an Alliance Night Elf rogue, level 12, with 13 Darkshore
quests in the log and the Classic experience preset: all 60 maps in 22 seconds. The saved
variables are `tools/forever_probe_70245/QCForeverProbe.lua` and the reader's rows
`tools/map_offers_70245.tsv` (neither in git).

- **Quest offers: none, on any map.** The server answered every zone's request with
  QUESTLINE_UPDATE within 122 to 228 ms, and every list was empty: no storyline starts, no forced
  quests and no task quests, on the old zones, the capitals, Mount Hyjal, Zephras Isle, Darkspear
  Islands, the Riverglades and Shen'dralas alike. The five maps that sent no update were the world
  map and the four continent maps, which Blizzard's own map never asks for, and their lists were
  empty too. So Forever's new zones won't get pins from the game's offers: the recorder
  (recommendation 1) and the hand lists stay the only sources, as forever.md assumed.
- **Quests in the log come with positions.** `C_QuestLog.GetQuestsOnMap` listed the character's 13
  Darkshore quests with their objective points: on Darkshore, and also on both Kalimdor maps (1414
  and 1464), on Felwood (all 13, at x 17 to 41) and on Winterspring (2, at x 0 to 6). The client
  lists a point on every map whose frame holds it, overlaps included, the same overlap the
  importer works around (#144). Two things follow: the client's map lists aren't an answer key
  for which map a point belongs on (recommendation 10's check, with `GetMapPosFromWorldPos`, is
  still open), and Forever's server does send positions for log quests, although the client's
  `QuestPOIBlob` has 54 rows. A recorder could save a quest's objective and turn-in points while
  it's in the log, which is a different thing from where it's offered.
- **Points of interest: 16, all named; no events, hubs or dungeon entrances.** The six capitals on
  the world map and on their continent maps, and four on Darkspear Islands: Camp, Ruins, Abandoned
  Tower and Shipwreck Cove. The new zone has area POIs where the old zones have none; the
  client-tables review's `AreaPOI` table (372 rows on Forever) is where to look for more.
- **Events: none.** The events schedule has data but lists nothing ongoing or scheduled, and
  `CanShowEvents` is false. The fishing contest, the Scourge Invasion and the War Effort don't
  appear there on the beta (forever.md, open questions).
- **Level ranges: none.** `C_Map.GetMapLevels` gives 0 for every map: recommendation 12 is retail
  only.
- **User waypoints: allowed on 56 of the 60 maps.** Refused only on the four orphan maps (the three
  battlegrounds and Darkspear Islands). Recommendation 6's built-in waypoint works on Forever's
  zones.
- **Dungeon entrances: none** on any map: recommendation 14 is retail only.

The setting the Classic preset turns off, quest points of interest, is the map filter's "Quest
Objectives" entry (the `questPOI` setting), and it was on during the run, with every other entry
of Forever's filter: Show Quest Levels, Quest Difficulty Color, Instance Entrances, Low-Level
Quests and Tracked Items. So the empty offer lists stand. Forever's filter has no "Account
Completed Quests" entry, which retail's has (recommendation 8). The probe now records the
`questPOI` setting and the minimap's quest POI tracking with each run. The retail run,
which compares the game's offers with our pins, follows.

## Map-offers probe: retail run (7 October 2026, build 12.1.0.69933)

Run by the user with `/qcprobe maps 1` on an Alliance Human mage, level 90, with the probe folder
copied into retail's AddOns folder. The quest points of interest setting, the minimap's tracking of
quest points and the tracking of trivial and account-completed quests were all on. The saved
variables are `tools/retail_probe_69933/QCForeverProbe.lua` and the reader's rows
`tools/map_offers_retail_69933.tsv` (neither in git). The reader:
`tools/Report-MapOffers.lua tools/retail_probe_69933/QCForeverProbe.lua QuestCompletist`.

- **The run.** All 1,961 maps in 301 seconds at a 1-second wait; the runbook had guessed up to an
  hour. 1,913 maps answered in 41 to 201 ms, 109 on average. The 48 that didn't are the continents, the world
  map and the cosmic map, which Blizzard's own map never asks for either; their task quests and
  points of interest were listed all the same.
- **What retail serves,** as the baseline for the next run (offers, log quests and the account
  flags depend on the character):

  | What | Rows | Distinct |
  |---|---|---|
  | Quest offers | 439, on 88 maps | 246 quests |
  | Forced-visible quests | 77 | 17 |
  | Task quests | 2,016 | 366 |
  | Quests in the log | 41 | 9 |
  | Points of interest | 459 | 323 |
  | Dungeon entrances, with their journal instance | 290 | 190 |
  | Quest hubs | 14, all on Khaz Algar and Midnight maps | |
  | Events on maps | 63 | |
  | Events schedule | 4 ongoing, 121 scheduled | |
  | Maps with a level range | 182 | |
  | Maps allowing a user waypoint | 657 | |

  Forever's beta served none of the first three, no entrances, hubs or events, and 16 points of
  interest.
- **The offers say what the character has done, not what it can take.** 77 of the 246 carry the
  account-completed flag (another character did them) and 126 the hidden flag, as the tracking
  settings allow. The list alone is not an availability check.
- **Offers against our pins.** All 439 rows are quests in the addon's data. 254 start on the map
  that lists them, and 222 of those have a pin there: 151 within 1.5 map points of the game's
  position, 9 within 3, 31 within 10, 23 within 25 and 8 further. 20 have pins only on another
  map and 12 (10 quests) have none. The other 185 rows are storylines listed on a map other than
  the one they start on.
- **Why the pins differ: they sit where the quest ends.** The 50 quests more than 10 points off, or
  with their pin on another map, were traced with TrinityCore's dump, the client's tables and five
  Wowhead pages, and each claim was re-derived by a second reader.
  - The client's `QuestPOIBlob` holds two points that matter here: `ObjectiveIndex 32` is where
    the quest starts and `-1` is where it is handed in. All 439 offers lie within 10 yards of the
    same quest's point 32. The pipeline reads only point -1 and has called it the giver's pin.
  - TrinityCore's spawns agree. Of 1,421 quests whose starter and ender differ and have spawns on
    the point's map, point -1 is nearer the ender in 1,275, nearer the starter in 13 and within 20
    yards of both in 133. The offer is nearer the starter in 14 of the 15 quests where the two
    differ, and nearer the ender in none.
  - The pin review (PR #217, "October 2026, the pin review" in the pipeline plan) reached the same
    from the starters' side: of 2,622 quests whose TrinityCore starters and enders differ, point -1
    stands at an ender for 1,354 and at a starter for 31. What it lacked is where the start is,
    which the same table gives: point 32.
  - Wowhead agrees on three Midnight quests. "O Lonely Star" (92603) starts with Orin Straylight at
    39.8, 84.2 in Slayer's Rise and ends with another Orin Straylight, an NPC of a different ID, at
    39.4, 38; our pin is at the end, 46 points from where the game offers the quest. "The
    Conquered Heroes" (91145) and "Be Grudge You" (90615) are the same.
  - The pins keep the giver's name and ID but sit at the turn-in. Of the 50: 10 old-world quests
    have TrinityCore spawns at both ends, 3 are confirmed on Wowhead, 24 have an earlier pin of
    ours on the offer as well as the client's two points, 6 rest on the client's two points alone,
    1 (12507) has the ender's spawn at the pin and no known giver, and 6 are only another map ID
    for the same world point (433, 12049, 24824, 25084, 82706, 40029) and need nothing.
  - The pins were right more often before the rebuilds. Of 172 quests with a pin now and one in the
    snapshot of 20 September on the offer's map, the snapshot's pin is within 1.5 points of the
    offer for 159 and today's for 107: 55 quests with the right pin were moved to the turn-in.
  - It is not a few quests. Of 5,202 pairs of a quest and a map whose start and turn-in points are
    more than 1.5 map points apart and that have a pin on the map, 4,886 to 5,081 (by the
    tolerance used) have the pin only at the turn-in, and 1 to 4 only at the start. Where the two
    points coincide, which is most quests as giver and turn-in are one NPC, nothing is wrong.
  - The same reading runs through the tools and two plans. `Build-QuestLocationData.ps1` (the
    filter on index -1), `Get-WagoQuestRequirements.ps1`, `Find-UnavailableQuestCandidates.ps1`
    and, for Forever's start points, `Import-ForeverData.ps1` (Forever's table has 23 index -1
    blobs and 23 index 32 ones). The pipeline plan called -1
    the giver's pin until the pin review corrected it. The Stormwind Harbor entry in
    `data-cleanup.md`, whose decision (the user's) rested on those points being start points, now
    carries a correction and needs a second look:
    for "A Royal Summons" (38035) the harbor point is the turn-in, with TrinityCore's ender Sky
    Admiral Rogers, and the start is point 32 in Dalaran.
- **Quests the game offers that have no pin anywhere.** 11 offered quests (44543, 38777, 38785,
  38796, 38797, 38806, 40024, 40034, 40040, 56775, 82449) and 8 forced-visible ones (81854, 82552,
  83048, 83079, 83538, 84423, 91937, 92364). All 19 are in the data and none is flagged
  unavailable. 18 have a point 32 and no point -1, which is all the pipeline reads; 84423 has no
  point. In all, 4,278 quests have a point 32, no point -1 and no pin: 4,082 task quests (1,387 of
  them world quests) and 196 others, 192 of which convert to a map. Quest by quest:
  - The eight Legion profession "Sample" quests (38777, 38785, 38796, 38797, 38806, 40024, 40034,
    40040) are started by an item. Their start point, or the pin of the NPC who ends them (Mama
    Diggs and Kuhuine Tenderstride in Dalaran), can carry them; the point of 40040 is on no map.
  - 44543 "The Battle for Broken Shore" can join an existing pin; 56775 "Warming Up" has its point
    on open sea, and its Horde and Alliance versions (59926, 43806) are pinless the same way;
    82449 joins the Worldsoul weekly pins in Dornogal.
  - The seven forced world quests stay without pins, as the addon doesn't pin world quests, and 84423
    (a Dracthyr starter in The War Creche, filed under Hallowfall with an all-races mask) has no
    position at all: its category and mask look wrong, which is a separate check.
- **Task quests the data lacks.** The game lists 366 distinct task quests across the maps; 340 are
  in the data and 26 are not. 22 of the 26 are player-facing (14 world quests, a bonus objective
  and 7 quests an NPC starts) and 4 are hidden tracking quests, which stay out. All 26 are in the
  client's `QuestV2` and `QuestV2CliTask` tables on 12.1.0 and 12.1.5. No step of the pipeline
  finds quests in `QuestV2CliTask`: a quest enters only through a giver point, which task quests
  lack, and an answer from Blizzard's web API, which world quests never get. The 340 are there from
  the snapshot of 20 September. The whole table has 6,242 rows, 5,230 in the data and 1,012 not:
  470 hidden trackers and 542 player-facing quests (136 world quests, 52 world events, 36 bonus
  objectives and others), of which this character's maps showed 22. About 7 hidden trackers slip
  past the tracking flag (QuestInfo 265, or "Tracking Quest" in the title). 12.1.5 adds 125 quest
  IDs, none of them among the 26: 25 have a giver point, 8 only objective points and 92 none.
- **Dungeon entrances come with their journal instance,** so step 8's audit of dungeons against
  the Dungeon Journal has a second source for retail (recommendation 14).
- **To check:** the events schedule lists Midnight's world events (Saltheril's Soiree, Stormarion
  Assault, Legends of the Haranir, Prey, and scheduled Void Assaults, Abundance and Curse Surge).
  Whether any quest the addon shows as always available is gated by them is not known.

Nothing in the addon or the pipeline changed with these results. Decisions 8 and 9 below come from
them.

## Probe runs since (9 and 10 October 2026)

The probe ran on both games, with the lists built for the installed builds (retail 12.1.0.69933, the
Forever beta 1.60.1.70291, then 70338 the next day).

- **Maps:** the totals of 7 October again. Retail: 439 offers, 77 forced quests, 459 points of
  interest, 290 dungeon entrances, 14 hubs, 182 maps with a level range and 657 that allow a waypoint
  (2,033 task quests and 46 log quests, which depend on the character and the day). Forever, on both
  builds: no offers, forced quests, tasks, events, hubs or entrances, and 16 points of interest.
- **The quest-facts pass (recommendation 2):** all twelve functions exist on both clients, among them
  `GetQuestExpansion`, `IsBreadcrumbQuest` and `IsStoryQuest`. Retail answers with real values (13
  distinct expansion values, 13 campaigns, 1,570 quest lines among its 33,802 loaded quests, 871
  account-wide quests, 191 meta quests). Forever's are inert: every expansion is -2, and none is a task, world
  quest, campaign or story quest; 11 quests have a quest line. A refused quest saved no facts, so
  whether `GetQuestLineInfo` answers for one, and whether `IsAccountQuest` needs loaded data, were not
  known; the probe now tallies each function on the refused quests (`refusedFacts` in the quest run's
  row), and records the character and level of every run.
- **The quest pass on retail:** all 35,023 quests answered, 33,802 loaded (31,425 on 29 September,
  same build), so 183 newly loaded quests classify as Recurring.
- **The quest pass on Forever differs between runs:** about 80 of 7,320 quests are answered in one run
  and refused in the next (see [forever.md](forever.md), "The beta's answers differ between runs").
- **Pin names:** 10,562 of 10,564 retail pins and 1,503 of 1,503 Forever pins carry the game's own
  NPC name; the two retail ones differ by a trailing space.

## Decisions to take

1. **The recorder on retail** (recommendation 1). Is it wanted, and is it on by default? It writes
   only to the addon's saved variables and keeps the character's faction, race and class, not its
   name. **Recommendation:** yes, on by default with a size cap, since it costs nothing and every
   player who sends a file fills in pins; `/qc report` makes sending easy. It reverses the "Dropped"
   decision of 2026-10-03 in localized-npc-names.md, which foresaw exactly this return.
2. **The probe additions** (2 and 3). Each costs an in-game run: about two hours on retail for the
   facts pass, minutes for the map offers. **Recommendation:** both, the map offers first on the
   Forever beta, as the answer decides whether Forever's new zones can get pins without the recorder.
   The map offers were built and run in October; the user said "go ahead with the facts pass" on
   9 October 2026, and it is built (below).
3. **Scaling-aware levels** (4). It changes what "hide low level quests" hides for scaling quests.
   **Recommendation:** yes, with the stored level as the fallback.
4. **Text from the game** (5). English clients would show Blizzard's storyline names where ours
   differ, as quest and NPC names do. **Recommendation:** yes.
5. **Waypoints** (6): a fallback when TomTom is absent, or always an option? **Recommendation:** a
   fallback first; an option if players ask.
6. **The tracking toggles** (8). **Recommendation:** leave the filters as they are and note the
   toggles in the settings grid plan; the addon's defaults were chosen deliberately (settings-grid.md).
7. **Items 9 to 15:** after the probes report, one PR each, in the order above, as time allows.
8. **Pin start points** (the retail run, and PR #217's pin review, which found the same turn-in
   points from the starters' side and left those pins where the client puts them). The pipeline
   takes the client's turn-in point for the giver's. **Recommendation:** two pull requests. First fill the gaps: a quest with a start point
   (index 32) and no turn-in point gets a pin at the start point, which moves no existing pin (196
   quests, 192 with a map position, including 10 of the 19 above; 82449 by hand), and the
   scripts' comments, plans and Forever's importer say what the points are. Then take the 50
   quests of the shortlist (the 44 that aren't only another map ID): move each to its start point (the client's own
   point 32, so no spawn lookup is needed; #217 suggests the starters' spawns, and the two should
   agree), look at them in game, and decide from that whether the same rule applies to the 5,000 or so
   other pairs. The user's earlier decision that a pin matching the client's data stays is the one
   to revisit, as those pins match the turn-in point, not the start.
9. **Task quests in the database** (542 player-facing rows in `QuestV2CliTask`, 22 of them seen on
   one character's maps). **Recommendation:** yes, as an inflow step in the sweep that takes the
   title, level, type and map from the client's table, with no web API, skips the hidden trackers
   (the flag and QuestInfo 265) and gives no pins, as the 1,425 world quests already in the data
   have none. The database would grow by about 535 quests.

## Decisions (agreed 7 October 2026)

1. **The map-offers probe first** (recommendation 3): built and run the same day; results in
   "Map-offers probe: first run".
2. **A check stays even while it finds nothing.** The map pass stays in every probe run, and its
   totals are compared with the last run's (maintenance.md, step 10 and step 3b). The user's
   reason, in their words: we never know what the client files or the in-game APIs might start
   serving up, which is why these audits were asked for in the first place. The rule covers every
   check this review and the client-tables review add, so recommendation 11, the API check every
   sweep, follows from it; built the same day as `tools/Compare-ApiDocs.ps1` with
   `Read-ApiDocs.lua` (maintenance.md, step 2b under "Before a sweep").

## Open questions (to check in game)

- Does Forever's server send quest-line offers on any map? No, on the first run (above), with the
  quest points of interest setting on, so the setting isn't the reason.
- Do `GetQuestExpansion`, `IsBreadcrumbQuest` and `IsStoryQuest` return anything on 12.1.0 and on
  Forever? (Probe 2.)
- Does `GetQuestLineInfo` answer for a quest whose data hasn't been loaded? Blizzard calls it for
  log quests only. Does `IsAccountQuest` need the data loaded? (Probe 2 loads everything anyway.)
- Does Forever allow user waypoints (`CanSetUserWaypointOnMap`), and does its client return area
  POIs, dungeon entrances, zone level ranges or scheduled events?
- How large does the recorder's saved variable grow over a month of play?

## Out of scope

- Changing the addon or any tool: this review only recommends.
- The client's data tables: `client-tables-review.md` (#203). The tables this review points at
  there, with what that review found: `QuestV2CliTask` (task quests only; an on-accept item for 198,
  breadcrumbs for 11 unrelated pairs, skill filters), `PlayerCondition`, `ParagonReputation` (79
  rows), `AreaPOI` (linked to quests only through `QuestHub`), the campaign tables and `UiMap`'s
  content tuning.
- `C_UnitAuras`, PvP, housing, professions' crafting UI, and everything else the clients document
  that has no bearing on quests, givers, maps, holidays, requirements, storylines, reputation or
  text.
- Player-facing wording for any of the features above: it never names where data comes from.

## Status

- 2026-10-07: review written from the `live` and `forever` branch heads and the wiki's API list;
  nothing in the addon or tools changed. Merged as #204. Next: the user's decisions above, then one
  pull request per item taken, starting with the map-offers probe on the Forever beta and the
  recorder.
- 2026-10-07: the map-offers probe (recommendation 3) built, at the user's choice: `/qcprobe maps`
  in the Forever probe (PR #139's branch, now `tools/ForeverProbe`) asks each map for its quest
  offers, points of interest, events, quest hubs, dungeon entrances, level range and waypoint
  flag, and once per run for the events schedule, the experience preset and the tracking toggles;
  `tools/Report-MapOffers.lua` reads a pass against the addon's quests and pins
  (maintenance.md, "In the game", step 3b). Checked offline with stand-ins for the game: 16 checks
  across maps that answer, answer late, ask for a second request, never answer or refuse. Merged as
  #210.
- 2026-10-07: the first beta run (build 70245; results in "Map-offers probe: first run"): no quest
  offers on any map, log quests with positions, 16 named points of interest, no events, no level
  ranges, no dungeon entrances, user waypoints allowed on the zones, with the quest points of
  interest setting on. The user's decision the same day: the map pass stays in every probe run,
  and no check is dropped for finding nothing (Decisions, above).
- 2026-10-07: the API check every sweep (recommendation 11) built: `tools/Compare-ApiDocs.ps1`
  downloads both branches, reads the documentation with `tools/Read-ApiDocs.lua` (the loader this
  review was made with), saves a per-build list, reports what changed since the last one, and
  exits with 1 when a function the addon calls has gone or changed shape. Baselines saved for live
  12.1.0.69933 (5,539 functions, 1,782 events) and Forever 1.60.1.70245 (5,785 and 1,804); of the
  addon's 45 functions, 44 are documented on live and 45 on Forever, the missing one being
  Forever's `C_SkillInfo.GetSkillLineInfoByID`. Checked against doctored older lists: an added
  function, a removed one, one with changed returns, an added event, and an addon call that had
  vanished or changed shape were each reported, the last two with exit code 1. Next: the retail
  map run and the remaining decisions.
- 2026-10-07: the retail run (build 12.1.0.69933; "Map-offers probe: retail run"): 1,961 maps in
  five minutes, 246 distinct offers, 366 task quests, 459 points of interest and 290 dungeon
  entrances, as the baseline for later runs. It found that the client's `ObjectiveIndex -1` is a
  quest's turn-in and 32 its start, which the pipeline has had the other way round; 19 quests the
  game offers have no pin; and the pipeline never takes in task quests. Nothing changed in the
  addon or tools; decisions 8 and 9 follow.
- 2026-10-07: the user's rule that a feature or check built for one game goes to both unless a
  game can't support it, and the audit of where retail and Forever differ, are in
  `game-parity.md`; the API check now names the functions one game documents and the other
  doesn't, and fails when such a gap closes.
- 2026-10-08: decision 8 taken, by the user, in one step rather than two: the pipeline places each quest
  at its point 32, the client's start, and at its point -1 only when it has none; the turn-in pin goes.
  7,637 quests have other pins, 2,165 of them on another map, and the pins are within 1.5 points of
  242 of the 439 offers the retail run listed (159 before) and more than 5 points from 1 (56 before).
  The 192 quests with a start and no pin followed the same day (below); quest-location-data-pipeline.md,
  "October 2026, pins at the start".
- 2026-10-08: the campaign line of recommendation 5 is in the quest list's tooltip, from
  `C_CampaignInfo` and `C_QuestLine.GetQuestLineQuests` (client-tables-review.md, Status).
- 2026-10-08: the 193 quests with a start and no pin got pins (quest-location-data-pipeline.md,
  "October 2026, pins for quests with only a start point"): 9 of the 11 offered quests that had none,
  the Legion profession "Sample" quests among them. The new names were checked by hand and 11 quests
  moved to their real giver. 82449, a task-table quest, needs a hand entry; the 4,082 task quests in
  the data with a start and no pin stay unpinned, which decision 9 does not cover.
- 2026-10-08: pins from TrinityCore's start points (quest-location-data-pipeline.md, "pins from
  TrinityCore"): 1,453 more quests have a pin. The recorder (recommendation 1) is still the way to
  give the pins that stay nameless, and the quests TrinityCore has no start for, their giver.
- 2026-10-08: recommendation 1 and decision 1: the recorder is built into the addon for both games
  (`qcRecorder.lua`, on by default, checkbox, `/qc report`, `/qc record`), taken as agreed when the user
  said "Let's start on the retail recorder"; the plan, the data model and the list to try in game
  are in [quest-giver-recorder.md](quest-giver-recorder.md). The open question on its size is
  answered for the cap (514 KB on disk at the caps) but a month of play is still unmeasured. The merge
  tool is next; recommendation 2 (one probe for both games) after it.
- 2026-10-09: recommendation 1, the merge tool: `Import-RecordedGivers.ps1` (sweep step 6d), with a
  sandboxed reader and a ledger, fills retail pins' NPC IDs and pins quests no source places, from the
  notes of both games; see [quest-giver-recorder.md](quest-giver-recorder.md), "The merge tool".
- 2026-10-09: recommendation 11, the secrecy watch: `Read-ApiDocs.lua` keeps every flag with `Secret` in its
  name and the preconditions the documentation declares (on functions, events, arguments, returns, payload
  and structure fields and the structures those lead to), `Compare-ApiDocs.ps1` fails the sweep when
  they change on a function the addon calls or an event it listens for, and checks those events
  (18, all documented in both games) for payload and for going. New baseline: live 12.1.0.69933 5,655
  functions, 1,782 events (3,619 and 124 with flags); Forever 1.60.1.70245 5,903 and 1,804 (3,783 and
  125). The counts of 7 October let script objects' methods of one name overwrite each other. Not
  covered: the contents of structures, and the old globals the documentation leaves out.
- 2026-10-09: recommendation 2, the facts pass, built into the probe's quest pass for both games (the user:
  "dev-only addon, data only, go ahead with the facts pass"): for every quest that loads, `isTask`,
  `isWorld`, `taskZone`, `accountQuest`, `factionGroup`, `important`, `meta`, `questLineID`,
  `campaignID`, and the three undocumented `expansion`, `breadcrumb` and `story`, each from the first of
  its functions the client has, with the run's row saying which that was. The probe is `tools/ForeverProbe`,
  a dev-only addon; retail's list is every quest in `data\quests.jsonl` (QuestV2 is not asked), the
  recurring ones first. It still needs the in-game run (about two hours on retail) and readers.
