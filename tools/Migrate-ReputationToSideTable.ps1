<#
One-off migration: moves reputation rewards out of qcQuestDatabase fields 15-17 and into the
qcQuestReputation side table, keyed by quest ID.

Every entry that carries those fields is truncated back to 14 fields by cutting at the top-level
comma that ends field 14 - the rest of the line is never re-rendered. Quest 11's stray 15th field
(a misplaced faction ID, no value) is dropped the same way; its reward is backfilled later with the
other api-only quests.

All-or-nothing: any row that fails to parse or convert aborts the run before anything is written.
#>
param(
    [string]$QuestFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"
)

. "$PSScriptRoot\QuestReputation.ps1"

# The pre-migration reading of fields 16/17, kept here rather than in QuestReputation.ps1:
# that file describes the layout we are moving to, this describes the one we are leaving.
function Get-InlineReputation($f) {
    $set = @{}
    if ($f.Count -ge 17) {
        $fid = $f[15]; $rep = $f[16]
        if ($rep -match '^\{') { foreach ($p in [regex]::Matches($rep, '\[(\d+)\]=(-?\d+)')) { if ($p.Groups[2].Value -ne "0") { $set[$p.Groups[1].Value] = [int]$p.Groups[2].Value } } }
        elseif ($rep -match '^-?\d+$' -and $rep -ne "0" -and $fid -match '^\d+$' -and $fid -ne "0") { $set[$fid] = [int]$rep }
    }
    return $set
}

# Offsets of the top-level commas, so a line can be cut without rebuilding any field.
function Get-TopCommaIndexes($s) {
    $out = New-Object System.Collections.Generic.List[int]
    $depth = 0; $inStr = $false
    for ($i = 0; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($inStr) { if ($ch -eq '\') { $i++ } elseif ($ch -eq '"') { $inStr = $false }; continue }
        if ($ch -eq '"') { $inStr = $true } elseif ($ch -eq '{') { $depth++ } elseif ($ch -eq '}') { $depth-- }
        elseif ($ch -eq ',' -and $depth -eq 0) { $out.Add($i) }
    }
    return ,$out
}

$content = [System.IO.File]::ReadAllText($QuestFile, [System.Text.Encoding]::UTF8)
$lines = $content -split "`r`n"

$dbStart = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^qcQuestDatabase=\{') { $dbStart = $i; break } }
if ($dbStart -lt 0) { throw "qcQuestDatabase not found" }

$errors = New-Object System.Collections.Generic.List[string]
$rewards = @{}
$truncations = @{}
for ($i = $dbStart; $i -lt $lines.Count; $i++) {
    $m = [regex]::Match($lines[$i], '^\[(\d+)\]=\{(.*)\}(,?)$')
    if (-not $m.Success) { continue }
    $id = [int]$m.Groups[1].Value
    $body = $m.Groups[2].Value
    $fields = Split-Top $body
    if ($fields.Count -le 14) { continue }
    if ($fields.Count -gt 17) { $errors.Add("$id has $($fields.Count) fields"); continue }

    $rep = Get-InlineReputation $fields
    if ($rep.Count) {
        $pairs = ($rep.GetEnumerator() | Sort-Object { [int]$_.Key } | ForEach-Object { "[$($_.Key)]=$($_.Value)" }) -join ","
        $rewards[$id] = "{$pairs}"
    }

    $commas = Get-TopCommaIndexes $body
    if ($commas.Count -lt 14) { $errors.Add("$id has only $($commas.Count) top-level commas"); continue }
    $truncations[$i] = "[$id]={" + $body.Substring(0, $commas[13]) + "}" + $m.Groups[3].Value
}

if ($errors.Count) { throw "Refusing to write. Problems:`n" + ($errors -join "`n") }

$repLines = New-Object System.Collections.Generic.List[string]
$repLines.Add("")
$repLines.Add("qcQuestReputation = {  -- QuestId -> {[FactionId]=RepValue}")
$repLines.Add("")
foreach ($id in ($rewards.Keys | Sort-Object)) { $repLines.Add("`t[$id]=$($rewards[$id]),") }
$repLines.Add("}")
$repLines.Add("")

# Sits next to qcRenownLevelRequirements, the other faction table keyed by quest ID.
$anchor = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^qcRenownLevelRequirements = \{') {
        for ($j = $i + 1; $j -lt $lines.Count; $j++) { if ($lines[$j] -match '^\}') { $anchor = $j + 1; break } }
        break
    }
}
if ($anchor -lt 0) { throw "qcRenownLevelRequirements block not found" }

$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($i -eq $anchor) { foreach ($r in $repLines) { $out.Add($r) } }
    if ($truncations.ContainsKey($i)) { $out.Add($truncations[$i]) } else { $out.Add($lines[$i]) }
}

[System.IO.File]::WriteAllText($QuestFile, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
"Truncated entries: $($truncations.Count)"
"Reputation rows written: $($rewards.Count)"
"Inserted qcQuestReputation after line $anchor"
