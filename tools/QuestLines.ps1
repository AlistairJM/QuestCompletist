# Dot-sourced by Import-ForeverData.ps1: which quest of a quest line comes after which, from the client's
# QuestLineXQuest order, and whether the places agree (the hand-in map of one step is the start map of the next).

function Group-QuestLines($rows) {
    $lines = @{}
    foreach ($row in $rows) {
        $line = [int]$row.QuestLineID
        $lines[$line] += @([pscustomobject]@{ Quest = [int]$row.QuestID; Order = [int]$row.OrderIndex })
    }
    return $lines
}

function Get-QuestLineSteps($lines, $startMaps, $endMaps, $have) {
    $steps = New-Object System.Collections.Generic.List[object]
    foreach ($line in ($lines.Keys | Sort-Object)) {
        $ordered = @($lines[$line] | Where-Object { $have[$_.Quest] } | Sort-Object Order, Quest)
        for ($i = 1; $i -lt $ordered.Count; $i++) {
            $previous = $ordered[$i - 1]; $current = $ordered[$i]
            $state = 'chain'; $detail = ''
            if ($previous.Order -eq $current.Order) { $state = 'same order'; $detail = "both are step $($current.Order + 1)" }
            else {
                $ends = @($endMaps[$previous.Quest] | Where-Object { $null -ne $_ }); $starts = @($startMaps[$current.Quest] | Where-Object { $null -ne $_ })
                if (-not $ends.Count -or -not $starts.Count) { $state = 'no map point'; $detail = 'the client gives one of them no place' }
                elseif (-not @($ends | Where-Object { $starts -contains $_ }).Count) { $state = 'places differ'; $detail = "handed in on map $($ends -join '/'), the next starts on map $($starts -join '/')" }
            }
            $steps.Add([pscustomobject]@{ Line = $line; Quest = $current.Quest; Previous = $previous.Quest; Step = $current.Order + 1; State = $state; Detail = $detail })
        }
    }
    return $steps.ToArray()
}
