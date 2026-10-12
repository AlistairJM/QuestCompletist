<#
Checks Review-Calendar.ps1 and HolidayTables.ps1 on Holidays and HolidayNames tables, a qcHolidays,
quest data, a baseline and a decisions file made here, in a scratch folder: nothing in the checkout is
read or written (but the scripts themselves) and nothing is downloaded. The tables hold a yearly entry
whose calendar shows its second stage only, an entry dated only in the past, one whose dates run out
within the window, the yearly anniversary row and a per-region one its Flags hide, a looping brawl, a
weekly bonus event for the user's region and its twin for another, a row with no name, and events
dated far ahead. The checks: the next runs and last dates, the events no entry covers by region and
by Flags, the /qc holidays list, a sweep with nothing new staying silent, then one change at a time
against the baseline (a new event, dates running out, dates removed, dates to come again, a row whose
Flags put it on the calendar, a hidden event's dates running out, a game not run keeping its rows) and
each kind of fact in the decisions file, held and flipped.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ReviewCalendar.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$Review = Join-Path $PSScriptRoot 'Review-Calendar.ps1'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Has([string]$text, [string]$part, [string]$message) {
    Check ($text.Contains($part)) "$message (no '$part' in the output)"
}
function Lacks([string]$text, [string]$part, [string]$message) {
    Check (-not $text.Contains($part)) "$message ('$part' is in the output)"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("calendar-review-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$Retail = '12.9.0.1'; $Ptr = '12.9.5.1'; $Forever = '1.69.0.1'
$Header = 'ID,Region,Looping,HolidayNameID,HolidayDescriptionID,Priority,CalendarFilterType,Flags,' +
    ((0..9 | ForEach-Object { "Duration_$_" }) -join ',') + ',' + ((0..25 | ForEach-Object { "Date_$_" }) -join ',') + ',' +
    ((0..9 | ForEach-Object { "CalendarFlags_$_" }) -join ',') + ',TextureFileDataID_0,TextureFileDataID_1,TextureFileDataID_2'

# A packed date; $null leaves a field open ("any").
function Pack($year, $month, $day, $hour = 0, $minute = 0, $weekday = $null) {
    $f = @(
        $(if ($null -eq $minute) { 63 } else { $minute }),
        $(if ($null -eq $hour) { 31 } else { $hour }),
        $(if ($null -eq $weekday) { 7 } else { $weekday }),
        $(if ($null -eq $day) { 63 } else { $day - 1 }),
        $(if ($null -eq $month) { 15 } else { $month - 1 }),
        $(if ($null -eq $year) { 31 } else { $year - 2000 }))
    return [long]$f[0] + ([long]$f[1] -shl 6) + ([long]$f[2] -shl 11) + ([long]$f[3] -shl 14) + ([long]$f[4] -shl 20) + ([long]$f[5] -shl 24)
}

function Row([int]$id, [int]$nameId, [long[]]$dates, [int[]]$durations, [int]$region = 0, [int]$flags = 1, [int]$filter = 255, [int]$looping = 0, [int[]]$calendarFlags = @(3)) {
    $d = @(0) * 10; for ($i = 0; $i -lt $durations.Count; $i++) { $d[$i] = $durations[$i] }
    $t = @(0) * 26; for ($i = 0; $i -lt $dates.Count; $i++) { $t[$i] = $dates[$i] }
    $c = @(0) * 10; for ($i = 0; $i -lt $calendarFlags.Count; $i++) { $c[$i] = $calendarFlags[$i] }
    return "$id,$region,$looping,$nameId,0,0,$filter,$flags," + ($d -join ',') + ',' + ($t -join ',') + ',' + ($c -join ',') + ',0,0,0'
}

$Names = @{ 7 = 'Brewfest'; 13 = "Children's Week"; 40 = 'Old Faire Days'; 41 = "WoW's 22nd Anniversary"; 42 = "WoW's Anniversary"
    50 = 'Call of the Scarab'; 51 = 'Pet Battle Bonus Event'; 52 = 'PvP Brawl: Test Brawl'; 53 = 'Lost Event'; 54 = 'Long Event'
    55 = 'Bonus Twin'; 56 = 'Thousand Boat Bash'; 57 = 'Far Event'; 14 = 'Feast of Winter Veil' }

function Get-RetailRows {
    $weeks = @(for ($w = 0; $w -lt 5; $w++) { $day = (Get-Date '2026-10-07').AddDays(7 * $w); Pack $day.Year $day.Month $day.Day 6 })
    return @{
        372 = Row 372 7 @((Pack $null 9 13 7)) @(168, 384) -calendarFlags @(0, 3)
        201 = Row 201 13 @((Pack 2023 5 1)) @(168)
        500 = Row 500 40 @((Pack 2026 11 1), (Pack 2026 12 1)) @(168)
        1808 = Row 1808 41 @((Pack 2026 11 17 10)) @(504)
        1587 = Row 1587 42 @((Pack 2026 11 17 10)) @(504) -region 4 -flags 3
        638 = Row 638 50 @((Pack $null 1 21)) @(72)
        599 = Row 599 51 $weeks @(167) -region 4 -flags 13 -filter 0
        600 = Row 600 51 @((Pack 2027 1 7 7)) @(167) -region 24 -flags 13 -filter 0
        669 = Row 669 52 @((Pack 2026 9 30 8)) @(168, 336) -region 4 -flags 13 -filter 2 -looping 1
        700 = Row 700 53 @((Pack 2025 6 1)) @(48)
        710 = Row 710 54 @((Pack 2027 2 1), (Pack 2027 3 1)) @(24)
        711 = Row 711 57 @((Pack 2028 6 1)) @(24)
        1706 = Row 1706 55 @((Pack 2027 3 1)) @(24) -region 4 -flags 15
        900 = Row 900 0 @((Pack 2026 10 20)) @(48) -region 4 -flags 13
    }
}

function Write-Tables($build, $rows, [string]$dir) {
    New-Item -ItemType Directory -Force $dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir "Holidays-$build.csv"), (@($Header) + @($rows.Values) -join "`n") + "`n", $utf8)
    $names = @('ID,Name_lang') + @($Names.Keys | ForEach-Object { "$_,`"$($Names[$_])`"" })
    [IO.File]::WriteAllText((Join-Path $dir "HolidayNames-$build.csv"), ($names -join "`n") + "`n", $utf8)
}

$Addon = Join-Path $Scratch 'addon'; $Data = Join-Path $Scratch 'data'
New-Item -ItemType Directory -Force $Addon, (Join-Path $Data 'forever') | Out-Null
[IO.File]::WriteAllText((Join-Path $Addon 'qcCore.lua'), @"
local qcHolidays = {
	{flag=1, name="Brewfest", eventIDs={372}},
	{flag=2, name="Children's Week", eventIDs={201}},
	{flag=4, name="Old Fair", eventIDs={500}},
	{flag=8, name="Feast of Winter Veil", eventIDs={141}},
	{flag=16, name="WoW's Anniversary", eventIDs={1808}},
}
"@.Replace("`r`n", "`n"), $utf8)
[IO.File]::WriteAllText((Join-Path $Data 'quests.jsonl'), (@(1, 2, 4, 16 | ForEach-Object { "{`"id`":$_,`"holiday`":$_}" }) -join "`n") + "`n", $utf8)
[IO.File]::WriteAllText((Join-Path $Data 'forever\quests.jsonl'), "{`"id`":9,`"holiday`":2}`n{`"id`":10,`"holiday`":8}`n", $utf8)

$Decisions = Join-Path $Scratch 'decisions.csv'
function Write-Decisions([string[]]$facts) {
    $lines = @('"Decision","Decided","Recorded","Game","Fact","Seen","IfChanged"') + @($facts | ForEach-Object { $_ })
    [IO.File]::WriteAllText($Decisions, ($lines -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $true))
}
$AllFacts = @(
    '"Anniversary on 1808","2026-10-11","row 10","retail","dated 1808","","Add next year''s row."',
    '"Anniversary on 1808","2026-10-11","row 10","retail","hidden 1587","","Ask whether the entry takes it."',
    '"Anniversary on 1808","2026-10-11","row 10","retail","served 1808","2026-10-11, in game","Ask."',
    '"Children undated","2026-10-11","row 12","retail","no-date 201","","Children''s Week is dated again: check it."',
    '"Scarab open","not decided","row 35","retail","served 638","","Say so in row 35."',
    '"Untagged","2026-10-12","row 10","retail","no-row New Year''s Eve","","Ask."',
    '"Untagged","2026-10-12","row 10","retail","none","","No calendar fact."',
    '"Weekly untagged","2026-10-12","row 10","retail","weekly-every-day 4 2026-11-05","","Ask whether they stay untagged."',
    '"Forever 1879","2026-10-11","row 12","forever","not-served 1879","2026-10-11, the beta","Ask."',
    '"Forever 1879","2026-10-11","row 12","forever","hidden 1879","","Ask whether Winter Veil takes it."',
    '"Guest Relations","2026-10-12","row 10","retail","ask Are they offered?","","Ask."')

$Tools = Join-Path $Scratch 'tools'
$Baseline = Join-Path $Scratch 'baseline.csv'
function Invoke-Review([string]$today = '2026-10-12', [switch]$Update, [switch]$RetailOnly) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Review, '-ToolsDir', $Tools, '-AddonDir', $Addon, '-DataDir', $Data,
        '-DownloadDir', (Join-Path $Scratch 'downloads'), '-BaselineFile', $Baseline, '-DecisionsFile', $Decisions, '-Today', $today, '-Build', $Retail)
    if (-not $RetailOnly) { $arguments += @('-PtrBuild', $Ptr, '-ForeverBuild', $Forever) }
    if ($Update) { $arguments += '-UpdateBaseline' }
    $ErrorActionPreference = 'Continue'
    $text = (& powershell @arguments 2>&1 | Out-String)
    return [pscustomobject]@{ Text = $text; Code = $LASTEXITCODE }
}

function Set-Tables($liveRows, $ptrRows = $null) {
    Write-Tables $Retail $liveRows $Tools
    Write-Tables $Ptr $(if ($ptrRows) { $ptrRows } else { $liveRows }) $Tools
    $foreverRows = @{
        201 = Row 201 13 @((Pack 2023 5 1), (Pack 2025 4 28 10)) @(168)
        141 = Row 141 14 @((Pack $null 12 15 6)) @(432)
        1879 = Row 1879 0 @((Pack $null 11 15 6)) @(1464) -flags 3
    }
    Write-Tables $Forever $foreverRows $Tools
}

try {
    Set-Tables (Get-RetailRows)
    Write-Decisions $AllFacts

    "== No baseline yet"
    $r = Invoke-Review
    Check ($r.Code -eq 1) "with no baseline the run fails (exit $($r.Code))"
    Has $r.Text 'There is no baseline' 'it says there is no baseline'
    Check (-not (Test-Path (Join-Path $Scratch 'downloads'))) 'nothing is downloaded when the tables are in -ToolsDir'

    "== The entries"
    Has $r.Text 'Brewfest: next 2027-09-20 07:00 to 2027-10-06 07:00 (372); every year' "Brewfest's run is its second stage, the one with CalendarFlags, on its every-year date"
    Has $r.Text "Children's Week: no date to come, last 2023-05-08" 'an entry dated only in the past has no date to come'
    Has $r.Text 'Old Fair: next 2026-11-01 00:00 to 2026-11-08 00:00 (500); last 2026-12-08, within 90 days' 'an entry whose last date is within 90 days says so'
    Has $r.Text "WoW's Anniversary: next 2026-11-17 10:00 to 2026-12-08 10:00 (1808)" 'the anniversary entry runs on its yearly row'
    Has $r.Text 'Feast of Winter Veil: 141 not in this table (no quest of this game has it)' "an entry with no row in retail's table, and no retail quest, says both"

    "== The events no entry covers"
    Has $r.Text 'Call of the Scarab (638): next 2027-01-21 00:00 to 2027-01-24 00:00; every year' 'a yearly event no entry covers is listed with its next run'
    Has $r.Text 'Pet Battle Bonus Event (599; 1 more for other regions): next 2026-10-07 06:00 to 2026-10-14 05:00; last 2027-01-14' "a weekly event shows its region's next run, and its last date over every region"
    Has $r.Text 'PvP Brawl: Test Brawl (669): next 2026-10-21 08:00 to 2026-10-28 08:00; every 21 days' 'a looping row repeats its first date every sum of its durations, showing its first stage'
    Has $r.Text "WoW's Anniversary (1587) [Flags 3]: next 2026-11-17 10:00 to 2026-12-08 10:00" 'the per-region anniversary row, which the pattern leaves out, is listed as hidden by its Flags'
    Has $r.Text 'Bonus Twin (1706) [Flags 15]' 'a row whose Flags hold 2 is listed as hidden'
    Has $r.Text 'with no name: 900 (next 2026-10-20' 'a row with no name is listed as hidden'
    Lacks $r.Text 'Lost Event' 'an event with no date to come is not listed'
    $events = ($r.Text -split 'events dated to come that no entry covers')[1] -split '== ' | Select-Object -First 1
    Lacks $events 'Brewfest' 'an entry is not listed again as an event'
    Lacks $events 'Old Faire Days' 'nor a row of its IDs under another name'

    "== What /qc holidays should print"
    $preview = ($r.Text -split '== What /qc holidays should print on retail')[1] -split '== ' | Select-Object -First 1
    Has $preview "  Brewfest (372): 2027-09-20 07:00 to 2027-10-06 07:00" 'the preview lists an entry in use with its run'
    Has $preview "  Children's Week: not on the calendar in the next 12 months" 'an entry in use with no run in the 12 months says so'
    Lacks $preview 'Feast of Winter Veil' 'an entry no quest of the game has is left out, as qcPrintHolidays does'
    Has $preview "  Other calendar holidays, not tied to any quest:`r`n    Pet Battle Bonus Event (599)`r`n    Call of the Scarab (638)`r`n    PvP Brawl: Test Brawl (669)`r`n    Long Event (710)`r`n" 'the other holidays are listed by ID'
    Lacks $preview '(600)' "another region's row is not on the user's calendar"
    Lacks $preview '(900)' 'a row with no name is not on the calendar'
    Lacks $preview '(1587)' 'a row whose Flags hold 2 is not on the calendar'
    Lacks $preview '(711)' 'a row dated beyond the 12 months is not listed'
    $foreverPreview = ($r.Text -split '== What /qc holidays should print on WoW: Forever')[1] -split '== ' | Select-Object -First 1
    Has $foreverPreview 'Feast of Winter Veil (141): 2026-12-15 06:00 to 2027-01-02 06:00' "Forever's preview reads Forever's table"
    Lacks $foreverPreview '(1879)' "Forever's nameless 1879 is not on its calendar"

    "== The decisions, held"
    Has $r.Text 'holds    retail 12.9.0.1: dated 1808 (1808 next 2026-11-17)' 'a dated row holds dated'
    Has $r.Text 'holds    retail 12.9.0.1: hidden 1587 (Flags 3)' 'a row with Flags 3 holds hidden'
    Has $r.Text 'seen     retail: served 1808: 2026-10-11, in game' 'a fact seen in game is listed with its date'
    Has $r.Text "holds    retail 12.9.0.1: no-date 201 (201 last 2023-05-08)" 'a past row holds no-date'
    Has $r.Text 'open     retail: served 638: 638 is dated 2027-01-21, in the 12 months /qc holidays reads, so it should list it now' 'an open fact says when the game can answer it'
    Has $r.Text "holds    retail 12.9.0.1: no-row New Year's Eve (not in HolidayNames either)" 'a name with no row holds no-row'
    Has $r.Text 'no fact  retail: nothing in the tables to check' 'a decision with no calendar fact is listed, not checked'
    Has $r.Text 'holds    retail 12.9.0.1: weekly-every-day 4 2026-11-05 (every day to 2026-11-05 in region 4; the unbroken run of days with one lasts to 2026-11-11)' 'the weekly events cover every day to the date'
    Has $r.Text 'seen     forever: not-served 1879: 2026-10-11, the beta' "Forever's facts are listed"
    Has $r.Text 'holds    WoW: Forever 1.69.0.1: hidden 1879 (Flags 3)' "Forever's table answers Forever's facts"
    Has $r.Text 'open     retail: ask Are they offered?' 'a question for the game is open until it has an answer'
    Has $r.Text '8 hold or were seen in game, 0 fail, 2 open for the game to answer.' 'the decisions are counted'

    "== A sweep with nothing new is silent"
    $r = Invoke-Review -Update
    Check (Test-Path $Baseline) '-UpdateBaseline writes the baseline'
    $bytes = if (Test-Path $Baseline) { [IO.File]::ReadAllBytes($Baseline) } else { @(0) }
    Check ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF -and $bytes[-2] -eq 13 -and $bytes[-1] -eq 10) 'the baseline has a BOM and CRLF line ends'
    $rows = @(if (Test-Path $Baseline) { Import-Csv $Baseline })
    Check (@($rows | Where-Object { $_.Game -eq 'forever' }).Count -gt 0 -and @($rows | Where-Object { $_.Game -eq 'ptr' }).Count -gt 0) 'it holds rows for every game run'
    Check (-not @($rows | Where-Object { $_.Name -eq 'Lost Event' }).Count) 'an event with no date to come is left out of it'
    $r = Invoke-Review
    Check ($r.Code -eq 0) "a second run on the same tables passes (exit $($r.Code))"
    Has $r.Text '0 finding(s) and 0 other change(s) against the baseline.' 'it has nothing to say against the baseline'
    Has $r.Text 'No finding' 'it ends with no finding'
    $r = Invoke-Review -today '2026-10-14'
    Has $r.Text '0 finding(s) and 0 other change(s) against the baseline.' 'a later day, with only the next runs moved, says nothing either'

    "== A new event"
    $more = Get-RetailRows
    $more[642] = Row 642 56 @((Pack $null 6 6)) @(72)
    Set-Tables $more
    $r = Invoke-Review
    Check ($r.Code -eq 1) "a new event fails the run (exit $($r.Code))"
    Has $r.Text 'FINDING retail event "Thousand Boat Bash": new, dated to come (last never)' 'it is a finding on retail'
    Has $r.Text 'FINDING ptr event "Thousand Boat Bash": new, dated to come (last never)' 'and on the PTR'

    "== Dates run out, are removed, come again"
    $changed = Get-RetailRows
    $changed[710] = Row 710 54 @((Pack 2027 2 1)) @(24)
    $changed[201] = Row 201 13 @((Pack 2023 5 1), (Pack 2027 5 3 10)) @(168)
    Set-Tables $changed (Get-RetailRows)
    $r = Invoke-Review
    Has $r.Text 'FINDING retail event "Long Event": dates removed: its last date was 2027-03-02, now 2027-02-02' 'a last date moved earlier is a finding'
    Has $r.Text 'FINDING retail entry "Children''s Week": has dates to come again (last 2027-05-10)' 'an entry with dates to come again is a finding'
    Has $r.Text "FAILS    retail 12.9.0.1: no-date 201: dated again: 201 next 2027-05-03" 'the decision resting on it no longer holds'
    Has $r.Text "revisit: Children's Week is dated again: check it." 'and the review names what to revisit'
    Lacks $r.Text 'FINDING ptr entry "Children''s Week"' "the PTR's unchanged table has no such finding"
    Set-Tables (Get-RetailRows)
    $r = Invoke-Review -today '2027-01-20'
    Has $r.Text 'FINDING retail event "Long Event": its dates run out on 2027-03-02, within 90 days' 'an event whose last date comes within 90 days is a finding'
    Has $r.Text 'FINDING retail event "Pet Battle Bonus Event": has no date to come any more (last 2027-01-14)' 'so is one with no date to come any more'
    Has $r.Text 'FINDING retail entry "Old Fair": has no date to come any more (last 2026-12-08)' 'and an entry'
    Has $r.Text 'changed retail event "Bonus Twin": its dates run out on 2027-03-02, within 90 days' "a hidden event's dates running out is listed, not a finding"
    Has $r.Text 'FAILS    retail 12.9.0.1: weekly-every-day 4 2026-11-05: its date has passed' 'a weekly fact whose date has passed asks to be dated again'

    "== Flags that put a row on the calendar"
    $shown = Get-RetailRows
    $shown[1587] = Row 1587 42 @((Pack 2026 11 17 10)) @(504) -region 4 -flags 1
    $shown[599] = Row 599 51 @((Pack 2026 10 7 6), (Pack 2026 10 21 6), (Pack 2026 10 28 6), (Pack 2026 11 4 6)) @(167) -region 4 -flags 13 -filter 0
    Set-Tables $shown (Get-RetailRows)
    $r = Invoke-Review
    Has $r.Text 'FINDING retail event "WoW''s Anniversary": now on the calendar by its Flags and name' 'a hidden event whose Flags change is a finding'
    Has $r.Text 'FAILS    retail 12.9.0.1: hidden 1587: 1587 would now be on the calendar (Flags 1)' 'the hidden fact fails'
    Has $r.Text 'FAILS    retail 12.9.0.1: weekly-every-day 4 2026-11-05: no weekly event on 2026-10-15 in region 4' 'a week with no weekly event fails the weekly fact'
    Has $r.Text 'holds    retail PTR 12.9.5.1: hidden 1587 (Flags 3)' 'a fact is checked on the PTR too, and its result shown where it differs'

    "== A game not run keeps its rows"
    Set-Tables (Get-RetailRows)
    $before = @($(if (Test-Path $Baseline) { Import-Csv $Baseline }) | Where-Object { $_.Game -ne 'retail' } | ForEach-Object { "$($_.Game)|$($_.Name)" })
    $r = Invoke-Review -Update -RetailOnly
    $after = @($(if (Test-Path $Baseline) { Import-Csv $Baseline }) | Where-Object { $_.Game -ne 'retail' } | ForEach-Object { "$($_.Game)|$($_.Name)" })
    Check ($before.Count -gt 0 -and (($before -join ';') -eq ($after -join ';'))) "the PTR's and Forever's rows stay when only retail is run"
    Has $r.Text 'skipped  forever: hidden 1879 (no table of that game given)' "a fact of a game not run is skipped"
}
finally {
    Remove-Item -Recurse -Force $Scratch -ErrorAction SilentlyContinue
}

"$Passed checks passed, $Failed failed"
if ($Failed -gt 0) { exit 1 }
