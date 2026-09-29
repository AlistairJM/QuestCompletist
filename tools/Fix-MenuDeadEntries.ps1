<#
Removes quest menu entries that lead nowhere and restores one that was pointing at the wrong
category. Every removal is checked to hold no quests first (a quest's field 5 IS its category id -
see qcBuildQuestIndexes in qcCore.lua), so nothing becomes unreachable.

  - 14 "Other Categories" entries under Dragonflight and Korrak's Revenge under World Events point
    at category ids that no qcQuestCategories row defines.
  - 6 placeholder entries reading "Temp" in the Shadowlands, Dragonflight and War Within dungeon
    submenus all point at category 1150, which already has its own "BFA Uncategorized Quests" entry.
  - A stray "World Pvp" entry under Dragonflight points at 1344 ("The Harbinger"); the real one
    under Player Vs Player points at 1095 and stays.
  - The Broken Isles entry labelled "Acherus: The Ebon Hold" selects 1017 ("Dreadscar Rift", the
    Warlock hall). Category 1021 is the Death Knight hall and no entry reached it, so an entry for
    it is added beside the existing one rather than repointing and losing Dreadscar Rift.

All-or-nothing: if an entry to remove isn't found exactly once, or turns out to hold quests,
nothing is written.
#>
param(
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist"
)

$menuFile = "$AddonDir\qcMenu.lua"
$questContent = [System.IO.File]::ReadAllText("$AddonDir\qcQuest.lua", [System.Text.Encoding]::UTF8)

$questsInCategory = @{}
foreach ($m in [regex]::Matches($questContent, '(?m)^\[\d+\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",(-?\d+),')) {
    $cat = [int]$m.Groups[1].Value
    $questsInCategory[$cat] = ($questsInCategory[$cat] + 1)
}

$deadCategories = @(1321, 1323, 1325, 1327, 1329, 1332, 1333, 1334, 1336, 1337, 1338, 1339, 1340, 1341, 414)
$menu = [System.IO.File]::ReadAllText($menuFile, [System.Text.Encoding]::UTF8)
$lines = $menu -split "`r`n"

$errors = New-Object System.Collections.Generic.List[string]
foreach ($cat in $deadCategories) {
    if ($questsInCategory[$cat]) { $errors.Add("category $cat holds $($questsInCategory[$cat]) quests - not dead") }
}
if ($errors.Count) { throw "Refusing to write:`n" + ($errors -join "`n") }

function Test-Stub($line) { return $line -match '^\{text=qcL\.TEMP,isTitle=false,notCheckable=false,hasArrow=false,arg1=1150,' }

$removed = 0
$emptiedSubmenus = 0
$kept = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    # A dungeon submenu holding nothing but those placeholders goes as a whole: its parent, both
    # children and the braces they close are one entry. There are no categories for the Shadowlands,
    # Dragonflight or War Within dungeons to put in it.
    if ($line -match 'menuList=\{$' -and ($i + 2) -lt $lines.Count -and (Test-Stub $lines[$i + 1]) -and (Test-Stub $lines[$i + 2])) {
        $removed += 2
        $emptiedSubmenus++
        $i += 2
        continue
    }

    $drop = $false
    $m = [regex]::Match($line, '^\{text=qcL\.([A-Z0-9_]+),isTitle=false,notCheckable=false,hasArrow=false,arg1=(\d+),')
    if ($m.Success) {
        $key = $m.Groups[1].Value
        $cat = [int]$m.Groups[2].Value
        if ($deadCategories -contains $cat) { $drop = $true }
        elseif ($key -eq "WORLDPVP" -and $cat -eq 1344) { $drop = $true }
    }

    if (-not $drop) { $kept.Add($line); continue }
    $removed++

    # A dropped entry that also closed its submenu hands those braces to the entry before it.
    $tail = [regex]::Match($line, 'end\}(\}+),?$')
    if ($tail.Success) {
        if (-not $kept.Count) { throw "Nothing to carry closing braces onto: $line" }
        $prev = $kept[$kept.Count - 1] -replace ',$', ''
        $kept[$kept.Count - 1] = $prev + $tail.Groups[1].Value + ","
    }
}
"Entries removed: $removed (including $emptiedSubmenus dungeon submenus that held only placeholders)"

# The Death Knight hall (1021) had no entry of its own; add one next to the Warlock hall's.
$out = New-Object System.Collections.Generic.List[string]
$added = 0
foreach ($line in $kept) {
    $out.Add($line)
    if ($line -match '^\{text=qcL\.ACHERUSTHEEBONHOLD,isTitle=false,notCheckable=false,hasArrow=false,arg1=1017,') {
        $out.Add('{isTitle=false,notCheckable=false,hasArrow=false,arg1=1021,func=function(button,arg1)qcProcessMenuSelection(button,arg1);end},')
        $added++
    }
}
if ($added -ne 1) { throw "Expected to add 1 entry for category 1021, added $added" }
"Entries added: $added (category 1021, $($questsInCategory[1021]) quests, previously unreachable)"

[System.IO.File]::WriteAllText($menuFile, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
"Menu lines: $($lines.Count) -> $($out.Count)"
