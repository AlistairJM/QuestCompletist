# Quest names in the player's language

## Goal

Show quest names in the client's text language wherever the addon shows a quest name. Today they
all come from the English names in `qcQuestDatabase` (field 2), so a German client shows German
category names (since the client-name work) but English quest names.

## What's there today

| Where | Code | Name used |
|---|---|---|
| List rows | qcCore.lua:704 | `e[2]` |
| Quest tooltip, heading | qcCore.lua:1278 | `SetHyperlink("quest:id")` once the quest's data has loaded (already the client's language), otherwise `e[2]` (qcCore.lua:1280) |
| Quest tooltip, storyline lines | qcCore.lua:1333 | `e[2]` |
| Quest tooltip, prerequisite | qcCore.lua:1347 | `e[2]` |
| Map pin tooltips | `qcColouredQuestName`, qcCore.lua:1776 | `e[2]` |
| TomTom waypoint title | qcCore.lua:1527 | NPC name, else `e[2]` |
| Breadcrumb toast tooltip | `qcGetToastQuestInformation`, qcCore.lua:1698 | `e[2]` |
| Mutually exclusive alert | `qcMutuallyExclusiveQuestInformation`, qcCore.lua:1734 | `e[2]` |
| Search | `qcQuestNameUpperCache`, qcCore.lua:424 | upper-cased `e[2]` |
| Sorting | qcCore.lua:549, 554 | `e[2]` (tie-break under level sort; the key under A–Z sort) |

The tooltip already requests quest data (`C_QuestLog.RequestLoadQuestByID`) and redraws on
`QUEST_DATA_LOAD_RESULT`, with `qcQuestDataRequested` / `qcQuestDataLoaded` stopping repeat requests.

## What the game offers (checked against Gethe/wow-ui-source `live`, 2026-09-30)

- `C_QuestLog.GetTitleForQuestID(questID)` returns the title in the client's language, or nil when the
  client doesn't have the quest's data.
- Blizzard's own helper, `QuestUtils_GetQuestName`, tries `C_TaskQuest.GetQuestInfoByQuestID` first
  (world quests and other task quests), then `GetTitleForQuestID`. We do the same.
- `C_QuestLog.RequestLoadQuestByID` asks the server for the data, and `QUEST_DATA_LOAD_RESULT` reports
  the answer.
- **Known limit, from the quest-type probe (full-sweep runbook):** the server stops answering bursts
  of load requests. The probe settled on **4 requests in flight**. Some requests may never be answered,
  so a request needs a timeout, or one lost answer blocks the queue.

Still unknown, measured in phase 1: how many titles the client already has at login (the quest cache
on disk may keep them between sessions), how long a request takes, and whether `GetTitleForQuestID`
answers for quests the character has never seen.

## Phases (one PR each)

### Phase 1: measure on the English client (probe branch, not merged)

A temporary `/qc titlecheck <category>` on a scratch branch, like the quest-type probe in #42.
For each quest in a category it records:
- whether a title is available straight away, before any request;
- the request result (success, failure, or no answer within 5 s) and the time it took, with 4 in flight;
- the title the game gives, compared with our English name.

Run it on a small zone (Northshire/Elwynn), a big one (Durotar), a world-quest-heavy one (a Dragon
Isles or Khaz Algar zone), then `/reload` and run the first again to see whether titles survive a
reload.

It answers three things:
1. **Is a request queue needed at all?** If most titles are there at login, the rest is cosmetic.
2. **The queue settings:** whether 4 in flight and a 5 s timeout hold up.
3. **Name mismatches.** Where Blizzard's English title differs from ours (typos, renamed quests),
   this becomes a report. Fixing the names in `qcQuestDatabase` is a separate data decision, not
   part of this work.

### Phase 2: use the client's name everywhere

1. **`qcQuestName(questId)`:** `C_TaskQuest.GetQuestInfoByQuestID(questId) or
   C_QuestLog.GetTitleForQuestID(questId)`. If neither answers, it queues a load request and falls
   back to `e[2]`; nil for a quest that's in neither the game nor the database.
2. **Load queue:** `qcRequestQuestData(questId)`, shared with the existing tooltip request:
   - at most 4 in flight, first in first out;
   - each request is freed after `QUEST_DATA_LOAD_RESULT` or after the timeout;
   - a quest is never requested twice in a session (the existing `qcQuestDataRequested` / `qcQuestDataLoaded`);
   - when an answer lands for a quest that's on screen, it asks for a row redraw through
     `qcRequestRefresh(QC_REDRAW_ROWS)` (from #96), so a burst of answers redraws once per frame.
3. **Use `qcQuestName` at every site in the table above** except search and sorting (see below).
   The tooltip keeps `SetHyperlink` once data has loaded. Its fallback line, storyline lines and
   prerequisite switch to `qcQuestName`.
4. **What gets requested:** the list's 16 visible rows on each redraw, and the quests in a tooltip
   (quest, storyline, prerequisite, pin quests) when it opens. Nothing is requested in the
   background; scrolling and hovering fetch what the player looks at.
5. **Test harness:** `Test-QuestReachability.lua`'s `C_QuestLog` stand-in returns its dummy table for
   unknown functions. It must return nil for `GetTitleForQuestID`, and `C_TaskQuest` must be stubbed,
   or a stand-in table ends up used as a name. The list and tooltips aren't driven by the harness
   today, so this is a guard for later.

On an English client the only visible change is where Blizzard's title differs from ours, which is
the phase 1 report.

### Phase 3: check on a German client (no code unless something turns up)

Switch the text language to `deDE` (Game Menu → System → Languages, or `SET textLocale "deDE"` in
`WTF\Config.wtf` with the game closed), which downloads the language data and needs a restart. Then:
- open the list in a zone and check the rows fill in German, including after scrolling;
- check the quest tooltip, storyline and prerequisite lines, a map pin tooltip, and a TomTom waypoint;
- search for part of a German name, and for an English one (see below);
- switch back to `enUS`.

## Decisions (agreed 2026-09-30)

1. **Search.** The list can only search titles the client has loaded, and loading all ~35k quests to
   make them searchable would take hours at 4 in flight.
   **Recommendation:** match the English name, **or** the client's title when it's already cached. A
   German player finds quests they've seen by German name and everything by English name. Lua's
   `string.upper` only folds A–Z, so non-ASCII letters (ä, é, Cyrillic, CJK) match case-sensitively.
2. **Sorting.**
   **Recommendation:** sort by the name shown **when the list is built** (client title if cached,
   else English), and don't re-sort as titles arrive, so rows never jump while you read. The next
   rebuild (category change, turn-in, filter change) sorts again with whatever has loaded. Under the
   default level sort, the name is only a tie-break, so this mostly shows under A–Z sort.

## Out of scope (for later)

- **NPC names in pin tooltips** (`pinData[3]`) are English too. The client can name a creature through a
  tooltip hyperlink once it has seen it; that's a separate, smaller change.
- **The addon's own text:** "Search Results", "%d Quests Found", "x/y Complete", "Quest details not
  available from the game", "You are on this quest" and others are hard-coded English in
  `qcCore.lua`, not in the `Localization.*.lua` files. Moving them is easy; translating them needs
  translators.
- **Fixing `qcQuestDatabase` names** from the phase 1 mismatch report.

## Status

- 2026-09-30: plan written, decisions agreed. Phase 1 probe on `tools/quest-title-probe`.
