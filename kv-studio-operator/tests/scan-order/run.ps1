param(
  [string]$WorkRoot = ''
)

$ErrorActionPreference = 'Stop'

# Offline regression for assert_kv_scan_order.ps1.
# No KV STUDIO and no project files: synthetic inventories keep the cases fast and
# deterministic. Case 8 uses a real inventory when one is available.

$tool = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts\workflow_tools\assert_kv_scan_order.ps1'))
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "tool not found: $tool" }

if (-not $WorkRoot) {
  $WorkRoot = Join-Path $env:TEMP ('kv-scan-order-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

function New-TestModule([string]$Name, [int]$Order, [string]$Category = 'scan') {
  return [ordered]@{
    module_name = $Name
    execution_order = $Order
    category = $Category
    tree_text = "$Name [$Order]"
  }
}

function Write-Inventory([string]$Path, [object[]]$Modules) {
  $payload = [ordered]@{
    ok = $true
    schema_version = 1
    project_path = 'synthetic'
    program_modules = @($Modules)
  }
  $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$expectedModules = @(
  New-TestModule 'IO_In' 1
  New-TestModule 'Init' 2
  New-TestModule 'ST00_Demo' 3
  New-TestModule 'Status' 4
  New-TestModule 'Alarm' 5
  New-TestModule 'VersionInfo' 6 'standby'
)

$expectedPath = Join-Path $WorkRoot 'expected_inventory.json'
Write-Inventory $expectedPath $expectedModules

$results = New-Object System.Collections.Generic.List[object]

function Invoke-ScanOrderCase {
  param(
    [string]$Name,
    [string[]]$Arguments,
    [bool]$ExpectOk,
    [string]$ExpectCode = ''
  )
  $outDir = Join-Path $WorkRoot ('case_' + $Name)
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  # Array splatting passes every element positionally, so build a parameter table.
  $params = @{ OutDir = $outDir }
  for ($i = 0; $i -lt $Arguments.Count; $i++) {
    $token = [string]$Arguments[$i]
    if (-not $token.StartsWith('-')) { throw "bad test argument at index $i : $token" }
    $key = $token.Substring(1)
    if (($i + 1) -lt $Arguments.Count -and -not ([string]$Arguments[$i + 1]).StartsWith('-')) {
      $params[$key] = [string]$Arguments[$i + 1]
      $i++
    } else {
      $params[$key] = $true
    }
  }
  $global:LASTEXITCODE = $null
  & $tool @params 2>$null | Out-Null
  # A successful script does not call exit, so LASTEXITCODE stays null.
  $exit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
  $resultPath = Join-Path $outDir 'scan_order_verification.json'
  if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    $results.Add([pscustomobject]@{ case = $Name; pass = $false; detail = 'result json missing'; exit = $exit })
    return
  }
  $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $pass = $true
  $detail = ''
  if ($ExpectOk) {
    if ($exit -ne 0 -or $result.ok -ne $true) { $pass = $false; $detail = "expected ok, exit=$exit code=$($result.error_code)" }
  } else {
    if ($exit -eq 0 -or $result.ok -ne $false) { $pass = $false; $detail = "expected failure, exit=$exit ok=$($result.ok)" }
    elseif ($ExpectCode -and [string]$result.error_code -ne $ExpectCode) { $pass = $false; $detail = "expected $ExpectCode, got $($result.error_code)" }
  }
  $results.Add([pscustomobject]@{ case = $Name; pass = $pass; detail = $detail; exit = $exit })
}

# 1. identical schedule
Write-Inventory (Join-Path $WorkRoot 'actual_same.json') $expectedModules
Invoke-ScanOrderCase -Name 'same' -Arguments @('-ExpectedInventory', $expectedPath, '-ActualInventory', (Join-Path $WorkRoot 'actual_same.json')) -ExpectOk $true

# 2. two modules swapped -> relative order drift
$swapped = @(
  New-TestModule 'IO_In' 1
  New-TestModule 'ST00_Demo' 2
  New-TestModule 'Init' 3
  New-TestModule 'Status' 4
  New-TestModule 'Alarm' 5
  New-TestModule 'VersionInfo' 6 'standby'
)
Write-Inventory (Join-Path $WorkRoot 'actual_swapped.json') $swapped
Invoke-ScanOrderCase -Name 'order_drift' -Arguments @('-ExpectedInventory', $expectedPath, '-ActualInventory', (Join-Path $WorkRoot 'actual_swapped.json')) -ExpectOk $false -ExpectCode 'KV_SCAN_ORDER_MISMATCH'

# 3. one module missing
$missing = @($expectedModules | Where-Object { $_.module_name -ne 'Status' })
Write-Inventory (Join-Path $WorkRoot 'actual_missing.json') $missing
Invoke-ScanOrderCase -Name 'missing' -Arguments @('-ExpectedInventory', $expectedPath, '-ActualInventory', (Join-Path $WorkRoot 'actual_missing.json')) -ExpectOk $false -ExpectCode 'KV_SCAN_ORDER_MODULE_MISSING'

# 4. unexpected module fails, then is accepted with -AllowExtraModules
$extra = @($expectedModules) + @(New-TestModule 'ExtraModule' 7)
Write-Inventory (Join-Path $WorkRoot 'actual_extra.json') $extra
Invoke-ScanOrderCase -Name 'extra' -Arguments @('-ExpectedInventory', $expectedPath, '-ActualInventory', (Join-Path $WorkRoot 'actual_extra.json')) -ExpectOk $false -ExpectCode 'KV_SCAN_ORDER_MODULE_EXTRA'
Invoke-ScanOrderCase -Name 'extra_allowed' -Arguments @('-ExpectedInventory', $expectedPath, '-ActualInventory', (Join-Path $WorkRoot 'actual_extra.json'), '-AllowExtraModules') -ExpectOk $true

# 5. numbers shifted by +10: relative order still fine, exact numbers fail only when required
$shifted = @()
foreach ($m in $expectedModules) {
  $shifted += New-TestModule $m.module_name ([int]$m.execution_order + 10) ([string]$m.category)
}
Write-Inventory (Join-Path $WorkRoot 'actual_shifted.json') $shifted
Invoke-ScanOrderCase -Name 'shifted_relative_ok' -Arguments @('-ExpectedInventory', $expectedPath, '-ActualInventory', (Join-Path $WorkRoot 'actual_shifted.json')) -ExpectOk $true
Invoke-ScanOrderCase -Name 'shifted_exact_fail' -Arguments @('-ExpectedInventory', $expectedPath, '-ActualInventory', (Join-Path $WorkRoot 'actual_shifted.json'), '-RequireExactNumbers') -ExpectOk $false -ExpectCode 'KV_SCAN_ORDER_NUMBER_MISMATCH'

# 6. duplicate module name is rejected before any order comparison
$duplicate = @($expectedModules) + @(New-TestModule 'Init' 7)
Write-Inventory (Join-Path $WorkRoot 'actual_duplicate.json') $duplicate
Invoke-ScanOrderCase -Name 'duplicate' -Arguments @('-ExpectedInventory', $expectedPath, '-ActualInventory', (Join-Path $WorkRoot 'actual_duplicate.json')) -ExpectOk $false -ExpectCode 'KV_SCAN_ORDER_DUPLICATE_MODULE'

# 7. scaffold mode: only module_type 0 entries participate in the scan schedule
$scaffold = [ordered]@{
  schema_version = 2
  mnm_files = @(
    [ordered]@{ path = 'modules/Main/Main.mnm'; module_name = 'Main'; module_type = 0; category = 'scan' },
    [ordered]@{ path = 'modules/Worker/Worker.mnm'; module_name = 'Worker'; module_type = 0; category = 'scan' },
    [ordered]@{ path = 'modules/Reusable/Reusable.mnm'; module_name = 'Reusable'; module_type = 2; category = 'function_block' },
    [ordered]@{ path = 'modules/Alarm/Alarm.mnm'; module_name = 'Alarm'; module_type = 0; category = 'scan' }
  )
}
$scaffoldPath = Join-Path $WorkRoot 'scaffold.json'
$scaffold | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $scaffoldPath -Encoding UTF8
Write-Inventory (Join-Path $WorkRoot 'actual_scaffold_ok.json') @(
  New-TestModule 'Main' 1
  New-TestModule 'Worker' 2
  New-TestModule 'Alarm' 3
)
Invoke-ScanOrderCase -Name 'scaffold_ok' -Arguments @('-ScaffoldPath', $scaffoldPath, '-ActualInventory', (Join-Path $WorkRoot 'actual_scaffold_ok.json'), '-RequireExactNumbers') -ExpectOk $true
Write-Inventory (Join-Path $WorkRoot 'actual_scaffold_bad.json') @(
  New-TestModule 'Worker' 1
  New-TestModule 'Main' 2
  New-TestModule 'Alarm' 3
)
Invoke-ScanOrderCase -Name 'scaffold_order_fail' -Arguments @('-ScaffoldPath', $scaffoldPath, '-ActualInventory', (Join-Path $WorkRoot 'actual_scaffold_bad.json')) -ExpectOk $false -ExpectCode 'KV_SCAN_ORDER_MISMATCH'

# 8. optional real sample inventory (24 saved modules)
$realInventory = 'C:\kvrun\inv_now\project_inventory.json'
if (Test-Path -LiteralPath $realInventory -PathType Leaf) {
  Invoke-ScanOrderCase -Name 'real_sample_self' -Arguments @('-ExpectedInventory', $realInventory, '-ActualInventory', $realInventory) -ExpectOk $true
}

$failed = @($results | Where-Object { -not $_.pass })
$results | Format-Table -AutoSize | Out-String -Width 120 | Write-Output
Write-Output ''
Write-Output ("Cases: {0}  Passed: {1}  Failed: {2}" -f $results.Count, ($results.Count - $failed.Count), $failed.Count)
Write-Output "WorkRoot: $WorkRoot"
if ($failed.Count -gt 0) {
  foreach ($f in $failed) { Write-Output ("FAIL {0}: {1}" -f $f.case, $f.detail) }
  exit 1
}
exit 0
