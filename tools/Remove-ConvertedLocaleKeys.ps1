<#
Removes the qcLocalize text the client has made redundant, in both games. Where the client names a
category or a menu heading, it does so in every language, so our own text for it is duplicated
work that can only drift. Test-Localization.lua reports the same cases.

- Category entries in retail's qcMenu.lua lose their label: the menu names a category through
  qcCategoryName, so an entry's text only gives its indent. An indented entry keeps text="   ".
  Forever's menu is Build-ForeverMenu.ps1's, which writes no labels.
- A key nothing uses any more goes from every locale file: no code names it, no menu heading shows
  it, and the client names every category with its name (qcCategoryUiMapID or
  qcCategoryClientName) in its game.
- A key only headings the client names (clientName) show keeps its English, their fallback, and
  loses its translations.

Run it after Build-CategoryUiMapIDs.ps1, Build-CategoryClientNames.ps1 and Build-ForeverMenu.ps1,
with -WhatIf first.
#>
param(
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
function Read-Text([string]$path) { return [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) }

# The inside of a top-level table such as "qcQuestCategories={...}", found by counting braces
# outside strings and comments.
function Get-TableBody([string]$content, [string]$name) {
    $start = [regex]::Match($content, "(?m)^$name\s*=\s*\{")
    if (-not $start.Success) { throw "$name not found" }
    $from = $start.Index + $start.Length
    $depth = 1; $inString = $false; $i = $from
    for (; $i -lt $content.Length; $i++) {
        $c = $content[$i]
        if ($inString) { if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $inString = $false } }
        elseif ($c -eq '"') { $inString = $true }
        elseif ($c -eq '-' -and $content[$i + 1] -eq '-') { $i = $content.IndexOf("`n", $i); if ($i -lt 0) { break } }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { break } }
    }
    if ($depth) { throw "$name has no closing brace" }
    return $content.Substring($from, $i - $from)
}

# A menu entry's start up to its arg1: its text, whether the client names it, and its arg1.
$entryPattern = '\{text=(?<text>.*?),(?<client>clientName=\{[^{}]*\},)?isTitle=(?:true|false),notCheckable=(?:true|false),hasArrow=(?:true|false)(?:,arg1=(?<arg1>-?\d+|"[^"]*"))?'

$games = @(
    @{ Name = 'retail'; Quest = "$AddonDir\qcQuest.lua"; Menu = "$AddonDir\qcMenu.lua"; Generated = $false },
    @{ Name = 'Forever'; Quest = "$AddonDir\Forever\qcQuest.lua"; Menu = "$AddonDir\Forever\qcMenu.lua"; Generated = $true }
)
$categoryKeys = @{}   # every category's fallback key (qcCategoryName in qcCore.lua)
$neededKeys = @{}     # the keys of categories the client doesn't name
$plainUses = @{}      # keys menu text shows
$clientUses = @{}     # keys only as the fallback of headings the client names
$labelKeys = @{}      # keys in the labels of category entries
$labels = 0
foreach ($game in $games) {
    $content = Read-Text $game.Quest
    $named = @{}
    foreach ($table in 'qcCategoryUiMapID', 'qcCategoryClientName') {
        foreach ($m in [regex]::Matches((Get-TableBody $content $table), '\[(-?\d+)\]\s*=')) { $named[[int]$m.Groups[1].Value] = $true }
    }
    $categories = @{}
    foreach ($m in [regex]::Matches((Get-TableBody $content 'qcQuestCategories'), '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) {
        $id = [int]$m.Groups[1].Value
        $key = ($m.Groups[2].Value -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
        $categories[$id] = $true
        $categoryKeys[$key] = $true
        if (-not $named.ContainsKey($id)) { $neededKeys[$key] = $true }
    }

    $menu = Read-Text $game.Menu
    $found = 0
    $game.MenuText = [regex]::Replace($menu, $entryPattern, {
        param($m)
        $keys = @([regex]::Matches($m.Groups['text'].Value, 'qcL\.([A-Z0-9_]+)') | ForEach-Object { $_.Groups[1].Value })
        $script:found += $keys.Count
        if (-not $keys.Count) { return $m.Value }
        if ($m.Groups['arg1'].Value -match '^-?\d+$' -and $categories.ContainsKey([int]$m.Groups['arg1'].Value)) {
            $indent = [regex]::Match($m.Groups['text'].Value, '^(?:qcL\.[A-Z0-9_]+$|stringformat\("(\s*)%s)')
            if (-not $indent.Success) { throw "$($game.Name)'s menu: category $($m.Groups['arg1'].Value)'s entry has a label of an unexpected form: $($m.Groups['text'].Value)" }
            if ($game.Generated) { throw "$($game.Menu) has a label on category $($m.Groups['arg1'].Value)'s entry. Rerun Build-ForeverMenu.ps1." }
            $script:labels++
            foreach ($key in $keys) { $labelKeys[$key] = $true }
            $text = if ($indent.Groups[1].Value) { "text=`"$($indent.Groups[1].Value)`"," } else { '' }
            return '{' + $text + $m.Value.Substring(('{text=' + $m.Groups['text'].Value + ',').Length)
        }
        foreach ($key in $keys) { if ($m.Groups['client'].Success) { $clientUses[$key] = $true } else { $plainUses[$key] = $true } }
        return $m.Value
    })
    $inMenu = [regex]::Matches($menu, 'qcL\.[A-Z0-9_]+').Count
    if ($found -ne $inMenu) { throw "$($game.Menu): $inMenu qcL keys, but $found in entries this script reads. Has the menu's format changed?" }
}

# Keys the code names, apart from the menus: qcL.KEY, and a settings row's text, which the options
# panel looks up.
$codeUses = @{}
foreach ($lua in (Get-ChildItem $AddonDir -Recurse -Filter *.lua | Where-Object { $_.Name -notlike 'Localization.*' -and $_.Name -ne 'qcMenu.lua' })) {
    $text = Read-Text $lua.FullName
    foreach ($m in [regex]::Matches($text, '(?:qcL|qcLocalize)(?:\.([A-Z0-9_]+)|\[\s*"([A-Z0-9_]+)"\s*\])|text\s*=\s*"([A-Z][A-Z0-9_]*)"')) {
        foreach ($g in 1..3) { if ($m.Groups[$g].Success) { $codeUses[$m.Groups[$g].Value] = $lua.Name } }
    }
}

$english = @{}
foreach ($m in [regex]::Matches((Read-Text "$AddonDir\Localization.enUS.lua"), '(?m)^\s*([A-Z0-9_]+)\s*=\s*"')) { $english[$m.Groups[1].Value] = $true }
$removable = @{}; $untranslate = @{}
foreach ($key in $english.Keys) {
    if (-not ($categoryKeys.ContainsKey($key) -or $labelKeys.ContainsKey($key) -or $plainUses.ContainsKey($key) -or $clientUses.ContainsKey($key))) { continue }   # the addon's own text
    if ($neededKeys.ContainsKey($key) -or $codeUses.ContainsKey($key) -or $plainUses.ContainsKey($key)) { continue }
    if ($clientUses.ContainsKey($key)) { $untranslate[$key] = $true } else { $removable[$key] = $true }
}
"Category entries that lose their label: $labels"
"Keys nothing uses, to go from every locale file: $($removable.Count)"
"  $(($removable.Keys | Sort-Object) -join ' ')"
"Keys only headings the client names show, to keep in English only: $($untranslate.Count)"
"  $(($untranslate.Keys | Sort-Object) -join ' ')"

$total = 0
foreach ($file in (Get-ChildItem "$AddonDir\Localization.*.lua")) {
    $isEnglish = $file.Name -eq 'Localization.enUS.lua'
    $kept = New-Object System.Collections.Generic.List[string]
    $removed = 0
    foreach ($line in ((Read-Text $file.FullName) -split "`r`n")) {
        $m = [regex]::Match($line, '^\s*([A-Z0-9_]+)\s*=\s*"')
        if ($m.Success -and ($removable.ContainsKey($m.Groups[1].Value) -or (-not $isEnglish -and $untranslate.ContainsKey($m.Groups[1].Value)))) { $removed++; continue }
        $kept.Add($line)
    }
    $total += $removed
    if (-not $WhatIf) { [IO.File]::WriteAllText($file.FullName, ($kept -join "`r`n"), $utf8) }
}
foreach ($game in $games) {
    if (-not $WhatIf -and -not $game.Generated) { [IO.File]::WriteAllText($game.Menu, $game.MenuText, $utf8) }
}
"$(if ($WhatIf) { 'Would remove' } else { 'Removed' }) $total lines across the locale files."
