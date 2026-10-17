<#
Checks ConditionTexts.ps1 and the condition texts of AddonData.ps1 (Sync-QuestConditionTexts.ps1, step 2m) on made-up
client tables and a data folder in a temporary folder: nothing in the checkout is touched and nothing is downloaded. It
checks which texts are read (only the conditions asked for), which languages a record keeps (a translation; not a text
that is enUS's word for word, nor a language whose tables are enUS's), the keys left out (no enUS text, a game
variable), the data file's form and checks, and the Lua: each quest's text numbers, every language's list numbered
alike with enUS's text where a language has none, the client's language picked by GetLocale (run in Lua 5.1), and the
build leaving out a quest that has left the data and a text left with none.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncQuestConditionTexts.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param([string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
. (Join-Path $PSScriptRoot 'ConditionTexts.ps1')
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Row($id, $text) { return [pscustomobject]@{ ID = "$id"; Failure_description_lang = $text } }
function Gate($id, $text) { return [pscustomobject]@{ ID = "$id"; FailureReason_lang = $text } }

$wantedPlayer = @{ 10 = $true; 11 = $true; 12 = $true; 13 = $true }
$wantedChapter = @{ 5 = $true }
$read = Read-ConditionTexts @((Row 10 'Requires further advancement.'), (Row 11 'Reach level $pcMinLevel to continue.'), (Row 12 ''), (Row 99 'Not asked for.'), (Row 13 'Same everywhere.')) @((Gate 5 'Return next week.'), (Gate 6 'Not asked for.')) $wantedPlayer $wantedChapter
Equal (($read.Player.Keys | Sort-Object) -join ',') '10,11,13' 'R1: only the conditions asked for, and only those with a text'
Equal $read.Chapter[5] 'Return next week.' 'R1: a chapter gate''s text'

$tables = @{
    enUS = $read
    deDE = Read-ConditionTexts @((Row 10 'Erfordert weiteren Fortschritt.'), (Row 13 'Same everywhere.'), (Row 11 'Erreicht Stufe $pcMinLevel.')) @((Gate 5 'Kehrt nächste Woche zurück.')) $wantedPlayer $wantedChapter
    frFR = Read-ConditionTexts @((Row 10 'Requires further advancement.')) @() $wantedPlayer $wantedChapter
    itIT = Read-ConditionTexts @((Row 10 'Richiede altro.')) @() $wantedPlayer $wantedChapter
}
$tables.itIT.English = $true
$keys = [ordered]@{ c5 = @(300); p10 = @(100, 101); p11 = @(102); p12 = @(103); p13 = @(104) }
$result = Get-ConditionTextRecords $keys $tables $ConditionTextLocales
$by = @{}; foreach ($r in $result.Records) { $by[$r.key] = $r }
Equal (@($result.Records | ForEach-Object { $_.key }) -join ',') 'c5,p10,p13' 'G1: the keys kept, in order'
Equal $by['p10'].deDE 'Erfordert weiteren Fortschritt.' 'G2: a translation is kept'
Check ($null -eq $by['p10'].frFR) 'G2: a text that is enUS''s word for word is left out'
Check ($null -eq $by['p10'].itIT) 'G2: so is a language whose tables are enUS''s'
Check ($null -eq $by['p13'].deDE) 'G2: and a translation that is the English text'
Equal (@($by['p10'].quests) -join ',') '100,101' 'G2: with its quests'
Check (@($result.Skipped | Where-Object { $_ -match '^p11 .*game variable' }).Count -eq 1) 'G3: a text with a game variable is left out, and listed'
Check (@($result.Skipped | Where-Object { $_ -match '^p12 .*no enUS text' }).Count -eq 1) 'G3: so is a key with no English text'

$json = ConvertTo-ConditionTextJsonLines @($by['c5'], $by['p10'])
Equal $json ('{"key":"c5","quests":[300],"enUS":"Return next week.","deDE":"Kehrt nächste Woche zurück."}' + "`n" + '{"key":"p10","quests":[100,101],"enUS":"Requires further advancement.","deDE":"Erfordert weiteren Fortschritt."}' + "`n") 'J1: the data file, with only the languages a record has'

$bad = @(
    [pscustomobject]@{ key = 'x1'; quests = @(1); enUS = 'A' },
    [pscustomobject]@{ key = 'p1'; quests = @(1); enUS = 'A' },
    [pscustomobject]@{ key = 'p1'; quests = @(1); enUS = 'B' },
    [pscustomobject]@{ key = 'p2'; quests = @(); enUS = 'C' },
    [pscustomobject]@{ key = 'p3'; quests = @(1) },
    [pscustomobject]@{ key = 'p4'; quests = @(1); enUS = 'D'; deDE = "two`nlines" },
    [pscustomobject]@{ key = 'p5'; quests = @(1); enUS = 'Reach level $pcMinLevel.' })
$problems = @(Test-ConditionTextRecords $bad)
Check (@($problems | Where-Object { $_ -match "'key' is p or c" }).Count -eq 1) 'T1: a key that isn''t p or c and an ID is a problem'
Check (@($problems | Where-Object { $_ -match 'also on line 2' }).Count -eq 1) 'T1: so is a key listed twice'
Check (@($problems | Where-Object { $_ -match "'quests' must" }).Count -eq 1) 'T1: and no quests'
Check (@($problems | Where-Object { $_ -match "'enUS' must" }).Count -eq 1) 'T1: and no English text'
Check (@($problems | Where-Object { $_ -match "'deDE' has a control character" }).Count -eq 1) 'T1: and a text of two lines'
Check (@($problems | Where-Object { $_ -match "'enUS' has a game variable" }).Count -eq 1) 'T1: and a game variable'
Equal @(Test-ConditionTextRecords $result.Records).Count 0 'T1: sound records have none'

$lua = ConvertTo-LuaConditionTextTables @($by['c5'], $by['p10'], $by['p13'])
Check ($lua.Contains("qcQuestConditionTexts={`r`n[100]={2},`r`n[101]={2},`r`n[104]={3},`r`n[300]={1},`r`n}`r`n")) 'L1: each quest''s text numbers, in quest order'
Check ($lua.Contains('enUS={"Return next week.","Requires further advancement.","Same everywhere."},')) 'L1: enUS''s list'
Check ($lua.Contains('frFR={"Return next week.","Requires further advancement.","Same everywhere."},')) 'L1: a language with no text of its own has enUS''s'
Check ($lua.Contains('deDE={"Kehrt nächste Woche zurück.","Erfordert weiteren Fortschritt.","Same everywhere."},')) 'L1: and one with some, enUS''s for the rest'
Check ($lua.Contains('} qcConditionTexts=texts[GetLocale()] or texts.enUS end')) 'L1: the client''s language is picked, or enUS'
Equal (ConvertTo-LuaConditionTextTables @()) ("qcQuestConditionTexts={`r`n}`r`nqcConditionTexts={}`r`n") 'L2: with no texts, both tables are empty'

$root = Join-Path ([IO.Path]::GetTempPath()) ("condition_texts_test_" + [guid]::NewGuid().ToString('N'))
$data = Join-Path $root 'data'; $addon = Join-Path $root 'addon'
New-Item -ItemType Directory -Force $data, $addon | Out-Null
try {
    if (Test-Path $LuaExe) {
        foreach ($case in @(@('deDE', 'Kehrt nächste Woche zurück.'), @('enGB', 'Return next week.'))) {
            $file = Join-Path $root "locale_$($case[0]).lua"
            [IO.File]::WriteAllText($file, "function GetLocale() return '$($case[0])' end`r`n" + $lua + "io.write(qcConditionTexts[qcQuestConditionTexts[300][1]])`r`n", (New-Object Text.UTF8Encoding $false))
            $outputEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [Text.Encoding]::UTF8
            try { $out = (& $LuaExe $file) -join '' } finally { [Console]::OutputEncoding = $outputEncoding }
            Equal $out $case[1] "L3: Lua 5.1 picks the text for $($case[0])"
        }
    } else { Write-Output "(no Lua at ${LuaExe}: L3 skipped)" }

    [IO.File]::WriteAllText((Join-Path $data 'quests.jsonl'), '{"id":100,"name":"Quest 100","level":30,"zone":"","category":1,"type":1,"faction":1,"race":64175181,"class":8191}' + "`n")
    [IO.File]::WriteAllText((Join-Path $data 'pins.jsonl'), '{"map":1,"icon":1,"x":1,"y":1,"quests":[100]}' + "`n")
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    Check ($build.Ok -and [IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua')).Contains("qcConditionTexts={}`r`n")) 'B1: a data folder with no condition texts builds, with empty tables'
    [IO.File]::WriteAllText((Join-Path $data 'conditiontexts.jsonl'), (ConvertTo-ConditionTextJsonLines @($by['c5'], $by['p10'])), (New-Object Text.UTF8Encoding $false))
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    $text = [IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua'))
    Check ($build.Ok -and $text.Contains("qcQuestConditionTexts={`r`n[100]={1},`r`n}")) 'B2: a text of a quest in the data is written, its number counted among those kept'
    Check (-not $text.Contains('[101]=') -and -not $text.Contains('[300]=') -and -not $text.Contains('Return next week.')) 'B2: a quest that has left the data is left out, and a text left with none goes'
    Check (@($build.Lines | Where-Object { $_ -match '2 condition texts' }).Count -eq 1) 'B2: the count says what the file holds'
    Check (Invoke-AddonDataBuild -DataDir $data -AddonDir $addon -Check).Ok 'B3: a second build changes nothing'
    [IO.File]::WriteAllText((Join-Path $data 'conditiontexts.jsonl'), '{"key":"p10","quests":[100],"enUS":"A","enGB":"B"}' + "`n")
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    Check (-not $build.Ok -and @($build.Lines | Where-Object { $_ -match "unknown field 'enGB'" }).Count -eq 1) 'B4: an unknown field stops the build'
}
finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output "$Passed checks passed, $Failed failed."
if ($Failed -gt 0) { exit 1 }
