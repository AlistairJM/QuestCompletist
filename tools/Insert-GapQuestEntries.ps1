<#
Generates qcQuestDatabase entries for the gap-list quests fetched from Blizzard's
API and inserts them into qcQuest.lua, right after the qcQuestDatabase={ line.

Field layout matches the existing schema (verified against real rows this session):
id, name, level, zone, areaid, type, faction, race, class, profession, holiday,
covenant, storyline, prereq, field15(unused), factionid, repvalue.

Safe defaults for fields the API can't tell us: areaid=0 (not mapped into our
own zone-category scheme - a known limitation), type=1 (normal quest - the
overwhelming empirical default), race=67108863 (all races), class=8191 (all
classes), everything else 0 (no restriction/no data).
#>

$toolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools"
$questFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"

$data = Import-Csv "$toolsDir\gap_quest_data.csv"
Write-Output "Generating entries for $($data.Count) quests..."

function Escape-Lua($s) {
    return ($s -replace '\\', '\\\\') -replace '"', '\"'
}

$lines = New-Object System.Collections.Generic.List[string]
foreach ($row in $data) {
    $factionBits = switch ($row.Faction) {
        "ALLIANCE" { 1 }
        "HORDE" { 2 }
        default { 3 }
    }
    $title = Escape-Lua $row.Title
    $zone = Escape-Lua $row.AreaName
    $level = if ($row.Level) { $row.Level } else { 0 }
    $lines.Add("[$($row.QuestID)]={$($row.QuestID),`"$title`",$level,`"$zone`",0,1,$factionBits,67108863,8191,0,0,0,0,0,0,0,0},")
}

$content = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($questFile))
$marker = "qcQuestDatabase={"
$anchorMatch = [regex]::Match($content, '(?m)^qcQuestDatabase=\{')
if (-not $anchorMatch.Success) { throw "Could not find qcQuestDatabase={ marker" }
$insertAt = $anchorMatch.Index + $marker.Length

$header = "`r`n-- Entries below added from Blizzard's Data API to backfill quests found in`r`n-- wago.tools' location data with no prior entry here (see docs/plans/quest-location-data-pipeline.md).`r`n-- areaid is unmapped (0) - these won't appear correctly in the zone checklist yet.`r`n"
$block = $header + ($lines -join "`r`n") + "`r`n"

$newContent = $content.Substring(0, $insertAt) + $block + $content.Substring($insertAt)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllBytes($questFile, $utf8NoBom.GetBytes($newContent))

Write-Output "Inserted $($lines.Count) entries into $questFile"
