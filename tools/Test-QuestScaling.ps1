<#
Checks Apply-QuestScaling.ps1 and QuestScaling.ps1 on quests, a quest cache, a task table and probe saved
variables made here, in a scratch folder: nothing in the checkout is read or written (but the scripts
themselves). One world holds a quest for each way a ceiling can come out: probed on its tuning or only
sharing it, at its minimum or below it, a level of 0, a tuning from the task table, a split tuning, tuning 0,
no tuning, a tuning only a placeholder row, a refusal, a level of 0 or another build's row speaks for, and a
maxLevel that is added, changed, taken away or kept. The rest changes one thing at a time: -WhatIf and
-Check, a second run, the level-cap check (a run below the cap, a run with no level, a build whose cap
isn't known, -Cap), a probe of another build than the quest cache, and the agreement thresholds. A
Forever world checks -Game forever: it passes while every loaded quest has its stored level, fails on a
level the game doesn't give or on a maxLevel, and writes nothing.

The last section runs the tool on the real files, when they are there: -RealToolsDir (this folder by
default) with the newest retail probe, its build's quest cache and the task table. It copies the
checkout's data into the scratch folder, takes every maxLevel out, applies, and checks that only maxLevel
fields are added, every one above the quest's minimum, and that a second run changes nothing. It says
whether the result is the checkout's own data.

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
# trivial, expansion; $null = not asked).
function New-Quest([int]$level, $minLevel, $maxLevel, $cache, $task, $probe) {
    return @{ Level = $level; MinLevel = $minLevel; MaxLevel = $maxLevel; Cache = $cache; Task = $task; Probe = $probe }
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
    $q[13] = New-Quest 40 $null 55 0 $null (New-Row 'ok' 50 $true 4)
    $q[14] = New-Quest 30 $null 60 $null $null $null
    $q[15] = New-Quest 5 $null $null $null 100 $null
    $q[16] = New-Quest 0 $null $null 100 $null $null
    $q[17] = New-Quest 30 $null 45 500 $null (New-Row 'fail')
    $q[18] = New-Quest 30 $null $null 600 $null (New-Row 'ok' 40 $true 4 '12.1.0.69933')
    $q[19] = New-Quest 10 $null 65 100 $null $null
    $q[20] = New-Quest 30 $null $null 700 $null (New-Row 'ok' 0 $true 4)
    $q[21] = New-Quest 60 $null $null 200 $null (New-Row 'ok' 90 $false 11)
    return $q
}
# What each quest's maxLevel must be after a run of the world above.
$Wanted = @{ 1 = 70; 2 = 70; 3 = 70; 4 = 70; 5 = $null; 6 = $null; 7 = 90; 8 = 90; 9 = $null; 10 = $null; 11 = $null; 12 = $null
    13 = $null; 14 = 60; 15 = 70; 16 = 70; 17 = 45; 18 = $null; 19 = 70; 20 = $null; 21 = 90 }

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

function Write-World([string]$name, $quests, [string]$runs = (New-Run 90), [string]$probeBuild = '', [string]$cacheBuild = $Build) {
    $dir = Join-Path $Scratch $name
    $probeDir = "$dir\tools\retail_probe_" + ($(if ($probeBuild) { $probeBuild } else { $Build }) -replace '^.*\.', '')
    New-Item -ItemType Directory $probeDir, "$dir\data", "$dir\addon" -Force | Out-Null
    $data = @(); $cache = @(); $task = @('ID,QuestTitle_lang,ContentTuningID')
    foreach ($id in ($quests.Keys | Sort-Object)) {
        $q = $quests[$id]
        $line = '{"id":' + $id + ',"name":"Quest ' + $id + '","level":' + $q.Level + ',"zone":"Zone","category":1,"type":1,"faction":0,"race":0,"class":0'
        if ($null -ne $q.MinLevel) { $line += ',"minLevel":' + $q.MinLevel }
        if ($null -ne $q.MaxLevel) { $line += ',"maxLevel":' + $q.MaxLevel }
        $data += $line + '}'
        if ($null -ne $q.Cache) { $cache += '{"id":' + $id + ',"title":"Quest ' + $id + '","contentTuning":' + $q.Cache + ',"sort":0,"questType":2}' }
        if ($null -ne $q.Task) { $task += "$id,Quest $id,$($q.Task)" }
    }
    [IO.File]::WriteAllText("$dir\data\quests.jsonl", (($data -join "`n") + "`n"), $utf8)
    [IO.File]::WriteAllText("$dir\data\pins.jsonl", '{"map":84,"icon":1,"npc":29611,"name":"A Pin","x":26.12,"y":47.32,"quests":[1]}' + "`n", $utf8)
    [IO.File]::WriteAllText("$dir\tools\retail_quest_cache_$cacheBuild.jsonl", (($cache -join "`n") + "`n"), $utf8)
    [IO.File]::WriteAllText("$dir\tools\QuestV2CliTask.csv", (($task -join "`n") + "`n"), $utf8)
    Write-Probe "$probeDir\QCForeverProbe.lua" $quests $runs
    $result = Invoke-AddonDataBuild -DataDir "$dir\data" -AddonDir "$dir\addon"
    if (-not $result.Ok) { throw "The scratch world $name didn't build: $($result.Lines -join '; ')" }
    return $dir
}

function Invoke-Tool([string]$dir, [hashtable]$more = @{}) {
    $params = @{ ToolsDir = "$dir\tools"; DataDir = "$dir\data"; AddonDir = "$dir\addon"; MinProbed = 1; MinAgreement = 0.5 }
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
    foreach ($file in "data\quests.jsonl", "data\pins.jsonl", "addon\qcQuestData.lua", "addon\qcPinDB.lua") { $hashes += (Get-FileHash "$dir\$file").Hash }
    return $hashes -join ','
}

function Get-Records([string]$dir) {
    $records = @{}
    foreach ($line in [IO.File]::ReadAllLines("$dir\data\quests.jsonl")) { $r = $line | ConvertFrom-Json; $records[[int]$r.id] = $r }
    return $records
}

function Get-LuaMaxLevels([string]$dir) {
    $text = [IO.File]::ReadAllText("$dir\addon\qcQuestData.lua")
    $block = [regex]::Match($text, '(?s)qcQuestMaxLevel=\{\r?\n(.*?)\}').Groups[1].Value
    $entries = @{}
    foreach ($m in [regex]::Matches($block, '\[(\d+)\]=(\d+),')) { $entries[[int]$m.Groups[1].Value] = [int]$m.Groups[2].Value }
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
    Has $r.Text 'Sources: a probed tuning for 12 quests, a split one for 3, tuning 0 for 1; 5 keep what they have (1 no tuning, 4 tuning not probed).' 'W1: where each quest''s ceiling comes from'
    Has $r.Text 'Ceilings: 10 quests scale, 4 of them answered in the probe and 6 through their tuning; 1 are at their minimum at the cap, so don''t scale; 1 would have a ceiling below their minimum and get none.' 'W1: the ceilings, counted'
    Has $r.Text 'by ceiling: 90 (3), 70 (7)' 'W1: by level'
    Has $r.Text '1 of them have a level of 0 (no level)' 'W1: the level-0 quest that scales'
    Has $r.Text 'below its minimum: 6  level 60  minimum 75  the game''s level at the cap 70' 'W1: and the one whose ceiling is below its minimum'
    Has $r.Text 'Changes: 12 quests (9 maxLevel added, 1 changed, 2 removed).' 'W1: the changes'
    Has $r.Text 'hidden though the game calls them not trivial: 2 by the quest''s own level, 0 by the shown level (2 now shown)' 'W1: against the game, the quests the old rule hid'
    Has $r.Text 'shown though the game calls them trivial: 0 by the quest''s own level, 0 by the shown level' 'W1: and none the new rule shows that the game calls trivial'
    Has $r.Text 'Midnight: 2 -> 0; 0 -> 0' 'W1: by the game''s expansion'
    $r = Invoke-Tool $world @{ Check = $true }
    Equal $r.Exit 1 'W2: -Check exits 1 while the data differs'
    Equal (Get-Hashes $world) $before 'W2: and writes nothing'
    $r = Invoke-Tool $world
    Equal $r.Exit 0 'W3: the run exits 0'
    Has $r.Text 'Saved: 12 quests changed, 12 quests now hold a maxLevel.' 'W3: and saves'
    $records = Get-Records $world
    $lua = Get-LuaMaxLevels $world
    foreach ($id in ($Wanted.Keys | Sort-Object)) {
        $got = $records[$id].maxLevel
        if ($null -eq $Wanted[$id]) {
            Check ($null -eq $got) "W3: quest $id has no maxLevel (has $got)"
            Check (-not $lua.ContainsKey($id)) "W3: nor an entry in qcQuestMaxLevel"
        } else {
            Equal $got $Wanted[$id] "W3: quest $id gets maxLevel"
            Equal $lua[$id] $Wanted[$id] "W3: and qcQuestMaxLevel[$id]"
        }
    }
    $fresh = New-World
    foreach ($id in $fresh.Keys) {
        Equal $records[$id].level $fresh[$id].Level "W4: quest $id keeps its level"
        Equal $records[$id].minLevel $fresh[$id].MinLevel "W4: and its minLevel"
    }
    Equal $records.Count $fresh.Count 'W4: no quest is lost'
    $after = Get-Hashes $world
    $r = Invoke-Tool $world
    Equal $r.Exit 0 'W5: a second run exits 0'
    Has $r.Text "Nothing to change: every quest's maxLevel is what the probe says." 'W5: and changes nothing'
    Equal (Get-Hashes $world) $after 'W5: byte for byte'
    $r = Invoke-Tool $world @{ Check = $true }
    Equal $r.Exit 0 'W5: -Check passes now'
    $r = Invoke-Tool $world @{ WhatIf = $true }
    Has $r.Text 'hidden though the game calls them not trivial: 2 by the quest''s own level, 0 by the shown level (2 now shown)' 'W5: the comparison reads the data as saved'

    # --- The thresholds ---------------------------------------------------------------------------------------
    $r = Invoke-Tool $world @{ WhatIf = $true; MinAgreement = 0.99 }
    Equal $r.Exit 1 'T1: 67% of the probed quests on agreeing tunings is refused at -MinAgreement 0.99'
    Has $r.Text '[FAILED]' 'T1: and says so'
    Has $r.Text 'Nothing was changed.' 'T1: changing nothing'
    $r = Invoke-Tool $world @{ WhatIf = $true; MinProbed = 7 }
    Equal $r.Exit 1 'T2: fewer usable probed quests than -MinProbed is refused'
    Has $r.Text 'only 6 usable probed quests, fewer than -MinProbed 7' 'T2: and says so'

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
    $stripped = ([IO.File]::ReadAllText("$checkoutData\quests.jsonl") -replace ',"maxLevel":\d+(?=[,}])', '')
    [IO.File]::WriteAllText("$realDir\data\quests.jsonl", $stripped, $utf8)
    Copy-Item "$checkoutData\pins.jsonl" "$realDir\data\pins.jsonl"
    Invoke-AddonDataBuild -DataDir "$realDir\data" -AddonDir "$realDir\addon" | Out-Null
    $strippedLines = [IO.File]::ReadAllLines("$realDir\data\quests.jsonl")
    $r = Invoke-Tool $realDir @{ ToolsDir = $RealToolsDir; MinProbed = 20000; MinAgreement = 0.99 }
    Equal $r.Exit 0 'R1: on the real files the run exits 0'
    Check ($r.Text -match 'tunings scale to one level each at the cap, for [\d,]+ of them \((\d+\.\d+)%\); [\d,]+ give several  \[ok\]') 'R1: and the probe''s tunings agree'
    $appliedLines = [IO.File]::ReadAllLines("$realDir\data\quests.jsonl")
    Equal $appliedLines.Count $strippedLines.Count 'R2: the real data keeps all its quests'
    $added = 0; $bad = 0
    for ($i = 0; $i -lt $strippedLines.Count; $i++) {
        if ($appliedLines[$i] -ceq $strippedLines[$i]) { continue }
        $q = $appliedLines[$i] | ConvertFrom-Json
        $floor = if ($null -ne $q.minLevel) { [int]$q.minLevel } else { [int]$q.level }
        if (($appliedLines[$i] -replace ',"maxLevel":\d+(?=[,}])', '') -ceq $strippedLines[$i] -and $null -ne $q.maxLevel -and [int]$q.maxLevel -gt $floor) { $added++ }
        else { $bad++ }
    }
    Check ($added -gt 0) "R2: some quests get a maxLevel ($added)"
    Equal $bad 0 'R2: every changed line is the old one with a maxLevel added, always above the quest''s minimum'
    $realAfter = Get-Hashes $realDir
    $r = Invoke-Tool $realDir @{ ToolsDir = $RealToolsDir; MinProbed = 20000; MinAgreement = 0.99 }
    Equal $r.Exit 0 'R3: a second run on the real files exits 0'
    Has $r.Text 'Nothing to change' 'R3: and has nothing to change'
    Equal (Get-Hashes $realDir) $realAfter 'R3: byte for byte'
    $built = Invoke-AddonDataBuild -DataDir "$realDir\data" -AddonDir "$realDir\addon" -Check
    Check $built.Ok 'R3: and the Lua matches the data'
    $checkout = [IO.File]::ReadAllText("$checkoutData\quests.jsonl")
    $ours = [IO.File]::ReadAllText("$realDir\data\quests.jsonl")
    Write-Output ("Info: the real files give {0:N0} quests a maxLevel; the result {1} the checkout's own data." -f $added, $(if ($ours -ceq $checkout) { 'is' } else { 'is not' }))
}

Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "$Passed checks passed, $Failed failed"
if ($Failed -gt 0) { exit 1 }
