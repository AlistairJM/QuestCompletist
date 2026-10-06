# Filters for the map and the quest list

## Goal

The user, 6 October 2026: "why is filtering different for map vs list? For example you can hide daily
quests or repeatable quests from the list, but not from the map, and some filters the other way
around also".

## Why they differed

It was history, not design:
- **The original addon (109.5, 2018)** built the two sets separately.
  - The map got completed, low-level, profession, seasonal and in-progress filters.
  - The list got completed, low-level, profession and world quest filters.
  - Faction and race & class were shared.
- **Later versions** added each new filter to whichever view needed it first:
  - 109.97 added daily and repeatable to the list, unfinished requirements to the map, and covenant
    and warband to both.
  - The rebuild added no-data pins to the map, and "no longer available" to both.
- **109.97 also saved two map settings,** for world quests and for daily and repeatable quests. Neither
  had a checkbox, and nothing read them. Their defaults were dropped on 3 October.

Only three differences have a reason:
- **Show map icons** is the map's own switch.
- **Pins with no quest data:** the list only shows quests in the addon's data.
- **Non-active seasonal:** the list keeps holiday quests in their own World Events categories, so
  they're only seen by opening that holiday.

## Decision

The user, 6 October 2026, taking the recommendation:
- **A grid.** One row per filter, with a box for the map and one for the quest list.
  - Each view is set on its own: the user hides completed quests on the map but not in the list.
  - Seasonal and no-data pins keep only a map box.
  - Show map icons sits above the grid.
- **New boxes start off,** so nothing changes until a player ticks one. A filter the two views shared
  keeps the player's choice in both.
- **"Hide World Quests" becomes "Hide World and Weekly Quests":** world quests and weeklies share a
  type, so it always hid both.
- **111.5 waits** for this and the user's look at it in game.

The defaults are the user's own settings (#168), plus the new boxes off:

| Filter | Map | Quest list |
|---|---|---|
| Completed | on | off |
| In progress | on | off |
| Low level | off | off |
| Unfinished requirements | off | off |
| Other professions | on | on |
| Daily | off | on |
| Repeatable | off | on |
| World and weekly | off | on |
| Other faction | on | on |
| Other races and classes | on | on |
| Other covenants | on | on |
| Done by warband characters | off | off |
| No longer available | on | on |
| Non-active seasonal | on | |
| Pins with no quest data | on | |

## What changed

- **Settings:** every filter is saved as `QC_M_HIDE_<key>` for the map and `QC_L_HIDE_<key>` for the
  list. `QC_FILTERS` in `qcCore.lua` lists them, with each view's default, and the panel and the
  defaults are built from it.
- **Moving existing settings across** (`QC_SETTINGS_VERSION` 2), once per install:
  - The five shared settings (`QC_ML_HIDE_<key>`) go to both views.
  - The two dead map settings are removed, so the map's new world and weekly filter starts off.
    Most installs had `QC_M_HIDE_WORLDQUEST` saved as 1, which it had as a default.
- **One filter for both views,** `qcBuildViewFilter`. The same filter now behaves the same in both:
  - The list's completed and in-progress filters also treat a daily or weekly group's other quests
    as done once its limit is reached, as the map's did.
- **Counting:** the list's zone counter and the map's progress bars ignore the completed,
  in-progress and warband filters. The unfinished-requirements filter leaves quests out of both,
  as it already did on the map.
- **Tooltips follow their own view:**
  - the quest list tooltip's storyline follows the list's faction, race & class and warband filters;
  - a pin's progress bar follows the map's warband filter.
- **Texts:**
  - a "Quest List" heading, in every language and marked for review;
  - the game's own "Map" heading (`WORLD_MAP`);
  - "Hide World and Weekly Quests";
  - gone: the three section headings, and a "Hide Weekly Quests" nothing used.
- **The panel** is built from `QC_FILTERS`: about 250 lines of hand-placed checkboxes became about
  45. Its columns line up after the longest label in the player's language.

## Checks

- The Lua harness, 90 checks, covers:
  - moving old settings across, and a fresh install's defaults;
  - each view's own filters, including the new ones;
  - the zone counter;
  - the panel's boxes, their columns and what a click sets.
- The reachability reports for both games are unchanged apart from their timestamps, with 0 Lua
  errors. The check now runs the list's whole filter.
- In game: the panel's layout, and a filter of each kind on each view.

## Status

- 2026-10-06: #168 (the defaults) and this change in pull requests. Next: the user's look in game,
  then release 111.5.
- 2026-10-06: #168 and #169 merged, and released in 111.5.
