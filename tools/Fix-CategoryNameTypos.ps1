<#
One-off. Corrects the spelling of 22 quest category names to the game's own, and removes the
menu entry for "Storm Fileds" (1507), a category with no quests and no map in the game.

The names were found by comparing every category against the client's map (UiMap) and dungeon
journal (JournalInstance) names, ignoring case and punctuation or allowing a letter or two:
backticks for apostrophes, trailing spaces, "Frehold", "Zul Aman", "High Mountain", and
capitalisation slips on categories the client already names ("StormHeim", "Vol'Dun").
Deliberate differences are left alone: class halls ("Skyhold (Warrior)"), "Nagrand - Draenor",
"Return to Karazhan", "Sunken Temple", "Maw of Souls".

Afterwards run Build-CategoryUiMapIDs.ps1, which links every category whose name now matches its
map exactly, then Remove-ConvertedLocaleKeys.ps1 for the translations that makes redundant.

All-or-nothing: every old name must be found exactly once.
#>
param(
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist"
)

$renames = @(
    @(1113, 'Battle of Dazar`alor', "Battle of Dazar'alor"),
    @(1102, 'Frehold', 'Freehold'),
    @(1503, 'Isle of Queldanas', "Isle of Quel'Danas"),
    @(1301, 'Ohn`ahran Plains', "Ohn'ahran Plains"),
    @(1233, 'Queen`s Conservatory', "Queen's Conservatory"),
    @(405, 'Silvershard Mines ', 'Silvershard Mines'),
    @(406, 'Temple of Kotmogu ', 'Temple of Kotmogu'),
    @(403, 'The Battle of Gilneas', 'The Battle for Gilneas'),
    @(1112, 'The Motherload!!', 'The MOTHERLODE!!'),
    @(1510, 'Zul Aman', "Zul'Aman"),
    @(1005, 'High Mountain', 'Highmountain'),
    @(211, 'The Black Temple', 'Black Temple'),
    @(1344, 'Amirdrassil The Dreams Hope', "Amirdrassil, the Dream's Hope"),
    @(1115, "Ny'alotha, The Waking City", "Ny'alotha, the Waking City"),
    @(429, 'Acherus The Ebon Hold', 'Acherus: The Ebon Hold'),
    @(411, 'The Deaths Of Chromie', 'The Deaths of Chromie'),
    @(412, 'Terrace Of Endless Spring', 'Terrace of Endless Spring'),
    @(1006, 'StormHeim', 'Stormheim'),
    @(1047, 'The Seat of The Triumvirate', 'The Seat of the Triumvirate'),
    @(1064, 'Chamber Of Heart', 'Chamber of Heart'),
    @(1081, "Vol'Dun", "Vol'dun"),
    @(1105, 'Siege Of Boralus', 'Siege of Boralus')
)

$questFile = "$AddonDir\qcQuest.lua"
$quest = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)
foreach ($r in $renames) {
    $old = '{' + $r[0] + ',"' + $r[1] + '"}'
    $new = '{' + $r[0] + ',"' + $r[2] + '"}'
    $count = ([regex]::Matches($quest, [regex]::Escape($old))).Count
    if ($count -ne 1) { throw "Expected '$old' once in qcQuestCategories, found $count" }
    $quest = $quest.Replace($old, $new)
}

$menuFile = "$AddonDir\qcMenu.lua"
$lines = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllText($menuFile, [System.Text.Encoding]::UTF8) -split "`r`n")
$storm = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\{text=qcL\.STORMFILEDS,.*arg1=1507,.*end\},$') { $i } })
if ($storm.Count -ne 1) { throw "Expected one plain Storm Fileds entry, found $($storm.Count)" }
$lines.RemoveAt($storm[0])

[System.IO.File]::WriteAllText($questFile, $quest, (New-Object System.Text.UTF8Encoding $false))
[System.IO.File]::WriteAllText($menuFile, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
"Renamed $($renames.Count) categories; removed the Storm Fileds menu entry"
