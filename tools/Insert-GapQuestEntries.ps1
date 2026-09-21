<#
Generates qcQuestDatabase entries for the gap-list quests fetched from Blizzard's
API and inserts them into qcQuest.lua, right after the qcQuestDatabase={ line.

Field layout matches the existing schema (verified against real rows this session):
id, name, level, zone, areaid, type, faction, race, class, profession, holiday,
covenant, storyline, prereq, field15(unused), factionid, repvalue.

Safe defaults for fields the API can't tell us: areaid=0 (not mapped into our
own zone-category scheme - a known limitation), type=1 (normal quest - the
overwhelming empirical default), everything else 0 (no restriction/no data).
Race/class default to "all" (67108863/8191) UNLESS Fetch-GapQuestData.ps1 found
a real restriction in requirements.classes/requirements.races - see
Class-race-restriction-bugfix in git history for why this matters: an earlier
version of this script always defaulted to "all", silently dropping real
class-specific quest restrictions (e.g. Druid-only Order Hall quests) for 87
quests before that got caught and fixed.
#>

$toolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools"
$questFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"

$data = Import-Csv "$toolsDir\gap_quest_data.csv"
Write-Output "Generating entries for $($data.Count) quests..."

function Escape-Lua($s) {
    return ($s -replace '\\', '\\\\') -replace '"', '\"'
}

$classBits = @{
    "WARRIOR"=1;"PALADIN"=2;"HUNTER"=4;"ROGUE"=8;"PRIEST"=16;"DEATHKNIGHT"=32;"SHAMAN"=64;
    "MAGE"=128;"WARLOCK"=256;"DRUID"=512;"MONK"=1024;"DEMONHUNTER"=2048;"EVOKER"=4096
}
$raceBits = @{
    "HUMAN"=1;"ORC"=2;"DWARF"=4;"NIGHTELF"=8;"SCOURGE"=16;"TAUREN"=32;"GNOME"=64;"TROLL"=128;
    "GOBLIN"=256;"BLOODELF"=512;"DRAENEI"=1024;"WORGEN"=2048;"PANDAREN"=4096;"VOIDELF"=8192;
    "NIGHTBORNE"=16384;"HIGHMOUNTAINTAUREN"=32768;"LIGHTFORGEDDRAENEI"=65536;"DARKIRONDWARF"=131072;
    "MAGHARORC"=262144;"ZANDALARITROLL"=524288;"KULTIRAN"=1048576;"VULPERA"=2097152;
    "MECHAGNOME"=4194304;"DRACTHYR"=8388608;"EARTHENDWARF"=16777216;"HARRONIR"=33554432
}
$ALL_RACES = 67108863
$ALL_CLASSES = 8191
function Normalize($s) { return ($s -replace "[^a-zA-Z0-9]", "").ToUpper() }

# Resolves a Blizzard requirements.classes/races name list into our bitmask.
# Falls back to "all" (unrestricted) whenever the list can't be resolved with
# confidence - e.g. it names a race/class we don't have a bit for, lists so
# many entries it's clearly a faction-equivalent expression rather than a
# genuine narrow restriction (more than $maxNarrow entries), or contains a
# non-class sentinel like "Adventurer" (seen on quests that also list every
# other class - Blizzard's way of saying "no real restriction").
function Resolve-Bitmask($namesJoined, $bitTable, $allValue, $maxNarrow) {
    if (-not $namesJoined) { return $allValue }
    $names = $namesJoined -split ";"
    if ($names -contains "Adventurer") { return $allValue }
    if ($names.Count -gt $maxNarrow) { return $allValue }
    $mask = 0
    foreach ($n in $names) {
        $key = Normalize $n
        if (-not $bitTable.ContainsKey($key)) { return $allValue }
        $mask = $mask -bor $bitTable[$key]
    }
    if ($mask -eq 0) { return $allValue }
    return $mask
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
    $raceMask = Resolve-Bitmask $row.RaceNames $raceBits $ALL_RACES 8
    $classMask = Resolve-Bitmask $row.ClassNames $classBits $ALL_CLASSES 12
    $lines.Add("[$($row.QuestID)]={$($row.QuestID),`"$title`",$level,`"$zone`",0,1,$factionBits,$raceMask,$classMask,0,0,0,0,0,0,0,0},")
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
