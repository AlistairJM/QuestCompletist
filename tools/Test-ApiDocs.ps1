<#
Checks Read-ApiDocs.lua and Compare-ApiDocs.ps1 on small documentation made here, in a scratch folder:
nothing in the checkout is written and nothing is downloaded. The reader is run on documentation files
with every kind of secrecy flag, and the comparison on a base build and builds that change one thing
each (a flag added or removed on a function, an event or a structure the function returns, a payload,
a shape, a function that goes), for the functions and events the addon relies on and for those it
doesn't. It also checks lists saved before the flags were kept, a name two systems document, the
methods of script objects, names that differ by case, the build order, files that stop loading, the
scan of the addon's Lua, what the closing line claims, and the ways a run is refused.

  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ApiDocs.ps1

Ends with "N checks passed, M failed" and exits 1 on any failure. API_TEST_VERBOSE=1 prints every run.
#>
param(
    [string]$LuaExe = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)
$ErrorActionPreference = 'Stop'
$Tool = Join-Path $PSScriptRoot 'Compare-ApiDocs.ps1'
$Reader = Join-Path $PSScriptRoot 'Read-ApiDocs.lua'
$Passed = 0; $Failed = 0
function Check($condition, [string]$message) {
    if ($condition) { $script:Passed++ } else { $script:Failed++; Write-Output "FAIL: $message" }
}
function Equal($actual, $expected, [string]$message) {
    Check ($actual -ceq $expected) "$message (expected '$expected', got '$actual')"
}
function Has([string]$text, [string]$part, [string]$message) {
    Check ($text.Contains($part)) "$message (no '$part' in: $text)"
}
function Lacks([string]$text, [string]$part, [string]$message) {
    Check (-not $text.Contains($part)) "$message ('$part' is in: $text)"
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ("api-docs-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch | Out-Null

# --- Making documentation -------------------------------------------------------------------------

function LuaField([string]$name, [string]$type, [string]$extra = '') {
    '{ Name = "' + $name + '", Type = "' + $type + '", Nilable = false' + $(if ($extra) { ', ' + $extra } else { '' }) + ' }'
}
function LuaFunction([string]$name, [string]$flags, [string[]]$arguments, [string[]]$returns) {
    '{ Name = "' + $name + '", Type = "Function"' + $(if ($flags) { ', ' + $flags } else { '' }) + ', Arguments = { ' + ($arguments -join ', ') + ' }, Returns = { ' + ($returns -join ', ') + ' } }'
}
function LuaEvent([string]$literal, [string]$flags, [string[]]$payload) {
    '{ Name = "' + $literal + 'Event", Type = "Event", LiteralName = "' + $literal + '"' + $(if ($flags) { ', ' + $flags } else { '' }) + ', Payload = { ' + ($payload -join ', ') + ' } }'
}
function LuaStructure([string]$name, [string[]]$fields) {
    '{ Name = "' + $name + '", Type = "Structure", Fields = { ' + ($fields -join ', ') + ' } }'
}
function LuaCallback([string]$name, [string[]]$arguments) {
    '{ Name = "' + $name + '", Type = "CallbackType", Arguments = { ' + ($arguments -join ', ') + ' } }'
}
function LuaSystem([string]$system, [string]$namespace, [string[]]$functions = @(), [string[]]$events = @(), [string[]]$tables = @(), [string]$type = 'System', [string[]]$predicates = @()) {
    "local T =`n{`n`tName = `"$system`", Type = `"$type`", Namespace = `"$namespace`",`n`tFunctions = {`n" + ($functions -join ",`n") + "`n`t},`n`tEvents = {`n" + ($events -join ",`n") + "`n`t},`n`tTables = {`n" + ($tables -join ",`n") + "`n`t},`n`tPredicates = {`n" + (($predicates | ForEach-Object { '{ Name = "' + $_ + '", Type = "Precondition" }' }) -join ",`n") + "`n`t},`n}`nAPIDocumentation:AddDocumentationTable(T);`n"
}

# The base documentation, and what a build changes in it.
$Base = @{
    FooFlags = 'SecretArguments = "AllowedWhenUntainted"'; BarReturn = 'number'; HasBar = $true
    InnerFlag = ''; CallbackFlag = 'ConditionalSecret = true'; TestEventFlag = ''; TestEventType = 'number'; HasTestEvent = $true; HasOtherEvent = $true; UnlistenedFlag = ''
    QuestThingFlag = ''; QuestUnusedFlag = ''; OtherThingFlag = ''; OtherUnusedFlag = ''; GuardedFlag = ''
    Fresh = $false; DupAReturn = 'number'; DupAFlag = ''; DupBReturn = 'string'; DupBFlag = ''; ObjFlag = ''; GlobalTimeFlag = ''
    HasSelect = $true; HasExtra = $false; ForeverOnly = $false; EnumUser = 'plain'
    FooArg = 'number'; FooExtra = $false; HasQuestExtra = $false; HasQuestGone = $false; QuestUnusedRet = 'bool'
    HasOwnNs = $false; OwnNsFlag = ''; PredicatesFile = 'ok'
}
function With([hashtable]$changes) {
    $v = $Base.Clone()
    foreach ($k in $changes.Keys) { $v[$k] = $changes[$k] }
    return $v
}

function Get-Docs([hashtable]$v) {
    $docs = @{}
    $functions = @(
        (LuaFunction 'Foo' $v.FooFlags (@((LuaField 'id' $v.FooArg 'NeverSecret = true')) + @(if ($v.FooExtra) { LuaField 'extra' 'number' })) @((LuaField 'info' 'TestInfo'))),
        (LuaFunction 'Guarded' $v.GuardedFlag @() @((LuaField 'ok' 'bool'))),
        (LuaFunction 'Callback' '' @((LuaField 'handler' 'TestCallback')) @()),
        (LuaFunction 'Shapes' '' @('{ Name = "list", Type = "table", InnerType = "TestInfo", Nilable = true, Default = 5 }') @('{ Name = "mode", Type = "TestMode", Nilable = false, EnumValue = 3 }'))
    )
    if ($v.HasBar) { $functions += (LuaFunction 'Bar' '' @() @((LuaField 'n' $v.BarReturn 'SecretValue = true'))) }
    if ($v.Fresh) { $functions += (LuaFunction 'Fresh' 'SecretReturns = true' @() @((LuaField 'ok' 'bool'))) }
    if ($v.HasOwnNs) { $functions += (LuaFunction 'OwnGlobal' ('Namespace = ""' + $(if ($v.OwnNsFlag) { ', ' + $v.OwnNsFlag } else { '' })) @() @((LuaField 'ok' 'bool'))) }
    $events = @()
    if ($v.HasTestEvent) { $events += (LuaEvent 'TEST_EVENT' $v.TestEventFlag @((LuaField 'a' $v.TestEventType 'ConditionalSecret = true'))) }
    if ($v.HasOtherEvent) { $events += (LuaEvent 'OTHER_EVENT' '' @((LuaField 'x' 'TestInfo'))) }
    $events += (LuaEvent 'UNLISTENED_EVENT' $v.UnlistenedFlag @())
    $events += (LuaEvent 'EVENT_AFTER_DASHES' '' @())
    $events += (LuaEvent 'EVENT_IN_BLOCK' '' @())
    $tables = @(
        (LuaStructure 'TestInfo' @((LuaField 'a' 'number'), (LuaField 'b' 'number' 'NeverSecret = true'), (LuaField 'inner' 'TestInner'))),
        (LuaStructure 'TestInner' @((LuaField 'd' 'number' $v.InnerFlag), (LuaField 'loop' 'TestLoop'))),
        (LuaStructure 'TestLoop' @((LuaField 'again' 'TestLoop' 'SecretValue = true'), (LuaField 'back' 'TestInfo'))),
        (LuaCallback 'TestCallback' @((LuaField 'key' 'string' $v.CallbackFlag))),
        '{ Name = "TestMode", Type = "Enumeration", NumValues = 1, Fields = { { Name = "One", Type = "TestMode", EnumValue = 1 } } }'
    )
    $docs['TestDocumentation.lua'] = LuaSystem 'TestAPI' 'C_Test' $functions $events $tables
    $questFunctions = @(
        (LuaFunction 'Thing' $v.QuestThingFlag @() @((LuaField 'ok' 'bool'))),
        (LuaFunction 'Unused' $v.QuestUnusedFlag @() @((LuaField 'ok' $v.QuestUnusedRet))))
    $questEvents = @()
    if ($v.HasQuestGone) { $questFunctions += (LuaFunction 'Gone' '' @() @()) }
    if ($v.HasQuestExtra) {
        $questFunctions += (LuaFunction 'Extra' '' @() @((LuaField 'ok' 'bool')))
        $questEvents += (LuaEvent 'QUEST_EXTRA_EVENT' 'SecretPayloads = true' @())
    }
    $docs['QuestStuffDocumentation.lua'] = LuaSystem 'QuestStuffAPI' 'C_QuestStuff' $questFunctions $questEvents
    $docs['OtherDocumentation.lua'] = LuaSystem 'OtherAPI' 'C_Other' @(
        (LuaFunction 'Thing' $v.OtherThingFlag @() @((LuaField 'ok' 'bool'))),
        (LuaFunction 'Unused' $v.OtherUnusedFlag @() @((LuaField 'ok' 'bool'))))
    $docs['Digit2Documentation.lua'] = LuaSystem 'Digit2API' 'C_Digit2' @((LuaFunction 'Fn2' '' @() @()))
    $docs['AAADocumentation.lua'] = LuaSystem 'AAA' '' @((LuaFunction 'Dup' $v.DupAFlag @() @((LuaField 'x' $v.DupAReturn))))
    $globals = @(
        (LuaFunction 'Dup' $v.DupBFlag @() @((LuaField 'y' $v.DupBReturn))),
        (LuaFunction 'UnitName' '' @((LuaField 'unit' 'UnitToken')) @((LuaField 'name' 'string'))),
        (LuaFunction 'GetTime' $v.GlobalTimeFlag @() @((LuaField 'time' 'number')))
    )
    if ($v.HasSelect) { $globals += (LuaFunction 'Select' '' @() @()) }
    if ($v.HasExtra) { $globals += (LuaFunction 'Extra' '' @() @()) }
    $docs['ZZZDocumentation.lua'] = LuaSystem 'ZZZ' '' $globals
    $docs['ObjDocumentation.lua'] = LuaSystem 'ObjAPI' '' @((LuaFunction 'GetTime' $v.ObjFlag @() @((LuaField 'time' 'FrameTime')))) @() @() 'ScriptObject'
    if ($v.PredicatesFile -eq 'broken') { $docs['SecretPredicatesDocumentation.lua'] = "local T = { Name = `"SecretPredicates`", Type = `"System`", Predicates = { { Name = Enum.Kind.Bad } } }`nAPIDocumentation:AddDocumentationTable(T)`n" }
    else { $docs['SecretPredicatesDocumentation.lua'] = LuaSystem 'SecretPredicates' '' @() @() @() 'System' @('RequiresFooAccess') }
    if ($v.ForeverOnly) { $docs['ForeverDocumentation.lua'] = LuaSystem 'ForeverAPI' 'C_Forever' @((LuaFunction 'Only' '' @() @())) }
    if ($v.EnumUser -eq 'plain') { $docs['EnumUserDocumentation.lua'] = LuaSystem 'EnumUserAPI' 'C_EnumUser' @((LuaFunction 'Stable' '' @() @())) }
    if ($v.EnumUser -eq 'enum') { $docs['EnumUserDocumentation.lua'] = (LuaSystem 'EnumUserAPI' 'C_EnumUser' @((LuaFunction 'Stable' '' @() @((LuaField 'kind' 'number' 'EnumValue = Enum.Kind.Stable'))))) }
    return $docs
}

$AddonMain = @'
local info = C_Test.Foo(1)
local n = C_Test.Bar()
local g = C_Test.Guarded()
local cb = C_Test.Callback(nil)
local s = C_Test.Shapes()
local t = C_QuestStuff.Thing()
local o = C_Other.Thing()
local d2 = C_Digit2.Fn2()
local name = UnitName("player")
local d = Dup()
local now = GetTime()
local pick = select(1, ...)
local e = Extra()
frame:RegisterEvent("TEST_EVENT")
-- frame:RegisterEvent("UNLISTENED_EVENT") and C_Other.Hidden()
local dashes = "--"; frame:RegisterEvent("EVENT_AFTER_DASHES")
--[[ a block comment
frame:RegisterEvent("EVENT_IN_BLOCK")
C_Other.AlsoHidden()
]]
frame:Show()
local junk = "NOT_AN_EVENT"
'@
$AddonForever = "frame:RegisterEvent('OTHER_EVENT')`nlocal f = C_Forever and C_Forever.Only`n"
$BaseGlobals = @('UnitName', 'Dup', 'GetTime')

function New-Scenario([string]$name, [string]$addonMain = $AddonMain) {
    $root = Join-Path $Scratch $name
    foreach ($dir in 'tools', 'src\live', 'src\forever', 'addon\Forever') { New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null }
    [IO.File]::WriteAllText("$root\addon\main.lua", $addonMain)
    [IO.File]::WriteAllText("$root\addon\Forever\more.lua", $AddonForever)
    return @{ Root = $root; Tools = "$root\tools"; Source = "$root\src"; Addon = "$root\addon" }
}

# Puts a build's documentation in the source folder and runs the comparison on it.
function Set-Build([hashtable]$s, [hashtable]$v, [string]$build, [string]$branch = 'live') {
    $dir = Join-Path $s.Source $branch
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Get-ChildItem $dir -Filter *.lua | Remove-Item
    $docs = Get-Docs $v
    foreach ($file in $docs.Keys) { [IO.File]::WriteAllText((Join-Path $dir $file), $docs[$file]) }
    [IO.File]::WriteAllText((Join-Path $dir 'version.txt'), "$build`n")
}
function Invoke-Build([hashtable]$s, [hashtable]$v, [string]$build, [hashtable]$more = @{}, [string]$branch = 'live') {
    Set-Build $s $v $build $branch
    return (Invoke-Compare $s $more)
}
function Invoke-Compare([hashtable]$s, [hashtable]$more = @{}) {
    $params = @{ ToolsDir = $s.Tools; AddonDir = $s.Addon; SourceDir = $s.Source; LuaExe = $LuaExe; MinFiles = 1; MinLines = 5; Branches = @('live'); Globals = $BaseGlobals }
    foreach ($k in $more.Keys) { $params[$k] = $more[$k] }
    $global:LASTEXITCODE = 0
    $failure = ''
    $lines = @()
    try { $lines = @(& $Tool @params) } catch { $failure = $_.Exception.Message }
    if ($env:API_TEST_VERBOSE) { Write-Host "---- run (exit $global:LASTEXITCODE) $failure"; $lines | ForEach-Object { Write-Host "     $_" } }
    return @{ Text = ($lines -join "`n"); Exit = $global:LASTEXITCODE; Failure = $failure }
}
function Read-Tsv([string]$path) {
    $rows = @{}
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        if ($line.StartsWith('#')) { continue }
        $f = $line -split "`t"
        $rows["$($f[0]) $($f[2]) $($f[3])"] = $f
    }
    return $rows
}
function Cut-ToOldFormat([string]$path) {
    [IO.File]::WriteAllLines($path, [string[]]@([IO.File]::ReadAllLines($path) | Where-Object { -not $_.StartsWith('#') } | ForEach-Object { ($_ -split "`t")[0..6] -join "`t" }))
}

try {
    # --- The reader ------------------------------------------------------------------------------
    $docDir = Join-Path $Scratch 'reader'
    New-Item -ItemType Directory -Path $docDir | Out-Null
    $files = Get-Docs (With @{ InnerFlag = 'NeverSecret = true'; GuardedFlag = 'RequiresFooAccess = true' })
    foreach ($file in $files.Keys) { [IO.File]::WriteAllText("$docDir\$file", $files[$file]) }
    [IO.File]::WriteAllText("$docDir\FlagsDocumentation.lua", (LuaSystem 'FlagsAPI' 'C_Flags' @(
        '{ Name = "Many", Type = "Function", SecretArguments = "NotAllowed", SecretReturns = true, ConstSecretAccessor = true, SecretWhenInCombat = true, isaurasecret = true, MayReturnNothing = true, HasRestrictions = true, Documentation = { "One", "two" }, SecretReturnsForAspect = { "Text", "Cooldown" }, SecretNotSet = false, RequiresFooAccess = true, RequiresUndeclared = true, Arguments = {}, Returns = {} }',
        '{ Name = "Plain", Type = "Function", Documentation = { "Nothing secret here." } }',
        '{ Name = "ByType", Type = "Function", Arguments = { { Name = "list", Type = "table", InnerType = "TestInfo", Nilable = false } } }',
        '{ Name = "EnumUser", Type = "Function", Arguments = { { Name = "mode", Type = "Mode", Nilable = false } } }',
        '{ Name = "OwnNs", Type = "Function", Namespace = "", SecretReturns = true, Arguments = {}, Returns = {} }',
        '{ Name = "Tabs", Type = "Function", Documentation = { "a\tb\nc" }, Arguments = {}, Returns = {} }',
        '{ Name = "Defaults", Type = "Function", Arguments = { { Name = "flag", Type = "bool", Nilable = false, Default = false } }, Returns = {} }',
        '{ Name = "Many2", Type = "Function", Arguments = { { Name = "x", Type = "number", Nilable = false, NeverSecret = true, ConditionalSecret = true, SecretValue = true } } }') @() @(
        '{ Name = "Mode", Type = "Enumeration", NumValues = 1, Fields = { { Name = "One", Type = "Mode", EnumValue = 1, NeverSecret = true } } }',
        '{ Name = "Flagged", Type = "Structure", SecretWhenInCombat = true, Fields = { { Name = "a", Type = "number", Nilable = false } } }',
        '{ Name = "UsesFlagged", Type = "Structure", Fields = { { Name = "f", Type = "Flagged", Nilable = false } } }')))
    [IO.File]::WriteAllText("$docDir\ObjNsDocumentation.lua", (LuaSystem 'ObjNsAPI' 'C_ObjNs' @((LuaFunction 'Method' '' @() @())) @() @() 'ScriptObject'))
    [IO.File]::WriteAllText("$docDir\BrokenDocumentation.lua", "local T = { Name = `"Broken`", Type = `"System`", Functions = { { Name = `"X`", Type = `"Function`", SecretReturnsForAspect = { Enum.SecretAspect.Text } } } }`nAPIDocumentation:AddDocumentationTable(T)`n")
    $names = @(Get-ChildItem $docDir -Filter *.lua | Sort-Object Name | ForEach-Object { $_.Name })
    $out = @(& $LuaExe $Reader $docDir @names)
    Equal $LASTEXITCODE 0 'R1: the reader exits 0 although a file does not load'
    $rowsOut = @($out | Where-Object { $_ -notmatch '^#' })
    Check ($rowsOut.Count -gt 0 -and @($rowsOut | Where-Object { @($_ -split "`t").Count -ne 8 }).Count -eq 0) 'R1: every line has eight columns'
    Check (@($out | Where-Object { $_ -match '^# BrokenDocumentation\.lua: .*Enum' }).Count -eq 1) 'R1: the file that needs Enum is reported on a # line'
    Equal @($out | Where-Object { $_ -match '^# \d+ files, \d+ failed to load$' })[0] ('# ' + $names.Count + ' files, 1 failed to load') 'R1: and the count line says so'
    Check (-not (($rowsOut -join "`n") -match 'Broken')) 'R1: and none of its lines are printed'
    $table = @{}
    foreach ($line in $rowsOut) { $f = $line -split "`t"; $table["$($f[0]) $($f[2]) $($f[3])"] = $f }
    $foo = $table['F C_Test Foo']
    Equal $foo[7] 'SecretArguments=AllowedWhenUntainted; arg id:NeverSecret; TestInfo.b:NeverSecret; TestInner.d:NeverSecret; TestLoop.again:SecretValue' 'R2: a function: its flags, its argument, then the structures its return leads to, each once, a loop ended'
    Equal $table['F C_Test Bar'][7] 'return n:SecretValue' 'R2: a return field'
    Equal $table['E C_Test TEST_EVENT'][7] 'payload a:ConditionalSecret' 'R2: a payload field'
    Equal $table['E C_Test OTHER_EVENT'][7] 'TestInfo.b:NeverSecret; TestInner.d:NeverSecret; TestLoop.again:SecretValue' 'R2: a payload typed with a structure'
    Equal $table['E C_Test UNLISTENED_EVENT'][7] '' 'R2: nothing when there is nothing'
    Equal $table['F C_Test Callback'][7] 'TestCallback.key:ConditionalSecret' 'R2: a callback type is followed like a structure'
    Equal $table['F C_Test Guarded'][7] 'RequiresFooAccess' 'R2: a precondition the documentation declares is a flag'
    Equal $table['F C_Flags Many'][7] 'ConstSecretAccessor; RequiresFooAccess; SecretArguments=NotAllowed; SecretNotSet=false; SecretReturns; SecretReturnsForAspect=[Text,Cooldown]; SecretWhenInCombat; isaurasecret' 'R3: every key with secret in it in any case, the declared preconditions and not the undeclared ones, in order: true, a string, false, a list'
    Equal $table['F C_Flags Many'][6] 'MayReturnNothing; HasRestrictions; One two' 'R3: and none of them in the notes'
    Equal $table['F C_Flags Many2'][7] 'arg x:ConditionalSecret,NeverSecret,SecretValue' 'R3: several flags on one field, sorted'
    Equal $table['F C_Flags Plain'][7] '' 'R3: a function with documentation and no flags'
    Equal $table['F C_Flags ByType'][7] 'TestInfo.b:NeverSecret; TestInner.d:NeverSecret; TestLoop.again:SecretValue' 'R3: a table<Structure> argument leads to the structure'
    Equal $table['F C_Flags EnumUser'][7] '' 'R3: an enumeration is not a structure'
    Equal $table['T C_Test TestLoop (Structure)'][7] 'field again:SecretValue; TestInfo.b:NeverSecret; TestInner.d:NeverSecret' 'R4: a structure row: its own fields, then what they lead to'
    Equal $table['T C_Flags Flagged (Structure)'][7] 'SecretWhenInCombat' 'R4: a structure with a flag of its own'
    Equal $table['T C_Flags UsesFlagged (Structure)'][7] 'Flagged:SecretWhenInCombat' 'R4: and a structure that holds it, with the name'
    Equal $table['F C_Test Shapes'][4] 'list:table<TestInfo>?=5' 'R5: an argument: type, inner type, nilable and default'
    Equal $table['F C_Test Shapes'][5] 'mode:TestMode=3' 'R5: a return: the enum value'
    Equal $table['F ObjAPI GetTime'][2] 'ObjAPI' 'R6: the methods of a script object carry the system as their namespace'
    Equal $table['F  GetTime'][2] '' 'R6: a global carries none'
    Equal $table['F C_ObjNs Method'][2] 'C_ObjNs' 'R6: a script object that names a namespace keeps it'
    Equal $table['F  OwnNs'][7] 'SecretReturns' 'R6b: a function with a Namespace of its own is filed under it (here a global), not under its system'
    Check (-not $table.ContainsKey('F C_Flags OwnNs')) 'R6b: and not under the system'
    Equal $table['F C_Flags Tabs'][6] 'a b c' 'R6c: tabs and newlines in the documentation become spaces'
    Equal $table['F C_Flags Defaults'][4] 'flag:bool=false' 'R6c: a default of false is shown'
    $again = @(& $LuaExe $Reader $docDir @($names))
    Equal ($again -join "`n") ($out -join "`n") 'R7: a second reading is the same, line for line'
    $reversed = @(& $LuaExe $Reader $docDir @($names | Sort-Object -Descending))
    Equal (($reversed | Where-Object { $_ -notmatch '^#' } | Sort-Object) -join "`n") (($out | Where-Object { $_ -notmatch '^#' } | Sort-Object) -join "`n") 'R7: and the files in the other order give the same lines'

    # a flag the reader can't write down stops it loudly
    $badDir = Join-Path $Scratch 'badflag'
    New-Item -ItemType Directory -Path $badDir | Out-Null
    [IO.File]::WriteAllText("$badDir\BadDocumentation.lua", (LuaSystem 'BadAPI' 'C_Bad' @('{ Name = "X", Type = "Function", SecretReturnsForAspect = { { "Text" } } }')))
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $badOut = @(& $LuaExe $Reader $badDir 'BadDocumentation.lua' 2>&1) } finally { $ErrorActionPreference = $saved }
    Check ($LASTEXITCODE -ne 0) 'R8: a list flag holding a table stops the reader'
    Check ((($badOut | ForEach-Object { "$_" }) -join ' ') -match 'flag SecretReturnsForAspect holds a table') 'R8: and says which flag'
    Check ((($badOut | ForEach-Object { "$_" }) -join ' ') -match 'BadAPI C_Bad X: ') 'R8: and which function'

    # --- The comparison --------------------------------------------------------------------------
    $s = New-Scenario 'first'
    $r = Invoke-Build $s $Base '1.0.0.1'
    Equal $r.Failure '' 'A1: the first run does not fail'
    Equal $r.Exit 0 'A1: and exits 0'
    Has $r.Text 'No earlier list for this branch' 'A1: it says there is nothing to compare with'
    Has $r.Text 'carry secrecy flags' 'A1: and how many carry flags'
    Has $r.Text '3 events the addon listens for are documented: 3 on this branch.' 'A1: three events: one in quotes, one in a Forever file with single quotes, one after a string holding two dashes; none from comments'
    Has $r.Text '12 C_ functions and listed globals the addon calls: 11 documented on this branch; not documented here: C_Forever.Only.' 'A1: twelve calls: nine C_ names (one with a digit, none from comments) and three globals'
    Lacks $r.Text 'Also checked' 'A1: no global is left out of the list'
    Has $r.Text 'Nothing the addon relies on changed in what was compared. Not compared: live (no earlier list).' 'A1: and the closing line says nothing was compared'
    Has $r.Text 'Not checked: the contents of structures' 'A1: and what it does not check'
    Lacks $r.Text 'documents and another' 'A1: a run on one branch has no one-game lists'
    $tsv = Read-Tsv "$($s.Tools)\api_docs-live-1.0.0.1.tsv"
    Check ($tsv.Count -gt 0 -and @($tsv.Values | Where-Object { $_.Count -ne 8 }).Count -eq 0) 'A1: the saved list has eight columns'
    Equal $tsv['F C_Test Foo'][7] 'SecretArguments=AllowedWhenUntainted; arg id:NeverSecret; TestInfo.b:NeverSecret; TestLoop.again:SecretValue' 'A1: and the flags'
    Check (Test-Path "$($s.Tools)\api_docs\live-1.0.0.1\TestDocumentation.lua") 'A1: the documentation is kept under the build'
    Check (@([IO.File]::ReadAllLines("$($s.Tools)\api_docs-live-1.0.0.1.tsv") | Where-Object { $_ -match '^# \d+ files, 0 failed to load$' }).Count -eq 1) 'A1: and the reader''s count line is kept in the list'

    $r = Invoke-Build $s $Base '1.0.0.2'
    Equal $r.Exit 0 'A2: the same documentation again exits 0'
    Has $r.Text 'Against api_docs-live-1.0.0.1.tsv: functions 0 added, 0 removed, 0 changed; events 0 added, 0 removed.' 'A2: and finds nothing'
    Has $r.Text 'Secrecy flags changed on 0 functions and 0 events (0 quest-related, 0 the addon relies on).' 'A2: nor any flag'
    Has $r.Text 'Every documented function the addon calls and every event it listens for is documented as before' 'A2: and says so'
    Has $r.Text 'Not checked: the contents of structures beyond their flags' 'A2: and what it does not check'

    $r = Invoke-Build $s (With @{ FooFlags = 'SecretArguments = "AllowedWhenUntainted", SecretWhenInCombat = true'; InnerFlag = 'NeverSecret = true'; QuestThingFlag = 'SecretReturns = true'; QuestUnusedFlag = 'SecretReturns = true'; OtherThingFlag = 'SecretReturns = true'; OtherUnusedFlag = 'SecretReturns = true'; TestEventFlag = 'SecretPayloads = true'; UnlistenedFlag = 'SecretPayloads = true' }) '1.0.0.3'
    Equal $r.Exit 1 'A3: flags added to what the addon relies on exit 1'
    Has $r.Text 'the addon calls C_Test.Foo: its secrecy flags changed (+SecretWhenInCombat; +TestInner.d:NeverSecret)' 'A3: a flag on the function and a flag on a structure it returns'
    Has $r.Text 'the addon calls C_QuestStuff.Thing: its secrecy flags changed (+SecretReturns)' 'A3: a quest-related function it calls'
    Has $r.Text 'the addon calls C_Other.Thing: its secrecy flags changed (+SecretReturns)' 'A3: another it calls'
    Lacks $r.Text 'the addon calls C_Test.Bar' 'A3: but not one that did not change'
    Has $r.Text 'the addon listens for TEST_EVENT: its secrecy flags changed (+SecretPayloads)' 'A3: an event it listens for'
    Has $r.Text 'the addon listens for OTHER_EVENT: its secrecy flags changed (+TestInner.d:NeverSecret)' 'A3: an event whose payload leads to the structure'
    Has $r.Text 'Secrecy flags changed on 6 functions and 3 events (2 quest-related, 6 the addon relies on).' 'A3: the counts: Foo and Shapes (both return the structure), both Things and both Unused; three events; two in a quest-related namespace; four functions and two events relied on'
    Has $r.Text 'secrecy: C_QuestStuff.Unused  +SecretReturns' 'A3: a quest-related one it does not call is listed'
    Lacks $r.Text 'secrecy: C_Other.Unused' 'A3: one that is not quest-related is not'
    Has $r.Text '(2 more outside the quest-related systems; -ListAll lists them.)' 'A3: but counted'
    Has $r.Text 'secrecy: C_Other.Thing  +SecretReturns' 'A3: one the addon calls is listed though it is not quest-related'
    Has $r.Text 'secrecy: event TEST_EVENT  +SecretPayloads' 'A3: and so is an event it listens for'
    Has $r.Text 'secrecy: C_Test.Foo  +SecretWhenInCombat; +TestInner.d:NeverSecret' 'A3: with what changed'
    Has $r.Text '6 function(s) or event(s) the addon relies on' 'A3: six things to check'
    Lacks $r.Text 'Nothing the addon relies on changed' 'A3: and no claim that all is well'
    $r = Invoke-Compare $s @{ ListAll = $true }
    Has $r.Text 'secrecy: C_Other.Unused  +SecretReturns' 'A3: -ListAll lists the rest'
    Has $r.Text 'secrecy: event UNLISTENED_EVENT  +SecretPayloads' 'A3: events too'

    $r = Invoke-Build $s (With @{ QuestUnusedFlag = 'SecretReturns = true'; OtherUnusedFlag = 'SecretReturns = true'; UnlistenedFlag = 'SecretPayloads = true' }) '1.0.0.4'
    Equal $r.Exit 1 'A4: flags taken away from what the addon relies on exit 1 too'
    Has $r.Text 'the addon calls C_Test.Foo: its secrecy flags changed (-SecretWhenInCombat; -TestInner.d:NeverSecret)' 'A4: shown as removed'
    Has $r.Text 'the addon listens for TEST_EVENT: its secrecy flags changed (-SecretPayloads)' 'A4: for an event'

    $s = New-Scenario 'unused'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ QuestUnusedFlag = 'SecretReturns = true'; OtherUnusedFlag = 'SecretReturns = true'; UnlistenedFlag = 'SecretPayloads = true' }) '1.0.0.2'
    Equal $r.Exit 0 'A5: flags on what the addon does not use are listed and do not fail the run'
    Has $r.Text 'Secrecy flags changed on 2 functions and 1 events (1 quest-related, 0 the addon relies on).' 'A5: and counted'
    Has $r.Text 'secrecy: C_QuestStuff.Unused' 'A5: the quest-related one is listed'
    Has $r.Text '(2 more outside the quest-related systems; -ListAll lists them.)' 'A5: the others are counted'

    $s = New-Scenario 'preconditions'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ GuardedFlag = 'RequiresFooAccess = true' }) '1.0.0.2'
    Equal $r.Exit 1 'A5b: a precondition the documentation declares, added to a function the addon calls, exits 1'
    Has $r.Text 'the addon calls C_Test.Guarded: its secrecy flags changed (+RequiresFooAccess)' 'A5b: shown as a flag'
    $r = Invoke-Build $s (With @{ GuardedFlag = 'RequiresUndeclared = true' }) '1.0.0.3'
    Equal $r.Exit 1 'A5b: and one removed again (the new build differs from the last)'
    $s = New-Scenario 'callbacks'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ CallbackFlag = 'NeverSecret = true' }) '1.0.0.2'
    Equal $r.Exit 1 'A5c: a flag changed on a callback''s argument exits 1 for the function that takes it'
    Has $r.Text 'the addon calls C_Test.Callback: its secrecy flags changed (+TestCallback.key:NeverSecret; -TestCallback.key:ConditionalSecret)' 'A5c: shown with the callback''s name'

    $s = New-Scenario 'events'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ TestEventType = 'string' }) '1.0.0.2'
    Equal $r.Exit 1 'A6: an event whose payload changed exits 1'
    Has $r.Text 'the addon listens for TEST_EVENT: its payload changed, was (a:number), now (a:string)' 'A6: with what changed'
    Has $r.Text '1 function(s) or event(s) the addon relies on' 'A6: and counts it'
    $s = New-Scenario 'eventgone'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ HasOtherEvent = $false }) '1.0.0.2'
    Equal $r.Exit 1 'A6: an event that went exits 1'
    Has $r.Text 'the addon listens for OTHER_EVENT: documented in api_docs-live-1.0.0.1.tsv, gone now' 'A6: and says which'
    Has $r.Text 'event removed: OTHER_EVENT' 'A6: besides the removal'
    Has $r.Text '1 function(s) or event(s) the addon relies on' 'A6: and it is the only one counted'
    Lacks $r.Text 'its payload changed' 'A6: with nothing else changed'
    $r = Invoke-Build $s (With @{ HasOtherEvent = $false }) '1.0.0.3'
    Equal $r.Exit 0 'A6: once it is gone, a run that still lacks it is clean'
    Has $r.Text '2 events the addon listens for are documented: 2 on this branch.' 'A6: with two events left'

    $s = New-Scenario 'shapes'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ BarReturn = 'string' }) '1.0.0.2'
    Equal $r.Exit 1 'A7: a function whose return changed exits 1 (as before)'
    Has $r.Text 'the addon calls C_Test.Bar: its shape changed' 'A7: saying so'
    $r = Invoke-Build $s (With @{ HasBar = $false }) '1.0.0.3'
    Equal $r.Exit 1 'A7: a function that went exits 1'
    Has $r.Text 'the addon calls C_Test.Bar: documented in api_docs-live-1.0.0.2.tsv, gone now' 'A7: saying so'
    $r = Invoke-Build $s $Base '1.0.0.4'
    Equal $r.Exit 1 'A7: one that comes back exits 1 (a game gaining a function)'
    Has $r.Text 'the addon calls C_Test.Bar: not documented in api_docs-live-1.0.0.3.tsv, documented now' 'A7: saying so'

    $s = New-Scenario 'fresh'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ Fresh = $true }) '1.0.0.2'
    Equal $r.Exit 0 'A8: a new function the addon does not call does not fail the run'
    Has $r.Text 'added:   C_Test.Fresh() -> ok:bool  [SecretReturns]' 'A8: and its flags are shown as it is added'
    Has $r.Text 'Secrecy flags changed on 0 functions and 0 events' 'A8: a function that is new is not a change of flags'

    # a list saved before the flags were kept
    $s = New-Scenario 'oldlist'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $old = "$($s.Tools)\api_docs-live-1.0.0.1.tsv"
    Cut-ToOldFormat $old
    Check (@([IO.File]::ReadAllLines($old) | Where-Object { @($_ -split "`t").Count -ne 7 }).Count -eq 0) 'A9: the list is cut back to seven columns'
    $r = Invoke-Build $s $Base '1.0.0.2'
    Equal $r.Exit 0 'A9: the same documentation against an old list exits 0'
    Has $r.Text 'was saved before the secrecy flags were kept; read again from' 'A9: the old list is read again from its folder'
    Equal @(([IO.File]::ReadAllLines($old) | Select-Object -First 1) -split "`t").Count 8 'A9: and saved with the flags'
    Has $r.Text 'Every documented function the addon calls' 'A9: and the closing line may claim a full comparison'
    $s = New-Scenario 'oldlist2'
    [void](Invoke-Build $s $Base '1.0.0.1')
    Cut-ToOldFormat "$($s.Tools)\api_docs-live-1.0.0.1.tsv"
    $r = Invoke-Build $s (With @{ FooFlags = 'SecretArguments = "NotAllowed"' }) '1.0.0.2'
    Equal $r.Exit 1 'A9: and a flag that changed since is found'
    Has $r.Text '+SecretArguments=NotAllowed; -SecretArguments=AllowedWhenUntainted' 'A9: as a change'
    $s = New-Scenario 'oldlist3'
    [void](Invoke-Build $s $Base '1.0.0.1')
    Cut-ToOldFormat "$($s.Tools)\api_docs-live-1.0.0.1.tsv"
    Remove-Item "$($s.Tools)\api_docs\live-1.0.0.1" -Recurse -Force
    $r = Invoke-Build $s (With @{ FooFlags = 'SecretArguments = "NotAllowed"' }) '1.0.0.2'
    Equal $r.Exit 0 'A10: with the folder gone, secrecy is not compared and the run does not fail on it'
    Has $r.Text 'is gone: secrecy is not compared this time.' 'A10: and says so'
    Has $r.Text 'Not compared: secrecy on live.' 'A10: and the closing line says so too'
    Lacks $r.Text 'Every documented function' 'A10: instead of claiming a full comparison'
    $r = Invoke-Build $s (With @{ BarReturn = 'string' }) '1.0.0.3'
    Equal $r.Exit 1 'A10: the next run has the flags again, and a shape change still fails'
    Has $r.Text '+SecretArguments=AllowedWhenUntainted; -SecretArguments=NotAllowed' 'A10: and the flag change is found'

    # a name two systems document, and the methods of script objects
    $s = New-Scenario 'dups'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ DupAReturn = 'string' }) '1.0.0.2'
    Equal $r.Exit 1 'A11: a change in the first of two systems documenting a global is seen'
    Has $r.Text 'the addon calls Dup: its shape changed' 'A11: as a shape change'
    $r = Invoke-Build $s (With @{ DupAReturn = 'string'; DupBReturn = 'number' }) '1.0.0.3'
    Equal $r.Exit 1 'A11: and so is a change in the second'
    Has $r.Text 'the addon calls Dup: its shape changed' 'A11: as a shape change'
    $r = Invoke-Build $s (With @{ DupAReturn = 'string'; DupBReturn = 'number'; DupBFlag = 'SecretReturns = true' }) '1.0.0.4'
    Equal $r.Exit 1 'A11: a flag in the second'
    Has $r.Text 'the addon calls Dup: its secrecy flags changed (+SecretReturns)' 'A11: as a flag change'
    $r = Invoke-Build $s (With @{ DupAReturn = 'string'; DupBReturn = 'number'; DupBFlag = 'SecretReturns = true'; DupAFlag = 'SecretWhenInCombat = true' }) '1.0.0.5'
    Equal $r.Exit 1 'A11: and a flag in the first'
    Has $r.Text 'the addon calls Dup: its secrecy flags changed (+SecretWhenInCombat)' 'A11: as a flag change'
    $s = New-Scenario 'objects'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ ObjFlag = 'SecretWhenInCombat = true' }) '1.0.0.2' @{ ListAll = $true }
    Equal $r.Exit 0 'A11b: a flag on a script object''s method does not alarm the global of the same name'
    Has $r.Text 'secrecy: ObjAPI.GetTime  +SecretWhenInCombat' 'A11b: and is listed under the object'
    $r = Invoke-Build $s (With @{ GlobalTimeFlag = 'SecretWhenInCombat = true' }) '1.0.0.3'
    Equal $r.Exit 1 'A11b: a flag on the global does'
    Has $r.Text 'the addon calls GetTime: its secrecy flags changed (+SecretWhenInCombat)' 'A11b: and says so'

    # case and the scan of the addon's Lua
    $s = New-Scenario 'case'
    $r = Invoke-Build $s $Base '1.0.0.1' @{ Globals = @('UnitName', 'Dup', 'GetTime', 'select') }
    Has $r.Text ', select.' 'A12: select is not the documented Select (listed last among those not documented here)'
    Lacks $r.Text 'Also checked' 'A12: and Select is not taken for a global the addon calls'
    $s = New-Scenario 'unlisted'
    $r = Invoke-Build $s (With @{ HasExtra = $true }) '1.0.0.1'
    Has $r.Text "Also checked, as documented globals the addon appears to call that -Globals doesn't list: Extra." 'A13: a documented global the addon calls and the list lacks is named'
    Has $r.Text '13 C_ functions and listed globals the addon calls: 12 documented' 'A13: and checked with the rest'
    Equal $r.Exit 0 'A13: without failing the run'
    $r = Invoke-Build $s (With @{ HasExtra = $true }) '1.0.0.2' @{ Globals = @('UnitName', 'Dup', 'GetTime', 'Extra') }
    Lacks $r.Text 'Also checked' 'A13: once listed it is not named'
    $s = New-Scenario 'unlisted2'
    [void](Invoke-Build $s (With @{ HasExtra = $true }) '1.0.0.1')
    $r = Invoke-Build $s (With @{ HasExtra = $false }) '1.0.0.2'
    Equal $r.Exit 1 'A13: a documented global the addon calls that goes is found though the list never had it'
    Has $r.Text 'the addon calls Extra: documented in api_docs-live-1.0.0.1.tsv, gone now' 'A13: saying so'
    $quoted = "local a = C_Test.Foo()`nframe:Extra()`nlocal b = obj.Extra`nlocal c = other .. Extra`nlocal Extra2 = 1`n"
    $s = New-Scenario 'methods' $quoted
    $r = Invoke-Build $s (With @{ HasExtra = $true }) '1.0.0.1'
    Has $r.Text "Also checked, as documented globals the addon appears to call that -Globals doesn't list: Extra." 'A13b: a name after .. is a name'
    $s = New-Scenario 'methods2'
    [IO.File]::WriteAllText("$($s.Root)\addon\main.lua", "local a = C_Test.Foo()`nframe:Extra()`nlocal b = obj.Extra`nlocal Extra = 1`nlocal t = { Extra = 2 }`n")
    $r = Invoke-Build $s (With @{ HasExtra = $true }) '1.0.0.1'
    Lacks $r.Text 'Also checked' 'A13b: a method, a field and an assignment are not calls of a global'
    $s = New-Scenario 'digits'
    [IO.File]::WriteAllText("$($s.Root)\addon\main.lua", "local a = C_Digit2.Fn2()`n")
    $r = Invoke-Build $s $Base '1.0.0.1'
    Has $r.Text '5 C_ functions and listed globals the addon calls: 4 documented' 'A13c: C_ names with digits are whole (C_Digit2.Fn2 and the Forever file''s C_Forever.Only, and three globals)'

    # build order and two branches
    $s = New-Scenario 'order'
    [void](Invoke-Build $s $Base '1.0.0.9')
    [void](Invoke-Build $s $Base '1.0.0.10')
    $r = Invoke-Build $s $Base '1.0.0.11'
    Has $r.Text 'Against api_docs-live-1.0.0.10.tsv' 'A14: build 10 is later than build 9'
    $r = Invoke-Build $s $Base '1.0.0.5'
    Has $r.Text 'No earlier list for this branch' 'A14: a build compares with an earlier one, never a later one'
    $s = New-Scenario 'two'
    [void](Invoke-Build $s $Base '1.0.0.1')
    [void](Invoke-Build $s $Base '2.0.0.1' @{ Branches = @('forever') } 'forever')
    $r = Invoke-Build $s (With @{ ForeverOnly = $true }) '2.0.0.2' @{ Branches = @('live', 'forever') } 'forever'
    Has $r.Text '== live build 1.0.0.1' 'A15: both branches are read'
    Has $r.Text '== forever build 2.0.0.2' 'A15: the second too'
    Has $r.Text 'documents and another doesn''t: C_Forever.Only (forever only).' 'A15: and the one-game list ends the run'
    Has $r.Text 'Events the addon listens for that one game documents and another doesn''t: none.' 'A15: with the events after it'
    Equal $r.Exit 1 'A15: a game that gained a function the addon calls exits 1'
    $s = New-Scenario 'twoevents'
    [void](Invoke-Build $s $Base '1.0.0.1')
    [void](Invoke-Build $s (With @{ HasOtherEvent = $false }) '2.0.0.1' @{ Branches = @('forever') } 'forever')
    $r = Invoke-Compare $s @{ Branches = @('live', 'forever') }
    Has $r.Text 'Events the addon listens for that one game documents and another doesn''t: OTHER_EVENT (live only).' 'A15: an event one game documents is named'

    # a documentation file that stops loading, or starts
    $s = New-Scenario 'noload'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ EnumUser = 'enum' }) '1.0.0.2'
    Equal $r.Exit 0 'A16: a file that stops loading does not fail the run if the addon uses nothing in it'
    Has $r.Text 'EnumUserDocumentation.lua loaded before and doesn''t now' 'A16: it is named'
    Has $r.Text 'what it documents shows as removed' 'A16: with what that means'
    Has $r.Text 'removed: C_EnumUser.Stable' 'A16: and the functions show as removed'
    Has $r.Text 'EnumUserDocumentation.lua no longer loads on live' 'A16: the closing line points back to it'
    Lacks $r.Text 'Every documented function' 'A16: and does not claim a full comparison'
    $r = Invoke-Build $s $Base '1.0.0.3'
    Has $r.Text 'EnumUserDocumentation.lua didn''t load before and does now' 'A16: a file that loads again is named too'
    Has $r.Text 'EnumUserDocumentation.lua loads on live now' 'A16: and the closing line points back to it'

    # the closing line and the failures
    $s = New-Scenario 'readerfails'
    $fake = Join-Path $s.Root 'fake-lua.cmd'
    [IO.File]::WriteAllText($fake, "@echo off`r`necho F`tX`tC_X`tY`t`t`t`t`r`nexit /b 1`r`n")
    $r = Invoke-Build $s $Base '1.0.0.1' @{ LuaExe = $fake }
    Has $r.Failure 'Read-ApiDocs.lua failed' 'A17: a reader that fails stops the run'
    Check (-not (Test-Path "$($s.Tools)\api_docs-live-1.0.0.1.tsv")) 'A17: and leaves no list behind'
    $s = New-Scenario 'refresh'
    [void](Invoke-Build $s $Base '1.0.0.1')
    [void](Invoke-Build $s $Base '1.0.0.2')
    $r = Invoke-Build $s (With @{ FooFlags = 'SecretArguments = "NotAllowed"' }) '1.0.0.2'
    Equal $r.Exit 1 'A18: the same build read again from changed documentation is read from the changed files'
    Has $r.Text '+SecretArguments=NotAllowed' 'A18: with the change'

    # a break on one branch is not lost on the other
    $s = New-Scenario 'multi1'
    Set-Build $s $Base '1.0.0.1' 'live'; Set-Build $s $Base '2.0.0.1' 'forever'
    $r = Invoke-Compare $s @{ Branches = @('live', 'forever') }
    Has $r.Text 'Not compared: live (no earlier list); forever (no earlier list).' 'M1: both branches without an earlier list are named'
    Set-Build $s (With @{ BarReturn = 'string' }) '1.0.0.2' 'live'; Set-Build $s $Base '2.0.0.2' 'forever'
    $r = Invoke-Compare $s @{ Branches = @('live', 'forever') }
    Equal $r.Exit 1 'M2: a break on the first branch fails the run though the second is clean'
    Has $r.Text '1 function(s) or event(s) the addon relies on' 'M2: and is counted'
    Lacks $r.Text 'Every documented function' 'M2: with no claim that all is well'
    $s = New-Scenario 'multi2'
    Set-Build $s $Base '1.0.0.1' 'live'; Set-Build $s $Base '2.0.0.1' 'forever'
    [void](Invoke-Compare $s @{ Branches = @('live', 'forever') })
    Set-Build $s $Base '1.0.0.2' 'live'; Set-Build $s (With @{ BarReturn = 'string' }) '2.0.0.2' 'forever'
    $r = Invoke-Compare $s @{ Branches = @('live', 'forever') }
    Equal $r.Exit 1 'M3: and a break on the second branch does too'
    $s = New-Scenario 'multi3'
    Set-Build $s $Base '1.0.0.1' 'live'; Set-Build $s $Base '2.0.0.1' 'forever'
    [void](Invoke-Compare $s @{ Branches = @('live', 'forever') })
    Set-Build $s (With @{ EnumUser = 'enum' }) '1.0.0.2' 'live'; Set-Build $s (With @{ EnumUser = 'enum' }) '2.0.0.2' 'forever'
    $r = Invoke-Compare $s @{ Branches = @('live', 'forever') }
    Has $r.Text 'See above: EnumUserDocumentation.lua no longer loads on live; EnumUserDocumentation.lua no longer loads on forever.' 'M4: a file that stops loading on both branches is named for both'
    $s = New-Scenario 'twosecond'
    Set-Build $s (With @{ HasOtherEvent = $false }) '1.0.0.1' 'live'
    Set-Build $s (With @{ HasExtra = $true }) '2.0.0.1' 'forever'
    $r = Invoke-Compare $s @{ Branches = @('live', 'forever') }
    Has $r.Text 'Events the addon listens for that one game documents and another doesn''t: OTHER_EVENT (forever only).' 'M5: an event only the second game documents is named'
    Has $r.Text 'Extra (forever only)' 'M5: and so is a global'

    # arguments are part of a function's shape
    $s = New-Scenario 'args'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ FooArg = 'string' }) '1.0.0.2'
    Equal $r.Exit 1 'G1: an argument whose type changed exits 1'
    Has $r.Text 'the addon calls C_Test.Foo: its shape changed, was (id:number) -> info:TestInfo, now (id:string) -> info:TestInfo' 'G1: with what changed'
    $r = Invoke-Build $s (With @{ FooArg = 'string'; FooExtra = $true }) '1.0.0.3'
    Equal $r.Exit 1 'G1: and so does an argument added'
    Has $r.Text '(id:string, extra:number)' 'G1: shown in the list'

    # the scan of the addon's Lua
    $scan = "--[[ one ]] local a = C_Test.Foo() --[[ two ]]`n--[==[ C_Other.Thing() ]] C_Other.Unused() ]==] local b = C_Test.Bar()`nlocal s1 = `"q\`"--z`"; frame:RegisterEvent(`"TEST_EVENT`")`nlocal s2 = 'q\'--z'; frame:RegisterEvent('OTHER_EVENT')`nlocal t = u[v[1]]; local c = C_QuestStuff.Thing()`n-- C_Other.AlsoHidden()`n"
    $s = New-Scenario 'scan' $scan
    $r = Invoke-Build $s $Base '1.0.0.1'
    Has $r.Text '7 C_ functions and listed globals the addon calls: 6 documented on this branch; not documented here: C_Forever.Only.' 'S0: code between comments, a long comment of a level, and strings with escaped quotes and dashes'
    Has $r.Text '2 events the addon listens for are documented: 2 on this branch.' 'S0: and the events after them'
    $scanDoc = With @{ HasExtra = $true }
    $s = New-Scenario 'scan-comment' "local a = C_Test.Foo()`n-- Extra()`n--[[ Extra() ]]`n"
    Lacks (Invoke-Build $s $scanDoc '1.0.0.1').Text 'Also checked' 'S1: a name only in a comment is not a call'
    $s = New-Scenario 'scan-string' "local a = C_Test.Foo()`nlocal t = `"call Extra now`"`n"
    Lacks (Invoke-Build $s $scanDoc '1.0.0.1').Text 'Also checked' 'S2: a name only in a string is not a call'
    $s = New-Scenario 'scan-concat' "local a = C_Test.Foo()`nlocal t = `"x`"..Extra()`n"
    Has (Invoke-Build $s $scanDoc '1.0.0.1').Text 'Also checked' 'S3: a name after .. is a call'
    $s = New-Scenario 'scan-prefix' "local a = C_Test.Foo()`nlocal Extra2 = 1`n"
    Lacks (Invoke-Build $s $scanDoc '1.0.0.1').Text 'Also checked' 'S4: a longer name is not the name'
    $s = New-Scenario 'scan-compare' "local a = C_Test.Foo()`nif Extra == nil then end`n"
    Has (Invoke-Build $s $scanDoc '1.0.0.1').Text 'Also checked' 'S5: a comparison is a use'
    $s = New-Scenario 'scan-boundary' "local a = C_Test.Foo()`nlocal b = myC_Other.Thing`n"
    Has (Invoke-Build $s $Base '1.0.0.1').Text '5 C_ functions and listed globals the addon calls: 4 documented' 'S6: C_Other.Thing inside another name is not a call'

    # a function with a Namespace of its own, and a precondition file that does not load
    $s = New-Scenario 'ownns' "local a = C_Test.Foo()`nlocal g = OwnGlobal()`n"
    [void](Invoke-Build $s (With @{ HasOwnNs = $true }) '1.0.0.1')
    $r = Invoke-Build $s (With @{ HasOwnNs = $true; OwnNsFlag = 'SecretWhenInCombat = true' }) '1.0.0.2'
    Equal $r.Exit 1 'N1: a function filed under its own Namespace (a global) is checked as one'
    Has $r.Text 'the addon calls OwnGlobal: its secrecy flags changed (+SecretWhenInCombat)' 'N1: by its bare name'
    $s = New-Scenario 'nopredicates'
    [void](Invoke-Build $s (With @{ PredicatesFile = 'broken' }) '1.0.0.1')
    $r = Invoke-Build $s (With @{ PredicatesFile = 'broken' }) '1.0.0.2'
    Equal $r.Exit 0 'N2: preconditions that cannot be read do not fail the run'
    Has $r.Text 'Not compared: the Requires preconditions on live (SecretPredicatesDocumentation.lua doesn''t load).' 'N2: but are named as not compared'
    Lacks $r.Text 'Every documented function' 'N2: instead of claiming a full comparison'
    $s = New-Scenario 'foldnew' "local a = C_Test.Foo()`nlocal e = Extra()`n"
    [void](Invoke-Build $s $Base '1.0.0.1')
    $r = Invoke-Build $s (With @{ HasExtra = $true }) '1.0.0.2'
    Equal $r.Exit 1 'N3: a word the addon uses that becomes a documented global is checked once'
    Has $r.Text 'Only a word the addon uses' 'N3: and said to be only a word'

    # what a build reads and keeps
    $s = New-Scenario 'listings'
    [void](Invoke-Build $s (With @{ HasQuestGone = $true }) '1.0.0.1')
    $r = Invoke-Build $s (With @{ Fresh = $true; HasQuestExtra = $true; QuestUnusedRet = 'string' }) '1.0.0.2'
    Equal $r.Exit 0 'L1: functions and events added, removed and changed that the addon does not use do not fail the run'
    Has $r.Text 'functions 2 added, 1 removed, 1 changed; events 1 added, 0 removed.' 'L1: the counts'
    Has $r.Text 'added:   C_QuestStuff.Extra() -> ok:bool  <- quest-related, worth a look' 'L1: a quest-related function added'
    Has $r.Text 'removed: C_QuestStuff.Gone  <- quest-related' 'L1: a quest-related function removed'
    Has $r.Text 'changed: C_QuestStuff.Unused was () -> ok:bool, now () -> ok:string' 'L1: one changed'
    Has $r.Text 'event added:   QUEST_EXTRA_EVENT()  <- quest-related  [SecretPayloads]' 'L1: an event added, with its flags'
    Has $r.Text 'documentation files (0 don''t load on their own' 'L1: the header says how many files did not load'
    Check ($r.Text -match 'functions in \d+ C_ namespaces and the global systems, \d+ events; \d+ functions and \d+ events carry secrecy flags\.') 'L1: and how many functions and events carry flags'

    # the kept documentation folder
    $s = New-Scenario 'refresh2'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $kept = "$($s.Tools)\api_docs\live-1.0.0.1"
    Check (Test-Path "$kept\EnumUserDocumentation.lua") 'I1: the kept folder holds the build''s files'
    [void](Invoke-Build $s (With @{ EnumUser = 'none' }) '1.0.0.1')
    Check (-not (Test-Path "$kept\EnumUserDocumentation.lua")) 'I1: a file the source no longer has is removed on a refresh'
    Lacks ([IO.File]::ReadAllText("$($s.Tools)\api_docs-live-1.0.0.1.tsv")) 'C_EnumUser' 'I1: and so are its functions in the list'
    $count = (Get-Docs $Base).Count - 1
    $r = Invoke-Build $s (With @{ EnumUser = 'none' }) '1.0.0.1' @{ MinFiles = $count }
    Equal $r.Failure '' 'I2: exactly the least number of files asked for is enough'
    $r = Invoke-Build $s (With @{ EnumUser = 'none' }) '1.0.0.1' @{ MinFiles = $count + 1 }
    Check ($r.Failure -match 'Only \d+ documentation files') 'I2: one fewer is refused'
    Check ((Test-Path "$kept\TestDocumentation.lua")) 'I2: and the kept folder is left as it was'
    $s = New-Scenario 'junction'
    [void](Invoke-Build $s $Base '1.0.0.1')
    Set-Build $s $Base '1.0.0.2'
    $keptJunction = "$($s.Tools)\api_docs\live-1.0.0.2"
    New-Item -ItemType Directory -Path "$($s.Tools)\api_docs" -Force | Out-Null
    Move-Item "$($s.Source)\live" $keptJunction
    New-Item -ItemType Junction -Path "$($s.Source)\live" -Target $keptJunction | Out-Null
    $r = Invoke-Compare $s
    Equal $r.Failure '' 'I3: a source folder that is the kept folder itself does not lose it'
    Equal @(Get-ChildItem $keptJunction -Filter *.lua).Count (Get-Docs $Base).Count 'I3: every file is still there'
    (Get-Item "$($s.Source)\live").Delete()
    $s = New-Scenario 'oldnoload'
    [void](Invoke-Build $s (With @{ EnumUser = 'enum' }) '1.0.0.1')
    Cut-ToOldFormat "$($s.Tools)\api_docs-live-1.0.0.1.tsv"
    Remove-Item "$($s.Tools)\api_docs\live-1.0.0.1" -Recurse -Force
    $r = Invoke-Build $s (With @{ EnumUser = 'enum' }) '1.0.0.2'
    Lacks $r.Text 'loaded before and doesn''t now' 'I4: a list saved without the load information is not held against the files that do not load'
    Has $r.Text 'Not checked:' 'I4: and the closing line says what it did not check'
    $s = New-Scenario 'stray'
    [void](Invoke-Build $s $Base '1.0.0.1')
    [IO.File]::WriteAllText("$($s.Tools)\api_docs-live-stray.tsv", '')
    $r = Invoke-Build $s $Base '1.0.0.2'
    Equal $r.Failure '' 'I5: a file in the tools folder that is not a list of a build is ignored'
    $r = Invoke-Compare $s @{ SourceDir = '' }
    Check ($r.Failure -match '-SourceDir was given but is empty') 'I6: an empty -SourceDir is refused rather than downloading'
    $s = New-Scenario 'reread'
    [void](Invoke-Build $s $Base '1.0.0.1')
    $list = "$($s.Tools)\api_docs-live-1.0.0.1.tsv"
    [IO.File]::WriteAllLines($list, [string[]]@([IO.File]::ReadAllLines($list) | Where-Object { $_ -notmatch "`tC_Test`tFoo`t" }))
    $r = Invoke-Build $s $Base '1.0.0.2'
    Equal $r.Exit 0 'I7: an earlier list that no longer matches its kept folder is read from the folder'
    Has $r.Text 'functions 0 added, 0 removed, 0 changed; events 0 added, 0 removed.' 'I7: so nothing shows as added'

    # ways a run is refused
    $s = New-Scenario 'refused'
    $r = Invoke-Compare $s
    Has $r.Failure 'No version.txt' 'A19: no version.txt'
    [IO.File]::WriteAllText("$($s.Source)\live\version.txt", "not a build`n")
    $r = Invoke-Compare $s
    Has $r.Failure 'not a build number' 'A19: a version.txt that is not a build'
    [IO.File]::WriteAllText("$($s.Source)\live\version.txt", "1.0.0.1`n")
    $r = Invoke-Compare $s
    Has $r.Failure 'Only 0 documentation files' 'A19: too few documentation files'
    $r = Invoke-Build $s $Base '1.0.0.1' @{ MinLines = 100000 }
    Has $r.Failure 'it should give thousands' 'A19: too few lines'
    $s = New-Scenario 'noaddon'
    Remove-Item "$($s.Addon)\main.lua", "$($s.Addon)\Forever\more.lua"
    $r = Invoke-Build $s $Base '1.0.0.1'
    Has $r.Failure 'No .lua files in' 'A19: an addon folder with no Lua'

    # relative paths mean what the shell's folder says
    $s = New-Scenario 'relative'
    [void](Invoke-Build $s $Base '1.0.0.1')
    [void](Invoke-Build $s $Base '1.0.0.2')
    $other = Join-Path $Scratch 'elsewhere'
    New-Item -ItemType Directory -Path $other | Out-Null
    $savedDotNet = [Environment]::CurrentDirectory
    Push-Location $s.Root
    try {
        [Environment]::CurrentDirectory = $other
        $r = Invoke-Compare $s @{ ToolsDir = 'tools'; AddonDir = 'addon'; SourceDir = 'src' }
    } finally { [Environment]::CurrentDirectory = $savedDotNet; Pop-Location }
    Equal $r.Failure '' 'A20: relative folders are read relative to the shell'
    Has $r.Text 'Against api_docs-live-1.0.0.1.tsv' 'A20: and found the earlier list'
    Check (-not (Test-Path (Join-Path $other 'tools'))) 'A20: nothing is written to the process''s folder'

    # what the default -Globals holds
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Tool, [ref]$tokens, [ref]$errors)
    $default = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Globals' } | ForEach-Object { $_.DefaultValue.SubExpression.Extent.Text }
    foreach ($name in 'UnitGUID', 'UnitName', 'GetTime', 'GetBuildInfo', 'IsInInstance', 'issecretvalue') {
        Check ($default -match "'$name'") "A21: the default -Globals lists $name"
    }
    $expected = 'UnitName', 'UnitLevel', 'UnitRace', 'UnitClass', 'UnitFactionGroup', 'UnitQuestTrivialLevelRange', 'UnitGUID', 'IsInInstance', 'GetBuildInfo', 'GetLocale', 'GetTime', 'CheckInteractDistance', 'CreateFromMixins', 'IsLeftAltKeyDown', 'IsLeftShiftKeyDown', 'IsModifierKeyDown', 'IsShiftKeyDown', 'issecretvalue'
    Equal (([regex]::Matches($default, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }) -join ',') ($expected -join ',') 'A21: and nothing else, in this order'

    # the real documentation, when this checkout has it
    $real = Get-ChildItem (Join-Path $PSScriptRoot 'api_docs') -Directory -Filter 'live-*' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
    if ($real) {
        $realFiles = @(Get-ChildItem $real.FullName -Filter *Documentation.lua | Sort-Object Name | ForEach-Object { $_.Name })
        $realOut = @(& $LuaExe $Reader $real.FullName $realFiles)
        $realRows = @($realOut | Where-Object { $_ -notmatch '^#' })
        Check ($realRows.Count -gt 5000) 'R9: the real documentation gives thousands of lines'
        Check (@($realRows | Where-Object { @($_ -split "`t").Count -ne 8 }).Count -eq 0) 'R9: every one has eight columns'
        $flagged = @($realRows | Where-Object { ($_ -split "`t")[7] -match 'Secret' }).Count
        Check ($flagged -gt 1000) 'R9: and a good many carry secrecy flags'
        Check (@($realOut | Where-Object { $_ -match '^# [^:]+: ' }).Count -le 40) 'R9: only the constants and widget-method files fail to load'
        $quest = @($realRows | Where-Object { $_ -match '^F\tQuestLog\tC_QuestLog\tIsWorldQuest\t' })
        Check ($quest.Count -eq 1 -and ($quest[0] -split "`t")[7] -match 'SecretArguments=') 'R9: C_QuestLog.IsWorldQuest carries its flag'
        $notLoaded = @($realOut | Where-Object { $_ -match '^# ([^:]+): ' } | ForEach-Object { ($_ -replace '^# ([^:]+): .*$', '$1') })
        foreach ($kind in 'AllowedWhenUntainted', 'AllowedWhenTainted', 'NotAllowed') {
            $raw = 0
            foreach ($f in $realFiles) {
                if ($notLoaded -contains $f) { continue }
                $raw += ([regex]::Matches([IO.File]::ReadAllText((Join-Path $real.FullName $f)), "\bSecretArguments = `"$kind`"")).Count
            }
            $listed = @($realRows | Where-Object { $_ -match "^F\t" -and (($_ -split "`t")[7] -split '; ') -ccontains "SecretArguments=$kind" }).Count
            Equal $listed $raw "R9: every function the files give SecretArguments=$kind is listed with it, and no other"
        }
    }
}
finally {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "$Passed checks passed, $Failed failed"
exit $(if ($Failed -eq 0) { 0 } else { 1 })
