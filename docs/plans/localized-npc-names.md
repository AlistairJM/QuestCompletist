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
other 145 pins (106 NPC-and-map pairs, mostly on Isle of Thunder, the Jade Forest, Exile's Reach and
Krasarang Wilds), open the row's Wowhead link, read the quest's start NPC and its ID, and put the ID
in NewId. If the quest starts at an object or item, leave NewId blank. Then rerun the tool, which
sets just those, and ask the game for each new ID's name in English: it must be the pin's name.

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
  real ID.
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
  
  Merged as #114. All four phases are done; the 106 Wowhead lookups for pins with cleared IDs remain.
