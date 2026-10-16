<#
Step 6e of a sweep (docs/maintenance.md), and for WoW: Forever part of step 10 after the importer: the items that start
quests, from the game's own client tables, into data\startitems.jsonl (Forever: data\forever\startitems.jsonl), which
Build-AddonData.ps1 turns into qcQuestStartItems. The quest list's tooltip shows "Starts from: <item>", named by the game,
with what the item itself requires (open-items row 19; docs/plans/client-tables-audit.md, opportunity 2).

For each item that starts one of our quests, by its ItemSparse.StartQuestID or by a spell it casts when used, picked up
or looted (client tables audit, opportunity 3), it keeps the item's faction flag, level, profession, reputation and races
(StartItems.ps1 says how each is read). It downloads the build's ItemSparse, ChrRaces, ItemEffect, ItemXItemEffect and
SpellEffect into tools\ (<table>-<build>.csv) when they aren't there, and reports:
  - what changed against the data file: items added, gone and changed, and items whose quest has left the data;
  - the quests whose faction their start items contradict (every item for one side, the quest for the other or both):
    findings for a decision, as 11002, 38194, 38202 and 56071 were on 16 October 2026;
  - how many items start quests the data lacks (Find-MissingQuests.ps1, step 6, lists them).
-WhatIf reports without writing. Exit 0, or 1 when the quests' factions and their items disagree.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-QuestStartItems.ps1 -Game retail -Build <retail build> -WhatIf
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-QuestStartItems.ps1 -Game forever -Build <Forever build>
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
. "$PSScriptRoot\StartItems.ps1"

function Get-BuildTable([string]$table) {
    $path = Join-Path $ToolsDir "$table-$Build.csv"
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path -Headers @{ 'User-Agent' = 'QuestCompletist-tools' }
    }
    return $path
}

$quests = @{}
foreach ($q in (Read-QuestData $DataDir)) { $quests[[int]$q.id] = $q }
$itemPath = Get-BuildTable 'ItemSparse'
$racePath = Get-BuildTable 'ChrRaces'
$spellStarts = Get-SpellStartItems (Import-Csv (Get-BuildTable 'ItemEffect')) (Import-Csv (Get-BuildTable 'ItemXItemEffect')) `
    (Import-Csv (Get-BuildTable 'SpellEffect') | Where-Object { $_.Effect -eq '150' })
$allStarts = @{}
foreach ($quest in $spellStarts.Values) { $allStarts[$quest] = $true }
$namedQuest = @{}
$itemRows = Import-Csv $itemPath | Where-Object { ($_.StartQuestID -and $_.StartQuestID -ne '0') -or $spellStarts.ContainsKey([int]$_.ID) } | ForEach-Object {
    if ($_.StartQuestID -and $_.StartQuestID -ne '0') { $allStarts[[int]$_.StartQuestID] = $true; $namedQuest[[int]$_.ID] = [int]$_.StartQuestID }
    $_
}
$records = Get-StartItemRecords $itemRows (Import-Csv $racePath) $quests $spellStarts
$bySpell = @($records | Where-Object { $namedQuest[$_.item] -ne $_.quest })

$file = Join-Path (Resolve-Path $DataDir).Path 'startitems.jsonl'
$current = if (Test-Path $file) { @(Read-JsonLines $file) } else { @() }
$key = { param($s) (@($s.item, $s.quest, $s.side, $s.level, $s.skill, $s.skillRank, $s.rep, $s.repRank) -join '|') + '|' + (@($s.races) -join ',') }
$was = @{}; foreach ($s in $current) { $was[[int]$s.item] = & $key $s }
$now = @{}; foreach ($s in $records) { $now[$s.item] = & $key $s }
$added = @($now.Keys | Where-Object { -not $was.ContainsKey($_) })
$gone = @($was.Keys | Where-Object { -not $now.ContainsKey($_) })
$changed = @($now.Keys | Where-Object { $was.ContainsKey($_) -and $was[$_] -cne $now[$_] })
$orphans = @($current | Where-Object { -not $quests.ContainsKey([int]$_.quest) })
$missing = @($allStarts.Keys | Where-Object { -not $quests.ContainsKey($_) })

Write-Output "== $Game $Build"
Write-Output ("{0} items start {1} of our {2} quests; {3} carry a faction, {4} a level, {5} a profession, {6} a reputation, {7} races." -f
    $records.Count, @($records | Select-Object -ExpandProperty quest -Unique).Count, $quests.Count,
    @($records | Where-Object side).Count, @($records | Where-Object level).Count, @($records | Where-Object skill).Count,
    @($records | Where-Object rep).Count, @($records | Where-Object races).Count)
Write-Output "Against $(Split-Path -Leaf $file): $($added.Count) added, $($gone.Count) gone ($($orphans.Count) of them for quests no longer in the data), $($changed.Count) changed."
Write-Output "$($bySpell.Count) of the items start their quest by a spell they cast when used, picked up or looted, not by StartQuestID."
Write-Output "$($missing.Count) quests the data lacks are started by an item: Find-MissingQuests.ps1 (step 6) lists them."

$disagree = Get-StartItemFactionDisagreements $records $quests
$sideName = @{ 1 = 'Alliance'; 2 = 'Horde'; 3 = 'both' }
# The quest's own record, the server's (the newest quest cache), names its faction when its races are one side's: where
# that is the data's, the item is the odd one out (Forever's 79358, on 16 October 2026), and there's nothing to decide.
$cacheFile = Get-ChildItem (Join-Path $ToolsDir "$($Game)_quest_cache_*.jsonl") -ErrorAction SilentlyContinue |
    Sort-Object { [version]($_.BaseName -replace '^\w+_quest_cache_', '') } | Select-Object -Last 1
if ($cacheFile) {
    $recordSide = @{}
    foreach ($line in [IO.File]::ReadLines($cacheFile.FullName)) {
        if ($line -match '"id":(\d+),.*"faction":"(Alliance|Horde)"') { $recordSide[[int]$Matches[1]] = if ($Matches[2] -eq 'Alliance') { 1 } else { 2 } }
    }
    $confirmed = @($disagree | Where-Object { $recordSide[$_.Quest] -eq $_.Faction })
    if ($confirmed.Count) {
        Write-Output "Start items for the other side, but the quest's own record ($($cacheFile.Name)) gives the data's faction ($($confirmed.Count)): $(($confirmed | ForEach-Object { "$($_.Quest) $($_.Name)" }) -join '; ')"
        $disagree = @($disagree | Where-Object { $recordSide[$_.Quest] -ne $_.Faction })
    }
} else {
    Write-Output "No $($Game)_quest_cache_*.jsonl in $ToolsDir (step 2e or 10 reads the cache): the quests' own records aren't checked."
}
if ($disagree.Count) {
    Write-Output "Quests whose start items are for one side only and which the data gives another faction ($($disagree.Count)):"
    foreach ($d in $disagree) { Write-Output ("  {0} {1}: the data says {2}, its item {3} is {4} only" -f $d.Quest, $d.Name, $sideName[$d.Faction], $d.Items, $sideName[$d.ItemSide]) }
}

if (-not $WhatIf -and ($added.Count -or $gone.Count -or $changed.Count -or -not (Test-Path $file))) {
    Save-StartItemData $records $DataDir $AddonDir
} elseif ($WhatIf) {
    Write-Output 'WhatIf: nothing written.'
} else {
    Write-Output 'The data file already holds these items.'
}
if ($disagree.Count) { exit 1 }
exit 0
