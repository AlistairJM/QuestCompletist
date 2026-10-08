<#
Phase 1 pipeline: join wago.tools QuestPOIBlob + QuestPOIPoint + UiMapAssignment
into per-quest, per-map converted (mapX%, mapY%) positions for quest-giver pins,
then cross-reference against this addon's own quests (data\quests.jsonl).

A pin goes where a quest starts: its point 32 in QuestPOIBlob, else its point -1, which is the
quest's own point (where it starts and ends when that is one place, the turn-in otherwise). A start on
the parent map of another start of the quest (a continent over a zone) is left out. A quest with
a point 32 and no point -1 on a map is placed if it has a pin already, or is one of our quests and not in
the client's task table (QuestV2CliTask: world quests, bonus objectives and some dailies, which the addon
doesn't pin).

A quest the client's export lists no point for at all, and that passes the rules in
docs/plans/quest-location-data-pipeline.md ("October 2026, pins from TrinityCore"), gets its start
from TrinityCore's quest_poi instead (Source=trinitycore). It is named after a starter whose spawn
stands at the start. Without the TrinityCore dump or Lua it only warns and places none.

Inputs (expected already downloaded into tools/):
  QuestPOIBlob.csv, QuestPOIPoint.csv, UiMapAssignment.csv, UiMap.csv, QuestV2CliTask.csv, QuestV2.csv,
  QuestInfo.csv (step 1b), tools/tdb/TDB_full_world_*.sql (read with Lua 5.1), the addon's
  qcUnavailableQuests.lua; parameters -AddonDir, -TdbFile, -LuaExe

Output:
  tools/quest_locations.csv - QuestID, UiMapID, MapX, MapY, NumPointsUsed, ObjectiveIndex (32 or -1),
  InOurDB, OurQuestName, OurZoneName, Source, StarterNpcIds, StarterNames, GiverNpcId, GiverName
  tools/quest_locations_tdb_review.csv - quests TrinityCore has a start for that were left out, and why
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$TdbFile = '',
    [string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe'
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
    $ourQuests[[string]$quest.id] = @{ Name = $quest.name; Zone = $quest.zone; Type = $quest.type; Holiday = $quest.holiday; Profession = $quest.profession; Category = $quest.category }
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
# else at its point -1. A quest with a point 32 and no point -1 gets a location if it has a pin
# already (to move that pin to its start) or is one of our quests and not in the task table.
$pinned = New-Object System.Collections.Generic.HashSet[string]
foreach ($pin in (Read-PinData $DataDir)) { foreach ($questId in $pin.quests) { [void]$pinned.Add([string]$questId) } }
if (-not (Test-Path "$toolsDir\QuestV2CliTask.csv")) { throw "QuestV2CliTask.csv missing (step 1b): without it every task quest would get a pin" }
$isTask = New-Object System.Collections.Generic.HashSet[string]
foreach ($row in (Import-Csv "$toolsDir\QuestV2CliTask.csv")) { [void]$isTask.Add($row.ID) }
if ($isTask.Count -eq 0) { throw "QuestV2CliTask.csv has no rows" }
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
$startOnly = @($startConverted.Keys | Where-Object { -not $ownConverted.ContainsKey($_) -and ($pinned.Contains($_) -or ($ourQuests.ContainsKey($_) -and -not $isTask.Contains($_))) })
foreach ($questId in (@($ownConverted.Keys) + $startOnly | Sort-Object { [int]$_ })) {
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
            Source         = 'client'
            StarterNpcIds  = ''
            StarterNames   = ''
            GiverNpcId     = ''
            GiverName      = ''
        })
    }
}

# Quests the client's export lists no point for at all, from TrinityCore's quest_poi: the points the
# server sends the client, with the same ObjectiveIndex 32 for where a quest starts. Only one of our
# quests that has no pin, isn't a task quest, a system quest, a holiday quest or a removed one gets a
# location, at each place it starts (docs\plans\quest-location-data-pipeline.md, "October 2026, pins
# from TrinityCore"). What it leaves out for a reason a person should look at goes into
# tools\quest_locations_tdb_review.csv.
$tdbFile = if ($TdbFile) { $TdbFile } else { Get-ChildItem "$toolsDir\tdb\TDB_full_world_*.sql" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName }
$tdbPlaced = 0
$tdbPlaces = 0
$tdbSkipped = @{}
$tdbReview = New-Object System.Collections.Generic.List[object]
$tdbReviewFile = "$toolsDir\quest_locations_tdb_review.csv"
if (-not $tdbFile -or -not (Test-Path $LuaExe)) {
    Write-Warning "Skipping TrinityCore's start points: no tools\tdb\TDB_full_world_*.sql or no Lua 5.1 at ${LuaExe}. Quests only TrinityCore knows a start for get no location this run."
    if (Test-Path $tdbReviewFile) { Remove-Item $tdbReviewFile }
} else {
    function Read-DumpTable([string]$table, [string]$columns, [int]$atLeast) {
        $outputEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        try { $rows = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $tdbFile $table $columns) } finally { [Console]::OutputEncoding = $outputEncoding }
        if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $tdbFile ($table)" }
        if ($rows.Count -lt $atLeast) { throw "$table has $($rows.Count) rows in $tdbFile, fewer than the $atLeast expected: has the dump's layout changed?" }
        return $rows
    }
    foreach ($needed in 'QuestV2.csv', 'QuestInfo.csv') { if (-not (Test-Path "$toolsDir\$needed")) { throw "$needed missing (step 1b): needed to tell the quests TrinityCore's points may place" } }
    $questV2 = New-Object System.Collections.Generic.HashSet[string]
    foreach ($row in (Import-Csv "$toolsDir\QuestV2.csv")) { [void]$questV2.Add($row.ID) }
    $systemInfo = New-Object System.Collections.Generic.HashSet[string]
    foreach ($row in (Import-Csv "$toolsDir\QuestInfo.csv")) {
        if ($row.InfoName_lang -match 'World Quest|Emissary|Hidden Quest|Delve|Warfront Contribution|Envoy|Meta Quest|Professions|Pickpocketing|War Mode|Tracking|Bonus Objective') { [void]$systemInfo.Add($row.ID) }
    }
    $disabledMap = New-Object System.Collections.Generic.HashSet[string]
    foreach ($row in (Import-Csv "$toolsDir\UiMap.csv")) { if ($row.Name_lang -match 'Disabled') { [void]$disabledMap.Add($row.ID) } }
    $unavailable = New-Object System.Collections.Generic.HashSet[string]
    $unavailableFile = Join-Path $AddonDir 'qcUnavailableQuests.lua'
    if (Test-Path $unavailableFile) { foreach ($m in [regex]::Matches([IO.File]::ReadAllText($unavailableFile), '\[(\d+)\]=')) { [void]$unavailable.Add($m.Groups[1].Value) } }
    $clientListed = New-Object System.Collections.Generic.HashSet[string]
    foreach ($blob in $blobs) { [void]$clientListed.Add($blob.QuestID) }
    $template = @{}
    foreach ($row in (Read-DumpTable 'quest_template' '1,6,24' 30000)) { $f = $row.Split("`t"); $template[$f[0]] = @{ Info = $f[1]; Flags = [int64]$f[2] } }
    $disabled = New-Object System.Collections.Generic.HashSet[string]
    foreach ($row in (Read-DumpTable 'disables' '1,2' 2000)) { $f = $row.Split("`t"); if ($f[0] -eq '1') { [void]$disabled.Add($f[1]) } }
    $hasStarter = New-Object System.Collections.Generic.HashSet[string]
    $starterIds = @{}
    foreach ($row in (Read-DumpTable 'creature_queststarter' '1,2' 5000)) {
        $f = $row.Split("`t")
        [void]$hasStarter.Add($f[1])
        if (-not $starterIds.ContainsKey($f[1])) { $starterIds[$f[1]] = New-Object System.Collections.Generic.List[string] }
        $starterIds[$f[1]].Add($f[0])
    }
    foreach ($row in (Read-DumpTable 'gameobject_queststarter' '1,2' 1000)) { $f = $row.Split("`t"); [void]$hasStarter.Add($f[1]) }
    $systemCategories = @(170, 173, 191, 290, 1092, 1095, 1130, 1133, 1134, 1232, 1241, 1246, 1346, 1347, 1428, 1429, 1430, 1431, 1514, 1735)
    $holidayCategories = @(31, 37, 46, 50, 90, 126, 127, 133, 145, 153, 413)
    $landfall = 121
    $internalName = '\[DNT\]|\bDNT\b|\bTBD\b|\bDEPRECATED\b|^Test$|Test Quest$|Flight Test$|\bJrz\b|\bPlaceholder\b|^(Conditional Objectives|Prey Contract:|Paragon of |Bonus Objective:)'
    function Get-TdbSkipReason([string]$questId) {
        $ours = $ourQuests[$questId]
        if (-not $ours) { return 'not in our data' }
        if ($pinned.Contains($questId)) { return 'already has a pin' }
        if ($isTask.Contains($questId)) { return 'task quest' }
        if ($unavailable.Contains($questId)) { return 'flagged unavailable' }
        if (@(0, 1, 2, 4, 128) -notcontains [int]$ours.Type) { return 'quest type' }
        if ($ours.Holiday -or $ours.Profession) { return 'holiday or profession quest' }
        if ($holidayCategories -contains [int]$ours.Category) { return 'holiday category' }
        if ($systemCategories -contains [int]$ours.Category) { return 'system category' }
        if ([int]$ours.Category -eq $landfall) { return 'Landfall (retired dailies)' }
        if ($ours.Name -match $internalName) { return 'internal name' }
        if (-not $questV2.Contains($questId)) { return 'not in the client' }
        if ($disabled.Contains($questId)) { return 'disabled in TrinityCore' }
        $t = $template[$questId]
        if (-not $t) { return 'no row in TrinityCore quest_template' }
        if ($t.Flags -band 0x400) { return 'tracking quest' }
        if ($t.Flags -band 0x4000) { return 'unavailable in TrinityCore' }
        if (($t.Flags -band 0x80000) -and ($t.Flags -band 0x10000)) { return 'scripted helper' }
        if (($t.Flags -band 0x80000) -and -not $hasStarter.Contains($questId) -and [int]$ours.Category -ne 19) { return 'auto-accepted, no giver' }
        if ([int]$ours.Type -eq 128 -and -not ($t.Flags -band 0x9000)) { return 'weekly without a weekly or daily flag' }
        if ($systemInfo.Contains($t.Info)) { return 'system kind of quest' }
        if ($clientListed.Contains($questId)) { return 'the client lists it' }
        return $null
    }
    $reasonOf = @{}
    $startBlobs = @{}
    $allStarts = @{}
    $atPoint = @{}
    foreach ($row in (Read-DumpTable 'quest_poi' '1,3,4,7,8' 40000)) {
        $f = $row.Split("`t")
        if ($f[2] -ne '32') { continue }
        if ($ourQuests.ContainsKey($f[0])) { $allStarts["$($f[0])|$($f[1])"] = $f[3] }
        if (-not $reasonOf.ContainsKey($f[0])) { $reasonOf[$f[0]] = Get-TdbSkipReason $f[0] }
        if ($reasonOf[$f[0]]) { continue }
        if ($disabledMap.Contains($f[4])) { $tdbReview.Add([pscustomobject]@{ QuestID = $f[0]; Name = $ourQuests[$f[0]].Name; Reason = 'start on a disabled map'; Detail = "map $($f[4])" }); continue }
        $startBlobs["$($f[0])|$($f[1])"] = @{ Quest = $f[0]; MapID = $f[3]; UiMapID = $f[4]; Seen = $false }
    }
    foreach ($reason in $reasonOf.Values) { if ($reason) { $tdbSkipped[$reason] = 1 + [int]$tdbSkipped[$reason] } }
    $tdbStarts = @{}
    foreach ($row in (Read-DumpTable 'quest_poi_points' '1,2,3,4,5' 80000)) {
        $f = $row.Split("`t")
        if ($f[2] -ne '0') { continue }
        $startKey = "$($f[0])|$($f[1])"
        if ($allStarts.ContainsKey($startKey)) {
            $k = "$($allStarts[$startKey])|$([math]::Round([double]$f[3]))|$([math]::Round([double]$f[4]))"
            if (-not $atPoint.ContainsKey($k)) { $atPoint[$k] = New-Object System.Collections.Generic.HashSet[string] }
            [void]$atPoint[$k].Add($f[0])
        }
        $blob = $startBlobs[$startKey]
        if (-not $blob) { continue }
        $blob.Seen = $true
        if (-not $regionsByMap.ContainsKey($blob.UiMapID)) { $tdbReview.Add([pscustomobject]@{ QuestID = $f[0]; Name = $ourQuests[$f[0]].Name; Reason = 'start on a map without a region'; Detail = "map $($blob.UiMapID)" }); continue }
        $conv = Get-BestConversion -worldX ([double]$f[3]) -worldY ([double]$f[4]) -instanceId $blob.MapID -candidateRegions $regionsByMap[$blob.UiMapID]
        if (-not $conv) { $tdbReview.Add([pscustomobject]@{ QuestID = $f[0]; Name = $ourQuests[$f[0]].Name; Reason = 'start outside every region of its map'; Detail = "map $($blob.UiMapID)" }); continue }
        if (-not $tdbStarts.ContainsKey($f[0])) { $tdbStarts[$f[0]] = New-Object System.Collections.Generic.List[object] }
        $tdbStarts[$f[0]].Add(@{ UiMapID = $blob.UiMapID; MapID = $blob.MapID; WX = [double]$f[3]; WY = [double]$f[4]; X = [math]::Round($conv.X * 100, 2); Y = [math]::Round($conv.Y * 100, 2) })
    }
    foreach ($key in $startBlobs.Keys) {
        if (-not $startBlobs[$key].Seen) { $q = $startBlobs[$key].Quest; $tdbReview.Add([pscustomobject]@{ QuestID = $q; Name = $ourQuests[$q].Name; Reason = 'start without a point'; Detail = $key }) }
    }
    # Some starts are one placeholder world point shared by quests of several zones (Mechagon's board
    # holds quests of Maldraxxus and Zereth Mortis): where five or more quests of ours, pinned or not, of
    # three or more categories start at a point, only the quests of its commonest category (if that is
    # half of them) stay.
    $placeholder = @{}
    foreach ($k in $atPoint.Keys) {
        $quests = @($atPoint[$k])
        $categories = @($quests | ForEach-Object { $ourQuests[$_].Category } | Group-Object | Sort-Object Count -Descending)
        if ($quests.Count -lt 5 -or $categories.Count -lt 3) { continue }
        $keep = if ($categories[0].Count * 2 -ge $quests.Count) { $categories[0].Name } else { $null }
        foreach ($q in $quests) { if ($null -eq $keep -or [string]$ourQuests[$q].Category -ne [string]$keep) { $placeholder[$q] = "$($quests.Count) quests of $($categories.Count) categories share the point $k" } }
    }
    $creatureName = @{}
    foreach ($row in (Read-DumpTable 'creature_template' '1,4' 30000)) { $f = $row.Split("`t"); $creatureName[$f[0]] = $f[1] }
    $wantedStarters = New-Object System.Collections.Generic.HashSet[string]
    foreach ($questId in $tdbStarts.Keys) { foreach ($id in $starterIds[$questId]) { [void]$wantedStarters.Add($id) } }
    $spawnsOf = @{}
    foreach ($row in (Read-DumpTable 'creature' '1,2,3,13,14' 150000)) {
        $f = $row.Split("`t")
        if (-not $wantedStarters.Contains($f[1])) { continue }
        if (-not $spawnsOf.ContainsKey($f[1])) { $spawnsOf[$f[1]] = New-Object System.Collections.Generic.List[object] }
        $spawnsOf[$f[1]].Add(@{ Map = $f[2]; X = [double]$f[3]; Y = [double]$f[4] })
    }
    function Find-GiverAtPlace($ids, $place) {
        $best = $null; $bestDistance = 1.5
        foreach ($id in $ids) {
            foreach ($spawn in $spawnsOf[$id]) {
                $conv = Get-BestConversion -worldX $spawn.X -worldY $spawn.Y -instanceId $spawn.Map -candidateRegions $regionsByMap[$place.UiMapID]
                if (-not $conv) { continue }
                $distance = [math]::Sqrt([math]::Pow($conv.X * 100 - $place.X, 2) + [math]::Pow($conv.Y * 100 - $place.Y, 2))
                if ($distance -le $bestDistance) { $best = $id; $bestDistance = $distance }
            }
        }
        return $best
    }
    $maxPlaces = 6
    foreach ($questId in ($tdbStarts.Keys | Sort-Object { [int]$_ })) {
        $ours = $ourQuests[$questId]
        if ($placeholder.ContainsKey($questId)) { $tdbReview.Add([pscustomobject]@{ QuestID = $questId; Name = $ours.Name; Reason = 'placeholder start'; Detail = $placeholder[$questId] }); continue }
        $starts = $tdbStarts[$questId]
        $places = New-Object System.Collections.Generic.List[object]
        foreach ($s in $starts) {
            $covered = $starts | Where-Object { $_ -ne $s -and $_.MapID -eq $s.MapID -and (Test-AncestorMap $s.UiMapID $_.UiMapID) -and [math]::Abs($_.WX - $s.WX) -le 5 -and [math]::Abs($_.WY - $s.WY) -le 5 }
            if ($covered) { continue }
            $same = $places | Where-Object { $_.UiMapID -eq $s.UiMapID -and [math]::Sqrt([math]::Pow($_.X - $s.X, 2) + [math]::Pow($_.Y - $s.Y, 2)) -le 1.5 }
            if (-not $same) { $places.Add($s) }
        }
        if ($places.Count -gt $maxPlaces -or $places.Count -eq 0) {
            $tdbReview.Add([pscustomobject]@{ QuestID = $questId; Name = $ours.Name; Reason = "$($places.Count) places"; Detail = (($places | ForEach-Object { "$($_.UiMapID):$($_.X),$($_.Y)" }) -join ' ') })
            continue
        }
        $ids = @($starterIds[$questId] | Where-Object { $_ } | Select-Object -Unique)
        foreach ($place in $places) {
            $giver = Find-GiverAtPlace $ids $place
            $results.Add([PSCustomObject]@{
                QuestID        = $questId
                UiMapID        = $place.UiMapID
                MapX           = $place.X
                MapY           = $place.Y
                NumPointsUsed  = 1
                ObjectiveIndex = '32'
                InOurDB        = $true
                OurQuestName   = $ours.Name
                OurZoneName    = $ours.Zone
                Source         = 'trinitycore'
                StarterNpcIds  = $ids -join '|'
                StarterNames   = (@($ids | ForEach-Object { $creatureName[$_] } | Where-Object { $_ } | Select-Object -Unique)) -join '|'
                GiverNpcId     = if ($giver) { $giver } else { '' }
                GiverName      = if ($giver) { $creatureName[$giver] } else { '' }
            })
            $tdbPlaces++
        }
        $tdbPlaced++
    }
    $tdbReview | Export-Csv -Path $tdbReviewFile -NoTypeInformation -Encoding utf8
}
$tdbReviewed = @($tdbReview | Select-Object -ExpandProperty QuestID -Unique).Count
Write-Output "TrinityCore start points: $tdbPlaced quests placed at $tdbPlaces places; $tdbReviewed quests in tools\quest_locations_tdb_review.csv for a person to look at"
foreach ($reason in ($tdbSkipped.Keys | Sort-Object)) { Write-Output "  not placed, $($reason): $($tdbSkipped[$reason])" }

Write-Output "Skipped (no matching point): $skippedNoPoint"
Write-Output "Skipped (no matching region): $skippedNoRegion"
Write-Output "Skipped (point outside every region of its map): $skippedOffMap"
Write-Output "Quests placed at their start (point 32): $($questsAtStart.Count) ($($startOnly.Count) with no point -1, $(@($startOnly | Where-Object { -not $pinned.Contains($_) }).Count) of them with no pin yet); at their own point (-1): $($questsAtOwnPoint.Count)"
Write-Output "Starts on a parent map of another start of the quest, left out: $droppedParentCopies"
Write-Output "Converted quest locations: $($results.Count)"

$outFile = "$toolsDir\quest_locations.csv"
$results | Export-Csv -Path $outFile -NoTypeInformation -Encoding utf8
Write-Output "Written to $outFile"

$inOurDb = ($results | Where-Object { $_.InOurDB }).Count
$notInOurDb = $results.Count - $inOurDb
Write-Output "Quests already in our quest data: $inOurDb"
Write-Output "Quests NOT in our quest data (gap list): $notInOurDb"
