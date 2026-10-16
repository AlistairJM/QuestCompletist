<#
Checks SharedSlots.ps1 (step 2k, Sync-SharedSlotLinks.ps1) on made-up quests, switches, decisions, completed lists
and a made-up qcQuest.lua: nothing in the checkout is touched and nothing is downloaded. It checks which quests a
switch groups (not recurring ones, not ones on their own), which pairs could be "only one of these" (different
names, one character could be offered both), the decisions (a SKIP chain covers a group), every kind of finding,
the counts, the writing of qcMutuallyExclusive (hand lines and their comments kept, the section rewritten, a second
run changing nothing, removals going to qcFormerlyExclusive, Windows line endings kept) and reading the probe's
completed lists.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncSharedSlotLinks.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SharedSlots.ps1')
. (Join-Path $PSScriptRoot 'ProbeResults.ps1')
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Q($id, $name, $faction = 3, $class = 8191, $race = 67108863, $type = 1) {
    return [pscustomobject]@{ id = $id; name = $name; faction = $faction; class = $class; race = $race; type = $type }
}
function Throws([scriptblock]$block, [string]$part, [string]$message) {
    try { & $block; Check $false "$message (no error)" } catch { Check ($_.Exception.Message -like "*$part*") "$message (got '$($_.Exception.Message)')" }
}

$quests = @{}
foreach ($q in @(
    (Q 1 'Allegiance to the Aldor'), (Q 2 'Allegiance to the Scryers'),
    (Q 3 'Speak with Private Weeks' 1), (Q 4 'Speak with Scout Neftis' 2),
    (Q 5 'The Arts of a Mage' 3 128), (Q 6 'The Arts of a Shaman' 3 64),
    (Q 7 'Report to the Trading Post'), (Q 8 'Report to the Trading Post'),
    (Q 9 'A Gift For Fung' 3 8191 67108863 4), (Q 10 'A Gift For Ella' 3 8191 67108863 4),
    (Q 11 'Alone on a switch'),
    (Q 12 'Favored of the Light' 1 16 1), (Q 13 'Favored of Elune' 1 16 8),
    (Q 20 'Old lead-in'), (Q 21 'Board quest'),
    (Q 30 'Linked A'), (Q 31 'Linked B'), (Q 32 'Linked C'), (Q 33 'Linked D'),
    (Q 40 'Paragon one'), (Q 41 'Paragon two'), (Q 42 'Paragon three'),
    (Q 50 'Added one'), (Q 51 'Added two'))) { $quests[$q.id] = $q }
$v2 = @(
    @(1, 100), @(2, 100), @(3, 101), @(4, 101), @(5, 102), @(6, 102), @(7, 103), @(8, 103), @(9, 104), @(10, 104),
    @(11, 105), @(12, 106), @(13, 106), @(20, 107), @(21, 107), @(30, 108), @(31, 108), @(32, 109), @(33, 110),
    @(40, 111), @(41, 111), @(42, 111), @(50, 112), @(51, 113), @(99, 105)) |
    ForEach-Object { [pscustomobject]@{ ID = "$($_[0])"; UniqueBitFlag = "$($_[1])" } }

$slots = Get-QuestSlots $v2
$groups = Get-SharedSlotGroups $slots $quests
Equal $slots[99] 105 'G1: every QuestV2 row has a switch, ours or not'
Check (-not $groups.ContainsKey(104)) 'G1: daily quests make no group'
Check (-not $groups.ContainsKey(105)) 'G1: a switch holding one of our quests (and one we lack) makes no group'
Equal ($groups[100] -join ',') '1,2' 'G1: the Aldor and Scryers share a switch'

$pairs = Get-SharedSlotPairs $groups $quests
$keys = @($pairs | ForEach-Object { "$($_.A)-$($_.B)" })
Check ($keys -contains '1-2') 'P1: two quests one character could be offered are a pair'
Check ($keys -notcontains '3-4') 'P1: an Alliance and a Horde quest are not'
Check ($keys -notcontains '5-6') 'P1: nor quests of two classes'
Check ($keys -notcontains '7-8') 'P1: nor two quests of one name'
Check ($keys -notcontains '12-13') 'P1: nor quests of two races'
Equal (@($pairs | Where-Object { $_.Slot -eq 111 }).Count) 3 'P1: a switch of three gives three pairs'

$lua = @"
qcBreadcrumbQuests = {
	[21] = {20},
}

qcMutuallyExclusive = {
	[30] = {31}, -- A
	[31] = {30}, -- H
	--[[ A block ]]--
	[32]={33},
	[33]={32},
	-- [1] = {2},

}

qcFormerlyExclusive = {1453,28651}  -- QuestIds a removed qcMutuallyExclusive link ticked
"@ -replace "`r?`n", "`r`n"
$exclusive = Get-ListPairs (Read-LuaQuestLists $lua 'qcMutuallyExclusive')
$breadcrumb = Get-ListPairs (Read-LuaQuestLists $lua 'qcBreadcrumbQuests')
Equal (@($exclusive.Keys | Sort-Object) -join ' ') '30|31 32|33' 'L1: the links are read, a commented-out line is not'
Check $breadcrumb.ContainsKey('20|21') 'L1: the breadcrumbs are read as pairs'

$rows = @(
    [pscustomobject]@{ Quest = '50'; Other = '51'; Link = 'exclusive'; Decision = 'ADD' },
    [pscustomobject]@{ Quest = '40'; Other = '41'; Link = 'exclusive'; Decision = 'SKIP' },
    [pscustomobject]@{ Quest = '41'; Other = '42'; Link = 'exclusive'; Decision = 'SKIP' },
    [pscustomobject]@{ Quest = '33'; Other = '32'; Link = 'exclusive'; Decision = 'KEEP' },
    [pscustomobject]@{ Quest = '70'; Other = '71'; Link = 'prereq'; Decision = 'SET' })
$decisions = Read-SharedSlotDecisions $rows
Equal (Get-PairDecision $decisions 51 50) 'ADD' 'D1: a decision reads either way round'
Equal (Get-PairDecision $decisions 40 42) 'SKIP' 'D1: a SKIP chain covers the pair it joins'
Equal (Get-PairDecision $decisions 1 2) $null 'D1: an undecided pair has none'
Throws { Read-SharedSlotDecisions @([pscustomobject]@{ Quest = '1'; Other = '2'; Link = 'exclusive'; Decision = 'MAYBE' }) } 'ADD, REMOVE, SKIP or KEEP' 'D2: an unknown decision stops it'
Throws { Read-SharedSlotDecisions @([pscustomobject]@{ Quest = '1'; Other = '2'; Link = 'exclusive'; Decision = 'ADD' }, [pscustomobject]@{ Quest = '2'; Other = '1'; Link = 'exclusive'; Decision = 'SKIP' }) } 'twice' 'D2: so does a pair decided twice'

$completed = @([pscustomobject]@{ Character = 'Alliance Human PRIEST'; Level = '70'; Build = '12.1.5.70391'; Ids = [System.Collections.Generic.HashSet[int]]@(32, 33, 1) })
$result = Get-SharedSlotFindings $pairs $slots $quests $exclusive $breadcrumb $decisions $completed
$f = @($result.Findings | ForEach-Object { "$($_.Kind):$($_.Quest)-$($_.Other)" })
Check ($f -contains 'one switch, not linked:1-2') 'F1: an unlinked pair on one switch is a finding'
Check (@($f | Where-Object { $_ -like '*:40-*' -or $_ -like '*:41-*' }).Count -eq 0) 'F1: a skipped group is not'
Check (@($f | Where-Object { $_ -like '*20-21*' }).Count -eq 0) 'F1: nor a breadcrumb pair'
Check (@($f | Where-Object { $_ -like '*30-31*' }).Count -eq 0) 'F1: nor a link one switch confirms'
Check ($f -contains 'added for one switch, no longer on one:50-51') 'F2: an added pair whose switches now differ is a finding'
Check (@($f | Where-Object { $_ -like 'decided ADD*50-51' }).Count -eq 1) 'F2: and, not yet written, a decision to apply'
Check (@($f | Where-Object { $_ -like '*32-33*' }).Count -eq 0) 'F3: a link done both of on different switches is no finding once KEPT'
Equal $result.Counts.CompletedBoth 1 'F3: but it is counted'
Equal $result.Counts.ConfirmedBySwitch 1 'F4: one link is on one switch'
Equal $result.Counts.NotOnOneSwitch 1 'F4: one is not'
Equal $result.Counts.BreadcrumbsOnOneSwitch 1 'F4: one breadcrumb pair shares a switch'
$noKeep = Read-SharedSlotDecisions @($rows | Where-Object { $_.Decision -ne 'KEEP' })
$result2 = Get-SharedSlotFindings $pairs $slots $quests $exclusive $breadcrumb $noKeep $completed
Check (@($result2.Findings | Where-Object { $_.Kind -like 'linked, but the game says*' -and $_.Quest -eq 32 }).Count -eq 1) 'F3: without the KEEP, the pair one character did both of is a finding'
$removeRows = @($rows | Where-Object { $_.Decision -ne 'KEEP' }) + [pscustomobject]@{ Quest = '30'; Other = '31'; Link = 'exclusive'; Decision = 'REMOVE' }
$result3 = Get-SharedSlotFindings $pairs $slots $quests $exclusive $breadcrumb (Read-SharedSlotDecisions $removeRows) @()
Check (@($result3.Findings | Where-Object { $_.Kind -eq 'decided REMOVE, still in the table' -and $_.Quest -eq 30 }).Count -eq 1) 'F5: a REMOVE not yet written is a finding'

$changes = Get-SharedSlotChanges (Read-SharedSlotDecisions $removeRows) $exclusive $quests
Equal (@($changes.Adds | ForEach-Object { $_ -join '-' }) -join ' ') '50-51' 'S1: the ADD is to write'
Equal (@($changes.Removes | ForEach-Object { $_ -join '-' }) -join ' ') '30-31' 'S1: and the REMOVE'
$written = Set-ExclusiveLinks $lua (@(, @(1, 2)) + $changes.Adds + @(, @(32, 11))) $changes.Removes
Check ($written -match "\[32\]=\{33,11\},") 'S2: a hand line gains the new quest in its own style'
Check ($written -notmatch '\[30\]' -and $written -notmatch '\[31\] = ') 'S2: hand lines emptied by a removal go'
Check ($written -match '--\[\[ A block \]\]--') 'S2: comments stay'
Check ($written -match '-- \[1\] = \{2\},') 'S2: a commented-out entry is left alone'
Check ($written.Contains("`t$SharedSlotMarker`r`n`t[1]={2},`r`n`t[2]={1},`r`n`t[11]={32},`r`n`t[50]={51},`r`n`t[51]={50},")) 'S3: quests with no hand line go in the section, in order'
Check ($written -match 'qcFormerlyExclusive = \{30,31,1453,28651\}') 'S4: removed quests join qcFormerlyExclusive'
Check (-not ($written -replace "`r`n", '').Contains("`n")) 'S5: Windows line endings are kept'
$again = Set-ExclusiveLinks $written (@(, @(1, 2)) + $changes.Adds) @()
Equal $again $written 'S6: a second run with the same decisions changes nothing'
$after = Get-ListPairs (Read-LuaQuestLists $written 'qcMutuallyExclusive')
Equal (@($after.Keys | Sort-Object) -join ' ') '1|2 11|32 32|33 50|51' 'S7: the table reads back as written'

$lua51 = 'C:\Program Files (x86)\Lua\5.1\lua.exe'
if (Test-Path $lua51) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("shared_slot_test_" + [guid]::NewGuid().ToString('N') + '.lua')
    Set-Content $tmp @'
QCForeverProbeDB = {
	["completed"] = {
		["Player-1-0001"] = {["build"] = "12.1.5.70391", ["time"] = 1790000000, ["character"] = "Horde Orc WARRIOR", ["level"] = 80, ["ids"] = "1,5,30,31"},
	},
}
'@ -Encoding ASCII
    try {
        $rows = @(Get-ProbeCompletions $tmp)
        Equal $rows.Count 1 'C1: one character''s completed list is read'
        Equal $rows[0].Character 'Horde Orc WARRIOR' 'C1: with the character'
        Check ($rows[0].Ids.Contains(30) -and $rows[0].Ids.Contains(31) -and $rows[0].Ids.Count -eq 4) 'C1: and its quests'
    } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
} else {
    Write-Output "Lua 5.1 not found at ${lua51}: the completed-list reader is not checked."
}

Write-Output "$Passed checks passed, $Failed failed."
if ($Failed -gt 0) { exit 1 }
