<#
Shared by Apply-QuestScaling.ps1 and Test-QuestScaling.ps1, dot-sourced:
	. "$PSScriptRoot\QuestScaling.ps1"

Where a retail quest's scaling ceiling comes from, and the level the addon shows a quest at.

A retail quest scales with the character between two levels its ContentTuningID sets. The game's
level for it (GetQuestDifficultyLevel) is the character's level, raised to the quest's minimum and
held down at the tuning's maximum: TrinityCore's Player::GetQuestLevel says so, and at the level cap
the game's answer is the maximum itself. The game calls a quest trivial (grey) when that level is
above 0 and below the character's level less UnitQuestTrivialLevelRange, which is the addon's
low-level rule applied to the scaled level.

TrinityCore takes the tuning through the character's Chromie Time options (CTROptions' ConditionalFlags
pick a ConditionalContentTuning redirect), so a character in Chromie Time may scale to another level;
the ceilings here are those of the probe's character, and that redirect is not modelled. The server
sends each character its own redirect bits, which no addon call reads (docs\plans\quest-scaling-redirects.md):
in the game, one level 90 character got 90 for 11 "Riverpaw Gnoll Bounty" in Nazmir and 30 in Elwynn
Forest. So each tuning a redirect can move also gets samples, quests the probe loaded on it, for the addon
to read the game's own level from (Get-TuningSamples); a tuning no ConditionalContentTuning row names
gives every character its own range, which the ceiling already holds, and gets none.

So a probe run at the level cap gives each tuning's maximum: every quest it loaded on the tuning
answers that level, and quests the server refused, or the probe never asked, share it through their
tuning. A quest's tuning is the quest cache's, else the task table's (QuestLevels.ps1's
Read-QuestTunings). Tuning 0 has no range. The ContentTuning table's own maximum (MaxLevelSquish and
MaxLevelScalingOffset) is not used: the game scaled 105 of the 771 tunings the 12.1.5 probe answered
for higher than it says (750, 1427 and 1707 are 60 or less in the table and 90 in the game).

The ceiling is stored as `maxLevel` only where it is above the quest's minimum (minLevel, else
level); a quest whose ceiling is its minimum does not scale. The level the list shows, sorts by and
the low-level filter reads is Get-ShownQuestLevel's, the same rule as qcShownQuestLevel in qcCore.lua.
#>
. "$PSScriptRoot\QuestLevels.ps1"
. "$PSScriptRoot\ProbeResults.ps1"

# The level cap of each retail expansion's builds, by the build's first number. A build of an
# expansion not listed is refused until its cap is added here (or given with -Cap).
$script:RetailLevelCaps = @{ 11 = 80; 12 = 90 }

# The game's expansion numbers (GetQuestExpansion), for the reports.
$script:ExpansionNames = @{ 0 = 'Classic'; 1 = 'The Burning Crusade'; 2 = 'Wrath of the Lich King'; 3 = 'Cataclysm'
    4 = 'Mists of Pandaria'; 5 = 'Warlords of Draenor'; 6 = 'Legion'; 7 = 'Battle for Azeroth'; 8 = 'Shadowlands'
    9 = 'Dragonflight'; 10 = 'The War Within'; 11 = 'Midnight' }

function Get-RetailLevelCap([string]$build) {
    $major = [int]($build -replace '^(\d+)\..*$', '$1')
    if ($script:RetailLevelCaps.ContainsKey($major)) { return $script:RetailLevelCaps[$major] }
    return $null
}

function Get-ExpansionName($expansion) {
    if ($null -eq $expansion) { return 'no expansion' }
    if ($script:ExpansionNames.ContainsKey([int]$expansion)) { return $script:ExpansionNames[[int]$expansion] }
    return "expansion $expansion"
}

# Whether every quest run of the probe's build was made at the cap: a row keeps only its last answer, and
# any of the build's quest runs may have given it. Ok, and the Problem when not.
function Test-ProbeAtCap($probe, $cap) {
    if ($null -eq $cap) { return [pscustomobject]@{ Ok = $false; Problem = "no level cap is known for build $($probe.Build): add its expansion to `$RetailLevelCaps in QuestScaling.ps1, or give -Cap" } }
    $runs = @($probe.BuildRuns)
    if ($runs.Count -eq 0) { return [pscustomobject]@{ Ok = $false; Problem = "the probe file has no quest run on build $($probe.Build)" } }
    $off = @($runs | Where-Object { $_.Level -ne $cap })
    if ($off.Count -eq 0) { return [pscustomobject]@{ Ok = $true; Problem = '' } }
    $what = ($off | ForEach-Object { "run $($_.Run) at $(if ($null -ne $_.Level) { "level $($_.Level)" } else { 'no recorded level' })" }) -join ', '
    return [pscustomobject]@{ Ok = $false; Problem = "the quest runs of build $($probe.Build) were not all made at the level cap ($cap): $what. A level below the cap says only that a quest scales at least that far; run the probe's quest pass (/qcprobe quests all) on a character at the cap" }
}

# The level each tuning scales to at the cap, from the probe's loaded quests with a level above 0 (Get-ProbeLevelFacts
# leaves out refused quests, timeouts and the placeholder rows of records held in part). Single maps a tuning
# to its one level; Split maps each tuning whose quests gave several to what they gave (level -> quests). The counts
# say what each row came to: Used, NoLevel (a level of 0 or none), NoTuning, TuningZero.
function Get-TuningCeilings($probe, $questTuning) {
    $levels = @{}
    $counts = [ordered]@{ Used = 0; NoLevel = 0; NoTuning = 0; TuningZero = 0 }
    foreach ($id in $probe.Quests.Keys) {
        $level = $probe.Quests[$id].Level
        if ($null -eq $level -or $level -le 0) { $counts.NoLevel++; continue }
        $n = [int]$id
        if (-not $questTuning.ContainsKey($n)) { $counts.NoTuning++; continue }
        $tuning = $questTuning[$n]
        if ($tuning -eq 0) { $counts.TuningZero++; continue }
        if (-not $levels.ContainsKey($tuning)) { $levels[$tuning] = @{} }
        $levels[$tuning][$level] = 1 + [int]$levels[$tuning][$level]
        $counts.Used++
    }
    $single = @{}
    $split = @{}
    $onSingle = 0
    foreach ($tuning in $levels.Keys) {
        $found = $levels[$tuning]
        if ($found.Count -eq 1) {
            $single[$tuning] = @($found.Keys)[0]
            $onSingle += @($found.Values)[0]
        } else {
            $split[$tuning] = $found
        }
    }
    return [pscustomobject]@{ Single = $single; Split = $split; Counts = $counts; OnSingle = $onSingle }
}

# What a quest's maxLevel should be, and why: Source is probe (its tuning's level at the cap; Ceiling is
# that, or $null when it is not above the quest's minimum), split (its tuning gave several: none),
# tuning0 (no range: none) or keep (no tuning, or one the probe has no level for: it keeps what it has).
function Get-QuestCeiling($quest, $questTuning, $ceilings) {
    $id = [int]$quest.id
    if (-not $questTuning.ContainsKey($id)) { return [pscustomobject]@{ Source = 'keep'; Why = 'no tuning'; Ceiling = $null; Level = $null } }
    $tuning = $questTuning[$id]
    if ($tuning -eq 0) { return [pscustomobject]@{ Source = 'tuning0'; Why = ''; Ceiling = $null; Level = $null } }
    if ($ceilings.Single.ContainsKey($tuning)) {
        $level = [int]$ceilings.Single[$tuning]
        $ceiling = if ($level -gt (Get-QuestGate $quest)) { $level } else { $null }
        return [pscustomobject]@{ Source = 'probe'; Why = ''; Ceiling = $ceiling; Level = $level }
    }
    if ($ceilings.Split.ContainsKey($tuning)) { return [pscustomobject]@{ Source = 'split'; Why = ''; Ceiling = $null; Level = $null } }
    return [pscustomobject]@{ Source = 'keep'; Why = 'tuning not probed'; Ceiling = $null; Level = $null }
}

# The level the addon shows a quest at, for a character of $playerLevel: its own level, or for a quest with a
# ceiling the character's level, raised to the quest's minimum (minLevel, else level) and held down at the
# ceiling. qcShownQuestLevel in qcCore.lua is the same rule.
function Get-ShownQuestLevel([int]$level, $minLevel, $maxLevel, [int]$playerLevel) {
    if ($null -eq $maxLevel) { return $level }
    $floor = if ($null -ne $minLevel) { [int]$minLevel } else { $level }
    return [Math]::Max($floor, [Math]::Min($playerLevel, [int]$maxLevel))
}

# The addon's low-level filter: a level above 0 and below the cutoff (the character's level less its trivial range).
function Test-LowLevel([int]$shown, [int]$cutoff) { return $shown -gt 0 -and $shown -lt $cutoff }

# The addon's low-level rule against the game's IsQuestTrivial, at the probe's character level and trivial range,
# for every quest of $records the probe asked: the report's lines, and the totals (HidBefore and HidAfter: hidden
# though the game calls them not trivial, by the quest's own level and by the level shown with $maxOf's ceilings;
# ShownBefore and ShownAfter: shown though the game calls them trivial), by the game's expansion too.
function Compare-TrivialRule($records, $probe, $maxOf) {
    $lines = New-Object System.Collections.Generic.List[string]
    $total = [ordered]@{ Asked = 0; HidBefore = 0; HidAfter = 0; ShownBefore = 0; ShownAfter = 0 }
    if ($null -eq $probe.TrivialRange -or $probe.TrivialRange -is [bool] -or $null -eq $probe.CharacterLevel) {
        $lines.Add('Against the game: not compared, as the probe run kept no trivial range or character level.')
        return [pscustomobject]@{ Lines = $lines.ToArray(); Total = $total }
    }
    $player = [int]$probe.CharacterLevel
    $cutoff = $player - [int]$probe.TrivialRange
    $rows = [ordered]@{}
    foreach ($q in $records) {
        $id = [int]$q.id
        $p = $probe.Quests[[string]$id]
        if (-not $p -or $null -eq $p.Trivial) { continue }
        $total.Asked++
        $before = Test-LowLevel ([int]$q.level) $cutoff
        $after = Test-LowLevel (Get-ShownQuestLevel ([int]$q.level) $q.minLevel $maxOf[$id] $player) $cutoff
        $key = Get-ExpansionName $p.Expansion
        if (-not $rows.Contains($key)) { $rows[$key] = [ordered]@{ Order = $(if ($null -ne $p.Expansion) { [int]$p.Expansion } else { 99 }); HidBefore = 0; HidAfter = 0; ShownBefore = 0; ShownAfter = 0 } }
        $row = $rows[$key]
        if (-not $p.Trivial) { if ($before) { $row.HidBefore++ }; if ($after) { $row.HidAfter++ } }
        else { if (-not $before) { $row.ShownBefore++ }; if (-not $after) { $row.ShownAfter++ } }
    }
    foreach ($row in $rows.Values) { foreach ($k in 'HidBefore', 'HidAfter', 'ShownBefore', 'ShownAfter') { $total[$k] += $row[$k] } }
    $lines.Add(("Against the game, at the probe's level {0} with its trivial range {1} (hidden below {2}), for the {3:N0} quests of ours it asked IsQuestTrivial about:" -f
        $player, $probe.TrivialRange, $cutoff, $total.Asked))
    $lines.Add(("  hidden though the game calls them not trivial: {0:N0} by the quest's own level, {1:N0} by the shown level ({2:N0} now shown)" -f
        $total.HidBefore, $total.HidAfter, ($total.HidBefore - $total.HidAfter)))
    $lines.Add(("  shown though the game calls them trivial: {0:N0} by the quest's own level, {1:N0} by the shown level" -f $total.ShownBefore, $total.ShownAfter))
    $lines.Add('  by the game''s expansion (hidden though not trivial, before -> after; shown though trivial, before -> after):')
    foreach ($key in (@($rows.Keys) | Sort-Object { $rows[$_].Order })) {
        $row = $rows[$key]
        if (($row.HidBefore + $row.HidAfter + $row.ShownBefore + $row.ShownAfter) -eq 0) { continue }
        $lines.Add(("    {0}: {1:N0} -> {2:N0}; {3:N0} -> {4:N0}" -f $key, $row.HidBefore, $row.HidAfter, $row.ShownBefore, $row.ShownAfter))
    }
    return [pscustomobject]@{ Lines = $lines.ToArray(); Total = $total }
}

# The client's ConditionalContentTuning table: each row sends a tuning (ParentContentTuningID) to another
# (RedirectContentTuningID) for a character whose redirect bit RedirectEnum is on, the row of highest OrderIndex
# winning (TrinityCore's DB2Manager::GetRedirectedContentTuningId; quest 78642 shows it in the game).
$script:RedirectColumns = @('ID', 'OrderIndex', 'RedirectContentTuningID', 'RedirectEnum', 'ParentContentTuningID')

# tools\<table>-<build>.csv, downloaded from wago.tools when it is missing, and checked for $columns and more than
# $minRows rows before it is kept. $download takes the address and the path to save to; the tests give their own.
function Get-ClientTableFile([string]$toolsDir, [string]$table, [string]$build, [string[]]$columns, [int]$minRows, [scriptblock]$download = $null) {
    $path = Join-Path $toolsDir "$table-$build.csv"
    if (Test-Path $path) { return $path }
    if (-not $download) { $download = { param($uri, $to) $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $to } }
    $part = "$path.download"
    & $download "https://wago.tools/db2/$table/csv?build=$build" $part
    try {
        $header = ((Get-Content $part -TotalCount 1) -replace '^\xEF\xBB\xBF', '').Trim() -split ','
        $lacking = @($columns | Where-Object { $header -notcontains $_ })
        if ($lacking.Count -gt 0) { throw "The $table table for build $build has no column $($lacking -join ', '): Blizzard changed it." }
        if (@(Get-Content $part -TotalCount ($minRows + 2)).Count -lt ($minRows + 2)) { throw "The $table table for build $build has $minRows rows or fewer." }
    } catch {
        Remove-Item $part -ErrorAction SilentlyContinue
        throw
    }
    Move-Item $part $path -Force
    return $path
}

# The redirect table, read: Rows, ByEnum (rows per RedirectEnum) and ByParent (each redirected tuning's
# RedirectEnum values, ascending and each once).
function Read-TuningRedirects([string]$path) {
    $rows = @(Import-Csv $path)
    if ($rows.Count -eq 0) { throw "$path has no rows." }
    foreach ($column in $script:RedirectColumns) {
        if ($null -eq $rows[0].PSObject.Properties[$column]) { throw "$path has no '$column' column: Blizzard changed the table, so check the redirects in QuestScaling.ps1." }
    }
    $byEnum = @{}
    $sets = @{}
    foreach ($row in $rows) {
        $enum = [int]$row.RedirectEnum
        $parent = [int]$row.ParentContentTuningID
        $byEnum[$enum] = 1 + [int]$byEnum[$enum]
        if (-not $sets.ContainsKey($parent)) { $sets[$parent] = New-Object 'System.Collections.Generic.SortedSet[int]' }
        [void]$sets[$parent].Add($enum)
    }
    $byParent = @{}
    foreach ($parent in $sets.Keys) { $byParent[$parent] = [int[]]@($sets[$parent]) }
    return [pscustomobject]@{ Rows = $rows.Count; ByEnum = $byEnum; ByParent = $byParent }
}

# The baseline of the redirect table: the build it was taken from and its rows per RedirectEnum; $null with no file.
function Read-RedirectBaseline([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    $byEnum = @{}
    $build = ''
    foreach ($row in (Import-Csv $path)) { $byEnum[[int]$row.RedirectEnum] = [int]$row.Rows; $build = $row.Build }
    return [pscustomobject]@{ Build = $build; ByEnum = $byEnum }
}

function ConvertTo-RedirectBaselineText($redirects, [string]$build) {
    $lines = @('"Build","RedirectEnum","Rows"')
    foreach ($enum in (@($redirects.ByEnum.Keys) | Sort-Object)) { $lines += '"{0}","{1}","{2}"' -f $build, $enum, $redirects.ByEnum[$enum] }
    return ($lines -join "`r`n") + "`r`n"
}

# The redirect table against its baseline: the report's lines, the RedirectEnum values the baseline lacks (New), those
# the table lost (Gone) and those whose row count changed (Moved).
function Compare-RedirectBaseline($redirects, $baseline, [string]$build) {
    $lines = New-Object System.Collections.Generic.List[string]
    $enums = @(@($redirects.ByEnum.Keys) | Sort-Object)
    $lines.Add(("Redirects (ConditionalContentTuning of {0}): {1:N0} rows, {2} RedirectEnum values, {3:N0} tunings redirected; rows by enum: {4}" -f
        $build, $redirects.Rows, $enums.Count, $redirects.ByParent.Count, (($enums | ForEach-Object { "$_ ($($redirects.ByEnum[$_]))" }) -join ', ')))
    if ($null -eq $baseline) {
        $lines.Add('  No baseline file, so every RedirectEnum counts as new; -UpdateBaseline writes one from this run.')
        return [pscustomobject]@{ Lines = $lines.ToArray(); New = $enums; Gone = @(); Moved = @() }
    }
    $new = @($enums | Where-Object { -not $baseline.ByEnum.ContainsKey($_) })
    $gone = @(@($baseline.ByEnum.Keys) | Where-Object { -not $redirects.ByEnum.ContainsKey($_) } | Sort-Object)
    $moved = @($enums | Where-Object { $baseline.ByEnum.ContainsKey($_) -and $baseline.ByEnum[$_] -ne $redirects.ByEnum[$_] })
    $total = 0
    foreach ($rows in $baseline.ByEnum.Values) { $total += $rows }
    $named = { param($list, $text) if ($list.Count) { ' (' + (($list | ForEach-Object { & $text $_ }) -join ', ') + ')' } else { '' } }
    $lines.Add(("  against the baseline of {0} ({1:N0} rows): {2} new{3}, {4} gone{5}, {6} with another row count{7}  [{8}]" -f
        $baseline.Build, $total, $new.Count, (& $named $new { param($e) "$e" }), $gone.Count, (& $named $gone { param($e) "$e" }),
        $moved.Count, (& $named $moved { param($e) "${e}: $($baseline.ByEnum[$e]) -> $($redirects.ByEnum[$e])" }), $(if ($new.Count) { 'NEW' } else { 'ok' })))
    if ($new.Count) { $lines.Add('  A new RedirectEnum is a redirect no sweep has read: look at the tunings it moves (docs\plans\quest-scaling-redirects.md), then run with -UpdateBaseline.') }
    return [pscustomobject]@{ Lines = $lines.ToArray(); New = $new; Gone = $gone; Moved = $moved }
}

# What the addon counts as recurring (qcRecurringTypes: repeatable, daily, world quest or weekly), and whether both
# factions can take a quest (a faction mask of 0 holds none back).
function Test-RecurringQuest($quest) { return ([int]$quest.type -band (2 + 4 + 128)) -ne 0 }
function Test-BothFactions($quest) { $f = [int]$quest.faction; return $f -eq 0 -or ($f -band 3) -eq 3 }

# Each quest the probe loaded (ok or cached, with a level above 0) at its tuning's one level, by tuning. A late answer
# doesn't count.
function Get-SampleCandidates($probe, $questTuning, $ceilings) {
    $byTuning = @{}
    foreach ($key in $probe.Quests.Keys) {
        $p = $probe.Quests[$key]
        if (@('ok', 'cached') -cnotcontains $p.Result -or $null -eq $p.Level -or $p.Level -le 0) { continue }
        $id = [int]$key
        if (-not $questTuning.ContainsKey($id)) { continue }
        $tuning = $questTuning[$id]
        if ($tuning -eq 0 -or -not $ceilings.Single.ContainsKey($tuning) -or [int]$ceilings.Single[$tuning] -ne $p.Level) { continue }
        if (-not $byTuning.ContainsKey($tuning)) { $byTuning[$tuning] = New-Object System.Collections.Generic.List[int] }
        $byTuning[$tuning].Add($id)
    }
    return $byTuning
}

# A quest's kind as a sample, lower being better: a quest of ours, in QuestV2, not flagged unavailable, one-time, open
# to both factions (the probe's character loaded the other faction's quests, but no run has shown the reverse).
function Get-SampleKind($id, $ours, $questV2, $unavailable) {
    $q = $ours[$id]
    return 16 * [int]($null -eq $q) + 8 * [int](-not $questV2.Contains($id)) + 4 * [int]$unavailable.Contains($id) +
        2 * [int]($null -ne $q -and (Test-RecurringQuest $q)) + [int]($null -ne $q -and -not (Test-BothFactions $q))
}

# The order samples are taken in, best first: by kind (Get-SampleKind), then a sample already stored ($kept, in its
# stored order) before a new one, then the lowest id. So a fuller probe adds samples without moving one that players'
# clients may already hold, unless a better kind of quest is there to take its place.
function Get-SampleOrder($ids, $ours, $questV2, $unavailable, $kept = @()) {
    $at = @{}
    foreach ($id in @($kept)) { if (-not $at.ContainsKey([int]$id)) { $at[[int]$id] = $at.Count } }
    $rows = foreach ($id in $ids) {
        [pscustomobject]@{
            Id = $id
            Kind = Get-SampleKind $id $ours $questV2 $unavailable
            New = [int](-not $at.ContainsKey([int]$id))
            StoredAt = if ($at.ContainsKey([int]$id)) { $at[[int]$id] } else { 0 }
        }
    }
    return @($rows | Sort-Object Kind, New, StoredAt, Id | ForEach-Object { $_.Id })
}

# The records of tunings.jsonl: one for each tuning our quests are on ($used: tuning -> how many) that a redirect
# names and the probe sampled, with its level at the cap, its RedirectEnum values and up to $max samples, a sample of
# the $stored records staying while it is still a candidate (Get-SampleOrder). Fixed lists the tunings no redirect
# names, whose level is their own range for every character; Missing those a redirect names that get no samples, with
# Why: split, not probed, or no loaded quest. Kept counts the stored samples that stay, and Displaced lists those still
# candidates that don't (Tuning, Quest, Why).
function Get-TuningSamples($used, $redirects, $ceilings, $candidates, $ours, $questV2, $unavailable, [int]$max, $stored = @()) {
    $storedOf = @{}
    foreach ($t in @($stored)) { $storedOf[[int]$t.id] = [int[]]@($t.samples) }
    $records = New-Object System.Collections.Generic.List[object]
    $fixed = New-Object System.Collections.Generic.List[int]
    $missing = New-Object System.Collections.Generic.List[object]
    $displaced = New-Object System.Collections.Generic.List[object]
    $kept = 0
    foreach ($tuning in (@($used.Keys) | Sort-Object)) {
        if (-not $redirects.ByParent.ContainsKey($tuning)) { $fixed.Add($tuning); continue }
        $why = if ($ceilings.Split.ContainsKey($tuning)) { 'split' } elseif (-not $ceilings.Single.ContainsKey($tuning)) { 'not probed' } elseif (-not $candidates.ContainsKey($tuning)) { 'no loaded quest' } else { '' }
        if ($why) { $missing.Add([pscustomobject]@{ Tuning = $tuning; Why = $why; Quests = $used[$tuning] }); continue }
        $before = if ($storedOf.ContainsKey([int]$tuning)) { $storedOf[[int]$tuning] } else { [int[]]@() }
        $chosen = [int[]]@(Get-SampleOrder $candidates[$tuning] $ours $questV2 $unavailable $before | Select-Object -First $max)
        foreach ($s in $before) {
            if ($chosen -contains $s) { $kept++; continue }
            if (-not $candidates[$tuning].Contains($s)) { continue }
            $kind = Get-SampleKind $s $ours $questV2 $unavailable
            $better = @($chosen | Where-Object { (Get-SampleKind $_ $ours $questV2 $unavailable) -lt $kind }).Count -gt 0
            $displaced.Add([pscustomobject]@{ Tuning = $tuning; Quest = $s; Why = $(if ($better) { 'a better kind of quest takes its place' } else { "-Samples $max keeps the ones before it" }) })
        }
        $records.Add([pscustomobject]@{ id = $tuning; level = [int]$ceilings.Single[$tuning]; redirects = $redirects.ByParent[$tuning]; samples = $chosen })
    }
    return [pscustomobject]@{ Records = $records.ToArray(); Fixed = $fixed.ToArray(); Missing = $missing.ToArray(); Kept = $kept; Displaced = $displaced.ToArray() }
}

# The stored tunings.jsonl against the wanted records: Added, Changed and Removed (tuning ids); LevelMoved, each tuning
# in both whose level is another (Tuning, Old, New, Redirects); and Stale, each stored sample that is no longer one
# (Tuning, Quest, Why).
function Compare-TuningRecords($stored, $wanted, $probe, $questTuning, $ceilings) {
    $was = @{}; foreach ($t in $stored) { $was[[int]$t.id] = $t }
    $now = @{}; foreach ($t in $wanted) { $now[[int]$t.id] = $t }
    $text = { param($t) "$($t.level)|$(@($t.redirects) -join ',')|$(@($t.samples) -join ',')" }
    $added = @(@($now.Keys) | Where-Object { -not $was.ContainsKey($_) } | Sort-Object)
    $removed = @(@($was.Keys) | Where-Object { -not $now.ContainsKey($_) } | Sort-Object)
    $changed = @(@($now.Keys) | Where-Object { $was.ContainsKey($_) -and (& $text $was[$_]) -cne (& $text $now[$_]) } | Sort-Object)
    $levelMoved = @(@($now.Keys) | Where-Object { $was.ContainsKey($_) -and [int]$was[$_].level -ne [int]$now[$_].level } | Sort-Object | ForEach-Object {
        [pscustomobject]@{ Tuning = $_; Old = [int]$was[$_].level; New = [int]$now[$_].level; Redirects = @($now[$_].redirects) } })
    $stale = New-Object System.Collections.Generic.List[object]
    foreach ($t in $stored) {
        $tuning = [int]$t.id
        foreach ($quest in @($t.samples)) {
            $p = $probe.Quests[[string]$quest]
            $why = if (-not $p -or @('ok', 'cached') -cnotcontains $p.Result -or $null -eq $p.Level -or $p.Level -le 0) { 'not loaded in the probe' }
                elseif (-not $questTuning.ContainsKey([int]$quest) -or $questTuning[[int]$quest] -ne $tuning) { 'on another tuning now' }
                elseif (-not $ceilings.Single.ContainsKey($tuning) -or $p.Level -ne [int]$ceilings.Single[$tuning]) { "at level $($p.Level), not its tuning's one level" }
                else { '' }
            if ($why) { $stale.Add([pscustomobject]@{ Tuning = $tuning; Quest = [int]$quest; Why = $why }) }
        }
    }
    return [pscustomobject]@{ Added = $added; Changed = $changed; Removed = $removed; LevelMoved = $levelMoved; Stale = $stale.ToArray() }
}
