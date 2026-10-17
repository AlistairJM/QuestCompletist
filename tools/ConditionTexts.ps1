# The game's own text for a condition that holds quests back, for Sync-QuestConditionTexts.ps1 (docs/maintenance.md,
# step 2m) and its test. QuestConditions.ps1's Get-ConditionTextKeys says which conditions hold which quests back;
# this takes each one's text in every language. docs/plans/client-tables-audit.md, opportunity 4, part D.

# A condition's text, in the client's tables of one language: 'Player' (PlayerCondition.Failure_description_lang) and
# 'Chapter' (CampaignXCondition.FailureReason_lang), ID -> text, only for the IDs in $wanted (a set).
function Read-ConditionTexts($playerRows, $chapterRows, $wantedPlayer, $wantedChapter) {
    $texts = @{ Player = @{}; Chapter = @{} }
    foreach ($row in $playerRows) { if ($row.Failure_description_lang -and $wantedPlayer.ContainsKey([int]$row.ID)) { $texts.Player[[int]$row.ID] = $row.Failure_description_lang } }
    foreach ($row in $chapterRows) { if ($row.FailureReason_lang -and $wantedChapter.ContainsKey([int]$row.ID)) { $texts.Chapter[[int]$row.ID] = $row.FailureReason_lang } }
    return $texts
}

# The data file's records: for each key of Get-ConditionTextKeys ($keys, key -> quests, in order), its quests and its
# text in each language. $tables: locale -> Read-ConditionTexts' result, with English = $true for a language whose tables
# are enUS's under its name (as wago serves some), which is then left out. A text that is enUS's word for word is left
# out too: the addon shows enUS's for a language that has none. A key whose English text names a game variable
# ($pcMinLevel, which only the game can fill) or holds a control character is left out, and listed with why; a
# language's text with either is left out alone.
function Get-ConditionTextRecords($keys, $tables, $locales) {
    $records = New-Object System.Collections.Generic.List[object]
    $skipped = New-Object System.Collections.Generic.List[string]
    $bad = '\$[A-Za-z]|[\x00-\x1f]'
    foreach ($key in $keys.Keys) {
        $kind = if ($key.StartsWith('p')) { 'Player' } else { 'Chapter' }
        $id = [int]$key.Substring(1)
        $english = $tables['enUS'][$kind][$id]
        if (-not $english) { $skipped.Add("$key (quests $(@($keys[$key]) -join ', ')): no enUS text"); continue }
        if ($english -match $bad) { $skipped.Add("$key (quests $(@($keys[$key]) -join ', ')): '$english' holds a game variable or a control character"); continue }
        $record = [ordered]@{ key = $key; quests = @($keys[$key]); enUS = $english }
        foreach ($locale in $locales) {
            if ($locale -eq 'enUS' -or -not $tables.ContainsKey($locale) -or $tables[$locale].English) { continue }
            $text = $tables[$locale][$kind][$id]
            if ($text -and $text -cne $english -and $text -notmatch $bad) { $record[$locale] = $text }
        }
        $records.Add([pscustomobject]$record)
    }
    return [pscustomobject]@{ Records = $records.ToArray(); Skipped = $skipped.ToArray() }
}
