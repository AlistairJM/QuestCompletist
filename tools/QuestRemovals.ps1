# Dot-sourced by Import-ForeverData.ps1 and Show-RemovedQuests.ps1: which quests a data file has lost, and the
# decisions (docs\plans\quest-removal-decisions.csv) that say what to do about them.

function Read-QuestIdLines([string]$text) {
    $lines = @{}
    foreach ($line in ($text -split "`n")) {
        if ($line -match '^\s*\{"id":(\d+)[,}]') { $lines[[int]$Matches[1]] = $line.Trim() }
    }
    return $lines
}

function Find-RemovedQuests([string]$oldText, $newIds) {
    $removed = New-Object System.Collections.Generic.List[object]
    $old = Read-QuestIdLines $oldText
    foreach ($id in ($old.Keys | Sort-Object)) {
        if ($newIds.ContainsKey($id)) { continue }
        $row = $old[$id] | ConvertFrom-Json
        $removed.Add([pscustomobject]@{ Id = $id; Name = [string]$row.name; Zone = [string]$row.zone; Level = $row.level })
    }
    return $removed.ToArray()
}

function Read-RemovalDecisions([string]$path, [string]$game) {
    $decisions = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $path)) { return $decisions.ToArray() }
    foreach ($row in (Import-Csv -LiteralPath $path)) {
        if ($row.Game -ne $game) { continue }
        if ($row.Decision -notin 'KEEP', 'REMOVE') { throw "$path gives quest $($row.Quest) the decision '$($row.Decision)': it must be KEEP or REMOVE." }
        if ($row.Quest -notmatch '^\d+$') { throw "$path has a row whose quest, '$($row.Quest)', is not a number." }
        $decisions.Add([pscustomobject]@{ Quest = [int]$row.Quest; Decision = $row.Decision; Reason = $row.Reason })
    }
    return $decisions.ToArray()
}

function Format-RemovedQuests($removed, $decided) {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($q in $removed) {
        $state = if ($decided.ContainsKey($q.Id)) { 'REMOVE decided' } else { 'UNDECIDED' }
        $lines.Add(('  {0,7}  {1,-48} {2,-24} level {3,-3} {4}' -f $q.Id, $q.Name, $q.Zone, $q.Level, $state))
    }
    return $lines.ToArray()
}
