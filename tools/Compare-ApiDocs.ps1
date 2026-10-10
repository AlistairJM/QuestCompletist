<#
Reports what changed in the game's Lua API between builds, so that a sweep notices a function or
event the addon relies on going missing or changing shape or secrecy, and sees new functions and
events worth a look. It reads Blizzard's generated API documentation from the UI source mirror
Gethe/wow-ui-source, one branch per game (live for retail, forever for WoW: Forever), as the API
review did (docs\plans\game-api-review.md, recommendation 11). The documentation is partial: the old
global functions (GetQuestID, GetAvailableQuestInfo and the rest) aren't in it, so only the C_
functions and the documented globals can be checked.

For each branch it downloads the branch's archive, takes the build from its version.txt, keeps the
documentation files in tools\api_docs\<branch>-<build>\, and has Read-ApiDocs.lua turn them into
tools\api_docs-<branch>-<build>.tsv. It then compares that with the newest earlier list saved for
the same branch (an earlier build, never a later one): functions and events added and removed, with
the quest-related namespaces picked out, and for every function the addon calls (the C_ calls in
QuestCompletist\*.lua and QuestCompletist\Forever\*.lua, plus the documented globals it uses: the
-Globals list, and any other documented global its code names) whether it is still there with the
same arguments and returns. A function the addon calls that has gone or changed since the earlier
list exits with 1: check the code before the sweep goes on. New functions are a prompt to look, not
a failure.

Secrecy is compared the same way. Read-ApiDocs.lua keeps every flag with "Secret" in its name and
the preconditions the documentation declares, on the function or event, on each argument, return and
payload field, and on the fields of every structure those lead to, and a function or event whose
flags changed is listed (the quest-related ones, and the ones the addon relies on; -ListAll lists
them all). A change in the flags of a function the addon calls, or of an event it listens for, exits
with 1 as a change of shape does: a flag that makes a value secret in combat or an instance can stop
the addon reading it. An event the addon listens for is any quoted name in its Lua that the
documentation lists as an event; one that has gone, or whose payload changed, exits with 1 too. The
fields of a structure are compared only for their flags, not for fields added, removed or retyped.
An earlier list saved before the flags were kept is read again from its documentation folder, so it
needs no download. A documentation file that stopped loading (or started) is named: what it
documents shows as removed (or added).

A few structures and enumerations the addon (or its probe) reads are watched field by field, as functions are:
-Tables names them (UIMapType, whose Continent and Zone values the continent icons look for, and UiMapDetails, the
map facts they read). A field added, removed or retyped, or an enumeration value renumbered, or one that goes,
exits with 1: the code reads the value by its number or the field by its name.

A function the addon calls that one game documents and the other doesn't (C_SkillInfo on retail)
is listed at the end: the code guards each, with a fallback where it has one (the skill check
reads the character's profession list without C_SkillInfo), and what is still that game's alone is
in docs\plans\game-parity.md. When such a function turns up in a game's documentation that
lacked it in the earlier list, that exits with 1 too: the game has gained it, so check that the
code reads it as its fallback did, and share any feature that was gated on it. Events are listed
the same way, without the exit.

  .\Compare-ApiDocs.ps1
  .\Compare-ApiDocs.ps1 -Branches live
  .\Compare-ApiDocs.ps1 -ListAll
  .\Compare-ApiDocs.ps1 -SourceDir <folder holding live\ and forever\, each with version.txt and the *Documentation.lua files>

-SourceDir reads the documentation from a folder instead of downloading it. -MinFiles and -MinLines
are the sanity limits on what a download or a reading must hold; the tests lower them.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string[]]$Branches = @('live', 'forever'),
    [string[]]$Tables = @('UIMapType', 'UiMapDetails'),
    [string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe',
    [string]$DownloadDir = (Join-Path $env:TEMP 'api_docs'),
    [string]$SourceDir,
    [int]$MinFiles = 100,
    [int]$MinLines = 1000,
    [switch]$ListAll,
    [string[]]$Globals = @('UnitName', 'UnitLevel', 'UnitRace', 'UnitClass', 'UnitFactionGroup', 'UnitQuestTrivialLevelRange', 'UnitGUID', 'IsInInstance', 'GetBuildInfo', 'GetLocale', 'GetTime', 'CheckInteractDistance', 'CreateFromMixins', 'IsLeftAltKeyDown', 'IsLeftShiftKeyDown', 'IsModifierKeyDown', 'IsShiftKeyDown', 'issecretvalue')
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($PSBoundParameters.ContainsKey('SourceDir') -and -not $SourceDir) { throw '-SourceDir was given but is empty; leave it out to download.' }
foreach ($name in 'ToolsDir', 'AddonDir', 'DownloadDir', 'SourceDir') {
    $value = Get-Variable $name -ValueOnly
    if ($value) { Set-Variable $name ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($value)) }
}
$questLike = 'Quest|Map|Poi|POI|Gossip|Tooltip|Creature|Calendar|Reputation|MajorFaction|Campaign|SuperTrack|Minimap|Vignette|EventScheduler|GameRules|SkillInfo|Covenant|Journal|PlayerInfo|^Unit$|Navigation|Holiday|TaskQuest|Scenario|AdventureMap'
if (-not (Test-Path $LuaExe)) { throw "Lua 5.1 wasn't found at $LuaExe (docs\maintenance.md, one-time setup)." }

# What the addon's Lua names, with its comments taken out: the C_Namespace.Function calls, the
# documented globals given, the quoted names that may be events, and the bare names that may be
# global calls (any name not reached through a dot or colon, not assigned to, with strings blanked).
function Get-AddonSource {
    $raw = New-Object System.Collections.Generic.List[string]
    foreach ($file in @(Get-ChildItem (Join-Path $AddonDir '*.lua')) + @(Get-ChildItem (Join-Path $AddonDir 'Forever\*.lua') -ErrorAction SilentlyContinue)) {
        $raw.Add([IO.File]::ReadAllText($file.FullName))
    }
    if ($raw.Count -eq 0) { throw "No .lua files in $AddonDir." }
    $text = $raw -join "`n"
    $strings = '"(?:\\.|[^"\\\r\n])*"|''(?:\\.|[^''\\\r\n])*'''
    $code = [regex]::Replace($text, "($strings)|--\[(=*)\[[\s\S]*?\]\2\]|--[^\r\n]*", { param($m) if ($m.Groups[1].Success) { $m.Value } else { '' } })
    $events = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($code, '["'']([A-Z][A-Z0-9_]{3,})["'']')) { [void]$events.Add($m.Groups[1].Value) }
    $bare = [regex]::Replace($code, $strings, '""')
    $words = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($bare, '(?<![\w:])(?<!(?<!\.)\.)([A-Za-z_][A-Za-z0-9_]+)(?!\w)(?!\s*=(?!=))')) { [void]$words.Add($m.Groups[1].Value) }
    $calls = @{}
    foreach ($m in [regex]::Matches($code, '\bC_\w+\.\w+')) { $calls[$m.Value] = $true }
    foreach ($g in $Globals) { $calls[$g] = $true }
    return @{ Calls = @($calls.Keys | Sort-Object); Events = $events; Words = $words }
}

function Assert-Build([string]$branch, [string]$build) {
    if ($build -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw "The $branch version.txt says '$build', not a build number." }
}

# Puts the documentation files where the lists are read from, tools\api_docs\<branch>-<build>\,
# replacing any copy kept from an earlier run of the same build.
function Install-Docs([string]$branch, [string]$build, [int]$count, [scriptblock]$copy) {
    $dir = Join-Path $ToolsDir "api_docs\$branch-$build"
    if ($count -lt $MinFiles) { throw "Only $count documentation files for ${branch}: has the mirror's layout changed?" }
    $stage = "$dir.new"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force $stage | Out-Null
    & $copy $stage
    if (Test-Path $dir) { Get-ChildItem (Join-Path $dir '*.lua') | Remove-Item -Force }
    New-Item -ItemType Directory -Force $dir | Out-Null
    Get-ChildItem (Join-Path $stage '*.lua') | Move-Item -Destination $dir -Force
    Remove-Item $stage -Recurse -Force
    return @{ Build = $build; Dir = $dir }
}

# Downloads the branch's archive and keeps its documentation folder and build.
function Get-DownloadedDocs([string]$branch) {
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
        Assert-Build $branch $build
        $docs = @($zip.Entries | Where-Object { $_.FullName -match '/Blizzard_APIDocumentationGenerated/[^/]+Documentation\.lua$' })
        return Install-Docs $branch $build $docs.Count {
            param($dir)
            foreach ($entry in $docs) { [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $dir ($entry.FullName -split '/')[-1]), $true) }
        }
    } finally { $zip.Dispose() }
}

# Takes the branch's build and documentation files from -SourceDir\<branch>\ instead.
function Get-LocalDocs([string]$branch) {
    $from = Join-Path $SourceDir $branch
    $versionFile = Join-Path $from 'version.txt'
    if (-not (Test-Path $versionFile)) { throw "No version.txt in $from." }
    $build = ([IO.File]::ReadAllText($versionFile)).Trim()
    Assert-Build $branch $build
    $docs = @(Get-ChildItem (Join-Path $from '*Documentation.lua'))
    return Install-Docs $branch $build $docs.Count {
        param($dir)
        foreach ($doc in $docs) { Copy-Item $doc.FullName (Join-Path $dir $doc.Name) -Force }
    }
}

function Get-BranchDocs([string]$branch) {
    if ($SourceDir) { return Get-LocalDocs $branch }
    return Get-DownloadedDocs $branch
}

# Has Read-ApiDocs.lua read a documentation folder and saves the list, with the reader's # lines
# (the files that didn't load, and the count) at the end.
function Write-List([string]$dir, [string]$listFile) {
    $files = @(Get-ChildItem (Join-Path $dir '*.lua') | Sort-Object Name)
    $output = @(& $LuaExe (Join-Path $PSScriptRoot 'Read-ApiDocs.lua') $dir @($files | ForEach-Object { $_.Name }))
    if ($LASTEXITCODE -ne 0) { throw "Read-ApiDocs.lua failed on $dir." }
    $lines = @($output | Where-Object { $_ -notmatch '^#' })
    if ($lines.Count -lt $MinLines) { throw "Read-ApiDocs.lua gave $($lines.Count) lines for $dir; it should give thousands." }
    $notes = @($output | Where-Object { $_ -match '^#' })
    [IO.File]::WriteAllLines($listFile, [string[]]($lines + $notes))
    return @{ Files = $files.Count; NotLoaded = @($notes | Where-Object { $_ -match '^# .*: ' }).Count }
}

# Reads a saved list into functions and events keyed by their full name, which Lua reads with its
# case (Select, a housing method, is not select), and the files that didn't load. A name two
# systems document is one key holding both shapes, so the order of the files can't matter.
function Read-List([string]$path) {
    $functions = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    $events = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    $notLoaded = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    $tables = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    $withSecrecy = $false; $withLoadInfo = $false
    foreach ($row in [IO.File]::ReadAllLines($path)) {
        if ($row.StartsWith('#')) {
            if ($row -match '^# \d+ files, \d+ failed to load$') { $withLoadInfo = $true }
            elseif ($row -match '^# ([^:]+): (.*)$') { $notLoaded[$Matches[1]] = $Matches[2] }
            continue
        }
        $f = $row -split "`t"
        if ($f.Count -lt 6) { continue }
        $secrecy = ''
        if ($f.Count -ge 8) { $withSecrecy = $true; $secrecy = $f[7] }
        $key = if ($f[2]) { "$($f[2]).$($f[3])" } else { $f[3] }
        $where = if ($f[2]) { $f[2] } else { $f[1] }
        if ($f[0] -eq 'F') { $table = $functions; $shape = "($($f[4])) -> $($f[5])" }
        elseif ($f[0] -eq 'E') { $table = $events; $key = $f[3]; $shape = "($($f[4]))" }
        elseif ($f[0] -eq 'T') {
            $name = $f[3] -replace ' \((Enumeration|Structure|CallbackType)\)$', ''
            if (-not $tables.ContainsKey($name)) { $tables[$name] = $f[4] }
            continue
        }
        else { continue }
        if ($table.ContainsKey($key)) {
            $entry = $table[$key]
            $entry.Shapes = @($entry.Shapes + $shape | Sort-Object -Unique -CaseSensitive)
            $entry.Shape = $entry.Shapes -join ' | '
            $entry.Secrecy = (@($entry.Secrecy -split '; ') + @($secrecy -split '; ') | Where-Object { $_ } | Sort-Object -Unique -CaseSensitive) -join '; '
        } else {
            $table[$key] = @{ Where = $where; Bare = (-not $f[2]); Shapes = @($shape); Shape = $shape; Secrecy = $secrecy }
        }
    }
    return @{ Functions = $functions; Events = $events; Tables = $tables; NotLoaded = $notLoaded; HasSecrecy = $withSecrecy; HasLoadInfo = $withLoadInfo }
}

# What two secrecy texts differ by: "+flag; -flag", or nothing.
function Get-SecrecyChange([string]$old, [string]$new) {
    if ($old -ceq $new) { return '' }
    $o = @($old -split '; ' | Where-Object { $_ })
    $n = @($new -split '; ' | Where-Object { $_ })
    $added = @($n | Where-Object { $o -cnotcontains $_ } | ForEach-Object { "+$_" })
    $removed = @($o | Where-Object { $n -cnotcontains $_ } | ForEach-Object { "-$_" })
    return (@($added) + @($removed)) -join '; '
}

function Get-SecrecyChanges($old, $new) {
    $changes = @{}
    foreach ($k in $new.Keys) {
        if ($old.ContainsKey($k)) {
            $change = Get-SecrecyChange $old[$k].Secrecy $new[$k].Secrecy
            if ($change) { $changes[$k] = $change }
        }
    }
    return $changes
}

function Compare-Branch([string]$branch, $source) {
    $got = Get-BranchDocs $branch
    $build = $got.Build
    Write-Output "== $branch build $build"
    $listFile = Join-Path $ToolsDir "api_docs-$branch-$build.tsv"
    $made = Write-List $got.Dir $listFile
    $new = Read-List $listFile
    if ($new.NotLoaded.ContainsKey('SecretPredicatesDocumentation.lua')) { $script:notCompared += "the Requires preconditions on $branch (SecretPredicatesDocumentation.lua doesn't load)" }
    $namespaces = @($new.Functions.Values | Where-Object { $_.Where -match '^C_' } | ForEach-Object { $_.Where } | Sort-Object -Unique)
    $flagged = @($new.Functions.Values | Where-Object { $_.Secrecy }).Count
    $flaggedE = @($new.Events.Values | Where-Object { $_.Secrecy }).Count
    Write-Output "$($made.Files) documentation files ($($made.NotLoaded) don't load on their own: constants files and widget-method files that refer to Enum or Constants): $($new.Functions.Count) functions in $($namespaces.Count) C_ namespaces and the global systems, $($new.Events.Count) events; $flagged functions and $flaggedE events carry secrecy flags."

    $earlier = Get-ChildItem (Join-Path $ToolsDir "api_docs-$branch-*.tsv") |
        Where-Object { $_.BaseName -match "^api_docs-$branch-\d+\.\d+\.\d+\.\d+$" -and [version]($_.BaseName -replace "^api_docs-$branch-") -lt [version]$build } |
        Sort-Object { [version]($_.BaseName -replace "^api_docs-$branch-") } | Select-Object -Last 1
    $old = $null
    $secrecyF = @{}; $secrecyE = @{}
    if ($earlier) {
        $old = Read-List $earlier.FullName
        $stale = -not $old.HasSecrecy -or -not $old.HasLoadInfo
        $oldDir = Join-Path $ToolsDir ("api_docs\$branch-" + ($earlier.BaseName -replace "^api_docs-$branch-"))
        if (Test-Path $oldDir) {
            [void](Write-List $oldDir $earlier.FullName)
            $old = Read-List $earlier.FullName
            if ($stale) { Write-Output "$($earlier.Name) was saved before the secrecy flags were kept; read again from $oldDir." }
        } elseif ($stale) {
            Write-Output "$($earlier.Name) was saved before the secrecy flags were kept and $oldDir is gone: secrecy is not compared this time."
            $script:notCompared += "secrecy on $branch"
        }
        $addedF = @($new.Functions.Keys | Where-Object { -not $old.Functions.ContainsKey($_) } | Sort-Object)
        $goneF = @($old.Functions.Keys | Where-Object { -not $new.Functions.ContainsKey($_) } | Sort-Object)
        $changedF = @($new.Functions.Keys | Where-Object { $old.Functions.ContainsKey($_) -and $old.Functions[$_].Shape -ne $new.Functions[$_].Shape } | Sort-Object)
        $addedE = @($new.Events.Keys | Where-Object { -not $old.Events.ContainsKey($_) } | Sort-Object)
        $goneE = @($old.Events.Keys | Where-Object { -not $new.Events.ContainsKey($_) } | Sort-Object)
        Write-Output "Against $($earlier.Name): functions $($addedF.Count) added, $($goneF.Count) removed, $($changedF.Count) changed; events $($addedE.Count) added, $($goneE.Count) removed."
        if ($old.HasLoadInfo) {
            foreach ($file in @($new.NotLoaded.Keys | Where-Object { -not $old.NotLoaded.ContainsKey($_) } | Sort-Object)) {
                Write-Output "  $file loaded before and doesn't now ($($new.NotLoaded[$file])): what it documents shows as removed."
                $script:notices += "$file no longer loads on $branch"
            }
            foreach ($file in @($old.NotLoaded.Keys | Where-Object { -not $new.NotLoaded.ContainsKey($_) } | Sort-Object)) {
                Write-Output "  $file didn't load before and does now: what it documents shows as added."
                $script:notices += "$file loads on $branch now"
            }
        }
        foreach ($k in $addedF) { Write-Output ("  added:   $k$($new.Functions[$k].Shape)" + $(if ($new.Functions[$k].Where -match $questLike) { "  <- quest-related, worth a look" } else { "" }) + $(if ($new.Functions[$k].Secrecy) { "  [$($new.Functions[$k].Secrecy)]" } else { "" })) }
        foreach ($k in $goneF) { Write-Output ("  removed: $k" + $(if ($old.Functions[$k].Where -match $questLike) { "  <- quest-related" } else { "" })) }
        foreach ($k in $changedF) { Write-Output "  changed: $k was $($old.Functions[$k].Shape), now $($new.Functions[$k].Shape)" }
        foreach ($k in $addedE) { Write-Output ("  event added:   $k$($new.Events[$k].Shape)" + $(if ($new.Events[$k].Where -match $questLike) { "  <- quest-related" } else { "" }) + $(if ($new.Events[$k].Secrecy) { "  [$($new.Events[$k].Secrecy)]" } else { "" })) }
        foreach ($k in $goneE) { Write-Output "  event removed: $k" }
    } else {
        Write-Output "No earlier list for this branch to compare with (saved as $($listFile | Split-Path -Leaf))."
        $script:notCompared += "$branch (no earlier list)"
    }

    $calls = $source.Calls
    $extra = @($source.Words | Where-Object { $_ -notin $calls -and (($new.Functions.ContainsKey($_) -and $new.Functions[$_].Bare) -or ($old -and $old.Functions.ContainsKey($_) -and $old.Functions[$_].Bare)) } | Sort-Object)
    if ($extra) {
        Write-Output "Also checked, as documented globals the addon appears to call that -Globals doesn't list: $($extra -join ', ')."
        $calls = @($calls + $extra | Sort-Object)
    }
    $script:callsOf[$branch] = $calls

    if ($old -and $old.HasSecrecy) {
        $secrecyF = Get-SecrecyChanges $old.Functions $new.Functions
        $secrecyE = Get-SecrecyChanges $old.Events $new.Events
        $relied = @($secrecyF.Keys | Where-Object { $calls -contains $_ }) + @($secrecyE.Keys | Where-Object { $source.Events.Contains($_) })
        $questy = @($secrecyF.Keys | Where-Object { $new.Functions[$_].Where -match $questLike }) + @($secrecyE.Keys | Where-Object { $new.Events[$_].Where -match $questLike })
        Write-Output "Secrecy flags changed on $($secrecyF.Count) functions and $($secrecyE.Count) events ($($questy.Count) quest-related, $($relied.Count) the addon relies on)."
        $hidden = 0
        foreach ($k in @($secrecyF.Keys | Sort-Object)) {
            if ($ListAll -or $new.Functions[$k].Where -match $questLike -or $calls -contains $k) { Write-Output "  secrecy: $k  $($secrecyF[$k])" } else { $hidden++ }
        }
        foreach ($k in @($secrecyE.Keys | Sort-Object)) {
            if ($ListAll -or $new.Events[$k].Where -match $questLike -or $source.Events.Contains($k)) { Write-Output "  secrecy: event $k  $($secrecyE[$k])" } else { $hidden++ }
        }
        if ($hidden -gt 0) { Write-Output "  ($hidden more outside the quest-related systems; -ListAll lists them.)" }
    }

    $present = 0; $absent = @(); $broken = 0
    $script:documented[$branch] = @()
    foreach ($call in $calls) {
        if ($new.Functions.ContainsKey($call)) {
            $present++
            $script:documented[$branch] += $call
            $problem = $false
            if ($old -and -not $old.Functions.ContainsKey($call)) {
                Write-Output ("  the addon calls ${call}: not documented in $($earlier.Name), documented now. This game has gained it: check that the code reads it as its fallback did, and share any feature gated on it (docs\plans\game-parity.md)." +
                    $(if ($extra -contains $call) { " (Only a word the addon uses, so a local or parameter of that name would do this; it will not repeat on the next build.)" } else { "" }))
                $problem = $true
            } elseif ($old -and $old.Functions[$call].Shape -ne $new.Functions[$call].Shape) {
                Write-Output "  the addon calls ${call}: its shape changed, was $($old.Functions[$call].Shape), now $($new.Functions[$call].Shape)"
                $problem = $true
            }
            if ($secrecyF.ContainsKey($call)) {
                Write-Output "  the addon calls ${call}: its secrecy flags changed ($($secrecyF[$call])). Check the arguments the code passes and what it reads back, in combat and in an instance."
                $problem = $true
            }
            if ($problem) { $broken++ }
        } elseif ($old -and $old.Functions.ContainsKey($call)) {
            Write-Output "  the addon calls ${call}: documented in $($earlier.Name), gone now"
            $broken++
        } else {
            $absent += $call
        }
    }
    Write-Output ("$($calls.Count) C_ functions and listed globals the addon calls: $present documented on this branch" + $(if ($absent) { "; not documented here: $($absent -join ', ')" } else { "" }) + ".")

    $listened = @($source.Events | Where-Object { $new.Events.ContainsKey($_) -or ($old -and $old.Events.ContainsKey($_)) } | Sort-Object)
    $eventsPresent = 0; $eventBroken = 0
    $script:listenedOn[$branch] = @($listened | Where-Object { $new.Events.ContainsKey($_) })
    foreach ($ev in $listened) {
        if ($new.Events.ContainsKey($ev)) {
            $eventsPresent++
            $problem = $false
            if ($old -and $old.Events.ContainsKey($ev) -and $old.Events[$ev].Shape -ne $new.Events[$ev].Shape) {
                Write-Output "  the addon listens for ${ev}: its payload changed, was $($old.Events[$ev].Shape), now $($new.Events[$ev].Shape)"
                $problem = $true
            }
            if ($secrecyE.ContainsKey($ev)) {
                Write-Output "  the addon listens for ${ev}: its secrecy flags changed ($($secrecyE[$ev])). Check what the code reads from it, in combat and in an instance."
                $problem = $true
            }
            if ($problem) { $eventBroken++ }
        } else {
            Write-Output "  the addon listens for ${ev}: documented in $($earlier.Name), gone now"
            $eventBroken++
        }
    }
    Write-Output "$($listened.Count) events the addon listens for are documented: $eventsPresent on this branch."
    $script:brokenTotal += $broken + $eventBroken

    $tablesPresent = 0; $tablesAbsent = @()
    foreach ($name in $Tables) {
        if ($new.Tables.ContainsKey($name)) {
            $tablesPresent++
            if ($old -and $old.Tables.ContainsKey($name) -and $old.Tables[$name] -cne $new.Tables[$name]) {
                Write-Output "  the addon relies on ${name}: its fields changed, was $($old.Tables[$name]), now $($new.Tables[$name])"
                $script:tablesBroken++
            }
        } elseif ($old -and $old.Tables.ContainsKey($name)) {
            Write-Output "  the addon relies on ${name}: documented in $($earlier.Name), gone now"
            $script:tablesBroken++
        } else {
            $tablesAbsent += $name
        }
    }
    Write-Output ("$($Tables.Count) structures and enumerations the addon relies on: $tablesPresent documented on this branch" + $(if ($tablesAbsent) { "; not documented here: $($tablesAbsent -join ', ')" } else { "" }) + ".")
}

$source = Get-AddonSource
$script:brokenTotal = 0
$script:tablesBroken = 0
$script:documented = @{}
$script:callsOf = @{}
$script:listenedOn = @{}
$script:notCompared = @()
$script:notices = @()
foreach ($branch in $Branches) { Compare-Branch $branch $source }
if ($Branches.Count -gt 1) {
    $only = @()
    $allCalls = @($script:callsOf.Values | ForEach-Object { $_ } | Sort-Object -Unique)
    foreach ($call in $allCalls) {
        $has = @($Branches | Where-Object { $script:documented[$_] -contains $call })
        if ($has.Count -gt 0 -and $has.Count -lt $Branches.Count) { $only += "$call ($($has -join ', ') only)" }
    }
    Write-Output ("Functions the addon calls that one game documents and another doesn't: " + $(if ($only) { $only -join '; ' } else { 'none' }) + ". The code guards each, with a fallback where it has one; when a game gains one, check the fallback against it and share any feature gated on it (docs\plans\game-parity.md).")
    $onlyEvents = @()
    foreach ($ev in @($script:listenedOn.Values | ForEach-Object { $_ } | Sort-Object -Unique)) {
        $has = @($Branches | Where-Object { $script:listenedOn[$_] -contains $ev })
        if ($has.Count -lt $Branches.Count) { $onlyEvents += "$ev ($($has -join ', ') only)" }
    }
    Write-Output ("Events the addon listens for that one game documents and another doesn't: " + $(if ($onlyEvents) { $onlyEvents -join '; ' } else { 'none' }) + ".")
}
if ($script:tablesBroken -gt 0) {
    Write-Output "$script:tablesBroken structure(s) or enumeration(s) the addon relies on have changed or gone: check the code that reads them (-Tables lists them) before the sweep goes on."
}
if ($script:brokenTotal -gt 0) {
    Write-Output "$script:brokenTotal function(s) or event(s) the addon relies on have gone, changed (shape or secrecy), or newly appeared on a game that lacked them: check the code before the sweep goes on."
}
if ($script:brokenTotal -gt 0 -or $script:tablesBroken -gt 0) { exit 1 }
$unchecked = "Not checked: the contents of structures beyond their flags, except the ones -Tables names, and the old globals (GetQuestID, GetNumAvailableQuests and the recorder's other quest-window calls), which the documentation leaves out."
if ($script:notCompared.Count -gt 0 -or $script:notices.Count -gt 0) {
    Write-Output ("Nothing the addon relies on changed in what was compared." + $(if ($script:notCompared) { " Not compared: $($script:notCompared -join '; ')." } else { "" }) + $(if ($script:notices) { " See above: $($script:notices -join '; ')." } else { "" }) + " $unchecked")
    exit 0
}
Write-Output "Every documented function the addon calls and every event it listens for is documented as before, secrecy flags included, on each branch that documents it. $unchecked"
