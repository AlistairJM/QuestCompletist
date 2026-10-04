<#
Writes data\quests.jsonl and data\pins.jsonl from the qcQuestDatabase rows of qcQuest.lua and from
qcPinDB.lua, keeping their order.

Until every tool writes the JSON Lines files itself, run this after any tool that changes those Lua
files, then Build-AddonData.ps1 -Check to confirm the two agree. It's deleted once they all do.
#>
param(
    [string]$AddonDir = (Join-Path $PSScriptRoot '..\QuestCompletist'),
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data')
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

$AddonDir = (Resolve-Path $AddonDir).Path
New-Item -ItemType Directory -Force $DataDir | Out-Null
$DataDir = (Resolve-Path $DataDir).Path

$quests = ConvertFrom-LuaQuestBlock ([IO.File]::ReadAllText((Join-Path $AddonDir 'qcQuest.lua')))
$pins = ConvertFrom-LuaPinFile ([IO.File]::ReadAllText((Join-Path $AddonDir 'qcPinDB.lua')))
[IO.File]::WriteAllText((Join-Path $DataDir 'quests.jsonl'), (ConvertTo-QuestJsonLines $quests), $script:Utf8)
[IO.File]::WriteAllText((Join-Path $DataDir 'pins.jsonl'), (ConvertTo-PinJsonLines $pins), $script:Utf8)
"Wrote $($quests.Count) quests and $($pins.Count) pins to $DataDir"
