<#
Checks QuestRemovals.ps1, ForeverAnswers.ps1 and Show-RemovedQuests.ps1 on made-up data in a scratch folder (and a
scratch git repository): nothing in the checkout is touched and nothing is downloaded. It checks which quests count
as removed, the decisions file, the answer memory (a run is a build's cache, a missed run counts only for a quest
that was asked about, a run is never counted twice, an answer resets the count, the memory reads back byte for
byte), and that Show-RemovedQuests.ps1 exits 1 for an undecided removal and for a KEEP quest that is gone.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-QuestRemovals.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'QuestRemovals.ps1')
. (Join-Path $PSScriptRoot 'ForeverAnswers.ps1')
$Tool = Join-Path $PSScriptRoot 'Show-RemovedQuests.ps1'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("quest-removals-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null

function Quest-Line([int]$id, [string]$name, [string]$zone, [int]$level = 10) {
    return '{"id":' + $id + ',"name":"' + $name.Replace('"', '\"') + '","level":' + $level + ',"zone":"' + $zone + '","category":1,"type":1,"faction":3,"race":0,"class":8191}'
}
function Cache-Line([int]$id, [string]$title) {
    return '{"id":' + $id + ',"title":"' + $title + '","level":10,"minLevel":1,"sort":15,"reputation":[[529,75]]}'
}
function Raw-Cache($lines) { $h = @{}; foreach ($l in $lines) { $h[[int]($l -replace '^\{"id":(\d+),.*$', '$1')] = $l }; return $h }
function Ids([int[]]$ids) { $h = @{}; foreach ($i in $ids) { $h[$i] = $true }; return $h }

try {
    # --- which quests are removed ----------------------------------------------------------------
    $old = ((Quest-Line 1 'One' 'Elwynn Forest' 5), (Quest-Line 2 'He said "two"' 'Duskwood' 27), (Quest-Line 3 'Three' 'Seasonal' 60)) -join "`n"
    $new = Read-QuestIdLines ((Quest-Line 1 'One' 'Elwynn Forest' 5) + "`n" + (Quest-Line 9 'Nine' 'X'))
    Equal $new.Count 2 'R1: the ids of a quest file are read'
    $removed = @(Find-RemovedQuests $old $new)
    Equal $removed.Count 2 'R1: two quests of three have gone'
    Equal (($removed | ForEach-Object { $_.Id }) -join ',') '2,3' 'R1: by id, in order'
    Equal $removed[0].Name 'He said "two"' 'R1: the name keeps its quotes'
    Equal $removed[1].Zone 'Seasonal' 'R1: and the zone'
    Equal $removed[1].Level 60 'R1: and the level'
    Equal @(Find-RemovedQuests $old (Read-QuestIdLines $old)).Count 0 'R1: nothing has gone when nothing has'
    $text = Format-RemovedQuests $removed @{ 2 = $true }
    Check ($text[0] -match '2\s+He said "two"\s+Duskwood\s+level 27\s+REMOVE decided') 'R2: a decided removal says so'
    Check ($text[1] -match '3\s+Three\s+Seasonal\s+level 60\s+UNDECIDED') 'R2: and an undecided one'

    # --- the decisions file ----------------------------------------------------------------------
    $decisions = "$Scratch\decisions.csv"
    [IO.File]::WriteAllText($decisions, "Game,Quest,Decision,Reason`r`nforever,79482,KEEP,`"Christmas, kept`"`r`nretail,5,REMOVE,gone`r`nforever,9,REMOVE,agreed`r`n")
    $f = @(Read-RemovalDecisions $decisions 'forever')
    Equal $f.Count 2 'D1: only the game''s own rows are read'
    Equal $f[0].Quest 79482 'D1: the quest is a number'
    Equal $f[0].Reason 'Christmas, kept' 'D1: and a reason may hold a comma'
    Equal @(Read-RemovalDecisions "$Scratch\nowhere.csv" 'forever').Count 0 'D1: a missing file has no decisions'
    [IO.File]::WriteAllText($decisions, "Game,Quest,Decision,Reason`r`nforever,1,DELETE,x`r`n")
    $threw = $false; try { Read-RemovalDecisions $decisions 'forever' | Out-Null } catch { $threw = $_.Exception.Message -match 'must be KEEP or REMOVE' }
    Check $threw 'D2: a decision that is not KEEP or REMOVE is refused'
    [IO.File]::WriteAllText($decisions, "Game,Quest,Decision,Reason`r`nforever,abc,KEEP,x`r`n")
    $threw = $false; try { Read-RemovalDecisions $decisions 'forever' | Out-Null } catch { $threw = $_.Exception.Message -match 'not a number' }
    Check $threw 'D2: and a quest that is not a number'

    # --- the answer memory -----------------------------------------------------------------------
    $m = New-AnswerMemory
    Update-AnswerMemory $m (Raw-Cache @((Cache-Line 1 'A'), (Cache-Line 2 'B'), (Cache-Line 3 'C'))) $null 'b1'
    Equal $m.Runs.Count 1 'A1: the first cache is a run'
    Equal $m.Quests.Count 3 'A1: with every quest in it'
    Equal $m.Quests[2].Missed 0 'A1: none missed'
    Update-AnswerMemory $m (Raw-Cache @((Cache-Line 1 'A2'), (Cache-Line 4 'D'))) (Ids 1, 2, 3, 4) 'b2'
    Equal $m.Quests[1].Missed 0 'A2: a quest answered again has missed none'
    Check ($m.Quests[1].Raw -match '"title":"A2"') 'A2: and has the newest record'
    Equal $m.Quests[1].Seen 'b2' 'A2: seen in the newest run'
    Equal $m.Quests[2].Missed 1 'A2: a quest asked about and not answered has missed one run'
    Equal $m.Quests[2].Seen 'b1' 'A2: and was last seen in the run before'
    Check ($m.Quests[2].Raw -match '"title":"B"') 'A2: and keeps its last record'
    Equal $m.Quests[4].Missed 0 'A2: a new quest starts at none'
    Update-AnswerMemory $m (Raw-Cache @((Cache-Line 1 'A3'))) (Ids 1, 2, 4) 'b3'
    Equal $m.Quests[2].Missed 2 'A3: a second run missed in a row'
    Equal $m.Quests[3].Missed 1 'A3: a quest the run did not ask about is not counted'
    Equal $m.Quests[4].Missed 1 'A3: a quest asked about and refused is'
    Update-AnswerMemory $m (Raw-Cache @((Cache-Line 1 'A3'), (Cache-Line 2 'B3'))) (Ids 1, 2, 4) 'b3'
    Equal $m.Runs.Count 3 'A4: the same build again is not a new run'
    Equal $m.Quests[2].Missed 0 'A4: but an answer it adds still counts, and resets the quest'
    Equal $m.Quests[4].Missed 1 'A4: and a miss is not counted twice'
    for ($run = 4; $run -le 13; $run++) { Update-AnswerMemory $m (Raw-Cache @((Cache-Line 1 'A'))) (Ids 1, 2, 3, 4) "b$run" }
    Equal $m.Quests[2].Missed 10 'A5: ten runs in a row without an answer'
    Equal ((Get-QuestsMissedSince $m 10) -join ',') '2,3,4' 'A5: 2, 3 and 4 have missed 10 or more, and 1 has not'
    Equal ((Get-QuestsMissedSince $m 11) -join ',') '3,4' 'A5: 3 and 4 have missed 11'
    Equal $m.Quests[1].Missed 0 'A5: a quest answered every run has missed none'

    $path = "$Scratch\answers.jsonl"
    [IO.File]::WriteAllText($path, (ConvertTo-AnswerLines $m))
    $back = Read-AnswerMemory $path
    Equal $back.Runs.Count 13 'A6: the runs read back'
    Equal $back.Quests.Count 4 'A6: and the quests'
    Equal (ConvertTo-AnswerLines $back) (ConvertTo-AnswerLines $m) 'A6: byte for byte'
    Equal $back.Quests[2].Missed 10 'A6: with their counts'
    Check ((Read-AnswerMemory "$Scratch\none.jsonl").Runs.Count -eq 0) 'A6: no file is no memory'
    [IO.File]::WriteAllText($path, "{`"runs`":[]}`n{`"oops`":1}`n")
    $threw = $false; try { Read-AnswerMemory $path | Out-Null } catch { $threw = $_.Exception.Message -match "doesn't know" }
    Check $threw 'A6: a line it does not know is refused'

    # --- Show-RemovedQuests.ps1 on a scratch repository ------------------------------------------
    $repo = "$Scratch\repo"
    foreach ($dir in 'data\forever', 'docs\plans') { New-Item -ItemType Directory -Path "$repo\$dir" -Force | Out-Null }
    $first = ((Quest-Line 1 'One' 'Elwynn Forest'), (Quest-Line 2 'Two' 'Duskwood'), (Quest-Line 3 'Three' 'Seasonal')) -join "`n"
    [IO.File]::WriteAllText("$repo\data\forever\quests.jsonl", $first + "`n")
    [IO.File]::WriteAllText("$repo\data\quests.jsonl", $first + "`n")
    function Invoke-Repo([string[]]$arguments) {
        $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & git -C $repo -c user.email=t@t -c user.name=t -c core.autocrlf=false -c core.safecrlf=false @arguments 2>&1 | Out-Null } finally { $ErrorActionPreference = $saved }
    }
    Invoke-Repo @('init', '-q')
    Invoke-Repo @('add', '-A')
    Invoke-Repo @('commit', '-q', '-m', 'base')
    $second = ((Quest-Line 1 'One' 'Elwynn Forest'), (Quest-Line 3 'Three' 'Seasonal')) -join "`n"
    [IO.File]::WriteAllText("$repo\data\forever\quests.jsonl", $second + "`n")
    function Run-Tool([string[]]$more) {
        $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $Tool -RepoDir $repo -Base HEAD @more 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $saved }
        return @{ Text = ($output -join "`n"); Exit = $LASTEXITCODE }
    }
    $r = Run-Tool @('-Game', 'forever')
    Equal $r.Exit 1 "S1: a quest gone with no decision exits 1 ($($r.Text))"
    Check ($r.Text -match '2\s+Two\s+Duskwood\s+level 10\s+UNDECIDED') 'S1: and is listed with its zone'
    Check ($r.Text -match 'show the list to the user') 'S1: with what to do'
    $r = Run-Tool @('-Game', 'retail')
    Equal $r.Exit 0 'S1: retail, whose file has not changed, exits 0'
    Check ($r.Text -match 'No quest has left data/quests.jsonl') 'S1: and says so'
    [IO.File]::WriteAllText("$repo\docs\plans\quest-removal-decisions.csv", "Game,Quest,Decision,Reason`r`nforever,2,REMOVE,the user agreed`r`n")
    $r = Run-Tool @('-Game', 'forever')
    Equal $r.Exit 0 'S2: a REMOVE decision lets it go'
    Check ($r.Text -match '2\s+Two\s+Duskwood.*REMOVE decided') 'S2: and the list still shows it'
    [IO.File]::WriteAllText("$repo\docs\plans\quest-removal-decisions.csv", "Game,Quest,Decision,Reason`r`nforever,2,REMOVE,agreed`r`nforever,3,KEEP,keep`r`nforever,77,KEEP,never there`r`n")
    $r = Run-Tool @('-Game', 'forever')
    Equal $r.Exit 1 'S3: a KEEP quest that is missing exits 1'
    Check ($r.Text -match 'missing from the data: 77') 'S3: and is named'
    $threw = (Run-Tool @('-Game', 'classic')).Exit -ne 0
    Check $threw 'S3: a game that is not retail or forever is refused'
}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
