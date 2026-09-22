<#
Extracts the quest race/class restrictions that Blizzard ships in the game client
(via wago.tools DB2 exports) and converts them to the addon's own bit layout, as an
independent second source alongside Blizzard's Data API for Audit-QuestAccuracy.ps1.

Most quest requirements are server-side and not in the client at all, so coverage
is partial by nature:
  - QuestV2CliTask: explicit FiltRaceMasks/FiltClasses for task quests (world quests,
    bonus objectives, holiday quests).
  - QuestPOIBlob.PlayerConditionID -> PlayerCondition RaceMasks/ClassMask, quest-giver
    POIs only (ObjectiveIndex -1; turn-in POIs carry per-class-hall conditions that say
    nothing about who can take the quest), and only when every giver POI carries a mask.
A zero or all-bits mask means "no filter", which is treated as no information.

Output: quest_wago_requirements.csv (QuestID, WagoFaction, WagoRace, WagoClass, Source),
empty value = wago says nothing about that field.
#>
param([switch]$Refresh)

$toolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools"
$ProgressPreference = "SilentlyContinue"

foreach ($t in "QuestV2CliTask", "PlayerCondition", "ChrRaces", "ChrClasses", "QuestPOIBlob") {
    $path = "$toolsDir\$t.csv"
    if ($Refresh -or -not (Test-Path $path)) {
        Write-Output "Downloading $t..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$t/csv" -OutFile $path
        Start-Sleep -Seconds 1
    }
}

$raceBits = @{
    "HUMAN"=1;"ORC"=2;"DWARF"=4;"NIGHTELF"=8;"SCOURGE"=16;"TAUREN"=32;"GNOME"=64;"TROLL"=128;
    "GOBLIN"=256;"BLOODELF"=512;"DRAENEI"=1024;"WORGEN"=2048;"PANDAREN"=4096;"VOIDELF"=8192;
    "NIGHTBORNE"=16384;"HIGHMOUNTAINTAUREN"=32768;"LIGHTFORGEDDRAENEI"=65536;"DARKIRONDWARF"=131072;
    "MAGHARORC"=262144;"ZANDALARITROLL"=524288;"KULTIRAN"=1048576;"VULPERA"=2097152;
    "MECHAGNOME"=4194304;"DRACTHYR"=8388608;"EARTHENDWARF"=16777216;"HARRONIR"=33554432
}
$classBits = @{
    "WARRIOR"=1;"PALADIN"=2;"HUNTER"=4;"ROGUE"=8;"PRIEST"=16;"DEATHKNIGHT"=32;"SHAMAN"=64;
    "MAGE"=128;"WARLOCK"=256;"DRUID"=512;"MONK"=1024;"DEMONHUNTER"=2048;"EVOKER"=4096
}
$ALLIANCE_RACES = 64175181
$HORDE_RACES = 61658034
$NEUTRAL_RACES = $ALLIANCE_RACES -band $HORDE_RACES

# Client race masks index by ChrRaces.PlayableRaceBit; several race IDs (e.g. Pandaren
# neutral/Alliance/Horde) share one addon bit. Client class masks are 1 << (ClassID-1).
$raceByBit = @{}
foreach ($r in Import-Csv "$toolsDir\ChrRaces.csv") {
    $key = ($r.ClientFileString -replace "[^a-zA-Z]", "").ToUpper()
    if ($r.PlayableRaceBit -ne "-1" -and $raceBits.ContainsKey($key)) { $raceByBit[[int]$r.PlayableRaceBit] = $raceBits[$key] }
}
$classById = @{}
foreach ($c in Import-Csv "$toolsDir\ChrClasses.csv") {
    $key = ($c.Filename -replace "[^a-zA-Z]", "").ToUpper()
    if ($classBits.ContainsKey($key)) { $classById[[int]$c.ID] = $classBits[$key] }
}
$missingRaces = @($raceBits.Values | Where-Object { $raceByBit.Values -notcontains $_ })
if ($missingRaces.Count -or $classById.Count -ne 13) { throw "ChrRaces/ChrClasses mapping incomplete (races missing: $missingRaces, classes: $($classById.Count)/13)" }

function Convert-RaceMask($lo, $hi) {
    $m = ([long]$hi -shl 32) -bor ([long]$lo -band 0xFFFFFFFFL)
    $out = 0
    foreach ($b in $raceByBit.Keys) { if ($m -band ([long]1 -shl $b)) { $out = $out -bor $raceByBit[$b] } }
    return $out
}
function Convert-ClassMask($m) {
    $out = 0
    foreach ($id in $classById.Keys) { if ([long]$m -band ([long]1 -shl ($id - 1))) { $out = $out -bor $classById[$id] } }
    return $out
}
function Get-FactionFromRaces($race) {
    if (-not $race) { return "" }
    $a = $race -band ($ALLIANCE_RACES -band -bnot $NEUTRAL_RACES)
    $h = $race -band ($HORDE_RACES -band -bnot $NEUTRAL_RACES)
    if ($a -and -not $h) { return 1 }
    if ($h -and -not $a) { return 2 }
    return ""
}

$result = @{}
foreach ($t in Import-Csv "$toolsDir\QuestV2CliTask.csv") {
    $race = Convert-RaceMask $t.FiltRaceMasks_0 $t.FiltRaceMasks_1
    $class = Convert-ClassMask $t.FiltClasses
    if ($race -or $class) { $result[$t.ID] = @{ Race = $race; Class = $class; Source = "CliTask" } }
}

$blobConds = @{}
foreach ($b in Import-Csv "$toolsDir\QuestPOIBlob.csv") {
    if ($b.ObjectiveIndex -ne "-1") { continue }
    if (-not $blobConds.ContainsKey($b.QuestID)) { $blobConds[$b.QuestID] = New-Object System.Collections.Generic.List[string] }
    $blobConds[$b.QuestID].Add($b.PlayerConditionID)
}
$needed = @{}
foreach ($q in $blobConds.Keys) { foreach ($c in $blobConds[$q]) { if ($c -ne "0") { $needed[$c] = $true } } }
$conds = @{}
Import-Csv "$toolsDir\PlayerCondition.csv" | ForEach-Object {
    if ($needed.ContainsKey($_.ID)) { $conds[$_.ID] = @{ Race = (Convert-RaceMask $_.RaceMasks_0 $_.RaceMasks_1); Class = (Convert-ClassMask $_.ClassMask) } }
}
foreach ($q in $blobConds.Keys) {
    if ($result.ContainsKey($q)) { continue }
    $race = 0; $class = 0; $raceAll = $true; $classAll = $true
    foreach ($c in $blobConds[$q]) {
        $pc = $conds[$c]
        if (-not $pc -or -not $pc.Race) { $raceAll = $false } else { $race = $race -bor $pc.Race }
        if (-not $pc -or -not $pc.Class) { $classAll = $false } else { $class = $class -bor $pc.Class }
    }
    if (-not $raceAll) { $race = 0 }
    if (-not $classAll) { $class = 0 }
    if ($race -or $class) { $result[$q] = @{ Race = $race; Class = $class; Source = "POICondition" } }
}

$outFile = "$toolsDir\quest_wago_requirements.csv"
# A contiguous low-bit mask (e.g. class 4095 = all but Evoker) is Blizzard's own "everything
# that existed at the time", same as a stale all-classes sentinel - not a real restriction.
function Test-EraComplete([long]$m) { return ($m -ge 1023) -and (($m -band ($m + 1)) -eq 0) }
foreach ($q in @($result.Keys)) {
    if (Test-EraComplete $result[$q].Race) { $result[$q].Race = 0 }
    if (Test-EraComplete $result[$q].Class) { $result[$q].Class = 0 }
    if (-not $result[$q].Race -and -not $result[$q].Class) { $result.Remove($q) }
}
$result.GetEnumerator() | Sort-Object { [int]$_.Key } | ForEach-Object {
    [PSCustomObject]@{
        QuestID = $_.Key
        WagoFaction = Get-FactionFromRaces $_.Value.Race
        WagoRace = if ($_.Value.Race) { $_.Value.Race } else { "" }
        WagoClass = if ($_.Value.Class) { $_.Value.Class } else { "" }
        Source = $_.Value.Source
    }
} | Export-Csv $outFile -NoTypeInformation -Encoding utf8
$cliCount = @($result.Values | Where-Object { $_.Source -eq "CliTask" }).Count
Write-Output "Quests with a client-side restriction: $($result.Count) (CliTask $cliCount, POICondition $($result.Count - $cliCount)) -> $outFile"
