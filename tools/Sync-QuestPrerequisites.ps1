<#
Sets the quests' prerequisites (prereq in data\quests.jsonl) from the sources step 2b checks them
against, as decided with the user on 6 October 2026:
  - Blizzard's API, where it names required quests: its list replaces ours. Its AND/OR tree becomes
    a list that all must be done, with a choice (one of them will do) as a list inside it. It names
    at most 3 quests, though, and often leaves out the step just before the quest in its
    storyline, so a quest of ours it leaves out stays when it's that step (28 of 29 were, in
    October 2026).
  - TrinityCore's previous quest (PrevQuestID), for a quest that has no prerequisite and that the
    API is silent on, when it's the step just before the quest in the quest's own Blizzard
    storyline (the client's QuestLineXQuest for -Build).
  - The client's own task-quest tables, as decided on 7 October 2026, for a task quest (a world
    quest, bonus objective, calling and the like), which the API doesn't serve. QuestV2CliTask
    names quests that must be done (FiltCompletedQuest), and its PlayerCondition (ConditionID)
    quests the character must have turned in (PrevQuestID); both are required at once. Each is up
    to four quests with a logic field, read as the game reads a PlayerCondition's: bit 16+n turns
    the nth answer round (a quest that must NOT be done), and two bits each say how the next quest
    joins the answer so far, from left to right: 1 and, 2 or, 0 not at all. Since 17 October 2026
    (the client tables audit, opportunity 4) the condition's ModifierTree is read as well, as
    QuestConditions.ps1 reads a quest line's, the quests it names joining the others; a tree that
    can't be met as read is left out. Where the client's
    list leaves us something to show, it replaces ours, except that one of ours stays when it's the
    step just before the quest in its storyline, as with the API's list. A quest that must not be
    done is no prerequisite. A quest we hold no data for (a hidden tracking quest, with no name to
    show) can't be told to the player: as a quest to do first it's left out, and as one of several
    that will do it takes the whole choice with it, as another way needs nothing we could show.
    The tables are those step 1b refreshes (QuestV2CliTask.csv and PlayerCondition.csv in
    -ToolsDir); they're fetched for -Build when missing, as are the ModifierTree and the others
    QuestConditions.ps1 reads.
A quest the API and the client are silent on keeps its prerequisite.

Then, as decided with the user on 12 October 2026 (QuestConditions.ps1 reads the client's tables):
  - The current expansion's campaign (-Campaign): each chapter's first quest needs the last quest of
    the chapter before, where the API is silent on it. The zone campaigns the Scouting Map offers
    in any order (-ScoutingMapLine) need what its quest (-ScoutingMapQuest) needs instead.
  - The client's conditions on the expansion's quest lines and other campaigns: a quest on one that
    needs no other quest of it gets the condition as well, the hidden quest 90806 included.
  - A required quest the game offered together with the quest, in the probe's map pass for -Build
    (-OffersFile), isn't one: it wasn't done, and the game offered the quest all the same.
  - The client's own follow-ups (the quest cache's RewardNextQuest, tools\retail_quest_cache_<Build>.jsonl
    from step 2e, or -QuestCacheFile) for a quest with no other requirement that the API is silent
    on, where TrinityCore's requirement (its NextQuestID or PrevQuestID) says the same: any one of
    them will do. Where TrinityCore names none the follow-up is often a re-offer, not a requirement
    (1 in 4 where it has a row, October 2026), so those aren't taken. Nor is a breadcrumb into the
    quest (qcBreadcrumbQuests): the game offers the quest to a character who skipped it. A cache
    that looks partial (QuestCacheFiles.ps1) is warned about: its gaps are follow-ups not taken.
Last, the prerequisites decided with the user (-DecisionsFile, docs\plans\quest-link-decisions.csv,
in the columns of WoW: Forever's link decisions) replace whatever the sources give: a quest's prereq
SET rows name the quest it needs, and several rows for one quest are a choice; a prereq NONE row (Other
0) says it needs none. The run lists any the sources would give something else, so a sweep sees when
Blizzard starts to name one.

A one-time quest's required quest that recurs (daily, weekly or repeatable) is left out: the game
only knows such a quest is done until the next reset, so the map would hide the one-time quest
again. A choice that offers one is left out whole. A recurring quest keeps a recurring
requirement only where Blizzard's API or the client's task tables name it, as in a chain of world
quests, which the game knows within the day or week; our own and TrinityCore's would hide the later
quest after every reset. A requirement that would make two quests each require the other is left
out too, and listed.

With -WhatIf it only reports. Otherwise it saves through AddonData.ps1, which rebuilds the Lua.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = "12.1.5.70391",
    [string]$TdbFile = "",
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [int]$Campaign = 270,
    [int]$ScoutingMapLine = 6131,
    [int]$ScoutingMapQuest = 95008,
    [string]$OffersFile = "",
    [string]$QuestCacheFile = "",
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-link-decisions.csv'),
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\QuestConditions.ps1"
. "$PSScriptRoot\QuestCacheFiles.ps1"

$records = Read-QuestData $DataDir
$quests = @{}
foreach ($q in $records) { $quests[[int]$q.id] = $q }
function Test-Recurring([int]$id) { return $quests.ContainsKey($id) -and ($quests[$id].type -band (2 + 4 + 128)) }
# Whether $prereq can stand as $id's prerequisite: a quest that recurs only for one that recurs too, as
# within a day or week the game knows it's done.
function Test-Checkable([int]$id, [int]$prereq) { return (Test-Recurring $id) -or -not (Test-Recurring $prereq) }

# Blizzard's tree, simplified: a quest ID, or a group (And, and its Items) holding quests and groups
# of the other kind, as one inside another of the same kind joins it, and one of a single item is
# that item. $null when nothing usable is left; 'recurring' for a choice that can't be checked.
function Convert-ApiNode($node) {
    if ($node.target) {
        if ($node.must_be_incomplete) { return $null }
        $id = [int]$node.target.id
        if (-not (Test-Checkable $script:converting $id)) { return 'recurring' }
        return $id
    }
    $isAnd = $node.operator.type -eq 'AND'
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($child in $node.conditions) {
        $item = Convert-ApiNode $child
        if ($null -eq $item) { continue }
        if ($item -is [string]) { if ($isAnd) { continue } else { return 'recurring' } }
        if ($item -is [pscustomobject] -and $item.And -eq $isAnd) { foreach ($x in $item.Items) { $items.Add($x) } }
        else { $items.Add($item) }
    }
    if ($items.Count -eq 0) { return $null }
    if ($items.Count -eq 1) { return $items[0] }
    return [pscustomobject]@{ And = $isAnd; Items = $items.ToArray() }
}
$api = @{}
$cache = Join-Path $ToolsDir 'quest_api_cache'
foreach ($file in (Get-ChildItem $cache -Filter *.json | Select-String -Pattern '"quests":\{"operator"' -List | Select-Object -ExpandProperty Path)) {
    $json = [IO.File]::ReadAllText($file) | ConvertFrom-Json
    $id = [int]$json.id
    if (-not $quests.ContainsKey($id)) { continue }
    $script:converting = $id
    $api[$id] = ConvertTo-PrereqValue (Convert-ApiNode $json.requirements.quests)
}

# The client's task quests. A group of the simplified tree with its leaves joined as the game joins
# them: $null (nothing to show) stands for an answer that's always yes, so it drops out of an AND and
# takes the whole OR with it.
function Join-Nodes([bool]$isAnd, $a, $b) {
    if ($null -eq $a) { if ($isAnd) { return $b } else { return $null } }
    if ($null -eq $b) { if ($isAnd) { return $a } else { return $null } }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($node in @($a, $b)) {
        $parts = if ($node -is [pscustomobject] -and $node.And -eq $isAnd) { $node.Items } else { @($node) }
        foreach ($part in $parts) { if ($part -is [pscustomobject] -or $items -notcontains $part) { $items.Add($part) } }
    }
    if ($items.Count -eq 1) { return $items[0] }
    return [pscustomobject]@{ And = $isAnd; Items = $items.ToArray() }
}
# One of the client's lists of quests (FiltCompletedQuest, or a PlayerCondition's PrevQuestID) with
# its logic field, as a tree; $null when it leaves nothing to show.
function Convert-ClientList($row, [string]$prefix, [int]$count, [string]$logicField) {
    $logic = [int64]$row.$logicField
    $answer = $null
    for ($i = 0; $i -lt $count; $i++) {
        $id = [int]$row.("${prefix}_$i")
        $item = $null
        if ($id -gt 0 -and -not ($logic -band (0x10000 -shl $i))) {
            if (-not $quests.ContainsKey($id)) { $script:notInData[$id] = $true }
            elseif (Test-Checkable $script:converting $id) { $item = $id }
        }
        if ($i -eq 0) { $answer = $item; continue }
        $how = [int](($logic -shr (2 * ($i - 1))) -band 3)
        if ($how -eq 1) { $answer = Join-Nodes $true $answer $item }
        elseif ($how -eq 2) { $answer = Join-Nodes $false $answer $item }
    }
    return $answer
}

# A condition's tree (QuestConditions.ps1) with the quests a task quest can't show dropped as
# Convert-ClientList drops them.
function Select-TaskQuests($node) {
    if ($null -eq $node) { return $null }
    if (-not (Test-ConditionGroup $node)) {
        $id = [int]$node
        if (-not $quests.ContainsKey($id)) { $script:notInData[$id] = $true; return $null }
        if (-not (Test-Checkable $script:converting $id)) { return $null }
        return $id
    }
    $joined = $null; $first = $true
    foreach ($item in $node.Items) {
        $part = Select-TaskQuests $item
        if ($first) { $joined = $part; $first = $false } else { $joined = Join-Nodes $node.And $joined $part }
    }
    return $joined
}

$path = Join-Path $ToolsDir 'QuestV2CliTask.csv'
if (-not (Test-Path $path)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/QuestV2CliTask/csv?build=$Build" -OutFile $path }
$conditionTables = Import-ClientConditions $ToolsDir $Build
$tasks = @(Import-Csv $path | Where-Object { $quests.ContainsKey([int]$_.ID) })
$script:notInData = @{}
$client = @{}
foreach ($t in $tasks) {
    $script:converting = [int]$t.ID
    $own = Convert-ClientList $t 'FiltCompletedQuest' 3 'FiltCompletedQuestLogic'
    $condition = $null
    $row = $conditionTables.Conditions[[int]$t.ConditionID]
    if ($row -and -not ($row.Flags -band 0x100)) {
        $condition = ConvertFrom-PrevQuests $row
        if ($row.Tree -and -not ($row.Flags -band 0x200)) {
            $tree = ConvertFrom-ModifierTree $conditionTables $row.Tree 1
            if ($tree -isnot [string]) { $condition = Join-Condition $true $condition $tree }
        }
        $condition = Select-TaskQuests $condition
    }
    $value = ConvertTo-PrereqValue (Join-Nodes $true $own $condition)
    if ($null -ne $value) { $client[[int]$t.ID] = $value }
}

$tcPrev = @{}; $tcNext = @{}
if (-not $TdbFile) {
    $TdbFile = Get-ChildItem "$ToolsDir\tdb\TDB_full_world_*.sql" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName
}
if ($TdbFile) {
    $outputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try { $rows = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $TdbFile quest_template_addon '1,5,6') } finally { [Console]::OutputEncoding = $outputEncoding }
    if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $TdbFile" }
    foreach ($row in $rows) {
        $f = $row.Split("`t")
        if ([int]$f[1] -gt 0) { $tcPrev[[int]$f[0]] = [int]$f[1] }
        if ([int]$f[2] -gt 0) { $tcNext[[int]$f[0]] = [int]$f[2] }
    }
}
$lineCsv = "$ToolsDir\QuestLineXQuest-$Build.csv"
if (-not (Test-Path $lineCsv)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/QuestLineXQuest/csv?build=$Build" -OutFile $lineCsv }
$order = @{}
foreach ($row in Import-Csv $lineCsv) { $order["$($row.QuestLineID)|$($row.QuestID)"] = [int]$row.OrderIndex }
function Test-StepJustBefore([int]$id, [int]$prev) {
    $line = [int]$quests[$id].storyline
    if (-not $line) { return $false }
    $a = $order["$line|$prev"]; $b = $order["$line|$id"]
    return ($null -ne $a) -and ($null -ne $b) -and ($b - $a -eq 1)
}
function Test-OtherFaction([int]$a, [int]$b) {
    if (-not ($quests.ContainsKey($a) -and $quests.ContainsKey($b))) { return $false }
    $fa = $quests[$a].faction; $fb = $quests[$b].faction
    return ($fa -eq 1 -and $fb -eq 2) -or ($fa -eq 2 -and $fb -eq 1)
}

# A prereq as the parts that each must be done, and back.
function Get-PrereqParts($value) {
    if ($null -eq $value -or ($value -isnot [array] -and $value -eq 0)) { return , @() }
    return , @($value)
}
function Join-PrereqParts($parts) {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($part in $parts) { $list.Add($part) }
    if ($list.Count -eq 0) { return $null }
    if ($list.Count -eq 1 -and $list[0] -isnot [array]) { return [int]$list[0] }
    return , $list.ToArray()
}
function Get-PartText($part) { return ConvertTo-PrereqText $part '[' ']' }
# A choice that names a quest the same prereq requires anyway is met with it, so it's dropped.
function Remove-MetChoices($value) {
    $parts = Get-PrereqParts $value
    $required = @($parts | Where-Object { $_ -isnot [array] } | ForEach-Object { [int]$_ })
    return Join-PrereqParts @($parts | Where-Object { -not ($_ -is [array] -and @($_ | Where-Object { $_ -isnot [array] -and $required -contains [int]$_ }).Count) })
}

# The client's conditions, as the parts each quest they cover gets: left out where they name a quest
# that recurs and the quest doesn't, as the API's are.
$gates = @(Get-ConditionGates $conditionTables $Campaign $quests)
$chapterLinks = Get-ChapterLinks $conditionTables $Campaign $ScoutingMapLine $ScoutingMapQuest $quests
function Select-Checkable($node, [int]$id) {
    if ($null -eq $node -or $node -is [string]) { return $node }
    if (-not (Test-ConditionGroup $node)) {
        if ($quests.ContainsKey([int]$node) -and -not (Test-Checkable $id ([int]$node))) { return $null }
        return $node
    }
    $joined = $null; $first = $true
    foreach ($item in $node.Items) {
        $part = Select-Checkable $item $id
        if ($first) { $joined = $part; $first = $false } else { $joined = Join-Condition $node.And $joined $part }
    }
    return $joined
}
$gateParts = @{}
foreach ($gate in $gates) {
    foreach ($id in $gate.Quests) {
        if (-not $quests.ContainsKey($id)) { continue }
        $value = ConvertTo-PrereqValue (Select-Checkable $gate.Gate $id)
        if ($null -eq $value) { continue }
        if (-not $gateParts.ContainsKey($id)) { $gateParts[$id] = New-Object System.Collections.Generic.List[object] }
        foreach ($part in (Get-PrereqParts $value)) { $gateParts[$id].Add([pscustomobject]@{ Gate = $gate; Part = $part }) }
    }
}
# Ours without the parts a condition gave it, so each run starts from what the other sources say.
$own = @{}
foreach ($id in $quests.Keys) {
    $parts = Get-PrereqParts $quests[$id].prereq
    if ($gateParts.ContainsKey($id)) {
        $given = @($gateParts[$id] | ForEach-Object { Get-PartText $_.Part })
        $kept = New-Object System.Collections.Generic.List[object]
        foreach ($part in $parts) { if ($given -notcontains (Get-PartText $part)) { $kept.Add($part) } }
        $parts = $kept
    }
    $own[$id] = Join-PrereqParts $parts
}

$new = @{}
$counts = [ordered]@{ fromApiNew = 0; fromApiChanged = 0; fromApiSame = 0; keptApi = 0; fromClientNew = 0; fromClientChanged = 0; fromClientSame = 0; keptClient = 0; fromTrinityCore = 0 }
foreach ($id in ($quests.Keys | Sort-Object)) {
    $q = $quests[$id]
    $ours = if ($own[$id]) { ConvertTo-PrereqText $own[$id] '[' ']' } else { '' }
    $source = ''
    if ($api.ContainsKey($id) -and $null -ne $api[$id]) { $source = 'Api'; $value = $api[$id] }
    elseif ($client.ContainsKey($id) -and -not $api.ContainsKey($id)) { $source = 'Client'; $value = $client[$id] }
    if ($source) {
        # The API names at most 3 quests and often leaves out the step just before the quest in its
        # storyline, and the client names what must be done before a task quest shows, not the chain.
        # One of ours that's missing from the list stays when it's the step just before the quest in
        # its storyline, as it nearly always is.
        $listed = Get-PrereqQuests $value
        $ourQuests = if ($own[$id]) { Get-PrereqQuests $own[$id] } else { @() }
        $kept = @($ourQuests | Where-Object { $listed -notcontains $_ -and (Test-StepJustBefore $id $_) })
        if ($kept.Count) { $value = @($kept) + @($value); $counts["kept$source"]++ }
        if ($source -eq 'Client') { $value = Remove-MetChoices $value }
        $text = ConvertTo-PrereqText $value '[' ']'
        if ($text -eq $ours) { $counts["from${source}Same"]++; continue }
        $new[$id] = $value
        if ($ours) { $counts["from${source}Changed"]++ } else { $counts["from${source}New"]++ }
    } elseif (-not $ours -and -not $api.ContainsKey($id) -and $tcPrev.ContainsKey($id)) {
        $prev = $tcPrev[$id]
        if ($quests.ContainsKey($prev) -and (Test-Checkable $id $prev) -and -not (Test-OtherFaction $id $prev) -and (Test-StepJustBefore $id $prev)) {
            $new[$id] = $prev; $counts.fromTrinityCore++
        }
    }
}
$final = @{}
foreach ($id in $quests.Keys) { if ($new.ContainsKey($id)) { $final[$id] = $new[$id] } else { $final[$id] = $own[$id] } }

$offered = @{}
if (-not $OffersFile) { $OffersFile = Join-Path $ToolsDir ("map_offers_retail_{0}.tsv" -f $Build.Split('.')[-1]) }
if (Test-Path $OffersFile) {
    foreach ($row in Import-Csv $OffersFile -Delimiter "`t") { if ($row.kind -eq 'offer') { $offered[[int]$row.id] = $true } }
} else { "No map pass for $Build at $OffersFile, so no required quest is checked against the game's offers." }

# The client's follow-ups: the quests whose hand-in offers this one next (the quest cache's
# RewardNextQuest), where TrinityCore's requirement says the same. A follow-up the game offered
# together with this quest, that recurs while this doesn't, is the other faction's, is no longer in
# the game, or needs a higher level than this, isn't one.
$unavailable = @{}
foreach ($line in [IO.File]::ReadLines((Join-Path $AddonDir 'qcUnavailableQuests.lua'))) { if ($line -match '^\[(\d+)\]=') { $unavailable[[int]$Matches[1]] = $true } }
$crumbBlock = [regex]::Match([IO.File]::ReadAllText((Join-Path $AddonDir 'qcQuest.lua')), '(?s)(?:^|\n)qcBreadcrumbQuests\s*=\s*\{[^\n]*\n(.*?)\n\}')
if (-not $crumbBlock.Success) { throw "qcQuest.lua has no qcBreadcrumbQuests table." }
$leadsTo = @{}
foreach ($line in (($crumbBlock.Groups[1].Value -replace '(?s)--\[\[.*?\]\]', '' -replace '--[^\n]*', '') -split "`n")) {
    if ($line -notmatch '^\s*\[(\d+)\]\s*=\s*\{([\d,\s]*)\}') { continue }
    $target = $Matches[1]
    foreach ($crumb in ($Matches[2] -split '[,\s]+' | Where-Object { $_ })) { $leadsTo["$crumb>$target"] = $true }
}
$leadIns = New-Object System.Collections.Generic.List[string]
$severalLeadIns = New-Object System.Collections.Generic.List[string]
function Get-MinLevel([int]$id) { if ($null -ne $quests[$id].minLevel) { return [int]$quests[$id].minLevel } return [int]$quests[$id].level }
if (-not $QuestCacheFile) { $QuestCacheFile = Join-Path $ToolsDir "retail_quest_cache_$Build.jsonl" }
$offeredAfter = @{}
if (Test-Path $QuestCacheFile) {
    Get-QuestCacheWarning $QuestCacheFile $quests.Keys
    foreach ($line in [IO.File]::ReadLines($QuestCacheFile)) {
        if ($line -notmatch '"nextQuest":(\d+)') { continue }
        $next = [int]$Matches[1]
        if ($line -match '^\{"id":(\d+)') { $offeredAfter[$next] += @([int]$Matches[1]) }
    }
} else { "No quest cache for $Build at $QuestCacheFile, so no follow-up is taken." }
$followUp = @{}
foreach ($id in $offeredAfter.Keys) {
    if (-not $quests.ContainsKey($id)) { continue }
    $level = Get-MinLevel $id
    $by = New-Object System.Collections.Generic.List[int]
    $unrepeated = 0
    foreach ($source in $offeredAfter[$id]) {
        $a = [int]$source
        if ($a -eq $id -or $by.Contains($a) -or -not $quests.ContainsKey($a)) { continue }
        if ($leadsTo.ContainsKey("$a>$id")) { if ($tcNext[$a] -eq $id -or $tcPrev[$id] -eq $a) { $leadIns.Add("$id <- $a") }; continue }
        if (($offered.ContainsKey($a) -and $offered.ContainsKey($id)) -or -not (Test-Checkable $id $a) -or (Test-OtherFaction $id $a)) { continue }
        if ($unavailable.ContainsKey($a) -or ($level -gt 0 -and (Get-MinLevel $a) -gt $level)) { continue }
        if (-not ($tcNext[$a] -eq $id -or $tcPrev[$id] -eq $a)) { $unrepeated++; continue }
        $by.Add($a)
    }
    if ($by.Count -and $unrepeated) { $severalLeadIns.Add("$id <- $($by -join '/') (the cache also names $unrepeated TrinityCore doesn't repeat)"); continue }
    if ($by.Count) { $by.Sort(); $followUp[$id] = $by.ToArray() }
}

$chapters = New-Object System.Collections.Generic.List[string]
foreach ($id in ($chapterLinks.Keys | Sort-Object)) {
    if ($api.ContainsKey($id) -and $null -ne $api[$id]) { continue }
    if ((Get-PartText $final[$id]) -ne (Get-PartText $chapterLinks[$id])) { $chapters.Add("$id needs $(Get-PartText $chapterLinks[$id])") }
    $final[$id] = $chapterLinks[$id]
}

$notBlizzard = New-Object System.Collections.Generic.List[string]
foreach ($id in ($quests.Keys | Sort-Object)) {
    if (-not (Test-Recurring $id) -or -not $final[$id]) { continue }
    $named = @()
    if ($api.ContainsKey($id) -and $null -ne $api[$id]) { $named += Get-PrereqQuests $api[$id] }
    if ($client.ContainsKey($id)) { $named += Get-PrereqQuests $client[$id] }
    if ($followUp.ContainsKey($id)) { $named += $followUp[$id] }
    $parts = New-Object System.Collections.Generic.List[object]
    foreach ($part in (Get-PrereqParts $final[$id])) {
        $theirs = @((Get-PrereqQuests $part) | Where-Object { (Test-Recurring $_) -and $named -notcontains $_ })
        if ($theirs.Count) { $notBlizzard.Add("$id <- $(Get-PartText $part)") } else { $parts.Add($part) }
    }
    $final[$id] = Join-PrereqParts $parts
}

# A quest with no other requirement, that the API is silent on, needs one of its follow-ups' sources
# done, unless that one already needs it.
function Test-Needs([int]$from, [int]$target) {
    $seen = @{}; $queue = New-Object System.Collections.Generic.Queue[int]; $queue.Enqueue($from)
    while ($queue.Count) {
        $at = $queue.Dequeue()
        foreach ($other in (Get-PrereqQuests $final[$at])) {
            if ($other -eq $target) { return $true }
            if ($other -and $quests.ContainsKey($other) -and -not $seen.ContainsKey($other)) { $seen[$other] = $true; $queue.Enqueue($other) }
        }
    }
    return $false
}
$followed = 0
foreach ($id in ($followUp.Keys | Sort-Object)) {
    if ($final[$id] -or ($api.ContainsKey($id) -and $null -ne $api[$id])) { continue }
    $by = New-Object System.Collections.Generic.List[object]
    foreach ($a in $followUp[$id]) { if (-not (Test-Needs $a $id)) { $by.Add($a) } }
    if (-not $by.Count) { continue }
    if ($by.Count -eq 1) { $final[$id] = [int]$by[0] } else { $final[$id] = Join-PrereqParts @(, $by.ToArray()) }
    $followed++
}

$contradicted = New-Object System.Collections.Generic.List[string]
foreach ($id in ($offered.Keys | Sort-Object)) {
    if (-not $quests.ContainsKey($id) -or -not $final[$id]) { continue }
    $parts = New-Object System.Collections.Generic.List[object]
    foreach ($part in (Get-PrereqParts $final[$id])) {
        if ($part -isnot [array] -and $offered.ContainsKey([int]$part)) { $contradicted.Add("$id <- $part") } else { $parts.Add($part) }
    }
    $final[$id] = Join-PrereqParts $parts
}

$gated = @{}
$refused = New-Object System.Collections.Generic.List[string]
foreach ($id in ($gateParts.Keys | Sort-Object)) {
    $needs = @(Get-PrereqQuests $final[$id])
    $parts = New-Object System.Collections.Generic.List[object]
    foreach ($part in (Get-PrereqParts $final[$id])) { $parts.Add($part) }
    foreach ($given in $gateParts[$id]) {
        if (@($needs | Where-Object { $given.Gate.Quests -contains $_ }).Count) { continue }
        $text = Get-PartText $given.Part
        if (@($parts | Where-Object { (Get-PartText $_) -eq $text }).Count) { continue }
        $alsoOffered = @((Get-PrereqQuests $given.Part) | Where-Object { $offered.ContainsKey($_) })
        if ($offered.ContainsKey($id) -and $alsoOffered.Count -and $given.Part -isnot [array]) { $refused.Add("$id <- $text"); continue }
        $parts.Add($given.Part)
        $gated["$($given.Gate.Kind) $($given.Gate.Id)"] = $gated["$($given.Gate.Kind) $($given.Gate.Id)"] + 1
    }
    $final[$id] = Join-PrereqParts $parts
}

$new = @{}
foreach ($id in $quests.Keys) {
    if ((Get-PartText $final[$id]) -ne (Get-PartText $quests[$id].prereq)) { $new[$id] = $final[$id] }
}

$decided = @{}; $decidedNone = @{}
foreach ($row in @(Import-Csv $DecisionsFile -Encoding UTF8)) {
    if ($row.Quest -notmatch '^\d+$' -or $row.Other -notmatch '^\d+$') { throw "$DecisionsFile has a row whose quests, '$($row.Quest)' and '$($row.Other)', aren't both numbers." }
    if ($row.Link -eq 'exclusive') { continue }
    $quest = [int]$row.Quest; $other = [int]$row.Other
    if ("$($row.Link) $($row.Decision)" -eq 'prereq NONE') {
        if ($other -ne 0) { throw "$DecisionsFile gives quest $quest a prereq NONE row that names quest ${other}: Other is 0 there." }
        if ($decidedNone.ContainsKey($quest)) { throw "$DecisionsFile says twice that quest $quest needs none." }
        $decidedNone[$quest] = $true
        continue
    }
    if ("$($row.Link) $($row.Decision)" -ne 'prereq SET') { throw "$DecisionsFile gives quest $($row.Quest) the link '$($row.Link)' with the decision '$($row.Decision)': only prereq SET and prereq NONE rows are read here (exclusive rows are step 2k's)." }
    if ($quest -eq $other) { throw "$DecisionsFile makes quest $quest require itself." }
    if ($decided[$quest] -contains $other) { throw "$DecisionsFile gives quest $quest the prerequisite $other twice." }
    $decided[$quest] += @($other)
}
$decidedChanged = 0; $decidedSame = 0
$overruled = New-Object System.Collections.Generic.List[string]
$decidedMissing = New-Object System.Collections.Generic.List[string]
foreach ($id in ($decided.Keys | Sort-Object)) {
    $options = @($decided[$id] | Sort-Object)
    if (-not $quests.ContainsKey($id) -or @($options | Where-Object { -not $quests.ContainsKey($_) }).Count) { $decidedMissing.Add("$id <- $($options -join ' or ')"); continue }
    $value = if ($options.Count -eq 1) { $options[0] } else { , (, [object[]]$options) }
    $text = ConvertTo-PrereqText $value '[' ']'
    if ($new.ContainsKey($id) -and (ConvertTo-PrereqText $new[$id] '[' ']') -ne $text) { $overruled.Add("$id <- $(ConvertTo-PrereqText $new[$id] '[' ']')") }
    if ((ConvertTo-PrereqText $quests[$id].prereq '[' ']') -eq $text) { $new.Remove($id); $decidedSame++ } else { $new[$id] = $value; $decidedChanged++ }
}
foreach ($id in ($decidedNone.Keys | Sort-Object)) {
    if ($decided.ContainsKey($id)) { throw "$DecisionsFile both names a prerequisite for quest $id and says it needs none." }
    if (-not $quests.ContainsKey($id)) { $decidedMissing.Add("$id <- none"); continue }
    if ($new.ContainsKey($id) -and $null -ne $new[$id]) { $overruled.Add("$id <- $(ConvertTo-PrereqText $new[$id] '[' ']')") }
    if ($null -eq $quests[$id].prereq) { $new.Remove($id); $decidedSame++ } else { $new[$id] = $null; $decidedChanged++ }
}

# Leave out a requirement that would make two quests each require the other, or a quest require itself.
$cycles = New-Object System.Collections.Generic.List[string]
function Get-Needs([int]$id) {
    $value = if ($new.ContainsKey($id)) { $new[$id] } else { $quests[$id].prereq }
    if (-not $value) { return , @() }
    $ids = Get-PrereqQuests $value
    return , $ids
}
foreach ($id in @($new.Keys)) {
    if ($null -eq $new[$id]) { continue }
    $needs = Get-PrereqQuests $new[$id]
    if ($needs -contains $id) { $cycles.Add("$id requires itself"); $new.Remove($id); continue }
    foreach ($other in $needs) {
        if (-not $quests.ContainsKey($other)) { continue }
        $otherNeeds = Get-Needs $other
        if ($otherNeeds -contains $id) { $cycles.Add("$id and $other would each require the other"); $new.Remove($id); break }
    }
}

"From the API: {0} quests get a prerequisite, {1} change theirs ({3} keep ours as well), {2} already match. From TrinityCore: {4}." -f $counts.fromApiNew, $counts.fromApiChanged, $counts.fromApiSame, $counts.keptApi, $counts.fromTrinityCore
"From the client's task quests: {0} quests get a prerequisite, {1} change theirs ({3} keep ours as well), {2} already match; it names {4} quests we hold no data for, so those requirements are left out." -f $counts.fromClientNew, $counts.fromClientChanged, $counts.fromClientSame, $counts.keptClient, $script:notInData.Count
"Campaign ${Campaign}: {0} chapters' first quests need the chapter before ({1} of them change)." -f $chapterLinks.Count, $chapters.Count
"The client's conditions: {0} quest lines and campaigns, given to {1} quests ({2})." -f $gates.Count, (($gated.Values | Measure-Object -Sum).Sum), (($gated.Keys | Sort-Object | ForEach-Object { "$_ x$($gated[$_])" }) -join ', ')
"The client's follow-ups that TrinityCore's requirement repeats: {0} quests have one, {1} take it now; {2} breadcrumbs into their quest left out." -f $followUp.Count, $followed, $leadIns.Count
"Left out as the cache names more lead-ins than TrinityCore repeats: $($severalLeadIns.Count)" + $(if ($severalLeadIns.Count) { " (" + ($severalLeadIns -join '; ') + ")" } else { '' })
"Left out as the game offered them together with the quest: $($contradicted.Count) required quests, and $($refused.Count) conditions."
"Recurring quests' recurring requirements that Blizzard doesn't name, left out: $($notBlizzard.Count)"
"Decided with the user ({0}): {1} quests ({4} of them with none), {2} change, {3} already match." -f (Split-Path -Leaf $DecisionsFile), ($decided.Count + $decidedNone.Count), $decidedChanged, $decidedSame, $decidedNone.Count
if ($overruled.Count) { "  The sources would give $($overruled.Count) of them something else, which the decisions overrule: " + ($overruled -join '; ') }
if ($decidedMissing.Count) { "  $($decidedMissing.Count) name a quest not in the data, so they're left out: " + ($decidedMissing -join '; ') }
"Left out as they'd go round in a circle: $($cycles.Count)" + $(if ($cycles.Count) { " (" + ($cycles -join '; ') + ")" } else { '' })
"Changes: $($new.Count)"
if ($WhatIf) {
    foreach ($list in @(@('Chapters', $chapters), @('Offered together', $contradicted), @('Conditions refused', $refused), @('Recurring, not Blizzard''s', $notBlizzard), @('Breadcrumbs into their quest', $leadIns))) {
        if ($list[1].Count) { "  $($list[0]): " + ($list[1] -join '; ') }
    }
    foreach ($id in ($new.Keys | Sort-Object | Select-Object -First 40)) {
        $q = $quests[$id]
        "  {0} {1}: {2} -> {3}" -f $id, $q.name, $(if ($q.prereq) { ConvertTo-PrereqText $q.prereq '[' ']' } else { 'none' }), $(if ($null -ne $new[$id]) { ConvertTo-PrereqText $new[$id] '[' ']' } else { 'none' })
    }
    return
}
foreach ($id in $new.Keys) { Set-RecordField $quests[$id] 'prereq' $new[$id] }
Save-QuestData $records $DataDir $AddonDir
