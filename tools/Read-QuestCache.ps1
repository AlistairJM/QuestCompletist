<#
Reads a game's quest cache (Cache\WDB\enUS\questcache.wdb) into one JSON line per quest
(docs/plans/forever.md, phase 2; retail since docs/plans/game-parity.md, recommendation 6). The client
keeps the server's record of every quest it has asked about there; the probe asks about them all.

-Build says the game: 1.x is WoW: Forever, 12.x and up retail. Each record is the server's quest
record, laid out as TrinityCore's QueryQuestInfoResponse: a block of fixed numbers (122 in Forever, 120
in retail, whose records lack QuestLevel and QuestMinLevel), the objectives and other lists, then the
texts. Every record must be read to its last byte, and the file must end with its terminator, or
nothing is written: a record that doesn't fit means the layout has changed, a missing terminator a
copy cut short.

A line holds the quest's id, title, level and minLevel (Forever) or contentTuning (retail, whose level
range is a function of that ContentTuningID), and sort (its zone, or a negative QuestSort for class,
profession and holiday quests), questType (0, which every repeatable quest has but so do many
that are not: retail's repeatable ones are 0 and not in QuestV2; 1 disabled, 2 normal, 3 task), and
when they apply: questInfo (1 group, 41 PvP, 62 raid, 81 dungeon), groupSize, recurs (weekly when the
flags say so, else daily when they or flagsEx do: the API's is_weekly and is_daily), nextQuest (the
follow-up offered on hand-in), startItem (the item the quest hands out when it is accepted, not the
item that begins it), giver (the quest giver's creature ID, empty in every record so far), flags,
flagsEx, scheduler (the quest is reset by the game's scheduler, as many unflagged dailies and
weeklies are), reputation (each faction it rewards, with the amount), and races with their faction.
races lists the playable races that may take the quest; it's left out when every race may (a mask
of all ones, or of none, as TrinityCore's AllowableRaces 0), as for most quests of one faction, whose
giver decides. Retail's two placeholder races, "TBD NPC Race", one in each side's masks, are left
out of the list. The quest texts other than the title are left out.

A record gives each reputation reward as a step in the client's QuestFactionReward table (a gain or,
when negative, a loss), or as its own amount in hundredths, which wins when it's set. The amounts
are worked out as the game does.

Race bits and reputation steps come from the client's ChrRaces and QuestFactionReward tables for
-Build (wago.tools), whose build must be the cache's. The cache comes from tools\forever_probe_*
or tools\retail_probe_*, or -CacheFile.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$CacheFile = "",
    [string]$Build = "",
    [string]$OutFile = ""
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\LatestBuilds.ps1"
$Build = Resolve-ProbeBuild $Build 'forever' $ToolsDir 'Build'

$major = [int]$Build.Split('.')[0]
$game = if ($major -eq 1) { 'forever' } elseif ($major -ge 10) { 'retail' } else { throw "-Build $Build is neither WoW: Forever (1.x) nor retail (12.x)." }
$layouts = @{
    forever = @{ Fixed = 122; Spells = 16; Objectives = 109; Treasure = 112, 113; Conditional = 118, 119; House = 120, 121
        Level = 2; MinLevel = 4; Sort = 6; Info = 7; Group = 8; Next = 9; StartItem = 24; Flags = 25; FlagsEx = 26; Giver = 117; Reputation = 75; Races = 110 }
    retail  = @{ Fixed = 120; Spells = 14; Objectives = 107; Treasure = 110, 111; Conditional = 116, 117; House = 118, 119
        Tuning = 3; Sort = 4; Info = 5; Group = 6; Next = 7; StartItem = 22; Flags = 23; FlagsEx = 24; Giver = 115; Reputation = 73; Races = 108 }
}
$layout = $layouts[$game]

if (-not $CacheFile) {
    $CacheFile = Get-ChildItem "$ToolsDir\${game}_probe_*\questcache.wdb" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
    if (-not $CacheFile) { throw "No questcache.wdb under $ToolsDir\${game}_probe_*: give -CacheFile." }
}
$bytes = [System.IO.File]::ReadAllBytes($CacheFile)
$magic = -join [char[]]($bytes[3], $bytes[2], $bytes[1], $bytes[0])
if ($magic -ne 'WQST') { throw "$CacheFile isn't a quest cache (it starts '$magic')." }
$cacheBuild = [BitConverter]::ToUInt32($bytes, 4)
$locale = -join [char[]]($bytes[11], $bytes[10], $bytes[9], $bytes[8])
if ($Build.Split('.')[-1] -ne "$cacheBuild") { throw "The cache is from build $cacheBuild, not $Build. Give -Build." }

$racesCsv = "$ToolsDir\ChrRaces-$Build.csv"
if (-not (Test-Path $racesCsv)) {
    Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/ChrRaces/csv?build=$Build" -OutFile $racesCsv
}
$playable = @(Import-Csv $racesCsv | Where-Object { ($(if ($game -eq 'retail') { $_.ClientFileString -notlike 'tbd*' } else { [long]$_.Flags -band 0x400000 })) -and [int]$_.PlayableRaceBit -ge 0 } |
    ForEach-Object { [pscustomobject]@{ Id = [int]$_.ID; Bit = [int]$_.PlayableRaceBit; Side = [int]$_.Alliance } } |
    Sort-Object Id)
if ($playable.Count -lt 8) { throw "ChrRaces for $Build has only $($playable.Count) playable races." }
$rewardCsv = "$ToolsDir\QuestFactionReward-$Build.csv"
if (-not (Test-Path $rewardCsv)) {
    Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/QuestFactionReward/csv?build=$Build" -OutFile $rewardCsv
}
$rewardSteps = @{}
foreach ($row in Import-Csv $rewardCsv) { $rewardSteps[[int]$row.ID] = @(0..9 | ForEach-Object { [int]$row."Difficulty_$_" }) }
if (-not ($rewardSteps.ContainsKey(1) -and $rewardSteps.ContainsKey(2))) { throw "QuestFactionReward for $Build lacks its gain and loss rows, 1 and 2." }

function Get-JsonString([string]$text) {
    $escaped = $text.Replace('\', '\\').Replace('"', '\"')
    return '"' + [regex]::Replace($escaped, '[\x00-\x1f]', { param($m) '\u{0:x4}' -f [int][char]$m.Value }) + '"'
}

$utf8 = [System.Text.Encoding]::UTF8
$textBits = 9, 12, 12, 9, 10, 8, 10, 8, 11
$fixed = $layout.Fixed
$fields = New-Object 'int[]' $fixed
$treasure = $layout.Treasure; $conditional = $layout.Conditional; $house = $layout.House
$reputationSlots = 0..4 | ForEach-Object { $layout.Reputation + 4 * $_ }
$lines = New-Object System.Collections.Generic.List[string]
$failed = New-Object System.Collections.Generic.List[string]
$counts = @{ alliance = 0; horde = 0; someRaces = 0; noRace = 0; daily = 0; weekly = 0; startItem = 0; nextQuest = 0; giver = 0; reputation = 0 }
$offset = 24
$terminated = $false
while ($offset + 8 -le $bytes.Length) {
    $id = [BitConverter]::ToUInt32($bytes, $offset)
    $length = [BitConverter]::ToInt32($bytes, $offset + 4)
    if ($length -le 0) { $terminated = ($id -eq 0 -and $length -eq 0 -and $offset + 8 -eq $bytes.Length); break }
    $start = $offset + 8
    $end = $start + $length
    $offset = $end
    try {
        for ($i = 0; $i -lt $fixed; $i++) { $fields[$i] = [BitConverter]::ToInt32($bytes, $start + 4 * $i) }
        if ($fields[0] -ne $id) { throw "it holds quest $($fields[0])" }
        $pos = $start + 4 * $fixed + 12 * $fields[$layout.Spells]
        for ($o = 0; $o -lt $fields[$layout.Objectives]; $o++) {
            $pos += 33
            $effects = [BitConverter]::ToInt32($bytes, $pos)
            $pos += 8 + 4 * $effects
            $pos += 2 + $bytes[$pos]
        }
        $pos += 4 * ($fields[$treasure[0]] + $fields[$treasure[1]])
        for ($c = 0; $c -lt $fields[$conditional[0]] + $fields[$conditional[1]]; $c++) {
            $pos += 8
            $pos += 2 + (([int]$bytes[$pos] -shl 4) -bor ($bytes[$pos + 1] -shr 4))
        }
        $pos += 4 * ($fields[$house[0]] + $fields[$house[1]])
        $bit = 0
        $textLengths = foreach ($size in $textBits) {
            $value = 0
            for ($k = 0; $k -lt $size; $k++) {
                $value = ($value -shl 1) -bor (($bytes[$pos + ($bit -shr 3)] -shr (7 - ($bit -band 7))) -band 1)
                $bit++
            }
            $value
        }
        $scheduler = ($bytes[$pos + ($bit -shr 3)] -shr (7 - ($bit -band 7))) -band 1
        $pos += 12
        $title = $utf8.GetString($bytes, $pos, $textLengths[0])
        foreach ($textLength in $textLengths) { $pos += $textLength }
        if ($pos -gt $end) { throw "it runs $($pos - $end) bytes past its end" }
        if ($pos -lt $end) { throw "$($end - $pos) bytes are left over" }
    } catch {
        $failed.Add("$id ($_)")
        continue
    }

    $line = '{"id":' + $id + ',"title":' + (Get-JsonString $title)
    if ($game -eq 'retail') { $line += ',"contentTuning":' + $fields[$layout.Tuning] }
    else { $line += ',"level":' + $fields[$layout.Level] + ',"minLevel":' + $fields[$layout.MinLevel] }
    $line += ',"sort":' + $fields[$layout.Sort]
    if ($fields[$layout.Info]) { $line += ',"questInfo":' + $fields[$layout.Info] }
    if ($fields[$layout.Group]) { $line += ',"groupSize":' + $fields[$layout.Group] }
    $flags = [long]$fields[$layout.Flags] -band 0xFFFFFFFFL
    $flagsEx = [long]$fields[$layout.FlagsEx] -band 0xFFFFFFFFL
    if ($flags -band 0x8000) { $line += ',"recurs":"weekly"'; $counts.weekly++ }
    elseif (($flags -band 0x1000) -or ($flagsEx -band 0x8000)) { $line += ',"recurs":"daily"'; $counts.daily++ }
    if ($fields[$layout.Next]) { $line += ',"nextQuest":' + $fields[$layout.Next]; $counts.nextQuest++ }
    if ($fields[$layout.StartItem]) { $line += ',"startItem":' + $fields[$layout.StartItem]; $counts.startItem++ }
    if ($fields[$layout.Giver]) { $line += ',"giver":' + $fields[$layout.Giver]; $counts.giver++ }
    if ($flags) { $line += ',"flags":' + $flags }
    if ($flagsEx) { $line += ',"flagsEx":' + $flagsEx }
    $line += ',"questType":' + $fields[1]
    if ($scheduler) { $line += ',"scheduler":true' }
    $rewards = foreach ($slot in $reputationSlots) {
        $faction = $fields[$slot]; $step = $fields[$slot + 1]; $own = $fields[$slot + 2]
        if (-not $faction) { continue }
        if ([Math]::Abs($step) -gt 9) { throw "Quest $id rewards reputation step $step, outside QuestFactionReward's 0 to 9." }
        $amount = if ($own) { [Math]::Truncate($own / 100) } elseif ($step -gt 0) { $rewardSteps[1][$step] } else { $rewardSteps[2][-$step] }
        if ($amount) { "[$faction,$amount]" }
    }
    if ($rewards) { $line += ',"reputation":[' + (@($rewards) -join ',') + ']'; $counts.reputation++ }
    $low = [BitConverter]::ToUInt32($bytes, $start + 4 * $layout.Races)
    $high = [BitConverter]::ToUInt32($bytes, $start + 4 * $layout.Races + 4)
    if (($low -ne [uint32]::MaxValue -or $high -ne [uint32]::MaxValue) -and ($low -ne 0 -or $high -ne 0)) {
        $allowed = @($playable | Where-Object {
            if ($_.Bit -lt 32) { ($low -shr $_.Bit) -band 1 } else { ($high -shr ($_.Bit - 32)) -band 1 } })
        $line += ',"races":[' + (($allowed | ForEach-Object { $_.Id }) -join ',') + ']'
        $sides = @($allowed | ForEach-Object { $_.Side })
        if ($allowed.Count -eq 0) { $counts.noRace++ }
        elseif ($sides -contains 0 -and $sides -notcontains 1) { $line += ',"faction":"Alliance"'; $counts.alliance++ }
        elseif ($sides -contains 1 -and $sides -notcontains 0) { $line += ',"faction":"Horde"'; $counts.horde++ }
        else { $counts.someRaces++ }
    }
    $lines.Add($line + '}')
}

if ($failed.Count) {
    throw ("{0} of {1} records don't fit the layout, so nothing was written. The first: {2}" -f
        $failed.Count, ($failed.Count + $lines.Count), (($failed | Select-Object -First 5) -join '; '))
}
if (-not $terminated) { throw "$CacheFile doesn't end with its terminator after $($lines.Count) quests: it is cut short or holds an empty record." }
if (-not $lines.Count) { throw "$CacheFile holds no quests." }
if (-not $OutFile) { $OutFile = "$ToolsDir\${game}_quest_cache_$Build.jsonl" }
$sorted = $lines | Sort-Object { [int]($_ -replace '^\{"id":(\d+),.*$', '$1') }
[System.IO.File]::WriteAllText($OutFile, (($sorted -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
Write-Host ("{0} quests from build {1} ({2}) written to {3}." -f $lines.Count, $cacheBuild, $locale, $OutFile)
Write-Host ("Races: {0} Alliance only, {1} Horde only, {2} other sets, {3} no playable race. Recurring: {4} daily, {5} weekly. {6} start from an item, {7} offer a follow-up, {8} name their quest giver, {9} reward reputation." -f
    $counts.alliance, $counts.horde, $counts.someRaces, $counts.noRace, $counts.daily, $counts.weekly, $counts.startItem, $counts.nextQuest, $counts.giver, $counts.reputation)
