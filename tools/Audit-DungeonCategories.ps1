<#
Report only: checks every dungeon and raid in the game's Dungeon Journal against our categories and
menu, expansion by expansion.

For each journal instance (Current Season and the world-boss entries left out) it reports:
  - the categories named like it (case, punctuation and a leading "The" ignored);
  - where the menu reaches them - it should be under Dungeons & Raids, in the instance's expansion;
  - the quests tied to it, and where those are filed. A quest is tied to an instance when its name
    is "<instance>: ...", its Blizzard API area is the instance, or our zone text is the instance.
It also lists categories in a Dungeons & Raids expansion submenu that aren't a journal instance of
that expansion.

The menu is read by loading qcMenu.lua in Lua 5.1, so nested submenus come out exactly as the addon
builds them. Writes tools/dungeon_audit.csv.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [string]$Build = "12.1.0.69933",
    [switch]$Refresh
)
$ErrorActionPreference = "Stop"

foreach ($table in "JournalTier", "JournalTierXInstance", "JournalInstance", "Map") {
    if ($Refresh -or -not (Test-Path "$ToolsDir\$table.csv")) {
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile "$ToolsDir\$table.csv"
    }
}

function Get-Key($s) { return (($s -replace '^The\s+', '') -replace '[^A-Za-z0-9]', '').ToLower() }

# Categories that group several instances, so they match no single journal instance: Ahn'Qiraj,
# Auchindoun, Caverns of Time, Coilfang Reservoir, Hellfire Citadel (TBC) and Tempest Keep.
$hubs = @("3", "14", "36", "39", "95", "205")

$tiers = @{}
foreach ($row in Import-Csv "$ToolsDir\JournalTier.csv") { if ([int]$row.Expansion -lt 9000) { $tiers[$row.ID] = $row } }
$instances = @{}
# Flag 2 marks the world-boss pages (Pandaria, Broken Isles, Midnight), not instances.
foreach ($row in Import-Csv "$ToolsDir\JournalInstance.csv") { if (-not ([int]$row.Flags -band 2)) { $instances[$row.ID] = $row } }
$instanceType = @{}
foreach ($row in Import-Csv "$ToolsDir\Map.csv") { $instanceType[$row.ID] = $row.InstanceType }
$tierNames = @{}
foreach ($tier in $tiers.Values) { $tierNames[(Get-Key $tier.Name_lang)] = $true }

# The expansion of an instance is the earliest tier listing it.
$expansionOf = @{}
foreach ($row in Import-Csv "$ToolsDir\JournalTierXInstance.csv") {
    if (-not $tiers.ContainsKey($row.JournalTierID) -or -not $instances.ContainsKey($row.JournalInstanceID)) { continue }
    # The journal counts expansions from 1 (Shadowlands is 900); the client's EXPANSION_NAMEn from 0.
    $expansion = [int]$tiers[$row.JournalTierID].Expansion / 100 - 1
    if (-not $expansionOf.ContainsKey($row.JournalInstanceID) -or $expansion -lt $expansionOf[$row.JournalInstanceID]) { $expansionOf[$row.JournalInstanceID] = $expansion }
}

$content = [System.IO.File]::ReadAllText("$AddonDir\qcQuest.lua", [System.Text.Encoding]::UTF8)
$categoryName = @{}
$categoriesByKey = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcQuestCategories=\{(.*?)^\}').Groups[1].Value, '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) {
    if ($categoryName.ContainsKey($m.Groups[1].Value)) { continue }
    $categoryName[$m.Groups[1].Value] = $m.Groups[2].Value
    $key = Get-Key $m.Groups[2].Value
    if (-not $categoriesByKey.ContainsKey($key)) { $categoriesByKey[$key] = New-Object System.Collections.Generic.List[string] }
    $categoriesByKey[$key].Add($m.Groups[1].Value)
}

# Menu paths, from the menu as Lua builds it.
$dumper = @'
qcLocalize = setmetatable({}, {__index = function(_, k) return "qcL." .. k end})
function GetText(k) return "GetText." .. k end
dofile(arg[1])
local function walk(list, path)
    for _, item in ipairs(list) do
        local label = (item.text or ""):gsub("^%s+", "")
        if item.menuList then walk(item.menuList, path .. " > " .. label)
        elseif type(item.arg1) == "number" then print(item.arg1 .. "\t" .. path) end
    end
end
local heading = ""
for _, item in ipairs(qcMenu) do
    local label = (item.text or ""):gsub("^%s+", "")
    if item.isTitle then heading = label
    elseif item.menuList then walk(item.menuList, heading .. " > " .. label)
    elseif type(item.arg1) == "number" then print(item.arg1 .. "\t" .. heading) end
end
'@
$dumperFile = [System.IO.Path]::GetTempFileName() + ".lua"
[System.IO.File]::WriteAllText($dumperFile, $dumper)
$menuLines = & $Lua $dumperFile "$AddonDir\qcMenu.lua"
Remove-Item $dumperFile
if ($LASTEXITCODE -ne 0) { throw "Lua could not load qcMenu.lua" }
$menuPaths = @{}
foreach ($line in $menuLines) {
    $category, $path = $line -split "`t", 2
    if (-not $menuPaths.ContainsKey($category)) { $menuPaths[$category] = New-Object System.Collections.Generic.List[string] }
    $menuPaths[$category].Add($path)
}
$dungeonsHeading = "qcL.DUNGEONSANDRAIDS"

# The English name the addon shows: qcCategoryUiMapID first, then qcCategoryClientName, then ours.
$uiMapName = @{}
foreach ($row in Import-Csv "$ToolsDir\UiMap.csv") { $uiMapName[$row.ID] = $row.Name_lang }
$areaName = @{}
foreach ($row in Import-Csv "$ToolsDir\AreaTable.csv") { $areaName[$row.ID] = $row.AreaName_lang }
$journalName = @{}
foreach ($row in Import-Csv "$ToolsDir\JournalInstance.csv") { $journalName[$row.ID] = $row.Name_lang }
$namedByMap = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcCategoryUiMapID\s*=\s*\{(.*?)^\}').Groups[1].Value, '\[(\d+)\]=(\d+)')) { $namedByMap[$m.Groups[1].Value] = $m.Groups[2].Value }
$namedBySource = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcCategoryClientName\s*=\s*\{(.*?)^\}').Groups[1].Value, '\[(\d+)\]=\{"(map|instance|area)",(\d+)\}')) { $namedBySource[$m.Groups[1].Value] = @($m.Groups[2].Value, $m.Groups[3].Value) }
function Get-ShownName($category) {
    if ($namedByMap.ContainsKey($category)) { return $uiMapName[$namedByMap[$category]] }
    if ($namedBySource.ContainsKey($category)) {
        $kind, $id = $namedBySource[$category]
        switch ($kind) { "map" { return $uiMapName[$id] } "instance" { return $journalName[$id] } "area" { return $areaName[$id] } }
    }
    return $categoryName[$category]
}
function Get-ExpectedPath($expansion) { return "$dungeonsHeading > GetText.EXPANSION_NAME$expansion" }

# Quests, and the instance names each one is tied to.
$instanceKeys = @{}
foreach ($id in $expansionOf.Keys) {
    foreach ($key in @(Get-Key $instances[$id].Name_lang)) {
        if ($tierNames.ContainsKey($key)) { continue }
        if (-not $instanceKeys.ContainsKey($key)) { $instanceKeys[$key] = New-Object System.Collections.Generic.List[string] }
        if (-not $instanceKeys[$key].Contains($id)) { $instanceKeys[$key].Add($id) }
    }
}
$questsIn = @{}
$tied = @{}
foreach ($m in [regex]::Matches($content, '(?m)^\[(\d+)\]=\{\d+,"((?:[^"\\]|\\.)*)",[^,]*,"((?:[^"\\]|\\.)*)",(-?\d+),')) {
    $questId = $m.Groups[1].Value
    $category = $m.Groups[4].Value
    $questsIn[$category] = 1 + $questsIn[$category]
    $how = @{}
    $prefix = [regex]::Match($m.Groups[2].Value, '^(.+?):\s')
    if ($prefix.Success) { $how[(Get-Key $prefix.Groups[1].Value)] += @("name") }
    if ($m.Groups[3].Value) { $how[(Get-Key $m.Groups[3].Value)] += @("zone text") }
    $cached = "$ToolsDir\quest_api_cache\$questId.json"
    if (Test-Path $cached) {
        $area = [regex]::Match([System.IO.File]::ReadAllText($cached), '"area":\{.*?"name":"([^"]+)"')
        if ($area.Success) { $how[(Get-Key $area.Groups[1].Value)] += @("API area") }
    }
    foreach ($key in $how.Keys) {
        if (-not $instanceKeys.ContainsKey($key)) { continue }
        if (-not $tied.ContainsKey($key)) { $tied[$key] = New-Object System.Collections.Generic.List[object] }
        $tied[$key].Add([PSCustomObject]@{ QuestID = $questId; Name = $m.Groups[2].Value; Category = $category; How = $how[$key] -join "+" })
    }
}

$rows = New-Object System.Collections.Generic.List[object]
$elsewhereRows = New-Object System.Collections.Generic.List[object]
foreach ($id in ($expansionOf.Keys | Sort-Object { $expansionOf[$_] }, { $instances[$_].Name_lang })) {
    $instance = $instances[$id]
    $key = Get-Key $instance.Name_lang
    if ($tierNames.ContainsKey($key)) { continue }
    $expansion = $expansionOf[$id]
    $kind = switch ($instanceType[$instance.MapID]) { "1" { "dungeon" } "2" { "raid" } default { "other ($($instanceType[$instance.MapID]))" } }
    $categories = @(if ($categoriesByKey.ContainsKey($key)) { $categoriesByKey[$key] | Where-Object { $hubs -notcontains $_ } })
    $keys = @($key)
    $paths = @($categories | ForEach-Object { if ($menuPaths.ContainsKey($_)) { $menuPaths[$_] } })
    $inDungeonMenu = @($categories | Where-Object { $menuPaths.ContainsKey($_) -and $menuPaths[$_] -contains (Get-ExpectedPath $expansion) })
    $quests = @($keys | Select-Object -Unique | ForEach-Object { if ($tied.ContainsKey($_)) { $tied[$_] } } | Sort-Object QuestID -Unique)
    $sameNamedHubs = @(if ($categoriesByKey.ContainsKey($key)) { $categoriesByKey[$key] | Where-Object { $hubs -contains $_ } })
    $elsewhere = @($quests | Where-Object { $categories -notcontains $_.Category -and $sameNamedHubs -notcontains $_.Category })
    $filedIn = 0; foreach ($c in $categories) { $filedIn += [int]$questsIn[$c] }
    foreach ($quest in $elsewhere) {
        $elsewhereRows.Add([PSCustomObject]@{ Expansion = $expansion; Instance = $instance.Name_lang; QuestID = $quest.QuestID; Name = $quest.Name; TiedBy = $quest.How; FiledIn = "$($quest.Category) $($categoryName[$quest.Category])"; InstanceCategory = ($categories | ForEach-Object { "$_ $($categoryName[$_])" }) -join "; " })
    }

    $issues = New-Object System.Collections.Generic.List[string]
    if (-not $categories.Count) { if ($elsewhere.Count) { $issues.Add("no category") } }
    elseif (-not $paths.Count) { if ($filedIn -or $quests.Count) { $issues.Add("not in the menu") } }
    elseif (-not $inDungeonMenu.Count) { $issues.Add("not under Dungeons & Raids > its expansion") }
    if ($elsewhere.Count) { $issues.Add("$($elsewhere.Count) tied quests filed elsewhere") }
    foreach ($c in $categories) {
        $shown = Get-ShownName $c
        if ($shown -cne $instance.Name_lang) { $issues.Add("category $c is shown as '$shown', the journal says '$($instance.Name_lang)'") }
    }

    $rows.Add([PSCustomObject]@{
        Expansion = $expansion
        Instance = $instance.Name_lang
        Kind = $kind
        JournalID = $id
        Categories = ($categories | ForEach-Object { "$_ $($categoryName[$_])" }) -join "; "
        MenuPaths = ($paths | Select-Object -Unique) -join "; "
        QuestsInCategory = $filedIn
        TiedQuests = $quests.Count
        FiledElsewhere = ($elsewhere | Group-Object Category | Sort-Object Count -Descending | ForEach-Object { "$($_.Name) $($categoryName[$_.Name]) x$($_.Count)" }) -join "; "
        Issues = $issues -join "; "
    })
}

# Categories under a Dungeons & Raids expansion submenu that aren't a journal instance of it.
$stray = New-Object System.Collections.Generic.List[string]
foreach ($category in $menuPaths.Keys) {
    foreach ($path in $menuPaths[$category]) {
        $m = [regex]::Match($path, "^$([regex]::Escape($dungeonsHeading)) > GetText\.EXPANSION_NAME(\d+)")
        if (-not $m.Success) { continue }
        if ($hubs -contains $category) { continue }
        $key = Get-Key $categoryName[$category]
        $match = @(if ($instanceKeys.ContainsKey($key)) { $instanceKeys[$key] | Where-Object { $expansionOf[$_] -eq [int]$m.Groups[1].Value } })
        if (-not $match.Count) { $stray.Add("expansion $($m.Groups[1].Value): $category $($categoryName[$category]) ($([int]$questsIn[$category]) quests)") }
    }
}

$rows | Export-Csv "$ToolsDir\dungeon_audit.csv" -NoTypeInformation -Encoding UTF8
$elsewhereRows | Export-Csv "$ToolsDir\dungeon_audit_quests.csv" -NoTypeInformation -Encoding UTF8
foreach ($group in ($rows | Group-Object Expansion | Sort-Object { [int]$_.Name })) {
    $withIssues = @($group.Group | Where-Object Issues)
    "Expansion $($group.Name): $($group.Count) instances, $($withIssues.Count) with issues"
    foreach ($row in $withIssues) { "  {0} ({1}): {2}" -f $row.Instance, $row.Kind, $row.Issues }
}
"In a Dungeons & Raids submenu but not a journal instance of that expansion: $($stray.Count)"
$stray | ForEach-Object { "  $_" }
"Written to $ToolsDir\dungeon_audit.csv, and the quests filed elsewhere to $ToolsDir\dungeon_audit_quests.csv"
