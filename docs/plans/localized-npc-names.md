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

What the pins hold (14,738 pins, 6,468 distinct NPC IDs):

| Pins | Count | What happens to them |
|---|---|---|
| A name and an NPC ID | 9,063 | Can be looked up |
| A name but NPC ID 0 | 2,588 | Stay English: nothing to look up. Mostly NPCs whose ID was never recorded (Durotan 23 pins, Archmage Khadgar 16, Draka 13), plus objects ("Hero's Call Board", "Wanted Poster") and items |
| No name | 3,087 | Unchanged: they show as "<Yourself>" or under "Other quests" |

## Where the names can come from

**Not from data we ship.** The client's own `Creature` table (wago.tools, build 12.1.0.69933) has
23,074 creatures, but only **676 of our 6,468** pin NPCs. The rest exist only on Blizzard's servers.
Shipping translated names in ten languages would also add to the download and the memory use that
`load-and-memory.md` cut.

**From the game, on request** (checked against Gethe/wow-ui-source `live`, 2026-10-03):
- `C_TooltipInfo.GetHyperlink(hyperlink)` returns a tooltip's data: `lines`, each with `leftText`,
  and a `dataInstanceID`. `GameTooltip:SetHyperlink` uses it. It may return nothing.
- A creature's hyperlink is `unit:Creature-0-0-0-0-<NPC ID>-0000000000`, and its first line is the
  creature's name in the client's language. This is the usual way for an addon to name a creature it
  isn't looking at, but no Blizzard code to check it against turned up, so the probe confirms it
  works in 12.1.
- `TOOLTIP_DATA_UPDATE(dataInstanceID)` fires "when a sparse or cache lookup has resolved", and
  Blizzard's own tooltips rebuild on it (`TooltipDataHandler.lua`). So a creature the client hasn't
  cached should come back without a name, and the name should arrive with that event.
- `GetHyperlink` is marked `SecretArguments = "AllowedWhenUntainted"`. Our argument is a plain string
  we build, so that shouldn't matter, but 12.0's secret values are new enough that the probe checks
  in combat and in an instance.
- The client keeps creature data on disk per language (`Cache\WDB\<locale>\creaturecache.wdb`, 198 KB
  in English and 29 KB in German here), like the quest cache #100 relies on.

**Still unknown, measured in phase 1:**
1. **Does the server answer for NPCs the character has never met?** `localized-quest-names.md`
   assumed the client can only name a creature "once it has seen it". If that's true, only met NPCs
   can be translated, and the rest keep their English names.
2. How fast answers come, how many fail, and whether the server throttles a burst (quest loads
   needed a limit of 4 in flight).
3. Whether anything is blocked in combat or in an instance.
4. How many of our English names differ from Blizzard's.

## Phases (one PR each)

### Phase 1: probe (branch, not merged)

A temporary `/qc npccheck <map ID | all> [in flight]` on a probe branch, like the quest title probe
(#99). For each distinct NPC ID on that map's pins (or on every map), it records:
- whether a name is there straight away, and the raw shape of the reply when it isn't (no data, no
  lines, an empty line or a placeholder);
- for names not there straight away: whether `TOOLTIP_DATA_UPDATE` brought one, and how long it took,
  with a 5 s timeout and the given number in flight (default 4);
- the name, compared with ours.

Results go to a saved variable, as with the title probe, so they can be read offline.

Runs, each on English and then German (whose creature cache is nearly empty):

| Run | Map ID | NPCs |
|---|---|---|
| Elwynn Forest | 37 | 19 |
| Durotar | 1 | 35 |
| Isle of Dorn | 2248 | 136 |
| Stormwind City | 84 | 79 |
| Everything, 4 in flight, then 16 | `all` | 6,468 |

Then two small runs on German: one inside a dungeon, and one while fighting a training dummy.

It answers:
1. **Can unmet NPCs be named at all?** If not, this feature only translates NPCs the player has met,
   which is still the ones near where they play.
2. **The queue settings.** Is a limit needed, and does a 5 s timeout hold up?
3. **Combat and instances.** Do they work there, or do names have to wait until afterwards?
4. **Name differences.** This becomes a report. Fixing names in `qcPinDB` is a separate data decision.

### Phase 2: use the client's name

1. **`qcNpcName(pinData)`:** the stored name for a pin with NPC ID 0 or no name. Otherwise, the
   session's name for that NPC if it has one; else the name from `GetHyperlink` if the client has
   it; else start a request and return the stored English name.
2. **Requests:** each pending NPC remembers its `dataInstanceID`. On `TOOLTIP_DATA_UPDATE` the name
   is read again and kept for the session. With the limit, timeout and single retry the probe
   settles on, an NPC is requested at most twice a session. Nothing is saved: the client's cache
   already keeps names between sessions.
3. **Redraw:** when a name lands for an NPC in an open tooltip, the existing
   `qcRedrawLoadedNames` redraws it once per frame, as for quest names.
4. **Use it at all three sites in the table above.** The pin tooltip keeps grouping stacked pins by
   the name shown. The TomTom waypoint uses whatever name is known when it's clicked, since a
   waypoint's title can't change afterwards.
5. **What gets requested:** the NPCs in a tooltip when it opens. Whether to also request the open
   map's NPCs when the map opens, so hovering is instant, depends on phase 1's speeds (see
   decision 2).
6. **Test harness:** `Test-QuestReachability.lua` needs a `C_TooltipInfo` stand-in that returns
   nothing, or its dummy table ends up used as a name.

### Phase 3: check in game, on English and German

Switch the text language in the Battle.net app (World of Warcraft → cog → Game Settings → Text
Language), not in game: the app resets a choice made in game. Then check map pin tooltips, the quest
tooltip's giver line and a TomTom waypoint, on a map you've played and on one you haven't, and switch
back to English.

## Decisions

1. **English clients use Blizzard's names too.** Where Blizzard's English name differs from ours,
   the English client shows Blizzard's, as quest names already do.
   **Recommendation:** yes. It's the same rule as for quests, and it quietly fixes outdated names.
2. **Request the open map's NPCs when the map opens?** This makes hovering instant, at the cost of
   requests for pins the player may never hover. A busy map has up to ~140 NPCs (Isle of Dorn 136,
   Dornogal 106).
   **Recommendation:** decide after phase 1. Do it only if the whole-set run shows the server answers
   quickly with no throttling. Otherwise request on hover only.

## Out of scope

- **Pins with NPC ID 0** (2,588 named pins): we have no ID for them, so they stay English. Filling
  in the NPC IDs that are missing (Durotan, Khadgar and the like) would let those be translated too.
  That's a data job for later. Objects and items would need their own kind of lookup.
- **The addon's own text,** including "Quest Giver:" and "Unknown or Auto-Accepted Quest": that's
  the hard-coded-text item in `localized-quest-names.md`.
- **Fixing `qcPinDB` names** from the phase 1 report.

## Status

- 2026-10-03: plan written. Next: agree the decisions, then phase 1.
