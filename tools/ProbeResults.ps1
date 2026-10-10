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

# What the probe's last quest run (the one that asked IsQuestTrivial) saved about each loaded quest's level for
# its character: IsQuestTrivial (Trivial), GetContentDifficultyQuestForPlayer (Difficulty: 0 Trivial, 1 Easy,
# 2 Fair, 3 Difficult, 4 Impossible) and GetQuestDifficultyLevel (Level), with the character's level and its two
# trivial ranges. A function or a range is $false when the client has no such call, $null when it gave nothing. The
# counts are keyed by strings: 'true', 'false' and 'none' for Trivial; '0' to '4', 'none' and 'other' for Difficulty;
# 'true/0' for both.
function Get-ProbeLevelFacts([string]$Path, [string]$LuaExe = 'C:\Program Files (x86)\Lua\5.1\lua.exe') {
    if (-not (Test-Path $Path)) { throw "Probe results not found at $Path" }
    $lines = @(& $LuaExe "$PSScriptRoot\Read-ForeverProbe.lua" $Path facts)
    if ($LASTEXITCODE -ne 0) { throw "Read-ForeverProbe.lua failed on $Path" }
    $rows = @{}
    $runs = @{}
    foreach ($line in $lines) {
        $f = $line.Split("`t")
        switch ($f[0]) {
            'quest' { $rows[$f[1]] = @{ Build = $f[2]; Result = $f[3] } }
            'fact' { if ($f[2] -ceq 'level' -or $f[2] -ceq 'trivial' -or $f[2] -ceq 'contentDifficulty') { $rows[$f[1]][$f[2]] = $f[3] } }
            'run' { $runs[[int]$f[1]] = @{ Kind = $f[2]; Build = $f[3]; Character = $f[5]; Level = $f[6]; Facts = @{}; Ranges = @{} } }
            'runfact' { $runs[[int]$f[1]].Facts[$f[2]] = $f[3] }
            'trivialrange' { $runs[[int]$f[1]].Ranges[$f[2]] = $f[3] }
        }
    }
    $run = $null
    foreach ($n in @($runs.Keys | Sort-Object)) {
        if ($runs[$n].Kind -ceq 'quests' -and $runs[$n].Facts.ContainsKey('trivial')) { $run = $runs[$n] }
    }
    if (-not $run) { throw "No quest run in $Path asked IsQuestTrivial" }
    $answer = { param($value, [bool]$number) if ($null -eq $value) { $null } elseif ($value -ceq 'false') { $false } elseif ($number) { [int]$value } else { $value } }
    $trivial = [ordered]@{ 'true' = 0; 'false' = 0; 'none' = 0 }
    $difficulty = [ordered]@{ '0' = 0; '1' = 0; '2' = 0; '3' = 0; '4' = 0; 'none' = 0; 'other' = 0 }
    $together = @{}
    $quests = @{}
    foreach ($id in $rows.Keys) {
        $row = $rows[$id]
        if ($row.Build -cne $run.Build -or @('ok', 'cached', 'late') -cnotcontains $row.Result) { continue }
        $t = if ($row.ContainsKey('trivial') -and @('true', 'false') -ccontains $row.trivial) { $row.trivial } else { 'none' }
        $d = if (-not $row.ContainsKey('contentDifficulty')) { 'none' } elseif ($row.contentDifficulty -cmatch '^[0-4]$') { $row.contentDifficulty } else { 'other' }
        $trivial[$t]++
        $difficulty[$d]++
        $together["$t/$d"] = 1 + [int]$together["$t/$d"]
        $level = if ($row.ContainsKey('level') -and $row.level -match '^-?\d+$') { [int]$row.level } else { $null }
        $quests[$id] = [pscustomobject]@{
            Level = $level
            Trivial = if ($t -eq 'none') { $null } else { $t -ceq 'true' }
            Difficulty = if ($d -match '^[0-4]$') { [int]$d } else { $null }
        }
    }
    return [pscustomobject]@{
        Build = $run.Build
        Character = $run.Character
        CharacterLevel = if ($run.Level -match '^\d+$') { [int]$run.Level } else { $null }
        TrivialFunction = & $answer $run.Facts['trivial'] $false
        DifficultyFunction = & $answer $run.Facts['contentDifficulty'] $false
        TrivialRange = & $answer $run.Ranges['UnitQuestTrivialLevelRange'] $true
        TrivialRangeScaling = & $answer $run.Ranges['UnitQuestTrivialLevelRangeScaling'] $true
        Loaded = $quests.Count
        Trivial = $trivial
        Difficulty = $difficulty
        Together = $together
        Quests = $quests
    }
}
