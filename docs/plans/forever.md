# WoW: Forever version

## Goal

A version of the addon for WoW: Forever, running alongside retail: one folder, one release, and our
own Forever quest and pin database. It's a longer-term project, and the retail plan comes first.
Phases 1 to 4 are done: the addon runs on the Forever beta with its own data, every release since
111.1 carries Forever's files, and the full sweep refreshes that data along with retail's
([maintenance.md](../maintenance.md), step 10).

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

- **Which quests the game records as completed:** `QuestV2` lists 6,609 quest IDs. 4,805 are also
  in Classic Era (1.15.9). 1,804 are new, 1,720 of them numbered 90000 and up. It isn't a list of
  every quest: it leaves out repeatable ones (see "Repeatable quests" below).
- **Maps:** Classic Era's map IDs (947 and 1411–1464), plus six new ones: 2482 Mount Hyjal, 2521
  and 2665 Zephras Isle, 2524 Darkspear Islands, 2548 Riverglades and 2652 Shen'dralas.
  `UiMapAssignment` converts world coordinates to map positions, and our pin tool's formula works
  with it (see the check against our old pins below).
- **Names of zones and headings:** `AreaTable` (1,371 areas) and `QuestSort` (class, profession and
  holiday headings, with three new ones: The High Order, Camping and Night Elf).
- **Not there:** quest names, levels, quest givers and requirements, which come from the server. The
  data retail's start points and storylines are built from is nearly empty: `QuestPOIBlob` has 54
  rows (23 start points) and `QuestLine` has 3. The importer uses the start points even so (see
  "Start points" below).

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

- **The probe** asks the server about every quest in `QuestV2` and every CMaNGOS quest it lacks
  (7,319 on build 70205), as #99, #42 and #112 did on retail:
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
  `Build-AddonData.ps1`, which builds both games. `links.jsonl` and `reputation.jsonl` go into
  Forever's `qcQuest.lua` through `Build-ForeverMenu.ps1`.
- **Menus and categories:** Forever's own, generated by `Build-ForeverMenu.ps1`. That means the
  Eastern Kingdoms and Kalimdor zones, the new zones, dungeons, raids, and the class, profession and
  holiday headings.
- **Code:** the same files. Retail-only features (covenants, renown, the warband, world quests) never
  come up in Forever's data. Check each feature on the Forever client before release.
- **CurseForge:** Thalid83's Classic files are on the same project. Release 111.1 (5 October 2026)
  was the first with Forever's files, uploaded for both Retail and Forever (1.60.1); it's still
  worth talking to them (see the open questions).

## Phases (one PR each)

1. **Beta probe and recorder** (#139, probe branch, not merged): a small addon with a `_Camelot` TOC, run
   in `_classic_beta_`. It does the quest pass and the NPC pass, and records while you play. The
   results, and copies of `questcache.wdb` and `creaturecache.wdb`, go into `tools/` (gitignored).
2. **Cache reader** (tool, `tools/Read-ForeverQuestCache.ps1`, #141): decodes the cache records, checked
   against CMaNGOS for the quests both have.
3. **CMaNGOS importer** (tool, `tools/Import-ForeverData.ps1`, #142): turns the dump into
   `data/forever`, with spawns converted to map positions. It merges the probe, cache and recorder results, and lists every disagreement for
   review, including the 83 givers and 185 positions above.
4. **Forever TOC, menus and build** (addon), tested on the beta.
5. **At launch:** rerun the probe on the live build (a full sweep's step 10), compare, and release
   the update. Releases have carried Forever's beta data since 111.1. Also check for Blizzard data
   the beta didn't have, and take it over CMaNGOS's wherever it appears:
   - a Forever namespace in Blizzard's web API, which retail's reputation rewards, requirements and
     names come from;
   - client tables that gain quest data, as `QuestPOIBlob` holds start points. On retail, no client
     table holds a quest's reputation, breadcrumbs or "only one of these" groups (checked 29
     September 2026); the server sends reputation in each quest's record, which the probe reads.
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
  calls 171 quests Recurring, while `IsRepeatableQuest` said no to every quest. That proves nothing:
  the run asked only about quests in `QuestV2`, which leaves out repeatable ones, and on retail
  `IsRepeatableQuest` also said no to all 386 loaded quests Blizzard's API flags repeatable.
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

### Phase 2: the cache reader (5 October 2026)

`tools/Read-ForeverQuestCache.ps1` reads `questcache.wdb` into
`tools/forever_quest_cache_<build>.jsonl`, one quest per line:
- **Always:** id, title, level, minLevel and sort (the zone, or a negative QuestSort for class,
  profession and holiday quests).
- **Where they apply:** questInfo, groupSize, recurs, nextQuest, startItem, flags, reputation (each
  faction with its amount, since 6 October), and races with their faction.

It reads every record to its last byte, or writes nothing. On the beta cache (2,860 quests, under 2
seconds):
- **Every record reads exactly, and every title matches the game's.** It stops without writing on a
  changed objective count, text length or record length, a cache from another build, or a creature
  cache. A rerun gives the same file byte for byte.
- **Recurrence:** the daily (0x1000) and weekly (0x8000) flags pick out exactly the 171 quests the
  game calls Recurring.
- **Races** decode with Forever's `ChrRaces`:
  - Bits 0–7 are the original eight races, and bits 32 and 33 the Alliance and Horde Skyborne (races
    95 and 96). The races playable in Forever carry the flag 0x400000.
  - 404 quests are Alliance-only, 404 Horde-only, and 12 are for both Skyborne.
  - The other 2,040 leave it to the giver, including 1,172 that CMaNGOS gives one faction.
- **Against CMaNGOS** (1,811 quests): the starting item matches for all 500 that have one, and the
  faction for all 129 both give. The zone matches for 1,802, the level for 1,795, the minimum level
  for 1,743, and the follow-up quest for 746 of 795. The differences are Blizzard's, such as a cooking
  quest filed under Cooking, or Forever's new follow-ups such as 98298 after quest 99.

### Phase 3: the importer (5 October 2026)

`tools/Import-ForeverData.ps1` builds `data/forever/quests.jsonl` and `pins.jsonl` from four sources:
the client's `QuestV2`, the quest cache file, CMaNGOS's dump and the probe's saved variables. It
downloads the dump and any client tables it lacks.
- **The game wins wherever it speaks.** Title, level, zone, recurrence and race restrictions come
  from the cache, and recorded spots and NPC names from the probe.
- **The files use retail's fields and conventions** (see the tool's header), so the existing build
  turns them into Lua. Tried into a scratch folder, it wrote a 267 KB `qcQuestData.lua` and an 87 KB
  `qcPinDB.lua`, both passing `luac -p`.

From the beta's data (9 seconds, with the same files on a rerun):
- **4,506 quests:** 1,810 from the game and CMaNGOS, 972 from the game only (mostly Forever's new
  quests), and 1,724 from CMaNGOS only, which the beta doesn't serve yet. 78 with internal or test
  titles were left out.
- **1,541 pins on 48 maps**, 151 of them objects such as wanted posters. The recorder's spots and
  givers count: the "WANTED: Murkdeep!" poster also offers Forever's new quest 98025.
- **Category** is Blizzard's own: the zone's AreaTable ID, or the negative QuestSort ID for class,
  profession and holiday quests and Forever's own headings (Camping, The High Order, Nightmare
  Incursions). Phase 4's menu is built on these.
- **Seasonal quests** get their holiday from CMaNGOS's events, which carry Blizzard's holiday IDs, or
  from their heading. That gives 146 seasonal quests, 137 of them with a holiday. (Since 6 October,
  also from the events all their givers stand during: see "Event quests" below.)
- **Skyborne** has no race bit in the addon yet. The data uses 67108864, and phase 4 adds it to
  `qcRaceBits`.

Its review list, `tools/forever_import_review.csv` (3,307 rows), holds:
- **Not yet confirmed:** 1,674 quests the game hasn't confirmed yet, and 50 that failed on the beta
  below level 36 (perhaps not in Forever).
- **No known giver:** 1,137 quests. 971 are quests only the game knows, 123 start from an item, and
  CMaNGOS gives no giver for 43.
- **No pin:** 110 more quests whose givers aren't on a Forever map, being inside dungeons or summoned.
- **Disagreements:** 80 old pins naming another giver, 167 more than 3 map points from it, 9 zones
  Blizzard changed, and the 2 renamed NPCs.

### Phase 4: the addon on Forever (5 October 2026)

- **`QuestCompletist_Camelot.toc`** loads the shared code (the localization files, `qcCore.lua`
  and the XML) with Forever's own files from `QuestCompletist\Forever\`. Those are `qcMenu.lua`,
  `qcPinDB.lua`, `qcQuest.lua`, `qcQuestData.lua` and `qcUnavailableQuests.lua`.
  - Retail's TOC and files are unchanged.
  - It leaves out `qcCompletedQuests`, the old completions format, since Forever has no old data to
    convert.
- **`tools\Build-ForeverMenu.ps1`** writes Forever's menu and category tables from the data and the
  client's tables:
  - **Continents:** the Kalimdor and Eastern Kingdoms zones by retail's regions, and Zephras Isle.
  - **Dungeons and raids,** by their instance's type.
  - **Classes, battlegrounds, professions, world events** and Forever's other headings.
  - **Names:** the menu's names come from the client in the player's language (areas, classes,
    professions), with English as the fallback.
  - **Storylines** come from `QuestLine`. Breadcrumbs, mutually exclusive quests and reputation
    rewards were left empty; they came on 6 October (see below).
  - **The new zones:** Riverglades lies east of Burning Steppes and Redridge, so it's with the
    southern Eastern Kingdoms zones.
- **`tools\Build-AddonData.ps1`** builds both games, and `-Check` checks both. Each Lua file's
  header names its data folder.
- **`qcCore.lua`** gains the Skyborne race bit, 67108864.
- **`Test-QuestReachability.lua`** takes a TOC and a UiMap table. On Forever's files, every quest is
  reachable from the menu and every pin is drawn, on a map the client has, with no Lua errors.
  Retail's report is unchanged.
- **Import changes:** `Import-ForeverData.ps1` now files 297 quests under a whole zone or instance,
  so the menu has neither one-quest subzones nor two entries for one instance.
  - **Subzones go under their zone,** as retail's categories are zones: Valley of Trials under
    Durotar, Northshire Valley under Elwynn Forest, Booty Bay under Stranglethorn Vale.
  - **Outdoor areas named after an instance go under the instance's own area:** Gnomeregan in Dun
    Morogh, Zul'Gurub in Stranglethorn, and the Alterac Valley subzone. Zones with a map of their own
    are left alone, since Forever also has a dungeon called Deadwind Pass. Areas inside an instance
    stay in it: Sunken Temple's map names the outdoor temple as its area.
  - **Quests in a zone the client's AreaTable lacks go under Uncategorized.** Two quests are affected,
    both in area 16550.
- **The beta test:** the beta's `Interface\AddOns\QuestCompletist` is a link to the repository's
  folder, like retail's, so both games run the branch checked out (maintenance.md, "One-time
  setup").

### Pins on the right map (5 October 2026)

The beta test found Felwood and Winterspring quest givers drawn at the edge of the Mount Hyjal map.
- **The cause:** a CMaNGOS spawn is a position in the world, and the importer placed it on the
  smallest UiMapAssignment frame that held it. Frames are rectangles that overlap their neighbours,
  so 276 pins were on the wrong map. Forever's new Mount Hyjal frame overlaps parts of Felwood and
  Winterspring, and among old zones:
  - Auberdine was on Felwood, Darkshire on Deadwind Pass;
  - the Crossroads and Ratchet were on Durotar;
  - Brill and the Bulwark were on Western Plaguelands, Southshore on Alterac Mountains.
- **The fix:** the importer now tries, in order, the frames that hold the spawn:
  1. the map our old Classic pin had for the NPC;
  2. a city;
  3. the zone the giver's quests are in;
  4. the smallest.
  It only uses maps Classic Era already had, so a vanilla NPC is never put in one of Forever's new
  zones.
- **How the order was chosen:** on 884 NPCs whose spawn several frames hold, the old pins' maps
  served as the answer key.
  - The smallest frame matched them for 73%, the quests' zone for 89%, and a city first, then the
    quests' zone, for 90%.
  - In the cases checked, the old pins were right where the rules weren't. Givers whose quests are
    filed under a neighbouring zone are the misses: Tirion Fordring, the Bulwark's NPCs, Cairne
    Bloodhoof.
  - So the old pins come first, and the rules only decide for NPCs without one.
  - The rules changed again after the probe rerun: see "Three importer fixes" below.
- **New zones get pins only from the recorder** (or a lookup). CMaNGOS's NPCs are vanilla, and the
  quest cache names no quest giver. Mount Hyjal has no quests yet: the beta answered none filed
  there. Riverglades has one, "Remember That I Love You", started by an item, so it has no giver.

### Start points, and watching for more client data (5 October 2026)

Zephras Isle's 112 quests had no pins, which raised the question of whether a sweep would notice
if Blizzard filled in more of the client's data. It downloads every table for each new build, but
the importer didn't read all the ones that could place a quest:
- **Start points** (`QuestPOIBlob` and `QuestPOIPoint`, the tables retail's pins come from): 23 of
  them, for 22 quests.
  - 11 of those quests are ours: new quests in Westfall, Stormwind and Elwynn Forest with no known
    giver, such as "Testing the Wells" and "Murloc Gills".
  - They now have 4 pins at those points, with no giver named, as the tables don't say who stands
    there.
  - The other 11, in Tanaris and Mount Hyjal, aren't in our data yet: the beta hasn't answered
    them.
  - A quest that has a giver's pin keeps it. A start point more than 3 map points from its pins
    goes on the review list.
- **The quest-giver field** of the game's quest records is empty in all 2,860. The cache reader now
  keeps it, and the importer counts the quests that have it and lists them for review.
- **The record's map point** is set for 21 old quests, and marks where the quest is handed in. For
  "The Defias Brotherhood" (quest 65) it's exactly where CMaNGOS has the hand-in NPC in Lakeshire.
  It doesn't say where a quest starts, so it isn't used.
- **The recorder's notes:** a sweep now copies the probe's saved variables every time, not only
  after a probe run, as the recorder adds to them whenever you play.

The importer's summary prints the start point and giver counts, so a sweep shows when either grows.

### Repeatable quests (5 October 2026)

The importer took only the CMaNGOS quests `QuestV2` lists, and the probe asked only about those. But
`QuestV2` isn't a list of every quest:
- **It lists the quests the game records as completed.** Each row's `UniqueBitFlag` is the quest's
  bit in the character's record of completed quests. Dailies and weeklies are there, as they stay
  completed until the reset. A repeatable quest is never recorded as completed, so it has no row.
- **On retail** (12.1.0.69933), none of the 500 quests Blizzard's API flags repeatable is in it,
  against 98% of all its other quests (29,004 of 29,568), dailies and weeklies included.
- **On Forever**, 39 of CMaNGOS's 612 repeatable quests are in it, against 3,496 of its 3,633
  others. So 573 repeatable quests were missing from our data: Argent Dawn and Cenarion Circle
  turn-ins, the Darkmoon Faire's, the mount exchanges, the shaman's Saptas, "Apprentice Angler".
- **137 more CMaNGOS quests it lacks** aren't repeatable in CMaNGOS, but most look repeatable in
  Blizzard's data: 72 Naxxramas tier 3 turn-ins, Lunar Festival and Hallow's End turn-ins, Ahn'Qiraj
  War signets and battleground mark turn-ins. Retail's API calls 3 of the Lunar Festival ones
  repeatable. Some may be IDs Forever doesn't use.

What changed (user's decision, 5 October 2026):
- **The importer keeps CMaNGOS's repeatable quests** without `QuestV2`. Any other CMaNGOS quest it
  lacks comes in once the game answers for it, as every quest in the cache does. Each kept quest
  `QuestV2` lacks goes on the review list as "not in the client's QuestV2".
- **The probe asks about all 710** (#139): 7,319 quests and 1,550 NPCs on build 70205. 65 of the 573
  and 19 of the 137 are level 1 to 35, which the beta answers now. Most of the rest are level 46 to
  60.
- **A repeatable profession quest is repeatable** (type 2) with its profession set, as on retail,
  not a profession quest (type 32), which would keep a tick after one turn-in. That's 18 of the 573,
  such as "Membership Card Renewal" and the Felwood salves, plus Goblin Engineering and "Enchanted
  Thorium Platemail: Volume III". A pin takes the profession icon when every quest on it has a
  profession, as retail's pin tool does, so Riggle Bassbait's pin ("Master Angler", weekly) shows
  fishing's.

The result: **5,079 quests** (573 more) and **1,725 pins** (180 more, and 111 existing pins with new
quests). Darkmoon Faire gets its first quests, its 40 turn-ins, and Reputation (the Commendation
Signets) and Treasure Map are new headings. 79 of the new quests have no pin, as their givers stand
inside instances (48 in Ahn'Qiraj), and 101 have no known giver (71 start from an item). The review
list has 4,650 rows.

The probe can't say whether a quest repeats: on retail, `IsRepeatableQuest` said no to all 386 loaded
quests the API flags repeatable. So a quest's type comes from CMaNGOS. The recorder notes whether a
giver offers a quest as repeatable, though the importer doesn't read that yet.

### Probe rerun (5 October 2026, evening, build 70205)

The rerun asked about 4,459 quests in 6½ minutes: the 3,749 that failed the first time, and the 710
new IDs. 138 answered (6 already in the cache) and 4,321 failed. The NPC pass named the 90 new NPCs.
- **The beta hasn't opened more.** Only 21 of the 3,749 earlier failures answered.
- **117 of the 710 new IDs answered:** 94 of the 573 repeatable quests and 23 of the 137 others. At
  levels 1 to 35, 54 of 84 answered. The cut-off isn't strictly by level: all 32 Commendation Signet
  quests and some Darkmoon Faire turn-ins answered at level 60.
- **Failures that say something:**
  - The 14 mount exchanges (7660–7678, level 1) fail, although the beta answers level 1 quests.
    Forever probably doesn't have them.
  - Every battleground quest fails, the ones in `QuestV2` included, so the battlegrounds seem to be
    closed on the beta.
  - The Scourge Invasion turn-ins and "Apprentice Angler" fail. They're event quests, perhaps only
    served while their event runs.
- **The recorder** gave Zephras Isle its first pins: 7 givers for 10 quests, such as Rorian the
  Dayseeker and Elatrell Featherlight.

Step 10 then gave **5,109 quests** (30 more) and **1,739 pins** (14 more):
- **New quests:** 23 of the 137, now that the server answers them, such as Paladin, Shaman and
  Darkmoon Faire quests, the Ahn'Qiraj War signets and the battleground "Past Victories"; and 7 of
  Forever's new quests, such as "Conflict at Darkspear Islands".
- **The server's answers replace CMaNGOS's** for the quests it now knows: titles ("Thunderbrew Lager"
  is "Thunderbrew"), levels (the rare fish are level 60) and race limits (6 quests).
- **7 quests have no zone in the server's record**, so they're under Uncategorized, as quest 1782
  already was: the 6 "Past Victories" quests and "Arena Grandmaster". Each is listed for review.
- **The review list** has 4,580 rows. "Failed on the beta below level 36" now holds 84, with the mount
  exchanges, battleground and event quests.
- **Found while checking the pins:** the Darkmoon Faire's givers in Mulgore are pinned on Desolace
  (4) and Thunder Bluff (2). They have no old Classic pin, and their quests' heading isn't a zone,
  so the last rule, the smallest frame that holds the spawn, picks a neighbour whose rectangle
  reaches into Mulgore.

### Three importer fixes (5 October 2026)

All three came out of the rerun (user's decision: do all three).

1. **Which map a spawn goes on.** Measured as #144 was, on the 884 NPCs with an old pin whose spawn
   several Era frames hold, with each NPC's own pin left out:

   | Rule after the NPC's own old pin | Right |
   |---|---|
   | City, zone, smallest (before) | 796 (90.0%) |
   | City, zone, then the frame the spawn stands furthest inside | 819 (92.6%) |
   | Old pins within 100 yards, then city, zone, furthest inside | 867 (98.1%) |
   | The same, with near-ties (within 0.05) going to the smallest | 868 (98.2%) |

   - The importer uses the last. The old pins within 100 yards are a human answer: Ravenholdt's
     guards stay on Alterac Mountains, with Fahrad's and Lord Jorach Ravenholdt's old pins.
   - The near-tie rule keeps the two guards furthest out there, and Golhine the Hooded in Felwood's
     Talonbranch Glade. Each stands about as far inside a neighbouring zone's frame.
   - A city also needs the spawn's height: within 50 yards of the heights its old-pinned NPCs stand
     at. That keeps the Darkmoon Faire at the foot of Thunder Bluff's mesa (height about −8) off the
     city's map (62 to 177). A margin from the city frame's edge doesn't work instead: at 10% it
     moves 19 genuine Ironforge, Darnassus and Undercity NPCs out.
   - **Result:** 31 pins moved, none added or lost. All six Mulgore faire givers go to Mulgore.
     Kargath's "WANTED" and "KILL ON SIGHT" posters go from Searing Gorge's edge to the Badlands, and
     the Bulwark's Argent Officer Garush to Tirisfal. Lunar Festival elders go to their towns.
2. **Zones.** When the server's record names no zone, CMaNGOS's is used. 8 quests leave
   Uncategorized for Arathi Basin, Warsong Gulch, Stranglethorn Vale and Warrior, each listed for
   review. Uncategorized keeps 9 quests that neither source places, among them "REUSE ME" (98338),
   an internal title the junk filter misses.
3. **Quests the beta refuses.** A quest `QuestV2` lacks rests on CMaNGOS alone. When the beta
   refused it at level 1 to 35, where it answers nearly everything, it's left out, and it comes back
   once the server answers it.
   - That's 28 of #157's repeatable quests: the 14 mount exchanges and 14 battleground turn-ins.
   - The battleground ones may return when the battlegrounds answer.
   - The 7 mount vendors' pins go with them.

The result: **5,081 quests** and **1,732 pins**. The review list has 4,580 rows.

### Breadcrumbs, "only one of these" and reputation (6 October 2026)

Until now, Forever's quests had no breadcrumbs, no quests that shut each other out, and no
reputation rewards, so its quest window never warned and its tooltips showed no reputation. The
importer now writes two more files, and `Build-ForeverMenu.ps1` turns them into `qcQuest.lua`'s
tables. The addon's code is the same: Forever's client has every function and text these use, such
as `C_Reputation.GetFactionDataByID` and "Reputation Changes".

- **Breadcrumbs and groups come from CMaNGOS,** the only source for either: the game's quest record
  holds neither.
  - **Breadcrumbs:** CMaNGOS's `BreadcrumbForQuestId` gives 124 breadcrumbs, all in our data,
    leading to 93 quests. Examples are the three "The Ashenvale Hunt" quests that lead to the fourth,
    and the class trainers' summons. Retail's hand-made table has 6 of these pairs too, all the same
    way round.
  - **Groups:** a positive `ExclusiveGroup` means only one of its quests can be done. 91 groups have
    two or more quests in our data. Most are real choices: a class quest offered by several trainers,
    Gnome or Goblin Engineering, the three paths of the Ahn'Qiraj War, the three Argent Dawn
    Commissions.
  - **Recurring quests are left out.** CMaNGOS also groups repeatable quests, such as the
    battleground turn-ins of each level bracket and the replacement Water Sapta. A repeatable quest's
    completion isn't kept, so those only shut each other out while one is in the quest log. The
    addon ticks a group's other quests when one is handed in, so 85 groups with 257 quests remain.
- **Reputation comes from the game's records only.** The cache reader now writes each reward's
  amount. A record gives a step in the client's `QuestFactionReward` table, or its own amount in
  hundredths, which wins when it's set (as TrinityCore reads it).
  - **Forever's table is Classic Era's:** steps 1 to 7 give 10, 25, 50, 75, 100, 150 and 200. In TBC
    Anniversary's, as in retail's, they give 10, 25, 75, 150, 250, 350 and 500. The Burning Crusade
    raised quest reputation, so a city's usual 100 became 250
    ([Blizzard forum](https://eu.forums.blizzard.com/en/wow/t/reputation-in-tb%D1%81-classic-from-quests-with-the-cities-of-azeroths-factions-and-penalties-for-completing-quests-below-the-players-level-by-more-than-5-levels/271228)).
    Wowhead Classic agrees: Kobold Camp Cleanup gives 100 with Stormwind, and Bloodscalp Ears 100
    with Booty Bay and −500 with the Bloodsail Buccaneers.
  - **CMaNGOS's amounts are mostly TBC's.** Of the 1,346 rewards both give, on 1,180 quests, 96%
    match TBC's table and 16% the game's (the steps of 10, 25 and 5 are the same in both). A few,
    such as the cloth donations' 150, are Classic's.
  - **So a quest the game hasn't answered has no reputation yet:** 1,012 such quests reward some
    in CMaNGOS. Most are above level 40, which the beta doesn't serve yet; the rerun at launch fills
    them in.
- **The data:** `data/forever/links.jsonl` (348 quests) and `reputation.jsonl` (2,304 rewards on
  1,837 quests, from 40 factions). `Build-ForeverMenu.ps1` writes them into `qcBreadcrumbQuests`,
  `qcMutuallyExclusive` and `qcQuestReputation`. It also writes each faction's English name from the
  client's `Faction` table into `qcFactions`, for when the game doesn't name one. Forever's new
  factions are among them, such as the High Order and the Windshapers.
- **Checked** with a test that loads the Forever TOC with stand-ins for the game:
  - the tooltips of quests 7, 189 and 99191;
  - the breadcrumb notice on 6383 and the "only one of these" alert on 235;
  - the quests ticked on hand-in and at login.
  
  Three broken copies of the tables (no groups, breadcrumbs the wrong way round, TBC's amounts)
  each failed it. The reachability check is still clean.

### Event quests (6 October 2026)

The user found pins in Darnassus for the Scourge Invasion's "Light's Hope Chapel" and "Investigate
the Scourge of Darnassus", though the event isn't running. The importer only gave a quest a holiday
when CMaNGOS tied its event to one of the client's holidays, so givers who stand only during other
events were pinned all year.

- **What was pinned all year,** by CMaNGOS's `game_event_creature` and `game_event_gameobject`:
  - the Scourge Invasion's 23 givers in the six capitals, Dun Morogh and the Eastern Plaguelands;
  - the Ahn'Qiraj War Effort's 58: the collectors and commendation officers of the collection
    phase, the ten-hour war's sergeants, the officers who take signets once the war is over, and
    the Colossus researchers and the Scarab Gong in Silithus. Its phases can't run together, so
    some of these were wrong whatever state Forever's world is in;
  - the fishing contest's 5 announcers and judges in Booty Bay, Orgrimmar and Ironforge;
  - Kruban Darkblade in Orgrimmar, who stands there while the Darkmoon Faire is being built;
  - two objects only there during a holiday, whose quests were seasonal with no holiday: Hallow's
    End's kegs ("Ruined Kegs") and Love is in the Air's cauldron ("A Bubbling Cauldron").
- **The importer** gives a quest the holiday or event all its givers, NPCs and objects, stand only
  during. One giver who's always there means the quest is always there. CMaNGOS's events with no
  holiday of their own go by their description: the faire's building days are the faire's, the
  contest's announcers and judges the contest's (Holidays ID 301, on Forever's calendar every Sunday
  from 14:00 for two hours), and the Scourge Invasion and the War Effort get flags of their own.
- **The Scourge Invasion and the War Effort aren't in Forever's Holidays table** (build 70205), so
  its calendar can't show them. Their entries in `qcHolidays` have no IDs, and the seasonal filter,
  on for the map by default, always hides their pins. The quest list keeps their quests.
- **Recurring quests keep their type.** Seasonal came before daily, weekly and repeatable, so a
  repeatable holiday quest was seasonal, and stayed ticked off once handed in. Recurrence now comes
  first, as on retail: the Darkmoon Faire's 40 turn-ins and Love is in the Air's 2 "Gift Giving"
  quests are repeatable, as are the event quests above that repeat.
- **`/qc holidays`** lists only the holidays the game's quests have, so Forever's no longer lists
  retail's, and retail's doesn't list Forever's events.
- **The result:** 139 quests gained a holiday (21 of the Scourge Invasion, 108 of the War Effort, 7
  of the fishing contest, the faire's one and the 2 objects'), and 42 holiday quests are repeatable.
  Still 5,081 quests and 1,732 pins. The reachability check lists the 81 pins of the Scourge
  Invasion and the War Effort in a section of their own; every other count is still 0. A test with
  stand-ins for the calendar showed the fishing pins on a Sunday afternoon and the keg during
  Hallow's End, and none of the 81 pins on any day.

## Decisions

1. **A longer-term project** (2026-10-04): the retail plan comes first.
2. **Our own database, not a dependency on QuestieDB** (2026-10-05).
3. **Start on the beta** (2026-10-05): the probe and recorder run there before launch, and again on
   the live game.

## Open questions

- The interface number at launch, and whether the `_Camelot` suffix stays.
- Whether retail recognises the `camelot` token. That only matters for a one-TOC layout.
- Whether Thalid83 plans a Forever version, and whether their Classic data can be compared.
- Which old quests that only the game knows Forever really offers. They're later Classic Era
  additions, such as a Warlock "The Binding" chain and Paladin quests numbered 78000 and up.
- Whether Forever will run the Scourge Invasion or the Ahn'Qiraj War Effort, and how. In Classic Era
  the war is long over, and the officers who take signets stand in the capitals for good; if
  Forever's world is like that, their pins should show. If either event comes to Forever's calendar,
  `/qc holidays` lists it among the calendar holidays not tied to a quest.
- Whether the 39 quests CMaNGOS calls repeatable that `QuestV2` does list really repeat. No quest
  retail's API flags repeatable is in retail's `QuestV2`, but Forever's lists "Junkboxes Needed"
  (8249), which retail's API calls repeatable. They keep CMaNGOS's type until the recorder sees them
  offered.

## Status

- 2026-10-04 and 05: researched and planned.
- 2026-10-05: phase 1's probe (#139) ran on the beta; results above.
- 2026-10-05: phase 2's cache reader (#141) written; results above.
- 2026-10-05: phase 3's importer (#142) written; results above.
- 2026-10-05: phase 4's addon files merged (#143); results above. The beta test found indented
  subzones in the menus (fixed in #143) and pins on the wrong maps (fixed in #144).
- 2026-10-05: the full sweep covers Forever: maintenance.md's step 10 rebuilds its data, and the
  probe's steps are under "In the game" (#145).
- 2026-10-05: the importer pins quests at the client's start points and counts what Blizzard fills
  in; the sweep takes in the recorder's notes every time.
- 2026-10-05: `QuestV2` leaves out repeatable quests, so the importer keeps CMaNGOS's 573 and the
  probe (#139) asks about all 710 CMaNGOS quests it lacks (#157); results above.
- 2026-10-05: the probe rerun and step 10 (#159); results above.
- 2026-10-05: three importer fixes: spawns' maps by nearby old pins and height, CMaNGOS's zone where
  the game gives none, and quests the beta refuses left out; results above. Next: a probe rerun once
  the beta opens levels above 40, more of Zephras Isle from the recorder, and the importer's next
  pieces (breadcrumbs, mutually exclusive quests, reputation rewards).
- 2026-10-06: beta build 70235 has the same quest and map tables as 70205, so it needs no rerun.
  Breadcrumbs and "only one of these" groups from CMaNGOS, and reputation from the game's records
  (Classic Era's amounts, not CMaNGOS's mostly TBC ones) (#162); results above. Next: a probe rerun once
  the beta opens levels above 40, and more of Zephras Isle from the recorder.
- 2026-10-06: quests whose givers only stand during an event follow it. The Scourge Invasion's and
  the Ahn'Qiraj War Effort's, which the calendar doesn't show, stay off the map, and recurring
  holiday quests keep their type; results above.
