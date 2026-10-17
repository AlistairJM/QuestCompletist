<#
Checks EntrancePins.ps1, the entrance pins of AddonData.ps1 and Sync-EntrancePins.ps1 (step 6f) on made-up client tables
and data folders in a temporary folder: nothing in the checkout is touched and nothing is downloaded. It checks the name
key, the category tables read from qcQuest.lua, where a world position lands (one zone, the entrance's area or one above
it, several zones, none, the map a phased copy stands for), which journal instances and Forever maps count, the decisions
file, the quests an entrance lists (pinned, no-pin task kinds, unavailable, a side's door), the game's own places (read
from a made-up probe file, by journal instance and by name, winning over the doors, two instances on one category), the
data file's checks and the build (a quest a pin gains since, the icons, the header), a run on retail (no probe, a held
door, its SHOW row, the game's place, a second run, stale rows) and one on WoW: Forever (corpse points, a door several
zones hold though retail's area would choose, then a place its game draws).

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncEntrancePins.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
. (Join-Path $PSScriptRoot 'EntrancePins.ps1')
. (Join-Path $PSScriptRoot 'ProbeResults.ps1')
$Tool = Join-Path $PSScriptRoot 'Sync-EntrancePins.ps1'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Throws([scriptblock]$block, [string]$text, [string]$message) {
    try { & $block; Check $false "$message (no error)" } catch { Check ($_.Exception.Message -like "*$text*") "$message ($($_.Exception.Message))" }
}

# A world map 0 with a continent over two zones: Zone A (UiMap 10, area 50) covers x -1000 to 0, Zone B (UiMap 11, area
# 60, Sub B 501 under it) x -500 to 500, both y -1000 to 1000. Map 2 is a phased copy of map 0 (ParentMapID), map 3 one by
# CosmeticParentMapID.
function Csv($header, $rows) { return ($header + "`r`n" + (($rows | ForEach-Object { $_ -join ',' }) -join "`r`n") + "`r`n") }
$UiMapCsv = Csv 'ID,Name_lang,Type' @(@(1, 'Continent', 2), @(10, 'Zone A', 3), @(11, 'Zone B', 3))
$AssignCsv = Csv 'UiMapID,MapID,AreaID,Region_0,Region_1,Region_3,Region_4,UiMin_0,UiMin_1,UiMax_0,UiMax_1' @(
    @(1, 0, 0, -2000, -2000, 2000, 2000, 0, 0, 1, 1), @(10, 0, 50, -1000, -1000, 0, 1000, 0, 0, 1, 1), @(11, 0, 60, -500, -1000, 500, 1000, 0, 0, 1, 1))
$AreaCsv = Csv 'ID,AreaName_lang,ParentAreaID' @(@(50, 'Zone A', 0), @(60, 'Zone B', 0), @(501, 'Sub B', 60))
function MapRow($id, $name, $type, $area = 0, $parent = -1, $cosmetic = -1, $corpseMap = -1, $cx = 0, $cy = 0) {
    return @($id, $name, $type, $area, $parent, $cosmetic, $corpseMap, $cx, $cy)
}
$MapHeader = 'ID,MapName_lang,InstanceType,AreaTableID,ParentMapID,CosmeticParentMapID,CorpseMapID,Corpse_0,Corpse_1'

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("entrance-pins-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null
try {
    # A. The module
    Equal (Get-InstanceKey 'The Deep Halls') (Get-InstanceKey "Deep-Halls") 'A1: a leading "The", case and punctuation are ignored'
    Equal (Get-InstanceKey "Ahn'Qiraj Temple") 'ahnqirajtemple' 'A1: the key of a name'
    $lua = Join-Path $Scratch 'qcQuest.lua'
    [IO.File]::WriteAllText($lua, "qcQuestCategories={`r`n{5,`"First`"},`r`n{5,`"Again`"},`r`n{-7,`"Neg \`"q\`"`"},`r`n}`r`nqcCategoryUiMapID={}`r`nqcCategoryClientName={`r`n[9]=12,`r`n}`r`n")
    $names = Read-QuestCategoryNames $lua
    Equal "$($names[5])|$($names[-7])|$($names.Count)" 'First|Neg \"q\"|2' 'A2: the categories, the first row of an ID winning'
    Equal (Read-CategoryUiMapIds $lua).Count 0 'A2: an empty qcCategoryUiMapID on one line reads as empty, not the next table'
    [IO.File]::WriteAllText($lua, "qcCategoryUiMapID = {  -- CategoryId -> UiMapId`r`n`t[902]=10,`t-- Zone Hall`r`n`t[3] = 11,`r`n}`r`n")
    $ui = Read-CategoryUiMapIds $lua
    Equal "$($ui[902]),$($ui[3])" '10,11' 'A2: the category maps, spaced or not'

    $mapRows = (Csv $MapHeader @((MapRow 0 'World' 0), (MapRow 2 'Phase' 0 0 0), (MapRow 3 'Cosmetic' 0 0 -1 0), (MapRow 4 'Lone' 0))) | ConvertFrom-Csv
    $locator = New-ZoneLocator $mapRows ($UiMapCsv | ConvertFrom-Csv) ($AssignCsv | ConvertFrom-Csv) ($AreaCsv | ConvertFrom-Csv)
    $p = ConvertTo-ZonePoint $locator 0 -800 0 0
    Equal "$($p.How) $($p.UiMap) $($p.X),$($p.Y)" 'box 10 50,80' 'A3: a point one zone holds goes on it, the continent left out'
    $p = ConvertTo-ZonePoint $locator 0 -200 500 0
    Equal "$($p.How) $($p.UiMap) $(($p.Zones | ForEach-Object { "$($_.UiMap) $($_.X),$($_.Y)" }) -join '; ')" 'several 0 10 25,20; 11 25,70' 'A3: two zones and no area: held, with both places'
    $p = ConvertTo-ZonePoint $locator 0 -200 500 501
    Equal "$($p.How) $($p.UiMap) $($p.X),$($p.Y)" 'area 11 25,70' 'A3: the area under a zone chooses it'
    $p = ConvertTo-ZonePoint $locator 0 -200 500 50
    Equal "$($p.How) $($p.UiMap)" 'area 10' 'A3: the area of the other zone chooses that one'
    $p = ConvertTo-ZonePoint $locator 0 -800 0 60
    Equal "$($p.How) $($p.UiMap)" 'box 10' 'A3: an area no zone holding the point has leaves the one zone'
    $p = ConvertTo-ZonePoint $locator 0 5000 0 0
    Equal "$($p.How) $($p.UiMap) $($p.Zones.Count)" 'none 0 0' 'A3: a point no zone holds: held'
    $p = ConvertTo-ZonePoint $locator 2 -800 0 0
    Equal "$($p.How) $($p.UiMap) $($p.X),$($p.Y)" 'box 10 50,80' 'A3: a phased copy is placed on the map it is a copy of (ParentMapID)'
    $p = ConvertTo-ZonePoint $locator 3 -800 0 0
    Equal "$($p.How) $($p.UiMap)" 'box 10' 'A3: and by CosmeticParentMapID'
    $p = ConvertTo-ZonePoint $locator 4 -800 0 0
    Equal $p.How 'none' 'A3: a map with no zone and no parent: held'

    $journal = (Csv 'ID,Name_lang,MapID,Flags' @(@(1, 'The Deep Halls', 100, 0), @(2, 'Deep Vault', 101, 0), @(3, 'Sky Spire', 102, 0), @(4, 'Zone Hall', 103, 0),
        @(5, 'Boss Field', 104, 2), @(6, 'Open Plaza', 105, 0), @(7, 'Two Doors', 106, 0), @(8, 'Lost Keep', 107, 0), @(9, 'Nobody', 108, 0))) | ConvertFrom-Csv
    $entrances = (Csv 'ID,Position_0,Position_1,Position_2,MapID,AreaTableID,Faction,JournalInstanceID' @(
        @(11, -800, 0, 0, 0, 0, -1, 1), @(12, -200, 500, 0, 2, 501, -1, 3), @(13, -800, 0, 0, 0, 0, 1, 7), @(14, -200, 500, 0, 0, 0, 0, 7), @(15, -800, 0, 0, 0, 0, -1, 2))) | ConvertFrom-Csv
    $instanceMaps = (Csv $MapHeader @((MapRow 100 'a' 1), (MapRow 101 'b' 1), (MapRow 102 'c' 2), (MapRow 103 'd' 1), (MapRow 104 'e' 1), (MapRow 105 'f' 0), (MapRow 106 'g' 1), (MapRow 107 'h' 1), (MapRow 108 'i' 1))) | ConvertFrom-Csv
    $cats = @{ 70 = 'Elwynn Forest'; 900 = 'Deep Halls'; 3 = 'Deep Vault'; 901 = 'Sky Spire'; 902 = 'Zone Hall'; 903 = 'Boss Field'; 904 = 'Open Plaza'; 905 = 'Two Doors'; 906 = 'Lost Keep'; 907 = 'The Lost Keep' }
    $retail = @(Get-RetailInstances $journal $entrances $instanceMaps $cats @{ 902 = 10 } ($UiMapCsv | ConvertFrom-Csv))
    Equal (($retail | ForEach-Object { "$($_.Name):$($_.Kind):$($_.Categories -join '+'):$(@($_.Doors).Count)" }) -join '; ') 'The Deep Halls:dungeon:900:1; Sky Spire:raid:901:1; Two Doors:dungeon:905:2; Lost Keep:dungeon:906+907:0' 'A4: the journal instances that count, their kinds, categories and doors: not a hub, a zone, a world boss, an open map or one no category names'
    Equal ((@($retail[2].Doors) | ForEach-Object { "$($_.Door) side $($_.Side) hint $($_.Hint)" }) -join '; ') '13 side 1 hint 0; 14 side 2 hint 0' 'A4: an entrance of faction 1 is the Alliance''s, of 0 the Horde''s'
    Equal "$($retail[1].Doors[0].Area) $($retail[1].Doors[0].Hint)" '501 501' 'A4: a retail entrance''s area is its own'

    $foreverMaps = (Csv $MapHeader @((MapRow 300 'Old Cave' 1 2000 -1 -1 0 -800 0), (MapRow 301 'Fire Pit' 2 2001 -1 -1 0 -200 500), (MapRow 302 'No Door' 1 2002),
        (MapRow 303 'Not Ours' 1 2999 -1 -1 0 -800 0), (MapRow 304 'Open' 0 2000 -1 -1 0 -800 0))) | ConvertFrom-Csv
    $retailJournal = (Csv 'ID,Name_lang,MapID,Flags' @(, @(9, 'The Fire Pit', 1, 0))) | ConvertFrom-Csv
    $retailDoors = (Csv 'ID,Position_0,Position_1,Position_2,MapID,AreaTableID,Faction,JournalInstanceID' @(, @(20, 0, 0, 0, 0, 501, -1, 9))) | ConvertFrom-Csv
    $forever = @(Get-ForeverInstances $foreverMaps @{ 2000 = 'Old Cave'; 2001 = 'Fire Pit'; 2002 = 'No Door' } $retailJournal $retailDoors)
    Equal (($forever | ForEach-Object { "$($_.Name):$($_.Kind):$($_.Categories -join '+'):$(@($_.Doors).Count)" }) -join '; ') 'Old Cave:dungeon:2000:1; Fire Pit:raid:2001:1; No Door:dungeon:2002:0' 'A5: a dungeon or raid map whose area is a category, its corpse point the door'
    Equal "$($forever[1].Doors[0].Map) $($forever[1].Doors[0].X),$($forever[1].Doors[0].Y) area $($forever[1].Doors[0].Area) hint $($forever[1].Doors[0].Hint)" '0 -200,500 area 0 hint 501' 'A5: no area of its own; retail''s area, by name, only a hint'

    $decisionFile = Join-Path $Scratch 'decisions.csv'
    function Decisions($rows) {
        $rows | ForEach-Object { [pscustomobject][ordered]@{ Game = $_[0]; Instance = $_[1]; Door = $_[2]; Decision = $_[3]; UiMapID = $_[4]; X = $_[5]; Y = $_[6]; Evidence = 'e' } } |
            Export-Csv $decisionFile -NoTypeInformation -Encoding UTF8
    }
    Decisions @(@('retail', 'Two Doors', '14', 'SHOW', '11', '25.5', '70'), @('retail', 'Sky Spire', '12', 'HIDE', '', '', ''), @('forever', 'Two Doors', '14', 'HIDE', '', '', ''))
    $d = Read-EntranceDecisions $decisionFile 'retail'
    Equal "$($d.Count) $($d['Two Doors|14'].Decision) $($d['Sky Spire|12'].Decision)" '2 SHOW HIDE' 'A6: one game''s rows, keyed by instance and door'
    Equal (Read-EntranceDecisions (Join-Path $Scratch 'none.csv') 'retail').Count 0 'A6: no file, no rows'
    Decisions @(, @('retail', 'Two Doors', '14', 'SHOW', '11', '', '70'))
    Throws { Read-EntranceDecisions $decisionFile 'retail' } 'SHOW needs a UiMapID, X and Y' 'A6: SHOW without a place is refused'
    Decisions @(, @('retail', 'Two Doors', '14', 'SHOW', '11', '125', '70'))
    Throws { Read-EntranceDecisions $decisionFile 'retail' } 'map points' 'A6: a place off the map is refused'
    Decisions @(, @('retail', 'Two Doors', '14', 'MOVE', '', '', ''))
    Throws { Read-EntranceDecisions $decisionFile 'retail' } 'only SHOW and HIDE' 'A6: another decision is refused'
    Decisions @(@('retail', 'Two Doors', '14', 'HIDE', '', '', ''), @('retail', 'Two Doors', '14', 'HIDE', '', '', ''))
    Throws { Read-EntranceDecisions $decisionFile 'retail' } 'listed twice' 'A6: a door listed twice is refused'

    function Quest($id, $category, $faction = 0) { [pscustomobject]@{ id = $id; name = "Quest $id"; level = 10; zone = ''; category = $category; type = 1; faction = $faction; race = 0; class = 8191 } }
    $quests = @((Quest 1001 900), (Quest 1002 900 1), (Quest 1003 900), (Quest 1004 900), (Quest 1005 901), (Quest 1006 905 1), (Quest 1007 905 2), (Quest 1008 905 0),
        (Quest 1015 905 3), (Quest 1009 906), (Quest 1010 3), (Quest 1011 902), (Quest 1014 70))
    $pinned = New-Object 'System.Collections.Generic.HashSet[int]'; [void]$pinned.Add(1002); [void]$pinned.Add(1014)
    $skip = New-Object 'System.Collections.Generic.HashSet[int]'; [void]$skip.Add(1003); [void]$skip.Add(1004)
    $result = Get-EntrancePins $retail $quests $pinned $skip $locator @{}
    Equal (($result.Doors | ForEach-Object { "$($_.Instance)|$($_.Door)|$($_.How)|$($_.Quests -join ' ')" }) -join '; ') 'The Deep Halls|11|box|1001; Sky Spire|12|area|1005; Two Doors|13|box|1006 1008 1015; Two Doors|14|several|1007 1008 1015' 'A7: each door, its quests and how it was placed: no pinned, skipped or other category''s quest; a side''s door keeps the quests that side can take'
    Equal (($result.Pins | ForEach-Object { "$($_.map) $($_.x),$($_.y) $($_.kind) $($_.name)" }) -join '; ') '10 50,80 dungeon The Deep Halls; 11 25,70 raid Sky Spire; 10 50,80 dungeon Two Doors' 'A7: a pin per placed door, none for a held one'
    Equal (($result.Doorless | ForEach-Object { "$($_.Name) $($_.Quests)" }) -join '; ') 'Lost Keep 1' 'A7: an instance with quests and no door is listed'
    $d = @{ 'Two Doors|14' = [pscustomobject]@{ Decision = 'SHOW'; UiMapID = '11'; X = '25.5'; Y = '70' }; 'Sky Spire|12' = [pscustomobject]@{ Decision = 'HIDE' } }
    $result = Get-EntrancePins $retail $quests $pinned $skip $locator $d
    $door14 = $result.Doors | Where-Object Door -eq 14
    Equal "$($door14.How) $($door14.Decided) $($door14.UiMap) $($door14.X),$($door14.Y)" 'SHOW True 11 25.5,70' 'A7: a SHOW row places a held door'
    Equal (($result.Doors | Where-Object Door -eq 12).How) 'area' 'A7: a row for a door the rule places changes nothing (the tool reports the row)'
    Equal @($result.Pins).Count 4 'A7: so it keeps its pin'
    $d = @{ 'Two Doors|14' = [pscustomobject]@{ Decision = 'HIDE' } }
    $result = Get-EntrancePins $retail $quests $pinned $skip $locator $d
    Equal "$(($result.Doors | Where-Object Door -eq 14).How) $(@($result.Pins).Count)" 'HIDE 3' 'A7: a HIDE row leaves a held door without a pin'

    $spot = { param($map, $journal, $x, $y, $name) [pscustomobject]@{ Map = $map; Journal = $journal; X = [decimal]$x; Y = [decimal]$y; Name = $name } }
    $game = Group-GameEntrances @((& $spot 11 3 '12.3' '45.6' 'Sky Spire'), (& $spot 10 3 '80' '20.25' 'Sky Spire'), (& $spot 11 3 '12.3' '45.6' 'Sky Spire'), (& $spot 10 0 '5' '5' 'The Lost Keep'))
    Equal "$($game['j3'].Count) $($game['nskyspire'].Count) $($game['nlostkeep'].Count) $($game.ContainsKey('j0'))" '2 2 1 False' 'A8: the game''s places by journal instance and by name, a place given twice counted once'
    $result = Get-EntrancePins $retail $quests $pinned $skip $locator @{ 'Sky Spire|12' = [pscustomobject]@{ Decision = 'HIDE' } } $game
    Equal (($result.Doors | Where-Object Instance -eq 'Sky Spire' | ForEach-Object { "$($_.How) $($_.UiMap) $($_.X),$($_.Y) $($_.Door)|$($_.Held)|$($_.Decided)" }) -join '; ') 'game 10 80,20.25 |False|False; game 11 12.3,45.6 |False|False' 'A9: an instance the game draws gets its places, not its door, and no row applies'
    Equal (($result.Pins | Where-Object name -eq 'Sky Spire' | ForEach-Object { "$($_.map) $($_.kind) $($_.quests -join '+')" }) -join '; ') '10 raid 1005; 11 raid 1005' 'A9: a pin at each place, with its quests'
    Equal (($result.Doors | Where-Object Instance -eq 'The Deep Halls' | ForEach-Object { $_.How }) -join ',') 'box' 'A9: an instance the game doesn''t draw keeps its doors'
    $twins = @([pscustomobject]@{ Name = 'Old Halls'; Kind = 'dungeon'; Categories = @(900); GameKey = 'j1'; Doors = @($retail[0].Doors) },
        [pscustomobject]@{ Name = 'New Halls'; Kind = 'raid'; Categories = @(900); GameKey = 'j50'; Doors = @() },
        [pscustomobject]@{ Name = 'Lone Halls'; Kind = 'raid'; Categories = @(900, 901); GameKey = 'j51'; Doors = @() })
    $result = Get-EntrancePins $twins $quests $pinned $skip $locator @{} (Group-GameEntrances @(, (& $spot 11 50 '1' '2' 'New Halls')))
    Equal (($result.Doors | ForEach-Object { "$($_.Instance) $($_.How)" }) -join '; ') 'New Halls game' 'A9: of two instances on one category, the one the game draws places its quests and the other gets no door'
    Equal (($result.Doorless | ForEach-Object { "$($_.Name) $($_.Quests)" }) -join '; ') 'Lone Halls 2' 'A9: one with a category of its own still counts as having no door'

    # B. The data file and the build
    function Entrance($map, $x, $y, $kind, $name, $quests) { [pscustomobject][ordered]@{ map = $map; x = $x; y = $y; kind = $kind; name = $name; quests = $quests } }
    Equal @(Test-EntranceRecords @((Entrance 10 50 80 'dungeon' 'A' @(1)), (Entrance 11 ([decimal]25.5) 70 'raid' 'B' @(2, 3)))).Count 0 'B1: sound records pass'
    $bad = @(Test-EntranceRecords @((Entrance 0 50 80 'dungeon' 'A' @(1)), (Entrance 10 101 80 'dungeon' 'A' @(1)), (Entrance 10 50 80 'scenario' 'A' @(1)),
        (Entrance 10 50 80 'dungeon' '' @(1)), (Entrance 10 50 80 'dungeon' 'A' @()), (Entrance 10 50 80 'dungeon' 'A' @(1, 1))))
    Equal $bad.Count 6 "B1: a bad map, x, kind, name, an empty and a doubled quest list are each a problem ($($bad -join ' / '))"
    Check ($bad[2] -like "*'kind' is 'dungeon' or 'raid'*") "B1: the kind's problem names the kinds ($($bad[2]))"
    $pinProblems = @(Test-PinRecords @([pscustomobject]@{ map = 10; icon = 12; npc = 0; name = 'X'; x = 1; y = 1; quests = @(1) }))
    Check ($pinProblems.Count -eq 1 -and $pinProblems[0] -like "*icon 12 is an entrance pin's*") "B2: pins.jsonl can't hold an entrance's icon ($($pinProblems -join ' / '))"
    $ids = New-Object 'System.Collections.Generic.HashSet[long]'; foreach ($i in 1, 2, 3, 4) { [void]$ids.Add($i) }
    $rows = @(Get-EntrancePinRows @((Entrance 10 50 80 'dungeon' 'A' @(1, 2, 9)), (Entrance 11 25 70 'raid' 'B' @(3)), (Entrance 12 1 1 'raid' 'C' @(4))) @([pscustomobject]@{ map = 10; quests = @(2, 3) }) $ids)
    Equal (($rows | ForEach-Object { "$($_.map) $($_.icon) $($_.npc) $($_.name) $($_.quests -join '+')" }) -join '; ') '10 12 0 A 1; 12 13 0 C 4' 'B3: a quest a pin has or the data lacks leaves its entrance, and an entrance left with none goes'
    $lua = ConvertTo-LuaPinFile @([pscustomobject]@{ map = 12; icon = 1; npc = 5; name = 'Giver'; x = 1; y = 2; quests = @(7); note = $null }) 'data' $rows
    Equal ($lua -split "`r`n")[0] '-- Generated from data\pins.jsonl and data\entrances.jsonl by tools\Build-AddonData.ps1. Edit the data files, not this one.' 'B4: the header names both files'
    Equal (($lua -split "`r`n")[2..6] -join '|') "`t[10] = {|`t`t{12,0,`"A`",50,80,{1}},|`t},|`t[12] = {|`t`t{1,5,`"Giver`",1,2,{7}}," 'B4: maps in order, a map only an entrance has among them'
    Check ($lua.Contains("{1,5,`"Giver`",1,2,{7}},`r`n`t`t{13,0,`"C`",1,1,{4}},")) 'B4: an entrance follows its map''s pins'
    Equal ((ConvertTo-LuaPinFile @([pscustomobject]@{ map = 12; icon = 1; npc = 5; name = 'Giver'; x = 1; y = 2; quests = @(7); note = $null }) 'data') -split "`r`n")[0] '-- Generated from data\pins.jsonl by tools\Build-AddonData.ps1. Edit the data file, not this one.' 'B4: without entrances the header is as before'
    Equal (ConvertTo-EntranceJsonLines @((Entrance 10 ([decimal]50.50) 80 'dungeon' 'Say "hi"' @(1, 2)))) ('{"map":10,"x":50.5,"y":80,"kind":"dungeon","name":"Say \"hi\"","quests":[1,2]}' + "`n") 'B5: a record''s line'

    # C. A run on retail
    function New-World([string]$name, [string]$game) {
        $root = Join-Path $Scratch $name
        foreach ($dir in 'tools', 'data', 'addon', 'docs') { New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null }
        return $root
    }
    function Write-Quests($root, $quests, $pins) {
        $q = $quests | ForEach-Object { '{"id":' + $_.id + ',"name":"' + $_.name + '","level":10,"zone":"","category":' + $_.category + ',"type":1,"faction":' + $_.faction + ',"race":0,"class":8191}' }
        [IO.File]::WriteAllText("$root\data\quests.jsonl", (($q -join "`n") + "`n"))
        [IO.File]::WriteAllText("$root\data\pins.jsonl", (($pins -join "`n") + "`n"))
        $build = Invoke-AddonDataBuild -DataDir "$root\data" -AddonDir "$root\addon"
        if (-not $build.Ok) { throw "the world's build failed: $($build.Lines -join ' / ')" }
    }
    function Invoke-Tool([string]$root, [string[]]$arguments) {
        $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $out = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $Tool @arguments -ToolsDir "$root\tools" -DataDir "$root\data" -AddonDir "$root\addon" -DecisionsFile "$root\docs\decisions.csv" 2>&1) } finally { $ErrorActionPreference = $saved }
        return [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($out | ForEach-Object { "$_" }) -join "`n" }
    }
    function Write-RetailDecisions($root, $rows) {
        $rows | ForEach-Object { [pscustomobject][ordered]@{ Game = $_[0]; Instance = $_[1]; Door = $_[2]; Decision = $_[3]; UiMapID = $_[4]; X = $_[5]; Y = $_[6]; Evidence = 'e' } } |
            Export-Csv "$root\docs\decisions.csv" -NoTypeInformation -Encoding UTF8
    }
    $B = '1.0.0.1'
    $root = New-World 'retail'
    [IO.File]::WriteAllText("$root\tools\Map-$B.csv", (Csv $MapHeader @((MapRow 0 'World' 0), (MapRow 2 'Phase' 0 0 0), (MapRow 100 'a' 1), (MapRow 101 'b' 1), (MapRow 102 'c' 2),
        (MapRow 103 'd' 1), (MapRow 104 'e' 1), (MapRow 105 'f' 0), (MapRow 106 'g' 1), (MapRow 107 'h' 1))))
    [IO.File]::WriteAllText("$root\tools\UiMap-$B.csv", $UiMapCsv)
    [IO.File]::WriteAllText("$root\tools\UiMapAssignment-$B.csv", $AssignCsv)
    [IO.File]::WriteAllText("$root\tools\AreaTable-$B.csv", $AreaCsv)
    [IO.File]::WriteAllText("$root\tools\JournalInstance-$B.csv", (Csv 'ID,Name_lang,MapID,Flags' @(@(1, 'The Deep Halls', 100, 0), @(2, 'Deep Vault', 101, 0), @(3, 'Sky Spire', 102, 0),
        @(4, 'Zone Hall', 103, 0), @(5, 'Boss Field', 104, 2), @(6, 'Open Plaza', 105, 0), @(7, 'Two Doors', 106, 0), @(8, 'Lost Keep', 107, 0))))
    [IO.File]::WriteAllText("$root\tools\JournalInstanceEntrance-$B.csv", (Csv 'ID,Position_0,Position_1,Position_2,MapID,AreaTableID,Faction,JournalInstanceID' @(
        @(11, -800, 0, 0, 0, 0, -1, 1), @(12, -200, 500, 0, 2, 501, -1, 3), @(13, -800, 0, 0, 0, 0, 1, 7), @(14, -200, 500, 0, 0, 0, 0, 7), @(15, -800, 0, 0, 0, 0, -1, 2))))
    [IO.File]::WriteAllText("$root\tools\QuestV2CliTask.csv", (Csv 'ID,QuestInfoID' @(@(1003, 109), @(1001, 0))))
    [IO.File]::WriteAllText("$root\addon\qcQuest.lua", "qcQuestCategories={`r`n{70,`"Elwynn Forest`"},`r`n{900,`"Deep Halls`"},`r`n{3,`"Deep Vault`"},`r`n{901,`"Sky Spire`"},`r`n{902,`"Zone Hall`"},`r`n{903,`"Boss Field`"},`r`n{904,`"Open Plaza`"},`r`n{905,`"Two Doors`"},`r`n{906,`"Lost Keep`"},`r`n}`r`nqcCategoryUiMapID = {`r`n`t[902]=10,`r`n}`r`n")
    [IO.File]::WriteAllText("$root\addon\qcUnavailableQuests.lua", "qcUnavailableQuests = {`r`n[1004]=1,`r`n}`r`n")
    Write-Quests $root @((Quest 1001 900), (Quest 1002 900 1), (Quest 1003 900), (Quest 1004 900), (Quest 1005 901), (Quest 1006 905 1), (Quest 1007 905 2), (Quest 1008 905 0),
        (Quest 1009 906), (Quest 1010 3), (Quest 1011 902), (Quest 1014 70)) @('{"map":10,"icon":1,"npc":5,"name":"Giver","x":10,"y":10,"quests":[1002,1014]}')
    $pinLua = [IO.File]::ReadAllText("$root\addon\qcPinDB.lua")

    $r = Invoke-Tool $root @('-Game', 'retail', '-Build', $B, '-WhatIf')
    Check ($r.Exit -eq 1 -and $r.Text -match 'saw the game draw no entrance: run its map pass, or every instance goes to its doors') "C0: on retail, a probe with no entrance is a finding ($($r.Text))"
    Check ($r.Text -match 'placed by their area 1, by the one zone holding them 2') 'C0: and every instance goes to its doors'
    New-Item -ItemType Directory -Path "$root\tools\retail_probe_1" | Out-Null
    [IO.File]::WriteAllText("$root\tools\retail_probe_1\QCForeverProbe.lua", "QCForeverProbeDB = {`r`n[`"maps`"] = {`r`n[10] = {`r`n[`"entrances`"] = {`r`n{`r`n[`"x`"] = 12.3,`r`n[`"name`"] = `"Sky Spire`",`r`n[`"y`"] = 45.6,`r`n[`"atlas`"] = `"Raid`",`r`n[`"journalInstanceID`"] = 3,`r`n},`r`n},`r`n},`r`n[11] = {`r`n},`r`n},`r`n}`r`n")
    Equal (@(Get-ProbeEntrances "$root\tools\retail_probe_1\QCForeverProbe.lua") | ForEach-Object { "$($_.Map) $($_.Journal) $($_.X),$($_.Y) $($_.Name)" }) '10 3 12.3,45.6 Sky Spire' 'C1: the probe''s entrances are read'

    $r = Invoke-Tool $root @('-Game', 'retail', '-Build', $B, '-WhatIf')
    Equal $r.Exit 1 "C1: a held door without a row is a finding ($($r.Text))"
    Check ($r.Text -match 'Findings: 1: Two Doors, door 14: held by Zone A \(10\) 25,20, Zone B \(11\) 25,70; give it a row') 'C1: which says where it could go'
    Check ($r.Text -match '4 dungeon and raid categories; 4 have quests no pin places \(1 task quests of a no-pin kind left out\)') 'C1: the instances counted, the world quest kind left out'
    Check ($r.Text -match 'The game''s own map \(probe retail_probe_1\): 1 entrances; 1 of these instances placed at its 1 places') 'C1: the game draws one'
    Check ($r.Text -match 'go to their doors \(The Deep Halls, Two Doors\): 3; placed by their area 0, by the one zone holding them 2, by a SHOW row 0; hidden by a row 0; held with no row 1') 'C1: how the others'' doors were placed'
    Check ($r.Text -match 'no door in the client''s data: 1 \(Lost Keep 1\)') 'C1: the doorless instance'
    Check (-not (Test-Path "$root\data\entrances.jsonl") -and [IO.File]::ReadAllText("$root\addon\qcPinDB.lua") -ceq $pinLua) 'C1: -WhatIf writes nothing'
    $report = @(Import-Csv "$root\tools\entrance_pins_retail.csv")
    Equal (($report | ForEach-Object { "$($_.Door) $($_.How) $($_.Zone) $($_.X),$($_.Y) $($_.QuestIDs)" }) -join '; ') '11 box Zone A 50,80 1001;  game Zone A 12.3,45.6 1005; 13 box Zone A 50,80 1006 1008; 14 several  , 1007 1008' 'C1: the report: each place and door, and its quests'
    Equal ($report | Where-Object Door -eq 11).RetailArea '' 'C1: a door with no area has none in the report'

    Write-RetailDecisions $root @(, @('retail', 'Two Doors', '14', 'SHOW', '11', '25.00', '70.00'))
    $r = Invoke-Tool $root @('-Game', 'retail', '-Build', $B)
    Equal $r.Exit 0 "C2: with a SHOW row the run has no finding ($($r.Text))"
    Equal ([IO.File]::ReadAllText("$root\data\entrances.jsonl")) ('{"map":10,"x":50,"y":80,"kind":"dungeon","name":"The Deep Halls","quests":[1001]}' + "`n" +
        '{"map":10,"x":12.3,"y":45.6,"kind":"raid","name":"Sky Spire","quests":[1005]}' + "`n" + '{"map":10,"x":50,"y":80,"kind":"dungeon","name":"Two Doors","quests":[1006,1008]}' + "`n" +
        '{"map":11,"x":25,"y":70,"kind":"dungeon","name":"Two Doors","quests":[1007,1008]}' + "`n") 'C2: entrances.jsonl, the game''s place for the instance it draws'
    $pinLua = [IO.File]::ReadAllText("$root\addon\qcPinDB.lua")
    Check ($pinLua.Contains("`t[10] = {`r`n`t`t{1,5,`"Giver`",10,10,{1002,1014}},`r`n`t`t{12,0,`"The Deep Halls`",50,80,{1001}},`r`n`t`t{13,0,`"Sky Spire`",12.3,45.6,{1005}},`r`n`t`t{12,0,`"Two Doors`",50,80,{1006,1008}},`r`n`t},")) 'C2: the build writes the entrance pins after the giver, a raid''s with its own icon'
    Check ($pinLua.Contains("`t[11] = {`r`n`t`t{12,0,`"Two Doors`",25,70,{1007,1008}},`r`n`t},")) 'C2: and the SHOW row''s'
    Check ($r.Text -match '4 entrance pins' -and $r.Text -match 'entrances.jsonl written: 4 pins new or changed, 0 gone') 'C2: the build and the run count them'
    $r = Invoke-Tool $root @('-Game', 'retail', '-Build', $B)
    Check ($r.Exit -eq 0 -and $r.Text -match 'entrances.jsonl: no change') "C3: a second run changes nothing ($($r.Text))"
    $check = Invoke-AddonDataBuild -DataDir "$root\data" -AddonDir "$root\addon" -Check
    Check $check.Ok 'C3: the Lua matches the data files'

    Write-RetailDecisions $root @(@('retail', 'Two Doors', '14', 'SHOW', '11', '25.00', '70.00'), @('retail', 'The Deep Halls', '11', 'HIDE', '', '', ''),
        @('retail', 'Sky Spire', '12', 'HIDE', '', '', ''), @('retail', 'Gone', '99', 'HIDE', '', '', ''))
    $r = Invoke-Tool $root @('-Game', 'retail', '-Build', $B, '-WhatIf')
    Equal $r.Exit 1 'C4: a row for a door the rule places, for an instance the game draws, or for no door, is a finding'
    foreach ($row in 'The Deep Halls, door 11', 'Sky Spire, door 12', 'Gone, door 99') {
        Check ($r.Text -match "a decision row for $row, which is no held door with quests no pin has \(the rule places it, or the game draws the instance\); drop the row") "C4: $row"
    }
    $r = Invoke-Tool $root @('-Game', 'forever', '-Build', $B)
    Check ($r.Exit -ne 0 -and $r.Text -match 'Give -RetailBuild') 'C5: Forever needs the retail build'

    # D. A run on WoW: Forever
    $F = '1.60.0.2'
    $root = New-World 'forever'
    [IO.File]::WriteAllText("$root\tools\Map-$F.csv", (Csv $MapHeader @((MapRow 0 'World' 0), (MapRow 300 'Old Cave' 1 2000 -1 -1 0 -800 0), (MapRow 301 'Fire Pit' 2 2001 -1 -1 0 -200 500), (MapRow 302 'No Door' 1 2002))))
    [IO.File]::WriteAllText("$root\tools\UiMap-$F.csv", $UiMapCsv)
    [IO.File]::WriteAllText("$root\tools\UiMapAssignment-$F.csv", $AssignCsv)
    [IO.File]::WriteAllText("$root\tools\AreaTable-$F.csv", (Csv 'ID,AreaName_lang,ParentAreaID' @(@(50, 'Zone A', 0), @(60, 'Zone B', 0))))
    [IO.File]::WriteAllText("$root\tools\AreaTable-$B.csv", $AreaCsv)
    [IO.File]::WriteAllText("$root\tools\JournalInstance-$B.csv", (Csv 'ID,Name_lang,MapID,Flags' @(, @(9, 'The Fire Pit', 1, 0))))
    [IO.File]::WriteAllText("$root\tools\JournalInstanceEntrance-$B.csv", (Csv 'ID,Position_0,Position_1,Position_2,MapID,AreaTableID,Faction,JournalInstanceID' @(, @(20, 0, 0, 0, 0, 501, -1, 9))))
    [IO.File]::WriteAllText("$root\addon\qcQuest.lua", "qcQuestCategories={`r`n{2000,`"Old Cave`"},`r`n{2001,`"Fire Pit`"},`r`n{2002,`"No Door`"},`r`n}`r`nqcCategoryUiMapID={}`r`n")
    [IO.File]::WriteAllText("$root\addon\qcUnavailableQuests.lua", "qcUnavailableQuests = {`r`n}`r`n")
    Write-Quests $root @((Quest 3001 2000), (Quest 3002 2001), (Quest 3003 2002)) @('{"map":10,"icon":1,"npc":5,"name":"Giver","x":10,"y":10,"quests":[3999]}')
    $r = Invoke-Tool $root @('-Game', 'forever', '-Build', $F, '-RetailBuild', $B)
    Equal $r.Exit 1 "D1: a corpse point two zones hold is held, though retail's area would choose ($($r.Text))"
    Check ($r.Text -match 'Fire Pit, door 301: held by Zone A \(10\) 25,20, Zone B \(11\) 25,70') 'D1: and says where it could go'
    Check ($r.Text -notmatch 'task quests') 'D1: Forever has no task table to read'
    Equal ([IO.File]::ReadAllText("$root\data\entrances.jsonl")) ('{"map":10,"x":50,"y":80,"kind":"dungeon","name":"Old Cave","quests":[3001]}' + "`n") 'D1: the placed door is written all the same'
    $report = @(Import-Csv "$root\tools\entrance_pins_forever.csv")
    Equal (($report | ForEach-Object { "$($_.Door) $($_.How) $($_.RetailArea)" }) -join '; ') '300 box ; 301 several 501 Sub B' 'D1: the report gives retail''s area as the hint'
    Write-RetailDecisions $root @(, @('forever', 'Fire Pit', '301', 'SHOW', '10', '25', '20'))
    $r = Invoke-Tool $root @('-Game', 'forever', '-Build', $F, '-RetailBuild', $B)
    Equal $r.Exit 0 "D2: its row places it, and Forever's probe drawing none is no finding ($($r.Text))"
    Check ([IO.File]::ReadAllText("$root\addon\qcPinDB.lua").Contains("{12,0,`"Old Cave`",50,80,{3001}},`r`n`t`t{13,0,`"Fire Pit`",25,20,{3002}},")) 'D2: both pins built, the raid''s with its icon'
    New-Item -ItemType Directory -Path "$root\tools\forever_probe_1" | Out-Null
    [IO.File]::WriteAllText("$root\tools\forever_probe_1\QCForeverProbe.lua", "QCForeverProbeDB = {`r`n[`"maps`"] = {`r`n[11] = {`r`n[`"entrances`"] = {`r`n{`r`n[`"x`"] = 70,`r`n[`"name`"] = `"The Fire Pit`",`r`n[`"y`"] = 30.5,`r`n},`r`n},`r`n},`r`n},`r`n}`r`n")
    $r = Invoke-Tool $root @('-Game', 'forever', '-Build', $F, '-RetailBuild', $B)
    Equal $r.Exit 1 "D3: once Forever's game draws an instance, by name, its place wins and the row is a finding ($($r.Text))"
    Check ($r.Text -match 'a decision row for Fire Pit, door 301, which is no held door') 'D3: the row to drop'
    Check ([IO.File]::ReadAllText("$root\data\entrances.jsonl").Contains('{"map":11,"x":70,"y":30.5,"kind":"raid","name":"Fire Pit","quests":[3002]}')) 'D3: the pin at the game''s place'
}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
