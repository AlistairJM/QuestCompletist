<#
Writes WoW: Forever's menu and category tables into QuestCompletist\Forever\ (docs/plans/forever.md,
phase 4): qcMenu.lua, qcQuest.lua and qcUnavailableQuests.lua. They're built from the data
Import-ForeverData.ps1 writes in data\forever\ and the client's tables for -Build. Rerun it after
Import-ForeverData.ps1.

Every category in the data gets a place in the menu:
  - The zones of the Eastern Kingdoms and Kalimdor go under their region. Import-ForeverData.ps1
    has already filed subzones' quests under their zone. A zone missing from the region table below
    goes in its continent's "Other" group; add it to the table.
  - Lands with a map of their own (Zephras Isle) go under Continents.
  - Dungeons, raids and battlegrounds are placed by their instance's type. That includes an outdoor
    area of the same name the importer kept, such as Blackrock Depths, but never a zone with a map
    of its own: Forever also has a dungeon called Deadwind Pass.
  - Class, profession and holiday headings, and Forever's other headings, go under their own titles;
    Uncategorized comes last.
  - Headings the client has a name for take it ($headingSources below), as retail's do. Forever
    has no achievement categories, so "Dungeons & Raids" is the Group Finder's title and "World
    Events" stays ours.
The Settings entries are copied from retail's QuestCompletist\qcMenu.lua.

qcQuest.lua holds what the core reads:
  - which map is which category (qcAreaIDToCategoryID);
  - each category's English name (qcQuestCategories);
  - where the client names it (qcCategoryClientName: the area, class or profession, else one of the
    client's in-game strings with the category's English name, so the name is in the player's
    language);
  - Forever's storylines (qcQuestLines);
  - the reputation each quest rewards (qcQuestReputation), from reputation.jsonl, and those
    factions' English names (qcFactions), for when the game doesn't name one;
  - the profession, and the skill level in it, each quest needs (qcQuestSkillRequirements), from
    skills.jsonl;
  - each quest's breadcrumbs (qcBreadcrumbQuests) and the quests it shuts out
    (qcMutuallyExclusive), from links.jsonl;
  - empty tables for retail-only features.
qcUnavailableQuests.lua is empty: no Forever quest is flagged yet.

-Check writes nothing and exits with 1 if a file is out of date.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data\forever'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist\Forever'),
    [string]$LocaleFile = (Join-Path $PSScriptRoot '..\QuestCompletist\Localization.enUS.lua'),
    [string]$Build = "1.60.1.70205",
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"

function Get-ClientTable([string]$table) {
    $path = "$ToolsDir\$table-$Build.csv"
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path
        Start-Sleep -Milliseconds 300
    }
    return Import-Csv $path
}

$regions = [ordered]@{
    KALIMDOR = [ordered]@{
        NORTHERNKALIMDOR = @('Ashenvale', 'Azshara', 'Darkshore', 'Darnassus', 'Felwood', 'Moonglade', 'Mount Hyjal', 'Teldrassil', 'Winterspring')
        CENTRALKALIMDOR = @('Desolace', 'Durotar', 'Dustwallow Marsh', 'Mulgore', 'Orgrimmar', 'Stonetalon Mountains', 'The Barrens', 'Thunder Bluff')
        SOUTHERNKALIMDOR = @('Feralas', "Shen'dralas", 'Silithus', 'Tanaris', 'Thousand Needles', "Un'Goro Crater")
    }
    EASTERNKINGDOMS = [ordered]@{
        LORDAERON = @('Alterac Mountains', 'Arathi Highlands', 'Eastern Plaguelands', 'Hillsbrad Foothills', 'Silverpine Forest', 'The Hinterlands', "Thoradin's Wall", 'Tirisfal Glades', 'Undercity', 'Western Plaguelands')
        KHAZMODAN = @('Badlands', 'Dun Morogh', 'Ironforge', 'Loch Modan', 'Searing Gorge', 'Wetlands')
        AZEROTH = @('Blackrock Mountain', 'Blasted Lands', 'Burning Steppes', 'Deadwind Pass', 'Duskwood', 'Elwynn Forest', 'Redridge Mountains', 'Riverglades', 'Stormwind City', 'Stranglethorn Vale', 'Swamp of Sorrows', 'Westfall')
    }
}
$continentOfMap = @{ 1 = 'KALIMDOR'; 0 = 'EASTERNKINGDOMS' }
# Headings the client names, by their qcL key. Each must give the English in Localization.enUS.lua.
$headingSources = @{
    KALIMDOR = @('map', 1414); EASTERNKINGDOMS = @('map', 1415); AZEROTH = @('map', 947)
    DUNGEONSANDRAIDS = @('string', 'GROUP_FINDER'); DUNGEONS = @('string', 'DUNGEONS'); RAIDS = @('string', 'RAIDS')
    MISCELLANEOUS = @('string', 'MISCELLANEOUS'); BATTLEGROUNDS = @('string', 'BATTLEGROUNDS'); PROFESSIONS = @('string', 'TRADE_SKILLS')
}
$classIdBySort = @{ (-81) = 1; (-141) = 2; (-261) = 3; (-162) = 4; (-262) = 5; (-82) = 7; (-161) = 8; (-61) = 9; (-263) = 11 }
$skillBySort = @{ (-24) = 182; (-101) = 356; (-121) = 164; (-181) = 171; (-182) = 165; (-201) = 202; (-264) = 197; (-304) = 185; (-324) = 129 }
$eventSorts = @(-22, -364, -365, -366, -368, -369)
$professionAreas = @('Crafting')

$areas = @{}; foreach ($row in Get-ClientTable 'AreaTable') { $areas[[int]$row.ID] = $row }
$maps = @{}; foreach ($row in Get-ClientTable 'Map') { $maps[[int]$row.ID] = $row }
$sortName = @{}; foreach ($row in Get-ClientTable 'QuestSort') { $sortName[-[int]$row.ID] = $row.SortName_lang }
$uiMapType = @{}; $uiMapName = @{}
foreach ($row in Get-ClientTable 'UiMap') { $uiMapType[[int]$row.ID] = [int]$row.Type; $uiMapName[[int]$row.ID] = $row.Name_lang }
# The client's UI strings loaded in game (flag 1; the rest are the login screen's), by their English
# text, matched exactly, the lowest ID first.
$stringText = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
$stringByText = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
foreach ($row in (Get-ClientTable 'GlobalStrings' | Sort-Object { [int]$_.ID })) {
    if (-not ([int]"0$($row.Flags)" -band 1)) { continue }
    $stringText[$row.BaseTag] = $row.TagText_lang
    if ($row.TagText_lang -and -not $stringByText.ContainsKey($row.TagText_lang)) { $stringByText[$row.TagText_lang] = $row.BaseTag }
}
$english = @{}
foreach ($m in [regex]::Matches([IO.File]::ReadAllText($LocaleFile), '(?m)^\s*([A-Z0-9]+)\s*=\s*"((?:[^"\\]|\\.)*)"')) {
    $english[$m.Groups[1].Value] = $m.Groups[2].Value
}
$zoneMaps = @{}
foreach ($row in (Get-ClientTable 'UiMapAssignment' | Sort-Object { [int]$_.UiMapID }, { [int]$_.ID })) {
    $uiMap = [int]$row.UiMapID; $area = [int]$row.AreaID
    if ($uiMapType[$uiMap] -ge 3 -and $area -and -not $zoneMaps.ContainsKey($uiMap)) { $zoneMaps[$uiMap] = $area }
}
$instanceType = @{}
foreach ($map in ($maps.Values | Sort-Object { -[int]$_.AreaTableID }, { [int]$_.ID })) {
    $type = [int]$map.InstanceType
    if ($type -ge 1 -and $type -le 4 -and -not $instanceType.ContainsKey($map.MapName_lang)) { $instanceType[$map.MapName_lang] = $type }
}

$categories = @{}
foreach ($line in [IO.File]::ReadAllLines((Join-Path $DataDir 'quests.jsonl'))) {
    if ($line -match '"category":(-?\d+)') { $categories[[int]$Matches[1]] = $true }
}
function Get-EnglishName([int]$id) {
    if ($id -eq 0) { return 'Uncategorized' }
    if ($id -lt 0) { return $sortName[$id] }
    return $areas[$id].AreaName_lang
}

$continents = @{}
foreach ($continent in $regions.Keys) {
    $continents[$continent] = [ordered]@{}
    foreach ($region in $regions[$continent].Keys) { $continents[$continent][$region] = New-Object System.Collections.Generic.List[int] }
    $continents[$continent]['OTHERCATEGORIES'] = New-Object System.Collections.Generic.List[int]
}
$lands = New-Object System.Collections.Generic.List[int]
$dungeons = New-Object System.Collections.Generic.List[int]
$raids = New-Object System.Collections.Generic.List[int]
$battlegrounds = New-Object System.Collections.Generic.List[int]
$classes = New-Object System.Collections.Generic.List[int]
$professions = New-Object System.Collections.Generic.List[int]
$events = New-Object System.Collections.Generic.List[int]
$others = New-Object System.Collections.Generic.List[int]
foreach ($id in $categories.Keys) {
    if ($id -eq 0) { continue }
    if ($id -lt 0) {
        if ($classIdBySort.ContainsKey($id)) { $classes.Add($id) }
        elseif ($skillBySort.ContainsKey($id)) { $professions.Add($id) }
        elseif ($eventSorts -contains $id) { $events.Add($id) }
        else { $others.Add($id) }
        continue
    }
    $area = $areas[$id]
    if (-not $area) { throw "Category $id isn't in AreaTable for build $Build. Rerun Import-ForeverData.ps1." }
    $type = [int]$maps[[int]$area.ContinentID].InstanceType
    if ($type -eq 0 -and -not ($zoneMaps.Values -contains $id) -and $instanceType.ContainsKey($area.AreaName_lang)) {
        $type = $instanceType[$area.AreaName_lang]
    }
    if ($type -eq 1) { $dungeons.Add($id); continue }
    if ($type -eq 2) { $raids.Add($id); continue }
    if ($type -eq 3 -or $type -eq 4) { $battlegrounds.Add($id); continue }
    if ($professionAreas -contains $area.AreaName_lang) { $professions.Add($id); continue }
    $continent = $continentOfMap[[int]$area.ContinentID]
    if (-not $continent) {
        if ($zoneMaps.Values -contains $id) { $lands.Add($id) } else { $others.Add($id) }
        continue
    }
    $top = $area
    while ([int]$top.ParentAreaID -and $areas[[int]$top.ParentAreaID]) { $top = $areas[[int]$top.ParentAreaID] }
    $placed = $false
    foreach ($region in $regions[$continent].Keys) {
        if ($regions[$continent][$region] -contains $top.AreaName_lang) { $continents[$continent][$region].Add($id); $placed = $true; break }
    }
    if (-not $placed) { $continents[$continent]['OTHERCATEGORIES'].Add($id) }
}

function Get-Sorted($ids) { return @($ids | Sort-Object { Get-EnglishName $_ }, { $_ }) }
function Format-Leaf([int]$id, [string]$indent) {
    $text = if ($indent) { "text=`"$indent`"," } else { '' }
    return "{${text}isTitle=false,notCheckable=false,hasArrow=false,arg1=$id,func=function(button,arg1)qcProcessMenuSelection(button,arg1);end}"
}
# A heading's clientName field, if the client names it ($headingSources).
function Get-ClientField([string]$key) {
    $source = $headingSources[$key]
    if (-not $source) { return '' }
    $name = if ($source[0] -eq 'map') { $uiMapName[$source[1]] } else { $stringText[$source[1]] }
    if ($name -cne $english[$key]) { throw "Heading $key '$($english[$key])': the client for build $Build would call it '$name'." }
    $id = if ($source[0] -eq 'map') { $source[1] } else { "`"$($source[1])`"" }
    return "clientName={`"$($source[0])`",$id},"
}
function Format-Submenu([string]$key, [string[]]$entries) {
    return "{text=stringformat(`"   %s`",qcL.$key),$(Get-ClientField $key)isTitle=false,notCheckable=true,hasArrow=true,menuList={`r`n" + ($entries -join ",`r`n") + "}}"
}
function Format-Title([string]$key) {
    return "{text=qcL.$key,$(Get-ClientField $key)isTitle=true,notCheckable=true,hasArrow=false}"
}
function Get-ZoneLeaves($ids) { return @(Get-Sorted $ids | ForEach-Object { Format-Leaf $_ '' }) }

$menu = New-Object System.Collections.Generic.List[string]
$menu.Add((Format-Title 'CONTINENTS'))
foreach ($continent in $regions.Keys) {
    $groups = New-Object System.Collections.Generic.List[string]
    foreach ($region in $continents[$continent].Keys) {
        $zones = $continents[$continent][$region]
        if ($zones.Count) { $groups.Add((Format-Submenu $region @(Get-ZoneLeaves $zones))) }
    }
    if ($groups.Count) { $menu.Add((Format-Submenu $continent $groups.ToArray())) }
}
foreach ($id in (Get-Sorted $lands)) { $menu.Add((Format-Leaf $id '   ')) }
if ($dungeons.Count -or $raids.Count) {
    $menu.Add((Format-Title 'DUNGEONSANDRAIDS'))
    if ($dungeons.Count) { $menu.Add((Format-Submenu 'DUNGEONS' @(Get-Sorted $dungeons | ForEach-Object { Format-Leaf $_ '' }))) }
    if ($raids.Count) { $menu.Add((Format-Submenu 'RAIDS' @(Get-Sorted $raids | ForEach-Object { Format-Leaf $_ '' }))) }
}
if ($classes.Count) {
    $menu.Add((Format-Title 'CLASSQUESTS'))
    $menu.Add((Format-Submenu 'CLASSES' @(Get-Sorted $classes | ForEach-Object { Format-Leaf $_ '' })))
}
$menu.Add((Format-Title 'MISCELLANEOUS'))
if ($battlegrounds.Count) { $menu.Add((Format-Submenu 'BATTLEGROUNDS' @(Get-Sorted $battlegrounds | ForEach-Object { Format-Leaf $_ '' }))) }
if ($professions.Count) { $menu.Add((Format-Submenu 'PROFESSIONS' @(Get-Sorted $professions | ForEach-Object { Format-Leaf $_ '' }))) }
if ($events.Count) { $menu.Add((Format-Submenu 'WORLDEVENTS' @(Get-Sorted $events | ForEach-Object { Format-Leaf $_ '' }))) }
foreach ($id in (Get-Sorted $others)) { $menu.Add((Format-Leaf $id '   ')) }
$menu.Add((Format-Leaf 0 '   '))
$retailMenu = [IO.File]::ReadAllLines((Join-Path $PSScriptRoot '..\QuestCompletist\qcMenu.lua'))
$settingsStart = [Array]::FindIndex($retailMenu, [Predicate[string]] { param($l) $l.StartsWith('{text=GetText("SETTINGS"),isTitle=true') })
$settingsEnd = [Array]::FindLastIndex($retailMenu, [Predicate[string]] { param($l) $l.Trim() -eq '}' })
if ($settingsStart -lt 0 -or $settingsEnd -le $settingsStart) { throw "Couldn't find the Settings entries in QuestCompletist\qcMenu.lua." }
$settings = ($retailMenu[$settingsStart..($settingsEnd - 1)] -join "`r`n").TrimEnd(',')

$header = "-- Generated by tools\Build-ForeverMenu.ps1 from data\forever\ and the client's tables (build $Build). Rerun it instead of editing this file."
$menuText = $header + "`r`nlocal qcL = qcLocalize`r`nlocal stringformat = string.format`r`nqcMenu={`r`n" + ($menu -join ",`r`n") + ",`r`n" + $settings + "`r`n}`r`n"

function Format-LuaString([string]$text) { return '"' + $text.Replace('\', '\\').Replace('"', '\"') + '"' }
$quest = New-Object System.Text.StringBuilder
[void]$quest.Append("$header`r`nqcAreaIDToCategoryID={`r`n")
foreach ($uiMap in ($zoneMaps.Keys | Sort-Object)) { [void]$quest.Append("[$uiMap]=$($zoneMaps[$uiMap]),`r`n") }
[void]$quest.Append("}`r`nqcQuestCategories={`r`n")
foreach ($id in (Get-Sorted @($categories.Keys))) { [void]$quest.Append("{$id,$(Format-LuaString (Get-EnglishName $id))},`r`n") }
[void]$quest.Append("}`r`nqcCategoryUiMapID={}`r`nqcCategoryClientName={`r`n")
$ourNames = New-Object System.Collections.Generic.List[string]
foreach ($id in (@($categories.Keys) | Sort-Object)) {
    $name = [string](Get-EnglishName $id)
    $source = if ($id -eq 0) { '{"string","STABLE_PET_UNCATEGORIZED"}' } elseif ($id -gt 0) { "{`"area`",$id}" }
        elseif ($classIdBySort.ContainsKey($id)) { "{`"class`",$($classIdBySort[$id])}" } elseif ($skillBySort.ContainsKey($id)) { "{`"skill`",$($skillBySort[$id])}" }
        elseif ($name -and $stringByText.ContainsKey($name)) { "{`"string`",`"$($stringByText[$name])`"}" }
    if ($source) { [void]$quest.Append("[$id]=$source,`r`n") } else { $ourNames.Add($name) }
}
$inData = @{}
foreach ($line in [IO.File]::ReadAllLines((Join-Path $DataDir 'quests.jsonl'))) { if ($line -match '^\{"id":(\d+),') { $inData[[int]$Matches[1]] = $true } }
function Read-DataLines([string]$name, [string]$pattern) {
    $n = 0
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $DataDir $name))) {
        $n++
        if ($line -notmatch $pattern) { throw "$name line $n isn't a line Import-ForeverData.ps1 writes: $line" }
        if (-not $inData[[int]$Matches[1]]) { throw "$name line $n is about quest $($Matches[1]), which quests.jsonl doesn't have. Rerun Import-ForeverData.ps1." }
        , $Matches.Clone()
    }
}
$rewards = @{}; $factions = @{}
foreach ($m in (Read-DataLines 'reputation.jsonl' '^\{"quest":(\d+),"faction":(\d+),"amount":(-?\d+)\}$')) {
    $rewards[[int]$m[1]] += @("[$($m[2])]=$($m[3])")
    $factions[[int]$m[2]] = $true
}
$links = @(Read-DataLines 'links.jsonl' '^\{"quest":(\d+)(?:,"breadcrumbs":\[(\d+(?:,\d+)*)\])?(?:,"exclusiveWith":\[(\d+(?:,\d+)*)\])?\}$')
$skills = @(Read-DataLines 'skills.jsonl' '^\{"quest":(\d+),"skill":(\d+),"level":(\d+)\}$')
$factionName = @{}
if ($factions.Count) { foreach ($row in Get-ClientTable 'Faction') { $factionName[[int]$row.ID] = $row.Name_lang } }
[void]$quest.Append("}`r`nqcFactions={`r`n")
foreach ($faction in ($factions.Keys | Sort-Object)) {
    if (-not $factionName[$faction]) { throw "Faction $faction, which quests reward, has no name in the client's Faction table for build $Build." }
    [void]$quest.Append("[$faction]=$(Format-LuaString $factionName[$faction]),`r`n")
}
[void]$quest.Append("}`r`nqcRenownLevelRequirements={}`r`nqcQuestSkillRequirements={`r`n")
foreach ($m in $skills) { [void]$quest.Append("[$($m[1])]={$($m[2]),$($m[3])},`r`n") }
[void]$quest.Append("}`r`nqcQuestReputation={`r`n")
foreach ($id in ($rewards.Keys | Sort-Object)) { [void]$quest.Append("[$id]={$($rewards[$id] -join ',')},`r`n") }
[void]$quest.Append("}`r`nqcQuestLines={`r`n")
$lineQuests = @{}
foreach ($row in (Get-ClientTable 'QuestLineXQuest' | Sort-Object { [int]$_.QuestLineID }, { [int]$_.OrderIndex })) {
    if ($inData[[int]$row.QuestID]) { $lineQuests[[int]$row.QuestLineID] += @([int]$row.QuestID) }
}
foreach ($row in (Get-ClientTable 'QuestLine' | Sort-Object { [int]$_.ID })) {
    $ids = $lineQuests[[int]$row.ID]
    if ($ids) { [void]$quest.Append("`t[$($row.ID)]={name=$(Format-LuaString $row.Name_lang),quests={$($ids -join ',')}},`r`n") }
}
[void]$quest.Append("}`r`nqcBreadcrumbQuests={`r`n")
foreach ($m in ($links | Where-Object { $_[2] })) { [void]$quest.Append("[$($m[1])]={$($m[2])},`r`n") }
[void]$quest.Append("}`r`nqcMutuallyExclusive={`r`n")
foreach ($m in ($links | Where-Object { $_[3] })) { [void]$quest.Append("[$($m[1])]={$($m[3])},`r`n") }
[void]$quest.Append("}`r`n")
foreach ($table in 'qcOverrideDailyExclusiveQuest', 'qcOverrideWeeklyExclusiveQuest') { [void]$quest.Append("$table={}`r`n") }
$unavailable = "$header`r`nqcUnavailableQuests = {`r`n}`r`n"

$utf8 = New-Object System.Text.UTF8Encoding $false
$outdated = 0
New-Item -ItemType Directory -Force $AddonDir | Out-Null
foreach ($file in @(@{ Name = 'qcMenu.lua'; Text = $menuText }, @{ Name = 'qcQuest.lua'; Text = $quest.ToString() }, @{ Name = 'qcUnavailableQuests.lua'; Text = $unavailable })) {
    $path = Join-Path $AddonDir $file.Name
    $old = if (Test-Path $path) { [IO.File]::ReadAllText($path) } else { '' }
    if ($old -ceq $file.Text) { "$($file.Name): up to date"; continue }
    if ($Check) { "$($file.Name): doesn't match the data and client tables"; $outdated++; continue }
    [IO.File]::WriteAllText($path, $file.Text, $utf8)
    "$($file.Name): written"
}
"{0} categories: {1} zones, {2} other lands, {3} dungeons, {4} raids, {5} battlegrounds, {6} classes, {7} professions, {8} world events, {9} others." -f
    $categories.Count, ($categories.Count - $lands.Count - $dungeons.Count - $raids.Count - $battlegrounds.Count - $classes.Count - $professions.Count - $events.Count - $others.Count - [int]$categories.ContainsKey(0)),
    $lands.Count, $dungeons.Count, $raids.Count, $battlegrounds.Count, $classes.Count, $professions.Count, $events.Count, $others.Count
$unplaced = @($continents.Values | ForEach-Object { $_['OTHERCATEGORIES'] } | ForEach-Object { Get-EnglishName $_ })
if ($unplaced.Count) { "Zones in no region (in their continent's Other group): $($unplaced -join ', ')" }
if ($ourNames.Count) { "Categories still named by our own strings: $(($ourNames | Sort-Object) -join ', ')" }
$keyless = @($ourNames | Where-Object { -not $english.ContainsKey(($_ -replace '[^A-Za-z0-9]', '').ToUpperInvariant()) } | Sort-Object)
if ($keyless.Count) { "Of those, with no key in Localization.enUS.lua, so in English in every language: $($keyless -join ', ')" }
if ($outdated) { exit 1 }
