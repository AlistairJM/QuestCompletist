<#
Checks the two retail checks that now run on WoW: Forever's data as well (sweep step 10):
Audit-QuestTables.ps1 -Game forever (-OwnDataOnly), which reads no API cache, TrinityCore dump or client
table, and Remove-DuplicatePinQuests.ps1 -Game forever. They run on small data made in a scratch folder, so
nothing in the checkout is written and nothing is downloaded; then the audit runs on Forever's committed
tables, which must have no finding that its decisions file doesn't keep.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ForeverChecks.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param(
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"
$Audit = Join-Path $PSScriptRoot 'Audit-QuestTables.ps1'
$Remove = Join-Path $PSScriptRoot 'Remove-DuplicatePinQuests.ps1'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("forever-checks-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null

function Add-Quest($list, [int]$id, [string]$name, [int]$type = 1, [int]$faction = 3, $prereq = $null) {
    $q = '{"id":' + $id + ',"name":"' + $name + '","level":10,"zone":"","category":10,"type":' + $type + ',"faction":' + $faction + ',"race":0,"class":8191'
    if ($prereq) { $q += ',"prereq":' + $prereq }
    $list.Add($q + '}')
}

# A Forever-shaped world: data\forever, the generated Lua beside it (one-line empty tables, as the importer writes them).
function New-World([string]$name) {
    $root = Join-Path $Scratch $name
    foreach ($dir in 'tools', 'data\forever', 'addon\Forever') { New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null }
    $quests = New-Object System.Collections.Generic.List[string]
    Add-Quest $quests 1 'Plain'
    Add-Quest $quests 2 'Daily' 4
    Add-Quest $quests 3 'Needs the daily' 1 3 2
    Add-Quest $quests 4 'Needs itself' 1 3 4
    Add-Quest $quests 5 'Five' 1 3 6
    Add-Quest $quests 6 'Six' 1 3 5
    Add-Quest $quests 7 'Needs a stranger' 1 3 99
    Add-Quest $quests 8 'Alliance' 1 1 9
    Add-Quest $quests 9 'Horde' 1 2
    Add-Quest $quests 10 'Fine' 1 3 1
    Add-Quest $quests 11 'Gone' 1 3
    Add-Quest $quests 13 'One of two, one Horde' 1 1 '[[10,9]]'
    Add-Quest $quests 14 'Both of two, one Horde' 1 1 '[10,9]'
    Add-Quest $quests 15 'One of two, one daily' 1 3 '[[1,2]]'
    [IO.File]::WriteAllText("$root\data\forever\quests.jsonl", (($quests -join "`n") + "`n"))
    $pins = @(
        '{"map":1411,"icon":1,"name":"Bottle","x":10,"y":10,"quests":[5]}',
        '{"map":1411,"icon":1,"name":"Bottle","x":10.1,"y":10.1,"quests":[5]}',
        '{"map":1411,"icon":1,"name":"Bottle","x":12,"y":12,"quests":[5]}',
        '{"map":1411,"icon":1,"npc":77,"name":"Keeper","x":50,"y":50,"quests":[1,10]}',
        '{"map":1411,"icon":1,"npc":78,"name":"Other","x":50.1,"y":50.1,"quests":[1]}',
        '{"map":1411,"icon":1,"name":"Bottle","x":80,"y":80,"quests":[6]}'
    )
    [IO.File]::WriteAllText("$root\data\forever\pins.jsonl", (($pins -join "`n") + "`n"))
    $lua = @'
qcAreaIDToCategoryID={
[1411]=14,
}
qcRenownLevelRequirements={}
qcQuestSkillRequirements={
[777]={185,50},
}
qcBreadcrumbQuests={
[1]={2},
[12]={1},
}
qcMutuallyExclusive={
[5]={6},
[5]={6,10},
[1]={1},
}
qcClosedOnceDone={
[2]=true,
[99]=true,
}
qcQuestNeedsInLog={
[3]={1},
[4]={4},
[10]={99},
}
qcOverrideDailyExclusiveQuest={}
qcOverrideWeeklyExclusiveQuest={}
qcFactions={
[1]="Name",
[1]="Again",
}
'@
    [IO.File]::WriteAllText("$root\addon\Forever\qcQuest.lua", ($lua -replace "`r?`n", "`r`n"))
    [IO.File]::WriteAllText("$root\addon\Forever\qcUnavailableQuests.lua", "qcUnavailableQuests = {`r`n[11]=1,`r`n}`r`n")
    [IO.File]::WriteAllText("$root\addon\QuestCompletist.toc", "## Interface: 120100, 120105`r`n")
    [IO.File]::WriteAllText("$root\addon\QuestCompletist_Camelot.toc", "## Interface: 16001`r`n")
    return $root
}

function Run-Script([string]$script, [string[]]$arguments) {
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $script @arguments 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $saved }
    return @{ Text = ($output -join "`n"); Exit = $LASTEXITCODE }
}

try {
    # --- the audit, on a scratch copy of Forever's layout ------------------------------------------
    $w = New-World 'audit'
    $out = "$w\tools\audit.csv"
    $r = Run-Script $Audit @('-Game', 'forever', '-ToolsDir', "$w\tools", '-DataDir', "$w\data\forever", '-AddonDir', "$w\addon\Forever", '-DecisionsFile', "$w\none.csv", '-OutFile', $out)
    Equal $r.Exit 1 'A1: the audit runs on Forever''s layout with nothing downloaded, and fails on its new findings'
    Check ($r.Text -match '(?m)^NEW  prereq: requires itself  4 4$') "A1: and lists them ($($r.Text))"
    Check ($r.Text -match 'Sources: the data and the tables only \(forever\)') "A1: and says what it did not read ($($r.Text))"
    Check ($r.Text -match '0 renown requirements') 'A1: an empty one-line table is empty, and does not swallow the next table'
    $f = @(Import-Csv $out)
    function Count-Kind([string]$kind) { return @($f | Where-Object { $_.Kind -eq $kind }).Count }
    function Get-KindQuests([string]$kind) { return (@($f | Where-Object { $_.Kind -eq $kind } | ForEach-Object { [int]$_.Quest } | Sort-Object) -join ',') }
    Equal (Count-Kind 'prereq: recurring quest') 2 'A2: a one-time quest that requires a daily one, alone or as one of a choice'
    Equal (Get-KindQuests 'prereq: recurring quest') '3,15' 'A2: are quests 3 and 15'
    Equal (Count-Kind 'prereq: requires itself') 1 'A2: a quest that requires itself'
    Equal (Count-Kind 'prereq: each requires the other') 2 'A2: two that require each other (both ways round)'
    Equal (Count-Kind 'prereq: quest not in the data') 1 'A2: a prerequisite that is not in the data'
    Equal (Get-KindQuests 'prereq: other faction') '8,14' 'A2: a prerequisite of the other faction, alone or in a list that needs all of it, but not as one of a choice'
    Equal (Count-Kind 'breadcrumb: recurring quest') 1 'A2: a breadcrumb that is a daily quest'
    Equal (Count-Kind 'breadcrumb: quest not in the data') 1 'A2: a breadcrumb pair naming a quest not in the data'
    Equal (Count-Kind 'exclusive: shuts itself out') 1 'A2: a quest that closes itself'
    Equal (Count-Kind 'exclusive: listed twice') 1 'A2: a quest listed twice'
    Equal (Count-Kind 'exclusive: quest flagged unavailable') 0 'A2: and nothing flagged that is not named'
    Equal (Count-Kind 'closed once done: not a breadcrumb') 1 'A2: a quest kept while its quest is in the log that is no breadcrumb'
    Equal (@($f | Where-Object { $_.Kind -eq 'closed once done: not a breadcrumb' }))[0].Quest '99' 'A2: is quest 99'
    Equal (Get-KindQuests 'in the log: needs itself') '4' 'A2: a quest that needs itself in the log'
    Equal (Get-KindQuests 'in the log: quest not in the data') '10' 'A2: one that needs a quest not in the data in the log'
    Check (@($f | Where-Object { $_.Kind -match 'API|TrinityCore|client' }).Count -eq 0) 'A3: nothing from the API, TrinityCore or the client'
    Equal @($f | Where-Object { $_.Kind -match 'faction name: (faction not in|differs)|renown: faction' }).Count 0 'A3: and the factions are not held against the client'
    Check (-not (Test-Path "$w\tools\Faction-12.1.0.69933.csv")) 'A3: no table was downloaded'

    $keep = "$w\keep.csv"
    [IO.File]::WriteAllText($keep, "Kind,Quest,Other,Decision,Reason`r`nprereq: requires itself,4,4,KEEP,looked at`r`nprereq: requires itself,5,5,KEEP,fixed since`r`n")
    $r = Run-Script $Audit @('-Game', 'forever', '-ToolsDir', "$w\tools", '-DataDir', "$w\data\forever", '-AddonDir', "$w\addon\Forever", '-DecisionsFile', $keep, '-OutFile', $out)
    $kept = @(Import-Csv $out | Where-Object { $_.Kept })
    Equal $kept.Count 1 'A4: a KEEP row marks its finding'
    Check ($r.Text -match 'prereq: requires itself: 1 \(0 new\)') 'A4: and it no longer counts as new'
    $stale = @(Import-Csv $out | Where-Object { $_.Kind -eq 'decision out of date' })
    Equal (($stale | ForEach-Object { "$($_.Quest) $($_.Other): $($_.Detail)" }) -join ' | ') "5 5: the KEEP row for 'prereq: requires itself' matches no finding" 'A4: a KEEP row that matches no finding is a finding of its own'
    Check ($r.Text -match '(?m)^NEW  decision out of date  5 5: ') "A4: and is listed as new ($($r.Text))"

    $r = Run-Script $Audit @('-Game', 'forever', '-ToolsDir', "$w\tools", '-DataDir', "$w\data\forever", '-AddonDir', "$w\addon\Forever", '-DecisionsFile', "$w\none.csv", '-OutFile', "$w\tools\second.csv")
    $r = Run-Script $Audit @('-Game', 'forever', '-ToolsDir', "$w\tools", '-DataDir', "$w\data\forever", '-AddonDir', "$w\addon\Forever", '-DecisionsFile', "$w\none.csv", '-OutFile', "$w\tools\third.csv")
    Equal (Get-Content "$w\tools\third.csv" -Raw) (Get-Content "$w\tools\second.csv" -Raw) 'A5: a rerun finds the same'
    $r = Run-Script $Audit @('-Game', 'classic')
    Check ($r.Exit -ne 0 -and $r.Text -match '-Game must be retail or forever') 'A6: a game that is not retail or forever is refused'

    # -OwnDataOnly on the retail layout reads the same data and tables
    $r = Run-Script $Audit @('-OwnDataOnly', '-ToolsDir', "$w\tools", '-DataDir', "$w\data\forever", '-AddonDir', "$w\addon\Forever", '-DecisionsFile', "$w\none.csv", '-OutFile', "$w\tools\retail.csv")
    Equal $r.Exit 1 'A7: -OwnDataOnly alone also needs nothing downloaded'
    Equal (Get-Content "$w\tools\retail.csv" -Raw) (Get-Content "$w\tools\second.csv" -Raw) 'A7: and finds the same'
    $r = Run-Script $Audit @('-OwnDataOnly', '-ToolsDir', "$w\tools", '-DataDir', "$w\data\forever", '-AddonDir', "$w\addon\Forever", '-DecisionsFile', $keep, '-OutFile', "$w\tools\retail.csv")
    Equal @(Import-Csv "$w\tools\retail.csv" | Where-Object { $_.Kind -eq 'decision out of date' }).Count 0 'A7: on retail it skips the API, TrinityCore and the client, so it judges no KEEP row'
    Check ($r.Text -match "The KEEP rows weren't held against the findings") "A7: and says so ($($r.Text))"

    $all = "$w\all.csv"
    Import-Csv "$w\tools\second.csv" | ForEach-Object { [pscustomobject]@{ Kind = $_.Kind; Quest = $_.Quest; Other = $_.Other; Decision = 'KEEP'; Reason = 'looked at' } } | Export-Csv $all -NoTypeInformation
    $r = Run-Script $Audit @('-Game', 'forever', '-ToolsDir', "$w\tools", '-DataDir', "$w\data\forever", '-AddonDir', "$w\addon\Forever", '-DecisionsFile', $all, '-OutFile', "$w\tools\all.csv")
    Equal $r.Exit 0 'A8: with every finding kept the run exits 0'
    Check ($r.Text -match 'of which new: 0\.' -and $r.Text -notmatch '(?m)^NEW ') "A8: and lists nothing new ($($r.Text))"

    # --- the duplicate-quest removal ---------------------------------------------------------------
    $w = New-World 'pins'
    $null = Invoke-AddonDataBuild -DataDir "$w\data\forever" -AddonDir "$w\addon\Forever"
    $before = [IO.File]::ReadAllText("$w\data\forever\pins.jsonl")
    $r = Run-Script $Remove @('-Game', 'forever', '-ToolsDir', "$w\tools", '-DataDir', "$w\data\forever", '-AddonDir', "$w\addon\Forever", '-WhatIf')
    Equal $r.Exit 0 'D1: the removal runs on Forever''s layout with no start points'
    Check ($r.Text -match 'Would take 1 quests off 1 pins, removing 1 pins') "D1: and lists what it would do ($($r.Text))"
    Equal ([IO.File]::ReadAllText("$w\data\forever\pins.jsonl")) $before 'D1: -WhatIf changes nothing'
    Check ($r.Text -match 'Left alone[^
]*: 1') 'D1: and lists the pin 2 points off as left alone (further than half a point, with no start point to choose)'
    $r = Run-Script $Remove @('-Game', 'forever', '-ToolsDir', "$w\tools", '-DataDir', "$w\data\forever", '-AddonDir', "$w\addon\Forever")
    Equal $r.Exit 0 'D2: the run itself exits 0'
    $after = @([IO.File]::ReadAllLines("$w\data\forever\pins.jsonl"))
    Equal $after.Count 5 'D2: one of the six pins goes'
    Check (@($after | Where-Object { $_ -match '"x":10,' }).Count -eq 1 -and @($after | Where-Object { $_ -match '"x":10.1,' }).Count -eq 0) 'D2: the one at 10.1 goes, the first stays'
    Check (@($after | Where-Object { $_ -match '"name":"Keeper"' }).Count -eq 1) 'D2: a pin with an NPC ID stays'
    Check (@($after | Where-Object { $_ -match '"name":"Other"' }).Count -eq 1) 'D2: and another giver of one of its quests keeps it (other names are other givers)'
    Check (@($after | Where-Object { $_ -match '"x":12,' }).Count -eq 1) 'D2: a pin 2 points off stays (further than half a point)'
    Check ((Get-Content "$w\addon\Forever\qcPinDB.lua" -Raw) -notmatch '10\.1,10\.1') 'D2: the Lua is rebuilt'
    $r = Run-Script $Remove @('-Game', 'forever', '-ToolsDir', "$w\tools", '-DataDir', "$w\data\forever", '-AddonDir', "$w\addon\Forever", '-WhatIf')
    Check ($r.Text -match 'Would take 0 quests off 0 pins') 'D3: a second run changes nothing'
    $r = Run-Script $Remove @('-Game', 'classic')
    Check ($r.Exit -ne 0 -and $r.Text -match '-Game must be retail or forever') 'D4: a game that is not retail or forever is refused'

    # --- Forever's committed tables ----------------------------------------------------------------
    $real = Join-Path $PSScriptRoot '..\data\forever\quests.jsonl'
    if (Test-Path $real) {
        $r = Run-Script $Audit @('-Game', 'forever', '-ToolsDir', "$Scratch", '-OutFile', "$Scratch\real.csv")
        Equal $r.Exit 0 'R1: the audit runs on Forever''s committed data'
        Check ($r.Text -match 'of which new: 0\.') "R1: and has no finding the decisions file doesn't keep ($($r.Text))"
        $r = Run-Script $Remove @('-Game', 'forever', '-WhatIf')
        Check ($r.Text -match 'Would take 0 quests off 0 pins') "R1: and no pin shares a quest with a same-named pin beside it ($($r.Text))"
    }
}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
