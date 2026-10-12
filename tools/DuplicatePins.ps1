# Dot-sourced by Remove-DuplicatePinQuests.ps1 and Import-ForeverData.ps1: takes a quest off a pin when another pin
# with the same giver name, close by on the same map, has it too (the rule Remove-DuplicatePinQuests.ps1 describes).
# -StartPoints holds the game's start points by "map|quest", each an array of x and y; Forever has none.
# Returns the pins kept, in their order, and what changed: Changes (a line per pin that loses a quest), TakenOff,
# Changed (the pins that lose one), Removed (those left with none, which go) and LeftAlone (a line per quest that
# stays on pins of one name further apart than the addon draws as one).

function Remove-DuplicatePins($pins, [hashtable]$StartPoints = @{}) {
    $groupDistance = 3.0
    $sameSpot = 1.5
    $drawnAsOne = 0.5

    $pins = @($pins)
    $count = $pins.Count
    $x = New-Object double[] $count
    $y = New-Object double[] $count
    for ($i = 0; $i -lt $count; $i++) { $x[$i] = [double]$pins[$i].x; $y[$i] = [double]$pins[$i].y }
    function Get-Distance([int]$a, [int]$b) { $dx = $x[$a] - $x[$b]; $dy = $y[$a] - $y[$b]; return [math]::Sqrt($dx * $dx + $dy * $dy) }

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
            foreach ($point in $StartPoints["$map|$questId"]) {
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
                    if ($null -ne $spot) { $spot.Add($i) } else { $spots.Add((New-Object System.Collections.Generic.List[int] (, [int[]]@($i)))) }
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
    $removed = New-Object System.Collections.Generic.List[object]
    $changes = New-Object System.Collections.Generic.List[string]
    $takenOff = 0
    for ($i = 0; $i -lt $count; $i++) {
        $pin = $pins[$i]
        if (-not $drop.ContainsKey($i)) { $kept.Add($pin); continue }
        $remaining = @($pin.quests | Where-Object { -not $drop[$i].Contains([int]$_) })
        $takenOff += $pin.quests.Count - $remaining.Count
        $changes.Add("map $($pin.map): $(Get-PinText $i) loses $($drop[$i] -join ', ')$(if (-not $remaining.Count) { ', and the pin goes' })")
        if ($remaining.Count -eq 0) {
            if ($null -ne $pin.note) { throw "Pin $(Get-PinText $i) on map $($pin.map) would go with its note: '$($pin.note)'" }
            $removed.Add($pin)
            continue
        }
        Set-RecordField $pin 'quests' ([object[]]$remaining)
        $kept.Add($pin)
    }
    return [pscustomobject]@{ Pins = $kept.ToArray(); Changes = $changes.ToArray(); TakenOff = $takenOff; Changed = $drop.Count
        Removed = $removed.ToArray(); LeftAlone = $leftAlone.ToArray() }
}
