# Shared plan construction only. This library never sends desktop input.
function New-KvWorkflowPlan {
  param([string]$ScriptsRoot,[string]$Operation,[string]$ProjectPath,[string]$OutDir,[int]$TimeoutSeconds=120,[string]$ResultName='workflow_result.json',[switch]$NewProject)
  $OutDir=[IO.Path]::GetFullPath($OutDir)
  $ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
  if ($NewProject) {
    if (Test-Path -LiteralPath $ProjectPath) { throw "KV_TARGET_PROJECT_ALREADY_EXISTS: $ProjectPath" }
  } elseif (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "KV_PROJECT_FILE_MISSING: $ProjectPath" }
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $plan=[ordered]@{
    ok=$true;schema_version=2;operation=$Operation;project_path=$ProjectPath;project_name=[IO.Path]::GetFileNameWithoutExtension($ProjectPath)
    run_root=$OutDir;artifact_root=(Join-Path $OutDir 'artifacts');result_path=(Join-Path $OutDir $ResultName)
    timeout_seconds=$TimeoutSeconds;require_compile_result=$false;steps=[Collections.Generic.List[object]]::new()
  }
  foreach ($gate in @('ui_guard_usage','agent_boundary')) {
    $dest=Join-Path $plan.artifact_root $gate
    $plan.steps.Add(@{name="assert_$gate";kind='gate';script_name="gates/assert_kv_mvp_$gate.ps1";classes=@('gate');out_dir=$dest;parameters=@{ScriptsRoot=$ScriptsRoot;OutDir=$dest}})
  }
  return $plan
}

function Add-KvWorkflowStep {
  param([System.Collections.IDictionary]$Plan,[string]$Name,[string]$Script,[hashtable]$Parameters,[string]$Class='runner_child_approved',[string]$OutDir='')
  if (-not $OutDir) { $OutDir=Join-Path $Plan.artifact_root $Name }
  $Plan.steps.Add(@{name=$Name;kind=$(if($Class -eq 'runner_child_approved'){'runner_child'}else{'tool'});script_name=$Script;classes=@($Class);out_dir=$OutDir;parameters=$Parameters})
}

function Submit-KvWorkflowPlan {
  param([System.Collections.IDictionary]$Plan,[string]$ScriptsRoot,[switch]$PlanOnly)
  $path=Join-Path $Plan.run_root 'execution_plan.json'
  $Plan | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $path -Encoding UTF8
  . (Join-Path $ScriptsRoot 'workflow_tools/kv_step_evidence.ps1')
  . (Join-Path $ScriptsRoot 'workflow_tools/kv_plan_preflight.ps1')
  $preflight=Test-KvExecutionPlanPreflight -Plan (Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json) -ScriptsRoot $ScriptsRoot
  @{ok=$true;status='planned';inputs=@($preflight.inputs);execution_plan_sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Plan.run_root 'plan_preflight_result.json') -Encoding UTF8
  if ($PlanOnly) { return }
  $executor=Resolve-KvStudioOperatorScriptPath -ScriptRoot $ScriptsRoot -Name 'workflow_tools/invoke_kv_flat_execution_plan.ps1' -Classes workflow_tool
  & powershell -NoProfile -ExecutionPolicy Bypass -File $executor -PlanPath $path -TimeoutSeconds $Plan.timeout_seconds
  if ($LASTEXITCODE -ne 0) { throw "KV_WORKFLOW_FAILED: inspect $($Plan.result_path)" }
}
