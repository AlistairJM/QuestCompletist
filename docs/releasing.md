# Releasing a new version

How to turn what's merged on `master` into a release: version number and README, ZIP, tag,
changelog, CurseForge description, and tidying up the branches afterwards. Everything here is run
from the repository root in PowerShell.

If you're working with Claude Code in this repository, **"do a release"** runs all of this for you,
and gives you the ZIP, the changelog and the refreshed description to upload.

`README.md` is the addon's CurseForge description without the changelogs. Each release keeps the
two the same (steps 3 and 7).

## 1. Everything merged

Merge the pull requests that are ready. A pull request that changes the addon and hasn't been tested
in game yet waits until it has.

Check [Dated changes](#dated-changes) at the end: a change whose date has passed goes into this
release, in a pull request of its own.

## 2. Everything pushed

```powershell
git checkout master
git pull
git status
git log origin/master..master
```

- `git status` should show nothing but the old `QuestCompletistv*.zip` files.
- `git log origin/master..master` should print nothing.
- No local branch should hold commits that aren't on `master`. Anything left over is reported and
  decided on, not silently released or dropped.

## 3. Version number and README

On a `release/<version>` branch, change all three:
- `## Version:` in `QuestCompletist\QuestCompletist.toc`
- `## Version:` in `QuestCompletist\QuestCompletist_Camelot.toc`, WoW: Forever's
- `local QCADDON_VERSION` in `QuestCompletist\qcCore.lua`

The next version is the last tag plus 0.1 (110.9 follows 110.8), unless you choose otherwise. All
three files use Windows line endings; edit them in an editor or with perl, not Git Bash's `sed`, which
turns them into Unix ones.

Check `## Interface:` in `QuestCompletist\QuestCompletist.toc` too. The game calls an addon out of
date unless that line lists the client's interface number, which goes up with retail patches, minor
ones included: 12.1.5 is 120105. Each patch's page on
[warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/Patch_12.1.5) gives its number. When a patch is due,
list both numbers, the live one first (`## Interface: 120100, 120105`), so the release works before
and after it. WoW: Forever's TOC has its own number.

In the same pull request, bring `README.md` up to date. It's the addon's CurseForge description
without the changelogs, and step 7 publishes it as it is:
- Start from the live page, <https://www.curseforge.com/wow/addons/quest-completist>, not the
  README, as the description may have been edited there.
- Keep its layout: the title, Game versions, Features with bold subheadings, Handy clicks, Feedback
  and the "Viduus, Frostmane EU" heading.
- Change the description only when a release adds something big enough to mention. Check its
  numbers against the data: `Build-AddonData.ps1 -Check` prints the quest and pin counts.
- Like the changelog, it says what the addon does, not where its data comes from (see step 6).

Then check:

```powershell
& "C:\Program Files (x86)\Lua\5.1\luac.exe" -p (Get-ChildItem QuestCompletist\*.lua, QuestCompletist\Forever\*.lua).FullName
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-AddonData.ps1 -Check
```

The syntax check must be silent, and `-Check` must say all four generated files are up to date,
two for each game. Open the pull request and merge it.

## 4. ZIP

On `master`, after pulling the version change:

```powershell
git archive --format=zip --prefix=QuestCompletist/ -o QuestCompletistv<version>.zip HEAD:QuestCompletist
```

Check that it holds the same files as `QuestCompletist\` and shows the new version in the TOC.

## 5. Tag

Tag the merge commit of the version pull request, and push the tag:

```powershell
git tag -a v<version> -m "Quest Completist <version>"
git push origin v<version>
```

## 6. Changelog

Cover everything merged since the previous tag (`git log v<previous>..HEAD`), written for players,
not developers:

- Say what a player notices: "Map pins now show in Blackfathom Deeps and Gnomeregan", not what
  changed in the code.
- No pull request numbers, file or function names, field numbers, bitmasks, API names, tool
  changes, or counts that mean nothing in game.
- Don't go into where the data comes from: not Blizzard's API or the game's tables, other
  projects' databases, or the Forever beta. Say what changed, not how it was found.
- Leave out changes players can't see (docs, tools, tidying up), or fold them into one plain line
  such as "Smaller download and lower memory use".
- Short bullets under plain headings such as **New**, **Fixed** and **Improved**. Name the zones,
  quests, holidays or classes players will recognise.
- Start each bullet with a bold opener, e.g. "- **Quest names now show in your game's language** on
  non-English clients…".
- Say "fully close and restart World of Warcraft" only when the TOC's file list or the saved
  variables changed.

## 7. CurseForge description

The whole description is `README.md` as merged in step 3, then, after a `---`, the changelogs of
**the last 5 versions only**, newest first. The README never holds the changelogs.

- Older changelogs come from the page, or from the Files tab's "What's new" for versions no longer
  on it. Every changelog uses bold openers on its bullets.
- If the description needs a change at this point, change the README too, in a pull request of its
  own, so the two stay the same.

Upload the ZIP to CurseForge with the changelog, tick every game version the two TOCs list, and paste
in the refreshed description.

## 8. Delete merged branches

Once the tag is pushed, delete every branch that's fully merged, on GitHub and locally:

```powershell
git fetch origin --prune
git rev-list --count origin/master..origin/<branch>   # 0 means fully merged
git push origin --delete <branch> <branch> ...
git branch -d <branch>                                  # refuses a branch with unmerged work
```

- Delete a branch only when it has no commits that aren't on `master` and no open pull request
  uses it.
- Keep any branch with work that isn't on `master`, and any local branch an old worktree still has
  checked out; the app removes old worktrees itself.
- Note what was deleted and what's left.

## Dated changes

Changes that wait for a date rather than a number of releases. Once a date has passed, make the
change in its own pull request before the release.

- **From 1 April 2027: drop the old completions format.**
  - Remove `qcCompletedQuests` from `## SavedVariablesPerCharacter` in `QuestCompletist.toc`.
  - Delete `qcMigrateCompletions` and its call in `qcCore.lua`.
  - The changelog says to fully close and restart World of Warcraft. It also says that a character
    not logged in since 110.7 loses the quests marked on it by hand; the server resyncs the rest.

  Why it waits: [plans/load-and-memory.md](plans/load-and-memory.md), decision 2.
