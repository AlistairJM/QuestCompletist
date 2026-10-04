<#
Generates the quest storyline data from Blizzard's own questline tables (QuestLine and
QuestLineXQuest on wago.tools, pinned to one build):

  - qcQuestLines in qcQuest.lua: [questLineID] = {name = "...", quests = {...}} - the storyline's
    name and its quests in Blizzard's order (OrderIndex), limited to quests we have.
  - every quest's storyline in data\quests.jsonl (left out when it has none), then qcQuest.lua is
    rebuilt.

Questlines with internal names ("8.0 Professions - ... - SCS", "[DNT] ...", "Test Questline") are
never shown. A quest in several questlines is given the most specific one - the fewest quests,
then the lowest ID - so a campaign chapter wins over the whole campaign.

All-or-nothing: if the Lua doesn't match the data files, or the qcQuestLines block isn't found as
expected, nothing is written.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = "12.1.0.69933",
    [switch]$Refresh
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

$ProgressPreference = "SilentlyContinue"
foreach ($table in "QuestLine", "QuestLineXQuest") {
    $path = "$ToolsDir\$table-$Build.csv"
    if ($Refresh -or -not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path
        Start-Sleep -Milliseconds 300
    }
}

$internalName = '^\s*$|^\d+\.\d|\[DNT\]|\(DNT\)|\[PH\]|\[DEPRECATED\]|\(STM\)|\(POC\)|- SCS$|(?i)\btest\b|^Zone \d+ Neck \d+$|^Catch Up: .*Wrapper'

# qcQuestLines is written into qcQuest.lua before the quests are saved, so check first that saving
# them won't refuse.
Assert-LuaMatchesData $DataDir $AddonDir
$questFile = "$AddonDir\qcQuest.lua"
$content = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)

$questRecords = Read-QuestData $DataDir
$ourQuests = @{}
$before = @{}
foreach ($quest in $questRecords) {
    $ourQuests[[string]$quest.id] = $true
    $before[[string]$quest.id] = if ($quest.storyline) { [string]$quest.storyline } else { "0" }
}

$names = @{}
$dropped = 0
foreach ($row in Import-Csv "$ToolsDir\QuestLine-$Build.csv") {
    if ($row.Name_lang -match $internalName) { $dropped++; continue }
    $names[$row.ID] = $row.Name_lang
}

$members = @{}
foreach ($row in Import-Csv "$ToolsDir\QuestLineXQuest-$Build.csv") {
    if (-not $names.ContainsKey($row.QuestLineID) -or -not $ourQuests.ContainsKey($row.QuestID)) { continue }
    if (-not $members.ContainsKey($row.QuestLineID)) { $members[$row.QuestLineID] = New-Object System.Collections.Generic.List[object] }
    $members[$row.QuestLineID].Add([PSCustomObject]@{ Quest = [int]$row.QuestID; Order = [int]$row.OrderIndex; Row = [int]$row.ID })
}

$primary = @{}
foreach ($lineId in $members.Keys) {
    $size = $members[$lineId].Count
    foreach ($member in $members[$lineId]) {
        $questId = "$($member.Quest)"
        $current = $primary[$questId]
        if (-not $current -or $size -lt $members[$current].Count -or ($size -eq $members[$current].Count -and [int]$lineId -lt [int]$current)) {
            $primary[$questId] = $lineId
        }
    }
}

$usedLines = @($primary.Values | Sort-Object -Unique { [int]$_ })
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("qcQuestLines = {`r`n")
foreach ($lineId in ($usedLines | Sort-Object { [int]$_ })) {
    $ordered = $members[$lineId] | Sort-Object Order, Row | ForEach-Object { $_.Quest }
    $quests = (@($ordered | Select-Object -Unique) -join ",")
    $name = $names[$lineId].Replace('\', '\\').Replace('"', '\"')
    [void]$sb.Append("`t[$lineId]={name=`"$name`",quests={$quests}},`r`n")
}
[void]$sb.Append("}")

$block = [regex]::Match($content, '(?sm)^qcQuestLines = \{.*?^\}')
if (-not $block.Success) { throw "qcQuestLines block not found" }
if (([regex]::Matches($content, '(?m)^qcQuestLines = \{')).Count -ne 1) { throw "qcQuestLines is defined more than once" }
$updated = $content.Substring(0, $block.Index) + $sb.ToString() + $content.Substring($block.Index + $block.Length)
if ($updated -cne $content) { [System.IO.File]::WriteAllText($questFile, $updated, $script:Utf8) }

$changed = 0
foreach ($quest in $questRecords) {
    $questId = [string]$quest.id
    $new = if ($primary.ContainsKey($questId)) { $primary[$questId] } else { "0" }
    if ($new -ne $before[$questId]) { Set-RecordField $quest 'storyline' ([int]$new); $changed++ }
}
if ($changed -gt 0) { Save-QuestData $questRecords $DataDir $AddonDir }

$hadBefore = @($before.Values | Where-Object { $_ -ne "0" }).Count
$gained = @($primary.Keys | Where-Object { $before[$_] -eq "0" }).Count
$lost = @($before.Keys | Where-Object { $before[$_] -ne "0" -and -not $primary.ContainsKey($_) }).Count
$repointed = @($primary.Keys | Where-Object { $before[$_] -ne "0" -and $before[$_] -ne $primary[$_] }).Count
"Questlines: $($names.Count) with player-facing names ($dropped internal skipped); $($usedLines.Count) written"
"Quests with a storyline: $hadBefore -> $($primary.Count)  (gained $gained, lost $lost, moved to another storyline $repointed)"
"Field 13 values changed: $changed"
