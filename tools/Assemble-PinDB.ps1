<#
Final assembly: for each converted quest-giver location, choose who its pin names and its icon, group the
locations into pins, and write the result as tools\pins_candidate.jsonl for review, in the same form as
data\pins.jsonl. -Apply also saves it as data\pins.jsonl and rebuilds qcPinDB.lua.

The rules both games share are in PinRules.ps1: who a pin names is the first of the quest's existing pin
nearest the location (borrowed from ANY existing pin match, regardless of drift status - identity isn't
affected by map-ID reorganization), a TrinityCore starter whose spawn stands at the start, and a known
NPC within 1.5 map points that starts the quest; with none, nobody. A giver's locations within 1.5 map
points of each other on one map share a pin, and so do the locations that name nobody: one pin per spot,
whose icon comes from its quests when they bring different ones.

Retail carries over what its pins hold: an old (quest, NPC) pair the new data doesn't reproduce is kept
as it is, a rebuilt pin within 1.5 points of an existing one is put back at its spot, and a pin's note
stays with it there (see the position step below); notes that find no pin are listed.
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
. "$PSScriptRoot\PinRules.ps1"
$toolsDir = $ToolsDir

Write-Output "Loading the quests, for the default icon and a spot's icon..."
$questRecords = @{}
foreach ($quest in (Read-QuestData $DataDir)) { $questRecords[[string]$quest.id] = $quest }

Write-Output "Loading existing pin data (any match, not just position-verified) for identity borrowing..."
$existing = Import-Csv "$toolsDir\existing_pindb_by_quest.csv"
$existingByQuest = @{}
foreach ($e in $existing) {
    if (-not $existingByQuest.ContainsKey($e.QuestID)) { $existingByQuest[$e.QuestID] = New-Object System.Collections.Generic.List[object] }
    $existingByQuest[$e.QuestID].Add($e)
}

# A quest offered in several places has a pin in each; take identity from the one nearest this
# location on the same map, not whichever happens to come first.
function Get-NearestExistingPin($questId, $mapId, $x, $y) {
    $pins = $existingByQuest[$questId]
    $sameMap = @($pins | Where-Object { $_.OldUiMapID -eq $mapId })
    if (-not $sameMap.Count) { return $pins[0] }
    return $sameMap | Sort-Object { Get-PinDistance $x $y $_.OldMapX $_.OldMapY } | Select-Object -First 1
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

# A quest with no pin of its own to borrow from (placed from the client's points or TrinityCore's) takes a
# neighbour's identity only when that NPC starts it: the NPC next to a start is often not its giver.
function Test-StartsQuest($row, $pin) {
    if (@($row.StarterNpcIds -split '[|]' | Where-Object { $_ }) -contains [string]$pin.NpcId) { return $true }
    return [bool]$pin.NpcName -and (@($row.StarterNames -split '[|]' | Where-Object { $_ }) -contains $pin.NpcName)
}
# The nearest known NPC on the location's map, within one spot, that starts the quest.
function Find-NeighbourStarter($loc) {
    if (-not $distinctPinsByMap.ContainsKey($loc.UiMapID)) { return $null }
    $best = $null; $bestDist = [double]::MaxValue
    foreach ($candidate in $distinctPinsByMap[$loc.UiMapID]) {
        if (-not (Test-StartsQuest $loc $candidate)) { continue }
        $dist = Get-PinDistance $loc.MapX $loc.MapY $candidate.OldMapX $candidate.OldMapY
        if ($dist -lt $bestDist) { $bestDist = $dist; $best = $candidate }
    }
    if ($best -and $bestDist -le $PinSameSpot) { return $best }
    return $null
}

Write-Output "Loading converted quest-giver locations..."
$locations = Import-Csv "$toolsDir\quest_locations.csv"

Write-Output "Choosing who each location's pin names, in PinRules.ps1's order (its existing pin, a starter's spawn at the start, a known NPC within $PinSameSpot map points that starts it)..."
$enriched = New-Object System.Collections.Generic.List[object]
foreach ($loc in $locations) {
    $carried = if ($existingByQuest.ContainsKey($loc.QuestID)) { Get-NearestExistingPin $loc.QuestID $loc.UiMapID $loc.MapX $loc.MapY }
    $starter = if ($loc.GiverNpcId) { [PSCustomObject]@{ NpcId = $loc.GiverNpcId; NpcName = $loc.GiverName } }
    $identity = Select-PinIdentity ([ordered]@{ pin = $carried; emulator = $starter; neighbour = { Find-NeighbourStarter $loc } })
    $npcId = "0"; $npcName = ""; $iconType = "1"
    if ($identity.Value) { $npcId = $identity.Value.NpcId; $npcName = $identity.Value.NpcName }
    if ($identity.Source -eq 'pin') { $iconType = $carried.IconType }
    elseif ($identity.Source -ne 'emulator' -and $questRecords.ContainsKey($loc.QuestID) -and $questRecords[$loc.QuestID].profession) { $iconType = "3" }
    $enriched.Add([PSCustomObject]@{
        QuestID = $loc.QuestID; UiMapID = $loc.UiMapID; MapX = $loc.MapX; MapY = $loc.MapY
        NpcId = $npcId; NpcName = $npcName; IconType = $iconType
        IdentitySource = $identity.Source
        Source = $loc.Source; StarterNpcIds = $loc.StarterNpcIds; StarterNames = $loc.StarterNames
    })
}
Write-Output "Resolved via proximity match: $(@($enriched | Where-Object { $_.IdentitySource -eq 'neighbour' }).Count)"

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

Write-Output "Grouping into pins by PinRules.ps1: a giver's locations (by NPC ID, else by name) within $PinSameSpot map points"
Write-Output "on one map share a pin, and so do the locations that name nobody, one pin per spot..."
# A known NPC's quests share a pin only where they start close together. Story NPCs stand in
# several places on one map (Thalyssra across Suramar), and grouping by map + NPC alone put every
# one of their quests on a single pin, up to 90 map points from where the quest starts. 3 points
# until October 2026: a quest with a start point in the client's data now keeps it rather than
# joining its giver's pin up to 3 points away (docs/plans/quest-location-data-pipeline.md).
$pinGroups = New-Object System.Collections.Generic.List[object]
$groupIndex = New-PinGroups
foreach ($row in $enriched) {
    $giver = Get-PinGiverKey $row.NpcId $row.NpcName
    $group = Find-PinGroup $groupIndex $row.UiMapID $giver $row.MapX $row.MapY
    if (-not $group) {
        $group = Add-PinGroup $groupIndex $row.UiMapID $giver $row.MapX $row.MapY ([PSCustomObject]@{
            UiMapID = $row.UiMapID; Giver = $giver; NpcId = $row.NpcId; NpcName = $row.NpcName
            IconType = $row.IconType; MapX = $row.MapX; MapY = $row.MapY
            QuestIDs = New-Object System.Collections.Generic.List[string]
            Note = $null
            IconFromPin = $false
            Icons = New-Object System.Collections.Generic.HashSet[string]
        })
        $pinGroups.Add($group)
    }
    # A quest new to the pins comes with a default icon, which must not replace the icon of the pin it joins.
    if (-not $group.IconFromPin -and ($row.IdentitySource -eq 'pin' -or $row.IdentitySource -eq 'kept-old-unreplaced')) {
        $group.IconType = $row.IconType
        $group.IconFromPin = $true
    }
    [void]$group.Icons.Add([string]$row.IconType)
    if ($row.Note -and -not $group.Note) { $group.Note = $row.Note }
    if (-not $group.QuestIDs.Contains($row.QuestID)) {
        $group.QuestIDs.Add($row.QuestID)
    }
}

Write-Output "Total pins after grouping: $($pinGroups.Count) (from $($enriched.Count) quest-giver locations)"

# Positions are recomputed from the client's data on every run. Where the live qcPinDB.lua already
# has a pin for the same NPC (or, with no NPC, for one of the same quests) within 1.5 map points,
# reuse its exact coordinates, so a rerun doesn't nudge pins that haven't really moved.
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
foreach ($g in $pinGroups) {
    $lookup = if ($g.NpcId -ne "0") { @("$($g.UiMapID)|npc-$($g.NpcId)") } else { @($g.QuestIDs | ForEach-Object { "$($g.UiMapID)|quest-$_" }) }
    $best = $null; $bestDist = [double]::MaxValue
    foreach ($k in $lookup) {
        if (-not $livePositions.ContainsKey($k)) { continue }
        foreach ($p in $livePositions[$k]) {
            $d = Get-PinDistance $g.MapX $g.MapY $p.OldMapX $p.OldMapY
            if ($d -le $PinSameSpot -and $d -lt $bestDist) { $best = $p; $bestDist = $d }
        }
    }
    if ($best -and ($g.MapX -ne $best.OldMapX -or $g.MapY -ne $best.OldMapY)) {
        $g.MapX = $best.OldMapX; $g.MapY = $best.OldMapY
        $keptPositions++
    }
    if ($best -and $best.Note -and -not $g.Note) { $g.Note = $best.Note }
}
Write-Output "Pins snapped back to an existing position within $PinSameSpot points: $keptPositions"

# Two groups of one giver, or two that name nobody, can snap onto the same existing coordinates: they are one pin.
$mergedGroups = 0
$groupAtPlace = @{}
$placed = New-Object System.Collections.Generic.List[object]
foreach ($g in $pinGroups) {
    $place = "$($g.UiMapID)|$($g.Giver)|$([decimal]::Parse([string]$g.MapX, $script:Invariant))|$([decimal]::Parse([string]$g.MapY, $script:Invariant))"
    if (-not $groupAtPlace.ContainsKey($place)) { $groupAtPlace[$place] = $g; $placed.Add($g); continue }
    $base = $groupAtPlace[$place]
    foreach ($questId in $g.QuestIDs) { if (-not $base.QuestIDs.Contains($questId)) { $base.QuestIDs.Add($questId) } }
    foreach ($icon in $g.Icons) { [void]$base.Icons.Add($icon) }
    if ($g.Note -and -not $base.Note) { $base.Note = $g.Note }
    $mergedGroups++
}
$pinGroups = $placed
Write-Output "Groups of one giver, or of nobody, that landed on the same spot and became one pin: $mergedGroups"

# A pin that names nobody holds whatever starts at its spot; when its quests bring different icons, its quests choose.
$iconsFromQuests = 0
foreach ($g in $pinGroups) {
    if ($g.Giver -or $g.Icons.Count -lt 2) { continue }
    $g.IconType = [string](Get-PinQuestIcon @($g.QuestIDs | ForEach-Object { $questRecords[$_] }))
    $iconsFromQuests++
}
Write-Output "Pins that name nobody whose quests brought different icons, which take theirs from the quests: $iconsFromQuests"

$keptNotes = @{}
foreach ($g in $pinGroups) { if ($g.Note) { $keptNotes[$g.Note] = $true } }
$lostNotes = @($existing | Where-Object { $_.Note -and -not $keptNotes.ContainsKey($_.Note) } |
    ForEach-Object { "  map $($_.OldUiMapID) at $($_.OldMapX),$($_.OldMapY): $($_.Note)" } | Select-Object -Unique)
Write-Output "Pin notes that found no pin: $($lostNotes.Count)"
$lostNotes

Write-Output "Writing the pins, map by map..."
$byMap = @{}
foreach ($g in $pinGroups) {
    if (-not $byMap.ContainsKey($g.UiMapID)) { $byMap[$g.UiMapID] = New-Object System.Collections.Generic.List[object] }
    $byMap[$g.UiMapID].Add($g)
}

$pins = New-Object System.Collections.Generic.List[object]
foreach ($mapId in ($byMap.Keys | Sort-Object { [int]$_ })) {
    # Hashtable order changes between runs; a fixed order keeps an unchanged rerun byte-identical.
    $ordered = $byMap[$mapId] | Sort-Object { ($_.QuestIDs | ForEach-Object { [int]$_ } | Measure-Object -Minimum).Minimum }, { [double]$_.MapX }, { [double]$_.MapY }, { [int]$_.NpcId }
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

$borrowedCount = ($enriched | Where-Object { $_.IdentitySource -eq "pin" }).Count
$proximityCount = ($enriched | Where-Object { $_.IdentitySource -eq "neighbour" }).Count
$giverSpawnCount = ($enriched | Where-Object { $_.IdentitySource -eq "emulator" }).Count
$inferredCount = ($enriched | Where-Object { $_.IdentitySource -eq "none" }).Count
Write-Output "Identity borrowed from existing data (exact quest match): $borrowedCount"
Write-Output "Identity from a starter's spawn at the start point: $giverSpawnCount"
Write-Output "Identity resolved via proximity match (same map, nearby known NPC): $proximityCount"
Write-Output "Identity still unknown (no prior pin, nothing nearby): $inferredCount"

$enriched | Export-Csv -Path "$toolsDir\quest_locations_enriched.csv" -NoTypeInformation -Encoding utf8
