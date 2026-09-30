<#
Generates qcCategoryClientName in qcQuest.lua: for quest categories the client can name other than
by a map (those are in qcCategoryUiMapID, from Build-CategoryUiMapIDs.ps1 - run that first), where
to ask the client for the name, so it doesn't have to be translated in 11 locale files.

A category is included when one of these client tables has a row whose English name is exactly
ours, tried in this order: class, covenant, profession (skill line), map, Dungeon Journal instance,
achievement category, faction, Blizzard's UI strings, area. The lowest matching id is taken.
Class halls and the two "- Draenor" zones combine two client names ($handPicked below), and a few
entries are chosen by hand where the client's spelling differs slightly from ours.

Every entry is checked by rebuilding its English name from the tables; only the differences
listed in $expectedDifferences are allowed. Only categories holding quests are considered.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$QuestFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua",
    [string]$MenuFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcMenu.lua",
    [string]$LocaleFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\Localization.enUS.lua",
    [string]$Build = "12.1.0.69933",
    [switch]$Refresh
)

$sources = @(
    @{ Kind = "class"; Table = "ChrClasses"; Name = "Name_lang"; Id = "ID" },
    @{ Kind = "covenant"; Table = "Covenant"; Name = "Name_lang"; Id = "ID" },
    @{ Kind = "skill"; Table = "SkillLine"; Name = "DisplayName_lang"; Id = "ID" },
    @{ Kind = "map"; Table = "UiMap"; Name = "Name_lang"; Id = "ID" },
    @{ Kind = "instance"; Table = "JournalInstance"; Name = "Name_lang"; Id = "ID" },
    @{ Kind = "achievementcategory"; Table = "Achievement_Category"; Name = "Name_lang"; Id = "ID" },
    @{ Kind = "faction"; Table = "Faction"; Name = "Name_lang"; Id = "ID" },
    @{ Kind = "string"; Table = "GlobalStrings"; Name = "TagText_lang"; Id = "BaseTag"; Order = "ID" },
    @{ Kind = "area"; Table = "AreaTable"; Name = "AreaName_lang"; Id = "ID" }
)

$handPicked = @{
    "1009" = @("format", "%s (%s)", @("map", 734), @("class", 8))
    "1010" = @("format", "%s (%s)", @("map", 672), @("class", 12))
    "1011" = @("format", "%s (%s)", @("map", 702), @("class", 5))
    "1012" = @("format", "%s (%s)", @("map", 695), @("class", 1))
    "1013" = @("format", "%s (%s)", @("map", 747), @("class", 11))
    "1014" = @("format", "%s (%s)", @("area", 7753), @("class", 7))
    "1015" = @("format", "%s (%s)", @("map", 709), @("class", 10))
    "1016" = @("format", "%s (%s)", @("map", 739), @("class", 3))
    "1021" = @("format", "%s (%s)", @("map", 647), @("class", 6))
    "314" = @("format", "%s - %s", @("map", 550), @("map", 572))
    "315" = @("format", "%s - %s", @("map", 539), @("map", 572))
    "1420" = @("area", 15133)
    "1430" = @("area", 15329)
    "1221" = @("covenant", 4)
}
$expectedDifferences = @{
    "1420" = "Awakening The Machine"
    "1430" = "Delver's Headquarters"
    "1221" = "Necrolord"
}
# Categories whose only match is a placeholder, not a name a player would recognise.
$skip = @("1240")   # "9.1 Campaign" matches an area of that name

# Menu headings, by their qcL key, chosen by hand: a heading's word can mean something else in
# another language ("Midnight" the expansion, not the time of day). Headings not listed ("Main
# Zones", "Northern Kalimdor") are our own and keep their translations.
$headings = [ordered]@{
    "KALIMDOR" = @("map", 12); "EASTERNKINGDOMS" = @("map", 13); "AZEROTH" = @("map", 947)
    "VASHJIR" = @("map", 203); "OUTLAND" = @("map", 101); "NORTHREND" = @("map", 113)
    "THEMAELSTROM" = @("map", 948); "PANDARIA" = @("map", 424); "DRAENOR" = @("map", 572)
    "THEBROKENISLES" = @("map", 619); "KULTIRAS" = @("map", 876); "ZANDALAR" = @("map", 875)
    "BFA" = @("string", "EXPANSION_NAME7"); "SHADOWLANDS" = @("string", "EXPANSION_NAME8")
    "DRAGONFLIGHT" = @("string", "EXPANSION_NAME9"); "TWW" = @("string", "EXPANSION_NAME10")
    "MIDNIGHT" = @("string", "EXPANSION_NAME11"); "MISCELLANEOUS" = @("string", "MISCELLANEOUS")
    "DUNGEONSANDRAIDS" = @("achievementcategory", 168); "PLAYERVSPLAYER" = @("string", "PLAYER_V_PLAYER")
    "BATTLEGROUNDS" = @("string", "BATTLEGROUNDS"); "PROFESSIONS" = @("string", "TRADE_SKILLS")
    "WORLDEVENTS" = @("achievementcategory", 155)
}
$headingDifferences = @{
    "THEBROKENISLES" = "Broken Isles"
    "BFA" = "Battle for Azeroth"
    "PLAYERVSPLAYER" = "Player vs. Player"
}

$ProgressPreference = "SilentlyContinue"
$names = @{}
$byName = @{}
foreach ($s in $sources) {
    $csv = "$ToolsDir\$($s.Table).csv"
    if ($Refresh -or -not (Test-Path $csv)) {
        Write-Output "Downloading $($s.Table)..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$($s.Table)/csv?build=$Build" -OutFile $csv
    }
    $orderBy = if ($s.Order) { $s.Order } else { $s.Id }
    $names[$s.Kind] = @{}
    $byName[$s.Kind] = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)   # names match exactly, case included
    foreach ($row in (Import-Csv $csv | Sort-Object { [int]$_.$orderBy })) {
        $id = $row.($s.Id); $name = $row.($s.Name)
        if (-not $name) { continue }
        if ($s.Kind -eq "covenant" -and [int]$id -gt 4) { continue }   # 1-4 are the Shadowlands covenants
        $names[$s.Kind][$id] = $name
        if (-not $byName[$s.Kind].ContainsKey($name)) { $byName[$s.Kind][$name] = $id }
    }
}

function Format-English($source) {
    if ($source[0] -eq "format") {
        $parts = @(for ($i = 2; $i -lt $source.Count; $i++) { Format-English $source[$i] })
        $text = $source[1]
        foreach ($part in $parts) { $text = ([regex]'%s').Replace($text, $part.Replace('$', '$$'), 1) }
        return $text
    }
    return $names[$source[0]]["$($source[1])"]
}
function Format-Lua($source) {
    $items = foreach ($item in $source) {
        if ($item -is [array]) { Format-Lua $item }
        elseif ("$item" -match '^\d+$') { "$item" }
        else { '"' + $item + '"' }
    }
    return "{" + ($items -join ",") + "}"
}

$content = [System.IO.File]::ReadAllText($QuestFile, [System.Text.Encoding]::UTF8)
$categories = [ordered]@{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcQuestCategories=\{(.*?)^\}').Groups[1].Value, '\{(\d+),"((?:[^"\\]|\\.)*)"\}')) {
    if (-not $categories.Contains($m.Groups[1].Value)) { $categories[$m.Groups[1].Value] = $m.Groups[2].Value }
}
$mapNamed = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcCategoryUiMapID = \{(.*?)^\}').Groups[1].Value, '\[(\d+)\]=')) { [void]$mapNamed.Add($m.Groups[1].Value) }
$withQuests = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in [regex]::Matches($content, '(?m)^\[\d+\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",(\d+),')) { [void]$withQuests.Add($m.Groups[1].Value) }

$chosen = [ordered]@{}
$left = New-Object System.Collections.Generic.List[string]
foreach ($cat in ($categories.Keys | Sort-Object { [int]$_ })) {
    if ($mapNamed.Contains($cat) -or -not $withQuests.Contains($cat) -or $skip -contains $cat) { continue }
    $name = $categories[$cat]
    $source = $null
    if ($handPicked.ContainsKey($cat)) { $source = $handPicked[$cat] }
    else {
        foreach ($s in $sources) {
            if ($byName[$s.Kind].ContainsKey($name)) { $source = @($s.Kind, $byName[$s.Kind][$name]); break }
        }
    }
    if (-not $source) { $left.Add("$cat $name"); continue }
    $english = Format-English $source
    $expected = if ($expectedDifferences.ContainsKey($cat)) { $expectedDifferences[$cat] } else { $name }
    if ($english -cne $expected) { throw "Category $cat '$name': the client would call it '$english'" }
    $chosen[$cat] = $source
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("")
$lines.Add("qcCategoryClientName = {  -- CategoryId -> where the client names it other than by map; see qcClientCategoryName")
$lines.Add("")
foreach ($cat in $chosen.Keys) { $lines.Add("`t[$cat]=$(Format-Lua $chosen[$cat]),`t-- $($categories[$cat])") }
$lines.Add("}")
$lines.Add("")

$existing = [regex]::Match($content, '(?sm)^\r?\nqcCategoryClientName = \{.*?^\}\r?\n\r?\n')
if ($existing.Success) { $content = $content.Remove($existing.Index, $existing.Length) }
$anchor = [regex]::Match($content, '(?sm)^qcCategoryUiMapID = \{.*?^\}\r?\n')
if (-not $anchor.Success) { throw "qcCategoryUiMapID block not found; run Build-CategoryUiMapIDs.ps1 first" }
$insertAt = $anchor.Index + $anchor.Length
$content = $content.Substring(0, $insertAt) + (($lines -join "`r`n") + "`r`n") + $content.Substring($insertAt)
[System.IO.File]::WriteAllText($QuestFile, $content, (New-Object System.Text.UTF8Encoding $false))

"Categories the client names other than by map: $($chosen.Count)"
$chosen.Values | Group-Object { $_[0] } | Sort-Object Count -Descending | ForEach-Object { "  $($_.Name): $($_.Count)" }
"Categories with quests still named by our own strings: $($left.Count)"
$left | ForEach-Object { "  $_" }

$english = @{}
foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($LocaleFile, [System.Text.Encoding]::UTF8), '(?m)^\s*([A-Z0-9]+)\s*=\s*"((?:[^"\\]|\\.)*)"')) { $english[$m.Groups[1].Value] = $m.Groups[2].Value }
foreach ($key in $headings.Keys) {
    $client = Format-English $headings[$key]
    $expected = if ($headingDifferences.ContainsKey($key)) { $headingDifferences[$key] } else { $english[$key] }
    if ($client -cne $expected) { throw "Heading $key '$($english[$key])': the client would call it '$client'" }
}

$lines = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllText($MenuFile, [System.Text.Encoding]::UTF8) -split "`r`n")
$named = @{}
for ($i = 0; $i -lt $lines.Count; $i++) {
    $m = [regex]::Match($lines[$i], '^(\{text=(?:stringformat\("   %s",)?qcL\.([A-Z0-9]+)\)?,)(clientName=\{[^}]*(?:\{[^}]*\}[^}]*)*\},)?')
    if (-not $m.Success -or -not $headings.Contains($m.Groups[2].Value)) { continue }
    if (($lines[$i] -split 'menuList=\{', 2)[0] -match 'arg1=') { continue }   # a category entry; qcCategoryName names it
    $field = "clientName=$(Format-Lua $headings[$m.Groups[2].Value]),"
    $lines[$i] = $m.Groups[1].Value + $field + $lines[$i].Substring($m.Length)
    $named[$m.Groups[2].Value] = 1 + $named[$m.Groups[2].Value]
}
$unused = @($headings.Keys | Where-Object { -not $named.ContainsKey($_) })
if ($unused.Count) { throw "No menu heading found for: $($unused -join ', ')" }
[System.IO.File]::WriteAllText($MenuFile, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
"Menu headings the client names: $($headings.Count) ($(($named.Values | Measure-Object -Sum).Sum) lines)"
