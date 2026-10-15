<#
Checks the pin rules both games share (PinRules.ps1) and how retail's pin tools follow them, on a small world made in
a scratch folder: nothing in the checkout is written and nothing is downloaded. The rules themselves come first; then
the pipeline (Parse-ExistingPinDB.ps1 and Assemble-PinDB.ps1 -Apply) builds the world's pins from its locations: three
quests at one spot with no giver share one nameless pin, a pin's icon comes from its quests when they bring different
ones, and the spot is 1.5 map points, no more. Then a giver turns up for one quest of a spot, from the client's giver
table (Apply-ClientQuestGivers.ps1) and from the recorder (Import-RecordedGivers.ps1): the quest moves to a pin of
its giver, the other two stay together on the nameless pin, which nobody renames, and a rebuild keeps it so.
Test-ForeverImport.ps1 checks the same on WoW: Forever's importer.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-PinRules.ps1

-Tools names another folder of the pin tools to run the same checks on (master's, to see which fail there); -Keep
leaves the scratch folder where it is and says where.

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param(
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [string]$Tools = $PSScriptRoot,
    [switch]$Keep
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\PinRules.ps1"
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

# ---------- R: the rules ----------
Equal $PinSameSpot 1.5 'R1: one spot is 1.5 map points'
$groups = New-PinGroups
$first = Add-PinGroup $groups 37 '' 10 10 'first'
Equal (Find-PinGroup $groups 37 '' 11.5 10) 'first' 'R2: a row exactly 1.5 points from a pin''s first row joins it'
Equal (Find-PinGroup $groups 37 '' 11.51 10) $null 'R2: 1.51 points away it does not'
Equal (Find-PinGroup $groups 37 'npc:5' 10 10) $null 'R2: nor does a row of a giver, on the pin of nobody'
Equal (Find-PinGroup $groups 84 '' 10 10) $null 'R2: nor one on another map'
$null = Add-PinGroup $groups 37 '' 12 10 'second'
Equal (Find-PinGroup $groups 37 '' 11.2 10) 'second' 'R3: a row within reach of two pins joins the nearer'
Equal (Get-PinGiverKey '7001' 'Spot Giver') 'npc:7001' 'R4: a row is grouped by its NPC ID'
Equal (Get-PinGiverKey '0' 'Old Name') 'name:Old Name' 'R4: else by its name'
Equal (Get-PinGiverKey '0' '') '' 'R4: else by nothing but its spot'
$who = Select-PinIdentity ([ordered]@{ neighbour = 'near'; emulator = 'tc'; pin = $null })
Equal "$($who.Source)=$($who.Value)" 'emulator=tc' 'R5: the first source in $PinIdentityOrder that has someone wins, whatever order they are given in'
$asked = $false
$who = Select-PinIdentity ([ordered]@{ pin = 'carried'; neighbour = { $script:asked = $true; 'near' } })
Check ($who.Source -eq 'pin' -and -not $asked) 'R5: a slow source is not asked when one before it answers'
Equal (Select-PinIdentity ([ordered]@{ emulator = $null })).Source 'none' 'R5: with no answer the pin names nobody'
$threw = $false; try { $null = Select-PinIdentity @{ guess = 'x' } } catch { $threw = $true }
Check $threw 'R5: a source the order lacks is refused'
$seasonal = [pscustomobject]@{ type = 64; class = 8191 }; $profession = [pscustomobject]@{ type = 1; profession = 4; class = 8191 }
$classOnly = [pscustomobject]@{ type = 1; class = 8 }; $plain = [pscustomobject]@{ type = 1; class = 8191 }
Equal (Get-PinQuestIcon @($seasonal, $seasonal)) 5 'R6: every quest seasonal: the seasonal icon'
Equal (Get-PinQuestIcon @($profession, $profession)) 3 'R6: every quest a profession''s: the profession icon'
Equal (Get-PinQuestIcon @($classOnly)) 9 'R6: every quest for some classes: the class icon'
Equal (Get-PinQuestIcon @($seasonal, $profession)) 1 'R6: quests of different kinds: the normal icon'
function Show-Split($split) { return "fill $($split.Fill); moves $((@($split.Moves.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value -join ',')" })) -join ' '); disputed $($split.Disputed -join ',')" }
$claims = [ordered]@{}; $claims.Add(7002, @(2))
Equal (Show-Split (Split-NamelessPin @(1, 2, 3) $claims)) 'fill ; moves 7002=2; disputed ' 'R7: a giver of one quest of three takes that quest, and the pin names nobody'
$claims = [ordered]@{}; $claims.Add(7004, @(1, 2))
Equal (Show-Split (Split-NamelessPin @(1, 2) $claims)) 'fill 7004; moves ; disputed ' 'R7: a giver of every quest on the pin takes the pin'
$claims = [ordered]@{}; $claims.Add(7005, @(1, 2)); $claims.Add(7006, @(2, 9))
Equal (Show-Split (Split-NamelessPin @(1, 2) $claims)) 'fill ; moves 7005=1; disputed 2' 'R7: a quest two givers claim stays, the rest move, and a quest not on the pin is no claim'
$claims = [ordered]@{}; $claims.Add('Creature:1', @(1)); $claims.Add('GameObject:2', @(2))
Equal (Show-Split (Split-NamelessPin @(1, 2) $claims)) 'fill ; moves Creature:1=1 GameObject:2=2; disputed ' 'R7: two givers with a quest each both move, in the order given'

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("pin-rules-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null

# ---------- The scratch world ----------
# Map 37 covers world -1000 to 1000 on both axes: map x = (1000 - world y) / 20, map y = (1000 - world x) / 20.
function Get-World([double]$x, [double]$y) { return @{ X = 1000 - 20 * $y; Y = 1000 - 20 * $x } }

function Add-Quest($list, [int]$id, [int]$type = 1, [int]$profession = 0) {
    $q = '{"id":' + $id + ',"name":"Quest ' + $id + '","level":10,"zone":"","category":10,"type":' + $type + ',"faction":2,"race":67108863,"class":8191'
    if ($profession) { $q += ',"profession":' + $profession }
    $list.Add($q + '}')
}

function New-World([string]$name) {
    $root = Join-Path $Scratch $name
    foreach ($dir in 'tools', 'tools\recordings\own\retail', 'data', 'addon') { New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null }
    $t = "$root\tools"
    [IO.File]::WriteAllText("$t\UiMap.csv", "Name_lang,ID,ParentUiMapID,Flags,System,Type`r`nElwynn,37,0,0,0,3`r`n")
    [IO.File]::WriteAllText("$t\UiMap-1.60.1.70205.csv", "Name_lang,ID,ParentUiMapID,Flags,System,Type`r`nTeldrassil,1438,0,0,0,3`r`n")
    [IO.File]::WriteAllText("$t\UiMapAssignment.csv", "UiMapID,MapID,Region_0,Region_1,Region_3,Region_4,UiMin_0,UiMin_1,UiMax_0,UiMax_1`r`n37,0,-1000,-1000,1000,1000,0,0,1,1`r`n")
    [IO.File]::WriteAllText("$t\QuestV2CliTask.csv", "ID,QuestInfoID`r`n")
    [IO.File]::WriteAllText("$t\QuestInfo.csv", "ID,InfoName_lang,Type,Modifiers,Profession`r`n0,None,0,0,0`r`n")
    $quests = New-Object System.Collections.Generic.List[string]
    foreach ($id in 1001..1006 + 1011..1016) { Add-Quest $quests $id }
    Add-Quest $quests 1007 64
    Add-Quest $quests 1008 1 4
    Add-Quest $quests 1009 1 4
    Add-Quest $quests 1010 1 4
    [IO.File]::WriteAllText("$root\data\quests.jsonl", (($quests | Sort-Object { [int]($_ -replace '^\{"id":(\d+).*$', '$1') }) -join "`n") + "`n")
    # The pins before the first run: Spot Giver's, and nameless pins of 1007 (seasonal) and 1009 (drawn as normal).
    [IO.File]::WriteAllText("$root\data\pins.jsonl", ((@(
        '{"map":37,"icon":1,"npc":7001,"name":"Spot Giver","x":10,"y":10,"quests":[1016]}'
        '{"map":37,"icon":5,"x":20,"y":20,"quests":[1007]}'
        '{"map":37,"icon":1,"x":25,"y":25,"quests":[1009]}'
    ) -join "`n") + "`n"))
    # Where the quests start, as Build-QuestLocationData.ps1 writes it: three quests at one spot (1001 to 1003), a spot
    # of two with one giver (1014, 1015), another three (1011 to 1013), the 1.5-point edge (1004 to 1006), two spots
    # whose quests bring different icons (1007 and 1008, 1009 and 1010), and Spot Giver's quest.
    $rows = @(
        @(1001, 40, 40), @(1002, 40.5, 40.3), @(1003, 39.6, 40.8),
        @(1014, 80, 80), @(1015, 80.4, 79.8),
        @(1011, 70, 70), @(1012, 70.5, 70.4), @(1013, 69.7, 70.6),
        @(1004, 60, 60), @(1005, 61.5, 60), @(1006, 60, 61.51),
        @(1007, 20.2, 20.1), @(1008, 20.5, 20.4), @(1009, 25.1, 25), @(1010, 25.4, 25.3),
        @(1016, 10.3, 10.2))
    $rows | ForEach-Object { [pscustomobject][ordered]@{ QuestID = $_[0]; UiMapID = 37; MapX = $_[1]; MapY = $_[2]; NumPointsUsed = 1; ObjectiveIndex = 32
        InOurDB = 'True'; OurQuestName = "Quest $($_[0])"; OurZoneName = ''; Source = 'client'; StarterNpcIds = ''; StarterNames = ''; GiverNpcId = ''; GiverName = '' } } |
        Export-Csv "$t\quest_locations.csv" -NoTypeInformation -Encoding UTF8
    [IO.File]::WriteAllText("$root\addon\qcUnavailableQuests.lua", "qcUnavailableQuests = {`r`n}`r`n")
    [IO.File]::WriteAllText("$root\addon\QuestCompletist.toc", "## Interface: 120100, 120105`r`n")
    [IO.File]::WriteAllText("$root\addon\QuestCompletist_Camelot.toc", "## Interface: 16001`r`n")
    $null = Invoke-AddonDataBuild -DataDir "$root\data" -AddonDir "$root\addon"
    return $root
}

# The client's giver table names Yotnar Test (7002) for 1002 and Pair Giver (7004) for 1014 and 1015, standing at
# their starts; TrinityCore names them too, as starters of those quests.
function Write-Givers([string]$root) {
    $yotnar = Get-World 40.5 40.3; $pair = Get-World 80.2 80.1
    [IO.File]::WriteAllText("$root\tools\CollectableSourceQuestSparse.csv", "ID,QuestID,QuestGiverCreatureID,QuestMapID,QuestPosition_0,QuestPosition_1`r`n" +
        "1,1002,7002,0,$($yotnar.X),$($yotnar.Y)`r`n2,1014,7004,0,$($pair.X),$($pair.Y)`r`n3,1015,7004,0,$($pair.X),$($pair.Y)`r`n")
    [IO.File]::WriteAllText("$root\tools\dump.sql", (@(
        "INSERT INTO ``creature_template`` VALUES (7002,0,0,'Yotnar Test'),(7004,0,0,'Pair Giver');"
        'INSERT INTO `creature_queststarter` VALUES (7002,1002),(7004,1014),(7004,1015);'
        "INSERT INTO ``creature`` VALUES (1,7002,0,0,0,0,0,0,0,0,0,0,$($yotnar.X),$($yotnar.Y)),(2,7004,0,0,0,0,0,0,0,0,0,0,$($pair.X),$($pair.Y));"
    ) -join "`n") + "`n")
}

# The recorder's own retail file: Recorded Giver (7003) stood by the start of 1012 and offered it.
function Write-Recording([string]$root) {
    [IO.File]::WriteAllText("$root\tools\recordings\own\retail\QuestCompletist.lua", (@(
        'qcQuestRecorder = {'
        '["v"] = 1,'
        '["seq"] = 10,'
        '["bv"] = { [70391] = "12.1.5" },'
        '["g"] = {'
        '["Creature:7003"] = "Recorded Giver|70391|1|37 70.3 70.2 3|1012||0",'
        '},'
        '["q"] = {'
        '[1012] = "70391|1|32|1|8|1024|",'
        '},'
        '["s"] = {'
        '},'
        '}'
    ) -join "`r`n") + "`r`n")
}

function Run-Script([string]$script, [string[]]$arguments) {
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $script @arguments 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $saved }
    return @{ Text = ($output -join "`n"); Exit = $LASTEXITCODE }
}
function Invoke-Pipeline([string]$root) {
    $r = Run-Script "$Tools\Parse-ExistingPinDB.ps1" @('-ToolsDir', "$root\tools", '-DataDir', "$root\data")
    if ($r.Exit -ne 0) { return $r }
    return Run-Script "$Tools\Assemble-PinDB.ps1" @('-Apply', '-ToolsDir', "$root\tools", '-DataDir', "$root\data", '-AddonDir', "$root\addon")
}
function Invoke-ClientGivers([string]$root) {
    return Run-Script "$Tools\Apply-ClientQuestGivers.ps1" @('-ToolsDir', "$root\tools", '-DataDir', "$root\data", '-AddonDir', "$root\addon", '-Build', '12.1.5.70391',
        '-TdbFile', "$root\tools\dump.sql", '-LuaExe', $LuaExe, '-ReportFile', "$root\client-giver-report.txt", '-DecisionsFile', "$root\no-decisions.csv")
}
function Invoke-Recorder([string]$root) {
    return Run-Script "$Tools\Import-RecordedGivers.ps1" @('-ToolsDir', "$root\tools", '-DataDir', "$root\data", '-AddonDir', "$root\addon", '-LedgerFile', "$root\ledger.csv",
        '-DecisionsFile', "$root\no-decisions.csv", '-GiverDecisionsFile', "$root\no-decisions.csv", '-NpcIdDecisionsFile', "$root\no-decisions.csv",
        '-ReportFile', "$root\recorded-giver-report.txt", '-ForeverBuild', '1.60.1.70205', '-LuaExe', $LuaExe)
}
function Get-Pins([string]$root) { return , @(Read-PinData "$root\data") }
function Pins-Of($pins, [int]$quest) { return , @($pins | Where-Object { @($_.quests) -contains $quest }) }
function Describe($pin) {
    $who = if ($pin.npc) { "$($pin.npc) $($pin.name)" } elseif ($null -ne $pin.name) { $pin.name } else { 'nobody' }
    return "$who at $(([decimal]$pin.x).ToString('0.##', $script:Invariant)),$(([decimal]$pin.y).ToString('0.##', $script:Invariant)) icon $($pin.icon): $(@($pin.quests) -join ',')"
}
function Describe-Quest($pins, [int]$quest) { return ((Pins-Of $pins $quest | ForEach-Object { Describe $_ }) -join '; ') }

try {
    # ---------- A: the pipeline, one pin per spot ----------
    $w = New-World 'world'
    $r = Invoke-Pipeline $w
    Equal $r.Exit 0 "A1: the pipeline runs ($($r.Text))"
    $pins = Get-Pins $w
    Equal (Describe-Quest $pins 1001) 'nobody at 40,40 icon 1: 1001,1002,1003' 'A2: three quests that start at one spot with no giver share one nameless pin, at the first one''s start'
    Equal (Describe-Quest $pins 1004) 'nobody at 60,60 icon 1: 1004,1005' 'A3: a start exactly 1.5 points from a nameless pin joins it'
    Equal (Describe-Quest $pins 1006) 'nobody at 60,61.51 icon 1: 1006' 'A3: 1.51 points away it gets a pin of its own'
    Equal (Describe-Quest $pins 1007) 'nobody at 20,20 icon 1: 1007,1008' 'A4: a seasonal quest''s pin (icon 5) and a profession quest at one spot: the normal icon, from the quests, at the old pin''s place'
    Equal (Describe-Quest $pins 1009) 'nobody at 25,25 icon 3: 1009,1010' 'A4: two profession quests, one drawn as normal: the profession icon'
    Equal (Describe-Quest $pins 1016) '7001 Spot Giver at 10,10 icon 1: 1016' 'A5: a giver''s pin is as it was'
    $r = Invoke-Pipeline $w
    $first = [IO.File]::ReadAllText("$w\data\pins.jsonl")
    $r = Invoke-Pipeline $w
    Equal ([IO.File]::ReadAllText("$w\data\pins.jsonl")) $first 'A6: a rebuild writes the pins byte for byte as they were'

    # ---------- B: the client's giver table names the giver of one quest of a spot ----------
    Write-Givers $w
    $r = Invoke-ClientGivers $w
    Equal $r.Exit 0 "B1: Apply-ClientQuestGivers.ps1 runs ($($r.Text))"
    $pins = Get-Pins $w
    Equal (Describe-Quest $pins 1002) '7002 Yotnar Test at 40,40 icon 1: 1002' 'B2: the quest the client names a giver for moves to a pin of that giver, at the spot''s place'
    Equal (Describe-Quest $pins 1001) 'nobody at 40,40 icon 1: 1001,1003' 'B3: the other two stay together on the nameless pin, and nobody renames it'
    Equal (Describe-Quest $pins 1014) '7004 Pair Giver at 80,80 icon 1: 1014,1015' 'B4: a nameless pin whose every quest has one giver takes it'
    $report = if (Test-Path "$w\client-giver-report.txt") { [IO.File]::ReadAllText("$w\client-giver-report.txt") } else { '' }
    Check ($report -match '1 times a nameless pin gives quests to their giver''s pin' -and $report -match '1 pins with no NPC ID take the client''s giver') "B5: the report lists the move and the fill ($report)"
    $before = [IO.File]::ReadAllText("$w\data\pins.jsonl")
    $r = Invoke-ClientGivers $w
    Equal ([IO.File]::ReadAllText("$w\data\pins.jsonl")) $before 'B6: a second run changes nothing'
    $r = Invoke-Pipeline $w
    Equal $r.Exit 0 "B7: the pipeline runs after it ($($r.Text))"
    $pins = Get-Pins $w
    Equal ((Describe-Quest $pins 1002) + ' | ' + (Describe-Quest $pins 1001)) '7002 Yotnar Test at 40,40 icon 1: 1002 | nobody at 40,40 icon 1: 1001,1003' 'B7: and a rebuild keeps the quest on its giver''s pin and the other two on the nameless one'

    # ---------- C: the recorder saw the giver of one quest of a spot ----------
    Write-Recording $w
    $r = Invoke-Recorder $w
    Equal $r.Exit 0 "C1: Import-RecordedGivers.ps1 runs ($($r.Text))"
    $pins = Get-Pins $w
    Equal (Describe-Quest $pins 1012) '7003 Recorded Giver at 70,70 icon 1: 1012' 'C2: the quest the recorder saw offered moves to a pin of its giver, at the spot''s place'
    Equal (Describe-Quest $pins 1011) 'nobody at 70,70 icon 1: 1011,1013' 'C3: the other two stay together on the nameless pin, and nobody renames it'
    $report = if (Test-Path "$w\recorded-giver-report.txt") { [IO.File]::ReadAllText("$w\recorded-giver-report.txt") } else { '' }
    Check ($report -match '1 quests move from a nameless pin to their giver''s' -and $report -match "  move  map 37 at 70,70: quests 1012 to Creature:7003 'Recorded Giver'") "C4: the report lists the move ($report)"
    $before = [IO.File]::ReadAllText("$w\data\pins.jsonl")
    $r = Invoke-Recorder $w
    Equal ([IO.File]::ReadAllText("$w\data\pins.jsonl")) $before 'C5: a second run changes nothing'
    $r = Invoke-Pipeline $w
    Equal $r.Exit 0 "C6: the pipeline runs after it ($($r.Text))"
    $pins = Get-Pins $w
    Equal ((Describe-Quest $pins 1012) + ' | ' + (Describe-Quest $pins 1011)) '7003 Recorded Giver at 70,70 icon 1: 1012 | nobody at 70,70 icon 1: 1011,1013' 'C6: and a rebuild keeps them so'
    $rebuilt = [IO.File]::ReadAllText("$w\data\pins.jsonl")
    $r = Invoke-Pipeline $w
    Equal ([IO.File]::ReadAllText("$w\data\pins.jsonl")) $rebuilt 'C7: a second rebuild writes the pins byte for byte as the first'
}
finally {
    if ($Keep) { Write-Output "Scratch kept: $Scratch" } else { Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
