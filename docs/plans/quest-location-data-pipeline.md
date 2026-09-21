# Plan: Rebuilding Quest Location Data from wago.tools

## Context

This addon's map-pin feature (`qcPinDB.lua`) hasn't been meaningfully refreshed in years, and we'd deferred a decision on whether to keep investing in it at all, since the base WoW client now shows its own quest markers. That changed when we found a legitimate, verified way to source fresh quest-giver location data directly from Blizzard's client files via wago.tools — something neither Blizzard's own Data API nor Wowhead (whose ToS explicitly forbids scraping) can offer. This plan scopes the work to actually use that.

**Scope for this plan: Retail only.** Classic Era/Anniversary/MoP Progression and Forever are explicitly out of scope for now, per the earlier "Retail first" decision — see "Possible future extensions" at the end for why they might still be reachable later.

## What we've already proven (this session)

- **Data source**: wago.tools exposes raw Blizzard client DB2 tables via an open, undocumented-ToS-restriction, no-auth API. This is raw client data, not a third party's curated/copyrighted content — same legal footing as typing quest names in by hand, which this addon already does.
- **The tables that matter**:
  - `QuestPOIBlob` (72,698 rows): links `QuestID` → `UiMapID` + one or more point-blobs. `ObjectiveIndex = -1` marks the quest-giver's own pin (a single point); `ObjectiveIndex >= 0` marks a multi-point objective-area outline (meaning of the paired `ObjectiveID` is still unresolved — see Open Questions).
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
  | `[1]` | Map level/floor (`0` = normal outdoor) — compared against `mapLevel` in `qcRefreshPins` |
  | `[2]` | Icon type, `1`–`11` (normal/repeatable/profession/daily/seasonal/special/weekly/monthly/class/kill/legendary) — passed straight to `qcShowPin` |
  | `[3]` | Quest-giver creature (NPC) ID |
  | `[4]` | NPC name (string, or `nil` for special-case pins) |
  | `[5]`, `[6]` | X/Y position, **0–100 scale** (matches in-game hover readout directly — multiply our `[0,1]` formula output by 100) |
  | `[7]` | List of quest IDs offered/completed at this pin |
  | `[8]` (optional) | Free-text note, seen on special-case pins (e.g. "Provided when you assist an Injured Razer Hill Grunt") |

  `qcPinDB[UiMapID]` keys are confirmed intended as live `UiMapID` (via `qcRefreshPins(UiMapID, mapLevel)`). We also directly caught a real drift bug this pipeline will fix: `qcPinDB[1]` is commented `Durotar`, but current `UiMapID 1` is actually **Kalimdor** (the whole continent) — concrete proof the existing pin data has drifted from the modern ID space.

- **Multi-row `UiMapAssignment` entries, checked across the full table (1,956 distinct `UiMapID`s):** the vast majority (e.g. Stormwind City, `UiMapID 137`, 22 rows) share one identical bounding box across all rows — those extra rows just tag different building/WMO sub-areas, not different geography, so picking any row is safe. But **150 UiMapIDs (~7.7%) have genuinely different bounding boxes across rows.** Phase 1's script needs to handle this: for those maps, try each candidate region and keep whichever produces a normalized result inside `[0, 1]`, rather than assuming one row per map.

## Open questions (still unresolved, may need work during Phase 1)

1. **`ObjectiveID`/`ObjectiveIndex` meaning beyond "-1 = giver pin."** Didn't resolve what table (if any) `ObjectiveID` cross-references. Not blocking for giver pins, but blocks pulling in richer "objective area" pins as a bonus.
2. **No published rate limit for wago.tools.** Should self-impose a conservative delay between requests when pulling ~250K+ rows across tables, out of politeness, even though nothing prohibits it outright.
3. **Some old quests only have continent-level POI data, not zone-level.** Checked across all 109 known Durotar quests: 56 resolve to `UiMapID 463` (the real zone map), but 42 resolve to `UiMapID 1` (the Kalimdor continent) — a real pattern, not a fluke. This looks like a genuine gap in Blizzard's own source data for older vanilla content that never got a fine-grained pin when the modern per-zone map system rolled out. Not fixable by us; the pin will only show at the continent zoom level for these quests. Not blocking — a continent-level pin is still better than none — but worth knowing before treating every conversion as equally precise.

## Phase 1 status: MVP built and working

A working pipeline exists (`tools/Build-QuestLocationData.ps1` → `tools/Join-LocationsWithExisting.ps1` → `tools/Derive-IconTypeMapping.ps1` → `tools/Assemble-PinDB.ps1`), producing `tools/qcPinDB_candidate.lua` (syntax-checked, valid Lua). Numbers from the current run:

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

## Possible future extensions (explicitly not this plan)

- **Forever**: wago.tools tracks a `wow_classic_beta` build (`1.60.1.69913`) that matches Forever's own `/dump GetBuildInfo()` output exactly. If that build's client files include the same `QuestPOIBlob`/`QuestPOIPoint` tables, the same pipeline might work for Forever specifically — worth a quick check later, not part of this plan.
- **Classic Era / Anniversary / MoP Progression**: unlike Blizzard's REST API (which has zero quest data for any Classic flavor), wago.tools archives builds for these too. If their client files contain the same DB2 tables, this could be a real path to Classic support that we previously ruled out. Separate investigation, separate plan.
