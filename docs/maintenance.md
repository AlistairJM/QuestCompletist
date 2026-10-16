# Maintaining the quest data

How to refresh and re-check the addon's data after a WoW patch: quests, quest types, reputation
rewards, storylines, category names and map pins, for both games the addon runs on, retail and
WoW: Forever. Everything here is run from the repository root in PowerShell, using the scripts in
`tools/`.

If you're working with Claude Code in this repository, **"do a full sweep"** (or "refresh the data")
runs all of this for you, for both games. It will tell you up front which steps need you in the
game.

Releasing a new version is covered in [releasing.md](releasing.md). What is still open from earlier
sweeps, and the calls kept, are in [plans/open-items.md](plans/open-items.md): read it before a sweep.

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
  `minLevel` is left out when it's the same as `level`, and kept when it's 0 (no minimum).
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
change goes into the importer or its sources, and the next import keeps it. Three more files there
hold what retail keeps in `qcQuest.lua` by hand, and go into Forever's `qcQuest.lua`:
- `data\forever\links.jsonl`, one line for each quest with breadcrumbs or quests it shuts out:
  `{"quest":6383,"breadcrumbs":[235,742,6382]}`, `{"quest":235,"exclusiveWith":[742,6382]}`. A link
  `docs\plans\forever-quest-link-decisions.csv` adds is in, and one it removes is left out (step 10).
- `data\forever\reputation.jsonl`, one line for each reputation reward:
  `{"quest":189,"faction":87,"amount":-500}`.
- `data\forever\skills.jsonl`, one line for each quest that needs a profession, with the skill level
  it needs: `{"quest":715,"skill":171,"level":1}`.

`tools\Build-AddonData.ps1` checks the data files and writes the Lua files, for both games. With
`-Check` it writes nothing and only says whether the Lua matches. It names any problem by file and
line, e.g. `quests.jsonl line 3 (id 53665): 'level' is missing`.

In `qcQuestData.lua` a quest's row in `qcQuestDatabase` is `{name, level, category, type, faction,
race, class, storyline}`, with storyline left off when it's 0. Profession, holiday, covenant, PvP and
prerequisite, which most quests don't have, and the minimum level, where it isn't the row's level,
are in `qcQuestProfession`, `qcQuestHoliday`, `qcQuestCovenant`, `qcQuestPvP`, `qcQuestPrereq` and
`qcQuestMinLevel`, keyed by quest ID, a list of prerequisites as a Lua table.
The zone text stays in the data file only: the game never reads it.

`level` means two things, and the data keeps both. The row's level is the quest's own: the list's
bracket (`[30] Name`), its sort and the low-level filter read it. A level of 0 or below is no level:
the list prints the bare name with no bracket, the low-level filter (the map's too) never counts the
quest as low, and the sort puts it first. `qcQuestMinLevel[questId]` is the level a character needs to
take the quest, and the tooltip's "Requires Level" line, the grey pins and the requirements-not-met
filter read `qcQuestMinLevel[questId] or level`, where 0 or below asks for nothing. The table holds only
the quests whose minimum is not their level, and it keeps a 0 (no minimum); a minimum of 0 or 1 against
a level of 0 or 1 is no difference and gets no entry. Retail's table is filled by
`Apply-QuestMinLevels.ps1` ([step 2g](#2g-minimum-levels)) from Blizzard's data, the API's
`min_character_level` where the API has a record and else the client's level range for the quest's
content tuning, and holds 1,627 of the 35,529 quests (11 October 2026: 1,623 at the first run, and 4 of the 506 task
quests step 6b added). Retail's `level` is not
refreshed: of the 30,066 quests whose API record gives a minimum it equals the API's for 28,477, is a 0
against a 1 for 191 (the same thing), and differed for 1,398, which now have the API's number in the
table; 463 quests no source speaks for, and one whose tuning has a minimum beyond the level cap, keep
what they had, and the 17 on tuning 0 have no entry, so their own level is their gate. Forever's
`level` is the quest's own level, so its table holds 4,202 of its 5,105
quests (14 October 2026). The importer fills it from the game's quest cache, and from CMaNGOS where
the game hasn't answered. The code doesn't ask which game it is on, only whether the table has an
entry.

**Every tool that changes quests or pins does it through the data files** and rebuilds the Lua:
`Apply-AccuracyFixes.ps1`, `Sync-QuestNamesFromApi.ps1`, `Sync-QuestProfessions.ps1`,
`Retype-FlaggedWorldQuests.ps1`, `Retype-ProbeRecurring.ps1`, `File-WeeklyEventQuests.ps1`,
`Place-UncategorisedQuests.ps1`, `Insert-GapQuestEntries.ps1`, `Add-TaskQuests.ps1`, `Build-QuestLines.ps1`,
`Sync-QuestPrerequisites.ps1`, `Apply-QuestMinLevels.ps1`, `Apply-ClientQuestGivers.ps1`, `Apply-PinNpcIds.ps1`,
`Fill-PinNpcIds.ps1`, `Import-RecordedGivers.ps1`, `Assemble-PinDB.ps1` and `Remove-DuplicatePinQuests.ps1`.
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

1. **Check that every source is the newest,** at the start of a sweep and again just before each
   in-game session:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\Get-LatestBuilds.ps1
   ```
   Every change and sweep uses the newest version of every data source: the client's files, the
   in-game probes and the external databases (the user's rule, 9 October 2026). The script compares
   what the checkout holds with what is published, and changes nothing: the installed clients
   (`.build.info`) against wago.tools' newest build of the same product; the probe lists, in the
   checkout and in each game's AddOns folder, and the probe results against the installed client;
   the client tables in `tools\` for the current version of retail live, the retail PTR, Forever's
   beta and Classic Era (a version with no table at all counts as behind for retail live and
   Forever); the `-Build` defaults pinned in scripts; the API docs against Gethe/wow-ui-source;
   CMaNGOS's dump and TrinityCore's TDB; and the Blizzard API cache against the newest live build.
   Each source reads `ok`, `BEHIND`, `none` (nothing held) or `unknown` (could not be reached). It
   exits 1 when anything is behind and 2 when nothing is but a source was unreachable. A `BEHIND`
   is fixed before the sweep goes on: refresh the source and rerun what depends on it.
   - **A client that is behind** is updated through Battle.net, with the game closed, before a
     probe run, or its results are for the build before.
   - **Forever's beta moves about daily** (70245 on 6 October, 70291 on 8, 70338 on 9), which is why
     the check runs again before the game session, and why every result and report names the build
     it was taken on.
   - **Forever's product** is `wow_classic_beta` during its beta, retail's `wow`. After Forever's
     launch on 4 November 2026 find which product carries it in <https://wago.tools/api/builds>
     and edit `$GameProducts` in `tools\LatestBuilds.ps1`.
   - **The retail PTR** is listed by wago.tools under two products, `wowt` and `wowxptr`
     (`$RetailPtrProducts` in `tools\LatestBuilds.ps1`). The check takes the newer of the two products'
     newest builds, by version and then build, and its "retail PTR" row names the product it came from.
     The 12.1.5 PTR was on `wowxptr` (70340 on 12 October 2026). A 12.1.7 PTR, 12.1.7.70424, has been
     on `wowt` since 15 October 2026, and the check missed it while it read `wowxptr` alone (until
     16 October 2026). That build, or a newer one the check names, is `Review-Calendar.ps1`'s
     `-PtrBuild` at the next sweep (step 2h), not 12.1.5's.
   - `Test-LatestBuilds.ps1` checks the script on a made-up game folder and made-up newest versions.
2. **Pin the builds.** Scripts that take `-Build` should be given their game's current build:
   retail's for steps 1 to 9, Forever's for step 10, and both games' for steps 2b and 2h, which read
   both games' tables: `Compare-ClientTables.ps1` takes `-Build` and `-ForeverBuild`, and
   `Review-Calendar.ps1` `-Build`, `-PtrBuild` (the retail PTR's, when there is one: the build item 1's
   "retail PTR" row names) and `-ForeverBuild`.
   The Forever tools (`Read-QuestCache.ps1`,
   `Import-ForeverData.ps1`, `Build-ForeverMenu.ps1`, `Import-RecordedGivers.ps1` and
   `Sync-QuestSortNames.ps1`'s `-ForeverBuild`) take the build of the newest `tools\forever_probe_<revision>`
   results when it is left out, and say which: the importer needs the tables, the quest cache and the
   probe's answers on one build, and the check says when those results are behind the installed client.
   Twelve of retail's tools still carry a build as their `-Build` default (the check counts them under
   "Pinned builds"). The check lists a default only when it is older than the newest build of its own
   version, so a default left on the patch before still reads `ok`: all twelve were on 12.1.0.69933 while
   12.1.5.70391 was live, and the check passed them. So at the sweep for a new patch, change the twelve
   defaults to the new live build
   (`Select-String -Path tools\*.ps1 -Pattern '^\s*\[string\]\$Build = "\d'` lists them: Add-TaskQuests,
   Add-ZoneTableMaps, Apply-ClientQuestGivers, Audit-DungeonCategories, Audit-QuestTables,
   Build-CategoryClientNames, Build-CategoryUiMapIDs, Build-QuestLines, Find-UnavailableQuestCandidates,
   Get-WagoQuestRequirements, Sync-QuestPrerequisites and Sync-QuestSortNames, whose help examples name
   the builds too); between patches, pass the build.
   Downloading a table from wago.tools without a build number does *not* reliably return the latest build.
2b. **Check the client's tables for changes,** both games, every sweep. Blizzard can change a
   table's columns, or add tables, at a patch, an expansion, or when a game goes from beta to live,
   and the tools read 32 of them on retail and 16 on Forever (counted on 11 October 2026; there were 26
   and 14 at the first review). Run
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\Compare-ClientTables.ps1 -Build <retail build> -ForeverBuild <Forever build>
   ```
   It saves every table name wago.tools has for each build as `tools\client_tables-<build>.txt`,
   lists the tables added and removed since the newest earlier list for that game (quest-related
   names flagged), and compares the column names of every table the tools read with the cached
   copy in `tools\`. A column change exits with 1: check the tool that reads that table, and the
   plan docs, before the sweep goes on. Retail's `ContentTuning` is one of them
   (`Apply-QuestMinLevels.ps1` reads four of its columns): the check caches it as
   `ContentTuning-<build>.csv` the first time, and a copy that lacks `MinLevelSquish`,
   `MaxLevelSquish`, `MinLevelScalingOffset` or `MaxLevelScalingOffset` exits with 1 whether or not an
   earlier copy exists. A new table or column that could serve the addon is a
   finding to plan, not just to note. It also compares `qcHolidays` (see [Holidays](#holidays))
   with both games' calendar tables: an ID the client has under one of our holidays' names that
   `qcHolidays` lacks exits with 1 too, and goes into `qcHolidays` before the sweep goes on, as
   does a holiday whose calendar-window filter differs from the one the client's
   `CalendarFilterType` puts it under. Two entries are matched by a name pattern instead of their
   own name (`$HolidayRowPatterns` in `tools\HolidayTables.ps1`, which sweep step 2h shares; see
   [Holidays](#holidays)): WoW's Anniversary by its yearly rows'
   names ("WoW's 22nd Anniversary" and the like) and the Skyriding Cups by the cups' names
   ("Kalimdor Cup" and any other "<Region> Cup"). A row of those names that runs today or later and
   is missing from its entry exits with 1, and its ID goes into the entry; past rows are left out.
   What this check doesn't see, an entry with no date to come, an event no entry covers, or a decision
   whose ground has moved, is sweep step 2h's.
   On 11 October 2026 a run on retail 12.1.0.69933 and Forever 1.60.1.70338 gave no finding: no
   column changes, and of 20 holidays 18 matched and the Scourge Invasion and the Ahn'Qiraj War
   Effort have no row; the 12.1.5 PTR's (70077) calendar tables gave the same holiday result, with
   no 23rd anniversary row yet. On 12 October 2026, with the Skyriding Cups added, the same
   builds and the PTR gave no finding either (of 21 holidays 19 matched), and the cups' pattern
   matched only the six cups' names in their HolidayNames (none in Forever's). Later that day,
   with Dastardly Duos and The Great Gnomeregan Run added (#314), retail and Forever gave no finding
   (of 23 holidays 21 matched, the two new ones by their own names, under the Holidays filter
   their rows give, `CalendarFilterType` 255), nor did the PTR. With Call of the Scarab added
   (#315), the same three builds gave no finding again (of 24 holidays 22 matched on retail and
   Forever, the new one by its own name, row 638, under `CalendarFilterType` 255). Baseline on 2026-10-07: retail 12.1.0.69933 had 1,104 tables and Forever 1.60.1.70245 had
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
   removed since the newest earlier build's list for that branch, with quest-related namespaces
   flagged. It also checks that every function the addon calls, its `C_` calls, the documented
   globals in the script's `-Globals` list and any other documented global its code names, is
   still documented with the same arguments, returns and secrecy flags, and the same for every
   event the addon listens for (any quoted name in its Lua that the documentation lists as an
   event): one gone or changed exits with 1, so check the code before the sweep goes on.
   The lists keep every flag with `Secret` in its name (`SecretArguments`, `SecretReturns`,
   `SecretWhenInCombat`, `SecretPayloads`, a field's `NeverSecret` or `SecretValue` ...) and the
   preconditions the documentation declares (`RequiresUnitAuraAccess` ...), on the function or
   event, on each argument, return and payload field, and on the fields of the structures those
   lead to, so a flag added to what `C_QuestLog.GetInfo` returns shows on `C_QuestLog.GetInfo`. A
   flag that makes a value secret in combat or in an instance can stop the addon reading it, which
   is why a change in the flags of something the addon relies on fails the check as a change of
   shape does. Other functions and events whose flags changed are listed when they are
   quest-related and counted otherwise (`-ListAll` lists them all). The recorder's events
   (`GOSSIP_SHOW` and the `QUEST_*` ones) are documented in both games, so they are what the check
   can see of it; its quest-window globals (`GetNumAvailableQuests`, `GetAvailableQuestInfo`,
   `GetQuestID` and their kind) are in no documentation, and the contents of a structure are not
   compared, only its flags, except for the two the continent icons and the probe read by name,
   `UIMapType` (its `Continent` and `Zone` numbers) and `UiMapDetails` (its `mapID`, `name`, `mapType`,
   `parentMapID` and `flags`), which `-Tables` names: their fields and values are compared as a
   function's shape is, and a change exits with 1. The closing line says what was not checked. A list saved before the
   flags were kept is read again from its folder in `tools\api_docs\`, and a documentation file that
   stopped loading (or started) is named, as what it documents shows as removed (or added).
   A function one game's documentation lacks
   and the other's has is only reported: `C_SkillInfo.GetSkillLineInfoByID` is Forever's, and the
   code falls back to the character's profession list without it. Baseline on 2026-10-09: live
   12.1.0.69933 had 5,655 functions and 1,782 events (3,619 and 124 with secrecy flags), Forever
   1.60.1.70245 5,903 and 1,804 (3,783 and 125); the addon calls 61 functions (60 documented on
   live, 61 on Forever) and listens for 18 events, all documented in both. A function's own
   `Namespace` wins over its system's: `InCombatLockdown` sits in the `C_RestrictedActions` system
   but is the global `InCombatLockdown`. The counts of
   2026-10-07 (5,539 and 5,785 functions) let the methods of different script objects with one name
   overwrite each other. The first systematic
   review of the API (2026-10-07) is in [plans/game-api-review.md](plans/game-api-review.md). A
   new function or event that could serve the addon is a finding to plan, as a new table is.
   It ends with the functions the addon calls that one game documents and the other doesn't
   (`C_SkillInfo.GetSkillLineInfoByID`, Forever's), and exits with 1 when one of those turns up on
   the game that lacked it: that game has gained it, so check that the code reads it as its
   fallback did, and share any feature gated on it. `-SourceDir <folder>` reads `live\` and
   `forever\` (each with `version.txt` and the `*Documentation.lua` files) from a folder instead of
   downloading; `Test-ApiDocs.ps1` checks all of this on made-up documentation.
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
   there's none. `Get-LatestBuilds.ps1` says whether the one held is the newest in Full_DB, which is
   what decides whether to move it aside.
5. **Get TrinityCore's latest world database** for steps 2b, 2c, 2d, 6 and 6c. Download the newest
   `TDB_full_*.7z` from [TrinityCore's releases](https://github.com/TrinityCore/TrinityCore/releases),
   extract its `TDB_full_world_*.sql` into `tools\tdb\` with 7-Zip, and move the older one aside.
   Those steps read the newest one there and name it in their summaries. Step 6 also needs Lua 5.1
   (one-time setup). `Get-LatestBuilds.ps1` says whether a newer release is out.

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
| 0 | Everything is the newest version: clients, probe lists and results, tables, API docs, databases | `Get-LatestBuilds.ps1` ([Before a sweep](#before-a-sweep), item 1) | No |
| 1b | Second source for race and class, and the task-quest tables 1d and 2c read. Run it before step 1 and let it finish: the audit reads its `quest_wago_requirements.csv` when it starts | `Get-WagoQuestRequirements.ps1 -Refresh` | No |
| 1 | Faction, race and class (after step 1b) | `Audit-QuestAccuracy.ps1` → `Categorize-AuditDiscrepancies.ps1` → `Apply-AccuracyFixes.ps1 -Field <field>` | Only the last one |
| 1c | Quest names: the API's titles, else the quest cache's or the task table's (after steps 1, 1b and 2e, whose API cache, task table and quest cache it reads) | `Sync-QuestNamesFromApi.ps1 -WhatIf`, then without `-WhatIf` | Only the last one |
| 1d | Professions (after steps 1b and 2e, whose tables and quest cache it reads): task quests, Blizzard's profession headings, the knowledge a quest rewards, and the hand decisions | `Sync-QuestProfessions.ps1 -WhatIf`, then without `-WhatIf` | Only the last one |
| 2 | Reputation rewards (the cache pass wants step 2e's reader run first) | `Compare-QuestReputation.ps1` → `Apply-ReputationBackfill.ps1` | Only the last one |
| 2b | Breadcrumbs, "only one of these", renown, prerequisites and the other tables kept by hand | `Audit-QuestTables.ps1` | No |
| 2c | Prerequisites from Blizzard's API, the client's task quests, its quest line and campaign conditions, the current campaign's chapters, the quest cache's follow-ups, the map pass's offers, TrinityCore and the decisions kept by hand (after the retail map pass and step 2e) | `Sync-QuestPrerequisites.ps1 -WhatIf`, then without `-WhatIf` | Only the last one |
| 2d | Holiday tags: quests that belong to a holiday and carry none, or the wrong one | `Audit-QuestHolidays.ps1` | No |
| 2e | The retail quest cache, read and checked against Blizzard's data | `Read-QuestCache.ps1 -Build <retail build>` → `Compare-QuestCache.ps1` | No |
| 2i | The PvP tag, from the quest cache's kind of each quest, else the API, the task table and TrinityCore or CMaNGOS, and the hand decisions (after step 2e; Forever's comes from its importer too): `pvp` on every PvP quest, for both games; lists, and leaves alone, the quests in battlegrounds, Wintergrasp, Tol Barad and Ashran no source tags | `Sync-QuestPvP.ps1 -Game retail -WhatIf`, then without `-WhatIf`; the same with `-Game forever` after step 10 | Only the last one |
| 2f | Where each zone sits on its continent map, for the zone icons | the probe's map pass ([In the game](#in-the-game), step 3b) → `Compare-ContinentGeometry.lua <saved variables> docs\plans\continent-geometry-baseline.csv`, then `--update` once the differences are read | No |
| 2g | Minimum levels: the API's, else the client's level ranges, in `qcQuestMinLevel` (after steps 1, 1b and 2e; again after step 6 or 6b adds quests) | `Compare-QuestLevels.ps1` → `Apply-QuestMinLevels.ps1 -WhatIf`, then without `-WhatIf` → `Compare-QuestLevels.ps1 -UpdateBaseline` once the differences are read | Only the applying run |
| 2h | The calendar, both games: each holiday entry's dates to come, the dated events no entry covers, the decisions that rest on the calendar, and what `/qc holidays` should show, beside one `/qc holidays` per game in game | `Review-Calendar.ps1 -Build <retail build> -PtrBuild <PTR build> -ForeverBuild <Forever build>`, then `-UpdateBaseline` once the findings and changes are read; `/qc holidays` once on each game ([In the game](#in-the-game)) | No |
| 3 | Quest types | `Retype-FlaggedWorldQuests.ps1`, `Retype-ProbeRecurring.ps1` | Yes |
| 4 | Storylines | `Build-QuestLines.ps1 -Build <retail build> -Refresh` | Yes |
| 5 | Zone table and category names from the client | `Build-CategoryUiMapIDs.ps1 -Build <retail build> -Refresh` → `Add-ZoneTableMaps.ps1 -Build <retail build> -Refresh` → `Build-CategoryUiMapIDs.ps1` → `Build-CategoryClientNames.ps1 -Build <retail build> -Refresh` → `Sync-QuestSortNames.ps1 -Build <retail build> -ForeverBuild <Forever build> -Refresh` → `Remove-ConvertedLocaleKeys.ps1 -WhatIf` | Yes |
| 6 | Map pins, and quests new to the database | see [the pin pipeline](plans/quest-location-data-pipeline.md) → `Remove-DuplicatePinQuests.ps1`, then `Fetch-GapQuestData.ps1` → `Insert-GapQuestEntries.ps1` → `File-WeeklyEventQuests.ps1`; then steps 2b, 2c, 2g and 4 again, for the quests the inserter added | A candidate file, until you apply it |
| 6b | Task quests the client lists and the database lacks (world quests, bonus objectives, world events), no pins | `Add-TaskQuests.ps1 -WhatIf`, then without `-WhatIf`; then steps 1, 1d, 2, 2g, 2i, 2c and 4 again and `File-WeeklyEventQuests.ps1`, for the new rows | The applying run |
| 6c | Quest givers from the client's data and TrinityCore, then NPC IDs for named pins from TrinityCore | `Apply-ClientQuestGivers.ps1 -Refresh -WhatIf`, then without `-WhatIf` → `Fill-PinNpcIds.ps1 -WhatIf`, then without `-WhatIf`; then the pin pipeline again, for the pins they merge | The applying runs |
| 6d | Quest givers the addon's recorder noted, for both games: NPC IDs for pins that have none, pins for quests no source places, every disagreement listed | collect the recording files (below, "In the game"), then `Import-RecordedGivers.ps1 -WhatIf`, then without `-WhatIf`; then `Remove-DuplicatePinQuests.ps1 -WhatIf` and the pin pipeline again, for the pins it merges. Forever gets its ledger and report only | The applying run |
| 7 | Quests that may no longer be obtainable | `Find-UnavailableQuestCandidates.ps1 -Refresh` | No |
| 8 | Dungeons and raids against the Dungeon Journal | `Audit-DungeonCategories.ps1 -Refresh` | No |
| 9 | Quests and pins nothing can display | `Test-QuestReachability.lua`, after every step that edits the addon | No |
| 10 | WoW: Forever's quests and pins | the recorder's notes and [the Forever probe](#in-the-game) → `Read-QuestCache.ps1` → `Import-ForeverData.ps1` → `Build-ForeverMenu.ps1` → `Remove-ConvertedLocaleKeys.ps1 -WhatIf` → `Build-AddonData.ps1` → `Test-QuestReachability.lua` with Forever's TOC | Yes |

Steps 1 to 9 are retail's, except 6d, which reads both games' recorder notes and writes only retail's pins,
and 2h, which reviews both games' calendars.
Blizzard's API has no Forever data, so Forever has a step of its own,
which rebuilds its data from the game, the client's tables and CMaNGOS's database. It gets its own
pull request, like each kind of retail change. Which of retail's checks Forever has an equivalent
of, which it lacks and why, is in [plans/game-parity.md](plans/game-parity.md).

After each step that edits the addon, bring the data files up to date as described in
[The quest and pin data files](#the-quest-and-pin-data-files).

Step 3 reads the saved results of the in-game probe, so it needs nothing from the game on an
ordinary sweep. When step 6 or 6b adds quests, those have never been probed. Run
[the probe](#in-the-game) after them, then step 3 again. Step 10 always takes in the recorder's
notes (its item 1), but only needs a new probe run when Forever has a new build, or when the
beta opens higher levels; otherwise the last run's results stand.

### 1. Faction, race and class

`Audit-QuestAccuracy.ps1` checks every quest against Blizzard's API, filling `tools\quest_api_cache`
as it goes. That takes about 17 minutes with an empty cache. It writes
`quest_accuracy_audit.csv`, plus a list of quests the API doesn't know (old or removed content,
expected). `Categorize-AuditDiscrepancies.ps1` groups the disagreements.
`Get-WagoQuestRequirements.ps1` (step 1b) gives it a second source from the client's tables: the
task quests' races and classes (`QuestV2CliTask`), the conditions on a quest's start points
(`QuestPOIBlob` and `PlayerCondition`), and the classes that may use the items that start a quest
(`ItemSparse`: 36 quests on build 12.1.5.70391, as on 12.1.0.69933, and the 25 we have agree with
ours). WoW: Forever's importer reads the same item columns (step 10).

Run step 1b first, and start the audit only when it has finished. The audit reads
`quest_wago_requirements.csv` once, when it starts, and a 1b run beside it leaves the audit on the
old file: on 14 October 2026 the two ran together, and the audit was run again on 15 October from the
cache it had filled.

A class list that names Adventurer or Traveler (non-class entries) is read without them, not as "all classes" (13 October 2026: 21 fixes, and KEEP rows for the 175 lists that are wider than ours only because they predate Evoker, start in Acherus or belong to a class hall).

The 12.1.5 baseline (15 October 2026: the API's static-12.1.5_70077 records, the client's tables of
12.1.5.70391): 11,936 disagreement rows, and 5,359 of our quests the API doesn't know. Categorize
found 1 quest with a FIX field, 0 with SKIP, 1 with MANUAL and 217 KEPT. The FIX was 97212 Candy
Bucket, faction 3 to 2: the API and TrinityCore give it to the Horde only, and #328 had opened it to
both factions by a slip. `Apply-AccuracyFixes.ps1` applied it; race and class had no fix. The MANUAL
was 44920 Order of Incantations. The API lists every class but Evoker, plus Adventurer (4095), and
ours had 5 classes (2093). On the user's word it now has every class (8191), read like the 117
pre-Evoker lists. Categorize on the audit with those two rows brought up to date reports 0 FIX,
0 MANUAL and 218 KEPT. 12.1.5's API no longer lists classes for 39934 Our New Allies, so its KEEP row
matches no disagreement now. It stays, in case the list comes back.

Review before applying anything. Two lessons from the last cleanup:
- A faction's race mask is not a stale placeholder.
- Only restrictions the API actually asserts can be trusted.

The decisions from that cleanup are in
[plans/quest-database-accuracy-cleanup.md](plans/quest-database-accuracy-cleanup.md).
`Apply-AccuracyFixes.ps1` applies one field's reviewed fixes at a time. A value changed by hand gets
a `FIX` row in `docs\plans\quest-accuracy-manual-decisions.csv`, from `Cur` to `Target`, with the
reason. Categorize reads only that file's `KEEP` rows (below), and applies them only to rows it
marks MANUAL. If it would mark the changed value MANUAL (as it does 44920's pre-Evoker list,
15 October 2026), the value also needs a `KEEP` row with the new value in `Cur`, which turns it into
KEPT. A `KEEP` row doesn't hold back a FIX, so a hand change against a narrowing the API asserts
needs Categorize changed or the fix left unapplied.

To leave a MANUAL row as it is, record it in `docs\plans\quest-accuracy-manual-decisions.csv` with
`Decision` set to `KEEP`, our current value in `Cur`, and a reason. Later sweeps then report it as
KEPT rather than raising it again, unless our value changes.

### 1c. Quest names

`Sync-QuestNamesFromApi.ps1` gives each quest Blizzard's title for it and rebuilds `qcQuestData.lua`.
The game shows its own title once a quest's data has loaded, so ours matters for English search and
until then. A quest takes the title of the first of these that has one for it:
1. its record in `tools\quest_api_cache`, which step 1's audit fills;
2. for a quest the API doesn't serve (a `.404` file there), the newest retail quest cache (step 2e;
   `-Build` reads another);
3. for a quest the API doesn't serve and that cache lacks, the client's task table,
   `QuestV2CliTask.csv` (step 1b), which titles world quests, bonus objectives and the other task
   quests.

The user chose that order (decision 10e of the 12.1.5 sweep, option A). A quest none of them titles
keeps its name, as does one the API cache has no file for yet. The title is copied exactly, odd
spacing and capitals included, as the game shows it, with one exception: a title that starts with
`[DEPRECATED]` is never taken. That prefix is Blizzard's mark on a quest it retired. Whether such a
quest can still be done is decided on its evidence in `docs\plans\unavailable-quest-decisions.csv`
([plans/unavailable-quests.md](plans/unavailable-quests.md)), not by its title, and the quest keeps
its name; the run lists these apart. `-WhatIf` lists every rename by source, without making them.
`Test-SyncQuestNames.ps1` tests the order and the exception. From a worktree, point `-ToolsDir` at
the main checkout's `tools\`.

On 15 October 2026 (retail 12.1.5.70391, with the API cache of 14 October, whose records come from
the API's 12.1.5_70077 namespace) it checked 30,185 quests and renamed 5, each a title Blizzard changed
in 12.1.5 (the API's 12.1.0 records had our old names): 84773 Crystallized Celebration Crate, 88942
The Elves Are Going to War, 92450 Growing Up Is Hard, 94450 Twenty-Five Percent Completed and 94452
Seventy-Five Percent Completed. 5,359 quests were API 404s and kept their names, and the 29 quests
#347 added had no record in the cache yet. A second run changes nothing.

The 12.1.5 baseline, with the fallback (16 October 2026: the API cache of 14 October, whose files for
the 29 quests of #347 were fetched on 16 October from the same namespace, so every quest of ours has
one; the quest cache of 12.1.5.70391, its copies of 14 and 15 October read together, 29,824 of our
35,573 quests; the task table of 12.1.5.70391). By source:

| Source | Quests it titles | Renamed |
|---|---|---|
| The API | 30,209 | 0 |
| The quest cache, for the 5,364 the API doesn't serve | 1,977 | 19 |
| The task table, for those the cache lacks | 2,881 | 15 |
| Neither: the name stays | 506 | |

- **From the quest cache:** 41778, 46810, 46946, 48100 (The Defense of Eredath), 52115 (Kraken, not
  Kracken), 53372, 53982, 55976, 56119, 57330, 91802 (The Best Bites Are Bog Bugs), 92087 to 92093
  ("Level 2" to "Level 8", which ours had as "Unlock Ability 1 - Level 2" and so on) and 92123
  (Cragpine).
- **From the task table:** 45654 and 45737 (C'Thun), 45743, 51004, 51097, 51120 and 51988 (their
  nicknames' quotes, `Stef "Marrow" Quin`), 51848, 51894, 56793, 58744 (Whispers, not Whipers),
  91798 (Fish of the Day), 92139, 92150 and 92576 (Dominating the Domanaar).
- **Titles not taken:** 4, the Sunstrider Isle quests 8330, 8336, 8345 and 8346, which the quest cache
  titles `[DEPRECATED]...`. They got `KEEP` rows: `QuestV2` of 12.1.5.70391 lists them, and the server
  sent their data to the probe on 15 October, so they don't meet the rule to flag one
  ([plans/unavailable-quests.md](plans/unavailable-quests.md)).
- Of the 506 that keep their names, the 12.1.5 probe titles none, and 12.1.0.69933's cache, which
  this step doesn't read, differs from ours on 3: 52928, 53159 and 53239, "Wartime Donations: ..." in
  ours and "Arathi Donations: ..." there. The server refused all three to the 12.1.5 probe.
- The run warns that the quest cache holds under 90% of our quests (83.8%). A second run changes
  nothing.

### 1d. Professions

`Sync-QuestProfessions.ps1` gives a quest the profession it needs, so "Hide Other Profession Quests"
hides a Mining quest from a character without Mining. Three passes each read one kind of Blizzard
data:
- **Task quests** (world quests, bonus objectives, callings), which the API mostly doesn't serve: two columns
  of the client's `QuestV2CliTask` that agree wherever both speak, the skill the quest asks for, in
  the expansion's own line of the profession (its `SkillLine` row names the base profession), and the
  profession of its quest type (`QuestInfo`).
- **Blizzard's profession headings:** the category of the quest's API record (step 1) and the sort in
  the quest cache (step 2e), when that heading is a `QuestSort` named after a profession. Blizzard
  files quests this way up to Battle for Azeroth, and three later ones (67221, 81564, 81565); its
  other profession quests from Dragonflight on carry one general "Professions" heading, which names
  none.
- **The knowledge a quest rewards:** a guaranteed reward that the client's `Item` table files as
  Miscellaneous, Other and whose `ItemSparse` row needs a skill, such as Thalassian Miner's Notes.
  Recipes, reagents and fishing poles need a skill too but are other classes. This is how
  Midnight's and Dragonflight's profession quests are found.

Quests none of them names, and quests our data has wrong, are decided by hand in
[plans/quest-profession-decisions.csv](plans/quest-profession-decisions.csv): a `SET` row gives the
quest its `Target` profession (0 takes it away), and its `TargetCategory` and `TargetZone` when the
row has them, while the data still has the row's `Cur` (and `CurCategory` and `CurZone`, where given);
a `KEEP` row keeps a quest as it is though a pass names another profession, and is listed as out of
date once none does. A decided quest isn't listed for what the passes say of it.
- **Only a quest with no profession is given one.** A quest of ours that has another, a pass whose
  sources disagree, passes that disagree with each other, and a skill line with no bit in
  `qcProfessionBits` are listed and left. So is a decision the data no longer matches.
- **It lists quests filed under another profession's heading** in our menu, for a decision to move.
- **The skill level isn't kept.** It belongs with the skill requirements, which retail doesn't
  fill yet ([plans/game-parity.md](plans/game-parity.md), recommendation 3).

It reads `QuestV2CliTask.csv`, `QuestInfo.csv` and `ItemSparse.csv` as step 1b downloads them, and
keeps its own `SkillLine`, `QuestSort` and `Item` tables under the build's name
(`QuestSort-<build>.csv`), downloaded when the build has none; the build is the newest quest cache's.

On 12 October 2026 the headings gave 63 quests a profession and the knowledge rewards 58 (the 14
Midnight trainer quests of Silvermoon City among them). The decisions gave 81 more quests one (47 of
them Archaeology finds), took it from 8 story quests that no source ties to a profession, corrected 13
(the Ub3r-Spanner storyline was Enchanting), and moved 34 to their own profession's heading: 1,954
quests have one. A second run changes nothing, and step 6b gives the task quests it adds their
profession the same way, so this step finds nothing in them. `Test-SyncQuestProfessions.ps1 -ToolsDir
<the main checkout's tools>` checks the tool.

WoW: Forever has no task table and its quests reward no profession knowledge, so its professions come
from CMaNGOS in step 10, whose item 10 runs this tool's heading check on Forever's data.

### 2. Reputation rewards

`Compare-QuestReputation.ps1` compares `qcQuestReputation` against the API cache from step 1 and
writes `quest_reputation_compare.csv`. Then `Apply-ReputationBackfill.ps1` adds the rewards the API
lists and we don't have, and corrects the ones whose amounts differ from the API's. It leaves a
reward only we list alone and counts it: check those by hand, as the API may simply not list a
reward the game gives. On 15 October 2026 (API cache `12.1.5_70077`) the API pass found 4 rewards
to add, step 6b's 11378, 11382, 11386 and 57326 (below), none to correct and none only we list;
with them, all 11,039 of our rewards match the API.

Its cache pass (retail only, report-only) then checks the same rewards against the client's own
quest cache. It needs step 2e's `Read-QuestCache.ps1` to have written
`tools\retail_quest_cache_<build>.jsonl` (the newest is read unless `-Cache` names one) and the
client's Faction table for that build; without either it says so and skips, and the rest runs as
before:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/Faction/csv?build=<retail build>" -OutFile tools\Faction-<retail build>.csv
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Compare-QuestReputation.ps1
```

Each quest of ours falls in one class, found by comparing ours, the API's and the cache's rewards as
sets of faction=amount, never by position. A faction counts as shown when the Faction table lists it,
its `ReputationIndex` is 0 or more (the client keeps no standing for it otherwise) and
`ReputationFlags_0` lacks bit 4 (value 4, hidden). The classes, with the `Kind` of the row each
writes to `quest_reputation_compare.csv` (the old kinds, `api-only`, `ours-only` and `differ`, are
still written by the API comparison, and `Apply-ReputationBackfill.ps1` acts on `api-only` and
`differ` only):

| Class | Quests where | Kind |
|---|---|---|
| A | wherever each lists, ours, the API and the cache are the same | none |
| B | the cache has the API's rewards (ours, with none from the API) and more, only on factions that are not shown | `cache-more` |
| **C** | both list and the factions or amounts differ, a cache reward on a shown faction the API does not list included | `cache-differ` |
| **D** | ours or the API lists a reward and the cache has the quest with none | `cache-lost` |
| E | the cache lists rewards, ours and the API none, and one is on a shown faction: backfill candidates | `cache-only` |
| F | the same, with none on a shown faction | `cache-hidden` |
| G | the quest is not in the cache (informational) | none |
| H | the cache's own extras: quests not in our data, slots with an amount of 0, a faction in two slots | none |

The run exits with 1 on a class C or D quest, and says the reader looks moved when there are 100 or
more C quests (`-ReaderMovedAt`): run `Compare-QuestCache.ps1` then, and don't use the cache's
rewards that sweep. It prints the three builds (the API's, the cache's, the Faction table's) and warns
when they differ, as on 15 October 2026 (API `12.1.5_70077`, the other two `12.1.5.70391`); a few C
quests may be a hotfix between them. B, E, F and G move with what a probe run asked for, so their
quests are kept in `docs\plans\quest-reputation-cache-baseline.csv`, and each run says how many are
new and gone against it. Once those are explained, rerun with `-UpdateBaseline` and commit the file.
A cache that looks partial ([2e](#2e-the-retail-quest-cache)) would put the quests it lacks in G for
no reason of the game's, so the pass warns then, and `-UpdateBaseline` refuses to write (exit 1) until
a whole cache is read; `-AcceptPartialCache` writes it all the same.
On 9 October 2026 (cache 12.1.0.69933, API cache 12.1.0_68914) the classes held A 10,786, B 3 (quests
41138, 43568, 73226), C 0, D 0, E 2,043 quests with 2,986 rewards (all of them quests the API has no
record of), F 153 and G 2,451 (246 of them with a reward row of ours), and the cache reproduced all
11,690 of the API's rewards. Step 6b's 506 task quests (11 October 2026) moved E to 2,085 (42 new, all of
them new rows) and G to 2,852 (401 new, the new rows the cache lacks), and the baseline file was rewritten.
Whether to backfill E is the user's decision
([plans/retail-quest-cache.md](plans/retail-quest-cache.md)); nothing here changes data.

On 15 October 2026 (cache 12.1.5.70391, API cache 12.1.5_70077, Faction table 12.1.5.70391)
C and D were 0 and B the same 3 quests, and the cache reproduced all 10,054 of the API's
rewards on the quests it holds: A 9,329, E 433 quests with 581 rewards (all of them quests the
API has no record of), F 130, G 8,975 (1,707 with a reward row of ours) and H 18 (none with a
reward). That cache is partial: it holds 26,598 of our 35,573 quests ([In the game](#in-the-game),
the probe's step 3). The baseline was written on 11 October from an earlier reading of the
12.1.0 cache than the one in `tools\` (12 October, 33,123 quests): 409 of the baseline's G
quests are in the 12 October reading. The classes moved with the quests each reading holds,
and G with the data's new quests too. The 1,709 E and 32 F quests gone from the baseline are
all quests this cache lacks, now in G, and the 57 new E and 9 new F quests were all G in the
baseline. G gained 6,366 quests: 6,336 that the 12 October reading holds and this cache lacks,
and 30 that neither file holds, all added to the data since the baseline (#347's 29, and 97212,
a Midnight Candy Bucket added on 13 October). It lost the 243 baseline G quests this cache holds,
146 of them also in the 12 October reading. So the baseline file stays as it was until a complete
12.1.5 cache is read. The API cache of 14 October has no record of the 29 quests #347 added
(18 Hallow's End quests and 11 task quests), so the API pass counts 5,388 quests with none:
the 5,359 the API does not know and those 29. The records fetched for #347 on 15 October, in
the same namespace, list no reputation reward for the 24 the API knows, and it does not know
97219, 97241, 98421, 98422 and 98801; the quest cache holds none of the 29. On those records,
step 2 would add nothing for them once step 1 has fetched them.

### 2b. The tables kept by hand

`Audit-QuestTables.ps1` checks what no other step does:
- in `qcQuest.lua`: the breadcrumbs (`qcBreadcrumbQuests`), the quests that close others once
  they're done (`qcMutuallyExclusive`), the breadcrumbs the API closes only once their quest is done
  (`qcClosedOnceDone`, which must match the API both ways), the quests offered only while another is
  in the log (`qcQuestNeedsInLog`, empty on retail), the renown requirements, the daily and weekly
  limits and the faction names;
- in `data\quests.jsonl`: the prerequisites.

It needs the API cache from step 1 and the TrinityCore dump ([Before a sweep](#before-a-sweep), item 5),
and writes `tools\quest_table_audit.csv` (or `-OutFile`), one row per finding, with a count for each kind.
It lists the new findings (the first 50; the report has them all) and exits with 1 when there is one,
as step 2d does.

- **Against our own data:**
  - a quest that isn't in `quests.jsonl`, or is flagged unavailable;
  - a daily, weekly or repeatable quest in a breadcrumb or "only one of these" pair, since the
    addon never ticks those;
  - a one-time quest that requires a daily, weekly or repeatable one: the game only knows that one
    is done until the next reset, so the map would hide the quest again;
  - a breadcrumb, or a prerequisite that must be done, for the other faction: the addon counts
    such a prerequisite as met, so it does nothing;
  - a prerequisite of another profession (`prereq: other profession`): one whose profession shares
    none with the quest's, or any profession's for a quest with none. A character without it never
    meets it, so the requirements filter hides the quest and its tooltip names a quest the profession
    filter hides. Retail has none since 12 October 2026; Forever has two (769 and 5124, open-items);
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

A `KEEP` row that matches no finding is a new finding too, **decision out of date**, with the row's
`Kind` in its detail: the data or a source changed, so the row keeps nothing. Take it out, or move it
to the finding that took its place once that has been looked at. Only a run that read every source
judges the rows: a retail run with `-OwnDataOnly`, or with no TrinityCore dump, skips checks that would
have found something, so it says it held no row against the findings. The first run with this check,
on 15 October 2026 (12.1.5.70391), reported 129 findings, 10 of them new. 3 were one-time quests that require
a quest retyped as weekly on 10 October (#257): 83531 requires 83530, 89056 requires 89197 and 89057
requires 85721. The other 7 were rows out of date: six `prereq: recurring quest` rows whose quest #257
retyped as weekly too (83530, 85470, 85721, 88659, 89195 and 89197), and the `prereq: quest not in the
data` row for 91798, whose 91799 step 6b added on 11 October. Step 2c then dropped all seven links on 12
October (recurring links Blizzard doesn't name), so none of those quests has a prerequisite now and no
finding took the rows' place. The user kept the 3 the same day, as decision 3 of 6 October kept the 26
like them ([plans/quest-table-checks.md](plans/quest-table-checks.md#review-of-what-was-left-6-october-2026)),
and the 7 rows were taken out: the run then reported 122 findings, all kept, none new and no row out of
date.

`-Game forever` runs the checks that need only our own data on `data\forever` and
`QuestCompletist\Forever`, as step 10 does after the import: the breadcrumb, "only one of these" and
prerequisite tables against the quests (a quest not in the data, a daily or repeatable quest in a pair
or required by a one-time quest, a quest that requires itself or is required back, one for the other
faction or another profession, a quest listed twice). Forever's tables are generated, so the checks for hand errors don't
apply, and it reads no API cache, TrinityCore dump or client table. `-OwnDataOnly` does the same on
either game's folders with no download. Forever's `KEEP` rows are in
`docs\plans\forever-quest-table-decisions.csv`, and the findings go to
`tools\quest_table_audit_forever.csv`. As those checks are all Forever has, its rows are held against
the findings, and one that matches none is out of date, as on retail; on 15 October 2026 none was.

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
- **The current expansion's campaign** (`-Campaign`, 270 for Midnight): each chapter's first quest
  needs the last quest of the chapter before, where the API is silent on it. The zone campaigns the
  Scouting Map offers in any order (`-ScoutingMapLine 6131`) need what its quest needs instead
  (`-ScoutingMapQuest 95008`, "Adventuring in Midnight", whose objective is to choose one there).
  Change both, and `-Campaign`, for the next expansion.
- **The client's conditions on the expansion's quest lines and other campaigns** (`QuestLine.PlayerConditionID`
  and `Campaign.Prerequisite`, read through `PlayerCondition` and `ModifierTree` by `QuestConditions.ps1`): a
  quest on one that needs no other quest of it gets the condition too. Only conditions that name a quest of
  `-Campaign`, or the hidden quest a line accepts in place of one, are taken: on 12.1.0.69933 that is 15
  Voidstorm and Zul'Aman lines and campaigns 284 and 324, given to 213 quests, all through 86509, 86521,
  86522, 86565 or the hidden 90806. The addon counts 90806 but doesn't name it (`qcPrereq.Text`). A game
  feature switched on for everyone (type 289) is read as off; anything else it can't check is read as met.
- **A required quest the game offered together with the quest** in the newest map pass for `-Build`
  (`tools\map_offers_retail_<build>.tsv`, `-OffersFile`) is left out: it wasn't done, and the game offered
  the quest all the same. 32 on 12.1.0.69933. With no map pass for the build it says so and checks nothing.
- **The client's own follow-ups** (the quest cache's `RewardNextQuest`, from step 2e's
  `tools\retail_quest_cache_<build>.jsonl`, or `-QuestCacheFile`): a quest with no requirement, that the
  API is silent on, needs one of the quests whose hand-in offers it, where TrinityCore's `NextQuestID`
  or `PrevQuestID` says the same, and none of the checks above or below rules it out (also an
  unavailable quest, or one that needs a higher level). A breadcrumb into the quest (`qcBreadcrumbQuests`)
  isn't one either: the game offers the quest to a character who skipped it (129 left out). 1,384 quests on
  12 October 2026. A board quest (Hero's Call, Warchief's Command) is a breadcrumb into the quest its follow-up names: it has a row in `qcBreadcrumbQuests`, so it is never taken. Where the cache names several lead-ins and TrinityCore repeats only some, the quest is left out and listed ("Left out as the cache names more lead-ins than TrinityCore repeats"; 14 on 13 October 2026). A follow-up
  TrinityCore doesn't repeat is often a re-offer, so it isn't taken ([plans/retail-quest-cache.md](plans/retail-quest-cache.md),
  "Next quest"). Run step 2e first, with every session's copy of the build's cache in its probe folder:
  the game's own `Cache\WDB\enUS\questcache.wdb` is newer than the probe's copy after any play, but can
  hold only that session's quests, and step 2e joins the copies ([In the game](#in-the-game), step 3).
- **A one-time quest never gets a daily, weekly or repeatable requirement,** and a choice that
  offers one is left out whole. A recurring quest keeps one only where Blizzard's API or the client's
  task tables name it, as in a chain of world quests, which the game knows within the day or week;
  ours and TrinityCore's would hide the later quest after every reset (544 left out on 12 October
  2026, 102 kept).
- **The prerequisites decided with the user** replace what the sources give:
  `docs\plans\quest-link-decisions.csv`, in the columns of Forever's link decisions (`Quest`, `Name`,
  `Link` = `prereq`, `Other`, `Decision` = `SET`, `Evidence`), where several rows for one quest are a
  choice. The run counts them, and lists any that a source would now give something else, so a sweep
  sees when Blizzard starts to name one. Since 12 October 2026 it holds Dragonflight's renown crafting
  knowledge quests (45 rows). Each faction's Crafter's Knowledge I and II (`RenownRewards`) is one reward
  per profession, given to a character with any of the set's professions (its `PlayerCondition`). So
  each variant needs the renown quest before its set in Blizzard's line, and the reward after a set
  skips the variants. The 109.97 data chained each variant to another profession's.
- **A requirement that would make two quests each require the other** is left out, and listed.

A second run changes nothing, so a sweep only shows what Blizzard or TrinityCore changed. Each run
starts from ours without the conditions it gave, so a condition that changes or goes is changed or
taken off too. Step 2b knows the conditions' quests as the client's (`-OwnDataOnly` doesn't read the
client's tables, so there 90806 shows as a quest not in the data).

### 2d. Holiday tags

`Audit-QuestHolidays.ps1` checks retail's `holiday` values in `data\quests.jsonl` (see
[Holidays](#holidays)). It needs the API cache from step 1 and the TrinityCore dump of step 2b,
reads `qcHolidays` from `qcCore.lua`, and writes `tools\quest_holiday_audit.csv`, one row per
finding. Three signals, each independent, can name a holiday: the quest's category in Blizzard's
API, the game event TrinityCore puts it in (with the event's holiday), and the heading our data
files it under. A name is a holiday's when it is a name in `qcHolidays` or one of the 12 other names
the script lists (`$aliases`): two spellings (Midsummer, Winter Veil), the API's names for the
Ahn'Qiraj War Effort, the Scourge Invasion and Hearthstone's 10th Anniversary, the six cups' names,
and the API's Secrets of Azeroth (646), which holds only the 20th anniversary's Guest Relations quests
and is read as WoW's Anniversary. The summary prints every category and event it read as a holiday,
so a spelling that stopped matching shows as a name missing there.
- **untagged**, **wrong tag** (a signal names another holiday), and **untagged, an event with no
  flag** (TrinityCore has the quest in an event no `qcHolidays` entry names, such as New Year's Eve).
- **decision not applied**, **out of date** or **for a quest not in the data:** a row of
  `docs\plans\quest-holiday-decisions.csv` that the data no longer agrees with, such as a tag
  removed since its `SET` row.

A finding is covered, and not new, when the decisions file has a `PENDING` row for the same holiday
while the quest is still untagged, or a `KEEP` row while its tag is still the row's `Target`. The run
exits with 1 on a new finding: tag the quest in the data file and record a `SET` or `CORRECT` row, or
add the `PENDING` or `KEEP` row that says why it stays as it is. It only sees holidays with a flag in
`qcHolidays`; the quests of one with no flag show up once a flag is added.

Baseline on 12 October 2026, after decision 10's answers (#314): 920 quests in an API category read
as a holiday, 583 in a TrinityCore event read as one and 1,037 filed under a holiday heading. That is
13 findings, all covered by `KEEP` rows (the Darkmoon Island Warlock quests, the Candy Bucket that
TrinityCore puts in Love is in the Air, and the two New Year's Eve quests), so none is new; no row of
the decisions file is `PENDING`. Before those answers it was 856 quests in a holiday's API category
and 67 findings (56 `PENDING`: the Ahn'Qiraj War Effort's 43, the Scourge Invasion's 11 and the two
New Year's Eve quests). The 920 count the 16 Skyriding cup quests (the API's four cup categories,
and our heading "Northrend Cup", are read as the Skyriding Cups through aliases), the 57 Guest
Relations quests of WoW's Anniversary (the alias for Secrets of Azeroth) and 7 of the 11 Dastardly
Duos quests (the API's category of that name; the other 4 have none). The anniversary's other 19
quests are named by no signal (the API files them under the general "Seasonal", and neither
TrinityCore's anniversary events nor our headings hold them), so step 2d checks them only through
their `SET` rows, as it does The Great Gnomeregan Run's 47709 and Call of the Scarab's 18 quests: the
API gives those an area, Silithus (1377), and no category, TrinityCore has no event with them, and our
heading for them is Silithus. With them tagged (#315), the run's counts and its 13 findings are the
same, none new. The first run also found quest 43472, filed under Midsummer while its
`PENDING` row said WoW Anniversary; it now sits under Seasonal like its sibling 43461. The
run takes about 20 seconds.

On 15 October 2026, with the 12.1.5 API cache (12.1.5_70077), the counts were 982, 583 and 1,052 and
the findings 15: the API now files the Candy Exchanges 92567 and 92569 under Hallow's End, and their
`KEEP` rows held them untagged. With 12.1.5's Hallow's End quests tagged (the two exchanges, the eight
task quests of step 6b and 18 quests new to the data), the counts are 1,004, 587 (four of the new Horde
Candy Buckets are in TrinityCore's Hallow's End event) and 1,082 (with Broomstick Express and Specter
Inspector, 92104 and 92455, moved from Uncategorized under the Hallow's End heading too), and the findings
the same 13, none new. The 1,004 need the API records of the quests new to the data: a cache without the
24 fetched for them (22 of them in Hallow's End's category) counts 982, and step 1 fetches them. The same
day the `SET` rows of the 12 Bar Tab Barrels, which said the API gave them no category, were brought up
to date: the 12.1.5 API files all 30 Bar Tab Barrels of our data under Brewfest (370). That changed no
count or finding.

### 2e. The retail quest cache

The client keeps the server's record of every quest it has asked about in
`Cache\WDB\enUS\questcache.wdb`, and step 10 reads WoW: Forever's copy of it. Retail's holds the same
record, in the same layout with two fields fewer, for every quest the game has been asked about
(32,713 on 9 October 2026, 33,123 on 12 October; 29,844 for 12.1.5.70391 on 16 October, from two
copies). The cache holds only what was asked: the
quest-type probe (`/qc typecheck`, see [In the game](#in-the-game)) asks for every quest in our data,
so a cache from ordinary play is far too small, and `Compare-QuestCache.ps1` fails when fewer than
20,000 quests could be compared. A cache can pass that check and still be partial: 12.1.5.70391's,
of 14 October 2026, held 26,616 quests against the 33,123 of 12.1.0.69933's, though the probe's quest
pass asked all 35,544 of ours. The server refused 4,959 of them, asked 4 at a time, and 3,987 more were
among the 5,242 the probe counted as held with no level ([In the game](#in-the-game), step 3), which
never reached the cache. So the tools of steps 1d, 2, 2c, 2e, 2g, 2i and 6b (the check is in
`QuestCacheFiles.ps1`) warn when the cache holds under 90% of the quests of the newest cache of an
earlier build in `tools\`, or of the quests in our data, and name both counts. The warning changes
no exit code, but steps 2 and 2g refuse `-UpdateBaseline` (exit 1) while it stands, unless
`-AcceptPartialCache` is given. Step 6's `Find-MissingQuests.ps1` reads the cache too and does not
warn yet, so don't run its `-UpdateBaseline` on a cache the others warn about. When the warning
shows, ask the missing quests again before using the cache's values. The game's copy can hold only
the last session's quests (on 15 October 2026 it held that day's 5,110, the 26,616 of the day before
gone), so log out fully after each session, which makes the game write the cache, and copy the file from
`_retail_\Cache\WDB\enUS\` to `tools\retail_probe_<build number>\` (`retail_probe_69933` for build
12.1.0.69933), each session's copy under its own name (as `questcache.2026-10-14-1208.wdb`; the latest
may stay `questcache.wdb`). The reader joins every copy of the build in that folder. The comparison also
needs the API cache (step 1), the client's task table (step 1b) and the client's `QuestV2` for the
cache's build, which step 1b's unnumbered `QuestV2.csv` is not:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/QuestV2/csv?build=<retail build>" -OutFile tools\QuestV2-<retail build>.csv
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Read-QuestCache.ps1 -Build <retail build>
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Compare-QuestCache.ps1
```

Without that file the run still exits 0 but skips the repeatable check, and its closing line says so.
The reader fetches the `ChrRaces` and `QuestFactionReward` tables for the build from wago.tools when
`tools\` lacks them.

By default the reader reads every `questcache*.wdb` of the build in the `tools\retail_probe_*` folder
that holds the newest of them; `-CacheFile` names the copies instead (comma-separated, wildcards
allowed). In the folder, a copy of another build is left out, and the run says so; a named one stops
the run, as do copies of two locales. A quest in several copies takes the newest file's record, by
write time. The run says for each file how many quests it gave, how many no older copy held, and how
many of the rest read differently from an older copy. On 16 October 2026 the two copies of 12.1.5.70391,
`questcache.2026-10-14-1208.wdb` (26,616 quests) and the `questcache.wdb` of 15 October (5,110: 3,228
new, and the 1,882 an older copy held read the same), gave 29,844 quests. What the 14 October copy alone
gave is kept as `tools\retail_probe_70391\retail_quest_cache_12.1.5.70391.2026-10-14.jsonl`, not in
`tools\` itself, where step 6's `Find-MissingQuests.ps1` reads each `retail_quest_cache_*.jsonl` name as
a build and stops on one that isn't.

The reader (about 30 seconds) writes `tools\retail_quest_cache_<build>.jsonl`, one quest per line:
its title, content tuning, sort (the zone, or a negative number for a heading such as a class or a
profession), quest type, flags, and when they apply the quest info, group size, recurrence, follow-up
quest, start item, reputation rewards and races. It reads every record to its last byte and the file
to its terminator, or writes nothing. That can't see two fields of the same size swapped, so
`Compare-QuestCache.ps1` (about 25 seconds) compares the values with Blizzard's own: the API's records
for the same quests, and the task table's rows. It exits with 1 when a check differs for more than 5
quests and for more than 0.5% of what it compared, which a shifted field does for thousands; when the
title, sort or daily check compared fewer than 20,000 quests (`-MinCompared`), as with an incomplete
API cache; or when a check it needs compared nothing. Fewer differences are listed and are what a
hotfix between the API cache's build and the cache's looks like. It does not look at the group size,
the follow-up quest, the quest giver, the scheduler bit or the flags bits other than daily and weekly.
On 9 October 2026 (cache 12.1.0.69933, API cache 12.1.0_68914) nothing differed: titles for 28,985
quests, sort for 28,614, daily, weekly, recurs and repeatable for 28,985 each, faction for 9,273 and
races for 728, 11,690 reputation rewards, one level range for each of 741 content tunings over 28,983
quests, quest info for 1,830 quests against the API and 4,125 against the task table, which also
agreed on content tuning and start item for those 4,125. On 16 October 2026 (the joined cache of
12.1.5.70391, API cache 12.1.5_70077) nothing differed either, over fewer quests: titles, daily,
weekly, recurs and repeatable for 27,847 each, sort for 27,516, faction for 9,019 and races for 567,
11,093 reputation rewards, one level range per content tuning over 27,845 quests, quest info for 1,779
quests against the API and 2,311 against the task table, which also agreed on content tuning and start
item for those 2,311. The partial-cache warning still shows, for our quests only: the cache holds
29,824 of our 35,573 (83.8%), while its 29,844 quests are 90.1% of 12.1.0.69933's 33,123, just over
the 90% the other half asks for. If it fails, don't use the cache's values
that sweep: check that the cache, the API cache and the task table are from the builds you think,
then rerun the reader's record walk and look at the first differing quests with both values.

Step 2's cache pass reads the same file for the reputation rewards. What the cache says about our
data, and what it can't, is in [plans/retail-quest-cache.md](plans/retail-quest-cache.md). Two things
to know before reading its
file: `startItem` is the item the quest hands over when it is accepted, not the item that begins it,
and the record holds no level, only the ContentTuning ID that Blizzard's level range is a function of.

### 2g. Minimum levels

`Apply-QuestMinLevels.ps1` gives each retail quest the level a character needs to take it, so that
the tooltip's "Requires Level" line, the grey pins and "Hide quests with unfinished requirements" agree
with the game (the user's decision of 11 October 2026, option C of open-items.md rows 14 and 8). The
level goes in the quest's `minLevel` field, which the build writes to `qcQuestMinLevel`; the quest's own
`level` is not touched, because the list's bracket, its sort and the low-level filter read that
([the data files](#the-quest-and-pin-data-files)). Forever's table is filled by its importer (step 10);
this is retail's. It needs the API cache (step 1), the quest cache (step 2e) and the task table (step 1b):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Compare-QuestLevels.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Apply-QuestMinLevels.ps1 -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Apply-QuestMinLevels.ps1
```

Where a minimum comes from (`QuestLevels.ps1`), the first that has one:
- **The API's `min_character_level`**, for the 30,066 quests whose record gives one.
- **The client's level range.** A quest's `ContentTuningID` is in the quest cache for every quest it
  holds and in the task table for task quests (the cache's wins; they agree), and the `ContentTuning`
  table gives the range. A tuning's minimum is `MinLevelSquish` plus a base that
  `MinLevelScalingOffset` picks: 0 adds nothing, 1 adds 1, 2 adds the level cap (90) and 3 the cap before
  it (80). The bases are what the API's own minimums say, not a documented rule. A minimum beyond the cap
  (tuning 949's 255, which marks a quest nobody can take) is no level and gives none.
- **Tuning 0**, no range: nothing says what the minimum is, so the quest gets no `minLevel` (one it holds
  is taken away) and its own level stays its gate, as before step 2g. That is the user's decision of 11
  October 2026: no quest the API gives a minimum for is on tuning 0 in the cache or the task table, and on
  tuning 0 TrinityCore falls back to the quest's own `MinLevel`, which our files don't hold, so nothing
  can test that tuning 0 means no minimum; TrinityCore's own table even puts 67 quests the API gives a
  minimum for on tuning 0 (below). An API minimum would still decide for a quest on tuning 0.
- **Nothing**, for a quest in neither the cache nor the task table, or on a tuning the formula can't
  vouch for: it keeps what it had.

The table is downloaded for the cache's build when `tools\` lacks it (`ContentTuning-<build>.csv`; `-Refresh`
fetches it again, `-Build` names another build); the sweep's step 2b caches it too.

Before it writes anything the script tests the formula against every quest that has both an API minimum
and a tuning, and stops, changing nothing, unless at least 99% of at least 20,000 agree (`-MinAgreement`,
`-MinTested`). On 11 October 2026 (ContentTuning of build 12.1.0.69933, the quest cache of that build, the
API cache of 12.1.0_68914) **29,289 of 29,289 agreed** (offset type 0: 29,068; type 1: 210; type 2: 7;
type 3: 4); the API's other 777 minimums are for quests the cache and the task table have no tuning ID
for. A tuning whose own API quests disagree, or whose offset type no API quest has confirmed, is not used
for quests the API has no record of. A cross-check on TrinityCore's `quest_template.ContentTuningID`
(TDB 12.1.0.26091, once, by hand, not part of the tool) gave a tuning for 721 of those 777: the formula
agreed on 654 and the other 67 have tuning 0 there, quests old enough to have a minimum in the API and
none in the table. The API shows the minimum without `AllowedMinOffset` (-1, -2 or -4 on 2,522 of the
tested quests, nearly all of the newer expansions): none of them agrees with the minimum plus the offset. Whether
the game lets a character take such a quest that many levels early is not known.

It writes `minLevel` only where the minimum differs from `level`, treating 0 and 1 as the same, and
writes none for a quest on tuning 0 with no API minimum. A second run changes nothing, byte for
byte; after step 6 or 6b has added quests a rerun covers just those and any quest whose source has
moved. `-WhatIf` reports the sources, the changes by direction (the gate lowered or raised) and examples, and writes no data (a missing ContentTuning table is still downloaded into `tools\` first); `-Check` is the same and exits 1
when the data isn't what the sources say, for a Test- or Audit- step to call. The run of 11 October
2026: 1,623 quests changed, all of them a `minLevel` added (no other field of any quest, and no pin):
1,398 from the API (1,180 lowered, 218 raised) and 225 from the client's ranges (187 lowered, 38
raised), 1,367 lowered and 256 raised in all. The biggest blocks are Zaralek Cavern (265), Mechagon (226)
and the Emerald Dream (201), all lowered. The 17 quests on tuning 0 got none: an earlier rule gave the
five of them whose level is above 0 (9422, 50341, 54255, 54256 and 89346) a gate of 0, and the user chose
to leave them as they were; the other 12 are level 0.

**12.1.5 (15 October 2026).** With the ContentTuning table and the partial quest cache of 12.1.5.70391
and the API cache of 12.1.5_70077, the formula agreed for 25,759 of 25,759 quests (offset type 0: 25,615;
type 1: 134; type 2: 6; type 3: 4). Blizzard's retune lowered 15 Prey world quests: 95942, 95974 and
95989 (The Coiled Isle) and 96588 to 96599 (Voidstorm, Harandar, Zul'Aman and Eversong Woods) were on
tuning 5381 (90 to 90) in the quest cache of 12.1.0.69933, and 12.1.5's task table puts them on 5224
(80 to 90), the tuning of their 12 siblings (91207, 91458, 91523, 91590 to 91592, 91594 to 91596, 91601,
91602 and 91604), which are level 80. So `Compare-QuestLevels.ps1` found them new in class D: level 90,
and a minimum of 80. On the user's word they were given level 80 by hand, like the siblings, rather than
a `minLevel` (no tool refreshes retail's `level`). Now their level is their range's floor, class D is 0
again and `Apply-QuestMinLevels.ps1 -WhatIf` changes nothing. Class N was 571 (553 no record, 15 on
tuning 0, 3 above the cap). Against the baseline, 89 are new, all "no record": 71 that 12.1.0.69933's
cache holds and the partial cache lacks (step 2e), and 18 Hallow's End quests new to the data since the
baseline, which neither cache nor the API cache holds. One has gone: 54393 now has a tuning. The
baseline was not rewritten, since the cache is partial.

`Compare-QuestLevels.ps1` is the check, which writes nothing: the formula's test, then every quest
against its sources, in two classes kept in `docs\plans\quest-levels-baseline.csv` (`-UpdateBaseline`
rewrites it once the differences are read). Class D is a quest whose `minLevel` is not what its sources say:
a quest that matched in the baseline and doesn't now (a hotfix to a tuning, a quest added or its level
changed by another step) fails the run, and `Apply-QuestMinLevels.ps1 -WhatIf` says what to set. Class N is
a quest no source speaks for (483 on 11 October 2026: 463 that neither the quest cache nor the task table
has, three whose tuning has a minimum beyond the cap (38708, and the task quests 36868 and 36869), and the
17 on tuning 0); a new one is listed, since a source was lost, and doesn't fail. A
quest on tuning 0 that holds a `minLevel` is class D, so one of them gaining a gate again fails the run.
Baseline: D 0, N 483. A quest cache that looks partial ([2e](#2e-the-retail-quest-cache)) would put
those of the quests it lacks that neither the API nor the task table covers in class N as "no record"
(535 on 12.1.5.70391's partial cache, against 454 on 12.1.0.69933's), and test the formula on fewer
quests (25,759 against 29,447), so both scripts warn then, and `-UpdateBaseline` refuses to
write (exit 1) unless `-AcceptPartialCache` is given. `Apply-QuestMinLevels.ps1` still runs: a quest
the cache lacks keeps what it has, unless the API or the task table gives it a minimum.
Because the formula is tested against the API on every run, a new level cap, or a change in what
`MinLevelScalingOffset` means, fails here. `Test-QuestLevels.ps1` tests all three scripts on made-up quests
and, with the real files, on a copy of the data, and the partial-cache check of `QuestCacheFiles.ps1` on
made-up caches (209 checks).

### 2h. The calendar

Blizzard dates its calendar some months ahead, and adds dates, or doesn't, at each patch, so every
sweep revisits the holiday decisions taken on the calendar's word, on both games (the user, 11 October
2026). `Review-Calendar.ps1` reads the newest Holidays and HolidayNames tables of retail live, of the
retail PTR when there is one and of Forever (the builds resolved as in [Before a sweep](#before-a-sweep),
item 1), `qcHolidays` and each game's quest data, and changes nothing but its baseline, when asked:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Review-Calendar.ps1 -Build <retail build> -PtrBuild <PTR build> -ForeverBuild <Forever build>
```

It takes each table from `tools\` as `<Table>-<build>.csv` (step 2b caches them there), else downloads
it into `-DownloadDir`. It writes:
- **for each entry of `qcHolidays`, per game,** its next run on the user's realm and each other ID's, and
  the last date the table holds in any region, or "no date to come": an entry with none keeps its pins
  hidden for good;
- **the events dated to come that no entry covers** (not one of an entry's IDs, its name, or its
  `$HolidayRowPatterns` pattern): those on the user's region's calendar, which `/qc holidays` lists under
  "Other calendar holidays", those dated there but not expected on the calendar, and those dated for
  other regions only, each with its next run and its last date;
- **what `/qc holidays` should print** on each game today, in its order and words, to set beside the one
  run in game (below);
- **the comparison with the baseline**, `docs\plans\calendar-baseline.csv` and the two files beside it,
  `calendar-baseline-rows.csv` and `calendar-baseline-facts.csv`;
- **each fact of `docs\plans\calendar-decisions.csv`**, the decisions taken on the calendar's word, with
  its outcome today, and the decision to revisit when that outcome differs from the baseline's.

**Regions, and what the calendar shows.** A Holidays row's `Region` is a mask: 0 is every region, and the
user's realm reads the rows that hold 4 (Day of the Dead, 409, is for 1999, which holds 4, and the realm
served it). The next runs and the `/qc holidays` list are region 4's, an event's last date is any
region's, and an event with a row per region counts once, with the number of the others. A row is on the
calendar when it has a name, its `Flags` hold 1 and not 2, and its `Region` mask holds 4. Blizzard
documents none of this: the rule is inferred from the tables, it matched the user's retail `/qc holidays`
of 11 October 2026 exactly (the same 58 IDs, and the same days, below), and every sweep checks it again,
by the `/qc holidays` of each game set beside the review's list (below, and
[In the game](#in-the-game)). The review assumes region 4 for Forever too, until the first Forever
`/qc holidays` paste settles it: Forever's Fireworks Spectacular (62) is dated for region 1 only, so
whether that paste lists it says which. A row's run is its stages from the
first whose `CalendarFlags` is set to the last, so Brewfest shows from 20 September, a week after its
date, and the Darkmoon Faire from the Sunday after its Friday; a looping row repeats its first date every
sum of its durations (the PvP brawls every 77 days). `HolidayTables.ps1` holds this reading, which step
2b shares (`Get-HolidayLastDate`, the packed dates and `$HolidayRowPatterns`).

**The baseline** is three files, each per game (`retail`, `ptr`, `forever`). `calendar-baseline.csv`
holds each entry and each event with a date to come: its IDs, whether it has a date to come, its last
date (`never` for a row dated every year, or looping), whether that is within 90 days (`-SoonDays`) and
whether a row of it is on the calendar by its Flags and name, in any region. `calendar-baseline-rows.csv`
holds each of their rows that an entry lists or that has a date to come: its `Region`, its `Flags`,
whether those and its name put it on the calendar, and its runs to come (the day each starts on the
calendar, or the words of a row that repeats, such as `every year`). `calendar-baseline-facts.csv` holds
each table fact's outcome on each table (below). The run exits with 1 on a finding, never for a raid
opening still in the table ("Raid openings", below):
- a new event with dates to come; an entry or event with dates to come again; and, for an entry or an
  event on the calendar, one that loses its dates to come, is gone from the table, has its last date
  moved earlier (dates removed), or has it come within 90 days;
- a row with runs to come that comes onto the calendar or leaves it, by its Flags and name, or by its
  Region for region 4: Call of the Scarab's 638 or WoW's Anniversary's 1808 moved to another region, its
  dates kept there, is a finding, as the user's calendar no longer shows it;
- for an entry's row, or a row on the calendar by its Flags and name, a run to come that is no longer in
  the table (the Darkmoon Faire's run from 1 November 2026 taken out, the later ones kept), the row
  gone, a repeating row that stops repeating, and an entry's row dated to come again; so one ID of an
  entry going dateless (1407 of the cups, 1405 of Hallow's End, 335 of Love is in the Air) is a finding
  while the entry's other IDs keep it dated;
- a fact whose outcome changed (below).

The same for an event off the calendar (a row with no name, the plain-named "WoW's Anniversary" rows),
more dates or runs, new rows, an event that an entry now covers ("now covered by the entry ...", as The
Great Gnomeregan Run was when its entry came in, #314), and a new entry or fact are listed and don't fail. Only
runs still to come are compared: one that has begun since the baseline is no change, so a run passing,
the Darkmoon Faire's monthly move, and a sweep with nothing new in the tables say nothing beyond what
time brings: an event's dates coming within the 90 days or running out, and a fact whose outcome turns
as its days pass (the weekly fact below). A repeating row is kept as repeating, not by its date, so
Blizzard moving a yearly holiday (Brewfest a week earlier, say) or shortening a run in the middle is no
finding; the next-run list shows the new dates, and the per-game `/qc holidays` shows them in game. Once the
findings and changes are read, `-UpdateBaseline` rewrites the three files' rows of the games run and
keeps the others'. The 90 days: retail's patches come eight to twelve weeks apart, and each one's table dates
the rotating events (the weekly bonus events, Timewalking, the Darkmoon Faire) a few months further, so
an event whose dates end within 90 days may run out before the next patch; seen a sweep ahead, there is
time to read the PTR's table and to decide.

**Raid openings** still in the table are listed apart and never fail the run. The table dates each
raid's opening as an event of its own: a row per region for each of its `HolidayDescriptionID`s
(Kith'ix: three for each of four regions), named for the raid, of one moment (every `Duration` 0) and
with `Flags` 13, so on the calendar by its Flags and name. The Unbinding of Kith'ix (HolidayNames 465,
rows 1880 to 1891) is new in 12.1.5, whose table (70391) holds 135 such rows for nine raids. No entry
follows one and nothing is done when one appears or lapses, so every change of an event whose rows are
all of these (new, running out within the 90 days, no date to come any more, or any other, such as a run
removed or a row moved to another region) is listed as a change under "Raid openings" at the end of the
comparison (`Test-RaidOpening` in `Review-Calendar.ps1`). An event with any other row stays as before
(Aberrus, name 421, has a 24-hour row, 1361, beside its 19 of one moment), and so does one gone from the
table, which the review can no longer tell from another. On 15 October 2026 (retail 12.1.5.70391, the
PTR's 70340, Forever 1.60.1.70374) this turned the run's 2 findings, Kith'ix new on live and on the PTR,
into changes, and nothing else moved.

**The decisions file** has a row per fact: `Decision`, `Decided` (when, and by whom), `Recorded` (the
open-items row, the decisions CSV's rows, the pull request), `Game` (`retail`, checked on live and on
the PTR, or `forever`), `Fact`, `Seen` and `IfChanged` (what to revisit when the fact's outcome changes).
The tables answer these, each `holds`, `waits` or `fails`:
- `dated <IDs>`: each has a date to come, in any region;
- `no-date <IDs>`: none has one;
- `hidden <IDs>`: none is on the calendar by its Flags and name;
- `no-row <name>`: no Holidays row has the name;
- `yearly <entry>`: holds while a row of the entry (its IDs in `qcHolidays`, or a row its
  `$HolidayRowPatterns` pattern matches) is dated to come on region 4's calendar; waits from the end of
  a year's run until a year after that run began, while the table has no later row; fails after that,
  when next year's row was due and isn't there. WoW's Anniversary holds until 1808 ends on 8 December
  2026, then waits until 17 November 2027 unless the 23rd's row comes first;
- `weekly-every-day <region>`: some weekly bonus event is on that region's calendar, by its name, Flags
  and Region, every day from today to the last day the table dates one there; it fails on a day with
  none, and when none is dated to come. Its outcome can also turn with time alone, as the days with
  none pass or the last dated run ends: on the 12.1.5 tables (live's 70391 and the PTR's 70340, which
  date the weekly events as 12.1.0's did) it fails today (no weekly event on 7 to 19 January and 28
  January to 9 February 2027), holds from 10 February (only Timewalking 1583, 10 to 17 February, is
  left) and fails again from 18 February (none dated to come). Such a turn is a finding
  like the others: read it, then `-UpdateBaseline`. The weekly bonus events are taken by name (`$WeeklyEventPattern`
  in `Review-Calendar.ps1`): the Battleground, Arena Skirmish, Pet Battle, World Quest, Delves and
  Apexis Bonus Events and the Timewalking, Midnight and older Dungeon Events, whatever calendar filter
  their row has (Timewalking's 1583 has `CalendarFilterType` 255, not the weekly 0, and the calendar
  served it on 11 October 2026).

No fact carries a date, so none needs editing to stay true. `-UpdateBaseline` stores each outcome in
`calendar-baseline-facts.csv`, and an outcome that differs from the stored one is a finding, for which the
run prints `IfChanged`. A fact that fails or waits is listed every sweep, at the end of the decisions,
with the open ones, and is a finding only when its outcome changes; a new fact is listed until the
baseline has it. The game alone answers `served <IDs>`, `not-served <IDs>` and `ask <question>`: they
hold once `Seen` has the day they were seen (or answered), and until then are listed as open every sweep,
with the day an ID comes into the 12 months `/qc holidays` reads; the baseline doesn't store them. A
decision's part that rests on no calendar fact has a row with `none`, so the file holds the whole answer.

**In the game, every sweep, once per game:** `/qc holidays`, as a screenshot or a paste, set beside the
run's "What /qc holidays should print" ([In the game](#in-the-game)). An ID one lists and the other
doesn't is a finding to look at (the reading of the tables, a row dated some other way, or the game).
Put the day in `Seen` for each open fact the game has answered, and add a `not-served` row for a row the
table dates in the 12 months and the game doesn't list.

The first run, on 12 October 2026 (retail 12.1.0.69933, the 12.1.5 PTR's 70077 and Forever 1.60.1.70338),
wrote the first baseline: 185 rows, 21 entries for each game and the events with dates to come, 57 on
retail and on the PTR and 8 on Forever; with the rows and facts files, added the same day, 377 rows (179
on retail and on the PTR, 19 on Forever) and 34 fact outcomes. Of the decisions file's 30 rows, 25 facts
hold or were seen in game, one fails, one is `none`, and three are open: whether the calendar serves the
Outland (1407) and Northrend (1429) Cups, dated in 2028, beyond the 12 months `/qc holidays` reads,
whether the Guest Relations quests are offered while WoW's Anniversary runs, and whether the New Year's
Eve quests 8860 and 8861 follow Fireworks Celebration (658). The one that fails is
`weekly-every-day 4`, on live and on the PTR (below). Run as of 11 October 2026, its list for retail is
the user's `/qc holidays` of that day ([Holidays](#holidays)): the same 58 IDs, and for each entry the
same days. Live's table (12.1.0) then dated the Darkmoon Faire (479) to 13 December 2026, within the 90
days, and the PTR's to 12 December 2027, the one line in which the two differed; 34 events on the
calendar had no entry, Call of the Scarab (638) and The Great Gnomeregan Run (696) among them, and ten
rows with no name were dated in region 4 off the calendar. What the tables say now is under the sweep of
16 October 2026, below.

Later that day decision 10's answers added two entries (#314). Run again on the same tables, the review
gave no finding and listed 8 changes: Dastardly Duos a new entry with no date to come on each game (it
was no event of the baseline, having no date to come); The Great Gnomeregan Run a new entry, dated to come
on retail and on the PTR (to 14 October 2030), where its event, 696, is "now covered by the entry", and
with no date on Forever, whose table lacks the row. With `-UpdateBaseline` the baseline holds 189 rows
(23 entries for each game; 33 events on retail's and the PTR's calendars have no entry now), 383 in the rows file
(the three Dastardly Duos rows on retail and on the PTR added) and the same 34 fact outcomes, and a second
run says nothing. Retail's "What /qc holidays should print" now has a line for each entry its quests carry,
the Scourge Invasion, the Ahn'Qiraj War Effort and Dastardly Duos among them ("not on the calendar in the
next 12 months"), and The Great Gnomeregan Run (696) on its own line instead of under "Other calendar
holidays".

Later still, decision 35's answer added Call of the Scarab's entry (#315). Run again on the same tables,
the review gave no finding and listed 5 changes: Call of the Scarab a new entry, dated to come on retail
and on the PTR (every year, from 21 January 00:00 for 72 hours), where its event, 638, is "now covered by
the entry", and with no date on Forever, whose table lacks the row; the decision's `dated 638` outcomes,
under its new name, were new. With `-UpdateBaseline` the baseline holds 190 rows (24 entries for each
game; 32 events on retail's and the PTR's calendars have no entry now), the same 383 in the rows file
(638's on retail and on the PTR now an entry's) and 34 fact outcomes, and a run after it says nothing.
Retail's "What /qc holidays should print" lists Call of the Scarab (638) on its own line instead of under
"Other calendar holidays".

The sweep of 16 October 2026, three days after 12.1.5 went live (retail 12.1.5.70391, the PTR's
12.1.5.70340 and Forever 1.60.1.70374), gave no finding and 6 changes. Live's Holidays table changes one
row of 12.1.0's and adds twelve, and the PTR's is the same file, as is each one's HolidayNames: it dates
the Darkmoon Faire (479) monthly through the run of 5 to 12 December 2027 (12 more runs, from 3 January
2027; its last date 13 December 2026 -> 12 December 2027, no longer within the 90 days), and adds The
Unbinding of Kith'ix, a raid opening (above). It extends no weekly bonus event and no Timewalking, and
names no 23rd anniversary. Kith'ix's twelve rows are dated 13 to 15 October 2026 (region 4's on 14
October at 06:00), so on 16 October the event has no date to come and, never in the baseline, isn't
listed at all; the run of 15 October had listed it as a raid opening. The other changes are two rows
with no name and off the calendar, 651 and 653, whose last runs ended on 14 and 15 October ("has no date
to come any more"), on live and on the PTR. Forever's table is 70338's, unchanged. No decision moved:
the same 25 facts hold or were seen, `weekly-every-day 4` fails on the same days as on 12.1.0, and the
same three are open. With `-UpdateBaseline` the baseline holds 186 rows (651 and 653 gone, on live and
on the PTR), 371 in the rows file (479's runs to come extended; the passed Timewalking rows 643, 652,
654 and 656 and the nameless 651 and 653 gone, on each) and the same 34 fact outcomes, and a run after it
says nothing. On these tables:
- **Running out within 90 days, on live and on the PTR:** WoW's Anniversary (1808, 8 December 2026; no
  table has next year's row yet) and the weekly events: the Arena Skirmish (19 November), World Quest (3
  December), Pet Battle and Battleground (10 December) and Delves (24 December) Bonus Events and the
  Midnight Dungeon Event (31 December 2026). Timewalking runs to 18 February 2027 and the Darkmoon Faire
  to 12 December 2027. On region 4's calendar some weekly bonus event runs every day to 6 January 2027,
  and then none from 7 to 19 January and from 28 January to 9 February, between the Timewalking runs of
  20 to 27 January (1720) and 10 to 17 February (1583, the last), so `weekly-every-day 4` fails.
- **No date to come:** Hearthstone's 10th Anniversary (2024 only) and Dastardly Duos (2025 only) on
  retail; on Forever, Children's Week (2023 to 2025) and the Darkmoon Faire (263 and 264 hold no date at
  all).
- **On the calendar with no entry:** 32 events on retail, the same on the PTR, among them the bonus and
  dungeon events, Timewalking and eleven PvP brawls; on Forever the three Calls to Arms (1840 to 1842).
  Dated in region 4 and off the calendar: the plain-named "WoW's Anniversary" (1587, Flags 3) and nine
  rows with no name on retail, four with no name on Forever, 1879 among them.
- **Findings time alone brings,** on these tables (each seen by a run with a later `-Today` against this
  baseline): from 18 November 2026 the Lunar Festival (327, last 16 February 2027) comes within the 90
  days, on all three tables; from 20 November the Arena Skirmish Bonus Event has no date to come and
  Timewalking (last 18 February 2027) comes within the 90 days; from 24 November so does Love is in the
  Air (423, last 22 February 2027), on live and on the PTR (Forever's 335 is dated every year); after 3
  December the World Quest Bonus Event has no date to come, after 8 December WoW's Anniversary (1808),
  whose `yearly` fact goes from holding to waiting, after 10 December the Pet Battle and Battleground
  Bonus Events, after 24 December the Delves Bonus Event and after 31 December the Midnight Dungeon
  Event, so a sweep on 1 January 2027 would list 23 findings. `weekly-every-day 4` then holds from 10
  February 2027 and fails again from 18 February; the Lunar Festival has no date to come from 17
  February, Timewalking from 19 February and Love is in the Air from 23 February; the Harvest Festival
  (321, last 18 September 2027, on both games) comes within the 90 days from 20 June 2027 and has no
  date to come from 19 September, the Darkmoon Faire comes within them from 13 September 2027 and has
  none from 13 December, and WoW's Anniversary's `yearly` fact goes from waiting to failing on 17
  November 2027. A newer table that dates these further turns each into a change instead.

A 12.1.7 PTR, 12.1.7.70424, came out on 15 October 2026 under wago.tools' `wowt` (the 12.1.5 PTR's
builds are under `wowxptr`, the product `Get-LatestBuilds.ps1` reads for the PTR), after this sweep's
builds were set, and the baseline's PTR rows stay 70340's. Its Holidays table dates the Arena Skirmish,
Battleground, World Quest and Delves Bonus Events, the Midnight Dungeon Event and Timewalking into July
and August 2027 (the Pet Battle Bonus Event still ends on 10 December 2026), dates Turbulent Timeways
(1458, whose last run was 1 July to 12 August 2026) again, on region 4's calendar from 2 December 2026
to 27 January 2027, gives the nameless 651 and 653 a run in January 2027 (19 to 28 January), adds a
row with no name, 1895 (Flags 15), and its HolidayNames is live's. Given as `-PtrBuild` against this
baseline, it makes 21 findings: Turbulent Timeways, 1895, 651 and 653 new, 16 Timewalking runs removed
before they came (their rows dated other weeks instead), and `weekly-every-day 4` holding on it, every
day to 18 August 2027, whose `IfChanged` asks the user whether the weekly bonus event quests still stay
untagged.

`Test-ReviewCalendar.ps1` checks the review and `HolidayTables.ps1` on made-up tables (157 checks).

### 2i. The PvP tag

`qcQuestPvP` (the `pvp` field of the data files) holds the quests that are PvP. A quest takes the answer of the
first source that has one: the game's quest cache (`questInfo`, step 2e: 41 PvP on both games, and on retail
also 113 PvP World Quest, 255 War Mode PvP, 256 PvP Conquest and 278 PvP Elite World Quest; on Forever also the
last record in `data\forever\answers.jsonl` of a quest the beta answered only on an earlier build, for the quests
the importer keeps from it, by the same code in `ForeverAnswers.ps1`), then on retail
Blizzard's API (type 41) and the client's task table (`QuestInfoID`), then the emulator for a quest the game
hasn't answered (TrinityCore's `QuestInfoID` on retail, CMaNGOS's `Type` on Forever, the same kinds). The game's
"not PvP" stands over an emulator that says PvP. Hand decisions, which come first, are in
[quest-pvp-decisions.csv](plans/quest-pvp-decisions.csv): "Arena Grandmaster" (7838, Stranglethorn Vale's third
arena quest) is PvP by the user's word, where the game has no kind for it and CMaNGOS calls it PvP. The addon puts the
game's crossed swords before a PvP quest's name in the quest list and the map pins' tooltips, and draws them as
the icon of a pin whose quests are all PvP. Every sweep, with the newest cache of each game:

- `Sync-QuestPvP.ps1 -Game retail -WhatIf`, then without `-WhatIf` when it would change anything.
- Forever's comes from its importer (step 10), which applies the same order (cache and answer memory, then
  CMaNGOS, decisions first); run `Sync-QuestPvP.ps1 -Game forever -WhatIf` after the importer, and it must say
  0 quests get `pvp` and list nothing under "Has pvp, but no source calls the quest PvP". Its first line says how
  many quests the answer memory adds to the newest cache; the next says so when the memory's last run isn't that
  cache's build (run the importer first), and a missing memory is named as skipped.
- Compare its counts with the last sweep's. Baseline, 13 October 2026 (retail cache 12.1.0.69933): retail 363
  (the game 343: PvP 157, PvP World Quest 42, War Mode PvP 32, PvP Conquest 106, PvP Elite World Quest 6; the API
  4, the task table 3, TrinityCore 13), 109 of our quests no source answers for. Forever, 14 October 2026 (cache
  1.60.1.70374): 183 (the game 33, CMaNGOS 149, one decision), 0 of our quests no source answers for (5 with the
  newest cache alone); on 70338 it was 179 with the memory (the game 27, CMaNGOS 151), 176 without it (the game
  14, CMaNGOS 161). The sources agreed wherever more than one answered, except 7838. A kind the game adds (a new
  `QuestInfo` row with PvP in its name, read in `tools\QuestInfo.csv`)
  belongs in `$pvpKinds` in `Sync-QuestPvP.ps1`.
- Looked at on 13 October 2026 and not used, to be looked at again when a source changes: the quest cache's
  `flags` and `flagsEx` (no bit marks PvP: retail's 0x4000 and 0x4000000 are 32% and 31% of the PvP quests and
  0.2% and 1.4% of the rest, and are not PvP flags; Forever's 0x40, the raid size, is on 7 of its 15 PvP quests
  and 2 others), `AreaTable.Flags` (0x10000 is on 198 areas, the battlegrounds and arenas among them, but also
  Dustwallow Marsh and Kun-Lai Summit), and Wowhead, whose Quick Facts show "Type: PvP" for the quests the game
  tags and nothing for the ones it doesn't (3 pages read; its pages can't be read in bulk). The Forever probe's
  tags repeat the cache's, and the recorder and `recorded_quest_types.csv` hold no PvP data.
- It also lists, and never changes, the quests in the places PvP happens that no source tags (retail 147: Ashran
  56, Tol Barad 68, Alterac Valley 15, Arathi Basin 3, Seething Shore 2; Forever 34: Alterac Valley 20, Arathi
  Basin 8, Warsong Gulch 6). Whether any of them gets the tag is the user's call, by a row in the decisions file,
  so the list is read each sweep for a count that moved or a quest a source has started to tag.

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
  - **Inputs:** the probe's saved results on retail: the newest `tools\retail_probe_<build number>\QCForeverProbe.lua`
    (the probe's list is every quest in the data, so a quest added since needs a new list and run), else
    the older `tools\quest_type_probe_results.lua` of the retail type probe, whose only run, on 29
    September 2026, is the baseline until the probe has run on retail; and `QuestV2` for the probe's
    build. The script downloads that table when it isn't there. `Test-ProbeResults.ps1` checks that
    both files give the same retypes.

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

The quest tooltip shows a storyline's name from the game (`C_QuestLine.GetQuestLineInfo`, in the
player's language) when the game's quest line for the quest is the quest's `storyline`, and the name
in `qcQuestLines` otherwise. So the rule above, the smallest quest line a quest is in, decides how
often the game's name is used: 98.1% on the 15 October 2026 retail probe of 12.1.5.70391 (15,979 of
the 16,293 storylined quests it gave a quest line for; it gave none for the other 716 of the 17,009),
97.9% on the 9 October one (16,391 of 16,737), 11 of 11 on Forever's. Of the other 314 on 12.1.5, the
game names a line with more of our quests for 244; one with as many for 45, where the tool takes the
lower ID (17 of them are in 1108 "Through the Shattered Sky", where the game names 1267 "Maw Intro");
and an internal line the tool skips for 25 (11 in the "Catch Up: War Within: Wrapper" lines, 6 in
"[PH] 12.1 Max Level Campaign Chp 1", 6 in `[DNT]` lines, 2 in test lines). To measure it again,
compare the probe's `questLineID` facts (`Read-ForeverProbe.lua <file> facts`, the `fact <quest>
questLineID <id>` lines) with each quest's `storyline`, sizing each line by its quests in our data, as
the tool does.

The 12.1.5 run (15 October 2026, build 12.1.5.70391): 1,563 quest lines with player-facing names
(131 internal skipped), 1,476 written to `qcQuestLines` (1,474 before); 17,009 quests with a storyline
(16,950 before), the 59 gained being step 6b's rows of 11 October, and none lost or moved. The 12.1.5
tables add 5 quest lines and 36 of their rows, none for a quest of ours, and reorder Shadows Awaken (40)
to 33075, 33070, 33765, 33905, 33813, 34019. The 59 were in the 12.1.0 tables too: step 4 hadn't run
since step 6b added them. Two lines are new to `qcQuestLines`: 6056 "Blessing Task List" (7 quests)
and 6228 "The Coiled Isle - World Quests/Repeatables" (31, and the same 7, which go to the smaller
line). Five grew: 5954 "Prey WQs" by 15, 5978 by 3, 5986, 383 and 5747 by one each. The 15 October probe
gave a quest line for 28 of the 59, ours for 26 and the larger 6228 for 2 of 6056's, and got no answer
for the other 31.

### 5. Zone table and category names from the client

`Build-CategoryUiMapIDs.ps1 -Build <retail build> -Refresh` downloads the game's map table
(`UiMap.csv`) for that build and maps quest categories to game maps, so the client supplies their
names in every language. A tool of this step downloads a table only with `-Refresh` or when the
file is missing, and retail's file names carry no build, so without `-Refresh` a run reads
whatever build's table is already there. Without `-Build` it downloads the tables of the build it
has as its default, which after a patch is the one before. So each run here that downloads passes
both.

Then run `Add-ZoneTableMaps.ps1 -Build <retail build> -Refresh -WhatIf`, then without `-WhatIf`.
It adds the maps missing from `qcAreaIDToCategoryID`, which turns the map you're on into a quest
category. The addon switches the quest list through it when you enter a zone, and
`Place-UncategorisedQuests.ps1` files quests by it. Nothing else maintains it, so new dungeons and
new versions of a zone's map drift out of it. A map is added when a category is named by it, when
it has the same name and parent as a map already listed (a dungeon's other floors), when it's in
the client's map group (`UiMapGroupMember`, the floor selector's list, downloaded for `-Build`) of
a map already listed (floors with names of their own, such as Black Temple's Karabor Sewers), or
when its name is exactly that of one category with no map yet. It never adds continent-level maps,
never gives a map to a category with no quests, and never changes an existing entry. A floor it
leaves out because its name is another category's (The Stockade, in Stormwind City's group) is
listed, for adding by hand if that's wrong. Run `Build-CategoryUiMapIDs.ps1` again afterwards,
without `-Refresh`, so it sees the new maps.

Then run `Build-CategoryClientNames.ps1 -Build <retail build> -Refresh`. It names the categories
that aren't maps from other client tables: classes, professions, covenants, dungeons, achievement
categories (the world events), factions, Blizzard's UI text and area names. A rerun with no client
changes leaves `qcQuest.lua` byte-identical. Names we made up ("Bfa Unknown", "Garrison Support")
stay ours.
The same tool writes `clientName` into `qcMenu.lua` for the menu headings it lists (continents,
expansions, "Battlegrounds", "Professions" and so on), chosen by hand.

Then run `Sync-QuestSortNames.ps1 -Build <retail build> -ForeverBuild <Forever build> -Refresh`,
with `-WhatIf` first. The game can't be asked at runtime for the name of a quest log heading, so a
category filed under one ("Timerunning", "Garrison Support", the War Campaigns, Forever's "Lunar
Festival") keeps its key in the `Localization` files, and this tool writes the client's own name
for the heading, in each language, into those keys from the `QuestSort` table, downloaded per
language. The headings are chosen by hand in the script, only where the heading's English is
exactly the category's name; it stops if Blizzard renames a heading or we a category. Both games'
headings are covered, retail's text first where both have one ("Seasonal"), Forever's if retail's
table is a copy of the English one. A rerun with no client changes leaves every file
byte-identical. A language's table that is byte for byte its build's English one isn't a
translation (as wago serves Forever 1.60.1.70374's Italian one), so the tool skips it: a key that
only such tables have keeps the file's own text, and the tool's line for that file names it as
kept. One of those keys that the file lacks stays out, so the game shows English for it, and the
tool names it as not added. Then run `Test-Localization.lua` (below).

`Remove-ConvertedLocaleKeys.ps1` then deletes the text the client has made redundant, in both
games. Run it with `-WhatIf` first.
- The key of a category the client names goes from every locale file, unless code or a heading
  uses it. Should the game ever return no name, the category's English name shows.
- So does the key of a category taken out of `qcQuestCategories`, unless a category of either game,
  code or a heading still uses it: an English key nothing uses.
- A heading the client names keeps its English, as the fallback, but not its translations.
- A category's entry in `qcMenu.lua` loses its label: the menu names categories through
  `qcCategoryName`, so the label never shows. An indented entry keeps its indent, as
  `text="   "`.

The 12.1.5 run (15 October 2026, retail 12.1.5.70391, Forever 1.60.1.70374) is the baseline to
compare a sweep with:
- `Build-CategoryUiMapIDs.ps1`: 337 of the 481 categories named by a map, 32 left to our own text
  because the client's name differs ("Maw of Souls" is "Helmouth Cliffs" to the client). Both runs
  left `qcQuest.lua` as it was.
- `Add-ZoneTableMaps.ps1` added 2 maps, both by the same name and parent: 2605 Silvermoon City (as
  2393, parent 2395) to Silvermoon City (1512), and 2162 Alterac Valley (as 91 and 1537, parent 25) to
  Alterac Valley (7). Runs had listed 2162 since at least 11 October
  ([plans/menu-review.md](plans/menu-review.md), question 31) without its being added; it was added by
  the user's decision of 15 October 2026. Neither map has a pin. It listed The Stockade (1013) as
  before. The table has 1,111 keys (1,115 entries: 219, 221, 1670 and 2372 are each there twice).
- `Build-CategoryClientNames.ps1`: 111 categories named other than by map (instance 19, achievement
  category 16, area 16, skill 16, class 12, format 11, string 8, faction 6, covenant 4, map 3), 31
  categories with quests still named by our own text, 25 menu headings named by the client (26
  lines). `qcQuest.lua` and `qcMenu.lua` were left as they were.
- `Sync-QuestSortNames.ps1`: 0 keys changed or added; 31 unchanged in each file except Italian's,
  which has 26 unchanged and 5 kept (AHNQIRAJWAR, CAMPING, INVASION, LUNARFESTIVAL, MIDSUMMER) as the
  file has them, Forever's Italian table being its English one.
- `Remove-ConvertedLocaleKeys.ps1 -WhatIf`: 0 lines, with 29 keys kept in English only for the
  headings the client names. `Test-Localization.lua`: 162 keys of English's own, 133 of each other
  language's, no problems.
- Of the tables downloaded with `-Refresh`, the build-less `Covenant.csv` and `GlobalStrings.csv` in
  `tools\` were of an older build than 12.1.5.70391's, so a run without `-Refresh` would have read
  those.

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
continent over a zone) is left out. A quest with a point 32 and no point -1 on a map is placed when it has a
pin already (534 do), which it moves to its start, or when it is one of our quests and not a task
quest of a kind the addon doesn't pin (193 more in October 2026, 814 on 11 October, 77 of them
Dragonrider Racing): a task quest is
one in the client's task table, which holds the world quests and bonus objectives the addon doesn't
pin, and also dailies, seasonal and ordinary quests, which it does. The kinds it doesn't are listed by
`QuestInfoID` in `$noPinKinds`, a table at the top of `Build-QuestLocationData.ps1`: every `QuestInfo`
named "World Quest", Hidden Quest, Threat Wrapper, Bonus Objective with Completion Toast, and Calling
Quest (271), which is held until it is known whether the game still offers callings (delete its line to
pin them; `Test-QuestLocationKinds.ps1` checks that). Dragonrider Racing (281) is pinned, nameless, as
no source has a giver for it. The run stops at a `QuestInfo` named "World Quest" that
the table lacks, so a kind a new build adds is looked at, not pinned; add its line. A task kind that is
not named "World Quest" and is not in the table is pinned: World Event (82), Emissary Quest (128) and
Delve (288) would be as soon as the task-quest change (#295) adds quests of those kinds that have a
start, so read the run's count of new task quests by kind before applying, and add a line to hold one.
Since #295, the next run pins 175 of its quests, 52 of them World Event (decision 40 of
[plans/open-items.md](plans/open-items.md)). The tool needs
`UiMap.csv`, `QuestV2CliTask.csv` and `QuestInfo.csv` (it stops without the last two) as well as the
tables above; step 5 downloads `UiMap.csv`, and step 1b `QuestV2CliTask.csv`, `QuestV2.csv` and
`QuestInfo.csv`.

A quest the client's export lists no point for at all gets its start from TrinityCore's
`quest_poi` (point 32; point -1 is mostly the hand-in and is not used) when it is a normal quest
of ours with no pin: not a task, system or holiday quest, not flagged unavailable, in `QuestV2`, not disabled in
TrinityCore, and not an auto-accepted one with no giver
([plans/quest-location-data-pipeline.md](plans/quest-location-data-pipeline.md), "October 2026,
pins from TrinityCore", has the rules; a task quest is held only when its kind is in `$noPinKinds`). The
tool reads the newest `tools\tdb\TDB_full_world_*.sql` with
Lua 5.1 and, without them, only warns and places none. It writes each place of such a quest, up to
six, to `quest_locations.csv` (`Source=trinitycore`). The quests it holds back for a person, at a
placeholder start point or with no usable start, go to `tools\quest_locations_tdb_review.csv`: look
through it every sweep. A starter whose TrinityCore spawn stands at the start names the pin;
otherwise the quest joins a neighbour's pin only if that NPC starts it, else it gets a nameless pin,
and it never changes the icon of a pin it joins. A quest the client places (a point 32) that has no pin
yet is named the same way, by the starters TrinityCore lists for it, instead of taking the name of
whichever known NPC stands within 1.5 points. Once a quest has a pin, the next run leaves it
out of the CSV and its pin stays, so a rerun's CSV is shorter by these quests and Join's "No
existing pin at all" count is the number of new quests to review (1,453 in October 2026). To take a
pin away, flag the quest unavailable, or take it off its pin in `data\pins.jsonl`.

A start goes on the map its own row names, the client's or TrinityCore's, even when it lies within a
point of that map's edge and the quest's other points are on the neighbouring map. Quest 26064 was moved
to the neighbour by hand (its line in `data\pins.jsonl`, then `Build-AddonData.ps1`, the four steps and
`Assemble-PinDB.ps1 -Apply` for the file's order), which a rerun keeps because the quest has a pin and
no row of its own; the 15 other quests of that shape stay where the client puts them
([plans/quest-location-data-pipeline.md](plans/quest-location-data-pipeline.md), "a start on the edge
of a map", and decision 32 in [plans/open-items.md](plans/open-items.md)).

A quest whose only start is on a disabled map (a `UiMap` named "... - Disabled", held back as
`start on a disabled map`) gets its pin by hand: a line in `data\pins.jsonl` on the disabled map's
parent, the zone's own map, with the start's world point converted by that map's `UiMapAssignment`
row. It has no name unless the client's giver table, or a starter's spawn within 1.5 map points,
names one. The line goes where the pipeline orders its map's pins (lowest quest ID, then x, then y),
the pipeline keeps it, and the quest leaves the review file at the next run. The two of October 2026
are in [plans/quest-location-data-pipeline.md](plans/quest-location-data-pipeline.md), "A start on a
disabled map".

Run the retail map pass each retail sweep too ([In the game](#in-the-game), step 3b; it takes the
geometry of the continent maps as well, read with `tools\Report-ContinentGeometry.lua` and compared with its
baseline by `tools\Compare-ContinentGeometry.lua`, step 2f). Its offers
are the game's own start positions, to compare with the pins: `tools\Report-MapOffers.lua` lists the
quests whose pin is far from, or on another map than, the game's position. The 439 offers of the first
run were within 10 yards of point 32. On the 12.1.5 pass (14 October 2026) the pins were within 1.5
points of 243 of its 412 offers and more than 5 points from 1; Eversong Woods (map 2395) answered no
offers that run.

The grouping rule and the order a pin's giver is chosen in are `tools\PinRules.ps1`, which Forever's
importer uses too (step 10), so the pins of both games follow one rule; what stays retail's own is
the carry-over of what its pins hold (the borrowed names, the old pairs kept, the positions reused):
- A pin names the first of these that has someone: the quest's existing pin nearest the start (the
  carry-over), a starter whose TrinityCore spawn stands at the start, and a known NPC within 1.5 map
  points that starts the quest. With none, it names nobody.
- A giver's quests share a pin only where they start within 1.5 map points of each other (3 until
  October 2026, when the user chose that a quest with a start point in the client's data keeps it
  rather than joining its giver's pin up to 3 points away; see the pipeline plan, "October 2026,
  after the NPC IDs"). The giver is the pin's NPC ID, or its name when it has no ID.
- Quests that name nobody (no NPC ID and no name) share one pin per spot, in both games: a start
  within 1.5 map points of such a pin's first start joins it, the nearest when several are in reach.
  Until October 2026 retail gave them a pin per quest and place (decided 13 October, the 1.5 points
  on 15 October: [plans/open-items.md](plans/open-items.md), row 7). When the quests of a spot bring
  different icons, the pin takes its quests' icon (seasonal, profession or class when every quest is
  one, else normal); otherwise the icon it brings stays.
- A pin that lands within 1.5 points of an existing one keeps the existing coordinates, and its note.
  Notes that find no pin are listed. Two groups of one giver, or two that name nobody, that land on
  the same coordinates this way become one pin, so a rebuild leaves no two pins of a giver closer
  than 1.5 points. With the reused coordinates, a start can end up a little more than 1.5 points from
  its pin (16 starts, 1.5 to 2.1 points, on the 12.1.5 data).
- Pins are written in a fixed order.

On the 12.1.5 tables (build 12.1.5.70391, 16 October 2026) the pipeline makes 13,549 pins where the
rule of a pin per nameless quest made 16,294 from the same inputs: 2,745 of the 5,364 nameless pins
merge into others, leaving 2,619, and the 10,593 pins with an NPC ID and the 337 with only a name are
line for line the same. No quest gains or loses its last pin: 7 quests whose starts straddle two
spots sit on two nameless pins close by, 2 quests with several pins on one map have one fewer, and 8
spots whose quests bring different icons take their quests' (for 3, another than their first pin's).
The pin data still holds a pin per quest: applying the rule is its own
pull request, after the 12.1.5 story quests
([plans/quest-location-data-pipeline.md](plans/quest-location-data-pipeline.md), "October 2026, one
pin per spot").

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

After a probe run's NPC pass (`/qcprobe npcs`, [In the game](#in-the-game)), run
`Compare-PinNpcNames.ps1 -Game retail` (and `-Game forever`): it compares the name on every pin that has
an NPC ID with the name the game gives that creature, and writes the ones that differ to
`tools\pin_npc_names_<game>.csv` with a class: `spacing` and `contains` are NAME rows for
`pin-npc-id-decisions.csv` after a look, `differs` is an ID that names another creature (an ID row), and
`not named` and `not asked` are listed for the record. It changes nothing.

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
  has none. A pin with no name holds what starts at its spot, so it takes the giver only when the
  giver is found for every quest on it. Otherwise the quests the giver is found for move to its
  pin within 1.5 points, or to a new one at the nameless pin's place, and the others stay on the
  nameless pin, which keeps no name (`Split-NamelessPin` in `PinRules.ps1`; the import of Forever
  gets the same by placing every quest at its giver each time). A quest two givers are found for
  stays, and is listed with the pins whose quests name different givers.
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

`Import-RecordedGivers.ps1` (step 6d, after 6c) takes in what the addon's recorder noted while the
game was played ([plans/quest-giver-recorder.md](plans/quest-giver-recorder.md)). It needs `tools\UiMap.csv`
(step 5) and Forever's `UiMap-<build>.csv`, and for new pins `QuestV2CliTask.csv`, `QuestInfo.csv` and, to
count a class, `QuestV2.csv` (step 1b). The files are
the maintainer's own (`tools\recordings\own\retail\` and `\own\forever\`, and the Forever probes'
files in `tools\`) and players' (`tools\recordings\players\<tag>\`, the tag a label such as `p01`,
never a name); see "In the game" for how to collect them. A file is read by
`Read-RecordedGivers.lua`, which refuses anything that is not plain data, because a saved-variables
file is Lua code and a player may have sent it. The game each file belongs to comes from the
versions in it, and only the versions the TOCs name are read (`-Builds` changes that).

What it keeps is the ledger, `plans\recorded-quest-givers.csv`: the givers, the places they were
seen, the quests they offered and took in, and the quests that began away from a giver, with the
sources that saw each. It only grows, so the facts outlive the addon's cap and a file a player
clears. A fact is acted on when the maintainer's own files saw it, or two different players did;
a lone player's file decides nothing (not a name, not where a place is, not how often a giver was seen).
Two files are two players whatever they hold, so open players' files only after a sweep on your own has
run clean. `-ForgetTag p07` takes a source out of the ledger and skips its file for that run: delete the
file as well, or the next run reads it again, and a pin that source helped to fill keeps its ID.

On retail's pins it fills a pin's missing NPC ID (with its name) when a trusted creature offered one
of the pin's quests and stood within 1.5 map points of it; and it gives a quest that has no pin one,
at the place its giver was most seen, or adds the quest to the pin that giver already has. The
holds the TrinityCore pass puts on a quest that no creature offers (not in `QuestV2`, a
holiday, a profession, a quest type other than 0, 1, 2, 4 and 128, and a task of a kind of
`$noPinKinds` that the recorder doesn't hold itself) are waived when a creature offers it, and the report
counts the quests by class; a world, bonus or hidden quest, a quest flagged unavailable, an internal name
and a system category stay held, except six system categories whose quests mostly stand on a pin with an NPC
already (World PvP, Little Scales Daycare, Upgrade System, Warbands, Delver's Headquarters, Weekly Events:
`$allowedSystemCategories` in the tool; Prey and Garrison Support stay held on purpose, see the plan, "Adds").
A pin with no name is filled only when the giver offered every quest on it; otherwise the quests a
trusted giver offered there move to its pin within 1.5 points, or to a new pin of the giver at the
nameless pin's place, and the others stay, as in step 6c. It never moves a pin, never changes an ID
or a name that is there, never takes a quest off a pin but in such a move, and writes no pin if any
of that would happen. A fill that would put two pins of one NPC within 1.5 points is not made (the pipeline would
merge them and move one pin's quests): it is listed, as are a pin the recorded giver stood 1.5 to 3
points from, a giver recorded where the game gave no position, and trusted sources that disagree on a
name (the giver then has none). Everything that needs a person is in `tools\recorded-giver-report.txt`,
and the lists beside it, each for both games, with the sources and whether they are enough to act on: `recorded_unknown_quests.csv` (offers for
quests the data lacks, for `Fetch-GapQuestData.ps1`), `recorded_quest_types.csv` (a recorded
daily, weekly or repeatable that is not the quest's type, for step 3), `recorded_headings.csv`
(the log heading of unplaced quests), `recorded_start_items.csv` (quests that began with an item
or a trigger) and `recorded_mask_contradictions.csv` (a character offered a quest whose faction,
race or class mask excludes them); they are lists to look through, and nothing reads them yet. A case
looked at that stays goes in `plans\recorded-giver-decisions.csv` (`Quest`, `Map`, `X`, `Y`, `Decision`
KEEP, `Reason`, as in `pin-giver-decisions.csv`, whose KEEP rows it also honours: a KEEP on any quest of a
pin keeps the pin; a row with a quest and no map or place keeps the quest from getting a pin from here; a
pin whose ID `pin-npc-id-decisions.csv` took off by hand is left alone). A second run changes nothing. After it, run
`Remove-DuplicatePinQuests.ps1 -WhatIf` and rerun the pin pipeline, as after 6c. Forever's pins are
rebuilt by `Import-ForeverData.ps1` every time, and it reads the ledger (step 10, item 1), so for
Forever this step only keeps the ledger and the lists; run it before step 10. The report does not compare
the ledger with Forever's pins, so its "0 cases for
review" says nothing about them. The first real run (11 October 2026, the Forever beta file: 87 records, 0
odd, 42 givers, 40 spots, 45 offers, 41 turn-ins, no starts; the ledger 121 to 231 rows, no pin changed, a
second run byte for byte) has its numbers in [plans/quest-giver-recorder.md](plans/quest-giver-recorder.md),
"The first real run". The baseline to compare a sweep with is the run of 14 October 2026 (Forever beta
1.60.1.70374): the addon's Forever file 144 records, 0 odd (69 givers, 67 spots, 76 offers, 49 turn-ins, no
starts), the probe's file 164 records (80 givers, 88 spots, 99 offers, 58 turn-ins), and the Forever ledger
231 to 326 rows (80 givers, 88 spots, 99 offers, 59 turn-ins), all trusted. Every giver note in them was of
build 70338 or earlier. Retail's file held 0 records again, so retail's pins did not change.

After any change to the pins, run `Remove-DuplicatePinQuests.ps1 -WhatIf`, then without `-WhatIf`
if it lists anything. It takes a quest off a pin when a pin with the same giver name within 3 map
points has it too, which would list it twice in one tooltip or show it on two pins side by side.
Where the game has a start point for the quest, the quest stays on the pin nearest it; otherwise,
of pins within half a point of each other, it stays on one. Pins further apart, with no start point
to choose between them, are only listed: a character in a phased story often stands in two places
(Captain Danuvin at Sentinel Hill). A rebuild from clean pins creates no duplicates, but renaming
pins can, as two pins then share a name. It says which rows of `pin-npc-id-decisions.csv` belong to
pins it removed; delete them, or `Apply-PinNpcIds.ps1` stops.

`-Game forever` does the same on `data\forever\pins.jsonl` (step 10, after the import). Forever has no
start points like retail's, so only the half-point rule applies. The importer makes a pin for each
object entry that starts a quest, and CMaNGOS gives some objects several entries of one name, so the
first run, in October 2026, took quest 2933 off 10 "Venom Bottle" pins and quest 926 off one "Flawed
Power Stones" pin, and removed those 11 pins. Since 12 October 2026 the importer applies the same rule before
it writes (`tools\DuplicatePins.ps1`, which both use), so on Forever this takes nothing off and only lists the
one pair of Venom Bottle pins further apart.

Quests that appear in the pin data but are missing from the database are fetched with
`Fetch-GapQuestData.ps1` and added with `Insert-GapQuestEntries.ps1`. Run
`Assemble-PinDB.ps1 -Apply` before inserting, because the inserter uses the new pins. The fetch
keeps each API response in `tools\quest_api_cache`, and the inserter refuses any quest that's
already in the database.

The fetch reads its quest IDs from `tools\gap_quest_ids.txt`, which no tool writes: make it from the quests the pin data names and the data lacks (the rows of `Find-MissingQuests.ps1`'s report whose Sources include `pin`: 261 on retail on 15 October 2026, 156 of them retired), or from the candidates of `Find-MissingQuests.ps1` the user has said to add (below). A quest the Blizzard API has no record of (a 404) is dropped, so a quest only the client or an emulator knows (a new holiday quest, say) goes in through the cache or the probe and a decisions row instead.

**Quests the data lacks.** `Find-MissingQuests.ps1 -Game retail` (and `-Game forever`; report only, about a minute) lists the quests the client's QuestV2 or QuestPOIBlob, the game's newest quest cache, the emulator (TrinityCore, CMaNGOS) or the pins know and the data doesn't hold, and sorts them: task rows (step 6b), tracking and retired quests, internal titles, quests the emulator disables, and the rest with or without evidence that someone starts them (an emulator starter, a start point, a quest line row, an item that starts it). A quest's title comes from the quest cache, then Blizzard's API (`tools\quest_api_cache`, which has a quest the data lacks once `Fetch-GapQuestData.ps1` has asked for it), then the task table, then the emulator. Internal titles are placeholders and tests, `(POC)`, `TO DEPRECATE`, the `LFGDungeons - ` rows, Midnight's `Midnight (90) E` and its other level brackets, and `Prey: Target NN`. Quest lines come from `QuestLineXQuest-<newest QuestV2 build>.csv`. Steps 2b, 2c and 4 (retail) and step 10 (Forever) download that table for the pinned build, so it is missing when a PTR's QuestV2 is the newest, or when step 10 has not yet run on a new Forever build. When that file is missing, each game reads its newest numbered one up to that build; retail, failing that, reads the unnumbered `tools\QuestLineXQuest.csv`, step 7's download, of an unknown build. The items that start a quest (`ItemSparse`) are found the same way: retail has only step 1b's unnumbered `tools\ItemSparse.csv`, and Forever reads its previous build's until step 10 downloads the new one (on 15 October 2026, 131 Forever rows have a start item this way, against 14 from `ItemSparse-1.60.1.70374.csv` alone, which isn't there yet). The run says when it reads another file, or none. QuestV2 alone proves nothing: it omits almost all repeatable quests and lists tracking and retired ones. Look at the candidates, record each reviewed one in `docs\plans\missing-quest-decisions.csv` (Game, Quest, Name, Decision ADD or SKIP, Reason), and add nothing without the user having seen the list. Its baseline is `docs\plans\missing-quests-baseline.csv` (13 October 2026: 555 retail candidates, 130 Forever); it exits 1 on more undecided candidates than that, and `-UpdateBaseline` writes the new counts once they are explained. That baseline's run had no quest line table (its report has no quest line rows). On 15 October 2026 retail has 558 candidates. 11 are new and wait for the user's review before the baseline moves: 10 quest line rows (War Pigs!, Hisingen Blues, The Empty Cradle, four Nightmare Prey quests and three Special Assignments) and 98831 The Labyrinth, which only the 12.1.5.70391 quest cache titles. 93701 Brittle and Brilliant has left the candidates: only the 12.1.0.69933 cache titles it, and the report reads the newest cache, so it is now untitled. Seven more no longer count since the 18 Hallow's End quests of 15 October 2026: the six Horde Candy Buckets are in the data, and 52991 '[REMOVED]' has a `SKIP` row. A quest with no title anywhere (20,341 on retail on 15 October 2026) is mostly a hidden or tracking quest, but 2,099 of them have evidence, among them 95808 and 95812, which only QuestPOIBlob and a pin name; a Candy Bucket the emulator knows but nothing places is the holiday case, which needs the user's list first.

The inserter then files the new quests itself, by running `Place-UncategorisedQuests.ps1` on the
same data. It lists any new quest it couldn't place; those stay in category 0, Uncategorized. That
run covers every quest in category 0, not only the new ones, so it also files older ones it can: on
15 October 2026 it filed 34 (the Chromie Time quests 60959 to 60971 among them), which were put
back, as the pull request was about the new quests only. Check the diff for old rows that moved. New
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

For category 0 it also has a list of name prefixes (`$namePrefixRules`), for a family whose zone text
other families share: "Infinite Research" goes to Timerunning, where the Legion Remix research quests
already are (October 2026). It throws if a rule points at a category no menu entry reaches.

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

Once the inserter has added quests, and `File-WeeklyEventQuests.ps1` has filed them, run steps 2b
and 2c again for them: 2b checks the tables kept by hand and the prerequisites against what the API
says of them, and 2c gives them their prerequisites. Then run steps 2g and 4, for their minimum
levels and storylines, and the probe and step 3, for their types ([The sweep](#the-sweep)).

Merging a category into another is a refile with more to clean up (Darkmoon Island and four one-quest
categories went into their zones on 11 October 2026). Refile its quests first, with `Set-RecordField`
and `Save-QuestData` from `AddonData.ps1`: the target's category and the zone text the target's other
quests carry. Delete its row in `qcQuestCategories`, and point every row of `qcAreaIDToCategoryID`
that names it at the target: the placement rules above find a category through its name and through
those rows, so a row left behind would file new quests under an ID that no longer exists. Then run
`Build-CategoryUiMapIDs.ps1` and `Build-CategoryClientNames.ps1` (step 5), which drop its client-name
row, `Remove-EmptyMenuEntries.ps1`, which drops its menu entry, and `Remove-ConvertedLocaleKeys.ps1`
(`-WhatIf` first), which removes its locale key if it had one and nothing else uses it. To prove that
new quests of the zone go to the target, put the moved quests back in category 0 in a scratch copy of
`data\` and run `Place-UncategorisedQuests.ps1 -WhatIf -Explain` with that `-DataDir` and a scratch
`-ToolsDir` (`-Explain` writes its CSV there).

`Remove-EmptyMenuEntries.ps1` leaves the row of a category it empties, so an entry can come back with
one line, and such rows pile up as unused definitions: no quest carries the ID, no menu entry names it, no
row of `qcAreaIDToCategoryID` has it as a value, and nothing else names it (`qcCategoryClientName`,
`QC_ZONE_EXTRA_CATEGORIES` in `qcContinentPins.lua`, the `systemCategories` list of
`Build-QuestLocationData.ps1` and `Import-RecordedGivers.ps1`, any other category number in `tools\`).
On 11 October 2026 the 82 that had piled up were removed in one pass
([plans/menu-review.md](plans/menu-review.md), question 31): delete the rows, run the generators and
`Remove-ConvertedLocaleKeys.ps1` as above, and prove it with a Lua dump of the menu and of
`qcQuestCategories` before and after, where only the removed rows may differ. `Audit-DungeonCategories.ps1`
then says "no category" instead of "not in the menu" for a dungeon whose unused category went, and
`Place-UncategorisedQuests.ps1` files a quest of an undefined category in category 0.

### 6b. Task quests the database lacks

`Add-TaskQuests.ps1` adds the quests of the client's own task table (`tools\QuestV2CliTask.csv`, step 1b)
that `data\quests.jsonl` doesn't hold: world quests, bonus objectives, world events, Prey and Special
Assignment quests and the like. Nothing else finds them: the pin pipeline takes a quest through a giver
point, which a task quest has none of, and Blizzard's API knows only some task quests (on 12.1.5, 6 of
the 11 new ones and 1,306 of the 5,740 in the data), so neither its quest records nor its area,
category and type lists can find the rest.
Run it with `-WhatIf` first: it prints the counts and the quests it can't place and writes nothing. A
second run adds nothing and changes no byte, and no row that is there is changed or removed. It reads
`QuestV2CliTask`, `QuestInfo`, `SkillLine`, `QuestPOIBlob`, `UiMap` and `ChrRaces` from `-ToolsDir`
(downloaded for `-Build` when missing or with `-Refresh`) and the `retail_quest_cache_<build>.jsonl` of
the newest build, and files the new rows through a scratch copy of the data and
`Place-UncategorisedQuests.ps1`, so no old row is touched.

- **Skipped, in this order:** a row already in the data (even if the client names it a tracker or has
  renamed it); a hidden tracker, a quest the game keeps out of the quest log (`Flags_0` has 0x400, the
  tracking flag, or `QuestInfoID` is 265, Hidden Quest, or the title is exactly "Tracking Quest"); a row
  with no title; and an internal entry ("[DNT] ...", "Test Quest", "(NOT USED)", "[REUSE THIS RECORD]":
  `$internalName` in the script), which a player never meets and the quest list would show, as it showed
  the 22 flagged under decision 20 of [plans/open-items.md](plans/open-items.md). Every skipped internal
  title is printed on each run, so a real quest with "Test" in its name would show there.
- **A new row** carries the client's title and the conventions of the 5,230 task quests the data held on 11
  October 2026, each rule checked against them:

  | Field | From | Agrees with the existing rows |
  |---|---|---|
  | type | weekly flag (`Flags_0` 0x8000) 128; daily flag (`Flags_0` 0x1000 or `Flags_1` 0x8000) 4; a world quest kind (QuestInfo "... World Quest", "World Boss", "Dragonrider Racing") 128; a Calling Quest 4; else 1 | 94% (the rest are old judgement calls: Dungeon World Quests typed 1, seasonal quests typed 64) |
  | faction, race, class | `FiltRaceMasks` and `FiltClasses` as step 1b reads them: Alliance-only is faction 1 with the Alliance's races, Horde-only faction 2, anything else 3; a mask of every race or class restricts nothing | 97% |
  | profession | the skill the quest asks for, else its QuestInfo, as step 1d gives it | step 1d changes nothing afterwards |
  | level | the commonest level of the task quests of ours with the same `ContentTuningID` (the lowest of a tie), else of our quests of that tuning in the retail quest cache, else 0. The API's range is not used: a family with no level of its own is stored 0 and an expansion's quests hold its cap, which is the stored convention (open-items.md, rows 8, 13 and 33) | 99% (each row left out of its own count) |
  | zone | the name of the map most of its `QuestPOIBlob` points are on, else its namesakes' | – |
  | category | a quest whose namesakes all carry one holiday takes that holiday, their category if it is one (Honor the Flame, Bar Tab Barrel) and, with no flag of its own, their commonest type; else `Place-UncategorisedQuests.ps1`; last, the category two or more namesakes share. What is left stays in category 0, Uncategorized | – |

  A new row has no pin, prerequisite, storyline, reputation, minimum level or PvP tag: pins stay out
  (the addon pins no world quest, and the 1,425 world quests already in the data have none either), and
  the rest comes from the steps below on their next run.
- **What the addon does with them.** The quest list hides type 128 (world quests, weeklies) and type 4
  (dailies) by default, so only the type 1 and 64 rows show until a player unticks "Hide World and Weekly
  Quests" or "Hide Daily Quests". The new rows have no pins of their own, so the zone maps show nothing new except that six of them sit on pins that already exist: 49739 shows the Fire Marshal Jill pin that the "no data" filter used to hide, and 56802 and 56818 to 56821 join the Atolia Seapearl pin on Nazjatar. The continent icons count
  from categories and skip types 2, 4 and 128, so no world quest or daily counts, but a type 1 or 64
  row in a zone category does, as the existing one-time task quests do. Category 0 has a menu entry
  under Miscellaneous, so a quest it holds can be browsed to, and every search finds every new quest.
  `Test-QuestReachability.lua` (step 9) must still say 0 quests never shown and 0 in categories the list
  can't browse to.
- **Afterwards,** run these for the new rows, in this order:
  - step 1, whose audit fetches into the cache the API's record of each new row the API knows, and
    checks their faction, race and class;
  - step 1d, which finds nothing: the profession is set;
  - step 2, `Compare-QuestReputation.ps1` and then `Apply-ReputationBackfill.ps1`, for the rewards the
    API lists. After step 6b's first run (11 October 2026, below), step 2 ran before step 1 had
    fetched the new rows' API records, so 11378, 11382, 11386 and 57326 were still without their
    rewards at the 12.1.5 sweep, whose compare (14 October 2026) listed them as `api-only`; step 2
    added them on 15 October 2026. The compare
    counts the new rows with a cache reward on a visible faction in class E (42 on 11 October 2026)
    and the new rows the cache lacks in G (401): they are explained, so rerun it with `-UpdateBaseline`
    (refused, as step 2g's is, while the cache looks partial: step 2e);
  - step 2g, for the minimum levels, and step 2i, `Sync-QuestPvP.ps1 -Game retail -WhatIf` and then
    without `-WhatIf`, for the PvP tag, which it also reads from the task table: on 14 October 2026,
    248 of the data's 5,740 task quests had a minimum level and 52 the tag;
  - step 2c (the prerequisites the client names, 112 of the first run's rows, in #319, and no old row)
    and step 4 (59 storylines for the first run's rows, given at the 12.1.5 sweep on 15 October 2026,
    and no old row);
  - `File-WeeklyEventQuests.ps1 -WhatIf`, then without `-WhatIf` if it lists any: placement files a
    weekly event quest by its zone, and 93598 "Emissary of War" was still under Silvermoon City at
    the 12.1.5 sweep;
  - the probe and step 3, for the types that recur;
  - `Audit-QuestHolidays.ps1` and `Audit-QuestTables.ps1`, which must show nothing new.
- **The first run (11 October 2026, build 12.1.0.69933):** 6,242 rows; 5,230 in the data; 477 hidden
  trackers (470 by the flag, 6 more by QuestInfo 265 and 1 more by the title); 29 internal entries;
  506 added (202 type 1, 7 type 64, 37 type 4, 260 type 128), 41 of them left in category 0 because the
  client gives them no map point. The plan counted about 535 (game-api-review.md, decision 9: the 542
  player-facing rows less 7 trackers that slip past the flag); the 29 internal entries come off those.
  Forever's client has no task table (`QuestV2CliTask` is not among its 613 tables), so the step is
  retail's alone ([plans/game-parity.md](plans/game-parity.md)).
- **The 12.1.5 run (15 October 2026, build 12.1.5.70391):** 6,258 rows; 5,740 in the data; 478 hidden
  trackers (471 by the flag, 6 by QuestInfo 265, 1 by the title); 29 internal entries; 11 added (4 type 1,
  6 type 4, 1 type 128), 2 of them left in category 0 (97219 and 97241, no map point). Step 1 hadn't
  fetched the new rows' API records yet, so the tool filed them by map point, not by API area: 98390
  went to Voidstorm (1508), where its one client point is, but its API area is Silvermoon City, where
  98379 before it is filed, so it was moved to 1512 by hand. `Place-UncategorisedQuests.ps1` refiles
  only category 0, so check each new row's API area once step 1 has its record. Eight are Hallow's
  End quests (Sugar Run x3, A Haunted Home, Candy Crafting x3, Community Candy Crawl). None has a
  namesake in the data, so the tool gave them no holiday, and they were tagged Hallow's End and filed
  under its heading by hand, with `SET` rows in
  [plans/quest-holiday-decisions.csv](plans/quest-holiday-decisions.csv). The evidence is Blizzard's: the
  API's category for four of them; for all eight, world state 1963 in the task table, which only Hallow's
  End's task quests need; and for seven, content tuning 426, whose other 24 quests of ours are all
  tagged Hallow's End. `Audit-QuestHolidays.ps1` sees a new row's API category only once step 1 has
  fetched its record, and the other four have none, so look for a holiday task quest with no namesake
  by hand. Step 1d found nothing, step 2c gave 5 of the 11 a prerequisite and
  changed no old row, and step 4 gave none of them a storyline. The quest cache has none of the 11, so
  `Compare-QuestReputation.ps1` counts them in G.

### 7. Quests that may no longer be obtainable

`Find-UnavailableQuestCandidates.ps1` gathers evidence per quest from the API, the client's tables,
our pins and the probe's saved results on retail (whether the server knows the quest). It's a report
only; see [plans/unavailable-quests.md](plans/unavailable-quests.md). Its summary counts the quests
that have no sign of being live and no decision yet: those are the ones to review, in groups, with
the user.

Before this step, rerun step 1's audit after any pull request that adds quests: the audit fetches
the API records `tools\quest_api_cache` lacks, and this step reads the API only through that cache.

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

An internal or placeholder name ("[DNT]", "[PH]", "TBD", "Unused") is no evidence either, but the user
has twice flagged such quests by name although they fail at least one of them: the internal and test entries
on 5 October 2026, and on 11 October 2026 the 22 placeholder-named quests that still showed in the
default quest list (decision 20 of [plans/open-items.md](plans/open-items.md)). One that a default
filter already hides (a repeatable, daily or world quest) gets a KEEP row instead, and
`Build-UnavailableQuests.ps1` refuses a client task quest unless its row has reason 3, which flags one on purpose (86645 and 94815).

Players who accept or turn in a flagged quest get a chat message, and the quest is recorded in their
`qcFlaggedButSeen` saved variable. Unflag anything reported that way.

The 12.1.5 baseline (15 October 2026: the client's tables of 12.1.5.70391, the API cache of 14 and 15
October, the probe of 15 October): the API 404s on 925 non-task quests, 527 of them with no sign of
being live, 0 of those undecided; 191 are not in `QuestV2`, 34 of them unknown to the server too. The
one undecided quest was 94474 The Great Vault: it is in `QuestV2`, the probe loaded it and the quest
cache holds it, so it got a KEEP row on the user's word, and it moved from Azuremyst Isle to
Silvermoon City, the game's sort for it. Its quest-cache record carries the server's Deprecated flag
(0x4000), the one sign against it. On 15 October 2026 the 29 quests #347 added were missing from
`tools\quest_api_cache`; without them the run counts 943, 530 and 193 and lists 92568, 92570 and
54709 as undecided.

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

It writes `tools\reachability-report.txt`, a report apart from its last check below, listing:
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
- The minimum level, for a character of level 1, 10, 30 and 60 with nothing else in its way: the
  tooltip's "Requires Level" line, the grey pins and the requirements-not-met filter against each
  quest's `minLevel`, else its `level`, in the data file `qcQuestData.lua` was built from. It reports
  quests that need a level the character has, quests that need one it lacks, and pins greyed or not
  wrongly. It checks the opposite mistake too: the low-level filter, and the bracket and sort of the
  list (its first 16 rows in each category), must still follow the quest's own `level`, where 0 or
  below is no level (no bracket, never low). A PvP quest's row has the game's crossed swords
  (`|A:questlog-questtypeicon-pvp:14:14|a `) before its name, after any bracket. Since step 2g retail's two levels differ for 1,627 quests,
  so both games' runs can catch a mix-up there (with the requirements filter ignoring `qcQuestMinLevel`,
  retail's run finds 2,828 problems; with the grey pins and the tooltip line ignoring it, 6,748). Made-up quests with those levels check the same, and the
  minimum level at 0, apart from the data (33 checks). The summary has one line per level and one for
  the made-up quests, and each must read 0. A wrong reading prints `FAILED` and ends the run with
  exit status 1.
- The line an empty quest list says. When the filters hid every quest of the selected category, the
  list says how many ("Quests hidden by your filters: 22", `qcL.QUESTSHIDDEN`, drawn by
  `qcShowHiddenQuests` in `qcCore.lua` into `qcHiddenQuests`, a one-line text over the list's first
  rows in `QuestCompletist.xml`). It counts the category's whole quest list only when that list is
  empty, so a list with rows costs nothing; a search, a category with no quests and a list with rows
  say nothing, and the header's "x/y Complete" and the rows are as before. Made-up quests in made-up
  categories, each kind hidden by one of the list's 13 filters (and one by two), check the line against
  the number the real filter hides, with that filter on and with all of them, then with a search, a
  redraw and a change of filters in between; every category of the data is then listed at the default
  settings and its line, its hidden count and its header are checked (1,026 checks on retail, 292 on
  Forever, on 11 October 2026). The report ends with the categories whose list is empty by default for
  the made-up character, a Horde Blood Elf Death Knight (61 of retail's 480, 15 of Forever's 113). A
  wrong reading ends the run with exit status 1, as the level checks do.

It assumes best-case progress: max level (but for the minimum-level check), prerequisites done, max
renown, every profession. The quest search finds every quest by name whatever this reports. Some
results are expected. Pins whose quests aren't in the database stay hidden while "hide quests with
no data" is on. A map missing from `UiMap.csv` can't be opened on retail; a newer build than the
downloaded one may add it.

This checks retail's files. Step 10 runs it on Forever's.

### 10. WoW: Forever

The Forever version loads through `QuestCompletist_Camelot.toc`, with the shared code and its own
files in `QuestCompletist\Forever\`. Its plan, with what each run so far found, is
[plans/forever.md](plans/forever.md). Run these in order, with the main checkout's `tools\` as
`-ToolsDir` and, if it isn't the newest probe results' build, Forever's build as `-Build`:

1. **The recorder's notes, every time.** Copy the probe's saved variables, `QCForeverProbe.lua`,
   from the Forever client into the newest `tools\forever_probe_<build number>\` (see
   [In the game](#in-the-game), step 5), and the addon's file for Forever into
   `tools\recordings\own\forever\` (see "In the game"). Both recorders add to their file whenever you
   play, so this brings in the quest givers you've met since the last sweep. Log out or `/reload`
   first, so the game has written them. Then run step 6d: it keeps the notes of every probe file in
   `tools\` and of the addon's own file in the ledger, and **the importer (item 4) takes its recorded
   givers, where they stood, their names and the quests they offered from the ledger alone**; the
   probe's file is read for the game's answers and NPC names only. If the probe's file holds a giver,
   place or offer the ledger lacks, the importer stops before it writes anything and says to run 6d.
   Only the probe's file is checked: the addon's file and players' files are not, so it is running 6d
   first, as here, that brings their notes in. A quest this import adds can't have its recorded offers
   in the ledger until 6d has read the new data; the review lists them as "recorded offer not in the
   ledger yet": run 6d and the import again. **On a new Forever build** 6d needs
   `tools\UiMap-<build>.csv`, which only the importer (or a download by hand from wago.tools) makes, so
   the order is: the import (item 4), which fetches the client tables and then stops at the ledger
   check; step 6d; the import again. If none of the file's notes is of a version the TOCs name, 6d leaves
   the probe's file unread ("Not read" in its report) and the importer stops, until the version is
   passed to both with `-Builds`. A file that mixes a named and an unnamed version is read in part by
   both and does not stop: the unnamed version's notes are left out, so pass `-Builds` whenever the
   beta's version changes. The import's "Recorded givers:" summary line says what the ledger gave: 78
   givers with a place, 78 places and 98 quests with an offer, and no row waiting for a second source, on
   build 70374 on 14 October 2026.
2. **The probe**, when Forever has a new build, the beta opens higher levels, or the probe's quest
   list has grown: see [In the game](#in-the-game). Otherwise the last run's results stand. Every
   probe run includes the map pass (step 3b there), and the reader's totals are compared with the
   last run's in [game-api-review.md](plans/game-api-review.md), "Map-offers probe": on build
   70245, no quest offers, 16 points of interest, no events, no dungeon entrances and no level
   ranges. A rise in any of them is a finding to plan, as a new client table is (step 2b under
   "Before a sweep"): offers would become start points for quests with no giver.
3. `Read-QuestCache.ps1 -Build <build>` reads the probe folder's copies of the game's quest cache
   (every `questcache*.wdb` of the build in the `forever_probe_*` folder that holds the newest of them,
   joined as step 2e describes) into `tools\forever_quest_cache_<build>.jsonl`. If a single record
   doesn't read exactly, it writes nothing: Blizzard has changed the record's layout, and the reader
   needs updating. (The same script reads retail's cache, from a retail build number: step 2e.)
4. `Import-ForeverData.ps1 -Build <build>` writes `data\forever\quests.jsonl`, `pins.jsonl`,
   `links.jsonl`, `reputation.jsonl` and `skills.jsonl`, and the review list,
   `tools\forever_import_review.csv`. It downloads the client tables and the CMaNGOS dump it doesn't
   have. Compare its summary with the last run's in the plan, and look through the review list for
   new rows: quests the game hasn't confirmed, quests with no known giver or no pin, and places
   where CMaNGOS and our old Classic pins disagree.
   Breadcrumbs and the groups of quests of which only one can be done come from CMaNGOS, without
   recurring quests, with the links a hand list adds and less those it removes (below). A quest is
   also a breadcrumb of the quest its CMaNGOS `NextQuestInChain` names, unless that one needs it done:
   the server closes it once that quest is taken or done (141 on builds 70338 and 70374, the summary's "closed by
   their next quest in the chain"). The summary's "Storylines:" line is a watch on the client's `QuestLine` and
   `QuestLineXQuest` tables, the only source of Forever's storylines: on builds 70205 to 70374 they had 3 and 22
   rows, so 11 of our quests were in 1 storyline. A rise in any of them means Blizzard has started to
   fill them in, and the menu and the quest list's storyline lines then have something to show.
   A quest's prerequisite is CMaNGOS's requirement, as its server checks it: its `PrevQuestId` or any
   quest whose `NextQuestId` names it, a negative `ExclusiveGroup`'s whole group, and a
   `RequiredCondition` that asks only for quests handed in, written as a list where it needs all of
   several quests (`[7791,7793,7794]`) or one of several (`[[994,995]]`). A negative `PrevQuestId` or
   `NextQuestId` means the quest is offered only while that one is in the log: `links.jsonl` gives it as
   `needsInLog` (35 quests on builds 70338 and 70374, the "Links:" line's last number), which becomes
   `qcQuestNeedsInLog`. A requirement neither can hold (an aura, an area, the war effort's collections)
   is left out and listed in the review as "CMaNGOS requirement not a prerequisite" (82 conditions on
   builds 70338 and 70374). A quest CMaNGOS gives no requirement takes the quest whose follow-up it is in the
   cache, when only one names it.
   A quest with no prerequisite from CMaNGOS or the cache's follow-up links gets the quest before it in
   its quest line (the client's `QuestLineXQuest` order) when that one is handed in on the map this one
   starts on (the client's `QuestPOIBlob` points -1 and 32), which is the case for the ten steps after
   the first of "Toxic Soil", quest line 6026 (92742 to 92819, Westfall, Stormwind and Elwynn). The
   summary's "Prerequisites:" line counts them (2,399 quests, 126 of them lists, 2,175 from CMaNGOS's
   requirement and 34 with its condition, 10 from the quest line order and 20 from the hand list below,
   which removes 15, on build 70374 on 14 October 2026), and the review lists each as "prerequisite from the quest line order", a line whose places
   don't match, or that the hand list removes, as "quest line order not used", and one that disagrees with another source as
   "quest line order disagrees with the prerequisite". Look at all three after an import: a rise in
   the first means Blizzard filled in more quest lines. Reputation comes from the game's records only: CMaNGOS's amounts are mostly The
   Burning Crusade's, larger than Classic's. The summary counts the quests the game hasn't answered
   that reward reputation in CMaNGOS; they get theirs once it answers. Its "Reputation:" line read 2,354
   rewards on 1,871 quests, with 1,000 quests waiting, on build 70374 on 14 October 2026.
   The level a character needs to take a quest (`minLevel`) is the game's, else CMaNGOS's
   `MinLevel`, as given; it is kept only where it differs from the quest's own level (`level`), and
   builds into `qcQuestMinLevel` (see the data files above). The summary's "Minimum levels:" line
   counts them: 4,202 quests, 2,483 from the game and 1,719 from CMaNGOS, 26 of them above the
   quest's level and 4 at 0 (no minimum), on build 1.60.1.70374 on 14 October 2026 (4,194, 2,462,
   1,732, 26 and 4 on build 70338; 4,180, 2,436, 1,744, 26 and 2 on build 70205).
   The profession a quest needs, and the skill level in it, come from CMaNGOS too: the game's
   records only say what skill a quest rewards. The summary's "Skills:" line counts them, 141
   quests, 102 of them with a level above 1, in October 2026.
   The client's `QuestV2` isn't a list of every quest. It lists the quests the game records as
   completed, so it leaves out repeatable ones. The importer keeps CMaNGOS's repeatable quests
   without it; any other CMaNGOS quest it lacks comes in once the probe gets an answer for it. The
   review list names each kept quest `QuestV2` lacks. A quest `QuestV2` lacks that the beta refused
   at level 1 to 35, where it answers nearly everything, is left out until the server answers it.
   The beta's answers differ between runs (about 80 of 7,320 quests each time), so the importer
   keeps the game's last record of every quest it has ever answered, with the number of runs in a row
   it has gone unanswered, in `data\forever\answers.jsonl` (a run is one client build's quest cache;
   a quest the probe didn't ask about isn't counted). A quest not answered now keeps its last record
   and the review lists it as "kept from an earlier run"; only after `-MaxMissedRuns` (10) runs in a
   row does it stop being imported. With no answers file it is made from the `forever_quest_cache_<build>.jsonl`
   files in `tools\`, so keep each run's. The summary's "Answer memory:" line counts them.
   `Sync-QuestPvP.ps1 -Game forever` (step 2i) reads the same file, through the same code in
   `ForeverAnswers.ps1`, so a quest kept from an earlier run gets the same PvP answer from both. It doesn't
   make a missing file from the caches, as the importer does: it names the file as skipped.
   **No quest leaves the data unseen.** Before it writes anything, the importer compares its quests
   with `data\forever\quests.jsonl` and stops, writing nothing, if any would go (ten missed runs, an
   internal title, a CMaNGOS change): it lists them, with ID, name and zone, in the output and in
   `tools\quest_removals_forever.csv`. Show that list to the user. Then add a row for each to
   `docs\plans\quest-removal-decisions.csv` (`Game`, `Quest`, `Decision`, `Reason`): `REMOVE` once the
   user has agreed, or `KEEP`, which keeps the quest from its last record whatever else would drop it.
   A quest with no giver on a map gets a pin at its start point in the client's tables, when it has
   one. The summary counts those start points, and the quest records that name their giver. Both
   are nearly empty in Forever so far, so a rise means Blizzard has filled in more.
   Pins follow the same rule as retail's ([plans/game-parity.md](plans/game-parity.md)): a normal quest
   gets a pin at every place a source puts its pickup, named after the giver when one stands there and
   nameless otherwise, with one nameless pin per 1.5-point spot (`tools\PinRules.ps1`, shared with step 6).
   On build 70374 that changes nothing: the 11 quests pinned at their start stand on 4 pins, the quests of
   each at one point, and no two of the 4 are within 1.5 points. A quest whose giver turns up later
   leaves the spot for its giver's pin at the next import. Forever's sources are CMaNGOS's creature and object givers with their spawns,
   the recorder's places, the hand list and the client's start points (point 32 first). A giver the
   ledger has a trusted place for stands there instead of at CMaNGOS's spawns, and its places within
   1.5 map points of each other (the merge tool's test) are one pin, two places further apart are two. It has no
   equivalent of retail's TrinityCore start table, as CMaNGOS's `quest_poi` holds no point 32 and its
   point -1 is the hand-in, and it has no world quests to leave out. Its pinless quests, by cause in
   the review list of 14 October 2026 (build 70374), are 1,424 of the 5,105: 1,238 "no giver" rows
   (969 that only the game knows, with no giver and no start point, 197 started by an item and 72 that
   CMaNGOS gives no giver) and 186 "no pin: giver not on a Forever map" rows (6 October's 189 were 142
   whose giver stands only inside instances, 46 whose giver has no CMaNGOS spawn and 1 off every
   Forever map). Compare each import's pinless count and causes with these: a start point, recorded
   place or spawn that turns up for one of them is a pin the importer already makes.
   A quest whose givers, NPCs and objects, all stand only during one of CMaNGOS's game events gets
   that event's holiday, so its pins follow the calendar. Events with no holiday of their own go by
   their description: the Darkmoon Faire's building days, the fishing contest's announcers and
   judges, and the Scourge Invasion and Ahn'Qiraj War Effort, which the calendar doesn't show, so
   their quests stay off the map. Recurring quests keep their type: a repeatable holiday quest is
   repeatable, as on retail, and any other holiday quest is seasonal (type 64), so tagging an
   ordinary quest changes its type from 1 to 64.
   A quest under the heading Ahn'Qiraj War is the war effort's, and one CMaNGOS files under
   Invasion is the Scourge Invasion's; Forever's own Invasion quest (98471), which CMaNGOS lacks,
   is neither. The seasonal quests no event or heading reaches get their holiday by hand, from
   `docs\plans\forever-quest-holiday-decisions.csv` (quest, name, holiday, decision `SET`,
   evidence): the 12 orphan quests of Children's Week, which orphans with no CMaNGOS spawn start,
   and 6 Winter Veil quests the game files under Seasonal. The holiday is a name in `qcHolidays`,
   and each row says what the tag rests on. The review list names a row that another source also
   tags ("hand-kept holiday not needed") or tags otherwise, and one whose quest isn't imported.
   Links CMaNGOS gets wrong are corrected by hand in `docs\plans\forever-quest-link-decisions.csv`
   (quest, name, link, other quest, decision, evidence). A `prereq` row `SET`s the other quest as
   the quest's prerequisite, over any other source's: a lead-in CMaNGOS has only as a breadcrumb,
   or a quest it doesn't link at all, though the server won't offer the quest without it. Several
   `SET` rows for one quest are a choice, any one of which will do (`[[1639,1678,1683]]`). A
   `prereq` row can also `REMOVE` the prerequisite the other sources give, mostly a breadcrumb the
   cache's next quest made one, and the quest line order then doesn't put it back. An `exclusive`
   row `ADD`s or `REMOVE`s a pair of an "only one of these" group, both ways round. A `breadcrumb`
   row `ADD`s the other quest to the quest's breadcrumbs, the quests it closes once done: the addon
   ticks them at its hand-in, and the quest window's notice lists those still to do that the character can take. The first
   rows come from the beta on 11 October 2026: Snatch and Grab (2206) needs Seek out SI: 7 (2205),
   Destiny Calls (2242) needs The Apple Falls (2241), the three cities' rogue lead-ins (2205, 2218
   and 2241) don't shut each other out, and Bounty on Murlocs (46) needs Deliver Thomas' Report
   (39). The same day's review of the other CMaNGOS links ([plans/forever.md](plans/forever.md)) added 71 rows: the
   level 10 warrior and mage lead-ins don't shut each other out, the quests they lead to do and
   close every lead-in, and the steps after those take any of them; Securing the Supply Lines
   (8280) isn't shut out by its own breadcrumbs; the two first steps of the shamans' Call of Earth
   (1516, 1519) shut each other out; and 13 quests lose a prerequisite or get another. Two more keep
   The Battle of Alterac (7141) and The Battle for Alterac (7142) open, as no one gives the lead-ins
   CMaNGOS makes them need (7221, 7222). Each row
   says what it rests on: a test in the game first, then first-hand reports such as Questie's
   issues and Wowhead's comments, as our own data can't show what the server does; a row that
   rests on less says so ("taken to", "no first-hand report"). The review list names a row whose
   quests aren't imported or recur, a link another source already gives ("hand-kept prerequisite
   not needed", "hand-kept breadcrumb not needed", "hand-kept link not needed") or a prerequisite it
   gives otherwise, and a removal with nothing to remove. `Build-ForeverMenu.ps1` also writes the
   quests of the `exclusive` `REMOVE` rows into `qcFormerlyExclusive`: the addon ticked them when
   another quest of their group was handed in, so until 1 April 2027 the login sync drops such a
   tick when the server doesn't confirm it ([releasing.md](releasing.md), "Dated changes"), and the
   links that remain then tick back what they still close.
   A quest's class is the game's where it gives one, as the game's quest records carry none: a class
   heading or, for a quest that no NPC or object starts, the items that start it, when the client's
   `ItemSparse` lets only some classes use them (Foror's Compendium, 7507, for warriors and paladins).
   CMaNGOS's class comes next. A quest only the game knows that it files under a zone is for every class
   unless `docs\plans\forever-quest-class-decisions.csv` (quest, name, class, decision `SET`, evidence)
   says otherwise, over every other source: Zephras Isle's Call of Earth (92466 to 92468), for shamans.
   The class is one or more of the client's class names, separated by commas, and each row says what it
   rests on, as the link list's do. A quest whose only prerequisite is for some classes is for them too,
   down the chain, as the addon counts a prerequisite the character can't take as met. The summary's
   "Classes:" line counts them: 888 quests for some classes only, 1 from its items, 2 from their
   prerequisite and 3 by hand, on build 70338 on 11 October 2026 and again on build 70374 on 14 October.
   The review list names each change
   ("class from the items that start it", "class from its prerequisite"), an item's class a giver makes
   moot, and a row another source already gives or contradicts.
   A giver no source has, like those of most of Forever's new quests, can be looked up by hand on
   Wowhead's Forever pages and added to `docs\plans\forever-quest-givers.csv` (quest, NPC, name,
   note, an optional decision). The NPC stands where CMaNGOS or the recorder puts it, and the recorder wins when it saw
   another giver offer the quest. A row whose Decision is REMOVE takes the NPC off the quest instead, for a starter CMaNGOS has the wrong way round (26 and 27, A Lesson to Learn, whose givers classic-db update 4777 swaps). A quest filed under a heading that isn't a place, a race's (Night
   Elf), Treasure Map, Epic or Legendary, goes under a zone instead: the one
   `docs\plans\forever-quest-zones.csv` gives it by hand (quest, zone's `AreaTable` ID, name,
   note), else its pins' zone, else the zone of the NPC CMaNGOS has it handed in to, else
   CMaNGOS's. The review list says which, and flags a listed zone that isn't used. The Commendation
   Signets' turn-ins, which CMaNGOS files under Reputation, go under Ahn'Qiraj War with the rest of
   the war effort: its supply quests give the signets, and its officers take them.
5. `Build-ForeverMenu.ps1 -Build <build>` writes `QuestCompletist\Forever\qcMenu.lua`, `qcQuest.lua`
   and `qcUnavailableQuests.lua`. `qcQuest.lua` takes in `links.jsonl` (breadcrumbs,
   `qcMutuallyExclusive` and `qcQuestNeedsInLog`), `reputation.jsonl` and
   `skills.jsonl`, with the factions' English names from the client's `Faction` table, and the
   quests of the link decisions' `REMOVE` rows as `qcFormerlyExclusive`. A new zone
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
   show: 23 of the Scourge Invasion's and 58 of the Ahn'Qiraj War Effort's. That includes the four
   "character level" lines, the minimum-level check, and the "made-up quests" line (0 of 33 checks wrong),
   which fail the run when one isn't 0.
8. `Audit-QuestTables.ps1 -Game forever` ([2b](#2b-the-tables-kept-by-hand)): the consistency checks on
   the quests' prerequisites and the breadcrumb and "only one of these" tables the import generated. The
   run of 14 October 2026 (build 70374) found 6 on 2,399 prerequisites and 447 table entries (35 of them
   quests that need another in the log), all kept in `docs\plans\forever-quest-table-decisions.csv`: one
   prerequisite that names the other faction's quest (3647 needs 3643), two that name another profession's
   quest (769 and 5124, waiting for evidence), and three that name a repeatable one (3638, 4001 and 5125;
   3638's as one of a choice). No row of that file is out of date. The other faction's prerequisites of 28
   and 29 went with the data-sources review's D7 on 13 October. The first run, on 9 October, also found a quest whose own
   record in the game names itself as its next quest (92727, which the importer no longer takes as its
   previous quest). Anything new is a finding to look at before the pull request: the run exits with 1.
9. `Remove-DuplicatePinQuests.ps1 -Game forever -WhatIf` (see step 6), as a check. Several CMaNGOS
   entries of one object give pins of one name at one spot (Venom Bottle, Flawed Power Stones), and the
   importer applies this tool's rule before it writes, so it should take nothing off and list only the one
   pair of Venom Bottle pins further apart. A quest it would take off means the importer and the tool
   disagree: find out why before running it without `-WhatIf`, which rebuilds `qcPinDB.lua` itself.
10. `Sync-QuestProfessions.ps1 -Game forever` (see step 1d), report only: the quests filed under a
   profession's heading in Forever's menu whose profession, from CMaNGOS, is another. On 12 October 2026
   its 114 quests under the nine profession headings all had their heading's profession.

With the same sources, a rerun writes the same `quests.jsonl`, `pins.jsonl`, `links.jsonl`, `reputation.jsonl`,
`skills.jsonl` and `answers.jsonl` byte for byte; `Test-ForeverImport.ps1` checks it on its own small world. So
whatever changes in them comes from the game, the client's tables, CMaNGOS or the ledger, and is for review
before its pull request. Until decision 36 of
[plans/open-items.md](plans/open-items.md) is taken, the ledger can move a pin with nothing new seen: it sums a
place's visits over every probe file read, and the probe's file is cumulative, so the same visits count once per
file and can make the other of two rows 0.1 apart the place. That is how Thundris Windweaver's pin (map 1439)
went to 37.4,40.2 on 12 October 2026. He now stands at 37.4,40.1 by the same visit sum (22 against 15), where
the addon's file and the newest probe file saw him more often. The committed `pins.jsonl` is the import of
14 October 2026 (build 70374, with the ledger at 326 Forever rows), which the user reviewed and accepted pin
by pin. It moved 26 pins and added 5. 21 givers new to the ledger moved to their recorded places: 20 by 0.02
to 0.26 of a map point, and Darcy in Lakeshire by 1.1 (she walks a path, and her CMaNGOS spawn is one end of
it). 4 givers the ledger already had moved 0.1 to 0.14 to the row seen more often, and Gubber Blump, whose two
rows now tie at 6 visits, to the lower one (36.1,44.9). The 5 new pins are for
quests only the game knew: four givers in Elwynn Forest and the Wanted: Incinerator Gar'im poster in
Redridge Mountains (see the status of 14 October in [plans/forever.md](plans/forever.md)). A giver the
recorders meet later moves its pin the same way, because the recorder keeps where the player stood: the
first import after the ledger grows moves such pins, and the review list's "recorded spot far from CMaNGOS"
names a giver more than a point off. That place still wins over the spawn (decision 38 of
[plans/open-items.md](plans/open-items.md), taken 12 October 2026), so the row is there to be looked at,
not to undo the move.

## Text in other languages

Names come from the game in the player's language: quests, NPCs, factions, maps, and the categories
and menu headings of steps 5 and 10. The addon's own text is in
`QuestCompletist\Localization.<language>.lua`.

- `Localization.enUS.lua` has every key in English. Each other file sets the keys it translates,
  and any key it lacks shows in English.
- Text the game already has comes from the game, in its words: "Search" (`SEARCH`), "Search Results"
  (`SPELLBOOK_SEARCH_HEADER_RESULTS`), the quest tooltip's "Storyline" (`QUEST_CLASSIFICATION_QUESTLINE`) and "Campaign"
  (`QUEST_CLASSIFICATION_CAMPAIGN`), its "Type" row (`TYPE`, the game's classification and tag names, and
  the storyline's name where the game's quest line is ours: step 4),
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
  English name's letters and digits, upper-cased, such as `AHNQIRAJWAR`; one it names needs
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

Seasonal quests need no yearly upkeep, except WoW's Anniversary, whose calendar event is a new row
every year: step 2b of the sweep reports the new row, and its ID goes into the entry (below). The
Skyriding Cups are matched the same way, so a cup Blizzard adds as a new row (the Pandaria and
Broken Isles Cups have names in the client's tables but no rows yet) is reported too. The
map's seasonal filter asks the game's calendar which holidays are running, and `qcHolidays` in
`qcCore.lua` ties each holiday value in the quest database to the IDs of the game's Holidays table
that its calendar event carries. The filter is the map's alone: the quest list keeps holiday quests
in their own categories. A pin is drawn while any one of its quests passes the filter, so a pin that
holds a tagged quest and ordinary ones stays drawn out of season, and only a pin whose quests are all
tagged, for holidays that aren't running, goes. On 9 October 2026 quest 81561 stood on three such
mixed pins, and 11882 on one of its 8 pins; since the cups' quests were tagged (#310), 81561's three hold
tagged quests alone, so 11882 is the only quest of a `SET` or `CORRECT` row with such a pin (recounted
on 12 October 2026, #315). Stacked pins are drawn as one while any of them is: on
Tanaris, three anniversary pins (47254's, Chromie's and Yllana's) share a stack of seven with
Bobadormu's pin, which holds the weekly Timewalking quests 83274 and 85947 (untagged, the user's
decision of 12 October 2026), and Alyx's three, whose Guest Relations quests are WoW's Anniversary's
since #314, so out of season the stack stays, under Bobadormu's name, with the two weekly quests alone.
In Ahn'Qiraj: The Fallen Kingdom, the pins of two Call of the Scarab turn-ins (45747 for the Horde and
45755 for the Alliance, each holding its quest alone) stack with Windcaller Yessendra's, whose quests are
untagged, so out of season her pin stays, under her name, without the turn-in.

`/qc holidays` in game lists what the filter sees: which of the holidays this game's quests have are
running, each one's next dates, and any calendar holiday that isn't tied to a quest. Retail's list
now includes Pirates' Day, because 42758 is the first retail quest tagged with it, and the Moonkin
Festival and Hearthstone's 10th Anniversary, whose quests were tagged on 10 October 2026 (47430,
and six Hearthstone quests, two of them pinned), and WoW's Anniversary and the Skyriding Cups,
whose 19 and 16 quests were tagged on 11 October 2026 (twelve of the cups' pinned). Since 12 October
2026 (#314) it also includes Dastardly Duos and The Great Gnomeregan Run, whose 11 quests and one
were tagged that day (six and the one pinned), and the Scourge Invasion and the Ahn'Qiraj War Effort,
whose 11 and 43 retail quests (none pinned) were tagged with them that day; the 57 Guest Relations
quests took WoW's Anniversary, which now has 76 quests, 52 of them pinned. Later that day (#315)
Call of the Scarab joined them, with its 18 quests (the 16 turn-ins pinned), and left "Other calendar
holidays". Each entry's line is the soonest event of any of its IDs, under that event's own name and ID, and under
it a line for each other ID of the entry that the calendar has in its 12 months, soonest first, so
each ID can be confirmed in game (Hallow's End's 324 and 1405, Love is in the Air's 423 and 335, the
Darkmoon Faire's 479, 263 and 264, Hearthstone's 10th Anniversary's 1462 and 1578, the Skyriding Cups' four). Until 12
October 2026 it printed the soonest alone, so an entry with several IDs showed only its next one. A
holiday there that should match one of ours, under a new ID, means an entry in `qcHolidays` needs
that ID adding. Sweep step 2h prints what the list should be, from the tables, to set beside it.
Step 2b of a sweep finds the same offline, from the client's Holidays and HolidayNames tables: for
each entry in `qcHolidays`, every ID the client has under that name in either game, against the
IDs the entry lists; for WoW's Anniversary, every row named "WoW's <ordinal> Anniversary" that runs
today or later, and for the Skyriding Cups every such row named "<Region> Cup". A new holiday
with quests needs a new flag, an entry, and its quests' `holiday` set in `data\quests.jsonl`. Forever's quests get theirs from the importer, through its own table
from Holidays IDs to flags, so add the ID there too and rerun step 10. The importer also tags by
heading (Ahn'Qiraj War, and the quests CMaNGOS files under Invasion) and by a small hand list,
`docs\plans\forever-quest-holiday-decisions.csv`, for quests that no event reaches; a new
holiday's quests that need it go in that list, with their evidence.

Retail's `holiday` values are hand data: no tool writes them (Forever's come from the importer
and its hand list).
They live in `data\quests.jsonl` and are changed there, by hand or through `AddonData.ps1`
(`Read-QuestData`, `Set-RecordField` and `Save-QuestData`, which rebuilds the Lua as it saves).
`Build-AddonData.ps1` rebuilds the Lua from the file and checks the records, and its `-Check` says
whether the Lua still matches. Every decision, with its evidence, is in
`docs\plans\quest-holiday-decisions.csv`, one row per quest: `SET` rows are quests given their
holiday, `CORRECT` rows tags that were wrong (with the category and zone text each moved to), `KEEP`
rows tags and omissions checked and left as they are, and `PENDING` rows quests that may belong to a
holiday and are left untagged until someone decides. Read the file for what is pending; this page
doesn't count it (no row has been since the user answered decision 10 on 12 October 2026, #314). A
pending row says why: it is undecided because the holiday has no flag in `qcHolidays`, the flag has no
calendar ID in this game, or the evidence is doubtful.

In that file, `Cur` and `Target` are the holiday value before and after (on a pending row, the value
the quest would take, blank when no flag exists). `CurCategory`, `TargetCategory`, `CurZone` and
`TargetZone` are filled only on the rows that change them. `Pins` is the number of pins in
`data\pins.jsonl` that hold the quest, and `PinsAllYear`, on `SET` and `CORRECT` rows, how many of
those also hold a quest with no holiday, so stay drawn out of season. The evidence says who
decided: "Approved with the group" for the tagged quests the user approved as a group, not one by
one, "The user ruled" for quests the user said belong to a holiday, "Left out by the user's
decision" for judgment calls the user left out, "Not decided", or, on `KEEP` rows, "Checked". The rows
of decision 10's answers keep the evidence they had while pending and add "The user's decision of 12
October 2026 (decision 10 of open-items.md)" with the user's words and the reason: 123 `SET` rows and
76 `KEEP` rows, the `KEEP` rows with `Cur` and `Target` both 0 (77 until 15 October 2026, when #347
tagged the Candy Exchanges 92567 and 92569 and added a row for 93598, filed with the weekly events).
The 18 `SET` rows of decision 35's answer (Call of the Scarab, #315) give the user's words and end
"The user's decision of 12 October 2026 (decision 35 of open-items.md)." The counts were recounted for every row on 12 October 2026 (#315):
25 older rows were out of date, as pins came after them (the 12 Bar Tab Barrels, the 8 "Desecrate this
Fire!" rows, 11886, 11964, 11966 and 82672 in `Pins`, and 81561 in `PinsAllYear`). A pin added or
removed later leaves a row's counts as they were until the next recount.

The evidence a tag rests on is Blizzard's API quest category when it is the holiday's own (the
general "Seasonal" one names none), TrinityCore's `game_event_*_quest` and
`game_event_seasonal_questrelation` tables, quests of the same name, the quest's description and
reward, and an achievement the quest is a criterion of, when the achievement's event is the holiday.

Step 2d checks that retail's holiday tags are complete and right, against the API's quest category,
TrinityCore's events and the quest's heading; step 9 only checks that each value is in `qcHolidays`,
and step 2b the IDs in `qcHolidays` against the client's calendar tables. A holiday quest that
appears without a tag shows its pin all year until step 2d reports it and it is tagged. Step 6's
TrinityCore placement already leaves out any quest with a `holiday` value, the holiday categories
(31, 37, 46, 50, 90, 126, 127, 133, 145, 153, 413) and quests whose type isn't 0, 1, 2, 4 or 128, so
tagging an ordinary quest that has no pin also stops that step placing one for it. On 9 October 2026
that changed nothing: of the quests tagged that day without a pin, none would have been placed by it
anyway, since the rest were skipped already or TrinityCore has no start point for them. Nor on 12
October 2026 (#314), measured by running step 6's placement on scratch copies before and after: of
the 72 quests tagged that day with no pin, 24 (15 of the Ahn'Qiraj War Effort, 9 of the Scourge
Invasion) have a TrinityCore start but are disabled in TrinityCore, which the placement skipped already,
and the other 48 have none; no location changed. Nor for Call of the Scarab's two quests with no pin
(#315), measured the same way: TrinityCore has a start for 45785 in Silithus but no giver, so the
placement skipped it already as auto-accepted with no giver (it now skips it as a holiday quest), and
none for 45787; `quest_locations.csv` and the review file came out the same. The client's own points
place a tagged quest as before.

Some events aren't on the calendar at all. The Scourge Invasion and the Ahn'Qiraj War Effort have
entries in `qcHolidays` with no IDs, so the seasonal filter always hides their quests on the map, and
the continent icons don't count them; the quest list still has them. They were Forever's until 12
October 2026, when retail's 11 and 43 quests of the two events (Blizzard's API files them under
Invasion and Ahn'Qiraj War, which step 2d reads as the two entries) took them too, the user's answer
to decision 10 (#314); none of retail's has a pin. `/qc holidays` says they're not on the calendar, and
step 2b that no row of their names exists. If Blizzard ever adds one to the Holidays table, step 2b reports its ID,
step 2h's `no-row` facts for them go from holding to failing, a finding (`calendar-decisions.csv`), and in game it shows up as a
calendar holiday not tied to a quest: add its ID. Retail has the same
problem with the Stranglethorn Fishing Extravaganza: `qcHolidays` carries it for Forever (event 301),
but retail's Holidays table has no such row, so a retail quest tagged with it would be hidden for
good, and its seven retail quests stay untagged for that reason (`KEEP` rows, the user's decision of
12 October 2026).

Forever's calendar, in its Holidays table (the same in builds 70245, 70291, 70338 and 70374; dates
decoded by hand at first, by step 2h's review every sweep since 12 October 2026): Children's Week (201)
has dates only in 2023, 2024 and 2025, so the calendar has none to show and its pins stay hidden
until the game dates it again (the two matron quests, 172 and 1468, hold the only two). Winter
Veil (141) is dated from 15 December for 18 days, and `/qc holidays` on the beta showed it so on 11 October 2026 (15 December to 2 January). A row with no name, 1879, is dated from 15
November for 61 days in the table, but that check did not list it under "Other calendar holidays", so
the game does not serve it and nothing was added to Winter Veil's IDs in `qcHolidays`
([open-items.md](plans/open-items.md), decision 12). Its Flags (3) keep it off the calendar, and
`calendar-decisions.csv` holds that check in game as a fact, with the Flags step 2h checks every
sweep, as it checks that Children's Week and the Darkmoon Faire (263 and 264, which hold no date at
all) still have no date to come. On 11 October 2026 the 29 seasonal quests
that had no holiday were tagged (351 Forever quests have one now); none of the 29 has a pin, so the
filter changes nothing on the map for them, and the quest list never applies it.

Hearthstone's 10th Anniversary is on retail's calendar for 2024 only. The client's Holidays table has
two rows under that name, 1462 (from 11 March 2024) and 1578 (from 26 September 2024, one region),
and none for a later year. Its entry lists both, so its pins stay hidden until the game dates the
event again, and `/qc holidays` says it isn't on the calendar in the next 12 months (it did so on
retail on 11 October 2026). A later anniversary would be a row under a new name, which step 2b
doesn't match to this entry: it shows in `/qc holidays` under "Other calendar holidays" and in step
2h as a new event no entry covers, and its ID goes into this entry. If the two rows are dated again,
step 2h reports each row dated to come again and the decisions file's `no-date 1462 1578` going from
holding to failing, both findings. Step 2d reads
Blizzard's quest category "Hearthstone Anniversary" as this entry through an alias in
`Audit-QuestHolidays.ps1`. Neither this event nor the Moonkin Festival (694) is in Forever's Holidays
table.

WoW's Anniversary is on retail's calendar as a new Holidays row every year, named with the year's
ordinal: "WoW's 21st Anniversary" is 1501 (from 16 November 2025) and "WoW's 22nd Anniversary" 1808
(from 17 November 2026, for 504 hours). The table also has five rows named plain "WoW's Anniversary",
one per region (590 and 1587 to 1590, Flags 3, dated every year from 2016 to 2026; 1587 is region
4's, from 17 November 2026 for 504 hours), but on 11 October 2026 `/qc holidays` on retail listed
1808 under "Other calendar holidays" and none of the five, so the entry lists 1808 alone. It keeps
each year's ID. Step 2b matches it to the rows named "WoW's <ordinal> Anniversary" (`$HolidayRowPatterns`
in `HolidayTables.ps1`) and reports one that runs today or later and isn't in the entry, so next
year's row is a finding of the sweep; until its ID is added, the anniversary's pins stay hidden while
it runs, and `/qc holidays` lists the row under "Other calendar holidays". A year can have one
ordinal row per region (the 20th had six) and the check reports each; adding them all is harmless. The
plain-named rows are left out of step 2b, so a year dated only on them would pass it silently; step 2h
lists them among the rows dated in region 4 and off the calendar, and checks every sweep that their
Flags still keep them off (`calendar-decisions.csv`, with 1587's absence from the list of 11 October).
After 8 December 2026, when 1808's run ends, the entry has no date to come until next year's row is in
the table: step 2h's `yearly WoW's Anniversary` fact then goes from holding to waiting (a finding at that
sweep), is listed as waiting every sweep after, and fails if no later row is in the table by 17 November
2027, a year after 1808 began (`calendar-decisions.csv`). On 16 October 2026 no table has a 23rd row
or name yet: not 12.1.5 live's (70391), the 12.1.5 PTR's (70340) or the 12.1.7 PTR's (70424), whose
HolidayNames are the same file. Since 12 October 2026 (#314, the user's answer to
decision 10) the entry also holds the 20th anniversary's 57 Guest Relations quests (83794 to 85574;
44 of them pinned, most in Tanaris near the Caverns of Time), which Blizzard's API files
under its category Secrets of Azeroth (646); the client's rows of that name (1396, 1398 and 1399) are
another event, of 2023, with no date to come. Step 2d reads that category as this entry through an alias
in `Audit-QuestHolidays.ps1` (it holds no other quest of ours); no API category, TrinityCore event or
heading names the entry's other 19 quests. Whether later anniversaries still offer the Guest Relations
quests is open (an `ask` fact in `calendar-decisions.csv`): if they don't, their pins show while the
anniversary runs for quests nobody can take. Forever's Holidays table (the same in 70245, 70291, 70338
and 70374) has no anniversary row, and its data no anniversary quest, so step 2b lists the entry as not
on Forever's calendar, which is no finding.

The Skyriding Cups are one entry with one flag (the user's decision of 11 October 2026; named after
the client's "Skyriding Races" on 12 October, as no table names the four cups together) for four
events, each a Holidays row of its own, for all regions and 336 hours at a time: the Kalimdor Cup
1395 (dated 15 August 2023, 25 February 2025, 23 February 2027 and 27 February 2029), the Eastern
Kingdoms Cup 1400 (4 October 2023, 26 August 2025, 24 August 2027 and 28 August 2029), the Outland
Cup 1407 (18 January 2024, 24 February 2026, 22 February 2028 and 26 February 2030) and the
Northrend Cup 1429 (30 April 2024, 25 August 2026, 29 August 2028 and 27 August 2030). On 11 October
2026 `/qc holidays` on retail listed 1395 and 1400 under "Other calendar holidays"; 1407 and 1429
are next dated more than 12 months ahead, beyond what the command reads, so the calendar serving
them is not yet seen: step 2h lists them as open facts, and says when each comes into the 12 months
(from February 2027 for 1407, August 2027 for 1429). 12 of the cups' 16 quests stand on six pins (the Racing Enthusiasts in Stormwind and
Orgrimmar, Lord Andestrasz in Valdrakken and the three Holiday Enthusiasts in Dornogal), which show
while any cup runs; the Dornogal pins also hold other holidays' quests and show while those run.
With one flag, `/qc holidays` lists the cups under the entry and no longer under "Other calendar
holidays": the next cup, and on a line below it each other cup the calendar has in its 12 months
(on 12 October 2026, the Kalimdor Cup and then the Eastern Kingdoms Cup). Step 2b matches the entry to every row named
"<Region> Cup" (`$HolidayRowPatterns`); on 12 October 2026 that took in only the six cups' names in retail
12.1.0.69933's and the 12.1.5 PTR's (70077) HolidayNames: the four above, the Pandaria Cup (432)
and the Broken Isles Cup (433), which have no Holidays row in either build, nor on 16 October 2026 in
12.1.5 live's (70391) or the PTR's (70340), whose only new name is The Unbinding of Kith'ix. A cup's
row that runs today or later and isn't in the entry is a finding; until its ID is added, the cups' pins
stay hidden while only that cup runs, and `/qc holidays` lists it under "Other calendar holidays". Step
2d reads the API's cup categories (all six) and our heading "Northrend Cup" as this entry through
aliases in `Audit-QuestHolidays.ps1`, so a new cup's quests show up there untagged. Forever's Holidays
table (the same in 70245, 70291, 70338 and 70374) has no cup and its data no cup quest, so step 2b
lists the entry as not on Forever's calendar, which is no finding.

Dastardly Duos and The Great Gnomeregan Run have entries of their own since 12 October 2026 (#314, the
user's answers to decision 10), each on the rows of its own name, which step 2b checks by that name.
Dastardly Duos (flag 2097152), a limited-time event at Vinnie Sweets in Dornogal from patch 11.1.5, is
three rows, one per region: 1599 (from 3 June 2025) and 1689 (region 4's, from 4 June 2025), for 42
days each, and 1673 (10 April 2025, 48 hours). None is dated after 2025, so its 11 quests' pins (six,
on Vinnie Sweets' and Wodin the Troll-Servant's pins on the Isle of Dorn) stay hidden until Blizzard
dates it again, as Hearthstone's 10th Anniversary's do; step 2h's `no-date 1599 1673 1689` fact then
goes from holding to failing, and `/qc holidays` says meanwhile that it is not on the calendar. Step 2d
reads the API's category Dastardly Duos (651, 7 of the 11 quests) as the entry by its name. The Great
Gnomeregan Run (flag 4194304) is row 696, for every region, 48 hours each October (10 to 12 October
2026, then from 9 October 2027; the table dates it to 2030), which `/qc holidays` on retail listed
under "Other calendar holidays" on 11 October 2026 and now lists as the entry. Its one quest, 47709 (for
gnomes, filed under the general "Seasonal" in the API), has one pin, nameless, on map 469, which shows
only while the race runs. Neither event is in Forever's tables or data, so step 2b lists both as not on
Forever's calendar, which is no finding.

Call of the Scarab has an entry of its own since 12 October 2026 (#315, the user's answer to decision
35: "yes, add the Call of the Scarab holiday"): flag 8388608 on row 638, the only row of its name, for
every region, 72 hours from 21 January 00:00 every year, under the Holidays filter. `/qc holidays` on
retail listed it under "Other calendar holidays" on 11 October 2026 and now lists it as the entry (next
21 to 24 January 2027). Its 18 quests are the event's 16 turn-ins, 45747 to 45762 (four elemental
items and four sigils of the Abyssal High Council, one ID per faction each, handed in for Qiraji
Commendations), and the two "Call of the Scarab" quests 45785 (Horde) and 45787 (Alliance). The 16
turn-ins stand on 24 pins, 20 in Silithus and 4 in Ahn'Qiraj: The Fallen Kingdom, each holding its quest
alone, which show only while the event runs; the other two have none. On 11 October 2026 the user had
kept the 16 shown and not flagged unavailable (decision 5), as the event is alive, and their `KEEP`
rows in `unavailable-quest-decisions.csv` stay. No signal of step 2d names the event (the API files all
18 under the area Silithus, 1377, with no category; TrinityCore has no event for it), so it checks them
through their `SET` rows; step 2b matches the entry by its own name. 28 more quests of the event, 14
meat turn-ins that wake the colossi and 14 world quests, are untagged until the user decides
([open-items.md](plans/open-items.md), decision 39). Forever's tables have no row 638 and its data none
of these quests, so step 2b lists the entry as not on Forever's calendar, which is no finding.

Retail's calendar on 11 October 2026, as `/qc holidays` listed it on the user's realm (whose
per-region rows are region 4's): every holiday our quests have was dated in the next 12 months
except Hearthstone's 10th Anniversary, as expected. Brewfest (372) 2027-09-20 to 2027-10-06,
Children's Week (201) 2027-05-03 to 05-10, Day of the Dead (409) 2026-11-01 to 11-03, Feast of
Winter Veil (141) 2026-12-15 to 2027-01-02, Hallow's End (324) 2026-10-19 to 11-02, Harvest Festival
(321) 2027-09-11 to 09-18, Love is in the Air (423) 2027-02-08 to 02-22, Lunar Festival (327)
2027-02-02 to 02-16, Midsummer (341) 2027-06-21 to 07-05, Noblegarden (181) 2027-03-29 to 04-05,
Pilgrim's Bounty (404) 2026-11-22 to 11-29, Pirates' Day (398) 2027-09-19 to 09-20, Trial of Style
(691) 2027-03-20 to 03-27, Darkmoon Faire (479) 2026-11-01 to 11-07, Moonkin Festival (694)
2026-11-12. The calendar holidays tied to no quest were Fireworks Spectacular (62), Pet Battle Bonus
Event (599), Battleground Bonus Event (602), Arena Skirmish Bonus Event (610), World Quest Bonus
Event (613), Hatching of the Hippogryphs (634), Volunteer Guard Day (635), Call of the Scarab (638),
Thousand Boat Bash (642), Un'Goro Madness (644), Spring Balloon Festival (645), March of the Tadpoles
(647), Glowcap Festival (648), Timewalking Dungeon Event (652, 1063, 1265, 1583, 1667, 1705, 1720),
Fireworks Celebration (658), PvP Brawl: Southshore vs. Tarren Mill (669), Gravity Lapse (670),
Warsong Scramble (671), Arathi Blizzard (673), Packed House (674), Auction House Dance Party (692),
The Great Gnomeregan Run (696), PvP Brawl: Deep Six (704), Cooking Impossible (1049), Wanderer's
Festival (1052), Free T-Shirt Day (1053), Luminous Luminaries (1054), Classic Ashran (1122), Temple
of Hotmogu (1169), Deepwind Dunk (1241), Shado-Pan Showdown (1244), Kalimdor Cup (1395), Eastern
Kingdoms Cup (1400), Delves Bonus Event (1560), Darkspear Dash (1793), Midnight Dungeon Event (1803)
and WoW's 22nd Anniversary (1808), which went into `qcHolidays` that day, as did the two cups, in
the Skyriding Cups. So the calendar serves Call of the Scarab (638) and The Great Gnomeregan Run
(696), whose entries came in on 12 October 2026 (#315 and #314), and the
Kalimdor and Eastern Kingdoms Cups, under those IDs. This list is the first comparison for step 2h's check in game: the
review, run as of 11 October 2026, lists the same 58 IDs, and for each entry the same days (the
Darkmoon Faire to 8 November 00:00, the end of the 7th). The IDs that decisions rest on are kept as
facts in `docs\plans\calendar-decisions.csv`, with the day they were seen: 1808, 1395, 1400, 638 and
696 seen, 1587 dated and not listed. A sweep's `/qc holidays` is set beside the review's list the same
way, on both games.

The calendar only serves events around the month it's set to, and at login it's set to November
2004. The addon sets it to the current month before reading, as Blizzard's calendar does when it
opens, but leaves it alone while that window is open. If the calendar can't answer, including a month
with no events at all, the last answer stands, and until there is one every seasonal quest is shown.
A day with no events, in a month that has some, means no holiday is running: retail always has some
event on, but WoW: Forever's calendar has empty days. `/qc holidays` steps the calendar through the
next 12 months, then sets it back to the current one.

The calendar also has to be asked for its events. On WoW: Forever a fresh login showed every seasonal
pin on the map, with the filter on, until the player opened and closed Blizzard's calendar window.
That window calls `C_Calendar.OpenCalendar()` each time it opens (so does the Guild News pane), and
nothing in Blizzard's interface calls it at login. So the addon calls it at login and on a reload,
and listens for CALENDAR_UPDATE_EVENT_LIST. Until the first answer, each event redraws the open map,
whose read sets the month and takes the answer; afterwards an event redraws it only when the answer
for the month already shown has changed, so the event never moves a month another addon set. Until
the first answer every seasonal quest is shown. The addon's own month changes fire the same event,
so reading the calendar and `/qc holidays` ignore it while they run. `/qc holidays` says why when
there's no answer: the month has no events, or the read raised an error. A map drawn while
Blizzard's window is open on another month can't read either, and keeps the last answer.

Blizzard's calendar window has a Filters menu, and its checkboxes are CVars: `calendarShowHolidays`,
`calendarShowDarkmoon`, `calendarShowWeeklyHolidays`, `calendarShowBattlegrounds`,
`calendarShowLockouts` and, on WoW: Forever, `calendarShowResets`. The window's own Lua filters
nothing (in `Blizzard_Calendar` on the `live` and `forever` branches a checkbox only calls `SetCVar`
and redraws from `C_Calendar.GetNumDayEvents` and `GetDayEvent`, and nothing else reads the CVars),
so the game itself must leave the events of an unticked filter out of those lists. That is read from
the source, and nobody has seen it in game. If it holds, a player who unticks Holidays leaves the
addon a month without holiday events: with raid lockouts or weekly events on, the month counts as
"ready, nothing running", and the seasonal filter hides the quests of a holiday that is running,
which is worse than showing them. So each update also reads the CVars with `GetCVarBool` and counts
every holiday whose filter is unticked as running, which shows its quests. Only an explicit `false`
counts; a CVar the game doesn't have returns nil and is taken as ticked, since nothing is left out
for it. The holidays with no IDs, which are never on the calendar, stay hidden whatever the filters. The other holidays are still judged by the calendar, and the addon never changes a setting.
An answer read while a filter was unticked keeps those holidays as running until a read made with it
ticked replaces it. The map notices a change at its next draw, or when the calendar fires its event.

Each entry in `qcHolidays` names the filter that holds its events: Holidays unless it has `filter=`.
The Darkmoon Faire is under Darkmoon Faire and the Stranglethorn Fishing Extravaganza under Weekly
Holidays. That comes from the `CalendarFilterType` column of the client's Holidays table: 0 is a
weekly holiday, 1 the Darkmoon Faire, 2 a battleground, and anything else (255 in retail, 3 on
Forever) a plain holiday. The names fit in both games: retail's 0 rows are bonus events, dungeon
events and the fishing derby, its 2 rows Calls to Arms and brawls, and Forever's 0 row the fishing
contest. Step 2b compares each entry with the column, so a holiday that Blizzard moves to another
filter, or one under the battlegrounds filter (which needs an entry in `qcCalendarFilters`), is a
finding. `/qc holidays` names an unticked filter in the game's own words and lists the holidays
under it, which it can't look up on the calendar.

To check it in game, log in fresh and open the map in a zone with seasonal pins out of season: they
should vanish within a moment without the calendar window being opened. `Test-SeasonalCalendar.lua`
checks the same offline, against a calendar that stays empty until it's asked and leaves out the
events of an unticked filter, and fails if the addon stops asking, stops redrawing, or reads an
unticked filter as a month with no holiday. Run it for both games' TOCs after any change to the
calendar code:

```powershell
& "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-SeasonalCalendar.lua
& "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-SeasonalCalendar.lua QuestCompletist QuestCompletist_Camelot.toc
```

WoW: Forever's calendar uses Classic's Holidays IDs where they differ from retail's, such as 263 and
264 for the Darkmoon Faire, so an entry in `qcHolidays` can list both games' IDs.

The minimum check, seven lines per game, is in [plans/open-items.md](plans/open-items.md), "To try in
game"; what follows is the long experiment, for a puzzling result only.

What the filters do in game is still to be seen, once in each game. Log in fresh and leave
Blizzard's calendar window shut, then run these (each fits the chat box), waiting a couple of seconds
after the first, and again after opening the window once:

```text
/run C_Calendar.OpenCalendar()
/run local n=C_DateAndTime.GetCurrentCalendarTime() C_Calendar.SetAbsMonth(n.month,n.year)
/run local c,t,s=C_Calendar,{},"" for d=1,c.GetMonthInfo(0).numDays do for i=1,c.GetNumDayEvents(0,d) do local e=c.GetDayEvent(0,d,i) local k=e.calendarType:sub(1,6)..(e.eventID or 0) if not t[k] then t[k]=1 s=s..k.." " end end end print(s)
/run for _,c in ipairs({"Holidays","Darkmoon","WeeklyHolidays","Battlegrounds","Lockouts","Resets"}) do c="calendarShow"..c print(c,GetCVar(c),GetCVarBool(c)) end
```

The third line lists every event of the current month once, as its type and ID (`HOLIDA324` is
Hallow's End). The fourth gives each CVar as the string and as the boolean; retail has no
`calendarShowResets`, so it prints nil there. Then untick one filter, run the third line again, and tick
it back:

```text
/run SetCVar("calendarShowHolidays",false)
/run SetCVar("calendarShowHolidays",true)
/run SetCVar("calendarShowDarkmoon",false)
/run SetCVar("calendarShowDarkmoon",true)
/run SetCVar("calendarShowWeeklyHolidays",false)
/run SetCVar("calendarShowWeeklyHolidays",true)
```

If the game leaves out an unticked filter's events, the list loses the ordinary holidays (324, and
1405 on retail) with Holidays, the Darkmoon Faire (479 on retail, 263 and 264 on Forever) with
Darkmoon, and the fishing contest (301, Sundays, Forever) with Weekly Holidays, and nothing else
changes; that is what the addon is built on. If the list never changes, the game leaves the events in
and the addon's handling is harmless and unneeded. Any other result means `qcHolidays` has the wrong
filter for an ID, or the game filters some other way, and the addon wants another look. To see
whether a click on the checkbox tells the addon, register the events before unticking:

```text
/run QCE=CreateFrame("Frame") QCE:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST") QCE:RegisterEvent("CVAR_UPDATE") QCE:SetScript("OnEvent",function(_,e,a,b) print(e,a,b) end)
```

With the addon, unticking Holidays and typing `/qc holidays` should list the ordinary holidays as
shown because the filter is unticked, and a map open on a zone with out-of-season seasonal pins should
show them.

## In the game

Some answers only the game client has.

**The calendar (`/qc holidays`), every sweep, on both games** (sweep step 2h). In a city, with
Blizzard's calendar window shut, type `/qc holidays` once on retail and once on Forever, and keep a
screenshot or a paste of what it prints. Set each beside the review's "What /qc holidays should print"
for that game: the same IDs under the same entries, and the same days. An ID the game lists and the
review doesn't, or the other way, is a finding to look at. For each open `served` fact of
`docs\plans\calendar-decisions.csv` that the game now lists, put the day in its `Seen` column; for a
row the table dates in the 12 months and the game doesn't list, add a `not-served` row with the day.
The first comparison is retail's list of 11 October 2026 ([Holidays](#holidays)).

**Quest-type probe (`/qc typecheck`).** This asks the client whether each quest recurs. It's pull
request #42, which is closed and its branch deleted; GitHub keeps its commits. It is superseded by the
probe below, which asks the same and more on both games from a dev-only addon; once the probe has run
on retail this section goes. Until then its saved results stand.

Run the probe after step 6 or 6b has added quests, then run step 3 again. On a sweep that adds nothing, the
saved results are enough.

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

`Retype-ProbeRecurring.ps1` reads that copy, or the probe's below.

**The probe (`/qcprobe`).** A small addon of its own, for the maintainer only: it is not part of
Quest Completist, and the ZIP, which holds `QuestCompletist\` alone, never has it. It runs in WoW:
Forever and in retail. It asks the server
about every quest in the client's `QuestV2` and every CMaNGOS quest `QuestV2` lacks, as it leaves out
repeatable quests. It names the quest givers, and records quest givers while you play. Its map pass
asks every map for the quest offers, points of interest, events, quest hubs and dungeon entrances
the game lists ([game-api-review.md](plans/game-api-review.md), recommendation 3).
It began as pull request #139, which stays open as the record; its files are in
`tools\ForeverProbe\`. Step 10 reads what it gathers. After a change to it, run `tools\Test-Probe.lua`
(it plays a run against stand-ins for the game and must say "0 failed").

1. Close the game, let Battle.net update it, and run `Get-LatestBuilds.ps1` ([Before a sweep](#before-a-sweep),
   item 1). Then rebuild the probe's lists of quests (the client's `QuestV2`, and the CMaNGOS
   quests it lacks) and of NPCs. They are generated, so they are not in git, and each game has its
   own (`QuestIDs_Forever.lua`, `NpcIDs_Forever.lua`; the retail TOC loads the `_Retail` ones):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\ForeverProbe\Build-ProbeLists.ps1 -Game forever -ToolsDir tools
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\ForeverProbe\Build-ProbeLists.ps1 -Game retail
   ```
   Without `-Build` the builder takes the build of the client installed under `-WowDir` (from
   `.build.info`), which is the build the probe will run on; it says which. A `-Build` that isn't
   the installed client's is allowed, for a client not installed yet, but warned about. The beta
   can update between building the lists and the run: run `Get-LatestBuilds.ps1` again before the
   session, and rebuild if the list is behind.
   The retail lists need no download: every quest in `data\quests.jsonl`, the daily, repeatable and
   128 ones first, and the NPC of every pin in `data\pins.jsonl`. The Forever NPCs are CMaNGOS's
   givers of the listed quests and the NPCs of `data\forever\pins.jsonl`. `Test-ProbeLists.ps1` checks
   the builder on made-up data.
2. Copy `tools\ForeverProbe\QCForeverProbe` from the checkout into
   `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\` (or `_retail_`),
   replacing any copy there, and restart the game fully.
3. Type `/qcprobe quests`. It asks about every quest that hasn't answered on this build, one at a
   time, and at the end asks every quest the server refused once more, one at a time, a refusal that
   came after both tries ran out included (the row says `retried`, keeps the refusal's `ms` and `at`
   and has the second answer's in `retriedMs` and `retriedAt`; the run's row counts `retried` and
   `recovered`). On 14 October 2026 the 12.1.5 server refused 4,959 quests asked 4 at a time; asked
   again one at a time the next day, 2,632 of them loaded (53%; 61% of the one-time ones), so a refusal
   at speed is not evidence on its own. What stayed refused is mostly recurring content: of the world
   quests, weeklies and dailies (the addon's types 128 and 4) asked that day after a refusal or a
   partial record on the 14th, 71% of the 5,326 that were not on the 14 October map pass's task lists
   stayed refused, against 1 of the 21 that were (the game already held the other 297 on them). That
   leans towards the server answering for active content, but 29% of the inactive ones still loaded,
   and no Blizzard source says so. `/qcprobe quests 4` still asks 4 at a
   time. One that gets no answer in 5 seconds is asked once more, and a quest the game already holds in
   full (a level above 0) isn't asked. One it holds only in part is, and a rerun asks again a quest saved
   as cached with no level: before this rule the 12.1.5 run saved 5,242 such placeholders as cached,
   3,996 of them task quests, most of which (3,340) were not in that day's quest cache. Each answer
   keeps when it came (`at`, in ms from the run's start). It says how many minutes are left every 500
   quests; stopping it (`/qcprobe stop`) and running it again picks up where it was, across logouts. On
   the beta, 4 at a time, 70374's 7,320 quests took 11 minutes. One at a time they take about 45 (the
   beta answers in about a third of a second), and asking again the 4,279 it refuses (it answers only up
   to about level 40) takes about 25 more, so a Forever pass is now a little over an hour; a rerun asks
   those refusals twice again, about 50 minutes. For every
   quest that loads it also saves the facts of API review recommendation 2 (whether the quest is
   account-wide, its faction group, whether it is important or meta, its quest line and campaign, its
   zone if it is a task, and the expansion, breadcrumb and story answers of three undocumented
   functions) and, for the character that runs it, what `IsQuestTrivial` and
   `GetContentDifficultyQuestForPlayer` say about it (0 Trivial to 4 Impossible; recommendation 4,
   scaling-aware levels), and the run's row says which functions the client has and what the
   character's `UnitQuestTrivialLevelRange` and `UnitQuestTrivialLevelRangeScaling` were. Those two
   answers depend on the character's level, so run it on one character, and on a build that was
   probed before the level facts existed (Forever's 70338) type `/qcprobe quests all`, because a quest
   already answered on a build isn't asked again. `Get-ProbeLevelFacts` in `ProbeResults.ps1` tallies them
   (how many are trivial, how many at each difficulty, and both together); nothing else reads the
   facts yet.
   Then `/qcprobe npcs`, outside any instance,
   as instances hide names. `/qcprobe status` says what's been gathered. On retail a full quest pass
   after a patch takes about two and a half hours one at a time (35,544 quests on 12.1.5; 4 at a time it
   took 36 minutes, with the refusals above; about 4 quests a second one at a time, as the 15 October rerun of
   10,201 took 43 minutes), asking its refusals again adds about 25 (that rerun refused 5,721), and a
   rerun only asks what the game doesn't hold. The NPC pass takes about 37 minutes on retail after a
   patch (8,440 NPCs on 12.1.5, nearly all named by a second look) and about nine when the game has most
   of them (8,418 in 513 s on 12.1.0), about 7 on Forever (1,513 on 70374), and the saved variables are
   about 18 MB; delete the addon's folder, or disable it, when you are not running it. After the run,
   log out fully and copy `questcache.wdb` at once: on 15 October 2026 the game's copy held only that
   day's 5,110 quests, the 26,616 of the day before gone. Keep each session's copy under its own name
   in `tools\<game>_probe_<build number>\`, as `questcache.2026-10-14-1208.wdb`: `Read-QuestCache.ps1`
   (step 2e for retail, step 10 for Forever) reads every copy of the build there together, each quest
   from the newest file that holds it.
3b. Type `/qcprobe maps`. It asks the server for each of the client's maps in turn (60 on Forever)
   and waits 2 seconds for each answer, so a run takes a minute or two; `/qcprobe maps 1` waits 1
   second. One run is enough. The results note the experience preset chosen once at Forever's login
   screen, Classic or Enhanced (Blizzard's code calls the second Modern): a starting-settings
   choice, whose Classic option turns the quest points of interest on the map off: the map
   filter's "Quest Objectives" entry, the `questPOI` setting, which the results note. The first
   run, on beta build 70245 (7 October 2026), had it on and found no offers on any map
   (game-api-review.md, "Map-offers probe: first run"), and so did the runs on 70291, 70338 and 70374
   (9, 10 and 14 October). Run it with every probe run all the same:
   a check stays in the sweep while it finds nothing, as the client's files and the game's API can
   start serving more at any build (decided 7 October 2026), and a change in its totals is a
   finding to plan. It works on retail too, and the retail sweep takes it as well: copy the folder
   into `_retail_`'s AddOns and type `/qcprobe maps 1`. Retail's 1,967 maps took 314 seconds
   (12.1.5, 14 October 2026). Read it with `tools\Report-MapOffers.lua <saved variables> QuestCompletist` and
   compare the totals with the baseline in game-api-review.md, "Map-offers probe: retail run"; the
   offers and log quests depend on the character, so use a similar one.
   The map pass ends by taking the **geometry** (the zone icons planned in
   [continent-pins.md](plans/continent-pins.md) need it): for every cosmic, world and continent map, each
   child map with its rectangle on it, what the game's hit test names at the rectangle's centre and over a
   60 x 40 grid, and the zone lists `GetMapChildrenInfo` gives with and without the type filter. `/qcprobe
   geometry` takes it alone, in a moment. It also notes the map window's size when the world map is
   showing, so for the pixel numbers open the map on a continent first, and run it once windowed and once
   maximised. Read it with `tools\Report-ContinentGeometry.lua <saved variables> [rows.csv]`, which lists
   what is odd on each continent (a rectangle that is missing or flat, twin zones, a centre another map
   takes, zone icons closer than 32 UI units, the largest the icon is drawn, at 700, 1000 and 1500 px) and
   writes one row per child map, and per map the hit test names that is no child.
   Then compare it with the baseline kept in the repository (sweep step 2f), for each game:
   ```powershell
   & "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Compare-ContinentGeometry.lua tools\<game>_probe_<build number>\QCForeverProbe.lua docs\plans\continent-geometry-baseline.csv
   ```
   It lists the zones that came, went or moved (more than 0.05 of a map point) on a continent map, and the
   maps whose type, flags, group, nav-bar listing or hit-test answer changed, and exits with 1 when
   there is any. A different zone list is a prompt to look at that continent's icons, not a failure of the
   addon, which asks the game each time; a zone in `QC_ZONE_ICON_AT` (`qcContinentPins.lua`) whose rectangle
   moved or whose hit area changed ("hit area N cells at x, y -> ...") wants its row read again from its
   `CentroidX` and `CentroidY` (over 100) in the new rows. The same goes for a hub in `QC_CONTINENT_HUBS`
   (`qcContinentPins.lua`: Oribos, Dalaran, Undermine, Nazjatar, Ahn'Qiraj: The Fallen Kingdom), whose row is
   the baseline's row of the same map (Oribos, Dalaran and Ahn'Qiraj are child rows of their continents;
   Undermine and Nazjatar are not children, so they are also in the report's "the hit test names maps that
   are not children" line). A map newly named in that line, or a quest category that no icon counts (a
   sub-zone for `QC_SUBZONE_HOST`, whose zone is the map's parent in the client's `UiMap` table), is a candidate
   for the next row: `tools\Test-ContinentPins.lua` prints, at the end of its real-data pass, how many quests are
   in no icon and the largest categories among them, for each game. When the differences are read, run it again with `--update`,
   which replaces that game's rows and keeps the other game's (it warns when the file has fewer rows than
   the baseline, which is a pass that stopped early), and commit the baseline. Names are compared as the
   client gives them, so take the dump on an English client, and a zone gated by a player condition
   (Quel'Thalas on Eastern Kingdoms) can come or go with the character: a difference there may be the
   character, not the game. On retail 12.1.5 (14 October 2026) the compare was clean: none of the
   six new maps is a child of a continent map (they sit under Eversong Woods and The Underbelly, or
   have no parent).
4. Log out fully, so the game writes the results and its caches. Then copy these from
   `C:\Program Files (x86)\World of Warcraft\_classic_beta_\` into
   `tools\forever_probe_<build number>\` (`forever_probe_70205` for build 1.60.1.70205):
   - `Cache\WDB\enUS\questcache.wdb` (each session's copy under its own name, as step 3 says) and
     `creaturecache.wdb`;
   - `WTF\Account\<ACCOUNT>\SavedVariables\QCForeverProbe.lua`.

After Forever's launch, use its live client's folder in place of `_classic_beta_`. From `_retail_`, copy
`WTF\Account\<ACCOUNT>\SavedVariables\QCForeverProbe.lua` and `Cache\WDB\enUS\questcache.wdb` into
`tools\retail_probe_<build number>\` (`retail_probe_69933` for build 12.1.0.69933), keeping each session's
copy of the cache under its own name, as step 3 says. Step 3 of the sweep, step 7 and the map report read
the `.lua` file there, and step 2e reads every copy of the cache together.

`Read-ForeverProbe.lua <file> facts` prints every fact the quest
pass saved, one per line, then a `run` line for each run (its kind, build, time, the character that ran
it, as faction, race and class and never a name, and its level), a `runfact` line for each fact of a
quest run (the function that answered it, or `false` when the client has none), a `trivialrange` line
for each of the character's two trivial level ranges (`false` when the client lacks the call) and a
`refusedfact` line for each
function the quest pass asked about the quests the server refused: how many it was asked about, how
many it answered anything for, how many with something other than no, and the first of those. Two runs
on different characters, with their answers compared, show whether the beta's answers follow the character.

A map pass is read with `tools\Report-MapOffers.lua`, which prints each map's offers, with how far
each is from the quest's pin, and the points of interest, events, hubs and entrances, and writes
the rows as a TSV. Give `QuestCompletist` instead of `QuestCompletist\Forever` for a retail file, and
name its TSV `map_offers_retail_<build number>.tsv`, which step 2c reads:
```powershell
& "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Report-MapOffers.lua tools\forever_probe_<build number>\QCForeverProbe.lua QuestCompletist\Forever tools\map_offers_<build number>.tsv
& "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Report-MapOffers.lua tools\retail_probe_<build number>\QCForeverProbe.lua QuestCompletist tools\map_offers_retail_<build number>.tsv
```

Leave the probe installed while you play Forever. Its recorder notes which quests each NPC or object
offers and where it stands. For most of Forever's new quests the recorders (this one and the addon's,
below) are the only source of where they start, so step 10 copies its file on every sweep.

From the version that ships it, the addon itself notes the same on both games (on by default,
`/qc report` shows what it holds; [quest-giver-recorder.md](plans/quest-giver-recorder.md)). Leave it
on while you play retail and Forever. Step 6d merges its notes into the pins. Before it, after a full
log out of each game, copy `WTF\Account\<account>\SavedVariables\QuestCompletist.lua` from the game's
folder (`_retail_`; `_classic_beta_` until Forever launches, then its live folder) into
`tools\recordings\own\retail\` and `tools\recordings\own\forever\`, replacing the old copy: the
file is cumulative. A player's file goes in `tools\recordings\players\<tag>\QuestCompletist.lua`;
nothing opens those files but `Read-RecordedGivers.lua`. Do this every sweep, so nothing is lost to
the addon's cap. Forever's importer reads the ledger, so both recorders' notes reach Forever's pins
through step 6d (step 10, item 1), and what they saw is combined there. Keep the probe installed while
you play the Forever beta: both recorders are kept, the probe's as well as the addon's (the user, 11
October 2026; plans/quest-giver-recorder.md, "What is left"). On 11 October 2026 the probe's own saved file in the game was
newer than the copy in `tools\` (53 givers, 68 offers and 50 turn-ins against 33, 36 and 18) and held everything
the addon's file did, bar one turn-in, with the same 40 spots to the tenth of a point, and more; copy it before step 10.

## Checking a change before its pull request

```powershell
& "C:\Program Files (x86)\Lua\5.1\luac.exe" -p (Get-ChildItem QuestCompletist\*.lua, QuestCompletist\Forever\*.lua).FullName
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-AddonData.ps1 -Check
git diff --stat
```

- The syntax check must be silent. If it says "main function has more than 200 local variables",
  a file has hit Lua 5.1's limit on locals declared at its top, and WoW wouldn't load it. Each file
  has its own 200: `qcCore.lua` had room for 21 more on 12 October 2026, measured by adding
  `local zzProbeN = N` lines to the end of a copy one at a time until `luac -p` failed (`luac -l` lists
  199 there, as it also counts the locals of blocks that have closed). In October 2026 `qcTooltips.lua` had 150 left (`luac -l` listed 50 on 11 October) and
  `qcMapPins.lua` 149 (after the map's tooltip moved from one to the other). Code that doesn't need to live in `qcCore.lua` can go in a file of its own,
  as the tooltips and map pins do. Every file gets the addon's own table (`select(2, ...)`), and
  `qcCore.lua` hands those files what they need through it, at its end. A new file goes in both
  TOCs, and the release that ships it tells players to fully close and restart World of Warcraft.
- `Build-AddonData.ps1 -Check` must say all four generated files are up to date, two for each game.
  The last line for each game gives its quest and pin counts, which should only change when quests
  or pins were meant to be added or removed. As of 15 October 2026 they're 35,573 quests and 16,084
  pins for retail, and 5,105 quests and 1,706 pins for Forever.
- The diff should touch only what the change is about. For data changes, check that only the
  intended field moved on each line of the data files.
- The addon's files use Windows (CRLF) line endings. A script that writes them must keep that.
  `.gitattributes` stores `qcQuest.lua`, `qcQuestData.lua`, `qcPinDB.lua` and everything in
  `QuestCompletist\Forever\` exactly as written.
- For filter or data changes, run `Test-QuestReachability.lua` before and after, and compare the
  summaries it prints. A change to the shared code needs it for both games: step 9 for retail,
  step 10 for Forever. Its four "character level" lines (the minimum level), its "made-up quests"
  line (a level of 0 or below) and its "empty list's line" line (what an empty list says) must read 0,
  and the run exits with 1 when they don't.
- For changes to `Read-QuestCache.ps1`, `Compare-QuestCache.ps1` or `Compare-QuestReputation.ps1`,
  run `Test-QuestCache.ps1`, `Test-CompareQuestCache.ps1` and `Test-CompareQuestReputation.ps1`.
  They build their own caches, API records and tables in a scratch folder; each must end "N checks
  passed, 0 failed".
- For changes to `QuestLevels.ps1`, `Apply-QuestMinLevels.ps1` or `Compare-QuestLevels.ps1` (retail's minimum
  levels, step 2g), run `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-QuestLevels.ps1`. It
  makes quests, API records, a quest cache and a ContentTuning table in a scratch folder (nothing downloaded),
  and with the real files in `tools\` (or `-RealToolsDir`) also applies the formula to a copy of the data. It
  must say "0 failed".
- For changes to `QuestCacheFiles.ps1` (which quest cache a tool reads, and the warning for one that looks
  partial, step 2e), run `Test-QuestLevels.ps1`, which tests it on made-up caches, and the tests of the tools
  that print its warning: `Test-CompareQuestCache.ps1`, `Test-CompareQuestReputation.ps1`,
  `Test-AddTaskQuests.ps1`, `Test-SyncQuestProfessions.ps1`, `Test-SyncQuestNames.ps1` and
  `Test-SyncQuestPvP.ps1` (which checks that retail's cache is warned about when it holds too few of our
  quests, and that Forever's isn't held to our quests). Each must say "0 failed". `Sync-QuestPrerequisites.ps1` prints it too and has no test, so run it with `-WhatIf` on the
  real files in `tools\`: `Sync-QuestPrerequisites.ps1 -Build <newest retail build> -WhatIf` must warn only
  when that cache looks partial.
- For changes to `QuestLines.ps1` (the prerequisites Forever's importer takes from a quest line's order), run
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-QuestLines.ps1` (made-up quest lines). It must
  say "0 failed".
- For changes to `QuestConditions.ps1` (the client's quest line and campaign conditions, steps 2b and 2c), run
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-QuestConditions.ps1` (made-up client tables). It
  must say "0 failed". Then run step 2c with `-WhatIf` on the real tables: it must say "Changes: 0".
- For changes to `Add-TaskQuests.ps1` (step 6b), run `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-AddTaskQuests.ps1 -ToolsDir <the main checkout's tools folder>`.
  It adds made-up task quests to a scratch copy and checks each skip and each field, then (with the real
  table) takes every 25th task quest of the data out and checks that the tool brings back exactly those;
  `-MadeUpOnly` runs the first half alone. It must say "0 failed".
- For changes to `Sync-QuestProfessions.ps1` (step 1d) or its decisions file, run
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncQuestProfessions.ps1 -ToolsDir <the main checkout's tools folder>`.
  It checks each pass, each kind of decision, each list and `-Game forever` on made-up tables, then
  (with the real tables) takes the profession, heading or zone from quests of every pass and kind of
  decision and checks that the tool gives exactly that back; `-MadeUpOnly` runs the first half alone. It
  must say "0 failed".
- For changes to `Sync-QuestNamesFromApi.ps1` (step 1c), run
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncQuestNames.ps1`. It makes API records,
  two quest caches and a task table in a scratch folder (nothing downloaded) and checks which source names
  each quest (the API first, then the newest cache, then the task table), that titles are copied exactly,
  that no `[DEPRECATED]` title is taken from any source, that missing sources are named as skipped, that
  `-WhatIf` writes nothing and that a second run changes nothing. It must say "0 failed".
- For changes to `Sync-QuestPvP.ps1` (step 2i), or to `ForeverAnswers.ps1` or `QuestRemovals.ps1`, run
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncQuestPvP.ps1`. It makes a Forever world
  (two quest caches, an answer memory, a CMaNGOS dump, removal decisions) and a retail one in a scratch folder
  (nothing downloaded) and checks which source tags each quest, a quest kept from an earlier run included, that
  a missing memory is named as skipped and one out of step with the cache is named, that retail's cache
  is warned about when it holds too few of our quests and Forever's isn't, that `-WhatIf` writes nothing and
  that a second run changes nothing. It must say "0 failed".
- For changes to the calendar code, `/qc holidays` included, run `Test-SeasonalCalendar.lua` for both
  games' TOCs (see [Holidays](#holidays)). It must say "All checks passed."
- For changes to `Review-Calendar.ps1` or `HolidayTables.ps1` (step 2h, and the holiday check of step
  2b), run `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ReviewCalendar.ps1`. It makes
  the tables, qcHolidays, quest data, baseline and decisions file in a scratch folder (nothing
  downloaded) and must say "0 failed"; then run `Compare-ClientTables.ps1` too.
- For changes to the map's tooltip (`qcTooltips.lua`, `qcMapPins.lua`), run `Test-MapTooltip.lua` for both
  games' TOCs. It must say "All checks passed." It plays a pin's tooltip (opened, filled, redrawn by names
  and by Shift, closed) against stand-ins that write down every call; give it a file as a third argument
  and run it on the code before and after a change to compare the two records line by line. It also draws
  stacks of pins through the map's own pass and clicks them: on made-up stacks it checks that the pin, its
  waypoint and its tooltip's first heading go by the first pin that has a name, and on every stack in the
  data that each with a named pin is named. It also clicks a pin and a quest in the list with TomTom loaded
  (TomTom's waypoint, nothing of the game's) and without it (the game's own waypoint and arrow, against
  stand-ins for a client that allows the map, refuses it, turns the map pin off by rule, errors, or lacks
  the functions), and checks that the pin's tooltip offers a click only where one will set a waypoint.
  It checks the tooltip with the quest IDs turned off and with a quest it marks PvP, and the PvP pin icon.
  The pins and quests it uses are the first fitting ones in the data of the TOC it loads, so the two
  games' runs check different quests. Forever's run:
  `& "C:\Program Files (x86)\Lua\5.1\lua.exe" tools\Test-MapTooltip.lua QuestCompletist QuestCompletist_Camelot.toc`.
- For changes to what the addon ticks (the login sync and hand-ins in `qcCore.lua`, with their
  breadcrumbs and "only one of these" groups) or to Forever's links or classes, run `Test-Completions.lua` for both
  games' TOCs. It must say "All checks passed." It fires the login and hand-in events against a made-up
  server, checks the clean-up of `qcFormerlyExclusive` on one of the game's groups, and on Forever walks
  the quests of `forever-quest-link-decisions.csv` (the level 10 rogue, warrior and mage quests, Bounty
  on Murlocs, Securing the Supply Lines, Call of Earth, and some of the prerequisites it sets or removes)
  and checks who can take Zephras Isle's Call of Earth and the Foror's Compendium chain.
  It also checks that the map hides a breadcrumb still to do while the quest it leads to is in the log,
  keeps one done or in the log and those in `qcClosedOnceDone`, and that a hand-in ticks breadcrumbs of
  breadcrumbs: on a chain from the game's data, on retail's quests listed as each other's breadcrumb and
  its API breadcrumbs, and on Forever's level 16 rogue quests. On Forever it also walks the rest of
  CMaNGOS's requirements (#308): a quest that needs all of a group (A Donation of Runecloth), one of
  several (Trek to Ashenvale, Covert Ops - Alpha), the quests a condition names, the Alterac quests kept
  open, Moonglade's Heeding the Call lead-ins, and the quest window's breadcrumb notice counting only
  the lead-ins the character can take (In Search of Anthion). It also checks the quests offered only
  while another is in the log (`qcQuestNeedsInLog`, #309): Digging Through the Dirt is grey, with a
  line under Required Quest in its tooltip, until Bride of the Embalmer is in the log, and is ticked at
  that quest's hand-in and by the login sync; the repeatable Earth Sapta isn't ticked when Call of
  Earth is handed in. Run it too for changes to the map's filters in `qcBuildViewFilter`.
- For changes to the quest list's tooltip (the storyline's name and the "Type:" row in `qcTooltips.lua`), run
  `Test-QuestTooltip.lua` for both games' TOCs. It must say "All checks passed." It draws the real tooltip for a
  quest in a storyline, a plain one and a daily one, with stand-ins for the game's quest calls that answer what each
  case says: the game's quest line is ours, another, nothing, an error, a secret value or no function at all.
  It also takes every quest of a profession that has a quest to do first, for a character with that
  profession alone. With every quest that character could do done, the list's filter, with the requirements
  and profession filters on, must keep the quest. With nothing done, its "Required Quest" lines must name no
  quest of another profession. Run it for changes to the prerequisites or the professions too.
  Give it a file as a third argument to write each case's lines out, and run it on the code before and after a
  change to compare them.
- For changes to the saved settings or the options panel, run `Test-Settings.lua` for both games' TOCs. It must
  say "All checks passed." It builds the panel against frames that keep their anchors and heights, so it
  also says how much room the page has left (33 px with the continent box in).
- For changes to the zone icons' counting (`qcContinentPins.lua`, `qcGetZoneQuests` in `qcCore.lua`), run
  `Test-ContinentPins.lua` for both games' TOCs. It must say "All checks passed." It builds a made-up
  continent from the game's own zones, counts a character step by step (a breadcrumb whose quest is in the
  log counts as closed, not available), checks every category against the quest list's zone counter, and,
  with the client's UiMap table in `tools\`, gives every continent its zones and times a pass. Retail's
  table is `UiMap.csv`; Forever's is the newest `UiMap-1.60.1.<build>.csv` by build number, unless a third
  argument names another.
- For changes to the addon's text, run `Test-Localization.lua` (see
  [Text in other languages](#text-in-other-languages)). It must say "No problems".
- **A quest never leaves the data unseen.** Before a pull request that touches `data\quests.jsonl` or
  `data\forever\quests.jsonl`, run `powershell -NoProfile -ExecutionPolicy Bypass -File
  tools\Show-RemovedQuests.ps1 -Game retail` (or `forever`): it lists the quests the file has lost since
  `origin/master`, with ID, name and zone, and exits 1 for one with no `REMOVE` row in
  `docs\plans\quest-removal-decisions.csv`. Show the list to the user and wait for their review before
  committing the change; put it in the pull request. `Test-QuestRemovals.ps1` checks the tool and the
  importer's answer memory on made-up data and must say "0 failed".
- For changes to the probe (`tools\ForeverProbe\QCForeverProbe`) or to `Report-ContinentGeometry.lua` or
  `Compare-ContinentGeometry.lua`, run `Test-Probe.lua`. It must say "0 failed".
  It plays the quest, NPC and map passes and the recorder against stand-ins for the API, on a clock of its
  own, so it can't say what the game answers: that is the run under [In the game](#in-the-game).
  For `Build-ProbeLists.ps1`, run `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ProbeLists.ps1`
  (made-up data, nothing downloaded). For `Get-LatestBuilds.ps1` or `LatestBuilds.ps1`, run
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-LatestBuilds.ps1` (a made-up game folder and
  made-up newest versions, nothing downloaded or read from the real game). All must say "0 failed".
  For `ProbeResults.ps1`, `Read-ForeverProbe.lua`, `Retype-ProbeRecurring.ps1`,
  `Find-UnavailableQuestCandidates.ps1` or `Compare-PinNpcNames.ps1`, run `powershell -NoProfile -ExecutionPolicy Bypass -File
  tools\Test-ProbeResults.ps1` (both probes' files read the same, and the two scripts give the same answers
  on a scratch copy of the data). It must say "0 failed".
- For changes to the recorder (`qcRecorder.lua`) or what it reads, run `Test-Recorder.lua`. It must
  say "0 failed". It plays the events against stand-ins for the API, so it can't say what the game
  answers: that is the in-game list in [quest-giver-recorder.md](plans/quest-giver-recorder.md).
- For changes to `Read-RecordedGivers.lua`, `RecordedGivers.ps1` or `Import-RecordedGivers.ps1`, run
  `Test-RecordedGivers.lua` (the reader: what it reads, and the hostile files it refuses) and
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-RecordedGivers.ps1` (the rules and the
  tool, on small data made in a scratch folder). Both must say "0 failed".
- For changes to `Import-ForeverData.ps1`, or to what it takes from the ledger (`RecordedGivers.ps1`), run
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ForeverImport.ps1`. It builds a small Forever
  world in a scratch folder (client tables, CMaNGOS dump, quest cache, probe file, ledger made by step 6d, and
  its own hand lists) and runs the importer on it: what the ledger gives, the trust rule, the 1.5-point radius
  (one place at exactly 1.5 points, two at 1.51), the stale-ledger stop, that the ledger's retail rows change
  nothing, a rerun that must write every file byte for byte, the classes (from the items that start a quest,
  the hand list of classes and a quest's only prerequisite, and the class rows it refuses), and, with the
  ledger filled from the probe's file alone, the files
  master's importer wrote on that world (kept in the test as written once by it, 448bd64). It must say
  "0 failed". A change that is meant to alter those files means writing the expected text again, from a run
  that has been checked by hand. Its section L checks the pins of start points with no giver: one per
  1.5-point spot, the icon from the quests, and a giver found later taking its quest off the spot.
- For changes to `PinRules.ps1`, `Assemble-PinDB.ps1` or `Apply-ClientQuestGivers.ps1`, or to how
  `RecordedGivers.ps1` fills a pin, run `powershell -NoProfile -ExecutionPolicy Bypass -File
  tools\Test-PinRules.ps1` (the rules, then the pipeline and both fill tools on a world made in a scratch
  folder: three quests at one spot with no giver share a pin, the icon of a spot whose quests bring
  different ones, the 1.5-point edge, and a giver found for one quest from the client's giver table and from
  the recorder taking that quest to its own pin while the other two stay on the nameless one, through a
  rebuild, and two nameless pins on one point each giving the client's giver only their own quest). It
  must say "0 failed"; `-Tools` runs it on another copy of the tools, to see what fails
  there. Also run `Test-ForeverImport.ps1` and `Test-RecordedGivers.ps1`, as both games use the rules,
  and the pin pipeline (step 6) on scratch copies before and after, comparing the candidates' pins.
- For changes to `Read-ApiDocs.lua` or `Compare-ApiDocs.ps1`, run
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ApiDocs.ps1` (fixtures made in a
  scratch folder, nothing downloaded; with the real documentation folders in `tools\api_docs\` it also
  checks the reader against them). It must say "0 failed".
- For changes to `Build-QuestLocationData.ps1`'s kinds of task quest (`$noPinKinds`) or to what its
  TrinityCore pass holds, run
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-QuestLocationKinds.ps1` (made-up client
  tables and a made-up TrinityCore dump in a scratch folder, read with Lua 5.1, nothing downloaded). It must
  say "0 failed". Run the pin pipeline (step 6) before and after and compare the pins by quest: only the
  quests the change names may gain or lose one.
- For changes to `Audit-QuestTables.ps1` or `Remove-DuplicatePinQuests.ps1`, or to the data and tables they
  check on Forever, run `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ForeverChecks.ps1`. It
  must say "0 failed". It makes small data in a scratch folder for both, and ends with the two run on Forever's
  committed data, which must have no finding the decisions file doesn't keep, no row of that file that keeps
  nothing, and no duplicate to remove.

## Bundled libraries

The minimap button needs four libraries, kept unchanged in `QuestCompletist\Libs\` and listed in both
TOCs before the addon's own files:

| Library | Version | Source |
|---|---|---|
| LibStub | 2 | `https://repos.wowace.com/wow/libstub/trunk/LibStub.lua` |
| CallbackHandler-1.0 | 8 | `https://repos.wowace.com/wow/callbackhandler/trunk/CallbackHandler-1.0/` |
| LibDataBroker-1.1 | 4 | `https://github.com/tekkub/libdatabroker-1-1` |
| LibDBIcon-1.0 | 56 | `https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0/` |

They aren't part of a sweep. To update one, download the file from its source, read what changed,
and check that `Test-Localization.lua` and the syntax check above still pass. Each library keeps the
highest version of itself that any loaded addon carries, so a newer copy in another addon wins
without conflict. LibStub is public domain; CurseForge lists LibDBIcon as Ace3-style BSD.

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
| Blizzard's Game Data API | faction, race, class, reputation, daily/weekly flags, quest names, required quests, the minimum level (`min_character_level`, step 2g), the quest category that names a holiday or a profession, and the rewards that are profession knowledge (retail only) | `Audit-QuestAccuracy.ps1`, cached in `tools\quest_api_cache`; the holiday category is read by `Audit-QuestHolidays.ps1` (step 2d), the profession category and rewards by `Sync-QuestProfessions.ps1` (step 1d) |
| The game client's own tables, via [wago.tools](https://wago.tools) | task quests with their professions and prerequisites, the profession headings (`QuestSort`) and the items that are profession knowledge (`Item`, `ItemSparse`), the professions a renown reward is given for (`RenownRewards`, `PlayerCondition`, `ModifierTree`, `SkillLine`; the evidence in `plans\quest-link-decisions.csv`), questlines, map positions, map names, dungeon journal, faction names and which have renown or friendship ranks, and the level ranges (`ContentTuning`) that give the minimum level of the quests the API has no record of (step 2g); for Forever, which quests exist, its maps, zones, headings, races, classes and factions, its reputation amounts, and the few quest start points it has; on both, the classes that may use the items that start a quest | CSV exports per build, e.g. `https://wago.tools/db2/QuestLine/csv?build=<build>` |
| The game itself | recurring or one-time, world quest or not; for Forever, each quest's title, level, minimum level, zone, race limits, recurrence and reputation rewards, and quest givers seen while playing; each map's quest offers, points of interest and events (the probe's map pass) | in-game probes and runtime API calls; the addon's recorder (`Import-RecordedGivers.ps1`, ledger `plans\recorded-quest-givers.csv`, which Forever's `Import-ForeverData.ps1` reads); the quest cache of either game, read by `Read-QuestCache.ps1` (on retail its sort names a profession's heading, for step 1d); `Report-MapOffers.lua` |
| TrinityCore's world database ([TrinityCore](https://github.com/TrinityCore/TrinityCore/releases)) | breadcrumbs, groups of which only one can be done, and previous quests, for older quests; the quest giver's creature ID for a pin that has a name and none; the start points of quests the client lists none for (`quest_poi`) and their starters' spawns; which holiday event a quest belongs to (`game_event_seasonal_questrelation`, `game_event_creature_quest`, `game_event_gameobject_quest`), as evidence for retail's holiday tags | `Audit-QuestTables.ps1`, `Audit-QuestHolidays.ps1`, `Sync-QuestPrerequisites.ps1`, `Fill-PinNpcIds.ps1` and `Build-QuestLocationData.ps1`, from `tools\tdb\` |
| CMaNGOS's vanilla database ([cmangos/classic-db](https://github.com/cmangos/classic-db)) | WoW: Forever's old-world quests, givers and their spawns, breadcrumbs and quests of which only one can be done | `Import-ForeverData.ps1`, from its `Full_DB` dump |
| [Wowhead](https://www.wowhead.com), by hand | the right NPC for retail pins whose ID was wrong; WoW: Forever quest givers and zones no other source has; the event in a retail quest's quick facts and the achievement it is a criterion of, as evidence for its holiday tag; players' first-hand comments, with Questie's issues and a test in the game, as evidence for a WoW: Forever link CMaNGOS gets wrong or a class no source gives | looked up by a person: `plans\pin-npc-id-decisions.csv`, read by `Apply-PinNpcIds.ps1`, and `plans\forever-quest-givers.csv` and `plans\forever-quest-zones.csv`, read by `Import-ForeverData.ps1`; the holiday evidence is in `plans\quest-holiday-decisions.csv`; the link evidence is in `plans\forever-quest-link-decisions.csv`, read by `Import-ForeverData.ps1` and `Build-ForeverMenu.ps1`; the class evidence is in `plans\forever-quest-class-decisions.csv`, read by `Import-ForeverData.ps1` |
