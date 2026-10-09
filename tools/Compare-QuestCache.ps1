<#
Checks that Read-QuestCache.ps1 still reads retail's quest cache right. The reader walks every record
to its last byte, but a layout that moves one field for another of the same size would still walk, and
every value would be wrong. So the cache's values are compared with what Blizzard's own data says about
the same quests:

  - Blizzard's API records (tools\quest_api_cache, the sweep's step 1): title, sort (the API's area or,
    as a negative number, its category), questInfo (the API's type), daily, weekly and repeatable (the
    API's is_daily, is_weekly and is_repeatable), the reputation amounts, and that each content tuning
    gives one level range;
  - the client's task table (tools\QuestV2CliTask.csv, step 1b): questInfo, contentTuning and startItem.

Those two sources are Blizzard's, not the cache's, so a shift shows as thousands of differences. A few
differences are what a hotfix between the API's build and the cache's looks like; they are listed and
don't fail the run. It fails when a check differs for more than 0.5% of what it compared (and at least
5), when it compared fewer quests than -MinCompared, or when the cache can't be found.

The baseline on 9 October 2026 (cache 12.1.0.69933, API 12.1.0_68914) is in docs\maintenance.md,
step 2d. Exit 0 is a clean run, 1 a failed one.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$Cache = "",
    [int]$MinCompared = 20000,
    [int]$Examples = 5
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"

if (-not $Cache) {
    $newest = Get-ChildItem "$ToolsDir\retail_quest_cache_*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match '^retail_quest_cache_\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object { [version]($_.BaseName -replace '^retail_quest_cache_') } | Select-Object -Last 1
    if (-not $newest) { throw "No retail_quest_cache_<build>.jsonl under ${ToolsDir}: run Read-QuestCache.ps1 -Build <retail build> first." }
    $Cache = $newest.FullName
}
$build = ((Split-Path $Cache -Leaf) -replace '^retail_quest_cache_', '' -replace '\.jsonl$', '')
$apiDir = "$ToolsDir\quest_api_cache"
if (-not (Test-Path $apiDir)) { throw "No ${apiDir}: run Audit-QuestAccuracy.ps1 (step 1) first." }
$cliFile = "$ToolsDir\QuestV2CliTask.csv"
if (-not (Test-Path $cliFile)) { throw "No ${cliFile}: run Get-WagoQuestRequirements.ps1 (step 1b) first." }

$quests = @{}
foreach ($line in [IO.File]::ReadAllLines($Cache, (New-Object Text.UTF8Encoding $false))) {
    if (-not $line) { continue }
    $q = $line | ConvertFrom-Json
    $quests[[int]$q.id] = $q
}
$cli = @{}
foreach ($row in Import-Csv $cliFile) { $cli[[int]$row.ID] = $row }
$questV2 = $null
$questV2File = "$ToolsDir\QuestV2-$build.csv"
if (Test-Path $questV2File) {
    $questV2 = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($row in Import-Csv $questV2File) { [void]$questV2.Add([int]$row.ID) }
}

$checks = [ordered]@{}
function Note-Check([string]$name, [bool]$equal, [string]$example) {
    if (-not $checks.Contains($name)) { $checks[$name] = @{ Compared = 0; Differ = 0; Examples = New-Object System.Collections.Generic.List[string] } }
    $c = $checks[$name]
    $c.Compared++
    if (-not $equal) {
        $c.Differ++
        if ($c.Examples.Count -lt $Examples) { $c.Examples.Add($example) }
    }
}

$stringRx = '"(?:[^"\\]|\\.)*"'
$titleRx = New-Object Text.RegularExpressions.Regex ('^\{"_links":\{"self":\{"href":"[^"]*namespace=static-([^"]*?)-[a-z]+"\}\},"id":(\d+),"title":(' + $stringRx + ')')
$areaRx = New-Object Text.RegularExpressions.Regex ('"area":\{"key":\{[^}]*\},"name":' + $stringRx + ',"id":(\d+)\}')
$categoryRx = New-Object Text.RegularExpressions.Regex ('"category":\{"key":\{[^}]*\},"name":' + $stringRx + ',"id":(\d+)\}')
$typeRx = New-Object Text.RegularExpressions.Regex ('"type":\{"key":\{[^}]*\},"name":' + $stringRx + ',"id":(\d+)\}')
$minRx = New-Object Text.RegularExpressions.Regex '"min_character_level":(\d+),"max_character_level":(\d+)'
$rewardRx = New-Object Text.RegularExpressions.Regex ('"reward":\{"key":\{"href":"[^"]*/reputation-faction/\d+[^"]*"\},"name":' + $stringRx + ',"id":(\d+)\},"value":(-?\d+)')

$apiBuilds = @{}
$withApi = 0
$tuningLevels = @{}
foreach ($id in ($quests.Keys | Sort-Object)) {
    $q = $quests[$id]
    $file = "$apiDir\$id.json"
    if (Test-Path $file) {
        $text = [IO.File]::ReadAllText($file)
        $head = $titleRx.Match($text)
        if ($head.Success) {
            $withApi++
            $apiBuilds[$head.Groups[1].Value] = 1 + [int]$apiBuilds[$head.Groups[1].Value]
            $title = [regex]::Unescape($head.Groups[3].Value.Substring(1, $head.Groups[3].Value.Length - 2))
            Note-Check 'title' ($title -ceq $q.title) "$id cache '$($q.title)', API '$title'"

            $area = $areaRx.Match($text); $category = $categoryRx.Match($text)
            if ($area.Success -or $category.Success) {
                $apiSort = if ($area.Success) { [int]$area.Groups[1].Value } else { -[int]$category.Groups[1].Value }
                Note-Check 'sort' ($apiSort -eq [int]$q.sort) "$id cache $($q.sort), API $apiSort"
            }
            $type = $typeRx.Match($text)
            if ($type.Success) { Note-Check 'questInfo against the API' ([int]$type.Groups[1].Value -eq [int]$q.questInfo) "$id cache $([int]$q.questInfo), API $($type.Groups[1].Value)" }

            $flags = [long]$q.flags; $flagsEx = [long]$q.flagsEx
            $daily = [bool](($flags -band 0x1000) -or ($flagsEx -band 0x8000))
            $weekly = [bool]($flags -band 0x8000)
            Note-Check 'daily' ($daily -eq $text.Contains('"is_daily":true')) "$id cache daily=$daily, API is_daily=$($text.Contains('"is_daily":true'))"
            Note-Check 'weekly' ($weekly -eq $text.Contains('"is_weekly":true')) "$id cache weekly=$weekly, API is_weekly=$($text.Contains('"is_weekly":true'))"
            if ($questV2) {
                $repeatable = [bool]([int]$q.questType -eq 0 -and -not $questV2.Contains($id))
                Note-Check 'repeatable' ($repeatable -eq $text.Contains('"is_repeatable":true')) "$id cache repeatable=$repeatable, API is_repeatable=$($text.Contains('"is_repeatable":true'))"
            }

            $levels = $minRx.Match($text)
            if ($levels.Success) {
                $pair = $levels.Groups[1].Value + '-' + $levels.Groups[2].Value
                $tuning = [int]$q.contentTuning
                if (-not $tuningLevels.ContainsKey($tuning)) { $tuningLevels[$tuning] = @{ Pair = $pair; Quest = $id; Equal = $true } }
                else {
                    $t = $tuningLevels[$tuning]
                    if ($t.Pair -ne $pair) { $t.Equal = $false }
                    Note-Check 'one level range per content tuning' ($t.Pair -eq $pair) "$id tuning $tuning gives $pair, but quest $($t.Quest) gives $($t.Pair)"
                }
            }

            $apiRewards = @{}
            foreach ($m in $rewardRx.Matches($text)) { $apiRewards[[int]$m.Groups[1].Value] = [int]$m.Groups[2].Value }
            if ($apiRewards.Count) {
                $mine = @{}
                foreach ($pair in @($q.reputation)) { if ($pair) { $mine[[int]$pair[0]] = [int]$pair[1] } }
                foreach ($faction in $apiRewards.Keys) {
                    $same = $mine.ContainsKey($faction) -and $mine[$faction] -eq $apiRewards[$faction]
                    Note-Check 'reputation reward' $same "$id faction ${faction}: cache $(if ($mine.ContainsKey($faction)) { $mine[$faction] } else { 'none' }), API $($apiRewards[$faction])"
                }
            }
        }
    }
    if ($cli.ContainsKey($id)) {
        $row = $cli[$id]
        Note-Check 'questInfo against the client table' ([int]$q.questInfo -eq [int]$row.QuestInfoID) "$id cache $([int]$q.questInfo), table $($row.QuestInfoID)"
        Note-Check 'contentTuning against the client table' ([int]$q.contentTuning -eq [int]$row.ContentTuningID) "$id cache $([int]$q.contentTuning), table $($row.ContentTuningID)"
        Note-Check 'startItem against the client table' ([long]$q.startItem -eq [long]$row.StartItem) "$id cache $([long]$q.startItem), table $($row.StartItem)"
    }
}

$failed = $false
Write-Output ("Cache {0}: {1} quests, {2} with an API record (build {3}), {4} in the client's task table." -f
    (Split-Path $Cache -Leaf), $quests.Count, $withApi, (($apiBuilds.Keys | Sort-Object) -join ', '), @($quests.Keys | Where-Object { $cli.ContainsKey($_) }).Count)
foreach ($name in $checks.Keys) {
    $c = $checks[$name]
    $limit = [Math]::Max(5, [int][Math]::Floor($c.Compared * 0.005))
    $verdict = if ($c.Differ -gt $limit) { $failed = $true; 'FAILED' } elseif ($c.Differ -gt 0) { 'differs' } else { 'ok' }
    Write-Output ("  {0}: {1:N0} compared, {2:N0} differ  [{3}]" -f $name, $c.Compared, $c.Differ, $verdict)
    foreach ($example in $c.Examples) { Write-Output "      $example" }
    if ($c.Compared -lt $MinCompared -and $name -in 'title', 'sort', 'daily') {
        Write-Output "      only $($c.Compared) compared, fewer than -MinCompared ${MinCompared}: is the API cache complete?"
        $failed = $true
    }
}
foreach ($required in 'title', 'sort', 'questInfo against the API', 'daily', 'weekly', 'reputation reward', 'questInfo against the client table', 'contentTuning against the client table', 'startItem against the client table') {
    if (-not $checks.Contains($required)) { Write-Output "  ${required}: nothing compared  [FAILED]"; $failed = $true }
}
$notCompared = @()
$noApi = $quests.Count - $withApi
if ($noApi -gt 0) {
    $inTable = @($quests.Keys | Where-Object { $cli.ContainsKey($_) -and -not (Test-Path "$apiDir\$_.json") }).Count
    $notCompared += "{0} {1} the API has no record of ({2} of them in the client's task table)" -f $noApi, $(if ($noApi -eq 1) { 'quest' } else { 'quests' }), $inTable
}
if (-not $questV2) { $notCompared += "repeatable (no $questV2File)" }
if ($apiBuilds.Count -gt 1) { $notCompared += "the API cache holds more than one build" }
if ($notCompared) { Write-Output ("Not compared: {0}." -f ($notCompared -join '; ')) }
Write-Output "The values here are Blizzard's own: a shift in the reader's field numbers would show as thousands of differences, a hotfix between the builds as a few."
if ($failed) { Write-Output "FAILED: do not use the cache's values this sweep; see docs\maintenance.md, step 2d."; exit 1 }
exit 0
