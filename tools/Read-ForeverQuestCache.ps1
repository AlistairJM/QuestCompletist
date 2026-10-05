<#
Reads WoW: Forever's quest cache (Cache\WDB\enUS\questcache.wdb) into one JSON line per quest
(docs/plans/forever.md, phase 2). The client keeps the server's record of every quest it has asked
about there; the Forever probe asks about them all.

Each record is the server's quest record, laid out as TrinityCore's QueryQuestInfoResponse: 122 fixed
numbers, the objectives and other lists, then the texts. Every record must be read to its last
byte, or nothing is written: a record that doesn't fit means the layout has changed.

A line holds the quest's id, title, level, minLevel and sort (its zone, or a negative QuestSort for
class, profession and holiday quests), and when they apply: questInfo (1 group, 41 PvP, 62 raid,
81 dungeon), groupSize, recurs (daily or weekly), nextQuest (the follow-up offered on hand-in),
startItem, flags, reputation (the factions it rewards), and races with their faction. races lists
the races playable in Forever that may take the quest; it's left out when every race may, as for
most quests of one faction, whose giver decides. The quest texts other than the title are left out.

Race bits come from the client's ChrRaces table for -Build (wago.tools), whose build must be the
cache's.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$CacheFile = "",
    [string]$Build = "1.60.1.70205",
    [string]$OutFile = ""
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"

if (-not $CacheFile) {
    $CacheFile = Get-ChildItem "$ToolsDir\forever_probe_*\questcache.wdb" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
    if (-not $CacheFile) { throw "No questcache.wdb under $ToolsDir\forever_probe_*: give -CacheFile." }
}
$bytes = [System.IO.File]::ReadAllBytes($CacheFile)
$ascii = [System.Text.Encoding]::ASCII
$magic = -join [char[]]($bytes[3], $bytes[2], $bytes[1], $bytes[0])
if ($magic -ne 'WQST') { throw "$CacheFile isn't a quest cache (it starts '$magic')." }
$cacheBuild = [BitConverter]::ToUInt32($bytes, 4)
$locale = -join [char[]]($bytes[11], $bytes[10], $bytes[9], $bytes[8])
if ($Build.Split('.')[-1] -ne "$cacheBuild") { throw "The cache is from build $cacheBuild, not $Build. Give -Build." }

$racesCsv = "$ToolsDir\ChrRaces-$Build.csv"
if (-not (Test-Path $racesCsv)) {
    Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/ChrRaces/csv?build=$Build" -OutFile $racesCsv
}
$playable = @(Import-Csv $racesCsv | Where-Object { ([long]$_.Flags -band 0x400000) -and [int]$_.PlayableRaceBit -ge 0 } |
    ForEach-Object { [pscustomobject]@{ Id = [int]$_.ID; Bit = [int]$_.PlayableRaceBit; Horde = [int]$_.Alliance -eq 1 } } |
    Sort-Object Id)
if ($playable.Count -lt 8) { throw "ChrRaces for $Build has only $($playable.Count) races playable in Forever." }

function Get-JsonString([string]$text) {
    $escaped = $text.Replace('\', '\\').Replace('"', '\"')
    return '"' + [regex]::Replace($escaped, '[\x00-\x1f]', { param($m) '\u{0:x4}' -f [int][char]$m.Value }) + '"'
}

$utf8 = [System.Text.Encoding]::UTF8
$textBits = 9, 12, 12, 9, 10, 8, 10, 8, 11
$fields = New-Object 'int[]' 122
$lines = New-Object System.Collections.Generic.List[string]
$failed = New-Object System.Collections.Generic.List[string]
$counts = @{ alliance = 0; horde = 0; someRaces = 0; noRace = 0; daily = 0; weekly = 0; startItem = 0; nextQuest = 0 }
$offset = 24
while ($offset + 8 -le $bytes.Length) {
    $id = [BitConverter]::ToUInt32($bytes, $offset)
    $length = [BitConverter]::ToInt32($bytes, $offset + 4)
    if ($length -le 0) { break }
    $start = $offset + 8
    $end = $start + $length
    $offset = $end
    try {
        for ($i = 0; $i -lt 122; $i++) { $fields[$i] = [BitConverter]::ToInt32($bytes, $start + 4 * $i) }
        if ($fields[0] -ne $id) { throw "it holds quest $($fields[0])" }
        $pos = $start + 488 + 12 * $fields[16]
        for ($o = 0; $o -lt $fields[109]; $o++) {
            $pos += 33
            $effects = [BitConverter]::ToInt32($bytes, $pos)
            $pos += 8 + 4 * $effects
            $pos += 2 + $bytes[$pos]
        }
        $pos += 4 * ($fields[112] + $fields[113])
        for ($c = 0; $c -lt $fields[118] + $fields[119]; $c++) {
            $pos += 8
            $pos += 2 + (([int]$bytes[$pos] -shl 4) -bor ($bytes[$pos + 1] -shr 4))
        }
        $pos += 4 * ($fields[120] + $fields[121])
        $bit = 0
        $textLengths = foreach ($size in $textBits) {
            $value = 0
            for ($k = 0; $k -lt $size; $k++) {
                $value = ($value -shl 1) -bor (($bytes[$pos + ($bit -shr 3)] -shr (7 - ($bit -band 7))) -band 1)
                $bit++
            }
            $value
        }
        $pos += 12
        $title = $utf8.GetString($bytes, $pos, $textLengths[0])
        foreach ($textLength in $textLengths) { $pos += $textLength }
        if ($pos -gt $end) { throw "it runs $($pos - $end) bytes past its end" }
        if ($pos -lt $end) { throw "$($end - $pos) bytes are left over" }
    } catch {
        $failed.Add("$id ($_)")
        continue
    }

    $line = '{"id":' + $id + ',"title":' + (Get-JsonString $title) + ',"level":' + $fields[2] +
        ',"minLevel":' + $fields[4] + ',"sort":' + $fields[6]
    if ($fields[7]) { $line += ',"questInfo":' + $fields[7] }
    if ($fields[8]) { $line += ',"groupSize":' + $fields[8] }
    $flags = [long]$fields[25] -band 0xFFFFFFFFL
    if ($flags -band 0x1000) { $line += ',"recurs":"daily"'; $counts.daily++ }
    elseif ($flags -band 0x8000) { $line += ',"recurs":"weekly"'; $counts.weekly++ }
    if ($fields[9]) { $line += ',"nextQuest":' + $fields[9]; $counts.nextQuest++ }
    if ($fields[24]) { $line += ',"startItem":' + $fields[24]; $counts.startItem++ }
    if ($flags) { $line += ',"flags":' + $flags }
    $factions = @(75, 79, 83, 87, 91 | Where-Object { $fields[$_] } | ForEach-Object { $fields[$_] })
    if ($factions.Count) { $line += ',"reputation":[' + ($factions -join ',') + ']' }
    $low = [BitConverter]::ToUInt32($bytes, $start + 440)
    $high = [BitConverter]::ToUInt32($bytes, $start + 444)
    if ($low -ne [uint32]::MaxValue -or $high -ne [uint32]::MaxValue) {
        $allowed = @($playable | Where-Object {
            if ($_.Bit -lt 32) { ($low -shr $_.Bit) -band 1 } else { ($high -shr ($_.Bit - 32)) -band 1 } })
        $line += ',"races":[' + (($allowed | ForEach-Object { $_.Id }) -join ',') + ']'
        if ($allowed.Count -eq 0) { $counts.noRace++ }
        elseif (-not ($allowed | Where-Object { $_.Horde })) { $line += ',"faction":"Alliance"'; $counts.alliance++ }
        elseif (-not ($allowed | Where-Object { -not $_.Horde })) { $line += ',"faction":"Horde"'; $counts.horde++ }
        else { $counts.someRaces++ }
    }
    $lines.Add($line + '}')
}

if ($failed.Count) {
    throw ("{0} of {1} records don't fit the layout, so nothing was written. The first: {2}" -f
        $failed.Count, ($failed.Count + $lines.Count), (($failed | Select-Object -First 5) -join '; '))
}
if (-not $OutFile) { $OutFile = "$ToolsDir\forever_quest_cache_$Build.jsonl" }
$sorted = $lines | Sort-Object { [int]($_ -replace '^\{"id":(\d+),.*$', '$1') }
[System.IO.File]::WriteAllText($OutFile, (($sorted -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
Write-Host ("{0} quests from build {1} ({2}) written to {3}." -f $lines.Count, $cacheBuild, $locale, $OutFile)
Write-Host ("Races: {0} Alliance only, {1} Horde only, {2} other sets, {3} no race playable in Forever. Recurring: {4} daily, {5} weekly. {6} start from an item, {7} offer a follow-up." -f
    $counts.alliance, $counts.horde, $counts.someRaces, $counts.noRace, $counts.daily, $counts.weekly, $counts.startItem, $counts.nextQuest)
