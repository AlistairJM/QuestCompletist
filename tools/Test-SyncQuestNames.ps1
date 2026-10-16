<#
Checks Sync-QuestNamesFromApi.ps1 (step 1c) in a scratch folder on made-up quests: nothing in the checkout is
touched and nothing is downloaded.

  N1  The order of the sources: the API's title wins wherever the API has a record, even over the quest cache's;
      a quest the API doesn't serve (.404) takes the newest quest cache's title, and the task table's only when
      that cache lacks it; an older cache isn't read; a quest with no API file at all keeps its name; a task row
      with no title titles nothing. Titles are copied exactly (two spaces, quotes), and the counts and listings
      say which source renamed what.
  N2  A title that starts with [DEPRECATED], in any case and from any source, is never taken, and is listed. The
      source that has the quest decides: the task table's title doesn't stand in for a cache's [DEPRECATED] one.
  N3  -WhatIf writes nothing; the real run renames exactly what it listed, the data passes the record checks and
      the Lua matches; a second run changes no byte.
  N4  -Build reads that cache instead of the newest. Missing caches and task table are named as skipped, and then
      the quests the API doesn't serve keep their names. Without the API cache, or with a -Build that has no
      cache, it stops and writes nothing. A cache holding under 90% of our quests is warned about.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncQuestNames.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
$Tool = Join-Path $PSScriptRoot 'Sync-QuestNamesFromApi.ps1'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Invoke-Tool([string[]]$arguments) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $Tool @arguments 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $saved }
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($output -join "`n") }
}
function Get-Hash([string]$path) { return (Get-FileHash $path -Algorithm SHA256).Hash }
function New-Folder([string]$path) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
function Write-Text([string]$path, [string[]]$lines) { [IO.File]::WriteAllText($path, (($lines | ForEach-Object { "$_`n" }) -join ''), $script:Utf8) }
function Quest-Row([int]$id) {
    return [pscustomobject][ordered]@{ id = $id; name = "Quest $id"; level = 10; zone = 'Somewhere'; category = 1; type = 1; faction = 3; race = 0; class = 8191 }
}
# The IDs listed under a heading of the tool's report ("Heading (N):" and lines "  <id>: ...").
function Listed([string]$text, [string]$heading) {
    $m = [regex]::Match($text, "(?m)^$([regex]::Escape($heading)) \(\d+\):\r?\n((?:  .*(?:\r?\n|$))*)")
    if (-not $m.Success) { return '(no heading)' }
    return (@([regex]::Matches($m.Groups[1].Value, '(?m)^  (\d+):') | ForEach-Object { $_.Groups[1].Value }) -join ',')
}
function Names([string]$dataDir) {
    $names = @{}
    foreach ($quest in (Read-QuestData $dataDir)) { $names[[int]$quest.id] = $quest.name }
    return $names
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("sync-quest-names-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Folder $Scratch

try {
    # 1001 API title                          1007 API title "[DEPRECATED]..."
    # 1002 API title equal to ours            1008 404, the task table's "[Deprecated] ..."
    # 1003 404, the cache's and a task title  1009 no API file, though the cache has it
    # 1004 404, a task title; only the older  1010 API title, and a cache title too
    #      cache has it                       1011 404, the cache's 'WANTED:  "Hogger"'
    # 1005 404, an empty task title; only     1012 404, the task table's 'Stef "Marrow" Quin'
    #      the older cache has it
    # 1006 404, the cache's "[DEPRECATED]..." and a task title
    $tools = "$Scratch\tools"; $data = "$Scratch\data"; $addon = "$Scratch\addon"; $api = "$tools\quest_api_cache"
    New-Folder $tools; New-Folder $data; New-Folder $addon; New-Folder $api
    Write-Text "$api\1001.json" '{"id":1001,"title":"Api Title 1001"}'
    Write-Text "$api\1002.json" '{"id":1002,"title":"Quest 1002"}'
    Write-Text "$api\1007.json" '{"id":1007,"title":"[DEPRECATED]Api Title 1007"}'
    Write-Text "$api\1010.json" '{"id":1010,"title":"Api Title 1010"}'
    foreach ($id in 1003, 1004, 1005, 1006, 1008, 1011, 1012) { Write-Text "$api\$id.404" @() }
    Write-Text "$tools\retail_quest_cache_9.9.9.99999.jsonl" '{"id":1002,"title":"Cache Title 1002"}', '{"id":1003,"title":"Cache Title 1003"}',
        '{"id":1006,"title":"[DEPRECATED]Cache Title 1006"}', '{"id":1009,"title":"Cache Title 1009"}', '{"id":1010,"title":"Cache Title 1010"}',
        '{"id":1011,"title":"WANTED:  \"Hogger\""}'
    Write-Text "$tools\retail_quest_cache_9.9.9.99998.jsonl" '{"id":1004,"title":"Old Cache Title 1004"}', '{"id":1005,"title":"Old Cache Title 1005"}'
    Write-Text "$tools\QuestV2CliTask.csv" 'ID,QuestTitle_lang,BulletText_lang', '1003,"Task Title 1003",', '1004,"Task Title 1004",', '1005,,',
        '1006,"Task Title 1006",', '1008,"[Deprecated] Task Title 1008",', '1012,"Stef ""Marrow"" Quin",'
    [IO.File]::WriteAllText("$data\quests.jsonl", (ConvertTo-QuestJsonLines @(1001..1012 | ForEach-Object { Quest-Row $_ })), $script:Utf8)
    [IO.File]::WriteAllText("$data\pins.jsonl", '{"map":84,"icon":1,"name":"Somebody","x":1.5,"y":2.5,"quests":[1001]}' + "`n", $script:Utf8)
    $built = Invoke-AddonDataBuild $data $addon
    if (-not $built.Ok) { throw ("The scratch Lua didn't build:`n" + ($built.Lines -join "`n")) }
    $common = @('-ToolsDir', $tools, '-DataDir', $data, '-AddonDir', $addon)
    $hashes = @{ Quests = Get-Hash "$data\quests.jsonl"; Lua = Get-Hash "$addon\qcQuestData.lua" }
    $cacheHeading = 'Renamed from the quest cache of 9.9.9.99999'
    $taskHeading = 'Renamed from the task table (QuestV2CliTask)'
    $notTakenHeading = 'Titles not taken, as they start with [DEPRECATED]'

    $report = Invoke-Tool ($common + '-WhatIf')
    Equal $report.Exit 0 "N1: -WhatIf succeeds ($($report.Text))"
    Check ($report.Text -match '(?m)^4 quests checked against the API: 2 renamed\.') "N1: four API titles, two of them new ($($report.Text))"
    Check ($report.Text -match '(?m)^7 quests the API doesn''t serve: 3 titled by the quest cache of 9\.9\.9\.99999 \(2 renamed\), 3 by the task table \(QuestV2CliTask\) \(2 renamed\), 1 by neither, which keep their names\.') "N1: the counts by source ($($report.Text))"
    Equal (Listed $report.Text 'Renamed from the API') '1001,1010' 'N1: the API wins wherever it has a record, over the cache too'
    Equal (Listed $report.Text $cacheHeading) '1003,1011' 'N1: the newest cache, over the task table'
    Equal (Listed $report.Text $taskHeading) '1004,1012' 'N1: the task table only where the newest cache lacks the quest'
    Equal (Listed $report.Text $notTakenHeading) '1006,1007,1008' 'N2: no [DEPRECATED] title is taken, from any source'
    Check ($report.Text -match '(?m)^  1006: Quest 1006 keeps its name; the quest cache of 9\.9\.9\.99999 has \[DEPRECATED\]Cache Title 1006$') "N2: the cache's title is named, not the task table's ($($report.Text))"
    Check ($report.Text -match '(?m)^  1011: Quest 1011 -> WANTED:  "Hogger"$') "N1: the title as it is ($($report.Text))"
    Check ($report.Text -match '(?m)^WhatIf: nothing changed\.$') 'N3: -WhatIf says it changed nothing'
    Equal (Get-Hash "$data\quests.jsonl") $hashes.Quests 'N3: -WhatIf writes nothing'
    Equal (Get-Hash "$addon\qcQuestData.lua") $hashes.Lua 'N3: not even the Lua'
    Check ($report.Text -match '(?m)^WARNING: retail_quest_cache_9\.9\.9\.99999\.jsonl looks partial, .*: 6 of our 12 \(') "N4: a cache with half our quests is warned about ($($report.Text))"
    Check ($report.Text -notmatch 'Skipped') "N4: with every source there, none is named as skipped ($($report.Text))"

    $run = Invoke-Tool $common
    Equal $run.Exit 0 "N3: the run succeeds ($($run.Text))"
    $names = Names $data
    $expected = @{ 1001 = 'Api Title 1001'; 1002 = 'Quest 1002'; 1003 = 'Cache Title 1003'; 1004 = 'Task Title 1004'; 1005 = 'Quest 1005'
        1006 = 'Quest 1006'; 1007 = 'Quest 1007'; 1008 = 'Quest 1008'; 1009 = 'Quest 1009'; 1010 = 'Api Title 1010'
        1011 = 'WANTED:  "Hogger"'; 1012 = 'Stef "Marrow" Quin' }
    foreach ($id in ($expected.Keys | Sort-Object)) { Equal $names[$id] $expected[$id] "N3: $id's name after the run" }
    $problems = @(Test-QuestRecords (Read-QuestData $data))
    Equal $problems.Count 0 "N3: every record passes Test-QuestRecords ($($problems -join '; '))"
    Check (Invoke-AddonDataBuild $data $addon -Check).Ok 'N3: qcQuestData.lua matches the data'
    $after = @{ Quests = Get-Hash "$data\quests.jsonl"; Lua = Get-Hash "$addon\qcQuestData.lua" }
    $again = Invoke-Tool $common
    Check ($again.Exit -eq 0 -and $again.Text -match '(?m)^4 quests checked against the API: 0 renamed\.' -and
        $again.Text -match '\(0 renamed\), 3 by the task table \(QuestV2CliTask\) \(0 renamed\)') "N3: a second run has nothing to rename ($($again.Text))"
    Equal (Listed $again.Text $notTakenHeading) '1006,1007,1008' 'N3: and still lists the titles not taken'
    Equal (Get-Hash "$data\quests.jsonl") $after.Quests 'N3: and changes no byte of quests.jsonl'
    Equal (Get-Hash "$addon\qcQuestData.lua") $after.Lua 'N3: or of the Lua'

    # The same quests, as they were, for the runs on other sources.
    [IO.File]::WriteAllText("$data\quests.jsonl", (ConvertTo-QuestJsonLines @(1001..1012 | ForEach-Object { Quest-Row $_ })), $script:Utf8)
    $built = Invoke-AddonDataBuild $data $addon
    if (-not $built.Ok) { throw ("The scratch Lua didn't build again:`n" + ($built.Lines -join "`n")) }

    $older = Invoke-Tool ($common + @('-Build', '9.9.9.99998', '-WhatIf'))
    Equal $older.Exit 0 "N4: a run on an older -Build succeeds ($($older.Text))"
    Check ($older.Text -match '(?m)^7 quests the API doesn''t serve: 2 titled by the quest cache of 9\.9\.9\.99998 \(2 renamed\), 4 by the task table \(QuestV2CliTask\) \(3 renamed\), 1 by neither') "N4: the counts on the older cache ($($older.Text))"
    Equal (Listed $older.Text 'Renamed from the quest cache of 9.9.9.99998') '1004,1005' 'N4: -Build reads that cache'
    Equal (Listed $older.Text $taskHeading) '1003,1006,1012' 'N4: and the quests it lacks fall to the task table'
    Equal (Listed $older.Text $notTakenHeading) '1007,1008' 'N4: where a [DEPRECATED] title is still not taken'

    $bare = "$Scratch\bare-tools"
    New-Folder "$bare\quest_api_cache"
    Copy-Item "$api\*" "$bare\quest_api_cache"
    $alone = Invoke-Tool @('-ToolsDir', $bare, '-DataDir', $data, '-AddonDir', $addon, '-WhatIf')
    Equal $alone.Exit 0 "N4: a run with the API cache alone succeeds ($($alone.Text))"
    Check ($alone.Text -match "(?m)^Skipped, as it's missing: the retail quest cache") "N4: the missing quest cache is named ($($alone.Text))"
    Check ($alone.Text -match "(?m)^Skipped, as it's missing: the task table") "N4: the missing task table is named ($($alone.Text))"
    Check ($alone.Text -match '(?m)^7 quests the API doesn''t serve: 0 titled by the quest cache \(0 renamed\), 0 by .* 7 by neither, which keep their names\.') "N4: and the quests the API doesn't serve keep their names ($($alone.Text))"
    Equal (Listed $alone.Text 'Renamed from the API') '1001,1010' 'N4: the API still renames'

    $lua = Get-Hash "$addon\qcQuestData.lua"; $quests = Get-Hash "$data\quests.jsonl"
    $noApi = Invoke-Tool @('-ToolsDir', "$Scratch\no-tools", '-DataDir', $data, '-AddonDir', $addon)
    Check ($noApi.Exit -ne 0 -and $noApi.Text -match 'run Audit-QuestAccuracy\.ps1') "N4: without the API cache it stops ($($noApi.Text))"
    $noBuild = Invoke-Tool ($common + @('-Build', '9.9.9.99997'))
    Check ($noBuild.Exit -ne 0 -and $noBuild.Text -match "There's no .*retail_quest_cache_9\.9\.9\.99997\.jsonl") "N4: a -Build with no cache stops ($($noBuild.Text))"
    Equal (Get-Hash "$data\quests.jsonl") $quests 'N4: and neither writes the data'
    Equal (Get-Hash "$addon\qcQuestData.lua") $lua 'N4: or the Lua'
} finally {
    if (Test-Path $Scratch) { Remove-Item $Scratch -Recurse -Force }
}

Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
