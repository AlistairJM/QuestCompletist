<#
Gives a retail pin that has a name and no NPC ID the ID of its quest giver, from TrinityCore's
world database: the creature that starts one of the pin's quests there and bears exactly the pin's
name (surrounding spaces aside: a few names there end in one). The addon asks the game for that
creature's name in the player's language, so the pin's name then shows in every language, and its
tooltip gets the creature's title (<Innkeeper>).

A pin stays as it is when no quest of its starts at a creature of its name there: its quests start
at objects, or at a creature of another name, or the database lists no start for them, which is
how it has a quest that starts from an item ("Dargol's Skull") and content after Dragonflight. The
report lists those by reason, for a lookup by hand (plans\pin-npc-id-decisions.csv).

When several creatures of the pin's name start its quests (one per phase of a story), the pin
takes the one that starts most of them, then the lowest ID; the report names the others.

WoW: Forever's pins aren't touched: Import-ForeverData.ps1 gives them their IDs from CMaNGOS.

Reads the newest tools\tdb\TDB_full_world_*.sql (maintenance.md, "Before a sweep") through
Read-SqlDump.lua. A second run changes nothing. With -WhatIf it only reports; otherwise it saves
through AddonData.ps1, which rebuilds the Lua. After it, rerun the pin pipeline: a pin that now
shares its ID with another pin of that NPC within 3 points joins it at the next rebuild.

  .\Fill-PinNpcIds.ps1 -WhatIf
  .\Fill-PinNpcIds.ps1
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$TdbFile = "",
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [string]$ReportFile = (Join-Path $PSScriptRoot 'pin-npc-id-report.txt'),
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

if (-not $TdbFile) {
    $TdbFile = Get-ChildItem "$ToolsDir\tdb\TDB_full_world_*.sql" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $TdbFile) { throw "No tools\tdb\TDB_full_world_*.sql: see maintenance.md, 'Before a sweep'." }

function Read-DumpTable([string]$table, [string]$columns) {
    $outputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try { $rows = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $TdbFile $table $columns) } finally { [Console]::OutputEncoding = $outputEncoding }
    if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $TdbFile ($table)" }
    return $rows
}

$creatureName = @{}
foreach ($row in Read-DumpTable 'creature_template' '1,4') {
    $f = $row.Split("`t")
    $creatureName[[int]$f[0]] = $f[1]
}
$creatureStarts = @{}
foreach ($row in Read-DumpTable 'creature_queststarter' '1,2') {
    $f = $row.Split("`t")
    $quest = [int]$f[1]
    if (-not $creatureStarts.ContainsKey($quest)) { $creatureStarts[$quest] = New-Object System.Collections.Generic.List[int] }
    $creatureStarts[$quest].Add([int]$f[0])
}
$objectStarts = @{}
foreach ($row in Read-DumpTable 'gameobject_queststarter' '1,2') {
    $f = $row.Split("`t")
    $objectStarts[[int]$f[1]] = $true
}

$pins = Read-PinData $DataDir
$filled = New-Object System.Collections.Generic.List[string]
$atObjects = New-Object System.Collections.Generic.List[string]
$otherNames = New-Object System.Collections.Generic.List[string]
$notInDump = New-Object System.Collections.Generic.List[string]
$unnamed = 0; $withId = 0; $severalIds = 0
foreach ($pin in $pins) {
    if ($null -eq $pin.name) { $unnamed++; continue }
    if ($pin.npc) { $withId++; continue }
    $place = "map $($pin.map) at $($pin.x),$($pin.y): $($pin.name)"
    $starts = @{}
    $others = @{}
    $objects = 0; $missing = 0
    foreach ($questId in $pin.quests) {
        $quest = [int]$questId
        $known = $false
        if ($creatureStarts.ContainsKey($quest)) {
            $known = $true
            foreach ($id in $creatureStarts[$quest]) {
                $name = $creatureName[$id]
                if ($name -and $name.Trim() -ceq $pin.name.Trim()) {
                    if ($starts.ContainsKey($id)) { $starts[$id]++ } else { $starts[$id] = 1 }
                } elseif ($name) {
                    $others[$name] = $true
                }
            }
        }
        if ($objectStarts.ContainsKey($quest)) { $known = $true; $objects++ }
        if (-not $known) { $missing++ }
    }
    if ($starts.Count -eq 0) {
        if ($others.Count -gt 0) { $otherNames.Add("$place <- " + (($others.Keys | Sort-Object) -join ', ')) }
        elseif ($objects -gt 0) { $atObjects.Add($place) }
        else { $notInDump.Add($place) }
        continue
    }
    $best = 0
    foreach ($id in $starts.Keys) {
        if ($best -eq 0 -or $starts[$id] -gt $starts[$best] -or ($starts[$id] -eq $starts[$best] -and $id -lt $best)) { $best = $id }
    }
    $line = "$place -> $best"
    if ($starts.Count -gt 1) {
        $severalIds++
        $line += " (also " + (($starts.Keys | Where-Object { $_ -ne $best } | Sort-Object) -join ', ') + ")"
    }
    $filled.Add($line)
    Set-RecordField $pin 'npc' $best
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add("Fill-PinNpcIds.ps1 on $(Split-Path $TdbFile -Leaf), $(Get-Date -Format 'yyyy-MM-dd')")
$report.Add("$($pins.Count) pins: $withId with an ID, $unnamed with no name, $($filled.Count + $atObjects.Count + $otherNames.Count + $notInDump.Count) with a name and no ID.")
$report.Add("")
$report.Add("$($filled.Count) pins given the ID of the creature of their name that starts their quests ($severalIds with another ID of that name in brackets):")
foreach ($line in $filled) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($atObjects.Count) pins whose quests start at objects or items (no creature to name):")
foreach ($line in $atObjects) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($otherNames.Count) pins whose quests start at creatures of other names (look up by hand):")
foreach ($line in $otherNames) { $report.Add("  $line") }
$report.Add("")
$report.Add("$($notInDump.Count) pins whose quests have no start in the database (an item, or content it lacks; look up by hand):")
foreach ($line in $notInDump) { $report.Add("  $line") }
[IO.File]::WriteAllLines($ReportFile, $report)

Write-Output "$($filled.Count) pins get an ID; $($atObjects.Count) start at objects, $($otherNames.Count) at creatures of other names, $($notInDump.Count) aren't in $(Split-Path $TdbFile -Leaf)."
Write-Output "Report: $ReportFile"
if ($WhatIf) { Write-Output "WhatIf: nothing changed."; exit 0 }
if ($filled.Count -gt 0) { Save-PinData $pins $DataDir $AddonDir }
