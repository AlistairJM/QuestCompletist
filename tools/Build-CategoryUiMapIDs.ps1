<#
Generates qcCategoryUiMapID in qcQuest.lua: the UiMap id whose name the client should be asked for
when naming each quest category, so those names don't have to be translated in 11 locale files.

Only categories where a mapped UiMap's name matches our own name exactly are included, so no
displayed name changes in English. Categories where the client's name differs on purpose
("Maw of Souls" is "Helmouth Cliffs" to Blizzard) or where ours has a typo are left out; those are
judgement calls, not conversions.

Where several mapped ids carry the matching name, the lowest is stored.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$QuestFile = (Join-Path $PSScriptRoot '..\QuestCompletist\qcQuest.lua'),
    [string]$Build = "12.1.0.69933",
    [switch]$Refresh
)

$uiMapCsv = "$ToolsDir\UiMap.csv"
if ($Refresh -or -not (Test-Path $uiMapCsv)) {
    $ProgressPreference = "SilentlyContinue"
    Write-Output "Downloading UiMap..."
    Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/UiMap/csv?build=$Build" -OutFile $uiMapCsv
}
$uiName = @{}
Import-Csv $uiMapCsv | ForEach-Object { $uiName[$_.ID] = $_.Name_lang }

$content = [System.IO.File]::ReadAllText($QuestFile, [System.Text.Encoding]::UTF8)

$categories = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcQuestCategories=\{(.*?)^\}').Groups[1].Value, '\{(\d+),"((?:[^"\\]|\\.)*)"\}')) {
    $categories[[int]$m.Groups[1].Value] = $m.Groups[2].Value
}

$byCategory = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcAreaIDToCategoryID=\{(.*?)^\}').Groups[1].Value, '\[(\d+)\]=(\d+)')) {
    $cat = [int]$m.Groups[2].Value
    if (-not $byCategory.ContainsKey($cat)) { $byCategory[$cat] = New-Object System.Collections.Generic.List[string] }
    $byCategory[$cat].Add($m.Groups[1].Value)
}
# Entries added directly (such as the Shadowlands to War Within dungeon and raid categories) have no
# zone mapping, so the current table is a candidate source too; the name check below still applies.
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcCategoryUiMapID = \{(.*?)^\}').Groups[1].Value, '\[(\d+)\]=(\d+)')) {
    $cat = [int]$m.Groups[1].Value
    if (-not $byCategory.ContainsKey($cat)) { $byCategory[$cat] = New-Object System.Collections.Generic.List[string] }
    if (-not $byCategory[$cat].Contains($m.Groups[2].Value)) { $byCategory[$cat].Add($m.Groups[2].Value) }
}

$chosen = @{}
$skipped = New-Object System.Collections.Generic.List[string]
foreach ($cat in ($categories.Keys | Sort-Object)) {
    $ids = $byCategory[$cat]
    if (-not $ids) { continue }
    $matching = @($ids | Where-Object { $uiName[$_] -ceq $categories[$cat] } | Sort-Object { [int]$_ })
    if ($matching.Count) { $chosen[$cat] = $matching[0] }
    else {
        $live = @($ids | Where-Object { $uiName.ContainsKey($_) } | ForEach-Object { $uiName[$_] } | Select-Object -Unique)
        if ($live.Count) { $skipped.Add("$($categories[$cat]) <- $($live -join ' | ')") }
    }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("")
$lines.Add("qcCategoryUiMapID = {  -- CategoryId -> UiMapId, for C_Map.GetMapInfo to name the category")
$lines.Add("")
foreach ($cat in ($chosen.Keys | Sort-Object)) {
    $lines.Add("`t[$cat]=$($chosen[$cat]),`t-- $($categories[$cat])")
}
$lines.Add("}")
$lines.Add("")

$anchor = [regex]::Match($content, '(?sm)^qcQuestCategories=\{.*?^\}\r?\n')
if (-not $anchor.Success) { throw "qcQuestCategories block not found" }

$existing = [regex]::Match($content, '(?sm)^\r?\nqcCategoryUiMapID = \{.*?^\}\r?\n\r?\n')
if ($existing.Success) { $content = $content.Remove($existing.Index, $existing.Length) ; $anchor = [regex]::Match($content, '(?sm)^qcQuestCategories=\{.*?^\}\r?\n') }

$insertAt = $anchor.Index + $anchor.Length
$content = $content.Substring(0, $insertAt) + (($lines -join "`r`n") + "`r`n") + $content.Substring($insertAt)
[System.IO.File]::WriteAllText($QuestFile, $content, (New-Object System.Text.UTF8Encoding $false))

"Categories with a client-supplied name: $($chosen.Count) of $($categories.Count)"
"Categories left to our own strings (name differs): $($skipped.Count)"
$skipped | Sort-Object | ForEach-Object { "  $_" }
