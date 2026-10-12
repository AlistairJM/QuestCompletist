<#
Takes a quest off a pin when another pin with the same giver name, close by on the same map, has it
too. The addon draws pins within half a map point of each other as one, so there the quest was
listed twice in the tooltip; further apart, the same giver showed the quest on two pins.

For each quest on two or more pins with the same name, each within 3 map points of another:
  1. Where the game's own quest data (quest_locations.csv, from Build-QuestLocationData.ps1) has a
     start point for the quest on that map, it stays on the pin nearest each start point, when
     that's within 1.5 points, the pipeline's "same spot". A quest with a start point at each pin
     stays on each (Efee in Shadowmoon Valley).
  2. Otherwise, of pins within 0.5 points of each other (the addon draws them as one), it stays on
     one. Pins further apart than that keep it, and are listed: a character in a phased story
     often stands in two places, offering the quest in both (Captain Danuvin at Sentinel Hill), and
     nothing in the data says either is wrong.
Where pins tie, the quest stays on the one with the most quests, then one with an NPC ID, then the
first in the file. A pin left with no quests is removed. Pins with different names that offer the
same quest are different quest givers (class trainers), and keep it. The rule is in DuplicatePins.ps1.

Only data\pins.jsonl changes, then qcPinDB.lua is rebuilt. Running it again changes nothing.
  .\Remove-DuplicatePinQuests.ps1 -WhatIf     lists what would change
  .\Remove-DuplicatePinQuests.ps1 -Game forever -WhatIf     the same on data\forever\pins.jsonl, whose
        pins the importer writes; Forever has no equivalent of retail's start points in
        quest_locations.csv, so only the second rule applies, and it has no decisions file. The
        importer applies the same rule before it writes, so this finds nothing to take off there and
        only lists the quests left on pins further apart
#>
param(
    [string]$Game = 'retail',
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = '',
    [string]$AddonDir = '',
    [string]$DecisionsCsv = '',
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\DuplicatePins.ps1"
if ($Game -notin 'retail', 'forever') { throw "-Game must be retail or forever." }
$forever = $Game -eq 'forever'
if (-not $DataDir) { $DataDir = Join-Path $PSScriptRoot $(if ($forever) { '..\data\forever' } else { '..\data' }) }
if (-not $AddonDir) { $AddonDir = Join-Path $PSScriptRoot $(if ($forever) { '..\QuestCompletist\Forever' } else { '..\QuestCompletist' }) }
if (-not $DecisionsCsv -and -not $forever) { $DecisionsCsv = Join-Path $PSScriptRoot '..\docs\plans\pin-npc-id-decisions.csv' }

$startPoints = @{}
foreach ($row in $(if ($forever) { @() } else { Import-Csv "$ToolsDir\quest_locations.csv" })) {
    $key = "$($row.UiMapID)|$($row.QuestID)"
    if (-not $startPoints.ContainsKey($key)) { $startPoints[$key] = New-Object System.Collections.Generic.List[double[]] }
    $startPoints[$key].Add([double[]]@([double]$row.MapX, [double]$row.MapY))
}

$result = Remove-DuplicatePins @(Read-PinData $DataDir) $startPoints
$result.Changes
"$(if ($WhatIf) { 'Would take' } else { 'Took' }) $($result.TakenOff) quests off $($result.Changed) pins, removing $($result.Removed.Count) pins left with none"
if ($result.LeftAlone.Count) {
    "Left alone, as the pins are apart and the game has no start point to choose between them: $($result.LeftAlone.Count)"
    $result.LeftAlone
}

function Get-PlaceKey($map, $px, $py) {
    $format = '0.############################'
    return "$map|$(([decimal]$px).ToString($format, $script:Invariant))|$(([decimal]$py).ToString($format, $script:Invariant))"
}
if ($result.Removed.Count -and $DecisionsCsv -and (Test-Path $DecisionsCsv)) {
    $gone = @{}
    foreach ($pin in $result.Removed) { $gone[(Get-PlaceKey $pin.map $pin.x $pin.y)] = $true }
    $rows = @(Import-Csv $DecisionsCsv -Encoding UTF8 | Where-Object {
        $gone.ContainsKey((Get-PlaceKey $_.Map ([decimal]::Parse($_.X, $script:Invariant)) ([decimal]::Parse($_.Y, $script:Invariant))))
    })
    if ($rows.Count) {
        "Delete these rows from $(Split-Path -Leaf $DecisionsCsv), as their pins are gone (Apply-PinNpcIds.ps1 stops at a row with no pin):"
        $rows | ForEach-Object { "  $($_.Action) map $($_.Map) at $($_.X),$($_.Y): $($_.Name) [$($_.Id)]" }
    }
}

if (-not $WhatIf -and $result.Changed) { Save-PinData $result.Pins $DataDir $AddonDir }
