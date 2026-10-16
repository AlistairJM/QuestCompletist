<#
Checks Apply-QuestScaling.ps1 and QuestScaling.ps1 on quests, a quest cache, a task table, probe saved
variables, a redirect table, a QuestV2 table, a redirect baseline and unavailable decisions made here, in a
scratch folder: nothing in the checkout is read or written (but the scripts themselves). One world holds a
quest for each way a ceiling can come out: probed on its tuning or only
sharing it, at its minimum (with an own level of its minimum, below it, above it or of 0) or below it, a
level of 0, a tuning from the task table, a split tuning, tuning 0,
no tuning, a tuning only a placeholder row, a refusal, a level of 0 or another build's row speaks for, and a
maxLevel that is added, changed, taken away or kept. Its quests' tunings are added, changed, taken away
(tuning 0) and kept (no source), and its tunings are redirected or not, sampled, split or unprobed, so
tunings.jsonl and the Lua's qcQuestTuning and qcTuningSample are checked against what they must hold.
The rest changes one thing at a time: -WhatIf and
-Check, a second run, the level-cap check (a run below the cap, a run with no level, a build whose cap
isn't known, -Cap), a probe of another build than the quest cache, the agreement thresholds, a sample the
probe no longer loads or that moved tuning, the order samples are taken in and -Samples, stored samples
that stay when a fuller probe loads more, give way to a better kind or to a lower -Samples, a tuning whose
level moved, and the redirect table against its baseline (a new RedirectEnum, one gone, another row count,
no baseline, -UpdateBaseline, which -WhatIf refuses).
A Forever world checks -Game forever: it passes while every loaded quest has its stored level, fails on a
level the game doesn't give, on a maxLevel, on a tuning or on a tunings.jsonl, and writes nothing. The
shared functions are checked one at a time, and so are AddonData.ps1's checks of tunings.jsonl and the
tables it builds from it.

The last section runs the tool on the real files, when they are there: -RealToolsDir (this folder by
default) with the newest retail probe, its build's quest cache and the task table (the tool downloads the
redirect table and QuestV2 into it when it lacks them). It copies the checkout's data into the scratch
folder, takes every maxLevel and tuning out and tunings.jsonl away, applies, and checks that only maxLevel
and tuning fields are added, every maxLevel above the quest's minimum, and that a second run changes
nothing. It says whether the result is the checkout's own data, tunings.jsonl included, and whether the
redirect table has a RedirectEnum the checkout's baseline lacks.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-QuestScaling.ps1 [-RealToolsDir <tools folder with the data>]

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param([string]$RealToolsDir = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$savedCulture = [Threading.Thread]::CurrentThread.CurrentCulture
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
. "$PSScriptRoot\QuestScaling.ps1"
$Apply = Join-Path $PSScriptRoot 'Apply-QuestScaling.ps1'
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

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("quest-scaling-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$Build = '12.1.5.70400'

# Level, minLevel, maxLevel already held; cache tuning, task-table tuning; the probe's row (result, level,
# trivial, expansion; $null = not asked); the tuning already held, the type and the faction mask.
function New-Quest([int]$level, $minLevel, $maxLevel, $cache, $task, $probe, $tuning = $null, [int]$type = 1, [int]$faction = 0) {
    return @{ Level = $level; MinLevel = $minLevel; MaxLevel = $maxLevel; Cache = $cache; Task = $task; Probe = $probe; Tuning = $tuning; Type = $type; Faction = $faction }
}
function New-Row([string]$result, $level = $null, $trivial = $null, $expansion = $null, [string]$build = $Build) {
    return @{ Result = $result; Level = $level; Trivial = $trivial; Expansion = $expansion; Build = $build }
}

function New-World {
    $q = @{}
    $q[1] = New-Quest 30 10 $null 100 $null (New-Row 'ok' 70 $true 6)
    $q[2] = New-Quest 20 $null $null 100 $null (New-Row 'cached' 70 $true 6)
    $q[3] = New-Quest 25 $null $null 100 $null (New-Row 'fail')
    $q[4] = New-Quest 40 $null $null 100 $null $null
    $q[5] = New-Quest 70 $null $null 100 $null $null
    $q[6] = New-Quest 60 75 $null 100 $null $null
    $q[7] = New-Quest 20 $null $null 200 $null (New-Row 'ok' 90 $false 11)
    $q[8] = New-Quest 10 $null $null 200 $null (New-Row 'cached' 0 $false 11)
    $q[9] = New-Quest 15 $null $null 300 $null (New-Row 'cached' 0 $false 11)
    $q[10] = New-Quest 50 $null $null 400 $null (New-Row 'ok' 60 $true 5)
    $q[11] = New-Quest 50 $null $null 400 $null (New-Row 'late' 70 $true 5)
    $q[12] = New-Quest 50 $null 80 400 $null $null
    $q[13] = New-Quest 40 $null 55 0 $null (New-Row 'ok' 50 $true 4) 100
    $q[14] = New-Quest 30 $null 60 $null $null $null 900
    $q[15] = New-Quest 5 $null $null $null 100 $null
    $q[16] = New-Quest 0 $null $null 100 $null $null 555
    $q[17] = New-Quest 30 $null 45 500 $null (New-Row 'fail')
    $q[18] = New-Quest 30 $null $null 600 $null (New-Row 'ok' 40 $true 4 '12.1.0.69933')
    $q[19] = New-Quest 10 $null 65 100 $null $null
    $q[20] = New-Quest 30 $null $null 700 $null (New-Row 'ok' 0 $true 4)
    $q[21] = New-Quest 60 $null $null 200 $null (New-Row 'ok' 90 $false 11)
    $q[22] = New-Quest 50 70 $null 100 $null $null
    $q[23] = New-Quest 80 70 $null 100 $null $null
    $q[24] = New-Quest 0 70 $null 100 $null $null
    return $q
}
# What each quest's maxLevel must be after a run of the world above, and its tuning.
$Wanted = @{ 1 = 70; 2 = 70; 3 = 70; 4 = 70; 5 = $null; 6 = $null; 7 = 90; 8 = 90; 9 = $null; 10 = $null; 11 = $null; 12 = $null
    13 = $null; 14 = 60; 15 = 70; 16 = 70; 17 = 45; 18 = $null; 19 = 70; 20 = $null; 21 = 90; 22 = $null; 23 = $null; 24 = $null }
$WantedTuning = @{ 1 = 100; 2 = 100; 3 = 100; 4 = 100; 5 = 100; 6 = 100; 7 = 200; 8 = 200; 9 = 300; 10 = 400; 11 = 400; 12 = 400
    13 = $null; 14 = 900; 15 = 100; 16 = 100; 17 = 500; 18 = 600; 19 = 100; 20 = 700; 21 = 200; 22 = 100; 23 = 100; 24 = 100 }
# The world's redirect table: a row redirects tunings 100 (two), 200, 300, 400 and 700; none names 500, 600 or 900.
$Redirects = @('ID,OrderIndex,RedirectContentTuningID,RedirectFlag,RedirectEnum,ParentContentTuningID',
    '1,0,1000,1,0,100', '2,1,1001,0,34,100', '3,0,1002,8192,13,200', '4,0,1001,0,34,300', '5,0,1001,0,34,400', '6,0,1003,32,5,700')
$Baseline = @('"Build","RedirectEnum","Rows"', "`"$Build`",`"0`",`"1`"", "`"$Build`",`"5`",`"1`"", "`"$Build`",`"13`",`"1`"", "`"$Build`",`"34`",`"3`"")
$WantedTunings = "{`"id`":100,`"level`":70,`"redirects`":[0,34],`"samples`":[1,2]}`n{`"id`":200,`"level`":90,`"redirects`":[13],`"samples`":[7,21]}`n"

function Write-Probe([string]$path, $quests, [string]$runs) {
    $rows = foreach ($id in ($quests.Keys | Sort-Object)) {
        $p = $quests[$id].Probe
        if (-not $p) { continue }
        $row = '[' + $id + '] = {build = "' + $p.Build + '", result = "' + $p.Result + '"'
        if ($null -ne $p.Level) { $row += ', level = ' + $p.Level }
        if ($null -ne $p.Trivial) { $row += ', trivial = ' + $(if ($p.Trivial) { 'true' } else { 'false' }) }
        if ($null -ne $p.Expansion) { $row += ', expansion = ' + $p.Expansion }
        $row + '},'
    }
    [IO.File]::WriteAllText($path, "QCForeverProbeDB = {`nquests = {`n$($rows -join "`n")`n},`nnpcs = {},`ngivers = {},`nstarted = {},`naccepted = {},`nmaps = {},`nlogins = {},`nruns = {`n$runs`n},`n}`n", $utf8)
}
function New-Run([int]$level, [string]$build = $Build, [string]$character = 'Alliance Human MAGE') {
    $at = if ($level -gt 0) { ", level = $level" } else { '' }
    return '{kind = "quests", build = "' + $build + '", time = 5, character = "' + $character + '"' + $at + ', answered = 9, asked = 9, facts = {trivial = "C_QuestLog.IsQuestTrivial"}, trivialRange = {UnitQuestTrivialLevelRange = 5, UnitQuestTrivialLevelRangeScaling = 5}},'
}
function Write-Cache([string]$dir, $quests, [string]$cacheBuild = $Build) {
    $cache = foreach ($id in ($quests.Keys | Sort-Object)) {
        if ($null -ne $quests[$id].Cache) { '{"id":' + $id + ',"title":"Quest ' + $id + '","contentTuning":' + $quests[$id].Cache + ',"sort":0,"questType":2}' }
    }
    [IO.File]::WriteAllText("$dir\tools\retail_quest_cache_$cacheBuild.jsonl", ((@($cache) -join "`n") + "`n"), $utf8)
}
function Get-ProbeFile([string]$dir) { return (Get-ChildItem "$dir\tools\retail_probe_*\QCForeverProbe.lua" | Select-Object -First 1).FullName }

# $v2 lists the quests in QuestV2 (all of the world's when $null); $unavailable the ones flagged; $baseline
# the baseline's lines, or $null for no file.
function Write-World([string]$name, $quests, [string]$runs = (New-Run 90), [string]$probeBuild = '', [string]$cacheBuild = $Build,
    [string[]]$redirects = $Redirects, $baseline = $Baseline, $v2 = $null, $unavailable = @()) {
    $dir = Join-Path $Scratch $name
    $probeDir = "$dir\tools\retail_probe_" + ($(if ($probeBuild) { $probeBuild } else { $Build }) -replace '^.*\.', '')
    New-Item -ItemType Directory $probeDir, "$dir\data", "$dir\addon" -Force | Out-Null
    $data = @(); $task = @('ID,QuestTitle_lang,ContentTuningID')
    foreach ($id in ($quests.Keys | Sort-Object)) {
        $q = $quests[$id]
        $line = '{"id":' + $id + ',"name":"Quest ' + $id + '","level":' + $q.Level + ',"zone":"Zone","category":1,"type":' + $q.Type + ',"faction":' + $q.Faction + ',"race":0,"class":0'
        if ($null -ne $q.MinLevel) { $line += ',"minLevel":' + $q.MinLevel }
        if ($null -ne $q.MaxLevel) { $line += ',"maxLevel":' + $q.MaxLevel }
        if ($null -ne $q.Tuning) { $line += ',"tuning":' + $q.Tuning }
        $data += $line + '}'
        if ($null -ne $q.Task) { $task += "$id,Quest $id,$($q.Task)" }
    }
    [IO.File]::WriteAllText("$dir\data\quests.jsonl", (($data -join "`n") + "`n"), $utf8)
    [IO.File]::WriteAllText("$dir\data\pins.jsonl", '{"map":84,"icon":1,"npc":29611,"name":"A Pin","x":26.12,"y":47.32,"quests":[1]}' + "`n", $utf8)
    Write-Cache $dir $quests $cacheBuild
    [IO.File]::WriteAllText("$dir\tools\QuestV2CliTask.csv", (($task -join "`n") + "`n"), $utf8)
    [IO.File]::WriteAllText("$dir\tools\ConditionalContentTuning-$cacheBuild.csv", (($redirects -join "`n") + "`n"), $utf8)
    $inV2 = if ($null -ne $v2) { @($v2) } else { @($quests.Keys | Sort-Object) }
    [IO.File]::WriteAllText("$dir\tools\QuestV2-$cacheBuild.csv", ((@('ID,UniqueBitFlag,UiQuestDetailsThemeID') + @($inV2 | ForEach-Object { "$_,1,0" })) -join "`n") + "`n", $utf8)
    $flags = @('"QuestID","Name","Zone","Reason","Decision","Evidence"') + @($unavailable | ForEach-Object { "`"$_`",`"Quest $_`",`"Zone`",`"1`",`"FLAG`",`"test`"" })
    [IO.File]::WriteAllText("$dir\unavailable.csv", (($flags -join "`n") + "`n"), $utf8)
    if ($null -ne $baseline) { [IO.File]::WriteAllText("$dir\baseline.csv", ((@($baseline) -join "`r`n") + "`r`n"), $utf8) }
    Write-Probe "$probeDir\QCForeverProbe.lua" $quests $runs
    $result = Invoke-AddonDataBuild -DataDir "$dir\data" -AddonDir "$dir\addon"
    if (-not $result.Ok) { throw "The scratch world $name didn't build: $($result.Lines -join '; ')" }
    return $dir
}

function Invoke-Tool([string]$dir, [hashtable]$more = @{}) {
    $params = @{ ToolsDir = "$dir\tools"; DataDir = "$dir\data"; AddonDir = "$dir\addon"; MinProbed = 1; MinAgreement = 0.5
        BaselineFile = "$dir\baseline.csv"; UnavailableFile = "$dir\unavailable.csv" }
    foreach ($k in $more.Keys) { $params[$k] = $more[$k] }
    $global:LASTEXITCODE = 0
    $failure = ''
    $lines = @()
    try { $lines = @(& $Apply @params *>&1 | ForEach-Object { "$_" }) } catch { $failure = $_.Exception.Message }
    if ($env:QUEST_SCALING_TEST_VERBOSE) { Write-Host "---- run (exit $global:LASTEXITCODE) $failure"; $lines | ForEach-Object { Write-Host "     $_" } }
    return @{ Text = (($lines + $failure) -join "`n"); Exit = $global:LASTEXITCODE; Failure = $failure }
}

function Get-Hashes([string]$dir) {
    $hashes = @()
    foreach ($file in "data\quests.jsonl", "data\pins.jsonl", "data\tunings.jsonl", "addon\qcQuestData.lua", "addon\qcPinDB.lua") {
        $hashes += $(if (Test-Path "$dir\$file") { (Get-FileHash "$dir\$file").Hash } else { 'none' })
    }
    return $hashes -join ','
}

function Get-Records([string]$dir) {
    $records = @{}
    foreach ($line in [IO.File]::ReadAllLines("$dir\data\quests.jsonl")) { $r = $line | ConvertFrom-Json; $records[[int]$r.id] = $r }
    return $records
}

function Get-TuningText([string]$dir) {
    $path = "$dir\data\tunings.jsonl"
    if (Test-Path $path) { return [IO.File]::ReadAllText($path) }
    return ''
}

# A table of qcQuestData.lua: each key's value as written, a number or a {list}.
function Get-LuaTable([string]$dir, [string]$table) {
    $text = [IO.File]::ReadAllText("$dir\addon\qcQuestData.lua")
    $block = [regex]::Match($text, "(?s)(?<=\n)$table=\{\r?\n(.*?)\r?\n\}\r?\n").Groups[1].Value
    $entries = @{}
    foreach ($m in [regex]::Matches($block, '\[(\d+)\]=(\{[\d,]*\}|\d+),')) { $entries[[int]$m.Groups[1].Value] = $m.Groups[2].Value }
    return $entries
}

try {
    # --- The rule, one call at a time ------------------------------------------------------------------
    Equal (Get-ShownQuestLevel 30 10 70 90) 70 'S1: at the cap a scaling quest shows its ceiling'
    Equal (Get-ShownQuestLevel 30 10 70 45) 45 'S1: between its minimum and its ceiling, the character''s level'
    Equal (Get-ShownQuestLevel 30 10 70 1) 10 'S1: below its minimum, the minimum'
    Equal (Get-ShownQuestLevel 10 $null 90 5) 10 'S1: with no minLevel the minimum is the level'
    Equal (Get-ShownQuestLevel 0 $null 60 1) 1 'S1: a level of 0 that scales shows the character''s'
    Equal (Get-ShownQuestLevel 50 10 30 90) 30 'S1: a level above the ceiling is held down at the cap'
    Equal (Get-ShownQuestLevel 20 $null $null 90) 20 'S1: a quest with no ceiling shows its own level'
    Equal (Get-ShownQuestLevel 20 5 $null 90) 20 'S1: and so does one with a minLevel and no ceiling (as on Forever)'
    Equal (Get-ShownQuestLevel 40 60 50 90) 60 'S1: a ceiling below the minimum leaves the minimum'
    Check (Test-LowLevel 70 85) 'S1: below the cutoff is low'
    Check (-not (Test-LowLevel 85 85)) 'S1: at it is not'
    Check (-not (Test-LowLevel 0 85)) 'S1: nor is a level of 0'
    Equal (Get-RetailLevelCap '12.1.5.70391') 90 'S2: 12.x builds cap at 90'
    Equal (Get-RetailLevelCap '11.2.7.64000') 80 'S2: 11.x at 80'
    Check ($null -eq (Get-RetailLevelCap '13.0.0.80000')) 'S2: an expansion not listed has no known cap'
    $fake = [pscustomobject]@{ Build = $Build; BuildRuns = @([pscustomobject]@{ Run = 1; Character = 'A'; Level = 90 }, [pscustomobject]@{ Run = 3; Character = 'A'; Level = 90 }) }
    Check (Test-ProbeAtCap $fake 90).Ok 'S3: every quest run at the cap passes'
    $fake.BuildRuns[1].Level = 89
    $at = Test-ProbeAtCap $fake 90
    Check (-not $at.Ok) 'S3: one run below the cap fails'
    Has $at.Problem 'run 3 at level 89' 'S3: and names it'
    $fake.BuildRuns[1].Level = $null
    Has (Test-ProbeAtCap $fake 90).Problem 'run 3 at no recorded level' 'S3: a run with no level fails too'
    Check (-not (Test-ProbeAtCap $fake $null).Ok) 'S3: and any build with no known cap'
    $fake.BuildRuns = @()
    Has (Test-ProbeAtCap $fake 90).Problem 'no quest run' 'S3: as does a file with no quest run on the build'

    # --- Redirects and samples, one call at a time --------------------------------------------------------
    Check (Test-RecurringQuest ([pscustomobject]@{ type = 4 })) 'U1: a daily recurs'
    Check (Test-RecurringQuest ([pscustomobject]@{ type = 128 })) 'U1: and so does a world quest or weekly'
    Check (-not (Test-RecurringQuest ([pscustomobject]@{ type = 64 }))) 'U1: a seasonal quest does not, as the addon counts it one-time'
    Check (Test-BothFactions ([pscustomobject]@{ faction = 3 })) 'U1: faction 3 is both factions'
    Check (Test-BothFactions ([pscustomobject]@{ faction = 0 })) 'U1: and 0 holds none back'
    Check (-not (Test-BothFactions ([pscustomobject]@{ faction = 2 }))) 'U1: 2 is one faction'
    $unit = Join-Path $Scratch 'unit'
    New-Item -ItemType Directory $unit | Out-Null
    $table = Join-Path $unit 'redirects.csv'
    [IO.File]::WriteAllText($table, "ID,OrderIndex,RedirectContentTuningID,RedirectFlag,RedirectEnum,ParentContentTuningID`n1,2,9,0,34,50`n2,0,9,1,0,50`n3,1,9,0,34,50`n4,0,8,8192,13,60`n", $utf8)
    $red = Read-TuningRedirects $table
    Equal $red.Rows 4 'U2: the redirect table''s rows are counted'
    Equal (@($red.ByParent[50]) -join ',') '0,34' 'U2: a tuning''s RedirectEnum values, ascending and each once'
    Equal $red.ByEnum[34] 2 'U2: and the rows of each RedirectEnum'
    [IO.File]::WriteAllText($table, "ID,OrderIndex,RedirectContentTuningID,RedirectFlag,ParentContentTuningID`n1,2,9,0,50`n", $utf8)
    $failure = ''
    try { Read-TuningRedirects $table | Out-Null } catch { $failure = $_.Exception.Message }
    Has $failure "has no 'RedirectEnum' column" 'U2: a table without a column the tool reads is refused'
    $script:Downloads = @()
    $download = { param($uri, $to) $script:Downloads += $uri; [IO.File]::WriteAllText($to, "ID,A`n" + ((1..5 | ForEach-Object { "$_,0" }) -join "`n") + "`n") }
    $got = Get-ClientTableFile $unit 'Table' '1.2.3.4' @('ID', 'A') 4 $download
    Equal (Split-Path -Leaf $got) 'Table-1.2.3.4.csv' 'U3: a table the folder lacks is downloaded under its build'
    Equal ($script:Downloads -join ' ') 'https://wago.tools/db2/Table/csv?build=1.2.3.4' 'U3: from wago.tools, pinned to the build'
    Get-ClientTableFile $unit 'Table' '1.2.3.4' @('ID', 'A') 4 $download | Out-Null
    Equal $script:Downloads.Count 1 'U3: and one already there is not downloaded again'
    $failure = ''
    try { Get-ClientTableFile $unit 'Other' '1.2.3.4' @('ID', 'B') 4 $download | Out-Null } catch { $failure = $_.Exception.Message }
    Has $failure 'has no column B' 'U3: a download that lacks a column is refused'
    Check (-not (Test-Path "$unit\Other-1.2.3.4.csv") -and -not (Test-Path "$unit\Other-1.2.3.4.csv.download")) 'U3: and leaves nothing behind'
    $failure = ''
    try { Get-ClientTableFile $unit 'Short' '1.2.3.4' @('ID', 'A') 5 $download | Out-Null } catch { $failure = $_.Exception.Message }
    Has $failure 'has 5 rows or fewer' 'U3: and so is one with too few rows'
    $ours = @{
        1 = [pscustomobject]@{ type = 1; faction = 3 }; 2 = [pscustomobject]@{ type = 4; faction = 3 }; 3 = [pscustomobject]@{ type = 1; faction = 1 }
        4 = [pscustomobject]@{ type = 1; faction = 3 }; 5 = [pscustomobject]@{ type = 1; faction = 3 }; 6 = [pscustomobject]@{ type = 1; faction = 3 }
    }
    $v2 = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($id in 1, 2, 3, 4, 5, 7) { [void]$v2.Add($id) }
    $flagged = New-Object 'System.Collections.Generic.HashSet[int]'
    [void]$flagged.Add(5)
    Equal ((Get-SampleOrder @(7, 6, 5, 4, 3, 2, 1) $ours $v2 $flagged) -join ',') '1,4,3,2,5,6,7' 'U4: samples go ours, in QuestV2, not flagged, one-time, both factions, then by id'
    Equal ((Get-SampleOrder @(7, 6, 5, 4, 3, 2, 1) $ours $v2 $flagged @(4, 3)) -join ',') '4,1,3,2,5,6,7' 'U4: a stored sample goes before a new one of its kind, but not before a better kind'
    Equal ((@(1, 2, 3, 5, 6, 7) | ForEach-Object { Get-SampleKind $_ $ours $v2 $flagged }) -join ',') '0,2,1,4,8,16' 'U4: each kind weighs more than all the ones after it'

    # --- The data files: tunings.jsonl and the tables built from it -----------------------------------------
    $tunings = @([pscustomobject]@{ id = 5; level = 30; redirects = @(0, 34); samples = @(11, 12) }, [pscustomobject]@{ id = 9; level = 90; redirects = @(13); samples = @(20) })
    Equal (@(Test-TuningRecords $tunings).Count) 0 'D1: sound tuning records pass'
    $bad = @(
        [pscustomobject]@{ id = 0; level = 30; redirects = @(0); samples = @(1) },
        [pscustomobject]@{ id = 7; level = 0; redirects = @(); samples = @(1, 1) },
        [pscustomobject]@{ id = 6; level = 30; redirects = @(34, 0); samples = @(0) })
    $problems = @(Test-TuningRecords $bad) -join "`n"
    Has $problems "line 1 (id 0): 'id' must be a whole number above 0" 'D1: an id of 0 is refused'
    Has $problems "line 2 (id 7): 'level' must be a whole number above 0" 'D1: and a level of 0'
    Has $problems "line 2 (id 7): 'redirects' must list at least one number" 'D1: and no redirects'
    Has $problems "line 2 (id 7): 'samples' names a number twice" 'D1: and a sample named twice'
    Has $problems "line 3 (id 6): the ids must go up, and this one follows 7" 'D1: and ids out of order'
    Has $problems "line 3 (id 6): 'redirects' must go up" 'D1: and redirects out of order'
    Has $problems "line 3 (id 6): 'samples' must hold whole numbers of 1 or more" 'D1: and a sample of 0'
    $quest = { param($id, $tuning) $q = [pscustomobject]@{ id = $id; name = "Q$id"; level = 1; zone = ''; category = 1; type = 1; faction = 0; race = 0; class = 0 }; if ($tuning) { $q | Add-Member tuning $tuning }; $q }
    $three = @((& $quest 11 5), (& $quest 12 8), (& $quest 13 $null))
    $lua = ConvertTo-LuaQuestFile $three 'data' $tunings
    Has $lua "qcQuestTuning={`r`n[11]=5,`r`n}`r`n" 'D2: qcQuestTuning holds the quests on a tuning of tunings.jsonl, and no other'
    Has $lua "qcTuningSample={`r`n[5]={11,12},`r`n[9]={20},`r`n}`r`n" 'D2: and qcTuningSample each record''s samples, in their order'
    Has (ConvertTo-LuaQuestFile $three 'data') "qcQuestTuning={`r`n}`r`nqcTuningSample={`r`n}`r`n" 'D2: with no tunings both tables are empty, as on Forever'
    Equal (ConvertTo-QuestJsonLines @((& $quest 11 5))) "{`"id`":11,`"name`":`"Q11`",`"level`":1,`"zone`":`"`",`"category`":1,`"type`":1,`"faction`":0,`"race`":0,`"class`":0,`"tuning`":5}`n" 'D3: a quest''s tuning is written last'
    Equal (ConvertTo-TuningJsonLines $tunings) "{`"id`":5,`"level`":30,`"redirects`":[0,34],`"samples`":[11,12]}`n{`"id`":9,`"level`":90,`"redirects`":[13],`"samples`":[20]}`n" 'D3: and a tuning record''s fields in their order'
    $files = Join-Path $Scratch 'datafiles'
    New-Item -ItemType Directory "$files\data", "$files\addon" | Out-Null
    [IO.File]::WriteAllText("$files\data\quests.jsonl", "{`"id`":11,`"name`":`"Q11`",`"level`":1,`"zone`":`"`",`"category`":1,`"type`":1,`"faction`":0,`"race`":0,`"class`":0,`"tuning`":0}`n", $utf8)
    [IO.File]::WriteAllText("$files\data\pins.jsonl", '{"map":84,"icon":1,"x":26.12,"y":47.32,"quests":[11]}' + "`n", $utf8)
    [IO.File]::WriteAllText("$files\data\tunings.jsonl", '{"id":5,"level":30,"redirects":[0],"samples":[11],"extra":1}' + "`n", $utf8)
    $built = Invoke-AddonDataBuild -DataDir "$files\data" -AddonDir "$files\addon"
    Check (-not $built.Ok) 'D4: the build refuses bad data'
    Has ($built.Lines -join "`n") "'tuning' must be a whole number above 0" 'D4: a tuning of 0'
    Has ($built.Lines -join "`n") "tunings.jsonl line 1: unknown field 'extra'" 'D4: and a field tunings.jsonl doesn''t have'
    Check (-not (Test-Path "$files\addon\qcQuestData.lua")) 'D4: and writes nothing'
    [IO.File]::WriteAllText("$files\data\quests.jsonl", "{`"id`":11,`"name`":`"Q11`",`"level`":1,`"zone`":`"`",`"category`":1,`"type`":1,`"faction`":0,`"race`":0,`"class`":0,`"tuning`":5}`n", $utf8)
    [IO.File]::WriteAllText("$files\data\tunings.jsonl", '{"id":5,"level":30,"redirects":[0],"samples":[11]}' + "`n", $utf8)
    $built = Invoke-AddonDataBuild -DataDir "$files\data" -AddonDir "$files\addon"
    Check $built.Ok 'D5: sound data builds'
    Has ($built.Lines -join "`n") '1 quests, 1 pins, 1 tunings' 'D5: and counts the tunings'
    Equal (Get-LuaTable $files 'qcTuningSample')[5] '{11}' 'D5: qcTuningSample comes from tunings.jsonl'
    Equal (Get-LuaTable $files 'qcQuestTuning')[11] '5' 'D5: and qcQuestTuning from the quest''s tuning'
    Equal @(Read-TuningData "$files\addon").Count 0 'D5: a folder with no tunings.jsonl reads as none'

    # --- One world, every case ----------------------------------------------------------------------------
    $world = Write-World 'world' (New-World)
    $before = Get-Hashes $world
    $r = Invoke-Tool $world @{ WhatIf = $true }
    Equal $r.Exit 0 'W1: -WhatIf exits 0'
    Equal (Get-Hashes $world) $before 'W1: and writes nothing'
    Has $r.Text 'quest runs on the build: run 1, Alliance Human MAGE at level 90.' 'W1: it names the probe''s quest run and its level'
    Has $r.Text '2 placeholder rows of records held in part left out' 'W1: a cached row with no level is a placeholder, left out'
    Has $r.Text 'Tunings: 6 probed quests used (1 with no level above 0, 0 with no tuning and 1 on tuning 0 left out); 2 tunings scale to one level each at the cap, for 4 of them (66.67%); 1 give several  [ok]' 'W1: the tunings, counted'
    Has $r.Text 'tuning 400 gives several levels, so none of its quests gets a ceiling: 60 (1 quests), 70 (1 quests)' 'W1: the split tuning, with its levels'
    Has $r.Text 'Sources: a probed tuning for 15 quests, a split one for 3, tuning 0 for 1; 5 keep what they have (1 no tuning, 4 tuning not probed).' 'W1: where each quest''s ceiling comes from'
    Has $r.Text 'Ceilings: 10 quests scale, 4 of them answered in the probe and 6 through their tuning; 4 are at their minimum at the cap, so don''t scale; 1 would have a ceiling below their minimum and get none.' 'W1: the ceilings, counted'
    Has $r.Text 'by ceiling: 90 (3), 70 (7)' 'W1: by level'
    Has $r.Text '1 of them have a level of 0 (no level)' 'W1: the level-0 quest that scales'
    Has $r.Text 'below its minimum: 6  level 60  minimum 75  the game''s level at the cap 70' 'W1: and the one whose ceiling is below its minimum'
    Has $r.Text '3 of those at their minimum have a level of their own that isn''t it' 'W1: the quests held at their minimum whose own level is another'
    Has $r.Text '1 below it, 1 above it and 1 of level 0 (no bracket, never low); 0 of them answered in the probe' 'W1: below, above and of level 0'
    Has $r.Text "    22  level 50  minimum 70  Quest 22`n    23  level 80  minimum 70  Quest 23`n    24  level 0  minimum 70  Quest 24" 'W1: listed by id'
    Check (-not $r.Text.Contains('    5  level 70  minimum')) 'W1: but not the one whose own level is its minimum'
    Has $r.Text 'Changes: 12 quests (9 maxLevel added, 1 changed, 2 removed).' 'W1: the changes'
    Has $r.Text 'hidden though the game calls them not trivial: 2 by the quest''s own level, 0 by the shown level (2 now shown)' 'W1: against the game, the quests the old rule hid'
    Has $r.Text 'shown though the game calls them trivial: 0 by the quest''s own level, 0 by the shown level' 'W1: and none the new rule shows that the game calls trivial'
    Has $r.Text 'Midnight: 2 -> 0; 0 -> 0' 'W1: by the game''s expansion'
    Has $r.Text 'Quest tunings: 23 quests get one, 21 from the quest cache and 1 from the task table; 1 keep the one they hold, as neither has them; 1 are on tuning 0 (1 in the cache, 0 in the task table) and 0 have none in either, so get none.' 'W1: where each quest''s tuning comes from'
    Has $r.Text '  changes: 23 quests (21 tuning added, 1 changed, 1 removed)' 'W1: the tunings added, changed and taken away'
    Has $r.Text "    16  tuning 555 -> 100  Quest 16`n    13  tuning 100 -> none  Quest 13" 'W1: the changed one and the one on tuning 0, listed'
    Has $r.Text 'Redirects (ConditionalContentTuning of 12.1.5.70400): 6 rows, 4 RedirectEnum values, 5 tunings redirected; rows by enum: 0 (1), 5 (1), 13 (1), 34 (3)' 'W1: the redirect table, counted'
    Has $r.Text 'against the baseline of 12.1.5.70400 (6 rows): 0 new, 0 gone, 0 with another row count  [ok]' 'W1: and against its baseline'
    Has $r.Text 'Samples: our quests are on 8 tunings; a redirect names 5 of them, and none the other 3, whose level is their own range for every character. 2 get samples (0 with 3 or more, 2 with 2, 0 with 1); 3 that a redirect names get none.' 'W1: the tunings that get samples'
    Has $r.Text "  no samples: tuning 300 (1 of our quests): not probed`n  no samples: tuning 400 (3 of our quests): split`n  no samples: tuning 700 (1 of our quests): not probed" 'W1: and those that get none, and why: a placeholder or a level of 0 is no level'
    Has $r.Text '  4 samples: 4 quests of ours, 4 in QuestV2, 4 one-time, 4 open to both factions, 0 flagged unavailable. The addon gets the tuning of the 15 quests on a sampled tuning (qcQuestTuning); the other 8 with one keep it in the data only.' 'W1: the samples, and what the addon gets'
    Has $r.Text '  tunings.jsonl: 0 records held, 2 wanted; 2 added, 0 changed, 0 removed; 0 stored samples stay, 0 are no longer ones and 0 give way' 'W1: tunings.jsonl''s changes'
    Check (-not $r.Text.Contains('have another level at the cap')) 'W1: with nothing stored, no tuning''s level has moved'
    Has $r.Text 'Lua tables: qcQuestMaxLevel 12 keys and qcQuestTuning 15, 32,756 and 32,753 under 32,768; above it Lua 5.1 doubles a table''s hash part' 'W1: the two big tables'' keys, against the hash part''s step'
    Has $r.Text '(docs\plans\load-and-memory.md)  [ok]' 'W1: both under it'
    Has $r.Text '-WhatIf: nothing was written (12 maxLevel and 23 tuning changes, and tunings.jsonl).' 'W1: and that nothing was written'
    $r = Invoke-Tool $world @{ Check = $true }
    Equal $r.Exit 1 'W2: -Check exits 1 while the data differs'
    Has $r.Text 'Check failed: the data isn''t what the sources say (12 maxLevel and 23 tuning changes, and tunings.jsonl)' 'W2: and says how'
    Equal (Get-Hashes $world) $before 'W2: and writes nothing'
    $r = Invoke-Tool $world
    Equal $r.Exit 0 'W3: the run exits 0'
    Has $r.Text 'Saved: 23 quests changed, 12 quests now hold a maxLevel and 23 a tuning; tunings.jsonl holds 2 tunings.' 'W3: and saves'
    $records = Get-Records $world
    $lua = Get-LuaTable $world 'qcQuestMaxLevel'
    $luaTuning = Get-LuaTable $world 'qcQuestTuning'
    foreach ($id in ($Wanted.Keys | Sort-Object)) {
        $got = $records[$id].maxLevel
        if ($null -eq $Wanted[$id]) {
            Check ($null -eq $got) "W3: quest $id has no maxLevel (has $got)"
            Check (-not $lua.ContainsKey($id)) "W3: nor an entry in qcQuestMaxLevel"
        } else {
            Equal $got $Wanted[$id] "W3: quest $id gets maxLevel"
            Equal $lua[$id] "$($Wanted[$id])" "W3: and qcQuestMaxLevel[$id]"
        }
        Equal $records[$id].tuning $WantedTuning[$id] "W3: quest $id gets its tuning"
        if ($WantedTuning[$id] -eq 100 -or $WantedTuning[$id] -eq 200) { Equal $luaTuning[$id] "$($WantedTuning[$id])" "W3: and qcQuestTuning[$id], its tuning having samples" }
        else { Check (-not $luaTuning.ContainsKey($id)) "W3: quest $id is not in qcQuestTuning, its tuning having no samples" }
    }
    Equal (Get-TuningText $world) $WantedTunings 'W3: tunings.jsonl holds the sampled tunings, each with its level, redirects and samples'
    $samples = Get-LuaTable $world 'qcTuningSample'
    Equal (($samples.Keys | Sort-Object | ForEach-Object { "$_=$($samples[$_])" }) -join ' ') '100={1,2} 200={7,21}' 'W3: and qcTuningSample the same samples'
    $fresh = New-World
    foreach ($id in $fresh.Keys) {
        Equal $records[$id].level $fresh[$id].Level "W4: quest $id keeps its level"
        Equal $records[$id].minLevel $fresh[$id].MinLevel "W4: and its minLevel"
    }
    Equal $records.Count $fresh.Count 'W4: no quest is lost'
    $after = Get-Hashes $world
    $r = Invoke-Tool $world
    Equal $r.Exit 0 'W5: a second run exits 0'
    Has $r.Text "Nothing to change: every quest's maxLevel and tuning, and tunings.jsonl, are what the sources say." 'W5: and changes nothing'
    Equal (Get-Hashes $world) $after 'W5: byte for byte'
    $r = Invoke-Tool $world @{ Check = $true }
    Equal $r.Exit 0 'W5: -Check passes now'
    $r = Invoke-Tool $world @{ WhatIf = $true }
    Has $r.Text 'hidden though the game calls them not trivial: 2 by the quest''s own level, 0 by the shown level (2 now shown)' 'W5: the comparison reads the data as saved'
    Has $r.Text '  tunings.jsonl: 2 records held, 2 wanted; 0 added, 0 changed, 0 removed; 4 stored samples stay, 0 are no longer ones and 0 give way' 'W5: and so does the samples'' part'
    $r = Invoke-Tool $world @{ Check = $true; BaselineFile = "$world\missing.csv" }
    Equal $r.Exit 1 'W6: -Check with no baseline file exits 1'
    Has $r.Text 'No baseline file, so every RedirectEnum counts as new' 'W6: and says why'
    Has $r.Text 'the redirect table has RedirectEnum values its baseline lacks (0, 5, 13, 34)' 'W6: naming them all'
    $r = Invoke-Tool $world @{ Check = $true; UpdateBaseline = $true }
    Has $r.Failure '-Check writes nothing, so it takes no -UpdateBaseline.' 'W6: -Check with -UpdateBaseline is refused'
    [IO.File]::WriteAllText("$world\baseline-short.csv", ((@($Baseline | Select-Object -First 4) -join "`r`n") + "`r`n"), $utf8)
    $baselineBefore = (Get-FileHash "$world\baseline-short.csv").Hash
    $r = Invoke-Tool $world @{ WhatIf = $true; UpdateBaseline = $true; BaselineFile = "$world\baseline-short.csv" }
    Has $r.Failure '-WhatIf writes nothing, so it takes no -UpdateBaseline.' 'W6: and so is -WhatIf with -UpdateBaseline'
    Check (-not $r.Text.Contains('Baseline written')) 'W6: which writes no baseline'
    Equal (Get-FileHash "$world\baseline-short.csv").Hash $baselineBefore 'W6: leaving a baseline the table no longer matches as it was'
    Equal (Get-Hashes $world) $after 'W6: and the data too'

    # --- The thresholds ---------------------------------------------------------------------------------------
    $r = Invoke-Tool $world @{ WhatIf = $true; MinAgreement = 0.99 }
    Equal $r.Exit 1 'T1: 67% of the probed quests on agreeing tunings is refused at -MinAgreement 0.99'
    Has $r.Text '[FAILED]' 'T1: and says so'
    Has $r.Text 'Nothing was changed.' 'T1: changing nothing'
    $r = Invoke-Tool $world @{ WhatIf = $true; MinProbed = 7 }
    Equal $r.Exit 1 'T2: fewer usable probed quests than -MinProbed is refused'
    Has $r.Text 'only 6 usable probed quests, fewer than -MinProbed 7' 'T2: and says so'

    # --- Samples the probe no longer gives --------------------------------------------------------------------
    $quests = New-World
    $stale = Write-World 'stale' $quests
    Invoke-Tool $stale | Out-Null
    $quests[1].Probe.Result = 'fail'
    Write-Probe (Get-ProbeFile $stale) $quests (New-Run 90)
    $r = Invoke-Tool $stale @{ Check = $true }
    Equal $r.Exit 1 'P1: -Check fails once a stored sample is no longer loaded'
    Has $r.Text '  tunings.jsonl: 2 records held, 2 wanted; 0 added, 1 changed, 0 removed; 3 stored samples stay, 1 are no longer ones and 0 give way' 'P1: it counts the change'
    Has $r.Text '    tuning 100, sample 1: not loaded in the probe' 'P1: and names the sample and why'
    $r = Invoke-Tool $stale
    Equal $r.Exit 0 'P1: the run exits 0'
    Has (Get-TuningText $stale) '{"id":100,"level":70,"redirects":[0,34],"samples":[2]}' 'P1: and the tuning keeps only the sample still loaded'
    $quests[1].Probe.Result = 'ok'
    $quests[2].Cache = 300
    Write-Probe (Get-ProbeFile $stale) $quests (New-Run 90)
    Write-Cache $stale $quests
    $r = Invoke-Tool $stale @{ WhatIf = $true }
    Has $r.Text '    tuning 100, sample 2: on another tuning now' 'P2: a sample whose quest moved tuning is no longer one'
    Has $r.Text '    2  tuning 100 -> 300  Quest 2' 'P2: and the quest''s tuning changes'
    Has $r.Text '  tunings.jsonl: 2 records held, 3 wanted; 1 added, 1 changed, 0 removed; 2 stored samples stay, 1 are no longer ones and 0 give way' 'P2: the tuning it moved to gets samples'
    $r = Invoke-Tool $stale
    Equal (Get-TuningText $stale) "{`"id`":100,`"level`":70,`"redirects`":[0,34],`"samples`":[1]}`n{`"id`":200,`"level`":90,`"redirects`":[13],`"samples`":[7,21]}`n{`"id`":300,`"level`":70,`"redirects`":[34],`"samples`":[2]}`n" 'P2: and the run writes them all'

    # --- The order samples are taken in, and -Samples ----------------------------------------------------------
    $order = @{}
    $order[31] = New-Quest 20 $null $null 200 $null (New-Row 'ok' 90 $false 11) $null 1 3
    $order[32] = New-Quest 20 $null $null 200 $null (New-Row 'ok' 90 $false 11) $null 4 3
    $order[33] = New-Quest 20 $null $null 200 $null (New-Row 'ok' 90 $false 11) $null 1 1
    $order[34] = New-Quest 20 $null $null 200 $null (New-Row 'ok' 90 $false 11) $null 1 3
    $order[35] = New-Quest 20 $null $null 200 $null (New-Row 'ok' 90 $false 11) $null 1 3
    $order[36] = New-Quest 20 $null $null 200 $null (New-Row 'late' 90 $false 11) $null 1 3
    $order[37] = New-Quest 20 $null $null 200 $null (New-Row 'ok' 90 $false 11) $null 1 3
    $ordered = Write-World 'order' $order (New-Run 90) '' $Build @($Redirects[0], '3,0,1002,8192,13,200') @('"Build","RedirectEnum","Rows"', "`"$Build`",`"13`",`"1`"") @(31, 32, 33, 35, 36, 37) @(35)
    $r = Invoke-Tool $ordered
    Equal $r.Exit 0 'O1: the run exits 0'
    Equal (Get-TuningText $ordered) "{`"id`":200,`"level`":90,`"redirects`":[13],`"samples`":[31,37,33]}`n" 'O1: three samples, the best first'
    $r = Invoke-Tool $ordered @{ Samples = 6 }
    Equal (Get-TuningText $ordered) "{`"id`":200,`"level`":90,`"redirects`":[13],`"samples`":[31,37,33,32,35,34]}`n" 'O2: -Samples 6 takes every candidate: one faction, then recurring, then flagged, then not in QuestV2; a late answer is none'
    Has $r.Text '6 samples: 6 quests of ours, 5 in QuestV2, 5 one-time, 5 open to both factions, 1 flagged unavailable.' 'O2: and counts them by kind'
    $failure = (Invoke-Tool $ordered @{ Samples = 0 }).Failure
    Has $failure '-Samples must be 1 or more.' 'O3: -Samples 0 is refused'

    # --- Stored samples: they stay, or give way to a better kind or a lower -Samples ------------------------------
    $keep = @{}
    foreach ($id in 41, 42, 43) { $keep[$id] = New-Quest 20 $null $null 200 $null (New-Row 'ok' 90 $false 11) $null 1 3 }
    $keep[40] = New-Quest 20 $null $null 200 $null $null $null 1 3
    $kept = Write-World 'keep' $keep (New-Run 90) '' $Build @($Redirects[0], '3,0,1002,8192,13,200') @('"Build","RedirectEnum","Rows"', "`"$Build`",`"13`",`"1`"")
    Invoke-Tool $kept | Out-Null
    $keepText = { param($samples) "{`"id`":200,`"level`":90,`"redirects`":[13],`"samples`":[$samples]}`n" }
    Equal (Get-TuningText $kept) (& $keepText '41,42,43') 'K1: the three quests the probe loaded are the samples'
    $keep[40].Probe = New-Row 'ok' 90 $false 11
    Write-Probe (Get-ProbeFile $kept) $keep (New-Run 90)
    $keptBefore = Get-Hashes $kept
    $r = Invoke-Tool $kept @{ Check = $true }
    Equal $r.Exit 0 'K2: a fuller probe that loads a quest of the same kind and a lower id changes nothing, so -Check passes'
    Has $r.Text '  tunings.jsonl: 1 records held, 1 wanted; 0 added, 0 changed, 0 removed; 3 stored samples stay, 0 are no longer ones and 0 give way' 'K2: the stored samples stay'
    Invoke-Tool $kept | Out-Null
    Equal (Get-Hashes $kept) $keptBefore 'K2: and an applying run writes nothing'
    [IO.File]::WriteAllText("$kept\unavailable.csv", "`"QuestID`",`"Name`",`"Zone`",`"Reason`",`"Decision`",`"Evidence`"`n`"43`",`"Quest 43`",`"Zone`",`"1`",`"FLAG`",`"test`"`n", $utf8)
    $r = Invoke-Tool $kept @{ WhatIf = $true }
    Has $r.Text '  tunings.jsonl: 1 records held, 1 wanted; 0 added, 1 changed, 0 removed; 2 stored samples stay, 0 are no longer ones and 1 give way' 'K3: a stored sample flagged unavailable gives way to a loaded quest of a better kind'
    Has $r.Text '    tuning 200, sample 43: still loaded at its tuning''s level, but a better kind of quest takes its place' 'K3: and is named, with why'
    Invoke-Tool $kept | Out-Null
    Equal (Get-TuningText $kept) (& $keepText '41,42,40') 'K3: the samples kept stay in their order, and the new one follows'
    $r = Invoke-Tool $kept @{ Samples = 2 }
    Has $r.Text '    tuning 200, sample 40: still loaded at its tuning''s level, but -Samples 2 keeps the ones before it' 'K4: a lower -Samples drops the last stored sample, and says so'
    Equal (Get-TuningText $kept) (& $keepText '41,42') 'K4: keeping the ones before it'
    $r = Invoke-Tool $kept
    Has $r.Text '0 added, 1 changed, 0 removed; 2 stored samples stay, 0 are no longer ones and 0 give way' 'K5: -Samples 3 again tops the tuning up'
    Equal (Get-TuningText $kept) (& $keepText '41,42,40') 'K5: with the best quest not yet a sample, not the flagged one'
    foreach ($id in 40, 41, 42, 43) { $keep[$id].Probe.Level = 80 }
    Write-Probe (Get-ProbeFile $kept) $keep (New-Run 90)
    $r = Invoke-Tool $kept @{ WhatIf = $true }
    Has $r.Text '  1 sampled tunings have another level at the cap than tunings.jsonl holds; many at once can mean the probe''s character had other redirect bits' 'K6: a sampled tuning whose level moved is listed'
    Has $r.Text "    200  90 -> 80  (13)" 'K6: with its levels and RedirectEnum values'
    Has $r.Text '3 stored samples stay, 0 are no longer ones and 0 give way' 'K6: its samples stay, as they give its one level still'

    # --- The redirect table against its baseline ----------------------------------------------------------------
    $enums = Write-World 'enums' (New-World) (New-Run 90) '' $Build ($Redirects + '7,2,1004,0,40,100') @($Baseline[0], $Baseline[1], $Baseline[2], "`"$Build`",`"9`",`"1`"", "`"$Build`",`"13`",`"2`"", $Baseline[4])
    $r = Invoke-Tool $enums @{ WhatIf = $true }
    Has $r.Text 'against the baseline of 12.1.5.70400 (8 rows): 1 new (40), 1 gone (9), 1 with another row count (13: 2 -> 1)  [NEW]' 'E1: a new RedirectEnum, one gone and another row count'
    Has $r.Text 'A new RedirectEnum is a redirect no sweep has read' 'E1: and what to do about the new one'
    $r = Invoke-Tool $enums
    Equal $r.Exit 0 'E2: the run still writes the data'
    Has (Get-TuningText $enums) '{"id":100,"level":70,"redirects":[0,34,40],"samples":[1,2]}' 'E2: with the new RedirectEnum among the tuning''s redirects'
    $r = Invoke-Tool $enums @{ Check = $true }
    Equal $r.Exit 1 'E3: but -Check fails while the baseline lacks the RedirectEnum'
    Has $r.Text 'Check failed: the redirect table has RedirectEnum values its baseline lacks (40): look at them, then -UpdateBaseline.' 'E3: and names it'
    $r = Invoke-Tool $enums @{ UpdateBaseline = $true }
    Has $r.Text 'Baseline written: 5 RedirectEnum values, 7 rows of 12.1.5.70400' 'E4: -UpdateBaseline writes the baseline'
    Has $r.Text 'Nothing to change' 'E4: and the data, written by E2, stays'
    Equal ([IO.File]::ReadAllText("$enums\baseline.csv")) ("`"Build`",`"RedirectEnum`",`"Rows`"`r`n`"$Build`",`"0`",`"1`"`r`n`"$Build`",`"5`",`"1`"`r`n`"$Build`",`"13`",`"1`"`r`n`"$Build`",`"34`",`"3`"`r`n`"$Build`",`"40`",`"1`"`r`n") 'E4: the table''s rows by RedirectEnum'
    $r = Invoke-Tool $enums @{ Check = $true }
    Equal $r.Exit 0 'E4: and -Check passes after it'

    # --- The level cap ---------------------------------------------------------------------------------------
    $low = Write-World 'low' (New-World) ((New-Run 90) + "`n" + (New-Run 80))
    $lowBefore = Get-Hashes $low
    $r = Invoke-Tool $low
    Equal $r.Exit 1 'C1: a quest run of the build below the cap is refused'
    Has $r.Text 'run 2 at level 80' 'C1: naming the run'
    Equal (Get-Hashes $low) $lowBefore 'C1: and nothing is written'
    $none = Write-World 'none' (New-World) (New-Run 0)
    $r = Invoke-Tool $none
    Equal $r.Exit 1 'C2: a run that kept no level is refused'
    Has $r.Text 'run 1 at no recorded level' 'C2: and named'
    $other = Write-World 'other' (New-World) ((New-Run 60 '12.1.0.69933') + "`n" + (New-Run 90))
    $r = Invoke-Tool $other @{ WhatIf = $true }
    Equal $r.Exit 0 'C3: a run below the cap on another build does not count'
    $newBuild = '13.0.0.80000'
    $quests = New-World
    foreach ($q in $quests.Values) { if ($q.Probe -and $q.Probe.Build -eq $Build) { $q.Probe.Build = $newBuild } }
    $next = Write-World 'next' $quests (New-Run 100 $newBuild) $newBuild $newBuild
    $r = Invoke-Tool $next @{ WhatIf = $true }
    Equal $r.Exit 1 'C4: a build whose cap is not known is refused'
    Has $r.Text 'no level cap is known for build 13.0.0.80000' 'C4: and says so'
    $r = Invoke-Tool $next @{ WhatIf = $true; Cap = 100 }
    Equal $r.Exit 0 'C4: -Cap gives it'
    Has $r.Text 'level cap 100' 'C4: and the run uses it'
    Has $r.Text 'Redirects (ConditionalContentTuning of 13.0.0.80000)' 'C4: reading the redirect table of the probe''s build'

    # --- The build ---------------------------------------------------------------------------------------
    $mismatch = Write-World 'mismatch' (New-World) (New-Run 90) $Build '12.1.5.70500'
    $r = Invoke-Tool $mismatch @{ WhatIf = $true }
    Equal $r.Exit 1 'B1: a probe of another build than the quest cache is refused'
    Has $r.Text 'the probe ran on build 12.1.5.70400 and the quest cache is of 12.1.5.70500' 'B1: and says so'

    # --- Forever: the check, which writes nothing ---------------------------------------------------------
    $fBuild = '1.60.1.70900'
    $fdir = Join-Path $Scratch 'forever'
    New-Item -ItemType Directory "$fdir\tools\forever_probe_70900", "$fdir\data\forever" -Force | Out-Null
    $fQuests = @{
        1 = (New-Quest 10 $null $null $null $null (New-Row 'ok' 10 $true $null $fBuild))
        2 = (New-Quest 28 25 $null $null $null (New-Row 'ok' 28 $false $null $fBuild))
        3 = (New-Quest 0 $null $null $null $null (New-Row 'ok' 0 $true $null $fBuild))
        4 = (New-Quest 30 $null $null $null $null $null)
    }
    function Write-Forever($quests) {
        $data = foreach ($id in ($quests.Keys | Sort-Object)) {
            $q = $quests[$id]
            $line = '{"id":' + $id + ',"name":"Quest ' + $id + '","level":' + $q.Level + ',"zone":"Zone","category":1,"type":1,"faction":0,"race":0,"class":0'
            if ($null -ne $q.MinLevel) { $line += ',"minLevel":' + $q.MinLevel }
            if ($null -ne $q.MaxLevel) { $line += ',"maxLevel":' + $q.MaxLevel }
            if ($null -ne $q.Tuning) { $line += ',"tuning":' + $q.Tuning }
            $line + '}'
        }
        [IO.File]::WriteAllText("$fdir\data\forever\quests.jsonl", (($data -join "`n") + "`n"), $utf8)
        Write-Probe "$fdir\tools\forever_probe_70900\QCForeverProbe.lua" $quests (New-Run 30 $fBuild 'Horde Orc WARRIOR')
    }
    function Invoke-Forever {
        $global:LASTEXITCODE = 0
        $lines = @(& $Apply -Game forever -ToolsDir "$fdir\tools" -DataDir "$fdir\data\forever" *>&1 | ForEach-Object { "$_" })
        return @{ Text = ($lines -join "`n"); Exit = $global:LASTEXITCODE }
    }
    Write-Forever $fQuests
    $fBefore = (Get-FileHash "$fdir\data\forever\quests.jsonl").Hash
    $r = Invoke-Forever
    Equal $r.Exit 0 'F1: Forever with every loaded quest at its stored level passes'
    Has $r.Text 'Horde Orc WARRIOR at level 30; of the 3 quests of ours it loaded, 3 have their stored level and 0 another.' 'F1: and counts them'
    Has $r.Text 'hidden though the game calls them not trivial: 0 by the quest''s own level, 0 by the shown level' 'F1: the rule against the game at the probe''s level'
    Has $r.Text 'shown though the game calls them trivial: 1 by the quest''s own level, 1 by the shown level' 'F1: a level of 0 is never low, though the game greys it'
    Has $r.Text "Forever's quests don't scale" 'F1: and says so'
    Equal (Get-FileHash "$fdir\data\forever\quests.jsonl").Hash $fBefore 'F1: writing nothing'
    Check (-not (Test-Path "$fdir\data\forever\tunings.jsonl")) 'F1: and no tunings.jsonl'
    $fQuests[2].Probe.Level = 30
    Write-Forever $fQuests
    $r = Invoke-Forever
    Equal $r.Exit 1 'F2: a quest whose level is not the game''s fails'
    Has $r.Text '2  level 28, the game''s 30  Quest 2' 'F2: and is listed'
    $fQuests[2].Probe.Level = 28
    $fQuests[4].MaxLevel = 40
    Write-Forever $fQuests
    $r = Invoke-Forever
    Equal $r.Exit 1 'F3: a maxLevel in Forever''s data fails'
    Has $r.Text '1 of Forever''s quests hold a maxLevel' 'F3: and says so'
    $fQuests[4].MaxLevel = $null
    $fQuests[4].Tuning = 100
    Write-Forever $fQuests
    $r = Invoke-Forever
    Equal $r.Exit 1 'F4: so does a tuning'
    Has $r.Text '1 of Forever''s quests hold a tuning' 'F4: and says so'
    $fQuests[4].Tuning = $null
    Write-Forever $fQuests
    [IO.File]::WriteAllText("$fdir\data\forever\tunings.jsonl", '{"id":5,"level":30,"redirects":[0],"samples":[1]}' + "`n", $utf8)
    $r = Invoke-Forever
    Equal $r.Exit 1 'F5: and a tunings.jsonl in Forever''s data folder'
    Has $r.Text "Forever's data folder holds a tunings.jsonl" 'F5: named'
    Remove-Item "$fdir\data\forever\tunings.jsonl"
    Equal (Invoke-Forever).Exit 0 'F6: without them it passes again'
} finally {
    [Threading.Thread]::CurrentThread.CurrentCulture = $savedCulture
}

# --- The real files ------------------------------------------------------------------------------------------
$realProbe = Find-ProbeResults $RealToolsDir
$haveReal = (Test-Path $realProbe) -and $realProbe -match 'retail_probe_' -and (Test-Path "$RealToolsDir\QuestV2CliTask.csv") -and
    @(Get-QuestCacheFiles $RealToolsDir).Count -gt 0
if (-not $haveReal) {
    Write-Output "The real files aren't in ${RealToolsDir} (a retail probe, a quest cache and the task table): that section was skipped."
} else {
    $realDir = Join-Path $Scratch 'real'
    New-Item -ItemType Directory "$realDir\data", "$realDir\addon" | Out-Null
    $checkoutData = Join-Path $PSScriptRoot '..\data'
    $plans = Join-Path $PSScriptRoot '..\docs\plans'
    $realFiles = @{ ToolsDir = $RealToolsDir; MinProbed = 20000; MinAgreement = 0.99
        BaselineFile = "$plans\quest-scaling-redirects-baseline.csv"; UnavailableFile = "$plans\unavailable-quest-decisions.csv" }
    $strip = { param($text) $text -replace ',"maxLevel":\d+(?=[,}])', '' -replace ',"tuning":\d+(?=[,}])', '' }
    [IO.File]::WriteAllText("$realDir\data\quests.jsonl", (& $strip ([IO.File]::ReadAllText("$checkoutData\quests.jsonl"))), $utf8)
    Copy-Item "$checkoutData\pins.jsonl" "$realDir\data\pins.jsonl"
    Invoke-AddonDataBuild -DataDir "$realDir\data" -AddonDir "$realDir\addon" | Out-Null
    $strippedLines = [IO.File]::ReadAllLines("$realDir\data\quests.jsonl")
    $r = Invoke-Tool $realDir $realFiles
    Equal $r.Exit 0 'R1: on the real files the run exits 0'
    Check ($r.Text -match 'tunings scale to one level each at the cap, for [\d,]+ of them \((\d+\.\d+)%\); [\d,]+ give several  \[ok\]') 'R1: and the probe''s tunings agree'
    $appliedLines = [IO.File]::ReadAllLines("$realDir\data\quests.jsonl")
    Equal $appliedLines.Count $strippedLines.Count 'R2: the real data keeps all its quests'
    $added = 0; $tuned = 0; $bad = 0
    for ($i = 0; $i -lt $strippedLines.Count; $i++) {
        if ($appliedLines[$i] -ceq $strippedLines[$i]) { continue }
        $q = $appliedLines[$i] | ConvertFrom-Json
        $floor = if ($null -ne $q.minLevel) { [int]$q.minLevel } else { [int]$q.level }
        if ((& $strip $appliedLines[$i]) -cne $strippedLines[$i] -or ($null -ne $q.maxLevel -and [int]$q.maxLevel -le $floor)) { $bad++; continue }
        if ($null -ne $q.maxLevel) { $added++ }
        if ($null -ne $q.tuning) { $tuned++ }
    }
    Check ($added -gt 0) "R2: some quests get a maxLevel ($added)"
    Check ($tuned -gt 0) "R2: and some a tuning ($tuned)"
    Equal $bad 0 'R2: every changed line is the old one with a maxLevel or a tuning added, a maxLevel always above the quest''s minimum'
    $realTunings = @(Read-TuningData "$realDir\data")
    Check ($realTunings.Count -gt 0) "R2: tunings.jsonl gets records ($($realTunings.Count))"
    Equal @(Test-TuningRecords $realTunings).Count 0 'R2: every one sound'
    $realAfter = Get-Hashes $realDir
    $r = Invoke-Tool $realDir $realFiles
    Equal $r.Exit 0 'R3: a second run on the real files exits 0'
    Has $r.Text 'Nothing to change' 'R3: and has nothing to change'
    Equal (Get-Hashes $realDir) $realAfter 'R3: byte for byte'
    $built = Invoke-AddonDataBuild -DataDir "$realDir\data" -AddonDir "$realDir\addon" -Check
    Check $built.Ok 'R3: and the Lua matches the data'
    $same = ([IO.File]::ReadAllText("$realDir\data\quests.jsonl") -ceq [IO.File]::ReadAllText("$checkoutData\quests.jsonl")) -and
        ((Get-TuningText $realDir) -ceq (Get-TuningText (Join-Path $PSScriptRoot '..')))
    $redirectLine = @($r.Text -split "`n" | Where-Object { $_ -match '^  (against the baseline|No baseline file)' }) -join ' '
    Write-Output ("Info: the real files give {0:N0} quests a maxLevel, {1:N0} a tuning and tunings.jsonl {2:N0} tunings; the result {3} the checkout's own data. Redirects:{4}" -f
        $added, $tuned, $realTunings.Count, $(if ($same) { 'is' } else { 'is not' }), $redirectLine)
}

Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "$Passed checks passed, $Failed failed"
if ($Failed -gt 0) { exit 1 }
