<#
Checks QuestConditions.ps1 on made-up client tables, written to a scratch folder: nothing in the checkout is
touched and nothing is downloaded. It reads a PlayerCondition's quests with their logic and its ModifierTree's
AND, OR, NOT, "N of", nested conditions, nested trees and game features, a condition switched off and one whose
tree the game reads the other way round; keeps only the conditions that name a quest of the current campaign or a
hidden quest a line accepts in place of one; links each chapter of the campaign to the one before, or a Scouting
Map chapter to what the map's quest needs; and reads the covenants a condition needs, the covenants' headings and
each quest's covenants from its task condition, quest line, campaign, chapter (by its OrderIndex) and heading.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-QuestConditions.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
. (Join-Path $PSScriptRoot 'QuestConditions.ps1')
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Text($node) { return ConvertTo-PrereqText (ConvertTo-PrereqValue $node) '[' ']' }

$build = '1.0.0.1'
$dir = Join-Path ([IO.Path]::GetTempPath()) ("qc-conditions-" + [guid]::NewGuid())
New-Item -ItemType Directory $dir | Out-Null
function Write-Table([string]$name, [string]$header, [string[]]$rows) {
    Set-Content -Path (Join-Path $dir $name) -Value (@($header) + $rows) -Encoding UTF8
}
try {
    # The campaign (10): chapters 100 (1, 2, 3), 101 (4, 5) and 102 (6, 7); 102 starts on the Scouting Map line 200,
    # whose quest 3 needs 2. Quest 999 is hidden (not in our data), 888 is an older expansion's hidden quest.
    Write-Table "QuestLineXQuest-$build.csv" 'QuestLineID,QuestID,OrderIndex' @(
        '100,2,1', '100,1,0', '100,3,2', '101,4,0', '101,5,1', '102,6,0', '102,7,1', '200,8,0', '200,6,1',
        '300,30,0', '300,31,1', '300,32,2', '301,40,0', '302,41,0', '303,42,0', '304,43,0', '400,44,0', '500,50,0', '500,51,1',
        '600,60,0', '601,61,0', '602,62,0')
    Write-Table "QuestLine-$build.csv" 'ID,Name_lang,PlayerConditionID' @(
        '100,"Chapter one",0', '101,"Chapter two",0', '102,"Chapter three",0', '200,"Scouting Map",0',
        '300,"Either way",1', '301,"Hidden only",2', '302,"Not a quest",3', '303,"Logic or",9', '304,"Two of",10', '400,"Older",4',
        '600,"Covenant line",23', '601,"Covenant chapter one",0', '602,"Covenant chapter three",0')
    Write-Table "Campaign-$build.csv" 'ID,Title_lang,Prerequisite' @('10,"The campaign",11', '11,"Later",5', '12,"Empty",0', '13,"Covenant campaign",24')
    # Campaign 13 skips chapter OrderIndex 1, as campaign 271 does; its chapter 2 has a gate of its own.
    Write-Table "CampaignXQuestLine-$build.csv" 'CampaignID,QuestLineID,OrderIndex' @('10,101,1', '10,100,0', '10,102,2', '11,500,0', '13,601,0', '13,602,2')
    Write-Table "CampaignXCondition-$build.csv" 'ID,FailureReason_lang,PlayerConditionID,OrderIndex,Flags,CampaignID' @('1,"Reach level 30 to continue.",25,2,0,13')
    Write-Table "ModifierTree-$build.csv" 'ID,Parent,Operator,Amount,Type,Asset,SecondaryAsset' @(
        '130,0,4,0,0,0,0', '131,130,2,0,119,500,5', '132,130,2,0,119,501,3',
        '140,0,8,1,0,0,0', '141,140,2,0,119,500,4', '142,140,2,0,119,500,6',
        '150,0,8,1,0,0,0', '151,150,2,0,119,500,4', '152,150,2,0,119,501,2', '160,0,3,0,119,500,9',
        '10,0,8,1,0,0', '11,10,0,0,110,5', '12,10,0,0,110,999',
        '20,0,4,0,0,0', '21,20,0,0,110,5', '22,20,3,0,110,6',
        '30,0,8,1,0,0', '31,30,4,0,0,0', '32,31,3,0,2,6', '33,31,0,0,2,7', '34,30,4,0,0,0', '35,34,0,0,2,6', '36,34,0,0,2,8',
        '40,0,0,0,289,1886', '50,0,0,0,110,999', '60,0,8,2,0,0', '61,60,0,0,110,5', '62,60,0,0,110,7',
        '70,0,2,0,110,7', '80,0,2,0,73,20', '90,0,4,0,0,0', '91,90,2,0,288,3', '92,90,2,0,110,44',
        '100,0,8,1,0,0', '101,100,2,0,288,1', '102,100,4,0,0,0', '103,102,2,0,288,1', '104,102,2,0,110,7',
        '110,0,8,1,0,0', '111,110,2,0,288,1', '112,110,2,0,288,2', '120,0,3,0,288,4')
    Write-Table 'PlayerCondition.csv' 'ID,PrevQuestLogic,PrevQuestID_0,PrevQuestID_1,PrevQuestID_2,PrevQuestID_3,ModifierTreeID,Flags,CovenantID,Failure_description_lang,CurrencyLogic,CurrencyID_0,CurrencyID_1,CurrencyID_2,CurrencyID_3,CurrencyCount_0,CurrencyCount_1,CurrencyCount_2,CurrencyCount_3' @(
        '30,0,0,0,0,0,0,0,0,,0,500,0,0,0,7,0,0,0', '31,0,0,0,0,0,130,0,0,,0,0,0,0,0,0,0,0,0', '32,0,0,0,0,0,140,0,0,,0,0,0,0,0,0,0,0,0',
        '33,0,0,0,0,0,150,0,0,,0,0,0,0,0,0,0,0,0', '34,0,0,0,0,0,0,0,0,,0,999,0,0,0,10,0,0,0', '35,0,0,0,0,0,0,0,0,,65536,500,0,0,0,7,0,0,0',
        '36,0,0,0,0,0,0,0,0,,2,500,501,0,0,7,3,0,0', '37,0,0,0,0,0,160,0,0,,0,0,0,0,0,0,0,0,0', '38,0,0,0,0,0,0,0,0,,1,500,501,0,0,2,8,0,0',
        '39,0,0,0,0,0,0,256,0,,0,500,0,0,0,7,0,0,0', '40,0,0,0,0,0,130,512,0,,0,0,0,0,0,0,0,0,0',
        '1,0,0,0,0,0,10,0,0,"Finish the first part."', '2,0,999,0,0,0,0,0,0', '3,0,0,0,0,0,20,0,0', '4,0,888,0,0,0,0,0,0', '5,0,0,0,0,0,30,0,0', '6,0,0,0,0,0,40,0,0',
        '7,0,0,0,0,0,50,0,0', '8,0,0,0,0,0,0,0,0', '9,2,5,7,0,0,0,0,0', '10,0,0,0,0,0,60,0,0', '11,0,5,0,0,0,0,0,0', '12,65536,5,0,0,0,0,0,0',
        '20,0,5,0,0,0,70,256,0', '21,0,5,0,0,0,50,512,0', '22,0,0,0,0,0,80,0,0', '23,0,0,0,0,0,0,0,2,"You must be a member of the Venthyr Covenant."', '24,0,0,0,0,0,90,0,0,"Requires further advancement."',
        '25,0,0,0,0,0,100,0,0', '26,0,0,0,0,0,110,0,0', '27,0,0,0,0,0,120,0,0', '28,0,0,0,0,0,90,512,0')
    $c = Import-ClientConditions $dir $build
    $quests = @{}
    foreach ($id in 1, 2, 3, 4, 5, 6, 7, 8, 30, 31, 32, 40, 41, 42, 43, 44, 50, 51) { $quests[$id] = [pscustomobject]@{ id = $id; prereq = $null } }
    $quests[3].prereq = 2

    Equal (Text (ConvertFrom-PlayerCondition $c 1)) '[[5,999]]' 'P1: an OR of two quests is a choice, the hidden one kept'
    Equal (Text (ConvertFrom-PlayerCondition $c 2)) '999' 'P1: a quest the condition names directly'
    Equal (Text (ConvertFrom-PlayerCondition $c 3)) '5' 'P2: a quest that must not be done is read as met'
    Equal (Text (ConvertFrom-PlayerCondition $c 5)) '999' 'P3: a branch that needs a game feature drops out of the OR'
    Equal (ConvertFrom-PlayerCondition $c 6) 'never' 'P3: a game feature on its own is never met'
    Equal (Text (ConvertFrom-PlayerCondition $c 9)) '[[5,7]]' 'P4: PrevQuestLogic 2 joins the next quest with OR'
    Check ($null -eq (ConvertFrom-PlayerCondition $c 10)) 'P5: two of a group can''t be checked, so it reads as met'
    Check ($null -eq (ConvertFrom-PlayerCondition $c 12)) 'P5: and so can''t a quest that must not be done'
    Check ($null -eq (ConvertFrom-PlayerCondition $c 77)) 'P5: and a condition the table lacks'
    Check (-not (Test-ConditionGroup $c.Tree[11].Asset)) 'P6: a quest ID read from a table is no group'
    Check ($null -eq (ConvertFrom-PlayerCondition $c 20)) 'P7: a condition the client switches off (0x100) is met'
    Equal (Text (ConvertFrom-PlayerCondition $c 21)) '5' 'P7: a tree the game reads the other way round (0x200) is left out, its quests kept'
    Equal (Text (ConvertFrom-PlayerCondition $c 22)) '5' 'P8: a nested tree (type 73) is read'
    Equal (Text (ConvertFrom-PrevQuests $c.Conditions[9])) '[[5,7]]' 'P9: a condition''s own quests without its tree'

    Equal (@(Get-ConditionCovenants $c 23) -join ',') '2' 'V1: a condition''s CovenantID'
    Equal (@(Get-ConditionCovenants $c 24) -join ',') '3' 'V1: a covenant its tree needs (type 288)'
    Equal (@(Get-ConditionCovenants $c 25) -join ',') '1' 'V2: a choice whose every branch needs the same covenant'
    Equal (@(Get-ConditionCovenants $c 26) -join ',') '' 'V2: a choice of two covenants needs neither'
    Equal (@(Get-ConditionCovenants $c 27) -join ',') '' 'V2: nor does a covenant the character mustn''t have'
    Equal (@(Get-ConditionCovenants $c 28) -join ',') '' 'V2: nor a tree the game reads the other way round'
    $headings = Get-CovenantHeadings @(
        [pscustomobject]@{ ID = '589'; SortName_lang = 'Kyrian Callings' }, [pscustomobject]@{ ID = '590'; SortName_lang = 'Night Fae Callings' },
        [pscustomobject]@{ ID = '700'; SortName_lang = 'Maruuk Centaur Quests' }, [pscustomobject]@{ ID = '701'; SortName_lang = 'Kyrians' }) @(
        [pscustomobject]@{ ID = '1'; Name_lang = 'Kyrian' }, [pscustomobject]@{ ID = '3'; Name_lang = 'Night Fae' }, [pscustomobject]@{ ID = '12'; Name_lang = 'Maruuk Centaur' })
    Equal (($headings.Keys | Sort-Object | ForEach-Object { "$_=$($headings[$_])" }) -join ' ') '589=1 590=3' 'V3: a covenant''s headings, not a renown faction''s'
    $named = Get-ClientCovenants $c @{ 63 = 23 } @{ 64 = -589; 65 = -999 } $headings
    Equal (($named.Keys | Sort-Object | ForEach-Object { "$_=$($named[$_] -join '/')" }) -join ' ') '60=2 61=3 62=1/3 63=2 64=1' 'V4: by quest line, campaign, chapter (by OrderIndex), task condition and heading; one several name lists each'
    Equal $c.ChapterConditions[0].Text 'Reach level 30 to continue.' 'V5: a chapter gate keeps the game''s text'

    $ours = @{}
    foreach ($id in 31, 32, 60, 61, 62, 63) { $ours[$id] = [pscustomobject]@{ id = $id } }
    $keys = Get-ConditionTextKeys $c @{ 63 = 23; 32 = 8 } $ours
    Equal (($keys.Keys | ForEach-Object { "$_=$($keys[$_] -join ',')" }) -join ' ') 'c1=62 p1=31 p23=60,63 p24=61' 'X1: texts by key: a chapter gate on its chapter''s first quest, a line''s and a campaign''s on their first of ours, a task quest''s on itself; none for a condition with no text'

    # Renown currencies 500 (faction 9000) and 501 (faction 9001); 999 is another currency.
    $renown = @{ 500 = 9000; 501 = 9001 }
    function Needs([int]$id) { $n = Get-ConditionRenowns $c $id $renown; return (($n.Keys | Sort-Object | ForEach-Object { "$_=$($n[$_])" }) -join ' ') }
    Equal (Needs 30) '9000=7' 'N1: a renown currency the condition''s own columns ask for'
    Equal (Needs 31) '9000=5 9001=3' 'N1: two its tree asks for (type 119, the amount in SecondaryAsset)'
    Equal (Needs 32) '9000=4' 'N2: a choice of two levels of one faction needs the lower'
    Equal (Needs 33) '' 'N2: a choice of two factions needs neither'
    Equal (Needs 34) '' 'N3: a currency that is no renown is no requirement'
    Equal (Needs 35) '' 'N3: nor is one the condition says mustn''t be held'
    Equal (Needs 36) '' 'N3: nor two its columns join by OR'
    Equal (Needs 37) '' 'N3: nor one the tree says mustn''t be held'
    Equal (Needs 38) '9000=2 9001=8' 'N4: two its columns join by AND'
    Equal (Needs 39) '' 'N5: a disabled condition asks for nothing'
    Equal (Needs 40) '' 'N5: nor does a tree the condition inverts'

    $gates = @(Get-ConditionGates $c 10 $quests)
    Equal (($gates | ForEach-Object { "$($_.Kind) $($_.Id)" }) -join ', ') 'line 300, line 301, line 302, line 303, campaign 11' 'G1: the conditions that name the campaign''s quests or the hidden one it accepts'
    $byId = @{}; foreach ($g in $gates) { $byId["$($g.Kind) $($g.Id)"] = $g }
    Equal (($byId['line 300'].Quests) -join ',') '30,31,32' 'G2: a line covers its quests, in order'
    Equal (($byId['campaign 11'].Quests) -join ',') '50,51' 'G2: a campaign covers its lines'' quests'
    Equal (Text $byId['campaign 11'].Gate) '999' 'G2: the later campaign needs the hidden quest'
    Check (-not $byId.ContainsKey('line 400')) 'G3: an older expansion''s hidden quest is left alone'
    Check (-not $byId.ContainsKey('campaign 10')) 'G3: so is the campaign''s own condition'

    $links = Get-ChapterLinks $c 10 200 3 $quests
    Equal (($links.Keys | Sort-Object | ForEach-Object { "$_<$($links[$_])" }) -join ' ') '4<3 6<2' 'C1: chapter two needs chapter one''s last quest, the map''s chapter what the map''s quest needs'
    $quests.Remove(5)
    $links = Get-ChapterLinks $c 10 200 3 $quests
    Equal $links.Count 2 'C2: a chapter whose last quest we lack still links the others'
} finally {
    Remove-Item -Recurse -Force $dir
}

Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
