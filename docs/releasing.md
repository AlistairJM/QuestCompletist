# Releasing a new version

How to turn what's merged on `master` into a release: version number, ZIP, tag, changelog,
CurseForge description, and tidying up the branches afterwards. Everything here is run from the
repository root in PowerShell.

If you're working with Claude Code in this repository, **"do a release"** runs all of this for you,
and gives you the ZIP, the changelog and the refreshed description to upload.

## 1. Everything merged

Merge the pull requests that are ready. A pull request that changes the addon and hasn't been tested
in game yet waits until it has.

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

## 3. Version number

On a `release/<version>` branch, change both:
- `## Version:` in `QuestCompletist\QuestCompletist.toc`
- `local QCADDON_VERSION` in `QuestCompletist\qcCore.lua`

The next version is the last tag plus 0.1 (110.9 follows 110.8), unless you choose otherwise. Both
files use Windows line endings; edit them in an editor or with perl, not Git Bash's `sed`, which
turns them into Unix ones. Then check:

```powershell
& "C:\Program Files (x86)\Lua\5.1\luac.exe" -p (Get-ChildItem QuestCompletist\*.lua).FullName
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-AddonData.ps1 -Check
```

The syntax check must be silent, and `-Check` must say both generated files are up to date. Open
the pull request and merge it.

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
- Leave out changes players can't see (docs, tools, tidying up), or fold them into one plain line
  such as "Smaller download and lower memory use".
- Short bullets under plain headings such as **New**, **Fixed** and **Improved**. Name the zones,
  quests, holidays or classes players will recognise.
- Start each bullet with a bold opener, e.g. "- **Quest names now show in your game's language** on
  non-English clients…".
- Say "fully close and restart World of Warcraft" only when the TOC's file list or the saved
  variables changed.

## 7. CurseForge description

Refresh the whole description: the description itself, then, after the `---`, the changelogs of
**the last 5 versions only**, newest first.

- Start from the live page, <https://www.curseforge.com/wow/addons/quest-completist>, not an old
  copy, as it may have been edited there.
- Keep its layout: the title, Game versions, Features with bold subheadings, Handy clicks, Feedback,
  the "Viduus, Frostmane EU" heading, `---`, then the changelogs.
- Change the description itself only when a release adds something big enough to mention. Check
  its numbers against the data: `Build-AddonData.ps1 -Check` prints the quest and pin counts.
- Older changelogs come from the page, or from the Files tab's "What's new" for versions no longer
  on it. Every changelog uses bold openers on its bullets.

Upload the ZIP to CurseForge with the changelog, and paste in the refreshed description.

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
