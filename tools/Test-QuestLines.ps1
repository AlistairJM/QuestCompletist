<#
Checks QuestLines.ps1 on made-up quest lines: nothing in the checkout is touched and nothing is downloaded. It
checks that quests are ordered by the client's order index, that a step is linked to the one before it only when
the places agree (the hand-in map of one is the start map of the next), and that a step that doesn't chain says
why: its places differ, the client gives no place, two steps share an index. A quest we don't have is skipped
and the steps either side of it are not joined across the gap.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-QuestLines.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'QuestLines.ps1')
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Rows($line, $quests) {
    $i = 0
    return @($quests | ForEach-Object { [pscustomobject]@{ QuestLineID = "$line"; QuestID = "$_"; OrderIndex = "$($i)" }; $i++ })
}
function Have($ids) { $h = @{}; foreach ($id in $ids) { $h[[int]$id] = $true }; return $h }

# A line of five, given out of order: 10 starts in 1, hands in at 1; 11 starts in 1, hands in at 2; 12 starts in 2, hands in at 3;
# 13 starts in 9 (not 3), hands in at 9; 14 starts in 9, hands in at 1.
$rows = @(Rows 500 @(10, 11, 12, 13, 14))
$shuffled = @($rows[3], $rows[0], $rows[4], $rows[2], $rows[1])
$lines = Group-QuestLines $shuffled
Equal $lines.Count 1 'G1: the rows are grouped into one line'
Equal @($lines[500]).Count 5 'G1: with its five quests'
$start = @{ 10 = @(1); 11 = @(1); 12 = @(2); 13 = @(9); 14 = @(9) }
$end = @{ 10 = @(1); 11 = @(2); 12 = @(3); 13 = @(9); 14 = @(1) }
$steps = @(Get-QuestLineSteps $lines $start $end (Have 10, 11, 12, 13, 14))
Equal $steps.Count 4 'S1: five quests make four steps'
Equal (($steps | ForEach-Object { "$($_.Previous)>$($_.Quest)" }) -join ' ') '10>11 11>12 12>13 13>14' 'S1: in the order of the client, not of the rows'
Equal (($steps | ForEach-Object { $_.State }) -join ',') 'chain,chain,places differ,chain' 'S1: 12 to 13 does not chain, the places differ'
Check ($steps[2].Detail -match 'handed in on map 3, the next starts on map 9') 'S1: and says where'
Equal $steps[0].Step 2 'S1: a step is counted from 1, so the second quest is step 2'
Equal $steps[0].Line 500 'S1: and knows its line'

# Several places on one side: they agree when any one matches.
$steps = @(Get-QuestLineSteps (Group-QuestLines (Rows 600 @(20, 21))) @{ 20 = @(1); 21 = @(5, 6) } @{ 20 = @(4, 6); 21 = @(6) } (Have 20, 21))
Equal $steps[0].State 'chain' 'S2: a quest with two hand-in maps chains when one is the next start'

# No place from the client, on either side of a step.
$steps = @(Get-QuestLineSteps (Group-QuestLines (Rows 700 @(30, 31, 32))) @{ 30 = @(1) } @{ 30 = @(1); 31 = @(1) } (Have 30, 31, 32))
Equal (($steps | ForEach-Object { $_.State }) -join ',') 'no map point,no map point' 'S3: a quest the client gives no start is not chained to the one before'
Check ($steps[0].Detail -match 'no place') 'S3: and says so'
$steps = @(Get-QuestLineSteps (Group-QuestLines (Rows 710 @(33, 34))) @{ 33 = @(1); 34 = @(1) } @{ 34 = @(1) } (Have 33, 34))
Equal $steps[0].State 'no map point' 'S3: nor one whose predecessor has no hand-in place'
$steps = @(Get-QuestLineSteps (Group-QuestLines (Rows 720 @(35, 36, 37))) @{ 35 = @(1); 37 = @(1) } @{ 35 = @(1); 36 = @(1) } (Have 35, 36, 37))
Equal (($steps | ForEach-Object { $_.State }) -join ',') 'no map point,chain' 'S3: a step with a place on each side chains, whatever the others lack'

# Two quests of one index are parallel, and no step is made between them.
$parallel = @([pscustomobject]@{ QuestLineID = '800'; QuestID = '40'; OrderIndex = '0' }, [pscustomobject]@{ QuestLineID = '800'; QuestID = '41'; OrderIndex = '1' }, [pscustomobject]@{ QuestLineID = '800'; QuestID = '42'; OrderIndex = '1' })
$steps = @(Get-QuestLineSteps (Group-QuestLines $parallel) @{ 40 = @(1); 41 = @(1); 42 = @(1) } @{ 40 = @(1); 41 = @(1); 42 = @(1) } (Have 40, 41, 42))
Equal (($steps | ForEach-Object { "$($_.Previous)>$($_.Quest):$($_.State)" }) -join ' ') '40>41:chain 41>42:same order' 'S4: two quests of one index are flagged, not chained'
Check ($steps[1].Detail -match 'both are step 2') 'S4: saying which step'

# A quest we don't have is skipped, and the steps either side are not joined across it.
$steps = @(Get-QuestLineSteps (Group-QuestLines (Rows 900 @(50, 51, 52, 53))) @{ 50 = @(1); 51 = @(1); 52 = @(1); 53 = @(1) } @{ 50 = @(1); 51 = @(1); 52 = @(1); 53 = @(1) } (Have 50, 52, 53))
Equal (($steps | ForEach-Object { "$($_.Previous)>$($_.Quest)" }) -join ' ') '50>52 52>53' 'S5: a quest we lack is left out and its neighbours are joined, as the game would offer them'
Equal @(Get-QuestLineSteps (Group-QuestLines (Rows 901 @(60))) @{} @{} (Have 60)).Count 0 'S5: a line of one quest has no steps'
Equal @(Get-QuestLineSteps @{} @{} @{} @{}).Count 0 'S5: and no lines no steps'

Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
