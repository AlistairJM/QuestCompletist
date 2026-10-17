<#
Checks FactionReach.ps1 and the factions of AddonData.ps1 (Sync-FactionReach.ps1, step 2n) on a made-up Faction and ChrRaces
table and data folder in a temporary folder: nothing in the checkout is touched and nothing is downloaded. It checks which
races are playable, the first slot a race and class get (a race mask's low and high word, the sign bit of each, a class
mask), who can earn each faction (an open one, the other side's locked one, one locked for one race, a class's own slot,
one nobody can, a race no slot names falling into an empty slot), which never shows its bar (hidden, a header without its
own bar, a header with it), the reading with no race table, the records, the data file's form and checks, the Lua, and the
build.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncFactionReach.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
. (Join-Path $PSScriptRoot 'FactionReach.ps1')
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

# Races: 1 (bit 0) and 3 (bit 2) the Alliance's, 2 (bit 1) and 27 (bit 26) the Horde's, 31 (bit 31: the low word's sign
# bit) and 40 (bit 33: the high word) the Alliance's too, 24 (bit 23) of neither side, 99 no player's.
$races = @(
    [pscustomobject]@{ ID = '1'; Flags = '0'; PlayableRaceBit = '0' }, [pscustomobject]@{ ID = '2'; Flags = '0'; PlayableRaceBit = '1' },
    [pscustomobject]@{ ID = '3'; Flags = '0'; PlayableRaceBit = '2' }, [pscustomobject]@{ ID = '27'; Flags = '0'; PlayableRaceBit = '26' },
    [pscustomobject]@{ ID = '31'; Flags = '0'; PlayableRaceBit = '31' }, [pscustomobject]@{ ID = '40'; Flags = '0'; PlayableRaceBit = '33' },
    [pscustomobject]@{ ID = '24'; Flags = '0'; PlayableRaceBit = '23' }, [pscustomobject]@{ ID = '99'; Flags = '1'; PlayableRaceBit = '40' },
    [pscustomobject]@{ ID = '98'; Flags = '0'; PlayableRaceBit = '-1' })
$alliance = @(1, 4, -2147483648, 2)   # low word bits 0, 2, 31; high word bit 1 (race bit 33)
$allianceLow = 1 + 4 + -2147483648; $allianceHigh = 2
$hordeLow = 2 + 67108864; $hordeHigh = 0
# [id, index, [slot: low, high, class, base, max, flags] ...]
function Faction($id, $index, $slots) {
    $row = [ordered]@{ ID = "$id"; Name_lang = "Faction $id"; ReputationIndex = "$index" }
    for ($i = 0; $i -lt 4; $i++) {
        $s = if ($i -lt $slots.Count) { $slots[$i] } else { @(0, 0, 0, 0, 0, 0) }
        $row["ReputationRaceMasks${i}_0"] = "$($s[0])"; $row["ReputationRaceMasks${i}_1"] = "$($s[1])"; $row["ReputationClassMask_$i"] = "$($s[2])"
        $row["ReputationBase_$i"] = "$($s[3])"; $row["ReputationMax_$i"] = "$($s[4])"; $row["ReputationFlags_$i"] = "$($s[5])"
    }
    return [pscustomobject]$row
}
$factions = @(
    (Faction 10 1 @(, @(0, 0, 0, 0, 42000, 16))),                                                                  # everyone
    (Faction 11 2 @(@($allianceLow, $allianceHigh, 0, -42000, -42000, 6), @(0, 0, 0, 0, 42000, 16))),               # the Horde's: the Alliance locked first
    (Faction 12 3 @(@($hordeLow, $hordeHigh, 0, -42000, -42000, 6), @($allianceLow, $allianceHigh, 0, 0, 42000, 16))),  # the Alliance's; 24 falls in the empty slot
    (Faction 13 4 @(@(67108864, 0, 0, -42000, -42000, 6), @(0, 0, 0, 0, 42000, 16))),                               # all but race 27
    (Faction 14 5 @(@(0, 0, 32, 3200, 42000, 16), @(0, 0, 0, 0, 42000, 16))),                                       # a class's own slot first
    (Faction 15 6 @(, @(0, 0, 0, -42000, -42000, 6))),                                                             # nobody
    (Faction 16 7 @(, @(0, 0, 0, 0, 42000, 20))),                                                                  # hidden
    (Faction 67 8 @(, @(0, 0, 0, 0, 42000, 25))),                                                                  # a header without its bar
    (Faction 18 9 @(, @(0, 0, 0, 0, 42000, 136))),                                                                 # a header with its bar
    (Faction 19 -1 @(, @(0, 0, 0, 0, 42000, 16))),                                                                 # no standing
    (Faction 20 10 @(@($allianceLow, $allianceHigh, 0, 0, 42000, 16), @($hordeLow, $hordeHigh, 0, -42000, -42000, 6))))  # the Alliance's; 24 matches no slot

Equal (@(Get-PlayableRaces $races | ForEach-Object { $_.Id }) -join ',') '1,2,3,27,31,40,24' 'P1: playable races: not no player''s, not without a bit'
Check (Test-RaceInMask -2147483648 0 31) 'P2: the low word''s sign bit is race bit 31'
Check (Test-RaceInMask 0 2 33) 'P2: the high word holds bits 32 and on'
Check (-not (Test-RaceInMask 4 0 0)) 'P2: a mask without the race''s bit doesn''t hold it'
Check (Test-RaceInMask 0 0 5) 'P2: an empty mask holds every race'

$reach = Get-FactionReach $factions $races
Equal $reach.Count 10 'R1: every faction with a standing, none without'
Check ($reach[10].Everyone -and $reach[10].Shown) 'R2: an open faction: everyone, shown'
Equal ($reach[11].Races -join ',') '2,24,27' 'R3: the other side locked first: the rest can earn it'
Equal ($reach[12].Races -join ',') '1,3,31,40' 'R3: and the mirror; a race of neither side falls into the empty slot, base 0 and cap 0'
Equal ($reach[13].Races -join ',') '1,2,3,24,31,40' 'R4: one race locked out'
Check $reach[14].Everyone 'R5: a class''s own first slot doesn''t lock the other classes out'
Equal ($reach[15].Races -join ',') '' 'R6: nobody can earn a locked faction'
Check (-not $reach[15].Everyone) 'R6: and it isn''t everyone''s'
Check (-not $reach[16].Shown) 'R7: a hidden slot shows no bar'
Check (-not $reach[67].Shown) 'R7: nor does a header without its own'
Check $reach[18].Shown 'R7: a header with its own bar does'
Equal ($reach[20].Races -join ',') '1,3,31,40' 'R8: a race no slot names gets none'

$noRaces = Get-FactionReach $factions @()
Check ($noRaces[11].Everyone -and $noRaces[11].Shown) 'N1: with no race table, an open slot anywhere makes it shown'
Check (-not $noRaces[67].Shown) 'N1: and a bar-less header still isn''t'

$records = @(Get-FactionReachRecords $reach)
Equal (@($records | ForEach-Object { $_.faction }) -join ',') '11,12,13,15,16,20,67' 'G1: the records: a faction some race can''t earn or never shown, in ID order'
Equal (($records | Where-Object { $_.faction -eq 16 }).PSObject.Properties.Name -join ',') 'faction,hidden' 'G1: a hidden one everyone can earn has no race list'

$json = ConvertTo-FactionJsonLines @($records | Where-Object { $_.faction -in 11, 15, 67 })
Equal $json ('{"faction":11,"races":[2,24,27]}' + "`n" + '{"faction":15,"races":[],"hidden":true}' + "`n" + '{"faction":67,"hidden":true}' + "`n") 'J1: the data file (one nobody can earn shows no bar either)'
$problems = @(Test-FactionRecords @([pscustomobject]@{ faction = 0 }, [pscustomobject]@{ faction = 5; races = @(1) }, [pscustomobject]@{ faction = 5; races = @(1) },
    [pscustomobject]@{ faction = 6; races = @('x') }, [pscustomobject]@{ faction = 7; hidden = 'yes' }, [pscustomobject]@{ faction = 8 }))
Check (@($problems | Where-Object { $_ -match "'faction' must" }).Count -eq 1) 'T1: a faction of 0 is a problem'
Check (@($problems | Where-Object { $_ -match 'also on line 2' }).Count -eq 1) 'T1: so is one listed twice'
Check (@($problems | Where-Object { $_ -match "'races' must" }).Count -eq 1) 'T1: and a race that isn''t an ID'
Check (@($problems | Where-Object { $_ -match "'hidden' is true" }).Count -eq 1) 'T1: and a hidden that isn''t true'
Check (@($problems | Where-Object { $_ -match 'every race can earn and see' }).Count -eq 1) 'T1: and one with nothing to say'
Equal @(Test-FactionRecords $records).Count 0 'T1: sound records have none'
$lua = ConvertTo-LuaFactionTables $records
Check ($lua.Contains("qcFactionRaces={`r`n[11]={[2]=1,[24]=1,[27]=1},`r`n")) 'L1: a race set per faction'
Check ($lua.Contains("[15]={},`r`n")) 'L1: an empty set for one nobody can earn'
Check ($lua.Contains("qcFactionHidden={`r`n[15]=1,`r`n[16]=1,`r`n[67]=1,`r`n}`r`n")) 'L1: the hidden ones'
Equal (ConvertTo-LuaFactionTables @()) "qcFactionRaces={`r`n}`r`nqcFactionHidden={`r`n}`r`n" 'L2: with none, both tables are empty'

$root = Join-Path ([IO.Path]::GetTempPath()) ("faction_reach_test_" + [guid]::NewGuid().ToString('N'))
$data = Join-Path $root 'data'; $addon = Join-Path $root 'addon'
New-Item -ItemType Directory -Force $data, $addon | Out-Null
try {
    [IO.File]::WriteAllText((Join-Path $data 'quests.jsonl'), '{"id":100,"name":"Quest 100","level":30,"zone":"","category":1,"type":1,"faction":1,"race":64175181,"class":8191}' + "`n")
    [IO.File]::WriteAllText((Join-Path $data 'pins.jsonl'), '{"map":1,"icon":1,"x":1,"y":1,"quests":[100]}' + "`n")
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    Check ($build.Ok -and [IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua')).Contains("qcFactionRaces={`r`n}`r`nqcFactionHidden={`r`n}`r`n")) 'B1: a data folder with no factions builds, with empty tables'
    [IO.File]::WriteAllText((Join-Path $data 'factions.jsonl'), (ConvertTo-FactionJsonLines $records))
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    Check ($build.Ok -and [IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua')).Contains('[13]={[1]=1,[2]=1,[3]=1,[24]=1,[31]=1,[40]=1},')) 'B2: the factions are written'
    Check (@($build.Lines | Where-Object { $_ -match '7 factions' }).Count -eq 1) 'B2: and counted'
    Check (Invoke-AddonDataBuild -DataDir $data -AddonDir $addon -Check).Ok 'B3: a second build changes nothing'
    [IO.File]::WriteAllText((Join-Path $data 'factions.jsonl'), '{"faction":11,"races":[2],"side":2}' + "`n")
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    Check (-not $build.Ok -and @($build.Lines | Where-Object { $_ -match "unknown field 'side'" }).Count -eq 1) 'B4: an unknown field stops the build'
}
finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output "$Passed checks passed, $Failed failed."
if ($Failed -gt 0) { exit 1 }
