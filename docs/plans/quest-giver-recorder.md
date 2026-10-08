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
| 5 | Caps: 2,500 givers, 5,000 quests, 500 quests started away from a giver; when a table is full its oldest tenth goes | a full file must not block new content such as 12.1.5 or Forever's launch zones |
| 6 | Faction, race and class are kept as a union bit mask per quest, in the quest data's own bit values | answers "was this ever offered to a Horde, orc, warrior" without making the account's character list a fingerprint |
| 7 | No world, bonus or hidden quests | the addon pins none of them and they would use the cap |
| 8 | A quest with no giver gets a position only from an item, an area trigger or an auto-accept popup, and the first place seen stays | the window a player clicks later opens wherever they are |
| 9 | The guard is read-only: the recorder never moves a pin; the tool (still to build) fills blanks and lists disagreements | the pin spacing and "pins that match client data stay" rules |

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

Measured offline for a full file (2,500 + 5,000 + 500 records, plain Lua on this PC, 32-bit): 514 KB
on disk, 0.8 MB of memory (about 1.5 MB in the game), 6 ms to load, and the login pass over the keys
costs under a millisecond. Today's account file is about 1 KB. [load-and-memory.md](load-and-memory.md)
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

## To try in game before it ships

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

## What is left

1. **The tool** (next pull request): `Read-RecordedGivers.lua` (a sandboxed reader, since a player's
   file is code) and `Import-RecordedGivers.ps1`, in the retail pin pipeline and for Forever. It fills
   NPC IDs and names where a pin has none, adds a pin only for a quest that has none, lists every
   disagreement for review, and never moves a pin or changes an ID or name that is there. Trust: the
   maintainer's own files count as one source, a player's file needs a second independent one agreeing
   within 1.5 map points. A tracked, anonymised ledger carries the facts between sweeps. The steps go
   in [maintenance.md](../maintenance.md) as step 6d for both games.
2. **The API watch:** `Read-ApiDocs.lua` keeps only some `Secret*` flags; keep them all, so step 2b
   sees a new secrecy flag on the functions the recorder uses.
3. **One probe for both games** (recommendation 2).
4. **Forever's importer** reads the ledger, and its recorded-spot merge radius moves from 3 to 1.5
   map points; the probe's own recorder (PR #139) is retired after one sweep.
5. **Later, if wanted:** a copy-text window for the report; a novelty test so the file skips what the
   shipped pins hold; recorded recurrence and headings into the type and category steps.

## Status

- 2026-10-08: design from five investigations and a cross-check; `qcRecorder.lua`, the setting,
  `/qc report` and `/qc record`, the strings in all eleven languages and `Test-Recorder.lua` built on
  `feature/quest-giver-recorder`. Not tried in game, so not in a release.
