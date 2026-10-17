<#
Step 1e of a sweep (docs/maintenance.md), both games, after step 2e has read the newest quest cache: the races each
quest's data allows against the race list the game's own record of it gives (QuestRaces.ps1 says how they're compared).
Only where the game lists races: a quest it lists none for is open to every race in its eyes, and a restriction of ours
there is ours to keep (the 1,679 retail quests of 17 October 2026, counted, not listed).

Each difference needs a row in docs\plans\quest-race-decisions.csv: FIX takes the game's list (the quest's race mask and
faction from it), KEEP keeps ours. On retail the run writes the FIX rows into data\quests.jsonl; on WoW: Forever the
importer gives a quest the cache's list (step 10), so a difference there is a finding. A difference with no row is a
finding, and so is a FIX row the game's list no longer backs. Open-items row 17 (the user's choices of 12 and 17 October
2026). It writes tools\quest_races_<game>.csv (or -OutFile), one row per difference. -WhatIf reports without writing.
Exit 1 when there is a finding.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Compare-QuestRaces.ps1 -Game retail -Build <retail build> -WhatIf
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Compare-QuestRaces.ps1 -Game forever -Build <Forever build>
#>
param(
    [ValidateSet('retail', 'forever')][string]$Game = 'retail',
    [string]$Build = '',
    [string]$QuestCacheFile = '',
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-race-decisions.csv'),
    [string]$OutFile = '',
    [string]$ToolsDir = '',
    [string]$DataDir = '',
    [string]$AddonDir = '',
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $Build) { throw 'Give -Build: the build of the client''s race table to read.' }
if (-not $ToolsDir) { $ToolsDir = $PSScriptRoot }
if (-not $DataDir) { $DataDir = if ($Game -eq 'retail') { Join-Path $PSScriptRoot '..\data' } else { Join-Path $PSScriptRoot '..\data\forever' } }
if (-not $AddonDir) { $AddonDir = if ($Game -eq 'retail') { Join-Path $PSScriptRoot '..\QuestCompletist' } else { Join-Path $PSScriptRoot '..\QuestCompletist\Forever' } }
if (-not $OutFile) { $OutFile = Join-Path $ToolsDir "quest_races_$Game.csv" }
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\QuestRaces.ps1"
. "$PSScriptRoot\QuestCacheFiles.ps1"

$racePath = Join-Path $ToolsDir "ChrRaces-$Build.csv"
if (-not (Test-Path $racePath)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/ChrRaces/csv?build=$Build" -OutFile $racePath -Headers @{ 'User-Agent' = 'QuestCompletist-tools' } }
$races = @(Get-ComparedRaces (Import-Csv $racePath))
$decisions = Read-QuestRaceDecisions $DecisionsFile $Game
if (-not $QuestCacheFile) { $QuestCacheFile = Get-QuestCacheFiles $ToolsDir $Game | Select-Object -Last 1 -ExpandProperty FullName }
if (-not $QuestCacheFile) { throw "There's no quest cache of $Game under $ToolsDir. Run step 2e (Read-QuestCache.ps1) first." }
Get-QuestCacheWarning $QuestCacheFile | ForEach-Object { Write-Warning $_ }
$listed = @{}; $held = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($line in [IO.File]::ReadLines($QuestCacheFile)) {
    $c = $line | ConvertFrom-Json
    [void]$held.Add([int]$c.id)
    if ($c.races -and @($c.races).Count) { $listed[[int]$c.id] = @($c.races) }
}

$quests = Read-QuestData $DataDir
$names = { param($list) ($list | ForEach-Object { $_.Name }) -join ' ' }
$report = New-Object System.Collections.Generic.List[object]
$findings = New-Object System.Collections.Generic.List[string]
$classes = [ordered]@{ contradiction = 0; stale = 0; narrowing = 0; shown = 0; crosses = 0 }
$fixes = @{}; $kept = 0; $compared = 0; $ourOnly = 0
foreach ($q in $quests) {
    $id = [int]$q.id
    if (-not $listed.ContainsKey($id)) {
        if ($held.Contains($id) -and @(Get-DataRaces $races ([long]$q.race) ([int]$q.faction)).Count -lt $races.Count) { $ourOnly++ }
        continue
    }
    $compared++
    $d = Compare-QuestRaceList $races ([long]$q.race) ([int]$q.faction) $listed[$id]
    if (-not $d) {
        if ($decisions.ContainsKey($id) -and $decisions[$id].Decision -eq 'KEEP') { $findings.Add("$id $($q.name): a KEEP row, but the data and the game now agree") }
        continue
    }
    $classes[$d.Class]++
    $decision = if ($decisions.ContainsKey($id)) { $decisions[$id].Decision } else { '' }
    $result = switch ($decision) {
        'FIX' {
            if (-not $d.Mask) { $findings.Add("$id $($q.name): a FIX row, but the game lists only races our bits can't name"); 'finding: nothing to take' }
            elseif ($Game -eq 'retail') { $fixes[$id] = $d; "race $($d.Mask), faction $($d.Faction)" }
            else { $findings.Add("$id $($q.name): $($d.Class), which the importer should have taken from the cache"); 'finding: the importer''s' }
        }
        'KEEP' { $kept++; 'kept' }
        default { $findings.Add("$id $($q.name): $($d.Class) with no decision row"); 'finding: no decision' }
    }
    $report.Add([pscustomobject]@{ Game = $Game; QuestID = $id; Name = $q.name; Zone = $q.zone; Class = $d.Class; Faction = [int]$q.faction; Race = [long]$q.race
        Hide = (& $names $d.Hide); Show = (& $names $d.Show); Decision = $decision; Result = $result })
}
foreach ($id in ($decisions.Keys | Sort-Object)) {
    if ($decisions[$id].Decision -eq 'FIX' -and -not $listed.ContainsKey($id)) { $findings.Add("$id $($decisions[$id].Name): a FIX row, but the game's record lists no races for it now") }
}
$report | Export-Csv $OutFile -NoTypeInformation -Encoding UTF8

"Races, $Game ($(Split-Path -Leaf $QuestCacheFile), ChrRaces $Build): the game lists races for $compared of our quests; $($report.Count) differ (" +
    (($classes.Keys | ForEach-Object { "$_ $($classes[$_])" }) -join ', ') + "). Decided: FIX $($fixes.Count + @($report | Where-Object { $_.Result -like 'finding: the importer*' }).Count), KEEP $kept."
"Our own restrictions where the game lists no races (kept, not listed): $ourOnly."
"Findings: $($findings.Count)" + $(if ($findings.Count) { ": " + (($findings | Select-Object -First 20) -join '; ') } else { '' })
"quests.jsonl: $($fixes.Count) race lists taken from the game" + $(if ($fixes.Count -and $fixes.Count -le 40) { ": " + (($fixes.Keys | Sort-Object) -join ', ') } else { '' }) + '.'
"Report: $OutFile ($($report.Count) rows)."

if (-not $WhatIf -and $fixes.Count) {
    foreach ($q in $quests) {
        $d = $fixes[[int]$q.id]
        if ($d) { Set-RecordField $q 'race' ([long]$d.Mask); Set-RecordField $q 'faction' ([long]$d.Faction) }
    }
    Save-QuestData $quests $DataDir $AddonDir
}
exit $(if ($findings.Count) { 1 } else { 0 })
