<#
Two independent fixes to qcQuest.lua:

1. Remove the 10 duplicate stub entries mistakenly inserted by
   Insert-GapQuestEntries.ps1 - these quest IDs were misclassified as
   "missing" because the detection regex couldn't handle names containing
   escaped quotes (e.g. Grillok "Darkeye"). The pre-existing entries are
   correct and richer (real areaid, storyline/prereq links); keep those.

2. Fix 10 pre-existing invalid Lua escape sequences (predate this session
   entirely - e.g. "Crowleg\ Dan" instead of a valid escape). These were
   only discovered because this is the first time the full file has been
   syntax-checked with luac.
#>

$file = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"
$content = Get-Content $file -Raw

# --- Fix 1: remove the 10 duplicate stub lines I inserted ---
$duplicateIds = @(176, 10834, 25432, 26825, 26826, 45652, 57889, 63652, 79726, 86277)
$removedCount = 0
foreach ($id in $duplicateIds) {
    # Match only within my inserted block's line format (ends in ",0,0,0,0,0,0,0}," - 17 fields, areaid=0)
    $pattern = "(?m)^\[$id\]=\{$id,`"[^\r\n]*?`",\d+,`"[^`"]*`",0,1,\d,\d+,\d+,0,0,0,0,0,0,0,0\},\r?\n"
    $newContent = [regex]::Replace($content, $pattern, "", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($newContent -ne $content) { $removedCount++ }
    $content = $newContent
}
Write-Output "Removed $removedCount / $($duplicateIds.Count) duplicate stub lines"

# --- Fix 2: repair invalid escape sequences ---
# Group A: bare backslash with a matching \" later in the same entry - insert the missing quote
$pairedFixes = @{
    'Crowleg\ Dan' = $null  # no pair - handled in group B
}
$replacements = @(
    @{ Old = 'It''s Not \Ogre\" Yet'; New = 'It''s Not \"Ogre\" Yet' }
    @{ Old = 'The \Jinyu Princess\" Irrigation System'; New = 'The \"Jinyu Princess\" Irrigation System' }
    @{ Old = 'The \Earth-Slasher\" Master Plow'; New = 'The \"Earth-Slasher\" Master Plow' }
    @{ Old = '\Ancient\" Elven War'; New = '\"Ancient\" Elven War' }
    @{ Old = 'A \Humble\" Request'; New = 'A \"Humble\" Request' }
)
foreach ($r in $replacements) {
    if ($content.Contains($r.Old)) {
        $content = $content.Replace($r.Old, $r.New)
        Write-Output "Fixed: $($r.Old)"
    } else {
        Write-Output "NOT FOUND (already fixed or changed): $($r.Old)"
    }
}

# Group B: bare stray backslash with no evidenced pair - remove the backslash
$strayRemovals = @(
    'Crowleg\ Dan', 'Street \Cred', 'Define \Crazy', 'Magic\ Mushrooms', 'Thunder King\ Pest Repellers'
)
foreach ($s in $strayRemovals) {
    $fixed = $s.Replace('\', '')
    if ($content.Contains($s)) {
        $content = $content.Replace($s, $fixed)
        Write-Output "Fixed: $s -> $fixed"
    } else {
        Write-Output "NOT FOUND (already fixed or changed): $s"
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllBytes($file, $utf8NoBom.GetBytes($content))
Write-Output "Written."
