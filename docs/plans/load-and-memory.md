# Load time, memory and search speed

## Goal

Item 4 of the improvement list: measure what the addon costs at login and while it runs, then cut
the costs worth cutting. The measurements below changed the priorities: the biggest user-visible
cost is **search**, not memory.

## Measured offline (2026-09-30, master 2a29d47)

Lua 5.1 on this PC is 32-bit and WoW's is 64-bit, so WoW's absolute numbers are larger. The
relative sizes should hold. In-game numbers are phase 1.

**Loading the addon:**

| Part | Memory | Load time |
|---|---|---|
| Quest database, `qcQuest.lua` (35,023 quests, one 14-field table each) | most of the total | 96 ms |
| Pin database, `qcPinDB.lua` | ~3–5 MB | 31 ms |
| Everything else (menus, 11 language files, core) | < 1 MB | – |
| **Total once loaded** | **~17.8 MB** | **~130 ms** |

**Built later, on first use:**

| What | When | Memory | Used by |
|---|---|---|---|
| Category index | first time the list opens | 0.8 MB | browsing |
| Upper-cased English names | first time the list opens | 3.2 MB | **search only** |
| Upper-cased client names (#100) | first search | 3.1 MB with every name known | search only |

**List and search work** (garbage collection paused, so everything allocated is counted):

| Action | Allocated | Time |
|---|---|---|
| Rebuild Elwynn Forest (101 quests) / Isle of Dorn (327) | 18 / 106 KB | < 1 ms |
| Redraw the rows | 0 | < 1 ms |
| First search keystroke "T" (27,642 matches) | **8.8 MB** | **61 ms** |
| Each further short keystroke ("TH", "THE", "THE ") | **3.4–4.4 MB** | **27–45 ms** |
| A specific search ("HOGGER") | 1 KB | 5 ms |

A frame at 60 fps lasts about 16 ms, so each short keystroke drops two or three frames, and leaves
megabytes for the garbage collector to clear later.

**Saved completions:** `qcCompletedQuests` stores one table per quest, `{["C"] = 1}`. The biggest
character (Kranaa) has 12,259 of them, every one `C = 1`. That's 355 KB on disk and 1.3 MB in memory.
As plain numbers, the same data is ~0.26 MB in memory and ~155 KB on disk.

## Findings, biggest first

1. **Search copies every matching quest.** `qcGetCategoryQuests` deep-copies each matching row
   (`qcCopyTable(holdingTable)`, qcCore.lua:635 and :650): all 14 fields of every match, on every
   keystroke. Nothing writes to those rows, and sorting only reorders the list, so the copy does
   nothing. The search itself takes ~5 ms; the copy is the rest. Category rebuilds copy too, but
   they're small.
2. **Search-only data is built for browsing.** The 3.2 MB of upper-cased English names is built the
   first time the list opens, though only search reads it. The client-name index (#100) stores a
   name for every quest the client knows, which on an English client duplicates the English index
   almost exactly: 3.1 MB for about five names that differ.
3. **Completions as tables.** About 1 MB of memory and 200 KB on disk on a big character, plus the
   work of reading all those tables at login.
4. **Not worth changing:** the quest database's layout (one table per quest). A packed layout would
   save a lot of memory, but every one of the hundreds of places that reads `e[n]` would change, for
   memory the game hardly notices. The pin database is small enough as it is.

## Phases

### Phase 1: baseline in game (no code)

Using standard `/run` commands, on the big character (Kranaa) and a fresh one:
- memory straight after login;
- after opening the list;
- after a search for "t";
- the time a one-letter search takes.

The exact commands go to the user when this phase starts. The same commands are run again after
each later phase.

### Phase 2: search (one PR)

1. **Drop the copies.** `qcCategoryQuests` holds the database rows themselves.
   `qcCopyTable` then has no callers and goes.
2. **Build the English search index on the first search,** not when the list first opens. People
   who never search save 3.2 MB.
3. **Keep only client names that differ from the English one,** in the client-name index. On
   English clients it shrinks to a handful; on German clients it's barely smaller.
4. **Check** with the scratch simulations: the list and search output must be identical to master's
   (same rows, same order, same counts) across categories and search terms, and the #100 name
   simulation must still pass. Measure again offline and in game.

Expected: a short keystroke goes from 27–61 ms and 3–9 MB to about 5 ms and almost nothing
allocated, and the list's first open costs 3.2 MB less.

### Phase 3: completions as numbers (one PR)

`qcCompletedQuests[questId]` becomes the mark itself: 1 = completed, 2 = unattainable, 0 = marked
not done by hand (the same values `C` holds now). It's converted once when the addon loads.
Around 38 places read or write it today.
- **Check:** convert a copy of Kranaa's saved file offline and compare every quest's mark before
  and after. Simulate the shift/alt-click cycles (0↔1, 0↔2, 1↔2), the daily/weekly resets, the
  breadcrumb and exclusive marks, and the server sync. Then test in game on Kranaa and a fresh
  character.
- **Decision needed (below):** what an older version of the addon does with the new format.

## Decisions (agreed 2026-09-30)

1. **Delay search while typing?** Waiting ~0.2 s after the last keystroke would skip the work for
   keystrokes typed quickly in a row.
   **Recommendation: no**, once phase 2 brings a keystroke to ~5 ms. Search would feel less
   immediate for no real gain. Revisit if phase 1 shows it's still slow in game.
2. **Saved format and older versions.** If phase 3 keeps the name `qcCompletedQuests`, an older
   version of the addon installed later would find numbers where it expects tables, and error on
   the first quest it looks at.
   **Recommendation:** save under a new name, `qcCharacterCompletions`. The TOC has to declare
   **both** names for a while (a few releases), because WoW only loads saved variables the TOC
   declares, and the old data must be loaded to be converted. On the first login with the new
   version the addon converts `{["C"] = n}` to `n`, then sets `qcCompletedQuests` to nil so WoW
   leaves it out of the file. An older version would then find its variable empty and rebuild
   completions from the server, losing only hand-made marks, instead of erroring. It's also the
   cleaner name. Cost: a TOC change, so players need a full restart after updating, as with any
   addon update. Once enough releases have passed, the old name comes out of the TOC.

   Formats, from Kranaa's saved file: before, `[31730] = { ["C"] = 1, },` (one table per quest);
   after, `[31730] = 1,`. The values are unchanged: 1 completed, 2 unattainable, 0 marked not done by
   hand; no entry means nothing recorded. Only the `C` field has ever been used.

## Status

- 2026-09-30: plan written from offline measurements, decisions agreed. Next: phase 1 in game.
