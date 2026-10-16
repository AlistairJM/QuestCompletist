<#
Report-only (step 6, "Quests the data lacks"). Lists the quests that a game's client, quest cache, emulator or pins
know and the data doesn't hold, and says which look like quests a player can take. It changes no data.

Retail: data\quests.jsonl against the client's QuestV2 (live build and, when present, the PTR's) and QuestPOIBlob,
the newest quest cache (tools\retail_quest_cache_<build>.jsonl, step 2e), TrinityCore's quest_template, the
client's task table and the quests the pins name. Titles come from the newest cache, then Blizzard's API
(tools\quest_api_cache, step 1), then the task table, then the older caches in tools\ (newest first), then
TrinityCore. An older cache gives only a title, and only where no current source has one: the flags and the
quest type come from the newest.
WoW: Forever: data\forever\quests.jsonl against its QuestV2 and QuestPOIBlob, its quest caches (read the same
way), CMaNGOS's quest_template and its pins.
QuestV2 proves nothing alone (it omits almost all repeatable quests, and lists tracking and retired ones), so a
quest is a candidate only with evidence that someone gives it or starts it, and none of the reasons to leave it out.

A quest the tool leaves out says why, in the first of these that holds: a task row (retail's task quests have
their own step, 6b), the server's tracking flag (0x400), its internal-build flag (FlagsEx 0x20000), the
retired flag (0x4000), a title that marks it as internal (placeholders, tests, proofs of concept, dungeon
finder rows and the like), no title, a disables row in the emulator
(TrinityCore's sourceType 1), a quest type of 1 in the cache. A candidate has at least one of: an emulator
starter (a creature or an object), a start point (point 32 in the client's QuestPOIBlob, or in
TrinityCore's quest_poi), a quest line row (QuestLineXQuest-<newest QuestV2 build>.csv, else the game's newest
numbered one up to that build, else on retail the unnumbered QuestLineXQuest.csv, of an unknown build), an item
that starts it (ItemSparse StartQuestID, its table found the same way).
Anything else is "noEvidence".

Decisions already taken are in docs\plans\missing-quest-decisions.csv (Game, Quest, Name, Decision, Reason):
ADD means the quest is meant to be added (once the user has seen the list), SKIP that it was looked at and
isn't. A decided quest isn't reported again. The counts of each kind are kept in
docs\plans\missing-quests-baseline.csv; the script exits 1 when the undecided candidates are more than
the baseline's, and -UpdateBaseline writes the new counts once the new ones are explained.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Find-MissingQuests.ps1 -Game retail
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Find-MissingQuests.ps1 -Game forever

Writes tools\missing_quests_<game>.csv (every quest the data lacks, with its kind and evidence).
#>
param(
    [ValidateSet('retail', 'forever')][string]$Game = 'retail',
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = '',
    [string]$Build = '',
    [string]$TdbFile = '',
    [string]$CmangosDump = '',
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\missing-quest-decisions.csv'),
    [string]$BaselineFile = (Join-Path $PSScriptRoot '..\docs\plans\missing-quests-baseline.csv'),
    [string]$OutFile = '',
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$UpdateBaseline
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\QuestCacheFiles.ps1"
if (-not $DataDir) { $DataDir = if ($Game -eq 'forever') { Join-Path $PSScriptRoot '..\data\forever' } else { Join-Path $PSScriptRoot '..\data' } }
if (-not $OutFile) { $OutFile = Join-Path $ToolsDir "missing_quests_$Game.csv" }

function Newest-Build([string]$pattern, [string]$prefix) {
    $names = @(Get-ChildItem (Join-Path $ToolsDir $pattern) -ErrorAction SilentlyContinue | ForEach-Object { $_.Name -replace "^$prefix-(.*)\.csv$", '$1' } | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
    return @($names | Sort-Object { [version]$_ })
}
function Find-ClientTable([string]$table, [string]$what) {
    $builds = @(Newest-Build "$table-*.csv" $table | Where-Object { $_ -like $buildLike -and [version]$_ -le [version]$latest })
    if ($builds.Count) {
        $file = "$table-$($builds[-1]).csv"
        $note = if ($builds[-1] -ne $latest) { "No $table-$latest.csv: ${what}s from $file." } else { '' }
    } elseif ($Game -eq 'retail' -and (Test-Path (Join-Path $ToolsDir "$table.csv"))) {
        $file = "$table.csv"
        $note = "No $table-<build>.csv up to ${latest}: ${what}s from the unnumbered $file, of an unknown build."
    } else {
        $file = ''
        $note = "No $table table for $Game in ${ToolsDir}: $what evidence is missing."
    }
    return [pscustomobject]@{ Path = $(if ($file) { Join-Path $ToolsDir $file } else { '' }); Note = $note }
}
function Read-Ids([string]$path) {
    $ids = @{}
    foreach ($row in (Import-Csv $path)) { $ids[[int]$row.ID] = $true }
    return $ids
}
function Read-Dump([string]$file, [string]$table, [string]$columns) {
    $saved = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try { $rows = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $file $table $columns) } finally { [Console]::OutputEncoding = $saved }
    if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $table" }
    return $rows
}

$ours = @{}
foreach ($q in (Read-QuestData $DataDir)) { $ours[[int]$q.id] = $q }
$pinned = @{}
foreach ($pin in (Read-PinData $DataDir)) { foreach ($q in $pin.quests) { $pinned[[int]$q] = $true } }

# Client: QuestV2, and the PTR's when it is newer than the live build's.
$buildLike = if ($Game -eq 'forever') { '1.*' } else { '12.*' }
$clientBuilds = @(Newest-Build 'QuestV2-*.csv' 'QuestV2' | Where-Object { $_ -like $buildLike })
if (-not $clientBuilds.Count) { throw "No QuestV2-<build>.csv for $Game in $ToolsDir." }
if ($Build) { $clientBuilds = @($clientBuilds | Where-Object { [version]$_ -le [version]$Build }) }
$clientKnown = @{}
foreach ($b in $clientBuilds) { foreach ($id in (Read-Ids (Join-Path $ToolsDir "QuestV2-$b.csv")).Keys) { if (-not $clientKnown.ContainsKey($id)) { $clientKnown[$id] = $b } } }
$latest = $clientBuilds[-1]

# The quest caches of the game: the newest for everything, the older builds' for titles only.
function Get-CacheBuild($file) { return $file.BaseName -replace '^.*_quest_cache_', '' }
$cacheFiles = @(Get-QuestCacheFiles $ToolsDir $Game)
[array]::Reverse($cacheFiles)
$cache = @{}
$olderTitle = @{}
if ($cacheFiles.Count) {
    foreach ($line in [IO.File]::ReadLines($cacheFiles[0].FullName)) {
        if ($line -match '^\{"id":(\d+),') { $cache[[int]$Matches[1]] = $line | ConvertFrom-Json }
    }
    foreach ($file in ($cacheFiles | Select-Object -Skip 1)) {
        $build = Get-CacheBuild $file
        foreach ($line in [IO.File]::ReadLines($file.FullName)) {
            if ($line -notmatch '^\{"id":(\d+),') { continue }
            $id = [int]$Matches[1]
            if ($cache.ContainsKey($id) -or $olderTitle.ContainsKey($id) -or $ours.ContainsKey($id)) { continue }
            $title = [string]($line | ConvertFrom-Json).title
            if ($title) { $olderTitle[$id] = [pscustomobject]@{ Title = $title; Build = $build } }
        }
    }
    $older = if ($cacheFiles.Count -gt 1) { "; for titles only, $((@($cacheFiles | Select-Object -Skip 1 | ForEach-Object { Get-CacheBuild $_ })) -join ', '), which title $($olderTitle.Count) quests the newest lacks" } else { '' }
    Write-Output "Quest cache: $(Get-CacheBuild $cacheFiles[0])$older."
} else { Write-Output "No quest cache for $Game in ${ToolsDir}: its titles and flags are missing." }

# Blizzard's API (retail): the current cache folder only, not the dated copies beside it.
$apiDir = Join-Path $ToolsDir 'quest_api_cache'
$apiHas = @{}
if ($Game -eq 'retail') {
    if (Test-Path $apiDir) {
        foreach ($f in [IO.Directory]::EnumerateFiles($apiDir, '*.json')) { $n = [IO.Path]::GetFileNameWithoutExtension($f); if ($n -match '^\d+$') { $apiHas[[int]$n] = $true } }
    } else { Write-Output "No quest_api_cache in ${ToolsDir}: the API's titles are missing." }
}

# Task rows (retail): their own step.
$task = @{}
if ($Game -eq 'retail' -and (Test-Path (Join-Path $ToolsDir 'QuestV2CliTask.csv'))) {
    foreach ($row in (Import-Csv (Join-Path $ToolsDir 'QuestV2CliTask.csv'))) { $task[[int]$row.ID] = $row.QuestTitle_lang }
}

# Emulator: TrinityCore (retail) or CMaNGOS (Forever).
$em = @{}; $emStarter = @{}; $emObject = @{}; $emDisabled = @{}; $emStart32 = @{}; $emItemStart = @{}
$tempSql = $null
if ($Game -eq 'retail') {
    if (-not $TdbFile) { $TdbFile = @(Get-ChildItem (Join-Path $ToolsDir 'tdb\TDB_full_world_*.sql') | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName)[0] }
    $source = $TdbFile
    foreach ($line in (Read-Dump $source quest_template '1,2,24,25,111')) { $f = $line.Split("`t"); $em[[int]$f[0]] = [pscustomobject]@{ Type = [int]$f[1]; Flags = [uint32]$f[2]; FlagsEx = [uint32]$f[3]; Title = $f[4] } }
    foreach ($line in (Read-Dump $source creature_queststarter '1,2')) { $f = $line.Split("`t"); $emStarter[[int]$f[1]] = $true }
    foreach ($line in (Read-Dump $source gameobject_queststarter '1,2')) { $f = $line.Split("`t"); $emObject[[int]$f[1]] = $true }
    foreach ($line in (Read-Dump $source disables '1,2,3,6')) { $f = $line.Split("`t"); if ($f[0] -eq '1') { $emDisabled[[int]$f[1]] = $f[3] } }
    foreach ($line in (Read-Dump $source quest_poi '1,4')) { $f = $line.Split("`t"); if ($f[1] -eq '32') { $emStart32[[int]$f[0]] = $true } }
} else {
    if (-not $CmangosDump) { $CmangosDump = @(Get-ChildItem (Join-Path $ToolsDir 'ClassicDB_*.sql.gz') | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName)[0] }
    $tempSql = [IO.Path]::GetTempFileName()
    $in = [IO.File]::OpenRead($CmangosDump); $gz = New-Object System.IO.Compression.GZipStream($in, [IO.Compression.CompressionMode]::Decompress)
    $out = [IO.File]::Create($tempSql); $gz.CopyTo($out); $out.Close(); $gz.Close(); $in.Close()
    $source = $tempSql
    foreach ($line in (Read-Dump $source quest_template '1,31,22')) { $f = $line.Split("`t"); $em[[int]$f[0]] = [pscustomobject]@{ Type = 0; Flags = 0; FlagsEx = 0; Title = $f[1]; Special = [int]$f[2] } }
    foreach ($line in (Read-Dump $source creature_questrelation '1,2')) { $f = $line.Split("`t"); $emStarter[[int]$f[1]] = $true }
    foreach ($line in (Read-Dump $source gameobject_questrelation '1,2')) { $f = $line.Split("`t"); $emObject[[int]$f[1]] = $true }
    foreach ($line in (Read-Dump $source item_template '1,111')) { $f = $line.Split("`t"); if ([int]$f[1]) { $emItemStart[[int]$f[1]] = $true } }
}
if ($tempSql) { Remove-Item $tempSql -ErrorAction SilentlyContinue }

# Client evidence: start points, quest lines, items that start a quest.
$clientStart32 = @{}; $clientPoi = @{}
foreach ($file in (Get-ChildItem (Join-Path $ToolsDir 'QuestPOIBlob*.csv') -ErrorAction SilentlyContinue)) {
    $isForever = $file.Name -match '-1\.\d'
    if (($Game -eq 'forever') -ne $isForever) { continue }
    foreach ($row in (Import-Csv $file.FullName)) { $clientPoi[[int]$row.QuestID] = $true; if ($row.ObjectiveIndex -eq '32') { $clientStart32[[int]$row.QuestID] = $true } }
}
$questLine = @{}
$lineTable = Find-ClientTable 'QuestLineXQuest' 'quest line'
if ($lineTable.Note) { Write-Output $lineTable.Note }
if ($lineTable.Path) { foreach ($row in (Import-Csv $lineTable.Path)) { $questLine[[int]$row.QuestID] = [int]$row.QuestLineID } }
$itemStart = @{}
$itemTable = Find-ClientTable 'ItemSparse' 'start item'
if ($itemTable.Note) { Write-Output $itemTable.Note }
if ($itemTable.Path) { foreach ($row in (Import-Csv $itemTable.Path)) { if ([int]$row.StartQuestID) { $itemStart[[int]$row.StartQuestID] = $true } } }
foreach ($id in $emItemStart.Keys) { $itemStart[$id] = $true }

# Decisions.
$decided = @{}
if (Test-Path $DecisionsFile) {
    foreach ($row in (Import-Csv $DecisionsFile)) {
        if ($row.Game -ne $Game) { continue }
        if ($row.Decision -notin 'ADD', 'SKIP') { throw "$DecisionsFile gives quest $($row.Quest) the decision '$($row.Decision)': it is ADD or SKIP." }
        $decided[[int]$row.Quest] = $row
    }
}

$internal = '^<|UNUSED|\[DNT\]|\(DNT\)|\[PH\]|\(POC\)|^ZZ|\bNYI\b|DEPRECATED|\bTO DEPRECATE\b|\bTEST\b|test quest|do not use|\(NOT USED\)|REUSE|^Tracking Quest$|\bTBD\b|placeholder|^Midnight \([\d-]+\) E\b|^LFGDungeons - |^Prey: Target \d+'
$known = @{}
foreach ($set in $clientKnown.Keys, $clientPoi.Keys, $cache.Keys, $em.Keys, $pinned.Keys) { foreach ($id in $set) { if ([int]$id -gt 0) { $known[[int]$id] = $true } } }
if ($Game -eq 'retail') { foreach ($id in $task.Keys) { $known[[int]$id] = $true } }

$rows = New-Object System.Collections.Generic.List[object]
foreach ($id in ($known.Keys | Sort-Object)) {
    if ($ours.ContainsKey($id)) { continue }
    $c = $cache[$id]; $e = $em[$id]
    $apiTitle = if ($apiHas.ContainsKey($id)) { [string]([IO.File]::ReadAllText((Join-Path $apiDir "$id.json"), [Text.Encoding]::UTF8) | ConvertFrom-Json).title } else { '' }
    $o = $olderTitle[$id]
    $title = if ($c -and $c.title) { [string]$c.title } elseif ($apiTitle) { $apiTitle } elseif ($task.ContainsKey($id) -and $task[$id]) { [string]$task[$id] } elseif ($o) { $o.Title } elseif ($e) { [string]$e.Title } else { '' }
    $flags = if ($c) { [uint32]$(if ($null -ne $c.flags) { $c.flags } else { 0 }) } elseif ($e) { $e.Flags } else { [uint32]0 }
    $flagsEx = if ($c) { [uint32]$(if ($null -ne $c.flagsEx) { $c.flagsEx } else { 0 }) } elseif ($e) { $e.FlagsEx } else { [uint32]0 }
    $evidence = New-Object System.Collections.Generic.List[string]
    if ($emStarter.ContainsKey($id)) { $evidence.Add('emulatorNpc') }
    if ($emObject.ContainsKey($id)) { $evidence.Add('emulatorObject') }
    if ($clientStart32.ContainsKey($id)) { $evidence.Add('clientStart') }
    if ($emStart32.ContainsKey($id)) { $evidence.Add('emulatorStart') }
    if ($questLine.ContainsKey($id)) { $evidence.Add("questLine$($questLine[$id])") }
    if ($itemStart.ContainsKey($id)) { $evidence.Add('startItem') }
    $kind =
        if ($task.ContainsKey($id)) { 'task' }
        elseif ($flags -band 0x400) { 'tracking' }
        elseif ($flagsEx -band 0x20000) { 'internalBuild' }
        elseif ($flags -band 0x4000) { 'retired' }
        elseif ($title -match $internal) { 'internalTitle' }
        elseif (-not $title) { 'noTitle' }
        elseif ($emDisabled.ContainsKey($id)) { 'disabled' }
        elseif ($c -and [int]$c.questType -eq 1) { 'questType1' }
        elseif ($evidence.Count) { 'candidate' }
        else { 'noEvidence' }
    $rows.Add([pscustomobject]@{
        Quest = $id; Kind = $kind; Name = $title; Evidence = ($evidence -join '+')
        Sources = (@(if ($clientKnown.ContainsKey($id)) { "QuestV2($($clientKnown[$id]))" }; if ($clientPoi.ContainsKey($id)) { 'QuestPOIBlob' }; if ($c) { 'cache' }; if ($o) { "cache($($o.Build))" }; if ($apiHas.ContainsKey($id)) { 'api' }; if ($e) { 'emulator' }; if ($pinned.ContainsKey($id)) { 'pin' }) -join '+')
        Decision = if ($decided.ContainsKey($id)) { $decided[$id].Decision } else { '' }
    })
}
$rows | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8

Write-Output ("{0}: {1} quests in the data; {2} known to the client, its cache, the emulator or the pins and not in the data (client build {3})." -f $Game, $ours.Count, $rows.Count, $latest)
foreach ($g in ($rows | Group-Object Kind | Sort-Object Name)) { Write-Output ("  {0}: {1}" -f $g.Name, $g.Count) }
$undecided = @($rows | Where-Object { $_.Kind -eq 'candidate' -and -not $_.Decision })
$decidedCandidates = @($rows | Where-Object { $_.Kind -eq 'candidate' -and $_.Decision })
Write-Output ("Candidates: {0} undecided, {1} decided. Written to {2}" -f $undecided.Count, $decidedCandidates.Count, $OutFile)
foreach ($row in ($undecided | Select-Object -First 25)) { Write-Output ("  {0} {1} [{2}]" -f $row.Quest, $row.Name, $row.Evidence) }
if ($undecided.Count -gt 25) { Write-Output "  ... and $($undecided.Count - 25) more in the file." }
foreach ($row in $decided.Values) { if ($ours.ContainsKey([int]$row.Quest) -and $row.Decision -eq 'ADD') { Write-Output "Decided ADD and now in the data: $($row.Quest)" } }

# Baseline: counts per kind, and the undecided candidates.
$baseline = @{}
if (Test-Path $BaselineFile) { foreach ($row in (Import-Csv $BaselineFile)) { if ($row.Game -eq $Game) { $baseline[$row.Kind] = [int]$row.Count } } }
if ($UpdateBaseline) {
    $keep = @(); if (Test-Path $BaselineFile) { $keep = @(Import-Csv $BaselineFile | Where-Object { $_.Game -ne $Game }) }
    $new = @(foreach ($g in ($rows | Group-Object Kind | Sort-Object Name)) { [pscustomobject]@{ Game = $Game; Kind = $g.Name; Count = if ($g.Name -eq 'candidate') { @($g.Group | Where-Object { -not $_.Decision }).Count } else { $g.Count } } })
    @($keep + $new) | Export-Csv -Path $BaselineFile -NoTypeInformation -Encoding UTF8
    Write-Output "Baseline written: $BaselineFile"
    exit 0
}
$was = if ($baseline.ContainsKey('candidate')) { $baseline['candidate'] } else { $null }
if ($null -eq $was) { Write-Output "No baseline for $Game yet (-UpdateBaseline writes it)."; exit 0 }
Write-Output "Baseline: $was undecided candidates."
if ($undecided.Count -gt $was) { Write-Output "$($undecided.Count - $was) more undecided candidates than the baseline."; exit 1 }
