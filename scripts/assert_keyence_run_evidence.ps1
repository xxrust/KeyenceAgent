param(
  [Parameter(Mandatory=$true)][string]$WorkflowResultPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$ScriptsRoot='',
  [switch]$AllowHistoricalCode
)
$ErrorActionPreference='Stop'
if (-not $ScriptsRoot) { $ScriptsRoot=Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'kv-studio-operator/scripts' }
. (Join-Path $ScriptsRoot 'workflow_tools/kv_step_evidence.ps1')
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
try {
  $result=Get-Content -Raw -Encoding UTF8 -LiteralPath $WorkflowResultPath | ConvertFrom-Json
  if ($result.ok -isnot [bool] -or -not $result.ok -or -not $result.run_id -or -not $result.code_sha256 -or -not $result.steps.Count) { throw 'KV_EVIDENCE_WORKFLOW_NOT_PROVEN' }
  $code=Get-Content -Raw -Encoding UTF8 -LiteralPath $result.code_fingerprint_path | ConvertFrom-Json
  if ($code.sha256 -ne $result.code_sha256) { throw 'KV_EVIDENCE_CODE_RECEIPT_MISMATCH' }
  $current=Get-KvCodeFingerprint $ScriptsRoot
  $currentCode=($current.sha256 -eq $code.sha256)
  if (-not $currentCode -and -not $AllowHistoricalCode) { throw 'KV_EVIDENCE_CODE_CHANGED' }
  if ((Get-FileHash -LiteralPath $result.execution_plan_path -Algorithm SHA256).Hash -ne $result.execution_plan_sha256) { throw 'KV_EVIDENCE_PLAN_CHANGED' }
  $artifacts=0
  foreach ($step in $result.steps) {
    if ($step.exit_code -ne 0 -or -not $step.receipt_path) { throw 'KV_EVIDENCE_STEP_NOT_PROVEN' }
    $receipt=Get-Content -Raw -Encoding UTF8 -LiteralPath $step.receipt_path | ConvertFrom-Json
    if ($receipt.ok -isnot [bool] -or -not $receipt.ok -or $receipt.run_id -ne $result.run_id -or $receipt.code_sha256 -ne $result.code_sha256 -or $receipt.step -ne $step.name) { throw 'KV_EVIDENCE_STEP_RECEIPT_MISMATCH' }
    if ($receipt.artifacts.Count -eq 0 -or $receipt.artifacts.Count -ne $step.artifacts.Count) { throw 'KV_EVIDENCE_ARTIFACTS_MISSING' }
    foreach ($file in $receipt.artifacts) {
      if (-not (Test-Path -LiteralPath $file.path -PathType Leaf) -or (Get-FileHash -LiteralPath $file.path -Algorithm SHA256).Hash -ne $file.sha256) { throw "KV_EVIDENCE_ARTIFACT_CHANGED: $($file.path)" }
      $declared=@($step.artifacts | Where-Object { $_.path -eq $file.path -and $_.sha256 -eq $file.sha256 })
      if ($declared.Count -ne 1) { throw 'KV_EVIDENCE_ARTIFACT_RECEIPT_MISMATCH' }
      $artifacts++
    }
  }
  $events=@(Get-Content -LiteralPath $result.run_log_path -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
  if (@($events | Where-Object { $_.type -eq 'workflow_succeeded' -and $_.run_id -eq $result.run_id }).Count -ne 1) { throw 'KV_EVIDENCE_SUCCESS_LOG_MISSING' }
  $atomic=@($events | Where-Object { $_.type -eq 'atomic_action' })
  if (@($atomic | Where-Object { $_.elapsed_ms -ge 10000 -or $_.ok -isnot [bool] -or -not $_.ok }).Count) { throw 'KV_EVIDENCE_ATOMIC_BUDGET_FAILED' }
  $payload=@{ok=$true;workflow_result_path=$WorkflowResultPath;run_id=$result.run_id;current_code=$currentCode;verified_artifacts=$artifacts;max_atomic_ms=($atomic | Measure-Object elapsed_ms -Maximum).Maximum;scope='provenance, successful step contracts and timings; semantic assertions remain those of the workflow'}
} catch { $payload=@{ok=$false;error_code=($_.Exception.Message -split ':',2)[0];message=$_.Exception.Message;workflow_result_path=$WorkflowResultPath} }
$payload | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $OutDir 'evidence_gate.json') -Encoding UTF8
$payload | ConvertTo-Json -Depth 7
if (-not $payload.ok) { exit 1 }
