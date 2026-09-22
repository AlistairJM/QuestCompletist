<#
Report-only. Gathers independent evidence about whether each quest in qcQuestDatabase is still
obtainable, for building qcUnavailableQuests.lua. Makes no edits.

Quest titles are deliberately NOT used: Blizzard marks retired quests inconsistently.

Signals per quest (1 = present):
  ApiFound      Blizzard's quest API knows it (tools/quest_api_cache, from Audit-QuestAccuracy.ps1)
  IsTask        client task quest (world quest / bonus objective; QuestV2CliTask) - API never serves these
  InClient      in the client's QuestV2 table
  GiverPOI      client has a quest-giver map point (QuestPOIBlob, ObjectiveIndex -1)
  AnyPOI        client has any map point for it
  InPinDB       our qcPinDB has a pin for it
  InQuestLine   part of a client quest line (QuestLineXQuest)
  InAchievement an achievement criterion requires completing it (Criteria Type 27)
  IsPrereq      another quest in our DB lists it as its prerequisite (field 14)
Bucket: task / api-found / nontask-inclient / not-in-client

Output: quest_availability_signals.csv (every quest) plus a summary on stdout.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [string[]]$SampleIds = @()
)
$ProgressPreference = "SilentlyContinue"
$SampleIds = @($SampleIds | ForEach-Object { $_ -split "," } | Where-Object { $_ })
foreach ($t in "QuestV2", "QuestV2CliTask", "QuestPOIBlob", "QuestLineXQuest", "Criteria") {
    if (-not (Test-Path "$ToolsDir\$t.csv")) {
        Write-Output "Downloading $t..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$t/csv" -OutFile "$ToolsDir\$t.csv"
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

$pinText = [System.IO.File]::ReadAllText("$AddonDir\qcPinDB.lua")
$inPin = @{}
foreach ($m in [regex]::Matches($pinText, ',\{([\d,]+)\}\}')) { foreach ($q in $m.Groups[1].Value -split ",") { $inPin[$q] = $true } }

$content = [System.IO.File]::ReadAllText("$AddonDir\qcQuest.lua")
$start = [regex]::Match($content, '(?m)^qcQuestDatabase=\{').Index
$entries = New-Object System.Collections.Generic.List[object]
$prereqOf = @{}
$p = '^\[(\d+)\]=\{\d+,"((?:[^"\\]|\\.)*)",(\d+|Unknown),"((?:[^"\\]|\\.)*)",-?\d+,(\d+),\d+,\d+,\d+,-?\d+,-?\d+,-?\d+,-?\d+,(-?\d+)'
foreach ($l in ($content.Substring($start) -split "`r`n")) {
    $m = [regex]::Match($l, $p); if (-not $m.Success) { continue }
    $entries.Add($m)
    if ($m.Groups[6].Value -ne "0") { $prereqOf[$m.Groups[6].Value] = $true }
}

$rows = foreach ($m in $entries) {
    $id = $m.Groups[1].Value
    $api = Test-Path "$ToolsDir\quest_api_cache\$id.json"
    $bucket = if ($isTask.ContainsKey($id)) { "task" } elseif ($api) { "api-found" } elseif ($inClient.ContainsKey($id)) { "nontask-inclient" } else { "not-in-client" }
    [PSCustomObject]@{
        QuestID = $id; Name = $m.Groups[2].Value; Zone = $m.Groups[4].Value; Type = $m.Groups[5].Value; Bucket = $bucket
        ApiFound = [int]$api; IsTask = [int]$isTask.ContainsKey($id); InClient = [int]$inClient.ContainsKey($id)
        GiverPOI = [int]$giverPoi.ContainsKey($id); AnyPOI = [int]$anyPoi.ContainsKey($id); InPinDB = [int]$inPin.ContainsKey($id)
        InQuestLine = [int]$inLine.ContainsKey($id); InAchievement = [int]$inAch.ContainsKey($id); IsPrereq = [int]$prereqOf.ContainsKey($id)
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
"Non-task quests the API 404s on: $($nonTask404.Count); with NO positive signal at all: $(@($nonTask404 | Where-Object { ($_.GiverPOI + $_.AnyPOI + $_.InPinDB + $_.InQuestLine + $_.InAchievement + $_.IsPrereq) -eq 0 }).Count)"
if ($SampleIds) {
    "Samples:"
    $rows | Where-Object { $SampleIds -contains $_.QuestID } | Format-Table QuestID, Name, Bucket, InClient, GiverPOI, AnyPOI, InPinDB, InQuestLine, InAchievement, IsPrereq -AutoSize | Out-String -Width 200
}
