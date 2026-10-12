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
  - the comparison with the baseline (-BaselineFile, docs\plans\calendar-baseline.csv);
  - each fact of -DecisionsFile (docs\plans\calendar-decisions.csv), which lists the decisions taken on
    the calendar's word: whether it still holds, and the decision to revisit when it doesn't. A fact only
    the game can answer is listed as open until the file has the date it was seen.

The baseline holds every entry and every event with a date to come, per game (retail, ptr, forever): its
IDs, whether it has a date to come, its last date ("never" for a row dated every year, or looping),
whether that falls within -SoonDays, and whether a row of it is on the calendar by its Flags and name. A
finding (exit 1) is a new event with dates to come, an entry or event with dates to come again, one whose
rows come onto the calendar or leave it, and, for an entry or an event on the calendar, one that loses its
dates to come, is gone from the table, has its last date moved earlier (dates removed) or has it come
within -SoonDays of today. The same for an event off the calendar (a nameless row, the plain-named
"WoW's Anniversary" rows), more dates and new rows of an event are listed and don't fail. The next run
itself isn't compared, so the Darkmoon Faire's monthly move says nothing, and a sweep with nothing new is
silent. -UpdateBaseline rewrites the rows of the games run, once the findings are read. A fact that no
longer holds is a finding too.

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
$windowEnd = (New-Object DateTime $Today.Year, $Today.Month, 1).AddMonths(13).AddSeconds(-1)
$soonEnd = $Today.AddDays($SoonDays)
$entries = Read-QcHolidays $AddonDir
$findings = New-Object System.Collections.Generic.List[string]

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
            Filter = [int]$r.CalendarFilterType; Last = $last; ToCome = ($null -ne $last -and $last.End -ge $Today)
            Shown = (Test-HolidayShown $r $name); Ours = (Test-HolidayRegion $r $Region)
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
    $soon = $toCome -and $last -ne 'never' -and [datetime]::ParseExact($last, 'yyyy-MM-dd', $null) -le $soonEnd
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

function Test-Covered($row) {
    foreach ($e in $entries) {
        if ($e.IDs -contains $row.ID) { return $true }
        if (-not $row.Name) { continue }
        $pattern = $HolidayRowPatterns[$e.Name]
        if ($pattern) { if ($row.Name -match $pattern.Pattern) { return $true } }
        elseif ($row.Name -eq $e.Name) { return $true }
    }
    return $false
}

function Write-Entries($game) {
    Write-Output "== $($game.Label) $($game.Build): qcHolidays, the next run in region $Region and the last date the table holds in any region"
    foreach ($e in $entries) {
        $rows = @($e.IDs | Where-Object { $game.Rows.ContainsKey($_) } | ForEach-Object { $game.Rows[$_] })
        $state = Get-State 'entry' $e.Name $rows
        $game.States.Add($state)
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
        if (Test-Covered $row) { continue }
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

function Compare-Baseline($games) {
    $run = @($games | ForEach-Object { $_.Key })
    Write-Output "== Against the baseline, $BaselineFile"
    $now = @{}
    foreach ($g in $games) { foreach ($s in $g.States) { $now["$($g.Key)|$($s.Kind)|$($s.Name)"] = $s } }
    if (-not (Test-Path $BaselineFile)) {
        Write-Output "  There is no baseline: the $($now.Count) entries and dated events of this run would all be new. -UpdateBaseline writes one from this run."
        $findings.Add('no baseline')
        return
    }
    $old = @{}
    foreach ($b in (Import-Csv $BaselineFile)) { if ($run -contains $b.Game) { $old["$($b.Game)|$($b.Kind)|$($b.Name)"] = $b } }
    $byKey = @{}
    foreach ($g in $games) { $byKey[$g.Key] = $g }
    $before = $findings.Count
    $changes = 0
    foreach ($key in (@($now.Keys) + @($old.Keys) | Sort-Object -Unique)) {
        $n = $now[$key]; $o = $old[$key]
        $part = $key -split '\|', 3
        if (-not $n) { $n = $byKey[$part[0]].Undated["$($part[1])|$($part[2])"] }
        $label = "$($part[0]) $($part[1]) ""$($part[2])"""
        $say = @(); $fail = @()
        if (-not $o) {
            if ($n.ToCome -eq 'yes') { $fail += "new, dated to come (last $($n.Last))$(if ($n.Shown -eq 'no') { ', not on the calendar by its Flags or name' })" } else { $say += 'new, with no date to come' }
        } else {
            $lost = @()
            if (-not $n) {
                if ($o.ToCome -eq 'yes') { $lost += "gone from the table, which dated it to $($o.Last) (dates removed)" } else { $say += 'gone' }
            } else {
                if ($o.ToCome -eq 'yes' -and $n.ToCome -eq 'no') { $lost += "has no date to come any more (last $($n.Last))" }
                if ($o.ToCome -eq 'no' -and $n.ToCome -eq 'yes') { $fail += "has dates to come again (last $($n.Last))" }
                if ($o.Last -ne $n.Last) {
                    $earlier = $n.Last -eq 'none' -or ($o.Last -eq 'never') -or ($o.Last -ne 'none' -and $n.Last -ne 'never' -and $n.Last -lt $o.Last)
                    if ($earlier -and $n.ToCome -eq 'yes') { $lost += "dates removed: its last date was $($o.Last), now $($n.Last)" }
                    elseif ($earlier) { $say += "last date $($o.Last) -> $($n.Last)" }
                    else { $say += "more dates: last $($o.Last) -> $($n.Last)" }
                }
                if ($o.Soon -eq 'no' -and $n.Soon -eq 'yes') { $lost += "its dates run out on $($n.Last), within $SoonDays days" }
                if ($o.Shown -ne $n.Shown) { $fail += $(if ($n.Shown -eq 'yes') { 'now on the calendar by its Flags and name' } else { 'no longer on the calendar by its Flags and name' }) }
                if ($o.IDs -ne $n.IDs) { $say += "rows $($o.IDs) -> $($n.IDs)" }
            }
            if ($part[1] -eq 'entry' -or $o.Shown -eq 'yes') { $fail += $lost } else { $say += $lost }
        }
        foreach ($f in $fail) { Write-Output "  FINDING $label`: $f"; $findings.Add("$label`: $f") }
        foreach ($t in $say) { Write-Output "  changed $label`: $t"; $changes++ }
    }
    Write-Output "  $($findings.Count - $before) finding(s) and $changes other change(s) against the baseline."
}

function Write-Baseline($games) {
    $run = @($games | ForEach-Object { $_.Key })
    $rows = @()
    if (Test-Path $BaselineFile) { $rows = @(Import-Csv $BaselineFile | Where-Object { $run -notcontains $_.Game }) }
    foreach ($g in $games) { foreach ($s in $g.States) { $rows += [pscustomobject]@{ Game = $g.Key; Kind = $s.Kind; Name = $s.Name; IDs = $s.IDs; ToCome = $s.ToCome; Last = $s.Last; Soon = $s.Soon; Shown = $s.Shown } } }
    $order = @{ retail = 0; ptr = 1; forever = 2 }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('"Game","Kind","Name","IDs","ToCome","Last","Soon","Shown"')
    foreach ($r in ($rows | Sort-Object { $order[$_.Game] }, Kind, Name)) {
        $lines.Add((@($r.Game, $r.Kind, $r.Name, $r.IDs, $r.ToCome, $r.Last, $r.Soon, $r.Shown) | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }) -join ',')
    }
    [IO.File]::WriteAllText($BaselineFile, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $true))
    Write-Output "Baseline written: $($lines.Count - 1) rows -> $BaselineFile"
}

# Whether every day from today to $until has a run of a weekly event (the calendar window's Weekly
# Holidays filter, CalendarFilterType 0) on the region's calendar: the first day without one, and the last
# day of the unbroken stretch from today.
function Get-WeeklyCover($game, [int]$region, [datetime]$until) {
    $to = $until.AddDays(400)
    $runs = @(foreach ($row in $game.Rows.Values) {
        if ($row.Filter -ne 0 -or -not $row.Shown -or -not (Test-HolidayRegion $row.Row $region)) { continue }
        Get-HolidayRuns $row.Row $Today $to
    })
    $covered = { param([datetime]$day) foreach ($r in $runs) { if ($r.Start -lt $day.AddDays(1) -and $r.End -gt $day) { return $true } }; return $false }
    $gap = $null
    for ($day = $Today; $day -le $until; $day = $day.AddDays(1)) { if (-not (& $covered $day)) { $gap = $day; break } }
    $end = $null
    for ($day = $Today; $day -le $to; $day = $day.AddDays(1)) { if (& $covered $day) { $end = $day } else { break } }
    return [pscustomobject]@{ Gap = $gap; End = $end }
}

function Test-Fact($game, [string]$fact) {
    $words = @($fact -split '\s+' | Where-Object { $_ })
    $ids = @($words | Select-Object -Skip 1 | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    $missing = @($ids | Where-Object { -not $game.Rows.ContainsKey($_) })
    switch ($words[0]) {
        'dated' {
            if ($missing.Count) { return @{ Holds = $false; Why = "no row $($missing -join ', ')" } }
            $what = @($ids | ForEach-Object { "$_ $(Get-RowWords $game.Rows[$_])" }) -join '; '
            $bad = @($ids | Where-Object { -not $game.Rows[$_].ToCome })
            if ($bad.Count) { return @{ Holds = $false; Why = "no date to come for $($bad -join ', ') ($what)" } }
            return @{ Holds = $true; Why = $what }
        }
        'no-date' {
            $what = @($ids | ForEach-Object { if ($game.Rows.ContainsKey($_)) { "$_ $(Get-RowWords $game.Rows[$_])" } else { "$_ no row" } }) -join '; '
            $bad = @($ids | Where-Object { $game.Rows.ContainsKey($_) -and $game.Rows[$_].ToCome })
            if ($bad.Count) { return @{ Holds = $false; Why = "dated again: $what" } }
            return @{ Holds = $true; Why = $what }
        }
        'hidden' {
            if ($missing.Count) { return @{ Holds = $false; Why = "no row $($missing -join ', ')" } }
            $what = "Flags " + (@($ids | ForEach-Object { $game.Rows[$_].Flags }) -join ', ')
            $bad = @($ids | Where-Object { $game.Rows[$_].Shown })
            if ($bad.Count) { return @{ Holds = $false; Why = "$($bad -join ', ') would now be on the calendar ($what)" } }
            return @{ Holds = $true; Why = $what }
        }
        'no-row' {
            $name = ($fact -replace '^\s*no-row\s+', '').Trim()
            $found = @($game.Rows.Values | Where-Object { $_.Name -eq $name } | ForEach-Object { $_.ID } | Sort-Object)
            if ($found.Count) { return @{ Holds = $false; Why = "rows $($found -join ', ') have that name" } }
            $named = @($game.Names.Values | Where-Object { $_ -eq $name }).Count -gt 0
            return @{ Holds = $true; Why = $(if ($named) { 'HolidayNames has the name, and no Holidays row uses it' } else { 'not in HolidayNames either' }) }
        }
        'weekly-every-day' {
            $region = [int]$words[1]
            $until = [datetime]::ParseExact($words[2], 'yyyy-MM-dd', $null)
            $cover = Get-WeeklyCover $game $region $until
            $reach = if ($cover.End) { "the unbroken run of days with one lasts to $(Format-Day $cover.End)" } else { 'none runs today' }
            if ($until -lt $Today) { return @{ Holds = $false; Why = "its date has passed; $reach" } }
            if ($cover.Gap) { return @{ Holds = $false; Why = "no weekly event on $(Format-Day $cover.Gap) in region $region; $reach" } }
            return @{ Holds = $true; Why = "every day to $(Format-Day $until) in region $region; $reach" }
        }
        default { throw "Unknown fact '$fact' in $DecisionsFile" }
    }
}

function Write-Decisions($games) {
    Write-Output "== Decisions that rest on the calendar, $DecisionsFile"
    if (-not (Test-Path $DecisionsFile)) { Write-Output "  There is no decisions file."; return }
    $byGame = @{}
    foreach ($g in $games) { $byGame[$g.Key] = $g }
    $open = 0; $failed = 0; $held = 0
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
                if ($d.Seen) { Write-Output "    seen     $($d.Game): $($d.Fact): $($d.Seen)"; $held++; continue }
                $open++
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
                continue
            }
            $targets = @(@($(if ($d.Game -eq 'retail') { $byGame['retail']; $byGame['ptr'] } else { $byGame[$d.Game] })) | Where-Object { $_ })
            if ($targets.Count -eq 0) { Write-Output "    skipped  $($d.Game): $($d.Fact) (no table of that game given)"; continue }
            $results = @($targets | ForEach-Object { [pscustomobject]@{ Game = $_; Result = (Test-Fact $_ $d.Fact) } })
            for ($i = 0; $i -lt $results.Count; $i++) {
                $r = $results[$i]
                $on = "$($r.Game.Label) $($r.Game.Build)"
                if ($i -gt 0 -and $r.Result.Holds -eq $results[0].Result.Holds) { continue }
                if ($r.Result.Holds) { Write-Output "    holds    $on`: $($d.Fact) ($($r.Result.Why))"; $held++; continue }
                Write-Output "    FAILS    $on`: $($d.Fact): $($r.Result.Why)"
                Write-Output "             revisit: $($d.IfChanged)"
                $findings.Add("$name`: $($d.Fact) on $on"); $failed++
            }
        }
    }
    Write-Output "  $held hold or were seen in game, $failed fail, $open open for the game to answer."
}

$games = @(
    foreach ($g in @(@{ Key = 'retail'; Label = 'retail'; Build = $Build; Data = (Join-Path $DataDir 'quests.jsonl') },
        @{ Key = 'ptr'; Label = 'retail PTR'; Build = $PtrBuild; Data = (Join-Path $DataDir 'quests.jsonl') },
        @{ Key = 'forever'; Label = 'WoW: Forever'; Build = $ForeverBuild; Data = (Join-Path $DataDir 'forever\quests.jsonl') })) {
        if (-not $g.Build) { continue }
        $game = [pscustomobject]@{ Key = $g.Key; Label = $g.Label; Build = $g.Build; InUse = (Get-FlagsInUse $g.Data); Rows = $null; Names = $null
            States = (New-Object System.Collections.Generic.List[object]); Undated = @{} }
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
    Write-Output "$($findings.Count) finding(s): revisit what each names; once the baseline's are read, rerun with -UpdateBaseline."
    exit 1
}
Write-Output "No finding: the calendar tables say what the baseline and the decisions file expect."
