<#
Gives the Shadowlands, Dragonflight and War Within dungeons and raids categories of their own, the
way every earlier expansion already has them, and moves the quests that belong to them out of the
"Bfa Unknown" catch-all.

The instance list per expansion comes from the game's own Dungeon Journal tables (JournalTier,
JournalInstance, JournalTierXInstance on wago.tools), so it matches what players see in-game. Each
new category is mapped to its UiMap id in qcCategoryUiMapID, so its name comes from the client and
needs no translating.

Quests are matched to an instance by name: a quest sitting in the catch-all whose zone is "Dungeon"
and whose title names an instance ("Necrotic Wake: A Paragon's Plight") moves to that instance's
category. Anything that doesn't match is left where it is.

All-or-nothing: any category id collision, missing anchor or failed rewrite stops the run.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [switch]$Refresh
)

$ProgressPreference = "SilentlyContinue"
foreach ($t in "JournalTier", "JournalInstance", "JournalTierXInstance", "UiMap") {
    $path = "$ToolsDir\$t.csv"
    if ($Refresh -or -not (Test-Path $path)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$t/csv" -OutFile $path; Start-Sleep -Milliseconds 300 }
}

$instances = @{}
Import-Csv "$ToolsDir\JournalInstance.csv" | ForEach-Object { $instances[$_.ID] = $_ }
$uiByName = @{}
Import-Csv "$ToolsDir\UiMap.csv" | ForEach-Object { if (-not $uiByName.ContainsKey($_.Name_lang)) { $uiByName[$_.Name_lang] = $_.ID } }
$links = Import-Csv "$ToolsDir\JournalTierXInstance.csv"

# The tier's own overworld container isn't a dungeon.
$notInstances = @("Shadowlands", "Dragon Isles", "Khaz Algar")
$tiers = @(
    @{ Id = 499; Name = "Shadowlands";    Expansion = "EXPANSION_NAME8" }
    @{ Id = 503; Name = "Dragonflight";   Expansion = "EXPANSION_NAME9" }
    @{ Id = 514; Name = "The War Within"; Expansion = "EXPANSION_NAME10" }
)

$questFile = "$AddonDir\qcQuest.lua"
$content = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)

$categoryBlock = [regex]::Match($content, '(?sm)^qcQuestCategories=\{(.*?)^\}')
$categoriesByName = @{}
$usedIds = @{}
foreach ($m in [regex]::Matches($categoryBlock.Groups[1].Value, '\{(\d+),"((?:[^"\\]|\\.)*)"\}')) {
    $usedIds[[int]$m.Groups[1].Value] = $true
    if (-not $categoriesByName.ContainsKey($m.Groups[2].Value)) { $categoriesByName[$m.Groups[2].Value] = [int]$m.Groups[1].Value }
}
$nextId = (($usedIds.Keys | Measure-Object -Maximum).Maximum) + 1

function Get-NameKey($s) { return (($s -replace "^[Tt]he ", "") -replace "[^A-Za-z0-9]", "").ToLower() }

# An instance we already have a category for keeps it and still gets a menu entry. Matching is on
# the exact name: "Uldaman" is the classic dungeon, not Dragonflight's "Uldaman: Legacy of Tyr",
# and "Amirdrassil" is the zone, not the raid. Where our name is genuinely the same instance under
# a shorter title, it is listed here rather than guessed at.
$aliases = @{ "Tazavesh, the Veiled Market" = "Tazavesh" }
$existingByKey = @{}
foreach ($pair in $categoriesByName.GetEnumerator()) { $existingByKey[(Get-NameKey $pair.Key)] = $pair.Value }

$plan = New-Object System.Collections.Generic.List[object]
foreach ($tier in $tiers) {
    foreach ($link in ($links | Where-Object { $_.JournalTierID -eq "$($tier.Id)" } | Sort-Object { [int]$_.OrderIndex })) {
        $instance = $instances[$link.JournalInstanceID]
        if (-not $instance) { continue }
        $name = $instance.Name_lang
        if ($notInstances -contains $name) { continue }
        if ($plan | Where-Object { $_.Name -eq $name }) { continue }

        $lookup = if ($aliases.ContainsKey($name)) { $aliases[$name] } else { $name }
        $existingId = $existingByKey[(Get-NameKey $lookup)]

        if ($existingId) {
            $plan.Add([PSCustomObject]@{ Name = $name; Expansion = $tier.Expansion; Tier = $tier.Name; CategoryId = $existingId; UiMapId = $null; IsNew = $false })
        } else {
            $plan.Add([PSCustomObject]@{ Name = $name; Expansion = $tier.Expansion; Tier = $tier.Name; CategoryId = $nextId; UiMapId = $uiByName[$name]; IsNew = $true })
            $nextId++
        }
    }
}
$reused = @($plan | Where-Object { -not $_.IsNew })
"Instances in the menu: $($plan.Count)   reusing an existing category: $($reused.Count)"
$reused | ForEach-Object { "  $($_.Name) -> category $($_.CategoryId)" }
$newOnes = @($plan | Where-Object { $_.IsNew })
"Categories to add: $($newOnes.Count)"
$newOnes | Group-Object Tier | ForEach-Object { "  $($_.Name): $($_.Count)" }
$noMap = @($newOnes | Where-Object { -not $_.UiMapId })
if ($noMap.Count) { "  without a UiMap (keep our own name): $(($noMap.Name) -join ', ')" }

# Which quests should move: in the catch-all, zone "Dungeon", title naming an instance.
function Get-MatchKey($s) { return (($s -replace "^[Tt]he ", "") -replace "[^A-Za-z0-9]", "").ToLower() }
$moves = @{}
$questLines = [regex]::Matches($content, '(?m)^\[(\d+)\]=\{\d+,"((?:[^"\\]|\\.)*)",[^,]*,"((?:[^"\\]|\\.)*)",(\d+),(\d+),')
$currentType = @{}
foreach ($m in $questLines) { $currentType[$m.Groups[1].Value] = $m.Groups[5].Value }
foreach ($m in $questLines) {
    if ($m.Groups[4].Value -ne "1150") { continue }
    $zone = $m.Groups[3].Value
    $title = $m.Groups[2].Value
    if ($zone -ne "Dungeon" -and -not ($plan | Where-Object { $_.Name -eq $zone })) { continue }
    $titleKey = Get-MatchKey $title
    $best = $null
    foreach ($entry in $plan) {
        $key = Get-MatchKey $entry.Name
        if ($key.Length -ge 6 -and $titleKey.StartsWith($key)) {
            if (-not $best -or $key.Length -gt (Get-MatchKey $best.Name).Length) { $best = $entry }
        }
    }
    if ($best) { $moves[$m.Groups[1].Value] = $best }
}
"Quests moving out of the catch-all: $($moves.Count)"
$moves.Values | Group-Object Name | Sort-Object Count -Descending | ForEach-Object { "  $($_.Name): $($_.Count)" }

if (-not $newOnes.Count) { throw "Nothing to add" }

# 1. New category rows, appended before the closing brace of qcQuestCategories.
$newRows = ($newOnes | ForEach-Object { "{$($_.CategoryId),`"$($_.Name)`"}" }) -join ","
# The block match ends on its closing brace; insert whole lines immediately before it.
$insertAt = $categoryBlock.Index + $categoryBlock.Length - 1
$content = $content.Substring(0, $insertAt) + $newRows + ",`r`n" + $content.Substring($insertAt)

# 2. UiMap ids so the client names them.
$mapBlock = [regex]::Match($content, '(?sm)^qcCategoryUiMapID = \{(.*?)^\}')
if (-not $mapBlock.Success) { throw "qcCategoryUiMapID not found - run Build-CategoryUiMapIDs.ps1 first" }
$mapRows = (($newOnes | Where-Object { $_.UiMapId } | ForEach-Object { "`t[$($_.CategoryId)]=$($_.UiMapId),`t-- $($_.Name)" }) -join "`r`n") + "`r`n"
$mapInsertAt = $mapBlock.Index + $mapBlock.Length - 1
$content = $content.Substring(0, $mapInsertAt) + $mapRows + $content.Substring($mapInsertAt)

# 3. Move the matched quests into their instance's category.
$moved = 0
$content = [regex]::Replace($content, '(?m)^(\[(\d+)\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",)1150,', {
    param($m)
    $target = $moves[$m.Groups[2].Value]
    if ($target) { $script:moved++; return $m.Groups[1].Value + "$($target.CategoryId)," }
    return $m.Value
})
if ($moved -ne $moves.Count) { throw "Expected to move $($moves.Count) quests, moved $moved" }

# 3b. Most of those quests are typed 128, "world quest", which hides them whenever the world-quest
# filter is on - so a dungeon category would look empty while its counter showed a total. They are
# not world quests: Blizzard's API calls them Dungeon or Raid and the client's task-quest table
# (QuestV2CliTask) has no row for them. Retype those to 1, an ordinary quest.
$taskQuests = @{}
if (Test-Path "$ToolsDir\QuestV2CliTask.csv") {
    Get-Content "$ToolsDir\QuestV2CliTask.csv" | Select-Object -Skip 1 | ForEach-Object { $taskQuests[$_.Split(",")[0]] = $true }
} else { throw "QuestV2CliTask.csv missing - needed to tell a real world quest from a mistyped one" }

$retype = @{}
foreach ($questId in $moves.Keys) {
    if ($currentType[$questId] -ne "128") { continue }
    if ($taskQuests.ContainsKey($questId)) { continue }
    $cached = "$ToolsDir\quest_api_cache\$questId.json"
    if (-not (Test-Path $cached)) { continue }
    $apiType = [regex]::Match([System.IO.File]::ReadAllText($cached), '"type":\{.*?"name":"([^"]+)"')
    if ($apiType.Success -and $apiType.Groups[1].Value -match '^(Dungeon|Raid|Group)') { $retype[$questId] = $apiType.Groups[1].Value }
}
$retyped = 0
$content = [regex]::Replace($content, '(?m)^(\[(\d+)\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",\d+,)128,', {
    param($m)
    if ($retype.ContainsKey($m.Groups[2].Value)) { $script:retyped++; return $m.Groups[1].Value + "1," }
    return $m.Value
})
if ($retyped -ne $retype.Count) { throw "Expected to retype $($retype.Count) quests, retyped $retyped" }
"Quests retyped from world quest to normal: $retyped"
$retype.Values | Group-Object | ForEach-Object { "  API says $($_.Name): $($_.Count)" }

[System.IO.File]::WriteAllText($questFile, $content, (New-Object System.Text.UTF8Encoding $false))

# 4. Menu rows, restored under Dungeons & Raids in the same shape as the other expansions.
$menuFile = "$AddonDir\qcMenu.lua"
$menu = [System.IO.File]::ReadAllText($menuFile, [System.Text.Encoding]::UTF8)
$menuLines = $menu -split "`r`n"
$anchorIndex = -1
for ($i = 0; $i -lt $menuLines.Count; $i++) { if ($menuLines[$i] -match 'GetText\("EXPANSION_NAME7"\)') { $anchorIndex = $i } }
if ($anchorIndex -lt 0) { throw "EXPANSION_NAME7 row not found in the menu" }
# That row ends where its submenu closes.
$end = $anchorIndex
while ($end -lt $menuLines.Count -and $menuLines[$end] -notmatch '\}\}\},?$') { $end++ }
if ($end -ge $menuLines.Count) { throw "Could not find the end of the EXPANSION_NAME7 submenu" }

$block = New-Object System.Collections.Generic.List[string]
foreach ($tier in $tiers) {
    $entries = @($plan | Where-Object { $_.Expansion -eq $tier.Expansion } | Sort-Object Name)
    if (-not $entries.Count) { continue }
    $block.Add("{text=stringformat(`"   %s`",GetText(`"$($tier.Expansion)`")),isTitle=false,notCheckable=true,hasArrow=true,menuList={")
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $close = if ($i -eq $entries.Count - 1) { "}}}," } else { "}," }
        $block.Add("{isTitle=false,notCheckable=false,hasArrow=false,arg1=$($entries[$i].CategoryId),func=function(button,arg1)qcProcessMenuSelection(button,arg1);end$close")
    }
}
$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $menuLines.Count; $i++) {
    $out.Add($menuLines[$i])
    if ($i -eq $end) { foreach ($l in $block) { $out.Add($l) } }
}
[System.IO.File]::WriteAllText($menuFile, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
"Menu rows added: $(@($tiers | Where-Object { $plan.Expansion -contains $_.Expansion }).Count), entries: $($block.Count - 3)"
