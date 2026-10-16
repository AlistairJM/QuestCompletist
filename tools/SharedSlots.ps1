# Quests on one completion switch, for Sync-SharedSlotLinks.ps1 (docs/maintenance.md, step 2k) and its test.
# The client's QuestV2.UniqueBitFlag is a quest's bit in the character's completed-quest record
# (TrinityCore's Player::SetQuestCompletedBit), and quests that share one are completed together: the game
# reports every quest on a switch as done once one of them is (proven on 780 groups of a retail character and
# 16 of two Forever characters, 16 October 2026). docs/plans/client-tables-audit.md, opportunity 1.

$SharedSlotRecurringTypes = 2 + 4 + 128

function Get-PairKey([int]$a, [int]$b) {
    return "$([Math]::Min($a, $b))|$([Math]::Max($a, $b))"
}

# Quest ID -> switch, from QuestV2's rows (ID, UniqueBitFlag).
function Get-QuestSlots($questV2Rows) {
    $slots = @{}
    foreach ($row in $questV2Rows) { $slots[[int]$row.ID] = [int]$row.UniqueBitFlag }
    return $slots
}

# Switch -> our non-recurring quests on it, for switches holding two or more of them.
function Get-SharedSlotGroups($slots, $quests) {
    $groups = @{}
    foreach ($id in $quests.Keys) {
        if (-not $slots.ContainsKey([int]$id)) { continue }
        if (([int]$quests[$id].type -band $SharedSlotRecurringTypes) -ne 0) { continue }
        $groups[$slots[[int]$id]] += @([int]$id)
    }
    foreach ($slot in @($groups.Keys)) {
        if ($groups[$slot].Count -lt 2) { $groups.Remove($slot) } else { $groups[$slot] = @($groups[$slot] | Sort-Object) }
    }
    return $groups
}

# Whether one character could be offered both quests: their faction, class and race limits overlap.
function Test-OneCharacterCanMeet($a, $b) {
    if ((([int]$a.faction) -band ([int]$b.faction)) -eq 0) { return $false }
    if ((([long]$a.class) -band ([long]$b.class)) -eq 0) { return $false }
    if ((([long]$a.race) -band ([long]$b.race)) -eq 0) { return $false }
    return $true
}

# The pairs a shared switch makes "only one of these": quests of different names that one character could
# be offered. Quests of one name on a switch are the same quest for each faction, class or covenant, which the
# game's own completed list already ticks together.
function Get-SharedSlotPairs($groups, $quests) {
    $pairs = New-Object System.Collections.ArrayList
    foreach ($slot in ($groups.Keys | Sort-Object)) {
        $ids = $groups[$slot]
        for ($i = 0; $i -lt $ids.Count; $i++) {
            for ($j = $i + 1; $j -lt $ids.Count; $j++) {
                $a = $quests[$ids[$i]]; $b = $quests[$ids[$j]]
                if ($a.name -ceq $b.name) { continue }
                if (-not (Test-OneCharacterCanMeet $a $b)) { continue }
                [void]$pairs.Add([pscustomobject]@{ Slot = $slot; A = [int]$ids[$i]; B = [int]$ids[$j] })
            }
        }
    }
    return , $pairs
}

# The text of a Lua table assigned at the start of a line ("name = {" to its closing "}"), with where it starts.
function Find-LuaTable([string]$text, [string]$name) {
    $m = [regex]::Match($text, "(?m)^$([regex]::Escape($name))\s*=\s*\{")
    if (-not $m.Success) { throw "No table $name in the file." }
    $depth = 0
    for ($i = $m.Index + $m.Length - 1; $i -lt $text.Length; $i++) {
        $c = $text[$i]
        if ($c -eq '-' -and $i + 1 -lt $text.Length -and $text[$i + 1] -eq '-') {
            $end = $text.IndexOf("`n", $i); if ($end -lt 0) { $end = $text.Length }
            $i = $end; continue
        }
        if ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return [pscustomobject]@{ Start = $m.Index; Open = $m.Index + $m.Length; Close = $i } } }
    }
    throw "Table $name has no closing brace."
}

# A table of quest ID -> list of quest IDs ([1] = {2, 3}), as pairs. Commented-out lines are skipped.
function Read-LuaQuestLists([string]$text, [string]$name) {
    $t = Find-LuaTable $text $name
    $body = $text.Substring($t.Open, $t.Close - $t.Open)
    $lists = @{}
    foreach ($line in ($body -split "`n")) {
        $code = ($line -replace '--.*$', '')
        foreach ($e in [regex]::Matches($code, '\[(\d+)\]\s*=\s*\{([^}]*)\}')) {
            $lists[[int]$e.Groups[1].Value] += @([regex]::Matches($e.Groups[2].Value, '\d+') | ForEach-Object { [int]$_.Value })
        }
    }
    return $lists
}

# Pair key -> $true for every pair of a quest-list table (either direction).
function Get-ListPairs($lists) {
    $pairs = @{}
    foreach ($id in $lists.Keys) { foreach ($other in $lists[$id]) { $pairs[(Get-PairKey $id $other)] = $true } }
    return $pairs
}

# Forever's links (data\forever\links.jsonl): exclusive and breadcrumb pairs.
function Read-ForeverLinkPairs($lines) {
    $exclusive = @{}; $breadcrumb = @{}
    foreach ($line in $lines) {
        if (-not $line.Trim()) { continue }
        $o = $line | ConvertFrom-Json
        foreach ($b in @($o.exclusiveWith)) { if ($b) { $exclusive[(Get-PairKey $o.quest $b)] = $true } }
        foreach ($b in @($o.breadcrumbs)) { if ($b) { $breadcrumb[(Get-PairKey $o.quest $b)] = $true } }
    }
    return [pscustomobject]@{ Exclusive = $exclusive; Breadcrumb = $breadcrumb }
}

# The "exclusive" rows of a link-decisions file (Quest, Name, Link, Other, Decision, Evidence): ADD links a pair,
# REMOVE unlinks it, SKIP leaves a shared-switch pair unlinked, KEEP keeps a link the evidence questions. A SKIP
# covers every pair its rows join, so a group needs only a chain of rows.
function Read-SharedSlotDecisions($rows, [string]$file = 'the decisions file') {
    $byPair = @{}
    $parent = @{}
    function Root($x) { while ($parent[$x] -ne $x) { $parent[$x] = $parent[$parent[$x]]; $x = $parent[$x] }; return $x }
    foreach ($row in $rows) {
        if ($row.Link -ne 'exclusive') { continue }
        if (@('ADD', 'REMOVE', 'SKIP', 'KEEP') -cnotcontains $row.Decision) { throw "$file gives quests $($row.Quest) and $($row.Other) the exclusive decision '$($row.Decision)': it is ADD, REMOVE, SKIP or KEEP." }
        $a = [int]$row.Quest; $b = [int]$row.Other
        $key = Get-PairKey $a $b
        if ($byPair.ContainsKey($key)) { throw "$file decides the link between quests $a and $b twice." }
        $byPair[$key] = $row.Decision
        if ($row.Decision -eq 'SKIP') {
            foreach ($x in $a, $b) { if (-not $parent.ContainsKey($x)) { $parent[$x] = $x } }
            $ra = Root $a; $rb = Root $b
            if ($ra -ne $rb) { $parent[$ra] = $rb }
        }
    }
    $skipped = @{}
    foreach ($x in @($parent.Keys)) { $skipped[$x] = Root $x }
    return [pscustomobject]@{ ByPair = $byPair; SkipGroup = $skipped }
}

function Get-PairDecision($decisions, [int]$a, [int]$b) {
    $key = Get-PairKey $a $b
    if ($decisions.ByPair.ContainsKey($key)) { return $decisions.ByPair[$key] }
    if ($decisions.SkipGroup.ContainsKey($a) -and $decisions.SkipGroup.ContainsKey($b) -and $decisions.SkipGroup[$a] -eq $decisions.SkipGroup[$b]) { return 'SKIP' }
    return $null
}

# What the sweep reports. Findings need a decision; counts are for the record.
#   exclusive: pair key -> $true (the table, or Forever's links); breadcrumb: the same for breadcrumb links.
#   completions: the probe's rows (Ids: a set of quest IDs), for "the game says one character did both".
function Get-SharedSlotFindings($pairs, $slots, $quests, $exclusive, $breadcrumb, $decisions, $completions) {
    $findings = New-Object System.Collections.ArrayList
    $add = { param($kind, $a, $b, $detail)
        [void]$findings.Add([pscustomobject]@{ Kind = $kind; Quest = $a; Other = $b; Decision = (Get-PairDecision $decisions $a $b); Detail = $detail }) }
    foreach ($p in $pairs) {
        $key = Get-PairKey $p.A $p.B
        if ($exclusive.ContainsKey($key) -or $breadcrumb.ContainsKey($key)) { continue }
        if ($null -ne (Get-PairDecision $decisions $p.A $p.B)) { continue }
        & $add 'one switch, not linked' $p.A $p.B "switch $($p.Slot)"
    }
    foreach ($key in ($decisions.ByPair.Keys | Sort-Object)) {
        $a, $b = $key.Split('|') | ForEach-Object { [int]$_ }
        if ($decisions.ByPair[$key] -eq 'ADD' -and -not $exclusive.ContainsKey($key) -and $quests.ContainsKey($a) -and $quests.ContainsKey($b)) { & $add 'decided ADD, not yet in the table' $a $b '' }
        if ($decisions.ByPair[$key] -eq 'REMOVE' -and $exclusive.ContainsKey($key)) { & $add 'decided REMOVE, still in the table' $a $b '' }
    }
    foreach ($key in ($decisions.ByPair.Keys | Sort-Object)) {
        if ($decisions.ByPair[$key] -ne 'ADD') { continue }
        $a, $b = $key.Split('|') | ForEach-Object { [int]$_ }
        if ($slots.ContainsKey($a) -and $slots.ContainsKey($b) -and $slots[$a] -eq $slots[$b]) { continue }
        & $add 'added for one switch, no longer on one' $a $b "switches $($slots[$a]) and $($slots[$b])"
    }
    $counts = [ordered]@{ Linked = 0; ConfirmedBySwitch = 0; NotOnOneSwitch = 0; BreadcrumbsOnOneSwitch = 0; CompletedBoth = 0 }
    foreach ($key in ($exclusive.Keys | Sort-Object)) {
        $a, $b = $key.Split('|') | ForEach-Object { [int]$_ }
        $counts.Linked++
        $sameSwitch = $slots.ContainsKey($a) -and $slots.ContainsKey($b) -and $slots[$a] -eq $slots[$b]
        if ($sameSwitch) { $counts.ConfirmedBySwitch++; continue }
        $counts.NotOnOneSwitch++
        $who = @($completions | Where-Object { $_.Ids.Contains($a) -and $_.Ids.Contains($b) })
        if ($who.Count) {
            $counts.CompletedBoth++
            if ((Get-PairDecision $decisions $a $b) -notin 'KEEP', 'REMOVE') {
                & $add 'linked, but the game says one character did both' $a $b (($who | ForEach-Object { "$($_.Character) level $($_.Level) on $($_.Build)" }) -join '; ')
            }
        }
    }
    foreach ($key in $breadcrumb.Keys) {
        $a, $b = $key.Split('|') | ForEach-Object { [int]$_ }
        if ($slots.ContainsKey($a) -and $slots.ContainsKey($b) -and $slots[$a] -eq $slots[$b]) { $counts.BreadcrumbsOnOneSwitch++ }
    }
    return [pscustomobject]@{ Findings = $findings; Counts = $counts }
}

# The pairs the decisions want in the table and out of it, against what it holds.
function Get-SharedSlotChanges($decisions, $exclusive, $quests) {
    $adds = @(); $removes = @()
    foreach ($key in ($decisions.ByPair.Keys | Sort-Object)) {
        $a, $b = $key.Split('|') | ForEach-Object { [int]$_ }
        switch ($decisions.ByPair[$key]) {
            'ADD' { if (-not $exclusive.ContainsKey($key) -and $quests.ContainsKey($a) -and $quests.ContainsKey($b)) { $adds += , @($a, $b) } }
            'REMOVE' { if ($exclusive.ContainsKey($key)) { $removes += , @($a, $b) } }
        }
    }
    return [pscustomobject]@{ Adds = $adds; Removes = $removes }
}

# qcQuest.lua with the pairs added to and removed from qcMutuallyExclusive, and the quests of removed pairs added to
# qcFormerlyExclusive (so the addon drops ticks the server doesn't confirm). Entries written by hand keep their line and
# comment; a quest with no hand entry goes into the section after the marker, which is written afresh each time.
$SharedSlotMarker = '-- Quests on one completion switch: docs/plans/quest-link-decisions.csv, tools\Sync-SharedSlotLinks.ps1'
function Set-ExclusiveLinks([string]$text, $adds, $removes) {
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $t = Find-LuaTable $text 'qcMutuallyExclusive'
    $lines = $text.Substring($t.Open, $t.Close - $t.Open) -split "`r?`n"
    $markerLine = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -ceq $SharedSlotMarker) { $markerLine = $i; break } }
    $handLines = if ($markerLine -ge 0) { @($lines[0..($markerLine - 1)]) } else { @($lines) }
    $entry = '\[(\d+)\]\s*=\s*\{([^}]*)\}'
    $codeOf = { param($line) $at = $line.IndexOf('--'); if ($at -ge 0) { $line.Substring(0, $at) } else { $line } }
    $final = @{}; $hand = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq $markerLine) { continue }
        foreach ($e in [regex]::Matches((& $codeOf $lines[$i]), $entry)) {
            $id = [int]$e.Groups[1].Value
            if ($markerLine -lt 0 -or $i -lt $markerLine) { $hand[$id] = $true }
            if (-not $final.ContainsKey($id)) { $final[$id] = New-Object System.Collections.Generic.List[int] }
            foreach ($o in [regex]::Matches($e.Groups[2].Value, '\d+')) { if (-not $final[$id].Contains([int]$o.Value)) { $final[$id].Add([int]$o.Value) } }
        }
    }
    foreach ($p in $adds) {
        foreach ($pair in @(@($p[0], $p[1]), @($p[1], $p[0]))) {
            if (-not $final.ContainsKey($pair[0])) { $final[$pair[0]] = New-Object System.Collections.Generic.List[int] }
            if (-not $final[$pair[0]].Contains($pair[1])) { $final[$pair[0]].Add($pair[1]) }
        }
    }
    $formerly = @()
    foreach ($p in $removes) {
        foreach ($pair in @(@($p[0], $p[1]), @($p[1], $p[0]))) { if ($final.ContainsKey($pair[0])) { [void]$final[$pair[0]].Remove($pair[1]) } }
        $formerly += $p[0], $p[1]
    }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $handLines) {
        $code = & $codeOf $line
        $comment = $line.Substring($code.Length)
        if (-not [regex]::IsMatch($code, $entry)) { $out.Add($line); continue }
        $newCode = [regex]::Replace($code, "$entry,?", {
            param($m)
            $id = [int]$m.Groups[1].Value
            $before = @([regex]::Matches($m.Groups[2].Value, '\d+') | ForEach-Object { [int]$_.Value })
            $after = @($before | Where-Object { $final[$id].Contains($_) }) + @($final[$id] | Where-Object { $before -notcontains $_ })
            if (-not $after.Count) { return '' }
            $sep = if ($m.Groups[2].Value -match ',\s') { ', ' } else { ',' }
            return $m.Value.Substring(0, $m.Groups[2].Index - $m.Index) + ($after -join $sep) + '},'
        })
        if ($newCode.Trim() -eq '') { continue }
        $out.Add($newCode + $comment)
    }
    while ($out.Count -and $out[$out.Count - 1].Trim() -eq '') { $out.RemoveAt($out.Count - 1) }
    $section = @(foreach ($id in ($final.Keys | Sort-Object)) {
        if ($hand.ContainsKey($id) -or -not $final[$id].Count) { continue }
        "`t[$id]={$((@($final[$id]) | Sort-Object) -join ',')},"
    })
    $body = ($out -join $nl) + $nl
    if ($section.Count) { $body += $nl + "`t" + $SharedSlotMarker + $nl + ($section -join $nl) + $nl }
    $text = $text.Substring(0, $t.Open) + $body + $text.Substring($t.Close)
    if ($formerly.Count) {
        $m = [regex]::Match($text, '(?m)^qcFormerlyExclusive\s*=\s*\{([^}]*)\}')
        if (-not $m.Success) { throw 'No qcFormerlyExclusive table in the file.' }
        $ids = @(@([regex]::Matches($m.Groups[1].Value, '\d+') | ForEach-Object { [int]$_.Value }) + $formerly | Sort-Object -Unique)
        $text = $text.Substring(0, $m.Groups[1].Index) + ($ids -join ',') + $text.Substring($m.Groups[1].Index + $m.Groups[1].Length)
    }
    return $text
}

