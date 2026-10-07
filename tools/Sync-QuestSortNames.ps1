<#
Writes, into every Localization file, the client's own name in that language for each category
that's filed under one of the game's quest log headings: "Timerunning", "Garrison Support", the
War Campaigns, Forever's "Lunar Festival" and the rest. The game can't be asked for a heading's
name at runtime, so these categories can't be named through qcCategoryUiMapID or
qcCategoryClientName as the others are; they fall back to their key in the Localization files
(qcCategoryName in qcCore.lua), and this tool fills those keys from the client's QuestSort table,
downloaded for each client language.

The headings are chosen by hand, in $retail and $forever below, as the other kinds are in
Build-CategoryClientNames.ps1: only a heading whose English is exactly the category's name. A
heading whose English differs ("Time Rifts" for our "Time Rift", "Weekly Event" for "Weekly
Events") is a judgement call, not a conversion, and isn't listed. A category both games have takes
retail's text. The English heading's key must be the key listed, or the tool stops: Blizzard
renamed the heading, or we the category.

A key already in a file is rewritten with the client's text, and loses its "Needs review" or
"Requires localization" note; a key the file lacks is added in alphabetical order. Nothing else in
the files changes. A rerun with no client changes leaves every file byte-identical.

Reads tools\QuestSort.<locale>.csv (retail) and tools\QuestSort-<Forever build>.<locale>.csv,
downloaded when missing or with -Refresh.

  .\Sync-QuestSortNames.ps1 -Build 12.1.0.69933 -ForeverBuild 1.60.1.70245 -WhatIf
  .\Sync-QuestSortNames.ps1 -Build 12.1.0.69933 -ForeverBuild 1.60.1.70245
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$Build = "12.1.0.69933",
    [string]$ForeverBuild = "1.60.1.70245",
    [switch]$Refresh,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Our key (the category's English name, letters and digits, upper-cased) -> the heading's QuestSort ID.
$retail = [ordered]@{
    ALLIANCEWARCAMPAIGN = 447; ASSAULTONTHEDARKPORTAL = 402; BLACKEMPIRECAMPAIGN = 584; COVENANTASSAULTS = 604
    DAYOFTHEDEAD = 41; DEATHRISING = 588; ELEMENTALBONDS = 381; FIRELANDSINVASION = 379; GARRISONCAMPAIGN = 401
    GARRISONSUPPORT = 403; GILNEASRECLAMATION = 630; HERITAGE = 560; HORDEWARCAMPAIGN = 448; LANDFALL = 396
    NORTHRENDCUP = 634; PANDARENBREWMASTERS = 391; PANDARENCAMPAIGN = 397; RATEDPVP = 557; SEASONAL = 22
    THEHARBINGER = 637; THEZANDALARI = 380; TIMERUNNING = 639; TOURNAMENT = 241; UPGRADESYSTEM = 642
    WARBANDS = 643; WORLDPVP = 555
}
$forever = [ordered]@{ AHNQIRAJWAR = 365; CAMPING = 666; INVASION = 368; LUNARFESTIVAL = 366; MIDSUMMER = 369; SEASONAL = 22 }

$locales = @('enUS', 'ptBR', 'frFR', 'deDE', 'itIT', 'koKR', 'esMX', 'ruRU', 'zhCN', 'esES', 'zhTW')

function Get-Headings([string]$locale, [string]$build, [string]$file) {
    $path = Join-Path $ToolsDir $file
    if ($Refresh -or -not (Test-Path $path)) {
        Write-Host "Downloading QuestSort ($locale, $build)..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/QuestSort/csv?build=$build&locale=$locale" -OutFile $path
        Start-Sleep -Seconds 1
    }
    $names = @{}
    foreach ($row in Import-Csv $path -Encoding UTF8) { $names[[int]$row.ID] = $row.SortName_lang }
    return $names
}

# The text for each key in one language: retail's heading, else Forever's.
function Get-Texts([string]$locale) {
    $retailNames = Get-Headings $locale $Build "QuestSort.$locale.csv"
    $foreverNames = Get-Headings $locale $ForeverBuild "QuestSort-$ForeverBuild.$locale.csv"
    $texts = [ordered]@{}
    foreach ($key in $retail.Keys) { $texts[$key] = $retailNames[$retail[$key]] }
    foreach ($key in $forever.Keys) { if (-not $texts.Contains($key)) { $texts[$key] = $foreverNames[$forever[$key]] } }
    foreach ($key in @($texts.Keys)) { if (-not $texts[$key]) { throw "No $locale heading for $key (QuestSort ID $(if ($retail.Contains($key)) { $retail[$key] } else { $forever[$key] }))" } }
    return $texts
}

function ConvertTo-LuaString([string]$text) { return '"' + $text.Replace('\', '\\').Replace('"', '\"') + '"' }

$english = Get-Texts 'enUS'
foreach ($key in $english.Keys) {
    $derived = ([regex]::Replace($english[$key], '[^A-Za-z0-9]', '')).ToUpperInvariant()
    if ($derived -cne $key) { throw "The English heading for $key is '$($english[$key])', whose key would be $derived. Blizzard renamed the heading, or we the category." }
}
$categories = @{}
foreach ($game in @('', 'Forever')) {
    $content = [IO.File]::ReadAllText((Join-Path (Join-Path $AddonDir $game) 'qcQuest.lua'), [Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcQuestCategories\s*=\s*\{(.*?)^\}').Groups[1].Value, '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) {
        $categories[([regex]::Replace($m.Groups[2].Value, '[^A-Za-z0-9]', '')).ToUpperInvariant()] = $m.Groups[2].Value
    }
}
foreach ($key in $english.Keys) {
    if (-not $categories.ContainsKey($key)) { throw "No category in either game's qcQuest.lua has the key $key" }
    if ($categories[$key] -cne $english[$key]) { throw "Category '$($categories[$key])' isn't named exactly as the client's heading '$($english[$key])'" }
}

$total = 0
foreach ($locale in $locales) {
    $texts = Get-Texts $locale
    $path = Join-Path $AddonDir "Localization.$locale.lua"
    $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $newline = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.AddRange([string[]]($raw -split "\r?\n"))
    $changed = New-Object System.Collections.Generic.List[string]
    $added = New-Object System.Collections.Generic.List[string]
    foreach ($key in $texts.Keys) {
        $line = "`t$key = $(ConvertTo-LuaString $texts[$key]),"
        $at = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -cmatch "^\s*$key\s*=\s*`"") { $at = $i; break } }
        if ($at -ge 0) {
            if ($lines[$at] -cne $line) { $lines[$at] = $line; $changed.Add($key) }
            continue
        }
        $insertAt = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $m = [regex]::Match($lines[$i], '^\s*([A-Z][A-Z0-9_]*)\s*=\s*"')
            if ($m.Success -and [string]::CompareOrdinal($m.Groups[1].Value, $key) -gt 0) { $insertAt = $i; break }
        }
        if ($insertAt -lt 0) {
            for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match '^\s*\}') { $insertAt = $i; break } }
        }
        if ($insertAt -lt 0) { throw "No place to add $key in Localization.$locale.lua" }
        $lines.Insert($insertAt, $line)
        $added.Add($key)
    }
    $total += $changed.Count + $added.Count
    "Localization.$locale.lua: $($changed.Count) changed, $($added.Count) added, $($texts.Count - $changed.Count - $added.Count) unchanged" +
        $(if ($changed.Count) { "; changed " + ($changed -join ', ') } else { '' }) + $(if ($added.Count) { "; added " + ($added -join ', ') } else { '' })
    if ($WhatIf -or $changed.Count + $added.Count -eq 0) { continue }
    [IO.File]::WriteAllText($path, ($lines -join $newline), (New-Object Text.UTF8Encoding $false))
}
if ($WhatIf) { "WhatIf: nothing changed ($total keys would)." } else { "$total keys written. Run Test-Localization.lua." }
