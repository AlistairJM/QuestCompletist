<#
Brings qcQuestReputation in line with the API, from quest_reputation_compare.csv:
  - api-only rows (the API lists a reward and we have none) are inserted in quest ID order;
  - differ rows (both list rewards, but not the same) have their line replaced with the API's.
ours-only rows (we list a reward the API doesn't) are left alone and counted: review them by hand,
as the API may simply not list a reward the game gives.

No other line in qcQuest.lua is touched.

All-or-nothing: any unparseable row, an api-only quest that already has a row, a differ quest that
has none, and any quest ID absent from data\quests.jsonl abort the run before anything is written.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$QuestFile = (Join-Path $PSScriptRoot '..\QuestCompletist\qcQuest.lua')
)

. "$PSScriptRoot\QuestReputation.ps1"
. "$PSScriptRoot\AddonData.ps1"

$content = [System.IO.File]::ReadAllText($QuestFile, [System.Text.Encoding]::UTF8)
$lines = $content -split "`r`n"

$existing = Get-QuestReputation $content
$questIds = @{}
foreach ($quest in (Read-QuestData $DataDir)) { $questIds[[string]$quest.id] = $true }

$errors = New-Object System.Collections.Generic.List[string]
$new = @{}; $replace = @{}; $oursOnly = 0
foreach ($row in (Import-Csv "$ToolsDir\quest_reputation_compare.csv")) {
    $id = $row.QuestID
    if ($row.Kind -eq "ours-only") { $oursOnly++; continue }
    if ($row.Kind -ne "api-only" -and $row.Kind -ne "differ") { continue }
    if ($row.Kind -eq "api-only" -and $existing.ContainsKey($id)) { $errors.Add("$id already has a reputation row"); continue }
    if ($row.Kind -eq "differ" -and -not $existing.ContainsKey($id)) { $errors.Add("$id has no reputation row to correct"); continue }
    if (-not $questIds.ContainsKey($id)) { $errors.Add("$id is not in quests.jsonl"); continue }
    $pairs = New-Object System.Collections.Generic.List[object]
    foreach ($part in ($row.Api -split ";")) {
        if ($part -match '^(\d+)=(-?\d+)$') {
            if ($matches[2] -ne "0") { $pairs.Add([PSCustomObject]@{ Faction = [int]$matches[1]; Value = [int]$matches[2] }) }
        } else { $errors.Add("$id has an unparseable reward: '$part'") }
    }
    if (-not $pairs.Count) { $errors.Add("$id has no non-zero reward"); continue }
    $rendered = ($pairs | Sort-Object Faction | ForEach-Object { "[$($_.Faction)]=$($_.Value)" }) -join ","
    if ($row.Kind -eq "api-only") { $new[$id] = "{$rendered}" } else { $replace[$id] = "{$rendered}" }
}

if ($errors.Count) { throw "Refusing to write. $($errors.Count) problem(s):`n" + (($errors | Select-Object -First 20) -join "`n") }

$blockStart = -1; $blockEnd = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^qcQuestReputation = \{') { $blockStart = $i }
    elseif ($blockStart -ge 0 -and $lines[$i] -match '^\}') { $blockEnd = $i; break }
}
if ($blockStart -lt 0 -or $blockEnd -lt 0) { throw "qcQuestReputation block not found" }

$pending = [System.Collections.ArrayList]@($new.Keys | Sort-Object { [int]$_ })
$replaced = 0
$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Count; $i++) {
    # Rows go in ahead of the first existing row with a higher ID; whatever is left goes in
    # before the closing brace. Blank lines inside the block are stepped over, not treated as a
    # position.
    $line = $lines[$i]
    if ($i -gt $blockStart -and $i -le $blockEnd) {
        $rowId = if ($line -match '^\s*\[(\d+)\]=') { $matches[1] } else { $null }
        $flushBelow = if ($rowId) { [int]$rowId } elseif ($i -eq $blockEnd) { [int]::MaxValue } else { -1 }
        while ($pending.Count -and $flushBelow -ge 0 -and [int]$pending[0] -lt $flushBelow) {
            $out.Add("`t[$($pending[0])]=$($new[$pending[0]]),")
            $pending.RemoveAt(0)
        }
        if ($rowId -and $replace.ContainsKey($rowId)) { $line = "`t[$rowId]=$($replace[$rowId]),"; $replaced++ }
    }
    $out.Add($line)
}
if ($pending.Count) { throw "Unplaced rows: $($pending.Count)" }
if ($replaced -ne $replace.Count) { throw "Only $replaced of the $($replace.Count) rows to correct were found." }

[System.IO.File]::WriteAllText($QuestFile, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
"Rows added: $($new.Count); corrected: $replaced"
"Rewards only we list, left for review: $oursOnly"
"qcQuestReputation now holds: $($existing.Count + $new.Count)"
