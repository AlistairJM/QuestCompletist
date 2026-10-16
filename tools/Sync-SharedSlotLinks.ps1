<#
Step 2k of a sweep (docs/maintenance.md), both games: keeps the "only one of these" links (qcMutuallyExclusive) in step
with the game's own evidence.

The client's QuestV2.UniqueBitFlag is a quest's switch in the character's completed-quest record, and quests on one
switch are completed together: the game reports all of them done once one is. Quests of different names on one switch
that one character could be offered (faction, class and race overlap; not daily, weekly or repeatable) are "only one
of these". The probe's completed lists (QCForeverProbeDB.completed, as the game gave them) show the opposite: a linked
pair one character has done both of, on different switches, isn't one.

Each run lists, for the user to decide in the game's link-decisions file (Link "exclusive"; retail
docs\plans\quest-link-decisions.csv, Forever docs\plans\forever-quest-link-decisions.csv):
  one switch, not linked                            ADD it, or SKIP it (a SKIP chain covers a whole group)
  added for one switch, no longer on one            Blizzard changed the switches: REMOVE it, or KEEP it
  linked, but the game says one character did both  REMOVE it, or KEEP it
and, until they are written, decisions not yet in the table. It counts the links a shared switch confirms, the links
on different switches (not proof against them: the server shuts quests out by rules the client never gets), and the
breadcrumb links whose quests share a switch.

-Apply (retail) writes the ADD and REMOVE rows into qcMutuallyExclusive in QuestCompletist\qcQuest.lua, and puts a
removed pair's quests in qcFormerlyExclusive. Forever's links are written by Import-ForeverData.ps1 (step 10), which
reads the same rows. The report is tools\shared_slot_links_<game>.csv. Exit 0: nothing to decide or write; 1: a
finding.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-SharedSlotLinks.ps1 -Game retail -Build 12.1.5.70391 [-Apply]
#>
param(
    [Parameter(Mandatory)][ValidateSet('retail', 'forever')][string]$Game,
    [Parameter(Mandatory)][string]$Build,
    [string]$ToolsDir = '',
    [string]$RepoDir = '',
    [string]$ProbeResults = '',
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty in the defaults of a script with a mandatory parameter (Windows PowerShell 5.1).
if (-not $ToolsDir) { $ToolsDir = $PSScriptRoot }
if (-not $RepoDir) { $RepoDir = Join-Path $PSScriptRoot '..' }
$ProgressPreference = 'SilentlyContinue'
. "$PSScriptRoot\SharedSlots.ps1"
. "$PSScriptRoot\ProbeResults.ps1"
if ($Apply -and $Game -eq 'forever') { throw "Forever's links are written by Import-ForeverData.ps1 (step 10) from the decisions file; run without -Apply." }

$questV2 = Join-Path $ToolsDir "QuestV2-$Build.csv"
if (-not (Test-Path $questV2)) {
    Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/QuestV2/csv?build=$Build" -OutFile $questV2 -Headers @{ 'User-Agent' = 'QuestCompletist-tools' }
}
$slots = Get-QuestSlots (Import-Csv $questV2)
if ($slots.Count -lt 1000) { throw "$questV2 has only $($slots.Count) quests: is the build right?" }

$questFile = if ($Game -eq 'retail') { Join-Path $RepoDir 'data\quests.jsonl' } else { Join-Path $RepoDir 'data\forever\quests.jsonl' }
$quests = @{}
foreach ($line in [IO.File]::ReadAllLines($questFile)) { if ($line.Trim()) { $q = $line | ConvertFrom-Json; $quests[[int]$q.id] = $q } }

$luaFile = Join-Path $RepoDir 'QuestCompletist\qcQuest.lua'
function Read-Links {
    if ($Game -eq 'retail') {
        $text = [IO.File]::ReadAllText($luaFile)
        return [pscustomobject]@{
            Exclusive = Get-ListPairs (Read-LuaQuestLists $text 'qcMutuallyExclusive')
            Breadcrumb = Get-ListPairs (Read-LuaQuestLists $text 'qcBreadcrumbQuests')
        }
    }
    return Read-ForeverLinkPairs ([IO.File]::ReadAllLines((Join-Path $RepoDir 'data\forever\links.jsonl')))
}
$links = Read-Links

$decisionFile = if ($Game -eq 'retail') { Join-Path $RepoDir 'docs\plans\quest-link-decisions.csv' } else { Join-Path $RepoDir 'docs\plans\forever-quest-link-decisions.csv' }
$decisions = Read-SharedSlotDecisions (Import-Csv $decisionFile -Encoding UTF8) (Split-Path -Leaf $decisionFile)

if (-not $ProbeResults) {
    $newest = Get-ChildItem "$ToolsDir\$($Game)_probe_*\QCForeverProbe.lua" -ErrorAction SilentlyContinue |
        Sort-Object { [int]($_.Directory.Name -replace '^\w+_probe_(\d+).*$', '$1') } | Select-Object -Last 1
    if ($newest) { $ProbeResults = $newest.FullName }
}
$completions = @()
if ($ProbeResults) { $completions = @(Get-ProbeCompletions $ProbeResults) }
$probeNote = if (-not $ProbeResults) { "no probe results in $ToolsDir" }
    elseif (-not $completions.Count) { "the probe results ($ProbeResults) hold no completed lists yet: they are saved from the next login with the probe on" }
    else { "$($completions.Count) characters' completed lists from $ProbeResults" }

$groups = Get-SharedSlotGroups $slots $quests
$pairs = Get-SharedSlotPairs $groups $quests

if ($Apply) {
    $changes = Get-SharedSlotChanges $decisions $links.Exclusive $quests
    if ($changes.Adds.Count -or $changes.Removes.Count) {
        $bytes = [IO.File]::ReadAllBytes($luaFile)
        $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $text = Set-ExclusiveLinks ([IO.File]::ReadAllText($luaFile)) $changes.Adds $changes.Removes
        [IO.File]::WriteAllText($luaFile, $text, (New-Object System.Text.UTF8Encoding($bom)))
        Write-Output "Wrote qcMutuallyExclusive: $($changes.Adds.Count) pairs added, $($changes.Removes.Count) removed."
        $links = Read-Links
    } else {
        Write-Output 'qcMutuallyExclusive already holds every decision.'
    }
}

$result = Get-SharedSlotFindings $pairs $slots $quests $links.Exclusive $links.Breadcrumb $decisions $completions
$name = { param($id) if ($quests.ContainsKey([int]$id)) { $quests[[int]$id].name } else { '' } }
$rows = @($result.Findings | Sort-Object Kind, Quest, Other | ForEach-Object {
    [pscustomobject]@{ Kind = $_.Kind; Quest = $_.Quest; Name = & $name $_.Quest; Other = $_.Other; OtherName = & $name $_.Other; Decision = $_.Decision; Detail = $_.Detail }
})
$report = Join-Path $ToolsDir "shared_slot_links_$Game.csv"
$rows | Export-Csv $report -NoTypeInformation -Encoding UTF8

$c = $result.Counts
Write-Output "== $Game $Build"
Write-Output "Switches holding two or more of our non-recurring quests: $($groups.Count); pairs that could be 'only one of these': $($pairs.Count)."
Write-Output "Links: $($c.Linked); on one switch $($c.ConfirmedBySwitch), on different switches $($c.NotOnOneSwitch) (not proof against them)."
Write-Output "Breadcrumb links whose quests share a switch: $($c.BreadcrumbsOnOneSwitch)."
Write-Output "Completed lists: $probeNote; linked pairs a character did both of: $($c.CompletedBoth)."
foreach ($g in ($rows | Group-Object Kind)) { Write-Output ("  {0}: {1}" -f $g.Name, $g.Count) }
if (-not $rows.Count) { Write-Output 'No findings.'; exit 0 }
Write-Output "Findings in $report."
exit 1
