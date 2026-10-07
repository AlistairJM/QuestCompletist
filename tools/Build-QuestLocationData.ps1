<#
Phase 1 pipeline: join wago.tools QuestPOIBlob + QuestPOIPoint + UiMapAssignment
into per-quest, per-map converted (mapX%, mapY%) positions for quest-giver pins,
then cross-reference against this addon's own quests (data\quests.jsonl).

Inputs (expected already downloaded into tools/):
  QuestPOIBlob.csv, QuestPOIPoint.csv, UiMapAssignment.csv

Output:
  tools/quest_locations.csv - QuestID, UiMapID, MapX, MapY, NumPointsUsed, InOurDB, OurZoneName
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data')
)
. "$PSScriptRoot\AddonData.ps1"
$toolsDir = $ToolsDir

Write-Output "Loading source tables..."
$blobs = Import-Csv "$toolsDir\QuestPOIBlob.csv"
$points = Import-Csv "$toolsDir\QuestPOIPoint.csv"
$regions = Import-Csv "$toolsDir\UiMapAssignment.csv"
$parentMap = @{}
foreach ($m in (Import-Csv "$toolsDir\UiMap.csv")) { $parentMap[$m.ID] = $m.ParentUiMapID }

# Index points by QuestPOIBlobID for fast lookup
Write-Output "Indexing points by blob ID..."
$pointsByBlob = @{}
foreach ($p in $points) {
    $key = $p.QuestPOIBlobID
    if (-not $pointsByBlob.ContainsKey($key)) { $pointsByBlob[$key] = @() }
    $pointsByBlob[$key] += $p
}

# Index regions by UiMapID (may have multiple candidate boxes per map)
Write-Output "Indexing regions by UiMapID..."
$regionsByMap = @{}
foreach ($r in $regions) {
    $key = $r.UiMapID
    if (-not $regionsByMap.ContainsKey($key)) { $regionsByMap[$key] = @() }
    $regionsByMap[$key] += $r
}

# Convert one world (x,y) into a map percentage using a specific region row.
# Formula verified in Phase 0 against two real in-game landmark readings. A region can cover only
# part of its map (UiMin..UiMax), as each zone does on a continent map.
function Convert-WorldToMapPercent($worldX, $worldY, $region) {
    $r0 = [double]$region.Region_0
    $r1 = [double]$region.Region_1
    $r3 = [double]$region.Region_3
    $r4 = [double]$region.Region_4
    $fx = ($r4 - $worldY) / ($r4 - $r1)
    $fy = ($r3 - $worldX) / ($r3 - $r0)
    $uMin0 = [double]$region.UiMin_0; $uMin1 = [double]$region.UiMin_1
    $uMax0 = [double]$region.UiMax_0; $uMax1 = [double]$region.UiMax_1
    return @{ X = $uMin0 + $fx * ($uMax0 - $uMin0); Y = $uMin1 + $fy * ($uMax1 - $uMin1) }
}

# The region that contains the point, preferring one on the location's own instance (a phased copy
# of a zone has its own instance but shares the zone's coordinates). $null when none does: the point
# isn't on this map, and a pin placed from it would sit off the map's edge.
function Get-BestConversion($worldX, $worldY, $instanceId, $candidateRegions) {
    $fallback = $null
    foreach ($region in $candidateRegions) {
        $inside = $worldX -ge [double]$region.Region_0 -and $worldX -le [double]$region.Region_3 -and
                  $worldY -ge [double]$region.Region_1 -and $worldY -le [double]$region.Region_4
        if (-not $inside) { continue }
        if ($region.MapID -eq $instanceId) { return Convert-WorldToMapPercent $worldX $worldY $region }
        if (-not $fallback) { $fallback = $region }
    }
    if ($fallback) { return Convert-WorldToMapPercent $worldX $worldY $fallback }
    return $null
}

Write-Output "Loading our own quest IDs and zone names..."
$ourQuests = @{}
foreach ($quest in (Read-QuestData $DataDir)) {
    $ourQuests[[string]$quest.id] = @{ Name = $quest.name; Zone = $quest.zone }
}
Write-Output "Our quest data has $($ourQuests.Count) quests."

Write-Output "Processing quest blobs (ObjectiveIndex 32, the start, and -1, the quest's own point)..."
$results = New-Object System.Collections.Generic.List[object]
$skippedNoPoint = 0
$skippedNoRegion = 0
$skippedOffMap = 0

function Convert-Blob($blob) {
    if (-not $pointsByBlob.ContainsKey($blob.ID)) { $script:skippedNoPoint++; return $null }
    if (-not $regionsByMap.ContainsKey($blob.UiMapID)) { $script:skippedNoRegion++; return $null }
    $pt = $pointsByBlob[$blob.ID][0]  # take first point; >99.8% of giver blobs have exactly one anyway
    $conv = Get-BestConversion -worldX ([double]$pt.X) -worldY ([double]$pt.Y) -instanceId $blob.MapID -candidateRegions $regionsByMap[$blob.UiMapID]
    if (-not $conv) { $script:skippedOffMap++; return $null }
    return @{ Blob = $blob; X = [math]::Round($conv.X * 100, 2); Y = [math]::Round($conv.Y * 100, 2) }
}

# A quest's point -1 is where it starts and ends when that is one place, and the turn-in otherwise
# (docs\plans\quest-location-data-pipeline.md, "October 2026, the pin review"); its point 32 is
# where it starts. A quest the client gives a point -1 is placed at its points 32 when it has any,
# else at its point -1. A quest with a point 32 and no point -1 gets no location, as before.
$startConverted = @{}
foreach ($blob in ($blobs | Where-Object { $_.ObjectiveIndex -eq "32" })) {
    $c = Convert-Blob $blob
    if ($c) {
        if (-not $startConverted.ContainsKey($blob.QuestID)) { $startConverted[$blob.QuestID] = New-Object System.Collections.Generic.List[object] }
        $startConverted[$blob.QuestID].Add($c)
    }
}
$questsAtStart = New-Object System.Collections.Generic.HashSet[string]
$questsAtOwnPoint = New-Object System.Collections.Generic.HashSet[string]
$ownConverted = @{}
foreach ($blob in ($blobs | Where-Object { $_.ObjectiveIndex -eq "-1" })) {
    $c = Convert-Blob $blob
    if (-not $c) { continue }
    if (-not $ownConverted.ContainsKey($blob.QuestID)) { $ownConverted[$blob.QuestID] = New-Object System.Collections.Generic.List[object] }
    $ownConverted[$blob.QuestID].Add($c)
}
function Test-AncestorMap($ancestor, $map) {
    $up = $parentMap[$map]
    for ($i = 0; $up -and $up -ne '0' -and $i -lt 20; $i++) { if ($up -eq $ancestor) { return $true }; $up = $parentMap[$up] }
    return $false
}
$droppedParentCopies = 0
foreach ($questId in ($ownConverted.Keys | Sort-Object { [int]$_ })) {
    if ($startConverted.ContainsKey($questId)) {
        # The client also lists a start on a parent map (a continent over a zone) at the same place.
        $starts = $startConverted[$questId]
        $chosen = @($starts | Where-Object { $c = $_; -not ($starts | Where-Object { $_ -ne $c -and (Test-AncestorMap $c.Blob.UiMapID $_.Blob.UiMapID) }) })
        $droppedParentCopies += $starts.Count - $chosen.Count
        [void]$questsAtStart.Add($questId)
    } else {
        $chosen = $ownConverted[$questId]
        [void]$questsAtOwnPoint.Add($questId)
    }
    $ours = $ourQuests[$questId]
    foreach ($c in $chosen) {
        $results.Add([PSCustomObject]@{
            QuestID        = $questId
            UiMapID        = $c.Blob.UiMapID
            MapX           = $c.X
            MapY           = $c.Y
            NumPointsUsed  = $pointsByBlob[$c.Blob.ID].Count
            ObjectiveIndex = $c.Blob.ObjectiveIndex
            InOurDB        = [bool]$ours
            OurQuestName   = if ($ours) { $ours.Name } else { "" }
            OurZoneName    = if ($ours) { $ours.Zone } else { "" }
        })
    }
}

Write-Output "Skipped (no matching point): $skippedNoPoint"
Write-Output "Skipped (no matching region): $skippedNoRegion"
Write-Output "Skipped (point outside every region of its map): $skippedOffMap"
Write-Output "Quests placed at their start (point 32): $($questsAtStart.Count); at their own point (-1): $($questsAtOwnPoint.Count)"
Write-Output "Starts on a parent map of another start of the quest, left out: $droppedParentCopies"
Write-Output "Converted quest locations: $($results.Count)"

$outFile = "$toolsDir\quest_locations.csv"
$results | Export-Csv -Path $outFile -NoTypeInformation -Encoding utf8
Write-Output "Written to $outFile"

$inOurDb = ($results | Where-Object { $_.InOurDB }).Count
$notInOurDb = $results.Count - $inOurDb
Write-Output "Quests already in our quest data: $inOurDb"
Write-Output "Quests NOT in our quest data (gap list): $notInOurDb"
