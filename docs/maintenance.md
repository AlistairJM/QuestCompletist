# Maintaining the quest data

How to refresh and re-check the addon's data after a WoW patch: quests, quest types, reputation
rewards, storylines, category names and map pins. Everything here is run from the repository root
in PowerShell, using the scripts in `tools/`.

If you're working with Claude Code in this repository, **"do a full sweep"** runs all of this for
you. It will tell you up front which steps need you in the game.

## One-time setup

- **Lua 5.1** at `C:\Program Files (x86)\Lua\5.1\` – for `luac -p`, the syntax check every change
  gets before it's committed.
- **GitHub CLI** (`gh`) – every change goes in through a branch and a pull request, never straight
  to `master`.
- **Blizzard API credentials** in `tools\.env`:
  ```
  BLIZZARD_CLIENT_ID=...
  BLIZZARD_CLIENT_SECRET=...
  ```
  Create a client at <https://develop.battle.net/access/clients>. The file is gitignored; never
  commit it or paste it anywhere.
- **Let the game run the repository's copy of the addon.** Replace the installed folder with a link
  to the repo, so a `/reload` in game picks up whatever branch is checked out:
  ```powershell
  Rename-Item "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\QuestCompletist" "QuestCompletist.installed"
  New-Item -ItemType Junction -Path "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\QuestCompletist" -Target "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist"
  ```
  Then move `QuestCompletist.installed` out of the `AddOns` folder. **Don't let CurseForge update,
  reinstall or uninstall Quest Completist while the link is in place.** Reinstalling through it is
  what broke the link last time, and depending on how it clears the folder, it could delete files
  in the repository.

`tools\` only tracks its `*.ps1` scripts. Everything the scripts download or write there (CSV
exports, the API cache, reports) is gitignored and can be regenerated.

## Before a sweep

1. **Find the current game builds** at <https://wago.tools/api/builds/latest>. Retail is product
   `wow`. The TOC's second interface number (`16001`) is Classic 1.60, product `wow_classic_beta`.
2. **Pin the build.** Scripts that take `-Build` should be given the current retail build.
   Downloading a table from wago.tools without a build number does *not* reliably return the latest
   retail build.
3. **Move the Blizzard API cache aside** so every quest is fetched fresh:
   ```powershell
   Rename-Item tools\quest_api_cache "quest_api_cache.$(Get-Date -Format yyyyMMdd)"
   ```
   The audit reuses whatever is cached, forever. A cached `.json` or `.404` for a quest is never
   fetched again.

Run a script with:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\<Script>.ps1 [parameters]
```

## The sweep

Run the report-only steps first, then make one branch and pull request per kind of change.

| # | Area | Scripts, in order | Edits the addon? |
|---|---|---|---|
| 1 | Faction, race and class | `Audit-QuestAccuracy.ps1` → `Categorize-AuditDiscrepancies.ps1` → `Apply-AccuracyFixes.ps1 -Field <field>` | Only the last one |
| 1b | Second source for race and class | `Get-WagoQuestRequirements.ps1 -Refresh` | No |
| 2 | Reputation rewards | `Compare-QuestReputation.ps1` → `Apply-ReputationBackfill.ps1` | Only the last one |
| 3 | Quest types | `Retype-FlaggedWorldQuests.ps1`, `Retype-ProbeRecurring.ps1` | Yes |
| 4 | Storylines | `Build-QuestLines.ps1 -Build <retail build> -Refresh` | Yes |
| 5 | Category names from the client | `Build-CategoryUiMapIDs.ps1 -Refresh` → `Remove-ConvertedLocaleKeys.ps1 -WhatIf` → `Build-CategoryClientNames.ps1 -Refresh` | Yes |
| 6 | Map pins | see [the pin pipeline](plans/quest-location-data-pipeline.md) | Writes a candidate file only |
| 7 | Quests that may no longer be obtainable | `Find-UnavailableQuestCandidates.ps1 -Refresh` | No |

### 1. Faction, race and class

`Audit-QuestAccuracy.ps1` checks every quest against Blizzard's API, filling `tools\quest_api_cache`
as it goes. That takes about 17 minutes with an empty cache. It writes
`quest_accuracy_audit.csv`, plus a list of quests the API doesn't know (old or removed content,
expected). `Categorize-AuditDiscrepancies.ps1` groups the disagreements.

Review before applying anything. Two lessons from the last cleanup:
- A faction's race mask is not a stale placeholder.
- Only restrictions the API actually asserts can be trusted.

The decisions from that cleanup are in
[plans/quest-database-accuracy-cleanup.md](plans/quest-database-accuracy-cleanup.md).
`Apply-AccuracyFixes.ps1` applies one field's reviewed fixes at a time.

To leave a MANUAL row as it is, record it in `docs\plans\quest-accuracy-manual-decisions.csv` with
`Decision` set to `KEEP`, our current value in `Cur`, and a reason. Later sweeps then report it as
KEPT rather than raising it again, unless our value changes.

### 2. Reputation rewards

`Compare-QuestReputation.ps1` compares `qcQuestReputation` against the API cache from step 1 and
writes `quest_reputation_compare.csv`. `Apply-ReputationBackfill.ps1` only adds rewards the API
lists and we don't have. It never changes existing ones.

### 3. Quest types

Types are a bitmask. The ones that matter here:

| Type | Meaning |
|---|---|
| 1 | normal, one-time |
| 2 | repeatable |
| 4 | daily |
| 128 | world quest **or** weekly. The weekly reset clears both. |

- `Retype-FlaggedWorldQuests.ps1` moves 128 to daily or repeatable when the API flags the quest that
  way and it isn't a world quest.
- `Retype-ProbeRecurring.ps1` moves 1 to daily or 128 when the in-game probe (below) says the quest
  recurs **and** the API flags it daily or weekly.

Both only pick up new cases, so they're safe to rerun. Before changing any type by hand, know that
neither source proves a quest is one-time:
- The API leaves many weeklies unflagged, such as Shadowlands' "Trading Favors" and Dragonflight's
  profession weeklies.
- The game calls paragon caches, emissary bounties, Special Assignments and "Conquest's Reward"
  *Normal*, even though they recur.

### 4. Storylines

`Build-QuestLines.ps1` regenerates each quest's storyline (field 13) and the `qcQuestLines` table
from Blizzard's own questline tables. It skips internal questlines ("8.0 Professions - … - SCS",
"[DNT] …"). It stores each storyline's quests in Blizzard's order.

### 5. Category names from the client

`Build-CategoryUiMapIDs.ps1` maps quest categories to game maps, so the client supplies their names
in every language. `Remove-ConvertedLocaleKeys.ps1` then deletes the translations that became
redundant. Run it with `-WhatIf` first.

Then run `Build-CategoryClientNames.ps1 -Refresh`. It names the categories that aren't maps from
other client tables: classes, professions, covenants, dungeons, achievement categories (the world
events), factions, Blizzard's UI text and area names. A rerun with no client changes leaves
`qcQuest.lua` byte-identical. Names we made up ("Bfa Unknown", "Garrison Support") stay ours.
Classic lacks some of these game functions, so those categories fall back to our translations.
The same tool writes `clientName` into `qcMenu.lua` for the menu headings it lists (continents,
expansions, "Battlegrounds", "Professions" and so on), chosen by hand.

### 6. Map pins

The pipeline builds `tools\qcPinDB_candidate.lua` for review. It never overwrites
`QuestCompletist\qcPinDB.lua`, and existing pins shouldn't move without a reason. The steps are in
[plans/quest-location-data-pipeline.md](plans/quest-location-data-pipeline.md). Download
`QuestPOIPoint` and `UiMapAssignment` for the pinned build first; `QuestPOIBlob` comes with step 1b.
Then run `Build-QuestLocationData.ps1`, `Parse-ExistingPinDB.ps1`, `Join-LocationsWithExisting.ps1`
and `Assemble-PinDB.ps1`, in that order.

`Join-LocationsWithExisting.ps1` reports how far each quest's start in the fresh data is from its
nearest existing pin. Treat that as a finding to review. When you're ready to take the new data,
run `Assemble-PinDB.ps1 -Apply`, which also writes `QuestCompletist\qcPinDB.lua`.

- An NPC's quests share a pin only where they start within 3 map points of each other.
- A pin that lands within 1.5 points of an existing one keeps the existing coordinates.
- Pins are written in a fixed order.

With no real changes, a rerun leaves `qcPinDB.lua` byte-identical.

Quests that appear in the pin data but are missing from the database are fetched with
`Fetch-GapQuestData.ps1` and added with `Insert-GapQuestEntries.ps1`. The inserter refuses any
quest that's already in the database.

It inserts them without a category (category 0), and no menu entry reaches those. Run
`Place-UncategorisedQuests.ps1 -WhatIf` afterwards, then without `-WhatIf`. It files each quest by
the first of these that gives an answer:
1. a name of the form "<category>: …" ("Prey: Anguish Island")
2. its Blizzard API area
3. the zone that contains that area on Blizzard's map
4. the map its pin is on
5. its own zone text
6. the zone above its pin's map, when that map has no category itself (Naigtal → Voidstorm)
7. its storyline, when the filed quests in it all agree and at least half of it is filed

`-Explain` writes `tools\uncategorised_quests.csv`: each quest it placed, with the rule, and each
quest it couldn't, with what's missing. The summary names the maps that have pins but no category,
which usually means `qcAreaIDToCategoryID` lacks them.

It never files a quest in a category that no menu entry reaches. A quest in such a category can
still be found by search, but not by browsing. After adding categories, check every category that
holds quests has an entry in `qcMenu.lua`.

`-Refile 1150,1050` also files the quests in the catch-all categories "Bfa Unknown" and "Legion
Uncategorized". For those it adds a hand-written list in the script that maps the catch-all's zone
text ("Death Knight Campaign", "Time Rifts") to a category. What's left in the catch-alls has nothing to go on.

A quest nothing can place stays in category 0, which the menu lists as Uncategorized under
Miscellaneous. A quest in a category that isn't defined is moved there too.

Then run `File-WeeklyEventQuests.ps1 -WhatIf`, then without `-WhatIf`. It moves the weekly bonus
event quests (timewalking, "A Call to Battle", "The Arena Calls" and the rest) to Weekly Events, under
World Events. A quest qualifies when the API puts it in its "Weekly Event" category, or when its
name is one of the event families and the API names no other category. Placement would otherwise
file new ones by their quest-giver's zone. It only finds new cases, so it's safe to rerun.

After moving quests between categories, run `Remove-EmptyMenuEntries.ps1 -WhatIf`, then without
`-WhatIf`. It removes menu entries whose category no longer holds any quests, except Uncategorized.

### 7. Quests that may no longer be obtainable

`Find-UnavailableQuestCandidates.ps1` gathers evidence per quest from the API, the client's tables
and our pins. It's a report only; see [plans/unavailable-quests.md](plans/unavailable-quests.md).

## In the game

Some answers only the game client has.

**Quest-type probe (`/qc typecheck`).** This asks the client whether each quest recurs. It lives on
the draft pull request #42, branch `tools/quest-type-probe`.

1. Check out that branch, then **restart the game fully**. The probe adds a file to the TOC, and a
   `/reload` doesn't pick that up.
2. Type `/qc typecheck`. It loads every quest from the server a few at a time, which takes about two
   hours. `/qc typecheck stop` pauses it, and running it again resumes. Its progress is kept across
   `/reload`s and logouts.
3. When it says it has finished, `/reload`.
4. **Before switching branches**, copy
   `C:\Program Files (x86)\World of Warcraft\_retail_\WTF\Account\<ACCOUNT>\SavedVariables\QuestCompletist.lua`
   to `tools\quest_type_probe_results.lua`. Once the probe isn't in the TOC any more, WoW drops its
   results from that file the next time it saves.

`Retype-ProbeRecurring.ps1` reads that copy.

## Checking a change before its pull request

```powershell
& "C:\Program Files (x86)\Lua\5.1\luac.exe" -p QuestCompletist\qcQuest.lua QuestCompletist\qcCore.lua
(Select-String -Path QuestCompletist\qcQuest.lua -Pattern '^\[\d+\]=\{').Count
git diff --stat
```

- The syntax check must be silent.
- The quest count should only change when quests were meant to be added or removed. It's 35,023 as
  of September 2026.
- The diff should touch only what the change is about. For data changes, check that only the
  intended field moved on each line.
- The addon's files use Windows (CRLF) line endings. A script that writes them must keep that.

## Never rerun these

These were one-off fixes or migrations. Running them again would fail, or worse, apply their change
twice:

- `Migrate-ReputationToSideTable.ps1`
- `Fix-MenuDeadEntries.ps1`
- `Fix-MisfiledUiMapCategories.ps1`
- `Fix-QuestDatabaseIssues.ps1`
- `Relocate-GapQuestEntries.ps1`
- `Add-DungeonCategories.ps1`
- `Add-MissingMenuEntries.ps1`
- `Fix-CategoryNameTypos.ps1`
- `Fix-DuplicateCategory1344.ps1`
- `Fix-MenuStructure.ps1`
- `Retype-OneTimeFamilies.ps1`, a hand-judged list of quests
- `Derive-IconTypeMapping.ps1`, analysis only

## Where the data comes from

| Source | Used for | How |
|---|---|---|
| Blizzard's Game Data API | faction, race, class, reputation, daily/weekly flags | `Audit-QuestAccuracy.ps1`, cached in `tools\quest_api_cache` |
| The game client's own tables, via [wago.tools](https://wago.tools) | task quests, questlines, map positions, map names, dungeon journal | CSV exports per build, e.g. `https://wago.tools/db2/QuestLine/csv?build=<build>` |
| The game itself | recurring or one-time, world quest or not | in-game probes and runtime API calls |
