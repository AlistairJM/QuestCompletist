# The quest giver recorder

## Goal

The user, 8 October 2026: "Let's start on the retail recorder." It is recommendation 1 of the
[API review](game-api-review.md) and of [game-parity.md](game-parity.md): the Forever probe has a
recorder that notes which quest each NPC offers and takes in, and where the player stood, and it is
the only source of pickup data for Forever's new content. Retail has no such check. The recorder now
lives in the addon, so it runs on both games, and a later tool turns what it noted into pins and
NPC IDs.

## Decisions

The user said to start; the calls below are the API review's recommendations (decision 1 and the
recorder paragraph of recommendation 1), taken as agreed until the user says otherwise.

| # | Decision | Why |
|---|---|---|
| 1 | In the main addon, on by default, with a checkbox, `/qc record on\|off\|clear` and a one-time chat notice | an opt-in recorder would note almost nobody; the notes never leave the computer |
| 2 | Nothing identifying: no character or realm name, no GUID, no time. A giver is its kind and ID, a quest is its ID | a file a player sends must be safe to read and keep |
| 3 | Names and headings only from an English client (`GetLocale() == "enUS"`); IDs, offers, hand-ins and positions from every client | a wrong NPC name is worse than none, and the tool needs the English name |
| 4 | One packed string per record, not a table per record | 514 KB on disk and 0.8 MB of memory at the caps, against three times that |
| 5 | Caps: 5,000 givers, 10,000 quests, 4,000 quests started away from a giver (2,500, 5,000 and 500 until 10 October 2026, when the user doubled the first two and raised the third eightfold); when a table is full its oldest tenth goes | a full file must not block new content such as 12.1.5 or Forever's launch zones |
| 6 | Faction, race and class are kept as a union bit mask per quest, in the quest data's own bit values | answers "was this ever offered to a Horde, orc, warrior" without making the account's character list a fingerprint |
| 7 | No world, bonus or hidden quests | the addon pins none of them and they would use the cap |
| 8 | A quest with no giver gets a position only from an item, an area trigger or an auto-accept popup, and the first place seen stays | the window a player clicks later opens wherever they are |
| 9 | The guard is read-only: the recorder never moves a pin; the tool (`Import-RecordedGivers.ps1`) fills blanks and lists disagreements | the pin spacing and "pins that match client data stay" rules |

The old note in [localized-npc-names.md](localized-npc-names.md) ("Dropped, 3 October 2026": a
`/qc report`) said an addon can't send data. That is still so: `/qc report` prints what is held and
where the file is, and the player attaches the file to a comment if they wish. The recorder returns
for that reason, and for the Forever probe's.

## What is saved

`qcQuestRecorder`, an account-wide saved variable in both TOCs. It is written when the player logs
out or reloads, to `WTF\Account\<account>\SavedVariables\QuestCompletist.lua` of each game's folder.
Retail and Forever never share a file. Nothing is created or read at file load, only at
`ADDON_LOADED`, when the table is checked: a record of the wrong shape is dropped, a schema newer
than the code is left alone.

| Key | Holds |
|---|---|
| `v`, `seq`, `ev` | schema number; the last sequence number (it orders eviction, and replaces times); how many records have been evicted |
| `bv` | build number → version string, at most 8 |
| `err` | `n`, the number of failures; `last`, the last message (200 characters) |
| `d` | counters with a fixed vocabulary (below) |
| `noticed` | the first-run notice was shown |
| `g["Creature:3701"]` | `name\|build\|seq\|spots\|offers\|turnins\|flags` |
| `q[questId]` | `build\|seq\|flags\|faction\|race\|class\|heading` |
| `s[questId]` | `kind\|item\|map\|x\|y\|build\|seq` |

- **Kinds:** `Creature`, `GameObject`, `Vehicle`. The ID is field 6 of the GUID. A `Player`, `Pet` or
  `Item` GUID makes the event record nothing.
- **Spots** are `map x y visits` joined by `;`: the *player's* place on the map in percent, to a
  tenth, which was within 0.04 to 0.14 map points of the NPC for the eight Forever NPCs measured.
  `-1 -1` is no position (an instance, or a hidden value). A new place within 1.0 point of one held
  adds a visit to it; further away it is a new spot, up to four. A visit counts when the giver
  changes or 30 seconds have passed.
- **Offers and turn-ins** are quest IDs joined by `,`, up to 60 each. A quest can be in both.
- **Quest flags:** 1 the frequency is known; 2 and 4 the frequency (0 default, 1 daily, 2 weekly,
  3 scheduled); 8 repeatable; 16 accepted by a character; 32 offered by a giver; 64 whether it is
  repeatable is known. The two "known" bits are apart because a single-quest NPC's window says
  nothing of repeatability, and the accept gives only the frequency.
- **Giver flags:** 1 a different English name was seen (the first stands); 2 the offers list is full;
  4 the turn-ins list is full.
- **Start kinds:** 1 an item, 2 an area trigger or auto-accept popup.
- **Counters (`d`):** `ev:<event>` handler runs; `rd:<event>:<token>:<state>:<where>` how the giver was
  read (`ok`, `hid` hidden by the game, `oth` not a creature or object, `none`; `w` open world, `i`
  instance, `c` combat); `pos:ok|nil|nomap`; `name:ok|hid|bad|loc`; `head:ok|none|loc`;
  `skip:task|hidden|adv|noid`; `bit:unk`; `near:true|false`; `hook:none`; `api:greeting`. They answer,
  from real play, the questions that can't be settled offline.

Measured offline for a full file at the first caps (2,500 + 5,000 + 500 records, plain Lua on this PC,
32-bit): 514 KB on disk, 0.8 MB of memory (about 1.5 MB in the game), 6 ms to load. At the caps of 10
October 2026 (5,000 + 10,000 + 4,000 records, 19,000 in all), measured again with one synthetic file
for both sizes (555 KB then, 1,249 KB now): 2.25 times the size and memory, about 3.5 times the load,
so about 1.2 MB on disk, 3.3 MB of memory in plain Lua and 15 ms to load, still under a fifth of the
addon's 17.8 MB. Making room scans a table once, 7 ms at 10,000 records, and happens once for every
thousand new quests. The login pass over the keys costs about a millisecond. Today's account file is about 1 KB. [load-and-memory.md](load-and-memory.md)
has the addon's own numbers.

## Events

One frame, six events registered only while recording is on (turning it off costs nothing), no
`OnUpdate`, no timers. Every handler runs under `pcall`; three failures stop the recorder for the
session, and the player is told once. The addon's own event handler is untouched.

| Event | Reads | Records |
|---|---|---|
| `GOSSIP_SHOW` | `C_GossipInfo.GetAvailableQuests` and `GetActiveQuests`; the giver from `npc`, then `questnpc` | the giver with the offered and taken-in quests; nothing for a vendor or flight master with no quests |
| `QUEST_GREETING` | the giver from `questnpc`, then `npc` (Blizzard's quest frame uses `questnpc`); `GetNumAvailableQuests`/`GetAvailableQuestInfo` (frequency, repeatable, ID) and `GetNumActiveQuests`/`GetActiveQuestID`, which Blizzard's own quest frame calls but the API lists don't document | the same; a missing function is counted |
| `QUEST_DETAIL` | `GetQuestID`, the giver from `questnpc`, then `npc`; the item ID in the payload | an offer; with no giver, an item or auto-accept area trigger start |
| `QUEST_PROGRESS`, `QUEST_COMPLETE` | the same | a turn-in; with no NPC (auto-complete) nothing |
| `QUEST_ACCEPTED` | the quest's log entry and the heading above it | the quest's heading, frequency and that it was accepted; no giver, no position |
| `AddAutoQuestPopUp` (a post-hook on the objective tracker) | quest ID, `"OFFER"`, item ID | a start, first place wins |

Why the hook: Blizzard's own `QUEST_DETAIL` handler calls `CloseQuest()` right after adding the
popup, before ours runs, so `GetQuestID()` may be 0 there. The hook gets the quest ID and the item.

Each handler reads the giver itself and adds to a set, so the order in which a hand-in, a follow-up
offer and the accept arrive doesn't matter.

### What the game's secrecy rules do

In 12.x the game can hide a unit's identity, and a position. The recorder never touches a value
before `issecretvalue` has been asked, reads the GUID (not `UnitCreatureID`, which returns nothing
when restricted and so can't tell hidden from absent), and counts every outcome. A giver the game
hides still leaves the quest's facts, never a giver, and never a start.

## Privacy

- Stored: NPC and object IDs and English names; quest IDs; map IDs and percentages; the faction, race
  and class bits; build numbers and version strings.
- Never read: the character's name or GUID, the realm, time, guild, chat. `Test-Recorder.lua` greps
  the source for `UnitName("player"`, `GetRealmName`, `time(`, `SendAddonMessage`, `C_Timer` and the
  like, and walks the saved table for a planted character name.
- `qcFlaggedButSeen`, which already shares the file, stores `time()`; that is older and unchanged.
- The notice, the checkbox's tooltip and `/qc report` say that nothing is sent. The wording names no
  data source. The README says the same in two sentences.

## Tests

`tools\Test-Recorder.lua` (Lua 5.1, from the repository root) drives real event sequences against
stand-ins for the API and checks the table the game would save: 341 checks across set-up, the setting,
single-quest, gossip, greeting and hand-in givers, objects and vehicles, item and area-trigger starts,
quests that arrive with no window, positions, English and German clients, the union masks, the caps and
the exact eviction, the privacy scan, a save and reload round trip, damaged and newer tables, handler
failures, which token each event reads first, the `/qc` command as written in `qcCore.lua`, and the
report in all eleven languages.

Hidden values are stand-ins that keep their type and raise on arithmetic, comparison, concatenation,
indexing and length, as the game's do. Every `secret()` and `isSet()` guard in the recorder was removed in
turn: each removal makes a check fail, except the one inside `isSet` itself (equivalent here). Lua 5.1
can't trap `==`, `~=` or a hidden value used as a table key, so the order of the GUID guard is read from
the source. Other mutations (the caps, the 60-entry lists, the spot merge, the first-writer rule, the
name rules, the task filter, the mask union, the English gate, the token order) each fail too. It runs in
checking a change ([maintenance.md](../maintenance.md)).

An independent review of the first version found the one that mattered: the GUID was compared with `nil`
before it was asked whether it was hidden, which the game does not allow. Fixed, with the other
findings (the recurrence bit, the checkbox not restarting a stopped recorder, the greeting's token order,
build pruning).

Also unchanged: `Test-Localization.lua` ("No problems"), `Test-QuestReachability.lua` for both TOCs
(retail 1 / 0 / 99 / 2 as on master, Forever 0, no Lua errors).

## To try in game (it shipped in 112.7 without this)

The stand-ins say what the code does, not what the game answers. One session on a branch, loaded
through the junctions; **fully close and restart WoW** (a new file and saved variable), and back up
`QuestCompletist.lua` first because the game drops a variable the TOC doesn't name when it saves.
Blizzard's `/etrace`, filtered to `QUEST_`, `GOSSIP_` and `ADDON_RESTRICTION_STATE_CHANGED`, shows the
real order and payloads; `/qc report` and the `d` counters in the saved file show what the recorder saw.

- A single-quest NPC, a gossip NPC with several quests, a greeting NPC, a hand-in with a chain
  follow-up, a daily the NPC both offers and takes in, a notice board.
- An item-started quest and an area-trigger quest: does our `QUEST_DETAIL` see `GetQuestID()` as 0, and
  does the hook fire? Then click the tracker popup from elsewhere.
- A party-shared quest, a world quest (must be skipped), the splash-screen quest if reachable.
- Inside a dungeon and a delve, and in combat, mounted and on a taxi: do the `hid` counters ever
  count, and does the position come back nil?
- Are `npc` and `questnpc` both valid, at each event? (`npc` is proven on Forever only.)
- A collapsed quest log header: is the heading found?
- A German client, if one is to hand: names and headings empty.
- `/reload`, then read the saved file; toggle; clear; the options panel's layout in the longest
  language; memory in the game.

Record the answers here.

## The merge tool

`Import-RecordedGivers.ps1` is step 6d of the sweep ([maintenance.md](../maintenance.md)); the rules
are in `RecordedGivers.ps1`, the reader in `Read-RecordedGivers.lua`. The calls it takes are these,
and the first group are the user's standing rules, applied. An independent review of 9 October 2026
(five lenses, 72 findings that survived a skeptic) shaped much of it; what it changed is said in place.

**Reading a file.** A saved-variables file is Lua code, and a player may have sent it, so the reader
never runs it as it stands: it reads the text (a bare CR ends a comment, as it does in Lua 5.1) and
refuses anything that is not assignments of tables, strings, numbers and `true`, `false` or `nil`
to names (no call, operator, function, long string or comment, or name used as a value), a file over
8 MB (checked before it is read), tables nested over 24 deep, and a file with more records than the
addon can keep (5,000 givers, 10,000 quests, 4,000 starts, which also admits the smaller files of the
addon's first version; a giver with more than four spots or sixty
offers is an odd record). What passes is loaded with no globals and an instruction budget, and the
tool gives the reader two minutes. A refused or unreadable file is named in the report and the run
goes on. Names and headings are kept only if they are 64 bytes or fewer, have no `|` or control
character, and do not begin with `=`, `+`, `@` or `-` (a spreadsheet takes those for a formula);
positions are rounded to four places so nothing prints as `1e-005` or `-0`; a build must be under a
billion. `Test-RecordedGivers.lua` plays hostile files against it (`os.execute`, a loop, a memory bomb
through a string method, precompiled code, a file over 8 MB, deep nesting, code after a CR), and a
differential fuzz of the checker against Lua 5.1's own parser found no other way through.

**What counts.** A file counts for the game its builds say, whatever folder it is in, and only for
the versions the TOCs name (`12.1.`, `1.60.`). Fewer than a fifth of its records may be odd (and at
least three). A map the game's table lacks, a build that is not read and a quest the data lacks are left
out and counted, the maps by number; the unknown quests go to `tools\recorded_unknown_quests.csv`.

**Trust.** The maintainer's own files (`own-retail`, `own-forever`, and every probe folder) are one
source, however many: they describe the same visits. A fact is acted on when "own" saw it, or two
different players did. **A lone player's file decides nothing:** not a name, not where a place is, not
which place is main, not how often a giver was seen (the maintainer's own sightings seed and weigh the
places; a lone player's row may only join one). Names are compared exactly, case included, and a giver
whose trusted rows give two names has none, listed, because a wrong name is worse than none. A player's
tag is a label, `p01`, never a name; the tag is the folder's name in lower case, so renaming a folder is a
new player. **The weakest link:** two files are two players, whatever they hold. One person with two
accounts, or a copy of one file under two tags, is trusted; so is a pair of invented files. That is why
players' files are opened only after one sweep on the maintainer's own has run clean, why the report says
where every fact came from, and why `-ForgetTag p07` exists: it takes a source out of the ledger and
skips its file for that run. Delete the file too, or the next run reads it again; a pin that source helped
to fill keeps its ID (the tool never changes one), so undo that in `pins.jsonl` before the change is merged,
or with an `ID` row in `pin-npc-id-decisions.csv`.

**The ledger** (`plans\recorded-quest-givers.csv`, tracked, no names of people): a row per giver
(with the English name it bore), per place it was seen, per quest it offered or took in, per quest
that began away from a giver, each with `Src`, `tag=n;tag=n`. It only grows. It is why the facts
survive the addon's cap, a file a player clears, and a lost file. Rows are compared exactly, written in
a total order (so a rerun is byte for byte), and a repeated row after a merge of two copies keeps the
sources of both.

**Fills.** A pin with no NPC ID gets the ID (and the name, together: the addon reads a pin with an ID
and no name as a quest the player gives themselves) of the one trusted creature that offered one of the
pin's quests and stood within 1.5 map points of it. The offer decides, never the nearest giver: a quarter
of all pins have another within 1.5 points. When the pin has a name it must be the giver's, compared as
Blizzard writes it. Two givers of one name (phased copies) are one character: the one that offers most
of the pin's quests is taken. Left and listed: two givers of different names, a vehicle, a giver with no
trusted English name or whose sources disagree on it, a pin whose ID `pin-npc-id-decisions.csv` took off by
hand, a case `pin-giver-decisions.csv` or `recorded-giver-decisions.csv` keeps (a KEEP on any quest of the
pin keeps the pin), a giver that stood 1.5 to 3 points away, a giver recorded where the game gave no
position, and a quest the giver both offered and took in when it stood somewhere else as well (the recorder
keeps what a giver offered and took in, and where it stood, but not which place went with which: see below).
**A fill that would put two pins of one NPC, or of one object name, 1.5 points or less apart but not on
one spot, is not made:** the pipeline would merge them at its next run and move one pin's quests. Blank
pins stacked on one spot are filled together, which the pipeline then makes one pin without moving anything.

**Where the game gave no position** (an instance): the recorder stores `-1 -1`, and the tool lists the
case instead of filling it. A quest that has one pin on a map and a giver recorded on it is not proof that
the pin is the giver's place, and "dungeon" maps are mostly open-world cities, so the instance test needs
`Map.InstanceType`, which the tool does not have. A later step.

**Adds.** A quest with no pin gets one at the place a trusted giver of it was most seen (a player's place,
0.04 to 0.14 points from the NPC where measured), or joins the pin that giver already has within 1.5
points, or a pin of its name that has no NPC; up to six givers, and a fuller list goes to the review.
Copies of one character get one pin. A giver with no trusted English name gets a pin with no NPC and no
name (nameless is fine), which a later run fills once two sources give a name. The pin is placed in the
pipeline's order (map, then lowest quest, x, y, NPC), with the profession icon, 3, only when every quest on
it has a profession, and 1 otherwise, as `Apply-ClientQuestGivers.ps1` does. A quest the user keeps from
getting a pin (a `KEEP` row with only a quest, or with the place) gets none, and the report counts it.
What may get a pin follows the user's rule (a normal quest, never a world quest) and what the scouts of
9 October measured: held back are a quest not in the data, one flagged unavailable, an internal name, a
task whose `QuestInfo` kind is world, bonus, hidden, delve or the like (3,380 quests, none with a creature
starter in TrinityCore) and a system category (Garrison Support, Torghast, Prey and so on; the list
`Import-RecordedGivers.ps1` holds is empty of allowed ones until a person decides one). **Waived because a
creature offering the quest answers them:** not in `QuestV2` (it omits repeatables), the inferences from
TrinityCore's templates, a task of another kind, Landfall, holiday and profession quests, and a quest type
other than 0, 1, 2, 4 and 128. The report counts the quests by class, and
[open-items.md](open-items.md) lists the waiver as a call the user may reverse.

**Review.** `pin names another NPC than the recorded giver`, `same name under another ID`, `pin name
differs from the name recorded for its ID`, `quest offered away from its pins` (a giver none of whose places
is near any pin of the quest), `pin at the hand-in`, `offered but flagged unavailable`, the givers whose
trusted names disagree, masks the notes contradict, and what the fills and adds left alone. Beside the
report, each with a `Game` column (Forever's too), the sources and whether they are enough to act on:
`recorded_unknown_quests.csv`, `recorded_quest_types.csv` (a recorded recurrence that is not the quest's
type, or that disagrees), `recorded_headings.csv`, `recorded_start_items.csv` and
`recorded_mask_contradictions.csv`. They are lists to look through: nothing reads them yet (the gap-quest
fetch takes its IDs from `gap_quest_ids.txt`, which nothing writes).

**Checked.** `Test-RecordedGivers.ps1` makes small data in a scratch folder (quests, pins, the Lua built
from them, recordings of every kind) and checks the rules and the tool end to end, including that a second
run leaves `pins.jsonl`, the Lua and the ledger byte for byte, that nothing moves, and (with a deliberately
broken copy of the tool) that a change that would move a pin saves none. On a scratch copy of the real data,
25 pins blanked and 8 removed were given back exactly (the ID and name of the 25, the NPC, name and place
within 0.2 points of the 8), a second run changed nothing, and the real pin pipeline
(`Parse-ExistingPinDB.ps1`, `Assemble-PinDB.ps1`) run on the result reproduced it line for line.

**Known limits.** (1) The recorder keeps what a giver offered and took in, and where the player stood, but
not which place went with which quest; the tool is careful where it matters (the hand-in hold, the review),
but storing the place's index with each offer in the recorder would be better, and cheap while the format is
unreleased. (2) The map the game reports for the player (`GetBestMapForUnit`, the most specific one) may not
be the map the pin is on: the scouts found a quarter of zone pins on a larger sibling map (Orgrimmar and
Durotar), where an exact match misses, so the yield of fills may be three quarters of what a perfect match
gives. Those cases show up as `quest offered away from its pins`. Converting through the client's map
frames (`UiMapAssignment`) would recover them; it is not built. (3) The 1.5 point radius is a ceiling, tight
on small maps. (4) Two accounts of one person count as two players (see Trust).

## What is left

1. **The in-game session** above. The recorder was released first, in 112.7, on the user's word.
2. **The first real ingest** of the maintainer's own retail and Forever files: run step 6d `-WhatIf`,
   read the report, write `KEEP` rows, run it, then `Remove-DuplicatePinQuests.ps1 -WhatIf` and the pin
   pipeline. Open the call for players' files after one sweep has run clean.
3. **One probe for both games** (recommendation 2).
4. **Forever's importer** reads the ledger, and its recorded-spot merge radius moves from 3 to 1.5
   map points; the probe's own recorder (PR #139) is retired after one sweep.
5. **Later, if wanted:** a copy-text window for the report; a novelty test so the file skips what the
   shipped pins hold; the map-frame conversion above; the instance rule; recorded recurrence and
   headings applied by steps 3 and the category steps rather than listed.

## Status

- 2026-10-08: design from five investigations and a cross-check; `qcRecorder.lua`, the setting,
  `/qc report` and `/qc record`, the strings in all eleven languages and `Test-Recorder.lua` built on
  `feature/quest-giver-recorder` (#228). Not tried in game, so not in a release.
- 2026-10-09: the merge tool built (`tools/recorded-givers`): `Read-RecordedGivers.lua`,
  `RecordedGivers.ps1`, `Import-RecordedGivers.ps1`, the ledger and the decisions file, step 6d in
  the runbook. Facts from four read-only scouts (pins, which quests may be pinned, house style, maps)
  shaped it. Tried on a scratch copy of the real data; no real recording exists yet.
- 2026-10-09 (later): the review's findings fixed: a bare CR hid code from the checker (it now ends a
  comment, and the reader has an instruction budget and the tool a time limit), builds and positions that
  printed in forms PowerShell could not read, no caps, names with a leading `=`; a lone player's file no
  longer decides a name, a place or a count; trusted names that disagree leave a giver without one; fills
  that would merge two pins, KEEP on any quest of a pin, a pin with no NPC and no name made for an unnamed
  giver, the icon, the near-miss and hand-in cases, Forever's lists, a total order for the ledger. The
  tests went from 253 and 125 checks to 367 and 267.
- 2026-10-09: the API watch (`tools/api-secrecy-flags`): `Read-ApiDocs.lua` keeps every secrecy flag and
  `Compare-ApiDocs.ps1` compares them, for the functions the addon calls and the events it listens for
  (all six of the recorder's are documented in both games; its quest-window globals are in no
  documentation, so the events are what the watch can see of it). Two independent reviews (a mutation
  sweep of the tests among them) shaped it, the second round fixing a function's own namespace, a
  half-installed download and a stray list file; `Test-ApiDocs.ps1` has 231 checks. Step 2b of the runbook.
- 2026-10-09 (later): merged (#228) and released in 112.7 without the in-game session, on the user's
  word ("assume it works"). It is on by default; the README and the changelog say what it keeps and
  that nothing is sent. The in-game session now checks what players already have. The in-game
  `/qc report` text still invites players to attach their file to a comment; the README and the
  changelog do not, because the call for players' files waits for one clean sweep (see "What is left").