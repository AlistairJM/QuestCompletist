<#
Phase 1 pipeline: join wago.tools QuestPOIBlob + QuestPOIPoint + UiMapAssignment
into per-quest, per-map converted (mapX%, mapY%) positions for quest-giver pins,
then cross-reference against this addon's own qcQuestDatabase.

Inputs (expected already downloaded into tools/):
  QuestPOIBlob.csv, QuestPOIPoint.csv, UiMapAssignment.csv

Output:
  tools/quest_locations.csv - QuestID, UiMapID, MapX, MapY, NumPointsUsed, InOurDB, OurZoneName
#>

$toolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools"
$questFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"

Write-Output "Loading source tables..."
$blobs = Import-Csv "$toolsDir\QuestPOIBlob.csv"
$points = Import-Csv "$toolsDir\QuestPOIPoint.csv"
$regions = Import-Csv "$toolsDir\UiMapAssignment.csv"

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
# Formula verified in Phase 0 against two real in-game landmark readings.
function Convert-WorldToMapPercent($worldX, $worldY, $region) {
    $r0 = [double]$region.Region_0
    $r1 = [double]$region.Region_1
    $r3 = [double]$region.Region_3
    $r4 = [double]$region.Region_4
    $mapX = ($r4 - $worldY) / ($r4 - $r1)
    $mapY = ($r3 - $worldX) / ($r3 - $r0)
    return @{ X = $mapX; Y = $mapY }
}

# For UiMapIDs with multiple distinct regions, try each and keep the one that
# lands inside [0,1] on both axes. Falls back to the first region otherwise.
function Get-BestConversion($worldX, $worldY, $candidateRegions) {
    foreach ($region in $candidateRegions) {
        $result = Convert-WorldToMapPercent -worldX $worldX -worldY $worldY -region $region
        if ($result.X -ge 0 -and $result.X -le 1 -and $result.Y -ge 0 -and $result.Y -le 1) {
            return $result
        }
    }
    # Nothing fit cleanly - return the first region's result anyway, flagged by caller via out-of-range values
    return Convert-WorldToMapPercent -worldX $worldX -worldY $worldY -region $candidateRegions[0]
}

Write-Output "Loading our own qcQuestDatabase quest IDs and zone names..."
$content = Get-Content $questFile -Raw
$startIdx = $content.IndexOf("qcQuestDatabase={")
$dbBlock = $content.Substring($startIdx)
$ourQuestMatches = [regex]::Matches($dbBlock, '\[(\d+)\]=\{\d+,"([^"]*)",\d+,"([^"]*)"')
$ourQuests = @{}
foreach ($m in $ourQuestMatches) {
    $ourQuests[$m.Groups[1].Value] = @{ Name = $m.Groups[2].Value; Zone = $m.Groups[3].Value }
}
Write-Output "Our qcQuestDatabase has $($ourQuests.Count) quests parsed."

Write-Output "Processing quest-giver blobs (ObjectiveIndex = -1)..."
$giverBlobs = $blobs | Where-Object { $_.ObjectiveIndex -eq "-1" }
$results = New-Object System.Collections.Generic.List[object]
$skippedNoPoint = 0
$skippedNoRegion = 0

foreach ($blob in $giverBlobs) {
    $blobId = $blob.ID
    $questId = $blob.QuestID
    $uiMapId = $blob.UiMapID

    if (-not $pointsByBlob.ContainsKey($blobId)) { $skippedNoPoint++; continue }
    if (-not $regionsByMap.ContainsKey($uiMapId)) { $skippedNoRegion++; continue }

    $pt = $pointsByBlob[$blobId][0]  # take first point; >99.8% of giver blobs have exactly one anyway
    $candidateRegions = $regionsByMap[$uiMapId]
    $conv = Get-BestConversion -worldX ([double]$pt.X) -worldY ([double]$pt.Y) -candidateRegions $candidateRegions

    $ours = $ourQuests[$questId]

    $results.Add([PSCustomObject]@{
        QuestID       = $questId
        UiMapID       = $uiMapId
        MapX          = [math]::Round($conv.X * 100, 2)
        MapY          = [math]::Round($conv.Y * 100, 2)
        NumPointsUsed = $pointsByBlob[$blobId].Count
        InOurDB       = [bool]$ours
        OurQuestName  = if ($ours) { $ours.Name } else { "" }
        OurZoneName   = if ($ours) { $ours.Zone } else { "" }
    })
}

Write-Output "Skipped (no matching point): $skippedNoPoint"
Write-Output "Skipped (no matching region): $skippedNoRegion"
Write-Output "Converted quest-giver locations: $($results.Count)"

$outFile = "$toolsDir\quest_locations.csv"
$results | Export-Csv -Path $outFile -NoTypeInformation -Encoding utf8
Write-Output "Written to $outFile"

$inOurDb = ($results | Where-Object { $_.InOurDB }).Count
$notInOurDb = $results.Count - $inOurDb
Write-Output "Quests already in our qcQuestDatabase: $inOurDb"
Write-Output "Quests NOT in our qcQuestDatabase (gap list): $notInOurDb"
