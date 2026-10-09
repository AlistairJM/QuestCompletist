# Retail's quest cache

What the retail client's quest cache holds, how it is read, and what it says about our data. It is
recommendation 6 of [game-parity.md](game-parity.md): the reader Forever has, for retail too. The
runbook step is [maintenance.md](../maintenance.md), step 2e. Counted on 9 October 2026 on the cache
of retail build 12.1.0.69933 (32,713 quests) against the data of master a288b24 (35,023 quests) and
the API cache of build 12.1.0_68914.

## What it is

The client keeps the server's record of every quest it has asked about in
`Cache\WDB\enUS\questcache.wdb`. Retail's is TrinityCore's `QueryQuestInfoResponse` record, as
Forever's is, with 120 fixed numbers where Forever's has 122: retail's record has no `QuestLevel` and
no `QuestMinLevel`, only the `ContentTuningID` that Blizzard's level range is a function of. The
fields the reader takes, as their position among the fixed numbers:

| Field | Forever | Retail |
|---|---|---|
| quest type (0 includes every repeatable quest and many that are not: repeatable is 0 and not in `QuestV2`; 1 disabled, 2 normal, 3 task) | 1 | 1 |
| level, minimum level | 2, 4 | none |
| content tuning | none | 3 |
| sort (zone, or minus a QuestSort heading) | 6 | 4 |
| quest info (1 group, 41 PvP, 62 raid, 81 dungeon ...) | 7 | 5 |
| suggested group size | 8 | 6 |
| follow-up quest offered on hand-in (`RewardNextQuest`) | 9 | 7 |
| start item (see below) | 24 | 22 |
| flags, flags Ex | 25, 26 | 23, 24 |
| reputation rewards, five slots of four numbers | 75 | 73 |
| allowed races, a 64-bit mask | 110, 111 | 108, 109 |
| quest giver (creature ID; empty in every record so far) | 117 | 115 |
| list counts: reward spells, objectives, treasure pickers (2), conditional texts (2), house rewards (2) | 16, 109, 112 and 113, 118 and 119, 120 and 121 | 14, 107, 110 and 111, 116 and 117, 118 and 119 |

After the fixed numbers come the lists, the nine texts' lengths as bits (9, 12, 12, 9, 10, 8, 10, 8
and 11, then the reset-by-scheduler bit) and the texts, title first. The walk of a retail record is
Forever's with the indexes two lower; `Read-QuestCache.ps1` holds one walker and a table of
positions for each game, and takes the game from `-Build` (1.x is Forever, 12.x retail). It refuses
a file that does not end with its 8-byte terminator, so a copy cut short writes nothing.

Three independent derivations (TrinityCore's packet definition, an empirical alignment against
TrinityCore's database, and Forever's walk shifted) arrived at this layout, and a reader written
afresh from the definition read the same 32,713 records to their last byte. Forever's output through
the one reader is the old reader's, plus the new fields, line for line.

## Checked against Blizzard's data

`Compare-QuestCache.ps1` compares the cache with sources that are not the cache: the API's records
(title, sort, daily, weekly, recurs, repeatable, quest info, faction, races, reputation amounts, the
level range of each content tuning) and the client's task table, `QuestV2CliTask` (quest info,
content tuning, start item). A layout that moved one field for another of the same size would still
walk to the last byte, and for those fields this is what would show it. It does not look at the
group size, the follow-up quest, the quest giver, the scheduler bit or the flags bits other than
daily and weekly; the follow-up quest was compared once, by hand, with TrinityCore's (32,688 of
32,688). The first run found nothing:

| Check | Compared | Differ |
|---|---|---|
| title | 28,985 | 0 |
| sort (the API's area, or minus its category) | 28,614 | 0 |
| daily (flags 0x1000 or flags Ex 0x8000), weekly (flags 0x8000), repeatable (quest type 0 and not in `QuestV2`) | 28,985 each | 0 |
| recurs (weekly before daily) | 28,985 | 0 |
| faction, races | 9,273, 728 | 0 |
| reputation reward amounts | 11,690 | 0 |
| one level range for each content tuning (a tuning's commonest range is the one its quests are held to) | 28,983 (741 tunings) | 0 |
| quest info against the API, and against the task table | 1,830, 4,125 | 0 |
| content tuning and start item against the task table | 4,125 each | 0 |

The cache is the server's record, the same one the API publishes part of, so this proves the reader
and not what a player is awarded: where the API and the cache agree they are one source twice.

## What it says about our data

Each of these was counted by one analyst and recounted by a second with a different method; where the
second differed, the number here is the second's. Nothing in our data was changed.

### Level

The record has no level. `ContentTuning` (Blizzard's table, not in `tools\` yet) is the only source of
a quest's minimum, in TrinityCore's `Player::GetQuestMinLevel` too. The API's `min_character_level`
and `max_character_level` are a function of the cache's content tuning (741 tunings, 28,983 quests,
no conflict, though the two are different builds), and the cache's content tuning equals the task
table's for 4,125 of 4,125.

- The API gives a minimum for 30,066 of our 35,023 quests. Our `level` equals it for 28,455 and
  differs for 1,611: 191 of those are our 0 against its 1, which means the same, 1,420 are different,
  and 932 are our expansion cap (70 or 50) against a minimum of 10 to 40, a different notion of level
  rather than a wrong one.
- Of the 4,955 quests the API has no record of, the content tuning gives a level range for 4,305
  (the task table alone for 3,894; the cache adds 411): 4,088 equal our level, 217 differ. 650 have
  none. Together 34,371 quests have a Blizzard level range.
- 37 content tunings in use have no range (154 quests, none with an API record): they need the
  `ContentTuning` table. It would also say whether the API shows `MinLevel` or `MinLevelWithDelta`,
  and settle the rule for a quest of the other faction. Tuning 0 means no minimum.
- **Decision for the user** (open-items.md row 14, beside row 8's refresh from the API): whether
  retail's gate comes from the tuning. Forever's structure
  already holds it: `level` stays the row's own (the list bracket and the sort) and the gate goes in
  `qcQuestMinLevel`, empty on retail today. It would touch 1,828 quests. The maximum would also fix
  the low-level filter hiding scaling quests early (21,972 quests have a maximum above our level).
  The docs call refreshing retail's levels a separate decision, and the pipeline rule is that
  existing values don't change without cause.

### Reputation

The reader's arithmetic reproduces the API's figure for 11,690 of 11,690 rewards: 8,913 steps from
`QuestFactionReward` row 1, 34 from row 2, 2,743 amounts of the record's own (hundredths), which win
over a step in 751 of 751 slots that have both. Our 11,035 reward rows have no disagreement with the
cache or the API. The cache has rewards ours lack for 2,199 quests (3,144 rewards): 2,196 that have
none of ours, and 3 with an extra faction (41138, 43568, 73226):

- 2,043 quests the API has no record of, with a reward on a faction the client's `Faction` table does
  not flag hidden (`ReputationFlags_0` bit 4), 2,986 rewards (1,871 typed 128 by us; 1,972 are in the
  client's task table). Two more such quests carry only `GarInvasion_Shadowmoon`, which makes 2,045
  (1,974 in the task table). This is the first source for that gap, and `quest-reputation-data.md`'s
  "no per-quest source" was about the client's tables, which still hold. **Decision for the user:**
  backfill the 2,043. The open question is whether the record's template amount is what the game
  awards for a world quest, so spot-check in game first (54538, 51630, 70655, 61783, one type 1
  quest). `qcFactions` needs one entry, 2574.
- The other 156 quests (154 the API has a record of but lists none of these rewards for): 158 rewards,
  157 on 17 factions the API never lists (16 flagged hidden, such as the `GarInvasion` ones, and 1833,
  whose one reward is 42,999), and 2557 on quest 73226, which has 2511 of ours; 2557 is not in the
  client's `Faction` table. Not to be taken without a rule.
- 246 of our reward rows are for quests the cache doesn't have.

### Start item

`startItem` is TrinityCore's `StartItem`: the item the server hands the player when the quest is
accepted (`Quest::GetSrcItemId`, taken back when the quest is abandoned). It is not the item that
begins the quest. 5,049 cached quests have one (3,823 items). TDB gives a `StartItem` to 115 more of
our quests that the cache lacks, the task table to 23 of those 115, and neither differs from the
cache where they overlap. Our data has none of them. 2,167 of the 5,049 have a creature or object as
their starter in TrinityCore (one more, 9731, only an area trigger that completes it), 504 are the
one Dragonriding race timer item, and of the quests whose start item is in CMaNGOS's item table only
32 of 226 (retail) and 47 of 530 (Forever) have an item whose own `startquest` is the quest. Loot
doesn't place quests either: 1,129 of the 3,823 items have no source in TrinityCore, and a drop is
not a start point.

So no "Starts from: <item>" from this field (recommendation 13 of the API review, and the start items
of this document's origin in game-parity.md): the true link is the item's `StartQuestID` in
`ItemSparse` (a client table not in `tools\`), the in-game `QUEST_DETAIL` event's
`questStartItemID` (the Forever probe saves it as a "started" row; no run has produced one), and, for
Forever, CMaNGOS's `item_template.startquest`.

### Recurrence and flags

The cache reproduces the API's `is_daily` (flags 0x1000 or flags Ex 0x8000), `is_weekly` (0x8000) and
`is_repeatable` (quest type 0 and not in `QuestV2`) with no mismatch over 28,985 quests. Every quest
the client calls "Recurring" (3,464 of the 31,425 the probe loaded) has `recurs` or `scheduler`:
3,222 by `recurs`, 242 by the scheduler bit alone. The pair is no stand-in for the class: it holds
for 5,841 of the 31,425, 2,377 more, 1,751 of them in the client's world quest class, and 2,039 of
the 2,668 probed quests that have the bit are not Recurring. The reader writes `recurs` the way
`Retype-ProbeRecurring.ps1` ranks it (weekly wins), and takes a daily from flags Ex 0x8000 too: 1,382
quests are daily only by flags Ex (1,347 are written daily, and the other 35 also carry the weekly
flag, so weekly wins). Forever's 152 flags Ex 0x8000 quests all have flags 0x1000, so its dailies were
not undercounted.

Our quest types, against the cache (none is a probe-derived type; all are in families the retype
tools do not look at): 173 contradictions. 37 typed daily that Blizzard calls weekly; 92 typed
repeatable that Blizzard calls daily (88) or weekly (4), 77 of them in `QuestV2`; 4 typed profession
or seasonal that recur (29320, 29361, 6983, 7043; the addon draws them a permanent tick); 38 one-time
task quests with a daily or weekly flag (the API has no record of them and the client class is Bonus
Objective or World Quest); 2 typed 128 that are daily only (43179, 54349). Not a contradiction: 57300
(type 138), which the addon's bit mask already treats as recurring. Also 17 profession and seasonal
quests in the cache, outside task-type quests, absent from `QuestV2`, that follow the Darkmoon-deck
rule for repeatable; and 21 quests with a `[DEPRECATED]`, `[DNT]` or `[PH]` title that we show.

The 226 typed daily or weekly (types 4 and 128) that carry no daily, weekly or scheduler signal are
families kept on purpose (Conquest's Reward, Legion raid copies, paragon, supplies); the 513 typed
repeatable by `QuestV2` absence (503 of them #156's set, decided with the user) are a heuristic the
cache can neither confirm nor refute: its quest type is the field the API's `is_repeatable` comes
from, and it calls the Darkmoon decks Normal. **Decisions for the user:** each class of the 173 is a
type change, to be listed by the check that is still to be built.

### Next quest

`nextQuest` is `RewardNextQuest`, the quest the client asks the NPC for after hand-in, not a
prerequisite: it equals TrinityCore's for 32,688 of 32,688 quests and is non-zero for 7,337. Of those
edges, 2,686 (36.6%) agree with our prerequisites, directly or through the prerequisites of a
prerequisite, 116 sit with a different one, 43 point at quests we don't hold, 17 are self-offers and
4,475 go to a quest with no prerequisite of ours. For the 4,475 the cache alone can't tell a gap from
a re-offer: where a second source speaks the edge agrees with it 90% (API), 96% (ours) and 98.8%
(TrinityCore), so between 9% and about 70% are real gaps.

What the edges found in our own data needs no cache: five prerequisite cycles over 38 quests (of 14,
11, 5, 4 and 4), seven edges where our prerequisite runs against both the cache and the client's
storyline (five of them inside the 14-cycle), and four places where the cache contradicts an
exclusive group or a breadcrumb.

### Races

The race list is the same server field the API serves (equal on all 28,985 shared quests but two
empty masks), so the cache is a coverage complement for step 1 and 1b and not a second vote: it
covers 3,587 of the 4,955 quests the API has no record of, has nothing for class, and misses 1,083
quests the API has. Ours allows a race as the addon does: the mask has its bit and the faction
(Alliance 1, Horde 2, neutral Pandaren 4) allows its side, a mask or faction of 0 restricts nothing,
and the 30 race IDs of ours that have a bit are compared (neutral Pandaren left out). On that
definition the cache agrees with ours exactly for 30,737 of 32,572 quests. Where it asserts a list
and ours differs: 98 quests. 70 we hide from races Blizzard allows (49 narrowings to the starting
races, a call for the user; 19 stale masks that lack the races added after Legion; and two outright
contradictions, quest 2 "Sharptalon's Claw", a Horde quest whose race mask in our data is the
Alliance's, and 27675 "Forged Documents", an Alliance quest with the Horde's mask; the cache says
Horde and Alliance). 27 we show to races it denies (13 Argent Tournament quests and the like, 47253,
and the neutral-Pandaren-only 30039, 30043 and 30044). One crosses (9329). The sweep's step 1 sees 91
of the 98 only as unactioned raw rows, because its comparison reads an API faction, or a race list
longer than eight, as silence; the other seven it never sees.

1,737 quests have a restriction of ours that no Blizzard source repeats, which is how a giver's own
race or the zone's side looks: a zone-side test agrees with ours for 381 of the 391 it can test.
Retail's restricted masks carry one placeholder race, "TBD NPC Race": 95 in the Alliance lists and 96
in the Horde lists (10,041 of 10,767; 726 carry neither; the bits Forever uses for its Skyborne); the
reader leaves them out for retail. A mask of 0 (two quests, 24712 and 82739) means no restriction.

### Sort

The cache's sort is the API's area or category (28,614 of 28,614; the 371 whose API record has neither
have a sort of 0) and TrinityCore's `QuestSortID` (99.96%), so it can't find a misfile the API-based
placement already encoded. What it adds: 98 quests filed Uncategorized whose sort names one category
(82 are API "category" headings that `Place-UncategorisedQuests.ps1` doesn't read), about 27
profession misfiles (15 Tailoring quests under Leatherworking, 12 Engineering quests under
Enchanting, whose profession bit is also wrong: 4, Enchanting's, instead of 8), a starter-zone
routing gap (the map ids 462, 460, 461 and 469 send the list to categories with no quests), and a way
to see sort drift between builds. Our category agrees with it for 96.4% of the quests that have an
expected category (28,437 of 29,484); about 560 of the 1,047 disagreements are the commonest filing of
their sort or a parent or child of it, which is our deliberate regrouping.

### Coverage and titles

The cache holds 32,572 of our 35,023 quests; 141 are only in the cache (106 task quests and 35 others:
invasion points, meta and tracking quests, test quests, a handful of real gaps), and the 2,451 only in
ours all failed to load in the probe of 29 September, so the cache, which holds only what was asked
for, can neither keep nor remove them. Titles: for the 28,985 quests the API has, data, API and cache
agree on every one; the 34 that differ are quests the API has no record of, where TrinityCore agrees
with the cache for 32 (our names are stale), and four carry a `[DEPRECATED]` prefix in the cache that
ours strips.

## Corrections to earlier notes

- "Start item" in recommendation 13 and the field table of [game-api-review.md](game-api-review.md),
  in [game-parity.md](game-parity.md), in [client-tables-review.md](client-tables-review.md) and in
  [forever.md](forever.md) meant the item that begins a quest. The field is the item handed over on
  accept (above).
- client-tables-review.md says `ContentTuning` adds nothing because only task quests carry a
  `ContentTuningID`; the cache carries one for all 32,713 quests.
- quest-reputation-data.md says there is no per-quest reputation source: it means the API and the
  client's tables.
- game-api-review.md's gaps table is out of date; counted again on 9 October 2026: retail pins
  15,202, with an NPC ID 10,564, with neither 4,301, quests with no pin 10,361, quests whose only pins
  are nameless 3,696 counting every quest ID a pin lists as the table did (3,600 counting only ours).

## Checks to build

None of these changes data; each prints what it found and keeps a baseline. They are not built yet.
Baselines belong in a file keyed by quest, since counts move with what a probe run asked for.

| Check | Where | Fails on |
|---|---|---|
| Reputation: the cache's rewards against ours and the API's, with the classes above | a pass in `Compare-QuestReputation.ps1`, retail | a reward that differs, or one ours or the API's lists that the cache lacks (both 0 today) |
| Levels: ours against the tuning's range, coverage of tunings with no range | `Compare-QuestLevels.ps1` and the `ContentTuning` table, step 2b | a quest that was equal in the baseline and is not |
| Recurrence: daily, weekly, repeatable and scheduler against our types | an input to `Retype-ProbeRecurring.ps1` | nothing; it proposes |
| Races: the 30 race IDs of ours (26 bits) that each of ours and the cache allows | `Compare-QuestRaces.ps1`, a new step 1e | a difference without a decision row |
| Sort: our category against the sort's expected one | `Audit-QuestSort.ps1`, step 5 | a pair without an exception row |
| Next quest: cycles, clashes and the reader guard | `Audit-QuestTables.ps1` | a cycle, a clash |

## Decisions waiting

1. Retail's gate level from the tuning (Level, above): row 14 of open-items.md, the other way to row 8,
   which takes the API's minimum and leaves the 4,955 quests it has no record of without a level.
2. Backfill of the 2,043 quests' reputation from the cache, after a few checks in game.
3. The type changes of Recurrence and flags.
4. The race changes of Races: the two contradictions and the 19 stale masks recommended, the 49
   narrowings a call.
5. The Sort fixes, the 98 Uncategorized quests first.
6. Whether to keep "Starts from": only from `ItemSparse.StartQuestID` or `QUEST_DETAIL`.

## Log

- 2026-10-09: the reader (`Read-QuestCache.ps1`, formerly `Read-ForeverQuestCache.ps1`) takes retail's
  layout; `Compare-QuestCache.ps1` checks it against the API and the task table; `Test-QuestCache.ps1`
  and `Test-CompareQuestCache.ps1` test both on caches built in the tests. Eight comparisons of the
  cache with our data, each recounted by a second analyst, are the sections above.
- 2026-10-09 (later): four reviewers and a skeptic for each of their 43 findings (three refuted)
  shaped the change: the reader refuses a file without its terminator and a cache with no quests; the
  tripwire also compares recurs, faction and races, holds a content tuning to its commonest range, and
  counts the quests the API has no record of by their `.404` files; the tests gained the cases the
  reviewers named; these numbers are the recounted ones.
