<#
Adds the gap-list quests fetched from Blizzard's API (tools\gap_quest_data.csv) to the end of
data\quests.jsonl, then rebuilds qcQuest.lua.

Safe defaults for fields the API can't tell us: type=1 (normal quest - the
overwhelming empirical default), everything else 0 (no restriction/no data).
The category starts at 0, then Place-UncategorisedQuests.ps1 runs on the same
data to file each new quest by its API area or its pin; the ones it can't
place are listed and stay at 0. Apply the new pins (Assemble-PinDB.ps1 -Apply)
first, so the placement can use them.
Race/class default to "all" (67108863/8191) UNLESS Fetch-GapQuestData.ps1 found
a real restriction in requirements.classes/requirements.races - see git history
for why this matters: an earlier version of this script always defaulted to
"all", silently dropping real class-specific quest restrictions (e.g.
Druid-only Order Hall quests) for 87 quests before that got caught and fixed.
Reputation rewards are NOT part of the entry: they live in qcQuestReputation,
keyed by quest ID. This script emitted them inline until that moved, and did it
one slot early (five zeros instead of six between class and the faction id), so
any entry it wrote needed correcting afterwards. Rewards for new quests go through
Apply-ReputationBackfill.ps1 instead.
#>

param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist')
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

$data = @(Import-Csv "$ToolsDir\gap_quest_data.csv")
if ($data.Count -eq 0) { Write-Output "gap_quest_data.csv lists no quests; nothing to add."; exit 0 }
Write-Output "Generating entries for $($data.Count) quests..."

$classBits = @{
    "WARRIOR"=1;"PALADIN"=2;"HUNTER"=4;"ROGUE"=8;"PRIEST"=16;"DEATHKNIGHT"=32;"SHAMAN"=64;
    "MAGE"=128;"WARLOCK"=256;"DRUID"=512;"MONK"=1024;"DEMONHUNTER"=2048;"EVOKER"=4096
}
$raceBits = @{
    "HUMAN"=1;"ORC"=2;"DWARF"=4;"NIGHTELF"=8;"SCOURGE"=16;"TAUREN"=32;"GNOME"=64;"TROLL"=128;
    "GOBLIN"=256;"BLOODELF"=512;"DRAENEI"=1024;"WORGEN"=2048;"PANDAREN"=4096;"VOIDELF"=8192;
    "NIGHTBORNE"=16384;"HIGHMOUNTAINTAUREN"=32768;"LIGHTFORGEDDRAENEI"=65536;"DARKIRONDWARF"=131072;
    "MAGHARORC"=262144;"ZANDALARITROLL"=524288;"KULTIRAN"=1048576;"VULPERA"=2097152;
    "MECHAGNOME"=4194304;"DRACTHYR"=8388608;"EARTHENDWARF"=16777216;"HARRONIR"=33554432;
    # Blizzard API display names that differ from the client race file names above
    "UNDEAD"=16;"EARTHEN"=16777216;"HARANIR"=33554432
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

$quests = @(Read-QuestData $DataDir)
# A second entry for a quest ID would silently replace the first when Lua loads the table.
$present = @{}
foreach ($quest in $quests) { $present[[string]$quest.id] = $true }
$duplicates = @($data | Where-Object { $present.ContainsKey("$($_.QuestID)") } | ForEach-Object { $_.QuestID })
if ($duplicates.Count) { throw "Already in quests.jsonl, refusing to insert again: $($duplicates -join ', ')" }

$added = foreach ($row in $data) {
    $factionBits = switch ($row.Faction) {
        "ALLIANCE" { 1 }
        "HORDE" { 2 }
        default { 3 }
    }
    [pscustomobject][ordered]@{
        id = [int]$row.QuestID
        name = $row.Title
        level = if ($row.Level) { [int]$row.Level } else { 0 }
        zone = $row.AreaName
        category = 0
        type = 1
        faction = $factionBits
        race = Resolve-Bitmask $row.RaceNames $raceBits $ALL_RACES 8
        class = Resolve-Bitmask $row.ClassNames $classBits $ALL_CLASSES 12
    }
}
Save-QuestData ($quests + @($added)) $DataDir $AddonDir
Write-Output "Added $($data.Count) quests to the end of quests.jsonl"

& "$PSScriptRoot\Place-UncategorisedQuests.ps1" -ToolsDir $ToolsDir -DataDir $DataDir -AddonDir $AddonDir

$inserted = @{}
foreach ($row in $data) { $inserted["$($row.QuestID)"] = $true }
$unplaced = @(Read-QuestData $DataDir | Where-Object { $inserted.ContainsKey([string]$_.id) -and $_.category -eq 0 } |
    ForEach-Object { "  $($_.id) $($_.name)" })
Write-Output "New quests left without a category: $($unplaced.Count)"
$unplaced
