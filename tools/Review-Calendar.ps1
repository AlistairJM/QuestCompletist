<#
Report only: the calendar review of every sweep, for both games. It reads the newest Holidays and
HolidayNames tables of retail live (-Build), the retail PTR (-PtrBuild, when there is one) and WoW: Forever
(-ForeverBuild), qcHolidays from qcCore.lua and the holiday values of each game's quests, and writes

  - per qcHolidays entry and game: its next run on the user's realm (-Region, 4), each other ID's, and the
    last date the table holds in any region, or "no date to come", when its pins stay hidden for good;
  - every event the table dates that no entry covers (not one of an entry's IDs, its name, or its
    $HolidayRowPatterns pattern), by name, ID and region, with its next run and its last date: those the
    calendar shows in the region, those it is not expected to show, and those dated for other regions only;
  - what /qc holidays should print on each game today, in its order and words, to set beside the one
    run in game (the sweep asks for one per game: maintenance.md, "Holidays");
  - the comparison with the baseline (-BaselineFile, docs\plans\calendar-baseline.csv, and beside it
    calendar-baseline-rows.csv and calendar-baseline-facts.csv);
  - each fact of -DecisionsFile (docs\plans\calendar-decisions.csv), which lists the decisions taken on
    the calendar's word: its outcome today, and the decision to revisit when that outcome has changed. A
    fact only the game can answer is listed as open until the file has the date it was seen.

The baseline is three files, per game (retail, ptr, forever). The first holds every entry and every event
with a date to come: its IDs, whether it has a date to come, its last date ("never" for a row dated every
year, or looping), whether that falls within -SoonDays, and whether a row of it is on the calendar by its
Flags and name. The -rows file holds each of their rows that an entry lists or that has a date to come:
its Region, Flags, whether its Flags and name put it on the calendar, and its runs to come (the day each
starts, as the calendar shows it, or the words of a row that repeats). The -facts file holds each table
fact's outcome on each table.

A finding (exit 1) is
  - a new event with dates to come, an entry or event with dates to come again, and, for an entry or an
    event on the calendar, one that loses its dates to come, is gone from the table, has its last date
    moved earlier (dates removed) or has it come within -SoonDays of today;
  - a row with runs to come that comes onto the calendar or leaves it, by its Flags and name, or by its
    Region for region 4 (-Region): the user's calendar is region 4's, so a row that leaves it while other
    regions keep their dates is a finding;
  - for an entry's row, or a row on the calendar by its Flags and name, a run to come that is no longer in
    the table (or the row itself gone), a repeating row that stops repeating, and (an entry's) a row dated
    to come again;
  - a fact whose outcome (holds, waits or fails) differs from the baseline's.
The same for an event off the calendar (a nameless row, the plain-named "WoW's Anniversary" rows), more
dates, more runs, new rows, an event that an entry now covers, and a new entry or fact are listed and
don't fail. Only runs still to come are compared, so a run that passes, the Darkmoon Faire's monthly
move, and a sweep with nothing new in the tables say nothing beyond what time brings (an event's dates
coming within the window or running out, a fact whose outcome turns as its days pass). A fact that fails, waits or is open is
listed every sweep, and is a finding only when its outcome changes. -UpdateBaseline rewrites the rows of
the games run, once the findings and changes are read.

-SoonDays is 90: retail's patches come eight to twelve weeks apart, and each one's table dates the
rotating events (the weekly bonus events, Timewalking, the Darkmoon Faire) a few months further, so an
event whose dates end within 90 days may run out before the next patch; seen a sweep ahead, there is
time to read the PTR's table (-PtrBuild) and to decide.

A row's Region is a mask: 0 is every region, and the user's realm reads the rows that hold 4. The
calendar is expected to show a row that has a name and whose Flags hold 1 and not 2 (inferred
from the tables, Test-HolidayShown in HolidayTables.ps1). The times are the tables' own, which the game
may show in another time zone, and the list assumes every filter of the calendar window is ticked.

The tables are read from -ToolsDir as <Table>-<build>.csv, else downloaded into -DownloadDir\<build>\.
Nothing else is written, but the baseline with -UpdateBaseline.

  .\Review-Calendar.ps1 -Build 12.1.0.69933 -PtrBuild 12.1.5.70077 -ForeverBuild 1.60.1.70338
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$Build = '',
    [string]$PtrBuild = '',
    [string]$ForeverBuild = '',
    [string]$DownloadDir = (Join-Path $env:TEMP 'client_tables'),
    [string]$BaselineFile = (Join-Path $PSScriptRoot '..\docs\plans\calendar-baseline.csv'),
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\calendar-decisions.csv'),
    [datetime]$Today = [datetime]::Today,
    [int]$Region = 4,
    [int]$SoonDays = 90,
    [switch]$UpdateBaseline
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
if (-not $Build -and -not $PtrBuild -and -not $ForeverBuild) { throw "Give -Build (retail), -PtrBuild and/or -ForeverBuild." }
. "$PSScriptRoot\HolidayTables.ps1"

$Today = $Today.Date
$BaselineFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BaselineFile)
$DecisionsFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DecisionsFile)
$baseName = Join-Path (Split-Path $BaselineFile) ([IO.Path]::GetFileNameWithoutExtension($BaselineFile))
$RowsFile = "$baseName-rows.csv"
$FactsFile = "$baseName-facts.csv"
$windowEnd = (New-Object DateTime $Today.Year, $Today.Month, 1).AddMonths(13).AddSeconds(-1)
$soonEnd = $Today.AddDays($SoonDays)
$entries = Read-QcHolidays $AddonDir
$findings = New-Object System.Collections.Generic.List[string]
$FactOutcomes = New-Object System.Collections.Generic.List[object]

# The weekly bonus events, by name: the Battleground, Arena Skirmish, Pet Battle, World Quest, Delves and
# Apexis Bonus Events, and the Timewalking, Midnight and earlier expansions' Dungeon Events. On 12 October
# 2026 these were the 14 names (15 rows) that match in retail's HolidayNames (12.1.0.69933 and the 12.1.5
# PTR's 70077), and no other name there has "Event"; Forever's (1.60.1.70338) had none.
$WeeklyEventPattern = '^.+ (?:Bonus|Dungeon) Event$'

function Get-Table([string]$build, [string]$table) {
    $held = Join-Path $ToolsDir "$table-$build.csv"
    if (Test-Path $held) { return $held }
    $dir = Join-Path $DownloadDir $build
    $path = Join-Path $dir "$table.csv"
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Force $dir | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$build" -OutFile $path
        Start-Sleep -Milliseconds 500
    }
    return $path
}

function Get-FlagsInUse([string]$file) {
    $inUse = 0
    if (Test-Path $file) {
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($file), '"holiday":(\d+)')) { $inUse = $inUse -bor [int]$m.Groups[1].Value }
    }
    return $inUse
}

function Format-Time([datetime]$t) { return $t.ToString('yyyy-MM-dd HH:mm') }
function Format-Day([datetime]$t) { return $t.ToString('yyyy-MM-dd') }
function ConvertTo-Day([string]$day) { return [datetime]::ParseExact($day, 'yyyy-MM-dd', $null) }

function Get-RepeatWords($r, $last) {
    if ($null -eq $last -or $last.End -ne [datetime]::MaxValue) { return $null }
    if ([int]$r.Looping -ne 0) { return "every $([Math]::Round((@(Get-HolidayStages $r) | Measure-Object -Sum).Sum / 24)) days" }
    $d = @(Get-HolidayDates $r | Where-Object { $null -eq $_.Year })[0]
    if ($null -eq $d.Month -and $null -eq $d.Day) { if ($null -ne $d.Weekday) { return 'every week' } else { return 'every day' } }
    if ($null -eq $d.Month) { return 'every month' }
    return 'every year'
}

# A row as the review reads it: its name, its runs from today to the end of the 12th month ahead (what
# /qc holidays reads), its last date, and whether it is the region's and on the calendar.
function Read-Game($game) {
    $names = @{}
    foreach ($r in Import-Csv (Get-Table $game.Build 'HolidayNames')) { $names[$r.ID] = $r.Name_lang }
    $rows = @{}
    foreach ($r in Import-Csv (Get-Table $game.Build 'Holidays')) {
        $last = Get-HolidayLastDate $r
        $name = [string]$names[$r.HolidayNameID]
        $rows[[int]$r.ID] = [pscustomobject]@{
            ID = [int]$r.ID; Row = $r; Name = $name; Region = [int]$r.Region; Flags = [int]$r.Flags
            Last = $last; ToCome = ($null -ne $last -and $last.End -ge $Today)
            Shown = (Test-HolidayShown $r $name); Ours = (Test-HolidayRegion $r $Region); Weekly = ($name -match $WeeklyEventPattern)
            Runs = @(Get-HolidayRuns $r $Today $windowEnd | Where-Object { $_.End -gt $Today })
            Repeat = (Get-RepeatWords $r $last); Later = $null
        }
    }
    $game.Names = $names
    $game.Rows = $rows
}

# The row's next run, beyond the 12 months when it has none in them.
function Get-Next($row) {
    if ($row.Runs.Count) { return $row.Runs[0] }
    if (-not $row.ToCome) { return $null }
    if ($null -eq $row.Later) { $row.Later = @(Get-HolidayRuns $row.Row $Today $Today.AddYears(6) | Where-Object { $_.End -gt $Today } | Select-Object -First 1) }
    return @($row.Later)[0]
}

# A row's runs to come, as the baseline keeps them: the day each starts on the calendar, or the words of a
# row that repeats, or nothing.
function Get-FutureRuns($row) {
    if (-not $row.ToCome) { return '' }
    if ($row.Last.End -eq [datetime]::MaxValue) { return [string]$row.Repeat }
    return (@(Get-HolidayRuns $row.Row $Today $row.Last.End | Where-Object { $_.End -gt $Today } | ForEach-Object { Format-Day $_.Start }) | Sort-Object -Unique) -join ' '
}

function Get-RunDays([string]$runs) {
    if ($runs -match '^\d{4}-') { return @($runs -split ' ') }
    return @()
}

function Get-RowState($row, [string]$kind, [string]$name) {
    return [pscustomobject]@{ ID = $row.ID; Kind = $kind; Name = $name; Region = $row.Region; Flags = $row.Flags
        Shown = $(if ($row.Shown) { 'yes' } else { 'no' }); Runs = (Get-FutureRuns $row) }
}

function Get-LastText($rows) {
    $ends = @($rows | Where-Object { $_.Last } | ForEach-Object { $_.Last.End })
    if ($ends.Count -eq 0) { return 'none' }
    $max = ($ends | Measure-Object -Maximum).Maximum
    if ($max -eq [datetime]::MaxValue) { return 'never' }
    return Format-Day $max
}

function Get-State($kind, [string]$name, $rows) {
    $rows = @($rows)
    $last = Get-LastText $rows
    $toCome = @($rows | Where-Object { $_.ToCome }).Count -gt 0
    $soon = $toCome -and $last -ne 'never' -and (ConvertTo-Day $last) -le $soonEnd
    $shown = @($rows | Where-Object { $_.Shown }).Count -gt 0
    return [pscustomobject]@{
        Kind = $kind; Name = $name; IDs = (@($rows | ForEach-Object { $_.ID } | Sort-Object) -join ' ')
        ToCome = $(if ($toCome) { 'yes' } else { 'no' }); Last = $last; Soon = $(if ($soon) { 'yes' } else { 'no' })
        Shown = $(if ($shown) { 'yes' } else { 'no' })
    }
}

function Get-LastWords($state, $rows) {
    if ($state.ToCome -eq 'no') { return $(if ($state.Last -eq 'none') { 'never dated' } else { "no date to come, last $($state.Last)" }) }
    if ($state.Last -eq 'never') { return (@($rows | Where-Object { $_.Repeat } | ForEach-Object { $_.Repeat } | Sort-Object -Unique) -join ', ') }
    return "last $($state.Last)" + $(if ($state.Soon -eq 'yes') { ", within $SoonDays days" } else { '' })
}

function Get-FirstRun($rows) {
    $best = $null
    foreach ($row in $rows) {
        $run = Get-Next $row
        if ($run -and (-not $best -or $run.Start -lt $best.Run.Start)) { $best = [pscustomobject]@{ Row = $row; Run = $run } }
    }
    return $best
}

function Get-RowWords($row) {
    $next = Get-Next $row
    if ($next) { return "next $(Format-Day $next.Start)" }
    $last = Get-LastText @($row)
    if ($last -eq 'none') { return 'never dated' }
    return "last $last"
}

function Format-Run($first, [bool]$withID) {
    return "$(Format-Time $first.Run.Start) to $(Format-Time $first.Run.End)" + $(if ($withID) { " ($($first.Row.ID))" } else { '' })
}

# The entry that covers a row: one of its IDs, or its name, or its $HolidayRowPatterns pattern.
function Get-CoveringEntry($row) {
    foreach ($e in $entries) {
        if ($e.IDs -contains $row.ID) { return $e.Name }
        if (-not $row.Name) { continue }
        $pattern = $HolidayRowPatterns[$e.Name]
        if ($pattern) { if ($row.Name -match $pattern.Pattern) { return $e.Name } }
        elseif ($row.Name -eq $e.Name) { return $e.Name }
    }
    return $null
}

function Write-Entries($game) {
    Write-Output "== $($game.Label) $($game.Build): qcHolidays, the next run in region $Region and the last date the table holds in any region"
    foreach ($e in $entries) {
        $rows = @($e.IDs | Where-Object { $game.Rows.ContainsKey($_) } | ForEach-Object { $game.Rows[$_] })
        $state = Get-State 'entry' $e.Name $rows
        $game.States.Add($state)
        foreach ($row in $rows) { $game.RowStates[$row.ID] = Get-RowState $row 'entry' $e.Name }
        $unused = if (($game.InUse -band $e.Flag) -eq 0) { ' (no quest of this game has it)' } else { '' }
        if ($e.IDs.Count -eq 0) { Write-Output "  $($e.Name): no ID, never on the calendar$unused"; continue }
        if ($rows.Count -eq 0) { Write-Output "  $($e.Name): $($e.IDs -join ', ') not in this table$unused"; continue }
        $first = Get-FirstRun @($rows | Where-Object { $_.Ours -and $_.Shown })
        $text = if ($first) { "next $(Format-Run $first $true); $(Get-LastWords $state $rows)" }
            elseif ($state.ToCome -eq 'yes') { "not on the calendar in region $Region; $(Get-LastWords $state $rows)" }
            else { Get-LastWords $state $rows }
        $others = @(foreach ($row in $rows) {
            if ($first -and $row.ID -eq $first.Row.ID) { continue }
            $where = if (-not $row.Ours) { ' (other regions)' } elseif (-not $row.Shown) { ' (not shown by its Flags)' } else { '' }
            "$($row.ID)$where " + (Get-RowWords $row)
        })
        $missing = @($e.IDs | Where-Object { -not $game.Rows.ContainsKey($_) })
        if ($others.Count) { $text += '; ' + ($others -join '; ') }
        if ($missing.Count) { $text += "; $($missing -join ', ') not in this table" }
        Write-Output "  $($e.Name): $text$unused"
    }
}

function Write-Events($game) {
    $byName = @{}
    foreach ($row in $game.Rows.Values) {
        if (Get-CoveringEntry $row) { continue }
        $key = if ($row.Name) { $row.Name } else { "#$($row.ID)" }
        if (-not $byName.ContainsKey($key)) { $byName[$key] = New-Object System.Collections.Generic.List[object] }
        $byName[$key].Add($row)
    }
    $lines = @{ shown = (New-Object System.Collections.Generic.List[string]); hidden = (New-Object System.Collections.Generic.List[string]); elsewhere = (New-Object System.Collections.Generic.List[string]) }
    $nameless = @{ shown = @(); hidden = @(); elsewhere = @() }
    foreach ($key in ($byName.Keys | Sort-Object { $_ -notlike '#*' }, { if ($_ -like '#*') { [int]$_.Substring(1) } else { $_ } })) {
        $rows = @($byName[$key] | Sort-Object ID)
        $state = Get-State 'event' $key $rows
        if ($state.ToCome -ne 'yes') { $game.Undated["event|$key"] = $state; continue }
        $game.States.Add($state)
        $dated = @($rows | Where-Object { $_.ToCome })
        foreach ($row in $dated) { $game.RowStates[$row.ID] = Get-RowState $row 'event' $key }
        $oursShown = @($dated | Where-Object { $_.Ours -and $_.Shown })
        $oursHidden = @($dated | Where-Object { $_.Ours -and -not $_.Shown })
        $elsewhere = @($dated | Where-Object { -not $_.Ours })
        $group = if ($oursShown.Count) { 'shown' } elseif ($oursHidden.Count) { 'hidden' } else { 'elsewhere' }
        $ids = @(switch ($group) { 'shown' { $oursShown } 'hidden' { $oursHidden } default { $elsewhere } })
        $first = Get-FirstRun $ids
        $when = $(if ($first) { "next $(Format-Run $first ($ids.Count -gt 1))" + '; ' } else { '' }) + (Get-LastWords $state $rows)
        $flags = if ($group -eq 'hidden') { ", Flags $(@($ids | ForEach-Object { $_.Flags } | Sort-Object -Unique) -join ' ')" } else { '' }
        if (-not $rows[0].Name) {
            $nameless[$group] += "$($rows[0].ID) ($(if ($first) { "next $(Format-Day $first.Run.Start), " } else { '' })$(Get-LastWords $state $rows)$flags)"
            continue
        }
        $line = "    $key ($(@($ids | ForEach-Object { $_.ID }) -join ', ')"
        if ($group -eq 'shown' -and $oursHidden.Count) { $line += "; not shown by their Flags: $(@($oursHidden | ForEach-Object { $_.ID }) -join ', ')" }
        if ($group -ne 'elsewhere' -and $elsewhere.Count) { $line += "; $($elsewhere.Count) more for other regions" }
        $lines[$group].Add("$line)$(if ($flags) { " [$($flags.Substring(2))]" }): $when")
    }
    Write-Output "== $($game.Label) $($game.Build): events dated to come that no entry covers"
    $titles = @{
        shown = "On the calendar in region $Region, so /qc holidays lists them under ""Other calendar holidays"" when they fall in its 12 months"
        hidden = "Dated in region $Region but not expected on the calendar: their Flags lack 1 or hold 2, or they have no name"
        elsewhere = "Dated for other regions only"
    }
    foreach ($group in 'shown', 'hidden', 'elsewhere') {
        Write-Output "  $($titles[$group]) ($($lines[$group].Count + $nameless[$group].Count)):"
        $lines[$group] | ForEach-Object { Write-Output $_ }
        if ($nameless[$group].Count) { Write-Output "    with no name: $($nameless[$group] -join '; ')" }
    }
}

# The lines of /qc holidays as qcPrintHolidays prints them, every filter of the calendar window ticked:
# the entries this game's quests have, each with the IDs the calendar shows in the 12 months, soonest
# first, and the calendar's other holidays by ID.
function Write-Preview($game) {
    Write-Output "== What /qc holidays should print on $($game.Label) in region $Region on $(Format-Day $Today)"
    Write-Output "Seasonal quests follow these calendar holidays:"
    $onCalendar = @($game.Rows.Values | Where-Object { $_.Ours -and $_.Shown -and $_.Runs.Count })
    $tracked = @{}
    foreach ($e in $entries) {
        if (($game.InUse -band $e.Flag) -eq 0) { continue }
        foreach ($id in $e.IDs) { $tracked[$id] = $true }
        $seen = @($onCalendar | Where-Object { $e.IDs -contains $_.ID } | ForEach-Object {
            $run = $_.Runs[0]
            [pscustomobject]@{ Row = $_; Run = $run; Day = $(if ($run.Start -lt $Today) { $Today } else { $run.Start.Date }) }
        } | Sort-Object Day, { $_.Row.ID })
        if ($seen.Count -eq 0) { Write-Output "  $($e.Name): not on the calendar in the next 12 months"; continue }
        for ($i = 0; $i -lt $seen.Count; $i++) {
            $s = $seen[$i]
            $running = if ($i -eq 0 -and $s.Run.Start -le $Today -and $Today -lt $s.Run.End) { 'Running ' } else { '' }
            Write-Output "$(if ($i -eq 0) { '  ' } else { '    ' })$running$($s.Row.Name) ($($s.Row.ID)): $(Format-Time $s.Run.Start) to $(Format-Time $s.Run.End)"
        }
    }
    $others = @($onCalendar | Where-Object { -not $tracked.ContainsKey($_.ID) } | Sort-Object ID)
    if ($others.Count) {
        Write-Output "  Other calendar holidays, not tied to any quest:"
        foreach ($row in $others) { Write-Output "    $($row.Name) ($($row.ID))" }
    }
}

function New-Note([string]$key, [bool]$fail, [string]$text, [string]$what) {
    return [pscustomobject]@{ Key = $key; Fail = $fail; Text = $text; What = $what }
}

# What changed in a row since the baseline ($o, a row of the -rows file; $n, the row now, or $null when the
# table lacks it). Only runs still to come count: one that started since the baseline is no change.
function Compare-Row([string]$key, $o, $n) {
    $id = $o.ID
    $strict = $o.Kind -eq 'entry' -or ($n -and $n.Kind -eq 'entry') -or $o.Shown -eq 'yes'
    $days = @(Get-RunDays $o.Runs)
    $repeat = [bool]$o.Runs -and $days.Count -eq 0
    $coming = @($days | Where-Object { (ConvertTo-Day $_) -gt $Today })
    $hadToCome = $repeat -or $coming.Count -gt 0
    if (-not $n) {
        if ($hadToCome) { return New-Note $key $strict "$id`: gone from the table, with runs to come ($(if ($repeat) { $o.Runs } else { $coming -join ', ' }))" 'gone' }
        return New-Note $key $false "$id`: gone from the table" 'gone'
    }
    $nowDays = @(Get-RunDays $n.Runs)
    $nowRepeat = [bool]$n.Runs -and $nowDays.Count -eq 0
    if ($repeat -and $nowRepeat) {
        if ($n.Runs -ne $o.Runs) { New-Note $key $false "$id`: repeats $($n.Runs) now, was $($o.Runs)" 'repeat' }
    } elseif ($repeat) {
        New-Note $key $strict "$id`: no longer repeats ($($o.Runs)): $(if ($nowDays.Count) { "its runs to come are $($nowDays -join ', ')" } else { 'no date to come' })" 'lost'
    } elseif ($nowRepeat) {
        New-Note $key $false "$id`: repeats $($n.Runs) now" 'added'
    } else {
        $lost = @($coming | Where-Object { $nowDays -notcontains $_ })
        $added = @($nowDays | Where-Object { $days -notcontains $_ })
        if ($lost.Count) {
            $s = $lost.Count -gt 1
            New-Note $key $strict "$id`: run$(if ($s) { 's' }) of $($lost -join ', ') removed before $(if ($s) { 'they' } else { 'it' }) came$(if (-not $nowDays.Count) { '; no date to come now' })" 'lost'
        }
        if ($added.Count) {
            if ($hadToCome) { New-Note $key $false "$id`: more runs: $($added -join ', ')" 'added' }
            else { New-Note $key ($o.Kind -eq 'entry' -or $n.Kind -eq 'entry') "$id`: dated to come again: $($added -join ', ')" 'again' }
        }
    }
    $toCome = $hadToCome -or [bool]$n.Runs
    if ($o.Shown -ne $n.Shown) {
        $why = if ($o.Flags -ne [string]$n.Flags) { "Flags $($o.Flags) -> $($n.Flags)" } else { 'its name' }
        $text = if ($n.Shown -eq 'yes') { "now on the calendar by its Flags and name ($why)" } else { "off the calendar by its Flags or name ($why)" }
        New-Note $key $toCome "$id`: $text" 'shown'
    }
    if ($o.Region -ne [string]$n.Region) {
        $was = Test-HolidayRegion ([pscustomobject]@{ Region = $o.Region }) $Region
        $is = Test-HolidayRegion ([pscustomobject]@{ Region = $n.Region }) $Region
        if ($was -ne $is -and $toCome -and ($o.Shown -eq 'yes' -or $n.Shown -eq 'yes')) {
            New-Note $key $true "$id`: $(if ($is) { 'onto' } else { 'off' }) region $Region's calendar by its Region ($($o.Region) -> $($n.Region))" 'region'
        } else { New-Note $key $false "$id`: Region $($o.Region) -> $($n.Region)" 'region' }
    }
}

function Compare-Baseline($games) {
    $run = @($games | ForEach-Object { $_.Key })
    Write-Output "== Against the baseline, $BaselineFile and its -rows and -facts files"
    $now = @{}
    foreach ($g in $games) { foreach ($s in $g.States) { $now["$($g.Key)|$($s.Kind)|$($s.Name)"] = $s } }
    $missing = @($BaselineFile, $RowsFile, $FactsFile | Where-Object { -not (Test-Path $_) } | ForEach-Object { Split-Path -Leaf $_ })
    if ($missing.Count) {
        Write-Output "  There is no baseline ($($missing -join ', ') missing): the $($now.Count) entries and dated events of this run would all be new. -UpdateBaseline writes one from this run."
        $findings.Add('no baseline')
        return
    }
    $old = @{}
    foreach ($b in (Import-Csv $BaselineFile)) { if ($run -contains $b.Game) { $old["$($b.Game)|$($b.Kind)|$($b.Name)"] = $b } }
    $byKey = @{}
    foreach ($g in $games) { $byKey[$g.Key] = $g }
    $notes = New-Object System.Collections.Generic.List[object]
    $oldRows = @{}
    foreach ($b in (Import-Csv $RowsFile)) { if ($run -contains $b.Game) { $oldRows["$($b.Game)|$($b.ID)"] = $b } }
    foreach ($o in $oldRows.Values) {
        $g = $byKey[$o.Game]
        $id = [int]$o.ID
        $n = $g.RowStates[$id]
        if (-not $n -and $g.Rows.ContainsKey($id)) {
            $row = $g.Rows[$id]
            $cover = Get-CoveringEntry $row
            $n = if ($cover) { Get-RowState $row 'entry' $cover } else { Get-RowState $row 'event' $(if ($row.Name) { $row.Name } else { "#$id" }) }
        }
        $key = if ($n) { "$($o.Game)|$($n.Kind)|$($n.Name)" } else { "$($o.Game)|$($o.Kind)|$($o.Name)" }
        foreach ($note in @(Compare-Row $key $o $n)) { $notes.Add($note) }
    }
    foreach ($g in $games) {
        $fresh = @{}
        foreach ($n in ($g.RowStates.Values | Sort-Object ID)) {
            $key = "$($g.Key)|$($n.Kind)|$($n.Name)"
            if ($oldRows.ContainsKey("$($g.Key)|$($n.ID)") -or -not $n.Runs -or -not $old.ContainsKey($key)) { continue }
            if (-not $fresh.ContainsKey($key)) { $fresh[$key] = @() }
            $fresh[$key] += "$($n.ID) ($($n.Runs))"
        }
        foreach ($key in $fresh.Keys) { $notes.Add((New-Note $key $false "rows new to the baseline, dated to come: $($fresh[$key] -join '; ')" 'added')) }
    }
    foreach ($key in (@($now.Keys) + @($old.Keys) | Sort-Object -Unique)) {
        $n = $now[$key]; $o = $old[$key]
        $part = $key -split '\|', 3
        $g = $byKey[$part[0]]
        if (-not $n) { $n = $g.Undated["$($part[1])|$($part[2])"] }
        $strict = $part[1] -eq 'entry' -or ($o -and $o.Shown -eq 'yes')
        $mine = @($notes | Where-Object { $_.Key -eq $key })
        $add = { param([bool]$fail, [string]$text, [string]$what) $notes.Add((New-Note $key $fail $text $what)) }
        if (-not $o) {
            if ($part[1] -eq 'entry') { & $add $false "new entry, $(if ($n.ToCome -eq 'yes') { "dated to come (last $($n.Last))" } else { 'with no date to come' })" 'new' }
            elseif ($n.ToCome -eq 'yes') { & $add $true "new, dated to come (last $($n.Last))$(if ($n.Shown -eq 'no') { ', not on the calendar by its Flags or name' })" 'new' }
            else { & $add $false 'new, with no date to come' 'new' }
            continue
        }
        if (-not $n) {
            if ($part[1] -eq 'entry') { & $add $false 'not in qcHolidays any more' 'gone'; continue }
            $covers = @($o.IDs -split ' ' | Where-Object { $_ -and $g.Rows.ContainsKey([int]$_) } | ForEach-Object { Get-CoveringEntry $g.Rows[[int]$_] } | Where-Object { $_ } | Sort-Object -Unique)
            if ($covers.Count) { & $add $false "now covered by the entry $($covers -join ', ')" 'covered'; continue }
            foreach ($note in $mine) { if ($note.What -eq 'gone') { [void]$notes.Remove($note) } }
            if ($o.ToCome -eq 'yes') { & $add $strict "gone from the table, which had dates to come $(if ($o.Last -eq 'never') { 'with no end' } else { "to $($o.Last)" })" 'gone' } else { & $add $false 'gone from the table' 'gone' }
            continue
        }
        if ($o.ToCome -eq 'yes' -and $n.ToCome -eq 'no') { & $add $strict "has no date to come any more (last $($n.Last))" 'lost' }
        if ($o.ToCome -eq 'no' -and $n.ToCome -eq 'yes') { & $add $true "has dates to come again (last $($n.Last))" 'again' }
        if ($o.Last -ne $n.Last) {
            $earlier = $n.Last -eq 'none' -or ($o.Last -eq 'never') -or ($o.Last -ne 'none' -and $n.Last -ne 'never' -and $n.Last -lt $o.Last)
            if ($earlier -and $n.ToCome -eq 'yes') {
                if (-not @($mine | Where-Object { $_.What -eq 'lost' }).Count) { & $add $strict "dates removed: its last date was $($o.Last), now $($n.Last)" 'lost' }
            }
            elseif ($earlier) { & $add $false "last date $($o.Last) -> $($n.Last)" 'lost' }
            else { & $add $false "more dates: last $($o.Last) -> $($n.Last)" 'added' }
        }
        if ($o.Soon -eq 'no' -and $n.Soon -eq 'yes') { & $add $strict "its dates run out on $($n.Last), within $SoonDays days" 'soon' }
        if ($o.Shown -ne $n.Shown -and -not @($mine | Where-Object { $_.What -eq 'shown' }).Count) {
            & $add $true $(if ($n.Shown -eq 'yes') { 'now on the calendar by its Flags and name' } else { 'no longer on the calendar by its Flags and name' }) 'shown'
        }
        if ($o.IDs -ne $n.IDs) {
            & $add $false "rows $($o.IDs) -> $($n.IDs)" 'rows'
            $covers = @($o.IDs -split ' ' | Where-Object { $_ -and ($n.IDs -split ' ') -notcontains $_ -and $g.Rows.ContainsKey([int]$_) } | ForEach-Object { Get-CoveringEntry $g.Rows[[int]$_] } | Where-Object { $_ } | Sort-Object -Unique)
            if ($covers.Count) { & $add $false "some rows now covered by the entry $($covers -join ', ')" 'covered' }
        }
    }
    $before = $findings.Count
    $changes = 0
    foreach ($key in (@($notes | ForEach-Object { $_.Key }) | Sort-Object -Unique)) {
        $part = $key -split '\|', 3
        $label = "$($part[0]) $($part[1]) ""$($part[2])"""
        $mine = @($notes | Where-Object { $_.Key -eq $key })
        foreach ($note in @($mine | Where-Object { $_.Fail })) { Write-Output "  FINDING $label`: $($note.Text)"; $findings.Add("$label`: $($note.Text)") }
        foreach ($note in @($mine | Where-Object { -not $_.Fail })) { Write-Output "  changed $label`: $($note.Text)"; $changes++ }
    }
    Write-Output "  $($findings.Count - $before) finding(s) and $changes other change(s) against the baseline."
}

function Write-Csv([string]$path, [string[]]$columns, $rows) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((@($columns | ForEach-Object { '"' + $_ + '"' }) -join ','))
    foreach ($r in $rows) { $lines.Add((@($columns | ForEach-Object { '"' + ([string]$r.$_).Replace('"', '""') + '"' }) -join ',')) }
    [IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $true))
    return $lines.Count - 1
}

function Write-Baseline($games) {
    $run = @($games | ForEach-Object { $_.Key })
    $order = @{ retail = 0; ptr = 1; forever = 2 }
    $kept = { param($file) if (Test-Path $file) { @(Import-Csv $file | Where-Object { $run -notcontains $_.Game }) } else { @() } }
    $states = @(& $kept $BaselineFile) + @(foreach ($g in $games) { foreach ($s in $g.States) {
        [pscustomobject]@{ Game = $g.Key; Kind = $s.Kind; Name = $s.Name; IDs = $s.IDs; ToCome = $s.ToCome; Last = $s.Last; Soon = $s.Soon; Shown = $s.Shown } } })
    $rows = @(& $kept $RowsFile) + @(foreach ($g in $games) { foreach ($s in $g.RowStates.Values) {
        [pscustomobject]@{ Game = $g.Key; ID = $s.ID; Kind = $s.Kind; Name = $s.Name; Region = $s.Region; Flags = $s.Flags; Shown = $s.Shown; Runs = $s.Runs } } })
    $facts = @(& $kept $FactsFile) + $FactOutcomes.ToArray()
    $counts = @(
        (Write-Csv $BaselineFile @('Game', 'Kind', 'Name', 'IDs', 'ToCome', 'Last', 'Soon', 'Shown') ($states | Sort-Object { $order[$_.Game] }, Kind, Name)),
        (Write-Csv $RowsFile @('Game', 'ID', 'Kind', 'Name', 'Region', 'Flags', 'Shown', 'Runs') ($rows | Sort-Object { $order[$_.Game] }, { [int]$_.ID })),
        (Write-Csv $FactsFile @('Game', 'Decision', 'Fact', 'Outcome') ($facts | Sort-Object { $order[$_.Game] }, Decision, Fact)))
    Write-Output "Baseline written: $($counts[0]) entries and events -> $BaselineFile; $($counts[1]) rows -> $RowsFile; $($counts[2]) fact outcomes -> $FactsFile"
}

# Whether some weekly bonus event ($WeeklyEventPattern) is on the region's calendar, by its Flags, name and
# Region, every day from today to the last day the table dates one there: the days without one, and the
# unbroken stretch from today.
function Get-WeeklyCover($game, [int]$region) {
    $dated = @(foreach ($row in $game.Rows.Values) {
        if (-not $row.Weekly -or -not $row.Shown -or -not $row.ToCome -or -not (Test-HolidayRegion $row.Row $region)) { continue }
        $row
    })
    if ($dated.Count -eq 0) { return @{ Outcome = 'fails'; Why = "no weekly bonus event is dated to come on region $region's calendar" } }
    $lastEnd = ($dated | ForEach-Object { $_.Last.End } | Measure-Object -Maximum).Maximum
    $until = if ($lastEnd -eq [datetime]::MaxValue) { $Today.AddYears(1) } else { $lastEnd.AddTicks(-1).Date }
    $through = if ($lastEnd -eq [datetime]::MaxValue) { "for a year, as one of them repeats" } else { "to $(Format-Day $until), the last day the table dates one for region $region" }
    $runs = @(foreach ($row in $dated) { Get-HolidayRuns $row.Row $Today $until.AddDays(1) })
    $covered = { param([datetime]$day) foreach ($r in $runs) { if ($r.Start -lt $day.AddDays(1) -and $r.End -gt $day) { return $true } }; return $false }
    $gaps = New-Object System.Collections.Generic.List[string]
    $gapDays = 0; $from = $null; $to = $null; $unbroken = $null
    for ($day = $Today; $day -le $until; $day = $day.AddDays(1)) {
        if (& $covered $day) {
            if ($from) { $gaps.Add($(if ($from -eq $to) { Format-Day $from } else { "$(Format-Day $from) to $(Format-Day $to)" })); $from = $null }
            if ($gapDays -eq 0) { $unbroken = $day }
            continue
        }
        $gapDays++
        if (-not $from) { $from = $day }
        $to = $day
    }
    if ($from) { $gaps.Add($(if ($from -eq $to) { Format-Day $from } else { "$(Format-Day $from) to $(Format-Day $to)" })) }
    if ($gaps.Count -eq 0) { return @{ Outcome = 'holds'; Why = "every day from today $through" } }
    $reach = if ($unbroken) { "unbroken from today to $(Format-Day $unbroken)" } else { 'none runs today' }
    return @{ Outcome = 'fails'; Why = "no weekly bonus event on $($gaps -join ', ') ($gapDays day$(if ($gapDays -gt 1) { 's' })), from today $through; $reach" }
}

# A yearly entry ($HolidayRowPatterns, or its IDs): one of its rows on the region's calendar has a date to
# come; or, between two years, it waits until a year after its last run began, when the next year's row is due.
function Test-Yearly($game, [string]$name) {
    $entry = @($entries | Where-Object { $_.Name -eq $name })[0]
    if (-not $entry) { throw "No qcHolidays entry is named '$name' (fact 'yearly $name' in $DecisionsFile)" }
    $pattern = $HolidayRowPatterns[$name]
    $mine = @(foreach ($row in $game.Rows.Values) {
        if (-not ($entry.IDs -contains $row.ID -or ($pattern -and $row.Name -match $pattern.Pattern))) { continue }
        if ($row.Shown -and $row.Ours) { $row }
    })
    if ($mine.Count -eq 0) { return @{ Outcome = 'fails'; Why = "no row of it is on region $Region's calendar" } }
    $dated = @($mine | Where-Object { $_.ToCome } | Sort-Object ID)
    if ($dated.Count) { return @{ Outcome = 'holds'; Why = (@($dated | ForEach-Object { "$($_.ID) $(Get-RowWords $_)" }) -join '; ') } }
    $last = @($mine | Where-Object { $_.Last } | Sort-Object { $_.Last.Start } | Select-Object -Last 1)[0]
    if (-not $last) { return @{ Outcome = 'fails'; Why = 'never dated' } }
    $due = $last.Last.Start.AddYears(1)
    if ($Today -lt $due.Date) { return @{ Outcome = 'waits'; Why = "$($last.ID)'s run ended $(Format-Day $last.Last.End), and the table has no later row yet: the next year's is due by $(Format-Day $due), a year after $($last.ID) began; until it is in the table and the entry, the entry has no date to come" } }
    return @{ Outcome = 'fails'; Why = "no row dated since $($last.ID) began on $(Format-Day $last.Last.Start): the next year's was due by $(Format-Day $due)" }
}

function Test-Fact($game, [string]$fact) {
    $words = @($fact -split '\s+' | Where-Object { $_ })
    $ids = @($words | Select-Object -Skip 1 | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    $missing = @($ids | Where-Object { -not $game.Rows.ContainsKey($_) })
    switch ($words[0]) {
        'dated' {
            if ($missing.Count) { return @{ Outcome = 'fails'; Why = "no row $($missing -join ', ')" } }
            $what = @($ids | ForEach-Object { "$_ $(Get-RowWords $game.Rows[$_])" }) -join '; '
            $bad = @($ids | Where-Object { -not $game.Rows[$_].ToCome })
            if ($bad.Count) { return @{ Outcome = 'fails'; Why = "no date to come for $($bad -join ', ') ($what)" } }
            return @{ Outcome = 'holds'; Why = $what }
        }
        'no-date' {
            $what = @($ids | ForEach-Object { if ($game.Rows.ContainsKey($_)) { "$_ $(Get-RowWords $game.Rows[$_])" } else { "$_ no row" } }) -join '; '
            $bad = @($ids | Where-Object { $game.Rows.ContainsKey($_) -and $game.Rows[$_].ToCome })
            if ($bad.Count) { return @{ Outcome = 'fails'; Why = "dated again: $what" } }
            return @{ Outcome = 'holds'; Why = $what }
        }
        'hidden' {
            if ($missing.Count) { return @{ Outcome = 'fails'; Why = "no row $($missing -join ', ')" } }
            $what = "Flags " + (@($ids | ForEach-Object { $game.Rows[$_].Flags }) -join ', ')
            $bad = @($ids | Where-Object { $game.Rows[$_].Shown })
            if ($bad.Count) { return @{ Outcome = 'fails'; Why = "$($bad -join ', ') would now be on the calendar ($what)" } }
            return @{ Outcome = 'holds'; Why = $what }
        }
        'no-row' {
            $name = ($fact -replace '^\s*no-row\s+', '').Trim()
            $found = @($game.Rows.Values | Where-Object { $_.Name -eq $name } | ForEach-Object { $_.ID } | Sort-Object)
            if ($found.Count) { return @{ Outcome = 'fails'; Why = "rows $($found -join ', ') have that name" } }
            $named = @($game.Names.Values | Where-Object { $_ -eq $name }).Count -gt 0
            return @{ Outcome = 'holds'; Why = $(if ($named) { 'HolidayNames has the name, and no Holidays row uses it' } else { 'not in HolidayNames either' }) }
        }
        'weekly-every-day' {
            if ($words.Count -ne 2 -or $words[1] -notmatch '^\d+$') { throw "weekly-every-day takes a region and nothing else: '$fact' in $DecisionsFile" }
            return Get-WeeklyCover $game ([int]$words[1])
        }
        'yearly' { return Test-Yearly $game ($fact -replace '^\s*yearly\s+', '').Trim() }
        default { throw "Unknown fact '$fact' in $DecisionsFile" }
    }
}

function Write-Decisions($games) {
    Write-Output "== Decisions that rest on the calendar, $DecisionsFile"
    if (-not (Test-Path $DecisionsFile)) { Write-Output "  There is no decisions file."; return }
    $byGame = @{}
    foreach ($g in $games) { $byGame[$g.Key] = $g }
    $stored = $null
    if (Test-Path $FactsFile) {
        $stored = @{}
        foreach ($b in (Import-Csv $FactsFile)) { $stored["$($b.Game)|$($b.Decision)|$($b.Fact)"] = $b.Outcome }
    }
    $count = @{ holds = 0; waits = 0; fails = 0; open = 0; changed = 0; new = 0 }
    $listed = New-Object System.Collections.Generic.List[string]
    $groups = [ordered]@{}
    foreach ($d in (Import-Csv $DecisionsFile)) {
        if (-not $groups.Contains($d.Decision)) { $groups[$d.Decision] = New-Object System.Collections.Generic.List[object] }
        $groups[$d.Decision].Add($d)
    }
    foreach ($name in $groups.Keys) {
        $first = $groups[$name][0]
        Write-Output "  $name ($($first.Decided); $($first.Recorded))"
        foreach ($d in $groups[$name]) {
            $verb = ($d.Fact -split '\s+')[0]
            if ($verb -eq 'none') { Write-Output "    no fact  $($d.Game): nothing in the tables to check"; continue }
            if ($verb -in 'served', 'not-served', 'ask') {
                if ($d.Seen) { Write-Output "    seen     $($d.Game): $($d.Fact): $($d.Seen)"; $count.holds++; continue }
                $count.open++
                $table = $byGame[$d.Game]
                $when = ''
                if ($verb -eq 'served' -and $table) {
                    $when = ': ' + (@(($d.Fact -split '\s+' | Select-Object -Skip 1) | ForEach-Object {
                        $row = $table.Rows[[int]$_]
                        if (-not $row) { "$_ has no row" }
                        elseif (-not $row.Ours) { "$_ is for other regions, which region $Region's calendar can't show" }
                        elseif ($row.Runs.Count) { "$_ is dated $(Format-Day $row.Runs[0].Start), in the 12 months /qc holidays reads, so it should list it now" }
                        elseif ($row.ToCome) { "$_ is next dated $(Format-Day (Get-Next $row).Start), beyond the 12 months /qc holidays reads" }
                        else { "$_ has no date to come" }
                    }) -join '; ')
                }
                Write-Output "    open     $($d.Game): $($d.Fact)$when"
                $listed.Add("    open     $($d.Game): $($d.Fact) ($name)")
                continue
            }
            $targets = @(@($(if ($d.Game -eq 'retail') { $byGame['retail']; $byGame['ptr'] } else { $byGame[$d.Game] })) | Where-Object { $_ })
            if ($targets.Count -eq 0) { Write-Output "    skipped  $($d.Game): $($d.Fact) (no table of that game given)"; continue }
            for ($i = 0; $i -lt $targets.Count; $i++) {
                $t = $targets[$i]
                $result = Test-Fact $t $d.Fact
                $outcome = $result.Outcome
                if ($i -eq 0) { $firstOutcome = $outcome }
                $FactOutcomes.Add([pscustomobject]@{ Game = $t.Key; Decision = $name; Fact = $d.Fact; Outcome = $outcome })
                $was = if ($null -ne $stored) { $stored["$($t.Key)|$name|$($d.Fact)"] } else { $null }
                $changed = $null -ne $stored -and $was -and $was -ne $outcome
                if ($i -gt 0 -and $outcome -eq $firstOutcome -and -not $changed -and ($null -eq $stored -or $was)) { continue }
                $on = "$($t.Label) $($t.Build)"
                $count[$outcome]++
                Write-Output "    $($outcome.PadRight(8)) $on`: $($d.Fact)$(if ($outcome -eq 'holds') { " ($($result.Why))" } else { ": $($result.Why)" })"
                if ($outcome -ne 'holds') { $listed.Add("    $($outcome.PadRight(8)) $on`: $($d.Fact) ($name)") }
                if ($changed) {
                    Write-Output "             FINDING: $was at the baseline, $outcome now. Revisit: $($d.IfChanged)"
                    $findings.Add("$name`: $($d.Fact) on $on, $was -> $outcome"); $count.changed++
                }
                elseif ($null -ne $stored -and -not $was) { Write-Output "             new: no outcome in the baseline yet"; $count.new++ }
            }
        }
    }
    Write-Output "  $($count.holds) hold or were seen in game, $($count.waits) wait, $($count.fails) fail, $($count.open) open for the game to answer; $($count.changed) outcome(s) changed since the baseline, $($count.new) new."
    if ($null -eq $stored) { Write-Output "  No fact outcomes in the baseline yet: -UpdateBaseline records them." }
    if ($listed.Count) {
        Write-Output "  Not holding today, listed every sweep (a finding only when an outcome changes):"
        $listed | ForEach-Object { Write-Output $_ }
    }
}

$games = @(
    foreach ($g in @(@{ Key = 'retail'; Label = 'retail'; Build = $Build; Data = (Join-Path $DataDir 'quests.jsonl') },
        @{ Key = 'ptr'; Label = 'retail PTR'; Build = $PtrBuild; Data = (Join-Path $DataDir 'quests.jsonl') },
        @{ Key = 'forever'; Label = 'WoW: Forever'; Build = $ForeverBuild; Data = (Join-Path $DataDir 'forever\quests.jsonl') })) {
        if (-not $g.Build) { continue }
        $game = [pscustomobject]@{ Key = $g.Key; Label = $g.Label; Build = $g.Build; InUse = (Get-FlagsInUse $g.Data); Rows = $null; Names = $null
            States = (New-Object System.Collections.Generic.List[object]); Undated = @{}; RowStates = @{} }
        Read-Game $game
        $game
    })

Write-Output "Calendar review of $(Format-Day $Today) for region $Region (the rows whose Region is 0 or holds $Region); a last date within $SoonDays days counts as running out. Tables: $(@($games | ForEach-Object { "$($_.Label) $($_.Build)" }) -join ', ')."
$sections = @{}
foreach ($game in $games) { $sections[$game.Key] = @(Write-Entries $game; Write-Events $game) }
foreach ($game in $games) {
    if ($game.Key -ne 'ptr' -or -not $sections.ContainsKey('retail')) { $sections[$game.Key] | ForEach-Object { Write-Output $_ }; continue }
    $live = @($sections['retail'] | Where-Object { $_ -notlike '==*' })
    $ptr = @($sections['ptr'] | Where-Object { $_ -notlike '==*' })
    $liveOnly = @($live | Where-Object { $ptr -notcontains $_ })
    $ptrOnly = @($ptr | Where-Object { $live -notcontains $_ })
    Write-Output "== $($game.Label) $($game.Build): where its lines differ from live's ($($ptrOnly.Count) of $($ptr.Count))"
    foreach ($line in $liveOnly) { Write-Output "  live: $($line.Trim())" }
    foreach ($line in $ptrOnly) { Write-Output "  PTR:  $($line.Trim())" }
}
foreach ($game in $games) { if ($game.Key -ne 'ptr') { Write-Preview $game } }
Compare-Baseline $games
Write-Decisions $games
if ($UpdateBaseline) { Write-Baseline $games }
if ($findings.Count -gt 0) {
    Write-Output "$($findings.Count) finding(s): revisit what each names; once they and the changes are read, rerun with -UpdateBaseline."
    exit 1
}
Write-Output "No finding: the calendar tables say what the baseline and the decisions file expect."
