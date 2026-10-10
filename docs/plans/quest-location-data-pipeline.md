# Plan: Rebuilding Quest Location Data from wago.tools

## Context

This addon's map-pin feature (`qcPinDB.lua`) hasn't been meaningfully refreshed in years, and we'd deferred a decision on whether to keep investing in it at all, since the base WoW client now shows its own quest markers. That changed when we found a legitimate, verified way to source fresh quest-giver location data directly from Blizzard's client files via wago.tools — something neither Blizzard's own Data API nor Wowhead (whose ToS explicitly forbids scraping) can offer. This plan scopes the work to actually use that.

**Scope for this plan: Retail only.** Classic Era/Anniversary/MoP Progression and Forever are explicitly out of scope for now, per the earlier "Retail first" decision — see "Possible future extensions" at the end for why they might still be reachable later.

## What we've already proven (this session)

- **Data source**: wago.tools exposes raw Blizzard client DB2 tables via an open, undocumented-ToS-restriction, no-auth API. This is raw client data, not a third party's curated/copyrighted content — same legal footing as typing quest names in by hand, which this addon already does.
- **The tables that matter**:
  - `QuestPOIBlob` (72,698 rows): links `QuestID` → `UiMapID` + one or more point-blobs. `ObjectiveIndex = -1` marks the quest's own pin (a single point), which is the quest giver's where the quest starts and ends in one place and otherwise often the turn-in ("October 2026, the pin review", below), and `ObjectiveIndex = 32` marks its start point ("October 2026, the start points", below); `ObjectiveIndex >= 0` marks a multi-point objective-area outline (meaning of the paired `ObjectiveID` is still unresolved — see Open Questions).
  - `QuestPOIPoint` (172,609 rows): raw X/Y/Z world coordinates per point, keyed by `QuestPOIBlobID`.
  - `UiMapAssignment`: per-`UiMapID` world-space bounding box (`Region_0`, `Region_1`, `Region_3`, `Region_4`).
- **Verified conversion formula** (confirmed against two independent, real in-game landmark readings — Goldshire and Northshire Abbey on the Elwynn Forest map — both within ~1 percentage point):
  ```
  mapX = (Region_4 - worldY) / (Region_4 - Region_1)
  mapY = (Region_3 - worldX) / (Region_3 - Region_0)
  ```
  (World `+X` = north, world `+Y` = west; both axes are swapped and inverted relative to top-left-origin map percentages — this matches WoW's well-known coordinate convention.)
- **End-to-end proof of concept**: quest 11 ("Riverpaw Gnoll Bounty," a quest already in our own `qcQuestDatabase`, tagged Elwynn Forest) → resolved via `QuestPOIBlob`/`QuestPOIPoint` → converted to `(24.2%, 74.5%)` on the Elwynn Forest map, consistent with gnoll camps being in the zone's southern reaches.

## Phase 0 findings (resolved)

- **`qcPinDB.lua` entry schema, fully confirmed from code (`qcCore.lua`) and data:**

  | Field | Meaning |
  |---|---|
  | `[1]` | Icon type, `1`–`11` (normal/repeatable/profession/daily/seasonal/special/weekly/monthly/class/kill/legendary) |
  | `[2]` | Quest-giver creature (NPC) ID |
  | `[3]` | NPC name (string, or `nil` for special-case pins) |
  | `[4]`, `[5]` | X/Y position, **0–100 scale** (matches in-game hover readout directly — multiply our `[0,1]` formula output by 100) |
  | `[6]` | List of quest IDs offered/completed at this pin |
  | `[7]` (optional) | Free-text note, seen on special-case pins (e.g. "Provided when you assist an Injured Razer Hill Grunt") |

  Pins originally led with a map level (the pre-8.0 dungeon floor). Since 8.0 every floor has its own
  `UiMapID`, so the field only ever hid pins. It was removed in September 2026, and every field
  above moved down one.

  `qcPinDB[UiMapID]` keys are confirmed intended as live `UiMapID` (via `qcRefreshPins(UiMapID, mapLevel)`). We also directly caught a real drift bug this pipeline will fix: `qcPinDB[1]` is commented `Durotar`, but current `UiMapID 1` is actually **Kalimdor** (the whole continent) — concrete proof the existing pin data has drifted from the modern ID space.

- **Multi-row `UiMapAssignment` entries, checked across the full table (1,956 distinct `UiMapID`s):** the vast majority (e.g. Stormwind City, `UiMapID 137`, 22 rows) share one identical bounding box across all rows — those extra rows just tag different building/WMO sub-areas, not different geography, so picking any row is safe. But **150 UiMapIDs (~7.7%) have genuinely different bounding boxes across rows.** Phase 1's script needs to handle this: for those maps, try each candidate region and keep whichever produces a normalized result inside `[0, 1]`, rather than assuming one row per map.

  Since September 2026 the script keeps the region that contains the point, preferring one on the location's own instance (a phased copy of a zone has its own instance but shares the zone's coordinates), and scales into the part of the map that region covers (`UiMin`..`UiMax`), as each zone's region does on a continent map. A point no region contains is skipped. It used to fall back to the first region, which wrote 31 pins off their maps' edges, and ignoring `UiMin`/`UiMax` put Broken Isles pins well south of Dalaran.

## Open questions (still unresolved, may need work during Phase 1)

1. **`ObjectiveID`/`ObjectiveIndex` meaning beyond "-1 = turn-in, 32 = start."** Didn't resolve what table (if any) `ObjectiveID` cross-references. Not blocking for giver pins, but blocks pulling in richer "objective area" pins as a bonus.
2. **No published rate limit for wago.tools.** Should self-impose a conservative delay between requests when pulling ~250K+ rows across tables, out of politeness, even though nothing prohibits it outright.
3. **Some old quests only have continent-level POI data, not zone-level.** Checked across all 109 known Durotar quests: 56 resolve to `UiMapID 463` (the real zone map), but 42 resolve to `UiMapID 1` (the Kalimdor continent) — a real pattern, not a fluke. This looks like a genuine gap in Blizzard's own source data for older vanilla content that never got a fine-grained pin when the modern per-zone map system rolled out. Not fixable by us; the pin will only show at the continent zoom level for these quests. Not blocking — a continent-level pin is still better than none — but worth knowing before treating every conversion as equally precise.

## Phase 1 status: MVP built and working

(This section records the first run. Since #123 the pipeline works from `data\pins.jsonl` and writes
`tools\pins_candidate.jsonl` for review; the current steps are in `docs/maintenance.md`, step 6.)

A working pipeline exists (`tools/Build-QuestLocationData.ps1` → `tools/Join-LocationsWithExisting.ps1` → `tools/Assemble-PinDB.ps1`), producing `tools/qcPinDB_candidate.lua` (syntax-checked, valid Lua). Numbers from the current run:

- 17,885 quest-giver locations converted from wago.tools source data, zero pipeline failures
- Cross-referenced against our own `qcQuestDatabase`: 17,260 matched, 625 quest IDs found in Blizzard's data with no match in ours at all (a bonus gap list)
- Measured drift against the *existing* `qcPinDB.lua`: of 13,004 quests that already had a pin, **1,978 point at the wrong map entirely and 3,242 are on the right map but the wrong spot** — only 7,784 (60%) were already accurate. Plus 4,881 quest-giver locations that never had a pin at all.
- NPC identity (creature ID/name) and icon type are borrowed from the existing pin data by quest ID wherever a match exists (13,004 quests).
- **Proximity matching** (added after checking whether NPC identity is recoverable any other legitimate way — it mostly isn't; that association is server-side, not in any client data source we can use): for the 4,881 quests with no prior pin, checked whether a *different*, already-known NPC sits within 1.5 map points on the same `UiMapID` (most NPCs offer several quests, so a nearby known NPC is very likely the same one). This resolved **1,801 of 4,881** (37%). Spot-checked the matches — all plausible, well-known named NPCs (Voren'thal the Seer, A'dal, Admiral Odesyus), not noise.
- Remaining **3,080 quests genuinely have no recoverable NPC identity** — icon type defaults to "normal" unless the quest's profession flag says otherwise, and NPC identity is left blank (`0`/`nil`), honestly, rather than guessed.
- Grouped 17,885 quest-giver locations into **10,983 pins** (down from 12,524 before proximity matching, since more quests now correctly collapse under a shared NPC instead of sitting as isolated "unknown" singleton pins).

**Not sourced from Blizzard's REST API at all** — the whole location pipeline runs on wago.tools' raw client data only, since the Blizzard API has no quest-giver/location endpoints whatsoever (confirmed earlier). The API remains a legitimate, separate option for enriching the 625 gap-list quests' names/levels (not yet done).

**Integration decision confirmed: merge, not replace** (see Phase 3 above) — the merge logic itself (folding in untouched old (quest, NPC) pairs the new pipeline has no data for) is still not built.

**Not yet done:** the candidate file hasn't been spot-checked in-game, the quest/NPC merge logic isn't built, and nothing has been merged into the real `qcPinDB.lua` or opened as a PR. That's the natural next step whenever this picks back up.

## Phased plan

**Phase 0 — Finish reverse-engineering (small, focused)**
- Fully document `qcPinDB.lua`'s current entry schema from the existing data + `qcCore.lua` usage.
- Validate the conversion formula against 2-3 more `UiMapID`s, including at least one multi-row case (e.g., Stormwind City), to confirm it generalizes or to learn the special-case handling needed.
- (Optional, can defer) Resolve `ObjectiveID`'s meaning.

**Phase 1 — Build the offline pipeline (a script, not live in-game code)**
- Pull full `QuestPOIBlob`, `QuestPOIPoint`, `UiMapAssignment`, and `Map` tables from wago.tools once, save locally.
- Join: quest → blob(s) → point(s) → converted `(mapX, mapY)` per `UiMapID`.
- Cross-reference against our existing `qcQuestDatabase`:
  - Quests present in both → candidate updates/verification.
  - Quests in wago.tools data but missing from `qcQuestDatabase` → a bonus gap list, similar to the 85-zone gap analysis we already did.
- Emit a new/patched `qcPinDB.lua` (or a diff against the current file) in the correct Lua table shape from Phase 0.

**Phase 2 — Validation**
- Spot-check a random sample of converted pins against known-good positions, ideally via more in-game hover checks (the same method that caught our first formula being wrong).
- Automated sanity checks: reject/flag any converted percentage outside `[0, 1]`, or any `UiMapID` with no matching `Map`/`UiMapAssignment` row.

**Phase 3 — Integration**
- **Decided: merge, not replace.** Checked this directly: quests like 13479 ("Spring Gatherer," a Noblegarden vendor offered from 5 different cities in the old data) and 6384 (offered by two alternate NPCs, "Burok" and "Devrak") have **zero** entries anywhere in the new pipeline's output — Blizzard's current client data has no giver-pin at all for them, likely old/holiday content that predates the modern per-quest POI system (same family of gap as the continent-only-pin issue above). Outright replacement would silently delete real, currently-valid pins for these and probably many similar quests.
  - Correct merge rule: work at (quest, NPC) granularity, not just quest. For any (quest, NPC) pair present in the old data with no corresponding entry anywhere in the new pipeline's output, keep the old entry untouched. Where the new pipeline does have data for a (quest, NPC) pair, prefer it — that's where we've proven it's more accurate (the 40% drift figure).
  - This merge logic isn't built yet — `Assemble-PinDB.ps1` currently only emits from the new pipeline's data and doesn't fold in untouched old entries. That's the next concrete step.
- Revisit the "should the live map-pin feature still exist" question now that fresh, verified data is actually possible — this plan doesn't presume the answer, it just makes the answer informed instead of guessed.

## October 2026 rebuild

On 2026-10-04 the September 30 locations were applied again, after a review of the 158 lines a
rerun changed. None came from new client data: the pipeline was catching up with changes made to
the pins since its last run on September 29.

- **47 merges of two pins of one quest giver.** 32 of the pins that joined another still carried a
  pre-8.0 map floor on September 29, which hid them and kept them apart; drawn since September 30,
  they sat beside the same NPC's pin (Lord Jorach Ravenholdt and Archmage Modera in Legion's
  Dalaran, Odyn in Skyhold). 5 were the Demon Hunter class hall pins
  moved to the Fel Hammer's maps that day. 6 have no NPC ID, so join by name: Kairoz and Emperor
  Shaohao, moved to the Timeless Isle's map, and Warlord Breka Grimaxe, General Nazgrim and
  Lor'themar Theron, whose wrong IDs #113 cleared. The rest were pairs on exactly the same spot.
  Moving a pin's quests to their giver's other pin shifted them by up to 2.05 points; none of those
  has a start point in the client's data. Two quests that do start exactly where they were moved
  1.1 points, within the pipeline's 1.5-point "same spot": General Nazgrim's "The Final Blow!" and
  Lor'themar Theron's "To the Skies!".
- **3 quests moved to their own pin where the client's data starts them**, 1.5 to 3 points from a
  giver pin with no NPC ID: Sky Admiral Rogers (the Jade Forest), Korven the Prime (Dread Wastes) and
  Jessup McCree (New Tinkertown).
- **3 quests taken off a pin, the client's data starting them elsewhere:** "Abundant Offerings" from
  Zul'Aman's map edge (x = 100, left by the old off-map conversion; its pins in Eversong Woods and
  two other maps stay), "We Have a Problem" from the Vindicaar (it starts in Eredath) and "Working
  for G.E.T.A." from Gig Sheets (it starts at the G.E.T.A. board).
- **2 quest lists in a new order:** Marshal Gabriel's (57754 back in sequence after #105's typo fix)
  and Ulfar's.

Checks: no quest left a map but those three; no tooltip lists a quest twice; 14,726 pins became
14,680, and the map draws 8,383 pin icons instead of 8,401. The reachability report differs only in
five pins that held nothing but quests with no data, and joined their giver's pin. A rerun now
leaves the pins byte-identical. Five rows of `pin-npc-id-decisions.csv` were for merged pins: four
were deleted, as the pin that took their quests has a row of its own, and Lor'themar Theron's moved
to the pin that took his quests.

Later the same day, filling 28 NPC IDs from pins of the same name (localized-npc-names.md) gave seven
pins the ID of a pin of that character within 3 points, so the rebuild was applied again: 14,673
pins, and a rerun still leaves them byte-identical.

## October 2026, after the NPC IDs

On 2026-10-07 `Fill-PinNpcIds.ps1` gave 2,259 pins that had a name and no NPC ID their giver's
ID (localized-npc-names.md, "IDs from TrinityCore's quest starters"). maintenance.md asks for a
pipeline rerun after any ID change, because a known NPC's quests group onto one pin where they
start close together. The rerun, on the same client data (the September 30 locations, nothing
refreshed), was done twice, with the two groupings compared, and the user chose the second:

- **With the 3-point rule the pipeline had used until then,** 57 pins merged into 54 pins of the
  same NPC on the same map (1 within 1.5 points, 22 within 2, 19 within 2.5, 13 within 3; the
  furthest 2.99, High Commander Halford Wyrmbane's third pin in Dragonblight), and nothing else
  changed. But 81 quest placements moved, 73 of them quests with a start point in the client's
  data on that map, and 66 of those left it: they had been within 1.5 points of it, 55 exactly on
  it, and would have sat 1.6 to 3 points away. In October's rebuild only two such quests had
  moved, by 1.1 points. The rule had been doing what it was designed to do, since without IDs the
  same pins had been kept apart by the 1.5-point rule for pins without one, but at this scale it
  moved quests off the client's own start points.
- **With a 1.5-point rule, the one chosen** (`$npcGroupThreshold` in `Assemble-PinDB.ps1`, applied
  in the pull request after the IDs'), nothing merges. Instead 250 pins split off existing pins:
  a known NPC's quest that the client starts 1.5 points or more from the NPC's pin gets a pin of
  its own at that start point, where the earlier runs had grouped it onto the NPC's pin up to 3
  points away. 316 quest placements moved (bands: 141 within 2 points, 111 within 2.5, 63 within
  3, and Valeera Sanguinar's "Champion: Valeera Sanguinar" in Legion's Dalaran by 3.05, onto its
  start point). Of 325 start-point checks, 320 moved closer and 241 landed exactly on the start,
  and none moved away. Every added pin at a new position (174; the other 76 sit on a position
  another pin already had) carries an NPC ID and sits exactly on a client start point of one of
  its quests. Suramar, Tiragarde Sound, Maldraxxus, Revendreth, Eversong Woods, Bastion, Hallowfall and
  Zuldazar gained the most: story NPCs whose quests start in several places. The map now has 250
  more pins (14,923), each a second pin of an NPC 1.5 to 3 points from its first.

Checks on the 1.5-point result: the data is the candidate byte for byte; `Apply-PinNpcIds.ps1
-WhatIf` matched every row after one correction (the "Your Hatchling" row in the Jade Forest had
said the pin was an object, and now records creature 65669, which TrinityCore says starts its
quests and the fill had set); `Remove-DuplicatePinQuests.ps1` found one new duplicate, "A
Traitor's Death" (50454), which the client starts at two points 0.5 apart in Drustvar and the
split had put on two Marshal Everit Reade pins, and took it off the farther one; the same 14 pairs
are left alone as before. The reachability summary differs by one: 92 pins hidden from every
character by the identity filters instead of 91, as Magister Umbric's "no data" quest 83561 in
Eversong Woods, hidden before as well, now has a pin of its own.
- **Forever**: checked in October 2026 on beta build `1.60.1.70205` (wago.tools product `wow_classic_beta`). Its `QuestPOIBlob` has only 54 rows (23 start points), so this pipeline can't build Forever's pins. The plan for a Forever version, with other sources, is [forever.md](forever.md).
- **Classic Era / Anniversary / MoP Progression**: unlike Blizzard's REST API (which has zero quest data for any Classic flavor), wago.tools archives builds for these too. If their client files contain the same DB2 tables, this could be a real path to Classic support that we previously ruled out. Separate investigation, separate plan.

## October 2026, the client's own quest givers

The client tables review ([client-tables-review.md](client-tables-review.md), 2026-10-07) found
the one client table that names a quest giver: `CollectableSourceQuestSparse`, which, for every
quest whose reward has an appearance the collections can show, holds the giver's creature ID and
each of its spawns (an instance and a world position). On build 12.1.0.69933 that's 2,074 quests,
2,070 of them ours. The new `tools/Apply-ClientQuestGivers.ps1` (step 6c, before the TrinityCore
fill) applies it to the pins, with the pipeline's conversion of a spawn to a map's percentages:

- **1,758 quests have a pin whose NPC ID is the client's giver.** For 262 of those pins no spawn
  stands within 3 points: the giver stands in several places, and the pin is at another of them.
- **94 pins with no NPC ID and no name**, the pipeline's "no recoverable identity" pins, got the
  client's giver and its name from TrinityCore's dump, where a spawn stood within 1.5 points of
  the pin, 0 points for most: Gazlowe, Eitrigg, Colonel Troteman, Dispatch Commander Ruag. Two
  named pins whose names carry a "<Remote>" suffix (Commander Mar'alith, Daria L'Rayne) were left
  for a look by hand, as the database names the giver without it; 37 ID-less pins have no spawn
  within 1.5 points.
- **98 pins added and 10 existing pins of the giver joined** for the 103 quests that had no pin
  and no start point in the client's data: Veren Tallstrider's "Gathering Leather", Caitrin
  Ironkettle's Pilgrim's Bounty quests, Prospector Stonehewer's "Hero of the Stormpike" on both
  Alterac Valley maps. A giver's spawns within 1.5 points share a pin, so 18 quests sit on more
  than one new pin, at each place their giver stands. Two spawns are on instances no map holds.
- **76 pins name another NPC than the client's giver.** They're listed in
  `tools\client-giver-report.txt` with the nearest spawn's distance: 47 within 1.5 points, the same
  spot under another ID of the character (Locus-Keeper Mnemis 167034 for our 167035), 28
  further, 1 on another map. They are reviewed in the section below.
- **The pipeline rerun** the runbook asks for after an ID change merged 27 pins: a newly identified
  NPC's two pins within 1.5 points (Gazlowe's two at one spot in Northern Barrens, Gazrog's 0.03
  apart), and 4 of those merges moved quests by up to 0.9 points (Archmage Khadgar in Draenor's
  Nagrand). Every one of the 24,412 quest placements survived. `Remove-DuplicatePinQuests.ps1`
  found the usual re-split of "A Traitor's Death" (50454) and took it off the farther Marshal
  Everit Reade pin again; 16 pairs are left alone, the 14 before plus two new pins of a giver with
  two IDs (Prospector Stonehewer). `Apply-PinNpcIds.ps1 -WhatIf` matches every row.
- **Result:** 14,994 pins (14,923 before), 11,638 of them with an NPC ID and 2,993 with neither
  ID nor name (3,087 before). The reachability report differs only in the pin count.


## October 2026, the pin review

The 76 pins that name another NPC than the client's giver, the 37 without an ID that the giver
stands too far from to fill, and four odd ones (two "<Remote>" names, two named `CHANGE_TO_NIL`)
were read pin by pin: the evidence for each pin (the client's table, TrinityCore's quest starters
and what stands within 1.5 points of it) was read by one agent, and a second tried to refute every
decision. The two agreed on 174 of 175 decisions, and with the tool's rules on all but a few.
TrinityCore's starters, which the first review hadn't used, added 37 more pins, 56 quests, where
a starter stands within 1.5 points of a pin whose NPC isn't one; the same two passes agreed on 85
of the 90 decisions there.

- **Pins merge quests of NPCs who stand together.** The earlier line that 47 of the 76 were "the
  same spot under another ID" was mostly wrong. Only 17 of the 76 are one character under two
  creature IDs (Matthias Lehner's 32404 and 32408). The rest are neighbours: the pin took the name of one NPC
  standing at the spot, and the quests of the others went under it, like Kelsey Steelspark's pin
  in Tanaris holding Megs Dreadshredder's Horde quests, or Mordant Grimsby's in Dustwallow Marsh
  holding "Swamp Eye" Jarl's. `Apply-ClientQuestGivers.ps1` now gives such a quest to its giver's
  pin at the same spot: 123 quests moved (50 on the client's table, 70 on TrinityCore's word, 3 by
  decision), 7 pins with no NPC took the client's giver, and 10 pins left with no quest went. The
  pins went from 14,994 to 15,054, and the 23,283 quests that have a pin still all have one.
- **The client's quest-giver points are mostly turn-in points.** `ObjectiveIndex = -1` in
  `QuestPOIBlob` was taken to be the quest giver's own pin, and it is where a quest starts and
  ends at one place. Of 2,622 quests whose TrinityCore starters and enders differ, the point
  stands at an ender only for 1,354 and at a starter only for 31 (205 at both, 201 at neither,
  831 with no spawn on that map to compare). Wowhead says the same for the five that were looked
  up: "Rite of Vision" starts at Zarlman Two-Moons and ends at Una Wildmane, where its pin is, 39.7
  points from the start; "Back to Riznek" starts at Khan Blizh and ends at Riznek, where its pin is.
  So a pin for a quest that starts and ends in different places often stands at the turn-in, under
  the name of the NPC who starts it: the 262 pins counted above as far from every spawn of their
  giver are such pins, as are 20 of the 48 cases below. This review listed them and left them
  where the client's data put them, as decided on 6 October ("a pin that matches the client's
  data stays"); the user then chose that pins stand where a quest is picked up, and "October 2026,
  pins at the start" below moves them, by the client's own start points rather than the starters'
  spawns.
- **Two earlier decisions were wrong.** The Exile's Reach pins at 61.88,82.88 and 61.88,82.35 had
  been given Captain Garrick's and Warlord Breka Grimaxe's IDs by name; Wowhead says "Emergency
  First Aid" starts and ends at Lady Jaina Proudmoore, and "Murloc Mania" at Thrall, as
  TrinityCore's starters did. The quests moved to their pins, and the two rows of
  `pin-npc-id-decisions.csv` went with their pins. Two more Alliance quests there, 58915 and 58933,
  sit under Breka Grimaxe's pin at the turn-in, Private Cole's spot, with their starters elsewhere.
- **By hand:** the two pins named `CHANGE_TO_NIL`, a leftover marker of the old addon's author,
  lost their name; quest 24799 left a Thousand Needles pin it had no business on, as it has its
  own pin in Icecrown.
- **What stayed** (before the pins moved to the start; 39 of these rows left the file then, as their
  pins moved, and 6 were added): 48 cases in `docs/plans/pin-giver-decisions.csv`, each with its
  reason: 20 where
  the pin stands at the turn-in (TrinityCore's ender or Wowhead says so), 13 pins with no NPC whose
  giver stands more than 3 points away, 6 whose giver has no spawn on the map (an image, a summon
  or an item), 5 pins whose NPC stays as the giver stands farther than 1.5 points, 3 "<Remote>"
  names, which are deliberate, and a pin that lost its junk name. TrinityCore also lists another
  starter than the pin's NPC for 163 quests the client doesn't have, with none within 1.5
  points: left alone.

## October 2026, the start points

The pin review above found that `ObjectiveIndex -1` is mostly a quest's turn-in. The retail run of
the Forever probe's map pass (7 October 2026; [game-api-review.md](game-api-review.md),
"Map-offers probe: retail run") found where the start is: `ObjectiveIndex 32`, in the same table.

- **Evidence:** all 439 offers the game listed lie within 10 yards of the same quest's point 32.
  Of 1,421 quests whose starter and ender differ in TrinityCore's dump and have spawns on the
  point's map, point -1 is nearer the ender in 1,275 and nearer the starter in 13; point 32 is
  nearer the starter for 1,369 of 1,513 blobs and nearer the ender for 24. Wowhead agrees on "O Lonely Star", "The Conquered
  Heroes" and "Be Grudge You".
- **What it means for the pins:** of 5,202 pairs of a quest and a map whose two points are more
  than 1.5 map points apart and that have a pin on the map, 4,886 to 5,081 have the pin only at
  the turn-in. The pins of 20 September were nearer the start (159 of 172 quests within 1.5 points
  of the offer, against 107 today): the rebuilds moved 55 of them to the turn-in.
- **Quests with a start point and no turn-in point** (4,278 without a pin: 4,082 task quests and
  196 others, 192 with a map position) got no pin, as the filter dropped them (given one in the last section). The 19 quests the
  game offers or forces visible that have no pin are of this kind.
- **A way to move the turn-in pins that needs no spawn data:** the start point is in the table the
  pipeline already reads, for every quest that has one.
- **Other readers of -1:** `Get-WagoQuestRequirements.ps1`; `Find-UnavailableQuestCandidates.ps1`,
  whose "GiverPOI" is the quest's own point (a turn-in when it ends elsewhere), so whether a start
  point should count as evidence that a quest is still obtainable is to check; and, for Forever,
  `Import-ForeverData.ps1`, which now reads point 32 as well.
- **Done in the next section.** The decision was number 8 under "Decisions to take" in
  game-api-review.md; the user chose to move the pins by the client's start points in one step,
  rather than the 50-quest shortlist first.

## October 2026, pins at the start

On 8 October 2026 the pipeline began to place each quest where it starts. The user's rule is that a
pin stands where a quest is picked up, never at the hand-in; it overrides the 6 October decision that
a pin matching the client's data stays (which rested on point -1 being the start), and the
4 October decision about the pins in the water at Stormwind Harbor, which were turn-in points.

- **The rule** (`Build-QuestLocationData.ps1`). A quest is placed at its points 32 when the client
  has any (15,866 quests with a point -1), and at its point -1 otherwise (433). A point 32 on a parent
  map of another point 32 of the quest, a continent over a zone, is left out (409 blobs): the
  client lists both. Flag bit 2 doesn't mark them; 4,571 zone-map starts carry it. A quest with a
  point 32 and no point -1 was placed only if it had a pin already (534 quests; 162 of them moved);
  the 192 without one got pins in the last section. The rule lives in the pipeline because the
  pipeline recomputes every position from the client's data on each run: a move made afterwards
  would be put back at the next rebuild. The turn-in pin goes; a pin means a quest can be picked up
  there, and a second pin at the hand-in would list it as available under the same name.
- **Spawn data is the cross-check, not the source.** The client has a start for nearly every quest;
  the client's giver table covers 2,074 quests and TrinityCore's spawns stop at Mists of Pandaria.
  Of the 3,550 pairs of a quest and a pin where the client's table or TrinityCore names a starter
  and an ender that differ, with spawns on the pin's map, the pin stands at a starter's spawn in
  1,693 (503 before) and at an ender's in 26 (1,230 before). 19 of the 26 are pins at the client's
  own start point, which stands at the ender; 7 are quests with no start point, which sit at the turn-in: 31145 "The Rear is Clear",
  26538 "Emergency Aid", 28405 "Weapons of Darkness", 75190 "Ready and Abel", 9897 "I'm Saved!",
  14405 "Escape By Sea" and 29652 "One Last Favor".
- **What moved.** Pins went from 15,054 to 13,688, mostly as pins at hand-ins joined the pins of
  their starters. The 23,283 quests with a pin all still have one, and no quest gained a first pin.
  7,637 quests have other pins than before: 2,165 on another map (a quest that starts in a different
  zone than it ends in now shows on the zone where it starts), 2,450 moved by more than 10 map
  points, 2,012 by 3 to 10, 702 by 1.5 to 3, 2 by less, 306 regrouped at the same places, and 15,646
  unchanged. "Rite of Vision" is at Zarlman Two-Moons and "Back to Riznek" at Khan Blizh
  (Wowhead's starts); "O Lonely Star" is at 39.99, 84.26 in Slayer's Rise; "A Royal Summons" is in
  Dalaran, no longer at the harbor.
- **Against the game's own offers** (the retail map pass, 439 offer rows of 246 quests): a pin within
  1.5 points of the offer for 242, against 159; more than 5 points away for 1, against 56. The
  pins' NPCs stand within 1.5 points of them for 3,800 pins, against 3,370, and more than 10 points
  away for 466, against 1,158.
- **Step 6c on the moved pins** gave 18 pins with no ID the client's giver, moved 95 quests to the giver
  who stands at the spot (92 pins left empty went), and left 16 cases for review, none new after the
  decisions below. The pins "far from every spawn of their giver" fell from 275 to 38. One MOVE row
  was added (11652 to Annihilator Grek'lor, whose pin had taken Gorge the Corpsegrinder's name),
  and the rows that no longer described a pin left the file: `pin-giver-decisions.csv` has 19
  rows (from 52), `pin-npc-id-decisions.csv` 197 (from 219), its rows moved to the pins that took
  their quests (78 rows, 8 copied where a pin split, 28 dropped where two pins merged into one that
  already had the row).
- **A fix to the grouping.** The stable-position step snaps a group to an existing pin's coordinates
  within 1.5 points, and two groups of one NPC could snap onto the same ones (2 pairs on master; the move
  produced 11 more). `Assemble-PinDB.ps1` now makes them one pin, so no two pins of an NPC are
  closer than 1.5 points; the 1.5-point grouping rule and the spacing floor are otherwise as
  before.
- **Checks.** The pipeline, 6c, `Apply-PinNpcIds.ps1`, `Fill-PinNpcIds.ps1` and
  `Remove-DuplicatePinQuests.ps1` (4 quests off 3 pins, 1 pin gone) were rerun until a second run
  changed nothing. The reachability report differs from master's only in the pin count and in 100
  pins hidden by the identity filters, all by "no data", against 93: those quests share pins
  differently now. Not tried in game.
- **Forever.** `Import-ForeverData.ps1` takes point 32 first as well. Its data is unchanged until
  the next import, which would move 5 of the 11 quests pinned from the client's start points
  (92748, 92750, 92751, 92752 and 92753), some to another map.

## October 2026, pins for quests with only a start point

The 8 October change left the quests with a point 32, no point -1 on a map and no pin without a pin
(decision 8's first step). `Build-QuestLocationData.ps1` now places such a quest at its start when
it is one of our quests and not in the client's task table (`QuestV2CliTask`: world quests and bonus
objectives, which the addon doesn't pin, but also some dailies, holiday and ordinary quests); one
that already had a pin was placed before. The tool stops if `QuestV2CliTask.csv` (step 1b) is
missing, as without it every task quest would get a pin.

- **193 quests got their first pin,** in 201 places: the 192 counted before, and 81969 "An End to the
  End", whose point -1 is off its map. 124 places joined pins that already held other quests, by the
  pipeline's rule that a start within 1.5 points of a known NPC's pin takes that NPC; 77 are on
  new pins. 136 places carry a giver's name and 65 have none. Pins went from 13,688 to 13,772
  and quests with a pin from 23,283 to 23,476. Every one of the 13,688 old pins is still there,
  13,625 identical and 63 with new quests added: nothing moved, nothing went, no icon changed.
  Five non-task quests still have no pin, as their start is on no map: 66038, 27858 and 27898
  "Rheastrasza's Gift", 40040 "Felwort Sample" and 46812 "Draconic Secrets".
- **The names were checked.** A quest that joins a known NPC's pin takes that NPC's name, which is
  wrong when the NPC only stands nearby. Eleven were moved to their real giver by `MOVE` rows in
  `pin-giver-decisions.csv`: 54147 to Princess Talanji (it was under Genn Greymane, an Alliance
  NPC, for a Horde quest), 28446 and 28447 to Ariok, 33826 and 33828 to the Frostwolf Champions,
  27894 to Rhea, 30657 to General Nazgrim, 36512 to Soulbinder Tuulani, and 43261, 43262 and 40704
  to Vanessa VanCleef, Garona Halforcen and Li Li Stormstout (the client's start for the four
  champion quests there is a placeholder point). Eight unnamed pins got their giver by `FILL`
  rows, each read on Wowhead: Warmaster Zog (36261), the Demon Hunter (37450), Lady Jaina Proudmoore
  (56775), Private Cole (58208 and 58209), Thrall (59926) and Grunt Throg (59927 and 59928). The
  Exile's Reach pins stand on a sea map and their NPCs only on the ship's instance maps, so
  the spawn data could not place them. Four more are `KEEP` rows: "The Warden's Game" and "The
  Sentinel's Game" and their Horde versions start at a Stone or Marble Slab, an object, whatever
  TrinityCore's creature starters say.
- **Left as they are:** six Horde and five Alliance Chromie Time quests (the "Onward to Adventure"
  campaign quests), which are auto-accepted and carry the name of the nearest NPC, as 60887 and
  60891 already did; 41852 and 41853, listed under Brewer Almai though the class hall's
  Brewmaster ends them; 41627 and 26149, beside pins of their same-name twins that carry an
  object's name and no ID; and 44543, under the Kor'kron Loyalist who stands 0.03 points from it.
  The recorder (`game-parity.md`, recommendation 1) would give these their real giver.
- **Icons.** `Assemble-PinDB.ps1` gave a group the icon of its first row, and a new quest's default
  icon came first: Rukua's pin in Darkshore lost its class icon (9 to 1) and three profession pins
  went from 1 to 3. A quest new to a pin no longer replaces its icon (`IconFromPin`, in "pins from
  TrinityCore" below).
- **Of the 19 quests the retail map pass found with no pin,** 9 of the 11 the game offers now have
  one (the Legion profession "Sample" quests, "The Battle for Broken Shore" and "Warming Up"), and
  so do the twins 43806 and 59926. Still without: 40040, whose start is on no map, and 82449 "The
  Call of the Worldsoul", a task-table quest that needs a hand entry; the seven forced world
  quests and 84423 have no start for the addon to show. Against the game's 439 offers the pins are
  within 1.5 points of 253 (242 before), and 6 rows (2 quests) have no pin at all (34 before).
- **Checks.** The pipeline, step 6c, `Apply-PinNpcIds.ps1`, `Fill-PinNpcIds.ps1` and
  `Remove-DuplicatePinQuests.ps1` were rerun until a second run changed nothing, which took two
  rounds. The reachability report differs from master's in the pin count alone, and
  `Build-AddonData.ps1 -Check` passes for both games. Three independent readers checked the
  positions of all 193 quests against the client's tables (every pin within 1.36 points of the
  start, none beyond 1.5), the names, and the script and these docs. Not tried in game.
- **Open:** 4,082 task quests already in the data have a start and no pin, 1,387 of them world
  quests; whether to pin any of them is not decided. Decision 9 in game-api-review.md is about
  adding task quests to the database, with no pins.

## October 2026, pins from TrinityCore

The user's rule (8 October 2026): a normal quest gets a pin whenever there is data for where it is
picked up, with or without an NPC, and never a world quest; the same for every game that has the
data. The client's export of `QuestPOIBlob` lists no point at all for thousands of our quests, but
TrinityCore's `quest_poi` and `quest_poi_points` do: they are the points the server sends the
client, with the same `ObjectiveIndex 32` for where a quest starts (and -1, mostly the turn-in,
which is not used). Where both list a quest, 19,801 of 19,806 single-place quests agree within 1.5
map points. `Build-QuestLocationData.ps1` now places the quests the client doesn't list, as rows with
`Source=trinitycore`, and `Assemble-PinDB.ps1` pins them.

- **Which quests.** One of ours with no pin that is none of these: a task quest
  (`QuestV2CliTask`); flagged unavailable; a type other than 0, 1, 2, 4 or 128; tagged a holiday or
  profession quest; in a system category (Scenario, Delves, Prey, Warbands, Warfront Contribution,
  Path of Ascension, Covenant Assaults, Torghast, Time Rift, Weekly Events, World PvP and the
  others in the script), a holiday's category, or Landfall, whose dailies look retired; named like
  an internal quest; absent from the client's `QuestV2`; disabled in TrinityCore; without a
  `quest_template` row; flagged tracking (0x400) or unavailable (0x4000), or auto-accept together
  with auto-complete (a scripted helper), or auto-accept with no starter (a trigger, not a giver);
  type 128 with no weekly or daily flag; or of a system kind (World Quest, Emissary, Delve, Envoy,
  Meta Quest, Professions and the like). The script prints a count per reason.
- **Where.** Every start place, after dropping a start on the parent map of another start at the
  same world point and merging places within 1.5 map points: up to six places (class and race
  quests start in several cities). More, none, a start with no point, on a map without a region or on
  a disabled map go to `tools\quest_locations_tdb_review.csv`, and so do the quests at a
  placeholder point: where five or more of our quests of three or more categories start at one
  world point (Mechagon's board also holds quests of Maldraxxus and Zereth Mortis, the Nerub-ar
  Palace point those of three expansions), only the quests of its commonest category stay, and none
  when that is under half of them.
- **Names.** A pin takes a creature starter's name when that starter's TrinityCore spawn stands
  within 1.5 map points of the start on the same map. Otherwise the quest joins a neighbouring
  pin's identity only if that NPC, or one of the same name, starts it, else it gets a nameless pin
  of its own: the NPC next to a start is often not its giver. A quest new to the pins never changes
  the icon of the pin it joins (`IconFromPin`, replacing #223's copy of the icon).
- **Result** (build 12.1.0.69933, TrinityCore 1210.26091). 1,453 quests got their first pin in 1,778
  places: 207 on pins that already held other quests, 1,571 on 1,430 new pins. 508 places carry a
  giver's name (402 from a starter's spawn at the start, 99 by joining a starter's pin, 7 by hand)
  and 1,270 have none. Pins went from 13,772 to 15,202 and quests with a pin from 23,476 to 24,929. Every one
  of the 13,772 earlier pins is still there, 13,646 identical and 126 with new quests added.
  Pins with an NPC ID went from 10,404 to 10,564 and pins with neither ID nor name from 3,031 to 4,301.
- **Left for a person** (`tools\quest_locations_tdb_review.csv`, 157 quests): 130 at placeholder
  points, 17 starting outside every region of their map, 5 with more than six places, 3 with a start but
  no point, 3 on a map without a region and 2 on a disabled map. The script also prints, per reason, the
  quests TrinityCore has a start for that were not placed; among them are 2,766 that are not in our
  quest data, a list to look through for the step that adds quests the database lacks.
- **Names by hand.** Seven nameless pins got the starter the client's giver table puts at the
  start (Master Hight, Wavespeaker Tulra) by `FILL` rows. About twenty pet-battle tutorial
  quests stand nameless on their trainers' pins, and want one Wowhead check per city before
  `FILL` rows. Three quests of holidays have no holiday tag in our data (47430, 79178, 79694) and
  were pinned; they want the tag.
- **A rerun.** Once a quest has a pin, the next run leaves it out of `quest_locations.csv` ("already
  has a pin"), and its pin stays through the preserved-pairs net, so the CSV is shorter by these
  quests and Join's "No existing pin at all" count is the number of new quests to review. A new
  rule therefore takes no pin away: flag a retired quest in `unavailable-quest-decisions.csv`, or
  take the quest off its pin in `data\pins.jsonl` and rerun.
- **Checks.** Three independent readers recomputed all the positions from TrinityCore's points
  (own pins within 0.007 map points, joined pins within 1.49), checked the names and the
  population, and the script and these docs; what they found is fixed above. The pipeline, step
  6c, `Apply-PinNpcIds.ps1`, `Fill-PinNpcIds.ps1` and `Remove-DuplicatePinQuests.ps1` were rerun
  until a second run changed nothing (two rounds). The reachability report differs from master's in
  the pin count and one pin hidden by "no data" less. Not tried in game.
- **Open.** About 10% of the pins that have a creature starter spawn are far from it (30 of 278);
  TrinityCore's starter list is stale in places such as Orgrimmar's class hubs, and the quest points
  agree with the client where the client lists them. 1036 "Avast Ye, Scallywag" is pinned where the
  client puts its end, not at "Pretty Boy" Duncan: it wants a look in game. Item-started quests
  with a start point, and auto-accepts that have a starter, are pinned at that point, as before.
- **Stacks on the map.** `qcMergeStackedPins` draws one pin for the pins within 0.5 map points of
  the first, and that pin was the first one's: a click set a TomTom waypoint titled with its NPC, or
  with its first quest when it had no name. Where a nameless pin came first and a named pin joined
  it, the click gave a quest's name. Over the whole data with every map filter off, that is 267 of
  retail's 3,060 stacks (141 of 1,972 with the default filters, for a maximum-level Alliance night
  elf druid with nothing done); Forever has none among its 206. The 53 the pass above counted are
  the 267's stacks whose first pin that pass added (47 with a named pin from before it).
  The pin now takes its icon, NPC and name from the group's first named pin, else from its first
  pin. Who joins a group is still measured from its first pin, and the pin stays at the first pin's
  point, so none moved and every member is within 0.5 points of it, which the named pin's point
  could not promise (it lies up to 0.496 from the first pin in 129 of the 267, and at the same
  point in 138). `Test-MapTooltip.lua` checks it, on made-up stacks and on every stack in the data.
  The tooltip needed no change: it lists the members by name, so the first named one already
  headed it, and its lines are the same for every stack in the data.

## October 2026, pins from the addon's recorder

`Import-RecordedGivers.ps1` (sweep step 6d, after 6c; the rules and the reasons are in
[quest-giver-recorder.md](quest-giver-recorder.md), "The merge tool") is a third kind of source for
pins beside the client's points and TrinityCore's: what players, and the maintainer, saw in the game.
It works on `data\pins.jsonl` after the pipeline, as the 6c tools do, and writes through `Save-PinData`;
the pipeline keeps what it writes (a scratch run of `Parse-ExistingPinDB.ps1` and `Assemble-PinDB.ps1`
over its output reproduced it line for line, new pins and fills included, because a pin with an NPC ID is
covered by its quest and NPC pair and sits where the pipeline sorts it).

- **A fill never decides by distance.** The recorded giver must have offered one of the pin's quests;
  where two pins sit within 1.5 points, only the offer tells which is whose.
- **A fill that would make two pins of one NPC 1.5 points or less apart, but not on one spot, is not made,**
  because the next rebuild merges them and the lower quest's place wins, which can move the other pin's
  quests by up to 1.5 points. It is listed.
- **A quest that has any pin, anywhere, gets no second one** from this tool; a giver that offers it somewhere
  else is listed (`quest offered away from its pins`).
- **The holds the TrinityCore pass puts on a quest are waived when a creature offers it** (not in
  `QuestV2`, the template inferences, a task of another kind than world, bonus or hidden, Landfall,
  holiday, profession, a quest type other than 0, 1, 2, 4 and 128); the ones that are definitions stay (unavailable, internal name, world, bonus or
  hidden task, system category), and the new pins are counted by class so the user sees what the waiver let in.
