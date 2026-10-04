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
- **Blizzard's quest API**: `is_daily`, `is_weekly` and `is_repeatable`. It leaves many weeklies
  unflagged, and has no record (404) of many recent and removed quests.
- Neither source can show a quest is one-time, so that call is judgement: the quest's name, zone
  and questline.

## Done

| PR | Quests | What |
|---|---|---|
| #38 | 36 | Typed 128, but the API flags them daily or repeatable, and they aren't world quests (`Retype-FlaggedWorldQuests.ps1`). |
| #43 | 897 | Typed one-time, and both the game and the API say daily or weekly (`Retype-ProbeRecurring.ps1`). |
| #44 | 132 | Typed daily or weekly, but one-time by nature: Legion profession questlines, reputation milestones, pet battle introduction, dungeon and raid story quests. Judgement, by family. It left 346 of the 478 the game calls Normal: 202 that recur on a schedule, and 144 it couldn't place. |
| #133 | 135 | October 2026, below. |

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

## Still open (counted October 2026)

- **224 typed one-time that the game says recur.** 142 have no API flag, 79 are flagged daily and
  repeatable, 1 daily and weekly, 2 aren't in the API. The game shows they come back, but nothing
  says which recurring type. Families include Covenant Assaults, the Forbidden Reach, The Oasis,
  Archaeology fragments, Dragonflight's profession quests, Ashran's artifact fragments, fishing
  lunkers and Midnight's Harandar "WANTED" quests.
- **326 typed daily or weekly that the game calls Normal**, the rest of #44's set. Most recur by
  nature and stay: emissaries, paragon caches and "Supplies from…", Special Assignments,
  "Conquest's Reward" (not in the API, so maybe removed), warfronts, crafting orders, Delves and
  tracking quests. Still unsure:
  - Legion raid quests in four copies (The Nighthold, Tomb of Sargeras, Antorus);
  - recent raid quests (Manaforge Omega, Liberation of Undermine, The Voidspire);
  - warfront intro quests, and a few pet battle quests;
  - "Let's Fish!" (Mechagon) and "Moments of Reflection" (Antoran Wastes).
- **358 typed one-time that the API alone flags recurring** (240 repeatable, 32 daily and
  repeatable, 86 daily), which the game doesn't call Recurring. Not looked at yet.
