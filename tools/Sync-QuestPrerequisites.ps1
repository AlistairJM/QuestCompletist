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
    joins the answer so far, from left to right: 1 and, 2 or, 0 not at all. Where the client's
    list leaves us something to show, it replaces ours, except that one of ours stays when it's the
    step just before the quest in its storyline, as with the API's list. A quest that must not be
    done is no prerequisite. A quest we hold no data for (a hidden tracking quest, with no name to
    show) can't be told to the player: as a quest to do first it's left out, and as one of several
    that will do it takes the whole choice with it, as another way needs nothing we could show.
    The tables are those step 1b refreshes (QuestV2CliTask.csv and PlayerCondition.csv in
    -ToolsDir); they're fetched for -Build when missing.
A quest the API and the client are silent on keeps its prerequisite.

A one-time quest's required quest that recurs (daily, weekly or repeatable) is left out: the game
only knows such a quest is done until the next reset, so the map would hide the one-time quest
again. A choice that offers one is left out whole. A recurring quest keeps a recurring
requirement, as in a chain of world quests, which the game knows within the day or week. A
requirement that would make two quests each require the other is left out too, and listed.

With -WhatIf it only reports. Otherwise it saves through AddonData.ps1, which rebuilds the Lua.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = "12.1.0.69933",
    [string]$TdbFile = "",
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\AddonData.ps1"

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
# A simplified tree as a prereq: a quest, or a list that all must be done, whose inner lists are
# choices, whose inner lists are all of it again. A choice at the top goes in a list of its own.
function ConvertTo-Nested($group) {
    $out = @()
    foreach ($item in $group.Items) {
        if ($item -is [pscustomobject]) { $out += , (ConvertTo-Nested $item) } else { $out += [int]$item }
    }
    return , $out
}
function ConvertTo-PrereqValue($value) {
    if ($null -eq $value -or $value -is [string]) { return $null }
    if ($value -isnot [pscustomobject]) { return [int]$value }
    if (-not $value.And) { $value = [pscustomobject]@{ And = $true; Items = @($value) } }
    return , (ConvertTo-Nested $value)
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

foreach ($table in 'QuestV2CliTask', 'PlayerCondition') {
    $path = Join-Path $ToolsDir "$table.csv"
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path
        Start-Sleep -Seconds 1
    }
}
$tasks = @(Import-Csv (Join-Path $ToolsDir 'QuestV2CliTask.csv') | Where-Object { $quests.ContainsKey([int]$_.ID) })
$wanted = @{}
foreach ($t in $tasks) { if ($t.ConditionID -ne '0') { $wanted[$t.ConditionID] = $true } }
$conditions = @{}
Import-Csv (Join-Path $ToolsDir 'PlayerCondition.csv') | ForEach-Object { if ($wanted.ContainsKey($_.ID)) { $conditions[$_.ID] = $_ } }
$script:notInData = @{}
$client = @{}
foreach ($t in $tasks) {
    $script:converting = [int]$t.ID
    $own = Convert-ClientList $t 'FiltCompletedQuest' 3 'FiltCompletedQuestLogic'
    $condition = $null
    if ($conditions.ContainsKey($t.ConditionID)) { $condition = Convert-ClientList $conditions[$t.ConditionID] 'PrevQuestID' 4 'PrevQuestLogic' }
    $value = ConvertTo-PrereqValue (Join-Nodes $true $own $condition)
    if ($null -ne $value) { $client[[int]$t.ID] = $value }
}

$tcPrev = @{}
if (-not $TdbFile) {
    $TdbFile = Get-ChildItem "$ToolsDir\tdb\TDB_full_world_*.sql" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName
}
if ($TdbFile) {
    $outputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try { $rows = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $TdbFile quest_template_addon '1,5') } finally { [Console]::OutputEncoding = $outputEncoding }
    if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $TdbFile" }
    foreach ($row in $rows) { $f = $row.Split("`t"); if ([int]$f[1] -gt 0) { $tcPrev[[int]$f[0]] = [int]$f[1] } }
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

$new = @{}
$counts = [ordered]@{ fromApiNew = 0; fromApiChanged = 0; fromApiSame = 0; keptApi = 0; fromClientNew = 0; fromClientChanged = 0; fromClientSame = 0; keptClient = 0; fromTrinityCore = 0 }
foreach ($id in ($quests.Keys | Sort-Object)) {
    $q = $quests[$id]
    $ours = if ($q.prereq) { ConvertTo-PrereqText $q.prereq '[' ']' } else { '' }
    $source = ''
    if ($api.ContainsKey($id) -and $null -ne $api[$id]) { $source = 'Api'; $value = $api[$id] }
    elseif ($client.ContainsKey($id) -and -not $api.ContainsKey($id)) { $source = 'Client'; $value = $client[$id] }
    if ($source) {
        # The API names at most 3 quests and often leaves out the step just before the quest in its
        # storyline, and the client names what must be done before a task quest shows, not the chain.
        # One of ours that's missing from the list stays when it's the step just before the quest in
        # its storyline, as it nearly always is.
        $listed = Get-PrereqQuests $value
        $ourQuests = if ($q.prereq) { Get-PrereqQuests $q.prereq } else { @() }
        $kept = @($ourQuests | Where-Object { $listed -notcontains $_ -and (Test-StepJustBefore $id $_) })
        if ($kept.Count) { $value = @($kept) + @($value); $counts["kept$source"]++ }
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

# Leave out a requirement that would make two quests each require the other, or a quest require itself.
$cycles = New-Object System.Collections.Generic.List[string]
function Get-Needs([int]$id) {
    $value = if ($new.ContainsKey($id)) { $new[$id] } else { $quests[$id].prereq }
    if (-not $value) { return , @() }
    $ids = Get-PrereqQuests $value
    return , $ids
}
foreach ($id in @($new.Keys)) {
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
"Left out as they'd go round in a circle: $($cycles.Count)" + $(if ($cycles.Count) { " (" + ($cycles -join '; ') + ")" } else { '' })
"Changes: $($new.Count)"
if ($WhatIf) {
    foreach ($id in ($new.Keys | Sort-Object | Select-Object -First 40)) {
        $q = $quests[$id]
        "  {0} {1}: {2} -> {3}" -f $id, $q.name, $(if ($q.prereq) { ConvertTo-PrereqText $q.prereq '[' ']' } else { 'none' }), (ConvertTo-PrereqText $new[$id] '[' ']')
    }
    return
}
foreach ($id in $new.Keys) { Set-RecordField $quests[$id] 'prereq' $new[$id] }
Save-QuestData $records $DataDir $AddonDir
