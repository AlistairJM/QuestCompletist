<#
Measures every column of every client table of one game build (docs/plans/client-tables-audit.md). Reads the CSV
exports in -CacheDir\<build>\ (one file per table, as wago.tools' /db2/<table>/csv?build=<build> gives them), the
schema definitions of wowdev/WoWDBDefs in -DbdDir (types, foreign keys, comments) and the tools in this folder
(which column each one mentions), and writes four files into -OutDir for the game:

  <game>-tables.csv    one row per table: rows, columns, foreign keys out, tools that mention it
  <game>-columns.csv   one row per column: DBD type, foreign key, comment, rows, non-empty, non-zero, distinct,
                       min, max, the commonest values, and the tools that mention both the table and the column
  <game>-bits.csv      one row per set bit of every integer column that looks like a flag or mask: how many rows
                       have it, and the first rows that do
  <game>-fks.csv       one row per foreign key: how many distinct values it holds, and how many of those are the ID
                       of a row in the target table (a foreign key the schema declares and the data disproves is
                       not a relationship)
  <game>-refs.csv      every integer column whose values are 80% or more IDs of one of the key tables in -RefTargets
                       (quests, maps, factions, conditions ...), declared in the schema or not: the relationships
                       the schema leaves out

-Download fetches the tables first (one request every 600 ms, resumable). Report-only: it changes nothing else.
#>
param(
    [Parameter(Mandatory)][string]$Game,
    [Parameter(Mandatory)][string]$Build,
    [string]$CacheDir = (Join-Path $env:TEMP 'client_tables_audit'),
    [string]$DbdDir = (Join-Path $env:TEMP 'WoWDBDefs\definitions'),
    [string]$OutDir = (Join-Path $PSScriptRoot '..\docs\plans\client-tables-audit'),
    [string]$ToolsDir = $PSScriptRoot,
    [string[]]$RefTargets = @('QuestV2', 'QuestLine', 'Campaign', 'QuestSort', 'QuestInfo', 'PlayerCondition', 'ModifierTree', 'ContentTuning', 'UiMap', 'AreaTable', 'Map', 'Faction', 'FriendshipReputation', 'SkillLine', 'Holidays', 'Achievement', 'Criteria', 'CriteriaTree', 'ChrRaces', 'ChrClasses', 'ChrSpecialization', 'CurrencyTypes', 'Creature', 'GameObjects', 'Item', 'AreaPOI', 'LFGDungeons', 'JournalInstance', 'Covenant', 'ScheduledEvent', 'UiMapGroup', 'Expansion', 'ExpansionLevel'),
    [switch]$Download
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$dir = Join-Path $CacheDir $Build
New-Item -ItemType Directory -Force $dir, $OutDir | Out-Null

function Get-TableList([string]$build) {
    $page = (Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2?build=$build" -Headers @{ 'User-Agent' = 'QuestCompletist-tools' }).Content
    $names = [regex]::Matches($page, '&quot;\d+&quot;:&quot;([A-Za-z0-9_]+)&quot;') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    if ($names.Count -lt 100) { throw "Only $($names.Count) table names found for build ${build}: has wago.tools changed its page?" }
    return @($names)
}

if ($Download) {
    foreach ($t in (Get-TableList $Build)) {
        $path = Join-Path $dir "$t.csv"
        if ((Test-Path $path) -and (Get-Item $path).Length -gt 0) { continue }
        for ($try = 1; $try -le 3; $try++) {
            try { Invoke-WebRequest -UseBasicParsing -Uri "https://wago.tools/db2/$t/csv?build=$Build" -OutFile $path -Headers @{ 'User-Agent' = 'QuestCompletist-tools' }; break }
            catch { Remove-Item $path -ErrorAction SilentlyContinue; Start-Sleep -Seconds (5 * $try) }
        }
        Start-Sleep -Milliseconds 600
    }
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

public class ColumnStats {
    public string Name;
    public long NonEmpty, NonZero, Rows;
    public bool AllInteger = true, AllNumber = true;
    public long MinI = long.MaxValue, MaxI = long.MinValue;
    public double MinD = double.MaxValue, MaxD = double.MinValue;
    public Dictionary<string, long> Counts = new Dictionary<string, long>();
    public bool Overflow;
    public long[] Bits = new long[64];
    public long BitOr;
    public List<string> BitRows = new List<string>();
    public HashSet<long> Ids;
    public bool Uncapped, IdsCapped;
}

public class TableStats {
    public string[] Header;
    public ColumnStats[] Cols;
    public long Rows;
    public int IdColumn = -1;
}

public static class CsvAudit {
    public static int CountIn(HashSet<long> vals, HashSet<long> target, long[] sortedTarget, out double chance) {
        int n = 0;
        long lo = long.MaxValue, hi = long.MinValue;
        foreach (long v in vals) {
            if (v == 0) continue;
            if (v < lo) lo = v;
            if (v > hi) hi = v;
            if (target.Contains(v)) n++;
        }
        chance = 1;
        if (hi >= lo) {
            int a = Array.BinarySearch(sortedTarget, lo); if (a < 0) a = ~a;
            int b = Array.BinarySearch(sortedTarget, hi); b = b < 0 ? ~b : b + 1;
            chance = Math.Min(1.0, (double)(b - a) / (double)(hi - lo + 1));
        }
        return n;
    }

    static List<string[]> ReadRecords(TextReader r, int limit) {
        var list = new List<string[]>();
        var fields = new List<string>();
        var sb = new StringBuilder();
        bool inQ = false, any = false;
        int c;
        while ((c = r.Read()) != -1) {
            char ch = (char)c;
            if (inQ) {
                if (ch == '"') {
                    if (r.Peek() == '"') { r.Read(); sb.Append('"'); } else inQ = false;
                } else sb.Append(ch);
            } else if (ch == '"') { inQ = true; any = true; }
            else if (ch == ',') { fields.Add(sb.ToString()); sb.Length = 0; any = true; }
            else if (ch == '\r') { }
            else if (ch == '\n') {
                if (any || sb.Length > 0) { fields.Add(sb.ToString()); list.Add(fields.ToArray()); }
                fields.Clear(); sb.Length = 0; any = false;
                if (limit > 0 && list.Count >= limit) return list;
            } else { sb.Append(ch); any = true; }
        }
        if (any || sb.Length > 0) { fields.Add(sb.ToString()); list.Add(fields.ToArray()); }
        return list;
    }

    public static TableStats Measure(string path, HashSet<string> bitColumns, HashSet<string> collectColumns, int maxDistinct) {
        var ts = new TableStats();
        using (var sr = new StreamReader(path, Encoding.UTF8, true, 1 << 16)) {
            var head = ReadRecords(new StringReader(PeekLine(path)), 1);
            if (head.Count == 0) return ts;
            ts.Header = head[0];
            if (ts.Header.Length > 0 && ts.Header[0].Length > 0 && ts.Header[0][0] == (char)0xFEFF) ts.Header[0] = ts.Header[0].Substring(1);
            int n = ts.Header.Length;
            ts.Cols = new ColumnStats[n];
            for (int i = 0; i < n; i++) {
                ts.Cols[i] = new ColumnStats { Name = ts.Header[i] };
                if (ts.Header[i] == "ID") ts.IdColumn = i;
                ts.Cols[i].Ids = new HashSet<long>();
                ts.Cols[i].Uncapped = ts.Header[i] == "ID" || collectColumns.Contains(ts.Header[i]);
            }
            sr.ReadLine();
            var fields = new List<string>();
            var sb = new StringBuilder();
            bool inQ = false, any = false;
            int c;
            while ((c = sr.Read()) != -1) {
                char ch = (char)c;
                if (inQ) {
                    if (ch == '"') {
                        if (sr.Peek() == '"') { sr.Read(); sb.Append('"'); } else inQ = false;
                    } else sb.Append(ch);
                } else if (ch == '"') { inQ = true; any = true; }
                else if (ch == ',') { fields.Add(sb.ToString()); sb.Length = 0; any = true; }
                else if (ch == '\r') { }
                else if (ch == '\n') {
                    if (any || sb.Length > 0) { fields.Add(sb.ToString()); Row(ts, fields, bitColumns, maxDistinct); }
                    fields.Clear(); sb.Length = 0; any = false;
                } else { sb.Append(ch); any = true; }
            }
            if (any || sb.Length > 0) { fields.Add(sb.ToString()); Row(ts, fields, bitColumns, maxDistinct); }
        }
        return ts;
    }

    static string PeekLine(string path) {
        using (var s = new StreamReader(path, Encoding.UTF8, true, 1 << 16)) {
            var sb = new StringBuilder();
            bool inQ = false;
            int c;
            while ((c = s.Read()) != -1) {
                char ch = (char)c;
                if (ch == '"') inQ = !inQ;
                if (ch == '\n' && !inQ) break;
                sb.Append(ch);
            }
            return sb.ToString() + "\n";
        }
    }

    static void Row(TableStats ts, List<string> f, HashSet<string> bitColumns, int maxDistinct) {
        ts.Rows++;
        int n = ts.Cols.Length;
        string rowId = ts.IdColumn >= 0 && ts.IdColumn < f.Count ? f[ts.IdColumn] : ts.Rows.ToString();
        for (int i = 0; i < n; i++) {
            var cs = ts.Cols[i];
            cs.Rows++;
            string v = i < f.Count ? f[i] : "";
            if (v.Length == 0) continue;
            cs.NonEmpty++;
            long l = 0; double d = 0;
            bool isInt = cs.AllInteger && long.TryParse(v, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out l);
            bool isNum = false;
            if (isInt) { isNum = true; d = l; }
            else if (cs.AllNumber) isNum = double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out d);
            if (!isInt) cs.AllInteger = false;
            if (!isNum) cs.AllNumber = false;
            if (isNum) {
                if (d != 0) cs.NonZero++;
                if (d < cs.MinD) cs.MinD = d;
                if (d > cs.MaxD) cs.MaxD = d;
                if (isInt) {
                    if (l < cs.MinI) cs.MinI = l;
                    if (l > cs.MaxI) cs.MaxI = l;
                    if (cs.Uncapped || cs.Ids.Count < 200000) cs.Ids.Add(l); else cs.IdsCapped = true;
                    if (l != 0 && bitColumns.Contains(cs.Name)) {
                        cs.BitOr |= l;
                        for (int b = 0; b < 64; b++) if (((ulong)l >> b & 1UL) != 0) {
                            cs.Bits[b]++;
                            if (cs.Bits[b] <= 3) cs.BitRows.Add(b + ":" + rowId);
                        }
                    }
                }
            } else cs.NonZero++;
            if (!cs.Overflow) {
                long cnt;
                cs.Counts.TryGetValue(v, out cnt);
                cs.Counts[v] = cnt + 1;
                if (cs.Counts.Count > maxDistinct) { cs.Overflow = true; }
            }
        }
    }
}
'@

function Get-Dbd([string]$table) {
    $file = Join-Path $DbdDir "$table.dbd"
    if (-not (Test-Path $file)) { return $null }
    $cols = @{}
    $inCols = $false
    foreach ($line in [IO.File]::ReadLines($file)) {
        if ($line -eq 'COLUMNS') { $inCols = $true; continue }
        if ($inCols -and $line.Trim() -eq '') { break }
        if (-not $inCols) { continue }
        if ($line -match '^(?<type>[a-z]+)(?:<(?<fk>[A-Za-z0-9_]+)::(?<fkcol>[A-Za-z0-9_]+)>)?\s+(?<name>[A-Za-z0-9_]+)(?<opt>\?)?(?:\s*//\s*(?<c>.*))?$') {
            $cols[$Matches.name] = [pscustomobject]@{ Type = $Matches.type; FkTable = $Matches.fk; FkColumn = $Matches.fkcol; Comment = $Matches.c }
        }
    }
    return $cols
}

$toolText = @{}
foreach ($f in Get-ChildItem (Join-Path $ToolsDir '*.ps1') | Where-Object { $_.Name -notmatch '^(Test-|Audit-ClientTables)' }) { $toolText[$f.Name] = [IO.File]::ReadAllText($f.FullName) }
function Get-ToolsMentioning([string[]]$tableFiles, [string]$column) {
    if (-not $tableFiles) { return '' }
    $base = $column -replace '_\d+$', ''
    $re = "(?<![A-Za-z0-9])$([regex]::Escape($base))(?:_\d+)?(?![A-Za-z0-9])"
    return (@($tableFiles | Where-Object { $toolText[$_] -match $re }) -join ';')
}

$targets = @{}
$none = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($n in $RefTargets) {
    $p = Join-Path $dir "$n.csv"
    if (-not (Test-Path $p)) { continue }
    $m = [CsvAudit]::Measure($p, $none, $none, 1)
    if ($m.IdColumn -ge 0 -and $m.Cols[$m.IdColumn].Ids.Count -ge 20) {
        $sorted = [long[]]@($m.Cols[$m.IdColumn].Ids); [Array]::Sort($sorted)
        $targets[$n] = @{ Ids = $m.Cols[$m.IdColumn].Ids; Sorted = $sorted }
    }
}
$refRows = New-Object System.Collections.ArrayList

$bitName = 'Flag|Mask|Bit|Modifier|Option|Filt|Legacy|Attr|Behavior|Required|Allowed|Hidden|Show|Visib'
$tableRows = New-Object System.Collections.ArrayList
$colRows = New-Object System.Collections.ArrayList
$bitRows = New-Object System.Collections.ArrayList
$fkRows = New-Object System.Collections.ArrayList
$ids = @{}
$pending = New-Object System.Collections.ArrayList
$files = Get-ChildItem (Join-Path $dir '*.csv') | Sort-Object Name
$i = 0
foreach ($f in $files) {
    $i++
    $t = $f.BaseName
    $dbd = Get-Dbd $t
    $bitCols = New-Object 'System.Collections.Generic.HashSet[string]'
    $header = ((Get-Content $f.FullName -TotalCount 1) -replace '^\xEF\xBB\xBF', '') -split ','
    foreach ($h in $header) {
        $b = $h -replace '_\d+$', ''
        $d = if ($dbd) { $dbd[$b] } else { $null }
        if ($h -match $bitName -or ($d -and $d.Comment -match 'flag|mask|bit')) { [void]$bitCols.Add($h) }
    }
    $fkCols = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($h in $header) { $d = if ($dbd) { $dbd[($h -replace '_\d+$', '')] } else { $null }; if ($d -and $d.FkTable -and $d.FkColumn -eq 'ID') { [void]$fkCols.Add($h) } }
    $ts = [CsvAudit]::Measure($f.FullName, $bitCols, $fkCols, 400)
    if (-not $ts.Cols) { continue }
    $fkOut = 0
    $tableRe = "(?<![A-Za-z0-9_])$([regex]::Escape($t))(?![A-Za-z0-9])"
    $tableFiles = @($toolText.Keys | Where-Object { $toolText[$_] -match $tableRe } | Sort-Object)
    foreach ($c in $ts.Cols) {
        $b = $c.Name -replace '_\d+$', ''
        $d = if ($dbd) { $dbd[$b] } else { $null }
        if ($d -and $d.FkTable) { $fkOut++ }
        $top = if ($c.Overflow) { '' } else { ($c.Counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8 | ForEach-Object { '{0}:{1}' -f ($_.Key.Substring(0, [Math]::Min(40, $_.Key.Length))), $_.Value }) -join ' | ' }
        $min = ''; $max = ''
        if ($c.AllInteger -and $c.NonEmpty -gt 0) { $min = $c.MinI; $max = $c.MaxI } elseif ($c.AllNumber -and $c.NonEmpty -gt 0) { $min = $c.MinD; $max = $c.MaxD }
        [void]$colRows.Add([pscustomobject]@{
            Table = $t; Column = $c.Name; DbdType = if ($d) { $d.Type } else { '' }
            FkTable = if ($d) { $d.FkTable } else { '' }; FkColumn = if ($d) { $d.FkColumn } else { '' }
            Comment = if ($d) { $d.Comment } else { '' }
            Rows = $c.Rows; NonEmpty = $c.NonEmpty; NonZero = $c.NonZero
            Distinct = if ($c.Overflow) { ">$($c.Counts.Count)" } else { $c.Counts.Count }
            Min = $min; Max = $max; Top = $top
            ReadBy = Get-ToolsMentioning $tableFiles $c.Name
        })
        if ($c.AllInteger -and $c.Ids.Count -ge 5 -and -not ($c.Name -eq 'ID')) {
            $nz = $c.Ids.Count - [int]$c.Ids.Contains(0)
            foreach ($tn in $targets.Keys) {
                if ($tn -eq $t) { continue }
                $chance = 0.0
                $hit = [CsvAudit]::CountIn($c.Ids, $targets[$tn].Ids, $targets[$tn].Sorted, [ref]$chance)
                $declared = [bool]($d -and $d.FkTable -eq $tn)
                if ($hit -ge 5 -and $nz -gt 0 -and ($hit / $nz) -ge 0.8 -and ($declared -or $chance -le 0.25)) {
                    [void]$refRows.Add([pscustomobject]@{ Table = $t; Column = $c.Name; Target = $tn; DistinctValues = $nz; Resolving = $hit; Share = [Math]::Round($hit / $nz, 3); ByChance = [Math]::Round($chance, 3); Capped = $c.IdsCapped; DeclaredFk = $declared; TargetIds = $targets[$tn].Ids.Count; NonZeroRows = $c.NonZero })
                }
            }
        }
        if ($bitCols.Contains($c.Name) -and $c.BitOr -ne 0) {
            $rowsByBit = @{}
            foreach ($br in $c.BitRows) { $p = $br -split ':', 2; if (-not $rowsByBit[$p[0]]) { $rowsByBit[$p[0]] = New-Object System.Collections.ArrayList }; [void]$rowsByBit[$p[0]].Add($p[1]) }
            for ($bit = 0; $bit -lt 64; $bit++) {
                if ($c.Bits[$bit] -gt 0) { [void]$bitRows.Add([pscustomobject]@{ Table = $t; Column = $c.Name; Bit = $bit; Mask = ('0x{0:X}' -f ([uint64]1 -shl $bit)); Rows = $c.Bits[$bit]; Of = $c.NonZero; Examples = ($rowsByBit["$bit"] -join ' ') }) }
            }
        }
        if ($d -and $d.FkTable) { [void]$pending.Add([pscustomobject]@{ Table = $t; Column = $c.Name; FkTable = $d.FkTable; FkColumn = $d.FkColumn; NonZero = $c.NonZero; Values = $c.Ids }) }
    }
    if ($ts.IdColumn -ge 0) { $ids[$t] = $ts.Cols[$ts.IdColumn].Ids }
    [void]$tableRows.Add([pscustomobject]@{
        Table = $t; Rows = $ts.Rows; Columns = $ts.Cols.Count; DbdKnown = [bool]$dbd; ForeignKeysOut = $fkOut
        ReadBy = $tableFiles -join ';'
    })
    if ($i % 100 -eq 0) { Write-Host "$i / $($files.Count) tables" }
}

foreach ($p in $pending) {
    $target = $ids[$p.FkTable]
    $row = [pscustomobject]@{ Table = $p.Table; Column = $p.Column; FkTable = $p.FkTable; FkColumn = $p.FkColumn; Used = $p.NonZero; DistinctValues = ''; Resolving = ''; Note = '' }
    if (-not $target) { $row.Note = 'target table not in this build' }
    elseif ($p.FkColumn -ne 'ID') { $row.Note = 'not an ID column, unchecked' }
    elseif ($p.NonZero -eq 0 -or -not $p.Values) { $row.Note = 'column empty' }
    else {
        $vals = @($p.Values | Where-Object { $_ -ne 0 })
        $row.DistinctValues = $vals.Count
        $row.Resolving = @($vals | Where-Object { $target.Contains($_) }).Count
    }
    [void]$fkRows.Add($row)
}

$colRows | Export-Csv (Join-Path $OutDir "$Game-columns.csv") -NoTypeInformation -Encoding UTF8
$tableRows | Export-Csv (Join-Path $OutDir "$Game-tables.csv") -NoTypeInformation -Encoding UTF8
$bitRows | Export-Csv (Join-Path $OutDir "$Game-bits.csv") -NoTypeInformation -Encoding UTF8
$fkRows | Export-Csv (Join-Path $OutDir "$Game-fks.csv") -NoTypeInformation -Encoding UTF8
$refRows | Export-Csv (Join-Path $OutDir "$Game-refs.csv") -NoTypeInformation -Encoding UTF8
Write-Host "$Game $Build : $($tableRows.Count) tables, $($colRows.Count) columns, $($bitRows.Count) set bits, $($fkRows.Count) foreign keys."
