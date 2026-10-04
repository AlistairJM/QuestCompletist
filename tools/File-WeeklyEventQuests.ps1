<#
Files the weekly bonus event quests (timewalking "... Path/Journey Through Time", "A Call to Battle",
"The Arena Calls", "Emissary of War", "The Very Best" and the rest) under the Weekly Events category,
listed under World Events in the menu. They used to be scattered: the catch-alls, Uncategorized, and
whichever zone the quest-giver stood in.

A quest is taken when Blizzard's quest API puts it in the "Weekly Event" quest category (409), or
when its name is one of the event families and the API names no other category. Many of the older
event quests are gone from the API, so the names are needed; the API check keeps out same-named
quests from elsewhere ("The Time to Strike" is also a Void Assaults quest).

Only the category changes, in data\quests.jsonl, then qcQuest.lua is rebuilt. Safe to rerun:
quests already filed there are left alone.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [switch]$WhatIf
)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\AddonData.ps1"

$families = '^(An? \w+ (Path|Journey) Through Time|A Call to (Battle|Delves)|The Arena Calls|Emissary of War|The World Awaits|The Very Best|The Time to Strike|Timeworn Keystone: .+)$'

$content = [System.IO.File]::ReadAllText("$AddonDir\qcQuest.lua", [System.Text.Encoding]::UTF8)
$categoryName = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcQuestCategories=\{(.*?)^\}').Groups[1].Value, '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) {
    $categoryName[$m.Groups[1].Value] = $m.Groups[2].Value
}
$target = @($categoryName.Keys | Where-Object { $categoryName[$_] -eq "Weekly Events" })
if ($target.Count -ne 1) { throw "Expected one Weekly Events category, found $($target.Count)" }
$target = [int]$target[0]

$quests = Read-QuestData $DataDir
$moved = 0
$from = @{}
foreach ($quest in $quests) {
    $current = [string]$quest.category
    if ($quest.category -eq $target) { continue }
    $apiCategory = $null
    $cached = "$ToolsDir\quest_api_cache\$($quest.id).json"
    if (Test-Path $cached) {
        $category = [regex]::Match([System.IO.File]::ReadAllText($cached), '"category":\{"key":\{[^}]*\},"name":"[^"]*","id":(\d+)\}')
        if ($category.Success) { $apiCategory = $category.Groups[1].Value }
    }
    if ($apiCategory -eq "409" -or ($quest.name -match $families -and -not $apiCategory)) {
        Set-RecordField $quest 'category' $target
        $moved++
        $from["$current $($categoryName[$current])"] = 1 + $from["$current $($categoryName[$current])"]
    }
}

if (-not $WhatIf -and $moved -gt 0) { Save-QuestData $quests $DataDir $AddonDir }
"$(if ($WhatIf) { 'Would move' } else { 'Moved' }) $moved quests to Weekly Events ($target)"
$from.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "  from {0}: {1}" -f $_.Key, $_.Value }
