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
  also gets the zone and minimum level of the new quests. Races, flags and objectives are probably in
  there too, still to be decoded. `creaturecache.wdb` does the same for NPCs.
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
  only its own files, and one ZIP, tag and release cover both.
- **Data:** `data/forever/quests.jsonl` and `pins.jsonl`, built into `QuestCompletist/Forever/` by
  the existing build tools (`-DataDir`, `-AddonDir`).
- **Menus and categories:** Forever's own. That means the Eastern Kingdoms and Kalimdor zones, the
  new zones, dungeons, raids, and the class, profession and holiday headings.
- **Code:** the same files. Retail-only features (covenants, renown, the warband, world quests) never
  come up in Forever's data. Check each feature on the Forever client before release.
- **CurseForge:** Thalid83's Classic files are on the same project, so talk to them before the first
  Forever file goes up.

## Phases (one PR each)

1. **Beta probe and recorder** (probe branch, not merged): a small addon with a `_Camelot` TOC, run
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

## Decisions

1. **A longer-term project** (2026-10-04): the retail plan comes first.
2. **Our own database, not a dependency on QuestieDB** (2026-10-05).
3. **Start on the beta** (2026-10-05): the probe and recorder run there before launch, and again on
   the live game.

## Open questions

- The TOC suffix and interface number at launch.
- What else the quest cache holds, and whether the beta server answers for every quest.
- Whether Thalid83 plans a Forever version, and whether their Classic data can be compared.

## Status

- 2026-10-04 and 05: researched and planned. Nothing built.
