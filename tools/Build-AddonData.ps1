<#
Builds the addon's quest and pin data from data\quests.jsonl and data\pins.jsonl: the
qcQuestDatabase rows of QuestCompletist\qcQuest.lua, leaving the rest of that file as it is, and
the whole of QuestCompletist\qcPinDB.lua. The records are checked first; if any problem is found,
nothing is written.

-Check writes nothing. It says whether the Lua files already match the data files, and exits with 1
if they don't. Run it before every pull request that touches the data.
#>
param(
    [switch]$Check,
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data')
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

$build = Invoke-AddonDataBuild -DataDir $DataDir -AddonDir $AddonDir -Check:$Check
$build.Lines
if (-not $build.Ok) { exit 1 }
