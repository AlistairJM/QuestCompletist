<#
Checks Read-QuestCache.ps1 on quest caches made here, in a scratch folder: nothing in the checkout is
written and nothing is downloaded. The caches are built record by record in both games' layouts, from
a field table typed in below rather than read from the reader, so a slipped field number in the reader
shows. It checks every field of a line, the lists a record walks past (reward spells, objectives with
and without visual effects, treasure pickers, conditional texts, house rewards), the races of both
games (the high word, the neutral side, a race one game counts and the other doesn't), the reputation
amounts, how the output is named and ordered, and every way a cache is refused: a record that
is a byte too long or short, a cache of the other game's layout, the wrong build, a file that is no
quest cache.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-QuestCache.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
$Tool = Join-Path $PSScriptRoot 'Read-QuestCache.ps1'
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
function Lacks([string]$text, [string]$part, [string]$message) {
    Check (-not $text.Contains($part)) "$message ('$part' is in: $text)"
}

function Invoke-WebRequest { throw 'A download was tried.' }

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("quest-cache-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false

$Games = @{
    forever = @{ Version = '1.60.1.70205'; Build = 70205; Fixed = 122; Spells = 16; Objectives = 109; Treasure = 112, 113; Conditional = 118, 119; House = 120, 121
        Level = 2; MinLevel = 4; Sort = 6; Info = 7; Group = 8; Next = 9; StartItem = 24; Flags = 25; FlagsEx = 26; QuestType = 1; Giver = 117; Rep = 75; Races = 110 }
    retail  = @{ Version = '12.1.0.69933'; Build = 69933; Fixed = 120; Spells = 14; Objectives = 107; Treasure = 110, 111; Conditional = 116, 117; House = 118, 119
        Tuning = 3; Sort = 4; Info = 5; Group = 6; Next = 7; StartItem = 22; Flags = 23; FlagsEx = 24; QuestType = 1; Giver = 115; Rep = 73; Races = 108 }
}

function Put([System.Collections.Generic.List[byte]]$list, [long]$value) {
    $list.AddRange([BitConverter]::GetBytes([uint32]($value -band 0xFFFFFFFFL)))
}

function New-Payload([hashtable]$Layout, [hashtable]$q) {
    $fixed = New-Object 'long[]' $Layout.Fixed
    $fixed[0] = $q.Id
    $fixed[1] = 2
    $fixed[$Layout.Races] = 0xFFFFFFFFL
    $fixed[$Layout.Races + 1] = 0xFFFFFFFFL
    foreach ($name in @($q.Set.Keys)) {
        if ($name -eq 'RacesLow') { $fixed[$Layout.Races] = $q.Set[$name] }
        elseif ($name -eq 'RacesHigh') { $fixed[$Layout.Races + 1] = $q.Set[$name] }
        else { $fixed[$Layout[$name]] = $q.Set[$name] }
    }
    if ($q.Set.ContainsKey('RacesLow') -and -not $q.Set.ContainsKey('RacesHigh')) { $fixed[$Layout.Races + 1] = 0 }
    $slot = 0
    foreach ($reward in $q.Rep) {
        $fixed[$Layout.Rep + 4 * $slot] = $reward[0]
        $fixed[$Layout.Rep + 4 * $slot + 1] = $reward[1]
        $fixed[$Layout.Rep + 4 * $slot + 2] = $reward[2]
        $slot++
    }
    $fixed[$Layout.Spells] = $q.Spells
    $fixed[$Layout.Objectives] = @($q.Objectives).Count + $q.Lie
    $fixed[$Layout.Treasure[0]] = $q.Treasure[0]; $fixed[$Layout.Treasure[1]] = $q.Treasure[1]
    $fixed[$Layout.Conditional[0]] = @($q.ConditionalDesc).Count; $fixed[$Layout.Conditional[1]] = @($q.ConditionalLog).Count
    $fixed[$Layout.House[0]] = $q.House[0]; $fixed[$Layout.House[1]] = $q.House[1]

    $b = New-Object 'System.Collections.Generic.List[byte]'
    foreach ($v in $fixed) { Put $b $v }
    for ($i = 0; $i -lt $q.Spells; $i++) { Put $b (1000 + $i); Put $b 0; Put $b 0 }
    foreach ($o in $q.Objectives) {
        $b.AddRange([byte[]](New-Object byte[] 33))
        Put $b $o.Effects
        Put $b 0
        for ($e = 0; $e -lt $o.Effects; $e++) { Put $b (5 + $e) }
        $d = $utf8.GetBytes($o.Description)
        $b.Add([byte]$d.Length); $b.Add(0x80); $b.AddRange($d)
    }
    for ($i = 0; $i -lt $q.Treasure[0] + $q.Treasure[1]; $i++) { Put $b 7 }
    foreach ($text in @($q.ConditionalDesc) + @($q.ConditionalLog)) {
        $d = $utf8.GetBytes($text)
        $b.AddRange([byte[]](New-Object byte[] 8))
        $b.Add([byte]($d.Length -shr 4)); $b.Add([byte](($d.Length -band 15) -shl 4)); $b.AddRange($d)
    }
    for ($i = 0; $i -lt $q.House[0] + $q.House[1]; $i++) { Put $b 9 }

    $texts = @($q.Title) + @($q.Others) + @(1..9 | ForEach-Object { '' })
    $texts = @($texts[0..8])
    $textBytes = @($texts | ForEach-Object { , $utf8.GetBytes($_) })
    $sizes = 9, 12, 12, 9, 10, 8, 10, 8, 11
    $bits = New-Object 'System.Collections.Generic.List[int]'
    for ($i = 0; $i -lt 9; $i++) { for ($k = $sizes[$i] - 1; $k -ge 0; $k--) { $bits.Add(($textBytes[$i].Length -shr $k) -band 1) } }
    $bits.Add($(if ($q.Scheduler) { 1 } else { 0 }))
    while ($bits.Count -lt 96) { $bits.Add(0) }
    for ($i = 0; $i -lt 12; $i++) {
        $v = 0
        for ($k = 0; $k -lt 8; $k++) { $v = ($v -shl 1) -bor $bits[$i * 8 + $k] }
        $b.Add([byte]$v)
    }
    foreach ($t in $textBytes) { $b.AddRange([byte[]]$t) }
    if ($q.Extra) { $b.AddRange([byte[]]$q.Extra) }
    if ($q.Cut) { $b.RemoveRange($b.Count - $q.Cut, $q.Cut) }
    return , $b.ToArray()
}

function New-Quest([int]$id, [string]$title, [hashtable]$more = @{}) {
    $q = @{ Id = $id; Title = $title; Set = @{}; Rep = @(); Spells = 0; Objectives = @(); Treasure = @(0, 0); ConditionalDesc = @(); ConditionalLog = @(); House = @(0, 0); Others = @(); Extra = $null; Cut = 0; Lie = 0; Scheduler = $false }
    foreach ($k in $more.Keys) { $q[$k] = $more[$k] }
    return $q
}

function Write-Cache([hashtable]$Layout, [hashtable[]]$quests, [string]$path, [int]$build = 0, [string]$magic = 'WQST') {
    if (-not $build) { $build = $Layout.Build }
    $b = New-Object 'System.Collections.Generic.List[byte]'
    $b.AddRange([byte[]]($magic.ToCharArray()[3..0] | ForEach-Object { [byte][char]$_ }))
    Put $b $build
    $b.AddRange([byte[]](0x53, 0x55, 0x6e, 0x65))
    Put $b 12288; Put $b 12; Put $b 0
    foreach ($q in $quests) {
        $payload = New-Payload $Layout $q
        Put $b $q.Id
        Put $b $payload.Length
        $b.AddRange([byte[]]$payload)
    }
    $b.AddRange([byte[]](New-Object byte[] 8))
    [IO.File]::WriteAllBytes($path, $b.ToArray())
}

function Write-Tables([string]$dir, [string]$version) {
    $races = @(
        'ID,ClientPrefix,ClientFileString,Flags,PlayableRaceBit,Alliance',
        '1,Hu,Human,6291468,0,0', '2,Or,Orc,6291468,1,1', '3,Dw,Dwarf,6291468,2,0', '4,Ne,NightElf,6291468,3,0',
        '5,Sc,Scourge,6291468,4,1', '6,Ta,Tauren,6291468,5,1', '7,Gn,Gnome,6291468,6,0', '8,Tr,Troll,6291468,7,1',
        '24,Pa,Pandaren,6291468,14,2', '32,Kt,KulTiran,6291468,31,0', '98,Xx,Hidden,6291468,-1,0', '99,Al,Allied,1,8,0')
    if ($version -like '12.*') { $races += '95,Tb,tbdNPCRaceX,0,32,2', '96,Tb,tbdNPCRaceY,0,33,2', '97,Nw,Newrace,0,34,1' }
    else { $races += '95,Sa,SkyborneA,6291468,32,0', '96,Sh,SkyborneH,6291468,33,1' }
    [IO.File]::WriteAllLines("$dir\ChrRaces-$version.csv", [string[]]$races)
    $rewards = @(
        'ID,Difficulty_0,Difficulty_1,Difficulty_2,Difficulty_3,Difficulty_4,Difficulty_5,Difficulty_6,Difficulty_7,Difficulty_8,Difficulty_9',
        '1,0,10,25,75,150,250,350,500,1000,5',
        '2,0,-10,-25,-75,-150,-250,-350,-500,-1000,-5')
    [IO.File]::WriteAllLines("$dir\QuestFactionReward-$version.csv", [string[]]$rewards)
}

function Invoke-Reader([hashtable]$more) {
    $params = @{ ToolsDir = $Scratch }
    foreach ($k in $more.Keys) { $params[$k] = $more[$k] }
    $failure = ''
    $text = ''
    try { $text = (@(& $Tool @params 6>&1 | ForEach-Object { "$_" }) -join "`n") } catch { $failure = $_.Exception.Message }
    return @{ Text = $text; Failure = $failure }
}

function Read-Lines([string]$path) {
    return , @([IO.File]::ReadAllLines($path, $utf8) | Where-Object { $_ })
}

try {
    foreach ($g in $Games.Values) { Write-Tables $Scratch $g.Version }

    # --- WoW: Forever -----------------------------------------------------------------------------
    $Forever = $Games.forever
    $big = New-Quest 100 'Plains Quest' @{
        Set = @{ Level = 10; MinLevel = 5; Sort = 331; Info = 1; Group = 3; Next = 101; StartItem = 2000; Flags = 0x1000; RacesLow = 77 }
        Rep = @(@(76, 3, 0), @(72, -2, 0), @(70, 0, 5000), @(68, 0, -1050), @(66, 0, 7700))
        Spells = 2
        Objectives = @(@{ Effects = 0; Description = 'Kill 5 boars' }, @{ Effects = 2; Description = '' }, @{ Effects = 1; Description = 'x' * 200 })
        Treasure = @(1, 2); ConditionalDesc = @('Alternative text'); ConditionalLog = @('Log text', ('y' * 3000)); House = @(1, 2)
        Others = @('The log description', 'A longer quest description for this quest', 'Area', 'Hello', 'Giver', 'Bye', 'Turn in', 'Done')
    }
    $small = New-Quest 5 'Plain' @{ Set = @{ Level = 1 } }
    $zeroRep = New-Quest 6 'Zero rep' @{ Set = @{ Level = 2 }; Rep = @(@(66, 0, 0), @(0, 3, 0)) }
    $path = "$Scratch\forever1.wdb"; $out = "$Scratch\forever1.jsonl"
    Write-Cache $Forever @($big, $small, $zeroRep) $path
    $r = Invoke-Reader @{ CacheFile = $path; Build = $Forever.Version; OutFile = $out }
    Equal $r.Failure '' 'F1: a cache of both quests reads'
    $lines = Read-Lines $out
    Equal $lines.Count 3 'F1: three lines'
    Equal $lines[0] '{"id":5,"title":"Plain","level":1,"minLevel":0,"sort":0,"questType":2}' 'F1: the lines are ordered by id, and a quest with nothing else has only the always-there fields'
    Equal $lines[1] '{"id":6,"title":"Zero rep","level":2,"minLevel":0,"sort":0,"questType":2}' 'F1: a reward of nothing, and a reward of a faction 0, are left out'
    Equal $lines[2] '{"id":100,"title":"Plains Quest","level":10,"minLevel":5,"sort":331,"questInfo":1,"groupSize":3,"recurs":"daily","nextQuest":101,"startItem":2000,"flags":4096,"questType":2,"reputation":[[76,75],[72,-25],[70,50],[68,-10],[66,77]],"races":[1,3,4,7],"faction":"Alliance"}' 'F1: every field of the busy quest, five reputation rewards, after walking past its lists'
    Has $r.Text '3 quests from build 70205 (enUS) written to' 'F1: the summary names the count, build and locale'
    Has $r.Text 'Races: 1 Alliance only, 0 Horde only, 0 other sets, 0 no playable race. Recurring: 1 daily, 0 weekly. 1 start from an item, 1 offer a follow-up, 0 name their quest giver, 1 reward reputation.' 'F1: and the counts'
    $r2 = Invoke-Reader @{ CacheFile = $path; Build = $Forever.Version; OutFile = "$Scratch\forever1b.jsonl" }
    Equal ([IO.File]::ReadAllText("$Scratch\forever1b.jsonl")) ([IO.File]::ReadAllText($out)) 'F2: a rerun gives the same file'
    Equal ([IO.File]::ReadAllBytes($out)[0]) ([byte][char]'{') 'F2: with no byte order mark'
    Equal ([IO.File]::ReadAllText($out)[-1]) "`n" 'F2: and a closing newline'

    $weekly = New-Quest 7 'Weekly' @{ Set = @{ Level = 20; MinLevel = 20; Flags = 0x80008000; Giver = 4321; RacesLow = 18 } }
    $horde = New-Quest 8 'Horde thing' @{ Set = @{ RacesLow = 18 } }
    $mixed = New-Quest 9 'Mixed' @{ Set = @{ RacesLow = 3 } }
    $neutral = New-Quest 10 'Neutral' @{ Set = @{ RacesLow = 16384 } }
    $allyNeutral = New-Quest 11 'Ally and neutral' @{ Set = @{ RacesLow = 16385 } }
    $highAlliance = New-Quest 12 'High word, Alliance' @{ Set = @{ RacesLow = 0; RacesHigh = 1 } }
    $highHorde = New-Quest 13 'High word, Horde' @{ Set = @{ RacesLow = 0; RacesHigh = 2 } }
    $nobody = New-Quest 14 'Nobody' @{ Set = @{ RacesLow = 0; RacesHigh = 0 } }
    $notPlayable = New-Quest 15 'Not playable here' @{ Set = @{ RacesLow = 256 } }
    $noBit = New-Quest 16 'Half mask' @{ Set = @{ RacesLow = 0xFFFFFFFFL; RacesHigh = 0 } }
    $longTexts = @(('a' * 3000), ('b' * 2100), ('c' * 300), ('d' * 600), ('e' * 200), ('f' * 600), ('g' * 200), ('h' * 1100))
    $long = New-Quest 17 ('T' * 300) @{ Others = $longTexts }
    $path = "$Scratch\forever2.wdb"; $out = "$Scratch\forever2.jsonl"
    Write-Cache $Forever @($weekly, $horde, $mixed, $neutral, $allyNeutral, $highAlliance, $highHorde, $nobody, $notPlayable, $noBit, $long) $path
    $r = Invoke-Reader @{ CacheFile = $path; Build = $Forever.Version; OutFile = $out }
    Equal $r.Failure '' 'F3: the second cache reads'
    $lines = Read-Lines $out
    Equal $lines[0] '{"id":7,"title":"Weekly","level":20,"minLevel":20,"sort":0,"recurs":"weekly","giver":4321,"flags":2147516416,"questType":2,"races":[2,5],"faction":"Horde"}' 'F3: the weekly flag, a flag above 31 bits, a named giver and a Horde set'
    Equal $lines[1] '{"id":8,"title":"Horde thing","level":0,"minLevel":0,"sort":0,"questType":2,"races":[2,5],"faction":"Horde"}' 'F3: races without the other fields'
    Equal $lines[2] '{"id":9,"title":"Mixed","level":0,"minLevel":0,"sort":0,"questType":2,"races":[1,2]}' 'F3: both sides leave the faction out'
    Equal $lines[3] '{"id":10,"title":"Neutral","level":0,"minLevel":0,"sort":0,"questType":2,"races":[24]}' 'F3: a neutral race alone gives no faction'
    Equal $lines[4] '{"id":11,"title":"Ally and neutral","level":0,"minLevel":0,"sort":0,"questType":2,"races":[1,24],"faction":"Alliance"}' 'F3: Alliance and neutral is Alliance'
    Equal $lines[5] '{"id":12,"title":"High word, Alliance","level":0,"minLevel":0,"sort":0,"questType":2,"races":[95],"faction":"Alliance"}' 'F3: bit 32 is the high word''s first'
    Equal $lines[6] '{"id":13,"title":"High word, Horde","level":0,"minLevel":0,"sort":0,"questType":2,"races":[96],"faction":"Horde"}' 'F3: bit 33 is its second'
    Equal $lines[7] '{"id":14,"title":"Nobody","level":0,"minLevel":0,"sort":0,"questType":2}' 'F3: a mask of none, as TrinityCore''s AllowableRaces 0, restricts nothing'
    Equal $lines[8] '{"id":15,"title":"Not playable here","level":0,"minLevel":0,"sort":0,"questType":2,"races":[]}' 'F3: a race the client doesn''t flag as playable in Forever is left out'
    Equal $lines[9] '{"id":16,"title":"Half mask","level":0,"minLevel":0,"sort":0,"questType":2,"races":[1,2,3,4,5,6,7,8,24,32]}' 'F3: a mask with only the low word full lists the low races, not the high ones'
    Equal $lines.Count 11 'F3: and the long-texted quest is read too'
    Equal (($lines[10] | ConvertFrom-Json).title.Length) 300 'F3: whose title takes the nine bits of its length, and whose other eight texts each need every bit of theirs'
    Has $r.Text 'Races: 2 Alliance only, 3 Horde only, 3 other sets, 1 no playable race.' 'F3: the race counts (a neutral race alone, a mixed set and the half mask are no side)'
    Has $r.Text 'Recurring: 0 daily, 1 weekly. 0 start from an item, 0 offer a follow-up, 1 name their quest giver, 0 reward reputation.' 'F3: and the rest'

    $both = New-Quest 20 'Both flags' @{ Set = @{ Flags = 0x9000 } }
    $path = "$Scratch\forever3.wdb"; $out = "$Scratch\forever3.jsonl"
    Write-Cache $Forever @($both) $path
    [void](Invoke-Reader @{ CacheFile = $path; Build = $Forever.Version; OutFile = $out })
    Has ((Read-Lines $out)[0]) '"recurs":"weekly","flags":36864' 'F4: weekly wins when both flags are set'

    $display = New-Quest 30 'Displayed as daily' @{ Set = @{ FlagsEx = 0x8000 } }
    $weeklyEx = New-Quest 31 'Weekly, shown daily' @{ Set = @{ Flags = 0x8000; FlagsEx = 0x8000 } }
    $scheduled = New-Quest 32 'Scheduled' @{ Scheduler = $true; Set = @{ FlagsEx = 0x100 } }
    $task = New-Quest 33 'Task' @{ Set = @{ QuestType = 3 } }
    $repeatable = New-Quest 34 'Repeatable' @{ Set = @{ QuestType = 0 } }
    $path = "$Scratch\forever6.wdb"; $out = "$Scratch\forever6.jsonl"
    Write-Cache $Forever @($display, $weeklyEx, $scheduled, $task, $repeatable) $path
    $r = Invoke-Reader @{ CacheFile = $path; Build = $Forever.Version; OutFile = $out }
    Equal $r.Failure '' 'F6: the flag cache reads'
    $lines = Read-Lines $out
    Equal $lines[0] '{"id":30,"title":"Displayed as daily","level":0,"minLevel":0,"sort":0,"recurs":"daily","flagsEx":32768,"questType":2}' 'F6: FlagsEx 0x8000 makes a quest daily, with its flagsEx kept'
    Equal $lines[1] '{"id":31,"title":"Weekly, shown daily","level":0,"minLevel":0,"sort":0,"recurs":"weekly","flags":32768,"flagsEx":32768,"questType":2}' 'F6: and the weekly flag still wins'
    Equal $lines[2] '{"id":32,"title":"Scheduled","level":0,"minLevel":0,"sort":0,"flagsEx":256,"questType":2,"scheduler":true}' 'F6: the scheduler bit comes after the text lengths'
    Equal $lines[3] '{"id":33,"title":"Task","level":0,"minLevel":0,"sort":0,"questType":3}' 'F6: a task quest''s type'
    Equal $lines[4] '{"id":34,"title":"Repeatable","level":0,"minLevel":0,"sort":0,"questType":0}' 'F6: and a quest type of 0 is kept, not left out as empty'
    Has $r.Text 'Recurring: 1 daily, 1 weekly.' 'F6: the counts take the new rule'

    foreach ($step in 12, 10, -10) {
        $tooBig = New-Quest 21 "Step $step" @{ Rep = @(, @(76, $step, 0)) }
        $path = "$Scratch\forever4.wdb"; $out = "$Scratch\forever4.jsonl"
        Write-Cache $Forever @($tooBig) $path
        $r = Invoke-Reader @{ CacheFile = $path; Build = $Forever.Version; OutFile = $out }
        Has $r.Failure "Quest 21 rewards reputation step $step" "F5: a reputation step of $step, outside the table, stops the run"
        Check (-not (Test-Path $out)) "F5: and writes nothing for step $step"
    }
    $edge = New-Quest 22 'Steps nine' @{ Rep = @(@(76, 9, 0), @(77, -9, 0)) }
    $path = "$Scratch\forever5.wdb"; $out = "$Scratch\forever5.jsonl"
    Write-Cache $Forever @($edge) $path
    $r = Invoke-Reader @{ CacheFile = $path; Build = $Forever.Version; OutFile = $out }
    Equal $r.Failure '' 'F5: the last step of the table, up and down, is read'
    Has ((Read-Lines $out)[0]) '"reputation":[[76,5],[77,-5]]' 'F5: with the amounts of its last column'
    $amounts = New-Quest 23 'Amounts' @{ Rep = @(@(76, 1, 0), @(77, -1, 0), @(78, 3, 2500), @(79, 0, 12399), @(80, 0, -12399)) }
    $path = "$Scratch\forever7.wdb"; $out = "$Scratch\forever7.jsonl"
    Write-Cache $Forever @($amounts) $path
    [void](Invoke-Reader @{ CacheFile = $path; Build = $Forever.Version; OutFile = $out })
    Has ((Read-Lines $out)[0]) '"reputation":[[76,10],[77,-10],[78,25],[79,123],[80,-123]]' 'F7: steps of 1 up and down, an own amount over a step, and own amounts cut to whole points'

    $word = @(
        (New-Quest 40 'Bit 31' @{ Set = @{ RacesLow = 2147483648 } }),
        (New-Quest 41 'Not bit 31' @{ Set = @{ RacesLow = 2147483647 } }))
    $path = "$Scratch\forever8.wdb"; $out = "$Scratch\forever8.jsonl"
    Write-Cache $Forever $word $path
    [void](Invoke-Reader @{ CacheFile = $path; Build = $Forever.Version; OutFile = $out })
    $lines = Read-Lines $out
    Equal $lines[0] '{"id":40,"title":"Bit 31","level":0,"minLevel":0,"sort":0,"questType":2,"races":[32],"faction":"Alliance"}' 'F8: bit 31 of the low word is a race'
    Equal $lines[1] '{"id":41,"title":"Not bit 31","level":0,"minLevel":0,"sort":0,"questType":2,"races":[1,2,3,4,5,6,7,8,24]}' 'F8: and without it the race goes'

    $several = @(
        (New-Quest 24 'Bit 11 in both' @{ Set = @{ Flags = 0x800; FlagsEx = 0x800 } }),
        (New-Quest 25 'Top bit of flagsEx' @{ Set = @{ FlagsEx = 0x80000000L } }),
        (New-Quest 26 'Daily with another bit' @{ Set = @{ Flags = 0x1004 } }),
        (New-Quest 27 'Displayed daily with another bit' @{ Set = @{ FlagsEx = 0x8004 } }))
    $path = "$Scratch\forever9.wdb"; $out = "$Scratch\forever9.jsonl"
    Write-Cache $Forever $several $path
    [void](Invoke-Reader @{ CacheFile = $path; Build = $Forever.Version; OutFile = $out })
    $lines = Read-Lines $out
    Equal $lines[0] '{"id":24,"title":"Bit 11 in both","level":0,"minLevel":0,"sort":0,"flags":2048,"flagsEx":2048,"questType":2}' 'F9: a bit that is neither daily nor weekly is kept in both words and makes nothing recurring'
    Equal $lines[1] '{"id":25,"title":"Top bit of flagsEx","level":0,"minLevel":0,"sort":0,"flagsEx":2147483648,"questType":2}' 'F9: the top bit of flagsEx stays unsigned'
    Equal $lines[2] '{"id":26,"title":"Daily with another bit","level":0,"minLevel":0,"sort":0,"recurs":"daily","flags":4100,"questType":2}' 'F9: the daily flag is a bit test, not an equality'
    Equal $lines[3] '{"id":27,"title":"Displayed daily with another bit","level":0,"minLevel":0,"sort":0,"recurs":"daily","flagsEx":32772,"questType":2}' 'F9: and so is flagsEx''s'

    # --- Retail ---------------------------------------------------------------------------------------
    $Retail = $Games.retail
    $busy = New-Quest 200 ('The "Quoted" \ Quest' + [char]0x00e9 + "`t") @{
        Set = @{ Tuning = 73; Sort = -22; Info = 62; Group = 5; Next = 4242; StartItem = 5; Flags = 0x80008000; Giver = 77; RacesLow = 0; RacesHigh = 4 }
        Rep = @(@(1273, 5, 0), @(1275, -3, 0), @(1277, 0, 4000))
        Spells = 1
        Objectives = @(@{ Effects = 3; Description = 'Collect' })
        Treasure = @(2, 1); ConditionalDesc = @('a', 'b'); ConditionalLog = @('c'); House = @(0, 1)
        Others = @('log', 'description', 'area')
    }
    $plain = New-Quest 150 'Plain retail' @{ Set = @{ Tuning = 12; Sort = 331 } }
    $control = New-Quest 151 ('a' + [char]0 + [char]31 + 'b') @{ }
    $path = "$Scratch\retail1.wdb"; $out = "$Scratch\retail1.jsonl"
    Write-Cache $Retail @($busy, $plain, $control) $path
    $r = Invoke-Reader @{ CacheFile = $path; Build = $Retail.Version; OutFile = $out }
    Equal $r.Failure '' 'R1: a retail cache reads'
    $lines = Read-Lines $out
    Equal $lines[0] '{"id":150,"title":"Plain retail","contentTuning":12,"sort":331,"questType":2}' 'R1: retail has a content tuning and no level'
    Equal $lines[1] '{"id":151,"title":"a\u0000\u001fb","contentTuning":0,"sort":0,"questType":2}' 'R1: control characters in a title are escaped, the first and the last of them'
    Equal $lines[2] ('{"id":200,"title":"The \"Quoted\" \\ Quest' + [char]0x00e9 + '\u0009","contentTuning":73,"sort":-22,"questInfo":62,"groupSize":5,"recurs":"weekly","nextQuest":4242,"startItem":5,"giver":77,"flags":2147516416,"questType":2,"reputation":[[1273,250],[1275,-75],[1277,40]],"races":[97],"faction":"Horde"}') 'R1: every field of the busy retail quest, with its title escaped, and a race of the high word'
    Has $r.Text '3 quests from build 69933 (enUS) written to' 'R1: the summary'
    Lacks ([IO.File]::ReadAllText($out)) '"level"' 'R1: no level in the file'

    $rDisplay = New-Quest 160 'Retail displayed as daily' @{ Set = @{ Tuning = 5; FlagsEx = 0x8000 }; Scheduler = $true }
    $rTask = New-Quest 161 'Retail task' @{ Set = @{ Tuning = 5; QuestType = 3; Flags = 0x4000 } }
    $path = "$Scratch\retail4.wdb"; $out = "$Scratch\retail4.jsonl"
    Write-Cache $Retail @($rDisplay, $rTask) $path
    [void](Invoke-Reader @{ CacheFile = $path; Build = $Retail.Version; OutFile = $out })
    $lines = Read-Lines $out
    Equal $lines[0] '{"id":160,"title":"Retail displayed as daily","contentTuning":5,"sort":0,"recurs":"daily","flagsEx":32768,"questType":2,"scheduler":true}' 'R4: retail''s FlagsEx is its field 24, and its scheduler bit is read'
    Equal $lines[1] '{"id":161,"title":"Retail task","contentTuning":5,"sort":0,"flags":16384,"questType":3}' 'R4: and its quest type is field 1'

    $rAmounts = New-Quest 202 'Retail amounts' @{ Set = @{ Tuning = 5 }; Rep = @(@(1273, 1, 0), @(1275, -1, 0), @(1277, 3, 2500), @(1279, 0, 12399), @(1281, 0, -12399)) }
    $rWord = New-Quest 170 'Retail bit 31' @{ Set = @{ Tuning = 5; RacesLow = 2147483648 } }
    $rSeveral = @(
        (New-Quest 162 'Bit 11 in both' @{ Set = @{ Flags = 0x800; FlagsEx = 0x800 } }),
        (New-Quest 163 'Top bit of flagsEx' @{ Set = @{ FlagsEx = 0x80000000L } }),
        (New-Quest 164 'Daily with another bit' @{ Set = @{ Flags = 0x1004 } }),
        (New-Quest 165 'Displayed daily with another bit' @{ Set = @{ FlagsEx = 0x8004 } }))
    $path = "$Scratch\retail5.wdb"; $out = "$Scratch\retail5.jsonl"
    Write-Cache $Retail (@($rAmounts, $rWord) + $rSeveral) $path
    [void](Invoke-Reader @{ CacheFile = $path; Build = $Retail.Version; OutFile = $out })
    $lines = Read-Lines $out
    Equal $lines[0] '{"id":162,"title":"Bit 11 in both","contentTuning":0,"sort":0,"flags":2048,"flagsEx":2048,"questType":2}' 'R5: a bit that is neither daily nor weekly is kept in both words and makes nothing recurring'
    Equal $lines[1] '{"id":163,"title":"Top bit of flagsEx","contentTuning":0,"sort":0,"flagsEx":2147483648,"questType":2}' 'R5: the top bit of flagsEx stays unsigned'
    Equal $lines[2] '{"id":164,"title":"Daily with another bit","contentTuning":0,"sort":0,"recurs":"daily","flags":4100,"questType":2}' 'R5: the daily flag is a bit test, not an equality'
    Equal $lines[3] '{"id":165,"title":"Displayed daily with another bit","contentTuning":0,"sort":0,"recurs":"daily","flagsEx":32772,"questType":2}' 'R5: and so is flagsEx''s'
    Equal $lines[4] '{"id":170,"title":"Retail bit 31","contentTuning":5,"sort":0,"questType":2,"races":[32],"faction":"Alliance"}' 'R5: bit 31 of the low word is a race in retail too'
    Equal $lines[5] '{"id":202,"title":"Retail amounts","contentTuning":5,"sort":0,"questType":2,"reputation":[[1273,10],[1275,-10],[1277,25],[1279,123],[1281,-123]]}' 'R5: steps of 1 up and down, an own amount over a step, and own amounts cut to whole points'

    $mix = @(
        (New-Quest 301 'Alliance, neutral, and Alliance-flag 99' @{ Set = @{ RacesLow = 16640 } }),
        (New-Quest 302 'Neutral only' @{ Set = @{ RacesLow = 16384 } }),
        (New-Quest 303 'Nobody' @{ Set = @{ RacesLow = 0; RacesHigh = 0 } }),
        (New-Quest 304 'All' @{ }),
        (New-Quest 305 'Placeholder races only' @{ Set = @{ RacesLow = 0; RacesHigh = 3 } }))
    $path = "$Scratch\retail2.wdb"; $out = "$Scratch\retail2.jsonl"
    Write-Cache $Retail $mix $path
    [void](Invoke-Reader @{ CacheFile = $path; Build = $Retail.Version; OutFile = $out })
    $lines = Read-Lines $out
    Equal $lines[0] '{"id":301,"title":"Alliance, neutral, and Alliance-flag 99","contentTuning":0,"sort":0,"questType":2,"races":[24,99],"faction":"Alliance"}' 'R2: retail counts every race that has a bit, not only those Forever flags, and the neutral one is no side'
    Equal $lines[1] '{"id":302,"title":"Neutral only","contentTuning":0,"sort":0,"questType":2,"races":[24]}' 'R2: a neutral race alone gives no faction'
    Equal $lines[2] '{"id":303,"title":"Nobody","contentTuning":0,"sort":0,"questType":2}' 'R2: a mask of none restricts nothing, in retail too'
    Equal $lines[3] '{"id":304,"title":"All","contentTuning":0,"sort":0,"questType":2}' 'R2: a record open to every race lists none'
    Equal $lines[4] '{"id":305,"title":"Placeholder races only","contentTuning":0,"sort":0,"questType":2,"races":[]}' 'R2: retail''s two placeholder races, TBD NPC Race, are not listed, though their bits are set'

    $rooms = New-Quest 310 'Houses' @{ Spells = 3; Objectives = @(@{ Effects = 0; Description = '' }, @{ Effects = 5; Description = 'z' * 100 }); Treasure = @(0, 3); House = @(2, 2); ConditionalDesc = @('p' * 70); ConditionalLog = @() }
    $path = "$Scratch\retail3.wdb"; $out = "$Scratch\retail3.jsonl"
    $longR = New-Quest 311 ('T' * 300) @{ Others = $longTexts }
    Write-Cache $Retail @($rooms, $longR) $path
    $r = Invoke-Reader @{ CacheFile = $path; Build = $Retail.Version; OutFile = $out }
    Equal $r.Failure '' 'R3: lists of every kind are walked to the last byte'
    Equal (((Read-Lines $out)[1] | ConvertFrom-Json).title.Length) 300 'R3: and long texts keep all the bits of their lengths'

    # --- The default output name and cache location --------------------------------------------------
    $dir = "$Scratch\home"
    New-Item -ItemType Directory "$dir\retail_probe_69933", "$dir\forever_probe_70205" | Out-Null
    foreach ($g in $Games.Values) { Write-Tables $dir $g.Version }
    Write-Cache $Retail @($plain) "$dir\retail_probe_69933\questcache.wdb"
    Write-Cache $Forever @($small) "$dir\forever_probe_70205\questcache.wdb"
    $params = @{ ToolsDir = $dir }
    try { $text = (@(& $Tool @params -Build $Retail.Version 6>&1 | ForEach-Object { "$_" }) -join "`n") } catch { $text = $_.Exception.Message }
    Check (Test-Path "$dir\retail_quest_cache_12.1.0.69933.jsonl") 'D1: retail writes retail_quest_cache_<build>.jsonl in the tools folder'
    Has ([IO.File]::ReadAllText("$dir\retail_quest_cache_12.1.0.69933.jsonl")) '"Plain retail"' 'D1: from the retail probe''s cache, not Forever''s'
    try { $text = (@(& $Tool @params -Build $Forever.Version 6>&1 | ForEach-Object { "$_" }) -join "`n") } catch { $text = $_.Exception.Message }
    Check (Test-Path "$dir\forever_quest_cache_1.60.1.70205.jsonl") 'D1: Forever writes forever_quest_cache_<build>.jsonl'
    Has ([IO.File]::ReadAllText("$dir\forever_quest_cache_1.60.1.70205.jsonl")) '"Plain"' 'D1: from the Forever probe''s cache'
    New-Item -ItemType Directory "$dir\retail_probe_70000" | Out-Null
    Write-Cache $Retail @((New-Quest 160 'Older retail')) "$dir\retail_probe_70000\questcache.wdb"
    (Get-Item "$dir\retail_probe_70000\questcache.wdb").LastWriteTime = [datetime]'2020-01-01'
    try { $text = (@(& $Tool @params -Build $Retail.Version 6>&1 | ForEach-Object { "$_" }) -join "`n") } catch { $text = $_.Exception.Message }
    Lacks ([IO.File]::ReadAllText("$dir\retail_quest_cache_12.1.0.69933.jsonl")) 'Older retail' 'D1: the newest cache by write time is read, whatever the folders'' names'
    $empty = "$Scratch\empty"
    New-Item -ItemType Directory $empty | Out-Null
    $r = $null
    try { & $Tool -ToolsDir $empty -Build $Retail.Version 6>&1 | Out-Null } catch { $r = $_.Exception.Message }
    Has $r 'No questcache.wdb under' 'D2: no cache to find is said so'
    Has $r 'retail_probe_*' 'D2: naming the retail folders it looked in'

    # --- A cache that doesn't fit ---------------------------------------------------------------------
    foreach ($case in @(
            @{ Name = 'long'; Quest = (New-Quest 401 'Too long' @{ Extra = @(1) }); Expect = '1 bytes are left over' },
            @{ Name = 'short'; Quest = (New-Quest 402 'Too short' @{ Others = @('A text'); Cut = 1 }); Expect = 'bytes past its end' },
            @{ Name = 'lie'; Quest = (New-Quest 403 'Counts one objective too many' @{ Lie = 1; Others = @('Text') }); Expect = '' })) {
        foreach ($game in 'forever', 'retail') {
            $Spec = $Games[$game]
            $path = "$Scratch\bad-$($case.Name)-$game.wdb"; $out = "$Scratch\bad-$($case.Name)-$game.jsonl"
            Write-Cache $Spec @((New-Quest 400 'Fine'), $case.Quest) $path
            $r = Invoke-Reader @{ CacheFile = $path; Build = $Spec.Version; OutFile = $out }
            Has $r.Failure "1 of 2 records don't fit the layout, so nothing was written" "B1: $game, a record $($case.Name): the run stops with the count"
            Has $r.Failure "$($case.Quest.Id) (" "B1: $game, $($case.Name): and names the quest"
            if ($case.Expect) { Has $r.Failure $case.Expect "B1: $game, $($case.Name): and why" }
            Check (-not (Test-Path $out)) "B1: $game, $($case.Name): and writes nothing, though the other record was fine"
        }
    }
    foreach ($game in 'forever', 'retail') {
        $Spec = $Games[$game]
        $path = "$Scratch\badid-$game.wdb"
        Write-Cache $Spec @((New-Quest 411 'Other')) $path
        $bytes = [IO.File]::ReadAllBytes($path)
        $bytes[24] = 99
        [IO.File]::WriteAllBytes($path, $bytes)
        $r = Invoke-Reader @{ CacheFile = $path; Build = $Spec.Version; OutFile = "$Scratch\badid-$game.jsonl" }
        Has $r.Failure 'it holds quest 411' "B2: $game, a record whose own id isn't its header's is refused"
    }

    # --- A cache cut short ------------------------------------------------------------------------------
    foreach ($game in 'forever', 'retail') {
        $Spec = $Games[$game]
        $whole = "$Scratch\cut-$game.wdb"
        Write-Cache $Spec @((New-Quest 700 'First'), (New-Quest 701 'Second'), (New-Quest 702 'Third' @{ Others = @('Some text to cut') })) $whole
        $bytes = [IO.File]::ReadAllBytes($whole)
        $secondAt = 24 + 8 + [BitConverter]::ToInt32($bytes, 28)
        $noLength = [byte[]]$bytes.Clone()
        foreach ($k in 4..7) { $noLength[$secondAt + $k] = 0 }
        $negativeLength = [byte[]]$bytes.Clone()
        foreach ($k in 4..7) { $negativeLength[$secondAt + $k] = 255 }
        $zeroedHeader = [byte[]]$bytes.Clone()
        foreach ($k in 0..7) { $zeroedHeader[$secondAt + $k] = 0 }
        $idTerminator = [byte[]]$bytes.Clone()
        $idTerminator[$bytes.Length - 8] = 9
        $negativeTerminator = [byte[]]$bytes.Clone()
        foreach ($k in 4..7) { $negativeTerminator[$bytes.Length - 8 + $k] = 255 }
        $cases = @(
            @{ Name = 'no terminator'; Bytes = [byte[]]$bytes[0..($bytes.Length - 9)]; Expect = "doesn't end with its terminator after 3 quests" },
            @{ Name = 'cut inside the last record'; Bytes = [byte[]]$bytes[0..($bytes.Length - 30)]; Expect = "records don't fit|doesn't end with its terminator" },
            @{ Name = 'cut after the second record'; Bytes = [byte[]]$bytes[0..($secondAt - 1)]; Expect = "doesn't end with its terminator after 1 quests" },
            @{ Name = 'a record of no length'; Bytes = $noLength; Expect = "doesn't end with its terminator after 1 quests" },
            @{ Name = 'a record of negative length'; Bytes = $negativeLength; Expect = "doesn't end with its terminator after 1 quests" },
            @{ Name = 'a zeroed header between records'; Bytes = $zeroedHeader; Expect = "doesn't end with its terminator after 1 quests" },
            @{ Name = 'a terminator with an id'; Bytes = $idTerminator; Expect = "doesn't end with its terminator after 3 quests" },
            @{ Name = 'a terminator of negative length'; Bytes = $negativeTerminator; Expect = "doesn't end with its terminator after 3 quests" },
            @{ Name = 'bytes after the terminator'; Bytes = [byte[]]($bytes + (New-Object byte[] 4)); Expect = "doesn't end with its terminator after 3 quests" },
            @{ Name = 'nothing after the header'; Bytes = [byte[]]($bytes[0..23] + (New-Object byte[] 8)); Expect = 'holds no quests' })
        foreach ($case in $cases) {
            $path = "$Scratch\cut-$($case.Name -replace '\W', '')-$game.wdb"; $out = "$Scratch\cut-$game.jsonl"
            [IO.File]::WriteAllBytes($path, $case.Bytes)
            $r = Invoke-Reader @{ CacheFile = $path; Build = $Spec.Version; OutFile = $out }
            Check ($r.Failure -match $case.Expect) "C1: $game, $($case.Name): refused with the reason (got '$($r.Failure)')"
            Check (-not (Test-Path $out)) "C1: $game, $($case.Name): and nothing is written"
        }
    }

    # --- The other game's layout ----------------------------------------------------------------------
    $four = @(1..4 | ForEach-Object { New-Quest (500 + $_) "Quest number $_" @{ Others = @('A description of some length', 'Area'); Objectives = @(@{ Effects = 1; Description = 'Do it' }) } })
    $path = "$Scratch\mix-f.wdb"
    Write-Cache $Forever $four $path 69933
    $r = Invoke-Reader @{ CacheFile = $path; Build = $Retail.Version; OutFile = "$Scratch\mix-f.jsonl" }
    Has $r.Failure "records don't fit the layout, so nothing was written" 'L1: a cache in Forever''s layout read as retail is refused'
    $path = "$Scratch\mix-r.wdb"
    Write-Cache $Retail $four $path 70205
    $r = Invoke-Reader @{ CacheFile = $path; Build = $Forever.Version; OutFile = "$Scratch\mix-r.jsonl" }
    Has $r.Failure "records don't fit the layout, so nothing was written" 'L1: and retail''s read as Forever is'

    # --- The wrong cache --------------------------------------------------------------------------------
    $path = "$Scratch\okay.wdb"
    Write-Cache $Retail @($plain) $path
    $r = Invoke-Reader @{ CacheFile = $path; Build = '12.1.0.69934'; OutFile = "$Scratch\x1.jsonl" }
    Has $r.Failure 'The cache is from build 69933, not 12.1.0.69934' 'W1: a cache of another build is refused'
    $path = "$Scratch\magic.wdb"
    Write-Cache $Retail @($plain) $path 0 'WCRQ'
    $r = Invoke-Reader @{ CacheFile = $path; Build = $Retail.Version; OutFile = "$Scratch\x2.jsonl" }
    Has $r.Failure 'isn''t a quest cache (it starts ''WCRQ'')' 'W2: a creature cache is refused'
    $r = Invoke-Reader @{ CacheFile = "$Scratch\okay.wdb"; Build = '5.0.0.69933'; OutFile = "$Scratch\x3.jsonl" }
    Has $r.Failure 'is neither WoW: Forever (1.x) nor retail (12.x)' 'W3: a build that is neither game is refused'
    $r = Invoke-Reader @{ CacheFile = "$Scratch\okay.wdb"; Build = '0.9.0.69933'; OutFile = "$Scratch\x4.jsonl" }
    Has $r.Failure 'is neither WoW: Forever' 'W3: nor is a build that starts with 0'
    Check (-not (Test-Path "$Scratch\x1.jsonl") -and -not (Test-Path "$Scratch\x2.jsonl") -and -not (Test-Path "$Scratch\x3.jsonl")) 'W3: and none of the refusals wrote a file'
    $few = "$Scratch\few"
    New-Item -ItemType Directory $few | Out-Null
    [IO.File]::WriteAllLines("$few\ChrRaces-12.1.0.69933.csv", [string[]]@('ID,Flags,PlayableRaceBit,Alliance', '1,0,0,0', '2,0,1,1'))
    Copy-Item "$Scratch\QuestFactionReward-12.1.0.69933.csv" "$few\QuestFactionReward-12.1.0.69933.csv"
    $r = $null
    try { & $Tool -ToolsDir $few -Build $Retail.Version -CacheFile "$Scratch\okay.wdb" -OutFile "$few\o.jsonl" 6>&1 | Out-Null } catch { $r = $_.Exception.Message }
    Has $r 'has only 2 playable races' 'W4: a races table with too few playable races is refused'
    [IO.File]::WriteAllLines("$few\ChrRaces-12.1.0.69933.csv", [string[]](Get-Content "$Scratch\ChrRaces-12.1.0.69933.csv"))
    [IO.File]::WriteAllLines("$few\QuestFactionReward-12.1.0.69933.csv", [string[]]@('ID,Difficulty_0,Difficulty_1,Difficulty_2,Difficulty_3,Difficulty_4,Difficulty_5,Difficulty_6,Difficulty_7,Difficulty_8,Difficulty_9', '1,0,10,25,75,150,250,350,500,1000,0'))
    $r = $null
    try { & $Tool -ToolsDir $few -Build $Retail.Version -CacheFile "$Scratch\okay.wdb" -OutFile "$few\o.jsonl" 6>&1 | Out-Null } catch { $r = $_.Exception.Message }
    Has $r 'lacks its gain and loss rows' 'W5: a reward table without its loss row is refused'
    [IO.File]::WriteAllLines("$few\QuestFactionReward-12.1.0.69933.csv", [string[]]@('ID,Difficulty_0,Difficulty_1,Difficulty_2,Difficulty_3,Difficulty_4,Difficulty_5,Difficulty_6,Difficulty_7,Difficulty_8,Difficulty_9', '2,0,-10,-25,-75,-150,-250,-350,-500,-1000,-5'))
    $r = $null
    try { & $Tool -ToolsDir $few -Build $Retail.Version -CacheFile "$Scratch\okay.wdb" -OutFile "$few\o.jsonl" 6>&1 | Out-Null } catch { $r = $_.Exception.Message }
    Has $r 'lacks its gain and loss rows' 'W5: nor one without its gain row'
}
catch { Check $false "the run stopped: $($_.Exception.Message)" }
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
