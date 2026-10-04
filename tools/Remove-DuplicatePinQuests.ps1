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
same quest are different quest givers (class trainers), and keep it.

Only data\pins.jsonl changes, then qcPinDB.lua is rebuilt. Running it again changes nothing.
  .\Remove-DuplicatePinQuests.ps1 -WhatIf     lists what would change
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$DecisionsCsv = (Join-Path $PSScriptRoot '..\docs\plans\pin-npc-id-decisions.csv'),
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

$groupDistance = 3.0
$sameSpot = 1.5
$drawnAsOne = 0.5

$pins = @(Read-PinData $DataDir)
$count = $pins.Count
$x = New-Object double[] $count
$y = New-Object double[] $count
for ($i = 0; $i -lt $count; $i++) { $x[$i] = [double]$pins[$i].x; $y[$i] = [double]$pins[$i].y }
function Get-Distance([int]$a, [int]$b) { $dx = $x[$a] - $x[$b]; $dy = $y[$a] - $y[$b]; return [math]::Sqrt($dx * $dx + $dy * $dy) }

$startPoints = @{}
foreach ($row in Import-Csv "$ToolsDir\quest_locations.csv") {
    $key = "$($row.UiMapID)|$($row.QuestID)"
    if (-not $startPoints.ContainsKey($key)) { $startPoints[$key] = New-Object System.Collections.Generic.List[double[]] }
    $startPoints[$key].Add([double[]]@([double]$row.MapX, [double]$row.MapY))
}

# Pins are kept as indexes: every [pscustomobject] hashes alike, so keying a hashtable by pin is slow.
$pinsOf = @{}
for ($i = 0; $i -lt $count; $i++) {
    if ($null -eq $pins[$i].name) { continue }
    foreach ($questId in $pins[$i].quests) {
        $key = "$($pins[$i].map)|$($pins[$i].name)|$questId"
        if (-not $pinsOf.ContainsKey($key)) { $pinsOf[$key] = New-Object System.Collections.Generic.List[int] }
        $pinsOf[$key].Add($i)
    }
}

function Get-Preferred([int[]]$candidates) {
    return $candidates | Sort-Object { -$pins[$_].quests.Count }, { if ($pins[$_].npc) { 0 } else { 1 } }, { $_ } | Select-Object -First 1
}
function Get-PinText([int]$i) {
    $pin = $pins[$i]
    return "$($pin.name)$(if ($pin.npc) { " [$($pin.npc)]" }) at $($pin.x), $($pin.y)"
}

$drop = @{}
$leftAlone = New-Object System.Collections.Generic.List[string]
foreach ($key in ($pinsOf.Keys | Sort-Object)) {
    $holders = $pinsOf[$key]
    if ($holders.Count -lt 2) { continue }
    $map, $name, $questId = $key -split '\|', 3

    $group = @{}
    foreach ($i in $holders) { $group[$i] = $i }
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($a in $holders) {
            foreach ($b in $holders) {
                if ($group[$a] -lt $group[$b] -and (Get-Distance $a $b) -le $groupDistance) { $group[$b] = $group[$a]; $changed = $true }
            }
        }
    }

    foreach ($members in ($holders | Group-Object { $group[$_] })) {
        $near = [int[]]@($members.Group)
        if ($near.Count -lt 2) { continue }
        $keep = New-Object System.Collections.Generic.List[int]
        foreach ($point in $startPoints["$map|$questId"]) {
            $best = [double]::MaxValue
            foreach ($i in $near) {
                $dx = $x[$i] - $point[0]; $dy = $y[$i] - $point[1]
                $best = [math]::Min($best, [math]::Sqrt($dx * $dx + $dy * $dy))
            }
            if ($best -gt $sameSpot) { continue }
            $nearest = Get-Preferred @($near | Where-Object { $dx = $x[$_] - $point[0]; $dy = $y[$_] - $point[1]; [math]::Sqrt($dx * $dx + $dy * $dy) -le $best + 1e-9 })
            if (-not $keep.Contains($nearest)) { $keep.Add($nearest) }
        }
        if ($keep.Count -eq 0) {
            $spots = New-Object System.Collections.Generic.List[object]
            foreach ($i in $near) {
                $spot = $null
                foreach ($s in $spots) { if ((Get-Distance $s[0] $i) -le $drawnAsOne) { $spot = $s; break } }
                if ($spot) { $spot.Add($i) } else { $spots.Add((New-Object System.Collections.Generic.List[int] (, [int[]]@($i)))) }
            }
            foreach ($s in $spots) { $keep.Add((Get-Preferred $s.ToArray())) }
            if ($spots.Count -gt 1) { $leftAlone.Add("  map ${map}: quest $questId on " + (($keep | ForEach-Object { Get-PinText $_ }) -join '; ')) }
        }
        foreach ($i in $near) {
            if ($keep.Contains($i)) { continue }
            if (-not $drop.ContainsKey($i)) { $drop[$i] = New-Object System.Collections.Generic.List[int] }
            $drop[$i].Add([int]$questId)
        }
    }
}

$kept = New-Object System.Collections.Generic.List[object]
$removedPins = New-Object System.Collections.Generic.List[int]
$takenOff = 0
for ($i = 0; $i -lt $count; $i++) {
    $pin = $pins[$i]
    if (-not $drop.ContainsKey($i)) { $kept.Add($pin); continue }
    $remaining = @($pin.quests | Where-Object { -not $drop[$i].Contains([int]$_) })
    $takenOff += $pin.quests.Count - $remaining.Count
    "map $($pin.map): $(Get-PinText $i) loses $($drop[$i] -join ', ')$(if (-not $remaining.Count) { ', and the pin goes' })"
    if ($remaining.Count -eq 0) {
        if ($null -ne $pin.note) { throw "Pin $(Get-PinText $i) on map $($pin.map) would go with its note: '$($pin.note)'" }
        $removedPins.Add($i)
        continue
    }
    Set-RecordField $pin 'quests' ([object[]]$remaining)
    $kept.Add($pin)
}

"$(if ($WhatIf) { 'Would take' } else { 'Took' }) $takenOff quests off $($drop.Count) pins, removing $($removedPins.Count) pins left with none"
if ($leftAlone.Count) {
    "Left alone, as the pins are apart and the game has no start point to choose between them: $($leftAlone.Count)"
    $leftAlone
}

function Get-PlaceKey($map, $px, $py) {
    $format = '0.############################'
    return "$map|$(([decimal]$px).ToString($format, $script:Invariant))|$(([decimal]$py).ToString($format, $script:Invariant))"
}
if ($removedPins.Count -and (Test-Path $DecisionsCsv)) {
    $gone = @{}
    foreach ($i in $removedPins) { $gone[(Get-PlaceKey $pins[$i].map $pins[$i].x $pins[$i].y)] = $true }
    $rows = @(Import-Csv $DecisionsCsv -Encoding UTF8 | Where-Object {
        $gone.ContainsKey((Get-PlaceKey $_.Map ([decimal]::Parse($_.X, $script:Invariant)) ([decimal]::Parse($_.Y, $script:Invariant))))
    })
    if ($rows.Count) {
        "Delete these rows from $(Split-Path -Leaf $DecisionsCsv), as their pins are gone (Apply-PinNpcIds.ps1 stops at a row with no pin):"
        $rows | ForEach-Object { "  $($_.Action) map $($_.Map) at $($_.X),$($_.Y): $($_.Name) [$($_.Id)]" }
    }
}

if (-not $WhatIf -and $drop.Count) { Save-PinData $kept $DataDir $AddonDir }
