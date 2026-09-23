# Plan: Quest Reputation Reward Data

## Goal

Backfill reputation rewards for the ~10,900 quests where Blizzard's API lists one and our database
has none, so the quest tooltip's reputation panel shows real data. Existing reputation data is
already accurate and should be left alone.

## Before starting

- **Merge the accuracy cleanup PRs first:** #14, then #15 → #16 → #17 → #18 → #19 → #20. Those
  PRs rewrite faction/race/class on 1,170 quest lines. Branching from `master` before they merge
  would conflict on those lines. Afterwards, branch from `master`.
- **Refresh the API cache if it's gone.** `tools/quest_api_cache/` is gitignored. If it's missing,
  run `tools/Audit-QuestAccuracy.ps1`, which rebuilds it in ~17 minutes with 8 parallel workers.
  It needs `tools/.env` with `BLIZZARD_CLIENT_ID`/`BLIZZARD_CLIENT_SECRET`.
- **Re-run `tools/Compare-QuestReputation.ps1`** and check the numbers below still hold before
  changing anything.

## How reputation is stored and shown today (the layout Phase 2a replaces)

Each `qcQuestDatabase` entry is a positional table. Reputation lives in the last three fields, and
**only entries with 17 fields have them**:

| Field | Meaning | Notes |
|---|---|---|
| 1–9 | id, name, level, zone, areaid, type, faction, race, class | Always present |
| 10–14 | profession, holiday, covenant, storyline, prereq | Always present |
| 15 | unused ("Beta Code" in `qcCore.lua:555`) | `0` in all 656 17-field entries; never read |
| 16 | primary reputation faction ID | Tooltip shows `Faction: <qcFactions name>` (`qcCore.lua:1170-1177`) |
| 17 | reputation reward: a number, **or** `{[factionID]=value, ...}` | Tooltip panel (`qcCore.lua:1179-1217`) handles both forms |

Examples:
```lua
[26863]={26863,"Filthy Paws",5,"Loch Modan",0,1,1,67108863,8191,0,0,0,0,0,0,47,350},
[8249]={8249,"Junkboxes Needed",20,"",0,1,3,67108863,8191,0,0,0,0,0,0,349,{[349]=75,[70]=-75}},
```

- **Number form:** the tooltip shows a generic "Reputation: 350 rep" line, and the faction name
  comes from field 16's `Faction:` line.
- **Table form:** the tooltip lists each faction by its `qcFactions` name (falling back to the raw
  ID), with signed values.
- **Faction names:** `qcFactions` (in `qcQuest.lua`, around line 215) maps faction ID → English
  name, 218 entries.
- **Renown is out of scope:** `qcRenownLevelRequirements` is a separate *requirement* table,
  not a reward.

## What we know (measured 2026-09-22, `master` + cached API)

Numbers are from `tools/Compare-QuestReputation.ps1`:

| | Quests |
|---|---|
| Entries with 14 fields (no reputation fields at all) | 34,366 |
| Entries with 17 fields | 656 (120 have a non-zero reward; the rest are all zeros) |
| Entries with 15 fields (odd one out, quest 11) | 1 |
| API has reputation, we have none | **10,915** |
| ...of which the API lists more than one faction | 840 |
| Both have reputation, and it matches exactly (factions and values) | **120 of 120** |
| We have reputation, the API has none | 0 |
| Neither has reputation | 19,033 |
| API returns 404 (task quests; no reputation source) | 4,955 |

Other findings:
- **Existing data is accurate.** Every quest that already has reputation matches the API exactly,
  so this is purely a backfill, not a correction.
- **API values can be used as-is.** They are the base reward amounts that the existing data
  already uses. The most common are 250 (4,261), 75, 150, 350, 10, 500, 25 and 100. 31 rewards
  are negative, e.g. quest 351 gives Booty Bay +250 and Bloodsail Buccaneers −250. The table form
  already supports those.
- **54 reward factions are missing from `qcFactions`.** They cover about 2,900 rewards. For
  those, the tooltip would drop the `Faction:` line (single-number form) or show the raw ID
  (table form). They're mostly Mists of Pandaria (Tillers and their
  friends, Klaxxi, Golden Lotus, Shado-Pan…) and Battle for Azeroth (Zandalari Empire, Proudmoore
  Admiralty, Storm's Wake, 7th Legion, Honorbound, Tortollan Seekers, Champions of Azeroth…), plus
  a few older ones (Horde 67, Alliance 469, Frostwolf Clan 729, Thrallmar 947…). The full list is
  printed by the compare script.
- **No oddities to filter out.** No guild reputation or other surprising factions appear. The
  most common reward factions are Stormwind, Orgrimmar, Valdrakken Accord, Darnassus, Undercity,
  Bilgewater Cartel, Valiance Expedition and Ironforge.

## Known bug to fix first: the audit's reputation check is wrong

`tools/Audit-QuestAccuracy.ps1` decides whether we have reputation with:
```powershell
if ($tail -match ',[1-9]\d*,\{') { $hasRepCurrently = $true }
elseif ($tail -match ',[1-9]\d*,[1-9]\d*\s*$') { $hasRepCurrently = $true }
```
The second pattern matches **any entry whose last two fields are non-zero**. On a 14-field entry,
those are *storyline* and *prereq*, so 4,849 entries are misread as having reputation. That's why
the accuracy audit reported 3,918 "we have rep, API doesn't" rows. Those are almost all noise; the
real figure is 0.

Fix: count fields properly (the top-level splitter in `Compare-QuestReputation.ps1` does this), and
only read fields 16/17 when the entry has 17 fields. Then the audit and the categorizer's
"Reputation mismatches" section report real numbers. Better still, point the audit's reputation
column at the same logic as the compare script, so there's one definition.

## Design decisions (agreed 2026-09-23)

Reputation moves **out of the positional entry and into a side table keyed by quest ID**, the
pattern `qcRenownLevelRequirements` (`qcQuest.lua:436`) and `qcPinDB` already use:

```lua
qcQuestReputation = {
	[12008]={[72]=150},
	[51515]={[2103]=350,[1133]=350},
}
```

1. **One shape for every reward**, `{[factionID]=value,...}`, single or multi. That retires the
   number-vs-table duality the tooltip currently branches on, and the faction name comes from the
   key, so nothing needs a separate "primary faction" field.
2. **Quests with no reputation aren't listed at all.** No padding, and adding a future sparse
   attribute means another keyed table rather than new positional slots on 35,023 lines.
3. **Every quest entry ends up 14 fields.** Fields 15/16/17 are removed from the 656 entries that
   have them, and quest 11's stray 15th field goes too. Field 15 was never read for its value
   (`qcCore.lua:555` assigns it to an unused local), and fields 16/17 are read only by the
   reputation tooltip, which moves to the side table in the same change.
4. **Backfilling is then purely additive:** new rows in `qcQuestReputation`, no existing quest line
   touched. That removes the line-re-rendering risk that caused the PR #12 regression, and
   verification becomes "every pre-existing line is byte-identical".
5. **Add the 54 missing factions to `qcFactions`** using the API's English `reward.name`. The
   existing table is English-only, so this matches it.
6. **Task quests (4,955 API 404s):** leave as-is. There's no per-quest reputation source: it's
   server-side data, and wago.tools' client tables don't carry per-quest reputation amounts
   (`QuestFactionReward` is a generic amount table, not per quest; worth a 5-minute confirmation
   in the session). Document the gap rather than invent values.

Final state: 35,023 entries of exactly 14 fields, and `qcQuestReputation` with 11,035 rows
(120 migrated + 10,915 backfilled, quest 11 among them).

### Quest 11 and the off-by-one it shares with the gap inserter

Quest 11 has 15 fields, and the stray 15th is `72` — Stormwind's faction ID, with no value after
it. The API says quest 11 rewards Stormwind 250. So the faction ID was written one slot early and
the tooltip has silently shown nothing ever since.

`tools/Insert-GapQuestEntries.ps1:99` has the same fault: its template emits only five zeros
between class and the faction ID, producing **16**-field entries with the faction in slot 15. No
16-field entries exist in the file, so its output was corrected after the fact at some point, but
the script would reintroduce the bug on its next run. Phase 2a stops it writing reputation fields
at all.

## Phases

### Phase 0: tooling (no data changes) — done

Result: the field 16/17 reading now lives in `tools/QuestReputation.ps1`, which both the audit and
the compare script use. After re-running the audit from cache, the categorizer shows 10,915
"API has, we don't" and 0 the other way. That set is exactly the compare script's `api-only`
rows. Faction, race and class rows are unchanged (11,820 rows, all identical).

- Fix the audit's reputation detection (above), re-run the audit from cache, and confirm the
  categorizer's reputation section now shows ~10,915 "API has, we don't" and ~0 the other way.
- Keep `Compare-QuestReputation.ps1` as the single source of truth for reputation comparisons.
  Its CSV (`quest_reputation_compare.csv`) is what the fix script should read.

### Phase 1: `qcFactions` additions (small PR)
- Add the 54 IDs in ID order, in the existing format (`[id] = "Name",`).
- Verify: `luac -p` clean, no duplicate keys, and the compare script reports 0 missing factions.

### Phase 2a: move reputation to `qcQuestReputation` (behaviour-preserving)

No reward value changes in this phase; the same 120 quests show the same reputation, read from a
new place.

- Add `qcQuestReputation` to `qcQuest.lua` with the 120 migrated rewards, converting the
  single-number form to `{[factionID]=value}`.
- Strip fields 15/16/17 from all 656 17-field entries, and quest 11's stray field 15, by truncating
  at the last `,` before `}`. Never rebuild the rest of the line.
- Rewrite the tooltip (`qcCore.lua:1170-1217`) to read `qcQuestReputation[questId]` and loop the
  table once; the `Faction:` line comes from the reward's own keys. Delete the dead `e[15]` read at
  `qcCore.lua:555`.
- Stop `tools/Insert-GapQuestEntries.ps1` writing reputation fields (it emits 14 fields now), which
  also retires its off-by-one.
- Teach `tools/QuestReputation.ps1` to read the side table, so the compare script keeps working.
- **Verification:** `luac -p` clean; CRLF throughout; quest ID set unchanged (35,023); entry shapes
  become 14 fields for all 35,023; each of the 657 changed lines differs only by the removed tail;
  the compare script still reports match=120, api-only=10,915; in-game the tooltip on quest 26863
  (Filthy Paws → Thorium Brotherhood 350) and 8249 (Junkboxes Needed → Ravenholdt +75, Syndicate
  −75) is unchanged.

### Phase 2b: backfill the 10,915 (additive only)

- **Write `tools/Apply-ReputationBackfill.ps1`.** It reads `quest_reputation_compare.csv` rows with
  `Kind = api-only`, renders one `[questID]={[factionID]=value,...}` row each, and inserts them into
  `qcQuestReputation` in quest ID order. It must refuse to write at all if any row fails to render
  or if a quest ID is already present, the same all-or-nothing approach as `Apply-AccuracyFixes.ps1`.
- **Verification:**
  - `luac -p` clean on `qcQuest.lua`; CRLF throughout;
  - **every pre-existing line byte-identical** — the diff is inserted lines only;
  - `qcQuestDatabase` untouched: quest ID set and all 35,023 entry lines unchanged;
  - `qcQuestReputation` holds 11,035 rows, no duplicate keys, and every value matches the API;
  - re-run `Compare-QuestReputation.ps1`: api-only drops to 0, match rises to 11,035;
  - load-test in the Lua 5.1 harness (the file grows by roughly 11,000 × ~20 bytes ≈ 220 KB);
  - in-game: quest 12008 (Warsong Offensive 150), multi-faction 51515 (Zandalari Empire +
    Darkspear Trolls, 350 each), and quest 11 (Stormwind 250, the off-by-one fix).

### Phase 3: wrap-up
- Record the final numbers in this doc and in the accuracy cleanup plan's status section.
- Document the field layout (1–14, all present) next to the tooltip code and in this doc, with the
  rule that new sparse attributes get their own keyed table.
- Note the task-quest gap (no source) as a known limitation.

## Risks and how to handle them

- **Line re-rendering bugs:** these caused a syntax-breaking regression once before (the PR #12
  history). Phase 2b touches no existing line at all. Phase 2a only truncates 657 lines at a known
  comma; keep the all-or-nothing applier and the diff-based checker for it.
- **Merge conflicts with the accuracy PRs:** avoided by starting after they're merged.
- **Tooltip regression in Phase 2a:** the read path changes, so the in-game check on a
  single-faction and a multi-faction quest is required before Phase 2b builds on it.
- **API value drift:** the cache records the API's state on 2026-09-22 (namespace
  `static-12.1.0_68914-us`). If the cache is rebuilt later, re-run the compare script and
  re-check the 120-match baseline before applying.

## Files

- `tools/Compare-QuestReputation.ps1`: report-only comparison (added with this plan).
- `tools/QuestReputation.ps1`: shared reading of our reputation data (added in Phase 0).
- `tools/Audit-QuestAccuracy.ps1`: builds/refreshes `tools/quest_api_cache/`.
- `tools/Insert-GapQuestEntries.ps1`: writes new quest entries; stops emitting fields 15–17 in 2a.
- `QuestCompletist/qcQuest.lua`: `qcFactions` (around line 215), `qcQuestDatabase`, and
  `qcQuestReputation` (new in 2a).
- `QuestCompletist/qcCore.lua:1170-1217`: reputation tooltip, rewritten in 2a; the dead field 15
  read is at `qcCore.lua:555`.
