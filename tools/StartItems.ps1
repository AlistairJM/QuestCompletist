# Items that start quests, from a client's ItemSparse and ChrRaces, for Sync-QuestStartItems.ps1 (both games) and its
# test. ItemSparse.StartQuestID is the only client link from an item to the quest it begins; the StartItem of the quest
# cache and TrinityCore is the item handed over on accept (docs/plans/retail-quest-cache.md, "Start item").
# Each item's own limits come with it:
#   side       its faction flag: Flags_1 0x1 Horde, 0x2 Alliance (TrinityCore's ITEM_FLAG2_FACTION_HORDE and
#              _ALLIANCE; exactly one of them on every item that has an opposite-faction twin)
#   level      RequiredLevel, the level to use it
#   skill      RequiredSkill and RequiredSkillRank, the skill line and skill to use it
#   rep        MinFactionID and MinReputation, the faction and standing (TrinityCore's ReputationRank, 0 Hated to 7 Exalted)
#   races      the playable races that may use it, as ChrRaces IDs, when not all may: AllowableRaces_0/_1 on retail,
#              AllowableRace_0/_1 on WoW: Forever, two 32-bit words of the race mask whose bits are
#              ChrRaces.PlayableRaceBit (0 or -1 for every race; ChrRaces.Flags 0x1 marks races no player plays)

# Race mask bit -> ChrRaces ID, for the races a player can play.
function Get-PlayableRaceBits($raceRows) {
    $bits = @{}
    foreach ($r in $raceRows) {
        if (([long]$r.Flags -band 1) -ne 0) { continue }
        $bit = [int]$r.PlayableRaceBit
        if ($bit -ge 0) { $bits[$bit] = [int]$r.ID }
    }
    return $bits
}

# The ChrRaces IDs a race mask allows, or $null when it allows every playable race.
function ConvertFrom-RaceWords([string]$low, [string]$high, $bits) {
    $lo = [long]$low; $hi = [long]$high
    if (($lo -eq 0 -and $hi -eq 0) -or ($lo -eq -1 -and $hi -eq -1)) { return $null }
    $mask = [uint64]($lo -band 0xFFFFFFFFL) -bor ([uint64]($hi -band 0xFFFFFFFFL) -shl 32)
    $ids = @(); $all = $true
    foreach ($bit in ($bits.Keys | Sort-Object)) {
        if ((($mask -shr $bit) -band 1) -eq 1) { $ids += $bits[$bit] } else { $all = $false }
    }
    if ($all -or -not $ids.Count) { return $null }
    return , @($ids | Sort-Object)
}

# Side (1 Alliance, 2 Horde) -> its playable races' IDs joined by commas, from ChrRaces.Alliance (0 Alliance, 1 Horde,
# 2 neither, as the starting Pandaren); and the IDs of the races of neither side.
function Get-SideRaces($raceRows) {
    $sides = @{ 1 = @(); 2 = @() }; $neither = @()
    foreach ($r in $raceRows) {
        if (([long]$r.Flags -band 1) -ne 0 -or [int]$r.PlayableRaceBit -lt 0) { continue }
        switch ([int]$r.Alliance) { 0 { $sides[1] += [int]$r.ID } 1 { $sides[2] += [int]$r.ID } default { $neither += [int]$r.ID } }
    }
    return [pscustomobject]@{ Alliance = (@($sides[1] | Sort-Object) -join ','); Horde = (@($sides[2] | Sort-Object) -join ','); Neither = $neither }
}

# One record per item that starts one of $questIds (a hashtable of quest ID -> anything), in item order. Races that are
# exactly one side's playable races are that side: the item's faction, not a list of races.
function Get-StartItemRecords($itemRows, $raceRows, $questIds) {
    $bits = Get-PlayableRaceBits $raceRows
    $sideRaces = Get-SideRaces $raceRows
    $records = New-Object System.Collections.Generic.List[object]
    $lowColumn = $null
    foreach ($row in $itemRows) {
        $quest = 0
        if (-not [int]::TryParse($row.StartQuestID, [ref]$quest) -or $quest -le 0 -or -not $questIds.ContainsKey($quest)) { continue }
        if (-not $lowColumn) { $lowColumn = if ($row.PSObject.Properties['AllowableRaces_0']) { 'AllowableRaces' } else { 'AllowableRace' } }
        $faction = [long]$row.Flags_1 -band 3
        $side = if ($faction -eq 1) { 2 } elseif ($faction -eq 2) { 1 } else { $null }
        $skill = [int]$row.RequiredSkill
        $rep = [int]$row.MinFactionID
        $races = ConvertFrom-RaceWords $row."${lowColumn}_0" $row."${lowColumn}_1" $bits
        if ($races) {
            $sided = (@($races | Where-Object { $sideRaces.Neither -notcontains $_ }) -join ',')
            $raceSide = if ($sided -ceq $sideRaces.Alliance) { 1 } elseif ($sided -ceq $sideRaces.Horde) { 2 } else { $null }
            if ($raceSide -and ($null -eq $side -or $side -eq $raceSide)) { $side = $raceSide; $races = $null }
        }
        $records.Add([pscustomobject]@{
            item = [int]$row.ID
            quest = $quest
            side = $side
            level = if ([int]$row.RequiredLevel -gt 1) { [int]$row.RequiredLevel } else { $null }
            skill = if ($skill -gt 0) { $skill } else { $null }
            skillRank = if ($skill -gt 0 -and [int]$row.RequiredSkillRank -gt 0) { [int]$row.RequiredSkillRank } else { $null }
            rep = if ($rep -gt 0) { $rep } else { $null }
            repRank = if ($rep -gt 0 -and [int]$row.MinReputation -gt 0) { [int]$row.MinReputation } else { $null }
            races = $races
        })
    }
    return , @($records | Sort-Object item)
}

# The quests whose faction their start items contradict: every item that starts the quest is for one side, and the
# quest is for the other or for both. The items of a quest with an item for each side say nothing.
function Get-StartItemFactionDisagreements($records, $quests) {
    $out = @()
    foreach ($group in ($records | Group-Object quest)) {
        if (@($group.Group | Where-Object { $null -eq $_.side }).Count) { continue }
        $sides = @($group.Group | ForEach-Object { $_.side } | Sort-Object -Unique)
        if ($sides.Count -ne 1) { continue }
        $q = $quests[[int]$group.Name]
        if ($q -and [int]$q.faction -ne $sides[0]) { $out += [pscustomobject]@{ Quest = [int]$group.Name; Name = $q.name; Faction = [int]$q.faction; ItemSide = $sides[0]; Items = (@($group.Group | ForEach-Object { $_.item }) -join ',') } }
    }
    return , $out
}
