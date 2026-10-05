<#
Builds the addon's quest and pin data from the data files: the whole of qcQuestData.lua (qcQuestDatabase
and the tables of rarer fields beside it) and the whole of qcPinDB.lua. With no folders given it builds
both games: data\ into QuestCompletist\ for retail, and data\forever\ into QuestCompletist\Forever\
for WoW: Forever (docs/plans/forever.md). The records are checked first; if any problem is found,
nothing is written for that game.

-Check writes nothing. It says whether the Lua files already match the data files, and exits with 1
if they don't. Run it before every pull request that touches the data.
#>
param(
    [switch]$Check,
    [string]$AddonDir = '',
    [string]$DataDir = ''
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AddonData.ps1"

$targets = New-Object System.Collections.Generic.List[object]
if ($AddonDir -or $DataDir) {
    $targets.Add([pscustomobject]@{ Data = $(if ($DataDir) { $DataDir } else { $DefaultDataDir }); Addon = $(if ($AddonDir) { $AddonDir } else { $DefaultAddonDir }) })
} else {
    $targets.Add([pscustomobject]@{ Data = $DefaultDataDir; Addon = $DefaultAddonDir })
    $foreverData = Join-Path $DefaultDataDir 'forever'
    if (Test-Path (Join-Path $foreverData 'quests.jsonl')) {
        $targets.Add([pscustomobject]@{ Data = $foreverData; Addon = (Join-Path $DefaultAddonDir 'Forever') })
    }
}

$ok = $true
foreach ($target in $targets) {
    if (-not $Check) { New-Item -ItemType Directory -Force $target.Addon | Out-Null }
    if ($targets.Count -gt 1) { "From $((Resolve-Path $target.Data).Path):" }
    $build = Invoke-AddonDataBuild -DataDir $target.Data -AddonDir $target.Addon -Check:$Check
    $build.Lines
    if (-not $build.Ok) { $ok = $false }
}
if (-not $ok) { exit 1 }
