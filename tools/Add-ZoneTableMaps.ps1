<#
Adds the game maps missing from qcAreaIDToCategoryID, the table that turns a map the player (or a
quest's pin) is on into a quest category. The addon switches the quest list when you enter a zone
through it, and Place-UncategorisedQuests.ps1 files quests by it. Nothing regenerates the table, so
maps added to the game, and categories added by hand, drift out of it: in October 2026 the 31
dungeon and raid categories 1702-1734 and Midnight's second Isle of Quel'Danas map were missing.

A map not in the table is added when, in order:
  1. qcCategoryUiMapID names a category by it.
  2. It has the same name and parent map as a map already in the table, and all of those point to
     one category (a dungeon's other floors; Isle of Quel'Danas 2424 beside 2432).
  3. Its name is exactly that of one category that has no map in the table yet; every floor of a
     new dungeon has the dungeon's name. This follows the table's convention: Karazhan lists all 17
     of its floors.
Never added: continent-level and larger maps (UiMap types 0-2); a map pointing at a category that
isn't defined; and a map that another category's name comes from (qcCategoryUiMapID or a
{"map",N} in qcCategoryClientName), or whose twin with the same name and parent is one - Acherus
647 and 648 are the Legion class hall, not category 429.

Entries already in the table are never changed. Safe to rerun: it only finds new cases.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [switch]$WhatIf
)
$ErrorActionPreference = "Stop"

$questFile = "$AddonDir\qcQuest.lua"
$content = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)

$tableMatch = [regex]::Match($content, '(?sm)^qcAreaIDToCategoryID=\{\r\n(.*?)^\}')
if (-not $tableMatch.Success) { throw "qcAreaIDToCategoryID not found" }
$categoryOfMap = @{}
foreach ($m in [regex]::Matches($tableMatch.Groups[1].Value, '\[(\d+)\]=(-?\d+)')) { $categoryOfMap[$m.Groups[1].Value] = $m.Groups[2].Value }

$categoryName = @{}
$categoriesByName = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcQuestCategories=\{(.*?)^\}').Groups[1].Value, '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) {
    $categoryName[$m.Groups[1].Value] = $m.Groups[2].Value
    if (-not $categoriesByName.ContainsKey($m.Groups[2].Value)) { $categoriesByName[$m.Groups[2].Value] = New-Object System.Collections.Generic.List[string] }
    if (-not $categoriesByName[$m.Groups[2].Value].Contains($m.Groups[1].Value)) { $categoriesByName[$m.Groups[2].Value].Add($m.Groups[1].Value) }
}

$namingMap = @{}
$namedBy = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcCategoryUiMapID\s*=\s*\{(.*?)^\}').Groups[1].Value, '\[(\d+)\]=(\d+)')) {
    $namingMap[$m.Groups[1].Value] = $m.Groups[2].Value
    $namedBy[$m.Groups[2].Value] = $m.Groups[1].Value
}
foreach ($line in [regex]::Match($content, '(?sm)^qcCategoryClientName\s*=\s*\{(.*?)^\}').Groups[1].Value -split "`r`n") {
    $entry = [regex]::Match($line, '^\s*\[(\d+)\]=')
    if (-not $entry.Success) { continue }
    foreach ($m in [regex]::Matches($line, '\{"map",(\d+)\}')) { $namedBy[$m.Groups[1].Value] = $entry.Groups[1].Value }
}

$maps = @{}
foreach ($row in Import-Csv "$ToolsDir\UiMap.csv") { $maps[$row.ID] = $row }

$add = [ordered]@{}
$rule = @{}
$twins = @{}
foreach ($row in $maps.Values) {
    $key = "$($row.Name_lang)|$($row.ParentUiMapID)"
    if (-not $twins.ContainsKey($key)) { $twins[$key] = New-Object System.Collections.Generic.List[string] }
    $twins[$key].Add($row.ID)
}
function Test-Addable($mapId, $category) {
    if ($categoryOfMap.ContainsKey($mapId) -or $add.Contains($mapId)) { return $false }
    if (-not $categoryName.ContainsKey($category)) { return $false }
    if (-not $maps.ContainsKey($mapId) -or [int]$maps[$mapId].Type -le 2) { return $false }
    foreach ($twin in $twins["$($maps[$mapId].Name_lang)|$($maps[$mapId].ParentUiMapID)"]) {
        if ($namedBy.ContainsKey($twin) -and $namedBy[$twin] -ne $category) { return $false }
    }
    return $true
}

foreach ($category in $namingMap.Keys) {
    $mapId = $namingMap[$category]
    if (Test-Addable $mapId $category) { $add[$mapId] = $category; $rule[$mapId] = "names the category" }
}

$siblings = @{}
foreach ($mapId in $categoryOfMap.Keys) {
    if (-not $maps.ContainsKey($mapId)) { continue }
    $key = "$($maps[$mapId].Name_lang)|$($maps[$mapId].ParentUiMapID)"
    if (-not $siblings.ContainsKey($key)) { $siblings[$key] = New-Object System.Collections.Generic.HashSet[string] }
    [void]$siblings[$key].Add($categoryOfMap[$mapId])
}
foreach ($row in $maps.Values) {
    $key = "$($row.Name_lang)|$($row.ParentUiMapID)"
    if (-not $siblings.ContainsKey($key) -or $siblings[$key].Count -ne 1) { continue }
    $category = @($siblings[$key])[0]
    if (Test-Addable $row.ID $category) { $add[$row.ID] = $category; $rule[$row.ID] = "same name and parent as a listed map" }
}

$mapped = New-Object System.Collections.Generic.HashSet[string]
foreach ($category in $categoryOfMap.Values) { [void]$mapped.Add($category) }
foreach ($row in $maps.Values) {
    if (-not $categoriesByName.ContainsKey($row.Name_lang)) { continue }
    $unmapped = @($categoriesByName[$row.Name_lang] | Where-Object { -not $mapped.Contains($_) })
    if ($unmapped.Count -ne 1) { continue }
    if (Test-Addable $row.ID $unmapped[0]) { $add[$row.ID] = $unmapped[0]; $rule[$row.ID] = "name of a category with no map" }
}

$byCategory = $add.Keys | Group-Object { $add[$_] } | Sort-Object { [int]$_.Name }
$lines = foreach ($group in $byCategory) {
    (($group.Group | Sort-Object { [int]$_ } | ForEach-Object { "[$_]=$($group.Name)," }) -join "") + "`t-- $($categoryName[$group.Name])"
}
if ($add.Count -and -not $WhatIf) {
    $insertAt = $tableMatch.Groups[1].Index + $tableMatch.Groups[1].Length
    $content = $content.Substring(0, $insertAt) + (($lines -join "`r`n") + "`r`n") + $content.Substring($insertAt)
    [System.IO.File]::WriteAllText($questFile, $content, (New-Object System.Text.UTF8Encoding $false))
}
"$(if ($WhatIf) { 'Would add' } else { 'Added' }) $($add.Count) maps to qcAreaIDToCategoryID, for $(@($byCategory).Count) categories"
$rule.Values | Group-Object | Sort-Object Count -Descending | ForEach-Object { "  by {0}: {1}" -f $_.Name, $_.Count }
foreach ($group in $byCategory) {
    "  {0} {1}: {2}" -f $group.Name, $categoryName[$group.Name], (($group.Group | Sort-Object { [int]$_ } | ForEach-Object { "$_ $($maps[$_].Name_lang)" }) -join ", ")
}
