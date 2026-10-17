<#
Shared reading and writing of the quest and pin data, dot-sourced by Build-AddonData.ps1 and every
tool that reads or changes quests or pins:
	. "$PSScriptRoot\AddonData.ps1"

data\quests.jsonl and data\pins.jsonl are the master copy of the quests and pins. They hold one
record per line, with named fields:
	{"id":176,"name":"WANTED:  \"Hogger\"","level":1,"zone":"Elwynn Forest","category":70,"type":1,"faction":1,"race":64175181,"class":8191,"storyline":566}
	{"map":84,"icon":1,"npc":29611,"name":"King Varian Wrynn","x":26.12,"y":47.32,"quests":[26365]}
Fields that are empty are left out: a quest's profession, holiday, covenant, pvp, storyline and prereq
when 0, and a pin's npc when 0, its name when it has none and its note when it has none. A quest's
prereq is the quest to do first, or a list of quests that all must be done; a list inside that
list is a choice, any one of which will do, and a list inside a choice is all of it again:
[57115,57116] needs both, and [[10983,10989,11057]] needs any one of the three. A quest's level is
its row's second value; minLevel, the level a character needs to accept the quest, is left out when
it is the same, and kept when it is 0 (no minimum). maxLevel, the level a scaling quest stops scaling
at (Apply-QuestScaling.ps1), is left out for a quest that doesn't scale. The records become the whole of
QuestCompletist\qcQuestData.lua, in file order (see ConvertTo-LuaQuestFile for its layout), and the
whole of qcPinDB.lua, map by map in ascending order. Both start with a line saying they're generated.
data\startitems.jsonl, written by Sync-QuestStartItems.ps1 and optional, holds the items that start quests,
one per line, with what the item itself requires (ConvertTo-LuaStartItemTable has the fields); it becomes
qcQuestStartItems at the end of qcQuestData.lua.
data\conditiontexts.jsonl, written by Sync-QuestConditionTexts.ps1 and optional, holds the game's own text for
a condition that holds quests back, one per line: its key, the quests and the text in each of the client's
languages, enUS's always ({"key":"c15","quests":[51571],"enUS":"...","deDE":"..."}); it becomes
qcQuestConditionTexts and qcConditionTexts at the end of qcQuestData.lua.
#>

$script:Invariant = [Globalization.CultureInfo]::InvariantCulture
$script:Utf8 = New-Object System.Text.UTF8Encoding $false
$DefaultDataDir = Join-Path $PSScriptRoot '..\data'
$DefaultAddonDir = Join-Path $PSScriptRoot '..\QuestCompletist'

$QuestFields = @('id', 'name', 'level', 'zone', 'category', 'type', 'faction', 'race', 'class',
    'profession', 'holiday', 'covenant', 'pvp', 'storyline', 'prereq', 'minLevel', 'maxLevel')
$QuestOptionalFields = @('profession', 'holiday', 'covenant', 'pvp', 'storyline', 'prereq', 'minLevel', 'maxLevel')
$PinFields = @('map', 'icon', 'npc', 'name', 'x', 'y', 'quests', 'note')
$StartItemFields = @('item', 'quest', 'side', 'level', 'skill', 'skillRank', 'rep', 'repRank', 'races')
$ConditionTextLocales = @('enUS', 'deDE', 'esES', 'esMX', 'frFR', 'itIT', 'koKR', 'ptBR', 'ruRU', 'zhCN', 'zhTW')
$ConditionTextFields = @('key', 'quests') + $ConditionTextLocales

function Test-WholeNumber($value) { return ($value -is [int]) -or ($value -is [long]) }
function Test-DataNumber($value) { return (Test-WholeNumber $value) -or ($value -is [decimal]) }

# A prereq that's a list, written as JSON ([1,[2,3]]) or Lua ({1,{2,3}}), and the check of its shape:
# quest IDs above 0, and lists that aren't empty.
function ConvertTo-PrereqText($value, [string]$open, [string]$close) {
    if ($value -isnot [array]) { return "$value" }
    return $open + (($value | ForEach-Object { ConvertTo-PrereqText $_ $open $close }) -join ',') + $close
}
function Test-PrereqValue($value) {
    if (Test-WholeNumber $value) { return $value -gt 0 }
    if ($value -isnot [array] -or $value.Count -eq 0) { return $false }
    foreach ($item in $value) { if (-not (Test-PrereqValue $item)) { return $false } }
    return $true
}
# The quests a prereq names, however it nests them.
function Get-PrereqQuests($value) {
    if ($value -isnot [array]) { return , @([int]$value) }
    $ids = @()
    foreach ($item in $value) { $ids += Get-PrereqQuests $item }
    return , $ids
}

# The text of quests.jsonl and pins.jsonl. Strings go in double quotes with \ and " escaped (the
# same in Lua and JSON; control characters are refused by the checks), and numbers are written the
# shortest way: 47.3 rather than 47.30. Like the Lua writers further down, these do it inline: a
# function call per field made writing them take a minute. A profession, holiday, covenant,
# storyline or prereq of 0 is left out, as is a pin's npc of 0; a minLevel is left out only when it
# is missing, since 0 is a minimum, and so is a maxLevel.
function ConvertTo-QuestJsonLines($quests) {
    $sb = New-Object System.Text.StringBuilder (6MB)
    foreach ($q in $quests) {
        [void]$sb.Append('{"id":' + $q.id + ',"name":"' + $q.name.Replace('\', '\\').Replace('"', '\"') + '","level":' + $q.level +
            ',"zone":"' + $q.zone.Replace('\', '\\').Replace('"', '\"') + '","category":' + $q.category + ',"type":' + $q.type +
            ',"faction":' + $q.faction + ',"race":' + $q.race + ',"class":' + $q.class)
        if ($q.profession) { [void]$sb.Append(',"profession":' + $q.profession) }
        if ($q.holiday) { [void]$sb.Append(',"holiday":' + $q.holiday) }
        if ($q.covenant) { [void]$sb.Append(',"covenant":' + $q.covenant) }
        if ($q.pvp) { [void]$sb.Append(',"pvp":' + $q.pvp) }
        if ($q.storyline) { [void]$sb.Append(',"storyline":' + $q.storyline) }
        $prereq = $q.prereq
        if ($prereq) { [void]$sb.Append(',"prereq":' + $(if ($prereq -is [array]) { ConvertTo-PrereqText $prereq '[' ']' } else { $prereq })) }
        if ($null -ne $q.minLevel) { [void]$sb.Append(',"minLevel":' + $q.minLevel) }
        if ($null -ne $q.maxLevel) { [void]$sb.Append(',"maxLevel":' + $q.maxLevel) }
        [void]$sb.Append("}`n")
    }
    return $sb.ToString()
}

function ConvertTo-PinJsonLines($pins) {
    $sb = New-Object System.Text.StringBuilder (2MB)
    foreach ($pin in $pins) {
        $x = $pin.x; if ($x -is [decimal]) { $x = $x.ToString('0.############################', $script:Invariant) }
        $y = $pin.y; if ($y -is [decimal]) { $y = $y.ToString('0.############################', $script:Invariant) }
        [void]$sb.Append('{"map":' + $pin.map + ',"icon":' + $pin.icon)
        if ($pin.npc) { [void]$sb.Append(',"npc":' + $pin.npc) }
        if ($null -ne $pin.name) { [void]$sb.Append(',"name":"' + $pin.name.Replace('\', '\\').Replace('"', '\"') + '"') }
        [void]$sb.Append(',"x":' + $x + ',"y":' + $y + ',"quests":[' + ($pin.quests -join ',') + ']')
        if ($null -ne $pin.note) { [void]$sb.Append(',"note":"' + $pin.note.Replace('\', '\\').Replace('"', '\"') + '"') }
        [void]$sb.Append("}`n")
    }
    return $sb.ToString()
}

function ConvertTo-StartItemJsonLines($items) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($s in $items) {
        [void]$sb.Append('{"item":' + $s.item + ',"quest":' + $s.quest)
        foreach ($field in 'side', 'level', 'skill', 'skillRank', 'rep', 'repRank') { if ($s.$field) { [void]$sb.Append(',"' + $field + '":' + $s.$field) } }
        if ($s.races) { [void]$sb.Append(',"races":[' + (@($s.races) -join ',') + ']') }
        [void]$sb.Append("}`n")
    }
    return $sb.ToString()
}

function ConvertTo-ConditionTextJsonLines($texts) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($t in $texts) {
        [void]$sb.Append('{"key":"' + $t.key + '","quests":[' + (@($t.quests) -join ',') + ']')
        foreach ($locale in $ConditionTextLocales) { if ($t.$locale) { [void]$sb.Append(',"' + $locale + '":"' + $t.$locale.Replace('\', '\\').Replace('"', '\"') + '"') } }
        [void]$sb.Append("}`n")
    }
    return $sb.ToString()
}

# One record per line, so a record's number is its line number; a blank line is refused.
function Read-JsonLines([string]$path) {
    $name = Split-Path -Leaf $path
    $lines = [IO.File]::ReadAllLines($path)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '') { throw "$name line $($i + 1): a blank line" }
    }
    try {
        $records = ('[' + ($lines -join ',') + ']') | ConvertFrom-Json
        return , $records
    } catch {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            try { $null = $lines[$i] | ConvertFrom-Json } catch { throw "$name line $($i + 1): $($_.Exception.Message)" }
        }
        throw
    }
}

# Field names other than the given ones, found in the file's text: inside a value, a quote is always
# escaped, so a name can only follow { or , directly.
function Find-UnknownFields([string]$path, [string[]]$fields) {
    $text = [IO.File]::ReadAllText($path)
    $known = ($fields | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($text, '(?<=[{,])"(?!(?:' + $known + ')")((?:[^"\\]|\\.)*)":')) {
        $line = ([regex]::Matches($text.Substring(0, $m.Index), "`n")).Count + 1
        $problems.Add("$(Split-Path -Leaf $path) line ${line}: unknown field '$($m.Groups[1].Value)'")
    }
    return $problems.ToArray()
}

# Every problem found, as "<what>: <problem>" lines; empty when the data is sound. Records that pass
# the quick test are sound; the rest are looked at field by field to say what's wrong.
function Test-QuestRecords($quests) {
    $problems = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.Dictionary[long, int]'
    $n = 0
    foreach ($q in $quests) {
        $n++
        $id = $q.id; $name = $q.name; $zone = $q.zone
        $sound = ($id -is [int]) -and ($name -is [string]) -and ($name -ne '') -and ($zone -is [string]) -and
            ($q.level -is [int]) -and ($q.category -is [int]) -and ($q.type -is [int]) -and ($q.faction -is [int]) -and
            ($q.race -is [int]) -and ($q.class -is [int]) -and
            ($null -eq $q.profession -or $q.profession -is [int]) -and ($null -eq $q.holiday -or $q.holiday -is [int]) -and
            ($null -eq $q.covenant -or $q.covenant -is [int]) -and ($null -eq $q.pvp -or $q.pvp -is [int]) -and ($null -eq $q.storyline -or $q.storyline -is [int]) -and
            ($null -eq $q.minLevel -or ($q.minLevel -is [int] -and $q.minLevel -ge 0 -and $q.minLevel -ne $q.level)) -and
            ($null -eq $q.maxLevel -or ($q.maxLevel -is [int] -and $q.maxLevel -gt 0)) -and
            ($null -eq $q.prereq -or ($q.prereq -is [int] -and $q.prereq -ge 0) -or (Test-PrereqValue $q.prereq)) -and -not ($name -match '[\x00-\x1f]') -and -not ($zone -match '[\x00-\x1f]')
        if (-not $sound) {
            $what = "quests.jsonl line $n" + $(if (Test-WholeNumber $id) { " (id $id)" } else { '' })
            foreach ($field in $QuestFields) {
                $value = $q.$field
                if ($null -eq $value) {
                    if ($QuestOptionalFields -notcontains $field) { $problems.Add("${what}: '$field' is missing") }
                } elseif ($field -eq 'name' -or $field -eq 'zone') {
                    if ($value -isnot [string]) { $problems.Add("${what}: '$field' must be text") }
                    elseif ($value -match '[\x00-\x1f]') { $problems.Add("${what}: '$field' contains a control character") }
                    elseif ($field -eq 'name' -and $value -eq '') { $problems.Add("${what}: 'name' is empty") }
                } elseif ($field -eq 'prereq') {
                    if (-not (($value -is [int] -and $value -ge 0) -or (Test-PrereqValue $value))) { $problems.Add("${what}: 'prereq' must be a quest ID, or a list of them with no empty list") }
                } elseif ($field -eq 'minLevel') {
                    if (-not (Test-WholeNumber $value) -or $value -lt 0) { $problems.Add("${what}: 'minLevel' must be a whole number, 0 or more") }
                    elseif ($value -eq $q.level) { $problems.Add("${what}: 'minLevel' is the same as 'level'; leave it out") }
                } elseif ($field -eq 'maxLevel') {
                    if (-not (Test-WholeNumber $value) -or $value -le 0) { $problems.Add("${what}: 'maxLevel' must be a whole number above 0") }
                } elseif (-not (Test-WholeNumber $value)) {
                    $problems.Add("${what}: '$field' must be a whole number")
                }
            }
        }
        if (Test-WholeNumber $id) {
            if ($seen.ContainsKey($id)) { $problems.Add("quests.jsonl line $n (id $id): the id is also used on line $($seen[$id])") }
            else { $seen[$id] = $n }
        }
    }
    return $problems.ToArray()
}

function Test-PinRecords($pins) {
    $problems = New-Object System.Collections.Generic.List[string]
    $n = 0
    foreach ($pin in $pins) {
        $n++
        $x = $pin.x; $y = $pin.y; $name = $pin.name; $note = $pin.note; $quests = $pin.quests
        $sound = ($pin.map -is [int]) -and ($pin.icon -is [int]) -and ($null -eq $pin.npc -or $pin.npc -is [int]) -and
            ($null -eq $name -or ($name -is [string] -and $name -ne '' -and -not ($name -match '[\x00-\x1f]'))) -and
            ($null -eq $note -or ($note -is [string] -and $note -ne '' -and -not ($note -match '[\x00-\x1f]'))) -and
            ($x -is [int] -or $x -is [decimal]) -and ($y -is [int] -or $y -is [decimal]) -and
            $x -ge 0 -and $x -le 100 -and $y -ge 0 -and $y -le 100 -and ($quests -is [array]) -and $quests.Count -gt 0
        if ($sound) {
            foreach ($questId in $quests) { if ($questId -isnot [int]) { $sound = $false; break } }
        }
        if ($sound) { continue }
        $what = "pins.jsonl line $n" + $(if (Test-WholeNumber $pin.map) { " (map $($pin.map))" } else { '' })
        foreach ($field in 'map', 'icon') {
            if (-not (Test-WholeNumber $pin.$field)) { $problems.Add("${what}: '$field' must be a whole number") }
        }
        if ($null -ne $pin.npc -and -not (Test-WholeNumber $pin.npc)) { $problems.Add("${what}: 'npc' must be a whole number") }
        foreach ($field in 'name', 'note') {
            $value = $pin.$field
            if ($null -eq $value) { continue }
            if ($value -isnot [string] -or $value -eq '') { $problems.Add("${what}: '$field' must be text, or left out") }
            elseif ($value -match '[\x00-\x1f]') { $problems.Add("${what}: '$field' contains a control character") }
        }
        foreach ($field in 'x', 'y') {
            $value = $pin.$field
            if (-not (Test-DataNumber $value)) { $problems.Add("${what}: '$field' must be a number") }
            elseif ($value -lt 0 -or $value -gt 100) { $problems.Add("${what}: '$field' is $value, outside 0 to 100") }
        }
        $list = @($quests)
        if ($null -eq $quests -or $list.Count -eq 0) { $problems.Add("${what}: 'quests' must list at least one quest") }
        elseif (@($list | Where-Object { -not (Test-WholeNumber $_) }).Count -gt 0) { $problems.Add("${what}: 'quests' must hold whole numbers") }
    }
    return $problems.ToArray()
}

# Problems with the start items: an item is listed once and has whole numbers above 0 (side 1 Alliance or 2 Horde;
# races, ChrRaces IDs). An item whose quest has left the data isn't one: it is left out of the Lua, and
# Sync-QuestStartItems.ps1 drops it.
function Test-StartItemRecords($items) {
    $problems = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $n = 0
    foreach ($s in $items) {
        $n++
        $what = "startitems.jsonl line $n" + $(if (Test-WholeNumber $s.item) { " (item $($s.item))" } else { '' })
        if (-not (Test-WholeNumber $s.item) -or $s.item -le 0) { $problems.Add("${what}: 'item' must be a whole number above 0"); continue }
        if ($seen.ContainsKey($s.item)) { $problems.Add("${what}: the item is also on line $($seen[$s.item])") } else { $seen[$s.item] = $n }
        if (-not (Test-WholeNumber $s.quest) -or $s.quest -le 0) { $problems.Add("${what}: 'quest' must be a whole number above 0") }
        foreach ($field in 'side', 'level', 'skill', 'skillRank', 'rep', 'repRank') {
            $value = $s.$field
            if ($null -ne $value -and (-not (Test-WholeNumber $value) -or $value -le 0)) { $problems.Add("${what}: '$field' must be a whole number above 0, or left out") }
        }
        if ($null -ne $s.side -and $s.side -ne 1 -and $s.side -ne 2) { $problems.Add("${what}: 'side' is 1 (Alliance) or 2 (Horde)") }
        if ($null -ne $s.races) {
            $list = @($s.races)
            if ($s.races -isnot [array] -or $list.Count -eq 0 -or @($list | Where-Object { -not (Test-WholeNumber $_) -or $_ -le 0 }).Count) { $problems.Add("${what}: 'races' must list race IDs") }
        }
    }
    return $problems.ToArray()
}

# Problems with the condition texts: a key ('p' and a PlayerCondition ID, or 'c' and a CampaignXCondition ID) is listed
# once, names quests, and has enUS's text; each text is one line, with no game variable ($pcMinLevel) left in it, which
# only the game can fill. A quest that has left the data isn't one: it is left out of the Lua.
function Test-ConditionTextRecords($texts) {
    $problems = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $n = 0
    foreach ($t in $texts) {
        $n++
        $what = "conditiontexts.jsonl line $n" + $(if ($t.key -is [string]) { " ($($t.key))" } else { '' })
        if ($t.key -isnot [string] -or $t.key -notmatch '^[pc][1-9]\d*$') { $problems.Add("${what}: 'key' is p or c and a condition's ID"); continue }
        if ($seen.ContainsKey($t.key)) { $problems.Add("${what}: the key is also on line $($seen[$t.key])") } else { $seen[$t.key] = $n }
        $list = @($t.quests)
        if ($t.quests -isnot [array] -or $list.Count -eq 0 -or @($list | Where-Object { -not (Test-WholeNumber $_) -or $_ -le 0 }).Count) { $problems.Add("${what}: 'quests' must list quest IDs") }
        if (-not $t.enUS) { $problems.Add("${what}: 'enUS' must hold the English text") }
        foreach ($locale in $ConditionTextLocales) {
            $text = $t.$locale
            if ($null -eq $text) { continue }
            if ($text -isnot [string] -or $text -eq '') { $problems.Add("${what}: '$locale' must be text, or left out"); continue }
            if ($text -match '[\x00-\x1f]') { $problems.Add("${what}: '$locale' has a control character") }
            if ($text -match '\$[A-Za-z]') { $problems.Add("${what}: '$locale' has a game variable the addon can't fill") }
        }
    }
    return $problems.ToArray()
}

# qcQuestConditionTexts: quest ID -> the numbers of its texts in qcConditionTexts; qcConditionTexts: the game's own
# words for a condition that holds a quest back, in the client's language (GetLocale), or enUS's where a language
# has none and for a language the data doesn't hold (enGB). Every language's list is in the file, numbered alike.
function ConvertTo-LuaConditionTextTables($texts) {
    $sb = New-Object System.Text.StringBuilder
    $byQuest = New-Object 'System.Collections.Generic.SortedDictionary[long, System.Collections.Generic.List[int]]'
    $n = 0
    foreach ($t in $texts) {
        $n++
        foreach ($quest in @($t.quests)) {
            if (-not $byQuest.ContainsKey([long]$quest)) { $byQuest[[long]$quest] = New-Object System.Collections.Generic.List[int] }
            $byQuest[[long]$quest].Add($n)
        }
    }
    [void]$sb.Append("qcQuestConditionTexts={`r`n")
    foreach ($entry in $byQuest.GetEnumerator()) { [void]$sb.Append('[' + $entry.Key + ']={' + ($entry.Value -join ',') + "},`r`n") }
    [void]$sb.Append("}`r`n")
    if ($n -eq 0) { [void]$sb.Append("qcConditionTexts={}`r`n"); return $sb.ToString() }
    [void]$sb.Append("do local texts={`r`n")
    foreach ($locale in $ConditionTextLocales) {
        $list = foreach ($t in $texts) { $text = if ($t.$locale) { $t.$locale } else { $t.enUS }; '"' + $text.Replace('\', '\\').Replace('"', '\"') + '"' }
        [void]$sb.Append($locale + '={' + ($list -join ',') + "},`r`n")
    }
    [void]$sb.Append("} qcConditionTexts=texts[GetLocale()] or texts.enUS end`r`n")
    return $sb.ToString()
}

# qcQuestStartItems: quest ID -> the items that start it, each {item, side, level, skill, skillRank, faction,
# standing, {races}}: side 1 Alliance or 2 Horde (the item's own faction flag, 0 for either), level the level to
# use it, skill and skillRank the profession and skill it needs, faction and standing the reputation it needs
# (standing 0 Hated to 7 Exalted), races the ChrRaces IDs that may use it when not all may. A trailing 0 is left off.
function ConvertTo-LuaStartItemTable($items) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("qcQuestStartItems={`r`n")
    foreach ($group in ($items | Group-Object { [long]$_.quest } | Sort-Object { [long]$_.Name })) {
        $entries = foreach ($s in ($group.Group | Sort-Object { [long]$_.item })) {
            $values = @($s.item, [int]$s.side, [int]$s.level, [int]$s.skill, [int]$s.skillRank, [int]$s.rep, [int]$s.repRank)
            $races = if ($s.races) { '{' + (@($s.races) -join ',') + '}' } else { $null }
            if ($races) { $values += $races } else { $last = $values.Count - 1; while ($last -gt 0 -and $values[$last] -eq 0) { $last-- }; $values = $values[0..$last] }
            '{' + ($values -join ',') + '}'
        }
        [void]$sb.Append('[' + $group.Name + ']={' + ($entries -join ',') + "},`r`n")
    }
    [void]$sb.Append("}`r`n")
    return $sb.ToString()
}

# The whole of qcQuestData.lua, each line ending in CRLF. A quest's row in qcQuestDatabase is
# {name, level, category, type, faction, race, class, storyline}, with storyline left off when it's
# 0; profession, holiday, covenant, pvp and prereq, which most quests don't have, go in tables of their
# own keyed by quest ID, a prereq list as a Lua table. qcQuestMinLevel holds the level a character
# needs to take a quest whose own level (the row's) is not that; a quest it lacks needs the row's
# level. qcQuestMaxLevel holds the level a scaling quest stops scaling at; the list shows such a quest
# at the character's level, kept between its minimum and that. The zone text isn't written: the game
# never reads it.
# This and ConvertTo-LuaPinFile quote and format inline, as the JSON writers do; a function call per
# field made the build take half a minute. Whole numbers turn into text the same way in any
# culture, so they're joined as they are.
function ConvertTo-LuaQuestFile($quests, [string]$source = 'data', $startItems = @(), $conditionTexts = @()) {
    $sb = New-Object System.Text.StringBuilder (4MB)
    [void]$sb.Append("-- Generated from $source\quests.jsonl by tools\Build-AddonData.ps1. Edit the data file, not this one.`r`nqcQuestDatabase={`r`n")
    # ZeroIsValue: a minimum level of 0 is a real value (no minimum); in the other tables 0 means none.
    $sparse = [ordered]@{
        qcQuestProfession = @{ Field = 'profession' }
        qcQuestHoliday = @{ Field = 'holiday' }
        qcQuestCovenant = @{ Field = 'covenant' }
        qcQuestPvP = @{ Field = 'pvp' }
        qcQuestPrereq = @{ Field = 'prereq' }
        qcQuestMinLevel = @{ Field = 'minLevel'; ZeroIsValue = $true }
        qcQuestMaxLevel = @{ Field = 'maxLevel' }
    }
    $tables = @{}
    foreach ($table in $sparse.Keys) { $tables[$table] = New-Object System.Text.StringBuilder }
    foreach ($q in $quests) {
        $name = '"' + $q.name.Replace('\', '\\').Replace('"', '\"') + '"'
        $row = @($name, $q.level, $q.category, $q.type, $q.faction, $q.race, $q.class) -join ','
        if ($q.storyline) { $row += ',' + $q.storyline }
        [void]$sb.Append('[' + $q.id + ']={' + $row + "},`r`n")
        foreach ($table in $sparse.Keys) {
            $column = $sparse[$table]
            $value = $q.($column.Field)
            if ($value -is [array]) { $value = ConvertTo-PrereqText $value '{' '}' }
            if ($value -or ($column.ZeroIsValue -and $null -ne $value)) { [void]$tables[$table].Append('[' + $q.id + ']=' + $value + ",`r`n") }
        }
    }
    [void]$sb.Append("}`r`n")
    foreach ($table in $sparse.Keys) { [void]$sb.Append($table + "={`r`n").Append($tables[$table].ToString()).Append("}`r`n") }
    [void]$sb.Append((ConvertTo-LuaStartItemTable @($startItems)))
    [void]$sb.Append((ConvertTo-LuaConditionTextTables @($conditionTexts)))
    return $sb.ToString()
}

# The whole of qcPinDB.lua. Pins keep their order within a map; maps go in ascending order.
function ConvertTo-LuaPinFile($pins, [string]$source = 'data') {
    $byMap = New-Object 'System.Collections.Generic.SortedDictionary[long, System.Collections.Generic.List[object]]'
    foreach ($pin in $pins) {
        $map = [long]$pin.map
        if (-not $byMap.ContainsKey($map)) { $byMap[$map] = New-Object System.Collections.Generic.List[object] }
        $byMap[$map].Add($pin)
    }
    $sb = New-Object System.Text.StringBuilder (2MB)
    [void]$sb.Append("-- Generated from $source\pins.jsonl by tools\Build-AddonData.ps1. Edit the data file, not this one.`r`n")
    [void]$sb.Append("qcPinDB = {`r`n")
    foreach ($entry in $byMap.GetEnumerator()) {
        [void]$sb.Append("`t[" + $entry.Key + "] = {`r`n")
        foreach ($pin in $entry.Value) {
            $npc = $pin.npc; if ($null -eq $npc) { $npc = 0 }
            $name = if ($null -ne $pin.name) { '"' + $pin.name.Replace('\', '\\').Replace('"', '\"') + '"' } else { 'nil' }
            $x = $pin.x; if ($x -is [decimal]) { $x = $x.ToString('0.############################', $script:Invariant) }
            $y = $pin.y; if ($y -is [decimal]) { $y = $y.ToString('0.############################', $script:Invariant) }
            $note = if ($null -ne $pin.note) { ',"' + $pin.note.Replace('\', '\\').Replace('"', '\"') + '"' } else { '' }
            [void]$sb.Append("`t`t{" + (@($pin.icon, $npc, $name, $x, $y) -join ',') + ',{' + ($pin.quests -join ',') + '}' + $note + "},`r`n")
        }
        [void]$sb.Append("`t},`r`n")
    }
    [void]$sb.Append("}`r`n")
    return $sb.ToString()
}

# Checks both data files and builds the Lua from them; with -Check, only compares. Returns Ok and the
# Lines to show. Ok is false if a file can't be read, a record has a problem, or -Check finds the
# Lua out of date.
function Invoke-AddonDataBuild([string]$DataDir = $DefaultDataDir, [string]$AddonDir = $DefaultAddonDir, [switch]$Check) {
    $lines = New-Object System.Collections.Generic.List[string]
    $DataDir = (Resolve-Path $DataDir).Path
    $AddonDir = (Resolve-Path $AddonDir).Path
    $questData = Join-Path $DataDir 'quests.jsonl'
    $pinData = Join-Path $DataDir 'pins.jsonl'
    $startItemData = Join-Path $DataDir 'startitems.jsonl'
    $conditionTextData = Join-Path $DataDir 'conditiontexts.jsonl'
    try {
        $quests = Read-JsonLines $questData
        $pins = Read-JsonLines $pinData
        $startItems = if (Test-Path $startItemData) { Read-JsonLines $startItemData } else { @() }
        $conditionTexts = if (Test-Path $conditionTextData) { Read-JsonLines $conditionTextData } else { @() }
    } catch {
        $lines.Add("  $($_.Exception.Message)")
        $lines.Add("The data files can't be read; nothing was written.")
        return [pscustomobject]@{ Ok = $false; Lines = $lines.ToArray() }
    }
    $problems = @(Find-UnknownFields $questData $QuestFields) + @(Test-QuestRecords $quests) +
        @(Find-UnknownFields $pinData $PinFields) + @(Test-PinRecords $pins)
    if (Test-Path $startItemData) { $problems += @(Find-UnknownFields $startItemData $StartItemFields) + @(Test-StartItemRecords $startItems) }
    if (Test-Path $conditionTextData) { $problems += @(Find-UnknownFields $conditionTextData $ConditionTextFields) + @(Test-ConditionTextRecords $conditionTexts) }
    if ($problems.Count -gt 0) {
        $problems | Select-Object -First 30 | ForEach-Object { $lines.Add("  $_") }
        if ($problems.Count -gt 30) { $lines.Add("  ... and $($problems.Count - 30) more") }
        $lines.Add("$($problems.Count) problem$(if ($problems.Count -ne 1) { 's' }) in the data files; nothing was written.")
        return [pscustomobject]@{ Ok = $false; Lines = $lines.ToArray() }
    }

    $questPath = Join-Path $AddonDir 'qcQuestData.lua'
    $pinPath = Join-Path $AddonDir 'qcPinDB.lua'
    $questIds = New-Object 'System.Collections.Generic.HashSet[long]'
    foreach ($q in $quests) { [void]$questIds.Add([long]$q.id) }
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $source = if ($DataDir.StartsWith($repoRoot + '\')) { $DataDir.Substring($repoRoot.Length + 1) } else { 'data' }
    $current = { param($path) if (Test-Path $path) { [IO.File]::ReadAllText($path) } else { '' } }
    # A condition text keeps the quests still in the data, and goes when none is.
    $textsKept = @(foreach ($t in $conditionTexts) {
        $kept = @(@($t.quests) | Where-Object { $questIds.Contains([long]$_) })
        if ($kept.Count) {
            $copy = [ordered]@{ key = $t.key; quests = $kept }
            foreach ($locale in $ConditionTextLocales) { if ($t.$locale) { $copy[$locale] = $t.$locale } }
            [pscustomobject]$copy
        }
    })
    $outputs = @(
        @{ Path = $questPath; Old = (& $current $questPath); New = (ConvertTo-LuaQuestFile $quests $source @($startItems | Where-Object { $questIds.Contains([long]$_.quest) }) $textsKept) },
        @{ Path = $pinPath; Old = (& $current $pinPath); New = (ConvertTo-LuaPinFile $pins $source) }
    )
    $differ = 0
    foreach ($output in $outputs) {
        $name = Split-Path -Leaf $output.Path
        if ($output.Old -ceq $output.New) { $lines.Add("${name}: up to date"); continue }
        $differ++
        if ($Check) {
            $old = $output.Old.Split("`n"); $new = $output.New.Split("`n")
            $i = 0
            while ($i -lt $old.Count -and $i -lt $new.Count -and $old[$i] -ceq $new[$i]) { $i++ }
            $at = { param($all) if ($i -lt $all.Count) { $all[$i].TrimEnd("`r") } else { '(end of file)' } }
            $lines.Add("${name}: doesn't match the data files, first at line $($i + 1)")
            $lines.Add("  file: $(& $at $old)")
            $lines.Add("  data: $(& $at $new)")
        } else {
            [IO.File]::WriteAllText($output.Path, $output.New, $script:Utf8)
            $lines.Add("${name}: written")
        }
    }
    $lines.Add("$($quests.Count) quests, $($pins.Count) pins, $(@($startItems).Count) start items, $(@($conditionTexts).Count) condition texts")
    return [pscustomobject]@{ Ok = -not ($Check -and $differ -gt 0); Lines = $lines.ToArray() }
}

# For tools: the records of a data file, in order. A field a record leaves out reads as $null; set
# fields with Set-RecordField, which adds the ones a record doesn't have yet.
function Read-QuestData([string]$DataDir = $DefaultDataDir) {
    $records = Read-JsonLines (Join-Path (Resolve-Path $DataDir).Path 'quests.jsonl')
    return $records
}

function Read-PinData([string]$DataDir = $DefaultDataDir) {
    $records = Read-JsonLines (Join-Path (Resolve-Path $DataDir).Path 'pins.jsonl')
    return $records
}

function Set-RecordField($record, [string]$field, $value) {
    if ($QuestFields -notcontains $field -and $PinFields -notcontains $field) { throw "No data file has a field '$field'" }
    if ($record -is [System.Collections.IDictionary]) { $record[$field] = $value; return }
    $property = $record.PSObject.Properties[$field]
    if ($property) { $property.Value = $value } else { $record | Add-Member -NotePropertyName $field -NotePropertyValue $value }
}

# For tools: checks the records, writes them to the data file and rebuilds the Lua from both data
# files. Throws, writing nothing, if a record has a problem, or if the Lua no longer matches the data
# files: rebuilding it would then lose whatever changed it.
function Save-QuestData($quests, [string]$DataDir = $DefaultDataDir, [string]$AddonDir = $DefaultAddonDir) {
    $problems = @(Test-QuestRecords $quests)
    if ($problems.Count -gt 0) { throw ("The quests weren't saved:`n  " + (($problems | Select-Object -First 20) -join "`n  ")) }
    Assert-LuaMatchesData $DataDir $AddonDir
    [IO.File]::WriteAllText((Join-Path (Resolve-Path $DataDir).Path 'quests.jsonl'), (ConvertTo-QuestJsonLines $quests), $script:Utf8)
    Complete-AddonDataSave $DataDir $AddonDir
}

function Save-StartItemData($items, [string]$DataDir = $DefaultDataDir, [string]$AddonDir = $DefaultAddonDir) {
    $problems = @(Test-StartItemRecords $items)
    if ($problems.Count -gt 0) { throw ("The start items weren't saved:`n  " + (($problems | Select-Object -First 20) -join "`n  ")) }
    Assert-LuaMatchesData $DataDir $AddonDir
    [IO.File]::WriteAllText((Join-Path (Resolve-Path $DataDir).Path 'startitems.jsonl'), (ConvertTo-StartItemJsonLines $items), $script:Utf8)
    Complete-AddonDataSave $DataDir $AddonDir
}

function Save-ConditionTextData($texts, [string]$DataDir = $DefaultDataDir, [string]$AddonDir = $DefaultAddonDir) {
    $problems = @(Test-ConditionTextRecords $texts)
    if ($problems.Count -gt 0) { throw ("The condition texts weren't saved:`n  " + (($problems | Select-Object -First 20) -join "`n  ")) }
    Assert-LuaMatchesData $DataDir $AddonDir
    [IO.File]::WriteAllText((Join-Path (Resolve-Path $DataDir).Path 'conditiontexts.jsonl'), (ConvertTo-ConditionTextJsonLines $texts), $script:Utf8)
    Complete-AddonDataSave $DataDir $AddonDir
}

function Save-PinData($pins, [string]$DataDir = $DefaultDataDir, [string]$AddonDir = $DefaultAddonDir) {
    $problems = @(Test-PinRecords $pins)
    if ($problems.Count -gt 0) { throw ("The pins weren't saved:`n  " + (($problems | Select-Object -First 20) -join "`n  ")) }
    Assert-LuaMatchesData $DataDir $AddonDir
    [IO.File]::WriteAllText((Join-Path (Resolve-Path $DataDir).Path 'pins.jsonl'), (ConvertTo-PinJsonLines $pins), $script:Utf8)
    Complete-AddonDataSave $DataDir $AddonDir
}

function Assert-LuaMatchesData([string]$DataDir, [string]$AddonDir) {
    $check = Invoke-AddonDataBuild -DataDir $DataDir -AddonDir $AddonDir -Check
    if ($check.Ok) { return }
    throw ("Nothing was saved: the Lua files don't match the data files.`n  " + ($check.Lines -join "`n  ") +
        "`nThe quest rows and the pins are generated. Make that change in the data files instead, run" +
        " Build-AddonData.ps1 (which overwrites the Lua with what the data files hold), then this again.")
}

function Complete-AddonDataSave([string]$DataDir, [string]$AddonDir) {
    $build = Invoke-AddonDataBuild -DataDir $DataDir -AddonDir $AddonDir
    $build.Lines | ForEach-Object { Write-Host $_ }
    if (-not $build.Ok) { throw 'The data file was written, but the Lua could not be built from it.' }
}
