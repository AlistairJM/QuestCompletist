# Which races a quest's data allows against the race list the game's own record of it gives (the quest cache, step 2e).
# Dot-sourced by Compare-QuestRaces.ps1 (docs/maintenance.md, step 1e). The cache's list is the server's own field, the
# one Blizzard's API serves (docs/plans/retail-quest-cache.md, "Races"); a quest it lists no races for is open to every
# race in the game's eyes, and a restriction of ours there (a giver's own race, a zone's side) is ours to keep.
#
# Our race bits (qcRaceBits in the addon) aren't Blizzard's PlayableRaceBit: a race's bit is found by its ChrRaces
# ClientFileString. The races that come in one per side (Pandaren, Dracthyr, Earthen, Haranir; WoW: Forever's Skyborne)
# share a bit, and the data's faction (1 the Alliance, 2 the Horde, 4 the neutral Pandaren) says which side's.

$QuestRaceBits = @{
    HUMAN = 1; ORC = 2; DWARF = 4; NIGHTELF = 8; SCOURGE = 16; TAUREN = 32; GNOME = 64; TROLL = 128
    GOBLIN = 256; BLOODELF = 512; DRAENEI = 1024; WORGEN = 2048; PANDAREN = 4096; VOIDELF = 8192
    NIGHTBORNE = 16384; HIGHMOUNTAINTAUREN = 32768; LIGHTFORGEDDRAENEI = 65536; DARKIRONDWARF = 131072
    MAGHARORC = 262144; ZANDALARITROLL = 524288; KULTIRAN = 1048576; VULPERA = 2097152
    MECHAGNOME = 4194304; DRACTHYR = 8388608; EARTHENDWARF = 16777216; HARRONIR = 33554432; SKYBORNE = 67108864
}
# The races added after Legion (the allied races and those since) have bits from the Void Elf's up.
$QuestLaterRaceBit = 8192

# The playable races of either side (ChrRaces.Alliance 0 or 1; the neutral Pandaren left out): Id, Name, Bit (ours) and
# Side (1 the Alliance, 2 the Horde). A playable race with no bit of ours stops the run: qcRaceBits needs it first.
function Get-ComparedRaces($raceRows) {
    foreach ($r in $raceRows) {
        if (([long]$r.Flags -band 1) -ne 0 -or [int]$r.PlayableRaceBit -lt 0 -or [int]$r.Alliance -gt 1) { continue }
        $key = ($r.ClientFileString -replace '[^a-zA-Z]', '').ToUpper()
        if (-not $QuestRaceBits.ContainsKey($key)) { throw "ChrRaces $($r.ID) ($($r.ClientFileString)) is playable and has no race bit of ours." }
        [pscustomobject]@{ Id = [int]$r.ID; Name = $r.ClientFileString; Bit = [long]$QuestRaceBits[$key]; Side = 1 + [int]$r.Alliance }
    }
}

# The compared races the data allows: its mask has the race's bit (0 for any race) and its faction the race's side (0 for
# either).
function Get-DataRaces($races, [long]$mask, [int]$faction) {
    @($races | Where-Object { ($mask -eq 0 -or ($mask -band $_.Bit)) -and ($faction -eq 0 -or ($faction -band $_.Side)) })
}

# One quest's data against the game's list ($listed, ChrRaces IDs; empty or $null when the game lists none, which is no
# difference). $null when they agree. Otherwise Class, Hide (the races the game allows and the data doesn't), Show (the
# reverse), and the data the game's list gives: Mask (its races' bits) and Faction (their sides, with the data's
# neutral Pandaren bit kept). The classes:
#   contradiction  the data's faction is one side and its mask names mostly the other side's races
#   stale          the data hides only races added after Legion, which its mask predates
#   narrowing      the data hides other races of a side the game allows (the starting race's quests, a class's races)
#   shown          the data allows races the game denies
#   crosses        both at once
function Compare-QuestRaceList($races, [long]$mask, [int]$faction, $listed) {
    $ids = @($listed | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ })
    if (-not $ids.Count) { return $null }
    $ours = Get-DataRaces $races $mask $faction
    $theirs = @($races | Where-Object { $ids -contains $_.Id })
    $hide = @($theirs | Where-Object { $ours.Id -notcontains $_.Id })
    $show = @($ours | Where-Object { $theirs.Id -notcontains $_.Id })
    if (-not $hide.Count -and -not $show.Count) { return $null }
    $side = $faction -band 3
    $maskSides = @($races | Where-Object { $mask -band $_.Bit } | ForEach-Object { $_.Side })
    $own = @($maskSides | Where-Object { $_ -eq $side }).Count
    $class = if ($mask -and ($side -eq 1 -or $side -eq 2) -and @($maskSides | Where-Object { $_ -ne $side }).Count -gt $own) { 'contradiction' }
        elseif ($hide.Count -and $show.Count) { 'crosses' }
        elseif ($show.Count) { 'shown' }
        elseif (-not @($hide | Where-Object { $_.Bit -lt $QuestLaterRaceBit }).Count) { 'stale' }
        else { 'narrowing' }
    $newMask = [long]0; $newSides = 0
    foreach ($r in $theirs) { $newMask = $newMask -bor $r.Bit; $newSides = $newSides -bor $r.Side }
    return [pscustomobject]@{ Class = $class; Hide = $hide; Show = $show; Mask = $newMask; Faction = ($newSides -bor ($faction -band 4)) }
}

# The rows of docs\plans\quest-race-decisions.csv for one game: quest ID -> the row (Decision FIX or KEEP).
function Read-QuestRaceDecisions([string]$path, [string]$game) {
    $rows = @{}
    if (-not (Test-Path $path)) { return $rows }
    foreach ($row in (Import-Csv $path -Encoding UTF8)) {
        if ($row.Game -ne $game) { continue }
        if ($row.Decision -ne 'FIX' -and $row.Decision -ne 'KEEP') { throw "quest-race-decisions.csv: quest $($row.QuestID) has decision '$($row.Decision)'; only FIX and KEEP are known." }
        $rows[[int]$row.QuestID] = $row
    }
    return $rows
}
