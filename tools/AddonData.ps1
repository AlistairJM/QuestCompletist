<#
Shared reading and writing of the quest and pin data, dot-sourced by Build-AddonData.ps1 and
Export-AddonData.ps1:
	. "$PSScriptRoot\AddonData.ps1"

data\quests.jsonl and data\pins.jsonl hold one record per line, with named fields:
	{"id":176,"name":"WANTED:  \"Hogger\"","level":1,"zone":"Elwynn Forest","category":70,"type":1,"faction":1,"race":64175181,"class":8191,"storyline":566}
	{"map":84,"icon":1,"npc":29611,"name":"King Varian Wrynn","x":26.12,"y":47.32,"quests":[26365]}
Fields that are empty are left out: a quest's profession, holiday, covenant, storyline and prereq
when 0, and a pin's npc when 0, its name when it has none and its note when it has none. The
records become the qcQuestDatabase rows of qcQuest.lua, in file order, and the whole of qcPinDB.lua,
map by map in ascending order.
#>

$script:Invariant = [Globalization.CultureInfo]::InvariantCulture

$QuestFields = @('id', 'name', 'level', 'zone', 'category', 'type', 'faction', 'race', 'class',
    'profession', 'holiday', 'covenant', 'storyline', 'prereq')
$QuestOptionalFields = @('profession', 'holiday', 'covenant', 'storyline', 'prereq')
$PinFields = @('map', 'icon', 'npc', 'name', 'x', 'y', 'quests', 'note')

function Test-WholeNumber($value) { return ($value -is [int]) -or ($value -is [long]) }
function Test-DataNumber($value) { return (Test-WholeNumber $value) -or ($value -is [decimal]) }

# Numbers are written the shortest way: 47.3 rather than 47.30, 64 rather than 64.0.
function Format-DataNumber($value) {
    if ($value -is [decimal]) { return $value.ToString('0.############################', $script:Invariant) }
    if (Test-WholeNumber $value) { return $value.ToString($script:Invariant) }
    throw "Not a number: $value"
}

# Lua and JSON both take a string in double quotes with \ and " escaped; control characters are
# refused by the checks below.
function ConvertTo-QuotedString([string]$s) {
    return '"' + $s.Replace('\', '\\').Replace('"', '\"') + '"'
}

function ConvertFrom-LuaString([string]$token) {
    $body = $token.Substring(1, $token.Length - 2)
    return [regex]::Replace($body, '\\(\d{1,3}|.)', {
        param($m)
        $e = $m.Groups[1].Value
        switch -CaseSensitive ($e) {
            '\' { return '\' }
            '"' { return '"' }
            "'" { return "'" }
            'n' { return "`n" }
            't' { return "`t" }
            default {
                if ($e -match '^\d+$' -and [int]$e -lt 128) { return [string][char][int]$e }
                throw "Unsupported escape \$e in $token"
            }
        }
    })
}

# One Lua value: a string, nil, a {..} list of whole numbers, or a number.
function ConvertFrom-LuaValue([string]$token) {
    if ($token.StartsWith('"')) { return ConvertFrom-LuaString $token }
    if ($token -eq 'nil') { return $null }
    if ($token.StartsWith('{')) {
        $ids = New-Object System.Collections.Generic.List[long]
        foreach ($part in $token.Substring(1, $token.Length - 2).Split(',')) {
            if ($part -ne '') { $ids.Add([long]::Parse($part, $script:Invariant)) }
        }
        return , $ids.ToArray()
    }
    if ($token -match '^-?\d+$') { return [long]::Parse($token, $script:Invariant) }
    if ($token -match '^-?\d+\.\d+$') { return [decimal]::Parse($token, $script:Invariant) }
    throw "Not a value: $token"
}

function Split-LuaValues([string]$inner) {
    return , @([regex]::Matches($inner, '"(?:[^"\\]|\\.)*"|\{[^}]*\}|[^,]+') | ForEach-Object { $_.Value })
}

function Find-QuestBlock([string]$luaText) {
    $open = [regex]::Match($luaText, '(?m)^qcQuestDatabase=\{\r?\n')
    if (-not $open.Success) { throw "qcQuestDatabase={ not found" }
    $start = $open.Index + $open.Length
    $close = [regex]::Match($luaText.Substring($start), '(?m)^\}')
    if (-not $close.Success) { throw "The end of qcQuestDatabase not found" }
    return @{ Start = $start; End = $start + $close.Index }
}

function ConvertFrom-LuaQuestBlock([string]$luaText) {
    $block = Find-QuestBlock $luaText
    $quests = New-Object System.Collections.Generic.List[object]
    $lineNo = 0
    foreach ($line in $luaText.Substring($block.Start, $block.End - $block.Start).Split("`n")) {
        $lineNo++
        $line = $line.TrimEnd("`r")
        if ($line -eq '' -or $line.StartsWith('--')) { continue }
        $m = [regex]::Match($line, '^\[(\d+)\]=\{(.*)\},$')
        if (-not $m.Success) { throw "qcQuestDatabase line $lineNo isn't a quest row: $line" }
        $values = Split-LuaValues $m.Groups[2].Value
        if ($values.Count -ne $QuestFields.Count) { throw "Quest $($m.Groups[1].Value) has $($values.Count) fields, not $($QuestFields.Count)" }
        $quest = [ordered]@{}
        for ($f = 0; $f -lt $QuestFields.Count; $f++) {
            $value = ConvertFrom-LuaValue $values[$f]
            if ($QuestOptionalFields -contains $QuestFields[$f] -and $value -eq 0) { continue }
            $quest[$QuestFields[$f]] = $value
        }
        if ([string]$quest.id -ne $m.Groups[1].Value) { throw "Quest [$($m.Groups[1].Value)] holds id $($quest.id)" }
        $quests.Add($quest)
    }
    return , $quests
}

function ConvertFrom-LuaPinFile([string]$luaText) {
    $pins = New-Object System.Collections.Generic.List[object]
    $map = $null
    $lineNo = 0
    foreach ($line in $luaText.Split("`n")) {
        $lineNo++
        $line = $line.TrimEnd("`r")
        if ($line -eq 'qcPinDB = {' -or $line -eq "`t}," -or $line -eq '}' -or $line -eq '') { continue }
        $m = [regex]::Match($line, '^\t\[(\d+)\] = \{$')
        if ($m.Success) { $map = [long]$m.Groups[1].Value; continue }
        $m = [regex]::Match($line, '^\t\t\{(.*)\},$')
        if (-not $m.Success -or $null -eq $map) { throw "qcPinDB.lua line $lineNo isn't a pin: $line" }
        $values = Split-LuaValues $m.Groups[1].Value
        if ($values.Count -lt 6 -or $values.Count -gt 7) { throw "qcPinDB.lua line $lineNo has $($values.Count) fields" }
        $pin = [ordered]@{ map = $map; icon = (ConvertFrom-LuaValue $values[0]) }
        $npc = ConvertFrom-LuaValue $values[1]
        if ($npc -ne 0) { $pin.npc = $npc }
        $name = ConvertFrom-LuaValue $values[2]
        if ($null -ne $name) { $pin.name = $name }
        $pin.x = ConvertFrom-LuaValue $values[3]
        $pin.y = ConvertFrom-LuaValue $values[4]
        $pin.quests = ConvertFrom-LuaValue $values[5]
        if ($values.Count -eq 7) { $pin.note = ConvertFrom-LuaValue $values[6] }
        $pins.Add($pin)
    }
    return , $pins
}

function ConvertTo-JsonLine($record, [string[]]$fields) {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($field in $fields) {
        $value = $record.$field
        if ($null -eq $value) { continue }
        if ($value -is [string]) { $text = ConvertTo-QuotedString $value }
        elseif ($value -is [array]) { $text = '[' + (($value | ForEach-Object { Format-DataNumber $_ }) -join ',') + ']' }
        else { $text = Format-DataNumber $value }
        $parts.Add('"' + $field + '":' + $text)
    }
    return '{' + ($parts -join ',') + '}'
}

function Write-JsonLines([string]$path, $records, [string[]]$fields) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($record in $records) { [void]$sb.Append((ConvertTo-JsonLine $record $fields)).Append("`n") }
    [IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
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
            ($null -eq $q.covenant -or $q.covenant -is [int]) -and ($null -eq $q.storyline -or $q.storyline -is [int]) -and
            ($null -eq $q.prereq -or $q.prereq -is [int]) -and -not ($name -match '[\x00-\x1f]') -and -not ($zone -match '[\x00-\x1f]')
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

# The qcQuestDatabase rows, each ending in CRLF. This and ConvertTo-LuaPinFile quote and format
# inline rather than through the helpers above: a function call per field made the build take half
# a minute. Whole numbers turn into text the same way in any culture, so they're joined as they are.
function ConvertTo-LuaQuestRows($quests) {
    $sb = New-Object System.Text.StringBuilder (6MB)
    foreach ($q in $quests) {
        $profession = $q.profession; if ($null -eq $profession) { $profession = 0 }
        $holiday = $q.holiday; if ($null -eq $holiday) { $holiday = 0 }
        $covenant = $q.covenant; if ($null -eq $covenant) { $covenant = 0 }
        $storyline = $q.storyline; if ($null -eq $storyline) { $storyline = 0 }
        $prereq = $q.prereq; if ($null -eq $prereq) { $prereq = 0 }
        $name = '"' + $q.name.Replace('\', '\\').Replace('"', '\"') + '"'
        $zone = '"' + $q.zone.Replace('\', '\\').Replace('"', '\"') + '"'
        [void]$sb.Append('[' + $q.id + ']={' + (@($q.id, $name, $q.level, $zone, $q.category, $q.type, $q.faction,
            $q.race, $q.class, $profession, $holiday, $covenant, $storyline, $prereq) -join ',') + "},`r`n")
    }
    return $sb.ToString()
}

# The whole of qcPinDB.lua. Pins keep their order within a map; maps go in ascending order.
function ConvertTo-LuaPinFile($pins) {
    $byMap = New-Object 'System.Collections.Generic.SortedDictionary[long, System.Collections.Generic.List[object]]'
    foreach ($pin in $pins) {
        $map = [long]$pin.map
        if (-not $byMap.ContainsKey($map)) { $byMap[$map] = New-Object System.Collections.Generic.List[object] }
        $byMap[$map].Add($pin)
    }
    $sb = New-Object System.Text.StringBuilder (2MB)
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

# qcQuest.lua with its qcQuestDatabase rows replaced; everything around them is kept as it is.
function Set-LuaQuestRows([string]$luaText, [string]$rows) {
    $block = Find-QuestBlock $luaText
    return $luaText.Substring(0, $block.Start) + $rows + $luaText.Substring($block.End)
}
