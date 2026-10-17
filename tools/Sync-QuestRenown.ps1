<#
Step 2o of a sweep (docs/maintenance.md): the renown or rank levels the game's own conditions ask of our task quests,
into data\renown.jsonl, which Build-AddonData.ps1 turns into qcQuestRenown. The addon reads it before the hand-kept
qcRenownLevelRequirements in qcQuest.lua, for the tooltip's "Required Renown" lines and the requirements filter
(data-sources-review recommendation 17, taken with the client tables audit's opportunity 5, part 3, on 17 October 2026).
Retail only: WoW: Forever's client has no task table and no renown currencies for its quests.

A task quest's condition (QuestV2CliTask.ConditionID) asks for renown as a renown currency (a faction's
Faction.RenownCurrencyID) held in some amount, by its own currency columns or by ModifierTree type 119; QuestConditions.ps1
(Get-ConditionRenowns) gives the levels every way through it needs. Where Blizzard's text says otherwise (four Hallowfall
quests ask for renown 3 and say "Rank 5"), the condition's level is taken: it is what the server checks. The hand rows
stay; the run says which of them the client's agree with, differ from, or say nothing about.

It downloads the build's Faction into tools\ (Faction-<build>.csv) when it isn't there, reports the rows added, changed
and gone against the data file, and the hand rows' standing. -WhatIf reports without writing. Exit 0.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sync-QuestRenown.ps1 -Build <retail build> -WhatIf
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

$factionPath = Join-Path $ToolsDir "Faction-$Build.csv"
if (-not (Test-Path $factionPath)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/Faction/csv?build=$Build" -OutFile $factionPath -Headers @{ 'User-Agent' = 'QuestCompletist-tools' } }
$renownCurrencies = @{}; $factionNames = @{}
foreach ($f in (Import-Csv $factionPath)) { $factionNames[[int]$f.ID] = $f.Name_lang; if ([int]$f.RenownCurrencyID) { $renownCurrencies[[int]$f.RenownCurrencyID] = [int]$f.ID } }

$quests = @{}
foreach ($q in (Read-QuestData $DataDir)) { $quests[[int]$q.id] = $q }
$taskPath = Join-Path $ToolsDir 'QuestV2CliTask.csv'
if (-not (Test-Path $taskPath)) { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/QuestV2CliTask/csv?build=$Build" -OutFile $taskPath }
$c = Import-ClientConditions $ToolsDir $Build
$rows = New-Object System.Collections.Generic.List[object]
foreach ($t in (Import-Csv $taskPath)) {
    $id = [int]$t.ID
    if (-not $quests.ContainsKey($id) -or $t.ConditionID -eq '0') { continue }
    $need = Get-ConditionRenowns $c ([int]$t.ConditionID) $renownCurrencies
    foreach ($faction in ($need.Keys | Sort-Object)) { $rows.Add([pscustomobject]@{ quest = $id; faction = [int]$faction; level = [int]$need[$faction] }) }
}
$rows = @($rows | Sort-Object { [long]$_.quest }, { [long]$_.faction })

$hand = @{}
$block = [regex]::Match([IO.File]::ReadAllText((Join-Path $AddonDir 'qcQuest.lua')), '(?s)qcRenownLevelRequirements = \{(.*?)\n\}')
foreach ($m in [regex]::Matches($block.Groups[1].Value, '\[(\d+)\]=\{(\d+),\s*(\d+)\}')) { $hand[[int]$m.Groups[1].Value] = @([int]$m.Groups[2].Value, [int]$m.Groups[3].Value) }
$agree = 0; $differ = New-Object System.Collections.Generic.List[string]
foreach ($id in ($hand.Keys | Sort-Object)) {
    $mine = @($rows | Where-Object { $_.quest -eq $id })
    if (-not $mine.Count) { continue }
    $same = @($mine | Where-Object { $_.faction -eq $hand[$id][0] -and $_.level -eq $hand[$id][1] })
    if ($same.Count) { $agree++ } else { $differ.Add("$id ours $($factionNames[$hand[$id][0]]) $($hand[$id][1]), the client's " + (($mine | ForEach-Object { "$($factionNames[$_.faction]) $($_.level)" }) -join ', ')) }
}

$file = Join-Path (Resolve-Path $DataDir).Path 'renown.jsonl'
$old = @{}
if (Test-Path $file) { foreach ($r in (Read-JsonLines $file)) { $old["$($r.quest)|$($r.faction)"] = [int]$r.level } }
$new = @{}; foreach ($r in $rows) { $new["$($r.quest)|$($r.faction)"] = $r.level }
$added = @($new.Keys | Where-Object { -not $old.ContainsKey($_) } | Sort-Object)
$changed = @($new.Keys | Where-Object { $old.ContainsKey($_) -and $old[$_] -ne $new[$_] } | Sort-Object)
$gone = @($old.Keys | Where-Object { -not $new.ContainsKey($_) } | Sort-Object)

"Renown from the client's conditions: $($rows.Count) rows on $(@($rows | ForEach-Object { $_.quest } | Sort-Object -Unique).Count) task quests (" +
    (($rows | Group-Object faction | Sort-Object Count -Descending | ForEach-Object { "$($factionNames[[int]$_.Name]) $($_.Count)" }) -join ', ') + ")."
"Hand rows (qcRenownLevelRequirements): $($hand.Count); the client agrees with $agree, differs from $($differ.Count), says nothing about $($hand.Count - $agree - $differ.Count)." +
    $(if ($differ.Count) { " Differ: " + ($differ -join '; ') } else { '' })
"Added $($added.Count), changed $($changed.Count), gone $($gone.Count)" + $(if ($added.Count + $changed.Count + $gone.Count -gt 0 -and $added.Count + $changed.Count + $gone.Count -le 40) { ": " + ((@($added | ForEach-Object { "+$_" }) + @($changed | ForEach-Object { "~$_" }) + @($gone | ForEach-Object { "-$_" })) -join ' ') } else { '' })

if (-not $WhatIf -and ($added.Count + $changed.Count + $gone.Count -gt 0)) { Save-RenownData $rows $DataDir $AddonDir }
