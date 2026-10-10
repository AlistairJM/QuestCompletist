<#
Checks the rules of the quest giver notes (RecordedGivers.ps1) and the tool that applies them
(Import-RecordedGivers.ps1) on small data made here, in a scratch folder: nothing in the checkout is
written. Read-RecordedGivers.lua has its own test, Test-RecordedGivers.lua.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-RecordedGivers.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param(
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\RecordedGivers.ps1"
$Tool = Join-Path $PSScriptRoot 'Import-RecordedGivers.ps1'
$Reader = Join-Path $PSScriptRoot 'Read-RecordedGivers.lua'
$Passed = 0; $Failed = 0
$script:ShowToolOutput = [bool]$env:RG_TEST_VERBOSE
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("recorded-givers-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null

# --- Making the scratch data ---------------------------------------------------------------------

function Add-Quest($list, [int]$id, [string]$name, [int]$type = 1, [int]$category = 10, [int]$profession = 0) {
    $q = '{"id":' + $id + ',"name":"' + $name + '","level":10,"zone":"","category":' + $category + ',"type":' + $type + ',"faction":2,"race":67108863,"class":8191'
    if ($profession) { $q += ',"profession":' + $profession }
    $list.Add($q + '}')
}

# One scratch world: tools, data and addon folders with a few quests and pins, the Lua built from them.
function New-World([string]$name, $pinLines = $null) {
    $root = Join-Path $Scratch $name
    foreach ($dir in 'tools', 'tools\recordings\own\retail', 'tools\recordings\own\forever', 'tools\recordings\players', 'data\forever', 'addon') {
        New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null
    }
    $maps = "Name_lang,ID,ParentUiMapID,Flags,System,Type`r`nStormwind,84,0,0,0,3`r`nElwynn,37,0,0,0,3`r`nDungeon,500,0,0,0,4`r`n"
    [IO.File]::WriteAllText("$root\tools\UiMap.csv", $maps)
    [IO.File]::WriteAllText("$root\tools\UiMap-1.60.1.70205.csv", "Name_lang,ID,ParentUiMapID,Flags,System,Type`r`nTeldrassil,1438,0,0,0,3`r`n")
    [IO.File]::WriteAllText("$root\tools\QuestV2CliTask.csv", "ID,QuestInfoID`r`n105,0`r`n118,99`r`n")
    [IO.File]::WriteAllText("$root\tools\QuestInfo.csv", "ID,InfoName_lang,Type,Modifiers,Profession`r`n0,None,0,0,0`r`n99,World Quest,0,0,0`r`n")
    $quests = New-Object System.Collections.Generic.List[string]
    Add-Quest $quests 100 'First'
    Add-Quest $quests 101 'Second'
    Add-Quest $quests 102 'Third'
    Add-Quest $quests 103 'Pinless'
    Add-Quest $quests 104 'Odd type' 64
    Add-Quest $quests 105 'A task'
    Add-Quest $quests 106 'Retired'
    Add-Quest $quests 107 'System' 1 170
    Add-Quest $quests 108 'Class quest'
    Add-Quest $quests 109 'Cooking' 1 10 185
    Add-Quest $quests 110 'No place'
    Add-Quest $quests 111 'Named pin'
    Add-Quest $quests 112 'Other name'
    Add-Quest $quests 113 'Crowd one'
    Add-Quest $quests 114 'Crowd two'
    Add-Quest $quests 115 'Joins'
    Add-Quest $quests 116 'Daily' 4
    Add-Quest $quests 117 'Elsewhere'
    Add-Quest $quests 118 'World thing'
    Add-Quest $quests 119 'Test Quest'
    [IO.File]::WriteAllText("$root\data\quests.jsonl", (($quests -join "`n") + "`n"))
    $foreverQuests = New-Object System.Collections.Generic.List[string]
    Add-Quest $foreverQuests 200 'Forever one'
    Add-Quest $foreverQuests 201 'Forever two'
    [IO.File]::WriteAllText("$root\data\forever\quests.jsonl", (($foreverQuests -join "`n") + "`n"))
    [IO.File]::WriteAllText("$root\data\forever\pins.jsonl", '{"map":1438,"icon":1,"npc":3595,"name":"Shanda","x":56.3,"y":59.9,"quests":[200]}' + "`n")
    $pins = if ($pinLines) { $pinLines } else { @(
        '{"map":37,"icon":1,"npc":3701,"name":"Guard Roberts","x":45.3,"y":67.8,"quests":[100,101]}',
        '{"map":37,"icon":1,"x":50,"y":50,"quests":[102]}',
        '{"map":84,"icon":1,"name":"Old Name","x":60,"y":60,"quests":[111]}',
        '{"map":84,"icon":1,"name":"Someone Else","x":70,"y":70,"quests":[112]}',
        '{"map":84,"icon":1,"x":10,"y":10,"quests":[113,114]}',
        '{"map":84,"icon":1,"npc":9001,"name":"Joiner","x":80,"y":20,"quests":[116]}',
        '{"map":84,"icon":1,"x":90,"y":90,"quests":[117]}'
    ) }
    [IO.File]::WriteAllText("$root\data\pins.jsonl", (($pins -join "`n") + "`n"))
    [IO.File]::WriteAllText("$root\addon\qcUnavailableQuests.lua", "qcUnavailableQuests = {`r`n[106]=1,`r`n}`r`n")
    [IO.File]::WriteAllText("$root\addon\QuestCompletist.toc", "## Interface: 120100, 120105`r`n")
    [IO.File]::WriteAllText("$root\addon\QuestCompletist_Camelot.toc", "## Interface: 16001`r`n")
    $null = Invoke-AddonDataBuild -DataDir "$root\data" -AddonDir "$root\addon"
    return $root
}

# A saved-variables file as the game writes one. Each giver is @{ Key; Name; Spots = @(@(map, x, y, visits)); Offers; Turn };
# each start @{ Quest; Kind; Item; Map; X; Y }.
function New-RecorderFile([string]$path, $givers, $starts = @(), [int]$build = 69933, [string]$version = '12.1.0') {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('qcQuestRecorder = {')
    [void]$sb.AppendLine('["v"] = 1,')
    [void]$sb.AppendLine('["seq"] = 10,')
    [void]$sb.AppendLine("[""bv""] = { [$build] = ""$version"" },")
    [void]$sb.AppendLine('["g"] = {')
    $questFacts = @{}
    foreach ($g in $givers) {
        $spots = ($g.Spots | ForEach-Object {
            $x = if ($_[1] -lt 0) { '-1' } else { ([decimal]$_[1]).ToString('0.0', $script:Invariant) }
            $y = if ($_[2] -lt 0) { '-1' } else { ([decimal]$_[2]).ToString('0.0', $script:Invariant) }
            "$($_[0]) $x $y $($_[3])"
        }) -join ';'
        $record = "$(([string]$g.Name).Replace([string][char]92, ([string][char]92 + [string][char]92)).Replace([string][char]34, ([string][char]92 + [string][char]34)))|$build|1|$spots|$(@($g.Offers) -join ',')|$(@($g.Turn) -join ',')|0"
        [void]$sb.AppendLine("[""$($g.Key)""] = ""$record"",")
        foreach ($quest in @($g.Offers)) { $questFacts[[int]$quest] = "$build|1|32|1|8|1024|" }
    }
    [void]$sb.AppendLine('},')
    [void]$sb.AppendLine('["q"] = {')
    foreach ($quest in ($questFacts.Keys | Sort-Object)) { [void]$sb.AppendLine("[$quest] = ""$($questFacts[$quest])"",") }
    [void]$sb.AppendLine('},')
    [void]$sb.AppendLine('["s"] = {')
    foreach ($s in $starts) {
        $x = if ($s.X -lt 0) { '-1' } else { ([decimal]$s.X).ToString('0.0', $script:Invariant) }
        $y = if ($s.Y -lt 0) { '-1' } else { ([decimal]$s.Y).ToString('0.0', $script:Invariant) }
        [void]$sb.AppendLine("[$($s.Quest)] = ""$($s.Kind)|$($s.Item)|$($s.Map)|$x|$y|$build|3"",")
    }
    [void]$sb.AppendLine('},')
    [void]$sb.AppendLine('}')
    [IO.File]::WriteAllText($path, $sb.ToString())
}

function Invoke-Tool([string]$root, [string[]]$more = @()) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Tool, '-ToolsDir', "$root\tools", '-DataDir', "$root\data", '-AddonDir', "$root\addon",
        '-LedgerFile', "$root\ledger.csv", '-DecisionsFile', "$root\decisions.csv", '-ReportFile', "$root\report.txt", '-LuaExe', $LuaExe)
    # The decision files of the checkout are not the test's: unless a test gives its own, there are none.
    if ($more -notcontains '-GiverDecisionsFile') { $arguments += @('-GiverDecisionsFile', "$root\no-giver-decisions.csv") }
    if ($more -notcontains '-NpcIdDecisionsFile') { $arguments += @('-NpcIdDecisionsFile', "$root\no-npc-decisions.csv") }
    $arguments += $more
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = @(& powershell @arguments 2>&1) } finally { $ErrorActionPreference = $saved }
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and $script:ShowToolOutput) { Write-Host "  (tool output: $(($output -join ' | ').Substring(0, [Math]::Min(700, ($output -join ' | ').Length)))" }
    return [pscustomobject]@{ Exit = $exit; Output = ($output -join "`n"); Report = $(if (Test-Path "$root\report.txt") { [IO.File]::ReadAllText("$root\report.txt") } else { '' }) }
}
function Get-Pins([string]$root) { return , @(Read-PinData "$root\data") }
function Get-PinText([string]$root) { return [IO.File]::ReadAllText("$root\data\pins.jsonl") }
function Find-Pin($pins, [int]$quest) { return , @($pins | Where-Object { @($_.quests) -contains $quest }) }
function Put-Own([string]$root, $givers, $starts = @()) { New-RecorderFile "$root\tools\recordings\own\retail\QuestCompletist.lua" $givers $starts }
function Put-Player([string]$root, [string]$tag, $givers, $starts = @()) {
    New-Item -ItemType Directory -Path "$root\tools\recordings\players\$tag" -Force | Out-Null
    New-RecorderFile "$root\tools\recordings\players\$tag\QuestCompletist.lua" $givers $starts
}


# ===================== proposed additional checks (scratch only) =====================

function G([string]$key, [string]$name, [int]$build, [string]$spots, [string]$offers, [string]$turns, [int]$flags = 0) {
    $escaped = $name.Replace('\', '\\').Replace('"', '\"')
    return "[""$key""] = ""$escaped|$build|1|$spots|$offers|$turns|$flags"","
}
function New-RawRecorder([string]$path, $gLines, $qLines = @(), $sLines = @(), $builds = @{ 69933 = '12.1.0' }, $extra = @()) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('qcQuestRecorder = {')
    [void]$sb.AppendLine('["v"] = 1,')
    [void]$sb.AppendLine('["seq"] = 10,')
    [void]$sb.AppendLine('["bv"] = {')
    foreach ($b in $builds.Keys) { [void]$sb.AppendLine("[$b] = ""$($builds[$b])"",") }
    [void]$sb.AppendLine('},')
    [void]$sb.AppendLine('["g"] = {')
    foreach ($l in $gLines) { [void]$sb.AppendLine($l) }
    [void]$sb.AppendLine('},')
    [void]$sb.AppendLine('["q"] = {')
    foreach ($l in $qLines) { [void]$sb.AppendLine($l.TrimEnd(',') + ',') }
    [void]$sb.AppendLine('},')
    [void]$sb.AppendLine('["s"] = {')
    foreach ($l in $sLines) { [void]$sb.AppendLine($l.TrimEnd(',') + ',') }
    [void]$sb.AppendLine('},')
    [void]$sb.AppendLine('}')
    foreach ($l in $extra) { [void]$sb.AppendLine($l) }
    [IO.File]::WriteAllText($path, $sb.ToString())
}
function Put-RawOwn([string]$root, $gLines, $qLines = @(), $sLines = @(), $builds = @{ 69933 = '12.1.0' }, $extra = @()) {
    New-RawRecorder "$root\tools\recordings\own\retail\QuestCompletist.lua" $gLines $qLines $sLines $builds $extra
}
function Put-RawPlayer([string]$root, [string]$tag, $gLines, $qLines = @(), $sLines = @(), $builds = @{ 69933 = '12.1.0' }) {
    New-Item -ItemType Directory -Path "$root\tools\recordings\players\$tag" -Force | Out-Null
    New-RawRecorder "$root\tools\recordings\players\$tag\QuestCompletist.lua" $gLines $qLines $sLines $builds
}
function Add-WorldQuests([string]$root, $lines) {
    $text = [IO.File]::ReadAllText("$root\data\quests.jsonl")
    [IO.File]::WriteAllText("$root\data\quests.jsonl", $text + (($lines -join "`n") + "`n"))
    $null = Invoke-AddonDataBuild -DataDir "$root\data" -AddonDir "$root\addon"
}
function Q([int]$id, [string]$name, [int]$type = 1, [int]$category = 10, [string]$extra = '', [int]$faction = 2, [long]$race = 67108863, [int]$class = 8191) {
    return '{"id":' + $id + ',"name":"' + $name + '","level":10,"zone":"","category":' + $category + ',"type":' + $type + ',"faction":' + $faction + ',"race":' + $race + ',"class":' + $class + $extra + '}'
}
function Pin-Lines([string]$root) { return @([IO.File]::ReadAllLines("$root\data\pins.jsonl")) }
function Ledger-Rows([string]$root) { return @((Read-RecordedLedger "$root\ledger.csv").Values) }

try {
    # ---------- E01: a trusted offer with an untrusted place does not fill or add ----------
    $root = New-World 'e01'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '' '102,103' ''))
    Put-RawPlayer $root 'p01' @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 9' '' ''))
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'E01: a place only one player saw does not fill a pin, though the offer is the maintainer''s'
    Equal (Find-Pin (Get-Pins $root) 103).Count 0 'E01: nor does it make a pin for a pinless quest'
    Put-RawPlayer $root 'p02' @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 1' '' ''))
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 102)[0].npc 3702 'E01: two players at that place make it count, and the pin is filled'
    Equal (Find-Pin (Get-Pins $root) 103).Count 1 'E01: and the pinless quest gets its pin'

    # ---------- E02: vehicles ----------
    $root = New-World 'e02'
    Put-RawOwn $root @((G 'Vehicle:7777' 'Siege Engine' 69933 '37 50.4 50.2 4' '102,103' ''))
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'E02: a vehicle fills no pin'
    Equal (Find-Pin (Get-Pins $root) 103).Count 0 'E02: and gets none made'
    Check ($run.Report -match 'a vehicle') 'E02: and the report counts it'

    # ---------- E03: objects ----------
    $root = New-World 'e03' @(
        '{"map":37,"icon":1,"x":50,"y":50,"quests":[102]}',
        '{"map":37,"icon":1,"name":"Notice Board","x":20,"y":20,"quests":[100]}',
        '{"map":37,"icon":1,"npc":3711,"name":"Neighbour","x":60,"y":60,"quests":[101]}')
    Put-RawOwn $root @(
        (G 'GameObject:175320' 'Wanted Poster' 69933 '37 50.4 50.2 3' '102' ''),
        (G 'GameObject:175321' 'Notice Board' 69933 '37 20.1 20.1 3' '100' ''),
        (G 'GameObject:175322' 'Old Chest' 69933 '84 33.3 44.4 5' '103,104' ''),
        (G 'GameObject:175323' 'Crate' 69933 '37 60.5 60.5 2' '105' ''))
    $run = Invoke-Tool $root
    $pins = Get-Pins $root
    $p = (Find-Pin $pins 102)[0]
    Check (-not $p.npc) 'E03: an object gives a pin no NPC ID'
    Equal $p.name 'Wanted Poster' 'E03: but its name'
    Check (-not (Find-Pin $pins 100)[0].npc) 'E03: a pin that already names an object gets nothing'
    $chest = Find-Pin $pins 103
    Equal $chest.Count 1 'E03: a pinless quest of an object gets a pin'
    Check (-not $chest[0].npc) 'E03: with no NPC ID'
    Equal $chest[0].name 'Old Chest' 'E03: and the object''s name'
    Equal (@($chest[0].quests) -join ',') '103,104' 'E03: a second quest of the object joins it'
    $crate = Find-Pin $pins 105
    Equal $crate.Count 1 'E03: an object quest beside a creature''s pin'
    Equal $crate[0].name 'Crate' 'E03: gets a pin of its own'
    Equal (@((Find-Pin $pins 101)[0].quests) -join ',') '101' 'E03: and the creature''s pin gains nothing'

    # ---------- E04: odd records ----------
    $root = New-World 'e04'
    $odd = @(
        (G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' ''),
        (G 'Player:1' 'x' 69933 '' '' ''), (G 'Player:2' 'x' 69933 '' '' ''), (G 'Player:3' 'x' 69933 '' '' ''))
    Put-RawOwn $root $odd
    $run = Invoke-Tool $root
    Check ($run.Report -match 'records are odd') 'E04: a file whose records are mostly odd is not read'
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'E04: and fills nothing'
    $few = @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' '')) + @(1..8 | ForEach-Object { (G "Creature:38$_" "Fine $_" 69933 '' '' '') }) + @((G 'Player:1' 'x' 69933 '' '' ''), (G 'Player:2' 'x' 69933 '' '' ''))
    Put-RawOwn $root $few
    $run = Invoke-Tool $root
    Check ($run.Report -notmatch 'records are odd') 'E04: two odd records of eleven are tolerated'
    Equal (Find-Pin (Get-Pins $root) 102)[0].npc 3702 'E04: and the rest is read'
    $three = @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' '')) + @(1..16 | ForEach-Object { (G "Creature:38$_" "Fine $_" 69933 '' '' '') }) + @((G 'Player:1' 'x' 69933 '' '' ''), (G 'Player:2' 'x' 69933 '' '' ''), (G 'Player:3' 'x' 69933 '' '' ''))
    $root = New-World 'e04b'
    Put-RawOwn $root $three
    $run = Invoke-Tool $root
    Check ($run.Report -notmatch 'records are odd') 'E04: three odd records of twenty (15 percent) are tolerated'
    $four = @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' '')) + @(1..14 | ForEach-Object { (G "Creature:38$_" "Fine $_" 69933 '' '' '') }) + @(1..5 | ForEach-Object { (G "Player:$_" 'x' 69933 '' '' '') })
    $root = New-World 'e04c'
    Put-RawOwn $root $four
    $run = Invoke-Tool $root
    Check ($run.Report -match 'records are odd') 'E04: five odd records of twenty (more than a fifth) are not'

    # ---------- E05: builds ----------
    $root = New-World 'e05'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 60000 '37 50.4 50.2 3' '102' '')) @() @() @{ 60000 = '12.0.7' }
    $run = Invoke-Tool $root
    Check ($run.Report -match 'none of its builds are read') 'E05: a retail build the TOCs do not name is not read'
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'E05: so nothing is filled'
    Put-RawOwn $root @(
        (G 'Creature:3702' 'Stable Master Gil' 60000 '37 50.4 50.2 3' '102' ''),
        (G 'Creature:3703' 'Old Name' 69933 '84 60.5 60.5 1' '111' '')) @() @() @{ 60000 = '12.0.7'; 69933 = '12.1.0' }
    $run = Invoke-Tool $root
    Check ((Find-Pin (Get-Pins $root) 111)[0].npc -eq 3703) 'E05: of two builds in one file the read one is used'
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'E05: and the other''s giver is left out'
    Check (@(Ledger-Rows $root | Where-Object { $_.Npc -eq '3702' }).Count -eq 0) 'E05: of the ledger too'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' '')) @() @() @{ 69933 = '12.10.0' }
    $run = Invoke-Tool $root
    Check ($run.Report -match 'none of its builds are read') 'E05: 12.10.0 is not 12.1'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' '')) @() @() @{ 69933 = '12.1.0'; 70245 = '1.60.1' }
    $run = Invoke-Tool $root
    Check ($run.Report -match 'no game') 'E05: a file of retail and Forever builds has no game'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' '')) @() @() @{}
    $run = Invoke-Tool $root
    Check ($run.Report -match 'names no build') 'E05: a file with no build is not read'

    # ---------- E06: maps ----------
    $root = New-World 'e06'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3;9999 10.0 10.0 2' '102' ''))
    $run = Invoke-Tool $root
    Check (@(Ledger-Rows $root | Where-Object { $_.Map -eq '9999' }).Count -eq 0) 'E06: a spot on a map the game lacks is not in the ledger'
    Check (@(Ledger-Rows $root | Where-Object { $_.Role -eq 'spot' -and $_.Map -eq '37' }).Count -eq 1) 'E06: the other spot is'
    Check ($run.Report -match '9999 \(1\)') 'E06: the report names the missing map'

    # ---------- E07: names ----------
    $root = New-World 'e07' @(
        '{"map":37,"icon":1,"name":"stable master gil","x":50,"y":50,"quests":[102]}',
        '{"map":37,"icon":1,"name":"|cff00ff00Guard Roberts <Captain>|r","x":20,"y":20,"quests":[100]}',
        '{"map":84,"icon":1,"name":"Double  Space","x":60,"y":60,"quests":[111]}')
    Put-RawOwn $root @(
        (G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' ''),
        (G 'Creature:3701' 'Guard Roberts' 69933 '37 20.1 20.1 3' '100' ''),
        (G 'Creature:3703' 'Double Space' 69933 '84 60.1 60.1 3' '111' ''))
    $run = Invoke-Tool $root
    $pins = Get-Pins $root
    Check (-not (Find-Pin $pins 102)[0].npc) 'E07: a name that differs in case only is another name'
    Check ($run.Report -match 'pin name differs from the recorded giver') 'E07: and is reported'
    Equal (Find-Pin $pins 100)[0].npc 3701 'E07: colour codes and a title do not make a name different'
    Equal (Find-Pin $pins 100)[0].name '|cff00ff00Guard Roberts <Captain>|r' 'E07: and the pin keeps its name as it was'
    Check (-not (Find-Pin $pins 111)[0].npc) 'E07: one space or two is another name'

    # ---------- E08: the cap of six ----------
    $root = New-World 'e08' @('{"map":37,"icon":1,"npc":3701,"name":"Guard Roberts","x":45.3,"y":67.8,"quests":[100]}')
    $eight = @(1..8 | ForEach-Object { (G "Creature:39$_" "Seller $_" 69933 "84 $(10 * $_).0 $(10 * $_).0 $(2 + $_)" '103' '') })
    Put-RawOwn $root $eight
    $run = Invoke-Tool $root
    $made = Find-Pin (Get-Pins $root) 103
    Equal $made.Count 6 'E08: a quest offered by eight givers gets six pins'
    Equal (@($made | ForEach-Object { $_.npc } | Sort-Object) -join ',') '393,394,395,396,397,398' 'E08: the six most seen'
    Check ($run.Report -match 'more than six places: quest 103.*Creature:391.*Creature:392|more than six places: quest 103.*Creature:392.*Creature:391') 'E08: the other two are for review'

    # ---------- E09: join or create ----------
    $root = New-World 'e09' @(
        '{"map":84,"icon":1,"npc":9001,"name":"Joiner","x":80,"y":20,"quests":[116]}',
        '{"map":84,"icon":1,"npc":9003,"name":"Neighbour","x":50,"y":50,"quests":[101]}',
        '{"map":84,"icon":1,"npc":9005,"name":"Far Joiner","x":10,"y":70,"quests":[117]}')
    Put-RawOwn $root @(
        (G 'Creature:9001' 'Joiner' 69933 '84 81.3 20.0 4' '115' ''),
        (G 'Creature:9002' 'Newcomer' 69933 '84 50.6 50.1 4' '103' ''),
        (G 'Creature:9005' 'Far Joiner' 69933 '84 10.0 72.0 4' '104' ''))
    $run = Invoke-Tool $root
    $pins = Get-Pins $root
    Equal (@((Find-Pin $pins 116)[0].quests) -join ',') '116,115' 'E09: a quest joins its giver''s pin 1.3 points away'
    $n = Find-Pin $pins 103
    Equal $n.Count 1 'E09: a giver beside another NPC''s pin'
    Equal $n[0].npc 9002 'E09: gets a pin of its own'
    Equal (@((Find-Pin $pins 101)[0].quests) -join ',') '101' 'E09: and the other NPC''s pin gains nothing'
    $f = Find-Pin $pins 104
    Equal $f.Count 1 'E09: a quest 2 points from its giver''s pin'
    Equal (@($f | Where-Object { $_.npc -eq 9005 -and (Format-PinNumber $_.y) -eq '72' }).Count) 1 'E09: gets a pin at the place seen'

    # ---------- E10: the ledger replaces its own numbers ----------
    $root = New-World 'e10'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' ''))
    $run = Invoke-Tool $root
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 70000 '37 50.4 50.2 5' '102' '')) @() @() @{ 70000 = '12.1.5' }
    $run = Invoke-Tool $root
    $spot = @(Ledger-Rows $root | Where-Object { $_.Role -eq 'spot' })[0]
    Equal $spot.Src 'own-retail=5' 'E10: a source read again replaces its number'
    Equal $spot.FirstBuild '69933' 'E10: the first build stays'
    Equal $spot.LastBuild '70000' 'E10: the last is the newest'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 2' '102' ''))
    $run = Invoke-Tool $root
    $spot = @(Ledger-Rows $root | Where-Object { $_.Role -eq 'spot' })[0]
    Equal $spot.Src 'own-retail=2' 'E10: and the number may go down'
    Equal $spot.LastBuild '70000' 'E10: while the last build does not'
    Put-RawPlayer $root 'p01' @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 7' '102' ''))
    $run = Invoke-Tool $root
    $spot = @(Ledger-Rows $root | Where-Object { $_.Role -eq 'spot' })[0]
    Equal $spot.Src 'own-retail=2;p01=7' 'E10: sources are written in order'
    $run = Invoke-Tool $root
    Check ($run.Report -match 'The ledger is as it was') 'E10: a ledger that would not change is not rewritten'

    # ---------- E11: forgetting ----------
    $root = New-World 'e11'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' ''))
    Put-RawPlayer $root 'p05' @((G 'Creature:3790' 'Only Seen By Five' 69933 '37 70.0 70.0 1' '101' ''))
    $run = Invoke-Tool $root
    Check (@(Ledger-Rows $root | Where-Object { $_.Npc -eq '3790' }).Count -gt 0) 'E11: the player''s rows are in the ledger'
    $run = Invoke-Tool $root @('-ForgetTag', 'p05')
    Check (@(Ledger-Rows $root | Where-Object { $_.Npc -eq '3790' }).Count -eq 0) 'E11: forgetting a source drops the rows no one else saw'
    Check (@(Ledger-Rows $root | Where-Object { $_.Npc -eq '3702' }).Count -gt 0) 'E11: and keeps the others'
    Check ($run.Report -match 'forgotten') 'E11: and does not read its file again'

}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------- part b ----------------
function Add-Many([string]$root, [int]$from, [int]$to) {
    $lines = @($from..$to | ForEach-Object { Q $_ "Many $_" })
    Add-WorldQuests $root $lines
}
function Review-Count([string]$report, [string]$kind) {
    return @($report -split "`r?`n" | Where-Object { $_ -match ('^  ' + [regex]::Escape($kind) + ': quest') }).Count
}
function Fill-Count([string]$report) {
    return @($report -split "`r?`n" | Where-Object { $_ -match '^  fill ' }).Count
}

try {
    # ---------- E12: pins are put in the pipeline's order, only on the maps that changed ----------
    $root = New-World 'e12' @(
        '{"map":37,"icon":1,"npc":3701,"name":"Guard Roberts","x":45.3,"y":67.8,"quests":[101]}',
        '{"map":84,"icon":1,"npc":9001,"name":"Joiner","x":80,"y":20,"quests":[116]}',
        '{"map":84,"icon":1,"x":10,"y":10,"quests":[113]}')
    Put-RawOwn $root @(
        (G 'Creature:3701' 'Guard Roberts' 69933 '37 45.3 67.8 2' '101,100' ''),
        (G 'Creature:3708' 'Class Trainer A' 69933 '37 20.0 20.0 5' '108' ''),
        (G 'Creature:3709' 'Class Trainer B' 69933 '37 10.0 30.0 2' '108' ''))
    $run = Invoke-Tool $root
    $lines = Pin-Lines $root
    $order = @($lines | ForEach-Object { if ($_ -match '"map":(\d+).*"x":([\d.]+)') { "$($Matches[1])@$($Matches[2])" } })
    Equal ($order -join ' ') '37@45.3 37@10 37@20 84@80 84@10' 'E12: two pins of one quest on a map go by x; a map nothing changed on keeps its order'
    Equal $run.Exit 0 'E12: the run succeeds'

    $root = New-World 'e13' @(
        '{"map":37,"icon":1,"x":40,"y":40,"quests":[103]}',
        '{"map":37,"icon":1,"x":30,"y":30,"quests":[105,101]}',
        '{"map":37,"icon":1,"x":50,"y":50,"quests":[102]}')
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 2' '102' ''))
    $run = Invoke-Tool $root
    $lines = Pin-Lines $root
    $order = @($lines | ForEach-Object { if ($_ -match '"quests":\[([\d,]+)\]') { $Matches[1] } })
    Equal ($order -join ' ') '105,101 102 103' 'E13: pins go by the lowest quest on them'

    # ---------- E14: what the review says and does not ----------
    $root = New-World 'e14' @(
        '{"map":37,"icon":1,"npc":4001,"name":"Alice","x":30,"y":30,"quests":[100]}',
        '{"map":37,"icon":1,"npc":4002,"name":"Bob","x":40,"y":40,"quests":[101]}',
        '{"map":37,"icon":1,"npc":4003,"name":"Cat","x":50,"y":50,"quests":[102]}',
        '{"map":84,"icon":1,"npc":4006,"name":"Erin","x":70,"y":70,"quests":[103]}',
        '{"map":84,"icon":1,"npc":4008,"name":"Gus","x":80,"y":80,"quests":[104]}',
        '{"map":84,"icon":1,"npc":4010,"name":"Ivy","x":20,"y":20,"quests":[105]}',
        '{"map":84,"icon":1,"npc":4011,"name":"Kim","x":60,"y":60,"quests":[106]}')
    Put-RawOwn $root @(
        (G 'Creature:4001' 'Alice' 69933 '37 31.9 30.0 2' '100' ''),
        (G 'Creature:4002' 'Bob' 69933 '37 45.0 40.0 2' '101' ''),
        (G 'Creature:4003' 'Cat' 69933 '37 53.1 50.0 2' '102' ''),
        (G 'Creature:4006' 'Erin' 69933 '84 70.1 70.1 2' '' '103'),
        (G 'Creature:4007' 'Frank' 69933 '84 70.0 72.9 2' '103' ''),
        (G 'Creature:4008' 'Gus' 69933 '84 80.1 80.1 2' '' '104'),
        (G 'Creature:4009' 'Hal' 69933 '84 80.0 83.1 2' '104' ''),
        (G 'Creature:4010' 'Ivy' 69933 '84 20.1 20.1 2' '' '105'),
        (G 'Creature:4012' 'Jon' 69933 '84 20.0 60.0 2' '105' ''),
        (G 'Creature:4011' 'Kim' 69933 '84 60.1 60.1 2' '106' ''))
    $before = Get-PinText $root
    $run = Invoke-Tool $root
    Equal (Get-PinText $root) $before 'E14: review items change no pin'
    Equal (Review-Count $run.Report 'quest offered away from its pins') 4 'E14: givers 5, 3.1, 3.1 and 40 points from their quest''s pin are away (101, 102, 104, 105); 1.9 and 2.9 are not'
    Equal (Review-Count $run.Report 'pin at the hand-in') 2 'E14: a pin at a turn-in is a hand-in only when every offer is more than 3 away (104, 105; not 103 whose offer is 2.9)'
    Equal (Review-Count $run.Report 'pin names another NPC than the recorded giver') 0 'E14: a pin whose own NPC is recorded there is not another NPC'
    Equal (Review-Count $run.Report 'same name under another ID') 0 'E14: nor a same name'
    Check ($run.Report -match 'pin at the hand-in: quest 105') 'E14: it is the pin whose offer is 40 points away'

    # ---------- E15: what may get a pin ----------
    $root = New-World 'e15' @('{"map":37,"icon":1,"npc":3701,"name":"Guard Roberts","x":45.3,"y":67.8,"quests":[100]}')
    $names = @('[DNT] Hidden', 'DNT thing', 'TBD something', 'Foo DEPRECATED', 'Test', 'Flight Test', 'Jrz quest', 'Placeholder thing', 'Blank',
        'Paragon of the Light', 'Prey Contract: Foo', 'Conditional Objectives', 'Bonus Objective: Foo', '[WIP] x', 'LFGDungeons 1', 'This Is Not a Quest')
    $cats = @(170, 173, 191, 290, 1092, 1095, 1130, 1133, 1134, 1232, 1241, 1246, 1346, 1347, 1428, 1429, 1430, 1431, 1514, 1735)
    $kinds = @('Emissary Quest', 'Hidden Quest', 'Delve Quest', 'Warfront Contribution', 'Envoy', 'Meta Quest', 'Professions', 'Pickpocketing', 'War Mode', 'Tracking', 'Bonus Objective')
    $quests = New-Object System.Collections.Generic.List[string]
    $givers = New-Object System.Collections.Generic.List[string]
    $n = 0
    function Offer-At([int]$quest) {
        $script:n++
        $x = 5 + 3 * ($script:n % 30); $y = 5 + 3 * [Math]::Floor($script:n / 30)
        $givers.Add((G "Creature:$(5000 + $script:n)" "Giver $script:n" 69933 "37 $x.0 $y.0 3" "$quest" ''))
    }
    $blocked = New-Object System.Collections.Generic.List[int]
    $id = 800
    foreach ($nm in $names) { $quests.Add((Q $id $nm)); $blocked.Add($id); Offer-At $id; $id++ }
    foreach ($c in $cats) { $quests.Add((Q $id "Cat $c" 1 $c)); $blocked.Add($id); Offer-At $id; $id++ }
    $infoRows = New-Object System.Collections.Generic.List[string]
    $taskRows = New-Object System.Collections.Generic.List[string]
    $infoId = 300
    foreach ($k in $kinds) {
        $quests.Add((Q $id "Kind $infoId")); $blocked.Add($id); Offer-At $id
        $infoRows.Add("$infoId,$k,0,0,0"); $taskRows.Add("$id,$infoId"); $id++; $infoId++
    }
    $okIds = New-Object System.Collections.Generic.List[int]
    $quests.Add((Q $id 'Fine one')); $okIds.Add($id); Offer-At $id; $id++
    $quests.Add((Q $id 'Holiday one' 1 10 ',"holiday":2')); $okIds.Add($id); Offer-At $id; $id++
    $quests.Add((Q $id 'Landfall one' 1 121)); $okIds.Add($id); Offer-At $id; $id++
    $quests.Add((Q $id 'Daily one' 4)); $okIds.Add($id); Offer-At $id; $id++
    $quests.Add((Q $id 'Weekly one' 128)); $okIds.Add($id); Offer-At $id; $id++
    $quests.Add((Q $id 'Repeatable one' 2)); $okIds.Add($id); Offer-At $id; $id++
    $quests.Add((Q $id 'Task of no kind')); $okIds.Add($id); Offer-At $id; $taskRows.Add("$id,0"); $id++
    Add-WorldQuests $root $quests
    [IO.File]::AppendAllText("$root\tools\QuestInfo.csv", (($infoRows -join "`r`n") + "`r`n"))
    [IO.File]::AppendAllText("$root\tools\QuestV2CliTask.csv", (($taskRows -join "`r`n") + "`r`n"))
    Put-RawOwn $root $givers
    $run = Invoke-Tool $root
    Equal $run.Exit 0 'E15: the run succeeds'
    $pins = Get-Pins $root
    $gotBlocked = @($blocked | Where-Object { (Find-Pin $pins $_).Count -gt 0 })
    Equal ($gotBlocked -join ',') '' 'E15: no internal name, system category or world/bonus/hidden kind gets a pin'
    $missing = @($okIds | Where-Object { (Find-Pin $pins $_).Count -ne 1 })
    Equal ($missing -join ',') '' 'E15: a holiday, Landfall, daily, weekly, repeatable and unkinded task quest does'

    # ---------- E16: when the tables are missing, or the quest is not in the data ----------
    $root = New-World 'e16'
    Remove-Item "$root\tools\QuestInfo.csv"
    Put-RawOwn $root @((G 'Creature:3707' 'Pinless Pete' 69933 '84 33.3 44.4 5' '103' ''))
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 103).Count 0 'E16: without the QuestInfo table no quest gets a pin'
    Check ($run.Report -match 'is missing') 'E16: and the report says why'
    $root = New-World 'e16b'
    Add-WorldQuests $root @((Q 150 'Short lived'))
    Put-RawOwn $root @((G 'Creature:3707' 'Pinless Pete' 69933 '84 33.3 44.4 5' '150' ''))
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 150).Count 1 'E16: a quest in the data gets its pin'
    $kept = @([IO.File]::ReadAllLines("$root\data\pins.jsonl") | Where-Object { $_ -notmatch '\[150\]' })
    [IO.File]::WriteAllText("$root\data\pins.jsonl", ($kept -join "`n") + "`n")
    $text = @([IO.File]::ReadAllLines("$root\data\quests.jsonl") | Where-Object { $_ -notmatch '"id":150,' })
    [IO.File]::WriteAllText("$root\data\quests.jsonl", ($text -join "`n") + "`n")
    $null = Invoke-AddonDataBuild -DataDir "$root\data" -AddonDir "$root\addon"
    $run = Invoke-Tool $root
    Equal $run.Exit 0 'E16: the run succeeds when the ledger holds a quest the data no longer has'
    Equal (Find-Pin (Get-Pins $root) 150).Count 0 'E16: and no pin is made for it'

    # ---------- E17: masks, recurrence, headings, starts, stale lists ----------
    $root = New-World 'e17'
    Add-WorldQuests $root @(
        (Q 600 'Race locked' 1 10 '' 3 1 8191), (Q 601 'Class locked' 1 10 '' 3 67108863 1), (Q 602 'No faction' 1 10 '' 0 67108863 8191),
        (Q 610 'Daily' 1), (Q 611 'Weekly' 1), (Q 612 'Weekly three' 1), (Q 613 'Repeatable' 1), (Q 614 'One time' 2),
        (Q 615 'One time zero' 0), (Q 616 'Daily ok' 4), (Q 617 'Conflict' 1), (Q 620 'Unplaced' 1 0))
    $qf = @(
        '[600] = "69933|1|32|1|2|8|"', '[601] = "69933|1|32|1|8|2|"', '[602] = "69933|1|32|1|8|2|"',
        '[610] = "69933|1|35|0|0|0|"', '[611] = "69933|1|37|0|0|0|"', '[612] = "69933|1|39|0|0|0|"', '[613] = "69933|1|105|0|0|0|"',
        '[614] = "69933|1|97|0|0|0|"', '[615] = "69933|1|97|0|0|0|"', '[616] = "69933|1|35|0|0|0|"', '[617] = "69933|1|35|0|0|0|"',
        '[620] = "69933|1|32|0|0|0|Duskwood"')
    Put-RawOwn $root @((G 'Creature:3707' 'Pinless Pete' 69933 '84 33.3 44.4 5' '600,601,602,610,611,612,613,614,615,616,617,620' '')) $qf `
        @('[101] = "2|0|0|-1|-1|69933|3",')
    Put-RawPlayer $root 'p01' @((G 'Creature:3707' 'Pinless Pete' 69933 '84 33.3 44.4 1' '617' '')) @('[617] = "69933|1|37|0|0|0|"')
    $run = Invoke-Tool $root
    Equal $run.Exit 0 'E17: the run succeeds'
    $masks = @(Import-Csv "$root\tools\recorded_mask_contradictions.csv")
    Equal (($masks | ForEach-Object { "$($_.Quest):$($_.Mask)" } | Sort-Object) -join ' ') '600:race 601:class' 'E17: a race and a class the data excludes are contradictions; a zero mask is none'
    $types = @(Import-Csv "$root\tools\recorded_quest_types.csv")
    Equal (($types | ForEach-Object { "$($_.Quest):$($_.Recorded):$($_.Suggested)" } | Sort-Object) -join ' ') '610:daily:4 611:weekly:128 612:weekly:128 613:repeatable:2 614:one-time:1 617:conflict: frequency 1 / 2:' 'E17: recorded recurrence that is not the type, or that disagrees, is listed, and only that'
    $heads = @(Import-Csv "$root\tools\recorded_headings.csv")
    Equal (($heads | ForEach-Object { "$($_.Quest):$($_.Headings)" }) -join ' ') '620:Duskwood' 'E17: a log heading is listed for an unplaced quest only'
    $starts = @(Import-Csv "$root\tools\recorded_start_items.csv")
    Equal ($starts.Count) 1 'E17: a start on no map is listed'
    Check ((Read-RecordedLedger "$root\ledger.csv").Values | Where-Object { $_.Role -eq 'start' -and $_.Map -eq '0' }) 'E17: and is in the ledger'
    Put-RawOwn $root @((G 'Creature:3707' 'Pinless Pete' 69933 '84 33.3 44.4 5' '' ''))
    Remove-Item "$root\tools\recordings\players\p01" -Recurse -Force
    $run = Invoke-Tool $root
    Check (-not (Test-Path "$root\tools\recorded_mask_contradictions.csv")) 'E17: a list with nothing in it is removed'
    Check (-not (Test-Path "$root\tools\recorded_quest_types.csv")) 'E17: all of them'

    # ---------- E18: the probe's file, extra map tables, tags ----------
    $root = New-World 'e18'
    New-Item -ItemType Directory -Path "$root\tools\forever_probe_70245" | Out-Null
    [IO.File]::WriteAllText("$root\tools\forever_probe_70245\QCForeverProbe.lua", @'
QCForeverProbeDB = {
	["givers"] = {
		["Creature:3595"] = {["kind"] = "Creature", ["id"] = 3595, ["name"] = "Shanda", ["build"] = "1.60.1.70245", ["spots"] = {["1438 56.3 59.9"] = 4}, ["offers"] = {[200] = {}}},
	},
}
'@)
    [IO.File]::WriteAllText("$root\tools\UiMap-12.1.0.69933.csv", "Name_lang,ID,ParentUiMapID,Flags,System,Type`r`nNew place,777,0,0,0,3`r`n")
    Put-RawOwn $root @((G 'Creature:3707' 'Pinless Pete' 69933 '777 33.3 44.4 5' '103' ''))
    foreach ($tag in 'own1', 'p 1', 'a;b', ('x' * 25)) {
        $dir = "$root\tools\recordings\players\$tag"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        New-RawRecorder "$dir\QuestCompletist.lua" @((G 'Creature:3999' 'Impostor' 69933 '37 5.0 5.0 9' '101' ''))
    }
    $run = Invoke-Tool $root
    $led = Read-RecordedLedger "$root\ledger.csv"
    Check (@($led.Values | Where-Object { $_.Src -match 'own-forever_probe_70245=' -and $_.Game -eq 'forever' -and $_.Role -eq 'offer' }).Count -eq 1) 'E18: the probe''s file is read, under its own tag'
    Check (@($led.Values | Where-Object { $_.Role -eq 'spot' -and $_.Map -eq '777' }).Count -eq 1) 'E18: a map from an extra UiMap table is a place'
    Check (@($led.Values | Where-Object { $_.Npc -eq '3999' }).Count -eq 0) 'E18: no folder that is not a tag is read (own1, a space, a semicolon, 25 characters)'
    $mapOrder = @((Get-Pins $root) | ForEach-Object { [int]$_.map })
    Check (@(1..($mapOrder.Count - 1) | Where-Object { $mapOrder[$_] -lt $mapOrder[$_ - 1] }).Count -eq 0) 'E18: a pin on a map the file had none of goes after the others, keeping the maps in order'

    # ---------- E19: no position ----------
    $root = New-World 'e19' @(
        '{"map":500,"icon":1,"x":20,"y":20,"quests":[110]}',
        '{"map":500,"icon":1,"x":30,"y":30,"quests":[110]}',
        '{"map":84,"icon":1,"x":40,"y":40,"quests":[111]}',
        '{"map":500,"icon":1,"x":50,"y":50,"quests":[111]}',
        '{"map":500,"icon":1,"x":60,"y":60,"quests":[112]}')
    Put-RawOwn $root @(
        (G 'Creature:3710' 'Dungeon Dan' 69933 '500 -1 -1 2' '110,111' ''),
        (G 'Creature:3711' 'Dungeon Dora' 69933 '500 -1 -1 2' '112' ''))
    [IO.File]::WriteAllText("$root\decisions.csv", '"Quest","Map","X","Y","Decision","Reason"' + "`r`n" + '"112","500","60","60","KEEP","looked"' + "`r`n")
    $run = Invoke-Tool $root
    $pins = Get-Pins $root
    Equal (Review-Count $run.Report 'recorded without a position') 1 'E19: only a quest with one pin on the map is reported for a giver with no position (111 has pins on two maps, one each; 110 two on one)'
    Check ($run.Report -match 'recorded without a position: quest 111 map 500') 'E19: it is the pin on map 500 for quest 111'
    Check (-not ($run.Report -match 'recorded without a position: quest 112')) 'E19: a decision silences it'
    Check ((@(Find-Pin $pins 110 | ForEach-Object { $_ } | Where-Object { $_.npc }).Count) -eq 0) 'E19: nothing is filled'

    # ---------- E20: phased copies of one name ----------
    $root = New-World 'e20' @(
        '{"map":37,"icon":1,"x":30,"y":30,"quests":[115,116,117]}',
        '{"map":84,"icon":1,"x":60,"y":60,"quests":[111]}',
        '{"map":84,"icon":1,"x":20,"y":20,"quests":[112]}')
    Put-RawOwn $root @(
        (G 'Creature:3720' 'Twin' 69933 '37 30.2 30.1 9' '115' ''),
        (G 'Creature:3721' 'Twin' 69933 '37 30.4 30.0 1' '116,117' ''),
        (G 'Creature:3730' 'Same' 69933 '84 60.1 60.1 3' '111' ''),
        (G 'Creature:3731' 'Same' 69933 '84 60.2 60.0 6' '111' ''),
        (G 'Creature:3741' 'Eq' 69933 '84 20.1 20.1 2' '112' ''),
        (G 'Creature:3740' 'Eq' 69933 '84 20.2 20.0 2' '112' ''))
    $run = Invoke-Tool $root
    $pins = Get-Pins $root
    Equal (Find-Pin $pins 115)[0].npc 3721 'E20: of two givers of one name the one that offers more of the pin''s quests wins, however seldom it was seen'
    Equal (Find-Pin $pins 111)[0].npc 3731 'E20: on a tie, the one seen more'
    Equal (Find-Pin $pins 112)[0].npc 3740 'E20: on a tie of that, the lower ID'

    # ---------- E21: a fill that would put two pins of one NPC close together ----------
    $root = New-World 'e21'
    Add-Many $root 700 730
    $pinLines = @(
        '{"map":37,"icon":1,"npc":3801,"name":"N1","x":10,"y":10,"quests":[700]}', '{"map":37,"icon":1,"x":10.3,"y":10,"quests":[701]}',
        '{"map":37,"icon":1,"npc":3802,"name":"N2","x":20,"y":20,"quests":[702]}', '{"map":37,"icon":1,"x":21.4,"y":20,"quests":[703]}',
        '{"map":37,"icon":1,"npc":3803,"name":"N3","x":30,"y":30,"quests":[704]}', '{"map":37,"icon":1,"x":33,"y":30,"quests":[705]}',
        '{"map":37,"icon":1,"npc":3804,"name":"N4","x":40,"y":40,"quests":[706]}', '{"map":37,"icon":1,"x":41.5,"y":40,"quests":[707]}',
        '{"map":37,"icon":1,"npc":3805,"name":"N5","x":50,"y":50,"quests":[708]}', '{"map":37,"icon":1,"x":50,"y":50,"quests":[709]}',
        '{"map":37,"icon":1,"x":60,"y":60,"quests":[710]}', '{"map":37,"icon":1,"x":61,"y":60,"quests":[711]}')
    [IO.File]::WriteAllText("$root\data\pins.jsonl", (($pinLines -join "`n") + "`n"))
    $null = Invoke-AddonDataBuild -DataDir "$root\data" -AddonDir "$root\addon"
    Put-RawOwn $root @(
        (G 'Creature:3801' 'N1' 69933 '37 10.35 10.0 2' '701' ''), (G 'Creature:3802' 'N2' 69933 '37 21.4 20.0 2' '703' ''),
        (G 'Creature:3803' 'N3' 69933 '37 33.0 30.0 2' '705' ''), (G 'Creature:3804' 'N4' 69933 '37 41.5 40.0 2' '707' ''),
        (G 'Creature:3805' 'N5' 69933 '37 50.0 50.0 2' '709' ''), (G 'Creature:3806' 'N6' 69933 '37 60.4 60.0 2' '710,711' ''))
    $run = Invoke-Tool $root
    $pins = Get-Pins $root
    Check (-not (Find-Pin $pins 701)[0].npc) 'E21: a fill 0.3 from a pin of the same NPC is not made'
    Check (-not (Find-Pin $pins 703)[0].npc) 'E21: nor 1.4 from it'
    Equal (Find-Pin $pins 705)[0].npc 3803 'E21: but 3 points from it is'
    Check (-not (Find-Pin $pins 707)[0].npc) 'E21: exactly 1.5 points is as near as the floor allows, so not'
    Equal (Find-Pin $pins 709)[0].npc 3805 'E21: on the same spot is fine'
    Equal (@((Find-Pin $pins 710) + (Find-Pin $pins 711) | Where-Object { $_.npc }).Count) 1 'E21: of two blank pins 1 point apart for one NPC only one is filled'
}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------- part c ----------------
try {
    # ---------- E22: the other decision files ----------
    $root = New-World 'e22' @(
        '{"map":84,"icon":1,"x":60,"y":60,"quests":[111]}',
        '{"map":84,"icon":1,"x":70,"y":70,"quests":[112]}',
        '{"map":84,"icon":1,"x":80,"y":80,"quests":[113]}')
    Put-RawOwn $root @(
        (G 'Creature:3703' 'Sam' 69933 '84 60.2 60.1 2' '111' ''),
        (G 'Creature:3704' 'Tom' 69933 '84 70.2 70.1 2' '112' ''),
        (G 'Creature:3705' 'Walt' 69933 '84 80.2 80.1 2' '113' ''))
    [IO.File]::WriteAllText("$root\giverdecisions.csv", '"Quest","Map","X","Y","Decision","NpcId","Reason"' + "`r`n" + '"113","84","80","80","MOVE","","x"' + "`r`n")
    [IO.File]::WriteAllText("$root\npcdecisions.csv", 'Action,Map,MapName,X,Y,Name,Id,GameNameForId,Quests,Wowhead,NewName,NewId,Note' + "`r`n" +
        'ID,84,Stormwind,70,70,Tom,99,Tom,112,,,12345,"changed to another"' + "`r`n" + 'NAME,84,Stormwind,60,60,Sam,3703,Sam,111,,Samuel,,"renamed"' + "`r`n")
    $run = Invoke-Tool $root @('-GiverDecisionsFile', "$root\giverdecisions.csv", '-NpcIdDecisionsFile', "$root\npcdecisions.csv")
    $pins = Get-Pins $root
    Equal (Find-Pin $pins 111)[0].npc 3703 'E22: a row of pin-npc-id-decisions.csv that is not an ID removal does not stop a fill'
    Equal (Find-Pin $pins 112)[0].npc 3704 'E22: nor an ID change'
    Equal (Find-Pin $pins 113)[0].npc 3705 'E22: nor a decision in pin-giver-decisions.csv that is not KEEP'

    # ---------- E23: trust, layer by layer ----------
    $root = New-World 'e23'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '' ''))
    Put-RawPlayer $root 'p01' @((G 'Creature:3702' 'Stable Master Gil' 69933 '' '102' ''))
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'E23: an offer one player saw is not acted on, though the place is the maintainer''s'
    Put-RawPlayer $root 'p02' @((G 'Creature:3702' 'Stable Master Gil' 69933 '' '102' ''))
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 102)[0].npc 3702 'E23: two players'' offer is'

    $root = New-World 'e23b' @('{"map":84,"icon":1,"npc":4006,"name":"Erin","x":70,"y":70,"quests":[103]}')
    Put-RawOwn $root @((G 'Creature:4006' 'Erin' 69933 '84 70.1 70.1 2' '' ''), (G 'Creature:4007' 'Frank' 69933 '84 10.0 10.0 2' '103' ''))
    Put-RawPlayer $root 'p01' @((G 'Creature:4006' 'Erin' 69933 '84 70.1 70.1 1' '' '103'))
    $run = Invoke-Tool $root
    Equal (Review-Count $run.Report 'pin at the hand-in') 0 'E23: a turn-in one player saw is not a hand-in'
    Put-RawPlayer $root 'p02' @((G 'Creature:4006' 'Erin' 69933 '84 70.1 70.1 1' '' '103'))
    $run = Invoke-Tool $root
    Equal (Review-Count $run.Report 'pin at the hand-in') 1 'E23: two players'' turn-in is'

    $root = New-World 'e23c'
    Put-RawOwn $root @((G 'Creature:3702' '' 69933 '37 50.4 50.2 3' '102' ''))
    Put-RawPlayer $root 'p01' @((G 'Creature:3702' 'Stable Master Gil' 69933 '' '' ''))
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'E23: a name one player gave is not enough'
    Check ($run.Report -match 'giver without a trusted English name') 'E23: and the report says so'
    Check (@(Ledger-Rows $root | Where-Object { $_.Role -eq 'giver' -and $_.Name -eq '' }).Count -eq 0) 'E23: a nameless giver is not a ledger row'

    $root = New-World 'e23d'
    Put-RawOwn $root @((G 'Creature:3702' 'Gil' 69933 '37 50.4 50.2 3' '102' ''))
    foreach ($tag in 'p01', 'p02') { Put-RawPlayer $root $tag @((G 'Creature:3702' 'Gill' 69933 '37 50.4 50.2 3' '102' '')) }
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'E23: when two trusted names disagree no name is used, whoever gave which'
    Check ($run.Report -match 'trusted sources disagree on the giver') 'E23: and the review says so'
    Check ($run.Report -match "Creature:3702: Gil / Gill") 'E23: and the report names the two'
    Equal (@(Ledger-Rows $root | Where-Object { $_.Role -eq 'giver' -and $_.Npc -eq '3702' }).Count) 2 'E23: two names for one giver are two ledger rows, one per name'

    $root = New-World 'e23e'
    foreach ($tag in 'p01', 'p02', 'p03') { Put-RawPlayer $root $tag @((G 'Creature:3702' 'Zed' 69933 '37 50.4 50.2 3' '102' '')) }
    foreach ($tag in 'p04', 'p05') { Put-RawPlayer $root $tag @((G 'Creature:3702' 'Abe' 69933 '37 50.4 50.2 3' '102' '')) }
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'E23: nor does the name more players gave win over another trusted one'

    # ---------- E24: the safety check, rule by rule ----------
    $root = New-World 'e24' @(
        '{"map":37,"icon":1,"npc":3701,"name":"Guard Roberts","x":45.3,"y":67.8,"quests":[100,101],"note":"Hello"}',
        '{"map":37,"icon":1,"x":50,"y":50,"quests":[102]}')
    $pins = New-Object System.Collections.Generic.List[object]
    foreach ($pin in (Read-PinData "$root\data")) { $pins.Add($pin) }
    $snapshot = Get-PinSnapshot $pins
    Equal @(Test-RecordedChangeSafe $snapshot $pins).Count 0 'E24: untouched pins pass'
    Set-RecordField $pins[0] 'y' ([decimal]67.9)
    Check (@(Test-RecordedChangeSafe $snapshot $pins) -match 'moved') 'E24: a pin moved in y does not'
    Set-RecordField $pins[0] 'y' ([decimal]67.8)
    Set-RecordField $pins[0] 'map' 84
    Check (@(Test-RecordedChangeSafe $snapshot $pins) -match 'moved') 'E24: a pin on another map does not'
    Set-RecordField $pins[0] 'map' 37
    Set-RecordField $pins[0] 'icon' 3
    Check (@(Test-RecordedChangeSafe $snapshot $pins) -match 'icon') 'E24: a changed icon does not'
    Set-RecordField $pins[0] 'icon' 1
    Set-RecordField $pins[0] 'note' 'Hello!'
    Check (@(Test-RecordedChangeSafe $snapshot $pins) -match 'note') 'E24: a changed note does not'
    Set-RecordField $pins[0] 'note' 'hello'
    Check (@(Test-RecordedChangeSafe $snapshot $pins) -match 'note') 'E24: a note changed in case only does not'
    Set-RecordField $pins[0] 'note' 'Hello'
    Set-RecordField $pins[0] 'name' 'guard roberts'
    Check (@(Test-RecordedChangeSafe $snapshot $pins) -match 'name') 'E24: a name changed in case only does not'
    Set-RecordField $pins[0] 'name' 'Guard Roberts'
    Set-RecordField $pins[1] 'npc' 5
    Check (@(Test-RecordedChangeSafe $snapshot $pins) -match 'NPC and no name') 'E24: an NPC ID without a name does not'
    Set-RecordField $pins[1] 'npc' 0
    Equal @(Test-RecordedChangeSafe $snapshot $pins).Count 0 'E24: and all put back passes'
    $pins.Add([pscustomobject]@{ map = 37; icon = 1; npc = 0; name = 'New'; x = [decimal]1; y = [decimal]1; quests = @(); note = $null })
    Check (@(Test-RecordedChangeSafe $snapshot $pins) -match 'no quest') 'E24: a new pin with no quest does not'
    $pins[$pins.Count - 1] = [pscustomobject]@{ map = 37; icon = 1; npc = 7; name = $null; x = [decimal]1; y = [decimal]1; quests = @(100); note = $null }
    Check (@(Test-RecordedChangeSafe $snapshot $pins) -match 'NPC and no name') 'E24: a new pin with an NPC and no name does not'

    # ---------- E25: the tool saves nothing when the check fails ----------
    $root = New-World 'e25' @(
        '{"map":37,"icon":1,"npc":3701,"x":45.3,"y":67.8,"quests":[100]}',
        '{"map":37,"icon":1,"x":50,"y":50,"quests":[102]}')
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' ''))
    $before = Get-PinText $root
    $run = Invoke-Tool $root
    Equal $run.Exit 0 'E25: a pin that already has an NPC and no name does not stop the run'
    Equal (Find-Pin (Get-Pins $root) 102)[0].npc 3702 'E25: and another pin is filled all the same'
    Equal (Find-Pin (Get-Pins $root) 100)[0].npc 3701 'E25: while the odd one is left as it was'
    Check ($null -eq (Find-Pin (Get-Pins $root) 100)[0].name) 'E25: without a name'

    # ---------- E26: the review honours the decisions ----------
    $root = New-World 'e26' @('{"map":37,"icon":1,"npc":4001,"name":"Alice","x":30,"y":30,"quests":[100]}')
    Put-RawOwn $root @((G 'Creature:4002' 'Bob' 69933 '37 30.3 30.1 2' '100' ''))
    $run = Invoke-Tool $root
    Equal (Review-Count $run.Report 'pin names another NPC than the recorded giver') 1 'E26: a pin whose NPC is not the one recorded there is reported'
    [IO.File]::WriteAllText("$root\decisions.csv", '"Quest","Map","X","Y","Decision","Reason"' + "`r`n" + '"100","37","30","30","KEEP","looked"' + "`r`n")
    $run = Invoke-Tool $root
    Equal (Review-Count $run.Report 'pin names another NPC than the recorded giver') 0 'E26: unless a decision says it stays'

    # ---------- E27: start lists, flagged quests, Forever starts and maps ----------
    $root = New-World 'e27'
    Put-RawOwn $root @((G 'Creature:3701' 'Guard Roberts' 69933 '37 45.3 67.8 2' '100' '')) @() `
        @('[103] = "1|5555|84|12.3|45.6|69933|3"', '[100] = "2|0|37|45.3|67.8|69933|4"') @{ 69933 = '12.1.0' } `
        @('qcFlaggedButSeen = {', '[101] = {["how"] = "accepted", ["time"] = 1, ["build"] = 120100},', '}')
    New-RawRecorder "$root\tools\recordings\own\forever\QuestCompletist.lua" @((G 'Creature:3595' 'Shanda' 70245 '1438 56.3 59.9 4' '200' '')) @() @('[201] = "1|6000|1438|10.0|20.0|70245|3"') @{ 70245 = '1.60.1' }
    $run = Invoke-Tool $root
    Equal $run.Exit 0 'E27: the run succeeds'
    $starts = @(Import-Csv "$root\tools\recorded_start_items.csv")
    Equal (($starts | Where-Object { $_.Game -eq 'retail' } | ForEach-Object { "$($_.Quest):$($_.Pinned)" } | Sort-Object) -join ' ') '100:True 103:False' 'E27: the start list says whether each retail quest has a pin'
    Equal (($starts | Where-Object { $_.Game -eq 'forever' } | ForEach-Object { "$($_.Quest):$($_.Pinned)" }) -join ' ') '201:False' 'E27: and Forever''s starts are listed beside them, against Forever''s pins'
    Check ($run.Report -match '1 quests flagged unavailable that a player accepted') 'E27: flagged quests are counted'
    $led = Read-RecordedLedger "$root\ledger.csv"
    Check (@($led.Values | Where-Object { $_.Game -eq 'forever' -and $_.Role -eq 'spot' -and $_.Map -eq '1438' }).Count -eq 1) 'E27: Forever''s map table is Forever''s'
    Check (@($led.Values | Where-Object { $_.Role -eq 'offer' -and $_.FirstBuild -eq '69933' -and $_.LastBuild -eq '69933' }).Count -ge 1) 'E27: a ledger offer row has its build'
    Check (@($led.Values | Where-Object { $_.Role -eq 'giver' -and $_.FirstBuild -eq '0' }).Count -eq 0) 'E27: and no row has build 0'

    # ---------- E28: versions come from the TOCs ----------
    $root = New-World 'e28'
    [IO.File]::WriteAllText("$root\addon\QuestCompletist.toc", "## Interface: 120200`r`n")
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' ''))
    Put-RawPlayer $root 'p01' @((G 'Creature:3703' 'Old Name' 70500 '84 60.5 60.5 1' '111' '')) @() @() @{ 70500 = '12.2.0' }
    $run = Invoke-Tool $root
    Check ($run.Report -match 'Versions read: 12.2., 1.60.') 'E28: the versions are the TOC''s'
    $led = Read-RecordedLedger "$root\ledger.csv"
    Check (@($led.Values | Where-Object { $_.Npc -eq '3703' }).Count -gt 0) 'E28: a build the TOC names is read'
    Check (@($led.Values | Where-Object { $_.Npc -eq '3702' }).Count -eq 0) 'E28: one it does not is not'

    # ---------- E29: the report says why a file was refused, and names are bytes ----------
    $root = New-World 'e29' @('{"map":37,"icon":1,"x":50,"y":50,"quests":[102]}')
    $fancy = "S" + [char]0x00E9 + "raphine"
    Put-RawOwn $root @((G 'Creature:3702' $fancy 69933 '37 50.4 50.2 3' '102' ''))
    New-Item -ItemType Directory -Path "$root\tools\recordings\players\p09" | Out-Null
    [IO.File]::WriteAllText("$root\tools\recordings\players\p09\QuestCompletist.lua", "os.execute('echo hi')`n")
    $keepEncoding = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(437); $run = Invoke-Tool $root } finally { [Console]::OutputEncoding = $keepEncoding }
    Equal (Find-Pin (Get-Pins $root) 102)[0].name $fancy 'E29: a name with an accent comes through the reader and the pins as it was, on a console that is not UTF-8'
    Check ($run.Report -match 'Not read: p09 .*: not plain saved variables') 'E29: a refused file says why, in the reader''s words'
    Check ($run.Report -notmatch "refused\t") 'E29: without the reader''s keyword'
    Check (@(Ledger-Rows $root | Where-Object { $_.Role -eq 'giver' -and $_.Name -ceq $fancy }).Count -eq 1) 'E29: and the ledger holds the name'

    # ---------- E30: forgetting counts its rows ----------
    $root = New-World 'e30'
    Put-RawPlayer $root 'p05' @((G 'Creature:3790' 'Only Seen By Five' 69933 '37 70.0 70.0 1' '101' ''))
    $null = Invoke-Tool $root
    $run = Invoke-Tool $root @('-ForgetTag', 'p05')
    Check ($run.Report -match 'Forgot source p05: it was in 3 ledger rows') 'E30: forgetting names the number of rows it was in (a giver, a spot, an offer)'
    Put-RawOwn $root @((G 'Creature:3701' 'Guard Roberts' 69933 '37 45.3 67.8 2' '100' ''))
    $run = Invoke-Tool $root @('-ForgetTag', 'nobody')
    Check ($run.Report -match 'Forgot source nobody: it was in 0 ledger rows') 'E30: a source that was never there is in none'

    # ---------- E31: the ledger is in a fixed order ----------
    $root = New-World 'e31'
    Put-RawOwn $root @(
        (G 'Creature:100' 'Hundred' 69933 '37 5.0 5.0 1' '101' ''),
        (G 'Creature:99' 'Ninety Nine' 69933 '37 9.0 9.0 1' '102' ''),
        (G 'GameObject:7' 'Chest' 69933 '37 20.0 20.0 1' '' ''))
    $null = Invoke-Tool $root
    $rows = @(Import-Csv "$root\ledger.csv" -Encoding UTF8)
    Equal (($rows | ForEach-Object { "$($_.Role):$($_.Kind):$($_.Npc)" }) -join ' ') 'giver:Creature:99 giver:Creature:100 giver:GameObject:7 spot:Creature:99 spot:Creature:100 spot:GameObject:7 offer:Creature:99 offer:Creature:100' 'E31: rows go by role, kind, then NPC as a number'

    # ---------- E32: names that differ in case only are different names ----------
    $root = New-World 'e32' @('{"map":37,"icon":1,"x":30,"y":30,"quests":[115,116]}')
    Put-RawOwn $root @(
        (G 'Creature:3720' 'Gil' 69933 '37 30.2 30.1 9' '115' ''),
        (G 'Creature:3721' 'GIL' 69933 '37 30.4 30.0 1' '116' ''))
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 115)[0].npc) 'E32: two givers whose names differ in case only do not fill one pin'
    Check ($run.Report -match 'two givers at one pin') 'E32: and the report says why'

    # ---------- E33: the radius of a fill is 1.5, and so is the radius of a place ----------
    $root = New-World 'e33' @(
        '{"map":37,"icon":1,"x":30,"y":30,"quests":[100]}',
        '{"map":37,"icon":1,"x":50,"y":50,"quests":[101]}',
        '{"map":37,"icon":1,"x":70,"y":70,"quests":[102]}')
    Put-RawOwn $root @(
        (G 'Creature:3801' 'Far Fan' 69933 '37 31.8 30.0 2' '100' ''),
        (G 'Creature:3802' 'Near Fan' 69933 '37 51.4 50.0 2' '101' ''),
        (G 'Creature:3803' 'Edge Fan' 69933 '37 71.5 70.0 2' '102' ''),
        (G 'Creature:3707' 'Pinless Pete' 69933 '84 10.0 10.0 5;84 12.0 10.0 4;84 10.5 10.0 1' '103' ''))
    $run = Invoke-Tool $root
    $pins = Get-Pins $root
    Check (-not (Find-Pin $pins 100)[0].npc) 'E33: a giver 1.8 points from the pin does not fill it'
    Equal (Find-Pin $pins 101)[0].npc 3802 'E33: 1.4 points does'
    Equal (Find-Pin $pins 102)[0].npc 3803 'E33: and so does exactly 1.5'
    Check ($run.Report -match "quest 103: Creature:3707 'Pinless Pete' at map 84 10,10 \(1 other places in the ledger\)") 'E33: spots 0.5 apart are one place, 2 apart are two, and the pin goes to the more visited'
}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------- part d: what the first round left alive ----------------
try {
    # ---------- E34: units ----------
    Check (Test-NearPlace 10 10 11.1 10.9) 'E34: 1.1 and 0.9 apart is 1.42 straight, near (a walk along both axes would be 2.0)'
    $places = Get-RecordedPlaces @(
        [pscustomobject]@{ Map = '84'; X = '-1'; Y = '-1'; Src = 'own-retail=9' },
        [pscustomobject]@{ Map = '84'; X = '0.5'; Y = '0.5'; Src = 'own-retail=1' })
    Equal $places.Count 2 'E34: a place with no position never takes in a place with one, however often it was seen'
    Equal (ConvertTo-PlainPinName '  Gil  ') 'Gil' 'E34: a name is compared without the spaces round it'
    Equal (Get-RecordedClass 'owner') 'owner' 'E34: only a tag that begins own- is the maintainer''s'
    Equal (Get-RecordedClass 'own1') 'own1' 'E34: so own1 is a player of that name'
    $pinList = New-Object System.Collections.Generic.List[object]
    foreach ($spec in @(@(5, 30, 20, 7), @(5, 30, 10, 9), @(5, 30, 10, 3), @(5, 10, 10, 1), @(2, 90, 90, 1))) {
        $pinList.Add([pscustomobject]@{ map = 37; icon = 1; npc = $spec[3]; name = "n$($spec[3])"; x = [decimal]$spec[1]; y = [decimal]$spec[2]; quests = [int[]]@($spec[0]); note = $null })
    }
    Sort-PinBlock $pinList 37
    Equal (($pinList | ForEach-Object { "$($_.quests[0])@$($_.x),$($_.y)#$($_.npc)" }) -join ' ') '2@90,90#1 5@10,10#1 5@30,10#3 5@30,10#9 5@30,20#7' 'E34: a map''s pins go by lowest quest, then x, then y, then NPC'
    $dupes = New-Object System.Collections.Generic.List[object]
    foreach ($tag in 'first', 'second', 'third') { $dupes.Add([pscustomobject]@{ map = 37; icon = 1; npc = 0; name = $tag; x = [decimal]5; y = [decimal]5; quests = [int[]]@(5); note = $null }) }
    Sort-PinBlock $dupes 37
    Equal (($dupes | ForEach-Object { $_.name }) -join ' ') 'first second third' 'E34: pins that tie in everything keep the order they had'
    $syn = [pscustomobject]@{ Tag = 't'; Path = 'p'; Refused = $null; Kind = 'recorder'; Schema = '1'; Game = 'retail'; Records = 1; Odd = 0; Builds = @{ 69933 = '12.1.0' }
        Givers = (New-Object System.Collections.Generic.List[object]); Spots = (New-Object System.Collections.Generic.List[object]); Offers = (New-Object System.Collections.Generic.List[object])
        Turnins = (New-Object System.Collections.Generic.List[object]); Quests = (New-Object System.Collections.Generic.List[object]); Starts = (New-Object System.Collections.Generic.List[object])
        Diag = @{}; Flagged = (New-Object System.Collections.Generic.List[object]) }
    $syn.Givers.Add([pscustomobject]@{ Kind = 'Creature'; Npc = 1; Name = 'A'; Build = 69933 })
    foreach ($xy in @(@('150', '5'), @('5', '-3'), @('-1', '-1'), @('100', '0'))) { $syn.Spots.Add([pscustomobject]@{ Kind = 'Creature'; Npc = 1; Map = 84; X = $xy[0]; Y = $xy[1]; Visits = 1; Build = 69933 }) }
    $mapIds = @{ retail = (New-Object 'System.Collections.Generic.HashSet[int]'); forever = (New-Object 'System.Collections.Generic.HashSet[int]') }
    [void]$mapIds.retail.Add(84)
    $facts = Get-RecordedFacts $syn @('12.1.') $mapIds @{ retail = (New-Object 'System.Collections.Generic.HashSet[int]'); forever = (New-Object 'System.Collections.Generic.HashSet[int]') }
    Equal (($facts.Spots | ForEach-Object { "$($_.X),$($_.Y)" }) -join ' ') '-1,-1 100,0' 'E34: a spot is kept only at -1 -1 or inside 0 to 100, whatever the reader let through'

    # ---------- E35: odd records at the edges ----------
    $root = New-World 'e35a'
    $g = @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' '')) + @(1..2 | ForEach-Object { (G "Creature:38$_" "Fine $_" 69933 '' '' '') }) + @((G 'Player:1' 'x' 69933 '' '' ''))
    Put-RawOwn $root $g
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 102)[0].npc 3702 'E35: one odd record of four is read (fewer than three odd ones is never enough)'
    $root = New-World 'e35b'
    $g = @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' '')) + @(1..15 | ForEach-Object { (G "Creature:38$_" "Fine $_" 69933 '' '' '') }) + @(1..4 | ForEach-Object { (G "Player:$_" 'x' 69933 '' '' '') })
    Put-RawOwn $root $g
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 102)[0].npc 3702 'E35: four odd records of twenty are exactly a fifth, which is not more than a fifth'

    # ---------- E36: builds and facts of builds that are not read ----------
    $root = New-World 'e36'
    Add-WorldQuests $root @((Q 620 'Unplaced' 1 0))
    Put-RawOwn $root @((G 'Creature:3703' 'Old Name' 69933 '84 60.5 60.5 1' '111' '')) @('[620] = "60000|1|32|0|0|0|Duskwood"') @('[102] = "1|55|84|10.0|10.0|60000|3"') @{ 60000 = '12.0.7'; 69933 = '12.1.0' }
    $run = Invoke-Tool $root
    Check (-not (Test-Path "$root\tools\recorded_headings.csv")) 'E36: a quest note of a build that is not read is not used'
    Check (-not (Test-Path "$root\tools\recorded_start_items.csv")) 'E36: nor a start'
    $root = New-World 'e36b'
    Put-RawOwn $root @((G 'Creature:3703' 'Old Name' 69933 '84 60.5 60.5 1' '111' ''))
    $run = Invoke-Tool $root @('-Builds', '12.1.0')
    Equal (Find-Pin (Get-Pins $root) 111)[0].npc 3703 'E36: -Builds takes a whole version as well as a prefix'

    # ---------- E37: quests the data lacks, in every role ----------
    $root = New-World 'e37'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102,99999' '99996')) @('[99994] = "69933|1|32|0|0|0|"') @('[99995] = "1|55|84|10.0|10.0|69933|3"')
    $run = Invoke-Tool $root
    $led = Read-RecordedLedger "$root\ledger.csv"
    Equal (@($led.Values | Where-Object { $_.Quest -in '99999', '99996', '99995' }).Count) 0 'E37: no ledger row names a quest the data lacks (offer, turn-in or start)'
    $list = [IO.File]::ReadAllText("$root\tools\recorded_unknown_quests.csv")
    Check ($list -match '99999' -and $list -match '99995' -and $list -match '99994') 'E37: the unknown offer, start and quest note are listed'
    Check ($run.Report -match 'left out: 4 with quest it does not read') 'E37: all four are counted'

    # ---------- E38: build bookkeeping and spot keys ----------
    $root = New-World 'e38'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 70000 '37 50.0 50.0 3;37 50.0 60.0 2' '102' '')) @() @() @{ 70000 = '12.1.5' }
    $null = Invoke-Tool $root
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.0 50.0 3;37 50.0 60.0 2' '102' ''))
    $null = Invoke-Tool $root
    $rows = Ledger-Rows $root
    Equal (@($rows | Where-Object { $_.Role -eq 'spot' }).Count) 2 'E38: two spots with one x and two y are two rows'
    Equal ((@($rows | Where-Object { $_.Role -eq 'giver' })[0]).FirstBuild) '69933' 'E38: a row read again in an older build has that build as its first'
    Equal ((@($rows | Where-Object { $_.Role -eq 'giver' })[0]).LastBuild) '70000' 'E38: and keeps the newer as its last'

    # ---------- E39: forgetting counts only the rows with the source ----------
    $root = New-World 'e39'
    Put-RawOwn $root @((G 'Creature:3701' 'Guard Roberts' 69933 '37 45.3 67.8 2' '100' ''))
    Put-RawPlayer $root 'p05' @((G 'Creature:3790' 'Only Seen By Five' 69933 '37 70.0 70.0 1' '101' ''))
    $null = Invoke-Tool $root
    $run = Invoke-Tool $root @('-ForgetTag', 'p05')
    Check ($run.Report -match 'Forgot source p05: it was in 3 ledger rows') 'E39: three of the six rows had p05'

    # ---------- E40: the review, case by case ----------
    $root = New-World 'e40' @(
        '{"map":37,"icon":1,"npc":4020,"name":"Lena","x":15,"y":15,"quests":[107]}',
        '{"map":84,"icon":1,"npc":4021,"name":"Mia","x":25,"y":25,"quests":[108]}',
        '{"map":84,"icon":1,"npc":4022,"name":"Pam","x":35,"y":35,"quests":[109]}',
        '{"map":37,"icon":1,"npc":4030,"name":"alice","x":45,"y":45,"quests":[110]}',
        '{"map":37,"icon":1,"npc":4005,"name":"david","x":55,"y":55,"quests":[111]}',
        '{"map":37,"icon":1,"npc":4040,"name":"Oz","x":65,"y":65,"quests":[112]}',
        '{"map":84,"icon":1,"npc":4050,"name":"Quin","x":45,"y":45,"quests":[113]}')
    Put-RawOwn $root @(
        (G 'Creature:4020' 'Lena' 69933 '84 15.0 15.0 2' '107' ''),
        (G 'Creature:4021' 'Mia' 69933 '84 25.1 25.1 2' '' '108'), (G 'Creature:4023' 'Ned' 69933 '37 25.0 25.0 2' '108' ''),
        (G 'Creature:4022' 'Pam' 69933 '84 35.1 35.1 2' '' '109'),
        (G 'Creature:4031' 'Alice' 69933 '37 45.2 45.1 2' '110' ''),
        (G 'Creature:4005' 'David' 69933 '37 55.1 55.1 2' '111' ''),
        (G 'Creature:4040' 'Oz' 69933 '37 20.0 20.0 2' '112' ''),
        (G 'Creature:4050' 'Quin' 69933 '84 45.1 45.1 2' '' '113'), (G 'Creature:4051' 'Rex' 69933 '84 5.0 5.0 2' '113' ''))
    Put-RawPlayer $root 'p01' @((G 'Creature:4040' 'Oz' 69933 '37 65.0 65.0 5' '' ''), (G 'Creature:4051' 'Rex' 69933 '84 45.0 45.0 5' '' ''))
    $run = Invoke-Tool $root
    Equal (Review-Count $run.Report 'quest offered away from its pins') 4 'E40: a giver on another map (107), one whose offers are on another map (108) and two whose only near place is one player''s (112, 113) are away'
    Equal (Review-Count $run.Report 'pin at the hand-in') 2 'E40: a hand-in whose every trusted offer is far or on another map is reported (108, 113), one with no recorded offer is not (109)'
    Equal (Review-Count $run.Report 'pin names another NPC than the recorded giver') 1 'E40: Alice for alice is another NPC, not the same name'
    Equal (Review-Count $run.Report 'same name under another ID') 0 'E40: and not a same name'
    Equal (Review-Count $run.Report 'pin name differs from the name recorded for its ID') 1 'E40: david for David is a different name'
    [IO.File]::WriteAllText("$root\decisions.csv", '"Quest","Map","X","Y","Decision","Reason"' + "`r`n" + '"111","37","55","55","KEEP","looked"' + "`r`n")
    $run = Invoke-Tool $root
    Equal (Review-Count $run.Report 'pin name differs from the name recorded for its ID') 0 'E40: a decision silences the name that differs'

    # ---------- E41: objects, case ----------
    $root = New-World 'e41' @(
        '{"map":84,"icon":1,"name":"old chest","x":33.3,"y":44.4,"quests":[117]}',
        '{"map":37,"icon":1,"name":"Notice Board","x":20,"y":20,"quests":[100]}')
    Put-RawOwn $root @(
        (G 'GameObject:175322' 'Old Chest' 69933 '84 33.4 44.4 5' '103' ''),
        (G 'GameObject:175321' 'Notice Board' 69933 '37 20.1 20.1 3' '100' ''))
    $run = Invoke-Tool $root
    $pins = Get-Pins $root
    Equal (@((Find-Pin $pins 103)[0].quests) -join ',') '103' 'E41: a pin that names an object in other letters is not the object''s pin: the quest gets its own'
    Check ($run.Report -match 'Retail pins: 0 get an NPC ID or a name; 0 quests join a pin, 1 new pins') 'E41: a pin that already names its object is not counted as filled'

    # ---------- E42: decisions by the quest that was offered ----------
    $root = New-World 'e42a' @('{"map":84,"icon":1,"x":20,"y":20,"quests":[101,102]}')
    Put-RawOwn $root @((G 'Creature:3704' 'Tom' 69933 '84 20.1 20.1 2' '102' ''))
    [IO.File]::WriteAllText("$root\decisions.csv", '"Quest","Map","X","Y","Decision","Reason"' + "`r`n" + '"102","84","20","20","KEEP","looked"' + "`r`n")
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'E42: a KEEP row for the quest the giver offered keeps a pin whose first quest is another'
    $root = New-World 'e42b' @('{"map":84,"icon":1,"x":20,"y":20,"quests":[101,102]}')
    Put-RawOwn $root @((G 'Creature:3704' 'Tom' 69933 '84 20.1 20.1 2' '102' ''))
    [IO.File]::WriteAllText("$root\decisions.csv", '"Quest","Map","X","Y","Decision","Reason"' + "`r`n" + '"101","84","20","20","KEEP","looked"' + "`r`n")
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'E42: and so does a row for the pin''s first quest'

    # ---------- E43: unnamed givers ----------
    $root = New-World 'e43' @('{"map":37,"icon":1,"x":50,"y":50,"quests":[102,103]}')
    Put-RawOwn $root @((G 'Creature:3702' '' 69933 '37 50.4 50.2 3' '102' ''), (G 'Creature:3703' '' 69933 '37 50.2 50.4 3' '103' ''))
    $run = Invoke-Tool $root
    Check ($run.Report -match 'two givers at one pin') 'E43: two givers of no name at one pin are two givers'

    # ---------- E44: which place a new pin gets ----------
    $root = New-World 'e44' @('{"map":37,"icon":1,"npc":3701,"name":"Guard Roberts","x":45.3,"y":67.8,"quests":[100]}')
    Put-RawOwn $root @(
        (G 'Creature:3707' 'Pinless Pete' 69933 '84 10.0 10.0 5;84 10.5 10.0 5;84 50.0 50.0 8' '103' ''),
        (G 'Creature:3708' 'Tie Tim' 69933 '84 40.0 40.0 3;84 20.0 20.0 3' '104' ''))
    $run = Invoke-Tool $root
    $pins = Get-Pins $root
    Equal (Format-PinNumber (Find-Pin $pins 103)[0].x) '10' 'E44: a place is as visited as its rows together (5 and 5 beat 8)'
    Equal (Format-PinNumber (Find-Pin $pins 104)[0].x) '20' 'E44: of two places seen as often the lower x is taken'

    # ---------- E45: exactly six givers are not more than six ----------
    $root = New-World 'e45' @('{"map":37,"icon":1,"npc":3701,"name":"Guard Roberts","x":45.3,"y":67.8,"quests":[100]}')
    Put-RawOwn $root @(1..6 | ForEach-Object { (G "Creature:39$_" "Seller $_" 69933 "84 $(10 * $_).0 $(10 * $_).0 3" '103' '') })
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 103).Count 6 'E45: six givers, six pins'
    Check ($run.Report -notmatch 'more than six places') 'E45: and nothing for review'

    # ---------- E46: the report names why a quest was held back ----------
    $root = New-World 'e46' @('{"map":37,"icon":1,"npc":3701,"name":"Guard Roberts","x":45.3,"y":67.8,"quests":[100]}')
    Add-WorldQuests $root @((Q 660 'Holiday q' 1 10 ',"holiday":2'), (Q 661 'Landfall q' 1 121), (Q 662 'Craft q' 1 10 ',"profession":185'), (Q 663 'Odd q' 64),
        (Q 664 'Weekly q' 128), (Q 665 'Daily q' 4), (Q 666 'Repeat q' 2), (Q 667 'Plain q' 1), (Q 668 'Zero q' 0))
    Put-RawOwn $root @(
        (G 'Creature:5001' 'G1' 69933 '84 10.0 10.0 1' '660' ''), (G 'Creature:5002' 'G2' 69933 '84 20.0 20.0 1' '661' ''),
        (G 'Creature:5003' 'G3' 69933 '84 30.0 30.0 1' '662' ''), (G 'Creature:5004' 'G4' 69933 '84 40.0 40.0 1' '663' ''),
        (G 'Creature:5005' 'G5' 69933 '84 50.0 50.0 1' '664,665,666,667,668' ''))
    $run = Invoke-Tool $root
    foreach ($plainQuest in 664, 665, 666, 667, 668) { Check (-not ($run.Report -match "add   quest ${plainQuest}:.*held back")) "E46: quest $plainQuest is of an ordinary type and is not held back" }
    Check ($run.Report -match 'add   quest 660:.*held back by the pipeline as: holiday') 'E46: a holiday quest is named as one'
    Check ($run.Report -match 'add   quest 661:.*held back by the pipeline as: Landfall') 'E46: a Landfall quest too'
    Check ($run.Report -match 'add   quest 662:.*held back by the pipeline as: profession') 'E46: a profession quest too'
    Check ($run.Report -match 'add   quest 663:.*held back by the pipeline as: quest type 64') 'E46: and a quest of type 64'
    # ===================== what the review of 9 October 2026 found =====================

    # ---------- F01: a file the reader cannot make sense of does not stop the sweep ----------
    $root = New-World 'f01'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' ''))
    New-Item -ItemType Directory -Path "$root\tools\recordings\players\p09" -Force | Out-Null
    [IO.File]::WriteAllText("$root\tools\recordings\players\p09\QuestCompletist.lua", "QCForeverProbeDB = {givers = {[`"Creature:1`"] = {kind = `"Creature`", id = 1, name = `"Bob`", build = `"1.60.1.99999999999`", spots = {[`"1438 0.00001 59.9`"] = 1}}}}`n")
    New-Item -ItemType Directory -Path "$root\tools\recordings\players\p08" -Force | Out-Null
    [IO.File]::WriteAllText("$root\tools\recordings\players\p08\QuestCompletist.lua", "qcQuestRecorder = {v = 1} -- x`rwhile true do end`n")
    $run = Invoke-Tool $root
    Equal $run.Exit 0 'F01: a file with a build no one could have, and one with code after a bare CR, do not stop the run'
    Check ($run.Report -match 'Not read: p09') 'F01: the first is named'
    Check ($run.Report -match 'Not read: p08') 'F01: and the second'
    Equal (Find-Pin (Get-Pins $root) 102)[0].npc 3702 'F01: and the good file is read all the same'

    # ---------- F02: a position that would print in exponent notation is read ----------
    $root = New-World 'f02'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 0.00001 50.2 3' '102' ''))
    $run = Invoke-Tool $root
    Equal $run.Exit 0 'F02: a position of 0.00001 does not stop the run'
    Check (@(Ledger-Rows $root | Where-Object { $_.Role -eq 'spot' -and $_.X -eq '0' }).Count -eq 1) 'F02: it is the place 0'

    # ---------- F03: names are compared exactly, so a lone player's spelling is never adopted ----------
    $root = New-World 'f03'
    Put-RawPlayer $root 'p01' @((G 'Creature:3702' 'STABLE MASTER GIL' 69933 '37 50.4 50.2 9' '102' ''))
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'F03: a lone player''s file fills nothing'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' ''))
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 102)[0].name 'Stable Master Gil' 'F03: when the maintainer''s file agrees, the pin gets the maintainer''s spelling'
    Equal (@(Ledger-Rows $root | Where-Object { $_.Role -eq 'giver' -and $_.Npc -eq '3702' }).Count) 2 'F03: and the two spellings are two ledger rows'
    Check (@(Ledger-Rows $root | Where-Object { $_.Role -eq 'giver' -and $_.Name -ceq 'STABLE MASTER GIL' -and $_.Src -eq 'p01=1' }).Count -eq 1) 'F03: the player''s stays theirs alone'

    # ---------- F04: a lone player's visits and place decide nothing ----------
    $root = New-World 'f04'
    Put-RawOwn $root @((G 'Creature:3707' 'Pinless Pete' 69933 '84 33.3 44.4 1' '103' ''))
    Put-RawPlayer $root 'p01' @((G 'Creature:3707' 'Pinless Pete' 69933 '84 34.7 44.4 999' '103' ''))
    $run = Invoke-Tool $root
    Equal (Format-PinNumber (Find-Pin (Get-Pins $root) 103)[0].x) '33.3' 'F04: a new pin is where the maintainer saw the giver, not where a lone player did, however often'
    $root = New-World 'f04b' @('{"map":37,"icon":1,"x":52.9,"y":50,"quests":[102]}')
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.0 50.0 1' '102' ''))
    Put-RawPlayer $root 'p01' @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 51.4 50.0 999' '102' ''))
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'F04: a lone player''s place does not bring a pin 2.9 points from the maintainer''s sighting within the radius'

    # ---------- F05: a giver with no trusted name still gets a pin for its quest, and the rest goes on ----------
    $root = New-World 'f05' @('{"map":37,"icon":1,"x":50,"y":50,"quests":[102]}')
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' ''))
    foreach ($tag in 'p01', 'p02') { Put-RawPlayer $root $tag @((G 'Creature:3707' '' 69933 '84 33.3 44.4 2' '103,104' '')) }
    $run = Invoke-Tool $root
    Equal $run.Exit 0 'F05: an unnamed giver does not stop the run'
    Equal (Find-Pin (Get-Pins $root) 102)[0].npc 3702 'F05: the fill goes through'
    $p103 = Find-Pin (Get-Pins $root) 103
    Equal $p103.Count 1 'F05: quest 103 gets a pin'
    Check ($p103[0].npc -eq $null -or [int]$p103[0].npc -eq 0) 'F05: with no NPC'
    Check ($null -eq $p103[0].name) 'F05: and no name'
    Equal (@($p103[0].quests) -join ',') '103,104' 'F05: both of the giver''s quests are on it'
    $text = Get-PinText $root
    $run2 = Invoke-Tool $root
    Equal (Get-PinText $root) $text 'F05: a second run changes nothing'
    foreach ($tag in 'p03', 'p04') { Put-RawPlayer $root $tag @((G 'Creature:3707' 'Pete' 69933 '84 33.3 44.4 2' '103,104' '')) }
    $run3 = Invoke-Tool $root
    $p103 = Find-Pin (Get-Pins $root) 103
    Equal $p103[0].npc 3707 'F05: once two players gave a name, a later run fills the pin'
    Equal $p103[0].name 'Pete' 'F05: with the name'

    # ---------- F06: a KEEP on any quest of a pin keeps the pin; a quest can be kept from getting a pin ----------
    $root = New-World 'f06' @('{"map":84,"icon":1,"x":60,"y":60,"quests":[111,112]}')
    Put-RawOwn $root @((G 'Creature:3703' 'Sam' 69933 '84 60.2 60.1 3' '111' ''), (G 'Creature:3707' 'Pinless Pete' 69933 '84 33.3 44.4 3' '103' ''))
    [IO.File]::WriteAllText("$root\decisions.csv", '"Quest","Map","X","Y","Decision","Reason"' + "`r`n" + '"112","84","60","60","KEEP","stays"' + "`r`n" + '"103","","","","KEEP","this quest gets no pin from here"' + "`r`n")
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 111)[0].npc) 'F06: a KEEP on the pin''s second quest keeps the pin as it is'
    Equal (Find-Pin (Get-Pins $root) 103).Count 0 'F06: a KEEP with only a quest keeps it from getting a pin'
    Check ($run.Report -match 'no pin: kept by a decision') 'F06: and the report counts it'
    [IO.File]::WriteAllText("$root\decisions.csv", '"Quest","Map","X","Y","Decision","Reason"' + "`r`n" + '"103","84","33.3","44.4","KEEP","not here"' + "`r`n")
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 103).Count 0 'F06: a KEEP at the place the pin would go keeps it from there too'

    # ---------- F07: a fill of an object's name does not make two pins of one name merge ----------
    $root = New-World 'f07' @('{"map":84,"icon":1,"name":"Notice Board","x":40,"y":40,"quests":[111]}', '{"map":84,"icon":1,"x":40.8,"y":40,"quests":[112]}')
    Put-RawOwn $root @((G 'GameObject:9001' 'Notice Board' 69933 '84 40.9 40.0 3' '112' ''))
    $run = Invoke-Tool $root
    Check ($null -eq (Find-Pin (Get-Pins $root) 112)[0].name) 'F07: the blank pin 0.8 points from a pin of that name is not named'
    Check ($run.Report -match 'a fill would merge two pins of one name') 'F07: and the report says why'
    $root = New-World 'f07b' @('{"map":84,"icon":1,"name":"Notice Board","x":40,"y":40,"quests":[111]}', '{"map":84,"icon":1,"x":40,"y":40,"quests":[112]}')
    Put-RawOwn $root @((G 'GameObject:9001' 'Notice Board' 69933 '84 40.1 40.0 3' '112' ''))
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 112)[0].name 'Notice Board' 'F07: on the same spot it is'

    # ---------- F08: copies of one character get one pin, and a pin of the name is joined ----------
    $root = New-World 'f08'
    Put-RawOwn $root @((G 'Creature:3707' 'Pinless Pete' 69933 '84 33.3 44.4 5' '103' ''), (G 'Creature:3799' 'Pinless Pete' 69933 '84 33.5 44.5 2' '103' ''))
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 103).Count 1 'F08: two givers of one name offering a quest at one place give it one pin'
    Equal (Find-Pin (Get-Pins $root) 103)[0].npc 3707 'F08: the more seen'
    Check ($run.Report -match 'same name under another ID') 'F08: and the other is named in the report'
    $root = New-World 'f08b' @('{"map":84,"icon":1,"name":"Pinless Pete","x":33,"y":44,"quests":[100]}')
    Put-RawOwn $root @((G 'Creature:3707' 'Pinless Pete' 69933 '84 33.3 44.4 5' '103' ''))
    $run = Invoke-Tool $root
    Equal (@(Get-Pins $root).Count) 1 'F08: a creature''s quest joins the pin that bears its name and has no NPC'
    Equal (@((Get-Pins $root)[0].quests) -join ',') '100,103' 'F08: and goes on it'

    # ---------- F09: a giver 1.5 to 3 points from a pin is listed ----------
    $root = New-World 'f09'
    Put-RawOwn $root @((G 'Creature:3802' 'Near Fan' 69933 '37 51.8 50.0 2' '102' ''))
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'F09: it does not fill the pin'
    Equal (Review-Count $run.Report 'giver stood 1.5 to 3 points from a pin') 1 'F09: but the report says it stood near'

    # ---------- F10: the icon of a new pin follows all its quests ----------
    $root = New-World 'f10'
    Add-WorldQuests $root @((Q 134 'Cook A' 1 10 ',"profession":185'), (Q 135 'Plain B'), (Q 136 'Plain C'), (Q 137 'Cook D' 1 10 ',"profession":185'), (Q 138 'Cook E' 1 10 ',"profession":185'))
    Put-RawOwn $root @((G 'Creature:3711' 'Mixed Mike' 69933 '84 55.5 15.5 5' '134,135,136' ''), (G 'Creature:3712' 'Cook Cass' 69933 '84 75.5 75.5 5' '137,138' ''))
    $run = Invoke-Tool $root
    Equal (Find-Pin (Get-Pins $root) 134)[0].icon 1 'F10: a pin with one profession quest and two plain ones has the plain icon, though its lowest quest is a profession one'
    Equal (Find-Pin (Get-Pins $root) 137)[0].icon 3 'F10: a pin of profession quests only has the profession icon'

    # ---------- F11: a giver that offers and takes in a quest, seen in two places ----------
    $root = New-World 'f11'
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3;84 20.0 20.0 3' '102' '102'))
    $run = Invoke-Tool $root
    Check (-not (Find-Pin (Get-Pins $root) 102)[0].npc) 'F11: the pin is not filled when the ledger cannot tell the offer from the hand-in'
    Equal (Review-Count $run.Report 'offered and taken in at different places') 1 'F11: and the report says so'

    # ---------- F12: trusted sources that disagree on a name leave a giver without one ----------
    $root = New-World 'f12'
    Put-RawOwn $root @((G 'Creature:3707' 'Pete' 69933 '84 33.3 44.4 5' '103' ''))
    foreach ($tag in 'p01', 'p02') { Put-RawPlayer $root $tag @((G 'Creature:3707' 'Peter' 69933 '84 33.3 44.4 1' '103' '')) }
    $run = Invoke-Tool $root
    Check ($run.Report -match '1 givers whose trusted sources give more than one name') 'F12: the report counts the givers whose names disagree'
    Check ($run.Report -match 'Creature:3707: Pete / Peter') 'F12: and names both'
    $p = Find-Pin (Get-Pins $root) 103
    Equal $p.Count 1 'F12: the quest still gets a pin'
    Check (-not [int]$p[0].npc -and $null -eq $p[0].name) 'F12: with no name and no NPC'

    # ---------- F13: the ledger is the same on every save ----------
    $ledger = New-LedgerTable
    foreach ($kind in 2, 1, 3) {
        $row = New-RecordedRow 'retail' 'start'; $row.Quest = '800'; $row.Map = '84'; $row.X = '45.3'; $row.Y = '67.8'; $row.Item = '5555'; $row.StartKind = "$kind"
        $row.Src = 'own-retail=1'; $row.FirstBuild = '1'; $row.LastBuild = '1'
        $ledger[(Get-RecordedKey $row)] = $row
    }
    foreach ($name in 'gil', 'Gil', 'GIL') {
        $row = New-RecordedRow 'retail' 'giver'; $row.Kind = 'Creature'; $row.Npc = '3702'; $row.Name = $name; $row.Src = 'own-retail=1'; $row.FirstBuild = '1'; $row.LastBuild = '1'
        $ledger[(Get-RecordedKey $row)] = $row
    }
    $file = Join-Path $Scratch 'order.csv'
    $null = Save-RecordedLedger $ledger $file
    $first = [IO.File]::ReadAllBytes($file)
    $same = $true
    for ($cycle = 0; $cycle -lt 4; $cycle++) {
        $again = Read-RecordedLedger $file
        $null = Save-RecordedLedger $again $file
        if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$first, [byte[]][IO.File]::ReadAllBytes($file))) { $same = $false }
    }
    Check $same 'F13: rows that tie on every column but one are in the same order after four saves and reads'
    Check (@($again.Values | Where-Object { $_.Role -eq 'giver' }).Count -eq 3) 'F13: names that differ in case only are three rows'
    $kinds = @($again.Values | Where-Object { $_.Role -eq 'start' } | ForEach-Object { $_.StartKind })
    Equal ($kinds -join ',') '1,2,3' 'F13: start rows go by kind'

    # ---------- F14: a ledger edited by hand ----------
    $file = Join-Path $Scratch 'hand.csv'
    $header = '"Game","Role","Kind","Npc","Name","Map","X","Y","Quest","Item","StartKind","FirstBuild","LastBuild","Src"'
    [IO.File]::WriteAllText($file, $header + "`r`n" + '"retail","offer","Creature","3702","","","","","102","","","1","5","own-retail=1"' + "`r`n" + '"retail","offer","Creature","3702","","","","","102","","","1","9","p01=2;p02=1"' + "`r`n")
    $merged = Read-RecordedLedger $file 3>$null
    Equal $merged.Count 1 'F14: a repeated row is one row'
    Equal (@($merged.Values)[0].Src) 'own-retail=1;p01=2;p02=1' 'F14: with the sources of both'
    Equal (@($merged.Values)[0].LastBuild) '9' 'F14: and the later build'
    [IO.File]::WriteAllText($file, $header + "`r`n" + '"retail","offer","Creature","3702","","","","","102","","","1","5","own-retail=abc"' + "`r`n")
    $message = ''
    try { $null = Read-RecordedLedger $file } catch { $message = $_.Exception.Message }
    Check ($message -match 'line 2') 'F14: a row that cannot be read is named by its line'
    [IO.File]::WriteAllText($file, $header + "`r`n" + '"retail","nonsense","Creature","3702","","","","","102","","","1","5","own-retail=1"' + "`r`n")
    $message = ''
    try { $null = Read-RecordedLedger $file } catch { $message = $_.Exception.Message }
    Check ($message -match 'line 2') 'F14: so is a row of a role no one knows'

    # ---------- F15: the lists say who gave what, and Forever has them too ----------
    $root = New-World 'f15'
    Add-WorldQuests $root @((Q 620 'Unplaced' 1 0))
    Put-RawOwn $root @((G 'Creature:3701' 'Guard Roberts' 69933 '37 45.3 67.8 2' '100' '')) `
        @('[100] = "69933|1|107|3|40|1|Elwynn"', '[620] = "69933|1|16|1|1|1|Duskwood"')
    Put-RawPlayer $root 'p01' @((G 'Creature:3701' 'Guard Roberts' 69933 '37 45.3 67.8 2' '100' '')) @('[100] = "69933|1|47|3|40|1|"')
    $run = Invoke-Tool $root
    $types = @(Import-Csv "$root\tools\recorded_quest_types.csv")
    Check ($types.Count -ge 1 -and $types[0].Game -eq 'retail') 'F15: the type list has a Game column'
    Check ($types[0].Sources -match 'own-retail' -and $types[0].Trust -eq 'trusted') 'F15: and the sources, and whether they are enough'
    $heads = @(Import-Csv "$root\tools\recorded_headings.csv")
    Check ($heads.Count -eq 1 -and $heads[0].Trust -eq 'trusted' -and $heads[0].Headings -eq 'Duskwood') 'F15: the heading list has a trust column'

    # ---------- F16: the report counts the quests given a pin by class, QuestV2 included ----------
    $root = New-World 'f16'
    [IO.File]::WriteAllText("$root\tools\QuestV2.csv", "ID,Name`r`n100,x`r`n101,x`r`n102,x`r`n104,x`r`n")
    Put-RawOwn $root @((G 'Creature:3707' 'Pinless Pete' 69933 '84 33.3 44.4 5' '103,104' ''))
    $run = Invoke-Tool $root
    Check ($run.Report -match 'by what the TrinityCore pass would have held them for') 'F16: the report sums the classes'
    Check ($run.Report -match 'not in QuestV2 1') 'F16: a quest the client does not list is one of them'
    Check ($run.Report -match 'quest type 64 1') 'F16: so is a seasonal type'
    Check ($run.Report -match '2 quests in all') 'F16: with the number of quests'

    # ---------- F17: forgetting lasts one run ----------
    $root = New-World 'f17'
    $giver = (G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' '')
    Put-RawPlayer $root 'p01' @($giver)
    Put-RawPlayer $root 'p02' @($giver)
    $null = Invoke-Tool $root
    $run = Invoke-Tool $root @('-ForgetTag', 'P02')
    Check (@(Ledger-Rows $root | Where-Object { $_.Src -match 'p02' }).Count -eq 0) 'F17: -ForgetTag takes the source out, whatever its case'
    $run = Invoke-Tool $root
    Check (@(Ledger-Rows $root | Where-Object { $_.Src -match 'p02' }).Count -gt 0) 'F17: and the next plain run reads the file again'

    # ---------- F18: a change that would move a pin saves nothing, end to end ----------
    $mutant = Join-Path $Scratch 'mutant'
    New-Item -ItemType Directory -Path $mutant -Force | Out-Null
    foreach ($name in 'Import-RecordedGivers.ps1', 'RecordedGivers.ps1', 'AddonData.ps1', 'Read-RecordedGivers.lua') { Copy-Item (Join-Path $PSScriptRoot $name) $mutant }
    $text = [IO.File]::ReadAllText("$mutant\RecordedGivers.ps1")
    $needle = "if (`$fill.Npc) { Set-RecordField `$pin 'npc' `$fill.Npc; `$done.Filled++ }"
    Check ($text.Contains($needle)) 'F18: the line the mutation changes is there'
    [IO.File]::WriteAllText("$mutant\RecordedGivers.ps1", $text.Replace($needle, $needle + "; Set-RecordField `$pin 'x' ([decimal]`$pin.x + 1)"))
    $root = New-World 'f18' @('{"map":37,"icon":1,"x":50,"y":50,"quests":[102]}', '{"map":84,"icon":1,"x":10,"y":10,"quests":[116]}')
    Put-RawOwn $root @((G 'Creature:3702' 'Stable Master Gil' 69933 '37 50.4 50.2 3' '102' ''))
    $before = Get-PinText $root
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$mutant\Import-RecordedGivers.ps1", '-ToolsDir', "$root\tools", '-DataDir', "$root\data", '-AddonDir', "$root\addon",
        '-LedgerFile', "$root\ledger.csv", '-DecisionsFile', "$root\decisions.csv", '-ReportFile', "$root\report.txt", '-LuaExe', $LuaExe)
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = @(& powershell @arguments 2>&1) } finally { $ErrorActionPreference = $saved }
    Check ($LASTEXITCODE -ne 0) 'F18: the run stops'
    Check (($output -join ' ') -match 'No pin was saved') 'F18: saying that no pin was saved'
    Check (($output -join ' ') -match 'moved') 'F18: and what moved'
    Equal (Get-PinText $root) $before 'F18: and the pins are as they were'
    Check (Test-Path "$root\report.txt") 'F18: the report is written all the same'
    Check (Test-Path "$root\ledger.csv") 'F18: and so is the ledger'

    # ---------- G1: a file over 8 MB is read when it is the maintainer's own, and refused when a player's ----------
    $big = New-Object System.Text.StringBuilder
    [void]$big.AppendLine('QCForeverProbeDB = {')
    [void]$big.AppendLine('["givers"] = {["Creature:3702"] = {["kind"] = "Creature", ["id"] = 3702, ["name"] = "Test Giver", ["build"] = "1.60.1.70338"}},')
    [void]$big.AppendLine('["quests"] = {')
    foreach ($i in 1..140000) { [void]$big.AppendLine("[$i] = {[""build""] = ""1.60.1.70338"", [""result""] = ""fail"", [""ms""] = 100},") }
    [void]$big.AppendLine('},')
    [void]$big.AppendLine('}')
    $bigText = $big.ToString()
    Check ($bigText.Length -gt 8MB) 'G1: the file is over 8 MB'
    $root = New-World 'g1own'
    New-Item -ItemType Directory -Path "$root\tools\forever_probe_70000" -Force | Out-Null
    [IO.File]::WriteAllText("$root\tools\forever_probe_70000\QCForeverProbe.lua", $bigText)
    $run = Invoke-Tool $root
    Check ($run.Report -match 'Read own-forever_probe_70000: forever, probe') "G1: the maintainer's probe file over 8 MB is read ($($run.Report.Substring(0, [Math]::Min(300, $run.Report.Length))))"
    Check ($run.Report -notmatch 'Not read: own-forever_probe_70000') 'G1: and not reported as refused'
    $root = New-World 'g1player'
    New-Item -ItemType Directory -Path "$root\tools\recordings\players\p10" -Force | Out-Null
    [IO.File]::WriteAllText("$root\tools\recordings\players\p10\QuestCompletist.lua", $bigText)
    $run = Invoke-Tool $root
    Check ($run.Report -match 'Not read: p10 .*larger than 8 MB') 'G1: the same file from a player is refused, at 8 MB'
}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
