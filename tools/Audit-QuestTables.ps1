<#
Report-only. Checks the quest tables kept by hand in QuestCompletist\qcQuest.lua, and the
prerequisites in data\quests.jsonl, against every source that can speak to them:
  - our own data: each quest a table names should be in data\quests.jsonl, not flagged unavailable
    (qcUnavailableQuests.lua) and, in breadcrumbs and "only one of these" pairs, not recurring,
    since the addon never ticks a daily, weekly or repeatable quest;
  - Blizzard's API, from the cache Audit-QuestAccuracy.ps1 fills (tools\quest_api_cache): the
    quests a quest requires done (all of them, or one of several), and the ones it requires not
    done, which close it. Where it speaks, it outranks TrinityCore;
  - the client's Faction table for -Build: which factions have renown, and their English names;
  - TrinityCore's world database, the newest tools\tdb\TDB_full_world_*.sql, for older quests:
    breadcrumbs (BreadcrumbForQuestId), groups of which only one can be done (a positive
    ExclusiveGroup) and previous quests (a positive PrevQuestID). It only speaks for a quest it has a
    row for, and has few rows for quests after Mists of Pandaria. Its groups we lack are counted,
    not listed: it also groups quests one character can do all of.

The tables it checks:
  qcBreadcrumbQuests     [quest] = {breadcrumbs}: quests that lead to it and close once it's done.
  qcMutuallyExclusive    [quest] = {quests}: quests that close once it's done.
  qcRenownLevelRequirements, qcOverrideDailyExclusiveQuest, qcOverrideWeeklyExclusiveQuest, and
  qcFactions' English names. Each table is also checked for a quest listed twice, as Lua keeps only
  the last.

Each finding is a row of -OutFile: Kind, Quest, Other, Detail, and Kept. A finding reviewed and left
as it is gets a KEEP row in -DecisionsFile (Kind, Quest, Other, Decision, Reason); later runs mark it
kept and count only the rest as new. A finding that's fixed in the data goes away by itself.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = "12.1.0.69933",
    [string]$TdbFile = "",
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-table-decisions.csv'),
    [string]$OutFile = "",
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\AddonData.ps1"
if (-not $OutFile) { $OutFile = "$ToolsDir\quest_table_audit.csv" }

$quests = @{}
foreach ($q in (Read-QuestData $DataDir)) { $quests[[int]$q.id] = $q }
function Get-QuestName([int]$id) { if ($quests.ContainsKey($id)) { return $quests[$id].name } return '?' }
function Test-Recurring([int]$id) { return $quests.ContainsKey($id) -and ($quests[$id].type -band (2 + 4 + 128)) }
# Whether $prereq can stand as $id's prerequisite: a quest that recurs only for one that recurs too, as
# within a day or week the game knows it's done.
function Test-Checkable([int]$id, [int]$prereq) { return (Test-Recurring $id) -or -not (Test-Recurring $prereq) }
function Test-OtherFaction([int]$a, [int]$b) {
    if (-not ($quests.ContainsKey($a) -and $quests.ContainsKey($b))) { return $false }
    $fa = $quests[$a].faction; $fb = $quests[$b].faction
    return ($fa -eq 1 -and $fb -eq 2) -or ($fa -eq 2 -and $fb -eq 1)
}

$luaText = [IO.File]::ReadAllText((Join-Path $AddonDir 'qcQuest.lua'))
function Get-TableLines([string]$name) {
    $block = [regex]::Match($luaText, "(?s)(?:^|\n)$name\s*=\s*\{[^\n]*\n(.*?)\n\}")
    if (-not $block.Success) { throw "qcQuest.lua has no $name table." }
    $text = $block.Groups[1].Value -replace '(?s)--\[\[.*?\]\]', '' -replace '--[^\n]*', ''
    return $text -split "`n"
}
$unavailable = @{}
foreach ($m in [regex]::Matches([IO.File]::ReadAllText((Join-Path $AddonDir 'qcUnavailableQuests.lua')), '\[(\d+)\]=(\d+)')) {
    $unavailable[[int]$m.Groups[1].Value] = [int]$m.Groups[2].Value
}

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding([string]$kind, $quest, $other, [string]$detail) {
    $findings.Add([pscustomobject]@{ Kind = $kind; Quest = "$quest"; Other = "$other"; Detail = $detail; Kept = '' })
}

# A table of [quest] = {quests}, read into quest -> list, noting quests listed twice.
function Read-ListTable([string]$name, [string]$label) {
    $table = @{}
    foreach ($line in (Get-TableLines $name)) {
        if ($line -notmatch '^\s*\[(\d+)\]\s*=\s*\{([\d,\s]*)\}') { continue }
        $id = [int]$Matches[1]
        $list = @($Matches[2] -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { [int]$_ })
        if ($table.ContainsKey($id)) { Add-Finding "${label}: listed twice" $id '' "only the last line counts: {$($list -join ',')}" }
        $table[$id] = $list
    }
    return $table
}
$breadcrumbs = Read-ListTable 'qcBreadcrumbQuests' 'breadcrumb'
$exclusive = Read-ListTable 'qcMutuallyExclusive' 'exclusive'
$closes = @{}
foreach ($id in $breadcrumbs.Keys) { foreach ($b in $breadcrumbs[$id]) { $closes["$id>$b"] = $true } }
foreach ($id in $exclusive.Keys) { foreach ($o in $exclusive[$id]) { $closes["$id>$o"] = $true } }

# Blizzard's API: each quest's required quests, as leaves of an AND/OR tree. A leaf under an OR is
# one of several that will do; one reached through ANDs only is a must. A leaf that must be
# incomplete is a quest that closes this one.
$requires = @{}; $mustDo = @{}; $closedBy = @{}
$cache = Join-Path $ToolsDir 'quest_api_cache'
foreach ($file in (Get-ChildItem $cache -Filter *.json | Select-String -Pattern '"quests":\{"operator"' -List | Select-Object -ExpandProperty Path)) {
    $json = [IO.File]::ReadAllText($file) | ConvertFrom-Json
    $id = [int]$json.id
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($json.requirements.quests, $true))
    while ($stack.Count) {
        $node, $allAnd = $stack.Pop()
        if ($node.target) {
            $other = [int]$node.target.id
            if ($node.must_be_incomplete) { $closedBy[$id] += @($other) }
            else { $requires[$id] += @($other); if ($allAnd) { $mustDo[$id] += @($other) } }
        } else { foreach ($child in $node.conditions) { $stack.Push(@($child, ($allAnd -and $node.operator.type -eq 'AND'))) } }
    }
}
function Test-MustDo([int]$a, [int]$b) { return $mustDo.ContainsKey($a) -and $mustDo[$a] -contains $b }
function Test-ApiCloses([int]$done, [int]$closed) { return $closedBy.ContainsKey($closed) -and $closedBy[$closed] -contains $done }

# TrinityCore's quest_template_addon: ID, PrevQuestID, ExclusiveGroup, BreadcrumbForQuestId.
$tc = @{}
if (-not $TdbFile) {
    $TdbFile = Get-ChildItem "$ToolsDir\tdb\TDB_full_world_*.sql" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName
}
if ($TdbFile) {
    $outputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try { $rows = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $TdbFile quest_template_addon '1,5,7,8') } finally { [Console]::OutputEncoding = $outputEncoding }
    if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $TdbFile" }
    foreach ($row in $rows) {
        $f = $row.Split("`t")
        $tc[[int]$f[0]] = [pscustomobject]@{ Prev = [int]$f[1]; Group = [int]$f[2]; BreadcrumbFor = [int]$f[3] }
    }
}
$tcGroups = @{}
foreach ($id in $tc.Keys) { if ($tc[$id].Group -gt 0 -and $quests.ContainsKey($id)) { $tcGroups[$tc[$id].Group] += @($id) } }
# Whether TrinityCore has doing $done close $closed: the two share a positive group, or $closed is a
# breadcrumb for $done.
function Test-TcCloses([int]$done, [int]$closed) {
    $a = $tc[$done]; $b = $tc[$closed]
    return ($a -and $b -and $a.Group -gt 0 -and $a.Group -eq $b.Group) -or ($b -and $b.BreadcrumbFor -eq $done)
}

# Breadcrumbs: [target] = {breadcrumbs}.
foreach ($target in ($breadcrumbs.Keys | Sort-Object)) {
    foreach ($crumb in $breadcrumbs[$target]) {
        foreach ($id in @($target, $crumb)) {
            if (-not $quests.ContainsKey($id)) { Add-Finding 'breadcrumb: quest not in the data' $target $crumb "$id isn't in quests.jsonl" }
            elseif ($unavailable.ContainsKey($id)) { Add-Finding 'breadcrumb: quest flagged unavailable' $target $crumb "$id $(Get-QuestName $id)" }
            elseif (Test-Recurring $id) { Add-Finding 'breadcrumb: recurring quest' $target $crumb "$id $(Get-QuestName $id) is type $($quests[$id].type)" }
        }
        if ($crumb -eq $target) { Add-Finding 'breadcrumb: leads to itself' $target $crumb '' }
        if (Test-OtherFaction $target $crumb) { Add-Finding 'breadcrumb: other faction' $target $crumb "$(Get-QuestName $crumb) -> $(Get-QuestName $target)" }
        if ((Test-MustDo $target $crumb) -or (Test-MustDo $crumb $target)) {
            Add-Finding "breadcrumb: the API requires one for the other" $target $crumb "$(Get-QuestName $crumb) -> $(Get-QuestName $target)"
        }
        $row = $tc[$crumb]
        if ($row -and $tc.ContainsKey($target) -and -not (Test-TcCloses $target $crumb) -and -not (Test-ApiCloses $target $crumb)) {
            Add-Finding 'breadcrumb: TrinityCore disagrees' $target $crumb ("TrinityCore: {0} is {1}" -f $crumb, $(if ($row.BreadcrumbFor) { "a breadcrumb for $($row.BreadcrumbFor)" } else { 'no breadcrumb' }))
        }
    }
}

# "Only one of these": [quest] = {quests that close once it's done}.
foreach ($id in ($exclusive.Keys | Sort-Object)) {
    foreach ($other in $exclusive[$id]) {
        foreach ($q in @($id, $other)) {
            if (-not $quests.ContainsKey($q)) { Add-Finding 'exclusive: quest not in the data' $id $other "$q isn't in quests.jsonl" }
            elseif ($unavailable.ContainsKey($q)) { Add-Finding 'exclusive: quest flagged unavailable' $id $other "$q $(Get-QuestName $q)" }
            elseif (Test-Recurring $q) { Add-Finding 'exclusive: recurring quest' $id $other "$q $(Get-QuestName $q) is type $($quests[$q].type)" }
        }
        if ($other -eq $id) { Add-Finding 'exclusive: shuts itself out' $id $other '' }
        if ((Test-MustDo $id $other) -or (Test-MustDo $other $id)) {
            Add-Finding 'exclusive: the API requires one for the other' $id $other "$(Get-QuestName $id) / $(Get-QuestName $other)"
        }
        $a = $tc[$id]; $b = $tc[$other]
        if ($a -and $b -and -not (Test-TcCloses $id $other) -and -not (Test-ApiCloses $id $other)) {
            Add-Finding 'exclusive: TrinityCore disagrees' $id $other ("TrinityCore groups: {0} and {1}; breadcrumb for: {2} and {3}" -f $a.Group, $b.Group, $a.BreadcrumbFor, $b.BreadcrumbFor)
        }
    }
}

# Quests the API says close another, and TrinityCore's breadcrumbs and groups, that our tables lack.
foreach ($id in ($closedBy.Keys | Sort-Object)) {
    foreach ($closer in $closedBy[$id]) {
        if (-not ($quests.ContainsKey($id) -and $quests.ContainsKey($closer)) -or (Test-Recurring $id) -or $closes["$closer>$id"]) { continue }
        Add-Finding 'API: closes a quest, not in our tables' $closer $id "doing $closer $(Get-QuestName $closer) closes $id $(Get-QuestName $id)"
    }
}
foreach ($crumb in ($tc.Keys | Sort-Object)) {
    $target = $tc[$crumb].BreadcrumbFor
    if ($target -le 0 -or -not ($quests.ContainsKey($crumb) -and $quests.ContainsKey($target))) { continue }
    if ((Test-Recurring $crumb) -or (Test-Recurring $target) -or $unavailable.ContainsKey($crumb) -or $unavailable.ContainsKey($target) -or $closes["$target>$crumb"]) { continue }
    Add-Finding 'breadcrumb: TrinityCore has, we don''t' $target $crumb "$(Get-QuestName $crumb) -> $(Get-QuestName $target)"
}
# TrinityCore's groups are counted, not taken: it also groups quests one character can do all of,
# such as Darrowshire's three in the Eastern Plaguelands (decided with the user, 2026-10-06).
$tcGroupsLacked = 0; $tcPairsLacked = 0
foreach ($group in ($tcGroups.Keys | Sort-Object)) {
    $members = @($tcGroups[$group] | Where-Object { -not (Test-Recurring $_) -and -not $unavailable.ContainsKey($_) } | Sort-Object)
    if ($members.Count -lt 2) { continue }
    $missing = 0
    foreach ($a in $members) { foreach ($b in $members) { if ($a -ne $b -and -not $closes["$a>$b"]) { $missing++ } } }
    if ($missing) { $tcGroupsLacked++; $tcPairsLacked += $missing }
}

# Prerequisites, from data\quests.jsonl: a quest, or a list of them (see AddonData.ps1). As
# Sync-QuestPrerequisites.ps1 sets them, a quest of ours the API leaves out is fine when it's the
# step just before in the quest's storyline, and TrinityCore's previous quest is only taken when it's
# that step: the others it offers are counted, not listed.
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
$tcNotTaken = 0
foreach ($id in ($quests.Keys | Sort-Object)) {
    $value = $quests[$id].prereq
    $api = $requires[$id]
    $row = $tc[$id]
    if ($value) {
        $ours = Get-PrereqQuests $value
        $musts = @(if ($value -is [array]) { $value | Where-Object { $_ -isnot [array] } } else { $value })
        foreach ($prereq in $ours) {
            if (-not $quests.ContainsKey($prereq)) { Add-Finding 'prereq: quest not in the data' $id $prereq '' }
            elseif (-not (Test-Checkable $id $prereq)) { Add-Finding 'prereq: recurring quest' $id $prereq "$(Get-QuestName $prereq) is type $($quests[$prereq].type), which the game doesn't keep as done" }
            if ($prereq -eq $id) { Add-Finding 'prereq: requires itself' $id $prereq '' }
            elseif ($quests.ContainsKey($prereq) -and $quests[$prereq].prereq) {
                $theirs = Get-PrereqQuests $quests[$prereq].prereq
                if ($theirs -contains $id) { Add-Finding 'prereq: each requires the other' $id $prereq '' }
            }
            if ($musts -contains $prereq -and (Test-OtherFaction $id $prereq)) { Add-Finding 'prereq: other faction' $id $prereq "$(Get-QuestName $id) requires $(Get-QuestName $prereq)" }
            if ($api -and $api -notcontains $prereq -and -not (Test-StepJustBefore $id $prereq)) {
                Add-Finding 'prereq: not one the API names' $id $prereq ("API: {0}" -f (($api | ForEach-Object { "$_ $(Get-QuestName $_)" }) -join ' | '))
            }
        }
        foreach ($required in @(if ($api) { $api | Where-Object { $quests.ContainsKey($_) -and (Test-Checkable $id $_) -and $ours -notcontains $_ } })) {
            Add-Finding 'prereq: the API names one we lack' $id $required (Get-QuestName $required)
        }
        if (-not $api -and $row -and $row.Prev -gt 0 -and $ours -notcontains $row.Prev) {
            Add-Finding 'prereq: TrinityCore differs' $id ($ours -join ' ') ("TrinityCore: {0} {1}" -f $row.Prev, (Get-QuestName $row.Prev))
        }
    } else {
        $named = @(if ($api) { $api | Where-Object { $quests.ContainsKey($_) -and (Test-Checkable $id $_) } })
        if ($named.Count) { Add-Finding 'prereq: the API has one, we don''t' $id '' (($named | ForEach-Object { "$_ $(Get-QuestName $_)" }) -join ' | ') }
        elseif (-not $api -and $row -and $row.Prev -gt 0 -and $quests.ContainsKey($row.Prev)) {
            if ((Test-Checkable $id $row.Prev) -and -not (Test-OtherFaction $id $row.Prev) -and (Test-StepJustBefore $id $row.Prev)) {
                Add-Finding 'prereq: TrinityCore has one, we don''t' $id $row.Prev (Get-QuestName $row.Prev)
            } else { $tcNotTaken++ }
        }
    }
}

# Renown requirements, the override tables and faction names, against the client's Faction table.
$factionCsv = "$ToolsDir\Faction-$Build.csv"
if (-not (Test-Path $factionCsv)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/Faction/csv?build=$Build" -OutFile $factionCsv }
$clientFaction = @{}
foreach ($row in Import-Csv $factionCsv) { $clientFaction[[int]$row.ID] = $row }
$renown = @{}
foreach ($line in (Get-TableLines 'qcRenownLevelRequirements')) {
    if ($line -notmatch '^\s*\[(\d+)\]\s*=\s*\{\s*(\d+)\s*,\s*(\d+)\s*\}') { continue }
    $id = [int]$Matches[1]; $faction = [int]$Matches[2]
    if ($renown.ContainsKey($id)) { Add-Finding 'renown: listed twice' $id $faction 'only the last line counts' }
    $renown[$id] = $faction
    if (-not $quests.ContainsKey($id)) { Add-Finding 'renown: quest not in the data' $id $faction '' }
    if (-not $clientFaction.ContainsKey($faction)) { Add-Finding 'renown: faction not in the client' $id $faction '' }
    elseif (-not [int]$clientFaction[$faction].RenownCurrencyID) { Add-Finding 'renown: faction has no renown' $id $faction $clientFaction[$faction].Name_lang }
}
foreach ($table in @(@('qcOverrideDailyExclusiveQuest', 4, 'daily'), @('qcOverrideWeeklyExclusiveQuest', 128, 'weekly'))) {
    foreach ($line in (Get-TableLines $table[0])) {
        if ($line -notmatch 'quests\s*=\s*\{([\d,\s]*)\}') { continue }
        foreach ($id in ($Matches[1] -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { [int]$_ })) {
            if (-not $quests.ContainsKey($id)) { Add-Finding "$($table[2]) limit: quest not in the data" $id '' $table[0] }
            elseif (-not ($quests[$id].type -band $table[1])) { Add-Finding "$($table[2]) limit: quest isn't $($table[2])" $id '' "$(Get-QuestName $id) is type $($quests[$id].type)" }
        }
    }
}
$factionNames = @{}
foreach ($line in (Get-TableLines 'qcFactions')) {
    if ($line -notmatch '^\s*\[(\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"') { continue }
    $id = [int]$Matches[1]
    if ($factionNames.ContainsKey($id)) { Add-Finding 'faction name: listed twice' $id '' 'only the last line counts' }
    $factionNames[$id] = $Matches[2]
    if (-not $clientFaction.ContainsKey($id)) { Add-Finding 'faction name: faction not in the client' $id '' $Matches[2] }
    elseif ($clientFaction[$id].Name_lang -cne $Matches[2]) { Add-Finding 'faction name: differs from the client' $id '' "ours: $($Matches[2]); the client: $($clientFaction[$id].Name_lang)" }
}
foreach ($faction in (@($renown.Values) | Sort-Object -Unique)) {
    if (-not $factionNames.ContainsKey($faction)) { Add-Finding 'faction name: missing' $faction '' 'a renown requirement names it' }
}

$kept = @{}
if (Test-Path $DecisionsFile) {
    foreach ($d in (Import-Csv $DecisionsFile)) { if ($d.Decision -eq 'KEEP') { $kept["$($d.Kind)|$($d.Quest)|$($d.Other)"] = $d.Reason } }
}
foreach ($f in $findings) { $reason = $kept["$($f.Kind)|$($f.Quest)|$($f.Other)"]; if ($reason) { $f.Kept = $reason } }
$findings | Sort-Object Kind, { [int]("0" + $_.Quest) }, { [int]("0" + $_.Other) } | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8

"Tables: {0} breadcrumb targets, {1} quests with others they close, {2} renown requirements, {3} faction names; {4} quests with a prerequisite." -f
    $breadcrumbs.Count, $exclusive.Count, $renown.Count, $factionNames.Count, @($quests.Values | Where-Object { $_.prereq }).Count
"Sources: the API names required quests for {0} quests and closing ones for {1}; TrinityCore has {2} rows{3}." -f
    $requires.Count, $closedBy.Count, $tc.Count, $(if ($TdbFile) { " ($(Split-Path -Leaf $TdbFile))" } else { ': no TDB_full_world_*.sql in tools\tdb, so its checks were skipped' })
"TrinityCore offers previous quests for $tcNotTaken more quests we have none for, but none that's the step just before in the quest's storyline, so they aren't taken."
"TrinityCore has $tcGroupsLacked groups of which only one can be done that we lack ($tcPairsLacked pairs). They aren't taken: it also groups quests one character can do all of."
$findings | Group-Object Kind | Sort-Object Name | ForEach-Object {
    $new = @($_.Group | Where-Object { -not $_.Kept }).Count
    "  {0}: {1}{2}" -f $_.Name, $_.Count, $(if ($new -ne $_.Count) { " ($new new)" } else { '' })
}
"Findings: $($findings.Count), of which new: $(@($findings | Where-Object { -not $_.Kept }).Count). Written to $OutFile"
