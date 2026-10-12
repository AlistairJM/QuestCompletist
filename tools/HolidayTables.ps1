# Dot-sourced by Compare-ClientTables.ps1 (step 2b) and Review-Calendar.ps1: qcHolidays as qcCore.lua has it,
# and the client's Holidays table read for its dates.

# Two entries are compared with the rows whose names match a pattern instead of the rows of their own name.
# WoW's Anniversary is a new row every year, named with the year's ordinal; the rows named plain "WoW's
# Anniversary" are left out, since the calendar didn't serve them in game on 11 October 2026. The Skyriding
# Cups are a row per cup, each named "<Region> Cup".
$HolidayRowPatterns = @{
    "WoW's Anniversary" = @{ Pattern = "^WoW's \d+(?:st|nd|rd|th) Anniversary$"; Row = "a new year's row" }
    'Skyriding Cups' = @{ Pattern = "^(?:[\w'-]+ )+Cup$"; Row = "a row named like a cup (check that it is one)" }
}

function Read-QcHolidays([string]$addonDir) {
    $core = [IO.File]::ReadAllText((Join-Path $addonDir 'qcCore.lua'))
    $block = [regex]::Match($core, '(?s)local qcHolidays = \{(.*?)\r?\n\}').Groups[1].Value
    $entries = @(foreach ($e in [regex]::Matches($block, '\{flag=(\d+), name="((?:[^"\\]|\\.)*)", eventIDs=\{([\d, ]*)\}(?:, filter="(\w+)")?\}')) {
        [pscustomobject]@{
            Flag = [int]$e.Groups[1].Value
            Name = $e.Groups[2].Value
            IDs = @($e.Groups[3].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { [int]$_ })
            Filter = if ($e.Groups[4].Success) { $e.Groups[4].Value } else { 'HOLIDAYS' }
        }
    })
    if ($entries.Count -eq 0) { throw "qcHolidays wasn't found in $addonDir\qcCore.lua" }
    return $entries
}

# A packed date's fields, each $null where the date leaves it open: the minute (bits 0 to 5, 63 for any), the
# hour (6 to 10, 31), the weekday (11 to 13, Sunday 0, 7 for any), the day and the month counted from 0 (14 to 19,
# 63; 20 to 23, 15) and the year from 2000 (24 to 28, 31 for every year).
function ConvertFrom-HolidayDate([long]$packed) {
    $minute = $packed -band 63; $hour = ($packed -shr 6) -band 31; $weekday = ($packed -shr 11) -band 7
    $day = ($packed -shr 14) -band 63; $month = ($packed -shr 20) -band 15; $year = ($packed -shr 24) -band 31
    return [pscustomobject]@{
        Minute = $(if ($minute -eq 63) { $null } else { [int]$minute })
        Hour = $(if ($hour -eq 31) { $null } else { [int]$hour })
        Weekday = $(if ($weekday -eq 7) { $null } else { [int]$weekday })
        Day = $(if ($day -eq 63) { $null } else { [int]$day + 1 })
        Month = $(if ($month -eq 15) { $null } else { [int]$month + 1 })
        Year = $(if ($year -eq 31) { $null } else { 2000 + [int]$year })
    }
}

function Get-HolidayDates($row) {
    return @(for ($i = 0; $i -lt 26; $i++) {
        $packed = [long]$row."Date_$i"
        if ($packed -gt 0) { ConvertFrom-HolidayDate $packed }
    })
}

function Get-HolidayStages($row) {
    $stages = @(for ($i = 0; $i -lt 10; $i++) {
        $hours = [int]$row."Duration_$i"
        if ($hours -le 0) { break }
        $hours
    })
    if ($stages.Count -eq 0) { return @(0) }
    return $stages
}

# The last date of a Holidays row, with its end after the row's durations (hours). A row that loops or has an
# every-year date never ends, and a row with no date has none. A month, day, hour or minute set to its "any"
# value counts as the latest it can mean.
function Get-HolidayLastDate($row) {
    $dates = @(Get-HolidayDates $row)
    if ($dates.Count -eq 0) { return $null }
    $never = [pscustomobject]@{ Start = $null; End = [datetime]::MaxValue }
    if ([int]$row.Looping -ne 0) { return $never }
    $hours = 0
    for ($i = 0; $i -lt 10; $i++) { $hours += [int]$row."Duration_$i" }
    $last = $null
    foreach ($d in $dates) {
        if ($null -eq $d.Year) { return $never }
        $month = if ($null -eq $d.Month) { 12 } else { [Math]::Min(12, $d.Month) }
        $day = [Math]::Min([DateTime]::DaysInMonth($d.Year, $month), $(if ($null -eq $d.Day) { 31 } else { $d.Day }))
        $hour = if ($null -eq $d.Hour) { 23 } else { [Math]::Min(23, $d.Hour) }
        $minute = if ($null -eq $d.Minute) { 59 } else { [Math]::Min(59, $d.Minute) }
        $start = New-Object DateTime $d.Year, $month, $day, $hour, $minute, 0
        if (-not $last -or $start -gt $last.Start) { $last = [pscustomobject]@{ Start = $start; End = $start.AddHours($hours) } }
    }
    return $last
}

# The runs of a row that touch $from to $to, soonest first, each the part the calendar shows: its stages from
# the first whose CalendarFlags is set to the last (the Darkmoon Faire's two days before it opens, and
# Brewfest's week before, are stages with none), or all of them when no stage has any. A date gives one run, or
# one a year, month, week or day for the fields it leaves open; a looping row repeats its first date every sum
# of its durations.
function Get-HolidayRuns($row, [datetime]$from, [datetime]$to) {
    $stages = @(Get-HolidayStages $row)
    $flagged = @(for ($i = 0; $i -lt $stages.Count; $i++) { if ([int]$row."CalendarFlags_$i" -ne 0) { $i } })
    $first = if ($flagged.Count) { $flagged[0] } else { 0 }
    $lastStage = if ($flagged.Count) { $flagged[-1] } else { $stages.Count - 1 }
    $offset = 0; for ($i = 0; $i -lt $first; $i++) { $offset += $stages[$i] }
    $length = 0; for ($i = $first; $i -le $lastStage; $i++) { $length += $stages[$i] }
    $cycle = ($stages | Measure-Object -Sum).Sum
    $dates = @(Get-HolidayDates $row)
    $starts = New-Object System.Collections.Generic.List[datetime]
    $full = { param($d) $null -ne $d.Year -and $null -ne $d.Month -and $null -ne $d.Day }
    $at = { param($d, [datetime]$day) $day.AddHours($(if ($null -eq $d.Hour) { 0 } else { [Math]::Min(23, $d.Hour) })).AddMinutes($(if ($null -eq $d.Minute) { 0 } else { [Math]::Min(59, $d.Minute) })) }
    if ([int]$row.Looping -ne 0 -and $dates.Count -gt 0 -and $cycle -gt 0 -and (& $full $dates[0]) -and $dates[0].Day -le [DateTime]::DaysInMonth($dates[0].Year, [Math]::Min(12, $dates[0].Month))) {
        $anchor = & $at $dates[0] (New-Object DateTime $dates[0].Year, ([Math]::Min(12, $dates[0].Month)), $dates[0].Day)
        $k = [Math]::Max(0, [Math]::Floor((($from - $anchor).TotalHours - $offset - $length) / $cycle))
        while ($true) {
            $start = $anchor.AddHours($k * $cycle)
            if ($start.AddHours($offset) -gt $to) { break }
            $starts.Add($start)
            $k++
        }
    } else {
        $earliest = $from.AddHours(-$cycle).Date.AddDays(-1)
        foreach ($d in $dates) {
            if ((& $full $d) -and $d.Month -le 12 -and $d.Day -le [DateTime]::DaysInMonth($d.Year, $d.Month)) {
                $starts.Add((& $at $d (New-Object DateTime $d.Year, $d.Month, $d.Day)))
                continue
            }
            for ($day = $earliest; $day -le $to.Date; $day = $day.AddDays(1)) {
                if ($null -ne $d.Year -and $day.Year -ne $d.Year) { continue }
                if ($null -ne $d.Month -and $day.Month -ne $d.Month) { continue }
                if ($null -ne $d.Day -and $day.Day -ne $d.Day) { continue }
                if ($null -ne $d.Weekday -and [int]$day.DayOfWeek -ne $d.Weekday) { continue }
                $starts.Add((& $at $d $day))
            }
        }
    }
    $runs = foreach ($start in ($starts | Sort-Object -Unique)) {
        $shownStart = $start.AddHours($offset)
        $shownEnd = $shownStart.AddHours($length)
        if ($shownEnd -ge $from -and $shownStart -le $to) { [pscustomobject]@{ Start = $shownStart; End = $shownEnd } }
    }
    return @($runs)
}

# The calendar shows a row that has a name and whose Flags hold 1 and not 2. Read from the tables, not
# from Blizzard: of the rows dated for region 4 in the 12 months /qc holidays read on retail on 11 October 2026, it
# listed the 58 that fit and none of the rest (1587, the region's plain "WoW's Anniversary", has Flags 3; 1706, a
# Timewalking row, 15; 653, with 13, has no name). Forever's 1879, with 3 and no name, wasn't listed either.
function Test-HolidayShown($row, [string]$name) {
    $flags = [int]$row.Flags
    return [bool]$name -and ($flags -band 1) -ne 0 -and ($flags -band 2) -eq 0
}

# Region is a mask: 0 is every region, and a row is for a realm whose region's bit it has (Day of the Dead,
# 409, is for 1999, which holds 4, and the calendar served it on the user's realm, of region 4).
function Test-HolidayRegion($row, [int]$region) {
    $mask = [int]$row.Region
    return $mask -eq 0 -or ($mask -band $region) -ne 0
}
