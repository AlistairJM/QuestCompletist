# WoW: Forever version

## Goal

A version of the addon for WoW: Forever, running alongside retail: one folder, one release, and our
own Forever quest and pin database. It's a longer-term project, and the retail plan comes first.
Nothing is built yet.

## What Forever is (checked October 2026)

- **Blizzard's "Classic+".** It launches on 4 November 2026; the beta opened on 17 September. It has
  the original continents up to level 60, plus new zones (Mount Hyjal, the Riverglades and others),
  quests, dungeons and raids, and a new race, the Skyborne. It's meant to be permanent.
- **The client is version 1.60.1** (beta build 70205). It's the wago.tools product
  `wow_classic_beta` and the Gethe/wow-ui-source branch `forever`, and it installs as
  `_classic_beta_` beside `_retail_`.
- **It runs retail's interface code.** All 29 `C_` functions the addon calls are in its API
  documentation, which is retail's plus extras (6,306 functions against retail's 6,048).
- **TOC:** interface 16001, and the file suffix `_Camelot`, which only Forever recognises.
  [warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/TOC_format) says the suffix may change before
  launch.

## What the client's own tables hold (build 70205)

- **Which quests exist:** `QuestV2` lists 6,609 quest IDs. 4,805 are also in Classic Era (1.15.9).
  1,804 are new, 1,720 of them numbered 90000 and up.
- **Maps:** Classic Era's map IDs (947 and 1411–1464), plus six new ones: 2482 Mount Hyjal, 2521
  and 2665 Zephras Isle, 2524 Darkspear Islands, 2548 Riverglades and 2652 Shen'dralas.
  `UiMapAssignment` converts world coordinates to map positions, and our pin tool's formula works
  with it (see the check against our old pins below).
- **Names of zones and headings:** `AreaTable` (1,371 areas) and `QuestSort` (class, profession and
  holiday headings, with three new ones: The High Order, Camping and Night Elf).
- **Not there:** quest names, levels, quest givers and requirements, which come from the server. The
  data retail's start points and storylines are built from is nearly empty: `QuestPOIBlob` has 54
  rows (23 start points) and `QuestLine` has 3.

Our retail database doesn't help much: it has only 555 of the 4,805 old quests, because Cataclysm
replaced most of them.

## Sources

### CMaNGOS's vanilla database: the old world

[cmangos/classic-db](https://github.com/cmangos/classic-db) is a vanilla (1.12) world database,
still maintained (last change 22 September 2026). Measured against its full dump,
`Full_DB/ClassicDB_1_12_1_z2815.sql.gz`:
- **3,532 of the 4,805 old quests**, each with its level, minimum level, races, classes, zone,
  prerequisites, mutually exclusive group and breadcrumb.
- **Quest givers:** 3,186 of them have an NPC giver, 3,147 with a spawn point (3,093 with exactly
  one). Another 179 start from an object.
- **Licence:** GPL-3.0, the same as ours, so we can import it with credit. Its `COPYRIGHT.md` says
  the game content in it (names and quest texts) is Blizzard's. We take names and facts, never the
  quest texts.
- **The 1,273 old IDs it lacks** aren't in QuestieDB either. They're probably hidden tracking
  quests, and the probe's names will tell.

### Our old Classic pins: a second opinion

Before #89, `qcPinDB.lua` held 1,310 pins on Classic Era maps 1411–1459, all with NPC IDs,
covering 3,071 of the old quests (`git show a9bc11c^:QuestCompletist/qcPinDB.lua`). Checked against
CMaNGOS:
- **Givers:** the same NPC for 3,436 of their 3,794 quests (90.6%), and a different NPC for 83.
- **Positions:** converted with Forever's map data, CMaNGOS's spawn of the same NPC is within 1 map
  point of 1,014 pins, and within 3 points of 89 more. 185 are further away.

The disagreements are a review list for the importer.

### The game: a probe on the beta now, and again at launch

- **The probe** asks the server about all 6,609 quests, as #99, #42 and #112 did on retail:
  `RequestLoadQuestByID`, then `GetTitleForQuestID`, `GetQuestDifficultyLevel`, `GetQuestTagInfo`,
  `IsEliteQuest`, `IsRepeatableQuest` and `GetSuggestedGroupSize`. A second pass asks for the NPCs
  CMaNGOS names as givers, as #112 did, to check they exist in Forever.
- **Saved variables work on the beta.** On build 70205 the Wowhead Looter addon writes its file (4
  October). Questie's maintainer reported in September that they didn't; that's been fixed.
- **The quest cache holds more than the functions return.** The client keeps the server's record of
  every quest it asks about in `Cache\WDB\enUS\questcache.wdb`. Quest 2561's record gives level 10,
  minimum level 3 and area 141 (Teldrassil), as CMaNGOS does, plus its title and texts. So the probe
  also gets the zone and minimum level of the new quests. What else it holds, and what it doesn't, is
  in the phase 1 results below. `creaturecache.wdb` does the same for NPCs.
- **Beta data can change.** The run at launch is the one that counts, and comparing it with the beta
  run shows what changed.
- **English is enough** for the database. Quest and NPC names show in the player's language from the
  game, as on retail.

### Quest givers for the new content

Neither CMaNGOS nor QuestieDB has these: each has only 3 of the 1,804 new quests.
- **Record while playing.** A recorder saves the giver's NPC or object ID, the map and position, and
  the quest log heading, each time a quest is offered or accepted. You send in the file, and a tool
  merges it. It can run on the beta too.
- **Wowhead** has a Forever section, for lookups by hand as on retail.

### Not used

- **QuestieDB**, Questie's database addon. It has no licence file, and we want our own database
  rather than a dependency (decision 2 below). Its Forever quest list is the same as CMaNGOS's (4,244
  shared IDs), so it adds little as a cross-check either.
- **Blizzard's web API** has no Forever data.

## Addon design

- **One folder, two TOCs.** A second TOC, `QuestCompletist_Camelot.toc` (interface 16001 for now),
  loads the shared code plus Forever's data files. The retail TOC stays as it is. Each game loads
  only its own files, and one ZIP, tag and release cover both. Forever reads a `_Camelot` TOC
  (phase 1 results).
- **Data:** `data/forever/quests.jsonl` and `pins.jsonl`, built into `QuestCompletist/Forever/` by
  the existing build tools (`-DataDir`, `-AddonDir`).
- **Menus and categories:** Forever's own. That means the Eastern Kingdoms and Kalimdor zones, the
  new zones, dungeons, raids, and the class, profession and holiday headings.
- **Code:** the same files. Retail-only features (covenants, renown, the warband, world quests) never
  come up in Forever's data. Check each feature on the Forever client before release.
- **CurseForge:** Thalid83's Classic files are on the same project, so talk to them before the first
  Forever file goes up.

## Phases (one PR each)

1. **Beta probe and recorder** (#139, probe branch, not merged): a small addon with a `_Camelot` TOC, run
   in `_classic_beta_`. It does the quest pass and the NPC pass, and records while you play. The
   results, and copies of `questcache.wdb` and `creaturecache.wdb`, go into `tools/` (gitignored).
2. **Cache reader** (tool): decodes the cache records, checked against CMaNGOS for the quests both
   have.
3. **CMaNGOS importer** (tool): turns the dump into `data/forever`, with spawns converted to map
   positions. It merges the probe, cache and recorder results, and lists every disagreement for
   review, including the 83 givers and 185 positions above.
4. **Forever TOC, menus and build** (addon), tested on the beta.
5. **At launch:** rerun the probe on the live build, compare, and release.
6. **After launch:** keep recording the new content's givers, and look up the rest on Wowhead.

### Phase 1 results (5 October 2026, beta build 70205, enUS)

Run on an Alliance Night Elf rogue, level 12. The probe's saved variables and both caches are in
`tools/forever_probe_70205/` in the main checkout (not in git).

- **TOC and load test.** Forever read `QCForeverProbe_Camelot.toc`, so the `_Camelot` suffix works.
  Of the per-file conditions, `camelot` and `mainline` match Forever, and `standard`, `classic` and
  `vanilla` are recognised and don't match. `forever` isn't recognised, so `[AllowLoadGameType
  forever]` loads, as QuestieDB found. Whether retail recognises `camelot` is untested, so two TOCs
  stay the safe design.
- **The beta only answers quests up to about level 40.** All 6,609 quests took 9½ minutes at 4 in
  flight: 2,860 answered (63 were already in the cache) and 3,749 failed. Failures follow the quest's
  level: 0–4% up to level 35, rising from 36 to 45, and nearly all from level 46. Zones, dungeons and
  raids for level 45 and up failed almost entirely. It isn't faction or class. Horde-only quests
  answered about as often as Alliance-only ones (60% against 66%), and other classes' quests about as
  often as everyone's. Rerun the probe when the beta opens higher levels; a plain rerun asks again
  about everything that hasn't answered.
- **849 of the 1,804 new quests answered**, such as "Camping 101: Cooking", "Trouble in the Valley"
  and the dungeon quest "Horrors in the Highland".
- **CMaNGOS agrees.** Of the 1,811 quests both have, levels match for 1,795. Titles match for 1,783.
  The other 28 are Blizzard's capitalisation and wording (`WANTED: "Hogger"`, "Look to the Stars"),
  and Blizzard's version wins. 201 of the 1,273 old IDs CMaNGOS lacks answered, all internal:
  "<UNUSED>", "<TXT>", "<NYI>" and test quests.
- **Tags and recurrence:** 129 dungeon, 115 elite, 17 PvP and 6 raid quests. The quest classification
  calls 171 quests Recurring, while `IsRepeatableQuest` said no to every quest.
- **All 1,460 NPCs were named**, 113 at once and the rest on the 1-second re-check, in under 6
  minutes. No `TOOLTIP_DATA_UPDATE` named one. 1,458 names match CMaNGOS, and Forever renamed two:
  8479 Kalaran Windblade is now Velarok Windblade, and 10776 Finkle Einhorn is Pip Quickwit.
- **The quest cache** (2,860 records) holds the server's quest record, laid out as TrinityCore's
  `QueryQuestInfoResponse`. Against CMaNGOS, the zone (the int32 at byte 24) matches for 1,802 of
  1,811 quests, the level (byte 8) for 1,795 and the minimum level (byte 16) for 1,743. It also has
  the follow-up quest, the starting item, reputation rewards, objectives and texts.
  - The race mask (bytes 440–447) is −1, meaning no restriction, for 2,040 quests; a faction quest's
    faction comes from its giver. It's an Alliance or Horde race set for 526 quests, and a single race
    for the starting quests.
  - The quest-giver field is empty in every record, so givers come from CMaNGOS, the recorder and
    Wowhead.
- **The recorder** saved 9 givers in Darkshore (8 NPCs and a wanted poster), 10 offers, and 10
  accepted quests with their quest log headings ("Darkshore", and "Cooking" for a cooking quest). For
  all 8 NPCs, CMaNGOS's spawn converted with Forever's map data is within 0.04–0.14 map points of
  where you stood, and so are our old pins.

## Decisions

1. **A longer-term project** (2026-10-04): the retail plan comes first.
2. **Our own database, not a dependency on QuestieDB** (2026-10-05).
3. **Start on the beta** (2026-10-05): the probe and recorder run there before launch, and again on
   the live game.

## Open questions

- The interface number at launch, and whether the `_Camelot` suffix stays.
- Whether retail recognises the `camelot` token. That only matters for a one-TOC layout.
- Which race each bit of the race mask is, from Forever's `ChrRaces` (for the cache reader).
- Whether Thalid83 plans a Forever version, and whether their Classic data can be compared.

## Status

- 2026-10-04 and 05: researched and planned.
- 2026-10-05: phase 1's probe (#139) ran on the beta; results above. Next: rerun it when the beta
  opens levels above 40, then phase 2.
