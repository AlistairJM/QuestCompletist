# E1b spells and collections (Spell*, Mount*, Toy, Heirloom, BattlePet*, Transmog*)

## Summary

119 tables: 2 USE (SpellEffect, SpellName, used together), 1 CHECK (Mount), 116 NO. Full list in `E1b_spells_collections-verdicts.csv`.

The one cluster table family that matters is SpellEffect. Effect values (TrinityCore SharedDefines.h SpellEffectName, 359 values; the SpellEffectNames table only carries the enum IDs) include real quest effects, and EffectMiscValue_0 carries the QuestV2 id:

| Effect | Name | Retail rows | Forever rows | EffectMiscValue_0 resolves to QuestV2 (retail / Forever) |
|---|---|---|---|---|
| 150 | QUEST_START | 1,177 | 83 | 1,108 / 82 |
| 16 | QUEST_COMPLETE | 7,415 | 237 | 7,246 / 236 |
| 139 | CLEAR_QUEST | 2,497 | 1 | 2,484 / 1 |
| 147 | QUEST_FAIL | 11 | 1 | 10 / 1 |
| 205 | LAUNCH_QUEST_CHOICE | 438 | 0 | 419 / - |
| 207 | LAUNCH_QUEST_TASK | 110 | 0 | 102 / - |
| 311 | SKIP_QUESTLINE | 11 | 0 | 5 / - |
| 70 | COMPLETE_AND_REWARD_WORLD_QUEST | 1 | 0 | - |

(Counts of 90/134 KILL_CREDIT and 61 SEND_EVENT: their misc value is a creature/event id; the QuestV2 "resolves" there are small-integer coincidences, ignore.) Effect 150 and 16 also hold a quest id in EffectBasePointsF for 26 and 176 rows: chance, not the carrier. Confidence PROVEN: TrinityCore enum + the resolve rates + spell names ("Launch Quest", "Start Quest: Master Sergeant Zaren", "Deputize: Feralas Mission V", "Clear DAILY Patrol SUBQuests 00").

## Opportunities, ranked

1. **Quests started by a spell, not an NPC (retail, USE).** Join effect 150 to our quests: 907 of our 35,544 quests are started by a spell (retail QUEST_START rows 1,173 -> 1,077 distinct quests, 1,013 in QuestV2, 916 of those ours). Only 56 of the 1,011 start spells sit on an item (ItemEffect.SpellID), so the rest are launched by scripts, gossip casts, cinematics or auto-grant. 442 of the 907 have a pin (an NPC also gives them), 465 have none. Of the 868 whose start spell is on no item, 439 are pinned and 429 are not; the 429 unpinned ones sit in Meta Quests 121 (Infinite Research etc.), Azj Kahet 36, Torghast 33, Suramar 10, Assault 9, Vision of Orgrimmar 8, Hallowfall 8, Battle Pets 8. This explains "no pin" for 429 quests (4.4 percent of the 9,768 unpinned). Use: mark as "launched automatically" rather than hunting for a giver. Not read by any tool today (grep of tools/ for SpellEffect: none). The earlier review did not assess this.
2. **Forever: 61 quest-start spells name quests absent from our Forever data (CHECK).** 82 start spells; 54 of the quests are "Deputize: Ashenvale/Hinterlands/Feralas Mission I-XVIII" (ids 81768-81874), cast from items; our data has only the 18 Duskwood missions (81730-81747) plus 98042 "It's All Fun and Games Until...". Also 78684 Mysterious Traveler, 82062 Fire Crown, 85112 Start The Depleted Scythe, 85304 Start Essence of Fire, 91877 Fel Pervasion, 84124/84317 [DNT] Arena Victory (hidden). Whether Ashenvale/Hinterlands/Feralas missions are live or future content needs an in-game check of the Deputy items; do not add them blind.
3. **Forever mounts gated by quests (CHECK).** Mount.PlayerConditionID (6 rows) joins PlayerCondition.PrevQuestID_0: 4490 Summon Felsteed, 1661 The Tome of Nobility (Warhorse), 7631 Dreadsteed of Xoroth, 7647 Judgment and Redemption (Charger) are ours; 94971 (Summon Warhorse, mount 2923) and 97185 (Summon Forsaken Charger, mount 3001) are in QuestV2 but not in our data or answers.jsonl. Two possible new Forever quests. Retail has one such mount quest (73199 Rhapsody in Blue, Tarecgosa's Visage).
4. **Quest-clear and quest-complete spells (info only).** CLEAR_QUEST spells reset repeatable sub-quests (179 of our quests, e.g. Zul'Drak "Clear DAILY Patrol SUBQuests", covenant "Reset ALL Covenant History" x24 each): a Blizzard confirmation that those quests are repeat/reset, not new data. QUEST_COMPLETE: 284 of our retail quests are completed by a spell (22 via item). No addon gain.
5. **Source text "Quest: name Zone: zone" (NO).** Mount 90 rows, Toy 124, BattlePetSpecies 119 carry the quest as a display name only, no ID column (SourceTypeEnum 1 = Quest per Enum.BattlePetSources: mount 120, toy 99, pet 137 rows). Exact name matches to our quests: 37, 35, 54 (ambiguous with duplicates). The game API returns it at runtime; as reward flags it adds nothing to filtering.

## Per-table notes (relevant tables)

**SpellEffect** (retail 632,510 / Forever 42,569 / Era 40,250). Columns: ID, EffectAura, DifficultyID, EffectIndex, Effect, EffectMiscValue_0/1, EffectBasePointsF, EffectTriggerSpell, ImplicitTarget_0/1, SpellID (FK Spell) and numeric coefficients. Same layout on both. Read by no tool. Aura decode (SpellAuraDefines.h): 261 PHASE 1,035 effects, 326 PHASE_GROUP 54, 291 MOD_XP_QUEST_PCT 72, 430 PLAY_SCENE 2,557. A phase aura applies a phase id but nothing in the client ties a quest to it (that is server script), so no per-quest phase data.

**SpellName**: only Name_lang; the label for each start/complete spell.

**Spell** (4 columns), **SpellMisc**: ShowFutureSpellPlayerConditionID 48 rows, 3 conditions, none with quest fields. Rest is attributes/ranges/icons.

**SpellAuraOptions**: refs.csv puts ProcCharges and CumulativeAura on QuestV2 at 81 percent; the values are stack counts up to 21: chance (ByChance 0.067 and 0.115), dismissed. **SpellLearnSpell** (248/52): spell-to-spell, no quest column. **SpellCastingRequirements**: 31 spells need a faction/reputation (Faction FK 100 percent); spell-level. **SpellAuraNames/SpellEffectNames**: enum registries (effect IDs equal TrinityCore).

**SkillLineAbility** (not in this cluster file, read for the focus list): retail 17,990 / Forever 7,834. AcquireMethod 0 Learned, 1 AutomaticSkillRank, 2 AutomaticCharLevel, 3 NeverLearned, 4 LearnedOrAutomaticCharLevel (TrinityCore DBCEnums.h). Flags 0x80 CanFallbackToLearnedOnSkillLearn: the skill is rewarded by a quest for Exile's Reach starters (21 retail rows, 1 Forever row has 0x100). No quest-id column: recipes unlocked by quests are not expressible here. TrivialSkillLineRankHigh resolving to QuestLine in refs.csv is chance (skill ranks). The ClassMask/RaceMasks bits listed 30+ set bits on 30 rows: those are all-classes sentinels (value -1/all ones), not real bits.

**Mount** (1,702 / 141): columns Name, SourceText, MountTypeID, Flags, SourceTypeEnum, SourceSpellID (FK Spell 100 percent), PlayerConditionID (FK PlayerCondition 100 percent). Flags bits unnamed (no Blizzard enum found; GUESS). MountCapability/MountXDisplay conditions: 1 and 18 quest ids, none ours (hidden). MountType/MountTypeXCapability/MountEquipment/MountXSpellVisualKitPicker: mechanics.

**Toy** (1,176 / 20), **Heirloom** (135 / -), **BattlePetSpecies** (3,004 / 114), **BattlePet\*** (retail only except Forever BattlePetSpecies, BattlePetTypeModifier, BattlePetXP): items/creatures, SourceTypeEnum + text, no quest id.

**Transmog\***: TransmogHoliday (41/4): item to Holidays (FK 100 percent). TransmogIllusion.UnlockConditionID: 49 hidden quest IDs. TransmogSet.TrackingQuestID is the quest cluster's (2,181 distinct QuestV2 at 100 percent, noted from refs.csv only).

**SpellXSpellVisual** (art): ViewerPlayerConditionID gives conditions with quest fields (retail 294 conditions, 283 quests, 194 ours). It is visual gating (e.g. a visual only after a quest); no addon meaning.

Art tables (SpellVisual*, SpellChain*, SpellMissile*, SpellActivationOverlay, SpellClutter*, SpellProcedural*, SpellSpecialUnitEffect): presentation, NO. Combat mechanics (SpellCooldowns, SpellPower, SpellRange, SpellDuration, SpellCategories, SpellInterrupts, SpellTotems, SpellShapeshift*, SpellScaling, SpellProcsPerMinute*, SpellEmpower*): NO.

## Games

BattlePet tables and Heirloom, Spell scaling, SpellEmpower are retail only; Forever has 31,863 spells and its own BattlePetXP/BattlePetTypeModifier; Era has Spell tables only (no Mount/Toy). Quest effects exist on both games but differently shaped: Forever has 82 QUEST_START rows, 73 on items, vs retail 956 on non-item spells.

## Things that do not exist

No table maps a recipe, mount, toy or pet to a quest id; no table tells which quest a phase aura belongs to; no table lists "launched automatically" explicitly (SpellEffect 150 is the only evidence).

## Open questions and tests

- In game, with Forever: check the Deputy Ashenvale/Hinterlands/Feralas mission items and quests 94971 / 97185 (`C_QuestLog.GetTitleForQuestID`, `GetQuestInfo`).
- Retail: pick 5 spell-started no-pin quests (e.g. 49539 Warchief's Command: Valley of the Four Winds!, 53885 Isolated Victory) and confirm no NPC offers them.
- Add a join check (effect 150 spells whose ItemEffect is empty vs gossip-launched) only if the owner wants the label; the data above is enough to tag the 465 unpinned quests.
