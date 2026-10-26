param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'

# Offline regression for get_kv_module_completion.ps1.
# Synthetic plan + step receipts prove the gate: an imported module without a
# variables result is incomplete, and the same plan turns complete once the
# variables result exists.

$tool = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts\workflow_tools\get_kv_module_completion.ps1'))
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "tool not found: $tool" }

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-module-completion-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$artifacts = Join-Path $WorkRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

$planPath = Join-Path $WorkRoot 'execution_plan.json'
[ordered]@{
  plan_id = 'module-completion-fixture'
  artifact_root = $artifacts
  variable_sets = @(
    [ordered]@{ module_name = 'ST01'; category = 'scan' },
    [ordered]@{ module_name = 'ST02'; category = 'scan' }
  )
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $planPath -Encoding UTF8

function Write-Json([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
}

Write-Json (Join-Path $artifacts 'import_mnm_1\step_receipt.json') ([ordered]@{ ok = $true; step = 'import_mnm_1' })
Write-Json (Join-Path $artifacts 'import_mnm_2\step_receipt.json') ([ordered]@{ ok = $true; step = 'import_mnm_2' })
Write-Json (Join-Path $artifacts 'set_variables\module_01_ST01\set_variables_result.json') ([ordered]@{ ok = $true; module = 'ST01' })

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}

$outDirIncomplete = Join-Path $WorkRoot 'out_incomplete'
& $tool -PlanPath $planPath -ArtifactsRoot $artifacts -OutDir $outDirIncomplete -AllowIncomplete | Out-Null
$exitIncomplete = $LASTEXITCODE
$incompleteReport = Get-Content -LiteralPath (Join-Path $outDirIncomplete 'module_completion.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Add-Case 'allow-incomplete exits 0' ($exitIncomplete -eq 0) "exit=$exitIncomplete"
Add-Case 'one incomplete module' ([int]$incompleteReport.incomplete_count -eq 1) "incomplete=$($incompleteReport.incomplete_count)"
Add-Case 'incomplete module is ST02' ([string]$incompleteReport.incomplete[0].module -eq 'ST02') ([string]$incompleteReport.incomplete[0].module)
Add-Case 'incomplete reason mentions variables' (@($incompleteReport.incomplete[0].reasons) -contains 'variables_missing_or_failed') (@($incompleteReport.incomplete[0].reasons) -join ',')
Add-Case 'complete modules count 1' ([int]$incompleteReport.complete_modules -eq 1) "complete=$($incompleteReport.complete_modules)"

$outDirGate = Join-Path $WorkRoot 'out_gate'
& $tool -PlanPath $planPath -ArtifactsRoot $artifacts -OutDir $outDirGate | Out-Null
$exitGate = $LASTEXITCODE
Add-Case 'gate without -AllowIncomplete exits 41' ($exitGate -eq 41) "exit=$exitGate"

Write-Json (Join-Path $artifacts 'set_variables\module_02_ST02\set_variables_result.json') ([ordered]@{ ok = $true; module = 'ST02' })
$outDirComplete = Join-Path $WorkRoot 'out_complete'
& $tool -PlanPath $planPath -ArtifactsRoot $artifacts -OutDir $outDirComplete | Out-Null
$exitComplete = $LASTEXITCODE
$completeReport = Get-Content -LiteralPath (Join-Path $outDirComplete 'module_completion.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Add-Case 'complete plan exits 0' ($exitComplete -eq 0) "exit=$exitComplete"
Add-Case 'complete plan ok true' ([bool]$completeReport.ok) "ok=$($completeReport.ok)"
Add-Case 'complete modules 2/2' (([int]$completeReport.complete_modules -eq 2) -and ([int]$completeReport.total_modules -eq 2)) "$($completeReport.complete_modules)/$($completeReport.total_modules)"

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'module-completion'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0
