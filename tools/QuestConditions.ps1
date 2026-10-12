<#
The client's own conditions on the current expansion's quest lines and campaigns, as prerequisites,
dot-sourced by Sync-QuestPrerequisites.ps1 (step 2c), which sets them, and Audit-QuestTables.ps1
(step 2b), which knows them as the client's:
	. "$PSScriptRoot\QuestConditions.ps1"

A quest line (QuestLine.PlayerConditionID) or a campaign (Campaign.Prerequisite) names the
PlayerCondition the game checks before it offers the line. A condition is read as a tree of quests
that must be done (PlayerCondition.PrevQuestID with its logic field, as Sync-QuestPrerequisites.ps1
reads a task quest's; ModifierTree type 110), joined by its ModifierTree's AND (operator 4) and OR
(operator 8 with an amount of 1), with nested conditions (type 2) inside it. Anything else is read as
met, as the addon can't check it: a quest that mustn't be done, a level, a reputation, an "N of" group.
A game feature switched on for everyone at once (type 289) is read as off, so the branch the game
keeps for while it's on drops out of an OR. Campaigns 284 and 324, for one, need the hidden quest
90806, or else feature 1886 on.

Only the current expansion's conditions are taken: those that name a quest of its campaign
(-Campaign), or a quest we hold no data for that a line accepts in place of one (90806, which the
Voidstorm lines accept in place of 86509 or 86565). Older lines' conditions name hidden quests of
their own (Shadowlands' 62713 and 57559) that nothing has shown how to read.

Such a quest we hold no data for is kept, though it can't be named: the addon counts it as done or
not and leaves it out of the text (qcPrereq.Text). It isn't a quest of ours, so step 2b doesn't call
it missing.
#>
# A tree's AND or OR, as against a quest: a quest ID read from a table can come wrapped, and pass
# for a [pscustomobject] too.
function Test-ConditionGroup($node) {
    return ($node -is [pscustomobject]) -and ($node.PSObject.Properties.Name -contains 'Items')
}

# Both parts of an AND or OR: $null stands for a part that's always met, 'never' for one never met.
function Join-Condition([bool]$isAnd, $a, $b) {
    if ($isAnd) {
        if ($a -is [string] -or $b -is [string]) { return 'never' }
        if ($null -eq $a) { return $b }
        if ($null -eq $b) { return $a }
    } else {
        if ($a -is [string]) { return $b }
        if ($b -is [string]) { return $a }
        if ($null -eq $a -or $null -eq $b) { return $null }
    }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($node in @($a, $b)) {
        $parts = if ((Test-ConditionGroup $node) -and $node.And -eq $isAnd) { $node.Items } else { @($node) }
        foreach ($part in $parts) { if ((Test-ConditionGroup $part) -or $items -notcontains $part) { $items.Add($part) } }
    }
    if ($items.Count -eq 1) { return $items[0] }
    return [pscustomobject]@{ And = $isAnd; Items = $items.ToArray() }
}

# A tree as a prereq (see AddonData.ps1): a quest, or a list that all must be done, whose inner
# lists are choices, whose inner lists are all of it again. A choice at the top goes in a list of
# its own. $null for none.
function ConvertTo-Nested($group) {
    $out = @()
    foreach ($item in $group.Items) {
        if (Test-ConditionGroup $item) { $out += , (ConvertTo-Nested $item) } else { $out += [int]$item }
    }
    return , $out
}
function ConvertTo-PrereqValue($value) {
    if ($null -eq $value -or $value -is [string]) { return $null }
    if (-not (Test-ConditionGroup $value)) { return [int]$value }
    if (-not $value.And) { $value = [pscustomobject]@{ And = $true; Items = @($value) } }
    return , (ConvertTo-Nested $value)
}

# The client's tables for -Build, from -ToolsDir, fetched when missing.
function Import-ClientConditions([string]$ToolsDir, [string]$Build) {
    foreach ($table in 'QuestLine', 'QuestLineXQuest', 'Campaign', 'CampaignXQuestLine', 'ModifierTree') {
        $path = Join-Path $ToolsDir "$table-$Build.csv"
        if (-not (Test-Path $path)) {
            Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path
            Start-Sleep -Seconds 1
        }
    }
    $conditionCsv = Join-Path $ToolsDir 'PlayerCondition.csv'
    if (-not (Test-Path $conditionCsv)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/PlayerCondition/csv?build=$Build" -OutFile $conditionCsv }
    $c = @{ Lines = @{}; LineQuests = @{}; Campaigns = @{}; CampaignLines = @{}; Tree = @{}; Children = @{}; Conditions = @{} }
    foreach ($row in Import-Csv (Join-Path $ToolsDir "QuestLine-$Build.csv")) { $c.Lines[[int]$row.ID] = $row }
    $steps = @{}
    foreach ($row in Import-Csv (Join-Path $ToolsDir "QuestLineXQuest-$Build.csv")) {
        $line = [int]$row.QuestLineID
        if (-not $steps.ContainsKey($line)) { $steps[$line] = New-Object System.Collections.Generic.List[object] }
        $steps[$line].Add([pscustomobject]@{ Quest = [int]$row.QuestID; Order = [int]$row.OrderIndex })
    }
    foreach ($line in $steps.Keys) { $c.LineQuests[$line] = @($steps[$line] | Sort-Object Order | ForEach-Object { $_.Quest }) }
    foreach ($row in Import-Csv (Join-Path $ToolsDir "Campaign-$Build.csv")) { $c.Campaigns[[int]$row.ID] = $row }
    $chapters = @{}
    foreach ($row in Import-Csv (Join-Path $ToolsDir "CampaignXQuestLine-$Build.csv")) {
        $campaign = [int]$row.CampaignID
        if (-not $chapters.ContainsKey($campaign)) { $chapters[$campaign] = New-Object System.Collections.Generic.List[object] }
        $chapters[$campaign].Add([pscustomobject]@{ Line = [int]$row.QuestLineID; Order = [int]$row.OrderIndex })
    }
    foreach ($campaign in $chapters.Keys) { $c.CampaignLines[$campaign] = @($chapters[$campaign] | Sort-Object Order | ForEach-Object { $_.Line }) }
    foreach ($row in Import-Csv (Join-Path $ToolsDir "ModifierTree-$Build.csv")) {
        $id = [int]$row.ID; $parent = [int]$row.Parent
        $c.Tree[$id] = [pscustomobject]@{ Operator = [int]$row.Operator; Amount = [int]$row.Amount; Type = [int]$row.Type; Asset = [int]$row.Asset }
        if ($parent) {
            if (-not $c.Children.ContainsKey($parent)) { $c.Children[$parent] = New-Object System.Collections.Generic.List[int] }
            $c.Children[$parent].Add($id)
        }
    }
    Import-Csv $conditionCsv | ForEach-Object {
        $c.Conditions[[int]$_.ID] = [pscustomobject]@{
            Prev = @([int]$_.PrevQuestID_0, [int]$_.PrevQuestID_1, [int]$_.PrevQuestID_2, [int]$_.PrevQuestID_3)
            Logic = [int64]$_.PrevQuestLogic; Tree = [int]$_.ModifierTreeID
        }
    }
    return $c
}

function Get-LineQuests($c, [int]$line) {
    if ($c.LineQuests.ContainsKey($line)) { return , @($c.LineQuests[$line]) }
    return , @()
}
function Get-CampaignLines($c, [int]$campaign) {
    if ($c.CampaignLines.ContainsKey($campaign)) { return , @($c.CampaignLines[$campaign]) }
    return , @()
}

# A PlayerCondition as a tree; $null when nothing in it can be checked, 'never' when it can't be met.
function ConvertFrom-PlayerCondition($c, [int]$id, [int]$depth = 0) {
    $row = $c.Conditions[$id]
    if (-not $row -or $depth -gt 20) { return $null }
    $answer = $null
    for ($i = 0; $i -lt 4; $i++) {
        $quest = $row.Prev[$i]
        $item = if ($quest -gt 0 -and -not ($row.Logic -band (0x10000 -shl $i))) { $quest } else { $null }
        if ($i -eq 0) { $answer = $item; continue }
        $how = [int](($row.Logic -shr (2 * ($i - 1))) -band 3)
        if ($how -eq 1) { $answer = Join-Condition $true $answer $item }
        elseif ($how -eq 2) { $answer = Join-Condition $false $answer $item }
    }
    if ($row.Tree) { $answer = Join-Condition $true $answer (ConvertFrom-ModifierTree $c $row.Tree ($depth + 1)) }
    return $answer
}
function ConvertFrom-ModifierTree($c, [int]$id, [int]$depth) {
    $node = $c.Tree[$id]
    if (-not $node -or $depth -gt 40 -or $node.Operator -eq 3) { return $null }
    $own = switch ($node.Type) {
        110 { $node.Asset }
        2 { ConvertFrom-PlayerCondition $c $node.Asset ($depth + 1) }
        289 { 'never' }
        default { $null }
    }
    $children = $c.Children[$id]
    if (-not $children) { return $own }
    if ($node.Operator -ne 4 -and -not ($node.Operator -eq 8 -and $node.Amount -le 1)) { return $own }
    $isAnd = $node.Operator -eq 4
    $joined = $null; $first = $true
    foreach ($child in $children) {
        $part = ConvertFrom-ModifierTree $c $child ($depth + 1)
        if ($first) { $joined = $part; $first = $false } else { $joined = Join-Condition $isAnd $joined $part }
    }
    return Join-Condition $true $own $joined
}

# The quests a tree names, however it nests them.
function Get-ConditionQuests($node) {
    if ($null -eq $node -or $node -is [string]) { return , @() }
    if (-not (Test-ConditionGroup $node)) { return , @([int]$node) }
    $ids = @()
    foreach ($item in $node.Items) { $ids += Get-ConditionQuests $item }
    return , $ids
}

# The current expansion's conditions on its quest lines and other campaigns, one row each: Kind
# ('line' or 'campaign'), Id, Name, Quests (the quests it covers, in order) and Gate (a tree). $quests
# is our data, by ID.
function Get-ConditionGates($c, [int]$Campaign, $quests) {
    $own = @{}
    foreach ($line in (Get-CampaignLines $c $Campaign)) { foreach ($quest in (Get-LineQuests $c $line)) { $own[$quest] = $true } }
    $gates = New-Object System.Collections.Generic.List[object]
    foreach ($id in ($c.Lines.Keys | Sort-Object)) {
        $condition = [int]$c.Lines[$id].PlayerConditionID
        if (-not $condition) { continue }
        $gate = ConvertFrom-PlayerCondition $c $condition
        if ($null -eq $gate -or $gate -is [string]) { continue }
        $gates.Add([pscustomobject]@{ Kind = 'line'; Id = $id; Name = $c.Lines[$id].Name_lang; Quests = (Get-LineQuests $c $id); Gate = $gate })
    }
    foreach ($id in ($c.Campaigns.Keys | Sort-Object)) {
        $condition = [int]$c.Campaigns[$id].Prerequisite
        if ($id -eq $Campaign -or -not $condition) { continue }
        $gate = ConvertFrom-PlayerCondition $c $condition
        if ($null -eq $gate -or $gate -is [string]) { continue }
        $covered = @(foreach ($line in (Get-CampaignLines $c $id)) { foreach ($quest in (Get-LineQuests $c $line)) { $quest } })
        $gates.Add([pscustomobject]@{ Kind = 'campaign'; Id = $id; Name = $c.Campaigns[$id].Title_lang; Quests = $covered; Gate = $gate })
    }
    # The hidden quests a line accepts in place of one of the campaign's.
    $instead = @{}
    foreach ($g in $gates) {
        $choices = @(if (Test-ConditionGroup $g.Gate) { if ($g.Gate.And) { $g.Gate.Items } else { $g.Gate } })
        foreach ($choice in $choices) {
            if (-not (Test-ConditionGroup $choice) -or $choice.And) { continue }
            if (@($choice.Items | Where-Object { -not (Test-ConditionGroup $_) -and $own.ContainsKey([int]$_) }).Count -eq 0) { continue }
            foreach ($item in $choice.Items) { if (-not (Test-ConditionGroup $item) -and -not $quests.ContainsKey([int]$item)) { $instead[[int]$item] = $true } }
        }
    }
    return @($gates | Where-Object { @((Get-ConditionQuests $_.Gate) | Where-Object { $own.ContainsKey($_) -or $instead.ContainsKey($_) }).Count -gt 0 })
}

# The campaign's chapters (its quest lines, in order) after the first: each one's first quest needs
# the last quest of the chapter before, by ID. A chapter that starts on -ScoutingMapLine, a line of the
# zone campaigns the Scouting Map offers in any order, needs what -ScoutingMapQuest needs instead: the
# map offers them while that quest, whose objective is to choose one, is in the log.
function Get-ChapterLinks($c, [int]$Campaign, [int]$ScoutingMapLine, [int]$ScoutingMapQuest, $quests) {
    $links = @{}
    $onMap = @{}
    foreach ($quest in (Get-LineQuests $c $ScoutingMapLine)) { $onMap[$quest] = $true }
    $mapNeeds = $null
    if ($quests.ContainsKey($ScoutingMapQuest)) { $mapNeeds = $quests[$ScoutingMapQuest].prereq }
    $lines = Get-CampaignLines $c $Campaign
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $steps = Get-LineQuests $c $lines[$i]
        $before = Get-LineQuests $c $lines[$i - 1]
        if (-not $steps.Count -or -not $before.Count) { continue }
        $head = $steps[0]; $last = $before[$before.Count - 1]
        if (-not $quests.ContainsKey($head)) { continue }
        if ($onMap.ContainsKey($head)) { if ($mapNeeds) { $links[$head] = $mapNeeds } }
        elseif ($quests.ContainsKey($last)) { $links[$head] = $last }
    }
    return $links
}
