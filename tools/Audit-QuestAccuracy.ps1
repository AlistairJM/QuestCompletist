<#
Report-only audit of the ENTIRE qcQuestDatabase (all ~35k quests) against
Blizzard's Data API for faction/race/class/reputation accuracy. Does NOT
modify qcQuest.lua - writes a CSV of every discrepancy found, plus a
separate list of quest IDs Blizzard's API no longer knows about (old/
removed content - expected, not itself a bug), for manual review before
any fix gets applied.

Field layout is NOT uniform across the database: older hand-curated
entries can be as short as 14 fields (id, name, level, zone, areaid,
type, faction, race, class, profession, holiday, covenant, storyline,
prereq), missing field15/factionid/repvalue entirely (Lua just returns
nil for the missing trailing fields, which the tooltip code already
guards against). Only id/name/level/areaid/type/faction/race/class
(the first 9 fields) are reliably present in every entry; everything
after class is parsed as a flexible tail.

Reuses the exact same bitmask-resolution rules already used and verified
in Insert-GapQuestEntries.ps1.
#>

$toolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools"
$questFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"

$envFile = "$toolsDir\.env"
$envVars = @{}
Get-Content $envFile | ForEach-Object { if ($_ -match '^([^=]+)=(.*)$') { $envVars[$matches[1]] = $matches[2] } }
$clientId = $envVars["BLIZZARD_CLIENT_ID"]
$clientSecret = $envVars["BLIZZARD_CLIENT_SECRET"]
$pair = "$clientId`:$clientSecret"
$basicAuth = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$tokenResponse = Invoke-RestMethod -Uri "https://oauth.battle.net/token" -Method Post -Headers @{ Authorization = "Basic $basicAuth" } -Body @{ grant_type = "client_credentials" } -ContentType "application/x-www-form-urlencoded"
$token = $tokenResponse.access_token
$headers = @{ Authorization = "Bearer $token" }

$classBits = @{
    "WARRIOR"=1;"PALADIN"=2;"HUNTER"=4;"ROGUE"=8;"PRIEST"=16;"DEATHKNIGHT"=32;"SHAMAN"=64;
    "MAGE"=128;"WARLOCK"=256;"DRUID"=512;"MONK"=1024;"DEMONHUNTER"=2048;"EVOKER"=4096
}
$raceBits = @{
    "HUMAN"=1;"ORC"=2;"DWARF"=4;"NIGHTELF"=8;"SCOURGE"=16;"TAUREN"=32;"GNOME"=64;"TROLL"=128;
    "GOBLIN"=256;"BLOODELF"=512;"DRAENEI"=1024;"WORGEN"=2048;"PANDAREN"=4096;"VOIDELF"=8192;
    "NIGHTBORNE"=16384;"HIGHMOUNTAINTAUREN"=32768;"LIGHTFORGEDDRAENEI"=65536;"DARKIRONDWARF"=131072;
    "MAGHARORC"=262144;"ZANDALARITROLL"=524288;"KULTIRAN"=1048576;"VULPERA"=2097152;
    "MECHAGNOME"=4194304;"DRACTHYR"=8388608;"EARTHENDWARF"=16777216;"HARRONIR"=33554432
}
$ALL_RACES = 67108863
$ALL_CLASSES = 8191
function Normalize($s) { return ($s -replace "[^a-zA-Z0-9]", "").ToUpper() }

function Resolve-Bitmask($namesJoined, $bitTable, $allValue, $maxNarrow) {
    if (-not $namesJoined) { return $allValue }
    $names = $namesJoined -split ";"
    if ($names -contains "Adventurer") { return $allValue }
    if ($names.Count -gt $maxNarrow) { return $allValue }
    $mask = 0
    foreach ($n in $names) {
        $key = Normalize $n
        if (-not $bitTable.ContainsKey($key)) { return $allValue }
        $mask = $mask -bor $bitTable[$key]
    }
    if ($mask -eq 0) { return $allValue }
    return $mask
}

Write-Output "Parsing current qcQuestDatabase..."
$content = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($questFile))
$anchor = [regex]::Match($content, '(?m)^qcQuestDatabase=\{')
$dbBlock = $content.Substring($anchor.Index)
$lines = $dbBlock -split "`r`n"
$allIdLines = $lines | Where-Object { $_ -match '^\[\d+\]=\{' }
$entryPattern = '^\[(\d+)\]=\{\d+,"((?:[^"\\]|\\.)*)",(\d+|Unknown),"(?:[^"\\]|\\.)*",(-?\d+),(\d+),(\d+),(\d+),(\d+),(.*)\},?$'

$entries = New-Object System.Collections.Generic.List[object]
foreach ($line in $allIdLines) {
    $m = [regex]::Match($line, $entryPattern)
    if (-not $m.Success) { Write-Output "PARSE FAILURE (skipped): $line"; continue }
    $tail = $m.Groups[9].Value
    $hasRepCurrently = $false
    if ($tail -match ',[1-9]\d*,\{') { $hasRepCurrently = $true }
    elseif ($tail -match ',[1-9]\d*,[1-9]\d*\s*$') { $hasRepCurrently = $true }
    $entries.Add([PSCustomObject]@{
        QuestID   = $m.Groups[1].Value
        Name      = $m.Groups[2].Value
        Faction   = [int]$m.Groups[6].Value
        Race      = [int]$m.Groups[7].Value
        Class     = [int]$m.Groups[8].Value
        HasRepCur = $hasRepCurrently
    })
}
Write-Output "Parsed $($entries.Count) / $($allIdLines.Count) quest entries."

$results = New-Object System.Collections.Generic.List[object]
$notFound = New-Object System.Collections.Generic.List[string]
$i = 0
$outFile = "$toolsDir\quest_accuracy_audit.csv"
$notFoundFile = "$toolsDir\quest_accuracy_notfound.txt"
if (Test-Path $outFile) { Remove-Item $outFile }
if (Test-Path $notFoundFile) { Remove-Item $notFoundFile }
$wroteHeader = $false

foreach ($e in $entries) {
    $i++
    try {
        $q = Invoke-RestMethod -Uri "https://us.api.blizzard.com/data/wow/quest/$($e.QuestID)`?namespace=static-us&locale=en_US" -Headers $headers -ErrorAction Stop
    } catch {
        $notFound.Add($e.QuestID)
        if ($i % 1000 -eq 0) { $notFound | Out-File $notFoundFile -Encoding utf8 }
        if ($i % 500 -eq 0) { Write-Output "  ...$i / $($entries.Count) (found=$($results.Count) notfound=$($notFound.Count))" }
        Start-Sleep -Milliseconds 30
        continue
    }

    $expFactionType = if ($q.requirements -and $q.requirements.faction) { $q.requirements.faction.type } else { "" }
    $expFaction = switch ($expFactionType) { "ALLIANCE" { 1 }; "HORDE" { 2 }; default { 3 } }
    $classNames = if ($q.requirements -and $q.requirements.classes) { ($q.requirements.classes | ForEach-Object { $_.name }) -join ";" } else { "" }
    $raceNames = if ($q.requirements -and $q.requirements.races) { ($q.requirements.races | ForEach-Object { $_.name }) -join ";" } else { "" }
    $expRace = Resolve-Bitmask $raceNames $raceBits $ALL_RACES 8
    $expClass = Resolve-Bitmask $classNames $classBits $ALL_CLASSES 12
    $expHasRep = [bool]($q.rewards -and $q.rewards.reputations -and $q.rewards.reputations.Count -gt 0)

    $mismatches = New-Object System.Collections.Generic.List[string]
    if ($e.Faction -ne $expFaction) { $mismatches.Add("faction: cur=$($e.Faction) exp=$expFaction") }
    if ($e.Race -ne $expRace) { $mismatches.Add("race: cur=$($e.Race) exp=$expRace ($raceNames)") }
    if ($e.Class -ne $expClass) { $mismatches.Add("class: cur=$($e.Class) exp=$expClass ($classNames)") }
    if ($expHasRep -ne $e.HasRepCur) { $mismatches.Add("reputation: cur_has=$($e.HasRepCur) exp_has=$expHasRep") }

    if ($mismatches.Count -gt 0) {
        $row = [PSCustomObject]@{ QuestID = $e.QuestID; Name = $e.Name; Mismatches = ($mismatches -join " | ") }
        $results.Add($row)
        $row | Export-Csv -Path $outFile -NoTypeInformation -Encoding utf8 -Append:$wroteHeader
        $wroteHeader = $true
    }

    if ($i % 500 -eq 0) { Write-Output "  ...$i / $($entries.Count) (found=$($results.Count) notfound=$($notFound.Count))" }
    Start-Sleep -Milliseconds 30
}

$notFound | Out-File $notFoundFile -Encoding utf8
Write-Output ""
Write-Output "Done. Scanned $($entries.Count) quests."
Write-Output "Discrepancies found: $($results.Count) -> $outFile"
Write-Output "Not found in API (likely old/removed content): $($notFound.Count) -> $notFoundFile"
