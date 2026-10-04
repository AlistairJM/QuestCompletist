<#
Gives each quest in data\quests.jsonl the title Blizzard's API has for it, from tools\quest_api_cache
(filled by Audit-QuestAccuracy.ps1), then rebuilds qcQuest.lua. The game shows its own title once a
quest's data has loaded, so our name only matters for English search and until then; keeping the
two the same means a quest is found under the name it's shown with.

Blizzard's title is copied exactly, including its odd spacing ("WANTED:  \"Hogger\"", with two spaces),
as that's what the game shows. Quests the API doesn't know keep their name.

  .\Sync-QuestNamesFromApi.ps1 -WhatIf     lists what would change
  .\Sync-QuestNamesFromApi.ps1             changes the quests
#>

param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

$cacheDir = Join-Path $ToolsDir "quest_api_cache"
$quests = Read-QuestData $DataDir
$changes = New-Object System.Collections.Generic.List[object]
$checked = 0
foreach ($quest in $quests) {
    $path = Join-Path $cacheDir "$($quest.id).json"
    if (-not (Test-Path $path)) { continue }
    $title = ([System.IO.File]::ReadAllText($path, $script:Utf8) | ConvertFrom-Json).title
    if (-not $title) { continue }
    $checked++
    if ($title -ceq $quest.name) { continue }
    $changes.Add([pscustomobject]@{ QuestID = [int]$quest.id; Ours = $quest.name; Blizzard = $title })
    Set-RecordField $quest 'name' $title
}

Write-Output ("{0} quests checked against the API: {1} names differ." -f $checked, $changes.Count)
if ($WhatIf) {
    $changes | Sort-Object QuestID | ForEach-Object { Write-Output ("  {0}: {1} -> {2}" -f $_.QuestID, $_.Ours, $_.Blizzard) }
    Write-Output "WhatIf: nothing changed."
    exit 0
}
if ($changes.Count -gt 0) { Save-QuestData $quests $DataDir $AddonDir }
