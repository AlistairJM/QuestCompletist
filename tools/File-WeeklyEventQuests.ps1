<#
Files the weekly bonus event quests (timewalking "... Path/Journey Through Time", "A Call to Battle",
"The Arena Calls", "Emissary of War", "The Very Best" and the rest) under the Weekly Events category,
listed under World Events in the menu. They used to be scattered: the catch-alls, Uncategorized, and
whichever zone the quest-giver stood in.

A quest is taken when Blizzard's quest API puts it in the "Weekly Event" quest category (409), or
when its name is one of the event families and the API names no other category. Many of the older
event quests are gone from the API, so the names are needed; the API check keeps out same-named
quests from elsewhere ("The Time to Strike" is also a Void Assaults quest).

Only field 5 changes. Safe to rerun: quests already filed there are left alone.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [switch]$WhatIf
)
$ErrorActionPreference = "Stop"

$families = '^(An? \w+ (Path|Journey) Through Time|A Call to (Battle|Delves)|The Arena Calls|Emissary of War|The World Awaits|The Very Best|The Time to Strike|Timeworn Keystone: .+)$'

$questFile = "$AddonDir\qcQuest.lua"
$content = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)

$categoryName = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcQuestCategories=\{(.*?)^\}').Groups[1].Value, '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) {
    $categoryName[$m.Groups[1].Value] = $m.Groups[2].Value
}
$target = @($categoryName.Keys | Where-Object { $categoryName[$_] -eq "Weekly Events" })
if ($target.Count -ne 1) { throw "Expected one Weekly Events category, found $($target.Count)" }
$target = $target[0]

$entryPattern = '(?m)^(\[(\d+)\]=\{\d+,"(?<name>(?:[^"\\]|\\.)*)",[^,]*,"(?:[^"\\]|\\.)*",)(-?\d+),'
$move = @{}
$from = @{}
foreach ($m in [regex]::Matches($content, $entryPattern)) {
    $questId = $m.Groups[2].Value
    $current = $m.Groups[3].Value
    if ($current -eq $target) { continue }
    $apiCategory = $null
    $cached = "$ToolsDir\quest_api_cache\$questId.json"
    if (Test-Path $cached) {
        $category = [regex]::Match([System.IO.File]::ReadAllText($cached), '"category":\{"key":\{[^}]*\},"name":"[^"]*","id":(\d+)\}')
        if ($category.Success) { $apiCategory = $category.Groups[1].Value }
    }
    if ($apiCategory -eq "409" -or ($m.Groups["name"].Value -match $families -and -not $apiCategory)) {
        $move[$questId] = $true
        $from["$current $($categoryName[$current])"] = 1 + $from["$current $($categoryName[$current])"]
    }
}

$moved = 0
$content = [regex]::Replace($content, $entryPattern, {
    param($m)
    if ($move.ContainsKey($m.Groups[2].Value)) { $script:moved++; return $m.Groups[1].Value + $target + "," }
    return $m.Value
})
if ($moved -ne $move.Count) { throw "Expected to move $($move.Count) quests, moved $moved" }

if (-not $WhatIf) { [System.IO.File]::WriteAllText($questFile, $content, (New-Object System.Text.UTF8Encoding $false)) }
"$(if ($WhatIf) { 'Would move' } else { 'Moved' }) $moved quests to Weekly Events ($target)"
$from.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "  from {0}: {1}" -f $_.Key, $_.Value }
