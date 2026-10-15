<#
Adds the player-facing task quests (world quests, bonus objectives, world events and the like) that
the client's own task table lists and data\quests.jsonl lacks, then rebuilds qcQuestData.lua. No
step of the pipeline finds a task quest: a quest enters through a giver point, which a task quest has
none of, or through an answer from Blizzard's web API, which never serves one. No row is ever changed
or removed, no pin is made (the addon pins no world quest), and a second run adds nothing and writes
nothing.

A row of tools\QuestV2CliTask.csv is skipped, in this order:
  present     its ID is already in the data
  hidden      a tracker the game keeps out of the quest log: Flags_0 has 0x400 (the tracking flag), or
              its QuestInfoID is 265 (Hidden Quest), or its title is exactly "Tracking Quest"
  no title    an empty title, which the data refuses
  internal    a test, placeholder or do-not-translate entry ("[DNT] ...", "Test Quest", "(NOT USED)"):
              not a quest a player can meet, and the quest list would show it. The skipped titles are
              listed on every run, so a real quest with "Test" in its name shows there
Every other row is added, with the conventions of the 5,230 task quests already in the data (the
percentages are of those, October 2026):
  name        the client's title, as it is
  type        a weekly flag (Flags_0 0x8000) is 128; a daily flag (Flags_0 0x1000, or Flags_1 0x8000, the
              flag the quest cache calls flagsEx) is 4; a world quest kind (QuestInfo "... World Quest",
              "World Boss", "Dragonrider Racing") is 128; a Calling Quest is 4; anything else is 1. 94%
              of the existing rows agree. A quest that takes a holiday from its namesakes (below) with
              no flag takes their commonest type
  faction, race, class
              from FiltRaceMasks and FiltClasses as Get-WagoQuestRequirements.ps1 reads them (a mask
              of every race or class is no restriction); an Alliance-only mask is faction 1 with the
              Alliance's races, a Horde-only one faction 2, anything else faction 3. 97% agree
  profession  as Sync-QuestProfessions.ps1 gives it: the skill the quest asks for, else its QuestInfo
  level       the level our task quests of the same ContentTuningID carry (the commonest, the lowest
              of a tie), else our quests of that tuning in the retail quest cache, else 0 (no level).
              A task quest's level is its own convention (a family with no level of its own is 0, an
              expansion's quests hold its cap), so the API's range is not used: 99% agree when each
              existing row is left out of its own count
  zone        the name of the map most of its points are on in QuestPOIBlob, or its namesakes' zone
              text, or empty
  category    a quest whose namesakes in the data all carry one holiday takes that holiday, and their
              category too when it is one (Honor the Flame, Bar Tab Barrel); otherwise
              Place-UncategorisedQuests.ps1 files it, as Insert-GapQuestEntries.ps1 has it do (run on a
              scratch copy, so no old row is touched); last, the category of two or more namesakes that
              all agree. What is left stays in category 0, which the menu lists as Uncategorized
Left to the sweep's later steps, as for every quest that enters the data: prerequisites (step 2c) and
storylines (step 4), reputation (step 2), and a type that recurs, which the probe says (step 3).

Reads tools\QuestV2CliTask.csv, QuestInfo.csv, SkillLine.csv, QuestPOIBlob.csv, UiMap.csv and
ChrRaces.csv (downloaded for -Build when they are missing, or with -Refresh), and the newest
retail_quest_cache_*.jsonl when there is one. With -WhatIf nothing is written: it prints what it would
add, by type and category, and the quests it can't place. Without it the rows go in at the end of
data\quests.jsonl, in ID order, through AddonData.ps1.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = "12.1.5.70391",
    [string]$Cache = '',
    [switch]$Refresh,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. "$PSScriptRoot\AddonData.ps1"

foreach ($table in 'QuestV2CliTask', 'QuestInfo', 'SkillLine', 'QuestPOIBlob', 'UiMap', 'ChrRaces') {
    $path = Join-Path $ToolsDir "$table.csv"
    if ($Refresh -or -not (Test-Path $path)) {
        Write-Output "Downloading $table..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path
        Start-Sleep -Seconds 1
    }
}
if (-not $Cache) {
    $Cache = [string](Get-ChildItem (Join-Path $ToolsDir 'retail_quest_cache_*.jsonl') -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName)
}

$ALL_RACES = 67108863
$ALLIANCE_RACES = 64175181
$HORDE_RACES = 61658034
$ALL_CLASSES = 8191
$raceBits = @{
    "HUMAN"=1;"ORC"=2;"DWARF"=4;"NIGHTELF"=8;"SCOURGE"=16;"TAUREN"=32;"GNOME"=64;"TROLL"=128;
    "GOBLIN"=256;"BLOODELF"=512;"DRAENEI"=1024;"WORGEN"=2048;"PANDAREN"=4096;"VOIDELF"=8192;
    "NIGHTBORNE"=16384;"HIGHMOUNTAINTAUREN"=32768;"LIGHTFORGEDDRAENEI"=65536;"DARKIRONDWARF"=131072;
    "MAGHARORC"=262144;"ZANDALARITROLL"=524288;"KULTIRAN"=1048576;"VULPERA"=2097152;
    "MECHAGNOME"=4194304;"DRACTHYR"=8388608;"EARTHENDWARF"=16777216;"HARRONIR"=33554432
}
$raceByBit = @{}
foreach ($r in Import-Csv (Join-Path $ToolsDir 'ChrRaces.csv')) {
    $key = ($r.ClientFileString -replace "[^a-zA-Z]", "").ToUpper()
    if ($r.PlayableRaceBit -ne "-1" -and $raceBits.ContainsKey($key)) { $raceByBit[[int]$r.PlayableRaceBit] = $raceBits[$key] }
}
if (@($raceBits.Values | Where-Object { $raceByBit.Values -notcontains $_ }).Count) { throw "ChrRaces.csv doesn't name every playable race" }

function Convert-RaceMask($lo, $hi) {
    $m = ([long]$hi -shl 32) -bor ([long]$lo -band 0xFFFFFFFFL)
    $out = 0
    foreach ($b in $raceByBit.Keys) { if ($m -band ([long]1 -shl $b)) { $out = $out -bor $raceByBit[$b] } }
    return $out
}
function Test-EraComplete([long]$m) { return ($m -ge 1023) -and (($m -band ($m + 1)) -eq 0) }

$core = [IO.File]::ReadAllText((Join-Path $AddonDir 'qcCore.lua'))
$block = [regex]::Match($core, '(?s)qcProfessionBits = \{(.*?)\}').Groups[1].Value
$professionBit = @{}
foreach ($m in [regex]::Matches($block, '\[(\d+)\]\s*=\s*(\d+)')) { $professionBit[[int]$m.Groups[1].Value] = [int]$m.Groups[2].Value }
if ($professionBit.Count -eq 0) { throw "qcProfessionBits wasn't found in $AddonDir\qcCore.lua" }
$parentLine = @{}
foreach ($row in Import-Csv (Join-Path $ToolsDir 'SkillLine.csv')) { $parentLine[[int]$row.ID] = [int]$row.ParentSkillLineID }
function Get-ProfessionBit([int]$line) {
    for ($step = 0; $line -gt 0 -and $step -lt 5; $step++) {
        if ($professionBit.ContainsKey($line)) { return $professionBit[$line] }
        $line = $parentLine[$line]
    }
    return 0
}
$kindName = @{}
$kindProfession = @{}
foreach ($row in Import-Csv (Join-Path $ToolsDir 'QuestInfo.csv') -Encoding UTF8) {
    $kindName[[int]$row.ID] = [string]$row.InfoName_lang
    if ([int]$row.Profession) { $kindProfession[[int]$row.ID] = [int]$row.Profession }
}

$questText = [IO.File]::ReadAllText((Join-Path $AddonDir 'qcQuest.lua'), [Text.Encoding]::UTF8)
$categoryName = @{}
foreach ($m in [regex]::Matches([regex]::Match($questText, '(?sm)^qcQuestCategories=\{(.*?)^\}').Groups[1].Value, '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) {
    if (-not $categoryName.ContainsKey($m.Groups[1].Value)) { $categoryName[$m.Groups[1].Value] = $m.Groups[2].Value }
}
$inMenu = New-Object System.Collections.Generic.HashSet[string]
foreach ($line in [IO.File]::ReadAllLines((Join-Path $AddonDir 'qcMenu.lua'))) {
    if ($line -match '^\s*--') { continue }
    foreach ($m in [regex]::Matches($line, 'arg1=(\d+),')) { [void]$inMenu.Add($m.Groups[1].Value) }
}
function Test-UsableCategory([int]$category) { return $category -ne 0 -and $categoryName.ContainsKey([string]$category) -and $inMenu.Contains([string]$category) }

$records = @(Read-QuestData $DataDir)
$present = New-Object System.Collections.Generic.HashSet[int]
$namesakes = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[object]]'
foreach ($q in $records) {
    [void]$present.Add([int]$q.id)
    if (-not $namesakes.ContainsKey([string]$q.name)) { $namesakes[[string]$q.name] = New-Object System.Collections.Generic.List[object] }
    $namesakes[[string]$q.name].Add($q)
}

$internalName = [regex]'\[DNT\]|<DNT>|\(DNT\)|\bDNT\b|\bTBD\b|NOT USED|\[NYI\]|\[internal only\]|REUSE THIS RECORD|\[RNM\]|\[PH\]|\bTest\b|\bTesting\b|\bPlaceholder\b|\bDEPRECATED\b'
$taskRows = @(Import-Csv (Join-Path $ToolsDir 'QuestV2CliTask.csv') -Encoding UTF8)

$counts = [ordered]@{ read = $taskRows.Count; present = 0; hiddenFlag = 0; hiddenKind = 0; hiddenTitle = 0; noTitle = 0; internal = 0 }
$internalSkipped = New-Object System.Collections.Generic.List[string]
$todo = New-Object System.Collections.Generic.List[object]
foreach ($row in $taskRows) {
    $id = [int]$row.ID
    if ($present.Contains($id)) { $counts.present++; continue }
    if ([long]$row.Flags_0 -band 0x400) { $counts.hiddenFlag++; continue }
    if ([int]$row.QuestInfoID -eq 265) { $counts.hiddenKind++; continue }
    if ($row.QuestTitle_lang -ceq 'Tracking Quest') { $counts.hiddenTitle++; continue }
    if (-not $row.QuestTitle_lang) { $counts.noTitle++; continue }
    if ($internalName.IsMatch($row.QuestTitle_lang)) { $counts.internal++; $internalSkipped.Add("$id $($row.QuestTitle_lang)"); continue }
    $todo.Add($row)
}
$hidden = $counts.hiddenFlag + $counts.hiddenKind + $counts.hiddenTitle

"Task table: {0} rows." -f $counts.read
"  already in the data: {0}" -f $counts.present
"  hidden trackers, skipped: {0} (tracking flag {1}, QuestInfo 265 {2}, titled Tracking Quest {3})" -f $hidden, $counts.hiddenFlag, $counts.hiddenKind, $counts.hiddenTitle
"  no title, skipped: {0}" -f $counts.noTitle
"  internal names, skipped: {0}" -f $counts.internal
foreach ($line in $internalSkipped) { "    $line" }
"  to add: {0}" -f $todo.Count
if ($todo.Count -eq 0) { return }

# The level a content tuning's quests carry: the commonest, the lowest of a tie. Our task quests first, then every quest of ours the cache gives that tuning.
function Add-Level($table, [int]$tuning, [int]$level) {
    if ($tuning -eq 0) { return }
    if (-not $table.ContainsKey($tuning)) { $table[$tuning] = @{} }
    $table[$tuning][$level] = 1 + [int]$table[$tuning][$level]
}
function Get-CommonLevel($table, [int]$tuning) {
    if (-not $table.ContainsKey($tuning)) { return $null }
    return @($table[$tuning].GetEnumerator() | Sort-Object @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key } })[0].Key
}
$byId = @{}
foreach ($q in $records) { $byId[[int]$q.id] = $q }
$taskLevels = @{}
$allLevels = @{}
foreach ($row in $taskRows) {
    if ($byId.ContainsKey([int]$row.ID)) { Add-Level $taskLevels ([int]$row.ContentTuningID) ([int]$byId[[int]$row.ID].level) }
}
$cacheNote = 'no quest cache, so the level of a tuning no task quest of ours has is 0'
if ($Cache -and (Test-Path $Cache)) {
    $cacheNote = "quest cache $(Split-Path $Cache -Leaf)"
    foreach ($line in [IO.File]::ReadLines($Cache)) {
        $m = [regex]::Match($line, '^\{"id":(\d+),.*?"contentTuning":(\d+)')
        if ($m.Success -and $byId.ContainsKey([int]$m.Groups[1].Value)) { Add-Level $allLevels ([int]$m.Groups[2].Value) ([int]$byId[[int]$m.Groups[1].Value].level) }
    }
}

$mapName = @{}
foreach ($row in Import-Csv (Join-Path $ToolsDir 'UiMap.csv') -Encoding UTF8) { $mapName[[string]$row.ID] = [string]$row.Name_lang }
$mapBlobs = @{}
foreach ($blob in Import-Csv (Join-Path $ToolsDir 'QuestPOIBlob.csv')) {
    $id = [int]$blob.QuestID
    if (-not $mapBlobs.ContainsKey($id)) { $mapBlobs[$id] = @{} }
    $mapBlobs[$id][[string]$blob.UiMapID] = 1 + [int]$mapBlobs[$id][[string]$blob.UiMapID]
}
function Get-PrimaryMap([int]$id) {
    if (-not $mapBlobs.ContainsKey($id)) { return $null }
    return @($mapBlobs[$id].GetEnumerator() | Sort-Object @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { [int]$_.Key } })[0].Key
}

$added = New-Object System.Collections.Generic.List[object]
$sources = @{ level = @{}; holiday = 0; profession = 0; unknownKind = New-Object System.Collections.Generic.HashSet[int] }
foreach ($row in ($todo | Sort-Object { [int]$_.ID })) {
    $id = [int]$row.ID
    $kind = $kindName[[int]$row.QuestInfoID]
    if ($null -eq $kind) { $kind = ''; [void]$sources.unknownKind.Add([int]$row.QuestInfoID) }
    $f0 = [long]$row.Flags_0; $f1 = [long]$row.Flags_1
    $type = if ($f0 -band 0x8000) { 128 } elseif (($f0 -band 0x1000) -or ($f1 -band 0x8000)) { 4 } elseif ($kind -match 'World Quest|World Boss|Dragonrider Racing') { 128 } elseif ($kind -ceq 'Calling Quest') { 4 } else { 1 }
    $flagged = [bool](($f0 -band 0x9000) -or ($f1 -band 0x8000))

    $race = Convert-RaceMask $row.FiltRaceMasks_0 $row.FiltRaceMasks_1
    $class = [long]$row.FiltClasses -band $ALL_CLASSES
    if (Test-EraComplete $race) { $race = 0 }
    if (Test-EraComplete $class) { $class = 0 }
    $both = $ALLIANCE_RACES -band $HORDE_RACES
    $alliance = $race -band ($ALLIANCE_RACES -band -bnot $both)
    $horde = $race -band ($HORDE_RACES -band -bnot $both)
    $faction = if ($race -and $alliance -and -not $horde) { 1 } elseif ($race -and $horde -and -not $alliance) { 2 } else { 3 }
    $raceMask = if ($faction -eq 1) { $ALLIANCE_RACES } elseif ($faction -eq 2) { $HORDE_RACES } elseif ($race) { $race } else { $ALL_RACES }
    $classMask = if ($class) { $class } else { $ALL_CLASSES }

    $tuning = [int]$row.ContentTuningID
    $level = Get-CommonLevel $taskLevels $tuning
    $levelFrom = 'task quests of the tuning'
    if ($null -eq $level) { $level = Get-CommonLevel $allLevels $tuning; $levelFrom = 'quests of the tuning in the cache' }
    if ($null -eq $level) { $level = 0; $levelFrom = 'none' }
    $sources.level[$levelFrom] = 1 + [int]$sources.level[$levelFrom]

    $map = Get-PrimaryMap $id
    $zone = if ($map -and $mapName.ContainsKey($map)) { $mapName[$map] } else { '' }
    $category = 0
    $holiday = 0

    $same = if ($namesakes.ContainsKey([string]$row.QuestTitle_lang)) { @($namesakes[[string]$row.QuestTitle_lang]) } else { @() }
    $holidays = @($same | ForEach-Object { [int]$_.holiday } | Sort-Object -Unique)
    if ($same.Count -gt 0 -and $holidays.Count -eq 1 -and $holidays[0] -ne 0) {
        $holiday = $holidays[0]
        $sources.holiday++
        $categories = @($same | ForEach-Object { [int]$_.category } | Sort-Object -Unique)
        if ($categories.Count -eq 1 -and (Test-UsableCategory $categories[0])) {
            $category = $categories[0]
            $zone = [string]@($same | Group-Object zone | Sort-Object @{ Expression = { $_.Count }; Descending = $true }, Name)[0].Name
        }
        if (-not $flagged -and $type -eq 1) {
            $type = [int]@($same | Group-Object type | Sort-Object @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { [int]$_.Name } })[0].Name
        }
    }

    $bySkill = 0; $byKind = 0
    if ([int]$row.FiltMinSkillID) { $bySkill = Get-ProfessionBit ([int]$row.FiltMinSkillID) }
    if ($kindProfession.ContainsKey([int]$row.QuestInfoID)) { $byKind = Get-ProfessionBit $kindProfession[[int]$row.QuestInfoID] }
    $profession = if ($bySkill -and $byKind -and $bySkill -ne $byKind) { 0 } elseif ($bySkill) { $bySkill } else { $byKind }

    $quest = [pscustomobject][ordered]@{
        id = $id; name = [string]$row.QuestTitle_lang; level = [int]$level; zone = $zone; category = $category; type = $type
        faction = $faction; race = [int]$raceMask; class = [int]$classMask
    }
    if ($profession) { Set-RecordField $quest 'profession' $profession; $sources.profession++ }
    if ($holiday) { Set-RecordField $quest 'holiday' $holiday }
    $added.Add($quest)
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('add-task-quests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Path "$scratch\data", "$scratch\addon" | Out-Null
    Copy-Item (Join-Path $DataDir 'pins.jsonl') "$scratch\data"
    foreach ($file in 'qcQuest.lua', 'qcMenu.lua', 'qcPinDB.lua') { Copy-Item (Join-Path $AddonDir $file) "$scratch\addon" }
    [IO.File]::WriteAllText("$scratch\data\quests.jsonl", (ConvertTo-QuestJsonLines (@($records) + $added.ToArray())), $script:Utf8)
    $built = Invoke-AddonDataBuild "$scratch\data" "$scratch\addon"
    if (-not $built.Ok) { throw ("The scratch copy didn't build:`n  " + ($built.Lines -join "`n  ")) }
    & "$PSScriptRoot\Place-UncategorisedQuests.ps1" -ToolsDir $ToolsDir -DataDir "$scratch\data" -AddonDir "$scratch\addon" *> $null
    $placed = @{}
    foreach ($q in (Read-QuestData "$scratch\data")) { $placed[[int]$q.id] = [int]$q.category }
} finally {
    if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
}
$filedBy = @{ 'its namesakes, by holiday' = 0; 'Place-UncategorisedQuests.ps1' = 0; 'two or more namesakes in one category' = 0 }
foreach ($quest in $added) {
    if ($quest.category -ne 0) { $filedBy['its namesakes, by holiday']++; continue }
    if ($placed.ContainsKey($quest.id) -and $placed[$quest.id] -ne 0) { $quest.category = $placed[$quest.id]; $filedBy['Place-UncategorisedQuests.ps1']++; continue }
    $same = if ($namesakes.ContainsKey($quest.name)) { @($namesakes[$quest.name]) } else { @() }
    $categories = @($same | ForEach-Object { [int]$_.category } | Sort-Object -Unique)
    if ($same.Count -ge 2 -and $categories.Count -eq 1 -and (Test-UsableCategory $categories[0])) {
        $quest.category = $categories[0]
        if (-not $quest.zone) { $quest.zone = [string]@($same | Group-Object zone | Sort-Object @{ Expression = { $_.Count }; Descending = $true }, Name)[0].Name }
        $filedBy['two or more namesakes in one category']++
    }
}

"Rows to add: {0}" -f $added.Count
"  by type: " + ((@($added | Group-Object type | Sort-Object { [int]$_.Name }) | ForEach-Object { "{0} x{1}" -f $_.Name, $_.Count }) -join ', ')
"  by quest kind: " + ((@($todo | Group-Object { $k = $kindName[[int]$_.QuestInfoID]; if ($k) { $k } else { 'none' } } | Sort-Object Count -Descending) | ForEach-Object { "{0} x{1}" -f $_.Name, $_.Count }) -join ', ')
"  filed by: " + (($filedBy.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0} {1}" -f $_.Name, $_.Value }) -join '; ')
"  levels from: " + (($sources.level.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0} {1}" -f $_.Name, $_.Value }) -join '; ') + " ($cacheNote)"
"  with a profession: {0}; with a holiday from its namesakes: {1}" -f $sources.profession, $sources.holiday
if ($sources.unknownKind.Count) { "  QuestInfo.csv has no row for: " + (($sources.unknownKind | Sort-Object) -join ', ') }
"  by category:"
foreach ($group in ($added | Group-Object category | Sort-Object @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { [int]$_.Name } })) {
    $label = if ($group.Name -eq '0') { 'Uncategorized' } else { $categoryName[$group.Name] }
    "    {0} {1}: {2}" -f $group.Name, $label, $group.Count
}
$unplaced = @($added | Where-Object { $_.category -eq 0 })
"Left in category 0 (Uncategorized): {0}" -f $unplaced.Count
foreach ($quest in $unplaced) {
    $map = Get-PrimaryMap $quest.id
    $where = if ($map) { "map $map $($mapName[$map])" } else { 'no map point' }
    "  {0} {1} ({2}, type {3}, level {4})" -f $quest.id, $quest.name, $where, $quest.type, $quest.level
}

if ($WhatIf) { return }
Save-QuestData (@($records) + $added.ToArray()) $DataDir $AddonDir
"Added {0} quests to the end of quests.jsonl" -f $added.Count
