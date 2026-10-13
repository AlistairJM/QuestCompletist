# Data sources review: both games, every source

## Goal

On 12 October 2026 the user found that WoW: Forever's importer used the quest cache's follow-ups to say "this
quest isn't available until you do that one", while retail didn't (retail got it the same day, in #320), and
asked for a full review across both games:

> All data within the addon (Quests, pins, reps, breadcrumbs, mutually exclusive, etc) must be as accurate as
> possible. If there is information we can grab in-game straight from the client, that should be a priority,
> data from the client tables the same, especially if they provide things like starting NPC IDs or starting
> locations, etc. But we always want to take data from every other possible data source so that we can cross
> reference that data and use it when needed also (especially during full sweeps). I also want the parity
> between the way we do things between the different game versions to be as small as possible.

This review goes field by field through both games: what the addon holds, every source that could inform it,
which tool reads what and in which order, and where the two games differ. It finds what is wrong today, what
no tool reads, and what is never cross-checked. Nothing in the data, the addon or the tools was changed. The
recommendations are for the user to choose from, like the other reviews in this folder.

[game-parity.md](game-parity.md) (7 to 12 October) was the first parity audit. It went feature by feature,
and several of its "equivalent" rows turn out to hide different rules. Its rows are corrected in the same
pull request as this review, and they point here for the detail.

## How it was done

- **Code and data:** master f3e3a4f (release 113.0), 12 October 2026. Retail has 35,529 quests and 16,084
  pins; Forever has 5,097 quests and 1,699 pins.
- **Builds:** retail live 12.1.0.69933 and the Forever beta 1.60.1.70338, both the newest on wago.tools that
  day. The 12.1.5 PTR has moved to 70340 while `tools\` holds 70077.
- **Other sources:** TrinityCore TDB 1210.26091 (9 September 2026, the newest release). CMaNGOS classic-db
  Full_DB at content 4493, with 355 update scripts since then that the importer doesn't apply (see
  recommendation 8). The Blizzard web API cache is namespace static-12.1.0_68914, fetched on 29 September.
  It is refreshed at each sweep by design, so that is not a gap.
- **Ten areas,** one reviewer each, both games every time:
  - prerequisites and chains;
  - breadcrumbs and "only one of these";
  - pin positions;
  - who starts a quest;
  - reputation;
  - faction, race, class and levels;
  - which quests exist, their types and availability;
  - holidays, professions and covenants;
  - categories, storylines and menus;
  - a source-by-source inventory of every field the client tables, both quest caches, the API records, both
    emulators, the probes and the recorder hold.
- **Checking:** every finding was then re-measured by a second reviewer, who was told to disprove it, using
  their own scripts and checking samples one by one. Findings raised during that check were checked again by
  a third. A completeness critic looked for fields and sources nobody had covered. It found three: retail's
  quest level, pin icons, and the missing source order.
- **Results:** after merging duplicates there were 181 distinct findings. 178 stood (116 of them with
  corrected numbers), 2 were refuted and 1 was already done. Some corrections changed the advice, not
  just the count. For example, the client field first read as "only while that quest is in your log"
  turned out to mean the reverse. A last pass checked this document itself against the verified evidence,
  claim by claim. Every number below is the
  checked one. The [appendix](#appendix-every-finding-and-its-verdict) lists every finding with its verdict.
- **What decides a recommendation:** the user's rule that a wrong gate is worse than a missing one. A
  prerequisite, class, faction or holiday that is wrong hides or greys a quest the player can take. A missing
  one only shows a quest a little early. Each recommendation says which way its errors would fall.
- **What the filters do by default** (`qcCore.lua:779-793`), which decides what a player sees:
  - completed quests are hidden on the map and shown ticked in the list;
  - other faction, race and class, other covenant, other profession and unavailable quests are hidden;
  - the requirements filter is off: a wrong prerequisite greys the pin and adds a wrong "Requires" line, and
    hides the quest only for players who turn the filter on;
  - the low-level filter is off.
- **Evidence from one character:** `tools\tdb\server_completed_kranaa.txt` is one character's completion
  list from 30 September 2026. Nowhere says how it was made; it looks like the server's list filtered to
  named quests (decision 14). It can point at a wrong link: "done, but the quest it supposedly needs isn't".
  Such a disproof can also be a time artefact, though: a quest added to the chain after the character did
  it, or a faction change (the character has 820 Horde-tagged completions beside 3,591 Alliance ones). So
  its disproofs are review rows, not removals. It can't prove a link, and it says nothing about "only one of
  these" pairs, because the server also flags sibling versions the character never did (every class's
  level-20 weapon quest, all 24 AQ40 class rewards).

## The short answer: why the games differ so much

The two games' data were built at different times, by different routes.

- **Forever** was built in October 2026 by one importer. On every run it reads two sources in full: the
  game's own quest records (the probe asks the server about every quest in the client's QuestV2 table and
  every CMaNGOS quest) and CMaNGOS, the vanilla emulator. It reads almost every CMaNGOS column that matters,
  generates every table, and writes review lists where sources disagree.
- **Retail** grew out of the Curse addon's hand data (109.5 in 2018 through 109.97, which covers content up
  to Midnight). Each field was then corrected from Blizzard's web API. Client tables were added one need at a time, and TrinityCore, the retail-era
  emulator, is mostly used as a check.

That one difference explains most of what follows:

1. **The emulators are read very differently.** Forever reads CMaNGOS's previous and next quests, negative
   groups, conditions, "only while in the log" links, classes, skills, the repeatable flag and chain closing.
   For retail, TrinityCore has the same columns, and they are read narrowly or not at all. Some of that was
   decided on purpose (6 October: TrinityCore prerequisites only where they are the storyline step just
   before; its groups not taken), and some never was.
2. **Generated against hand-kept.** Retail's breadcrumbs, "only one of these" groups, holidays, covenants,
   renown, faction names, zone table and menu are hand data. A sweep audits the links, holidays and faction
   names; the covenants, renown levels, zone table and menu are not checked at all. Forever's are generated
   at each import.
3. **Which source wins.** Forever takes the game's quest record as the value for names, levels, races,
   recurrence, reputation and category, with CMaNGOS as the fallback, and CMaNGOS first for prerequisites,
   links, class and professions. Retail takes the web API as the value and uses the game's record (the quest
   cache) as a check. Neither
   order is written down anywhere as one table (see [Source order by field](#source-order-by-field)).
4. **What gets cross-checked.** Retail has three-way checks with baselines for reputation, levels and the
   quest cache. Forever has none of those. Forever's importer writes review rows where retail's tools are
   silent.

Some of the difference is right, and should stay:

- The web API is Blizzard's own, and only retail has it.
- TrinityCore is thin, or guessed, for content after Mists of Pandaria.
- TrinityCore's groups are often wrong.
- TrinityCore's quest rows are sniffed from the same server record the quest cache holds, so when it agrees
  with the cache or the API, that is one source seen twice, not independent evidence.

Much of it isn't. The review found real defects on both sides that the other game's method would have caught,
sources one game reads and the other ignores, and checks one game runs and the other doesn't.

## Defects found

Each of these is wrong data or wrong behaviour today, with the fix the checking pass settled on. Those
marked *in game* need one look first. The rest can be fixed from the evidence in hand.

| # | Game | What is wrong | What the player sees | Fix |
|---|---|---|---|---|
| D1 | retail | #320 gave 25 quests a Hero's Call or Warchief's Command board quest as a prerequisite, where TrinityCore's previous quest "agreed". In 14 required parts every option is a board quest. Board quests are optional, and the completion list disproves 7 of the 7 it can test: 13594 Don't Forget the Horde, 25478 To the Summit, 26826 Dask "The Flask" Gobfizzle, 28174 Burning Vengeance, 24740 Volcanic Activity, 25316 As Hyjal Burns and 27997 The Corruption of the Jadefire. The other 7 can't be tested: 11585, 14184, 24862, 26022, 26293, 28096 and 28418. | the zone quest greyed, with a "Requires" line naming a board the player never needs | Treat each board quest as a breadcrumb of the quest its cache follow-up names (rows in `qcBreadcrumbQuests`, which step 2c's breadcrumb check already honours). Rerun 2c and show the user the 14 dropped gates first. |
| D2 | retail | Link tables contradict the prerequisites. Since #320, 10562 Besieged! needs 11044, but 49550 Hero's Call: Shadowmoon Valley! also leads to it, and `[49550]={11044}` ticks 11044 done; the same happens to 10595 (11048/49532) and 25428 (25412/25443). About 15 more #320 quests omit a lead-in the cache also names: 12468 The Conqueror's Task needs 12487, though 39206 Warchief's Command: Grizzly Hills! leads to it too; 3721 An OOX of Your Own needs only 836, though the cache names three predecessors and CMaNGOS requires all three rescues. 28504 Warchief's Command: Thousand Needles! ticks both its follow-ups, 25478 and 25356. 85249 can never show (it needs 85084 done, but it is a breadcrumb that closes once 85084 is done). The Gilneas trio 14402/14405/14463 are "only one of these" while Blizzard's API requires all three for 14465 and 14466. | quests marked done that the player still needs; greyed follow-ups that never clear | Remodel the three pairs as breadcrumbs into 10562, 10595 and 25428. Drop `[28504]` from the Thousand Needles group. Set 85249's prerequisite to 85082. Remove the Gilneas trio's exclusive links. In 2c, when the cache names several live lead-ins, take them all as a choice or skip the quest (18 today). |
| D3 | retail | Step 1 and the gap insert read any API class list naming the non-playable Adventurer class as "all classes" (`Resolve-Bitmask`, two copies). | 21 class quests open to every class: a Death Knight sees two copies of 13 Argent Tournament and Hellfire quests, a Druid two Bombing Runs | Skip class IDs outside `qcClassBits`, rerun step 1, apply the 21 fixes. Ship KEEP rows for the rows the fix surfaces: the 117 pre-Evoker lists, the 49 Acherus death knight quests, the 8 Paladin and 1 Mage class-hall quests. 44920 gets its own look. |
| D4 | retail | The Paladin Rescue storyline (5908) has single-faction tags that no Blizzard source asserts: 90548, 90550 to 90554 Horde, 90549, 90555 and 90570 Alliance. Only the starters 90546 and 90547 are faction quests. The map pass offered 90548 and 90550 to an Alliance character, and Blizzard's API makes 90551 and 90556 need quests of both tags. | 6 quests hidden from every Alliance character and 3 from every Horde character | Set 90548 to 90555 and 90570 to both factions. Make 90548's and 90549's prerequisite a choice of the two starters. Drop KEEP row 78 of quest-table-decisions.csv. |
| D5 | both | Seasonal completion marks never clear by themselves. The server is believed to reset a holiday quest for the next year (unproven offline, and it may happen at the next event's start rather than this one's end), but once `qcRecordServerCompletion` marks it, no automatic path clears the mark, whether it came from the player's own hand-in or a link tick; only Clear update cache or a shift-click does. That is 1,165 markable seasonal quests on retail (583 of them typed 1, not 64) and 228 on Forever. | last year's holiday quests shown done for ever (hidden on the map) | *In game:* one `/run` per game on a quest done in a past holiday, to see whether it reads not-flagged now. Then, in shared code at login, drop mark-1 seasonal quests the server doesn't flag, and let the sync re-apply links. |
| D6 | Forever | The cache follow-up rule makes 29 quests need their own breadcrumb, the defect retail fixed in #322. Of these, 2238 needs 2218 (proven in game); 2260 and 2298 were kept until a look in game; 15 are zone quests that no report settles (11, 276, 297, 466, 729, 844, 870, 1085, 1338, 1420, 2038, 2040, 2922, 2924, 2930), though first-hand reports went against six similar zone links (364, 429, 455, 639, 1275, 1302, now REMOVE rows); 11 are class lead-ins (1473, 1501, 1688, 1699, 1716, 1758, 1824, 1882, 1884, 1938, 1960). The 15 zone links and 9 of the class links are on the list the user left "not changed" on 11 October (open-items, "Data to finish"); 1882 and 1884 belong to the open mage lead-in question. | zone quests greyed for players who skipped the lead-in | Give the importer retail's filters (recommendation 10), after SET rows for 2238, 2260 and 2298. Whether the filter then drops the 15 zone links and the 11 class links is decision 3, since it reopens the 11 October call. |
| D7 | Forever | 26/27 A Lesson to Learn: CMaNGOS has the givers the wrong way round, so the Alliance quest is pinned on Turak Runetotem in Thunder Bluff and the Horde one on Mathrengyl Bearwalker in Darnassus. classic-db update 4777, not applied, swaps them. Blizzard's cache also says 27 leads to 28 and 26 to 29 (Trial of the Lake), while our data has 28 needing 26 and 29 needing 27. The KEEP rows calling that harmless misread it: a prerequisite the character can't take counts as met, so Trial of the Lake shows first. | a druid sees no pin at their own trainer; Trial of the Lake shows before A Lesson to Learn | SET rows 28 needs 27 and 29 needs 26, retire KEEP rows 2-3 of forever-quest-table-decisions.csv. For the givers, give the importer a replace decision (adding rows to forever-quest-givers.csv keeps the wrong pins behind the faction filter). Review 4736/4737, 4967/4968 and 8228/8229, which CMaNGOS also contradicts. |
| D8 | Forever | The game's `IsBreadcrumbQuest` is true for 954 Bashal'Aran, and false for 958, the other quest the same NPC offered. But our data makes 955 Bashal'Aran (Asterion) need 954. | if 954 is optional, Asterion's chain 955 to 957 is greyed for players who walk there directly | *In game:* does Asterion offer 955 to a level 7+ Alliance character who never took 954? If yes, add prereq REMOVE and breadcrumb ADD rows. If no, a KEEP note. |
| D9 | Forever | Forever put new quests into the Teldrassil chain (937 to 98392 to 98398 to 940), but 940 still needs CMaNGOS's 937. | 940 may show two steps early (the milder error) | *In game:* is 940 offered before 98398 is done? Until then keep it. List "the cache's source is a quest CMaNGOS lacks" in the import review (7 quests). |
| D10 | retail | When a quest's start moved to another map (the 20 September and 8 October rebuilds), `Assemble-PinDB.ps1` copied the old pin's NPC from the other map (line 48). 45174 The Hunt for Illidan Stormrage has 12 class-hall pins all named Allari the Souleater, who stands only in Azsuna. 11052 is named A'dal on map 104, 32329 Lor'themar at Domination Point, 54754 Nazgrim in Redridge, 57147 Gail Nozzywig, 37689 Taoshi in Stormwind. 1,771 pins still carry such a borrow; 1,300 of them are confirmed by no source, and 119 of those are contradicted by the NPC's own spawns. | pins naming an NPC who isn't there (the user's "a wrong NPC name is not fine") | Recommendation 31: fix the code, then work through a review list of 99 NPC pins whose NPC spawns elsewhere and that no source names as a starter (90 of them borrows; holiday NPCs excluded or KEEP), blank or KEEP by hand. Start with 45174. Leave the unconfirmed rest as a baseline for the recorder. |
| D11 | retail | Pin icons are legacy codes the current code reads differently. The 76 "weekly" icons are all item-started one-time quests. 115 pins draw the profession icon over 380 quests with no profession (the WANTED dungeon dailies, Quel'Danas dailies). The weekly PvP quest 28882 has a seasonal icon. Forever computes its icons from the quests. | misleading icons | Recommendation 32: one icon rule for both games, built from the quest fields (about 1,960 retail changes, shown to the user first). |
| D12 | retail | 86 world quests are typed one-time, though the game's own `IsWorldQuest` says they are world quests. | ticked for ever once done | Have `Retype-ProbeRecurring.ps1` read the probe's world-quest answer and move them to 128. |
| D13 | retail | The 6 October link fixes may have left ticks the server doesn't confirm on 10 quests, for players who handed in a removed partner on 109.97 to 111.x, but retail's `qcFormerlyExclusive` is empty: 1453, 11441, 11446, 26785, 26865, 26867, 26897, 27062, 27063, 28651. | quests stay marked done | Seed the list. In both games, build it from the difference between the released link tables and the new ones, both link types. |
| D14 | retail | The low-level filter, the list bracket and the level sort use the stored level, which is the legacy data's scaling floor (equal to the API's minimum for 28,668 of 30,066 quests, but never refreshed). At level 90 the game rates 10,196 quests at 90 whose stored level is below 80. | with "Hide low-level quests" on (off by default), current quests are hidden | Recommendation 27; let the 12.1.5 probe's `IsQuestTrivial` settle it (open-items row 9). |
| D15 | retail | 8 test-titled quests match Forever's own internal-name patterns (94580 Kate's Test Quest among them), and 11 more are plain developer titles (50035 Bret Test - SQL, 77988 Test, 86921 This is a repro test...). None has a decision. Four tools use four different patterns. | test quests in the list | One shared pattern that raises review rows in both games' step 7. The user decides each (decision 20 style). |
| D16 | retail | 38 quests with no API record keep legacy names that Blizzard's own cache, probe or task table contradict. | a stale name before the game's loads | Fall back to the cache, then the probe, then the task title, copied exactly. Send the 4 "[DEPRECATED]" ones to step 7. |
| D17 | retail | Smaller ones. 72878's API requirement tree has no operator, so 2b and 2c skip it. Step 1b reads the conditions on point -1 (mostly hand-ins) instead of the start (32). 56071's starting item is Horde-only. 4 quests (1442 among them) lack the class their class heading gives. 11 quests' stored level is above the API's maximum. `qcAreaIDToCategoryID` has a stale duplicate `[2372]=10`. | a handful of wrong votes and values | Fix each in the pull request of its area. |
| D18 | Forever | 7281 Brotherly Love and 7302 Fallen Sky Lords have no pin: their givers spawn only through `creature_spawn_entry`, which the importer doesn't read. | no pin | Read `creature_spawn_entry` and `gameobject_spawn_entry`. |
| D19 | both | The holiday spawn rule keeps only the last event of a spawn that is in several holidays' events. Forever is not affected today (CMaNGOS has none). Applied to TrinityCore, the same rule would tag 4 retail quests Day of the Dead (11357, 13484, 29074, 29400). | none today; a hazard for any shared or retail resolver | Count a spawn in more than one holiday's events as no evidence, in the importer now. |

## Recommendations, by theme

Each row gives the evidence in brief, which way errors would fall if it is applied, and the effort. The ranked
list is at the end of this section.

### 1. Let the game check the data

The user ranks the game first, but today the game's answers reach the data mostly through the quest cache.
The probe and the recorder already sit in both games, so a few more fields turn ordinary play into the check
of almost every field below.

| # | What | Games | Evidence | Errors fall | Effort |
|---|---|---|---|---|---|
| 1 | **A completion snapshot.** The probe saves `GetAllCompletedQuestIDs` (with faction, race and class bits, nothing identifying) on each quest run and map pass. One shared tool lists the prerequisites and in-log links it disproves ("done, but the quest it supposedly needs isn't"), as review rows with a baseline, in steps 2b and 10. It can't judge "only one of these" links, since the server flags sibling versions too. The map pass's "offered together" rule (2c) then becomes exact for the probe character. | both | One 30 September list already disproves (as review rows; some may be time artefacts): 1.9% of retail's checked links (103 of 5,415); 7 of the 7 board gates (D1); 41 of the 63 storyline-only disproofs, in four Dragonflight renown lines (1380 to 1383); and 9 of the 19 testable Dragonflight renown decision rows (70809, 72299, 72302, 72303 need 72039; 70910, 72335, 72336 need 72698; 71075, 72313 need 72131). | review rows only | medium |
| 2 | **The recorder notes more at an offer and a hand-in** (one schema change, shared code): (a) at each offer, the offered quest's prerequisites and in-log quests our data says are unmet; (b) the lowest level a quest was offered or accepted at; (c) the standing and renown with the factions in the quest's rewards and requirements; (d) at hand-in, the reputation gained; (e) AND-ed masks of the professions and covenant known; holidays running only with the user's OK, since the recorder's decision 2 keeps nothing identifying and no time; (f) once open-items row 42 is built, the game's map offers (quest, map, x, y). Step 6d carries them; 2c, the importer and step 2 list contradictions. | both | It settles, without a test sheet: TrinityCore's `AllowedMinOffset` (2,824 retail gates, recommendation 26); row 15's 2,085 cache-only rewards (allowing for reputation bonuses); Forever's Classic reputation tiers; the standing maxima (recommendation 24); and it gives evidence on the profession and holiday tags and against any of the 92 unsourced renown rows (an offer seen below the stored renown), though slowly. The probe already saves the lowest offered level, but its reader drops it. | review rows only; an offer at level L can only show a gate set too high | medium |
| 3 | **Marks that heal themselves** (shared code): when the game offers a quest the addon has marked done (mark 1) and `IsQuestFlaggedCompleted` says no, drop the mark. This also clears stale link ticks (D2, D13). At login, drop mark-1 seasonal quests the server doesn't flag (D5). | both | The game's offer proves the quest can be taken. | towards showing | small; D5 needs one line in game first |
| 4 | **One probe-facts check** for both games (steps 2e and 10). The probe's facts pass is saved on both and read by no tool. Use `factionGroup`, level, title and group size against the cache as a zero-tolerance tripwire: this gives Forever the cache check retail has, and closes `Compare-QuestCache.ps1`'s "group size not checked". List `IsBreadcrumbQuest` true where another quest requires it (D8), `IsWorldQuest` against our type (D12), and the quest line and campaign against our storyline (559 retail quests differ; `GetCampaignID` answers 0 for 5,211 the tables put in a campaign). | both | 0 differences today between the probe and the cache on level, title, group size and faction (retail 32,735 quests; Forever 2,935, 800 with a faction). The game's faction contradicts ours on 30 retail quests, all already known from the cache (retail-quest-cache.md, "Races"; open-items row 17); 9177 and 47253 are fixed with row 17's work. | report only | small |
| 5 | **Retail probe lists.** Add only the 560 to 700 player-facing quests of the missing-quest report (recommendation 37) to the quest list, not all 32k QuestV2 rows; this revisits the user's 9 October call (decision 12). Add the 1,150 TrinityCore and client-table starters never asked to the NPC list. Run the 12.1.5 probe on a Horde character: its row now records the character (#258), so refusals get a second faction for free. | retail | Of the 1,221 refusals of 9 October, Horde-only quests were refused 4.9% of the time against 2.4% for Alliance-only. The run row records no character (Alliance is inferred from the same session's map runs), all 1,221 were already refused on 29 September, and 6,232 of 6,552 Horde-only quests did load, so faction may explain only part of it. Asking takes about 11 quests a second. | adds answers only | small |
| 6 | **Point the retail recorder at the nameless pins.** 3,735 retail nameless pins have no static source at all (by map, task quests included: Zereth Mortis 169, Maldraxxus 126, Mechagon 126...). Leaving out the task and auto-accept pins, about 2,800 could be named by the recorder, and it has no retail records yet. Put "nameless pins by map" in step 6d's report, so ordinary play and players' files fill them. | retail | Excludes task and auto-accept pins (829 and 76), which have no giver to record. | none | small |

### 2. Read the emulators the same way

TrinityCore and CMaNGOS come from one codebase and agree where both speak: breadcrumbs 123 of 123, previous
quests 1,983 of 2,156, minimum reputation 232 of 252, skills 136 of 141. One thing differs: TrinityCore
requires a quest's previous quest *and* any quest that names it as next, while CMaNGOS accepts either. Any
shared reader needs that switch.

| # | What | Games | Evidence | Errors fall | Effort |
|---|---|---|---|---|---|
| 7 | **One emulator reader**, with the semantics switch, used by the importer and by retail's 2b and 2c. (a) Retail `qcQuestNeedsInLog` from TrinityCore: 20 negative previous quests (12557 Lab Work needs 12596 Pa'Troll in the log, the candy quests 8353 to 8360, Troll Patrol) and 19 single-branch in-log conditions, each reviewed by hand; drop those naming quests we lack. Never from the client's `PlayerCondition.CurrQuestID`: on all 21 conditions our 101 task quests use, it means "not while that quest is in the log", the reverse. (b) Forever: CMaNGOS's "quest taken" conditions as in-log links for 308, 1789 and 1790. (c) Retail step 2b, report only: TrinityCore's AllowableRaces and AllowableClasses (a mask with no post-Wrath class bits counts as unknown for those classes; 23 quests are open to all where TrinityCore restricts them and the API is silent), the standing requirements, negative groups (69 quests), "quest rewarded" conditions (83 quests, 0 of 44 parts disproved), the 106 previous-quest differences (other-faction options dropped), ContentTuningID in `Compare-QuestLevels.ps1`, MaxLevel and quest pools. TrinityCore's RequiredSkillID is the exception: it fills profession tags where Blizzard's passes are silent (recommendation 23). (d) Forever, report only: TrinityCore against CMaNGOS's links (4 TrinityCore-only breadcrumbs go into the open mage/priest lead-in question), skill levels (3 differ) and holidays (276 agree, 0 differ). | both | TrinityCore is a retail-era emulator, so its masks lack allied races (52244 to 53319 have no Kul Tiran) and are sometimes starting-race narrow. A wrong one hides a quest. Hence report only, with values taken only through decision rows. | review rows; (a) and (b) add gates, after review | medium |
| 8 | **CMaNGOS's update scripts.** The dump is content 4493; 355 classic-db update scripts since (October 2023 to September 2026) are not applied. They change the previous quest on 10 of our quests, the races on 6, the next quest on 3, a skill on 1, the givers of 26/27 (D7), and the givers of the six Heeding the Call quests 5923-5928 (update 4744; 5924 is pinned at Fylerian Nightwing, who no longer gives it). One of them settles the open 769 Kodo Hide Bag (Leatherworking 10, no link to 768). Now: step 10 reports the newest update against the dump and lists every statement touching an imported quest; each is reviewed and applied as a decision row citing the update. Later: import Full_DB with the updates applied by a real SQL engine (a throwaway portable MariaDB, as CMaNGOS's own installer does), since `Read-SqlDump.lua` can't run them. | Forever | Of the 10 prerequisite changes, 6 loosen a gate, 2 retarget (3787/3788) and 2 add one (8484/8485 need 8481; look first). The updates are VMaNGOS and Classic sniff research, better than the 2019 dump, but vanilla isn't Forever. | mostly towards showing | small now, medium later |
| 9 | **TrinityCore previous quests for retail** (decision 1, reopening the 6 October call). For 1,143 quests the API is silent and ours is empty; 974 of them pass retail's filters (795 previous-quest-only, 69 negative-group, 83 condition, 27 next-quest-only). Of the previous-quest candidates, the completion list disproves 2 of the 295 it can test (0.7%, against 1.9% for our own links); 822 are vanilla to Cataclysm, but 508 have no storyline for the client to check. If taken: first the negative-group (69) and condition (83) links, then the previous-quest-only ones as a review list with three new filters. Those filters: TrinityCore's own BreadcrumbForQuestId and our breadcrumb table (the 2c breadcrumb check never sees the TrinityCore branch), board quests, and a previous quest that is a later step in every storyline that holds the quest (59314 Sinfall shows why one storyline isn't enough). | retail | 5 candidates are TrinityCore's own breadcrumbs and 6 are board quests: wrong gates. 10 are later steps in one storyline and need review across every storyline (59314 is right there, 27290 is reversed, the rest look parallel). The negative groups have one measured disproof: 12 of 151 parts, all from 9365 A Thief's Reward, whose all-four-flames group predates Silvermoon. | adds gates | small |

### 3. One set of rules for the quest cache

Both games read the same server record through one walker (`Read-QuestCache.ps1`), but use it differently.

| # | What | Games | Evidence | Errors fall | Effort |
|---|---|---|---|---|---|
| 10 | **One follow-up rule.** A quest becomes the prerequisite of the quest its cache follow-up names only if: it isn't a breadcrumb into that quest (the emulator's BreadcrumbForQuestId, our breadcrumb table, breadcrumb ADD rows); it isn't a board quest; it isn't recurring; it isn't the other faction's; the follow-up's minimum level isn't lower than its own; it isn't unavailable; and it doesn't make a cycle. When several live lead-ins name the quest, take them all as a choice or skip it (Forever already skips). Retail has most of these and gets the board and several-lead-in filters (D1, D2). Forever gets them all, after SET rows for 2238, 2260 and 2298 (and for the class links, if decision 3 keeps them), so the filter drops only what decision 3 lets it (D6). Keep retail's TrinityCore-agreement condition: the wider retail rule (990 storyline steps, 0.9% disproved) waits for recommendation 1 or row 42, as the user decided on 12 October. | both | Retail: TrinityCore-agreed follow-ups are disproved 0.7% of the time, breadcrumbs into the quest 35.7%. Forever: 225 follow-ups taken with no filter; 44 sources are CMaNGOS breadcrumbs. | towards showing | small |
| 11 | **List where the emulator and the cache disagree,** in both games' review output with a baseline. Forever has 5 today: 28/29 (D7); 413 and 443, which are fine; and 940 (D9). Also list "the cache's source is a quest CMaNGOS lacks" (940 replaced; 19, 465, 480, 5929, 5930 and 6101 have Forever's new quest as an extra source, safe to add as "any of" after the user sees them). Check the cache's follow-up layout against TrinityCore's RewardNextQuest, which matches it for 32,688 of 32,688 quests. | both | It found D7 and D9. | report only | small |
| 12 | **Recurrence from the server's flags,** as Forever does. Retail's types agree with the cache's daily and weekly flags for 96.7% of quests (31,845 of 32,930); 185 would change. That is open-items row 16, waiting class by class. The obvious first class is 116 where the API agrees too, plus 38 task quests typed one-time that the server calls recurring, which today get a tick for ever. Build one tool with `-Game` and a baseline. For "repeatable", the probe's `IsRepeatableQuest` answers false for every quest on both games, so it is no source. Retail keeps the API's `is_repeatable` (TrinityCore's SpecialFlags and absence from QuestV2 as weaker votes); Forever has no Blizzard field; the offer's repeatable flag (recorder, probe givers) is the in-game tiebreaker in both. A side-by-side report only: raise to the user only rows where two independent sources say one-time. | both | | towards showing (un-ticks) | medium |
| 13 | **Availability signals.** (a) Add the server's own Deprecated (0x4000) and Tracking (0x400) flags to step 7 as columns, both games. 42 + 4 retail quests carry them with no decision; show them in five groups: a live twin of the same faction (15), only the other faction's version (3), twin also refused (2), API 404 only (21), API-served (94474 The Great Vault, lean KEEP). (b) Count the 87 API-served quests that meet the "sure sign" (absent from QuestV2 and refused); the summary only counts API 404s today. (c) Add as weak columns the server's quest type 1, CMaNGOS method 1 and TrinityCore's "Deprecated quest" disables (125 of our quests; the same kind of disable also covers 74 of the 147 missing holiday candidates, a filter for recommendation 37). (d) Name the probe character's faction in refusal evidence, and treat an other-faction refusal as weaker. (e) Correct the evidence text of 5 FLAG rows (55686, 55687, 55712, 55713, 61161), which say "unknown to the server" though the 9 October probe loaded them. Flags stay review-only: Midnight quests carry 0x4000 too. | both | | review rows only | small |
| 14 | **The reader keeps more** (both games). Keep the giver creature IDs in the cache's description entries (97 retail quests; Forever's 95250), never the completion-log ones (50 quests name the hand-in or "meet" NPC; keep those as a separate field for the pins-at-turn-ins review). Keep AreaGroupID (36 quests with no sort, 30 of them Ember Court), RewardSkillLineID and each reward's rank cap. Fix the "quest type 1 = disabled" label (type 1 is live boards, Darkmoon decks, garrison inn quests). The reward skill is a cross-check only: 48883 Big Gulls Won't Die rewards Fishing but doesn't need it, and 61545 rewards Inscription while needing Herbalism. The rank cap needs one look in game before the tooltip says "none at your standing" (98 retail quests, 6 Forever). | both | | none (fields only) | small |
| 15 | **Rewards.** Keep retail's API-first rule and row 15 as decided: the cache reproduces 11,690 of 11,690 API rewards, and TrinityCore's 100% agreement is the same server record a third time. Give Forever the check it lacks, rewards against CMaNGOS with a baseline. Use classes: same step; equal amount (56 CMaNGOS rows hold Classic values); step differs (7: 378, 384, 633, 1470, 5723, 5724, 6921); factions differ (35); CMaNGOS only; game only; game says none (11). Don't fill Forever's 1,008 unanswered quests from CMaNGOS: about 7% of quests would be wrong, and the gap is only until launch. Add TrinityCore as a fourth, report-only set to retail's comparison. Use one per-race "shown faction" helper in both games: the flags are per race group, and Wildhammer Clan is visible to Dwarves. | both | | report only | small |

### 4. Client tables not used yet

| # | What | Games | Evidence | Errors fall | Effort |
|---|---|---|---|---|---|
| 16 | **"Starts from"** (open-items row 19, already taken). Build it once in shared code from each game's own ItemSparse (`StartQuestID`), named live by `C_Item.GetItemNameByID`. Show it beside the giver line, not instead of it. Convert the 99 pins named exactly after a starting item. In the same pass: a start-item profession vote (it tags the 10 Mechagon fishing quests); ItemSparse's AllowableRaces as a review vote (it makes 56071 Horde); and on Forever, a comparison of the client's item starts with CMaNGOS's. | both | Retail: 1,789 items start 1,430 of our quests, which today the tools read only for class. Forever's importer reads its own ItemSparse for class too, but its item starts haven't been measured; CMaNGOS's 200 item-started quests stand in. | none for the line; review for the votes | medium |
| 17 | **Renown from the client's conditions.** The task table's PlayerConditions carry renown two ways: ModifierTree type 119 on a renown currency (48 quests), and PlayerCondition's own CurrencyID/CurrencyCount columns (21 quests). Of the 21, 4 equal hand rows exactly (79232, 81692, 81906, 90663) and 17 are new. Among them are the only Midnight renown requirements in any source: 54781, 91928, 91929 (The Singularity 11) and 96267 (Zul'jarra's Forces 10). In all, 65 quests the hand table lacks. Write them as generated rows; step 2b reports which hand rows the client confirms. Take the value where the text differs (Hallowfall 3 against "Rank 5"); 79333 needs all four TWW renowns at 4; leave out 72068, an objective's condition. | retail | quest-table-checks.md says the client has no renown requirements; it does. | adds gates from Blizzard's own conditions | small |
| 18 | **Older expansions' line and campaign conditions** (decision 2). The client's conditions are applied only for the current expansion. 18 older gates name only quests in our data and would gate 640 Battle for Azeroth, Shadowlands and Legion campaign quests (15 of them recurring), 633 of which have no prerequisite today. None is disproved (0 of 405 checks). The 52 gates naming hidden quests stay out: 35 of 35 checks disproved. | retail | Blizzard's own conditions, but line conditions, not necessarily acceptance checks, and one long-played character can't test the skip routes (Chromie Time, Threads of Fate); a wrong one hides a whole campaign. The covenant gates already carry both paths. | adds gates | small |
| 19 | **Categories from the game's sort** (open-items row 18, taken). Add the cache sort and the API category ahead of the API area in `Place-UncategorisedQuests.ps1`. File automatically only by a zone or a heading whose namesake category exists. Review the mixed headings by hand (-615 Trading Post, -432 Warfronts, -22 Seasonal, -646 Secrets of Azeroth), and never file test titles. A strict modal places 80 catch-all quests; the looser method 132. List first which moved quests change pin eligibility (recommendation 34). Then build the planned report-only `Audit-QuestSort.ps1`, with an exception file seeded with the deliberate sub-zone, dungeon and class-hall categories. About 10 are clear misfiles, e.g. 5 Midnight Silvermoon quests under Azuremyst Isle (94474, 94993, 95008, 95114, 95276) and 84419 To da Ruins!. Also add a zone-table report for unrouted zone maps (2472 Tazavesh, 2536 Atal'Aman, 2599 Val, 2600 Naigtal, 2451 Arathi Highlands) and make `Add-ZoneTableMaps.ps1` fail on duplicate keys. | retail | The cache sort equals the API's for 29,049 of 29,049 quests and TrinityCore's for 33,035 of 33,048. | menu placement only | small, then medium |
| 20 | **A holiday resolver for retail,** smaller than Forever's. Apply the SET/CORRECT rows. Fill an untagged quest only from Blizzard's heading (API category, then the cache sort) or a TrinityCore event relation that no Blizzard heading contradicts. Use as corroboration only, never as the sole filler: Blizzard's holiday achievements (they back 721 of 722 criteria quests in our data; the one exception, 11023 Bomb Them Again!, is an all-year daily), TrinityCore's sort and conditions, and spawns. Add SET/KEEP rows for the 11 holiday tags no source supports. Also add the cache sort and TrinityCore's sort and conditions to step 2d as signals. | retail | In this shape (Blizzard's heading first, TrinityCore events next, achievements and spawns as support only), today's tags are reproduced with no wrong additions. The first pass's 1,295 of 1,304 used achievements as fillers, which would tag 11023 wrongly, and 379 of its matches were decision rows reproducing themselves. | a wrong tag hides a quest all year, so fills come only from Blizzard's heading or an uncontradicted TrinityCore event relation | medium |
| 21 | **Covenants from the client:** a pass and check through campaign prerequisites (ModifierTree type 288), task conditions and covenant headings, with the intersection rule (a quest several covenants name, such as the chapters of the shared QuestLine 1210, stays untagged: 60287, 60289, 61355, 62837, 62882) and a baseline. | retail | Reproduces all 777 tags with 0 conflicts and finds 7 more. | adds 7 tags (4 world quests) | small |
| 22 | Lower value: CampaignXCondition chapter gates (measure in `-WhatIf` first, and never read NOT trees as met); the task quests' ModifierTrees (435 name a quest we hold); start points' PlayerConditionID (decode only the previous-quest ones into a per-pin gate). | retail | | adds gates | small each |

### 5. Requirements: missing sources and new gates

| # | What | Games | Evidence | Errors fall | Effort |
|---|---|---|---|---|---|
| 23 | **Profession tags from the emulator and start items.** Add a TrinityCore RequiredSkillID pass to step 1d that fills only when Blizzard's passes are silent; 8 live quests gain a tag (768, 6032, 7493, 7497, 11016, 11017, 11018, 12888). The 16 Felwood salve quests are refused by the server and go to the unavailable review instead. Add the start-item pass (recommendation 16). Then list tags no pass or decision supports (83 profession, 11 holiday) and settle them with SET/KEEP rows. On Forever, write a review row when CMaNGOS's RequiredSkill and the game's heading disagree; keep RequiredSkill first, since a heading says where Blizzard files a quest, not what it needs. | both | TrinityCore agrees with all 653 overlapping retail tags. | the profession filter is on by default, so these fills come only from requirement sources | small |
| 24 | **Reputation standing requirements** (both games, one table `qcQuestStandingRequirements` and one code path, read with `C_Reputation.GetFactionDataByID` and friendship ranks). Retail: 513 quests, from the API (469); TrinityCore's 44 only where the API has no record (4). Forever: 212 quests from CMaNGOS. Today the Aldor and Scryers quests, the Argent Dawn mantles, the Timbermaw and Zandalar turn-ins and the rest look takeable to everyone. Compare by the rank that holds the threshold, not by raw standing. Ship minimum gates first (254 retail quests above Neutral). Enable maximum gates only after 2 or 3 looks in game, because the API's maxima mix conventions: The Eye of Command has minimum = maximum = 42000, and 60 Tillers gift quests stop at "max 42000". | both | | min gates add requirements from Blizzard's or the emulator's data; raw max gates would hide quests from Exalted characters | medium |
| 25 | **A maximum level** (sparse `qcQuestMaxLevel`, both games). 76 Forever battleground bracket quests (54 pinned) show to every character above their bracket. Confirm once on Forever that a level-60 character is offered only the 51-60 version. | both | | adds gates after the check | small |
| 26 | **TrinityCore's AllowedMinOffset.** TrinityCore lets a quest be taken up to 4 levels below its minimum. If the game does the same, 2,824 retail gates are 1 to 4 levels too high. Settle it with recorder levels (recommendation 2) or one look, then change the formula in `QuestLevels.ps1` once. | retail | | today's error, if real, greys these quests for 1 to 4 levels (hides them with the requirements filter on) | small |
| 27 | **A scaled level for the low-level filter** (D14). Store a per-quest scaling cap from the cache's ContentTuningID (MaxLevel plus the scaling offset; AllowedMaxOffset 255 means no cap). It predicts the game's level for 31,231 of 32,720 tuned quests (95.4%). The filter compares the player's level, clamped between the minimum and the cap, and asks `C_QuestLog.IsQuestTrivial` live where the quest is loaded (both clients). Keep the bracket and the sort on the stored floor unless the user wants scaled numbers. Let the 12.1.5 probe's `IsQuestTrivial` confirm the AllowedMaxOffset 255 reading before building (open-items row 9). | retail (Forever keeps its fixed level) | | towards showing | medium |
| 28 | **Profession skill levels on retail** (game-parity recommendation 3, data half). After the agreed check in game: the task table's values on their own expansion lines (524 quests, 334 above 1), and TrinityCore's (60 profession levels above 1, not 78; 18 are Riding). TrinityCore's values above 300 are on the old cumulative scale and must be converted to the expansion's line (301 to 375 is Outland at value minus 300, and so on). Loading them as they are would grey the quest for everyone. | retail | | waits for the check | medium |

### 6. Pins

| # | What | Games | Evidence | Errors fall | Effort |
|---|---|---|---|---|---|
| 29 | **Move legacy pins to TrinityCore's start.** 6,612 pinned retail quests have a TrinityCore start point and no client one. The TrinityCore pass skips any quest that already has a pin, so their legacy pins were never moved the way client-placed ones were on 8 October. TrinityCore's start agrees with the client's in 23,087 of 23,092 shared cases. Of these pins, 440 stand more than 1.5 points from TrinityCore's start on the same instance. Apply automatically only to the 392 single-pin quests among them (e.g. 26121, 26134, 887 Dizzywig 19.9 points from his only spawn, 26336); hold multi-pin, other-map and phased cases for a person. Rerun 6c after. | retail | | wrong pins corrected; the identity guard of recommendation 31 must come first | medium |
| 30 | **The TrinityCore pass's holds** (decision 6). It holds holiday, seasonal and profession quests that Forever pins from the same kind of source: 337 quests would be placed. All 258 Candy Buckets need object-spawn placement at the same time, or half the inns get one. It also holds type-2 repeatables for not being in QuestV2, which omits almost all repeatables (914 of 995): waive that hold for them (101 quests, to the review list first), but not for dailies and weeklies, which QuestV2 does list. For quests with no point 32: use TrinityCore's 32 where it has one (18 quests), and list the 26 pins that stand only at a TrinityCore ender and the 64 item-started quests at their -1. Place the 16 board quests from TrinityCore's object spawns. Put the starter-spawn fallback (74 quests, mostly retired) in the review list, not on the map. | retail | Retail pins 38% of holiday quests and 57% of profession quests; Forever 85% and 96%. | review lists first | small |
| 31 | **Pin identity, retail, in one change.** (a) Fix `Assemble-PinDB.ps1`: line 48 returns nothing; the safety net counts a quest as covered once it has any new row (or 1,555 quests regain an old hand-in pin); and the same-map branch, which copies an identity at any distance, gets a distance cap. Fix `Build-QuestLocationData.ps1:370` in the same change, so it passes `StarterNpcIds` for pinned quests too. Fixing line 48 alone would make every cross-map row nameless, the right names included. (b) Name the nameless: 372 pins (351 quests) stand within 1.5 points of a TrinityCore starter of their quest; 46 copies the client's giver table skips (`Apply-ClientQuestGivers.ps1` stops at any NPC pin); 45 nameless pins of object-started quests stand at their object (59 pin-quest pairs). (c) Review lists in 6c, each with a baseline: the 99 NPC pins whose NPC spawns elsewhere and that no source names as a starter (90 of them cross-map borrows, D10; holiday NPCs excluded or KEEP); the 96 unlisted pin-quest pairs TrinityCore contradicts (of 113 counted, 34 of them at the ender; the other 17 are already listed as client-table quests); the 133 item- or object-started quests on NPC pins (52 at the ender, which go to the pins-at-turn-ins question); and the 14 TrinityCore/client giver-table disagreements (99.2% agree). | retail | | names only where the quest's own starter stands at the spot; a nameless pin is fine | small |
| 32 | **One pin-icon rule** for both games, built from the quest fields at build time: all seasonal, then seasonal; all one profession, then profession; all limited to one class or a few, then class (not Forever's literal "class isn't everyone", which would put the class icon on about 100 near-generic pins); otherwise plain. Retire codes 0, 2, 4, 6, 7, 8 and 10. Derive an "item starts this" icon from ItemSparse in both games if one is wanted. Add a step-9 check that every icon matches the rule. | both | About 1,960 retail changes; Forever's 1,699 already follow its rule. | icons only | small |
| 33 | **A pin-source agreement report** for both games (steps 6 and 10), report only, with a baseline file. Compare client 32 with TrinityCore 32 (23,087 of 23,092), with TrinityCore starter spawns (96.2%) and with the giver table (99.2%); the recorder with CMaNGOS (47 of 47 spots, 42 of 42 offers); and kept legacy pins that no source supports (1,301 retail quest-pin pairs; Forever's 50 old-pin quests as review rows). Use same-instance projection, and exclude pins at any start from "far from the starter" lists. Baseline the map-pass comparison too (254 offers within 1.5 points; 1 over 5; 4 with no pin), delete or rename the older `map_offers_69933.tsv` (a 7 October run; step 2c reads the `_retail_` file), and give `Report-MapOffers.lua` a restrictions section: a non-hidden offer our faction, race, class or level gate excludes is a fix candidate (it would have found D4). | both | | report only | medium |
| 34 | **Pin eligibility follows the category.** `Build-QuestLocationData.ps1` and `Import-RecordedGivers.ps1` refuse new pins to quests in listed categories (20 system and 11 holiday categories in the first; 14 in the second, by decisions 5a/5b). Any category change (recommendation 19) therefore also changes pin eligibility: 52 of the 132 catch-all placements land in held categories. No pin changes today: 31 are already held for other reasons and the rest lack a TrinityCore start, and the 32 the recorder pass would newly hold have no retail recordings yet. Have every placement dry run list those, and keep the lists in one shared file (they are hard-coded three times). Basing eligibility on quest kind instead is a separate decision for the user, not part of this. | retail | | | small |
| 35 | **Forever's smaller pin items:** read `creature_spawn_entry` (D18); put the 20 item-started quests with one CMaNGOS drop source on a review list, named after the item (where the object is the start, e.g. 781 Dirt-stained Map, pin it outright); list the 11 quests with a client start point that aren't imported (96912 to 96921, 91564); build row 37 (one 1.5-point radius); decision 7 (nameless pin per quest or per spot) is still open. | Forever | | | small |
| 36 | **The recorder's precedence:** align identity, not position. On retail, step 6d may add a pin or fill an empty identity for a trusted recorded offer whose pin NPC no Blizzard source confirms, and lists the disagreement, as Forever's importer does. It never moves a retail pin off the client's start point (recorder decision 9; "pins that match client data stay"). | retail | No retail recordings exist yet, so nothing changes until the first ingest. | | small |

### 7. Hand-kept and generated tables

| # | What | Games | Evidence | Effort |
|---|---|---|---|---|
| 37 | **A missing-quest report** for both games (report only, baseline). It lists quests that QuestV2, the cache or TrinityCore know and the data lacks, with a "player-facing" test (a TrinityCore giver, a TrinityCore or client start point, a starting item, or a quest-line row). It leaves out task rows, internal titles, quest type 1, TrinityCore's "Deprecated quest" disables and the 0x4000/0x400 quests. Retail has about 560 candidates, including 93701 Brittle and Brilliant; about 40 holiday ones look live. First the 15 Midnight Candy Buckets 97142 to 97213 (Hallow's End starts in about a week; they have no API record and no TrinityCore starter, so they would arrive pinless). Adds go through the cache or probe and a decisions file. Fix maintenance.md step 6, whose gap path needs a hand-made ID list that no tool writes. On Forever, the summary splits the 450 CMaNGOS-only repeatables from the 1,697 others and counts the QuestV2 rows never answered. | both | | medium |
| 38 | **Links stay hand-kept on retail.** A generator in Forever's shape reproduces only 90 of retail's 426 breadcrumb pairs from TrinityCore and the API. It would add 3,124 chain-closing pairs (about 1 in 4 is a re-offer, which would hide the lead-in) and 930 TrinityCore group pairs (against the 6 October decision, and mostly same-name or both-done). Every sourced link is already in the hand table and audited. Instead add, to both games' audits: a link pair against the prerequisites; a link-ticked quest that another quest requires (27 retail, 76 Forever; KEEP rows for the Arathi Basin brackets, AQ paths and the Ordo Warbringer branch); a prerequisite on a quest the API says must be incomplete (A Bee Test); a hand breadcrumb whose target differs from the breadcrumb's cache follow-up (8 retail, among them 11482 and 27919); and group classification. On Forever, put the 6 to 8 lead-in-shaped CMaNGOS groups (1282/1302, 1685/1715, 2378/2380, 5249/5250, 5142/5601, 8419/8420) first in the review queue, and keep the genuine choices. Triage the roughly 230 unsupported legacy retail pairs by kind: boards, other faction, same name, other. Where the cache names a common next quest, remodel boards with their sibling as breadcrumbs. | both | | small |
| 39 | **The chain-closing rule** (a lead-in closes once its follow-up is taken) runs only on Forever, on CMaNGOS's NextQuestInChain, and has never been tried in game. Don't port it to retail: 2,784 of its 3,124 candidates rest on a cache follow-up alone. One test in each game decides it. On Forever, take a follow-up with no prerequisite (a druid's Moonglade, 5921, without Heeding the Call) and see whether the lead-in is still offered. Until then, list Forever's 42 no-prerequisite lead-ins in the step-10 review. | both | | small |
| 40 | **One decision-file vocabulary.** Retail's quest-link-decisions.csv can only SET a prerequisite; give it REMOVE, so a wrong source-given prerequisite can be overruled (needed for the Dragonflight renown rows if they are disproved; D1 is fixed through breadcrumb rows instead). Forever's can't say a breadcrumb closes only once done; add that only if a warrior lead-in turns out to be offered while its target is in the log. Use one parser for both tools. Move retail's category script rules (`$zoneTextRules`, `$namePrefixRules`) into a `quest-category-decisions.csv` modelled on quest-profession-decisions.csv, once the placer has its sort rule. | both | | small |
| 41 | **Generated where it's free:** retail's `qcFactions` from the client's Faction table (with the standing table, which adds factions); retail's reputation into `data\reputation.jsonl`, if the Forever cross-check shares the reader; the storyline choice rule and its internal-name filter in the shared `QuestLines.ps1`, once Forever's QuestLine table grows. Keep retail's menu hand-kept (row 29), but add a membership check: every category with quests has an entry, and no entry is empty. | both | | small each |

### 8. Write down the source order, and keep the builds straight

| # | What | Games | Effort |
|---|---|---|---|
| 42 | Adopt the [source order table](#source-order-by-field) below: copy it into game-parity.md, make each tool follow it, and have each tool report where a lower source contradicts a higher one (Forever's importer already does for some fields). | both | small |
| 43 | **Retail's tools pick their build as Forever's do.** Read the build from the installed client's `.build.info` or `Get-LatestBuilds.ps1`, not a hard-coded 12.1.0.69933. Read only `<table>-<build>.csv` (PlayerCondition, among others, has no build in its name). Print the build each tool read. Copy every `questcache.wdb` with a timestamp before reading it: the 12 October cache behind #320 and step 2g can't be reread. Rename the mislabelled `retail_quest_cache_...from-probe-cache-2026-10-09.jsonl` (its content is 8 October's). Print the API namespace build in the 2b and 2c summaries. This matters for the 12.1.5 sweep (13 or 14 October): today some tools would move to the new build and others silently stay on 69933. | retail | small |

### Most valuable first

1. D1 and D2 (the #320 board gates and link contradictions) and D3 (Adventurer). These are small fixes to data that is wrong in release 113.0.
2. Recommendation 10 with D6, D7 and D13: one follow-up rule for both games, and the Forever and retail link fixes it implies.
3. Recommendations 1 to 4: the game as the checker (snapshot, recorder fields, marks that heal themselves, the probe-facts check), with D5.
4. Recommendation 31 with D10, then 29: retail pin identity and positions.
5. Recommendation 37 (missing quests), starting with the Midnight Candy Buckets before Hallow's End.
6. Recommendations 24 and 17 (standing from the API and CMaNGOS, renown from the client's conditions): the largest groups of quests shown to characters who can't take them.
7. Recommendation 8 (CMaNGOS's updates) before Forever's launch on 4 November.
8. Recommendations 7, 12, 13 and 33: the cross-checks that keep each of these from coming back, with baselines.
9. Recommendation 43, before the 12.1.5 sweep.
10. Everything else, in the order of the themes.

## Source order by field

Today's order is read from the code. The proposed default is the user's rule: first the game's own answer and
the client's tables, then Blizzard's web API, then the emulator, then legacy data, with hand decisions as
reviewed overrides. One refinement came out of the checking: a source that *states* a requirement (CMaNGOS's
RequiredClasses or RequiredSkill, the API's requirements) outranks one that only *files* the quest (a quest log
heading). That is why Forever's class and profession stay emulator-first for now, with a review row on any
disagreement. Each exception gives its reason as in game-parity.md: nature, API, data or process.

| Field | Retail today | Forever today | Proposed for both |
|---|---|---|---|
| Which quests exist | legacy data, plus quests pins name (from a hand-made list), plus the client's task table | every quest the game answers (QuestV2 and CMaNGOS, asked by the probe), plus CMaNGOS-only quests the beta hasn't reached | the game's answer and the client's tables, then the API, then the emulator; a missing-quest report in both (rec 37); adds and removals reviewed |
| Name (fallback; shown live anyway) | API, else legacy | cache, else CMaNGOS | game (cache, probe), then API, then task title, then emulator (D16) |
| Type and recurrence | probe classification, API flags, absence from QuestV2 (one-way retypes) | the server's flags, then CMaNGOS's SpecialFlags | the server's flags and the probe in both, the API as a check (rec 12); for "repeatable", retail's API flag with TrinityCore and QuestV2 as weaker votes, and the offer's flag as the tiebreaker in both |
| Faction and race | API (step 1), client votes (1b), legacy data | cache, then CMaNGOS's faction where the record lists no races; no review rows | game record, then client conditions and items, then API; the emulator a value only on Forever (era-matched), and on retail a report-only vote that changes data only through a decision row; every disagreement a review row (step 1e in both) |
| Class | API (Adventurer bug, D3), client votes | hand, ItemSparse (no giver), CMaNGOS, class heading, the only prerequisite's class | retail: API and ItemSparse, then the class heading (fixes where nothing contradicts it), with TrinityCore's classes report-only; Forever: CMaNGOS above the heading, with a review row on disagreement; the chain rule a report on retail |
| Minimum level | API, else the ContentTuning formula on the cache's tuning | cache, else CMaNGOS | unchanged, plus the recorder's lowest offered level as the check in both (rec 2); TrinityCore's tuning a retail check only |
| Level used by the low-level filter | legacy floor | the game's level | retail: a scaling cap from ContentTuning, live `IsQuestTrivial` where loaded (rec 27) |
| Prerequisites | API; client task table and the current expansion's conditions; campaign order; cache follow-ups where TrinityCore agrees; TrinityCore's previous quest when it is the step just before; legacy data; hand SET last | hand; CMaNGOS's full model; cache follow-up (no filters); quest-line order | retail: Blizzard first (API, client conditions, cache follow-ups under one filter set, rec 10), then TrinityCore through one reader as decision 1 allows (rec 7, 9), legacy links listed; Forever: CMaNGOS first as kept on 11 October, the cache a filtered fallback, disagreements listed (rec 11), the cache winning only for another faction's quest (D7) or after a look in game (D9); in both, the game's offers and snapshots as the check (rec 1, 2) and hand SET and REMOVE |
| Only while another is in the log | none | CMaNGOS's negative links | emulator in both (rec 7); never PlayerCondition's CurrQuestID |
| Breadcrumbs, "only one of these" | hand, audited against the API and TrinityCore | CMaNGOS, the chain rule, hand ADD/REMOVE | as today, with the same consistency checks in both (rec 38) and the game's offers as the check |
| Reputation rewards | API; the cache a report-only check | cache, unchecked | retail as today (Forever has no API, so this is nature); Forever checked against CMaNGOS (rec 15); observed gains from the recorder in both (rec 2) |
| Renown | hand (96) | – (nature) | client conditions generated; hand rows checked (rec 17) |
| Standing | none | none | API (retail), CMaNGOS (Forever), TrinityCore as a check; by rank (rec 24) |
| Holiday | hand, audited | hand, CMaNGOS events, the game's heading, CMaNGOS's heading, the spawn rule | hand, Blizzard's heading (API, cache), emulator events; achievements and spawns as support only (rec 20) |
| Profession | task table, headings, knowledge rewards, hand | CMaNGOS's RequiredSkill, then the game's heading | add the emulator's RequiredSkill and start items to retail; reward skill a check only; heading disagreements reviewed on Forever (rec 23) |
| Skill level | none | CMaNGOS | retail from the task table and TrinityCore, converted, after the check (rec 28); Forever checked against TrinityCore |
| Covenant | legacy data | – (nature) | the client's conditions as the check (rec 21) |
| Category | legacy data, the placer (API area), script rules | the game's sort, then CMaNGOS, hand zone list | the game's sort in both: through the placer and an audit with exceptions on retail (rec 19); hand rules in a decisions file (rec 40) |
| Storyline | QuestLineXQuest, chapter-first, internal names filtered | QuestLineXQuest, last row wins | one shared rule; the game's runtime quest line as the check (rec 4) |
| Pin position | client 32, then -1, then TrinityCore 32 (unpinned quests only), the giver table, legacy pins; the recorder fills blanks | the recorder, CMaNGOS spawns, client start points (no giver) | the client's start point and the game's offers where they exist, then the emulator's start and spawns; legacy pins kept, and listed where no source supports them (rec 29, 30, 33) |
| Pin identity | legacy (borrowed), client giver table, TrinityCore starter (named pins), hand; the recorder fills blanks | the recorder, CMaNGOS starters, hand; names from the probe | client giver table and recorder, then the emulator's starter at the spot; legacy identities kept unless contradicted (the 99 the spawns contradict reviewed, blank or KEEP; the other unconfirmed ones baselined and left for the recorder); nameless rather than a wrong name (rec 31, 36) |
| Pin icon | legacy codes | computed from the quests | computed in both (rec 32) |
| Availability | reviewed flags from evidence | refused or internal quests left out | one evidence method (server flags, refusals with faction, QuestV2 and PTR, API) in both; Forever's after launch (rec 13, game-parity recommendation 10) |

## Decisions for the user

Each is a question with a recommendation. The rows above that only add a check or a report are not
listed: they follow the user's "check everything every sweep" rule.

1. **TrinityCore previous quests on retail** (rec 9, reopening quest-table-checks.md decision 3 of
   6 October): take the condition links (83 quests, 0 of 44 parts disproved) and the negative-group links
   (69 quests; 12 of 151 parts disproved, all from 9365 A Thief's Reward, which would need a decision row)
   now, and the 795 previous-quest-only ones as a review list with the three new filters? *Recommended: yes
   to the first two, the review list for the third.*
2. **Older expansions' client conditions** (rec 18, extending the 12 October current-expansion rule): apply
   the 18 gates that name only our quests (640 quests)? *Recommended: yes, after one look at a skip route
   (Chromie Time or Threads of Fate), since a wrong gate hides a whole campaign.*
3. **Forever's own-breadcrumb links** (D6, reopening the 11 October "not changed" on 24 of them): drop the 15
   zone links, which no report settles but whose six similar neighbours first-hand reports disproved? And the
   11 class lead-ins (9 on the same list; 1882 and 1884 in the open mage question): drop them too, or keep them
   until each is seen in game? Class lead-ins have twice proved required (2205 to 2206, 2218 to 2238).
   *Recommended: drop the 15 zone links; keep the class links and list them.*
4. **Recurrence** (rec 12, open-items row 16): start with the 116 quests where the server and the API agree,
   plus the 38 task quests? *Recommended: yes.*
5. **Standing requirements** (rec 24): build them, minimum gates first? *Recommended: yes.*
6. **The TrinityCore pass's holds** (rec 30): place holiday, seasonal and profession quests (337) together
   with object spawns for the 258 Candy Buckets? *Recommended: yes, all at once.*
7. **Nameless pins per quest or per spot** (open-items row 7, game-parity recommendation 11): per spot on
   retail would remove 1,672 of its 5,159 nameless pins. *Still the user's call.*
8. **Category names:** rename Mac'Aree, Time Rift and Weekly Events to Blizzard's "Eredath",
   "Time Rifts" and "Weekly Event", so the client names them in every language? *Recommended: yes ("match
   Blizzard exactly").*
9. **Echo Isles** (map 463): its entry switches a new troll to a four-quest Battle for Azeroth category while
   their 57 starter quests sit in Durotar. Re-point it to Durotar, as decision 2 did for the other starter
   maps, or file the 57 under Echo Isles, as Blizzard's sort does? *The user's call.*
10. **Heading policy between the games** (AQ War Effort, Winter Veil, Midsummer, Invasion: about 60 quests
    filed differently): take it up with decision 30 after Forever's launch. *Recommended: wait.*
11. **The recorder's holiday mask** (rec 2e): its decision 2 keeps nothing identifying and no time, and a "holidays running" mask is
    coarse time of play. *The user's call; the profession and covenant masks don't need it.*
12. **The retail probe's quest list** (rec 5, revisiting 9 October): add the missing-quest candidates (560 to
    700, about a minute of asking), not all of QuestV2? *Recommended: yes.*
13. **Pin eligibility by quest kind instead of menu category** (rec 34): *recommended: not now*; keep the
    11-12 October per-category decisions.
14. **Where `server_completed_kranaa.txt` came from** (30 September): a server list, filtered? *A line in
    the docs, so it can be cited.*

## In game: the few lines this review needs

Only what no offline check can show. Each is one look, on whichever game it names, when convenient. Nothing
else in this review waits on them.

- **Both games:** a quest the character did in a past holiday (a Lunar Festival elder, say): does
  `IsQuestFlaggedCompleted` read false now? (D5)
- **Forever:**
  - A level 7+ Alliance character who never took 954: does Asterion offer 955 Bashal'Aran? (D8)
  - After handing in 937: is 940 Teldrassil offered before 98398 The Oracle Tree is done? (D9)
  - A level-60 character at a battlemaster: is only the 51-60 bracket quest offered? (rec 25)
  - A druid who takes Moonglade (5921) without Heeding the Call: is the lead-in still offered? (rec 39)
- **Retail:**
  - The 12.1.5 probe run (already planned), on a Horde character if possible (rec 5, rec 27).
  - A character with the renown but not 72039: is 70809 offered? (rec 1's renown rows)
  - At Exalted with Frostwolf or Stormpike, is The Eye of Command offered; at Best Friend, is a Tillers gift
    quest? (rec 24, before maximum gates)
  - A character 2 levels under a quest with an offset: is it offered? Or let recorder levels settle it.
    (rec 26)
  - The profession skill-rank check already agreed in open-items ("Which API reads an expansion's
    profession skill"), before any retail skill levels (rec 28).
- **Only when its recommendation is built:**
  - a quest with a reputation cap, at and above the cap, plus one friendship faction (rec 14);
  - that "Starts from" names the item once the item has loaded (rec 16);
  - a warrior lead-in with its target in the log, before Forever's decision file learns "closed once done"
    (rec 40).

## Checks to add to the sweep

| Check | Step | Games | Baseline (12 October 2026) |
|---|---|---|---|
| Completion snapshot against prerequisites and in-log links | 2b, 10 | both | new |
| Probe facts against the cache (faction, level, title, group size) | 2e, 10 | both | 0 differences |
| Breadcrumb flag on a quest another quest requires | 2e, 10 | both | 1 (Forever 955) |
| Emulator requirement against the cache follow-up; new-quest sources | 2c, 10 | both | Forever 5 + 7 |
| Link pair against prerequisites; link-ticked required quest; must-be-incomplete prerequisite; breadcrumb target against the cache | 2b, 10 | both | 27 retail, 76 Forever ticks; 8 breadcrumb targets |
| TrinityCore columns (races, classes, skill, standing, groups, conditions, previous quests, tuning, pools) | 2b | retail | report only |
| TrinityCore against CMaNGOS (links, skills, holidays) | 10 | Forever | 4 breadcrumbs; 3 skills; 276 holidays agree |
| CMaNGOS updates since the dump, touching imported quests | 10 | Forever | 355 scripts |
| Server flags against our recurrence | 3, 10 | both | 185 retail |
| Deprecated and tracking flags; sure sign for API-served quests | 7 | both | 42 + 4; 87 |
| Rewards against CMaNGOS | 10 | Forever | the seven classes of rec 15 |
| Unsupported profession and holiday tags | 1d, 2d | retail | 83 and 11 |
| Unsupported faction and class restrictions (step 1e) | 1 | both | 56 recent + 1,660 older faction tags; 195 class (retail) |
| Pin-source agreement; kept legacy pins | 6, 10 | both | 23,087 of 23,092; 96.2%; 99.2% |
| Pin identity review lists | 6c | retail | 99 NPC pins (90 borrowed); 96 TrinityCore pairs; 133 on NPC pins; 372 nameable |
| Map pass against pins and against restrictions | 2c, 6 (the pass itself: In the game, 3b) | both | 254 / 1 / 4; 2 restriction fixes |
| Missing quests | 6 | both | ~560 retail |
| Category against the game's sort, with exceptions | 5 | retail | ~10 clear misfiles |
| Unrouted zone maps | 5 | retail | 5 clear |
| Pin icons against the rule | 9 | both | ~1,960 retail |
| Storyline and campaign against the game's runtime answer | 4 | both | 559 differ |
| Builds read by each tool | all | both | — |

## Stale text found

The checking pass confirmed about 90 statements in the docs and tool headers that are out of date or
contradicted by the code. game-parity.md's rows are corrected in this pull request; open-items.md gets a
pointer here. The rest are listed for the pull request that touches each file, under the "keep docs current"
rule. Line numbers are master's (f3e3a4f); this pull request moves open-items.md's down by 7.

- **maintenance.md:**
  - line 368 says step 1b reads the start points; it reads point -1;
  - lines 991-997 give 97.9% storyline agreement; it is 96.7% today;
  - line 1020's examples are stale: Bfa Unknown (1150) is gone, and Garrison Support is now named from the
    client (QuestSort 403);
  - line 1060's "a pin goes where its quest starts" doesn't hold for TrinityCore-only quests (rec 29);
  - lines 1621-1633: "Pins follow the same rule as retail's", and Forever's pinless counts (1,424 now);
  - lines 1655-1657: a breadcrumb ADD row's quests also hide while the target is in the log;
  - lines 1679-1682: the class order is CMaNGOS before the heading;
  - line 1858: "no tool writes" holiday tags, but `Add-TaskQuests.ps1` does (game-parity.md's row is
    corrected in this pull request);
  - lines 2191 and 2323-2325: the retail probe has run, and the retail cache is read (step 2e);
  - lines 2553-2561, the data-sources table: CollectableSourceQuestSparse; `Apply-ClientQuestGivers.ps1`;
    CMaNGOS's holidays, professions, skills, conditions and in-log links; the unapplied updates; retail's
    use of QuestFactionReward and of the cache.
- **retail-quest-cache.md:**
  - line 19 and `Read-QuestCache.ps1:16` call quest type 1 "disabled";
  - line 202 says ItemSparse isn't in `tools\` (retail's is);
  - lines 296-301 hold an old count (98 is now 80 by a strict modal, 132 by a looser one);
  - lines 9-41 don't mention the description givers, AreaGroupID or the other dropped fields;
  - lines 135-137 should cite TrinityCore's AllowedMinOffset;
  - nothing yet says that PortraitGiverName is the kill target, not the giver.
- **quest-table-checks.md:**
  - lines 22-24 say the client has no renown requirements (it has, rec 17);
  - lines 164-168 (Paladin Rescue, D4).
- **client-tables-review.md:**
  - lines 98-99 (PlayerCondition carries renown and friendship conditions);
  - line 122 (RenownRewards has 3 of our quests);
  - line 137 (AreaGroupMember is quest data through AreaGroupID).
- **game-api-review.md:**
  - lines 452-455 and 811 still call `IsBreadcrumbQuest` untested. It answers true for 4 retail and 2 Forever
    quests and names no target, so it can't fill a breadcrumb table, but a true answer is a signal worth
    checking (D8);
  - lines 530-531 have no standing row;
  - recommendation 2 is done.
- **forever.md:**
  - lines 103-105 reject QuestieDB as a check, though it was used by hand;
  - lines 171-173 on `IsRepeatableQuest` (70338 loaded 98 CMaNGOS repeatables, all false);
  - lines 512-515 hold old reward counts (2,333 rewards on 1,855 quests; 1,008 waiting);
  - line 1321 counts TrinityCore's in-log links as 26 (the conditions add about 77 quests).
- **open-items.md:**
  - line 32's "502 gate on their own level" is harmless (a step 2g rerun changes nothing; noted there in this
    pull request);
  - lines 392 (2,802, not 2,766), 415-417 (1,424 pinless) and 420-422 (32 and 47);
  - lines 279-305 should note TrinityCore's cumulative skill scale;
  - lines 428-434: update 4645 is evidence for 769.
- **quest-types.md:** lines 149-152 say "still open: nothing", but row 16 is open.
- **unavailable-quests.md:** lines 64-73 (the sure sign is counted only for API 404s).
- **quest-reputation-data.md:** lines 146-148 (the task table's faction columns are all 0).
- **Tool headers:**
  - `Assemble-PinDB.ps1:5` says 3 points, but the code uses 1.5;
  - `Get-WagoQuestRequirements.ps1:11-13` (point -1);
  - `Insert-GapQuestEntries.ps1:56-58` (the Adventurer comment; `Audit-QuestAccuracy.ps1:58` is D3's code,
    not stale text);
  - `QuestConditions.ps1`:
    - lines 11-12: the addon does check renown;
    - lines 17-20: only 52 of the older gates name hidden quests;
  - `Compare-QuestCache.ps1:22-23` and line 204 (TrinityCore's RewardNextQuest and the probe's group size
    exist);
  - `Import-ForeverData.ps1`:
    - line 34 (closing wording);
    - line 79 (race 0 wording);
    - lines 87-97 (the profession order and the spawn rule's share).
- **Data files:**
  - unavailable-quest-decisions.csv rows 55686, 55687, 55712, 55713, 61161 (evidence text);
  - forever-quest-table-decisions.csv rows 2-3 (D7);
  - the gitignored `client-giver-report.txt` and `pin-npc-id-report.txt` predate the 11-12 October pins.

## Status

- 2026-10-12: review written (ten areas, two checking passes, a completeness critic, and a final check of this
  document against the evidence); no data, addon or tool change. game-parity.md's rows corrected and open-items.md pointed here, in the same pull request. Nothing
  decided yet.
- 2026-10-13: D1, D2, D3 and D13 fixed (the PR after #324, retail only). 28 breadcrumb rows were added or extended for the board and lead-in quests, and 28 quests lost a prerequisite on them; 28504 left the Thousand Needles group, the Gilneas trio and the three 10562/10595/25428 pairs are no longer exclusive; 85249 needs 85082 only (a decision row); Resolve-Bitmask skips Adventurer and Traveler, 21 class fixes applied and 175 KEEP rows added (44920 Order of Incantations is left for the user: ours 2093, the API 4095); `qcFormerlyExclusive` seeded with 10 quests. Step 2c now leaves a quest out when the cache names more lead-ins than TrinityCore repeats (14 listed, their existing prerequisites untouched: 12468, 26682 and 12 others need a look).

- 2026-10-13: D7, D18 and D19 fixed (Forever; its own pull request). 26/27 swap givers by a REMOVE/ADD decision, 28/29 take the other quest's prerequisite, creature_spawn_entry is read (7281 and 7302 pinned), and a spawn in several holidays' events counts for none. 4736/4737, 4967/4968 and 8228/8229 are still for the user.

- 2026-10-13: recommendation 37 started: `Find-MissingQuests.ps1` (report only, both games) and its decisions and baseline files (555 retail and 130 Forever candidates); the importer's summary splits CMaNGOS-only quests into repeatable and other (481 and 1,666) and counts QuestV2 rows never answered (3,700). Nothing added to the data yet: the Midnight Candy Buckets and the other live-looking holiday quests wait for the user's OK.

- 2026-10-13: the 15 Midnight Candy Buckets (97142-97213) are in the data, on the user's word (PR after #327); retail has 35,544 quests. The older buckets and the Ahune, Headless Horseman and gift quests are still undecided. The step-6 rules ask for a retail quest-type probe after quests are added (maintenance.md): the buckets are one-time holiday quests like the 265 already there.

## Appendix: every finding and its verdict

Area, the finding as first raised, the games, the checked verdict and the value. Findings raised by the
checking pass carry "(new)"; duplicates name the finding they were merged into.

| Area | Finding | Games | Verdict | Value |
|---|---|---|---|---|
| Prerequisites | Retail reads TrinityCore's quest links far more narrowly than Forever reads CMaNGOS's | retail | confirmed, corrected | medium |
| Prerequisites | TrinityCore and CMaNGOS combine PrevQuestID and NextQuestID differently, so one reader needs a semantics switch | both | confirmed, corrected | low |
| Prerequisites | Retail's qcQuestNeedsInLog is empty though TrinityCore and the client name 131 quests offered only while another is in the log | retail | confirmed, corrected | low |
| Prerequisites | Forever's importer drops CMaNGOS 'quest taken' conditions instead of turning them into needsInLog | forever | confirmed | low |
| Prerequisites | Forever's cache follow-up rule makes a quest require its own breadcrumb (the defect retail fixed in #322) | forever | confirmed, corrected | high |
| Prerequisites | The two games take the quest cache's follow-ups under different rules; a measured shared rule | both | confirmed, corrected | medium |
| Prerequisites | Older expansions' quest-line and campaign conditions are dropped wholesale, though those naming our own quests hold perfectly | retail | confirmed, corrected | medium |
| Prerequisites | Task quests' PlayerCondition ModifierTrees are skipped, though line conditions read the same trees | retail | confirmed | low |
| Prerequisites | The client's CampaignXCondition (chapter gates) is read by no tool | retail | confirmed | low |
| Prerequisites | Where the API speaks, the immediate predecessor that TrinityCore and the cache agree on is dropped, so quests open one step early | retail | confirmed | low |
| Prerequisites | One API requirement tree without an operator is skipped by both 2b and 2c | retail | confirmed | low |
| Prerequisites | API requirement trees come from a cache that is never refreshed (build 68914) | retail | refuted | low |
| Prerequisites | No sweep checks prerequisites against what real characters completed; the probe could snapshot GetAllCompletedQuestIDs in both games | both | confirmed | high |
| Prerequisites | 4,322 retail prerequisite links rest only on legacy data or storyline order and are never cross-checked; Dragonflight's renown lines fail most | retail | confirmed, corrected | medium |
| Prerequisites | 9 of the 19 testable Dragonflight renown decision rows (quest-link-decisions.csv) are disproved by a real character | retail | confirmed | medium |
| Prerequisites | Forever's Trial of the Lake prereqs name the other faction's quest; Blizzard's own cache gives the right one | forever | confirmed, corrected | low |
| Prerequisites | Neither game lists where its emulator's requirement and the quest cache's follow-up disagree | both | confirmed, corrected | medium |
| Prerequisites | Forever turns follow-ups into closing lead-ins (SatisfyQuestNextChain); retail ignores the same rule in TrinityCore | both | merged into "The NextQuestInChain closing rule runs only on Forever, on CMaNGOS's field instead of Blizzard's, and has never been tried in game" | medium |
| Prerequisites | The recorder sees every offer but not whether the offered quest's prerequisites were met | both | confirmed | high |
| Prerequisites | The map pass drops 'offered together' prereqs by heuristic; a completion snapshot would make it exact | both | confirmed | medium |
| Prerequisites | Retail's link decisions can only SET a prereq; Forever's can SET and REMOVE | both | confirmed | low |
| Prerequisites | QuestieDB's first-hand corrections are cited by hand but not used as a sweep cross-check for Forever | forever | confirmed | low |
| Prerequisites | Read-QuestCache.ps1 skips the conditional descriptions' quest-giver creature IDs (both games) | both | merged into "The reader skips the quest-giver creature IDs in both caches' conditional descriptions" | low |
| Links | Retail's breadcrumb and exclusive tables are 2018/109.97 hand data, while Forever's are generated each import | both | confirmed | medium |
| Links | The NextQuestInChain closing rule runs only on Forever, on CMaNGOS's field instead of Blizzard's, and has never been tried in game | both | confirmed, corrected | medium |
| Links | Forever makes a quest's CMaNGOS breadcrumb its prerequisite; retail's step 2c skips breadcrumbs | forever | merged into "Forever's cache follow-up rule makes a quest require its own breadcrumb (the defect retail fixed in #322)" | high |
| Links | Forever takes every CMaNGOS exclusive group while retail takes none of TrinityCore's, though both show the same false-group problem | both | confirmed, corrected | medium |
| Links | Forever's links are never checked against TrinityCore in a sweep, though TrinityCore has rows for nearly all vanilla quests | forever | confirmed | medium |
| Links | Retail's qcFormerlyExclusive is empty though the 6 October fixes left 10 in-data quests with stale link ticks | retail | confirmed, corrected | low |
| Links | Some link pairs contradict our own prerequisites, and step 2b checks this against the API only | both | confirmed, corrected | high |
| Links | Hand breadcrumb targets are never compared with the breadcrumb's own follow-up from Blizzard's quest cache | both | confirmed | medium |
| Links | The game's IsBreadcrumbQuest was probed on both games and is no breadcrumb source, and no flag bit is either; the result was never recorded | both | confirmed | low |
| Links | The game's own offers could verify every link live on both games, but nothing compares them | both | confirmed | high |
| Links | 995 Forever quests that CMaNGOS lacks have no breadcrumb, exclusive or in-log data at all | forever | confirmed, corrected | low |
| Links | Neither game reads the emulators' closing or in-log quest conditions into links | both | confirmed, corrected | low |
| Links | Forever's links tick 21 yearly holiday quests, and the addon never clears those ticks | forever | confirmed, corrected | medium |
| Links | Forever's decision file can't mark a breadcrumb 'closed only once done', so its 15 hand lead-ins hide while the target is merely in the log | forever | confirmed | low |
| Links | Retail's daily-limit groups ignore TrinityCore's quest pools: Horde and Darnassus cities are missing, and two pools are merged | retail | confirmed, corrected | low |
| Links | Retail models breadcrumb boards as symmetric exclusive pairs, so handing in a board ticks the zone quest it leads to | retail | confirmed, corrected | low |
| Pin positions | Retail: legacy pins of the 6,612 TC-only quests are never moved to or checked against TrinityCore's start point | retail | confirmed, corrected | high |
| Pin positions | Retail TC pass holds holiday, seasonal and profession quests that Forever pins from the same kind of source | retail | confirmed, corrected | medium |
| Pin positions | Retail TC pass holds recurring quests for not being in QuestV2, which never lists repeatables | retail | confirmed, corrected | low |
| Pin positions | Retail never places a pinless quest at its emulator starter's spawn; Forever's main source is exactly that | retail | confirmed, corrected | low |
| Pin positions | Item-started quests: neither game uses emulator loot sources; Forever's 200 stay pinless and retail's 70 item-named pins are legacy | both | confirmed, corrected | low |
| Pin positions | Both games pin a quest with no point 32 at its point -1, the hand-in for most quests | both | confirmed, corrected | low |
| Pin positions | Retail object-started quests: 151 nameless pins and 40 unpinned board quests that TrinityCore's object spawns could place and name | retail | confirmed, corrected | medium |
| Pin positions | Nameless pins: per quest on retail, per spot on Forever (new retail numbers for row 7) | both | confirmed | low |
| Pin positions | The recorder's precedence differs: it never moves a retail pin, but replaces all of a Forever giver's spawns | both | merged into "The recorder outranks CMaNGOS on Forever but only fills blanks on retail" | low |
| Pin positions | No sweep check records how far the pin sources agree, on either game | both | confirmed, corrected | high |
| Pin positions | The map pass is compared with the pins by hand only, and neighbour-map offers read as mismatches | both | confirmed | medium |
| Pin positions | Runtime: the addon's recorder could note the game's map offers (quest, map, x, y) on both games | both | confirmed | low |
| Pin positions | Start blobs' PlayerConditionID is dropped: condition-split starts show to every character | both | confirmed | low |
| Pin positions | Legacy pins are kept as values on retail but only as hints on Forever | both | confirmed | low |
| Pin positions | Forever's importer ignores CMaNGOS creature_spawn_entry, so 2 Alterac Valley quests lose their givers' spawns | forever | confirmed | low |
| Pin positions | Smaller pin rules that differ by process | both | confirmed, corrected | low |
| Pin positions | Forever: 140 quests whose givers stand only inside instances have no pin; retail pins such quests on dungeon maps | forever | confirmed | low |
| Pin positions | Forever: 11 quests have client start points but aren't imported (refused by the beta) | forever | confirmed, corrected | low |
| Givers | Retail never revisits a nameless pin: 372 sit at a TrinityCore starter of their quest | retail | confirmed, corrected | high |
| Givers | Apply-ClientQuestGivers never fills a nameless pin of a quest that has any NPC pin | retail | confirmed | medium |
| Givers | Retail never names object-started pins from TrinityCore; Forever names all of them from CMaNGOS (recommendation 12, now 151 pins) | retail | merged into "Retail object-started quests: 151 nameless pins and 40 unpinned board quests that TrinityCore's object spawns could place and name" | medium |
| Givers | ItemSparse.StartQuestID is read in both games but only for class; build 'Starts from' once for both, named live by C_Item | both | confirmed, corrected | high |
| Givers | 134 retail quests that start from an item or object sit on NPC pins, so the tooltip names an NPC as giver | retail | confirmed, corrected | medium |
| Givers | Retail counts TrinityCore's contradictions of pin NPCs but never lists them (113 pairs, 34 at the turn-in NPC) | retail | confirmed, corrected | low |
| Givers | The recorder outranks CMaNGOS on Forever but only fills blanks on retail | both | confirmed, corrected | low |
| Givers | About 2,950 retail nameless pins have no static source; only the retail recorder can name them, and it has never run | retail | confirmed, corrected | medium |
| Givers | The retail probe asks only pin NPCs; Forever's also asks the emulator's givers, and Forever's names follow the game | retail | confirmed, corrected | low |
| Givers | No sweep reports how far TrinityCore's starters agree with the client's giver table | retail | confirmed, corrected | low |
| Givers | Forever's importer reads the client's ItemSparse item starts and CMaNGOS's but never compares them, and uses CMaNGOS's for its labels | forever | confirmed | low |
| Givers | Object-named pins show English in every locale in both games; TrinityCore holds localized object names | both | confirmed | low |
| Givers | The quest cache's PortraitGiverName, dropped by the reader, is not a giver source (checked so no one repeats it) | both | confirmed | low |
| Givers | creaturecache.wdb is copied for Forever only and read by no tool | both | confirmed | low |
| Reputation | Reputation standing requirements are read in neither game: 513 retail and 215 Forever quests show as takeable to characters who can't take them | both | confirmed, corrected | high |
| Reputation | The client's own conditions give renown requirements for 48 retail quests the hand table lacks; QuestConditions.ps1 walks those trees and skips them | retail | confirmed, corrected | medium |
| Reputation | RenownRewards (Name, Level, track) names renown levels for Dragonflight/TWW/Manaforge reward quests; 36 are already written in the reviewed link evidence but not in qcRenownLevelRequirements | retail | confirmed, corrected | low |
| Reputation | Rewards: retail takes the API first and keeps the cache as a report-only check (2,085 quests waiting); Forever takes the cache unchecked. Same reader, opposite precedence | both | confirmed, corrected | low |
| Reputation | Forever's rewards are never compared with CMaNGOS (or anything) during a sweep; retail has a three-way comparison with a baseline | forever | confirmed, corrected | medium |
| Reputation | TrinityCore's rewards (100% agreement with Blizzard's where both exist) would cover 685 retail quests that neither the API nor the cache covers | retail | confirmed, corrected | low |
| Reputation | 1,008 Forever quests have CMaNGOS rewards and no answer from the game; CMaNGOS's step maps onto the game's table with 97.6% agreement | forever | confirmed, corrected | low |
| Reputation | Retail holds back cache rewards on hidden factions (class F); Forever's importer takes them | both | confirmed, corrected | low |
| Reputation | Each reward's rank cap (RewardFactionCapIn) is in both caches and dropped by the reader; 99 retail and 6 Forever tooltip quests show reputation the game stops giving at Friendly or Honored | both | confirmed, corrected | low |
| Reputation | Neither the recorder nor the probe captures reputation gained at hand-in, or standing/renown at an offer; both clients have the functions, and that is the in-game check row 15 and Forever's step table need | both | confirmed, corrected | high |
| Reputation | The 96 hand-kept renown rows have no source and no level check; an offer seen at a lower renown is the only evidence that could disprove one | retail | confirmed, corrected | low |
| Reputation | Retail's qcFactions is hand-kept; Forever's is generated from the client's Faction table | both | confirmed | low |
| Reputation | Retail's reputation lives in a hand Lua table edited by a tool; Forever's lives in data/forever/reputation.jsonl and is built | both | confirmed | low |
| Restrictions and levels | Step 1 and gap-insert read any API class list naming 'Adventurer' as all classes, leaving 21 class quests open to everyone | retail | confirmed, corrected | high |
| Restrictions and levels | Retail never reads TrinityCore's AllowableRaces, while Forever uses its emulator's RequiredRaces as a value source | both | confirmed | medium |
| Restrictions and levels | 23 retail quests are open to every class although TrinityCore restricts them and the API record is silent | retail | confirmed | medium |
| Restrictions and levels | Step 2g has no source for about 463 retail quests, while TrinityCore's ContentTuningID covers 341 of them | retail | confirmed, corrected | low |
| Restrictions and levels | Forever takes CMaNGOS's faction for 1,336 quests the game allows to every race, with no review row; retail has no equivalent rule or check | both | confirmed, corrected | medium |
| Restrictions and levels | For shared quest IDs, retail's Blizzard API names one faction for 58 quests Forever shows to both (16 visible: Alterac Valley and Barrens) | both | confirmed, corrected | medium |
| Restrictions and levels | Retail ignores the class QuestSort heading that Forever uses as a class source | retail | confirmed | low |
| Restrictions and levels | 189 retail class restrictions rest on no source; the audit records them, but Categorize discards every one | retail | confirmed, corrected | medium |
| Restrictions and levels | Forever narrows class down only-prerequisite chains; ported to retail, the rule would misfire on most of 85 quests because of single-class prerequisites | both | confirmed, corrected | medium |
| Restrictions and levels | TrinityCore lets quests be taken AllowedMinOffset levels early; 2,824 retail gates may be 1-4 levels too high | retail | confirmed | high |
| Restrictions and levels | No maximum-level gate: 76 Forever battleground bracket quests show to every character above their bracket | both | confirmed | medium |
| Restrictions and levels | Forever's minLevel/level come from the game else CMaNGOS with no comparison or baseline; retail has Compare-QuestLevels | forever | confirmed | medium |
| Restrictions and levels | The game tells us the level a quest is offered at, but the recorder doesn't keep it and the probe reader drops it | both | confirmed, corrected | high |
| Restrictions and levels | Map-pass offers contradict our faction/class masks for 4 retail quests; 2 (90548, 90550) are wrong in our data | both | confirmed, corrected | medium |
| Restrictions and levels | Step 1b reads PlayerConditions on turn-in POIs (ObjectiveIndex -1) instead of start points (32) | retail | confirmed, corrected | low |
| Restrictions and levels | Step 1b's output predates its own ItemSparse source; its build and table files aren't resolved to the latest | retail | merged into "Stale PTR tables, unlabelled retail CSV builds, and a retail cache output its kept file can't reproduce" | low |
| Restrictions and levels | Neither game reads ItemSparse.AllowableRaces of quest-starting items (both read AllowableClass) | both | confirmed | low |
| Restrictions and levels | The probe saves GetQuestFactionGroup for both games, but no tool reads it, and it duplicates the cache | both | merged into "The probe's facts pass is saved on both games and read by no tool; the game's faction contradicts ours on 30 quests" | low |
| Restrictions and levels | 20 Forever race-subset quests from CMaNGOS exclude Skyborne by construction, though the game adds Skyborne to many race-specific lists | forever | confirmed, corrected | low |
| Restrictions and levels | open-items.md's '502 of 506 task quests gate on their own level' is harmless: their level already equals the client formula | retail | confirmed | low |
| Inventory and types | Retail's probe never asks the server about quests our data lacks; Forever's probe asks about its whole client table | both | confirmed, corrected | medium |
| Inventory and types | No sweep step lists quests that QuestV2, the cache or TrinityCore know and retail's data lacks (93701 is one of about 560) | retail | confirmed, corrected | high |
| Inventory and types | The server's own Deprecated (0x4000) and Tracking (0x400) quest flags are in the cache, but no availability step reads them | both | confirmed | high |
| Inventory and types | Weaker availability signals are unused in both games: server questType 1, CMaNGOS Method 1 and TrinityCore's 'Deprecated quest' disables | both | confirmed, corrected | low |
| Inventory and types | Retail flags unavailable quests from reviewed decisions; Forever leaves them out instead and has no way to flag one | both | confirmed, corrected | medium |
| Inventory and types | Five FLAG rows rest on 'unknown to the server', which the newest probe and the cache contradict; retail keeps no answer memory | retail | confirmed | low |
| Inventory and types | Seven test or not-yet-implemented retail quests show with no decision; four tools use four different internal-name patterns | both | confirmed, corrected | medium |
| Inventory and types | Forever types recurrence from the server's flags; retail never compares its types with them (96.7% agree, 185 would change) | both | confirmed | high |
| Inventory and types | 86 retail world quests are typed one-time, though the probe's IsWorldQuest answer says they recur | retail | confirmed | medium |
| Inventory and types | 'Repeatable' comes from QuestV2 absence on retail and from the emulator's SpecialFlags on Forever; each game ignores the other source, and they disagree in both | both | confirmed, corrected | low |
| Inventory and types | Forever's importer ignores the probe's Recurring classification that retail's step 3 relies on | forever | confirmed | low |
| Inventory and types | The game's live answers on recurrence and on quests we lack are collected or available, but nothing reads them | both | confirmed, corrected | low |
| Inventory and types | Retail's names follow only the API; 38 quests the API lacks keep names that Blizzard's own cache, probe and task table contradict | retail | confirmed | low |
| Inventory and types | 2,147 Forever quests carry CMaNGOS's title and 450 are in the data on CMaNGOS's word alone, because the beta answers only to about level 35 | forever | confirmed, corrected | low |
| Inventory and types | Retail's inventory and availability tools default to build 12.1.0.69933 and check the PTR by hand; Forever's tools take the newest build | retail | merged into "Stale PTR tables, unlabelled retail CSV builds, and a retail cache output its kept file can't reproduce" | medium |
| Holidays, professions | Retail holiday tags are hand data with an audit while Forever's are generated; a Forever-shaped generator reproduces 1,295 of 1,304 retail tags | both | confirmed, corrected | medium |
| Holidays, professions | Blizzard's holiday achievements in the client tables back 721 tags and confirm 79 of the 150 tags no other source supports, yet no tool reads them | retail | confirmed, corrected | medium |
| Holidays, professions | Step 2d never reads the client's own heading (the quest cache's sort) or TrinityCore's sort, spawns and conditions; Forever's importer uses the client heading as a value source | retail | confirmed, corrected | medium |
| Holidays, professions | Forever's five holiday sources are combined by order with no disagreement report, and never compared with TrinityCore or retail's tags for the same quests | forever | confirmed, corrected | low |
| Holidays, professions | No check compares the two games' holiday, profession and skill data for quests both games have | both | confirmed | low |
| Holidays, professions | TrinityCore's RequiredSkillID is the retail twin of the CMaNGOS RequiredSkill that Forever relies on, but retail never reads it | retail | confirmed, corrected | medium |
| Holidays, professions | The quest cache's RewardSkillLineID is dropped by Read-QuestCache.ps1, and the API's rewards.skill isn't read; both name 11 untagged fishing quests | both | confirmed, corrected | low |
| Holidays, professions | Quests started by an item that needs a profession (ItemSparse StartQuestID + RequiredSkill) get no profession pass | both | confirmed | medium |
| Holidays, professions | Retail skill-requirement data: the real sizes, and a scale trap the parity plan doesn't record | both | confirmed, corrected | medium |
| Holidays, professions | Covenant tags are legacy data no tool writes or checks, yet the client reproduces all 777 and finds 7 more | retail | confirmed | low |
| Holidays, professions | 83 retail profession tags have no source at all, and step 1d never reports a tag no pass supports | retail | confirmed | medium |
| Holidays, professions | The probe keeps GetQuestTagInfo's tag but drops tradeskillLineID, and the game's 'Professions' tag (267) is unused | both | confirmed, corrected | low |
| Holidays, professions | The recorder could note the running holidays, the character's professions and its covenant when a quest is offered | both | confirmed, corrected | low |
| Holidays, professions | Forever derives type 64/32 from its holiday and profession tags; retail doesn't, so 581 holiday and 963 profession quests show the normal list icon | both | confirmed | low |
| Holidays, professions | Four retail quests need First Aid, which retail no longer has; the default profession filter always hides them | retail | confirmed | low |
| Holidays, professions | 147 holiday-linked quests in the client's QuestV2 are not in retail's data, and step 2d can't see them | retail | confirmed, corrected | medium |
| Holidays, professions | Three separate holiday name/ID resolvers, and Holidays ID 376 means different things to them | both | confirmed | low |
| Holidays, professions | Forever's profession takes CMaNGOS's RequiredSkill before the game's own heading, silently | forever | confirmed, corrected | low |
| Holidays, professions | Forever's skill levels (CMaNGOS) are never cross-checked; TrinityCore disagrees on 3 | forever | confirmed | low |
| Categories | Retail categories never take the game's own quest sort; Forever's do | both | confirmed, corrected | medium |
| Categories | 132 catch-all quests can be filed by the game's sort; the placer can't see them (API 'category' ignored, API missing for 26) | retail | confirmed, corrected | high |
| Categories | No sweep compares retail's category with the game's sort; about 50 quests look misfiled where the sort and every pin agree | retail | confirmed, corrected | high |
| Categories | Echo Isles map 463 sends trolls to a 4-quest BfA category while their 57 starter quests sit in Durotar; the starter-subzone rule is inconsistent | both | confirmed, corrected | low |
| Categories | Retail's zone table is hand-kept and leaves 98 pinned maps unrouted; Forever's is generated from the client and leaves none | both | confirmed, corrected | medium |
| Categories | The same Blizzard heading is filed differently in the two games (AQ War Effort, Winter Veil, Midsummer, Invasion) | both | confirmed, corrected | low |
| Categories | Retail's zone field is legacy free text with typos, yet it is a placement signal; Forever's is the client's name | retail | confirmed, corrected | low |
| Categories | Storylines come from one client table by two different rules | both | confirmed | low |
| Categories | No sweep compares storylines with the game's runtime quest line; 559 retail quests differ and get English names | both | confirmed | low |
| Categories | Runtime GetCampaignID answers for far fewer quests than the client's campaign tables list | retail | confirmed | low |
| Categories | The probe's C_TaskQuest.GetQuestZoneID answers are collected but not used | retail | confirmed, corrected | low |
| Categories | Retail category, zone and storyline tools hard-code build 12.1.0.69933 and read CSVs with no build in the name; Forever's tools work out the build | retail | merged into "Stale PTR tables, unlabelled retail CSV builds, and a retail cache output its kept file can't reproduce" | medium |
| Categories | Mac'Aree, Time Rift and Weekly Events don't match Blizzard's names, so they stay English | retail | confirmed, corrected | low |
| Categories | Forever quests with no usable sort go straight to Uncategorized, and 'REUSE ME' is one of them | forever | confirmed, corrected | low |
| Categories | Retail's hand placements live in script tables and direct edits; Forever's are a reviewed decisions CSV | both | confirmed, corrected | low |
| Categories | 42% of Forever's categories rest on CMaNGOS alone, and no second source is checked | forever | confirmed | low |
| Categories | Two menu builders: retail's menu is hand-kept, Forever's is generated | both | confirmed | low |
| Sources | Forever's CMaNGOS source skips 355 post-dump update scripts; wrong givers and prerequisites follow | forever | confirmed, corrected | high |
| Sources | Reputation standing requirements are in three sources and used by neither game | both | merged into "Reputation standing requirements are read in neither game: 513 retail and 215 Forever quests show as takeable to characters who can't take them" | high |
| Sources | Retail never pins from TrinityCore object spawns; Forever pins from CMaNGOS's | retail | merged into "Retail object-started quests: 151 nameless pins and 40 unpinned board quests that TrinityCore's object spawns could place and name" | medium |
| Sources | The same RewardNextQuest field closes lead-ins in Forever but only makes prerequisites on retail | both | merged into "The NextQuestInChain closing rule runs only on Forever, on CMaNGOS's field instead of Blizzard's, and has never been tried in game" | medium |
| Sources | Forever has no counterpart to retail's quest-cache tripwire; CMaNGOS could serve | forever | confirmed, corrected | medium |
| Sources | No sweep cross-checks Forever's CMaNGOS-derived links against TrinityCore | forever | merged into "Forever's links are never checked against TrinityCore in a sweep, though TrinityCore has rows for nearly all vanilla quests" | medium |
| Sources | The reader skips the quest-giver creature IDs in both caches' conditional descriptions | both | confirmed, corrected | low |
| Sources | Cache flags 0x4000 and 0x400 point at retired and hidden quests; step 7 ignores them | both | merged into "The server's own Deprecated (0x4000) and Tracking (0x400) quest flags are in the cache, but no availability step reads them" | high |
| Sources | The probe's facts pass is saved on both games and read by no tool; the game's faction contradicts ours on 30 quests | both | confirmed, corrected | medium |
| Sources | TrinityCore columns that CMaNGOS's equivalents feed in Forever are never read for retail | retail | confirmed, corrected | medium |
| Sources | Two Blizzard-side and emulator profession signals are unread in step 1d; TrinityCore has 677 skill requirements, not 78 | both | confirmed, corrected | medium |
| Sources | The quest record's AreaGroupID and the client's AreaGroupMember table give zones for uncategorized quests | retail | confirmed | low |
| Sources | TrinityCore's quest pools could feed and check the hand-kept 'only N of these' override tables | retail | merged into "Retail's daily-limit groups ignore TrinityCore's quest pools: Horde and Darnassus cities are missing, and two pools are merged" | low |
| Sources | The client's quest-line conditions are applied only for Midnight; 46 older lines name a quest we hold | retail | merged into "Older expansions' quest-line and campaign conditions are dropped wholesale, though those naming our own quests hold perfectly" | low |
| Sources | An unused runtime function could settle the reputation backfill in one probe pass | both | merged into "Neither the recorder nor the probe captures reputation gained at hand-in, or standing/renown at an offer; both clients have the functions, and that is the in-game check row 15 and Forever's step table need" | low |
| Sources | Forever imports cache reputation on hidden factions; retail's rule holds those out | forever | merged into "Retail holds back cache rewards on hidden factions (class F); Forever's importer takes them" | low |
| Sources | Stale PTR tables, unlabelled retail CSV builds, and a retail cache output its kept file can't reproduce | retail | confirmed, corrected | medium |
| Prerequisites | Task-quest CurrQuestID conditions mean 'not while that quest is in the log', the reverse of needsInLog (new) | retail | confirmed | low |
| Prerequisites | TrinityCore PrevQuestID candidates include breadcrumbs, board quests and later storyline steps (new) | retail | confirmed, corrected | high |
| Prerequisites | Forever inserted new quests into the Teldrassil chain; 940 still requires CMaNGOS's 937 (new) | forever | confirmed, corrected | low |
| Links | #320 follow-up prerequisites name one of two alternative lead-ins, and a hand exclusive link ticks that one away (new) | retail | confirmed, corrected | high |
| Links | Seasonal (type 64) completion marks never expire on either game (new) | both | confirmed, corrected | medium |
| Links | The Kranaa completion list used as link evidence has no documented provenance (new) | retail | confirmed, corrected | low |
| Pin positions, givers | Assemble-PinDB borrows a pin identity from another map, which can put an ender's name at a start (new) | retail | confirmed, corrected | medium |
| Pin positions, givers | Assemble-PinDB copies a quest's NPC identity across maps, so pins name NPCs who do not stand there (45174 on 12 class-hall maps named Allari) (new) | retail | merged into the finding above | medium |
| Reputation | PlayerCondition's own currency columns give client renown requirements the review missed: 21 task quests, 4 confirming hand rows, 4 of them Midnight (new) | retail | confirmed, corrected | medium |
| Reputation | The 'shown faction' test reads only ReputationFlags_0, but the Faction table's flags are per race group (new) | both | confirmed, corrected | low |
| Reputation | 647 quests in our data were asked by the 12.1.0 type probe, got no server record, and are API 404s (new) | retail | refuted | low |
| Reputation | API standing-requirement maxima need rank-based comparison or an in-game check before they gate anything (new) | retail | confirmed, corrected | medium |
| Restrictions and levels | Paladin Rescue storyline (5908) carries alternating faction tags that no Blizzard source asserts (new) | retail | confirmed, corrected | medium |
| Restrictions and levels | Fixing the Adventurer reader also surfaces 59 DK-start and class-hall MANUAL rows (new) | retail | confirmed, corrected | low |
| Restrictions and levels | Porting Forever's class-chain rule unchanged to retail would throw on 38 links (new) | retail | confirmed, corrected | low |
| Inventory and types | The probe's per-quest 'repeatable' fact is always false on both games (new) | both | already done | low |
| Inventory and types | Probe refusals may depend partly on the character's faction (new) | retail | confirmed, corrected | medium |
| Inventory and types | Most of the 42 undecided 'deprecated'-flagged retail quests have a live twin and no API record (new) | retail | confirmed, corrected | medium |
| Holidays, categories | The holiday spawn rule keeps only the last event of a spawn that belongs to several events (new) | both | confirmed | low |
| Holidays, categories | Profession reward signals are not requirements: 48883 and 61545 (new) | retail | confirmed | medium |
| Holidays, categories | A quest's category silently decides whether tools may give it new pins (new) | retail | confirmed, corrected | low |
| Holidays, categories | Some Uncategorized task quests can't be placed by any planned rule (new) | retail | confirmed, corrected | low |
| Sources | The game flags Forever 954 Bashal'Aran as a breadcrumb, but our data makes 955 require it (new) | forever | confirmed, corrected | low |
| Sources | Forever pins put 'A Lesson to Learn' on the other faction's druid trainer (new) | forever | confirmed, corrected | medium |
| Sources | Retail completion-log conditional entries name the turn-in or meet NPC for 51 quests (new) | retail | confirmed, corrected | low |
| Completeness critic | Retail's quest 'level' (list bracket, level sort, low-level filter) has no Blizzard source and was reviewed by no area; the game's own scaled level is already saved and unread (new) | both | confirmed, corrected | medium |
| Completeness critic | Retail pin icons are legacy codes the current code reinterprets: item-started quests draw the weekly icon, dungeon dailies the profession icon; Forever computes icons from quest data (new) | both | confirmed, corrected | medium |
| Completeness critic | No per-field source precedence is written down for either game, and the implemented orders differ between the games and from the user's 'game and client first' rule (new) | both | confirmed, corrected | medium |
