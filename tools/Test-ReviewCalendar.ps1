<#
Checks Review-Calendar.ps1 and HolidayTables.ps1 on Holidays and HolidayNames tables, a qcHolidays,
quest data, a baseline and a decisions file made here, in a scratch folder: nothing in the checkout is
read or written (but the scripts themselves) and nothing is downloaded. The tables hold a yearly entry
whose calendar shows its second stage only, an entry dated only in the past, one whose dates run out
within the window, entries of two IDs (one for other regions, one repeating, a cup dated years ahead),
the yearly anniversary row and a per-region one its Flags hide, a row whose Region is a mask holding 4,
a looping brawl, a weekly bonus event for the user's region and its twin for another, a Timewalking row
off the calendar window's weekly filter and a hidden one, a row with no name, and events dated far ahead.
The checks: the next runs and last dates, the events no entry covers by region and by Flags, the
/qc holidays list, a sweep with nothing new staying silent, then one change at a time against the
baseline (a new event, dates running out, removed or coming again, the 90-day window at days 89 to 91,
runs passing with time, a row whose Flags or Region put it on or off region 4's calendar, an earlier run
removed, one ID of an entry losing its dates, an event an entry now covers, an event gone from the table,
a game not run keeping its rows, raid openings appearing, running out, lapsing, losing a run and moving
to another region (beside a one-moment row of other Flags, an event with a longer row too, and an opening
whose row leaves Flags 13 or the table, which stay findings) and each kind of fact in the decisions file:
held, failing and staying so, and its outcome changing.

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
function After([string]$text, [string]$part) {
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count - 1; $i++) { if ($lines[$i].Contains($part)) { return $lines[$i + 1] } }
    return ''
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
    43 = "WoW's 23rd Anniversary"; 50 = 'Call of the Scarab'; 51 = 'Pet Battle Bonus Event'; 52 = 'PvP Brawl: Test Brawl'; 53 = 'Lost Event'
    54 = 'Long Event'; 55 = 'Bonus Twin'; 56 = 'Thousand Boat Bash'; 57 = 'Far Event'; 14 = 'Feast of Winter Veil'; 60 = 'Day of the Dead'
    61 = "Hallow's End"; 62 = 'Love is in the Air'; 63 = 'Kalimdor Cup'; 64 = 'Outland Cup'; 65 = 'Timewalking Dungeon Event'
    66 = 'The Dreamrift'; 67 = 'Hidden Moment'; 68 = 'The Voidspire'; 69 = 'Twin Opening' }

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
        409 = Row 409 60 @((Pack $null 11 1 10)) @(48) -region 1999
        324 = Row 324 61 @((Pack $null 10 19 10)) @(337)
        1405 = Row 1405 61 @((Pack 2027 7 25)) @(337) -region 832
        423 = Row 423 62 @((Pack 2027 2 8 10)) @(336)
        335 = Row 335 62 @((Pack $null 2 11 6)) @(120)
        1395 = Row 1395 63 @((Pack 2027 2 23)) @(336)
        1407 = Row 1407 64 @((Pack 2028 2 22), (Pack 2030 2 26)) @(336)
        1583 = Row 1583 65 @((Pack 2026 11 25 5)) @(167) -region 4 -flags 13
        1704 = Row 1704 65 @((Pack 2026 11 11)) @(336) -region 4 -flags 15 -filter 0
        1822 = Row 1822 0 @((Pack 2026 6 1)) @(9999) -flags 2 -filter 0
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
function Write-QcCore([string[]]$more = @()) {
    $lines = @('local qcHolidays = {',
        "`t{flag=1, name=`"Brewfest`", eventIDs={372}},",
        "`t{flag=2, name=`"Children's Week`", eventIDs={201}},",
        "`t{flag=4, name=`"Old Fair`", eventIDs={500}},",
        "`t{flag=8, name=`"Feast of Winter Veil`", eventIDs={141}},",
        "`t{flag=16, name=`"WoW's Anniversary`", eventIDs={1808}},",
        "`t{flag=32, name=`"Hallow's End`", eventIDs={324, 1405}},",
        "`t{flag=64, name=`"Love is in the Air`", eventIDs={423, 335}},",
        "`t{flag=128, name=`"Skyriding Cups`", eventIDs={1395, 1407}},") + @($more | ForEach-Object { "`t$_" }) + @('}')
    [IO.File]::WriteAllText((Join-Path $Addon 'qcCore.lua'), ($lines -join "`n") + "`n", $utf8)
}
Write-QcCore
[IO.File]::WriteAllText((Join-Path $Data 'quests.jsonl'), (@(1, 2, 4, 16, 32, 64, 128 | ForEach-Object { "{`"id`":$_,`"holiday`":$_}" }) -join "`n") + "`n", $utf8)
[IO.File]::WriteAllText((Join-Path $Data 'forever\quests.jsonl'), "{`"id`":9,`"holiday`":2}`n{`"id`":10,`"holiday`":8}`n", $utf8)

$Decisions = Join-Path $Scratch 'decisions.csv'
function Write-Decisions([string[]]$facts) {
    $lines = @('"Decision","Decided","Recorded","Game","Fact","Seen","IfChanged"') + @($facts | ForEach-Object { $_ })
    [IO.File]::WriteAllText($Decisions, ($lines -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $true))
}
$AllFacts = @(
    '"Anniversary on 1808","2026-10-11","row 10","retail","yearly WoW''s Anniversary","","Wait for next year''s row."',
    '"Anniversary on 1808","2026-10-11","row 10","retail","hidden 1587","","Ask whether the entry takes it."',
    '"Anniversary on 1808","2026-10-11","row 10","retail","served 1808","2026-10-11, in game","Ask."',
    '"Children undated","2026-10-11","row 12","retail","no-date 201","","Children''s Week is dated again: check it."',
    '"Scarab open","not decided","row 35","retail","served 638","","Say so in row 35."',
    '"Untagged","2026-10-12","row 10","retail","no-row New Year''s Eve","","Ask."',
    '"Untagged","2026-10-12","row 10","retail","none","","No calendar fact."',
    '"Weekly untagged","2026-10-12","row 10","retail","weekly-every-day 4","","Ask whether they stay untagged."',
    '"Forever 1879","2026-10-11","row 12","forever","not-served 1879","2026-10-11, the beta","Ask."',
    '"Forever 1879","2026-10-11","row 12","forever","hidden 1879","","Ask whether Winter Veil takes it."',
    '"Guest Relations","2026-10-12","row 10","retail","ask Are they offered?","","Ask."',
    '"Cups","2026-10-11","row 10","retail","dated 1395 1407","","A cup has no date to come: ask."')

$Tools = Join-Path $Scratch 'tools'
$Baseline = Join-Path $Scratch 'baseline.csv'
$BaselineRows = Join-Path $Scratch 'baseline-rows.csv'
$BaselineFacts = Join-Path $Scratch 'baseline-facts.csv'
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
    Has $r.Text 'There is no baseline (baseline.csv, baseline-rows.csv, baseline-facts.csv missing)' 'it says there is no baseline, and which files are missing'
    Check (-not (Test-Path (Join-Path $Scratch 'downloads'))) 'nothing is downloaded when the tables are in -ToolsDir'

    "== The entries"
    Has $r.Text 'Brewfest: next 2027-09-20 07:00 to 2027-10-06 07:00 (372); every year' "Brewfest's run is its second stage, the one with CalendarFlags, on its every-year date"
    Has $r.Text "Children's Week: no date to come, last 2023-05-08" 'an entry dated only in the past has no date to come'
    Has $r.Text 'Old Fair: next 2026-11-01 00:00 to 2026-11-08 00:00 (500); last 2026-12-08, within 90 days' 'an entry whose last date is within 90 days says so'
    Has $r.Text "WoW's Anniversary: next 2026-11-17 10:00 to 2026-12-08 10:00 (1808)" 'the anniversary entry runs on its yearly row'
    Has $r.Text 'Feast of Winter Veil: 141 not in this table (no quest of this game has it)' "an entry with no row in retail's table, and no retail quest, says both"
    Has $r.Text "Hallow's End: next 2026-10-19 10:00 to 2026-11-02 11:00 (324); every year; 1405 (other regions) next 2027-07-25" "an entry's ID for other regions is listed with its next run"
    Has $r.Text 'Love is in the Air: next 2027-02-08 10:00 to 2027-02-22 10:00 (423); every year; 335 next 2027-02-11' "an entry's repeating ID makes it every year"
    Has $r.Text 'Skyriding Cups: next 2027-02-23 00:00 to 2027-03-09 00:00 (1395); last 2030-03-12; 1407 next 2028-02-22' 'a cup dated years ahead is listed beyond the 12 months'

    "== The events no entry covers"
    $events = ($r.Text -split 'events dated to come that no entry covers')[1] -split '== ' | Select-Object -First 1
    $shownGroup = ($events -split 'Dated in region 4 but not expected')[0]
    Has $shownGroup 'Call of the Scarab (638): next 2027-01-21 00:00 to 2027-01-24 00:00; every year' 'a yearly event no entry covers is on the calendar with its next run'
    Has $shownGroup 'Day of the Dead (409): next 2026-11-01 10:00 to 2026-11-03 10:00; every year' 'a row whose Region is a mask holding 4 (1999) is on region 4''s calendar'
    Has $shownGroup 'Pet Battle Bonus Event (599; 1 more for other regions): next 2026-10-07 06:00 to 2026-10-14 05:00; last 2027-01-14' "a weekly event shows its region's next run, and its last date over every region"
    Has $shownGroup 'PvP Brawl: Test Brawl (669): next 2026-10-21 08:00 to 2026-10-28 08:00; every 21 days' 'a looping row repeats its first date every sum of its durations, showing its first stage'
    Has $shownGroup 'Timewalking Dungeon Event (1583; not shown by their Flags: 1704): next 2026-11-25 05:00 to 2026-12-02 04:00; last 2026-12-02, within 90 days' 'a Timewalking row off the weekly filter is on the calendar, its hidden twin named'
    Has $events "WoW's Anniversary (1587) [Flags 3]: next 2026-11-17 10:00 to 2026-12-08 10:00" 'the per-region anniversary row, which the pattern leaves out, is listed as hidden by its Flags'
    Has $events 'Bonus Twin (1706) [Flags 15]' 'a row whose Flags hold 2 is listed as hidden'
    Has $events 'with no name: 900 (next 2026-10-20' 'a row with no name is listed as hidden'
    Lacks $r.Text 'Lost Event' 'an event with no date to come is not listed'
    Lacks $events 'Brewfest' 'an entry is not listed again as an event'
    Lacks $events 'Old Faire Days' 'nor a row of its IDs under another name'
    Lacks $events 'Kalimdor Cup' "nor a cup's row"

    "== What /qc holidays should print"
    $preview = ($r.Text -split '== What /qc holidays should print on retail')[1] -split '== ' | Select-Object -First 1
    Has $preview "  Brewfest (372): 2027-09-20 07:00 to 2027-10-06 07:00" 'the preview lists an entry in use with its run'
    Has $preview "  Children's Week: not on the calendar in the next 12 months" 'an entry in use with no run in the 12 months says so'
    Has $preview "  Love is in the Air (423): 2027-02-08 10:00 to 2027-02-22 10:00`r`n    Love is in the Air (335): 2027-02-11 06:00 to 2027-02-16 06:00" "an entry's other ID in the 12 months is on a line below"
    Has $preview "  Hallow's End (324): 2026-10-19 10:00 to 2026-11-02 11:00`r`n  Love" "an entry's ID for other regions is not listed"
    Lacks $preview 'Feast of Winter Veil' 'an entry no quest of the game has is left out, as qcPrintHolidays does'
    Has $preview "  Other calendar holidays, not tied to any quest:`r`n    Day of the Dead (409)`r`n    Pet Battle Bonus Event (599)`r`n    Call of the Scarab (638)`r`n    PvP Brawl: Test Brawl (669)`r`n    Long Event (710)`r`n    Timewalking Dungeon Event (1583)`r`n" 'the other holidays are listed by ID, the region mask holding 4 among them'
    Lacks $preview '(600)' "another region's row is not on the user's calendar"
    Lacks $preview '(900)' 'a row with no name is not on the calendar'
    Lacks $preview '(1587)' 'a row whose Flags hold 2 is not on the calendar'
    Lacks $preview '(1704)' 'nor a hidden Timewalking row'
    Lacks $preview '(711)' 'a row dated beyond the 12 months is not listed'
    $foreverPreview = ($r.Text -split '== What /qc holidays should print on WoW: Forever')[1] -split '== ' | Select-Object -First 1
    Has $foreverPreview 'Feast of Winter Veil (141): 2026-12-15 06:00 to 2027-01-02 06:00' "Forever's preview reads Forever's table"
    Lacks $foreverPreview '(1879)' "Forever's nameless 1879 is not on its calendar"

    "== The decisions, first run"
    Has $r.Text "holds    retail 12.9.0.1: yearly WoW's Anniversary (1808 next 2026-11-17)" 'a yearly entry dated to come holds'
    Has $r.Text 'holds    retail 12.9.0.1: hidden 1587 (Flags 3)' 'a row with Flags 3 holds hidden'
    Has $r.Text 'seen     retail: served 1808: 2026-10-11, in game' 'a fact seen in game is listed with its date'
    Has $r.Text "holds    retail 12.9.0.1: no-date 201 (201 last 2023-05-08)" 'a past row holds no-date'
    Has $r.Text 'open     retail: served 638: 638 is dated 2027-01-21, in the 12 months /qc holidays reads, so it should list it now' 'an open fact says when the game can answer it'
    Has $r.Text "holds    retail 12.9.0.1: no-row New Year's Eve (not in HolidayNames either)" 'a name with no row holds no-row'
    Has $r.Text 'no fact  retail: nothing in the tables to check' 'a decision with no calendar fact is listed, not checked'
    Has $r.Text "fails    retail 12.9.0.1: weekly-every-day 4: no weekly bonus event on 2026-11-12 to 2026-11-24 (13 days), from today to 2026-12-02, the last day the table dates one for region 4; unbroken from today to 2026-11-11" 'the weekly events, by name and on the calendar (1583 off the weekly filter; not the hidden 1704, the nameless 1822, the brawl or the other region''s 600), leave a gap to their last day'
    Has $r.Text 'seen     forever: not-served 1879: 2026-10-11, the beta' "Forever's facts are listed"
    Has $r.Text 'holds    WoW: Forever 1.69.0.1: hidden 1879 (Flags 3)' "Forever's table answers Forever's facts"
    Has $r.Text 'open     retail: ask Are they offered?' 'a question for the game is open until it has an answer'
    Has $r.Text 'holds    retail 12.9.0.1: dated 1395 1407 (1395 next 2027-02-23; 1407 next 2028-02-22)' 'rows dated years ahead hold dated'
    Has $r.Text '8 hold or were seen in game, 0 wait, 1 fail, 2 open for the game to answer; 0 outcome(s) changed since the baseline, 0 new.' 'the decisions are counted'
    Has $r.Text 'No fact outcomes in the baseline yet' 'with no baseline, no outcome is compared'
    Has $r.Text "Not holding today, listed every sweep (a finding only when an outcome changes):`r`n    open     retail: served 638 (Scarab open)`r`n    fails    retail 12.9.0.1: weekly-every-day 4 (Weekly untagged)`r`n    open     retail: ask Are they offered? (Guest Relations)" 'the failing and open facts are listed at the end'

    "== A sweep with nothing new is silent"
    $r = Invoke-Review -Update
    foreach ($file in $Baseline, $BaselineRows, $BaselineFacts) {
        $bytes = if (Test-Path $file) { [IO.File]::ReadAllBytes($file) } else { @(0) }
        Check ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF -and $bytes[-2] -eq 13 -and $bytes[-1] -eq 10) "-UpdateBaseline writes $(Split-Path -Leaf $file) with a BOM and CRLF line ends"
    }
    $rows = @(if (Test-Path $Baseline) { Import-Csv $Baseline })
    Check (@($rows | Where-Object { $_.Game -eq 'forever' }).Count -gt 0 -and @($rows | Where-Object { $_.Game -eq 'ptr' }).Count -gt 0) 'it holds rows for every game run'
    Check (-not @($rows | Where-Object { $_.Name -eq 'Lost Event' }).Count) 'an event with no date to come is left out of it'
    $idRows = @(if (Test-Path $BaselineRows) { Import-Csv $BaselineRows | Where-Object { $_.Game -eq 'retail' } })
    $byId = @{}; foreach ($b in $idRows) { $byId[$b.ID] = $b }
    Check ($byId['500'].Runs -eq '2026-11-01 2026-12-01') "the rows file keeps each run to come of a dated row ('$($byId['500'].Runs)')"
    Check ($byId['599'].Runs -eq '2026-10-07 2026-10-14 2026-10-21 2026-10-28 2026-11-04') "including one running today ('$($byId['599'].Runs)')"
    Check ($byId['335'].Runs -eq 'every year' -and $byId['669'].Runs -eq 'every 21 days') 'and the words of a repeating row'
    Check ($byId['1405'].Region -eq '832' -and $byId['1405'].Shown -eq 'yes' -and $byId['1704'].Shown -eq 'no') "with each row's Region and whether it is shown"
    Check (-not $byId.ContainsKey('700') -and $byId.ContainsKey('201') -and $byId['201'].Runs -eq '') "an event's row with no date to come is left out, an entry's kept"
    $facts = @(if (Test-Path $BaselineFacts) { Import-Csv $BaselineFacts })
    Check (@($facts | Where-Object { $_.Game -eq 'retail' -and $_.Fact -eq 'weekly-every-day 4' -and $_.Outcome -eq 'fails' }).Count -eq 1) 'the facts file keeps a failing outcome'
    Check (@($facts | Where-Object { $_.Game -eq 'ptr' -and $_.Fact -eq 'hidden 1587' -and $_.Outcome -eq 'holds' }).Count -eq 1) "and each table's outcome, the PTR's too"
    Check (@($facts | Where-Object { $_.Fact -like 'served*' -or $_.Fact -like 'ask*' -or $_.Fact -eq 'none' }).Count -eq 0) "but none of the game's facts"
    $r = Invoke-Review
    Check ($r.Code -eq 0) "a second run on the same tables passes (exit $($r.Code))"
    Has $r.Text '0 finding(s) and 0 other change(s) against the baseline.' 'it has nothing to say against the baseline'
    Has $r.Text 'fails    retail 12.9.0.1: weekly-every-day 4' 'a fact that still fails is listed'
    Check (-not (After $r.Text 'fails    retail 12.9.0.1: weekly-every-day 4').Contains('FINDING')) 'and is no finding, as its outcome is the baseline''s'
    Has $r.Text '0 outcome(s) changed since the baseline, 0 new.' 'no outcome changed'
    Has $r.Text 'No finding' 'it ends with no finding'
    $r = Invoke-Review -today '2026-10-14'
    Check ($r.Code -eq 0) "a later day, with only the next runs moved, passes (exit $($r.Code))"
    Has $r.Text '0 finding(s) and 0 other change(s) against the baseline.' 'and says nothing either'

    "== A new event"
    $more = Get-RetailRows
    $more[642] = Row 642 56 @((Pack $null 6 6)) @(72)
    Set-Tables $more
    $r = Invoke-Review
    Check ($r.Code -eq 1) "a new event fails the run (exit $($r.Code))"
    Has $r.Text 'FINDING retail event "Thousand Boat Bash": new, dated to come (last never)' 'it is a finding on retail'
    Has $r.Text 'FINDING ptr event "Thousand Boat Bash": new, dated to come (last never)' 'and on the PTR'

    "== Dates removed, shortened, come again"
    $changed = Get-RetailRows
    $changed[710] = Row 710 54 @((Pack 2027 2 1)) @(24)
    $changed[711] = Row 711 57 @((Pack 2028 6 1)) @(12)
    $changed[201] = Row 201 13 @((Pack 2023 5 1), (Pack 2027 5 3 10)) @(168)
    Set-Tables $changed (Get-RetailRows)
    $r = Invoke-Review
    Has $r.Text 'FINDING retail event "Long Event": 710: run of 2027-03-01 removed before it came' 'a run to come taken out of the table is a finding'
    Lacks $r.Text 'Long Event": dates removed' 'which says it once, not again as a last date moved earlier'
    Has $r.Text 'FINDING retail event "Far Event": dates removed: its last date was 2028-06-02, now 2028-06-01' 'a last date moved earlier, with every run still there, is a finding'
    Has $r.Text 'FINDING retail entry "Children''s Week": has dates to come again (last 2027-05-10)' 'an entry with dates to come again is a finding'
    Has $r.Text 'FINDING retail entry "Children''s Week": 201: dated to come again: 2027-05-03' 'and so is its row'
    Has $r.Text "fails    retail 12.9.0.1: no-date 201: dated again: 201 next 2027-05-03" 'the decision resting on it no longer holds'
    Has (After $r.Text 'fails    retail 12.9.0.1: no-date 201') "FINDING: holds at the baseline, fails now. Revisit: Children's Week is dated again: check it." 'its outcome changed: a finding, naming what to revisit'
    Lacks $r.Text 'FINDING ptr entry "Children''s Week"' "the PTR's unchanged table has no such finding"

    "== Time passing alone"
    Set-Tables (Get-RetailRows)
    $r = Invoke-Review -today '2027-01-20'
    Has $r.Text 'FINDING retail event "Long Event": its dates run out on 2027-03-02, within 90 days' 'an event whose last date comes within 90 days is a finding'
    Has $r.Text 'FINDING retail event "Pet Battle Bonus Event": has no date to come any more (last 2027-01-14)' 'so is one with no date to come any more'
    Has $r.Text 'FINDING retail entry "Old Fair": has no date to come any more (last 2026-12-08)' 'and an entry'
    Has $r.Text 'changed retail event "Bonus Twin": its dates run out on 2027-03-02, within 90 days' "a hidden event's dates running out is listed, not a finding"
    Lacks $r.Text 'removed before' 'runs that passed with time are not runs removed'
    Has $r.Text "waits    retail 12.9.0.1: yearly WoW's Anniversary: 1808's run ended 2026-12-08, and the table has no later row yet: the next year's is due by 2027-11-17" 'a yearly entry between two years waits for its next row'
    Has (After $r.Text "waits    retail 12.9.0.1: yearly WoW's Anniversary") 'FINDING: holds at the baseline, waits now.' 'its outcome changed: a finding'
    Has $r.Text "fails    retail 12.9.0.1: weekly-every-day 4: no weekly bonus event is dated to come on region 4's calendar" 'with no weekly event dated to come, the weekly fact fails'
    Check (-not (After $r.Text 'fails    retail 12.9.0.1: weekly-every-day 4').Contains('FINDING')) 'which is no finding, as it failed at the baseline too'
    $r = Invoke-Review -today '2027-11-20'
    Has $r.Text "fails    retail 12.9.0.1: yearly WoW's Anniversary: no row dated since 1808 began on 2026-11-17: the next year's was due by 2027-11-17" 'a year after the last run began, with no new row, the yearly fact fails'
    $next = Get-RetailRows
    $next[1900] = Row 1900 43 @((Pack 2027 11 16 10)) @(504)
    Set-Tables $next
    $r = Invoke-Review -today '2026-12-20'
    Has $r.Text "holds    retail 12.9.0.1: yearly WoW's Anniversary (1900 next 2027-11-16)" "next year's row, by the entry's pattern, makes it hold again"

    "== The 90-day window"
    Set-Tables (Get-RetailRows)
    $r = Invoke-Review -today '2026-12-03'
    Has $r.Text 'Long Event (710): next 2027-02-01 00:00 to 2027-02-02 00:00; last 2027-03-02, within 90 days' 'a last date 89 days ahead is within the window'
    Has $r.Text 'FINDING retail event "Long Event": its dates run out on 2027-03-02, within 90 days' 'and a finding against the baseline'
    $r = Invoke-Review -today '2026-12-02'
    Has $r.Text 'Long Event (710): next 2027-02-01 00:00 to 2027-02-02 00:00; last 2027-03-02, within 90 days' 'so is one 90 days ahead'
    Has $r.Text 'FINDING retail event "Long Event": its dates run out on 2027-03-02, within 90 days' 'a finding too'
    $r = Invoke-Review -today '2026-12-01'
    Has $r.Text 'Long Event (710): next 2027-02-01 00:00 to 2027-02-02 00:00; last 2027-03-02' 'a last date 91 days ahead is listed'
    Lacks $r.Text 'last 2027-03-02, within 90 days' 'outside the window'
    Lacks $r.Text 'FINDING retail event "Long Event"' 'and no finding'

    "== Flags that put a row on the calendar, and a fact's outcome changing"
    $shown = Get-RetailRows
    $shown[1587] = Row 1587 42 @((Pack 2026 11 17 10)) @(504) -region 4 -flags 1
    $shown[1704] = Row 1704 65 @((Pack 2026 11 11)) @(336) -region 4 -flags 13 -filter 0
    Set-Tables $shown (Get-RetailRows)
    $r = Invoke-Review
    Has $r.Text 'FINDING retail event "WoW''s Anniversary": 1587: now on the calendar by its Flags and name (Flags 3 -> 1)' 'a hidden row whose Flags change is a finding, by its ID'
    Has $r.Text 'FINDING retail event "Timewalking Dungeon Event": 1704: now on the calendar by its Flags and name (Flags 15 -> 13)' 'so is one row of an event already on the calendar'
    Lacks $r.Text 'Anniversary": now on the calendar' 'and the event-wide line is not said again'
    Has $r.Text 'fails    retail 12.9.0.1: hidden 1587: 1587 would now be on the calendar (Flags 1)' 'the hidden fact fails'
    Has (After $r.Text 'fails    retail 12.9.0.1: hidden 1587') 'FINDING: holds at the baseline, fails now. Revisit: Ask whether the entry takes it.' 'a fact going from holds to fails is a finding'
    Has $r.Text 'holds    retail 12.9.0.1: weekly-every-day 4 (every day from today to 2026-12-02, the last day the table dates one for region 4)' 'a weekly row coming onto the calendar fills the gap'
    Has (After $r.Text 'holds    retail 12.9.0.1: weekly-every-day 4') 'FINDING: fails at the baseline, holds now. Revisit: Ask whether they stay untagged.' 'a fact going from fails to holds is a finding too'
    Has $r.Text 'holds    retail PTR 12.9.5.1: hidden 1587 (Flags 3)' 'a fact is checked on the PTR too, and its result shown where it differs'

    "== Region 4 losing a row or a run, other regions keeping theirs"
    $moved = Get-RetailRows
    $moved[638] = Row 638 50 @((Pack $null 1 21)) @(72) -region 2
    $moved[1808] = Row 1808 41 @((Pack 2026 11 17 10)) @(504) -region 2
    $moved[599] = Row 599 51 @((Pack 2026 10 7 6), (Pack 2026 10 14 6), (Pack 2026 10 28 6), (Pack 2026 11 4 6)) @(167) -region 4 -flags 13 -filter 0
    Set-Tables $moved (Get-RetailRows)
    $r = Invoke-Review
    Check ($r.Code -eq 1) "rows leaving region 4's calendar fail the run (exit $($r.Code))"
    Has $r.Text 'FINDING retail event "Call of the Scarab": 638: off region 4''s calendar by its Region (0 -> 2)' "an event's row moved to another region is a finding"
    Has $r.Text 'FINDING retail entry "WoW''s Anniversary": 1808: off region 4''s calendar by its Region (0 -> 2)' "so is an entry's"
    Has $r.Text 'FINDING retail event "Pet Battle Bonus Event": 599: run of 2026-10-21 removed before it came' "region 4's row losing a run while the other region's keeps its dates is a finding"
    Lacks $r.Text 'FINDING ptr' "the PTR's unchanged table has none"

    "== An earlier run removed, and one ID of an entry losing its dates"
    $lost = Get-RetailRows
    $lost[500] = Row 500 40 @((Pack 2026 12 1)) @(168)
    $lost[1405] = Row 1405 61 @((Pack 2023 7 25)) @(337) -region 832
    $lost[335] = Row 335 62 @((Pack 2025 2 11 6)) @(120)
    $lost[1407] = Row 1407 64 @((Pack 2024 1 18)) @(336)
    Set-Tables $lost (Get-RetailRows)
    $r = Invoke-Review
    Has $r.Text 'FINDING retail entry "Old Fair": 500: run of 2026-11-01 removed before it came' 'an earlier run to come removed, the last kept, is a finding'
    Has $r.Text 'FINDING retail entry "Hallow''s End": 1405: run of 2027-07-25 removed before it came; no date to come now' "an entry's other ID going dateless, while the entry's every-year row keeps it dated, is a finding"
    Has $r.Text 'FINDING retail entry "Love is in the Air": 335: no longer repeats (every year): no date to come' 'so is its repeating ID ceasing to repeat'
    Has $r.Text 'FINDING retail entry "Skyriding Cups": 1407: runs of 2028-02-22, 2030-02-26 removed before they came; no date to come now' "and a cup's runs years ahead"
    Has (After $r.Text 'fails    retail 12.9.0.1: dated 1395 1407') 'FINDING: holds at the baseline, fails now. Revisit: A cup has no date to come: ask.' 'the cup fact flips'
    Lacks $r.Text 'dates removed' 'the last dates moved earlier are not said again'

    "== An event an entry now covers"
    Set-Tables (Get-RetailRows)
    Write-QcCore @('{flag=256, name="Call of the Scarab", eventIDs={638}},', '{flag=512, name="Long Event", eventIDs={}},')
    $r = Invoke-Review
    Write-QcCore
    Has $r.Text 'changed retail event "Call of the Scarab": now covered by the entry Call of the Scarab' 'an event an entry takes by its ID is listed as covered'
    Has $r.Text 'changed retail event "Long Event": now covered by the entry Long Event' 'and one it takes by its name'
    Has $r.Text 'changed retail entry "Call of the Scarab": new entry, dated to come (last never)' 'the new entry is listed'
    Lacks $r.Text 'gone from the table' 'a covered event is not gone from the table'
    Lacks $r.Text 'FINDING' 'none of it is a finding'
    Check ($r.Code -eq 0) "a change the baseline update accepts passes (exit $($r.Code))"

    "== Gone from the table"
    $gone = Get-RetailRows
    $gone.Remove(638); $gone.Remove(711); $gone.Remove(1407)
    Set-Tables $gone (Get-RetailRows)
    $r = Invoke-Review
    Has $r.Text 'FINDING retail event "Call of the Scarab": gone from the table, which had dates to come with no end' 'an every-year event the table lost is a finding'
    Has $r.Text 'FINDING retail event "Far Event": gone from the table, which had dates to come to 2028-06-02' 'so is a dated one'
    Lacks $r.Text '638: gone' "an event gone as a whole isn't said again by its row"
    Has $r.Text 'FINDING retail entry "Skyriding Cups": 1407: gone from the table, with runs to come (2028-02-22, 2030-02-26)' "an entry's row the table lost is a finding"
    Lacks $r.Text 'now covered' 'an event gone is not covered'

    "== A game not run keeps its rows"
    Set-Tables (Get-RetailRows)
    $keep = { param($file) @($(if (Test-Path $file) { Import-Csv $file }) | Where-Object { $_.Game -ne 'retail' } | ForEach-Object { ($_.PSObject.Properties | ForEach-Object { $_.Value }) -join '|' }) }
    $before = @($Baseline, $BaselineRows, $BaselineFacts | ForEach-Object { (& $keep $_) -join ';' })
    $r = Invoke-Review -Update -RetailOnly
    $after = @($Baseline, $BaselineRows, $BaselineFacts | ForEach-Object { (& $keep $_) -join ';' })
    for ($i = 0; $i -lt 3; $i++) { Check ($before[$i] -and $before[$i] -eq $after[$i]) "the PTR's and Forever's rows stay in each baseline file ($i) when only retail is run" }
    Has $r.Text 'skipped  forever: hidden 1879 (no table of that game given)' "a fact of a game not run is skipped"

    "== Raid openings: new, running out, lapsing"
    $openings = Get-RetailRows
    $openings[1880] = Row 1880 66 @((Pack 2026 10 13 6)) @(0) -region 4 -flags 13
    $openings[1881] = Row 1881 66 @((Pack 2026 10 13 22)) @(0) -region 2 -flags 13
    $openings[1885] = Row 1885 68 @((Pack 2027 3 2 6)) @(0) -region 4 -flags 13
    $lookalikes = $openings.Clone()
    $lookalikes[1890] = Row 1890 67 @((Pack 2026 10 20 6)) @(0) -region 4 -flags 15
    $lookalikes[1891] = Row 1891 69 @((Pack 2026 10 21 6)) @(0) -region 4 -flags 13
    $lookalikes[1892] = Row 1892 69 @((Pack 2026 10 21 6)) @(24) -region 4 -flags 13
    Set-Tables $lookalikes
    $r = Invoke-Review
    $part = (($r.Text -split 'Raid openings \(events of named rows of one moment, Flags 13\), listed and never a finding:')[1] -split 'finding\(s\) and')[0]
    Has $part 'changed retail event "The Dreamrift": new, dated to come (last 2026-10-13)' 'a new raid opening is listed in a part of its own'
    Has $part 'changed ptr event "The Dreamrift": new, dated to come (last 2026-10-13)' 'on the PTR too'
    Has $part 'changed retail event "The Voidspire": new, dated to come (last 2027-03-02)' 'and so is one dated months ahead'
    Lacks $r.Text 'FINDING retail event "The Dreamrift"' 'a new raid opening is no finding'
    Has $r.Text 'The Dreamrift (1880; 1 more for other regions): next 2026-10-13 06:00 to 2026-10-13 06:00; last 2026-10-13, within 90 days' 'and is still listed among the events on the calendar'
    Has $r.Text 'FINDING retail event "Hidden Moment": new, dated to come (last 2026-10-20), not on the calendar by its Flags or name' 'a row of one moment with other Flags is no raid opening'
    Has $r.Text 'FINDING retail event "Twin Opening": new, dated to come (last 2026-10-22)' 'nor an event with a longer row beside its one moment'
    Check (-not $part.Contains('Hidden Moment') -and -not $part.Contains('Twin Opening')) 'which both stay out of the raid openings'
    Has $r.Text '4 finding(s) and 4 other change(s) against the baseline.' 'the raid openings count as changes'
    Set-Tables $openings
    $r = Invoke-Review -Update
    Check ($r.Code -eq 0) "new raid openings alone fail nothing (exit $($r.Code))"
    $r = Invoke-Review -today '2026-10-14'
    Check ($r.Code -eq 0) "a raid opening lapsing fails nothing (exit $($r.Code))"
    $part = (($r.Text -split 'listed and never a finding:')[1] -split 'finding\(s\) and')[0]
    Has $part 'changed retail event "The Dreamrift": has no date to come any more (last 2026-10-13)' 'a raid opening that has lapsed is listed with the raid openings'
    Has $r.Text '0 finding(s) and 2 other change(s) against the baseline.' 'on live and the PTR, and nothing else'
    $r = Invoke-Review -today '2026-12-03'
    $part = (($r.Text -split 'listed and never a finding:')[1] -split 'finding\(s\) and')[0]
    Has $part 'changed retail event "The Voidspire": its dates run out on 2027-03-02, within 90 days' 'a raid opening coming within 90 days is listed there'
    Lacks $r.Text 'FINDING retail event "The Voidspire"' 'and is no finding'
    Has $r.Text 'FINDING retail event "Long Event": its dates run out on 2027-03-02, within 90 days' 'while another event running out the same day still is'

    "== Raid openings: a run removed, a row moved, Flags changed, gone from the table"
    $moved = $openings.Clone()
    $moved[1885] = Row 1885 68 @((Pack 2027 3 9 6)) @(0) -region 2 -flags 13
    Set-Tables $moved
    $r = Invoke-Review
    Check ($r.Code -eq 0) "a raid opening losing a run and moving off region 4 fails nothing (exit $($r.Code))"
    $part = (($r.Text -split 'listed and never a finding:')[1] -split 'finding\(s\) and')[0]
    Has $part 'changed retail event "The Voidspire": 1885: run of 2027-03-02 removed before it came' "a raid opening's run removed is listed with the raid openings"
    Has $part 'changed retail event "The Voidspire": 1885: off region 4''s calendar by its Region (4 -> 2)' 'and so is its row moved to another region'
    Lacks $r.Text 'FINDING retail event "The Voidspire"' 'neither is a finding'
    $flagged = $openings.Clone()
    $flagged[1885] = Row 1885 68 @((Pack 2027 3 2 6)) @(0) -region 4 -flags 15
    Set-Tables $flagged
    $r = Invoke-Review
    Has $r.Text 'FINDING retail event "The Voidspire": 1885: off the calendar by its Flags or name (Flags 13 -> 15)' 'an opening whose row leaves Flags 13 is no raid opening, so its row leaving the calendar is a finding'
    $gone = $openings.Clone(); $gone.Remove(1885)
    Set-Tables $gone
    $r = Invoke-Review
    Has $r.Text 'FINDING retail event "The Voidspire": gone from the table, which had dates to come to 2027-03-02' 'a raid opening gone from the table is a finding'
}
finally {
    Remove-Item -Recurse -Force $Scratch -ErrorAction SilentlyContinue
}

"$Passed checks passed, $Failed failed"
if ($Failed -gt 0) { exit 1 }
