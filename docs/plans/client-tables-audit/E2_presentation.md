# E2_presentation findings

## Summary
76 tables (sound, animation, model, particle, texture, camera, cinematic, scene, weather, emote, movie). Verdict NO for all; none gives quest, zone, giver or availability data. Every column name and every non-chance refs.csv row was checked in all three games. No table in the cluster is read by any repo tool (ReadBy empty).

Quest-adjacent hits (all NO):
- SceneScriptText.Script: 339 distinct quest IDs appear as bare text (flagquest/startquest NNNNN) in 106 MB of scene Lua; 326 are in quests.jsonl (49309 Thunder's Fall, 50049 The Speaker's Perspective, 49425 City of Gold). Ties a scene to a quest, no availability. 171 of 3552 SceneScriptPackage names contain "Quest", 55 begin "Quest - <zone> (<name>)": names only.
- SoundKitEntry.PlayerConditionID: 1,360 of 1,310,132 rows, 22 conditions; five test PrevQuestID (90772, 80321, 78244, 89193, 86903), others ModifierTree. Forever 29 rows, Era 0.
- SoundBusOverride (retail only, 120 rows): 8 conditions, ModifierTree/aura, no quest.
- SoundEmitters (retail 25,987, Forever 1,786, Era 13): MapID, WorldStateExpression (398 retail), Phase gates; ambient sound positions only.
- CinematicCamera.ConversationID (15 retail, 1 Forever): Conversation ids, not quests. Movie.Summary_lang empty in all games.
- Emotes.ClassMask is -1 on all rows; RaceMasks -1 on 479/503 retail.
- refs.csv hits (AnimKitSegment, SoundKitAdvanced, ScreenEffect param columns pointing at QuestV2/UiMap/ModifierTree, shares 0.8-0.95; Forever ScreenEffect.Param_2 -> QuestV2 33 rows; Era AnimKitSegment.BlendOutTimeMs 25 rows) are float/int parameter columns (angles, times, delays): coincidence of small integers.

Games: retail has all 76; Forever and Era hold shrunk subsets (AnimKit 32,671 vs 796 vs 400; SoundKit 337,416 vs 23,331 vs 6,301). Retail-only: Anima*, SoundBusOverride, SoundFilter*, SoundKitFallback, ObjectEffectModifier, BoneWind*. Forever-only: ModelProperties. No quest-related table differs by game.

## Verdicts
See E2_presentation-verdicts.csv.

## Opportunities
None. Nicety only: SceneScriptText gives a scene-to-quest link for ~326 quests.

## Open questions
None needing an in-game test.
