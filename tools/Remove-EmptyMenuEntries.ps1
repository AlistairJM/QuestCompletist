<#
Removes menu entries whose category holds no quests, since they only ever open an empty list. The
category rows stay in qcQuestCategories, so an entry can be brought back with one line if quests
are filed there later.

Run it after anything that moves quests between categories (Place-UncategorisedQuests.ps1
-Refile). It refuses to empty a submenu completely; that needs a decision by hand. The
Uncategorized entry (category 0) is kept even when empty, so quests placed there later show up.
#>
param(
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [switch]$WhatIf
)
. "$PSScriptRoot\AddonData.ps1"

$quest = [System.IO.File]::ReadAllText("$AddonDir\qcQuest.lua", [System.Text.Encoding]::UTF8)
$questCount = @{}
foreach ($record in (Read-QuestData $DataDir)) {
    $questCount[[string]$record.category] = 1 + $questCount[[string]$record.category]
}
$categoryName = @{}
foreach ($m in [regex]::Matches([regex]::Match($quest, '(?sm)^qcQuestCategories=\{(.*?)^\}').Groups[1].Value, '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) {
    if (-not $categoryName.ContainsKey($m.Groups[1].Value)) { $categoryName[$m.Groups[1].Value] = $m.Groups[2].Value }
}

$menuFile = "$AddonDir\qcMenu.lua"
$lines = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllText($menuFile, [System.Text.Encoding]::UTF8) -split "`r`n")
$entry = '^\{(?:text=(?:(?!menuList)[^\r\n])*?,)?isTitle=false,notCheckable=false,hasArrow=false,arg1=(\d+),func=function\(button,arg1\)qcProcessMenuSelection\(button,arg1\);end\}(\}*),$'

$removed = New-Object System.Collections.Generic.List[string]
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $m = [regex]::Match($lines[$i], $entry)
    if (-not $m.Success -or $questCount.ContainsKey($m.Groups[1].Value) -or $m.Groups[1].Value -eq "0") { continue }
    $closers = $m.Groups[2].Value
    if ($closers) {
        # The entry closes its submenu, so the entry above takes over the closing brackets.
        if ($lines[$i - 1] -notmatch ';end\},$') { throw "Removing category $($m.Groups[1].Value) would empty its submenu" }
        $lines[$i - 1] = $lines[$i - 1] -replace ',$', "$closers,"
    }
    $lines.RemoveAt($i)
    $removed.Insert(0, "$($m.Groups[1].Value) $($categoryName[$m.Groups[1].Value])")
}

if (-not $WhatIf) {
    [System.IO.File]::WriteAllText($menuFile, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
}
"$(if ($WhatIf) { 'Would remove' } else { 'Removed' }) $($removed.Count) menu entries with no quests:"
$removed | ForEach-Object { "  $_" }
