<#
Builds WoW: Forever's quest and pin data, data\forever\quests.jsonl and pins.jsonl, from four sources
(docs/plans/forever.md, phase 3):

  - the client's QuestV2 table for -Build: which quests exist;
  - the quest cache file Read-ForeverQuestCache.ps1 writes: what the server says about each quest it
    answered;
  - CMaNGOS's vanilla database (cmangos/classic-db, Full_DB, GPL-3.0): the old world, including the
    quests the beta didn't answer, and who starts each quest and where they stand;
  - the beta probe's saved variables: which quests failed, the game's NPC names, and the recorder's
    quest givers and spots.

The game wins wherever it speaks. Title, level, zone, recurrence and race restrictions come from the
cache when it has the quest, a recorded spot wins over CMaNGOS's for that giver, and NPC names come
from the probe. A quest's givers are CMaNGOS's and the recorder's together. Quests with internal
titles ("<UNUSED>", "[DNT]" and the like, and test quests only the game knows) are left out, as are
CMaNGOS quests the client doesn't have.

The files follow data\quests.jsonl and pins.jsonl (see AddonData.ps1), with Forever's values:
  category  Blizzard's own: the zone's AreaTable ID, or the negative QuestSort ID for class,
            profession, holiday and Forever's other headings; 0 for none, or for an area the
            client's AreaTable doesn't have. zone is its name.
  faction   1 Alliance, 2 Horde, 3 both: from the cache's race restriction, or CMaNGOS's.
  race      0 for any race, since faction already gates; otherwise the addon's race bits, with
            Skyborne (races 95 and 96) as 67108864.
  class     the addon's class bits, from CMaNGOS or a class heading; 8191 for any.
  type      64 seasonal, 4 daily, 128 weekly, 32 profession, 2 repeatable or 1, the first that
            applies. holiday and profession hold the addon's flags.
  prereq    CMaNGOS's previous quest, or the quest whose follow-up this is in the cache.
Pins are CMaNGOS's spawns of each quest's NPC or object givers, converted to map positions with the
client's UiMapAssignment (the smallest zone frame that holds the spot), or the recorder's spots for the
givers it saw. Givers inside dungeons get no pin.

Anything worth a look goes to -ReviewFile, one row per finding; the summary counts them. With -WhatIf,
only the review is written.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data\forever'),
    [string]$Build = "1.60.1.70205",
    [string]$CacheFile = "",
    [string]$ProbeFile = "",
    [string]$CmangosDump = "",
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

function Get-ClientTable([string]$table) {
    $path = "$ToolsDir\$table-$Build.csv"
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path
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
    341 = 256; 181 = 512; 404 = 1024; 398 = 2048; 691 = 4096; 479 = 8192; 374 = 8192; 375 = 8192; 376 = 8192 }
$holidayBySort = @{ (-364) = 8192; (-366) = 128; (-369) = 256 }
$seasonalSort = -22
$allianceRaces = 77
$hordeRaces = 178
$internalTitle = '^<|UNUSED|\[DNT\]|\(DNT\)|\[PH\]|^ZZ|\bNYI\b|DEPRECATED|\bTEST\b'
$gameOnlyJunk = '(?i)test quest|test kill quest|do not use|^\[never used\]$|^REUSE$|\(123\)aa$|^Da Foo$'

$inClient = @{}
foreach ($row in Get-ClientTable 'QuestV2') { $inClient[[int]$row.ID] = $true }
$sortName = @{}
foreach ($row in Get-ClientTable 'AreaTable') { $sortName[[int]$row.ID] = $row.AreaName_lang }
foreach ($row in Get-ClientTable 'QuestSort') { $sortName[-[int]$row.ID] = $row.SortName_lang }
$storylineOf = @{}
foreach ($row in Get-ClientTable 'QuestLineXQuest') { $storylineOf[[int]$row.QuestID] = [int]$row.QuestLineID }
$uiMapType = @{}
foreach ($row in Get-ClientTable 'UiMap') { $uiMapType[[int]$row.ID] = [int]$row.Type }
$frames = @(Get-ClientTable 'UiMapAssignment' | Where-Object { $uiMapType[[int]$_.UiMapID] -ge 3 } | ForEach-Object {
    $minX = [double]$_.Region_0; $minY = [double]$_.Region_1; $maxX = [double]$_.Region_3; $maxY = [double]$_.Region_4
    [pscustomobject]@{ UiMap = [int]$_.UiMapID; Map = [int]$_.MapID; MinX = $minX; MinY = $minY; MaxX = $maxX; MaxY = $maxY
        U0 = [double]$_.UiMin_0; U1 = [double]$_.UiMin_1; V0 = [double]$_.UiMax_0; V1 = [double]$_.UiMax_1
        Area = ($maxX - $minX) * ($maxY - $minY) }
} | Sort-Object Area)

function Convert-ToMapSpot([int]$map, [double]$x, [double]$y) {
    foreach ($frame in $frames) {
        if ($frame.Map -ne $map -or $x -lt $frame.MinX -or $x -gt $frame.MaxX -or $y -lt $frame.MinY -or $y -gt $frame.MaxY) { continue }
        $fx = ($frame.MaxY - $y) / ($frame.MaxY - $frame.MinY)
        $fy = ($frame.MaxX - $x) / ($frame.MaxX - $frame.MinX)
        return [pscustomobject]@{ UiMap = $frame.UiMap
            X = [decimal][Math]::Round(100 * ($frame.U0 + $fx * ($frame.V0 - $frame.U0)), 2)
            Y = [decimal][Math]::Round(100 * ($frame.U1 + $fy * ($frame.V1 - $frame.U1)), 2) }
    }
    return $null
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
    foreach ($read in @(@('quest_template', '1,3,4,6,8,9,10,22,23,31'), @('creature_questrelation', '1,2'),
            @('gameobject_questrelation', '1,2'), @('creature', '1,2,3,5,6'), @('gameobject', '1,2,3,5,6'),
            @('creature_template', '1,2'), @('gameobject_template', '1,4'), @('item_template', '1,111'),
            @('game_event', '1,5'), @('game_event_quest', '1,2'), @('game_event_creature', '1,2'))) {
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
        Races = [int]$f[5]; Skill = [int]$f[6]; Special = [int]$f[7]; Prev = [int]$f[8]; Title = $f[9] }
}
$creatureStarters = @{}; $objectStarters = @{}
foreach ($line in $dump.creature_questrelation) { $f = $line.Split("`t"); $creatureStarters[[int]$f[1]] += @([int]$f[0]) }
foreach ($line in $dump.gameobject_questrelation) { $f = $line.Split("`t"); $objectStarters[[int]$f[1]] += @([int]$f[0]) }
$starterNpcs = @{}; foreach ($list in $creatureStarters.Values) { foreach ($npc in $list) { $starterNpcs[$npc] = $true } }
$starterObjects = @{}; foreach ($list in $objectStarters.Values) { foreach ($object in $list) { $starterObjects[$object] = $true } }
$itemStart = @{}
foreach ($line in $dump.item_template) { $f = $line.Split("`t"); if ($f[1] -ne '0') { $itemStart[[int]$f[1]] = [int]$f[0] } }
$eventHoliday = @{}
foreach ($line in $dump.game_event) { $f = $line.Split("`t"); $flag = $holidayByHolidayId[[int]$f[1]]; if ($flag) { $eventHoliday[[int]$f[0]] = $flag } }
$questHoliday = @{}
foreach ($line in $dump.game_event_quest) { $f = $line.Split("`t"); $flag = $eventHoliday[[int]$f[1]]; if ($flag) { $questHoliday[[int]$f[0]] = $flag } }
$spawnHoliday = @{}
foreach ($line in $dump.game_event_creature) { $f = $line.Split("`t"); $flag = $eventHoliday[[int]$f[1]]; if ($flag) { $spawnHoliday[[int]$f[0]] = $flag } }
$npcSpawns = @{}; $npcHoliday = @{}
foreach ($line in $dump.creature) {
    $f = $line.Split("`t")
    $npc = [int]$f[1]
    if (-not $starterNpcs[$npc]) { continue }
    $npcSpawns[$npc] += @([pscustomobject]@{ Map = [int]$f[2]; X = [double]$f[3]; Y = [double]$f[4] })
    $holiday = $spawnHoliday[[int]$f[0]]
    if (-not $npcHoliday.ContainsKey($npc)) { $npcHoliday[$npc] = $holiday } elseif ($npcHoliday[$npc] -ne $holiday) { $npcHoliday[$npc] = $null }
}
$objectSpawns = @{}
foreach ($line in $dump.gameobject) {
    $f = $line.Split("`t")
    $object = [int]$f[1]
    if ($starterObjects[$object]) { $objectSpawns[$object] += @([pscustomobject]@{ Map = [int]$f[2]; X = [double]$f[3]; Y = [double]$f[4] }) }
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

$ids = @(@($cache.Keys) + @($cmQuest.Keys | Where-Object { $inClient[$_] }) | Sort-Object -Unique)
$records = @{}
foreach ($id in $ids) {
    $c = $cache[$id]; $m = $cmQuest[$id]
    $title = if ($c) { $c.title } else { $m.Title }
    if ($title -cmatch $internalTitle -or (-not $m -and $title -match $gameOnlyJunk)) { Add-Review 'left out: internal title' $id '' $title; continue }
    $category = if ($c) { [int]$c.sort } else { $m.Zone }
    if ($category -ne 0 -and -not $sortName.ContainsKey($category)) {
        Add-Review 'zone not in the client, so Uncategorized' $id $category $title
        $category = 0
    }
    if ($c -and $m -and $m.Zone -ne $category) { Add-Review 'zone differs from CMaNGOS' $id $m.Zone "$($sortName[$category]) / CMaNGOS: $($sortName[$m.Zone])" }
    if (-not $c) {
        if ($probeResult[$id] -eq 'fail' -and $m.Level -le 35) { Add-Review 'failed on the beta below level 36' $id '' $title }
        else { Add-Review 'not confirmed by the game yet' $id '' $title }
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
    if (-not $holiday -and $creatureStarters[$id]) {
        $flags = @($creatureStarters[$id] | ForEach-Object { $npcHoliday[$_] } | Sort-Object -Unique)
        if ($flags.Count -eq 1 -and $flags[0]) { $holiday = $flags[0] }
    }
    $recurs = if ($c) { $c.recurs } else { $null }
    $type = if ($holiday -or $category -eq $seasonalSort) { 64 } elseif ($recurs -eq 'daily') { 4 } elseif ($recurs -eq 'weekly') { 128 }
        elseif ($profession) { 32 } elseif ($m -and ($m.Special -band 1)) { 2 } else { 1 }

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

foreach ($npc in $gameNpcName.Keys) {
    if ($cmNpcName.ContainsKey($npc) -and $cmNpcName[$npc] -ne $gameNpcName[$npc]) { Add-Review 'NPC renamed' '' $npc "$($cmNpcName[$npc]) is now $($gameNpcName[$npc])" }
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
        $spot = Convert-ToMapSpot $spawn.Map $spawn.X $spawn.Y
        if (-not $spot) { continue }
        $near = $spots | Where-Object { $_.UiMap -eq $spot.UiMap -and [Math]::Abs($_.X - $spot.X) -lt 3 -and [Math]::Abs($_.Y - $spot.Y) -lt 3 }
        if (-not $near) { $spots += $spot }
    }
    return $spots
}

$pins = @{}
$spotCache = @{}
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
    foreach ($object in $objectStarters[$id]) {
        $key = "GameObject:$object"
        if (-not $givers.Contains($key)) { $givers.Add($key) }
    }
    if ($givers.Count -eq 0) {
        $source = if (-not $cmQuest.ContainsKey($id)) { 'only the game knows it' } elseif ($itemStart.ContainsKey($id)) { "starts from item $($itemStart[$id])" } else { 'CMaNGOS has no giver' }
        Add-Review 'no giver' $id '' "$($records[$id].name) ($source)"
        continue
    }
    $placed = $false
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
            $placed = $true
        }
    }
    if (-not $placed) { Add-Review 'no pin: giver not on a Forever map' $id '' "$($records[$id].name) ($($givers -join ', '))" }
}

foreach ($pin in $pins.Values) {
    $onPin = @($pin.quests | ForEach-Object { $records[$_] })
    $pin.icon = if (-not ($onPin | Where-Object { $_.type -ne 64 })) { 5 }
        elseif (-not ($onPin | Where-Object { $_.type -ne 32 })) { 3 }
        elseif (-not ($onPin | Where-Object { $_.class -eq 8191 })) { 9 } else { 1 }
    $pin.quests = @($pin.quests | Sort-Object)
}

foreach ($key in $recordedSpots.Keys) {
    $kind, $giverId = $key.Split(':')
    $spawns = if ($kind -eq 'GameObject') { $objectSpawns[[int]$giverId] } else { $npcSpawns[[int]$giverId] }
    if (-not $spawns) { continue }
    $cmSpots = @($spawns | ForEach-Object { Convert-ToMapSpot $_.Map $_.X $_.Y } | Where-Object { $_ })
    foreach ($spot in $recordedSpots[$key]) {
        $same = @($cmSpots | Where-Object { $_.UiMap -eq $spot.UiMap })
        if (-not $same) { continue }
        $closest = ($same | ForEach-Object { [Math]::Sqrt([double](($_.X - $spot.X) * ($_.X - $spot.X) + ($_.Y - $spot.Y) * ($_.Y - $spot.Y))) } | Measure-Object -Minimum).Minimum
        if ($closest -gt 1) { Add-Review 'recorded spot far from CMaNGOS' '' $key ("{0} at {1} {2}: {3:0.0} map points from CMaNGOS's spawn" -f $recordedName[$key], $spot.X, $spot.Y, $closest) }
    }
}

$oldPins = git -C $repoRoot show "a9bc11c^:QuestCompletist/qcPinDB.lua"
$mapId = 0
foreach ($line in $oldPins) {
    if ($line -match '^\t\[(\d+)\] = \{') { $mapId = [int]$Matches[1]; continue }
    if ($mapId -lt 1411 -or $mapId -gt 1459 -or $line -notmatch '^\t\t\{\d+,(\d+),".*",([-0-9.]+),([-0-9.]+),\{([0-9,]*)\}') { continue }
    $npc = [int]$Matches[1]; $x = [decimal]$Matches[2]; $y = [decimal]$Matches[3]
    foreach ($quest in ($Matches[4].Split(',') | Where-Object { $_ } | ForEach-Object { [int]$_ })) {
        if (-not $records.ContainsKey($quest) -or -not $creatureStarters[$quest]) { continue }
        if ($creatureStarters[$quest] -notcontains $npc) {
            Add-Review 'old pin names another giver' $quest $npc "old pin: $npc; CMaNGOS: $($creatureStarters[$quest] -join ', ')"
        }
    }
    if (-not $npcSpawns[$npc]) { continue }
    $spots = @($npcSpawns[$npc] | ForEach-Object { Convert-ToMapSpot $_.Map $_.X $_.Y } | Where-Object { $_ -and $_.UiMap -eq $mapId })
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
Write-Host "Written: $questPath, $pinPath"
