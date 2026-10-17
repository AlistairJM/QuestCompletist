<#
Checks Audit-ClientTables.ps1 on a made-up client: three small tables, a schema for two of them and a made-up
tools folder, all in a temporary folder. Nothing in the checkout is touched and nothing is downloaded. It checks
the column counts, a quoted comma in a name, the set bits of a flag column, the share of a declared foreign key
that resolves, an undeclared reference found by value (and a column of small numbers that is not), and that a
column counts as read only when a tool mentions both its table and the column.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-AuditClientTables.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("audit_client_tables_test_" + [guid]::NewGuid().ToString('N'))
$build = '1.0.0.1'
$cache = Join-Path $root $build; $dbd = Join-Path $root 'dbd'; $tools = Join-Path $root 'tools'; $out = Join-Path $root 'out'
New-Item -ItemType Directory -Force $cache, $dbd, $tools, $out | Out-Null
try {
    $quests = (1..30 | ForEach-Object { "$($_ * 1000),$_" })
    Set-Content (Join-Path $cache 'QuestV2.csv') (@('ID,UniqueBitFlag') + $quests) -Encoding UTF8
    Set-Content (Join-Path $cache 'Thing.csv') @(
        'ID,QuestID,Flags,Name_lang',
        '1,1000,1,a', '2,2000,3,"b, with a comma"', '3,3000,0,c', '4,4000,4,d', '5,5000,1,e', '6,6000,1,f', '7,99999,0,g') -Encoding UTF8
    $mystery = (1..10 | ForEach-Object { "$($_),$($_ * 1000)" })
    $small = (1..10 | ForEach-Object { "$($_ + 10),$_" })
    Set-Content (Join-Path $cache 'Other.csv') (@('ID,Mystery,Small') + (1..10 | ForEach-Object { "$_,$($_ * 1000),$_" })) -Encoding UTF8
    Set-Content (Join-Path $dbd 'Thing.dbd') @('COLUMNS', 'int ID', 'int<QuestV2::ID> QuestID', 'int Flags // flag bits', 'locstring Name_lang', '', 'LAYOUT 00000000') -Encoding UTF8
    Set-Content (Join-Path $tools 'Fake.ps1') 'Import-Csv Thing.csv | ForEach-Object { $_.QuestID }' -Encoding UTF8

    & (Join-Path $PSScriptRoot 'Audit-ClientTables.ps1') -Game test -Build $build -CacheDir $root -DbdDir $dbd -OutDir $out -ToolsDir $tools | Out-Null

    $tables = @(Import-Csv (Join-Path $out 'test-tables.csv'))
    $columns = @(Import-Csv (Join-Path $out 'test-columns.csv'))
    $bits = @(Import-Csv (Join-Path $out 'test-bits.csv'))
    $fks = @(Import-Csv (Join-Path $out 'test-fks.csv'))
    $refs = @(Import-Csv (Join-Path $out 'test-refs.csv'))
    function Col($t, $c) { return @($columns | Where-Object { $_.Table -eq $t -and $_.Column -eq $c })[0] }

    Equal $tables.Count 3 'T1: three tables are measured'
    $thing = @($tables | Where-Object Table -eq 'Thing')[0]
    Equal $thing.Rows '7' 'T1: Thing has seven rows, the quoted comma did not split one'
    Equal $thing.Columns '4' 'T1: and four columns'
    Equal $thing.DbdKnown 'True' 'T1: its schema was found'
    Equal @($tables | Where-Object Table -eq 'Other')[0].DbdKnown 'False' 'T1: a table with no schema is still measured'
    Equal $thing.ReadBy 'Fake.ps1' 'T2: the tool that mentions the table is listed'

    Equal (Col 'Thing' 'Name_lang').Distinct '7' 'C1: seven distinct names'
    Equal (Col 'Thing' 'Name_lang').DbdType 'locstring' 'C1: the schema type is carried over'
    Equal (Col 'Thing' 'Flags').NonZero '5' 'C1: five rows have a flag set'
    Equal (Col 'Thing' 'Flags').Comment 'flag bits' 'C1: and the schema comment'
    Equal (Col 'Thing' 'QuestID').FkTable 'QuestV2' 'C2: the declared foreign key is kept'
    Equal (Col 'Thing' 'QuestID').ReadBy 'Fake.ps1' 'C3: a column a tool mentions with its table is read'
    Equal (Col 'Thing' 'Flags').ReadBy '' 'C3: one it does not mention is not'
    Equal (Col 'Other' 'Mystery').ReadBy '' 'C3: nor is a column of a table no tool mentions'

    $flagBits = @($bits | Where-Object { $_.Table -eq 'Thing' -and $_.Column -eq 'Flags' })
    Equal (($flagBits | ForEach-Object { "$($_.Bit):$($_.Rows)" }) -join ' ') '0:4 1:1 2:1' 'B1: bits 0, 1 and 2 are set on four, one and one rows'
    Equal (@($flagBits | Where-Object Bit -eq '0')[0].Examples) '1 2 5' 'B1: with the first rows that have the lowest bit'
    Equal @($bits | Where-Object { $_.Column -eq 'Name_lang' }).Count 0 'B1: a text column has no bits'

    $fk = @($fks | Where-Object { $_.Table -eq 'Thing' -and $_.Column -eq 'QuestID' })[0]
    Equal $fk.DistinctValues '7' 'F1: seven distinct quest values'
    Equal $fk.Resolving '6' 'F1: six are quests, 99999 is not'

    $ref = @($refs | Where-Object { $_.Table -eq 'Other' -and $_.Column -eq 'Mystery' -and $_.Target -eq 'QuestV2' })
    Equal $ref.Count 1 'R1: an undeclared column of quest IDs is found'
    Equal $ref[0].DeclaredFk 'False' 'R1: and marked undeclared'
    Equal @($refs | Where-Object { $_.Table -eq 'Other' -and $_.Column -eq 'Small' }).Count 0 'R2: a column of small numbers is not taken for quests'
    $declared = @($refs | Where-Object { $_.Table -eq 'Thing' -and $_.Column -eq 'QuestID' })
    Equal $declared.Count 1 'R3: the declared key shows too'
    Equal $declared[0].DeclaredFk 'True' 'R3: marked declared'

    # A second run in the same session works (the type is added once).
    & (Join-Path $PSScriptRoot 'Audit-ClientTables.ps1') -Game test2 -Build $build -CacheDir $root -DbdDir $dbd -OutDir $out -ToolsDir $tools | Out-Null
    Check (Test-Path (Join-Path $out 'test2-tables.csv')) 'S1: a second run in one session writes its files'
}
finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "$Passed checks passed, $Failed failed."
if ($Failed -gt 0) { exit 1 }
