<#
Step 2n of a sweep (docs/maintenance.md), and for WoW: Forever part of step 10 after the importer: which playable races can
earn each faction's reputation, and whether the game ever shows its bar, from the game's own Faction and ChrRaces tables
(FactionReach.ps1 says how they're read), into data\factions.jsonl (Forever: data\forever\factions.jsonl), which
Build-AddonData.ps1 turns into qcFactionRaces and qcFactionHidden. The quest list's tooltip leaves out a reputation reward
that the character's race can't earn, such as the other side's faction in a reward list that names both (Battle for
Azeroth's world quests list The Honorbound and the 7th Legion), or that the game never shows, such as the "Horde" and
"Alliance" headers. The data keeps every reward as Blizzard lists it (the client tables audit, opportunity 5, part 1, the
user's choice on 17 October 2026).

It downloads the build's Faction and ChrRaces into tools\ (<table>-<build>.csv) when they aren't there, and reports what
changed against the data file and how many of the game's reward rows each kind leaves out for someone. -WhatIf reports
without writing. Exit 0.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-FactionReach.ps1 -Game retail -Build <retail build> -WhatIf
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-FactionReach.ps1 -Game forever -Build <Forever build>
#>
param(
    [ValidateSet('retail', 'forever')][string]$Game = 'retail',
    [string]$Build = '',
    [string]$ToolsDir = '',
    [string]$DataDir = '',
    [string]$AddonDir = '',
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $Build) { throw 'Give -Build: the build of the client tables to read.' }
if (-not $ToolsDir) { $ToolsDir = $PSScriptRoot }
if (-not $DataDir) { $DataDir = if ($Game -eq 'retail') { Join-Path $PSScriptRoot '..\data' } else { Join-Path $PSScriptRoot '..\data\forever' } }
if (-not $AddonDir) { $AddonDir = if ($Game -eq 'retail') { Join-Path $PSScriptRoot '..\QuestCompletist' } else { Join-Path $PSScriptRoot '..\QuestCompletist\Forever' } }
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\FactionReach.ps1"
. "$PSScriptRoot\QuestReputation.ps1"

function Get-BuildTable([string]$table) {
    $path = Join-Path $ToolsDir "$table-$Build.csv"
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path -Headers @{ 'User-Agent' = 'QuestCompletist-tools' }
    }
    return $path
}

$raceRows = Import-Csv (Get-BuildTable 'ChrRaces')
$reach = Get-FactionReach (Import-Csv (Get-BuildTable 'Faction')) $raceRows
$records = @(Get-FactionReachRecords $reach)
# The playable races of each side (ChrRaces.Alliance: 0 the Alliance, 1 the Horde), for the quest data's faction 1 and 2.
$sideRaces = @{ 1 = @(); 2 = @() }
foreach ($row in $raceRows) {
    if (([long]$row.Flags -band 1) -ne 0 -or [int]$row.PlayableRaceBit -lt 0) { continue }
    if ([int]$row.Alliance -eq 0) { $sideRaces[1] += [int]$row.ID } elseif ([int]$row.Alliance -eq 1) { $sideRaces[2] += [int]$row.ID }
}
$questSide = @{}
foreach ($line in [IO.File]::ReadLines((Join-Path (Resolve-Path $DataDir).Path 'quests.jsonl'))) { if ($line -match '^\{"id":(\d+),.*?"faction":(\d)') { $questSide[[int]$Matches[1]] = [int]$Matches[2] } }

$rewards = @{}
if ($Game -eq 'forever') {
    foreach ($r in (Read-JsonLines (Join-Path (Resolve-Path $DataDir).Path 'reputation.jsonl'))) { if ($r.amount) { $rewards["$($r.quest)|$($r.faction)"] = [int]$r.faction } }
} else {
    $rewardSets = Get-QuestReputation ([IO.File]::ReadAllText((Join-Path $AddonDir 'qcQuest.lua')))
    foreach ($quest in $rewardSets.Keys) { foreach ($faction in $rewardSets[$quest].Keys) { $rewards["$quest|$faction"] = [int]$faction } }
}
# A row counts when a race of the quest's side (both sides for faction 3) can't earn the faction, or the faction is never
# shown. It goes by side, not by the quest's races, so a quest only one race takes can count though its race earns it.
$partial = 0; $hidden = 0; $quests = @{}; $unknown = @{}
foreach ($key in $rewards.Keys) {
    $f = $reach[$rewards[$key]]
    if (-not $f) { $unknown[$rewards[$key]] = $true; continue }
    $quest = [int]$key.Split('|')[0]
    if (-not $f.Shown) { $hidden++; $quests[$quest] = $true; continue }
    $side = [int]$questSide[$quest]
    $takers = if ($side -eq 1 -or $side -eq 2) { $sideRaces[$side] } else { $sideRaces[1] + $sideRaces[2] }
    if (@($takers | Where-Object { $f.Races -notcontains $_ }).Count -and -not $f.Everyone) { $partial++; $quests[$quest] = $true }
}

$file = Join-Path (Resolve-Path $DataDir).Path 'factions.jsonl'
$old = @{}
if (Test-Path $file) { foreach ($f in (Read-JsonLines $file)) { $old[[int]$f.faction] = (ConvertTo-FactionJsonLines @($f)) } }
$added = @(); $changed = @()
foreach ($r in $records) {
    if (-not $old.ContainsKey([int]$r.faction)) { $added += $r.faction }
    elseif ($old[[int]$r.faction] -cne (ConvertTo-FactionJsonLines @($r))) { $changed += $r.faction }
}
$gone = @($old.Keys | Where-Object { $id = $_; -not @($records | Where-Object { [int]$_.faction -eq $id }).Count } | Sort-Object)

"Factions with a standing: $($reach.Count); some race can't earn $(@($records | Where-Object { $null -ne $_.races }).Count) (nobody $(@($records | Where-Object { $null -ne $_.races -and -not @($_.races).Count }).Count)); never shown $(@($records | Where-Object { $_.hidden }).Count)."
"Reward rows ($($rewards.Count)) the tooltip leaves out for some character of the quest's side: $partial on a faction one of its races can't earn, $hidden on one never shown; $($quests.Count) quests." +
    $(if ($unknown.Count) { " $($unknown.Count) factions keep no standing: " + (($unknown.Keys | Sort-Object) -join ', ') } else { '' })
"Added $($added.Count), changed $($changed.Count), gone $($gone.Count)" + $(if ($added.Count + $changed.Count + $gone.Count -gt 0 -and $added.Count + $changed.Count + $gone.Count -le 40) { ": " + ((@($added | ForEach-Object { "+$_" }) + @($changed | ForEach-Object { "~$_" }) + @($gone | ForEach-Object { "-$_" })) -join ' ') } else { '' })

if (-not $WhatIf -and ($added.Count + $changed.Count + $gone.Count -gt 0)) { Save-FactionData $records $DataDir $AddonDir }
