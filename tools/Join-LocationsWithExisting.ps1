<#
Joins the new wago.tools-derived quest locations against the existing
qcPinDB.lua (quest-ID-keyed) to:
  1. Borrow NPC identity + icon type where the quest already has a pin.
  2. Measure drift: does the old pin's UiMapID/position still match reality?
#>

$toolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools"

$newLocations = Import-Csv "$toolsDir\quest_locations.csv"
$existing = Import-Csv "$toolsDir\existing_pindb_by_quest.csv"

# Index existing pin data by quest ID (a quest can have more than one old pin - keep all)
$existingByQuest = @{}
foreach ($e in $existing) {
    $key = $e.QuestID
    if (-not $existingByQuest.ContainsKey($key)) { $existingByQuest[$key] = @() }
    $existingByQuest[$key] += $e
}

$joined = New-Object System.Collections.Generic.List[object]
$noExistingPin = 0
$mapIdDrift = 0
$sameMapPositionDrift = 0
$sameMapCloseEnough = 0

foreach ($loc in $newLocations) {
    $qid = $loc.QuestID
    if (-not $existingByQuest.ContainsKey($qid)) {
        $noExistingPin++
        $joined.Add([PSCustomObject]@{
            QuestID = $qid; UiMapID = $loc.UiMapID; MapX = $loc.MapX; MapY = $loc.MapY
            InOurDB = $loc.InOurDB; OurQuestName = $loc.OurQuestName; OurZoneName = $loc.OurZoneName
            HasExistingPin = $false; DriftStatus = "no-existing-pin"
            OldUiMapID = ""; OldMapX = ""; OldMapY = ""; NpcId = ""; NpcName = ""; IconType = ""
        })
        continue
    }

    # A quest can have multiple old pins (rare) - just use the first for this pass
    $old = $existingByQuest[$qid][0]
    $driftStatus = ""

    if ($old.OldUiMapID -ne $loc.UiMapID) {
        $mapIdDrift++
        $driftStatus = "MAP_ID_DRIFT"
    } else {
        $dx = [double]$loc.MapX - [double]$old.OldMapX
        $dy = [double]$loc.MapY - [double]$old.OldMapY
        $dist = [math]::Sqrt($dx * $dx + $dy * $dy)
        if ($dist -gt 5) {
            $sameMapPositionDrift++
            $driftStatus = "POSITION_DRIFT ($([math]::Round($dist,1)) pts)"
        } else {
            $sameMapCloseEnough++
            $driftStatus = "OK"
        }
    }

    $joined.Add([PSCustomObject]@{
        QuestID = $qid; UiMapID = $loc.UiMapID; MapX = $loc.MapX; MapY = $loc.MapY
        InOurDB = $loc.InOurDB; OurQuestName = $loc.OurQuestName; OurZoneName = $loc.OurZoneName
        HasExistingPin = $true; DriftStatus = $driftStatus
        OldUiMapID = $old.OldUiMapID; OldMapX = $old.OldMapX; OldMapY = $old.OldMapY
        NpcId = $old.NpcId; NpcName = $old.NpcName; IconType = $old.IconType
    })
}

Write-Output "=== Summary ==="
Write-Output "Total new locations: $($newLocations.Count)"
Write-Output "No existing pin at all (net-new location data): $noExistingPin"
Write-Output "Existing pin, but UiMapID drifted: $mapIdDrift"
Write-Output "Existing pin, same UiMapID, position drifted >5 pts: $sameMapPositionDrift"
Write-Output "Existing pin, same UiMapID, position matches (<=5 pts): $sameMapCloseEnough"

$outFile = "$toolsDir\quest_locations_joined.csv"
$joined | Export-Csv -Path $outFile -NoTypeInformation -Encoding utf8
Write-Output "Written to $outFile"
