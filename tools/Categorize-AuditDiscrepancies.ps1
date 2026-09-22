<#
Report-only. Reads quest_accuracy_audit.csv (from Audit-QuestAccuracy.ps1) and
summarises discrepancies by mismatch type, then clusters race/class/faction
mismatches by (current -> expected) value so recurring stale sentinels stand
out from genuine one-off disagreements. Makes no edits to qcQuest.lua.
#>
param(
    [string]$AuditCsv = "C:\Users\alist\RiderProjects\QuestCompletist\tools\quest_accuracy_audit.csv",
    [string]$OutFile = "C:\Users\alist\RiderProjects\QuestCompletist\tools\quest_accuracy_categories.txt",
    [int]$MinClusterSize = 10
)

$toolsDir = Split-Path $AuditCsv
$classNames = "Warrior","Paladin","Hunter","Rogue","Priest","DeathKnight","Shaman","Mage","Warlock","Druid","Monk","DemonHunter","Evoker"
$raceNames = "Human","Orc","Dwarf","NightElf","Undead","Tauren","Gnome","Troll","Goblin","BloodElf","Draenei","Worgen",
    "Pandaren","VoidElf","Nightborne","HighmountainTauren","LightforgedDraenei","DarkIronDwarf","MagharOrc",
    "ZandalariTroll","KulTiran","Vulpera","Mechagnome","Dracthyr","EarthenDwarf","Harronir"

function Get-BitNames([long]$mask, $names) {
    $out = @()
    for ($b = 0; $b -lt $names.Count; $b++) { if ($mask -band ([long]1 -shl $b)) { $out += $names[$b] } }
    $extra = $mask -band (-bnot ([long]([math]::Pow(2, $names.Count)) - 1))
    if ($extra) { $out += "unknownBits($extra)" }
    return $out
}

function Describe-Diff([long]$cur, [long]$exp, $names) {
    $missing = Get-BitNames ($exp -band (-bnot $cur)) $names
    $surplus = Get-BitNames ($cur -band (-bnot $exp)) $names
    $parts = @()
    if ($missing) { $parts += "cur lacks: " + ($missing -join ",") }
    if ($surplus) { $parts += "cur has extra: " + ($surplus -join ",") }
    return $parts -join "; "
}

$backfilled = @{}
$backfillFile = "$toolsDir\backfilled_quest_ids.txt"
if (Test-Path $backfillFile) { Get-Content $backfillFile | ForEach-Object { $t = $_.Trim(); if ($t) { $backfilled[$t] = $true } } }

$rows = Import-Csv $AuditCsv
$report = New-Object System.Collections.Generic.List[string]
function Say($s) { $report.Add($s) }

$combo = @{}
$clusters = @{ race = @{}; class = @{}; faction = @{} }
$rep = @{}

foreach ($r in $rows) {
    $types = @()
    foreach ($part in ($r.Mismatches -split " \| ")) {
        if ($part -match '^(race|class|faction): cur=(-?\d+) exp=(-?\d+)') {
            $types += $matches[1]
            $key = "$($matches[2])->$($matches[3])"
            if (-not $clusters[$matches[1]].ContainsKey($key)) { $clusters[$matches[1]][$key] = New-Object System.Collections.Generic.List[string] }
            $clusters[$matches[1]][$key].Add($r.QuestID)
        } elseif ($part -match '^reputation: cur_has=(\w+) exp_has=(\w+)') {
            $types += "reputation"
            $src = if ($backfilled.ContainsKey($r.QuestID)) { "backfilled" } else { "original" }
            $key = "cur_has=$($matches[1]) exp_has=$($matches[2]) [$src]"
            if (-not $rep.ContainsKey($key)) { $rep[$key] = 0 }
            $rep[$key]++
        } elseif ($part -match '^wago-') {
            if ($types -notcontains "wago") { $types += "wago" }
        }
    }
    $k = ($types | Sort-Object) -join "+"
    if (-not $combo.ContainsKey($k)) { $combo[$k] = 0 }
    $combo[$k]++
}

Say "Source: $AuditCsv"
Say "Total discrepancy rows: $($rows.Count)"
Say ""
Say "== Rows by mismatch combination =="
$combo.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { Say ("{0,7}  {1}" -f $_.Value, $_.Key) }

Say ""
Say "== Rows containing each mismatch type =="
foreach ($t in "faction","race","class") {
    $n = ($clusters[$t].Values | Measure-Object -Property Count -Sum).Sum
    Say ("{0,7}  {1}" -f $n, $t)
}
Say ("{0,7}  {1}" -f (($rep.Values | Measure-Object -Sum).Sum), "reputation")

foreach ($t in "race","class","faction") {
    $names = switch ($t) { "race" { $raceNames } "class" { $classNames } default { $null } }
    $all = $clusters[$t].GetEnumerator() | Sort-Object { $_.Value.Count } -Descending
    $big = @($all | Where-Object { $_.Value.Count -ge $MinClusterSize })
    $small = @($all | Where-Object { $_.Value.Count -lt $MinClusterSize })
    $smallRows = ($small | ForEach-Object { $_.Value.Count } | Measure-Object -Sum).Sum
    Say ""
    Say "== $t clusters (cur->exp), size >= $MinClusterSize =="
    foreach ($c in $big) {
        $cur, $exp = $c.Key -split "->"
        $desc = if ($names) { Describe-Diff ([long]$cur) ([long]$exp) $names } else { "" }
        $sample = ($c.Value | Select-Object -First 5) -join ","
        Say ("{0,7}  {1,-24} {2}" -f $c.Value.Count, $c.Key, $desc)
        Say ("         e.g. $sample")
    }
    Say ("  (+ {0} smaller clusters covering {1} rows)" -f $small.Count, [int]$smallRows)
}

Say ""
Say "== Reputation mismatches (direction, backfilled vs original entry) =="
$rep.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { Say ("{0,7}  {1}" -f $_.Value, $_.Key) }

# Field-level mismatches overstate the problem: e.g. an "all Alliance races" mask plus
# faction=1 hides exactly the same players as faction=1 with race=all. Compare what
# each (faction,race,class) triple actually lets players see, the way qcCore filters it.
if ($rows.Count -gt 0 -and $rows[0].PSObject.Properties.Name -contains "CurRace") {
    $neutralRaces = "Pandaren","Dracthyr","EarthenDwarf","Harronir"
    $allianceRaces = "Human","Dwarf","NightElf","Gnome","Draenei","Worgen","VoidElf","LightforgedDraenei","DarkIronDwarf","KulTiran","Mechagnome"
    $players = New-Object System.Collections.Generic.List[object]
    for ($b = 0; $b -lt $raceNames.Count; $b++) {
        $n = $raceNames[$b]
        $facs = if ($neutralRaces -contains $n) { 1, 2 } elseif ($allianceRaces -contains $n) { 1 } else { 2 }
        if ($n -eq "Pandaren") { $facs += 4 }
        foreach ($f in $facs) { $players.Add(@{ F = $f; R = [long]1 -shl $b }) }
    }
    function Get-Visible([long]$f, [long]$r, [long]$c) {
        $set = New-Object System.Collections.Generic.HashSet[string]
        foreach ($p in $players) {
            if (($f -band $p.F) -and ($r -band $p.R)) {
                for ($cb = 0; $cb -lt $classNames.Count; $cb++) { if ($c -band ([long]1 -shl $cb)) { [void]$set.Add("$($p.F):$($p.R):$cb") } }
            }
        }
        return ,$set
    }
    $visCache = @{}
    function Get-VisibleCached($f, $r, $c) {
        $k = "$f/$r/$c"
        if (-not $visCache.ContainsKey($k)) { $visCache[$k] = Get-Visible $f $r $c }
        return ,$visCache[$k]
    }

    $effect = @{}
    $effClusters = @{}
    foreach ($r in $rows) {
        $cur = Get-VisibleCached ([long]$r.CurFaction) ([long]$r.CurRace) ([long]$r.CurClass)
        $exp = Get-VisibleCached ([long]$r.ExpFaction) ([long]$r.ExpRace) ([long]$r.ExpClass)
        $h = New-Object System.Collections.Generic.HashSet[string] (,$exp); $h.ExceptWith($cur); $hidden = $h.Count
        $x = New-Object System.Collections.Generic.HashSet[string] (,$cur); $x.ExceptWith($exp); $extra = $x.Count
        $kind = if ($hidden -eq 0 -and $extra -eq 0) { "equivalent" } elseif ($extra -eq 0) { "over-restricted" } elseif ($hidden -eq 0) { "under-restricted" } else { "both" }
        $rep = if ($r.CurHasRep -ne $r.ExpHasRep) { " +rep" } else { "" }
        $ek = "$kind$rep"
        if (-not $effect.ContainsKey($ek)) { $effect[$ek] = 0 }
        $effect[$ek]++
        if ($kind -ne "equivalent") {
            $ck = "$kind  f$($r.CurFaction)/r$($r.CurRace)/c$($r.CurClass) -> f$($r.ExpFaction)/r$($r.ExpRace)/c$($r.ExpClass)"
            if (-not $effClusters.ContainsKey($ck)) { $effClusters[$ck] = New-Object System.Collections.Generic.List[string] }
            $effClusters[$ck].Add($r.QuestID)
        }
    }

    Say ""
    Say "== Effective visibility vs API (faction/race/class combined; +rep = reputation also differs) =="
    $effect.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { Say ("{0,7}  {1}" -f $_.Value, $_.Key) }
    Say ""
    Say "== Visibility-changing clusters (cur -> exp), size >= $MinClusterSize =="
    $effClusters.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending | Where-Object { $_.Value.Count -ge $MinClusterSize } | ForEach-Object {
        Say ("{0,7}  {1}" -f $_.Value.Count, $_.Key)
        Say ("         e.g. " + (($_.Value | Select-Object -First 5) -join ","))
    }
    $smallEff = @($effClusters.Values | Where-Object { $_.Count -lt $MinClusterSize })
    Say ("  (+ {0} smaller clusters covering {1} rows)" -f $smallEff.Count, [int](($smallEff | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum))
}

# Three-way vote per field: ours vs Blizzard API vs wago.tools client data. Both sources
# routinely omit restrictions enforced by zone/phase/NPC, so "no restriction" from either
# is never evidence; only an explicit restriction counts.
#   FIX    - both sources assert the same value, or one asserts a subset of ours and the
#            other is silent (narrowing only)
#   SKIP   - the sources disagree and one of them matches ours
#   MANUAL - anything else (conflicting single source, sources disagree with each other,
#            or the combined fix would leave faction and race contradicting each other)
if ($rows.Count -gt 0 -and $rows[0].PSObject.Properties.Name -contains "WagoRace") {
    $allFor = @{ faction = 3; race = 67108863; class = 8191 }
    $allianceOnly = 64175181 -band -bnot (64175181 -band 61658034)
    $hordeOnly = 61658034 -band -bnot (64175181 -band 61658034)
    $candidates = New-Object System.Collections.Generic.List[object]

    foreach ($r in $rows) {
        $fields = @(
            @{ N = "faction"; Cur = [long]$r.CurFaction; Api = [long]$r.ExpFaction; Wago = $r.WagoFaction },
            @{ N = "race"; Cur = [long]$r.CurRace; Api = [long]$r.ExpRace; Wago = $r.WagoRace },
            @{ N = "class"; Cur = [long]$r.CurClass; Api = [long]$r.ExpClass; Wago = $r.WagoClass }
        )
        $questRows = @()
        foreach ($f in $fields) {
            $apiSays = $f.Api -ne $allFor[$f.N]
            $wagoSays = [bool]$f.Wago
            $wagoVal = if ($wagoSays) { [long]$f.Wago } else { $null }
            if ((-not $apiSays -or $f.Api -eq $f.Cur) -and (-not $wagoSays -or $wagoVal -eq $f.Cur)) { continue }

            $target = $null
            if ($apiSays -and $wagoSays) {
                if ($f.Api -eq $wagoVal) { $decision = "FIX"; $reason = "api+wago agree"; $target = $wagoVal }
                elseif ($f.Api -eq $f.Cur) { $decision = "SKIP"; $reason = "api supports ours, wago differs" }
                elseif ($wagoVal -eq $f.Cur) { $decision = "SKIP"; $reason = "wago supports ours, api differs" }
                else { $decision = "MANUAL"; $reason = "api and wago disagree with each other and ours" }
            } else {
                $src = if ($apiSays) { "api" } else { "wago" }
                $val = if ($apiSays) { $f.Api } else { $wagoVal }
                if (($f.Cur -band $val) -eq $val) { $decision = "FIX"; $reason = "$src-only narrowing"; $target = $val }
                else { $decision = "MANUAL"; $reason = "$src-only conflicting" }
            }
            $questRows += [PSCustomObject]@{
                QuestID = $r.QuestID; Name = $r.Name; Field = $f.N; Cur = $f.Cur
                Api = if ($apiSays) { $f.Api } else { "" }; Wago = $f.Wago
                Target = $target; Decision = $decision; Reason = $reason
            }
        }
        if (-not $questRows) { continue }

        $pf = [long]$r.CurFaction; $pr = [long]$r.CurRace; $pc = [long]$r.CurClass
        foreach ($q in $questRows | Where-Object Decision -eq "FIX") {
            switch ($q.Field) { "faction" { $pf = $q.Target } "race" { $pr = $q.Target } "class" { $pc = $q.Target } }
        }
        $own = switch ($pf) { 1 { $allianceOnly } 2 { $hordeOnly } default { $null } }
        $other = switch ($pf) { 1 { $hordeOnly } 2 { $allianceOnly } default { $null } }
        $incoherent = ($null -ne $own) -and (($pr -band $own) -eq 0) -and (($pr -band $other) -ne 0)
        $empty = (Get-VisibleCached $pf $pr $pc).Count -eq 0
        if ($incoherent -or $empty) {
            foreach ($q in $questRows | Where-Object Decision -eq "FIX") {
                $q.Decision = "MANUAL"; $q.Target = $null
                $q.Reason += $(if ($empty) { "; combined fix hides quest from everyone" } else { "; combined fix leaves faction/race contradictory" })
            }
        }
        foreach ($q in $questRows) { $candidates.Add($q) }
    }

    $candFile = "$toolsDir\quest_accuracy_candidates.csv"
    $candidates | Export-Csv $candFile -NoTypeInformation -Encoding utf8
    Say ""
    Say "== Three-way vote (ours / API / wago), per field -> $candFile =="
    $candidates | Group-Object Field, Decision, Reason | Sort-Object Name | ForEach-Object { Say ("{0,7}  {1}" -f $_.Count, $_.Name) }
    Say ""
    foreach ($d in "FIX", "SKIP", "MANUAL") {
        $n = @($candidates | Where-Object Decision -eq $d | ForEach-Object QuestID | Sort-Object -Unique).Count
        Say ("{0,7}  distinct quests with a {1} field" -f $n, $d)
    }
}

$report | Out-File $OutFile -Encoding utf8
$report
