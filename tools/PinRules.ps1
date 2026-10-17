<#
Dot-sourced by the pin tools of both games: the rules for how quests share a pin and who a pin names. Assemble-PinDB.ps1
(retail, step 6) and Import-ForeverData.ps1 (WoW: Forever, step 10) build their pins with them, and
Apply-ClientQuestGivers.ps1 (6c) and the recorder's fills (RecordedGivers.ps1, 6d) follow them when a giver turns up for
a quest that shares a nameless pin. What stays apart is where a quest goes: retail places it at the client's start
point, Forever at its giver; and retail carries over what its pins already hold (Assemble-PinDB.ps1).

  - One spot is $PinSameSpot map points (1.5), measured straight: two pins of one giver may stand that far apart, no
    closer (the pin spacing floor of 7 October 2026), and the recorder's places use the same radius.
  - Who a pin names comes from the first source in $PinIdentityOrder that has someone (Select-PinIdentity).
  - Rows of one giver on one map share the pin whose first row stands nearest them within one spot; rows that name
    nobody (no NPC ID and no name) share a pin per spot the same way (Find-PinGroup, Add-PinGroup). The tool says who
    the giver is (Get-PinGiverKey: an NPC ID, else a name; Forever keys its givers by their entry).
  - The icon of a pin from its quests (Get-PinQuestIcon): every Forever pin takes it, and on retail a nameless pin
    whose rows bring different icons does, where the other pins keep the icon they carry over.
  - When a giver is found for some quests of a nameless pin, those quests move to the giver's pin: its pin on that map
    within one spot, else a new one at the nameless pin's place (Split-NamelessPin, Find-GiverPin, New-GiverPin). The
    pin takes the giver only when that giver has every quest on it, so a spot is never named after one quest's giver.
  - The task quests of a kind in $NoPinTaskKinds get no pin, at their start (Build-QuestLocationData.ps1) or at an
    instance's entrance (Sync-EntrancePins.ps1).
#>

$PinSameSpot = 1.5

# The task quests (QuestV2CliTask, by its QuestInfoID) that get no pin; every other task quest is placed like any
# quest of ours. Every QuestInfo kind named "World Quest" is here, and Build-QuestLocationData.ps1 stops at one that
# isn't, so a kind a new build adds can't start getting pins unseen. 265 is a hidden tracker, 268 an assault wrapper
# and 283 a bonus objective, none of them named "World Quest". 271 is kept out until it is known whether the game still
# offers callings: deleting its line pins that kind (docs/plans/open-items.md, decision 2).
$NoPinTaskKinds = [ordered]@{
    109 = 'World Quest'
    110 = 'Epic World Quest'
    111 = 'Elite World Quest'
    112 = 'Epic Elite World Quest'
    113 = 'PvP World Quest'
    114 = 'First Aid World Quest'
    115 = 'Battle Pet World Quest'
    116 = 'Blacksmithing World Quest'
    117 = 'Leatherworking World Quest'
    118 = 'Alchemy World Quest'
    119 = 'Herbalism World Quest'
    120 = 'Mining World Quest'
    121 = 'Tailoring World Quest'
    122 = 'Engineering World Quest'
    123 = 'Enchanting World Quest'
    124 = 'Skinning World Quest'
    125 = 'Jewelcrafting World Quest'
    126 = 'Inscription World Quest'
    129 = 'Archaeology World Quest'
    130 = 'Fishing World Quest'
    131 = 'Cooking World Quest'
    135 = 'Rare World Quest'
    136 = 'Rare Elite World Quest'
    137 = 'Dungeon World Quest'
    139 = 'Legion Invasion World Quest'
    141 = 'Raid World Quest'
    142 = 'Legion Invasion Elite World Quest'
    144 = 'Legionfall World Quest'
    145 = 'Legionfall Dungeon World Quest'
    146 = 'Legion Invasion World Quest Wrapper'
    151 = 'Magni World Quest - Azerite'
    152 = 'Tortollan World Quest - 8.0'
    259 = 'Faction Assault World Quest'
    260 = 'Faction Assault Elite World Quest'
    265 = 'Hidden Quest'
    268 = 'Threat Wrapper'
    271 = 'Calling Quest'
    278 = 'PvP Elite World Quest'
    283 = 'Bonus Objective with Completion Toast'
    286 = 'Capstone World Quest'
    295 = 'Prey World Quest'
    296 = 'World Quest (Short Duration)'
    298 = 'Lair World Quest'
}

# The quests of a QuestV2CliTask table (its rows) whose kind gets no pin.
function Get-NoPinTaskQuests($taskRows) {
    $quests = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($row in $taskRows) { if ($NoPinTaskKinds.Contains([int]$row.QuestInfoID)) { [void]$quests.Add([int]$row.ID) } }
    return , $quests
}

# The sources of a pin's giver, the first that has one winning:
#   pin        the pin the data already has for the quest at that place (retail's carry-over, which holds what the
#              client's giver table, the recorder and the hand decisions gave its pins)
#   game       the game's own name for an NPC (Forever: the probe's NPC pass)
#   recorded   what the recorder saw, from the ledger's trusted rows
#   emulator   a starter of the quest that TrinityCore or CMaNGOS puts there
#   neighbour  a known NPC within one spot that starts the quest (retail, for a quest no pin has yet)
$PinIdentityOrder = @('pin', 'game', 'recorded', 'emulator', 'neighbour')

function Get-PinDistance($ax, $ay, $bx, $by) {
    $dx = [double]([decimal]$ax - [decimal]$bx); $dy = [double]([decimal]$ay - [decimal]$by)
    return [math]::Sqrt($dx * $dx + $dy * $dy)
}

# The first source of $PinIdentityOrder in -Candidates (a source and what it says: a giver, a name or $null) that says
# something, as Source and Value; Source is 'none' when none does. A script block stands for a source that is slow to
# ask: it is run only when no source before it has an answer.
function Select-PinIdentity([System.Collections.IDictionary]$Candidates) {
    foreach ($source in $Candidates.Keys) {
        if ($PinIdentityOrder -notcontains $source) { throw "'$source' is not a source of `$PinIdentityOrder ($($PinIdentityOrder -join ', '))" }
    }
    foreach ($source in $PinIdentityOrder) {
        if (-not $Candidates.Contains($source)) { continue }
        $answer = $Candidates[$source]
        if ($answer -is [scriptblock]) { $answer = & $answer }
        if ($answer) { return [pscustomobject]@{ Source = $source; Value = $answer } }
    }
    return [pscustomobject]@{ Source = 'none'; Value = $null }
}

# The giver rows are grouped by: "npc:<ID>", else "name:<name>", else '' for a row that names nobody.
function Get-PinGiverKey($npc, $name) {
    if ($npc -and [string]$npc -ne '0') { return "npc:$npc" }
    if ($name) { return "name:$name" }
    return ''
}

function New-PinGroups() { return @{} }

# Of the groups of -Giver on -Map, the one whose first row stands nearest the point within one spot, or $null.
function Find-PinGroup($groups, $map, [string]$giver, $x, $y) {
    $list = $groups["$map|$giver"]
    if (-not $list) { return $null }
    $best = $null; $bestDistance = [double]::MaxValue
    foreach ($entry in $list) {
        $distance = Get-PinDistance $x $y $entry.X $entry.Y
        if ($distance -le $PinSameSpot -and $distance -lt $bestDistance) { $best = $entry.Group; $bestDistance = $distance }
    }
    return $best
}

# Starts a group of -Giver on -Map with its first row at the point, and returns -Group.
function Add-PinGroup($groups, $map, [string]$giver, $x, $y, $group) {
    $key = "$map|$giver"
    if (-not $groups.ContainsKey($key)) { $groups[$key] = New-Object System.Collections.Generic.List[object] }
    $groups[$key].Add([pscustomobject]@{ X = $x; Y = $y; Group = $group })
    return $group
}

# The icon of a pin from its quests' records (as data\quests.jsonl holds them): 5 when every quest is seasonal (type
# 64), 3 when every quest needs a profession, 9 when every quest is for some classes only, else 1.
function Get-PinQuestIcon($records) {
    $records = @($records | Where-Object { $null -ne $_ })
    if ($records.Count -eq 0) { return 1 }
    if (-not ($records | Where-Object { $_.type -ne 64 })) { return 5 }
    if (-not ($records | Where-Object { -not $_.profession })) { return 3 }
    if (-not ($records | Where-Object { $_.class -eq 8191 })) { return 9 }
    return 1
}

# What a nameless pin does once givers of some of its quests are known. -Claims maps each giver to the quests of the
# pin it offers there. A quest two givers claim stays where it is (Disputed). When one giver has every quest of the
# pin, the pin takes that giver (Fill); otherwise each giver's quests leave for its own pin (Moves, a giver to its
# quests, in -Claims' order) and the quests no giver has stay on the nameless pin.
function Split-NamelessPin($quests, [System.Collections.IDictionary]$Claims) {
    # Entries rather than indexing: an ordered table indexed by a number reads the entry at that position.
    $onPin = @($quests | ForEach-Object { [int]$_ })
    $claimedBy = @{}
    foreach ($claim in $Claims.GetEnumerator()) {
        foreach ($quest in @($claim.Value | ForEach-Object { [int]$_ } | Select-Object -Unique)) {
            if ($onPin -notcontains $quest) { continue }
            if (-not $claimedBy.ContainsKey($quest)) { $claimedBy[$quest] = New-Object System.Collections.Generic.List[object] }
            $claimedBy[$quest].Add($claim.Key)
        }
    }
    $disputed = [int[]]@($claimedBy.Keys | Where-Object { $claimedBy[$_].Count -gt 1 } | Sort-Object)
    $moves = [ordered]@{}
    foreach ($claim in $Claims.GetEnumerator()) {
        $mine = [int[]]@($onPin | Where-Object { $claimedBy.ContainsKey($_) -and $claimedBy[$_].Count -eq 1 -and $claimedBy[$_][0] -eq $claim.Key })
        if ($mine.Count) { $moves.Add($claim.Key, $mine) }
    }
    $fill = $null
    if ($moves.Count -eq 1 -and @($moves.Values)[0].Count -eq $onPin.Count) {
        $fill = @($moves.Keys)[0]
        $moves = [ordered]@{}
    }
    return [pscustomobject]@{ Fill = $fill; Moves = $moves; Disputed = $disputed }
}

# The pin of a giver on -From's map within one spot of it, nearest first: by NPC ID, or for a giver with none (an
# object) by its name on a pin with no NPC ID. $null when it has none there.
function Find-GiverPin($pins, $from, [int]$npc, [string]$name) {
    $best = $null; $bestDistance = [double]::MaxValue
    foreach ($pin in $pins) {
        if ([object]::ReferenceEquals($pin, $from) -or [int]$pin.map -ne [int]$from.map) { continue }
        if ($npc) { if ([int]$pin.npc -ne $npc) { continue } }
        elseif ([int]$pin.npc -ne 0 -or $null -eq $pin.name -or $pin.name -cne $name) { continue }
        $distance = Get-PinDistance $pin.x $pin.y $from.x $from.y
        if ($distance -le $PinSameSpot -and $distance -lt $bestDistance) { $best = $pin; $bestDistance = $distance }
    }
    return $best
}

# A new pin of a giver at -From's place, with its icon, for quests that leave it.
function New-GiverPin($from, [int]$npc, $name, $quests) {
    return [pscustomobject][ordered]@{
        map = [int]$from.map; icon = $from.icon; npc = $npc; name = $name
        x = $from.x; y = $from.y; quests = [int[]]@($quests); note = $null
    }
}
