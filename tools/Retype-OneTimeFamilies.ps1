<#
Retypes to 1 (normal) quests typed daily (4) or 128 that are one-time.

Starting point: 478 quests typed 4 or 128 that the /qc typecheck probe (PR #42) found the game
client calls Normal once their data is loaded - so not daily or weekly. Normal also covers quests
that recur on other schedules (paragon caches, emissary bounties, Special Assignments, PvP
rewards), so the 478 were sorted into families by name and zone, and only the families that are
one-time by their nature are retyped here. That sorting is judgment, not data; the families left
alone (recurring or unsure) are for a later pass.

All-or-nothing: if any quest isn't found exactly once as type 4 or 128, nothing is written.
#>
param(
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist"
)

$families = [ordered]@{
    "Legion profession questlines" = @(38798,40149,38795,38796,40144,40134,40136,40151,40132,40137,38777,38797,38785,38801,40147,40855,38793,38791,38789,38792,38790,38794,38800,40152,40133,40146,40131,40141,40135,38888,40145,40143)
    "Reputation and renown milestones" = @(85808,85810,88881,85806,88872,85807,88878,85809,88875,88879,88870,88876,88873,83739,83740,83738,89515,79199,79196,89032,93566,79220,92411,85805,79219,66156,76425,92412,85471,79218,89035,66511,85109,75290,92410,65606,92413,93811,84485,71023,88880,88871,88877,88874)
    "Pet battle introduction" = @(31878,31879,31880,31881,31569,31570,31575,31578,31581,31556,31573,31576,31579,31823,31824,31825,31831,31568,31574,31577,31580)
    "Named dungeon and raid story quests" = @(86458,75694,76402,70170,70881,67081,65259,66458,66586,71093,86543,91411,93575,72261,90822,86521,86728,60501,70168,63903,64607,63986,50551,93651,58798,62371,82739,66847,91694,93850)
    "Legion zone story quests" = @(39851,41884,41882,39850,45727)
}

$retype = @{}
foreach ($family in $families.Keys) {
    foreach ($questId in $families[$family]) {
        if ($retype.ContainsKey("$questId")) { throw "Quest $questId is listed twice" }
        $retype["$questId"] = $family
    }
}

$questFile = "$AddonDir\qcQuest.lua"
$content = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)
$entryPattern = '(?m)^(\[(\d+)\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",-?\d+,)(4|128),'
$done = @{}
$content = [regex]::Replace($content, $entryPattern, {
    param($m)
    if ($retype.ContainsKey($m.Groups[2].Value)) { $script:done[$m.Groups[2].Value] = $m.Groups[3].Value; return $m.Groups[1].Value + "1," }
    return $m.Value
})
$missing = @($retype.Keys | Where-Object { -not $done.ContainsKey($_) })
if ($missing.Count) { throw "Not found as type 4 or 128: $($missing -join ', ')" }

[System.IO.File]::WriteAllText($questFile, $content, (New-Object System.Text.UTF8Encoding $false))
"Quests retyped to 1: $($done.Count)"
foreach ($family in $families.Keys) { "  {0}: {1}" -f $family, $families[$family].Count }
$done.Values | Group-Object | ForEach-Object { "  were type $($_.Name): $($_.Count)" }
