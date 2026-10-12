<#
Checks Sync-QuestProfessions.ps1 in a scratch folder: nothing in the checkout is touched and nothing is
downloaded.

  A  Made-up client tables, API records, quest cache and decisions, with the checkout's own qcCore.lua
     and qcQuest.lua: what each pass names (task, heading, knowledge) and what it leaves (a heading
     that names no profession, a recipe, a choice of rewards, an item that needs no skill, a skill line
     with no bit), the quests whose sources or passes disagree, a profession of ours that differs, the
     decisions (SET with and without a heading, KEEP, out of date, a quest not in the data), the quests
     filed under another profession's heading, that -WhatIf writes nothing, that the data passes the
     record checks and the Lua matches, and that a second run changes no byte.
  B  The real tables, API records and quest cache (in -ToolsDir) against a scratch copy of the
     checkout's data and decisions: nothing is left to do, then quests each pass and each kind of
     decision gave a profession lose it and the tool must give exactly that back, and a second run must
     change nothing. Skipped, with a line saying so, when the tables aren't there (they are only in the
     main checkout).

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-SyncQuestProfessions.ps1 [-ToolsDir <folder>] [-MadeUpOnly]

-MadeUpOnly runs A alone, which takes about half a minute; with both it takes about two minutes.

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
param([string]$ToolsDir = $PSScriptRoot, [switch]$MadeUpOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonData.ps1')
$Tool = Join-Path $PSScriptRoot 'Sync-QuestProfessions.ps1'
$AddonSource = Join-Path $PSScriptRoot '..\QuestCompletist'
$DataSource = Join-Path $PSScriptRoot '..\data'
$DecisionsSource = Join-Path $PSScriptRoot '..\docs\plans\quest-profession-decisions.csv'
$Passed = 0; $Failed = 0; $Skipped = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Invoke-Tool([string[]]$arguments) {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Tool @arguments 2>&1
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Text = (($output | ForEach-Object { "$_" }) -join "`n") }
}
function Get-Hash([string]$path) { return (Get-FileHash $path -Algorithm SHA256).Hash }
function New-Folder([string]$path) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
function Write-Csv([string]$path, $rows) { $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8 }
function Read-Quests([string]$dir) { return @(Read-QuestData $dir) }
function Quest-Row([int]$id, [int]$category = 0, [int]$profession = 0) {
    $q = [pscustomobject][ordered]@{ id = $id; name = "Quest $id"; level = 10; zone = ''; category = $category; type = 1; faction = 3; race = 67108863; class = 8191 }
    if ($profession) { Set-RecordField $q 'profession' $profession }
    return $q
}
function Copy-Addon([string]$to, [string[]]$files) {
    New-Folder $to
    foreach ($file in $files) { Copy-Item (Join-Path $AddonSource $file) $to }
}
function Assert-Sound([string]$label, [string]$dataDir, [string]$addonDir) {
    $problems = @(Test-QuestRecords (Read-Quests $dataDir))
    Equal $problems.Count 0 "${label}: every record passes Test-QuestRecords ($($problems -join '; '))"
    Check (Invoke-AddonDataBuild $dataDir $addonDir -Check).Ok "${label}: qcQuestData.lua matches the data"
}
function Section([string]$text, [string]$heading) {
    $m = [regex]::Match($text, "(?m)^$([regex]::Escape($heading)) \((\d+)\):\r?\n((?:  .*(?:\r?\n|$))*)")
    if (-not $m.Success) { return '' }
    return $m.Groups[2].Value
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("sync-quest-professions-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Folder $Scratch

try {
    # --- A: made-up tables --------------------------------------------------------------------------
    $tools = "$Scratch\tools"; $data = "$Scratch\data"; $addon = "$Scratch\addon"; $api = "$tools\quest_api_cache"
    New-Folder $tools; New-Folder $data; New-Folder $api
    Copy-Addon $addon 'qcCore.lua', 'qcQuest.lua', 'qcPinDB.lua', 'qcQuestData.lua'

    $quests = @(
        (Quest-Row 1001), (Quest-Row 1002), (Quest-Row 1003), (Quest-Row 1004), (Quest-Row 1005), (Quest-Row 1006),
        (Quest-Row 1007), (Quest-Row 1008), (Quest-Row 1009), (Quest-Row 1010), (Quest-Row 1011), (Quest-Row 1012 0 256),
        (Quest-Row 1013), (Quest-Row 1014 402), (Quest-Row 1015), (Quest-Row 1016), (Quest-Row 1017 98 512), (Quest-Row 1018 122 128),
        (Quest-Row 1019 72 8), (Quest-Row 1020 0 256), (Quest-Row 1021), (Quest-Row 1022)
    )
    [IO.File]::WriteAllText("$data\quests.jsonl", (ConvertTo-QuestJsonLines $quests), $script:Utf8)
    [IO.File]::WriteAllText("$data\pins.jsonl", '{"map":84,"icon":1,"name":"Somebody","x":1.5,"y":2.5,"quests":[1001]}' + "`n", $script:Utf8)
    $built = Invoke-AddonDataBuild $data $addon
    if (-not $built.Ok) { throw ("The scratch Lua didn't build:`n" + ($built.Lines -join "`n")) }

    Write-Csv "$tools\SkillLine.csv" @(
        [pscustomobject]@{ DisplayName_lang = 'Herbalism'; ID = 182; ParentSkillLineID = 0 }, [pscustomobject]@{ DisplayName_lang = 'Mining'; ID = 186; ParentSkillLineID = 0 },
        [pscustomobject]@{ DisplayName_lang = 'Engineering'; ID = 202; ParentSkillLineID = 0 }, [pscustomobject]@{ DisplayName_lang = 'Enchanting'; ID = 333; ParentSkillLineID = 0 },
        [pscustomobject]@{ DisplayName_lang = 'Thalassian Mining'; ID = 2916; ParentSkillLineID = 186 }, [pscustomobject]@{ DisplayName_lang = 'Thalassian Herbalism'; ID = 2912; ParentSkillLineID = 182 },
        [pscustomobject]@{ DisplayName_lang = 'Riding'; ID = 9999; ParentSkillLineID = 0 }
    )
    Write-Csv "$tools\QuestInfo.csv" @([pscustomobject]@{ ID = 119; Profession = 182 }, [pscustomobject]@{ ID = 109; Profession = 0 })
    Write-Csv "$tools\QuestV2CliTask.csv" @(
        [pscustomobject]@{ ID = 1001; FiltMinSkillID = 2916; QuestInfoID = 109 }, [pscustomobject]@{ ID = 1020; FiltMinSkillID = 0; QuestInfoID = 119 },
        [pscustomobject]@{ ID = 5000; FiltMinSkillID = 2916; QuestInfoID = 0 }
    )
    Write-Csv "$tools\QuestSort.csv" @(
        [pscustomobject]@{ ID = 408; SortName_lang = 'Mining' }, [pscustomobject]@{ ID = 201; SortName_lang = 'Engineering' },
        [pscustomobject]@{ ID = 24; SortName_lang = 'Herbalism' }, [pscustomobject]@{ ID = 571; SortName_lang = 'Professions' }
    )
    Write-Csv "$tools\Item.csv" @(
        [pscustomobject]@{ ID = 9001; ClassID = 15; SubclassID = 4 }, [pscustomobject]@{ ID = 9002; ClassID = 15; SubclassID = 4 },
        [pscustomobject]@{ ID = 9003; ClassID = 9; SubclassID = 5 }, [pscustomobject]@{ ID = 9004; ClassID = 15; SubclassID = 4 },
        [pscustomobject]@{ ID = 9005; ClassID = 15; SubclassID = 4 }
    )
    Write-Csv "$tools\ItemSparse.csv" @(
        [pscustomobject]@{ ID = 9001; Display_lang = 'Thalassian Miner''s Notes'; RequiredSkill = 2916 }, [pscustomobject]@{ ID = 9002; Display_lang = 'Thalassian Herbalist''s Notes'; RequiredSkill = 2912 },
        [pscustomobject]@{ ID = 9003; Display_lang = 'Recipe: Ore Stew'; RequiredSkill = 186 }, [pscustomobject]@{ ID = 9004; Display_lang = 'Trinket'; RequiredSkill = 0 },
        [pscustomobject]@{ ID = 9005; Display_lang = 'Riding Notes'; RequiredSkill = 9999 }
    )
    $cache = @(
        '{"id":1002,"title":"A","sort":-408}', '{"id":1004,"title":"B","contentTuning":1,"sort":-201,"questType":2}', '{"id":1005,"title":"C","sort":-24}',
        '{"id":1006,"title":"D","sort":-571}', '{"id":1013,"title":"E","sort":-408}', '{"id":1015,"title":"F","sort":-408}',
        '{"id":1021,"title":"Says \"sort\":-408 in its title","sort":12}'
    )
    [IO.File]::WriteAllText("$tools\retail_quest_cache_9.9.9.99999.jsonl", ($cache -join "`n") + "`n", $script:Utf8)
    function Write-Api([int]$id, [string]$body) { [IO.File]::WriteAllText("$api\$id.json", "{`"id`":$id,`"title`":`"Quest $id`"$body}", $script:Utf8) }
    function Category([int]$id, [string]$name) { return ",`"category`":{`"key`":{`"href`":`"https://example/$id`"},`"name`":`"$name`",`"id`":$id}" }
    function Items([string]$kind, [int[]]$items) {
        $list = ($items | ForEach-Object { "{`"item`":{`"key`":{`"href`":`"https://example/$_`"},`"name`":`"Item $_`",`"id`":$_}}" }) -join ','
        return ",`"rewards`":{`"experience`":10,`"items`":{`"$kind`":[$list]}}"
    }
    Write-Api 1002 (Category 408 'Mining')
    Write-Api 1003 (Category 24 'Herbalism')
    Write-Api 1005 (Category 408 'Mining')
    Write-Api 1006 (Category 571 'Professions')
    Write-Api 1007 (Items 'items' 9001)
    Write-Api 1008 (Items 'items' 9003)
    Write-Api 1009 (Items 'items' 9001, 9002)
    Write-Api 1010 (Items 'items' 9004)
    Write-Api 1011 (Items 'choice_of' 9001)
    Write-Api 1012 (Category 408 'Mining')
    Write-Api 1013 (Items 'items' 9002)
    Write-Api 1022 (Items 'items' 9005)

    $decisions = "$Scratch\decisions.csv"
    function Decision([int]$id, [string]$decision, $cur, $target, $curCategory = '', $targetCategory = '') {
        return [pscustomobject][ordered]@{ QuestID = $id; Name = "Quest $id"; Decision = $decision; Profession = ''; Cur = $cur; Target = $target; CurCategory = $curCategory; TargetCategory = $targetCategory; Evidence = 'test' }
    }
    Write-Csv $decisions @((Decision 1014 'SET' 0 8 402 72), (Decision 1015 'KEEP' 0 0), (Decision 1016 'SET' 4 8), (Decision 1018 'SET' 128 128 122 202), (Decision 1099 'SET' 0 8))

    $common = @('-ToolsDir', $tools, '-DataDir', $data, '-AddonDir', $addon, '-DecisionsFile', $decisions)
    $hashes = @{ Quests = Get-Hash "$data\quests.jsonl"; Lua = Get-Hash "$addon\qcQuestData.lua"; Pins = Get-Hash "$data\pins.jsonl" }
    $dry = Invoke-Tool ($common + '-WhatIf')
    Equal $dry.Exit 0 "A1: -WhatIf succeeds ($($dry.Text))"
    Check ($dry.Text -match 'Build 9\.9\.9\.99999\.') 'A1: the build is the newest quest cache''s'
    Check ($dry.Text -notmatch 'Downloading') 'A1: it downloads nothing when the tables are there'
    Check ($dry.Text -match '3 headings name a profession') "A1: Mining, Engineering and Herbalism are profession headings, Professions isn't"
    Check ($dry.Text -match '(?m)^Decisions: 5 rows; 2 to apply, 0 applied, 1 kept\.') "A1: two decisions to apply and one kept ($($dry.Text))"
    Equal (Get-Hash "$data\quests.jsonl") $hashes.Quests 'A1: -WhatIf leaves quests.jsonl alone'
    Equal (Get-Hash "$addon\qcQuestData.lua") $hashes.Lua 'A1: and the Lua'

    $sources = Section $dry.Text "A pass's sources disagree, left out"
    Check ($sources -match '1005 Quest 1005: heading, the API''s says Mining \(512\), the quest cache''s Herbalism \(256\)') 'A2: the API and the quest cache disagree on 1005'
    Check ($sources -match '1009 Quest 1009: knowledge, its rewards need Herbalism \(256\) and Mining \(512\)') 'A2: 1009 rewards two professions'' knowledge'
    $passes = Section $dry.Text 'Passes disagree, left out'
    Check ($passes -match '1013 Quest 1013: heading Mining \(512\), knowledge Herbalism \(256\)') "A2: the heading and knowledge passes disagree on 1013 ($passes)"
    $differ = Section $dry.Text 'Ours differs, left as it is'
    Check ($differ -match '1012 Quest 1012: ours Herbalism \(256\), heading Mining \(512\)') 'A2: 1012 keeps its own profession and is listed'
    $noBit = Section $dry.Text 'No profession bit for the skill line, left out'
    Check ($noBit -match '1022 Quest 1022: skill line 9999 of reward 9005') 'A2: a reward whose skill has no bit is listed'
    $stale = Section $dry.Text 'Decisions out of date'
    Check ($stale -match '1016 Quest 1016: SET row says 4/ to 8/, the data has 0/0') "A2: a SET row the data no longer matches ($stale)"
    Check ($stale -match '1099 Quest 1099: SET row for a quest not in the data') 'A2: a row for a quest not in the data'
    $headings = Section $dry.Text "Filed under another profession's heading"
    Check ($headings -match '1017 Quest 1017: Mining \(512\), filed under Herbalism \(256\) \(98\)') "A2: a Mining quest under the Herbalism heading ($headings)"
    Check ($headings -notmatch '1018') 'A2: a quest its decision moves to its own heading is not listed'
    Check ($headings -notmatch '1019') 'A2: nor one under its own heading'

    $run = Invoke-Tool $common
    Equal $run.Exit 0 "A3: the run succeeds ($($run.Text))"
    Equal (Get-Hash "$data\pins.jsonl") $hashes.Pins 'A3: the pins are untouched'
    Assert-Sound 'A3' $data $addon
    $byId = @{}; foreach ($q in (Read-Quests $data)) { $byId[[int]$q.id] = $q }
    function Field([int]$id, [string]$field) { return $byId[$id].$field }
    Equal (Field 1001 'profession') 512 'A4: task: a skill line gives its parent profession'
    Equal (Field 1020 'profession') 256 'A4: task: a quest kind that agrees with ours changes nothing'
    Equal (Field 1002 'profession') 512 'A4: heading: the API and the quest cache agree'
    Equal (Field 1003 'profession') 256 'A4: heading: the API alone'
    Equal (Field 1004 'profession') 8 'A4: heading: the quest cache alone'
    Check ($null -eq (Field 1005 'profession')) 'A4: heading: sources that disagree give none'
    Check ($null -eq (Field 1006 'profession')) 'A4: heading: the general Professions heading gives none'
    Check ($null -eq (Field 1021 'profession')) 'A4: heading: a positive sort is a zone, whatever the title says'
    Equal (Field 1007 'profession') 512 'A4: knowledge: notes that need Thalassian Mining give Mining'
    Check ($null -eq (Field 1008 'profession')) 'A4: knowledge: a recipe gives none'
    Check ($null -eq (Field 1009 'profession')) 'A4: knowledge: two professions give none'
    Check ($null -eq (Field 1010 'profession')) 'A4: knowledge: an item that needs no skill gives none'
    Check ($null -eq (Field 1011 'profession')) 'A4: knowledge: a choice of rewards gives none'
    Check ($null -eq (Field 1022 'profession')) 'A4: knowledge: a skill with no bit gives none'
    Equal (Field 1012 'profession') 256 'A4: ours is kept where it differs'
    Check ($null -eq (Field 1013 'profession')) 'A4: passes that disagree give none'
    Equal (Field 1014 'profession') 8 'A5: SET gives the Target'
    Equal (Field 1014 'category') 72 'A5: and the TargetCategory'
    Check ($null -eq (Field 1015 'profession')) 'A5: KEEP leaves the quest as it is though a pass names a profession'
    Check ($null -eq (Field 1016 'profession')) 'A5: an out-of-date SET row changes nothing'
    Equal (Field 1018 'profession') 128 'A5: a SET row that only moves the heading keeps the profession'
    Equal (Field 1018 'category') 202 'A5: and moves the heading'
    Equal (Field 1017 'category') 98 'A5: a quest filed under another heading is only listed'

    $hashes = @{ Quests = Get-Hash "$data\quests.jsonl"; Lua = Get-Hash "$addon\qcQuestData.lua" }
    $again = Invoke-Tool $common
    Equal $again.Exit 0 "A6: a second run succeeds ($($again.Text))"
    Check ($again.Text -match '(?m): 0 get it \(task 0, heading 0, knowledge 0\)') 'A6: no pass has anything to give'
    Check ($again.Text -match '(?m)^Decisions: 5 rows; 0 to apply, 2 applied, 1 kept\.') 'A6: and the decisions are applied'
    Equal (Get-Hash "$data\quests.jsonl") $hashes.Quests 'A6: it changes no byte of quests.jsonl'
    Equal (Get-Hash "$addon\qcQuestData.lua") $hashes.Lua 'A6: or of the Lua'

    # --- B: the real tables --------------------------------------------------------------------------
    $needed = 'QuestV2CliTask.csv', 'QuestInfo.csv', 'SkillLine.csv', 'QuestSort.csv', 'Item.csv', 'ItemSparse.csv', 'quest_api_cache'
    $missing = @($needed | Where-Object { -not (Test-Path (Join-Path $ToolsDir $_)) })
    if (-not (Get-ChildItem (Join-Path $ToolsDir 'retail_quest_cache_*.jsonl') -ErrorAction SilentlyContinue)) { $missing += 'retail_quest_cache_<build>.jsonl' }
    if ($MadeUpOnly) {
        Write-Output 'B was not run (-MadeUpOnly)'
    } elseif ($missing.Count) {
        $Skipped++
        Write-Output "SKIPPED B: $ToolsDir lacks $($missing -join ', '), so the real-table checks were not run (pass -ToolsDir <the main checkout's tools folder>)"
    } else {
        $real = "$Scratch\real"; New-Folder "$real\data"
        Copy-Item "$DataSource\quests.jsonl", "$DataSource\pins.jsonl" "$real\data"
        Copy-Addon "$real\addon" 'qcCore.lua', 'qcQuest.lua', 'qcPinDB.lua', 'qcQuestData.lua'
        $checkout = @{ Quests = Get-Hash "$real\data\quests.jsonl"; Lua = Get-Hash "$real\addon\qcQuestData.lua" }
        $common = @('-ToolsDir', $ToolsDir, '-DataDir', "$real\data", '-AddonDir', "$real\addon", '-DecisionsFile', $DecisionsSource)
        Assert-Sound 'B0' "$real\data" "$real\addon"
        $idle = Invoke-Tool ($common + '-WhatIf')
        Equal $idle.Exit 0 "B1: the run on the checkout's data succeeds ($($idle.Text))"
        Check ($idle.Text -match '(?m): 0 get it \(task 0, heading 0, knowledge 0\)') 'B1: no pass has anything left to give'
        Check ($idle.Text -match '(?m)^Decisions: \d+ rows; 0 to apply,') 'B1: and every decision is applied'
        foreach ($heading in "A pass's sources disagree, left out", 'Passes disagree, left out', 'Ours differs, left as it is', 'Decisions out of date', "Filed under another profession's heading") {
            Equal (Section $idle.Text $heading) '' "B1: nothing is listed under '$heading'"
        }

        # One quest or more of each pass and each kind of decision: the Midnight Silvermoon weeklies and
        # Dragonflight's knowledge quests (knowledge), Legion's and Pandaria's (heading), a task quest,
        # a Dragon Isles quest (SET from none), the Ub3r-Spanner (SET over ours, with its heading) and a
        # Tailoring quest under Leatherworking (SET of the heading alone).
        $original = @{}; foreach ($q in (Read-Quests "$real\data")) { $original[[int]$q.id] = $q }
        $taskQuest = (Import-Csv (Join-Path $ToolsDir 'QuestV2CliTask.csv') | Where-Object { [int]$_.FiltMinSkillID -and $original.ContainsKey([int]$_.ID) -and $original[[int]$_.ID].profession } | Select-Object -First 1).ID
        $stripped = @(93698, 93708, 93710, 93712, 72302, 38802, 40148, 31281, 31786, [int]$taskQuest, 72242)
        $reverted = @{ 53937 = @(4, 402); 53805 = @(128, 122) }
        foreach ($id in $stripped) { Check ($null -ne $original[$id].profession) "B2: $id has a profession to take out" }
        $records = Read-Quests "$real\data"
        foreach ($q in $records) {
            $id = [int]$q.id
            if ($stripped -contains $id) { $q.PSObject.Properties.Remove('profession') }
            if ($reverted.ContainsKey($id)) { Set-RecordField $q 'profession' $reverted[$id][0]; Set-RecordField $q 'category' $reverted[$id][1] }
        }
        Save-QuestData $records "$real\data" "$real\addon" | Out-Null
        $pinsHash = Get-Hash "$real\data\pins.jsonl"
        $back = Invoke-Tool $common
        Equal $back.Exit 0 "B3: the run after taking them out succeeds ($($back.Text))"
        Check ($back.Text -match "(?m): $($stripped.Count - 1) get it \(") "B3: the passes give back the $($stripped.Count - 1) they name ($($back.Text))"
        Check ($back.Text -match '(?m)^Decisions: \d+ rows; 3 to apply,') 'B3: and three decisions apply again'
        $now = @{}; foreach ($q in (Read-Quests "$real\data")) { $now[[int]$q.id] = $q }
        foreach ($id in ($stripped + @($reverted.Keys))) {
            Equal $now[$id].profession $original[$id].profession "B3: $id has its profession back"
            Equal $now[$id].category $original[$id].category "B3: $id is under its heading"
        }
        Equal (Get-Hash "$real\data\quests.jsonl") $checkout.Quests 'B3: quests.jsonl is byte for byte the checkout''s again'
        Equal (Get-Hash "$real\addon\qcQuestData.lua") $checkout.Lua 'B3: and so is the Lua'
        Equal (Get-Hash "$real\data\pins.jsonl") $pinsHash 'B3: the pins are untouched'
        Assert-Sound 'B3' "$real\data" "$real\addon"
        $hashes = @{ Quests = Get-Hash "$real\data\quests.jsonl"; Lua = Get-Hash "$real\addon\qcQuestData.lua" }
        $twice = Invoke-Tool $common
        Check ($twice.Exit -eq 0 -and $twice.Text -match '(?m): 0 get it \(') 'B4: a second run has nothing to give'
        Equal (Get-Hash "$real\data\quests.jsonl") $hashes.Quests 'B4: and changes no byte of quests.jsonl'
        Equal (Get-Hash "$real\addon\qcQuestData.lua") $hashes.Lua 'B4: or of the Lua'
    }
} finally {
    if (Test-Path $Scratch) { Remove-Item $Scratch -Recurse -Force }
}

Write-Output "$Passed checks passed, $Failed failed$(if ($Skipped) { ", $Skipped part skipped" })"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
