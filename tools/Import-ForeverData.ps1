<#
Builds WoW: Forever's quest and pin data, data\forever\quests.jsonl and pins.jsonl, from five sources
(docs/plans/forever.md, phase 3):

  - the client's tables for -Build: the quests the game records as completed (QuestV2), and where
    some start (QuestPOIBlob and QuestPOIPoint);
  - the quest cache file Read-ForeverQuestCache.ps1 writes: what the server says about each quest it
    answered;
  - CMaNGOS's vanilla database (cmangos/classic-db, Full_DB, GPL-3.0): the old world, including the
    quests the beta didn't answer, and who starts each quest and where they stand;
  - the beta probe's saved variables: which quests failed, the game's NPC names, and the recorder's
    quest givers and spots;
  - -GiverFile and -ZoneFile, docs\plans\forever-quest-givers.csv and forever-quest-zones.csv:
    givers and zones looked up by hand on Wowhead's Forever pages, for quests the other sources
    can't place. A listed NPC stands where CMaNGOS or the recorder puts it.

The game wins wherever it speaks. Title, level, zone, recurrence and race restrictions come from the
cache when it has the quest, a recorded spot wins over CMaNGOS's for that giver, and NPC names come
from the probe. A quest's givers are CMaNGOS's, the recorder's and the hand list's together, but a
listed giver the recorder didn't see offer the quest, when it saw another giver do so, is left out.
Quests with internal titles ("<UNUSED>", "[DNT]" and the like, and test quests only the game knows)
are left out.
QuestV2 isn't a list of every quest: a repeatable quest is never recorded as completed, so it has no
row. CMaNGOS's repeatable quests are kept without one; any other CMaNGOS quest QuestV2 lacks is left
out until the game answers for it. With no row, a quest the probe asked about that failed at level 1
to 35, where the beta answers nearly every quest, is left out too, until the game answers for it.
Every kept quest QuestV2 lacks is listed for review.

The files follow data\quests.jsonl and pins.jsonl (see AddonData.ps1), with Forever's values:
  category  Blizzard's own: the zone's AreaTable ID, or the negative QuestSort ID for class,
            profession, holiday and Forever's other headings; CMaNGOS's when the game's record
            has none; 0 for none, or for an area the client's AreaTable doesn't have. A quest
            filed under an area named after an instance (Gnomeregan in Dun Morogh) gets the
            instance's own area; one filed under any other subzone (Valley of Trials) gets its
            zone, as retail's categories are zones. A heading that isn't a place, a race's (Night
            Elf) or Treasure Map, gives way to the zone forever-quest-zones.csv gives the quest,
            else the zone of its pins' map, else CMaNGOS's zone, else 0. zone is its name.
  faction   1 Alliance, 2 Horde, 3 both: from the cache's race restriction, or CMaNGOS's.
  race      0 for any race, since faction already gates; otherwise the addon's race bits, with
            Skyborne (races 95 and 96) as 67108864.
  class     the addon's class bits, from CMaNGOS or a class heading; 8191 for any.
  type      4 daily, 128 weekly, 2 repeatable, 64 seasonal, 32 profession or 1, the first that
            applies, so a repeatable holiday or profession quest is repeatable, as on retail. holiday
            and profession hold the addon's flags.
  holiday   CMaNGOS's holiday for the quest, or for its heading; failing that, the holiday or event
            all its givers, NPCs and objects, stand only during. Events with no holiday of their
            own go by their description: the Darkmoon Faire's building days, the fishing contest's
            announcers and judges, and the Scourge Invasion and Ahn'Qiraj War Effort, which the
            calendar doesn't show, so the addon keeps their quests off the map.
  prereq    CMaNGOS's previous quest, or the quest whose follow-up this is in the cache.
Pins are CMaNGOS's spawns of each quest's NPC or object givers, or the recorder's spots for the givers
it saw. Spawns are converted to map positions with the client's UiMapAssignment frames. Frames are
rectangles and overlap, so a spawn goes on the first of these maps whose frame holds it:
  1. the map our old Classic pins had for that NPC (git history before #89), or the one whose old
     pin stands nearest the spawn when the NPC has old pins on several of them;
  2. the map our old pins put most NPCs within 100 yards on;
  3. a city, if the spawn stands within 50 yards of the heights of the NPCs our old pins have there;
  4. the zone its giver's quests are in;
  5. the one the spawn stands furthest inside, measured from the frame's nearest edge, or the
     smallest of those within 0.05 of that.
Only maps Classic Era (-EraBuild) already had are used, as CMaNGOS's NPCs can't stand in Forever's new
zones, whose frames reach over old ones (Mount Hyjal's covers parts of Felwood and Winterspring).
Givers inside dungeons get no pin. A giver found in more than 3 places on one map, like the chickens
that start CLUCK!, gets one pin on each of its maps, at its biggest group of spawns, when all its
quests recur and none is a holiday's: those pins show all year. A holiday's givers keep every pin.
A quest with no giver on a map gets a pin at its start point in the client's tables, if it has one,
with no giver named: the tables don't say who stands there. A quest that has a giver's pin keeps it,
and a start point more than 3 map points from all its pins on that map is listed for review. The
summary counts the client's start points, and the quests whose record in the cache names a giver
(none so far), so a rerun shows when Blizzard fills in more of either.

Three more files hold what Build-ForeverMenu.ps1 turns into the quest tooltip's reputation and
profession skill, and the quest window's warnings:
  links.jsonl       a line for each quest with links: its breadcrumbs, the quests that lead to it
                    and close once it's done (CMaNGOS's BreadcrumbForQuestId), and the quests it
                    shuts out, the rest of its CMaNGOS ExclusiveGroup when that's positive, as only
                    one quest of such a group can be done. Recurring quests are left out of both:
                    CMaNGOS also groups repeatable quests that only shut each other out while one is
                    in the quest log.
  reputation.jsonl  a line for each reputation reward, from the game's records only. CMaNGOS's
                    amounts are mostly The Burning Crusade's, which raised most quests' rewards (a
                    city's 100 became 250), so a quest the game hasn't answered gets its reputation
                    once it does.
  skills.jsonl      a line for each quest that needs a profession, and the skill level it needs:
                    CMaNGOS's RequiredSkill and RequiredSkillValue, as the game's records don't say.
                    A level of 1 asks only that the character has learned the profession.

Anything worth a look goes to -ReviewFile, one row per finding; the summary counts them. With -WhatIf,
only the review is written.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data\forever'),
    [string]$Build = "1.60.1.70205",
    [string]$EraBuild = "1.15.9.70003",
    [string]$CacheFile = "",
    [string]$ProbeFile = "",
    [string]$CmangosDump = "",
    [string]$GiverFile = (Join-Path $PSScriptRoot '..\docs\plans\forever-quest-givers.csv'),
    [string]$ZoneFile = (Join-Path $PSScriptRoot '..\docs\plans\forever-quest-zones.csv'),
    [string]$ReviewFile = "",
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\AddonData.ps1"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if (-not $CacheFile) { $CacheFile = "$ToolsDir\forever_quest_cache_$Build.jsonl" }
if (-not (Test-Path $CacheFile)) { throw "There's no $CacheFile. Run Read-ForeverQuestCache.ps1 first." }
if (-not $ProbeFile) {
    $ProbeFile = Get-ChildItem "$ToolsDir\forever_probe_*\QCForeverProbe.lua" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
    if (-not $ProbeFile) { throw "There are no probe results under $ToolsDir\forever_probe_*. Give -ProbeFile." }
}
if (-not $ReviewFile) { $ReviewFile = "$ToolsDir\forever_import_review.csv" }

function Get-ClientTable([string]$table, [string]$tableBuild = $Build) {
    $path = "$ToolsDir\$table-$tableBuild.csv"
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$tableBuild" -OutFile $path
        Start-Sleep -Milliseconds 300
    }
    return Import-Csv $path
}

if (-not $CmangosDump) {
    $CmangosDump = Get-ChildItem "$ToolsDir\ClassicDB_*.sql.gz" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $CmangosDump) {
        $listing = Invoke-RestMethod "https://api.github.com/repos/cmangos/classic-db/contents/Full_DB"
        $file = $listing | Where-Object { $_.name -like '*.sql.gz' } | Select-Object -First 1
        $CmangosDump = "$ToolsDir\$($file.name)"
        Invoke-WebRequest -UseBasicParsing -Uri $file.download_url -OutFile $CmangosDump
    }
}

$raceBit = @{ 1 = 1; 2 = 2; 3 = 4; 4 = 8; 5 = 16; 6 = 32; 7 = 64; 8 = 128; 95 = 67108864; 96 = 67108864 }
$classBySort = @{ (-81) = 1; (-141) = 2; (-261) = 4; (-162) = 8; (-262) = 16; (-82) = 64; (-161) = 128; (-61) = 256; (-263) = 512 }
$skillBySort = @{ (-24) = 182; (-101) = 356; (-121) = 164; (-181) = 171; (-182) = 165; (-201) = 202; (-264) = 197; (-304) = 185; (-324) = 129 }
$professionBySkill = @{ 171 = 1; 164 = 2; 333 = 4; 202 = 8; 165 = 64; 197 = 128; 182 = 256; 186 = 512; 393 = 1024; 129 = 4096; 185 = 8192; 356 = 16384 }
$holidayByHolidayId = @{ 372 = 1; 201 = 2; 409 = 4; 141 = 8; 324 = 16; 1405 = 16; 321 = 32; 423 = 64; 335 = 64; 327 = 128
    341 = 256; 181 = 512; 404 = 1024; 398 = 2048; 691 = 4096; 479 = 8192; 374 = 8192; 375 = 8192; 376 = 8192; 301 = 65536 }
# CMaNGOS's events with no holiday of their own, by their description: the Darkmoon Faire's building days, the
# fishing contest's announcers and judges, and two world events the calendar doesn't show.
$holidayByEventName = [ordered]@{ '^Darkmoon Faire' = 8192; '^Fishing Extravaganza' = 65536; '^Scourge Invasion' = 16384
    '^AQ War Effort' = 32768 }
$holidayBySort = @{ (-364) = 8192; (-366) = 128; (-369) = 256 }
$seasonalSort = -22
$allianceRaces = 77
$hordeRaces = 178
$internalTitle = '^<|UNUSED|\[DNT\]|\(DNT\)|\[PH\]|^ZZ|\bNYI\b|DEPRECATED|\bTEST\b'
$gameOnlyJunk = '(?i)test quest|test kill quest|do not use|^\[never used\]$|^REUSE$|\(123\)aa$|^Da Foo$'

$inClient = @{}
foreach ($row in Get-ClientTable 'QuestV2') { $inClient[[int]$row.ID] = $true }
$sortName = @{}; $areaParent = @{}; $areaMap = @{}
foreach ($row in Get-ClientTable 'AreaTable') {
    $sortName[[int]$row.ID] = $row.AreaName_lang
    $areaParent[[int]$row.ID] = [int]$row.ParentAreaID
    $areaMap[[int]$row.ID] = [int]$row.ContinentID
}
$raceName = @{}; foreach ($row in Get-ClientTable 'ChrRaces') { if ($row.Name_lang) { $raceName[$row.Name_lang] = $true } }
$placelessSort = @{ (-221) = $true }
foreach ($row in Get-ClientTable 'QuestSort') {
    $sortName[-[int]$row.ID] = $row.SortName_lang
    if ($raceName[$row.SortName_lang]) { $placelessSort[-[int]$row.ID] = $true }
}
$zoneAreas = @{}
foreach ($row in Get-ClientTable 'UiMapAssignment') { if ([int]$row.AreaID) { $zoneAreas[[int]$row.AreaID] = $true } }
$instanceMaps = @{}; $instanceArea = @{}
foreach ($map in (Get-ClientTable 'Map' | Where-Object { [int]$_.InstanceType -ge 1 -and [int]$_.InstanceType -le 4 } | Sort-Object { -[int]$_.AreaTableID }, { [int]$_.ID })) {
    $instanceMaps[[int]$map.ID] = $true
    if ($instanceArea.ContainsKey($map.MapName_lang)) { continue }
    $onMap = @($areaMap.Keys | Where-Object { $areaMap[$_] -eq [int]$map.ID -and -not $areaParent[$_] } | Sort-Object { $sortName[$_] -ne $map.MapName_lang }, { $_ })
    $own = if ($onMap.Count -and $sortName[$onMap[0]] -eq $map.MapName_lang) { $onMap[0] }
        elseif ($sortName.ContainsKey([int]$map.AreaTableID)) { [int]$map.AreaTableID } elseif ($onMap.Count) { $onMap[0] } else { $null }
    $instanceArea[$map.MapName_lang] = $own
}

# A quest filed under an outdoor area named after an instance (Gnomeregan in Dun Morogh) goes under
# the instance's own area, if it has one; one filed under any other subzone goes under its zone, or
# under the top area of its instance.
function Resolve-Category([int]$category) {
    if ($category -le 0) { return $category }
    $name = $sortName[$category]
    if (-not $instanceMaps[$areaMap[$category]] -and -not $zoneAreas[$category] -and $instanceArea.ContainsKey($name)) {
        if ($instanceArea[$name]) { return [int]$instanceArea[$name] }
        return $category
    }
    while ($areaParent[$category] -and $sortName.ContainsKey($areaParent[$category])) { $category = $areaParent[$category] }
    return $category
}
$storylineOf = @{}
foreach ($row in Get-ClientTable 'QuestLineXQuest') { $storylineOf[[int]$row.QuestID] = [int]$row.QuestLineID }
$uiMapType = @{}
foreach ($row in Get-ClientTable 'UiMap') { $uiMapType[[int]$row.ID] = [int]$row.Type }
$eraUiMaps = @{}
foreach ($row in Get-ClientTable 'UiMap' $EraBuild) { $eraUiMaps[[int]$row.ID] = $true }
$frames = @(Get-ClientTable 'UiMapAssignment' | Where-Object { $uiMapType[[int]$_.UiMapID] -ge 3 } | ForEach-Object {
    $minX = [double]$_.Region_0; $minY = [double]$_.Region_1; $maxX = [double]$_.Region_3; $maxY = [double]$_.Region_4
    [pscustomobject]@{ UiMap = [int]$_.UiMapID; Map = [int]$_.MapID; Zone = [int]$_.AreaID; New = -not $eraUiMaps[[int]$_.UiMapID]
        MinX = $minX; MinY = $minY; MaxX = $maxX; MaxY = $maxY
        U0 = [double]$_.UiMin_0; U1 = [double]$_.UiMin_1; V0 = [double]$_.UiMax_0; V1 = [double]$_.UiMax_1
        Area = ($maxX - $minX) * ($maxY - $minY) }
} | Sort-Object Area)
$uiMapArea = @{}; foreach ($frame in $frames) { if ($frame.Zone) { $uiMapArea[$frame.UiMap] = $frame.Zone } }

$cityMaps = @{ 1453 = $true; 1454 = $true; 1455 = $true; 1456 = $true; 1457 = $true; 1458 = $true }
$cityHeights = @{}
$oldPinSpots = @{}

# How far inside a frame a spawn stands: its distance to the nearest edge, as a share of the frame.
function Get-Centrality($frame, [double]$x, [double]$y) {
    $fx = ($frame.MaxY - $y) / ($frame.MaxY - $frame.MinY)
    $fy = ($frame.MaxX - $x) / ($frame.MaxX - $frame.MinX)
    return [Math]::Min([Math]::Min($fx, 1 - $fx), [Math]::Min($fy, 1 - $fy))
}

# Of the frames that hold a spawn, the map our old pins put most NPCs within 100 yards of it on.
function Get-NearbyOldPinMap($holding, [int]$map, [double]$x, [double]$y) {
    $votes = @{}
    $cellX = [Math]::Floor($x / 100); $cellY = [Math]::Floor($y / 100)
    foreach ($i in -1, 0, 1) {
        foreach ($j in -1, 0, 1) {
            foreach ($spot in $oldPinSpots["$map|$($cellX + $i)|$($cellY + $j)"]) {
                if (($spot.X - $x) * ($spot.X - $x) + ($spot.Y - $y) * ($spot.Y - $y) -gt 10000) { continue }
                foreach ($uiMap in $spot.UiMaps) { $votes[$uiMap] = 1 + [int]$votes[$uiMap] }
            }
        }
    }
    $best = $null; $bestVotes = 0
    foreach ($frame in $holding) { if ([int]$votes[$frame.UiMap] -gt $bestVotes) { $best = $frame; $bestVotes = [int]$votes[$frame.UiMap] } }
    return $best
}

# Of a giver's old pin maps whose frames hold a spawn, the one whose old pin stands nearest it. A
# giver found in several zones, such as the chickens, has an old pin in each, and their frames
# overlap: one in Westfall can be inside Elwynn Forest's too. The first map wins when no pin has a
# position.
function Select-NearestOldPinMap([int[]]$uiMaps, $pinsByMap, [int]$map, [double]$x, [double]$y) {
    $best = $uiMaps[0]; $bestDistance = [double]::MaxValue
    foreach ($uiMap in $uiMaps) {
        foreach ($point in $pinsByMap[$uiMap]) {
            if ($point.Map -ne $map) { continue }
            $distance = ($point.X - $x) * ($point.X - $x) + ($point.Y - $y) * ($point.Y - $y)
            if ($distance -lt $bestDistance) { $best = $uiMap; $bestDistance = $distance }
        }
    }
    return $best
}

# The map position of a CMaNGOS spawn: on -OnUiMap's frame if given. Otherwise the frames that hold
# it, of maps Classic Era had, are tried in this order:
#   1. a map -OldMaps has (our old Classic pins' maps for the giver), the one whose old pin stands
#      nearest the spawn when several do;
#   2. the map our old pins put most NPCs within 100 yards on;
#   3. a city whose old pins' NPCs stand within 50 yards of the spawn's height -Z;
#   4. one of -Zones (the zones the giver's quests are in);
#   5. the one the spawn stands furthest inside, with any within 0.05 of that counting as a tie that
#      the smallest wins.
# The old pins come first because the others guess wrong for a giver whose quests are filed under a
# neighbouring zone, like Tirion Fordring's. A frame is a rectangle, so a city's reaches past its
# walls: the height keeps the Darkmoon Faire at the foot of Thunder Bluff's mesa off the city's map.
function Convert-ToMapSpot([int]$map, [double]$x, [double]$y, $Zones = $null, $OldMaps = $null, [int]$OnUiMap = 0, [double]$Z = [double]::NaN) {
    $holding = @($frames | Where-Object { $_.Map -eq $map -and $x -ge $_.MinX -and $x -le $_.MaxX -and $y -ge $_.MinY -and $y -le $_.MaxY })
    if ($OnUiMap) {
        $chosen = $holding | Where-Object { $_.UiMap -eq $OnUiMap } | Select-Object -First 1
    } else {
        $old = @($holding | Where-Object { -not $_.New })
        $chosen = $null
        if ($OldMaps) {
            $oldPinned = @($old | Where-Object { $OldMaps.ContainsKey($_.UiMap) })
            if ($oldPinned.Count -gt 1) {
                $nearest = Select-NearestOldPinMap @($oldPinned | ForEach-Object { $_.UiMap }) $OldMaps $map $x $y
                $chosen = $oldPinned | Where-Object { $_.UiMap -eq $nearest } | Select-Object -First 1
            } else {
                $chosen = $oldPinned | Select-Object -First 1
            }
        }
        if (-not $chosen) { $chosen = Get-NearbyOldPinMap $old $map $x $y }
        if (-not $chosen) {
            $chosen = $old | Where-Object { $cityMaps.ContainsKey($_.UiMap) -and
                ([double]::IsNaN($Z) -or -not $cityHeights[$_.UiMap] -or ($Z -ge $cityHeights[$_.UiMap].Min - 50 -and $Z -le $cityHeights[$_.UiMap].Max + 50)) } | Select-Object -First 1
        }
        if (-not $chosen -and $Zones) { $chosen = $old | Where-Object { $Zones.ContainsKey($_.Zone) } | Select-Object -First 1 }
        if (-not $chosen -and $old.Count) {
            $deepest = ($old | ForEach-Object { Get-Centrality $_ $x $y } | Measure-Object -Maximum).Maximum
            $chosen = $old | Where-Object { (Get-Centrality $_ $x $y) -ge $deepest - 0.05 } | Select-Object -First 1
        }
    }
    if (-not $chosen) { return $null }
    $fx = ($chosen.MaxY - $y) / ($chosen.MaxY - $chosen.MinY)
    $fy = ($chosen.MaxX - $x) / ($chosen.MaxX - $chosen.MinX)
    return [pscustomobject]@{ UiMap = $chosen.UiMap
        X = [decimal][Math]::Round(100 * ($chosen.U0 + $fx * ($chosen.V0 - $chosen.U0)), 2)
        Y = [decimal][Math]::Round(100 * ($chosen.U1 + $fy * ($chosen.V1 - $chosen.U1)), 2) }
}

# Quest start points from the client's tables: a blob with objective index -1 marks where the quest is
# picked up. Its first point is used, as retail's pin tool does.
$firstPoint = @{}
foreach ($row in Get-ClientTable 'QuestPOIPoint') { if (-not $firstPoint.ContainsKey([int]$row.QuestPOIBlobID)) { $firstPoint[[int]$row.QuestPOIBlobID] = $row } }
$startSpots = @{}; $startOffMap = 0
foreach ($blob in (Get-ClientTable 'QuestPOIBlob' | Where-Object { $_.ObjectiveIndex -eq '-1' })) {
    $point = $firstPoint[[int]$blob.ID]
    if (-not $point) { continue }
    $spot = Convert-ToMapSpot ([int]$blob.MapID) ([double]$point.X) ([double]$point.Y) -OnUiMap ([int]$blob.UiMapID)
    if (-not $spot) { $startOffMap++; continue }
    $quest = [int]$blob.QuestID
    $near = $startSpots[$quest] | Where-Object { $_.UiMap -eq $spot.UiMap -and [Math]::Abs($_.X - $spot.X) -lt 3 -and [Math]::Abs($_.Y - $spot.Y) -lt 3 }
    if (-not $near) { $startSpots[$quest] += @($spot) }
}

$outputEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$sql = [IO.Path]::GetTempFileName()
try {
    $source = [IO.File]::OpenRead($CmangosDump)
    $gzip = New-Object System.IO.Compression.GZipStream($source, [IO.Compression.CompressionMode]::Decompress)
    $target = [IO.File]::Create($sql)
    $gzip.CopyTo($target)
    $target.Close(); $gzip.Close(); $source.Close()
    $dump = @{}
    foreach ($read in @(@('quest_template', '1,3,4,6,8,9,10,22,23,31,25,26,89,11'), @('creature_questrelation', '1,2'),
            @('gameobject_questrelation', '1,2'), @('creature', '1,2,3,5,6,7'), @('gameobject', '1,2,3,5,6,7'),
            @('creature_template', '1,2'), @('gameobject_template', '1,4'), @('item_template', '1,111'),
            @('game_event', '1,5,7'), @('game_event_quest', '1,2'), @('game_event_creature', '1,2'), @('game_event_gameobject', '1,2'))) {
        $dump[$read[0]] = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $sql $read[0] $read[1])
        if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $($read[0])" }
    }
    $probeLines = @(& $LuaExe "$PSScriptRoot\Read-ForeverProbe.lua" $ProbeFile)
    if ($LASTEXITCODE -ne 0) { throw "Read-ForeverProbe.lua failed on $ProbeFile" }
} finally {
    Remove-Item $sql -ErrorAction SilentlyContinue
    [Console]::OutputEncoding = $outputEncoding
}

$cmQuest = @{}
foreach ($line in $dump.quest_template) {
    $f = $line.Split("`t")
    $cmQuest[[int]$f[0]] = [pscustomobject]@{ Zone = [int]$f[1]; MinLevel = [int]$f[2]; Level = [int]$f[3]; Classes = [int]$f[4]
        Races = [int]$f[5]; Skill = [int]$f[6]; Special = [int]$f[7]; Prev = [int]$f[8]; Title = $f[9]; Group = [int]$f[10]; BreadcrumbFor = [int]$f[11]; Reputation = [int]$f[12] -ne 0
        SkillLevel = [int]$f[13] }
}
$creatureStarters = @{}; $objectStarters = @{}
foreach ($line in $dump.creature_questrelation) { $f = $line.Split("`t"); $creatureStarters[[int]$f[1]] += @([int]$f[0]) }
foreach ($line in $dump.gameobject_questrelation) { $f = $line.Split("`t"); $objectStarters[[int]$f[1]] += @([int]$f[0]) }
$starterNpcs = @{}; foreach ($list in $creatureStarters.Values) { foreach ($npc in $list) { $starterNpcs[$npc] = $true } }
$handStarters = @{}
foreach ($row in Import-Csv $GiverFile) { $handStarters[[int]$row.Quest] += @([int]$row.Npc); $starterNpcs[[int]$row.Npc] = $true }
$handZone = @{}; foreach ($row in Import-Csv $ZoneFile) { $handZone[[int]$row.Quest] = [int]$row.Zone }
$starterObjects = @{}; foreach ($list in $objectStarters.Values) { foreach ($object in $list) { $starterObjects[$object] = $true } }
$itemStart = @{}
foreach ($line in $dump.item_template) { $f = $line.Split("`t"); if ($f[1] -ne '0') { $itemStart[[int]$f[1]] = [int]$f[0] } }
$eventHoliday = @{}
foreach ($line in $dump.game_event) {
    $f = $line.Split("`t")
    $flag = $holidayByHolidayId[[int]$f[1]]
    if (-not $flag) { foreach ($name in $holidayByEventName.Keys) { if ($f[2] -match $name) { $flag = $holidayByEventName[$name]; break } } }
    if ($flag) { $eventHoliday[[int]$f[0]] = $flag }
}
$questHoliday = @{}
foreach ($line in $dump.game_event_quest) { $f = $line.Split("`t"); $flag = $eventHoliday[[int]$f[1]]; if ($flag) { $questHoliday[[int]$f[0]] = $flag } }
$spawnHoliday = @{}
foreach ($line in $dump.game_event_creature) { $f = $line.Split("`t"); $flag = $eventHoliday[[int]$f[1]]; if ($flag) { $spawnHoliday[[int]$f[0]] = $flag } }
$objectSpawnHoliday = @{}
foreach ($line in $dump.game_event_gameobject) { $f = $line.Split("`t"); $flag = $eventHoliday[[int]$f[1]]; if ($flag) { $objectSpawnHoliday[[int]$f[0]] = $flag } }
$oldPins = New-Object System.Collections.Generic.List[object]
# Each NPC's old pin maps, with where in the world each pin stands, from its map's frame.
$oldPinMaps = @{}
$mapId = 0
foreach ($line in (git -C $repoRoot show "a9bc11c^:QuestCompletist/qcPinDB.lua")) {
    if ($line -match '^\t\[(\d+)\] = \{') { $mapId = [int]$Matches[1]; continue }
    if ($mapId -lt 1411 -or $mapId -gt 1459 -or $line -notmatch '^\t\t\{\d+,(\d+),".*",([-0-9.]+),([-0-9.]+),\{([0-9,]*)\}') { continue }
    $npc = [int]$Matches[1]
    $oldPins.Add([pscustomobject]@{ UiMap = $mapId; Npc = $npc; X = [decimal]$Matches[2]; Y = [decimal]$Matches[3]
        Quests = @($Matches[4].Split(',') | Where-Object { $_ } | ForEach-Object { [int]$_ }) })
    if (-not $oldPinMaps.ContainsKey($npc)) { $oldPinMaps[$npc] = @{} }
    if (-not $oldPinMaps[$npc].ContainsKey($mapId)) { $oldPinMaps[$npc][$mapId] = @() }
    $frame = $frames | Where-Object { $_.UiMap -eq $mapId -and -not $_.New } | Select-Object -First 1
    if ($frame) {
        $fx = ([double]$Matches[2] / 100 - $frame.U0) / ($frame.V0 - $frame.U0)
        $fy = ([double]$Matches[3] / 100 - $frame.U1) / ($frame.V1 - $frame.U1)
        $oldPinMaps[$npc][$mapId] += @([pscustomobject]@{ Map = $frame.Map
            X = $frame.MaxX - $fy * ($frame.MaxX - $frame.MinX); Y = $frame.MaxY - $fx * ($frame.MaxY - $frame.MinY) })
    }
}
$npcSpawns = @{}; $npcHoliday = @{}; $oldPinNpcSpawns = @{}
foreach ($line in $dump.creature) {
    $f = $line.Split("`t")
    $npc = [int]$f[1]
    $spawn = [pscustomobject]@{ Map = [int]$f[2]; X = [double]$f[3]; Y = [double]$f[4]; Z = [double]$f[5] }
    if ($oldPinMaps.ContainsKey($npc)) { $oldPinNpcSpawns[$npc] += @($spawn) }
    if (-not $starterNpcs[$npc]) { continue }
    $npcSpawns[$npc] += @($spawn)
    $holiday = $spawnHoliday[[int]$f[0]]
    if (-not $npcHoliday.ContainsKey($npc)) { $npcHoliday[$npc] = $holiday } elseif ($npcHoliday[$npc] -ne $holiday) { $npcHoliday[$npc] = $null }
}
foreach ($npc in $oldPinNpcSpawns.Keys) {
    foreach ($spawn in $oldPinNpcSpawns[$npc]) {
        $maps = @($frames | Where-Object { $oldPinMaps[$npc].ContainsKey($_.UiMap) -and $_.Map -eq $spawn.Map -and
            $spawn.X -ge $_.MinX -and $spawn.X -le $_.MaxX -and $spawn.Y -ge $_.MinY -and $spawn.Y -le $_.MaxY } | Select-Object -ExpandProperty UiMap -Unique)
        if (-not $maps.Count) { continue }
        if ($maps.Count -gt 1) { $maps = @(Select-NearestOldPinMap $maps $oldPinMaps[$npc] $spawn.Map $spawn.X $spawn.Y) }
        $oldPinSpots["$($spawn.Map)|$([Math]::Floor($spawn.X / 100))|$([Math]::Floor($spawn.Y / 100))"] += @([pscustomobject]@{ X = $spawn.X; Y = $spawn.Y; UiMaps = $maps })
        foreach ($uiMap in ($maps | Where-Object { $cityMaps.ContainsKey($_) })) {
            $heights = $cityHeights[$uiMap]
            if (-not $heights) { $cityHeights[$uiMap] = [pscustomobject]@{ Min = $spawn.Z; Max = $spawn.Z }; continue }
            $heights.Min = [Math]::Min($heights.Min, $spawn.Z); $heights.Max = [Math]::Max($heights.Max, $spawn.Z)
        }
    }
}
$objectSpawns = @{}; $objectHoliday = @{}
foreach ($line in $dump.gameobject) {
    $f = $line.Split("`t")
    $object = [int]$f[1]
    if (-not $starterObjects[$object]) { continue }
    $objectSpawns[$object] += @([pscustomobject]@{ Map = [int]$f[2]; X = [double]$f[3]; Y = [double]$f[4]; Z = [double]$f[5] })
    $holiday = $objectSpawnHoliday[[int]$f[0]]
    if (-not $objectHoliday.ContainsKey($object)) { $objectHoliday[$object] = $holiday } elseif ($objectHoliday[$object] -ne $holiday) { $objectHoliday[$object] = $null }
}
$cmNpcName = @{}; foreach ($line in $dump.creature_template) { $f = $line.Split("`t"); if ($starterNpcs[[int]$f[0]]) { $cmNpcName[[int]$f[0]] = $f[1] } }
$objectName = @{}; foreach ($line in $dump.gameobject_template) { $f = $line.Split("`t"); if ($starterObjects[[int]$f[0]]) { $objectName[[int]$f[0]] = $f[1] } }

$cache = @{}
$cacheLines = [IO.File]::ReadAllLines($CacheFile)
foreach ($q in (('[' + ($cacheLines -join ',') + ']') | ConvertFrom-Json)) { $cache[[int]$q.id] = $q }
$probeResult = @{}; $gameNpcName = @{}; $recordedSpots = @{}; $recordedName = @{}; $recordedOffers = @{}
foreach ($line in $probeLines) {
    $f = $line.Split("`t")
    switch ($f[0]) {
        'quest' { if ($f[2] -eq $Build) { $probeResult[[int]$f[1]] = $f[3] } }
        'npc' { if ($f[2] -eq $Build -and $f[4]) { $gameNpcName[[int]$f[1]] = $f[4] } }
        'spot' {
            $parts = $f[4].Split(' ')
            if ($parts.Count -eq 3) {
                $key = "$($f[1]):$($f[2])"
                $recordedSpots[$key] += @([pscustomobject]@{ UiMap = [int]$parts[0]; X = [decimal]$parts[1]; Y = [decimal]$parts[2]; Seen = [int]$f[5] })
                if ($f[3]) { $recordedName[$key] = $f[3] }
            }
        }
        'offer' { $recordedOffers[[int]$f[3]] += @("$($f[1]):$($f[2])") }
    }
}

$review = New-Object System.Collections.Generic.List[object]
function Add-Review([string]$kind, $quest, $other, [string]$detail) {
    $review.Add([pscustomobject]@{ Kind = $kind; Quest = $quest; Other = $other; Detail = $detail })
}

$ids = @(@($cache.Keys) + @($cmQuest.Keys | Where-Object { $inClient[$_] -or ($cmQuest[$_].Special -band 1) }) | Sort-Object -Unique)
$records = @{}
$refiled = 0
$gameGivers = 0
foreach ($id in $ids) {
    $c = $cache[$id]; $m = $cmQuest[$id]
    $title = if ($c) { $c.title } else { $m.Title }
    if ($title -cmatch $internalTitle -or (-not $m -and $title -match $gameOnlyJunk)) { Add-Review 'left out: internal title' $id '' $title; continue }
    if (-not $c -and -not $inClient[$id] -and $probeResult[$id] -eq 'fail' -and $m.Level -ge 1 -and $m.Level -le 35) {
        Add-Review 'left out: failed on the beta below level 36' $id '' "$title (not in QuestV2)"
        continue
    }
    $category = if ($c -and [int]$c.sort) { [int]$c.sort } elseif ($m) { $m.Zone } else { 0 }
    if ($c -and -not [int]$c.sort -and $category) { Add-Review "no zone in the game's record, so CMaNGOS's" $id $category $title }
    if ($category -ne 0 -and -not $sortName.ContainsKey($category)) {
        Add-Review 'zone not in the client, so Uncategorized' $id $category $title
        $category = 0
    }
    $filedUnder = $category
    $category = Resolve-Category $category
    if ($category -ne $filedUnder) { $refiled++ }
    if ($c -and $m -and $sortName.ContainsKey($m.Zone) -and (Resolve-Category $m.Zone) -ne $category) {
        Add-Review 'zone differs from CMaNGOS' $id $m.Zone "$($sortName[$category]) / CMaNGOS: $($sortName[$m.Zone])"
    }
    if (-not $c) {
        if ($probeResult[$id] -eq 'fail' -and $m.Level -le 35) { Add-Review 'failed on the beta below level 36' $id '' $title }
        else { Add-Review 'not confirmed by the game yet' $id '' $title }
    }
    if (-not $inClient[$id]) {
        $cmangosSays = if (-not $m) { 'not in CMaNGOS' } elseif ($m.Special -band 1) { 'CMaNGOS: repeatable' } else { 'CMaNGOS: not repeatable' }
        Add-Review "not in the client's QuestV2" $id '' "$title ($cmangosSays)"
    }
    if ($c -and $c.giver) {
        $gameGivers++
        Add-Review 'giver named by the game' $id $c.giver "$title (CMaNGOS: $($creatureStarters[$id] -join ', '))"
    }

    $faction = 3; $race = 0
    if ($c -and $c.races) {
        foreach ($r in $c.races) { $race = $race -bor $raceBit[[int]$r] }
        $faction = if ($c.faction -eq 'Alliance') { 1 } elseif ($c.faction -eq 'Horde') { 2 } else { 3 }
    } elseif ($m -and $m.Races -and ($m.Races -band 255) -ne 255) {
        $races = $m.Races -band 255
        $faction = if (-not ($races -band $hordeRaces)) { 1 } elseif (-not ($races -band $allianceRaces)) { 2 } else { 3 }
        if (-not $c -and $races -ne $allianceRaces -and $races -ne $hordeRaces) { $race = $races }
    }
    $class = 8191
    if ($m -and $m.Classes) { $class = ($m.Classes -band 511) -bor $(if ($m.Classes -band 1024) { 512 } else { 0 }) }
    elseif ($classBySort.ContainsKey($category)) { $class = $classBySort[$category] }
    $skill = if ($m -and $m.Skill) { $m.Skill } elseif ($skillBySort.ContainsKey($category)) { $skillBySort[$category] } else { 0 }
    $profession = if ($professionBySkill.ContainsKey($skill)) { $professionBySkill[$skill] } else { 0 }
    $holiday = if ($questHoliday.ContainsKey($id)) { $questHoliday[$id] } elseif ($holidayBySort.ContainsKey($category)) { $holidayBySort[$category] } else { 0 }
    if (-not $holiday) {
        $flags = @(@(foreach ($npc in $creatureStarters[$id]) { if ($npcHoliday.ContainsKey($npc)) { [int]$npcHoliday[$npc] } }) +
            @(foreach ($object in $objectStarters[$id]) { if ($objectHoliday.ContainsKey($object)) { [int]$objectHoliday[$object] } }) | Sort-Object -Unique)
        if ($flags.Count -eq 1 -and $flags[0]) { $holiday = $flags[0] }
    }
    $recurs = if ($c) { $c.recurs } else { $null }
    $type = if ($recurs -eq 'daily') { 4 } elseif ($recurs -eq 'weekly') { 128 } elseif ($m -and ($m.Special -band 1)) { 2 }
        elseif ($holiday -or $category -eq $seasonalSort) { 64 } elseif ($profession) { 32 } else { 1 }

    $records[$id] = [pscustomobject]@{ id = $id; name = $title; level = $(if ($c) { [int]$c.level } else { $m.Level })
        zone = $(if ($sortName.ContainsKey($category)) { $sortName[$category] } else { '' }); category = $category
        type = $type; faction = $faction; race = $race; class = $class; profession = $profession; holiday = $holiday
        covenant = 0; storyline = $(if ($storylineOf.ContainsKey($id)) { $storylineOf[$id] } else { 0 }); prereq = 0 }
}

$previousByNext = @{}
foreach ($c in $cache.Values) { if ($c.nextQuest) { $previousByNext[[int]$c.nextQuest] += @([int]$c.id) } }
foreach ($q in $records.Values) {
    $m = $cmQuest[$q.id]
    if ($m -and $m.Prev -gt 0 -and $records.ContainsKey($m.Prev)) { $q.prereq = $m.Prev }
    elseif ($previousByNext[$q.id].Count -eq 1 -and $records.ContainsKey($previousByNext[$q.id][0])) { $q.prereq = $previousByNext[$q.id][0] }
}

$linkable = @{}
foreach ($q in $records.Values) { if (-not ($q.type -band (2 + 4 + 128))) { $linkable[$q.id] = $true } }
$breadcrumbs = @{}; $groups = @{}
foreach ($id in ($cmQuest.Keys | Sort-Object)) {
    if (-not $linkable[$id]) { continue }
    $m = $cmQuest[$id]
    if ($m.BreadcrumbFor -gt 0 -and $linkable[$m.BreadcrumbFor]) { $breadcrumbs[$m.BreadcrumbFor] += @($id) }
    if ($m.Group -gt 0) { $groups[$m.Group] += @($id) }
}
$exclusiveWith = @{}
$exclusiveGroups = 0
foreach ($members in $groups.Values) {
    if ($members.Count -lt 2) { continue }
    $exclusiveGroups++
    foreach ($id in $members) { $exclusiveWith[$id] = @($members | Where-Object { $_ -ne $id }) }
}
$linkLines = @(foreach ($id in (@($breadcrumbs.Keys) + @($exclusiveWith.Keys) | Sort-Object -Unique)) {
    $line = '{"quest":' + $id
    if ($breadcrumbs[$id]) { $line += ',"breadcrumbs":[' + ($breadcrumbs[$id] -join ',') + ']' }
    if ($exclusiveWith[$id]) { $line += ',"exclusiveWith":[' + ($exclusiveWith[$id] -join ',') + ']' }
    $line + '}'
})
$rewarding = 0; $cmangosOnlyReputation = 0
$reputationLines = @(foreach ($id in ($records.Keys | Sort-Object)) {
    $c = $cache[$id]
    if (-not $c) { if ($cmQuest[$id].Reputation) { $cmangosOnlyReputation++ }; continue }
    if ($null -eq $c.reputation) { continue }
    $rewarding++
    foreach ($reward in $c.reputation) {
        if ($reward -isnot [array] -or $reward.Count -ne 2) { throw "$CacheFile gives quest $id's reputation without amounts. Rerun Read-ForeverQuestCache.ps1." }
        '{"quest":' + $id + ',"faction":' + $reward[0] + ',"amount":' + $reward[1] + '}'
    }
})
# A required skill with no level (0) asks only that the character has learned it, as 1 does.
$skillLines = @(foreach ($id in ($records.Keys | Sort-Object)) {
    $m = $cmQuest[$id]
    if ($m -and $m.Skill) { '{"quest":' + $id + ',"skill":' + $m.Skill + ',"level":' + [Math]::Max(1, $m.SkillLevel) + '}' }
})

foreach ($npc in $gameNpcName.Keys) {
    if ($cmNpcName.ContainsKey($npc) -and $cmNpcName[$npc] -ne $gameNpcName[$npc]) { Add-Review 'NPC renamed' '' $npc "$($cmNpcName[$npc]) is now $($gameNpcName[$npc])" }
}

$giverZones = @{}
# Givers whose every quest recurs and isn't a holiday's: their pins show all year, done or not.
$everydayGivers = @{}
foreach ($q in $records.Values) {
    $keys = @($creatureStarters[$q.id] | ForEach-Object { "Creature:$_" }) + @($handStarters[$q.id] | Where-Object { $_ } | ForEach-Object { "Creature:$_" }) +
        @($objectStarters[$q.id] | ForEach-Object { "GameObject:$_" })
    foreach ($key in $keys) {
        $everyday = ($q.type -band (2 + 4 + 128)) -and -not $q.holiday
        $everydayGivers[$key] = $everyday -and (-not $everydayGivers.ContainsKey($key) -or $everydayGivers[$key])
        if ($q.category -le 0) { continue }
        if (-not $giverZones.ContainsKey($key)) { $giverZones[$key] = @{} }
        $giverZones[$key][$q.category] = $true
    }
}

function Get-GiverSpots([string]$kind, [int]$id) {
    $recorded = $recordedSpots["${kind}:$id"]
    if ($recorded) {
        $spots = @()
        foreach ($spot in ($recorded | Sort-Object { -$_.Seen }, UiMap, X, Y)) {
            $near = $spots | Where-Object { $_.UiMap -eq $spot.UiMap -and [Math]::Abs($_.X - $spot.X) -lt 3 -and [Math]::Abs($_.Y - $spot.Y) -lt 3 }
            if (-not $near) { $spots += $spot }
        }
        return $spots
    }
    $spawns = if ($kind -eq 'GameObject') { $objectSpawns[$id] } else { $npcSpawns[$id] }
    $spots = @()
    foreach ($spawn in $spawns) {
        $spot = Convert-ToMapSpot $spawn.Map $spawn.X $spawn.Y $giverZones["${kind}:$id"] $(if ($kind -ne 'GameObject') { $oldPinMaps[$id] }) -Z $spawn.Z
        if (-not $spot) { continue }
        $near = $spots | Where-Object { $_.UiMap -eq $spot.UiMap -and [Math]::Abs($_.X - $spot.X) -lt 3 -and [Math]::Abs($_.Y - $spot.Y) -lt 3 } | Select-Object -First 1
        if ($near) { $near.Spawns++ } else { $spots += ($spot | Add-Member -NotePropertyName Spawns -NotePropertyValue 1 -PassThru) }
    }
    if ($everydayGivers["${kind}:$id"] -and @($spots | Group-Object UiMap | Where-Object { $_.Count -gt 3 }).Count) {
        $spots = @($spots | Group-Object UiMap | ForEach-Object { $_.Group | Sort-Object { -$_.Spawns }, X, Y | Select-Object -First 1 })
    }
    return $spots
}

$pins = @{}
$spotCache = @{}
$startPinned = 0

function Add-StartPins([int]$id) {
    foreach ($spot in $startSpots[$id]) {
        $pinKey = "$($spot.UiMap)|Start|$($spot.X)|$($spot.Y)"
        if (-not $pins.ContainsKey($pinKey)) {
            $pins[$pinKey] = [pscustomobject]@{ map = $spot.UiMap; icon = 1; npc = 0; name = $null; x = $spot.X; y = $spot.Y
                quests = (New-Object System.Collections.Generic.List[int]); note = $null; Kind = 'Start'; GiverId = 0 }
        }
        $pins[$pinKey].quests.Add($id)
    }
}

foreach ($id in ($records.Keys | Sort-Object)) {
    $givers = New-Object System.Collections.Generic.List[string]
    foreach ($key in $recordedOffers[$id]) { if (-not $givers.Contains($key)) { $givers.Add($key) } }
    foreach ($npc in $creatureStarters[$id]) {
        $key = "Creature:$npc"
        if ($recordedOffers[$id] -and $recordedOffers[$id] -notcontains $key -and $recordedOffers[$id] -notcontains "Vehicle:$npc") {
            Add-Review 'recorder saw another giver' $id $npc "CMaNGOS: $($cmNpcName[$npc]); recorded: $($recordedOffers[$id] -join ', ')"
        }
        if (-not $givers.Contains($key)) { $givers.Add($key) }
    }
    foreach ($npc in $handStarters[$id]) {
        $key = "Creature:$npc"
        if ($recordedOffers[$id] -and $recordedOffers[$id] -notcontains $key -and $recordedOffers[$id] -notcontains "Vehicle:$npc") {
            Add-Review 'recorder saw another giver than the hand list' $id $npc "listed: $($cmNpcName[$npc]); recorded: $($recordedOffers[$id] -join ', ')"
            continue
        }
        if ($creatureStarters[$id] -or $objectStarters[$id]) { Add-Review "hand list adds to CMaNGOS's givers" $id $npc "$($records[$id].name): $($cmNpcName[$npc])" }
        if (-not $givers.Contains($key)) { $givers.Add($key) }
    }
    foreach ($object in $objectStarters[$id]) {
        $key = "GameObject:$object"
        if (-not $givers.Contains($key)) { $givers.Add($key) }
    }
    if ($givers.Count -eq 0) {
        $source = if (-not $cmQuest.ContainsKey($id)) { 'only the game knows it' } elseif ($itemStart.ContainsKey($id)) { "starts from item $($itemStart[$id])" } else { 'CMaNGOS has no giver' }
        if ($startSpots[$id]) {
            Add-StartPins $id
            $startPinned++
            Add-Review 'no giver: pin at its start point' $id '' "$($records[$id].name) ($source)"
        } else {
            Add-Review 'no giver' $id '' "$($records[$id].name) ($source)"
        }
        continue
    }
    $placed = New-Object System.Collections.Generic.List[object]
    foreach ($key in $givers) {
        $kind, $giverId = $key.Split(':')
        $giverId = [int]$giverId
        if (-not $spotCache.ContainsKey($key)) { $spotCache[$key] = @(Get-GiverSpots $kind $giverId) }
        foreach ($spot in $spotCache[$key]) {
            $isObject = $kind -eq 'GameObject'
            $pinKey = "$($spot.UiMap)|$key|$($spot.X)|$($spot.Y)"
            if (-not $pins.ContainsKey($pinKey)) {
                $name = if ($isObject) { if ($recordedName[$key]) { $recordedName[$key] } else { $objectName[$giverId] } }
                    elseif ($gameNpcName[$giverId]) { $gameNpcName[$giverId] } elseif ($recordedName[$key]) { $recordedName[$key] } else { $cmNpcName[$giverId] }
                $pins[$pinKey] = [pscustomobject]@{ map = $spot.UiMap; icon = 1; npc = $(if ($isObject) { 0 } else { $giverId })
                    name = $(if ($name) { $name } else { $null }); x = $spot.X; y = $spot.Y
                    quests = (New-Object System.Collections.Generic.List[int]); note = $null; Kind = $kind; GiverId = $giverId }
            }
            $pins[$pinKey].quests.Add($id)
            $placed.Add($pins[$pinKey])
        }
    }
    if (-not $placed.Count) {
        if ($startSpots[$id]) {
            Add-StartPins $id
            $startPinned++
            Add-Review 'giver not on a Forever map: pin at its start point' $id '' "$($records[$id].name) ($($givers -join ', '))"
        } else {
            Add-Review 'no pin: giver not on a Forever map' $id '' "$($records[$id].name) ($($givers -join ', '))"
        }
        continue
    }
    foreach ($spot in $startSpots[$id]) {
        $distances = @($placed | Where-Object { $_.map -eq $spot.UiMap } |
            ForEach-Object { [Math]::Sqrt([double](($_.x - $spot.X) * ($_.x - $spot.X) + ($_.y - $spot.Y) * ($_.y - $spot.Y))) })
        $closest = if ($distances.Count) { ($distances | Measure-Object -Minimum).Minimum } else { $null }
        if ($null -ne $closest -and $closest -le 3) { continue }
        $howFar = if ($null -eq $closest) { 'no pin of it on that map' } else { '{0:0.0} map points from its nearest pin' -f $closest }
        Add-Review "start point far from its giver's pin" $id '' ("{0}: start point on map {1} at {2} {3}, {4}" -f $records[$id].name, $spot.UiMap, $spot.X, $spot.Y, $howFar)
    }
}
foreach ($quest in $handStarters.Keys) { if (-not $records.ContainsKey($quest)) { Add-Review 'hand-listed quest not imported' $quest ($handStarters[$quest] -join ', ') '' } }

# A heading that isn't a place gives way to the hand-kept zone, else the zone of the quest's pins' map,
# the most pins first, else CMaNGOS's zone.
$refiledQuests = @{}
foreach ($q in @($records.Values | Where-Object { $placelessSort[$_.category] } | Sort-Object id)) {
    $refiledQuests[$q.id] = $true
    $heading = $sortName[$q.category]
    $zones = @($pins.Values | Where-Object { $_.quests.Contains($q.id) } | ForEach-Object { $uiMapArea[$_.map] } | Where-Object { $_ } |
        Group-Object | Sort-Object { -$_.Count }, { [int]$_.Name })
    $m = $cmQuest[$q.id]
    $listed = $handZone[$q.id]
    if ($listed -gt 0 -and $sortName.ContainsKey($listed)) { $zone = $listed; $kind = "heading isn't a place: hand-kept zone" }
    elseif ($zones.Count) { $zone = [int]$zones[0].Name; $kind = "heading isn't a place: its pins' zone" }
    elseif ($m -and $m.Zone -and $sortName.ContainsKey($m.Zone) -and -not $placelessSort[$m.Zone]) { $zone = $m.Zone; $kind = "heading isn't a place, no pin: CMaNGOS's zone" }
    else { $zone = 0; $kind = "heading isn't a place, no pin: Uncategorized" }
    if ($listed -and $zone -ne $listed) { Add-Review "hand-kept zone isn't an area in the client" $q.id $listed $q.name }
    $q.category = Resolve-Category $zone
    $q.zone = if ($sortName.ContainsKey($q.category)) { $sortName[$q.category] } else { '' }
    Add-Review $kind $q.id $q.category "$($q.name): $heading -> $(if ($q.zone) { $q.zone } else { 'Uncategorized' })"
}
foreach ($quest in $handZone.Keys) {
    if (-not $records.ContainsKey($quest)) { Add-Review 'hand-kept zone for a quest not imported' $quest $handZone[$quest] '' }
    elseif (-not $refiledQuests[$quest]) { Add-Review "hand-kept zone not used: the quest's heading is a place" $quest $handZone[$quest] $records[$quest].name }
}

foreach ($pin in $pins.Values) {
    $onPin = @($pin.quests | ForEach-Object { $records[$_] })
    $pin.icon = if (-not ($onPin | Where-Object { $_.type -ne 64 })) { 5 }
        elseif (-not ($onPin | Where-Object { -not $_.profession })) { 3 }
        elseif (-not ($onPin | Where-Object { $_.class -eq 8191 })) { 9 } else { 1 }
    $pin.quests = @($pin.quests | Sort-Object)
}

foreach ($key in $recordedSpots.Keys) {
    $kind, $giverId = $key.Split(':')
    $spawns = if ($kind -eq 'GameObject') { $objectSpawns[[int]$giverId] } else { $npcSpawns[[int]$giverId] }
    if (-not $spawns) { continue }
    foreach ($spot in $recordedSpots[$key]) {
        $same = @($spawns | ForEach-Object { Convert-ToMapSpot $_.Map $_.X $_.Y -OnUiMap $spot.UiMap } | Where-Object { $_ })
        if (-not $same) { continue }
        $closest = ($same | ForEach-Object { [Math]::Sqrt([double](($_.X - $spot.X) * ($_.X - $spot.X) + ($_.Y - $spot.Y) * ($_.Y - $spot.Y))) } | Measure-Object -Minimum).Minimum
        if ($closest -gt 1) { Add-Review 'recorded spot far from CMaNGOS' '' $key ("{0} at {1} {2}: {3:0.0} map points from CMaNGOS's spawn" -f $recordedName[$key], $spot.X, $spot.Y, $closest) }
    }
}

foreach ($old in $oldPins) {
    $npc = $old.Npc; $x = $old.X; $y = $old.Y; $mapId = $old.UiMap
    foreach ($quest in $old.Quests) {
        if (-not $records.ContainsKey($quest) -or -not $creatureStarters[$quest]) { continue }
        if ($creatureStarters[$quest] -notcontains $npc) {
            Add-Review 'old pin names another giver' $quest $npc "old pin: $npc; CMaNGOS: $($creatureStarters[$quest] -join ', ')"
        }
    }
    if (-not $npcSpawns[$npc]) { continue }
    $spots = @($npcSpawns[$npc] | ForEach-Object { Convert-ToMapSpot $_.Map $_.X $_.Y -OnUiMap $mapId } | Where-Object { $_ })
    if (-not $spots) { continue }
    $closest = ($spots | ForEach-Object { [Math]::Sqrt([double](($_.X - $x) * ($_.X - $x) + ($_.Y - $y) * ($_.Y - $y))) } | Measure-Object -Minimum).Minimum
    if ($closest -gt 3) { Add-Review 'old pin far from the giver' '' $npc ("{0} on map {1} at {2} {3}: {4:0.0} map points from CMaNGOS's spawn" -f $cmNpcName[$npc], $mapId, $x, $y, $closest) }
}

$review | Sort-Object Kind, { [int]("0" + $_.Quest) }, { "$($_.Other)" } |
    Export-Csv -Path $ReviewFile -NoTypeInformation -Encoding UTF8

$questList = @($records.Values | Sort-Object id)
$pinList = @($pins.Values | Sort-Object map, Kind, GiverId, x, y)
$fromBoth = @($questList | Where-Object { $cache.ContainsKey($_.id) -and $cmQuest.ContainsKey($_.id) }).Count
$fromGame = @($questList | Where-Object { $cache.ContainsKey($_.id) -and -not $cmQuest.ContainsKey($_.id) }).Count
Write-Host ("{0} quests: {1} from the game and CMaNGOS, {2} from the game only, {3} from CMaNGOS only. {4} pins on {5} maps." -f
    $questList.Count, $fromBoth, $fromGame, ($questList.Count - $fromBoth - $fromGame), $pinList.Count, @($pinList | Select-Object -ExpandProperty map -Unique).Count)
Write-Host ("{0} quests filed under a subzone or an instance's outdoor area are under their zone or instance." -f $refiled)
Write-Host ("Quests with a start point in the client's tables: {0} (ours: {1}; pinned there: {2}). Start points off their map: {3}. Quest records that name a giver: {4}." -f
    $startSpots.Count, @($startSpots.Keys | Where-Object { $records.ContainsKey($_) }).Count, $startPinned, $startOffMap, $gameGivers)
Write-Host ("Links: {0} breadcrumbs lead to {1} quests; {2} quests are in {3} groups of which only one can be done." -f
    @($breadcrumbs.Values | ForEach-Object { $_ }).Count, $breadcrumbs.Count, $exclusiveWith.Count, $exclusiveGroups)
Write-Host ("Reputation: {0} rewards on {1} quests, from the game's records. {2} quests the game hasn't answered reward reputation in CMaNGOS." -f
    $reputationLines.Count, $rewarding, $cmangosOnlyReputation)
Write-Host ("Skills: {0} quests need a profession, {1} of them a level above 1." -f
    $skillLines.Count, @($skillLines | Where-Object { $_ -notmatch '"level":1\}$' }).Count)
$review | Group-Object Kind | Sort-Object Name | ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Name, $_.Count) }
Write-Host "Review: $ReviewFile"
if ($WhatIf) { return }

$DataDir = (New-Item -ItemType Directory -Force $DataDir).FullName
$questPath = Join-Path $DataDir 'quests.jsonl'
$pinPath = Join-Path $DataDir 'pins.jsonl'
[IO.File]::WriteAllText($questPath, (ConvertTo-QuestJsonLines $questList), $Utf8)
[IO.File]::WriteAllText($pinPath, (ConvertTo-PinJsonLines $pinList), $Utf8)
$problems = @(Find-UnknownFields $questPath $QuestFields) + @(Test-QuestRecords (Read-JsonLines $questPath)) +
    @(Find-UnknownFields $pinPath $PinFields) + @(Test-PinRecords (Read-JsonLines $pinPath))
if ($problems.Count) { throw "The written files don't pass AddonData.ps1's checks: $(($problems | Select-Object -First 5) -join '; ')" }
$linkPath = Join-Path $DataDir 'links.jsonl'
$reputationPath = Join-Path $DataDir 'reputation.jsonl'
$skillPath = Join-Path $DataDir 'skills.jsonl'
[IO.File]::WriteAllText($linkPath, (($linkLines | ForEach-Object { "$_`n" }) -join ''), $Utf8)
[IO.File]::WriteAllText($reputationPath, (($reputationLines | ForEach-Object { "$_`n" }) -join ''), $Utf8)
[IO.File]::WriteAllText($skillPath, (($skillLines | ForEach-Object { "$_`n" }) -join ''), $Utf8)
Write-Host "Written: $questPath, $pinPath, $linkPath, $reputationPath, $skillPath"
