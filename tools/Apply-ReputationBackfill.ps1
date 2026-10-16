<#
Brings qcQuestReputation in line with the API, from quest_reputation_compare.csv:
  - api-only rows (the API lists a reward and we have none) are inserted in quest ID order;
  - differ rows (both list rewards, but not the same) have their line replaced with the API's.
ours-only rows (we list a reward the API doesn't) are left alone and counted: review them by hand,
as the API may simply not list a reward the game gives.

-CacheOnly also inserts the cache-only rows of the cache pass (class E: the quest cache rewards a
shown faction, ours and the API list nothing), for the quests the API has no record of (a .404 in
-ToolsDir's quest_api_cache). Only the rewards on shown factions are written (the CSV's CacheShown).
A quest whose API record lists no reward, or that step 1 hasn't asked about, is left and counted,
since the API speaks for the first and may for the second. A faction those rewards name that
qcFactions lacks is added to it, in ID order, with the Faction table's name (CacheFactionNames).
The cache's rewards are taken without a check in the game because they match the API's wherever
both list one (the user's decision 11b of the 12.1.5 sweep), and from the newest cache only. So it
refuses a CSV whose cache pass read another build than the newest under -ToolsDir (the CSV's
CacheBuild), and one with a cache-differ or cache-lost row, unless the API has a record of that
quest and the cache gives the API's amount for every faction the API lists and no reward on a
shown faction the API doesn't: then only ours differs, and the API's own row corrects it (or, for
a reward only we list, counts it). Without -CacheOnly neither is checked, as no cache reward is
written.

No other line in qcQuest.lua is touched.

All-or-nothing: any unparseable row, an api-only or cache-only quest that already has a row, a differ
quest that has none, and any quest ID absent from data\quests.jsonl abort the run before anything is
written.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$QuestFile = (Join-Path $PSScriptRoot '..\QuestCompletist\qcQuest.lua'),
    [switch]$CacheOnly
)

. "$PSScriptRoot\QuestReputation.ps1"
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\QuestCacheFiles.ps1"

$content = [System.IO.File]::ReadAllText($QuestFile, [System.Text.Encoding]::UTF8)
$lines = $content -split "`r`n"

$existing = Get-QuestReputation $content
$questIds = @{}
foreach ($quest in (Read-QuestData $DataDir)) { $questIds[[string]$quest.id] = $true }
$qcFactions = @{}
$fm = [regex]::Match($content, '(?s)qcFactions = \{(.*?)\n\}')
foreach ($m in [regex]::Matches($fm.Groups[1].Value, '\[(\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"')) { $qcFactions[[int]$m.Groups[1].Value] = $m.Groups[2].Value }

$errors = New-Object System.Collections.Generic.List[string]

function Get-RewardRow([string]$id, [string]$text) {
    $pairs = New-Object System.Collections.Generic.List[object]
    foreach ($part in ($text -split ";")) {
        if ($part -match '^(\d+)=(-?\d+)$') {
            if ($matches[2] -ne "0") { $pairs.Add([PSCustomObject]@{ Faction = [int]$matches[1]; Value = [int]$matches[2] }) }
        } else { $errors.Add("$id has an unparseable reward: '$part'") }
    }
    if (-not $pairs.Count) { $errors.Add("$id has no non-zero reward"); return $null }
    $rendered = ($pairs | Sort-Object Faction | ForEach-Object { "[$($_.Faction)]=$($_.Value)" }) -join ","
    return [PSCustomObject]@{ Text = "{$rendered}"; Pairs = $pairs }
}

function Read-Set([string]$text) {
    $set = @{}
    foreach ($part in ($text -split ";")) {
        if (-not $part) { continue }
        if ($part -notmatch '^(\d+)=(-?\d+)$') { return $null }
        $set[$matches[1]] = [int]$matches[2]
    }
    return $set
}

function Test-CacheGivesApi($row) {
    if (-not (Test-Path "$ToolsDir\quest_api_cache\$($row.QuestID).json")) { return $false }
    $api = Read-Set $row.Api; $cache = Read-Set $row.Cache; $shown = Read-Set $row.CacheShown
    if ($null -eq $api -or $null -eq $cache -or $null -eq $shown) { return $false }
    foreach ($faction in $api.Keys) { if (-not $cache.ContainsKey($faction) -or $cache[$faction] -ne $api[$faction]) { return $false } }
    foreach ($faction in $shown.Keys) { if (-not $api.ContainsKey($faction)) { return $false } }
    return $true
}

$new = @{}; $replace = @{}; $oursOnly = 0
$fromCache = @{}; $cacheRewards = 0; $cacheLeft = 0; $cacheNoRecord = 0; $apiListsNone = 0; $unasked = 0; $untrusted = 0; $oursStale = 0
$addFactions = @{}; $cacheBuilds = @{}
foreach ($row in (Import-Csv "$ToolsDir\quest_reputation_compare.csv")) {
    $id = $row.QuestID
    if ($row.Kind -like "cache-*") { $cacheBuilds[[string]$row.CacheBuild] = $true }
    if ($row.Kind -eq "ours-only") { $oursOnly++; continue }
    if ($row.Kind -eq "cache-differ" -or $row.Kind -eq "cache-lost") {
        if (Test-CacheGivesApi $row) { $oursStale++ } else { $untrusted++ }
        continue
    }
    if ($row.Kind -eq "cache-only") {
        if (-not $CacheOnly) {
            $cacheLeft++
            if (-not (Test-Path "$ToolsDir\quest_api_cache\$id.json") -and (Test-Path "$ToolsDir\quest_api_cache\$id.404")) { $cacheNoRecord++ }
            continue
        }
        if ($existing.ContainsKey($id)) { $errors.Add("$id already has a reputation row"); continue }
        if (-not $questIds.ContainsKey($id)) { $errors.Add("$id is not in quests.jsonl"); continue }
        if (Test-Path "$ToolsDir\quest_api_cache\$id.json") { $apiListsNone++; continue }
        if (-not (Test-Path "$ToolsDir\quest_api_cache\$id.404")) { $unasked++; continue }
        $reward = Get-RewardRow $id $row.CacheShown
        if (-not $reward) { continue }
        $names = @{}
        foreach ($part in ($row.CacheFactionNames -split ";")) { if ($part -match '^(\d+)=(.+)$') { $names[[int]$matches[1]] = $matches[2] } }
        foreach ($pair in $reward.Pairs) {
            if ($qcFactions.ContainsKey($pair.Faction)) { continue }
            $name = $names[$pair.Faction]
            if (-not $name -or $name -eq '(not in the Faction table)') { $errors.Add("$id rewards faction $($pair.Faction), which qcFactions lacks and the row does not name"); continue }
            $addFactions[$pair.Faction] = $name
        }
        $fromCache[$id] = $reward.Text
        $cacheRewards += $reward.Pairs.Count
        continue
    }
    if ($row.Kind -ne "api-only" -and $row.Kind -ne "differ") { continue }
    if ($row.Kind -eq "api-only" -and $existing.ContainsKey($id)) { $errors.Add("$id already has a reputation row"); continue }
    if ($row.Kind -eq "differ" -and -not $existing.ContainsKey($id)) { $errors.Add("$id has no reputation row to correct"); continue }
    if (-not $questIds.ContainsKey($id)) { $errors.Add("$id is not in quests.jsonl"); continue }
    $reward = Get-RewardRow $id $row.Api
    if (-not $reward) { continue }
    if ($row.Kind -eq "api-only") { $new[$id] = $reward.Text } else { $replace[$id] = $reward.Text }
}
if ($CacheOnly -and $untrusted) { $errors.Insert(0, "the CSV has $untrusted cache-differ or cache-lost rows whose quest cache record gives other rewards than the API's, or that the API has no record of to check it against, so the quest cache's rewards are not used; without -CacheOnly the API's rows are still applied (docs\maintenance.md, step 2)") }
if ($CacheOnly -and $cacheBuilds.Count) {
    $newest = Get-QuestCacheFiles $ToolsDir | Select-Object -Last 1
    $newestBuild = if ($newest) { $newest.BaseName -replace '^retail_quest_cache_' } else { '' }
    $read = @($cacheBuilds.Keys | Sort-Object)
    if (-not $newestBuild -or $read.Count -ne 1 -or $read[0] -ne $newestBuild) {
        $readText = ($read | ForEach-Object { if ($_) { $_ } else { '(none named)' } }) -join ' and '
        $errors.Insert(0, "the CSV's cache pass read the quest cache of $readText, not the newest under ${ToolsDir} ($(if ($newestBuild) { $newestBuild } else { 'none there' })), and only the newest cache's rewards are taken: rerun Compare-QuestReputation.ps1 without -Cache")
    }
}

if ($errors.Count) { throw "Refusing to write. $($errors.Count) problem(s):`n" + (($errors | Select-Object -First 20) -join "`n") }

function Find-Block($lines, [string]$name) {
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^$name = \{") { $start = $i }
        elseif ($start -ge 0 -and $lines[$i] -match '^\}') { return @($start, $i) }
    }
    throw "$name block not found"
}

if ($addFactions.Count) {
    $block = Find-Block $lines 'qcFactions'
    $waiting = [System.Collections.ArrayList]@($addFactions.Keys | Sort-Object)
    $withFactions = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($i -gt $block[0] -and $i -le $block[1]) {
            $factionId = if ($line -match '^\s*\[(\d+)\]\s*=') { [int]$matches[1] } elseif ($i -eq $block[1]) { [int]::MaxValue } else { -1 }
            if ($waiting.Count -and $i -eq $block[1]) {
                for ($k = $withFactions.Count - 1; $k -gt $block[0]; $k--) {
                    if ($withFactions[$k] -match '^\s*\[\d+\]') { if ($withFactions[$k] -notmatch ',\s*$') { $withFactions[$k] = $withFactions[$k].TrimEnd() + ',' }; break }
                }
            }
            while ($waiting.Count -and $factionId -ge 0 -and $waiting[0] -lt $factionId) {
                $withFactions.Add("`t[$($waiting[0])] = `"$($addFactions[$waiting[0]] -replace '\\', '\\' -replace '"', '\"')`",")
                $waiting.RemoveAt(0)
            }
        }
        $withFactions.Add($line)
    }
    $lines = $withFactions.ToArray()
}

$block = Find-Block $lines 'qcQuestReputation'
$blockStart = $block[0]; $blockEnd = $block[1]
foreach ($id in $fromCache.Keys) { $new[$id] = $fromCache[$id] }

$pending = [System.Collections.ArrayList]@($new.Keys | Sort-Object { [int]$_ })
$replaced = 0
$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Count; $i++) {
    # Rows go in ahead of the first existing row with a higher ID; whatever is left goes in
    # before the closing brace. Blank lines inside the block are stepped over, not treated as a
    # position.
    $line = $lines[$i]
    if ($i -gt $blockStart -and $i -le $blockEnd) {
        $rowId = if ($line -match '^\s*\[(\d+)\]=') { $matches[1] } else { $null }
        $flushBelow = if ($rowId) { [int]$rowId } elseif ($i -eq $blockEnd) { [int]::MaxValue } else { -1 }
        while ($pending.Count -and $flushBelow -ge 0 -and [int]$pending[0] -lt $flushBelow) {
            $out.Add("`t[$($pending[0])]=$($new[$pending[0]]),")
            $pending.RemoveAt(0)
        }
        if ($rowId -and $replace.ContainsKey($rowId)) { $line = "`t[$rowId]=$($replace[$rowId]),"; $replaced++ }
    }
    $out.Add($line)
}
if ($pending.Count) { throw "Unplaced rows: $($pending.Count)" }
if ($replaced -ne $replace.Count) { throw "Only $replaced of the $($replace.Count) rows to correct were found." }

[System.IO.File]::WriteAllText($QuestFile, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
"Rows added: $($new.Count - $fromCache.Count); corrected: $replaced"
"Rewards only we list, left for review: $oursOnly"
if ($CacheOnly) {
    "Rows added from the quest cache: $($fromCache.Count) quests, $cacheRewards rewards; left: $apiListsNone whose API record lists none, $unasked the API hasn't been asked about"
    "Factions added to qcFactions: $(if ($addFactions.Count) { ($addFactions.Keys | Sort-Object | ForEach-Object { "[$_] $($addFactions[$_])" }) -join ', ' } else { 'none' })"
    if ($oursStale) { "Cache-differ or cache-lost rows whose cache gives the API's rewards, so only ours differs: $oursStale" }
} elseif ($cacheLeft) {
    "Rewards only the quest cache lists, left: $cacheLeft quests; -CacheOnly writes the $cacheNoRecord the API has no record of"
}
"qcQuestReputation now holds: $($existing.Count + $new.Count)"
