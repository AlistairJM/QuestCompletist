# Dot-sourced by Compare-ClientTables.ps1 (step 2b): qcHolidays as qcCore.lua has it, and the client's
# Holidays table read for its dates.

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
