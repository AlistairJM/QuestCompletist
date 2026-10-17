<#
Checks QuestSides.ps1, the side rows of AddonData.ps1 and Sync-QuestSides.ps1 (step 2p) on made-up client tables,
emulator dumps, probe results and data folders in a temporary folder: nothing in the checkout is touched and nothing is
downloaded. It checks who can talk to a giver (a faction with a standing, the other side's locked, one earned from
unfriendly, a class's own first slot; enemy and friend groups and lists, hostile by default), a quest's starters, the
zone's side, what the step does with a quest, the quest chain's say (a follow-up, a clash either way, follow-ups held
back), the decisions file, the data file, its checks and the build, a run on retail (Blizzard's side from the probe and
the quest cache, the givers' side from pins and TrinityCore, an item anyone can loot, an unknown giver, a KEEP row, a
follow-up, a quest its chain holds open, the zone column, a second run) and one on WoW: Forever (CMaNGOS's starters, a
giver the probe saw, a side the importer should have given).

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncQuestSides.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
. (Join-Path $PSScriptRoot 'FactionReach.ps1')
. (Join-Path $PSScriptRoot 'QuestSides.ps1')
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

function Template($id, $faction, $group, $friendGroup, $enemyGroup, $flags = 0, $enemies = @(), $friends = @()) {
    $row = [ordered]@{ ID = "$id"; Faction = "$faction"; Flags = "$flags"; FactionGroup = "$group"; FriendGroup = "$friendGroup"; EnemyGroup = "$enemyGroup" }
    for ($i = 0; $i -lt 8; $i++) { $row["Enemies_$i"] = "$(if ($i -lt $enemies.Count) { $enemies[$i] } else { 0 })" }
    for ($i = 0; $i -lt 8; $i++) { $row["Friend_$i"] = "$(if ($i -lt $friends.Count) { $friends[$i] } else { 0 })" }
    [pscustomobject]$row
}
# [low, high, class, base, max, flags] per slot, as Test-SyncFactionReach.ps1's.
function Faction($id, $index, $slots) {
    $row = [ordered]@{ ID = "$id"; Name_lang = "Faction $id"; ReputationIndex = "$index" }
    for ($i = 0; $i -lt 4; $i++) {
        $s = if ($i -lt $slots.Count) { $slots[$i] } else { @(0, 0, 0, 0, 0, 0) }
        $row["ReputationRaceMasks${i}_0"] = "$($s[0])"; $row["ReputationRaceMasks${i}_1"] = "$($s[1])"; $row["ReputationClassMask_$i"] = "$($s[2])"
        $row["ReputationBase_$i"] = "$($s[3])"; $row["ReputationMax_$i"] = "$($s[4])"; $row["ReputationFlags_$i"] = "$($s[5])"
    }
    [pscustomobject]$row
}
function Race($id, $alliance, $bit, $template, $flags = 0) { [pscustomobject]@{ ID = "$id"; Alliance = "$alliance"; PlayableRaceBit = "$bit"; FactionID = "$template"; Flags = "$flags" } }

# A Human (template 1) for the Alliance and an Orc (template 2) for the Horde; a neutral Pandaren and a race no player
# plays, which count for neither side.
$templates = @(
    (Template 1 1 3 2 12), (Template 2 2 5 4 10),
    (Template 11 72 0 0 0), (Template 12 76 0 0 0),         # a city of each side: a standing the other side can't earn
    (Template 13 500 0 0 0),                                # neutral to all
    (Template 14 500 0 0 4), (Template 15 500 0 0 0 0 @(1)), # hostile to the Horde's group; to the Human's faction
    (Template 16 500 0 2 0 0x800), (Template 17 500 0 0 0 0x800),  # hostile by default, but friendly to the Alliance; and not
    (Template 18 609 0 0 0), (Template 19 700 0 0 0),       # a standing earned from unfriendly; a class's own first slot
    (Template 20 500 0 0 4 0 @() @(2)))                     # the Horde's group an enemy, but the Orc's faction a friend
$factions = @(
    (Faction 72 1 @(@(2, 0, 0, -42000, -42000, 6), @(0, 0, 0, 0, 42000, 16))),
    (Faction 76 2 @(@(1, 0, 0, -42000, -42000, 6), @(0, 0, 0, 0, 42000, 16))),
    (Faction 609 3 @(, @(0, 0, 0, -3000, 42000, 16))),
    (Faction 700 4 @(@(0, 0, 32, -42000, -42000, 6), @(0, 0, 0, 0, 42000, 16))),
    (Faction 500 -1 @()), (Faction 1 -1 @()), (Faction 2 -1 @()))
$races = @((Race 1 0 0 1), (Race 2 1 1 2), (Race 24 2 23 1), (Race 99 0 40 1 1))
$reader = New-SideReader $templates $factions $races
Equal (Get-TemplateSides $reader 11) 1 'G1: the Alliance city: the Horde is locked out of its standing'
Equal (Get-TemplateSides $reader 12) 2 'G1: and the Horde city'
Equal (Get-TemplateSides $reader 13) 3 'G2: a neutral giver talks to both'
Equal (Get-TemplateSides $reader 14) 1 'G2: one whose enemy groups hold the Horde''s talks to the Alliance'
Equal (Get-TemplateSides $reader 15) 2 'G2: one that names the Human''s faction an enemy talks to the Horde'
Equal (Get-TemplateSides $reader 16) 1 'G3: hostile by default, but friendly to the Alliance''s group'
Equal (Get-TemplateSides $reader 17) 0 'G3: hostile by default to everyone'
Equal (Get-TemplateSides $reader 18) 3 'G4: a standing both can earn from unfriendly'
Equal (Get-TemplateSides $reader 19) 3 'G4: a class''s own first slot locks out only that class'
Equal (Get-TemplateSides $reader 20) 3 'G5: a friend list comes before the enemy groups'
Check ($null -eq (Get-TemplateSides $reader 999)) 'G6: a template the build lacks is unknown'

function Starter($kind, $template, $side = 0) { [pscustomobject]@{ Kind = $kind; Template = $template; Side = $side } }
Check ($null -eq (Get-StarterSides $reader @())) 'S1: no starter, no side'
Equal (Get-StarterSides $reader @((Starter npc 11))) 1 'S1: one giver of one side'
Equal (Get-StarterSides $reader @((Starter npc 11), (Starter npc 12))) 3 'S2: a giver of each side opens it to both'
Check ($null -eq (Get-StarterSides $reader @((Starter npc 11), (Starter npc $null)))) 'S2: one side''s giver beside an unknown one says nothing'
Equal (Get-StarterSides $reader @((Starter npc 11), (Starter npc $null), (Starter npc 13))) 3 'S2: unless the others already open it to both'
Equal (Get-StarterSides $reader @((Starter npc 11), (Starter item $null 0))) 3 'S3: an item anyone can loot opens it to both'
Equal (Get-StarterSides $reader @(, (Starter item $null 2))) 2 'S3: an item of one side is that side''s'
Equal (Get-StarterSides $reader @(, (Starter object 0))) 3 'S3: an object of faction 0 is anyone''s'

$areas = @{}
foreach ($a in @(@(10, 0, 2), @(11, 10, 0), @(12, 0, 4), @(13, 0, 6), @(14, 0, 0))) { $areas[$a[0]] = [pscustomobject]@{ ID = $a[0]; ParentAreaID = $a[1]; FactionGroupMask = $a[2] } }
Equal (Get-ZoneSide $areas 10) 1 'Z1: an Alliance zone'
Equal (Get-ZoneSide $areas 11) 1 'Z1: its subzone, by its parent'
Equal (Get-ZoneSide $areas 12) 2 'Z1: a Horde zone'
Equal (Get-ZoneSide $areas 13) 3 'Z1: a zone of both'
Equal (Get-ZoneSide $areas 14) 0 'Z1: a zone that says nothing'
Equal (Get-ZoneSide $areas 999) 0 'Z1: a zone the table lacks'

Equal (((0, 3, 7, 1, 2, 5) | ForEach-Object { Test-SideOpen $_ }) -join ',') 'True,True,True,False,False,False' 'O1: open to both: 0, both bits, both and neutral; one side alone is not'
function Result($ours, $blizzard, $reach, $keep) { $r = Get-QuestSideResult $ours $blizzard $reach $keep; if ($r) { "$($r.Faction)/$($r.Side)/$($r.Finding)" } else { 'none' } }
Equal (Result 3 2 1 $false) '2/0/' 'R1: Blizzard''s side comes before the givers'''
Equal (Result 7 1 $null $false) '1/0/' 'R1: also for a quest open to the neutral Pandaren'
Equal (Result 3 $null 1 $false) '0/1/' 'R2: the givers'' side when Blizzard names none'
Equal (Result 0 $null 2 $false) '0/2/' 'R2: also for a faction of 0'
Equal (Result 3 $null 1 $true) 'none' 'R3: a KEEP row leaves it open'
Equal (Result 3 $null 3 $false) 'none' 'R3: givers of both sides leave it open'
Equal (Result 1 2 $null $false) '0/0/Blizzard names the Horde' 'R4: a quest of one side Blizzard names the other for is a finding'
Equal (Result 1 1 2 $false) 'none' 'R4: givers never move a quest Blizzard and the data agree on'

Equal ((Get-PrereqIds @(5, @(@(7, 8)), 9)) -join ',') '5,7,8,9' 'C0: a prerequisite list, however it nests'
function Chain($needs, $fixed, $rows, $open) {
    $neededBy = @{}
    foreach ($q in $needs.Keys) { foreach ($p in $needs[$q]) { if (-not $neededBy.ContainsKey($p)) { $neededBy[$p] = @() }; $neededBy[$p] += $q } }
    $openSet = @{}; foreach ($q in $open) { $openSet[$q] = $true }
    $c = Resolve-ChainSides $needs $neededBy $fixed $rows $openSet
    return (($c.Rows.Keys | Sort-Object | ForEach-Object { "$_=$($c.Rows[$_])" }) -join ' ') + ' | ' + (($c.Dropped.Keys | Sort-Object | ForEach-Object { "-$_" }) -join ' ') + ' | ' + (($c.Followed.Keys | Sort-Object | ForEach-Object { "$_<$($c.Followed[$_])" }) -join ' ')
}
Equal (Chain @{ 2 = @(1); 3 = @(2) } @{} @{ 1 = 1 } @(2, 3)) '1=1 2=1 3=1 |  | 2<1 3<2' 'C1: a follow-up takes its prerequisite''s side, down the chain'
Equal (Chain @{ 5 = @(4) } @{ 4 = 2 } @{ 5 = 1 } @()) ' | -5 | ' 'C2: a row whose quest needs one of the other side goes'
Equal (Chain @{ 7 = @(6) } @{ 7 = 2 } @{ 6 = 1 } @()) ' | -6 | ' 'C2: so does one a quest of the other side needs'
Equal (Chain @{ 8 = @(1); 9 = @(8) } @{ 9 = 2 } @{ 1 = 1 } @(8)) '1=1 |  | ' 'C3: no follow-up a quest of the other side needs'
Equal (Chain @{ 10 = @(1, 11) } @{ 11 = 2 } @{ 1 = 1 } @(10)) '1=1 |  | ' 'C3: nor one that needs both sides'' quests'
Equal (Chain @{ 12 = @(13) } @{ 13 = 1 } @{} @(12)) ' |  | ' 'C3: nor one whose prerequisite has its side from the data alone'

$root = Join-Path ([IO.Path]::GetTempPath()) ("quest_sides_test_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $root | Out-Null
try {
    $decisions = Join-Path $root 'decisions.csv'
    @([pscustomobject]@{ Game = 'retail'; QuestID = '204'; Name = 'Quest 204'; Decision = 'KEEP'; Evidence = 'Both sides take it.' },
      [pscustomobject]@{ Game = 'forever'; QuestID = '204'; Name = 'Quest 204'; Decision = 'KEEP'; Evidence = 'Forever too.' }) | Export-Csv $decisions -NoTypeInformation -Encoding UTF8
    $keep = Read-QuestSideDecisions $decisions 'retail'
    Equal "$($keep.Count) $($keep[204])" '1 Both sides take it.' 'D1: a game''s KEEP rows, with their evidence'
    Equal (Read-QuestSideDecisions (Join-Path $root 'none.csv') 'retail').Count 0 'D1: no file, no rows'
    [pscustomobject]@{ Game = 'retail'; QuestID = '9'; Name = 'Quest 9'; Decision = 'SET'; Evidence = '' } | Export-Csv (Join-Path $root 'bad.csv') -NoTypeInformation -Encoding UTF8
    $threw = $false; try { Read-QuestSideDecisions (Join-Path $root 'bad.csv') 'retail' | Out-Null } catch { $threw = $_.Exception.Message -match "only KEEP" }
    Check $threw 'D2: a decision other than KEEP stops the run'

    function Side($quest, $side) { [pscustomobject]@{ quest = $quest; side = $side } }
    Equal (ConvertTo-SideJsonLines @((Side 100 1), (Side 102 2))) ('{"quest":100,"side":1}' + "`n" + '{"quest":102,"side":2}' + "`n") 'J1: one quest per line'
    $problems = @(Test-SideRecords @((Side 0 1), (Side 100 3), (Side 101 1), (Side 101 2)))
    Check (@($problems | Where-Object { $_ -match "line 1: 'quest' must" }).Count -eq 1) 'T1: a quest of 0 is a problem'
    Check (@($problems | Where-Object { $_ -match "line 2: 'side' must" }).Count -eq 1) 'T1: so is a side that is neither 1 nor 2'
    Check (@($problems | Where-Object { $_ -match 'line 4: quest 101 is also on line 3' }).Count -eq 1) 'T1: and a quest listed twice'
    Equal @(Test-SideRecords @((Side 100 1))).Count 0 'T1: sound rows have none'

    $data = Join-Path $root 'data'; $addon = Join-Path $root 'addon'
    New-Item -ItemType Directory -Force $data, $addon | Out-Null
    $quest = { param($id, $faction) '{"id":' + $id + ',"name":"Quest ' + $id + '","level":30,"zone":"","category":1,"type":1,"faction":' + $faction + ',"race":64175181,"class":8191}' }
    [IO.File]::WriteAllText((Join-Path $data 'quests.jsonl'), ((@(@(100, 3), @(101, 1), @(102, 0), @(103, 7)) | ForEach-Object { & $quest $_[0] $_[1] }) -join "`n") + "`n")
    [IO.File]::WriteAllText((Join-Path $data 'pins.jsonl'), '{"map":1,"icon":1,"x":1,"y":1,"quests":[100]}' + "`n")
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    Check ($build.Ok -and @($build.Lines | Where-Object { $_ -match 'sides' }).Count -eq 0) 'B1: a data folder with no side rows builds and counts none'
    [IO.File]::WriteAllText((Join-Path $data 'sides.jsonl'), (ConvertTo-SideJsonLines @((Side 100 2), (Side 101 2), (Side 102 1), (Side 103 1), (Side 999 1))))
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    $lua = [IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua'))
    Check ($build.Ok -and $lua.Contains('[100]={"Quest 100",30,1,1,2,64175181,8191},')) 'B2: a quest open to both takes its row''s side'
    Check ($lua.Contains('[102]={"Quest 102",30,1,1,1,') -and $lua.Contains('[103]={"Quest 103",30,1,1,1,')) 'B2: so do a faction of 0 and one open to the neutral Pandaren too'
    Check $lua.Contains('[101]={"Quest 101",30,1,1,1,') 'B3: a quest that already has a side keeps it'
    Check (@($build.Lines | Where-Object { $_ -match '5 sides \(3 applied\)' }).Count -eq 1) 'B3: and the rows left out are counted'
    Check (Invoke-AddonDataBuild -DataDir $data -AddonDir $addon -Check).Ok 'B4: a second build changes nothing'
    [IO.File]::WriteAllText((Join-Path $data 'sides.jsonl'), '{"quest":100,"side":2,"why":"givers"}' + "`n")
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    Check (-not $build.Ok -and @($build.Lines | Where-Object { $_ -match "unknown field 'why'" }).Count -eq 1) 'B4: an unknown field stops the build'

    # A run on retail. Givers: 5000 the Alliance city's, 5001 the Horde city's, 5002 not in the dump; object 7000 of
    # faction 0. 200: the probe says Horde. 201: the quest cache says Alliance, its giver is the Horde's. 202: a pin of
    # 5000. 203: 5001 and an item anyone can loot. 204: 5001, with a KEEP row. 205: 5002. 207: object 7000. 208: a pin of
    # 5000, in an Alliance zone by the API's area. 209: no starter, in a Horde zone by TrinityCore's sort. 210 needs 202 and so follows it;
    # 211, a pin of 5000, needs 212, a Horde quest, and stays open.
    $tools = Join-Path $root 'tools'; $data = Join-Path $root 'retail'; $addon = Join-Path $root 'retail-addon'
    New-Item -ItemType Directory -Force $tools, $data, $addon, (Join-Path $tools 'quest_api_cache') | Out-Null
    $tableBuild = '9.9.9.1'
    $templates | Export-Csv (Join-Path $tools "FactionTemplate-$tableBuild.csv") -NoTypeInformation -Encoding UTF8
    $factions | Export-Csv (Join-Path $tools "Faction-$tableBuild.csv") -NoTypeInformation -Encoding UTF8
    $races | Export-Csv (Join-Path $tools "ChrRaces-$tableBuild.csv") -NoTypeInformation -Encoding UTF8
    @(@(10, 'Alliance Zone', 0, 2), @(12, 'Horde Zone', 0, 4)) | ForEach-Object { [pscustomobject]@{ ID = $_[0]; AreaName_lang = $_[1]; ParentAreaID = $_[2]; FactionGroupMask = $_[3] } } |
        Export-Csv (Join-Path $tools "AreaTable-$tableBuild.csv") -NoTypeInformation -Encoding UTF8
    $tdb = Join-Path $tools 'tdb.sql'
    [IO.File]::WriteAllText($tdb, (@(
        "INSERT INTO ``creature_template`` VALUES (5000,0,0,'Guard',0,0,0,0,0,0,11),(5001,0,0,'Grunt',0,0,0,0,0,0,12);",
        "INSERT INTO ``creature_queststarter`` VALUES (5001,200,0),(5001,201,0),(5001,203,0),(5001,204,0),(5002,205,0);",
        "INSERT INTO ``gameobject_queststarter`` VALUES (7000,207,0);",
        "INSERT INTO ``quest_template`` VALUES (209,2,0,0,12);") -join "`n") + "`n")
    $probe = Join-Path $tools 'QCForeverProbe.lua'
    [IO.File]::WriteAllText($probe, 'QCForeverProbeDB = { quests = { [200] = { build = "9.9.9.1", result = "ok", factionGroup = 2 }, [202] = { build = "9.9.9.1", result = "ok" } } }' + "`n")
    $cacheFile = Join-Path $tools "retail_quest_cache_$tableBuild.jsonl"
    [IO.File]::WriteAllText($cacheFile, '{"id":201,"title":"Quest 201","sort":0,"faction":"Alliance"}' + "`n")
    [IO.File]::WriteAllText((Join-Path $tools 'quest_api_cache\208.json'), '{"id":208,"title":"Quest 208","area":{"key":{"href":"x"},"name":"Alliance Zone","id":10}}')
    [IO.File]::WriteAllText((Join-Path $data 'quests.jsonl'), (@((200, 201, 202, 203, 204, 205, 207, 208, 209) | ForEach-Object { & $quest $_ 3 }) + @(((& $quest 210 3) -replace '\}$', ',"prereq":202}'), ((& $quest 211 3) -replace '\}$', ',"prereq":212}'), (& $quest 212 2)) -join "`n") + "`n")
    [IO.File]::WriteAllText((Join-Path $data 'pins.jsonl'), '{"map":1,"icon":1,"npc":5000,"name":"Guard","x":1,"y":1,"quests":[202,208,211]}' + "`n")
    [IO.File]::WriteAllText((Join-Path $data 'startitems.jsonl'), '{"item":9000,"quest":203}' + "`n")
    Check (Invoke-AddonDataBuild -DataDir $data -AddonDir $addon).Ok 'E0: the retail data folder builds'
    $step = @{ Game = 'retail'; Build = $tableBuild; ToolsDir = $tools; DataDir = $data; AddonDir = $addon; ProbeFile = $probe; QuestCacheFile = $cacheFile; EmulatorFile = $tdb
        DecisionsFile = $decisions; OutFile = (Join-Path $root 'sides-retail.csv') }
    $out = @(& (Join-Path $PSScriptRoot 'Sync-QuestSides.ps1') @step 6>$null 3>$null)
    $exit = $LASTEXITCODE
    Equal $out[0] 'Sides, retail (9.9.9.1): 12 quests, 11 open to both sides. Blizzard names a side for 2 of them (into quests.jsonl); their givers'' side for 2 more and 1 that follow them in their chain (sides.jsonl); left open, their chain being the other side''s, 1; kept by decision 1.' 'E1: the probe''s and the cache''s sides, two by givers, one following, one its chain holds open, one kept'
    Equal $out[1] 'The giver rule against Blizzard''s own side: agrees for 1 of the 2 quests both name a side for.' 'E2: the rule checked against Blizzard'
    Equal $out[2] 'Open to both, in one side''s zone (AreaTable.FactionGroupMask): 2; their givers open to both 0, one side 1, unknown 1.' 'E3: the zone, by the API''s area and by TrinityCore''s sort'
    Equal $out[3] 'Findings: 0' 'E3: no finding'
    Equal $out[4] 'quests.jsonl: 2 faction changes: 200 Horde, 201 Alliance.' 'E4: Blizzard''s sides into the data'
    Equal $out[5] 'sides.jsonl: added 3, changed 0, gone 0: +202 +208 +210.' 'E4: the givers'' sides into the side rows'
    Equal $exit 0 'E4: exit 0'
    Check ([IO.File]::ReadAllText((Join-Path $data 'quests.jsonl')).Contains('{"id":200,"name":"Quest 200","level":30,"zone":"","category":1,"type":1,"faction":2,')) 'E5: written to quests.jsonl'
    Equal ([IO.File]::ReadAllText((Join-Path $data 'sides.jsonl'))) (ConvertTo-SideJsonLines @((Side 202 1), (Side 208 1), (Side 210 1))) 'E5: and to sides.jsonl'
    $lua = [IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua'))
    Check ($lua.Contains('[202]={"Quest 202",30,1,1,1,') -and $lua.Contains('[203]={"Quest 203",30,1,1,3,') -and $lua.Contains('[205]={"Quest 205",30,1,1,3,') -and $lua.Contains('[207]={"Quest 207",30,1,1,3,')) 'E5: built; an item anyone loots, an unknown giver and an object of faction 0 leave theirs open'
    $report = @(Import-Csv (Join-Path $root 'sides-retail.csv'))
    Equal (($report | ForEach-Object { "$($_.QuestID):$($_.Result)" }) -join ' | ') '200:faction Horde (Blizzard) | 201:faction Alliance (Blizzard) | 202:side Alliance (givers) | 204:kept: Both sides take it. | 208:side Alliance (givers) | 209:zone only | 210:side Alliance (follows 202) | 211:open: its chain is the Horde''s' 'E6: the report''s rows'
    Equal (($report | Where-Object { $_.QuestID -eq '208' }) | ForEach-Object { "$($_.Zone)/$($_.ZoneSide)/$($_.Givers)" }) 'Alliance Zone/Alliance/Guard (Alliance)' 'E6: with the zone and the givers'
    $out = @(& (Join-Path $PSScriptRoot 'Sync-QuestSides.ps1') @step 6>$null 3>$null)
    Equal "$($out[4]) $($out[5])" 'quests.jsonl: 0 faction changes. sides.jsonl: added 0, changed 0, gone 0.' 'E7: a second run changes nothing'

    # A run on WoW: Forever (-WhatIf): 300's giver is the Horde's in CMaNGOS, 302's the Alliance's that the probe saw offer
    # it, and the probe names the Alliance for 301, which the importer should have given.
    $data = Join-Path $root 'forever'; New-Item -ItemType Directory -Force $data | Out-Null
    $sql = Join-Path $root 'cmangos.sql'
    [IO.File]::WriteAllText($sql, (@(
        "INSERT INTO ``creature_template`` VALUES (6000,'Grunt',0,0,0,0,0,0,0,12),(6001,'Guard',0,0,0,0,0,0,0,11);",
        "INSERT INTO ``creature_questrelation`` VALUES (6000,300);",
        "INSERT INTO ``quest_template`` VALUES (300,0,12);") -join "`n") + "`n")
    $gz = Join-Path $root 'ClassicDB.sql.gz'
    $source = [IO.File]::OpenRead($sql); $target = [IO.File]::Create($gz); $gzip = New-Object IO.Compression.GZipStream $target, ([IO.Compression.CompressionMode]::Compress)
    $source.CopyTo($gzip); $gzip.Close(); $target.Close(); $source.Close()
    $probe = Join-Path $root 'QCForeverProbe-forever.lua'
    [IO.File]::WriteAllText($probe, 'QCForeverProbeDB = { quests = { [301] = { build = "8.8.8.1", result = "ok", factionGroup = 1 } }, givers = { ["Creature:6001"] = { kind = "Creature", id = 6001, spots = {}, offers = { [302] = 1 }, turnIns = {} } } }' + "`n")
    $cacheFile = Join-Path $tools 'forever_quest_cache_8.8.8.1.jsonl'
    [IO.File]::WriteAllText($cacheFile, '{"id":300,"title":"Quest 300","sort":12}' + "`n")
    [IO.File]::WriteAllText((Join-Path $data 'quests.jsonl'), (((300, 301, 302) | ForEach-Object { & $quest $_ 3 }) -join "`n") + "`n")
    [IO.File]::WriteAllText((Join-Path $data 'pins.jsonl'), '{"map":1,"icon":1,"x":1,"y":1,"quests":[300]}' + "`n")
    $step = @{ Game = 'forever'; Build = $tableBuild; ToolsDir = $tools; DataDir = $data; AddonDir = $addon; ProbeFile = $probe; QuestCacheFile = $cacheFile; EmulatorFile = $gz
        DecisionsFile = $decisions; OutFile = (Join-Path $root 'sides-forever.csv'); WhatIf = $true }
    $out = @(& (Join-Path $PSScriptRoot 'Sync-QuestSides.ps1') @step 6>$null 3>$null)
    $exit = $LASTEXITCODE
    Equal $out[0] 'Sides, forever (9.9.9.1): 3 quests, 3 open to both sides. Blizzard names a side for 1 of them (the importer gives these); their givers'' side for 2 more and 0 that follow them in their chain (sides.jsonl); left open, their chain being the other side''s, 0; kept by decision 0.' 'F1: CMaNGOS''s giver and the one the probe saw'
    Equal $out[3] 'Findings: 1: 301 Quest 301: Blizzard names the Alliance, which the importer didn''t give' 'F2: a side the importer should have given is a finding'
    Equal $out[5] 'sides.jsonl: added 2, changed 0, gone 0: +300 +302.' 'F2: the givers'' sides'
    Equal $exit 1 'F2: exit 1 on a finding'
    Check (-not (Test-Path (Join-Path $data 'sides.jsonl'))) 'F3: -WhatIf writes nothing'
}
finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output "$Passed checks passed, $Failed failed."
if ($Failed -gt 0) { exit 1 }
