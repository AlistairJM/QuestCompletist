<#
Puts the quest giver notes the addon's recorder made (QuestCompletist\qcRecorder.lua; plans\quest-giver-recorder.md)
into the pins and the ledger, for both games.

It reads, with Read-RecordedGivers.lua, which refuses anything that is not plain data:
  tools\recordings\own\retail\QuestCompletist.lua      the maintainer's retail file   (source "own")
  tools\recordings\own\forever\QuestCompletist.lua     the maintainer's Forever file  (source "own")
  tools\recordings\players\<tag>\QuestCompletist.lua   a player's file; <tag> is a label such as p01
  tools\*_probe_*\QCForeverProbe.lua                   the probes' files               (source "own")
A file counts for the game its builds say (12.x is retail, 1.x Forever), whatever folder it is in, and
only if its builds are in -Builds (by default the versions the TOCs name: 12.1. and 1.60.). Copy a
saved-variables file in after logging out fully (maintenance.md, "In the game"). A file that cannot be
read is named in the report and the run goes on without it.

What it keeps is in the ledger, plans\recorded-quest-givers.csv: every giver, every place it was seen,
every quest it offered or took in, and every quest that started away from a giver, with the sources that
saw each. It only grows; a file read again replaces its own numbers. A fact is acted on when "own" saw it
or two different players did; a lone player's file decides nothing (not a name, not a place, not how often
it was seen). -ForgetTag p07 takes a source out of the ledger and skips its file for this run: delete the
file as well, or the next run reads it again.

On retail's pins (data\pins.jsonl) it does two things, and nothing else:
  - a pin with no NPC ID gets the ID, and the name if it has none, of a creature that offered one of its
    quests and stood within 1.5 map points of the pin, when the pin's name (if any) is that creature's.
    A pin of an object's quest gets the object's name. Where the game gave the recorder no position (an
    instance) the case is listed, not filled.
  - a quest with no pin gets one at the place a trusted giver of it was most seen, or joins the pin that
    giver already has within 1.5 points (a giver with no trusted English name gets a pin with no NPC and
    no name, which a later run fills). Up to six givers. A quest that is a world, bonus or hidden quest
    (a task of those kinds), flagged unavailable, in a system category, or named like a test does not.
    The other holds the TrinityCore pass puts on a quest (not in QuestV2, a task of another kind, Landfall,
    a holiday, a profession, a quest type other than 0, 1, 2, 4 and 128) are waived, because a creature
    offering the quest answers them; the report counts the quests by class.
It never moves a pin, never changes an ID or a name that is there, never takes a quest off a pin, and
saves no pin if any of that would happen. A fill that would put two pins of one NPC (or of one object name)
1.5 points or less apart, but not on one spot, is not made: the pipeline would merge them and move one pin's
quests. Everything else is in the report, for a person: a pin that names another NPC than the one recorded at
it, a quest offered away from its pins, a pin at a hand-in, names the trusted sources disagree on, masks the
notes contradict, and more. A case looked at that stays as it is goes in plans\recorded-giver-decisions.csv
(Quest, Map, X, Y, Decision KEEP, Reason; a row with only a quest keeps the quest from getting a pin from
here), as in pin-giver-decisions.csv, whose KEEP rows are honoured too. Forever's pins are rebuilt by
Import-ForeverData.ps1 every time, so for Forever it only keeps the ledger and the lists.

Run it after step 6c, then rerun the pin pipeline: a pin that now shares an NPC with another within 1.5
points joins it at the next rebuild. A second run changes nothing. With -WhatIf it only reports (and
writes the report and the lists beside it).

  .\Import-RecordedGivers.ps1 -WhatIf
  .\Import-RecordedGivers.ps1
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$RecordingsDir = "",
    [string]$LedgerFile = (Join-Path $PSScriptRoot '..\docs\plans\recorded-quest-givers.csv'),
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\recorded-giver-decisions.csv'),
    [string]$GiverDecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\pin-giver-decisions.csv'),
    [string]$NpcIdDecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\pin-npc-id-decisions.csv'),
    [string]$ReportFile = "",
    [string[]]$Builds = @(),
    [string]$ForeverBuild = '',
    [string[]]$ForgetTag = @(),
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\RecordedGivers.ps1"
. "$PSScriptRoot\LatestBuilds.ps1"
$ForeverBuild = Resolve-ProbeBuild $ForeverBuild 'forever' $ToolsDir 'ForeverBuild'
$ReaderScript = Join-Path $PSScriptRoot 'Read-RecordedGivers.lua'
if (-not $RecordingsDir) { $RecordingsDir = Join-Path $ToolsDir 'recordings' }
if (-not $ReportFile) { $ReportFile = Join-Path $ToolsDir 'recorded-giver-report.txt' }
if ($Builds.Count -eq 0) { $Builds = @(Get-TocVersions $AddonDir) }
if ($Builds.Count -eq 0) { throw "No versions to read: pass -Builds, or give -AddonDir the TOCs." }
$ForgetTag = @($ForgetTag | ForEach-Object { ConvertTo-RecordedTag $_ })

# --- What the game has: maps and quests, per game -------------------------------------------------
$MapIds = @{ retail = (New-Object 'System.Collections.Generic.HashSet[int]'); forever = (New-Object 'System.Collections.Generic.HashSet[int]') }
$mapTables = @(@('retail', (Join-Path $ToolsDir 'UiMap.csv'), 'step 5'), @('forever', (Join-Path $ToolsDir "UiMap-$ForeverBuild.csv"), "Import-ForeverData.ps1, or https://wago.tools/db2/UiMap/csv?build=$ForeverBuild"))
foreach ($table in (Get-ChildItem (Join-Path $ToolsDir 'UiMap-12.*.csv') -ErrorAction SilentlyContinue)) { $mapTables += , @('retail', $table.FullName, 'step 5') }
foreach ($pair in $mapTables) {
    if (-not (Test-Path $pair[1])) { throw "There's no $($pair[1]) (maintenance.md: $($pair[2]))." }
    foreach ($row in (Import-Csv $pair[1])) { [void]$MapIds[$pair[0]].Add([int]$row.ID) }
}
$retailQuests = Read-QuestData $DataDir
$foreverDir = Join-Path (Resolve-Path $DataDir).Path 'forever'
$foreverQuests = if (Test-Path (Join-Path $foreverDir 'quests.jsonl')) { Read-QuestData $foreverDir } else { @() }
$foreverPins = if (Test-Path (Join-Path $foreverDir 'pins.jsonl')) { Read-PinData $foreverDir } else { @() }
$QuestIds = @{ retail = (New-Object 'System.Collections.Generic.HashSet[int]'); forever = (New-Object 'System.Collections.Generic.HashSet[int]') }
$questByGame = @{ retail = @{}; forever = @{} }
foreach ($q in $retailQuests) { [void]$QuestIds.retail.Add([int]$q.id); $questByGame.retail[[int]$q.id] = $q }
foreach ($q in $foreverQuests) { [void]$QuestIds.forever.Add([int]$q.id); $questByGame.forever[[int]$q.id] = $q }
$questById = $questByGame.retail

# --- The files ---------------------------------------------------------------------------------
$sources = New-Object System.Collections.Generic.List[object]
foreach ($game in 'retail', 'forever') {
    $path = Join-Path $RecordingsDir "own\$game\QuestCompletist.lua"
    if (Test-Path $path) { $sources.Add([pscustomobject]@{ Tag = "own-$game"; Path = $path }) }
}
foreach ($dir in (Get-ChildItem (Join-Path $RecordingsDir 'players') -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $path = Join-Path $dir.FullName 'QuestCompletist.lua'
    if (-not (Test-Path $path)) { continue }
    if ($dir.Name -notmatch '^[A-Za-z0-9_]{1,24}$' -or $dir.Name -like 'own*') { Write-Warning "players\$($dir.Name): not a tag (letters, digits and _, not starting with own), so it is not read"; continue }
    $sources.Add([pscustomobject]@{ Tag = (ConvertTo-RecordedTag $dir.Name); Path = $path })
}
foreach ($file in (Get-ChildItem "$ToolsDir\*_probe_*\QCForeverProbe.lua" -ErrorAction SilentlyContinue | Sort-Object FullName)) {
    $sources.Add([pscustomobject]@{ Tag = 'own-' + (ConvertTo-RecordedTag $file.Directory.Name); Path = $file.FullName })
}

$ledger = Read-RecordedLedger $LedgerFile
$report = New-Object System.Collections.Generic.List[string]
$report.Add("Import-RecordedGivers.ps1, $(Get-Date -Format 'yyyy-MM-dd')")
$report.Add("Versions read: $($Builds -join ', ')")
$report.Add("")

foreach ($tag in $ForgetTag) {
    $removed = Remove-RecordedTag $ledger $tag
    $report.Add("Forgot source ${tag}: it was in $removed ledger rows. Delete its file too, or the next run reads it again.")
}

$unknownQuests = @{}
$questFacts = New-Object System.Collections.Generic.List[object]
$startFacts = New-Object System.Collections.Generic.List[object]
$flaggedFacts = New-Object System.Collections.Generic.List[object]
foreach ($source in $sources) {
    if ($ForgetTag -contains $source.Tag) { $report.Add("Not read: $($source.Tag): forgotten for this run."); continue }
    try {
        $file = Read-RecordedFile $source.Path $source.Tag $LuaExe $ReaderScript
        $facts = Get-RecordedFacts $file $Builds $MapIds $QuestIds
        if ($facts.Refused) {
            $report.Add("Not read: $($source.Tag) ($($source.Path)): $($facts.Refused).")
            continue
        }
        $changes = Add-RecordedFacts $ledger $facts
    } catch {
        $report.Add("Not read: $($source.Tag) ($($source.Path)): $($_.Exception.Message)")
        continue
    }
    $dropped = ($facts.Dropped.GetEnumerator() | Where-Object { $_.Value -gt 0 } | ForEach-Object { "$($_.Value) with $($_.Key) it does not read" }) -join ', '
    $report.Add("Read $($source.Tag): $($facts.Game), $($file.Kind), $($file.Records) records ($($file.Odd) odd), $($facts.Givers.Count) givers, $($facts.Spots.Count) spots, $($facts.Offers.Count) offers, $($facts.Turnins.Count) turn-ins, $($facts.Quests.Count) quest records, $($facts.Starts.Count) starts; $changes ledger rows new or changed$(if ($dropped) { "; left out: $dropped" })")
    if ($facts.DroppedMaps.Count -gt 0) { $report.Add("  maps its table lacks (download a newer UiMap, maintenance.md step 5): $(($facts.DroppedMaps.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name) ($($_.Value))" }) -join ', ')") }
    foreach ($u in $facts.UnknownQuests) { $unknownQuests["$($facts.Game)|$($u.Quest)|$($source.Tag)"] = [pscustomobject]@{ Game = $facts.Game; Quest = $u.Quest; Role = $u.Role; Source = $source.Tag } }
    foreach ($q in $facts.Quests) { $questFacts.Add([pscustomobject]@{ Game = $facts.Game; Tag = $source.Tag; Fact = $q }) }
    foreach ($s in $facts.Starts) { $startFacts.Add([pscustomobject]@{ Game = $facts.Game; Tag = $source.Tag; Fact = $s }) }
    foreach ($f in $facts.Flagged) { $flaggedFacts.Add([pscustomobject]@{ Game = $facts.Game; Tag = $source.Tag; Fact = $f }) }
}
if ($sources.Count -eq 0) { $report.Add("No files: nothing in $RecordingsDir\own, $RecordingsDir\players or $ToolsDir\*_probe_*.") }

# --- The ledger -----------------------------------------------------------------------------------
$report.Add("")
foreach ($game in 'retail', 'forever') {
    $rows = @($ledger.Values | Where-Object { $_.Game -eq $game })
    $trusted = @($rows | Where-Object { Test-RecordedTrusted $_ }).Count
    $report.Add("Ledger, ${game}: $($rows.Count) rows ($(@($rows | Group-Object Role | Sort-Object Name | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', ')); $trusted trusted, $($rows.Count - $trusted) waiting for a second source.")
}
if (-not $WhatIf) {
    if (Save-RecordedLedger $ledger $LedgerFile) { $report.Add("The ledger was written: $LedgerFile") } else { $report.Add("The ledger is as it was.") }
}

# --- What a quest may be pinned for -------------------------------------------------------------
$decisions = Read-RecordedDecisions $DecisionsFile
# What pin-giver-decisions.csv says stays (KEEP) stays here too, and a pin whose ID pin-npc-id-decisions.csv took off is not given one.
if (Test-Path $GiverDecisionsFile) {
    foreach ($row in (Import-Csv $GiverDecisionsFile -Encoding UTF8)) {
        if ($row.Decision -eq 'KEEP') { [void]$decisions.Add("$($row.Quest)|$($row.Map)|$(Format-PinNumber $row.X)|$(Format-PinNumber $row.Y)") }
    }
}
$clearedPins = New-Object System.Collections.Generic.HashSet[string]
if (Test-Path $NpcIdDecisionsFile) {
    foreach ($row in (Import-Csv $NpcIdDecisionsFile -Encoding UTF8)) {
        if ($row.Action -eq 'ID' -and -not $row.NewId) { [void]$clearedPins.Add("$($row.Map)|$(Format-PinNumber $row.X)|$(Format-PinNumber $row.Y)") }
    }
}
$unavailable = New-Object System.Collections.Generic.HashSet[int]
$unavailableFile = Join-Path $AddonDir 'qcUnavailableQuests.lua'
if (Test-Path $unavailableFile) { foreach ($m in [regex]::Matches([IO.File]::ReadAllText($unavailableFile), '\[(\d+)\]=')) { [void]$unavailable.Add([int]$m.Groups[1].Value) } }
$taskKind = @{}
$taskFile = Join-Path $ToolsDir 'QuestV2CliTask.csv'
$infoFile = Join-Path $ToolsDir 'QuestInfo.csv'
$questV2File = Join-Path $ToolsDir 'QuestV2.csv'
$haveTasks = (Test-Path $taskFile) -and (Test-Path $infoFile)
$systemInfo = New-Object System.Collections.Generic.HashSet[string]
if ($haveTasks) {
    foreach ($row in (Import-Csv $taskFile)) { $taskKind[[int]$row.ID] = [string]$row.QuestInfoID }
    foreach ($row in (Import-Csv $infoFile)) {
        if ($row.InfoName_lang -match 'World Quest|Emissary|Hidden Quest|Delve|Warfront Contribution|Envoy|Meta Quest|Professions|Pickpocketing|War Mode|Tracking|Bonus Objective') { [void]$systemInfo.Add([string]$row.ID) }
    }
}
$questV2 = $null
if (Test-Path $questV2File) {
    $questV2 = New-Object System.Collections.Generic.HashSet[int]
    foreach ($row in (Import-Csv $questV2File)) { [void]$questV2.Add([int]$row.ID) }
}
$systemCategories = @(170, 173, 191, 290, 1092, 1095, 1130, 1133, 1134, 1232, 1241, 1246, 1346, 1347, 1428, 1429, 1430, 1431, 1514, 1735)
# System categories whose quests may be pinned when a creature offers them. Empty until a person decides one.
$allowedSystemCategories = @()
$holidayCategories = @(31, 37, 46, 50, 90, 126, 127, 133, 145, 153, 413)
$internalName = '\[DNT\]|\bDNT\b|\bTBD\b|\bDEPRECATED\b|^Test$|Test Quest$|Flight Test$|\bJrz\b|\bPlaceholder\b|^Blank$|^(Conditional Objectives|Prey Contract:|Paragon of |Bonus Objective:)|\[WIP\]|^LFGDungeons|This Is Not a Quest'
$isPinnable = {
    param([int]$quest)
    if (-not $haveTasks) { return 'QuestV2CliTask.csv or QuestInfo.csv is missing (maintenance.md, step 1b)' }
    $q = $questById[$quest]
    if (-not $q) { return 'not in our data' }
    if ($unavailable.Contains($quest)) { return 'flagged unavailable' }
    if ($q.name -match $internalName) { return 'internal name' }
    if ($taskKind.ContainsKey($quest) -and $systemInfo.Contains($taskKind[$quest])) { return 'a world, bonus or hidden quest' }
    if ($systemCategories -contains [int]$q.category -and $allowedSystemCategories -notcontains [int]$q.category) { return "system category $($q.category)" }
    return $null
}
# What the TrinityCore pass would have held a pinned quest back for, for the report.
$waivedClass = {
    param([int]$quest)
    $q = $questById[$quest]
    $classes = New-Object System.Collections.Generic.List[string]
    if ($null -ne $questV2 -and -not $questV2.Contains($quest)) { $classes.Add('not in QuestV2') }
    if ($taskKind.ContainsKey($quest)) { $classes.Add('task quest (not a world or bonus kind)') }
    if ([int]$q.category -eq 121) { $classes.Add('Landfall') }
    if ($q.holiday -or $holidayCategories -contains [int]$q.category) { $classes.Add('holiday') }
    if ($q.profession) { $classes.Add('profession') }
    if (@(0, 1, 2, 4, 128) -notcontains [int]$q.type) { $classes.Add("quest type $($q.type)") }
    return $classes.ToArray()
}

# --- The pins -------------------------------------------------------------------------------------
$model = Get-RecordedModel $ledger 'retail'
$pins = New-Object System.Collections.Generic.List[object]
foreach ($pin in (Read-PinData $DataDir)) { $pins.Add($pin) }
$plan = Get-RecordedPlan $model $pins $isPinnable $decisions $clearedPins
$snapshot = Get-PinSnapshot $pins
$insertAfter = {
    param($list, $pin)
    for ($i = $list.Count - 1; $i -ge 0; $i--) { if ([int]$list[$i].map -le [int]$pin.map) { return $i + 1 } }
    return 0
}
# The profession icon when every quest on a new pin has a profession, as Apply-ClientQuestGivers.ps1 does.
$iconFor = {
    param($quests)
    foreach ($quest in $quests) { $q = $questById[[int]$quest]; if (-not $q -or -not $q.profession) { return 1 } }
    return 3
}
$done = Invoke-RecordedPlan $plan $pins $insertAfter $iconFor
$problems = @(Test-RecordedChangeSafe $snapshot $pins)
$review = New-Object System.Collections.Generic.List[object]
foreach ($item in $plan.Review) { $review.Add($item) }
foreach ($item in (Get-RecordedReview $model $pins $decisions $unavailable)) { $review.Add($item) }

$report.Add("")
$report.Add("Retail pins: $($plan.Fills.Count) get an NPC ID or a name; $($done.Joined) quests join a pin, $($done.Created) new pins.")
foreach ($fill in $plan.Fills) { $report.Add("  fill  $($fill.Where): $($fill.GiverKey) '$($fill.Name)' (quests $($fill.Quests -join ', '))") }
$classCount = @{}
$addedQuests = New-Object System.Collections.Generic.HashSet[int]
foreach ($add in $plan.Adds) {
    $classes = @(& $waivedClass $add.Quest)
    if ($addedQuests.Add($add.Quest)) { foreach ($c in $classes) { $classCount[$c] = 1 + [int]$classCount[$c] } }
    $report.Add("  add   quest $($add.Quest): $($add.Giver.Key) '$($add.Giver.Name)' at map $($add.Place.Map) $(Format-PinNumber $add.Place.X),$(Format-PinNumber $add.Place.Y)$(if ($add.Others -gt 0) { " ($($add.Others) other places in the ledger)" })$(if ($classes.Count -gt 0) { " [held back by the pipeline as: $($classes -join ', ')]" })")
}
if ($addedQuests.Count -gt 0) {
    $report.Add("  quests given a pin, by what the TrinityCore pass would have held them for (a quest counts under each class it has): $(if ($classCount.Count -gt 0) { (($classCount.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Value)" }) -join ', ') } else { 'none' }); $($addedQuests.Count) quests in all$(if ($null -eq $questV2) { '; QuestV2.csv is missing, so that class is not counted' })")
}
foreach ($note in $done.Notes) { $report.Add("  note  $note") }
$report.Add("")
$report.Add("Left alone (a count of pins for the fills, of quest and giver pairs for the adds):")
foreach ($key in $plan.Skipped.Keys) { $report.Add("  $($plan.Skipped[$key])  $key") }
if ($model.NameConflicts.Count -gt 0) {
    $report.Add("")
    $report.Add("$($model.NameConflicts.Count) givers whose trusted sources give more than one name (no name is used for them):")
    foreach ($c in $model.NameConflicts) { $report.Add("  $($c.Giver): $($c.Names)") }
}
$report.Add("")
$report.Add("For review ($($review.Count)):")
foreach ($r in ($review | Sort-Object Kind, { [int]("0" + $_.Quest) }, Where)) { $report.Add("  $($r.Kind): quest $($r.Quest) $($r.Where): $($r.Detail)") }

# The lists beside the report, one file each, gone when empty. A fact a lone player gave is marked.
function Write-RecordedList([string]$name, $rows) {
    $path = Join-Path $ToolsDir $name
    $list = @($rows | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) { Remove-Item $path -ErrorAction SilentlyContinue; return }
    $list | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
}
function Get-Trust($tags) {
    $classes = New-ClassSet
    foreach ($tag in $tags) { [void]$classes.Add((Get-RecordedClass $tag)) }
    return $(if ($classes.Contains('own') -or $classes.Count -ge 2) { 'trusted' } else { 'waiting' })
}

# Per game and quest: the masks, recurrences and headings the files give, and who gave them.
$byQuest = @{}
foreach ($entry in $questFacts) {
    $key = "$($entry.Game)|$($entry.Fact.Quest)"
    if (-not $byQuest.ContainsKey($key)) {
        $byQuest[$key] = @{ Game = $entry.Game; Quest = $entry.Fact.Quest; Faction = [long]0; Race = [long]0; Class = [long]0; Tags = (New-Object System.Collections.Generic.HashSet[string])
            Freq = (New-Object System.Collections.Generic.HashSet[string]); Rep = (New-Object System.Collections.Generic.HashSet[string]); Heading = (New-Object System.Collections.Generic.HashSet[string]) }
    }
    $b = $byQuest[$key]
    $b.Faction = $b.Faction -bor $entry.Fact.Faction; $b.Race = $b.Race -bor $entry.Fact.Race; $b.Class = $b.Class -bor $entry.Fact.Class
    [void]$b.Tags.Add($entry.Tag)
    if ($entry.Fact.Frequency -ne '') { [void]$b.Freq.Add($entry.Fact.Frequency) }
    if ($entry.Fact.Repeatable -ne '') { [void]$b.Rep.Add($entry.Fact.Repeatable) }
    if ($entry.Fact.Heading -ne '') { [void]$b.Heading.Add($entry.Fact.Heading) }
}
$maskRows = New-Object System.Collections.Generic.List[object]
$typeRows = New-Object System.Collections.Generic.List[object]
$headingRows = New-Object System.Collections.Generic.List[object]
foreach ($key in ($byQuest.Keys | Sort-Object { $_ })) {
    $b = $byQuest[$key]
    $data = $questByGame[$b.Game][[int]$b.Quest]
    if (-not $data) { continue }
    $from = (($b.Tags | Sort-Object) -join ' ')
    $trust = Get-Trust $b.Tags
    foreach ($pair in @(@('faction', $b.Faction, [long]$data.faction), @('race', $b.Race, [long]$data.race), @('class', $b.Class, [long]$data.class))) {
        if ($pair[2] -ne 0 -and (([long]$pair[1] -band (-bnot [long]$pair[2])) -band 0x7FFFFFFF) -ne 0) {
            $maskRows.Add([pscustomobject]@{ Game = $b.Game; Quest = $b.Quest; Name = $data.name; Mask = $pair[0]; InData = $pair[2]; Recorded = $pair[1]; Sources = $from; Trust = $trust })
        }
    }
    $expected = $null; $said = ''
    if ($b.Freq.Count -gt 1) { $said = "conflict: frequency $(($b.Freq | Sort-Object) -join ' / ')" }
    elseif ($b.Freq.Count -eq 1) {
        $f = @($b.Freq)[0]
        if ($f -eq '1') { $expected = 4; $said = 'daily' }
        elseif ($f -eq '2' -or $f -eq '3') { $expected = 128; $said = 'weekly' }
        elseif ($f -eq '0' -and $b.Rep.Count -gt 1) { $said = 'conflict: repeatable' }
        elseif ($f -eq '0' -and $b.Rep.Count -eq 1) {
            if (@($b.Rep)[0] -eq '1') { $expected = 2; $said = 'repeatable' } else { $expected = 1; $said = 'one-time' }
        }
    }
    if ($said.StartsWith('conflict') -or ($expected -and [int]$data.type -ne $expected -and -not ($expected -eq 1 -and [int]$data.type -eq 0))) {
        $typeRows.Add([pscustomobject]@{ Game = $b.Game; Quest = $b.Quest; Name = $data.name; Type = $data.type; Recorded = $said; Suggested = $(if ($expected) { $expected } else { '' }); Sources = $from; Trust = $trust })
    }
    if ([int]$data.category -eq 0 -and $b.Heading.Count -gt 0) {
        $headingRows.Add([pscustomobject]@{ Game = $b.Game; Quest = $b.Quest; Name = $data.name; Headings = (($b.Heading | Sort-Object) -join ' / '); Sources = $from; Trust = $trust })
    }
}
$report.Add("")
$report.Add("$($maskRows.Count) quest masks the notes contradict (a character was offered a quest the data's mask excludes; tools\recorded_mask_contradictions.csv).")
$flaggedBy = @($flaggedFacts | Where-Object { $_.Game -eq 'retail' } | Group-Object { $_.Fact.Quest } | Sort-Object { [int]$_.Name })
if ($flaggedBy.Count -gt 0) {
    $report.Add("$($flaggedBy.Count) quests flagged unavailable that a player accepted or turned in (qcFlaggedButSeen): $(($flaggedBy | ForEach-Object { $_.Name }) -join ', ')")
}
$pinnedQuests = @{ retail = (New-Object System.Collections.Generic.HashSet[int]); forever = (New-Object System.Collections.Generic.HashSet[int]) }
foreach ($pin in $pins) { foreach ($quest in $pin.quests) { [void]$pinnedQuests.retail.Add([int]$quest) } }
foreach ($pin in $foreverPins) { foreach ($quest in $pin.quests) { [void]$pinnedQuests.forever.Add([int]$quest) } }
$startRows = New-Object System.Collections.Generic.List[object]
foreach ($entry in ($startFacts | Sort-Object Game, { $_.Fact.Quest }, Tag)) {
    $s = $entry.Fact
    $startRows.Add([pscustomobject]@{ Game = $entry.Game; Quest = $s.Quest; Name = $questByGame[$entry.Game][[int]$s.Quest].name; StartKind = $s.StartKind; Item = $s.Item; Map = $s.Map; X = $s.X; Y = $s.Y
        Pinned = $pinnedQuests[$entry.Game].Contains([int]$s.Quest); Source = $entry.Tag })
}
Write-RecordedList 'recorded_unknown_quests.csv' ($unknownQuests.Values | Sort-Object Game, { [int]$_.Quest }, Source)
Write-RecordedList 'recorded_mask_contradictions.csv' $maskRows
Write-RecordedList 'recorded_quest_types.csv' $typeRows
Write-RecordedList 'recorded_headings.csv' $headingRows
Write-RecordedList 'recorded_start_items.csv' $startRows
$report.Add("")
$report.Add("Beside the report: $($unknownQuests.Count) offers for quests the data lacks (recorded_unknown_quests.csv), $($typeRows.Count) quests whose recorded recurrence is not their type or disagrees (recorded_quest_types.csv), $($headingRows.Count) unplaced quests with a log heading (recorded_headings.csv), $($startRows.Count) quests that started away from a giver (recorded_start_items.csv). Each has a Game column and the sources.")

[IO.File]::WriteAllLines($ReportFile, $report)
if ($problems.Count -gt 0) {
    throw ("No pin was saved: the change would not be only what this tool means to make.`n  " + ($problems -join "`n  "))
}
Write-Output "$($plan.Fills.Count) pins filled, $($done.Joined) quests joined a pin, $($done.Created) pins new; $($review.Count) cases for review."
Write-Output "Report: $ReportFile"
if ($WhatIf) { Write-Output "WhatIf: nothing changed."; exit 0 }
if ($plan.Fills.Count -gt 0 -or $done.Joined -gt 0 -or $done.Created -gt 0) { Save-PinData $pins.ToArray() $DataDir $AddonDir }
