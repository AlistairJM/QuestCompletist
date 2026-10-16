<#
Shared by Apply-QuestMinLevels.ps1, Compare-QuestLevels.ps1 and Test-QuestLevels.ps1, dot-sourced:
	. "$PSScriptRoot\QuestLevels.ps1"

Where a retail quest's minimum level (the level a character needs to take it) comes from. Two of
Blizzard's sources give it, and the API's wins:
  - the API's min_character_level (tools\quest_api_cache, the sweep's step 1), for the quests it has a
    record of;
  - the client's level ranges. A quest's ContentTuningID is in the client's quest cache
    (tools\retail_quest_cache_<build>.jsonl, step 2e) for every quest it holds, and in the task table
    (tools\QuestV2CliTask.csv, step 1b) for task quests; the ContentTuning table
    (tools\ContentTuning-<build>.csv, from wago.tools) turns the ID into a range. A quest on tuning 0
    has no range, and nothing says what its minimum is: no quest the API gives a minimum for is on
    tuning 0 in the quest cache or the task table, and on tuning 0 TrinityCore falls back to the quest's
    own MinLevel, which no file of ours holds. So it gets no minLevel and its gate stays its level (the
    user's decision of 11 October 2026); an API minimum still decides for a quest on tuning 0.

A tuning's minimum is MinLevelSquish plus a base that MinLevelScalingOffset picks: 0 adds nothing (the
squish value is the level), 1 adds 1, 2 adds the level cap (90) and 3 the level cap before it (80). The
bases are what the API's own minimums say, not a documented rule; the sweep tests the formula against
every quest that has both an API record and a tuning, and the tools refuse to write anything when fewer
than 99 percent agree. AllowedMinOffset (-1, -2 or -4 on 2,522 quests of the newer expansions) is not
part of it: the API shows the minimum without it. The other-faction rule of TrinityCore's
Player::GetQuestMinLevel (a quest of the other faction's tuning gets the maximum level) is a per-player
rule that no data file can hold, so it isn't applied. A tuning whose minimum is beyond the level cap
(tuning 949 has 255, a marker for a quest nobody can take) gives a quest no minimum: it is no level.

The data file keeps `level` as the quest's own level, which the list's bracket, sort and low-level
filter read for a quest that doesn't scale (QuestScaling.ps1 has the rest), and holds the minimum in
`minLevel` only where it is not that: 0 and 1 both mean no
minimum, so a quest whose level and minimum are both 0 or 1 gets no entry, and nor does a quest on
tuning 0 with no API minimum.
#>
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\QuestCacheFiles.ps1"

$script:TuningLevelBase = @{ 0 = 0; 1 = 1; 2 = 90; 3 = 80 }
$script:LevelCap = 90
$script:TuningColumns = @('ID', 'MinLevelSquish', 'MaxLevelSquish', 'MinLevelScalingOffset', 'MaxLevelScalingOffset')

function Resolve-RetailBuild([string]$toolsDir, [string]$build) {
    if ($build) { return $build }
    $newest = Get-QuestCacheFiles $toolsDir | Select-Object -Last 1
    if (-not $newest) { throw "No retail_quest_cache_<build>.jsonl under ${toolsDir}: run Read-QuestCache.ps1 -Build <retail build> (step 2e) first, or give -Build." }
    return ($newest.BaseName -replace '^retail_quest_cache_')
}

# tools\ContentTuning-<build>.csv, downloaded from wago.tools when it is missing or -Refresh is given.
# The download is checked before it replaces the file. $download is a script block taking the address
# and the path to save to; the tests give it their own.
function Get-ContentTuningFile([string]$toolsDir, [string]$build, [bool]$refresh = $false, [scriptblock]$download = $null) {
    $path = Join-Path $toolsDir "ContentTuning-$build.csv"
    if (-not $refresh -and (Test-Path $path)) { return $path }
    if (-not $download) { $download = { param($uri, $to) $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $to } }
    $part = "$path.download"
    & $download "https://wago.tools/db2/ContentTuning/csv?build=$build" $part
    try {
        $header = ((Get-Content $part -TotalCount 1) -replace '^\xEF\xBB\xBF', '').Trim() -split ','
        $lacking = @($script:TuningColumns | Where-Object { $header -notcontains $_ })
        if ($lacking.Count -gt 0) { throw "The ContentTuning table for build $build has no column $($lacking -join ', '): Blizzard changed it, so check the formula in QuestLevels.ps1." }
        if (@(Get-Content $part -TotalCount 100).Count -lt 100) { throw "The ContentTuning table for build $build has fewer than 100 rows." }
    } catch {
        Remove-Item $part -ErrorAction SilentlyContinue
        throw
    }
    Move-Item $part $path -Force
    return $path
}

# Every tuning's minimum, by ID: Type is its MinLevelScalingOffset, Minimum the level the formula gives
# (null for an offset type whose base isn't known).
function Read-ContentTuning([string]$path) {
    $rows = @(Import-Csv $path)
    if ($rows.Count -eq 0) { throw "$path has no rows." }
    foreach ($column in $script:TuningColumns) {
        if ($null -eq $rows[0].PSObject.Properties[$column]) { throw "$path has no '$column' column: Blizzard changed the table, so check the formula in QuestLevels.ps1." }
    }
    $tunings = @{}
    foreach ($row in $rows) {
        $type = [int]$row.MinLevelScalingOffset
        $minimum = $null
        if ($script:TuningLevelBase.ContainsKey($type)) { $minimum = [Math]::Max(0, $script:TuningLevelBase[$type] + [int]$row.MinLevelSquish) }
        $tunings[[int]$row.ID] = [pscustomobject]@{ Id = [int]$row.ID; Type = $type; Minimum = $minimum }
    }
    return $tunings
}

# Each quest's ContentTuningID: the quest cache's, else the task table's. Cache and table agree wherever
# both have one (Compare-QuestCache.ps1 checks it); Conflicts counts the quests where they don't.
function Read-QuestTunings([string]$cacheFile, [string]$taskFile) {
    $byQuest = @{}
    $rx = New-Object Text.RegularExpressions.Regex '^\{"id":(\d+),"title":"(?:[^"\\]|\\.)*","contentTuning":(\d+)[,}]'
    $n = 0
    foreach ($line in [IO.File]::ReadLines($cacheFile)) {
        $n++
        if (-not $line) { continue }
        $m = $rx.Match($line)
        if (-not $m.Success) { throw "$(Split-Path -Leaf $cacheFile) line ${n}: no id, title and contentTuning at its start; has Read-QuestCache.ps1 changed its lines?" }
        $byQuest[[int]$m.Groups[1].Value] = [int]$m.Groups[2].Value
    }
    $fromCache = $byQuest.Count
    $fromTable = 0; $conflicts = 0
    if (Test-Path $taskFile) {
        foreach ($row in (Import-Csv $taskFile)) {
            $id = [int]$row.ID
            if ($byQuest.ContainsKey($id)) { if ($byQuest[$id] -ne [int]$row.ContentTuningID) { $conflicts++ } }
            else { $byQuest[$id] = [int]$row.ContentTuningID; $fromTable++ }
        }
    }
    return [pscustomobject]@{ ByQuest = $byQuest; FromCache = $fromCache; FromTable = $fromTable; Conflicts = $conflicts }
}

# The API's minimum for each quest whose record gives one, by ID. Records counts the records read.
function Read-ApiMinimums([string]$apiDir) {
    $minimum = @{}
    $records = 0
    $rx = New-Object Text.RegularExpressions.Regex '"min_character_level":(\d+)'
    foreach ($file in [IO.Directory]::EnumerateFiles($apiDir, '*.json')) {
        $id = 0
        if (-not [int]::TryParse([IO.Path]::GetFileNameWithoutExtension($file), [ref]$id)) { continue }
        $records++
        $m = $rx.Match([IO.File]::ReadAllText($file))
        if ($m.Success) { $minimum[$id] = [int]$m.Groups[1].Value }
    }
    return [pscustomobject]@{ Minimum = $minimum; Records = $records }
}

# The formula against the API, for every quest that has both an API minimum and a tuning with a row.
# A tuning is trusted for the quests the API has no record of when none of its API quests disagrees and
# its offset type has been seen to agree on at least one tuning that has API quests (ConfirmedTypes).
# ByType is the count per MinLevelScalingOffset.
function Test-TuningFormula($apiMinimum, $questTuning, $tunings) {
    $result = [pscustomobject]@{
        Tested = 0; Agree = 0; NoTuning = 0; TuningZero = 0; NoRow = 0; UnknownType = 0
        Disagree = (New-Object System.Collections.Generic.List[object])
        ByType = @{}
        BadTunings = (New-Object 'System.Collections.Generic.HashSet[int]')
        ConfirmedTypes = (New-Object 'System.Collections.Generic.HashSet[int]')
    }
    $tested = @{}
    foreach ($id in ($apiMinimum.Keys | Sort-Object)) {
        if (-not $questTuning.ContainsKey($id)) { $result.NoTuning++; continue }
        $tuning = $questTuning[$id]
        if ($tuning -eq 0) { $result.TuningZero++; continue }
        if (-not $tunings.ContainsKey($tuning)) { $result.NoRow++; continue }
        $row = $tunings[$tuning]
        if ($null -eq $row.Minimum) { $result.UnknownType++; continue }
        $result.Tested++
        $tested[$tuning] = $true
        if (-not $result.ByType.ContainsKey($row.Type)) { $result.ByType[$row.Type] = @{ Tested = 0; Agree = 0 } }
        $result.ByType[$row.Type].Tested++
        if ($row.Minimum -eq $apiMinimum[$id]) { $result.Agree++; $result.ByType[$row.Type].Agree++ }
        else {
            $result.Disagree.Add([pscustomobject]@{ Id = $id; Tuning = $tuning; Formula = $row.Minimum; Api = $apiMinimum[$id]; Type = $row.Type })
            [void]$result.BadTunings.Add($tuning)
        }
    }
    foreach ($tuning in $tested.Keys) {
        if (-not $result.BadTunings.Contains($tuning)) { [void]$result.ConfirmedTypes.Add($tunings[$tuning].Type) }
    }
    return $result
}

# A quest's minimum and where it came from. Source is api (the API's record), tuning (the formula, for a
# quest with no API minimum), tuning0 (the client gives it tuning 0: no range, so no minimum is known,
# Minimum is null and the gate is the quest's level; Why says tuning 0) or none, with Why: no record, no
# row (the tuning isn't in the table), above the cap (a minimum beyond the level cap, such as the 255 of
# tuning 949, is a marker and no level), unverified (the formula disagrees with the API on that tuning,
# or its offset type has never agreed).
function Get-QuestMinimum([int]$id, $apiMinimum, $questTuning, $tunings, $validation) {
    if ($apiMinimum.ContainsKey($id)) { return [pscustomobject]@{ Source = 'api'; Minimum = $apiMinimum[$id]; Why = '' } }
    if (-not $questTuning.ContainsKey($id)) { return [pscustomobject]@{ Source = 'none'; Minimum = $null; Why = 'no record' } }
    $tuning = $questTuning[$id]
    if ($tuning -eq 0) { return [pscustomobject]@{ Source = 'tuning0'; Minimum = $null; Why = 'tuning 0' } }
    if (-not $tunings.ContainsKey($tuning)) { return [pscustomobject]@{ Source = 'none'; Minimum = $null; Why = 'no row' } }
    $row = $tunings[$tuning]
    if ($null -ne $row.Minimum -and $row.Minimum -gt $script:LevelCap) { return [pscustomobject]@{ Source = 'none'; Minimum = $null; Why = 'above the cap' } }
    if ($null -eq $row.Minimum -or $validation.BadTunings.Contains($tuning) -or -not $validation.ConfirmedTypes.Contains($row.Type)) {
        return [pscustomobject]@{ Source = 'none'; Minimum = $null; Why = 'unverified' }
    }
    return [pscustomobject]@{ Source = 'tuning'; Minimum = $row.Minimum; Why = '' }
}

# What the quest's minLevel field should hold for a quest of this level: nothing (null) when no minimum
# is known (null, tuning 0), when the minimum is the level, or when both are 0 or 1 (no minimum either
# way), else the minimum, 0 included.
function Get-WantedMinLevel([int]$level, $minimum) {
    if ($null -eq $minimum) { return $null }
    $minimum = [int]$minimum
    if ($level -eq $minimum -or ($level -le 1 -and $minimum -le 1)) { return $null }
    return $minimum
}

function Get-QuestGate($quest) {
    if ($null -ne $quest.minLevel) { return [int]$quest.minLevel }
    return [int]$quest.level
}

# Everything a run needs, read once: the data file's quests, the sources and the formula's test.
function Get-QuestLevelWorld([string]$toolsDir, [string]$dataDir, [string]$build = '', [bool]$refresh = $false, [scriptblock]$download = $null) {
    $build = Resolve-RetailBuild $toolsDir $build
    $cacheFile = Join-Path $toolsDir "retail_quest_cache_$build.jsonl"
    if (-not (Test-Path $cacheFile)) { throw "No ${cacheFile}: run Read-QuestCache.ps1 -Build $build (step 2e) first." }
    $apiDir = Join-Path $toolsDir 'quest_api_cache'
    if (-not (Test-Path $apiDir)) { throw "No ${apiDir}: run Audit-QuestAccuracy.ps1 (step 1) first." }
    $taskFile = Join-Path $toolsDir 'QuestV2CliTask.csv'
    $tuningFile = Get-ContentTuningFile $toolsDir $build $refresh $download
    $tunings = Read-ContentTuning $tuningFile
    $questTuning = Read-QuestTunings $cacheFile $taskFile
    $api = Read-ApiMinimums $apiDir
    $validation = Test-TuningFormula $api.Minimum $questTuning.ByQuest $tunings
    $records = Read-QuestData $dataDir
    $minimums = @{}
    foreach ($q in $records) { $minimums[[int]$q.id] = Get-QuestMinimum ([int]$q.id) $api.Minimum $questTuning.ByQuest $tunings $validation }
    $cacheWarning = @(Get-QuestCacheWarning $cacheFile $minimums.Keys)
    return [pscustomobject]@{
        Build = $build; CacheFile = $cacheFile; CacheWarning = $cacheWarning; TuningFile = $tuningFile; Tunings = $tunings; QuestTuning = $questTuning
        Api = $api; Validation = $validation; Records = $records; Minimums = $minimums
    }
}

# The formula's test as report lines, and whether it passes: the quests tested reach -MinTested and
# agree for at least -MinAgreement of them.
function Get-FormulaReport($world, [double]$minAgreement, [int]$minTested, [int]$examples) {
    $v = $world.Validation
    $lines = New-Object System.Collections.Generic.List[string]
    $share = if ($v.Tested -gt 0) { 100.0 * $v.Agree / $v.Tested } else { 0.0 }
    $ok = ($v.Tested -ge $minTested) -and ($v.Tested -gt 0) -and (($v.Agree / [Math]::Max(1, $v.Tested)) -ge $minAgreement)
    $lines.Add(("Formula: minimum = base[MinLevelScalingOffset] + MinLevelSquish, tested against {0:N0} quests that have an API minimum and a tuning in {1}: {2:N0} agree ({3:N2}%)  [{4}]" -f
        $v.Tested, (Split-Path -Leaf $world.TuningFile), $v.Agree, $share, $(if ($ok) { 'ok' } else { 'FAILED' })))
    foreach ($type in ($v.ByType.Keys | Sort-Object)) {
        $lines.Add(("  offset type {0} (base {1}): {2:N0} tested, {3:N0} agree" -f $type, $script:TuningLevelBase[$type], $v.ByType[$type].Tested, $v.ByType[$type].Agree))
    }
    $untested = $world.Api.Minimum.Count - $v.Tested
    $lines.Add(("  not tested: {0:N0} of the API's {1:N0} minimums (no tuning ID for {2:N0}, tuning 0 for {3:N0}, no row for {4:N0}, an unknown offset type for {5:N0})" -f
        $untested, $world.Api.Minimum.Count, $v.NoTuning, $v.TuningZero, $v.NoRow, $v.UnknownType))
    if ($v.Tested -lt $minTested) { $lines.Add("  only $($v.Tested) tested, fewer than -MinTested ${minTested}: is the API cache or the quest cache complete?") }
    foreach ($d in ($v.Disagree | Select-Object -First $examples)) {
        $lines.Add("  differs: quest $($d.Id) on tuning $($d.Tuning) (offset type $($d.Type)): formula $($d.Formula), API $($d.Api)")
    }
    if ($v.Disagree.Count -gt $examples) { $lines.Add("  ... and $($v.Disagree.Count - $examples) more that differ") }
    if ($world.QuestTuning.Conflicts -gt 0) { $lines.Add("  the quest cache and the task table disagree on the tuning of $($world.QuestTuning.Conflicts) quests (the cache's is used)") }
    return [pscustomobject]@{ Ok = $ok; Lines = $lines.ToArray() }
}
