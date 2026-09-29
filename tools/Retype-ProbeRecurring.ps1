<#
Retypes quests stored as 1 (normal) that two independent sources say recur:

  - the game client, via the /qc typecheck probe: with the quest's data loaded,
    C_QuestInfoSystem.GetQuestClassification answers Recurring (5), and
  - Blizzard's quest API flags it is_daily (-> 4) or is_weekly (-> 128, the addon's weekly type).

A quest flagged both daily and weekly, or also repeatable, is left alone.

Why both: loaded Recurring alone can't say daily from weekly, and the API flags alone have been
wrong about this addon's data before. Checked against 3,309 quests the API flags daily or weekly,
none of which the loaded client answered Normal.

Input: a copy of the SavedVariables file holding qcQuestTypeProbeResults (WoW drops it from the
live file once the probe is no longer in the TOC), and the API cache in quest_api_cache.

All-or-nothing: if any quest isn't found exactly once as type 1, nothing is written.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [string]$ProbeResults = "C:\Users\alist\RiderProjects\QuestCompletist\tools\quest_type_probe_results.lua"
)

if (-not (Test-Path $ProbeResults)) { throw "Probe results not found at $ProbeResults" }
$probe = [System.IO.File]::ReadAllText($ProbeResults)
$recurring = @{}
foreach ($m in [regex]::Matches($probe, '(?m)^\[(\d+)\] = "(\d+)\|[^|]*\|(\d+),[01-],([01t])",?\s*$')) {
    if ($m.Groups[2].Value -eq "1" -and $m.Groups[3].Value -eq "5" -and $m.Groups[4].Value -eq "1") { $recurring[$m.Groups[1].Value] = $true }
}
if (-not $recurring.Count) { throw "No loaded Recurring answers for type-1 quests in $ProbeResults" }

$questFile = "$AddonDir\qcQuest.lua"
$content = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)
$entryPattern = '(?m)^(\[(\d+)\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",-?\d+,)1,'
# The probe recorded each quest's type as it was then; only quests still typed 1 are candidates,
# so a rerun after an earlier retype finds only new cases.
$stillNormal = @{}
foreach ($m in [regex]::Matches($content, $entryPattern)) { $stillNormal[$m.Groups[2].Value] = $true }

$retype = @{}
foreach ($questId in $recurring.Keys) {
    if (-not $stillNormal.ContainsKey($questId)) { continue }
    $cached = "$ToolsDir\quest_api_cache\$questId.json"
    if (-not (Test-Path $cached)) { continue }
    $json = [System.IO.File]::ReadAllText($cached)
    $isDaily = $json -match '"is_daily":true'
    $isWeekly = $json -match '"is_weekly":true'
    if ($json -match '"is_repeatable":true' -or ($isDaily -and $isWeekly)) { continue }
    if ($isDaily) { $retype[$questId] = 4 }
    elseif ($isWeekly) { $retype[$questId] = 128 }
}

$retyped = 0
$content = [regex]::Replace($content, $entryPattern, {
    param($m)
    if ($retype.ContainsKey($m.Groups[2].Value)) { $script:retyped++; return $m.Groups[1].Value + $retype[$m.Groups[2].Value] + "," }
    return $m.Value
})
if ($retyped -ne $retype.Count) { throw "Expected to retype $($retype.Count) quests, retyped $retyped" }

[System.IO.File]::WriteAllText($questFile, $content, (New-Object System.Text.UTF8Encoding $false))
"Type-1 quests the loaded client calls Recurring: $($recurring.Count)"
"Quests retyped: $retyped"
$retype.GetEnumerator() | Group-Object Value | ForEach-Object { "  to type $($_.Name): $($_.Count)" }
