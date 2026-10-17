<#
Step 2l of a sweep (docs/maintenance.md): the quests' covenants (covenant in data\quests.jsonl, qcQuestCovenant)
checked against the client's own data and filled where ours has none, as recommendation 21 of the data sources
review has it (docs/plans/data-sources-review.md), taken with the client tables audit's opportunity 4 on 17 October
2026. Retail only: WoW: Forever has no covenants.

The client names a quest's covenant in its task condition (QuestV2CliTask.ConditionID), in the conditions of the
quest lines and campaigns it's on and of its campaign chapter (CampaignXCondition), each read by QuestConditions.ps1
as the covenant every way through the condition needs (PlayerCondition.CovenantID, ModifierTree type 288), and in its
heading: the quest cache's sort (step 2e) naming one of the covenants' "<covenant> Callings" headings. A quest that
one covenant names gets that covenant, as a bit (1 shifted by the covenant's ID, qcCovenantsBits). A quest that several
name, as the chapters of a quest line all four covenants' campaigns share (60287, 60289, 61355, 62837, 62882), is
open to each of them and stays untagged.

It downloads the build's QuestSort and Covenant into tools\ (<table>-<build>.csv) when they aren't there, reads the
quest cache of -Build (tools\retail_quest_cache_<build>.jsonl), or of the newest build before it, or -QuestCacheFile,
and reports:
  - the quests that get a covenant: one the client names, where ours has none;
  - findings for a decision, which it leaves as they are: a quest ours tags with another covenant than the client's,
    and one ours tags that several covenants name;
  - how many of ours the client doesn't name (a baseline; none are removed).
-WhatIf reports without writing. Exit 0, or 1 when there are findings.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-QuestCovenants.ps1 -Build <retail build> -WhatIf
#>
param(
    [string]$Build = '',
    [string]$ToolsDir = '',
    [string]$DataDir = '',
    [string]$AddonDir = '',
    [string]$QuestCacheFile = '',
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $Build) { throw 'Give -Build: the build of the client tables to read.' }
if (-not $ToolsDir) { $ToolsDir = $PSScriptRoot }
if (-not $DataDir) { $DataDir = Join-Path $PSScriptRoot '..\data' }
if (-not $AddonDir) { $AddonDir = Join-Path $PSScriptRoot '..\QuestCompletist' }
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\QuestConditions.ps1"
. "$PSScriptRoot\QuestCacheFiles.ps1"

function Get-BuildTable([string]$table) {
    $path = Join-Path $ToolsDir "$table-$Build.csv"
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path -Headers @{ 'User-Agent' = 'QuestCompletist-tools' }
    }
    return $path
}

$records = Read-QuestData $DataDir
$quests = @{}
foreach ($q in $records) { $quests[[int]$q.id] = $q }

$taskPath = Join-Path $ToolsDir 'QuestV2CliTask.csv'
if (-not (Test-Path $taskPath)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/QuestV2CliTask/csv?build=$Build" -OutFile $taskPath }
$c = Import-ClientConditions $ToolsDir $Build
$taskConditions = @{}
foreach ($t in (Import-Csv $taskPath)) { if ($t.ConditionID -ne '0' -and $quests.ContainsKey([int]$t.ID)) { $taskConditions[[int]$t.ID] = [int]$t.ConditionID } }
$headings = Get-CovenantHeadings (Import-Csv (Get-BuildTable 'QuestSort')) (Import-Csv (Get-BuildTable 'Covenant'))

if (-not $QuestCacheFile) {
    $QuestCacheFile = Join-Path $ToolsDir "retail_quest_cache_$Build.jsonl"
    if (-not (Test-Path $QuestCacheFile)) {
        $older = @(Get-QuestCacheFiles $ToolsDir 'retail' | Where-Object { [version]($_.BaseName -replace '^retail_quest_cache_') -lt [version]$Build } | Select-Object -Last 1)
        if ($older.Count) { $QuestCacheFile = $older[0].FullName }
    }
}
$sorts = @{}
if (Test-Path $QuestCacheFile) {
    Get-QuestCacheWarning $QuestCacheFile $quests.Keys
    foreach ($line in [IO.File]::ReadLines($QuestCacheFile)) {
        if ($line -match '^\{"id":(\d+),.*"sort":(-?\d+)' -and $quests.ContainsKey([int]$Matches[1])) { $sorts[[int]$Matches[1]] = [int]$Matches[2] }
    }
    "Headings from $(Split-Path -Leaf $QuestCacheFile)."
} else { "No quest cache for $Build or a build before it at $ToolsDir, so no heading is read." }

$client = Get-ClientCovenants $c $taskConditions $sorts $headings
$add = New-Object System.Collections.Generic.List[object]
$differ = New-Object System.Collections.Generic.List[string]
$several = New-Object System.Collections.Generic.List[string]
$same = 0; $open = 0; $onlyOurs = New-Object System.Collections.Generic.List[int]
foreach ($id in ($quests.Keys | Sort-Object)) {
    $ours = [int]$quests[$id].covenant
    $named = if ($client.ContainsKey($id)) { @($client[$id]) } else { @() }
    if ($named.Count -eq 0) { if ($ours) { $onlyOurs.Add($id) }; continue }
    if ($named.Count -gt 1) {
        if ($ours) { $several.Add("$id $($quests[$id].name): ours $ours, the client names $($named -join ', ')") } else { $open++ }
        continue
    }
    $bit = 1 -shl $named[0]
    if (-not $ours) { $add.Add([pscustomobject]@{ Id = $id; Bit = $bit; Covenant = $named[0] }) }
    elseif ($ours -ne $bit) { $differ.Add("$id $($quests[$id].name): ours $ours, the client's $bit (covenant $($named[0]))") }
    else { $same++ }
}

$covenantNames = @{}
foreach ($row in (Import-Csv (Get-BuildTable 'Covenant'))) { $covenantNames[[int]$row.ID] = $row.Name_lang }
"Covenants: the client names one for {0} of our quests ({1} already ours), several for {2} more that stay untagged." -f ($same + $add.Count + $differ.Count), $same, ($open + $several.Count)
"Gain one: $($add.Count)" + $(if ($add.Count) { " (" + (($add | ForEach-Object { "$($_.Id) $($quests[$_.Id].name) $($covenantNames[$_.Covenant])" }) -join '; ') + ")" } else { '' })
"Ours that the client doesn't name: $($onlyOurs.Count) (kept)"
if ($differ.Count) { "FINDING: ours differs from the client's on $($differ.Count): " + ($differ -join '; ') }
if ($several.Count) { "FINDING: ours tags $($several.Count) that several covenants name: " + ($several -join '; ') }

if (-not $WhatIf -and $add.Count) {
    foreach ($a in $add) { Set-RecordField $quests[$a.Id] 'covenant' $a.Bit }
    Save-QuestData $records $DataDir $AddonDir
}
exit $(if ($differ.Count -or $several.Count) { 1 } else { 0 })
