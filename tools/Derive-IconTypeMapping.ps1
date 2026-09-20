<#
Cross-tabulates existing (trustworthy) pin IconType values against our own
qcQuestDatabase's quest-type bitmask (field 6), to derive an empirical mapping
we can apply to quests that never had a pin before.
#>

$toolsDir = "C:\Users\alist\RiderProjects\QuestCompletist\tools"
$questFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"

Write-Output "Loading qcQuestDatabase type bitmask (field 6) per quest..."
$content = Get-Content $questFile -Raw
$startIdx = $content.IndexOf("qcQuestDatabase={")
$dbBlock = $content.Substring($startIdx)
# [ID]={ID,"Name",Level,"Zone",AreaID,Type,...
$typeMatches = [regex]::Matches($dbBlock, '\[(\d+)\]=\{\d+,"[^"]*",\d+,"[^"]*",\d+,(\d+),')
$questType = @{}
foreach ($m in $typeMatches) {
    $questType[$m.Groups[1].Value] = [int]$m.Groups[2].Value
}
Write-Output "Parsed type for $($questType.Count) quests."

$joined = Import-Csv "$toolsDir\quest_locations_joined.csv"
$trustworthy = $joined | Where-Object { $_.DriftStatus -eq "OK" }
Write-Output "Trustworthy (position-verified) pins to learn from: $($trustworthy.Count)"

$crosstab = @{}
foreach ($row in $trustworthy) {
    if (-not $questType.ContainsKey($row.QuestID)) { continue }
    $typeBits = $questType[$row.QuestID]
    $icon = $row.IconType
    $key = "$typeBits|$icon"
    if (-not $crosstab.ContainsKey($key)) { $crosstab[$key] = 0 }
    $crosstab[$key]++
}

Write-Output "=== TypeBits | IconType | Count ==="
$crosstab.GetEnumerator() | Sort-Object { [int]($_.Key -split '\|')[0] } | ForEach-Object {
    $parts = $_.Key -split '\|'
    Write-Output "TypeBits=$($parts[0])  IconType=$($parts[1])  Count=$($_.Value)"
}
