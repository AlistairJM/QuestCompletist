<#
Gives a real category to quests stored with none - category 0, which is where
Insert-GapQuestEntries.ps1 puts what it can't place, or an id no qcQuestCategories row defines.
No menu entry reaches those quests, so they can only be found by searching.

The category comes from, in order:
  0. A quest named "<category>: ..." ("Prey: Anguish Island", "Tol Dagor: The Fourth Key") goes to
     that category.
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
  4. Our own zone text, when it names exactly one category (three Nazmir quests sat under a
     mistyped category id).
  5. The zone above the pin's map, when the pin's own map has no category: the nearest map above
     it that has one, or whose name is exactly one category's, short of a continent (Naigtal ->
     Voidstorm). Below zone text, because a garrison or covenant sanctum map would otherwise climb
     to the zone outside it.
  6. Last, the quest's storyline, when every filed quest in it is in one category and at least half
     of it is filed.
Anything else stays in, or moves to, category 0, which the menu lists as Uncategorized: hidden
tracking entries with no zone at all, and the odd area with neither a category nor a map.

Checked by un-filing 2,000 random filed quests on a scratch copy: these rules put 1,706 back where
they were, 251 elsewhere (mostly pins of class, campaign and profession quests) and left 43, against
1,693 / 255 / 52 before rules 0 (outside -Refile), 5 and 6 were added.

-Explain writes tools/uncategorised_quests.csv: every quest placed, with the rule, and every quest
left, with what's missing - no API area, pins in several categories, or pins on maps with no
category (the summary lists those maps, which usually means qcAreaIDToCategoryID lacks them).

-Refile takes catch-all categories whose quests should be filed properly too (1050 "Legion
Uncategorized"; 1150 "Bfa Unknown" until what was left of it was merged into category 0). For those
quests, and for category 0, between rules 2 and 3, a hand-written list maps the catch-all's own zone
text to a category ("Death Knight Campaign" -> the Death Knight class hall), below in $zoneTextRules.
A quest is never filed in a category no menu entry reaches, nor back into the catch-all.

Only field 5 changes. All-or-nothing: if any chosen quest isn't found exactly once, nothing is
written.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [string[]]$Refile = @(),
    [switch]$WhatIf,
    [switch]$Explain
)

$Refile = @($Refile | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

$zoneTextRules = @{
    "1050" = @{
        "Death Knight Campaign" = "1021"; "Demon Hunter Campaign" = "1010"; "Mardum, the Shattered Abyss" = "1010"
        "Warlock Campaign" = "1017"; "Shaman Campaign" = "1014"; "Druid Campaign" = "1013"; "Monk Campaign" = "1015"
        "Mage Campaign" = "1009"; "Legionfall Campaign" = "1002"; "Dalaran" = "1003"
    }
    "0" = @{
        "Time Rifts" = "1347"; "Zskera Vaults" = "1304"; "Vision of Orgrimmar" = "1133"; "Primalist Storms" = "1322"
        "Death Knight Campaign" = "1021"; "Prey" = "1514"
    }
}

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

$inMenu = New-Object System.Collections.Generic.HashSet[string]
foreach ($line in [System.IO.File]::ReadAllLines("$AddonDir\qcMenu.lua")) {
    if ($line -match '^\s*--') { continue }
    foreach ($m in [regex]::Matches($line, 'arg1=(\d+),')) { [void]$inMenu.Add($m.Groups[1].Value) }
}

$categoryOfMap = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcAreaIDToCategoryID=\{(.*?)^\}').Groups[1].Value, '\[(\d+)\]=(-?\d+)')) {
    $categoryOfMap[$m.Groups[1].Value] = $m.Groups[2].Value
}

$mapsByName = @{}
$parentOf = @{}
$mapName = @{}
$mapType = @{}
if (Test-Path "$ToolsDir\UiMap.csv") {
    foreach ($row in Import-Csv "$ToolsDir\UiMap.csv") {
        if (-not $mapsByName.ContainsKey($row.Name_lang)) { $mapsByName[$row.Name_lang] = New-Object System.Collections.Generic.List[string] }
        $mapsByName[$row.Name_lang].Add($row.ID)
        $parentOf[$row.ID] = $row.ParentUiMapID
        $mapName[$row.ID] = $row.Name_lang
        $mapType[$row.ID] = $row.Type
    }
}

# The category of this map, or of the nearest map above it, stopping below continent level
# (UiMap types 0-2) so a pin never files a quest under a whole continent. A map with no entry in
# qcAreaIDToCategoryID but the name of exactly one category is taken as that category (Vault of the
# Wardens), so the climb doesn't overshoot it to the zone outside.
function Get-MapCategory($mapId) {
    $cursor = $mapId
    for ($depth = 0; $cursor -and $cursor -ne "0" -and $depth -lt 8; $depth++) {
        if ($categoryOfMap.ContainsKey($cursor)) { return $categoryOfMap[$cursor] }
        $named = if ($mapName[$cursor]) { $categoriesByName[(Get-NameKey $mapName[$cursor])] }
        if ($named -and $named.Count -eq 1) { return @($named)[0] }
        if ($mapType.ContainsKey($cursor) -and [int]$mapType[$cursor] -le 2) { return $null }
        $cursor = $parentOf[$cursor]
    }
    return $null
}

# Categories each quest's pins sit in: by the pin's own map, or failing that by the map named like
# a category or the zone above it ("climbed"), which ranks below our zone text.
$pinCategories = @{}
$climbedPinCategories = @{}
$pinMaps = @{}
$currentMap = $null
foreach ($line in [System.IO.File]::ReadAllLines("$AddonDir\qcPinDB.lua")) {
    $header = [regex]::Match($line, '^\t\[(\d+)\] = \{')
    if ($header.Success) { $currentMap = $header.Groups[1].Value; continue }
    $pin = [regex]::Match($line, '\{([\d,]*)\}\},?\s*$')
    if (-not $pin.Success -or -not $currentMap) { continue }
    $direct = $categoryOfMap.ContainsKey($currentMap)
    $mapCategory = Get-MapCategory $currentMap
    $into = if ($direct) { $pinCategories } else { $climbedPinCategories }
    foreach ($questId in ($pin.Groups[1].Value -split ',' | Where-Object { $_ })) {
        if (-not $pinMaps.ContainsKey($questId)) { $pinMaps[$questId] = New-Object System.Collections.Generic.HashSet[string] }
        [void]$pinMaps[$questId].Add($currentMap)
        if (-not $mapCategory) { continue }
        if (-not $into.ContainsKey($questId)) { $into[$questId] = New-Object System.Collections.Generic.HashSet[string] }
        [void]$into[$questId].Add($mapCategory)
    }
}

# Categories of the quest's own map points in the client (QuestPOIBlob.csv): its quest giver and
# its objective areas. Only the giver points become pins, so this also reaches quests whose only
# location is where their objectives are.
$pointCategories = @{}
if (Test-Path "$ToolsDir\QuestPOIBlob.csv") {
    $categoryOfUiMap = @{}
    foreach ($row in Import-Csv "$ToolsDir\QuestPOIBlob.csv") {
        if (-not $categoryOfUiMap.ContainsKey($row.UiMapID)) { $categoryOfUiMap[$row.UiMapID] = Get-MapCategory $row.UiMapID }
        $category = $categoryOfUiMap[$row.UiMapID]
        if (-not $category) { continue }
        if (-not $pointCategories.ContainsKey($row.QuestID)) { $pointCategories[$row.QuestID] = New-Object System.Collections.Generic.HashSet[string] }
        [void]$pointCategories[$row.QuestID].Add($category)
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

$storyOf = @{}
$storyQuests = @{}
$filedIn = @{}
foreach ($m in [regex]::Matches($content, '(?m)^\[(\d+)\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",(-?\d+),(?:[^,]*,){7}(\d+),')) {
    $filedIn[$m.Groups[1].Value] = $m.Groups[2].Value
    $story = $m.Groups[3].Value
    if ($story -eq "0") { continue }
    $storyOf[$m.Groups[1].Value] = $story
    if (-not $storyQuests.ContainsKey($story)) { $storyQuests[$story] = New-Object System.Collections.Generic.List[string] }
    $storyQuests[$story].Add($m.Groups[1].Value)
}
$catchAlls = @("1050", "1150")

$entryPattern = '(?m)^(\[(\d+)\]=\{\d+,"(?<name>(?:[^"\\]|\\.)*)",[^,]*,"((?:[^"\\]|\\.)*)",)(-?\d+),'
$place = @{}
$rules = @{}
$pending = New-Object System.Collections.Generic.List[object]
$ruleOf = @{}
foreach ($m in [regex]::Matches($content, $entryPattern)) {
    $questId = $m.Groups[2].Value
    $zoneText = $m.Groups[3].Value
    $current = $m.Groups[4].Value
    $refiling = $Refile -contains $current
    if (-not $refiling -and $current -ne "0" -and $categoryName.ContainsKey($current)) { continue }
    $usable = { param($c) $inMenu.Contains($c) -and $c -ne $current }

    # Wrapped outside the if: an if that yields one item unwraps it to a bare string, and [0] then
    # picks its first character (category 67 became 6).
    $pins = @(if ($pinCategories.ContainsKey($questId)) { $pinCategories[$questId] })
    $pins = @($pins | Where-Object { & $usable $_ })
    $climbedPins = @(if ($climbedPinCategories.ContainsKey($questId)) { $climbedPinCategories[$questId] })
    $climbedPins = @($climbedPins | Where-Object { & $usable $_ })
    $points = @(if ($pointCategories.ContainsKey($questId)) { $pointCategories[$questId] })
    $points = @($points | Where-Object { & $usable $_ })
    $target = $null; $rule = $null
    $cached = "$ToolsDir\quest_api_cache\$questId.json"
    $candidates = $null
    $areaName = $null
    if (Test-Path $cached) {
        $area = [regex]::Match([System.IO.File]::ReadAllText($cached), '"area":\{.*?"name":"([^"]+)"')
        if ($area.Success) { $areaName = $area.Groups[1].Value; $candidates = $categoriesByName[(Get-NameKey $areaName)] }
    }
    $containing = if ($areaName -and -not $candidates) { Get-ContainingCategory $areaName }
    $zoneMatches = @(if ($zoneText -and $categoriesByName.ContainsKey((Get-NameKey $zoneText))) { $categoriesByName[(Get-NameKey $zoneText)] })
    $zoneMatches = @($zoneMatches | Where-Object { & $usable $_ })
    $ambiguous = $false

    $prefix = [regex]::Match($m.Groups["name"].Value, '^(.+?):\s')
    if ($prefix.Success) {
        $named = @(if ($categoriesByName.ContainsKey((Get-NameKey $prefix.Groups[1].Value))) { $categoriesByName[(Get-NameKey $prefix.Groups[1].Value)] })
        $named = @($named | Where-Object { & $usable $_ })
        if ($named.Count -eq 1) { $target = $named[0]; $rule = "quest named after the category" }
    }
    if (-not $target) {
        if ($candidates) {
            $usableCandidates = @($candidates | Where-Object { & $usable $_ })
            if ($usableCandidates.Count -eq 1) { $target = $usableCandidates[0]; $rule = "API area" }
            elseif ($usableCandidates.Count -gt 1) {
                $picked = @($pins | Where-Object { $usableCandidates -contains $_ })
                if ($picked.Count -eq 1) { $target = $picked[0]; $rule = "API area, pin picks between same-named categories" }
                else { $ambiguous = $true }
            }
        } elseif ($containing -and (& $usable $containing)) {
            $target = $containing; $rule = "zone containing the API area"
        }
    }
    if (-not $target -and ($refiling -or $current -eq "0") -and $zoneTextRules.ContainsKey($current) -and $zoneTextRules[$current].ContainsKey($zoneText)) {
        $handTarget = $zoneTextRules[$current][$zoneText]
        if (-not (& $usable $handTarget)) { throw "Zone text rule '$zoneText' points at category $handTarget, which no menu entry reaches" }
        $target = $handTarget; $rule = "catch-all zone text, by hand"
    }
    if (-not $target -and -not $ambiguous) {
        if ($pins.Count -eq 1) { $target = $pins[0]; $rule = "pin's map" }
        elseif ($zoneMatches.Count -eq 1) { $target = $zoneMatches[0]; $rule = "our zone text" }
        elseif ($pins.Count -eq 0 -and $climbedPins.Count -eq 1) { $target = $climbedPins[0]; $rule = "zone above the pin's map" }
        elseif ($points.Count -eq 1) { $target = $points[0]; $rule = "client map points" }
    }
    if ($target) {
        $place[$questId] = $target
        $rules[$rule] = 1 + $rules[$rule]; $ruleOf[$questId] = $rule
    } else {
        $apiStatus = if ($ambiguous) { "area '$areaName' matches several categories, no pin to choose" }
            elseif (Test-Path "$ToolsDir\quest_api_cache\$questId.404") { "not in the API" }
            elseif (-not (Test-Path $cached)) { "not fetched" }
            elseif ($areaName) { "area '$areaName' matches no category or map" }
            else { "no area" }
        $pending.Add([PSCustomObject]@{ QuestID = $questId; Name = $m.Groups["name"].Value; ZoneText = $zoneText; Current = $current; Api = $apiStatus })
    }
}

# A quest nothing else placed joins its storyline, when every filed quest in the storyline is in
# the same category and at least half the storyline is filed. Catch-alls and quests placed by this
# rule don't count as filed. The half keeps a storyline that replays old zones (Lorewalking, three
# quests in Korthia and five unfiled) from pulling the rest into one of them.
$placedByRules = $place.Clone()
foreach ($quest in $pending) {
    $story = $storyOf[$quest.QuestID]
    if (-not $story) { continue }
    $siblingCategories = New-Object System.Collections.Generic.HashSet[string]
    $filed = 0
    foreach ($sibling in $storyQuests[$story]) {
        $category = if ($placedByRules.ContainsKey($sibling)) { $placedByRules[$sibling] } else { $filedIn[$sibling] }
        if ($category -eq "0" -or -not $categoryName.ContainsKey($category) -or $catchAlls -contains $category -or $Refile -contains $category) { continue }
        [void]$siblingCategories.Add($category)
        $filed++
    }
    if ($siblingCategories.Count -ne 1 -or $filed * 2 -lt $storyQuests[$story].Count) { continue }
    $category = @($siblingCategories)[0]
    if (-not $inMenu.Contains($category) -or $category -eq $quest.Current) { continue }
    $place[$quest.QuestID] = $category
    $rules["storyline"] = 1 + $rules["storyline"]; $ruleOf[$quest.QuestID] = "storyline $story"
}

$left = New-Object System.Collections.Generic.List[object]
foreach ($quest in $pending) {
    if ($place.ContainsKey($quest.QuestID)) { continue }
    if (-not $categoryName.ContainsKey($quest.Current)) {
        $place[$quest.QuestID] = "0"
        $rules["undefined category, to Uncategorized"] = 1 + $rules["undefined category, to Uncategorized"]
    }
    $maps = @(if ($pinMaps.ContainsKey($quest.QuestID)) { $pinMaps[$quest.QuestID] })
    $left.Add([PSCustomObject]@{
        QuestID = $quest.QuestID
        Name = $quest.Name
        ZoneText = $quest.ZoneText
        Api = $quest.Api
        Pins = if ($maps.Count) { ($maps | ForEach-Object { $c = Get-MapCategory $_; "$_ $($mapName[$_]) -> $(if ($c) { "$c $($categoryName[$c])" } else { 'no category' })" }) -join "; " } else { "none" }
        Storyline = if ($storyOf[$quest.QuestID]) { $storyOf[$quest.QuestID] } else { "none" }
    })
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
"Left without a category: $($left.Count)"
if ($Explain) {
    $nameOf = @{}
    foreach ($m in [regex]::Matches($content, '(?m)^\[(\d+)\]=\{\d+,"((?:[^"\\]|\\.)*)"')) { $nameOf[$m.Groups[1].Value] = $m.Groups[2].Value }
    $report = @($ruleOf.Keys | Sort-Object { [int]$_ } | ForEach-Object {
        [PSCustomObject]@{ QuestID = $_; Name = $nameOf[$_]; PlacedIn = "$($place[$_]) $($categoryName[$place[$_]])"; Rule = $ruleOf[$_]; ZoneText = ""; Api = ""; Pins = ""; Storyline = "" }
    })
    $report += @($left | ForEach-Object { [PSCustomObject]@{ QuestID = $_.QuestID; Name = $_.Name; PlacedIn = ""; Rule = ""; ZoneText = $_.ZoneText; Api = $_.Api; Pins = $_.Pins; Storyline = $_.Storyline } })
    $report | Export-Csv "$ToolsDir\uncategorised_quests.csv" -NoTypeInformation -Encoding UTF8
    "  API: " + (($left | Group-Object { $_.Api -replace "'.*'(?= matches)", "..." } | Sort-Object Count -Descending | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ", ")
    $withPins = @($left | Where-Object { $_.Pins -ne 'none' })
    $uncategorisedMaps = @($withPins | ForEach-Object { $_.Pins -split '; ' } | Where-Object { $_ -like '*-> no category' } | ForEach-Object { $_ -replace ' -> no category$', '' } | Group-Object | Sort-Object Count -Descending)
    "  pins: $(@($withPins | Where-Object { $_.Pins -notlike '*no category*' }).Count) have pins in several categories, $(@($withPins | Where-Object { $_.Pins -like '*no category*' }).Count) have pins on maps with no category"
    if ($uncategorisedMaps.Count) { "    maps with no category: " + (($uncategorisedMaps | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ", ") }
    "  storyline: $(@($left | Where-Object { $_.Storyline -ne 'none' }).Count) are in a storyline with no single filed category"
    "  Written to $ToolsDir\uncategorised_quests.csv"
}
