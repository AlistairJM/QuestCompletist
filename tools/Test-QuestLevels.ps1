<#
Checks Apply-QuestMinLevels.ps1, Compare-QuestLevels.ps1 and QuestLevels.ps1 on quests, API records, a
quest cache, a task table and a ContentTuning table made here, in a scratch folder: nothing in the
checkout is read or written (but the scripts themselves) and nothing is downloaded. One world holds a
quest for each way a minimum can come out: the API's and the formula's, an API record with no minimum,
tuning 0 (no minLevel, a 0 held there taken away, an API minimum still used), no source, a 0 against a
1, a minLevel that stays, goes or changes, a tuning the table has no row for, an offset type nobody
knows, a tuning the API contradicts, and the cache's tuning against the task table's. The rest changes
one thing at a time: the formula's agreement against the thresholds,
-WhatIf and -Check, a second run, quests added later, the baseline of Compare-QuestLevels.ps1, the
download of the table, and a quest cache that looks partial (QuestCacheFiles.ps1's warning against the
build before's cache and our data, and -UpdateBaseline refused unless -AcceptPartialCache).

The last section runs the same tools on the real files, when they are there: -RealToolsDir (this
folder by default) with the API cache, the quest cache, the task table and a ContentTuning table. It
copies the checkout's data into the scratch folder, takes every minLevel out, applies, and checks that
the formula holds, that only minLevel fields are added, none on tuning 0, and that a second run changes
nothing. It says whether the result is the checkout's own data.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-QuestLevels.ps1 [-RealToolsDir <tools folder with the data>]

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param([string]$RealToolsDir = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$savedCulture = [Threading.Thread]::CurrentThread.CurrentCulture
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
. "$PSScriptRoot\QuestLevels.ps1"
$Apply = Join-Path $PSScriptRoot 'Apply-QuestMinLevels.ps1'
$Compare = Join-Path $PSScriptRoot 'Compare-QuestLevels.ps1'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Has([string]$text, [string]$part, [string]$message) {
    Check ($text.Contains($part)) "$message (no '$part' in: $text)"
}
function Lacks([string]$text, [string]$part, [string]$message) {
    Check (-not $text.Contains($part)) "$message ('$part' is in: $text)"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("quest-levels-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$Build = '12.1.0.69933'
$TuningHeader = 'ID,Flags,ExpansionID,HPScalingCurveID,DMGScalingCurveID,HPPrimaryStatScalingCurveID,DMGPrimaryStatScalingCurveID,PrimaryStatScalingModPlayerDataElementCharacterID,PrimaryStatScalingModPlayerDataElementCharacterMultiplier,MinLevelSquish,MaxLevelSquish,MinLevelScalingOffset,MaxLevelScalingOffset,AllowedMinOffset,AllowedMaxOffset,LfgMinLevel,LfgMaxLevel,ILevel,XpMultQuest'

function New-Tuning([int]$id, [int]$minSquish, [int]$minOffset, [int]$allowedMin = 0) {
    return "$id,0,0,0,0,0,0,0,0,$minSquish,30,$minOffset,0,$allowedMin,0,0,0,0,1"
}

# The made-up table: a tuning for each way the formula can read a row.
$Tunings = @(
    (New-Tuning 10 10 0), (New-Tuning 11 0 1), (New-Tuning 12 0 2), (New-Tuning 13 0 3),
    (New-Tuning 14 5 0 -2), (New-Tuning 15 -1 2), (New-Tuning 16 0 0), (New-Tuning 17 7 9), (New-Tuning 18 20 0), (New-Tuning 19 255 0))

function New-Quest([int]$level, $api, $cache, $task, $minLevel = $null) {
    return @{ Level = $level; Api = $api; Cache = $cache; Task = $task; MinLevel = $minLevel }
}

# Api: $null = no record (a .404), 'none' = a record with no minimum, a number = its minimum.
function New-World {
    $q = @{}
    $q[1] = New-Quest 10 10 10 $null
    $q[2] = New-Quest 30 1 11 $null
    $q[3] = New-Quest 1 15 $null $null
    $q[4] = New-Quest 5 'none' 10 $null
    $q[5] = New-Quest 20 $null 10 $null
    $q[6] = New-Quest 90 $null $null 12
    $q[7] = New-Quest 50 $null 0 $null
    $q[8] = New-Quest 0 $null 0 $null
    $q[9] = New-Quest 20 $null $null $null 7
    $q[10] = New-Quest 0 1 11 $null
    $q[11] = New-Quest 1 $null 0 $null
    $q[12] = New-Quest 40 40 $null $null 25
    $q[13] = New-Quest 40 12 $null $null 12
    $q[14] = New-Quest 40 14 $null $null 12
    $q[15] = New-Quest 60 $null $null 13
    $q[16] = New-Quest 10 $null 11 10
    $q[17] = New-Quest 50 $null 17 $null
    $q[18] = New-Quest 50 $null 99 $null
    $q[19] = New-Quest 10 5 14 $null
    $q[20] = New-Quest 50 $null 15 $null
    $q[21] = New-Quest 3 $null 16 $null
    $q[22] = New-Quest 22 22 18 $null
    $q[23] = New-Quest 50 $null 18 $null
    $q[24] = New-Quest 80 90 12 $null
    $q[25] = New-Quest 75 80 13 $null
    $q[26] = New-Quest 45 $null 19 $null
    $q[27] = New-Quest 35 $null 0 $null 0
    $q[28] = New-Quest 20 'none' 0 $null
    $q[29] = New-Quest 30 12 0 $null
    for ($id = 1000; $id -lt 1120; $id++) { $q[$id] = New-Quest 10 10 10 $null }
    return $q
}

function New-ApiRecord([int]$id, $api) {
    $json = '{"_links":{"self":{"href":"https://us.api.blizzard.com/data/wow/quest/' + $id + '?namespace=static-12.1.0_68914-us"}},"id":' + $id + ',"title":"Quest ' + $id + '"'
    if ($api -eq 'none') { return $json + ',"requirements":{"faction":{"type":"HORDE","name":"Horde"}},"rewards":{"experience":100}}' }
    return $json + ',"requirements":{"min_character_level":' + $api + ',"max_character_level":90},"rewards":{"experience":100}}'
}

function Write-World([string]$name, $quests, [string[]]$table = $null) {
    if (-not $table) { $table = $Tunings }
    $dir = Join-Path $Scratch $name
    New-Item -ItemType Directory "$dir\tools\quest_api_cache", "$dir\data", "$dir\addon" -Force | Out-Null
    $data = @(); $cache = @(); $task = @('ID,QuestTitle_lang,ContentTuningID')
    foreach ($id in ($quests.Keys | Sort-Object)) {
        $q = $quests[$id]
        $line = '{"id":' + $id + ',"name":"Quest ' + $id + '","level":' + $q.Level + ',"zone":"Zone","category":1,"type":1,"faction":0,"race":0,"class":0'
        if ($null -ne $q.MinLevel) { $line += ',"minLevel":' + $q.MinLevel }
        $data += $line + '}'
        if ($null -eq $q.Api) { [IO.File]::WriteAllText("$dir\tools\quest_api_cache\$id.404", '', $utf8) }
        else { [IO.File]::WriteAllText("$dir\tools\quest_api_cache\$id.json", (New-ApiRecord $id $q.Api), $utf8) }
        if ($null -ne $q.Cache) { $cache += '{"id":' + $id + ',"title":"Quest ' + $id + '","contentTuning":' + $q.Cache + ',"sort":0,"questType":2}' }
        if ($null -ne $q.Task) { $task += "$id,Quest $id,$($q.Task)" }
    }
    [IO.File]::WriteAllText("$dir\data\quests.jsonl", (($data -join "`n") + "`n"), $utf8)
    [IO.File]::WriteAllText("$dir\data\pins.jsonl", '{"map":84,"icon":1,"npc":29611,"name":"A Pin","x":26.12,"y":47.32,"quests":[1]}' + "`n", $utf8)
    [IO.File]::WriteAllText("$dir\tools\retail_quest_cache_$Build.jsonl", (($cache -join "`n") + "`n"), $utf8)
    [IO.File]::WriteAllText("$dir\tools\QuestV2CliTask.csv", (($task -join "`n") + "`n"), $utf8)
    [IO.File]::WriteAllText("$dir\tools\ContentTuning-$Build.csv", ((@($TuningHeader) + $table) -join "`n") + "`n", $utf8)
    $result = Invoke-AddonDataBuild -DataDir "$dir\data" -AddonDir "$dir\addon"
    if (-not $result.Ok) { throw "The scratch world $name didn't build: $($result.Lines -join '; ')" }
    return $dir
}

function Invoke-Tool([string]$tool, [string]$dir, [hashtable]$more = @{}) {
    $params = @{ ToolsDir = "$dir\tools"; DataDir = "$dir\data" }
    if ($tool -eq $Apply) { $params.AddonDir = "$dir\addon"; $params.MinTested = 100 }
    else { $params.BaselineFile = "$dir\baseline.csv"; $params.MinTested = 100 }
    foreach ($k in $more.Keys) { $params[$k] = $more[$k] }
    $global:LASTEXITCODE = 0
    $failure = ''
    $lines = @()
    try { $lines = @(& $tool @params *>&1 | ForEach-Object { "$_" }) } catch { $failure = $_.Exception.Message }
    if ($env:QUEST_LEVELS_TEST_VERBOSE) { Write-Host "---- run (exit $global:LASTEXITCODE) $failure"; $lines | ForEach-Object { Write-Host "     $_" } }
    return @{ Text = (($lines + $failure) -join "`n"); Exit = $global:LASTEXITCODE; Failure = $failure }
}

function Get-Hashes([string]$dir) {
    $hashes = @()
    foreach ($file in "data\quests.jsonl", "data\pins.jsonl", "addon\qcQuestData.lua", "addon\qcPinDB.lua") { $hashes += (Get-FileHash "$dir\$file").Hash }
    return $hashes -join ','
}

function Get-Records([string]$dir) {
    $records = @{}
    foreach ($line in [IO.File]::ReadAllLines("$dir\data\quests.jsonl")) { $r = $line | ConvertFrom-Json; $records[[int]$r.id] = $r }
    return $records
}

function Get-LuaMinLevels([string]$dir) {
    $text = [IO.File]::ReadAllText("$dir\addon\qcQuestData.lua")
    $block = [regex]::Match($text, '(?s)qcQuestMinLevel=\{\r?\n(.*?)\}').Groups[1].Value
    $entries = @{}
    foreach ($m in [regex]::Matches($block, '\[(\d+)\]=(\d+),')) { $entries[[int]$m.Groups[1].Value] = [int]$m.Groups[2].Value }
    return $entries
}

# --- The formula, one row at a time -----------------------------------------------------------------
$formulaDir = Join-Path $Scratch 'formula'
New-Item -ItemType Directory $formulaDir | Out-Null
[IO.File]::WriteAllText("$formulaDir\ContentTuning-$Build.csv", ((@($TuningHeader) + $Tunings) -join "`n") + "`n", $utf8)
$read = Read-ContentTuning "$formulaDir\ContentTuning-$Build.csv"
Equal $read[10].Minimum 10 'T1: type 0 is the squish value'
Equal $read[11].Minimum 1 'T1: type 1 adds 1 to 0'
Equal $read[12].Minimum 90 'T1: type 2 is the level cap'
Equal $read[13].Minimum 80 'T1: type 3 is the cap before it'
Equal $read[14].Minimum 5 'T1: AllowedMinOffset is not part of it'
Equal $read[15].Minimum 89 'T1: a squish value of -1 on the cap is 89'
Equal $read[16].Minimum 0 'T1: a row with nothing is no minimum'
Check ($null -eq $read[17].Minimum) 'T1: a type nobody knows has no minimum'
Equal $read[17].Type 9 'T1: and keeps its type'
Equal $read[19].Minimum 255 'T1: a squish value of 255 is read as it is (Get-QuestMinimum refuses it as beyond the cap)'
Check ($null -eq (Get-WantedMinLevel 10 10)) 'T2: a minimum equal to the level is no entry'
Check ($null -eq (Get-WantedMinLevel 0 1)) 'T2: level 0 against minimum 1 is no entry'
Check ($null -eq (Get-WantedMinLevel 1 0)) 'T2: level 1 against minimum 0 is no entry'
Check ($null -eq (Get-WantedMinLevel 0 0)) 'T2: and 0 against 0'
Check ($null -eq (Get-WantedMinLevel 1 1)) 'T2: and 1 against 1'
Equal (Get-WantedMinLevel 30 1) 1 'T2: a minimum of 1 against a higher level is an entry'
Equal (Get-WantedMinLevel 50 0) 0 'T2: and so is a 0 against a higher level'
Equal (Get-WantedMinLevel 0 15) 15 'T2: and a minimum above a level of 0'
Equal (Get-WantedMinLevel 2 1) 1 'T2: level 2 against 1 is an entry'
Check ($null -eq (Get-WantedMinLevel 50 $null)) 'T2: no minimum known is no entry, whatever the level'
$m = Get-QuestMinimum 7 @{} @{ 7 = 0 } @{} $null
Equal $m.Source 'tuning0' 'T2: a quest on tuning 0 with no API minimum is tuning 0''s'
Check ($null -eq $m.Minimum) 'T2: and has no minimum, so its gate stays its level'
$m = Get-QuestMinimum 7 @{ 7 = 12 } @{ 7 = 0 } @{} $null
Equal $m.Source 'api' 'T2: an API minimum still decides on tuning 0'
Equal $m.Minimum 12 'T2: with its number'
Equal (Get-QuestGate ([pscustomobject]@{ level = 30; minLevel = 5 })) 5 'T2: the gate is the minLevel'
Equal (Get-QuestGate ([pscustomobject]@{ level = 30 })) 30 'T2: and else the level'
Equal (Get-QuestGate ([pscustomobject]@{ level = 30; minLevel = 0 })) 0 'T2: a 0 is a gate'

[IO.File]::WriteAllText("$formulaDir\bad.csv", "ID,MinLevelSquish,MaxLevelSquish,MinLevelScalingOffset`n1,5,30,0`n", $utf8)
$message = ''
try { Read-ContentTuning "$formulaDir\bad.csv" | Out-Null } catch { $message = $_.Exception.Message }
Has $message "no 'MaxLevelScalingOffset' column" 'T3: a table without a column the formula reads is refused, and the column named'

# --- The download of the table ----------------------------------------------------------------------
$downloadDir = Join-Path $Scratch 'download'
New-Item -ItemType Directory $downloadDir | Out-Null
$requested = New-Object System.Collections.Generic.List[string]
$good = { param($uri, $to) $requested.Add($uri); [IO.File]::WriteAllText($to, ((@($TuningHeader) + @(1..150 | ForEach-Object { New-Tuning $_ 5 0 })) -join "`n") + "`n", $utf8) }
$path = Get-ContentTuningFile $downloadDir $Build $false $good
Equal $path (Join-Path $downloadDir "ContentTuning-$Build.csv") 'D1: the table is saved as ContentTuning-<build>.csv'
Equal $requested[0] "https://wago.tools/db2/ContentTuning/csv?build=$Build" 'D1: from wago.tools, for the build'
Check (-not (Test-Path "$path.download")) 'D1: with no partial file left'
$before = $requested.Count
Get-ContentTuningFile $downloadDir $Build $false $good | Out-Null
Equal $requested.Count $before 'D2: a table that is there is not downloaded again'
Get-ContentTuningFile $downloadDir $Build $true $good | Out-Null
Equal $requested.Count ($before + 1) 'D2: unless -Refresh says so'
$held = [IO.File]::ReadAllText($path)
$shifted = { param($uri, $to) [IO.File]::WriteAllText($to, ((@('ID,MinLevel,MaxLevel') + @(1..150 | ForEach-Object { "$_,5,30" })) -join "`n") + "`n", $utf8) }
$message = ''
try { Get-ContentTuningFile $downloadDir $Build $true $shifted | Out-Null } catch { $message = $_.Exception.Message }
Has $message 'has no column MinLevelSquish' 'D3: a download without the formula''s columns is refused, naming them'
Equal ([IO.File]::ReadAllText($path)) $held 'D3: and the table that was there stays'
Check (-not (Test-Path "$path.download")) 'D3: with no partial file left'
$short = { param($uri, $to) [IO.File]::WriteAllText($to, ((@($TuningHeader) + @(1..5 | ForEach-Object { New-Tuning $_ 5 0 })) -join "`n") + "`n", $utf8) }
$message = ''
try { Get-ContentTuningFile $downloadDir $Build $true $short | Out-Null } catch { $message = $_.Exception.Message }
Has $message 'fewer than 100 rows' 'D4: a table with a handful of rows is refused'
$fresh = Join-Path $Scratch 'download-fresh'
New-Item -ItemType Directory $fresh | Out-Null
$message = ''
try { Get-ContentTuningFile $fresh $Build $false $shifted | Out-Null } catch { $message = $_.Exception.Message }
Has $message 'has no column' 'D5: a first download that is wrong is refused'
Check (-not (Test-Path "$fresh\ContentTuning-$Build.csv")) 'D5: and no table is saved'

# --- Apply, on the made-up world --------------------------------------------------------------------
$world = Write-World 'main' (New-World)
$beforeHashes = Get-Hashes $world
$beforeRecords = Get-Records $world
$r = Invoke-Tool $Apply $world @{ WhatIf = $true }
Equal $r.Exit 0 'A1: -WhatIf exits 0'
Equal (Get-Hashes $world) $beforeHashes 'A1: and writes nothing'
Has $r.Text '-WhatIf: nothing was written.' 'A1: and says so'
Has $r.Text 'tested against 127 quests that have an API minimum and a tuning' 'A2: the formula is tested on the 7 quests of the list that have both, and the 120 fillers'
Has $r.Text '126 agree (99.21%)  [ok]' 'A2: one quest, the one on tuning 18, disagrees, and 99.21% passes'
Has $r.Text 'differs: quest 22 on tuning 18 (offset type 0): formula 20, API 22' 'A2: and is named'
Has $r.Text 'offset type 0 (base 0): 123 tested, 122 agree' 'A2: each offset type has its line'
Has $r.Text 'offset type 3 (base 80): 1 tested, 1 agree' 'A2: the last of them too'
Has $r.Text 'not tested: 5 of the API''s 132 minimums (no tuning ID for 4, tuning 0 for 1, no row for 0, an unknown offset type for 0)' 'A2: and the API quests it could not test are counted, with why'
Has $r.Text 'the quest cache and the task table disagree on the tuning of 1 quests' 'A2: the one quest whose cache and task table differ is counted'
Has $r.Text 'Sources: the API for 132 quests, the client''s level range for 7, tuning 0 (no range: no minLevel, the gate is the level) for 5; 5 have neither and stay as they are (1 above the cap, 1 no record, 1 no row, 2 unverified).' 'A3: the sources, with the quests that have none and why'
Has $r.Text '129 quests already hold the minimum their sources give; 15 change: the gate is lowered for 6 and raised for 9.' 'A3: the changes by direction'
Has $r.Text 'from api: 8 (3 lowered, 5 raised); minLevel added 6, changed 1, removed 1' 'A4: those from the API, with what happens to the field'
Has $r.Text 'from tuning: 6 (3 lowered, 3 raised); minLevel added 6, changed 0, removed 0' 'A4: those from the formula'
Has $r.Text 'from tuning0: 1 (0 lowered, 1 raised); minLevel added 0, changed 0, removed 1' 'A4: and the one from tuning 0, whose 0 goes'
Has $r.Text '    27  level 35  gate 0 -> 35  tuning0  Quest 27' 'A4: an example line has the id, the level, the gate before and after, the source and the name'
Lacks $r.Text '    7  level 50' 'A4: a quest on tuning 0 with no minLevel is not changed'

$r = Invoke-Tool $Apply $world @{ Check = $true }
Equal $r.Exit 1 'A5: -Check exits 1 when the data is not what the sources say'
Equal (Get-Hashes $world) $beforeHashes 'A5: and writes nothing'
Has $r.Text 'The data isn''t what the sources say for 15 quests' 'A5: and says how many'

$r = Invoke-Tool $Apply $world
Equal $r.Exit 0 'A6: the run exits 0'
Has $r.Text 'Saved: 15 quests changed, 15 quests now hold a minLevel.' 'A6: 15 quests change; 15 hold a minLevel after (12 added, quest 14 changed, quests 9 and 13 kept, quests 12 and 27 removed)'
$after = Get-Records $world
$holding = @{ 2 = 1; 3 = 15; 4 = 10; 5 = 10; 9 = 7; 13 = 12; 14 = 14; 15 = 80; 16 = 1; 19 = 5; 20 = 89; 21 = 0; 24 = 90; 25 = 80; 29 = 12 }
foreach ($id in $holding.Keys) { Equal $after[$id].minLevel $holding[$id] "A7: quest $id holds minLevel $($holding[$id])" }
$holdingNone = 1, 6, 7, 8, 10, 11, 12, 17, 18, 22, 23, 26, 27, 28, 1000, 1119
foreach ($id in $holdingNone) { Check ($null -eq $after[$id].minLevel) "A7: quest $id holds no minLevel (has '$($after[$id].minLevel)')" }
Equal $after[17].level 50 'A8: a quest on a tuning nobody knows keeps its level'
Equal $after[26].level 45 'A8: and so does one on a tuning whose minimum is beyond the level cap (255 marks a quest nobody can take)'
Equal $after[9].minLevel 7 'A8: a minLevel on a quest with no source is left as it was'
Equal $after[16].minLevel 1 'A8: a quest in the cache and the task table on different tunings takes the cache''s (tuning 11, minimum 1)'
Equal $after[22].level 22 'A8: a quest the API gives 22 keeps it, though the formula says 20'
Check ($null -eq $after[7].minLevel -and $null -eq $after[27].minLevel -and $null -eq $after[28].minLevel) 'A8: a quest on tuning 0 with no API minimum holds no minLevel, and loses the 0 it held, so its gate is its level'
Equal $after[29].minLevel 12 'A8: one on tuning 0 with an API minimum takes the API''s'

$changedFields = 0
foreach ($id in $beforeRecords.Keys) {
    foreach ($field in 'id', 'name', 'level', 'zone', 'category', 'type', 'faction', 'race', 'class') {
        if ("$($beforeRecords[$id].$field)" -cne "$($after[$id].$field)") { $changedFields++ }
    }
}
Equal $changedFields 0 'A9: no field but minLevel changes'
Equal $after.Count $beforeRecords.Count 'A9: and no quest comes or goes'
Equal ((Get-Hashes $world).Split(',')[1]) $beforeHashes.Split(',')[1] 'A9: pins.jsonl is untouched'
Equal ((Get-Hashes $world).Split(',')[3]) $beforeHashes.Split(',')[3] 'A9: and so is qcPinDB.lua'
$lua = Get-LuaMinLevels $world
Equal $lua.Count 15 'A10: qcQuestMinLevel holds the 15 quests with a minLevel'
Equal $lua[21] 0 'A10: and keeps the 0 of a range whose minimum is 0'
Check (-not $lua.ContainsKey(7) -and -not $lua.ContainsKey(27)) 'A10: and has no entry for a quest on tuning 0 with no API minimum'
$built = Invoke-AddonDataBuild -DataDir "$world\data" -AddonDir "$world\addon" -Check
Check $built.Ok 'A10: the Lua matches the data'

$savedHashes = Get-Hashes $world
$r = Invoke-Tool $Apply $world
Equal $r.Exit 0 'A11: a second run exits 0'
Has $r.Text 'Nothing to change: every quest''s minLevel is what its sources say.' 'A11: and has nothing to change'
Equal (Get-Hashes $world) $savedHashes 'A11: the files are the same, byte for byte'
$r = Invoke-Tool $Apply $world @{ Check = $true }
Equal $r.Exit 0 'A11: -Check exits 0 then'

# --- Compare-QuestLevels.ps1 and its baseline -------------------------------------------------------
$r = Invoke-Tool $Compare $world
Equal $r.Exit 0 'C1: with no baseline and nothing different the run exits 0'
Has $r.Text 'No baseline file at' 'C1: and says so'
Has $r.Text '139 quests hold what their sources say, 0 do not (class D), 10 have no source (class N: 1 above the cap, 1 no record, 1 no row, 5 tuning 0, 2 unverified).' 'C1: the classes, and why the quests have no source (tuning 0 is none)'
Has $r.Text 'No quest that matched in the baseline differs now, and the formula reproduces the API.' 'C1: and ends well'
Check (-not (Test-Path "$world\baseline.csv")) 'C1: it writes no baseline unasked'
$r = Invoke-Tool $Compare $world @{ UpdateBaseline = $true }
Equal $r.Exit 0 'C2: -UpdateBaseline exits 0'
$bytes = [IO.File]::ReadAllBytes("$world\baseline.csv")
Check ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'C2: the baseline starts with a byte order mark, as the reputation baseline does'
$expectedBaseline = "`"Class`",`"QuestID`"`r`n" + ((7, 8, 9, 11, 17, 18, 23, 26, 27, 28 | ForEach-Object { "`"N`",`"$_`"`r`n" }) -join '')
Equal ([IO.File]::ReadAllText("$world\baseline.csv").TrimStart([char]0xFEFF)) $expectedBaseline 'C2: it lists the ten quests with no source, tuning 0''s five among them, by class and id'
$r = Invoke-Tool $Compare $world
Equal $r.Exit 0 'C3: with the baseline the run exits 0'
Has $r.Text 'N: 10 now, 10 in the baseline; 0 new, 0 gone' 'C3: and nothing is new'
Has $r.Text 'D: 0 now, 0 in the baseline; 0 new, 0 gone' 'C3: in either class'

$regress = Join-Path $Scratch 'regress'
Copy-Item $world $regress -Recurse
$text = [IO.File]::ReadAllText("$regress\data\quests.jsonl").Replace('{"id":1,"name":"Quest 1","level":10,', '{"id":1,"name":"Quest 1","level":20,')
[IO.File]::WriteAllText("$regress\data\quests.jsonl", $text, $utf8)
$r = Invoke-Tool $Compare $regress
Equal $r.Exit 1 'C4: a quest that matched in the baseline and does not now fails the run'
Has $r.Text 'D: 1 now, 0 in the baseline; 1 new, 0 gone' 'C4: it is the one new quest in class D'
Has $r.Text 'new: 1 Quest 1: gate 20, api says 10 (level 20)' 'C4: and is named, with the gate, the source and the level'
Has $r.Text 'FAILED: 1 quests are new in class D' 'C4: and the failure says why'
$r = Invoke-Tool $Compare $regress @{ UpdateBaseline = $true }
Equal $r.Exit 1 'C5: -UpdateBaseline still reports the run it records'
$r = Invoke-Tool $Compare $regress
Equal $r.Exit 0 'C5: and the next run, against the new baseline, passes'
Has $r.Text 'D: 1 now, 1 in the baseline; 0 new, 0 gone' 'C5: with the quest in the baseline'

$lost = Join-Path $Scratch 'lost'
Copy-Item $world $lost -Recurse
Remove-Item "$lost\tools\quest_api_cache\3.json"
[IO.File]::WriteAllText("$lost\tools\quest_api_cache\3.404", '', $utf8)
$r = Invoke-Tool $Compare $lost
Equal $r.Exit 0 'C6: a quest that loses its source is listed and does not fail the run'
Has $r.Text 'N: 11 now, 10 in the baseline; 1 new, 0 gone' 'C6: it is new in class N'
Has $r.Text 'new: 3 Quest 3: no source (no record): level 1, minLevel 15' 'C6: with its level and minLevel'

$gone = Join-Path $Scratch 'gone'
Copy-Item $world $gone -Recurse
[IO.File]::WriteAllText("$gone\tools\retail_quest_cache_$Build.jsonl", [IO.File]::ReadAllText("$gone\tools\retail_quest_cache_$Build.jsonl").Replace('"id":17,"title":"Quest 17","contentTuning":17', '"id":17,"title":"Quest 17","contentTuning":10'), $utf8)
[IO.File]::WriteAllText("$gone\data\quests.jsonl", [IO.File]::ReadAllText("$gone\data\quests.jsonl").Replace('{"id":17,"name":"Quest 17","level":50,', '{"id":17,"name":"Quest 17","level":10,'), $utf8)
$r = Invoke-Tool $Compare $gone
Equal $r.Exit 0 'C7: a quest that was in the baseline and has a source again is no failure'
Has $r.Text 'N: 9 now, 10 in the baseline; 0 new, 1 gone' 'C7: it is gone from class N'
$drift = Join-Path $Scratch 'drift'
Copy-Item $world $drift -Recurse
[IO.File]::WriteAllText("$drift\tools\ContentTuning-$Build.csv", ((@($TuningHeader) + @(10..18 | ForEach-Object { New-Tuning $_ 9 0 })) -join "`n") + "`n", $utf8)
$r = Invoke-Tool $Compare $drift
Equal $r.Exit 1 'C8: a table whose ranges the API contradicts fails the run'
Has $r.Text 'the formula no longer reproduces the API''s minimums' 'C8: and the failure says so'
[IO.File]::WriteAllText("$world\bad-baseline.csv", "`"Class`",`"QuestID`"`r`n`"X`",`"5`"`r`n", $utf8)
$r = Invoke-Tool $Compare $world @{ BaselineFile = "$world\bad-baseline.csv" }
Check ($r.Failure -ne '') 'C9: a baseline with a class that is not D or N stops the run'
Has $r.Failure "has class 'X', not D or N" 'C9: and says which'
$regain = Join-Path $Scratch 'regain'
Copy-Item $world $regain -Recurse
[IO.File]::WriteAllText("$regain\data\quests.jsonl", [IO.File]::ReadAllText("$regain\data\quests.jsonl").Replace('{"id":27,"name":"Quest 27","level":35,"zone":"Zone","category":1,"type":1,"faction":0,"race":0,"class":0}', '{"id":27,"name":"Quest 27","level":35,"zone":"Zone","category":1,"type":1,"faction":0,"race":0,"class":0,"minLevel":0}'), $utf8)
$r = Invoke-Tool $Compare $regain
Equal $r.Exit 1 'C10: a quest on tuning 0 that gets a minLevel again fails the run'
Has $r.Text 'D: 1 now, 0 in the baseline; 1 new, 0 gone' 'C10: it is new in class D'
Has $r.Text 'new: 27 Quest 27: gate 0, tuning0 says none (level 35)' 'C10: and is named, with the gate it should not have'
Has $r.Text 'N: 9 now, 10 in the baseline; 0 new, 1 gone' 'C10: and has left class N'

# --- Quests added later (the task quests of step 6) -------------------------------------------------
$oldLines = [IO.File]::ReadAllLines("$world\data\quests.jsonl")
$added = [IO.File]::ReadAllText("$world\data\quests.jsonl")
$added += '{"id":2001,"name":"New task","level":50,"zone":"Zone","category":1,"type":1,"faction":0,"race":0,"class":0}' + "`n"
$added += '{"id":2002,"name":"New task, right","level":10,"zone":"Zone","category":1,"type":1,"faction":0,"race":0,"class":0}' + "`n"
[IO.File]::WriteAllText("$world\data\quests.jsonl", $added, $utf8)
Invoke-AddonDataBuild -DataDir "$world\data" -AddonDir "$world\addon" | Out-Null
[IO.File]::WriteAllText("$world\tools\QuestV2CliTask.csv", ([IO.File]::ReadAllText("$world\tools\QuestV2CliTask.csv") + "2001,New task,10`n2002,New task right,10`n"), $utf8)
$r = Invoke-Tool $Compare $world
Equal $r.Exit 1 'L1: the check finds the new quest that is not as its source says'
Has $r.Text 'new: 2001 New task: gate 50, tuning says 10 (level 50)' 'L1: and names it'
$r = Invoke-Tool $Apply $world
Equal $r.Exit 0 'L2: a rerun after quests are added exits 0'
Has $r.Text 'Saved: 1 quests changed, 16 quests now hold a minLevel.' 'L2: and changes only the one that needs it'
$newLines = [IO.File]::ReadAllLines("$world\data\quests.jsonl")
$kept = 0
for ($i = 0; $i -lt $oldLines.Count; $i++) { if ($oldLines[$i] -ceq $newLines[$i]) { $kept++ } }
Equal $kept $oldLines.Count 'L2: every earlier line is as it was'
Has $newLines[$newLines.Count - 2] ',"minLevel":10}' 'L2: the new quest on tuning 10 holds its minimum'
Check (-not $newLines[$newLines.Count - 1].Contains('minLevel')) 'L2: the one whose minimum is its level holds none'
$r = Invoke-Tool $Compare $world
Equal $r.Exit 0 'L3: and the check passes again'

# --- The formula against the thresholds -------------------------------------------------------------
$more = New-World
$more[900] = New-Quest 22 22 18 $null
$failWorld = Write-World 'fail' $more
$failHashes = Get-Hashes $failWorld
$r = Invoke-Tool $Apply $failWorld
Equal $r.Exit 1 'F1: two disagreements in 128 (98.44%) fail the run'
Has $r.Text '[FAILED]' 'F1: the formula line says so'
Has $r.Text 'nothing was changed' 'F1: and nothing is'
Equal (Get-Hashes $failWorld) $failHashes 'F1: the files are as they were'
$r = Invoke-Tool $Apply $failWorld @{ MinAgreement = 0.98; WhatIf = $true }
Equal $r.Exit 0 'F2: with -MinAgreement 0.98 the same run passes'
$r = Invoke-Tool $Apply $world @{ MinTested = 200; WhatIf = $true }
Equal $r.Exit 1 'F3: fewer quests tested than -MinTested fail the run'
Has $r.Text 'only 127 tested, fewer than -MinTested 200' 'F3: and it says why'
$r = Invoke-Tool $Apply $world @{ MinTested = 20000; WhatIf = $true }
Equal $r.Exit 1 'F4: so does the default of 20,000, for a world this small'
$shiftWorld = Write-World 'shift' (New-World) @(10..18 | ForEach-Object { New-Tuning $_ 9 0 })
$shiftHashes = Get-Hashes $shiftWorld
$r = Invoke-Tool $Apply $shiftWorld
Equal $r.Exit 1 'F5: a table that gives the tunings other ranges fails the run'
Equal (Get-Hashes $shiftWorld) $shiftHashes 'F5: and nothing is written'

# A tuning the API contradicts is not used for the quests it has no record of; the rest of its type is.
$r = Invoke-Tool $Apply (Write-World 'bad-tuning' (New-World)) @{ WhatIf = $true }
Has $r.Text '2 unverified' 'F6: the two quests on tunings the formula can''t vouch for (17: an unknown type, 23: tuning 18, which the API contradicts)'

# An offset type no API quest has confirmed gives nothing, though the formula knows its base.
$only = @{}
for ($id = 1000; $id -lt 1120; $id++) { $only[$id] = New-Quest 10 10 10 $null }
$only[30] = New-Quest 50 $null 12 $null
$r = Invoke-Tool $Apply (Write-World 'unconfirmed' $only) @{ WhatIf = $true }
Has $r.Text '1 have neither and stay as they are (1 unverified).' 'F7: a quest on a type-2 tuning, when only type 0 has been tested against the API, is left as it is'
Has $r.Text 'Nothing to change' 'F7: and nothing changes'

# --- A table with a column gone -----------------------------------------------------------------------
$noColumn = Write-World 'no-column' (New-World)
$header = $TuningHeader.Replace('MinLevelSquish', 'MinLevelOther')
[IO.File]::WriteAllText("$noColumn\tools\ContentTuning-$Build.csv", ((@($header) + $Tunings) -join "`n") + "`n", $utf8)
$noColumnHashes = Get-Hashes $noColumn
$r = Invoke-Tool $Apply $noColumn
Check ($r.Failure -ne '') 'G1: a table that lacks a column the formula reads stops the run'
Has $r.Failure "no 'MinLevelSquish' column" 'G1: naming it'
Equal (Get-Hashes $noColumn) $noColumnHashes 'G1: and nothing is written'

# --- A quest cache that looks partial (QuestCacheFiles.ps1) ---------------------------------------------------
function Write-Cache([string]$dir, [string]$file, $ids) {
    New-Item -ItemType Directory $dir -Force | Out-Null
    [IO.File]::WriteAllText("$dir\$file", ((@($ids | ForEach-Object { '{"id":' + $_ + ',"title":"Quest ' + $_ + '","contentTuning":10,"sort":0,"questType":2}' }) -join "`n") + "`n"), $utf8)
    return "$dir\$file"
}
$sizeDir = Join-Path $Scratch 'cache-size'
$newest = Write-Cache $sizeDir 'retail_quest_cache_12.1.5.70391.jsonl' (1..90)
Equal @(Get-QuestCacheWarning $newest).Count 0 'K1: a cache with no build before it, and no data given, is not warned about'
$null = Write-Cache $sizeDir 'retail_quest_cache_12.1.0.69933.jsonl' (1..100)
Equal @(Get-QuestCacheWarning $newest).Count 0 'K1: nor one with 90 of the 100 quests of the build before: 90% is enough'
$newest = Write-Cache $sizeDir 'retail_quest_cache_12.1.5.70391.jsonl' (1..89)
$w = @(Get-QuestCacheWarning $newest)
Equal $w.Count 2 'K2: 89 of them is warned about, in two lines'
Equal $w[0] 'WARNING: retail_quest_cache_12.1.5.70391.jsonl looks partial, with under 90% of the quests it should hold: 89 against the 100 of retail_quest_cache_12.1.0.69933.jsonl, the build before (89.0%).' 'K2: the first names both counts and the cache of the build before'
Equal $w[1] 'WARNING: a probe run cut short leaves a cache like this, and what it lacks reads as quests no source speaks for. Finish the run and read the cache again (docs\maintenance.md, step 2e).' 'K2: the second why it matters and what to do'
$null = Write-Cache $sizeDir 'retail_quest_cache_12.1.0.9.jsonl' (1..50)
$null = Write-Cache $sizeDir 'retail_quest_cache_12.0.7.99999.jsonl' (1..50)
$null = Write-Cache $sizeDir 'retail_quest_cache_12.1.10.1.jsonl' (1..1000)
$null = Write-Cache $sizeDir 'retail_quest_cache_notabuild.jsonl' (1..1000)
$null = Write-Cache $sizeDir 'forever_quest_cache_1.60.1.70374.jsonl' (1..1000)
Has (@(Get-QuestCacheWarning $newest) -join "`n") 'against the 100 of retail_quest_cache_12.1.0.69933.jsonl' 'K3: the build before is the newest earlier one, by version and not by text; a later build, a name with no build and the other game''s cache are not it'
Equal ((@(Get-QuestCacheFiles $sizeDir) | ForEach-Object { $_.Name }) -join ',') 'retail_quest_cache_12.0.7.99999.jsonl,retail_quest_cache_12.1.0.9.jsonl,retail_quest_cache_12.1.0.69933.jsonl,retail_quest_cache_12.1.5.70391.jsonl,retail_quest_cache_12.1.10.1.jsonl' 'K3: Get-QuestCacheFiles lists the game''s caches by version'
Equal ((@(Get-QuestCacheFiles $sizeDir 'forever') | ForEach-Object { $_.Name }) -join ',') 'forever_quest_cache_1.60.1.70374.jsonl' 'K3: and Forever''s apart'
$emptyDir = Join-Path $Scratch 'cache-empty'
$null = Write-Cache $emptyDir 'retail_quest_cache_12.1.0.69933.jsonl' @()
$alone = Write-Cache $emptyDir 'retail_quest_cache_12.1.5.70391.jsonl' (1..5)
Equal @(Get-QuestCacheWarning $alone).Count 0 'K4: an empty cache of the build before is no measure'
$oursDir = Join-Path $Scratch 'cache-ours'
$alone = Write-Cache $oursDir 'retail_quest_cache_12.1.5.70391.jsonl' (@(1..89) + @(500..520))
Equal @(Get-QuestCacheWarning $alone (1..98)).Count 0 'K5: 89 of our 98 quests (90.8%) is not warned about'
$w = @(Get-QuestCacheWarning $alone (1..99))
Equal $w[0] 'WARNING: retail_quest_cache_12.1.5.70391.jsonl looks partial, with under 90% of the quests it should hold: 89 of our 99 (89.9%).' 'K5: 89 of our 99 is, and the quests only in the cache do not count'
$w = @(Get-QuestCacheWarning $newest (1..100))
Equal $w[0] 'WARNING: retail_quest_cache_12.1.5.70391.jsonl looks partial, with under 90% of the quests it should hold: 89 against the 100 of retail_quest_cache_12.1.0.69933.jsonl, the build before (89.0%), and 89 of our 100 (89.0%).' 'K6: both counts at once, in one line'
$odd = Write-Cache $oursDir 'retail_quest_cache_test.jsonl' (1..10)
Equal @(Get-QuestCacheWarning $odd (1..20))[0] 'WARNING: retail_quest_cache_test.jsonl looks partial, with under 90% of the quests it should hold: 10 of our 20 (50.0%).' 'K7: a cache whose name holds no build is held to our data alone'
$null = Write-Cache $oursDir 'forever_quest_cache_1.60.1.70338.jsonl' (1..100)
$w = @(Get-QuestCacheWarning (Write-Cache $oursDir 'forever_quest_cache_1.60.1.70374.jsonl' (1..80)))
Has $w[0] '80 against the 100 of forever_quest_cache_1.60.1.70338.jsonl, the build before (80.0%)' 'K8: Forever''s cache is held to the build before too'
Has $w[1] '(docs\maintenance.md, step 10).' 'K8: and the warning names its step'

$partial = Join-Path $Scratch 'partial'
Copy-Item $world $partial -Recurse
$r = Invoke-Tool $Compare $partial
Equal $r.Exit 0 'K9: the made-up world passes the check'
Lacks $r.Text 'looks partial' 'K9: and its cache, 142 of its 151 quests, is not warned about'
$before = @(foreach ($line in [IO.File]::ReadAllLines("$partial\tools\retail_quest_cache_$Build.jsonl")) { $line }) + @(5000..5207 | ForEach-Object { '{"id":' + $_ + ',"title":"Quest ' + $_ + '","contentTuning":10,"sort":0,"questType":2}' })
[IO.File]::WriteAllText("$partial\tools\retail_quest_cache_12.0.7.99999.jsonl", (($before -join "`n") + "`n"), $utf8)
$r = Invoke-Tool $Compare $partial
Equal $r.Exit 0 'K9: with a larger cache of the build before, the check exits as it did'
Has $r.Text "WARNING: retail_quest_cache_$Build.jsonl looks partial, with under 90% of the quests it should hold: 142 against the 350 of retail_quest_cache_12.0.7.99999.jsonl, the build before (40.6%)." 'K9: and warns, with both counts'
Has $r.Text 'Retail build 12.1.0.69933:' 'K9: the newest cache is still the one read'
$baselineBefore = [IO.File]::ReadAllText("$partial\baseline.csv")
$r = Invoke-Tool $Compare $partial @{ UpdateBaseline = $true }
Equal $r.Exit 1 'K10: -UpdateBaseline is refused while the warning stands'
Has $r.Text 'Baseline not written: the quest cache looks partial (the warning above).' 'K10: and says so'
Has $r.Text 'FAILED: -UpdateBaseline was refused, as the quest cache looks partial' 'K10: in the FAILED line'
Equal ([IO.File]::ReadAllText("$partial\baseline.csv")) $baselineBefore 'K10: and the baseline is left as it was'
$r = Invoke-Tool $Compare $partial @{ UpdateBaseline = $true; AcceptPartialCache = $true }
Equal $r.Exit 0 'K11: -AcceptPartialCache lets it write all the same'
Has $r.Text 'Baseline written: ' 'K11: the baseline'
Has $r.Text 'looks partial' 'K11: with the warning still shown'
$partialHashes = Get-Hashes $partial
$r = Invoke-Tool $Apply $partial @{ WhatIf = $true }
Equal $r.Exit 0 'K12: Apply-QuestMinLevels.ps1 -WhatIf exits as it did'
Has $r.Text "WARNING: retail_quest_cache_$Build.jsonl looks partial" 'K12: and warns'
$r = Invoke-Tool $Apply $partial
Equal $r.Exit 0 'K12: and a run of it too'
Has $r.Text 'Nothing to change' 'K12: which has nothing to change here'
Equal (Get-Hashes $partial) $partialHashes 'K12: and writes nothing'

# --- The real files ------------------------------------------------------------------------------------------
$realTable = @(Get-ChildItem "$RealToolsDir\ContentTuning-*.csv" -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -match '^ContentTuning-\d+\.\d+\.\d+\.\d+$' })
$realCache = @(Get-ChildItem "$RealToolsDir\retail_quest_cache_*.jsonl" -ErrorAction SilentlyContinue)
$haveReal = ($realTable.Count -gt 0) -and ($realCache.Count -gt 0) -and (Test-Path "$RealToolsDir\quest_api_cache") -and (Test-Path "$RealToolsDir\QuestV2CliTask.csv")
if (-not $haveReal) {
    Write-Output "The real files aren't in ${RealToolsDir} (a ContentTuning table, a quest cache, the API cache and the task table): that section was skipped."
} else {
    $realDir = Join-Path $Scratch 'real'
    New-Item -ItemType Directory "$realDir\data", "$realDir\addon" | Out-Null
    $checkoutData = Join-Path $PSScriptRoot '..\data'
    $stripped = ([IO.File]::ReadAllText("$checkoutData\quests.jsonl") -replace ',"minLevel":\d+\}', '}')
    [IO.File]::WriteAllText("$realDir\data\quests.jsonl", $stripped, $utf8)
    Copy-Item "$checkoutData\pins.jsonl" "$realDir\data\pins.jsonl"
    Invoke-AddonDataBuild -DataDir "$realDir\data" -AddonDir "$realDir\addon" | Out-Null
    $realBefore = Get-Hashes $realDir
    $strippedLines = [IO.File]::ReadAllLines("$realDir\data\quests.jsonl")
    $r = Invoke-Tool $Apply $realDir @{ ToolsDir = $RealToolsDir; MinTested = 20000 }
    Equal $r.Exit 0 'R1: on the real files the run exits 0'
    Check ($r.Text -match 'tested against ([\d,]+) quests .*: ([\d,]+) agree \((\d+\.\d+)%\)  \[ok\]') 'R1: the formula is tested and passes'
    if ($r.Text -match 'tested against ([\d,]+) quests .*: ([\d,]+) agree \((\d+\.\d+)%\)  \[ok\]') {
        Check ([double]$Matches[3] -ge 99.0 -and [int]($Matches[1] -replace ',') -ge 20000) "R1: it reproduces the API for at least 99% of 20,000 quests ($($Matches[2]) of $($Matches[1]), $($Matches[3])%)"
    }
    Lacks $r.Text 'from tuning0:' 'R1: no quest on tuning 0 gets a minLevel'
    $appliedLines = [IO.File]::ReadAllLines("$realDir\data\quests.jsonl")
    Equal $appliedLines.Count $strippedLines.Count 'R2: the real data keeps all its quests'
    $addedOnly = 0; $bad = 0
    for ($i = 0; $i -lt $strippedLines.Count; $i++) {
        if ($appliedLines[$i] -ceq $strippedLines[$i]) { continue }
        $changed = $appliedLines[$i] | ConvertFrom-Json
        if ($appliedLines[$i].EndsWith(',"minLevel":' + $changed.minLevel + '}') -and $appliedLines[$i].Substring(0, $appliedLines[$i].LastIndexOf(',"minLevel":')) + '}' -ceq $strippedLines[$i] -and $changed.minLevel -ne $changed.level) { $addedOnly++ }
        else { $bad++ }
    }
    Check ($addedOnly -gt 0) "R2: some quests get a minLevel ($addedOnly)"
    Equal $bad 0 'R2: every changed line is the old one with a minLevel added, which is never the level'
    $realAfter = Get-Hashes $realDir
    $r = Invoke-Tool $Apply $realDir @{ ToolsDir = $RealToolsDir; MinTested = 20000 }
    Equal $r.Exit 0 'R3: a second run on the real files exits 0'
    Has $r.Text 'Nothing to change' 'R3: and has nothing to change'
    Equal (Get-Hashes $realDir) $realAfter 'R3: byte for byte'
    $built = Invoke-AddonDataBuild -DataDir "$realDir\data" -AddonDir "$realDir\addon" -Check
    Check $built.Ok 'R3: and the Lua matches the data'
    $checkout = [IO.File]::ReadAllText("$checkoutData\quests.jsonl")
    $ours = [IO.File]::ReadAllText("$realDir\data\quests.jsonl")
    Write-Output ("Info: the real files give {0:N0} quests a minLevel; the result {1} the checkout's own data." -f $addedOnly, $(if ($ours -ceq $checkout) { 'is' } else { 'is not' }))
}

[Threading.Thread]::CurrentThread.CurrentCulture = $savedCulture
Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "$Passed checks passed, $Failed failed"
if ($Failed -gt 0) { exit 1 }
