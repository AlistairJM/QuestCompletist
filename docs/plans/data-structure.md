# How the quest and pin data is stored

Six ideas from 2026-10-03 for storing the quest rows and map pins better, taken up on 2026-10-04.
The aim: less memory in game, and tools that work with named fields instead of positions in a
row of 14 values.

## Where things stand

| Point | What | Status |
|---|---|---|
| 5 | Find a quest's pins once per session; a keyed table for categories' English names | Done, #118 |
| 6 | Quest rows and pins kept in JSON Lines files; the Lua built from them | Stage 1 done (this PR); stages 2 and 3 next |
| 4 | Named fields for the tools | Comes with point 6: tools read and write records through `tools\AddonData.ps1` |
| 1 | Profession, holiday, covenant and prerequisite in their own keyed tables | After point 6, as a change to the build step and to qcCore.lua |
| 2 | The zone text (field 4, never read in game) left out of the rows | After point 6, the same way |
| 3 | The quest ID no longer repeated inside its own row | After point 6, optional |

Measured on the rows alone: 10.55 MB today, 8.79 MB after point 1, 8.25 MB after points 1 and 2,
7.72 MB after all three.

## Point 6, in three stages

1. **The data files, the build step and the export (this PR).** `data\quests.jsonl` and
   `data\pins.jsonl` hold the same records as the Lua. `Build-AddonData.ps1` checks them and writes
   the Lua; `-Check` confirms the two agree. The Lua stays the copy the tools edit, so
   `Export-AddonData.ps1` brings the data files up to date after a tool runs. The Lua text was
   tidied once so the build reproduces it byte for byte; loaded in Lua 5.1, the tidied files give
   identical tables, iterated in the same order:
   - `qcQuest.lua`: the 27 comment and blank lines among the quest rows removed.
   - `qcPinDB.lua`: coordinates written the short way (581 lines, e.g. `42.0` → `42`), `\'` written
     as `'` (145 lines), 17 lines with a doubled carriage return, and 2 quest lists with a stray
     trailing comma.
2. **Move the tools over, a few per PR.** First list exactly which repeatable tools change the quest
   rows or the pins. Each then reads and writes the data files through `AddonData.ps1` and runs the
   build, instead of editing the Lua with regular expressions.
3. **Switch.** Once no tool edits the Lua, the data files become the master copy:
   `Export-AddonData.ps1` is deleted, the generated Lua gets a "generated, don't edit" header, and
   the maintenance notes say to edit only the data files.

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
  Lua keep theirs.
- **Only the quest rows and the pins move.** Menus, categories, storylines and the other tables in
  `qcQuest.lua` stay Lua for now; the build leaves everything outside the quest rows as it is.
- **The PowerShell JSON writer isn't used** for the data files: it writes `'` as `'`. The
  records are written by `AddonData.ps1`, escaping only `\` and `"`.
- **Line endings are pinned in `.gitattributes`.** The two generated Lua files are stored exactly
  as written (Windows line endings), and the data files always use Unix line endings, so `-Check`
  sees the same bytes on any machine.
