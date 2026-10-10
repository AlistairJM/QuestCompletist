<#
Step 0 of every sweep and of every probe run (docs\maintenance.md, "Before a sweep"). For each source the
tools read, says what the checkout holds and what is newest, and exits with 1 when anything is behind, so
no result is built on last time's version. Report-only: it changes nothing.

  Installed clients  .build.info against the newest build wago.tools publishes for the same product
                     (retail is `wow`, WoW: Forever `wow_classic_beta`; edit $GameProducts in
                     LatestBuilds.ps1 if Forever's product changes at its launch)
  Probe lists        the build in QuestIDs_<Game>.lua, in the checkout and in each game's AddOns folder,
                     against the installed client
  Probe results      the newest tools\<game>_probe_<revision> folder against the installed client
  Client tables      the tables in tools\ for each product's current version (retail live, retail PTR,
                     Forever beta, Classic Era): none held, or an older build than the newest
  Pinned builds      scripts whose -Build default is older than the newest build of that version
  API docs           api_docs-<branch>-<build>.tsv against Gethe/wow-ui-source's version.txt
  CMaNGOS, TrinityCore  the dump and the TDB held against the newest published
  Blizzard API cache quest_api_cache, whose last write must be later than the newest live build's publication

Exit 1: something is behind. Exit 2: nothing is behind, but a source could not be reached. -NewestFile reads
the newest versions from a JSON file (wago, gethe, cmangos, trinity) instead of the network, for
Test-LatestBuilds.ps1.
#>
param(
    [string]$WowDir = 'C:\Program Files (x86)\World of Warcraft',
    [string]$ToolsDir = $PSScriptRoot,
    [string]$NewestFile = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. "$PSScriptRoot\LatestBuilds.ps1"

function Get-Newest {
    if ($NewestFile) { return Get-Content -LiteralPath $NewestFile -Raw | ConvertFrom-Json }
    $headers = @{ 'User-Agent' = 'QuestCompletist-tools' }
    $newest = [pscustomobject]@{ wago = $null; gethe = [pscustomobject]@{ live = $null; forever = $null }; cmangos = $null; trinity = $null }
    try { $newest.wago = Invoke-RestMethod -Uri 'https://wago.tools/api/builds' -Headers $headers } catch { }
    foreach ($branch in 'live', 'forever') {
        try { $newest.gethe.$branch = (Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/Gethe/wow-ui-source/$branch/version.txt" -Headers $headers).Content.Trim() } catch { }
    }
    try {
        $listing = Invoke-RestMethod -Uri 'https://api.github.com/repos/cmangos/classic-db/contents/Full_DB' -Headers $headers
        $newest.cmangos = @($listing | Where-Object { $_.name -like '*.sql.gz' } | ForEach-Object { $_.name })
    } catch { }
    try {
        $releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/TrinityCore/TrinityCore/releases?per_page=30' -Headers $headers
        $tdb = @($releases | Where-Object { $_.tag_name -match '^TDB1\d{3}\.\d+$' })[0]
        if ($tdb) { $newest.trinity = [pscustomobject]@{ tag = $tdb.tag_name; published = $tdb.published_at } }
    } catch { }
    return $newest
}

$rows = New-Object System.Collections.Generic.List[object]
function Add-Row([string]$area, [string]$item, [string]$held, [string]$newest, [string]$state, [string]$note = '') {
    $rows.Add([pscustomobject]@{ Area = $area; Item = $item; Held = $held; Newest = $newest; State = $state; Note = $note })
}
function Get-State([string]$held, [string]$newest) {
    if ([version]$held -lt [version]$newest) { return 'BEHIND' }
    return 'ok'
}

$newest = Get-Newest
$published = $null
if ($newest.wago) { $published = Get-NewestPublished $newest.wago }
$unreachable = 'wago.tools was not reachable'

$installed = @{}
foreach ($game in $GameProducts.Keys) {
    $product = $GameProducts[$game]
    $build = Get-InstalledBuild $game $WowDir
    $installed[$game] = $build
    $latest = $null
    if ($published -and $published.Product.ContainsKey($product)) { $latest = $published.Product[$product].Version }
    if (-not $build) { Add-Row 'Installed clients' "$game ($product)" '' $latest 'none' "no $product in $WowDir\.build.info"; continue }
    if (-not $latest) { Add-Row 'Installed clients' "$game ($product)" $build '' 'unknown' $unreachable; continue }
    $state = Get-State $build $latest
    $note = ''
    if ($state -eq 'BEHIND') { $note = 'update the client before a probe run' }
    elseif ([version]$build -gt [version]$latest) { $note = 'newer than the newest wago.tools lists' }
    Add-Row 'Installed clients' "$game ($product)" $build $latest $state $note
}

$listFiles = @{ retail = 'QuestIDs_Retail.lua'; forever = 'QuestIDs_Forever.lua' }
foreach ($game in $GameProducts.Keys) {
    $target = $installed[$game]
    if (-not $target -and $published -and $published.Product.ContainsKey($GameProducts[$game])) { $target = $published.Product[$GameProducts[$game]].Version }
    $places = @(
        @{ Label = "checkout list ($game)"; Path = "$ToolsDir\ForeverProbe\QCForeverProbe\$($listFiles[$game])" },
        @{ Label = "AddOns copy ($game)"; Path = "$WowDir\$($GameFolders[$game])\Interface\AddOns\QCForeverProbe\$($listFiles[$game])" })
    foreach ($place in $places) {
        $built = Read-ListBuild $place.Path
        if (-not $built) { Add-Row 'Probe lists' $place.Label '' $target 'none' 'no list there'; continue }
        if (-not $target) { Add-Row 'Probe lists' $place.Label $built '' 'unknown' 'no installed client and wago.tools not reachable'; continue }
        $state = Get-State $built $target
        $note = ''
        if ($state -eq 'BEHIND') { $note = "rebuild with Build-ProbeLists.ps1 -Game $game, and copy it into the AddOns folder" }
        elseif ([version]$built -gt [version]$target) { $note = 'the list is for a newer build than the client' }
        Add-Row 'Probe lists' $place.Label $built $target $state $note
    }
}

foreach ($game in $GameProducts.Keys) {
    $folders = @(Get-ChildItem -LiteralPath $ToolsDir -Directory -Filter "${game}_probe_*" | Where-Object { $_.Name -match "^${game}_probe_(\d+)$" })
    $revision = $null
    if ($installed[$game]) { $revision = [int]($installed[$game] -split '\.')[3] }
    if (-not $folders.Count) { Add-Row 'Probe results' "tools\${game}_probe_<revision>" '' "$revision" 'none' 'no results held'; continue }
    $held = ($folders | ForEach-Object { [int]($_.Name -replace '^.*_(\d+)$', '$1') } | Sort-Object -Descending)[0]
    if ($null -eq $revision) { Add-Row 'Probe results' "newest $game results" "$held" '' 'unknown' 'no installed client to compare with'; continue }
    $state = 'ok'
    $note = ''
    if ($held -lt $revision) { $state = 'BEHIND'; $note = 'rerun the probe on the installed build' }
    Add-Row 'Probe results' "newest $game results" "$held" "$revision" $state $note
}

$tables = Get-HeldTables $ToolsDir
$tableProducts = @(
    @{ Label = 'retail live'; Product = 'wow'; Required = $true },
    @{ Label = 'retail PTR'; Product = 'wowxptr'; Required = $false },
    @{ Label = 'Forever beta'; Product = 'wow_classic_beta'; Required = $true },
    @{ Label = 'Classic Era'; Product = 'wow_classic_era'; Required = $false })
foreach ($p in $tableProducts) {
    if (-not $published -or -not $published.Product.ContainsKey($p.Product)) { Add-Row 'Client tables' $p.Label '' '' 'unknown' $unreachable; continue }
    $latest = $published.Product[$p.Product].Version
    $track = Get-BuildTrack $latest
    $onTrack = @($tables | Where-Object { $_.Track -eq $track })
    if (-not $onTrack.Count) {
        $state = 'none'
        if ($p.Required) { $state = 'BEHIND' }
        Add-Row 'Client tables' "$($p.Label), version $track" '' $latest $state 'no table held for this version'
        continue
    }
    $behind = @($onTrack | Where-Object { [version]$_.Build -lt [version]$latest } | Sort-Object Family)
    $top = ($onTrack | Sort-Object { [version]$_.Build } -Descending)[0].Build
    $state = 'ok'
    $note = ''
    if ($behind.Count) {
        $state = 'BEHIND'
        $names = @($behind | Select-Object -First 12 | ForEach-Object { "$($_.Family) $($_.Build -replace '^.*\.', '')" })
        $note = "$($behind.Count) of $($onTrack.Count) older: " + ($names -join ', ')
        if ($behind.Count -gt 12) { $note += ", and $($behind.Count - 12) more" }
    }
    Add-Row 'Client tables' "$($p.Label), version $track" "$($onTrack.Count) tables, newest $top" $latest $state $note
}

if ($published) {
    $pinned = @(Get-ScriptPins $ToolsDir)
    $current = 0
    foreach ($pin in $pinned) {
        $latest = $published.Track[(Get-BuildTrack $pin.Build)]
        if (-not $latest) { continue }
        if ([version]$pin.Build -lt [version]$latest.Version) { Add-Row 'Pinned builds' "$($pin.Script) -$($pin.Parameter)" $pin.Build $latest.Version 'BEHIND' 'pass the newest build, or change the default' }
        else { $current++ }
    }
    if ($current) { Add-Row 'Pinned builds' "$current other script defaults" '' '' 'ok' 'the newest build of their version' }
}

$docs = @{}
foreach ($file in Get-ChildItem -LiteralPath $ToolsDir -Filter 'api_docs-*.tsv' -File) {
    if ($file.Name -match '^api_docs-(live|forever)-(\d+\.\d+\.\d+\.\d+)\.tsv$') {
        if (-not $docs.ContainsKey($Matches[1]) -or [version]$Matches[2] -gt [version]$docs[$Matches[1]]) { $docs[$Matches[1]] = $Matches[2] }
    }
}
foreach ($branch in 'live', 'forever') {
    $mirror = $newest.gethe.$branch
    $held = $docs[$branch]
    if (-not $mirror) { Add-Row 'API docs' "Gethe/wow-ui-source $branch" $held '' 'unknown' 'GitHub was not reachable'; continue }
    if (-not $held) { Add-Row 'API docs' "Gethe/wow-ui-source $branch" '' $mirror 'none' 'no list held'; continue }
    $state = Get-State $held $mirror
    $note = ''
    if ($state -eq 'BEHIND') { $note = "run Compare-ApiDocs.ps1 -Branches $branch" }
    Add-Row 'API docs' "Gethe/wow-ui-source $branch" $held $mirror $state $note
}

$heldDump = @(Get-ChildItem -LiteralPath $ToolsDir -Filter 'ClassicDB_*.sql.gz' -File | ForEach-Object { $_.Name } | Sort-Object)
if (-not $newest.cmangos) { Add-Row 'Databases' 'CMaNGOS classic-db dump' ($heldDump -join ', ') '' 'unknown' 'GitHub was not reachable' }
else {
    $latestDump = @(@($newest.cmangos) | Sort-Object)[-1]
    $state = 'BEHIND'
    if ($heldDump -contains $latestDump) { $state = 'ok' }
    $note = ''
    if ($state -eq 'BEHIND') { $note = 'download the newest dump (Before a sweep, step 4)' }
    Add-Row 'Databases' 'CMaNGOS classic-db dump' ($heldDump -join ', ') $latestDump $state $note
}
$heldTdb = $null
foreach ($file in Get-ChildItem -LiteralPath "$ToolsDir\tdb" -Filter 'TDB_full_world_*.sql' -File -ErrorAction SilentlyContinue) {
    if ($file.Name -match '^TDB_full_world_(\d+\.\d+)_') {
        if (-not $heldTdb -or [version]$Matches[1] -gt [version]$heldTdb) { $heldTdb = $Matches[1] }
    }
}
if (-not $newest.trinity) { Add-Row 'Databases' 'TrinityCore TDB' $heldTdb '' 'unknown' 'GitHub was not reachable' }
elseif (-not $heldTdb) { Add-Row 'Databases' 'TrinityCore TDB' '' ($newest.trinity.tag -replace '^TDB', '') 'none' 'no world database in tools\tdb' }
else {
    $latestTdb = $newest.trinity.tag -replace '^TDB', ''
    $state = Get-State $heldTdb $latestTdb
    $note = ''
    if ($state -eq 'BEHIND') { $note = 'download the newest TDB_full (Before a sweep, step 5)' }
    Add-Row 'Databases' 'TrinityCore TDB' $heldTdb $latestTdb $state $note
}

$cache = Get-Item -LiteralPath "$ToolsDir\quest_api_cache" -ErrorAction SilentlyContinue
if (-not $cache) { Add-Row 'Databases' 'Blizzard API cache' '' '' 'none' 'no quest_api_cache' }
else {
    $namespace = ''
    $sample = Get-ChildItem -LiteralPath $cache.FullName -Filter '*.json' -File | Select-Object -First 1
    if ($sample -and ([System.IO.File]::ReadAllText($sample.FullName) -match 'namespace=static-([^&"]+?)-[a-z]+[&"]')) { $namespace = $Matches[1] }
    $written = $cache.LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm')
    if (-not $published -or -not $published.Product.ContainsKey('wow')) { Add-Row 'Databases' 'Blizzard API cache' "$namespace, $written" '' 'unknown' $unreachable }
    else {
        $live = $published.Product['wow']
        $liveWhen = [datetime]::ParseExact($live.Created, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
        $state = 'ok'
        $note = ''
        if ($cache.LastWriteTimeUtc -lt $liveWhen) { $state = 'BEHIND'; $note = 'fetched before the newest live build was published (Before a sweep, step 3)' }
        Add-Row 'Databases' 'Blizzard API cache' "$namespace, written $written" "live $($live.Version) at $($liveWhen.ToString('yyyy-MM-dd HH:mm'))" $state $note
    }
}

foreach ($area in ($rows | ForEach-Object { $_.Area } | Select-Object -Unique)) {
    Write-Output $area
    foreach ($row in ($rows | Where-Object { $_.Area -eq $area })) {
        $line = '  {0,-8} {1,-42} held {2,-28} newest {3}' -f $row.State, $row.Item, $row.Held, $row.Newest
        if ($row.Note) { $line += "  ($($row.Note))" }
        Write-Output $line
    }
}
$behind = @($rows | Where-Object { $_.State -eq 'BEHIND' }).Count
$unknown = @($rows | Where-Object { $_.State -eq 'unknown' }).Count
Write-Output ''
Write-Output "$behind behind, $unknown could not be checked, $(@($rows | Where-Object { $_.State -eq 'ok' }).Count) current."
if ($behind) { exit 1 }
if ($unknown) { exit 2 }
exit 0
