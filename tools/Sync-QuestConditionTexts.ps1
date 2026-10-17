<#
Step 2m of a sweep (docs/maintenance.md): the game's own text for a condition that holds a quest back ("Requires further
advancement in the Argus Campaign.", "Reach level 30 to continue your Order Hall campaign."), in every client language,
into data\conditiontexts.jsonl, which Build-AddonData.ps1 turns into qcQuestConditionTexts and qcConditionTexts. The quest
list's tooltip shows it while the quest isn't done, as information: the addon can't tell whether the condition is met
(the client tables audit, opportunity 4, part D, the user's choice on 17 October 2026). Retail only: WoW: Forever's
client has no task table and no quest table that names a condition, so it has no such text for a quest.

Which conditions hold which quests back is QuestConditions.ps1's Get-ConditionTextKeys: a task quest's own condition,
and the gates of quest lines, campaigns and campaign chapters on their first quest of ours. The texts are each
condition's PlayerCondition.Failure_description_lang and each chapter gate's CampaignXCondition.FailureReason_lang, read
from the build's tables in each language (tools\<table>-<build>.<locale>.csv, downloaded when missing: PlayerCondition
is about 17 MB a language). A language whose tables are enUS's byte for byte is English under its name and is left out,
as is a text that is enUS's word for word: the addon shows enUS's. A text that names a game variable ($pcMinLevel) is
left out and listed, as only the game can fill it.

It reports the texts added, gone and changed against the data file, and how many each language translates. -WhatIf
reports without writing. Exit 0.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-QuestConditionTexts.ps1 -Build <retail build> -WhatIf
#>
param(
    [string]$Build = '',
    [string]$ToolsDir = '',
    [string]$DataDir = '',
    [string]$AddonDir = '',
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $Build) { throw 'Give -Build: the build of the client tables to read.' }
if (-not $ToolsDir) { $ToolsDir = $PSScriptRoot }
if (-not $DataDir) { $DataDir = Join-Path $PSScriptRoot '..\data' }
if (-not $AddonDir) { $AddonDir = Join-Path $PSScriptRoot '..\QuestCompletist' }
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\QuestConditions.ps1"
. "$PSScriptRoot\ConditionTexts.ps1"

function Get-LocaleTable([string]$table, [string]$locale) {
    $path = Join-Path $ToolsDir "$table-$Build.$locale.csv"
    if (-not (Test-Path $path)) {
        Write-Host "Downloading $table ($locale, $Build)..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build&locale=$locale" -OutFile $path -Headers @{ 'User-Agent' = 'QuestCompletist-tools' }
        Start-Sleep -Seconds 1
    }
    return $path
}

$quests = @{}
foreach ($q in (Read-QuestData $DataDir)) { $quests[[int]$q.id] = $q }
$taskPath = Join-Path $ToolsDir 'QuestV2CliTask.csv'
if (-not (Test-Path $taskPath)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/QuestV2CliTask/csv?build=$Build" -OutFile $taskPath }
$c = Import-ClientConditions $ToolsDir $Build
$taskConditions = @{}
foreach ($t in (Import-Csv $taskPath)) { if ($t.ConditionID -ne '0' -and $quests.ContainsKey([int]$t.ID)) { $taskConditions[[int]$t.ID] = [int]$t.ConditionID } }
$keys = Get-ConditionTextKeys $c $taskConditions $quests
$wantedPlayer = @{}; $wantedChapter = @{}
foreach ($key in $keys.Keys) { if ($key.StartsWith('p')) { $wantedPlayer[[int]$key.Substring(1)] = $true } else { $wantedChapter[[int]$key.Substring(1)] = $true } }

$tables = @{}
$hashes = @{}
foreach ($locale in $ConditionTextLocales) {
    $playerPath = Get-LocaleTable 'PlayerCondition' $locale
    $chapterPath = Get-LocaleTable 'CampaignXCondition' $locale
    $hash = (Get-FileHash $playerPath -Algorithm SHA256).Hash + (Get-FileHash $chapterPath -Algorithm SHA256).Hash
    $hashes[$locale] = $hash
    $tables[$locale] = Read-ConditionTexts (Import-Csv $playerPath -Encoding UTF8) (Import-Csv $chapterPath -Encoding UTF8) $wantedPlayer $wantedChapter
    $tables[$locale].English = $locale -ne 'enUS' -and $hash -eq $hashes['enUS']
}
$result = Get-ConditionTextRecords $keys $tables $ConditionTextLocales
$records = $result.Records

$file = Join-Path (Resolve-Path $DataDir).Path 'conditiontexts.jsonl'
$old = @{}
if (Test-Path $file) { foreach ($t in (Read-JsonLines $file)) { $old[$t.key] = (ConvertTo-ConditionTextJsonLines @($t)) } }
$added = @(); $changed = @()
foreach ($r in $records) {
    if (-not $old.ContainsKey($r.key)) { $added += $r.key }
    elseif ($old[$r.key] -cne (ConvertTo-ConditionTextJsonLines @($r))) { $changed += $r.key }
}
$gone = @($old.Keys | Where-Object { $k = $_; -not @($records | Where-Object { $_.key -eq $k }).Count } | Sort-Object)

$questCount = @($records | ForEach-Object { $_.quests } | Sort-Object -Unique).Count
"Condition texts: $($records.Count) for $questCount quests (task conditions $(@($records | Where-Object { $_.key.StartsWith('p') }).Count), chapter gates $(@($records | Where-Object { $_.key.StartsWith('c') }).Count))."
"Translated: " + (($ConditionTextLocales | Where-Object { $_ -ne 'enUS' } | ForEach-Object { $l = $_; "$l $(@($records | Where-Object { $_.$l }).Count)" + $(if ($tables[$l].English) { ' (enUS tables)' } else { '' }) }) -join ', ')
"Added $($added.Count), changed $($changed.Count), gone $($gone.Count)" + $(if ($added.Count + $changed.Count + $gone.Count -gt 0 -and $added.Count + $changed.Count + $gone.Count -le 40) { ": " + ((@($added | ForEach-Object { "+$_" }) + @($changed | ForEach-Object { "~$_" }) + @($gone | ForEach-Object { "-$_" })) -join ' ') } else { '' })
if ($result.Skipped.Count) { "Left out: " + ($result.Skipped -join '; ') }

if (-not $WhatIf -and ($added.Count + $changed.Count + $gone.Count -gt 0)) { Save-ConditionTextData $records $DataDir $AddonDir }
