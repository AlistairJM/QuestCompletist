<#
Retypes quests stored as 128 ("world quest or weekly") that Blizzard's quest API explicitly flags
as daily or repeatable, and that the client's task-quest table (QuestV2CliTask) has no row for -
so they are not world quests either.

  is_daily      -> 4, daily. Resets daily instead of weekly; hidden by the daily filter.
  is_repeatable -> 2, repeatable (only when not also flagged daily).

Quests flagged is_weekly are left alone: 128 is also this addon's weekly type. So are quests the
API has no flag for at all. That is NOT evidence they are one-time: Dragonflight's weekly
profession quests, Shadowlands' "Trading Favors" and The War Within's weekly dungeon quests all
come back unflagged.

All-or-nothing: if any quest isn't found exactly once as type 128, nothing is written.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist"
)

$questFile = "$AddonDir\qcQuest.lua"
$content = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)

$taskQuests = @{}
if (-not (Test-Path "$ToolsDir\QuestV2CliTask.csv")) { throw "QuestV2CliTask.csv missing - needed to tell a real world quest from a mistyped one" }
Get-Content "$ToolsDir\QuestV2CliTask.csv" | Select-Object -Skip 1 | ForEach-Object { $taskQuests[$_.Split(",")[0]] = $true }

$entryPattern = '(?m)^(\[(\d+)\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",-?\d+,)128,'
$retype = @{}
foreach ($m in [regex]::Matches($content, $entryPattern)) {
    $questId = $m.Groups[2].Value
    if ($taskQuests.ContainsKey($questId)) { continue }
    $cached = "$ToolsDir\quest_api_cache\$questId.json"
    if (-not (Test-Path $cached)) { continue }
    $json = [System.IO.File]::ReadAllText($cached)
    if ($json -match '"is_weekly":true') { continue }
    if ($json -match '"is_daily":true') { $retype[$questId] = 4 }
    elseif ($json -match '"is_repeatable":true') { $retype[$questId] = 2 }
}

$retyped = 0
$content = [regex]::Replace($content, $entryPattern, {
    param($m)
    if ($retype.ContainsKey($m.Groups[2].Value)) { $script:retyped++; return $m.Groups[1].Value + $retype[$m.Groups[2].Value] + "," }
    return $m.Value
})
if ($retyped -ne $retype.Count) { throw "Expected to retype $($retype.Count) quests, retyped $retyped" }

[System.IO.File]::WriteAllText($questFile, $content, (New-Object System.Text.UTF8Encoding $false))
"Quests retyped: $retyped"
$retype.GetEnumerator() | Group-Object Value | ForEach-Object { "  to type $($_.Name): $($_.Count)" }
