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
It also lists the quests the game holds at their minimum whose own level is another: the list shows
that level, as no ceiling applies, and nothing here changes it (open-items.md, "Data to finish").

After the changes it compares the addon's low-level rule with the game's own answer, for every quest
the probe asked IsQuestTrivial about: how many the rule hid, before and after, that the game calls
not trivial, and how many it showed that the game calls trivial, by the game's expansion.

It also gives each quest its content tuning, as `tuning`: the quest cache's ContentTuningID, else the task
table's. A quest on tuning 0 gets none, and one neither source has keeps what it has. And it writes
data\tunings.jsonl: for each tuning our quests are on that a row of the client's ConditionalContentTuning
table names, the tuning's level at the cap, the RedirectEnum values of its rows and up to -Samples quests
the probe loaded (ok or cached) at that level, the best first (QuestScaling.ps1's Get-SampleOrder). The
server gives each character the redirect bits that choose such a row, and no addon call reads them, so a
character can get another level for the tuning than the probe's did (docs\plans\quest-scaling-redirects.md).
The addon is to read that level from a sample whose data the client holds. A tuning no row names gets no
record: every character gets its own range, which maxLevel already holds. The build writes qcTuningSample
from the records, and qcQuestTuning for the quests on their tunings. A stored sample stays while the newest
probe still loads it at its tuning's one level, unless a better kind of quest is there to take its place,
as players' clients may hold it already; one the probe no longer loads at that level, or whose quest moved
tuning, is listed and replaced. A sampled tuning whose level moved is listed too, as many at once can mean
the probe's character had other redirect bits. The redirect table is compared with its baseline
(-BaselineFile): its rows by RedirectEnum, and any RedirectEnum the baseline lacks, which a sweep must look
at before -UpdateBaseline takes it in. It also counts the keys of qcQuestMaxLevel and qcQuestTuning
against 32,768, above which Lua 5.1 doubles a table's hash part (docs\plans\load-and-memory.md).

  -WhatIf    report only: the sources, the ceilings, the changes and the comparison; writes no data
  -Check     like -WhatIf, but exits 1 when the data isn't what the probe says, or the redirect table has a
             RedirectEnum its baseline lacks (for Test- and Audit- steps)
  -Samples   the most samples a tuning gets (3)
  -BaselineFile    the redirect table's baseline; docs\plans\quest-scaling-redirects-baseline.csv by default
  -UpdateBaseline  write the baseline from this run's redirect table (not with -Check or -WhatIf)
  -UnavailableFile the reviewed unavailable quests, whose FLAG rows are taken as samples only after the others;
             docs\plans\unavailable-quest-decisions.csv by default
  -ProbeFile the probe's saved variables; the newest tools\retail_probe_<build>\QCForeverProbe.lua by default
  -Build     the retail build of the quest cache; the newest retail_quest_cache_<build>.jsonl's by default.
             It must be the probe's build.
  -Cap       the level cap of the probe's build, when $RetailLevelCaps in QuestScaling.ps1 lacks it
  -Game forever  the check for WoW: Forever, which writes nothing: data\forever\quests.jsonl against the
             newest tools\forever_probe_<build>\QCForeverProbe.lua. Forever's quests don't scale, so every
             quest the probe loaded must have its stored level and none may hold a maxLevel or a tuning,
             nor may the folder hold a tunings.jsonl; it lists any that doesn't, compares the low-level
             rule with IsQuestTrivial at the probe's level, and exits 1 when a quest's level is not the
             game's or a maxLevel, a tuning or a tunings.jsonl is there

Reads the probe file (In the game, step 3 of docs\maintenance.md), tools\retail_quest_cache_<build>.jsonl
(step 2e), tools\QuestV2CliTask.csv (step 1b), and tools\ConditionalContentTuning-<build>.csv and
tools\QuestV2-<build>.csv of the probe's build, which it downloads from wago.tools when they are missing.
Run it after step 2g, whose minLevel is each quest's floor, and again after step 6 or 6b adds quests.
Safe to rerun: a second run changes nothing. Exit 0 is a clean run, 1 a refused one or, with -Check, a
difference.
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
    [int]$Samples = 3,
    [string]$BaselineFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-scaling-redirects-baseline.csv'),
    [string]$UnavailableFile = (Join-Path $PSScriptRoot '..\docs\plans\unavailable-quest-decisions.csv'),
    [string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe',
    [switch]$WhatIf,
    [switch]$Check,
    [switch]$UpdateBaseline
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. "$PSScriptRoot\QuestScaling.ps1"

function Refuse([string]$why) {
    Write-Output "$why. Nothing was changed."
    exit 1
}

if ($Game -notin 'retail', 'forever') { throw '-Game must be retail or forever.' }
if ($Check -and $UpdateBaseline) { throw '-Check writes nothing, so it takes no -UpdateBaseline.' }
if ($WhatIf -and $UpdateBaseline) { throw '-WhatIf writes nothing, so it takes no -UpdateBaseline.' }
if ($Samples -lt 1) { throw '-Samples must be 1 or more.' }
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
    $tuned = 0
    foreach ($q in $records) {
        if ($null -ne $q.maxLevel) { $maxOf[[int]$q.id] = $q.maxLevel }
        if ($null -ne $q.tuning) { $tuned++ }
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
    if ($tuned) { Write-Output "$tuned of Forever's quests hold a tuning, which nothing gives them." }
    $tuningFile = Test-Path (Join-Path $DataDir 'tunings.jsonl')
    if ($tuningFile) { Write-Output "Forever's data folder holds a tunings.jsonl, which nothing writes there." }
    (Compare-TrivialRule $records $probe $maxOf).Lines | ForEach-Object { Write-Output $_ }
    if ($other.Count -gt 0 -or $maxOf.Count -gt 0 -or $tuned -gt 0 -or $tuningFile) {
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
$offFloor = New-Object System.Collections.Generic.List[object]
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
        } elseif ($r.Level -eq (Get-QuestGate $q)) {
            $atFloor++
            if ([int]$q.level -ne $r.Level) { $offFloor.Add($q) }
        } else { $belowFloor.Add([pscustomobject]@{ Quest = $q; Level = $r.Level }) }
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
if ($offFloor.Count) {
    $offZero = @($offFloor | Where-Object { [int]$_.level -le 0 }).Count
    $offBelow = @($offFloor | Where-Object { [int]$_.level -gt 0 -and [int]$_.level -lt [int]$_.minLevel }).Count
    $offProbed = @($offFloor | Where-Object { $probe.Quests.ContainsKey([string]$_.id) }).Count
    Write-Output ("  {0} of those at their minimum have a level of their own that isn't it, which the list shows, sorts by and the low-level filter reads, where the game holds the quest at its minimum: {1} below it, {2} above it and {3} of level 0 (no bracket, never low); {4} of them answered in the probe. The first {5} by id (id, level, minimum, name):" -f
        $offFloor.Count, $offBelow, ($offFloor.Count - $offBelow - $offZero), $offZero, $offProbed, $Examples)
    foreach ($q in ($offFloor | Sort-Object { [int]$_.id } | Select-Object -First $Examples)) {
        Write-Output ("    {0}  level {1}  minimum {2}  {3}" -f $q.id, $q.level, $q.minLevel, $q.name)
    }
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

$from = [ordered]@{ cache = 0; table = 0; zeroCache = 0; zeroTable = 0; keep = 0; none = 0 }
$wantedTuning = @{}
$used = @{}
$tuningChanges = New-Object System.Collections.Generic.List[object]
foreach ($q in $records) {
    $id = [int]$q.id
    $current = $q.tuning
    $inTable = $questTuning.TableIds.Contains($id)
    if ($questTuning.ByQuest.ContainsKey($id)) {
        $wanted = $questTuning.ByQuest[$id]
        if ($wanted -eq 0) { $wanted = $null; if ($inTable) { $from.zeroTable++ } else { $from.zeroCache++ } }
        elseif ($inTable) { $from.table++ } else { $from.cache++ }
    } elseif ($null -ne $current) { $wanted = [int]$current; $from.keep++ }
    else { $wanted = $null; $from.none++ }
    if ($null -ne $wanted) { $wantedTuning[$id] = $wanted; $used[$wanted] = 1 + [int]$used[$wanted] }
    if ($null -eq $wanted -and $null -eq $current) { continue }
    if ($null -ne $wanted -and $null -ne $current -and $wanted -eq [int]$current) { continue }
    $kind = if ($null -eq $current) { 'added' } elseif ($null -eq $wanted) { 'removed' } else { 'changed' }
    $tuningChanges.Add([pscustomobject]@{ Quest = $q; Id = $id; Old = $current; New = $wanted; Kind = $kind })
}
Write-Output ("Quest tunings: {0:N0} quests get one, {1:N0} from the quest cache and {2:N0} from the task table; {3:N0} keep the one they hold, as neither has them; {4:N0} are on tuning 0 ({5:N0} in the cache, {6:N0} in the task table) and {7:N0} have none in either, so get none." -f
    $wantedTuning.Count, $from.cache, $from.table, $from.keep, ($from.zeroCache + $from.zeroTable), $from.zeroCache, $from.zeroTable, $from.none)
Write-Output ("  changes: {0:N0} quests ({1:N0} tuning added, {2:N0} changed, {3:N0} removed)" -f $tuningChanges.Count,
    @($tuningChanges | Where-Object { $_.Kind -eq 'added' }).Count, @($tuningChanges | Where-Object { $_.Kind -eq 'changed' }).Count,
    @($tuningChanges | Where-Object { $_.Kind -eq 'removed' }).Count)
foreach ($kind in 'changed', 'removed') {
    foreach ($ch in (@($tuningChanges | Where-Object { $_.Kind -eq $kind }) | Sort-Object Id | Select-Object -First $Examples)) {
        Write-Output ("    {0}  tuning {1} -> {2}  {3}" -f $ch.Id, $ch.Old, $(if ($null -ne $ch.New) { $ch.New } else { 'none' }), $ch.Quest.name)
    }
}

$redirects = Read-TuningRedirects (Get-ClientTableFile $ToolsDir 'ConditionalContentTuning' $Build $script:RedirectColumns 100)
$redirectCheck = Compare-RedirectBaseline $redirects (Read-RedirectBaseline $BaselineFile) $Build
$redirectCheck.Lines | ForEach-Object { Write-Output $_ }

$questV2 = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($row in (Import-Csv (Get-ClientTableFile $ToolsDir 'QuestV2' $Build @('ID') 1000))) { [void]$questV2.Add([int]$row.ID) }
$unavailable = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($row in (Import-Csv $UnavailableFile)) { if ($row.Decision -ceq 'FLAG') { [void]$unavailable.Add([int]$row.QuestID) } }
$ours = @{}
foreach ($q in $records) { $ours[[int]$q.id] = $q }
$candidates = Get-SampleCandidates $probe $questTuning.ByQuest $ceilings
$stored = @(Read-TuningData $DataDir)
$sampled = Get-TuningSamples $used $redirects $ceilings $candidates $ours $questV2 $unavailable $Samples $stored
$records3 = @($sampled.Records | Where-Object { $_.samples.Count -ge 3 }).Count
$records2 = @($sampled.Records | Where-Object { $_.samples.Count -eq 2 }).Count
$records1 = @($sampled.Records | Where-Object { $_.samples.Count -eq 1 }).Count
Write-Output ("Samples: our quests are on {0:N0} tunings; a redirect names {1:N0} of them, and none the other {2:N0}, whose level is their own range for every character. {3:N0} get samples ({4:N0} with 3 or more, {5:N0} with 2, {6:N0} with 1); {7:N0} that a redirect names get none." -f
    $used.Count, ($sampled.Records.Count + $sampled.Missing.Count), $sampled.Fixed.Count, $sampled.Records.Count, $records3, $records2, $records1, $sampled.Missing.Count)
foreach ($m in $sampled.Missing) { Write-Output ("  no samples: tuning {0} ({1} of our quests): {2}" -f $m.Tuning, $m.Quests, $m.Why) }
$picked = @($sampled.Records | ForEach-Object { $_.samples } | ForEach-Object { $_ })
$kinds = [ordered]@{ ours = 0; v2 = 0; flagged = 0; oneTime = 0; both = 0 }
foreach ($id in $picked) {
    $q = $ours[$id]
    if ($q) { $kinds.ours++; if (-not (Test-RecurringQuest $q)) { $kinds.oneTime++ }; if (Test-BothFactions $q) { $kinds.both++ } }
    if ($questV2.Contains($id)) { $kinds.v2++ }
    if ($unavailable.Contains($id)) { $kinds.flagged++ }
}
$sampledSet = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($t in $sampled.Records) { [void]$sampledSet.Add([int]$t.id) }
$onSampled = @($wantedTuning.Values | Where-Object { $sampledSet.Contains($_) }).Count
Write-Output ("  {0:N0} samples: {1:N0} quests of ours, {2:N0} in QuestV2, {3:N0} one-time, {4:N0} open to both factions, {5:N0} flagged unavailable. The addon gets the tuning of the {6:N0} quests on a sampled tuning (qcQuestTuning); the other {7:N0} with one keep it in the data only." -f
    $picked.Count, $kinds.ours, $kinds.v2, $kinds.oneTime, $kinds.both, $kinds.flagged, $onSampled, ($wantedTuning.Count - $onSampled))
$tuningDiff = Compare-TuningRecords $stored $sampled.Records $probe $questTuning.ByQuest $ceilings
$tuningFileChanged = (ConvertTo-TuningJsonLines $stored) -cne (ConvertTo-TuningJsonLines $sampled.Records)
Write-Output ("  tunings.jsonl: {0:N0} records held, {1:N0} wanted; {2:N0} added, {3:N0} changed, {4:N0} removed; {5:N0} stored samples stay, {6:N0} are no longer ones and {7:N0} give way" -f
    $stored.Count, $sampled.Records.Count, $tuningDiff.Added.Count, $tuningDiff.Changed.Count, $tuningDiff.Removed.Count, $sampled.Kept, $tuningDiff.Stale.Count, $sampled.Displaced.Count)
foreach ($s in ($tuningDiff.Stale | Select-Object -First $Examples)) { Write-Output ("    tuning {0}, sample {1}: {2}" -f $s.Tuning, $s.Quest, $s.Why) }
if ($tuningDiff.Stale.Count -gt $Examples) { Write-Output "    ... and $($tuningDiff.Stale.Count - $Examples) more" }
foreach ($s in ($sampled.Displaced | Select-Object -First $Examples)) { Write-Output ("    tuning {0}, sample {1}: still loaded at its tuning's level, but {2}" -f $s.Tuning, $s.Quest, $s.Why) }
if ($sampled.Displaced.Count -gt $Examples) { Write-Output "    ... and $($sampled.Displaced.Count - $Examples) more that give way" }
if ($tuningDiff.LevelMoved.Count) {
    Write-Output ("  {0:N0} sampled tunings have another level at the cap than tunings.jsonl holds; many at once can mean the probe's character had other redirect bits than the last run's (docs\plans\quest-scaling-redirects.md). Tuning, level before and now, its RedirectEnum values:" -f $tuningDiff.LevelMoved.Count)
    foreach ($m in ($tuningDiff.LevelMoved | Select-Object -First $Examples)) { Write-Output ("    {0}  {1} -> {2}  ({3})" -f $m.Tuning, $m.Old, $m.New, ($m.Redirects -join ', ')) }
    if ($tuningDiff.LevelMoved.Count -gt $Examples) { Write-Output "    ... and $($tuningDiff.LevelMoved.Count - $Examples) more" }
}
$maxKeys = @($wantedOf.Values | Where-Object { $null -ne $_ }).Count
$hashLimit = 32768
Write-Output ("Lua tables: qcQuestMaxLevel {0:N0} keys and qcQuestTuning {1:N0}, {2:N0} and {3:N0} under {4:N0}; above it Lua 5.1 doubles a table's hash part, about 1 MB more loaded (docs\plans\load-and-memory.md)  [{5}]" -f
    $maxKeys, $onSampled, ($hashLimit - $maxKeys), ($hashLimit - $onSampled), $hashLimit, $(if ($maxKeys -gt $hashLimit -or $onSampled -gt $hashLimit) { 'OVER' } else { 'ok' }))

if ($UpdateBaseline) {
    [IO.File]::WriteAllText($BaselineFile, (ConvertTo-RedirectBaselineText $redirects $Build), (New-Object Text.UTF8Encoding $true))
    Write-Output "Baseline written: $($redirects.ByEnum.Count) RedirectEnum values, $($redirects.Rows) rows of $Build -> $([IO.Path]::GetFullPath($BaselineFile))"
}
$dataChanges = $changes.Count + $tuningChanges.Count + [int]$tuningFileChanged
$what = "$($changes.Count) maxLevel and $($tuningChanges.Count) tuning changes" + $(if ($tuningFileChanged) { ', and tunings.jsonl' } else { '' })
if ($Check) {
    $failed = @()
    if ($dataChanges) { $failed += "the data isn't what the sources say ($what): run Apply-QuestScaling.ps1 (-WhatIf first)" }
    if ($redirectCheck.New.Count) { $failed += "the redirect table has RedirectEnum values its baseline lacks ($($redirectCheck.New -join ', ')): look at them, then -UpdateBaseline" }
    if ($failed.Count) { Write-Output ("Check failed: " + ($failed -join '; ') + '.'); exit 1 }
}
if ($dataChanges -eq 0) {
    Write-Output "Nothing to change: every quest's maxLevel and tuning, and tunings.jsonl, are what the sources say."
    exit 0
}
if ($WhatIf) {
    Write-Output "-WhatIf: nothing was written ($what)."
    exit 0
}

foreach ($ch in $changes) { Set-RecordField $ch.Quest 'maxLevel' $ch.New }
foreach ($ch in $tuningChanges) { Set-RecordField $ch.Quest 'tuning' $ch.New }
Save-QuestData $records $DataDir $AddonDir $sampled.Records
$entries = @($records | Where-Object { $null -ne $_.maxLevel }).Count
$tunedNow = @($records | Where-Object { $null -ne $_.tuning }).Count
$changedQuests = @(@($changes | ForEach-Object { $_.Id }) + @($tuningChanges | ForEach-Object { $_.Id }) | Select-Object -Unique).Count
Write-Output "Saved: $changedQuests quests changed, $entries quests now hold a maxLevel and $tunedNow a tuning; tunings.jsonl holds $($sampled.Records.Count) tunings."
