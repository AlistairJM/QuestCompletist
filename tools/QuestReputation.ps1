<#
Shared reading of our reputation data, dot-sourced by Compare-QuestReputation.ps1 and
Audit-QuestAccuracy.ps1.

Rewards live in the qcQuestReputation side table, keyed by quest ID:
	[12008]={[72]=150},
	[51515]={[2103]=350,[1133]=350},
Quests with no reward aren't listed. qcQuestDatabase entries are 14 fields and carry none.
#>

# Splits on top-level commas only, so quoted names and {..} tables stay intact.
function Split-Top($s) {
    $out = New-Object System.Collections.Generic.List[string]
    $depth = 0; $inStr = $false; $cur = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($inStr) { [void]$cur.Append($ch); if ($ch -eq '\') { $i++; [void]$cur.Append($s[$i]) } elseif ($ch -eq '"') { $inStr = $false }; continue }
        if ($ch -eq '"') { $inStr = $true } elseif ($ch -eq '{') { $depth++ } elseif ($ch -eq '}') { $depth-- }
        if ($ch -eq ',' -and $depth -eq 0) { $out.Add($cur.ToString()); [void]$cur.Clear() } else { [void]$cur.Append($ch) }
    }
    $out.Add($cur.ToString())
    return ,$out
}

# Takes the whole qcQuest.lua text; returns @{ questID = @{ factionID = value } } for non-zero rewards.
function Get-QuestReputation($content) {
    $out = @{}
    $block = [regex]::Match($content, '(?s)^qcQuestReputation = \{(.*?)^\}', "Multiline")
    if (-not $block.Success) { throw "qcQuestReputation table not found" }
    foreach ($m in [regex]::Matches($block.Groups[1].Value, '(?m)^\s*\[(\d+)\]=\{(.*?)\},?\s*$')) {
        $set = @{}
        foreach ($p in [regex]::Matches($m.Groups[2].Value, '\[(\d+)\]=(-?\d+)')) {
            if ($p.Groups[2].Value -ne "0") { $set[$p.Groups[1].Value] = [int]$p.Groups[2].Value }
        }
        if ($set.Count) { $out[$m.Groups[1].Value] = $set }
    }
    return $out
}
