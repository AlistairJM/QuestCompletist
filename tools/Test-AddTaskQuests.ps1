<#
Checks Add-TaskQuests.ps1 in a scratch folder: nothing in the checkout is touched and nothing is downloaded.

  A  A made-up task table and a few made-up quests, with the checkout's own category, menu and
     profession tables: which rows are skipped and why (present, hidden by the tracking flag, by
     QuestInfo 265 or by the title, no title, internal names), the type, faction, race, class,
     profession, level, zone and category of every added row, the holiday and category its namesakes
     give it, that old rows stay byte for byte, that new ones go at the end in ID order and pass the
     record checks, that the Lua matches, that -WhatIf writes nothing and that a second run adds
     nothing and changes no byte. Its quest cache holds 1 of the 14 quests, so the run warns that
     it looks partial.
  B  The real table (tools\QuestV2CliTask.csv and the tables beside it, in -ToolsDir) against a scratch
     copy of the checkout's data: nothing is left to add, then every 25th task quest of the data is
     taken out and the tool must bring back exactly those, once, at the end, valid, with the pins
     untouched, and a second run must change nothing. Skipped, with a line saying so, when the tables
     aren't there (they are only in the main checkout).

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-AddTaskQuests.ps1 [-ToolsDir <folder>] [-MadeUpOnly]

-MadeUpOnly runs A alone, which takes about half a minute; with both it takes about a minute and a half.

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param([string]$ToolsDir = $PSScriptRoot, [switch]$MadeUpOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
$Tool = Join-Path $PSScriptRoot 'Add-TaskQuests.ps1'
$AddonSource = Join-Path $PSScriptRoot '..\QuestCompletist'
$DataSource = Join-Path $PSScriptRoot '..\data'
$Passed = 0; $Failed = 0; $Skipped = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Invoke-Tool([string[]]$arguments) {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Tool @arguments 2>&1
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Text = (($output | ForEach-Object { "$_" }) -join "`n") }
}
function Get-Hash([string]$path) { return (Get-FileHash $path -Algorithm SHA256).Hash }
function New-Folder([string]$path) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
function Write-Csv([string]$path, $rows) { $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8 }
function Read-Quests([string]$dir) { return @(Read-QuestData $dir) }
function Quest-Row([int]$id, [string]$name, [int]$level, [string]$zone, [int]$category, [int]$type, [int]$holiday = 0) {
    $q = [pscustomobject][ordered]@{ id = $id; name = $name; level = $level; zone = $zone; category = $category; type = $type; faction = 3; race = 67108863; class = 8191 }
    if ($holiday) { Set-RecordField $q 'holiday' $holiday }
    return $q
}
function Copy-Addon([string]$to, [string[]]$files) {
    New-Folder $to
    foreach ($file in $files) { Copy-Item (Join-Path $AddonSource $file) $to }
}
function Build-Lua([string]$dataDir, [string]$addonDir) {
    $built = Invoke-AddonDataBuild $dataDir $addonDir
    if (-not $built.Ok) { throw ("The scratch Lua didn't build:`n" + ($built.Lines -join "`n")) }
}
function Assert-Sound([string]$label, [string]$dataDir, [string]$addonDir) {
    $problems = @(Test-QuestRecords (Read-Quests $dataDir))
    Equal $problems.Count 0 "${label}: every record passes Test-QuestRecords ($($problems -join '; '))"
    Check (Invoke-AddonDataBuild $dataDir $addonDir -Check).Ok "${label}: qcQuestData.lua matches the data"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("add-task-quests-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Folder $Scratch

try {
    # --- A: a made-up table -------------------------------------------------------------------------
    $tools = "$Scratch\tools"; $data = "$Scratch\data"; $addon = "$Scratch\addon"
    New-Folder $tools; New-Folder $data
    Copy-Addon $addon 'qcCore.lua', 'qcQuest.lua', 'qcMenu.lua', 'qcPinDB.lua', 'qcQuestData.lua'

    $quests = @(
        (Quest-Row 1001 'Existing World One' 30 'Elwynn Forest' 70 128), (Quest-Row 1002 'Existing World Two' 30 'Elwynn Forest' 70 128),
        (Quest-Row 1003 'Existing World Three' 50 'Elwynn Forest' 70 128), (Quest-Row 1004 'Existing Bonus One' 20 'Durotar' 64 1),
        (Quest-Row 1005 'Existing Bonus Two' 40 'Durotar' 64 1), (Quest-Row 1006 'Existing Tracker' 10 'Durotar' 64 1),
        (Quest-Row 2001 'Cache Quest' 55 'Elwynn Forest' 70 1),
        (Quest-Row 2101 'Twin Quest' 12 'Elwynn Forest' 70 1), (Quest-Row 2102 'Twin Quest' 12 'Elwynn Forest' 70 1), (Quest-Row 2103 'Lone Quest' 12 'Durotar' 64 1),
        (Quest-Row 2201 'Fire Dance' 1 'Midsummer' 133 64 256), (Quest-Row 2202 'Fire Dance' 1 'Midsummer' 133 64 256),
        (Quest-Row 2301 'Work Day' 0 'Elwynn Forest' 70 1 4096), (Quest-Row 2302 'Work Day' 0 'Durotar' 64 1 4096)
    )
    [IO.File]::WriteAllText("$data\quests.jsonl", (ConvertTo-QuestJsonLines $quests), $script:Utf8)
    [IO.File]::WriteAllText("$data\pins.jsonl", '{"map":84,"icon":1,"name":"Somebody","x":1.5,"y":2.5,"quests":[1001]}' + "`n", $script:Utf8)
    Build-Lua $data $addon

    $raceNames = 'Human', 'Orc', 'Dwarf', 'NightElf', 'Scourge', 'Tauren', 'Gnome', 'Troll', 'Goblin', 'BloodElf', 'Draenei', 'Worgen', 'Pandaren', 'VoidElf', 'Nightborne',
        'HighmountainTauren', 'LightforgedDraenei', 'DarkIronDwarf', 'MagharOrc', 'ZandalariTroll', 'KulTiran', 'Vulpera', 'Mechagnome', 'Dracthyr', 'EarthenDwarf', 'Harronir'
    Write-Csv "$tools\ChrRaces.csv" @(for ($i = 0; $i -lt $raceNames.Count; $i++) { [pscustomobject]@{ ID = $i + 1; ClientFileString = $raceNames[$i]; PlayableRaceBit = $i } })
    Write-Csv "$tools\QuestInfo.csv" @(
        [pscustomobject]@{ ID = 109; InfoName_lang = 'World Quest'; Profession = 0 }, [pscustomobject]@{ ID = 271; InfoName_lang = 'Calling Quest'; Profession = 0 },
        [pscustomobject]@{ ID = 265; InfoName_lang = 'Hidden Quest'; Profession = 0 }, [pscustomobject]@{ ID = 119; InfoName_lang = 'Herbalism World Quest'; Profession = 182 },
        [pscustomobject]@{ ID = 120; InfoName_lang = 'Mining World Quest'; Profession = 186 }, [pscustomobject]@{ ID = 85; InfoName_lang = 'Heroic'; Profession = 0 }
    )
    Write-Csv "$tools\SkillLine.csv" @(
        [pscustomobject]@{ ID = 182; ParentSkillLineID = 0 }, [pscustomobject]@{ ID = 186; ParentSkillLineID = 0 },
        [pscustomobject]@{ ID = 2000; ParentSkillLineID = 182 }, [pscustomobject]@{ ID = 9999; ParentSkillLineID = 0 }
    )
    Write-Csv "$tools\UiMap.csv" @(
        [pscustomobject]@{ Name_lang = 'Azeroth'; ID = 947; ParentUiMapID = 0; Type = 1 }, [pscustomobject]@{ Name_lang = 'Kalimdor'; ID = 12; ParentUiMapID = 947; Type = 2 },
        [pscustomobject]@{ Name_lang = 'Eastern Kingdoms'; ID = 13; ParentUiMapID = 947; Type = 2 }, [pscustomobject]@{ Name_lang = 'Durotar'; ID = 1; ParentUiMapID = 12; Type = 3 },
        [pscustomobject]@{ Name_lang = 'Elwynn Forest'; ID = 37; ParentUiMapID = 13; Type = 3 }
    )
    function Blob([int]$quest, [int]$map, [int]$times = 1) { return @(1..$times | ForEach-Object { [pscustomobject]@{ ID = 1; MapID = 0; UiMapID = $map; Flags = 0; NumPoints = 1; QuestID = $quest; ObjectiveIndex = 0; ObjectiveID = 0; PlayerConditionID = 0; NavigationPlayerConditionID = 0 } }) }
    Write-Csv "$tools\QuestPOIBlob.csv" @((Blob 3001 37 3) + (Blob 3001 1 1) + (Blob 3002 1) + (Blob 3009 1) + (Blob 3010 37))
    [IO.File]::WriteAllText("$tools\retail_quest_cache_test.jsonl", '{"id":2001,"title":"Cache Quest","contentTuning":800,"sort":1}' + "`n", $script:Utf8)

    $all = -1
    function Task([int]$id, [string]$title, [int]$info = 0, [int]$tuning = 0, [long]$f0 = 0, [long]$f1 = 0, [long]$classes = -1, [int]$skill = 0, [long]$lo = -1, [long]$hi = -1) {
        return [pscustomobject]@{ ID = $id; QuestTitle_lang = $title; QuestInfoID = $info; ContentTuningID = $tuning; Flags_0 = $f0; Flags_1 = $f1; FiltClasses = $classes; FiltMinSkillID = $skill; FiltRaceMasks_0 = $lo; FiltRaceMasks_1 = $hi }
    }
    $table = @(
        (Task 1001 'Existing World One (renamed by the client)' 109 500), (Task 1002 'Existing World Two' 109 500), (Task 1003 'Existing World Three' 109 500),
        (Task 1004 'Existing Bonus One' 0 600), (Task 1005 'Existing Bonus Two' 0 600), (Task 1006 'Existing Tracker' 0 900 0x400),
        (Task 3001 'Mapped Quest' 0 500), (Task 3002 'Durotar Quest' 0 600), (Task 3003 'Nowhere Quest' 0 700), (Task 3004 'Prey: Moonlit Hunt' 0 700),
        (Task 3005 'Twin Quest' 0 700), (Task 3006 'Lone Quest' 0 700), (Task 3007 'Fire Dance' 0 700), (Task 3008 'Fire Dance' 0 700 0x1000),
        (Task 3009 'Work Day' 0 700), (Task 3010 'Cache Level Quest' 0 800),
        (Task 4001 'Flagged Tracker' 0 500 0x400), (Task 4002 'Hidden By Kind' 265 500), (Task 4003 'Tracking Quest' 0 500), (Task 4004 '' 0 500),
        (Task 4005 '[DNT] Thing' 0 500), (Task 4006 'Test Quest' 0 500), (Task 4007 'Greatest Hits' 0 500),
        (Task 5001 'Weekly Thing' 0 500 0x8000), (Task 5002 'Daily By Flag' 0 500 0x1000), (Task 5003 'Daily By Ex Flag' 0 500 0 0x8000),
        (Task 5004 'A World Quest' 109 500), (Task 5005 'A Calling' 271 500), (Task 5006 'Plain' 0 500), (Task 5007 'Weekly And Daily' 0 500 0x9000),
        (Task 5008 'Daily World Quest' 109 500 0x1000), (Task 5009 'Heroic Thing' 85 500),
        (Task 5101 'Alliance Only' 0 500 0 0 -1 0 1 0), (Task 5102 'Horde Only' 0 500 0 0 -1 0 2 0), (Task 5103 'Both Factions' 0 500 0 0 -1 0 3 0),
        (Task 5104 'Neutral Only' 0 500 0 0 -1 0 4096 0), (Task 5105 'Shaman Only' 0 500 0 0 64), (Task 5106 'Every Class' 0 500 0 0 8191),
        (Task 5201 'Herb Kind' 119 500), (Task 5202 'Herb Skill' 0 500 0 0 -1 2000), (Task 5203 'Skill And Kind Disagree' 120 500 0 0 -1 2000), (Task 5204 'Skill Without Profession' 0 500 0 0 -1 9999)
    )
    Write-Csv "$tools\QuestV2CliTask.csv" $table

    $dataBefore = [IO.File]::ReadAllLines("$data\quests.jsonl")
    $hashes = @{ Quests = Get-Hash "$data\quests.jsonl"; Lua = Get-Hash "$addon\qcQuestData.lua"; Pins = Get-Hash "$data\pins.jsonl" }

    $dry = Invoke-Tool @('-ToolsDir', $tools, '-DataDir', $data, '-AddonDir', $addon, '-WhatIf')
    Equal $dry.Exit 0 "A1: -WhatIf succeeds ($($dry.Text))"
    Check ($dry.Text -match 'Task table: 42 rows') "A1: it reads every row of the table"
    Check ($dry.Text -match 'already in the data: 6\b') "A1: six rows are in the data already, the one the table calls a tracker among them"
    Check ($dry.Text -match 'hidden trackers, skipped: 3 \(tracking flag 1, QuestInfo 265 1, titled Tracking Quest 1\)') "A1: a tracker by flag, by kind and by title"
    Check ($dry.Text -match 'no title, skipped: 1\b') "A1: a row with no title"
    Check ($dry.Text -match 'internal names, skipped: 2\b') "A1: two internal names"
    Check ($dry.Text -match '\[DNT\] Thing' -and $dry.Text -match 'Test Quest') "A1: and it lists them"
    Check ($dry.Text -match 'to add: 30\b' -and $dry.Text -match 'Rows to add: 30\b') "A1: 42 rows less 6, 3, 1 and 2 is 30 to add ($($dry.Text))"
    Check ($dry.Text -match 'WARNING: retail_quest_cache_test\.jsonl looks partial, with under 90% of the quests it should hold: 1 of our 14 \(7[.,]1%\)\.') "A1: a quest cache with 1 of our 14 quests is warned about ($($dry.Text))"
    Equal (Get-Hash "$data\quests.jsonl") $hashes.Quests 'A1: -WhatIf leaves quests.jsonl alone'
    Equal (Get-Hash "$addon\qcQuestData.lua") $hashes.Lua 'A1: and the Lua'

    $run = Invoke-Tool @('-ToolsDir', $tools, '-DataDir', $data, '-AddonDir', $addon)
    Equal $run.Exit 0 "A2: the run succeeds ($($run.Text))"
    $after = [IO.File]::ReadAllLines("$data\quests.jsonl")
    Equal $after.Count ($dataBefore.Count + 30) 'A2: 30 rows were added'
    $same = $true; for ($i = 0; $i -lt $dataBefore.Count; $i++) { if ($after[$i] -cne $dataBefore[$i]) { $same = $false } }
    Check $same 'A2: the old rows are byte for byte as they were, and so is their order'
    Equal (Get-Hash "$data\pins.jsonl") $hashes.Pins 'A2: the pins are untouched'
    Assert-Sound 'A2' $data $addon
    $now = Read-Quests $data
    $new = @($now | Select-Object -Skip $dataBefore.Count)
    Equal (($new | ForEach-Object { $_.id }) -join ',') ((($new | ForEach-Object { $_.id } | Sort-Object { [int]$_ }) -join ',')) 'A2: the new rows are in ID order'
    $byId = @{}; foreach ($q in $now) { $byId[[int]$q.id] = $q }
    function Field([int]$id, [string]$field) { return $byId[$id].$field }

    foreach ($id in 4001, 4002, 4003, 4004, 4005, 4006) { Check (-not ($new | Where-Object { $_.id -eq $id })) "A3: $id is not added" }
    Equal $byId[1001].name 'Existing World One' 'A3: a quest already in the data keeps its name, whatever the table says'
    Check ($null -ne $byId[4007]) 'A3: a title that merely contains "test" is added (Greatest Hits)'
    Equal (Field 4007 'name') 'Greatest Hits' 'A3: with the client title'

    Equal (Field 5001 'type') 128 'A4: a weekly flag is type 128'
    Equal (Field 5002 'type') 4 'A4: a daily flag is type 4'
    Equal (Field 5003 'type') 4 'A4: and so is the flag the cache calls flagsEx'
    Equal (Field 5004 'type') 128 'A4: a world quest kind is type 128'
    Equal (Field 5005 'type') 4 'A4: a Calling Quest is type 4'
    Equal (Field 5006 'type') 1 'A4: anything else is type 1'
    Equal (Field 5007 'type') 128 'A4: weekly wins over daily'
    Equal (Field 5008 'type') 4 'A4: a daily flag wins over the world quest kind'
    Equal (Field 5009 'type') 1 'A4: a Heroic quest without a flag is type 1'

    Equal (Field 5101 'faction') 1 'A5: an Alliance-only mask is faction 1'
    Equal (Field 5101 'race') 64175181 'A5: with the Alliance races'
    Equal (Field 5102 'faction') 2 'A5: a Horde-only mask is faction 2'
    Equal (Field 5102 'race') 61658034 'A5: with the Horde races'
    Equal (Field 5103 'faction') 3 'A5: Human and Orc together are neither'
    Equal (Field 5103 'race') 3 'A5: and keep their own mask'
    Equal (Field 5104 'faction') 3 'A5: a neutral race is neither'
    Equal (Field 5104 'race') 4096 'A5: and keeps its bit'
    Equal (Field 5006 'faction') 3 'A5: no mask is both factions'
    Equal (Field 5006 'race') 67108863 'A5: and every race'
    Equal (Field 5006 'class') 8191 'A5: and every class'
    Equal (Field 5105 'class') 64 'A5: a class mask is kept'
    Equal (Field 5106 'class') 8191 'A5: every class is no restriction'

    Equal (Field 5201 'profession') 256 'A6: a quest kind with a profession gives its bit'
    Equal (Field 5202 'profession') 256 'A6: a skill line gives its parent profession'
    Check ($null -eq (Field 5203 'profession')) 'A6: a skill and a kind that disagree give none'
    Check ($null -eq (Field 5204 'profession')) 'A6: a skill line with no profession gives none'
    Check ($null -eq (Field 5006 'profession')) 'A6: and a plain quest has none'

    Equal (Field 3001 'level') 30 'A7: the level is the commonest of the task quests of the tuning (30, 30 and 50)'
    Equal (Field 3002 'level') 20 'A7: the lowest of a tie (20 and 40)'
    Equal (Field 3003 'level') 0 'A7: a tuning nothing of ours has is level 0'
    Equal (Field 3010 'level') 55 'A7: a tuning only the quest cache has takes its quest''s level'

    Equal (Field 3001 'zone') 'Elwynn Forest' 'A8: the zone is the map most of the points are on'
    Equal (Field 3001 'category') 70 'A8: Place-UncategorisedQuests.ps1 files it in that zone''s category'
    Equal (Field 3002 'zone') 'Durotar' 'A8: another map'
    Equal (Field 3002 'category') 64 'A8: another category'
    Equal (Field 3003 'zone') '' 'A8: no map point is no zone'
    Equal (Field 3003 'category') 0 'A8: and category 0'
    Equal (Field 3004 'category') 1514 'A8: a name that begins with a category and a colon is filed there'
    Equal (Field 3005 'category') 70 'A8: no place, but two namesakes in one category: that category'
    Equal (Field 3005 'zone') 'Elwynn Forest' 'A8: and their zone'
    Equal (Field 3006 'category') 0 'A8: one namesake is not enough'
    Equal (Field 3010 'category') 70 'A8: a map decides before a namesake'

    Equal (Field 3007 'holiday') 256 'A9: the holiday of namesakes that all share one'
    Equal (Field 3007 'category') 133 'A9: and their category'
    Equal (Field 3007 'zone') 'Midsummer' 'A9: and zone'
    Equal (Field 3007 'type') 64 'A9: a quest with no flag takes their type'
    Equal (Field 3008 'type') 4 'A9: but a daily flag is the client''s word'
    Equal (Field 3008 'holiday') 256 'A9: and the holiday still goes'
    Equal (Field 3009 'holiday') 4096 'A9: a holiday whose namesakes are filed in several categories'
    Equal (Field 3009 'category') 64 'A9: leaves the category to the map'
    Check ($null -eq (Field 3001 'holiday')) 'A9: no namesake, no holiday'

    $hashes.Quests = Get-Hash "$data\quests.jsonl"; $hashes.Lua = Get-Hash "$addon\qcQuestData.lua"
    $again = Invoke-Tool @('-ToolsDir', $tools, '-DataDir', $data, '-AddonDir', $addon)
    Equal $again.Exit 0 "A10: a second run succeeds ($($again.Text))"
    Check ($again.Text -match 'to add: 0\b') 'A10: it has nothing to add'
    Equal (Get-Hash "$data\quests.jsonl") $hashes.Quests 'A10: and changes no byte of quests.jsonl'
    Equal (Get-Hash "$addon\qcQuestData.lua") $hashes.Lua 'A10: or of the Lua'

    # --- B: the real table --------------------------------------------------------------------------
    $needed = 'QuestV2CliTask.csv', 'QuestInfo.csv', 'SkillLine.csv', 'QuestPOIBlob.csv', 'UiMap.csv', 'ChrRaces.csv'
    $missing = @($needed | Where-Object { -not (Test-Path (Join-Path $ToolsDir $_)) })
    if ($MadeUpOnly) {
        Write-Output 'B was not run (-MadeUpOnly)'
    } elseif ($missing.Count) {
        $Skipped++
        Write-Output "SKIPPED B: $ToolsDir lacks $($missing -join ', '), so the real-table checks were not run (pass -ToolsDir <the main checkout's tools folder>)"
    } else {
        $real = "$Scratch\real"; New-Folder "$real\data"
        Copy-Item "$DataSource\quests.jsonl", "$DataSource\pins.jsonl" "$real\data"
        Copy-Addon "$real\addon" 'qcCore.lua', 'qcQuest.lua', 'qcMenu.lua', 'qcPinDB.lua', 'qcQuestData.lua'
        Assert-Sound 'B0' "$real\data" "$real\addon"
        $hashes = @{ Quests = Get-Hash "$real\data\quests.jsonl"; Lua = Get-Hash "$real\addon\qcQuestData.lua" }
        $idle = Invoke-Tool @('-ToolsDir', $ToolsDir, '-DataDir', "$real\data", '-AddonDir', "$real\addon")
        Equal $idle.Exit 0 "B1: the run on the checkout's data succeeds ($($idle.Text))"
        Check ($idle.Text -match 'to add: 0\b') 'B1: the checkout holds every task quest the table lists, bar the skipped ones'
        Equal (Get-Hash "$real\data\quests.jsonl") $hashes.Quests 'B1: and the run changes no byte of quests.jsonl'
        Equal (Get-Hash "$real\addon\qcQuestData.lua") $hashes.Lua 'B1: or of the Lua'

        $present = @{}; foreach ($q in (Read-Quests "$real\data")) { $present[[int]$q.id] = $true }
        $internal = [regex]'\[DNT\]|<DNT>|\(DNT\)|\bDNT\b|\bTBD\b|NOT USED|\[NYI\]|\[internal only\]|REUSE THIS RECORD|\[RNM\]|\[PH\]|\bTest\b|\bTesting\b|\bPlaceholder\b|\bDEPRECATED\b'
        $eligible = @(Import-Csv (Join-Path $ToolsDir 'QuestV2CliTask.csv') -Encoding UTF8 | Where-Object {
                $present.ContainsKey([int]$_.ID) -and -not ([long]$_.Flags_0 -band 0x400) -and [int]$_.QuestInfoID -ne 265 -and $_.QuestTitle_lang -cne 'Tracking Quest' -and
                $_.QuestTitle_lang -and -not $internal.IsMatch($_.QuestTitle_lang) })
        Check ($eligible.Count -gt 1000) "B2: the data holds many task quests the tool would add ($($eligible.Count))"
        $taken = @{}; for ($i = 0; $i -lt $eligible.Count; $i += 25) { $taken[[int]$eligible[$i].ID] = $true }
        $kept = @(Read-Quests "$real\data" | Where-Object { -not $taken.ContainsKey([int]$_.id) })
        Save-QuestData $kept "$real\data" "$real\addon" | Out-Null
        $keptLines = [IO.File]::ReadAllLines("$real\data\quests.jsonl")
        $hashes = @{ Pins = Get-Hash "$real\data\pins.jsonl" }
        $back = Invoke-Tool @('-ToolsDir', $ToolsDir, '-DataDir', "$real\data", '-AddonDir', "$real\addon")
        Equal $back.Exit 0 "B3: the run after taking $($taken.Count) task quests out succeeds ($($back.Text))"
        Check ($back.Text -match "Rows to add: $($taken.Count)\b") "B3: it adds exactly $($taken.Count)"
        $afterLines = [IO.File]::ReadAllLines("$real\data\quests.jsonl")
        Equal $afterLines.Count ($keptLines.Count + $taken.Count) 'B3: and the file grows by that many'
        $same = $true; for ($i = 0; $i -lt $keptLines.Count; $i++) { if ($afterLines[$i] -cne $keptLines[$i]) { $same = $false; break } }
        Check $same 'B3: the rows that were there are byte for byte as they were'
        $returned = @(Read-Quests "$real\data" | Select-Object -Skip $keptLines.Count | ForEach-Object { [int]$_.id })
        Equal (($returned | Sort-Object) -join ',') ((($taken.Keys | Sort-Object { [int]$_ }) -join ',')) 'B3: the quests brought back are the ones taken out'
        Equal ($returned -join ',') ((($returned | Sort-Object) -join ',')) 'B3: in ID order'
        Equal (Get-Hash "$real\data\pins.jsonl") $hashes.Pins 'B3: the pins are untouched'
        Assert-Sound 'B3' "$real\data" "$real\addon"
        $hashes = @{ Quests = Get-Hash "$real\data\quests.jsonl"; Lua = Get-Hash "$real\addon\qcQuestData.lua" }
        $twice = Invoke-Tool @('-ToolsDir', $ToolsDir, '-DataDir', "$real\data", '-AddonDir', "$real\addon")
        Check ($twice.Exit -eq 0 -and $twice.Text -match 'to add: 0\b') 'B4: a second run has nothing to add'
        Equal (Get-Hash "$real\data\quests.jsonl") $hashes.Quests 'B4: and changes no byte of quests.jsonl'
        Equal (Get-Hash "$real\addon\qcQuestData.lua") $hashes.Lua 'B4: or of the Lua'
    }
} finally {
    if (Test-Path $Scratch) { Remove-Item $Scratch -Recurse -Force }
}

Write-Output "$Passed checks passed, $Failed failed$(if ($Skipped) { ", $Skipped part skipped" })"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
