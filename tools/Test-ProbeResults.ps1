<#
Checks that the probe's saved variables and the retail type probe's (pull request #42) read the same way:
Read-ForeverProbe.lua's quest and fact lines, ProbeResults.ps1's Get-ProbeQuests on a file of each kind made
here, and Retype-ProbeRecurring.ps1 and Find-UnavailableQuestCandidates.ps1 run on a scratch copy of the
data with each, which must retype and report the same, and Compare-PinNpcNames.ps1 on made-up pins and
NPC names. When the #42 probe's real results are in
tools\quest_type_probe_results.lua (or -RealOld names a copy), they are converted to the probe's form and
must read the same too. Nothing in the checkout is written.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ProbeResults.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param(
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [string]$RealOld = (Join-Path $PSScriptRoot 'quest_type_probe_results.lua')
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\ProbeResults.ps1"
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("probe-results-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null

# Rows: id, load flag (1 loaded, 0 failed, t timed out), classification.
$Cases = @(
    @(110, '1', 5), @(111, '1', 7), @(112, '1', 7), @(113, '1', 5), @(114, '1', 7), @(115, 't', 7), @(116, '0', 7), @(117, '1', 0)
)
function Write-OldFile([string]$path, $cases, [string]$build = '12.1.0.69933') {
    $rows = ($cases | ForEach-Object { '[' + $_[0] + '] = "1|7,0,0,0,-,0|' + $_[2] + ',0,' + $_[1] + '",' }) -join "`n"
    [IO.File]::WriteAllText($path, "qcSettings = {`n[""SORT""] = 1,`n}`nqcQuestTypeProbeResults = {`n[""client""] = ""$build"",`n[""quests""] = {`n$rows`n},`n}`n")
}
function Write-NewFile([string]$path, $cases, [string]$build = '12.1.0.69933', [string]$extra = '') {
    $results = @{ '1' = 'ok'; '0' = 'fail'; 't' = 'timeout' }
    $rows = ($cases | ForEach-Object {
        $result = $results[$_[1]]
        $class = if ($_[1] -eq '1') { ', classification = ' + $_[2] } else { '' }
        '[' + $_[0] + '] = {build = "' + $build + '", result = "' + $result + '"' + $class + ', level = 10, accountQuest = false},'
    }) -join "`n"
    [IO.File]::WriteAllText($path, "QCForeverProbeDB = {`nquests = {`n$rows`n$extra`n},`nnpcs = {},`ngivers = {},`nstarted = {},`naccepted = {},`nmaps = {},`nruns = {},`nlogins = {},`n}`n")
}

try {
    # --- the reader and the helper ---------------------------------------------------------------
    $old = "$Scratch\old.lua"; $new = "$Scratch\new.lua"
    Write-OldFile $old $Cases
    Write-NewFile $new $Cases
    $lines = @(& $LuaExe "$PSScriptRoot\Read-ForeverProbe.lua" $new)
    Equal $LASTEXITCODE 0 'T1: the probe reader runs'
    Check ($lines -contains "quest`t110`t12.1.0.69933`tok`t5") 'T1: a quest line has the classification as its fifth column'
    Check ($lines -contains "quest`t115`t12.1.0.69933`ttimeout`t") 'T1: and none for a quest that did not load'
    Check (@($lines | Where-Object { $_.StartsWith("fact`t") }).Count -eq 0) 'T1: no fact lines by default'
    $facts = @(& $LuaExe "$PSScriptRoot\Read-ForeverProbe.lua" $new facts)
    Check ($facts -contains "fact`t110`taccountQuest`tfalse") 'T1: facts lists each field of a row, false included'
    Check ($facts -contains "fact`t110`tlevel`t10") 'T1: a number'
    Check (@($facts | Where-Object { $_ -match "^fact`t\d+`t(build|result)`t" }).Count -eq 0) 'T1: but not the build or the result'
    Check (@($facts | Where-Object { $_ -match "^(run|runfact|trivialrange|refusedfact)`t" }).Count -eq 0) 'T1: and a file with no runs has no run lines'
    $withRuns = "$Scratch\runs.lua"
    [IO.File]::WriteAllText($withRuns, "QCForeverProbeDB = {`nquests = {},`nnpcs = {},`ngivers = {},`nstarted = {},`naccepted = {},`nmaps = {},`nlogins = {},`nruns = {`n{kind = `"quests`", build = `"1.60.1.70338`", time = 5, character = `"Alliance NightElf ROGUE`", level = 13, answered = 7, asked = 9,`nfacts = {accountQuest = `"C_QuestLog.IsAccountQuest`", trivial = `"C_QuestLog.IsQuestTrivial`", contentDifficulty = `"C_PlayerInfo.GetContentDifficultyQuestForPlayer`", expansion = false},`ntrivialRange = {UnitQuestTrivialLevelRange = 6, UnitQuestTrivialLevelRangeScaling = false},`nrefusedFacts = {questLineID = {asked = 2, answered = 1, positive = 1, examples = {1001, 1005}}, accountQuest = {asked = 2, answered = 2, positive = 0, examples = {}}}},`n{kind = `"maps`", build = `"1.60.1.70338`", time = 6, answered = 60, asked = 60},`n},`n}`n")
    $runLines = @(& $LuaExe "$PSScriptRoot\Read-ForeverProbe.lua" $withRuns facts)
    Check ($runLines -contains "run`t1`tquests`t1.60.1.70338`t5`tAlliance NightElf ROGUE`t13`t7`t9") 'T1: facts gives each run, with its character and level'
    Check ($runLines -contains "run`t2`tmaps`t1.60.1.70338`t6`t`t`t60`t60") 'T1: and one that kept no character as empty fields'
    Check ($runLines -contains "runfact`t1`ttrivial`tC_QuestLog.IsQuestTrivial") 'T1: and the function that answered each fact of a quest run'
    Check ($runLines -contains "runfact`t1`tcontentDifficulty`tC_PlayerInfo.GetContentDifficultyQuestForPlayer") 'T1: the content difficulty too'
    Check ($runLines -contains "runfact`t1`texpansion`tfalse") 'T1: false for a function the client lacks'
    Check ($runLines -contains "trivialrange`t1`tUnitQuestTrivialLevelRange`t6") 'T1: and the run character''s trivial ranges'
    Check ($runLines -contains "trivialrange`t1`tUnitQuestTrivialLevelRangeScaling`tfalse") 'T1: false for a range call the client lacks'
    Check (@($runLines | Where-Object { $_ -match "^(runfact|trivialrange)`t2`t" }).Count -eq 0) 'T1: a run that kept neither has none of those lines'
    Check ($runLines -contains "refusedfact`t1`tquestLineID`t2`t1`t1`t1001,1005") 'T1: and what a function said for refused quests, with examples'
    Check ($runLines -contains "refusedfact`t1`taccountQuest`t2`t2`t0`t") 'T1: a function that only said no has no examples'
    Check (@(& $LuaExe "$PSScriptRoot\Read-ForeverProbe.lua" $withRuns | Where-Object { $_ -match "^(run|runfact|trivialrange|refusedfact)`t" }).Count -eq 0) 'T1: and the plain mode prints none of it'
    $levelRows = @(
        '[1] = {build = "12.1.5.70400", result = "ok", level = 10, trivial = true, contentDifficulty = 0},',
        '[2] = {build = "12.1.5.70400", result = "ok", level = 40, trivial = false, contentDifficulty = 2},',
        '[3] = {build = "12.1.5.70400", result = "cached", level = 41, trivial = false, contentDifficulty = 3},',
        '[4] = {build = "12.1.5.70400", result = "late", level = 20, trivial = true, contentDifficulty = 1},',
        '[5] = {build = "12.1.5.70400", result = "ok", level = 30},',
        '[6] = {build = "12.1.5.70400", result = "ok", level = 31, trivial = false, contentDifficulty = "hard"},',
        '[7] = {build = "12.1.5.70400", result = "fail"},',
        '[8] = {build = "12.1.0.69933", result = "ok", level = 5, trivial = true, contentDifficulty = 0},',
        '[9] = {build = "12.1.5.70400", result = "timeout"},',
        '[10] = {build = "12.1.5.70400", result = "ok", level = 12, trivial = true, contentDifficulty = 4},'
    ) -join "`n"
    $levelRuns = @(
        '{kind = "quests", build = "12.1.5.70400", time = 5, character = "Horde Orc WARRIOR", level = 20, answered = 9, asked = 10, facts = {trivial = "C_QuestLog.IsQuestTrivial", contentDifficulty = "C_PlayerInfo.GetContentDifficultyQuestForPlayer"}, trivialRange = {UnitQuestTrivialLevelRange = 4, UnitQuestTrivialLevelRangeScaling = 7}},',
        '{kind = "quests", build = "12.1.5.70400", time = 9, character = "Alliance Human MAGE", level = 40, answered = 9, asked = 10, facts = {trivial = "C_QuestLog.IsQuestTrivial", contentDifficulty = "C_PlayerInfo.GetContentDifficultyQuestForPlayer"}, trivialRange = {UnitQuestTrivialLevelRange = 6, UnitQuestTrivialLevelRangeScaling = false}},',
        '{kind = "maps", build = "12.1.5.70400", time = 10, character = "Alliance Human MAGE", level = 40, answered = 60, asked = 60},',
        '{kind = "quests", build = "12.1.5.70400", time = 11, character = "Alliance Human MAGE", level = 40, answered = 9, asked = 10, facts = {accountQuest = "C_QuestLog.IsAccountQuest"}},'
    ) -join "`n"
    $levelFile = "$Scratch\levels.lua"
    [IO.File]::WriteAllText($levelFile, "QCForeverProbeDB = {`nquests = {`n$levelRows`n},`nnpcs = {},`ngivers = {},`nstarted = {},`naccepted = {},`nmaps = {},`nlogins = {},`nruns = {`n$levelRuns`n},`n}`n")
    $levels = @(& $LuaExe "$PSScriptRoot\Read-ForeverProbe.lua" $levelFile facts)
    Check ($levels -contains "fact`t1`ttrivial`ttrue") 'T1: the content of IsQuestTrivial is a fact line, true'
    Check ($levels -contains "fact`t2`ttrivial`tfalse") 'T1: and false'
    Check ($levels -contains "fact`t10`tcontentDifficulty`t4") 'T1: the content difficulty, a number'
    Check ($levels -contains "fact`t1`tcontentDifficulty`t0") 'T1: and Trivial (0), which is a value too'

    $a = Get-ProbeQuests $old $LuaExe
    $b = Get-ProbeQuests $new $LuaExe
    Equal $a.Format 'typecheck' 'T2: the #42 file is read as that'
    Equal $b.Format 'probe' 'T2: the probe file as that'
    Equal $a.Build '12.1.0.69933' 'T2: the #42 build'
    Equal $b.Build '12.1.0.69933' 'T2: the probe build'
    Equal $a.Quests.Count $Cases.Count 'T2: every #42 row'
    Equal $b.Quests.Count $Cases.Count 'T2: every probe row'
    foreach ($case in $Cases) {
        $id = [string]$case[0]
        Equal $b.Quests[$id].Load $a.Quests[$id].Load "T2: quest $id loads the same"
        if ($a.Quests[$id].Load -eq '1') { Equal $b.Quests[$id].Classification $a.Quests[$id].Classification "T2: and, loaded, classifies the same" }
    }
    Equal $b.Quests['110'].Load '1' 'T2: ok is loaded'
    Equal $b.Quests['116'].Load '0' 'T2: fail is refused'
    Equal $b.Quests['115'].Load 't' 'T2: timeout is timed out'
    Equal $b.Quests['115'].Classification $null 'T2: with no classification'
    $mixed = "$Scratch\mixed.lua"
    Write-NewFile $mixed @(@(1, '1', 7), @(2, '1', 7), @(3, '1', 5)) '12.1.0.69933' '[4] = {build = "1.60.1.70245", result = "ok", classification = 7}, [5] = {build = "12.1.0.69933", result = "unknown"}, [6] = {build = "12.1.0.69933", result = "late"},'
    $m = Get-ProbeQuests $mixed $LuaExe
    Equal $m.Build '12.1.0.69933' 'T3: with two builds in a file, the one most quests were answered on'
    Check (-not $m.Quests.ContainsKey('4')) 'T3: a quest of the other build is left out'
    Check (-not $m.Quests.ContainsKey('5')) 'T3: and one with a result that means nothing'
    Equal $m.Quests['6'].Load '1' 'T3: an answer that came late is a loaded quest'
    Equal $m.Quests['6'].Classification $null 'T3: with no classification when the client gave none'
    $threw = $false; try { Get-ProbeQuests "$Scratch\nothing.lua" $LuaExe } catch { $threw = $true }
    Check $threw 'T4: a file that is not there is an error'
    [IO.File]::WriteAllText("$Scratch\other.lua", "something = {}`n")
    $threw = $false; try { Get-ProbeQuests "$Scratch\other.lua" $LuaExe } catch { $threw = $true }
    Check $threw 'T4: and so is a file that holds neither probe'
    [IO.File]::WriteAllText("$Scratch\empty.lua", "QCForeverProbeDB = { quests = {}, npcs = {} }`n")
    $threw = $false; try { Get-ProbeQuests "$Scratch\empty.lua" $LuaExe } catch { $threw = $true }
    Check $threw 'T4: and a probe file with no quests'

    # which file the tools take when none is named
    New-Item -ItemType Directory -Path "$Scratch\tools\retail_probe_69933", "$Scratch\tools\retail_probe_70100" -Force | Out-Null
    Copy-Item $new "$Scratch\tools\retail_probe_69933\QCForeverProbe.lua"
    Copy-Item $new "$Scratch\tools\retail_probe_70100\QCForeverProbe.lua"
    Equal (Find-ProbeResults "$Scratch\tools") "$Scratch\tools\retail_probe_70100\QCForeverProbe.lua" 'T5: the newest retail probe copy'
    Remove-Item "$Scratch\tools\retail_probe_69933", "$Scratch\tools\retail_probe_70100" -Recurse
    Equal (Find-ProbeResults "$Scratch\tools") "$Scratch\tools\quest_type_probe_results.lua" 'T5: else the #42 file'

    # the level facts: IsQuestTrivial and the content difficulty, tallied for the last quest run that asked
    $lf = Get-ProbeLevelFacts $levelFile $LuaExe
    Equal $lf.Build '12.1.5.70400' 'T9: the level facts are of the run''s build'
    Equal $lf.Character 'Alliance Human MAGE' 'T9: of the last quest run that asked IsQuestTrivial (not the one before, not the map run, not a later one that did not ask)'
    Equal $lf.CharacterLevel 40 'T9: with its character''s level'
    Equal $lf.TrivialFunction 'C_QuestLog.IsQuestTrivial' 'T9: the function that answered IsQuestTrivial'
    Equal $lf.DifficultyFunction 'C_PlayerInfo.GetContentDifficultyQuestForPlayer' 'T9: and the difficulty'
    Equal $lf.TrivialRange 6 'T9: the character''s trivial range'
    Check ($lf.TrivialRangeScaling -is [bool] -and -not $lf.TrivialRangeScaling) 'T9: and $false for a scaling range the client lacks'
    Equal $lf.Loaded 7 'T9: seven loaded quests of that build (not the refused one, the timed-out one or the other build''s)'
    Equal $lf.Trivial['true'] 3 'T9: three are trivial'
    Equal $lf.Trivial['false'] 3 'T9: three are not'
    Equal $lf.Trivial['none'] 1 'T9: and one has no answer'
    foreach ($d in '0', '1', '2', '3', '4', 'none', 'other') { Equal $lf.Difficulty[$d] 1 "T9: one quest has difficulty $d" }
    Equal $lf.Together['true/0'] 1 'T9: a trivial quest the game calls Trivial'
    Equal $lf.Together['true/4'] 1 'T9: and one it calls Impossible, so the two do not always agree'
    Equal $lf.Together['false/3'] 1 'T9: a quest that is not trivial and Difficult'
    Equal $lf.Together['none/none'] 1 'T9: one with neither answer'
    Equal $lf.Together['false/other'] 1 'T9: and one with an answer that is not 0 to 4'
    Equal $lf.Quests['2'].Level 40 'T9: a quest keeps the level the game gave'
    Check ($lf.Quests['2'].Trivial -is [bool] -and -not $lf.Quests['2'].Trivial) 'T9: and IsQuestTrivial, as a boolean'
    Equal $lf.Quests['2'].Difficulty 2 'T9: and the difficulty, as a number'
    Check ($lf.Quests['1'].Trivial -is [bool] -and $lf.Quests['1'].Trivial) 'T9: true as true'
    Equal $lf.Quests['1'].Difficulty 0 'T9: Trivial (0) as 0'
    Check ($null -eq $lf.Quests['5'].Trivial -and $null -eq $lf.Quests['5'].Difficulty) 'T9: a quest with no answer has none'
    Check ($null -eq $lf.Quests['6'].Difficulty) 'T9: nor does one whose difficulty is not 0 to 4'
    Check (-not $lf.Quests.ContainsKey('7') -and -not $lf.Quests.ContainsKey('8') -and -not $lf.Quests.ContainsKey('9')) 'T9: a refused, a timed-out and another build''s quest are left out'
    $noFunctions = "$Scratch\no-functions.lua"
    [IO.File]::WriteAllText($noFunctions, "QCForeverProbeDB = {`nquests = {`n[1] = {build = `"1.60.1.70338`", result = `"ok`", level = 3},`n},`nnpcs = {},`ngivers = {},`nstarted = {},`naccepted = {},`nmaps = {},`nlogins = {},`nruns = {`n{kind = `"quests`", build = `"1.60.1.70338`", time = 5, character = `"Alliance Human MAGE`", level = 3, answered = 1, asked = 1, facts = {trivial = false, contentDifficulty = false}},`n},`n}`n")
    $nf = Get-ProbeLevelFacts $noFunctions $LuaExe
    Check ($nf.TrivialFunction -is [bool] -and -not $nf.TrivialFunction -and $nf.DifficultyFunction -is [bool] -and -not $nf.DifficultyFunction) 'T9: a client without either function says $false for both'
    Check ($null -eq $nf.TrivialRange -and $null -eq $nf.TrivialRangeScaling) 'T9: and a run that kept no ranges has none'
    Equal $nf.Trivial['none'] 1 'T9: so its quest has no answer'
    Equal $nf.Quests['1'].Level 3 'T9: but has its level'
    $oldRun = "$Scratch\old-run.lua"
    [IO.File]::WriteAllText($oldRun, "QCForeverProbeDB = {`nquests = {},`nnpcs = {},`ngivers = {},`nstarted = {},`naccepted = {},`nmaps = {},`nlogins = {},`nruns = {`n{kind = `"quests`", build = `"1.60.1.70338`", time = 5, level = 3, answered = 1, asked = 1, facts = {accountQuest = `"C_QuestLog.IsAccountQuest`"}},`n},`n}`n")
    $threw = $false; try { Get-ProbeLevelFacts $oldRun $LuaExe } catch { $threw = "$_" -match 'asked IsQuestTrivial' }
    Check $threw 'T9: a file whose quest runs never asked IsQuestTrivial is an error that says so'
    $threw = $false; try { Get-ProbeLevelFacts "$Scratch\nothing.lua" $LuaExe } catch { $threw = $true }
    Check $threw 'T9: and so is a file that is not there'

    # --- Retype-ProbeRecurring.ps1 on a scratch copy of the data ---------------------------------
    function New-World([string]$name) {
        $root = Join-Path $Scratch $name
        foreach ($dir in 'tools\quest_api_cache', 'data\forever', 'addon') { New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null }
        $quests = foreach ($id in 110..118) {
            '{"id":' + $id + ',"name":"Q' + $id + '","level":10,"zone":"","category":10,"type":1,"faction":2,"race":67108863,"class":8191}'
        }
        [IO.File]::WriteAllText("$root\data\quests.jsonl", (($quests -join "`n") + "`n"))
        [IO.File]::WriteAllText("$root\data\pins.jsonl", '{"map":1,"icon":1,"x":50,"y":50,"quests":[110]}' + "`n")
        [IO.File]::WriteAllText("$root\addon\QuestCompletist.toc", "## Interface: 120100, 120105`r`n")
        [IO.File]::WriteAllText("$root\addon\QuestCompletist_Camelot.toc", "## Interface: 16001`r`n")
        [IO.File]::WriteAllText("$root\addon\qcUnavailableQuests.lua", "qcUnavailableQuests = {`r`n}`r`n")
        $null = Invoke-AddonDataBuild -DataDir "$root\data" -AddonDir "$root\addon"
        # the API's word on each: 110 daily, 111 weekly, 112 repeatable only, 113 and 114 and 116 not served, 115 daily
        [IO.File]::WriteAllText("$root\tools\quest_api_cache\110.json", '{"is_daily":true,"is_weekly":false,"is_repeatable":false}')
        [IO.File]::WriteAllText("$root\tools\quest_api_cache\111.json", '{"is_daily":false,"is_weekly":true,"is_repeatable":false}')
        [IO.File]::WriteAllText("$root\tools\quest_api_cache\112.json", '{"is_daily":false,"is_weekly":false,"is_repeatable":true}')
        foreach ($id in 113, 114, 116) { [IO.File]::WriteAllText("$root\tools\quest_api_cache\$id.404", '') }
        [IO.File]::WriteAllText("$root\tools\quest_api_cache\115.json", '{"is_daily":true,"is_weekly":false,"is_repeatable":false}')
        [IO.File]::WriteAllText("$root\tools\QuestV2-12.1.0.69933.csv", "ID`r`n110`r`n111`r`n112`r`n113`r`n115`r`n116`r`n117`r`n")
        [IO.File]::WriteAllText("$root\tools\QuestV2CliTask.csv", "ID`r`n")
        return $root
    }
    $results = @{}
    foreach ($kind in 'old', 'new') {
        $root = New-World "retype-$kind"
        $file = if ($kind -eq 'old') { $old } else { $new }
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Retype-ProbeRecurring.ps1" -ToolsDir "$root\tools" -DataDir "$root\data" -AddonDir "$root\addon" -ProbeResults $file -LuaExe $LuaExe 2>&1 | ForEach-Object { "$_" }
        $results[$kind] = @{ Text = ($output -join "`n"); Quests = [IO.File]::ReadAllText("$root\data\quests.jsonl"); Exit = $LASTEXITCODE }
    }
    Equal $results.old.Exit 0 'T6: Retype runs on the #42 results'
    Equal $results.new.Exit 0 'T6: and on the probe''s'
    Equal $results.new.Quests $results.old.Quests 'T6: and retypes the same'
    $types = @{}
    foreach ($line in ($results.new.Quests -split "`n")) { if ($line -match '"id":(\d+).*"type":(\d+)') { $types[$Matches[1]] = [int]$Matches[2] } }
    Equal $types['110'] 4 'T6: daily and Recurring becomes daily'
    Equal $types['111'] 1 'T6: weekly and Normal is left alone'
    Equal $types['112'] 2 'T6: repeatable only and Normal becomes repeatable'
    Equal $types['113'] 128 'T6: unflagged and Recurring becomes 128'
    Equal $types['114'] 2 'T6: unflagged, Normal and not in QuestV2 becomes repeatable'
    Equal $types['115'] 4 'T6: daily and not loaded becomes daily'
    Equal $types['116'] 1 'T6: unflagged and refused is left alone'
    Equal $types['117'] 1 'T6: a quest the API cache has not fetched is left alone'
    Equal ($results.new.Text -replace '(?s)\s+$', '') ($results.old.Text -replace '(?s)\s+$', '') 'T6: and says the same'

    # --- Find-UnavailableQuestCandidates.ps1 ---------------------------------------------------------
    $signals = @{}
    foreach ($kind in 'old', 'new') {
        $root = New-World "unavailable-$kind"
        foreach ($t in 'QuestV2', 'QuestV2CliTask', 'QuestPOIBlob', 'QuestLineXQuest', 'Criteria') {
            $header = switch ($t) { 'QuestPOIBlob' { "ID,QuestID,ObjectiveIndex" } 'QuestLineXQuest' { "ID,QuestID" } 'Criteria' { "ID,Type,Asset" } default { "ID" } }
            if ($t -eq 'QuestV2') { Copy-Item "$root\tools\QuestV2-12.1.0.69933.csv" "$root\tools\QuestV2.csv" }
            else { [IO.File]::WriteAllText("$root\tools\$t.csv", "$header`r`n") }
        }
        New-Item -ItemType Directory -Path "$root\docs" -Force | Out-Null
        [IO.File]::WriteAllText("$root\docs\decisions.csv", "QuestID,Decision`r`n")
        $file = if ($kind -eq 'old') { $old } else { $new }
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Find-UnavailableQuestCandidates.ps1" -ToolsDir "$root\tools" -DataDir "$root\data" -Decisions "$root\docs\decisions.csv" -ProbeResults $file -LuaExe $LuaExe 2>&1 | ForEach-Object { "$_" }
        $signals[$kind] = @{ Exit = $LASTEXITCODE; Csv = [IO.File]::ReadAllText("$root\tools\quest_availability_signals.csv") }
    }
    Equal $signals.old.Exit 0 'T7: the unavailable-quest report runs on the #42 results'
    Equal $signals.new.Exit 0 'T7: and on the probe''s'
    Equal $signals.new.Csv $signals.old.Csv 'T7: and writes the same signals'
    $byId = @{}
    foreach ($row in ($signals.new.Csv | ConvertFrom-Csv)) { $byId[$row.QuestID] = $row.ServerKnows }
    Equal $byId['110'] '1' 'T7: loaded is ServerKnows 1'
    Equal $byId['116'] '0' 'T7: refused is 0'
    Equal $byId['115'] '' 'T7: timed out is blank'
    Equal $byId['118'] '' 'T7: and so is a quest the probe never asked'

    # --- Compare-PinNpcNames.ps1 -----------------------------------------------------------------
    $root = Join-Path $Scratch 'names'
    foreach ($dir in 'tools\retail_probe_69933', 'data', 'docs') { New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null }
    $npcs = @(
        '[1] = {build = "12.1.0.69933", result = "now", name = "Guard Roberts"}',
        '[2] = {build = "12.1.0.69933", result = "poll", name = "Fizzi Liverzapper"}',
        '[3] = {build = "12.1.0.69933", result = "now", name = "Andorgos"}',
        '[4] = {build = "12.1.0.69933", result = "now", name = "Azj-Kahet Flame Guardian"}',
        '[5] = {build = "12.1.0.69933", result = "now", name = "Other Person"}',
        '[6] = {build = "12.1.0.69933", result = "none"}',
        '[8] = {build = "1.60.1.70205", result = "now", name = "Old build"}'
    ) -join ",`n"
    [IO.File]::WriteAllText("$root\tools\retail_probe_69933\QCForeverProbe.lua", "QCForeverProbeDB = {`nquests = {},`nnpcs = {`n$npcs`n},`ngivers = {},`nstarted = {},`naccepted = {},`nmaps = {},`nruns = {},`nlogins = {},`n}`n")
    $pins = @(
        '{"map":1,"icon":1,"npc":1,"name":"Guard Roberts","x":10,"y":10,"quests":[100]}',
        '{"map":1,"icon":1,"npc":2,"name":"Fizzi Liverzapper ","x":20,"y":20,"quests":[101]}',
        '{"map":1,"icon":1,"npc":3,"name":"Andorgos <Brood of Malygos>","x":30,"y":30,"quests":[102,103]}',
        '{"map":1,"icon":1,"npc":4,"name":"Azj","x":40,"y":40,"quests":[104]}',
        '{"map":1,"icon":1,"npc":5,"name":"Someone","x":50,"y":50.5,"quests":[105,106,107,108]}',
        '{"map":1,"icon":1,"npc":6,"name":"Lost","x":60,"y":60,"quests":[109]}',
        '{"map":1,"icon":1,"npc":7,"name":"New","x":70,"y":70,"quests":[110]}',
        '{"map":1,"icon":1,"npc":8,"name":"Old build","x":75,"y":75,"quests":[111]}',
        '{"map":1,"icon":1,"npc":0,"name":"Object","x":80,"y":80,"quests":[112]}',
        '{"map":1,"icon":1,"x":90,"y":90,"quests":[113]}'
    )
    [IO.File]::WriteAllText("$root\data\pins.jsonl", (($pins -join "`n") + "`n"))
    [IO.File]::WriteAllText("$root\docs\decisions.csv", "Action,Map,X,Y,Name`r`nID,1,50.0,50.5,Someone`r`n")
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Compare-PinNpcNames.ps1" -Game retail -ToolsDir "$root\tools" -DataDir "$root\data" -Decisions "$root\docs\decisions.csv" -LuaExe $LuaExe 2>&1 | ForEach-Object { "$_" }
    $text = $output -join "`n"
    Equal $LASTEXITCODE 0 'T8: the NPC-name comparison runs'
    Check ($text -match 'build 12\.1\.0\.69933, 6 NPCs asked, 5 named') "T8: it takes the probe's build, not the other ($text)"
    Check ($text -match 'Pins compared: 8 ') 'T8: the pins with an ID and a name are compared'
    Check ($text -match '(?m)^  same\s+1\s*$') 'T8: one is the same'
    Check ($text -match '(?m)^  spacing\s+2\s*\(2 without') 'T8: two differ only in spacing or a title'
    Check ($text -match '(?m)^  contains\s+1\s*\(1 without') 'T8: one holds the other name'
    Check ($text -match '(?m)^  differs\s+1\s*\(0 without') 'T8: one names another creature, and has a row in the decisions file'
    Check ($text -match '(?m)^  not named\s+1\s*\(1 without') 'T8: one the game never named'
    Check ($text -match '(?m)^  not asked\s+2\s*\(2 without') 'T8: two that the probe did not ask for (one only on another build)'
    $csv = @(Import-Csv "$root\tools\pin_npc_names_retail.csv")
    Equal $csv.Count 7 'T8: every pin that is not the same is in the file'
    Equal ($csv | Where-Object Class -eq 'differs').Decided 'ID' 'T8: and says what the decisions file has for it'
    Equal ($csv | Where-Object Class -eq 'differs').Quests '105 106 107' 'T8: with the first three quests'
    Equal ($csv | Where-Object { $_.Name -like 'Andorgos*' }).GameNameForId 'Andorgos' 'T8: and the game''s name'
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Compare-PinNpcNames.ps1" -Game forever -ToolsDir "$root\tools" -DataDir "$root\data" -LuaExe $LuaExe 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $saved }
    Check ($LASTEXITCODE -ne 0 -and ($output -join ' ') -match 'There are no probe results') 'T8: Forever with no Forever probe results is refused'

    # --- the real #42 results, when this checkout has them ---------------------------------------
    if (Test-Path $RealOld) {
        $real = Get-ProbeQuests $RealOld $LuaExe
        $rows = New-Object System.Collections.Generic.List[string]
        foreach ($id in $real.Quests.Keys) {
            $q = $real.Quests[$id]
            $result = switch ($q.Load) { '1' { 'ok' } '0' { 'fail' } default { 'timeout' } }
            $class = if ($null -ne $q.Classification -and $q.Load -eq '1') { ', classification = ' + $q.Classification } else { '' }
            $rows.Add('[' + $id + '] = {build = "' + $real.Build + '", result = "' + $result + '"' + $class + '},')
        }
        [IO.File]::WriteAllText("$Scratch\real-new.lua", "QCForeverProbeDB = {`nquests = {`n" + ($rows -join "`n") + "`n},`n}`n")
        $converted = Get-ProbeQuests "$Scratch\real-new.lua" $LuaExe
        Equal $converted.Build $real.Build 'R1: the real results converted to the probe''s form keep their build'
        Equal $converted.Quests.Count $real.Quests.Count 'R1: and their quests'
        $differ = 0
        foreach ($id in $real.Quests.Keys) {
            $x = $real.Quests[$id]; $y = $converted.Quests[$id]
            if ($x.Load -ne $y.Load -or ($x.Load -eq '1' -and $x.Classification -ne $y.Classification)) { $differ++ }
        }
        Equal $differ 0 'R1: and read the same, quest for quest (a quest that did not load has no classification that counts)'
    }
}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
