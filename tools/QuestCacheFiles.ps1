<#
Shared by the tools that read a quest cache Read-QuestCache.ps1 wrote (tools\<game>_quest_cache_<build>.jsonl,
step 2e for retail, step 10 for WoW: Forever), dot-sourced:
	. "$PSScriptRoot\QuestCacheFiles.ps1"

Get-QuestCacheFiles lists a game's caches, the oldest build first, by version and not by text; a file whose
name holds no build is none of them. Get-QuestCacheWarning says when the cache a tool reads looks partial.
The cache holds only what the probe asked for, so a probe run cut short leaves one far smaller than the
last, and what it lacks reads as quests no source speaks for: the 12.1.5 cache of 14 October 2026 held
26,616 quests against the 33,123 of 12.1.0's. The tools print the warning and go on;
Compare-QuestReputation.ps1 and Compare-QuestLevels.ps1 also refuse -UpdateBaseline while it stands,
unless -AcceptPartialCache is given.
#>

function Get-QuestCacheFiles([string]$toolsDir, [string]$game = 'retail') {
    Get-ChildItem (Join-Path $toolsDir "${game}_quest_cache_*.jsonl") -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match "^${game}_quest_cache_\d+\.\d+\.\d+\.\d+$" } |
        Sort-Object { [version]($_.BaseName -replace "^${game}_quest_cache_") }
}

function Get-QuestCacheIds([string]$path) {
    $ids = New-Object 'System.Collections.Generic.HashSet[int]'
    $rx = New-Object Text.RegularExpressions.Regex '^\s*\{"id":(\d+)'
    foreach ($line in [IO.File]::ReadLines($path)) {
        $m = $rx.Match($line)
        if ($m.Success) { [void]$ids.Add([int]$m.Groups[1].Value) }
    }
    return , $ids
}

# The warning's lines, or none: $cacheFile holds under $minShare of the quests of the newest cache of an
# earlier build beside it, or of our quests ($ourIds; without them that half isn't checked).
function Get-QuestCacheWarning([string]$cacheFile, $ourIds = $null, [double]$minShare = 0.9) {
    $cacheFile = (Resolve-Path -LiteralPath $cacheFile).ProviderPath
    $held = Get-QuestCacheIds $cacheFile
    $name = [IO.Path]::GetFileNameWithoutExtension($cacheFile)
    $game = if ($name -match '^([a-z]+)_quest_cache_') { $Matches[1] } else { 'retail' }
    $short = @()
    if ($name -match "^${game}_quest_cache_(\d+\.\d+\.\d+\.\d+)$") {
        $build = [version]$Matches[1]
        $before = @(Get-QuestCacheFiles (Split-Path $cacheFile -Parent) $game |
            Where-Object { [version]($_.BaseName -replace "^${game}_quest_cache_") -lt $build } | Select-Object -Last 1)
        if ($before.Count) {
            $earlier = (Get-QuestCacheIds $before[0].FullName).Count
            if ($earlier -gt 0 -and ($held.Count / $earlier) -lt $minShare) {
                $short += "{0:N0} against the {1:N0} of {2}, the build before ({3:N1}%)" -f $held.Count, $earlier, $before[0].Name, (100.0 * $held.Count / $earlier)
            }
        }
    }
    if ($null -ne $ourIds) {
        $ours = 0; $inCache = 0
        foreach ($id in $ourIds) { $ours++; if ($held.Contains([int]$id)) { $inCache++ } }
        if ($ours -gt 0 -and ($inCache / $ours) -lt $minShare) {
            $short += "{0:N0} of our {1:N0} ({2:N1}%)" -f $inCache, $ours, (100.0 * $inCache / $ours)
        }
    }
    if ($short.Count -eq 0) { return @() }
    $step = if ($game -eq 'forever') { 'step 10' } else { 'step 2e' }
    return @(
        ("WARNING: {0} looks partial, with under {1:N0}% of the quests it should hold: {2}." -f (Split-Path $cacheFile -Leaf), (100 * $minShare), ($short -join ', and ')),
        "WARNING: a probe run cut short leaves a cache like this, and what it lacks reads as quests no source speaks for. Finish the run and read the cache again (docs\maintenance.md, $step).")
}
