<#
Applies docs/plans/pin-npc-id-decisions.csv to the pins in data\pins.jsonl, then rebuilds qcPinDB.lua.
A pin's npc is the quest giver's creature ID, and the addon asks the game for that creature's name
in the player's language, so the ID has to be the right creature.

Each row names one pin by map, X and Y, and its name. X and Y are compared as numbers, so 38.0 in
the file matches a pin at 38.
  NAME  the game's English name for the pin's ID is better than ours (formatting, a name cut short):
        the pin takes NewName and keeps its ID.
  ID    the ID is the wrong creature, or not a creature at all: the pin's ID becomes NewId once
        someone has looked it up (Wowhead's quest page shows the start NPC), and 0 until then.

Rows come from the NPC name probe's English run (docs/plans/localized-npc-names.md). Running it
again changes nothing, so filling in NewId later and rerunning applies just those.

  .\Apply-PinNpcIds.ps1 -WhatIf     shows what would change
  .\Apply-PinNpcIds.ps1             changes the pins
#>

param(
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$DecisionsCsv = (Join-Path $PSScriptRoot '..\docs\plans\pin-npc-id-decisions.csv'),
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

function Get-PlaceKey($map, $x, $y) {
    $format = '0.############################'
    return "$map|$(([decimal]$x).ToString($format, $script:Invariant))|$(([decimal]$y).ToString($format, $script:Invariant))"
}

$rows = @(Import-Csv -Path $DecisionsCsv -Encoding UTF8)

$problems = New-Object System.Collections.Generic.List[string]
$rowsAt = @{}
foreach ($row in $rows) {
    if ($row.Action -notin @("NAME", "ID")) { $problems.Add("unknown action '$($row.Action)' for $($row.Name)") }
    if ($row.Action -eq "NAME" -and -not $row.NewName) { $problems.Add("NAME row without a NewName: $($row.Name)") }
    if ($row.NewId -and $row.NewId -notmatch '^\d+$') { $problems.Add("NewId isn't a number: '$($row.NewId)' for $($row.Name)") }
    $key = Get-PlaceKey $row.Map ([decimal]::Parse($row.X, $script:Invariant)) ([decimal]::Parse($row.Y, $script:Invariant))
    if (-not $rowsAt.ContainsKey($key)) { $rowsAt[$key] = New-Object System.Collections.Generic.List[object] }
    $rowsAt[$key].Add($row)
}
if ($problems.Count -gt 0) { $problems | ForEach-Object { Write-Output $_ }; exit 1 }

$pins = Read-PinData $DataDir
$matched = @{}
$renamed = 0; $cleared = 0; $set = 0
foreach ($pin in $pins) {
    if ($null -eq $pin.name) { continue }
    $key = Get-PlaceKey $pin.map $pin.x $pin.y
    if (-not $rowsAt.ContainsKey($key)) { continue }
    $id = if ($pin.npc) { [string]$pin.npc } else { "0" }
    foreach ($row in $rowsAt[$key]) {
        if ($pin.name -ne $row.Name -and $pin.name -ne $row.NewName) { continue }
        if ($id -ne $row.Id -and $id -ne "0" -and $id -ne $row.NewId) { continue }
        $matched[$row] = $true
        $newId = if ($row.NewId) { $row.NewId } elseif ($row.Action -eq "ID") { "0" } else { $id }
        $newName = if ($row.NewName) { $row.NewName } else { $pin.name }
        if ($newName -cne $pin.name) { $renamed++; Set-RecordField $pin 'name' $newName }
        if ($newId -ne $id) {
            if ($newId -eq "0") { $cleared++ } else { $set++ }
            Set-RecordField $pin 'npc' ([int]$newId)
        }
        break
    }
}

$unmatched = @($rows | Where-Object { -not $matched.ContainsKey($_) })
if ($unmatched.Count -gt 0) {
    Write-Output "$($unmatched.Count) rows match no pin:"
    $unmatched | ForEach-Object { Write-Output "  map $($_.Map) at $($_.X),$($_.Y): $($_.Name) [$($_.Id)]" }
    exit 1
}

Write-Output "$($rows.Count) rows: $renamed pins renamed, $cleared IDs cleared, $set IDs set."
if ($WhatIf) { Write-Output "WhatIf: nothing changed."; exit 0 }
if ($renamed + $cleared + $set -gt 0) { Save-PinData $pins $DataDir $AddonDir }
