<#
Removes the qcLocalize keys that qcCategoryUiMapID has made redundant: the client supplies those
category names in every locale, so translating them here is duplicated work that can only drift.

Two phases. First the menu entries for those categories drop their "text=qcL.KEY," - the dropdown
takes their name from qcCategoryName at display time, so the field is already unused. Then the
freed keys are removed from every locale file.

Refuses to write if a key is still named anywhere in the addon's Lua, or if any locale file is
missing a key the others have.
#>
param(
    [string]$AddonDir = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist",
    [switch]$WhatIf
)

$questFile = "$AddonDir\qcQuest.lua"
$menuFile = "$AddonDir\qcMenu.lua"
$content = [System.IO.File]::ReadAllText($questFile, [System.Text.Encoding]::UTF8)

$categories = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcQuestCategories=\{(.*?)^\}').Groups[1].Value, '\{(\d+),"((?:[^"\\]|\\.)*)"\}')) {
    $categories[[int]$m.Groups[1].Value] = $m.Groups[2].Value
}
$mapped = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcCategoryUiMapID = \{(.*?)^\}').Groups[1].Value, '\[(\d+)\]=(\d+)')) {
    $mapped[[int]$m.Groups[1].Value] = $true
}
if (-not $mapped.Count) { throw "qcCategoryUiMapID is empty or missing - run Build-CategoryUiMapIDs.ps1 first" }
"Categories served by the client: $($mapped.Count)"

# Phase 1: the menu no longer needs a text for a category the client names.
$menu = [System.IO.File]::ReadAllText($menuFile, [System.Text.Encoding]::UTF8)
$strippedKeys = @{}
$menuUpdated = [regex]::Replace($menu, '\{text=qcL\.([A-Z0-9_]+),(isTitle=false,notCheckable=false,hasArrow=false,arg1=(\d+),)', {
    param($m)
    $cat = [int]$m.Groups[3].Value
    if ($mapped.ContainsKey($cat)) { $strippedKeys[$m.Groups[1].Value] = $true; return "{" + $m.Groups[2].Value }
    return $m.Value
})
"Menu entries that dropped their text: $($strippedKeys.Count)"

# Phase 2: which of those keys are now unused, and present in every locale file.
$files = Get-ChildItem "$AddonDir\Localization.*.lua"
$parsed = @{}
foreach ($file in $files) {
    $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $keys = @{}
    foreach ($m in [regex]::Matches($text, '(?m)^\s*([A-Z0-9_]+)\s*=\s*"')) { $keys[$m.Groups[1].Value] = $true }
    $parsed[$file.FullName] = @{ Text = $text; Keys = $keys }
}

$referenced = @{}
foreach ($lua in (Get-ChildItem "$AddonDir\*.lua" | Where-Object { $_.Name -notlike "Localization.*" })) {
    $text = if ($lua.FullName -eq $menuFile) { $menuUpdated } else { [System.IO.File]::ReadAllText($lua.FullName, [System.Text.Encoding]::UTF8) }
    foreach ($m in [regex]::Matches($text, '(?:qcL|qcLocalize)(?:\.([A-Z0-9_]+)|\[\s*"([A-Z0-9_]+)"\s*\])')) {
        $name = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        $referenced[$name] = $lua.Name
    }
}

$removable = @{}
$skipped = New-Object System.Collections.Generic.List[string]
$partial = New-Object System.Collections.Generic.List[string]
foreach ($key in $strippedKeys.Keys) {
    if ($referenced.ContainsKey($key)) { $skipped.Add("$key (still named in $($referenced[$key]))"); continue }
    $removable[$key] = $true
    # The locale files are not in sync; a key some of them never had is still removable.
    $missingFrom = @($files | Where-Object { -not $parsed[$_.FullName].Keys.ContainsKey($key) })
    if ($missingFrom.Count) { $partial.Add("$key (was missing from $($missingFrom.Count) of $($files.Count) files)") }
}
"Keys removable: $($removable.Count)   held back: $($skipped.Count)"
$skipped | Sort-Object | ForEach-Object { "  $_" }
if ($partial.Count) { "Keys that were already absent from some locale files:"; $partial | Sort-Object | ForEach-Object { "  $_" } }

$totalRemoved = 0
foreach ($file in $files) {
    $lines = $parsed[$file.FullName].Text -split "`r`n"
    $kept = New-Object System.Collections.Generic.List[string]
    $removed = 0
    foreach ($line in $lines) {
        $m = [regex]::Match($line, '(?m)^\s*([A-Z0-9_]+)\s*=\s*"')
        if ($m.Success -and $removable.ContainsKey($m.Groups[1].Value)) { $removed++; continue }
        $kept.Add($line)
    }
    $expected = @($removable.Keys | Where-Object { $parsed[$file.FullName].Keys.ContainsKey($_) }).Count
    if ($removed -ne $expected) { throw "$($file.Name): removed $removed lines but expected $expected" }
    $totalRemoved += $removed
    if (-not $WhatIf) { [System.IO.File]::WriteAllText($file.FullName, ($kept -join "`r`n"), (New-Object System.Text.UTF8Encoding $false)) }
}

if (-not $WhatIf) { [System.IO.File]::WriteAllText($menuFile, $menuUpdated, (New-Object System.Text.UTF8Encoding $false)) }
"$(if ($WhatIf) { 'Would remove' } else { 'Removed' }) $totalRemoved strings across $($files.Count) locale files."
