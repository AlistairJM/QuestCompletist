<#
Lists the quests a game's quest data has lost since a git ref, with ID, name, zone and level, so that nobody
removes a quest unseen: run it before every pull request that touches data\quests.jsonl (retail) or
data\forever\quests.jsonl (Forever), and show the list to the user. Report-only.

  .\Show-RemovedQuests.ps1 -Game forever
  .\Show-RemovedQuests.ps1 -Game retail -Base origin/master

A removed quest needs a row in docs\plans\quest-removal-decisions.csv (Game, Quest, Decision, Reason): REMOVE
once the user has agreed it goes, KEEP when it must stay. Exit 1 when a removed quest has no REMOVE row, or
when a KEEP quest is missing from the data; exit 0 otherwise. Import-ForeverData.ps1 makes the same check
itself before it writes anything.
#>
param(
    [string]$Game = 'retail',
    [string]$Base = 'origin/master',
    [string]$RepoDir = (Join-Path $PSScriptRoot '..'),
    [string]$DataDir = '',
    [string]$DecisionsFile = ''
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\QuestRemovals.ps1"
if ($Game -notin 'retail', 'forever') { throw "-Game must be retail or forever." }
if (-not $DataDir) { $DataDir = if ($Game -eq 'retail') { Join-Path $RepoDir 'data' } else { Join-Path $RepoDir 'data\forever' } }
if (-not $DecisionsFile) { $DecisionsFile = Join-Path $RepoDir 'docs\plans\quest-removal-decisions.csv' }
$relative = if ($Game -eq 'retail') { 'data/quests.jsonl' } else { 'data/forever/quests.jsonl' }

$oldLines = @(git -C $RepoDir show "${Base}:$relative")
if ($LASTEXITCODE -ne 0) { throw "git could not show $relative at $Base." }
$newPath = Join-Path $DataDir 'quests.jsonl'
$newIds = Read-QuestIdLines ([IO.File]::ReadAllText($newPath))
$removed = @(Find-RemovedQuests ($oldLines -join "`n") $newIds)

$remove = @{}; $keep = @{}
foreach ($d in (Read-RemovalDecisions $DecisionsFile $Game)) {
    if ($d.Decision -eq 'REMOVE') { $remove[$d.Quest] = $d } else { $keep[$d.Quest] = $d }
}
$undecided = @($removed | Where-Object { -not $remove[$_.Id] })
$keptButGone = @($keep.Keys | Where-Object { -not $newIds.ContainsKey($_) } | Sort-Object)

if ($removed.Count) {
    Write-Output "Quests in $relative at $Base that $newPath no longer has ($($removed.Count)):"
    Format-RemovedQuests $removed $remove | ForEach-Object { Write-Output $_ }
}
else { Write-Output "No quest has left $relative since $Base." }
if ($keptButGone.Count) { Write-Output "Quests with a KEEP decision that are missing from the data: $($keptButGone -join ', ')." }
if ($undecided.Count) { Write-Output "$($undecided.Count) have no REMOVE decision in ${DecisionsFile}: show the list to the user before going on." }
if ($undecided.Count -or $keptButGone.Count) { exit 1 }
exit 0
