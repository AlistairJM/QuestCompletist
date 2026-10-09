# Plan: Flagging Unavailable Quests (obsolete and hidden tracking quests)

> Since October 2026 the quests live in `data/quests.jsonl` and are built into `qcQuestData.lua` with a different row layout (see [data-structure.md](data-structure.md)). File names, field numbers and code references below describe the addon as it was when this plan was written. Since 111.5 the map and the list each have their own "no longer available" setting (see [settings-grid.md](settings-grid.md)).

## Goal

Stop showing players quests they can no longer obtain, such as obsolete quests Blizzard retired
and hidden tracking quests that were never real player quests. Keep them in the database and keep
the decision reversible.

## Decisions already made (2026-09-22)

- **Flag, don't delete.** A wrong deletion is costly and easy to miss, and the location pipeline
  (`Insert-GapQuestEntries.ps1`) can quietly re-add deleted quests from wago.tools data. A wrong
  flag is a one-line fix.
- **Flags live in a separate file,** `QuestCompletist/qcUnavailableQuests.lua`, not in
  `qcQuest.lua`. This keeps the 35k-line database untouched and makes the flag list easy to
  review and regenerate.
- **Quest titles are not evidence.** Blizzard marks retired quests inconsistently (e.g.
  "[DEPRECATED]" prefixes), so no rule may depend on the title.

## What the evidence says

Source: `tools/Find-UnavailableQuestCandidates.ps1`, which writes
`tools/quest_availability_signals.csv`: one row per quest, with independent signals from the
game client's own tables (wago.tools), our pin database, and Blizzard's API cache.

**Candidates:** the 924 non-task quests Blizzard's API returns 404 for. Task quests (world
quests and bonus objectives) are excluded: the API never serves them, and the Phase 3 spot-check
found them live.

| Bucket | Quests | No positive signal | What they are |
|---|---|---|---|
| **Not in the client's `QuestV2` table** | 191 | 183 | Hidden tracking quests and removed content, e.g. 42467 "Legion 110 A". Top zones: Torghast 33, "Legion Uncategorized" 19, Vision of Orgrimmar 10 |
| **Still in the client** | 733 | 375 | Mixed: Wowhead showed 3 of 5 sampled as obsolete and 2 as live. Top no-signal zones: Warfronts 126, Eastern Kingdoms 36, Zuldazar 11, K'aresh 11 |

"Positive signal" means any of: a quest-giver or other map point in the client, a pin in our
`qcPinDB`, membership of a client quest line, an achievement criterion requiring it, or being
another quest's prerequisite in our DB.

**The signals can't separate obsolete from live on their own.** Against the 8 quests Wowhead
classified during the Phase 3 spot-check:

| Quest | Wowhead | Client | Giver point | Pin | Quest line | Achievement |
|---|---|---|---|---|---|---|
| 8346 Thirst Unending | obsolete | yes | – | yes | – | – |
| 24760 The Arts of a Shaman | obsolete | yes | – | – | – | – |
| 54079 Conquest's Reward | obsolete | yes | – | yes | – | – |
| 74431 Zskera Vaults | **live** | yes | – | – | – | – |
| 91023 Endeavor Reward | **live** | yes | – | – | – | – |
| 42467 Legion 110 A | no giver (tracking?) | – | – | – | – | – |
| 48237 Defeat Nekthara | no giver (tracking?) | – | – | – | – | – |
| 55125 Hunting Season | no giver (tracking?) | – | – | – | – | – |

Live quests 74431 and 91023 look exactly like obsolete 24760. For comparison, among quests the
API does know, 55% have a quest-giver map point, 57% a quest line and 77% a pin. So "no signal"
raises suspicion but proves nothing. Two consequences:

1. **Automatic flagging only where the evidence is structural:** quests absent from the client's
   own quest table (the 183 with no signal at all).
2. **Everything else goes through human review, in groups,** and the addon has safety nets so a
   wrong flag can never hide a quest the player is actually doing.

**Correction (2026-10-05): absence from `QuestV2` isn't structural evidence on its own.**
- The table never lists repeatable quests. None of the 500 the API flags repeatable are in it,
  against about 98% of one-time, daily and weekly quests.
- The sure sign is missing from it **and** unknown to the server. The `/qc typecheck` probe asked the
  server for every quest, and couldn't load 34 of the 191 missing from `QuestV2`.
- The other 157 include live repeatable rewards: paragon caches, renown rewards, Torghast's rescues
  and Horrific Visions.
- Phase 1's flags were corrected in #154 (below), and `Find-UnavailableQuestCandidates.ps1` now
  reports what the server knows.

## Addon design

### Data file
```lua
-- qcUnavailableQuests.lua
qcUnavailableQuests = {
	[42467]=2,	-- 2 = hidden tracking / not in the game client
	[8346]=1,	-- 1 = obsolete (reviewed)
}
```
Load it in `QuestCompletist.toc` before `qcCore.lua`. The reason codes allow different wording
later, and let the options panel say *why* a quest is hidden.

### Behaviour
A flagged quest is hidden **unless** any of these is true:
- the character has completed it (`C_QuestLog.IsQuestFlaggedCompleted`), so past completions stay
  visible and keep counting;
- it's in the character's quest log (`C_QuestLog.GetLogIndexForQuestID`), because if the player
  has it, it's obtainable by definition;
- the new option **"Show unavailable quests"** is on (default off). As built (2026-09-30), it's a
  "hide" checkbox like the other 18 filters, "Hide quests that are no longer available", on by
  default, setting `QC_ML_HIDE_UNAVAILABLE`, so the reachability check's "every filter off" pass
  covers it.

Where to apply it (all in `qcCore.lua`; updated 2026-09-30 for the code after #95–#103):
- **Quest list and completion counter:** both use `qcBuildQuestFilter(QC_LIST_FILTER)`. The
  counter's total should exclude flagged quests the character hasn't completed, so unobtainable
  quests don't drag completion percentages down. The completed/in-log exceptions need the
  character's state, which that filter deliberately doesn't read, so the check sits next to the
  "hide completed" and warband checks in `qcGetCategoryQuests` and `qcGetZoneCompletionStats`.
- **Map pins:** one more check in `qcBuildMapQuestFilter`, with the same exceptions.
- **Search:** unchanged. A search finds flagged quests, so they can still be looked up.
- **Options panel:** add the checkbox following the live-apply pattern from PR #5 (the filter
  applies immediately through `qcApplyFilterChange`).

### Self-correction
If a flagged quest is ever found in the player's quest log or completes, record its ID in a new
SavedVariable (e.g. `qcFlaggedButSeen`), and optionally print a one-time chat line. That's proof
the flag is wrong. Reviewing that list and removing those IDs is the ongoing maintenance loop, and
it catches mistakes that no offline data can.

## Tooling

- **`tools/Find-UnavailableQuestCandidates.ps1`** (added with this plan): report-only signal
  gathering. Re-run it after the database or the client tables change. Its CSV gives each quest's
  decision, if it has one, and its summary counts the no-signal quests still to review.
- **`tools/Build-UnavailableQuests.ps1`**: generates `qcUnavailableQuests.lua` from a
  reviewed decisions file, `docs/plans/unavailable-quest-decisions.csv`
  (`QuestID, Name, Zone, Reason, Decision, Evidence`). `FLAG` rows, with reason 1 or 2, are the
  quests it hides; `KEEP` rows record quests reviewed and left shown. This is the same pattern as the
  accuracy-cleanup decisions CSVs, so every flag carries its reason.
  - The file is generated in quest ID order, one entry per line, with a header comment saying
    it's generated.
  - It refuses IDs that aren't in `qcQuestDatabase`, and task quests (unless a decision row
    explicitly overrides).

## Phases (one PR each)

### Phase 0: mechanism with an empty flag list
- Add `qcUnavailableQuests.lua` (empty table), the TOC entry, the filter in list/counts/pins, the
  option checkbox, and the self-correction log.
- Verify in-game:
  - with one test ID temporarily flagged, it disappears from the list and pins and reappears when
    the option is on;
  - a completed flagged quest still shows;
  - counts change as expected.
- (The "WoW: Forever" check originally listed here was dropped when #87 made the addon retail-only.
  Forever came back in #143 with its own `qcUnavailableQuests.lua`, which flags nothing yet.)
- Check offline first: the scratch list/map simulations must give identical output with an empty
  flag list, and the expected differences with test flags.

### Phase 1: flag the 183 "not in client, no signal" quests (reason 2)
- Generate their decision rows from the signals CSV.
- Look over the list by zone before merging: Torghast, Visions, "Legion Uncategorized" and
  similar are expected. Anything that looks like a normal story quest gets pulled out for Phase 2.
- The other 8 not-in-client quests *with* a signal go to Phase 2 review.

**Phases 0 and 1 done together (2026-09-30, `feat/unavailable-quests`; item 5 phase 4 in
`data-cleanup.md`).** None of the 183 are in the 12.1.5 PTR's `QuestV2` or quest location data.
By name they're tracking and reward quests: 29 paragon "Supplies from…" caches, Vision and Torghast
trackers, 14 "Legion ### A"-style entries, Broken Shore contributions, and test entries. Decisions
are in `docs/plans/unavailable-quest-decisions.csv`, and `tools/Build-UnavailableQuests.ps1`
generates the Lua file. Offline checks:
- with the option off, every list, counter and search result matches master;
- with it on, only flagged quests leave lists and counter totals;
- 18 targeted checks (exceptions, map, option, log), each shown able to fail by a deliberate
  breakage.

**Corrected in #154 (2026-10-05).** The server still knew 150 of the 183 (the correction above).
- **148 unflagged**, with KEEP rows saying why: 76 paragon and renown rewards, 33 Torghast rescues,
  24 Horrific Visions quests, 9 contributions and 6 others.
- **35 stay flagged:** the 33 the server doesn't know either ("Legion ### A", "Party Crashers!", the
  Highmountain jetpack quests, Primal Obliterum, the fishing flier 8228 and others), and 2 internal
  entries.

### Phase 2: human review of the 375 in-client, no-signal quests (reason 1), in groups
- Review by zone/category rather than one by one. For example, all 126 Warfront quests (mostly
  BfA Warfront contribution quests like "Arathi Donations: …") are probably one decision, and
  "Rated PvP" season rewards another.
- Evidence for each group comes from the reviewer: in-game knowledge, or Wowhead viewed manually.
  Automated browsing gets blocked by Wowhead after about 11 pages, and its terms forbid scraping.
- Anything uncertain stays unflagged. The cost of wrongly hiding a live quest is higher than
  showing an obsolete one.

**Done with the user (2026-10-05, #154).** 376 quests by then, grouped by kind:

| Group | Quests | Decision |
|---|---|---|
| Internal and test entries ([DNT], placeholder and test names) | 25 | FLAG |
| Hidden trackers (Bronze to Platinum Tracker, Talador's "… Tracking", Venari Rep Token Tracking, N'Zoth assault trackers) | 44 | FLAG |
| Retired: The Arts of a Druid, Mage and Shaman (Wowhead lists 24760 as obsolete), Legion's pre-launch "Invasion: …", a Shadowlands Season 1 reward, "Armies of Legionfall [DEPRECATED]" | 7 | FLAG |
| "Conquest's Reward", Battle for Azeroth's weekly PvP rewards | 8 | FLAG, with the other 98 of that name (below) |
| Emissary bounties, which still rotate | 20 | KEEP |
| Recurring content that's likely live (Special Assignments, Zskera Vaults, Endeavors) and 2 holiday quests | 61 | KEEP |
| No pattern, no evidence either way | 80 | KEEP |
| Battle for Azeroth warfront donations ("Arathi Donations: …"): Wowhead shows no "no longer available" notice for any of the 8 the user looked up | 131 | KEEP |
| From Phase 1, not in the client but with a pin or an achievement criterion: 6 Legion "Supplies From …" caches and "The Bounties of Legionfall", repeatable paragon rewards the server still knows | 7 | KEEP |
| From Phase 1, the same: "Could I get a Fishing Flier?" 8229, which the server doesn't know either, like 8228 | 1 | FLAG (reason 2) |

- Flagging a hidden tracker is safe even if it's still live. The game completes trackers without a
  turn-in, so the self-correction message never fires, and a completed flagged quest still shows as
  done.
- All 106 "Conquest's Reward" quests are flagged, not just the 8 that came up here. None is known
  to Blizzard's API, and Wowhead lists 54079 as obsolete. The other 98 have pins (Marshal Gabriel and
  High Warlord Volrath), which go too.
- That's 183 more flags. With Phase 1's correction, 218 quests are flagged in all, and 503 have KEEP
  rows (56 of them from the menu review of 9 October 2026, [menu-review.md](menu-review.md)).

### Phase 3: maintenance
- Periodically review `qcFlaggedButSeen` (from players who report it, or your own characters) and
  unflag anything listed.
- After a new expansion or patch, re-run `Audit-QuestAccuracy.ps1` (API cache) and
  `Find-UnavailableQuestCandidates.ps1`, and review new candidates.

## Verification checklist (every PR that changes the flag list)
- `luac -p` clean on `qcUnavailableQuests.lua`.
- Every flagged ID exists in `qcQuestDatabase` and is not a task quest (unless overridden).
- Flag count in the Lua file = `FIX` rows in the decisions CSV.
- In-game: sample flagged quests are hidden; a completed flagged quest still shows.

## Not in scope
- Deleting quests from `qcQuest.lua`.
- Task quests (world quests and bonus objectives): old-expansion ones are generally still live.
- Reputation data (`docs/plans/quest-reputation-data.md`).
