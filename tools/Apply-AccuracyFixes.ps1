<#
Applies one field's FIX decisions from quest_accuracy_candidates.csv (written by
Categorize-AuditDiscrepancies.ps1) to qcQuest.lua. Only the named field is rewritten;
everything before and after it on the line is kept byte-for-byte. Aborts without
writing if any target line is missing or its current value differs from the CSV's.
#>
param(
    [Parameter(Mandatory)][ValidateSet("faction", "race", "class")][string]$Field,
    [string]$CandidatesCsv = "C:\Users\alist\RiderProjects\QuestCompletist\tools\quest_accuracy_candidates.csv",
    [string]$QuestFile = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"
)

$fixes = @{}
Import-Csv $CandidatesCsv | Where-Object { $_.Field -eq $Field -and $_.Decision -eq "FIX" } | ForEach-Object { $fixes[$_.QuestID] = $_ }
Write-Output "$($fixes.Count) $Field fixes to apply."

$content = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($QuestFile))
$loneLf = [regex]::Matches($content, "(?<!`r)`n").Count
if ($loneLf) { throw "qcQuest.lua already has $loneLf lone-LF line endings - fix those first." }
$lines = $content -split "`r`n"
$anchor = [array]::IndexOf($lines, ($lines | Where-Object { $_ -match '^qcQuestDatabase=\{' } | Select-Object -First 1))
if ($anchor -lt 0) { throw "qcQuestDatabase anchor not found." }

$pattern = '^(\[(\d+)\]=\{\d+,"(?:[^"\\]|\\.)*",(?:\d+|Unknown),"(?:[^"\\]|\\.)*",-?\d+,\d+,)(\d+),(\d+),(\d+)(,.*)$'
$fieldGroup = @{ faction = 3; race = 4; class = 5 }[$Field]
$applied = @{}
$problems = New-Object System.Collections.Generic.List[string]

for ($i = $anchor + 1; $i -lt $lines.Count; $i++) {
    $m = [regex]::Match($lines[$i], $pattern)
    if (-not $m.Success -or -not $fixes.ContainsKey($m.Groups[2].Value)) { continue }
    $id = $m.Groups[2].Value
    $fix = $fixes[$id]
    if ($applied.ContainsKey($id)) { $problems.Add("$id appears on more than one line"); continue }
    if ($m.Groups[$fieldGroup].Value -ne $fix.Cur) { $problems.Add("$id current $Field is $($m.Groups[$fieldGroup].Value), CSV expected $($fix.Cur)"); continue }
    $vals = @($m.Groups[3].Value, $m.Groups[4].Value, $m.Groups[5].Value)
    $vals[$fieldGroup - 3] = $fix.Target
    $lines[$i] = $m.Groups[1].Value + ($vals -join ",") + $m.Groups[6].Value
    $applied[$id] = $true
}
foreach ($id in $fixes.Keys) { if (-not $applied.ContainsKey($id) -and -not ($problems -match "^$id ")) { $problems.Add("$id not found in qcQuestDatabase") } }

if ($problems.Count) {
    $problems | ForEach-Object { Write-Output "PROBLEM: $_" }
    throw "$($problems.Count) problem(s) - nothing written."
}
[System.IO.File]::WriteAllText($QuestFile, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
Write-Output "Applied $($applied.Count) $Field fixes to $QuestFile."
