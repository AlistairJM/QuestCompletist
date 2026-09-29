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
    $byName[$s.Kind] = @{}
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
