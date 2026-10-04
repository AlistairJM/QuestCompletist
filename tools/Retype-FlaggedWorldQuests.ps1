<#
Retypes quests stored as 128 ("world quest or weekly") that Blizzard's quest API explicitly flags
as daily or repeatable, and that the client's task-quest table (QuestV2CliTask) has no row for -
so they are not world quests either. Changes data\quests.jsonl, then rebuilds qcQuestData.lua.

  is_daily      -> 4, daily. Resets daily instead of weekly; hidden by the daily filter.
  is_repeatable -> 2, repeatable (only when not also flagged daily).

Quests flagged is_weekly are left alone: 128 is also this addon's weekly type. So are quests the
API has no flag for at all. That is NOT evidence they are one-time: Dragonflight's weekly
profession quests, Shadowlands' "Trading Favors" and The War Within's weekly dungeon quests all
come back unflagged.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist')
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

$taskQuests = @{}
if (-not (Test-Path "$ToolsDir\QuestV2CliTask.csv")) { throw "QuestV2CliTask.csv missing - needed to tell a real world quest from a mistyped one" }
Get-Content "$ToolsDir\QuestV2CliTask.csv" | Select-Object -Skip 1 | ForEach-Object { $taskQuests[$_.Split(",")[0]] = $true }

$quests = Read-QuestData $DataDir
$retyped = @{ 4 = 0; 2 = 0 }
foreach ($quest in $quests) {
    if ($quest.type -ne 128) { continue }
    $questId = [string]$quest.id
    if ($taskQuests.ContainsKey($questId)) { continue }
    $cached = "$ToolsDir\quest_api_cache\$questId.json"
    if (-not (Test-Path $cached)) { continue }
    $json = [System.IO.File]::ReadAllText($cached)
    if ($json -match '"is_weekly":true') { continue }
    $type = if ($json -match '"is_daily":true') { 4 } elseif ($json -match '"is_repeatable":true') { 2 } else { continue }
    Set-RecordField $quest 'type' $type
    $retyped[$type]++
}

"Quests retyped: $($retyped[4] + $retyped[2])"
foreach ($type in 4, 2) { if ($retyped[$type] -gt 0) { "  to type ${type}: $($retyped[$type])" } }
if ($retyped[4] + $retyped[2] -gt 0) { Save-QuestData $quests $DataDir $AddonDir }
