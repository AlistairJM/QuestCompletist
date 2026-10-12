<#
Gives retail quests the profession they need (the `profession` field of data\quests.jsonl), so "Hide
Other Profession Quests" hides a Mining quest from a character without Mining. Three passes each read
one kind of Blizzard data, and each names at most one profession for a quest:
  task       a world quest, bonus objective or calling: two columns of the client's QuestV2CliTask,
             which agree wherever both do (506 of 506 quests of ours in October 2026):
               - FiltMinSkillID, the skill the character needs, in the expansion's own line of the
                 profession (Legion Mining, Kul Tiran Herbalism, Shadowlands Cooking). The line's
                 SkillLine row gives its base profession as ParentSkillLineID.
               - QuestInfoID, whose QuestInfo row has the base profession's skill line (Herbalism
                 World Quest).
  heading    the profession heading Blizzard files the quest under (a QuestSort): the category of its
             record in Blizzard's API (tools\quest_api_cache, step 1) and the negative sort in the
             client's quest cache (tools\retail_quest_cache_<build>.jsonl, step 2e), which agree
             wherever both have one (1,030 quests of ours in October 2026). A heading is a
             profession's when its QuestSort name is the name of the profession's SkillLine row.
             Blizzard files quests this way up to Battle for Azeroth; from Dragonflight on its
             profession quests carry only the general "Professions" heading, which names none.
  knowledge  the profession knowledge the quest rewards: the items of its API record's guaranteed
             rewards that the client's Item table files as Miscellaneous, Other (class 15, subclass 4)
             and whose ItemSparse row needs a skill (Thalassian Miner's Notes needs Midnight Mining).
             Recipes, reagents and fishing poles need a skill too, but are other classes. In October
             2026 these items named one profession for each of the 179 quests that reward them, and
             agreed with the 121 we had tagged.
The base profession's bit is the one qcProfessionBits in qcCore.lua gives; a skill line with no bit
is listed.

Only a quest with no profession is given one. A quest whose profession differs from a pass's, or
whose passes name different professions, is listed and left as it is.

Some quests no pass names, and some our data has wrong, are decided by hand in -DecisionsFile
(docs\plans\quest-profession-decisions.csv; Profession is the Target's name, for reading):
  SET   gives the quest its Target profession (and its TargetCategory, when the row has one), where
        the data still has the row's Cur (and CurCategory); a quest already at the Target is left.
  KEEP  keeps the quest at Cur, the profession it has, though a pass names another: Blizzard filed it
        under a profession it doesn't need.
A row the data matches neither way, or for a quest not in the data, is listed as out of date.

Last, it lists the quests filed under a profession's heading in our own menu (qcCategoryClientName in
qcQuest.lua names the heading's skill line) whose profession is another one.

The skill level a quest asks for (FiltMinSkillValue) isn't read here: it belongs with the skill
requirements (qcQuestSkillRequirements), which retail doesn't fill yet (game-parity.md).

Reads tools\QuestV2CliTask.csv, QuestInfo.csv, SkillLine.csv, QuestSort.csv, Item.csv and
ItemSparse.csv, downloaded for -Build when they're missing or -Refresh is given. -Build is the build of
the newest tools\retail_quest_cache_<build>.jsonl unless given; without that build's cache the heading
pass reads the API alone, and says so. Safe to rerun: a second run changes nothing. With -WhatIf it only
reports; otherwise it saves through AddonData.ps1, which rebuilds the Lua.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-profession-decisions.csv'),
    [string]$Build = '',
    [int]$Examples = 25,
    [switch]$Refresh,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\QuestLevels.ps1"
Add-Type -AssemblyName Microsoft.VisualBasic

$Build = Resolve-RetailBuild $ToolsDir $Build
foreach ($table in 'QuestV2CliTask', 'QuestInfo', 'SkillLine', 'QuestSort', 'Item', 'ItemSparse') {
    $path = Join-Path $ToolsDir "$table.csv"
    if ($Refresh -or -not (Test-Path $path)) {
        Write-Output "Downloading $table for $Build..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$Build" -OutFile $path
        Start-Sleep -Seconds 1
    }
}

# The named columns of each row of a client table, without Import-Csv's cost on the large ones.
function Read-TableColumns([string]$path, [string[]]$columns) {
    $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser $path
    try {
        $parser.SetDelimiters(','); $parser.HasFieldsEnclosedInQuotes = $true
        $header = $parser.ReadFields()
        $at = @(foreach ($column in $columns) {
            $i = [array]::IndexOf($header, $column)
            if ($i -lt 0) { throw "$path has no '$column' column: Blizzard changed the table." }
            $i
        })
        while (-not $parser.EndOfData) {
            $fields = $parser.ReadFields()
            ,@(foreach ($i in $at) { $fields[$i] })
        }
    } finally { $parser.Close() }
}

$core = [IO.File]::ReadAllText((Join-Path $AddonDir 'qcCore.lua'))
$block = [regex]::Match($core, '(?s)qcProfessionBits = \{(.*?)\}').Groups[1].Value
$bitOf = @{}
foreach ($m in [regex]::Matches($block, '\[(\d+)\]\s*=\s*(\d+)')) { $bitOf[[int]$m.Groups[1].Value] = [int]$m.Groups[2].Value }
if ($bitOf.Count -eq 0) { throw "qcProfessionBits wasn't found in $AddonDir\qcCore.lua" }

$parent = @{}; $lineName = @{}
foreach ($row in @(Read-TableColumns (Join-Path $ToolsDir 'SkillLine.csv') 'ID', 'ParentSkillLineID', 'DisplayName_lang')) {
    $parent[[int]$row[0]] = [int]$row[1]; $lineName[[int]$row[0]] = $row[2]
}
# The bit of a skill line's profession, going up from an expansion's line to its base; 0 when there's none.
function Get-ProfessionBit([int]$line) {
    for ($step = 0; $line -gt 0 -and $step -lt 5; $step++) {
        if ($bitOf.ContainsKey($line)) { return $bitOf[$line] }
        $line = $parent[$line]
    }
    return 0
}
$bitName = @{}
foreach ($line in $bitOf.Keys) { if ($lineName[$line] -and -not $bitName.ContainsKey($bitOf[$line])) { $bitName[$bitOf[$line]] = $lineName[$line] } }
function Get-BitName([int]$bit) { if ($bitName.ContainsKey($bit)) { return "$($bitName[$bit]) ($bit)" } return "$bit" }

$records = Read-QuestData $DataDir
$quests = @{}
foreach ($q in $records) { $quests[[int]$q.id] = $q }

$problems = [ordered]@{}
function Add-Problem([string]$kind, [string]$text) {
    if (-not $problems.Contains($kind)) { $problems[$kind] = New-Object System.Collections.Generic.List[string] }
    $problems[$kind].Add($text)
}
function Get-QuestText([int]$id) { return "$id $($quests[$id].name)" }
$named = @{ task = @{}; heading = @{}; knowledge = @{} }

# --- task: QuestV2CliTask -----------------------------------------------------------------------------
$infoProfession = @{}
foreach ($row in @(Read-TableColumns (Join-Path $ToolsDir 'QuestInfo.csv') 'ID', 'Profession')) { if ([int]$row[1]) { $infoProfession[[int]$row[0]] = [int]$row[1] } }
$taskCount = 0
foreach ($task in @(Read-TableColumns (Join-Path $ToolsDir 'QuestV2CliTask.csv') 'ID', 'FiltMinSkillID', 'QuestInfoID')) {
    $id = [int]$task[0]
    if (-not $quests.ContainsKey($id)) { continue }
    $taskCount++
    $bySkill = 0; $byType = 0
    if ([int]$task[1]) {
        $bySkill = Get-ProfessionBit ([int]$task[1])
        if (-not $bySkill) { Add-Problem 'No profession bit for the skill line, left out' "$(Get-QuestText $id): skill line $($task[1])" }
    }
    $line = $infoProfession[[int]$task[2]]
    if ($line) {
        $byType = Get-ProfessionBit $line
        if (-not $byType) { Add-Problem 'No profession bit for the skill line, left out' "$(Get-QuestText $id): skill line $line of quest type $($task[2])" }
    }
    if ($bySkill -and $byType -and $bySkill -ne $byType) { Add-Problem "A pass's sources disagree, left out" "$(Get-QuestText $id): task, its skill filter says $(Get-BitName $bySkill), its quest type $(Get-BitName $byType)"; continue }
    $bit = if ($bySkill) { $bySkill } else { $byType }
    if ($bit) { $named.task[$id] = $bit }
}

# --- heading: the API's category and the quest cache's sort -------------------------------------------
$headingBit = @{}
foreach ($row in @(Read-TableColumns (Join-Path $ToolsDir 'QuestSort.csv') 'ID', 'SortName_lang')) {
    foreach ($line in $bitOf.Keys) { if ($lineName[$line] -and $lineName[$line] -eq $row[1]) { $headingBit[[int]$row[0]] = $bitOf[$line] } }
}
if ($headingBit.Count -eq 0) { throw "No QuestSort row has a profession's name: has Blizzard changed QuestSort.csv or SkillLine.csv?" }
$apiDir = Join-Path $ToolsDir 'quest_api_cache'
$apiCategory = @{}; $apiRecords = 0; $rewardFiles = New-Object System.Collections.Generic.List[int]
$categoryRx = New-Object Text.RegularExpressions.Regex '"category":\{"key":\{"href":"[^"]*"\},"name":"(?:[^"\\]|\\.)*","id":(\d+)\}'
foreach ($id in $quests.Keys) {
    $path = Join-Path $apiDir "$id.json"
    if (-not [IO.File]::Exists($path)) { continue }
    $apiRecords++
    $text = [IO.File]::ReadAllText($path)
    $m = $categoryRx.Match($text)
    if ($m.Success) { $apiCategory[$id] = [int]$m.Groups[1].Value }
    if ($text.Contains('"items":{"items":')) { $rewardFiles.Add($id) }
}
$cacheSort = @{}
$cacheFile = Join-Path $ToolsDir "retail_quest_cache_$Build.jsonl"
$sortRx = New-Object Text.RegularExpressions.Regex '^\{"id":(\d+),"title":"(?:[^"\\]|\\.)*",.*?"sort":(-?\d+)[,}]'
if (Test-Path $cacheFile) {
    foreach ($line in [IO.File]::ReadLines($cacheFile)) {
        $m = $sortRx.Match($line)
        if ($m.Success -and [int]$m.Groups[2].Value -lt 0) { $cacheSort[[int]$m.Groups[1].Value] = -[int]$m.Groups[2].Value }
    }
} else {
    Write-Output "No quest cache for $Build (retail_quest_cache_$Build.jsonl): the heading pass reads the API alone."
}
foreach ($id in $quests.Keys) {
    $byApi = if ($apiCategory.ContainsKey($id)) { [int]$headingBit[$apiCategory[$id]] } else { 0 }
    $byCache = if ($cacheSort.ContainsKey($id)) { [int]$headingBit[$cacheSort[$id]] } else { 0 }
    if ($byApi -and $byCache -and $byApi -ne $byCache) { Add-Problem "A pass's sources disagree, left out" "$(Get-QuestText $id): heading, the API's says $(Get-BitName $byApi), the quest cache's $(Get-BitName $byCache)"; continue }
    $bit = if ($byApi) { $byApi } else { $byCache }
    if ($bit) { $named.heading[$id] = $bit }
}

# --- knowledge: the profession knowledge a quest rewards ----------------------------------------------
$knowledgeItems = @{}
foreach ($row in @(Read-TableColumns (Join-Path $ToolsDir 'Item.csv') 'ID', 'ClassID', 'SubclassID')) { if ($row[1] -eq '15' -and $row[2] -eq '4') { $knowledgeItems[[int]$row[0]] = 0 } }
foreach ($row in @(Read-TableColumns (Join-Path $ToolsDir 'ItemSparse.csv') 'ID', 'RequiredSkill')) {
    $item = [int]$row[0]
    if ($knowledgeItems.ContainsKey($item)) { $knowledgeItems[$item] = [int]$row[1] }
}
foreach ($id in $rewardFiles) {
    $record = [IO.File]::ReadAllText((Join-Path $apiDir "$id.json")) | ConvertFrom-Json
    $bits = @(@(foreach ($reward in @($record.rewards.items.items)) {
        $item = [int]$reward.item.id
        if (-not $knowledgeItems[$item]) { continue }
        $bit = Get-ProfessionBit $knowledgeItems[$item]
        if (-not $bit) { Add-Problem 'No profession bit for the skill line, left out' "$(Get-QuestText $id): skill line $($knowledgeItems[$item]) of reward $item $($reward.item.name)"; continue }
        $bit
    }) | Sort-Object -Unique)
    if ($bits.Count -gt 1) { Add-Problem "A pass's sources disagree, left out" "$(Get-QuestText $id): knowledge, its rewards need $((@($bits | ForEach-Object { Get-BitName $_ })) -join ' and ')"; continue }
    if ($bits.Count -eq 1) { $named.knowledge[$id] = $bits[0] }
}

# --- decisions ----------------------------------------------------------------------------------------
$decided = @{}
$decisionRows = @(Import-Csv $DecisionsFile -Encoding UTF8)
foreach ($row in $decisionRows) {
    $id = [int]$row.QuestID
    if ($decided.ContainsKey($id)) { throw "$DecisionsFile has quest $id twice." }
    $decided[$id] = $row
}
$counts = [ordered]@{ set = 0; same = 0; decided = 0; kept = 0 }
$changes = New-Object System.Collections.Generic.List[object]
foreach ($id in ($decided.Keys | Sort-Object)) {
    $row = $decided[$id]
    if (-not $quests.ContainsKey($id)) { Add-Problem 'Decisions out of date' "$id $($row.Name): $($row.Decision) row for a quest not in the data"; continue }
    $q = $quests[$id]
    $profession = [int]$q.profession; $category = [int]$q.category
    if ($row.Decision -eq 'SET') {
        $atTarget = $profession -eq [int]$row.Target -and (-not $row.TargetCategory -or $category -eq [int]$row.TargetCategory)
        $atCur = $profession -eq [int]$row.Cur -and (-not $row.CurCategory -or $category -eq [int]$row.CurCategory)
        if ($atTarget) { $counts.decided++ }
        elseif ($atCur) {
            $changes.Add([pscustomobject]@{ Quest = $q; Bit = [int]$row.Target; Category = $row.TargetCategory; Why = 'decision' })
        } else { Add-Problem 'Decisions out of date' "$(Get-QuestText $id): SET row says $($row.Cur)/$($row.CurCategory) to $($row.Target)/$($row.TargetCategory), the data has $profession/$category" }
    } elseif ($row.Decision -eq 'KEEP') {
        if ($profession -eq [int]$row.Cur) { $counts.kept++ }
        else { Add-Problem 'Decisions out of date' "$(Get-QuestText $id): KEEP row says $($row.Cur), the data has $profession" }
    } else { Add-Problem 'Decisions out of date' "$(Get-QuestText $id): decision '$($row.Decision)' is not SET or KEEP" }
}

# --- what the passes give -----------------------------------------------------------------------------
$byPass = [ordered]@{ task = 0; heading = 0; knowledge = 0 }
$namedIds = @{}
foreach ($pass in $named.Keys) { foreach ($id in $named[$pass].Keys) { $namedIds[$id] = $true } }
foreach ($id in ($namedIds.Keys | Sort-Object)) {
    if ($decided.ContainsKey($id)) { continue }
    $says = [ordered]@{}
    foreach ($pass in 'task', 'heading', 'knowledge') { if ($named[$pass].ContainsKey($id)) { $says[$pass] = $named[$pass][$id] } }
    if (@($says.Values | Sort-Object -Unique).Count -gt 1) {
        Add-Problem 'Passes disagree, left out' "$(Get-QuestText $id): $((@($says.Keys | ForEach-Object { "$_ $(Get-BitName $says[$_])" })) -join ', ')"
        continue
    }
    $bit = @($says.Values)[0]
    $current = [int]$quests[$id].profession
    if ($current -eq $bit) { $counts.same++ }
    elseif ($current) { Add-Problem 'Ours differs, left as it is' "$(Get-QuestText $id): ours $(Get-BitName $current), $((@($says.Keys)) -join ' and ') $(Get-BitName $bit)" }
    else {
        $pass = @($says.Keys)[0]
        $byPass[$pass]++; $counts.set++
        $changes.Add([pscustomobject]@{ Quest = $quests[$id]; Bit = $bit; Category = ''; Why = (@($says.Keys) -join '+') })
    }
}

# --- headings in our menu -----------------------------------------------------------------------------
$menu = [IO.File]::ReadAllText((Join-Path $AddonDir 'qcQuest.lua'))
$headingOf = @{}
foreach ($m in [regex]::Matches($menu, '\[(\d+)\]=\{"skill",(\d+)\}')) { $bit = Get-ProfessionBit ([int]$m.Groups[2].Value); if ($bit) { $headingOf[[int]$m.Groups[1].Value] = $bit } }
$after = @{}
foreach ($change in $changes) { $after[[int]$change.Quest.id] = $change }
foreach ($q in $records) {
    $id = [int]$q.id
    $profession = [int]$q.profession; $category = [int]$q.category
    if ($after.ContainsKey($id)) { $profession = $after[$id].Bit; if ($after[$id].Category) { $category = [int]$after[$id].Category } }
    $heading = $headingOf[$category]
    if ($heading -and $profession -and ($profession -band ($profession - 1)) -eq 0 -and $profession -ne $heading) {
        Add-Problem "Filed under another profession's heading" "$(Get-QuestText $id): $(Get-BitName $profession), filed under $(Get-BitName $heading) ($category)"
    }
}

"Build $Build. Task quests of ours: $taskCount; the API has $apiRecords of our quests; $($headingBit.Count) headings name a profession; $(@($knowledgeItems.Values | Where-Object { $_ }).Count) knowledge items need a skill."
"The passes name a profession for {0} quests (task {1}, heading {2}, knowledge {3}): {4} get it (task {5}, heading {6}, knowledge {7}), {8} already have it." -f
    $namedIds.Count, $named.task.Count, $named.heading.Count, $named.knowledge.Count, $counts.set, $byPass.task, $byPass.heading, $byPass.knowledge, $counts.same
"Decisions: {0} rows; {1} to apply, {2} applied, {3} kept." -f $decided.Count, @($changes | Where-Object { $_.Why -eq 'decision' }).Count, $counts.decided, $counts.kept
foreach ($kind in $problems.Keys) {
    "${kind} ($($problems[$kind].Count)):"
    $problems[$kind] | ForEach-Object { "  $_" }
}
if ($WhatIf) {
    if ($changes.Count) { "Would change ($($changes.Count)):" }
    foreach ($change in ($changes | Select-Object -First $Examples)) {
        $moved = if ($change.Category) { ", category $($change.Category)" } else { '' }
        "  {0} {1}: {2}{3} ({4})" -f $change.Quest.id, $change.Quest.name, (Get-BitName $change.Bit), $moved, $change.Why
    }
    if ($changes.Count -gt $Examples) { "  ... and $($changes.Count - $Examples) more" }
    return
}
if ($changes.Count -eq 0) { return }
foreach ($change in $changes) {
    Set-RecordField $change.Quest 'profession' $change.Bit
    if ($change.Category) { Set-RecordField $change.Quest 'category' ([int]$change.Category) }
}
Save-QuestData $records $DataDir $AddonDir
