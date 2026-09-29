<#
Generates the quest storyline data from Blizzard's own questline tables (QuestLine and
QuestLineXQuest on wago.tools, pinned to one build):

  - qcQuestLines: [questLineID] = {name = "...", quests = {...}} - the storyline's name and its
    quests in Blizzard's order (OrderIndex), limited to quests in qcQuestDatabase.
  - field 13 of every qcQuestDatabase entry: the quest's storyline, or 0.

Questlines with internal names ("8.0 Professions - ... - SCS", "[DNT] ...", "Test Questline") are
never shown. A quest in several questlines is given the most specific one - the fewest quests,
then the lowest ID - so a campaign chapter wins over the whole campaign.

All-or-nothing: if the quest database or the qcQuestLines block isn't found as expected, nothing
is written.
#>
param(
    [string]$ToolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools",
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [string]$Build = "12.1.0.69933",
    [switch]$Refresh
)

$ProgressPreference = "SilentlyContinue"
foreach ($table in "QuestLine", "QuestLineXQuest") {
    $path = "$ToolsDir\$table-$Build.csv"
    if ($Refresh -or -not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path
        Start-Sleep -Milliseconds 300
    }
}

$internalName = '^\s*$|^\d+\.\d|\[DNT\]|\(DNT\)|\[PH\]|\[DEPRECATED\]|\(STM\)|\(POC\)|- SCS$|(?i)\btest\b|^Zone \d+ Neck \d+$|^Catch Up: .*Wrapper'

$questFile = "$AddonDir\qcQuest.lua"
$content = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)

# Fields 1-12 of an entry, then field 13 (storyline).
$entryPattern = '(?m)^(\[(\d+)\]=\{\d+,"(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",-?\d+,\d+,\d+,\d+,\d+,\d+,\d+,\d+,)(\d+),'
$ourQuests = @{}
$before = @{}
foreach ($m in [regex]::Matches($content, $entryPattern)) {
    $ourQuests[$m.Groups[2].Value] = $true
    $before[$m.Groups[2].Value] = $m.Groups[3].Value
}
$entryCount = ([regex]::Matches($content, '(?m)^\[\d+\]=\{')).Count
if ($ourQuests.Count -ne $entryCount) { throw "Parsed $($ourQuests.Count) entries but the file has $entryCount" }

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
$content = $content.Substring(0, $block.Index) + $sb.ToString() + $content.Substring($block.Index + $block.Length)

$changed = 0
$content = [regex]::Replace($content, $entryPattern, {
    param($m)
    $new = if ($primary.ContainsKey($m.Groups[2].Value)) { $primary[$m.Groups[2].Value] } else { "0" }
    if ($new -ne $m.Groups[3].Value) { $script:changed++ }
    return $m.Groups[1].Value + $new + ","
})

[System.IO.File]::WriteAllText($questFile, $content, (New-Object System.Text.UTF8Encoding $false))

$hadBefore = @($before.Values | Where-Object { $_ -ne "0" }).Count
$gained = @($primary.Keys | Where-Object { $before[$_] -eq "0" }).Count
$lost = @($before.Keys | Where-Object { $before[$_] -ne "0" -and -not $primary.ContainsKey($_) }).Count
$repointed = @($primary.Keys | Where-Object { $before[$_] -ne "0" -and $before[$_] -ne $primary[$_] }).Count
"Questlines: $($names.Count) with player-facing names ($dropped internal skipped); $($usedLines.Count) written"
"Quests with a storyline: $hadBefore -> $($primary.Count)  (gained $gained, lost $lost, moved to another storyline $repointed)"
"Field 13 values changed: $changed"
