<#
Shared definition of "our" reputation reward for a qcQuestDatabase entry, dot-sourced by
Compare-QuestReputation.ps1 and Audit-QuestAccuracy.ps1.

Only entries with 17 fields carry reputation; 14-field entries stop at the prereq field.
Field 16 is the primary faction ID; field 17 is either a number (paired with field 16) or a
{[factionID]=value} table.
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

# Takes the fields from Split-Top; returns @{ factionID = value } for non-zero rewards.
function Get-OurReputation($f) {
    $set = @{}
    if ($f.Count -ge 17) {
        $fid = $f[15]; $rep = $f[16]
        if ($rep -match '^\{') { foreach ($p in [regex]::Matches($rep, '\[(\d+)\]=(-?\d+)')) { if ($p.Groups[2].Value -ne "0") { $set[$p.Groups[1].Value] = [int]$p.Groups[2].Value } } }
        elseif ($rep -match '^-?\d+$' -and $rep -ne "0" -and $fid -match '^\d+$' -and $fid -ne "0") { $set[$fid] = [int]$rep }
    }
    return $set
}
