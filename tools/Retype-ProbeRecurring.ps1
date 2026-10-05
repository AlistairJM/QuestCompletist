<#
Retypes quests the addon treats as one-time - 1 (normal), 0 (no type) or 16 (the original data's
weekly type, which the addon draws and counts as normal) - that the game client or Blizzard's quest
API say recur, in data\quests.jsonl, then rebuilds qcQuestData.lua.

The game client answers through the /qc typecheck probe: with the quest's data loaded,
C_QuestInfoSystem.GetQuestClassification says Recurring (5), Normal (7) or another class. Recurring
means daily or weekly: none of the 3,309 quests the API flags daily or weekly answered Normal, and
all 291 it flags repeatable and nothing else did, including 100 typed repeatable for years. So:

  API flags                       Recurring   Normal       not loaded, or another class
  weekly (with daily or not)      128         left alone   128
  daily (with repeatable or not)  4           left alone   4
  repeatable only                 left alone  2            2
  none, or 404                    128         left alone   left alone

A recurring quest the API doesn't flag is most likely weekly: the API flags nearly every daily but
leaves many weeklies unflagged, and of the 100 such quests already typed daily or weekly in October
2026, 85 were weekly. A quest the API cache hasn't fetched is left alone. See
docs\plans\quest-types.md.

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
$classification = @{}
foreach ($m in [regex]::Matches($probe, '(?m)^\[(\d+)\] = "\d+\|[^|]*\|(\d+),[01-],([01t])",?\s*$')) {
    if ($m.Groups[3].Value -eq "1") { $classification[$m.Groups[1].Value] = [int]$m.Groups[2].Value }
}
if (-not $classification.Count) { throw "No loaded answers in $ProbeResults" }

# Candidates are the quests typed one-time now, not when the probe ran, so a rerun after an
# earlier retype finds only new cases.
$oneTimeTypes = @(0, 1, 16)
$quests = Read-QuestData $DataDir
$retyped = @{ 2 = 0; 4 = 0; 128 = 0 }
foreach ($quest in $quests) {
    if ($oneTimeTypes -notcontains $quest.type) { continue }
    $questId = [string]$quest.id
    $cached = "$ToolsDir\quest_api_cache\$questId.json"
    if (Test-Path $cached) {
        $json = [System.IO.File]::ReadAllText($cached)
    } elseif (Test-Path "$ToolsDir\quest_api_cache\$questId.404") {
        $json = ''
    } else { continue }
    $isDaily = $json -match '"is_daily":true'
    $isWeekly = $json -match '"is_weekly":true'
    $isRepeatable = $json -match '"is_repeatable":true'
    $recurring = $classification[$questId] -eq 5
    $normal = $classification[$questId] -eq 7
    $type = if ($isWeekly) { if (-not $normal) { 128 } }
        elseif ($isDaily) { if (-not $normal) { 4 } }
        elseif ($isRepeatable) { if (-not $recurring) { 2 } }
        elseif ($recurring) { 128 }
    if (-not $type) { continue }
    Set-RecordField $quest 'type' $type
    $retyped[$type]++
}

"Quests the loaded client calls Recurring: $(@($classification.Values | Where-Object { $_ -eq 5 }).Count)"
"Quests retyped: $($retyped[2] + $retyped[4] + $retyped[128])"
foreach ($type in 2, 4, 128) { if ($retyped[$type] -gt 0) { "  to type ${type}: $($retyped[$type])" } }
if ($retyped[2] + $retyped[4] + $retyped[128] -gt 0) { Save-QuestData $quests $DataDir $AddonDir }
