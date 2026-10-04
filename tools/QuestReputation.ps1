<#
Shared reading of our reputation data, dot-sourced by Compare-QuestReputation.ps1,
Audit-QuestAccuracy.ps1 and Apply-ReputationBackfill.ps1.

Rewards live in the qcQuestReputation side table in qcQuest.lua, keyed by quest ID:
	[12008]={[72]=150},
	[51515]={[2103]=350,[1133]=350},
Quests with no reward aren't listed. The quests themselves (data\quests.jsonl) carry none.
#>

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
