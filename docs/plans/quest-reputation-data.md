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

## How reputation is stored and shown today

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

## Design decisions (recommendations; confirm at the start of the session)

1. **Storage form, following the existing convention:**
   - **Single faction** → field 16 = faction ID, field 17 = number. That's how 4/5 of the existing
     reputation entries are stored, and the tooltip shows the faction name via field 16.
   - **Several factions** (840) → field 16 = the first faction the API lists, field 17 = the
     `{[id]=value,...}` table, matching the existing table-form entries (e.g. 7168).
   - Field 15 = `0`.
2. **Extend 14-field entries to 17 fields** by inserting `,0,<factionID>,<value|table>` just before
   the closing `}`. Leave everything before that byte-for-byte, and keep the trailing `,` after
   `}` if present.
3. **17-field entries that are all zeros** (536): nothing to do. The API has no reputation for
   them either.
4. **Don't touch the 120 matching entries.**
5. **Add the 54 missing factions to `qcFactions`** using the API's English `reward.name`. The
   existing table is English-only, so this matches it.
6. **Task quests (4,955 API 404s):** leave as-is. There's no per-quest reputation source: it's
   server-side data, and wago.tools' client tables don't carry per-quest reputation amounts
   (`QuestFactionReward` is a generic amount table, not per quest; worth a 5-minute confirmation
   in the session). Document the gap rather than invent values.

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

### Phase 2: backfill (the main work)
- **Write `tools/Apply-ReputationBackfill.ps1`.** `Apply-AccuracyFixes.ps1` only rewrites fields
  7–9, so this needs its own applier. It should:
  - read `quest_reputation_compare.csv` rows with `Kind = api-only`;
  - match each quest line and require it to have exactly 14 fields (refuse anything else, and list
    the refusals);
  - insert the three fields before the final `}` without re-rendering any other part of the line;
  - refuse to write at all if any row fails, the same all-or-nothing approach as
    `Apply-AccuracyFixes.ps1`.
- **Batching**, one PR each:
  - **2a:** single-faction rewards (~10,075 quests). Consider splitting by quest ID range or
    expansion if the diff is too big to review comfortably.
  - **2b:** multi-faction rewards (840 quests, table form).
- **Verification**, all must pass (same standard as PRs #15–#20):
  - `luac -p` clean on `qcQuest.lua`;
  - zero lone-LF line endings (the file is CRLF throughout);
  - quest ID set unchanged (35,023);
  - exactly the expected number of lines changed, and each changed line differs from the original
    **only** by the inserted `,0,<id>,<value>` before the closing brace (write a diff-based checker,
    like the scratch `verify_multi.ps1` pattern used for #18–#20);
  - re-run `Compare-QuestReputation.ps1`: the batch's quests move from `api-only` to `match`;
  - load-test in the Lua 5.1 harness that the table still loads and `#` sizes are sane (the file
    grows by roughly 10,900 × ~10 bytes ≈ 110 KB, which is fine);
  - in-game: open the tooltip on a backfilled quest (e.g. 12008 → Warsong Offensive 150) and on a
    multi-faction one (e.g. 51515 → Zandalari Empire + Darkspear Trolls, 350 each).

### Phase 3: wrap-up
- Record the final numbers in this doc and in the accuracy cleanup plan's status section.
- Note the task-quest gap (no source) as a known limitation.

## Risks and how to handle them

- **Line re-rendering bugs:** these caused a syntax-breaking regression once before (the PR #12
  history). Never rebuild a line; only insert. Keep the all-or-nothing applier and the diff-based
  checker.
- **Merge conflicts with the accuracy PRs:** avoided by starting after they're merged.
- **Very large diff:** split Phase 2a if needed. Every line is the same kind of change, so review
  is mostly by the checker plus sampling.
- **API value drift:** the cache records the API's state on 2026-09-22 (namespace
  `static-12.1.0_68914-us`). If the cache is rebuilt later, re-run the compare script and
  re-check the 120-match baseline before applying.

## Files

- `tools/Compare-QuestReputation.ps1`: report-only comparison (added with this plan).
- `tools/Audit-QuestAccuracy.ps1`: builds/refreshes `tools/quest_api_cache/`; its reputation check
  needs the Phase 0 fix.
- `QuestCompletist/qcQuest.lua`: `qcFactions` (around line 215) and `qcQuestDatabase`.
- `QuestCompletist/qcCore.lua:1170-1217`: tooltip code that reads fields 16/17.
