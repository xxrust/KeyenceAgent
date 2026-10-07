param([Parameter(Mandatory=$true)][string]$PlanPath,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$scripts=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
. (Join-Path $scripts 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $scripts 'workflow_tools/kv_step_evidence.ps1')
. (Join-Path $scripts 'workflow_tools/kv_plan_preflight.ps1')
$original=Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8
$null=New-Item -ItemType Directory -Force -Path $OutDir
$rows=@()
foreach($case in @('valid','remove_compile','remove_arguments_readback','remove_verify','replace_body_input','disable_persistence','disable_compile_requirement','replace_contract','wrong_argument_direction_route')){
  $plan=$original|ConvertFrom-Json
  if($case -eq 'remove_arguments_readback' -and @($plan.steps|Where-Object name -eq 'arguments_readback').Count -eq 0){continue}
  if($case -eq 'wrong_argument_direction_route' -and @($plan.steps|Where-Object name -eq 'arguments').Count -eq 0){continue}
  if($case -like 'remove_*'){$name=$case.Substring(7);$plan.steps=@($plan.steps|Where-Object name -ne $name)}
  elseif($case -eq 'replace_body_input'){($plan.steps|Where-Object name -eq 'import').parameters.MnmPath=$PlanPath}
  elseif($case -eq 'disable_persistence'){($plan.steps|Where-Object name -eq 'locals').parameters.AuditPersistence=$false}
  elseif($case -eq 'disable_compile_requirement'){$plan.require_compile_result=$false}
  elseif($case -eq 'replace_contract'){($plan.steps|Where-Object name -eq 'verify').parameters.ContractPath=$PlanPath}
  elseif($case -eq 'wrong_argument_direction_route'){($plan.steps|Where-Object name -eq 'arguments_readback').parameters.SnapshotOnly=$false}
  $failure='';try{$null=Test-KvExecutionPlanPreflight $plan $scripts}catch{$failure=$_.Exception.Message}
  if(([string]::IsNullOrEmpty($failure)) -ne ($case -eq 'valid')){throw "Unexpected plan result: $case error=$failure"}
  $rows+=@{case=$case;ok=$true;observed_error=$failure}
}
@{ok=$true;ui_started=$false;tests=$rows}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($rows.Count) ST complete plan contract cases"
