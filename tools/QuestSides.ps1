# Which side can take a quest: the side Blizzard names for it, and the side that can talk to its givers. Dot-sourced by
# Sync-QuestSides.ps1 (docs/maintenance.md, step 2p; WoW: Forever's in step 10). docs/plans/client-tables-audit.md,
# opportunity 6.
#
# A side can talk to a giver when some playable race of it can (ChrRaces.Alliance: 0 the Alliance, 1 the Horde; each
# race's own FactionTemplate, ChrRaces.FactionID), by TrinityCore's Unit::GetFactionReactionTo: a giver whose faction
# keeps a standing (Faction.ReputationIndex 0 or more) goes by the race's first slot of it (FactionReach.ps1), and the
# race can talk to it once that slot's cap is neutral or better, as the other side's factions, -42000 of -42000, never
# are; any other giver goes by the two templates: hostile when either names the other's faction an enemy or the giver's
# enemy groups hold the race's group, friendly when either names the other a friend or their friend groups meet, and
# otherwise neutral, unless the giver is hostile by default (FactionTemplate flag 0x800). A quest giver talks to a
# neutral or friendlier player. An object of faction 0 or an item anyone can loot is open to both sides; an item of one
# side (data\startitems.jsonl) is that side's.
#
# Sides are a mask: 1 the Alliance, 2 the Horde, 3 both, 0 neither.

function Get-TemplateEnemies($t) { @(for ($i = 0; $i -lt 8; $i++) { [int]$t."Enemies_$i" }) | Where-Object { $_ } }
function Get-TemplateFriends($t) { @(for ($i = 0; $i -lt 8; $i++) { [int]$t."Friend_$i" }) | Where-Object { $_ } }

function New-SideReader($templateRows, $factionRows, $raceRows) {
    $templates = @{}
    foreach ($t in $templateRows) {
        $templates[[int]$t.ID] = [pscustomobject]@{ Id = [int]$t.ID; Faction = [int]$t.Faction; Flags = [int64]$t.Flags; Group = [int]$t.FactionGroup
            FriendGroup = [int]$t.FriendGroup; EnemyGroup = [int]$t.EnemyGroup; Enemies = @(Get-TemplateEnemies $t); Friends = @(Get-TemplateFriends $t) }
    }
    $factions = @{}
    foreach ($f in $factionRows) {
        if ([int]$f.ReputationIndex -lt 0) { continue }
        $factions[[int]$f.ID] = @(for ($i = 0; $i -lt 4; $i++) {
            [pscustomobject]@{ Low = $f."ReputationRaceMasks${i}_0"; High = $f."ReputationRaceMasks${i}_1"; Class = [int64]$f."ReputationClassMask_$i"; Max = [int]$f."ReputationMax_$i" }
        })
    }
    $players = @{ 1 = @(); 2 = @() }
    foreach ($r in $raceRows) {
        if (([long]$r.Flags -band 1) -ne 0 -or [int]$r.PlayableRaceBit -lt 0) { continue }
        $side = switch ([int]$r.Alliance) { 0 { 1 } 1 { 2 } default { 0 } }
        if ($side -and $templates.ContainsKey([int]$r.FactionID)) { $players[$side] += [pscustomobject]@{ Bit = [int]$r.PlayableRaceBit; Template = $templates[[int]$r.FactionID] } }
    }
    return @{ Templates = $templates; Factions = $factions; Players = $players; Known = @{} }
}

function Test-TemplateHostile($a, $b) {
    if ($a.Id -eq $b.Id) { return $false }
    if ($b.Faction) { if ($a.Enemies -contains $b.Faction) { return $true }; if ($a.Friends -contains $b.Faction) { return $false } }
    return ($a.EnemyGroup -band $b.Group) -ne 0
}
function Test-TemplateFriendly($a, $b) {
    if ($a.Id -eq $b.Id) { return $true }
    if ($b.Faction) { if ($a.Enemies -contains $b.Faction) { return $false }; if ($a.Friends -contains $b.Faction) { return $true } }
    return (($a.FriendGroup -band $b.Group) -ne 0) -or (($a.Group -band $b.FriendGroup) -ne 0)
}

# Whether one playable race can talk to a giver of this FactionTemplate.
function Test-RaceCanTalk($reader, $player, $giver) {
    $slots = $reader.Factions[$giver.Faction]
    if ($slots) {
        for ($class = 0; $class -lt 13; $class++) {
            foreach ($slot in $slots) {
                if (-not (Test-RaceInMask $slot.Low $slot.High $player.Bit)) { continue }
                if ($slot.Class -ne 0 -and $slot.Class -ne -1 -and -not ($slot.Class -band ([int64]1 -shl $class))) { continue }
                if ($slot.Max -ge 0) { return $true }
                break
            }
        }
        return $false
    }
    $race = $player.Template
    if (Test-TemplateHostile $giver $race) { return $false }
    if ((Test-TemplateFriendly $giver $race) -or (Test-TemplateFriendly $race $giver)) { return $true }
    return -not ($giver.Flags -band 0x800)
}

# The sides that can talk to a giver of this FactionTemplate ID, or $null for a template the build doesn't have.
function Get-TemplateSides($reader, [int]$template) {
    if ($reader.Known.ContainsKey($template)) { return $reader.Known[$template] }
    $giver = $reader.Templates[$template]
    $sides = $null
    if ($giver) {
        $sides = 0
        foreach ($side in 1, 2) { foreach ($player in $reader.Players[$side]) { if (Test-RaceCanTalk $reader $player $giver) { $sides = $sides -bor $side; break } } }
    }
    $reader.Known[$template] = $sides
    return $sides
}

# The sides that can start a quest from its starters: each @{ Kind = 'npc' | 'object' | 'item'; Template = FactionTemplate
# ID or $null when unknown; Side = an item's side, 0 for none }. $null when there are none, or when one is unknown and the
# others don't already open it to both sides.
function Get-StarterSides($reader, $starters) {
    $sides = 0; $unknown = $false; $any = $false
    foreach ($s in $starters) {
        $any = $true
        $mask = switch ($s.Kind) {
            'item' { if ($s.Side -eq 1 -or $s.Side -eq 2) { $s.Side } else { 3 } }
            'object' { if ($null -eq $s.Template) { $null } elseif ($s.Template -eq 0) { 3 } else { Get-TemplateSides $reader $s.Template } }
            default { if ($null -eq $s.Template) { $null } elseif ($s.Template -eq 0) { 3 } else { Get-TemplateSides $reader $s.Template } }
        }
        if ($null -eq $mask) { $unknown = $true } else { $sides = $sides -bor $mask }
    }
    if (-not $any) { return $null }
    if ($sides -eq 3) { return 3 }
    if ($unknown) { return $null }
    return $sides
}

# The zone's side from AreaTable.FactionGroupMask (2 the Alliance, 4 the Horde, 6 both), walking up to the parent while a
# subzone has none: 1, 2, 3, or 0 when no row says.
function Get-ZoneSide($areas, [int]$zone) {
    for ($depth = 0; $zone -and $areas.ContainsKey($zone) -and $depth -lt 10; $depth++) {
        $mask = [int]$areas[$zone].FactionGroupMask
        if ($mask) { return (($mask -band 2) -shr 1) -bor (($mask -band 4) -shr 1) }
        $zone = [int]$areas[$zone].ParentAreaID
    }
    return 0
}

function Test-SideOpen([int]$faction) { return $faction -eq 0 -or ($faction -band 3) -eq 3 }

# What the step does with one quest: Faction, the side Blizzard names for a quest the data opens to both (into
# quests.jsonl); Side, the side of its givers for one Blizzard names no side for and no KEEP row holds (into sides.jsonl);
# Finding, a quest of one side Blizzard names the other for.
function Get-QuestSideResult([int]$ours, $blizzard, $reach, [bool]$keep) {
    $open = Test-SideOpen $ours
    if ($open -and ($blizzard -eq 1 -or $blizzard -eq 2)) { return [pscustomobject]@{ Faction = [int]$blizzard; Side = 0; Finding = '' } }
    if ($open -and -not $keep -and ($reach -eq 1 -or $reach -eq 2)) { return [pscustomobject]@{ Faction = 0; Side = [int]$reach; Finding = '' } }
    if (-not $open -and ($blizzard -eq 1 -or $blizzard -eq 2) -and ($ours -band 3) -ne $blizzard) {
        return [pscustomobject]@{ Faction = 0; Side = 0; Finding = "Blizzard names the $(if ($blizzard -eq 1) { 'Alliance' } else { 'Horde' })" }
    }
    return $null
}

# A quest's prerequisites, however the list nests them (a choice's every quest too).
function Get-PrereqIds($value) {
    if ($value -is [array]) { foreach ($v in $value) { Get-PrereqIds $v } } elseif ($null -ne $value) { [int]$value }
}

# The quest chain's say on the givers' sides. $Needs: quest -> its prerequisites; $NeededBy: quest -> the quests that need
# it; $Fixed: quest -> the side the data gives it (1 or 2); $Rows: quest -> its givers' side; $Open: the quests a side may
# follow onto (open to both, no side Blizzard names, no KEEP row). A row whose quest needs, or is needed by, a quest of the
# other side goes (its chain is that side's, so a giver says otherwise only by mistake), until none clashes; then a quest
# of $Open whose prerequisites are one side's, one of them by a row, follows them, as the other side can't do them. Returns
# Rows (quest -> side), Dropped (quest -> the chain's side) and Followed (quest -> the prerequisite it follows).
function Resolve-ChainSides($Needs, $NeededBy, $Fixed, $Rows, $Open) {
    $side = @{}
    foreach ($q in $Rows.Keys) { $side[$q] = $Rows[$q] }
    $sideOf = { param($q) if ($Fixed.ContainsKey($q)) { $Fixed[$q] } elseif ($side.ContainsKey($q)) { $side[$q] } else { 0 } }
    $dropped = @{}
    do {
        $again = $false
        foreach ($q in @($side.Keys)) {
            $other = 3 - $side[$q]
            if (@(@($Needs[$q]) + @($NeededBy[$q]) | Where-Object { $_ -and (& $sideOf $_) -eq $other }).Count) { $dropped[$q] = $other; $side.Remove($q); $again = $true }
        }
    } while ($again)
    $followed = @{}
    $candidates = @($Open.Keys | Where-Object { $Needs.ContainsKey($_) -and -not $side.ContainsKey($_) -and -not $dropped.ContainsKey($_) })
    do {
        $again = $false
        foreach ($q in $candidates) {
            if ($side.ContainsKey($q)) { continue }
            $sides = @($Needs[$q] | ForEach-Object { & $sideOf $_ } | Where-Object { $_ -eq 1 -or $_ -eq 2 } | Sort-Object -Unique)
            $via = @($Needs[$q] | Where-Object { $side.ContainsKey($_) })
            if ($sides.Count -ne 1 -or -not $via.Count) { continue }
            if (@($NeededBy[$q] | Where-Object { $_ -and (& $sideOf $_) -eq 3 - $sides[0] }).Count) { continue }
            $side[$q] = $sides[0]; $followed[$q] = $via[0]; $again = $true
        }
    } while ($again)
    return [pscustomobject]@{ Rows = $side; Dropped = $dropped; Followed = $followed }
}

# The KEEP rows of docs\plans\quest-side-decisions.csv for one game: quest ID -> the row's evidence. A KEEP row leaves a
# quest open to both sides though its known givers are one side's.
function Read-QuestSideDecisions([string]$path, [string]$game) {
    $keep = @{}
    if (-not (Test-Path $path)) { return $keep }
    foreach ($row in (Import-Csv $path -Encoding UTF8)) {
        if ($row.Game -ne $game) { continue }
        if ($row.Decision -ne 'KEEP') { throw "quest-side-decisions.csv: quest $($row.QuestID) has decision '$($row.Decision)'; only KEEP is known." }
        $keep[[int]$row.QuestID] = $row.Evidence
    }
    return $keep
}
