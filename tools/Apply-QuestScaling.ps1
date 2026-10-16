<#
Gives retail's scaling quests the level they stop scaling at, so that the list's bracket, its sort and
the low-level filter (the list's and the map's) judge such a quest by the level the game scales it to,
not by the floor of its range (open-items.md row 9, option C, taken on 16 October 2026; API review
recommendation 4). Before it, the probe run of 15 October 2026 found 9,753 quests a level 90 character
lost to "Hide low level quests" that the game calls not trivial.

The ceiling is the level the game gives each content tuning at the level cap, read from the newest
retail probe run (QuestScaling.ps1 has the rule and the sources). Every quest run of the probe's
build must have been made by a character at the cap, or nothing is written: below the cap a scaled
level says only that the quest scales at least that far. Each tuning's loaded quests must agree on
one level; a tuning whose quests give several gets no ceiling, and the run stops, changing nothing,
unless at least -MinAgreement of at least -MinProbed usable quests sit on tunings that agree. Every
quest of a tuning, probed or not, gets that level as its `maxLevel` when it is above the quest's
minimum (minLevel, else level), and none when it isn't, or when its tuning is 0 or split. A quest
with no tuning, or on a tuning the probe has no level for, keeps what it has. Nothing else in a
record changes. Saved through AddonData.ps1, which rebuilds qcQuestData.lua (qcQuestMaxLevel).

After the changes it compares the addon's low-level rule with the game's own answer, for every quest
the probe asked IsQuestTrivial about: how many the rule hid, before and after, that the game calls
not trivial, and how many it showed that the game calls trivial, by the game's expansion.

  -WhatIf    report only: the sources, the ceilings, the changes and the comparison; writes no data
  -Check     like -WhatIf, but exits 1 when the data isn't what the probe says (for Test- and Audit- steps)
  -ProbeFile the probe's saved variables; the newest tools\retail_probe_<build>\QCForeverProbe.lua by default
  -Build     the retail build of the quest cache; the newest retail_quest_cache_<build>.jsonl's by default.
             It must be the probe's build.
  -Cap       the level cap of the probe's build, when $RetailLevelCaps in QuestScaling.ps1 lacks it
  -Game forever  the check for WoW: Forever, which writes nothing: data\forever\quests.jsonl against the
             newest tools\forever_probe_<build>\QCForeverProbe.lua. Forever's quests don't scale, so every
             quest the probe loaded must have its stored level and none may hold a maxLevel; it lists any
             that doesn't, compares the low-level rule with IsQuestTrivial at the probe's level, and exits
             1 when a quest's level is not the game's or a maxLevel is there

Reads the probe file (In the game, step 3 of docs\maintenance.md), tools\retail_quest_cache_<build>.jsonl
(step 2e) and tools\QuestV2CliTask.csv (step 1b). Run it after step 2g, whose minLevel is each quest's
floor, and again after step 6 or 6b adds quests. Safe to rerun: a second run changes nothing. Exit 0
is a clean run, 1 a refused one or, with -Check, a difference.
#>
param(
    [string]$Game = 'retail',
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = '',
    [string]$ProbeFile = '',
    [int]$Cap = 0,
    [double]$MinAgreement = 0.99,
    [int]$MinProbed = 20000,
    [int]$Examples = 10,
    [string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe',
    [switch]$WhatIf,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. "$PSScriptRoot\QuestScaling.ps1"

function Refuse([string]$why) {
    Write-Output "$why. Nothing was changed."
    exit 1
}

if ($Game -notin 'retail', 'forever') { throw '-Game must be retail or forever.' }
if ($Game -eq 'forever') {
    if (-not $PSBoundParameters.ContainsKey('DataDir')) { $DataDir = Join-Path $PSScriptRoot '..\data\forever' }
    if (-not $ProbeFile) {
        $ProbeFile = Get-ChildItem "$ToolsDir\forever_probe_*\QCForeverProbe.lua" -ErrorAction SilentlyContinue |
            Sort-Object { [int]($_.Directory.Name -replace '^forever_probe_(\d+).*$', '$1') } | Select-Object -Last 1 | ForEach-Object { $_.FullName }
    }
    if (-not $ProbeFile -or -not (Test-Path $ProbeFile)) { throw "No Forever probe results under $ToolsDir\forever_probe_*: give -ProbeFile." }
    $probe = Get-ProbeLevelFacts $ProbeFile $LuaExe
    $records = Read-QuestData $DataDir
    $same = 0
    $other = New-Object System.Collections.Generic.List[object]
    $maxOf = @{}
    foreach ($q in $records) {
        if ($null -ne $q.maxLevel) { $maxOf[[int]$q.id] = $q.maxLevel }
        $p = $probe.Quests[[string]$q.id]
        if (-not $p -or $null -eq $p.Level) { continue }
        if ($p.Level -eq [int]$q.level) { $same++ } else { $other.Add([pscustomobject]@{ Quest = $q; Game = $p.Level }) }
    }
    Write-Output ("Forever probe {0}: build {1}, {2} at level {3}; of the {4:N0} quests of ours it loaded, {5:N0} have their stored level and {6:N0} another." -f
        $ProbeFile, $probe.Build, $probe.Character, $probe.CharacterLevel, ($same + $other.Count), $same, $other.Count)
    foreach ($o in ($other | Sort-Object { [int]$_.Quest.id } | Select-Object -First $Examples)) {
        Write-Output ("  {0}  level {1}, the game's {2}  {3}" -f $o.Quest.id, $o.Quest.level, $o.Game, $o.Quest.name)
    }
    if ($other.Count -gt $Examples) { Write-Output "  ... and $($other.Count - $Examples) more" }
    if ($maxOf.Count) { Write-Output "$($maxOf.Count) of Forever's quests hold a maxLevel, which nothing gives them." }
    (Compare-TrivialRule $records $probe $maxOf).Lines | ForEach-Object { Write-Output $_ }
    if ($other.Count -gt 0 -or $maxOf.Count -gt 0) {
        Write-Output "Forever's quests don't read as fixed-level any more: look at the quests above before trusting the low-level filter there (docs\maintenance.md, step 2j)."
        exit 1
    }
    Write-Output "Forever's quests don't scale: every loaded quest has its stored level. Nothing to write."
    exit 0
}

$Build = Resolve-RetailBuild $ToolsDir $Build
$cacheFile = Join-Path $ToolsDir "retail_quest_cache_$Build.jsonl"
if (-not (Test-Path $cacheFile)) { throw "No ${cacheFile}: run Read-QuestCache.ps1 -Build $Build (step 2e) first." }
if (-not $ProbeFile) { $ProbeFile = Find-ProbeResults $ToolsDir }
if (-not (Test-Path $ProbeFile)) { throw "No probe results at ${ProbeFile}: copy the retail probe's saved variables into tools\retail_probe_<build>\ (In the game, step 3), or give -ProbeFile." }
$probe = Get-ProbeLevelFacts $ProbeFile $LuaExe
$runCap = if ($Cap -gt 0) { $Cap } else { Get-RetailLevelCap $probe.Build }
Write-Output ("Probe {0}: build {1}, {2:N0} loaded quests with level facts ({3:N0} placeholder rows of records held in part left out); quest runs on the build: {4}." -f
    $ProbeFile, $probe.Build, $probe.Loaded, $probe.Partial,
    (($probe.BuildRuns | ForEach-Object { "run $($_.Run), $($_.Character) at level $(if ($null -ne $_.Level) { $_.Level } else { '?' })" }) -join '; '))
$atCap = Test-ProbeAtCap $probe $runCap
if (-not $atCap.Ok) { Refuse "Refused: $($atCap.Problem)" }
if ($probe.Build -cne $Build) { Refuse "Refused: the probe ran on build $($probe.Build) and the quest cache is of $Build; the tunings must be the probe's (give -Build $($probe.Build), or probe the cache's build)" }

$questTuning = Read-QuestTunings $cacheFile (Join-Path $ToolsDir 'QuestV2CliTask.csv')
$records = Read-QuestData $DataDir
$cacheWarning = @(Get-QuestCacheWarning $cacheFile @($records | ForEach-Object { [int]$_.id }))
Write-Output ("Retail build {0}, level cap {1}: {2:N0} quests in the data; tunings for {3:N0} quests ({4:N0} from the quest cache, {5:N0} more from the task table)." -f
    $Build, $runCap, $records.Count, $questTuning.ByQuest.Count, $questTuning.FromCache, $questTuning.FromTable)
$cacheWarning | ForEach-Object { Write-Output $_ }

$ceilings = Get-TuningCeilings $probe $questTuning.ByQuest
$c = $ceilings.Counts
$agreement = if ($c.Used -gt 0) { $ceilings.OnSingle / $c.Used } else { 0.0 }
$ok = $c.Used -ge $MinProbed -and $agreement -ge $MinAgreement
Write-Output ("Tunings: {0:N0} probed quests used ({1:N0} with no level above 0, {2:N0} with no tuning and {3:N0} on tuning 0 left out); {4:N0} tunings scale to one level each at the cap, for {5:N0} of them ({6:N2}%); {7:N0} give several  [{8}]" -f
    $c.Used, $c.NoLevel, $c.NoTuning, $c.TuningZero, $ceilings.Single.Count, $ceilings.OnSingle, (100.0 * $agreement), $ceilings.Split.Count, $(if ($ok) { 'ok' } else { 'FAILED' }))
foreach ($tuning in (@($ceilings.Split.Keys) | Sort-Object | Select-Object -First $Examples)) {
    $found = $ceilings.Split[$tuning]
    Write-Output ("  tuning {0} gives several levels, so none of its quests gets a ceiling: {1}" -f $tuning, ((@($found.Keys) | Sort-Object | ForEach-Object { "$_ ($($found[$_]) quests)" }) -join ', '))
}
if ($ceilings.Split.Count -gt $Examples) { Write-Output "  ... and $($ceilings.Split.Count - $Examples) more tunings that give several levels" }
if (-not $ok) {
    if ($c.Used -lt $MinProbed) { Write-Output "  only $($c.Used) usable probed quests, fewer than -MinProbed ${MinProbed}: is the probe run complete?" }
    Refuse "The probe's scaled levels don't agree per tuning well enough"
}

$bySource = [ordered]@{ probe = 0; split = 0; tuning0 = 0; keep = 0 }
$kept = @{}
$wantedOf = @{}
$changes = New-Object System.Collections.Generic.List[object]
$given = 0; $givenProbed = 0; $atFloor = 0; $belowFloor = New-Object System.Collections.Generic.List[object]
$byCeiling = @{}; $levelZero = 0; $aboveCeiling = New-Object System.Collections.Generic.List[object]
foreach ($q in $records) {
    $id = [int]$q.id
    $r = Get-QuestCeiling $q $questTuning.ByQuest $ceilings
    $bySource[$r.Source]++
    $current = $q.maxLevel
    if ($r.Source -eq 'keep') {
        $kept[$r.Why] = 1 + [int]$kept[$r.Why]
        $wantedOf[$id] = $current
        continue
    }
    $wanted = $r.Ceiling
    $wantedOf[$id] = $wanted
    if ($r.Source -eq 'probe') {
        if ($null -ne $wanted) {
            $given++
            if ($probe.Quests.ContainsKey([string]$id)) { $givenProbed++ }
            $byCeiling[$wanted] = 1 + [int]$byCeiling[$wanted]
            if ([int]$q.level -le 0) { $levelZero++ }
            if ([int]$q.level -gt $wanted) { $aboveCeiling.Add($q) }
        } elseif ($r.Level -eq (Get-QuestGate $q)) { $atFloor++ }
        else { $belowFloor.Add([pscustomobject]@{ Quest = $q; Level = $r.Level }) }
    }
    if ($null -eq $wanted -and $null -eq $current) { continue }
    if ($null -ne $wanted -and $null -ne $current -and [int]$wanted -eq [int]$current) { continue }
    $kind = if ($null -eq $current) { 'added' } elseif ($null -eq $wanted) { 'removed' } else { 'changed' }
    $changes.Add([pscustomobject]@{ Quest = $q; Id = $id; Name = [string]$q.name; Old = $current; New = $wanted; Kind = $kind; Source = $r.Source })
}

$keptText = if ($kept.Count) { ' (' + ((@($kept.Keys) | Sort-Object | ForEach-Object { "$($kept[$_]) $_" }) -join ', ') + ')' } else { '' }
Write-Output ("Sources: a probed tuning for {0:N0} quests, a split one for {1:N0}, tuning 0 for {2:N0}; {3:N0} keep what they have{4}." -f
    $bySource.probe, $bySource.split, $bySource.tuning0, $bySource.keep, $keptText)
Write-Output ("Ceilings: {0:N0} quests scale, {1:N0} of them answered in the probe and {2:N0} through their tuning; {3:N0} are at their minimum at the cap, so don't scale; {4:N0} would have a ceiling below their minimum and get none." -f
    $given, $givenProbed, ($given - $givenProbed), $atFloor, $belowFloor.Count)
Write-Output ("  by ceiling: " + ((@($byCeiling.Keys) | Sort-Object -Descending | ForEach-Object { "$_ ($($byCeiling[$_]))" }) -join ', '))
if ($levelZero) { Write-Output "  $levelZero of them have a level of 0 (no level), so the list now shows them at a level" }
if ($aboveCeiling.Count) {
    Write-Output ("  {0} have a level of their own above their ceiling, so the list shows them lower at the cap than their level; the first by id (id, level, minimum, ceiling, name):" -f $aboveCeiling.Count)
    foreach ($q in ($aboveCeiling | Sort-Object { [int]$_.id } | Select-Object -First $Examples)) {
        Write-Output ("    {0}  level {1}  minimum {2}  ceiling {3}  {4}" -f $q.id, $q.level, (Get-QuestGate $q), $wantedOf[[int]$q.id], $q.name)
    }
}
foreach ($b in ($belowFloor | Sort-Object { [int]$_.Quest.id } | Select-Object -First $Examples)) {
    Write-Output ("  below its minimum: {0}  level {1}  minimum {2}  the game's level at the cap {3}  {4}" -f $b.Quest.id, $b.Quest.level, (Get-QuestGate $b.Quest), $b.Level, $b.Quest.name)
}

Write-Output ("Changes: {0:N0} quests ({1:N0} maxLevel added, {2:N0} changed, {3:N0} removed)." -f $changes.Count,
    @($changes | Where-Object { $_.Kind -eq 'added' }).Count, @($changes | Where-Object { $_.Kind -eq 'changed' }).Count,
    @($changes | Where-Object { $_.Kind -eq 'removed' }).Count)
foreach ($kind in 'added', 'changed', 'removed') {
    $these = @($changes | Where-Object { $_.Kind -eq $kind })
    if ($these.Count -eq 0) { continue }
    Write-Output "  $kind, the first ${Examples} by id (id, level, minimum, maxLevel before and after, source, name):"
    foreach ($ch in ($these | Sort-Object Id | Select-Object -First $Examples)) {
        Write-Output ("    {0}  level {1}  minimum {2}  {3} -> {4}  {5}  {6}" -f $ch.Id, $ch.Quest.level, (Get-QuestGate $ch.Quest),
            $(if ($null -ne $ch.Old) { $ch.Old } else { 'none' }), $(if ($null -ne $ch.New) { $ch.New } else { 'none' }), $ch.Source, $ch.Name)
    }
}

(Compare-TrivialRule $records $probe $wantedOf).Lines | ForEach-Object { Write-Output $_ }

if ($changes.Count -eq 0) {
    Write-Output "Nothing to change: every quest's maxLevel is what the probe says."
    exit 0
}
if ($Check) {
    Write-Output "The data isn't what the probe says for $($changes.Count) quests: run Apply-QuestScaling.ps1 (-WhatIf first)."
    exit 1
}
if ($WhatIf) {
    Write-Output '-WhatIf: nothing was written.'
    exit 0
}

foreach ($ch in $changes) { Set-RecordField $ch.Quest 'maxLevel' $ch.New }
Save-QuestData $records $DataDir $AddonDir
$entries = @($records | Where-Object { $null -ne $_.maxLevel }).Count
Write-Output "Saved: $($changes.Count) quests changed, $entries quests now hold a maxLevel."
