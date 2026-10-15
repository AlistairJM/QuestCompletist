<#
Report only: checks retail's quest minimum levels (the data file's minLevel, else level) against
Blizzard's, every sweep, and keeps a baseline so that a change shows. It is the check beside
Apply-QuestMinLevels.ps1 (QuestLevels.ps1 has the sources and the formula).

It prints
  - the formula (a ContentTuning row's minimum) tested against the API's min_character_level for every
    quest that has both: it fails below -MinAgreement of at least -MinTested quests, which is what a
    new level cap, a changed table or a hotfix to a tuning would look like;
  - the quests whose minimum, by the API or else the client's level range, is not what the data holds
    (class D), which Apply-QuestMinLevels.ps1 sets right; a quest on tuning 0 with no API minimum that
    holds a minLevel is one, since its gate must be its level;
  - the quests no source gives a minimum for (class N): not in the quest cache or the task table
    ("no record"), on a tuning the table has no row for ("no row"), on one whose minimum is beyond the
    level cap ("above the cap"), on one the API contradicts or whose offset type it never confirmed
    ("unverified"), or on tuning 0 with no API minimum and no minLevel ("tuning 0").

The quests of both classes are kept in the baseline file (-BaselineFile; -UpdateBaseline rewrites it
from this run), and each run says what is new: a D quest that wasn't in the baseline is a quest that
was right and no longer is, and fails the run (exit 1), as does a formula that no longer reproduces the
API. A new N quest is a source lost, and is listed. A quest in neither class is right.

A quest cache that looks partial (QuestCacheFiles.ps1: under 90% of the quests of the build before's
cache, or of ours) is warned about, and -UpdateBaseline refuses to write from it (exit 1) unless
-AcceptPartialCache is given: those of its gaps that neither the API nor the task table covers would go
into class N as "no record", and the formula would be tested on fewer quests.

A full sweep runs it after step 2e, which writes the quest cache it reads, and again after Apply-
QuestMinLevels.ps1 and after step 6 has added quests, when the baseline is rewritten once the new
quests are read. The first baseline is in docs\plans\quest-levels-baseline.csv.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$Build = '',
    [string]$BaselineFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-levels-baseline.csv'),
    [double]$MinAgreement = 0.99,
    [int]$MinTested = 20000,
    [int]$Examples = 5,
    [switch]$Refresh,
    [switch]$UpdateBaseline,
    [switch]$AcceptPartialCache
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. "$PSScriptRoot\QuestLevels.ps1"

$world = Get-QuestLevelWorld $ToolsDir $DataDir $Build $Refresh.IsPresent
Write-Output ("Retail build {0}: {1:N0} quests in the data, {2:N0} with an API minimum, {3:N0} tunings in the table." -f
    $world.Build, $world.Records.Count, $world.Api.Minimum.Count, $world.Tunings.Count)
$world.CacheWarning | ForEach-Object { Write-Output $_ }
$formula = Get-FormulaReport $world $MinAgreement $MinTested $Examples
$formula.Lines | ForEach-Object { Write-Output $_ }
$failed = -not $formula.Ok

$now = @{ D = New-Object 'System.Collections.Generic.HashSet[int]'; N = New-Object 'System.Collections.Generic.HashSet[int]' }
$details = @{}
$right = 0
$noSource = @{}
foreach ($q in $world.Records) {
    $id = [int]$q.id
    $m = $world.Minimums[$id]
    if ($m.Source -eq 'none' -or ($m.Source -eq 'tuning0' -and $null -eq $q.minLevel)) {
        [void]$now.N.Add($id)
        $noSource[$m.Why] = 1 + [int]$noSource[$m.Why]
        $details[$id] = "no source ($($m.Why)): level $($q.level), minLevel $(if ($null -ne $q.minLevel) { $q.minLevel } else { 'none' })"
        continue
    }
    $wanted = Get-WantedMinLevel ([int]$q.level) $m.Minimum
    $current = $q.minLevel
    $same = ($null -eq $wanted -and $null -eq $current) -or ($null -ne $wanted -and $null -ne $current -and [int]$wanted -eq [int]$current)
    if ($same) { $right++; continue }
    [void]$now.D.Add($id)
    $details[$id] = "gate $(Get-QuestGate $q), $($m.Source) says $(if ($null -ne $m.Minimum) { $m.Minimum } else { 'none' }) (level $($q.level))"
}
Write-Output ("Against the data: {0:N0} quests hold what their sources say, {1:N0} do not (class D), {2:N0} have no source (class N: {3})." -f
    $right, $now.D.Count, $now.N.Count,
    $(if ($noSource.Count) { (($noSource.Keys | Sort-Object | ForEach-Object { "$($noSource[$_]) $_" }) -join ', ') } else { 'none' }))

$baseline = @{ D = New-Object 'System.Collections.Generic.HashSet[int]'; N = New-Object 'System.Collections.Generic.HashSet[int]' }
$haveBaseline = Test-Path $BaselineFile
if ($haveBaseline) {
    foreach ($row in (Import-Csv $BaselineFile)) {
        if (-not $baseline.ContainsKey($row.Class)) { throw "$BaselineFile has class '$($row.Class)', not D or N." }
        [void]$baseline[$row.Class].Add([int]$row.QuestID)
    }
} else {
    Write-Output "  No baseline file at ${BaselineFile}: every class D quest counts as new; -UpdateBaseline writes one from this run."
}
$byName = @{}
foreach ($q in $world.Records) { $byName[[int]$q.id] = [string]$q.name }
foreach ($class in 'D', 'N') {
    $new = @($now[$class] | Where-Object { -not $baseline[$class].Contains($_) } | Sort-Object)
    $gone = @($baseline[$class] | Where-Object { -not $now[$class].Contains($_) } | Sort-Object)
    Write-Output ("  {0}: {1:N0} now, {2:N0} in the baseline; {3:N0} new, {4:N0} gone" -f $class, $now[$class].Count, $baseline[$class].Count, $new.Count, $gone.Count)
    foreach ($id in ($new | Select-Object -First $Examples)) { Write-Output "      new: $id $($byName[$id]): $($details[$id])" }
    if ($new.Count -gt $Examples) { Write-Output "      ... and $($new.Count - $Examples) more new" }
    if ($class -eq 'D' -and $new.Count -gt 0) { $failed = $true }
}

$refused = $UpdateBaseline -and $world.CacheWarning.Count -gt 0 -and -not $AcceptPartialCache
if ($refused) {
    Write-Output "Baseline not written: the quest cache looks partial (the warning above). Read a whole cache, or give -AcceptPartialCache to write it from this one all the same."
} elseif ($UpdateBaseline) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('"Class","QuestID"')
    foreach ($class in 'D', 'N') { foreach ($id in ($now[$class] | Sort-Object)) { $lines.Add('"' + $class + '","' + $id + '"') } }
    [IO.File]::WriteAllText($BaselineFile, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $true))
    Write-Output "Baseline written: $($lines.Count - 1) quests -> $BaselineFile"
}

if ($failed -or $refused) {
    $reasons = @()
    if (-not $formula.Ok) { $reasons += "the formula no longer reproduces the API's minimums" }
    $newD = @($now.D | Where-Object { -not $baseline.D.Contains($_) })
    if ($newD.Count -gt 0) { $reasons += "$($newD.Count) quests are new in class D, their minLevel not what their sources say (Apply-QuestMinLevels.ps1 -WhatIf says what it would set)" }
    if ($refused) { $reasons += "-UpdateBaseline was refused, as the quest cache looks partial" }
    Write-Output ("FAILED: " + ($reasons -join '; '))
    exit 1
}
Write-Output "No quest that matched in the baseline differs now, and the formula reproduces the API."
