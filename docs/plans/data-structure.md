# How the quest and pin data is stored

Six ideas from 2026-10-03 for storing the quest rows and map pins better, taken up on 2026-10-04.
The aim: less memory in game, and tools that work with named fields instead of positions in a
row of 14 values.

## Where things stand

| Point | What | Status |
|---|---|---|
| 5 | Find a quest's pins once per session; a keyed table for categories' English names | Done, #118 |
| 6 | Quest rows and pins kept in JSON Lines files; the Lua built from them | Done. Stage 1 #120; stage 2 #121, #122, #123 and the read-only tools; stage 3 #124. |
| 4 | Named fields for the tools | Done with point 6: every tool reads and writes records through `tools\AddonData.ps1`, and only the build knows the Lua row layout |
| 1 | Profession, holiday, covenant and prerequisite in their own keyed tables | Done, #126, with points 2 and 3 (see below) |
| 2 | The zone text (field 4, never read in game) left out of the rows | Done, #126 |
| 3 | The quest ID no longer repeated inside its own row | Done, #126 |

Estimated beforehand on the rows alone: 10.55 MB, 8.79 MB after point 1, 8.25 MB after points 1
and 2, 7.72 MB after all three. Measured on the real files after the change: the quest data takes
10.43 MB before and 7.57 MB after, 2.85 MB (27%) less.

## Point 6, in three stages

1. **The data files, the build step and the export (#120).** `data\quests.jsonl` and
   `data\pins.jsonl` hold the same records as the Lua. `Build-AddonData.ps1` checks them and writes
   the Lua; `-Check` confirms the two agree. The Lua stays the copy the tools edit, so
   `Export-AddonData.ps1` brought the data files up to date after a tool ran. The Lua text was
   tidied once so the build reproduces it byte for byte; loaded in Lua 5.1, the tidied files give
   identical tables, iterated in the same order:
   - `qcQuest.lua`: the 27 comment and blank lines among the quest rows removed.
   - `qcPinDB.lua`: coordinates written the short way (581 lines, e.g. `42.0` → `42`), `\'` written
     as `'` (145 lines), 17 lines with a doubled carriage return, and 2 quest lists with a stray
     trailing comma.
2. **Move the tools over, a few per PR.** Each reads and writes the data files through
   `AddonData.ps1` and rebuilds the Lua, instead of editing it with regular expressions. The
   inventory (2026-10-04) of the 25 repeatable scripts:
   - **Change quest rows or pins (10).**
     - Batch 1, done: `Apply-AccuracyFixes`, `Sync-QuestNamesFromApi`, `Retype-FlaggedWorldQuests`,
       `Retype-ProbeRecurring`, `File-WeeklyEventQuests`, `Apply-PinNpcIds`.
     - Batch 2, done: `Place-UncategorisedQuests`, `Insert-GapQuestEntries` (which runs it) and
       `Build-QuestLines` (which also rewrites the `qcQuestLines` table, which stays Lua). New quests
       now go at the end of the data file, with no comment lines.
     - Batch 3, done: `Assemble-PinDB`, with `Parse-ExistingPinDB`, which feeds it. The candidate
       for review is now `tools\pins_candidate.jsonl`.
   - **Only read them (10), done after stage 3.** `Apply-ReputationBackfill`,
     `Audit-DungeonCategories`, `Audit-QuestAccuracy`, `Build-CategoryClientNames`,
     `Build-QuestLocationData`, `Build-UnavailableQuests`, `Compare-QuestReputation`,
     `Find-UnavailableQuestCandidates`, `Remove-EmptyMenuEntries`, and `Parse-ExistingPinDB` (moved
     with batch 3). They read the Lua rows by position, so they had to move before points 1 to 3
     change the rows. `Compare-QuestReputation` no longer reports each row's field count, a check
     left over from when reputation sat inside the rows.
   - **Touch neither (5)**, nothing to do: `Add-ZoneTableMaps`, `Build-CategoryUiMapIDs`,
     `Categorize-AuditDiscrepancies`, `Fetch-GapQuestData`, `Get-WagoQuestRequirements`.

   Found along the way:
   - `Apply-PinNpcIds` matched pins by the coordinate text, so stage 1's tidy (`38.0` became `38`)
     left 17 decision rows matching no pin. Fixed in batch 1: it compares coordinates as numbers.
   - `Assemble-PinDB -Apply` rewrote the whole of `qcPinDB.lua`, dropping notes and not escaping
     `\` in names. Fixed in batch 3: it saves through the data file, and a note stays with a pin that
     keeps its spot. It still sorts each map's pins by quest ID, as the pins have always been built.
   - `Parse-ExistingPinDB` couldn't read a name with an escaped quote, so 15 pins, such as
     `Remy "Two Times"`, lost their NPC when the pins were rebuilt. Their quests went to whoever
     stood nearby (Renzik "The Shiv"'s to Monte Gazlowe). Fixed in batch 3: it reads the data file.
   - `Insert-GapQuestEntries` put new quests at the top of the rows, with two comment lines. Fixed in
     batch 2.
   - Every save now first checks that the Lua still matches the data files. Rebuilding it otherwise
     would lose a change an old-style tool made, or a hand edit.
3. **Switch, done.** Once no tool edited the quest rows or pins in the Lua (batch 3), the data files
   became the master copy. `Export-AddonData.ps1` and the Lua readers in `AddonData.ps1` are
   deleted. The generated rows of `qcQuest.lua` (since points 1 to 3, their own file,
   `qcQuestData.lua`) and the whole of `qcPinDB.lua` start with a line saying they're generated from
   the data files. The maintenance notes say to make hand changes in
   the data files and rebuild. The safeguard now tells anyone who edited the generated Lua to make
   the change in the data files instead. Loaded in Lua 5.1, the switched files give identical tables,
   in the same order.

   After stage 3 the read-only tools moved too, so nothing but the build reads or writes the Lua
   rows, and points 1 to 3 only need the build step and qcCore.lua to change.

## Points 1 to 3, done together (#126)

- **A file of its own.** The build writes `QuestCompletist\qcQuestData.lua` whole, as it does
  `qcPinDB.lua`, and the TOC loads it straight after `qcQuest.lua`. `qcQuest.lua` keeps only the
  hand-edited tables, so no file mixes generated and hand-edited Lua.
- **The row** is `{name, level, category, type, faction, race, class, storyline}`, with storyline
  left off when it's 0 (half the quests have none; a missing last value costs nothing).
- **Profession, holiday, covenant and prereq** are in `qcQuestProfession` (1,332 quests),
  `qcQuestHoliday` (911), `qcQuestCovenant` (777) and `qcQuestPrereq` (4,851), keyed by quest ID.
  Since 6 October 2026 a prereq can also be a list, and 7,621 quests have one
  ([quest-table-checks.md](quest-table-checks.md)).
  The code reads them as "nil means none", where it used to test for 0.
- **The zone text isn't written to the Lua.** The game never read it; it stays in the data file for
  the tools.
- **The quest ID isn't repeated inside its row.** The quest list now holds quest IDs rather than
  rows, the list and map filters take `(questId, row)`, and the list sorts by a level and name looked
  up per ID.
- **Tools:** only `AddonData.ps1` and the reachability harness, `Test-QuestReachability.lua`, which
  loads the addon's Lua, needed changing.

Checked against master on the real data, in Lua 5.1:
- every quest's fields match the old layout's, the game walks the quests in the same order, and
  every other table in `qcQuest.lua` is unchanged;
- the reachability report is identical (every quest's and pin's visibility under each filter);
- the quest list for every category under four settings profiles, page by page, is identical:
  each row's quest, text, icon and colour, the order, the completion counts, and seven searches;
- every map's pins under four profiles, including out-of-season holiday quests hidden, are
  identical: icon, greyed or not, and the whole tooltip;
- the quest tooltip of every quest with a storyline or prerequisite, and every tenth other, with
  and without the faction filter, and the new-data alert for every quest and three characters, are
  identical;
- the NPC-name and pin-lookup simulations pass unchanged.
Each of those comparisons was also run against deliberately broken copies of the code, and caught
every one (15 in all).

## Decisions

- **JSON Lines rather than TSV.** 15 quest names and 2 NPC names start with a quote mark
  (`"Crowleg" Dan`, `"Gabby" Gabi`). PowerShell's `Import-Csv` and Excel treat that quote as
  wrapping and silently drop it. JSON Lines also names the field next to each value, so a change to
  one field is readable in a diff. PowerShell 5.1 reads all 35,023 quests in about a second.
- **Fields that are usually empty are left out** of a record rather than written as 0: a quest's
  profession, holiday, covenant, storyline and prereq; a pin's npc, name and note.
- **Records keep the order the Lua has them in.** The order of the rows decides the order the game
  walks the table in, and search results come out in that order.
- **Comments among the quest rows were dropped** (the user's call). The tables that stay hand-edited
  Lua keep theirs. Since stage 3 the build writes one line above the rows, and at the top of
  `qcPinDB.lua`, saying they're generated.
- **Only the quest rows and the pins move.** Menus, categories, storylines and the other tables in
  `qcQuest.lua` stay hand-edited Lua. Since points 1 to 3 the generated quest data has a file of its
  own, so the build doesn't touch `qcQuest.lua` at all.
- **The PowerShell JSON writer isn't used** for the data files: it writes `'` as `\u0027`. The
  records are written by `AddonData.ps1`, escaping only `\` and `"`.
- **Line endings are pinned in `.gitattributes`.** The two generated Lua files, `qcQuestData.lua`
  and `qcPinDB.lua`, are stored exactly as written (Windows line endings), as is `qcQuest.lua`, and
  the data files always use Unix line endings, so `-Check` sees the same bytes on any machine.
