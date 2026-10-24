param(
  [string]$WorkRoot = ''
)

$ErrorActionPreference = 'Stop'

# Offline regression for the scaffold variable-attribute contract:
#   renderer -> scaffold.json variables.attributes -> validator -> execution plan.
# No KV STUDIO is opened.

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$renderer = Join-Path $repo 'scripts\render_kv_mvp_scaffold_model.ps1'
$validator = Join-Path $repo 'scripts\scaffold_tools\validate_kv_mvp_scaffold.ps1'
$planner = Join-Path $repo 'scripts\workflow_tools\new_kv_mvp_execution_plan.ps1'
foreach ($path in @($renderer, $validator, $planner)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "script not found: $path" }
}

if (-not $WorkRoot) {
  $WorkRoot = Join-Path $env:TEMP ('kv-scaffold-attr-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

function New-Model([bool]$Conflict = $false) {
  $deviceRow = [ordered]@{ name = 'R_Flag'; data_type = 'BOOL'; device = 'R100' }
  if ($Conflict) { $deviceRow['initial_value'] = 'TRUE' }
  return [ordered]@{
    schema_version = 1
    project = [ordered]@{ name = 'AttrTest'; cpu_model = 'KV-X520'; local_program = 'Main' }
    task = [ordered]@{ summary = 'scaffold variable attribute contract' }
    modules = @(
      [ordered]@{
        name = 'Main'
        module_type = 0
        variables = [ordered]@{
          global = @(
            $deviceRow
            [ordered]@{ name = 'Init_Flag'; data_type = 'BOOL'; initial_value = 'TRUE' }
            [ordered]@{ name = 'Note_Flag'; data_type = 'BOOL'; comment = 'full attr' }
            [ordered]@{ name = 'Start'; data_type = 'BOOL' }
          )
          local = @([ordered]@{ name = 'State'; data_type = 'BOOL'; initial_value = 'FALSE' })
        }
        mnm = [ordered]@{ instructions = @('LD Start', 'OUT R_Flag', 'LD Init_Flag', 'OUT Note_Flag', 'END', 'ENDH') }
      }
    )
  }
}

function Write-Model([string]$Root, [bool]$Conflict = $false) {
  New-Item -ItemType Directory -Force -Path $Root | Out-Null
  (New-Model $Conflict) | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $Root 'scaffold.model.json') -Encoding UTF8
}

$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Case, [bool]$Pass, [string]$Detail) {
  $results.Add([pscustomobject]@{ case = $Case; pass = $Pass; detail = $Detail })
}

function Invoke-Script([string]$Path, [hashtable]$Arguments) {
  $global:LASTEXITCODE = $null
  & $Path @Arguments 2>$null | Out-Null
  if ($null -eq $LASTEXITCODE) { return 0 }
  return [int]$LASTEXITCODE
}

# 1. Render a model that declares device / initial value / comment rows.
$root = Join-Path $WorkRoot 'full'
Write-Model $root
$exit = Invoke-Script $renderer @{ ModelPath = (Join-Path $root 'scaffold.model.json'); ScaffoldRoot = $root }
$manifest = Get-Content -LiteralPath (Join-Path $root 'scaffold.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Add-Result 'render_full' ($exit -eq 0) "exit=$exit"
Add-Result 'manifest_attributes_full' ([string]$manifest.variables.attributes -eq 'full') "attributes=$($manifest.variables.attributes) rows=$($manifest.variables.attribute_row_count)"
Add-Result 'manifest_attribute_row_count' ([int]$manifest.variables.attribute_row_count -eq 3) "rows=$($manifest.variables.attribute_row_count)"

# 2. Validator accepts the full-attribute scaffold and reports the verified fields.
$valOut = Join-Path $WorkRoot 'val_full'
$exit = Invoke-Script $validator @{ ScaffoldRoot = $root; OutDir = $valOut }
$validation = Get-Content -LiteralPath (Join-Path $valOut 'scaffold_validation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$verified = @($validation.variable_write_verified_fields)
$hasAll = ($verified -contains 'device') -and ($verified -contains 'initial_value') -and ($verified -contains 'comment')
Add-Result 'validator_accepts_full' ($exit -eq 0 -and $validation.ok -eq $true) "exit=$exit ok=$($validation.ok) code=$($validation.error_code)"
Add-Result 'validator_reports_full_fields' $hasAll "fields=$($verified -join ',')"

# 3. A scaffold that does not declare the mode still fails closed on device rows.
$manifestPath = Join-Path $root 'scaffold.json'
$goodManifest = [IO.File]::ReadAllText($manifestPath)
$legacy = $goodManifest | ConvertFrom-Json
$legacy.variables.PSObject.Properties.Remove('attributes')
$legacy | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$exit = Invoke-Script $validator @{ ScaffoldRoot = $root; OutDir = (Join-Path $WorkRoot 'val_legacy') }
$legacyResult = Get-Content -LiteralPath (Join-Path $WorkRoot 'val_legacy\scaffold_validation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Add-Result 'validator_legacy_fails_closed' ($exit -eq 41 -and [string]$legacyResult.error_code -eq 'KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED') "exit=$exit code=$($legacyResult.error_code)"
[IO.File]::WriteAllText($manifestPath, $goodManifest, (New-Object Text.UTF8Encoding($true)))

# 4. A bogus attributes value is rejected before any UI input.
$bogus = $goodManifest | ConvertFrom-Json
$bogus.variables.attributes = 'bogus'
$bogus | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$exit = Invoke-Script $validator @{ ScaffoldRoot = $root; OutDir = (Join-Path $WorkRoot 'val_bogus') }
$bogusResult = Get-Content -LiteralPath (Join-Path $WorkRoot 'val_bogus\scaffold_validation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Add-Result 'validator_rejects_bogus_mode' ($exit -eq 41 -and [string]$bogusResult.error_code -eq 'KV_SCAFFOLD_VARIABLE_SCHEMA_INVALID') "exit=$exit code=$($bogusResult.error_code)"
[IO.File]::WriteAllText($manifestPath, $goodManifest, (New-Object Text.UTF8Encoding($true)))

# 5. device + initial_value in one row is rejected with the dedicated code.
$conflictRoot = Join-Path $WorkRoot 'conflict'
Write-Model $conflictRoot $true
$exit = Invoke-Script $renderer @{ ModelPath = (Join-Path $conflictRoot 'scaffold.model.json'); ScaffoldRoot = $conflictRoot }
$exit = Invoke-Script $validator @{ ScaffoldRoot = $conflictRoot; OutDir = (Join-Path $WorkRoot 'val_conflict') }
$conflictResult = Get-Content -LiteralPath (Join-Path $WorkRoot 'val_conflict\scaffold_validation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Add-Result 'validator_rejects_device_initial_conflict' ($exit -eq 41 -and [string]$conflictResult.error_code -eq 'KV_VARIABLE_DEVICE_INITIAL_VALUE_CONFLICT') "exit=$exit code=$($conflictResult.error_code)"

# 6. The execution plan carries -FullGlobalAttributes into every variable step.
$kvsExe = ''
foreach ($candidate in @('H:\Keyence\KVS12\KVS\Kvs.exe', 'C:\Program Files\KEYENCE\KV STUDIO\Kvs.exe')) {
  if (Test-Path -LiteralPath $candidate -PathType Leaf) { $kvsExe = $candidate; break }
}
$planRoot = Join-Path $WorkRoot 'plan'
$planArgs = @{
  Mode = 'new_project'
  ScaffoldRoot = $root
  OutRoot = (Join-Path $WorkRoot 'runs')
  OutDir = $planRoot
  ProjectName = 'AttrPlanTest'
}
if ($kvsExe) { $planArgs['KvsExe'] = $kvsExe }
$exit = Invoke-Script $planner $planArgs
$planPath = Join-Path $planRoot 'execution_plan.json'
if (Test-Path -LiteralPath $planPath -PathType Leaf) {
  $plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $variableSteps = @($plan.steps | Where-Object { $_.script_name -eq 'set_variables_guarded.ps1' })
  $withFlag = @($variableSteps | Where-Object { @($_.arguments) -contains '-FullGlobalAttributes' })
  Add-Result 'plan_includes_full_attribute_switch' ($exit -eq 0 -and $variableSteps.Count -gt 0 -and $withFlag.Count -eq $variableSteps.Count) "exit=$exit steps=$($variableSteps.Count) flagged=$($withFlag.Count)"
} else {
  Add-Result 'plan_includes_full_attribute_switch' $false 'execution_plan.json missing'
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
