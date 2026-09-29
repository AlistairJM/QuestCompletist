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

$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\QuestReputation.ps1"
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
    "MECHAGNOME"=4194304;"DRACTHYR"=8388608;"EARTHENDWARF"=16777216;"HARRONIR"=33554432;
    # Blizzard API display names that differ from the client race file names above
    "UNDEAD"=16;"EARTHEN"=16777216;"HARANIR"=33554432
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
    $body = [regex]::Match($line, '^\[\d+\]=\{(.*)\},?$').Groups[1].Value
    $hasRepCurrently = (Get-OurReputation (Split-Top $body)).Count -gt 0
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

$wago = @{}
$wagoFile = "$toolsDir\quest_wago_requirements.csv"
if (Test-Path $wagoFile) { Import-Csv $wagoFile | ForEach-Object { $wago[$_.QuestID] = $_ } }
else { Write-Output "No $wagoFile - run Get-WagoQuestRequirements.ps1 to include client-side data." }

$results = New-Object System.Collections.Generic.List[object]
$notFound = New-Object System.Collections.Generic.List[string]
$i = 0
$outFile = "$toolsDir\quest_accuracy_audit.csv"
$notFoundFile = "$toolsDir\quest_accuracy_notfound.txt"
if (Test-Path $outFile) { Remove-Item $outFile }
if (Test-Path $notFoundFile) { Remove-Item $notFoundFile }
$wroteHeader = $false

# Only a real 404 counts as "not found"; 429/5xx/timeouts are retried, then reported separately.
$cacheDir = "$toolsDir\quest_api_cache"
if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory $cacheDir | Out-Null }
$errors = New-Object System.Collections.Generic.List[string]
$errorsFile = "$toolsDir\quest_accuracy_errors.txt"
if (Test-Path $errorsFile) { Remove-Item $errorsFile }

function Get-QuestJson($questId) {
    $jsonPath = "$cacheDir\$questId.json"
    if (Test-Path "$cacheDir\$questId.404") { return "404" }
    if (Test-Path $jsonPath) { return [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8) }
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $resp = Invoke-WebRequest -UseBasicParsing -Uri "https://us.api.blizzard.com/data/wow/quest/$questId`?namespace=static-us&locale=en_US" -Headers $headers -ErrorAction Stop
            $body = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
            [System.IO.File]::WriteAllText($jsonPath, $body, (New-Object System.Text.UTF8Encoding $false))
            return $body
        } catch {
            $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
            if ($status -eq 404) {
                [System.IO.File]::WriteAllText("$cacheDir\$questId.404", "")
                return "404"
            }
            Start-Sleep -Milliseconds (500 * [math]::Pow(2, $attempt - 1))
        }
    }
    return $null
}

$uncached = @($entries | Where-Object { -not (Test-Path "$cacheDir\$($_.QuestID).json") -and -not (Test-Path "$cacheDir\$($_.QuestID).404") } | ForEach-Object { $_.QuestID })
if ($uncached.Count -gt 0) {
    $threads = 8
    Write-Output "Prefetching $($uncached.Count) uncached quests with $threads parallel workers..."
    $worker = {
        param($ids, $cacheDir, $token)
        $ProgressPreference = "SilentlyContinue"
        $utf8 = New-Object System.Text.UTF8Encoding $false
        foreach ($id in $ids) {
            try {
                $resp = Invoke-WebRequest -UseBasicParsing -Uri "https://us.api.blizzard.com/data/wow/quest/$id`?namespace=static-us&locale=en_US" -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
                [System.IO.File]::WriteAllText("$cacheDir\$id.json", [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()), $utf8)
            } catch {
                if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { [System.IO.File]::WriteAllText("$cacheDir\$id.404", "") }
            }
        }
    }
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $threads)
    $pool.Open()
    $jobs = for ($t = 0; $t -lt $threads; $t++) {
        $chunk = @(for ($k = $t; $k -lt $uncached.Count; $k += $threads) { $uncached[$k] })
        $ps = [PowerShell]::Create().AddScript($worker).AddArgument($chunk).AddArgument($cacheDir).AddArgument($token)
        $ps.RunspacePool = $pool
        [PSCustomObject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
    }
    while (@($jobs | Where-Object { -not $_.Handle.IsCompleted }).Count -gt 0) {
        Start-Sleep -Seconds 30
        Write-Output "  ...cache now holds $((Get-ChildItem $cacheDir).Count) responses"
    }
    foreach ($j in $jobs) { $j.PS.EndInvoke($j.Handle); $j.PS.Dispose() }
    $pool.Close()
}

foreach ($e in $entries) {
    $i++
    $raw = Get-QuestJson $e.QuestID
    $w = $wago[$e.QuestID]
    $mismatches = New-Object System.Collections.Generic.List[string]
    if ($raw -eq "404" -or $null -eq $raw) {
        if ($raw -eq "404") { $notFound.Add($e.QuestID) } else { $errors.Add($e.QuestID) }
        if ($i % 1000 -eq 0) { $notFound | Out-File $notFoundFile -Encoding utf8 }
        if ($i % 500 -eq 0) { Write-Output "  ...$i / $($entries.Count) (found=$($results.Count) notfound=$($notFound.Count) errors=$($errors.Count))" }
        # The API's quest endpoint doesn't serve task quests (world quests, bonus objectives),
        # but wago often has their client-side filters - compare those with the API treated as silent.
        if ($raw -ne "404" -or -not $w) { continue }
        $apiFound = $false
        $expFaction = 3; $expRace = $ALL_RACES; $expClass = $ALL_CLASSES; $expHasRep = $e.HasRepCur
    } else {
        $q = $raw | ConvertFrom-Json
        $apiFound = $true

        $expFactionType = if ($q.requirements -and $q.requirements.faction) { $q.requirements.faction.type } else { "" }
        $expFaction = switch ($expFactionType) { "ALLIANCE" { 1 }; "HORDE" { 2 }; default { 3 } }
        $classNames = if ($q.requirements -and $q.requirements.classes) { ($q.requirements.classes | ForEach-Object { $_.name }) -join ";" } else { "" }
        $raceNames = if ($q.requirements -and $q.requirements.races) { ($q.requirements.races | ForEach-Object { $_.name }) -join ";" } else { "" }
        $expRace = Resolve-Bitmask $raceNames $raceBits $ALL_RACES 8
        $expClass = Resolve-Bitmask $classNames $classBits $ALL_CLASSES 12
        $expHasRep = [bool]($q.rewards -and $q.rewards.reputations -and $q.rewards.reputations.Count -gt 0)

        if ($e.Faction -ne $expFaction) { $mismatches.Add("faction: cur=$($e.Faction) exp=$expFaction") }
        if ($e.Race -ne $expRace) { $mismatches.Add("race: cur=$($e.Race) exp=$expRace ($raceNames)") }
        if ($e.Class -ne $expClass) { $mismatches.Add("class: cur=$($e.Class) exp=$expClass ($classNames)") }
        if ($expHasRep -ne $e.HasRepCur) { $mismatches.Add("reputation: cur_has=$($e.HasRepCur) exp_has=$expHasRep") }
    }

    if ($w) {
        if ($w.WagoFaction -and [int]$w.WagoFaction -ne $e.Faction) { $mismatches.Add("wago-faction: cur=$($e.Faction) wago=$($w.WagoFaction)") }
        if ($w.WagoRace -and [int]$w.WagoRace -ne $e.Race) { $mismatches.Add("wago-race: cur=$($e.Race) wago=$($w.WagoRace)") }
        if ($w.WagoClass -and [int]$w.WagoClass -ne $e.Class) { $mismatches.Add("wago-class: cur=$($e.Class) wago=$($w.WagoClass)") }
    }

    if ($mismatches.Count -gt 0) {
        $row = [PSCustomObject]@{
            QuestID = $e.QuestID; Name = $e.Name; Mismatches = ($mismatches -join " | ")
            CurFaction = $e.Faction; ExpFaction = $expFaction; CurRace = $e.Race; ExpRace = $expRace
            CurClass = $e.Class; ExpClass = $expClass; CurHasRep = $e.HasRepCur; ExpHasRep = $expHasRep
            WagoFaction = $w.WagoFaction; WagoRace = $w.WagoRace; WagoClass = $w.WagoClass; ApiFound = $apiFound
        }
        $results.Add($row)
        $row | Export-Csv -Path $outFile -NoTypeInformation -Encoding utf8 -Append:$wroteHeader
        $wroteHeader = $true
    }

    if ($i % 500 -eq 0) { Write-Output "  ...$i / $($entries.Count) (found=$($results.Count) notfound=$($notFound.Count) errors=$($errors.Count))" }
}

$notFound | Out-File $notFoundFile -Encoding utf8
$errors | Out-File $errorsFile -Encoding utf8
Write-Output ""
Write-Output "Done. Scanned $($entries.Count) quests."
Write-Output "Discrepancies found: $($results.Count) -> $outFile"
Write-Output "Not found in API (404 - mostly task quests the endpoint doesn't serve; compared against wago only): $($notFound.Count) -> $notFoundFile"
Write-Output "Failed after retries (NOT counted as not-found - re-run to retry): $($errors.Count) -> $errorsFile"
