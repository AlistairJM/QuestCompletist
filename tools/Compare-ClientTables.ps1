<#
Reports what changed in the game client's tables between builds, so that a sweep notices a schema
change in a table the tools read (a column added, renamed or gone) and sees new tables worth a
look. Blizzard can change tables at a patch, an expansion, or when a game goes from beta to live.

For each build given, it takes the list of every table wago.tools has for that build, saves it as
tools\client_tables-<build>.txt, and compares it with the newest earlier list saved for the same
game: tables added and removed, with the quest-related ones picked out (names with Quest, POI,
UiMap, Area, Journal, Campaign, Holiday, ContentTuning, Waypoint). Then, for every table the tools
read for that game (the client tables cached in tools\ as <Table>.csv or <Table>-<build>.csv; the
client's tables start with a capital, ours don't), it downloads the build's CSV and compares its
column names with the cached copy's. A column change exits with 1: check the tool that reads the
table, and the plan docs, before the sweep goes on. A new table is a prompt to see whether the addon
could use it, not a failure.

It also checks the holidays. qcHolidays in qcCore.lua ties each holiday value in the quest data to
the IDs of the client's Holidays table that its calendar event can carry, and Blizzard adds an ID
now and then (Hallow's End gained 1405). For each holiday there, the Holidays rows of that name
(through HolidayNames) in every build given are compared with the IDs qcHolidays lists: an ID the
client has and qcHolidays lacks is a finding, and exits with 1 as a column change does; add it to
qcHolidays. A holiday with no row of its name in any build checked is only reported: the Scourge
Invasion and the Ahn'Qiraj War Effort are never on the calendar. The rows' CalendarFilterType says
which filter of Blizzard's calendar window holds the event (0 weekly holidays, 1 Darkmoon Faire,
2 battlegrounds, anything else Holidays); it is compared with the filter that qcHolidays gives the
holiday ("HOLIDAYS" unless it has filter=), since the addon shows a holiday's quests when its filter
is unticked. A mismatch is a finding too, and a holiday under the battlegrounds filter needs one
added to qcCalendarFilters.

  .\Compare-ClientTables.ps1 -Build 12.1.0.69933 -ForeverBuild 1.60.1.70245
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = "",
    [string]$ForeverBuild = "",
    [string]$DownloadDir = (Join-Path $env:TEMP 'client_tables')
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $Build -and -not $ForeverBuild) { throw "Give -Build (retail) and/or -ForeverBuild." }
$questLike = 'Quest|POI|UiMap|UIMap|Area|Journal|Campaign|Holiday|ContentTuning|Waypoint|Storyline|Expansion'

function Get-TableList([string]$build) {
    $page = (Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2?build=$build").Content
    $names = [regex]::Matches($page, '&quot;\d+&quot;:&quot;([A-Za-z0-9_]+)&quot;') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    if ($names.Count -lt 100) { throw "Only $($names.Count) table names found for build ${build}: has wago.tools changed its page?" }
    return @($names)
}

function Compare-Build([string]$build, [string]$game) {
    $major = ($build -split '\.')[0]
    Write-Output "== $game build $build"
    $tables = Get-TableList $build
    $listFile = Join-Path $ToolsDir "client_tables-$build.txt"
    [IO.File]::WriteAllLines($listFile, $tables)
    $earlier = Get-ChildItem (Join-Path $ToolsDir 'client_tables-*.txt') |
        Where-Object { $_.BaseName -match "^client_tables-$major\." -and $_.BaseName -ne "client_tables-$build" } |
        Sort-Object { [version]($_.BaseName -replace '^client_tables-') } | Select-Object -Last 1
    if ($earlier) {
        $old = @(Get-Content $earlier.FullName)
        $added = @($tables | Where-Object { $old -notcontains $_ })
        $removed = @($old | Where-Object { $tables -notcontains $_ })
        Write-Output "$($tables.Count) tables; against $($earlier.Name): $($added.Count) added, $($removed.Count) removed."
        foreach ($t in $added) { Write-Output ("  added:   $t" + $(if ($t -match $questLike) { "  <- quest-related, worth a look" } else { "" })) }
        foreach ($t in $removed) { Write-Output ("  removed: $t" + $(if ($t -match $questLike) { "  <- quest-related" } else { "" })) }
    } else {
        Write-Output "$($tables.Count) tables; no earlier list for this game to compare with (saved as $($listFile | Split-Path -Leaf))."
    }

    $cached = @{}
    foreach ($f in Get-ChildItem (Join-Path $ToolsDir '*.csv')) {
        if ($f.BaseName -cnotmatch '^(?<t>[A-Z][A-Za-z0-9_]*?)(?:-(?<b>[\d.]+))?(?:\.[a-z]{2}[A-Z]{2})?$') { continue }
        $t = $Matches.t; $b = $Matches.b
        $forThisGame = if ($b) { ($b -split '\.')[0] -eq $major } else { $major -ne '1' }
        if (-not $forThisGame) { continue }
        if (-not $cached.ContainsKey($t) -or ($b -and -not $cached[$t].Build) -or ($b -and $cached[$t].Build -and [version]$b -gt [version]$cached[$t].Build)) {
            $cached[$t] = @{ File = $f; Build = $b }
        }
    }
    $changed = 0
    $dir = Join-Path $DownloadDir $build
    New-Item -ItemType Directory -Force $dir | Out-Null
    foreach ($t in ($cached.Keys | Sort-Object)) {
        if ($tables -notcontains $t) { Write-Output "  $t`: not in this build's table list"; $changed++; continue }
        $path = Join-Path $dir "$t.csv"
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$t/csv?build=$build" -OutFile $path
        Start-Sleep -Milliseconds 500
        $new = ((Get-Content $path -TotalCount 1) -replace '^\xEF\xBB\xBF', '').Trim()
        $old = ((Get-Content $cached[$t].File.FullName -TotalCount 1) -replace '^\xEF\xBB\xBF', '').Trim()
        if ($new -eq $old) { continue }
        $changed++
        $newCols = $new -split ','; $oldCols = $old -split ','
        $plus = @($newCols | Where-Object { $oldCols -notcontains $_ }); $minus = @($oldCols | Where-Object { $newCols -notcontains $_ })
        Write-Output "  $t`: columns changed against $($cached[$t].File.Name): added $(if ($plus) { $plus -join ', ' } else { 'none' }); gone $(if ($minus) { $minus -join ', ' } else { 'none' })"
    }
    Write-Output "$($cached.Count) tables the tools read checked: $changed changed."
    $script:changedTotal += $changed

    $names = @{}
    foreach ($row in Import-Csv (Get-BuildTable $build 'HolidayNames' $dir)) { $names[$row.ID] = $row.Name_lang }
    $byName = @{}
    $filterTypes = @{}
    foreach ($row in Import-Csv (Get-BuildTable $build 'Holidays' $dir)) {
        $filterTypes[[int]$row.ID] = [int]$row.CalendarFilterType
        $name = $names[$row.HolidayNameID]
        if (-not $name) { continue }
        if (-not $byName.ContainsKey($name)) { $byName[$name] = New-Object System.Collections.Generic.List[int] }
        $byName[$name].Add([int]$row.ID)
    }
    $script:holidaysByGame[$game] = $byName
    $script:filterTypesByGame[$game] = $filterTypes
}

# The build's copy of a table, downloaded once per run; the first run also caches it in tools\ as
# <Table>-<build>.csv, so later runs compare its columns like any other table the tools read.
function Get-BuildTable([string]$build, [string]$table, [string]$dir) {
    $path = Join-Path $dir "$table.csv"
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$build" -OutFile $path
        Start-Sleep -Milliseconds 500
    }
    $cache = Join-Path $ToolsDir "$table-$build.csv"
    if (-not (Test-Path $cache)) { Copy-Item $path $cache }
    return $path
}

function Compare-Holidays {
    $core = [IO.File]::ReadAllText((Join-Path $AddonDir 'qcCore.lua'))
    $block = [regex]::Match($core, '(?s)local qcHolidays = \{(.*?)\r?\n\}').Groups[1].Value
    $entries = [regex]::Matches($block, '\{flag=(\d+), name="((?:[^"\\]|\\.)*)", eventIDs=\{([\d, ]*)\}(?:, filter="(\w+)")?\}')
    if ($entries.Count -eq 0) { throw "qcHolidays wasn't found in $AddonDir\qcCore.lua" }
    $games = @($script:holidaysByGame.Keys | Sort-Object)
    Write-Output "== qcHolidays against the calendar tables of $($games -join ' and ')"
    $filterOfType = @{ 0 = 'WEEKLY'; 1 = 'DARKMOON'; 2 = 'BATTLEGROUND' }
    $matched = 0; $absent = @()
    foreach ($e in $entries) {
        $name = $e.Groups[2].Value
        $ours = @($e.Groups[3].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { [int]$_ })
        $filter = if ($e.Groups[4].Success) { $e.Groups[4].Value } else { 'HOLIDAYS' }
        foreach ($game in $games) {
            foreach ($id in $ours) {
                if (-not $script:filterTypesByGame[$game].ContainsKey($id)) { continue }
                $type = $script:filterTypesByGame[$game][$id]
                $want = if ($filterOfType.ContainsKey($type)) { $filterOfType[$type] } else { 'HOLIDAYS' }
                if ($want -ne $filter) {
                    Write-Output "  ${name}: $game puts ID $id under the calendar's $want filter (CalendarFilterType $type), and qcHolidays has $filter"
                    $script:holidayFindings++
                }
            }
        }
        $client = @{}
        foreach ($game in $games) {
            $ids = $script:holidaysByGame[$game][$name]
            if (-not $ids) { continue }
            foreach ($id in $ids) { if (-not $client.ContainsKey($id)) { $client[$id] = @() }; $client[$id] += $game }
        }
        if ($client.Count -eq 0) { $absent += $name; continue }
        $new = @($client.Keys | Where-Object { $ours -notcontains $_ } | Sort-Object)
        $gone = @($ours | Where-Object { -not $client.ContainsKey($_) })
        if ($new.Count -eq 0 -and $gone.Count -eq 0) { $matched++; continue }
        foreach ($id in $new) { Write-Output "  ${name}: the client has ID $id ($($client[$id] -join ', ')) that qcHolidays lacks"; $script:holidayFindings++ }
        if ($gone.Count -gt 0) {
            if ($games.Count -ge 2) { $script:holidayFindings++ }
            Write-Output ("  ${name}: qcHolidays has " + ($gone -join ', ') + ", which " + $(if ($games.Count -ge 2) { 'neither game has' } else { "$($games[0]) doesn't have (the other game may)" }))
        }
    }
    Write-Output "$($entries.Count) holidays: $matched match the client's IDs; not on any calendar checked: $(if ($absent) { $absent -join ', ' } else { 'none' })."
}

$script:changedTotal = 0
$script:holidayFindings = 0
$script:holidaysByGame = @{}
$script:filterTypesByGame = @{}
if ($Build) { Compare-Build $Build 'retail' }
if ($ForeverBuild) { Compare-Build $ForeverBuild 'WoW: Forever' }
Compare-Holidays
if ($script:changedTotal -gt 0) { Write-Output "Columns changed in $script:changedTotal table(s): check the tools that read them before the sweep goes on." }
if ($script:holidayFindings -gt 0) { Write-Output "$script:holidayFindings holiday finding(s): bring qcHolidays up to date before the sweep goes on." }
if ($script:changedTotal + $script:holidayFindings -gt 0) { exit 1 }
Write-Output "No column changes in the tables the tools read, and qcHolidays matches the calendar tables."
