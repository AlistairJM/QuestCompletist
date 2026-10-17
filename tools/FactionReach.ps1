# Which playable races can earn each faction's reputation, and whether the game ever shows its bar, from the client's
# Faction and ChrRaces tables. Dot-sourced by Sync-FactionReach.ps1 (docs/maintenance.md, step 2n), which writes it into
# data\factions.jsonl for the quest list's tooltip, and Compare-QuestReputation.ps1, which needs "shown" (step 2e).
# docs/plans/client-tables-audit.md, opportunity 5.
#
# A faction keeps a standing when its ReputationIndex is 0 or more. It has four slots, each a race mask (two 32-bit words,
# indexed by ChrRaces.PlayableRaceBit), a class mask (1 shifted by the class ID less one; 0 or -1 for every class), a base,
# a cap and flags. A character gets the first slot whose race mask is empty or holds its race and whose class mask holds
# its class (TrinityCore's GetFactionDataIndexForRaceAndClass). It can earn the faction when that slot's cap is above its
# base: the other side's factions sit at -42000 of -42000, hated and at war. The slot shows a bar unless it is hidden (flag
# 0x4) or a header without its own bar (0x8 without 0x80; "Horde" and "Alliance" are such headers).

# The races a player can play: ChrRaces.Flags 0x1 marks those no player plays.
function Get-PlayableRaces($raceRows) {
    foreach ($row in $raceRows) {
        if (([long]$row.Flags -band 1) -ne 0 -or [int]$row.PlayableRaceBit -lt 0) { continue }
        [pscustomobject]@{ Id = [int]$row.ID; Bit = [int]$row.PlayableRaceBit }
    }
}

function Test-RaceInMask($low, $high, [int]$bit) {
    $lo = [int64]$low; if ($lo -lt 0) { $lo += 4294967296 }
    $hi = [int64]$high; if ($hi -lt 0) { $hi += 4294967296 }
    if ($lo -eq 0 -and $hi -eq 0) { return $true }
    if ($bit -lt 32) { return ($lo -band ([int64]1 -shl $bit)) -ne 0 }
    return ($hi -band ([int64]1 -shl ($bit - 32))) -ne 0
}

function Test-SlotShown([int]$flags) { return -not ($flags -band 4) -and -not (($flags -band 8) -and -not ($flags -band 0x80)) }

# Faction ID -> Id, Name, Races (the playable races that can earn it, by ChrRaces ID, ascending), Everyone (every playable
# race can) and Shown (the bar shows for some race that can earn it). With no race rows, every slot counts as some race's.
function Get-FactionReach($factionRows, $raceRows) {
    $races = @(Get-PlayableRaces $raceRows)
    $reach = @{}
    foreach ($f in $factionRows) {
        if ([int]$f.ReputationIndex -lt 0) { continue }
        $slots = @(for ($i = 0; $i -lt 4; $i++) {
            [pscustomobject]@{ Low = $f."ReputationRaceMasks${i}_0"; High = $f."ReputationRaceMasks${i}_1"; Class = [int64]$f."ReputationClassMask_$i"
                Earn = [int]$f."ReputationMax_$i" -gt [int]$f."ReputationBase_$i"; Shown = Test-SlotShown ([int]$f."ReputationFlags_$i") }
        })
        $earners = New-Object System.Collections.Generic.List[int]
        $shown = $false
        if (-not $races.Count) {
            foreach ($slot in $slots) { if ($slot.Earn -and $slot.Shown) { $shown = $true } }
        }
        foreach ($race in $races) {
            $earns = $false
            for ($class = 0; $class -lt 13 -and -not ($earns -and $shown); $class++) {
                foreach ($slot in $slots) {
                    if (-not (Test-RaceInMask $slot.Low $slot.High $race.Bit)) { continue }
                    if ($slot.Class -ne 0 -and $slot.Class -ne -1 -and -not ($slot.Class -band ([int64]1 -shl $class))) { continue }
                    if ($slot.Earn) { $earns = $true; if ($slot.Shown) { $shown = $true } }
                    break
                }
            }
            if ($earns) { $earners.Add($race.Id) }
        }
        $earned = @($earners | Sort-Object)
        $reach[[int]$f.ID] = [pscustomobject]@{ Id = [int]$f.ID; Name = $f.Name_lang; Races = $earned; Everyone = (-not $races.Count) -or $earned.Count -eq $races.Count; Shown = $shown }
    }
    return $reach
}

# The data file's records: a faction some playable race can't earn lists the races that can (none, for one nobody can),
# and one whose bar never shows is hidden. Factions every race can earn and see are left out.
function Get-FactionReachRecords($reach) {
    foreach ($id in ($reach.Keys | Sort-Object)) {
        $f = $reach[$id]
        if ($f.Everyone -and $f.Shown) { continue }
        $record = [ordered]@{ faction = $id }
        if (-not $f.Everyone) { $record.races = @($f.Races) }
        if (-not $f.Shown) { $record.hidden = $true }
        [pscustomobject]$record
    }
}
