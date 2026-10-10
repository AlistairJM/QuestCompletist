<#
Checks LatestBuilds.ps1 and Get-LatestBuilds.ps1 on a game folder, a tools folder and a "newest versions" file
made in a scratch folder: nothing in the checkout is written, the real game folder is not read and nothing is
downloaded. It checks that a world where everything is the newest passes, that each kind of stale source
(client, probe list, probe results, tables, pinned build, API docs, CMaNGOS, TrinityCore, API cache) is reported
BEHIND and exits 1, that a client newer than wago.tools lists is not, that a product's newest build is the
latest published and not the highest version, and that unreachable sources exit 2.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-LatestBuilds.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
$Report = Join-Path $PSScriptRoot 'Get-LatestBuilds.ps1'
. (Join-Path $PSScriptRoot 'LatestBuilds.ps1')
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Has-Row([string]$text, [string]$state, [string]$item) {
    return $text -match ('(?m)^  ' + $state + '\s+' + $item)
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("latest-builds-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null

function Write-File([string]$path, [string]$text = 'x') {
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $text)
}

function Write-BuildInfo([string]$wow, [hashtable]$products) {
    $lines = @('Branch!STRING:0|Active!DEC:1|Version!STRING:0|Product!STRING:0')
    foreach ($product in $products.Keys) { $lines += "us|1|$($products[$product])|$product" }
    New-Item -ItemType Directory -Path $wow -Force | Out-Null
    [IO.File]::WriteAllLines("$wow\.build.info", [string[]]$lines)
}

function Write-List([string]$path, [string]$build) {
    Write-File $path "-- generated`r`nlocal _, probe = ...`r`nprobe.questBuild = `"$build`"`r`nprobe.questIds = {`r`n1,2,`r`n}`r`n"
}

function New-Newest([string]$path, [hashtable]$overrides = @{}) {
    $newest = [ordered]@{
        wago = [ordered]@{
            wow = @(@{ version = '12.1.0.69933'; created_at = '2026-09-22 14:18:16' }, @{ version = '12.1.0.69875'; created_at = '2026-09-18 19:51:00' })
            wowxptr = @(@{ version = '12.1.5.70077'; created_at = '2026-09-29 21:18:16' })
            wow_classic_beta = @(@{ version = '1.60.1.70338'; created_at = '2026-10-09 20:00:00' }, @{ version = '1.60.1.70291'; created_at = '2026-10-08 20:25:00' }, @{ version = '5.5.0.62071'; created_at = '2025-01-01 00:00:00' })
            wow_classic_era = @(@{ version = '1.15.9.70003'; created_at = '2026-09-29 14:06:00' })
        }
        gethe = [ordered]@{ live = '12.1.0.69933'; forever = '1.60.1.70338' }
        cmangos = @('ClassicDB_1_12_1_z2815.sql.gz')
        trinity = [ordered]@{ tag = 'TDB1210.26091'; published = '2026-09-09T19:11:52Z' }
    }
    foreach ($key in $overrides.Keys) { $newest[$key] = $overrides[$key] }
    [IO.File]::WriteAllText($path, ($newest | ConvertTo-Json -Depth 6))
}

function New-World([string]$name) {
    $root = Join-Path $Scratch $name
    $w = @{ Root = $root; Wow = "$root\wow"; Tools = "$root\tools"; Newest = "$root\newest.json" }
    Write-BuildInfo $w.Wow @{ wow = '12.1.0.69933'; wow_classic_beta = '1.60.1.70338' }
    foreach ($file in 'QuestV2-12.1.0.69933.csv', 'Faction-12.1.0.69933.csv', 'QuestV2-12.1.5.70077.csv', 'QuestV2-1.60.1.70338.csv', 'Faction-1.60.1.70338.csv', 'QuestSort-1.60.1.70338.deDE.csv', 'UiMap-1.15.9.70003.csv') {
        Write-File "$($w.Tools)\$file"
    }
    Write-File "$($w.Tools)\retail_quest_cache_12.1.0.69933.jsonl"
    Write-File "$($w.Tools)\api_docs-live-12.1.0.69933.tsv"
    Write-File "$($w.Tools)\api_docs-forever-1.60.1.70338.tsv"
    Write-File "$($w.Tools)\retail_probe_69933\QCForeverProbe.lua" "QCForeverProbeDB = {`n[`"runs`"] = {{[`"build`"] = `"12.1.0.69933`"}},`n}`n"
    Write-File "$($w.Tools)\forever_probe_70338\QCForeverProbe.lua" "QCForeverProbeDB = {`n[`"runs`"] = {{[`"build`"] = `"1.60.1.70205`"}, {[`"build`"] = `"1.60.1.70338`"}},`n}`n"
    Write-File "$($w.Tools)\ClassicDB_1_12_1_z2815.sql.gz"
    Write-File "$($w.Tools)\ClassicDB_1_12_1_z2900.sql.gz.20261005"
    Write-File "$($w.Tools)\tdb\TDB_full_world_1210.26091_2026_09_09.sql"
    Write-File "$($w.Tools)\quest_api_cache\1.json" '{"_links":{"self":{"href":"https://us.api.blizzard.com/data/wow/quest/1?namespace=static-12.1.0_68914-us"}}}'
    (Get-Item "$($w.Tools)\quest_api_cache").LastWriteTimeUtc = [datetime]'2026-09-30 19:00:00'
    Write-File "$($w.Tools)\Pinned.ps1" "param(`r`n    [string]`$Build = `"12.1.0.69933`",`r`n    [string]`$ForeverBuild = '1.60.1.70338'`r`n)`r`n"
    Write-File "$($w.Tools)\Test-Ignored.ps1" "param(`r`n    [string]`$Build = `"1.60.1.70000`"`r`n)`r`n"
    foreach ($folder in "$($w.Tools)\ForeverProbe\QCForeverProbe", "$($w.Wow)\_retail_\Interface\AddOns\QCForeverProbe", "$($w.Wow)\_classic_beta_\Interface\AddOns\QCForeverProbe") {
        Write-List "$folder\QuestIDs_Retail.lua" '12.1.0.69933'
        Write-List "$folder\QuestIDs_Forever.lua" '1.60.1.70338'
    }
    New-Newest $w.Newest
    return $w
}

function Run-Report([hashtable]$w) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Report, '-WowDir', $w.Wow, '-ToolsDir', $w.Tools, '-NewestFile', $w.Newest)
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = @(& powershell @arguments 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $saved }
    return @{ Text = ($output -join "`n"); Exit = $LASTEXITCODE }
}

try {
    # --- the library -----------------------------------------------------------------------------
    Equal (Get-BuildTrack '1.60.1.70338') '1.60.1' 'L1: a build''s version is its first three numbers'
    Check (Test-BuildNumber '12.1.0.69933') 'L1: a build number'
    Check (-not (Test-BuildNumber '12.1.0')) 'L1: and three numbers are not one'
    $w = New-World 'library'
    $info = Read-BuildInfo "$($w.Wow)\.build.info"
    Equal $info['wow_classic_beta'] '1.60.1.70338' 'L2: .build.info gives each product its version'
    Equal (Get-InstalledBuild 'retail' $w.Wow) '12.1.0.69933' 'L2: retail is the wow product'
    Equal (Get-InstalledBuild 'forever' $w.Wow) '1.60.1.70338' 'L2: Forever is the wow_classic_beta product'
    Equal (Get-InstalledBuild 'forever' "$($w.Root)\nowhere") $null 'L2: a game folder with no .build.info has no installed build'
    Write-BuildInfo $w.Wow @{ wow = '12.1.0.69933' }
    Equal (Get-InstalledBuild 'forever' $w.Wow) $null 'L2: nor does a game that is not in it'
    $pins = @(Get-ScriptPins $w.Tools)
    Equal $pins.Count 2 'L3: a script''s pinned builds are found, and a test script''s are not'
    Equal (($pins | ForEach-Object { $_.Parameter } | Sort-Object) -join ',') 'Build,ForeverBuild' 'L3: by parameter name'
    $tables = @(Get-HeldTables $w.Tools)
    Equal ($tables | Where-Object { $_.Family -eq 'QuestSort' } | ForEach-Object { $_.Build }) '1.60.1.70338' 'L4: a table with a locale in its name is found'
    Check (-not ($tables | Where-Object { $_.Family -like 'retail_quest_cache*' -or $_.Family -like 'api_docs*' })) 'L4: and a cache or an API list is not a table'
    $published = Get-NewestPublished (Get-Content "$($w.Newest)" -Raw | ConvertFrom-Json).wago
    Equal $published.Product['wow_classic_beta'].Version '1.60.1.70338' 'L5: a product''s newest build is the latest published, not the highest version (5.5.0.62071 is older)'
    Equal $published.Track['1.60.1'].Version '1.60.1.70338' 'L5: and a version''s newest build is the highest across the products that carry it'

    # --- the build of the newest probe results ---------------------------------------------------
    $w = New-World 'probebuild'
    Equal (Get-ProbeBuild 'forever' $w.Tools) '1.60.1.70338' 'P1: the build of the newest Forever results, not an older one in the same file'
    Equal (Get-ProbeBuild 'retail' $w.Tools) '12.1.0.69933' 'P1: and of retail'
    Write-File "$($w.Tools)\forever_probe_70205\QCForeverProbe.lua" "QCForeverProbeDB = {[`"runs`"] = {{[`"build`"] = `"1.60.1.70205`"}}}`n"
    Equal (Get-ProbeBuild 'forever' $w.Tools) '1.60.1.70338' 'P2: an older folder doesn''t win'
    Write-File "$($w.Tools)\forever_probe_70400\QCForeverProbe.lua" "QCForeverProbeDB = {[`"runs`"] = {{[`"build`"] = `"1.60.1.70400`"}}}`n"
    Equal (Get-ProbeBuild 'forever' $w.Tools) '1.60.1.70400' 'P2: a newer one does, by its number and not its date'
    Write-File "$($w.Tools)\forever_probe_70500\QCForeverProbe.lua" "nothing here`n"
    Equal (Get-ProbeBuild 'forever' $w.Tools) $null 'P3: a newest folder whose file names no build of its own gives none'
    Remove-Item "$($w.Tools)\forever_probe_70500" -Recurse
    Remove-Item "$($w.Tools)\forever_probe_70400\QCForeverProbe.lua"
    Equal (Get-ProbeBuild 'forever' $w.Tools) $null 'P3: and so does one with no file'
    Equal (Get-ProbeBuild 'forever' "$($w.Root)\nowhere") $null 'P3: and a tools folder with no results'
    Equal (Resolve-ProbeBuild '1.60.1.70001' 'forever' $w.Tools 'Build') '1.60.1.70001' 'P4: a build that is given is used as it is'
    Remove-Item "$($w.Tools)\forever_probe_70400" -Recurse
    Equal (Resolve-ProbeBuild '' 'forever' $w.Tools 'Build') '1.60.1.70338' 'P4: left out, it is the results'' build'
    $threw = $false; try { Resolve-ProbeBuild '' 'forever' "$($w.Root)\nowhere" 'Build' | Out-Null } catch { $threw = $_.Exception.Message -match 'no -Build and no forever probe results' }
    Check $threw 'P4: and with no results it is refused, naming the parameter'

    # --- everything is the newest ----------------------------------------------------------------
    $w = New-World 'current'
    $r = Run-Report $w
    Equal $r.Exit 0 "R1: when every source is the newest the report exits 0 ($($r.Text))"
    Check ($r.Text -match '(?m)^0 behind, 0 could not be checked') 'R1: and counts none behind'
    Check (Has-Row $r.Text 'ok' 'forever \(wow_classic_beta\)\s+held 1\.60\.1\.70338') 'R1: the Forever client is current'
    Check (Has-Row $r.Text 'ok' 'AddOns copy \(forever\)') 'R1: and so is the list in the AddOns folder'
    Check (Has-Row $r.Text 'ok' 'Forever beta, version 1\.60\.1') 'R1: and its tables'
    Check (Has-Row $r.Text 'ok' '2 other script defaults') 'R1: and the pinned builds'

    # --- each source stale -----------------------------------------------------------------------
    $w = New-World 'stale'
    Write-List "$($w.Wow)\_classic_beta_\Interface\AddOns\QCForeverProbe\QuestIDs_Forever.lua" '1.60.1.70291'
    Remove-Item "$($w.Tools)\forever_probe_70338" -Recurse
    Write-File "$($w.Tools)\forever_probe_70291\QCForeverProbe.lua"
    Remove-Item "$($w.Tools)\QuestV2-1.60.1.70338.csv", "$($w.Tools)\Faction-1.60.1.70338.csv", "$($w.Tools)\QuestSort-1.60.1.70338.deDE.csv"
    Write-File "$($w.Tools)\QuestV2-1.60.1.70291.csv"
    Write-File "$($w.Tools)\Faction-1.60.1.70205.csv"
    Write-File "$($w.Tools)\Pinned.ps1" "param(`r`n    [string]`$Build = `"12.1.0.69933`",`r`n    [string]`$ForeverBuild = '1.60.1.70205'`r`n)`r`n"
    Remove-Item "$($w.Tools)\api_docs-forever-1.60.1.70338.tsv"
    Write-File "$($w.Tools)\api_docs-forever-1.60.1.70291.tsv"
    (Get-Item "$($w.Tools)\quest_api_cache").LastWriteTimeUtc = [datetime]'2026-09-01 10:00:00'
    New-Newest $w.Newest @{
        cmangos = @('ClassicDB_1_12_1_z2815.sql.gz', 'ClassicDB_1_12_1_z2816.sql.gz')
        trinity = [ordered]@{ tag = 'TDB1210.26101'; published = '2026-10-09T00:00:00Z' }
    }
    $r = Run-Report $w
    Equal $r.Exit 1 'R2: a stale source makes the report exit 1'
    Check (Has-Row $r.Text 'ok' 'checkout list \(forever\)') 'R2: the checkout''s list is still current'
    Check (Has-Row $r.Text 'BEHIND' 'AddOns copy \(forever\)\s+held 1\.60\.1\.70291\s+newest 1\.60\.1\.70338') 'R2: a list built for the build before is behind'
    Check (Has-Row $r.Text 'BEHIND' 'newest forever results\s+held 70291\s+newest 70338') 'R2: so are the probe results'
    Check ($r.Text -match '(?m)^  BEHIND\s+Forever beta, version 1\.60\.1\s+held 2 tables, newest 1\.60\.1\.70291.*2 of 2 older: Faction 70205, QuestV2 70291') 'R2: and the tables, naming them'
    Check (Has-Row $r.Text 'BEHIND' 'Pinned\.ps1 -ForeverBuild\s+held 1\.60\.1\.70205\s+newest 1\.60\.1\.70338') 'R2: and a pinned default'
    Check (-not ($r.Text -match 'Pinned\.ps1 -Build')) 'R2: but not a pin that is the newest'
    Check (-not ($r.Text -match 'Test-Ignored')) 'R2: nor a test script''s'
    Check (Has-Row $r.Text 'BEHIND' 'Gethe/wow-ui-source forever\s+held 1\.60\.1\.70291') 'R2: and the API docs'
    Check (Has-Row $r.Text 'ok' 'Gethe/wow-ui-source live') 'R2: of the game that is current, not'
    Check (Has-Row $r.Text 'BEHIND' 'CMaNGOS classic-db dump\s+held ClassicDB_1_12_1_z2815\.sql\.gz\s+newest ClassicDB_1_12_1_z2816\.sql\.gz') 'R2: and the CMaNGOS dump (a renamed one does not count)'
    Check (Has-Row $r.Text 'BEHIND' 'TrinityCore TDB\s+held 1210\.26091\s+newest 1210\.26101') 'R2: and TrinityCore'
    Check (Has-Row $r.Text 'BEHIND' 'Blizzard API cache') 'R2: and an API cache fetched before the newest live build was published'
    Check ($r.Text -match 'held 12\.1\.0_68914, written 2026-09-01') 'R2: with its namespace'
    Check (Has-Row $r.Text 'ok' 'retail \(wow\)') 'R2: while the retail client is current'

    # --- the client is newer than the list, no tables for a version ------------------------------
    $w = New-World 'ahead'
    New-Newest $w.Newest @{ wago = [ordered]@{
        wow = @(@{ version = '12.1.0.69933'; created_at = '2026-09-22 14:18:16' })
        wowxptr = @(@{ version = '12.1.5.70077'; created_at = '2026-09-29 21:18:16' })
        wow_classic_beta = @(@{ version = '1.60.1.70291'; created_at = '2026-10-08 20:25:00' })
        wow_classic_era = @(@{ version = '1.15.9.70003'; created_at = '2026-09-29 14:06:00' }) } }
    $r = Run-Report $w
    Check ($r.Text -match '(?m)^  ok\s+forever \(wow_classic_beta\).*newer than the newest wago\.tools lists') 'R3: a client newer than wago.tools lists is not behind, and says why'
    Remove-Item "$($w.Tools)\QuestV2-12.1.0.69933.csv", "$($w.Tools)\Faction-12.1.0.69933.csv", "$($w.Tools)\QuestV2-12.1.5.70077.csv"
    $r = Run-Report $w
    Check (Has-Row $r.Text 'BEHIND' 'retail live, version 12\.1\.0.*no table held for this version') 'R3: no table at all for live retail''s version is behind'
    Check (Has-Row $r.Text 'none' 'retail PTR, version 12\.1\.5.*no table held for this version') 'R3: but none for the PTR is only noted'
    Equal $r.Exit 1 'R3: and the report still exits 1 for the one that is behind'

    # --- not reachable, not installed ------------------------------------------------------------
    $w = New-World 'offline'
    New-Newest $w.Newest @{ wago = $null }
    $r = Run-Report $w
    Equal $r.Exit 2 "R4: with wago.tools unreachable and nothing else behind the report exits 2 ($($r.Text))"
    Check (Has-Row $r.Text 'unknown' 'retail \(wow\)\s+held 12\.1\.0\.69933.*wago\.tools was not reachable') 'R4: and says what it could not check'
    $w = New-World 'uninstalled'
    Remove-Item "$($w.Wow)\.build.info"
    $r = Run-Report $w
    Check (Has-Row $r.Text 'none' 'retail \(wow\)') 'R5: a game that is not installed is none, not behind'
    Check (Has-Row $r.Text 'ok' 'checkout list \(retail\)\s+held 12\.1\.0\.69933\s+newest 12\.1\.0\.69933') 'R5: and the checkout''s list is compared with the newest published instead'
}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
