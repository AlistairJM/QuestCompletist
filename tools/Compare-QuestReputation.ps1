<#
Report-only. Compares every quest's reputation reward in qcQuest.lua (fields 16/17)
against Blizzard's API (rewards.reputations), using the response cache written by
Audit-QuestAccuracy.ps1 (tools/quest_api_cache). Makes no edits.

Only entries with 17 fields carry reputation; 14-field entries stop at the prereq
field and have none. Field 17 is either a number (paired with the faction ID in
field 16) or a {[factionID]=value} table.

Output: quest_reputation_compare.csv (one row per quest where ours and the API differ)
plus a summary on stdout.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$QuestFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"
)

$content = [System.IO.File]::ReadAllText($QuestFile)

$qcFactions = @{}
$fm = [regex]::Match($content, '(?s)qcFactions = \{(.*?)\n\}')
foreach ($m in [regex]::Matches($fm.Groups[1].Value, '\[(\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"')) { $qcFactions[$m.Groups[1].Value] = $m.Groups[2].Value }

# Splits on top-level commas only, so quoted names and {..} tables stay intact.
function Split-Top($s) {
    $out = New-Object System.Collections.Generic.List[string]
    $depth = 0; $inStr = $false; $cur = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($inStr) { [void]$cur.Append($ch); if ($ch -eq '\') { $i++; [void]$cur.Append($s[$i]) } elseif ($ch -eq '"') { $inStr = $false }; continue }
        if ($ch -eq '"') { $inStr = $true } elseif ($ch -eq '{') { $depth++ } elseif ($ch -eq '}') { $depth-- }
        if ($ch -eq ',' -and $depth -eq 0) { $out.Add($cur.ToString()); [void]$cur.Clear() } else { [void]$cur.Append($ch) }
    }
    $out.Add($cur.ToString())
    return ,$out
}

$ours = @{}; $shapes = @{}
$start = [regex]::Match($content, '(?m)^qcQuestDatabase=\{').Index
foreach ($l in ($content.Substring($start) -split "`r`n")) {
    $m = [regex]::Match($l, '^\[(\d+)\]=\{(.*)\},?$'); if (-not $m.Success) { continue }
    $f = Split-Top $m.Groups[2].Value
    $shapes[$f.Count]++
    $set = @{}
    if ($f.Count -ge 17) {
        $fid = $f[15]; $rep = $f[16]
        if ($rep -match '^\{') { foreach ($p in [regex]::Matches($rep, '\[(\d+)\]=(-?\d+)')) { if ($p.Groups[2].Value -ne "0") { $set[$p.Groups[1].Value] = [int]$p.Groups[2].Value } } }
        elseif ($rep -match '^-?\d+$' -and $rep -ne "0" -and $fid -match '^\d+$' -and $fid -ne "0") { $set[$fid] = [int]$rep }
    }
    $ours[$m.Groups[1].Value] = @{ Rep = $set; Fields = $f.Count }
}

function Format-Set($h) { return (($h.GetEnumerator() | Sort-Object { [int]$_.Key } | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ";") }

$summary = @{}; $unknown = @{}; $noApi = 0
$rows = New-Object System.Collections.Generic.List[object]
foreach ($id in $ours.Keys) {
    $path = "$ToolsDir\quest_api_cache\$id.json"
    if (-not (Test-Path $path)) { $noApi++; continue }
    $j = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
    $api = @{}; $names = @{}
    if ($j.rewards -and $j.rewards.reputations) {
        foreach ($r in $j.rewards.reputations) {
            $api["$($r.reward.id)"] = [int]$r.value; $names["$($r.reward.id)"] = $r.reward.name
            if (-not $qcFactions.ContainsKey("$($r.reward.id)")) { $unknown["$($r.reward.id)"] = $r.reward.name }
        }
    }
    $o = $ours[$id].Rep
    $a = Format-Set $api; $b = Format-Set $o
    $kind = if (-not $o.Count -and -not $api.Count) { "neither" } elseif (-not $o.Count) { "api-only" } elseif (-not $api.Count) { "ours-only" } elseif ($a -eq $b) { "match" } else { "differ" }
    $summary[$kind]++
    if ($kind -in "api-only", "ours-only", "differ") {
        $rows.Add([PSCustomObject]@{ QuestID = $id; Kind = $kind; OurFields = $ours[$id].Fields; Ours = $b; Api = $a; ApiFactionNames = (($names.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ";") })
    }
}

$outFile = "$ToolsDir\quest_reputation_compare.csv"
$rows | Sort-Object { [int]$_.QuestID } | Export-Csv $outFile -NoTypeInformation -Encoding utf8
"Entry shapes: " + (($shapes.GetEnumerator() | Sort-Object { [int]$_.Key } | ForEach-Object { "$($_.Key) fields=$($_.Value)" }) -join ", ")
"Quests the API 404s on (no reputation source): $noApi"
"Comparison: " + (($summary.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ", ")
"API-only rows with more than one faction: $(@($rows | Where-Object { $_.Kind -eq 'api-only' -and $_.Api -match ';' }).Count)"
"Reward factions missing from qcFactions: $($unknown.Count)"
$unknown.GetEnumerator() | Sort-Object { [int]$_.Key } | ForEach-Object { "  [$($_.Key)] $($_.Value)" }
"Rows written: $($rows.Count) -> $outFile"
