<#
Checks StartItems.ps1 and the start items of AddonData.ps1 (Sync-QuestStartItems.ps1, step 6e) on a made-up ItemSparse,
ChrRaces and data folder in a temporary folder: nothing in the checkout is touched and nothing is downloaded. It checks
which items are kept (those that start a quest of ours), each item's faction flag, level, profession, reputation and
races (races that are exactly one side's become that side; races of neither side don't count), the quests whose
faction their items contradict (not when an item is for either side, nor when the quest has an item per side), the
data file's and the Lua's form (a trailing 0 left off), the checks of the data file, and the build leaving out an
item whose quest has left the data.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncQuestStartItems.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
. (Join-Path $PSScriptRoot 'StartItems.ps1')
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

# Races: 1 and 3 Alliance (bits 0 and 2), 2 and 5 Horde (bits 1 and 4), 24 neither (bit 5), 99 no player's (NPC only).
$races = @(
    [pscustomobject]@{ ID = '1'; Flags = '0'; PlayableRaceBit = '0'; Alliance = '0' },
    [pscustomobject]@{ ID = '2'; Flags = '0'; PlayableRaceBit = '1'; Alliance = '1' },
    [pscustomobject]@{ ID = '3'; Flags = '0'; PlayableRaceBit = '2'; Alliance = '0' },
    [pscustomobject]@{ ID = '5'; Flags = '0'; PlayableRaceBit = '4'; Alliance = '1' },
    [pscustomobject]@{ ID = '24'; Flags = '0'; PlayableRaceBit = '5'; Alliance = '2' },
    [pscustomobject]@{ ID = '99'; Flags = '1'; PlayableRaceBit = '6'; Alliance = '0' })
function Item($id, $quest, $flags = 0, $level = 0, $skill = 0, $rank = 0, $rep = 0, $standing = 0, $low = -1, $high = -1) {
    return [pscustomobject]@{ ID = "$id"; StartQuestID = "$quest"; Flags_1 = "$flags"; RequiredLevel = "$level"; RequiredSkill = "$skill"
        RequiredSkillRank = "$rank"; MinFactionID = "$rep"; MinReputation = "$standing"; AllowableRaces_0 = "$low"; AllowableRaces_1 = "$high" }
}
$items = @(
    (Item 10 100 0 1),                  # any side, level 1: nothing to say
    (Item 11 101 2 30),                 # Alliance only, level 30
    (Item 12 102 1 0 197 75),           # Horde only, Tailoring 75
    (Item 13 103 0 0 0 0 1015 3),       # Netherwing, Neutral
    (Item 14 104 0 0 0 0 0 0 5 0),      # races 1 and 3: the Alliance's
    (Item 15 105 0 0 0 0 0 0 37 0),     # races 1, 3 and 24: the Alliance's and one of neither side
    (Item 16 106 0 0 0 0 0 0 3 0),      # races 1 and 2: one of each side
    (Item 17 107 2),                    # an item for each side of one quest
    (Item 18 107 1),
    (Item 19 108 2),                    # one Alliance item and one for either side
    (Item 20 108 0),
    (Item 21 999 2),                    # a quest we don't have
    (Item 22 0 2),                      # starts nothing
    (Item 23 109 0 0 0 0 0 0 0 0))      # races 0: every race
$quests = @{}
foreach ($q in @(@(100, 3), @(101, 3), @(102, 2), @(103, 3), @(104, 3), @(105, 3), @(106, 3), @(107, 3), @(108, 1), @(109, 3))) {
    $quests[$q[0]] = [pscustomobject]@{ id = $q[0]; name = "Quest $($q[0])"; faction = $q[1] }
}

$records = Get-StartItemRecords $items $races $quests
$by = @{}; foreach ($r in $records) { $by[$r.item] = $r }
Equal (@($records | ForEach-Object { $_.item }) -join ',') '10,11,12,13,14,15,16,17,18,19,20,23' 'R1: the items that start our quests, in order'
Check ($null -eq $by[10].level -and $null -eq $by[10].side) 'R2: level 1 and no flag say nothing'
Equal $by[11].side 1 'R2: flag 0x2 is the Alliance'
Equal $by[11].level 30 'R2: with its level'
Equal $by[12].side 2 'R2: flag 0x1 is the Horde'
Equal "$($by[12].skill)/$($by[12].skillRank)" '197/75' 'R2: and its profession and skill'
Equal "$($by[13].rep)/$($by[13].repRank)" '1015/3' 'R2: a reputation and its standing'
Check ($by[14].side -eq 1 -and $null -eq $by[14].races) 'R3: races that are the Alliance''s make the item the Alliance''s'
Check ($by[15].side -eq 1 -and $null -eq $by[15].races) 'R3: a race of neither side doesn''t change that'
Equal (@($by[16].races) -join ',') '1,2' 'R3: races of both sides stay a list'
Check ($null -eq $by[16].side) 'R3: and give no side'
Check ($null -eq $by[23].races) 'R3: a mask of 0 is every race'

$disagree = Get-StartItemFactionDisagreements $records $quests
Equal (@($disagree | ForEach-Object { "$($_.Quest):$($_.Faction)>$($_.ItemSide)" }) -join ' ') '101:3>1 104:3>1 105:3>1' 'F1: the quests for both whose one item is the Alliance''s, by flag or by races'
Check (@($disagree | Where-Object Quest -eq 107).Count -eq 0) 'F1: an item for each side says nothing'
Check (@($disagree | Where-Object Quest -eq 108).Count -eq 0) 'F1: nor does an item for either side beside an Alliance one'
Check (@($disagree | Where-Object Quest -eq 102).Count -eq 0) 'F1: nor a Horde item for a Horde quest'

$json = ConvertTo-StartItemJsonLines @($by[11], $by[13], $by[16])
Equal $json ('{"item":11,"quest":101,"side":1,"level":30}' + "`n" + '{"item":13,"quest":103,"rep":1015,"repRank":3}' + "`n" + '{"item":16,"quest":106,"races":[1,2]}' + "`n") 'J1: the data file leaves out what is empty'
$lua = ConvertTo-LuaStartItemTable @($by[17], $by[18], $by[10], $by[13], $by[16])
Check ($lua.Contains("[100]={{10}},`r`n")) 'L1: a trailing 0 is left off'
Check ($lua.Contains("[103]={{13,0,0,0,0,1015,3}},`r`n")) 'L1: a reputation keeps the fields before it'
Check ($lua.Contains("[106]={{16,0,0,0,0,0,0,{1,2}}},`r`n")) 'L1: races come last, as a table'
Check ($lua.Contains("[107]={{17,1},{18,2}},`r`n")) 'L1: a quest''s items go together, in item order'
Check ($lua.StartsWith("qcQuestStartItems={`r`n") -and $lua.EndsWith("}`r`n")) 'L1: the table is named and closed'

$bad = @([pscustomobject]@{ item = 5; quest = 1; side = 3 }, [pscustomobject]@{ item = 5; quest = 1 }, [pscustomobject]@{ item = 6; quest = 0 }, [pscustomobject]@{ item = 7; quest = 1; races = @() })
$problems = @(Test-StartItemRecords $bad)
Check (@($problems | Where-Object { $_ -match "'side' is 1" }).Count -eq 1) 'T1: a side other than 1 or 2 is a problem'
Check (@($problems | Where-Object { $_ -match 'also on line 1' }).Count -eq 1) 'T1: so is an item listed twice'
Check (@($problems | Where-Object { $_ -match "'quest' must be" }).Count -eq 1) 'T1: and a quest of 0'
Check (@($problems | Where-Object { $_ -match "'races' must" }).Count -eq 1) 'T1: and an empty race list'
Equal @(Test-StartItemRecords @($by[11], $by[16])).Count 0 'T1: sound items have none'

$root = Join-Path ([IO.Path]::GetTempPath()) ("start_items_test_" + [guid]::NewGuid().ToString('N'))
$data = Join-Path $root 'data'; $addon = Join-Path $root 'addon'
New-Item -ItemType Directory -Force $data, $addon | Out-Null
try {
    [IO.File]::WriteAllText((Join-Path $data 'quests.jsonl'), '{"id":101,"name":"Quest 101","level":30,"zone":"","category":1,"type":1,"faction":1,"race":64175181,"class":8191}' + "`n")
    [IO.File]::WriteAllText((Join-Path $data 'pins.jsonl'), '{"map":1,"icon":1,"x":1,"y":1,"quests":[101]}' + "`n")
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    Check $build.Ok 'B1: a data folder with no start items builds'
    Check ([IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua')).Contains("qcQuestStartItems={`r`n}`r`n")) 'B1: with an empty table'
    [IO.File]::WriteAllText((Join-Path $data 'startitems.jsonl'), (ConvertTo-StartItemJsonLines @($by[11], $by[12])))
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    $text = [IO.File]::ReadAllText((Join-Path $addon 'qcQuestData.lua'))
    Check ($build.Ok -and $text.Contains("[101]={{11,1,30}},")) 'B2: an item of a quest in the data is written'
    Check (-not $text.Contains('[102]=')) 'B2: one whose quest has left the data is left out'
    Check (@($build.Lines | Where-Object { $_ -match '2 start items' }).Count -eq 1) 'B2: the count says what the file holds'
    Check (Invoke-AddonDataBuild -DataDir $data -AddonDir $addon -Check).Ok 'B3: a second build changes nothing'
    [IO.File]::WriteAllText((Join-Path $data 'startitems.jsonl'), '{"item":11,"quest":101,"colour":3}' + "`n")
    $build = Invoke-AddonDataBuild -DataDir $data -AddonDir $addon
    Check (-not $build.Ok -and @($build.Lines | Where-Object { $_ -match "unknown field 'colour'" }).Count -eq 1) 'B4: an unknown field stops the build'
}
finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output "$Passed checks passed, $Failed failed."
if ($Failed -gt 0) { exit 1 }
