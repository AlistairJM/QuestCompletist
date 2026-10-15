<#
Checks Sync-QuestPvP.ps1 in a scratch folder on a made-up world: nothing in the checkout is touched and nothing
is downloaded.

  F  WoW: Forever: a quest cache, an older one, an answer memory, a CMaNGOS dump, removal decisions and data.
     A quest the game answered only on an earlier build takes its tag from the answer memory, as the importer
     does: kept from the memory's record (PvP or not, and the game's "not PvP" stands over CMaNGOS), already
     tagged and so not listed as having pvp with no source, held by a KEEP decision past -MaxMissedRuns, and
     left to CMaNGOS once it has missed -MaxMissedRuns runs or has a REMOVE decision. The newest cache wins
     over the memory, an older cache isn't read, and without the memory, which is named as skipped, a kept
     quest has no answer. -WhatIf writes nothing; the real run tags exactly the quests the report named, the
     data passes the record checks and the Lua matches, the memory is never written, and a second run changes
     no byte. A memory whose last run is behind the cache's build, or ahead of it, is named.
  R  Retail: an answer memory beside retail's data is not read or named.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncQuestPvP.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
$Tool = Join-Path $PSScriptRoot 'Sync-QuestPvP.ps1'
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
function Quest-Row([int]$id, [switch]$Pvp) {
    $q = [pscustomobject][ordered]@{ id = $id; name = "Quest $id"; level = 10; zone = 'Somewhere'; category = 1; type = 1; faction = 3; race = 0; class = 8191 }
    if ($Pvp) { Set-RecordField $q 'pvp' 1 }
    return $q
}
function Answer([int]$id, [int]$missed, [int]$kind) {
    $record = '{"id":' + $id + ',"title":"Quest ' + $id + '"' + $(if ($kind) { ',"questInfo":' + $kind } else { '' }) + '}'
    return '{"id":' + $id + ',"seen":"9.9.9.99998","missed":' + $missed + ',"record":' + $record + '}'
}
# The IDs listed under a heading of the tool's report ("Heading (N)...:" and lines "  <id> ...").
function Listed([string]$text, [string]$heading) {
    $m = [regex]::Match($text, "(?m)^$([regex]::Escape($heading)) \(\d+\)[^\r\n]*\r?\n((?:  .*(?:\r?\n|$))*)")
    if (-not $m.Success) { return '' }
    return (@([regex]::Matches($m.Groups[1].Value, '(?m)^  (\d+) ') | ForEach-Object { $_.Groups[1].Value }) -join ',')
}
function Tagged([string]$dataDir) { return (@(Read-QuestData $dataDir | Where-Object { $_.pvp } | ForEach-Object { $_.id }) -join ',') }
function Write-Dump([string]$path, $rows) {
    $sql = 'INSERT INTO `quest_template` VALUES ' + (($rows | ForEach-Object { "($($_[0]),0,10,5,0,0,$($_[1]),0,'Quest $($_[0])')" }) -join ',') + ";`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($sql)
    $stream = [IO.File]::Create($path)
    $gzip = New-Object System.IO.Compression.GZipStream($stream, [IO.Compression.CompressionMode]::Compress)
    $gzip.Write($bytes, 0, $bytes.Length)
    $gzip.Close(); $stream.Close()
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("sync-quest-pvp-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Folder $Scratch

try {
    $pvpDecisions = "$Scratch\quest-pvp-decisions.csv"
    Write-Text $pvpDecisions '"Game","QuestID","Name","Decision","Evidence"'
    $removals = "$Scratch\quest-removal-decisions.csv"
    Write-Text $removals 'Game,Quest,Decision,Reason', 'forever,3005,KEEP,kept by hand', 'forever,3006,REMOVE,agreed', 'retail,3002,REMOVE,the other game''s row'

    # --- F: WoW: Forever ------------------------------------------------------------------------
    # 3001 the newest cache says PvP           3006 PvP in the memory, missed 1, REMOVE: CMaNGOS says PvP
    # 3002 PvP in the memory, missed 1          3007 not PvP in the memory, missed 1: CMaNGOS says PvP
    # 3003 not PvP in the memory, missed 10:    3008 the newest cache says not PvP, the memory says PvP
    #      CMaNGOS says PvP                     3009 PvP in the memory, missed 1, already has pvp
    # 3004 PvP in the memory, missed 10, and    3010 has pvp, and no source answers
    #      in the older cache; nothing else
    # 3005 PvP in the memory, missed 10, KEEP: CMaNGOS says not
    $tools = "$Scratch\tools"; $data = "$Scratch\forever"; $addon = "$Scratch\addon"
    New-Folder $tools; New-Folder $data; New-Folder $addon
    Write-Text "$tools\forever_quest_cache_9.9.9.99999.jsonl" '{"id":3001,"title":"Quest 3001","questInfo":41}', '{"id":3008,"title":"Quest 3008"}'
    Write-Text "$tools\forever_quest_cache_9.9.9.99998.jsonl" '{"id":3004,"title":"Quest 3004","questInfo":41}'
    Write-Dump "$tools\ClassicDB_test.sql.gz" @(@(3001, 0), @(3003, 41), @(3005, 0), @(3006, 41), @(3007, 41))
    Write-Text "$data\answers.jsonl" '{"runs":["9.9.9.99998","9.9.9.99999"]}', (Answer 3002 1 41), (Answer 3003 10 0), (Answer 3004 10 41),
        (Answer 3005 10 41), (Answer 3006 1 41), (Answer 3007 1 0), (Answer 3008 0 41), (Answer 3009 1 41)
    $quests = @(3001..3008 | ForEach-Object { Quest-Row $_ }) + @((Quest-Row 3009 -Pvp), (Quest-Row 3010 -Pvp))
    [IO.File]::WriteAllText("$data\quests.jsonl", (ConvertTo-QuestJsonLines $quests), $script:Utf8)
    [IO.File]::WriteAllText("$data\pins.jsonl", '{"map":1429,"icon":1,"name":"Somebody","x":1.5,"y":2.5,"quests":[3001]}' + "`n", $script:Utf8)
    $built = Invoke-AddonDataBuild $data $addon
    if (-not $built.Ok) { throw ("The scratch Lua didn't build:`n" + ($built.Lines -join "`n")) }
    $common = @('-Game', 'forever', '-ToolsDir', $tools, '-DataDir', $data, '-AddonDir', $addon, '-DecisionsFile', $pvpDecisions, '-RemovalDecisionsFile', $removals)
    $hashes = @{ Quests = Get-Hash "$data\quests.jsonl"; Lua = Get-Hash "$addon\qcQuestData.lua"; Answers = Get-Hash "$data\answers.jsonl" }

    $report = Invoke-Tool ($common + '-WhatIf')
    Equal $report.Exit 0 "F1: -WhatIf succeeds ($($report.Text))"
    Check ($report.Text -match "(?m)^Build 9\.9\.9\.99999 \(forever\): the game's cache has 2 quests, and the answer memory 4 more it answered on an earlier build; no source answers for 2 of ours\.") "F1: it reads the newest cache and keeps four quests from the memory ($($report.Text))"
    Check ($report.Text -match '(?m)^Read: the game 6, .*CMaNGOS 5\.') 'F1: the kept answers count as the game''s'
    Check ($report.Text -notmatch 'Not found, skipped|last run') "F1: with the memory of the cache's build, nothing is named as missing or out of step ($($report.Text))"
    Check ($report.Text -match '(?m)^5 quests get pvp \(the game 3, CMaNGOS 2\), 1 already have it\.') "F1: five get pvp, three by the game and two by CMaNGOS ($($report.Text))"
    Equal (Listed $report.Text 'Would set pvp on') '3001,3002,3003,3005,3006' 'F1: the newest cache, a kept quest, a KEEP past the missed runs, and CMaNGOS for a quest let go'
    Equal (Listed $report.Text 'Has pvp, but no source calls the quest PvP') '3010' 'F2: a kept PvP quest that has pvp is not listed as having no source; one with no source is'
    Equal (Listed $report.Text "A source calls the quest PvP but the game's record says another kind") '3007' 'F3: a kept "not PvP" stands over CMaNGOS'
    Equal (Get-Hash "$data\quests.jsonl") $hashes.Quests 'F4: -WhatIf writes nothing'
    Equal (Get-Hash "$addon\qcQuestData.lua") $hashes.Lua 'F4: not even the Lua'

    $noMemory = Invoke-Tool ($common + @('-AnswerFile', "$Scratch\none.jsonl", '-WhatIf'))
    Equal $noMemory.Exit 0 "F5: a run without the memory succeeds ($($noMemory.Text))"
    Check ($noMemory.Text -match "the game's cache has 2 quests, and the answer memory 0 more") 'F5: and keeps nothing'
    Check ($noMemory.Text -match '(?m)^Read: .*Not found, skipped: .*answer memory') "F5: it names the memory as skipped ($($noMemory.Text))"
    Check ($noMemory.Text -notmatch 'last run') 'F5: and not as out of step'
    Equal (Listed $noMemory.Text 'Has pvp, but no source calls the quest PvP') '3009,3010' 'F5: so a kept PvP quest is left without a source'
    Equal (Listed $noMemory.Text 'Would set pvp on') '3001,3003,3006,3007' 'F5: and a kept quest the game calls not PvP falls to CMaNGOS'

    $run = Invoke-Tool $common
    Equal $run.Exit 0 "F6: the run succeeds ($($run.Text))"
    Equal (Tagged $data) '3001,3002,3003,3005,3006,3009,3010' 'F6: it tags the quests it named and keeps the ones that had pvp'
    $problems = @(Test-QuestRecords (Read-QuestData $data))
    Equal $problems.Count 0 "F6: every record passes Test-QuestRecords ($($problems -join '; '))"
    Check (Invoke-AddonDataBuild $data $addon -Check).Ok 'F6: qcQuestData.lua matches the data'
    Equal (Get-Hash "$data\answers.jsonl") $hashes.Answers 'F6: the answer memory is not written'
    $after = @{ Quests = Get-Hash "$data\quests.jsonl"; Lua = Get-Hash "$addon\qcQuestData.lua" }
    $again = Invoke-Tool $common
    Check ($again.Exit -eq 0 -and $again.Text -match '(?m)^0 quests get pvp \(\), 6 already have it\.') "F7: a second run has nothing to tag ($($again.Text))"
    Equal (Get-Hash "$data\quests.jsonl") $after.Quests 'F7: and changes no byte of quests.jsonl'
    Equal (Get-Hash "$addon\qcQuestData.lua") $after.Lua 'F7: or of the Lua'

    $behind = "$Scratch\behind.jsonl"
    Write-Text $behind '{"runs":["9.9.9.99998"]}', (Answer 3002 1 41)
    $old = Invoke-Tool ($common + @('-AnswerFile', $behind, '-WhatIf'))
    Equal $old.Exit 0 "F8: a run with a memory one run behind succeeds ($($old.Text))"
    Check ($old.Text -match "(?m)^The answer memory's last run is 9\.9\.9\.99998, not 9\.9\.9\.99999, .*: run the importer \(step 10\) first\.") "F8: it says the memory is behind the cache ($($old.Text))"
    $older = Invoke-Tool ($common + @('-Build', '9.9.9.99998', '-WhatIf'))
    Equal $older.Exit 0 "F8: a run on an older -Build succeeds ($($older.Text))"
    Check ($older.Text -match "(?m)^The answer memory's last run is 9\.9\.9\.99999, not 9\.9\.9\.99998, .*: its records can come from a later build\.") "F8: it says the memory is ahead of the cache ($($older.Text))"

    # --- R: retail ------------------------------------------------------------------------------
    $tools = "$Scratch\retail-tools"; $data = "$Scratch\retail"
    New-Folder $tools; New-Folder $data
    Write-Text "$tools\retail_quest_cache_9.9.9.99999.jsonl" '{"id":4001,"title":"Quest 4001","questInfo":255}'
    Write-Text "$data\answers.jsonl" '{"runs":["9.9.9.99998"]}', (Answer 4002 1 41)
    [IO.File]::WriteAllText("$data\quests.jsonl", (ConvertTo-QuestJsonLines @((Quest-Row 4001), (Quest-Row 4002))), $script:Utf8)
    [IO.File]::WriteAllText("$data\pins.jsonl", '{"map":84,"icon":1,"name":"Somebody","x":1.5,"y":2.5,"quests":[4001]}' + "`n", $script:Utf8)
    $retail = Invoke-Tool @('-Game', 'retail', '-ToolsDir', $tools, '-DataDir', $data, '-AddonDir', $addon, '-DecisionsFile', $pvpDecisions,
        '-RemovalDecisionsFile', $removals, '-TdbFile', "$Scratch\none.sql", '-WhatIf')
    Equal $retail.Exit 0 "R1: a retail run succeeds ($($retail.Text))"
    Check ($retail.Text -match "(?m)^Build 9\.9\.9\.99999 \(retail\): the game's cache has 1 quests; no source answers for 1 of ours\.") "R1: it names no answer memory ($($retail.Text))"
    Equal (Listed $retail.Text 'Would set pvp on') '4001' 'R1: and tags only what the cache says'
    Check ($retail.Text -notmatch 'answer memory') 'R1: nor names the memory as skipped or out of step'
} finally {
    if (Test-Path $Scratch) { Remove-Item $Scratch -Recurse -Force }
}

Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
