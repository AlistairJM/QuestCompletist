<#
Retypes quests the addon treats as one-time - 1 (normal), 0 (no type) or 16 (the original data's
weekly type, which the addon draws and counts as normal) - that the game client or Blizzard's quest
API say recur, in data\quests.jsonl, then rebuilds qcQuestData.lua.

The game client answers through the probe (tools\ForeverProbe, `/qcprobe quests`; before it, the retail
type probe of pull request #42): with the quest's data loaded,
C_QuestInfoSystem.GetQuestClassification says Recurring (5), Normal (7) or another class. Recurring
means daily or weekly: none of the 3,309 quests the API flags daily or weekly answered Normal, and
all 291 it flags repeatable and nothing else did, including 100 typed repeatable for years. So:

  API flags                       Recurring   Normal               another class        not loaded
  weekly (with daily or not)      128         left alone           128                  128
  daily (with repeatable or not)  4           left alone           4                    4
  repeatable only                 left alone  2                    2                    2
  none, or 404                    128         2 if not in QuestV2  2 if not in QuestV2  left alone

A recurring quest the API doesn't flag is most likely weekly: the API flags nearly every daily but
leaves many weeklies unflagged, and of the 100 such quests already typed daily or weekly in October
2026, 85 were weekly.

The client's QuestV2 table lists the quests the game can record as done, so it leaves out repeatable
ones: none of the 500 the API flags repeatable are in it, against 98% of the rest, and the rest it
leaves out are repeatables the API doesn't flag, such as Alterac Valley's supply turn-ins and the
Darkmoon Faire's decks. So a quest the server knows (the probe loaded it) that QuestV2 leaves out is
repeatable. The table must be the probe's build, QuestV2-<build>.csv, downloaded when missing: a
quest added since would look left out. Task quests are left alone, and so is a quest the API cache
hasn't fetched. See docs\plans\quest-types.md.

Input: the probe's saved variables, QCForeverProbe.lua, copied from the retail client into
tools\retail_probe_<build number>\ (the newest is taken), or a copy of the SavedVariables file holding
the #42 probe's qcQuestTypeProbeResults (tools\quest_type_probe_results.lua, used when there is no
probe copy; ProbeResults.ps1 reads either), the API cache in quest_api_cache, and QuestV2CliTask.csv
(task quests).
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$ProbeResults = '',
    [string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\ProbeResults.ps1"

if (-not $ProbeResults) { $ProbeResults = Find-ProbeResults $ToolsDir }
$probe = Get-ProbeQuests $ProbeResults $LuaExe
$classification = @{}
foreach ($id in $probe.Quests.Keys) {
    $answer = $probe.Quests[$id]
    if ($answer.Load -eq '1' -and $null -ne $answer.Classification) { $classification[$id] = $answer.Classification }
}
if (-not $classification.Count) { throw "No loaded answers in $ProbeResults" }
$probeBuild = $probe.Build

$clientQuests = "$ToolsDir\QuestV2-$probeBuild.csv"
if (-not (Test-Path $clientQuests)) {
    "Downloading QuestV2 for $probeBuild..."
    Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/QuestV2/csv?build=$probeBuild" -OutFile $clientQuests
}
$inClient = @{}
foreach ($row in Import-Csv $clientQuests) { $inClient[$row.ID] = $true }
if (-not (Test-Path "$ToolsDir\QuestV2CliTask.csv")) { throw "QuestV2CliTask.csv missing - needed to leave task quests alone" }
$isTask = @{}
foreach ($row in Import-Csv "$ToolsDir\QuestV2CliTask.csv") { $isTask[$row.ID] = $true }

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
        elseif ($classification.ContainsKey($questId) -and -not $inClient[$questId] -and -not $isTask[$questId]) { 2 }
    if (-not $type) { continue }
    Set-RecordField $quest 'type' $type
    $retyped[$type]++
}

"Quests the loaded client calls Recurring: $(@($classification.Values | Where-Object { $_ -eq 5 }).Count)"
"Quests retyped: $($retyped[2] + $retyped[4] + $retyped[128])"
foreach ($type in 2, 4, 128) { if ($retyped[$type] -gt 0) { "  to type ${type}: $($retyped[$type])" } }
if ($retyped[2] + $retyped[4] + $retyped[128] -gt 0) { Save-QuestData $quests $DataDir $AddonDir }
