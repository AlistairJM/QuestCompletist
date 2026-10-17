<#
Checks the renown rows of AddonData.ps1 and Sync-QuestRenown.ps1 (step 2o) on made-up client tables and a data folder in a
temporary folder: nothing in the checkout is touched and nothing is downloaded. It checks the data file's form and
checks, the Lua table and its order, the build (a quest no longer in the data left out, the count, a second build that
changes nothing, an unknown field stopping it), and a run of the step: the rows it finds, the hand rows it agrees with,
differs from and says nothing about, what it adds, and a second run and a -WhatIf run that write nothing.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncQuestRenown.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Row($quest, $faction, $level) { [pscustomobject]@{ quest = $quest; faction = $faction; level = $level } }

$rows = @((Row 101 9001 3), (Row 100 9000 7), (Row 101 9000 5))
Equal (ConvertTo-RenownJsonLines @($rows[1])) ('{"quest":100,"faction":9000,"level":7}' + "`n") 'J1: one row per line'
$problems = @(Test-RenownRecords @((Row 0 9000 1), (Row 100 9000 0), (Row 100 'x' 2), (Row 100 9000 2), (Row 100 9000 3)))
Check (@($problems | Where-Object { $_ -match "line 1: 'quest' must" }).Count -eq 1) 'T1: a quest of 0 is a problem'
Check (@($problems | Where-Object { $_ -match "line 2: 'level' must" }).Count -eq 1) 'T1: so is a level of 0'
Check (@($problems | Where-Object { $_ -match "line 3: 'faction' must" }).Count -eq 1) 'T1: and a faction that isn''t an ID'
Check (@($problems | Where-Object { $_ -match 'line 5: quest 100 and faction 9000 are also on line 4' }).Count -eq 1) 'T1: and a quest and faction listed twice'
Equal @(Test-RenownRecords $rows).Count 0 'T1: sound rows have none'
Equal (ConvertTo-LuaRenownTable $rows) "qcQuestRenown={`r`n[100]={{9000,7}},`r`n[101]={{9000,5},{9001,3}},`r`n}`r`n" 'L1: a list per quest, in quest and faction order'
Equal (ConvertTo-LuaRenownTable @()) "qcQuestRenown={`r`n}`r`n" 'L2: with none, the table is empty'

$root = Join-Path ([IO.Path]::GetTempPath()) ("quest_renown_test_" + [guid]::NewGuid().ToString('N'))
$data = Join-Path $root 'data'; $addon = Join-Path $root 'addon'; $tools = Join-Path $root 'tools'
New-Item -ItemType Directory -Force $data, $addon, $tools | Out-Null
try {
    $quests = foreach ($id in 100..104) { '{"id":' + $id + ',"name":"Quest ' + $id + '","level":70,"zone":"","category":1,"type":1,"faction":1,"race":64175181,"class":8191}' }
    [IO.File]::WriteAllText((Join-Path $data 'quests.jsonl'), ($quests -join "`n") + "`n")
    [IO.File]::WriteAllText((Join-Path $data 'pins.jsonl'), '{"map":1,"icon":1,"x":1,"y":1,"quests":[100]}' + "`n")
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    Check ($build.Ok -and [IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua')).Contains("qcQuestRenown={`r`n}`r`n")) 'B1: a data folder with no renown rows builds, with an empty table'
    Check (@($build.Lines | Where-Object { $_ -match 'renown rows' }).Count -eq 0) 'B1: and counts none'
    [IO.File]::WriteAllText((Join-Path $data 'renown.jsonl'), (ConvertTo-RenownJsonLines @($rows + (Row 999 9000 2))))
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    $lua = [IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua'))
    Check ($build.Ok -and $lua.Contains("qcQuestRenown={`r`n[100]={{9000,7}},`r`n[101]={{9000,5},{9001,3}},`r`n}`r`n")) 'B2: the rows are written, a quest no longer in the data left out'
    Check (@($build.Lines | Where-Object { $_ -match '4 renown rows' }).Count -eq 1) 'B2: and the file''s rows counted'
    Check (Invoke-AddonDataBuild -DataDir $data -AddonDir $addon -Check).Ok 'B3: a second build changes nothing'
    [IO.File]::WriteAllText((Join-Path $data 'renown.jsonl'), '{"quest":100,"faction":9000,"level":7,"rank":1}' + "`n")
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    Check (-not $build.Ok -and @($build.Lines | Where-Object { $_ -match "unknown field 'rank'" }).Count -eq 1) 'B4: an unknown field stops the build'

    # The step: renown currencies 500 (faction 9000) and 501 (faction 9001); quest 100 asks for 9000 at 7 by the
    # condition's own columns, 101 for both by its tree, 102 has no condition, 103 asks for a currency that is no renown,
    # 999 isn't ours. The hand rows: 100 agrees, 101 differs, 104 the client says nothing about.
    Remove-Item (Join-Path $data 'renown.jsonl')
    Check (Invoke-AddonDataBuild -DataDir $data -AddonDir $addon).Ok 'S0: the data folder builds again'
    $build = '900'
    function Write-Table([string]$name, [string]$header, [string[]]$lines) { [IO.File]::WriteAllText((Join-Path $tools $name), (@($header) + $lines) -join "`n") }
    Write-Table "Faction-$build.csv" 'ID,Name_lang,RenownCurrencyID' @('9000,First,500', '9001,Second,501', '9002,Third,0')
    Write-Table 'QuestV2CliTask.csv' 'ID,ConditionID' @('100,30', '101,31', '102,0', '103,34', '999,30')
    Write-Table "QuestLine-$build.csv" 'ID' @()
    Write-Table "QuestLineXQuest-$build.csv" 'QuestLineID,QuestID,OrderIndex' @()
    Write-Table "Campaign-$build.csv" 'ID' @()
    Write-Table "CampaignXQuestLine-$build.csv" 'CampaignID,QuestLineID,OrderIndex' @()
    Write-Table "CampaignXCondition-$build.csv" 'ID,CampaignID,OrderIndex,PlayerConditionID,FailureReason_lang' @()
    Write-Table "ModifierTree-$build.csv" 'ID,Parent,Operator,Amount,Type,Asset,SecondaryAsset' @('130,0,4,0,0,0,0', '131,130,2,0,119,500,5', '132,130,2,0,119,501,3')
    Write-Table 'PlayerCondition.csv' 'ID,PrevQuestLogic,PrevQuestID_0,PrevQuestID_1,PrevQuestID_2,PrevQuestID_3,ModifierTreeID,Flags,CovenantID,Failure_description_lang,CurrencyLogic,CurrencyID_0,CurrencyID_1,CurrencyID_2,CurrencyID_3,CurrencyCount_0,CurrencyCount_1,CurrencyCount_2,CurrencyCount_3' @(
        '30,0,0,0,0,0,0,0,0,,0,500,0,0,0,7,0,0,0', '31,0,0,0,0,0,130,0,0,,0,0,0,0,0,0,0,0,0', '34,0,0,0,0,0,0,0,0,,0,999,0,0,0,10,0,0,0')
    [IO.File]::WriteAllText((Join-Path $addon 'qcQuest.lua'), "qcRenownLevelRequirements = {  -- QuestId FactionId RenownLevel`r`n`r`n`t[100]={9000, 7},`r`n`t[101]={9001, 4},`r`n`t[104]={9000, 2},`r`n}`r`n")
    $step = @{ Build = $build; ToolsDir = $tools; DataDir = $data; AddonDir = $addon }
    $out = @(& (Join-Path $PSScriptRoot 'Sync-QuestRenown.ps1') @step 6>$null)
    Equal $out[0] 'Renown from the client''s conditions: 3 rows on 2 task quests (First 2, Second 1).' 'S1: the rows every way through each condition needs, ours only'
    Equal $out[1] 'Hand rows (qcRenownLevelRequirements): 3; the client agrees with 1, differs from 1, says nothing about 1. Differ: 101 ours Second 4, the client''s First 5, Second 3' 'S2: the hand rows'' standing'
    Equal $out[2] 'Added 3, changed 0, gone 0: +100|9000 +101|9000 +101|9001' 'S3: the rows added'
    Equal ([IO.File]::ReadAllText((Join-Path $data 'renown.jsonl'))) (ConvertTo-RenownJsonLines @((Row 100 9000 7), (Row 101 9000 5), (Row 101 9001 3))) 'S3: and written'
    Check ([IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua')).Contains("[101]={{9000,5},{9001,3}},")) 'S3: and built'
    $out = @(& (Join-Path $PSScriptRoot 'Sync-QuestRenown.ps1') @step 6>$null)
    Equal $out[2] 'Added 0, changed 0, gone 0' 'S4: a second run finds nothing to change'
    $edited = '{"quest":100,"faction":9000,"level":6}' + "`n" + '{"quest":101,"faction":9000,"level":5}' + "`n" + '{"quest":101,"faction":9001,"level":3}' + "`n" + '{"quest":103,"faction":9000,"level":2}' + "`n"
    [IO.File]::WriteAllText((Join-Path $data 'renown.jsonl'), $edited)
    $out = @(& (Join-Path $PSScriptRoot 'Sync-QuestRenown.ps1') @step -WhatIf 6>$null)
    Equal $out[2] 'Added 0, changed 1, gone 1: ~100|9000 -103|9000' 'S5: a row changed and one gone'
    Equal ([IO.File]::ReadAllText((Join-Path $data 'renown.jsonl'))) $edited 'S5: -WhatIf writes nothing'
}
finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output "$Passed checks passed, $Failed failed."
if ($Failed -gt 0) { exit 1 }
