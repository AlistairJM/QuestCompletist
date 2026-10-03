<#
Gives each quest in qcQuestDatabase the title Blizzard's API has for it, from tools\quest_api_cache
(filled by Audit-QuestAccuracy.ps1). The game shows its own title once a quest's data has loaded, so
our name only matters for English search and until then; keeping the two the same means a quest is
found under the name it's shown with.

Blizzard's title is copied exactly, including its odd spacing ("WANTED:  \"Hogger\"", with two spaces),
as that's what the game shows. Quests the API doesn't know keep their name.

  .\Sync-QuestNamesFromApi.ps1 -WhatIf     lists what would change
  .\Sync-QuestNamesFromApi.ps1             changes qcQuest.lua
#>

param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [switch]$WhatIf
)

$questFile = Join-Path $AddonDir "qcQuest.lua"
$cacheDir = Join-Path $ToolsDir "quest_api_cache"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$content = [System.IO.File]::ReadAllText($questFile, $utf8)

function ConvertFrom-LuaString([string]$text) { return $text.Replace('\"', '"').Replace('\\', '\') }
function ConvertTo-LuaString([string]$text) { return $text.Replace('\', '\\').Replace('"', '\"') }

$changes = New-Object System.Collections.Generic.List[object]
$counts = @{ checked = 0 }
# A database entry repeats its ID as the first field: [123]={123,"Name",...
$pattern = '(?m)^\[(\d+)\]=\{\1,"((?:[^"\\]|\\.)*)",'
$evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
    param($m)
    $questId = $m.Groups[1].Value
    $path = Join-Path $cacheDir "$questId.json"
    if (-not (Test-Path $path)) { return $m.Value }
    $title = ([System.IO.File]::ReadAllText($path, $utf8) | ConvertFrom-Json).title
    if (-not $title) { return $m.Value }
    $counts.checked++
    $ours = ConvertFrom-LuaString $m.Groups[2].Value
    if ($title -ceq $ours) { return $m.Value }
    $changes.Add([pscustomobject]@{ QuestID = [int]$questId; Ours = $ours; Blizzard = $title })
    return "[$questId]={$questId,`"$(ConvertTo-LuaString $title)`","
}
$updated = [regex]::Replace($content, $pattern, $evaluator)

Write-Output ("{0} quests checked against the API: {1} names differ." -f $counts.checked, $changes.Count)
if ($WhatIf) {
    $changes | Sort-Object QuestID | ForEach-Object { Write-Output ("  {0}: {1} -> {2}" -f $_.QuestID, $_.Ours, $_.Blizzard) }
    Write-Output "WhatIf: qcQuest.lua not changed."
    exit 0
}
if ($changes.Count -gt 0) {
    [System.IO.File]::WriteAllText($questFile, $updated, $utf8)
    Write-Output "qcQuest.lua updated."
}
