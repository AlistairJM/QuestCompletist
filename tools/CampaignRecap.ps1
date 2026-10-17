# The campaign recap (LoreTextPublic): the chapters a campaign's overview tells again, in order, each shown once its
# PlayerCondition is met. Dot-sourced by Compare-CampaignRecap.ps1 (docs/maintenance.md, step 2q), with
# QuestConditions.ps1 and AddonData.ps1. docs/plans/client-tables-audit.md, opportunity 7.
#
# Most of the conditions name the quest whose completion shows the chapter (PrevQuestID; else a quest the condition's
# ModifierTree asks for), so the recap orders those quests. It is a check of our chains, not a source of them: where the
# recap and Blizzard's own quest lines disagree, our chains follow the lines.

# Each recap entry: Campaign, Order, Condition and Quest (the first quest its condition names, 0 for none).
function Get-RecapEntries($c, $loreRows) {
    foreach ($r in $loreRows) {
        $condition = [int]$r.ConditionID
        $quest = 0
        $row = $c.Conditions[$condition]
        if ($row) {
            $own = @($row.Prev | Where-Object { $_ -gt 0 })
            if ($own.Count) { $quest = $own[0] }
            else {
                $gate = ConvertFrom-PlayerCondition $c $condition
                if ($null -ne $gate -and $gate -isnot [string]) { $named = Get-ConditionQuests $gate; if ($named.Count) { $quest = $named[0] } }
            }
        }
        [pscustomobject]@{ Campaign = [int]$r.CampaignID; Order = [int]$r._Order; Condition = $condition; Quest = [int]$quest }
    }
}

# The quests a quest needs before it, however far back, by our data ($quests: ID -> record).
function Get-QuestsBefore($quests, [int]$id, $memo) {
    if ($memo.ContainsKey($id)) { return , $memo[$id] }
    $set = New-Object 'System.Collections.Generic.HashSet[int]'
    $stack = New-Object System.Collections.Generic.Stack[int]
    $stack.Push($id)
    while ($stack.Count) {
        $x = $stack.Pop()
        $q = $quests[$x]
        if (-not $q -or $null -eq $q.prereq) { continue }
        $needs = Get-PrereqQuests $q.prereq
        foreach ($p in $needs) { if ($set.Add([int]$p)) { $stack.Push([int]$p) } }
    }
    $memo[$id] = $set
    return , $set
}

# The pairs of a campaign's recap entries next to each other (among those whose quest is ours, by Order) where our data
# makes the earlier entry's quest need the later one's: Campaign, Order, Quest, LaterOrder, Later. Compared counts the
# pairs looked at.
function Get-RecapReversals($entries, $quests) {
    $memo = @{}
    $reversed = New-Object System.Collections.Generic.List[object]
    $compared = 0
    foreach ($group in ($entries | Where-Object { $_.Quest -and $quests.ContainsKey($_.Quest) } | Group-Object Campaign)) {
        $seq = @($group.Group | Sort-Object Order)
        for ($i = 1; $i -lt $seq.Count; $i++) {
            $a = $seq[$i - 1]; $b = $seq[$i]
            if ($a.Quest -eq $b.Quest) { continue }
            $compared++
            if ((Get-QuestsBefore $quests $a.Quest $memo).Contains($b.Quest)) {
                $reversed.Add([pscustomobject]@{ Campaign = $a.Campaign; Order = $a.Order; Quest = $a.Quest; LaterOrder = $b.Order; Later = $b.Quest })
            }
        }
    }
    return [pscustomobject]@{ Compared = $compared; Reversed = $reversed.ToArray() }
}

# The KEEP rows of docs\plans\campaign-recap-decisions.csv: "campaign|quest|later" -> the row.
function Read-RecapDecisions([string]$path) {
    $rows = @{}
    if (-not (Test-Path $path)) { return $rows }
    foreach ($row in (Import-Csv $path -Encoding UTF8)) {
        if ($row.Decision -ne 'KEEP') { throw "campaign-recap-decisions.csv: campaign $($row.Campaign), quests $($row.Quest) and $($row.Later) have decision '$($row.Decision)'; only KEEP is known." }
        $key = "$([int]$row.Campaign)|$([int]$row.Quest)|$([int]$row.Later)"
        if ($rows.ContainsKey($key)) { throw "campaign-recap-decisions.csv: campaign $($row.Campaign), quests $($row.Quest) and $($row.Later) are listed twice." }
        $rows[$key] = $row
    }
    return $rows
}
