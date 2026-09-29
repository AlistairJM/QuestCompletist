<#
Report-only. Compares every quest's reputation reward in qcQuest.lua (the
qcQuestReputation side table) against Blizzard's API (rewards.reputations), using
the response cache written by Audit-QuestAccuracy.ps1 (tools/quest_api_cache).
Makes no edits.

How our data is read is defined once in QuestReputation.ps1, which
Audit-QuestAccuracy.ps1 shares.

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

. "$PSScriptRoot\QuestReputation.ps1"

$sideTable = Get-QuestReputation $content

$ours = @{}; $shapes = @{}
$start = [regex]::Match($content, '(?m)^qcQuestDatabase=\{').Index
foreach ($l in ($content.Substring($start) -split "`r`n")) {
    $m = [regex]::Match($l, '^\[(\d+)\]=\{(.*)\},?$'); if (-not $m.Success) { continue }
    $id = $m.Groups[1].Value
    $f = Split-Top $m.Groups[2].Value
    $shapes[$f.Count]++
    $set = if ($sideTable.ContainsKey($id)) { $sideTable[$id] } else { @{} }
    $ours[$id] = @{ Rep = $set; Fields = $f.Count }
}

$orphans = @($sideTable.Keys | Where-Object { -not $ours.ContainsKey($_) })

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
"qcQuestReputation rows: $($sideTable.Count)" + $(if ($orphans.Count) { " (WARNING - $($orphans.Count) not in qcQuestDatabase: $($orphans -join ','))" } else { "" })
"Quests the API 404s on (no reputation source): $noApi"
"Comparison: " + (($summary.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ", ")
"API-only rows with more than one faction: $(@($rows | Where-Object { $_.Kind -eq 'api-only' -and $_.Api -match ';' }).Count)"
"Reward factions missing from qcFactions: $($unknown.Count)"
$unknown.GetEnumerator() | Sort-Object { [int]$_.Key } | ForEach-Object { "  [$($_.Key)] $($_.Value)" }
"Rows written: $($rows.Count) -> $outFile"
