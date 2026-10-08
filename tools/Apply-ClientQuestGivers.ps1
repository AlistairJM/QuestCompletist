<#
Applies the quest givers the client's own data names to the retail pins. CollectableSourceQuestSparse
is the one client table that names a quest giver: for each quest whose reward has an appearance the
collections can show, the giver's creature ID and where it stands, as an instance and a world
position, one row per spawn (2,074 quests on build 12.1.0.69933; docs\plans\client-tables-review.md).
Blizzard's data over TrinityCore's wherever both speak.

For each such quest in data\quests.jsonl, against data\pins.jsonl:
  - A pin whose NPC ID is the client's giver agrees, and so does one whose NPC is the same character
    under another creature ID (the client and TrinityCore keep per-faction and phased copies, with the
    same English name). It's counted, and listed when no spawn stands within 3 map points of it: a
    giver stands in several places, and the pin may be at none.
  - A quest on a pin with another NPC moves to the giver's pin when a spawn of one of its givers stands
    within 1.5 map points of the pin, the pipeline's "same spot". The pipeline took each pin's NPC from
    a neighbour of the spot, so quests of several NPCs standing together often share one pin. The
    giver's pin is an existing pin of its own within 1.5 points, or a new one at the old pin's place;
    a pin left with no quest goes. A quest the client's table doesn't list moves the same way on
    TrinityCore's word: it lists other starters than the pin's NPC, one of them stands within 1.5
    points of the pin (by its own spawns, or the client's for a character of that name, as
    TrinityCore has few after Mists of Pandaria), and the pin's NPC isn't a starter of the quest.
  - A pin with no NPC ID takes the client's giver when one of its spawns stands within 3 map points of
    the pin and TrinityCore names no other starter, and the pin's other quests don't name a different
    giver there. A pin with no name needs the giver's name too, from TrinityCore's database (as
    Fill-PinNpcIds.ps1 reads it): without one it's only reported, because the addon reads a nameless
    pin with an ID as a quest the player gives themselves. A named pin keeps its name, and is reported
    instead when the database names the giver differently.
  - A quest with no pin gets one at the giver's spawn, on the smallest zone map (UiMap type 3,
    else the smallest dungeon or micro map) of its instance whose region holds the spawn, with the
    giver's name from TrinityCore. A giver's quests within 1.5 points of each other share the pin,
    and join an existing pin of that giver within 1.5 points. A spawn no map holds, and a giver
    the database doesn't name, are reported.
A giver that stands farther from the pin than that is listed, not acted on. The pins stand at the
client's start point of each quest (Build-QuestLocationData.ps1), and at its own point, the turn-in
when it ends elsewhere, for the few the client gives no start; so the giver may be one of several
places, or the pin may stand at the NPC who ends the quest (plans\quest-location-data-pipeline.md).

A listed case that was looked at and stays is recorded in docs\plans\pin-giver-decisions.csv (Quest, Map,
X and Y of its pin, Decision, NpcId, Reason), and later runs mark it kept and count only the new ones.
KEEP leaves it. MOVE gives the quest on that pin to the NPC in NpcId, and FILL gives a pin with no NPC
that NPC, for the cases the rules don't reach; a row whose quest has left the pin is stale and ignored.
WoW: Forever's pins aren't touched: its importer places them from CMaNGOS.

Reads tools\CollectableSourceQuestSparse.csv (downloaded for -Build when it's missing or with
-Refresh), tools\UiMapAssignment.csv and tools\UiMap.csv (step 6 downloads them), and the newest
tools\tdb\TDB_full_world_*.sql (maintenance.md, "Before a sweep"). With -WhatIf it only reports;
otherwise it saves through AddonData.ps1, which rebuilds the Lua. Then rerun the pin pipeline
(maintenance.md, step 6): a pin that now shares its ID with another pin of that NPC within 1.5
points joins it at the next rebuild. A second run changes nothing.

  .\Apply-ClientQuestGivers.ps1 -WhatIf
  .\Apply-ClientQuestGivers.ps1
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = "12.1.0.69933",
    [string]$TdbFile = "",
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [string]$ReportFile = (Join-Path $PSScriptRoot 'client-giver-report.txt'),
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\pin-giver-decisions.csv'),
    [switch]$Refresh,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. "$PSScriptRoot\AddonData.ps1"

$sameSpot = 1.5
$farFromPin = 3
$nearPin = 3

function Get-PlaceKey($map, $x, $y) {
    $format = '0.############################'
    return "$map|$(([decimal]$x).ToString($format, $script:Invariant))|$(([decimal]$y).ToString($format, $script:Invariant))"
}

$sourceCsv = "$ToolsDir\CollectableSourceQuestSparse.csv"
if ($Refresh -or -not (Test-Path $sourceCsv)) {
    Write-Output "Downloading CollectableSourceQuestSparse..."
    Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/CollectableSourceQuestSparse/csv?build=$Build" -OutFile $sourceCsv
}

if (-not $TdbFile) {
    $TdbFile = Get-ChildItem "$ToolsDir\tdb\TDB_full_world_*.sql" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $TdbFile) { throw "No tools\tdb\TDB_full_world_*.sql: see maintenance.md, 'Before a sweep'." }
Write-Output "Reading creature names from $(Split-Path $TdbFile -Leaf)..."
$outputEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [Text.Encoding]::UTF8
try { $rows = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $TdbFile 'creature_template' '1,4') } finally { [Console]::OutputEncoding = $outputEncoding }
if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $TdbFile (creature_template)" }
$creatureName = @{}
foreach ($row in $rows) { $f = $row.Split("`t"); $creatureName[$f[0]] = $f[1].Trim() }

# TrinityCore's creatures that start quests, and where they stand: the second source, for the quests
# the client's table doesn't list.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
try { $rows = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $TdbFile 'creature_queststarter' '1,2') } finally { [Console]::OutputEncoding = $outputEncoding }
if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $TdbFile (creature_queststarter)" }
$starters = @{}
foreach ($row in $rows) {
    $f = $row.Split("`t")
    if (-not $starters.ContainsKey($f[1])) { $starters[$f[1]] = New-Object System.Collections.Generic.List[string] }
    $starters[$f[1]].Add($f[0])
}
$startsQuests = New-Object System.Collections.Generic.HashSet[string]
foreach ($list in $starters.Values) { foreach ($id in $list) { [void]$startsQuests.Add($id) } }
[Console]::OutputEncoding = [Text.Encoding]::UTF8
try { $rows = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $TdbFile 'creature' '2,3,13,14') } finally { [Console]::OutputEncoding = $outputEncoding }
if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $TdbFile (creature)" }
$tcSpawns = @{}
foreach ($row in $rows) {
    $f = $row.Split("`t")
    if (-not $startsQuests.Contains($f[0])) { continue }
    if (-not $tcSpawns.ContainsKey($f[0])) { $tcSpawns[$f[0]] = New-Object System.Collections.Generic.List[object] }
    $tcSpawns[$f[0]].Add(@{ Giver = [int]$f[0]; Instance = $f[1]; X = [double]$f[2]; Y = [double]$f[3] })
}

# The reviewed cases: the ones that stay, by quest and place, with the reason, and the moves and fills
# the rules don't reach.
$kept = @{}
$decided = New-Object System.Collections.Generic.HashSet[string]
$moveDecisions = New-Object System.Collections.Generic.List[object]
if (Test-Path $DecisionsFile) {
    foreach ($row in (Import-Csv $DecisionsFile -Encoding UTF8)) {
        if ($row.Decision -eq 'KEEP') { $kept["$($row.Quest)|$(Get-PlaceKey $row.Map $row.X $row.Y)"] = $row.Reason }
        elseif ($row.Decision -eq "MOVE" -or $row.Decision -eq "FILL") { $moveDecisions.Add($row); [void]$decided.Add("$($row.Quest)|$(Get-PlaceKey $row.Map $row.X $row.Y)") }
        else { throw "${DecisionsFile}: unknown decision '$($row.Decision)' for quest $($row.Quest)" }
    }
}

# The pin pipeline's conversion of a world position to a map's percentages (Build-QuestLocationData.ps1).
function Convert-WorldToMapPercent($worldX, $worldY, $region) {
    $r0 = [double]$region.Region_0; $r1 = [double]$region.Region_1; $r3 = [double]$region.Region_3; $r4 = [double]$region.Region_4
    $fx = ($r4 - $worldY) / ($r4 - $r1); $fy = ($r3 - $worldX) / ($r3 - $r0)
    $uMin0 = [double]$region.UiMin_0; $uMin1 = [double]$region.UiMin_1; $uMax0 = [double]$region.UiMax_0; $uMax1 = [double]$region.UiMax_1
    return @{ X = [math]::Round(($uMin0 + $fx * ($uMax0 - $uMin0)) * 100, 2); Y = [math]::Round(($uMin1 + $fy * ($uMax1 - $uMin1)) * 100, 2) }
}
function Test-Inside($worldX, $worldY, $region) {
    return $worldX -ge [double]$region.Region_0 -and $worldX -le [double]$region.Region_3 -and $worldY -ge [double]$region.Region_1 -and $worldY -le [double]$region.Region_4
}
# Where a spawn falls on a given map, or $null when none of the map's regions holds it.
function Convert-ToMap($spawn, $mapId) {
    if (-not $regionsByMap.ContainsKey($mapId)) { return $null }
    $fallback = $null
    foreach ($region in $regionsByMap[$mapId]) {
        if (-not (Test-Inside $spawn.X $spawn.Y $region)) { continue }
        if ($region.MapID -eq $spawn.Instance) { return Convert-WorldToMapPercent $spawn.X $spawn.Y $region }
        if (-not $fallback) { $fallback = $region }
    }
    if ($fallback) { return Convert-WorldToMapPercent $spawn.X $spawn.Y $fallback }
    return $null
}
# The map a new pin for a spawn goes on: the smallest zone map of the spawn's instance whose region
# holds it, else the smallest dungeon or micro map.
function Find-MapForSpawn($spawn) {
    $best = $null; $bestArea = 0; $bestZone = $false
    foreach ($region in $regionsByInstance[[string]$spawn.Instance]) {
        $type = $uiMapType[$region.UiMapID]
        if ($type -lt 3 -or -not (Test-Inside $spawn.X $spawn.Y $region)) { continue }
        $zone = $type -eq 3
        $area = ([double]$region.Region_3 - [double]$region.Region_0) * ([double]$region.Region_4 - [double]$region.Region_1)
        if (-not $best -or ($zone -and -not $bestZone) -or ($zone -eq $bestZone -and $area -lt $bestArea)) { $best = $region; $bestArea = $area; $bestZone = $zone }
    }
    if (-not $best) { return $null }
    $at = Convert-WorldToMapPercent $spawn.X $spawn.Y $best
    return @{ Map = [int]$best.UiMapID; X = $at.X; Y = $at.Y }
}
function Get-Distance($ax, $ay, $bx, $by) {
    $dx = [double]$ax - [double]$bx; $dy = [double]$ay - [double]$by
    return [math]::Sqrt($dx * $dx + $dy * $dy)
}
# The nearest of a quest's spawns to a pin, on the pin's map: the giver and the distance, or $null.
function Find-NearestSpawn($spawns, $pin) {
    $best = $null
    foreach ($spawn in $spawns) {
        $at = Convert-ToMap $spawn ([string]$pin.map)
        if (-not $at) { continue }
        $d = Get-Distance $at.X $at.Y $pin.x $pin.y
        if (-not $best -or $d -lt $best.Distance) { $best = @{ Giver = $spawn.Giver; Distance = $d } }
    }
    return $best
}

$uiMapType = @{}
foreach ($row in Import-Csv "$ToolsDir\UiMap.csv") { $uiMapType[$row.ID] = [int]$row.Type }
$regionsByMap = @{}; $regionsByInstance = @{}
foreach ($region in Import-Csv "$ToolsDir\UiMapAssignment.csv") {
    if (-not $regionsByMap.ContainsKey($region.UiMapID)) { $regionsByMap[$region.UiMapID] = New-Object System.Collections.Generic.List[object] }
    $regionsByMap[$region.UiMapID].Add($region)
    if (-not $regionsByInstance.ContainsKey($region.MapID)) { $regionsByInstance[$region.MapID] = New-Object System.Collections.Generic.List[object] }
    $regionsByInstance[$region.MapID].Add($region)
}

$quests = @{}
foreach ($quest in (Read-QuestData $DataDir)) { $quests[[string]$quest.id] = $quest }
$pins = Read-PinData $DataDir
$pinsOfQuest = @{}
foreach ($pin in $pins) {
    foreach ($questId in $pin.quests) {
        if (-not $pinsOfQuest.ContainsKey([string]$questId)) { $pinsOfQuest[[string]$questId] = New-Object System.Collections.Generic.List[object] }
        $pinsOfQuest[[string]$questId].Add($pin)
    }
}

$spawnsOfQuest = @{}
$notOurs = New-Object System.Collections.Generic.HashSet[string]
$seen = New-Object System.Collections.Generic.HashSet[string]
# Where the client puts each character, by name, whatever quest it lists it for: positions for
# TrinityCore's starters that have none of their own (it has few spawns after Mists of Pandaria).
$spawnsByName = @{}
$spawnSeen = New-Object System.Collections.Generic.HashSet[string]
foreach ($row in Import-Csv $sourceCsv) {
    $giverName = $creatureName[[string]$row.QuestGiverCreatureID]
    if ($giverName -and $spawnSeen.Add("$($row.QuestGiverCreatureID)|$($row.QuestMapID)|$($row.QuestPosition_0)|$($row.QuestPosition_1)")) {
        if (-not $spawnsByName.ContainsKey($giverName)) { $spawnsByName[$giverName] = New-Object System.Collections.Generic.List[object] }
        $spawnsByName[$giverName].Add(@{ Giver = [int]$row.QuestGiverCreatureID; Instance = $row.QuestMapID; X = [double]$row.QuestPosition_0; Y = [double]$row.QuestPosition_1 })
    }
    if (-not $quests.ContainsKey($row.QuestID)) { [void]$notOurs.Add($row.QuestID); continue }
    if (-not $seen.Add("$($row.QuestID)|$($row.QuestGiverCreatureID)|$($row.QuestMapID)|$($row.QuestPosition_0)|$($row.QuestPosition_1)")) { continue }
    if (-not $spawnsOfQuest.ContainsKey($row.QuestID)) { $spawnsOfQuest[$row.QuestID] = New-Object System.Collections.Generic.List[object] }
    $spawnsOfQuest[$row.QuestID].Add(@{ Giver = [int]$row.QuestGiverCreatureID; Instance = $row.QuestMapID; X = [double]$row.QuestPosition_0; Y = [double]$row.QuestPosition_1 })
}

function Describe-Pin($pin) { return "map $($pin.map) at $($pin.x),$($pin.y): $(if ($null -ne $pin.name) { $pin.name } else { '(no name)' })" + $(if ($pin.npc) { " [$($pin.npc)]" } else { '' }) }
function Describe-Quest($questId) { return "$questId `"$($quests[$questId].name)`"" }
function Describe-Giver($id) { return "$id" + $(if ($creatureName.ContainsKey([string]$id)) { " $($creatureName[[string]$id])" } else { '' }) }

# Whether an NPC is one of the givers, or the same character under another creature ID: the client and
# TrinityCore keep per-faction and phased copies of a character, with the same English name.
function Test-SameCharacter($npc, $giverIds) {
    if ($giverIds -contains [int]$npc) { return $true }
    $name = $creatureName[[string]$npc]
    if (-not $name) { return $false }
    foreach ($id in $giverIds) { if ($creatureName[[string]$id] -ceq $name) { return $true } }
    return $false
}
function Add-Unplaced($list, $questId, $pin, $text) {
    $list.Add(@{ Key = "$questId|$(Get-PlaceKey $pin.map $pin.x $pin.y)"; Text = $text })
}

$agree = 0
$agreeFar = New-Object System.Collections.Generic.List[string]
$otherId = New-Object System.Collections.Generic.List[object]
$idlessFar = New-Object System.Collections.Generic.List[object]
$moves = New-Object System.Collections.Generic.List[object]
$fills = @{}
$pinless = New-Object System.Collections.Generic.List[object]
foreach ($questId in ($spawnsOfQuest.Keys | Sort-Object { [int]$_ })) {
    $spawns = $spawnsOfQuest[$questId]
    $givers = @($spawns | ForEach-Object { $_.Giver } | Sort-Object -Unique)
    if (-not $pinsOfQuest.ContainsKey($questId)) {
        foreach ($spawn in $spawns) { $pinless.Add(@{ Quest = $questId; Spawn = $spawn }) }
        continue
    }
    $questPins = $pinsOfQuest[$questId]
    $same = @($questPins | Where-Object { $_.npc -and (Test-SameCharacter $_.npc $givers) })
    if ($same.Count -gt 0) {
        $agree++
        $nearest = $null
        foreach ($pin in $same) { $n = Find-NearestSpawn $spawns $pin; if ($n -and (-not $nearest -or $n.Distance -lt $nearest.Distance)) { $nearest = $n } }
        if (-not $nearest) { $agreeFar.Add("$(Describe-Quest $questId): no spawn of $(($givers | ForEach-Object { Describe-Giver $_ }) -join ', ') on the pin's map, $(Describe-Pin $same[0])") }
        elseif ($nearest.Distance -gt $farFromPin) { $agreeFar.Add("$(Describe-Quest $questId): nearest spawn $([math]::Round($nearest.Distance, 1)) points from $(Describe-Pin $same[0])") }
        continue
    }
    $withId = @($questPins | Where-Object { $_.npc })
    if ($withId.Count -gt 0) {
        # Several NPCs can stand at one spot, and the pin took the identity of one of them: a giver of
        # the quest standing within 1.5 points of the pin takes the quest to a pin of its own.
        foreach ($pin in $withId) {
            $n = Find-NearestSpawn $spawns $pin
            if ($n -and $n.Distance -le $sameSpot -and $creatureName.ContainsKey([string]$n.Giver)) {
                $moves.Add(@{ Quest = $questId; Pin = $pin; Giver = $n.Giver; Distance = $n.Distance; Source = "the client's table" })
            } else {
                $where = if ($n) { "nearest spawn $([math]::Round($n.Distance, 1)) points away" } else { "no spawn on the pin's map" }
                Add-Unplaced $otherId $questId $pin "$(Describe-Quest $questId): $(Describe-Pin $pin); the client's giver is $(($givers | ForEach-Object { Describe-Giver $_ }) -join ' or '), $where"
            }
        }
        continue
    }
    foreach ($pin in $questPins) {
        $n = Find-NearestSpawn $spawns $pin
        $contradicted = $n -and $starters.ContainsKey($questId) -and -not $starters[$questId].Contains([string]$n.Giver)
        if ($n -and $n.Distance -le $nearPin -and -not $contradicted) {
            if (-not $fills.ContainsKey($pin)) { $fills[$pin] = New-Object System.Collections.Generic.List[object] }
            $fills[$pin].Add(@{ Quest = $questId; Giver = $n.Giver; Distance = $n.Distance })
        } else {
            $where = if ($n) { "nearest spawn $([math]::Round($n.Distance, 1)) points away" } else { "no spawn on the pin's map" }
            if ($contradicted) { $where += ", and TrinityCore names another starter" }
            Add-Unplaced $idlessFar $questId $pin "$(Describe-Quest $questId): $(Describe-Pin $pin); the client's giver $(($givers | ForEach-Object { Describe-Giver $_ }) -join ' or ') has its $where"
        }
    }
}

# The quests the client's table doesn't list, on pins with an NPC: when TrinityCore lists other starters
# than the pin's NPC and one stands within 1.5 points of the pin, the quest goes to it.
$tcElsewhere = 0
foreach ($pin in $pins) {
    if (-not $pin.npc) { continue }
    foreach ($questId in $pin.quests) {
        $qs = [string]$questId
        if ($spawnsOfQuest.ContainsKey($qs) -or -not $starters.ContainsKey($qs)) { continue }
        $startIds = @($starters[$qs] | ForEach-Object { [int]$_ })
        if (Test-SameCharacter $pin.npc $startIds) { continue }
        $best = $null
        foreach ($id in $startIds) {
            if (-not $creatureName.ContainsKey([string]$id)) { continue }
            $pool = New-Object System.Collections.Generic.List[object]
            if ($tcSpawns.ContainsKey([string]$id)) { $pool.AddRange($tcSpawns[[string]$id]) }
            if ($spawnsByName.ContainsKey($creatureName[[string]$id])) { $pool.AddRange($spawnsByName[$creatureName[[string]$id]]) }
            if ($pool.Count -eq 0) { continue }
            $n = Find-NearestSpawn $pool $pin
            if ($n -and (-not $best -or $n.Distance -lt $best.Distance)) { $best = $n }
        }
        if ($best -and $best.Distance -le $sameSpot) { $moves.Add(@{ Quest = $qs; Pin = $pin; Giver = $best.Giver; Distance = $best.Distance; Source = 'TrinityCore' }) }
        else { $tcElsewhere++ }
    }
}

# Reviewed moves the rules don't reach: a MOVE row names the giver that a quest on the pin at that place
# belongs to. One whose quest has left the pin, or whose pin already has that character, is stale.
$pinsAt = @{}
foreach ($pin in $pins) {
    $key = Get-PlaceKey $pin.map $pin.x $pin.y
    if (-not $pinsAt.ContainsKey($key)) { $pinsAt[$key] = New-Object System.Collections.Generic.List[object] }
    $pinsAt[$key].Add($pin)
}
foreach ($row in $moveDecisions) {
    $qid = [int]$row.Quest; $giver = [int]$row.NpcId
    $found = $null
    $key = Get-PlaceKey $row.Map $row.X $row.Y
    if ($pinsAt.ContainsKey($key)) { foreach ($candidate in $pinsAt[$key]) { if (@($candidate.quests) -contains $qid) { $found = $candidate; break } } }
    if (-not $found -or ($found.npc -and (Test-SameCharacter $found.npc @($giver)))) { continue }
    if (-not $creatureName.ContainsKey([string]$giver)) { throw "${DecisionsFile}: NPC $giver has no name in the database (quest $qid)" }
    if ($row.Decision -eq 'FILL') {
        if ($found.npc) { continue }
        if (-not $fills.ContainsKey($found)) { $fills[$found] = New-Object System.Collections.Generic.List[object] }
        $fills[$found].Add(@{ Quest = [string]$qid; Giver = $giver; Distance = 0.0 })
        continue
    }
    $already = $false
    foreach ($m in $moves) { if ($m.Pin -eq $found -and [int]$m.Quest -eq $qid) { $already = $true } }
    if (-not $already) { $moves.Add(@{ Quest = [string]$qid; Pin = $found; Giver = $giver; Distance = 0.0; Source = 'a decision' }) }
}

$filled = New-Object System.Collections.Generic.List[string]
$fillConflicts = New-Object System.Collections.Generic.List[string]
$fillNameless = New-Object System.Collections.Generic.List[string]
$fillRenamed = New-Object System.Collections.Generic.List[object]
foreach ($pin in @($fills.Keys)) {
    $matches = $fills[$pin]
    $giverIds = @($matches | ForEach-Object { $_.Giver } | Sort-Object -Unique)
    $place = Describe-Pin $pin
    if ($giverIds.Count -gt 1) {
        $fillConflicts.Add("${place}: its quests name different givers there, " + (($matches | ForEach-Object { "$(Describe-Giver $_.Giver) for $($_.Quest)" }) -join '; '))
        continue
    }
    $giver = $giverIds[0]
    $name = $creatureName[[string]$giver]
    if ($null -eq $pin.name) {
        if (-not $name) { $fillNameless.Add("${place}: giver $giver has no name in the database (quests $(($matches | ForEach-Object { $_.Quest }) -join ', '))"); continue }
        Set-RecordField $pin 'name' $name
    } elseif ($name -and $name -cne $pin.name.Trim()) {
        Add-Unplaced $fillRenamed $matches[0].Quest $pin "${place}: the client's giver $giver is `"$name`" in the database (quests $(($matches | ForEach-Object { $_.Quest }) -join ', '))"
        continue
    }
    Set-RecordField $pin 'npc' $giver
    $filled.Add("$place -> $(Describe-Giver $giver), $(($matches | ForEach-Object { "$($_.Quest) at $([math]::Round($_.Distance, 1))" }) -join ', ') points")
}

$pinsByMap = @{}
foreach ($pin in $pins) { if (-not $pinsByMap.ContainsKey([int]$pin.map)) { $pinsByMap[[int]$pin.map] = New-Object System.Collections.Generic.List[object] }; $pinsByMap[[int]$pin.map].Add($pin) }
$newPins = New-Object System.Collections.Generic.List[object]

# Moves: a quest leaves the pin that took a neighbour's identity for a pin of the giver at the same spot,
# an existing pin of that giver within 1.5 points or a new one at the old pin's place. A pin left with
# no quest goes.
$movedLines = New-Object System.Collections.Generic.List[string]
$emptied = New-Object System.Collections.Generic.HashSet[object]
$moveGroups = [ordered]@{}
foreach ($m in $moves) {
    $key = "$(Get-PlaceKey $m.Pin.map $m.Pin.x $m.Pin.y)|$($m.Pin.npc)|$($m.Giver)"
    if (-not $moveGroups.Contains($key)) { $moveGroups[$key] = @{ Pin = $m.Pin; Giver = $m.Giver; Items = New-Object System.Collections.Generic.List[object] } }
    $moveGroups[$key].Items.Add($m)
}
foreach ($group in $moveGroups.Values) {
    $pin = $group.Pin; $giver = $group.Giver
    $questList = @($group.Items | ForEach-Object { [int]$_.Quest } | Sort-Object -Unique)
    $place = Describe-Pin $pin
    Set-RecordField $pin 'quests' ([int[]]@($pin.quests | Where-Object { $questList -notcontains [int]$_ }))
    if (@($pin.quests).Count -eq 0) { [void]$emptied.Add($pin) }
    $target = $null
    foreach ($candidate in $pinsByMap[[int]$pin.map]) {
        if ($candidate -ne $pin -and $candidate.npc -and [int]$candidate.npc -eq $giver -and (Get-Distance $candidate.x $candidate.y $pin.x $pin.y) -le $sameSpot) { $target = $candidate; break }
    }
    if ($target) {
        Set-RecordField $target 'quests' ([int[]]@(@($target.quests) + @($questList | Where-Object { @($target.quests) -notcontains $_ })))
    } else {
        $target = [pscustomobject][ordered]@{
            map = [int]$pin.map; icon = $pin.icon; npc = [int]$giver; name = $creatureName[[string]$giver]
            x = $pin.x; y = $pin.y; quests = [int[]]$questList; note = $null
        }
        $newPins.Add($target)
        $pinsByMap[[int]$pin.map].Add($target)
    }
    $detail = ($group.Items | ForEach-Object { "$(Describe-Quest ([string]$_.Quest)) ($($_.Source)$(if ($_.Source -ne 'a decision') { ", $([math]::Round($_.Distance, 1)) points" }))" }) -join ', '
    $movedLines.Add("$place -> $(Describe-Giver $giver): $detail")
}

# New pins: a giver's spawns within 1.5 points of each other on one map share a pin, and join an
# existing pin of that giver there.
$added = New-Object System.Collections.Generic.List[string]
$joined = New-Object System.Collections.Generic.List[string]
$offMap = New-Object System.Collections.Generic.List[string]
$newNameless = New-Object System.Collections.Generic.List[string]
$clusters = New-Object System.Collections.Generic.List[object]
foreach ($entry in $pinless) {
    $at = Find-MapForSpawn $entry.Spawn
    if (-not $at) { $offMap.Add("$(Describe-Quest $entry.Quest): giver $(Describe-Giver $entry.Spawn.Giver) at $($entry.Spawn.X),$($entry.Spawn.Y) on instance $($entry.Spawn.Instance), which no map holds"); continue }
    $cluster = $null
    foreach ($c in $clusters) {
        if ($c.Giver -eq $entry.Spawn.Giver -and $c.Map -eq $at.Map -and (Get-Distance $c.X $c.Y $at.X $at.Y) -le $sameSpot) { $cluster = $c; break }
    }
    if (-not $cluster) {
        $cluster = @{ Giver = $entry.Spawn.Giver; Map = $at.Map; X = $at.X; Y = $at.Y; Quests = New-Object System.Collections.Generic.List[int] }
        $clusters.Add($cluster)
    }
    if (-not $cluster.Quests.Contains([int]$entry.Quest)) { $cluster.Quests.Add([int]$entry.Quest) }
}
foreach ($cluster in $clusters) {
    $existing = $null
    if ($pinsByMap.ContainsKey($cluster.Map)) {
        foreach ($pin in $pinsByMap[$cluster.Map]) {
            if ($pin.npc -and [int]$pin.npc -eq $cluster.Giver -and (Get-Distance $pin.x $pin.y $cluster.X $cluster.Y) -le $sameSpot) { $existing = $pin; break }
        }
    }
    $questList = @($cluster.Quests | Sort-Object)
    if ($existing) {
        $new = @($questList | Where-Object { $existing.quests -notcontains $_ })
        if ($new.Count -eq 0) { continue }
        Set-RecordField $existing 'quests' ([int[]](@($existing.quests) + $new))
        $joined.Add("$(Describe-Pin $existing) gets $(($new | ForEach-Object { Describe-Quest "$_" }) -join ', ')")
        continue
    }
    $name = $creatureName[[string]$cluster.Giver]
    if (-not $name) { $newNameless.Add("giver $($cluster.Giver) at map $($cluster.Map) $($cluster.X),$($cluster.Y) has no name in the database: $(($questList | ForEach-Object { Describe-Quest "$_" }) -join ', ')"); continue }
    $icon = 1
    if (@($questList | Where-Object { -not $quests["$_"].profession }).Count -eq 0) { $icon = 3 }
    $pin = [pscustomobject][ordered]@{
        map = [int]$cluster.Map; icon = $icon; npc = [int]$cluster.Giver; name = $name
        x = [decimal]$cluster.X; y = [decimal]$cluster.Y; quests = [int[]]$questList; note = $null
    }
    $newPins.Add($pin)
    $added.Add("$(Describe-Pin $pin): $(($questList | ForEach-Object { Describe-Quest "$_" }) -join ', ')")
}
# Each new pin goes after its map's last pin, so the file stays map by map.
$ordered = New-Object System.Collections.Generic.List[object]
$ordered.AddRange([object[]]@($pins | Where-Object { -not $emptied.Contains($_) }))
foreach ($pin in ($newPins | Sort-Object { $_.map }, { $_.quests[0] })) {
    $at = -1
    for ($i = $ordered.Count - 1; $i -ge 0; $i--) { if ([int]$ordered[$i].map -le $pin.map) { $at = $i; break } }
    $ordered.Insert($at + 1, $pin)
}

$report = New-Object System.Collections.Generic.List[string]
function Add-ReviewSection($title, $items) {
    $items = @($items | Where-Object { -not $decided.Contains($_.Key) })
    $new = @($items | Where-Object { -not $kept.ContainsKey($_.Key) }).Count
    $report.Add("$($items.Count) $title$(if ($new -ne $items.Count) { " ($new new)" })")
    foreach ($item in $items) { $report.Add("  $($item.Text)$(if ($kept.ContainsKey($item.Key)) { "  [kept: $($kept[$item.Key])]" })") }
    $report.Add("")
}
$report.Add("Apply-ClientQuestGivers.ps1 on CollectableSourceQuestSparse ($Build) and $(Split-Path $TdbFile -Leaf), $(Get-Date -Format 'yyyy-MM-dd')")
$report.Add("$($spawnsOfQuest.Count) quests with a giver in the client's data are ours; $($notOurs.Count) aren't.")
$report.Add("")
$report.Add("$agree quests have a pin with the client's giver as its NPC ID; $($agreeFar.Count) of those pins have no spawn within $farFromPin points:")
foreach ($line in $agreeFar) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($filled.Count) pins with no NPC ID take the client's giver, standing within $nearPin points:")
foreach ($line in $filled) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($fillNameless.Count) nameless pins would take a giver the database doesn't name (look up by hand):")
foreach ($line in $fillNameless) { $report.Add("  $line") }
$report.Add("")
Add-ReviewSection "named pins whose giver the database names differently (review):" $fillRenamed
$report.Add("$($fillConflicts.Count) pins whose quests name different givers:")
foreach ($line in $fillConflicts) { $report.Add("  $line") }
$report.Add("")
Add-ReviewSection "pins with no NPC ID that stay as they are, as no spawn of the client's giver stands within $nearPin points of them, or TrinityCore names another starter (review):" $idlessFar
$report.Add("$($movedLines.Count) pins give quests to the giver that stands at the same spot: the client's table or TrinityCore names a giver of the quest within $sameSpot points, and the pin's NPC isn't that character:")
foreach ($line in $movedLines) { $report.Add("  $line") }
$report.Add("")
Add-ReviewSection "quests on a pin whose NPC isn't a giver of theirs, with no giver standing within $sameSpot points of the pin (review):" $otherId
$report.Add("TrinityCore also lists other starters than the pin's NPC for $tcElsewhere quests the client's table doesn't have, with none within $sameSpot points: left alone.")
$report.Add("")
$report.Add("$($added.Count) pins added for quests that had none:")
foreach ($line in $added) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($joined.Count) existing pins of the giver that quests without a pin joined:")
foreach ($line in $joined) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($newNameless.Count) givers of quests without a pin that the database doesn't name (look up by hand):")
foreach ($line in $newNameless) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($offMap.Count) spawns of quests without a pin that no map holds:")
foreach ($line in $offMap) { $report.Add("  $line") }
[IO.File]::WriteAllLines($ReportFile, $report)

$unplaced = @(($otherId + $idlessFar + $fillRenamed) | Where-Object { -not $decided.Contains($_.Key) })
$unplacedNew = @($unplaced | Where-Object { -not $kept.ContainsKey($_.Key) }).Count
Write-Output "$agree quests agree with the client ($($agreeFar.Count) pins far from every spawn); $($filled.Count) pins get an ID; $($movedLines.Count) pins give quests to the giver at the same spot ($($emptied.Count) pins left empty go); $($added.Count) pins added and $($joined.Count) joined for quests without one; $($unplaced.Count) quests or pins left to review, $unplacedNew of them new."
Write-Output "Report: $ReportFile"
if ($WhatIf) { Write-Output "WhatIf: nothing changed."; exit 0 }
if ($filled.Count + $added.Count + $joined.Count + $movedLines.Count -gt 0) { Save-PinData $ordered $DataDir $AddonDir }
