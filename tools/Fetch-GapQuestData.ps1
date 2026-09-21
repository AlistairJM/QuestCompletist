<#
Fetches basic quest data (title, level, area, faction, class/race requirements)
from Blizzard's Data API for the quest IDs found in wago.tools' location data but
missing from our own qcQuestDatabase, so map pins for them show real info instead
of "Quest Missing in DB".
#>

$toolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools"

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

$questIds = Get-Content "$toolsDir\gap_quest_ids.txt" | Where-Object { $_ -match '\S' }
Write-Output "Fetching data for $($questIds.Count) quests..."

$results = New-Object System.Collections.Generic.List[object]
$notFound = 0
$i = 0
foreach ($qid in $questIds) {
    $i++
    try {
        $q = Invoke-RestMethod -Uri "https://us.api.blizzard.com/data/wow/quest/$qid`?namespace=static-us&locale=en_US" -Headers $headers -ErrorAction Stop
        $factionType = if ($q.requirements -and $q.requirements.faction) { $q.requirements.faction.type } else { "" }
        $classNames = if ($q.requirements -and $q.requirements.classes) { ($q.requirements.classes | ForEach-Object { $_.name }) -join ";" } else { "" }
        $raceNames = if ($q.requirements -and $q.requirements.races) { ($q.requirements.races | ForEach-Object { $_.name }) -join ";" } else { "" }
        $results.Add([PSCustomObject]@{
            QuestID    = $qid
            Title      = $q.title
            Level      = if ($q.requirements -and $q.requirements.min_character_level) { $q.requirements.min_character_level } else { 0 }
            AreaName   = if ($q.area) { $q.area.name } else { "" }
            Faction    = $factionType
            ClassNames = $classNames
            RaceNames  = $raceNames
        })
    } catch {
        $notFound++
    }
    if ($i % 50 -eq 0) { Write-Output "  ...$i / $($questIds.Count)" }
    Start-Sleep -Milliseconds 50
}

Write-Output "Fetched: $($results.Count)  Not found (404 etc): $notFound"
$results | Export-Csv -Path "$toolsDir\gap_quest_data.csv" -NoTypeInformation -Encoding utf8
Write-Output "Written to $toolsDir\gap_quest_data.csv"
