<#
Flattens the pins in data\pins.jsonl into a quest-ID-keyed lookup, tools\existing_pindb_by_quest.csv:
  QuestID -> { OldUiMapID, OldMapX, OldMapY, IconType, NpcId, NpcName, Note }

A single quest ID can appear at multiple pins (e.g. offered in more than one
place) - all occurrences are kept as a list per quest ID. NpcName and Note are
the plain text, empty when the pin has none.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data')
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

$outFile = Join-Path $ToolsDir "existing_pindb_by_quest.csv"
$format = '0.############################'
$results = New-Object System.Collections.Generic.List[object]
foreach ($pin in (Read-PinData $DataDir)) {
    $mapX = ([decimal]$pin.x).ToString($format, $script:Invariant)
    $mapY = ([decimal]$pin.y).ToString($format, $script:Invariant)
    foreach ($qid in $pin.quests) {
        $results.Add([PSCustomObject]@{
            QuestID     = [string]$qid
            OldUiMapID  = [string]$pin.map
            OldMapX     = $mapX
            OldMapY     = $mapY
            IconType    = [string]$pin.icon
            NpcId       = if ($pin.npc) { [string]$pin.npc } else { "0" }
            NpcName     = if ($null -ne $pin.name) { $pin.name } else { "" }
            Note        = if ($null -ne $pin.note) { $pin.note } else { "" }
        })
    }
}

Write-Output "Total (quest, pin) associations parsed: $($results.Count)"
$distinctQuests = ($results | Select-Object QuestID -Unique).Count
Write-Output "Distinct quest IDs with an existing pin: $distinctQuests"

$results | Export-Csv -Path $outFile -NoTypeInformation -Encoding utf8
Write-Output "Written to $outFile"
