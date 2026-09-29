<#
Corrects qcAreaIDToCategoryID entries that file a UiMap under the wrong quest category, found by
comparing every mapped id against wago.tools' UiMap export (see docs/plans/quest-reputation-data.md
for the probe that surfaced them).

Each fix states the UiMap's real name and the category it currently lands in. All-or-nothing: if
any entry no longer holds the expected old value, nothing is written.
#>
param(
    [string]$QuestFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"
)

# uimap id, its name in UiMap.db2, current category, corrected category
$fixes = @(
    @{ Map = 41;   Name = "Dalaran";                   From = 70;   To = 1003 }
    @{ Map = 86;   Name = "Orgrimmar";                 From = 147;  To = 148 }
    @{ Map = 168;  Name = "The Violet Hold";           From = 83;   To = 1036 }
    @{ Map = 179;  Name = "Gilneas";                   From = 84;   To = 83 }
    @{ Map = 219;  Name = "Zul'Farrak";                From = 3;    To = 278 }
    @{ Map = 220;  Name = "The Temple of Atal'Hakkar"; From = 3;    To = 198 }
    @{ Map = 221;  Name = "Blackfathom Deeps";         From = 3;    To = 21 }
    @{ Map = 469;  Name = "New Tinkertown";            From = 63;   To = 144 }
    @{ Map = 470;  Name = "Frostmane Hold";            From = 144;  To = 63 }
    @{ Map = 678;  Name = "Vault of the Wardens";      From = 83;   To = 1035 }
    @{ Map = 1673; Name = "Oribos";                    From = 1206; To = 1204 }
)

$content = [System.IO.File]::ReadAllText($QuestFile, [System.Text.Encoding]::UTF8)

$block = [regex]::Match($content, '(?sm)^qcAreaIDToCategoryID=\{(.*?)^\}')
if (-not $block.Success) { throw "qcAreaIDToCategoryID block not found" }
$blockText = $block.Groups[1].Value

$categories = @{}
foreach ($m in [regex]::Matches([regex]::Match($content, '(?sm)^qcQuestCategories=\{(.*?)^\}').Groups[1].Value, '\{(\d+),"((?:[^"\\]|\\.)*)"\}')) {
    $categories[[int]$m.Groups[1].Value] = $m.Groups[2].Value
}

$errors = New-Object System.Collections.Generic.List[string]
$updated = $blockText
foreach ($fix in $fixes) {
    if (-not $categories.ContainsKey($fix.To)) { $errors.Add("target category $($fix.To) does not exist"); continue }
    $pattern = "\[$($fix.Map)\]=$($fix.From)(?=[,\r\n])"
    $hits = [regex]::Matches($updated, $pattern)
    if ($hits.Count -ne 1) { $errors.Add("uimap $($fix.Map)=$($fix.From) matched $($hits.Count) times, expected 1"); continue }
    $updated = [regex]::Replace($updated, $pattern, "[$($fix.Map)]=$($fix.To)")
    "  [$($fix.Map)] $($fix.Name): $($fix.From) '$($categories[$fix.From])' -> $($fix.To) '$($categories[$fix.To])'"
}

if ($errors.Count) { throw "Refusing to write:`n" + ($errors -join "`n") }

$content = $content.Substring(0, $block.Groups[1].Index) + $updated + $content.Substring($block.Groups[1].Index + $block.Groups[1].Length)
[System.IO.File]::WriteAllText($QuestFile, $content, (New-Object System.Text.UTF8Encoding $false))
"Applied $($fixes.Count) corrections."
