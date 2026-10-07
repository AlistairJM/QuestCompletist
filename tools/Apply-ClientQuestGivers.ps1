<#
Applies the quest givers the client's own data names to the retail pins. CollectableSourceQuestSparse
is the one client table that names a quest giver: for each quest whose reward has an appearance the
collections can show, the giver's creature ID and where it stands, as an instance and a world
position, one row per spawn (2,074 quests on build 12.1.0.69933; docs\plans\client-tables-review.md).
Blizzard's data over TrinityCore's wherever both speak.

For each such quest in data\quests.jsonl, against data\pins.jsonl:
  - A pin whose NPC ID is the client's giver agrees. It's counted, and listed when no spawn stands
    within 3 map points of it: a giver stands in several places, and the pin may be at none.
  - A pin with no NPC ID takes the client's giver when one of its spawns stands within 1.5 map
    points of the pin, the pipeline's "same spot", and the pin's other quests don't name a
    different giver there. A pin with no name needs the giver's name too, from TrinityCore's
    database (as Fill-PinNpcIds.ps1 reads it): without one it's only reported, because the addon
    reads a nameless pin with an ID as a quest the player gives themselves. A named pin keeps its
    name, and is reported instead when the database names the giver differently.
  - A pin with another NPC ID is reported for review, with the nearest spawn's distance: within
    1.5 points it's the same spot, and Blizzard's ID is another version of the character.
  - A quest with no pin gets one at the giver's spawn, on the smallest zone map (UiMap type 3,
    else the smallest dungeon or micro map) of its instance whose region holds the spawn, with the
    giver's name from TrinityCore. A giver's quests within 1.5 points of each other share the pin,
    and join an existing pin of that giver within 1.5 points. A spawn no map holds, and a giver
    the database doesn't name, are reported.
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
    [switch]$Refresh,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. "$PSScriptRoot\AddonData.ps1"

$sameSpot = 1.5
$farFromPin = 3

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
foreach ($row in Import-Csv $sourceCsv) {
    if (-not $quests.ContainsKey($row.QuestID)) { [void]$notOurs.Add($row.QuestID); continue }
    if (-not $seen.Add("$($row.QuestID)|$($row.QuestGiverCreatureID)|$($row.QuestMapID)|$($row.QuestPosition_0)|$($row.QuestPosition_1)")) { continue }
    if (-not $spawnsOfQuest.ContainsKey($row.QuestID)) { $spawnsOfQuest[$row.QuestID] = New-Object System.Collections.Generic.List[object] }
    $spawnsOfQuest[$row.QuestID].Add(@{ Giver = [int]$row.QuestGiverCreatureID; Instance = $row.QuestMapID; X = [double]$row.QuestPosition_0; Y = [double]$row.QuestPosition_1 })
}

function Describe-Pin($pin) { return "map $($pin.map) at $($pin.x),$($pin.y): $(if ($null -ne $pin.name) { $pin.name } else { '(no name)' })" + $(if ($pin.npc) { " [$($pin.npc)]" } else { '' }) }
function Describe-Quest($questId) { return "$questId `"$($quests[$questId].name)`"" }
function Describe-Giver($id) { return "$id" + $(if ($creatureName.ContainsKey([string]$id)) { " $($creatureName[[string]$id])" } else { '' }) }

$agree = 0
$agreeFar = New-Object System.Collections.Generic.List[string]
$otherId = New-Object System.Collections.Generic.List[string]
$idlessFar = New-Object System.Collections.Generic.List[string]
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
    $same = @($questPins | Where-Object { $_.npc -and $givers -contains [int]$_.npc })
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
        $n = Find-NearestSpawn $spawns $withId[0]
        $where = if ($n) { "nearest spawn $([math]::Round($n.Distance, 1)) points away" } else { "no spawn on the pin's map" }
        $otherId.Add("$(Describe-Quest $questId): $(Describe-Pin $withId[0]); the client's giver is $(($givers | ForEach-Object { Describe-Giver $_ }) -join ' or '), $where")
        continue
    }
    foreach ($pin in $questPins) {
        $n = Find-NearestSpawn $spawns $pin
        if ($n -and $n.Distance -le $sameSpot) {
            if (-not $fills.ContainsKey($pin)) { $fills[$pin] = New-Object System.Collections.Generic.List[object] }
            $fills[$pin].Add(@{ Quest = $questId; Giver = $n.Giver; Distance = $n.Distance })
        } else {
            $where = if ($n) { "nearest spawn $([math]::Round($n.Distance, 1)) points away" } else { "no spawn on the pin's map" }
            $idlessFar.Add("$(Describe-Quest $questId): $(Describe-Pin $pin); the client's giver $(($givers | ForEach-Object { Describe-Giver $_ }) -join ' or ') has its $where")
        }
    }
}

$filled = New-Object System.Collections.Generic.List[string]
$fillConflicts = New-Object System.Collections.Generic.List[string]
$fillNameless = New-Object System.Collections.Generic.List[string]
$fillRenamed = New-Object System.Collections.Generic.List[string]
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
        $fillRenamed.Add("${place}: the client's giver $giver is `"$name`" in the database (quests $(($matches | ForEach-Object { $_.Quest }) -join ', '))")
        continue
    }
    Set-RecordField $pin 'npc' $giver
    $filled.Add("$place -> $(Describe-Giver $giver), $(($matches | ForEach-Object { "$($_.Quest) at $([math]::Round($_.Distance, 1))" }) -join ', ') points")
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
$pinsByMap = @{}
foreach ($pin in $pins) { if (-not $pinsByMap.ContainsKey([int]$pin.map)) { $pinsByMap[[int]$pin.map] = New-Object System.Collections.Generic.List[object] }; $pinsByMap[[int]$pin.map].Add($pin) }
$newPins = New-Object System.Collections.Generic.List[object]
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
$ordered.AddRange([object[]]$pins)
foreach ($pin in ($newPins | Sort-Object { $_.map }, { $_.quests[0] })) {
    $at = -1
    for ($i = $ordered.Count - 1; $i -ge 0; $i--) { if ([int]$ordered[$i].map -le $pin.map) { $at = $i; break } }
    $ordered.Insert($at + 1, $pin)
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add("Apply-ClientQuestGivers.ps1 on CollectableSourceQuestSparse ($Build) and $(Split-Path $TdbFile -Leaf), $(Get-Date -Format 'yyyy-MM-dd')")
$report.Add("$($spawnsOfQuest.Count) quests with a giver in the client's data are ours; $($notOurs.Count) aren't.")
$report.Add("")
$report.Add("$agree quests have a pin with the client's giver as its NPC ID; $($agreeFar.Count) of those pins have no spawn within $farFromPin points:")
foreach ($line in $agreeFar) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($filled.Count) pins with no NPC ID take the client's giver, standing within $sameSpot points:")
foreach ($line in $filled) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($fillNameless.Count) nameless pins would take a giver the database doesn't name (look up by hand):")
foreach ($line in $fillNameless) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($fillRenamed.Count) named pins whose giver the database names differently (look up by hand):")
foreach ($line in $fillRenamed) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($fillConflicts.Count) pins whose quests name different givers:")
foreach ($line in $fillConflicts) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($idlessFar.Count) pins with no NPC ID and no spawn of the client's giver within $sameSpot points:")
foreach ($line in $idlessFar) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($otherId.Count) pins whose NPC ID isn't the client's giver (review; within $sameSpot points it's the same spot under another ID):")
foreach ($line in $otherId) { $report.Add("  $line") }
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

Write-Output "$agree quests agree with the client ($($agreeFar.Count) pins far from every spawn); $($filled.Count) pins get an ID; $($added.Count) pins added and $($joined.Count) joined for quests without one; $($otherId.Count) pins name another NPC."
Write-Output "Report: $ReportFile"
if ($WhatIf) { Write-Output "WhatIf: nothing changed."; exit 0 }
if ($filled.Count + $added.Count + $joined.Count -gt 0) { Save-PinData $ordered $DataDir $AddonDir }
