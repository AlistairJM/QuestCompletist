<#
Gives quests the game calls PvP the `pvp` field of the data files (qcQuestPvP in the addon), for both
games. Each quest is decided by the first source that has an answer for it, in this order:
  1 the game's quest cache (questInfo, step 2e): the game's own kind of the quest
      retail   41 PvP, 113 PvP World Quest, 255 War Mode PvP, 256 PvP Conquest, 278 PvP Elite World Quest
      forever  41 PvP (the only PvP kind its client has)
  2 retail: Blizzard's API (tools\quest_api_cache, step 1), its quest type 41, the same kind as the cache's
  3 retail: the client's task table (QuestV2CliTask.csv, step 1b), its QuestInfoID, for task quests
  4 the emulator, for a quest the game hasn't answered: TrinityCore's QuestInfoID (retail), CMaNGOS's Type
    (Forever), whose 41 is the same kind. Forever's cache holds only what the beta has answered, so this is
    where its battleground quests come from.
An answer of the game that isn't PvP stands: a source below it that says PvP is listed as a disagreement
and not applied (CMaNGOS calls "Arena Grandmaster" PvP, the game's record says it is nothing).
On 13 October 2026 the sources agreed wherever more than one answered: the API and the cache on all 157
PvP quests, TrinityCore on all 343 the cache tags, CMaNGOS on 6 of 7.

The hand decisions in -DecisionsFile (docs\plans\quest-pvp-decisions.csv: Game, QuestID, Name, Decision PVP
or NOTPVP, Evidence) come before every source: "Arena Grandmaster" is PVP by the user's word. A decision a
source already gives is listed as not needed, and one for a quest not in the data as out of date.

Only sets the field. A quest with pvp that no source calls PvP is listed and left as it is. Last it lists,
for a look and no more, the quests in the places PvP happens (battlegrounds, Wintergrasp, Tol Barad, Ashran)
that no source tags: a judgement of ours, not the data's.

Reads tools\<game>_quest_cache_<build>.jsonl (the newest unless -Build is given), the API cache, the task
table, TrinityCore's tools\tdb\TDB_full_world_*.sql or CMaNGOS's tools\ClassicDB_*.sql.gz; a source that is
missing is named and skipped. Safe to rerun: a second run changes nothing. With -WhatIf it only reports;
otherwise it saves through AddonData.ps1, which rebuilds the Lua.
#>
param(
    [ValidateSet('retail', 'forever')]
    [string]$Game = 'retail',
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = '',
    [string]$AddonDir = '',
    [string]$Build = '',
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-pvp-decisions.csv'),
    [string]$TdbFile = '',
    [string]$CmangosDump = '',
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [int]$Examples = 25,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"
if (-not $DataDir) { $DataDir = Join-Path $PSScriptRoot $(if ($Game -eq 'forever') { '..\data\forever' } else { '..\data' }) }
if (-not $AddonDir) { $AddonDir = Join-Path $PSScriptRoot $(if ($Game -eq 'forever') { '..\QuestCompletist\Forever' } else { '..\QuestCompletist' }) }

$pvpKinds = if ($Game -eq 'forever') { @(41) } else { @(41, 113, 255, 256, 278) }
$kindName = @{ 41 = 'PvP'; 113 = 'PvP World Quest'; 255 = 'War Mode PvP'; 256 = 'PvP Conquest'; 278 = 'PvP Elite World Quest' }
$pvpPlaces = @('Alterac Valley', 'Warsong Gulch', 'Arathi Basin', 'Eye of the Storm', 'Strand of the Ancients', 'Isle of Conquest',
    'Wintergrasp', 'Tol Barad', 'Ashran', 'Battle for Gilneas', 'Twin Peaks', 'Deepwind Gorge', 'Silvershard Mines',
    'Temple of Kotmogu', 'Seething Shore', 'Rated PvP', 'World PvP')

function Read-Dump([string]$file, [string]$table, [string]$columns) {
    $saved = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try { $rows = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $file $table $columns) } finally { [Console]::OutputEncoding = $saved }
    if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $table" }
    return $rows
}

if (-not $Build) {
    $newest = Get-ChildItem "$ToolsDir\${Game}_quest_cache_*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match "^${Game}_quest_cache_\d+\.\d+\.\d+\.\d+$" } |
        Sort-Object { [version]($_.BaseName -replace "^${Game}_quest_cache_") } | Select-Object -Last 1
    if (-not $newest) { throw "No ${Game}_quest_cache_<build>.jsonl under ${ToolsDir}: run Read-QuestCache.ps1 first, or give -Build." }
    $Build = $newest.BaseName -replace "^${Game}_quest_cache_"
}
$cacheFile = Join-Path $ToolsDir "${Game}_quest_cache_$Build.jsonl"
if (-not (Test-Path $cacheFile)) { throw "There's no $cacheFile." }

# Each source's answer: a hashtable of quest ID to the kind it names (0 for none).
$cache = @{}
foreach ($line in [IO.File]::ReadLines($cacheFile)) {
    $line = $line.Trim().TrimEnd(',')
    if ($line -notmatch '^\{"id":(\d+)') { continue }
    $record = $line | ConvertFrom-Json
    $cache[[int]$record.id] = if ($null -ne $record.questInfo) { [int]$record.questInfo } else { 0 }
}
$skipped = @()
$api = @{}; $task = @{}; $emulator = @{}; $emulatorName = ''
if ($Game -eq 'retail') {
    $apiDir = Join-Path $ToolsDir 'quest_api_cache'
    if (Test-Path $apiDir) {
        foreach ($file in [IO.Directory]::EnumerateFiles($apiDir, '*.json')) {
            if ([IO.File]::ReadAllText($file).Contains('/quest/type/41?')) { $api[[int][IO.Path]::GetFileNameWithoutExtension($file)] = 41 }
        }
    } else { $skipped += "Blizzard's API cache (tools\quest_api_cache)" }
    $taskFile = Join-Path $ToolsDir 'QuestV2CliTask.csv'
    if (Test-Path $taskFile) { foreach ($row in (Import-Csv $taskFile)) { $task[[int]$row.ID] = [int]$row.QuestInfoID } }
    else { $skipped += 'the task table (QuestV2CliTask.csv)' }
    if (-not $TdbFile) { $TdbFile = @(Get-ChildItem (Join-Path $ToolsDir 'tdb\TDB_full_world_*.sql') -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName)[0] }
    if ($TdbFile -and (Test-Path $TdbFile)) {
        $emulatorName = 'TrinityCore'
        foreach ($line in (Read-Dump $TdbFile quest_template '1,6')) { $f = $line.Split("`t"); $emulator[[int]$f[0]] = [int]$f[1] }
    } else { $skipped += "TrinityCore's dump" }
} else {
    if (-not $CmangosDump) { $CmangosDump = @(Get-ChildItem (Join-Path $ToolsDir 'ClassicDB_*.sql.gz') -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName)[0] }
    if ($CmangosDump -and (Test-Path $CmangosDump)) {
        $emulatorName = 'CMaNGOS'
        $tempSql = [IO.Path]::GetTempFileName()
        try {
            $in = [IO.File]::OpenRead($CmangosDump); $gz = New-Object System.IO.Compression.GZipStream($in, [IO.Compression.CompressionMode]::Decompress)
            $out = [IO.File]::Create($tempSql); $gz.CopyTo($out); $out.Close(); $gz.Close(); $in.Close()
            foreach ($line in (Read-Dump $tempSql quest_template '1,7')) { $f = $line.Split("`t"); $emulator[[int]$f[0]] = [int]$f[1] }
        } finally { Remove-Item $tempSql -ErrorAction SilentlyContinue }
    } else { $skipped += "CMaNGOS's dump" }
}

$records = Read-QuestData $DataDir
$decision = @{}
foreach ($row in @(Import-Csv $DecisionsFile -Encoding UTF8 | Where-Object { $_.Game -eq $Game })) {
    if ($row.Decision -notin 'PVP', 'NOTPVP') { throw "$DecisionsFile gives quest $($row.QuestID) the decision '$($row.Decision)': use PVP or NOTPVP." }
    if ($decision.ContainsKey([int]$row.QuestID)) { throw "$DecisionsFile has quest $($row.QuestID) twice." }
    $decision[[int]$row.QuestID] = $row.Decision -eq 'PVP'
}
$inData = @{}
foreach ($q in $records) { $inData[[int]$q.id] = $true }
$stale = @($decision.Keys | Where-Object { -not $inData.ContainsKey($_) })
$notNeeded = @()
$sources = @(
    @{ Name = 'the game'; Answers = $cache },
    @{ Name = "Blizzard's API"; Answers = $api },
    @{ Name = 'the task table'; Answers = $task },
    @{ Name = $emulatorName; Answers = $emulator })
$changes = @(); $same = 0; $bySource = [ordered]@{}; $disagree = @(); $notPvp = @(); $untagged = @(); $unanswered = 0
foreach ($q in $records) {
    $id = [int]$q.id
    $decided = $null; $by = ''
    foreach ($source in $sources) {
        if ($source.Answers.ContainsKey($id)) { $decided = ($pvpKinds -contains $source.Answers[$id]); $by = $source.Name; break }
    }
    if ($decision.ContainsKey($id)) {
        if ($null -ne $decided -and $decided -eq $decision[$id]) { $notNeeded += $q }
        $decided = $decision[$id]; $by = 'a decision'
    }
    if ($null -eq $decided) { $unanswered++; $decided = $false }
    # A source below the one that decided, that calls the quest PvP: the game's "no" stands.
    if (-not $decided -and $by -eq 'the game') {
        $below = $sources[1..3] | Where-Object { $_.Answers.ContainsKey($id) -and ($pvpKinds -contains $_.Answers[$id]) } | Select-Object -First 1
        if ($below) { $disagree += [pscustomobject]@{ Quest = $q; Source = $below.Name; Game = $cache[$id] } }
    }
    if ($decided) {
        if ($q.pvp) { $same++ } else { $changes += $q; $bySource[$by] = 1 + [int]$bySource[$by] }
    } elseif ($q.pvp) {
        $notPvp += $q
    } elseif ($pvpPlaces | Where-Object { $q.zone -like "*$_*" }) {
        $untagged += $q
    }
}

"Build $Build ($Game): the game's cache has $($cache.Count) quests; no source answers for $unanswered of ours."
"Read: " + (($sources | Where-Object { $_.Name } | ForEach-Object { "$($_.Name) $($_.Answers.Count)" }) -join ', ') + $(if ($skipped.Count) { ". Not found, skipped: " + ($skipped -join ', ') } else { '' }) + '.'
"PvP kinds: " + (($pvpKinds | ForEach-Object { "$_ $($kindName[$_])" }) -join ', ') + "."
"{0} quests get pvp ({1}), {2} already have it." -f $changes.Count, (($bySource.Keys | ForEach-Object { "$_ $($bySource[$_])" }) -join ', '), $same
foreach ($id in $stale) { "A decision for quest $id, which isn't in the data (out of date)." }
foreach ($q in $notNeeded) { "The decision for quest $($q.id) $($q.name) isn't needed: a source says the same." }
if ($disagree.Count) {
    "A source calls the quest PvP but the game's record says another kind ($($disagree.Count)), left untagged:"
    foreach ($d in ($disagree | Select-Object -First $Examples)) { "  {0} {1}: {2} says PvP, the game says kind {3}" -f $d.Quest.id, $d.Quest.name, $d.Source, $d.Game }
}
if ($notPvp.Count) {
    "Has pvp, but no source calls the quest PvP ($($notPvp.Count)), left as it is:"
    foreach ($q in ($notPvp | Select-Object -First $Examples)) { "  {0} {1}" -f $q.id, $q.name }
}
if ($untagged.Count) {
    "In the places PvP happens, but no source tags them ($($untagged.Count)); a judgement for a look, nothing is changed:"
    foreach ($group in ($untagged | Group-Object zone | Sort-Object Count -Descending)) {
        "  {0}: {1}" -f $group.Name, $group.Count
    }
}
if ($WhatIf) {
    if ($changes.Count) { "Would set pvp on ($($changes.Count)):" }
    foreach ($q in ($changes | Select-Object -First $Examples)) { "  {0} {1}: {2}" -f $q.id, $q.name, $q.zone }
    if ($changes.Count -gt $Examples) { "  ... and $($changes.Count - $Examples) more" }
    return
}
if ($changes.Count -eq 0) { return }
foreach ($q in $changes) { Set-RecordField $q 'pvp' 1 }
Save-QuestData $records $DataDir $AddonDir
