# Data cleanup: dead pins, missing quests, unavailable quests, catch-all categories

## Goal

Item 5 of the improvement list: the data work parked in September. Three parts:
- the pins whose quests aren't in our database;
- flagging quests players can no longer get (the existing plan, `unavailable-quests.md`);
- the three catch-all categories.

## Where things stand (measured 2026-09-30, master f9c2620, client build 12.1.0.69933)

Retail is still on build 12.1.0.69933, the build our client tables come from.

### Pins with quests missing from `qcQuestDatabase`: 220 pins

| Group | Pins | What to do |
|---|---|---|
| Every quest is gone from the client's `QuestV2` | 39 | Delete the pin |
| No quest in our database, but the client has at least one | 110 (227 quest IDs) | Backfill the quests from Blizzard's API |
| Good pins that also carry quest IDs the client lacks | 7 | Remove those IDs (45 dead IDs in all, counting the 39 pins) |
| On maps 2647/2669, which aren't in the client's `UiMap` | 8 | Leave parked: there's no newer build to check them against |

These are hidden today by the default "hide quests with no data" filter; with it off, they show
"Quest Missing in DB".

### Unavailable quests (`Find-UnavailableQuestCandidates.ps1`, rerun today)

Blizzard's API returns 404 for 924 non-task quests. The numbers match the 2026-09-22 plan:

| Group | Quests |
|---|---|
| Not in the client's `QuestV2`, no sign of life | **183** (top: Torghast 33, Legion Uncategorized 19, Eastern Kingdoms 17, Vision of Orgrimmar 10) |
| Not in the client, some sign of life | 8 |
| In the client, no sign of life | **376** |
| In the client, some sign of life | 357 |

"Sign of life" means a quest-giver or other map point in the client, a pin, a client quest line, an
achievement criterion, or being another quest's prerequisite.

**New evidence tested and rejected:** the quest-type probe (#42) had the server load every quest,
and 3,598 failed. Against the quests Wowhead has classified, a failed load means nothing: live
74431 (Zskera Vaults) failed, while obsolete 8346 and 54079 loaded. So the old plan's rule stands.
Only quests missing from the client are flagged automatically; the rest need a person to judge.

### Catch-all categories

| Category | Quests | Known to the API | Unavailable candidates (no sign of life) | Task | Have a client map point |
|---|---|---|---|---|---|
| 1150 "Bfa Unknown" | 867 | 634 | 97 | 127 | 148 |
| 1050 "Legion Uncategorized" | 153 | 125 | 28 | 0 | 50 |
| 0 "Uncategorized" | 115 | 111 | 4 | 0 | 15 |

"Bfa Unknown" isn't BfA-only: it holds live quests from several expansions, e.g. The War Within's
"Lorewalking" quests. `Place-UncategorisedQuests.ps1` places quests by Blizzard's quest area, our
pin maps, a name prefix, our zone text and storylines. It doesn't use the **client's own map points**
(quest-giver, objective and turn-in points in `QuestPOIBlob`), which 213 of these quests have.

## Phases (one PR each, in this order)

### 1. Remove dead pins and dead pin quest IDs (data only)

**Done in #105, and much smaller than planned.** The "39 pins" above came from checking retail's
`QuestV2` alone. Checked as #94 did, against our database, retail's `QuestV2`, and the **12.1.5
PTR's** `QuestV2` and quest location data (build 12.1.5.70077):
- **18** of the 38 unknown pin quest IDs are 12.1.5 quests that aren't live yet (e.g. 95211,
  96707, 98836). Their pins stay.
- **15** more appear in retail's or the PTR's quest location data, so they aren't clearly dead.
- **Only 5 exist nowhere.** 157754 on Marshal Gabriel's Conquest's Reward pin was a typo for 57754;
  a nameless pin at the same spot carried 57754 alone and was removed. 4274, 48268, 1234 and 5312
  were removed from otherwise good pins.

The reachability report changed in exactly two lines (the pin count, and Odyn's pin's quest list).
**Lesson:** "missing from retail's quest table" doesn't mean dead; check the PTR build too.

### 2. Backfill the 227 quests behind 110 pins (data only, uses Blizzard's API)

- The existing path: `Fetch-GapQuestData.ps1` → `Insert-GapQuestEntries.ps1 -AddonDir` (which
  places what it can, see the full sweep runbook).
- **If the API 404s on a quest:** it's probably hidden or obsolete. List those pins for a decision
  rather than deleting them silently.
- **Expect 404s for the 12.1.5 quests** found in phase 1: Blizzard's API only serves live quests.
  Leave those pins for a pass after 12.1.5 goes live.
- **Check:**
  - the new rows are field-by-field sane (the accuracy audit rules);
  - the reachability report shows those pins drawable;
  - no existing row changes.

### 3. A placement rule from the client's map points (tool change, then data)

- Add a rule to `Place-UncategorisedQuests.ps1` after "pin's map". It uses the maps of a quest's
  client map points (`QuestPOIBlob` → `UiMapAssignment` → `qcAreaIDToCategoryID`, as the pin
  pipeline converts them), placing the quest only when they all point to one category.
- **Validate it the way the other rules were:** un-file 2,000 random filed quests on a scratch copy
  and count how many the new rule puts back where they were. If it's wrong too often, drop it.
- Then run `-Refile 1150,1050` and the category 0 pass (`-WhatIf` first), and review what moves.
- **Check:** as above, plus `Remove-EmptyMenuEntries.ps1 -WhatIf`.

### 4. Unavailable quests: mechanism, then the 183 (addon code, then data)

This is phases 0 and 1 of `unavailable-quests.md`, updated for the code as it is now (see that file).
- Add `qcUnavailableQuests.lua` and the "Show unavailable quests" option (off by default). A
  flagged quest is hidden from the list, the completion counter's total and the map, **unless**
  the character has completed it or has it in their quest log.
- Add the `qcFlaggedButSeen` log, which records any flagged quest a player turns out to have.
- Then flag the 183, after a look by zone.

### 5. Review the 376 in-client, no-sign-of-life quests with the user (ongoing)

Review in groups by zone: Warfronts, Rated PvP season rewards and so on. The evidence comes from
the user's knowledge, or Wowhead viewed by hand (it blocks automated browsing). Anything uncertain
stays unflagged.

## Decisions (agreed 2026-09-30)

1. **What to call "Bfa Unknown".** It's shown in the menu under that name, but it holds quests
   from several expansions.
   **Recommendation:** once phase 3 has moved what it can, merge what's left into 0
   "Uncategorized" (`Place-UncategorisedQuests.ps1` already sends unplaceable quests there), so
   the menu has one honest catch-all instead of a misleading one. "Legion Uncategorized" is
   accurate (Legion quests), so it stays.
2. **Order.** **Recommendation:** as above. The pins first (small, data-only, checkable), then
   placement, then the unavailable-quest feature, which is the only part that changes addon
   behaviour.

## Status

- 2026-09-30: measured and planned, decisions agreed. Phase 1 in #105 (corrected above: 5 dead IDs, no dead pins). Next: phase 2.
