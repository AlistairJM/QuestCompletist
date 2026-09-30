<#
One-off (October 2026): names every dungeon and raid category exactly as the Dungeon Journal does,
and adds the ones that were missing. Found by Audit-DungeonCategories.ps1. Do not rerun.

  - Renames 9 categories to their journal names ("Sunken Temple" -> "The Temple of Atal'hakkar",
    "Tazavesh" -> "Tazavesh, the Veiled Market", ...). Dire Maul and Stratholme become one of their
    journal wings each.
  - Adds 16 categories: the other Dire Maul and Stratholme wings, Temple of Ahn'Qiraj and The Eye
    beside the Ahn'Qiraj and Tempest Keep hubs, Wrath's The Violet Hold, and the 10 Midnight
    dungeons and raids that have quests, in a new Midnight submenu under Dungeons & Raids.
  - Points each of those instances' floor maps (the journal's boss maps) at its category in
    qcAreaIDToCategoryID.
  - Moves the quests listed below, each with its evidence.
  - Adds a locale key for each new name, with the journal's own translation for every locale
    (wago.tools JournalInstance, per locale). Old keys are left in place.

Run Add-ZoneTableMaps, Build-CategoryUiMapIDs and Build-CategoryClientNames afterwards.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [string]$Build = "12.1.0.69933"
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$utf8 = New-Object System.Text.UTF8Encoding $false

# category -> journal instance
$renames = [ordered]@{
    "215" = "63"; "24" = "229"; "198" = "237"; "105" = "750"; "1047" = "945"; "1244" = "1194"; "1036" = "777"
    "58" = "230"; "197" = "236"
}
# new category -> journal instance, and the category it's listed after in the menu ("" = alphabetical)
$added = [ordered]@{
    "1736" = @("283", "260")    # The Violet Hold, after Utgarde Pinnacle (last Wrath dungeon)
    "1737" = @("744", "165")    # Temple of Ahn'Qiraj, after Ruins of Ahn'Qiraj
    "1738" = @("749", "200")    # The Eye, after Sunwell Plateau
    "1739" = @("1276", "1740")  # Dire Maul - Warpwood Quarter
    "1740" = @("1277", "58")    # Dire Maul - Gordok Commons
    "1741" = @("1292", "197")   # Stratholme - Service Entrance
    "1742" = @("1299", ""); "1743" = @("1300", ""); "1744" = @("1304", ""); "1745" = @("1307", "")
    "1746" = @("1309", ""); "1747" = @("1311", ""); "1748" = @("1313", ""); "1749" = @("1314", "")
    "1750" = @("1315", ""); "1751" = @("1316", "")
}
$midnight = @("1742", "1743", "1744", "1745", "1746", "1747", "1748", "1749", "1750", "1751")

# quest -> @(from, to); the comment is the evidence
$moves = [ordered]@{}
function Add-Move($to, $from, [string[]]$quests) { foreach ($q in $quests) { $moves[$q] = @($from, $to) } }
Add-Move "1739" "58" @("27103", "27104", "27105")                       # pins on floor 239 (Warpwood Quarter)
Add-Move "1739" "58" @("27108", "27107")                                # Lethtendris is a Warpwood boss; Pusillin has the same quest-giver
Add-Move "1739" "58" @("27129", "27130")                                # "the eastern wing of Dire Maul"
Add-Move "1740" "58" @("27118", "27119", "27120", "27128")              # pins on floor 235 (Gordok Commons)
Add-Move "1740" "58" @("27124", "27125", "77194")                       # the Gordok guards and king
Add-Move "1740" "58" @("27133", "27134")                                # "the Gordok ogres in the northern wing"
Add-Move "1741" "197" @("27227", "27228", "27230", "27352", "27359")    # pins on floor 318 (Service Entrance)
Add-Move "1736" "1003" @("29830")                                       # Containment: Wrath's Violet Hold, filed in Legion Dalaran
Add-Move "1738" "205" @("11007")                                        # pin on map 334, The Eye
Add-Move "1747" "1510" @("86681", "86682", "91958")                     # "Den of Nalorakk: ..."
Add-Move "1743" "1508" @("86543")                                       # "Magisters' Terrace: Homecoming", level 88
Add-Move "1750" "1510" @("91411", "92954", "93575")                     # "Maisara Caverns: ..."
Add-Move "1744" "1511" @("90818", "90819", "90821", "90835", "90837")   # "Murder Row: ..."
Add-Move "1744" "1512" @("90822")
Add-Move "1751" "1508" @("86521")                                       # "Nexus-Point Xenas: ..."
Add-Move "1746" "1512" @("93651")                                       # "The Blinding Vale: ..."
Add-Move "1749" "1502" @("90744")                                       # "The Dreamrift: ..."
Add-Move "1745" "1508" @("94475", "94476", "94477")                     # "The Voidspire: ..."
Add-Move "1748" "1508" @("91565", "91566", "91583", "91597", "91598", "91599", "91600", "91603", "91605", "91606", "94844", "94845", "94848", "94849", "94855")   # "Voidscar Arena: ..."
Add-Move "1748" "1150" @("91694")
Add-Move "1742" "1511" @("93850")                                       # "Windrunner Spire: ..."
Add-Move "1114" "1065" @("56348", "56349", "56351", "56352")            # "The Eternal Palace: ...", filed in Nazjatar
Add-Move "1029" "1050" @("43552", "44270", "44271")                     # "Eye of Azshara", in Legion Uncategorized
Add-Move "1100" "1082" @("49901")                                       # "Atal'Dazar: ...", in Zuldazar
Add-Move "1030" "1006" @("40615")                                       # "Halls of Valor: ...", in Stormheim
Add-Move "1033" "1007" @("45238")                                       # "Return to Karazhan: ...", in Suramar
Add-Move "1717" "1302" @("67081")                                       # "Halls of Infusion: ...", in Thaldraszus
Add-Move "1733" "1408" @("86204")                                       # "Liberation of Undermine: ...", in Undermine
Add-Move "1038" "1001" @("45176")                                       # "Trial of Valor: ...", in Azsuna
Add-Move "1510" "0" @("94531", "92897")                                 # Midnight's Zul'Aman zone (level 90), not the Cataclysm dungeon
Add-Move "173" "1150" @("57637")                                        # "Disturbance Detected: Firelands", beside its Blackrock Depths twin

$journal = @{}
foreach ($row in Import-Csv "$ToolsDir\JournalInstance.csv") { $journal[$row.ID] = $row.Name_lang }
$encounters = "$ToolsDir\JournalEncounter.csv"
if (-not (Test-Path $encounters)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/JournalEncounter/csv?build=$Build" -OutFile $encounters }
$bossMaps = @{}
foreach ($row in Import-Csv $encounters) { if ($row.UiMapID -ne "0") { $bossMaps[$row.JournalInstanceID] += @($row.UiMapID) } }
$locales = @("deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW")
$localized = @{}
foreach ($locale in $locales) {
    $file = "$ToolsDir\JournalInstance.$locale.csv"
    if (-not (Test-Path $file)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/JournalInstance/csv?build=$Build&locale=$locale" -OutFile $file }
    $localized[$locale] = @{}
    foreach ($row in Import-Csv $file) { $localized[$locale][$row.ID] = $row.Name_lang }
}

$categoryJournal = [ordered]@{}
foreach ($c in $renames.Keys) { $categoryJournal[$c] = $renames[$c] }
foreach ($c in $added.Keys) { $categoryJournal[$c] = $added[$c][0] }
function Get-LocaleKey($name) { return ($name -replace '[^A-Za-z0-9]', '').ToUpper() }

# qcQuest.lua: category rows, quest moves, zone table
$questFile = "$AddonDir\qcQuest.lua"
$content = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)
foreach ($c in $renames.Keys) {
    $pattern = "\{$c,`"(?:[^`"\\]|\\.)*`"\}"
    if ([regex]::Matches($content, $pattern).Count -ne 1) { throw "Category $c isn't defined exactly once" }
    $content = [regex]::Replace($content, $pattern, "{$c,`"$($journal[$renames[$c]] -replace '"', '\"')`"}")
}
$rows = ($added.Keys | ForEach-Object { "{$_,`"$($journal[$added[$_][0]] -replace '"', '\"')`"}" }) -join ","
if ([regex]::Matches($content, '\{1735,"Weekly Events"\}').Count -ne 1) { throw "Weekly Events row not found" }
$content = $content.Replace('{1735,"Weekly Events"}', '{1735,"Weekly Events"},' + $rows)

$entryPattern = '(?m)^(\[(\d+)\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",)(-?\d+),'
$moved = 0
$content = [regex]::Replace($content, $entryPattern, {
    param($m)
    $quest = $m.Groups[2].Value
    if (-not $moves.Contains($quest)) { return $m.Value }
    if ($m.Groups[3].Value -ne $moves[$quest][0]) { throw "Quest $quest is in category $($m.Groups[3].Value), expected $($moves[$quest][0])" }
    $script:moved++
    return $m.Groups[1].Value + $moves[$quest][1] + ","
})
if ($moved -ne $moves.Count) { throw "Moved $moved of $($moves.Count) quests" }

# Temple of Ahn'Qiraj: the hub's quests pinned inside the Temple
$templeMaps = @($bossMaps["744"])
$templeQuests = New-Object System.Collections.Generic.HashSet[string]
$currentMap = $null
foreach ($line in [System.IO.File]::ReadAllLines("$AddonDir\qcPinDB.lua")) {
    $header = [regex]::Match($line, '^\t\[(\d+)\] = \{')
    if ($header.Success) { $currentMap = $header.Groups[1].Value; continue }
    $pin = [regex]::Match($line, '\{([\d,]*)\}\},?\s*$')
    if ($pin.Success -and $templeMaps -contains $currentMap) { foreach ($q in ($pin.Groups[1].Value -split ',' | Where-Object { $_ })) { [void]$templeQuests.Add($q) } }
}
$temple = 0
$content = [regex]::Replace($content, $entryPattern, {
    param($m)
    if ($m.Groups[3].Value -eq "3" -and $templeQuests.Contains($m.Groups[2].Value)) { $script:temple++; return $m.Groups[1].Value + "1737," }
    return $m.Value
})

$table = [regex]::Match($content, '(?sm)^qcAreaIDToCategoryID=\{\r\n(.*?)^\}')
$tableText = $table.Groups[1].Value
$repointed = 0
$newEntries = New-Object System.Collections.Generic.List[string]
foreach ($c in $categoryJournal.Keys) {
    foreach ($map in ($bossMaps[$categoryJournal[$c]] | Select-Object -Unique)) {
        if ([regex]::IsMatch($tableText, "\[$map\]=-?\d+")) {
            $tableText = [regex]::Replace($tableText, "\[$map\]=-?\d+", "[$map]=$c"); $repointed++
        } else { $newEntries.Add("[$map]=$c,") }
    }
}
if ($newEntries.Count) { $tableText += ($newEntries -join "") + "`t-- Dungeon Journal boss maps`r`n" }
$content = $content.Substring(0, $table.Groups[1].Index) + $tableText + $content.Substring($table.Groups[1].Index + $table.Groups[1].Length)
[System.IO.File]::WriteAllText($questFile, $content, $utf8)

# qcMenu.lua
$menuFile = "$AddonDir\qcMenu.lua"
$lines = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllText($menuFile, [System.Text.Encoding]::UTF8) -split "`r`n")
function New-Entry($c) { return "{isTitle=false,notCheckable=false,hasArrow=false,arg1=$c,func=function(button,arg1)qcProcessMenuSelection(button,arg1);end}," }
function Find-Entry($c) {
    $found = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "arg1=$c,func=function\(button,arg1\)qcProcessMenuSelection") { $i } })
    if ($found.Count -ne 1) { throw "Menu entry for category $c found $($found.Count) times" }
    return $found[0]
}
function Insert-After($anchor, $c) {
    $i = Find-Entry $anchor
    $closers = [regex]::Match($lines[$i], 'end\}(\}*),?$').Groups[1].Value
    if ($closers) { $lines[$i] = $lines[$i] -replace "end\}$([regex]::Escape($closers)),?$", "end}," }
    $lines.Insert($i + 1, ((New-Entry $c) -replace ',$', "$closers,"))
}
$i = Find-Entry "198"; $lines[$i] = $lines[$i] -replace '^\{text=qcL\.SUNKENTEMPLE,', '{'
foreach ($c in "1740", "1739", "1741", "1737", "1738", "1736") { Insert-After $added[$c][1] $c }

# Classic dungeons stay alphabetical after the renames: sort the block before the raids.
$names = @{}
foreach ($m in [regex]::Matches($content, '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) { if (-not $names.ContainsKey($m.Groups[1].Value)) { $names[$m.Groups[1].Value] = $m.Groups[2].Value } }
$first = Find-Entry "21"; $last = Find-Entry "278"
$block = @($lines.GetRange($first, $last - $first + 1))
$sorted = $block | Sort-Object { $names[[regex]::Match($_, 'arg1=(\d+),').Groups[1].Value] }
for ($k = 0; $k -lt $sorted.Count; $k++) { $lines[$first + $k] = $sorted[$k] }

$dungeons = $lines.FindIndex([Predicate[string]]{ param($l) $l -match 'qcL\.DUNGEONSANDRAIDS' })
$tww = $lines.FindIndex($dungeons, [Predicate[string]]{ param($l) $l -match 'GetText\("EXPANSION_NAME10"\)' })
$twwLast = $lines.FindIndex($tww, [Predicate[string]]{ param($l) $l -match 'end\}\}\},$' })
if ($dungeons -lt 0 -or $tww -lt 0 -or $twwLast -lt 0) { throw "The War Within's Dungeons & Raids submenu wasn't found" }
$midnightLines = @('{text=stringformat("   %s",GetText("EXPANSION_NAME11")),isTitle=false,notCheckable=true,hasArrow=true,menuList={')
$ordered = $midnight | Sort-Object { $journal[$added[$_][0]] }
foreach ($c in $ordered) { $midnightLines += New-Entry $c }
$midnightLines[-1] = $midnightLines[-1] -replace ',$', '}},'
$lines.InsertRange($twwLast + 1, [string[]]$midnightLines)
[System.IO.File]::WriteAllText($menuFile, ($lines -join "`r`n"), $utf8)

# Locale keys with the journal's own names
foreach ($locale in @("enUS") + $locales) {
    $file = "$AddonDir\Localization.$locale.lua"
    $bytes = [System.IO.File]::ReadAllBytes($file)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF
    $text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($c in $categoryJournal.Keys) {
        $id = $categoryJournal[$c]
        $key = Get-LocaleKey $journal[$id]
        if ($keys.Contains($key) -or [regex]::IsMatch($text, "(?m)^\s*$key\s*=")) { continue }
        $value = if ($locale -eq "enUS") { $journal[$id] } else { $localized[$locale][$id] }
        if (-not $value) { throw "No $locale name for journal instance $id" }
        $keys.Add($key)
        $at = $text.LastIndexOf("`r`n`t}")
        if ($at -lt 0) { throw "No closing brace for qcLocalize in $file" }
        $text = $text.Insert($at, "`r`n`t$key = `"$($value -replace '"', '\"')`",")
    }
    [System.IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $bom))
}

"Renamed $($renames.Count) categories, added $($added.Count)"
"Moved $moved listed quests, and $temple of the Ahn'Qiraj hub's quests pinned inside the Temple"
"Zone table: $repointed maps repointed, $($newEntries.Count) added"
