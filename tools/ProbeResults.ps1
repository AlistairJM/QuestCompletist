# What a probe run saved about quests, for the tools that retype quests and look for ones that may be gone.
# Dot-source this and call Get-ProbeQuests with the saved-variables file. It reads either probe's:
#   the probe in tools\ForeverProbe (QCForeverProbe.lua, QCForeverProbeDB), which runs on both games, and
#   the retail type probe of pull request #42 (a copy of QuestCompletist.lua holding qcQuestTypeProbeResults),
#   whose one run, on 29 September 2026, is the baseline until the probe has run on retail.
# Either way a quest reads the same: Load is '1' when the server sent its data (the client's record, a
# cached one, or an answer that came late), '0' when it refused, 't' when it never answered; and
# Classification is the client's answer once the data was loaded (5 Recurring, 7 Normal ...), or $null.

function Find-ProbeResults([string]$ToolsDir) {
    $retail = Get-ChildItem "$ToolsDir\retail_probe_*\QCForeverProbe.lua" -ErrorAction SilentlyContinue |
        Sort-Object { [int]($_.Directory.Name -replace '^retail_probe_(\d+).*$', '$1') } | Select-Object -Last 1
    if ($retail) { return $retail.FullName }
    return (Join-Path $ToolsDir 'quest_type_probe_results.lua')
}

function Get-ProbeQuests([string]$Path, [string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe') {
    if (-not (Test-Path $Path)) { throw "Probe results not found at $Path" }
    $text = [System.IO.File]::ReadAllText($Path)
    $quests = @{}
    if ($text.Contains('QCForeverProbeDB')) {
        $lines = @(& $LuaExe "$PSScriptRoot\Read-ForeverProbe.lua" $Path)
        if ($LASTEXITCODE -ne 0) { throw "Read-ForeverProbe.lua failed on $Path" }
        $rows = @($lines | Where-Object { $_.StartsWith("quest`t") } | ForEach-Object { , $_.Split("`t") })
        $build = ($rows | Group-Object { $_[2] } | Sort-Object Count -Descending | Select-Object -First 1).Name
        if (-not $build) { throw "No quests in $Path" }
        foreach ($f in $rows) {
            if ($f[2] -ne $build) { continue }
            $load = switch ($f[3]) { 'ok' { '1' } 'cached' { '1' } 'late' { '1' } 'fail' { '0' } 'timeout' { 't' } default { $null } }
            if ($null -eq $load) { continue }
            $class = $null
            if ($f.Count -gt 4 -and $f[4] -match '^\d+$') { $class = [int]$f[4] }
            $quests[$f[1]] = [pscustomobject]@{ Load = $load; Classification = $class }
        }
        return [pscustomobject]@{ Format = 'probe'; Build = $build; Quests = $quests }
    }
    if (-not $text.Contains('qcQuestTypeProbeResults')) { throw "$Path holds neither QCForeverProbeDB nor qcQuestTypeProbeResults." }
    foreach ($m in [regex]::Matches($text, '(?m)^\[(\d+)\] = "\d+\|[^|]*\|(\d+),[01-],([01t])",?\s*$')) {
        $quests[$m.Groups[1].Value] = [pscustomobject]@{ Load = $m.Groups[3].Value; Classification = [int]$m.Groups[2].Value }
    }
    $build = [regex]::Match($text, '\["client"\] = "([^"]+)"').Groups[1].Value
    if (-not $build) { throw "No client build in $Path" }
    return [pscustomobject]@{ Format = 'typecheck'; Build = $build; Quests = $quests }
}
