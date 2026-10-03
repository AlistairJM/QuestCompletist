<#
Applies docs/plans/pin-npc-id-decisions.csv to qcPinDB.lua. Field 2 of a pin is the quest giver's
creature ID, and the addon asks the game for that creature's name in the player's language, so the
ID has to be the right creature.

Each row names one pin by map, X and Y as written in qcPinDB.lua, and its name:
  NAME  the game's English name for the pin's ID is better than ours (formatting, a name cut short):
        the pin takes NewName and keeps its ID.
  ID    the ID is the wrong creature, or not a creature at all: the pin's ID becomes NewId once
        someone has looked it up (Wowhead's quest page shows the start NPC), and 0 until then.

Rows come from the NPC name probe's English run (docs/plans/localized-npc-names.md). Running it
again changes nothing, so filling in NewId later and rerunning applies just those.

  .\Apply-PinNpcIds.ps1 -WhatIf     shows what would change
  .\Apply-PinNpcIds.ps1             changes qcPinDB.lua
#>

param(
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [string]$DecisionsCsv = "C:\Users\alist\RiderProjects\QuestCompletist\docs\plans\pin-npc-id-decisions.csv",
    [switch]$WhatIf
)

$pinFile = Join-Path $AddonDir "qcPinDB.lua"
$rows = @(Import-Csv -Path $DecisionsCsv -Encoding UTF8)

$problems = New-Object System.Collections.Generic.List[string]
$rowsAt = @{}
foreach ($row in $rows) {
    if ($row.Action -notin @("NAME", "ID")) { $problems.Add("unknown action '$($row.Action)' for $($row.Name)") }
    if ($row.Action -eq "NAME" -and -not $row.NewName) { $problems.Add("NAME row without a NewName: $($row.Name)") }
    if ($row.NewId -and $row.NewId -notmatch '^\d+$') { $problems.Add("NewId isn't a number: '$($row.NewId)' for $($row.Name)") }
    $key = "$($row.Map)|$($row.X)|$($row.Y)"
    if (-not $rowsAt.ContainsKey($key)) { $rowsAt[$key] = New-Object System.Collections.Generic.List[object] }
    $rowsAt[$key].Add($row)
}
if ($problems.Count -gt 0) { $problems | ForEach-Object { Write-Output $_ }; exit 1 }

function ConvertFrom-LuaString([string]$text) { return $text.Replace('\"', '"').Replace('\\', '\') }
function ConvertTo-LuaString([string]$text) { return $text.Replace('\', '\\').Replace('"', '\"') }

$utf8 = New-Object System.Text.UTF8Encoding($false)
$lines = [System.IO.File]::ReadAllText($pinFile, $utf8) -split "`r`n"
$matched = @{}
$renamed = 0; $cleared = 0; $set = 0
$map = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\t\[(\d+)\] = \{$') { $map = $matches[1]; continue }
    if ($lines[$i] -notmatch '^(\t\t\{\d+,)(\d+),"((?:[^"\\]|\\.)*)",(-?[\d.]+),(-?[\d.]+),(.*)$') { continue }
    $head, $id, $luaName, $x, $y, $tail = $matches[1], $matches[2], $matches[3], $matches[4], $matches[5], $matches[6]
    $key = "$map|$x|$y"
    if (-not $rowsAt.ContainsKey($key)) { continue }
    $name = ConvertFrom-LuaString $luaName
    foreach ($row in $rowsAt[$key]) {
        if ($name -ne $row.Name -and $name -ne $row.NewName) { continue }
        if ($id -ne $row.Id -and $id -ne "0" -and $id -ne $row.NewId) { continue }
        $matched[$row] = $true
        $newId = if ($row.NewId) { $row.NewId } elseif ($row.Action -eq "ID") { "0" } else { $id }
        $newName = if ($row.NewName) { $row.NewName } else { $name }
        if ($newName -ne $name) { $renamed++ }
        if ($newId -ne $id) { if ($newId -eq "0") { $cleared++ } else { $set++ } }
        $lines[$i] = "$head$newId,`"$(ConvertTo-LuaString $newName)`",$x,$y,$tail"
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
if ($WhatIf) { Write-Output "WhatIf: qcPinDB.lua not changed."; exit 0 }
if ($renamed + $cleared + $set -gt 0) {
    [System.IO.File]::WriteAllText($pinFile, ($lines -join "`r`n"), $utf8)
    Write-Output "qcPinDB.lua updated."
}
