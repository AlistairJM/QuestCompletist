<#
Checks CampaignRecap.ps1 and Compare-CampaignRecap.ps1 (step 2q) on made-up client tables and data in a temporary
folder: nothing in the checkout is touched and nothing is downloaded. It checks the quest each recap entry names (by its
condition's own quests, by its ModifierTree, none), the quests a quest needs however far back, the pairs of entries next
to each other that our chains run the other way, the decisions file, and runs that list a reversal with no row, a KEEP
row that no longer fits, the recap's quests the data lacks and ours with no quest line.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-CompareCampaignRecap.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
. (Join-Path $PSScriptRoot 'QuestConditions.ps1')
. (Join-Path $PSScriptRoot 'CampaignRecap.ps1')
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("campaign_recap_test_" + [guid]::NewGuid().ToString('N'))
$tools = Join-Path $root 'tools'; $data = Join-Path $root 'data'
New-Item -ItemType Directory -Force $tools, $data | Out-Null
try {
    $build = '9.9.9.1'
    function Write-Table([string]$name, [string]$header, [string[]]$lines) { [IO.File]::WriteAllText((Join-Path $tools $name), ((@($header) + $lines) -join "`n") + "`n") }
    # Campaign 1's recap: quests 10, 11, 12 (by a tree), 99 (not ours) and an entry that names none; campaign 2's: 20, 21.
    Write-Table "QuestLine-$build.csv" 'ID,Name_lang,PlayerConditionID' @('1,Line One,0', '2,Line Two,0')
    Write-Table "QuestLineXQuest-$build.csv" 'QuestLineID,QuestID,OrderIndex' @('1,10,0', '1,11,1', '2,20,0', '2,21,1')
    Write-Table "Campaign-$build.csv" 'ID,Title_lang,Prerequisite' @('1,First,0', '2,Second,0')
    Write-Table "CampaignXQuestLine-$build.csv" 'CampaignID,QuestLineID,OrderIndex' @('1,1,0', '2,2,0')
    Write-Table "CampaignXCondition-$build.csv" 'ID,CampaignID,OrderIndex,PlayerConditionID,FailureReason_lang' @()
    Write-Table "ModifierTree-$build.csv" 'ID,Parent,Operator,Amount,Type,Asset,SecondaryAsset' @('300,0,0,0,110,12,0')
    Write-Table 'PlayerCondition.csv' 'ID,PrevQuestLogic,PrevQuestID_0,PrevQuestID_1,PrevQuestID_2,PrevQuestID_3,ModifierTreeID,Flags' @(
        '100,0,10,0,0,0,0,0', '101,0,11,0,0,0,0,0', '102,0,0,0,0,0,300,0', '103,0,99,0,0,0,0,0', '104,0,0,0,0,0,0,0', '200,0,20,0,0,0,0,0', '201,0,21,0,0,0,0,0')
    Write-Table "LoreTextPublic-$build.csv" 'LoreTextID,CampaignID,ConditionID,Flags,_Order,ParentID' @(
        '1,1,100,0,0,0', '2,1,101,0,1,0', '3,1,102,0,2,0', '4,1,103,0,3,0', '5,1,104,0,4,0', '6,2,200,0,0,0', '7,2,201,0,1,0')
    $quest = { param($id, $prereq) '{"id":' + $id + ',"name":"Quest ' + $id + '","level":10,"zone":"","category":1,"type":1,"faction":3,"race":67108863,"class":8191' + $(if ($prereq) { ',"prereq":' + $prereq } else { '' }) + '}' }
    [IO.File]::WriteAllText((Join-Path $data 'quests.jsonl'), ((@(@(10, 0), @(11, 12), @(12, 10), @(20, 21), @(21, 0)) | ForEach-Object { & $quest $_[0] $_[1] }) -join "`n") + "`n")
    [IO.File]::WriteAllText((Join-Path $data 'pins.jsonl'), '{"map":1,"icon":1,"x":1,"y":1,"quests":[10]}' + "`n")

    $c = Import-ClientConditions $tools $build
    $entries = @(Get-RecapEntries $c (Import-Csv (Join-Path $tools "LoreTextPublic-$build.csv")))
    Equal (($entries | ForEach-Object { "$($_.Campaign).$($_.Order)=$($_.Quest)" }) -join ' ') '1.0=10 1.1=11 1.2=12 1.3=99 1.4=0 2.0=20 2.1=21' 'E1: each entry''s quest: its condition''s own, its tree''s, or none'
    $quests = @{}; foreach ($q in (Read-QuestData $data)) { $quests[[int]$q.id] = $q }
    Equal (((Get-QuestsBefore $quests 11 @{}) | Sort-Object) -join ',') '10,12' 'E2: the quests a quest needs, however far back'
    $r = Get-RecapReversals $entries $quests
    Equal $r.Compared 3 'E3: the pairs of our quests next to each other in each recap'
    Equal (($r.Reversed | ForEach-Object { "$($_.Campaign):$($_.Quest)<$($_.Later)" }) -join ' ') '1:11<12 2:20<21' 'E3: the ones our chains run the other way'

    $decisionsFile = Join-Path $root 'decisions.csv'
    function Decisions($rows) { @($rows | ForEach-Object { [pscustomobject]@{ Campaign = "$($_[0])"; Quest = "$($_[1])"; Later = "$($_[2])"; Name = ''; Decision = $_[3]; Evidence = 'test' } }) | Export-Csv $decisionsFile -NoTypeInformation -Encoding UTF8 }
    Decisions @(, @(1, 11, 12, 'SET'))
    $threw = $false; try { Read-RecapDecisions $decisionsFile | Out-Null } catch { $threw = $_.Exception.Message -match 'only KEEP' }
    Check $threw 'D1: a decision other than KEEP stops the run'
    Decisions @(@(1, 11, 12, 'KEEP'), @(1, 11, 12, 'KEEP'))
    $threw = $false; try { Read-RecapDecisions $decisionsFile | Out-Null } catch { $threw = $_.Exception.Message -match 'listed twice' }
    Check $threw 'D1: so does a pair listed twice'

    $step = @{ Build = $build; ToolsDir = $tools; DataDir = $data; DecisionsFile = $decisionsFile; OutFile = (Join-Path $root 'recap.csv') }
    Decisions @(@(2, 20, 21, 'KEEP'), @(1, 10, 11, 'KEEP'))
    $out = @(& (Join-Path $PSScriptRoot 'Compare-CampaignRecap.ps1') @step 3>$null)
    $exit = $LASTEXITCODE
    Equal $out[0] 'Campaign recap (LoreTextPublic-9.9.9.1.csv): 7 entries in 2 campaigns; 6 name a quest (6 quests, 5 of them ours).' 'R1: the entries counted'
    Equal $out[1] 'Our chains against the recap''s order: 3 pairs of entries next to each other; 2 run the other way, 1 of them kept.' 'R1: the reversals, one kept'
    Equal $out[2] 'The recap''s quests the data lacks (step 6''s to look at): 1: 99' 'R2: a recap quest we lack'
    Equal $out[3] 'Ours with no quest line: 1: 12 Quest 12' 'R2: one of ours in no quest line'
    Equal $out[4] 'Findings: 2: campaign 1: 11 Quest 11 (recap 1) needs 12 Quest 12 (recap 2) in our data; a KEEP row for campaign 1, quests 10 and 11, whose pair no longer runs against the recap' 'R3: a reversal with no row and a KEEP row that no longer fits are findings'
    Equal $exit 1 'R3: exit 1'
    Equal ((Import-Csv (Join-Path $root 'recap.csv') | ForEach-Object { "$($_.Kind):$($_.Quest)" }) -join ' | ') 'against the recap:11 | against the recap:20 | not in the data:99 | no quest line:12' 'R4: the report''s rows'
    Decisions @(@(2, 20, 21, 'KEEP'), @(1, 11, 12, 'KEEP'))
    $out = @(& (Join-Path $PSScriptRoot 'Compare-CampaignRecap.ps1') @step 3>$null)
    Equal "$LASTEXITCODE $($out[4])" '0 Findings: 0' 'R5: with both kept, no finding'
}
finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output "$Passed checks passed, $Failed failed."
if ($Failed -gt 0) { exit 1 }
