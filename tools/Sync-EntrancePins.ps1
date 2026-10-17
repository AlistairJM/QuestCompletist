<#
Step 6f of a sweep (docs/maintenance.md), and for WoW: Forever part of step 10 after the importer: a pin at each dungeon and
raid entrance, listing the instance's quests that no pin places (the client tables audit, opportunity 8, the user's
choices of 17 October 2026). EntrancePins.ps1 says which categories are instances and where their pins go: wherever the
game's own map draws the instance, from the probe's map pass (retail: tools\retail_probe_*, the newest; Forever:
tools\forever_probe_*, whose client draws none so far), else at its doors (retail: the Dungeon Journal's door table;
Forever: the instance maps' corpse points), each door on the zone map its area or its place gives it.

The quests are those of the instance's categories that no pin of data\pins.jsonl holds, leaving out the task quests of a
kind PinRules.ps1 gives no pin (retail's world quests) and the quests qcUnavailableQuests names; a door of one side lists
only the quests that side can take. They are written to data\entrances.jsonl (Forever: data\forever\entrances.jsonl),
which the build turns into qcPinDB pins with a dungeon or raid icon (AddonData.ps1).

A door two zone maps hold and no area chooses between, or that no zone map holds, is held back: it gets a pin only by a
row of docs\plans\entrance-pin-decisions.csv (SHOW, with the UiMapID and the X and Y to put it at, or HIDE). On Forever any
door more than one zone holds is held, since retail's door areas are retail's doors (EntrancePins.ps1). Findings: a held
door with no row, a row for a door that isn't held (the rule places it, or the game draws the instance), and on retail a
probe that saw no entrance at all (its map pass is needed). The run writes tools\entrance_pins_<game>.csv (or -OutFile):
each place and door, how it was placed, the zones that hold a door and retail's area for it. It downloads the build's Map,
UiMap, UiMapAssignment and AreaTable, and the retail build's JournalInstance and JournalInstanceEntrance, into tools\
(<table>-<build>.csv) when they aren't there; retail reads step 1b's QuestV2CliTask.csv. -WhatIf reports without writing.
Exit 1 when there is a finding.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-EntrancePins.ps1 -Game retail -Build <retail build> -WhatIf
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-EntrancePins.ps1 -Game forever -Build <Forever build> -RetailBuild <retail build>
#>
param(
    [ValidateSet('retail', 'forever')][string]$Game = 'retail',
    [string]$Build = '',
    [string]$RetailBuild = '',
    [string]$ProbeFile = '',
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\entrance-pin-decisions.csv'),
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
if ($Game -eq 'retail') { if (-not $RetailBuild) { $RetailBuild = $Build } }
elseif (-not $RetailBuild) { throw 'Give -RetailBuild: the retail build whose Dungeon Journal names the entrance areas.' }
if (-not $ToolsDir) { $ToolsDir = $PSScriptRoot }
if (-not $DataDir) { $DataDir = if ($Game -eq 'retail') { Join-Path $PSScriptRoot '..\data' } else { Join-Path $PSScriptRoot '..\data\forever' } }
if (-not $AddonDir) { $AddonDir = if ($Game -eq 'retail') { Join-Path $PSScriptRoot '..\QuestCompletist' } else { Join-Path $PSScriptRoot '..\QuestCompletist\Forever' } }
if (-not $OutFile) { $OutFile = Join-Path $ToolsDir "entrance_pins_$Game.csv" }
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\PinRules.ps1"
. "$PSScriptRoot\EntrancePins.ps1"
. "$PSScriptRoot\ProbeResults.ps1"

function Get-BuildTable([string]$table, [string]$build) {
    $path = Join-Path $ToolsDir "$table-$build.csv"
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$build" -OutFile $path -Headers @{ 'User-Agent' = 'QuestCompletist-tools' }
        Start-Sleep -Milliseconds 300
    }
    return Import-Csv $path
}

$mapRows = Get-BuildTable 'Map' $Build
$uiMapRows = Get-BuildTable 'UiMap' $Build
$areaRows = Get-BuildTable 'AreaTable' $Build
$locator = New-ZoneLocator $mapRows $uiMapRows (Get-BuildTable 'UiMapAssignment' $Build) $areaRows
$journalRows = Get-BuildTable 'JournalInstance' $RetailBuild
$entranceRows = Get-BuildTable 'JournalInstanceEntrance' $RetailBuild
$questLua = Join-Path $AddonDir 'qcQuest.lua'
$categoryNames = Read-QuestCategoryNames $questLua
$instances = if ($Game -eq 'retail') {
    @(Get-RetailInstances $journalRows $entranceRows $mapRows $categoryNames (Read-CategoryUiMapIds $questLua) $uiMapRows)
} else {
    @(Get-ForeverInstances $mapRows $categoryNames $journalRows $entranceRows)
}

if (-not $ProbeFile) {
    $ProbeFile = if ($Game -eq 'retail') { Find-ProbeResults $ToolsDir } else {
        Get-ChildItem "$ToolsDir\forever_probe_*\QCForeverProbe.lua" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName }
}
$gameRows = @()
if ($ProbeFile -and (Test-Path $ProbeFile) -and [IO.File]::ReadAllText($ProbeFile).Contains('QCForeverProbeDB')) { $gameRows = @(Get-ProbeEntrances $ProbeFile $LuaExe) }
$gameSpots = Group-GameEntrances $gameRows

$quests = Read-QuestData $DataDir
$pinned = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($pin in (Read-PinData $DataDir)) { foreach ($q in $pin.quests) { [void]$pinned.Add([int]$q) } }
$skip = New-Object 'System.Collections.Generic.HashSet[int]'
$taskSkipped = 0
if ($Game -eq 'retail') {
    $taskFile = Join-Path $ToolsDir 'QuestV2CliTask.csv'
    if (-not (Test-Path $taskFile)) { throw "QuestV2CliTask.csv missing (step 1b): without it world quests would get entrance pins" }
    $skip.UnionWith((Get-NoPinTaskQuests (Import-Csv $taskFile)))
    $taskSkipped = $skip.Count
}
$unavailableFile = Join-Path $AddonDir 'qcUnavailableQuests.lua'
if (Test-Path $unavailableFile) { foreach ($m in [regex]::Matches([IO.File]::ReadAllText($unavailableFile), '\[(\d+)\]=')) { [void]$skip.Add([int]$m.Groups[1].Value) } }

$decisions = Read-EntranceDecisions $DecisionsFile $Game
$result = Get-EntrancePins $instances $quests $pinned $skip $locator $decisions $gameSpots

$areaName = @{}; foreach ($a in $areaRows) { $areaName[[int]$a.ID] = $a.AreaName_lang }
if ($Game -ne 'retail') { foreach ($a in (Get-BuildTable 'AreaTable' $RetailBuild)) { if (-not $areaName.ContainsKey([int]$a.ID)) { $areaName[[int]$a.ID] = $a.AreaName_lang } } }
$uiName = @{}; foreach ($u in $uiMapRows) { $uiName[[int]$u.ID] = $u.Name_lang }
$findings = New-Object System.Collections.Generic.List[string]
if ($Game -eq 'retail' -and -not $gameRows.Count) { $findings.Add("the probe ($(if ($ProbeFile) { $ProbeFile } else { 'none found' })) saw the game draw no entrance: run its map pass, or every instance goes to its doors") }
$report = New-Object System.Collections.Generic.List[object]
$heldKeys = @{}
foreach ($d in $result.Doors) {
    if ($d.Held) { $heldKeys["$($d.Instance)|$($d.Door)"] = $true }
    if ($d.Held -and -not $d.Decided) { $findings.Add("$($d.Instance), door $($d.Door): $(if ($d.How -eq 'none') { 'no zone map holds it' } else { 'held by ' + (($d.Zones | ForEach-Object { "$($_.Name) ($($_.UiMap)) $($_.X),$($_.Y)" }) -join ', ') }); give it a row") }
    $report.Add([pscustomobject]@{
        Instance = $d.Instance; Kind = $d.Kind; Door = $d.Door; Side = $d.Side; How = $d.How; UiMapID = $d.UiMap; Zone = $uiName[$d.UiMap]; X = $d.X; Y = $d.Y
        Quests = $d.Quests.Count; QuestIDs = ($d.Quests -join ' ')
        Zones = (($d.Zones | ForEach-Object { "$($_.Name) ($($_.UiMap)) $($_.X),$($_.Y)" }) -join '; ')
        RetailArea = $(if ($d.Hint) { "$($d.Hint) $($areaName[$d.Hint])" } else { '' })
    })
}
foreach ($key in ($decisions.Keys | Sort-Object)) {
    if (-not $heldKeys.ContainsKey($key)) { $findings.Add("a decision row for $($key.Replace('|', ', door ')), which is no held door with quests no pin has (the rule places it, or the game draws the instance); drop the row") }
}
$report | Export-Csv $OutFile -NoTypeInformation -Encoding UTF8

$entranceFile = Join-Path (Resolve-Path $DataDir).Path 'entrances.jsonl'
$old = if (Test-Path $entranceFile) { [IO.File]::ReadAllText($entranceFile) } else { '' }
$new = ConvertTo-EntranceJsonLines $result.Pins
$oldKeys = @{}; foreach ($line in ($old -split "`n" | Where-Object { $_ })) { $oldKeys[$line] = $true }
$newKeys = @{}; foreach ($line in ($new -split "`n" | Where-Object { $_ })) { $newKeys[$line] = $true }
$added = @($newKeys.Keys | Where-Object { -not $oldKeys.ContainsKey($_) }).Count
$dropped = @($oldKeys.Keys | Where-Object { -not $newKeys.ContainsKey($_) }).Count

$gameDoors = @($result.Doors | Where-Object How -eq 'game')
$tableDoors = @($result.Doors | Where-Object How -ne 'game')
$withPlaces = @($result.Doors | Select-Object -ExpandProperty Instance -Unique)
$placedNames = @($result.Pins | ForEach-Object { $_.name } | Select-Object -Unique)
$unplaced = @($withPlaces | Where-Object { $placedNames -notcontains $_ })
"Instances ($Game, build $Build): $($instances.Count) dungeon and raid categories; $($withPlaces.Count + $result.Doorless.Count) have quests no pin places" +
    $(if ($Game -eq 'retail') { " ($taskSkipped task quests of a no-pin kind left out)" } else { '' }) + '.'
"The game's own map (probe $(if ($ProbeFile) { Split-Path -Leaf (Split-Path -Parent $ProbeFile) } else { 'none' })): $($gameRows.Count) entrances; $(@($gameDoors | Select-Object -ExpandProperty Instance -Unique).Count) of these instances placed at its $($gameDoors.Count) places."
"The others go to their doors$(if ($tableDoors.Count) { " ($((@($tableDoors | Select-Object -ExpandProperty Instance -Unique)) -join ', '))" }): $($tableDoors.Count); placed by their area $(@($tableDoors | Where-Object How -eq 'area').Count), by the one zone holding them $(@($tableDoors | Where-Object How -eq 'box').Count), by a SHOW row $(@($tableDoors | Where-Object How -eq 'SHOW').Count); hidden by a row $(@($tableDoors | Where-Object How -eq 'HIDE').Count); held with no row $(@($tableDoors | Where-Object { $_.Held -and -not $_.Decided }).Count)."
"Entrance pins: $($result.Pins.Count), listing $(@($result.Pins | ForEach-Object { $_.quests } | Select-Object -Unique).Count) quests; instances with no pin placed: $($unplaced.Count)" + $(if ($unplaced.Count) { " ($($unplaced -join ', '))" } else { '' }) + '.'
"Instances with such quests, drawn nowhere and with no door in the client's data: $($result.Doorless.Count)" + $(if ($result.Doorless.Count) { " ($(($result.Doorless | ForEach-Object { "$($_.Name) $($_.Quests)" }) -join ', '))" } else { '' }) + '.'
if ($old -ceq $new) { "$(Split-Path -Leaf $entranceFile): no change." }
elseif ($WhatIf) { "$(Split-Path -Leaf $entranceFile) would change: $added pins new or changed, $dropped gone (-WhatIf: nothing written)." }
else {
    Save-EntranceData $result.Pins $DataDir $AddonDir
    "$(Split-Path -Leaf $entranceFile) written: $added pins new or changed, $dropped gone."
}
"Findings: $($findings.Count)" + $(if ($findings.Count) { ": " + (($findings | Select-Object -First 30) -join '; ') } else { '' })
"Report: $OutFile ($($report.Count) rows)."
exit $(if ($findings.Count) { 1 } else { 0 })
