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

$AddonDir = (Resolve-Path $AddonDir).Path
$DataDir = (Resolve-Path $DataDir).Path

$questData = Join-Path $DataDir 'quests.jsonl'
$pinData = Join-Path $DataDir 'pins.jsonl'
try {
    $quests = Read-JsonLines $questData
    $pins = Read-JsonLines $pinData
} catch {
    "  $($_.Exception.Message)"
    "The data files can't be read; nothing was written."
    exit 1
}
$problems = @(Find-UnknownFields $questData $QuestFields) + @(Test-QuestRecords $quests) +
    @(Find-UnknownFields $pinData $PinFields) + @(Test-PinRecords $pins)
if ($problems.Count -gt 0) {
    $problems | Select-Object -First 30 | ForEach-Object { "  $_" }
    if ($problems.Count -gt 30) { "  ... and $($problems.Count - 30) more" }
    "$($problems.Count) problem$(if ($problems.Count -ne 1) { 's' }) in the data files; nothing was written."
    exit 1
}

$questPath = Join-Path $AddonDir 'qcQuest.lua'
$pinPath = Join-Path $AddonDir 'qcPinDB.lua'
$questLua = [IO.File]::ReadAllText($questPath)
$outputs = @(
    @{ Path = $questPath; Old = $questLua; New = (Set-LuaQuestRows $questLua (ConvertTo-LuaQuestRows $quests)) },
    @{ Path = $pinPath; Old = [IO.File]::ReadAllText($pinPath); New = (ConvertTo-LuaPinFile $pins) }
)

$differ = 0
foreach ($output in $outputs) {
    $name = Split-Path -Leaf $output.Path
    if ($output.Old -ceq $output.New) { "${name}: up to date"; continue }
    $differ++
    if ($Check) {
        $old = $output.Old.Split("`n"); $new = $output.New.Split("`n")
        $i = 0
        while ($i -lt $old.Count -and $i -lt $new.Count -and $old[$i] -ceq $new[$i]) { $i++ }
        $show = { param($lines) if ($i -lt $lines.Count) { $lines[$i].TrimEnd("`r") } else { '(end of file)' } }
        "${name}: doesn't match the data files, first at line $($i + 1)"
        "  file: $(& $show $old)"
        "  data: $(& $show $new)"
    } else {
        [IO.File]::WriteAllText($output.Path, $output.New, (New-Object System.Text.UTF8Encoding $false))
        "${name}: written"
    }
}
"$($quests.Count) quests, $($pins.Count) pins"
if ($Check -and $differ -gt 0) { exit 1 }
