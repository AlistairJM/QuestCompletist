<#
Checks which task quests Build-QuestLocationData.ps1 places at their start, on made-up client tables in a
scratch folder: nothing in the checkout is written and nothing is downloaded. A task quest (a row of
QuestV2CliTask) is placed unless its QuestInfoID is a kind of $noPinKinds (PinRules.ps1's $NoPinTaskKinds), a quest that has a pin already
is placed whatever its kind, the run stops at a QuestInfo named World Quest that the table lacks, Dragonrider
Racing (281) is placed and Calling Quest (271) is held, and deleting the 271 line is all it takes to pin the callings.
On a made-up TrinityCore dump (read with Lua 5.1, -LuaExe), the TrinityCore pass places a Landfall quest the client
lists no point for, under its starter, and still holds a quest of a holiday's category.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-QuestLocationKinds.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param([string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe')
$ErrorActionPreference = 'Stop'
$Builder = Join-Path $PSScriptRoot 'Build-QuestLocationData.ps1'
$Rules = Join-Path $PSScriptRoot 'PinRules.ps1'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("quest-location-kinds-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null

$Kinds = @{
    1000 = $null
    1001 = 0
    1002 = 109
    1003 = 271
    1004 = 281
    1005 = 266
    1006 = 268
    1007 = 283
    1008 = 265
    1009 = 777
    1010 = 110
    1011 = 85
    1012 = 289
    1013 = 109
}

function New-World([string]$name, [string]$extraInfo = '') {
    $root = Join-Path $Scratch $name
    foreach ($dir in 'tools', 'data', 'addon', 'scripts') { New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null }
    $quests = New-Object System.Collections.Generic.List[string]
    $blobs = New-Object System.Collections.Generic.List[string]
    $points = New-Object System.Collections.Generic.List[string]
    $tasks = New-Object System.Collections.Generic.List[string]
    $blobId = 5000
    foreach ($id in ($Kinds.Keys | Sort-Object)) {
        $quests.Add('{"id":' + $id + ',"name":"Quest ' + $id + '","level":10,"zone":"","category":10,"type":1,"faction":2,"race":67108863,"class":8191}')
        $blobs.Add("$blobId,0,37,0,1,$id,32,0,0,0")
        $points.Add("$blobId,100,100,0")
        if ($null -ne $Kinds[$id]) { $tasks.Add("$id,$($Kinds[$id])") }
        $blobId++
    }
    [IO.File]::WriteAllText("$root\data\quests.jsonl", (($quests -join "`n") + "`n"))
    [IO.File]::WriteAllText("$root\data\pins.jsonl", '{"map":37,"icon":1,"x":50,"y":50,"quests":[1013]}' + "`n")
    [IO.File]::WriteAllText("$root\tools\QuestPOIBlob.csv", "ID,MapID,UiMapID,Flags,NumPoints,QuestID,ObjectiveIndex,ObjectiveID,PlayerConditionID,NavigationPlayerConditionID`r`n" + ($blobs -join "`r`n") + "`r`n")
    [IO.File]::WriteAllText("$root\tools\QuestPOIPoint.csv", "QuestPOIBlobID,X,Y,Z`r`n" + ($points -join "`r`n") + "`r`n")
    [IO.File]::WriteAllText("$root\tools\UiMapAssignment.csv", "UiMapID,MapID,Region_0,Region_1,Region_3,Region_4,UiMin_0,UiMin_1,UiMax_0,UiMax_1`r`n37,0,-1000,-1000,1000,1000,0,0,1,1`r`n")
    [IO.File]::WriteAllText("$root\tools\UiMap.csv", "Name_lang,ID,ParentUiMapID`r`nElwynn,37,0`r`n")
    [IO.File]::WriteAllText("$root\tools\QuestV2CliTask.csv", "ID,QuestInfoID`r`n" + ($tasks -join "`r`n") + "`r`n")
    $info = "ID,InfoName_lang,Type,Modifiers,Profession`r`n1,Group,0,0,0`r`n109,World Quest,2,256,0`r`n110,Epic World Quest,2,268,0`r`n265,Hidden Quest,5,272,0`r`n268,Threat Wrapper,14,272,0`r`n271,Calling Quest,15,0,0`r`n281,Dragonrider Racing,16,0,0`r`n283,Bonus Objective with Completion Toast,0,512,0`r`n" + $extraInfo
    [IO.File]::WriteAllText("$root\tools\QuestInfo.csv", $info)
    Copy-Item (Join-Path $PSScriptRoot 'AddonData.ps1') "$root\scripts\AddonData.ps1"
    Copy-Item $Builder "$root\scripts\Build-QuestLocationData.ps1"
    Copy-Item $Rules "$root\scripts\PinRules.ps1"
    return $root
}

function Invoke-Builder([string]$root, [string]$tdbFile = '') {
    $tdb = if ($tdbFile) { @('-TdbFile', $tdbFile, '-LuaExe', $LuaExe) } else { @('-LuaExe', "$root\no-lua.exe") }
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\scripts\Build-QuestLocationData.ps1" -ToolsDir "$root\tools" -DataDir "$root\data" -AddonDir "$root\addon" @tdb 2>&1) } finally { $ErrorActionPreference = $saved }
    $exit = $LASTEXITCODE
    $rows = @()
    if (Test-Path "$root\tools\quest_locations.csv") { $rows = @(Import-Csv "$root\tools\quest_locations.csv") }
    $placed = @($rows | ForEach-Object { [int]$_.QuestID } | Sort-Object -Unique)
    return [pscustomobject]@{ Exit = $exit; Text = ($out | ForEach-Object { "$_" }) -join "`n"; Placed = ($placed -join ','); Rows = $rows }
}

function Row([object[]]$values, [int]$columns) {
    $all = @($values) + @(@(0) * ($columns - $values.Count))
    return '(' + (($all | ForEach-Object { if ($_ -is [string]) { "'$_'" } else { "$_" } }) -join ',') + ')'
}

# Read-DumpTable stops at a table with fewer rows than a real dump has, so each table is padded with rows of
# IDs no quest of the world uses.
function Write-Dump([string]$path, [object[]]$tables) {
    $writer = New-Object IO.StreamWriter($path, $false, (New-Object Text.UTF8Encoding($false)))
    try {
        foreach ($t in $tables) {
            $rows = New-Object System.Collections.Generic.List[string]
            foreach ($row in $t.Rows) { $rows.Add($row) }
            $zeros = ',0' * ($t.Columns - 1)
            for ($i = 0; $i -lt $t.Filler; $i++) { $rows.Add("($(900000 + $i)$zeros)") }
            $writer.Write("INSERT INTO ``$($t.Name)`` VALUES " + ($rows -join ',') + ";`n")
        }
    } finally { $writer.Dispose() }
}

try {
    $root = New-World 'base'
    $r = Invoke-Builder $root
    Equal $r.Exit 0 "K1: the run succeeds ($($r.Text.Substring(0, [math]::Min(600, $r.Text.Length)))"
    Equal $r.Placed '1000,1001,1004,1005,1009,1011,1012,1013' 'K1: a quest that is no task, and task quests of kind 0, Dragonrider Racing (281), Combat Ally (266), Heroic (85), World Boss (289) and one QuestInfo has no row for, are placed; the pinned world quest too'
    Check ($r.Text -match 'left out as a kind in \$noPinKinds: 6') 'K1: six task quests are left out: a world quest, an epic one, a calling, a threat wrapper, a bonus objective and a hidden quest'
    Check ($r.Text -match 'placed at their start with no pin yet: 6\r?\n(.*\r?\n)*?\s+kind 281 \(Dragonrider Racing\): 1\r?\n') 'K1: six task quests are newly placed, the racing one among them'

    $root = New-World 'unknown-world-quest' "999,Fancy World Quest,2,256,0`r`n"
    $r = Invoke-Builder $root
    Check ($r.Exit -ne 0) 'K2: a QuestInfo named World Quest that the table lacks stops the run'
    Check ($r.Text -match 'QuestInfo 999 \(Fancy World Quest\) is named World Quest and is not in \$noPinKinds') 'K2: and says which'

    $root = New-World 'no-calling'
    $script = "$root\scripts\PinRules.ps1"
    $text = [IO.File]::ReadAllText($script)
    $line = "    271 = 'Calling Quest'"
    Equal ([regex]::Matches($text, [regex]::Escape($line)).Count) 1 'K3: the table has one line for the callings'
    [IO.File]::WriteAllText($script, $text.Replace($line + "`r`n", '').Replace($line + "`n", ''))
    $r = Invoke-Builder $root
    Equal $r.Exit 0 'K3: the run succeeds without the line'
    Equal $r.Placed '1000,1001,1003,1004,1005,1009,1011,1012,1013' 'K3: deleting the line pins the callings and nothing else'

    $text = [IO.File]::ReadAllText($Rules)
    Equal ([regex]::Matches($text, '(?m)^\s+281 = ').Count) 0 'K4: the table has no line for Dragonrider Racing'
    foreach ($held in "265 = 'Hidden Quest'", "268 = 'Threat Wrapper'", "271 = 'Calling Quest'", "283 = 'Bonus Objective with Completion Toast'") {
        Equal ([regex]::Matches($text, '(?m)^\s+' + [regex]::Escape($held) + '\s*$').Count) 1 "K4: the table holds $held"
    }

    $root = New-World 'no-task-table'
    Remove-Item "$root\tools\QuestV2CliTask.csv"
    $r = Invoke-Builder $root
    Check ($r.Exit -ne 0) 'K5: without QuestV2CliTask.csv the run stops'

    $root = New-World 'no-quest-info'
    Remove-Item "$root\tools\QuestInfo.csv"
    $r = Invoke-Builder $root
    Check ($r.Exit -ne 0) 'K6: without QuestInfo.csv the run stops'

    $root = New-World 'trinitycore'
    Copy-Item (Join-Path $PSScriptRoot 'Read-SqlDump.lua') "$root\scripts\Read-SqlDump.lua"
    $tdbQuests = @{
        2000 = @{ Line = '{"id":2000,"name":"Landfall daily","level":15,"zone":"Landfall","category":121,"type":4,"faction":1,"race":67108863,"class":8191}'; At = @(100, 100) }
        2001 = @{ Line = '{"id":2001,"name":"Holiday category quest","level":10,"zone":"","category":31,"type":1,"faction":2,"race":67108863,"class":8191}'; At = @(-300, 300) }
        2002 = @{ Line = '{"id":2002,"name":"Plain quest","level":10,"zone":"","category":10,"type":1,"faction":2,"race":67108863,"class":8191}'; At = @(-300, -300) }
    }
    $ids = @($tdbQuests.Keys | Sort-Object)
    [IO.File]::AppendAllText("$root\data\quests.jsonl", ((@($ids | ForEach-Object { $tdbQuests[$_].Line }) -join "`n") + "`n"))
    [IO.File]::WriteAllText("$root\tools\QuestV2.csv", "ID`r`n" + (($ids -join "`r`n") + "`r`n"))
    Write-Dump "$root\tools\dump.sql" @(
        @{ Name = 'quest_template'; Columns = 24; Filler = 30000; Rows = @($ids | ForEach-Object { Row @($_) 24 }) },
        @{ Name = 'disables'; Columns = 3; Filler = 2000; Rows = @() },
        @{ Name = 'creature_queststarter'; Columns = 2; Filler = 5000; Rows = @((Row @(7000, 2000) 2)) },
        @{ Name = 'gameobject_queststarter'; Columns = 2; Filler = 1000; Rows = @() },
        @{ Name = 'quest_poi'; Columns = 8; Filler = 40000; Rows = @($ids | ForEach-Object { Row @($_, 0, 0, 32, 0, 0, 0, 37) 8 }) },
        @{ Name = 'quest_poi_points'; Columns = 5; Filler = 80000; Rows = @($ids | ForEach-Object { Row @($_, 0, 0, $tdbQuests[$_].At[0], $tdbQuests[$_].At[1]) 5 }) },
        @{ Name = 'creature_template'; Columns = 4; Filler = 30000; Rows = @((Row @(7000, 0, 0, 'Landfall Giver') 4)) },
        @{ Name = 'creature'; Columns = 14; Filler = 150000; Rows = @((Row @(1, 7000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 100, 100) 14)) }
    )
    $r = Invoke-Builder $root "$root\tools\dump.sql"
    Equal $r.Exit 0 "K7: the run with a TrinityCore dump succeeds ($($r.Text.Substring(0, [math]::Min(600, $r.Text.Length))))"
    $tc = @($r.Rows | Where-Object { $_.Source -eq 'trinitycore' })
    Equal ((@($tc | ForEach-Object { $_.QuestID }) | Sort-Object) -join ',') '2000,2002' 'K7: TrinityCore''s starts place the Landfall quest and the plain one, not the quest of a holiday''s category'
    $landfall = @($tc | Where-Object { $_.QuestID -eq '2000' })
    Equal (($landfall | ForEach-Object { "$($_.UiMapID) $($_.MapX),$($_.MapY) $($_.GiverNpcId) $($_.GiverName)" }) -join '; ') '37 45,45 7000 Landfall Giver' 'K7: the Landfall quest stands at its start, named after its starter, whose spawn stands there'
    Check ($r.Text -match 'not placed, holiday category: 1') 'K7: the quest of a holiday''s category is held as one'
    Check ($r.Text -notmatch 'Landfall') 'K7: no reason the pass gives names Landfall'
}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
