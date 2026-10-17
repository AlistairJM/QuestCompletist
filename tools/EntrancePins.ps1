<#
Dot-sourced by Sync-EntrancePins.ps1 (step 6f, and WoW: Forever's step 10) and Audit-DungeonCategories.ps1 (step 8): which
of our categories is a dungeon or raid, where its entrances stand on a map, and the quests an entrance pin lists.

  - An instance category. Retail: a category named like a Dungeon Journal instance (Get-InstanceKey: case, punctuation
    and a leading "The" ignored), leaving out the world-boss pages (JournalInstance flag 2), the categories that group
    several instances ($InstanceHubCategories) and a zone named like an instance (its qcCategoryUiMapID a zone map, as
    Zul'Aman's is). Forever: its categories are AreaTable IDs, so a dungeon or raid map whose AreaTableID is a category.
  - Where the game's own map draws it. The probe's map pass asks the game for each map's dungeon entrances
    (C_EncounterJournal.GetDungeonEntrancesForMap), and an instance the game draws gets a pin at each of its places,
    whatever the tables below say (the user's choice of 17 October 2026): the game draws a door on every map it falls in
    (Wailing Caverns on the Durotar and Mulgore edges too), the Blackrock Mountain and Caverns of Time dungeons on their
    own maps, and its places are those of its icons, which the door table misses by up to 8.6 points (Uldaman). Retail
    matches the game's places by journal instance, Forever by name; Forever's client draws none so far.
  - Its doors, for an instance the game drew nowhere. Retail: the journal's JournalInstanceEntrance rows. Forever's
    client has no such table, so its door is the map's corpse point (Map.Corpse), where the game puts a ghost who died
    inside.
  - A world position to a zone map point (ConvertTo-ZonePoint): of the zone maps (UiMap type 3) whose UiMapAssignment
    region on that map holds the point, the one whose area is the entrance's area or an area above it (AreaTable
    ParentAreaID), else the only one. When no zone map holds it on its own map, the map it is a copy of is tried (Map
    ParentMapID, else CosmeticParentMapID: the N'Zoth assaults' Uldum and Vale of Eternal Blossoms, Tanaan Jungle's
    Draenor). Two or more with no area to choose between them hold the entrance back for a
    decision row (SHOW at a place, or HIDE). Only retail's entrances have an area of their own: retail's area for a
    Forever entrance is a hint in the report, as it is where retail's door stands (Blackfathom Deeps: Darkshore's
    Twilight Vale, where the old game's entrance is Ashenvale's).
#>

# Categories that group several instances, so they match no single journal instance: Ahn'Qiraj, Auchindoun, Caverns of
# Time, Coilfang Reservoir, Hellfire Citadel (TBC) and Tempest Keep.
$InstanceHubCategories = @(3, 14, 36, 39, 95, 205)

function Get-InstanceKey([string]$name) { return (($name -replace '^The\s+', '') -replace '[^A-Za-z0-9]', '').ToLower() }

# qcQuestCategories of a qcQuest.lua: category ID -> its English name (the first row of an ID wins).
function Read-QuestCategoryNames([string]$path) {
    $names = @{}
    $block = [regex]::Match([IO.File]::ReadAllText($path), '(?sm)^qcQuestCategories\s*=\s*\{(.*?)^\}').Groups[1].Value
    foreach ($m in [regex]::Matches($block, '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) {
        $id = [int]$m.Groups[1].Value
        if (-not $names.ContainsKey($id)) { $names[$id] = $m.Groups[2].Value }
    }
    return $names
}

# qcCategoryUiMapID of a qcQuest.lua: category ID -> UiMap ID.
function Read-CategoryUiMapIds([string]$path) {
    $maps = @{}
    $block = [regex]::Match([IO.File]::ReadAllText($path), '(?sm)^qcCategoryUiMapID\s*=\s*\{(\}|.*?^\})').Groups[1].Value
    foreach ($m in [regex]::Matches($block, '\[(-?\d+)\]\s*=\s*(\d+)')) { $maps[[int]$m.Groups[1].Value] = [int]$m.Groups[2].Value }
    return $maps
}

# What ConvertTo-ZonePoint reads, from a build's Map, UiMap, UiMapAssignment and AreaTable rows.
function New-ZoneLocator($mapRows, $uiMapRows, $assignmentRows, $areaRows) {
    $mapParent = @{}
    foreach ($m in $mapRows) {
        $parent = [int]$m.ParentMapID
        if ($parent -lt 0) { $parent = [int]$m.CosmeticParentMapID }
        if ($parent -ge 0) { $mapParent[[int]$m.ID] = $parent }
    }
    $uiMaps = @{}; foreach ($u in $uiMapRows) { $uiMaps[[int]$u.ID] = $u }
    $byMap = @{}
    foreach ($r in $assignmentRows) {
        $ui = $uiMaps[[int]$r.UiMapID]
        if (-not $ui -or [int]$ui.Type -ne 3) { continue }
        $map = [int]$r.MapID
        if (-not $byMap.ContainsKey($map)) { $byMap[$map] = New-Object System.Collections.Generic.List[object] }
        $byMap[$map].Add($r)
    }
    $parent = @{}; foreach ($a in $areaRows) { $parent[[int]$a.ID] = [int]$a.ParentAreaID }
    return [pscustomobject]@{ UiMaps = $uiMaps; ZonesByMap = $byMap; AreaParent = $parent; MapParent = $mapParent }
}

# An area and the areas above it, nearest first.
function Get-AreaChain($locator, [int]$area) {
    $chain = New-Object System.Collections.Generic.List[int]
    while ($area -and -not $chain.Contains($area)) {
        $chain.Add($area)
        $area = if ($locator.AreaParent.ContainsKey($area)) { $locator.AreaParent[$area] } else { 0 }
    }
    return , $chain.ToArray()
}

# A world position on a map as a point on a zone map: UiMap, X, Y (map points, 0 to 100, two decimals) and How ('area',
# the zone of the entrance's area; 'box', the only zone holding it), or UiMap 0 and How 'none' or 'several'. Zones lists
# every zone map holding the position, with its point, for the report and a decision row.
function ConvertTo-ZonePoint($locator, [int]$map, [double]$x, [double]$y, [int]$area) {
    $holding = New-Object System.Collections.Generic.List[object]
    $tried = @{}
    while ($holding.Count -eq 0 -and -not $tried.ContainsKey($map)) {
        $tried[$map] = $true
        $rows = if ($locator.ZonesByMap.ContainsKey($map)) { $locator.ZonesByMap[$map] } else { $null }
        foreach ($r in $rows) {
            if ($x -lt [double]$r.Region_0 -or $x -gt [double]$r.Region_3 -or $y -lt [double]$r.Region_1 -or $y -gt [double]$r.Region_4) { continue }
            $fx = ([double]$r.Region_4 - $y) / ([double]$r.Region_4 - [double]$r.Region_1)
            $fy = ([double]$r.Region_3 - $x) / ([double]$r.Region_3 - [double]$r.Region_0)
            $holding.Add([pscustomobject]@{
                UiMap = [int]$r.UiMapID; Area = [int]$r.AreaID; Name = $locator.UiMaps[[int]$r.UiMapID].Name_lang
                X = [math]::Round([decimal](([double]$r.UiMin_0 + $fx * ([double]$r.UiMax_0 - [double]$r.UiMin_0)) * 100), 2)
                Y = [math]::Round([decimal](([double]$r.UiMin_1 + $fy * ([double]$r.UiMax_1 - [double]$r.UiMin_1)) * 100), 2)
            })
        }
        if (-not $locator.MapParent.ContainsKey($map)) { break }
        $map = $locator.MapParent[$map]
    }
    $zones = @($holding | Sort-Object UiMap -Unique)
    $chosen = $null; $how = 'none'
    if ($area) {
        $chain = Get-AreaChain $locator $area
        foreach ($a in $chain) {
            $chosen = $zones | Where-Object { $_.Area -eq $a } | Select-Object -First 1
            if ($chosen) { $how = 'area'; break }
        }
    }
    if (-not $chosen) {
        if ($zones.Count -eq 1) { $chosen = $zones[0]; $how = 'box' }
        elseif ($zones.Count -gt 1) { $how = 'several' }
    }
    return [pscustomobject]@{
        UiMap = $(if ($chosen) { $chosen.UiMap } else { 0 }); X = $(if ($chosen) { $chosen.X } else { $null }); Y = $(if ($chosen) { $chosen.Y } else { $null })
        How = $how; Zones = $zones
    }
}

# Retail's instances: one per journal instance (not a world-boss page) whose map is a dungeon (Map.InstanceType 1) or a
# raid (2) and that one of our categories is named like, with its categories, the key of the game's places for it
# (GameKey: "j" and the journal instance) and its doors (Door: the JournalInstanceEntrance ID; Side: 1 the Alliance,
# 2 the Horde, 0 either).
function Get-RetailInstances($journalRows, $entranceRows, $mapRows, $categoryNames, $categoryUiMaps, $uiMapRows) {
    $instanceType = @{}; foreach ($m in $mapRows) { $instanceType[[int]$m.ID] = [int]$m.InstanceType }
    $uiType = @{}; foreach ($u in $uiMapRows) { $uiType[[int]$u.ID] = [int]$u.Type }
    $byKey = @{}
    foreach ($c in ($categoryNames.Keys | Sort-Object)) {
        if ($InstanceHubCategories -contains $c) { continue }
        if ($categoryUiMaps.ContainsKey($c) -and $uiType[$categoryUiMaps[$c]] -eq 3) { continue }
        $key = Get-InstanceKey $categoryNames[$c]
        if (-not $byKey.ContainsKey($key)) { $byKey[$key] = New-Object System.Collections.Generic.List[int] }
        $byKey[$key].Add($c)
    }
    $doors = @{}
    foreach ($e in $entranceRows) {
        $id = [int]$e.JournalInstanceID
        if (-not $doors.ContainsKey($id)) { $doors[$id] = New-Object System.Collections.Generic.List[object] }
        $side = switch ([int]$e.Faction) { 0 { 2 } 1 { 1 } default { 0 } }
        $doors[$id].Add([pscustomobject]@{ Door = [int]$e.ID; Map = [int]$e.MapID; X = [double]$e.Position_0; Y = [double]$e.Position_1; Area = [int]$e.AreaTableID; Hint = [int]$e.AreaTableID; Side = $side })
    }
    foreach ($j in ($journalRows | Sort-Object { [int]$_.ID })) {
        if ([int]$j.Flags -band 2) { continue }
        $kind = $instanceType[[int]$j.MapID]
        if ($kind -ne 1 -and $kind -ne 2) { continue }
        $key = Get-InstanceKey $j.Name_lang
        if (-not $byKey.ContainsKey($key)) { continue }
        [pscustomobject]@{
            Name = $j.Name_lang; Kind = $(if ($kind -eq 2) { 'raid' } else { 'dungeon' }); Categories = $byKey[$key].ToArray(); GameKey = "j$($j.ID)"
            Doors = @(if ($doors.ContainsKey([int]$j.ID)) { $doors[[int]$j.ID] })
        }
    }
}

# Forever's instances: one per dungeon or raid map whose AreaTableID is one of our categories, the key of the game's places
# for it (GameKey: "n" and its name's key), its door the map's corpse point (Door: the Map ID), with no area of its own;
# its Hint is retail's entrance area for the journal instance of the same name.
function Get-ForeverInstances($mapRows, $categoryNames, $retailJournalRows, $retailEntranceRows) {
    $journalKey = @{}; foreach ($j in $retailJournalRows) { $journalKey[[int]$j.ID] = Get-InstanceKey $j.Name_lang }
    $retailArea = @{}
    foreach ($e in ($retailEntranceRows | Sort-Object { [int]$_.ID })) {
        $key = $journalKey[[int]$e.JournalInstanceID]
        if ($key -and -not $retailArea.ContainsKey($key)) { $retailArea[$key] = [int]$e.AreaTableID }
    }
    foreach ($m in ($mapRows | Sort-Object { [int]$_.ID })) {
        $kind = [int]$m.InstanceType
        if ($kind -ne 1 -and $kind -ne 2) { continue }
        $category = [int]$m.AreaTableID
        if (-not $category -or -not $categoryNames.ContainsKey($category)) { continue }
        $doors = @()
        if ([int]$m.CorpseMapID -ge 0 -and ([double]$m.Corpse_0 -or [double]$m.Corpse_1)) {
            $key = Get-InstanceKey $m.MapName_lang
            $doors = @([pscustomobject]@{ Door = [int]$m.ID; Map = [int]$m.CorpseMapID; X = [double]$m.Corpse_0; Y = [double]$m.Corpse_1; Area = 0
                Hint = $(if ($retailArea.ContainsKey($key)) { $retailArea[$key] } else { 0 }); Side = 0 })
        }
        [pscustomobject]@{ Name = $m.MapName_lang; Kind = $(if ($kind -eq 2) { 'raid' } else { 'dungeon' }); Categories = @($category)
            GameKey = "n$(Get-InstanceKey $m.MapName_lang)"; Doors = $doors }
    }
}

# The decision rows of docs\plans\entrance-pin-decisions.csv for one game: "<instance>|<door>" -> the row. SHOW puts the
# entrance on UiMapID at X, Y; HIDE gives it no pin.
function Read-EntranceDecisions([string]$path, [string]$game) {
    $rows = @{}
    if (-not (Test-Path $path)) { return $rows }
    foreach ($row in (Import-Csv $path -Encoding UTF8)) {
        if ($row.Game -ne $game) { continue }
        $what = "entrance-pin-decisions.csv: $($row.Instance), door $($row.Door)"
        if ($row.Decision -eq 'SHOW') {
            if (-not ([int]$row.UiMapID -gt 0) -or "$($row.X)" -eq '' -or "$($row.Y)" -eq '') { throw "${what}: SHOW needs a UiMapID, X and Y" }
            $x = [decimal]::Parse($row.X, [Globalization.CultureInfo]::InvariantCulture); $y = [decimal]::Parse($row.Y, [Globalization.CultureInfo]::InvariantCulture)
            if ($x -lt 0 -or $x -gt 100 -or $y -lt 0 -or $y -gt 100) { throw "${what}: X and Y are map points, 0 to 100" }
        } elseif ($row.Decision -ne 'HIDE') { throw "${what}: decision '$($row.Decision)'; only SHOW and HIDE are known." }
        $key = "$($row.Instance)|$($row.Door)"
        if ($rows.ContainsKey($key)) { throw "${what}: listed twice" }
        $rows[$key] = $row
    }
    return $rows
}

# A quest's sides as the data has them: 1 the Alliance, 2 the Horde, 3 both.
function Get-QuestSides($quest) {
    $faction = [int]$quest.faction
    if ($faction -eq 1 -or $faction -eq 2) { return $faction }
    return 3
}

# The game's places of Get-ProbeEntrances' rows, by the instances' GameKey: "j" and the journal instance, and "n" and the
# key of the name the game gives it; a place the game gives twice counts once.
function Group-GameEntrances($rows) {
    $byKey = @{}
    $seen = @{}
    foreach ($r in $rows) {
        if ($seen.ContainsKey("$($r.Map)|$($r.Journal)|$($r.Name)|$($r.X)|$($r.Y)")) { continue }
        $seen["$($r.Map)|$($r.Journal)|$($r.Name)|$($r.X)|$($r.Y)"] = $true
        foreach ($key in @($(if ($r.Journal) { "j$($r.Journal)" }), "n$(Get-InstanceKey $r.Name)")) {
            if (-not $key -or $key -eq 'n') { continue }
            if (-not $byKey.ContainsKey($key)) { $byKey[$key] = New-Object System.Collections.Generic.List[object] }
            $byKey[$key].Add($r)
        }
    }
    return $byKey
}

# The entrance pins of -Instances, each listing the instance's quests no pin holds (-Pinned) and -Skip doesn't name; an
# instance with none gets no pin. An instance the game draws (-GameSpots, Group-GameEntrances' table) gets a pin at each
# of the game's places; any other one a pin per door, a side's door keeping the quests that side can take, unless every
# category of it is one a drawn instance has (two journal instances named alike, as Blackrock Depths the dungeon and the
# raid, or Magisters' Terrace and Midnight's: the drawn one places their quests). Pins lists
# the placed ones (map, x, y, kind, name, quests); Doors every place and door of an instance with quests, placed or not,
# with how it was placed (How: game, area, box, SHOW, HIDE, or none or several when it is held back for a decision row,
# Held for those three); Doorless the instances with such quests that the game draws nowhere and that have no door
# (Name, Quests).
function Get-EntrancePins($instances, $quests, $pinned, $skip, $locator, $decisions, $gameSpots = @{}) {
    $byCategory = @{}
    foreach ($q in $quests) {
        $category = [int]$q.category
        if (-not $byCategory.ContainsKey($category)) { $byCategory[$category] = New-Object System.Collections.Generic.List[object] }
        $byCategory[$category].Add($q)
    }
    $pins = New-Object System.Collections.Generic.List[object]
    $doors = New-Object System.Collections.Generic.List[object]
    $doorless = New-Object System.Collections.Generic.List[object]
    $drawn = @{}
    foreach ($instance in $instances) {
        if ($instance.GameKey -and $gameSpots.ContainsKey($instance.GameKey)) { foreach ($c in $instance.Categories) { $drawn[[int]$c] = $true } }
    }
    foreach ($instance in $instances) {
        $open = @(foreach ($c in $instance.Categories) { if ($byCategory.ContainsKey($c)) { $byCategory[$c] } }) |
            Where-Object { -not $pinned.Contains([int]$_.id) -and -not $skip.Contains([int]$_.id) } | Sort-Object { [int]$_.id }
        $open = @($open)
        if (-not $open.Count) { continue }
        $isDrawn = $instance.GameKey -and $gameSpots.ContainsKey($instance.GameKey)
        if (-not $isDrawn -and -not @($instance.Categories | Where-Object { -not $drawn.ContainsKey([int]$_) }).Count) { continue }
        if ($isDrawn) {
            $ids = [int[]]@($open | ForEach-Object { [int]$_.id })
            foreach ($spot in ($gameSpots[$instance.GameKey] | Sort-Object Map, X, Y)) {
                $x = [math]::Round([decimal]$spot.X, 2); $y = [math]::Round([decimal]$spot.Y, 2)
                $doors.Add([pscustomobject]@{ Instance = $instance.Name; Kind = $instance.Kind; Door = ''; Hint = 0; Side = 0; How = 'game'; Held = $false
                    Decided = $false; UiMap = $spot.Map; X = $x; Y = $y; Zones = @(); Quests = $ids })
                $pins.Add([pscustomobject][ordered]@{ map = $spot.Map; x = $x; y = $y; kind = $instance.Kind; name = $instance.Name; quests = $ids })
            }
            continue
        }
        if (-not @($instance.Doors).Count) { $doorless.Add([pscustomobject]@{ Name = $instance.Name; Quests = $open.Count }); continue }
        foreach ($door in $instance.Doors) {
            $mine = @($open | Where-Object { -not $door.Side -or ((Get-QuestSides $_) -band $door.Side) })
            if (-not $mine.Count) { continue }
            $place = ConvertTo-ZonePoint $locator $door.Map $door.X $door.Y $door.Area
            $how = $place.How; $map = $place.UiMap; $x = $place.X; $y = $place.Y
            $held = $how -in 'none', 'several'
            $decision = $decisions["$($instance.Name)|$($door.Door)"]
            if ($decision -and $held) {
                $how = $decision.Decision
                if ($how -eq 'SHOW') {
                    $map = [int]$decision.UiMapID
                    $x = [decimal]::Parse($decision.X, [Globalization.CultureInfo]::InvariantCulture); $y = [decimal]::Parse($decision.Y, [Globalization.CultureInfo]::InvariantCulture)
                }
            }
            $ids = [int[]]@($mine | ForEach-Object { [int]$_.id })
            $doors.Add([pscustomobject]@{ Instance = $instance.Name; Kind = $instance.Kind; Door = $door.Door; Hint = $door.Hint; Side = $door.Side; How = $how
                Held = $held; Decided = [bool]$decision; UiMap = $map; X = $x; Y = $y; Zones = $place.Zones; Quests = $ids })
            if ($how -in 'area', 'box', 'SHOW') {
                $pins.Add([pscustomobject][ordered]@{ map = $map; x = $x; y = $y; kind = $instance.Kind; name = $instance.Name; quests = $ids })
            }
        }
    }
    return [pscustomobject]@{ Pins = $pins.ToArray(); Doors = $doors.ToArray(); Doorless = $doorless.ToArray() }
}
