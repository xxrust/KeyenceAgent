param(
  [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'

# Offline regression for the variable write-capability contract.
# The UI persistence test is separate (it needs KV STUDIO); this test pins the
# fail-closed rules that protect the paste payload before any UI input.

if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$lib = Join-Path $RepoRoot 'scripts\kv_variable_definition_lib.ps1'
if (-not (Test-Path -LiteralPath $lib -PathType Leaf)) { throw "lib not found: $lib" }
. $lib

function New-Row {
  param([hashtable]$Overrides = @{})
  $row = @{
    scope = 'global'; owner_program = ''; name = 'TestVar'; data_type = 'INT'
    device = ''; initial_value = ''; retain = ''; constant = ''
    group_name = ''; assignment_target = ''; opc_ua = ''; file_export = ''
    comment = ''; status = 'declared'; evidence = ''
  }
  foreach ($key in $Overrides.Keys) { $row[$key] = $Overrides[$key] }
  return [pscustomobject]$row
}

$results = New-Object System.Collections.Generic.List[object]

function Invoke-Case {
  param(
    [string]$Name,
    [hashtable]$Overrides,
    [string]$Scope = 'global',
    [switch]$AllowGlobalAttributes,
    [switch]$AllowDefaultInitialValues,
    [string]$ExpectCode = '',
    [string[]]$ExpectFields = @()
  )
  $row = New-Row $Overrides
  $row.scope = $Scope
  $errors = @(Get-KvVariableWriteCapabilityErrors -Rows @($row) -Scope $Scope -AllowGlobalAttributes:$AllowGlobalAttributes -AllowDefaultInitialValues:$AllowDefaultInitialValues)
  $pass = $true
  $detail = ''
  if ($ExpectCode) {
    if ($errors.Count -eq 0) { $pass = $false; $detail = "expected $ExpectCode, got ALLOW" }
    elseif ([string]$errors[0].code -ne $ExpectCode) { $pass = $false; $detail = "expected $ExpectCode, got $($errors[0].code)" }
    elseif ($ExpectFields.Count -gt 0) {
      $actual = @($errors[0].fields)
      $missing = @($ExpectFields | Where-Object { $actual -notcontains $_ })
      if ($missing.Count -gt 0) { $pass = $false; $detail = "missing fields: $($missing -join ',') actual: $($actual -join ',')" }
    }
  } else {
    if ($errors.Count -gt 0) { $pass = $false; $detail = "expected ALLOW, got $($errors[0].code) fields=$($errors[0].fields -join ',')" }
  }
  $results.Add([pscustomobject]@{ case = $Name; pass = $pass; detail = $detail })
}

# Baseline: only name/type is proven.
Invoke-Case -Name 'default_device_rejected' -Overrides @{ device = 'DM100' } -ExpectCode 'KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED' -ExpectFields @('device')
Invoke-Case -Name 'default_initial_rejected' -Overrides @{ initial_value = '5' } -ExpectCode 'KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED' -ExpectFields @('initial_value')
Invoke-Case -Name 'default_name_type_allowed' -Overrides @{}

# Opt-in global attributes: device, initial value and comment become writable.
Invoke-Case -Name 'global_device_allowed' -Overrides @{ device = 'DM100' } -AllowGlobalAttributes
Invoke-Case -Name 'global_initial_allowed' -Overrides @{ initial_value = '5' } -AllowGlobalAttributes
Invoke-Case -Name 'global_comment_allowed' -Overrides @{ comment = 'note' } -AllowGlobalAttributes
Invoke-Case -Name 'global_device_initial_conflict' -Overrides @{ device = 'DM100'; initial_value = '5' } -AllowGlobalAttributes -ExpectCode 'KV_VARIABLE_DEVICE_INITIAL_VALUE_CONFLICT' -ExpectFields @('initial_value')

# Unsupported attributes stay fail-closed even in the opt-in mode.
Invoke-Case -Name 'global_retain_still_rejected' -Overrides @{ retain = 'True' } -AllowGlobalAttributes -ExpectCode 'KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED' -ExpectFields @('retain')
Invoke-Case -Name 'global_constant_still_rejected' -Overrides @{ constant = 'True' } -AllowGlobalAttributes -ExpectCode 'KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED' -ExpectFields @('constant')
Invoke-Case -Name 'global_group_still_rejected' -Overrides @{ group_name = 'G1' } -AllowGlobalAttributes -ExpectCode 'KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED' -ExpectFields @('group_name')

# Locals do not get the global attribute route.
Invoke-Case -Name 'local_device_still_rejected' -Overrides @{ device = 'DM100' } -Scope 'local' -AllowGlobalAttributes -ExpectCode 'KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED' -ExpectFields @('device')

# New-project default handling is unchanged.
Invoke-Case -Name 'default_initial_zero_allowed_for_new_project' -Overrides @{ initial_value = '0' } -AllowDefaultInitialValues
Invoke-Case -Name 'default_initial_nonzero_rejected_for_new_project' -Overrides @{ initial_value = '5' } -AllowDefaultInitialValues -ExpectCode 'KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED' -ExpectFields @('initial_value')

$failed = @($results | Where-Object { -not $_.pass })
$results | Format-Table -AutoSize | Out-String -Width 140 | Write-Output
Write-Output ''
Write-Output ("Cases: {0}  Passed: {1}  Failed: {2}" -f $results.Count, ($results.Count - $failed.Count), $failed.Count)
if ($failed.Count -gt 0) {
  foreach ($f in $failed) { Write-Output ("FAIL {0}: {1}" -f $f.case, $f.detail) }
  exit 1
}
exit 0
