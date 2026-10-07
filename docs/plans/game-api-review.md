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

`SetAbsMonth`, `GetMonthInfo`, `GetNumDayEvents` and `GetDayEvent` are used, and `GetDayEvent`'s
`title` already names a holiday in the player's language. `GetHolidayInfo(monthOffset, day, index)`
adds the description and texture; `SetMonth`, `GetMinDate`, `GetMaxCreateDate`, `GetRaidInfo`,
`GetEventIndex` and `GetClubCalendarEvents` no; the other 79 create, invite and manage events. No
new data. Event CALENDAR_UPDATE_EVENT_LIST says when the calendar's data has arrived: the holiday
filter could re-read then, instead of keeping "the last answer" until the next read
(maintenance.md, "Holidays"). The other 12 no.

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
`GetGameRuleAsFloat` and the rest. Forever only: `GetForeverExperiencePreset()`, Classic or Modern,
the choice made at character creation, which Forever's UI uses for nameplate and graphics defaults;
`SetForeverExperiencePreset`, `IsHardcoreActive`, `IsSelfFoundAllowed`, `AccountHasSDEnabled`,
`IsSDHDToggleEnabled`, `SetSDHDToggleValue`, and the event GAME_RULES_CHANGED. Use: a runtime way to
tell the games apart (`C_GameRules.GetForeverExperiencePreset ~= nil`) should the two TOCs ever
become one; and check whether the Modern preset changes what the quest UI shows.

### C_SkillInfo (none on live, 8 on Forever; 1 event)

`GetSkillLineInfoByID` is used for the profession skill requirements. `GetNumSkillLines`,
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
| Profession and skill level | CMaNGOS (Forever), TrinityCore | `QuestTagInfo.tradeskillLineID` for profession tags | no |
| Holiday and events | the calendar; CMaNGOS's events | `C_AreaPoiInfo.GetEventsForMap`, `C_EventScheduler`: which events run now, where, for how long | probe, then addon |
| Storylines | `QuestLine` and `QuestLineXQuest` | `GetQuestLineInfo`: the name in the player's language, and a second source for membership; `C_CampaignInfo`: campaigns | addon, probe |
| Prerequisites, breadcrumbs, "only one of these" | the API, TrinityCore, CMaNGOS, hand tables | `IsBreadcrumbQuest` if it works; the offer list shows which step is available now | check |
| Reputation rewards | the API (retail), the quest cache (Forever) | the same figures, for loaded quests | no |
| Renown and friendship requirements | hand table | nothing; `IsQuestFlaggedCompletedOnAccount` and the offer list are the only live availability | – |
| Pins: giver and position | client points, old pins, TrinityCore IDs (retail); CMaNGOS, recorder, hand lists (Forever) | the giver's GUID, name and position at every quest window, on retail too; popups and area triggers placed where they open; hand-in NPCs | recorder |
| Pins: which map | `UiMapAssignment` by our rules | the client's own `GetMapPosFromWorldPos` | probe |
| Availability (obsolete, hidden) | the API's 404s, `QuestV2`, the probe's loads | the offer list per map; `QuestIgnoresAccountCompletedFiltering`; `IsAccountQuest` | probe, addon |
| Account-wide quests | nothing | `IsAccountQuest` | probe → data → addon |
| Expansion | hand menus | `GetQuestExpansion` if it works | check |
| Zone level ranges | nothing | `C_Map.GetMapLevels` | addon |
| Starting item | not shipped (TrinityCore, CMaNGOS and Forever's cache have it; the client's `QuestV2CliTask` has it for 198 task quests only, per the client-tables review) | `C_Item.GetItemNameByID` names it in the player's language; QUEST_DETAIL's payload records it | later |
| Waypoints | TomTom | `C_Map.SetUserWaypoint` and `C_SuperTrack` | addon |
| Treasures and rares | not planned | `C_VignetteInfo` rewardQuestID | later |

## Recommendations, most valuable first

| # | What | Where | Gives | Effort | Risk |
|---|---|---|---|---|---|
| 1 | **A quest-giver recorder on retail too.** Move the Forever recorder's logic into the shared code of the addon, for both games: on GOSSIP_SHOW, QUEST_GREETING, QUEST_DETAIL, QUEST_COMPLETE and QUEST_ACCEPTED, save the giver's kind, ID (`UnitCreatureID` or the GUID) and name, the map and position, the quests offered with their frequency and repeatable flag, the quests taken in, the quest log heading, the start item, and for popups and area triggers the position where the window opened. Add `/qc report`, which says what's gathered and where the file is; a tools script merges a saved-variables file into the pin pipeline the way `Import-ForeverData.ps1` reads the probe's: filling IDs and names, adding pins only for quests that have none, listing every disagreement with an existing pin for review, never moving a pin on its own | addon (shared), tool | NPC IDs for the 363 named and 3,087 nameless pins as they're met, positions for the 12,110 quests without a pin, hand-in NPCs, the server's own recurrence per quest, Forever's new zones faster | small in the addon (the code exists), medium for the merge tool | fills in only from the maintainer's characters and from players who send their file; the saved variable grows with play (cap it); nothing leaves the machine |
| 2 | **A quest-facts probe pass** in the next retail type-probe run and the next Forever quest pass: for every loaded quest also save `IsAccountQuest`, `GetQuestFactionGroup`, `IsImportantQuest`, `IsMetaQuest`, `GetQuestDifficultyLevel`, `GetSuggestedGroupSize`, `GetQuestLineInfo` (questLineID), `C_CampaignInfo.GetCampaignID`, `C_TaskQuest.GetQuestZoneID` for task quests, and try `GetQuestExpansion`, `IsBreadcrumbQuest` and `IsStoryQuest` | probe (#42 and #139), then data and addon | an account-wide field, so the counter and filters can treat a quest another character finished as done for all; a third source for faction; a check of storylines; the campaign; zones for task quests; and whether three undocumented globals answer | small: the probes exist, one 2-hour run on retail | a probe answers only for quests the server still serves (31,425 of 35,023 on 29 September) |
| 3 | **A map-offers probe:** for every map in `UiMap`, `RequestQuestLinesForMap`, then after QUESTLINE_UPDATE save `GetAvailableQuestLines`, `GetForceVisibleQuests`, `C_TaskQuest.GetQuestsOnMap`, `GetQuestHubsForMap`, `GetAreaPOIForMap` with `GetAreaPOIInfo`, `GetEventsForMap`, and once `C_EventScheduler.GetOngoingEvents` and `GetScheduledEvents`; on Forever under both experience presets | probe (both games) | on Forever: whether the server sends offer positions at all (Zephras Isle has pins only from the recorder), what POIs and events exist, whether an invasion or the fishing contest shows up; on retail: how the offers' x, y compare with our pins, and which hubs and events there are | small | the offer list is per character: it shows what this character qualifies for, not every quest |
| 4 | **Scaling-aware levels:** the low-level filter asks `IsQuestTrivial`, and list rows, tooltips and grey pins take `GetQuestDifficultyLevel` and `GetContentDifficultyQuestForPlayer`, for quests whose data is loaded (the quest-name queue already loads what's on screen), falling back to the stored level | addon (both games) | the right "low level" answer for scaling quests and Chromie Time; Blizzard's own colours | medium | needs the quest's data, so the map's pins would queue loads like the NPC names do |
| 5 | **Text from the game:** the storyline name from `GetQuestLineInfo(questID, nil, false)`, the campaign from `C_CampaignInfo`, and a classification or tag line from `QuestUtil.GetQuestClassificationInfo` and `GetQuestTagInfo` (Dungeon, Raid, Group, Elite, Important, Campaign), all in the player's language | addon | the last English storyline names gone; Blizzard's own labels | small | as with names, an English client shows Blizzard's wording where ours differed |
| 6 | **Waypoints without TomTom:** on a pin click, `C_Map.SetUserWaypoint` on the pin and `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`, when TomTom isn't loaded or as an option; `SetSuperTrackedMapPin(QuestOffer, questID)` where the game lists the offer | addon | an arrow to a pin for everyone | small | `CanSetUserWaypointOnMap` must be checked per map, and on Forever at all |
| 7 | **Live refresh on more events:** MAJOR_FACTION_RENOWN_LEVEL_CHANGED, FACTION_STANDING_CHANGED, SKILL_LINES_CHANGED, COVENANT_CHOSEN, PLAYER_LEVEL_UP and CALENDAR_UPDATE_EVENT_LIST redraw an open map and list the way the quest events do (map-filter-and-live-refresh.md) | addon | gated pins change the moment the requirement is met; holidays read as soon as the calendar answers | small | none |
| 8 | **Follow the game's tracking toggles:** read `C_Minimap.IsTrackingAccountCompletedQuests` and `IsTrackingHiddenQuests` as the defaults of the warband and low-level filters, or as a "follow the minimap" option | addon | one setting instead of two | small | a design decision: the addon's filters have their own defaults and a settings grid |
| 9 | **Availability from the offers:** with the map open, mark the quests `GetAvailableQuestLines` lists as offered to this character now, in progress, or done by the warband, on our pins and in tooltips | addon | the server's own word on availability, for storyline starts, forced quests and tasks | medium | covers only what the game lists; depends on what probe 3 finds |
| 10 | **Conversion check:** run the Forever importer's spawns through `C_Map.GetMapPosFromWorldPos` without an override, and retail's pins through `GetWorldPosFromMapPos` and back, and compare with the tools' results | probe, tool | the client's own map choice for overlapping frames (the importer's rules reach 98.2%); a check of the pipeline's formula | small to medium: the probe needs the world coordinates in its lists | none |
| 11 | **An API check every sweep:** a tool that downloads both branches' documentation for the current builds, lists the functions and events of the namespaces the addon uses, and reports what was added or removed since the saved list, as `Compare-ClientTables.ps1` does for tables (step 2b). The Lua loader written for this review is its core | tool | no silent loss of a function the addon calls at a patch; new functions noticed | small | none |
| 12 | **Zone level ranges** from `C_Map.GetMapLevels` on zone categories | addon | "Westfall (10–15)" in menus or tooltips | small | check Forever answers |
| 13 | **Starting items:** a data field from TrinityCore, CMaNGOS and Forever's cache (the recorder adds what it sees), shown as "Starts from: <item>" through `C_Item.GetItemNameByID` | data, addon | where many of the 2,711 retail quests whose only pins are nameless, and Forever's item-started quests (123 on the first import), come from | medium | the item's name loads like a quest's |
| 14 | **Dungeon entrance pins** from `C_EncounterJournal.GetDungeonEntrancesForMap` for quests whose givers stand inside | addon | pins for the instance quests that have none on Forever, and retail's | medium | later |
| 15 | **Treasures and rares** from `C_VignetteInfo` | recorder, addon | names and places for hidden tracking quests | medium | a new feature, not planned |

## Decisions to take

1. **The recorder on retail** (recommendation 1). Is it wanted, and is it on by default? It writes
   only to the addon's saved variables and keeps the character's faction, race and class, not its
   name. **Recommendation:** yes, on by default with a size cap, since it costs nothing and every
   player who sends a file fills in pins; `/qc report` makes sending easy. It reverses the "Dropped"
   decision of 2026-10-03 in localized-npc-names.md, which foresaw exactly this return.
2. **The probe additions** (2 and 3). Each costs an in-game run: about two hours on retail for the
   facts pass, minutes for the map offers. **Recommendation:** both, the map offers first on the
   Forever beta, as the answer decides whether Forever's new zones can get pins without the recorder.
3. **Scaling-aware levels** (4). It changes what "hide low level quests" hides for scaling quests.
   **Recommendation:** yes, with the stored level as the fallback.
4. **Text from the game** (5). English clients would show Blizzard's storyline names where ours
   differ, as quest and NPC names do. **Recommendation:** yes.
5. **Waypoints** (6): a fallback when TomTom is absent, or always an option? **Recommendation:** a
   fallback first; an option if players ask.
6. **The tracking toggles** (8). **Recommendation:** leave the filters as they are and note the
   toggles in the settings grid plan; the addon's defaults were chosen deliberately (settings-grid.md).
7. **Items 9 to 15:** after the probes report, one PR each, in the order above, as time allows.

## Open questions (to check in game)

- Does Forever's server send quest-line offers on any map, and does the Modern experience preset
  change that? (Probe 3.)
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
  there, with what that review found: `QuestV2CliTask` (task quests only; a start item for 198,
  breadcrumbs for 11 unrelated pairs, skill filters), `PlayerCondition`, `ParagonReputation` (79
  rows), `AreaPOI` (linked to quests only through `QuestHub`), the campaign tables and `UiMap`'s
  content tuning.
- `C_UnitAuras`, PvP, housing, professions' crafting UI, and everything else the clients document
  that has no bearing on quests, givers, maps, holidays, requirements, storylines, reputation or
  text.
- Player-facing wording for any of the features above: it never names where data comes from.

## Status

- 2026-10-07: review written from the `live` and `forever` branch heads and the wiki's API list;
  nothing in the addon or tools changed. Next: the user's decisions above, then one pull request per
  item taken, starting with the map-offers probe on the Forever beta and the recorder.
