<#
Gives a real category to quests stored with none - category 0, which is where
Insert-GapQuestEntries.ps1 puts what it can't place, or an id no qcQuestCategories row defines.
No menu entry reaches those quests, so they can only be found by searching.

The category comes from, in order:
  1. The quest's area in Blizzard's quest API (tools/quest_api_cache), matched to a category of
     the same name. This is the database's own convention: of categorised quests with both
     signals, 96% are filed under their API area and 90% under their pin's map. Where several
     categories share the name (the old and the Midnight Eversong Woods), the one the quest's map
     pin sits in is taken; with no pin to choose, the quest is left alone.
  2. An API area with no category of its own is looked up as a map (UiMap.csv, from
     Build-CategoryUiMapIDs.ps1) and filed under the first map above it that has a category
     (Vaults of Atal'Utek -> The Coiled Isle).
  3. Otherwise the category of the map the quest's pin is on (qcPinDB -> qcAreaIDToCategoryID),
     when its pins all point to one category.
  4. Last, our own zone text, when it names exactly one category (three Nazmir quests sat under
     a mistyped category id).
Anything else stays where it is: hidden tracking entries with no zone at all, and the odd area
with neither a category nor a map.

Only field 5 changes. All-or-nothing: if any chosen quest isn't found exactly once, nothing is
written.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [switch]$WhatIf
)

$questFile = "$AddonDir\qcQuest.lua"
$content = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)

function Get-NameKey($s) { return ($s -replace "[^A-Za-z0-9]", "").ToLower() }

$categoryName = @{}
$categoriesByName = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcQuestCategories=\{(.*?)^\}').Groups[1].Value, '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) {
    $id = $m.Groups[1].Value
    if (-not $categoryName.ContainsKey($id)) { $categoryName[$id] = $m.Groups[2].Value }
    $key = Get-NameKey $m.Groups[2].Value
    if (-not $categoriesByName.ContainsKey($key)) { $categoriesByName[$key] = New-Object System.Collections.Generic.HashSet[string] }
    [void]$categoriesByName[$key].Add($id)
}

$categoryOfMap = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcAreaIDToCategoryID=\{(.*?)^\}').Groups[1].Value, '\[(\d+)\]=(-?\d+)')) {
    $categoryOfMap[$m.Groups[1].Value] = $m.Groups[2].Value
}

# Categories each quest's pins sit in, via the pin's map.
$pinCategories = @{}
$currentMap = $null
foreach ($line in [System.IO.File]::ReadAllLines("$AddonDir\qcPinDB.lua")) {
    $header = [regex]::Match($line, '^\t\[(\d+)\] = \{')
    if ($header.Success) { $currentMap = $header.Groups[1].Value; continue }
    $pin = [regex]::Match($line, '\{([\d,]*)\}\},?\s*$')
    if (-not $pin.Success -or -not $currentMap -or -not $categoryOfMap.ContainsKey($currentMap)) { continue }
    foreach ($questId in ($pin.Groups[1].Value -split ',' | Where-Object { $_ })) {
        if (-not $pinCategories.ContainsKey($questId)) { $pinCategories[$questId] = New-Object System.Collections.Generic.HashSet[string] }
        [void]$pinCategories[$questId].Add($categoryOfMap[$currentMap])
    }
}

$mapsByName = @{}
$parentOf = @{}
if (Test-Path "$ToolsDir\UiMap.csv") {
    foreach ($row in Import-Csv "$ToolsDir\UiMap.csv") {
        if (-not $mapsByName.ContainsKey($row.Name_lang)) { $mapsByName[$row.Name_lang] = New-Object System.Collections.Generic.List[string] }
        $mapsByName[$row.Name_lang].Add($row.ID)
        $parentOf[$row.ID] = $row.ParentUiMapID
    }
}

# The category of the nearest map at or above any map with this name, if they all agree.
function Get-ContainingCategory($areaName) {
    if (-not $mapsByName.ContainsKey($areaName)) { return $null }
    $found = New-Object System.Collections.Generic.HashSet[string]
    foreach ($mapId in $mapsByName[$areaName]) {
        $cursor = $mapId
        for ($depth = 0; $cursor -and $depth -lt 8; $depth++) {
            if ($categoryOfMap.ContainsKey($cursor)) { [void]$found.Add($categoryOfMap[$cursor]); break }
            $cursor = $parentOf[$cursor]
        }
    }
    if ($found.Count -eq 1) { return @($found)[0] }
    return $null
}

$entryPattern = '(?m)^(\[(\d+)\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"((?:[^"\\]|\\.)*)",)(-?\d+),'
$place = @{}
$rules = @{}
foreach ($m in [regex]::Matches($content, $entryPattern)) {
    $questId = $m.Groups[2].Value
    $zoneText = $m.Groups[3].Value
    $current = $m.Groups[4].Value
    if ($current -ne "0" -and $categoryName.ContainsKey($current)) { continue }

    # Wrapped outside the if: an if that yields one item unwraps it to a bare string, and [0] then
    # picks its first character (category 67 became 6).
    $pins = @(if ($pinCategories.ContainsKey($questId)) { $pinCategories[$questId] })
    $target = $null; $rule = $null
    $cached = "$ToolsDir\quest_api_cache\$questId.json"
    $candidates = $null
    $areaName = $null
    if (Test-Path $cached) {
        $area = [regex]::Match([System.IO.File]::ReadAllText($cached), '"area":\{.*?"name":"([^"]+)"')
        if ($area.Success) { $areaName = $area.Groups[1].Value; $candidates = $categoriesByName[(Get-NameKey $areaName)] }
    }
    $containing = if ($areaName -and -not $candidates) { Get-ContainingCategory $areaName }
    $zoneMatches = if ($zoneText) { $categoriesByName[(Get-NameKey $zoneText)] }
    if ($candidates) {
        if ($candidates.Count -eq 1) { $target = @($candidates)[0]; $rule = "API area" }
        else {
            $picked = @($pins | Where-Object { $candidates.Contains($_) })
            if ($picked.Count -eq 1) { $target = $picked[0]; $rule = "API area, pin picks between same-named categories" }
        }
    } elseif ($containing) {
        $target = $containing; $rule = "zone containing the API area"
    } elseif ($pins.Count -eq 1) {
        $target = $pins[0]; $rule = "pin's map"
    } elseif ($zoneMatches -and $zoneMatches.Count -eq 1) {
        $target = @($zoneMatches)[0]; $rule = "our zone text"
    }
    if ($target) {
        $place[$questId] = $target
        $rules[$rule] = 1 + $rules[$rule]
    }
}

$placed = 0
$content = [regex]::Replace($content, $entryPattern, {
    param($m)
    if ($place.ContainsKey($m.Groups[2].Value)) { $script:placed++; return $m.Groups[1].Value + $place[$m.Groups[2].Value] + "," }
    return $m.Value
})
if ($placed -ne $place.Count) { throw "Expected to place $($place.Count) quests, placed $placed" }

if (-not $WhatIf) { [System.IO.File]::WriteAllText($questFile, $content, (New-Object System.Text.UTF8Encoding $false)) }
"$(if ($WhatIf) { 'Would place' } else { 'Placed' }) $placed quests in a category"
$rules.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "  by {0}: {1}" -f $_.Key, $_.Value }
