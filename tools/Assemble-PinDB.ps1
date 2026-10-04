<#
Final assembly: for each converted quest-giver location, attach NPC identity +
icon type (borrowed from ANY existing pin match, regardless of drift status -
identity isn't affected by map-ID reorganization), group quests an NPC offers
from the same spot (within 3 map points) into one pin, and write the result as
tools\pins_candidate.jsonl for review, in the same form as data\pins.jsonl.
-Apply also saves it as data\pins.jsonl and rebuilds qcPinDB.lua.

A pin's note stays with it when the rebuilt pin is put back at the existing pin's
spot (see the position step below); notes that find no pin are listed.
#>

param(
    # Also save the result as the pins. Without it only the candidate is written.
    [switch]$Apply,
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist')
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"
$toolsDir = $ToolsDir

Write-Output "Loading the profession flag per quest for the default-icon fallback rule..."
$questProfession = @{}
foreach ($quest in (Read-QuestData $DataDir)) {
    $questProfession[[string]$quest.id] = if ($quest.profession) { [int]$quest.profession } else { 0 }
}

Write-Output "Loading existing pin data (any match, not just position-verified) for identity borrowing..."
$existing = Import-Csv "$toolsDir\existing_pindb_by_quest.csv"
$existingByQuest = @{}
foreach ($e in $existing) {
    if (-not $existingByQuest.ContainsKey($e.QuestID)) { $existingByQuest[$e.QuestID] = New-Object System.Collections.Generic.List[object] }
    $existingByQuest[$e.QuestID].Add($e)
}

function Get-MapDistance($ax, $ay, $bx, $by) {
    $dx = [double]$ax - [double]$bx; $dy = [double]$ay - [double]$by
    return [math]::Sqrt($dx * $dx + $dy * $dy)
}

# A quest offered in several places has a pin in each; take identity from the one nearest this
# location on the same map, not whichever happens to come first.
function Get-NearestExistingPin($questId, $mapId, $x, $y) {
    $pins = $existingByQuest[$questId]
    $sameMap = @($pins | Where-Object { $_.OldUiMapID -eq $mapId })
    if (-not $sameMap.Count) { return $pins[0] }
    return $sameMap | Sort-Object { Get-MapDistance $x $y $_.OldMapX $_.OldMapY } | Select-Object -First 1
}

Write-Output "Loading converted quest-giver locations..."
$locations = Import-Csv "$toolsDir\quest_locations.csv"

# Attach identity/icon to every location row
$enriched = New-Object System.Collections.Generic.List[object]
foreach ($loc in $locations) {
    $npcId = "0"; $npcName = ""; $iconType = "1"; $identitySource = "inferred-default"
    if ($existingByQuest.ContainsKey($loc.QuestID)) {
        $old = Get-NearestExistingPin $loc.QuestID $loc.UiMapID $loc.MapX $loc.MapY
        $npcId = $old.NpcId
        $npcName = $old.NpcName
        $iconType = $old.IconType
        $identitySource = "borrowed"
    } elseif ($questProfession.ContainsKey($loc.QuestID) -and $questProfession[$loc.QuestID] -ne 0) {
        $iconType = "3"
    }
    $enriched.Add([PSCustomObject]@{
        QuestID = $loc.QuestID; UiMapID = $loc.UiMapID; MapX = $loc.MapX; MapY = $loc.MapY
        NpcId = $npcId; NpcName = $npcName; IconType = $iconType
        IdentitySource = $identitySource
    })
}

Write-Output "Building distinct existing-pin index by map, for proximity matching..."
# Dedupe existing (quest,pin) associations down to distinct physical pins (NpcId+name+position),
# grouped by UiMapID, so we can look up "what NPC is standing near here" independent of quest ID.
$distinctPinsByMap = @{}
$seenPinKeys = New-Object System.Collections.Generic.HashSet[string]
foreach ($e in $existing) {
    if ($e.NpcId -eq "0") { continue }
    $pinKey = "$($e.OldUiMapID)|$($e.NpcId)|$($e.OldMapX)|$($e.OldMapY)"
    if ($seenPinKeys.Contains($pinKey)) { continue }
    [void]$seenPinKeys.Add($pinKey)
    if (-not $distinctPinsByMap.ContainsKey($e.OldUiMapID)) { $distinctPinsByMap[$e.OldUiMapID] = New-Object System.Collections.Generic.List[object] }
    $distinctPinsByMap[$e.OldUiMapID].Add($e)
}
$totalDistinctPins = 0
foreach ($v in $distinctPinsByMap.Values) { $totalDistinctPins += $v.Count }
Write-Output "Distinct known-NPC pins available for proximity matching: $totalDistinctPins"

Write-Output "Proximity-matching quests with no identity yet (within 1.5 map points, same UiMapID)..."
$proximityThreshold = 1.5
$proximityMatched = 0
foreach ($row in $enriched) {
    if ($row.IdentitySource -ne "inferred-default") { continue }
    if (-not $distinctPinsByMap.ContainsKey($row.UiMapID)) { continue }

    $bestDist = [double]::MaxValue
    $best = $null
    $rowX = [double]$row.MapX
    $rowY = [double]$row.MapY
    foreach ($candidate in $distinctPinsByMap[$row.UiMapID]) {
        $dx = $rowX - [double]$candidate.OldMapX
        $dy = $rowY - [double]$candidate.OldMapY
        $dist = [math]::Sqrt($dx * $dx + $dy * $dy)
        if ($dist -lt $bestDist) { $bestDist = $dist; $best = $candidate }
    }

    if ($best -and $bestDist -le $proximityThreshold) {
        $row.NpcId = $best.NpcId
        $row.NpcName = $best.NpcName
        $row.IdentitySource = "proximity-matched"
        $proximityMatched++
    }
}
Write-Output "Resolved via proximity match: $proximityMatched"

Write-Output "Building merge safety net: finding old (quest, NPC) pairs the new pipeline never reproduced..."
# Coverage key for a quest+NPC pairing. For old entries with a known NPC, covered means the
# new pipeline has SOME row for that exact quest with that exact NPC. For old entries with no
# NPC (id=0, e.g. special-case pins), covered means the new pipeline has ANY row for that quest
# at all, since we have no NPC to match precisely and trust the new data once it exists.
$coveredExactPairs = New-Object System.Collections.Generic.HashSet[string]
$coveredQuestIds = New-Object System.Collections.Generic.HashSet[string]
foreach ($row in $enriched) {
    [void]$coveredQuestIds.Add($row.QuestID)
    if ($row.NpcId -ne "0") {
        [void]$coveredExactPairs.Add("$($row.QuestID)|$($row.NpcId)")
    }
}

$keptOld = New-Object System.Collections.Generic.List[object]
foreach ($e in $existing) {
    $isCovered = if ($e.NpcId -ne "0") {
        $coveredExactPairs.Contains("$($e.QuestID)|$($e.NpcId)")
    } else {
        $coveredQuestIds.Contains($e.QuestID)
    }
    if (-not $isCovered) {
        $keptOld.Add([PSCustomObject]@{
            QuestID = $e.QuestID; UiMapID = $e.OldUiMapID; MapX = $e.OldMapX; MapY = $e.OldMapY
            NpcId = $e.NpcId; NpcName = $e.NpcName; IconType = $e.IconType
            IdentitySource = "kept-old-unreplaced"; Note = $e.Note
        })
    }
}
Write-Output "Old (quest, NPC) pairs preserved as-is (no replacement data exists): $($keptOld.Count)"

# Fold the preserved old entries into the same list so they go through identical grouping/emission
foreach ($k in $keptOld) { $enriched.Add($k) }
Write-Output "Total quest-giver location rows after merge: $($enriched.Count)"

Write-Output "Grouping into pins (same UiMapID + NPC ID share one pin when NPC ID is known and nonzero;"
Write-Output "unknown-NPC (id=0) pins with the same name within 1.5 map points on the same map are merged too -"
Write-Output "otherwise the same physical NPC ends up as many fully-overlapping pins, which breaks rendering"
Write-Output "when enough of them stack on the same spot)..."
$proximityMergeThreshold = 1.5
# A known NPC's quests share a pin only where they start close together. Story NPCs stand in
# several places on one map (Thalyssra across Suramar), and grouping by map + NPC alone put every
# one of their quests on a single pin, up to 90 map points from where the quest starts.
$npcGroupThreshold = 3.0
$pinGroups = @{}
$namedGroupKeysByMapAndName = @{}   # "$UiMapID|$Name" -> List[pinGroups key], for proximity lookup
$npcGroupKeys = @{}                 # "$UiMapID|npc-$NpcId" -> List[pinGroups key]
$questGroupKeys = @{}               # "$UiMapID|quest-$QuestID" -> List[pinGroups key]

# With no NPC to group by, one quest's starting points share a pin only when they're within 1.5
# map points; further apart they get a pin each, rather than collapsing onto the first.
function Get-QuestGroupKey($row) {
    $base = "$($row.UiMapID)|quest-$($row.QuestID)"
    if (-not $questGroupKeys.ContainsKey($base)) { $questGroupKeys[$base] = New-Object System.Collections.Generic.List[string] }
    foreach ($candidateKey in $questGroupKeys[$base]) {
        $c = $pinGroups[$candidateKey]
        if ((Get-MapDistance $row.MapX $row.MapY $c.MapX $c.MapY) -le $proximityMergeThreshold) { return $candidateKey }
    }
    $newKey = "$base|$($questGroupKeys[$base].Count)"
    $questGroupKeys[$base].Add($newKey)
    return $newKey
}

foreach ($row in $enriched) {
    $key = $null
    if ($row.NpcId -ne "0") {
        $npcKey = "$($row.UiMapID)|npc-$($row.NpcId)"
        if (-not $npcGroupKeys.ContainsKey($npcKey)) { $npcGroupKeys[$npcKey] = New-Object System.Collections.Generic.List[string] }
        $bestDist = [double]::MaxValue
        foreach ($candidateKey in $npcGroupKeys[$npcKey]) {
            $c = $pinGroups[$candidateKey]
            $dist = Get-MapDistance $row.MapX $row.MapY $c.MapX $c.MapY
            if ($dist -le $npcGroupThreshold -and $dist -lt $bestDist) { $key = $candidateKey; $bestDist = $dist }
        }
        if (-not $key) {
            $key = "$npcKey|$($npcGroupKeys[$npcKey].Count)"
            $npcGroupKeys[$npcKey].Add($key)
        }
    } elseif ($row.NpcName) {
        $nameLookupKey = "$($row.UiMapID)|$($row.NpcName)"
        $rowX = [double]$row.MapX; $rowY = [double]$row.MapY
        if ($namedGroupKeysByMapAndName.ContainsKey($nameLookupKey)) {
            $bestKey = $null; $bestDist = [double]::MaxValue
            foreach ($candidateKey in $namedGroupKeysByMapAndName[$nameLookupKey]) {
                $c = $pinGroups[$candidateKey]
                $dx = $rowX - [double]$c.MapX; $dy = $rowY - [double]$c.MapY
                $dist = [math]::Sqrt($dx*$dx + $dy*$dy)
                if ($dist -le $proximityMergeThreshold -and $dist -lt $bestDist) { $bestKey = $candidateKey; $bestDist = $dist }
            }
            if ($bestKey) { $key = $bestKey }
        }
        if (-not $key) {
            $key = Get-QuestGroupKey $row
            if (-not $namedGroupKeysByMapAndName.ContainsKey($nameLookupKey)) {
                $namedGroupKeysByMapAndName[$nameLookupKey] = New-Object System.Collections.Generic.List[string]
            }
            if (-not $namedGroupKeysByMapAndName[$nameLookupKey].Contains($key)) { $namedGroupKeysByMapAndName[$nameLookupKey].Add($key) }
        }
    } else {
        $key = Get-QuestGroupKey $row
    }
    if (-not $pinGroups.ContainsKey($key)) {
        $pinGroups[$key] = [PSCustomObject]@{
            UiMapID = $row.UiMapID; NpcId = $row.NpcId; NpcName = $row.NpcName
            IconType = $row.IconType; MapX = $row.MapX; MapY = $row.MapY
            QuestIDs = New-Object System.Collections.Generic.List[string]
            Note = $null
        }
    }
    if ($row.Note -and -not $pinGroups[$key].Note) { $pinGroups[$key].Note = $row.Note }
    if (-not $pinGroups[$key].QuestIDs.Contains($row.QuestID)) {
        $pinGroups[$key].QuestIDs.Add($row.QuestID)
    }
}

Write-Output "Total pins after grouping: $($pinGroups.Count) (from $($enriched.Count) quest-giver locations)"

# Positions are recomputed from the client's data on every run. Where the live qcPinDB.lua already
# has a pin for the same NPC (or, with no NPC, for one of the same quests) within 1.5 map points,
# reuse its exact coordinates, so a rerun doesn't nudge pins that haven't really moved.
$stableThreshold = 1.5
$livePositions = @{}
foreach ($e in $existing) {
    $keys = @("$($e.OldUiMapID)|quest-$($e.QuestID)")
    if ($e.NpcId -ne "0") { $keys += "$($e.OldUiMapID)|npc-$($e.NpcId)" }
    foreach ($k in $keys) {
        if (-not $livePositions.ContainsKey($k)) { $livePositions[$k] = New-Object System.Collections.Generic.List[object] }
        $livePositions[$k].Add($e)
    }
}
$keptPositions = 0
foreach ($g in $pinGroups.Values) {
    $lookup = if ($g.NpcId -ne "0") { @("$($g.UiMapID)|npc-$($g.NpcId)") } else { @($g.QuestIDs | ForEach-Object { "$($g.UiMapID)|quest-$_" }) }
    $best = $null; $bestDist = [double]::MaxValue
    foreach ($k in $lookup) {
        if (-not $livePositions.ContainsKey($k)) { continue }
        foreach ($p in $livePositions[$k]) {
            $d = Get-MapDistance $g.MapX $g.MapY $p.OldMapX $p.OldMapY
            if ($d -le $stableThreshold -and $d -lt $bestDist) { $best = $p; $bestDist = $d }
        }
    }
    if ($best -and ($g.MapX -ne $best.OldMapX -or $g.MapY -ne $best.OldMapY)) {
        $g.MapX = $best.OldMapX; $g.MapY = $best.OldMapY
        $keptPositions++
    }
    if ($best -and $best.Note -and -not $g.Note) { $g.Note = $best.Note }
}
Write-Output "Pins snapped back to an existing position within $stableThreshold points: $keptPositions"

$keptNotes = @{}
foreach ($g in $pinGroups.Values) { if ($g.Note) { $keptNotes[$g.Note] = $true } }
$lostNotes = @($existing | Where-Object { $_.Note -and -not $keptNotes.ContainsKey($_.Note) } |
    ForEach-Object { "  map $($_.OldUiMapID) at $($_.OldMapX),$($_.OldMapY): $($_.Note)" } | Select-Object -Unique)
Write-Output "Pin notes that found no pin: $($lostNotes.Count)"
$lostNotes

Write-Output "Writing the pins, map by map..."
$byMap = @{}
foreach ($g in $pinGroups.Values) {
    if (-not $byMap.ContainsKey($g.UiMapID)) { $byMap[$g.UiMapID] = New-Object System.Collections.Generic.List[object] }
    $byMap[$g.UiMapID].Add($g)
}

$pins = New-Object System.Collections.Generic.List[object]
foreach ($mapId in ($byMap.Keys | Sort-Object { [int]$_ })) {
    # Hashtable order changes between runs; a fixed order keeps an unchanged rerun byte-identical.
    $ordered = $byMap[$mapId] | Sort-Object { ($_.QuestIDs | ForEach-Object { [int]$_ } | Measure-Object -Minimum).Minimum }, { [double]$_.MapX }, { [double]$_.MapY }
    foreach ($group in $ordered) {
        $pins.Add([pscustomobject][ordered]@{
            map = [int]$mapId
            icon = [int]$group.IconType
            npc = [int]$group.NpcId
            name = if ($group.NpcName) { $group.NpcName } else { $null }
            x = [decimal]::Parse([string]$group.MapX, $script:Invariant)
            y = [decimal]::Parse([string]$group.MapY, $script:Invariant)
            quests = [int[]]@($group.QuestIDs | ForEach-Object { [int]$_ })
            note = $group.Note
        })
    }
}

$outFile = "$toolsDir\pins_candidate.jsonl"
[System.IO.File]::WriteAllText($outFile, (ConvertTo-PinJsonLines $pins), $script:Utf8)
Write-Output "Written candidate file to $outFile"

if ($Apply) {
    Save-PinData $pins $DataDir $AddonDir
    Write-Output "Applied to the pins."
}

$borrowedCount = ($enriched | Where-Object { $_.IdentitySource -eq "borrowed" }).Count
$proximityCount = ($enriched | Where-Object { $_.IdentitySource -eq "proximity-matched" }).Count
$inferredCount = ($enriched | Where-Object { $_.IdentitySource -eq "inferred-default" }).Count
Write-Output "Identity borrowed from existing data (exact quest match): $borrowedCount"
Write-Output "Identity resolved via proximity match (same map, nearby known NPC): $proximityCount"
Write-Output "Identity still unknown (no prior pin, nothing nearby): $inferredCount"

$enriched | Export-Csv -Path "$toolsDir\quest_locations_enriched.csv" -NoTypeInformation -Encoding utf8
