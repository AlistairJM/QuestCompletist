<#
Builds WoW: Forever's quest and pin data, data\forever\quests.jsonl and pins.jsonl, from seven sources
(docs/plans/forever.md, phase 3):

  - the client's tables for -Build (left out, the build of the newest tools\forever_probe_<revision>
    results, which the cache and the probe's answers must share): the quests the game records as completed (QuestV2), where
    some start (QuestPOIBlob and QuestPOIPoint), the classes (ChrClasses) and the items that start quests (ItemSparse);
  - the quest cache file Read-QuestCache.ps1 writes: what the server says about each quest it
    answered;
  - CMaNGOS's vanilla database (cmangos/classic-db, Full_DB, GPL-3.0): the old world, including the
    quests the beta didn't answer, and who starts each quest and where they stand;
  - the beta probe's saved variables: which quests failed and the game's NPC names;
  - the recorder's ledger, -LedgerFile (docs\plans\recorded-quest-givers.csv, which step 6d,
    Import-RecordedGivers.ps1, fills from the probe's files and the addon's own notes): the quest givers
    met in the game, where they stood, their English names and the quests they offered. Only what the
    maintainer's own files saw, or two different players did, counts (RecordedGivers.ps1 decides). The
    probe's own recorder notes are not read from its file: if the file holds a giver, spot or offer
    the ledger lacks (step 6d was not run on it), the run stops, so a ledger behind the probe's file
    can't silently drop its newest givers (of the versions -Builds counts). Only the probe's file is checked: the addon's own file and
    players' files are not, and for them the import relies on step 10's item 1 in maintenance.md
    (step 6d first). The file is read the way step 6d reads it, so -Builds (default: the versions
    the TOCs in -AddonDir name) says which of its builds count;
  - -GiverFile and -ZoneFile, docs\plans\forever-quest-givers.csv and forever-quest-zones.csv:
    givers and zones looked up by hand on Wowhead's Forever pages, for quests the other sources
    can't place. A listed NPC stands where CMaNGOS or the recorder puts it.
    A Decision column (ADD, the default, or REMOVE) lets a row take a starter CMaNGOS lists off a quest too,
    for a giver the dump has the wrong way round (classic-db update 4777 swaps those of quests 26 and 27).
  - -HolidayFile, docs\plans\forever-quest-holiday-decisions.csv: the holiday of quests no other
    source ties to one, with the evidence for each (Quest, Name, Holiday, Decision, Evidence). Holiday
    is a name in qcHolidays in qcCore.lua and Decision is SET.
  - -LinkFile, docs\plans\forever-quest-link-decisions.csv: links the other sources get wrong, with
    the evidence for each (Quest, Name, Link, Other, Decision, Evidence). A prereq row SETs Other as
    the quest's prerequisite, and several for one quest make a choice, any one of which will do; or
    it REMOVEs Other, the prerequisite the other sources give, and the quest line order doesn't put
    it back. An exclusive row ADDs Other to the quests the quest shuts out, or REMOVEs it, both ways
    round. A breadcrumb row ADDs Other to the quest's breadcrumbs: it closes once the quest is done.
  - -ClassFile, docs\plans\forever-quest-class-decisions.csv: the class of quests no other source
    limits, with the evidence for each (Quest, Name, Class, Decision, Evidence). Class is one or
    more of the client's class names (ChrClasses), separated by commas, and Decision is SET.

The game wins wherever it speaks. Title, level, minimum level, zone, recurrence and race restrictions
come from the cache when it has the quest, a recorded place wins over CMaNGOS's spawns for that giver, and NPC
names come from the probe. A quest's givers are CMaNGOS's, the recorder's and the hand list's together, but a
listed giver the recorder didn't see offer the quest, when it saw another giver do so, is left out.
Quests with internal titles ("<UNUSED>", "[DNT]" and the like, and test quests only the game knows)
are left out.
The beta's answers differ between runs, whatever the build: about 80 of 7,320 quests are answered in one
run and refused in the next. So the game's last record of every quest it has ever answered is kept in
-AnswerFile (data\forever\answers.jsonl), with how many runs in a row it has gone unanswered (a run is
one client build's quest cache, and a quest the probe didn't ask about isn't counted). A quest the
game doesn't answer now keeps its last record and is listed for review; it only stops being imported
after -MaxMissedRuns (10) runs in a row. With no answer file, it is made from the forever_quest_cache_<build>.jsonl
files in -ToolsDir.
Nothing leaves the data unseen. Before it writes anything, the importer compares its quests with
the ones in -DataDir, and a quest that would go (it missed -MaxMissedRuns runs, its title is internal,
CMaNGOS dropped it) is listed, in -RemovalsFile (tools\quest_removals_forever.csv) too, and the
run stops until -DecisionsFile (docs\plans\quest-removal-decisions.csv) has a row for it: REMOVE lets
it go, KEEP keeps it from its last record whatever else would drop it. Review the list with the user first.
QuestV2 isn't a list of every quest: a repeatable quest is never recorded as completed, so it has no
row. CMaNGOS's repeatable quests are kept without one; any other CMaNGOS quest QuestV2 lacks is left
out until the game answers for it. With no row, a quest the probe asked about that failed at level 1
to 35, where the beta answers nearly every quest, is left out too, until the game answers for it.
Every kept quest QuestV2 lacks is listed for review.

The files follow data\quests.jsonl and pins.jsonl (see AddonData.ps1), with Forever's values:
  level     the quest's own level: the game's, else CMaNGOS's QuestLevel.
  minLevel  the level a character needs to take the quest: the game's, else CMaNGOS's MinLevel, as
            given (0 is kept, for no minimum). Left out where it is the quest's level.
  pvp       1 where the game's record calls the quest PvP (its questInfo is 41), else, for a quest the game hasn't
            answered, where CMaNGOS's Type is 41; -PvpFile (docs\plans\quest-pvp-decisions.csv) decides first; as Sync-QuestPvP.ps1 sets it.
  category  Blizzard's own: the zone's AreaTable ID, or the negative QuestSort ID for class,
            profession, holiday and Forever's other headings; CMaNGOS's when the game's record
            has none; 0 for none, or for an area the client's AreaTable doesn't have. A quest
            filed under an area named after an instance (Gnomeregan in Dun Morogh) gets the
            instance's own area; one filed under any other subzone (Valley of Trials) gets its
            zone, as retail's categories are zones. A heading that isn't a place, a race's (Night
            Elf), Treasure Map, Epic or Legendary, gives way to the zone forever-quest-zones.csv
            gives the quest, else the zone of its pins' map, else that of the NPC CMaNGOS has it
            handed in to, else CMaNGOS's zone, else 0. The Commendation
            Signets' turn-ins, under the Reputation heading, go under Ahn'Qiraj War: the war
            effort's supply quests give the signets, and its officers take them. zone is its name.
  faction   1 Alliance, 2 Horde, 3 both: from the cache's race restriction, else the side the game names
            in the probe (GetQuestFactionGroup), else CMaNGOS's race restriction. Step 10's
            Sync-QuestSides.ps1 narrows a quest open to both whose givers are one side's, in sides.jsonl.
  race      0 for any race, since faction already gates; otherwise the addon's race bits, with
            Skyborne (races 95 and 96) as 67108864.
  class     the game's class mask (1 shifted left by the class ID less one): -ClassFile's, else
            that of the items that start the quest, when no NPC or object does and the client's
            ItemSparse lets only some classes use them, else CMaNGOS's, else a class heading's;
            8191 for any. The game's quest records carry no class. A quest whose only prerequisite
            is for some classes is for them too, as the addon counts a prerequisite the character
            can't take as met.
  type      4 daily, 128 weekly, 2 repeatable, 64 seasonal, 32 profession or 1, the first that
            applies, so a repeatable holiday or profession quest is repeatable, as on retail. holiday
            and profession hold the addon's flags.
  holiday   CMaNGOS's holiday for the quest, or for its heading; failing that, the holiday or event
            all its givers, NPCs and objects, stand only during. Events with no holiday of their
            own go by their description: the Darkmoon Faire's building days, the fishing contest's
            announcers and judges, and the Scourge Invasion and Ahn'Qiraj War Effort, which the
            calendar doesn't show, so the addon keeps their quests off the map. A quest under the
            war effort's own heading (Ahn'Qiraj War) is its, and so is one CMaNGOS files under
            Invasion; Forever's own Invasion quest, which CMaNGOS lacks, is not. -HolidayFile's
            holiday wins over all of these, and the review says when another source disagrees.
  prereq    -LinkFile's prerequisite or choice, else CMaNGOS's requirement: its previous quests (its PrevQuestId
                    and the quests whose NextQuestId names it, any one of them, or a negative ExclusiveGroup's whole
                    group) and a RequiredCondition that asks only for quests handed in, as a list where it needs
                    several; a quest that must be in the log goes in links.jsonl, and the rest a prerequisite
                    can't hold is listed for review. Else
                    the quest whose follow-up this is in the cache, less one -LinkFile removes, or
                    else the quest before it in its quest line (QuestLineXQuest's order), when the previous step is handed in on the
                    map this one starts on (the client's QuestPOIBlob points -1 and 32). A line that doesn't
                    chain that way, and a quest line that disagrees with another source, are listed in the review.
Pins are CMaNGOS's spawns of each quest's NPC or object givers, or the recorder's places for the givers
it saw: the ledger's places of a giver on one map, rows within 1.5 map points of each other being one place
(the merge tool's own test, so a giver's pins may stand 1.5 points apart, no closer). Spawns are converted
to map positions with the client's UiMapAssignment frames. Frames are
rectangles and overlap, so a spawn goes on the first of these maps whose frame holds it:
  1. the map our old Classic pins had for that NPC (git history before #89), or the one whose old
     pin stands nearest the spawn when the NPC has old pins on several of them;
  2. the map our old pins put most NPCs within 100 yards on;
  3. a city, if the spawn stands within 50 yards of the heights of the NPCs our old pins have there;
  4. the zone its giver's quests are in;
  5. the one the spawn stands furthest inside, measured from the frame's nearest edge, or the
     smallest of those within 0.05 of that.
Only maps Classic Era (-EraBuild) already had are used, as CMaNGOS's NPCs can't stand in Forever's new
zones, whose frames reach over old ones (Mount Hyjal's covers parts of Felwood and Winterspring).
Givers inside dungeons get no pin. A giver found in more than 3 places on one map, like the chickens
that start CLUCK!, gets one pin on each of its maps, at its biggest group of spawns, when all its
quests recur and none is a holiday's: those pins show all year. A holiday's givers keep every pin.
CMaNGOS has several entries for some objects (Venom Bottle, Flawed Power Stones), each with its own spawns, so
pins of one name can hold a quest at one spot: Remove-DuplicatePinQuests.ps1's rule (DuplicatePins.ps1) keeps it
on one pin of those within half a map point of each other before the pins are written, so a rerun writes them as
committed, with nothing left for that tool (step 10's item 9) to take off.
A quest with no giver on a map gets a pin at its start point in the client's tables, if it has one,
with no giver named: the tables don't say who stands there. Such start points within 1.5 map points of
each other on one map share one pin, one per spot, by the rules both games share (PinRules.ps1, which
also chooses a giver pin's name: the game's, else the recorder's, else CMaNGOS's, and every pin's icon
from its quests). A quest whose giver becomes known leaves the spot for the giver's pin at the next
import, and the spot's other quests stay where they are. A quest that has a giver's pin keeps it,
and a start point more than 3 map points from all its pins on that map is listed for review. The
summary counts the client's start points, and the quests whose record in the cache names a giver
(none so far), so a rerun shows when Blizzard fills in more of either.

Three more files hold what Build-ForeverMenu.ps1 turns into the quest tooltip's reputation and
profession skill, and the quest window's warnings:
  links.jsonl       a line for each quest with links: its breadcrumbs, the quests that lead to it
                    and close once it's done (CMaNGOS's BreadcrumbForQuestId, the quests whose
                    NextQuestInChain names it unless it needs them done, and -LinkFile's), the
                    quests one of which must be in the log for it to be taken (needsInLog: a negative
                    PrevQuestId, or another quest's negative NextQuestId), and
                    the quests it shuts out, the rest of its CMaNGOS ExclusiveGroup when that's
                    positive, as only one quest of such a group can be done, with the pairs -LinkFile
                    adds and less those it removes. Recurring
                    quests are left out of both: CMaNGOS also groups repeatable quests that only shut
                    each other out while one is in the quest log.
  reputation.jsonl  a line for each reputation reward, from the game's records only. CMaNGOS's
                    amounts are mostly The Burning Crusade's, which raised most quests' rewards (a
                    city's 100 became 250), so a quest the game hasn't answered gets its reputation
                    once it does.
  skills.jsonl      a line for each quest that needs a profession, and the skill level it needs:
                    CMaNGOS's RequiredSkill and RequiredSkillValue, as the game's records don't say.
                    A level of 1 asks only that the character has learned the profession.

Anything worth a look goes to -ReviewFile, one row per finding; the summary counts them. With -WhatIf,
only the review is written.
#>
param(
    [string]$ToolsDir = $PSScriptRoot,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data\forever'),
    [string]$Build = "",
    [string]$EraBuild = "1.15.9.70003",
    [string]$CacheFile = "",
    [string]$AnswerFile = "",
    [int]$MaxMissedRuns = 10,
    [string]$DecisionsFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-removal-decisions.csv'),
    [string]$RemovalsFile = "",
    [string]$ProbeFile = "",
    [string]$CmangosDump = "",
    [string]$GiverFile = (Join-Path $PSScriptRoot '..\docs\plans\forever-quest-givers.csv'),
    [string]$PvpFile = (Join-Path $PSScriptRoot '..\docs\plans\quest-pvp-decisions.csv'),
    [string]$ZoneFile = (Join-Path $PSScriptRoot '..\docs\plans\forever-quest-zones.csv'),
    [string]$HolidayFile = (Join-Path $PSScriptRoot '..\docs\plans\forever-quest-holiday-decisions.csv'),
    [string]$LinkFile = (Join-Path $PSScriptRoot '..\docs\plans\forever-quest-link-decisions.csv'),
    [string]$ClassFile = (Join-Path $PSScriptRoot '..\docs\plans\forever-quest-class-decisions.csv'),
    [string]$LedgerFile = (Join-Path $PSScriptRoot '..\docs\plans\recorded-quest-givers.csv'),
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string[]]$Builds = @(),
    [string]$ReviewFile = "",
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\AddonData.ps1"
. "$PSScriptRoot\PinRules.ps1"
. "$PSScriptRoot\DuplicatePins.ps1"
. "$PSScriptRoot\RecordedGivers.ps1"
. "$PSScriptRoot\QuestRemovals.ps1"
. "$PSScriptRoot\ForeverAnswers.ps1"
. "$PSScriptRoot\QuestLines.ps1"
. "$PSScriptRoot\LatestBuilds.ps1"
$Build = Resolve-ProbeBuild $Build 'forever' $ToolsDir 'Build'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if (-not $AnswerFile) { $AnswerFile = Join-Path $DataDir 'answers.jsonl' }
if (-not $RemovalsFile) { $RemovalsFile = "$ToolsDir\quest_removals_forever.csv" }
if (-not $CacheFile) { $CacheFile = "$ToolsDir\forever_quest_cache_$Build.jsonl" }
if (-not (Test-Path $CacheFile)) { throw "There's no $CacheFile. Run Read-QuestCache.ps1 first." }
if (-not $ProbeFile) {
    $ProbeFile = Get-ChildItem "$ToolsDir\forever_probe_*\QCForeverProbe.lua" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
    if (-not $ProbeFile) { throw "There are no probe results under $ToolsDir\forever_probe_*. Give -ProbeFile." }
}
if (-not $ReviewFile) { $ReviewFile = "$ToolsDir\forever_import_review.csv" }

function Get-ClientTable([string]$table, [string]$tableBuild = $Build) {
    $path = "$ToolsDir\$table-$tableBuild.csv"
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$table/csv?build=$tableBuild" -OutFile $path
        Start-Sleep -Milliseconds 300
    }
    return Import-Csv $path
}

if (-not $CmangosDump) {
    $CmangosDump = Get-ChildItem "$ToolsDir\ClassicDB_*.sql.gz" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $CmangosDump) {
        $listing = Invoke-RestMethod "https://api.github.com/repos/cmangos/classic-db/contents/Full_DB"
        $file = $listing | Where-Object { $_.name -like '*.sql.gz' } | Select-Object -First 1
        $CmangosDump = "$ToolsDir\$($file.name)"
        Invoke-WebRequest -UseBasicParsing -Uri $file.download_url -OutFile $CmangosDump
    }
}

$raceBit = @{ 1 = 1; 2 = 2; 3 = 4; 4 = 8; 5 = 16; 6 = 32; 7 = 64; 8 = 128; 95 = 67108864; 96 = 67108864 }
$classBySort = @{ (-81) = 1; (-141) = 2; (-261) = 4; (-162) = 8; (-262) = 16; (-82) = 64; (-161) = 128; (-61) = 256; (-263) = 1024 }
$skillBySort = @{ (-24) = 182; (-101) = 356; (-121) = 164; (-181) = 171; (-182) = 165; (-201) = 202; (-264) = 197; (-304) = 185; (-324) = 129 }
$professionBySkill = @{ 171 = 1; 164 = 2; 333 = 4; 202 = 8; 165 = 64; 197 = 128; 182 = 256; 186 = 512; 393 = 1024; 129 = 4096; 185 = 8192; 356 = 16384 }
$holidayByHolidayId = @{ 372 = 1; 201 = 2; 409 = 4; 141 = 8; 324 = 16; 1405 = 16; 321 = 32; 423 = 64; 335 = 64; 327 = 128
    341 = 256; 181 = 512; 404 = 1024; 398 = 2048; 691 = 4096; 479 = 8192; 374 = 8192; 375 = 8192; 376 = 8192; 301 = 65536 }
# CMaNGOS's events with no holiday of their own, by their description: the Darkmoon Faire's building days, the
# fishing contest's announcers and judges, and two world events the calendar doesn't show.
$holidayByEventName = [ordered]@{ '^Darkmoon Faire' = 8192; '^Fishing Extravaganza' = 65536; '^Scourge Invasion' = 16384
    '^AQ War Effort' = 32768 }
$holidayBySort = @{ (-364) = 8192; (-365) = 32768; (-366) = 128; (-369) = 256 }
# Not by the game's heading: Forever's own Invasion quest (98471) isn't the Scourge Invasion's.
$holidayByCmangosSort = @{ (-368) = 16384 }
$seasonalSort = -22
$reputationSort = -367; $aqWarSort = -365; $aqWarEffort = 32768
$allianceRaces = 77
$hordeRaces = 178
$internalTitle = '^<|UNUSED|\[DNT\]|\(DNT\)|\[PH\]|^ZZ|\bNYI\b|DEPRECATED|\bTEST\b'
$gameOnlyJunk = '(?i)test quest|test kill quest|do not use|^\[never used\]$|^REUSE$|\(123\)aa$|^Da Foo$'

$inClient = @{}
foreach ($row in Get-ClientTable 'QuestV2') { $inClient[[int]$row.ID] = $true }
$sortName = @{}; $areaParent = @{}; $areaMap = @{}
foreach ($row in Get-ClientTable 'AreaTable') {
    $sortName[[int]$row.ID] = $row.AreaName_lang
    $areaParent[[int]$row.ID] = [int]$row.ParentAreaID
    $areaMap[[int]$row.ID] = [int]$row.ContinentID
}
$raceName = @{}; foreach ($row in Get-ClientTable 'ChrRaces') { if ($row.Name_lang) { $raceName[$row.Name_lang] = $true } }
$placelessSort = @{ (-221) = $true; (-1) = $true; (-344) = $true }
foreach ($row in Get-ClientTable 'QuestSort') {
    $sortName[-[int]$row.ID] = $row.SortName_lang
    if ($raceName[$row.SortName_lang]) { $placelessSort[-[int]$row.ID] = $true }
}
$zoneAreas = @{}
foreach ($row in Get-ClientTable 'UiMapAssignment') { if ([int]$row.AreaID) { $zoneAreas[[int]$row.AreaID] = $true } }
$instanceMaps = @{}; $instanceArea = @{}
foreach ($map in (Get-ClientTable 'Map' | Where-Object { [int]$_.InstanceType -ge 1 -and [int]$_.InstanceType -le 4 } | Sort-Object { -[int]$_.AreaTableID }, { [int]$_.ID })) {
    $instanceMaps[[int]$map.ID] = $true
    if ($instanceArea.ContainsKey($map.MapName_lang)) { continue }
    $onMap = @($areaMap.Keys | Where-Object { $areaMap[$_] -eq [int]$map.ID -and -not $areaParent[$_] } | Sort-Object { $sortName[$_] -ne $map.MapName_lang }, { $_ })
    $own = if ($onMap.Count -and $sortName[$onMap[0]] -eq $map.MapName_lang) { $onMap[0] }
        elseif ($sortName.ContainsKey([int]$map.AreaTableID)) { [int]$map.AreaTableID } elseif ($onMap.Count) { $onMap[0] } else { $null }
    $instanceArea[$map.MapName_lang] = $own
}

# A quest filed under an outdoor area named after an instance (Gnomeregan in Dun Morogh) goes under
# the instance's own area, if it has one; one filed under any other subzone goes under its zone, or
# under the top area of its instance.
function Resolve-Category([int]$category) {
    if ($category -le 0) { return $category }
    $name = $sortName[$category]
    if (-not $instanceMaps[$areaMap[$category]] -and -not $zoneAreas[$category] -and $instanceArea.ContainsKey($name)) {
        if ($instanceArea[$name]) { return [int]$instanceArea[$name] }
        return $category
    }
    while ($areaParent[$category] -and $sortName.ContainsKey($areaParent[$category])) { $category = $areaParent[$category] }
    return $category
}
$storylineOf = @{}
foreach ($row in Get-ClientTable 'QuestLineXQuest') { $storylineOf[[int]$row.QuestID] = [int]$row.QuestLineID }
$uiMapType = @{}
foreach ($row in Get-ClientTable 'UiMap') { $uiMapType[[int]$row.ID] = [int]$row.Type }
$eraUiMaps = @{}
foreach ($row in Get-ClientTable 'UiMap' $EraBuild) { $eraUiMaps[[int]$row.ID] = $true }
$frames = @(Get-ClientTable 'UiMapAssignment' | Where-Object { $uiMapType[[int]$_.UiMapID] -ge 3 } | ForEach-Object {
    $minX = [double]$_.Region_0; $minY = [double]$_.Region_1; $maxX = [double]$_.Region_3; $maxY = [double]$_.Region_4
    [pscustomobject]@{ UiMap = [int]$_.UiMapID; Map = [int]$_.MapID; Zone = [int]$_.AreaID; New = -not $eraUiMaps[[int]$_.UiMapID]
        MinX = $minX; MinY = $minY; MaxX = $maxX; MaxY = $maxY
        U0 = [double]$_.UiMin_0; U1 = [double]$_.UiMin_1; V0 = [double]$_.UiMax_0; V1 = [double]$_.UiMax_1
        Area = ($maxX - $minX) * ($maxY - $minY) }
} | Sort-Object Area)
$uiMapArea = @{}; foreach ($frame in $frames) { if ($frame.Zone) { $uiMapArea[$frame.UiMap] = $frame.Zone } }

$cityMaps = @{ 1453 = $true; 1454 = $true; 1455 = $true; 1456 = $true; 1457 = $true; 1458 = $true }
$cityHeights = @{}
$oldPinSpots = @{}

# How far inside a frame a spawn stands: its distance to the nearest edge, as a share of the frame.
function Get-Centrality($frame, [double]$x, [double]$y) {
    $fx = ($frame.MaxY - $y) / ($frame.MaxY - $frame.MinY)
    $fy = ($frame.MaxX - $x) / ($frame.MaxX - $frame.MinX)
    return [Math]::Min([Math]::Min($fx, 1 - $fx), [Math]::Min($fy, 1 - $fy))
}

# Of the frames that hold a spawn, the map our old pins put most NPCs within 100 yards of it on.
function Get-NearbyOldPinMap($holding, [int]$map, [double]$x, [double]$y) {
    $votes = @{}
    $cellX = [Math]::Floor($x / 100); $cellY = [Math]::Floor($y / 100)
    foreach ($i in -1, 0, 1) {
        foreach ($j in -1, 0, 1) {
            foreach ($spot in $oldPinSpots["$map|$($cellX + $i)|$($cellY + $j)"]) {
                if (($spot.X - $x) * ($spot.X - $x) + ($spot.Y - $y) * ($spot.Y - $y) -gt 10000) { continue }
                foreach ($uiMap in $spot.UiMaps) { $votes[$uiMap] = 1 + [int]$votes[$uiMap] }
            }
        }
    }
    $best = $null; $bestVotes = 0
    foreach ($frame in $holding) { if ([int]$votes[$frame.UiMap] -gt $bestVotes) { $best = $frame; $bestVotes = [int]$votes[$frame.UiMap] } }
    return $best
}

# Of a giver's old pin maps whose frames hold a spawn, the one whose old pin stands nearest it. A
# giver found in several zones, such as the chickens, has an old pin in each, and their frames
# overlap: one in Westfall can be inside Elwynn Forest's too. The first map wins when no pin has a
# position.
function Select-NearestOldPinMap([int[]]$uiMaps, $pinsByMap, [int]$map, [double]$x, [double]$y) {
    $best = $uiMaps[0]; $bestDistance = [double]::MaxValue
    foreach ($uiMap in $uiMaps) {
        foreach ($point in $pinsByMap[$uiMap]) {
            if ($point.Map -ne $map) { continue }
            $distance = ($point.X - $x) * ($point.X - $x) + ($point.Y - $y) * ($point.Y - $y)
            if ($distance -lt $bestDistance) { $best = $uiMap; $bestDistance = $distance }
        }
    }
    return $best
}

# The map position of a CMaNGOS spawn: on -OnUiMap's frame if given. Otherwise the frames that hold
# it, of maps Classic Era had, are tried in this order:
#   1. a map -OldMaps has (our old Classic pins' maps for the giver), the one whose old pin stands
#      nearest the spawn when several do;
#   2. the map our old pins put most NPCs within 100 yards on;
#   3. a city whose old pins' NPCs stand within 50 yards of the spawn's height -Z;
#   4. one of -Zones (the zones the giver's quests are in);
#   5. the one the spawn stands furthest inside, with any within 0.05 of that counting as a tie that
#      the smallest wins.
# The old pins come first because the others guess wrong for a giver whose quests are filed under a
# neighbouring zone, like Tirion Fordring's. A frame is a rectangle, so a city's reaches past its
# walls: the height keeps the Darkmoon Faire at the foot of Thunder Bluff's mesa off the city's map.
function Convert-ToMapSpot([int]$map, [double]$x, [double]$y, $Zones = $null, $OldMaps = $null, [int]$OnUiMap = 0, [double]$Z = [double]::NaN) {
    $holding = @($frames | Where-Object { $_.Map -eq $map -and $x -ge $_.MinX -and $x -le $_.MaxX -and $y -ge $_.MinY -and $y -le $_.MaxY })
    if ($OnUiMap) {
        $chosen = $holding | Where-Object { $_.UiMap -eq $OnUiMap } | Select-Object -First 1
    } else {
        $old = @($holding | Where-Object { -not $_.New })
        $chosen = $null
        if ($OldMaps) {
            $oldPinned = @($old | Where-Object { $OldMaps.ContainsKey($_.UiMap) })
            if ($oldPinned.Count -gt 1) {
                $nearest = Select-NearestOldPinMap @($oldPinned | ForEach-Object { $_.UiMap }) $OldMaps $map $x $y
                $chosen = $oldPinned | Where-Object { $_.UiMap -eq $nearest } | Select-Object -First 1
            } else {
                $chosen = $oldPinned | Select-Object -First 1
            }
        }
        if (-not $chosen) { $chosen = Get-NearbyOldPinMap $old $map $x $y }
        if (-not $chosen) {
            $chosen = $old | Where-Object { $cityMaps.ContainsKey($_.UiMap) -and
                ([double]::IsNaN($Z) -or -not $cityHeights[$_.UiMap] -or ($Z -ge $cityHeights[$_.UiMap].Min - 50 -and $Z -le $cityHeights[$_.UiMap].Max + 50)) } | Select-Object -First 1
        }
        if (-not $chosen -and $Zones) { $chosen = $old | Where-Object { $Zones.ContainsKey($_.Zone) } | Select-Object -First 1 }
        if (-not $chosen -and $old.Count) {
            $deepest = ($old | ForEach-Object { Get-Centrality $_ $x $y } | Measure-Object -Maximum).Maximum
            $chosen = $old | Where-Object { (Get-Centrality $_ $x $y) -ge $deepest - 0.05 } | Select-Object -First 1
        }
    }
    if (-not $chosen) { return $null }
    $fx = ($chosen.MaxY - $y) / ($chosen.MaxY - $chosen.MinY)
    $fy = ($chosen.MaxX - $x) / ($chosen.MaxX - $chosen.MinX)
    return [pscustomobject]@{ UiMap = $chosen.UiMap
        X = [decimal][Math]::Round(100 * ($chosen.U0 + $fx * ($chosen.V0 - $chosen.U0)), 2)
        Y = [decimal][Math]::Round(100 * ($chosen.U1 + $fy * ($chosen.V1 - $chosen.U1)), 2) }
}

# Quest start points from the client's tables: a blob with objective index 32 marks where the quest is
# picked up, and index -1 is the quest's own point, which is its turn-in when it ends elsewhere. A quest
# the client gives a point 32 starts there; one with only a point -1 starts at it. The first point of a
# blob is used, as retail's pin tool does.
$firstPoint = @{}
foreach ($row in Get-ClientTable 'QuestPOIPoint') { if (-not $firstPoint.ContainsKey([int]$row.QuestPOIBlobID)) { $firstPoint[[int]$row.QuestPOIBlobID] = $row } }
$startSpots = @{}; $startOffMap = 0
$questBlobs = @(Get-ClientTable 'QuestPOIBlob' | Where-Object { $_.ObjectiveIndex -eq '-1' -or $_.ObjectiveIndex -eq '32' })
$hasStart = New-Object System.Collections.Generic.HashSet[int]
foreach ($blob in $questBlobs) { if ($blob.ObjectiveIndex -eq '32') { [void]$hasStart.Add([int]$blob.QuestID) } }
foreach ($blob in $questBlobs) {
    $quest = [int]$blob.QuestID
    if (($blob.ObjectiveIndex -eq '32') -ne $hasStart.Contains($quest)) { continue }
    $point = $firstPoint[[int]$blob.ID]
    if (-not $point) { continue }
    $spot = Convert-ToMapSpot ([int]$blob.MapID) ([double]$point.X) ([double]$point.Y) -OnUiMap ([int]$blob.UiMapID)
    if (-not $spot) { $startOffMap++; continue }
    $near = $startSpots[$quest] | Where-Object { $_.UiMap -eq $spot.UiMap -and [Math]::Abs($_.X - $spot.X) -lt 3 -and [Math]::Abs($_.Y - $spot.Y) -lt 3 }
    if (-not $near) { $startSpots[$quest] += @($spot) }
}

# The recorded givers come from the ledger, which Import-RecordedGivers.ps1 (step 6d) fills from the probe's
# files and the addon's own notes. If the probe's file holds a giver, spot or offer the ledger lacks, the
# ledger is behind it and the newest givers would be dropped without a word, so nothing is written. The file is
# read, and filtered, the way step 6d reads it (its builds, the game's maps, the quests the data has), and
# the ledger must hold each note under the file's own source tag with at least the file's number. Only the
# probe's file is checked: the addon's file and players' are left to the runbook's order (step 6d first).
if ($Builds.Count -eq 0) { $Builds = @(Get-TocVersions $AddonDir) }
if ($Builds.Count -eq 0) { throw "No versions to read the probe's file for: pass -Builds, or give -AddonDir the TOCs." }
$probeTag = 'own-' + (ConvertTo-RecordedTag (Split-Path -Leaf (Split-Path -Parent (Resolve-Path $ProbeFile).Path)))
$ledgerMaps = @{ retail = (New-Object 'System.Collections.Generic.HashSet[int]'); forever = (New-Object 'System.Collections.Generic.HashSet[int]') }
foreach ($map in $uiMapType.Keys) { [void]$ledgerMaps.forever.Add($map) }
$ledgerQuests = @{ retail = (New-Object 'System.Collections.Generic.HashSet[int]'); forever = (New-Object 'System.Collections.Generic.HashSet[int]') }
$dataQuestPath = Join-Path $DataDir 'quests.jsonl'
if (Test-Path -LiteralPath $dataQuestPath) {
    foreach ($line in [IO.File]::ReadLines((Resolve-Path -LiteralPath $dataQuestPath).Path)) {
        if ($line -match '^\{"id":(\d+),') { [void]$ledgerQuests.forever.Add([int]$Matches[1]) }
    }
}
$probeRead = Read-RecordedFile $ProbeFile $probeTag $LuaExe (Join-Path $PSScriptRoot 'Read-RecordedGivers.lua') 64
if ($probeRead.Refused) { throw "The probe's file $ProbeFile can't be read as recorder notes ($($probeRead.Refused)), which is how step 6d reads it too. Nothing was written." }
$probeNotes = $null
$ledgerGaps = @()
$ledger = Read-RecordedLedger $LedgerFile
if ($probeRead.Givers.Count + $probeRead.Spots.Count + $probeRead.Offers.Count -gt 0) {
    $probeNotes = Get-RecordedFacts $probeRead $Builds $ledgerMaps $ledgerQuests
    if ($probeNotes.Refused) {
        $hint = if ($probeNotes.Refused -like 'none of its builds are read*') {
            " The versions read are $($Builds -join ', '): if the TOCs don't name the file's version yet, pass it with -Builds, here and to step 6d."
        } else { '' }
        throw "The probe's file $ProbeFile can't be read as recorder notes ($($probeNotes.Refused)), which is how step 6d reads it too.$hint Nothing was written."
    }
    if ($probeNotes.Game -ne 'forever') { throw "The probe's file $ProbeFile is not Forever's: its builds say '$($probeNotes.Game)'. Nothing was written." }
    $ledgerGaps = @(Find-RecordedLedgerGaps $ledger $probeNotes)
}
if ($ledgerGaps.Count) {
    $shown = ($ledgerGaps | Select-Object -First 5) -join '; '
    throw ("The ledger $LedgerFile lacks $($ledgerGaps.Count) of the recorder notes in the probe's file $ProbeFile (source $probeTag): $shown" +
        $(if ($ledgerGaps.Count -gt 5) { "; and $($ledgerGaps.Count - 5) more" }) +
        ". Run step 6d (Import-RecordedGivers.ps1) on the probe's file first, so the ledger keeps them (on a new build it needs UiMap-$Build.csv, which this run has made sure is in -ToolsDir), then run this again. Nothing was written.")
}
$recordedModel = Get-RecordedModel $ledger 'forever'
$fromLedger = Get-RecordedGiverInputs $recordedModel
$recordedSpots = $fromLedger.Spots; $recordedName = $fromLedger.Names; $recordedOffers = $fromLedger.Offers

$outputEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$sql = [IO.Path]::GetTempFileName()
try {
    $source = [IO.File]::OpenRead($CmangosDump)
    $gzip = New-Object System.IO.Compression.GZipStream($source, [IO.Compression.CompressionMode]::Decompress)
    $target = [IO.File]::Create($sql)
    $gzip.CopyTo($target)
    $target.Close(); $gzip.Close(); $source.Close()
    $dump = @{}
    foreach ($read in @(@('quest_template', '1,3,4,6,8,9,10,22,23,31,25,26,89,11,24,12,27,7'), @('conditions', '1,2,3,4,5,6,7,8'), @('creature_questrelation', '1,2'),
            @('gameobject_questrelation', '1,2'), @('creature_involvedrelation', '1,2'), @('creature', '1,2,3,5,6,7'), @('gameobject', '1,2,3,5,6,7'), @('creature_spawn_entry', '1,2'), @('gameobject_spawn_entry', '1,2'),
            @('creature_template', '1,2'), @('gameobject_template', '1,4'), @('item_template', '1,111'),
            @('game_event', '1,5,7'), @('game_event_quest', '1,2'), @('game_event_creature', '1,2'), @('game_event_gameobject', '1,2'))) {
        $dump[$read[0]] = @(& $LuaExe "$PSScriptRoot\Read-SqlDump.lua" $sql $read[0] $read[1])
        if ($LASTEXITCODE -ne 0) { throw "Read-SqlDump.lua failed on $($read[0])" }
    }
    $probeLines = @(& $LuaExe "$PSScriptRoot\Read-ForeverProbe.lua" $ProbeFile facts)
    if ($LASTEXITCODE -ne 0) { throw "Read-ForeverProbe.lua failed on $ProbeFile" }
} finally {
    Remove-Item $sql -ErrorAction SilentlyContinue
    [Console]::OutputEncoding = $outputEncoding
}

$pvpDecision = @{}
if (Test-Path $PvpFile) {
    foreach ($row in @(Import-Csv $PvpFile -Encoding UTF8 | Where-Object { $_.Game -eq 'forever' })) { $pvpDecision[[int]$row.QuestID] = $row.Decision -eq 'PVP' }
}
$cmQuest = @{}
foreach ($line in $dump.quest_template) {
    $f = $line.Split("`t")
    $cmQuest[[int]$f[0]] = [pscustomobject]@{ Zone = [int]$f[1]; MinLevel = [int]$f[2]; Level = [int]$f[3]; Classes = [int]$f[4]
        Races = [int]$f[5]; Skill = [int]$f[6]; Special = [int]$f[7]; Prev = [int]$f[8]; Title = $f[9]; Group = [int]$f[10]; BreadcrumbFor = [int]$f[11]; Reputation = [int]$f[12] -ne 0
        SkillLevel = [int]$f[13]; Next = [int]$f[14]; Condition = [int]$f[15]; ChainNext = [int]$f[16]; Type = [int]$f[17] }
}
$cmCondition = @{}
foreach ($line in $dump.conditions) {
    $f = $line.Split("`t")
    $cmCondition[[int]$f[0]] = [pscustomobject]@{ Type = [int]$f[1]; Values = @([int]$f[2], [int]$f[3], [int]$f[4], [int]$f[5]); Flags = [int]$f[6]; Comment = $f[7] }
}
$creatureStarters = @{}; $objectStarters = @{}
foreach ($line in $dump.creature_questrelation) { $f = $line.Split("`t"); $creatureStarters[[int]$f[1]] += @([int]$f[0]) }
foreach ($line in $dump.gameobject_questrelation) { $f = $line.Split("`t"); $objectStarters[[int]$f[1]] += @([int]$f[0]) }
$starterNpcs = @{}; foreach ($list in $creatureStarters.Values) { foreach ($npc in $list) { $starterNpcs[$npc] = $true } }
$handStarters = @{}
$handRemovedStarters = New-Object System.Collections.Generic.List[object]
foreach ($row in Import-Csv $GiverFile) {
    $quest = [int]$row.Quest; $npc = [int]$row.Npc
    if ($row.Decision -eq 'REMOVE') {
        $handRemovedStarters.Add([pscustomobject]@{ Quest = $quest; Npc = $npc; Had = (@($creatureStarters[$quest]) -contains $npc) })
        $creatureStarters[$quest] = @($creatureStarters[$quest] | Where-Object { $_ -ne $npc })
        if (-not $creatureStarters[$quest].Count) { $creatureStarters.Remove($quest) }
    } elseif ($row.Decision -and $row.Decision -ne 'ADD') { throw "$GiverFile gives quest $quest the decision '$($row.Decision)': it is ADD (the default) or REMOVE." }
    else { $handStarters[$quest] += @($npc); $starterNpcs[$npc] = $true }
}
$handZone = @{}; foreach ($row in Import-Csv $ZoneFile) { $handZone[[int]$row.Quest] = [int]$row.Zone }
$holidayFlagByName = @{}
$qcCore = [IO.File]::ReadAllText((Join-Path $AddonDir 'qcCore.lua'))
foreach ($entry in [regex]::Matches($qcCore, '\{flag=(\d+), name="((?:[^"\\]|\\.)*)", eventIDs=')) { $holidayFlagByName[$entry.Groups[2].Value] = [int]$entry.Groups[1].Value }
if (-not $holidayFlagByName.Count) { throw "qcHolidays wasn't found in qcCore.lua." }
$handHoliday = @{}
foreach ($row in Import-Csv $HolidayFile) {
    if ($row.Decision -ne 'SET') { throw "$HolidayFile gives quest $($row.Quest) the decision '$($row.Decision)': it must be SET." }
    if ($row.Quest -notmatch '^\d+$') { throw "$HolidayFile has a row whose quest, '$($row.Quest)', is not a number." }
    if (-not $holidayFlagByName.ContainsKey($row.Holiday)) { throw "$HolidayFile gives quest $($row.Quest) the holiday '$($row.Holiday)', which qcHolidays in qcCore.lua lacks." }
    if ($handHoliday.ContainsKey([int]$row.Quest)) { throw "$HolidayFile lists quest $($row.Quest) twice." }
    $handHoliday[[int]$row.Quest] = $holidayFlagByName[$row.Holiday]
}
$handPrereq = @{}; $handPrereqRemovals = @{}; $handUnlinks = @{}; $handLinks = @{}; $handBreadcrumbs = @{}
foreach ($row in Import-Csv $LinkFile) {
    if ($row.Quest -notmatch '^\d+$' -or $row.Other -notmatch '^\d+$') { throw "$LinkFile has a row whose quests, '$($row.Quest)' and '$($row.Other)', aren't both numbers." }
    $quest = [int]$row.Quest; $other = [int]$row.Other
    if ($quest -eq $other) { throw "$LinkFile links quest $quest to itself." }
    $pair = "$([Math]::Min($quest, $other))|$([Math]::Max($quest, $other))"
    switch ("$($row.Link) $($row.Decision)") {
        'prereq SET' {
            if ($handPrereq[$quest] -contains $other) { throw "$LinkFile gives quest $quest the prerequisite $other twice." }
            $handPrereq[$quest] += @($other)
        }
        'prereq REMOVE' {
            if ($handPrereqRemovals.ContainsKey($quest)) { throw "$LinkFile removes two prerequisites of quest $quest." }
            $handPrereqRemovals[$quest] = $other
        }
        { $_ -in 'exclusive ADD', 'exclusive REMOVE' } {
            if ($handLinks.ContainsKey($pair) -or $handUnlinks.ContainsKey($pair)) { throw "$LinkFile lists the link between quests $quest and $other twice." }
            if ($row.Decision -eq 'ADD') { $handLinks[$pair] = @($quest, $other) } else { $handUnlinks[$pair] = @($quest, $other) }
        }
        { $_ -in 'exclusive SKIP', 'exclusive KEEP' } { }
        'breadcrumb ADD' {
            if ($handBreadcrumbs.ContainsKey("$quest|$other")) { throw "$LinkFile makes quest $other a breadcrumb of quest $quest twice." }
            $handBreadcrumbs["$quest|$other"] = @($quest, $other)
        }
        default {
            throw "$LinkFile gives quest $quest the link '$($row.Link)' with the decision '$($row.Decision)': a prereq is SET or REMOVEd, an exclusive ADDed, REMOVEd, SKIPped or KEPT (step 2k's), a breadcrumb ADDed."
        }
    }
}
foreach ($quest in $handPrereqRemovals.Keys) { if ($handPrereq.ContainsKey($quest)) { throw "$LinkFile both sets and removes a prerequisite of quest $quest." } }
$classBitByName = @{}; $playableClasses = 0
foreach ($row in Get-ClientTable 'ChrClasses') { $bit = 1 -shl ([int]$row.ID - 1); $classBitByName[$row.Name_lang] = $bit; $playableClasses = $playableClasses -bor $bit }
$handClass = @{}
foreach ($row in Import-Csv $ClassFile) {
    if ($row.Decision -ne 'SET') { throw "$ClassFile gives quest $($row.Quest) the decision '$($row.Decision)': it must be SET." }
    if ($row.Quest -notmatch '^\d+$') { throw "$ClassFile has a row whose quest, '$($row.Quest)', is not a number." }
    if ($handClass.ContainsKey([int]$row.Quest)) { throw "$ClassFile lists quest $($row.Quest) twice." }
    $mask = 0
    foreach ($name in ($row.Class -split ',' | ForEach-Object { $_.Trim() })) {
        if (-not $classBitByName.ContainsKey($name)) { throw "$ClassFile gives quest $($row.Quest) the class '$name', which the client's ChrClasses lacks." }
        $mask = $mask -bor $classBitByName[$name]
    }
    $handClass[[int]$row.Quest] = $mask
}
# The classes that may use the items that start each quest; an AllowableClass of -1 or 0 is any class.
$itemClass = @{}
foreach ($row in Get-ClientTable 'ItemSparse') {
    if ($row.StartQuestID -eq '0') { continue }
    $quest = [int]$row.StartQuestID
    $mask = [int]([long]$row.AllowableClass -band $playableClasses)
    if (-not $mask) { $mask = $playableClasses }
    if (-not $itemClass.ContainsKey($quest)) { $itemClass[$quest] = [pscustomobject]@{ Mask = 0; Items = @() } }
    $itemClass[$quest].Mask = $itemClass[$quest].Mask -bor $mask
    $itemClass[$quest].Items += @([int]$row.ID)
}
$creatureEnders = @{}; $enderNpcs = @{}
foreach ($line in $dump.creature_involvedrelation) {
    $f = $line.Split("`t")
    if (-not $cmQuest.ContainsKey([int]$f[1]) -or -not $placelessSort[$cmQuest[[int]$f[1]].Zone]) { continue }
    $creatureEnders[[int]$f[1]] += @([int]$f[0]); $enderNpcs[[int]$f[0]] = $true
}
$starterObjects = @{}; foreach ($list in $objectStarters.Values) { foreach ($object in $list) { $starterObjects[$object] = $true } }
$itemStart = @{}
foreach ($line in $dump.item_template) { $f = $line.Split("`t"); if ($f[1] -ne '0') { $itemStart[[int]$f[1]] = [int]$f[0] } }
$eventHoliday = @{}
foreach ($line in $dump.game_event) {
    $f = $line.Split("`t")
    $flag = $holidayByHolidayId[[int]$f[1]]
    if (-not $flag) { foreach ($name in $holidayByEventName.Keys) { if ($f[2] -match $name) { $flag = $holidayByEventName[$name]; break } } }
    if ($flag) { $eventHoliday[[int]$f[0]] = $flag }
}
$questHoliday = @{}
foreach ($line in $dump.game_event_quest) { $f = $line.Split("`t"); $flag = $eventHoliday[[int]$f[1]]; if ($flag) { $questHoliday[[int]$f[0]] = $flag } }
$ambiguousSpawns = New-Object System.Collections.Generic.List[string]
$spawnHoliday = @{}
foreach ($line in $dump.game_event_creature) {
    $f = $line.Split("`t"); $flag = $eventHoliday[[int]$f[1]]; $guid = [int]$f[0]
    if (-not $flag) { continue }
    if ($spawnHoliday.ContainsKey($guid) -and $spawnHoliday[$guid] -ne $flag) { if ($null -ne $spawnHoliday[$guid]) { $ambiguousSpawns.Add("creature $guid") }; $spawnHoliday[$guid] = $null } elseif (-not $spawnHoliday.ContainsKey($guid)) { $spawnHoliday[$guid] = $flag }
}
$objectSpawnHoliday = @{}
foreach ($line in $dump.game_event_gameobject) {
    $f = $line.Split("`t"); $flag = $eventHoliday[[int]$f[1]]; $guid = [int]$f[0]
    if (-not $flag) { continue }
    if ($objectSpawnHoliday.ContainsKey($guid) -and $objectSpawnHoliday[$guid] -ne $flag) { if ($null -ne $objectSpawnHoliday[$guid]) { $ambiguousSpawns.Add("object $guid") }; $objectSpawnHoliday[$guid] = $null } elseif (-not $objectSpawnHoliday.ContainsKey($guid)) { $objectSpawnHoliday[$guid] = $flag }
}
$oldPins = New-Object System.Collections.Generic.List[object]
# Each NPC's old pin maps, with where in the world each pin stands, from its map's frame.
$oldPinMaps = @{}
$mapId = 0
foreach ($line in (git -C $repoRoot show "a9bc11c^:QuestCompletist/qcPinDB.lua")) {
    if ($line -match '^\t\[(\d+)\] = \{') { $mapId = [int]$Matches[1]; continue }
    if ($mapId -lt 1411 -or $mapId -gt 1459 -or $line -notmatch '^\t\t\{\d+,(\d+),".*",([-0-9.]+),([-0-9.]+),\{([0-9,]*)\}') { continue }
    $npc = [int]$Matches[1]
    $oldPins.Add([pscustomobject]@{ UiMap = $mapId; Npc = $npc; X = [decimal]$Matches[2]; Y = [decimal]$Matches[3]
        Quests = @($Matches[4].Split(',') | Where-Object { $_ } | ForEach-Object { [int]$_ }) })
    if (-not $oldPinMaps.ContainsKey($npc)) { $oldPinMaps[$npc] = @{} }
    if (-not $oldPinMaps[$npc].ContainsKey($mapId)) { $oldPinMaps[$npc][$mapId] = @() }
    $frame = $frames | Where-Object { $_.UiMap -eq $mapId -and -not $_.New } | Select-Object -First 1
    if ($frame) {
        $fx = ([double]$Matches[2] / 100 - $frame.U0) / ($frame.V0 - $frame.U0)
        $fy = ([double]$Matches[3] / 100 - $frame.U1) / ($frame.V1 - $frame.U1)
        $oldPinMaps[$npc][$mapId] += @([pscustomobject]@{ Map = $frame.Map
            X = $frame.MaxX - $fy * ($frame.MaxX - $frame.MinX); Y = $frame.MaxY - $fx * ($frame.MaxY - $frame.MinY) })
    }
}
$spawnEntries = @{}; foreach ($line in $dump.creature_spawn_entry) { $f = $line.Split("`t"); $spawnEntries[[int]$f[0]] += @([int]$f[1]) }
$objectSpawnEntries = @{}; foreach ($line in $dump.gameobject_spawn_entry) { $f = $line.Split("`t"); $objectSpawnEntries[[int]$f[0]] += @([int]$f[1]) }
$npcSpawns = @{}; $npcHoliday = @{}; $oldPinNpcSpawns = @{}; $enderSpawns = @{}
foreach ($line in $dump.creature) {
    $f = $line.Split("`t")
    $entries = if ([int]$f[1]) { @([int]$f[1]) } else { @($spawnEntries[[int]$f[0]]) }
    foreach ($npc in $entries) {
        $spawn = [pscustomobject]@{ Map = [int]$f[2]; X = [double]$f[3]; Y = [double]$f[4]; Z = [double]$f[5] }
        if ($oldPinMaps.ContainsKey($npc)) { $oldPinNpcSpawns[$npc] += @($spawn) }
        if ($enderNpcs[$npc]) { $enderSpawns[$npc] += @($spawn) }
        if (-not $starterNpcs[$npc]) { continue }
        $npcSpawns[$npc] += @($spawn)
        $holiday = $spawnHoliday[[int]$f[0]]
        if (-not $npcHoliday.ContainsKey($npc)) { $npcHoliday[$npc] = $holiday } elseif ($npcHoliday[$npc] -ne $holiday) { $npcHoliday[$npc] = $null }
    }
}
foreach ($npc in $oldPinNpcSpawns.Keys) {
    foreach ($spawn in $oldPinNpcSpawns[$npc]) {
        $maps = @($frames | Where-Object { $oldPinMaps[$npc].ContainsKey($_.UiMap) -and $_.Map -eq $spawn.Map -and
            $spawn.X -ge $_.MinX -and $spawn.X -le $_.MaxX -and $spawn.Y -ge $_.MinY -and $spawn.Y -le $_.MaxY } | Select-Object -ExpandProperty UiMap -Unique)
        if (-not $maps.Count) { continue }
        if ($maps.Count -gt 1) { $maps = @(Select-NearestOldPinMap $maps $oldPinMaps[$npc] $spawn.Map $spawn.X $spawn.Y) }
        $oldPinSpots["$($spawn.Map)|$([Math]::Floor($spawn.X / 100))|$([Math]::Floor($spawn.Y / 100))"] += @([pscustomobject]@{ X = $spawn.X; Y = $spawn.Y; UiMaps = $maps })
        foreach ($uiMap in ($maps | Where-Object { $cityMaps.ContainsKey($_) })) {
            $heights = $cityHeights[$uiMap]
            if (-not $heights) { $cityHeights[$uiMap] = [pscustomobject]@{ Min = $spawn.Z; Max = $spawn.Z }; continue }
            $heights.Min = [Math]::Min($heights.Min, $spawn.Z); $heights.Max = [Math]::Max($heights.Max, $spawn.Z)
        }
    }
}
$objectSpawns = @{}; $objectHoliday = @{}
foreach ($line in $dump.gameobject) {
    $f = $line.Split("`t")
    $objectEntries = if ([int]$f[1]) { @([int]$f[1]) } else { @($objectSpawnEntries[[int]$f[0]]) }
    foreach ($object in $objectEntries) {
        if (-not $starterObjects[$object]) { continue }
        $objectSpawns[$object] += @([pscustomobject]@{ Map = [int]$f[2]; X = [double]$f[3]; Y = [double]$f[4]; Z = [double]$f[5] })
        $holiday = $objectSpawnHoliday[[int]$f[0]]
        if (-not $objectHoliday.ContainsKey($object)) { $objectHoliday[$object] = $holiday } elseif ($objectHoliday[$object] -ne $holiday) { $objectHoliday[$object] = $null }
    }
}
$cmNpcName = @{}; foreach ($line in $dump.creature_template) { $f = $line.Split("`t"); if ($starterNpcs[[int]$f[0]]) { $cmNpcName[[int]$f[0]] = $f[1] } }
$objectName = @{}; foreach ($line in $dump.gameobject_template) { $f = $line.Split("`t"); if ($starterObjects[[int]$f[0]]) { $objectName[[int]$f[0]] = $f[1] } }

$cache = @{}
$cacheLines = [IO.File]::ReadAllLines($CacheFile)
foreach ($q in (('[' + ($cacheLines -join ',') + ']') | ConvertFrom-Json)) { $cache[[int]$q.id] = $q }
$probeResult = @{}; $gameNpcName = @{}; $probeSide = @{}
foreach ($line in $probeLines) {
    $f = $line.Split("`t")
    switch ($f[0]) {
        'quest' { if ($f[2] -eq $Build) { $probeResult[[int]$f[1]] = $f[3] } }
        'fact' { if ($f[2] -ceq 'factionGroup' -and ($f[3] -ceq '1' -or $f[3] -ceq '2')) { $probeSide[[int]$f[1]] = [int]$f[3] } }
        'npc' { if ($f[2] -eq $Build -and $f[4]) { $gameNpcName[[int]$f[1]] = $f[4] } }
    }
}

$keep = @{}; $removeOk = @{}
foreach ($d in (Read-RemovalDecisions $DecisionsFile 'forever')) {
    if ($d.Decision -eq 'KEEP') { $keep[$d.Quest] = $d } else { $removeOk[$d.Quest] = $d }
}
$memory = Read-AnswerMemory $AnswerFile
if (-not $memory.Runs.Count) {
    $earlier = Get-ChildItem "$ToolsDir\forever_quest_cache_*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^forever_quest_cache_(\d+\.\d+\.\d+\.\d+)\.jsonl$' -and [version]$Matches[1] -le [version]$Build } |
        Sort-Object { [version]($_.Name -replace '^forever_quest_cache_(.*)\.jsonl$', '$1') }
    foreach ($file in $earlier) {
        Update-AnswerMemory $memory (Read-CacheLines $file.FullName) $null ($file.Name -replace '^forever_quest_cache_(.*)\.jsonl$', '$1')
    }
}
Update-AnswerMemory $memory (Read-CacheLines $CacheFile) $probeResult $Build
$carried = Get-CarriedAnswers $memory $cache $MaxMissedRuns $keep $removeOk
foreach ($id in $carried.Keys) { $cache[$id] = $carried[$id].Raw | ConvertFrom-Json }
$gone = @(Get-QuestsMissedSince $memory $MaxMissedRuns | Where-Object { -not $cache.ContainsKey($_) })

$review = New-Object System.Collections.Generic.List[object]
function Add-Review([string]$kind, $quest, $other, [string]$detail) {
    $review.Add([pscustomobject]@{ Kind = $kind; Quest = $quest; Other = $other; Detail = $detail })
}
foreach ($spawn in $ambiguousSpawns) { Add-Review 'spawn in the events of several holidays' $null $spawn "CMaNGOS lists this spawn in events of more than one holiday, so it counts for none." }

foreach ($id in $keep.Keys) {
    if (-not $cache.ContainsKey($id) -and -not $cmQuest.ContainsKey($id)) { throw "$DecisionsFile says to keep quest $id, which neither the game's answers nor CMaNGOS have." }
}
$ids = @(@($cache.Keys) + @($keep.Keys) + @($cmQuest.Keys | Where-Object { $inClient[$_] -or ($cmQuest[$_].Special -band 1) }) | Sort-Object -Unique)
$records = @{}
$refiled = 0
$gameGivers = 0
$classFromItems = 0; $classByHand = 0
foreach ($id in $ids) {
    $c = $cache[$id]; $m = $cmQuest[$id]
    $title = if ($c) { $c.title } else { $m.Title }
    if (($title -cmatch $internalTitle -or (-not $m -and $title -match $gameOnlyJunk)) -and -not $keep[$id]) { Add-Review 'left out: internal title' $id '' $title; continue }
    if ($carried[$id]) { Add-Review 'kept from an earlier run: not answered now' $id '' "$title (last answered on $($carried[$id].Seen), $($carried[$id].Missed) runs ago)" }
    if (-not $c -and -not $inClient[$id] -and $probeResult[$id] -eq 'fail' -and $m.Level -ge 1 -and $m.Level -le 35 -and -not $keep[$id]) {
        Add-Review 'left out: failed on the beta below level 36' $id '' "$title (not in QuestV2)"
        continue
    }
    $category = if ($c -and [int]$c.sort) { [int]$c.sort } elseif ($m) { $m.Zone } else { 0 }
    if ($c -and -not [int]$c.sort -and $category) { Add-Review "no zone in the game's record, so CMaNGOS's" $id $category $title }
    if ($category -ne 0 -and -not $sortName.ContainsKey($category)) {
        Add-Review 'zone not in the client, so Uncategorized' $id $category $title
        $category = 0
    }
    $filedUnder = $category
    $category = Resolve-Category $category
    if ($category -ne $filedUnder) { $refiled++ }
    if ($c -and $m -and $sortName.ContainsKey($m.Zone) -and (Resolve-Category $m.Zone) -ne $category) {
        Add-Review 'zone differs from CMaNGOS' $id $m.Zone "$($sortName[$category]) / CMaNGOS: $($sortName[$m.Zone])"
    }
    if (-not $c) {
        if ($probeResult[$id] -eq 'fail' -and $m.Level -le 35) { Add-Review 'failed on the beta below level 36' $id '' $title }
        else { Add-Review 'not confirmed by the game yet' $id '' $title }
    }
    if (-not $inClient[$id]) {
        $cmangosSays = if (-not $m) { 'not in CMaNGOS' } elseif ($m.Special -band 1) { 'CMaNGOS: repeatable' } else { 'CMaNGOS: not repeatable' }
        Add-Review "not in the client's QuestV2" $id '' "$title ($cmangosSays)"
    }
    if ($c -and $c.giver) {
        $gameGivers++
        Add-Review 'giver named by the game' $id $c.giver "$title (CMaNGOS: $($creatureStarters[$id] -join ', '))"
    }

    $faction = 3; $race = 0
    if ($c -and $c.races) {
        foreach ($r in $c.races) { $race = $race -bor $raceBit[[int]$r] }
        $faction = if ($c.faction -eq 'Alliance') { 1 } elseif ($c.faction -eq 'Horde') { 2 } else { 3 }
    } elseif ($probeSide.ContainsKey($id)) {
        $faction = $probeSide[$id]
    } elseif ($m -and $m.Races -and ($m.Races -band 255) -ne 255) {
        $races = $m.Races -band 255
        $faction = if (-not ($races -band $hordeRaces)) { 1 } elseif (-not ($races -band $allianceRaces)) { 2 } else { 3 }
        if (-not $c -and $races -ne $allianceRaces -and $races -ne $hordeRaces) { $race = $races }
    }
    $class = 8191
    if ($m -and $m.Classes) { $class = $m.Classes -band 8191 }
    elseif ($classBySort.ContainsKey($category)) { $class = $classBySort[$category] }
    $items = $itemClass[$id]
    if ($items -and $items.Mask -ne $playableClasses -and ($class -band $playableClasses) -ne $items.Mask) {
        if ($creatureStarters[$id] -or $objectStarters[$id] -or $handStarters[$id] -or $recordedOffers[$id]) {
            Add-Review 'class of the items that start it not used: a giver starts it too' $id $items.Mask "$title (items $($items.Items -join ', '); the other sources say $class)"
        } else {
            Add-Review 'class from the items that start it' $id $items.Mask "$title (items $($items.Items -join ', '); the other sources say $class)"
            $class = $items.Mask; $classFromItems++
        }
    }
    if ($handClass.ContainsKey($id)) {
        if (($class -band $playableClasses) -eq $handClass[$id]) { Add-Review 'hand-kept class not needed: another source gives it' $id $handClass[$id] $title }
        elseif (($class -band $playableClasses) -ne $playableClasses) { Add-Review 'hand-kept class differs from the other sources' $id $handClass[$id] "$title (they say $class)" }
        $class = $handClass[$id]; $classByHand++
    }
    $skill = if ($m -and $m.Skill) { $m.Skill } elseif ($skillBySort.ContainsKey($category)) { $skillBySort[$category] } else { 0 }
    $profession = if ($professionBySkill.ContainsKey($skill)) { $professionBySkill[$skill] } else { 0 }
    $holiday = if ($questHoliday.ContainsKey($id)) { $questHoliday[$id] } elseif ($holidayBySort.ContainsKey($category)) { $holidayBySort[$category] }
        elseif ($m -and $holidayByCmangosSort.ContainsKey($m.Zone)) { $holidayByCmangosSort[$m.Zone] } else { 0 }
    if (-not $holiday) {
        $flags = @(@(foreach ($npc in $creatureStarters[$id]) { if ($npcHoliday.ContainsKey($npc)) { [int]$npcHoliday[$npc] } }) +
            @(foreach ($object in $objectStarters[$id]) { if ($objectHoliday.ContainsKey($object)) { [int]$objectHoliday[$object] } }) | Sort-Object -Unique)
        if ($flags.Count -eq 1 -and $flags[0]) { $holiday = $flags[0] }
    }
    if ($handHoliday.ContainsKey($id)) {
        if ($holiday -and $holiday -ne $handHoliday[$id]) { Add-Review 'hand-kept holiday differs from the other sources' $id $handHoliday[$id] "$title (they say flag $holiday)" }
        elseif ($holiday) { Add-Review 'hand-kept holiday not needed: another source gives it' $id $holiday $title }
        $holiday = $handHoliday[$id]
    }
    if ($category -eq $reputationSort -and $holiday -eq $aqWarEffort) {
        $category = $aqWarSort
        Add-Review 'Reputation heading, but the war effort''s: Ahn''Qiraj War' $id $category $title
    }
    $recurs = if ($c) { $c.recurs } else { $null }
    $type = if ($recurs -eq 'daily') { 4 } elseif ($recurs -eq 'weekly') { 128 } elseif ($m -and ($m.Special -band 1)) { 2 }
        elseif ($holiday -or $category -eq $seasonalSort) { 64 } elseif ($profession) { 32 } else { 1 }

    if ($c -and $null -eq $c.minLevel) { throw "$CacheFile gives quest $id no minLevel. Rerun Read-QuestCache.ps1." }
    $level = if ($c) { [int]$c.level } else { $m.Level }
    $minLevel = if ($c) { [int]$c.minLevel } else { $m.MinLevel }
    $records[$id] = [pscustomobject]@{ id = $id; name = $title; level = $level
        zone = $(if ($sortName.ContainsKey($category)) { $sortName[$category] } else { '' }); category = $category
        type = $type; faction = $faction; race = $race; class = $class; profession = $profession; holiday = $holiday
        covenant = 0; pvp = $(if ($(if ($pvpDecision.ContainsKey($id)) { $pvpDecision[$id] } elseif ($c) { [int]$c.questInfo -eq 41 } elseif ($m) { $m.Type -eq 41 } else { $false })) { 1 } else { 0 }); storyline = $(if ($storylineOf.ContainsKey($id)) { $storylineOf[$id] } else { 0 }); prereq = 0
        minLevel = $(if ($minLevel -ne $level) { $minLevel } else { $null }) }
}

# CMaNGOS's requirement, as mangos-classic's server checks it (ObjectMgr::LoadQuests, and
# SatisfyQuestPreviousQuest and SatisfyQuestCondition in Player.cpp). A quest's previous quests are its
# PrevQuestId, unless that is a breadcrumb, and every quest whose NextQuestId names it: any one of them
# will do. One in a negative ExclusiveGroup needs its whole group done instead, unless the quest has a
# PrevQuestId that isn't that one's NextQuestId. A negative PrevQuestId or NextQuestId counts only while
# that quest is in the log, which a prerequisite can't say: it goes in links.jsonl. The RequiredCondition must hold too: one
# that asks only for quests handed in, with and and or of up to four parts, is added. A requirement is a tree of quests
# ({Op='quest'; Id}) and of and and or ({Op; Items}); a part that can't be one is a string saying why.
$cmPrevious = @{}; $cmGroups = @{}
foreach ($id in ($cmQuest.Keys | Sort-Object)) {
    $m = $cmQuest[$id]
    $previous = $cmQuest[[Math]::Abs($m.Prev)]
    if ($m.Prev -and $previous -and -not $previous.BreadcrumbFor) { $cmPrevious[$id] += @($m.Prev) }
    $next = [Math]::Abs($m.Next)
    if ($next -and $cmQuest.ContainsKey($next)) { $cmPrevious[$next] += @([Math]::Sign($m.Next) * $id) }
    if ($m.Group) { $cmGroups[$m.Group] += @($id) }
}
function Get-NeedKey($need) {
    if ($need.Op -eq 'quest') { return '{0:D8}' -f $need.Id }
    return $need.Op + '(' + (($need.Items | ForEach-Object { Get-NeedKey $_ }) -join ',') + ')'
}
function Join-Need([string]$op, $parts) {
    $items = @{}
    foreach ($part in $parts) { foreach ($item in $(if ($part.Op -eq $op) { $part.Items } else { @($part) })) { $items[(Get-NeedKey $item)] = $item } }
    if ($items.Count -eq 1) { return @($items.Values)[0] }
    return [pscustomobject]@{ Op = $op; Items = @($items.Keys | Sort-Object | ForEach-Object { $items[$_] }) }
}
function Get-NeedQuests($need) {
    if ($need.Op -eq 'quest') { return $need.Id }
    foreach ($item in $need.Items) { Get-NeedQuests $item }
}
function ConvertTo-NeedValue($need) {
    if ($need.Op -eq 'quest') { return $need.Id }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($item in $need.Items) { $list.Add((ConvertTo-NeedValue $item)) }
    return , $list.ToArray()
}
function Get-PreviousNeed([int]$id) {
    $m = $cmQuest[$id]
    $inLog = @($cmPrevious[$id] | Where-Object { $_ -lt 0 } | ForEach-Object { -$_ } | Sort-Object -Unique)
    $wholeGroup = @($inLog | Where-Object { $cmQuest[$_].Group -lt 0 -and -not ($m.Prev -and $cmQuest[$_].Next -ne [Math]::Abs($m.Prev)) })
    if ($inLog.Count -and ($inLog.Count -lt @($cmPrevious[$id]).Count -or $wholeGroup.Count)) {
        return "a quest in the log, a whole group or another quest done, which nothing here can say: $($cmPrevious[$id] -join ', ')"
    }
    if ($inLog.Count) { return [pscustomobject]@{ Op = 'inlog'; Ids = $inLog } }
    $parts = @(foreach ($quest in $cmPrevious[$id]) {
        $previous = $cmQuest[$quest]
        if ($previous.Group -lt 0 -and -not ($m.Prev -and $previous.Next -ne $m.Prev)) {
            [pscustomobject]@{ Op = 'group'; Need = (Join-Need 'and' @($cmGroups[$previous.Group] | ForEach-Object { [pscustomobject]@{ Op = 'quest'; Id = $_ } })) }
        } else { [pscustomobject]@{ Op = 'quest'; Id = $quest } }
    })
    $need = Join-Need 'or' @($parts | ForEach-Object { if ($_.Op -eq 'group') { $_.Need } else { $_ } })
    if (@($parts | Where-Object { $_.Op -eq 'group' }).Count -and $need.Op -eq 'or') { return "a whole group or another quest, which the server checks in an order the dump doesn't give" }
    return $need
}
function Get-ConditionNeed([int]$entry, [int]$depth = 0) {
    $condition = $cmCondition[$entry]
    if (-not $condition -or $depth -gt 20) { return "condition $entry, which the dump lacks" }
    if ($condition.Type -eq 8 -and -not ($condition.Flags -band 1)) { return [pscustomobject]@{ Op = 'quest'; Id = $condition.Values[0] } }
    if (($condition.Type -eq -1 -or $condition.Type -eq -2) -and -not ($condition.Flags -band 1)) {
        $parts = @($condition.Values | Where-Object { $_ } | ForEach-Object { Get-ConditionNeed $_ ($depth + 1) })
        foreach ($part in $parts) { if ($part -is [string]) { return $part } }
        return Join-Need $(if ($condition.Type -eq -1) { 'and' } else { 'or' }) $parts
    }
    return "condition $entry ($($condition.Comment))"
}
foreach ($c in $recordedModel.NameConflicts) {
    Add-Review 'recorded giver: trusted sources disagree on the name, none used' '' $c.Giver $c.Names
}
foreach ($note in $(if ($probeNotes) { $probeNotes.UnknownQuests })) {
    if ($note.Role -eq 'offer' -and $records.ContainsKey([int]$note.Quest)) {
        Add-Review 'recorded offer not in the ledger yet: the quest is new' $note.Quest "$($note.Kind):$($note.Npc)" "$($records[[int]$note.Quest].name): run step 6d on the new data, then this again"
    }
}

$previousByNext = @{}
foreach ($c in $cache.Values) { if ($c.nextQuest -and [int]$c.nextQuest -ne [int]$c.id) { $previousByNext[[int]$c.nextQuest] += @([int]$c.id) } }
$fromCmangos = 0; $fromCondition = 0; $needsInLog = @{}
foreach ($q in $records.Values) {
    $m = $cmQuest[$q.id]
    $parts = @()
    if ($m -and $cmPrevious[$q.id]) { $parts += , (Get-PreviousNeed $q.id) }
    if ($m -and $m.Condition) { $parts += , (Get-ConditionNeed $m.Condition) }
    foreach ($why in @($parts | Where-Object { $_ -is [string] })) { Add-Review 'CMaNGOS requirement not a prerequisite' $q.id '' "$($q.name): $why" }
    foreach ($part in @($parts | Where-Object { $_.Op -eq 'inlog' })) {
        $imported = @($part.Ids | Where-Object { $records.ContainsKey($_) })
        if ($imported.Count) { $needsInLog[$q.id] = $imported }
        else { Add-Review 'CMaNGOS requirement not a prerequisite' $q.id '' "$($q.name): only while $($part.Ids -join ' or ') is in the log, none of them imported" }
    }
    $parts = @($parts | Where-Object { $_ -isnot [string] -and $_.Op -ne 'inlog' })
    if ($parts.Count) {
        $need = Join-Need 'and' $parts
        $missing = @(Get-NeedQuests $need | Where-Object { -not $records.ContainsKey($_) } | Sort-Object -Unique)
        if (-not $missing.Count) {
            $q.prereq = ConvertTo-NeedValue $need
            if ($need.Op -eq 'or') { $q.prereq = , $q.prereq }
            $fromCmangos++
            if ($m.Condition -and (Get-ConditionNeed $m.Condition) -isnot [string]) { $fromCondition++ }
            continue
        }
        Add-Review 'CMaNGOS requirement not a prerequisite' $q.id '' "$($q.name): it names quests not imported, $($missing -join ', ')"
    }
    if ($previousByNext[$q.id].Count -eq 1 -and $records.ContainsKey($previousByNext[$q.id][0])) { $q.prereq = $previousByNext[$q.id][0] }
}
$removedPrereq = @{}; $prereqsRemoved = 0
foreach ($id in ($handPrereqRemovals.Keys | Sort-Object)) {
    $drop = $handPrereqRemovals[$id]
    if (-not $records.ContainsKey($id)) { Add-Review 'hand-kept link for a quest not imported' $id $drop 'prereq'; continue }
    $q = $records[$id]
    $removedPrereq[$id] = $drop
    $prereqText = ConvertTo-PrereqText $q.prereq '[' ']'
    if ($prereqText -ne "$drop") { Add-Review 'hand-kept prerequisite removal not needed: the other sources don''t give it' $id $drop "$($q.name) (they say $prereqText)"; continue }
    $q.prereq = 0; $prereqsRemoved++
}
# Several SET rows for one quest are a choice: any one of their quests will do.
$prereqsSet = 0
foreach ($id in ($handPrereq.Keys | Sort-Object)) {
    $options = @($handPrereq[$id] | Sort-Object)
    if (-not $records.ContainsKey($id) -or @($options | Where-Object { -not $records.ContainsKey($_) }).Count) { Add-Review 'hand-kept link for a quest not imported' $id ($options -join ' or ') 'prereq'; continue }
    $need = if ($options.Count -eq 1) { $options[0] } else { ,(,[object[]]$options) }
    $q = $records[$id]
    $needText = ConvertTo-PrereqText $need '[' ']'
    if ((ConvertTo-PrereqText $q.prereq '[' ']') -eq $needText) { Add-Review 'hand-kept prerequisite not needed: another source gives it' $id $needText $q.name }
    elseif ($q.prereq) { Add-Review 'hand-kept prerequisite differs from the other sources' $id $needText "$($q.name) (they say $(ConvertTo-PrereqText $q.prereq '[' ']'))" }
    $q.prereq = $need; $prereqsSet++
}

$startMaps = @{}; $endMaps = @{}
foreach ($blob in $questBlobs) {
    $map = [int]$blob.UiMapID
    if (-not $map) { continue }
    if ($blob.ObjectiveIndex -eq '32') { $startMaps[[int]$blob.QuestID] += @($map) } else { $endMaps[[int]$blob.QuestID] += @($map) }
}
foreach ($id in @($endMaps.Keys)) { if (-not $startMaps.ContainsKey($id)) { $startMaps[$id] = $endMaps[$id] } }
$haveQuest = @{}
foreach ($id in $records.Keys) { $haveQuest[[int]$id] = $true }
$fromLine = 0
foreach ($step in (Get-QuestLineSteps (Group-QuestLines (Get-ClientTable 'QuestLineXQuest')) $startMaps $endMaps $haveQuest)) {
    $q = $records[$step.Quest]
    $after = "$($records[$step.Previous].name) ($($step.Previous)), step $($step.Step) of quest line $($step.Line)"
    if ($step.State -ne 'chain') { Add-Review "quest line order not used: $($step.State)" $step.Quest $step.Previous "$($q.name) after ${after}: $($step.Detail)"; continue }
    if ($removedPrereq[$step.Quest] -eq $step.Previous) { Add-Review 'quest line order not used: the hand list removes that prerequisite' $step.Quest $step.Previous "$($q.name) after $after"; continue }
    $prereqText = ConvertTo-PrereqText $q.prereq '[' ']'
    if (-not $q.prereq) { $q.prereq = $step.Previous; $fromLine++; Add-Review 'prerequisite from the quest line order' $step.Quest $step.Previous "$($q.name) after $after" }
    elseif ($prereqText -ne "$($step.Previous)") { Add-Review 'quest line order disagrees with the prerequisite' $step.Quest $step.Previous "$($q.name): the prerequisite is $prereqText, the quest line has $after" }
}

# The addon counts a prerequisite the character can't take as met, so a quest whose only prerequisite is
# for some classes is for them too, down the chain.
$classFromPrereq = 0
do {
    $narrowed = $false
    foreach ($q in ($records.Values | Sort-Object id)) {
        if (-not $q.prereq -or $q.prereq -is [array] -or -not $records.ContainsKey([int]$q.prereq)) { continue }
        $p = $records[[int]$q.prereq]
        $class = $q.class -band $p.class
        if (($class -band $playableClasses) -eq ($q.class -band $playableClasses)) { continue }
        if (-not ($class -band $playableClasses)) { throw "Quest $($q.id) ($($q.name), class $($q.class)) needs quest $($p.id) ($($p.name)), which only class $($p.class) can take: correct a class in $ClassFile or the prerequisite in $LinkFile." }
        Add-Review 'class from its prerequisite' $q.id $p.id "$($q.name): $class, was $($q.class)"
        $q.class = $class; $classFromPrereq++; $narrowed = $true
    }
} while ($narrowed)

$linkable = @{}
foreach ($q in $records.Values) { if (-not ($q.type -band (2 + 4 + 128))) { $linkable[$q.id] = $true } }
$breadcrumbs = @{}; $groups = @{}
foreach ($id in ($cmQuest.Keys | Sort-Object)) {
    if (-not $linkable[$id]) { continue }
    $m = $cmQuest[$id]
    if ($m.BreadcrumbFor -gt 0 -and $linkable[$m.BreadcrumbFor]) { $breadcrumbs[$m.BreadcrumbFor] += @($id) }
    if ($m.Group -gt 0) { $groups[$m.Group] += @($id) }
}
$exclusiveWith = @{}
foreach ($members in $groups.Values) {
    if ($members.Count -lt 2) { continue }
    foreach ($id in $members) { $exclusiveWith[$id] = @($members | Where-Object { $_ -ne $id }) }
}
$breadcrumbsAdded = 0
foreach ($key in ($handBreadcrumbs.Keys | Sort-Object)) {
    $target, $crumb = $handBreadcrumbs[$key]
    if (-not $records.ContainsKey($target) -or -not $records.ContainsKey($crumb)) { Add-Review 'hand-kept link for a quest not imported' $target $crumb 'breadcrumb'; continue }
    if (-not $linkable[$target] -or -not $linkable[$crumb]) { Add-Review 'hand-kept link for a recurring quest' $target $crumb 'breadcrumb'; continue }
    if ($breadcrumbs[$target] -contains $crumb) { Add-Review 'hand-kept breadcrumb not needed: CMaNGOS gives it' $target $crumb "$($records[$crumb].name) to $($records[$target].name)"; continue }
    $breadcrumbs[$target] = @(@($breadcrumbs[$target] | Where-Object { $_ }) + $crumb | Sort-Object)
    $breadcrumbsAdded++
}
# A quest closes once the quest its NextQuestInChain names is taken or done, and that one can't be taken
# while it is in the log (SatisfyQuestNextChain and SatisfyQuestPrevChain in Player.cpp), as for a
# breadcrumb. So it is one, unless the other quest needs it done, which closes nothing, or is the other faction's, which no character takes both of.
function Test-PrereqRequires($value, [int]$quest, [bool]$all = $true) {
    if ($value -isnot [array]) { return [int]$value -eq $quest }
    foreach ($item in $value) {
        $requires = Test-PrereqRequires $item $quest (-not $all)
        if ($requires -eq $all) { return $all }
    }
    return -not $all
}
$chainLeadIns = 0
foreach ($id in ($cmQuest.Keys | Sort-Object)) {
    $next = $cmQuest[$id].ChainNext
    if (-not $linkable[$id] -or -not $linkable[$next] -or $breadcrumbs[$next] -contains $id) { continue }
    if ($records[$id].faction -ne 3 -and $records[$next].faction -ne 3 -and $records[$id].faction -ne $records[$next].faction) { continue }
    if ($records[$next].prereq -and (Test-PrereqRequires $records[$next].prereq $id)) { continue }
    $breadcrumbs[$next] = @(@($breadcrumbs[$next] | Where-Object { $_ }) + $id | Sort-Object)
    $chainLeadIns++
}
$linked = 0
foreach ($pair in ($handLinks.Keys | Sort-Object)) {
    $a, $b = $handLinks[$pair]
    if (-not $records.ContainsKey($a) -or -not $records.ContainsKey($b)) { Add-Review 'hand-kept link for a quest not imported' $a $b 'exclusive'; continue }
    if (-not $linkable[$a] -or -not $linkable[$b]) { Add-Review 'hand-kept link for a recurring quest' $a $b 'exclusive'; continue }
    if ($exclusiveWith[$a] -contains $b) { Add-Review 'hand-kept link not needed: CMaNGOS already has the quests shut each other out' $a $b "$($records[$a].name) / $($records[$b].name)"; continue }
    $exclusiveWith[$a] = @(@($exclusiveWith[$a] | Where-Object { $_ }) + $b | Sort-Object)
    $exclusiveWith[$b] = @(@($exclusiveWith[$b] | Where-Object { $_ }) + $a | Sort-Object)
    $linked++
}
$unlinked = 0
foreach ($pair in ($handUnlinks.Keys | Sort-Object)) {
    $a, $b = $handUnlinks[$pair]
    if (-not $records.ContainsKey($a) -or -not $records.ContainsKey($b)) { Add-Review 'hand-kept link for a quest not imported' $a $b 'exclusive'; continue }
    if ($exclusiveWith[$a] -notcontains $b) { Add-Review 'hand-kept link removal not needed: the quests don''t shut each other out' $a $b "$($records[$a].name) / $($records[$b].name)"; continue }
    $exclusiveWith[$a] = @($exclusiveWith[$a] | Where-Object { $_ -ne $b })
    $exclusiveWith[$b] = @($exclusiveWith[$b] | Where-Object { $_ -ne $a })
    $unlinked++
}
foreach ($id in @($exclusiveWith.Keys)) { if (-not $exclusiveWith[$id].Count) { $exclusiveWith.Remove($id) } }
$exclusiveGroups = 0; $grouped = @{}
foreach ($id in ($exclusiveWith.Keys | Sort-Object)) {
    if ($grouped[$id]) { continue }
    $exclusiveGroups++
    $next = @($id)
    while ($next.Count) {
        $next = @(foreach ($member in $next) { if (-not $grouped[$member]) { $grouped[$member] = $true; $exclusiveWith[$member] } })
    }
}
$linkLines = @(foreach ($id in (@($breadcrumbs.Keys) + @($exclusiveWith.Keys) + @($needsInLog.Keys) | Sort-Object -Unique)) {
    $line = '{"quest":' + $id
    if ($breadcrumbs[$id]) { $line += ',"breadcrumbs":[' + ($breadcrumbs[$id] -join ',') + ']' }
    if ($exclusiveWith[$id]) { $line += ',"exclusiveWith":[' + ($exclusiveWith[$id] -join ',') + ']' }
    if ($needsInLog[$id]) { $line += ',"needsInLog":[' + ($needsInLog[$id] -join ',') + ']' }
    $line + '}'
})
$rewarding = 0; $cmangosOnlyReputation = 0
$reputationLines = @(foreach ($id in ($records.Keys | Sort-Object)) {
    $c = $cache[$id]
    if (-not $c) { if ($cmQuest[$id].Reputation) { $cmangosOnlyReputation++ }; continue }
    if ($null -eq $c.reputation) { continue }
    $rewarding++
    foreach ($reward in $c.reputation) {
        if ($reward -isnot [array] -or $reward.Count -ne 2) { throw "$CacheFile gives quest $id's reputation without amounts. Rerun Read-QuestCache.ps1." }
        '{"quest":' + $id + ',"faction":' + $reward[0] + ',"amount":' + $reward[1] + '}'
    }
})
# A required skill with no level (0) asks only that the character has learned it, as 1 does.
$skillLines = @(foreach ($id in ($records.Keys | Sort-Object)) {
    $m = $cmQuest[$id]
    if ($m -and $m.Skill) { '{"quest":' + $id + ',"skill":' + $m.Skill + ',"level":' + [Math]::Max(1, $m.SkillLevel) + '}' }
})

foreach ($npc in $gameNpcName.Keys) {
    if ($cmNpcName.ContainsKey($npc) -and $cmNpcName[$npc] -ne $gameNpcName[$npc]) { Add-Review 'NPC renamed' '' $npc "$($cmNpcName[$npc]) is now $($gameNpcName[$npc])" }
}

$giverZones = @{}
# Givers whose every quest recurs and isn't a holiday's: their pins show all year, done or not.
$everydayGivers = @{}
foreach ($q in $records.Values) {
    $keys = @($creatureStarters[$q.id] | ForEach-Object { "Creature:$_" }) + @($handStarters[$q.id] | Where-Object { $_ } | ForEach-Object { "Creature:$_" }) +
        @($objectStarters[$q.id] | ForEach-Object { "GameObject:$_" })
    foreach ($key in $keys) {
        $everyday = ($q.type -band (2 + 4 + 128)) -and -not $q.holiday
        $everydayGivers[$key] = $everyday -and (-not $everydayGivers.ContainsKey($key) -or $everydayGivers[$key])
        if ($q.category -le 0) { continue }
        if (-not $giverZones.ContainsKey($key)) { $giverZones[$key] = @{} }
        $giverZones[$key][$q.category] = $true
    }
}

function Get-GiverSpots([string]$kind, [int]$id) {
    $recorded = $recordedSpots["${kind}:$id"]
    if ($recorded) { return $recorded }
    $spawns = if ($kind -eq 'GameObject') { $objectSpawns[$id] } else { $npcSpawns[$id] }
    $spots = @()
    foreach ($spawn in $spawns) {
        $spot = Convert-ToMapSpot $spawn.Map $spawn.X $spawn.Y $giverZones["${kind}:$id"] $(if ($kind -ne 'GameObject') { $oldPinMaps[$id] }) -Z $spawn.Z
        if (-not $spot) { continue }
        $near = $spots | Where-Object { $_.UiMap -eq $spot.UiMap -and [Math]::Abs($_.X - $spot.X) -lt 3 -and [Math]::Abs($_.Y - $spot.Y) -lt 3 } | Select-Object -First 1
        if ($near) { $near.Spawns++ } else { $spots += ($spot | Add-Member -NotePropertyName Spawns -NotePropertyValue 1 -PassThru) }
    }
    if ($everydayGivers["${kind}:$id"] -and @($spots | Group-Object UiMap | Where-Object { $_.Count -gt 3 }).Count) {
        $spots = @($spots | Group-Object UiMap | ForEach-Object { $_.Group | Sort-Object { -$_.Spawns }, X, Y | Select-Object -First 1 })
    }
    return $spots
}

# The pins, grouped by PinRules.ps1: a giver's by its key (Creature:, GameObject: or Vehicle: and its entry), the
# start points that name nobody by spot alone.
$pins = New-Object System.Collections.Generic.List[object]
$pinGroups = New-PinGroups
$spotCache = @{}
$startPinned = 0

function Get-Pin([int]$map, [string]$giver, [decimal]$x, [decimal]$y, $new) {
    $pin = Find-PinGroup $pinGroups $map $giver $x $y
    if ($pin) { return $pin }
    $pins.Add($new)
    return Add-PinGroup $pinGroups $map $giver $x $y $new
}

function Add-StartPins([int]$id) {
    foreach ($spot in $startSpots[$id]) {
        $pin = Get-Pin $spot.UiMap '' $spot.X $spot.Y ([pscustomobject]@{ map = $spot.UiMap; icon = 1; npc = 0; name = $null; x = $spot.X; y = $spot.Y
            quests = (New-Object System.Collections.Generic.List[int]); note = $null; Kind = 'Start'; GiverId = 0 })
        if (-not $pin.quests.Contains($id)) { $pin.quests.Add($id) }
    }
}

foreach ($id in ($records.Keys | Sort-Object)) {
    $givers = New-Object System.Collections.Generic.List[string]
    foreach ($key in $recordedOffers[$id]) { if (-not $givers.Contains($key)) { $givers.Add($key) } }
    foreach ($npc in $creatureStarters[$id]) {
        $key = "Creature:$npc"
        if ($recordedOffers[$id] -and $recordedOffers[$id] -notcontains $key -and $recordedOffers[$id] -notcontains "Vehicle:$npc") {
            Add-Review 'recorder saw another giver' $id $npc "CMaNGOS: $($cmNpcName[$npc]); recorded: $($recordedOffers[$id] -join ', ')"
        }
        if (-not $givers.Contains($key)) { $givers.Add($key) }
    }
    foreach ($npc in $handStarters[$id]) {
        $key = "Creature:$npc"
        if ($recordedOffers[$id] -and $recordedOffers[$id] -notcontains $key -and $recordedOffers[$id] -notcontains "Vehicle:$npc") {
            Add-Review 'recorder saw another giver than the hand list' $id $npc "listed: $($cmNpcName[$npc]); recorded: $($recordedOffers[$id] -join ', ')"
            continue
        }
        if ($creatureStarters[$id] -or $objectStarters[$id]) { Add-Review "hand list adds to CMaNGOS's givers" $id $npc "$($records[$id].name): $($cmNpcName[$npc])" }
        if (-not $givers.Contains($key)) { $givers.Add($key) }
    }
    foreach ($object in $objectStarters[$id]) {
        $key = "GameObject:$object"
        if (-not $givers.Contains($key)) { $givers.Add($key) }
    }
    if ($givers.Count -eq 0) {
        $source = if (-not $cmQuest.ContainsKey($id)) { 'only the game knows it' } elseif ($itemStart.ContainsKey($id)) { "starts from item $($itemStart[$id])" } else { 'CMaNGOS has no giver' }
        if ($startSpots[$id]) {
            Add-StartPins $id
            $startPinned++
            Add-Review 'no giver: pin at its start point' $id '' "$($records[$id].name) ($source)"
        } else {
            Add-Review 'no giver' $id '' "$($records[$id].name) ($source)"
        }
        continue
    }
    $placed = New-Object System.Collections.Generic.List[object]
    foreach ($key in $givers) {
        $kind, $giverId = $key.Split(':')
        $giverId = [int]$giverId
        if (-not $spotCache.ContainsKey($key)) { $spotCache[$key] = @(Get-GiverSpots $kind $giverId) }
        $isObject = $kind -eq 'GameObject'
        $name = (Select-PinIdentity ([ordered]@{ game = $(if (-not $isObject) { $gameNpcName[$giverId] }); recorded = $recordedName[$key]
                    emulator = $(if ($isObject) { $objectName[$giverId] } else { $cmNpcName[$giverId] }) })).Value
        foreach ($spot in $spotCache[$key]) {
            $pin = Get-Pin $spot.UiMap $key $spot.X $spot.Y ([pscustomobject]@{ map = $spot.UiMap; icon = 1; npc = $(if ($isObject) { 0 } else { $giverId })
                name = $(if ($name) { $name } else { $null }); x = $spot.X; y = $spot.Y
                quests = (New-Object System.Collections.Generic.List[int]); note = $null; Kind = $kind; GiverId = $giverId })
            if (-not $pin.quests.Contains($id)) { $pin.quests.Add($id) }
            $placed.Add($pin)
        }
    }
    if (-not $placed.Count) {
        if ($startSpots[$id]) {
            Add-StartPins $id
            $startPinned++
            Add-Review 'giver not on a Forever map: pin at its start point' $id '' "$($records[$id].name) ($($givers -join ', '))"
        } else {
            Add-Review 'no pin: giver not on a Forever map' $id '' "$($records[$id].name) ($($givers -join ', '))"
        }
        continue
    }
    foreach ($spot in $startSpots[$id]) {
        $distances = @($placed | Where-Object { $_.map -eq $spot.UiMap } |
            ForEach-Object { [Math]::Sqrt([double](($_.x - $spot.X) * ($_.x - $spot.X) + ($_.y - $spot.Y) * ($_.y - $spot.Y))) })
        $closest = if ($distances.Count) { ($distances | Measure-Object -Minimum).Minimum } else { $null }
        if ($null -ne $closest -and $closest -le 3) { continue }
        $howFar = if ($null -eq $closest) { 'no pin of it on that map' } else { '{0:0.0} map points from its nearest pin' -f $closest }
        Add-Review "start point far from its giver's pin" $id '' ("{0}: start point on map {1} at {2} {3}, {4}" -f $records[$id].name, $spot.UiMap, $spot.X, $spot.Y, $howFar)
    }
}
foreach ($quest in $handStarters.Keys) { if (-not $records.ContainsKey($quest)) { Add-Review 'hand-listed quest not imported' $quest ($handStarters[$quest] -join ', ') '' } }
foreach ($removal in $handRemovedStarters) {
    if (-not $records.ContainsKey($removal.Quest)) { Add-Review 'hand-kept giver removal for a quest not imported' $removal.Quest $removal.Npc '' }
    elseif (-not $removal.Had) { Add-Review 'hand-kept giver removal not needed' $removal.Quest $removal.Npc "CMaNGOS doesn't list NPC $($removal.Npc) as a starter of it." }
}
foreach ($quest in $handHoliday.Keys) { if (-not $records.ContainsKey($quest)) { Add-Review 'hand-kept holiday for a quest not imported' $quest $handHoliday[$quest] '' } }
foreach ($quest in $handClass.Keys) { if (-not $records.ContainsKey($quest)) { Add-Review 'hand-kept class for a quest not imported' $quest $handClass[$quest] '' } }

# A heading that isn't a place gives way to the hand-kept zone, else the zone of the quest's pins' map,
# the most pins first, else that of the NPC it's handed in to, else CMaNGOS's zone.
$refiledQuests = @{}
foreach ($q in @($records.Values | Where-Object { $placelessSort[$_.category] } | Sort-Object id)) {
    $refiledQuests[$q.id] = $true
    $heading = $sortName[$q.category]
    $zones = @($pins | Where-Object { $_.quests.Contains($q.id) } | ForEach-Object { $uiMapArea[$_.map] } | Where-Object { $_ } |
        Group-Object | Sort-Object { -$_.Count }, { [int]$_.Name })
    $enderZones = @($(foreach ($npc in $creatureEnders[$q.id]) { foreach ($spawn in $enderSpawns[$npc]) {
            $spot = Convert-ToMapSpot $spawn.Map $spawn.X $spawn.Y $null $oldPinMaps[$npc] -Z $spawn.Z
            if ($spot -and $uiMapArea[$spot.UiMap]) { $uiMapArea[$spot.UiMap] } } }) |
        Group-Object | Sort-Object { -$_.Count }, { [int]$_.Name })
    $m = $cmQuest[$q.id]
    $listed = $handZone[$q.id]
    if ($listed -gt 0 -and $sortName.ContainsKey($listed)) { $zone = $listed; $kind = "heading isn't a place: hand-kept zone" }
    elseif ($zones.Count) { $zone = [int]$zones[0].Name; $kind = "heading isn't a place: its pins' zone" }
    elseif ($enderZones.Count) { $zone = [int]$enderZones[0].Name; $kind = "heading isn't a place, no pin: hand-in NPC's zone" }
    elseif ($m -and $m.Zone -and $sortName.ContainsKey($m.Zone) -and -not $placelessSort[$m.Zone]) { $zone = $m.Zone; $kind = "heading isn't a place, no pin: CMaNGOS's zone" }
    else { $zone = 0; $kind = "heading isn't a place, no pin: Uncategorized" }
    if ($listed -and $zone -ne $listed) { Add-Review "hand-kept zone isn't an area in the client" $q.id $listed $q.name }
    $q.category = Resolve-Category $zone
    $q.zone = if ($sortName.ContainsKey($q.category)) { $sortName[$q.category] } else { '' }
    Add-Review $kind $q.id $q.category "$($q.name): $heading -> $(if ($q.zone) { $q.zone } else { 'Uncategorized' })"
}
foreach ($quest in $handZone.Keys) {
    if (-not $records.ContainsKey($quest)) { Add-Review 'hand-kept zone for a quest not imported' $quest $handZone[$quest] '' }
    elseif (-not $refiledQuests[$quest]) { Add-Review "hand-kept zone not used: the quest's heading is a place" $quest $handZone[$quest] $records[$quest].name }
}

foreach ($pin in $pins) {
    $pin.icon = Get-PinQuestIcon @($pin.quests | ForEach-Object { $records[$_] })
    $pin.quests = @($pin.quests | Sort-Object)
}

foreach ($key in $recordedSpots.Keys) {
    $kind, $giverId = $key.Split(':')
    $spawns = if ($kind -eq 'GameObject') { $objectSpawns[[int]$giverId] } else { $npcSpawns[[int]$giverId] }
    if (-not $spawns) { continue }
    foreach ($spot in $recordedSpots[$key]) {
        $same = @($spawns | ForEach-Object { Convert-ToMapSpot $_.Map $_.X $_.Y -OnUiMap $spot.UiMap } | Where-Object { $_ })
        if (-not $same) { continue }
        $closest = ($same | ForEach-Object { [Math]::Sqrt([double](($_.X - $spot.X) * ($_.X - $spot.X) + ($_.Y - $spot.Y) * ($_.Y - $spot.Y))) } | Measure-Object -Minimum).Minimum
        if ($closest -gt 1) { Add-Review 'recorded spot far from CMaNGOS' '' $key ("{0} at {1:0.0} {2:0.0}: {3:0.0} map points from CMaNGOS's spawn" -f $recordedName[$key], $spot.X, $spot.Y, $closest) }
    }
}

foreach ($old in $oldPins) {
    $npc = $old.Npc; $x = $old.X; $y = $old.Y; $mapId = $old.UiMap
    foreach ($quest in $old.Quests) {
        if (-not $records.ContainsKey($quest) -or -not $creatureStarters[$quest]) { continue }
        if ($creatureStarters[$quest] -notcontains $npc) {
            Add-Review 'old pin names another giver' $quest $npc "old pin: $npc; CMaNGOS: $($creatureStarters[$quest] -join ', ')"
        }
    }
    if (-not $npcSpawns[$npc]) { continue }
    $spots = @($npcSpawns[$npc] | ForEach-Object { Convert-ToMapSpot $_.Map $_.X $_.Y -OnUiMap $mapId } | Where-Object { $_ })
    if (-not $spots) { continue }
    $closest = ($spots | ForEach-Object { [Math]::Sqrt([double](($_.X - $x) * ($_.X - $x) + ($_.Y - $y) * ($_.Y - $y))) } | Measure-Object -Minimum).Minimum
    if ($closest -gt 3) { Add-Review 'old pin far from the giver' '' $npc ("{0} on map {1} at {2} {3}: {4:0.0} map points from CMaNGOS's spawn" -f $cmNpcName[$npc], $mapId, $x, $y, $closest) }
}

$review | Sort-Object Kind, { [int]("0" + $_.Quest) }, { "$($_.Other)" } |
    Export-Csv -Path $ReviewFile -NoTypeInformation -Encoding UTF8

$questList = @($records.Values | Sort-Object id)
$duplicates = Remove-DuplicatePins @($pins | Sort-Object map, Kind, GiverId, x, y)
$pinList = $duplicates.Pins
$fromBoth = @($questList | Where-Object { $cache.ContainsKey($_.id) -and $cmQuest.ContainsKey($_.id) }).Count
$fromGame = @($questList | Where-Object { $cache.ContainsKey($_.id) -and -not $cmQuest.ContainsKey($_.id) }).Count
Write-Host ("{0} quests: {1} from the game and CMaNGOS, {2} from the game only, {3} from CMaNGOS only. {4} pins on {5} maps." -f
    $questList.Count, $fromBoth, $fromGame, ($questList.Count - $fromBoth - $fromGame), $pinList.Count, @($pinList | Select-Object -ExpandProperty map -Unique).Count)
$cmOnly = @($questList | Where-Object { -not $cache.ContainsKey($_.id) })
Write-Host ("Of the {0} quests from CMaNGOS only, {1} are repeatable (kept without the game) and {2} are not; {3} rows of the client's QuestV2 have never been answered by the game." -f
    $cmOnly.Count, @($cmOnly | Where-Object { $cmQuest[$_.id].Special -band 1 }).Count, @($cmOnly | Where-Object { -not ($cmQuest[$_.id].Special -band 1) }).Count, @($inClient.Keys | Where-Object { -not $cache.ContainsKey($_) }).Count)
Write-Host ("Pins of one name at one spot: {0} quests taken off {1} pins, {2} pins removed; {3} quests stay on pins further apart." -f
    $duplicates.TakenOff, $duplicates.Changed, $duplicates.Removed.Count, $duplicates.LeftAlone.Count)
Write-Host ("Answer memory: {0} quests over {1} runs; {2} that the game didn't answer this run are kept from earlier ones; {3} have missed {4} runs in a row." -f
    $memory.Quests.Count, $memory.Runs.Count, @($questList | Where-Object { $carried[$_.id] }).Count, $gone.Count, $MaxMissedRuns)
Write-Host ("{0} quests filed under a subzone or an instance's outdoor area are under their zone or instance." -f $refiled)
Write-Host ("Quests with a start point in the client's tables: {0} (ours: {1}; pinned there: {2}). Start points off their map: {3}. Quest records that name a giver: {4}." -f
    $startSpots.Count, @($startSpots.Keys | Where-Object { $records.ContainsKey($_) }).Count, $startPinned, $startOffMap, $gameGivers)
Write-Host ("Links: {0} breadcrumbs lead to {1} quests, {2} of {3} added by hand and {4} closed by their next quest in the chain; {5} quests are in {6} groups of which only one can be done, after {7} of {8} pairs added and {9} of {10} removed by hand; {11} quests can be taken only while another is in the log." -f
    @($breadcrumbs.Values | ForEach-Object { $_ }).Count, $breadcrumbs.Count, $breadcrumbsAdded, $handBreadcrumbs.Count, $chainLeadIns, $exclusiveWith.Count, $exclusiveGroups,
    $linked, $handLinks.Count, $unlinked, $handUnlinks.Count, $needsInLog.Count)
Write-Host ("Storylines: the client's QuestLine has {0} rows and QuestLineXQuest {1}; {2} of our quests belong to {3} storyline(s)." -f
    @(Get-ClientTable 'QuestLine').Count, @(Get-ClientTable 'QuestLineXQuest').Count,
    @($questList | Where-Object { $_.storyline }).Count, @($questList | Where-Object { $_.storyline } | Select-Object -ExpandProperty storyline -Unique).Count)
Write-Host ("Prerequisites: {0} quests have one, {1} of them a list (all of several quests, or one of several); {2} from CMaNGOS's requirement before the hand list, {3} of them with its RequiredCondition; {4} from the quest line order (each step after the one before it, where the places agree) and {5} by hand; {6} removed by hand." -f
    @($questList | Where-Object { $_.prereq }).Count, @($questList | Where-Object { $_.prereq -is [array] }).Count, $fromCmangos, $fromCondition, $fromLine, $prereqsSet, $prereqsRemoved)
Write-Host ("Classes: {0} quests are for some classes only; {1} took it from the items that start them, {2} from their prerequisite and {3} by hand." -f
    @($questList | Where-Object { ($_.class -band $playableClasses) -ne $playableClasses }).Count, $classFromItems, $classFromPrereq, $classByHand)
Write-Host ("Reputation: {0} rewards on {1} quests, from the game's records. {2} quests the game hasn't answered reward reputation in CMaNGOS." -f
    $reputationLines.Count, $rewarding, $cmangosOnlyReputation)
Write-Host ("Skills: {0} quests need a profession, {1} of them a level above 1." -f
    $skillLines.Count, @($skillLines | Where-Object { $_ -notmatch '"level":1\}$' }).Count)
Write-Host ("Recorded givers (the ledger's Forever rows): {0} with a place, {1} places, {2} quests with an offer; {3} rows wait for a second source and are not used." -f
    $recordedSpots.Count, @($recordedSpots.Values | ForEach-Object { $_ }).Count, $recordedOffers.Count,
    @($ledger.Values | Where-Object { $_.Game -eq 'forever' -and -not (Test-RecordedTrusted $_) }).Count)
$withMinLevel = @($questList | Where-Object { $null -ne $_.minLevel })
Write-Host ("Minimum levels: {0} quests need another level than their own, {1} from the game and {2} from CMaNGOS; {3} are above the quest's level, {4} are 0." -f
    $withMinLevel.Count, @($withMinLevel | Where-Object { $cache.ContainsKey($_.id) }).Count, @($withMinLevel | Where-Object { -not $cache.ContainsKey($_.id) }).Count,
    @($withMinLevel | Where-Object { $_.minLevel -gt $_.level }).Count, @($withMinLevel | Where-Object { $_.minLevel -eq 0 }).Count)
$review | Group-Object Kind | Sort-Object Name | ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Name, $_.Count) }
Write-Host "Review: $ReviewFile"

$questIds = @{}
foreach ($q in $questList) { $questIds[[int]$q.id] = $true }
$oldQuestPath = Join-Path $DataDir 'quests.jsonl'
$removed = @()
if (Test-Path $oldQuestPath) { $removed = @(Find-RemovedQuests ([IO.File]::ReadAllText($oldQuestPath)) $questIds) }
if ($removed.Count) {
    $removed | Select-Object Id, Name, Zone, Level, @{ n = 'Decision'; e = { if ($removeOk[$_.Id]) { 'REMOVE' } else { 'UNDECIDED' } } } |
        Export-Csv -Path $RemovalsFile -NoTypeInformation -Encoding UTF8
    Write-Host "Quests that would leave the data ($($removed.Count)), also in ${RemovalsFile}:"
    Format-RemovedQuests $removed $removeOk | ForEach-Object { Write-Host $_ }
}
elseif (Test-Path $RemovalsFile) { Remove-Item $RemovalsFile }
$undecided = @($removed | Where-Object { -not $removeOk[$_.Id] })
if ($undecided.Count) {
    $message = "$($undecided.Count) quests would leave the data and have no decision in $DecisionsFile. Review them with the user, add a KEEP or a REMOVE row for each, and run again. Nothing was written."
    if ($WhatIf) { Write-Host $message } else { throw $message }
}
if ($WhatIf) { return }

$DataDir = (New-Item -ItemType Directory -Force $DataDir).FullName
$questPath = Join-Path $DataDir 'quests.jsonl'
$pinPath = Join-Path $DataDir 'pins.jsonl'
[IO.File]::WriteAllText($questPath, (ConvertTo-QuestJsonLines $questList), $Utf8)
[IO.File]::WriteAllText($pinPath, (ConvertTo-PinJsonLines $pinList), $Utf8)
$problems = @(Find-UnknownFields $questPath $QuestFields) + @(Test-QuestRecords (Read-JsonLines $questPath)) +
    @(Find-UnknownFields $pinPath $PinFields) + @(Test-PinRecords (Read-JsonLines $pinPath))
if ($problems.Count) { throw "The written files don't pass AddonData.ps1's checks: $(($problems | Select-Object -First 5) -join '; ')" }
$linkPath = Join-Path $DataDir 'links.jsonl'
$reputationPath = Join-Path $DataDir 'reputation.jsonl'
$skillPath = Join-Path $DataDir 'skills.jsonl'
[IO.File]::WriteAllText($linkPath, (($linkLines | ForEach-Object { "$_`n" }) -join ''), $Utf8)
[IO.File]::WriteAllText($reputationPath, (($reputationLines | ForEach-Object { "$_`n" }) -join ''), $Utf8)
[IO.File]::WriteAllText($skillPath, (($skillLines | ForEach-Object { "$_`n" }) -join ''), $Utf8)
[IO.File]::WriteAllText($AnswerFile, (ConvertTo-AnswerLines $memory), $Utf8)
Write-Host "Written: $questPath, $pinPath, $linkPath, $reputationPath, $skillPath, $AnswerFile"
