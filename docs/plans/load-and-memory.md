# Load time, memory and search speed

> Since October 2026 the quests live in `data/quests.jsonl` and are built into `qcQuestData.lua` with a different row layout (see [data-structure.md](data-structure.md)). File names, field numbers and code references below describe the addon as it was when this plan was written.

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

### Phase 1 results (2026-09-30, retail 12.1.0, master 2a29d47, English client)

| Measurement | In game | Offline (32-bit) |
|---|---|---|
| Memory after login (the list window opens at login) | 40.5 MB | ~22 MB |
| First search for "T" | 101 ms, 18.5 MB allocated | 61 ms, 8.8 MB |
| Repeat search for "T" (one keystroke) | 60 ms, 15.0 MB allocated | 27–45 ms, 3.4–4.4 MB |
| Memory after searching (garbage collected first) | 58.2 MB (+17.7 MB kept) | – |

- WoW's 64-bit Lua uses about 1.8× the memory of the offline measurements.
- A short search keystroke costs about 4 frames at 60 fps and allocates ~15 MB.
- The 17.7 MB kept after a search is the copies of the 27,642 matching rows (held until the list is
  next rebuilt) plus the client-name index. Phase 2 removes the copies, so it matters more than the
  offline numbers suggested.
- The list window has no `hidden="true"`, so it opens at login, and the list indexes are built at
  login for every player, not only for players who open the list.

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

### Phase 2 results (#102, measured in game on Kranaa)

| | Before (master) | After |
|---|---|---|
| Memory after login | 40.5 MB | 35.4 MB |
| First search "T" | 101 ms, 18.5 MB allocated | 59 ms, 5.8 MB |
| Repeat search "T" (one keystroke) | 60 ms, 15.0 MB | 10.4 ms, 0.75 MB |
| Memory after searching | 58.2 MB | 41.2 MB |

A search keystroke now fits in one 60 fps frame. Offline, every list and search result was
identical to master's (3,461 lines of output).

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

   **When (decided 2026-10-04): the first release after 1 April 2027.** The conversion runs once
   per character, at its first login on 110.7 or later, and releases came three in three days, so
   the measure is time, not releases. A character not logged in since then would keep only what the
   server resyncs, losing the quests marked by hand (completed, unattainable or not done). Keeping
   the conversion costs a TOC entry and one short function. The steps are in
   [../releasing.md](../releasing.md), "Dated changes".

   Formats, from Kranaa's saved file: before, `[31730] = { ["C"] = 1, },` (one table per quest);
   after, `[31730] = 1,`. The values are unchanged: 1 completed, 2 unattainable, 0 marked not done by
   hand; no entry means nothing recorded. Only the `C` field has ever been used.

## Status

- 2026-09-30: plan written from offline measurements, decisions agreed. Phase 1 measured in game. Phase 2 in #102, measured in game (results above). Next: phase 3.
- Phase 3 on `perf/completions-as-numbers`. A scratch simulation plays the same sequence through
  master and the branch from three starting points: no saved data, a copy of Kranaa's saved file,
  and a synthetic file with 0/1/2 marks. The sequence is loading, the login reset, the server sync,
  shift/alt-click cycles on daily, weekly and one-time quests, turn-ins (with breadcrumb and
  exclusive marks), the daily/weekly reset, and clearing the cache. After each step it dumps every
  quest's mark, every category's rows (colour and icon) and counter with "hide completed" off and
  on, pin tooltips, drawn map pins and breadcrumb toasts. **16,964 lines per start, identical
  apart from the old variable now being emptied.** Four deliberate breakages were each caught.
  The conversion check on Kranaa's file converted all 12,259 records with the same mark (two are
  for quests not in our database), and the saved file goes from 346 KB to about 155 KB. Broken
  records are dropped without an error, an existing new-format mark wins, and a second login changes
  nothing. Found in passing: master errors on a completion record that isn't a table; the
  conversion drops such records.
- Phase 3 in game (Kranaa, full restart): completed zones, the counter and hand marks behaved as
  before, and marks survived `/reload`. In the saved file afterwards, all 12,259 marks from the backup
  were present (0 changed, 0 lost, all plain numbers), plus the two test marks. The old variable is
  written as `qcCompletedQuests = nil`, and the file went from 355 KB to 171 KB.
- 2026-10-09, `qcQuestMinLevel` (the level a character needs to take a quest; see
  [data-structure.md](data-structure.md)), measured as above (Lua 5.1 on this PC, 32-bit, memory
  after a full collection):
  - Forever's `qcQuestData.lua` goes from 305,031 to 353,979 bytes (+48,948, +16%) and, once loaded,
    from 1,275.2 to 1,531.2 KB (+256.0 KB, +20%). The whole addon loaded on Forever's TOC goes from
    2,255.3 to 2,511.6 KB (+256.3 KB, +11%). The table has 4,180 keys, 82% of Forever's quests.
  - Loading the file takes about 7.4 ms before and 8.6 ms after (40 loads a run, eight runs, the
    medians), about 1.2 ms more (1.25 to 1.7 ms in the pairs a reviewer ran).
  - WoW's 64-bit Lua was not measured, as this PC has Lua 5.1 only as a 32-bit build. The 1.8×
    above is for the whole addon, mostly strings and row tables, and isn't known to hold for a table
    of numbers, so no 64-bit figure is given.
  - Against a ninth value in the rows, on the same footing (the 5,081 rows rebuilt by one script
    from the loaded data, keeping only what each variant needs, less the bare interpreter's 19 KB):
    the rows alone take 1,031 KB, with the keyed table 1,287 KB (+256.0 KB), with a ninth value
    1,162 KB (+130.5 KB, a nil filler where a row has no storyline), and with a ninth value in every
    row 1,190 KB (+158.6 KB). So the keyed table costs about twice what the ninth value would in
    memory. It was chosen because the project prefers a keyed table for sparse data to a new field
    in the row layout both games share (`qcQuestHoliday` and the other sparse tables were made so),
    and it is the design the user approved.
  - Retail's file gains an empty table (22 bytes), and its loaded size is unchanged: 15,174.0 KB
    for the whole addon before and 15,173.5 KB after.
- 2026-10-11, retail's `qcQuestMinLevel` is filled: 1,623 entries (`Apply-QuestMinLevels.ps1`; the quests'
  minimum levels from the API and the client's level ranges, [data-structure.md](data-structure.md)).
  Measured on `qcQuestData.lua` alone (Lua 5.1 on this PC, 32-bit; `dofile` in a fresh state, memory
  after two full collections; load time the median of 8 runs of 20 loads, in three before-and-after pairs).
  The first measurement had 1,628 entries, five of them the 0s of quests on tuning 0 that the user chose to
  leave as they were; the bytes are recounted for 1,623 and the memory measured again:
  - The file goes from 2,373,371 to 2,394,329 bytes (+20,958, +0.9%): a line of about 13 bytes for each
    entry.
  - Loaded, from 9,175.8 to 9,239.8 KB (+64.0 KB, +0.7%): a hash part of 2,048 slots of 32 bytes, the same
    for 1,623 keys as for 1,628 (both files load to the same size). Forever's 4,180 keys cost 256 KB, a
    hash part of 8,192, the same 32 bytes a slot.
  - Loading takes 65.1 to 66.2 ms before and 67.3 to 67.8 ms after (+1.5 to 2.2 ms), timed with the 1,628
    entries and not again: five lines fewer are within the run-to-run noise.
  - The whole addon on retail's TOC and WoW's 64-bit Lua were not measured; the table is a keyed table of
    numbers, and +64 KB is under 0.5% of the 15,174 KB the whole addon took.
- 2026-10-16, retail's `qcQuestMaxLevel`, the level a scaling quest stops scaling at (`Apply-QuestScaling.ps1`,
  27,637 entries; [maintenance.md](../maintenance.md#2j-scaling-quests-levels)). Measured on `qcQuestData.lua`
  alone, as above (Lua 5.1 on this PC, 32-bit; `dofile` in a fresh state, memory after two full collections;
  load time the median of 8 runs of 10 loads, twice):
  - The file goes from 2,461,508 to 2,819,637 bytes (+358,129, +14.5%), a line of about 13 bytes for each entry
    (on the data with the 33 story quests, #360's names, #361's types and #362's merged in; on the data before
    them, 2,458,901 to 2,817,030, the same +358,129).
  - Loaded, from 9,381.1 to 10,405.2 KB (+1,024.1 KB, +10.9%; before those merges 9,375.0 to 10,399.0 KB): a
    hash part of 32,768 slots of 32 bytes, as 27,637 keys are more than 16,384.
  - Loading takes 65.5 to 76.4 ms before and 81.8 to 84.5 ms after, about 8 to 16 ms more (timed on the data
    before those merges, and not again); the two pairs differ by more than the change in one of them, so the
    figure is rough.
  - Forever's file gains an empty table (22 bytes). The whole addon and WoW's 64-bit Lua were not measured.
    The table is keyed by quest, as the project keeps sparse quest data (data-structure.md), though its
    values come from 771 tunings: a table of tunings would still need each quest's tuning, a table of the
    same size.
- 2026-10-16, retail's `qcQuestTuning` (28,680 quests) and `qcTuningSample` (537 tunings), option E of
  [quest-scaling-redirects.md](quest-scaling-redirects.md). Measured on `qcQuestData.lua` alone, as above (Lua 5.1
  on this PC, 32-bit; `dofile` in a fresh state, memory after two full collections; load time the median of 8
  runs of 10 loads, twice):
  - The file goes from 2,822,865 to 3,239,164 bytes (+416,299, +14.7%).
  - Loaded, from 10,434.2 to 11,529.4 KB (+1,095.2 KB, +10.5%): a hash part of 32,768 slots for 28,680 keys,
    and 537 small sample lists.
  - With every quest's tuning, 33,250 keys, it would load to 12,553.4 KB (+2,119.2 KB): more than 32,768 keys
    take a hash part of 65,536 slots. So `qcQuestTuning` leaves out the 4,570 quests no sample can say
    anything about (on a tuning no redirect names, or one with no sample).
  - The room left before that step: 4,088 keys for `qcQuestTuning` (28,680), and 5,131 for `qcQuestMaxLevel`
    (27,637). If `qcQuestTuning` also held the 3,530 quests that scale on unredirected tunings (32,210 keys,
    so that `qcQuestMaxLevel` could go), 558; the addon code (17 October 2026) kept `qcQuestMaxLevel` for that room. A sweep that gives a few thousand more quests a sampled tuning,
    such as a new expansion's, would cross it, so step 2j prints both tables' keys against 32,768 and flags a
    table over it ([maintenance.md](../maintenance.md#2j-scaling-quests-levels)).
  - `dofile` takes 80.3 and 85.3 ms before and 90.4 and 86.3 ms after, too noisy to give more than "a few ms";
    running the compiled file alone takes 10.6 and 10.8 ms before and 11.5 and 11.4 ms after, under 1 ms more.
  - The code that reads them (17 October 2026) keeps a level per tuning read since the last view was built
    (537 at most) and, from the first quest data that arrives, an index of the 1,432 samples by tuning. With
    Forever's empty tables both stay empty.
  - Forever's file gains two empty tables (41 bytes) and loads to the same 1,576.9 KB. The whole addon and
    WoW's 64-bit Lua were not measured.
  - Measured again on master after #381 (17 October 2026), which added the start items: the file goes from
    2,859,950 to 3,276,249 bytes (the same +416,299) and loads from 10,668.9 to 11,763.9 KB (+1,095.0 KB).
    Forever's loads to 1,645.1 KB before and 1,645.0 KB after, the same within a collection's noise.

## The quest giver recorder (8 October 2026)

`qcRecorder.lua` keeps `qcQuestRecorder`, an account-wide saved variable, with one packed string per
record and caps of 5,000 givers, 10,000 quests and 4,000 quests started away from a giver (2,500,
5,000 and 500 until 10 October 2026; [quest-giver-recorder.md](quest-giver-recorder.md)). Measured
offline with a synthetic full file in plain Lua (32-bit, so the game's numbers are larger):

| | Records | File | Memory once loaded | Load |
|---|---|---|---|---|
| At the first caps (2,500 + 5,000 + 500) | 8,000 | 514 KB | 0.8 MB (about 1.5 MB in the game) | 6 ms |
| At the caps of 10 October 2026 (5,000 + 10,000 + 4,000), the same method as the line below | 19,000 | 1.25 MB | 3.3 MB | 15 ms |
| The first caps again, in that method (a heavier synthetic record) | 8,000 | 555 KB | 1.45 MB | 4.3 ms |
| A table per record instead | the same | | 2.2 to 3 times as much | |

The code itself adds a file of about 590 lines and nothing at login but one pass over the three
tables to check the shape of each key and value. In the game: the cost of an event is two small
list calls, one GUID read, one map position and a few string operations on at most two records.
Today's account file is about 1 KB. The in-game memory is to be measured in the recorder's session.

## The task quests (11 October 2026)

Step 6b of the sweep added 506 task quests to retail's data ([maintenance.md](../maintenance.md), step 6b), 35,023 to 35,529 (+1.4%), 18 of them with a profession and 25 with a holiday. Measured as above (Lua 5.1 on this PC, 32-bit, memory after a full collection, three loads of each file):

| | Before | After | |
|---|---|---|---|
| qcQuestData.lua on disk | 2,373,371 bytes | 2,405,155 bytes | +31,784 (+1.3%) |
| Loaded (all the quest tables) | 13,660 KB | 13,803 KB | +143 KB (+1.0%) |
| Load (parse and run) | 56 to 61 ms | 64 to 65 ms | about 7 ms more |

In the game, with the 1.8 times above, that is about 0.26 MB of the 35 to 40 MB the addon takes. The structures built later grow in proportion, by an estimate and not a measurement: the category index (0.8 MB) and the upper-cased names a first search builds (3.2 MB) by about 1.4% each, 56 KB together. qcPinDB.lua is untouched, as the new quests have no pins. Of the 506, 297 (world quests, weeklies and dailies) are hidden from a default list, and the other 209 show in 22 categories that already existed, 26 of them in Uncategorized.
