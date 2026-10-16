# Quest types: one-time, daily, weekly or repeatable

## Goal

Every quest's type should say whether it comes back, and how often, because the addon acts on it.
The types and the tools are in [../maintenance.md](../maintenance.md), step 3. What a wrong type
does:
- **A recurring quest typed one-time** gets a permanent completion tick the first time it's done,
  and "hide completed" then hides it for good, though it comes back.
- **A one-time quest typed daily, weekly or repeatable** never gets a tick: the addon doesn't
  record completions for recurring types. It counts as never done.
- **The wrong recurring type** only changes the icon and which filter hides the quest.

## The sources

- **The game client**, through the `/qc typecheck` probe (#42, run 2026-09-29 on 12.1.0.69933;
  the results are `tools\quest_type_probe_results.lua` in the main checkout, not in git). With a
  quest's data loaded, `C_QuestInfoSystem.GetQuestClassification` answers Recurring or Normal.
  Recurring can be trusted: none of the 3,309 quests Blizzard's API flags daily or weekly answered
  Normal. Normal can't: the game also says Normal for paragon caches, emissary bounties, Special
  Assignments and PvP rewards. The client only says how often a quest recurs for quests in the
  player's log.
- Recurring means daily or weekly, not repeatable: all 291 quests the API flags repeatable and
  nothing else answered Normal, 100 of them typed repeatable for years. So Normal says nothing
  against the API's repeatable flag.
- **Blizzard's quest API**: `is_daily`, `is_weekly` and `is_repeatable`. It leaves many weeklies
  unflagged, misses some repeatables, and has no record (404) of many recent and removed quests.
- **The client's `QuestV2` table** lists the quests the game can record as done.
  - It leaves out repeatable quests: none of the 500 the API flags repeatable are in it, against 98%
    of the rest.
  - The rest it leaves out are repeatables the API doesn't flag, such as Alterac Valley's supply
    turn-ins and the Darkmoon Faire's decks. So a quest it leaves out, which the server still knows
    (the probe loaded it), is repeatable.
  - A quest it lists isn't repeatable. It's one-time, daily or weekly.
- Neither the game nor the API can show a quest is one-time. With the quest in `QuestV2`, the API
  flagging nothing and the game saying Normal, it's one-time unless it recurs by a system of its
  own, such as emissary bounties, Legion Assaults, Special Assignments, crafting orders and Delves.
  That call is judgement: the quest's name, zone and questline.

## Done

| PR | Quests | What |
|---|---|---|
| #38 | 36 | Typed 128, but the API flags them daily or repeatable, and they aren't world quests (`Retype-FlaggedWorldQuests.ps1`). |
| #43 | 897 | Typed one-time, and both the game and the API say daily or weekly (`Retype-ProbeRecurring.ps1`). |
| #44 | 132 | Typed daily or weekly, but one-time by nature: Legion profession questlines, reputation milestones, pet battle introduction, dungeon and raid story quests. Judgement, by family. It left 346 of the 478 the game calls Normal: 202 that recur on a schedule, and 144 it couldn't place. |
| #133 | 135 | October 2026, below. |
| #153 | 587 | October 2026 review, below. |
| #156 | 603 | October 2026, the last sets, below. |
| 9 October probe | 53 | Typed one-time, and the game says Recurring, from the probe's first retail run (`Retype-ProbeRecurring.ps1`), below. |
| 12.1.5 sweep | 2 | Pilgrim's Bounty's "Sharing a Bountiful Feast", typed seasonal, made daily by Blizzard in 12.1.5. By hand, on the user's decision, below. |
| 12.1.5 probe | 25 | Typed one-time, and the game says Recurring, from the probe's 12.1.5 run (`Retype-ProbeRecurring.ps1`), below. |

**#133, October 2026.** The original data had a weekly type, 16, which the addon draws and counts as
one-time, so its 79 weeklies got a permanent tick: Wintergrasp's, Wrath raids' "… Must Die!",
the Warlords raid wings, Throne of Thunder's and "The Arena Calls".

- 68 of them, and 2 with no type (0), that the game and the API both say recur:
  `Retype-ProbeRecurring.ps1` now also takes types 0 and 16. 68 became weekly and 2 daily.
- By hand:
  - 9 more type-16 weeklies the API flags weekly, which the probe never loaded, became weekly.
  - The other 2 type-16 quests, "The Emerald Dreamcatcher" and "Investigate the Wreckage", became
    one-time. The game calls them Normal and the API flags neither.
  - 31 typed daily that the API flags repeatable only became repeatable: the Tillers' gifts, and
    Tiragarde Sound's and Stormsong Valley's turn-ins.
  - 3 emissary bounties typed daily became weekly, like the other emissaries: "Champions of
    Azeroth", "The Ankoan" and "The Unshackled".
  - 20 story quests typed daily or weekly became one-time. The game calls them Normal, the API
    flags neither, and each is in one of Blizzard's questlines whose other quests are one-time:
    - the Conquest Pit and "Ursoc, the Bear God" (Grizzly Hills);
    - "From Within" ×2 and "Into the Fray" (Behind Legion Lines);
    - "Assault on Broken Shore" (Legionfall Campaign);
    - "Not-So-Humble Beginnings", "Grimwing the Devourer", "Archdruid of Lore";
    - "Free Our Brothers and Sisters", "Together We Are Unstoppable";
    - "Delves: Measure Once, Cut Twice" (The Crimson Rogue).

    The exception is "Justice For The Fallen" (Zuldazar, the API's "The Shadow Hunter"): all four
    of its quests were typed daily.

Type 16 is now gone. Only the type field changed.

**#153, October 2026 review.** Every quest typed one-time that the game or the API says recurs,
decided with the user: the 224 the game calls Recurring and the 363 only the API flags.
`Retype-ProbeRecurring.ps1` now applies the rules for every one-time quest (its header has the table),
so a later sweep retypes new cases the same way:
- **245 to repeatable.** The API flags them repeatable and nothing else; the game says Normal for 191
  and hadn't loaded 54. Ember Court restocks, the Tillers' gifts, the Argent Dawn's scourgestones,
  Shattrath's and Nagrand's "More …" turn-ins, Iskaara's supplies, "The Horde Needs More …" and
  Ashran's trophies.
- **197 to daily.** The API flags them daily. The game says Recurring for 79 (also flagged
  repeatable, which the script used to skip), and hadn't loaded 118: Korthia, the Scourge
  invasion "Death Rising", Love is in the Air, the Maw, Ashran's artifact fragments, Nagrand's
  trophies and fishing lunkers.
- **145 to weekly.** The game says Recurring, and the API gives no frequency (2 of them it doesn't
  know at all) or flags both daily and weekly ("Pet Battle Challenge: Deadmines"). The API flags
  nearly every daily but leaves many weeklies unflagged: of the 100 quests the game calls Recurring
  and the API doesn't flag that were already typed daily or weekly, 85 were weekly. Hallowfall,
  Covenant Assaults, The Oasis, Archaeology, Suffusion Camps, the Forbidden Reach and Harandar's
  "WANTED".

Only the type field changed. Completions recorded while these were typed one-time go at the next
reset: dailies' and weeklies' as before, and repeatables' now with the dailies'.

**#156, October 2026: the last sets.** Decided with the user, using the client's `QuestV2` table
(The sources, above):
- **511 typed one-time became repeatable.** The server knows them but `QuestV2` leaves them out.
  `Retype-ProbeRecurring.ps1` has the rule now, against `QuestV2-<build>.csv` for the probe's build.
  - They include Alterac Valley's supply turn-ins, the Darkmoon Faire's decks, the Ahn'Qiraj and
    Warlords tier-token quests, Garrison invasions, the Ember Court's favors, Legion dungeon and
    Emerald Nightmare quests from the order hall table, and Torghast's and the Horrific Visions'
    quests.
  - The user's checks agreed: Wowhead marks "Avenger's Breastplate" repeatable, and Wowhead misses
    the mark on "Irondeep Supplies" and the Darkmoon decks, which the user knows are repeatable.
  - 2 of the 511 are internal entries already flagged unavailable.
- **The 326 typed daily or weekly that the game calls Normal**, the rest of #44's set:
  - **234 stay.**
    - 118 aren't in `QuestV2`, so they can't be one-time: the Legion raid quests in four copies,
      paragon caches, the Mechagon disc turn-ins.
    - 50 are "Conquest's Reward", flagged unavailable in #154.
    - 50 recur by a system of their own: Special Assignments, emissary bounties, the war efforts
      and tracking quests.
    - 16 belong to recurring families: the Legion Assaults (their questlines are weekly), "Peak
      Precision" (in "Siren Isle Weeklies"), the War Mode slayers, Crafting Orders, Delves and
      Deephaul Ravine.
  - **92 became one-time.** `QuestV2` lists them, the API flags nothing, the game says Normal, and
    Wowhead shows no schedule for any of the 8 the user checked.
    - 28 raid quests (Manaforge Omega, Liberation of Undermine, The Voidspire, Shadowlands' "Turning
      the Wheel").
    - 22 story quests, such as Suramar's "Insurrection" chapters, "Let's Fish!" and "Moments of
      Reflection".
    - 20 in the warfront zones (the warfront quests, Arathi Highlands and Darkshore), 8 "Paragon of
      …" and 6 "WANTED".
    - 8 others: three pet battle quests, Alterac Valley's anniversary quests, "The Stench of
      Revenge" and "Rearm, Reuse, Recycle". The last two now match their holiday's other quests.

Only the type field changed.

**The probe run of 9 October 2026.** The probe's first run on retail (build 12.1.0.69933, all 35,023
quests, 33,802 loaded against the 29 September type probe's 31,425) gave `Retype-ProbeRecurring.ps1`
53 quests that are typed one-time and that the game calls Recurring, among the 3,766 it does:

- **5 became repeatable (2):** "The Scrapbot Construction Kit" and the four Highmountain jetpack
  upgrades ("Upgrade Your Jetpack (Optional)", "Expedition GG-118 Micro-Jetpack" and the A.T.O.M.I.K.
  Mk. II pair).
- **48 became 128:** Covenant Assaults (7), Professions (9), The Oasis (7), The Forbidden Reach (5),
  Suffusion Camps (4), Hallowfall (4), Zaralek Cavern (3), Archaeology (2), Nazjatar (2), Silvermoon City
  (2) and a few others.
- Only the type field changed, no quest left the data, and `Test-QuestReachability.lua` reads the same
  before and after. Their pins now hide with the other repeatable and recurring quests by default.

**The 12.1.5 sweep, 15 October 2026.** "Sharing a Bountiful Feast", 14064 (Alliance) and 14065 (Horde),
the Pilgrim's Bounty feast, were typed seasonal (64) and became daily (4), keeping their Pilgrim's Bounty
tag, like the event's ten other dailies (14048, 14051, 14053 to 14055 and 14058 to 14062).
- Blizzard made them daily in 12.1.5: the API's records of 12.1.5_70077 flag them `is_daily` and those of
  12.1.0_68914 flag nothing, and the quest cache of 12.1.5.70391 gives them the daily flag (flags 4104,
  recurring daily), where 12.1.0.69933's gave flags 8 and no recurrence.
- No tool retypes a seasonal quest (`Retype-FlaggedWorldQuests.ps1` takes type 128 and
  `Retype-ProbeRecurring.ps1` the one-time types), so the change is by hand, on the user's decision.
- Only the type field changed. The holiday audit (step 2d) gives the same 13 findings, none new, and
  `Test-QuestReachability.lua` reads the same before and after. A completion recorded while they were
  seasonal goes at the next daily reset, as the other dailies' do.

**The probe's 12.1.5 run, 16 October 2026.** `Retype-ProbeRecurring.ps1` read the probe's file of 15
October for 12.1.5.70391 (`tools\retail_probe_70391\QCForeverProbe.lua`, the one `Find-ProbeResults`
picks: 35,544 quests, 29,823 loaded, 3,056 of them Recurring) and retyped 25 quests from one-time (1) to
128. `Retype-FlaggedWorldQuests.ps1` retyped none.
- **Why 128.** For each of the 25, the probe's record is a full one (level 70 to 90) and says Recurring,
  the API has a record and flags it neither daily, weekly nor repeatable, and `QuestV2` lists it, so it
  isn't repeatable. The script's table makes such a quest 128. The 12.1.5 quest cache agrees that they
  recur: each has the scheduler bit (the game's scheduler resets it) and no daily or weekly flag.
  - Archaeology (2): 41159 "Process of Elimination" and 41802 "The Gates of Valor".
  - Covenant Assaults (5): 63827 "Encouraging Words", 63952 "Heavy-Handed Tactics", 63969 "Looming
    Darkness", 63973 "Double Dromans" and 63974 "That's Going to Sting".
  - Profession quests (7): 66941 "Tremendous Tools", 66952 "The Gnoll's Clothes" and 72423 "Weathering
    the Storm" (Professions); 75286 "Blacksmith's Back" and 75288 "Enchanted Tales with Topuiz" (Zaralek
    Cavern); 93700 "Experience Tranquility" and 93709 "Stocking the Staples" (Silvermoon City).
  - The Oasis (2): 89057 "Pee-Yew de Foxy" and 89192 "A Hard Day's Work".
  - Silvermoon City's Void Assaults (2): 94385 "Void Assaults: Eversong Woods" and 94386 "Void Assaults:
    Zul'Aman".
  - Vaults of Atal'Utek (5, group quests): 96349 "Ancestral Gems", 96352 "Dark Charms", 96354 "A Balance
    Paid in Blood", 96360 "Wading In" and 96361 "Cursed Existence".
  - And 73715 "Driftwood Derby" (The Forbidden Reach) and 93425 "Sparks of War: Harandar".
- **No retype rests on a placeholder.** The run of 14 October saved 5,242 `cached` rows with level 0:
  records the client held only in part, whose facts are defaults, not the game's answer. The rerun of
  15 October asked 10,201 quests again, one at a time: those 5,242 and the 4,959 the server had refused.
  Its file differs from the 14 October one in exactly those 10,201 rows and has no `cached` row with
  level 0. (14 `ok` rows have level 0, the game's own answer; none of them is retyped.) On the 14 October
  file the script gives 18 of the 25. The other 7 (89057, 94386 and the five Vaults quests) were
  placeholders that day, 89057 a refusal, and full Recurring records on 15 October.
- **Nor on a refusal.** On the 9 October file (12.1.0.69933) the script retypes nothing, as #257 applied
  it. Of the quests typed one-time that the 9 October file calls Normal, the server refused 2,391 on 14
  October and still refused 693 of them on 15 October. The script's table retypes a quest that wasn't
  loaded only by the API's flags, and the API flags none of the 693 (687 records with no flag, 6 with no
  record), so none moves.
- **83530 "Hallowfall Fishing Derby" stays weekly (128).** #257 made it weekly from the 9 October run,
  whose record of it is a full one (level 79) and says Recurring; the 12.1.0.69933 quest cache gives it
  the scheduler bit. The server refused it on 15 October and its 14 October row was a placeholder
  (level 0, Normal), so 12.1.5 gives no answer against the 9 October one. The API flags nothing and the
  12.1.5 quest cache has no record of it. The `KEEP` row for 83531, which requires it, stays in
  [quest-table-decisions.csv](quest-table-decisions.csv), with this recheck in its reason.
- **#257's other retypes hold.** Of its 53, 16 say Recurring on 12.1.5 and the server refused the other
  37 (83530 among them); none says Normal.
- **The Hallow's End task quests step 6b added on 15 October (#347)** joined the data after the probe's
  list was made, so the probe didn't ask them and the script leaves them alone. Their step 6b types agree
  with the API's flags and the client's task table:
  - "Sugar Run" (92498, 93400, 95826), daily (4): the API flags them `is_daily`, and the task table gives
    the daily flag (`Flags_0` 0x1000).
  - "Candy Crafting" (97219, 98421, 98422), daily (4): the API has no record; the task table gives the
    daily flag.
  - "Community Candy Crawl" (98801), 128: the API has no record; the task table gives no daily or weekly
    flag and files it as a World Quest (QuestInfo 109).
  - "A Haunted Home" (93898), one-time (1): the API's record flags nothing, the task table gives no daily
    or weekly flag, and `QuestV2` lists it.

  The next probe run, with a list made from the data, asks them.
- **Step 2b.** 89057 requires 85721 "Killer Instinct" and 89192 requires 89254 "Shutterbug", both weekly,
  so with both now weekly too, their two `prereq: recurring quest` `KEEP` rows match no finding and were
  taken out. `Audit-QuestTables.ps1` then lists 120 findings, none new, and exits 0.
- Only the type field changed, no quest left the data, and `Test-QuestReachability.lua` reads the same
  before and after. The quest list's "Hide World and Weekly Quests" filter, on by default, now hides the
  25, and they no longer get a permanent tick.

## Still open

Nothing, as of October 2026. A sweep's new quests go through `Retype-ProbeRecurring.ps1` after
[the probe](../maintenance.md#in-the-game). What it leaves alone needs a review like the ones above.
