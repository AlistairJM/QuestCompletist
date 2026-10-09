<#
Report-only. Compares the names on a game's pins with the names the game gives their NPCs, from the
probe's NPC pass (tools\ForeverProbe, `/qcprobe npcs`): the probe asks the client what it calls each
creature, so this finds a pin that names another creature than its ID does (the ID is wrong), or the
right one in other words (a formatting difference, a name cut short). It changes nothing; the cases that
need acting on go into docs\plans\pin-npc-id-decisions.csv, which Apply-PinNpcIds.ps1 applies (NAME takes
the game's name, ID clears or replaces the ID). The columns are those of that file where they exist.

A pin is one of:
  same            the pin's name is the game's
  spacing         the same but for case, spaces or a <title> after the name: NAME
  contains        one name holds the other: NAME, after a look
  differs         the names have nothing in common: the ID is probably wrong creature: ID, after a look
  not named       the game never gave the creature a name (an instance, an object, an ID that is not a creature)
  not asked       the creature is not in the probe's list
Pins with no ID or no name are not compared. A case that has a row in the decisions file says so.

  -Game retail   the pins in data\pins.jsonl and the newest tools\retail_probe_<build>\QCForeverProbe.lua
  -Game forever  data\forever\pins.jsonl and the newest tools\forever_probe_<build>\QCForeverProbe.lua
  -ProbeFile     a copy of the saved variables to read instead

Writes tools\pin_npc_names_<game>.csv (every pin that is not "same") and prints the counts by class.
#>
param(
    [string]$Game = 'retail',
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$Decisions = (Join-Path $PSScriptRoot '..\docs\plans\pin-npc-id-decisions.csv'),
    [string]$ProbeFile = '',
    [string]$Output = '',
    [string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"
if ($Game -notin 'retail', 'forever') { throw "-Game must be retail or forever." }
$folder = if ($Game -eq 'retail') { 'retail_probe' } else { 'forever_probe' }
if (-not $ProbeFile) {
    $newest = Get-ChildItem "$ToolsDir\${folder}_*\QCForeverProbe.lua" -ErrorAction SilentlyContinue |
        Sort-Object { [int]($_.Directory.Name -replace "^${folder}_(\d+).*$", '$1') } | Select-Object -Last 1
    if (-not $newest) { throw "There are no probe results under $ToolsDir\${folder}_*. Give -ProbeFile." }
    $ProbeFile = $newest.FullName
}
if (-not $Output) { $Output = Join-Path $ToolsDir "pin_npc_names_$Game.csv" }
$pinDir = if ($Game -eq 'retail') { $DataDir } else { Join-Path $DataDir 'forever' }

$lines = @(& $LuaExe "$PSScriptRoot\Read-ForeverProbe.lua" $ProbeFile)
if ($LASTEXITCODE -ne 0) { throw "Read-ForeverProbe.lua failed on $ProbeFile" }
$rows = @($lines | Where-Object { $_.StartsWith("npc`t") } | ForEach-Object { , $_.Split("`t") })
$build = ($rows | Group-Object { $_[2] } | Sort-Object Count -Descending | Select-Object -First 1).Name
if (-not $build) { throw "No NPCs in ${ProbeFile}: has /qcprobe npcs been run?" }
$gameNames = @{}; $asked = @{}
foreach ($f in $rows) {
    if ($f[2] -ne $build) { continue }
    $asked[$f[1]] = $true
    if ($f[3] -ne 'none' -and $f.Count -gt 4 -and $f[4]) { $gameNames[$f[1]] = $f[4] }
}

function Get-PlaceKey($map, $x, $y) {
    $format = '0.############################'
    return "$map|$(([decimal]$x).ToString($format, $script:Invariant))|$(([decimal]$y).ToString($format, $script:Invariant))"
}
$decided = @{}
if (Test-Path $Decisions) {
    foreach ($row in (Import-Csv -Path $Decisions -Encoding UTF8)) {
        $decided[(Get-PlaceKey $row.Map ([decimal]::Parse($row.X, $script:Invariant)) ([decimal]::Parse($row.Y, $script:Invariant)))] = $row.Action
    }
}

function Get-Core([string]$name) {
    return (($name -replace '<[^>]*>', '') -replace '\s+', ' ').Trim().ToLowerInvariant()
}

$report = New-Object System.Collections.Generic.List[object]
$counts = @{}
$compared = 0
foreach ($pin in (Read-PinData $pinDir)) {
    if (-not $pin.npc -or $null -eq $pin.name -or $pin.name -eq '') { continue }
    $compared++
    $id = [string]$pin.npc
    $theirs = $gameNames[$id]
    $class = if (-not $asked.ContainsKey($id)) { 'not asked' }
        elseif (-not $theirs) { 'not named' }
        elseif ($pin.name -ceq $theirs) { 'same' }
        elseif ((Get-Core $pin.name) -ceq (Get-Core $theirs)) { 'spacing' }
        elseif ((Get-Core $pin.name).Contains((Get-Core $theirs)) -or (Get-Core $theirs).Contains((Get-Core $pin.name))) { 'contains' }
        else { 'differs' }
    $counts[$class] = 1 + [int]$counts[$class]
    if ($class -eq 'same') { continue }
    $key = Get-PlaceKey $pin.map $pin.x $pin.y
    $report.Add([pscustomobject]@{
        Class = $class; Map = $pin.map; X = $pin.x; Y = $pin.y; Name = $pin.name; Id = $id; GameNameForId = $theirs
        Quests = (@($pin.quests | Select-Object -First 3) -join ' '); Decided = [string]$decided[$key]
    })
}
$report | Sort-Object Class, Map, X, Y | Export-Csv -Path $Output -NoTypeInformation -Encoding UTF8

"Probe results: $ProbeFile (build $build, $($asked.Count) NPCs asked, $($gameNames.Count) named)."
"Pins compared: $compared (with an NPC ID and a name)."
foreach ($class in 'same', 'spacing', 'contains', 'differs', 'not named', 'not asked') {
    $open = @($report | Where-Object { $_.Class -eq $class -and -not $_.Decided }).Count
    "  {0,-10}{1,7}{2}" -f $class, [int]$counts[$class], $(if ($class -ne 'same' -and $counts[$class]) { "  ($open without a row in the decisions file)" } else { '' })
}
"Written: $Output"
