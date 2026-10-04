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

  It happened again on 2026-10-03: CurseForge's 110.7 update replaced the link with a plain copy,
  deleting the repository's `QuestCompletist/Images` on the way, and in-game tests ran the released
  copy without anyone noticing. The fix was to uninstall Quest Completist in the CurseForge app (safe
  while the folder is a plain copy), then create the link again. **Before every in-game test**, check
  both:
  ```powershell
  (Get-Item "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\QuestCompletist").LinkType   # must be Junction
  git -C "C:\Users\alist\RiderProjects\QuestCompletist" status -sb   # the branch under test, no deleted files
  ```

`tools\` only tracks its `*.ps1` scripts. Everything the scripts download or write there (CSV
exports, the API cache, reports) is gitignored and can be regenerated.

## The quest and pin data files

The quest rows and the map pins are also kept in `data\`, one record per line, with named fields:

- `data\quests.jsonl`, one quest per line:
  `{"id":176,"name":"WANTED:  \"Hogger\"","level":1,"zone":"Elwynn Forest","category":70,"type":1,"faction":1,"race":64175181,"class":8191,"storyline":566}`.
  `profession`, `holiday`, `covenant`, `storyline` and `prereq` are left out when they're 0.
- `data\pins.jsonl`, one pin per line:
  `{"map":84,"icon":1,"npc":29611,"name":"King Varian Wrynn","x":26.12,"y":47.32,"quests":[26365]}`.
  `npc` is left out when it's 0, and `name` and `note` when the pin has none.

`tools\Build-AddonData.ps1` checks them and writes the `qcQuestDatabase` rows of `qcQuest.lua` and
the whole of `qcPinDB.lua`. With `-Check` it writes nothing and only says whether the Lua matches.
It names any problem by file and line, e.g. `quests.jsonl line 3 (id 53665): 'level' is missing`.

**Tools are moving over to the data files** (see [the plan](plans/data-structure.md)). These already
change the data files and rebuild the Lua themselves: `Apply-AccuracyFixes.ps1`,
`Sync-QuestNamesFromApi.ps1`, `Retype-FlaggedWorldQuests.ps1`, `Retype-ProbeRecurring.ps1`,
`File-WeeklyEventQuests.ps1` and `Apply-PinNpcIds.ps1`. They take `-DataDir` and `-AddonDir`, and
default to the checkout they're in. Before saving, they check that the Lua still matches the data
files, and stop without changing anything if it doesn't.

The other tools still edit the Lua. After any of them changes `qcQuest.lua` or `qcPinDB.lua`, run
this, and commit the data files along with the Lua:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Export-AddonData.ps1    # about a minute
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-AddonData.ps1 -Check
```

`-Check` must say both files are up to date.

## Before a sweep

1. **Find the current retail build** at <https://wago.tools/api/builds/latest> (product `wow`).
   The addon targets retail only.
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
| 1c | Quest names | `Sync-QuestNamesFromApi.ps1 -WhatIf`, then without `-WhatIf` | Only the last one |
| 2 | Reputation rewards | `Compare-QuestReputation.ps1` → `Apply-ReputationBackfill.ps1` | Only the last one |
| 3 | Quest types | `Retype-FlaggedWorldQuests.ps1`, `Retype-ProbeRecurring.ps1` | Yes |
| 4 | Storylines | `Build-QuestLines.ps1 -Build <retail build> -Refresh` | Yes |
| 5 | Zone table and category names from the client | `Build-CategoryUiMapIDs.ps1 -Refresh` → `Add-ZoneTableMaps.ps1` → `Build-CategoryUiMapIDs.ps1` → `Remove-ConvertedLocaleKeys.ps1 -WhatIf` → `Build-CategoryClientNames.ps1 -Refresh` | Yes |
| 6 | Map pins, and quests new to the database | see [the pin pipeline](plans/quest-location-data-pipeline.md), then `Fetch-GapQuestData.ps1` → `Insert-GapQuestEntries.ps1` → `File-WeeklyEventQuests.ps1` | A candidate file, until you apply it |
| 7 | Quests that may no longer be obtainable | `Find-UnavailableQuestCandidates.ps1 -Refresh` | No |
| 8 | Dungeons and raids against the Dungeon Journal | `Audit-DungeonCategories.ps1 -Refresh` | No |
| 9 | Quests and pins nothing can display | `Test-QuestReachability.lua`, after every step that edits the addon | No |

After each step that edits the addon, bring the data files up to date as described in
[The quest and pin data files](#the-quest-and-pin-data-files).

Step 3 reads the saved results of the in-game probe, so it needs nothing from the game on an
ordinary sweep. When step 6 adds quests, those have never been probed. Run
[the probe](#in-the-game) after step 6, then step 3 again.

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
  recurs **and** the API flags it daily or weekly. It reads the probe's saved results in
  `tools\quest_type_probe_results.lua`, which only cover quests that were in the database when the
  probe ran.

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

### 5. Zone table and category names from the client

`Build-CategoryUiMapIDs.ps1 -Refresh` downloads the game's map table (`UiMap.csv`) for the pinned
build and maps quest categories to game maps, so the client supplies their names in every language.

Then run `Add-ZoneTableMaps.ps1 -WhatIf`, then without `-WhatIf`. It adds the maps missing from
`qcAreaIDToCategoryID`, which turns the map you're on into a quest category. The addon switches the
quest list through it when you enter a zone, and `Place-UncategorisedQuests.ps1` files quests by it.
Nothing else maintains it, so new dungeons and new versions of a zone's map drift out of it. A map
is added when a category is named by it, when it has the same name and parent as a map already
listed (a dungeon's other floors), or when its name is exactly that of one category with no map
yet. It never adds continent-level maps, and never changes an existing entry. Run
`Build-CategoryUiMapIDs.ps1` again afterwards, without `-Refresh`, so it sees the new maps.

`Remove-ConvertedLocaleKeys.ps1` then deletes the translations that became redundant. Run it with
`-WhatIf` first.

Then run `Build-CategoryClientNames.ps1 -Refresh`. It names the categories that aren't maps from
other client tables: classes, professions, covenants, dungeons, achievement categories (the world
events), factions, Blizzard's UI text and area names. A rerun with no client changes leaves
`qcQuest.lua` byte-identical. Names we made up ("Bfa Unknown", "Garrison Support") stay ours.
If the game returns no name for a category, our translation is used.
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
`Fetch-GapQuestData.ps1` and added with `Insert-GapQuestEntries.ps1`. Run
`Assemble-PinDB.ps1 -Apply` before inserting, because the inserter uses the new pins. The fetch
keeps each API response in `tools\quest_api_cache`, and the inserter refuses any quest that's
already in the database.

The inserter then files the new quests itself, by running `Place-UncategorisedQuests.ps1` on the
same folder. It lists any new quest it couldn't place; those stay in category 0, Uncategorized. Like
the other scripts that write, both take `-AddonDir`, so they can run against a scratch copy of the
addon.

`Place-UncategorisedQuests.ps1` also works on its own, on every quest without a category or in a
category that isn't defined. Run it with `-WhatIf` first. It files each quest by the first of these
that gives an answer:
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

`-Refile 1050` also files the quests in the catch-all category "Legion Uncategorized". For those,
and for category 0, it adds a hand-written list in the script that maps the quest's zone text
("Death Knight Campaign", "Time Rifts") to a category. What's left in the catch-alls has nothing to go on.

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

The quests the addon hides as unavailable are the FLAG rows of
`docs/plans/unavailable-quest-decisions.csv`. After changing that file, run
`Build-UnavailableQuests.ps1` to regenerate `qcUnavailableQuests.lua`; don't edit the Lua file by
hand. Before flagging a quest as gone from the client, check the latest PTR build's `QuestV2` as
well as retail's: a quest missing from retail may be upcoming content. Players who accept or turn in
a flagged quest get a chat message, and the quest is recorded in their `qcFlaggedButSeen` saved
variable. Unflag anything reported that way.

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
- Quests in categories the list can't browse to, pin maps missing from `tools\UiMap.csv`, and
  holiday values that aren't in `qcHolidays`.

It assumes best-case progress: max level, prerequisites done, max renown, every profession. The
quest search finds every quest by name whatever this reports. Some results are expected. Pins whose
quests aren't in the database stay hidden while "hide quests with no data" is on. A map missing
from `UiMap.csv` can't be opened on retail; a newer build than the downloaded one may add it.

## Holidays

Seasonal quests need no yearly upkeep. The map's seasonal filter asks the game's calendar which
holidays are running, and `qcHolidays` in `qcCore.lua` ties each holiday value in the quest
database to the IDs of the game's Holidays table that its calendar event carries.

`/qc holidays` in game lists what the filter sees: which holidays are running, each one's next dates,
and any calendar holiday that isn't tied to a quest. A holiday there that should match one of ours,
under a new ID, means an entry in `qcHolidays` needs that ID adding. A new holiday with quests
needs a new flag, an entry, and its quests' field 11 set.

The calendar only serves events around the month it's set to, and at login it's set to November
2004. The addon sets it to the current month before reading, as Blizzard's calendar does when it
opens, but leaves it alone while that window is open. If the calendar can't answer, including a day
with no events at all, the last answer stands, and until there is one every seasonal quest is shown.
`/qc holidays` steps the calendar through the next 12 months, then sets it back to the current one.

## In the game

Some answers only the game client has.

**Quest-type probe (`/qc typecheck`).** This asks the client whether each quest recurs. It lives on
the draft pull request #42, branch `tools/quest-type-probe`.

Run it after step 6 has added quests, then run step 3 again. On a sweep that adds nothing, the saved
results are enough.

1. Check out that branch and merge `master` into it. The probe walks the branch's own quest
   database, so quests added since the branch was last updated aren't probed.
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

## Checking a change before its pull request

```powershell
& "C:\Program Files (x86)\Lua\5.1\luac.exe" -p QuestCompletist\qcQuest.lua QuestCompletist\qcCore.lua
(Select-String -Path QuestCompletist\qcQuest.lua -Pattern '^\[\d+\]=\{').Count
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-AddonData.ps1 -Check
git diff --stat
```

- The syntax check must be silent.
- `Build-AddonData.ps1 -Check` must say both files are up to date.
- The quest count should only change when quests were meant to be added or removed. It's 35,023 as
  of September 2026.
- The diff should touch only what the change is about. For data changes, check that only the
  intended field moved on each line.
- The addon's files use Windows (CRLF) line endings. A script that writes them must keep that.
  `.gitattributes` stores `qcQuest.lua` and `qcPinDB.lua` exactly as written.
- For filter or data changes, run `Test-QuestReachability.lua` (step 9) before and after, and compare
  the summaries it prints.

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
| Blizzard's Game Data API | faction, race, class, reputation, daily/weekly flags, quest names | `Audit-QuestAccuracy.ps1`, cached in `tools\quest_api_cache` |
| The game client's own tables, via [wago.tools](https://wago.tools) | task quests, questlines, map positions, map names, dungeon journal | CSV exports per build, e.g. `https://wago.tools/db2/QuestLine/csv?build=<build>` |
| The game itself | recurring or one-time, world quest or not | in-game probes and runtime API calls |
