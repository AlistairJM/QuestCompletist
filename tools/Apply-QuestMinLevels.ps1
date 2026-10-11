<#
Gives retail quests their real minimum level: the level a character needs to take them, which the
tooltip's "Requires Level" line, the grey pins and the requirements filter read as
qcQuestMinLevel[questId] or level. Until October 2026 retail's table was empty, so the gate was the
quest's own level, which is not the game's minimum for 1,398 of the 30,066 quests the API has a record
of: a level 1 character was told "Requires Level 30" for quests the game lets it take.

The minimum is the API's min_character_level where the API has a record, else the client's level range
for the quest's ContentTuningID (QuestLevels.ps1 has the formula and the sources; a quest on tuning 0
with no API minimum has no known minimum, so it holds no `minLevel` and its gate is its level, and one
with neither source is left as it is). It goes in the data file's `minLevel` field only where it differs
from `level`, which stays the quest's own level (the list's bracket, sort and low-level filter read it);
a minimum of 0 or 1 against a level of 0 or 1 is no difference. Nothing else in a record changes. Saved
through AddonData.ps1, which rebuilds qcQuestData.lua.

Before anything is written the formula is tested against every quest that has both an API minimum and a
tuning, and the run stops, changing nothing, unless at least -MinAgreement of at least -MinTested agree
(Blizzard changing the table, or the cap, would show here). Safe to rerun: a second run changes nothing,
and after quests are added to the data (the task quests of step 6) it covers just those, and any quest
whose source has moved. Existing `minLevel` values change only when a source says so.

  -WhatIf   report only: the sources, the changes by direction and examples; writes no data (a missing ContentTuning table is downloaded into tools\ first)
  -Check    like -WhatIf, but exits 1 when the data isn't what the sources say (for Test- and Audit- steps)
  -Refresh  download the ContentTuning table again (it is downloaded when tools\ lacks it for the build)
  -Build    the retail build of the table and the quest cache; the newest retail_quest_cache_<build>.jsonl's by default

Reads tools\quest_api_cache (step 1), tools\retail_quest_cache_<build>.jsonl (step 2e),
tools\QuestV2CliTask.csv (step 1b) and tools\ContentTuning-<build>.csv. Exit 0 is a clean run, 1 a
refused one or, with -Check, a difference.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = '',
    [double]$MinAgreement = 0.99,
    [int]$MinTested = 20000,
    [int]$Examples = 10,
    [switch]$Refresh,
    [switch]$WhatIf,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. "$PSScriptRoot\QuestLevels.ps1"

$world = Get-QuestLevelWorld $ToolsDir $DataDir $Build $Refresh.IsPresent
Write-Output ("Retail build {0}: {1:N0} quests in the data, {2:N0} API records ({3:N0} with a minimum), {4:N0} tunings in the table, tunings for {5:N0} quests ({6:N0} from the quest cache, {7:N0} more from the task table)." -f
    $world.Build, $world.Records.Count, $world.Api.Records, $world.Api.Minimum.Count, $world.Tunings.Count,
    $world.QuestTuning.ByQuest.Count, $world.QuestTuning.FromCache, $world.QuestTuning.FromTable)
$formula = Get-FormulaReport $world $MinAgreement $MinTested 5
$formula.Lines | ForEach-Object { Write-Output $_ }
if (-not $formula.Ok) {
    Write-Output "The formula doesn't reproduce the API's minimums well enough: nothing was changed."
    exit 1
}

$bySource = [ordered]@{ api = 0; tuning = 0; tuning0 = 0 }
$none = @{}
$changes = New-Object System.Collections.Generic.List[object]
$same = 0
foreach ($q in $world.Records) {
    $m = $world.Minimums[[int]$q.id]
    if ($m.Source -eq 'none') { $none[$m.Why] = 1 + [int]$none[$m.Why]; continue }
    $bySource[$m.Source]++
    $level = [int]$q.level
    $wanted = Get-WantedMinLevel $level $m.Minimum
    $current = $q.minLevel
    if ($null -eq $wanted -and $null -eq $current) { $same++; continue }
    if ($null -ne $wanted -and $null -ne $current -and [int]$wanted -eq [int]$current) { $same++; continue }
    $oldGate = Get-QuestGate $q
    $newGate = if ($null -ne $wanted) { [int]$wanted } else { $level }
    $kind = if ($null -eq $current) { 'added' } elseif ($null -eq $wanted) { 'removed' } else { 'changed' }
    $changes.Add([pscustomobject]@{ Quest = $q; Id = [int]$q.id; Name = [string]$q.name; Level = $level; OldGate = $oldGate; NewGate = $newGate; Wanted = $wanted; Source = $m.Source; Kind = $kind
        Direction = $(if ($newGate -lt $oldGate) { 'lowered' } elseif ($newGate -gt $oldGate) { 'raised' } else { 'same' }) })
}

$noneCount = 0
foreach ($count in $none.Values) { $noneCount += $count }
Write-Output ("Sources: the API for {0:N0} quests, the client's level range for {1:N0}, tuning 0 (no range: no minLevel, the gate is the level) for {2:N0}; {3:N0} have neither and stay as they are ({4})." -f
    $bySource.api, $bySource.tuning, $bySource.tuning0, $noneCount,
    $(if ($none.Count) { (($none.Keys | Sort-Object | ForEach-Object { "$($none[$_]) $_" }) -join ', ') } else { 'none' }))
$lowered = @($changes | Where-Object { $_.Direction -eq 'lowered' })
$raised = @($changes | Where-Object { $_.Direction -eq 'raised' })
$sameGate = @($changes | Where-Object { $_.Direction -eq 'same' })
Write-Output ("{0:N0} quests already hold the minimum their sources give; {1:N0} change: the gate is lowered for {2:N0} and raised for {3:N0}{4}." -f
    $same, $changes.Count, $lowered.Count, $raised.Count, $(if ($sameGate.Count) { ", unchanged for $($sameGate.Count)" } else { '' }))
foreach ($source in 'api', 'tuning', 'tuning0') {
    $from = @($changes | Where-Object { $_.Source -eq $source })
    if ($from.Count -eq 0) { continue }
    Write-Output ("  from {0}: {1:N0} ({2:N0} lowered, {3:N0} raised); minLevel {4} {5:N0}, {6} {7:N0}, {8} {9:N0}" -f $source, $from.Count,
        @($from | Where-Object { $_.Direction -eq 'lowered' }).Count, @($from | Where-Object { $_.Direction -eq 'raised' }).Count,
        'added', @($from | Where-Object { $_.Kind -eq 'added' }).Count, 'changed', @($from | Where-Object { $_.Kind -eq 'changed' }).Count,
        'removed', @($from | Where-Object { $_.Kind -eq 'removed' }).Count)
}
foreach ($direction in $lowered, $raised) {
    if ($direction.Count -eq 0) { continue }
    Write-Output "  $($direction[0].Direction), the first ${Examples} by id (id, level, gate before and after, source, name):"
    foreach ($c in ($direction | Sort-Object Id | Select-Object -First $Examples)) {
        Write-Output ("    {0}  level {1}  gate {2} -> {3}  {4}  {5}" -f $c.Id, $c.Level, $c.OldGate, $c.NewGate, $c.Source, $c.Name)
    }
}

if ($changes.Count -eq 0) {
    Write-Output "Nothing to change: every quest's minLevel is what its sources say."
    exit 0
}
if ($Check) {
    Write-Output "The data isn't what the sources say for $($changes.Count) quests: run Apply-QuestMinLevels.ps1 (-WhatIf first)."
    exit 1
}
if ($WhatIf) {
    Write-Output "-WhatIf: nothing was written."
    exit 0
}

foreach ($c in $changes) { Set-RecordField $c.Quest 'minLevel' $c.Wanted }
Save-QuestData $world.Records $DataDir $AddonDir
$entries = @($world.Records | Where-Object { $null -ne $_.minLevel }).Count
Write-Output "Saved: $($changes.Count) quests changed, $entries quests now hold a minLevel."
