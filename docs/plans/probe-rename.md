# Renaming the probe

## Goal

The user, 10 October 2026, after the probe had run on both games: "should we be changing the probe name from
`QCForeverProbe`?" Then: "Plan the full rename for after the retail run." The name dates from the Forever beta
probe (#139). The probe now runs on retail and Forever (`tools/ForeverProbe`, #232 to #237, run on both on 9
and 10 October), and the addon list says "QC Forever probe". This is the plan; nothing is renamed yet.

## What changes, and what does not

| Now | After | Why |
|---|---|---|
| AddOns folder `QCForeverProbe` | `QCProbe` | the name the game shows and the saved-variables file takes |
| `QCForeverProbe.toc`, `QCForeverProbe_Camelot.toc` | `QCProbe.toc`, `QCProbe_Camelot.toc` | a TOC must be named after its folder; the `_Camelot` suffix stays (it is how Forever's client picks its TOC) |
| `QCForeverProbe.lua` (the addon's code) | `QCProbe.lua` | |
| TOC title and chat prefix "QC Forever probe" | "QC probe" | |
| `## SavedVariables: QCForeverProbeDB`, the global `QCForeverProbeDB` | `QCProbeDB` | the TOC lists both for one release, see "Keeping the old results" |
| `SlashCmdList.QCFOREVERPROBE` | `QCPROBE` | `/qcprobe` itself does not change |
| `tools/ForeverProbe/` and `tools/ForeverProbe/QCForeverProbe/` | `tools/Probe/` and `tools/Probe/QCProbe/` | `Build-ProbeLists.ps1` keeps its name and moves with the folder |
| `tools/Read-ForeverProbe.lua` | `tools/Read-Probe.lua` | |
| The saved file `WTF\Account\<account>\SavedVariables\QCForeverProbe.lua` | `QCProbe.lua` | the game writes it, named after the addon |
| The probe's result files, `tools\<game>_probe_<revision>\QCForeverProbe.lua` | `QCProbe.lua` | the six files held now are renamed once |

Not renamed, on purpose:

- `/qcprobe`, the command (already neutral).
- `tools\forever_probe_<revision>\` and `tools\retail_probe_<revision>\`: those folders hold one game's results,
  and the game is in the name for a reason.
- `QuestIDs_Forever.lua`, `NpcIDs_Retail.lua` and the other per-game lists, for the same reason, and the Forever-only
  code (`GetForeverExperiencePreset`) and tools (`Import-ForeverData.ps1`).
- `Test-Probe.lua` and `Test-ProbeLists.ps1` (the names are already neutral), and the history in
  `docs/plans/forever.md`, where "QCForeverProbe" says what it was called then.

## Inventory (master at b25544d)

27 tracked files and 92 lines carry `QCForeverProbe`; 28 files and 125 lines carry `ForeverProbe` in any form.

- **The probe**, 4 files: `QCForeverProbe.lua` (7 lines: the header, the saved variable at its load, the slash
  command, the chat prefix, a hint naming the builder), the two TOCs (title, saved variable, file lists), and
  `Build-ProbeLists.ps1` (its default `-AddonDir`, the header of each list it writes).
- **Tools that find a result file by name:** `Compare-PinNpcNames.ps1`, `Import-ForeverData.ps1` (the newest
  `forever_probe_*\QCForeverProbe.lua`), `Import-RecordedGivers.ps1` (`*_probe_*\QCForeverProbe.lua`),
  `ProbeResults.ps1` (retail's newest), `LatestBuilds.ps1` (`Get-ProbeBuild`, and where it looks for the
  scripts' pinned builds), `Get-LatestBuilds.ps1` (the checkout's lists and the AddOns copies), and the comments of
  `Find-UnavailableQuestCandidates.ps1` and `Retype-ProbeRecurring.ps1`.
- **Tools that read the saved variable by name:** `Read-ForeverProbe.lua`, `Report-MapOffers.lua`,
  `Read-RecordedGivers.lua` and `ProbeResults.ps1` (which tells a probe file from the old type probe's by
  looking for `QCForeverProbeDB`).
- **Tests**, 7 files: `Test-Probe.lua`, `Test-ProbeResults.ps1`, `Test-LatestBuilds.ps1`, `Test-RecordedGivers.lua`
  and `.ps1`, `Test-ProbeLists.ps1`, `Test-QuestCache.ps1`, and the fixtures in them that stand in for the AddOns folder.
- **`.gitignore`**, 4 lines: the exception for `Read-ForeverProbe.lua`, for `tools/ForeverProbe/`, and the two
  patterns for the generated lists.
- **Docs:** `maintenance.md` (12 lines: steps 3 and 10, "In the game", the checks list), `game-api-review.md` (5, mostly
  paths of dated results), `open-items.md` (2) and `forever.md` (2, historical).
- **On this PC, outside the repository:** `_retail_` and `_classic_beta_` `Interface\AddOns\QCForeverProbe`, the two
  saved files (17.3 MB for retail, 2.0 MB for Forever), and the six result files in `tools\` (four Forever, retail's
  and its dated copy).

## When

Not before both of these, in this order:

1. **The retail run after 12.1.5 is read.** The patch goes live on 13 or 14 October. The run (`/qcprobe quests`,
   `npcs`, `maps 1`, after `Get-LatestBuilds.ps1` and a rebuilt retail list) is copied into
   `tools\retail_probe_<build>\` and read (step 3, `Compare-PinNpcNames.ps1`, step 2e, step 7). No run is in flight
   and no result unread when the names change.
2. **#262 (the geometry pass) has merged**, and any other branch that edits `QCForeverProbe.lua`, `Test-Probe.lua` or
   `tools/ForeverProbe`. At the time of writing #262 adds 171 lines to the probe and 252 to `Test-Probe.lua`;
   a rename under it would conflict on every hunk.

And before Forever's launch on 4 November, which is the next time the probe runs: the target is the week of 19
October. The rename is one pull request, with the local steps below once it is merged.

## The pull request

1. **Move the files with `git mv`** (history follows): the folder `tools/ForeverProbe` to `tools/Probe`, its
   `QCForeverProbe` to `QCProbe`, the three files inside it, and `Read-ForeverProbe.lua` to `Read-Probe.lua`.
   The generated lists are ignored files and stay behind in the old folder; they are rebuilt, and the old folder is deleted.
2. **Replace the names in the contents,** token by token, from the table above, with a one-off script that is
   deleted after the merge. It keeps each file's line endings and encoding (most of these files are CRLF, some
   have a BOM), and the diff is checked file by file for lines that changed other than by the token.
3. **The probe's own changes:**
   - The TOCs list `QCProbeDB, QCForeverProbeDB`, and the probe adopts an old table when the new one is absent:
     `QCProbeDB = QCProbeDB or QCForeverProbeDB`, then `QCForeverProbeDB = nil` so it is not saved twice. A
     test plays both: a fresh install, and an old saved table that is adopted with its runs and its quests intact.
   - The chat prefix, the slash key and the hint that names the builder.
4. **The readers accept both saved-variable names,** `QCProbeDB or QCForeverProbeDB`, in `Read-Probe.lua`,
   `Report-MapOffers.lua`, `Read-RecordedGivers.lua` and `ProbeResults.ps1`, so old files read as they did. The tools
   that find a result file by name look for `QCProbe.lua`.
5. **`Get-LatestBuilds.ps1` gains a check:** an old `QCForeverProbe` folder still in a game's AddOns is `BEHIND`
   ("remove it: both would load, and both answer `/qcprobe`"). It is the one mistake the rename invites.
6. **Tests:** the existing ones follow the names; new ones for the adoption, for each reader on an old file and on a
   new one, for the new check, and for `.gitignore` (the generated lists are still ignored in their new place).
   All test scripts must pass, not only the ones near the change: that is how #256 went wrong.
7. **Docs:** `maintenance.md`, `open-items.md`, `game-api-review.md` and this plan say the new names; where a doc
   records a dated result by its path, the path is the new one (the files are renamed on disk).

## After the merge, on this PC

1. Close both games.
2. In each game's `Interface\AddOns`, delete `QCForeverProbe`.
3. `Build-ProbeLists.ps1 -Game retail` and `-Game forever` (they take the installed builds), then copy
   `tools\Probe\QCProbe` into `_retail_` and `_classic_beta_`.
4. To keep the old results in the new addon: copy `WTF\Account\<account>\SavedVariables\QCForeverProbe.lua` to
   `QCProbe.lua` in each game before the first login. The probe adopts the table. Skipping it loses nothing that
   matters: the quest caches, the answer memory, the ledger and the result folders hold what the sweep uses, and
   the probe asks again whatever has no answer on the build.
5. Rename the six result files in `tools\*_probe_*` to `QCProbe.lua` (and the dated copy to `QCProbe.2026-10-07.lua`).
6. `Get-LatestBuilds.ps1` must say everything is current and no old probe folder is installed.
7. In the game: log in on each, see "QC probe: loaded", and `/qcprobe status`. The next real run is the first test of
   the rest; it needs nothing extra from the user.

## Rollback

Revert the pull request, put the old folder back in AddOns. The old saved files are never touched (the new addon
writes `QCProbe.lua` beside them), so nothing is lost either way.

## Risks

| Risk | What stops it |
|---|---|
| A run in flight, or a result unread, when the names change | the first condition under "When" |
| A conflict with other probe work | the second; #262 first |
| Both folders installed, so two probes answer `/qcprobe` | step 2 after the merge, and the new check |
| A tool still looks for the old file name and finds nothing | the tests run every reader on a new-named folder; the check on the real folders is `Get-LatestBuilds.ps1` and a full run of the importer with `-WhatIf` |
| An old result file unreadable | the readers accept both variable names, and a test reads a real old-shaped file |
| A CRLF file rewritten as LF, or a BOM lost | the script's rules and the file-by-file diff check (`sed -i` is not used: it silently converts CRLF to LF) |
| The generated lists left behind in `tools/ForeverProbe` | rebuilt in step 3 and the old folder deleted; they are ignored, so nothing is committed by mistake |

## To decide

- That the new name is `QCProbe` (the shortest that is neutral; `QCDevProbe` would say what it is for, at four
  more letters).
- Whether to keep the adoption of the old saved table (a few lines and a test, so that an old file can be moved
  in), or to start the new saved file empty.
- The week of 19 October as the target.
