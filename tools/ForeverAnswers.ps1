# Dot-sourced by Import-ForeverData.ps1: data\forever\answers.jsonl, what the game has ever said about each
# quest and how many runs in a row it has not said it. A run is one client build's quest cache.
#
#   {"runs":["1.60.1.70205","1.60.1.70291"]}
#   {"id":329,"seen":"1.60.1.70338","missed":0,"record":{...a line of forever_quest_cache_<build>.jsonl...}}

function New-AnswerMemory {
    return [pscustomobject]@{ Runs = (New-Object System.Collections.Generic.List[string]); Quests = @{} }
}

function Read-AnswerMemory([string]$path) {
    $memory = New-AnswerMemory
    if (-not (Test-Path -LiteralPath $path)) { return $memory }
    foreach ($line in [System.IO.File]::ReadLines($path)) {
        if (-not $line.Trim()) { continue }
        if ($line -match '^\{"runs":\[(.*)\]\}$') {
            foreach ($run in ($Matches[1] -split ',')) { if ($run.Trim()) { $memory.Runs.Add($run.Trim().Trim('"')) } }
        }
        elseif ($line -match '^\{"id":(\d+),"seen":"([^"]*)","missed":(\d+),"record":(\{.*\})\}$') {
            $memory.Quests[[int]$Matches[1]] = [pscustomobject]@{ Seen = $Matches[2]; Missed = [int]$Matches[3]; Raw = $Matches[4] }
        }
        else { throw "$path has a line this reader doesn't know: $($line.Substring(0, [Math]::Min(80, $line.Length)))" }
    }
    return $memory
}

function ConvertTo-AnswerLines($memory) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('{"runs":[' + (($memory.Runs | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']}')
    foreach ($id in ($memory.Quests.Keys | Sort-Object)) {
        $q = $memory.Quests[$id]
        $lines.Add('{"id":' + $id + ',"seen":"' + $q.Seen + '","missed":' + $q.Missed + ',"record":' + $q.Raw + '}')
    }
    return (($lines | ForEach-Object { "$_`n" }) -join '')
}

function Read-CacheLines([string]$path) {
    $raw = @{}
    foreach ($line in [System.IO.File]::ReadLines($path)) {
        if ($line -match '^\{"id":(\d+),') { $raw[[int]$Matches[1]] = $line.Trim() }
    }
    return $raw
}

function Update-AnswerMemory($memory, $rawById, $asked, [string]$run) {
    $newRun = -not $memory.Runs.Contains($run)
    if ($newRun) { $memory.Runs.Add($run) }
    foreach ($id in $rawById.Keys) {
        $memory.Quests[$id] = [pscustomobject]@{ Seen = $run; Missed = 0; Raw = $rawById[$id] }
    }
    if ($newRun) {
        foreach ($id in @($memory.Quests.Keys)) {
            if ($rawById.ContainsKey($id)) { continue }
            if ($null -ne $asked -and -not $asked.ContainsKey($id)) { continue }
            $memory.Quests[$id].Missed++
        }
    }
}

function Get-QuestsMissedSince($memory, [int]$runs) {
    return @($memory.Quests.Keys | Where-Object { $memory.Quests[$_].Missed -ge $runs } | Sort-Object)
}
