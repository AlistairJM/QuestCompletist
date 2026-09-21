<#
Final assembly: for each converted quest-giver location, attach NPC identity +
icon type (borrowed from ANY existing pin match, regardless of drift status -
identity isn't affected by map-ID reorganization), group quests sharing the
same NPC into one pin, and emit valid qcPinDB.lua Lua table syntax as a new,
separate candidate file for review.
#>

$toolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools"
$questFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"

Write-Output "Loading profession flag (field 10) per quest for the default-icon fallback rule..."
$content = Get-Content $questFile -Raw
$startIdx = $content.IndexOf("qcQuestDatabase={")
$dbBlock = $content.Substring($startIdx)
$profMatches = [regex]::Matches($dbBlock, '\[(\d+)\]=\{\d+,"[^"]*",\d+,"[^"]*",\d+,\d+,\d+,\d+,\d+,(\d+),')
$questProfession = @{}
foreach ($m in $profMatches) {
    $questProfession[$m.Groups[1].Value] = [int]$m.Groups[2].Value
}

Write-Output "Loading existing pin data (any match, not just position-verified) for identity borrowing..."
$existing = Import-Csv "$toolsDir\existing_pindb_by_quest.csv"
$existingByQuest = @{}
foreach ($e in $existing) {
    if (-not $existingByQuest.ContainsKey($e.QuestID)) { $existingByQuest[$e.QuestID] = $e }
}

Write-Output "Loading converted quest-giver locations..."
$locations = Import-Csv "$toolsDir\quest_locations.csv"

# Attach identity/icon to every location row
$enriched = New-Object System.Collections.Generic.List[object]
foreach ($loc in $locations) {
    $npcId = "0"; $npcName = ""; $iconType = "1"; $mapLevel = "0"; $identitySource = "inferred-default"
    if ($existingByQuest.ContainsKey($loc.QuestID)) {
        $old = $existingByQuest[$loc.QuestID]
        $npcId = $old.NpcId
        $npcName = $old.NpcName
        $iconType = $old.IconType
        $identitySource = "borrowed"
    } elseif ($questProfession.ContainsKey($loc.QuestID) -and $questProfession[$loc.QuestID] -ne 0) {
        $iconType = "3"
    }
    $enriched.Add([PSCustomObject]@{
        QuestID = $loc.QuestID; UiMapID = $loc.UiMapID; MapX = $loc.MapX; MapY = $loc.MapY
        NpcId = $npcId; NpcName = $npcName; IconType = $iconType; MapLevel = $mapLevel
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
            NpcId = $e.NpcId; NpcName = $e.NpcName; IconType = $e.IconType; MapLevel = $e.OldMapLevel
            IdentitySource = "kept-old-unreplaced"
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
$pinGroups = @{}
$namedGroupKeysByMapAndName = @{}   # "$UiMapID|$MapLevel|$Name" -> List[pinGroups key], for proximity lookup
foreach ($row in $enriched) {
    $key = $null
    if ($row.NpcId -ne "0") {
        $key = "$($row.UiMapID)|$($row.MapLevel)|npc-$($row.NpcId)"
    } elseif ($row.NpcName) {
        $nameLookupKey = "$($row.UiMapID)|$($row.MapLevel)|$($row.NpcName)"
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
            $key = "$($row.UiMapID)|$($row.MapLevel)|quest-$($row.QuestID)"
            if (-not $namedGroupKeysByMapAndName.ContainsKey($nameLookupKey)) {
                $namedGroupKeysByMapAndName[$nameLookupKey] = New-Object System.Collections.Generic.List[string]
            }
            $namedGroupKeysByMapAndName[$nameLookupKey].Add($key)
        }
    } else {
        $key = "$($row.UiMapID)|$($row.MapLevel)|quest-$($row.QuestID)"
    }
    if (-not $pinGroups.ContainsKey($key)) {
        $pinGroups[$key] = [PSCustomObject]@{
            UiMapID = $row.UiMapID; MapLevel = $row.MapLevel; NpcId = $row.NpcId; NpcName = $row.NpcName
            IconType = $row.IconType; MapX = $row.MapX; MapY = $row.MapY
            QuestIDs = New-Object System.Collections.Generic.List[string]
        }
    }
    if (-not $pinGroups[$key].QuestIDs.Contains($row.QuestID)) {
        $pinGroups[$key].QuestIDs.Add($row.QuestID)
    }
}

Write-Output "Total pins after grouping: $($pinGroups.Count) (from $($enriched.Count) quest-giver locations)"

Write-Output "Emitting Lua syntax grouped by UiMapID..."
$byMap = @{}
foreach ($g in $pinGroups.Values) {
    if (-not $byMap.ContainsKey($g.UiMapID)) { $byMap[$g.UiMapID] = New-Object System.Collections.Generic.List[object] }
    $byMap[$g.UiMapID].Add($g)
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("qcPinDB_candidate = {")
foreach ($mapId in ($byMap.Keys | Sort-Object { [int]$_ })) {
    [void]$sb.AppendLine("`t[$mapId] = {")
    foreach ($pin in $byMap[$mapId]) {
        $nameLiteral = if ($pin.NpcName) { '"' + ($pin.NpcName -replace '"', '\"') + '"' } else { "nil" }
        $questList = ($pin.QuestIDs -join ",")
        [void]$sb.AppendLine("`t`t{$($pin.MapLevel),$($pin.IconType),$($pin.NpcId),$nameLiteral,$($pin.MapX),$($pin.MapY),{$questList}},")
    }
    [void]$sb.AppendLine("`t},")
}
[void]$sb.AppendLine("}")

$outFile = "$toolsDir\qcPinDB_candidate.lua"
$sb.ToString() | Out-File -FilePath $outFile -Encoding utf8
Write-Output "Written candidate file to $outFile"

$borrowedCount = ($enriched | Where-Object { $_.IdentitySource -eq "borrowed" }).Count
$proximityCount = ($enriched | Where-Object { $_.IdentitySource -eq "proximity-matched" }).Count
$inferredCount = ($enriched | Where-Object { $_.IdentitySource -eq "inferred-default" }).Count
Write-Output "Identity borrowed from existing data (exact quest match): $borrowedCount"
Write-Output "Identity resolved via proximity match (same map, nearby known NPC): $proximityCount"
Write-Output "Identity still unknown (no prior pin, nothing nearby): $inferredCount"

$enriched | Export-Csv -Path "$toolsDir\quest_locations_enriched.csv" -NoTypeInformation -Encoding utf8
