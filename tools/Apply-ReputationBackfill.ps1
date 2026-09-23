<#
Backfills reputation rewards into qcQuestReputation from quest_reputation_compare.csv
(rows with Kind = api-only, i.e. the API lists a reward and we have none).

Purely additive: rows are inserted into the qcQuestReputation block in quest ID order and no
existing line in qcQuest.lua is touched.

All-or-nothing: any unparseable row, any quest ID already in the table, and any quest ID absent
from qcQuestDatabase aborts the run before anything is written.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$QuestFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"
)

. "$PSScriptRoot\QuestReputation.ps1"

$content = [System.IO.File]::ReadAllText($QuestFile, [System.Text.Encoding]::UTF8)
$lines = $content -split "`r`n"

$existing = Get-QuestReputation $content
$questIds = @{}
foreach ($m in [regex]::Matches($content, '(?m)^\[(\d+)\]=\{')) { $questIds[$m.Groups[1].Value] = $true }

$errors = New-Object System.Collections.Generic.List[string]
$new = @{}
foreach ($row in (Import-Csv "$ToolsDir\quest_reputation_compare.csv" | Where-Object { $_.Kind -eq "api-only" })) {
    $id = $row.QuestID
    if ($existing.ContainsKey($id)) { $errors.Add("$id already has a reputation row"); continue }
    if (-not $questIds.ContainsKey($id)) { $errors.Add("$id is not in qcQuestDatabase"); continue }
    $pairs = New-Object System.Collections.Generic.List[object]
    foreach ($part in ($row.Api -split ";")) {
        if ($part -match '^(\d+)=(-?\d+)$') {
            if ($matches[2] -ne "0") { $pairs.Add([PSCustomObject]@{ Faction = [int]$matches[1]; Value = [int]$matches[2] }) }
        } else { $errors.Add("$id has an unparseable reward: '$part'") }
    }
    if (-not $pairs.Count) { $errors.Add("$id has no non-zero reward"); continue }
    $rendered = ($pairs | Sort-Object Faction | ForEach-Object { "[$($_.Faction)]=$($_.Value)" }) -join ","
    $new[$id] = "{$rendered}"
}

if ($errors.Count) { throw "Refusing to write. $($errors.Count) problem(s):`n" + (($errors | Select-Object -First 20) -join "`n") }

$blockStart = -1; $blockEnd = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^qcQuestReputation = \{') { $blockStart = $i }
    elseif ($blockStart -ge 0 -and $lines[$i] -match '^\}') { $blockEnd = $i; break }
}
if ($blockStart -lt 0 -or $blockEnd -lt 0) { throw "qcQuestReputation block not found" }

$pending = [System.Collections.ArrayList]@($new.Keys | Sort-Object { [int]$_ })
$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Count; $i++) {
    # Rows go in ahead of the first existing row with a higher ID; whatever is left goes in
    # before the closing brace. Blank lines inside the block are stepped over, not treated as a
    # position.
    if ($i -gt $blockStart -and $i -le $blockEnd) {
        $flushBelow = if ($lines[$i] -match '^\s*\[(\d+)\]=') { [int]$matches[1] } elseif ($i -eq $blockEnd) { [int]::MaxValue } else { -1 }
        while ($pending.Count -and $flushBelow -ge 0 -and [int]$pending[0] -lt $flushBelow) {
            $out.Add("`t[$($pending[0])]=$($new[$pending[0]]),")
            $pending.RemoveAt(0)
        }
    }
    $out.Add($lines[$i])
}
if ($pending.Count) { throw "Unplaced rows: $($pending.Count)" }

[System.IO.File]::WriteAllText($QuestFile, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
"Rows added: $($new.Count)"
"qcQuestReputation now holds: $($existing.Count + $new.Count)"
