<#
Fixes a real bug: Insert-GapQuestEntries.ps1 used .IndexOf("qcQuestDatabase={")
which matched a COMMENT containing that literal text at line ~2815, not the
actual table declaration - so all 425 backfilled entries ended up inside
qcOverrideWeeklyQuestTypesBasedOnStorylineId instead of qcQuestDatabase.

This removes that whole misplaced block and re-inserts it into the real
qcQuestDatabase table, this time matching only a start-of-line declaration.
#>

$file = "C:\Users\alist\RiderProjects\QuestCompletist\QuestCompletist\qcQuest.lua"
$content = Get-Content $file -Raw

# Scope the search to right after the misplaced table's declaration line, to
# avoid any risk of matching an unrelated comment block elsewhere in this huge file.
$tableDeclMatch = [regex]::Match($content, "(?m)^qcOverrideWeeklyQuestTypesBasedOnStorylineId = \{[^\r\n]*\r?\n")
if (-not $tableDeclMatch.Success) { throw "Could not find qcOverrideWeeklyQuestTypesBasedOnStorylineId declaration" }
$searchFrom = $tableDeclMatch.Index + $tableDeclMatch.Length

$badBlockPattern = "(?m)\G(?:^--[^\r\n]*\r?\n)+(?:\[\d+\]=\{[^\r\n]*\},\r?\n)+"
$match = [regex]::Match($content.Substring($searchFrom), $badBlockPattern)
if (-not $match.Success) { throw "Could not find the misplaced block to remove" }
$absoluteIndex = $searchFrom + $match.Index
Write-Output "Found misplaced block at index $absoluteIndex, length $($match.Length) chars, removing..."
$content = $content.Remove($absoluteIndex, $match.Length)

# Find the REAL qcQuestDatabase declaration - anchored at start of line, not inside a comment
$realMarkerMatch = [regex]::Match($content, "(?m)^qcQuestDatabase=\{")
if (-not $realMarkerMatch.Success) { throw "Could not find the real qcQuestDatabase={ declaration" }
$insertAt = $realMarkerMatch.Index + $realMarkerMatch.Length
Write-Output "Real qcQuestDatabase={ found at index $($realMarkerMatch.Index)"

$block = $match.Value  # reuse the exact same text block, just relocated
$newContent = $content.Substring(0, $insertAt) + "`n" + $block + $content.Substring($insertAt)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllBytes($file, $utf8NoBom.GetBytes($newContent))
Write-Output "Relocated block into the real qcQuestDatabase table."
