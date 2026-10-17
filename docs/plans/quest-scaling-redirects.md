# Scaling quests: redirected content tunings

## Summary

Retail's scaling ceilings (`maxLevel`, `qcQuestMaxLevel`, open-items.md row 9, option C, #364) are the
levels the probe's character got. The game moves a quest's level range for some characters and not for
others, by redirect bits the server sends each character, which no addon call reads. On 16 October 2026
the user took **option E**: ship each retail quest's content tuning and a few quests per tuning to read
the game's own level from, at run time, with the stored ceilings as the fallback. Two pull requests:

1. **Data and tools** (#378): each quest's `tuning`, `data\tunings.jsonl` with the samples, the Lua
   tables `qcQuestTuning` and `qcTuningSample`, and step 2j's checks.
2. **Addon code** (#382, stacked on it, below): the list, the map and the continent icons read a sample's
   level, under the performance rule below, checked offline by `Test-QuestScaling.lua`; one short check
   in game is left (open-items.md, "To try in game").

## How a quest's level is chosen

A retail quest's `ContentTuningID` gives its level range. The client's `ConditionalContentTuning` table
lists redirects: a row sends a tuning (`ParentContentTuningID`) to another (`RedirectContentTuningID`) for a
character whose redirect bit `RedirectEnum` is on. The server sends each character its bits (TrinityCore:
`m_playerData->CtrOptions->ConditionalFlags`), and no addon call reads them. TrinityCore's
`DB2Manager::GetRedirectedContentTuningId` takes a tuning's rows by `OrderIndex`, highest first, and the
first row whose bit is on wins. `Player::GetQuestLevel` then gives the character's level, raised to the
redirected tuning's minimum and held down at its maximum. A tuning no row names is never redirected, so
every character gets its own range.

On 12.1.5.70391 the table has 2,564 rows and 39 `RedirectEnum` values, and redirects 1,031 tunings. The
largest are 34 (772 rows), 0 (638), 13 (498), 5 (165) and 30 (105). The rows per value are the baseline in
[quest-scaling-redirects-baseline.csv](quest-scaling-redirects-baseline.csv).

The probe's character had bits 1, 5, 14 and 33 on, standing in a Midnight zone. The research of 16 October
fitted the bits to the 15 October run: with no bit on, the client tables give another level at 90 than the
quest pass for 1,239 of the 28,448 quests it loaded fresh (`ok`) with a level and a tuning, and with 1, 14 and
33 on, for none. The map pass's level ranges need bit 5 as well: with no bit on, 23 of its 182 maps with a
range and a tuning differ, and none with 1, 14, 33 and 5. So the stored ceilings hold for a character with
those bits, and for nobody else where a redirect applies.

## The readings of 16 October 2026

On the probe's level 90 mage, with
`/run local s=GetZoneText()for _,q in ipairs({11,26024,26042,7781,28713,78642,78126,60514,94871,54})do C_QuestLog.RequestLoadQuestByID(q)s=s.." "..q.."="..C_QuestLog.GetQuestDifficultyLevel(q)end print(s,C_Map.GetMapLevels(37))`:

> In-game, same level 90 mage: in Nazmir (Zandalar; the character's housing Endeavor 'Vacation Season'
> (24, Zandalar/Kul Tiras) is active) bit 34 is ON: 11=90 26024=90 26042=90 7781=90 28713=10 78642=90
> 78126=80 60514=90 94871=90 54=10, Elwynn map levels 25-90; in Silvermoon City and in Elwynn Forest it is
> OFF: 11=30 26024=30 26042=30 7781=30 28713=10 78642=80 78126=80 60514=90 94871=90 54=10, map 1-30.
> 78642 shows the HIGHEST OrderIndex redirect wins. Every probed tuning (771 tunings, 29,809 readings) gave
> ONE level for all its quests (26024's earlier 60 was a misread).

Against the data this pull request writes:

| Quest | Tuning | Its redirects | Stored (maxLevel, else level) | Nazmir (34 on) | Silvermoon, Elwynn (34 off) |
|---|---|---|---|---|---|
| 11 Riverpaw Gnoll Bounty | 73 | 0, 13, 34 | 30 | 90 | 30 |
| 26024 Wanted!  Marez Cowl | 17 | 0, 13, 34 | 30 | 90 | 30 |
| 26042 Breaking the Keystone | 17 | 0, 13, 34 | 30 | 90 | 30 |
| 7781 The Lord of Blackrock | 1005 | 0, 34 | 30 | 90 | 30 |
| 28713 The Balance of Nature | 1478 | 13 | 10 | 10 | 10 |
| 78642 New Candle, New Hope | 2798 | 14, 32, 34 | 80 | 90 | 80 |
| 78126 Lightbringer's Duty | 2462 | 32 | 80 | 80 | 80 |
| 60514 Hunting Trophies | 746 | 0, 1, 13, 34 | 90 | 90 | 90 |
| 94871 Eversong | 3085 | 33 | 90 | 90 | 90 |
| 54 Report to Goldshire | 1476 | none | 10 | 10 | 10 |

Every quest whose tuning a bit-34 row names went to 90 in Nazmir, and every other kept its stored level;
with bit 34 off, all ten read their stored level. Tuning 2798's own range stops at 75, and it has rows for 14
(`OrderIndex` 0, to a 70 to 80 range), 32 (1) and 34 (2, to a 25 to 90 range). 78642 read 80 with bit 34 off,
the bit-14 row's level, and 90 with it on: the row of highest `OrderIndex` won, as TrinityCore takes them.

## The decision: option E

Taken by the user on 16 October 2026, after #371: ship each retail quest's ContentTuningID and 2 or 3
representative quests per tuning. At run time the addon takes `C_QuestLog.GetQuestDifficultyLevel` of a
representative whose data the client already holds as that tuning's level, the game's own answer in any
redirect state (an Endeavor zone, Chromie Time, an alt without the probe's bits), with today's stored
ceilings as the fallback.

**The performance rule** (the user asked for it, given #371): the map and continent views never call
`RequestLoadQuestByID` and never force a map refresh; they only read representatives the client already
holds. Only the quest list asks, for the tunings of its current category whose stored shown level is below
the character's level (otherwise nothing can change), through the existing queue of four requests at a
time (`qcRequestQuestData` in `qcCore.lua`), with at most one batched list redraw when the answers change
something. Quest loads today redraw only list rows and tooltips, never map pins, and that stays so. Loaded
quests stay in the client's quest cache on disk, so the map finds them on later refreshes.

Forever's quests don't scale (`Apply-QuestScaling.ps1 -Game forever` checks it at each probe run), so its
tables stay empty and its behaviour doesn't change; the shared code is gated on the data, not on the game
([game-parity.md](game-parity.md)).

## What the first pull request (#378) ships

Written by `Apply-QuestScaling.ps1` (step 2j, [maintenance.md](../maintenance.md#2j-scaling-quests-levels)),
from the 12.1.5.70391 sources:

- **`tuning` on 33,250 of the 35,687 retail quests**: 29,811 from the joined quest cache
  (`tools\retail_quest_cache_12.1.5.70391.jsonl`) and 3,439 from the task table (`QuestV2CliTask`). 16 are
  on tuning 0 (14 in the cache, 2 in the task table), which has no range, and 2,421 have none in either, so
  they get none. World quests are among them. The 2,421 include the 33 item-started quests #380 added
  (35,654 quests before it), which neither source has.
- **`data\tunings.jsonl`, 537 records**, one per tuning our quests are on that a `ConditionalContentTuning`
  row names and the probe sampled: `{"id":73,"level":30,"redirects":[0,13,34],"samples":[11,35,37]}`.
  `level` is what the samples answered at the cap in the probe, `redirects` the tuning's `RedirectEnum`
  values, `samples` the quests to read, the first preferred. The build writes them to `qcTuningSample`
  (`[73]={11,35,37}`) and the tuning of each quest on them to `qcQuestTuning` (`[11]=73`), 28,680 quests.
- **Which tunings.** Our quests are on 783 tunings. A redirect names 543; the other 240 give every
  character their own range, which the stored ceiling already holds, so they need no samples. 537 of the
  543 have samples: 424 with 3, 47 with 2 and 66 with 1 (a tuning with one loaded quest has one sample). The
  6 left (2251, 2306, 2330, 2516, 2535 and 2862, 11 quests) have no level in the probe; their quests keep the
  stored level and get a sample when a probe loads one.
- **The samples, 1,432 quests.** A sample is a quest the probe loaded (`ok` or `cached`, with a level above
  0) at its tuning's one level; a late answer doesn't count. They are taken in this order: a quest of ours,
  in `QuestV2` 12.1.5, not flagged in `unavailable-quest-decisions.csv`, one-time rather than recurring (the
  addon's `qcRecurringTypes`), open to both factions, then the lowest ID. 1,393 of them are in `QuestV2`,
  1,310 are one-time, 1,216 are open to both factions, and one is flagged unavailable: 42905, whose tuning
  627 has only it and 42904, which `QuestV2` lacks. The faction step is there because the probe's Alliance
  character loaded the other faction's quests about as often as its own (5,519 of the 6,589 Horde-only
  quests it asked, 5,828 of the 6,739 Alliance-only ones), but no retail probe run has had a Horde
  character, so a quest of both factions is the one the evidence covers for every character. A later run
  keeps a stored sample while the newest probe still loads it at its tuning's level, unless a quest of a
  better kind in that order can take its place, and only tops a tuning up: the map reads only samples the
  client holds, and players' clients may hold the stored ones already.
- **Why `qcQuestTuning` holds 28,680 quests and not all 33,250.** The other 4,570 are on the 240 tunings no
  redirect names (4,559) or on the 6 with no samples (11): no sample can say more about their level than the
  stored one does, and they keep their tuning in the data. Leaving them out keeps the table under 32,768
  keys, with 4,088 to spare: a sweep that gives a few thousand more quests a sampled tuning, such as a new
  expansion's, would cross it, and step 2j prints the count against it. Measured on `qcQuestData.lua` alone
  (Lua 5.1 on this PC, 32-bit, `dofile` in a fresh state, memory after two full collections): 10,434.2 KB
  before, 11,529.4 KB with this pull request (+1,095.2 KB), and 12,553.4 KB with all 33,250 (+2,119.2 KB),
  as 33,250 keys take a hash part of 65,536 slots. The file grows from 2,822,865 to 3,239,164 bytes. Forever's gains two empty tables (41 bytes) and loads to the same size.
  On master after #381 (17 October 2026), with the start items: 10,668.9 KB before and 11,763.9 KB after
  (+1,095.0 KB), and 2,859,950 to 3,276,249 bytes, the same +416,299.
- **`maxLevel` stays as it is**, the fallback. It is the per-tuning level without loss: for every one of the
  35,687 quests, `maxLevel` is its tuning's level where that is above the quest's minimum and is missing
  otherwise, and no quest has a `maxLevel` without a tuning. Replacing `qcQuestMaxLevel` (27,637 keys, a
  32,768-slot table) by a level per tuning would save about 1 MB, but needs the addon to read it, which this
  pull request doesn't change, and `qcQuestTuning` to hold the 3,530 quests that scale on unredirected
  tunings too: 32,210 in all, still under 32,768 keys but with only 558 to spare. The second pull request
  kept `qcQuestMaxLevel` as it is, for that room.

## The sweep's checks

Step 2j now also writes the tunings and the samples, and checks them: `-Check` exits 1 when a quest's
`tuning` or `tunings.jsonl` isn't what the sources say, which includes a stored sample the newest probe no
longer loads, or no longer gives its tuning's one level, or that moved to another tuning (each is listed,
and the applying run replaces it). A stored sample that is still valid is kept, so a fuller probe only
adds samples, except where one gives way to a better kind or to a lower `-Samples` (listed with why).
Applied with the 14 October probe file and then the 15 October one, 19 tunings were added and 20
changed: 14 topped up, and 6 samples gave way to a quest open to both factions or one-time; before
stored samples were kept, 57 changed, though none was stale. A sampled tuning whose level moved is listed,
as many at once can mean the probe's character had other bits; so before a quest pass, the `/run` line
above should read 30 for 11 and 80 for 78642 where the probe stands. It compares the redirect table
with its baseline: the rows per `RedirectEnum`, the values gone and those with another row count are
reported, and a value the baseline lacks fails `-Check`, because it is a redirect no sweep has read. Look
at the tunings it names, then `-UpdateBaseline` takes it in (not with `-Check` or `-WhatIf`, which write
nothing). It counts the keys of `qcQuestMaxLevel` and `qcQuestTuning` against 32,768 and flags a table
over it. `-Game forever` fails if Forever's data holds a `tuning` or a `tunings.jsonl`. The run is
idempotent: a second one changes nothing.

## What the second pull request does

The addon code (#382, `qcTuning` in `qcCore.lua`; [maintenance.md](../maintenance.md#2j-scaling-quests-levels),
"How the addon reads the samples"), under the rule above:

- **The level.** A quest in `qcQuestTuning` reads `C_QuestLog.GetQuestDifficultyLevel` of the first sample of
  its tuning that gives a level above 0 (a secret value counts as none). That is the level of every quest on
  the tuning for this character now: TrinityCore's `Player::GetQuestLevel` takes it from the tuning alone, and
  each of the 771 tunings probed gave one level for all its quests. With no such sample it reads the stored
  level, as before. `qcShownQuestLevel` keeps its arguments and its answer's meaning, so the list's bracket
  and sort, the low-level filter of the list and the map, the pins and the continent icons all read it.
- **When it is read.** Once per tuning when a view is built, and again after `ZONE_CHANGED_NEW_AREA`,
  `PLAYER_LEVEL_UP`, `UNIT_CTR_OPTIONS` (registered for the player, in a `pcall` for a client without the
  event; it also rebuilds the list) or a sample's `QUEST_DATA_LOAD_RESULT`.
- **What is asked.** Only the list's category build asks, through `qcRequestQuestData`: for each tuning of
  the category with no level from a sample and a quest stored below the character's level, one sample, the
  first neither answered nor given up. A failed sample gets the queue's own second try after 30 seconds,
  and only after that fails is the next one asked, so one tuning never has two samples loading. The maps,
  the continent icons, their tooltips and search never ask for a sample to get a level. A tooltip or a
  search row still asks for the names of the quests it shows, as before, and one of those can be a sample.
- **What is redrawn.** Once nothing the list waits on is loading, the list is rebuilt once if an answer
  changed a level it read; answers that agree with the stored levels rebuild nothing, and no answer redraws
  a map.
- **Forever** has empty tables, so the code reads no level and asks for no sample there.

One limit of the rule: a tuning whose quests are all stored at the character's level is not asked about, so
a redirect that would put them lower (a character without one of the probe's bits) shows only once a sample
of that tuning is held anyway, from an earlier answer or the client's quest cache.

`Test-QuestScaling.lua` (both TOCs, 68 checks on retail and 11 on Forever, 17 October 2026) plays this
against a game whose levels follow the client's 12.1.5.70391 redirect and ContentTuning tables:
- The ten readings of 16 October, in Nazmir and in Silvermoon City, come out as read.
- With the probe's bits and every sample held, every quest reads its stored level at levels 1, 10, 30, 60
  and 90, but 46 quests at their tuning's minimum whose own level isn't it (24428, 28165, 31497, the 31 of
  tuning 464 such as 50417, 82586, 85085, 91843 and others; open-items.md row 8). They read their tuning's
  level, the game's. Whether they should, or be held to their stored level, is the user's call
  (open-items.md, row 9).
- In Nazmir at 90 with bit 34, its 160 quests on the three tunings bit 34 moves (190, 467 and 1403) read
  their stored levels and are hidden by the low-level filter until the list's samples are answered, then
  read 90, are kept, show as [90] and are drawn on Nazmir's map. The list asked for the first sample of each
  of the 6 tunings with a quest stored below 90, once, and was rebuilt once.
- In Chromie Time at 40, 11 "Riverpaw Gnoll Bounty" reads 30 and is hidden until its sample is answered,
  then 40.
- With no quest name held, drawing all 544 maps' pins (with the low-level filter on and off) and a
  continent of every zone, and hovering the continent's 178 icons, ask the game for nothing, as on master.
  With every name held, hovering all 9,667 pins and a search ask for nothing either. With none held, those
  two ask for the names they show: 25,809 quests (25,805 before master's #379 to #381 were merged in), 1,163
  of them samples, the same quests as with the samples taken out of the data. Building every one of the 482 categories in turn asks for one sample of each of the
  427 tunings that needed one.

The in-game check is open-items.md's "Scaling quests in an Endeavor's zones", under "To try in game": 47919
"Just Say No to Cannibalism" at "[90]" in Nazmir with the Endeavor active, and at "[60]" in Silvermoon City.
