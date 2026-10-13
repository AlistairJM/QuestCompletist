<#
Gives quests the game calls PvP the `pvp` field of the data files (qcQuestPvP in the addon), for both
games. The game's own record of each quest says what kind it is (questInfo in the quest cache that
Read-QuestCache.ps1 writes, step 2e):
  retail   41 PvP, 113 PvP World Quest, 255 War Mode PvP, 256 PvP Conquest, 278 PvP Elite World Quest
  forever  41 PvP (the only PvP kind its client has)
A quest the cache doesn't know isn't tagged: the game's tag is all this goes by. Forever's cache holds
only what the beta has answered, so most of its battleground quests have no answer yet.

Only sets the field. A quest with pvp whose cache record says another kind is listed and left as it is.
Last it lists, for a look and no more, the quests in the places PvP happens (battlegrounds, Wintergrasp,
Tol Barad, Ashran, the arenas) that the game doesn't tag: those are a judgement of ours, not the game's.

Reads tools\<game>_quest_cache_<build>.jsonl, the newest unless -Build is given. Safe to rerun: a second
run changes nothing. With -WhatIf it only reports; otherwise it saves through AddonData.ps1, which
rebuilds the Lua.
#>
param(
    [ValidateSet('retail', 'forever')]
    [string]$Game = 'retail',
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = '',
    [string]$AddonDir = '',
    [string]$Build = '',
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

if (-not $Build) {
    $newest = Get-ChildItem "$ToolsDir\${Game}_quest_cache_*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match "^${Game}_quest_cache_\d+\.\d+\.\d+\.\d+$" } |
        Sort-Object { [version]($_.BaseName -replace "^${Game}_quest_cache_") } | Select-Object -Last 1
    if (-not $newest) { throw "No ${Game}_quest_cache_<build>.jsonl under ${ToolsDir}: run Read-QuestCache.ps1 first, or give -Build." }
    $Build = $newest.BaseName -replace "^${Game}_quest_cache_"
}
$cacheFile = Join-Path $ToolsDir "${Game}_quest_cache_$Build.jsonl"
if (-not (Test-Path $cacheFile)) { throw "There's no $cacheFile." }

$kind = @{}
foreach ($line in [IO.File]::ReadLines($cacheFile)) {
    $line = $line.Trim().TrimEnd(',')
    if ($line -notmatch '^\{"id":(\d+)') { continue }
    $record = $line | ConvertFrom-Json
    $kind[[int]$record.id] = if ($null -ne $record.questInfo) { [int]$record.questInfo } else { 0 }
}

$records = Read-QuestData $DataDir
$changes = @(); $same = 0; $byKind = @{}; $disagree = @(); $untagged = @(); $unanswered = 0
foreach ($q in $records) {
    $id = [int]$q.id
    $known = $kind.ContainsKey($id)
    if (-not $known) { $unanswered++ }
    $isPvp = $known -and ($pvpKinds -contains $kind[$id])
    if ($isPvp) {
        if ($q.pvp) { $same++ } else { $changes += $q; $byKind[$kind[$id]] = 1 + [int]$byKind[$kind[$id]] }
    } elseif ($q.pvp) {
        $disagree += $q
    } elseif ($pvpPlaces | Where-Object { $q.zone -like "*$_*" }) {
        $untagged += $q
    }
}

"Build $Build ($Game): $($kind.Count) quests in the cache, $unanswered of ours it doesn't know."
"PvP kinds: " + (($pvpKinds | ForEach-Object { "$_ $($kindName[$_])" }) -join ', ') + "."
"{0} quests get pvp ({1}), {2} already have it." -f $changes.Count, (($byKind.Keys | Sort-Object | ForEach-Object { "$($kindName[$_]) $($byKind[$_])" }) -join ', '), $same
if ($disagree.Count) {
    "Has pvp, but the cache says another kind ($($disagree.Count)), left as it is:"
    foreach ($q in ($disagree | Select-Object -First $Examples)) { "  {0} {1}: kind {2}" -f $q.id, $q.name, $kind[[int]$q.id] }
}
if ($untagged.Count) {
    "In the places PvP happens, but the game doesn't tag them ($($untagged.Count)); a judgement for a look, nothing is changed:"
    foreach ($group in ($untagged | Group-Object zone | Sort-Object Count -Descending)) {
        $noAnswer = @($group.Group | Where-Object { -not $kind.ContainsKey([int]$_.id) }).Count
        "  {0}: {1} ({2} the cache doesn't know)" -f $group.Name, $group.Count, $noAnswer
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
