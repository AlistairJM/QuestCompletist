<#
Gives the task quests (world quests, bonus objectives, callings and the like) the profession they
need, from the client. The API doesn't serve task quests, and nothing else names a profession for a
retail quest that was added since Mists of Pandaria, so a gathering or crafting world quest was
shown to every character and kept by "Hide Other Profession Quests" for none.

Two columns of the client's QuestV2CliTask say it, and agree wherever both do (506 of 506 quests of
ours in October 2026):
  - FiltMinSkillID, the skill the character needs, in the expansion's own line of the profession
    (Legion Mining, Kul Tiran Herbalism, Shadowlands Cooking). The line's SkillLine row gives its
    base profession as ParentSkillLineID.
  - QuestInfoID, whose QuestInfo row has the base profession's skill line (Herbalism World Quest).
The base profession's bit is the one qcProfessionBits in qcCore.lua gives.

Only a quest with no profession is given one. A quest of ours whose profession differs from the
client's is left as it is and listed, as is a quest the two columns disagree on, or one whose skill
line has no bit. The skill level the quest asks for (FiltMinSkillValue) isn't read here: it belongs
with the skill requirements (qcQuestSkillRequirements), which retail doesn't fill yet (game-parity.md).

Reads tools\QuestV2CliTask.csv, QuestInfo.csv and SkillLine.csv, downloaded for -Build when they're
missing or -Refresh is given. Safe to rerun: it only finds new cases. With -WhatIf it only reports;
otherwise it saves through AddonData.ps1, which rebuilds the Lua.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = "12.1.0.69933",
    [switch]$Refresh,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\AddonData.ps1"

foreach ($table in 'QuestV2CliTask', 'QuestInfo', 'SkillLine') {
    $path = Join-Path $ToolsDir "$table.csv"
    if ($Refresh -or -not (Test-Path $path)) {
        Write-Output "Downloading $table..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path
        Start-Sleep -Seconds 1
    }
}

$core = [IO.File]::ReadAllText((Join-Path $AddonDir 'qcCore.lua'))
$block = [regex]::Match($core, '(?s)qcProfessionBits = \{(.*?)\}').Groups[1].Value
$bitOf = @{}
foreach ($m in [regex]::Matches($block, '\[(\d+)\]\s*=\s*(\d+)')) { $bitOf[[int]$m.Groups[1].Value] = [int]$m.Groups[2].Value }
if ($bitOf.Count -eq 0) { throw "qcProfessionBits wasn't found in $AddonDir\qcCore.lua" }

$parent = @{}
foreach ($row in Import-Csv (Join-Path $ToolsDir 'SkillLine.csv')) { $parent[[int]$row.ID] = [int]$row.ParentSkillLineID }
# The bit of a skill line's profession, going up from an expansion's line to its base; 0 when there's none.
function Get-ProfessionBit([int]$line) {
    for ($step = 0; $line -gt 0 -and $step -lt 5; $step++) {
        if ($bitOf.ContainsKey($line)) { return $bitOf[$line] }
        $line = $parent[$line]
    }
    return 0
}
$infoProfession = @{}
foreach ($row in Import-Csv (Join-Path $ToolsDir 'QuestInfo.csv')) { if ([int]$row.Profession) { $infoProfession[[int]$row.ID] = [int]$row.Profession } }

$records = Read-QuestData $DataDir
$quests = @{}
foreach ($q in $records) { $quests[[int]$q.id] = $q }

$counts = [ordered]@{ tasks = 0; named = 0; set = 0; same = 0 }
$disagree = New-Object System.Collections.Generic.List[string]
$differ = New-Object System.Collections.Generic.List[string]
$noBit = New-Object System.Collections.Generic.List[string]
$changes = New-Object System.Collections.Generic.List[object]
foreach ($task in (Import-Csv (Join-Path $ToolsDir 'QuestV2CliTask.csv'))) {
    $id = [int]$task.ID
    if (-not $quests.ContainsKey($id)) { continue }
    $counts.tasks++
    $q = $quests[$id]
    $bySkill = 0; $byType = 0
    if ([int]$task.FiltMinSkillID) {
        $bySkill = Get-ProfessionBit ([int]$task.FiltMinSkillID)
        if (-not $bySkill) { $noBit.Add("$id $($q.name): skill line $($task.FiltMinSkillID)") }
    }
    $line = $infoProfession[[int]$task.QuestInfoID]
    if ($line) {
        $byType = Get-ProfessionBit $line
        if (-not $byType) { $noBit.Add("$id $($q.name): skill line $line of quest type $($task.QuestInfoID)") }
    }
    if ($bySkill -and $byType -and $bySkill -ne $byType) { $disagree.Add("$id $($q.name): its skill filter says $bySkill, its quest type $byType"); continue }
    $bit = if ($bySkill) { $bySkill } else { $byType }
    if (-not $bit) { continue }
    $counts.named++
    $current = [int]$q.profession
    if ($current -eq $bit) { $counts.same++ }
    elseif ($current) { $differ.Add("$id $($q.name): ours $current, the client's $bit") }
    else { $counts.set++; $changes.Add(@($q, $bit)) }
}

"{0} task quests of ours; the client names a profession for {1}: {2} get it, {3} already match." -f $counts.tasks, $counts.named, $counts.set, $counts.same
if ($differ.Count) { "Ours differs, left as it is ($($differ.Count)):"; $differ | ForEach-Object { "  $_" } }
if ($disagree.Count) { "Its two columns disagree, left out ($($disagree.Count)):"; $disagree | ForEach-Object { "  $_" } }
if ($noBit.Count) { "No profession bit for the skill line, left out ($($noBit.Count)):"; $noBit | ForEach-Object { "  $_" } }
if ($WhatIf) {
    foreach ($change in ($changes | Select-Object -First 25)) { "  {0} {1}: profession {2}" -f $change[0].id, $change[0].name, $change[1] }
    return
}
foreach ($change in $changes) { Set-RecordField $change[0] 'profession' $change[1] }
Save-QuestData $records $DataDir $AddonDir
