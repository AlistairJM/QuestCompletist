<#
Step 2q of a sweep (docs/maintenance.md), retail (WoW: Forever's client has no campaigns): our quest chains against the
order of the game's campaign recap (LoreTextPublic, CampaignRecap.ps1 says how it's read). A pair of recap entries next
to each other whose quests our data chains the other way round is a finding, unless docs\plans\campaign-recap-decisions.csv
keeps it (where Blizzard's own quest lines, which our chains follow, disagree with the recap). The run also lists the
recap's quests the data lacks (for step 6) and ours with no quest line. The client tables audit, opportunity 7 (the user's
choices of 17 October 2026, which also fixed five links of the Maw intro the recap showed running backwards).

It downloads the build's LoreTextPublic and the condition tables QuestConditions.ps1 reads into tools\
(<table>-<build>.csv) when they aren't there, and writes tools\campaign_recap_retail.csv (or -OutFile). A KEEP row whose
pair no longer runs the other way is a finding too. Exit 1 when there is a finding.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Compare-CampaignRecap.ps1 -Build <retail build>
#>
param(
    [string]$Build = '',
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\campaign-recap-decisions.csv'),
    [string]$OutFile = '',
    [string]$ToolsDir = '',
    [string]$DataDir = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $Build) { throw 'Give -Build: the build of the client tables to read.' }
if (-not $ToolsDir) { $ToolsDir = $PSScriptRoot }
if (-not $DataDir) { $DataDir = Join-Path $PSScriptRoot '..\data' }
if (-not $OutFile) { $OutFile = Join-Path $ToolsDir 'campaign_recap_retail.csv' }
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\QuestConditions.ps1"
. "$PSScriptRoot\CampaignRecap.ps1"

$lorePath = Join-Path $ToolsDir "LoreTextPublic-$Build.csv"
if (-not (Test-Path $lorePath)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/LoreTextPublic/csv?build=$Build" -OutFile $lorePath -Headers @{ 'User-Agent' = 'QuestCompletist-tools' } }
$c = Import-ClientConditions $ToolsDir $Build
$quests = @{}; foreach ($q in (Read-QuestData $DataDir)) { $quests[[int]$q.id] = $q }
$decisions = Read-RecapDecisions $DecisionsFile
$entries = @(Get-RecapEntries $c (Import-Csv $lorePath))
$named = @($entries | Where-Object { $_.Quest })
$ours = @($named | Where-Object { $quests.ContainsKey($_.Quest) })
$result = Get-RecapReversals $entries $quests

$inLine = @{}; foreach ($line in $c.LineQuests.Keys) { foreach ($q in $c.LineQuests[$line]) { $inLine[$q] = $true } }
$campaignName = { param($id) if ($c.Campaigns.ContainsKey($id)) { $c.Campaigns[$id].Title_lang } else { '' } }
$nameOf = { param($id) if ($quests.ContainsKey($id)) { $quests[$id].name } else { '' } }
$report = New-Object System.Collections.Generic.List[object]
$findings = New-Object System.Collections.Generic.List[string]
$seen = @{}; $kept = 0
foreach ($r in $result.Reversed) {
    $key = "$($r.Campaign)|$($r.Quest)|$($r.Later)"
    $seen[$key] = $true
    $decision = if ($decisions.ContainsKey($key)) { 'KEEP' } else { '' }
    if ($decision) { $kept++ } else { $findings.Add("campaign $($r.Campaign): $($r.Quest) $(& $nameOf $r.Quest) (recap $($r.Order)) needs $($r.Later) $(& $nameOf $r.Later) (recap $($r.LaterOrder)) in our data") }
    $report.Add([pscustomobject]@{ Kind = 'against the recap'; Campaign = $r.Campaign; CampaignName = (& $campaignName $r.Campaign); Order = $r.Order; Quest = $r.Quest; Name = (& $nameOf $r.Quest)
        Later = $r.Later; LaterName = (& $nameOf $r.Later); Decision = $decision })
}
foreach ($key in ($decisions.Keys | Sort-Object)) {
    if ($seen.ContainsKey($key)) { continue }
    $parts = $key.Split('|')
    $findings.Add("a KEEP row for campaign $($parts[0]), quests $($parts[1]) and $($parts[2]), whose pair no longer runs against the recap")
}
$lacking = @($named | Where-Object { -not $quests.ContainsKey($_.Quest) } | Select-Object -ExpandProperty Quest -Unique | Sort-Object)
foreach ($id in $lacking) {
    $e = $named | Where-Object { $_.Quest -eq $id } | Select-Object -First 1
    $report.Add([pscustomobject]@{ Kind = 'not in the data'; Campaign = $e.Campaign; CampaignName = (& $campaignName $e.Campaign); Order = $e.Order; Quest = $id; Name = ''; Later = ''; LaterName = ''; Decision = '' })
}
$lineless = @($ours | Where-Object { -not $inLine.ContainsKey($_.Quest) } | Select-Object -ExpandProperty Quest -Unique | Sort-Object)
foreach ($id in $lineless) {
    $e = $ours | Where-Object { $_.Quest -eq $id } | Select-Object -First 1
    $report.Add([pscustomobject]@{ Kind = 'no quest line'; Campaign = $e.Campaign; CampaignName = (& $campaignName $e.Campaign); Order = $e.Order; Quest = $id; Name = (& $nameOf $id); Later = ''; LaterName = ''; Decision = '' })
}
$report | Export-Csv $OutFile -NoTypeInformation -Encoding UTF8

"Campaign recap ($(Split-Path -Leaf $lorePath)): $($entries.Count) entries in $(@($entries | Select-Object -ExpandProperty Campaign -Unique).Count) campaigns; $($named.Count) name a quest ($(@($named | Select-Object -ExpandProperty Quest -Unique).Count) quests, $(@($ours | Select-Object -ExpandProperty Quest -Unique).Count) of them ours)."
"Our chains against the recap's order: $($result.Compared) pairs of entries next to each other; $(@($result.Reversed).Count) run the other way, $kept of them kept."
"The recap's quests the data lacks (step 6's to look at): $($lacking.Count)" + $(if ($lacking.Count) { ": " + ($lacking -join ', ') } else { '' })
"Ours with no quest line: $($lineless.Count)" + $(if ($lineless.Count) { ": " + (($lineless | ForEach-Object { "$_ $(& $nameOf $_)" }) -join '; ') } else { '' })
"Findings: $($findings.Count)" + $(if ($findings.Count) { ": " + (($findings | Select-Object -First 20) -join '; ') } else { '' })
"Report: $OutFile ($($report.Count) rows)."
exit $(if ($findings.Count) { 1 } else { 0 })
