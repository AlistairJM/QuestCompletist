<#
The rules of the quest giver notes, dot-sourced by Import-RecordedGivers.ps1 and Test-RecordedGivers.ps1:
	. "$PSScriptRoot\RecordedGivers.ps1"

The addon's recorder (QuestCompletist\qcRecorder.lua, plans\quest-giver-recorder.md) keeps notes of the
quest givers a player meets. A file of them is read by Read-RecordedGivers.lua, which refuses anything
that is not plain data, because a player may have sent it. What it prints becomes facts:
	giver  a creature, object or vehicle, with the English name the game gave it
	spot   where the player stood beside it, a map and a place in percent (-1 -1: the game gave none)
	offer  a quest it offered
	turnin a quest it took in
	start  a quest that began with no giver (an item or a trigger), where the player stood
Facts are kept in the ledger, plans\recorded-quest-givers.csv. A fact is a row there, and the row says
which sources saw it: Src is "tag=n;tag=n", the n being how many times that source saw it (visits for
a spot, 1 for the rest). The ledger only grows: a file read again replaces its own numbers, and a fact
a source no longer holds (the addon's notes are capped, and a player may clear them) stays.

A source is a tag. The maintainer's own files are "own-retail", "own-forever" and the Forever probe's
"own-probe-<build>"; all of them count as one source, "own", because they describe the same visits. A
player's file is under the tag the maintainer gave it (p01, p02: never a name). A fact is trusted when
"own" saw it or two different players did. How often a source saw it is never evidence.
#>

$script:Invariant = [Globalization.CultureInfo]::InvariantCulture

# How far apart two places on one map may be and still be one place: the pin spacing floor (two pins
# of one NPC may sit 1.5 map points apart, no closer), measured straight, as the pipeline does.
$RecordedPlaceRadius = 1.5
# More than this share of a file's records odd (and at least three of them): the file is not read.
$RecordedOddShare = 0.2
$RecordedLedgerColumns = @('Game', 'Role', 'Kind', 'Npc', 'Name', 'Map', 'X', 'Y', 'Quest', 'Item', 'StartKind', 'FirstBuild', 'LastBuild', 'Src')
$RecordedRoleOrder = @{ giver = 0; spot = 1; offer = 2; turnin = 3; start = 4 }

# The tag of a source, as the ledger spells it: letters, digits, "_" and "-", in lower case (Windows folder
# names ignore case, and a tag that held ";" or "=" would break the ledger's Src field).
function ConvertTo-RecordedTag([string]$name) {
    return ($name.ToLowerInvariant() -replace '[^a-z0-9_-]', '_')
}

# The source class of a tag: the maintainer's own files are one source.
function Get-RecordedClass([string]$tag) {
    if ($tag -like 'own-*') { return 'own' }
    return $tag
}

# "tag=n;tag=n" as an ordered table, and back.
function ConvertFrom-RecordedSrc([string]$src) {
    $table = [ordered]@{}
    if ($src) {
        foreach ($part in $src.Split(';')) {
            $at = $part.LastIndexOf('=')
            $count = 0
            if ($at -le 0 -or -not [int]::TryParse($part.Substring($at + 1), [ref]$count)) { throw "a source '$part' that is not tag=number" }
            $table[$part.Substring(0, $at)] = $count
        }
    }
    return $table
}
function ConvertTo-RecordedSrc($table) {
    return (($table.Keys | Sort-Object { $_ } -CaseSensitive | ForEach-Object { "$_=$($table[$_])" }) -join ';')
}

function New-ClassSet() {
    return , (New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase))
}

# Whether a ledger row's sources are enough to act on: the maintainer's own, or two players.
function Get-RecordedClasses($row) {
    $classes = New-ClassSet
    foreach ($tag in (ConvertFrom-RecordedSrc $row.Src).Keys) { [void]$classes.Add((Get-RecordedClass $tag)) }
    return , $classes
}
function Test-RecordedTrusted($row) {
    $classes = Get-RecordedClasses $row
    return $classes.Contains('own') -or $classes.Count -ge 2
}

# --- Reading a file ----------------------------------------------------------------------------

# Runs the reader on a file with a time limit and returns its exit code and its lines. The reader refuses
# what is not plain data, but a file is still a stranger's, so it does not get to take long.
function Invoke-RecordedReader([string]$LuaExe, [string]$ReaderScript, [string]$Path, [string]$Tag, [int]$TimeoutSeconds = 120) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $LuaExe
    $info.Arguments = '"' + $ReaderScript + '" "' + $Path + '" "' + $Tag + '"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding $false
    $process = [System.Diagnostics.Process]::Start($info)
    $out = $process.StandardOutput.ReadToEndAsync()
    $err = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        return [pscustomobject]@{ Exit = -1; Lines = @(); TimedOut = $true }
    }
    $process.WaitForExit()
    $lines = @($out.Result.Split("`n") | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne '' })
    return [pscustomobject]@{ Exit = $process.ExitCode; Lines = $lines; TimedOut = $false }
}

# Runs Read-RecordedGivers.lua on a saved-variables file and turns its lines into a record: Refused is
# the reason it would not read the file, or $null; the lists hold what the file says before any filter.
function Read-RecordedFile([string]$Path, [string]$Tag, [string]$LuaExe, [string]$ReaderScript) {
    $result = [pscustomobject]@{
        Tag = $Tag; Path = $Path; Refused = $null; Kind = ''; Schema = ''; Game = ''; Records = 0; Odd = 0
        Builds = @{}; Givers = (New-Object System.Collections.Generic.List[object]); Spots = (New-Object System.Collections.Generic.List[object])
        Offers = (New-Object System.Collections.Generic.List[object]); Turnins = (New-Object System.Collections.Generic.List[object])
        Quests = (New-Object System.Collections.Generic.List[object]); Starts = (New-Object System.Collections.Generic.List[object])
        Diag = @{}; Flagged = (New-Object System.Collections.Generic.List[object])
    }
    $run = Invoke-RecordedReader $LuaExe $ReaderScript $Path $Tag
    if ($run.TimedOut) { $result.Refused = 'the reader took more than two minutes'; return $result }
    if ($run.Exit -ne 0) {
        $first = if ($run.Lines.Count -gt 0) { [string]$run.Lines[0] } else { '' }
        $result.Refused = if ($first.StartsWith("refused`t")) { $first.Substring(8) } else { "the reader failed ($($run.Exit))" }
        return $result
    }
    try {
        foreach ($line in $run.Lines) {
            $f = $line.Split("`t")
            switch ($f[0]) {
                'file' { $result.Kind = $f[2]; $result.Schema = $f[3]; $result.Game = $f[4]; $result.Records = [int]$f[5]; $result.Odd = [int]$f[6] }
                'build' { $result.Builds[[int]$f[1]] = $f[2] }
                'giver' { $result.Givers.Add([pscustomobject]@{ Kind = $f[1]; Npc = [int]$f[2]; Name = $f[3]; Build = [int]$f[4] }) }
                'spot' { $result.Spots.Add([pscustomobject]@{ Kind = $f[1]; Npc = [int]$f[2]; Map = [int]$f[3]; X = $f[4]; Y = $f[5]; Visits = [int]$f[6]; Build = [int]$f[7] }) }
                'offer' { $result.Offers.Add([pscustomobject]@{ Kind = $f[1]; Npc = [int]$f[2]; Quest = [int]$f[3] }) }
                'turnin' { $result.Turnins.Add([pscustomobject]@{ Kind = $f[1]; Npc = [int]$f[2]; Quest = [int]$f[3] }) }
                'quest' {
                    $result.Quests.Add([pscustomobject]@{ Quest = [int]$f[1]; Build = [int]$f[2]; Frequency = $f[3]; Repeatable = $f[4]
                        Accepted = ($f[5] -eq '1'); Offered = ($f[6] -eq '1'); Faction = [int]$f[7]; Race = [long]$f[8]; Class = [long]$f[9]; Heading = $f[10] })
                }
                'start' { $result.Starts.Add([pscustomobject]@{ Quest = [int]$f[1]; StartKind = [int]$f[2]; Item = [int]$f[3]; Map = [int]$f[4]; X = $f[5]; Y = $f[6]; Build = [int]$f[7] }) }
                'diag' { $result.Diag[$f[1]] = [int]$f[2] }
                'flagged' { $result.Flagged.Add([pscustomobject]@{ Quest = [int]$f[1]; How = $f[2]; Build = $f[3] }) }
            }
        }
    } catch {
        $result.Refused = "its lines could not be read: $($_.Exception.Message)"
    }
    return $result
}

# What a file contributes once the filters have been applied, with a count of what each took out. The
# file's game comes from the versions in it, never from its folder. A file that is not read at all has
# its reason in Refused.
#   -Builds       version prefixes that are read ("12.1.0", "1.60.1")
#   -MapIds       per game, the set of map IDs the game has
#   -QuestIds     per game, the set of quest IDs the game's data has
function Get-RecordedFacts($file, [string[]]$Builds, [hashtable]$MapIds, [hashtable]$QuestIds) {
    $facts = [pscustomobject]@{
        Tag = $file.Tag; Game = ''; Refused = $null
        Givers = (New-Object System.Collections.Generic.List[object]); Spots = (New-Object System.Collections.Generic.List[object])
        Offers = (New-Object System.Collections.Generic.List[object]); Turnins = (New-Object System.Collections.Generic.List[object])
        Starts = (New-Object System.Collections.Generic.List[object]); Quests = (New-Object System.Collections.Generic.List[object])
        UnknownQuests = (New-Object System.Collections.Generic.List[object]); Flagged = $file.Flagged; Diag = $file.Diag
        Dropped = [ordered]@{ build = 0; map = 0; quest = 0 }; DroppedMaps = @{}
    }
    if ($file.Refused) { $facts.Refused = $file.Refused; return $facts }
    if ($file.Odd -ge 3 -and $file.Odd -gt $file.Records * $RecordedOddShare) {
        $facts.Refused = "$($file.Odd) of its $($file.Records) records are odd"
        return $facts
    }
    $game = $file.Game
    if ($game -ne 'retail' -and $game -ne 'forever') {
        $facts.Refused = if ($file.Builds.Count -eq 0) { 'it names no build' } else { "no game: its builds are $((@($file.Builds.Values) | Sort-Object) -join ', ')" }
        return $facts
    }
    $facts.Game = $game
    $accepted = @{}
    foreach ($build in $file.Builds.Keys) {
        foreach ($prefix in $Builds) {
            $p = $prefix.TrimEnd('.')
            if ($file.Builds[$build] -eq $p -or $file.Builds[$build].StartsWith("$p.")) { $accepted[$build] = $true }
        }
    }
    if ($accepted.Count -eq 0) {
        $facts.Refused = "none of its builds are read ($((@($file.Builds.Values) | Sort-Object) -join ', '))"
        return $facts
    }
    $maps = $MapIds[$game]
    $quests = $QuestIds[$game]
    function Test-Place($map, [string]$x, [string]$y) {
        if (-not $maps.Contains([int]$map)) { $facts.DroppedMaps[[int]$map] = 1 + [int]$facts.DroppedMaps[[int]$map]; return $false }
        $dx = [decimal]::Parse($x, [Globalization.NumberStyles]::Float, $script:Invariant); $dy = [decimal]::Parse($y, [Globalization.NumberStyles]::Float, $script:Invariant)
        if ($dx -eq -1 -and $dy -eq -1) { return $true }
        return $dx -ge 0 -and $dx -le 100 -and $dy -ge 0 -and $dy -le 100
    }
    foreach ($g in $file.Givers) {
        if (-not $accepted.ContainsKey($g.Build)) { $facts.Dropped.build++; continue }
        $facts.Givers.Add($g)
    }
    $keep = @{}
    foreach ($g in $facts.Givers) { $keep["$($g.Kind):$($g.Npc)"] = $true }
    foreach ($s in $file.Spots) {
        if (-not $accepted.ContainsKey($s.Build)) { $facts.Dropped.build++; continue }
        if (-not (Test-Place $s.Map $s.X $s.Y)) { $facts.Dropped.map++; continue }
        $facts.Spots.Add($s)
    }
    foreach ($o in $file.Offers) {
        if (-not $keep.ContainsKey("$($o.Kind):$($o.Npc)")) { $facts.Dropped.build++; continue }
        if (-not $quests.Contains($o.Quest)) { $facts.UnknownQuests.Add([pscustomobject]@{ Quest = $o.Quest; Kind = $o.Kind; Npc = $o.Npc; Role = 'offer' }); $facts.Dropped.quest++; continue }
        $facts.Offers.Add($o)
    }
    foreach ($t in $file.Turnins) {
        if (-not $keep.ContainsKey("$($t.Kind):$($t.Npc)")) { $facts.Dropped.build++; continue }
        if (-not $quests.Contains($t.Quest)) { $facts.Dropped.quest++; continue }
        $facts.Turnins.Add($t)
    }
    foreach ($s in $file.Starts) {
        if (-not $accepted.ContainsKey($s.Build)) { $facts.Dropped.build++; continue }
        if ($s.Map -ne 0 -and -not (Test-Place $s.Map $s.X $s.Y)) { $facts.Dropped.map++; continue }
        if (-not $quests.Contains($s.Quest)) { $facts.UnknownQuests.Add([pscustomobject]@{ Quest = $s.Quest; Kind = ''; Npc = 0; Role = 'start' }); $facts.Dropped.quest++; continue }
        $facts.Starts.Add($s)
    }
    foreach ($q in $file.Quests) {
        if (-not $accepted.ContainsKey($q.Build)) { $facts.Dropped.build++; continue }
        if (-not $quests.Contains($q.Quest)) { $facts.UnknownQuests.Add([pscustomobject]@{ Quest = $q.Quest; Kind = ''; Npc = 0; Role = 'quest' }); $facts.Dropped.quest++; continue }
        $facts.Quests.Add($q)
    }
    return $facts
}

# --- The ledger ---------------------------------------------------------------------------------

function Get-RecordedKey($row) {
    switch ($row.Role) {
        'giver' { return "$($row.Game)|giver|$($row.Kind)|$($row.Npc)|$($row.Name)" }
        'spot' { return "$($row.Game)|spot|$($row.Kind)|$($row.Npc)|$($row.Map)|$($row.X)|$($row.Y)" }
        'offer' { return "$($row.Game)|offer|$($row.Kind)|$($row.Npc)|$($row.Quest)" }
        'turnin' { return "$($row.Game)|turnin|$($row.Kind)|$($row.Npc)|$($row.Quest)" }
        'start' { return "$($row.Game)|start|$($row.Quest)|$($row.Map)|$($row.X)|$($row.Y)|$($row.StartKind)|$($row.Item)" }
    }
    throw "A ledger row of role '$($row.Role)'"
}

function New-RecordedRow([string]$game, [string]$role) {
    $row = [ordered]@{}
    foreach ($column in $RecordedLedgerColumns) { $row[$column] = '' }
    $row.Game = $game; $row.Role = $role
    return [pscustomobject]$row
}

# The ledger as a table of rows by key. The keys are compared exactly: a name that differs by a capital
# letter or an invisible character is a different giver row, never a corroboration of another.
function New-LedgerTable() {
    return , (New-Object System.Collections.Specialized.OrderedDictionary)
}

function Read-RecordedLedger([string]$Path) {
    $rows = New-LedgerTable
    if (-not (Test-Path $Path)) { return , $rows }
    $line = 1
    foreach ($csv in (Import-Csv $Path -Encoding UTF8)) {
        $line++
        try {
            $row = New-RecordedRow $csv.Game $csv.Role
            foreach ($column in $RecordedLedgerColumns) { $row.$column = [string]$csv.$column }
            $key = Get-RecordedKey $row
            $src = ConvertFrom-RecordedSrc $row.Src
            if ($rows.Contains($key)) {
                # The same fact twice (a merge of two copies of the file): the sources of both stand.
                Write-Warning "$(Split-Path -Leaf $Path) line ${line}: a repeated row, merged"
                $old = $rows[$key]
                $oldSrc = ConvertFrom-RecordedSrc $old.Src
                foreach ($tag in $src.Keys) { if (-not $oldSrc.Contains($tag) -or $oldSrc[$tag] -lt $src[$tag]) { $oldSrc[$tag] = $src[$tag] } }
                $old.Src = ConvertTo-RecordedSrc $oldSrc
                if ($row.FirstBuild -ne '' -and ($old.FirstBuild -eq '' -or [int]$row.FirstBuild -lt [int]$old.FirstBuild)) { $old.FirstBuild = $row.FirstBuild }
                if ($row.LastBuild -ne '' -and ($old.LastBuild -eq '' -or [int]$row.LastBuild -gt [int]$old.LastBuild)) { $old.LastBuild = $row.LastBuild }
            } else {
                $rows[$key] = $row
            }
        } catch {
            throw "$(Split-Path -Leaf $Path) line ${line}: $($_.Exception.Message)"
        }
    }
    return , $rows
}

# A total order, compared exactly, so the file is the same on every save whatever order it was read in
# (Sort-Object is not stable, and compares text by the culture).
function Get-RecordedSortedRows($ledger) {
    $rows = @($ledger.Values)
    $keys = New-Object 'string[]' $rows.Count
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        $x = if ($r.X -ne '') { [decimal]::Parse($r.X, $script:Invariant) + 1000 } else { [decimal]0 }
        $y = if ($r.Y -ne '') { [decimal]::Parse($r.Y, $script:Invariant) + 1000 } else { [decimal]0 }
        $num = { param($v) if ($v -ne '') { ([long]$v).ToString('D12') } else { ''.PadLeft(12, '0') } }
        $keys[$i] = "$($r.Game)|$($RecordedRoleOrder[$r.Role])|$($r.Kind)|$(& $num $r.Npc)|$(& $num $r.Quest)|$(& $num $r.Map)|$($x.ToString('00000.0000', $script:Invariant))|$($y.ToString('00000.0000', $script:Invariant))|$($r.Name)|$(& $num $r.Item)|$($r.StartKind)|$(Get-RecordedKey $r)`0$($i.ToString('D9'))"
    }
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    $sorted = New-Object 'object[]' $rows.Count
    for ($i = 0; $i -lt $keys.Count; $i++) { $sorted[$i] = $rows[[int]$keys[$i].Substring($keys[$i].Length - 9)] }
    return , $sorted
}

# The ledger the way the other tracked CSVs are written (a byte order mark, every field quoted, CRLF),
# and only when it differs from the file, so a rerun leaves it as it is.
function Save-RecordedLedger($ledger, [string]$Path) {
    $temp = [IO.Path]::GetTempFileName()
    try {
        $sorted = Get-RecordedSortedRows $ledger
        if ($sorted.Count -eq 0) {
            [IO.File]::WriteAllText($temp, ('"' + ($RecordedLedgerColumns -join '","') + '"' + "`r`n"), (New-Object System.Text.UTF8Encoding $true))
        } else {
            $sorted | Select-Object $RecordedLedgerColumns | Export-Csv -Path $temp -NoTypeInformation -Encoding UTF8
        }
        $new = [IO.File]::ReadAllBytes($temp)
        if ((Test-Path $Path) -and [Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($Path), [byte[]]$new)) { return $false }
        [IO.File]::WriteAllBytes($Path, $new)
        return $true
    } finally { Remove-Item $temp -ErrorAction SilentlyContinue }
}

# Puts a source's facts in the ledger: a row it saw gets the source's number, a row it didn't is left.
function Add-RecordedFacts($ledger, $facts) {
    $tag = $facts.Tag
    $game = $facts.Game
    function Set-Seen($row, [int]$build, [int]$count) {
        $key = Get-RecordedKey $row
        if ($ledger.Contains($key)) {
            $row = $ledger[$key]
        } else {
            $ledger[$key] = $row
            $row.FirstBuild = "$build"; $row.LastBuild = "$build"
        }
        $src = ConvertFrom-RecordedSrc $row.Src
        if (-not $src.Contains($tag) -or $src[$tag] -ne $count) { $src[$tag] = $count; $script:RecordedChanged++ }
        $row.Src = ConvertTo-RecordedSrc $src
        if ($build -lt [int]$row.FirstBuild) { $row.FirstBuild = "$build" }
        if ($build -gt [int]$row.LastBuild) { $row.LastBuild = "$build" }
    }
    $script:RecordedChanged = 0
    foreach ($g in $facts.Givers) {
        if ($g.Name -eq '') { continue }
        $row = New-RecordedRow $game 'giver'; $row.Kind = $g.Kind; $row.Npc = "$($g.Npc)"; $row.Name = $g.Name
        Set-Seen $row $g.Build 1
    }
    foreach ($s in $facts.Spots) {
        $row = New-RecordedRow $game 'spot'; $row.Kind = $s.Kind; $row.Npc = "$($s.Npc)"; $row.Map = "$($s.Map)"; $row.X = $s.X; $row.Y = $s.Y
        Set-Seen $row $s.Build $s.Visits
    }
    $buildOf = @{}
    foreach ($g in $facts.Givers) { $buildOf["$($g.Kind):$($g.Npc)"] = $g.Build }
    foreach ($o in $facts.Offers) {
        $row = New-RecordedRow $game 'offer'; $row.Kind = $o.Kind; $row.Npc = "$($o.Npc)"; $row.Quest = "$($o.Quest)"
        Set-Seen $row $buildOf["$($o.Kind):$($o.Npc)"] 1
    }
    foreach ($t in $facts.Turnins) {
        $row = New-RecordedRow $game 'turnin'; $row.Kind = $t.Kind; $row.Npc = "$($t.Npc)"; $row.Quest = "$($t.Quest)"
        Set-Seen $row $buildOf["$($t.Kind):$($t.Npc)"] 1
    }
    foreach ($s in $facts.Starts) {
        $row = New-RecordedRow $game 'start'; $row.Quest = "$($s.Quest)"; $row.Map = "$($s.Map)"; $row.X = $s.X; $row.Y = $s.Y
        $row.StartKind = "$($s.StartKind)"; $row.Item = "$($s.Item)"
        Set-Seen $row $s.Build 1
    }
    return $script:RecordedChanged
}

# Takes a source out of every row, and the rows nobody else saw. It lasts for the ledger as it stands:
# the source's file must be taken away as well (or skipped with -ForgetTag every run), or it is read again.
function Remove-RecordedTag($ledger, [string]$tag) {
    $removed = 0
    foreach ($key in @($ledger.Keys)) {
        $row = $ledger[$key]
        $src = ConvertFrom-RecordedSrc $row.Src
        if (-not $src.Contains($tag)) { continue }
        $src.Remove($tag)
        $removed++
        if ($src.Count -eq 0) { $ledger.Remove($key) } else { $row.Src = ConvertTo-RecordedSrc $src }
    }
    return $removed
}

# --- Places -------------------------------------------------------------------------------------

function Get-PlaceDistance([decimal]$x1, [decimal]$y1, [decimal]$x2, [decimal]$y2) {
    $dx = [double]($x1 - $x2); $dy = [double]($y1 - $y2)
    return [Math]::Sqrt($dx * $dx + $dy * $dy)
}
function Test-NearPlace([decimal]$x1, [decimal]$y1, [decimal]$x2, [decimal]$y2, [double]$radius = $RecordedPlaceRadius) {
    return (Get-PlaceDistance $x1 $y1 $x2 $y2) -le $radius
}

# The versions a game's TOCs name, as prefixes: the Interface line "120100, 120105" is 12.1.0 and 12.1.5,
# so retail's recordings of 12.1.x are read; "16001" is Forever's 1.60.
function Get-TocVersions([string]$AddonDir) {
    $prefixes = New-Object System.Collections.Generic.List[string]
    foreach ($toc in 'QuestCompletist.toc', 'QuestCompletist_Camelot.toc') {
        $path = Join-Path $AddonDir $toc
        if (-not (Test-Path $path)) { continue }
        foreach ($line in [IO.File]::ReadAllLines($path)) {
            if ($line -match '^\s*##\s*Interface:\s*(.+)$') {
                foreach ($number in ($Matches[1] -split '[,\s]+' | Where-Object { $_ })) {
                    $n = [int]$number
                    $prefix = "$([int][Math]::Floor($n / 10000)).$([int][Math]::Floor(($n % 10000) / 100))."
                    if (-not $prefixes.Contains($prefix)) { $prefixes.Add($prefix) }
                }
            }
        }
    }
    return $prefixes.ToArray()
}

# The places a giver was seen at on one map, from its spot rows: rows within the radius of a seed make
# one place, which is where the seed is. The sources of all the rows are the place's; whether it is
# trusted follows from them. What the maintainer's own files saw decides where a place is and which is
# seen most: a lone player's row never seeds a place or adds to its visits, though it may join one
# (it is then corroboration of a place that is already there). The giver's rows without a position
# (-1 -1) make one place. Returns places by descending visits, then map, X, Y.
function Get-RecordedPlaces($spotRows) {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($row in $spotRows) {
        $src = ConvertFrom-RecordedSrc $row.Src
        $total = 0; $own = 0
        foreach ($tag in $src.Keys) { $total += $src[$tag]; if ((Get-RecordedClass $tag) -eq 'own') { $own += $src[$tag] } }
        $hasOwn = @($src.Keys | Where-Object { (Get-RecordedClass $_) -eq 'own' }).Count -gt 0
        $items.Add([pscustomobject]@{ Row = $row; Src = $src; Total = $total; Own = $own; HasOwn = $hasOwn
            Weight = $(if ($hasOwn) { $own } else { $total })
            X = [decimal]::Parse($row.X, $script:Invariant); Y = [decimal]::Parse($row.Y, $script:Invariant); Map = [int]$row.Map; Taken = $false })
    }
    $ordered = @($items | Sort-Object @{ Expression = { if ($_.HasOwn) { 0 } else { 1 } } }, @{ Expression = { -$_.Weight } }, Map, X, Y)
    $places = New-Object System.Collections.Generic.List[object]
    foreach ($seed in $ordered) {
        if ($seed.Taken) { continue }
        $seed.Taken = $true
        $members = New-Object System.Collections.Generic.List[object]
        $members.Add($seed)
        foreach ($member in $ordered) {
            if ($member.Taken) { continue }
            if ($member.Map -ne $seed.Map) { continue }
            if (($seed.X -lt 0) -ne ($member.X -lt 0)) { continue }
            if ($seed.X -ge 0 -and -not (Test-NearPlace $seed.X $seed.Y $member.X $member.Y)) { continue }
            $member.Taken = $true
            $members.Add($member)
        }
        $place = [pscustomobject]@{ Map = $seed.Map; X = $seed.X; Y = $seed.Y; Visits = 0; Src = [ordered]@{}; Classes = (New-ClassSet) }
        $anyOwn = @($members | Where-Object { $_.HasOwn }).Count -gt 0
        foreach ($member in $members) {
            $place.Visits += $(if ($anyOwn) { $member.Own } else { $member.Total })
            foreach ($tag in $member.Src.Keys) {
                $place.Src[$tag] = [int]$place.Src[$tag] + $member.Src[$tag]
                [void]$place.Classes.Add((Get-RecordedClass $tag))
            }
        }
        $place | Add-Member -NotePropertyName Trusted -NotePropertyValue ($place.Classes.Contains('own') -or $place.Classes.Count -ge 2)
        $places.Add($place)
    }
    return , @($places | Sort-Object @{ Expression = { -$_.Visits } }, Map, X, Y)
}

# --- The model: what the ledger says, once trust is applied -------------------------------------

# A name as the pins keep it, for comparing: colour codes and a trailing <title> taken off.
function ConvertTo-PlainPinName([string]$name) {
    if (-not $name) { return '' }
    $plain = [regex]::Replace($name, '\|c[0-9A-Fa-f]{8}|\|r', '')
    $plain = [regex]::Replace($plain, '\s*<[^>]*>\s*$', '')
    return $plain.Trim()
}

# The ledger's rows of one game as givers (with their places and the name the trusted rows agree on),
# the quests each trusted giver offers and takes in, and the rows still waiting for a second source.
# A giver whose trusted rows give two names has none (NameConflicts says which): a wrong name is worse
# than none.
function Get-RecordedModel($ledger, [string]$game) {
    $model = [pscustomobject]@{
        Game = $game
        Givers = @{}
        Offers = @{}
        Turnins = @{}
        Awaiting = (New-Object System.Collections.Generic.List[object])
        NameConflicts = (New-Object System.Collections.Generic.List[object])
    }
    $spotsOf = @{}
    $namesOf = @{}
    foreach ($row in $ledger.Values) {
        if ($row.Game -ne $game) { continue }
        $trusted = Test-RecordedTrusted $row
        $key = "$($row.Kind):$($row.Npc)"
        switch ($row.Role) {
            'giver' {
                if (-not $namesOf.ContainsKey($key)) { $namesOf[$key] = New-Object System.Collections.Generic.List[object] }
                $namesOf[$key].Add($row)
            }
            'spot' {
                if (-not $spotsOf.ContainsKey($key)) { $spotsOf[$key] = New-Object System.Collections.Generic.List[object] }
                $spotsOf[$key].Add($row)
            }
            'offer' {
                if ($trusted) {
                    $quest = [int]$row.Quest
                    if (-not $model.Offers.ContainsKey($quest)) { $model.Offers[$quest] = New-Object System.Collections.Generic.List[string] }
                    $model.Offers[$quest].Add($key)
                } else { $model.Awaiting.Add($row) }
            }
            'turnin' {
                if ($trusted) {
                    $quest = [int]$row.Quest
                    if (-not $model.Turnins.ContainsKey($quest)) { $model.Turnins[$quest] = New-Object System.Collections.Generic.List[string] }
                    $model.Turnins[$quest].Add($key)
                } else { $model.Awaiting.Add($row) }
            }
            default { if (-not $trusted) { $model.Awaiting.Add($row) } }
        }
    }
    $keys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($key in $spotsOf.Keys) { [void]$keys.Add($key) }
    foreach ($key in $namesOf.Keys) { [void]$keys.Add($key) }
    foreach ($key in ($keys | Sort-Object { $_ } -CaseSensitive)) {
        $kind, $npc = $key.Split(':')
        $giver = [pscustomobject]@{ Key = $key; Kind = $kind; Npc = [int]$npc; Name = ''; Maps = @{}; Places = (New-Object System.Collections.Generic.List[object]) }
        if ($namesOf.ContainsKey($key)) {
            $trustedNames = @($namesOf[$key] | Where-Object { Test-RecordedTrusted $_ } | ForEach-Object { $_.Name } | Sort-Object { $_ } -Unique -CaseSensitive)
            if ($trustedNames.Count -eq 1) { $giver.Name = $trustedNames[0] }
            elseif ($trustedNames.Count -gt 1) { $model.NameConflicts.Add([pscustomobject]@{ Giver = $key; Names = ($trustedNames -join ' / ') }) }
        }
        if ($spotsOf.ContainsKey($key)) {
            foreach ($group in ($spotsOf[$key] | Group-Object { $_.Map })) {
                $places = Get-RecordedPlaces $group.Group
                $giver.Maps[[int]$group.Name] = $places
                foreach ($place in $places) { $giver.Places.Add($place) }
            }
        }
        $model.Givers[$key] = $giver
    }
    return $model
}

# The trusted place of a giver on a map that is within the radius of a point, or the one with no
# position when $withoutPosition. $null when there is none.
function Find-GiverPlace($giver, [int]$map, [decimal]$x, [decimal]$y, [bool]$withoutPosition = $false) {
    if (-not $giver.Maps.ContainsKey($map)) { return $null }
    foreach ($place in $giver.Maps[$map]) {
        if (-not $place.Trusted) { continue }
        if ($place.X -lt 0) {
            if ($withoutPosition) { return $place }
            continue
        }
        if (-not $withoutPosition -and (Test-NearPlace $place.X $place.Y $x $y)) { return $place }
    }
    return $null
}

# --- What changes -------------------------------------------------------------------------------

function Format-PinNumber($value) {
    return ([decimal]$value).ToString('0.############################', $script:Invariant)
}
# A pin's place, the way pin-giver-decisions.csv keys it: quest|map|x|y.
function Get-DecisionKey([int]$quest, $pin) {
    return "$quest|$($pin.map)|$(Format-PinNumber $pin.x)|$(Format-PinNumber $pin.y)"
}
# Whether a case was looked at and stays: the quest on that pin, or the quest wherever (a row with no
# map and place).
function Test-Kept($decisions, [int]$quest, $pin) {
    if ($decisions.Contains("$quest|*")) { return $true }
    return $null -ne $pin -and $decisions.Contains((Get-DecisionKey $quest $pin))
}

# Reads docs\plans\recorded-giver-decisions.csv (Quest, Map, X, Y, Decision, Reason): a case that was
# looked at and stays as it is. KEEP is the only decision. A row with a map and place keeps that pin as it
# is (or the add at that place); a row with only a quest keeps the quest from getting a pin from here.
# Returns the set of keys.
function Read-RecordedDecisions([string]$Path) {
    $keys = New-Object System.Collections.Generic.HashSet[string]
    if (-not (Test-Path $Path)) { return , $keys }
    foreach ($row in (Import-Csv $Path -Encoding UTF8)) {
        if ($row.Decision -ne 'KEEP') { throw "$(Split-Path -Leaf $Path): '$($row.Decision)' isn't a decision this tool knows (KEEP), for quest $($row.Quest)" }
        if ($row.Map -eq '' -and $row.X -eq '' -and $row.Y -eq '') { [void]$keys.Add("$($row.Quest)|*") }
        else { [void]$keys.Add("$($row.Quest)|$($row.Map)|$(Format-PinNumber $row.X)|$(Format-PinNumber $row.Y)") }
    }
    return , $keys
}
function Describe-Pin($pin) {
    return "map $($pin.map) at $(Format-PinNumber $pin.x),$(Format-PinNumber $pin.y)"
}

<#
Works out what the ledger changes in the pins and what it only has to say. Nothing is changed here.
    Fills       a pin with no NPC ID, one of whose quests a trusted creature offered within the radius of it
    Adds        a quest with no pin: the pin it joins or the pin it gets, at a trusted giver's most seen place
    Review      the disagreements and the cases that need a person
-IsPinnable is a script block, given a quest's ID, that says why a quest may not get a pin ($null when
it may). -Pins is the pins as Read-PinData gives them. -Decisions holds the keys of cases that were looked
at and stay; -ClearedPins the places (map|x|y) of pins whose ID was taken off by hand, which a fill
leaves alone.
#>
function Get-RecordedPlan($model, $pins, [scriptblock]$IsPinnable, $decisions, $clearedPins, [int]$MaxPlaces = 6) {
    $plan = [pscustomobject]@{
        Fills = (New-Object System.Collections.Generic.List[object]); Adds = (New-Object System.Collections.Generic.List[object])
        Review = (New-Object System.Collections.Generic.List[object]); Skipped = [ordered]@{}
    }
    $review = $plan.Review
    $skipped = $plan.Skipped
    $addReview = { param([string]$kind, $quest, [string]$where, [string]$detail) $review.Add([pscustomobject]@{ Kind = $kind; Quest = $quest; Where = $where; Detail = $detail }) }
    $skip = { param([string]$why) $skipped[$why] = 1 + [int]$skipped[$why] }
    $conflicted = @{}
    foreach ($c in $model.NameConflicts) { $conflicted[$c.Giver] = $c.Names }
    $nearMiss = $RecordedPlaceRadius * 2

    $pinsOfQuest = @{}
    $npcPins = @{}
    $namePins = @{}
    foreach ($pin in $pins) {
        foreach ($quest in $pin.quests) {
            if (-not $pinsOfQuest.ContainsKey([int]$quest)) { $pinsOfQuest[[int]$quest] = New-Object System.Collections.Generic.List[object] }
            $pinsOfQuest[[int]$quest].Add($pin)
        }
        if ($pin.npc) {
            $key = "$($pin.map)|$($pin.npc)"
            if (-not $npcPins.ContainsKey($key)) { $npcPins[$key] = New-Object System.Collections.Generic.List[object] }
            $npcPins[$key].Add($pin)
        } elseif ($null -ne $pin.name) {
            $key = "$($pin.map)|$($pin.name)"
            if (-not $namePins.ContainsKey($key)) { $namePins[$key] = New-Object System.Collections.Generic.List[object] }
            $namePins[$key].Add($pin)
        }
    }
    $offerers = {
        param([int]$quest)
        if ($model.Offers.ContainsKey($quest)) { return , @($model.Offers[$quest] | Sort-Object { $_ } -Unique -CaseSensitive) }
        return , @()
    }
    # A pin of the same kind close by, but not on the same spot: the pipeline joins such pins at its
    # next run, and the quests of one of the two move. That is for a person to say.
    $twinOf = {
        param($index, [string]$key, $pin)
        if (-not $index.ContainsKey($key)) { return $null }
        return @($index[$key] | Where-Object { $d = Get-PlaceDistance $_.x $_.y $pin.x $pin.y; $d -gt 0.01 -and $d -le $RecordedPlaceRadius }) | Select-Object -First 1
    }

    # (a) A pin with no NPC ID.
    foreach ($pin in $pins) {
        if ($pin.npc) { continue }
        $found = @{}
        $placeOf = @{}
        $positionless = New-Object System.Collections.Generic.List[string]
        $near = New-Object System.Collections.Generic.List[string]
        foreach ($quest in $pin.quests) {
            $q = [int]$quest
            $onMap = 0
            if ($pinsOfQuest.ContainsKey($q)) { $onMap = @($pinsOfQuest[$q] | Where-Object { $_.map -eq $pin.map }).Count }
            foreach ($giverKey in (& $offerers $q)) {
                $giver = $model.Givers[$giverKey]
                if (-not $giver) { continue }
                $place = Find-GiverPlace $giver ([int]$pin.map) $pin.x $pin.y
                if ($place) {
                    if (-not $found.ContainsKey($giverKey)) { $found[$giverKey] = New-Object System.Collections.Generic.List[int]; $placeOf[$giverKey] = $place }
                    $found[$giverKey].Add($q)
                } elseif ($onMap -eq 1 -and (Find-GiverPlace $giver ([int]$pin.map) 0 0 $true) -and -not $positionless.Contains($giverKey)) {
                    $positionless.Add($giverKey)
                } elseif ($giver.Maps.ContainsKey([int]$pin.map)) {
                    foreach ($p in $giver.Maps[[int]$pin.map]) {
                        if ($p.Trusted -and $p.X -ge 0 -and (Get-PlaceDistance $p.X $p.Y $pin.x $pin.y) -le $nearMiss -and -not $near.Contains($giverKey)) { $near.Add($giverKey) }
                    }
                }
            }
        }
        $where = Describe-Pin $pin
        $anchor = [int]$pin.quests[0]
        $kept = @($pin.quests | Where-Object { Test-Kept $decisions ([int]$_) $pin }).Count -gt 0
        if ($found.Count -eq 0) {
            if (-not $kept -and $positionless.Count -gt 0) {
                & $addReview 'recorded without a position' $anchor $where "$($positionless -join ', ') offers a quest of this pin, its only pin on the map, but the game gave no position"
                & $skip 'recorded without a position'
            } elseif (-not $kept -and $near.Count -gt 0) {
                & $addReview 'giver stood 1.5 to 3 points from a pin' $anchor $where "$($near -join ', ') offers a quest of this pin, trusted, but stood further than the radius"
                & $skip 'a giver 1.5 to 3 points away'
            }
            continue
        }
        if ($kept) { & $skip 'kept by a decision'; continue }
        if ($clearedPins.Contains("$($pin.map)|$(Format-PinNumber $pin.x)|$(Format-PinNumber $pin.y)")) {
            & $addReview 'pin whose ID was taken off by hand' $anchor $where ('recorded: ' + (($found.Keys | Sort-Object { $_ } -CaseSensitive) -join ', '))
            & $skip 'its ID was taken off by hand'
            continue
        }
        if ($found.Count -gt 1) {
            # Phased or per-faction copies of one character bear one name: take the one that offers most of the pin's quests.
            $names = @($found.Keys | ForEach-Object { $model.Givers[$_].Name } | Sort-Object { $_ } -Unique -CaseSensitive)
            if ($names.Count -eq 1 -and $names[0]) {
                $best = @($found.Keys | Sort-Object @{ Expression = { -$found[$_].Count } }, @{ Expression = { -$placeOf[$_].Visits } }, @{ Expression = { $model.Givers[$_].Npc } })
                & $addReview 'same name under another ID' $anchor $where "recorded: $($best -join ', ') bear one name; the first is taken"
                $keep = $best[0]
                foreach ($key in @($found.Keys)) { if ($key -ne $keep) { $found.Remove($key) } }
            } else {
                & $addReview 'two givers at one pin' $anchor $where ('recorded: ' + (($found.Keys | Sort-Object { $_ } -CaseSensitive) -join ', '))
                & $skip 'two givers at one pin'
                continue
            }
        }
        $giverKey = @($found.Keys)[0]
        $giver = $model.Givers[$giverKey]
        if ($giver.Kind -eq 'Vehicle') { & $skip 'a vehicle'; continue }
        if (-not $giver.Name) {
            if ($conflicted.ContainsKey($giverKey)) {
                & $addReview 'trusted sources disagree on the giver''s name' $anchor $where "$giverKey`: $($conflicted[$giverKey])"
                & $skip 'the sources disagree on the giver''s name'
            } else {
                & $addReview 'giver without a trusted English name' $anchor $where $giverKey
                & $skip 'no English name for the giver'
            }
            continue
        }
        if ($null -ne $pin.name -and (ConvertTo-PlainPinName $pin.name) -cne (ConvertTo-PlainPinName $giver.Name)) {
            & $addReview 'pin name differs from the recorded giver' $anchor $where "pin: $($pin.name); recorded ${giverKey}: $($giver.Name)"
            & $skip 'the pin names someone else'
            continue
        }
        # Every other quest on the pin that a trusted giver offered here was offered by this one.
        $conflict = $null
        foreach ($quest in $pin.quests) {
            if ($found[$giverKey].Contains([int]$quest)) { continue }
            foreach ($other in (& $offerers ([int]$quest))) {
                if ($other -eq $giverKey) { continue }
                $og = $model.Givers[$other]
                if ($og -and $og.Name -cne $giver.Name -and (Find-GiverPlace $og ([int]$pin.map) $pin.x $pin.y)) { $conflict = "quest $quest is offered by $other" }
            }
        }
        if ($conflict) {
            & $addReview 'quests of one pin offered by two givers' $anchor $where "$giverKey and $conflict"
            & $skip 'quests offered by two givers'
            continue
        }
        # The recorder knows what a giver offered and took in, and where it stood, but not which place went
        # with which: a quest it both offered and took in, with a place far from the pin, may be the hand-in.
        $turnsIn = @($found[$giverKey] | Where-Object { $model.Turnins.ContainsKey($_) -and $model.Turnins[$_].Contains($giverKey) })
        if ($turnsIn.Count -gt 0) {
            $elsewhere = @($giver.Places | Where-Object { $_.Trusted -and $_.X -ge 0 -and ($_.Map -ne [int]$pin.map -or (Get-PlaceDistance $_.X $_.Y $pin.x $pin.y) -gt $nearMiss) })
            if ($elsewhere.Count -gt 0) {
                & $addReview 'offered and taken in at different places' $anchor $where "$giverKey offers and takes in quest $($turnsIn[0]) and stood both here and elsewhere"
                & $skip 'offered and taken in at different places'
                continue
            }
        }
        if ($giver.Kind -eq 'GameObject') {
            if ($null -eq $pin.name) {
                $twin = & $twinOf $namePins "$($pin.map)|$($giver.Name)" $pin
                if ($twin) {
                    & $addReview 'a fill would merge two pins of one name' $anchor $where "$giverKey '$($giver.Name)' already has a pin at $(Describe-Pin $twin)"
                    & $skip 'would merge with a pin of the same name'
                    continue
                }
                $mergeKey = "$($pin.map)|$($giver.Name)"
                if (-not $namePins.ContainsKey($mergeKey)) { $namePins[$mergeKey] = New-Object System.Collections.Generic.List[object] }
                $namePins[$mergeKey].Add($pin)
                $plan.Fills.Add([pscustomobject]@{ Pin = $pin; GiverKey = $giverKey; Npc = 0; Name = $giver.Name; Quests = $found[$giverKey].ToArray(); Where = $where })
            } else { & $skip 'an object that the pin already names' }
            continue
        }
        $mergeKey = "$($pin.map)|$($giver.Npc)"
        $twin = & $twinOf $npcPins $mergeKey $pin
        if ($twin) {
            & $addReview 'a fill would merge two pins of one NPC' $anchor $where "$giverKey '$($giver.Name)' already has a pin at $(Describe-Pin $twin)"
            & $skip 'would merge with a pin of the same NPC'
            continue
        }
        if (-not $npcPins.ContainsKey($mergeKey)) { $npcPins[$mergeKey] = New-Object System.Collections.Generic.List[object] }
        $npcPins[$mergeKey].Add($pin)
        $plan.Fills.Add([pscustomobject]@{ Pin = $pin; GiverKey = $giverKey; Npc = $giver.Npc; Name = $giver.Name; Quests = $found[$giverKey].ToArray(); Where = $where })
    }

    # (b) A quest with no pin at all.
    foreach ($quest in ($model.Offers.Keys | Sort-Object)) {
        if ($pinsOfQuest.ContainsKey($quest)) { continue }
        if ($decisions.Contains("$quest|*")) { & $skip 'no pin: kept by a decision'; continue }
        $why = & $IsPinnable $quest
        if ($why) { & $skip "no pin: $why"; continue }
        $options = New-Object System.Collections.Generic.List[object]
        foreach ($giverKey in (& $offerers $quest)) {
            $giver = $model.Givers[$giverKey]
            if (-not $giver) { continue }
            if ($giver.Kind -eq 'Vehicle') { & $skip 'no pin: a vehicle'; continue }
            $places = @($giver.Places | Where-Object { $_.Trusted -and $_.X -ge 0 } | Sort-Object @{ Expression = { -$_.Visits } }, Map, X, Y)
            if ($places.Count -eq 0) { & $skip 'no pin: the giver has no trusted place with a position'; continue }
            $options.Add([pscustomobject]@{ Giver = $giver; Place = $places[0]; Others = $places.Count - 1 })
        }
        $ordered = @($options | Sort-Object @{ Expression = { -$_.Place.Visits } }, @{ Expression = { $_.Giver.Key } })
        # Copies of one character (the same name, and places within the radius) get one pin.
        $distinct = New-Object System.Collections.Generic.List[object]
        foreach ($option in $ordered) {
            $same = $null
            if ($option.Giver.Name) {
                foreach ($d in $distinct) {
                    if ($d.Giver.Name -ceq $option.Giver.Name -and $d.Place.Map -eq $option.Place.Map -and (Test-NearPlace $d.Place.X $d.Place.Y $option.Place.X $option.Place.Y)) { $same = $d; break }
                }
            }
            if ($same) {
                & $addReview 'same name under another ID' $quest "map $($option.Place.Map) at $(Format-PinNumber $option.Place.X),$(Format-PinNumber $option.Place.Y)" "recorded: $($same.Giver.Key) and $($option.Giver.Key) bear one name; the first is taken"
            } else { $distinct.Add($option) }
        }
        $ordered = $distinct.ToArray()
        $kept = New-Object System.Collections.Generic.List[object]
        foreach ($option in $ordered) {
            $key = "$quest|$($option.Place.Map)|$(Format-PinNumber $option.Place.X)|$(Format-PinNumber $option.Place.Y)"
            if ($decisions.Contains($key)) { & $skip 'no pin: kept by a decision' } else { $kept.Add($option) }
        }
        $ordered = $kept.ToArray()
        if ($ordered.Count -gt $MaxPlaces) {
            & $addReview 'more than six places' $quest '' (($ordered | Select-Object -Skip $MaxPlaces | ForEach-Object { $_.Giver.Key }) -join ', ')
            $ordered = @($ordered | Select-Object -First $MaxPlaces)
        }
        foreach ($option in $ordered) {
            $plan.Adds.Add([pscustomobject]@{ Quest = $quest; Giver = $option.Giver; Place = $option.Place; Others = $option.Others })
        }
    }
    return $plan
}

# --- Changing the pins --------------------------------------------------------------------------

# Pins are objects, and every object hashes alike for a HashSet, so the sets of pins compare by
# reference and hash by identity.
if (-not ('RecordedGiversReferenceComparer' -as [type])) {
    Add-Type -TypeDefinition @"
using System.Collections.Generic;
using System.Runtime.CompilerServices;
public class RecordedGiversReferenceComparer : IEqualityComparer<object> {
    public static int Marker = 1;
    bool IEqualityComparer<object>.Equals(object a, object b) { return object.ReferenceEquals(a, b); }
    int IEqualityComparer<object>.GetHashCode(object o) { return RuntimeHelpers.GetHashCode(o); }
}
"@
}
function New-PinSet() { return , (New-Object 'System.Collections.Generic.HashSet[object]' (New-Object RecordedGiversReferenceComparer)) }

# What a pin was, to check afterwards that it still is.
function Get-PinSnapshot($pins) {
    $snapshot = New-Object System.Collections.Generic.List[object]
    foreach ($pin in $pins) {
        $snapshot.Add([pscustomobject]@{
            Pin = $pin; Map = $pin.map; X = Format-PinNumber $pin.x; Y = Format-PinNumber $pin.y; Icon = $pin.icon
            Npc = [int]$pin.npc; Name = $pin.name; Note = $pin.note; Quests = @($pin.quests | ForEach-Object { [int]$_ })
        })
    }
    return , $snapshot
}

# The pipeline's order within a map (Assemble-PinDB.ps1): the lowest quest ID on the pin, then x, y and the NPC.
function Sort-PinBlock($pins, [int]$map) {
    $first = -1; $last = -1
    for ($i = 0; $i -lt $pins.Count; $i++) {
        if ([int]$pins[$i].map -eq $map) { if ($first -lt 0) { $first = $i }; $last = $i }
    }
    if ($first -lt 0) { return }
    $block = @(for ($i = $first; $i -le $last; $i++) { [pscustomobject]@{ Pin = $pins[$i]; At = $i } })
    $sorted = @($block | Sort-Object { ($_.Pin.quests | Measure-Object -Minimum).Minimum }, { [double]$_.Pin.x }, { [double]$_.Pin.y }, { [int]$_.Pin.npc }, At)
    for ($i = 0; $i -lt $sorted.Count; $i++) { $pins[$first + $i] = $sorted[$i].Pin }
}

<#
Carries out a plan on the pins (the list Read-PinData returned, which is added to and changed) and
returns what was done. A fill gives a pin the NPC ID and name; an add puts a quest on the pin of its
giver within the radius of the place, or gives it a pin there (with no NPC and no name when the giver has
no trusted name: a later run fills them in once there is one). Where a new pin goes is -InsertAfter, a
script block given the pins and the new pin, returning the index to insert at; the maps that changed are
put back in the pipeline's order afterwards. -IconFor is given the quests of a new pin, once they are all on it.
#>
function Invoke-RecordedPlan($plan, [System.Collections.Generic.List[object]]$pins, [scriptblock]$InsertAfter, [scriptblock]$IconFor) {
    $done = [pscustomobject]@{ Filled = 0; Named = 0; Joined = 0; Created = 0; Notes = (New-Object System.Collections.Generic.List[string]) }
    $touched = New-Object System.Collections.Generic.HashSet[int]
    $byMap = @{}
    foreach ($pin in $pins) {
        $m = [int]$pin.map
        if (-not $byMap.ContainsKey($m)) { $byMap[$m] = New-Object System.Collections.Generic.List[object] }
        $byMap[$m].Add($pin)
    }
    foreach ($fill in $plan.Fills) {
        $pin = $fill.Pin
        if ($fill.Npc) { Set-RecordField $pin 'npc' $fill.Npc; $done.Filled++ }
        if ($null -eq $pin.name) { Set-RecordField $pin 'name' $fill.Name; $done.Named++ }
        [void]$touched.Add([int]$pin.map)
    }
    $created = New-Object System.Collections.Generic.List[object]
    $nameless = New-Object System.Collections.Generic.List[object]
    foreach ($add in $plan.Adds) {
        $giver = $add.Giver
        $place = $add.Place
        $quest = $add.Quest
        $creature = $giver.Kind -eq 'Creature'
        $named = [bool]$giver.Name
        $same = $null
        if (-not $named) {
            foreach ($entry in $nameless) {
                if ($entry.Giver -ceq $giver.Key -and [int]$entry.Pin.map -eq [int]$place.Map -and (Test-NearPlace $entry.Pin.x $entry.Pin.y $place.X $place.Y)) { $same = $entry.Pin; break }
            }
        } elseif ($byMap.ContainsKey([int]$place.Map)) {
            foreach ($candidate in $byMap[[int]$place.Map]) {
                if (-not (Test-NearPlace $candidate.x $candidate.y $place.X $place.Y)) { continue }
                if ($creature) {
                    if ([int]$candidate.npc -ne $giver.Npc -and -not ([int]$candidate.npc -eq 0 -and $null -ne $candidate.name -and (ConvertTo-PlainPinName $candidate.name) -ceq (ConvertTo-PlainPinName $giver.Name))) { continue }
                } elseif ([int]$candidate.npc -ne 0 -or $null -eq $candidate.name -or $candidate.name -cne $giver.Name) { continue }
                $same = $candidate
                break
            }
        }
        if ($same) {
            if (@($same.quests) -notcontains $quest) {
                Set-RecordField $same 'quests' ([int[]](@($same.quests) + $quest))
                $done.Joined++
                [void]$touched.Add([int]$same.map)
            }
            continue
        }
        $pin = [pscustomobject][ordered]@{
            map = [int]$place.Map; icon = 1; npc = $(if ($creature -and $named) { [int]$giver.Npc } else { 0 }); name = $(if ($named) { $giver.Name } else { $null })
            x = [decimal]$place.X; y = [decimal]$place.Y; quests = [int[]]@($quest); note = $null
        }
        $pins.Insert((& $InsertAfter $pins $pin), $pin)
        $m = [int]$pin.map
        if (-not $byMap.ContainsKey($m)) { $byMap[$m] = New-Object System.Collections.Generic.List[object] }
        $byMap[$m].Add($pin)
        $created.Add($pin)
        if (-not $named) { $nameless.Add([pscustomobject]@{ Giver = $giver.Key; Pin = $pin }) }
        [void]$touched.Add($m)
        $done.Created++
    }
    foreach ($pin in $created) { $pin.icon = & $IconFor @($pin.quests) }
    foreach ($m in $touched) { Sort-PinBlock $pins $m }
    return $done
}

# The change must be only what the tool means to make, or nothing is saved: every old pin is where
# it was, with the icon and note it had, its NPC and name only filled where they were empty, and every
# quest it had; the pins that are new are the only other difference. Returns the problems, if any.
function Test-RecordedChangeSafe($snapshot, $pins) {
    $problems = New-Object System.Collections.Generic.List[string]
    $old = New-PinSet
    foreach ($was in $snapshot) {
        [void]$old.Add($was.Pin)
        $pin = $was.Pin
        $at = "map $($was.Map) at $($was.X),$($was.Y)"
        if ($pin.map -ne $was.Map -or (Format-PinNumber $pin.x) -ne $was.X -or (Format-PinNumber $pin.y) -ne $was.Y) { $problems.Add("$at moved") }
        if ($pin.icon -ne $was.Icon) { $problems.Add("$at changed its icon") }
        if ($pin.note -cne $was.Note) { $problems.Add("$at changed its note") }
        if ($was.Npc -ne 0 -and [int]$pin.npc -ne $was.Npc) { $problems.Add("$at changed its NPC") }
        if ($null -ne $was.Name -and $pin.name -cne $was.Name) { $problems.Add("$at changed its name") }
        if ($was.Npc -eq 0 -and [int]$pin.npc -ne 0 -and -not $pin.name) { $problems.Add("$at was given an NPC and no name") }
        $now = @($pin.quests | ForEach-Object { [int]$_ })
        foreach ($quest in $was.Quests) { if ($now -notcontains $quest) { $problems.Add("$at lost quest $quest") } }
    }
    $seen = New-PinSet
    foreach ($pin in $pins) {
        [void]$seen.Add($pin)
        if (-not $old.Contains($pin)) {
            if (@($pin.quests).Count -eq 0) { $problems.Add("a new pin has no quest") }
            if ([int]$pin.npc -ne 0 -and -not $pin.name) { $problems.Add("a new pin has an NPC and no name") }
        }
    }
    foreach ($was in $snapshot) { if (-not $seen.Contains($was.Pin)) { $problems.Add("map $($was.Map) at $($was.X),$($was.Y) is gone") } }
    return $problems.ToArray()
}

# --- What only needs a person -------------------------------------------------------------------

# The disagreements between the ledger and the pins as they stand, one item each:
#   pin names another NPC than the recorded giver  a trusted creature stands at the pin and offers its quest; the pin's NPC isn't one that does
#   same name under another ID                     the same, but the recorded giver bears the pin's name (an alias, or two spawns)
#   pin name differs from the name recorded for its ID
#   quest offered away from its pins               a trusted giver offers a quest 3 points or more from every pin it has on that map, or on another map
#   pin at the hand-in                             a pin by a trusted turn-in of one of its quests, with every recorded offer of the quest 3 or more points away
#   offered but flagged unavailable
function Get-RecordedReview($model, $pins, $decisions, $unavailable) {
    $items = New-Object System.Collections.Generic.List[object]
    $far = 3.0
    $add = { param([string]$kind, $quest, [string]$where, [string]$detail) $items.Add([pscustomobject]@{ Kind = $kind; Quest = $quest; Where = $where; Detail = $detail }) }
    $pinsOfQuest = @{}
    foreach ($pin in $pins) {
        foreach ($quest in $pin.quests) {
            if (-not $pinsOfQuest.ContainsKey([int]$quest)) { $pinsOfQuest[[int]$quest] = New-Object System.Collections.Generic.List[object] }
            $pinsOfQuest[[int]$quest].Add($pin)
        }
    }
    $offerers = { param([int]$quest) if ($model.Offers.ContainsKey($quest)) { return , @($model.Offers[$quest] | Sort-Object { $_ } -Unique -CaseSensitive) }; return , @() }
    $turners = { param([int]$quest) if ($model.Turnins.ContainsKey($quest)) { return , @($model.Turnins[$quest] | Sort-Object { $_ } -Unique -CaseSensitive) }; return , @() }
    # The nearest a giver's trusted places on a map come to a point; $null when it has none there.
    $nearest = {
        param($giver, [int]$map, [decimal]$x, [decimal]$y)
        $best = $null
        if ($giver.Maps.ContainsKey($map)) {
            foreach ($place in $giver.Maps[$map]) {
                if (-not $place.Trusted -or $place.X -lt 0) { continue }
                $d = Get-PlaceDistance $place.X $place.Y $x $y
                if ($null -eq $best -or $d -lt $best) { $best = $d }
            }
        }
        return $best
    }

    foreach ($pin in $pins) {
        $where = Describe-Pin $pin
        foreach ($quest in $pin.quests) {
            $q = [int]$quest
            if (Test-Kept $decisions $q $pin) { continue }
            if ($pin.npc) {
                $own = "Creature:$($pin.npc)"
                $here = @((& $offerers $q) | Where-Object { $model.Givers[$_] -and (Find-GiverPlace $model.Givers[$_] ([int]$pin.map) $pin.x $pin.y) })
                if ($here.Count -gt 0 -and $here -notcontains $own) {
                    $recorded = $model.Givers[$here[0]]
                    $kind = 'pin names another NPC than the recorded giver'
                    if ($recorded.Name -and $null -ne $pin.name -and (ConvertTo-PlainPinName $pin.name) -ceq (ConvertTo-PlainPinName $recorded.Name)) { $kind = 'same name under another ID' }
                    & $add $kind $q $where "pin: $($pin.npc) '$($pin.name)'; recorded: $($recorded.Key) '$($recorded.Name)'"
                }
            }
            # A hand-in: a turn-in stands at the pin and no offer of the quest does.
            $located = @((& $offerers $q) | Where-Object { $model.Givers[$_] -and @($model.Givers[$_].Places | Where-Object { $_.Trusted -and $_.X -ge 0 }).Count -gt 0 })
            if ($located.Count -gt 0) {
                $atTurnin = @((& $turners $q) | Where-Object { $model.Givers[$_] -and (Find-GiverPlace $model.Givers[$_] ([int]$pin.map) $pin.x $pin.y) })
                if ($atTurnin.Count -gt 0) {
                    $closest = $null
                    foreach ($key in $located) {
                        $d = & $nearest $model.Givers[$key] ([int]$pin.map) $pin.x $pin.y
                        if ($null -ne $d -and ($null -eq $closest -or $d -lt $closest)) { $closest = $d }
                    }
                    if ($null -eq $closest -or $closest -ge $far) {
                        & $add 'pin at the hand-in' $q $where "a recorded turn-in by $($atTurnin[0]) stands here and every recorded offer is $(if ($null -ne $closest) { "$([Math]::Round($closest, 1)) points or more away" } else { 'on another map' }): $($located -join ', ')"
                    }
                }
            }
        }
        if ($pin.npc -and $null -ne $pin.name) {
            $giver = $model.Givers["Creature:$($pin.npc)"]
            if ($giver -and $giver.Name -and (ConvertTo-PlainPinName $pin.name) -cne (ConvertTo-PlainPinName $giver.Name) -and -not (Test-Kept $decisions ([int]$pin.quests[0]) $pin)) {
                & $add 'pin name differs from the name recorded for its ID' $pin.quests[0] $where "pin: '$($pin.name)'; recorded: '$($giver.Name)'"
            }
        }
    }

    foreach ($quest in ($model.Offers.Keys | Sort-Object)) {
        if ($unavailable.Contains($quest)) {
            & $add 'offered but flagged unavailable' $quest '' ((& $offerers $quest) -join ', ')
        }
        if (-not $pinsOfQuest.ContainsKey($quest)) { continue }
        foreach ($key in (& $offerers $quest)) {
            $giver = $model.Givers[$key]
            if (-not $giver) { continue }
            # The ledger knows what a giver offered, and where it stood, but not which place went with which
            # quest: it is away only if none of its places is near a pin of the quest.
            $places = @($giver.Places | Where-Object { $_.Trusted -and $_.X -ge 0 })
            if ($places.Count -eq 0) { continue }
            $near = $false
            foreach ($place in $places) {
                foreach ($pin in $pinsOfQuest[$quest]) {
                    if ([int]$pin.map -eq $place.Map -and (Get-PlaceDistance $place.X $place.Y $pin.x $pin.y) -lt $far) { $near = $true; break }
                }
                if ($near) { break }
            }
            if (-not $near -and -not $decisions.Contains("$quest|*")) {
                $pinText = ($pinsOfQuest[$quest] | ForEach-Object { Describe-Pin $_ }) -join '; '
                $placeText = ($places | ForEach-Object { "map $($_.Map) at $(Format-PinNumber $_.X),$(Format-PinNumber $_.Y)" }) -join '; '
                & $add 'quest offered away from its pins' $quest $placeText "$key '$($giver.Name)' offers it; its pins: $pinText"
            }
        }
    }
    return , $items
}
