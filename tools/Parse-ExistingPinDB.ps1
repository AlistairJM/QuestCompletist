<#
Parses the existing qcPinDB.lua into a flat, quest-ID-keyed lookup:
  QuestID -> { NpcId, NpcName, IconType, OldUiMapID, OldMapX, OldMapY }

A single quest ID can appear at multiple pins (e.g. offered in more than one
place) - all occurrences are kept as a list per quest ID.
#>

$pinFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcPinDB.lua"
$outFile = "C:\Users\alist\RiderProjects\QuestCompletist\tools\existing_pindb_by_quest.csv"

$lines = Get-Content $pinFile
$currentUiMapId = $null
$results = New-Object System.Collections.Generic.List[object]

$pinPattern = '^\s*\{(\d+),(\d+),(\d+),(?:"([^"]*)"|nil),([\d.]+),([\d.]+),\{([\d,]*)\}'
$mapHeaderPattern = '^\s*\[(\d+)\]\s*=\s*\{'

foreach ($line in $lines) {
    $mapMatch = [regex]::Match($line, $mapHeaderPattern)
    if ($mapMatch.Success) {
        $currentUiMapId = $mapMatch.Groups[1].Value
        continue
    }

    $pinMatch = [regex]::Match($line, $pinPattern)
    if ($pinMatch.Success -and $currentUiMapId) {
        $mapLevel = $pinMatch.Groups[1].Value
        $iconType = $pinMatch.Groups[2].Value
        $npcId = $pinMatch.Groups[3].Value
        $npcName = $pinMatch.Groups[4].Value
        $mapX = $pinMatch.Groups[5].Value
        $mapY = $pinMatch.Groups[6].Value
        $questIdsRaw = $pinMatch.Groups[7].Value
        if ($questIdsRaw) {
            $questIds = $questIdsRaw -split ','
            foreach ($qid in $questIds) {
                $results.Add([PSCustomObject]@{
                    QuestID     = $qid
                    OldUiMapID  = $currentUiMapId
                    OldMapLevel = $mapLevel
                    OldMapX     = $mapX
                    OldMapY     = $mapY
                    IconType    = $iconType
                    NpcId       = $npcId
                    NpcName     = $npcName
                })
            }
        }
    }
}

Write-Output "Total (quest, pin) associations parsed: $($results.Count)"
$distinctQuests = ($results | Select-Object QuestID -Unique).Count
Write-Output "Distinct quest IDs with an existing pin: $distinctQuests"

$results | Export-Csv -Path $outFile -NoTypeInformation -Encoding utf8
Write-Output "Written to $outFile"
