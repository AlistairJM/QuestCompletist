<#
Shared reading and writing of the quest and pin data, dot-sourced by Build-AddonData.ps1 and every
tool that reads or changes quests or pins:
	. "$PSScriptRoot\AddonData.ps1"

data\quests.jsonl and data\pins.jsonl are the master copy of the quests and pins. They hold one
record per line, with named fields:
	{"id":176,"name":"WANTED:  \"Hogger\"","level":1,"zone":"Elwynn Forest","category":70,"type":1,"faction":1,"race":64175181,"class":8191,"storyline":566}
	{"map":84,"icon":1,"npc":29611,"name":"King Varian Wrynn","x":26.12,"y":47.32,"quests":[26365]}
Fields that are empty are left out: a quest's profession, holiday, covenant, storyline and prereq
when 0, and a pin's npc when 0, its name when it has none and its note when it has none. The
records become the qcQuestDatabase rows of qcQuest.lua, in file order, and the whole of qcPinDB.lua,
map by map in ascending order. Both start with a line saying they're generated.
#>

$script:Invariant = [Globalization.CultureInfo]::InvariantCulture
$script:Utf8 = New-Object System.Text.UTF8Encoding $false
$DefaultDataDir = Join-Path $PSScriptRoot '..\data'
$DefaultAddonDir = Join-Path $PSScriptRoot '..\QuestCompletist'

$QuestFields = @('id', 'name', 'level', 'zone', 'category', 'type', 'faction', 'race', 'class',
    'profession', 'holiday', 'covenant', 'storyline', 'prereq')
$QuestOptionalFields = @('profession', 'holiday', 'covenant', 'storyline', 'prereq')
$PinFields = @('map', 'icon', 'npc', 'name', 'x', 'y', 'quests', 'note')

function Test-WholeNumber($value) { return ($value -is [int]) -or ($value -is [long]) }
function Test-DataNumber($value) { return (Test-WholeNumber $value) -or ($value -is [decimal]) }

function Find-QuestBlock([string]$luaText) {
    $open = [regex]::Match($luaText, '(?m)^qcQuestDatabase=\{\r?\n')
    if (-not $open.Success) { throw "qcQuestDatabase={ not found" }
    $start = $open.Index + $open.Length
    $close = [regex]::Match($luaText.Substring($start), '(?m)^\}')
    if (-not $close.Success) { throw "The end of qcQuestDatabase not found" }
    return @{ Start = $start; End = $start + $close.Index }
}

# The text of quests.jsonl and pins.jsonl. Strings go in double quotes with \ and " escaped (the
# same in Lua and JSON; control characters are refused by the checks), and numbers are written the
# shortest way: 47.3 rather than 47.30. Like the Lua writers further down, these do it inline: a
# function call per field made writing them take a minute. A profession, holiday, covenant,
# storyline or prereq of 0 is left out, as is a pin's npc of 0.
function ConvertTo-QuestJsonLines($quests) {
    $sb = New-Object System.Text.StringBuilder (6MB)
    foreach ($q in $quests) {
        [void]$sb.Append('{"id":' + $q.id + ',"name":"' + $q.name.Replace('\', '\\').Replace('"', '\"') + '","level":' + $q.level +
            ',"zone":"' + $q.zone.Replace('\', '\\').Replace('"', '\"') + '","category":' + $q.category + ',"type":' + $q.type +
            ',"faction":' + $q.faction + ',"race":' + $q.race + ',"class":' + $q.class)
        if ($q.profession) { [void]$sb.Append(',"profession":' + $q.profession) }
        if ($q.holiday) { [void]$sb.Append(',"holiday":' + $q.holiday) }
        if ($q.covenant) { [void]$sb.Append(',"covenant":' + $q.covenant) }
        if ($q.storyline) { [void]$sb.Append(',"storyline":' + $q.storyline) }
        if ($q.prereq) { [void]$sb.Append(',"prereq":' + $q.prereq) }
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
# inline, as the JSON writers do; a function call per field made the build take half a minute.
# Whole numbers turn into text the same way in any culture, so they're joined as they are.
function ConvertTo-LuaQuestRows($quests) {
    $sb = New-Object System.Text.StringBuilder (6MB)
    [void]$sb.Append("-- Generated from data\quests.jsonl by tools\Build-AddonData.ps1. Edit the data file, not these rows.`r`n")
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
    [void]$sb.Append("-- Generated from data\pins.jsonl by tools\Build-AddonData.ps1. Edit the data file, not this one.`r`n")
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

# Checks both data files and builds the Lua from them; with -Check, only compares. Returns Ok and the
# Lines to show. Ok is false if a file can't be read, a record has a problem, or -Check finds the
# Lua out of date.
function Invoke-AddonDataBuild([string]$DataDir = $DefaultDataDir, [string]$AddonDir = $DefaultAddonDir, [switch]$Check) {
    $lines = New-Object System.Collections.Generic.List[string]
    $DataDir = (Resolve-Path $DataDir).Path
    $AddonDir = (Resolve-Path $AddonDir).Path
    $questData = Join-Path $DataDir 'quests.jsonl'
    $pinData = Join-Path $DataDir 'pins.jsonl'
    try {
        $quests = Read-JsonLines $questData
        $pins = Read-JsonLines $pinData
    } catch {
        $lines.Add("  $($_.Exception.Message)")
        $lines.Add("The data files can't be read; nothing was written.")
        return [pscustomobject]@{ Ok = $false; Lines = $lines.ToArray() }
    }
    $problems = @(Find-UnknownFields $questData $QuestFields) + @(Test-QuestRecords $quests) +
        @(Find-UnknownFields $pinData $PinFields) + @(Test-PinRecords $pins)
    if ($problems.Count -gt 0) {
        $problems | Select-Object -First 30 | ForEach-Object { $lines.Add("  $_") }
        if ($problems.Count -gt 30) { $lines.Add("  ... and $($problems.Count - 30) more") }
        $lines.Add("$($problems.Count) problem$(if ($problems.Count -ne 1) { 's' }) in the data files; nothing was written.")
        return [pscustomobject]@{ Ok = $false; Lines = $lines.ToArray() }
    }

    $questPath = Join-Path $AddonDir 'qcQuest.lua'
    $pinPath = Join-Path $AddonDir 'qcPinDB.lua'
    $questLua = [IO.File]::ReadAllText($questPath)
    $outputs = @(
        @{ Path = $questPath; Old = $questLua; New = (Set-LuaQuestRows $questLua (ConvertTo-LuaQuestRows $quests)) },
        @{ Path = $pinPath; Old = [IO.File]::ReadAllText($pinPath); New = (ConvertTo-LuaPinFile $pins) }
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
    $lines.Add("$($quests.Count) quests, $($pins.Count) pins")
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
