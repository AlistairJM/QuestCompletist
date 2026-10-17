<#
Step 2p of a sweep (docs/maintenance.md), and for WoW: Forever part of step 10 after the importer: which side can take each
quest the data opens to both sides (the client tables audit, opportunity 6, the user's choices on 17 October 2026).

  - Blizzard's side. The side the game names for the quest (the probe's GetQuestFactionGroup, else the quest cache's
    faction) is written into data\quests.jsonl as its faction (part A). On Forever the importer gives it (step 10), so one
    left over is a finding.
  - Its givers' side. When Blizzard names none, and every known starter of the quest is one side's alone (QuestSides.ps1
    says how a giver is read), that side goes into data\sides.jsonl (Forever: data\forever\sides.jsonl), which the build
    writes as the quest's faction (part B). The starters are our pins' NPCs, the givers the probe saw offer it, the
    emulator's (TrinityCore's on retail, CMaNGOS's on Forever) and the items that start it; a giver's faction comes from
    the emulator. A KEEP row in docs\plans\quest-side-decisions.csv leaves a quest open to both. The quest chain has the
    last word (Resolve-ChainSides): a quest that needs, or is needed by, a quest of the other side stays open (90762 sits
    between two Horde quests, though TrinityCore's giver for it is the Alliance's), and a quest open to both that needs a
    quest given a side this way follows it, so the other side isn't shown a quest it can't reach.
  - The zone's side (AreaTable.FactionGroupMask, of the API's area, else the quest cache's or the emulator's zone) is a
    report column only (part C): it can't tell a side's home zone from a quest only that side may take.

A quest of one side that Blizzard names the other for, or that the probe and the cache disagree on, is a finding. The run
checks the giver rule against Blizzard's own sides, reports what changed and writes tools\quest_sides_<game>.csv (or
-OutFile): each change, finding and quest kept, and each quest open to both in one side's zone. It downloads the build's
FactionTemplate, Faction, ChrRaces and AreaTable into tools\ (<table>-<build>.csv) when they aren't there. -WhatIf reports
without writing. Exit 1 when there is a finding.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-QuestSides.ps1 -Game retail -Build <retail build> -WhatIf
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-QuestSides.ps1 -Game forever -Build <Forever build>
#>
param(
    [ValidateSet('retail', 'forever')][string]$Game = 'retail',
    [string]$Build = '',
    [string]$ProbeFile = '',
    [string]$QuestCacheFile = '',
    [string]$EmulatorFile = '',
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-side-decisions.csv'),
    [string]$OutFile = '',
    [string]$ToolsDir = '',
    [string]$DataDir = '',
    [string]$AddonDir = '',
    [string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe',
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $Build) { throw 'Give -Build: the build of the client tables to read.' }
if (-not $ToolsDir) { $ToolsDir = $PSScriptRoot }
if (-not $DataDir) { $DataDir = if ($Game -eq 'retail') { Join-Path $PSScriptRoot '..\data' } else { Join-Path $PSScriptRoot '..\data\forever' } }
if (-not $AddonDir) { $AddonDir = if ($Game -eq 'retail') { Join-Path $PSScriptRoot '..\QuestCompletist' } else { Join-Path $PSScriptRoot '..\QuestCompletist\Forever' } }
if (-not $OutFile) { $OutFile = Join-Path $ToolsDir "quest_sides_$Game.csv" }
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\FactionReach.ps1"
. "$PSScriptRoot\QuestSides.ps1"
. "$PSScriptRoot\ProbeResults.ps1"
. "$PSScriptRoot\QuestCacheFiles.ps1"

function Get-BuildTable([string]$table) {
    $path = Join-Path $ToolsDir "$table-$Build.csv"
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path -Headers @{ 'User-Agent' = 'QuestCompletist-tools' }
        Start-Sleep -Milliseconds 300
    }
    return Import-Csv $path
}
function Read-Dump([string]$file, [string]$table, [string]$columns) {
    $encoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try { $lines = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $file $table $columns) } finally { [Console]::OutputEncoding = $encoding }
    if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $table" }
    return $lines
}

$reader = New-SideReader (Get-BuildTable 'FactionTemplate') (Get-BuildTable 'Faction') (Get-BuildTable 'ChrRaces')
$areas = @{}; foreach ($a in (Get-BuildTable 'AreaTable')) { $areas[[int]$a.ID] = $a }
$keep = Read-QuestSideDecisions $DecisionsFile $Game
$quests = Read-QuestData $DataDir

if (-not $ProbeFile) {
    $ProbeFile = if ($Game -eq 'retail') { Find-ProbeResults $ToolsDir } else {
        Get-ChildItem "$ToolsDir\forever_probe_*\QCForeverProbe.lua" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName }
}
$probe = if ($ProbeFile -and (Test-Path $ProbeFile) -and [IO.File]::ReadAllText($ProbeFile).Contains('QCForeverProbeDB')) { Get-ProbeSides $ProbeFile $LuaExe } else { $null }
if (-not $probe) { Write-Warning "No probe results with the game's own faction answers (tools\$Game`_probe_*): Blizzard's side comes from the quest cache alone." }
if (-not $QuestCacheFile) { $QuestCacheFile = Get-QuestCacheFiles $ToolsDir $Game | Select-Object -Last 1 -ExpandProperty FullName }
$cacheSide = @{}; $cacheZone = @{}
if ($QuestCacheFile) {
    Get-QuestCacheWarning $QuestCacheFile | ForEach-Object { Write-Warning $_ }
    foreach ($line in [IO.File]::ReadLines($QuestCacheFile)) {
        $c = $line | ConvertFrom-Json
        if ($c.faction -eq 'Alliance') { $cacheSide[[int]$c.id] = 1 } elseif ($c.faction -eq 'Horde') { $cacheSide[[int]$c.id] = 2 }
        if ([int]$c.sort -gt 0) { $cacheZone[[int]$c.id] = [int]$c.sort }
    }
}

# The emulator's starters, their factions and names, and its zone for each quest.
$starters = @{}
function Add-Starter([int]$quest, [string]$kind, [int]$id) {
    if (-not $starters.ContainsKey($quest)) { $starters[$quest] = @{} }
    $starters[$quest]["$kind|$id"] = $true
}
$creatureFaction = @{}; $creatureName = @{}; $objectFaction = @{}; $emulatorZone = @{}
if ($Game -eq 'retail') {
    if (-not $EmulatorFile) { $EmulatorFile = Get-ChildItem "$ToolsDir\tdb\TDB_full_world_*.sql" | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName }
    foreach ($l in (Read-Dump $EmulatorFile creature_template '1,4,11')) { $f = $l.Split("`t"); $creatureName[[int]$f[0]] = $f[1]; $creatureFaction[[int]$f[0]] = [int]$f[2] }
    foreach ($l in (Read-Dump $EmulatorFile gameobject_template_addon '1,2')) { $f = $l.Split("`t"); $objectFaction[[int]$f[0]] = [int]$f[1] }
    foreach ($l in (Read-Dump $EmulatorFile creature_queststarter '1,2')) { $f = $l.Split("`t"); Add-Starter ([int]$f[1]) 'npc' ([int]$f[0]) }
    foreach ($l in (Read-Dump $EmulatorFile gameobject_queststarter '1,2')) { $f = $l.Split("`t"); Add-Starter ([int]$f[1]) 'object' ([int]$f[0]) }
    foreach ($l in (Read-Dump $EmulatorFile quest_template '1,5')) { $f = $l.Split("`t"); if ([int]$f[1] -gt 0) { $emulatorZone[[int]$f[0]] = [int]$f[1] } }
    $objectDefault = 0
} else {
    if (-not $EmulatorFile) { $EmulatorFile = Get-ChildItem "$ToolsDir\ClassicDB_*.sql.gz" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
    $sql = Join-Path ([IO.Path]::GetTempPath()) ("quest_sides_" + [guid]::NewGuid().ToString('N') + '.sql')
    $source = [IO.File]::OpenRead($EmulatorFile); $gzip = New-Object IO.Compression.GZipStream $source, ([IO.Compression.CompressionMode]::Decompress); $target = [IO.File]::Create($sql)
    try { $gzip.CopyTo($target) } finally { $target.Close(); $gzip.Close(); $source.Close() }
    try {
        foreach ($l in (Read-Dump $sql creature_template '1,2,10')) { $f = $l.Split("`t"); $creatureName[[int]$f[0]] = $f[1]; $creatureFaction[[int]$f[0]] = [int]$f[2] }
        foreach ($l in (Read-Dump $sql gameobject_template '1,5')) { $f = $l.Split("`t"); $objectFaction[[int]$f[0]] = [int]$f[1] }
        foreach ($l in (Read-Dump $sql creature_questrelation '1,2')) { $f = $l.Split("`t"); Add-Starter ([int]$f[1]) 'npc' ([int]$f[0]) }
        foreach ($l in (Read-Dump $sql gameobject_questrelation '1,2')) { $f = $l.Split("`t"); Add-Starter ([int]$f[1]) 'object' ([int]$f[0]) }
        foreach ($l in (Read-Dump $sql quest_template '1,3')) { $f = $l.Split("`t"); if ([int]$f[1] -gt 0) { $emulatorZone[[int]$f[0]] = [int]$f[1] } }
    } finally { Remove-Item $sql -ErrorAction SilentlyContinue }
    $objectDefault = $null
}
$pinName = @{}
foreach ($p in (Read-JsonLines (Join-Path (Resolve-Path $DataDir).Path 'pins.jsonl'))) {
    if (-not $p.npc) { continue }
    if ($p.name) { $pinName[[int]$p.npc] = $p.name }
    foreach ($q in $p.quests) { Add-Starter ([int]$q) 'npc' ([int]$p.npc) }
}
if ($probe) { foreach ($q in $probe.Offers.Keys) { foreach ($o in $probe.Offers[$q]) { Add-Starter $q $o.Kind $o.Id } } }
$itemSide = @{}
$itemFile = Join-Path (Resolve-Path $DataDir).Path 'startitems.jsonl'
if (Test-Path $itemFile) { foreach ($it in (Read-JsonLines $itemFile)) { Add-Starter ([int]$it.quest) 'item' ([int]$it.item); $itemSide[[int]$it.item] = [int]$it.side } }

$apiZone = @{}
if ($Game -eq 'retail') {
    $areaRx = New-Object Text.RegularExpressions.Regex '"area":\{"key":\{[^}]*\},"name":"(?:[^"\\]|\\.)*","id":(\d+)\}'
    foreach ($q in $quests) {
        $path = Join-Path $ToolsDir "quest_api_cache\$($q.id).json"
        if (Test-Path $path) { $m = $areaRx.Match([IO.File]::ReadAllText($path)); if ($m.Success) { $apiZone[[int]$q.id] = [int]$m.Groups[1].Value } }
    }
}

$sideName = @{ 0 = 'neither'; 1 = 'Alliance'; 2 = 'Horde'; 3 = 'both' }
$detail = New-Object System.Collections.Generic.List[object]
$factionChanges = @{}; $giverRows = @{}; $findings = New-Object System.Collections.Generic.List[string]
$needs = @{}; $neededBy = @{}; $fixed = @{}; $followable = @{}
$checked = 0; $agreed = 0; $open = 0; $kept = 0; $named = 0
$zoneCount = @{ both = 0; one = 0; unknown = 0 }
foreach ($q in $quests) {
    $id = [int]$q.id
    $probeSays = if ($probe -and $probe.Sides.ContainsKey($id)) { $probe.Sides[$id] } else { $null }
    $cacheSays = if ($cacheSide.ContainsKey($id)) { $cacheSide[$id] } else { $null }
    $blizzard = if ($probeSays) { $probeSays } else { $cacheSays }
    if ($probeSays -and $cacheSays -and $probeSays -ne $cacheSays) { $findings.Add("$id $($q.name): the probe says $($sideName[$probeSays]), the quest cache $($sideName[$cacheSays])") }
    $list = @(); $names = @()
    if ($starters.ContainsKey($id)) {
        foreach ($key in ($starters[$id].Keys | Sort-Object)) {
            $kind, $ref = $key.Split('|'); $ref = [int]$ref
            $template = switch ($kind) {
                'npc' { if ($creatureFaction.ContainsKey($ref)) { $creatureFaction[$ref] } else { $null } }
                'object' { if ($objectFaction.ContainsKey($ref)) { $objectFaction[$ref] } else { $objectDefault } }
                default { $null }
            }
            $list += [pscustomobject]@{ Kind = $kind; Template = $template; Side = $(if ($kind -eq 'item') { [int]$itemSide[$ref] } else { 0 }) }
            $label = switch ($kind) { 'npc' { if ($pinName.ContainsKey($ref)) { $pinName[$ref] } elseif ($creatureName.ContainsKey($ref)) { $creatureName[$ref] } else { "NPC $ref" } } 'object' { "object $ref" } default { "item $ref" } }
            $one = if ($kind -eq 'item') { if ($itemSide[$ref] -in 1, 2) { $itemSide[$ref] } else { 3 } } elseif ($null -eq $template) { $null } elseif ($template -eq 0) { 3 } else { Get-TemplateSides $reader $template }
            $names += "$label ($(if ($null -eq $one) { 'unknown' } else { $sideName[$one] }))"
        }
    }
    $reach = Get-StarterSides $reader $list
    if ($blizzard -and ($reach -eq 1 -or $reach -eq 2)) { $checked++; if ($reach -eq $blizzard) { $agreed++ } }
    $zone = if ($apiZone.ContainsKey($id)) { $apiZone[$id] } elseif ($cacheZone.ContainsKey($id)) { $cacheZone[$id] } elseif ($emulatorZone.ContainsKey($id)) { $emulatorZone[$id] } else { 0 }
    $zoneSide = if ($zone) { Get-ZoneSide $areas $zone } else { 0 }
    $isOpen = Test-SideOpen ([int]$q.faction)
    if ($isOpen) { $open++ }
    $result = Get-QuestSideResult ([int]$q.faction) $blizzard $reach $keep.ContainsKey($id)
    $what = ''
    $side = [int]$q.faction -band 3
    if ($result -and $result.Faction) {
        $named++
        if ($Game -eq 'retail') { $factionChanges[$id] = $result.Faction; $side = $result.Faction; $what = "faction $($sideName[$result.Faction]) (Blizzard)" }
        else { $findings.Add("$id $($q.name): Blizzard names the $($sideName[$result.Faction]), which the importer didn't give"); $what = "finding: Blizzard names the $($sideName[$result.Faction])" }
    } elseif ($result -and $result.Side) { $giverRows[$id] = $result.Side; $what = "side $($sideName[$result.Side]) (givers)" }
    elseif ($result -and $result.Finding) { $findings.Add("$id $($q.name): ours $($sideName[[int]$q.faction -band 3]), $($result.Finding)"); $what = "finding: $($result.Finding)" }
    elseif ($isOpen -and $keep.ContainsKey($id) -and ($reach -eq 1 -or $reach -eq 2)) { $kept++; $what = "kept: $($keep[$id])" }
    elseif ($blizzard -and ($reach -eq 1 -or $reach -eq 2) -and $reach -ne $blizzard) { $what = "the givers' side isn't Blizzard's" }
    if ($side -eq 1 -or $side -eq 2) { $fixed[$id] = $side }
    elseif ($isOpen -and -not $blizzard -and -not $keep.ContainsKey($id)) { $followable[$id] = $true }
    if ($null -ne $q.prereq) {
        $needs[$id] = @(Get-PrereqIds $q.prereq | Sort-Object -Unique)
        foreach ($p in $needs[$id]) { if (-not $neededBy.ContainsKey($p)) { $neededBy[$p] = New-Object System.Collections.Generic.List[int] }; $neededBy[$p].Add($id) }
    }
    if ($isOpen -and ($zoneSide -eq 1 -or $zoneSide -eq 2)) {
        if ($reach -eq 3) { $zoneCount.both++ } elseif ($reach -eq 1 -or $reach -eq 2) { $zoneCount.one++ } else { $zoneCount.unknown++ }
        if (-not $what) { $what = 'zone only' }
    }
    $detail.Add([pscustomobject]@{ Game = $Game; QuestID = $id; Name = $q.name; Ours = [int]$q.faction; Result = $what
        Probe = $(if ($probeSays) { $sideName[$probeSays] } else { '' }); Cache = $(if ($cacheSays) { $sideName[$cacheSays] } else { '' })
        Givers = ($names -join '; '); GiverSide = $(if ($null -eq $reach) { 'unknown' } else { $sideName[$reach] })
        Zone = $(if ($zone -and $areas.ContainsKey($zone)) { $areas[$zone].AreaName_lang } else { '' }); ZoneSide = $(if ($zoneSide) { $sideName[$zoneSide] } else { '' }) })
}
$chain = Resolve-ChainSides $needs $neededBy $fixed $giverRows $followable
$byQuest = @{}; foreach ($d in $detail) { $byQuest[$d.QuestID] = $d }
foreach ($id in $chain.Dropped.Keys) { $byQuest[$id].Result = "open: its chain is the $($sideName[$chain.Dropped[$id]])'s" }
foreach ($id in $chain.Followed.Keys) { $byQuest[$id].Result = "side $($sideName[$chain.Rows[$id]]) (follows $($chain.Followed[$id]))" }
$sideRows = @($chain.Rows.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ quest = $_; side = $chain.Rows[$_] } })
$report = @($detail | Where-Object { $_.Result })
$report | Export-Csv $OutFile -NoTypeInformation -Encoding UTF8

$file = Join-Path (Resolve-Path $DataDir).Path 'sides.jsonl'
$old = @{}
if (Test-Path $file) { foreach ($r in (Read-JsonLines $file)) { $old[[int]$r.quest] = [int]$r.side } }
$new = @{}; foreach ($r in $sideRows) { $new[[int]$r.quest] = [int]$r.side }
$added = @($new.Keys | Where-Object { -not $old.ContainsKey($_) } | Sort-Object)
$changed = @($new.Keys | Where-Object { $old.ContainsKey($_) -and $old[$_] -ne $new[$_] } | Sort-Object)
$gone = @($old.Keys | Where-Object { -not $new.ContainsKey($_) } | Sort-Object)

"Sides, $Game ($Build): $($quests.Count) quests, $open open to both sides. Blizzard names a side for $named of them" +
    $(if ($Game -eq 'retail') { ' (into quests.jsonl)' } else { ' (the importer gives these)' }) + "; their givers' side for $($sideRows.Count - $chain.Followed.Count) more" +
    " and $($chain.Followed.Count) that follow them in their chain (sides.jsonl); left open, their chain being the other side's, $($chain.Dropped.Count); kept by decision $kept."
"The giver rule against Blizzard's own side: agrees for $agreed of the $checked quests both name a side for."
"Open to both, in one side's zone (AreaTable.FactionGroupMask): $($zoneCount.both + $zoneCount.one + $zoneCount.unknown); their givers open to both $($zoneCount.both), one side $($zoneCount.one), unknown $($zoneCount.unknown)."
"Findings: $($findings.Count)" + $(if ($findings.Count) { ": " + (($findings | Select-Object -First 20) -join '; ') } else { '' })
"quests.jsonl: $($factionChanges.Count) faction changes" + $(if ($factionChanges.Count -and $factionChanges.Count -le 40) { ": " + (($factionChanges.Keys | Sort-Object | ForEach-Object { "$_ $($sideName[$factionChanges[$_]])" }) -join ', ') } else { '' }) + '.'
"sides.jsonl: added $($added.Count), changed $($changed.Count), gone $($gone.Count)" + $(if ($added.Count + $changed.Count + $gone.Count -gt 0 -and $added.Count + $changed.Count + $gone.Count -le 60) { ": " + ((@($added | ForEach-Object { "+$_" }) + @($changed | ForEach-Object { "~$_" }) + @($gone | ForEach-Object { "-$_" })) -join ' ') } else { '' }) + '.'
"Report: $OutFile ($($report.Count) rows)."

if (-not $WhatIf) {
    if ($factionChanges.Count) {
        foreach ($q in $quests) { if ($factionChanges.ContainsKey([int]$q.id)) { Set-RecordField $q 'faction' ([long]$factionChanges[[int]$q.id]) } }
        Save-QuestData $quests $DataDir $AddonDir
    }
    if ($added.Count + $changed.Count + $gone.Count -gt 0) { Save-SideData $sideRows $DataDir $AddonDir }
}
if ($findings.Count) { exit 1 }
