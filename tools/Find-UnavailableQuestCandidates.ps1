<#
Report-only. Gathers independent evidence about whether each quest in data\quests.jsonl is still
obtainable, for building qcUnavailableQuests.lua. Makes no edits.

Quest titles are deliberately NOT used: Blizzard marks retired quests inconsistently.

Signals per quest (1 = present):
  ApiFound      Blizzard's quest API knows it (tools/quest_api_cache, from Audit-QuestAccuracy.ps1)
  IsTask        client task quest (world quest / bonus objective; QuestV2CliTask) - API never serves these
  InClient      in the client's QuestV2 table, which never lists repeatable quests: none of the
                500 the API flags repeatable are in it. Missing from it proves nothing on its own.
  ServerKnows   the server sent the quest's data to the /qc typecheck probe (its saved results,
                quest_type_probe_results.lua); 0 if it didn't, blank if the probe never asked.
                Missing from QuestV2 with ServerKnows 0 is the one sure sign a quest is gone.
  GiverPOI      client has a quest-giver map point (QuestPOIBlob, ObjectiveIndex -1)
  AnyPOI        client has any map point for it
  InPinDB       one of our pins (data\pins.jsonl) offers it
  InQuestLine   part of a client quest line (QuestLineXQuest)
  InAchievement an achievement criterion requires completing it (Criteria Type 27)
  IsPrereq      another of our quests lists it among its prerequisites
Bucket: task / api-found / nontask-inclient / not-in-client
Decision: the quest's row in docs\plans\unavailable-quest-decisions.csv (FLAG or KEEP), if reviewed.

Output: quest_availability_signals.csv (every quest) plus a summary on stdout, which counts the
quests with no positive signal that have no decision yet: the ones to review.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$Decisions = (Join-Path $PSScriptRoot '..\docs\plans\unavailable-quest-decisions.csv'),
    [string]$ProbeResults = (Join-Path $PSScriptRoot 'quest_type_probe_results.lua'),
    [string[]]$SampleIds = @(),
    [string]$Build = "12.1.0.69933",
    [switch]$Refresh
)
$ProgressPreference = "SilentlyContinue"
$SampleIds = @($SampleIds | ForEach-Object { $_ -split "," } | Where-Object { $_ })
foreach ($t in "QuestV2", "QuestV2CliTask", "QuestPOIBlob", "QuestLineXQuest", "Criteria") {
    if ($Refresh -or -not (Test-Path "$ToolsDir\$t.csv")) {
        Write-Output "Downloading $t..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$t/csv?build=$Build" -OutFile "$ToolsDir\$t.csv"
        Start-Sleep -Seconds 1
    }
}

function Set-Of($ids) { $h = @{}; foreach ($i in $ids) { $h["$i"] = $true }; return $h }
$inClient = Set-Of (Import-Csv "$ToolsDir\QuestV2.csv" | ForEach-Object ID)
$isTask = Set-Of (Import-Csv "$ToolsDir\QuestV2CliTask.csv" | ForEach-Object ID)
$blobs = Import-Csv "$ToolsDir\QuestPOIBlob.csv"
$anyPoi = Set-Of ($blobs | ForEach-Object QuestID)
$giverPoi = Set-Of ($blobs | Where-Object ObjectiveIndex -eq "-1" | ForEach-Object QuestID)
$inLine = Set-Of (Import-Csv "$ToolsDir\QuestLineXQuest.csv" | ForEach-Object QuestID)
$inAch = Set-Of (Import-Csv "$ToolsDir\Criteria.csv" | Where-Object Type -eq "27" | ForEach-Object Asset)

. "$PSScriptRoot\AddonData.ps1"
$inPin = @{}
foreach ($pin in (Read-PinData $DataDir)) { foreach ($q in $pin.quests) { $inPin["$q"] = $true } }

$entries = @(Read-QuestData $DataDir)
$prereqOf = @{}
foreach ($quest in $entries) { if ($quest.prereq) { foreach ($id in (Get-PrereqQuests $quest.prereq)) { $prereqOf["$id"] = $true } } }
$decided = @{}
foreach ($row in Import-Csv $Decisions) { $decided[$row.QuestID] = $row.Decision }
$serverKnows = @{}
if (Test-Path $ProbeResults) {
    $probe = [System.IO.File]::ReadAllText($ProbeResults)
    foreach ($m in [regex]::Matches($probe, '(?m)^\[(\d+)\] = "\d+\|[^|]*\|\d+,[01-],([01])",?\s*$')) { $serverKnows[$m.Groups[1].Value] = $m.Groups[2].Value }
} else { Write-Warning "No probe results at $ProbeResults, so ServerKnows is blank" }

$rows = foreach ($quest in $entries) {
    $id = [string]$quest.id
    $api = Test-Path "$ToolsDir\quest_api_cache\$id.json"
    $bucket = if ($isTask.ContainsKey($id)) { "task" } elseif ($api) { "api-found" } elseif ($inClient.ContainsKey($id)) { "nontask-inclient" } else { "not-in-client" }
    [PSCustomObject]@{
        QuestID = $id; Name = $quest.name; Zone = $quest.zone; Type = [string]$quest.type; Bucket = $bucket
        ApiFound = [int]$api; IsTask = [int]$isTask.ContainsKey($id); InClient = [int]$inClient.ContainsKey($id)
        ServerKnows = [string]$serverKnows[$id]
        GiverPOI = [int]$giverPoi.ContainsKey($id); AnyPOI = [int]$anyPoi.ContainsKey($id); InPinDB = [int]$inPin.ContainsKey($id)
        InQuestLine = [int]$inLine.ContainsKey($id); InAchievement = [int]$inAch.ContainsKey($id); IsPrereq = [int]$prereqOf.ContainsKey($id)
        Decision = [string]$decided[$id]
    }
}
$rows | Export-Csv "$ToolsDir\quest_availability_signals.csv" -NoTypeInformation -Encoding utf8

$signals = "InClient", "GiverPOI", "AnyPOI", "InPinDB", "InQuestLine", "InAchievement", "IsPrereq"
"Share of quests with each signal, by bucket:"
"{0,-18}{1,7}  {2}" -f "bucket", "quests", (($signals | ForEach-Object { "{0,13}" -f $_ }) -join "")
foreach ($g in $rows | Group-Object Bucket | Sort-Object Name) {
    $n = $g.Count
    "{0,-18}{1,7}  {2}" -f $g.Name, $n, (($signals | ForEach-Object { $s = $_; "{0,12:P0} " -f ((@($g.Group | Where-Object { $_.$s -eq 1 }).Count) / $n) }) -join "")
}
$nonTask404 = @($rows | Where-Object { $_.Bucket -in "nontask-inclient", "not-in-client" })
$noSignal = @($nonTask404 | Where-Object { ($_.GiverPOI + $_.AnyPOI + $_.InPinDB + $_.InQuestLine + $_.InAchievement + $_.IsPrereq) -eq 0 })
"Non-task quests the API 404s on: $($nonTask404.Count); with NO positive signal at all: $($noSignal.Count), of which not yet decided: $(@($noSignal | Where-Object { -not $_.Decision }).Count)"
$notInClient = @($nonTask404 | Where-Object { $_.InClient -eq 0 })
"Of those not in QuestV2 ($($notInClient.Count)), unknown to the server too, so surely gone: $(@($notInClient | Where-Object { $_.ServerKnows -eq '0' }).Count)"
if ($SampleIds) {
    "Samples:"
    $rows | Where-Object { $SampleIds -contains $_.QuestID } | Format-Table QuestID, Name, Bucket, InClient, ServerKnows, GiverPOI, AnyPOI, InPinDB, InQuestLine, InAchievement, IsPrereq -AutoSize | Out-String -Width 200
}
