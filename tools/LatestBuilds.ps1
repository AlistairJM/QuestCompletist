# Dot-sourced by Get-LatestBuilds.ps1 and ForeverProbe\Build-ProbeLists.ps1: reads the installed clients'
# builds from .build.info, works out the newest build wago.tools publishes, and finds the builds the
# tools folder holds.

$GameProducts = [ordered]@{ retail = 'wow'; forever = 'wow_classic_beta' }
$GameFolders = @{ retail = '_retail_'; forever = '_classic_beta_' }
$DefaultWowDir = 'C:\Program Files (x86)\World of Warcraft'

function Test-BuildNumber([string]$text) {
    return $text -match '^\d+\.\d+\.\d+\.\d+$'
}

function Get-BuildTrack([string]$build) {
    return (($build -split '\.')[0..2]) -join '.'
}

function Read-BuildInfo([string]$path) {
    $found = @{}
    if (-not (Test-Path -LiteralPath $path)) { return $found }
    $lines = @([System.IO.File]::ReadAllLines($path) | Where-Object { $_.Trim() })
    if ($lines.Count -lt 2) { return $found }
    $names = @($lines[0].Split('|') | ForEach-Object { ($_ -split '!')[0] })
    $iProduct = [array]::IndexOf($names, 'Product')
    $iVersion = [array]::IndexOf($names, 'Version')
    if ($iProduct -lt 0 -or $iVersion -lt 0) { return $found }
    foreach ($line in ($lines | Select-Object -Skip 1)) {
        $fields = $line.Split('|')
        if ($fields.Count -gt [Math]::Max($iProduct, $iVersion)) { $found[$fields[$iProduct]] = $fields[$iVersion] }
    }
    return $found
}

function Get-InstalledBuild([string]$game, [string]$wowDir) {
    $builds = Read-BuildInfo (Join-Path $wowDir '.build.info')
    $product = $GameProducts[$game]
    if ($product -and $builds.ContainsKey($product)) { return $builds[$product] }
    return $null
}

function Get-NewestPublished($wago) {
    $byProduct = @{}
    $byTrack = @{}
    foreach ($property in $wago.PSObject.Properties) {
        foreach ($entry in @($property.Value)) {
            $version = [string]$entry.version
            if (-not (Test-BuildNumber $version)) { continue }
            $item = [pscustomobject]@{ Product = $property.Name; Version = $version; Created = [string]$entry.created_at }
            $current = $byProduct[$property.Name]
            if (-not $current -or [string]::CompareOrdinal($item.Created, $current.Created) -gt 0) { $byProduct[$property.Name] = $item }
            $track = Get-BuildTrack $version
            $current = $byTrack[$track]
            if (-not $current -or [version]$version -gt [version]$current.Version) { $byTrack[$track] = $item }
        }
    }
    return @{ Product = $byProduct; Track = $byTrack }
}

function Get-HeldTables([string]$toolsDir) {
    $newest = @{}
    foreach ($file in Get-ChildItem -LiteralPath $toolsDir -File -ErrorAction SilentlyContinue) {
        if ($file.Name -notmatch '^(?<family>[A-Za-z][A-Za-z0-9_]*)-(?<build>\d+\.\d+\.\d+\.\d+)(?:\.[A-Za-z]{4})?\.(?:csv|txt)$') { continue }
        $build = $Matches['build']
        $key = $Matches['family'] + '|' + (Get-BuildTrack $build)
        if (-not $newest.ContainsKey($key) -or [version]$build -gt [version]$newest[$key].Build) {
            $newest[$key] = [pscustomobject]@{ Family = $Matches['family']; Track = (Get-BuildTrack $build); Build = $build }
        }
    }
    return @($newest.Values)
}

function Get-ScriptPins([string]$toolsDir) {
    $pins = New-Object System.Collections.Generic.List[object]
    $files = @(Get-ChildItem -LiteralPath $toolsDir -Filter '*.ps1' -File) +
        @(Get-ChildItem -LiteralPath (Join-Path $toolsDir 'ForeverProbe') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        if ($file.Name -like 'Test-*') { continue }
        $text = [System.IO.File]::ReadAllText($file.FullName)
        foreach ($m in [regex]::Matches($text, '(?m)^\s*\[string\]\$(?<param>\w*Build)\s*=\s*["''](?<build>\d+\.\d+\.\d+\.\d+)["'']')) {
            $pins.Add([pscustomobject]@{ Script = $file.Name; Parameter = $m.Groups['param'].Value; Build = $m.Groups['build'].Value })
        }
    }
    return $pins.ToArray()
}

function Read-ListBuild([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    foreach ($line in [System.IO.File]::ReadLines($path)) {
        if ($line -match '^probe\.questBuild\s*=\s*"(\d+\.\d+\.\d+\.\d+)"') { return $Matches[1] }
    }
    return $null
}
