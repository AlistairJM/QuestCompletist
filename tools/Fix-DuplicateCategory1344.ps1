<#
One-off. Category 1344 was defined twice in qcQuestCategories - "Amirdrassil, the Dream's Hope"
and "The Harbinger" - so every menu entry for it showed one name (whichever row the lookup met
last) and the two quest sets were mixed in one list.

  - Amirdrassil keeps 1344 with its 8 raid quests (zone text and Blizzard's API agree).
  - The Harbinger, the Xal'atath questline, moves to the free id 1348 with its 14 quests, listed
    below by id, and its menu entry follows.
  - Amirdrassil's translation key was misspelled AMIRDRASILTHEDREAMSHOPE (one S) in every locale
    file and the menu, while the addon looks up AMIRDRASSILTHEDREAMSHOPE, so the translation was
    never found. It is renamed, and the English text corrected.

All-or-nothing: every edit must find exactly what it expects.
#>
param(
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist"
)

$harbingerQuests = @(79009, 79010, 79011, 79012, 79013, 79014, 79015, 79016, 79017, 79018, 79019, 79020, 79021, 81654)

function Replace-Once($text, $old, $new, $where) {
    $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
    if ($count -ne 1) { throw "$where : expected '$old' once, found $count" }
    return $text.Replace($old, $new)
}

$questFile = "$AddonDir\qcQuest.lua"
$quest = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)
if ($quest -match '\{1348,"') { throw "Category 1348 is already in use" }
$quest = Replace-Once $quest '{1344,"The Harbinger"}' '{1348,"The Harbinger"}' "qcQuestCategories"
foreach ($questId in $harbingerQuests) {
    $pattern = "(?m)^(\[$questId\]=\{$questId,`"(?:[^`"\\]|\\.)*`",[^,]*,`"The Harbinger`",)1344,"
    $hits = [regex]::Matches($quest, $pattern).Count
    if ($hits -ne 1) { throw "Quest $questId is not a Harbinger quest in category 1344 ($hits matches)" }
    $quest = [regex]::Replace($quest, $pattern, '${1}1348,')
}
$left = [regex]::Matches($quest, '(?m)^\[\d+\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"The Harbinger",1344,').Count
if ($left) { throw "$left Harbinger quests are still in 1344" }

$menuFile = "$AddonDir\qcMenu.lua"
$menu = [System.IO.File]::ReadAllText($menuFile, [System.Text.Encoding]::UTF8)
$menu = Replace-Once $menu 'text=qcL.THEHARBINGER,isTitle=false,notCheckable=false,hasArrow=false,arg1=1344,' 'text=qcL.THEHARBINGER,isTitle=false,notCheckable=false,hasArrow=false,arg1=1348,' "qcMenu.lua"
$menu = Replace-Once $menu 'qcL.AMIRDRASILTHEDREAMSHOPE,' 'qcL.AMIRDRASSILTHEDREAMSHOPE,' "qcMenu.lua"

$locales = @{}
foreach ($file in Get-ChildItem "$AddonDir\Localization.*.lua") {
    $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    if ($text -match 'AMIRDRASSILTHEDREAMSHOPE') { throw "$($file.Name) already has the corrected key" }
    $line = [regex]::Matches($text, '(?m)^(\s*)AMIRDRASILTHEDREAMSHOPE(\s*=)')
    if ($line.Count -ne 1) { throw "$($file.Name): expected one AMIRDRASILTHEDREAMSHOPE line, found $($line.Count)" }
    $text = [regex]::Replace($text, '(?m)^(\s*)AMIRDRASILTHEDREAMSHOPE(\s*=)', '${1}AMIRDRASSILTHEDREAMSHOPE${2}')
    if ($file.Name -eq "Localization.enUS.lua") {
        $text = Replace-Once $text 'AMIRDRASSILTHEDREAMSHOPE = "Amirdrassil The Dreams Hope"' "AMIRDRASSILTHEDREAMSHOPE = `"Amirdrassil, the Dream's Hope`"" $file.Name
    }
    $locales[$file.FullName] = $text
}

$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($questFile, $quest, $utf8)
[System.IO.File]::WriteAllText($menuFile, $menu, $utf8)
foreach ($path in $locales.Keys) { [System.IO.File]::WriteAllText($path, $locales[$path], $utf8) }
"The Harbinger moved to 1348 with $($harbingerQuests.Count) quests; Amirdrassil keeps 1344"
"Renamed AMIRDRASILTHEDREAMSHOPE -> AMIRDRASSILTHEDREAMSHOPE in $($locales.Count) locale files and the menu"
