<#
One-off. Tidies the menu before the catch-all categories are refiled:

  - Removes the "Class Campains" submenu, an exact copy of "Classes", and the "Island
    Expeditions" submenu, which listed seven Kalimdor zones that have entries of their own.
  - Removes the "Whaler's Nook" entry, which pointed at Azerothian Archives (1343), so Azerothian
    Archives was listed twice. The two headings' translations and Whaler's Nook's go with them.
  - Restores the commented-out First Aid entry; its 4 quests had no other way in.
  - Adds a Prey category (1514) under Midnight, for the Prey hunts that sit in Bfa Unknown.
  - Adds the closing bracket missing from "Acherus: The Ebon Hold (Death Knight".
  - Moves 16 quests whose Blizzard API area names a category with no quests, or no menu entry:
    listed below with the category each is expected to be in now.

Run Place-UncategorisedQuests.ps1 -Refile 1150,1050 afterwards, then Remove-EmptyMenuEntries.ps1.

All-or-nothing: every edit must find exactly what it expects.
#>
param(
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist"
)

$questMoves = @(
    @(40717, 44, 1003),   # Calling of the Council: "Dalaran City", which has no menu entry
    @(39107, 296, 164),   # An Even Bigga Score: "Pickpocketing", which has no menu entry
    @(47654, 1044, 1047), @(48231, 1041, 1047),
    @(88977, 1508, 1509), @(88978, 1508, 1509), @(88979, 1508, 1509), @(90544, 1508, 1509),
    @(89016, 1408, 1733), @(89018, 1408, 1733), @(89024, 1408, 1733), @(89027, 1408, 1733),
    @(89252, 1408, 1733), @(89351, 1408, 1733), @(89352, 1408, 1733), @(89353, 1408, 1733)
)

function Replace-Once($text, $old, $new, $where) {
    $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
    if ($count -ne 1) { throw "$where : expected '$old' once, found $count" }
    return $text.Replace($old, $new)
}

$utf8 = New-Object System.Text.UTF8Encoding $false

$questFile = "$AddonDir\qcQuest.lua"
$quest = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)
if ($quest -match '\{1514,"') { throw "Category 1514 is already in use" }
$quest = Replace-Once $quest '{1513,"The Coiled Isle"},' '{1513,"The Coiled Isle"},{1514,"Prey"},' "qcQuestCategories"
$quest = Replace-Once $quest '{1021,"Acherus: The Ebon Hold (Death Knight"}' '{1021,"Acherus: The Ebon Hold (Death Knight)"}' "qcQuestCategories"
foreach ($move in $questMoves) {
    $pattern = "(?m)^(\[$($move[0])\]=\{$($move[0]),`"(?:[^`"\\]|\\.)*`",[^,]*,`"(?:[^`"\\]|\\.)*`",)$($move[1]),"
    $hits = [regex]::Matches($quest, $pattern).Count
    if ($hits -ne 1) { throw "Quest $($move[0]) is not in category $($move[1]) ($hits matches)" }
    $quest = [regex]::Replace($quest, $pattern, "`${1}$($move[2]),")
}

$menuFile = "$AddonDir\qcMenu.lua"
$lines = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllText($menuFile, [System.Text.Encoding]::UTF8) -split "`r`n")

function Find-Line($pattern) {
    $found = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { $i } })
    if ($found.Count -ne 1) { throw "Expected one menu line matching $pattern, found $($found.Count)" }
    return $found[0]
}

# A submenu runs from its heading to the entry that closes it with "end}}},".
foreach ($heading in @('qcL\.CLASSCAMPAINS\),', 'qcL\.ISLANDEXPEDITIONS\),')) {
    $start = Find-Line $heading
    $end = $start + 1
    while ($lines[$end] -notmatch ';end\}\}\},$') {
        if ($lines[$end] -notmatch '^\{text=.*arg1=\d+,func=.*;end\},$|^\{isTitle=false,.*arg1=\d+,func=.*;end\},$') { throw "Unexpected line in submenu $heading : $($lines[$end])" }
        $end++
    }
    $lines.RemoveRange($start, $end - $start + 1)
}

$whaler = Find-Line '^\{text=qcL\.WHALLERSNOOK,.*arg1=1343,.*;end\}(\}+),$'
$closers = [regex]::Match($lines[$whaler], ';end\}(\}+),$').Groups[1].Value
if ($lines[$whaler - 1] -notmatch ';end\},$') { throw "The entry before Whaler's Nook doesn't end a plain entry" }
$lines[$whaler - 1] = $lines[$whaler - 1] -replace ',$', "$closers,"
$lines.RemoveAt($whaler)

$firstAid = Find-Line '^--\{text=qcL\.FIRSTAID,.*arg1=79,'
$lines[$firstAid] = $lines[$firstAid].Substring(2)

$neighborhood = Find-Line '^\{text=qcL\.NEIGHBORHOOD,.*arg1=1504,'
$lines.Insert($neighborhood, '{isTitle=false,notCheckable=false,hasArrow=false,arg1=1514,func=function(button,arg1)qcProcessMenuSelection(button,arg1);end},')

$menu = $lines -join "`r`n"
foreach ($key in @('CLASSCAMPAINS', 'WHALLERSNOOK')) { if ($menu -match "qcL\.$key\b") { throw "qcL.$key is still used in the menu" } }

$locales = @{}
foreach ($file in Get-ChildItem "$AddonDir\Localization.*.lua") {
    $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    foreach ($key in @('CLASSCAMPAINS', 'WHALLERSNOOK')) {
        $pattern = "(?m)^\s*$key\s*=.*\r\n"
        $count = [regex]::Matches($text, $pattern).Count
        if ($count -ne 1) { throw "$($file.Name): expected one $key line, found $count" }
        $text = [regex]::Replace($text, $pattern, "")
    }
    $locales[$file.FullName] = $text
}

[System.IO.File]::WriteAllText($questFile, $quest, $utf8)
[System.IO.File]::WriteAllText($menuFile, $menu, $utf8)
foreach ($path in $locales.Keys) { [System.IO.File]::WriteAllText($path, $locales[$path], $utf8) }
"Removed the Class Campains and Island Expeditions submenus and the Whaler's Nook entry; restored First Aid; added Prey (1514)"
"Moved $($questMoves.Count) quests; removed 2 translations from $($locales.Count) locale files"
