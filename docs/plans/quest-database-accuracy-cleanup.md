# Plan: Quest Database Accuracy Cleanup (post-audit)

## Context

`tools/Audit-QuestAccuracy.ps1` (built 2026-09-21/22, see git history) scanned the entire
`qcQuestDatabase` (35,023 entries) against Blizzard's Data API for faction/race/class/reputation
accuracy. This addon predates the Blizzard API by years and was hand-curated the whole time, so a
large mismatch count was expected going in — the question was always "how much, and which parts
are safe to fix mechanically vs. need a human to look."

Results of that first run:
- **20,228 discrepancies** → `tools/quest_accuracy_audit.csv` (one row per quest, `Mismatches`
  column lists which of faction/race/class/reputation disagree and what Blizzard's API expects).
- **4,957 quest IDs not found in the API at all** → `tools/quest_accuracy_notfound.txt` (expected —
  almost certainly old/removed content; see Phase 3).
- One clear, unambiguous sub-pattern was already extracted and fixed:
  [PR #12](https://github.com/AlistairJM/QuestCompletist/pull/12) fixed **249 quests** with
  `faction=0, race=0` — a sentinel combination that isn't a legitimate value under the addon's own
  `BitBand` filter logic (it hides the quest from every player), caused by a backfill script bug.
  That PR only touched the faction/race fields on those 249 rows — if any of them also had a class
  or reputation mismatch, that part is **still open**. Don't assume those 249 are fully clean; see
  Phase 0.

**Also confirmed this session (2026-09-22), so it doesn't need re-litigating:** the bitmask
conversion used throughout the audit/fix scripts is not a scheme mismatch. Blizzard's API returns
human-readable class/race **names** (e.g. `"Mage"`, `"Human"`), which `Resolve-Bitmask` in both
`Audit-QuestAccuracy.ps1` and `Insert-GapQuestEntries.ps1` maps through addon-native bit tables
that were checked and are byte-for-byte identical to the addon's own `qcClassBits`/`qcRaceBits` in
[qcCore.lua:64-82](../../QuestCompletist/qcCore.lua). Blizzard's raw internal class/race IDs are
never stored. There is no conversion bug to hunt for here.

## The core risk for this cleanup

20,228 is too many to eyeball, but it's also too many to blindly bulk-apply Blizzard's "expected"
value for. Unlike the 249-quest fix (where `faction=0,race=0` is unambiguously wrong under any
reading), most of these 20,228 need a reason to believe *our* data is wrong before overwriting it,
because:
- The addon's DB is hand-curated across years and may encode intentional decisions the API can't
  see (e.g. a quest chain gated by something other than a hard class/race requirement).
- Quest requirements can genuinely change between game patches; "current API state" isn't
  automatically "eternal truth" for old/removed content.
- A handful of edge cases in `Resolve-Bitmask` itself (the `Adventurer` sentinel, the
  `$maxNarrow` cutoff) are heuristics, not certainties.

The one pattern already spotted that *is* safe to bulk-fix mechanically is the **stale
"all races" sentinel** problem: this addon's `ALL_RACES` constant is `67108863` (26 bits, current
as of Dragonflight-era races like Dracthyr/Earthen Dwarf/Harronir). Many older entries instead use
a *smaller* historical "all races that existed at the time" constant (two examples seen so far:
`64175181`, `61658034`) that never got updated as new playable races shipped. A single specific
numeric constant recurring thousands of times across otherwise-unrelated quests (different zones,
levels, eras) cannot be a deliberate per-quest design choice — it's a stale sentinel, safe to
replace with the current `67108863` **once confirmed by clustering** (Phase 1). This is the same
shape of bug as the 249-quest fix, just on the "wrong value" side instead of the "zero" side, and
should be fixed the same mechanical way.

## Phase 0 — Re-baseline (do this first, before trusting any number above)

- Re-run `tools/Audit-QuestAccuracy.ps1` against current `master` (post-PR #12) to get a fresh CSV.
  Do **not** just subtract 249 from 20,228 — some of those 249 rows may still have an open
  class/reputation mismatch untouched by PR #12.
- Record the new total discrepancy count and not-found count at the top of this doc (or in the PR
  description of whatever fixes this) so progress is trackable across sessions.

## Phase 1 — Categorize and cluster (build, don't guess)

Build a new script, `tools/Categorize-AuditDiscrepancies.ps1`, that reads the fresh CSV and:
1. Splits rows by which mismatch type(s) they contain (faction / race / class / reputation, and
   combinations) — a plain count per category first.
2. For race and class mismatches specifically, clusters rows by their **current** value (the
   `cur=` number in the `Mismatches` text) and reports frequency, plus what the `exp=` value is for
   each cluster.
   - A cluster with a high count (hundreds/thousands) where `exp=` is consistently `67108863`
     (all races) or `8191` (all classes) is a stale "unrestricted" sentinel — high-confidence,
     mechanical fix, same as PR #12's approach.
   - Check specifically whether an analogous stale-class-sentinel pattern exists too — this
     addon's `ALL_CLASSES` has also grown over time (Monk, Demon Hunter, Evoker all added after
     launch), so an old "all classes at the time" constant smaller than `8191` recurring often is
     the same bug on the class side. Don't assume it's race-only until the clustering says so.
   - Small clusters (single digits, or values that don't recur) are more likely genuine
     per-quest disagreements and need individual review, not a bulk rule.
3. Reputation-only mismatches are a separate category from faction/race/class — likely another
   instance of "backfilled entries never captured `rewards.reputations`" (the same systemic gap
   already found and fixed once for a different quest batch, see PR #10). Worth checking whether
   these cluster around specific backfill batches (e.g. by checking if they're quests with no
   pre-existing pin data, same signature as before) rather than being random.

Output of this phase should be a plain-language summary (counts per cluster) that a human decides
on before any file gets touched — this phase makes no edits.

## Phase 2 — Fix in scoped batches, each its own branch/PR

For each high-confidence cluster identified in Phase 1 (e.g. "stale all-races sentinel `64175181`
→ `67108863`, N quests"):
- Write a small, targeted script (same shape as the PR #12 fix): capture each matched line's full
  remaining tail via `(.*)$` and reuse it verbatim, only replacing the specific field(s) known to
  be wrong. Do not reconstruct any part of the line by hand — that's what caused the syntax-error
  regression during the 249-quest fix earlier this session.
- Verify before claiming done, every time, no exceptions (per [[feedback_verify_before_claiming_fixed]]):
  - `luac -p` (or the local Lua 5.1 harness) on the resulting `qcQuest.lua` — must be clean.
  - Zero lone-LF line endings introduced (check explicitly; this bit us twice this session).
  - Quest ID set unchanged (35,023 in, 35,023 out) and exact line-changed count matches the
    cluster size.
  - Spot-check several individual fixed rows by hand against the audit CSV's `exp=` value.
- One PR per cluster/category, not one giant PR for all 20k — keeps each change reviewable and
  revertable independently, and matches how PR #10/#11/#12 were each scoped this session.
- Leave low-confidence/individual-judgment rows for a manual triage pass, or a follow-up plan —
  don't force everything into this cleanup just because it was found by the same audit.

## Phase 3 — Not-found list (`quest_accuracy_notfound.txt`, ~4,957 IDs)

- Spot-check a sample (10-20 IDs) manually — e.g. via Wowhead or the WoW client's own quest log
  API for known-removed content — to confirm these really are old/removed/inaccessible quests
  rather than a transient API/rate-limit artifact of the original scan.
- If confirmed as expected "old content, API doesn't know about it," no DB change is needed —
  just document the finding. If any sampled ID turns out to still be a live, current quest that
  the API should have returned, that's a bug in the audit script (possibly a transient failure)
  worth re-scanning just that subset before trusting the "not found" list further.

## Explicitly out of scope for this plan

- The TomTom "C stack overflow" crash investigation is unrelated to database accuracy and was
  paused separately — see the `project_tomtom_crash_investigation` memory for where that left off.
  Pick that up as its own task, not folded into this cleanup.

## How to resume

Start at Phase 0. Nothing in Phase 1+ should be trusted until the CSV is regenerated against
current `master`.
