<#
Checks Compare-QuestCache.ps1 on a cache, API records and client tables made here, in a scratch folder:
nothing in the checkout is read or written and nothing is downloaded. It makes a base set of quests
whose cache values, API records and client-table rows all agree, and changes one thing at a time: a
title, a sort, a daily, weekly, recurs or repeatable flag, a faction, the races, a questInfo, a
content tuning, a start item, a reputation amount, a few differences (what a hotfix looks like), and enough of them to look like a shifted
field. It also checks the ways a run is refused and what it says it did not compare.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-CompareQuestCache.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
$savedCulture = [Threading.Thread]::CurrentThread.CurrentCulture
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$Tool = Join-Path $PSScriptRoot 'Compare-QuestCache.ps1'
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

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("compare-quest-cache-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$Build = '12.1.0.69933'

function New-ApiRecord([int]$id, [hashtable]$a) {
    $namespace = if ($a.Namespace) { $a.Namespace } else { '12.1.0_68914' }
    $json = '{"_links":{"self":{"href":"https://us.api.blizzard.com/data/wow/quest/' + $id + '?namespace=static-' + $namespace + '-us"}},"id":' + $id + ',"title":"' + $a.Title + '"'
    if ($a.Type) { $json += ',"type":{"key":{"href":"https://us.api.blizzard.com/data/wow/quest/type/' + $a.Type + '?namespace=static-' + $namespace + '-us"},"name":"Kind","id":' + $a.Type + '}' }
    if ($a.Area) { $json += ',"area":{"key":{"href":"https://us.api.blizzard.com/data/wow/quest/area/' + $a.Area + '?namespace=static-' + $namespace + '-us"},"name":"Zone \"One\"","id":' + $a.Area + '}' }
    if ($a.Category) { $json += ',"category":{"key":{"href":"https://us.api.blizzard.com/data/wow/quest/category/' + $a.Category + '?namespace=static-' + $namespace + '-us"},"name":"Heading","id":' + $a.Category + '}' }
    $json += ',"description":"Some text, with a \"quote\" and a newline\n."'
    $sideText = $(if ($a.Faction) { '"faction":{"type":"' + $a.Faction + '","name":"Side"},' } else { '' })
    $raceText = $(if ($a.Races) { '"races":[' + (($a.Races | ForEach-Object { '{"key":{"href":"https://us.api.blizzard.com/data/wow/playable-race/' + $_ + '?namespace=static-' + $namespace + '-us"},"name":"Race","id":' + $_ + '}' }) -join ',') + '],' } else { '' })
    $json += ',"requirements":{' + $(if ($null -ne $a.Min) { '"min_character_level":' + $a.Min + ',"max_character_level":' + $a.Max + ',' } else { '' }) + $sideText + $raceText + '"reputations":[{"faction":{"key":{"href":"https://us.api.blizzard.com/data/wow/reputation-faction/9?namespace=x"},"name":"Needed","id":9},"max_reputation":-1}]}'
    $rewards = '"experience":100'
    $reps = @()
    foreach ($r in @($a.Reps)) { if ($r) { $reps += '{"reward":{"key":{"href":"https://us.api.blizzard.com/data/wow/reputation-faction/' + $r[0] + '?namespace=static-' + $namespace + '-us"},"name":"Faction","id":' + $r[0] + '},"value":' + $r[1] + '}' } }
    if ($reps) { $rewards += ',"reputations":[' + ($reps -join ',') + ']' }
    $rewards += ',"currency":[{"reward":{"key":{"href":"https://us.api.blizzard.com/data/wow/currency/515?namespace=static-' + $namespace + '-us"},"name":"Ticket","id":515},"value":5}]'
    $json += ',"rewards":{' + $rewards + '}'
    if ($a.Daily) { $json += ',"is_daily":true' }
    if ($a.Weekly) { $json += ',"is_weekly":true' }
    if ($a.Repeatable) { $json += ',"is_repeatable":true' }
    return $json + '}'
}

function New-CacheLine([int]$id, [hashtable]$c) {
    $line = '{"id":' + $id + ',"title":"' + $c.Title + '","contentTuning":' + $c.Tuning + ',"sort":' + $c.Sort
    if ($c.Info) { $line += ',"questInfo":' + $c.Info }
    if ($c.StartItem) { $line += ',"startItem":' + $c.StartItem }
    if ($c.Flags) { $line += ',"flags":' + $c.Flags }
    if ($c.FlagsEx) { $line += ',"flagsEx":' + $c.FlagsEx }
    if ($c.Recurs) { $line += ',"recurs":"' + $c.Recurs + '"' }
    if ($null -ne $c.Races) { $line += ',"races":[' + ($c.Races -join ',') + ']' }
    if ($c.Faction) { $line += ',"faction":"' + $c.Faction + '"' }
    $line += ',"questType":' + $c.QuestType
    $reps = @()
    foreach ($r in @($c.Reps)) { if ($r) { $reps += '[' + $r[0] + ',' + $r[1] + ']' } }
    if ($reps) { $line += ',"reputation":[' + ($reps -join ',') + ']' }
    return $line + '}'
}

# A quest is a pair: what the cache says, and what Blizzard's data says; both start the same.
function New-Base {
    $q = @{}
    $q[1] = @{ Cache = @{ Title = 'Alpha'; Tuning = 12; Sort = 331; Info = 41; StartItem = 100; QuestType = 2; Faction = 'Alliance'; Races = @(1, 3, 4) }
        Api = @{ Title = 'Alpha'; Area = 331; Type = 41; Min = 7; Max = 30; Faction = 'ALLIANCE' }; Cli = @(41, 12, 100) }
    $q[2] = @{ Cache = @{ Title = 'Beta'; Tuning = 12; Sort = -81; Flags = 4096; Recurs = 'daily'; QuestType = 2; Reps = @(, @(76, 250)) }
        Api = @{ Title = 'Beta'; Category = 81; Min = 7; Max = 30; Daily = $true; Reps = @(, @(76, 250)) } }
    $q[3] = @{ Cache = @{ Title = 'Gamma'; Tuning = 20; Sort = 5; FlagsEx = 32768; Recurs = 'daily'; QuestType = 2; Reps = @(@(76, 250), @(72, -25)) }
        Api = @{ Title = 'Gamma'; Area = 5; Min = 30; Max = 40; Daily = $true; Reps = @(@(76, 250), @(72, -25)) } }
    $q[4] = @{ Cache = @{ Title = 'Delta'; Tuning = 20; Sort = 5; Flags = 32768; Recurs = 'weekly'; QuestType = 2 }
        Api = @{ Title = 'Delta'; Area = 5; Min = 30; Max = 40; Weekly = $true } }
    $q[5] = @{ Cache = @{ Title = 'Epsilon'; Tuning = 12; Sort = 0; QuestType = 0 }
        Api = @{ Title = 'Epsilon'; Min = 7; Max = 30; Repeatable = $true } }
    $q[6] = @{ Cache = @{ Title = 'Zeta'; Tuning = 12; Sort = 0; QuestType = 0 }
        Api = @{ Title = 'Zeta'; Min = 7; Max = 30 }; InQuestV2 = $true }
    $q[7] = @{ Cache = @{ Title = 'Eta (no API record)'; Tuning = 33; Sort = 7; Info = 41; StartItem = 9; QuestType = 3 }
        Cli = @(41, 33, 9) }
    $q[8] = @{ Cache = @{ Title = 'The \"Quoted\" \u00e9 \\ quest'; Tuning = 12; Sort = 331; QuestType = 2; Faction = 'Horde'; Races = @(2, 5) }
        Api = @{ Title = 'The \"Quoted\" \u00e9 \\ quest'; Area = 331; Min = 7; Max = 30; Races = @(2, 5) } }
    return $q
}

function Write-World([string]$name, $quests, [hashtable]$options = @{}) {
    $dir = Join-Path $Scratch $name
    New-Item -ItemType Directory "$dir\quest_api_cache" -Force | Out-Null
    $cache = @(); $cli = @('ID,QuestTitle_lang,StartItem,QuestInfoID,ContentTuningID'); $v2 = @('ID,UniqueBitFlag')
    foreach ($id in $quests.Keys) {
        $q = $quests[$id]
        $cache += New-CacheLine $id $q.Cache
        if ($q.Api) { [IO.File]::WriteAllText("$dir\quest_api_cache\$id.json", (New-ApiRecord $id $q.Api), $utf8) }
        else { [IO.File]::WriteAllText("$dir\quest_api_cache\$id.404", '', $utf8) }
        if ($q.Cli) { $cli += "$id,Title,$($q.Cli[2]),$($q.Cli[0]),$($q.Cli[1])" }
        if ($q.InQuestV2 -or $id -le 4) { $v2 += "$id,1" }
    }
    [IO.File]::WriteAllText("$dir\retail_quest_cache_$Build.jsonl", (($cache -join "`n") + "`n"), $utf8)
    [IO.File]::WriteAllText("$dir\QuestV2CliTask.csv", (($cli -join "`r`n") + "`r`n"), $utf8)
    if (-not $options.NoQuestV2) { [IO.File]::WriteAllText("$dir\QuestV2-$Build.csv", (($v2 -join "`r`n") + "`r`n"), $utf8) }
    return $dir
}

function Invoke-Tool([string]$dir, [hashtable]$more = @{}) {
    $params = @{ ToolsDir = $dir; MinCompared = 1 }
    foreach ($k in $more.Keys) { $params[$k] = $more[$k] }
    if ($null -eq $params['MinCompared']) { $params.Remove('MinCompared') }
    $global:LASTEXITCODE = 0
    $failure = ''
    $lines = @()
    try { $lines = @(& $Tool @params) } catch { $failure = $_.Exception.Message }
    if ($env:QUEST_CACHE_TEST_VERBOSE) { Write-Host "---- run (exit $global:LASTEXITCODE) $failure"; $lines | ForEach-Object { Write-Host "     $_" } }
    return @{ Text = ($lines -join "`n"); Exit = $global:LASTEXITCODE; Failure = $failure }
}

try {
    # --- A clean run ---------------------------------------------------------------------------------
    $dir = Write-World 'clean' (New-Base)
    $r = Invoke-Tool $dir
    Equal $r.Failure '' 'C1: a clean run does not throw'
    Equal $r.Exit 0 'C1: a clean run exits 0'
    Has $r.Text 'Cache retail_quest_cache_12.1.0.69933.jsonl: 8 quests, 7 with an API record (build 12.1.0_68914), 2 in the client''s task table.' 'C1: the header counts quests, API records, its build and the task table'
    Has $r.Text 'title: 7 compared, 0 differ  [ok]' 'C1: titles, with escapes and a non-ASCII letter, agree'
    Has $r.Text 'sort: 5 compared, 0 differ  [ok]' 'C1: sort compares an area and a category only where the API gives one'
    Has $r.Text 'daily: 7 compared, 0 differ  [ok]' 'C1: daily, from the flag and from FlagsEx'
    Has $r.Text 'weekly: 7 compared, 0 differ  [ok]' 'C1: weekly'
    Has $r.Text 'recurs: 7 compared, 0 differ  [ok]' 'C1: recurs, which is weekly before daily'
    Has $r.Text 'faction: 1 compared, 0 differ  [ok]' 'C1: faction, where the API names one'
    Has $r.Text 'races: 1 compared, 0 differ  [ok]' 'C1: races, where the API lists them'
    Has $r.Text 'repeatable: 7 compared, 0 differ  [ok]' 'C1: repeatable, a quest of type 0 that is not in QuestV2'
    Has $r.Text 'reputation reward: 3 compared, 0 differ  [ok]' 'C1: reputation rewards, not the currency next to them or the faction a quest requires'
    Has $r.Text 'one level range per content tuning: 7 compared, 0 differ  [ok]' 'C1: each tuning gives one range'
    Has $r.Text 'questInfo against the API: 1 compared, 0 differ  [ok]' 'C1: questInfo is compared where the API has a type'
    Has $r.Text 'questInfo against the client table: 2 compared, 0 differ  [ok]' 'C1: and against the client table'
    Has $r.Text 'contentTuning against the client table: 2 compared, 0 differ  [ok]' 'C1: contentTuning'
    Has $r.Text 'startItem against the client table: 2 compared, 0 differ  [ok]' 'C1: startItem'

    # --- One difference at a time: listed, not failed -------------------------------------------------
    $cases = @(
        @{ Name = 'title'; Id = 1; Edit = { param($q) $q.Cache.Title = 'Alpha!' }; Line = 'title: 7 compared, 1 differ  [differs]'; Example = "1 cache 'Alpha!', API 'Alpha'" },
        @{ Name = 'title case'; Id = 1; Edit = { param($q) $q.Cache.Title = 'alpha' }; Line = 'title: 7 compared, 1 differ  [differs]'; Example = "1 cache 'alpha', API 'Alpha'" },
        @{ Name = 'sort'; Id = 1; Edit = { param($q) $q.Cache.Sort = 332 }; Line = 'sort: 5 compared, 1 differ  [differs]'; Example = '1 cache 332, API 331' },
        @{ Name = 'category'; Id = 2; Edit = { param($q) $q.Cache.Sort = 81 }; Line = 'sort: 5 compared, 1 differ  [differs]'; Example = '2 cache 81, API -81' },
        @{ Name = 'daily lost'; Id = 2; Edit = { param($q) $q.Cache.Flags = 0 }; Line = 'daily: 7 compared, 1 differ  [differs]'; Example = '2 cache daily=False, API is_daily=True' },
        @{ Name = 'daily ex lost'; Id = 3; Edit = { param($q) $q.Cache.FlagsEx = 0 }; Line = 'daily: 7 compared, 1 differ  [differs]'; Example = '3 cache daily=False, API is_daily=True' },
        @{ Name = 'daily made up'; Id = 1; Edit = { param($q) $q.Cache.Flags = 4096 }; Line = 'daily: 7 compared, 1 differ  [differs]'; Example = '1 cache daily=True, API is_daily=False' },
        @{ Name = 'weekly lost'; Id = 4; Edit = { param($q) $q.Cache.Flags = 0 }; Line = 'weekly: 7 compared, 1 differ  [differs]'; Example = '4 cache weekly=False, API is_weekly=True' },
        @{ Name = 'recurs lost'; Id = 2; Edit = { param($q) $q.Cache.Recurs = '' }; Line = 'recurs: 7 compared, 1 differ  [differs]'; Example = "2 cache '', API 'daily'" },
        @{ Name = 'recurs wrong'; Id = 4; Edit = { param($q) $q.Cache.Recurs = 'daily' }; Line = 'recurs: 7 compared, 1 differ  [differs]'; Example = "4 cache 'daily', API 'weekly'" },
        @{ Name = 'faction swapped'; Id = 1; Edit = { param($q) $q.Cache.Faction = 'Horde' }; Line = 'faction: 1 compared, 1 differ  [differs]'; Example = "1 cache 'Horde', API 'Alliance'" },
        @{ Name = 'faction lost'; Id = 1; Edit = { param($q) $q.Cache.Faction = '' }; Line = 'faction: 1 compared, 1 differ  [differs]'; Example = "1 cache '', API 'Alliance'" },
        @{ Name = 'races'; Id = 8; Edit = { param($q) $q.Cache.Races = @(2, 6) }; Line = 'races: 1 compared, 1 differ  [differs]'; Example = '8 cache [2,6], API [2,5]' },
        @{ Name = 'faction case'; Id = 1; Edit = { param($q) $q.Cache.Faction = 'alliance' }; Line = 'faction: 1 compared, 1 differ  [differs]'; Example = "1 cache 'alliance', API 'Alliance'" },
        @{ Name = 'races lost'; Id = 8; Edit = { param($q) $q.Cache.Races = $null }; Line = 'races: 1 compared, 1 differ  [differs]'; Example = '8 cache [], API [2,5]' },
        @{ Name = 'sign'; Id = 3; Edit = { param($q) $q.Cache.Reps = @(@(76, 250), @(72, 25)) }; Line = 'reputation reward: 3 compared, 1 differ  [differs]'; Example = '3 faction 72: cache 25, API -25' },
        @{ Name = 'no reward at all'; Id = 2; Edit = { param($q) $q.Cache.Reps = $null }; Line = 'reputation reward: 3 compared, 1 differ  [differs]'; Example = '2 faction 76: cache none, API 250' },
        @{ Name = 'repeatable lost'; Id = 5; Edit = { param($q) $q.Cache.QuestType = 2 }; Line = 'repeatable: 7 compared, 1 differ  [differs]'; Example = '5 cache repeatable=False, API is_repeatable=True' },
        @{ Name = 'repeatable made up'; Id = 8; Edit = { param($q) $q.Cache.QuestType = 0 }; Line = 'repeatable: 7 compared, 1 differ  [differs]'; Example = '8 cache repeatable=True, API is_repeatable=False' },
        @{ Name = 'questInfo vs API'; Id = 1; Edit = { param($q) $q.Cache.Info = 62 }; Line = 'questInfo against the API: 1 compared, 1 differ  [differs]'; Example = '1 cache 62, API 41' },
        @{ Name = 'questInfo vs table'; Id = 7; Edit = { param($q) $q.Cache.Info = 62 }; Line = 'questInfo against the client table: 2 compared, 1 differ  [differs]'; Example = '7 cache 62, table 41' },
        @{ Name = 'tuning vs table'; Id = 7; Edit = { param($q) $q.Cache.Tuning = 34 }; Line = 'contentTuning against the client table: 2 compared, 1 differ  [differs]'; Example = '7 cache 34, table 33' },
        @{ Name = 'start item'; Id = 1; Edit = { param($q) $q.Cache.StartItem = 101 }; Line = 'startItem against the client table: 2 compared, 1 differ  [differs]'; Example = '1 cache 101, table 100' },
        @{ Name = 'start item made up'; Id = 7; Edit = { param($q) $q.Cache.StartItem = 0 }; Line = 'startItem against the client table: 2 compared, 1 differ  [differs]'; Example = '7 cache 0, table 9' },
        @{ Name = 'amount'; Id = 2; Edit = { param($q) $q.Cache.Reps = @(, @(76, 150)) }; Line = 'reputation reward: 3 compared, 1 differ  [differs]'; Example = '2 faction 76: cache 150, API 250' },
        @{ Name = 'reward lost'; Id = 3; Edit = { param($q) $q.Cache.Reps = @(, @(76, 250)) }; Line = 'reputation reward: 3 compared, 1 differ  [differs]'; Example = '3 faction 72: cache none, API -25' },
        @{ Name = 'tuning range'; Id = 4; Edit = { param($q) $q.Cache.Tuning = 12 }; Line = 'one level range per content tuning: 7 compared, 1 differ  [differs]'; Example = '4 tuning 12 gives 30-40, but quest 1 gives 7-30' }
    )
    foreach ($case in $cases) {
        $world = New-Base
        & $case.Edit $world[[int]$case.Id]
        $dir = Write-World ("one-" + ($case.Name -replace '\W', '')) $world
        $r = Invoke-Tool $dir
        Equal $r.Exit 0 "O1: $($case.Name): one difference does not fail the run"
        Has $r.Text $case.Line "O1: $($case.Name): it is counted"
        Has $r.Text $case.Example "O1: $($case.Name): and named with both values"
    }
    $world = New-Base
    $world[4].Cache.FlagsEx = 32768; $world[4].Api.Daily = $true
    $dir = Write-World 'bothrecur' $world
    $r = Invoke-Tool $dir
    Equal $r.Exit 0 'O6: a quest the API calls both daily and weekly is weekly in the cache'
    Has $r.Text 'recurs: 7 compared, 0 differ  [ok]' 'O6: weekly is put before daily'
    Has $r.Text 'daily: 7 compared, 0 differ  [ok]' 'O6: though the daily bit is still read'
    $world = New-Base
    $world[8].Cache.Races = @(5, 2)
    $dir = Write-World 'raceorder1' $world
    $r = Invoke-Tool $dir
    Has $r.Text 'races: 1 compared, 0 differ  [ok]' 'O7: the cache''s races are compared whatever their order'
    $world = New-Base
    $world[8].Api.Races = @(5, 2); $world[8].Cache.Races = @(2, 5)
    $dir = Write-World 'raceorder2' $world
    $r = Invoke-Tool $dir
    Has $r.Text 'races: 1 compared, 0 differ  [ok]' 'O7: and so are the API''s'
    $world = New-Base
    $world[10] = @{ Cache = @{ Title = 'Iota'; Tuning = 50; Sort = 0; QuestType = 2 }; Api = @{ Title = 'Iota'; Min = 7; Max = 30 } }
    $world[11] = @{ Cache = @{ Title = 'Kappa'; Tuning = 50; Sort = 0; QuestType = 2 }; Api = @{ Title = 'Kappa'; Min = 8; Max = 31 } }
    $dir = Write-World 'tie' $world
    $r = Invoke-Tool $dir
    Has $r.Text '11 tuning 50 gives 8-31, but quest 10 gives 7-30' 'O8: when two ranges tie, the lowest quest''s is the one the other is held to'
    $world = New-Base
    $world[9] = @{ Cache = @{ Title = 'Theta'; Tuning = 12; Sort = 0; QuestType = 2 }; Api = @{ Title = 'Theta'; Min = $null } }
    $dir = Write-World 'nolevels' $world
    $r = Invoke-Tool $dir
    Equal $r.Exit 0 'O3: an API record with no level range is not compared'
    Has $r.Text 'one level range per content tuning: 7 compared, 0 differ  [ok]' 'O3: and does not count as a range of its own'
    $dir = Write-World 'blankline' (New-Base)
    $cacheFile = "$dir\retail_quest_cache_$Build.jsonl"
    $lines = [IO.File]::ReadAllLines($cacheFile)
    [IO.File]::WriteAllText($cacheFile, (($lines[0..2] -join "`n") + "`n`n" + ($lines[3..($lines.Count - 1)] -join "`n") + "`n`n"), $utf8)
    $r = Invoke-Tool $dir
    Equal $r.Failure '' 'O4: blank lines in the cache are skipped'
    Equal $r.Exit 0 'O4: and the run passes'
    Has $r.Text ': 8 quests,' 'O4: with every quest read'
    $world = New-Base
    foreach ($id in @($world.Keys)) { if ($world[$id].Api) { $world[$id].Api.Remove('Area'); $world[$id].Api.Remove('Category') } }
    $dir = Write-World 'nosort' $world
    $r = Invoke-Tool $dir
    Equal $r.Exit 1 'O5: a run that compared no sort at all fails'
    Has $r.Text 'sort: nothing compared  [FAILED]' 'O5: and names it'
    $extra = New-Base
    $extra[2].Cache.Reps = @(@(76, 250), @(99, 10))
    $dir = Write-World 'more-reps' $extra
    $r = Invoke-Tool $dir
    Equal $r.Exit 0 'O2: a reward on a faction the API doesn''t list is not held against the cache'
    Has $r.Text 'reputation reward: 3 compared, 0 differ  [ok]' 'O2: it is not compared at all'

    # --- Enough differences to look like a shifted field: failed ----------------------------------------
    $big = @{}
    foreach ($id in 1..60) {
        $big[$id] = @{ Cache = @{ Title = "Quest $id"; Tuning = 12; Sort = 331; Info = 41; StartItem = 100; Flags = 4096; Recurs = 'daily'; Faction = 'Alliance'; Races = @(1, 3); QuestType = 2; Reps = @(, @(76, 250)) }
            Api = @{ Title = "Quest $id"; Area = 331; Type = 41; Min = 7; Max = 30; Daily = $true; Faction = 'ALLIANCE'; Races = @(1, 3); Reps = @(, @(76, 250)) }; Cli = @(41, 12, 100) }
    }
    $dir = Write-World 'big-clean' $big
    $r = Invoke-Tool $dir
    Equal $r.Exit 0 'S1: sixty agreeing quests pass'
    foreach ($shift in @(
            @{ Name = 'title'; Edit = { param($q) $q.Cache.Title = 'x' }; Line = 'title: 60 compared, 60 differ  [FAILED]' },
            @{ Name = 'sort'; Edit = { param($q) $q.Cache.Sort = 1 }; Line = 'sort: 60 compared, 60 differ  [FAILED]' },
            @{ Name = 'daily'; Edit = { param($q) $q.Cache.Flags = 0 }; Line = 'daily: 60 compared, 60 differ  [FAILED]' },
            @{ Name = 'questInfo'; Edit = { param($q) $q.Cache.Info = 1 }; Line = 'questInfo against the API: 60 compared, 60 differ  [FAILED]' },
            @{ Name = 'tuning'; Edit = { param($q) $q.Cache.Tuning = 13 }; Line = 'contentTuning against the client table: 60 compared, 60 differ  [FAILED]' },
            @{ Name = 'startItem'; Edit = { param($q) $q.Cache.StartItem = 1 }; Line = 'startItem against the client table: 60 compared, 60 differ  [FAILED]' },
            @{ Name = 'reputation'; Edit = { param($q) $q.Cache.Reps = @(, @(76, 1)) }; Line = 'reputation reward: 60 compared, 60 differ  [FAILED]' },
            @{ Name = 'recurs'; Edit = { param($q) $q.Cache.Recurs = 'weekly' }; Line = 'recurs: 60 compared, 60 differ  [FAILED]' },
            @{ Name = 'faction'; Edit = { param($q) $q.Cache.Faction = 'Horde' }; Line = 'faction: 60 compared, 60 differ  [FAILED]' },
            @{ Name = 'races'; Edit = { param($q) $q.Cache.Races = @(2, 5) }; Line = 'races: 60 compared, 60 differ  [FAILED]' })) {
        $world = @{}
        foreach ($id in 1..60) {
            $world[$id] = @{ Cache = @{} + $big[$id].Cache; Api = $big[$id].Api; Cli = $big[$id].Cli }
            & $shift.Edit $world[$id]
        }
        $dir = Write-World ("shift-" + $shift.Name) $world
        $r = Invoke-Tool $dir
        Equal $r.Exit 1 "S2: $($shift.Name): sixty differences fail the run"
        Has $r.Text $shift.Line "S2: $($shift.Name): the check says FAILED"
        Has $r.Text 'FAILED: do not use the cache''s values this sweep' "S2: $($shift.Name): and the run says what to do"
    }
    $world = @{}
    foreach ($id in 1..60) { $world[$id] = @{ Cache = @{} + $big[$id].Cache; Api = @{} + $big[$id].Api; Cli = $big[$id].Cli } }
    $world[1].Api.Min = 1; $world[1].Api.Max = 5
    $dir = Write-World 'oddone' $world
    $r = Invoke-Tool $dir
    Equal $r.Exit 0 'S5: one quest of sixty with a level range of its own is a hotfix, not a failure'
    Has $r.Text 'one level range per content tuning: 60 compared, 1 differ  [differs]' 'S5: it is the odd one that is counted, whichever quest has the lowest id'
    Has $r.Text '1 tuning 12 gives 1-5, but quest 2 gives 7-30' 'S5: and named against the range the rest agree on'
    $world[1].Api.Min = 7; $world[1].Api.Max = 30
    foreach ($id in 1..5) { $world[$id].Cache.Sort = 1 }
    $dir = Write-World 'limit5' $world
    $r = Invoke-Tool $dir
    Equal $r.Exit 0 'S3: five differences are still a hotfix, not a shift'
    foreach ($id in 1..6) { $world[$id].Cache.Sort = 1 }
    $dir = Write-World 'limit6' $world
    $r = Invoke-Tool $dir
    Equal $r.Exit 1 'S3: six are not'
    Has $r.Text 'sort: 60 compared, 6 differ  [FAILED]' 'S3: and say so'
    Equal @($r.Text -split "`n" | Where-Object { $_ -match '^\s+\d+ cache 1, API 331$' }).Count 5 'S3: with five examples, not six'
    $dir = Write-World 'examples2' $world
    $r = Invoke-Tool $dir @{ Examples = 2 }
    Equal @($r.Text -split "`n" | Where-Object { $_ -match '^\s+\d+ cache 1, API 331$' }).Count 2 'S3: -Examples changes how many'

    $huge = @{}
    foreach ($id in 1..1100) {
        $huge[$id] = @{ Cache = @{ Title = "Q$id"; Tuning = 12; Sort = 331; QuestType = 2 }; Api = @{ Title = "Q$id"; Area = 331; Min = 7; Max = 30 } }
    }
    foreach ($id in 1..6) { $huge[$id].Cache.Sort = 1 }
    $dir = Write-World 'huge' $huge
    $r = Invoke-Tool $dir @{ MinCompared = 1 }
    Has $r.Text 'sort: 1,100 compared, 6 differ  [FAILED]' 'S4: below 1,100 quests the limit stays 5, so six differences fail'
    $huge2 = @{}
    foreach ($id in 1..2200) { $huge2[$id] = @{ Cache = @{ Title = "Q$id"; Tuning = 12; Sort = $(if ($id -le 10) { 1 } else { 331 }); QuestType = 2 }; Api = @{ Title = "Q$id"; Area = 331; Min = 7; Max = 30 } } }
    $dir = Write-World 'huge2' $huge2
    $r = Invoke-Tool $dir
    Has $r.Text 'sort: 2,200 compared, 10 differ  [differs]' 'S4: ten differences in 2,200 quests are 0.45%: listed, not failed'

    # --- Refusals and what is not compared ---------------------------------------------------------------
    $dir = Write-World 'few' (New-Base)
    $r = Invoke-Tool $dir @{ MinCompared = 6 }
    Equal $r.Exit 1 'M1: fewer quests compared than -MinCompared fails the run'
    Has $r.Text 'only 5 compared, fewer than -MinCompared 6: is the API cache or the quest cache complete?' 'M1: and says why, for the check that compared fewest'
    $dir = Write-World 'default-min' (New-Base)
    $r = Invoke-Tool $dir @{ MinCompared = $null }
    Equal $r.Exit 1 'M1: the default -MinCompared is 20,000, far more than a small cache has'
    Has $r.Text 'fewer than -MinCompared 20000: is the API cache or the quest cache complete?' 'M1: and the message names it'
    $dir = Write-World 'few-ok' (New-Base)
    $r = Invoke-Tool $dir @{ MinCompared = 5 }
    Equal $r.Exit 0 'M1: exactly -MinCompared is enough'

    $dir = Write-World 'noV2' (New-Base) @{ NoQuestV2 = $true }
    $r = Invoke-Tool $dir
    Equal $r.Exit 0 'M2: without QuestV2 the other checks still pass'
    Lacks $r.Text 'repeatable: ' 'M2: there is no repeatable line'
    Has $r.Text "Not compared: 1 quest the API has no record of (1 of them in the client's task table); repeatable (no $dir\QuestV2-$Build.csv)." 'M2: and the closing line says so'
    $dir = Write-World 'clean2' (New-Base)
    $r = Invoke-Tool $dir
    Has $r.Text "Not compared: 1 quest the API has no record of (1 of them in the client's task table)." 'M2: a full run still names the quests the API has no record of'
    $world = New-Base
    $world[7].Api = @{ Title = 'Eta'; Area = 7; Min = 33; Max = 40 }
    $world[7].Cache.Title = 'Eta'
    $dir = Write-World 'allhaveapi' $world
    $r = Invoke-Tool $dir
    Lacks $r.Text 'Not compared:' 'M2: when every quest has an API record and every file is there, nothing is left out'

    $world = New-Base
    $world[1].Api.Namespace = '12.1.0_68000'
    $dir = Write-World 'twobuilds' $world
    $r = Invoke-Tool $dir
    Has $r.Text 'with an API record (build 12.1.0_68000, 12.1.0_68914)' 'M3: two API builds are both named'
    Has $r.Text 'the API cache holds more than one build' 'M3: and the closing line says so'

    $empty = Join-Path $Scratch 'empty'
    New-Item -ItemType Directory $empty | Out-Null
    $r = Invoke-Tool $empty
    Has $r.Failure 'No retail_quest_cache_<build>.jsonl under' 'M4: no cache at all is refused'
    $dir = Write-World 'noapi' (New-Base)
    Remove-Item "$dir\quest_api_cache" -Recurse -Force
    $r = Invoke-Tool $dir
    Has $r.Failure 'run Audit-QuestAccuracy.ps1 (step 1) first' 'M4: no API cache is refused'
    $dir = Write-World 'nocli' (New-Base)
    Remove-Item "$dir\QuestV2CliTask.csv"
    $r = Invoke-Tool $dir
    Has $r.Failure 'run Get-WagoQuestRequirements.ps1 (step 1b) first' 'M4: no task table is refused'
    $dir = Write-World 'allfour' (New-Base)
    Get-ChildItem "$dir\quest_api_cache" | Remove-Item -Force
    $r = Invoke-Tool $dir
    Equal $r.Exit 1 'M5: an API cache with no records fails the run'
    Has $r.Text 'title: nothing compared  [FAILED]' 'M5: naming what it could not compare'
    foreach ($name in 'sort', 'daily', 'weekly', 'recurs', 'faction', 'races', 'reputation reward', 'one level range per content tuning', 'questInfo against the API') { Has $r.Text "${name}: nothing compared  [FAILED]" "M5: and $name too" }

    $world = New-Base
    $world[1].Cli = $null; $world[7].Cli = $null
    $dir = Write-World 'emptytable' $world
    $r = Invoke-Tool $dir
    Equal $r.Exit 1 'M5: a client task table with no rows fails the run'
    foreach ($name in 'questInfo against the client table', 'contentTuning against the client table', 'startItem against the client table') { Has $r.Text "${name}: nothing compared  [FAILED]" "M5: $name is named" }
    foreach ($case in @(
            @{ Name = 'reputation'; Edit = { param($q) $q.Api.Reps = $null }; Line = 'reputation reward: nothing compared  [FAILED]' },
            @{ Name = 'type'; Edit = { param($q) $q.Api.Remove('Type') }; Line = 'questInfo against the API: nothing compared  [FAILED]' },
            @{ Name = 'faction'; Edit = { param($q) $q.Api.Remove('Faction') }; Line = 'faction: nothing compared  [FAILED]' },
            @{ Name = 'races'; Edit = { param($q) $q.Api.Remove('Races') }; Line = 'races: nothing compared  [FAILED]' })) {
        $world = New-Base
        foreach ($id in @($world.Keys)) { if ($world[$id].Api) { & $case.Edit $world[$id] } }
        $dir = Write-World ("none-" + $case.Name) $world
        $r = Invoke-Tool $dir
        Equal $r.Exit 1 "M5: an API cache with no $($case.Name) at all fails the run"
        Has $r.Text $case.Line "M5: and names it"
    }
    $world = New-Base
    $world[9] = @{ Cache = @{ Title = 'Iota'; Tuning = 12; Sort = 0; StartItem = 5; QuestType = 2 }; Cli = @(0, 12, 0) }
    $dir = Write-World 'zerotable' $world
    $r = Invoke-Tool $dir
    Equal $r.Exit 0 'M5: a start item against a task table of 0 is one difference'
    Has $r.Text 'startItem against the client table: 3 compared, 1 differ  [differs]' 'M5: counted'
    Has $r.Text '9 cache 5, table 0' 'M5: and named'
    Has $r.Text "Not compared: 2 quests the API has no record of (2 of them in the client's task table)." 'M5: the quests with no API record are counted by their .404 files'
    $dir = Write-World 'partialapi' (New-Base)
    Remove-Item "$dir\quest_api_cache\8.json"
    $r = Invoke-Tool $dir
    Has $r.Text 'Not compared: 1 quest the API has no record of (1 of them in the client''s task table); 1 quest not in the API cache or not recognised in it.' 'M5: a quest with neither a record nor a .404 is said to be missing from the API cache, not to have no record'

    $dir = Write-World 'twocaches' (New-Base)
    Copy-Item "$dir\retail_quest_cache_$Build.jsonl" "$dir\retail_quest_cache_12.1.0.9.jsonl"
    [IO.File]::WriteAllText("$dir\retail_quest_cache_12.1.0.9.jsonl", "", $utf8)
    [IO.File]::WriteAllText("$dir\retail_quest_cache_notabuild.jsonl", "", $utf8)
    $r = Invoke-Tool $dir
    Has $r.Text 'Cache retail_quest_cache_12.1.0.69933.jsonl' 'M6: the newest build''s cache is the one read, by version and not by text, and a file that is no build is ignored'
    $r = Invoke-Tool $dir @{ Cache = "$dir\retail_quest_cache_12.1.0.9.jsonl" }
    Has $r.Text 'Cache retail_quest_cache_12.1.0.9.jsonl: 0 quests' 'M6: -Cache names another'
}
finally {
    [Threading.Thread]::CurrentThread.CurrentCulture = $savedCulture
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
