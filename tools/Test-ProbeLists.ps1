<#
Checks Build-ProbeLists.ps1 on small data made in a scratch folder: nothing in the checkout is written and
nothing is downloaded. For retail it checks which quests and NPCs the lists hold and in which order; for
Forever, with a made-up QuestV2 table and CMaNGOS dump, that the quests are the two tables' union and the
NPCs the givers of those quests plus the pins'; and that every list loads as Lua and the builder refuses
what it should.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ProbeLists.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param(
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)
$ErrorActionPreference = 'Stop'
$Builder = Join-Path $PSScriptRoot 'ForeverProbe\Build-ProbeLists.ps1'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("probe-lists-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null

function New-World([string]$name) {
    $root = Join-Path $Scratch $name
    foreach ($dir in 'tools', 'data\forever', 'addon') { New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null }
    return @{ Root = $root; Tools = "$root\tools"; Data = "$root\data"; Addon = "$root\addon" }
}

# 1,200 quests: ids 1000..2199, every 7th typed daily (4), every 11th repeatable (2), every 13th 128, a few typed 1,
# one id listed twice. Pins: NPCs 300..449 (some twice), some pins with no NPC.
function Write-RetailData($w) {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($id in 1000..2199) {
        $type = 1
        if ($id % 13 -eq 0) { $type = 128 } elseif ($id % 11 -eq 0) { $type = 2 } elseif ($id % 7 -eq 0) { $type = 4 }
        $lines.Add('{"id":' + $id + ',"name":"Q' + $id + '","level":10,"zone":"","category":10,"type":' + $type + ',"faction":2,"race":67108863,"class":8191}')
    }
    $lines.Add('{"id":1000,"name":"Again","level":10,"zone":"","category":10,"type":1,"faction":2,"race":67108863,"class":8191}')
    [IO.File]::WriteAllText("$($w.Data)\quests.jsonl", (($lines -join "`n") + "`n"))
    $pins = New-Object System.Collections.Generic.List[string]
    foreach ($npc in 449..300) { $pins.Add('{"map":1,"icon":1,"npc":' + $npc + ',"name":"N' + $npc + '","x":50,"y":50,"quests":[1000]}') }
    foreach ($npc in 300..320) { $pins.Add('{"map":2,"icon":1,"npc":' + $npc + ',"name":"N' + $npc + '","x":10,"y":10,"quests":[1001]}') }
    $pins.Add('{"map":3,"icon":1,"name":"No NPC","x":10,"y":10,"quests":[1002]}')
    $pins.Add('{"map":3,"icon":3,"npc":0,"name":"Zero","x":10,"y":10,"quests":[1003]}')
    [IO.File]::WriteAllText("$($w.Data)\pins.jsonl", (($pins -join "`n") + "`n"))
}

function Read-List([string]$path, [string]$variable) {
    $script = "local probe = {}; assert(loadfile([[$path]]))('QCForeverProbe', probe); local list = probe.$variable; io.write(tostring(probe.questBuild), '|', #list, '|', table.concat(list, ','))"
    $out = & $LuaExe -e $script
    $parts = ($out -join '') -split '\|', 3
    return @{ Build = $parts[0]; Count = [int]$parts[1]; Ids = @($parts[2] -split ',' | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
}

function Run-Builder([hashtable]$w, [string[]]$more) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Builder, '-ToolsDir', $w.Tools, '-DataDir', $w.Data, '-AddonDir', $w.Addon, '-LuaExe', $LuaExe) + $more
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = @(& powershell @arguments 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $saved }
    return @{ Text = ($output -join "`n"); Exit = $LASTEXITCODE }
}

try {
    # --- retail ----------------------------------------------------------------------------------
    $w = New-World 'retail'
    Write-RetailData $w
    $r = Run-Builder $w @('-Game', 'retail', '-Build', '12.1.0.69933')
    Equal $r.Exit 0 'T1: the retail run exits 0'
    Check ($r.Text -match '1200 quests \(\d+ typed daily, repeatable or 128 first, \d+ others\); 150 NPCs from the pins') "T1: and says what it wrote ($($r.Text))"
    Check ((Test-Path "$($w.Addon)\QuestIDs_Retail.lua") -and (Test-Path "$($w.Addon)\NpcIDs_Retail.lua")) 'T1: the two retail lists are written'
    Check (-not (Test-Path "$($w.Addon)\QuestIDs_Forever.lua")) 'T1: and no Forever list'
    $q = Read-List "$($w.Addon)\QuestIDs_Retail.lua" 'questIds'
    Equal $q.Build '12.1.0.69933' 'T1: the quest list carries the build'
    Equal $q.Count 1200 'T1: every quest once, though one is listed twice'
    Equal @($q.Ids | Sort-Object -Unique).Count 1200 'T1: and none twice'
    $recurring = @(1000..2199 | Where-Object { $_ % 13 -eq 0 -or $_ % 11 -eq 0 -or $_ % 7 -eq 0 })
    $others = @(1000..2199 | Where-Object { -not ($_ % 13 -eq 0 -or $_ % 11 -eq 0 -or $_ % 7 -eq 0) })
    Equal (($q.Ids[0..($recurring.Count - 1)]) -join ',') (($recurring | Sort-Object) -join ',') 'T1: the daily, repeatable and 128 quests come first, in order'
    Equal (($q.Ids[$recurring.Count..($q.Ids.Count - 1)]) -join ',') (($others | Sort-Object) -join ',') 'T1: then the rest, in order'
    $n = Read-List "$($w.Addon)\NpcIDs_Retail.lua" 'npcIds'
    Equal $n.Count 150 'T1: the NPCs, once each (300 to 449; the pins of 300 to 320 repeat them, and a pin with none or 0 adds nothing)'
    Equal ($n.Ids -join ',') ((300..449) -join ',') 'T1: sorted'

    $r = Run-Builder $w @('-Game', 'retail', '-Build', '12.1.0')
    Check ($r.Exit -ne 0 -and $r.Text -match 'is not a build number') 'T2: a build that is not a build number is refused'
    $r = Run-Builder $w @('-Game', 'classic', '-Build', '12.1.0.69933')
    Check ($r.Exit -ne 0) 'T2: so is a game that is not retail or forever'
    $r = Run-Builder $w @('-Game', 'retail')
    Check ($r.Exit -ne 0) 'T2: and a run with no build'
    [IO.File]::WriteAllText("$($w.Data)\quests.jsonl", "{`"id`":1,`"type`":1}`n")
    $r = Run-Builder $w @('-Game', 'retail', '-Build', '12.1.0.69933')
    Check ($r.Exit -ne 0 -and $r.Text -match 'has only 1 quests') 'T2: a quest file with almost nothing in it is refused'
    Write-RetailData $w
    [IO.File]::WriteAllText("$($w.Data)\pins.jsonl", "{`"map`":1,`"npc`":5}`n")
    $r = Run-Builder $w @('-Game', 'retail', '-Build', '12.1.0.69933')
    Check ($r.Exit -ne 0 -and $r.Text -match 'has only 1 NPCs') 'T2: and a pin file with almost nothing in it'
    Write-RetailData $w
    $lines = [IO.File]::ReadAllLines("$($w.Data)\quests.jsonl")
    [IO.File]::WriteAllLines("$($w.Data)\quests.jsonl", [string[]]($lines + '{"name":"no id"}'))
    $r = Run-Builder $w @('-Game', 'retail', '-Build', '12.1.0.69933')
    Check ($r.Exit -ne 0 -and $r.Text -match 'has no quest ID') 'T2: a quest line with no ID is refused'

    # --- forever ---------------------------------------------------------------------------------
    $w = New-World 'forever'
    Write-RetailData $w
    $v2 = New-Object System.Collections.Generic.List[string]
    $v2.Add('ID')
    foreach ($id in 1..1100) { $v2.Add("$id") }
    [IO.File]::WriteAllLines("$($w.Tools)\QuestV2-1.60.1.70245.csv", [string[]]$v2)
    $fp = New-Object System.Collections.Generic.List[string]
    foreach ($npc in 9000..9004) { $fp.Add('{"map":1411,"icon":1,"npc":' + $npc + ',"name":"F' + $npc + '","x":50,"y":50,"quests":[1]}') }
    $fp.Add('{"map":1411,"icon":1,"name":"No NPC","x":50,"y":50,"quests":[2]}')
    [IO.File]::WriteAllText("$($w.Data)\forever\pins.jsonl", (($fp -join "`n") + "`n"))
    $sql = @(
        '-- dump',
        'INSERT INTO `creature_questrelation` VALUES (500,5),(501,1101),(502,1500),(503,9),(500,6);',
        'INSERT INTO `quest_template` VALUES (5,''a''),(1101,''b''),(1102,''c''),(1,''d'');'
    ) -join "`n"
    $gzPath = "$($w.Tools)\ClassicDB_test.sql.gz"
    $file = [IO.File]::Create($gzPath)
    $gz = New-Object System.IO.Compression.GZipStream($file, [System.IO.Compression.CompressionMode]::Compress)
    $bytes = [Text.Encoding]::UTF8.GetBytes($sql + "`n")
    $gz.Write($bytes, 0, $bytes.Length)
    $gz.Close(); $file.Close()
    $r = Run-Builder $w @('-Game', 'forever', '-Build', '1.60.1.70245')
    Equal $r.Exit 0 'T3: the Forever run exits 0'
    Check ($r.Text -match '1102 quests: 1100 in QuestV2 \(build 1.60.1.70245\) and 2 CMaNGOS quests it lacks; 8 NPCs: 3 CMaNGOS givers, 5 more from our pins') "T3: and says what it wrote ($($r.Text))"
    Check ((Test-Path "$($w.Addon)\QuestIDs_Forever.lua") -and (Test-Path "$($w.Addon)\NpcIDs_Forever.lua")) 'T3: the two Forever lists are written'
    Check (-not (Test-Path "$($w.Addon)\QuestIDs_Retail.lua")) 'T3: and no retail list'
    $q = Read-List "$($w.Addon)\QuestIDs_Forever.lua" 'questIds'
    Equal $q.Build '1.60.1.70245' 'T3: the quest list carries the build'
    Equal $q.Count 1102 'T3: QuestV2 and the CMaNGOS quests it lacks (1101 and 1102)'
    Equal ($q.Ids[1099..1101] -join ',') '1100,1101,1102' 'T3: in order'
    $n = Read-List "$($w.Addon)\NpcIDs_Forever.lua" 'npcIds'
    Equal ($n.Ids -join ',') '500,501,503,9000,9001,9002,9003,9004' 'T3: the givers of listed quests (the one for quest 1500, which neither table has, is left out) and the NPCs on Forever pins'
}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
