# Checking the quest tables kept by hand

## Goal

Every sweep should check everything, in both games (the user, 6 October 2026: "Ideally I want
everything checked every time"). Retail's sweep checked faction, race, class, names, reputation,
types, storylines, zones, pins, availability and dungeons, but nothing checked these:
- **in `qcQuest.lua`:**
  - the breadcrumbs (`qcBreadcrumbQuests`);
  - the quests that close others once they're done (`qcMutuallyExclusive`);
  - the renown requirements (`qcRenownLevelRequirements`);
  - the daily and weekly limits;
  - the faction names (`qcFactions`);
- **in `data\quests.jsonl`:** the prerequisites.

`tools\Audit-QuestTables.ps1` is a new step of the sweep, step 2b in
[maintenance.md](../maintenance.md#2b-the-tables-kept-by-hand), that checks them all. Step 2 now
also corrects reputation amounts that differ from the API's, not just missing rewards.

## Sources, and how far to trust them

Blizzard publishes no breadcrumbs or renown requirements: the API and the client's tables have
neither. Quest 82781 needs renown 3 with the Council of Dornogal, yet the API gives only its level
range. So the check takes what each source offers:
- **Our own data.** Every quest a table names should exist, be available, and in a breadcrumb or
  "only one of these" pair, not recur.
- **Blizzard's API** names required quests for 903 of our quests, and for 78 the quests that close
  them (a requirement that they're not done).
  - It never names more than 3 required quests: 831 of the 903 name exactly 3. So its lists look cut
    short, and a prerequisite of ours it doesn't name may still be right.
  - Our prerequisites agree with it for 122 of the 151 quests both give one for.
- **TrinityCore's database** (TDB 1210.26091, September 2026) has 15,200 quest rows. For quests after
  Mists of Pandaria it has few.
  - Its previous quests agree with the API for 46 of the 57 quests both speak for: about the same
    as ours.
  - Of the 4,102 previous quests it gives where we have none, 2,792 come earlier in the quest's own
    Blizzard storyline, and 2,036 are the step just before.

## First run (6 October 2026)

5,341 findings, most of them additions on offer. In three groups:

### Mistakes

- **Prerequisites that are reputation amounts:** quest 29037 "requires" quest 1500, 25432 requires
  150, 38044 requires 500, and 29362, 31936, 31937 and 31938 require 250. They look like values
  that slipped into the prerequisite field in the old data layout.
- **Prerequisites that don't exist:** 10 quests (60346 to 60357) require 60345, and 92331 requires
  91205; the API knows neither. 62727, 90573 and 91798 require quests not in our data.
- **Quests listed twice**, where Lua keeps only the last line:
  - 8 are the same line twice: the breadcrumbs of 25129, 27713, 27762 and 27774, the
    25479/25481/28503 group, and 82400's renown requirement;
  - 6 drop a breadcrumb, often the other faction's: 6610, 26065, 57919, and the three Chamber of
    Heart quests (55519, 55732, 56401) each lose one.
- **Quests not in our data:** 12 breadcrumb pairs and 12 "only one of these" pairs name one. The
  quest window counts such a breadcrumb as available.
- **Faction names** that differ from the client's:
  - Orgri'la is Ogri'la;
  - Explorer's League is Explorers' League;
  - The Cartels of the Undermine is The Cartels of Undermine;
  - the two Brawl factions carry "(Season 4)".
  
  Four "(Renown)" entries (2545 to 2548) name factions the client doesn't have.
- **Limits:** "I Got Nothin' Left!" (6609), a fishing quest, is in the fishing dailies' limit but
  isn't a daily. "Sparks of War: K'aresh" (90781) is in a weekly limit but typed one-time.

### To review

- **The other faction:**
  - The Alliance's two "Hero's Call: Southern Barrens!" quests (28550, 28551) are listed as
    breadcrumbs for the Horde quest "Clear the High Road" (24504).
  - The Horde quest "Sharptalon's Claw" (2) requires "Riverpaw Gnoll Bounty" (11), an Alliance
    quest. TrinityCore says 6383.
- **Recurring quests in breadcrumbs:**
  - "Coastal Gloom" (43738, type 128) is a breadcrumb's target.
  - The daily "Alpaca It Up" (58879) is listed as the breadcrumb for "Alpaca It In" (58887). A daily
    is never ticked, so the quest window always says a breadcrumb is available there.
- **Renown requirements** on The Weaver (2601) and The General (2605), which have no renown in the
  client's tables, so the tooltip can't show these 3 quests' requirement.
- **29 prerequisites the API doesn't name.** That's weak evidence, since its lists stop at 3.
- **TrinityCore disagrees** on 44 breadcrumbs, 31 "only one of these" pairs and 15 prerequisites.

### Additions on offer

- **30 pairs from Blizzard's API** where doing one quest closes another, which our tables lack.
  Examples: "Fate of the Stormstouts" closes once "Chen and Li Li" is done, and the Blade's Edge ogre
  quests close once the gronn quests are.
- **752 prerequisites the API names where we have none.** Each names 2 or 3 quests, and our data
  holds one prerequisite per quest.
- **4,102 prerequisites TrinityCore has where we have none**, 2,792 of them earlier in the quest's
  own storyline.
- **35 TrinityCore breadcrumbs and 223 TrinityCore groups** we lack.

## Decisions

The user, 2026-10-06, taking each recommendation:
1. **Fix the mistakes**, all of them.
2. **Add Blizzard's 30 pairs**, as breadcrumbs of the quest that closes the others: the quest window
   then warns before closing them, and ticks them once it's done.
3. **TrinityCore's prerequisites:** take only the 2,036 that are the step just before the quest in
   Blizzard's own storyline, where both sources agree.
4. **Let a quest hold several prerequisites**, show them all in the tooltip and check them all on the
   map, then take Blizzard's lists.

## Fixes (6 October 2026)

Decisions 1 and 2:
- **18 prerequisites removed:** the 7 reputation amounts, and 11 naming quests the API doesn't know.
  The 3 naming quests outside our data that the API hasn't been asked about stay, for review.
- **14 repeated lines merged.** The 6 lost breadcrumbs are back.
- **24 pairs naming quests not in our data removed.**
- **30 API pairs added**, as 20 lines in `qcBreadcrumbQuests`. One went into an existing line, 29907's.
- **5 faction names** now match the client's.

The check then found 5,246 things, 95 fewer. One finding is new: TrinityCore doesn't list the
restored Horde breadcrumb "The Wavespeaker" (26057) for "Free Wil'hai" (26065), though it may only be
missing there.

Two refinements to the check came out of this:
- **"One of these" requirements.** A quest the API requires as one of several alternatives no longer
  counts as contradicting a pair. Quest 10995 requires one of three intro quests that close once
  it's done.
- **The API outranks TrinityCore.** TrinityCore no longer disagrees with a pair Blizzard's API
  asserts.

The quest window's breadcrumb notice counts every listed breadcrumb not yet done, the other
faction's too. Some of the API pairs list both factions' versions of a quest, as 6610's breadcrumbs
already did.

## Several prerequisites (6 October 2026)

Decisions 3 and 4:
- **The data:** a quest's `prereq` can be a list that all must be done. A list inside it is a
  choice, any one of which will do, and a list inside a choice is all of it again. A single quest
  stays a number. The Lua table follows suit.
- **The code:** `qcPrereq` in `qcCore.lua` checks and describes them.
  - The quest tooltip lists each required quest on a line of its own, with its icon, and a choice
    on one line: "Step 4 or Step 5 or Step 6", in the player's language (`SERVICES_CONJUNCTION_OR`).
  - The map greys a pin, and with its filter on hides a quest, until every requirement is met.
    Its tooltip names what's missing: "Requires Step 3", or "Requires Step 4 or Step 5 or Step 6".
- **A fix found on the way:** the map's renown check stopped with an error if the game gave no
  renown level for the faction. It now counts that as met, as the pin tooltip already did.
- **`tools/Sync-QuestPrerequisites.ps1`**, step 2c of the sweep, sets them. A second run changes
  nothing.
  - **Blizzard's lists:** 752 quests got the API's list, and 154 had theirs corrected.
  - **Ours kept as well, 28 times:** the API names at most 3 quests and often leaves out the step
    just before the quest in its storyline. Of the 29 prerequisites of ours it didn't name, 28 were
    that step, so they stay alongside Blizzard's list.
  - **TrinityCore's previous quest**, where it's the step just before: 2,036.
  - **Left out:** a one-time quest's daily, weekly or repeatable requirement, since the game only
    knows such a quest is done until the reset, but a recurring quest keeps one, as in a chain of
    world quests. One pair that would each require the other (91587 and 91588) is left out too.
  - **Totals:** 4,833 quests had a prerequisite before, and 7,621 now.

The check then found 397 things. The prerequisite ones:
- 26 one-time quests that require a recurring one, already in our data;
- 3 that require a quest of the other faction, two of them where our own faction data looks wrong:
  - the Alliance quest "Garrison Campaign: The Warlock" requires "Secrets of the Sargerei", which
    we have as Horde;
  - "Captured Information" and "Signs of the Struggle" share a storyline but are of different
    factions in our data;
- 6 that name quests outside our data;
- 15 where TrinityCore differs.

## Status

- 2026-10-06: the check written (step 2b) and run; step 2 corrects differing amounts. All 11,035 of
  our reputation rewards matched the API.
- 2026-10-06: decisions 1 and 2 applied (above). Next: several prerequisites per quest, then
  Blizzard's lists and TrinityCore's 2,036 (decisions 3 and 4), and the review of the rest.
- 2026-10-06: decisions 3 and 4 applied: several prerequisites per quest, step 2c (above). Next: the
  user's check in game, then the review of what's left.
