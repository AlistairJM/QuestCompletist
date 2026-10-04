<#
Retypes quests stored as 1 (normal) that two independent sources say recur, in data\quests.jsonl,
then rebuilds qcQuest.lua:

  - the game client, via the /qc typecheck probe: with the quest's data loaded,
    C_QuestInfoSystem.GetQuestClassification answers Recurring (5), and
  - Blizzard's quest API flags it is_daily (-> 4) or is_weekly (-> 128, the addon's weekly type).

A quest flagged both daily and weekly, or also repeatable, is left alone.

Why both: loaded Recurring alone can't say daily from weekly, and the API flags alone have been
wrong about this addon's data before. Checked against 3,309 quests the API flags daily or weekly,
none of which the loaded client answered Normal.

Input: a copy of the SavedVariables file holding qcQuestTypeProbeResults (WoW drops it from the
live file once the probe is no longer in the TOC), and the API cache in quest_api_cache.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$ProbeResults = (Join-Path $PSScriptRoot 'quest_type_probe_results.lua')
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

if (-not (Test-Path $ProbeResults)) { throw "Probe results not found at $ProbeResults" }
$probe = [System.IO.File]::ReadAllText($ProbeResults)
$recurring = @{}
foreach ($m in [regex]::Matches($probe, '(?m)^\[(\d+)\] = "(\d+)\|[^|]*\|(\d+),[01-],([01t])",?\s*$')) {
    if ($m.Groups[2].Value -eq "1" -and $m.Groups[3].Value -eq "5" -and $m.Groups[4].Value -eq "1") { $recurring[$m.Groups[1].Value] = $true }
}
if (-not $recurring.Count) { throw "No loaded Recurring answers for type-1 quests in $ProbeResults" }

# The probe recorded each quest's type as it was then; only quests still typed 1 are candidates,
# so a rerun after an earlier retype finds only new cases.
$quests = Read-QuestData $DataDir
$retyped = @{ 4 = 0; 128 = 0 }
foreach ($quest in $quests) {
    $questId = [string]$quest.id
    if ($quest.type -ne 1 -or -not $recurring.ContainsKey($questId)) { continue }
    $cached = "$ToolsDir\quest_api_cache\$questId.json"
    if (-not (Test-Path $cached)) { continue }
    $json = [System.IO.File]::ReadAllText($cached)
    $isDaily = $json -match '"is_daily":true'
    $isWeekly = $json -match '"is_weekly":true'
    if ($json -match '"is_repeatable":true' -or ($isDaily -and $isWeekly)) { continue }
    $type = if ($isDaily) { 4 } elseif ($isWeekly) { 128 } else { continue }
    Set-RecordField $quest 'type' $type
    $retyped[$type]++
}

"Type-1 quests the loaded client calls Recurring: $($recurring.Count)"
"Quests retyped: $($retyped[4] + $retyped[128])"
foreach ($type in 4, 128) { if ($retyped[$type] -gt 0) { "  to type ${type}: $($retyped[$type])" } }
if ($retyped[4] + $retyped[128] -gt 0) { Save-QuestData $quests $DataDir $AddonDir }
