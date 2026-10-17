<#
The client's own conditions on the current expansion's quest lines and campaigns, and on task quests,
as prerequisites, dot-sourced by Sync-QuestPrerequisites.ps1 (step 2c), which sets them,
Audit-QuestTables.ps1 (step 2b), which knows them as the client's, Sync-QuestCovenants.ps1 (step 2l),
which reads their covenants, Sync-QuestConditionTexts.ps1 (step 2m), which takes the text the game
shows when one isn't met, and Sync-QuestRenown.ps1 (step 2o), which reads the renown levels they need:
	. "$PSScriptRoot\QuestConditions.ps1"

A quest line (QuestLine.PlayerConditionID), a campaign (Campaign.Prerequisite) or a task quest
(QuestV2CliTask.ConditionID) names the PlayerCondition the game checks before it offers the line or the
quest. A condition is read as a tree of quests that must be done (PlayerCondition.PrevQuestID with its
logic field; ModifierTree type 110), joined by its ModifierTree's AND (operator 4) and OR (operator 8
with an amount of 1), with nested conditions (type 2) and nested trees (type 73) inside it. Anything
else is read as met, as the addon can't check it: a quest that mustn't be done, a level, a reputation,
an "N of" group. So is a condition the client switches off (flag 0x100), and the tree of one the game
reads the other way round (flag 0x200), as the addon can't check its opposite. A game feature switched
on for everyone at once (type 289) is read as off, so the branch the game keeps for while it's on drops
out of an OR. Campaigns 284 and 324, for one, need the hidden quest 90806, or else feature 1886 on. (No
task quest's requirement depends on that reading: read as on, the same 415 quests gain the same ones,
12.1.5.70448.)

A condition's covenant (its CovenantID, or ModifierTree type 288) is read apart:
Get-ConditionCovenants gives the ones every way through the condition needs. So is its text
(Get-ConditionTextKeys): which quests the game holds back with it. So are the renown levels it needs
(Get-ConditionRenowns: a renown currency held in some amount, by the condition's currency columns or
ModifierTree type 119).

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
    foreach ($table in 'QuestLine', 'QuestLineXQuest', 'Campaign', 'CampaignXQuestLine', 'CampaignXCondition', 'ModifierTree') {
        $path = Join-Path $ToolsDir "$table-$Build.csv"
        if (-not (Test-Path $path)) {
            Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path
            Start-Sleep -Seconds 1
        }
    }
    $conditionCsv = Join-Path $ToolsDir 'PlayerCondition.csv'
    if (-not (Test-Path $conditionCsv)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/PlayerCondition/csv?build=$Build" -OutFile $conditionCsv }
    $c = @{ Lines = @{}; LineQuests = @{}; Campaigns = @{}; CampaignLines = @{}; Chapters = @{}; ChapterConditions = @(); Tree = @{}; Children = @{}; Conditions = @{} }
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
        $c.Chapters["$campaign|$([int]$row.OrderIndex)"] = [int]$row.QuestLineID
    }
    foreach ($campaign in $chapters.Keys) { $c.CampaignLines[$campaign] = @($chapters[$campaign] | Sort-Object Order | ForEach-Object { $_.Line }) }
    # A chapter's own gate, with the game's text for when it isn't met: the chapter is the campaign's line
    # of the same OrderIndex (campaign 271 skips one, so it isn't the place in the list).
    $c.ChapterConditions = @(Import-Csv (Join-Path $ToolsDir "CampaignXCondition-$Build.csv") | ForEach-Object {
        [pscustomobject]@{ Id = [int]$_.ID; Campaign = [int]$_.CampaignID; Order = [int]$_.OrderIndex; Condition = [int]$_.PlayerConditionID; Text = $_.FailureReason_lang }
    })
    foreach ($row in Import-Csv (Join-Path $ToolsDir "ModifierTree-$Build.csv")) {
        $id = [int]$row.ID; $parent = [int]$row.Parent
        $c.Tree[$id] = [pscustomobject]@{ Operator = [int]$row.Operator; Amount = [int]$row.Amount; Type = [int]$row.Type; Asset = [int]$row.Asset; Secondary = [int]$row.SecondaryAsset }
        if ($parent) {
            if (-not $c.Children.ContainsKey($parent)) { $c.Children[$parent] = New-Object System.Collections.Generic.List[int] }
            $c.Children[$parent].Add($id)
        }
    }
    Import-Csv $conditionCsv | ForEach-Object {
        $c.Conditions[[int]$_.ID] = [pscustomobject]@{
            Prev = @([int]$_.PrevQuestID_0, [int]$_.PrevQuestID_1, [int]$_.PrevQuestID_2, [int]$_.PrevQuestID_3)
            Logic = [int64]$_.PrevQuestLogic; Tree = [int]$_.ModifierTreeID; Flags = [int]$_.Flags; Covenant = [int]$_.CovenantID
            HasText = [bool]$_.Failure_description_lang
            Currency = @([int]$_.CurrencyID_0, [int]$_.CurrencyID_1, [int]$_.CurrencyID_2, [int]$_.CurrencyID_3)
            Count = @([int]$_.CurrencyCount_0, [int]$_.CurrencyCount_1, [int]$_.CurrencyCount_2, [int]$_.CurrencyCount_3)
            CurrencyLogic = [int64]$_.CurrencyLogic
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
    if (-not $row -or $depth -gt 20 -or ($row.Flags -band 0x100)) { return $null }
    $answer = ConvertFrom-PrevQuests $row
    if ($row.Tree -and -not ($row.Flags -band 0x200)) { $answer = Join-Condition $true $answer (ConvertFrom-ModifierTree $c $row.Tree ($depth + 1)) }
    return $answer
}
# A condition's own quests (PrevQuestID with its logic field) as a tree, without its ModifierTree.
function ConvertFrom-PrevQuests($row) {
    $answer = $null
    for ($i = 0; $i -lt 4; $i++) {
        $quest = $row.Prev[$i]
        $item = if ($quest -gt 0 -and -not ($row.Logic -band (0x10000 -shl $i))) { $quest } else { $null }
        if ($i -eq 0) { $answer = $item; continue }
        $how = [int](($row.Logic -shr (2 * ($i - 1))) -band 3)
        if ($how -eq 1) { $answer = Join-Condition $true $answer $item }
        elseif ($how -eq 2) { $answer = Join-Condition $false $answer $item }
    }
    return $answer
}
function ConvertFrom-ModifierTree($c, [int]$id, [int]$depth) {
    $node = $c.Tree[$id]
    if (-not $node -or $depth -gt 40 -or $node.Operator -eq 3) { return $null }
    $own = switch ($node.Type) {
        110 { $node.Asset }
        2 { ConvertFrom-PlayerCondition $c $node.Asset ($depth + 1) }
        73 { ConvertFrom-ModifierTree $c $node.Asset ($depth + 1) }
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

# The covenants every way through a condition needs: its CovenantID and the type 288 leaves of its tree,
# where a choice needs only those every branch of it does. None for an "N of" group.
function Get-ConditionCovenants($c, [int]$id, [int]$depth = 0) {
    $row = $c.Conditions[$id]
    if (-not $row -or $depth -gt 20 -or ($row.Flags -band 0x100)) { return }
    $found = @()
    if ($row.Covenant) { $found += $row.Covenant }
    if ($row.Tree -and -not ($row.Flags -band 0x200)) { $found += @(Get-TreeCovenants $c $row.Tree ($depth + 1)) }
    $found | Sort-Object -Unique
}
function Get-TreeCovenants($c, [int]$id, [int]$depth) {
    $node = $c.Tree[$id]
    if (-not $node -or $depth -gt 40 -or $node.Operator -eq 3) { return }
    $found = @()
    switch ($node.Type) {
        288 { $found += $node.Asset }
        2 { $found += @(Get-ConditionCovenants $c $node.Asset ($depth + 1)) }
        73 { $found += @(Get-TreeCovenants $c $node.Asset ($depth + 1)) }
    }
    $children = $c.Children[$id]
    if ($children -and $node.Operator -eq 4) {
        foreach ($child in $children) { $found += @(Get-TreeCovenants $c $child ($depth + 1)) }
    } elseif ($children -and $node.Operator -eq 8 -and $node.Amount -le 1) {
        $common = @(); $first = $true
        foreach ($child in $children) {
            $part = @(Get-TreeCovenants $c $child ($depth + 1))
            if ($first) { $common = $part; $first = $false } else { $common = @($common | Where-Object { $part -contains $_ }) }
        }
        $found += $common
    }
    $found | Sort-Object -Unique
}

# The renown levels every way through a condition needs, as faction -> level: a renown currency
# (Faction.RenownCurrencyID; $RenownCurrencies, currency -> faction) held in at least that amount, by the condition's own
# currency columns when their logic field joins them by AND, or by ModifierTree type 119 (Asset the currency,
# SecondaryAsset the amount). Two asks for one faction keep the higher level; a choice needs only what every branch does,
# at the lowest level among them.
function Get-ConditionRenowns($c, [int]$id, $RenownCurrencies, [int]$depth = 0) {
    $need = @{}
    $row = $c.Conditions[$id]
    if (-not $row -or $depth -gt 20 -or ($row.Flags -band 0x100)) { return $need }
    $slots = @(for ($i = 0; $i -lt 4; $i++) {
        $currency = $row.Currency[$i]
        [pscustomobject]@{ On = $currency -gt 0 -and -not ($row.CurrencyLogic -band (0x10000 -shl $i)); Currency = $currency; Count = $row.Count[$i]
            How = $(if ($i -eq 0) { 1 } else { [int](($row.CurrencyLogic -shr (2 * ($i - 1))) -band 3) }) }
    })
    if (-not @($slots | Where-Object { $_.How -eq 2 }).Count) {
        foreach ($slot in $slots) {
            if ($slot.On -and $slot.How -eq 1 -and $RenownCurrencies.ContainsKey($slot.Currency)) { $need = Join-RenownNeeds $need @{ $RenownCurrencies[$slot.Currency] = $slot.Count } }
        }
    }
    if ($row.Tree -and -not ($row.Flags -band 0x200)) { $need = Join-RenownNeeds $need (Get-TreeRenowns $c $row.Tree $RenownCurrencies ($depth + 1)) }
    return $need
}
function Get-TreeRenowns($c, [int]$id, $RenownCurrencies, [int]$depth) {
    $need = @{}
    $node = $c.Tree[$id]
    if (-not $node -or $depth -gt 40 -or $node.Operator -eq 3) { return $need }
    switch ($node.Type) {
        119 { if ($RenownCurrencies.ContainsKey($node.Asset)) { $need = @{ $RenownCurrencies[$node.Asset] = $node.Secondary } } }
        2 { $need = Get-ConditionRenowns $c $node.Asset $RenownCurrencies ($depth + 1) }
        73 { $need = Get-TreeRenowns $c $node.Asset $RenownCurrencies ($depth + 1) }
    }
    $children = $c.Children[$id]
    if ($children -and $node.Operator -eq 4) {
        foreach ($child in $children) { $need = Join-RenownNeeds $need (Get-TreeRenowns $c $child $RenownCurrencies ($depth + 1)) }
    } elseif ($children -and $node.Operator -eq 8 -and $node.Amount -le 1) {
        $common = $null
        foreach ($child in $children) {
            $part = Get-TreeRenowns $c $child $RenownCurrencies ($depth + 1)
            if ($null -eq $common) { $common = $part; continue }
            $kept = @{}
            foreach ($faction in $common.Keys) { if ($part.ContainsKey($faction)) { $kept[$faction] = [Math]::Min($common[$faction], $part[$faction]) } }
            $common = $kept
        }
        if ($common) { $need = Join-RenownNeeds $need $common }
    }
    return $need
}
function Join-RenownNeeds($a, $b) {
    $joined = @{}
    foreach ($faction in $a.Keys) { $joined[$faction] = $a[$faction] }
    foreach ($faction in $b.Keys) { if (-not $joined.ContainsKey($faction) -or $joined[$faction] -lt $b[$faction]) { $joined[$faction] = $b[$faction] } }
    return $joined
}

# The Shadowlands covenants' quest headings ("Kyrian Callings"): QuestSort ID -> covenant, a heading being
# one whose name starts with the covenant's. Only covenants 1 to 4 are the covenants; the table's later
# rows are renown factions.
function Get-CovenantHeadings($QuestSorts, $Covenants) {
    $headings = @{}
    foreach ($covenant in @($Covenants | Where-Object { [int]$_.ID -ge 1 -and [int]$_.ID -le 4 })) {
        foreach ($sort in @($QuestSorts | Where-Object { $_.SortName_lang -like "$($covenant.Name_lang) *" })) { $headings[[int]$sort.ID] = [int]$covenant.ID }
    }
    return $headings
}

# The covenants each quest's client data names, by quest: its task condition ($TaskConditions, quest ->
# ConditionID), the conditions of the quest lines and campaigns it's on, its campaign chapter's own gate,
# and its heading ($Sorts, quest -> the quest cache's sort, whose negative is a QuestSort ID; $Headings,
# QuestSort ID -> covenant). Each that needs one covenant (Get-ConditionCovenants) names it. A quest that
# several covenants name, as the chapters of a quest line all four campaigns share, is open to each of them.
function Get-ClientCovenants($c, $TaskConditions, $Sorts, $Headings) {
    $byCondition = @{}
    function Get-Named([int]$condition) {
        if (-not $byCondition.ContainsKey($condition)) {
            $list = @(Get-ConditionCovenants $c $condition)
            $byCondition[$condition] = if ($list.Count -eq 1) { $list[0] } else { 0 }
        }
        return $byCondition[$condition]
    }
    $named = @{}
    function Add-Named($quests, [int]$covenant) {
        if (-not $covenant) { return }
        foreach ($quest in $quests) {
            if (-not $named.ContainsKey([int]$quest)) { $named[[int]$quest] = @{} }
            $named[[int]$quest][$covenant] = $true
        }
    }
    foreach ($quest in $TaskConditions.Keys) { Add-Named @($quest) (Get-Named $TaskConditions[$quest]) }
    foreach ($line in $c.Lines.Keys) {
        $condition = [int]$c.Lines[$line].PlayerConditionID
        if ($condition) { Add-Named (Get-LineQuests $c $line) (Get-Named $condition) }
    }
    foreach ($campaign in $c.Campaigns.Keys) {
        $condition = [int]$c.Campaigns[$campaign].Prerequisite
        if (-not $condition) { continue }
        $covenant = Get-Named $condition
        foreach ($line in (Get-CampaignLines $c $campaign)) { Add-Named (Get-LineQuests $c $line) $covenant }
    }
    foreach ($gate in $c.ChapterConditions) {
        $line = $c.Chapters["$($gate.Campaign)|$($gate.Order)"]
        if ($line) { Add-Named (Get-LineQuests $c $line) (Get-Named $gate.Condition) }
    }
    foreach ($quest in $Sorts.Keys) {
        $sort = -[int]$Sorts[$quest]
        if ($Headings.ContainsKey($sort)) { Add-Named @($quest) $Headings[$sort] }
    }
    $result = @{}
    foreach ($quest in $named.Keys) { $result[$quest] = @($named[$quest].Keys | Sort-Object) }
    return $result
}

# The conditions whose text the game shows when they aren't met, and the quests of ours each holds back, by key:
# 'p' and a PlayerCondition's ID (Failure_description_lang) for a task quest's condition (each quest's own) and
# for a quest line's or campaign's (the first quest of ours of the line, or of the campaign's first chapter), and
# 'c' and a CampaignXCondition's ID (FailureReason_lang) for a chapter's gate (the first quest of ours of the
# chapter). $quests is our data, by ID. Gives key -> sorted quest IDs, ordered by key.
function Get-ConditionTextKeys($c, $TaskConditions, $quests) {
    $keys = @{}
    function Add-Key([string]$key, $quest) {
        if (-not $quest) { return }
        if (-not $keys.ContainsKey($key)) { $keys[$key] = @{} }
        $keys[$key][[int]$quest] = $true
    }
    function Get-FirstOurs($line) { foreach ($quest in (Get-LineQuests $c $line)) { if ($quests.ContainsKey([int]$quest)) { return [int]$quest } } }
    function Test-Text([int]$condition) { return $condition -and $c.Conditions.ContainsKey($condition) -and $c.Conditions[$condition].HasText }
    foreach ($quest in $TaskConditions.Keys) { if (Test-Text $TaskConditions[$quest]) { Add-Key "p$($TaskConditions[$quest])" $quest } }
    foreach ($line in $c.Lines.Keys) {
        $condition = [int]$c.Lines[$line].PlayerConditionID
        if (Test-Text $condition) { Add-Key "p$condition" (Get-FirstOurs $line) }
    }
    foreach ($campaign in $c.Campaigns.Keys) {
        $condition = [int]$c.Campaigns[$campaign].Prerequisite
        $lines = Get-CampaignLines $c $campaign
        if ((Test-Text $condition) -and $lines.Count) { Add-Key "p$condition" (Get-FirstOurs $lines[0]) }
    }
    foreach ($gate in $c.ChapterConditions) {
        $line = $c.Chapters["$($gate.Campaign)|$($gate.Order)"]
        if ($gate.Text -and $line) { Add-Key "c$($gate.Id)" (Get-FirstOurs $line) }
    }
    $result = [ordered]@{}
    foreach ($key in ($keys.Keys | Sort-Object { $_.Substring(0, 1) }, { [int]$_.Substring(1) })) { $result[$key] = @($keys[$key].Keys | Sort-Object) }
    return $result
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
