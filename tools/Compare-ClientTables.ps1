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

  .\Compare-ClientTables.ps1 -Build 12.1.0.69933 -ForeverBuild 1.60.1.70245
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
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
}

$script:changedTotal = 0
if ($Build) { Compare-Build $Build 'retail' }
if ($ForeverBuild) { Compare-Build $ForeverBuild 'WoW: Forever' }
if ($script:changedTotal -gt 0) { Write-Output "Columns changed in $script:changedTotal table(s): check the tools that read them before the sweep goes on."; exit 1 }
Write-Output "No column changes in the tables the tools read."
