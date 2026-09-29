<#
One-off. Makes the quest categories that hold quests reachable from the menu.

qcMenu.lua:
  - 2 entries that named a category but carried no arg1 (so clicking them did nothing) are
    connected: Crystalsong Forest (417) and Old Hillsbrad Foothills (408).
  - 16 more such entries are removed: old raids whose category is empty or missing (Onyxia's
    Lair, Firelands, Dragon Soul, ...). A removed entry that closed its submenu hands its
    closing braces to the entry before it.
  - 21 entries are added, each just before a sibling already in the right submenu (the anchor
    must appear in the menu exactly once).

qcQuest.lua: a new category for The Coiled Isle (Midnight, UiMap 2512), named by the client via
qcCategoryUiMapID, and selected on entering it or the Vaults of Atal'Utek inside it (2509).

All-or-nothing: any anchor, removal or connection not found exactly as expected stops the run.
#>
param(
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist"
)

$menuFile = "$AddonDir\qcMenu.lua"
$questFile = "$AddonDir\qcQuest.lua"
$lines = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllText($menuFile, [System.Text.Encoding]::UTF8) -split "`r`n")

$connect = @{ "CRYSTALSONGFOREST" = 417; "OLDHILLSBRADFOOTHILLS" = 408 }
$remove = @("THEMAELSTROM", "ISLEOFGIANTS", "BLACKWINGLAIR", "THEBLACKMORASS", "SERPENTSHRINECAVERN",
    "GRUULSLAIR", "THEEYE", "THEVIOLETHOLD", "ONYXIASLAIR", "VAULTOFARCHAVON", "BARADINHOLD",
    "BLACKWINGDESCENT", "FIRELANDS", "DRAGONSOUL", "THEBASTIONOFTWILIGHT", "THRONEOFTHEFOURWINDS")
# new category -> an existing entry in the submenu it belongs in; the new entry goes just before it
$add = [ordered]@{
    238 = 221    # The Wandering Isle        -> Pandaria, beside The Jade Forest
    219 = 121    # The Halfhill Market       -> Pandaria, other categories
    208 = 121    # The Arboretum
    86 = 121     # Greenstone Village
    152 = 121    # Peak of Serenity
    1134 = 1133  # Death Rising              -> Miscellaneous, beside Visions of N'Zoth
    411 = 59     # The Deaths of Chromie     -> Northrend, beside Dragonblight
    40 = 29      # Coldarra                  -> Northrend, beside Borean Tundra
    20 = 7       # Battlegrounds             -> Player vs Player > Battlegrounds
    407 = 318    # Hellfire Citadel (raid)   -> Warlords of Draenor dungeons & raids
    53 = 245     # Deathknell                -> Lordaeron, beside Tirisfal Glades
    45 = 100     # Dalaran Crater            -> Lordaeron, beside Hillsbrad Foothills
    6 = 100      # Alterac Mountains
    1046 = 1006  # Helheim                   -> The Broken Isles, beside Stormheim
    1004 = 1001  # Eye of Azshara (zone)     -> The Broken Isles, beside Azsuna
    1049 = 1005  # Thunder Totem             -> The Broken Isles, beside Highmountain
    316 = 46     # Darkmoon Island           -> World Events, beside Darkmoon Faire
    68 = 140     # Echo Isles                -> Central Kalimdor, beside Mulgore
    419 = 1231   # Sinfall                   -> Shadowlands covenant sanctuaries
    295 = 70     # Northshire                -> Azeroth, beside Elwynn Forest
    195 = 194    # Stormwind Harbor          -> Azeroth, beside Stormwind City
    1513 = 1510  # The Coiled Isle (new)     -> Midnight, beside Zul'Aman
}
$entry = '{{isTitle=false,notCheckable=false,hasArrow=false,arg1={0},func=function(button,arg1)qcProcessMenuSelection(button,arg1);end}},'

function Find-Lines($pattern) {
    $found = @()
    for ($i = 0; $i -lt $lines.Count; $i++) { if (-not $lines[$i].StartsWith("--") -and $lines[$i] -match $pattern) { $found += $i } }
    return ,$found
}

foreach ($key in $connect.Keys) {
    $hit = Find-Lines "^\{text=qcL\.$key,isTitle=false,notCheckable=false,hasArrow=false,func="
    if ($hit.Count -ne 1) { throw "Expected one unconnected $key entry, found $($hit.Count)" }
    $lines[$hit[0]] = $lines[$hit[0]] -replace 'hasArrow=false,func=', "hasArrow=false,arg1=$($connect[$key]),func="
}

$removed = 0
foreach ($key in $remove) {
    $hit = Find-Lines "^\{text=qcL\.$key,isTitle=false,notCheckable=false,hasArrow=false,func="
    if ($hit.Count -ne 1) { throw "Expected one unconnected $key entry, found $($hit.Count)" }
    $i = $hit[0]
    $tail = [regex]::Match($lines[$i], 'end\}(\}+),?$')
    if ($tail.Success) {
        $prev = $i - 1
        if ($lines[$prev] -notmatch '^\{.*end\},$') { throw "$key closes its submenu but the entry before it isn't a plain entry: $($lines[$prev])" }
        $lines[$prev] = ($lines[$prev] -replace ',$', '') + $tail.Groups[1].Value + ","
    }
    $lines.RemoveAt($i)
    $removed++
}

$added = 0
# GetEnumerator, not $add[$id]: an integer index into an ordered dictionary is a position.
foreach ($pair in $add.GetEnumerator()) {
    $newId = $pair.Key; $anchorId = $pair.Value
    if ((Find-Lines "arg1=$newId,").Count) { throw "Category $newId already has a menu entry" }
    $anchor = Find-Lines "arg1=$anchorId,"
    if ($anchor.Count -ne 1) { throw "Anchor $anchorId for $newId appears $($anchor.Count) times in the menu" }
    $lines.Insert($anchor[0], ($entry -f $newId))
    $added++
}

# The Coiled Isle's category.
$quest = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)
if ($quest -match '\{1513,"') { throw "Category 1513 already exists" }
$quest = $quest.Replace('{1512,"Silvermoon City"},', '{1512,"Silvermoon City"},{1513,"The Coiled Isle"},')
if ($quest -notmatch '\{1513,"The Coiled Isle"\}') { throw "Could not add the category row" }
$uiBlock = [regex]::Match($quest, '(?sm)^qcCategoryUiMapID = \{.*?^\}')
$uiAnchor = [regex]::Match($uiBlock.Value, "(?m)^\t\[1512\]=2393,[^\r\n]*\r\n")
if (-not $uiAnchor.Success) { throw "qcCategoryUiMapID [1512] line not found" }
$insertAt = $uiBlock.Index + $uiAnchor.Index + $uiAnchor.Length
$quest = $quest.Insert($insertAt, "`t[1513]=2512,`t-- The Coiled Isle`r`n")
$zoneBlock = [regex]::Match($quest, '(?sm)^qcAreaIDToCategoryID=\{.*?^\}')
if ($zoneBlock.Value -match '\[(2509|2512)\]=') { throw "The Coiled Isle's maps are already mapped" }
$quest = $quest.Insert($zoneBlock.Index + $zoneBlock.Length - 1, "[2509]=1513,[2512]=1513,`r`n")

[System.IO.File]::WriteAllText($menuFile, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
[System.IO.File]::WriteAllText($questFile, $quest, (New-Object System.Text.UTF8Encoding $false))
"Menu: connected $($connect.Count), removed $removed, added $added entries"
"Added category 1513 The Coiled Isle (UiMap 2512; zone maps 2509, 2512)"
