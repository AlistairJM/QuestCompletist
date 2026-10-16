# Open items and calls kept

What was decided on 7 and 8 October 2026, and what is left to come back to. Each item points at the
document that has the detail. When one is done, change its line here and say so in that document's
status.

## After 113.0

Everything open was merged and released as 113.0 on 12 October 2026. On the same day the user said to "go
ahead with your recommendations" and keep the rest for later; the decision rows below say which were
taken. What is left, in one place:

- **The data sources review (12 October 2026):** [data-sources-review.md](data-sources-review.md) went field by
  field through every source of both games. Its defects D1 to D19 (among them #320's board-quest prerequisites,
  the Adventurer class lists, the Paladin Rescue faction tags, Forever's own-breadcrumb prerequisites and its
  A Lesson to Learn givers), its 43 recommendations, its 14 decisions and its few in-game lines are the next
  work; its Status section logs what has been fixed or decided since, among them D16 (step 1c's names for
  the quests the API doesn't serve, 16 October 2026).

- **To build (decided):** rows 17 (the two race contradictions and the 19 stale masks), 18 (the 98
  Uncategorized quests whose sort names one category), 19 ("Starts from" only from the item or the quest
  window), 37 (one 1.5-point grouping radius for Forever's CMaNGOS spawns and start points) and 42 (the
  game's own offers in the requirements filter).
- **Needs the game first:** the lines under "To try in game", among them the hidden quest 90806 (per
  character or warband) and one `/qc holidays` per game. Row 15's five quests no longer need it: the user's
  decision 11b of the 12.1.5 sweep took the cache's rewards without them (done 16 October 2026).
- **Still the user's call:** rows 16, 36 and 39 (row 7 was decided on 13 and 15 October, and row 40 for the
  12.1.5 sweep, both done on 16 October; row 9, the last open part of row 6, was taken on 16 October, once
  the 12.1.5 retail probe run was read),
  and the 12.1.5 sweep itself comes once the patch is live.
- **Smaller follow-ups noted on the way:** Forever's 769 and 5124 (below, "Data to finish"); 93701 "Brittle
  and Brilliant", missing from the data; names for the 36 nameless Landfall pins; 114 pins drawn with the
  profession icon though none of their quests is a profession quest (the old daily icon number); the
  Forever recorder's leftovers (a report comparing the ledger with Forever's pins, the profession quest
  types in the recorded types, Monty and Nipsy on the Deeprun Tram with no map, and the next step-10 run
  with the probe's newer saved variables); and the open "ask" rows of `calendar-decisions.csv` (among them
  whether New Year's 8860 and 8861 follow the Fireworks Celebration, and whether the Forever beta's realm
  shares retail's calendar region).
- **Found while writing 113.0's notes:** 12 quests still list their own breadcrumb as the quest to do first
  (from the 109.97 data; step 2c's follow-ups no longer add such links); 98 Midnight quests whose only
  requirement is the hidden quest 90806 show greyed with no "Requires" line, so the pin says nothing of why;
  step 2g wasn't rerun after step 6b added 506 quests, so 502 of them gate on their own level (harmless, checked
  12 October 2026: their level already equals the client's formula, so a rerun changes nothing); Dreadscar Rift,
  Acherus: The Ebon Hold and Legion Uncategorized went under Other Categories in the Legion menu split
  without being named in the request; and game-api-review.md's recommendation 2 still gives the
  account-wide field as a reason, though the game counts an account-wide quest as done on every
  character (checked in game on 12 October 2026, so the addon needs no change for those quests).
- **The 12.1.5 sweep's decision 9, the 12.1.5 story content (option A): done on 16 October 2026** (branch
  `data/story-quests-12-1-5`). 33 quests Blizzard's API serves are in the data through step 6's gap route,
  each with an `ADD` row in `missing-quest-decisions.csv`: the 27 on no-data pins (lines 6221 "Sins of the
  Past", 6233 "What Slept Below", 6245 "To the Faithful", 6301 "Into the Labyrinth" and 6385 "The Labyrinth
  of Kindo'jan"), 98833, 98834, 95811 and 95813 (a start point, no pin yet) and 99306 and 99312 (no start
  point, no pin). Two categories with Blizzard's names (9b): 1515 "The Labyrinth of Kindo'jan" under
  Midnight > Other Categories and the raid's 1752 "The Unbinding of Kith'ix" under Dungeons & Raids >
  Midnight. The 34 old Uncategorized quests the inserter refiled stay refiled (9c). Campaign 349 stays
  gate-only (9e; maintenance.md, step 2c). 93420 stays an undecided candidate. Their pins came with the
  per-spot pins on 16 October 2026 (row 7: 17 of the 33 moved to their start points, 95811, 95813, 98833
  and 98834 got their first pins, 95187 went to Lor'themar Theron's pin); left from it: the probe and step 3
  for the new rows, the next sweep's.
- **Shipped untried in game in 113.0,** on the user's go-ahead: most of the addon changes since 112.9 (the
  waypoint fallback, the tooltip's Type line, the empty list's count, the menu splits, `/qc holidays`
  listing every ID, the requirements gates and their tooltip text). The lines under "To try in game"
  are the quickest way to see them.

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
- **No prerequisite names another profession's quest** (12 October 2026, "Apply all 45" and "Yes, 2b
  finding"). Dragonflight's renown crafting variants each need their set's renown quest, and the reward
  after a set skips the variants (`quest-link-decisions.csv`, step 2c). The 109.97 data had chained them
  across professions. `qcPrereq.CanTake` doesn't read professions: a character can learn one, and no
  choice in either game mixes them. Step 2b's `prereq: other profession` watches both games instead.
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
- **Midnight's "unfinished requirements" gates** (12 October 2026, data and the tooltip's text, untried in game).
  Two lines on retail say whether the hidden quest 90806, which the client's conditions accept in place of
  Voidstorm's 86509 and 86565 and which campaigns 284 and 324 require, is a character's or the warband's.
  On a character that finished the campaign and on one that hasn't:
  `/run for _,q in ipairs({90806,86509,86565}) do print(q,C_QuestLog.IsQuestFlaggedCompleted(q),C_QuestLog.IsQuestFlaggedCompletedOnAccount(q)) end`.
  The addon reads the first column. If 90806 is true only in the second on a character the game lets into
  Voidstorm's side lines, the check must read the warband's. And on an alt with no Midnight progress,
  `/run local m=2437 C_QuestLine.RequestQuestLinesForMap(m) C_Timer.After(3,function() for _,q in ipairs(C_QuestLine.GetAvailableQuestLines(m)) do print(q.questID,q.questName) end end)`
  lists what the game offers in Zul'Aman. The simulation with nothing done shows 56 Zul'Aman pins on a
  level-90 Blood Elf; any the game doesn't list is a leak no Blizzard data explains.
- **Waypoints without TomTom** (#300, built 11 October 2026, untried in game). With TomTom disabled, click a pin
  on a zone's map on each game and look for Blizzard's waypoint arrow. If nothing appears,
  `/run print(C_GameRules.IsGameRuleActive(Enum.GameRule.WorldMapTrackingPinDisabled), C_Map.CanSetUserWaypointOnMap(C_Map.GetBestMapForUnit("player")))`
  says which of the two refused.
- **Scaling quests below the level cap** (16 October 2026, row 9, untried in game; retail, one line). The
  probe ran only at the cap, so the levels below it follow the game's rule as TrinityCore has it. On a
  character below 90, `/run local q=11 C_QuestLog.RequestLoadQuestByID(q) C_Timer.After(2,function() print(UnitLevel("player"),C_QuestLog.GetQuestDifficultyLevel(q),C_QuestLog.IsQuestTrivial(q)) end)`
  asks about 11 "Riverpaw Gnoll Bounty" (level 1, scaling to 30): below 31 the second number should be the
  character's level and the third false, as the list's "[level]" shows; from 36 on, 30 and true.
- **Scaling quests in Chromie Time** (16 October 2026, row 9, untried in game; retail, one line). The
  ceilings come from a character at the cap, and TrinityCore takes a tuning through the character's
  Chromie Time options (`ConditionalContentTuning`), which the addon doesn't model. On a character in
  Chromie Time above level 30,
  `/run local q=11 C_QuestLog.RequestLoadQuestByID(q) C_Timer.After(2,function() print(C_PlayerInfo.IsPlayerInChromieTime(),UnitLevel("player"),C_QuestLog.GetQuestDifficultyLevel(q)) end)`
  should print true, the level, then 30, the list's "[30]". A third number above 30 means Chromie Time
  scales the quest further, so the list reads such quests too low there.
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
- **The anniversary's pins (retail, one look after 17 November 2026).** The 76 WoW's Anniversary quests
  (the 19 of #305 and, since #314, the 57 Guest Relations quests) are tagged on calendar ID 1808, which
  `/qc holidays` listed on 11 October 2026. Offline, with the default filters, their pins are hidden out
  of season (on Tanaris, Moira Thaurissan's and the Guest Relations givers' go: Raenie Fizzlebog's,
  Athelton Jones', Jepetto Joybuzz's, Maru's, Reshad's, Riko's and Bonenose's; the stack at Chromie loses
  its anniversary and Guest Relations quests and stays under Bobadormu's name with the weekly Timewalking
  quests 83274 and 85947; 47254's in the Caverns of Time, Rexxar's in Borean Tundra, Dapperdew's in
  Ardenweald and the Dalaran Survivor's in Dornogal go too, and Baron Revilgaz's stack in the Cape of
  Stranglethorn loses Scowling Rosa's quest) and shown with 1808 running. While the event runs, those pins should be on the map; before 17
  November they should not. Whether the Guest Relations quests are still offered then is an open fact of
  `calendar-decisions.csv`: if a giver offers nothing while its pin shows, say so.
- **Decision 10's other answers (retail, #314, untried in game).** `/qc holidays` should now list
  Dastardly Duos and the Scourge Invasion and the Ahn'Qiraj War Effort as not on the calendar in the
  next 12 months, and The Great Gnomeregan Run (696, 9 to 11 October 2027) as an entry, no longer under
  "Other calendar holidays". Vinnie Sweets' pin on the Isle of Dorn (the Dastardly Duos quests, stacked
  with Wodin the Troll-Servant's) stays off the map until Blizzard dates the event again, and the race's
  pin (47709, for gnomes, in New Tinkertown) shows only while 696 runs.
- **Call of the Scarab (retail, #315, untried in game; one look while it runs, from 21 January 2027).**
  `/qc holidays` should now list Call of the Scarab (638, 21 to 24 January 2027) as an entry, no longer
  under "Other calendar holidays". Offline, with the default filters, the 24 pins of its 16 turn-ins
  (12 for each faction, in Silithus and Ahn'Qiraj: The Fallen Kingdom) are hidden out of season and
  shown while 638 runs; Windcaller Yessendra's pin, which shares a stack with one turn-in pin of each
  faction in Ahn'Qiraj: The Fallen Kingdom, stays under her name. While the event runs, those pins should
  be on the map, and Kalimdor's Silithus icon should count 9 more quests than out of season.
- **The cups' pins (retail, one look while a cup runs; the next is the Kalimdor Cup, from 23 February
  2027).** The 16 Skyriding cup quests share one flag on the four cups' calendar IDs (#310).
  `/qc holidays` listed 1395 and 1400 on 11 October 2026; the Outland (1407) and Northrend (1429)
  Cups are next dated in 2028, beyond its 12 months, so nobody has seen the calendar serve them yet.
  Offline, with the default filters, out of season the Racing Enthusiast's pin in Stormwind or
  Orgrimmar, Lord Andestrasz's in Valdrakken and the three Holiday Enthusiasts' in Dornogal go (the
  Dornogal ones stay while another of their holidays runs), and any cup running brings them back.
  Now `/qc holidays` should show the cups under the Kalimdor Cup (1395), with the Eastern Kingdoms Cup
  (1400) on a line below it, and neither under "Other calendar holidays"; while a cup runs, those pins
  should be on the map. The Outland Cup (1407) comes into the command's 12 months from February 2027 and
  the Northrend Cup (1429) from August 2027: a line for each then shows the calendar serves it, which
  goes into `calendar-decisions.csv` (sweep step 2h lists both as open until then).
- **`/qc holidays` lists every ID of an entry** (built 12 October 2026, untried in game; both games):
  under each holiday's soonest event, a line for each of its other IDs the calendar has in the next 12
  months. On retail today that is the Eastern Kingdoms Cup (1400) under the Kalimdor Cup (1395); the
  rest of the list should read as before. `Test-SeasonalCalendar.lua` checks it offline.
- **The calendar, every sweep (step 2h of [maintenance.md](../maintenance.md)), both games:** one
  `/qc holidays` per game, a screenshot or a paste, set beside what `Review-Calendar.ps1` says it should
  print. The first comparison is retail's list of 11 October 2026, which the review reproduces exactly;
  Forever's full list hasn't been seen yet (the check of 11 October noted Winter Veil, 141, and the
  absence of 1879, Children's Week and the Darkmoon Faire only), so its first full paste is the next
  sweep's.
- **The pins of #223 and #224** (193 quests with only a start point, and 1,453 more from
  TrinityCore's start points) shipped in 112.5 without an in-game check: the user, shown a list of
  spots to check, said it was too much to check by hand and to go ahead (8 October 2026). When
  convenient, look at a few, and at these: quest 1036 "Avast Ye, Scallywag" (its pin is where the
  client puts its end, not at "Pretty Boy" Duncan), the class quests at Orgrimmar's and Stormwind's
  hubs, and the pins on the Caverns
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
  35,023 quests, 8,418 NPCs, 1,961 maps; the Forever beta, 70291), 10 October (Forever, 70338) and 14
  October (Forever 1.60.1.70374, a level 16 Night Elf rogue); the results are in
  `tools\retail_probe_69933\`, `tools\forever_probe_70338\` and `tools\forever_probe_70374\`. Pin names:
  10,562 of 10,564 retail pins and 1,503 of 1,503 Forever pins are the game's own. The map totals are
  those of 7 October (retail 439 offers; Forever none, 16 points of interest, again on 70374, whose
  continent geometry is 70338's). All twelve fact functions exist on both clients, `GetQuestExpansion`,
  `IsBreadcrumbQuest` and `IsStoryQuest` among them, but Forever returns inert values for most (every
  expansion -2, no tasks, campaigns or story quests). **Forever answered the two open questions on 14
  October** (`refusedFacts` in the quest run's row): of the 4,279 quests the server refused,
  `GetQuestLineInfo` and `GetQuestFactionGroup` answered none, while `IsAccountQuest` answered every one
  without loaded data (all false), as the other ten functions did; only
  `GetContentDifficultyQuestForPlayer` gave a value above 0. **Still open:** the same two questions on
  retail, whose 12.1.5.70391 files (`tools\retail_probe_70391\`) are still to read with
  `Read-ForeverProbe.lua <file> facts`, the 9 October results being the baseline; and whether the beta's
  answers follow the character, which needs a run on another character (the 14 October run was the same
  rogue's). Before the next run, copy the probe folder into the AddOns folders again and run
  `Get-LatestBuilds.ps1`.

## Decisions waiting for the user

| # | Decision | Recommendation | Detail |
|---|---|---|---|
| 1 | Add the about 535 player-facing task quests the database lacks (decision 9), with no pins | **yes, 11 October 2026, done**: `Add-TaskQuests.ps1` (step 6b) added 506 quests, the 535 less 29 internal test and placeholder entries: 260 of type 128 (world quests and weeklies), 37 dailies and 209 others that the list shows by default, 41 of all in Uncategorized; retail alone | [game-api-review.md](game-api-review.md), "Decisions to take"; [maintenance.md](../maintenance.md), step 6b |
| 2 | Pin the task quests already in the data that have a start and are not world quests (4,082 have a start and no pin: 3,148 of world-quest kinds, 758 of other kinds, 83 callings, 77 racing, 16 threat wrappers and bonus objectives) | **yes, 11 October 2026, done: the 758 kinds plus Dragonrider Racing** (the user: "yes, include racing, hold callings"). 814 quests are pinned: 737 of the 758 (21 start off their map) and the 77 racing quests (77 start gates on 12 maps, no giver). Pins went from 15,181 to 16,048 (15,971 for the 758 alone), quests with a pin from 24,931 to 25,745, and 844 of the 867 new pins have no giver. The racing pins show on the map at the default settings (its "Hide World and Weekly Quests" filter is off; the list's is on). **Still held, by their lines in `$noPinKinds` (deleting a line pins that kind):** the callings (83 daily quests with 98 places on 7 covenant sanctum maps, 86 nameless pins), until it is known whether the game still offers them, and the 11 Threat Wrapper (268) and 5 Bonus Objective with Completion Toast (283) quests that have a start, as the approval was for the 758, which has neither | quest-location-data-pipeline.md, "pins for the task quests that are not world quests" |
| 3 | 82449 "The Call of the Worldsoul", a task-table quest | **resolved by row 2 (11 October 2026): it is pinned at its client start, nameless** (a Meta Quest, one of the 758, in Dornogal); the hand entry is not needed | same |
| 4 | Item-started quests with a start point but no NPC (about 13% of all pins) | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): keep pinning them, as before | quest-location-data-pipeline.md, "pins from TrinityCore" |
| 5a | What a creature's offer lets a quest have a pin for ([quest-giver-recorder.md](quest-giver-recorder.md), "The merge tool", Adds): the holds on a quest that no creature offers (not in `QuestV2`, holiday, profession, a quest type other than 0, 1, 2, 4 and 128, and a calling or threat-wrapper task, the kinds of `$noPinKinds` the tool does not hold itself) are waived when a creature offers it; unavailable and internal-name quests stay held, and so do the system categories except the six of 5b (a task of another kind than world, bonus or hidden was in the list until 11 October 2026, when the pipeline began to pin those, and Landfall until 12 October 2026, when it stopped holding Landfall: row 34) | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): keep: an NPC offering a quest is the best proof it is a real pickup; the report counts the quests by class. This settles decisions 2 and 5 case by case for NPC-offered quests. To undo a class, edit `$isPinnable` in `Import-RecordedGivers.ps1`, or add a `KEEP` row for the quest | the plan, "Adds" |
| 5b | Which system category (Garrison Support, Torghast, Prey, Delves ...) may get pins from an offer | yes, 11 October 2026, done: allowed are World PvP 1095, Little Scales Daycare 1346, Upgrade System 1428, Warbands 1429, Delver's Headquarters 1430 and Weekly Events 1735, the categories where at least half the quests already stand on a pin with an NPC; held are Prey 1514 and Garrison Support 290 until there is more detail, and the 12 others, which are below 45% (Visions of N'Zoth and Time Rift are the nearest). `$allowedSystemCategories` in `Import-RecordedGivers.ps1` is the switch; the report lists the held ones by category; the TrinityCore pass's own skip is unchanged | the plan, "Adds" |
| 5 | The Landfall dailies (31 without a pin, 29 with one already) and the Silithus sigil quests (10), which look retired | **yes, 11 October 2026, done: KEEP rows, nothing flagged.** The evidence says they are not retired: the 73 Landfall dailies are served by the API, listed in both builds' QuestV2 and known to the server, and the sigil quests are the turn-ins of the yearly Call of the Scarab event (16 quests, not 10). 89 `KEEP` rows now record that. The pin pipeline's own Landfall hold went on 12 October 2026 (row 34), and the 31 got pins: 60 of the 73 have one now. Since 12 October 2026 the event has its own holiday entry (row 35, #315), so the 16 turn-ins' pins show only while it runs; their `KEEP` rows stay, as they are still not flagged | unavailable-quests.md |
| 6 | The remaining decisions 1 to 7 of the API review (recorder on retail and the probe additions are agreed and built, and so are text from the game and the waypoint fallback (#300), on 11 October 2026; the tracking toggles stay as they are, the user's call of 11 October 2026 ("leave the filters alone"); scaling-aware levels taken on 16 October 2026, row 9) | **all taken** (see that document) | game-api-review.md |
| 7 | Pin-per-quest (retail) or pin-per-spot (Forever) for nameless pins | **decided: per spot in both games, 13 October 2026; the spot is 1.5 map points, 15 October** (row 37's one radius; retail keeps its carry-over, and the grouping rule and the order a pin's giver is chosen in are one module both games call). **Tools built** (`tools\PinRules.ps1`, pull request tools/pin-rules-shared): retail's pipeline and Forever's importer group by it, and steps 6c and 6d take a quest whose giver they find off a shared nameless pin to the giver's pin instead of naming the spot after it. On the 12.1.5 tables it merges 2,745 of retail's 5,364 nameless candidate pins (13,549 pins instead of 16,294, no quest gaining or losing its last pin) and nothing on Forever. **Done, 16 October 2026** (branch `data/pins-12-1-5`): applied to `data\pins.jsonl` on 12.1.5.70391, with the 12.1.5 story quests; 2,746 of 5,368 nameless pins merged, and the pins went from 16,084 to 13,547 (2,622 nameless). 17 story quests moved to their start points and 95811, 95813, 98833 and 98834 got their first pins. Three names the run carried from another map were set right on the recommendations the user delegated: 14022 and 14036 nameless at their new starts in Dornogal and Silvermoon City, with their Goblin Commoner pins in Netherstorm and the Storm Peaks kept, and 95187 on Lor'themar Theron's pin by a `MOVE` row | game-parity.md, recommendation 11; quest-location-data-pipeline.md, "October 2026, one pin per spot" |
| 8 | Refresh retail's levels from the API: 1,589 quests differ from it (large blocks in Zaralek Cavern, Mechagon Island and the Emerald Dream, where the API gives a much lower minimum than we store), 4,955 have no API record, 224 are 0 | **not taken, 11 October 2026: option C chosen instead (row 14)**; the API minimum is used for the gate, the stored level is unchanged; a quest with no API record takes the client's level range, or keeps its level as the gate when it is on tuning 0 or has no source | client-tables-review.md (the note on `level`); maintenance.md, the data files |
| 9 | Scaling quests: the list bracket and the low-level filter read a scaling range's floor, so they judge a quest low level too early | probe first, agreed 10 October 2026: #282 adds `IsQuestTrivial` and the content difficulty to the probe's facts pass. **Taken, option C, 16 October 2026, on the user's word to go with the recommendations while they were away; built the same day (`Apply-QuestScaling.ps1`, step 2j):** the list's bracket, its sort and the low-level filter (list and map, both games' code) read the level the game scales a quest to: the character's, raised to the quest's minimum and held down at its new `maxLevel`, each content tuning's level at the level cap. The evidence, both runs read first: on the 12.1.5.70391 probe of 15 October (level 90) `IsQuestTrivial` is our rule on the scaled level for all 29,809 loaded quests with a level, and each of 771 tunings scales to one level at the cap; our stored level hid 9,753 quests the game calls not trivial (2,434 Midnight; the 14 October file gave the 8,043 and 1,978 first counted), and the new rule hides 4, part of 59 quests whose own level isn't the minimum the game holds them at (below, "Data to finish"). The ceilings are a character's outside Chromie Time; its redirected tunings are not modelled ("To try in game"). Forever's 70374 run gave every loaded quest its stored level, so Forever has no `maxLevel` and does not change. 27,637 retail quests got a `maxLevel`; no quest left the data | game-api-review.md, recommendation 4; maintenance.md, step 2j |
| 10 | Holiday flags for the retail events `qcHolidays` has none for: the four Dragonriding cups (16 quests, 12 with pins, which showed all year until they were tagged), Secrets of Azeroth, WoW Anniversary, Dastardly Duos, the weekly bonus events, and the 54 Ahn'Qiraj War Effort and Scourge Invasion quests | **WoW Anniversary: yes, 11 October 2026 ("build it with 1808 and the yearly check"), done in #305**: flag 524288 on calendar ID 1808, the 19 quests tagged, and step 2b reports each later year's row. **The Dragonriding cups: yes, 11 October 2026 ("yes, one shared cup flag"), done in #310**: one flag, 1048576 ("Skyriding Cups", the name the user chose on 12 October 2026, as the client now says "Skyriding Races"), on the four cups' calendar IDs 1395, 1400, 1407 and 1429, the 16 quests tagged, and step 2b reports a new cup's row ("<Region> Cup"). For the other events the recommendation was a flag per event, tied to the calendar ID that `/qc holidays` lists under "Other calendar holidays" while it runs. **The rest: answered by the user on 12 October 2026, done in #314**, so no row of `quest-holiday-decisions.csv` is PENDING: Dastardly Duos (flag 2097152 on 1599, 1673 and 1689, dated in 2025 only, 11 quests) and The Great Gnomeregan Run (flag 4194304 on 696, quest 47709) got entries of their own ("yes, add its own holiday", "yes, add the Gnomeregan Run holiday"); the 57 Guest Relations quests, which Blizzard's API files under Secrets of Azeroth, took WoW's Anniversary ("yes, tag them with the anniversary holiday"; step 2d reads that category as the anniversary); the 43 Ahn'Qiraj War Effort and 11 Scourge Invasion quests took their entries ("yes, tag them with their existing holidays"); and the 52 weekly bonus event quests (53 since #347 filed 93598 with them on 15 October 2026) and 25 others stay untagged as `KEEP` rows ("yes, leave them untagged"); two of the 25, the Candy Exchanges 92567 and 92569, were tagged Hallow's End under its heading on 15 October 2026 (#347), once the 12.1.5 API filed them under its 'Hallow's End' category. The next free flag was 8388608, which Call of the Scarab took on 12 October 2026 (row 35, #315); the next is 16777216. Each answer, and the calendar facts it rests on, is a row of `calendar-decisions.csv`, which sweep step 2h re-checks; open facts there ask whether the Guest Relations quests are offered while WoW's Anniversary runs, and whether the New Year's Eve quests 8860 and 8861 (no pins) should follow retail's Fireworks Celebration (658), on 31 December from 18:00 for 12 hours, which `/qc holidays` listed on 11 October 2026 | `quest-holiday-decisions.csv`; `calendar-decisions.csv`; maintenance.md, "Holidays" and steps 2d and 2h |
| 11 | Two quests of the holiday record: 56322 "Contained Alemental" (Wowhead lists Event: Brewfest) and the 12 "Bar Tab Barrel" quests, tagged Brewfest but still filed under the Dragon Isles zones, unlike the ten already under Brewfest | **yes, 10 October 2026, done**: 56322 tagged and the 12 Barrels refiled under Brewfest (31) | `quest-holiday-decisions.csv` |
| 12 | Forever's 29 untagged seasonal quests (none has a pin: 12 Children's Week and 6 Winter Veil by a hand list, 9 Scourge Invasion and 2 Ahn'Qiraj War Effort by an importer rule), and its calendar gaps: no dates for Children's Week or the Darkmoon Faire on the beta, and a nameless Winter Veil-like Holidays row, 1879, that the date decode puts from 15 November (not on the beta's calendar when checked in game, 11 October 2026) | **tagging: yes, 11 October 2026, done in #288**: the 29 are tagged (12 Children's Week and 6 Winter Veil from `forever-quest-holiday-decisions.csv`, 9 Scourge Invasion and 2 Ahn'Qiraj War Effort by the importer's heading rules). **Checked by the user in game, 11 October 2026:** `/qc holidays` on the beta lists Winter Veil as 141 (15 December to 2 January) and not 1879, so nothing is added; Children's Week and the Darkmoon Faire are not on the beta's calendar, which hides nothing, since the seasonal filter is the map's only and none of the 29 has a pin. These calendar facts (201, 263 and 264 undated; 1879 off the calendar and not listed) are rows of `calendar-decisions.csv`, which sweep step 2h re-checks | forever.md, "Seasonal quests with no holiday"; maintenance.md, "Holidays"; `calendar-decisions.csv` |
| 13 | A level of 0 or below reads as a level: 246 retail and 12 Forever quests show "[0]" in the list and count as low level for everyone | **yes, 10 October 2026, built in #283**: no level in the two readers; the sources for the 246 are under row 33 | `qcCore.lua`, the list row and the low-level filter |
| 14 | Retail's gate level from the content tuning (the other way to row 8, which uses the API's minimum): `level` stays the row's own and `qcQuestMinLevel` carries the gate, as on Forever; 1,828 quests change | **yes, option C, 11 October 2026, done**: 1,623 quests got a `minLevel` (the API's minimum, else the client's level range; step 2g of the runbook). The 17 quests on tuning 0 with no API minimum got none, so their own level stays their gate: a first rule gave five of them (9422, 50341, 54255, 54256, 89346) a gate of 0, and the user chose the same day to leave them as they were | [retail-quest-cache.md](retail-quest-cache.md), "Level"; the other way to row 8 |
| 15 | Backfill reputation rewards from the cache for the 2,043 quests the API has no record of that reward a visible faction | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): yes, after in-game checks of five quests. **Changed by the user's decision 11b of the 12.1.5 sweep (option B): from the newest cache only, with no check in game. Done 16 October 2026:** the joined 12.1.5 cache's 738 quests with a reward on a shown faction and no API record (1,028 rewards: 645 quests typed 128, 75 one-time, 14 daily, 3 repeatable, 1 type 0; 621 of them world quests), written by `Apply-ReputationBackfill.ps1 -CacheOnly`, with 2574 Dream Wardens added to `qcFactions`. The checks were dropped because the cache gives the API's figure for every reward both list: 11,093 of 11,093 on that cache (10,054 of 10,054 on its first, partial reading). The 1,439 quests of the 12.1.0 list that the 12.1.5 cache lacks keep no reward until a cache holds them: `-CacheOnly` refuses a compare made from an older cache than the newest in `tools\`. The step 2 baseline was rewritten on the same cache with `-AcceptPartialCache` (decided for the sweep: the cache holds 29,825 of our 35,606 quests, with the 33 story quests, and will not get fuller this sweep) | same, "Reputation"; maintenance.md, step 2; the quests are the `cache-only` rows of `quest_reputation_compare.csv` (`Compare-QuestReputation.ps1`) |
| 16 | Type changes the cache shows: 37 daily that are weekly, 92 repeatable that Blizzard calls daily or weekly, 4 that recur and are ticked for ever, 17 repeatable by the Darkmoon-deck rule, 38 one-time task quests, 21 test or deprecated titles | class by class | same, "Recurrence and flags" |
| 17 | Race changes: the two outright contradictions (quest 2, 27675), 19 stale masks, 49 starting-race narrowings, 28 where we show a quest to races the server denies | **contradictions and stale masks taken, 12 October 2026** (the user: "go ahead with your recommendations"), to build after 113.0; the narrowings and the 28 stay calls: the contradictions and stale masks yes; the narrowings are a call; the 28 class by class | same, "Races" |
| 18 | Sort fixes: 98 Uncategorized quests whose sort names one category, 27 profession misfiles | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): yes. **The 27 profession misfiles: done, 12 October 2026** (with the profession tags players reported missing): the 15 Tailoring quests moved from Leatherworking to Tailoring, and the 12 Ub3r-Spanner quests from Enchanting to Engineering with their bit, as rows of `quest-profession-decisions.csv`, with seven more profession quests that sat under a zone or another profession; step 1d now lists any quest filed under another profession's heading. The 98 Uncategorized quests still wait, to build after 113.0 ("After 113.0", above) | same, "Sort" |
| 19 | "Starts from" only from `ItemSparse.StartQuestID` or `QUEST_DETAIL`, never from the cache's `startItem` | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): yes, to build after 113.0 ("After 113.0", above) | same, "Start item" |
| 20 | The 22 placeholder-named quests that still show in default lists (menu review R08) fail the step-7 evidence rules: flag them anyway? | **yes, 11 October 2026, done**: the same call as 5 October on the internal and test entries; all 22 flagged (86645 and 94815, client task quests, with the builder's reason 3), 240 flags and 481 `KEEP` rows now | [menu-review.md](menu-review.md), question 20 |
| 21 | One submenu shape for every expansion (R28) | **yes, 11 October 2026, done**: Main Zones and Other Categories for Draenor and The Broken Isles; Outland, Northrend and The Maelstrom stay flat | [menu-review.md](menu-review.md), question 21 |
| 22 | Midnight: move Founder's Point and Razorwind Shores into Other Categories (R27) | **yes, 10 October 2026, done** | [menu-review.md](menu-review.md), question 22 |
| 23 | Split Lordaeron into Lordaeron, Quel'Thalas, Gilneas and Tol Barad (R26) | **yes, 10 October 2026, done**: named from the client's maps | [menu-review.md](menu-review.md), question 23 |
| 24 | Merge Darkmoon Island into Darkmoon Faire and four one-quest entries into their zones (R15, R31) | **yes, 11 October 2026, done**: the 14 quests moved, the five categories removed with their menu entries, and the zone table sends the old maps to the targets, so the sweep tools file new quests there | [menu-review.md](menu-review.md), question 24 |
| 25 | Names that repeat, groups and categories that share a name, Forever's "Invasion" (R17 to R21, R25, F03) | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): leave; if it matters, show the menu path in the list header (no new text) | [menu-review.md](menu-review.md), question 25 |
| 26 | Entries empty by default and tiny entries (R29, R30, R39, F06, F07, F09) | **yes, 11 October 2026, done**: all kept; an empty list says "Quests hidden by your filters: N" on both games | [menu-review.md](menu-review.md), question 26 |
| 27 | Rated PvP, 86 of 87 quests unavailable (R06) | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): keep | [menu-review.md](menu-review.md), question 27 |
| 28 | Class Quests has no Evoker (R05) | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): leave | [menu-review.md](menu-review.md), question 28 |
| 29 | Ordering rule for Retail's lists (R33) | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): keep the hand order | [menu-review.md](menu-review.md), question 29 |
| 30 | Forever: split Seasonal, and Deeprun Tram and Special loose (F04, F05) | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): leave until after the 4 November launch | [menu-review.md](menu-review.md), question 30 |
| 31 | Remove the 83 unused category definitions (R32) | **yes, 11 October 2026, done**: 82 removed with their table rows and 12 locale keys; Island Expeditions (1130) stays, because two tools still name it | [menu-review.md](menu-review.md), question 31 |
| 32 | A start within a map point of an edge goes on the map the client's row for it names. 26064 was moved by hand to Stonetalon Mountains (10 October 2026); 15 other quests have the same shape and their client start on the edge map: Mulgore's Jin'Zil (5) and Devo (2), Stonetalon's Grimfang (2), Dread Wastes' Taran Zhu (4) and Garrosh (1), Crystalsong Forest's Xink (1). All were on the other map before "pins at the start" | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): leave them where the client puts them; if the user wants the rule ("prefer the map the other points are on", tried at 1 point, 16 quests including 26064), it is a small change to `Build-QuestLocationData.ps1` and a rerun of step 6, and the Mulgore camp's 7 quests are the nearest case to 26064 | [quest-location-data-pipeline.md](quest-location-data-pipeline.md), "a start on the edge of a map" |
| 33 | Retail's real minimums where we store 0, from the sources checked on 10 October 2026 ([retail-quest-cache.md](retail-quest-cache.md), "Level"). 22 quests have their own API record with a real minimum: 16 Garrison "Your Second ... Work Order" quests at 10 (3 of them sit on TrinityCore's tuning 0, which disagrees), 3 at 80 (64159, 64162, 64163) and 3 at 90 (62355, 89403, 91632); 90751 reads 80 from a neighbour's range only. 191 have an API minimum of 1 and stay 0, since a 1 would hide them as low level for a high-level character, as every retail quest with a minimum of 1 is today; the rest are tuning 0, test or tracking quests, or have no source | **yes, 10 October 2026, done**: the 22 set to the API's minimum, the rest left at 0 | the 22 `level` values in `data/quests.jsonl`, then a rebuild |
| 34 | Landfall's hold in the pin pipeline (`$landfall` in `Build-QuestLocationData.ps1`, "whose dailies look retired"): 44 Landfall quests had no pin, 31 of them with a TrinityCore start point; row 5's evidence says the dailies show no sign of being retired | **yes, 12 October 2026 ("yes, drop the Landfall hold"), done**: the hold is gone from `Build-QuestLocationData.ps1`, and `Import-RecordedGivers.ps1` no longer counts Landfall as a hold it waives. The 31 got pins at 37 places: 36 new nameless pins (TrinityCore has no spawn for their starters) and 32450 on Blood Guard Gro'tash's pin, its starter's; no other pin changed. 60 of the 73 have a pin now; the other 13 have no start point in any source. Pins went from 16,048 to 16,084 | [quest-location-data-pipeline.md](quest-location-data-pipeline.md), "Landfall's pins"; row 5; unavailable-quests.md |
| 35 | A holiday flag for Call of the Scarab (Holidays row 638, 21 to 23 January, every year): the 16 quests of 45747 to 45762 and, by the analyst's count, about 29 more of the event by name | **yes, 12 October 2026 ("yes, add the Call of the Scarab holiday"), done in #315**: `qcHolidays` has "Call of the Scarab", flag 8388608, on row 638 (for every region, 72 hours from 21 January every year), which retail `/qc holidays` listed under "Other calendar holidays" on 11 October 2026 and now lists as the entry. The 16 turn-ins 45747 to 45762 (24 pins, in Silithus and Ahn'Qiraj: The Fallen Kingdom, which now show only while the event runs) and the two "Call of the Scarab" quests 45785 and 45787 (no pins) are tagged, with 18 `SET` rows. The analyst's "about 29 more" are 28 quests, left untagged for the user (row 39). Its facts (638 dated every year; served, seen 11 October 2026) are rows of `calendar-decisions.csv`, which sweep step 2h re-checks | row 5; unavailable-quests.md; `quest-holiday-decisions.csv`; `calendar-decisions.csv`; maintenance.md, "Holidays" |
| 36 | How a place's visits are counted when several of the maintainer's files hold the same visits: the probe's file is cumulative, so a spot seen 3 times is 3 in each of four files and 12 in the sum, and the sum decides which of two rows 0.1 apart seeds a place | change it to the largest number any one own source gives (the sources describe the same visits, as the plan says); it moved 1 Forever pin by 0.1 on today's ledger, and it is a change to `Get-RecordedPlaces`, which retail's step 6d shares, so it is left as it is until you say. Measured again on 12 October, with the ledger of #298 (the pins committed then follow the sum): the largest-number rule would put Thundris Windweaver back at 37.4,40.1 (5 visits in the addon's file, against 3 in each probe file at 37.4,40.2), but move Cerellean Whiteclaw 35.8 to 35.7, Gubber Blump 45 to 44.9 and "WANTED: Murkdeep!" 37.3 to 37.2, 0.1 each, as their two rows then tie and the lower one wins; so it is not a clean fix either. Measured again on the ledger of 14 October (build 70374, 326 rows): the sum now puts Thundris at 37.4,40.1 (22 visits against 15) and Gubber Blump at 36.1,44.9 (a tie, 6 against 6, which the lower row wins), where the largest-number rule would put them too, and the user accepted both moves with that import; the rule would still move Cerellean Whiteclaw and "WANTED: Murkdeep!" 0.1 each, as above | [quest-giver-recorder.md](quest-giver-recorder.md), "Known limits" (5); [forever.md](forever.md), "The importer reads the ledger" and "A rerun of the import" |
| 37 | Whether Forever's importer should group a giver's CMaNGOS spawns, and a quest's client start points, by the 1.5-point near-place test (`Test-NearPlace`) as it now groups recorded places, instead of the 3-point box both still use (the pin-spacing verdict of 7 October 2026). Measured on scratch copies (build 70338, each import followed by step 9; the same on today's ledger and on #298's): the start points change nothing. The spawns give 4 more pins, 1,698 to 1,702, for three givers whose spawns stand 1.5 to 2.2 points apart: Theramore Lieutenant (Dustwallow Marsh, quest 1220) 2 more, 2.0 and 2.2 points from its nearest pin; Lunar Festival Emissary (Ironforge, 8870 to 8872) 1, 1.85; Argent Quartermaster (Darnassus, six Scourge Invasion quests) 1, 1.52. So 10 quests gain another pin (all of them already had one) and none loses one. The CLUCK! chicken (3861), which gets one pin per map at its biggest group of spawns, moves on 3 of its 9 maps (Elwynn Forest 1.9, Duskwood 4.6, Wetlands 9.0 points), because smaller groups make another group the biggest. Step 9 leaves the new pins, as they are more than 0.5 apart | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): yes for both, so one radius holds for every Forever pin and for retail's; the 4 pins are NPCs that do stand apart, and the chicken only moves to another of its groups (if it should stay, its biggest group can still be counted at 3 points), to build after 113.0 ("After 113.0", above) | [forever.md](forever.md), "The importer reads the ledger" |
| 38 | Whether a recorded place more than a point from CMaNGOS's spawn should still win over the spawn. Today it does, and the review list names it ("recorded spot far from CMaNGOS"). The one case measured is Darcy (NPC 379, CMaNGOS's "Waitress", Lakeshire, Redridge Mountains, map 1433), who starts "A Free Lunch" (129): the probe's file of 11 October recorded her at 21.6,45.4, 1.10 points from her spawn at 21.53,44.3. CMaNGOS has her walk a 16-point path (`MovementType` 2), about 1.4 points end to end, pausing 12 to 32 seconds at five of its points; the spawn is one end of the path, and the recorded place is 0.11 from the point where she waits longest (32 seconds). They differ because she walks: both are places she stands | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): keep the recorded place winning (where a player found her is first-hand, and here it lies on her own path), and keep the review row so a far place is looked at each sweep. **Applied 14 October 2026:** the import of build 70374 moved Darcy's pin to 21.6,45.4, and the user accepted it | [forever.md](forever.md), "The importer reads the ledger"; the review list, `tools\forever_import_review.csv` |
| 39 | Call of the Scarab's other quests (row 35's "about 29 more"), found on 12 October 2026 and left untagged: 28 in all, none with a pin, a flag or a row in the decisions files. **14 meat turn-ins**, 45637 to 45643 (Horde) and 45729 to 45735 (Alliance): Sandworm Meat, Crunchy Spider Legs, Chilled Meat, Crocolisk Tails, Raw Tiger Steaks, Raw Clefthoof Meat and Lean Shanks, repeatable in our data. Blizzard's API serves them under the area Silithus (1377), each rewards 20 Qiraji Commendations of its faction (the currency of the 16 tagged turn-ins), and their text asks for meat to wake the colossi of Silithus; they are not in `QuestV2` of 12.1.0 or the 12.1.5 PTR. **14 world quests**, 45651, 45654 to 45657, 45674 and 45675 (Horde) and 45736 to 45742 (Alliance): The Ruins of Ahn'Qiraj: Ossirian, Ahn'Qiraj: C'Thun, The Colossus of Ashi, Lesser Wind Stones, Silithyst, The Colossus of Regal and The Colossus of Zora. The API has no record of them; both builds' `QuestV2` lists them, and TrinityCore has them as world quests (QuestType 3); our data has them as types 1, 4 and 128. Nothing names the event for them but their titles and their place in its ID range. No API category, TrinityCore game event or heading names Call of the Scarab for any of the 28 | the user's call. Tagging the meat turn-ins rests on their text and reward; the world quests on their names and IDs alone. Either way no pin changes (none has one) and the list doesn't change (the seasonal filter is the map's alone); out of season Kalimdor's Silithus icon would stop counting 45742 (The Colossus of Zora, Alliance, type 1), the only one of the 28 a continent icon counts, and a tag keeps step 6's TrinityCore placement from ever pinning a quest | `quest-holiday-decisions.csv`; maintenance.md, "Holidays" |
| 40 | The task quests step 6b added on 11 October (row 1) that the client gives a start: the next run of step 6 pins 175 of them at 202 places (186 new pins, and 11382 and 11386 join Wind Trader Zhareem's), as no kind of theirs is in `$noPinKinds`: kind 0 77, World Event 82 52 (Founder's Point's "Snail Mail" quests among them), Group 1 20, Important Quest 282 12, World Boss 289 5, Meta Quest 284 4, Heroic 85 2, Dungeon 81 2, Raid 62 1. Found while dropping the Landfall hold (row 34), whose rounds left them out | **yes, pin them all, World Event included (the user, for the 12.1.5 sweep's decision 5), done 16 October 2026** (branch `data/pins-12-1-5`): World Event stays out of `$noPinKinds`. The run pinned 184 task quests with a start: 174 of these (the 175th, 97128, is a Lair World Quest in 12.1.5's task table, which `$noPinKinds` holds since #337), 98379 and 98390 from step 6b's 12.1.5 run, and 8 Hallow's End quests, which follow the calendar; by kind 0 83, World Event 52, Group 20, Important Quest 14, Meta Quest 6, World Boss 4, Heroic 2, Dungeon 2, Raid 1. 11382 and 11386 joined Wind Trader Zhareem's pin | [quest-location-data-pipeline.md](quest-location-data-pipeline.md), "Landfall's pins" (Checks) |
| 41 | Quests that teach a profession: 32684 "You Want Fish?" and 32685 "No Fishing Pole Necessary!" (Fishing), 31279 and 31486 "Everything I Know About Cooking" and 31281 "So You Want to Be a Chef..." (Cooking) carry their profession since 12 October 2026, as Blizzard files them under it, so "Hide Other Profession Quests" hides them from the characters that lack it, whom they are for (in 2013 the game offered 32685 to a character without Fishing) | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): keep them tagged, as Blizzard files them; `KEEP` rows untag them if not | `quest-profession-decisions.csv`; maintenance.md, step 1d |
| 42 | The game's own offers in the requirements filter (game-api-review.md, recommendation 9): five choices set out on 12 October 2026 for the quests no data gates (186 on the Midnight maps): (1) besides never hiding a quest the game offers, hide a storyline step that starts on the open map when the game has answered for that map without listing it (task quests and quests in no storyline stay with the data); (2) on the open zone map's pins and their tooltips first, the continent icons in a later pull request, not the quest list; (3) ask on every map open and change, as Blizzard's map does, keep each map's answer for the session, drop all answers when a quest is accepted, handed in or removed and on a level or renown change, and count an empty answer as none; (4) one shared code path for both games, switched on by what the game supports (Forever's beta answers every map with an empty list, so nothing changes there); (5) no "offered now" tooltip line for now | **taken, 12 October 2026** (the user: "go ahead with your recommendations"): all five as recommended, to build after 113.0, with a few lines to try in game | game-api-review.md, recommendation 9 |

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
  look through them with `-WhatIf` ([menu-review.md](menu-review.md)). **Done on 16 October 2026:** the
  gap inserter's run filed 34 (30 by pin's map, 2 by storyline, 2 by API area; maintenance.md, step 6),
  kept on the user's word (the 12.1.5 sweep's decision 9c); a `-WhatIf` run now places none of the 779
  left in category 0.
- **238 quest IDs on pins or prerequisites with no quest row** (234 on pins only since the 27 story
  quests of 16 October 2026 went in, 261 before; 4 prerequisites only: 30490, 54130, 59174, 89285): parked since phase 2 of
  [data-cleanup.md](data-cleanup.md); the menu review found nothing new. Since 12 October 2026 the
  tooltip and the pins' "Requires" text leave such a quest out and still count it, as for the
  client's hidden 90806 (`qcPrereq.Text`).
- **Forever quests with no profession that need a profession quest** (step 2b's `prereq: other
  profession`, 12 October 2026): 769 "Kodo Hide Bag" needs 768 "Gathering Leather" (Skinning), and 5124
  "Fiery Plate Gauntlets" needs 5103 "Hot Fiery Death" (Blacksmithing). A character without the
  profession never meets them. Each wants a profession for the quest, or its link removed in
  `forever-quest-link-decisions.csv`, on evidence; until then both are `KEEP` rows of
  `forever-quest-table-decisions.csv`, so step 10's check passes. Once both are settled, `Test-QuestTooltip.lua`'s
  profession check can take quests with no profession too.
- **What still shows with "unfinished requirements" hidden** on a level-90 character with no Midnight
  progress (12 October 2026, after the client's conditions and the campaign's chapter order): Eversong 67
  of 200 pinned quests, Silvermoon 96 of 214, Zul'Aman 56 of 197, Harandar 63 of 174, Voidstorm 18 of 144,
  The Coiled Isle 49 of 82. Blizzard's API names no required quest for any of the 186 shown on the last
  four maps, and their lines have no condition the client lets us read, so no source gates them.
  Most are 12.1 side lines (Coiled Isle's 6264 shows all 11 steps). Ways on: the game's own offers at run time
  ([game-api-review.md](game-api-review.md), recommendation 9), or a reviewed per-line list. Also left:
  - The recurring links Blizzard doesn't name were dropped (544). That also shows Saltheril's Haven's 20
    dailies and weeklies (line 5841, Eversong) and Broken Throne's 4 dailies (5951, Zul'Aman) to a
    character that hasn't unlocked them; neither line has a condition the client lets us read.
  - Campaigns 357 to 359 (Val and Naigtal, 12.1) have only a world-state condition (5703); Voidstorm's
    continent count at level 80 is 31 (54 before), mostly those.
  - Zul'Aman's line 6011 needs line 5724 done or a warband-wide test (ModifierTree type 383) that a
    prerequisite can't say, so it has no gate.
- **59 retail quests the game holds at a minimum their own level isn't** (16 October 2026, row 9's check).
  Each is on a tuning whose level at the cap is the quest's `minLevel`, so it doesn't scale and gets no
  `maxLevel`. The list's bracket, its sort and the low-level filter therefore read its own `level`, where
  the game reads the minimum. `Apply-QuestScaling.ps1 -WhatIf -Examples 60` (maintenance.md step 2j) lists
  them by id; 31 were loaded in the 15 October probe.
  - **50 below their minimum.** The low-level filter hides such a quest once the character is 6 levels
    above its own level, but the game calls it trivial only from 6 levels above its minimum. By minimum:
    30: 24428 (level 1). 35: 28165, 31497, 32806, 32807, 32816 and 33249. 45: 40753. 50: 31 quests from
    50417 to 51874 (50417 "Ruin Has Come", level 10, is hidden from a character of level 50 to 55). 70:
    91843, 91864, 91868 and 91871 (the Recaps, level 10). 80: 76140, 82586 and 85085 (level 70). 90:
    41368 "Lost Mail" and 47148 "Something Different" (level 10), 58273 and 58274 "Servant of N'Zoth"
    (level 50). Only the four with a minimum of 90 show this at the cap: they are the 4 the low-level filter
    still hides there, though the game calls them not trivial.
  - **4 above it:** 52182, 52244, 52312 and 53310, level 50 with a minimum of 10, the game's level for them
    at the cap. The list shows them as [50].
  - **5 of level 0:** 38204 and 38205 (minimum 40), and 96746, 96995 and 97128 (minimum 90). They get no
    bracket and are never hidden.

  Retail's `level` is refreshed by no tool (row 8). The ways to fix it: a hand change of `level` to the
  minimum, on this evidence; a rule that does that for every such quest; or giving these quests
  `maxLevel` = `minLevel`, which makes `qcShownQuestLevel` return the minimum at every character level. The
  last widens row 9's rule (a ceiling only where it is above the minimum), so it is a decision for the user.
- **93701 "Brittle and Brilliant"**, a Midnight trainer quest of Silvermoon City, is in the 12.1.0.69933
  quest cache (quest info 267, Professions) and not in the data; 93707 and 93713 are only in `QuestV2`. The
  12.1.5.70391 cache lacks it, so `Find-MissingQuests.ps1`, which reads the newest cache, files it as untitled.

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
