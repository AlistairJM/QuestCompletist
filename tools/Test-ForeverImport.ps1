<#
Checks what Import-ForeverData.ps1 (sweep step 10) takes from the recorder's ledger, on a small Forever
world made in a scratch folder: nothing in the checkout is written and nothing is downloaded. The world
has its own client tables, CMaNGOS dump, quest cache, probe file and ledger. The ledger is made from the
probe file by Import-RecordedGivers.ps1 (step 6d), as in a sweep. Section H compares the importer's files
with $MasterOutput, what master's importer wrote on its world; a change meant to alter those files writes
them again, from a run checked by hand.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ForeverImport.ps1

-Importer names another copy of the importer (in tools\) to run the same checks on; -Keep leaves the
scratch folder where it is and says where.

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param(
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [string]$Importer = (Join-Path $PSScriptRoot 'Import-ForeverData.ps1'),
    [switch]$Keep
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\RecordedGivers.ps1"
$MergeTool = Join-Path $PSScriptRoot 'Import-RecordedGivers.ps1'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

# What master's importer (448bd64), which read the recorder's notes straight from the probe's file, wrote on
# section H's world, run once with -Importer and the parameters it lacks accepted and ignored. It is not made
# from the code it checks: section H checks that the ledger, filled from that file alone, gives the same files.
$MasterOutput = [ordered]@{
    'data\forever\pins.jsonl' = (@(
        '{"map":1411,"icon":1,"npc":910001,"name":"Alpha Giver","x":52,"y":51,"quests":[9001]}'
        '{"map":1411,"icon":1,"npc":910003,"name":"Gamma Giver","x":20,"y":20,"quests":[9003]}'
        '{"map":1411,"icon":1,"npc":910005,"name":"Epsilon Giver","x":60,"y":60,"quests":[9005]}'
        '{"map":1411,"icon":1,"npc":910005,"name":"Epsilon Giver","x":63,"y":60,"quests":[9005]}'
        '{"map":1411,"icon":1,"npc":910006,"name":"Zeta Giver","x":10,"y":10,"quests":[9006]}'
        '{"map":1411,"icon":1,"npc":910007,"name":"Eta Giver","x":70,"y":30,"quests":[9007]}'
        '{"map":1411,"icon":1,"name":"Kappa Chest Old","x":70,"y":70,"quests":[9011]}'
    ) -join "`n") + "`n"
    'data\forever\quests.jsonl' = (@(
        '{"id":9001,"name":"Alpha Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
        '{"id":9002,"name":"Beta Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
        '{"id":9003,"name":"Gamma Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
        '{"id":9004,"name":"Delta Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
        '{"id":9005,"name":"Epsilon Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
        '{"id":9006,"name":"Zeta Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
        '{"id":9007,"name":"Eta Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
        '{"id":9008,"name":"Theta Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
        '{"id":9010,"name":"Iota Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
        '{"id":9011,"name":"Kappa Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
        '{"id":9012,"name":"Lambda Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
        '{"id":9013,"name":"Mu Quest","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191,"minLevel":5}'
    ) -join "`n") + "`n"
    'data\forever\links.jsonl' = ''
    'data\forever\reputation.jsonl' = ''
    'data\forever\skills.jsonl' = ''
    'data\forever\answers.jsonl' = (@(
        '{"runs":["1.60.1.70900"]}'
        '{"id":9001,"seen":"1.60.1.70900","missed":0,"record":{"id":9001,"title":"Alpha Quest","level":10,"minLevel":5,"sort":10}}'
        '{"id":9002,"seen":"1.60.1.70900","missed":0,"record":{"id":9002,"title":"Beta Quest","level":10,"minLevel":5,"sort":10}}'
        '{"id":9003,"seen":"1.60.1.70900","missed":0,"record":{"id":9003,"title":"Gamma Quest","level":10,"minLevel":5,"sort":10}}'
        '{"id":9004,"seen":"1.60.1.70900","missed":0,"record":{"id":9004,"title":"Delta Quest","level":10,"minLevel":5,"sort":10}}'
        '{"id":9005,"seen":"1.60.1.70900","missed":0,"record":{"id":9005,"title":"Epsilon Quest","level":10,"minLevel":5,"sort":10}}'
        '{"id":9006,"seen":"1.60.1.70900","missed":0,"record":{"id":9006,"title":"Zeta Quest","level":10,"minLevel":5,"sort":10}}'
        '{"id":9007,"seen":"1.60.1.70900","missed":0,"record":{"id":9007,"title":"Eta Quest","level":10,"minLevel":5,"sort":10}}'
        '{"id":9008,"seen":"1.60.1.70900","missed":0,"record":{"id":9008,"title":"Theta Quest","level":10,"minLevel":5,"sort":10}}'
        '{"id":9010,"seen":"1.60.1.70900","missed":0,"record":{"id":9010,"title":"Iota Quest","level":10,"minLevel":5,"sort":10}}'
        '{"id":9011,"seen":"1.60.1.70900","missed":0,"record":{"id":9011,"title":"Kappa Quest","level":10,"minLevel":5,"sort":10}}'
        '{"id":9012,"seen":"1.60.1.70900","missed":0,"record":{"id":9012,"title":"Lambda Quest","level":10,"minLevel":5,"sort":10}}'
        '{"id":9013,"seen":"1.60.1.70900","missed":0,"record":{"id":9013,"title":"Mu Quest","level":10,"minLevel":5,"sort":10}}'
    ) -join "`n") + "`n"
    'review.csv' = (@(
        '"Kind","Quest","Other","Detail"'
        '"no giver","9002","","Beta Quest (only the game knows it)"'
        '"no giver","9004","","Delta Quest (only the game knows it)"'
        '"no giver","9008","","Theta Quest (only the game knows it)"'
        '"no giver","9010","","Iota Quest (only the game knows it)"'
        '"no giver","9012","","Lambda Quest (only the game knows it)"'
        '"no giver","9013","","Mu Quest (only the game knows it)"'
        '"old pin names another giver","9001","16013","old pin: 16013; CMaNGOS: 910001"'
        '"old pin names another giver","9007","16012","old pin: 16012; CMaNGOS: 910007"'
        '"recorded spot far from CMaNGOS","","Creature:910001","Alpha Giver at 52.0 51.0: 2.2 map points from CMaNGOS''s spawn"'
    ) -join "`r`n") + "`r`n"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("forever-import-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null
$Build = '1.60.1.70900'
$Tag = 'own-forever_probe_70900'

# --- Making the scratch world --------------------------------------------------------------------

function Write-Lines([string]$path, $lines) { [IO.File]::WriteAllText($path, ((@($lines) -join "`r`n") + "`r`n")) }

# One line of the quest cache the importer reads (Read-QuestCache.ps1 writes the real ones).
function Cache-Line([int]$id, [string]$title) { return '{"id":' + $id + ',"title":"' + $title + '","level":10,"minLevel":5,"sort":10}' }

# A row of CMaNGOS's quest_template with the columns the importer reads (Read-SqlDump.lua numbers them from 1).
function Quest-Row([int]$id, [string]$title) {
    $fields = @(1..90 | ForEach-Object { '0' })
    $fields[0] = "$id"; $fields[2] = '10'; $fields[3] = '5'; $fields[5] = '10'; $fields[30] = "'$title'"
    return '(' + ($fields -join ',') + ')'
}

function Write-Dump([string]$path, $quests, $starters, $spawns, $names, $objectStarters = @(), $objectSpawns = @(), $objectNames = @()) {
    $sql = New-Object System.Collections.Generic.List[string]
    if ($quests.Count) { $sql.Add('INSERT INTO `quest_template` VALUES ' + (($quests | ForEach-Object { Quest-Row $_[0] $_[1] }) -join ',') + ';') }
    if ($starters.Count) { $sql.Add('INSERT INTO `creature_questrelation` VALUES ' + (($starters | ForEach-Object { "($($_[0]),$($_[1]))" }) -join ',') + ';') }
    if ($spawns.Count) { $sql.Add('INSERT INTO `creature` VALUES ' + (($spawns | ForEach-Object { "($($_[0]),$($_[1]),1,0,$($_[2]),$($_[3]),5.0)" }) -join ',') + ';') }
    if ($names.Count) { $sql.Add('INSERT INTO `creature_template` VALUES ' + (($names | ForEach-Object { "($($_[0]),'$($_[1])')" }) -join ',') + ';') }
    if ($objectStarters.Count) { $sql.Add('INSERT INTO `gameobject_questrelation` VALUES ' + (($objectStarters | ForEach-Object { "($($_[0]),$($_[1]))" }) -join ',') + ';') }
    if ($objectSpawns.Count) { $sql.Add('INSERT INTO `gameobject` VALUES ' + (($objectSpawns | ForEach-Object { "($($_[0]),$($_[1]),1,0,$($_[2]),$($_[3]),5.0)" }) -join ',') + ';') }
    if ($objectNames.Count) { $sql.Add('INSERT INTO `gameobject_template` VALUES ' + (($objectNames | ForEach-Object { "($($_[0]),2,0,'$($_[1])')" }) -join ',') + ';') }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($sql -join "`n") + "`n")
    $stream = [IO.File]::Create($path)
    $gzip = New-Object System.IO.Compression.GZipStream($stream, [IO.Compression.CompressionMode]::Compress)
    $gzip.Write($bytes, 0, $bytes.Length)
    $gzip.Close(); $stream.Close()
}

# The probe's saved variables. Each giver is @{ Kind; Id; Name; Spots = @(@(map, x, y, visits)); Offers; Turn }.
function Write-Probe([string]$path, $givers, $builds = $Build) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('QCForeverProbeDB = {')
    [void]$sb.AppendLine('["quests"] = {')
    [void]$sb.AppendLine("[9001] = { [""build""] = ""$Build"", [""result""] = ""ok"", [""classification""] = ""normal"" },")
    [void]$sb.AppendLine('},')
    [void]$sb.AppendLine('["npcs"] = {')
    [void]$sb.AppendLine("[910001] = { [""build""] = ""$Build"", [""result""] = ""ok"", [""name""] = ""Alpha Giver"" },")
    [void]$sb.AppendLine('},')
    [void]$sb.AppendLine('["givers"] = {')
    foreach ($g in $givers) {
        [void]$sb.AppendLine("[""$($g.Kind):$($g.Id)""] = { [""kind""] = ""$($g.Kind)"", [""id""] = $($g.Id), [""name""] = ""$($g.Name)"", [""build""] = ""$builds"",")
        [void]$sb.AppendLine('["spots"] = {')
        foreach ($s in $g.Spots) { [void]$sb.AppendLine("[""$($s[0]) $(([decimal]$s[1]).ToString('0.0', $script:Invariant)) $(([decimal]$s[2]).ToString('0.0', $script:Invariant))""] = $($s[3]),") }
        [void]$sb.AppendLine('},')
        [void]$sb.AppendLine('["offers"] = {')
        foreach ($q in @($g.Offers)) { [void]$sb.AppendLine("[$q] = { [""frequency""] = 0, [""repeatable""] = false },") }
        [void]$sb.AppendLine('},')
        [void]$sb.AppendLine('["turnIns"] = {')
        foreach ($q in @($g.Turn)) { [void]$sb.AppendLine("[$q] = true,") }
        [void]$sb.AppendLine('}, },')
    }
    [void]$sb.AppendLine('},')
    [void]$sb.AppendLine('["accepted"] = {}, ["started"] = {},')
    [void]$sb.AppendLine('}')
    [IO.File]::WriteAllText($path, $sb.ToString())
}

function G([string]$kind, [int]$id, [string]$name, $spots, $offers, $turn = @()) {
    return @{ Kind = $kind; Id = $id; Name = $name; Spots = $spots; Offers = $offers; Turn = $turn }
}

# The givers the probe met. 910001 has a CMaNGOS spawn at 50,50 too; 910003 stood at two places 1.4
# points apart, 910004 1.6 apart, 910005 3 apart; 910006 offers a quest the data lacks.
function Get-ProbeGivers() {
    return @(
        (G 'Creature' 910001 'Alpha Giver' @(, @(1411, 52, 51, 4)) @(9001))
        (G 'Creature' 910003 'Gamma Giver' @(@(1411, 20, 20, 5), @(1411, 21.4, 20, 1)) @(9003))
        (G 'Creature' 910004 'Delta Giver' @(@(1411, 40, 40, 5), @(1411, 41.6, 40, 1)) @(9004))
        (G 'Creature' 910005 'Epsilon Giver' @(@(1411, 60, 60, 2), @(1411, 63, 60, 1)) @(9005))
        (G 'Creature' 910006 'Zeta Giver' @(, @(1411, 10, 10, 2)) @(9006))
    )
}

# The world: tools, data and addon folders, the probe file, the dump and the cache.
function New-World([string]$name, [switch]$ZetaKnown, $Givers = (Get-ProbeGivers)) {
    $root = Join-Path $Scratch $name
    foreach ($dir in 'tools', 'tools\forever_probe_70900', 'data\forever', 'addon') { New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null }
    $t = "$root\tools"
    $quests = @{ 9001 = 'Alpha Quest'; 9002 = 'Beta Quest'; 9003 = 'Gamma Quest'; 9004 = 'Delta Quest'; 9005 = 'Epsilon Quest'
        9006 = 'Zeta Quest'; 9007 = 'Eta Quest'; 9008 = 'Theta Quest'; 9010 = 'Iota Quest'; 9011 = 'Kappa Quest'; 9012 = 'Lambda Quest'
        9013 = 'Mu Quest' }
    Write-Lines "$t\QuestV2-$Build.csv" (@('ID') + @($quests.Keys | Sort-Object))
    Write-Lines "$t\AreaTable-$Build.csv" @('ID,ZoneName,AreaName_lang,ContinentID,ParentAreaID', '10,Alpha,Alpha Zone,1,0')
    Write-Lines "$t\ChrRaces-$Build.csv" @('ID,Name_lang', '1,Human')
    Write-Lines "$t\QuestSort-$Build.csv" @('ID,SortName_lang,UiOrderIndex,Flags', '1,Epic,0,0')
    Write-Lines "$t\Map-$Build.csv" @('ID,MapName_lang,InstanceType,AreaTableID', '1,Kalimdor,0,0')
    Write-Lines "$t\UiMapAssignment-$Build.csv" @('UiMin_0,UiMin_1,UiMax_0,UiMax_1,Region_0,Region_1,Region_2,Region_3,Region_4,Region_5,ID,UiMapID,OrderIndex,MapID,AreaID',
        '0,0,1,1,-1000,-1000,-1000000,1000,1000,1000000,1,1411,0,1,10')
    foreach ($b in $Build, '1.15.9.70003') { Write-Lines "$t\UiMap-$b.csv" @('Name_lang,ID,ParentUiMapID,Flags,System,Type', 'Alpha,1411,0,0,0,3', 'Beta,1412,0,0,0,3') }
    Write-Lines "$t\UiMap.csv" @('Name_lang,ID,ParentUiMapID,Flags,System,Type', 'Stormwind,84,0,0,0,3')
    Write-Lines "$t\QuestLineXQuest-$Build.csv" @('ID,QuestLineID,QuestID,OrderIndex,Flags')
    Write-Lines "$t\QuestLine-$Build.csv" @('ID,Name_lang')
    Write-Lines "$t\QuestPOIBlob-$Build.csv" @('ID,MapID,UiMapID,Flags,NumPoints,QuestID,ObjectiveIndex,ObjectiveID')
    Write-Lines "$t\QuestPOIPoint-$Build.csv" @('ID,X,Y,Z,QuestPOIBlobID')
    Write-Lines "$t\forever_quest_cache_$Build.jsonl" @($quests.Keys | Sort-Object | ForEach-Object { Cache-Line $_ $quests[$_] })
    # CMaNGOS: 910001, 910007 and the object 910012 start quests and stand somewhere; the others are the recorder's alone.
    Write-Dump "$t\ClassicDB_test.sql.gz" @(@(9001, 'Alpha Quest'), @(9007, 'Eta Quest'), @(9011, 'Kappa Quest')) @(@(910001, 9001), @(910007, 9007)) `
        @(@(1, 910001, 0, 0), @(2, 910007, 400, -400)) @(@(910001, 'Alpha Giver'), @(910007, 'Eta Giver')) `
        @(, @(910012, 9011)) @(, @(3, 910012, -400, -400)) @(, @(910012, 'Kappa Chest Old'))
    Write-Probe "$t\forever_probe_70900\QCForeverProbe.lua" $Givers
    Write-Lines "$root\decisions.csv" @('Game,Quest,Decision,Reason')
    Write-Lines "$root\givers.csv" @('Quest,Npc,Name,Note')
    Write-Lines "$root\zones.csv" @('Quest,Zone,Name,Note')
    Write-Lines "$root\holidays.csv" @('Quest,Name,Holiday,Decision,Evidence')
    # Retail's data (step 6d reads it) and Forever's data from an earlier import, which has every quest but 9006.
    [IO.File]::WriteAllText("$root\data\quests.jsonl", '{"id":100,"name":"Retail","level":10,"zone":"","category":10,"type":1,"faction":2,"race":67108863,"class":8191}' + "`n")
    [IO.File]::WriteAllText("$root\data\pins.jsonl", '{"map":84,"icon":1,"name":"Retail Giver","x":50,"y":50,"quests":[100]}' + "`n")
    $old = @($quests.Keys | Sort-Object | Where-Object { $ZetaKnown -or $_ -ne 9006 } | ForEach-Object {
        '{"id":' + $_ + ',"name":"' + $quests[$_] + '","level":10,"zone":"Alpha Zone","category":10,"type":1,"faction":3,"race":0,"class":8191}' })
    [IO.File]::WriteAllText("$root\data\forever\quests.jsonl", ($old -join "`n") + "`n")
    [IO.File]::WriteAllText("$root\data\forever\pins.jsonl", '{"map":1411,"icon":1,"name":"Old Pin","x":5,"y":5,"quests":[9001]}' + "`n")
    [IO.File]::WriteAllText("$root\addon\QuestCompletist.toc", "## Interface: 120100, 120105`r`n")
    [IO.File]::WriteAllText("$root\addon\QuestCompletist_Camelot.toc", "## Interface: 16001`r`n")
    Copy-Item (Join-Path $PSScriptRoot '..\QuestCompletist\qcCore.lua') "$root\addon\qcCore.lua"
    return $root
}

function Run-Script([string]$script, [string[]]$arguments) {
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $script @arguments 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $saved }
    return @{ Text = ($output -join "`n"); Exit = $LASTEXITCODE }
}

# Step 6d on the world, as a sweep runs it before step 10.
function Invoke-MergeTool([string]$root, [string[]]$more = @()) {
    return Run-Script $MergeTool (@('-ToolsDir', "$root\tools", '-DataDir', "$root\data", '-AddonDir', "$root\addon", '-LedgerFile', "$root\ledger.csv",
        '-DecisionsFile', "$root\none.csv", '-GiverDecisionsFile', "$root\none.csv", '-NpcIdDecisionsFile', "$root\none.csv",
        '-ReportFile', "$root\report.txt", '-ForeverBuild', $Build, '-LuaExe', $LuaExe) + $more)
}

# Step 10's importer on the world.
function Invoke-Importer([string]$root, [string[]]$more = @(), [string]$ledger = "$root\ledger.csv") {
    return Run-Script $Importer (@('-ToolsDir', "$root\tools", '-DataDir', "$root\data\forever", '-Build', $Build, '-ProbeFile', "$root\tools\forever_probe_70900\QCForeverProbe.lua",
        '-CmangosDump', "$root\tools\ClassicDB_test.sql.gz", '-CacheFile', "$root\tools\forever_quest_cache_$Build.jsonl",
        '-DecisionsFile', "$root\decisions.csv", '-GiverFile', "$root\givers.csv", '-ZoneFile', "$root\zones.csv", '-HolidayFile', "$root\holidays.csv",
        '-LedgerFile', $ledger, '-AddonDir', "$root\addon", '-ReviewFile', "$root\review.csv", '-RemovalsFile', "$root\removals.csv", '-LuaExe', $LuaExe) + $more)
}

function Get-WorldPins([string]$root) {
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($pin in (Read-PinData "$root\data\forever")) { $all.Add($pin) }
    return , $all.ToArray()
}
function Pins-Of($pins, [int]$quest) {
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($pin in $pins) { if (@($pin.quests) -contains $quest) { $found.Add($pin) } }
    return , $found.ToArray()
}
function Place-Of($pin) { return "$(([decimal]$pin.x).ToString('0.##', $script:Invariant)),$(([decimal]$pin.y).ToString('0.##', $script:Invariant))" }
function Places-Of($pins, [int]$quest) {
    $places = New-Object System.Collections.Generic.List[string]
    foreach ($pin in (Pins-Of $pins $quest)) { $places.Add((Place-Of $pin)) }
    return (($places | Sort-Object { $_ }) -join ' ')
}
function Review-Kinds([string]$root) { return @(Import-Csv "$root\review.csv") }
function Hash-Of([string]$path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash }
function Hash-Data([string]$root) { return ((Get-ChildItem "$root\data\forever" -File | Sort-Object Name | ForEach-Object { "$($_.Name)=$(Hash-Of $_.FullName)" }) -join ';') }

# A row in the ledger as a person or a player's file would have left it.
function Add-LedgerRow([string]$root, [string]$role, [string]$kind, [int]$npc, [string]$src, [string]$name = '', [string]$map = '', [string]$x = '', [string]$y = '', [string]$quest = '', [string]$game = 'forever') {
    $ledger = Read-RecordedLedger "$root\ledger.csv"
    $row = New-RecordedRow $game $role
    $row.Kind = $kind; $row.Npc = "$npc"; $row.Name = $name; $row.Map = $map; $row.X = $x; $row.Y = $y; $row.Quest = $quest
    $row.FirstBuild = '70900'; $row.LastBuild = '70900'; $row.Src = $src
    $ledger[(Get-RecordedKey $row)] = $row
    [void](Save-RecordedLedger $ledger "$root\ledger.csv")
}

try {
    # ---------- A: a first import, after step 6d ----------
    $w = New-World 'base'
    $r = Invoke-MergeTool $w
    Equal $r.Exit 0 "A1: step 6d reads the probe file into the ledger ($($r.Text))"
    $ledgerRows = @((Read-RecordedLedger "$w\ledger.csv").Values)
    Check (@($ledgerRows | Where-Object { $_.Role -eq 'spot' -and $_.Npc -eq '910003' }).Count -eq 2) 'A1: and the ledger holds both places of 910003'
    Check (@($ledgerRows | Where-Object { $_.Role -eq 'offer' -and $_.Quest -eq '9006' }).Count -eq 0) 'A1: but not the offer of a quest the data lacks'
    # Players' notes: one player alone (untrusted), two players together (trusted), the addon's own file (trusted).
    Add-LedgerRow $w 'giver' 'Creature' 910002 'p01=1' 'Beta Giver'
    Add-LedgerRow $w 'spot' 'Creature' 910002 'p01=3' '' '1411' '30' '30'
    Add-LedgerRow $w 'offer' 'Creature' 910002 'p01=1' '' '' '' '' '9002'
    Add-LedgerRow $w 'giver' 'Creature' 910008 'p01=1;p02=1' 'Theta Giver'
    Add-LedgerRow $w 'spot' 'Creature' 910008 'p01=2;p02=2' '' '1411' '80' '80'
    Add-LedgerRow $w 'offer' 'Creature' 910008 'p01=1;p02=1' '' '' '' '' '9008'
    Add-LedgerRow $w 'giver' 'Creature' 910010 'own-forever=2' 'Iota Giver'
    Add-LedgerRow $w 'spot' 'Creature' 910010 'own-forever=2' '' '1411' '90' '90'
    Add-LedgerRow $w 'offer' 'Creature' 910010 'own-forever=2' '' '' '' '' '9010'
    $r = Invoke-Importer $w
    Equal $r.Exit 0 "A2: the importer runs ($($r.Text))"
    $pins = Get-WorldPins $w
    Equal (Places-Of $pins 9001) '52,51' 'A3: a recorded place wins over CMaNGOS''s spawn of that giver (50,50)'
    $alpha = (Pins-Of $pins 9001)[0]
    Equal $alpha.npc 910001 'A3: and the pin names the giver'
    Equal $alpha.name 'Alpha Giver' 'A3: with the name the ledger holds'
    Equal (Places-Of $pins 9007) '70,30' 'A4: a giver the recorder never met keeps CMaNGOS''s spawn'
    Equal (Places-Of $pins 9003) '20,20' 'A5: two places 1.4 points apart are one pin, at the more visited'
    Equal (Places-Of $pins 9004) '40,40 41.6,40' 'A6: two places 1.6 points apart are two pins'
    Equal (Places-Of $pins 9005) '60,60 63,60' 'A7: and so are two 3 points apart'
    Equal (Places-Of $pins 9002) '' 'A8: what only one player saw decides nothing: no pin'
    Check (@(Review-Kinds $w | Where-Object { $_.Kind -eq 'no giver' -and $_.Quest -eq '9002' }).Count -eq 1) 'A8: and the quest is listed as having no giver'
    Equal (Places-Of $pins 9008) '80,80' 'A9: what two players saw counts'
    $a9 = (Pins-Of $pins 9008)[0]
    Equal $a9.name 'Theta Giver' 'A9: with its name'
    Equal (Places-Of $pins 9010) '90,90' 'A10: a giver only the addon''s own notes saw gets its pin: the ledger, not the probe file, is the source'
    Equal (Places-Of $pins 9006) '' 'A11: a quest the data lacked when step 6d ran has no recorded offer yet'
    Check (@(Review-Kinds $w | Where-Object { $_.Kind -like 'recorded offer not in the ledger yet*' -and $_.Quest -eq '9006' }).Count -eq 1) 'A11: and the review says to run step 6d again'
    Check ($r.Text -match 'Recorded givers \(the ledger''s Forever rows\): 7 with a place, 9 places, 6 quests with an offer; 3 rows wait for a second source') "A12: the summary counts what the ledger gave ($($r.Text))"
    $first = Hash-Data $w
    $firstReview = Hash-Of "$w\review.csv"

    # ---------- B: the quest the data lacked, once the data has it ----------
    $r = Invoke-MergeTool $w
    Equal $r.Exit 0 'B1: step 6d again, now that the data has quest 9006'
    Check (@((Read-RecordedLedger "$w\ledger.csv").Values | Where-Object { $_.Role -eq 'offer' -and $_.Quest -eq '9006' }).Count -eq 1) 'B1: keeps the offer'
    $r = Invoke-Importer $w
    Equal $r.Exit 0 "B2: the importer runs again ($($r.Text))"
    $pins = Get-WorldPins $w
    Equal (Places-Of $pins 9006) '10,10' 'B2: and the quest gets its pin'
    Equal @(Review-Kinds $w | Where-Object { $_.Kind -like 'recorded offer not in the ledger yet*' }).Count 0 'B2: and the review no longer says to run step 6d'
    Equal (Places-Of $pins 9004) '40,40 41.6,40' 'B2: the other pins are as they were'

    # ---------- C: a rerun changes nothing ----------
    $before = Hash-Data $w
    $beforeReview = Hash-Of "$w\review.csv"
    $r = Invoke-Importer $w
    Equal $r.Exit 0 'C1: a rerun on its own output runs'
    Equal (Hash-Data $w) $before 'C1: and writes every data file byte for byte as it was'
    Equal (Hash-Of "$w\review.csv") $beforeReview 'C1: and the review list too'
    $r = Invoke-Importer $w @('-WhatIf')
    Equal $r.Exit 0 'C2: -WhatIf runs'
    Equal (Hash-Data $w) $before 'C2: and writes no data file'

    # ---------- D: a stale ledger stops the import ----------
    $probe = "$w\tools\forever_probe_70900\QCForeverProbe.lua"
    $good = [IO.File]::ReadAllText($probe)
    $stale = (Get-ProbeGivers) + @(, (G 'Creature' 910009 'Late Giver' @(, @(1411, 15, 15, 1)) @(9003)))
    Write-Probe $probe $stale
    $dataBefore = Hash-Data $w
    $reviewBefore = Hash-Of "$w\review.csv"
    $r = Invoke-Importer $w
    Check ($r.Exit -ne 0) 'D1: a probe file with a giver the ledger lacks stops the import'
    Check ($r.Text -match 'Import-RecordedGivers\.ps1' -and $r.Text -match 'step 6d') "D1: and says to run step 6d first ($($r.Text))"
    Check ($r.Text -match "giver Creature:910009 'Late Giver'" -and $r.Text -match 'spot of Creature:910009 on map 1411 at 15,15' -and $r.Text -match 'offer of quest 9003 by Creature:910009') 'D1: and names what the ledger lacks'
    Check ($r.Text -match 'Nothing was written') 'D1: and that nothing was written'
    Equal (Hash-Data $w) $dataBefore 'D1: no data file changed'
    Equal (Hash-Of "$w\review.csv") $reviewBefore 'D1: nor the review list'
    $r = Invoke-Importer $w @('-WhatIf')
    Check ($r.Exit -ne 0) 'D2: -WhatIf stops too: its review list would be as wrong'
    $r = Invoke-MergeTool $w
    Equal $r.Exit 0 'D3: step 6d on the new file'
    $r = Invoke-Importer $w
    Equal $r.Exit 0 "D3: lets the importer run ($($r.Text))"
    Equal (Places-Of (Get-WorldPins $w) 9003) '15,15 20,20' 'D3: and the new giver''s pin is there'

    # The number counts: the file's visits must be in the ledger.
    $more = (Get-ProbeGivers) + @(, (G 'Creature' 910009 'Late Giver' @(, @(1411, 15, 15, 1)) @(9003)))
    $more[0].Spots = @(, @(1411, 52, 51, 6))
    Write-Probe $probe $more
    $r = Invoke-Importer $w
    Check ($r.Exit -ne 0 -and $r.Text -match 'seen 6 times in the file and 4 in the ledger') "D4: a spot seen more often in the file than in the ledger stops it ($($r.Text))"
    $r = Invoke-MergeTool $w
    $r = Invoke-Importer $w
    Equal $r.Exit 0 'D4: step 6d catches the ledger up'
    $fewer = (Get-ProbeGivers) + @(, (G 'Creature' 910009 'Late Giver' @(, @(1411, 15, 15, 1)) @(9003)))
    $fewer[0].Spots = @(, @(1411, 52, 51, 2))
    Write-Probe $probe $fewer
    $r = Invoke-Importer $w
    Equal $r.Exit 0 'D5: a ledger that holds more than the file is not stale (it only grows)'

    # Notes step 6d leaves out do not make a ledger stale.
    $odd = (Get-ProbeGivers) + @(, (G 'Creature' 910009 'Late Giver' @(, @(1411, 15, 15, 1)) @(9003)))
    $odd += (G 'Creature' 910011 'Nowhere Giver' @(, @(9999, 15, 15, 1)) @(99999))
    Write-Probe $probe $odd
    $r = Invoke-MergeTool $w
    $kept = @((Read-RecordedLedger "$w\ledger.csv").Values | Where-Object { $_.Npc -eq '910011' })
    Check (@($kept | Where-Object { $_.Role -eq 'giver' }).Count -eq 1 -and @($kept | Where-Object { $_.Role -ne 'giver' }).Count -eq 0) 'D6: step 6d keeps the giver of a map the game lacks and of a quest the data lacks, but not that spot or offer'
    $r = Invoke-Importer $w
    Equal $r.Exit 0 "D6: so the importer does not look for them ($($r.Text))"

    # No ledger at all.
    Write-Probe $probe (Get-ProbeGivers)
    $r = Invoke-Importer $w @() "$w\no-such-ledger.csv"
    Check ($r.Exit -ne 0 -and $r.Text -match 'step 6d') 'D7: a missing ledger with a probe file that holds notes stops the import'
    Write-Probe $probe @()
    $r = Invoke-Importer $w @() "$w\no-such-ledger.csv"
    Equal $r.Exit 0 "D8: and a probe file with no notes needs none ($($r.Text))"
    Equal (Places-Of (Get-WorldPins $w) 9001) '50,50' 'D8: a giver the ledger lacks then has CMaNGOS''s spawn'

    # A file that is not Forever's.
    Write-Probe $probe (Get-ProbeGivers) '12.1.0.69933'
    $r = Invoke-Importer $w
    Check ($r.Exit -ne 0 -and $r.Text -match 'not Forever''s') "D9: a probe file of another game stops the import ($($r.Text))"

    # A file of a version the TOCs don't name yet, as on a new Forever version.
    Write-Probe $probe (Get-ProbeGivers) '1.61.0.71000'
    $r = Invoke-Importer $w
    Check ($r.Exit -ne 0 -and $r.Text -match 'none of its builds are read' -and $r.Text -match 'versions read are [^:]*1\.60\.:' -and $r.Text -match 'with -Builds, here and to step 6d') "D10: a probe file of a version the TOCs don't name stops the import and says to pass it with -Builds ($($r.Text))"
    $r = Invoke-MergeTool $w @('-Builds', '1.61.')
    Equal $r.Exit 0 "D10: step 6d reads it with -Builds ($($r.Text))"
    $r = Invoke-Importer $w @('-Builds', '1.61.')
    Equal $r.Exit 0 "D10: and so does the importer ($($r.Text))"
    [IO.File]::WriteAllText($probe, $good)

    # ---------- E: the trust rule, on rows one player and two players left ----------
    $w2 = New-World 'trust' -ZetaKnown
    $r = Invoke-MergeTool $w2
    Add-LedgerRow $w2 'giver' 'Creature' 910002 'p01=1' 'Beta Giver'
    Add-LedgerRow $w2 'spot' 'Creature' 910002 'p01=3' '' '1411' '30' '30'
    Add-LedgerRow $w2 'offer' 'Creature' 910002 'p01=1' '' '' '' '' '9002'
    # A lone player's name and place for a giver the maintainer met change neither its name nor its place.
    Add-LedgerRow $w2 'giver' 'Creature' 910001 'p01=1' 'Impostor'
    Add-LedgerRow $w2 'spot' 'Creature' 910001 'p01=9' '' '1411' '11' '11'
    # The name is checked on an object: a creature's pin takes the probe's NPC list first, so a recorded
    # creature name could not show either way. The ledger's trusted name beats CMaNGOS's for an object.
    Add-LedgerRow $w2 'giver' 'GameObject' 910012 'own-forever=1' 'Kappa Chest'
    Add-LedgerRow $w2 'spot' 'GameObject' 910012 'own-forever=2' '' '1411' '75' '75'
    Add-LedgerRow $w2 'offer' 'GameObject' 910012 'own-forever=1' '' '' '' '' '9011'
    Add-LedgerRow $w2 'giver' 'GameObject' 910012 'p01=1' 'Impostor Chest'
    $r = Invoke-Importer $w2
    Equal $r.Exit 0 "E1: the importer runs with a lone player's rows in the ledger ($($r.Text))"
    $pins = Get-WorldPins $w2
    Equal (Places-Of $pins 9001) '52,51' 'E1: a lone player''s place for a known giver adds no pin and moves none'
    $kappa = Pins-Of $pins 9011
    Equal (Places-Of $pins 9011) '75,75' 'E1: an object''s recorded place wins over its CMaNGOS spawn (70,70)'
    Equal $kappa[0].name 'Kappa Chest' 'E1: and a lone player''s name for it changes nothing: the trusted name stands, not CMaNGOS''s'
    Equal (Places-Of $pins 9002) '' 'E1: a giver only a lone player met has no pin'
    Check ($r.Text -match '6 rows wait for a second source and are not used') "E1: and the summary counts the rows left unused ($($r.Text))"
    # The same giver under a second player becomes known.
    Add-LedgerRow $w2 'giver' 'Creature' 910002 'p01=1;p02=1' 'Beta Giver'
    Add-LedgerRow $w2 'spot' 'Creature' 910002 'p01=3;p02=1' '' '1411' '30' '30'
    Add-LedgerRow $w2 'offer' 'Creature' 910002 'p01=1;p02=1' '' '' '' '' '9002'
    $r = Invoke-Importer $w2
    Equal (Places-Of (Get-WorldPins $w2) 9002) '30,30' 'E2: a second player makes it count'
    # Two trusted names for one giver: none is used.
    Add-LedgerRow $w2 'giver' 'Creature' 910008 'own-forever=1' 'Theta Giver'
    Add-LedgerRow $w2 'giver' 'Creature' 910008 'own-forever=1' 'Theta Giver, Elder'
    Add-LedgerRow $w2 'spot' 'Creature' 910008 'own-forever=1' '' '1411' '80' '80'
    Add-LedgerRow $w2 'offer' 'Creature' 910008 'own-forever=1' '' '' '' '' '9008'
    $r = Invoke-Importer $w2
    $theta = Pins-Of (Get-WorldPins $w2) 9008
    Equal $theta.Count 1 'E3: a giver whose trusted names disagree still gets its pin'
    Check ($theta[0].name -cne 'Theta Giver' -and $theta[0].name -cne 'Theta Giver, Elder') "E3: but under neither name (got '$($theta[0].name)')"
    Check (@(Review-Kinds $w2 | Where-Object { $_.Kind -like 'recorded giver: trusted sources disagree*' -and $_.Other -eq 'Creature:910008' }).Count -eq 1) 'E3: and the review lists the disagreement'

    # ---------- F: the edge of a place, Test-NearPlace's 1.5 map points ----------
    Add-LedgerRow $w2 'giver' 'Creature' 910013 'own-forever=1' 'Lambda Giver'
    Add-LedgerRow $w2 'spot' 'Creature' 910013 'own-forever=3' '' '1411' '30' '50'
    Add-LedgerRow $w2 'spot' 'Creature' 910013 'own-forever=1' '' '1411' '31.5' '50'
    Add-LedgerRow $w2 'offer' 'Creature' 910013 'own-forever=1' '' '' '' '' '9012'
    Add-LedgerRow $w2 'giver' 'Creature' 910014 'own-forever=1' 'Mu Giver'
    Add-LedgerRow $w2 'spot' 'Creature' 910014 'own-forever=3' '' '1411' '30' '60'
    Add-LedgerRow $w2 'spot' 'Creature' 910014 'own-forever=1' '' '1411' '31.51' '60'
    Add-LedgerRow $w2 'offer' 'Creature' 910014 'own-forever=1' '' '' '' '' '9013'
    $r = Invoke-Importer $w2
    Equal $r.Exit 0 "F1: the importer runs ($($r.Text))"
    $pins = Get-WorldPins $w2
    Equal (Places-Of $pins 9012) '30,50' 'F1: two places exactly 1.5 points apart are one place, at the more visited'
    Equal (Places-Of $pins 9013) '30,60 31.51,60' 'F2: 1.51 points apart they are two'

    # ---------- G: the ledger's retail rows are not Forever's ----------
    $before = Hash-Data $w2
    $beforeReview = Hash-Of "$w2\review.csv"
    $beforeSummary = @($r.Text -split "`n" | Where-Object { $_ -like 'Recorded givers*' })
    Add-LedgerRow $w2 'giver' 'Creature' 910007 'own-retail=1' 'Eta Retail' -game 'retail'
    Add-LedgerRow $w2 'spot' 'Creature' 910007 'own-retail=5' '' '1411' '11' '11' -game 'retail'
    Add-LedgerRow $w2 'offer' 'Creature' 910007 'own-retail=1' '' '' '' '' '9007' -game 'retail'
    Add-LedgerRow $w2 'giver' 'Creature' 910015 'own-retail=1' 'Nu Retail' -game 'retail'
    Add-LedgerRow $w2 'spot' 'Creature' 910015 'own-retail=2' '' '1411' '12' '12' -game 'retail'
    Add-LedgerRow $w2 'offer' 'Creature' 910015 'own-retail=1' '' '' '' '' '9007' -game 'retail'
    $r = Invoke-Importer $w2
    Equal $r.Exit 0 "G1: the importer runs with retail rows in the ledger ($($r.Text))"
    $pins = Get-WorldPins $w2
    Equal (Places-Of $pins 9007) '70,30' 'G1: retail rows for the same NPC ID neither move its Forever pin nor add one'
    $eta = Pins-Of $pins 9007
    Equal $eta[0].name 'Eta Giver' 'G1: nor name it'
    Equal (Hash-Data $w2) $before 'G2: every data file is as it was without the retail rows'
    Equal (Hash-Of "$w2\review.csv") $beforeReview 'G2: and the review list'
    Equal (@($r.Text -split "`n" | Where-Object { $_ -like 'Recorded givers*' }) -join '') ($beforeSummary -join '') 'G2: and the summary''s count of recorded givers'

    # ---------- H: master's output when the ledger holds the probe's file alone ----------
    # With only the probe's notes in the ledger, the importer must write $MasterOutput, master's files on this
    # world. Delta is left out: its places are 1.6 points apart, which master's 3-point box made one pin and
    # the 1.5-point radius makes two (A6).
    $w3 = New-World 'same' -ZetaKnown -Givers @(Get-ProbeGivers | Where-Object { $_.Id -ne 910004 })
    $r = Invoke-MergeTool $w3
    Equal $r.Exit 0 "H1: step 6d reads the probe's file alone ($($r.Text))"
    $r = Invoke-Importer $w3
    Equal $r.Exit 0 "H1: the importer runs ($($r.Text))"
    foreach ($file in $MasterOutput.Keys) {
        Equal ([IO.File]::ReadAllText("$w3\$file")) $MasterOutput[$file] "H1: $file is master's, byte for byte"
    }
}
finally {
    if ($Keep) { Write-Output "Scratch kept: $Scratch" } else { Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
