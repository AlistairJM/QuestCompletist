# Open items and calls kept

What was decided on 7 and 8 October 2026, and what is left to come back to. Each item points at the
document that has the detail. When one is done, change its line here and say so in that document's
status.

## Calls kept

The user agreed all of these ("keep all of these calls", 8 October 2026):

- **A normal quest gets a pin wherever a source puts where it is picked up, with or without an NPC,
  and never a world quest; the same for every game that has the data, and the steps are in the
  runbook for every sweep.** Retail: [maintenance.md](../maintenance.md) steps 5 and 6;
  Forever: step 10; the rule and its limits per game are in
  [game-parity.md](game-parity.md), data row "Pickup sources for pins".
- **No quest leaves the data unseen, and a missed answer doesn't remove one** (10 October 2026). The
  importer stops and lists any quest it would drop, with ID, name and zone, and waits for a KEEP or
  REMOVE row in `quest-removal-decisions.csv`; `Show-RemovedQuests.ps1` does the same for either game
  before a pull request. The beta's API sometimes doesn't return quests it has (Christmas quests among
  them), so Forever's importer keeps a quest's last record until it has missed 10 runs in a row, and
  then asks. Kept by the user: 79482, 79483, 79492, 79495, 93188 and 93196
  ([forever.md](forever.md), "The beta's answers differ between runs").
- **A pin stands where a quest starts (`QuestPOIBlob` point 32), never at the hand-in.**
  [quest-location-data-pipeline.md](quest-location-data-pipeline.md), "pins at the start".
- **A quest that starts in several places gets a pin at each, up to six** (class and race quests
  start in several cities, as in the client's own data); more go to
  `tools\quest_locations_tdb_review.csv`.
- **A nameless pin is fine; a wrong NPC name is not.** A quest joins a neighbour's identity only if
  that NPC starts it, and by-hand names go in `pin-giver-decisions.csv`, each read on Wowhead.
- **Untested changes wait** unless the user says to ship them: a pull request that changes the addon
  and hasn't been tried in game is not in the release ([releasing.md](../releasing.md), step 1).
  #223 and #224 went out in 112.5 on the user's word, and #276 and #280 in 112.9 (10 October 2026).
- **Continent maps get one icon per zone** (10 October 2026, "go with your picks"): the quests left
  to do in the zone, counted from the quest list's categories with the map's filters and without
  daily, weekly and repeatable quests, hovered for counts and progress, opened with a click, with a
  child option of "Show Map Icons" that is on by default. Capitals fold into their host zone, and the
  continents inside a continent (Quel'Thalas, Argus) get an icon on the outer map that opens them. Built
  in eight pull requests, the first of them the probe's geometry pass
  ([continent-pins.md](continent-pins.md)).
- **Both quest-giver recorders are kept** (11 October 2026, "yes, keep both, go ahead"): the probe's own
  recorder is not retired once the addon's has run a sweep. Both feed the ledger through step 6d, and
  Forever's importer reads the ledger, so what they saw is combined
  ([quest-giver-recorder.md](quest-giver-recorder.md), "What is left", 4).
- **A check stays in the sweep even while it finds nothing**, and every feature or check built for
  one game goes to both unless a game can't support it
  ([game-parity.md](game-parity.md)).
- **Every change and sweep uses the newest version of every data source**: the client's files, the
  in-game probes and the external databases (9 October 2026). The beta moved from 70245 to 70291 to
  70338 in three days while the tables and the probe list stayed behind. `Get-LatestBuilds.ps1` is
  step 0 of the sweep and is run again before each in-game session
  ([maintenance.md](../maintenance.md), "Before a sweep").

## To try in game

Keep the manual checking small. The user has said (9 October 2026) that long in-game test sheets are
too much to ask. The code and the data are checked offline (the real addon files under stand-in APIs,
counts recomputed a second way, the repo's test tools), so ask for in-game testing only for what the
game alone can answer, such as what an API call returns or how retail and Forever differ, as a few
lines per game and a few minutes in all, and say what was verified offline instead of asking for it
again.

- **The quest tooltip's storyline name and "Type:" row** (built 11 October 2026, untried, both games; one line each):
  hover one quest in the list and read the Storyline and Type lines. Retail: 10257 "Capturing the Keystone"
  (Netherstorm) should show "Type: Dungeon" and its storyline's name in your language. Forever: 19 "Tharil'zun"
  (Redridge Mountains) should show "Type: Elite". A storyline name still in English on another language's client
  is expected for about 2 quests in 100 (the game names a larger quest line); say if it is more.
- **Waypoints without TomTom** (#300, built 11 October 2026, untried in game). With TomTom disabled, click a pin
  on a zone's map on each game and look for Blizzard's waypoint arrow. If nothing appears,
  `/run print(C_GameRules.IsGameRuleActive(Enum.GameRule.WorldMapTrackingPinDisabled), C_Map.CanSetUserWaypointOnMap(C_Map.GetBestMapForUnit("player")))`
  says which of the two refused.
- **Retail's minimum levels (11 October 2026, untried in game):** on a level 1 Horde character, hover the pin of quest 24430 "Blacken the Skies" (Azshara, 14.5, 65.7) and read the Requires Level line: 5 (it said 30 before).
- **The continent icons** (released in 112.8; the first look is done, the final build is untried; the probe's geometry pass is run): both games'
  dumps were read on 10 October and are the baseline (`continent-geometry-baseline.csv`, sweep step
  2f); retail's next dump comes with its map pass once 12.1.5 is live, plus `/qcprobe geometry`
  with the world map open on a continent, windowed and then maximised. One
  look at the icons on each game, five observations in about three minutes ([continent-pins.md](continent-pins.md), "To try in game").
  The first look moved Tiragarde Sound's icon and nudged Darkshore's and Felwood's on both games
  (`QC_ZONE_ICON_AT`), added icons for the hubs and sub-zones it found missing on retail (Oribos, Dalaran,
  Undermine, Nazjatar, Ahn'Qiraj: The Fallen Kingdom, Korthia and the rest), enlarged the icon where
  its art allows and put a green check on finished zones (while the map shows completed quests);
  twelve more retail zones and one Forever zone sit 50 px or more from their hit area's centre and wait for the user to say which to move.
- **The level 10 rogue lead-ins on Forever** (#297, 11 October 2026, not yet tried in game, so not for a
  release until tried or the user says so). Two looks on the beta: on Rothro after `/reload`, Road to
  Salvation (2218) shows as not done; on a new Human rogue, Snatch and Grab (2206) on Master Mathias
  Shaw's pin is grey, "Requires Seek out SI: 7", until Seek out SI: 7 is handed in. Optionally, a
  third: after handing in Deliver Thomas' Report (39), Guard Thomas offers Bounty on Murlocs (46),
  which his pin greys until then. Destiny Calls needing The Apple Falls, and a hand-in ticking no other
  lead-in, are checked offline by `Test-Completions.lua` ([forever.md](forever.md), "Lead-ins the
  server requires").
- **Breadcrumbs closed while their quest is in the log** (11 October 2026, stacked on #297, not yet tried
  in game, so not for a release until tried or the user says so). One look on the beta: with Redridge
  Rendezvous (2281) in Rothro's log, Keryn Sylvius's pin no longer lists SI:7 (2300) but still shows Seek
  out SI: 7 as done (Rothro's map hides quests in the log, not done ones), and Erion Shadewhisper's pin
  still shows Erion's Behest. The same code runs on retail; its breadcrumb chains, the quests listed as
  each other's breadcrumb and the API's breadcrumbs in `qcClosedOnceDone` are checked offline by
  `Test-Completions.lua` ([forever.md](forever.md), "Lead-ins the game closes while their quest is in
  the log").
- **The class quests' links on Forever** (11 October 2026, stacked on the two above; data only, no
  addon code). One question the game alone answers, on Rothro before he takes Redridge Rendezvous
  (2281): does Hulfdan Blackbeard in Ironforge offer Kingly Shakedown (2298) without To Hulfdan! (2299)
  done, and, if Rothro hasn't done Erion Shadewhisper (2259), does Erion offer Erion's Behest (2260)?
  If so, a `prereq` `REMOVE` row each. The warrior, mage, Silithus and Call of Earth rows rest on
  Questie's issues and Wowhead's comments and are checked offline by `Test-Completions.lua`
  ([forever.md](forever.md), "CMaNGOS's other links, reviewed against first-hand reports").
- **Call of Earth on Zephras Isle is for shamans** (#307, 11 October 2026, stacked on the three above; data
  only). One question the game alone answers: does Windshaper Boro in Thendal Grove offer Call of Earth
  (92466) to a Windshaper of another class at level 3 or 4? If he does, the three rows of
  `forever-quest-class-decisions.csv` go ([forever.md](forever.md), "Class quests the game files under
  a zone").
- **CMaNGOS's other requirements on Forever** (#308, 11 October 2026; data, and a
  small change to the quest window's breadcrumb notice on both games, untried in game, so not for a
  release until tried or the user says so). One look on the beta: at In Search of Anthion (8929) or
  Taming the Beast, the notice counts only the lead-ins this character can take. The 119 prerequisites
  and 141 lead-ins closed by their next quest come from CMaNGOS and are checked offline by
  `Test-Completions.lua` ([forever.md](forever.md), "The rest of CMaNGOS's requirements").
- **Quests offered only while another is in the log, on Forever** (#309, 11 October 2026, stacked on the one
  above; shared code, untried in game, so not for a release until tried or the user says so). One look
  on the beta: a quest of `qcQuestNeedsInLog`, such as Digging Through the Dirt (254) in Duskwood, is
  grey ("Requires Bride of the Embalmer in your quest log") until Bride of the Embalmer is taken, then
  white. The rest is checked offline by `Test-Completions.lua` ([forever.md](forever.md), "Quests
  offered only while another is in the log").
- **Two retail breadcrumbs that close only once all their quests are done** (found 11 October 2026, data
  from 6 October). Blizzard's API keeps 65890 The Nelthazan Ruins offered while any of 65891, 65893 or
  66719 is still to do, and 66261 A Minor Setback while any of 66262, 66263 or 66264 is; our breadcrumb
  table ticks each once any one is handed in. `qcBreadcrumbQuests` can't say "all of", and
  `Audit-QuestTables.ps1` takes each "must be incomplete" leaf whatever the AND/OR above it. To decide: a
  table for "all of", or dropping the six pairs and clearing their ticks through `qcFormerlyExclusive`.
- **Stacked pins** (#276, released in 112.9 untried; one optional line on retail). Click a stacked pin
  whose first quest has no giver name and see the named giver's icon, name and TomTom title (Durotar
  around 45.7, 15.9 has one). The holidays half of this item (#280) is answered: the user's
  `/qc holidays` on retail, 11 October 2026, dated the Moonkin Festival (694) on 12 November 2026 and
  said Hearthstone's 10th Anniversary is not on the calendar in the next 12 months, both as expected
  ([maintenance.md](../maintenance.md), "Holidays").
- **The anniversary's pins (retail, one look after 17 November 2026).** The 19 WoW's Anniversary quests
  are tagged on calendar ID 1808, which `/qc holidays` listed on 11 October 2026. Offline, with the
  default filters, their pins are hidden out of season (Moira Thaurissan's pin on Tanaris and 47254's
  in the Caverns of Time go, and the Tanaris stack at Chromie loses its anniversary quests and stays
  under Bobadormu's name) and shown with 1808 running. While the event runs, those pins should be on
  the map; before 17 November they should not.
- **The cups' pins (retail, one look while a cup runs; the next is the Kalimdor Cup, from 23 February
  2027).** The 16 Skyriding cup quests share one flag on the four cups' calendar IDs (#310).
  `/qc holidays` listed 1395 and 1400 on 11 October 2026; the Outland (1407) and Northrend (1429)
  Cups are next dated in 2028, beyond its 12 months, so nobody has seen the calendar serve them yet.
  Offline, with the default filters, out of season the Racing Enthusiast's pin in Stormwind or
  Orgrimmar, Lord Andestrasz's in Valdrakken and the three Holiday Enthusiasts' in Dornogal go (the
  Dornogal ones stay while another of their holidays runs), and any cup running brings them back.
  Now `/qc holidays` should show one line for the cups, naming the Kalimdor Cup (1395), and no
  Eastern Kingdoms Cup under "Other calendar holidays"; while a cup runs, those pins should be on the
  map. After the Eastern Kingdoms Cup of 2027 ends (7 September 2027), the cups' line should name the
  Outland Cup (1407), which shows the calendar serves it.
- **The pins of #223 and #224** (193 quests with only a start point, and 1,453 more from
  TrinityCore's start points) shipped in 112.5 without an in-game check: the user, shown a list of
  spots to check, said it was too much to check by hand and to go ahead (8 October 2026). When
  convenient, look at a few, and at these: quest 1036 "Avast Ye, Scallywag" (its pin is where the
  client puts its end, not at "Pretty Boy" Duncan), the class quests at Orgrimmar's and Stormwind's
  hubs, the Silithus sigil quests (45749 to 45762, which may be retired), and the pins on the Caverns
  of Time.
- **The pins moved to quest starts (#219)** are checked by the user for a sample, not for every
  zone.
- **The menu review (#251, released in 112.7 untried; the starter areas only).** The offline checks cover the menus: every category with
  quests has a menu entry and a zone row, none is empty, and the reachability run leaves no quest out.
  What only the game can show is the four starter areas, whose quests are filed under their parent
  zone: walk into Camp Narache, Shadowglen, Valley of Trials and New Tinkertown and see the list follow
  Mulgore, Teldrassil, Durotar and Dun Morogh ([menu-review.md](menu-review.md)). The new Quel'Thalas, Gilneas and Tol Barad submenus under Eastern Kingdoms, and Founder's Point and Razorwind Shores under Midnight's Other Categories, are offline-checked too (the three names come from the client's maps, with English as the fallback). The Main Zones and Other Categories submenus of Draenor and The Broken Isles (question 21) are offline-checked too. The one new thing to look at is the line an empty list shows (question 26, "Quests hidden by your filters: N"): open any entry that lists nothing at the default filters, such as Rated PvP on retail.
- **The calendar window's filters, on both games (#243, released in 112.6 on 9 October 2026).** The
  seasonal filter treats a holiday whose filter is unticked as running, on the reading of Blizzard's
  source that the game then leaves its events out of the calendar. Nobody has seen that in game.
  The whole check is seven lines per game, entered one at a time (a pasted block is joined into one
  chat line), in a city with the calendar window shut:

  ```text
  /qc holidays
  /run function QCL(c) local t,s={},"" for d=1,c.GetMonthInfo(0).numDays do for i=1,c.GetNumDayEvents(0,d) do local e=c.GetDayEvent(0,d,i) local k=e.calendarType:sub(1,6)..(e.eventID or 0) if not t[k] then t[k]=1 s=s..k.." " end end end print(s) end
  /run QCL(C_Calendar)
  /run print(SetCVar("calendarShowHolidays","0"),GetCVar("calendarShowHolidays"))
  /run QCL(C_Calendar)
  /qc holidays
  /run print(SetCVar("calendarShowHolidays","1"),GetCVar("calendarShowHolidays"))
  ```

  Paste back the first `/qc holidays` (it also lists the other calendar holidays), the two lists, the
  two read-backs (`nil 0` and `nil 1`, or `true` for `nil`) and the filter line of the second
  `/qc holidays`.
  - `HOLIDA324`, and `HOLIDA1405` on retail, are in the first list and missing from the second: the
    game drops an unticked filter's events, and the handling is needed. In both lists: the game keeps
    them, the handling is harmless but unneeded, and the user decides whether to keep it. Anything
    else (another ID gone, an error, a read-back that did not change): the table `qcHolidays` or the
    CVars need another look.
  - It leaves unseen, on purpose: that Darkmoon and the fishing contest sit under their filters (the
    table is the client's own `CalendarFilterType`, and the handling fails open, so an unticked
    filter shows the quests), whether ticking a box fires `CVAR_UPDATE` (the map notices at its next
    draw; a listener was left out), and the map with a filter unticked (tested offline). The longer
    experiment is in [maintenance.md](../maintenance.md), "Holidays", for a puzzling result only.
  - The user decided on 9 October 2026 to go with #243 without this check, and to deal with any
    problem when it shows, so it shipped in 112.6. The seven lines stay for whoever wants to
    run them. When they have been run, change the "not yet seen in game" wording in maintenance.md
    ("Holidays") and in the C_Calendar section of [game-api-review.md](game-api-review.md), and take
    this item off the list.

- **Which API reads an expansion's profession skill, on retail (two lines, retail only).** Retail's
  skill requirements are on expansion skill lines: of the 524 task quests with a skill filter, 464
  name one ("Legion Mining" 2566, "Kul Tiran Herbalism" 2549, "Legion Skinning" 2558, whose parents
  in `SkillLine.csv` are the base professions 186, 182 and 393) and 60 a base line (Fishing 356 x44,
  Jewelcrafting 755 x12, Tailoring 197 x4). Offline, Blizzard's own profession book
  (`Blizzard_ProfessionsBook`) reads `GetProfessionInfo` as rank and maximum of a line it titles
  with the 11th value `skillLineName`, with a base `skillLine` in the 7th (it hands that one to the
  unlearn dialog); that the line is the newest known one is an inference from that code, not seen.
  So the fallback in `qcSkillRank` can answer for the base lines and for nothing else, which is why
  it says "can't say" for the rest. The API that may answer for an expansion line is
  `C_TradeSkillUI.GetProfessionInfoBySkillLineID`; what the game alone can say is whether it works
  with the professions window shut and returns the character's level. On a retail character with a
  profession, best one with an older expansion's skill, in a city, window shut, entered one at a
  time:

  ```text
  /run for _,i in pairs({GetProfessions()}) do print(GetProfessionInfo(i)) end
  /run for _,l in ipairs(C_TradeSkillUI.GetAllProfessionTradeSkillLines()) do local i=C_TradeSkillUI.GetProfessionInfoBySkillLineID(l) if i and (i.skillLevel or 0)>0 then print(l,i.professionName,i.skillLevel,i.maxSkillLevel) end end
  ```

  Paste back both outputs.
  - The second lists expansion lines (2566 and the like) with the character's levels: the API reads
    them with the window shut, and `qcSkillRank` can use it on a client without `C_SkillInfo`, then
    the data from `QuestV2CliTask` and TrinityCore (recommendation 3 of
    [game-parity.md](game-parity.md)). Nothing, a Lua error, or only base lines: it needs the window,
    and an expansion line stays "can't say" on retail; the data then covers the base lines only.
  - The first shows whether the 7th value is a base line (164, 186 ...) and the rank the newest
    line's, as read above.
  - No offline test can answer this: the stand-ins for the client only return what they are given.
- **The recorder** (#228, released in 112.7 untried), on both games: a full WoW restart, then the list in
  [quest-giver-recorder.md](quest-giver-recorder.md) ("To try in game"): the order of the events,
  whether the game hides who is speaking, whether the popup hook fires, what the options panel
  looks like in the longest language. It went out in 112.7 on the user's word, without this session
  (9 October 2026), so the session now checks what players already have. **Forever answered part of it
  on 11 October 2026** (the beta file, 87 records, read clean): every window's giver was readable (`npc` at
  gossip, `questnpc` at the quest windows, nothing hidden), the popup hook installed, and the game named no
  map in the Deeprun Tram, where the recorder keeps no spot at all. **Still open:** retail
  (its recorder file held 0 records on 11 October), an item or area-trigger start, and a dungeon, delve,
  combat, mounted or taxi read, on either game; the options panel's layout and `/qc report`
  ([quest-giver-recorder.md](quest-giver-recorder.md), "To try in game").
- **The probe on both games** (`tools/ForeverProbe`): **run and read** on 9 October (retail 12.1.0.69933:
  35,023 quests, 8,418 NPCs, 1,961 maps; the Forever beta, 70291) and 10 October (Forever, 70338); the
  results are in `tools\retail_probe_69933\` and `tools\forever_probe_70338\`. Pin names: 10,562 of
  10,564 retail pins and 1,503 of 1,503 Forever pins are the game's own. The map totals are those of 7
  October (retail 439 offers; Forever none, 16 points of interest). All twelve fact functions exist on
  both clients, `GetQuestExpansion`, `IsBreadcrumbQuest` and `IsStoryQuest` among them, but Forever
  returns inert values for most (every expansion -2, no tasks, campaigns or story quests). Still open:
  whether `GetQuestLineInfo` answers for a quest the server refused, and whether `IsAccountQuest` needs
  loaded data. The probe now tallies every fact function on the quests it is refused (`refusedFacts` in
  the quest run's row) and records the character and level of every run, so the next run answers both,
  and says whether the beta's answers follow the character: copy the probe folder into the AddOns
  folders again first, then read the file with `Read-ForeverProbe.lua <file> facts`. The next run is
  retail's, once 12.1.5 is live (13 or 14 October): run `Get-LatestBuilds.ps1` first, then the same
  three commands, so the 9 October results are the baseline.

## Decisions waiting for the user

| # | Decision | Recommendation | Detail |
|---|---|---|---|
| 1 | Add the about 535 player-facing task quests the database lacks (decision 9), with no pins | **yes, 11 October 2026, done**: `Add-TaskQuests.ps1` (step 6b) added 506 quests, the 535 less 29 internal test and placeholder entries: 260 of type 128 (world quests and weeklies), 37 dailies and 209 others that the list shows by default, 41 of all in Uncategorized; retail alone | [game-api-review.md](game-api-review.md), "Decisions to take"; [maintenance.md](../maintenance.md), step 6b |
| 2 | Pin the task quests already in the data that have a start and are not world quests (4,082 have a start and no pin: 3,148 of world-quest kinds, 758 of other kinds, 83 callings, 77 racing, 16 threat wrappers and bonus objectives) | **yes, 11 October 2026, done: the 758 kinds plus Dragonrider Racing** (the user: "yes, include racing, hold callings"). 814 quests are pinned: 737 of the 758 (21 start off their map) and the 77 racing quests (77 start gates on 12 maps, no giver). Pins went from 15,181 to 16,048 (15,971 for the 758 alone), quests with a pin from 24,931 to 25,745, and 844 of the 867 new pins have no giver. The racing pins show on the map at the default settings (its "Hide World and Weekly Quests" filter is off; the list's is on). **Still held, by their lines in `$noPinKinds` (deleting a line pins that kind):** the callings (83 daily quests with 98 places on 7 covenant sanctum maps, 86 nameless pins), until it is known whether the game still offers them, and the 11 Threat Wrapper (268) and 5 Bonus Objective with Completion Toast (283) quests that have a start, as the approval was for the 758, which has neither | quest-location-data-pipeline.md, "pins for the task quests that are not world quests" |
| 3 | 82449 "The Call of the Worldsoul", a task-table quest | **resolved by row 2 (11 October 2026): it is pinned at its client start, nameless** (a Meta Quest, one of the 758, in Dornogal); the hand entry is not needed | same |
| 4 | Item-started quests with a start point but no NPC (about 13% of all pins) | keep pinning them, as before | quest-location-data-pipeline.md, "pins from TrinityCore" |
| 5a | What a creature's offer lets a quest have a pin for ([quest-giver-recorder.md](quest-giver-recorder.md), "The merge tool", Adds): the holds on a quest that no creature offers (not in `QuestV2`, Landfall, holiday, profession, a quest type other than 0, 1, 2, 4 and 128, and a calling or threat-wrapper task, the kinds of `$noPinKinds` the tool does not hold itself) are waived when a creature offers it; unavailable and internal-name quests stay held, and so do the system categories except the six of 5b (a task of another kind than world, bonus or hidden was in the list until 11 October 2026, when the pipeline began to pin those) | keep: an NPC offering a quest is the best proof it is a real pickup; the report counts the quests by class. This settles decisions 2 and 5 case by case for NPC-offered quests. To undo a class, edit `$isPinnable` in `Import-RecordedGivers.ps1`, or add a `KEEP` row for the quest | the plan, "Adds" |
| 5b | Which system category (Garrison Support, Torghast, Prey, Delves ...) may get pins from an offer | yes, 11 October 2026, done: allowed are World PvP 1095, Little Scales Daycare 1346, Upgrade System 1428, Warbands 1429, Delver's Headquarters 1430 and Weekly Events 1735, the categories where at least half the quests already stand on a pin with an NPC; held are Prey 1514 and Garrison Support 290 until there is more detail, and the 12 others, which are below 45% (Visions of N'Zoth and Time Rift are the nearest). `$allowedSystemCategories` in `Import-RecordedGivers.ps1` is the switch; the report lists the held ones by category; the TrinityCore pass's own skip is unchanged | the plan, "Adds" |
| 5 | The Landfall dailies (31 without a pin, 29 with one already) and the Silithus sigil quests (10), which look retired | **yes, 11 October 2026, done: KEEP rows, nothing flagged.** The evidence says they are not retired: the 73 Landfall dailies are served by the API, listed in both builds' QuestV2 and known to the server, and the sigil quests are the turn-ins of the yearly Call of the Scarab event (16 quests, not 10). 89 `KEEP` rows now record that | unavailable-quests.md |
| 6 | The remaining decisions 1 to 7 of the API review (recorder on retail and the probe additions are agreed and built, and so are text from the game and the waypoint fallback (#300), on 11 October 2026; the tracking toggles stay as they are, the user's call of 11 October 2026 ("leave the filters alone"); still open: scaling-aware levels) | see that document | game-api-review.md |
| 7 | Pin-per-quest (retail) or pin-per-spot (Forever) for nameless pins | decide, then align the tool that differs | game-parity.md, recommendation 11 |
| 8 | Refresh retail's levels from the API: 1,589 quests differ from it (large blocks in Zaralek Cavern, Mechagon Island and the Emerald Dream, where the API gives a much lower minimum than we store), 4,955 have no API record, 224 are 0 | **not taken, 11 October 2026: option C chosen instead (row 14)**; the API minimum is used for the gate, the stored level is unchanged; a quest with no API record takes the client's level range, or keeps its level as the gate when it is on tuning 0 or has no source | client-tables-review.md (the note on `level`); maintenance.md, the data files |
| 9 | Scaling quests: the list bracket and the low-level filter read a scaling range's floor, so they judge a quest low level too early | probe first, agreed 10 October 2026: #282 adds `IsQuestTrivial` and the content difficulty to the probe's facts pass (copy the probe into both AddOns folders again first); read the post-12.1.5 retail run and Forever's next run, then decide | game-api-review.md, recommendation 4 |
| 10 | Holiday flags for the retail events `qcHolidays` has none for: the four Dragonriding cups (16 quests, 12 with pins, which showed all year until they were tagged), Secrets of Azeroth, WoW Anniversary, Dastardly Duos, the weekly bonus events, and the 54 Ahn'Qiraj War Effort and Scourge Invasion quests | **WoW Anniversary: yes, 11 October 2026 ("build it with 1808 and the yearly check"), done in #305**: flag 524288 on calendar ID 1808, the 19 quests tagged, and step 2b reports each later year's row. **The Dragonriding cups: yes, 11 October 2026 ("yes, one shared cup flag"), done in #310**: one flag, 1048576 ("Skyriding Cups", the name the user chose on 12 October 2026, as the client now says "Skyriding Races"), on the four cups' calendar IDs 1395, 1400, 1407 and 1429, the 16 quests tagged, and step 2b reports a new cup's row ("<Region> Cup"). For the other events: a flag per event, tied to the calendar ID that `/qc holidays` lists under "Other calendar holidays" while it runs; the next free flag is 2097152 | `quest-holiday-decisions.csv`, the PENDING rows; maintenance.md, "Holidays" |
| 11 | Two quests of the holiday record: 56322 "Contained Alemental" (Wowhead lists Event: Brewfest) and the 12 "Bar Tab Barrel" quests, tagged Brewfest but still filed under the Dragon Isles zones, unlike the ten already under Brewfest | **yes, 10 October 2026, done**: 56322 tagged and the 12 Barrels refiled under Brewfest (31) | `quest-holiday-decisions.csv` |
| 12 | Forever's 29 untagged seasonal quests (none has a pin: 12 Children's Week and 6 Winter Veil by a hand list, 9 Scourge Invasion and 2 Ahn'Qiraj War Effort by an importer rule), and its calendar gaps: no dates for Children's Week or the Darkmoon Faire on the beta, and a nameless Winter Veil-like Holidays row, 1879, that the date decode puts from 15 November (not on the beta's calendar when checked in game, 11 October 2026) | **tagging: yes, 11 October 2026, done in #288**: the 29 are tagged (12 Children's Week and 6 Winter Veil from `forever-quest-holiday-decisions.csv`, 9 Scourge Invasion and 2 Ahn'Qiraj War Effort by the importer's heading rules). **Checked by the user in game, 11 October 2026:** `/qc holidays` on the beta lists Winter Veil as 141 (15 December to 2 January) and not 1879, so nothing is added; Children's Week and the Darkmoon Faire are not on the beta's calendar, which hides nothing, since the seasonal filter is the map's only and none of the 29 has a pin | forever.md, "Seasonal quests with no holiday"; maintenance.md, "Holidays" |
| 13 | A level of 0 or below reads as a level: 246 retail and 12 Forever quests show "[0]" in the list and count as low level for everyone | **yes, 10 October 2026, built in #283**: no level in the two readers; the sources for the 246 are under row 33 | `qcCore.lua`, the list row and the low-level filter |
| 14 | Retail's gate level from the content tuning (the other way to row 8, which uses the API's minimum): `level` stays the row's own and `qcQuestMinLevel` carries the gate, as on Forever; 1,828 quests change | **yes, option C, 11 October 2026, done**: 1,623 quests got a `minLevel` (the API's minimum, else the client's level range; step 2g of the runbook). The 17 quests on tuning 0 with no API minimum got none, so their own level stays their gate: a first rule gave five of them (9422, 50341, 54255, 54256, 89346) a gate of 0, and the user chose the same day to leave them as they were | [retail-quest-cache.md](retail-quest-cache.md), "Level"; the other way to row 8 |
| 15 | Backfill reputation rewards from the cache for the 2,043 quests the API has no record of that reward a visible faction | yes, after in-game checks of five quests | same, "Reputation"; the quests are the `cache-only` rows of `quest_reputation_compare.csv` (`Compare-QuestReputation.ps1`) |
| 16 | Type changes the cache shows: 37 daily that are weekly, 92 repeatable that Blizzard calls daily or weekly, 4 that recur and are ticked for ever, 17 repeatable by the Darkmoon-deck rule, 38 one-time task quests, 21 test or deprecated titles | class by class | same, "Recurrence and flags" |
| 17 | Race changes: the two outright contradictions (quest 2, 27675), 19 stale masks, 49 starting-race narrowings, 28 where we show a quest to races the server denies | the contradictions and stale masks yes; the narrowings are a call; the 28 class by class | same, "Races" |
| 18 | Sort fixes: 98 Uncategorized quests whose sort names one category, 27 profession misfiles | yes | same, "Sort" |
| 19 | "Starts from" only from `ItemSparse.StartQuestID` or `QUEST_DETAIL`, never from the cache's `startItem` | yes | same, "Start item" |
| 20 | The 22 placeholder-named quests that still show in default lists (menu review R08) fail the step-7 evidence rules: flag them anyway? | **yes, 11 October 2026, done**: the same call as 5 October on the internal and test entries; all 22 flagged (86645 and 94815, client task quests, with the builder's reason 3), 240 flags and 481 `KEEP` rows now | [menu-review.md](menu-review.md), question 20 |
| 21 | One submenu shape for every expansion (R28) | **yes, 11 October 2026, done**: Main Zones and Other Categories for Draenor and The Broken Isles; Outland, Northrend and The Maelstrom stay flat | [menu-review.md](menu-review.md), question 21 |
| 22 | Midnight: move Founder's Point and Razorwind Shores into Other Categories (R27) | **yes, 10 October 2026, done** | [menu-review.md](menu-review.md), question 22 |
| 23 | Split Lordaeron into Lordaeron, Quel'Thalas, Gilneas and Tol Barad (R26) | **yes, 10 October 2026, done**: named from the client's maps | [menu-review.md](menu-review.md), question 23 |
| 24 | Merge Darkmoon Island into Darkmoon Faire and four one-quest entries into their zones (R15, R31) | **yes, 11 October 2026, done**: the 14 quests moved, the five categories removed with their menu entries, and the zone table sends the old maps to the targets, so the sweep tools file new quests there | [menu-review.md](menu-review.md), question 24 |
| 25 | Names that repeat, groups and categories that share a name, Forever's "Invasion" (R17 to R21, R25, F03) | leave; if it matters, show the menu path in the list header (no new text) | [menu-review.md](menu-review.md), question 25 |
| 26 | Entries empty by default and tiny entries (R29, R30, R39, F06, F07, F09) | **yes, 11 October 2026, done**: all kept; an empty list says "Quests hidden by your filters: N" on both games | [menu-review.md](menu-review.md), question 26 |
| 27 | Rated PvP, 86 of 87 quests unavailable (R06) | keep | [menu-review.md](menu-review.md), question 27 |
| 28 | Class Quests has no Evoker (R05) | leave | [menu-review.md](menu-review.md), question 28 |
| 29 | Ordering rule for Retail's lists (R33) | keep the hand order | [menu-review.md](menu-review.md), question 29 |
| 30 | Forever: split Seasonal, and Deeprun Tram and Special loose (F04, F05) | leave until after the 4 November launch | [menu-review.md](menu-review.md), question 30 |
| 31 | Remove the 83 unused category definitions (R32) | **yes, 11 October 2026, done**: 82 removed with their table rows and 12 locale keys; Island Expeditions (1130) stays, because two tools still name it | [menu-review.md](menu-review.md), question 31 |
| 32 | A start within a map point of an edge goes on the map the client's row for it names. 26064 was moved by hand to Stonetalon Mountains (10 October 2026); 15 other quests have the same shape and their client start on the edge map: Mulgore's Jin'Zil (5) and Devo (2), Stonetalon's Grimfang (2), Dread Wastes' Taran Zhu (4) and Garrosh (1), Crystalsong Forest's Xink (1). All were on the other map before "pins at the start" | leave them where the client puts them; if the user wants the rule ("prefer the map the other points are on", tried at 1 point, 16 quests including 26064), it is a small change to `Build-QuestLocationData.ps1` and a rerun of step 6, and the Mulgore camp's 7 quests are the nearest case to 26064 | [quest-location-data-pipeline.md](quest-location-data-pipeline.md), "a start on the edge of a map" |
| 33 | Retail's real minimums where we store 0, from the sources checked on 10 October 2026 ([retail-quest-cache.md](retail-quest-cache.md), "Level"). 22 quests have their own API record with a real minimum: 16 Garrison "Your Second ... Work Order" quests at 10 (3 of them sit on TrinityCore's tuning 0, which disagrees), 3 at 80 (64159, 64162, 64163) and 3 at 90 (62355, 89403, 91632); 90751 reads 80 from a neighbour's range only. 191 have an API minimum of 1 and stay 0, since a 1 would hide them as low level for a high-level character, as every retail quest with a minimum of 1 is today; the rest are tuning 0, test or tracking quests, or have no source | **yes, 10 October 2026, done**: the 22 set to the API's minimum, the rest left at 0 | the 22 `level` values in `data/quests.jsonl`, then a rebuild |
| 34 | Landfall's hold in the pin pipeline (`$landfall` in `Build-QuestLocationData.ps1`, "whose dailies look retired"): 44 Landfall quests have no pin, 31 of them with a TrinityCore start point; row 5's evidence says the dailies show no sign of being retired | keep the hold until someone has seen a level 15 to 35 character offered the dailies at Lion's Landing or Domination Point, then drop it | row 5; unavailable-quests.md |
| 35 | A holiday flag for Call of the Scarab (Holidays row 638, 21 to 23 January, every year): the 16 quests of 45747 to 45762 and, by the analyst's count, about 29 more of the event by name | undecided: the calendar does serve row 638 (retail `/qc holidays` listed it under "Other calendar holidays" on 11 October 2026), so a flag would show their pins only during the event and hide them the rest of the year; it takes one of the free flags in `qcHolidays` | row 5; unavailable-quests.md |
| 36 | How a place's visits are counted when several of the maintainer's files hold the same visits: the probe's file is cumulative, so a spot seen 3 times is 3 in each of four files and 12 in the sum, and the sum decides which of two rows 0.1 apart seeds a place | change it to the largest number any one own source gives (the sources describe the same visits, as the plan says); it moved 1 Forever pin by 0.1 on today's ledger, and it is a change to `Get-RecordedPlaces`, which retail's step 6d shares, so it is left as it is until you say | [quest-giver-recorder.md](quest-giver-recorder.md), "Known limits" (5); [forever.md](forever.md), "The importer reads the ledger" |
| 37 | Whether Forever's importer should group a giver's CMaNGOS spawns, and a quest's client start points, by the 1.5-point near-place test (`Test-NearPlace`) as it now groups recorded places, instead of the 3-point box both still use (the pin-spacing verdict of 7 October 2026). Measured on scratch copies (build 70338, each import followed by step 9; the same on today's ledger and on #298's): the start points change nothing. The spawns give 4 more pins, 1,698 to 1,702, for three givers whose spawns stand 1.5 to 2.2 points apart: Theramore Lieutenant (Dustwallow Marsh, quest 1220) 2 more, 2.0 and 2.2 points from its nearest pin; Lunar Festival Emissary (Ironforge, 8870 to 8872) 1, 1.85; Argent Quartermaster (Darnassus, six Scourge Invasion quests) 1, 1.52. So 10 quests gain another pin (all of them already had one) and none loses one. The CLUCK! chicken (3861), which gets one pin per map at its biggest group of spawns, moves on 3 of its 9 maps (Elwynn Forest 1.9, Duskwood 4.6, Wetlands 9.0 points), because smaller groups make another group the biggest. Step 9 leaves the new pins, as they are more than 0.5 apart | yes for both, so one radius holds for every Forever pin and for retail's; the 4 pins are NPCs that do stand apart, and the chicken only moves to another of its groups (if it should stay, its biggest group can still be counted at 3 points) | [forever.md](forever.md), "The importer reads the ledger" |
| 38 | Whether a recorded place more than a point from CMaNGOS's spawn should still win over the spawn. Today it does, and the review list names it ("recorded spot far from CMaNGOS"). The one case measured is Darcy (NPC 379, CMaNGOS's "Waitress", Lakeshire, Redridge Mountains, map 1433), who starts "A Free Lunch" (129): the probe's file of 11 October recorded her at 21.6,45.4, 1.10 points from her spawn at 21.53,44.3. CMaNGOS has her walk a 16-point path (`MovementType` 2), about 1.4 points end to end, pausing 12 to 32 seconds at five of its points; the spawn is one end of the path, and the recorded place is 0.11 from the point where she waits longest (32 seconds). They differ because she walks: both are places she stands | keep the recorded place winning (where a player found her is first-hand, and here it lies on her own path), and keep the review row so a far place is looked at each sweep | [forever.md](forever.md), "The importer reads the ledger"; the review list, `tools\forever_import_review.csv` |

## Data to finish

- **Names the TrinityCore pass left**: the Chromie Time breadcrumbs ("Onward to Adventure", 11
  quests), 41852 and 41853 under Brewer Almai, 41627 and 26149 beside pins of their twins that carry
  an object's name, and six stacks where a new pin names an NPC whose sibling quests sit on nameless
  old pins (Neeka Bloodscar, Merda Stronghoof, Keeper Remulos, Captain Verne, Bodrick Grey, Griff).
- **The 154 quests in `quest_locations_tdb_review.csv`**: placeholder starts (raid-wing quests, the
  Draenor garrison points, Mechagon, Nerub-ar Palace), starts outside every map, more than six
  places. Look through it after every run of step 6.
- **2,766 quests TrinityCore has a start for that the database lacks**: a list to look through for
  the step that adds quests the database lacks (`Fetch-GapQuestData.ps1`).
- **Forever's other CMaNGOS links**: the rogue lead-ins showed that a CMaNGOS breadcrumb can be a
  lead-in the server requires, and an `ExclusiveGroup` a choice it doesn't enforce. The level 10 warrior
  and mage groups, Securing the Supply Lines, Call of Earth and 14 prerequisites were reviewed and
  corrected on 11 October 2026 ([forever.md](forever.md), "CMaNGOS's other links, reviewed against
  first-hand reports"). Left: the rest of the 85 groups and 280 breadcrumbs (141 of them, since the
  same day, the quests CMaNGOS's next quest in the chain closes), which no report has
  questioned yet; 24 quests whose prerequisite is their own breadcrumb, from the cache's next quest,
  that no report settles (11, 276, 297, 466, 729, 844, 870, 1085, 1338, 1420, 1473, 1501, 1688, 1699,
  1716, 1758, 1824, 1938, 1960, 2038, 2040, 2922, 2924, 2930); Great-father Winter's 6961, which
  TrinityCore and QuestieDB put in 7021 and 7024's group; and whether the mage targets need their
  lead-ins (QuestieDB says not). Each correction is a row in `forever-quest-link-decisions.csv`, and
  the login clean-up covers its ticks.
- **Forever quests that may be for some classes only, left for everyone**: the game's records give no
  class, and nothing from Forever shows one for Stalk With The Earthmother (76156, 76160, 76240; Season
  of Discovery's warrior and shaman chain), Grant's Shield and Silvia's Sword (79362, 79363; its shaman
  quests), the 41 library books under Special (78124 to 84402; its mages' books) or Sparring Match (99108,
  "Though you are not a warrior"). A test in the game or a first-hand report makes each a row in
  `forever-quest-class-decisions.csv` ([forever.md](forever.md), "Class quests the game files under a
  zone"). Seen in passing: A Scribbled Letter (92479) is under the game's Warrior heading but sends the
  player to Tordrin Sternblade, "the new Hunter trainer" (91758), and QuestieDB calls it a hunter's;
  and the game gives Call of Earth's first step (92466) no race, where its next two are Horde's.
- **Forever's 1,414 pinless quests** have no pickup data in any source; the recorder is the way
  ([forever.md](forever.md)). About 60 of the new retail pins are for quests started by an object and about 120 by an
  item alone, and have no name; Forever names its pins after the object or item (game-parity.md, recommendation 12).
- **Pins and where they came from**: a pin does not record its source, and a new rule takes no pin
  away. A removal route (a decisions file like the unavailable quests') is open.
- **Uncategorized after the Infinite Research refile**: a plain
  `Place-UncategorisedQuests.ps1 -Refile 0` would move 30 more (28 by pin's map, 2 by storyline);
  look through them with `-WhatIf` ([menu-review.md](menu-review.md)).
- **265 quest IDs on pins or prerequisites with no quest row** (261 on pins only, 4 prerequisites
  only: 30490, 54130, 59174, 89285): parked since phase 2 of
  [data-cleanup.md](data-cleanup.md); the menu review found nothing new.

## Code to finish

- **README** says retail has "over 15,000" quest-giver pins and Forever "around 1,700"; check both at
  each release.

## The agreed order of work

From [game-parity.md](game-parity.md), decision 3, with what is done:

1. Profession skill fallback: **done** (#216).
2. Retail map pass: **done** (#219 carries its record).
3. **Built, waiting for the game:** the recorder on retail, with one probe for both games
   (recommendations 1 and 2). The addon half (#228) is released (112.7, untried) and waits for its in-game session;
   the merge tool (step 6d) has read Forever's first recording (11 October: the ledger only, no pin changed)
   and still waits for retail's, and Forever's importer reads its ledger (11 October 2026)
   ([quest-giver-recorder.md](quest-giver-recorder.md)); the secrecy watch of step 2b is built; the
   probe is on master as a dev-only addon (#232 to #237), and both games' first runs are in (9 and 10
   October; see "To try in game").
4. The consistency checks of `Audit-QuestTables.ps1` and `Remove-DuplicatePinQuests.ps1` on Forever's
   data (recommendations 4 and 5): **done** (#238).
5. Retail's profession skill data, after one in-game check of what `GetProfessionInfo` reports for an
   expansion's skill line (recommendation 3): the two lines are under "To try in game".
6. The dungeon journal on Forever (**done**, #241: the client has no Journal tables), the quest cache
   reader on retail (**done**, #246, [retail-quest-cache.md](retail-quest-cache.md)), the importer's
   `QuestLine` row counts (**done**, #239) (recommendations 9, 6, 7).
7. A review of Forever's hidden and test quests, after its launch on 4 November (recommendation 10).

8. The continent icons ([continent-pins.md](continent-pins.md)): the plan, then the probe's geometry
   pass before retail's 12.1.5 map pass, then the counting and the icons: **done** (#261 to #272, released in 112.8).

Also: the 12.1.5 sweep when the patch is live (13 or 14 October; the TOC lists both interface
numbers), a Warband-filter check on the Forever beta, and the dated changes of 1 April 2027
(releasing.md: the old completions format, and the login clean-up of `qcFormerlyExclusive` ticks).

After the retail run of the 12.1.5 sweep has been read, and #262 (the probe's geometry pass) has merged, and
before Forever's launch on 4 November: **rename the probe** from `QCForeverProbe` to `QCProbe`, as one pull
request with local steps after it ([probe-rename.md](probe-rename.md), planned 10 October 2026, target the
week of 19 October). Nothing is renamed before then.
