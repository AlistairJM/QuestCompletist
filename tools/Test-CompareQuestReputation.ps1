<#
Checks the cache pass of Compare-QuestReputation.ps1 on quests, API records, a quest cache, a Faction
table and a qcQuest.lua made here, in a scratch folder: nothing in the checkout is read or written
(only that the baseline file the script defaults to is there) and nothing is downloaded. One world holds a quest for each way ours, the API's and the cache's rewards can
agree or not (class A to H), with the factions in different orders, a faction listed twice and slots
with an amount of 0; the rest changes one thing at a time: the Faction table's flags, the builds, the
baseline file, the files that are missing, and what the run exits with. It also runs
Apply-ReputationBackfill.ps1 on the CSV, to check that it leaves the cache pass's rows alone.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-CompareQuestReputation.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
$savedCulture = [Threading.Thread]::CurrentThread.CurrentCulture
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$Tool = Join-Path $PSScriptRoot 'Compare-QuestReputation.ps1'
$Apply = Join-Path $PSScriptRoot 'Apply-ReputationBackfill.ps1'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Has([string]$text, [string]$part, [string]$message) {
    Check ($text.Contains($part)) "$message (no '$part' in: $text)"
}
function HasLine([string]$text, [string]$part, [string]$message) {
    Check (("`n" + $text).Contains("`n" + $part)) "$message (no line starting '$part' in: $text)"
}
function Lacks([string]$text, [string]$part, [string]$message) {
    Check (-not $text.Contains($part)) "$message ('$part' is in: $text)"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("compare-quest-reputation-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$Build = '12.1.0.69933'

function Get-Pairs([string]$text) {
    $out = @()
    foreach ($part in ($text -split '\s+' | Where-Object { $_ })) { $faction, $amount = $part -split '='; $out += , @([int]$faction, [int]$amount) }
    return , $out
}

function New-ApiRecord([int]$id, [string]$reps, [string]$namespace) {
    $json = '{"_links":{"self":{"href":"https://us.api.blizzard.com/data/wow/quest/' + $id + '?namespace=static-' + $namespace + '-us"}},"id":' + $id + ',"title":"Quest ' + $id + '"'
    $json += ',"requirements":{"reputations":[{"faction":{"key":{"href":"https://us.api.blizzard.com/data/wow/reputation-faction/9?namespace=x"},"name":"Needed","id":9},"max_reputation":-1}]}'
    $rewards = '"experience":100'
    $list = @()
    foreach ($pair in (Get-Pairs $reps)) { $list += '{"reward":{"key":{"href":"https://us.api.blizzard.com/data/wow/reputation-faction/' + $pair[0] + '?namespace=static-' + $namespace + '-us"},"name":"Faction \"' + $pair[0] + '\"","id":' + $pair[0] + '},"value":' + $pair[1] + '}' }
    if ($list) { $rewards += ',"reputations":[' + ($list -join ',') + ']' }
    $rewards += ',"currency":[{"reward":{"key":{"href":"https://us.api.blizzard.com/data/wow/currency/515?namespace=static-' + $namespace + '-us"},"name":"Ticket","id":515},"value":5}]'
    return $json + ',"rewards":{' + $rewards + '}}'
}

$FactionRows = @(
    @(76, 'Orgrimmar', 10, 2), @(72, 'Stormwind', 11, 0), @(80, 'Eighty', 12, 16), @(81, 'Eighty-one', 13, 8),
    @(82, 'Eighty-two', 14, 1), @(56, 'Fifty-six', 0, 0), @(9, 'Nine', 15, 0), @(100, 'Hundred', 16, 0),
    @(98, 'Hidden six', 21, 6), @(99, 'Hidden four', 20, 4), @(97, 'Hidden twenty', 22, 20), @(55, 'No slot', -1, 0))

function New-Quest([string]$ours, $api, $cache, [hashtable]$more = @{}) {
    $quest = @{ Ours = $ours; Api = $api; Cache = $cache; InData = $true }
    foreach ($key in $more.Keys) { $quest[$key] = $more[$key] }
    return $quest
}

function New-World {
    $q = @{}
    $q[1] = New-Quest '76=250' '76=250' '76=250'
    $q[2] = New-Quest '76=250 72=-25' '72=-25 76=250' '72=-25 76=250'
    $q[3] = New-Quest '' '76=250' '76=250'
    $q[4] = New-Quest '76=250' $null '76=250'
    $q[5] = New-Quest '76=250' '' '76=250'
    $q[6] = New-Quest '76=250' $null '76=100 76=150'
    $q[7] = New-Quest '76=250' $null '76=250 72=0'
    $q[8] = New-Quest '72=-25' $null '72=-25'
    $q[9] = New-Quest '' $null ''
    $q[10] = New-Quest '' $null '76=0'
    $q[11] = New-Quest '76=250' '76=250' '76=250 99=10'
    $q[12] = New-Quest '76=250' $null '76=250 98=5'
    $q[13] = New-Quest '' '76=250' '76=250 88=5'
    $q[14] = New-Quest '76=250' '76=250' '76=250 55=5'
    $q[15] = New-Quest '76=250' '76=250' '76=200'
    $q[16] = New-Quest '76=250' '76=250' '72=250'
    $q[17] = New-Quest '76=100' '76=250' '76=250'
    $q[18] = New-Quest '76=250' '76=100' '76=250'
    $q[19] = New-Quest '76=250' '76=250' '76=250 72=5'
    $q[20] = New-Quest '76=250 72=-25' '76=250 72=-25' '76=250'
    $q[21] = New-Quest '72=-25' '72=-25' '72=25'
    $q[22] = New-Quest '76=250' $null '76=200'
    $q[23] = New-Quest '76=250' '' '76=250 72=5'
    $q[24] = New-Quest '76=250' $null ''
    $q[25] = New-Quest '' '76=250' ''
    $q[26] = New-Quest '76=100' '76=250' ''
    $q[27] = New-Quest '76=250' '76=250' '76=0'
    $q[28] = New-Quest '' $null '76=250'
    $q[29] = New-Quest '' '' '72=5'
    $q[30] = New-Quest '' 'unasked' '80=5'
    $q[31] = New-Quest '' $null '76=5 99=10'
    $q[32] = New-Quest '' $null '81=5'
    $q[33] = New-Quest '' $null '99=5'
    $q[34] = New-Quest '' $null '88=5'
    $q[35] = New-Quest '' $null '55=5'
    $q[36] = New-Quest '' $null '98=5 99=5'
    $q[37] = New-Quest '76=250' $null $null
    $q[38] = New-Quest '' $null $null
    $q[39] = New-Quest '' $null '76=5' @{ InData = $false }
    $q[40] = New-Quest '' $null '' @{ InData = $false }
    $q[41] = New-Quest '' $null '76=5'
    $q[42] = New-Quest '' $null '72=5'
    $q[43] = New-Quest '' $null '80=5'
    $q[44] = New-Quest '' $null '81=5'
    $q[45] = New-Quest '' $null '82=5'
    $q[46] = New-Quest '' $null '56=5'
    $q[47] = New-Quest '' $null '98=5'
    $q[48] = New-Quest '' $null '99=5'
    $q[49] = New-Quest '' $null '97=5'
    $q[50] = New-Quest '' $null '55=5'
    $q[51] = New-Quest '' $null '88=5'
    $q[52] = New-Quest '' $null '9=5'
    $q[53] = New-Quest '' $null '100=5'
    return $q
}

function Write-World([string]$name, $quests, [hashtable]$options = @{}) {
    $dir = Join-Path $Scratch $name
    New-Item -ItemType Directory "$dir\quest_api_cache", "$dir\data" -Force | Out-Null
    $namespace = if ($options.Namespace) { $options.Namespace } else { '12.1.0_68914' }
    $data = @(); $cache = @(); $lua = @()
    foreach ($id in ($quests.Keys | Sort-Object)) {
        $q = $quests[$id]
        if ($q.InData) {
            $data += '{"id":' + $id + ',"name":"Quest ' + $id + '","level":1,"zone":"","category":1,"type":1,"faction":0,"race":0,"class":0}'
            $oursPairs = Get-Pairs $q.Ours
            if ($oursPairs.Count) { $lua += "`t[$id]={" + (($oursPairs | ForEach-Object { "[$($_[0])]=$($_[1])" }) -join ',') + '},' }
            if ($q.Api -eq 'unasked') { }
            elseif ($null -eq $q.Api) { [IO.File]::WriteAllText("$dir\quest_api_cache\$id.404", '', $utf8) }
            else { [IO.File]::WriteAllText("$dir\quest_api_cache\$id.json", (New-ApiRecord $id $q.Api $namespace), $utf8) }
        }
        if ($null -ne $q.Cache) {
            $line = '{"id":' + $id + ',"title":"Quest ' + $id + '","contentTuning":1,"sort":0,"questType":2'
            $pairs = Get-Pairs $q.Cache
            if ($pairs.Count) { $line += ',"reputation":[' + (($pairs | ForEach-Object { "[$($_[0]),$($_[1])]" }) -join ',') + ']' }
            $cache += $line + '}'
        }
    }
    [IO.File]::WriteAllText("$dir\data\quests.jsonl", (($data -join "`n") + "`n"), $utf8)
    [IO.File]::WriteAllText("$dir\qcQuest.lua", ((@('qcFactions = {', '    [76] = "Orgrimmar", ', '    [72] = "Stormwind", ', '    [80] = "Eighty", ', '}', '', 'qcQuestReputation = {  -- QuestId -> {[FactionId]=RepValue}', '') + $lua + @('}', '')) -join "`r`n"), $utf8)
    if (-not $options.NoCache) { [IO.File]::WriteAllText("$dir\retail_quest_cache_$Build.jsonl", (($cache -join "`n") + "`n"), $utf8) }
    if (-not $options.NoFaction) {
        $table = @('ID,Name_lang,ReputationIndex,ReputationFlags_0') + @($FactionRows | ForEach-Object { "$($_[0]),$($_[1]),$($_[2]),$($_[3])" })
        [IO.File]::WriteAllText("$dir\Faction-$Build.csv", (($table -join "`r`n") + "`r`n"), $utf8)
    }
    return $dir
}

function Invoke-Tool([string]$dir, [hashtable]$more = @{}) {
    $params = @{ ToolsDir = $dir; DataDir = "$dir\data"; QuestFile = "$dir\qcQuest.lua"; BaselineFile = "$dir\baseline.csv" }
    foreach ($k in $more.Keys) { $params[$k] = $more[$k] }
    $global:LASTEXITCODE = 0
    $failure = ''
    $lines = @()
    $cacheFailed = $true; $baseline = @{ B = $null }; $aApiOnly = 5; $notInCacheWithReward = 5; $apiRewards = 5; $apiReproduced = 5
    try { $lines = @(& $Tool @params) } catch { $failure = $_.Exception.Message }
    if ($env:QUEST_REPUTATION_TEST_VERBOSE) { Write-Host "---- run (exit $global:LASTEXITCODE) $failure"; $lines | ForEach-Object { Write-Host "     $_" } }
    return @{ Text = ($lines -join "`n"); Exit = $global:LASTEXITCODE; Failure = $failure }
}

function Read-Rows([string]$dir) {
    $rows = @{}
    foreach ($row in (Import-Csv "$dir\quest_reputation_compare.csv")) {
        if (-not $rows.ContainsKey($row.QuestID)) { $rows[$row.QuestID] = @() }
        $rows[$row.QuestID] += $row.Kind
    }
    return $rows
}

try {
    # --- Every class, in one world -----------------------------------------------------------------
    $dir = Write-World 'main' (New-World)
    $r = Invoke-Tool $dir
    Equal $r.Failure '' 'W1: the run does not throw'
    Equal $r.Exit 1 'W1: a world with differing and lost rewards fails the run'
    HasLine $r.Text 'Cache pass: retail_quest_cache_12.1.0.69933.jsonl holds 51 quests, 49 of our 51. Faction table Faction-12.1.0.69933.csv: 12 factions, 8 shown.' 'W1: the header counts the cache, the quests of ours in it, and the shown factions'
    HasLine $r.Text 'Builds: API 12.1.0_68914, cache 12.1.0.69933, Faction table 12.1.0.69933.' 'W1: the three builds are printed'
    HasLine $r.Text 'WARNING: the builds differ' 'W1: and a warning says they differ'
    HasLine $r.Text '  A agree: 8 (of which ours lists none, the API and the cache agree: 1)' 'W2: A counts the quests whose sets are equal, whatever the order, a faction in two slots, an empty slot, a loss'
    HasLine $r.Text '  B cache adds rewards on factions that are not shown: 4' 'W2: B is extra rewards on hidden, absent and no-slot factions'
    HasLine $r.Text '  C DIFFER: 9' 'W2: C'
    HasLine $r.Text '  D LOST: 4' 'W2: D'
    HasLine $r.Text '  E cache only, on a shown faction (backfill candidates): 13 quests, 13 rewards; API: no record 11, a record listing none 1, not asked 1' 'W2: E, with its rewards on shown factions and what the API says'
    HasLine $r.Text '  F cache only, on factions that are not shown: 9' 'W2: F'
    HasLine $r.Text '  G not in the cache: 2 (1 with a reward row of ours)' 'W2: G'
    HasLine $r.Text '  H only in the cache: 2 quests (1 with a reward); 3 empty-amount slots; 1 factions in two slots of one quest' 'W2: H'
    HasLine $r.Text '  Nothing listed anywhere: 2' 'W2: and the quests with nothing anywhere'
    HasLine $r.Text '  API rewards the cache reproduces: 10 of 18' 'W2: the API rewards the cache has with the same amount'
    HasLine $r.Text '  E rewards on a faction missing from qcFactions: [9] Nine, 1' 'W3: a shown faction of E that qcFactions lacks is named, in numeric order'
    HasLine $r.Text "  E rewards on a faction missing from qcFactions: [56] Fifty-six, 1`n  E rewards on a faction missing from qcFactions: [81] Eighty-one, 2`n  E rewards on a faction missing from qcFactions: [82] Eighty-two, 1`n  E rewards on a faction missing from qcFactions: [100] Hundred, 1" 'W3: with the number of rewards each'
    Lacks $r.Text 'missing from qcFactions: [76]' 'W3: a faction qcFactions has is not named'
    Lacks $r.Text 'missing from qcFactions: [99]' 'W3: nor a hidden one'
    HasLine $r.Text 'FAILED: 9 quests have a reward that differs and 4 lost theirs in the cache (Kinds cache-differ and cache-lost in the CSV).' 'W4: the failure names both counts'
    Lacks $r.Text 'looks moved' 'W4: and does not say the reader moved'
    HasLine $r.Text 'Quests the API 404s on (no reputation source): 32' 'W5: the old summary is still there'
    HasLine $r.Text 'Comparison: api-only=3, differ=3, match=10, neither=1, ours-only=2' 'W5: and the old comparison, unchanged'
    HasLine $r.Text 'Rows written: 47 ->' 'W5: the rows written count the old and the cache pass'

    $kinds = Read-Rows $dir
    $expected = @{}
    foreach ($id in 11..14) { $expected["$id"] = 'cache-more' }
    foreach ($id in 15..23) { $expected["$id"] = 'cache-differ' }
    foreach ($id in 24..27) { $expected["$id"] = 'cache-lost' }
    foreach ($id in @(28, 29, 30, 31, 32, 41, 42, 43, 44, 45, 46, 52, 53)) { $expected["$id"] = 'cache-only' }
    foreach ($id in @(33, 34, 35, 36, 47, 48, 49, 50, 51)) { $expected["$id"] = 'cache-hidden' }
    foreach ($id in 1..53) {
        $got = if ($kinds.ContainsKey("$id")) { @($kinds["$id"] | Where-Object { $_ -like 'cache-*' }) } else { @() }
        $want = if ($expected.ContainsKey("$id")) { @($expected["$id"]) } else { @() }
        Equal ($got -join ',') ($want -join ',') "W6: quest $id gets its cache Kind, or none"
    }
    $oldKinds = @{ 3 = 'api-only'; 13 = 'api-only'; 25 = 'api-only'; 17 = 'differ'; 18 = 'differ'; 26 = 'differ'; 5 = 'ours-only'; 23 = 'ours-only' }
    foreach ($id in 1..53) {
        $got = if ($kinds.ContainsKey("$id")) { @($kinds["$id"] | Where-Object { $_ -notlike 'cache-*' }) } else { @() }
        $want = if ($oldKinds.ContainsKey($id)) { @($oldKinds[$id]) } else { @() }
        Equal ($got -join ',') ($want -join ',') "W7: quest $id keeps its old Kind, or none"
    }
    Equal ($kinds['17'] -join ',') 'cache-differ,differ' 'W7: a quest with both is listed twice, cache Kind first'
    foreach ($kind in @($kinds.Values | ForEach-Object { $_ } | Sort-Object -Unique)) {
        if ($kind -like 'cache-*') { Check ($kind -ine 'differ' -and $kind -ine 'api-only' -and $kind -ine 'ours-only') "W8: the Kind $kind is none Apply-ReputationBackfill acts on or counts" }
    }
    $csv = @(Import-Csv "$dir\quest_reputation_compare.csv")
    Equal (($csv[0].PSObject.Properties.Name) -join ',') 'QuestID,Kind,Ours,Api,ApiFactionNames,Cache,CacheFactionNames' 'W9: the columns are the old ones and the cache'
    $row = $csv | Where-Object { $_.QuestID -eq '13' -and $_.Kind -eq 'cache-more' }
    Equal $row.Ours '' 'W9: a row of the cache pass has ours'
    Equal $row.Api '76=250' 'W9: and the API''s'
    Equal $row.Cache '76=250;88=5' 'W9: and the cache''s'
    Equal $row.CacheFactionNames '76=Orgrimmar;88=(not in the Faction table)' 'W9: and the names of the cache''s factions from the Faction table'
    $row = $csv | Where-Object { $_.QuestID -eq '17' -and $_.Kind -eq 'differ' }
    Equal $row.Cache '' 'W9: a row of the old pass has no cache'
    Equal $row.ApiFactionNames '76=Faction "76"' 'W9: and still has the API''s names'
    $row = $csv | Where-Object { $_.QuestID -eq '28' }
    Equal $row.Api '' 'W9: a quest the API has no record of has no API reward'
    $row = $csv | Where-Object { $_.QuestID -eq '2' }
    Equal @($row).Count 0 'W9: a quest that agrees has no row'
    Equal (@($csv | ForEach-Object { [int]$_.QuestID }) -join ',') ((@($csv | ForEach-Object { [int]$_.QuestID } | Sort-Object)) -join ',') 'W9: the rows are in quest order'

    # --- The examples ------------------------------------------------------------------------------
    HasLine $r.Text '  C  15  ours [76=250]  API [76=250]  cache [76=200]' 'X1: a class names a quest with all three sets'
    HasLine $r.Text '  B  13  ours []  API [76=250]  cache [76=250;88=5]' 'X1: B too'
    HasLine $r.Text '  D  26  ours [76=100]  API [76=250]  cache []' 'X1: and D'
    HasLine $r.Text '  E  28  ours []  API []  cache [76=250]' 'X1: and E'
    HasLine $r.Text '  F  33  ours []  API []  cache [99=5]' 'X1: and F'
    Equal @($r.Text -split "`n" | Where-Object { $_ -match '^  E  \d+  ours' }).Count 5 'X2: five examples of a class by default'
    Equal @($r.Text -split "`n" | Where-Object { $_ -match '^  C  \d+  ours' }).Count 5 'X2: for every class'
    $r2 = Invoke-Tool $dir @{ Examples = 2 }
    Equal @($r2.Text -split "`n" | Where-Object { $_ -match '^  E  \d+  ours' }).Count 2 'X2: -Examples changes how many'
    Equal @($r2.Text -split "`n" | Where-Object { $_ -match '^  B  \d+  ours' }).Count 2 'X2: for every class'
    $r2 = Invoke-Tool $dir @{ Examples = 20 }
    Equal @($r2.Text -split "`n" | Where-Object { $_ -match '^  E  \d+  ours' }).Count 13 'X2: and a class with fewer is listed whole'
    Lacks $r.Text '  A  1  ours' 'X3: class A has no examples'
    Lacks $r.Text '  G  37  ours' 'X3: nor G'

    # --- Apply-ReputationBackfill leaves the cache pass's rows alone ---------------------------------
    $applyDir = Join-Path $Scratch 'apply'
    Copy-Item $dir $applyDir -Recurse
    $luaBefore = [IO.File]::ReadAllText("$applyDir\qcQuest.lua")
    $global:LASTEXITCODE = 0
    $applied = @(& $Apply -ToolsDir $applyDir -DataDir "$applyDir\data" -QuestFile "$applyDir\qcQuest.lua") -join "`n"
    Has $applied 'Rows added: 3; corrected: 3' 'Y1: only the api-only and differ rows are applied'
    Has $applied 'Rewards only we list, left for review: 2' 'Y1: and the ours-only rows are counted'
    $luaAfter = [IO.File]::ReadAllText("$applyDir\qcQuest.lua")
    . "$PSScriptRoot\QuestReputation.ps1"
    function Format-Flat($set) { return (($set.Keys | Sort-Object { [int]$_ } | ForEach-Object { "$_=$($set[$_])" }) -join ',') }
    function Get-Flat($map) { return @($map.Keys | ForEach-Object { "${_}:" + (Format-Flat $map[$_]) }) }
    $changed = @(Compare-Object (Get-Flat (Get-QuestReputation $luaBefore)) (Get-Flat (Get-QuestReputation $luaAfter)) | ForEach-Object { [int]($_.InputObject -replace ':.*$') } | Sort-Object -Unique)
    Equal ($changed -join ',') '3,13,17,18,25,26' 'Y2: only the api-only and differ quests have a different row, none of the cache Kinds'
    $afterMap = Get-QuestReputation $luaAfter
    Equal (Format-Flat $afterMap['3']) '76=250' 'Y2: an api-only quest has the API''s reward'
    Equal (Format-Flat $afterMap['17']) '76=250' 'Y2: and a differ quest has its row corrected'

    # --- Which factions are shown ------------------------------------------------------------------------
    foreach ($case in @(
            @{ Faction = 76; Class = 'cache-only'; Why = 'flags 2' }, @{ Faction = 72; Class = 'cache-only'; Why = 'flags 0' },
            @{ Faction = 80; Class = 'cache-only'; Why = 'flags 16, which is not hidden' }, @{ Faction = 81; Class = 'cache-only'; Why = 'flags 8' },
            @{ Faction = 82; Class = 'cache-only'; Why = 'flags 1' }, @{ Faction = 56; Class = 'cache-only'; Why = 'index 0' },
            @{ Faction = 98; Class = 'cache-hidden'; Why = 'flags 6' }, @{ Faction = 99; Class = 'cache-hidden'; Why = 'flags 4' },
            @{ Faction = 97; Class = 'cache-hidden'; Why = 'flags 20' }, @{ Faction = 55; Class = 'cache-hidden'; Why = 'index -1' },
            @{ Faction = 88; Class = 'cache-hidden'; Why = 'not in the table' })) {
        $world = @{ 1 = New-Quest '' $null "$($case.Faction)=5" }
        $d = Write-World ("shown-" + $case.Faction) $world
        $null = Invoke-Tool $d
        $shownKinds = Read-Rows $d
        Equal ($shownKinds['1'] -join ',') $case.Class "Z1: faction $($case.Faction) ($($case.Why)) is $(if ($case.Class -eq 'cache-only') { 'shown' } else { 'not shown' })"
    }

    # --- Exit codes ---------------------------------------------------------------------------------------
    $world = @{ 1 = New-Quest '76=250' '76=250' '76=250'; 2 = New-Quest '76=250' $null '76=250 99=5'; 3 = New-Quest '' $null '76=5'; 4 = New-Quest '' $null '99=5'; 5 = New-Quest '76=250' $null $null }
    $d = Write-World 'exit-clean' $world
    $r = Invoke-Tool $d
    Equal $r.Exit 0 'E1: agreeing quests and B, E, F and G only exit 0'
    Lacks $r.Text 'FAILED' 'E1: and do not say FAILED'
    $world = @{ 1 = New-Quest '76=250' '76=250' '76=200' }
    $d = Write-World 'exit-c' $world
    $r = Invoke-Tool $d
    Equal $r.Exit 1 'E2: one class C quest fails the run'
    HasLine $r.Text 'FAILED: 1 quests have a reward that differs and 0 lost theirs in the cache' 'E2: and says so'
    $world = @{ 1 = New-Quest '76=250' $null '' }
    $d = Write-World 'exit-d' $world
    $r = Invoke-Tool $d
    Equal $r.Exit 1 'E3: one class D quest fails the run'
    HasLine $r.Text 'FAILED: 0 quests have a reward that differs and 1 lost theirs in the cache' 'E3: and says so'
    $world = @{ 1 = New-Quest '76=250' '76=250' '76=200'; 2 = New-Quest '76=250' '76=250' '76=200' }
    $d = Write-World 'exit-moved' $world
    $r = Invoke-Tool $d @{ ReaderMovedAt = 2 }
    Equal $r.Exit 1 'E4: as many class C quests as -ReaderMovedAt fail the run'
    HasLine $r.Text 'FAILED: 2 quests have a reward that differs between ours, the API and the cache: the cache reader looks moved. Run Compare-QuestCache.ps1' 'E4: and say the reader looks moved'
    $r = Invoke-Tool $d @{ ReaderMovedAt = 3 }
    Equal $r.Exit 1 'E5: one fewer is still a failure'
    Lacks $r.Text 'looks moved' 'E5: but does not say the reader moved'
    $r = Invoke-Tool $d
    Lacks $r.Text 'looks moved' 'E5: the default is far more than two'
    $world = @{}
    foreach ($id in 1..100) { $world[$id] = New-Quest '76=250' '76=250' '76=200' }
    $d = Write-World 'exit-hundred' $world
    $r = Invoke-Tool $d
    HasLine $r.Text 'FAILED: 100 quests have a reward that differs between ours, the API and the cache: the cache reader looks moved.' 'E5: the default -ReaderMovedAt is 100'
    $world.Remove(100)
    $d = Write-World 'exit-ninetynine' $world
    $r = Invoke-Tool $d
    HasLine $r.Text 'FAILED: 99 quests have a reward that differs and 0 lost theirs' 'E5: and 99 are not enough'

    # --- Skipped, and the files it needs ------------------------------------------------------------------
    $d = Write-World 'nocache' (New-World) @{ NoCache = $true }
    $r = Invoke-Tool $d
    Equal $r.Failure '' 'S1: without a cache the run does not throw'
    Equal $r.Exit 0 'S1: and exits 0, because the old pass found nothing wrong'
    HasLine $r.Text "Cache pass skipped: no retail_quest_cache_<build>.jsonl under $d (Read-QuestCache.ps1 -Build <retail build>, step 2e of docs\maintenance.md)." 'S1: it says it was skipped, and what to run'
    Lacks $r.Text 'A agree' 'S1: with no classes'
    HasLine $r.Text 'Comparison: api-only=3, differ=3, match=10, neither=1, ours-only=2' 'S1: the old pass runs'
    HasLine $r.Text 'Rows written: 8 ->' 'S1: and writes its rows'
    $csv = @(Import-Csv "$d\quest_reputation_compare.csv")
    Equal $csv.Count 8 'S1: the CSV holds the old rows only'
    Equal (($csv[0].PSObject.Properties.Name) -join ',') 'QuestID,Kind,Ours,Api,ApiFactionNames,Cache,CacheFactionNames' 'S1: with the same columns'
    $d = Write-World 'nofaction' (New-World) @{ NoFaction = $true }
    $r = Invoke-Tool $d
    Equal $r.Failure '' 'S2: without a Faction table the run does not throw'
    Equal $r.Exit 0 'S2: and exits 0'
    HasLine $r.Text "Cache pass skipped: no Faction table for build $Build under $d (https://wago.tools/db2/Faction/csv?build=$Build, saved as Faction-$Build.csv)." 'S2: it says what is missing and where to get it'
    Lacks $r.Text 'A agree' 'S2: with no classes'
    $forever = "Faction-1.60.1.70205.csv"
    Copy-Item "$Scratch\main\Faction-$Build.csv" "$d\$forever"
    $r = Invoke-Tool $d
    HasLine $r.Text 'Cache pass skipped: no Faction table' 'S3: another game''s Faction table is not used'
    $d = Write-World 'otherfaction' (New-World) @{ NoFaction = $true }
    Copy-Item "$Scratch\main\Faction-$Build.csv" "$d\Faction-12.1.0.9.csv"
    Copy-Item "$Scratch\main\Faction-$Build.csv" "$d\Faction-12.1.0.70000.csv"
    Copy-Item "$Scratch\main\Faction-$Build.csv" "$d\Faction-12.0.9.99999.csv"
    Copy-Item "$Scratch\main\Faction-$Build.csv" "$d\Faction.csv"
    $r = Invoke-Tool $d
    Has $r.Text 'Faction table Faction-12.1.0.70000.csv: 12 factions' 'S4: without the cache''s build, the newest of the same major version is read, by version and not by text'
    HasLine $r.Text 'Builds: API 12.1.0_68914, cache 12.1.0.69933, Faction table 12.1.0.70000.' 'S4: and named as the Faction table''s build'
    HasLine $r.Text 'WARNING: the builds differ' 'S4: with a warning'
    $d = Write-World 'badfaction' (New-World) @{ NoFaction = $true }
    [IO.File]::WriteAllText("$d\Faction-$Build.csv", "ID,Name_lang,ReputationIndex`r`n76,Orgrimmar,10`r`n", $utf8)
    $r = Invoke-Tool $d
    Equal $r.Failure '' 'S5: a Faction table without a column the pass reads does not throw'
    Equal $r.Exit 1 'S5: it fails the run'
    HasLine $r.Text "FAILED: the cache pass stopped: $d\Faction-$Build.csv has no rows or no ReputationFlags_0 column." 'S5: and says why'
    Lacks $r.Text 'A agree' 'S5: with no classes'
    Has $r.Text 'Comparison: api-only=3, differ=3, match=10, neither=1, ours-only=2' 'S5: the API comparison still runs'
    Equal @(Import-Csv "$d\quest_reputation_compare.csv").Count 8 'S5: and its rows are written, and no others'
    foreach ($column in 'ID', 'Name_lang', 'ReputationIndex') {
        $header = (@('ID', 'Name_lang', 'ReputationIndex', 'ReputationFlags_0') | Where-Object { $_ -ne $column }) -join ','
        [IO.File]::WriteAllText("$d\Faction-$Build.csv", "$header`r`n1,2,3`r`n", $utf8)
        $r = Invoke-Tool $d
        HasLine $r.Text "FAILED: the cache pass stopped: $d\Faction-$Build.csv has no rows or no $column column." "S5: and one without $column"
    }
    [IO.File]::WriteAllText("$d\Faction-$Build.csv", "ID,Name_lang,ReputationIndex,ReputationFlags_0`r`n", $utf8)
    $r = Invoke-Tool $d
    HasLine $r.Text "FAILED: the cache pass stopped: $d\Faction-$Build.csv has no rows or no ID column." 'S5: and one with no rows'

    # --- Which cache --------------------------------------------------------------------------------------
    $d = Write-World 'twocaches' (New-World)
    [IO.File]::WriteAllText("$d\retail_quest_cache_12.1.0.9.jsonl", "", $utf8)
    [IO.File]::WriteAllText("$d\retail_quest_cache_notabuild.jsonl", "", $utf8)
    [IO.File]::WriteAllText("$d\retail_quest_cache_99.9.9.9.jsonl.bak", "", $utf8)
    $r = Invoke-Tool $d
    HasLine $r.Text 'Cache pass: retail_quest_cache_12.1.0.69933.jsonl holds 51 quests' 'C1: the newest build''s cache is read, by version and not by text, and a file that is no build is ignored'
    $r = Invoke-Tool $d @{ Cache = "$d\retail_quest_cache_12.1.0.9.jsonl" }
    HasLine $r.Text 'Cache pass: retail_quest_cache_12.1.0.9.jsonl holds 0 quests, 0 of our 51.' 'C2: -Cache names another'
    HasLine $r.Text 'WARNING: the cache holds none of our quests.' 'C2: and a cache with none of ours is warned about'
    HasLine $r.Text 'Builds: API 12.1.0_68914, cache 12.1.0.9, Faction table 12.1.0.69933.' 'C2: the Faction table is looked for by the cache''s build, then the newest'
    HasLine $r.Text '  G not in the cache: 51 (' 'C2: every quest of ours is not in it'
    Equal $r.Exit 0 'C2: and an empty cache fails nothing'
    $r = Invoke-Tool $d @{ Cache = "$d\no-such-cache.jsonl" }
    Has $r.Failure "No $d\no-such-cache.jsonl." 'C3: a -Cache that does not exist is refused'
    $d = Write-World 'blanklines' (New-World)
    $cacheFile = "$d\retail_quest_cache_$Build.jsonl"
    $lines = [IO.File]::ReadAllLines($cacheFile)
    [IO.File]::WriteAllText($cacheFile, (($lines[0..2] -join "`n") + "`n`n" + ($lines[3..($lines.Count - 1)] -join "`n") + "`n`n"), $utf8)
    $r = Invoke-Tool $d
    Equal $r.Failure '' 'C4: blank lines in the cache are skipped'
    Has $r.Text 'holds 51 quests, 49 of our 51' 'C4: with every quest read'

    # --- The builds -----------------------------------------------------------------------------------------
    $d = Write-World 'samebuild' (New-World) @{ Namespace = '12.1.0_69933' }
    $r = Invoke-Tool $d
    HasLine $r.Text 'Builds: API 12.1.0_69933, cache 12.1.0.69933, Faction table 12.1.0.69933.' 'B1: the three builds are printed'
    Lacks $r.Text 'WARNING: the builds differ' 'B1: and an underscore in the API''s is the same as a dot'
    $d = Write-World 'twoapi' (New-World)
    [IO.File]::WriteAllText("$d\quest_api_cache\1.json", (New-ApiRecord 1 '76=250' '12.1.0_68000'), $utf8)
    $r = Invoke-Tool $d
    HasLine $r.Text 'Builds: API 12.1.0_68000, 12.1.0_68914, cache' 'B2: two API builds are both named'
    $d = Write-World 'noapi' (New-World)
    Get-ChildItem "$d\quest_api_cache" | Remove-Item -Force
    $r = Invoke-Tool $d
    HasLine $r.Text 'Builds: API none read, cache 12.1.0.69933' 'B3: with no API record the build is "none read"'
    HasLine $r.Text 'WARNING: no API record was read, so the classes below hold ours and the cache only.' 'B3: and a warning says what that means'
    $d = Write-World 'allbuilds' (New-World) @{ Namespace = '12.1.0_69933' }
    $r = Invoke-Tool $d
    Lacks $r.Text 'no API record was read' 'B3: and has none when records were read'

    # --- The baseline ----------------------------------------------------------------------------------------
    $d = Write-World 'baseline' (New-World)
    $r = Invoke-Tool $d
    HasLine $r.Text "  No baseline file at $d\baseline.csv: -UpdateBaseline writes one from this run." 'L1: without a baseline file, the run says how to write one'
    Lacks $r.Text 'in the baseline;' 'L1: and compares nothing'
    Check (-not (Test-Path "$d\baseline.csv")) 'L1: and writes nothing'
    $r = Invoke-Tool $d @{ UpdateBaseline = $true }
    HasLine $r.Text "  Baseline written: 28 quests -> $d\baseline.csv" 'L2: -UpdateBaseline writes the quests of B, E, F and G'
    $bytes = [IO.File]::ReadAllBytes("$d\baseline.csv")
    Equal ('{0:X2}{1:X2}{2:X2}' -f $bytes[0], $bytes[1], $bytes[2]) 'EFBBBF' 'L2: with a byte order mark, like the other CSVs under docs\plans'
    $text = [IO.File]::ReadAllText("$d\baseline.csv", $utf8).TrimStart([char]0xFEFF)
    $expectedLines = @('"Class","QuestID"') + @(11..14 | ForEach-Object { '"B","' + $_ + '"' }) + @(28, 29, 30, 31, 32, 41, 42, 43, 44, 45, 46, 52, 53 | ForEach-Object { '"E","' + $_ + '"' }) + @(33, 34, 35, 36, 47, 48, 49, 50, 51 | ForEach-Object { '"F","' + $_ + '"' }) + @(37, 38 | ForEach-Object { '"G","' + $_ + '"' })
    Equal $text (($expectedLines -join "`r`n") + "`r`n") 'L2: one row for each, by class and then by quest, with CRLF'
    $r = Invoke-Tool $d
    foreach ($line in 'B: 4 now, 4 in the baseline; 0 new, 0 gone', 'E: 13 now, 13 in the baseline; 0 new, 0 gone', 'F: 9 now, 9 in the baseline; 0 new, 0 gone', 'G: 2 now, 2 in the baseline; 0 new, 0 gone') { Has $r.Text "  $line" "L3: the next run finds nothing new: $line" }
    Lacks $r.Text '      new:' 'L3: and lists none'
    Lacks $r.Text '      gone:' 'L3: of either'
    Lacks $r.Text 'No baseline file' 'L3: and does not say there is none'
    Lacks $r.Text 'Baseline written' 'L3: or write one'
    Equal ([IO.File]::ReadAllText("$d\baseline.csv", $utf8).TrimStart([char]0xFEFF)) (($expectedLines -join "`r`n") + "`r`n") 'L3: or change it'

    $world = New-World
    $world[28].Cache = $null
    $world[33].Cache = '76=5'
    $d2 = Write-World 'baseline-moved' $world
    Copy-Item "$d\baseline.csv" "$d2\baseline.csv"
    $r = Invoke-Tool $d2
    Equal $r.Exit 1 'L4: what moved between classes does not change the exit code'
    HasLine $r.Text '  B: 4 now, 4 in the baseline; 0 new, 0 gone' 'L4: B did not move'
    HasLine $r.Text "  E: 13 now, 13 in the baseline; 1 new, 1 gone`n      new: 33`n      gone: 28" 'L4: E has the quest that came from F, and lost the one that is no longer in the cache'
    HasLine $r.Text "  F: 8 now, 9 in the baseline; 0 new, 1 gone`n      gone: 33" 'L4: F lost it'
    HasLine $r.Text "  G: 3 now, 2 in the baseline; 1 new, 0 gone`n      new: 28" 'L4: and G has the other'
    $before = [IO.File]::ReadAllText("$d2\baseline.csv", $utf8)
    $r = Invoke-Tool $d2 @{ UpdateBaseline = $true }
    HasLine $r.Text '      new: 33' 'L5: -UpdateBaseline still says what moved'
    HasLine $r.Text '  Baseline written: 28 quests' 'L5: and then rewrites the file'
    Check ([IO.File]::ReadAllText("$d2\baseline.csv", $utf8) -ne $before) 'L5: with the new classes'
    $r = Invoke-Tool $d2
    HasLine $r.Text '  E: 13 now, 13 in the baseline; 0 new, 0 gone' 'L5: which a run then finds as it is'

    $lines = @('"Class","QuestID"') + @(100..104 | ForEach-Object { '"E","' + $_ + '"' })
    [IO.File]::WriteAllText("$d2\baseline.csv", (($lines -join "`r`n") + "`r`n"), $utf8)
    $r = Invoke-Tool $d2 @{ Examples = 2 }
    HasLine $r.Text "  E: 13 now, 5 in the baseline; 13 new, 5 gone`n      new: 29, 30, ...`n      gone: 100, 101, ..." 'L6: -Examples caps the quests named, which are in quest order'
    HasLine $r.Text "  B: 4 now, 0 in the baseline; 4 new, 0 gone`n      new: 11, 12, ..." 'L6: for every class'
    $r = Invoke-Tool $d2 @{ Examples = 13 }
    HasLine $r.Text '      new: 29, 30, 31, 32, 33, 41, 42, 43, 44, 45, 46, 52, 53' 'L6: a list of exactly -Examples quests has no ellipsis'
    Lacks $r.Text ', ...' 'L6: and no other list has one'
    $r = Invoke-Tool $d2 @{ Examples = 5 }
    HasLine $r.Text '      gone: 100, 101, 102, 103, 104' 'L6: nor does a shorter one'
    Lacks $r.Text '104, ...' 'L6: and none'
    [IO.File]::WriteAllText("$d2\baseline.csv", "`"Class`",`"QuestID`"`r`n`"A`",`"1`"`r`n", $utf8)
    $r = Invoke-Tool $d2
    Equal $r.Exit 1 'L7: a baseline row of another class fails the run'
    HasLine $r.Text "FAILED: the cache pass stopped: $d2\baseline.csv has class 'A', not one of B, E, F, G." 'L7: and is named'
    Equal @(Import-Csv "$d2\quest_reputation_compare.csv").Count 8 'L7: and the rows of classes B to F that were found by then are not written'
    [IO.File]::WriteAllText("$d2\baseline.csv", "`"Class`",`"QuestID`"`r`n", $utf8)
    $r = Invoke-Tool $d2
    HasLine $r.Text '  G: 3 now, 0 in the baseline; 3 new, 0 gone' 'L8: a baseline with no rows is read as empty'

    # --- The exact build, a cache that is not JSON, the defaults ----------------------------------------------------
    $d = Write-World 'exactfaction' (New-World)
    [IO.File]::WriteAllText("$d\Faction-12.1.0.70000.csv", "ID,Name_lang,ReputationIndex,ReputationFlags_0`r`n76,Orgrimmar,10,2`r`n", $utf8)
    $r = Invoke-Tool $d
    HasLine $r.Text 'Cache pass: retail_quest_cache_12.1.0.69933.jsonl holds 51 quests, 49 of our 51. Faction table Faction-12.1.0.69933.csv: 12 factions, 8 shown.' 'F1: the Faction table of the cache''s own build is read, though a newer one is there'
    $d = Write-World 'badcache' (New-World)
    [IO.File]::AppendAllText("$d\retail_quest_cache_$Build.jsonl", '{"id":99,"reputation":[[76,' + "`n", $utf8)
    $r = Invoke-Tool $d
    Equal $r.Failure '' 'F2: a cache line that is not JSON does not throw'
    Equal $r.Exit 1 'F2: it fails the run'
    HasLine $r.Text 'FAILED: the cache pass stopped: ' 'F2: and says the pass stopped'
    Lacks $r.Text 'A agree' 'F2: with no classes'
    Equal @(Import-Csv "$d\quest_reputation_compare.csv").Count 8 'F2: and the CSV holds the API comparison''s rows only'
    $parsed = [System.Management.Automation.Language.Parser]::ParseFile($Tool, [ref]$null, [ref]$null)
    $defaults = @{}
    foreach ($parameter in $parsed.ParamBlock.Parameters) { if ($parameter.DefaultValue) { $defaults[$parameter.Name.VariablePath.UserPath] = $parameter.DefaultValue.Extent.Text } }
    Equal $defaults['BaselineFile'] "(Join-Path `$PSScriptRoot '..\docs\plans\quest-reputation-cache-baseline.csv')" 'F3: the baseline file defaults to the one under docs\plans'
    Check (Test-Path (Join-Path $PSScriptRoot '..\docs\plans\quest-reputation-cache-baseline.csv')) 'F3: and it is committed there'
    Equal $defaults['QuestFile'] "(Join-Path `$PSScriptRoot '..\QuestCompletist\qcQuest.lua')" 'F3: the quest file defaults to the addon''s'
    Equal $defaults['ReaderMovedAt'] '100' 'F3: and -ReaderMovedAt to 100'
    Equal $defaults['Examples'] '5' 'F3: and -Examples to 5'

    # --- The cache's own oddities -------------------------------------------------------------------------------
    $world = @{ 1 = New-Quest '76=250 72=-25' $null '76=100 72=-25 76=150'; 2 = New-Quest '76=150' $null '76=100 76=50' }
    $d = Write-World 'twice' $world
    $r = Invoke-Tool $d
    HasLine $r.Text '  A agree: 2' 'O1: a faction in two slots is its amounts added'
    Has $r.Text '2 factions in two slots of one quest' 'O1: and every such slot is counted'
    $world = @{ 1 = New-Quest '' $null '76=0'; 2 = New-Quest '' $null '76=0 72=0' }
    $d = Write-World 'zeroslots' $world
    $r = Invoke-Tool $d
    Has $r.Text '3 empty-amount slots' 'O2: every slot with an amount of 0 is counted'
    HasLine $r.Text '  Nothing listed anywhere: 2' 'O2: and is no reward'
    $world = @{ 1 = New-Quest '' $null '76=0 72=-5' }
    $d = Write-World 'zeromix' $world
    $r = Invoke-Tool $d
    HasLine $r.Text '  E cache only, on a shown faction (backfill candidates): 1 quests, 1 rewards' 'O2: the other slots of the quest are kept'
    $world = @{ 1 = New-Quest '' $null '76=5'; 2 = New-Quest '' $null '76=5' }
    $d = Write-World 'idorder' $world
    [IO.File]::WriteAllText("$d\retail_quest_cache_$Build.jsonl", '{"id":2,"reputation":[[76,5]]}' + "`n" + '{"id":1,"reputation":[[76,5]]}' + "`n", $utf8)
    $r = Invoke-Tool $d
    HasLine $r.Text '  E cache only, on a shown faction (backfill candidates): 2 quests' 'O3: the cache is read in any order'

}
finally {
    [Threading.Thread]::CurrentThread.CurrentCulture = $savedCulture
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
