# Plan: Flagging Unavailable Quests (obsolete and hidden tracking quests)

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
- the new option **"Show unavailable quests"** is on (default off).

Where to apply it (all in `qcCore.lua`):
- **Quest list:** alongside the other hide filters, right after the category list is built
  (`qcCategoryQuests = qcCopyTable(...)` around lines 248–254; the existing filters follow at
  ~262–360).
- **Completion counts:** the "X/Y Complete" figure (~505–532) should exclude flagged quests the
  character hasn't completed, so unobtainable quests don't drag completion percentages down.
- **Map pins:** skip flagged quest IDs when building a map's pins (~1736 onwards), with the same
  completed/in-log exceptions.
- **Options panel:** add the checkbox following the live-apply pattern from PR #5 (the filter
  applies immediately; no reliance on the legacy `self.okay` callback).

### Self-correction
If a flagged quest is ever found in the player's quest log or completes, record its ID in a new
SavedVariable (e.g. `qcFlaggedButSeen`), and optionally print a one-time chat line. That's proof
the flag is wrong. Reviewing that list and removing those IDs is the ongoing maintenance loop, and
it catches mistakes that no offline data can.

## Tooling

- **`tools/Find-UnavailableQuestCandidates.ps1`** (added with this plan): report-only signal
  gathering. Re-run it after the database or the client tables change.
- **`tools/Build-UnavailableQuests.ps1`** (to write): generates `qcUnavailableQuests.lua` from a
  reviewed decisions file, `docs/plans/unavailable-quest-decisions.csv`
  (`QuestID, Name, Reason(1|2), Evidence, ReviewedBy`). This is the same pattern as the
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
- Also verify under the "WoW: Forever" interface (`16001`), which the TOC also targets. Guard any
  API that may not exist there, the same way the existing code guards `C_MajorFactions`.

### Phase 1: flag the 183 "not in client, no signal" quests (reason 2)
- Generate their decision rows from the signals CSV.
- Look over the list by zone before merging: Torghast, Visions, "Legion Uncategorized" and
  similar are expected. Anything that looks like a normal story quest gets pulled out for Phase 2.
- The other 8 not-in-client quests *with* a signal go to Phase 2 review.

### Phase 2: human review of the 375 in-client, no-signal quests (reason 1), in groups
- Review by zone/category rather than one by one. For example, all 126 Warfront quests (mostly
  BfA Warfront contribution quests like "Arathi Donations: …") are probably one decision, and
  "Rated PvP" season rewards another.
- Evidence for each group comes from the reviewer: in-game knowledge, or Wowhead viewed manually.
  Automated browsing gets blocked by Wowhead after about 11 pages, and its terms forbid scraping.
- Anything uncertain stays unflagged. The cost of wrongly hiding a live quest is higher than
  showing an obsolete one.

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
