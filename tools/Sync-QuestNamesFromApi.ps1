<#
Gives each quest in data\quests.jsonl Blizzard's title for it, then rebuilds qcQuestData.lua. The game shows its
own title once a quest's data has loaded, so our name only matters for English search and until then; keeping the
two the same means a quest is found under the name it's shown with. A quest takes the title of the first of these
that has one for it:
  1 Blizzard's API: the quest's record in tools\quest_api_cache (filled by Audit-QuestAccuracy.ps1, step 1)
  2 for a quest the API doesn't serve (a .404 file there): the newest retail quest cache,
    tools\retail_quest_cache_<build>.jsonl (step 2e; -Build reads another)
  3 for a quest the API doesn't serve and the cache lacks: the client's task table, tools\QuestV2CliTask.csv
    (step 1b), which titles world quests, bonus objectives and the other task quests
A quest none of them titles keeps its name, as does one with no file in the API cache yet.

Blizzard's title is copied exactly, including its odd spacing ("WANTED:  \"Hogger\"", with two spaces), as that's
what the game shows, with one exception: a title that starts with [DEPRECATED] is never taken. That's Blizzard's
mark on a quest it retired (8330 "[DEPRECATED]Solanian's Belongings"), and whether such a quest can still be done
is decided on its evidence in docs\plans\unavailable-quest-decisions.csv, not by its title; it keeps the name it
had, and is listed as not taken.

A source that is missing is named and skipped, except the API cache, without which nothing is checked. A quest
cache that looks partial (QuestCacheFiles.ps1) is warned about: the quests it lacks fall to the task table or keep
their names.

  .\Sync-QuestNamesFromApi.ps1 -WhatIf     lists every rename by source, and the titles not taken
  .\Sync-QuestNamesFromApi.ps1             renames the quests; a second run changes nothing

Tested by Test-SyncQuestNames.ps1.
#>

param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = '',
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\QuestCacheFiles.ps1"

$apiDir = Join-Path $ToolsDir 'quest_api_cache'
if (-not (Test-Path -LiteralPath $apiDir)) { throw "There's no $apiDir`: run Audit-QuestAccuracy.ps1 (step 1) first." }
$quests = Read-QuestData $DataDir
$skipped = @()

$apiTitles = @{}
$notServed = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($quest in $quests) {
    $id = [int]$quest.id
    $path = Join-Path $apiDir "$id.json"
    if (Test-Path -LiteralPath $path) {
        $title = ([IO.File]::ReadAllText($path, $script:Utf8) | ConvertFrom-Json).title
        if ($title) { $apiTitles[$id] = $title }
    } elseif (Test-Path -LiteralPath (Join-Path $apiDir "$id.404")) { [void]$notServed.Add($id) }
}

$cacheFile = ''
if ($Build) {
    $cacheFile = Join-Path $ToolsDir "retail_quest_cache_$Build.jsonl"
    if (-not (Test-Path -LiteralPath $cacheFile)) { throw "There's no $cacheFile." }
} else {
    $newest = Get-QuestCacheFiles $ToolsDir 'retail' | Select-Object -Last 1
    if ($newest) { $cacheFile = $newest.FullName; $Build = $newest.BaseName -replace '^retail_quest_cache_' }
}
$cacheTitles = @{}
$warning = @()
if ($cacheFile) {
    $rx = New-Object Text.RegularExpressions.Regex '^\s*\{"id":(\d+)'
    foreach ($line in [IO.File]::ReadLines($cacheFile)) {
        $m = $rx.Match($line)
        if (-not $m.Success -or -not $notServed.Contains([int]$m.Groups[1].Value)) { continue }
        $title = ($line.Trim().TrimEnd(',') | ConvertFrom-Json).title
        if ($title) { $cacheTitles[[int]$m.Groups[1].Value] = $title }
    }
    $warning = @(Get-QuestCacheWarning $cacheFile @($quests | ForEach-Object { [int]$_.id }))
} else { $skipped += 'the retail quest cache (tools\retail_quest_cache_<build>.jsonl, step 2e)' }

$taskTitles = @{}
$taskFile = Join-Path $ToolsDir 'QuestV2CliTask.csv'
if (Test-Path -LiteralPath $taskFile) {
    foreach ($row in (Import-Csv -LiteralPath $taskFile -Encoding UTF8)) {
        $id = [int]$row.ID
        if ($notServed.Contains($id) -and $row.QuestTitle_lang) { $taskTitles[$id] = $row.QuestTitle_lang }
    }
} else { $skipped += 'the task table (tools\QuestV2CliTask.csv, step 1b)' }

$sources = [ordered]@{ api = 'the API'; cache = $(if ($cacheFile) { "the quest cache of $Build" } else { 'the quest cache' }); task = 'the task table (QuestV2CliTask)' }
$titled = @{}; $renames = @{}
foreach ($key in $sources.Keys) { $titled[$key] = 0; $renames[$key] = New-Object System.Collections.Generic.List[object] }
$notTaken = New-Object System.Collections.Generic.List[object]
$untitled = 0
foreach ($quest in $quests) {
    $id = [int]$quest.id
    if ($apiTitles.ContainsKey($id)) { $source = 'api'; $title = $apiTitles[$id] }
    elseif (-not $notServed.Contains($id)) { continue }
    elseif ($cacheTitles.ContainsKey($id)) { $source = 'cache'; $title = $cacheTitles[$id] }
    elseif ($taskTitles.ContainsKey($id)) { $source = 'task'; $title = $taskTitles[$id] }
    else { $untitled++; continue }
    $titled[$source]++
    if ($title -ceq $quest.name) { continue }
    $change = [pscustomobject]@{ QuestID = $id; Ours = $quest.name; Blizzard = $title; Source = $source }
    if ($title.StartsWith('[DEPRECATED]', [StringComparison]::OrdinalIgnoreCase)) { $notTaken.Add($change); continue }
    $renames[$source].Add($change)
    Set-RecordField $quest 'name' $title
}

foreach ($name in $skipped) { Write-Output "Skipped, as it's missing: $name." }
$warning | ForEach-Object { Write-Output $_ }
Write-Output ("{0:N0} quests checked against the API: {1:N0} renamed." -f $titled.api, $renames.api.Count)
Write-Output ("{0:N0} quests the API doesn't serve: {1:N0} titled by {2} ({3:N0} renamed), {4:N0} by {5} ({6:N0} renamed), {7:N0} by neither, which keep their names." -f `
    $notServed.Count, $titled.cache, $sources.cache, $renames.cache.Count, $titled.task, $sources.task, $renames.task.Count, $untitled)
Write-Output ("Titles not taken, as they start with [DEPRECATED] ({0}):" -f $notTaken.Count)
$notTaken | Sort-Object QuestID | ForEach-Object { Write-Output ("  {0}: {1} keeps its name; {2} has {3}" -f $_.QuestID, $_.Ours, $sources[$_.Source], $_.Blizzard) }
if ($WhatIf) {
    foreach ($key in $sources.Keys) {
        Write-Output ("Renamed from {0} ({1}):" -f $sources[$key], $renames[$key].Count)
        $renames[$key] | Sort-Object QuestID | ForEach-Object { Write-Output ("  {0}: {1} -> {2}" -f $_.QuestID, $_.Ours, $_.Blizzard) }
    }
    Write-Output "WhatIf: nothing changed."
    exit 0
}
if (($renames.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum -gt 0) { Save-QuestData $quests $DataDir $AddonDir }
