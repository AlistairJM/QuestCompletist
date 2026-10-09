<#
Report-only. Compares every quest's reputation reward in qcQuest.lua (the
qcQuestReputation side table) against Blizzard's API (rewards.reputations), using
the response cache written by Audit-QuestAccuracy.ps1 (tools/quest_api_cache).
Makes no edits.

How our data is read is defined once in QuestReputation.ps1, which
Audit-QuestAccuracy.ps1 shares.

Output: quest_reputation_compare.csv (one row per quest where ours and the API differ,
and one per quest of classes B to F of the cache pass below) plus a summary on stdout.

The cache pass (retail only) also checks the rewards against the client's own quest cache,
tools\retail_quest_cache_<build>.jsonl, which Read-QuestCache.ps1 writes (step 2e; the newest
is used unless -Cache names one) and the client's Faction table for that build
(Faction-<build>.csv, else the newest of the same major version). Without either it is
skipped with a note and the rest runs as before. Each quest of ours is put in one class,
by comparing three sets of faction=amount, ours, the API's and the cache's, never by position:
  A  agree: wherever each lists, all three are the same
  B  the cache has the API's (or, with no API reward, ours) plus rewards only on factions that
     are not shown
  C  DIFFER: both list, and the factions or the amounts differ (a cache reward on a shown
     faction that the API does not list is this too)
  D  LOST: ours or the API lists a reward, and the quest is in the cache with none
  E  the cache lists rewards, ours and the API none, and one is on a shown faction: backfill
     candidates
  F  the same, with none on a shown faction
  G  not in the cache (informational)
  H  the cache's own extras: quests not in our data, slots with an amount of 0, a faction in
     two slots of one quest (their amounts are added)
A faction is shown when the Faction table lists it, its ReputationIndex is not negative (the
client keeps no standing for it) and ReputationFlags_0 has not got bit 4 (value 4, hidden).
Rows of classes B to F are written with the Kinds cache-more, cache-differ, cache-lost,
cache-only and cache-hidden; Apply-ReputationBackfill.ps1 acts on differ and api-only only.

B, E, F and G move with what a probe run asked for, so their quests are kept in the baseline
file (-BaselineFile; -UpdateBaseline rewrites it from this run) and each run says what is new
and gone. The run fails (exit 1) only on a class C or D quest; with -ReaderMovedAt of them or
more it says the cache reader has moved. The three builds (API, cache, Faction table) are
printed, with a warning when they differ.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$QuestFile = (Join-Path $PSScriptRoot '..\QuestCompletist\qcQuest.lua'),
    [string]$Cache = "",
    [string]$BaselineFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-reputation-cache-baseline.csv'),
    [switch]$UpdateBaseline,
    [int]$ReaderMovedAt = 100,
    [int]$Examples = 5
)

if ($Cache -and -not (Test-Path $Cache)) { throw "No ${Cache}." }

$content = [System.IO.File]::ReadAllText($QuestFile)

$qcFactions = @{}
$fm = [regex]::Match($content, '(?s)qcFactions = \{(.*?)\n\}')
foreach ($m in [regex]::Matches($fm.Groups[1].Value, '\[(\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"')) { $qcFactions[$m.Groups[1].Value] = $m.Groups[2].Value }

. "$PSScriptRoot\QuestReputation.ps1"
. "$PSScriptRoot\AddonData.ps1"

$sideTable = Get-QuestReputation $content

$ours = @{}
foreach ($quest in (Read-QuestData $DataDir)) {
    $id = [string]$quest.id
    $set = if ($sideTable.ContainsKey($id)) { $sideTable[$id] } else { @{} }
    $ours[$id] = @{ Rep = $set }
}

$orphans = @($sideTable.Keys | Where-Object { -not $ours.ContainsKey($_) })

function Format-Set($h) { return (($h.GetEnumerator() | Sort-Object { [int]$_.Key } | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ";") }

$summary = @{}; $unknown = @{}; $noApi = 0
$apiSets = @{}; $apiNamespaces = New-Object 'System.Collections.Generic.HashSet[string]'
$rows = New-Object System.Collections.Generic.List[object]
foreach ($id in $ours.Keys) {
    $path = "$ToolsDir\quest_api_cache\$id.json"
    if (-not (Test-Path $path)) { $noApi++; continue }
    $j = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
    $api = @{}; $names = @{}
    if ($j.rewards -and $j.rewards.reputations) {
        foreach ($r in $j.rewards.reputations) {
            $api["$($r.reward.id)"] = [int]$r.value; $names["$($r.reward.id)"] = $r.reward.name
            if (-not $qcFactions.ContainsKey("$($r.reward.id)")) { $unknown["$($r.reward.id)"] = $r.reward.name }
        }
    }
    $apiSets[$id] = $api
    $namespace = [regex]::Match([string]$j._links.self.href, 'namespace=static-([^&]*?)-[a-z]+(?:&|$)')
    if ($namespace.Success) { [void]$apiNamespaces.Add($namespace.Groups[1].Value) }
    $o = $ours[$id].Rep
    $a = Format-Set $api; $b = Format-Set $o
    $kind = if (-not $o.Count -and -not $api.Count) { "neither" } elseif (-not $o.Count) { "api-only" } elseif (-not $api.Count) { "ours-only" } elseif ($a -eq $b) { "match" } else { "differ" }
    $summary[$kind]++
    if ($kind -in "api-only", "ours-only", "differ") {
        $rows.Add([PSCustomObject]@{ QuestID = $id; Kind = $kind; Ours = $b; Api = $a; ApiFactionNames = (($names.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ";"); Cache = ""; CacheFactionNames = "" })
    }
}

function Test-SameSet($left, $right) {
    if ($left.Count -ne $right.Count) { return $false }
    foreach ($faction in $left.Keys) {
        if (-not $right.ContainsKey($faction) -or $right[$faction] -ne $left[$faction]) { return $false }
    }
    return $true
}

function Get-CacheClass($oursSet, $apiSet, $cacheSet, $shown) {
    if (-not $oursSet.Count -and -not $apiSet.Count) {
        if (-not $cacheSet.Count) { return 'neither' }
        foreach ($faction in $cacheSet.Keys) { if ($shown.Contains([int]$faction)) { return 'E' } }
        return 'F'
    }
    if (-not $cacheSet.Count) { return 'D' }
    if ($oursSet.Count -and $apiSet.Count -and -not (Test-SameSet $oursSet $apiSet)) { return 'C' }
    $listed = if ($apiSet.Count) { $apiSet } else { $oursSet }
    if (Test-SameSet $listed $cacheSet) { return 'A' }
    foreach ($faction in $listed.Keys) {
        if (-not $cacheSet.ContainsKey($faction) -or $cacheSet[$faction] -ne $listed[$faction]) { return 'C' }
    }
    foreach ($faction in $cacheSet.Keys) {
        if (-not $listed.ContainsKey($faction) -and $shown.Contains([int]$faction)) { return 'C' }
    }
    return 'B'
}

if (-not $Cache) {
    $newest = Get-ChildItem "$ToolsDir\retail_quest_cache_*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match '^retail_quest_cache_\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object { [version]($_.BaseName -replace '^retail_quest_cache_') } | Select-Object -Last 1
    if ($newest) { $Cache = $newest.FullName }
}
if ($Cache) {
    $cacheBuild = (Split-Path $Cache -Leaf) -replace '^retail_quest_cache_', '' -replace '\.jsonl$', ''
    $factionFile = "$ToolsDir\Faction-$cacheBuild.csv"
    if (-not (Test-Path $factionFile)) {
        $major = $cacheBuild.Split('.')[0]
        $newestFaction = Get-ChildItem "$ToolsDir\Faction-*.csv" -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -match '^Faction-\d+\.\d+\.\d+\.\d+$' -and $_.BaseName.StartsWith("Faction-$major.") } |
            Sort-Object { [version]($_.BaseName -replace '^Faction-') } | Select-Object -Last 1
        $factionFile = if ($newestFaction) { $newestFaction.FullName } else { $null }
    }
}

$report = New-Object System.Collections.Generic.List[string]
$cacheRows = New-Object System.Collections.Generic.List[object]
$cacheFailed = $false
if (-not $Cache) {
    $report.Add("Cache pass skipped: no retail_quest_cache_<build>.jsonl under ${ToolsDir} (Read-QuestCache.ps1 -Build <retail build>, step 2e of docs\maintenance.md).")
}
elseif (-not $factionFile) {
    $report.Add("Cache pass skipped: no Faction table for build $cacheBuild under ${ToolsDir} (https://wago.tools/db2/Faction/csv?build=$cacheBuild, saved as Faction-$cacheBuild.csv).")
}
else {
    try {
        $factionBuild = (Split-Path $factionFile -Leaf) -replace '^Faction-', '' -replace '\.csv$', ''
        $factionRows = @(Import-Csv $factionFile)
        foreach ($column in 'ID', 'Name_lang', 'ReputationIndex', 'ReputationFlags_0') {
            if (-not $factionRows.Count -or $factionRows[0].PSObject.Properties.Name -notcontains $column) { throw "${factionFile} has no rows or no $column column." }
        }
        $shown = New-Object 'System.Collections.Generic.HashSet[int]'
        $factionNames = @{}
        foreach ($factionRow in $factionRows) {
            $factionNames[[int]$factionRow.ID] = $factionRow.Name_lang
            if ([int]$factionRow.ReputationIndex -ge 0 -and -not ([int]$factionRow.ReputationFlags_0 -band 4)) { [void]$shown.Add([int]$factionRow.ID) }
        }

        $cacheSets = @{}; $emptySlots = 0; $twiceSlots = 0
        foreach ($line in [IO.File]::ReadAllLines($Cache)) {
            if (-not $line) { continue }
            $record = $line | ConvertFrom-Json
            $recordSet = @{}
            foreach ($pair in @($record.reputation)) {
                if (-not $pair) { continue }
                $factionKey = [string][int]$pair[0]; $amount = [int]$pair[1]
                if (-not $amount) { $emptySlots++; continue }
                if ($recordSet.ContainsKey($factionKey)) { $twiceSlots++; $recordSet[$factionKey] += $amount } else { $recordSet[$factionKey] = $amount }
            }
            $cacheSets[[string][int]$record.id] = $recordSet
        }

        $members = @{}; $firstLines = @{}
        foreach ($class in 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'neither') { $members[$class] = New-Object System.Collections.Generic.List[int]; $firstLines[$class] = New-Object System.Collections.Generic.List[string] }
        $rowKinds = @{ B = 'cache-more'; C = 'cache-differ'; D = 'cache-lost'; E = 'cache-only'; F = 'cache-hidden' }
        $aApiOnly = 0; $notInCacheWithReward = 0; $apiRewards = 0; $apiReproduced = 0
        $eRewards = 0; $eApiState = @{ noRecord = 0; record = 0; unasked = 0 }; $eMissing = @{}
        foreach ($id in ($ours.Keys | Sort-Object { [int]$_ })) {
            $oursSet = $ours[$id].Rep
            if (-not $cacheSets.ContainsKey($id)) {
                $members.G.Add([int]$id)
                if ($oursSet.Count) { $notInCacheWithReward++ }
                continue
            }
            $apiSet = if ($apiSets.ContainsKey($id)) { $apiSets[$id] } else { @{} }
            $cacheSet = $cacheSets[$id]
            foreach ($faction in $apiSet.Keys) {
                $apiRewards++
                if ($cacheSet.ContainsKey($faction) -and $cacheSet[$faction] -eq $apiSet[$faction]) { $apiReproduced++ }
            }
            $class = Get-CacheClass $oursSet $apiSet $cacheSet $shown
            $members[$class].Add([int]$id)
            $example = "$id  ours [$(Format-Set $oursSet)]  API [$(Format-Set $apiSet)]  cache [$(Format-Set $cacheSet)]"
            if ($firstLines[$class].Count -lt $Examples) { $firstLines[$class].Add($example) }
            if ($class -eq 'A' -and -not $oursSet.Count) { $aApiOnly++ }
            if ($class -eq 'E') {
                foreach ($faction in $cacheSet.Keys) {
                    if (-not $shown.Contains([int]$faction)) { continue }
                    $eRewards++
                    if (-not $qcFactions.ContainsKey($faction)) { $eMissing[$faction] = 1 + [int]$eMissing[$faction] }
                }
                if ($apiSets.ContainsKey($id)) { $eApiState.record++ } elseif (Test-Path "$ToolsDir\quest_api_cache\$id.404") { $eApiState.noRecord++ } else { $eApiState.unasked++ }
            }
            if ($rowKinds.ContainsKey($class)) {
                $cacheNames = ($cacheSet.Keys | Sort-Object { [int]$_ } | ForEach-Object { "$_=$(if ($factionNames.ContainsKey([int]$_)) { $factionNames[[int]$_] } else { '(not in the Faction table)' })" }) -join ";"
                $cacheRows.Add([PSCustomObject]@{ QuestID = $id; Kind = $rowKinds[$class]; Ours = (Format-Set $oursSet); Api = (Format-Set $apiSet); ApiFactionNames = ""; Cache = (Format-Set $cacheSet); CacheFactionNames = $cacheNames })
            }
        }
        $cacheOnly = @($cacheSets.Keys | Where-Object { -not $ours.ContainsKey($_) })
        $cacheOnlyWithReward = @($cacheOnly | Where-Object { $cacheSets[$_].Count }).Count

        $apiBuilds = @($apiNamespaces | Sort-Object)
        $cacheFile = Split-Path $Cache -Leaf
        $report.Add(("Cache pass: {0} holds {1:N0} quests, {2:N0} of our {3:N0}. Faction table {4}: {5:N0} factions, {6:N0} shown." -f $cacheFile, $cacheSets.Count, ($ours.Count - $members.G.Count), $ours.Count, (Split-Path $factionFile -Leaf), $factionNames.Count, $shown.Count))
        $report.Add("Builds: API $(if ($apiBuilds) { $apiBuilds -join ', ' } else { 'none read' }), cache $cacheBuild, Faction table $factionBuild.")
        $distinct = @(@($apiBuilds | ForEach-Object { $_ -replace '_', '.' }) + $cacheBuild + $factionBuild | Sort-Object -Unique)
        if ($distinct.Count -gt 1) { $report.Add("WARNING: the builds differ: a reward that differs below may be a hotfix between them, but hundreds would be a reader that moved.") }
        if (-not $apiBuilds) { $report.Add("WARNING: no API record was read, so the classes below hold ours and the cache only.") }
        if ($members.G.Count -eq $ours.Count) { $report.Add("WARNING: the cache holds none of our quests.") }
        $report.Add(("  A agree: {0:N0} (of which ours lists none, the API and the cache agree: {1:N0})" -f $members.A.Count, $aApiOnly))
        $report.Add(("  B cache adds rewards on factions that are not shown: {0:N0}" -f $members.B.Count))
        $report.Add(("  C DIFFER: {0:N0}" -f $members.C.Count))
        $report.Add(("  D LOST: {0:N0}" -f $members.D.Count))
        $report.Add(("  E cache only, on a shown faction (backfill candidates): {0:N0} quests, {1:N0} rewards; API: no record {2:N0}, a record listing none {3:N0}, not asked {4:N0}" -f $members.E.Count, $eRewards, $eApiState.noRecord, $eApiState.record, $eApiState.unasked))
        $report.Add(("  F cache only, on factions that are not shown: {0:N0}" -f $members.F.Count))
        $report.Add(("  G not in the cache: {0:N0} ({1:N0} with a reward row of ours)" -f $members.G.Count, $notInCacheWithReward))
        $report.Add(("  H only in the cache: {0:N0} quests ({1:N0} with a reward); {2:N0} empty-amount slots; {3:N0} factions in two slots of one quest" -f $cacheOnly.Count, $cacheOnlyWithReward, $emptySlots, $twiceSlots))
        $report.Add(("  Nothing listed anywhere: {0:N0}" -f $members.neither.Count))
        $report.Add(("  API rewards the cache reproduces: {0:N0} of {1:N0}" -f $apiReproduced, $apiRewards))
        foreach ($faction in ($eMissing.Keys | Sort-Object { [int]$_ })) {
            $report.Add(("  E rewards on a faction missing from qcFactions: [{0}] {1}, {2:N0}" -f $faction, $factionNames[[int]$faction], $eMissing[$faction]))
        }

        $baseline = $null
        if (Test-Path $BaselineFile) {
            $baseline = @{}
            foreach ($class in 'B', 'E', 'F', 'G') { $baseline[$class] = New-Object 'System.Collections.Generic.HashSet[int]' }
            foreach ($baselineRow in (Import-Csv $BaselineFile)) {
                if (-not $baseline.ContainsKey($baselineRow.Class)) { throw "${BaselineFile} has class '$($baselineRow.Class)', not one of B, E, F, G." }
                [void]$baseline[$baselineRow.Class].Add([int]$baselineRow.QuestID)
            }
        }
        else {
            $report.Add("  No baseline file at ${BaselineFile}: -UpdateBaseline writes one from this run.")
        }
        if ($baseline) {
            foreach ($class in 'B', 'E', 'F', 'G') {
                $was = $baseline[$class]
                $now = New-Object 'System.Collections.Generic.HashSet[int]'
                foreach ($id in $members[$class]) { [void]$now.Add($id) }
                $new = @($members[$class] | Where-Object { -not $was.Contains($_) })
                $gone = @($was | Where-Object { -not $now.Contains($_) } | Sort-Object)
                $report.Add(("  {0}: {1:N0} now, {2:N0} in the baseline; {3:N0} new, {4:N0} gone" -f $class, $now.Count, $was.Count, $new.Count, $gone.Count))
                foreach ($change in @(@('new', $new), @('gone', $gone))) {
                    if ($change[1].Count) { $report.Add("      $($change[0]): $((@($change[1] | Select-Object -First $Examples)) -join ', ')$(if ($change[1].Count -gt $Examples) { ', ...' })") }
                }
            }
        }
        if ($UpdateBaseline) {
            $baselineLines = New-Object System.Collections.Generic.List[string]
            $baselineLines.Add('"Class","QuestID"')
            foreach ($class in 'B', 'E', 'F', 'G') { foreach ($id in ($members[$class] | Sort-Object)) { $baselineLines.Add('"' + $class + '","' + $id + '"') } }
            [IO.File]::WriteAllText($BaselineFile, (($baselineLines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $true))
            $report.Add("  Baseline written: $($baselineLines.Count - 1) quests -> $BaselineFile")
        }
        foreach ($class in 'B', 'C', 'D', 'E', 'F') {
            foreach ($example in $firstLines[$class]) { $report.Add("  $class  $example") }
        }
        if ($members.C.Count -ge $ReaderMovedAt) {
            $cacheFailed = $true
            $report.Add("FAILED: $($members.C.Count) quests have a reward that differs between ours, the API and the cache: the cache reader looks moved. Run Compare-QuestCache.ps1 and do not use the cache's rewards this sweep (docs\maintenance.md, step 2e).")
        }
        elseif ($members.C.Count -gt 0 -or $members.D.Count -gt 0) {
            $cacheFailed = $true
            $report.Add("FAILED: $($members.C.Count) quests have a reward that differs and $($members.D.Count) lost theirs in the cache (Kinds cache-differ and cache-lost in the CSV).")
        }
    }
    catch {
        $cacheRows.Clear()
        $cacheFailed = $true
        $report.Add("FAILED: the cache pass stopped: $($_.Exception.Message)")
    }
}

$outFile = "$ToolsDir\quest_reputation_compare.csv"
$rows.ToArray() + $cacheRows.ToArray() | Sort-Object { [int]$_.QuestID }, Kind | Export-Csv $outFile -NoTypeInformation -Encoding utf8
"qcQuestReputation rows: $($sideTable.Count)" + $(if ($orphans.Count) { " (WARNING - $($orphans.Count) not in quests.jsonl: $($orphans -join ','))" } else { "" })
"Quests the API 404s on (no reputation source): $noApi"
"Comparison: " + (($summary.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ", ")
"API-only rows with more than one faction: $(@($rows | Where-Object { $_.Kind -eq 'api-only' -and $_.Api -match ';' }).Count)"
"Reward factions missing from qcFactions: $($unknown.Count)"
$unknown.GetEnumerator() | Sort-Object { [int]$_.Key } | ForEach-Object { "  [$($_.Key)] $($_.Value)" }
"Rows written: $($rows.Count + $cacheRows.Count) -> $outFile"
$report
if ($cacheFailed) { exit 1 }
