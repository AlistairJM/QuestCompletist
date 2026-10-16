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
