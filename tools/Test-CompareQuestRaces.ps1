<#
Checks QuestRaces.ps1 and Compare-QuestRaces.ps1 (step 1e) on a made-up race table, quest cache, data folder and
decisions file in a temporary folder: nothing in the checkout is touched and nothing is downloaded. It checks which races
are compared (a side's, one per side sharing a bit, not the neutral Pandaren, not a race no player plays, and a stop for
a race with no bit of ours), which races the data allows, each class of difference and the data the game's list gives,
the decisions file, and runs on retail (a finding, the FIX rows written, a second run, rows that go wrong) and on WoW:
Forever (a difference is the importer's).

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-CompareQuestRaces.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
. (Join-Path $PSScriptRoot 'QuestRaces.ps1')
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

function Race($id, $name, $alliance, $bit, $flags = 0) { [pscustomobject]@{ ID = "$id"; ClientFileString = $name; Alliance = "$alliance"; PlayableRaceBit = "$bit"; Flags = "$flags" } }
# The Alliance: Human 1, Dwarf 4, the Pandaren 4096 and the Void Elf 8192 (12293); the Horde: Orc 2, the Pandaren and the
# Nightborne 16384 (20482).
$raceRows = @((Race 1 'Human' 0 0), (Race 3 'Dwarf' 0 2), (Race 2 'Orc' 1 1), (Race 24 'Pandaren' 2 23), (Race 25 'Pandaren' 0 24),
    (Race 26 'Pandaren' 1 25), (Race 29 'VoidElf' 0 28), (Race 27 'Nightborne' 1 26), (Race 99 'Mystery' 0 40 1), (Race 98 'Mystery' 0 -1))
$races = @(Get-ComparedRaces $raceRows)
Equal (($races | ForEach-Object { "$($_.Id):$($_.Bit):$($_.Side)" }) -join ' ') '1:1:1 3:4:1 2:2:2 25:4096:1 26:4096:2 29:8192:1 27:16384:2' 'R1: each side''s races with our bits; not the neutral Pandaren, nor a race no player plays'
$threw = $false; try { Get-ComparedRaces @(Race 50 'Mystery' 0 30) | Out-Null } catch { $threw = $_.Exception.Message -match 'no race bit of ours' }
Check $threw 'R2: a playable race with no bit of ours stops the run'

function Ids($list) { ($list | ForEach-Object { $_.Id }) -join ',' }
Equal (Ids (Get-DataRaces $races 0 0)) '1,3,2,25,26,29,27' 'D1: mask and faction 0: every race'
Equal (Ids (Get-DataRaces $races 0 1)) '1,3,25,29' 'D1: faction 1: the Alliance''s'
Equal (Ids (Get-DataRaces $races 4096 2)) '26' 'D1: the shared Pandaren bit with faction 2: the Horde''s Pandaren'

function Get-Difference($mask, $faction, $listed) { $d = Compare-QuestRaceList $races $mask $faction $listed; if ($d) { "$($d.Class) -$(Ids $d.Hide) +$(Ids $d.Show) $($d.Mask)/$($d.Faction)" } else { 'none' } }
Equal (Get-Difference 1 1 @()) 'none' 'C1: no list from the game, no difference'
Equal (Get-Difference 12293 1 @(1, 3, 25, 29)) 'none' 'C1: the same races, no difference'
Equal (Get-Difference 12293 2 @(2, 26, 27)) 'contradiction -2,27 + 20482/2' 'C2: a Horde quest with the Alliance''s mask'
Equal (Get-Difference 4101 1 @(1, 3, 25, 29)) 'stale -29 + 12293/1' 'C3: a mask that lacks only a race added after Legion'
Equal (Get-Difference 1 1 @(1, 3, 25, 29)) 'narrowing -3,25,29 + 12293/1' 'C4: a mask of the starting race'
Equal (Get-Difference 20482 2 @(2, 26)) 'shown - +27 4098/2' 'C5: the data allows a race the game denies'
Equal (Get-Difference 2 2 @(26, 27)) 'crosses -26,27 +2 20480/2' 'C6: both ways'
Equal (Get-Difference 4096 7 @(24)) 'shown - +25,26 0/4' 'C7: the neutral Pandaren alone: no race of ours, the neutral bit kept'
Equal (Get-Difference 20482 3 @(2, 26, 27, 1)) 'crosses -1 +25 20483/3' 'C8: a list of both sides gives both sides'

$root = Join-Path ([IO.Path]::GetTempPath()) ("quest_races_test_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $root | Out-Null
try {
    $decisionsFile = Join-Path $root 'decisions.csv'
    function Decisions($rows) {
        @($rows | ForEach-Object { [pscustomobject]@{ Game = $_[0]; QuestID = "$($_[1])"; Name = "Quest $($_[1])"; Decision = $_[2]; Class = ''; Evidence = 'test' } }) | Export-Csv $decisionsFile -NoTypeInformation -Encoding UTF8
    }
    Decisions @(@('retail', 100, 'FIX'), @('forever', 100, 'KEEP'))
    $read = Read-QuestRaceDecisions $decisionsFile 'retail'
    Equal "$($read.Count) $($read[100].Decision)" '1 FIX' 'F1: a game''s rows'
    Decisions @(, @('retail', 100, 'SET'))
    $threw = $false; try { Read-QuestRaceDecisions $decisionsFile 'retail' | Out-Null } catch { $threw = $_.Exception.Message -match 'only FIX and KEEP' }
    Check $threw 'F2: an unknown decision stops the run'

    $tools = Join-Path $root 'tools'; $data = Join-Path $root 'data'; $addon = Join-Path $root 'addon'
    New-Item -ItemType Directory -Force $tools, $data, $addon | Out-Null
    $build = '9.9.9.1'
    $raceRows | Select-Object -First 8 | Export-Csv (Join-Path $tools "ChrRaces-$build.csv") -NoTypeInformation -Encoding UTF8
    $cache = Join-Path $tools "retail_quest_cache_$build.jsonl"
    $lines = @(@(100, '[2,26,27]'), @(101, '[1,3,25,29]'), @(102, '[1,3,25,29]'), @(103, '[2,26]'), @(104, '[26,27]'), @(105, '[1,3,25,29]'), @(106, $null), @(108, '[24]')) |
        ForEach-Object { '{"id":' + $_[0] + ',"title":"Quest ' + $_[0] + '","sort":0' + $(if ($_[1]) { ',"races":' + $_[1] } else { '' }) + '}' }
    [IO.File]::WriteAllText($cache, ($lines -join "`n") + "`n")
    $quest = { param($id, $faction, $race) '{"id":' + $id + ',"name":"Quest ' + $id + '","level":10,"zone":"","category":1,"type":1,"faction":' + $faction + ',"race":' + $race + ',"class":8191}' }
    $questLines = @(@(100, 2, 12293), @(101, 1, 4101), @(102, 1, 1), @(103, 2, 20482), @(104, 2, 2), @(105, 1, 12293), @(106, 1, 0), @(107, 2, 0), @(108, 7, 4096)) | ForEach-Object { & $quest $_[0] $_[1] $_[2] }
    [IO.File]::WriteAllText((Join-Path $data 'quests.jsonl'), ($questLines -join "`n") + "`n")
    [IO.File]::WriteAllText((Join-Path $data 'pins.jsonl'), '{"map":1,"icon":1,"x":1,"y":1,"quests":[100]}' + "`n")
    Check (Invoke-AddonDataBuild -DataDir $data -AddonDir $addon).Ok 'E0: the data folder builds'
    $step = @{ Game = 'retail'; Build = $build; ToolsDir = $tools; DataDir = $data; AddonDir = $addon; QuestCacheFile = $cache; DecisionsFile = $decisionsFile; OutFile = (Join-Path $root 'races.csv') }
    function Run($more = @{}) { $all = $step.Clone(); foreach ($k in $more.Keys) { $all[$k] = $more[$k] }; $out = @(& (Join-Path $PSScriptRoot 'Compare-QuestRaces.ps1') @all 6>$null 3>$null); return @{ Out = $out; Exit = $LASTEXITCODE } }

    Decisions @(@('retail', 100, 'FIX'), @('retail', 101, 'FIX'), @('retail', 102, 'KEEP'), @('retail', 104, 'FIX'), @('retail', 108, 'KEEP'))
    $r = Run @{ WhatIf = $true }
    Equal $r.Out[0] 'Races, retail (retail_quest_cache_9.9.9.1.jsonl, ChrRaces 9.9.9.1): the game lists races for 7 of our quests; 6 differ (contradiction 1, stale 1, narrowing 1, shown 2, crosses 1). Decided: FIX 3, KEEP 2.' 'E1: each class counted, with the decisions'
    Equal $r.Out[1] 'Our own restrictions where the game lists no races (kept, not listed): 1.' 'E1: a restriction where the game lists none is counted, one the cache lacks isn''t'
    Equal $r.Out[2] 'Findings: 1: 103 Quest 103: shown with no decision row' 'E2: a difference with no row is a finding'
    Equal $r.Exit 1 'E2: exit 1'
    Check ([IO.File]::ReadAllText((Join-Path $data 'quests.jsonl')).Contains((& $quest 100 2 12293))) 'E2: -WhatIf writes nothing'

    Decisions @(@('retail', 100, 'FIX'), @('retail', 101, 'FIX'), @('retail', 102, 'KEEP'), @('retail', 103, 'FIX'), @('retail', 104, 'FIX'), @('retail', 108, 'KEEP'))
    $r = Run
    Equal "$($r.Exit) $($r.Out[3])" '0 quests.jsonl: 4 race lists taken from the game: 100, 101, 103, 104.' 'E3: the FIX rows are written'
    $text = [IO.File]::ReadAllText((Join-Path $data 'quests.jsonl'))
    Check ($text.Contains((& $quest 100 2 20482)) -and $text.Contains((& $quest 101 1 12293)) -and $text.Contains((& $quest 103 2 4098)) -and $text.Contains((& $quest 104 2 20480))) 'E3: each with the game''s races'
    Check ($text.Contains((& $quest 102 1 1)) -and $text.Contains((& $quest 108 7 4096))) 'E3: the KEEP rows'' quests as they were'
    Check ([IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua')).Contains('[100]={"Quest 100",10,1,1,2,20482,8191},')) 'E3: and built'
    $r = Run
    Equal "$($r.Exit) $($r.Out[0])" '0 Races, retail (retail_quest_cache_9.9.9.1.jsonl, ChrRaces 9.9.9.1): the game lists races for 7 of our quests; 2 differ (contradiction 0, stale 0, narrowing 1, shown 1, crosses 0). Decided: FIX 0, KEEP 2.' 'E4: a second run leaves the KEEP rows'' alone'

    Decisions @(@('retail', 102, 'KEEP'), @('retail', 105, 'KEEP'), @('retail', 107, 'FIX'), @('retail', 108, 'FIX'))
    $r = Run @{ WhatIf = $true }
    Equal $r.Out[2] 'Findings: 3: 105 Quest 105: a KEEP row, but the data and the game now agree; 108 Quest 108: a FIX row, but the game lists only races our bits can''t name; 107 Quest 107: a FIX row, but the game''s record lists no races for it now' 'E5: rows that no longer fit are findings'

    $forever = Join-Path $root 'forever'; New-Item -ItemType Directory -Force $forever | Out-Null
    [IO.File]::WriteAllText((Join-Path $forever 'quests.jsonl'), ((@(@(101, 1, 4101), @(105, 1, 12293)) | ForEach-Object { & $quest $_[0] $_[1] $_[2] }) -join "`n") + "`n")
    $foreverCache = Join-Path $tools "forever_quest_cache_$build.jsonl"
    [IO.File]::WriteAllText($foreverCache, '{"id":101,"title":"Quest 101","races":[1,3,25,29]}' + "`n" + '{"id":105,"title":"Quest 105","races":[1,3,25,29]}' + "`n")
    Decisions @(, @('forever', 101, 'FIX'))
    $r = Run @{ Game = 'forever'; DataDir = $forever; QuestCacheFile = $foreverCache; WhatIf = $true }
    Equal "$($r.Exit) $($r.Out[2])" '1 Findings: 1: 101 Quest 101: stale, which the importer should have taken from the cache' 'G1: on Forever a difference is the importer''s'
}
finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output "$Passed checks passed, $Failed failed."
if ($Failed -gt 0) { exit 1 }
