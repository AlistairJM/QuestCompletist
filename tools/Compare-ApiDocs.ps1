<#
Reports what changed in the game's Lua API between builds, so that a sweep notices a function the
addon calls going missing or changing shape, and sees new functions and events worth a look. It
reads Blizzard's generated API documentation from the UI source mirror Gethe/wow-ui-source, one
branch per game (live for retail, forever for WoW: Forever), as the API review did
(docs\plans\game-api-review.md, recommendation 11). The documentation is partial: the old global
functions (GetQuestID, GetAvailableQuestInfo and the rest) aren't in it, so only the C_ functions
and the documented globals can be checked.

For each branch it downloads the branch's archive, takes the build from its version.txt, keeps the
documentation files in tools\api_docs\<branch>-<build>\, and has Read-ApiDocs.lua turn them into
tools\api_docs-<branch>-<build>.tsv. It then compares that with the newest earlier list saved for
the same branch: functions and events added and removed, with the quest-related namespaces picked
out, and for every function the addon calls (the C_ calls in QuestCompletist\*.lua and
QuestCompletist\Forever\*.lua, plus the documented globals it uses) whether it is still there with
the same arguments and returns. A function the addon calls that has gone or changed since the
earlier list exits with 1: check the code before the sweep goes on. New functions are a prompt to
look, not a failure.

A function the addon calls that one game documents and the other doesn't (C_SkillInfo on retail)
is listed at the end: the code guards each, with a fallback where it has one (the skill check
reads the character's profession list without C_SkillInfo), and what is still that game's alone is
in docs\plans\game-parity.md. When such a function turns up in a game's documentation that
lacked it in the earlier list, that exits with 1 too: the game has gained it, so check that the
code reads it as its fallback did, and share any feature that was gated on it.

  .\Compare-ApiDocs.ps1
  .\Compare-ApiDocs.ps1 -Branches live
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string[]]$Branches = @('live', 'forever'),
    [string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe',
    [string]$DownloadDir = (Join-Path $env:TEMP 'api_docs'),
    [string[]]$Globals = @('UnitName', 'UnitLevel', 'UnitRace', 'UnitClass', 'UnitFactionGroup', 'UnitQuestTrivialLevelRange', 'IsInInstance', 'GetBuildInfo', 'GetLocale', 'issecretvalue')
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$questLike = 'Quest|Map|Poi|POI|Gossip|Tooltip|Creature|Calendar|Reputation|MajorFaction|Campaign|SuperTrack|Minimap|Vignette|EventScheduler|GameRules|SkillInfo|Covenant|Journal|PlayerInfo|^Unit$|Navigation|Holiday|TaskQuest|Scenario|AdventureMap'
if (-not (Test-Path $LuaExe)) { throw "Lua 5.1 wasn't found at $LuaExe (docs\maintenance.md, one-time setup)." }

# The functions the addon calls: C_Namespace.Function in its Lua, and the documented globals given.
function Get-AddonCalls {
    $calls = @{}
    foreach ($file in @(Get-ChildItem (Join-Path $AddonDir '*.lua')) + @(Get-ChildItem (Join-Path $AddonDir 'Forever\*.lua') -ErrorAction SilentlyContinue)) {
        $text = [IO.File]::ReadAllText($file.FullName)
        foreach ($m in [regex]::Matches($text, '\bC_[A-Za-z]+\.[A-Za-z]+')) { $calls[$m.Value] = $true }
    }
    foreach ($g in $Globals) { $calls[$g] = $true }
    return @($calls.Keys | Sort-Object)
}

# Downloads the branch's archive and keeps its documentation folder and build.
function Get-BranchDocs([string]$branch) {
    New-Item -ItemType Directory -Force $DownloadDir | Out-Null
    $zipPath = Join-Path $DownloadDir "$branch.zip"
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/Gethe/wow-ui-source/archive/refs/heads/$branch.zip" -OutFile $zipPath
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $version = $zip.Entries | Where-Object { $_.FullName -match '^[^/]+/version\.txt$' } | Select-Object -First 1
        if (-not $version) { throw "No version.txt in the $branch archive." }
        $reader = New-Object IO.StreamReader($version.Open())
        $build = $reader.ReadToEnd().Trim()
        $reader.Close()
        if ($build -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw "The $branch archive's version.txt says '$build', not a build number." }
        $dir = Join-Path $ToolsDir "api_docs\$branch-$build"
        $docs = @($zip.Entries | Where-Object { $_.FullName -match '/Blizzard_APIDocumentationGenerated/[^/]+Documentation\.lua$' })
        if ($docs.Count -lt 100) { throw "Only $($docs.Count) documentation files in the $branch archive: has the mirror's layout changed?" }
        if (-not (Test-Path $dir) -or @(Get-ChildItem (Join-Path $dir '*.lua')).Count -ne $docs.Count) {
            New-Item -ItemType Directory -Force $dir | Out-Null
            foreach ($entry in $docs) { [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $dir ($entry.FullName -split '/')[-1]), $true) }
        }
    } finally { $zip.Dispose() }
    return @{ Build = $build; Dir = $dir }
}

# Reads a saved list into functions and events keyed by their full name.
function Read-List([string]$path) {
    $functions = @{}; $events = @{}
    foreach ($row in [IO.File]::ReadAllLines($path)) {
        $f = $row -split "`t"
        if ($f.Count -lt 6) { continue }
        $key = if ($f[2]) { "$($f[2]).$($f[3])" } else { $f[3] }
        $where = if ($f[2]) { $f[2] } else { $f[1] }
        if ($f[0] -eq 'F') { $functions[$key] = @{ Where = $where; Shape = "($($f[4])) -> $($f[5])" } }
        elseif ($f[0] -eq 'E') { $events[$f[3]] = @{ Where = $where; Shape = "($($f[4]))" } }
    }
    return @{ Functions = $functions; Events = $events }
}

function Compare-Branch([string]$branch, [string[]]$calls) {
    $got = Get-BranchDocs $branch
    $build = $got.Build
    Write-Output "== $branch build $build"
    $files = @(Get-ChildItem (Join-Path $got.Dir '*.lua') | Sort-Object Name)
    $listFile = Join-Path $ToolsDir "api_docs-$branch-$build.tsv"
    $output = @(& $LuaExe (Join-Path $PSScriptRoot 'Read-ApiDocs.lua') $got.Dir @($files | ForEach-Object { $_.Name }))
    if ($LASTEXITCODE -ne 0) { throw "Read-ApiDocs.lua failed on $($got.Dir)." }
    $lines = @($output | Where-Object { $_ -notmatch '^#' })
    $notLoaded = @($output | Where-Object { $_ -match '^# .*: ' })
    if ($lines.Count -lt 1000) { throw "Read-ApiDocs.lua gave $($lines.Count) lines for $branch; it should give thousands." }
    [IO.File]::WriteAllLines($listFile, [string[]]$lines)
    $new = Read-List $listFile
    $namespaces = @($new.Functions.Values | Where-Object { $_.Where -match '^C_' } | ForEach-Object { $_.Where } | Sort-Object -Unique)
    Write-Output "$($files.Count) documentation files ($($notLoaded.Count) constants files that don't load on their own): $($new.Functions.Count) functions in $($namespaces.Count) C_ namespaces and the global systems, $($new.Events.Count) events."

    $earlier = Get-ChildItem (Join-Path $ToolsDir "api_docs-$branch-*.tsv") |
        Where-Object { $_.BaseName -ne "api_docs-$branch-$build" } |
        Sort-Object { [version]($_.BaseName -replace "^api_docs-$branch-") } | Select-Object -Last 1
    $old = $null
    if ($earlier) {
        $old = Read-List $earlier.FullName
        $addedF = @($new.Functions.Keys | Where-Object { -not $old.Functions.ContainsKey($_) } | Sort-Object)
        $goneF = @($old.Functions.Keys | Where-Object { -not $new.Functions.ContainsKey($_) } | Sort-Object)
        $changedF = @($new.Functions.Keys | Where-Object { $old.Functions.ContainsKey($_) -and $old.Functions[$_].Shape -ne $new.Functions[$_].Shape } | Sort-Object)
        $addedE = @($new.Events.Keys | Where-Object { -not $old.Events.ContainsKey($_) } | Sort-Object)
        $goneE = @($old.Events.Keys | Where-Object { -not $new.Events.ContainsKey($_) } | Sort-Object)
        Write-Output "Against $($earlier.Name): functions $($addedF.Count) added, $($goneF.Count) removed, $($changedF.Count) changed; events $($addedE.Count) added, $($goneE.Count) removed."
        foreach ($k in $addedF) { Write-Output ("  added:   $k$($new.Functions[$k].Shape)" + $(if ($new.Functions[$k].Where -match $questLike) { "  <- quest-related, worth a look" } else { "" })) }
        foreach ($k in $goneF) { Write-Output ("  removed: $k" + $(if ($old.Functions[$k].Where -match $questLike) { "  <- quest-related" } else { "" })) }
        foreach ($k in $changedF) { Write-Output "  changed: $k was $($old.Functions[$k].Shape), now $($new.Functions[$k].Shape)" }
        foreach ($k in $addedE) { Write-Output ("  event added:   $k$($new.Events[$k].Shape)" + $(if ($new.Events[$k].Where -match $questLike) { "  <- quest-related" } else { "" })) }
        foreach ($k in $goneE) { Write-Output "  event removed: $k" }
    } else {
        Write-Output "No earlier list for this branch to compare with (saved as $($listFile | Split-Path -Leaf))."
    }

    $present = 0; $absent = @(); $broken = 0
    $script:documented[$branch] = @()
    foreach ($call in $calls) {
        if ($new.Functions.ContainsKey($call)) {
            $present++
            $script:documented[$branch] += $call
            if ($old -and -not $old.Functions.ContainsKey($call)) {
                Write-Output "  the addon calls ${call}: not documented in $($earlier.Name), documented now. This game has gained it: check that the code reads it as its fallback did, and share any feature gated on it (docs\plans\game-parity.md)."
                $broken++
            } elseif ($old -and $old.Functions[$call].Shape -ne $new.Functions[$call].Shape) {
                Write-Output "  the addon calls ${call}: its shape changed, was $($old.Functions[$call].Shape), now $($new.Functions[$call].Shape)"
                $broken++
            }
        } elseif ($old -and $old.Functions.ContainsKey($call)) {
            Write-Output "  the addon calls ${call}: documented in $($earlier.Name), gone now"
            $broken++
        } else {
            $absent += $call
        }
    }
    Write-Output ("$($calls.Count) functions the addon calls: $present documented on this branch" + $(if ($absent) { "; not documented here: $($absent -join ', ')" } else { "" }) + ".")
    $script:brokenTotal += $broken
}

$calls = Get-AddonCalls
$script:brokenTotal = 0
$script:documented = @{}
foreach ($branch in $Branches) { Compare-Branch $branch $calls }
if ($Branches.Count -gt 1) {
    $only = @()
    foreach ($call in $calls) {
        $has = @($Branches | Where-Object { $script:documented[$_] -contains $call })
        if ($has.Count -gt 0 -and $has.Count -lt $Branches.Count) { $only += "$call ($($has -join ', ') only)" }
    }
    Write-Output ("Functions the addon calls that one game documents and another doesn't: " + $(if ($only) { $only -join '; ' } else { 'none' }) + ". The code guards each, with a fallback where it has one; when a game gains one, check the fallback against it and share any feature gated on it (docs\plans\game-parity.md).")
}
if ($script:brokenTotal -gt 0) {
    Write-Output "$script:brokenTotal function(s) the addon calls have gone, changed, or newly appeared on a game that lacked them: check the code before the sweep goes on."
    exit 1
}
Write-Output "Every function the addon calls is documented as before on each branch that documents it."
