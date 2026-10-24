param(
  [string]$WorkRoot = ''
)

$ErrorActionPreference = 'Stop'

# Offline regression for assert_kv_library_dependencies.ps1.
# The synthetic tree mirrors the saved WsTreeEnv.xml shape:
# 功能块 > UniversalLibrary > <category> > <vendor> > <FB name>:<comment>

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tool = Join-Path $repo 'scripts\workflow_tools\assert_kv_library_dependencies.ps1'
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "tool not found: $tool" }

if (-not $WorkRoot) {
  $WorkRoot = Join-Path $env:TEMP ('kv-library-dep-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$funcBlock = -join ([char[]](0x529F, 0x80FD, 0x5757))
$universal = 'UniversalLibrary'

function New-NodeXml([string]$Name, [string]$InnerChildren) {
  return @"
<Child><value.first>$Name</value.first><value.second><Expanded>0</Expanded>$InnerChildren</value.second></Child>
"@
}

function New-FbXml([string]$Name) {
  $child = New-NodeXml 'Start FB' ''
  return New-NodeXml $Name $child
}

function Write-Tree([string]$Path, [bool]$WithLibrary) {
  $motor = if ($WithLibrary) {
    $vendor = New-NodeXml 'Inovance_SV630N_V100' ((New-FbXml 'MC_ModelCheck_INOVA:model check') + (New-FbXml 'MC_ParameterInitialize_INOVA:init'))
    New-NodeXml 'Motor' $vendor
  } else { '' }
  $library = if ($WithLibrary) { New-NodeXml $universal $motor } else { '' }
  $main = New-NodeXml 'Main [1]' ''
  $xml = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`r`n<Root><Expanded>0</Expanded><Child><value.first>$funcBlock</value.first><value.second><Expanded>1</Expanded>$library$main</value.second></Child></Root>"
  [IO.File]::WriteAllText($Path, $xml, (New-Object Text.UTF8Encoding($false)))
}

$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Case, [bool]$Pass, [string]$Detail) {
  $results.Add([pscustomobject]@{ case = $Case; pass = $Pass; detail = $Detail })
}

function Invoke-Case([string]$Name, [string]$ProjectPath, [string[]]$Library, [string[]]$Prefix, [bool]$ExpectOk, [string]$ExpectCode = '') {
  $outDir = Join-Path $WorkRoot ('case_' + $Name)
  $params = @{ ProjectPath = $ProjectPath; OutDir = $outDir }
  if ($Library.Count -gt 0) { $params['RequiredLibrary'] = $Library }
  if ($Prefix.Count -gt 0) { $params['RequiredFbNamePrefix'] = $Prefix }
  $global:LASTEXITCODE = $null
  & $tool @params 2>$null | Out-Null
  $exit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
  $resultPath = Join-Path $outDir 'library_dependency_result.json'
  if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { Add-Result $Name $false 'result json missing'; return }
  $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($ExpectOk) {
    Add-Result $Name ($exit -eq 0 -and $result.ok -eq $true) "exit=$exit ok=$($result.ok) code=$($result.error_code) fbs=$($result.universal_library_fb_count)"
  } else {
    Add-Result $Name ($exit -eq 1 -and [string]$result.error_code -eq $ExpectCode) "exit=$exit code=$($result.error_code) expected=$ExpectCode"
  }
}

# 1. Library present with the expected vendor and FB prefix.
$withLibrary = Join-Path $WorkRoot 'with_library'; New-Item -ItemType Directory -Force -Path $withLibrary | Out-Null
Write-Tree (Join-Path $withLibrary 'WsTreeEnv.xml') $true
Invoke-Case 'present' $withLibrary @('Inovance_SV630N_V100') @('MC_') $true

# 2. Unknown vendor.
Invoke-Case 'vendor_missing' $withLibrary @('YAKO_MS_MINI_E_V100') @() $false 'KV_LIBRARY_VENDOR_MISSING'

# 3. Known vendor but no FB with the requested prefix.
Invoke-Case 'prefix_missing' $withLibrary @() @('ZZ_') $false 'KV_LIBRARY_FB_MISSING'

# 4. No UniversalLibrary tree at all.
$noLibrary = Join-Path $WorkRoot 'no_library'; New-Item -ItemType Directory -Force -Path $noLibrary | Out-Null
Write-Tree (Join-Path $noLibrary 'WsTreeEnv.xml') $false
Invoke-Case 'tree_missing' $noLibrary @('Inovance_SV630N_V100') @() $false 'KV_LIBRARY_TREE_MISSING'

# 5. No requirements: a project without a library is still valid.
Invoke-Case 'no_requirements' $noLibrary @() @() $true

# 6. Optional real projects from the live experiment.
$liveProject = 'C:\kvrun\ultest\Projects\ULTest'
if (Test-Path -LiteralPath (Join-Path $liveProject 'WsTreeEnv.xml') -PathType Leaf) {
  Invoke-Case 'live_ultest' $liveProject @('Inovance_SV630N_V100') @('MC_') $true
}
$freshProject = 'H:\kvOp\plc_scaffold_audit_20260906\ui_scope_fixed\ScopeReuseRegressionFixed\Projects\ScopeReuseRegressionFixed'
if (Test-Path -LiteralPath (Join-Path $freshProject 'WsTreeEnv.xml') -PathType Leaf) {
  Invoke-Case 'live_fresh_project' $freshProject @('Inovance_SV630N_V100') @() $false 'KV_LIBRARY_TREE_MISSING'
}

$failed = @($results | Where-Object { -not $_.pass })
$results | Format-Table -AutoSize | Out-String -Width 140 | Write-Output
Write-Output ''
Write-Output ("Cases: {0}  Passed: {1}  Failed: {2}" -f $results.Count, ($results.Count - $failed.Count), $failed.Count)
Write-Output "WorkRoot: $WorkRoot"
if ($failed.Count -gt 0) {
  foreach ($f in $failed) { Write-Output ("FAIL {0}: {1}" -f $f.case, $f.detail) }
  exit 1
}
exit 0
