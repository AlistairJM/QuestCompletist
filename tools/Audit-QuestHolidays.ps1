<#
Report-only. Checks retail's holiday tags, the `holiday` field of data\quests.jsonl, so a quest that
belongs to a holiday and carries no tag, or the wrong one, is found every sweep. Makes no edits.

A tag is a flag of qcHolidays in QuestCompletist\qcCore.lua, read from there with the IDs of the
game's Holidays table each holiday's calendar event carries. Three signals, each independent:
  API       the quest's category in Blizzard's API (tools\quest_api_cache, from Audit-QuestAccuracy.ps1):
            Brewfest, Lunar Festival... Its general "Seasonal" category names no holiday.
  Event     the game event TrinityCore puts the quest in (game_event_seasonal_questrelation,
            game_event_creature_quest, game_event_gameobject_quest, in the newest
            tools\tdb\TDB_full_world_*.sql), and that event's holiday: game_event.holiday is a Holidays
            ID qcHolidays lists, and an event with none goes by its description ("Winter Veil: Gifts").
  Category  the heading our data files the quest under (qcQuestCategories in qcQuest.lua).
A signal names a holiday when its name is a name in qcHolidays, or one of the few spellings $aliases
lists. The run prints every API category and event it read as a holiday, so a spelling that stopped
matching shows as a name missing from that list. It can only see holidays qcHolidays has a flag for.

Findings, each a row of -OutFile (Kind, Quest, Name, Tag, Says, Detail, Decision, Covered):
  untagged        no tag, and a signal names a holiday
  wrong tag       a tag, and a signal names another holiday
  untagged, an event with no flag    no tag, and TrinityCore has the quest in an event that names no
                  holiday qcHolidays has (New Year's Eve)
  decision not applied      a SET or CORRECT row of the decisions file says the tag is its Target,
                  and the data has another
  decision out of date      a PENDING row says the quest is untagged (its Cur), or a KEEP row that the
                  tag is its Target, and the data has another
  decision for a quest not in the data    a SET or CORRECT row
A finding is covered, and not counted as new, by a row of -DecisionsFile
(docs\plans\quest-holiday-decisions.csv): a PENDING row for the same holiday while the quest is still
untagged, or a KEEP row while its tag is still the row's Target. Exits with 1 when any finding is not
covered.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$TdbFile = "",
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-holiday-decisions.csv'),
    [string]$OutFile = "",
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\AddonData.ps1"
if (-not $OutFile) { $OutFile = "$ToolsDir\quest_holiday_audit.csv" }

$quests = @{}
foreach ($q in (Read-QuestData $DataDir)) { $quests[[int]$q.id] = $q }

$core = [IO.File]::ReadAllText((Join-Path $AddonDir 'qcCore.lua'))
$block = [regex]::Match($core, '(?s)local qcHolidays = \{(.*?)\r?\n\}').Groups[1].Value
$holidays = @(foreach ($e in [regex]::Matches($block, '\{flag=(\d+), name="((?:[^"\\]|\\.)*)", eventIDs=\{([\d, ]*)\}(?:, filter="\w+")?\}')) {
    [pscustomobject]@{ Flag = [int]$e.Groups[1].Value; Name = $e.Groups[2].Value
        Ids = @($e.Groups[3].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
})
if ($holidays.Count -eq 0 -or $holidays.Count -ne ([regex]::Matches($block, 'flag=')).Count) { throw "qcHolidays wasn't read whole from $AddonDir\qcCore.lua" }

function Get-Key([string]$name) { return ($name -replace '[\u2019'']', '').Trim().ToLowerInvariant() -replace '\s+', ' ' }
# Names Blizzard's API and our headings give a holiday that qcHolidays spells otherwise.
$aliases = [ordered]@{ 'Midsummer' = 'Midsummer Fire Festival'; 'Winter Veil' = 'Feast of Winter Veil'
    "Ahn'Qiraj War" = "Ahn'Qiraj War Effort"; 'Invasion' = 'Scourge Invasion'; 'Hearthstone Anniversary' = "Hearthstone's 10th Anniversary" }
$byName = @{}; $byEventId = @{}; $holidayOfFlag = @{}
foreach ($h in $holidays) {
    $byName[(Get-Key $h.Name)] = $h; $holidayOfFlag[$h.Flag] = $h
    foreach ($id in $h.Ids) { $byEventId[$id] = $h }
}
foreach ($alias in $aliases.Keys) {
    $target = $byName[(Get-Key $aliases[$alias])]
    if (-not $target) { throw "The alias '$alias' names '$($aliases[$alias])', which qcHolidays lacks." }
    $byName[(Get-Key $alias)] = $target
}
function Find-Holiday([string]$name) { return $byName[(Get-Key $name)] }
function Get-TagName([int]$tag) { if ($tag -eq 0) { return 'none' } if ($holidayOfFlag.ContainsKey($tag)) { return $holidayOfFlag[$tag].Name } return "flag $tag" }

$questText = [IO.File]::ReadAllText((Join-Path $AddonDir 'qcQuest.lua'))
$block = [regex]::Match($questText, '(?s)qcQuestCategories\s*=\s*\{\r?\n(.*?)\r?\n\}').Groups[1].Value
$categoryName = @{}
foreach ($m in [regex]::Matches($block, '\{(-?\d+),"((?:[^"\\]|\\.)*)"\}')) { $categoryName[[int]$m.Groups[1].Value] = $m.Groups[2].Value }
if ($categoryName.Count -eq 0) { throw "qcQuest.lua has no qcQuestCategories table." }

# Blizzard's API: each cached quest's category name.
$apiCategory = @{}; $apiRecords = 0
$cacheDir = Join-Path $ToolsDir 'quest_api_cache'
if (Test-Path $cacheDir) {
    $pattern = New-Object Text.RegularExpressions.Regex('"category":\{"key":\{"href":"[^"]*"\},"name":"((?:[^"\\]|\\.)*)","id":\d+\}')
    foreach ($file in [IO.Directory]::EnumerateFiles($cacheDir, '*.json')) {
        $id = 0
        if (-not [int]::TryParse([IO.Path]::GetFileNameWithoutExtension($file), [ref]$id) -or -not $quests.ContainsKey($id)) { continue }
        $apiRecords++
        $m = $pattern.Match([IO.File]::ReadAllText($file))
        if ($m.Success) { $apiCategory[$id] = [regex]::Unescape($m.Groups[1].Value) }
    }
}

# TrinityCore: each game event's holiday and description, and the events each quest is in. Columns are
# found by name in the dump's CREATE TABLE, so a schema change stops the run instead of shifting them.
if (-not $TdbFile) {
    $TdbFile = Get-ChildItem "$ToolsDir\tdb\TDB_full_world_*.sql" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName
}
$events = @{}; $questEvents = @{}
if ($TdbFile) {
    $wanted = 'game_event', 'game_event_seasonal_questrelation', 'game_event_creature_quest', 'game_event_gameobject_quest'
    $layout = @{}
    $reader = New-Object IO.StreamReader($TdbFile)
    try {
        while ($layout.Count -lt $wanted.Count -and $null -ne ($line = $reader.ReadLine())) {
            if ($line -match '^CREATE TABLE `(\w+)` \(' -and $wanted -contains $Matches[1]) {
                $table = $Matches[1]
                $columns = New-Object System.Collections.Generic.List[string]
                while ($null -ne ($line = $reader.ReadLine()) -and $line -match '^\s+`(\w+)` ') { $columns.Add($Matches[1]) }
                $layout[$table] = $columns
            }
        }
    } finally { $reader.Close() }
    function Read-DumpTable([string]$table, [string[]]$columns) {
        if (-not $layout.ContainsKey($table)) { throw "$TdbFile has no table $table." }
        $numbers = foreach ($column in $columns) {
            $at = $layout[$table].IndexOf($column)
            if ($at -lt 0) { throw "$table in $TdbFile has no column ${column}: TrinityCore changed it, so update this tool." }
            $at + 1
        }
        $rows = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $TdbFile $table ($numbers -join ',')); if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $table" }
        return $rows
    }
    $outputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try {
        foreach ($row in (Read-DumpTable 'game_event' 'eventEntry', 'holiday', 'description')) {
            $f = $row.Split("`t")
            $events[[int]$f[0]] = [pscustomobject]@{ Holiday = [int]$f[1]; Description = $f[2].Trim() }
        }
        foreach ($spec in @(@('game_event_seasonal_questrelation', 'questId'), @('game_event_creature_quest', 'quest'), @('game_event_gameobject_quest', 'quest'))) {
            foreach ($row in (Read-DumpTable $spec[0] @($spec[1], 'eventEntry'))) {
                $f = $row.Split("`t")
                if (-not $questEvents.ContainsKey([int]$f[0])) { $questEvents[[int]$f[0]] = New-Object System.Collections.Generic.SortedSet[int] }
                [void]$questEvents[[int]$f[0]].Add([int]$f[1])
            }
        }
    } finally { [Console]::OutputEncoding = $outputEncoding }
}
function Get-EventHoliday([int]$id) {
    $event = $events[$id]
    if (-not $event) { return $null }
    if ($event.Holiday -and $byEventId.ContainsKey($event.Holiday)) { return $byEventId[$event.Holiday] }
    return Find-Holiday ($event.Description -split ':')[0]
}
function Get-EventLabel([int]$id) { if ($events.ContainsKey($id)) { return "event $id '$($events[$id].Description)'" } return "event $id" }

$decisions = @{}
foreach ($row in (Import-Csv $DecisionsFile -Encoding UTF8)) {
    if ($decisions.ContainsKey($row.QuestID)) { throw "$DecisionsFile has quest $($row.QuestID) twice." }
    $decisions[$row.QuestID] = $row
}

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding([string]$kind, [int]$id, [int]$tag, [string]$says, [string]$detail, [string]$covered) {
    $row = $decisions["$id"]
    $findings.Add([pscustomobject]@{ Kind = $kind; Quest = "$id"; Name = $(if ($quests.ContainsKey($id)) { $quests[$id].name } else { $row.Name })
        Tag = Get-TagName $tag; Says = $says; Detail = $detail; Decision = [string]$row.Decision; Covered = $covered })
}
function Test-SameHoliday([string]$a, [string]$b) {
    $ha = Find-Holiday $a; $hb = Find-Holiday $b
    return (Get-Key $a) -eq (Get-Key $b) -or ($ha -and $hb -and $ha.Flag -eq $hb.Flag)
}
function Get-Covered($row, [int]$tag, [string[]]$says) {
    if ($row.Decision -eq 'KEEP' -and $tag -eq [int]$row.Target) { return 'KEEP' }
    if ($row.Decision -eq 'PENDING' -and $tag -eq [int]$row.Cur -and @($says | Where-Object { -not (Test-SameHoliday $_ $row.Holiday) }).Count -eq 0) { return 'PENDING' }
    return ''
}

$readAsHoliday = @{ API = @{}; Event = @{}; Category = @{} }
$unflaggedEvents = @{}
$signalQuests = @{ API = 0; Event = 0; Category = 0 }
foreach ($id in ($quests.Keys | Sort-Object)) {
    $q = $quests[$id]
    $tag = [int]$q.holiday
    $named = New-Object System.Collections.Generic.List[object]
    $unflagged = New-Object System.Collections.Generic.List[string]
    $api = $apiCategory[$id]
    if ($api) {
        $h = Find-Holiday $api
        if ($h) { $named.Add([pscustomobject]@{ Holiday = $h; Text = "API category '$api'" }); $readAsHoliday.API[$api] = $h.Name; $signalQuests.API++ }
    }
    if ($questEvents.ContainsKey($id)) {
        $hit = $false
        foreach ($eventId in $questEvents[$id]) {
            $h = Get-EventHoliday $eventId
            if ($h) { $named.Add([pscustomobject]@{ Holiday = $h; Text = "TrinityCore $(Get-EventLabel $eventId)" }); $readAsHoliday.Event[$eventId] = $h.Name; $hit = $true }
            else { $unflagged.Add($(if ($events.ContainsKey($eventId)) { $events[$eventId].Description } else { "event $eventId" })); $unflaggedEvents[$eventId] += 1 }
        }
        if ($hit) { $signalQuests.Event++ }
    }
    $heading = $categoryName[[int]$q.category]
    if ($heading) {
        $h = Find-Holiday $heading
        if ($h) { $named.Add([pscustomobject]@{ Holiday = $h; Text = "category '$heading'" }); $readAsHoliday.Category[$heading] = $h.Name; $signalQuests.Category++ }
    }
    if ($named.Count -eq 0 -and $unflagged.Count -eq 0) { continue }
    $row = $decisions["$id"]
    $detail = (@($named | ForEach-Object { $_.Text }) + @($unflagged | ForEach-Object { "TrinityCore event '$_', which has no flag" })) -join '; '
    if ($tag -eq 0) {
        if ($named.Count) {
            $says = @($named | ForEach-Object { $_.Holiday.Name } | Sort-Object -Unique)
            Add-Finding 'untagged' $id $tag ($says -join ' | ') $detail (Get-Covered $row $tag $says)
        } else {
            $says = @($unflagged | Sort-Object -Unique)
            Add-Finding 'untagged, an event with no flag' $id $tag ($says -join ' | ') $detail (Get-Covered $row $tag $says)
        }
    } else {
        $others = @($named | Where-Object { $_.Holiday.Flag -ne $tag } | ForEach-Object { $_.Holiday.Name } | Sort-Object -Unique)
        if ($others.Count) { Add-Finding 'wrong tag' $id $tag ($others -join ' | ') $detail (Get-Covered $row $tag $others) }
    }
}

foreach ($row in ($decisions.Values | Sort-Object { [int]$_.QuestID })) {
    $id = [int]$row.QuestID
    if (-not $quests.ContainsKey($id)) {
        if ($row.Decision -in 'SET', 'CORRECT') { Add-Finding 'decision for a quest not in the data' $id 0 $row.Holiday "$($row.Decision) row" '' }
        continue
    }
    $tag = [int]$quests[$id].holiday
    $says = [string]$row.Holiday
    if ($row.Decision -in 'SET', 'CORRECT') {
        if ($tag -ne [int]$row.Target) { Add-Finding 'decision not applied' $id $tag $says "$($row.Decision) row says $(Get-TagName ([int]$row.Target)) ($($row.Target))" '' }
    } elseif ($row.Decision -eq 'PENDING') {
        if ($tag -ne [int]$row.Cur) { Add-Finding 'decision out of date' $id $tag $says "PENDING row says $(Get-TagName ([int]$row.Cur)) ($($row.Cur))" '' }
    } elseif ($row.Decision -eq 'KEEP') {
        if ($tag -ne [int]$row.Target) { Add-Finding 'decision out of date' $id $tag $says "KEEP row says $(Get-TagName ([int]$row.Target)) ($($row.Target))" '' }
    } else {
        Add-Finding 'decision out of date' $id $tag $says "decision '$($row.Decision)' is not SET, CORRECT, PENDING or KEEP" ''
    }
}

$findings | Sort-Object Kind, { [int]$_.Quest } | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8

"Quests: {0} in the data, {1} tagged; qcHolidays has {2} holidays; the decisions file has {3} rows." -f $quests.Count, @($quests.Values | Where-Object { $_.holiday }).Count, $holidays.Count, $decisions.Count
if (Test-Path $cacheDir) {
    "API: {0} of our quests are in the cache; {1} are in a category read as a holiday." -f $apiRecords, $signalQuests.API
    "  categories read as holidays: " + (($readAsHoliday.API.Keys | Sort-Object | ForEach-Object { "$_ -> $($readAsHoliday.API[$_])" }) -join '; ')
} else { "API: no tools\quest_api_cache, so its signal was skipped." }
if ($TdbFile) {
    "TrinityCore ({0}): {1} of our quests are in a game event; {2} are in one read as a holiday." -f (Split-Path -Leaf $TdbFile), @($questEvents.Keys | Where-Object { $quests.ContainsKey($_) }).Count, $signalQuests.Event
    "  events read as holidays: " + (($readAsHoliday.Event.Keys | Sort-Object | ForEach-Object { "$_ $($events[$_].Description) -> $($readAsHoliday.Event[$_])" }) -join '; ')
    "  events with our quests that name no holiday: " + $(if ($unflaggedEvents.Count) { (($unflaggedEvents.Keys | Sort-Object | ForEach-Object { "$_ $($events[$_].Description) ($($unflaggedEvents[$_]))" }) -join '; ') } else { 'none' })
} else { "TrinityCore: no TDB_full_world_*.sql in tools\tdb, so its signal was skipped." }
"Headings: {0} of our quests are filed under a heading read as a holiday: {1}." -f $signalQuests.Category, (($readAsHoliday.Category.Keys | Sort-Object | ForEach-Object { "$_ -> $($readAsHoliday.Category[$_])" }) -join '; ')
$undecided = @($findings | Where-Object { -not $_.Covered })
$findings | Group-Object Kind | Sort-Object Name | ForEach-Object {
    $new = @($_.Group | Where-Object { -not $_.Covered }).Count
    "  {0}: {1}{2}" -f $_.Name, $_.Count, $(if ($new -ne $_.Count) { " ($new new)" } else { '' })
}
foreach ($f in ($undecided | Select-Object -First 50)) { "NEW  {0}  {1} {2}: tag {3}, says {4} ({5})" -f $f.Kind, $f.Quest, $f.Name, $f.Tag, $f.Says, $f.Detail }
if ($undecided.Count -gt 50) { "... and $($undecided.Count - 50) more in the report" }
"Findings: $($findings.Count), of which new: $($undecided.Count). Written to $OutFile"
if ($undecided.Count -gt 0) { exit 1 }
