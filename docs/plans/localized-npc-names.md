# NPC names in the player's language

## Goal

Show quest givers' names in the client's text language. Quest names have been in the client's
language since #100 (`localized-quest-names.md`), but the NPC names next to them still come from
the English names in `qcPinDB` (pin field 3). So a German map pin tooltip shows German quest names
under an English quest giver.

## What's there today (master 34475a8)

| Where | Code | Name used |
|---|---|---|
| Map pin tooltip, giver heading | `qcPinGiverName`, qcCore.lua:2011; drawn by `qcAddGiverToTooltip`, qcCore.lua:2038 | `pinData[3]` |
| Quest tooltip, "Quest Giver:" line | qcCore.lua:1580 | `npcData[3]` |
| TomTom waypoint title | qcCore.lua:1679 | `pin[3]`, else the quest name |

The pin tooltip groups stacked pins by giver name (qcCore.lua:2097), so the name decides which pins
are listed together.

What the pins hold (14,738 pins):

| Pins | Before phase 2 | After phase 2 | What happens to them |
|---|---|---|---|
| A name and an NPC ID | 9,063 (6,468 IDs) | 8,891 | Named by the game, in the player's language |
| A name but NPC ID 0 | 2,588 | 2,760 | Keep our English name. Mostly NPCs whose ID was never recorded (Durotan 23 pins, Archmage Khadgar 16, Draka 13), plus objects ("Hero's Call Board", "Wanted Poster") and items |
| No name | 3,087 | 3,087 | Unchanged: they show as "<Yourself>" or under "Other quests" |

## Where the names can come from

**Not from data we ship.** The client's own `Creature` table (wago.tools, build 12.1.0.69933) has
23,074 creatures, but only **676 of our 6,468** pin NPCs. The rest exist only on Blizzard's servers.
Shipping translated names in ten languages would also add to the download and the memory use that
`load-and-memory.md` cut.

**From the game, on request** (checked against Gethe/wow-ui-source `live`, 2026-10-03, and measured
in phase 1):
- `C_TooltipInfo.GetHyperlink("unit:Creature-0-0-0-0-<NPC ID>-0000000000")` returns the creature's
  tooltip data; the first line's `leftText` is its name in the client's language.
- For a creature the client hasn't cached, it returns nothing, then the game fires one
  `TOOLTIP_DATA_UPDATE` when the name arrives. With nothing returned there's no `dataInstanceID` to
  match the event to, so on any update event the addon re-checks the NPCs it's waiting for.
- `GetHyperlink` is marked `SecretArguments = "AllowedWhenUntainted"`. Our argument is a plain string
  we build, so that shouldn't matter; the German runs check combat and instances.
- The client keeps creature data on disk per language (`Cache\WDB\<locale>\creaturecache.wdb`), like
  the quest cache #100 relies on.

**Nowhere for checking quest givers' IDs automatically** (checked 2026-10-03):

| Source | Quest givers? |
|---|---|
| Blizzard's quest API (35,250 cached responses) | No: title, area, description, requirements and rewards only |
| Blizzard's creature API | Beasts only: it knows 756, the Skullsplitter Panther, but not Chromie, Khadgar or the Kargath Grunt |
| The client's tables (wago.tools) | No quest-giver links and no NPC positions |
| TrinityCore's database | Yes, but only for content before Mists of Pandaria |
| Wowhead | Yes, on every quest page ("Start: ..."), but by hand only: it blocks automated browsing and its terms forbid scraping |
| The game, when a quest window opens | Yes, exactly, but only for quests someone picks up, and an addon can't send anything anywhere |

## Phases (one PR each)

### Phase 1: probe (`tools/npc-name-probe`, #112, not merged)

`/qc npccheck <map ID | all | names> [in flight]` asks `GetHyperlink` for each NPC with a limit in
flight and a 5 s timeout, and records whether the name was there straight away, what brought it and
how long it took, what the first reply held, combat and instance, and the name next to ours.

**English results (2026-10-03, enUS, build 12.1.0.69933).** The first four runs used a version that
only re-checked once a second, so their times are that interval, not the server's.

| Run | NPCs | Took | Straight away | After an update event | On the 1 s re-check | Never |
|---|---|---|---|---|---|---|
| Elwynn Forest (37) | 19 | 5 s | 1 | – | 18 | 0 |
| Durotar (1) | 35 | 9 s | 0 | – | 35 | 0 |
| Isle of Dorn (2248) | 136 | 50 s | 0 | – | 133 | 3 |
| Same-name creatures | 190 | 49 s | 4 | – | 186 | 0 |
| Stormwind City (84) | 79 | 2.3 s | 15 | 64 | 0 | 0 |
| Every pin NPC, 4 in flight | 6,468 | 3.4 min | 1,572 | 4,865 | 0 | 31 |

1. **NPCs the character has never met are named.** The old assumption ("once it has seen it") was
   wrong: 6,437 of 6,468 were named. 1,572 were already cached, mostly by the earlier runs; the
   other 4,865 came from the server.
2. **It's fast:** after the update event, names took 100 ms (median), 165 ms (99th percentile) and
   166 ms at most. Nothing failed or timed out at 4 in flight.
3. **Never named (31 IDs):** 23 are objects or items whose IDs aren't creatures ("Note", "Wanted: The
   Boroughbreaker", "Suspicious Vent"), and 8 are NPCs with IDs no creature has (Watcher Lara 7812;
   Wowhead has her as 73348).
4. **Our pin IDs aren't all right.** Compared pin by pin with the game's English name for the pin's ID:

   | Difference | Pins | IDs | Examples |
   |---|---|---|---|
   | None | 8,828 | 6,289 | |
   | Formatting | 25 | 19 | `Renzik &quot;The Shiv&quot;` → `Renzik "The Shiv"`; "Arch Druid" → "Archdruid" |
   | One name contains the other | 38 | 34 | Names cut at a hyphen: "Locus" → "Locus-Walker", "King Mrgl" → "King Mrgl-Mrgl"; "Khadgar" → "Archmage Khadgar" |
   | Share a word | 11 | 4 | "Belrysa" → "Belysra" (our typo); "Shuja Grimaxe" → "Breka Grimaxe" (a different NPC) |
   | A different creature | 125 | 96 | "Chromie" → "Kargath Grunt", "Sky Admiral Rogers" → "Skullsplitter Panther" |

   For the last group our name is right and the ID is wrong. Spot check: our "Chromie" pin on the
   Timeless Isle gives "Journey to the Timeless Isle" (33231) and has ID 8155. Wowhead has the quest
   starting at Chromie, NPC 73691, and NPC 8155 as the Kargath Grunt. Trusting the ID would have put
   "Kargath Grunt" on Chromie's pin, in every language.

**German results (2026-10-03, deDE, after the English runs; the German cache started nearly empty):**

| Run | NPCs | Took | Straight away | After an update event | Never |
|---|---|---|---|---|---|
| Wald von Elwynn (37) | 19 | 0.8 s | 1 | 18 | 0 |
| Durotar (1) | 35 | 1.3 s | 0 | 35 | 0 |
| Insel von Dorn (2248) | 136 | 20 s | 0 | 133 | 3 |
| Sturmwind (84) | 79 | 3.0 s | 2 | 77 | 0 |
| Dornogal (2339), **inside a dungeon** | 106 | 146 s | 0 | 0 | **106** |
| Orgrimmar (85), **in combat** (all 65 requests) | 65 | 1.5 s | 24 | 41 | 0 |
| Every pin NPC, **16 in flight** | 6,468 | 72 s | 393 | 6,044 | 31 |

1. **German names come back the same way:** "Marshal Dughan" → "Marschall Dughan", `"Auntie" Bernice
   Stonefield` → "Tantchen Bernice Steinfeld", "Lunar Festival Harbinger" → "Botin des Mondfests".
2. **Combat changes nothing.**
3. **Instances hide the names.** Inside the dungeon, the 32 NPCs earlier runs had cached all came back
   as secret values, and the other 74 came back empty and never named. The server did answer: 73
   of those 74 were cached when the next run asked for them outside. So in an instance the addon
   can't read a name it hasn't already learned that session.
4. **16 in flight isn't throttled:** 6,468 NPCs in 72 s (about 84 requests a second), with the same
   timings as at 4 (median 100 ms, 99th percentile 165 ms, at most 192 ms) and no failures.

### Phase 2: correct the pins' NPC IDs (data)

Field 2 of a pin is the quest giver's creature ID, shown in the pin tooltip, and phase 3 asks the
game for that creature's name. So it has to be the right creature, or 0.

`docs/plans/pin-npc-id-decisions.csv`, generated from the English run, has one row per pin;
`tools/Apply-PinNpcIds.ps1` applies it.
- **NAME (63 pins, 52 IDs):** the formatting and "contains" groups, and Belysra. The pin takes the
  game's English name and keeps its ID. Subtitles we'd added go ("Andorgos \<Brood of Malygos\>" →
  "Andorgos").
- **ID (172 pins, 132 IDs):** the "different creature" group; the other three "share a word" pins
  (Spring Gatherer, Hallowfall Flame Guardian, Shuja Grimaxe); "Image of Nozdormu" and "Paper Scrap
  (item)", which could be either; and the 31 never named. Their ID becomes 0 now, and the right ID
  once it's been looked up.

**The lookup, by hand.** 27 of the ID rows are objects or items, marked "leave NewId blank". For the
other 109 pins (91 NPC-and-map pairs, mostly on Isle of Thunder, Krasarang Wilds and the Jade
Forest), open the row's Wowhead link, read the quest's start NPC and its ID, and put the ID in
NewId. If the quest starts at an object or item, leave NewId blank. Then rerun the tool, which
sets just those, and ask the game for each new ID's name in English: it must be the pin's name.
(There were 145 pins, 106 pairs, until October 2026, when four Midsummer Flame Guardian pins went:
each was beside the same guardian's pin with the right ID and the same quest. See data-cleanup.md,
"Found later". The October 2026 pin rebuild then merged four more into a pin of the same name and
map that has its own row, and moved Lor'themar Theron's Isle of Thunder row to the pin that took
his quests; see quest-location-data-pipeline.md.)

**Looked up (2026-10-07).** All 109. Wowhead blocks the browser after about five page loads in a
few minutes, even twenty seconds apart, for ten minutes or so, so TrinityCore's dump
(`tools/tdb`, build 12.1.0) answered first: `creature_queststarter` and `gameobject_queststarter`
for every quest on each pin, with the creature's name from `creature_template`. Wowhead's quest
pages were read for the 10 quests the dump lacks (Argus, Exile's Reach, Nazjatar, the Emerald
Nightmare, the Maw, Valdrakken) and to confirm 12 more; the two never disagreed. Results:
- **100 IDs set** (83 as they were named, 17 renamed). A pin whose quests all start at a creature
  of another name takes that creature's name as well as its ID: the four Noblegarden "Spring
  Gatherer" pins are Spring Collectors, "Finkle Einhorn" is Pip Quickwit in both Blackrock Caverns
  and Hyjal, "Jessera of Mac'Aree" is Maatparm, Krasarang's "Admiral Taylor" at Lion's Landing is
  The Monkey King, and seven had the right ID under a wrong or misspelt name (Zevrist, Nozdormu,
  Kharmarn Palegrip twice, Gaal, Tomas Riogain, Scalecommander Emberthal). Exile's Reach's "Meredy
  Huntswell" keeps its ID, which the game names "Wrathion": check that pin in game. The Maw's
  "Paper Scrap (item)" keeps the Paper Scrap creature's ID under the game's name for it.
- **9 start at objects** (the Sparklematic 5200 twice, the four Stolen Explorers' League Documents,
  Elder Atkanok's shrine, Dire Maul's Broken Trap, Ghostlands' wanted poster): NewId stays blank.
- Where a character has one ID per phase (Lady Jaina Proudmoore, Lor'themar Theron, Kai-Lin
  Honeydew), the pin takes the first; the row notes the others.
The reachability report is identical to master's. Still to do in game: hover the renamed pins and
Exile's Reach's to see the names the client gives their IDs.

**IDs from TrinityCore's quest starters (2026-10-07).** The 109 were the pins whose IDs #113 had
cleared. 2,622 more retail pins had a name and no ID at all (3,087 have neither), most of them
ordinary quest givers in Wrath, Burning Crusade and Draenor zones that were never given one. The
dump's `creature_queststarter` names the creature that starts each quest, so `tools/Fill-PinNpcIds.ps1`
(maintenance.md step 6c) gives such a pin the ID of the creature of exactly its name that starts one
of its quests, taking the one that starts most of them, then the lowest ID, where a character has
one per phase (80 pins). It changes no name and moves no pin:
- **2,259 pins got an ID** (the 2,257 whose name matched to the letter, and two whose name in the
  dump ends in a space). Retail now has 11,223 pins with an ID, 363 with a name and none.
- **227** start at objects, so keep ID 0, as the "Out of scope" bullet says.
- **14** start at creatures of other names, for the decisions file: three names carry our own
  `<Remote>` suffix, Elwynn's two "Marshal McCree" pins hold quests of the other marshals, two Tol
  Barad pins are named "CHANGE_TO_NIL" (their quests start at Kagtha), and a third "Jessup McCree"
  pin in New Tinkertown holds Kharmarn Palegrip's quests, like the two #198 renamed.
- **122** have no start in the dump: nearly all start from an item ("Dargol's Skull", "Captain
  Sanders' Treasure Map"), so there is no creature to name.
The reachability report is identical to master's but for four pins in Ashran now printed with
their ID. `Remove-DuplicatePinQuests.ps1` finds the same 14 pairs as before. A rerun of the pin
pipeline, with its 3-point rule, would merge 57 pins into a pin of the same NPC (one within 1.5
points, the rest 1.6 to 3 apart), moving 66 quests off the client's start point for them. The
pull request after this one does that rerun with the rule tightened to 1.5 points instead, which
merges nothing and gives 250 quests a pin at their start point; quest-location-data-pipeline.md
("October 2026, after the NPC IDs") compares the two.
Forever's pins aren't touched: the importer gives them their IDs from CMaNGOS.

**Filled from pins of the same name (October 2026).** 28 rows had a pin on the same map with the
same name and an ID, which the English probe had already confirmed is that name. Their NewId is
that pin's ID, applied, and their Note says which pin it came from.
- A story character with a different ID in each phase (Captain Garrick, General Nazgrim, Rell
  Nightwind, Shuja Grimaxe, Rivett Clutchpop) took the nearest such pin's ID. That's the right name
  in every language, though it may be another phase's creature.
- With the IDs in, a pipeline rerun put seven pins of one character beside a pin with the same ID,
  so that rebuild was applied too, as the pipeline's 3-point rule asks: Captain Garrick, Warlord
  Breka Grimaxe, Rell Nightwind and Chen Stormstout. The six rows whose pins it merged were
  deleted, as the pin that took their quests already had their ID.

**Checks:**
- 235 lines change, each only in the ID or name field; line endings are unchanged.
- Every one of the 8,891 named pins left with an ID has exactly the game's English name.
- The reachability report is identical to master's except for the stacked-pin count (13,639 →
  13,637): on Isle of Thunder (Taran Zhu) and in Borean Tundra (Elder Atkanok), a pin with no ID and
  its twin with a wrong ID are now identical, so the map stacks them. Their tooltip already listed
  them together, by name.
- Rerunning the tool changes nothing. Filling in one NewId (Chromie, 73691) changes one line. A NewId
  that isn't a number is refused before anything is written.

### Phase 3: use the client's name (code)

1. **`qcNpcName(pinData)`:** the stored name for a pin with NPC ID 0 or no name. Otherwise, the
   session's name for that NPC if it has one; else the name from `GetHyperlink` if the client has
   it; else start a request and return the stored English name.
2. **Requests:** asking for an uncached creature is itself the request, so a hovered pin, the quest
   tooltip and a TomTom click ask straight away. Only an opened map's pins wait in a queue: up to 16
   in flight (phase 1 saw no throttling), the map opened last first. On any `TOOLTIP_DATA_UPDATE`,
   the NPCs being waited for are re-checked. A 5 s timeout frees a request's slot; an NPC that timed
   out isn't asked again that session (the probe saw no failures that a retry would have fixed). A
   name is kept for the session. Nothing is saved: the client's cache keeps names between sessions.
3. **Instances:** a secret value (`issecretvalue`) counts as no name, and nothing is requested or
   retried while `IsInInstance()`; NPCs without a name are tried again after leaving. So inside an
   instance, pins show names learned earlier in the session, and English otherwise.
4. **Redraw:** when a name lands for an NPC in an open tooltip, the existing
   `qcRedrawLoadedNames` redraws it once per frame, as for quest names.
5. **Use it at all three sites in the table above.** The pin tooltip keeps grouping stacked pins by
   the name shown. The TomTom waypoint uses whatever name is known when it's clicked, since a
   waypoint's title can't change afterwards.
6. **What gets requested:** the NPCs on the drawn pins when the map shows a map (decision 2), and
   the NPCs in a tooltip when it opens (the quest tooltip's giver line isn't on the map).
7. **Test harness:** `Test-QuestReachability.lua` needs a `C_TooltipInfo` stand-in that returns
   nothing, or its dummy table ends up used as a name.

### Phase 4: check in game, on English and German

Switch the text language in the Battle.net app, not in game: the app resets a choice made in game.
Then check map pin tooltips, the quest tooltip's giver line and a TomTom waypoint, on a map you've
played and on one you haven't. Inside a dungeon, open a pin tooltip and the quest list: no errors,
and pins show English names or ones learned earlier. (Quest names from #100 haven't been checked
inside an instance either; this covers them.) Then switch back to English.

## Dropped (2026-10-03)

- **A name-to-creature lookup table for pins with NPC ID 0.** It relied on Blizzard's creature search,
  which only knows beasts, so it would have reached about 620 of the 2,588 pins. Correcting IDs in
  `qcPinDB` was preferred to another table. Those pins keep their English name.
- **A recorder of quest givers' real IDs as players play.** It would be exact, but an addon can't send
  data anywhere: it would only fill in from our own characters' saved variables and from players who
  report it. It could come back later together with a `/qc report` command, which would also make
  `qcFlaggedButSeen` easier to report.

## Decisions (agreed 2026-10-03)

1. **English clients use Blizzard's names too.** Where Blizzard's English name differs from ours,
   the English client shows Blizzard's, as quest names already do. Phase 2 makes this safe: every
   remaining ID's English name matches ours.
2. **Request the open map's NPCs when the map opens: yes, outside instances.** It costs requests for
   pins the player may never hover, but a busy map has at most ~140 NPCs (Isle of Dorn 136, Dornogal
   106). At 16 in flight the server answered about 84 requests a second, so an uncached busy map
   takes about 2 s, and most names are there by the time the player hovers a pin.
3. **Correct IDs rather than add a lookup table** (see "Dropped").

## Out of scope

- **Objects and items** among the pins ("Hero's Call Board", "Wanted Poster"): they aren't creatures,
  so they keep their English name, and their NPC ID is 0.
- **The 2,760 named pins with NPC ID 0:** they keep their English name until someone records their
  real ID. (Done for most on 2026-10-07 from TrinityCore's quest starters, `tools/Fill-PinNpcIds.ps1`,
  sweep step 6c: see "IDs from TrinityCore's quest starters" under phase 2.)
- **The addon's own text,** including "Quest Giver:" and "Unknown or Auto-Accepted Quest": that's
  the hard-coded-text item in `localized-quest-names.md`.

## Status

- 2026-10-03: plan written; decisions agreed. Phase 1 probe on `tools/npc-name-probe` (#112); English
  and German runs done (results above; raw data kept in `tools/npc_name_probe_results_all.lua`,
  gitignored). Phase 1 is complete.
- Phase 2 on `data/pin-npc-ids`: 63 pins renamed and 172 IDs cleared; the 106 lookups wait for a
  person with Wowhead. The name-lookup phase was dropped (see "Dropped"). In game (German): Chromie's
  pin shows no wrong ID, and Renzik's shows `"The Shiv"`. Merged as #113.
- Phase 3 on `feat/localized-npc-names`. A scratch simulation (a fake clock, and a fake server that
  replies empty, names the creature 100–180 ms later and fires an update event with no matching ID,
  and hides names in instances) passes 34 checks: map prefetch (Isle of Dorn's 28 givers named
  0.4 s after it opens, each asked once, at most 16 in flight), hover, the quest tooltip's giver
  line, TomTom, instances, timeouts, secret values, stacked pins and redraw batching. 14 deliberate
  breakages were each caught. It found two real problems, both fixed: the quest tooltip's giver line
  asked for every pin it looked through (3,936 NPCs for one tooltip), and a hovered pin waited
  behind its map's queue. #100's quest-name simulation (27 checks) and #96's list simulations give
  identical output on master and the branch, and the reachability report is unchanged.
- Phase 4 in game (2026-10-03):
  - **German:** pin tooltips on a zone never visited, the quest tooltip's giver line and a TomTom
    waypoint showed German names.
  - **Inside a dungeon** (Stormwind Stockade): no errors on the map or in the quest list, so neither
    NPC nor quest names (#100) trip over the hidden names. Names arriving after leaving couldn't be
    checked in game (the instance map can't be opened outside); the simulation covers it.
  - **English:** pins look as before.
  
  Merged as #114. All four phases are done; the Wowhead lookups for pins with cleared IDs remained
  (91 NPC-and-map pairs, 109 pins, since October 2026; 106 pairs to begin with).
- 2026-10-07: the 109 lookups done on `data/pin-npc-id-lookups` (see "Looked up" under phase 2):
  100 IDs set, 17 of those pins renamed, 9 object starts left at 0. Next: the renamed pins and
  Exile's Reach's in game.
- 2026-10-07: 2,259 of the 2,622 pins with a name and no ID given one from TrinityCore's quest
  starters by the new `tools/Fill-PinNpcIds.ps1`, sweep step 6c, on `data/pin-npc-ids-from-tdb`
  (see "IDs from TrinityCore's quest starters" under phase 2). The pipeline rerun the IDs call for
  follows on `data/pin-merges-after-ids`, with the grouping rule tightened from 3 points to 1.5 at
  the user's choice, so that 250 quests get a pin at their client start point instead of 57 pins
  merging (quest-location-data-pipeline.md, "October 2026, after the NPC IDs"). Next: the 14
  other-name pins through the decisions file.
- 2026-10-07: the client's own quest givers, from `CollectableSourceQuestSparse` (the one client
  table that names one; client-tables-review.md), through the new `tools/Apply-ClientQuestGivers.ps1`,
  sweep step 6c, on `data/client-quest-givers` (#208): 94 nameless pins got the client's giver
  and its TrinityCore name, where a spawn stood within 1.5 points; 76 pins whose ID isn't the
  client's giver are listed in `tools\client-giver-report.txt` for review, 47 of them within 1.5
  points of a spawn, so the same spot under another ID of the character. Next: those 76 through
  the decisions file.
