<#
Applies one field's FIX decisions from quest_accuracy_candidates.csv (written by
Categorize-AuditDiscrepancies.ps1) to data\quests.jsonl, then rebuilds qcQuestData.lua. Only the named
field changes. Aborts without writing if any quest is missing or its current value differs from
the CSV's.
#>
param(
    [Parameter(Mandatory)][ValidateSet("faction", "race", "class")][string]$Field,
    [string]$CandidatesCsv = (Join-Path $PSScriptRoot 'quest_accuracy_candidates.csv'),
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist')
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

$fixes = @{}
Import-Csv $CandidatesCsv | Where-Object { $_.Field -eq $Field -and $_.Decision -eq "FIX" } | ForEach-Object { $fixes[$_.QuestID] = $_ }
Write-Output "$($fixes.Count) $Field fixes to apply."

$quests = Read-QuestData $DataDir
$applied = @{}
$problems = New-Object System.Collections.Generic.List[string]
foreach ($quest in $quests) {
    $id = [string]$quest.id
    if (-not $fixes.ContainsKey($id)) { continue }
    $fix = $fixes[$id]
    if ([string]$quest.$Field -ne $fix.Cur) { $problems.Add("$id current $Field is $($quest.$Field), CSV expected $($fix.Cur)"); continue }
    Set-RecordField $quest $Field ([long]$fix.Target)
    $applied[$id] = $true
}
foreach ($id in $fixes.Keys) { if (-not $applied.ContainsKey($id) -and -not ($problems -match "^$id ")) { $problems.Add("$id not found in quests.jsonl") } }

if ($problems.Count) {
    $problems | ForEach-Object { Write-Output "PROBLEM: $_" }
    throw "$($problems.Count) problem(s) - nothing written."
}
if ($applied.Count -gt 0) { Save-QuestData $quests $DataDir $AddonDir }
Write-Output "Applied $($applied.Count) $Field fixes."
