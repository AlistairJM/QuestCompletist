# Maintaining the quest data

How to refresh and re-check the addon's data after a WoW patch: quests, quest types, reputation
rewards, storylines, category names and map pins, for both games the addon runs on, retail and
WoW: Forever. Everything here is run from the repository root in PowerShell, using the scripts in
`tools/`.

If you're working with Claude Code in this repository, **"do a full sweep"** (or "refresh the data")
runs all of this for you, for both games. It will tell you up front which steps need you in the
game.

Releasing a new version is covered in [releasing.md](releasing.md).

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
  Then move `QuestCompletist.installed` out of the `AddOns` folder. Do the same for WoW: Forever, in
  its client's folder (`_classic_beta_` during the beta). Both links point at the same folder:
  retail reads `QuestCompletist.toc` and Forever reads `QuestCompletist_Camelot.toc`, so the branch
  checked out decides what both games run. **Don't let CurseForge update, reinstall or uninstall
  Quest Completist while a link is in place.** Reinstalling through it is what broke the link last
  time, and depending on how it clears the folder, it could delete files in the repository.

  It happened again on 2026-10-03: CurseForge's 110.7 update replaced the link with a plain copy,
  deleting the repository's `QuestCompletist/Images` on the way, and in-game tests ran the released
  copy without anyone noticing. The fix was to uninstall Quest Completist in the CurseForge app (safe
  while the folder is a plain copy), then create the link again. **Before every in-game test**, check
  the links and the branch:
  ```powershell
  (Get-Item "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\QuestCompletist").LinkType   # must be Junction
  (Get-Item "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\QuestCompletist").LinkType   # must be Junction
  git -C "C:\Users\alist\RiderProjects\QuestCompletist" status -sb   # the branch under test, no deleted files
  ```

`tools\` only tracks its `*.ps1` scripts. Everything the scripts download or write there (CSV
exports, the API cache, reports) is gitignored and can be regenerated.

## The quest and pin data files

The quests and the map pins live in `data\`, one record per line, with named fields. These are the
master copy: `QuestCompletist\qcQuestData.lua` and `QuestCompletist\qcPinDB.lua` are built from them,
and each starts with a line saying so. `qcQuest.lua` holds only the hand-edited tables (menus,
categories, the zone table, reputation rewards, storylines and so on).

- `data\quests.jsonl`, one quest per line:
  `{"id":176,"name":"WANTED:  \"Hogger\"","level":1,"zone":"Elwynn Forest","category":70,"type":1,"faction":1,"race":64175181,"class":8191,"storyline":566}`.
  `profession`, `holiday`, `covenant`, `storyline` and `prereq` are left out when they're 0.
  `class` is the game's own class mask, 1 shifted left by the class ID less one (Warrior 1,
  Paladin 2, … Monk 512, Druid 1024, Evoker 4096), so masks from Blizzard's API, the client
  tables and CMaNGOS are used as they are; `race` and the other masks are the addon's own bits,
  listed in `qcCore.lua`.
  `prereq` is the quest to do first, or a list of quests that all must be done. A list inside that
  list is a choice, any one of which will do, and a list inside a choice is all of it again:
  `[57115,57116]` needs both, `[[10983,10989,11057]]` any one of the three. A quest the character
  couldn't take, for its faction, race or class, doesn't count: Blizzard's lists name both
  factions' versions of a quest, so the addon counts such a required quest as met, and leaves it out
  of a choice.
- `data\pins.jsonl`, one pin per line:
  `{"map":84,"icon":1,"npc":29611,"name":"King Varian Wrynn","x":26.12,"y":47.32,"quests":[26365]}`.
  `npc` is left out when it's 0, and `name` and `note` when the pin has none.

WoW: Forever's quests and pins are in `data\forever\`, in the same form, and build into
`QuestCompletist\Forever\`. Its importer writes them (step 10), so they're never edited by hand: a
change goes into the importer or its sources, and the next import keeps it. Two more files there
hold what retail keeps in `qcQuest.lua` by hand, and go into Forever's `qcQuest.lua`:
- `data\forever\links.jsonl`, one line for each quest with breadcrumbs or quests it shuts out:
  `{"quest":6383,"breadcrumbs":[235,742,6382]}`, `{"quest":235,"exclusiveWith":[742,6382]}`.
- `data\forever\reputation.jsonl`, one line for each reputation reward:
  `{"quest":189,"faction":87,"amount":-500}`.

`tools\Build-AddonData.ps1` checks the data files and writes the Lua files, for both games. With
`-Check` it writes nothing and only says whether the Lua matches. It names any problem by file and
line, e.g. `quests.jsonl line 3 (id 53665): 'level' is missing`.

In `qcQuestData.lua` a quest's row in `qcQuestDatabase` is `{name, level, category, type, faction,
race, class, storyline}`, with storyline left off when it's 0. Profession, holiday, covenant and
prerequisite, which most quests don't have, are in `qcQuestProfession`, `qcQuestHoliday`,
`qcQuestCovenant` and `qcQuestPrereq`, keyed by quest ID, a list of prerequisites as a Lua table.
The zone text stays in the data file only: the game never reads it.

**Every tool that changes quests or pins does it through the data files** and rebuilds the Lua:
`Apply-AccuracyFixes.ps1`, `Sync-QuestNamesFromApi.ps1`, `Sync-QuestProfessions.ps1`,
`Retype-FlaggedWorldQuests.ps1`, `Retype-ProbeRecurring.ps1`, `File-WeeklyEventQuests.ps1`,
`Place-UncategorisedQuests.ps1`, `Insert-GapQuestEntries.ps1`, `Build-QuestLines.ps1`,
`Sync-QuestPrerequisites.ps1`, `Apply-ClientQuestGivers.ps1`, `Apply-PinNpcIds.ps1`,
`Fill-PinNpcIds.ps1`, `Assemble-PinDB.ps1` and `Remove-DuplicatePinQuests.ps1`.
They take `-DataDir` and `-AddonDir`, and default to the checkout they're in, so a scratch copy for
a trial run needs both folders. Before saving, they check that the Lua still matches the data
files, and stop without changing anything if it doesn't. Commit the data files along with the Lua.
Every other tool reads quests and pins from the data files too, never from the Lua. Some of them
edit tables the data files don't hold (menus, categories, the zone table, reputation rewards),
which stay hand-edited Lua.

**To change a quest or a pin by hand**, edit its line in the data file with a text editor, then
rebuild:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-AddonData.ps1
```

Never edit `qcQuestData.lua` or `qcPinDB.lua` directly: the next build overwrites them, and until
then every tool refuses to save.

## Before a sweep

1. **Find the current builds** at <https://wago.tools/api/builds/latest>: retail is product `wow`,
   and WoW: Forever is `wow_classic_beta` (version 1.60) during its beta. Check which product carries
   Forever after its launch on 4 November 2026.
2. **Pin the builds.** Scripts that take `-Build` should be given their game's current build:
   retail's for steps 1 to 9, Forever's for step 10. The Forever tools default to the beta build
   they were written on, so always pass it. Downloading a table from wago.tools without a build
   number does *not* reliably return the latest build.
2b. **Check the client's tables for changes,** both games, every sweep. Blizzard can change a
   table's columns, or add tables, at a patch, an expansion, or when a game goes from beta to live,
   and the tools read 26 of them (14 for Forever). Run
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\Compare-ClientTables.ps1 -Build <retail build> -ForeverBuild <Forever build>
   ```
   It saves every table name wago.tools has for each build as `tools\client_tables-<build>.txt`,
   lists the tables added and removed since the newest earlier list for that game (quest-related
   names flagged), and compares the column names of every table the tools read with the cached
   copy in `tools\`. A column change exits with 1: check the tool that reads that table, and the
   plan docs, before the sweep goes on. A new table or column that could serve the addon is a
   finding to plan, not just to note. It also compares `qcHolidays` (see [Holidays](#holidays))
   with both games' calendar tables: an ID the client has under one of our holidays' names that
   `qcHolidays` lacks exits with 1 too, and goes into `qcHolidays` before the sweep goes on.
   Baseline on 2026-10-07: retail 12.1.0.69933 had 1,104 tables and Forever 1.60.1.70245 had
   612, with no column changes in the tables read, and every holiday's IDs matched. The first
   systematic review of every table (2026-10-07) is in
   [plans/client-tables-review.md](plans/client-tables-review.md); before it, the tables read
   were chosen as each need came up.

   Then check the game's Lua API the same way:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\Compare-ApiDocs.ps1
   ```
   It downloads the `live` and `forever` branches of Gethe/wow-ui-source, the UI source of retail
   and WoW: Forever, reads Blizzard's generated API documentation with `Read-ApiDocs.lua`, saves
   every function and event as `tools\api_docs-<branch>-<build>.tsv` (the files themselves stay
   in `tools\api_docs\`, for grepping how Blizzard uses a function), and lists what was added or
   removed since the newest earlier list for that branch, with quest-related namespaces flagged.
   It also checks that every function the addon calls, its `C_` calls and the documented globals
   it uses, is still documented with the same arguments and returns: one gone or changed exits
   with 1, so check the code before the sweep goes on. A function one game's documentation lacks
   and the other's has is only reported: `C_SkillInfo.GetSkillLineInfoByID` is Forever's, and the
   code falls back to the character's profession list without it. The documentation leaves out the
   old globals (`GetQuestID`,
   `GetAvailableQuestInfo` and their kind), which it can't check. Baseline on 2026-10-07: live
   12.1.0.69933 had 5,539 functions and 1,782 events, Forever 1.60.1.70245 5,785 and 1,804, and
   the addon's 45 functions were all documented on Forever and 44 on live. The first systematic
   review of the API (2026-10-07) is in [plans/game-api-review.md](plans/game-api-review.md). A
   new function or event that could serve the addon is a finding to plan, as a new table is.
   It ends with the functions the addon calls that one game documents and the other doesn't
   (`C_SkillInfo.GetSkillLineInfoByID`, Forever's), and exits with 1 when one of those turns up on
   the game that lacked it: that game has gained it, so check that the code reads it as its
   fallback did, and share any feature gated on it.
   Which checks each game has, and why the rest differ, is
   [plans/game-parity.md](plans/game-parity.md): a check built for one game goes to both unless a
   game can't support it.
3. **Move the Blizzard API cache aside** so every quest is fetched fresh:
   ```powershell
   Rename-Item tools\quest_api_cache "quest_api_cache.$(Get-Date -Format yyyyMMdd)"
   ```
   The audit reuses whatever is cached, forever. A cached `.json` or `.404` for a quest is never
   fetched again.
4. **Move CMaNGOS's database aside** too, so step 10 downloads its latest dump:
   ```powershell
   Get-Item tools\ClassicDB_*.sql.gz | Rename-Item -NewName { "$($_.Name).$(Get-Date -Format yyyyMMdd)" }
   ```
   The Forever tools take the `ClassicDB_*.sql.gz` already in `tools\`, and only download one when
   there's none.
5. **Get TrinityCore's latest world database** for steps 2b, 2c and 6c. Download the newest
   `TDB_full_*.7z` from [TrinityCore's releases](https://github.com/TrinityCore/TrinityCore/releases),
   extract its `TDB_full_world_*.sql` into `tools\tdb\` with 7-Zip, and move the older one aside.
   Those steps read the newest one there and name it in their summaries.

Run a script with:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\<Script>.ps1 [parameters]
```

Every script works on the checkout it's in by default: its own `tools\`, `data\` and
`QuestCompletist\`. The caches, downloaded tables and `tools\.env` are only in the main checkout,
so a script run from another copy of the repository, such as a worktree, needs them pointed at the
main checkout's `tools\`: `-ToolsDir` in most scripts, or the input file's own parameter
(`-AuditCsv`, `-CandidatesCsv`) in the two accuracy scripts.

## The sweep

Run the report-only steps first, then make one branch and pull request per kind of change.

| # | Area | Scripts, in order | Edits the addon? |
|---|---|---|---|
| 1 | Faction, race and class | `Audit-QuestAccuracy.ps1` → `Categorize-AuditDiscrepancies.ps1` → `Apply-AccuracyFixes.ps1 -Field <field>` | Only the last one |
| 1b | Second source for race and class, and the task-quest tables 1d and 2c read | `Get-WagoQuestRequirements.ps1 -Refresh` | No |
| 1c | Quest names | `Sync-QuestNamesFromApi.ps1 -WhatIf`, then without `-WhatIf` | Only the last one |
| 1d | Professions of task quests | `Sync-QuestProfessions.ps1 -WhatIf`, then without `-WhatIf` | Only the last one |
| 2 | Reputation rewards | `Compare-QuestReputation.ps1` → `Apply-ReputationBackfill.ps1` | Only the last one |
| 2b | Breadcrumbs, "only one of these", renown, prerequisites and the other tables kept by hand | `Audit-QuestTables.ps1` | No |
| 2c | Prerequisites from Blizzard's API, the client's task quests and TrinityCore | `Sync-QuestPrerequisites.ps1 -WhatIf`, then without `-WhatIf` | Only the last one |
| 3 | Quest types | `Retype-FlaggedWorldQuests.ps1`, `Retype-ProbeRecurring.ps1` | Yes |
| 4 | Storylines | `Build-QuestLines.ps1 -Build <retail build> -Refresh` | Yes |
| 5 | Zone table and category names from the client | `Build-CategoryUiMapIDs.ps1 -Refresh` → `Add-ZoneTableMaps.ps1` → `Build-CategoryUiMapIDs.ps1` → `Build-CategoryClientNames.ps1 -Refresh` → `Sync-QuestSortNames.ps1 -Refresh` → `Remove-ConvertedLocaleKeys.ps1 -WhatIf` | Yes |
| 6 | Map pins, and quests new to the database | see [the pin pipeline](plans/quest-location-data-pipeline.md) → `Remove-DuplicatePinQuests.ps1`, then `Fetch-GapQuestData.ps1` → `Insert-GapQuestEntries.ps1` → `File-WeeklyEventQuests.ps1` | A candidate file, until you apply it |
| 6c | Quest givers from the client's data and TrinityCore, then NPC IDs for named pins from TrinityCore | `Apply-ClientQuestGivers.ps1 -Refresh -WhatIf`, then without `-WhatIf` → `Fill-PinNpcIds.ps1 -WhatIf`, then without `-WhatIf`; then the pin pipeline again, for the pins they merge | The applying runs |
| 7 | Quests that may no longer be obtainable | `Find-UnavailableQuestCandidates.ps1 -Refresh` | No |
| 8 | Dungeons and raids against the Dungeon Journal | `Audit-DungeonCategories.ps1 -Refresh` | No |
| 9 | Quests and pins nothing can display | `Test-QuestReachability.lua`, after every step that edits the addon | No |
| 10 | WoW: Forever's quests and pins | the recorder's notes and [the Forever probe](#in-the-game) → `Read-ForeverQuestCache.ps1` → `Import-ForeverData.ps1` → `Build-ForeverMenu.ps1` → `Remove-ConvertedLocaleKeys.ps1 -WhatIf` → `Build-AddonData.ps1` → `Test-QuestReachability.lua` with Forever's TOC | Yes |

Steps 1 to 9 are retail's. Blizzard's API has no Forever data, so Forever has a step of its own,
which rebuilds its data from the game, the client's tables and CMaNGOS's database. It gets its own
pull request, like each kind of retail change. Which of retail's checks Forever has an equivalent
of, which it lacks and why, is in [plans/game-parity.md](plans/game-parity.md).

After each step that edits the addon, bring the data files up to date as described in
[The quest and pin data files](#the-quest-and-pin-data-files).

Step 3 reads the saved results of the in-game probe, so it needs nothing from the game on an
ordinary sweep. When step 6 adds quests, those have never been probed. Run
[the probe](#in-the-game) after step 6, then step 3 again. Step 10 always takes in the Forever
probe's recorder notes, but only needs a new probe run when Forever has a new build, or when the
beta opens higher levels; otherwise the last run's results stand.

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

### 1d. Professions of task quests

`Sync-QuestProfessions.ps1` gives a world quest, bonus objective or calling the profession it needs,
so "Hide Other Profession Quests" hides a Legion Mining world quest from a character without Mining.
The API doesn't serve task quests, so the client says it, in two columns of `QuestV2CliTask` that
agree wherever both speak: the skill the quest asks for, in the expansion's own line of the
profession (its `SkillLine` row names the base profession), and the profession of its quest type
(`QuestInfo`). Run it with `-WhatIf` first.
- **Only a quest with no profession is given one.** A quest of ours that has another, a quest whose
  two columns disagree and a skill line with no bit in `qcProfessionBits` are listed and left.
- **The skill level isn't kept.** It belongs with the skill requirements, which retail doesn't
  fill yet ([plans/game-parity.md](plans/game-parity.md), recommendation 3).

A second run changes nothing. WoW: Forever has no such table, so its professions come from
CMaNGOS in step 10.
### 2. Reputation rewards

`Compare-QuestReputation.ps1` compares `qcQuestReputation` against the API cache from step 1 and
writes `quest_reputation_compare.csv`. Then `Apply-ReputationBackfill.ps1` adds the rewards the API
lists and we don't have, and corrects the ones whose amounts differ from the API's. It leaves a
reward only we list alone and counts it: check those by hand, as the API may simply not list a
reward the game gives. In October 2026 all 11,035 of our rewards matched the API.

### 2b. The tables kept by hand

`Audit-QuestTables.ps1` checks what no other step does:
- in `qcQuest.lua`: the breadcrumbs (`qcBreadcrumbQuests`), the quests that close others once
  they're done (`qcMutuallyExclusive`), the renown requirements, the daily and weekly limits and
  the faction names;
- in `data\quests.jsonl`: the prerequisites.

It needs the API cache from step 1, and writes `tools\quest_table_audit.csv`, one row per finding,
with a count for each kind.

- **Against our own data:**
  - a quest that isn't in `quests.jsonl`, or is flagged unavailable;
  - a daily, weekly or repeatable quest in a breadcrumb or "only one of these" pair, since the
    addon never ticks those;
  - a one-time quest that requires a daily, weekly or repeatable one: the game only knows that one
    is done until the next reset, so the map would hide the quest again;
  - a breadcrumb, or a prerequisite that must be done, for the other faction: the addon counts
    such a prerequisite as met, so it does nothing;
  - a quest listed twice in a table, as Lua keeps only the last line.
- **Against Blizzard's API:** the quests it says a quest requires, and the ones it says close a
  quest (a requirement that they're not done). It names at most 3 required quests, and often leaves
  out the step just before the quest in its storyline, so a quest of ours that's that step isn't
  counted against it.
- **Against the client's tables:** which factions have renown or friendship ranks (The Weaver's
  "Rank 7"), and the factions' English names.
- **Against TrinityCore's database** (the newest `tools\tdb\TDB_full_world_*.sql`), for older
  quests: its breadcrumbs, groups and previous quests. It only speaks for quests it has a row for,
  and has few after Mists of Pandaria. Of the previous quests it offers where we have none, only
  those that are the step just before in the quest's own storyline are listed, as step 2c only
  takes those; the rest are counted. Its groups of which only one can be done are counted, not
  listed: it also groups quests one character can do all of, such as Darrowshire's three in the
  Eastern Plaguelands.

Review the new findings, and fix the data where it's wrong. For a finding that's right as it is,
add a `KEEP` row to `docs\plans\quest-table-decisions.csv`: `Kind`, `Quest` and `Other` copied from
the report, then `Decision` and `Reason`. Later runs mark it kept and count only the rest as new. The
first run's findings and what was decided are in [plans/quest-table-checks.md](plans/quest-table-checks.md).

### 2c. Prerequisites

`Sync-QuestPrerequisites.ps1` sets the prerequisites step 2b checks, from the same sources. Run it
with `-WhatIf` first to see what it would change.
- **Where Blizzard's API names required quests,** its list replaces ours: an AND of them, with an OR
  as a choice. As the API names at most 3, a quest of ours it leaves out stays when it's the step
  just before in the quest's storyline.
- **Where the API is silent on a task quest,** the client's own tables are taken: the quests its
  `QuestV2CliTask` row says must be done and those its `PlayerCondition` says were turned in, both
  required, read with the logic fields the game gives them (and, or, and a quest that mustn't be
  done, which is no prerequisite). They replace ours, except for the step just before in the
  quest's storyline, as with the API's list. Most of what the client gates a task quest on is a
  hidden tracking quest we hold no data for, with no name to show: it's left out of the list,
  or the whole choice it's in. The tables are those step 1b refreshes.
- **Where the API is silent and we have none,** TrinityCore's previous quest is taken when it's the
  step just before in the quest's storyline (the client's `QuestLineXQuest` for `-Build`).
- **A one-time quest never gets a daily, weekly or repeatable requirement,** and a choice that
  offers one is left out whole. A recurring quest keeps one, as in a chain of world quests, which
  the game knows within the day or week.
- **A requirement that would make two quests each require the other** is left out, and listed.

A second run changes nothing, so a sweep only shows what Blizzard or TrinityCore changed.

### 3. Quest types

Types are a bitmask. The ones that matter here:

| Type | Meaning |
|---|---|
| 1 | normal, one-time |
| 2 | repeatable |
| 4 | daily |
| 128 | world quest **or** weekly. The weekly reset clears both. |

Type 0 (no type) acts as 1. The original data also had a weekly type, 16, which the addon treats
as one-time; since October 2026 no quest has it.

- `Retype-FlaggedWorldQuests.ps1` moves 128 to daily or repeatable when the API flags the quest that
  way and it isn't a world quest.
- `Retype-ProbeRecurring.ps1` moves a quest typed one-time (1, 0 or 16) to a recurring type, from
  the in-game probe (below) and the API's flags. The API's flag chooses daily, 128 or repeatable,
  unless the probe's answer contradicts it, and a quest the probe says recurs that the API doesn't
  flag daily or weekly gets 128. The table is in the script's header.
  - **A quest the server knows that the client's `QuestV2` table leaves out becomes repeatable.**
    That table lists only quests the game can record as done.
  - **Inputs:** the probe's saved results in `tools\quest_type_probe_results.lua`, which only cover
    quests that were in the database when the probe ran, and `QuestV2` for the probe's build. The
    script downloads that table when it isn't there.

What's been checked and decided, and the quests still open, are in
[plans/quest-types.md](plans/quest-types.md).

Both only pick up new cases, so they're safe to rerun. Before changing any type by hand, know that
neither the API nor the game proves a quest is one-time:
- The API leaves many weeklies unflagged, such as Shadowlands' "Trading Favors" and Dragonflight's
  profession weeklies.
- The game calls paragon caches, emissary bounties, Special Assignments and "Conquest's Reward"
  *Normal*, even though they recur.
- `QuestV2` comes closest. A quest it lists isn't repeatable. If the API also flags nothing and the
  game says Normal, the quest is one-time, unless it recurs by a system of its own, like emissary
  bounties or Special Assignments.

### 4. Storylines

`Build-QuestLines.ps1` regenerates each quest's `storyline` and the `qcQuestLines` table
from Blizzard's own questline tables. It skips internal questlines ("8.0 Professions - … - SCS",
"[DNT] …"). It stores each storyline's quests in Blizzard's order.

### 5. Zone table and category names from the client

`Build-CategoryUiMapIDs.ps1 -Refresh` downloads the game's map table (`UiMap.csv`) for the pinned
build and maps quest categories to game maps, so the client supplies their names in every language.

Then run `Add-ZoneTableMaps.ps1 -WhatIf`, then without `-WhatIf`. It adds the maps missing from
`qcAreaIDToCategoryID`, which turns the map you're on into a quest category. The addon switches the
quest list through it when you enter a zone, and `Place-UncategorisedQuests.ps1` files quests by it.
Nothing else maintains it, so new dungeons and new versions of a zone's map drift out of it. A map
is added when a category is named by it, when it has the same name and parent as a map already
listed (a dungeon's other floors), when it's in the client's map group (`UiMapGroupMember`, the
floor selector's list, downloaded for `-Build`) of a map already listed (floors with names of their
own, such as Black Temple's Karabor Sewers), or when its name is exactly that of one category with
no map yet. It never adds continent-level maps, never gives a map to a category with no quests,
and never changes an existing entry. A floor it leaves out because its name is another category's
(The Stockade, in Stormwind City's group) is listed, for adding by hand if that's wrong. Run
`Build-CategoryUiMapIDs.ps1` again afterwards, without `-Refresh`, so it sees the new maps.

Then run `Build-CategoryClientNames.ps1 -Refresh`. It names the categories that aren't maps from
other client tables: classes, professions, covenants, dungeons, achievement categories (the world
events), factions, Blizzard's UI text and area names. A rerun with no client changes leaves
`qcQuest.lua` byte-identical. Names we made up ("Bfa Unknown", "Garrison Support") stay ours.
The same tool writes `clientName` into `qcMenu.lua` for the menu headings it lists (continents,
expansions, "Battlegrounds", "Professions" and so on), chosen by hand.

Then run `Sync-QuestSortNames.ps1 -Build <retail build> -ForeverBuild <Forever build> -Refresh`,
with `-WhatIf` first. The game can't be asked at runtime for the name of a quest log heading, so a
category filed under one ("Timerunning", "Garrison Support", the War Campaigns, Forever's "Lunar
Festival") keeps its key in the `Localization` files, and this tool writes the client's own name
for the heading, in each language, into those keys from the `QuestSort` table, downloaded per
language. The headings are chosen by hand in the script, only where the heading's English is
exactly the category's name; it stops if Blizzard renames a heading or we a category. Both games'
headings are covered, retail's text first where both have one ("Seasonal"). A rerun with no client
changes leaves every file byte-identical. Then run `Test-Localization.lua` (below).

`Remove-ConvertedLocaleKeys.ps1` then deletes the text the client has made redundant, in both
games. Run it with `-WhatIf` first.
- The key of a category the client names goes from every locale file, unless code or a heading
  uses it. Should the game ever return no name, the category's English name shows.
- A heading the client names keeps its English, as the fallback, but not its translations.
- A category's entry in `qcMenu.lua` loses its label: the menu names categories through
  `qcCategoryName`, so the label never shows. An indented entry keeps its indent, as
  `text="   "`.

### 6. Map pins

The pipeline builds `tools\pins_candidate.jsonl` for review, in the same form as `data\pins.jsonl`,
so the two compare line by line. It never changes the pins without `-Apply`, and existing pins
shouldn't move without a reason. The steps are in
[plans/quest-location-data-pipeline.md](plans/quest-location-data-pipeline.md). Download
`QuestPOIPoint` and `UiMapAssignment` for the pinned build first; `QuestPOIBlob` comes with step 1b.
Then run `Build-QuestLocationData.ps1`, `Parse-ExistingPinDB.ps1`, `Join-LocationsWithExisting.ps1`
and `Assemble-PinDB.ps1`, in that order.

`Join-LocationsWithExisting.ps1` reports how far each quest's start in the fresh data is from its
nearest existing pin. Treat that as a finding to review. When you're ready to take the new data,
run `Assemble-PinDB.ps1 -Apply`, which saves the candidate as `data\pins.jsonl` and rebuilds
`QuestCompletist\qcPinDB.lua`.

A pin goes where its quest starts: `Build-QuestLocationData.ps1` takes each quest's point 32 in
`QuestPOIBlob` and, for the few quests with none, its point -1. Point -1 is the quest's own point,
where it starts and ends when that is one place and its turn-in when it ends elsewhere; taken as the
pin, it put about 7,600 quests at the hand-in ([plans/quest-location-data-pipeline.md](plans/quest-location-data-pipeline.md),
"October 2026, pins at the start"). Point 32 on a parent map of another point 32 of the quest (a
continent over a zone) is left out. A quest with a point 32 and no point -1 is placed only when it
has a pin already (534 do): it moves that pin to its start, and giving pins to the others is a step
of its own. The tool needs `UiMap.csv` as well as the tables above (step 5 downloads it).

Run the retail map pass each retail sweep too ([In the game](#in-the-game), step 4b). Its offers
are the game's own start positions, to compare with the pins: `tools\Report-MapOffers.lua` lists the
quests whose pin is far from, or on another map than, the game's position. The 439 offers of the first
run were within 10 yards of point 32; the pins are now within 1.5 points of 242 of them and more than
5 points from 1.

- An NPC's quests share a pin only where they start within 1.5 map points of each other (3 until
  October 2026, when the user chose that a quest with a start point in the client's data keeps it
  rather than joining its giver's pin up to 3 points away; see the pipeline plan, "October 2026,
  after the NPC IDs").
- A pin that lands within 1.5 points of an existing one keeps the existing coordinates, and its note.
  Notes that find no pin are listed. Two groups of one NPC that land on the same coordinates this
  way become one pin, so a rebuild leaves no two pins of an NPC closer than 1.5 points.
- Pins are written in a fixed order.

With no real changes, a rerun leaves `data\pins.jsonl` and `qcPinDB.lua` byte-identical; the
September 30 locations were last applied in October 2026 (see the pipeline plan, "October 2026
rebuild"). So whatever a rerun changes comes from new client data or a change made since, and is
for review before `-Apply`.

After `-Apply`, run `Apply-PinNpcIds.ps1 -WhatIf`. A row in `pin-npc-id-decisions.csv` whose pin
the rebuild merged into another matches no pin, and stops that tool. Point the row at the pin that
took its quests, or delete it if that pin has a row of its own or already has the row's NewId.

It works the other way too. When `Apply-PinNpcIds.ps1` or `Fill-PinNpcIds.ps1` gives a pin the ID
of another pin of that NPC within 1.5 points, the next rebuild merges the two, and a quest of a
now-known NPC that the client starts 1.5 points or more from its pin gets a pin of its own there.
So after setting IDs, rerun the pipeline: apply what it changes, then check the rows again.

`Apply-ClientQuestGivers.ps1` (step 6c, first) takes quest givers from the client's own data,
which names one for every quest whose reward has an appearance the collections can show
(`CollectableSourceQuestSparse`, about 2,000 quests; see
[plans/client-tables-review.md](plans/client-tables-review.md)): the giver's creature ID and each
of its spawns. Blizzard's data over TrinityCore's wherever both speak.
- **A quest on a pin whose NPC is another character moves to its giver's pin** when a spawn of the
  giver stands within 1.5 map points of the pin. The same name under another creature ID is the
  same character, and counts as agreeing. The pipeline took each pin's NPC from a neighbour of the
  spot, so the quests of several NPCs standing together often shared one pin; the quest goes to
  an existing pin of its giver within 1.5 points, or to a new one at the old pin's place, and a
  pin left with no quest goes. A quest the client's table doesn't list moves on TrinityCore's word
  when it lists a starter other than the pin's NPC and one stands within 1.5 points (by its own
  spawns, or the client's for a character of that name, as TrinityCore has few after Mists of
  Pandaria).
- **A pin with no NPC ID takes the giver** when a spawn stands within 3 map points of it and
  TrinityCore names no other starter, with the giver's name from TrinityCore's database if the pin
  has none.
- **A quest with no pin gets one** at the giver's spawn, on the smallest zone map that holds it,
  joining a pin of that giver within 1.5 points.
- **A giver farther than that is listed, not acted on.** The pins stand at the client's start
  points, so a giver farther from its pin is one of several places the character stands, or the
  quest is one of the few with no start point, whose pin stays at its turn-in
  ([plans/quest-location-data-pipeline.md](plans/quest-location-data-pipeline.md), "October 2026, pins
  at the start").

The report is `tools\client-giver-report.txt`. A listed case that was looked at and stays goes into
`docs\plans\pin-giver-decisions.csv` as a `KEEP` row (`Quest`, the `Map`, `X` and `Y` of its pin, a
`Reason`); later runs mark it kept and count only the new ones. `MOVE` gives the quest on that pin
to the NPC in `NpcId`, and `FILL` gives a pin with no NPC that NPC, for the cases the rules don't
reach. Run it with `-WhatIf` first (`-Refresh` downloads the table again for the build). A second
run changes nothing; a new build, or new pins from step 6, may give more.

`Fill-PinNpcIds.ps1` (step 6c, second) gives a pin that has a name and no NPC ID the ID of the
creature of exactly that name that starts one of its quests in TrinityCore's database (step 5
under "Before a sweep"), so the game names it in the player's language. It leaves a pin whose
quests start at objects or items, or at a creature of another name, and lists those in
`tools\pin-npc-id-report.txt` for a lookup by hand through `pin-npc-id-decisions.csv`. Run it with
`-WhatIf` first. A second run changes nothing; a newer database or new pins from step 6 may fill
more.

After any change to the pins, run `Remove-DuplicatePinQuests.ps1 -WhatIf`, then without `-WhatIf`
if it lists anything. It takes a quest off a pin when a pin with the same giver name within 3 map
points has it too, which would list it twice in one tooltip or show it on two pins side by side.
Where the game has a start point for the quest, the quest stays on the pin nearest it; otherwise,
of pins within half a point of each other, it stays on one. Pins further apart, with no start point
to choose between them, are only listed: a character in a phased story often stands in two places
(Captain Danuvin at Sentinel Hill). A rebuild from clean pins creates no duplicates, but renaming
pins can, as two pins then share a name. It says which rows of `pin-npc-id-decisions.csv` belong to
pins it removed; delete them, or `Apply-PinNpcIds.ps1` stops.

Quests that appear in the pin data but are missing from the database are fetched with
`Fetch-GapQuestData.ps1` and added with `Insert-GapQuestEntries.ps1`. Run
`Assemble-PinDB.ps1 -Apply` before inserting, because the inserter uses the new pins. The fetch
keeps each API response in `tools\quest_api_cache`, and the inserter refuses any quest that's
already in the database.

The inserter then files the new quests itself, by running `Place-UncategorisedQuests.ps1` on the
same data. It lists any new quest it couldn't place; those stay in category 0, Uncategorized. New
quests go at the end of `data\quests.jsonl`. Like the other scripts that write, both take `-DataDir`
and `-AddonDir`, so they can run against a scratch copy.

`Place-UncategorisedQuests.ps1` also works on its own, on every quest without a category or in a
category that isn't defined. Run it with `-WhatIf` first. It files each quest by the first of these
that gives an answer:
1. a name of the form "<category>: …" ("Prey: Anguish Island")
2. its Blizzard API area. When two of our categories share the area's name (the old and the
   Midnight Eversong Woods), the map its pin is on chooses between them; failing that, the area's
   number does: the category every other filed quest of that area is in, if at least 3 are
3. the zone that contains that area on Blizzard's map
4. the map its pin is on
5. its own zone text
6. the zone above its pin's map, when that map has no category itself (Naigtal → Voidstorm)
7. its map points in the game's own quest data (`QuestPOIBlob.csv`), when they all point to one
   category
8. its storyline, when the filed quests in it all agree and at least half of it is filed

`-Explain` writes `tools\uncategorised_quests.csv`: each quest it placed, with the rule, and each
quest it couldn't, with what's missing. The summary names the maps that have pins but no category,
which usually means `qcAreaIDToCategoryID` lacks them.

It never files a quest in a category that no menu entry reaches. A quest in such a category can
still be found by search, but not by browsing. After adding categories, check every category that
holds quests has an entry in `qcMenu.lua`.

`-Refile 1050` also files the quests in the catch-all category "Legion Uncategorized". For those,
and for category 0, it adds a hand-written list in the script that maps the quest's zone text
("Death Knight Campaign", "Time Rifts") to a category. What's left in the catch-alls has nothing to go on.

`-Refile 123` did the same for "Legendary" in October 2026, as its quests all belong to zones, like
Forever's: the pins placed 41 and the other 17 were placed by hand (see
[plans/data-cleanup.md](plans/data-cleanup.md)). Check what a refile files by name: the prefix rule
put "Hunter: Hunted", a quest for every class, under Hunter. Then run `Remove-EmptyMenuEntries.ps1`,
and `Build-CategoryClientNames.ps1` (step 5), which drops the name of a category the refile emptied.

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

`Find-UnavailableQuestCandidates.ps1` gathers evidence per quest from the API, the client's tables,
our pins and the type probe's saved results (whether the server knows the quest). It's a report
only; see [plans/unavailable-quests.md](plans/unavailable-quests.md). Its summary counts the quests
that have no sign of being live and no decision yet: those are the ones to review, in groups, with
the user.

The quests the addon hides as unavailable are the FLAG rows of
`docs/plans/unavailable-quest-decisions.csv`. A quest reviewed and left shown gets a KEEP row, with
the evidence, so later sweeps don't raise it again. After changing that file, run
`Build-UnavailableQuests.ps1` to regenerate `qcUnavailableQuests.lua`; don't edit the Lua file by
hand. Before flagging a quest as gone from the client, check two things:
- **That the server doesn't know it either** (`ServerKnows` 0 in the finder's CSV). `QuestV2`
  never lists repeatable quests, so missing from it proves nothing on its own; phase 1 got this
  wrong for 148 quests.
- **That it's missing from the latest PTR build's `QuestV2` as well as retail's**: a quest missing
  from retail may be upcoming content.

Players who accept or turn in a flagged quest get a chat message, and the quest is recorded in their
`qcFlaggedButSeen` saved variable. Unflag anything reported that way.

### 8. Dungeons and raids against the Dungeon Journal

`Audit-DungeonCategories.ps1 -Refresh` checks every dungeon and raid in the game's Dungeon Journal,
expansion by expansion. It's a report only, written to `tools\dungeon_audit.csv`, with the quests it
finds filed elsewhere in `tools\dungeon_audit_quests.csv`. For each instance it reports:
- a category that the game would show under a name that isn't exactly the journal's. Case counts,
  and the name checked is the one the game shows (from a map, the journal or an area), not our own
  string;
- a category missing from the menu, or not under Dungeons & Raids in the instance's expansion;
- quests tied to the instance and filed elsewhere. A quest is tied by a name "<instance>: …", its API
  area, or our zone text.

After a new expansion or patch it's the check that finds dungeons and raids with no category yet.
Some quests it reports are filed elsewhere on purpose and stay where they are: class and profession
quests that happen to name a dungeon, quests in a hub (Ahn'Qiraj, Auchindoun, Caverns of Time,
Coilfang Reservoir, the Burning Crusade Hellfire Citadel, Tempest Keep), Return to Karazhan quests
the API calls Karazhan, and lead-in quests handed out in a city or zone.

### 9. Quests and pins nothing can display

`Test-QuestReachability.lua` is the one Lua tool. It loads the addon with stand-ins for the WoW API
and runs the real quest list filter and map pin code for every race, faction, class, covenant and
holiday, so it can't drift from the addon's own logic. It takes about 25 seconds:

```powershell
& "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-QuestReachability.lua
```

It writes `tools\reachability-report.txt`, a report only, listing:
- Lua errors the addon raises. One bad value can stop a whole map's pins from drawing.
- Quests and pins that never show, even with every filter off.
- Quests and pins that every possible character is denied with the character filters on (faction,
  race/class, profession, covenant, seasonal, no-data, requirements-not-met), and which filter
  hides each one. This is where contradictory data turns up, such as an Alliance quest whose race
  mask only holds Horde races.
- Pins of events the calendar doesn't show, such as the Scourge Invasion, which the seasonal filter
  hides from everyone, as it should. Retail has none.
- Quests in categories the list can't browse to, pin maps missing from `tools\UiMap.csv`, and
  holiday values that aren't in `qcHolidays`.

It assumes best-case progress: max level, prerequisites done, max renown, every profession. The
quest search finds every quest by name whatever this reports. Some results are expected. Pins whose
quests aren't in the database stay hidden while "hide quests with no data" is on. A map missing
from `UiMap.csv` can't be opened on retail; a newer build than the downloaded one may add it.

This checks retail's files. Step 10 runs it on Forever's.

### 10. WoW: Forever

The Forever version loads through `QuestCompletist_Camelot.toc`, with the shared code and its own
files in `QuestCompletist\Forever\`. Its plan, with what each run so far found, is
[plans/forever.md](plans/forever.md). Run these in order, with the main checkout's `tools\` as
`-ToolsDir` and Forever's build as `-Build`:

1. **The recorder's notes, every time.** Copy the probe's saved variables, `QCForeverProbe.lua`,
   from the Forever client into the newest `tools\forever_probe_<build number>\` (see
   [In the game](#in-the-game), step 5). The recorder adds to that file whenever you play, so this
   brings in the quest givers you've met since the last sweep. Log out or `/reload` first, so the
   game has written it.
2. **The probe**, when Forever has a new build, the beta opens higher levels, or the probe's quest
   list has grown: see [In the game](#in-the-game). Otherwise the last run's results stand. Every
   probe run includes the map pass (step 4b there), and the reader's totals are compared with the
   last run's in [game-api-review.md](plans/game-api-review.md), "Map-offers probe": on build
   70245, no quest offers, 16 points of interest, no events, no dungeon entrances and no level
   ranges. A rise in any of them is a finding to plan, as a new client table is (step 2b under
   "Before a sweep"): offers would become start points for quests with no giver.
3. `Read-ForeverQuestCache.ps1 -Build <build>` reads the probe's copy of the game's quest cache into
   `tools\forever_quest_cache_<build>.jsonl`. If a single record doesn't read exactly, it writes
   nothing: Blizzard has changed the record's layout, and the reader needs updating.
4. `Import-ForeverData.ps1 -Build <build>` writes `data\forever\quests.jsonl`, `pins.jsonl`,
   `links.jsonl`, `reputation.jsonl` and `skills.jsonl`, and the review list,
   `tools\forever_import_review.csv`. It downloads the client tables and the CMaNGOS dump it doesn't
   have. Compare its summary with the last run's in the plan, and look through the review list for
   new rows: quests the game hasn't confirmed, quests with no known giver or no pin, and places
   where CMaNGOS and our old Classic pins disagree.
   Breadcrumbs and the groups of quests of which only one can be done come from CMaNGOS, without
   recurring quests. Reputation comes from the game's records only: CMaNGOS's amounts are mostly The
   Burning Crusade's, larger than Classic's. The summary counts the quests the game hasn't answered
   that reward reputation in CMaNGOS; they get theirs once it answers.
   The profession a quest needs, and the skill level in it, come from CMaNGOS too: the game's
   records only say what skill a quest rewards. The summary's "Skills:" line counts them, 141
   quests, 102 of them with a level above 1, in October 2026.
   The client's `QuestV2` isn't a list of every quest. It lists the quests the game records as
   completed, so it leaves out repeatable ones. The importer keeps CMaNGOS's repeatable quests
   without it; any other CMaNGOS quest it lacks comes in once the probe gets an answer for it. The
   review list names each kept quest `QuestV2` lacks. A quest `QuestV2` lacks that the beta refused
   at level 1 to 35, where it answers nearly everything, is left out until the server answers it.
   A quest with no giver on a map gets a pin at its start point in the client's tables, when it has
   one. The summary counts those start points, and the quest records that name their giver. Both
   are nearly empty in Forever so far, so a rise means Blizzard has filled in more.
   A quest whose givers, NPCs and objects, all stand only during one of CMaNGOS's game events gets
   that event's holiday, so its pins follow the calendar. Events with no holiday of their own go by
   their description: the Darkmoon Faire's building days, the fishing contest's announcers and
   judges, and the Scourge Invasion and Ahn'Qiraj War Effort, which the calendar doesn't show, so
   their quests stay off the map. Recurring quests keep their type: a repeatable holiday quest is
   repeatable, as on retail.
   A giver no source has, like those of most of Forever's new quests, can be looked up by hand on
   Wowhead's Forever pages and added to `docs\plans\forever-quest-givers.csv` (quest, NPC, name,
   note). The NPC stands where CMaNGOS or the recorder puts it, and the recorder wins when it saw
   another giver offer the quest. A quest filed under a heading that isn't a place, a race's (Night
   Elf), Treasure Map, Epic or Legendary, goes under a zone instead: the one
   `docs\plans\forever-quest-zones.csv` gives it by hand (quest, zone's `AreaTable` ID, name,
   note), else its pins' zone, else the zone of the NPC CMaNGOS has it handed in to, else
   CMaNGOS's. The review list says which, and flags a listed zone that isn't used. The Commendation
   Signets' turn-ins, which CMaNGOS files under Reputation, go under Ahn'Qiraj War with the rest of
   the war effort: its supply quests give the signets, and its officers take them.
5. `Build-ForeverMenu.ps1 -Build <build>` writes `QuestCompletist\Forever\qcMenu.lua`, `qcQuest.lua`
   and `qcUnavailableQuests.lua`. `qcQuest.lua` takes in `links.jsonl`, `reputation.jsonl` and
   `skills.jsonl`, with the factions' English names from the client's `Faction` table. A new zone
   it can't place goes in its continent's "Other" group; add the zone to the script's region table.
   Categories and headings take the client's names where it has them: areas, classes, professions,
   races and its in-game UI strings (the script's `$headingSources` for headings). It lists the
   categories still named by our own strings: quest log headings such as "Lunar Festival", which
   the game can't be asked for. Each has a key in every `Localization` file, made from its English
   name as for any category, which `Sync-QuestSortNames.ps1` (step 5) fills with the client's
   name for that heading in each language, from its `QuestSort` table; a new heading goes into
   that script's list. The script names any that lack a key. If it names a category our text
   covered, run `Remove-ConvertedLocaleKeys.ps1` (step 5).
6. `Build-AddonData.ps1` builds both games' `qcQuestData.lua` and `qcPinDB.lua`; `-Check` checks
   both.
7. The reachability check (step 9), with Forever's TOC and its client's map table:
   ```powershell
   & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-QuestReachability.lua QuestCompletist tools QuestCompletist_Camelot.toc tools\UiMap-<build>.csv
   ```
   It writes `tools\reachability-report-QuestCompletist_Camelot.txt`. Every count in its summary was
   0 in October 2026, so anything else is new, apart from the 81 pins of events the calendar doesn't
   show: 23 of the Scourge Invasion's and 58 of the Ahn'Qiraj War Effort's.

With the same sources, a rerun writes the same files byte for byte. So whatever changes comes from
the game, the client's tables or CMaNGOS, and is for review before its pull request.

## Text in other languages

Names come from the game in the player's language: quests, NPCs, factions, maps, and the categories
and menu headings of steps 5 and 10. The addon's own text is in
`QuestCompletist\Localization.<language>.lua`.

- `Localization.enUS.lua` has every key in English. Each other file sets the keys it translates,
  and any key it lacks shows in English.
- Text the game already has comes from the game, in its words: "Search" (`SEARCH`), "Search Results"
  (`SPELLBOOK_SEARCH_HEADER_RESULTS`), the quest tooltip's "Storyline" (`QUEST_CLASSIFICATION_QUESTLINE`) and "Campaign"
  (`QUEST_CLASSIFICATION_CAMPAIGN`),
  "Unknown" for a name the game hasn't sent (`UNKNOWN`), and "Categories" and "Filters" on the
  window's buttons. A label's colon comes from `STAT_FORMAT` ("%s:"), which French spaces and
  Chinese writes full-width.
- `-- Needs review` marks a translation no native speaker has checked: most of them, including those
  written in October 2026. `-- Requires localization` marks text still in English.
- A translation must keep the English placeholders (`%d`, `%s`) in the same order: `string.format`
  stops with an error when a translation asks for more values than the code passes.
- To add text, add its key to `Localization.enUS.lua`, use `qcL.KEY` in the code, and add
  translations where you can. Then run the check below.

```powershell
& "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-Localization.lua
```

It loads the files as the game does, for each language, and reports keys the code uses that have
no text, placeholders that differ from the English, and translations that don't format. It also
reports text to remove. `Remove-ConvertedLocaleKeys.ps1` (step 5) removes all but the last:
- an English key nothing uses, in either game: no code names it, no menu heading shows it, and no
  category falls back to it. A category the client can't name falls back to the key made of its
  English name's letters and digits, upper-cased, such as `STRANGLETHORNVALE`; one it names needs
  no key;
- a translation of a key that only headings the client names show;
- a label on a category's entry in a menu, which never shows;
- a key a translation has that English doesn't.

Still in English: the `/qc holidays` output, which is for maintainers, and a handful of retail
category names the game has no name for: our own groupings ("Legion Uncategorized", "Warfront
Contribution"), "Mac'Aree", and three whose quest log heading is worded differently ("Time Rift"
is the game's "Time Rifts", "Weekly Events" its "Weekly Event", and "9.1 Campaign" can't be a key).
The 26 retail categories filed under a heading worded exactly as ours, and WoW: Forever's six, take
the game's own names for those headings in every language, through `Sync-QuestSortNames.ps1`
(step 5).

## Holidays

Seasonal quests need no yearly upkeep. The map's seasonal filter asks the game's calendar which
holidays are running, and `qcHolidays` in `qcCore.lua` ties each holiday value in the quest
database to the IDs of the game's Holidays table that its calendar event carries.

`/qc holidays` in game lists what the filter sees: which of the holidays this game's quests have are
running, each one's next dates, and any calendar holiday that isn't tied to a quest. A holiday there
that should match one of ours, under a new ID, means an entry in `qcHolidays` needs that ID adding.
Step 2b of a sweep finds the same offline, from the client's Holidays and HolidayNames tables: for
each entry in `qcHolidays`, every ID the client has under that name in either game, against the
IDs the entry lists. A new holiday with quests needs a new flag, an entry, and its quests' `holiday`
set in `data\quests.jsonl`. Forever's quests get theirs from the importer, through its own table
from Holidays IDs to flags, so add the ID there too and rerun step 10.

Some events aren't on the calendar at all. WoW: Forever's Scourge Invasion and Ahn'Qiraj War Effort
have entries in `qcHolidays` with no IDs, so the seasonal filter always hides their quests on the map;
the quest list still has them. `/qc holidays` says they're not on the calendar, and step 2b that no
row of their names exists. If Blizzard ever adds one to the Holidays table, step 2b reports its ID,
and in game it shows up as a calendar holiday not tied to a quest: add its ID.

The calendar only serves events around the month it's set to, and at login it's set to November
2004. The addon sets it to the current month before reading, as Blizzard's calendar does when it
opens, but leaves it alone while that window is open. If the calendar can't answer, including a month
with no events at all, the last answer stands, and until there is one every seasonal quest is shown.
A day with no events, in a month that has some, means no holiday is running: retail always has some
event on, but WoW: Forever's calendar has empty days. `/qc holidays` steps the calendar through the
next 12 months, then sets it back to the current one.

WoW: Forever's calendar uses Classic's Holidays IDs where they differ from retail's, such as 263 and
264 for the Darkmoon Faire, so an entry in `qcHolidays` can list both games' IDs.

## In the game

Some answers only the game client has.

**Quest-type probe (`/qc typecheck`).** This asks the client whether each quest recurs. It's pull
request #42, which is closed and its branch deleted; GitHub keeps its commits.

Run it after step 6 has added quests, then run step 3 again. On a sweep that adds nothing, the saved
results are enough.

1. Bring the branch back with `git fetch origin pull/42/head:tools/quest-type-probe`, check it out
   and merge `master` into it. The probe walks the branch's own quest database, so quests added
   since the branch was last updated aren't probed.
2. **Restart the game fully**. The probe adds a file to the TOC, and a `/reload` doesn't pick that
   up.
3. Type `/qc typecheck`. It loads every quest from the server a few at a time, which takes about two
   hours. `/qc typecheck stop` pauses it, and running it again resumes. Its progress is kept across
   `/reload`s and logouts.
4. When it says it has finished, `/reload`.
5. **Before switching branches**, copy
   `C:\Program Files (x86)\World of Warcraft\_retail_\WTF\Account\<ACCOUNT>\SavedVariables\QuestCompletist.lua`
   to `tools\quest_type_probe_results.lua`. Once the probe isn't in the TOC any more, WoW drops its
   results from that file the next time it saves.

`Retype-ProbeRecurring.ps1` reads that copy.

**Forever probe (`/qcprobe`).** A small addon of its own for the Forever client. It asks the server
about every quest in the client's `QuestV2` and every CMaNGOS quest `QuestV2` lacks, as it leaves out
repeatable quests. It names the quest givers, and records quest givers while you play. Its map pass
asks every map for the quest offers, points of interest, events, quest hubs and dungeon entrances
the game lists ([game-api-review.md](plans/game-api-review.md), recommendation 3).
It's pull request #139, which stays open and isn't for merging; its files are in
`tools\ForeverProbe\` on the branch `tools/forever-probe`. Step 10 reads what it gathers.

1. The first time, check the branch out into a folder of its own beside the repository, so the main
   checkout, which both games load the addon from, stays where it is:
   ```powershell
   git fetch origin tools/forever-probe
   git worktree add ..\QuestCompletist-probe origin/tools/forever-probe
   ```
2. For a new build, rebuild the probe's lists of quests (the client's `QuestV2`, and the CMaNGOS
   quests it lacks) and of NPCs:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File ..\QuestCompletist-probe\tools\ForeverProbe\Build-ProbeLists.ps1 -Build <build> -ToolsDir tools
   ```
3. Copy `..\QuestCompletist-probe\tools\ForeverProbe\QCForeverProbe` into
   `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\`, replacing any copy
   there, and restart the game fully.
4. Type `/qcprobe quests`. It asks about every quest that hasn't answered on this build, 4 at a
   time; the first run's 6,609 took about 10 minutes on the beta, and the list is now 7,319 long.
   Then `/qcprobe npcs`, outside any instance,
   as instances hide names. `/qcprobe status` says what's been gathered.
4b. Type `/qcprobe maps`. It asks the server for each of the client's maps in turn (60 on Forever)
   and waits 2 seconds for each answer, so a run takes a minute or two; `/qcprobe maps 1` waits 1
   second. One run is enough. The results note the experience preset chosen once at Forever's login
   screen, Classic or Enhanced (Blizzard's code calls the second Modern): a starting-settings
   choice, whose Classic option turns the quest points of interest on the map off: the map
   filter's "Quest Objectives" entry, the `questPOI` setting, which the results note. The first
   run, on beta build 70245 (7 October 2026), had it on and found no offers on any map
   (game-api-review.md, "Map-offers probe: first run"). Run it with every probe run all the same:
   a check stays in the sweep while it finds nothing, as the client's files and the game's API can
   start serving more at any build (decided 7 October 2026), and a change in its totals is a
   finding to plan. It works on retail too, and the retail sweep takes it as well: copy the folder
   into `_retail_`'s AddOns and type `/qcprobe maps 1`. Retail's 1,961 maps took five minutes
   (7 October 2026). Read it with `tools\Report-MapOffers.lua <saved variables> QuestCompletist` and
   compare the totals with the baseline in game-api-review.md, "Map-offers probe: retail run"; the
   offers and log quests depend on the character, so use a similar one.
5. Log out fully, so the game writes the results and its caches. Then copy these from
   `C:\Program Files (x86)\World of Warcraft\_classic_beta_\` into
   `tools\forever_probe_<build number>\` (`forever_probe_70205` for build 1.60.1.70205):
   - `Cache\WDB\enUS\questcache.wdb` and `creaturecache.wdb`;
   - `WTF\Account\<ACCOUNT>\SavedVariables\QCForeverProbe.lua`.

After Forever's launch, use its live client's folder in place of `_classic_beta_`.

A map pass is read with `tools\Report-MapOffers.lua`, which prints each map's offers, with how far
each is from the quest's pin, and the points of interest, events, hubs and entrances, and writes
the rows as a TSV. Give `QuestCompletist` instead of `QuestCompletist\Forever` for a retail file:
```powershell
& "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Report-MapOffers.lua tools\forever_probe_<build number>\QCForeverProbe.lua QuestCompletist\Forever tools\map_offers_<build number>.tsv
```

Leave the probe installed while you play Forever. Its recorder notes which quests each NPC or object
offers and where it stands. For most of Forever's new quests that's the only source of where they
start, so step 10 copies its file on every sweep.

## Checking a change before its pull request

```powershell
& "C:\Program Files (x86)\Lua\5.1\luac.exe" -p (Get-ChildItem QuestCompletist\*.lua, QuestCompletist\Forever\*.lua).FullName
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-AddonData.ps1 -Check
git diff --stat
```

- The syntax check must be silent. If it says "main function has more than 200 local variables",
  a file has hit Lua 5.1's limit on locals declared at its top, and WoW wouldn't load it. Each file
  has its own 200: in October 2026, `qcCore.lua` had 20 left, `qcTooltips.lua` 164 and
  `qcMapPins.lua` 144. Code that doesn't need to live in `qcCore.lua` can go in a file of its own,
  as the tooltips and map pins do. Every file gets the addon's own table (`select(2, ...)`), and
  `qcCore.lua` hands those files what they need through it, at its end. A new file goes in both
  TOCs, and the release that ships it tells players to fully close and restart World of Warcraft.
- `Build-AddonData.ps1 -Check` must say all four generated files are up to date, two for each game.
  The last line for each game gives its quest and pin counts, which should only change when quests
  or pins were meant to be added or removed. As of October 2026 they're 35,023 quests and 14,673
  pins for retail, and 5,081 quests and 1,706 pins for Forever.
- The diff should touch only what the change is about. For data changes, check that only the
  intended field moved on each line of the data files.
- The addon's files use Windows (CRLF) line endings. A script that writes them must keep that.
  `.gitattributes` stores `qcQuest.lua`, `qcQuestData.lua`, `qcPinDB.lua` and everything in
  `QuestCompletist\Forever\` exactly as written.
- For filter or data changes, run `Test-QuestReachability.lua` before and after, and compare the
  summaries it prints. A change to the shared code needs it for both games: step 9 for retail,
  step 10 for Forever.
- For changes to the addon's text, run `Test-Localization.lua` (see
  [Text in other languages](#text-in-other-languages)). It must say "No problems".

## One-off scripts

A script written for a one-off fix or migration is deleted once its change is merged, so everything
in `tools\` is safe to run again. Git history keeps the old ones; this lists them and the commit
that deleted each:

```powershell
git log --diff-filter=D --name-only --oneline -- tools
```

## Where the data comes from

| Source | Used for | How |
|---|---|---|
| Blizzard's Game Data API | faction, race, class, reputation, daily/weekly flags, quest names, required quests (retail only) | `Audit-QuestAccuracy.ps1`, cached in `tools\quest_api_cache` |
| The game client's own tables, via [wago.tools](https://wago.tools) | task quests with their professions and prerequisites, questlines, map positions, map names, dungeon journal, faction names and which have renown or friendship ranks; for Forever, which quests exist, its maps, zones, headings, races and factions, its reputation amounts, and the few quest start points it has | CSV exports per build, e.g. `https://wago.tools/db2/QuestLine/csv?build=<build>` |
| The game itself | recurring or one-time, world quest or not; for Forever, each quest's title, level, zone, race limits, recurrence and reputation rewards, and quest givers seen while playing; each map's quest offers, points of interest and events (the probe's map pass) | in-game probes and runtime API calls; Forever's quest cache, read by `Read-ForeverQuestCache.ps1`; `Report-MapOffers.lua` |
| TrinityCore's world database ([TrinityCore](https://github.com/TrinityCore/TrinityCore/releases)) | breadcrumbs, groups of which only one can be done, and previous quests, for older quests; the quest giver's creature ID for a pin that has a name and none | `Audit-QuestTables.ps1`, `Sync-QuestPrerequisites.ps1` and `Fill-PinNpcIds.ps1`, from `tools\tdb\` |
| CMaNGOS's vanilla database ([cmangos/classic-db](https://github.com/cmangos/classic-db)) | WoW: Forever's old-world quests, givers and their spawns, breadcrumbs and quests of which only one can be done | `Import-ForeverData.ps1`, from its `Full_DB` dump |
| [Wowhead](https://www.wowhead.com), by hand | the right NPC for retail pins whose ID was wrong; WoW: Forever quest givers and zones no other source has | looked up by a person: `plans\pin-npc-id-decisions.csv`, read by `Apply-PinNpcIds.ps1`, and `plans\forever-quest-givers.csv` and `plans\forever-quest-zones.csv`, read by `Import-ForeverData.ps1` |
