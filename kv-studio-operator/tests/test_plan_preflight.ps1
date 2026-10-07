param(
  [Parameter(Mandatory=$true)][string]$FixturePlanPath,
  [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference='Stop'
$scriptsRoot=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
. (Join-Path $scriptsRoot 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $scriptsRoot 'workflow_tools/kv_step_evidence.ps1')
. (Join-Path $scriptsRoot 'workflow_tools/kv_plan_preflight.ps1')
$planJson=Get-Content -Raw -Encoding UTF8 -LiteralPath $FixturePlanPath
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$results=[Collections.Generic.List[object]]::new()
function Expect-Rejection([string]$Name,[scriptblock]$Mutation,[string]$ErrorCode) {
  $plan=$planJson | ConvertFrom-Json
  & $Mutation $plan
  $caught=''
  try { $null=Test-KvExecutionPlanPreflight $plan $scriptsRoot } catch { $caught=$_.Exception.Message }
  if (-not $caught.StartsWith($ErrorCode)) { throw "Test $Name expected $ErrorCode, got: $caught" }
  $results.Add(@{name=$Name;ok=$true;error_code=$ErrorCode})
}
$baseline=Test-KvExecutionPlanPreflight ($planJson | ConvertFrom-Json) $scriptsRoot
$results.Add(@{name='valid_plan';ok=$true})
Expect-Rejection 'missing_gate' {param($p) $p.steps=@($p.steps | Select-Object -Skip 1)} 'KV_PLAN_STEPS_REQUIRED'
Expect-Rejection 'wrong_gate_order' {param($p) $a=$p.steps[0];$p.steps[0]=$p.steps[1];$p.steps[1]=$a} 'KV_PLAN_REQUIRED_GATE_ORDER'
Expect-Rejection 'pending_class' {param($p) $p.steps[2].classes=@('runner_child_pending')} 'KV_PLAN_STEP_CLASS_INVALID'
Expect-Rejection 'unknown_parameter' {param($p) $p.steps[2].arguments+=@('-UnknownInput','x')} 'KV_PLAN_PARAMETER_UNKNOWN'
Expect-Rejection 'missing_mandatory_parameter' {param($p) $p.steps[2].arguments=@('-OutDir',$p.steps[2].out_dir)} 'KV_PLAN_PARAMETER_REQUIRED'
Expect-Rejection 'duplicate_parameter' {param($p) $p.steps[2].arguments+=@('-OutDir',$p.steps[2].out_dir)} 'KV_PLAN_PARAMETER_DUPLICATE'
Expect-Rejection 'project_mismatch' {param($p) $p.steps[2].arguments[1]='H:\other_project.kpr'} 'KV_PLAN_STEP_PROJECT_MISMATCH'
Expect-Rejection 'out_dir_mismatch' {param($p) $p.steps[2].out_dir=Join-Path $p.run_root 'wrong'} 'KV_PLAN_STEP_OUT_DIR_MISMATCH'
Expect-Rejection 'gate_scope_narrowed' {param($p) $p.steps[0].arguments+=@('-ScriptNames','runner_children/set_fb_arguments_guarded.ps1')} 'KV_PLAN_GATE_SCOPE_RESTRICTED'
Expect-Rejection 'string_compile_flag' {param($p) $p.require_compile_result='false'} 'KV_PLAN_COMPILE_FLAG_INVALID'
Expect-Rejection 'typed_boolean_mismatch' {
  param($p)
  $s=$p.steps[2]
  $s | Add-Member -NotePropertyName parameters -NotePropertyValue ([pscustomobject]@{ProjectPath=$p.project_path;FbModuleName='FB_Cylinder';OutDir=$s.out_dir;SnapshotOnly='false'})
  $s.arguments=@()
} 'KV_PLAN_PARAMETER_TYPE_INVALID'
Expect-Rejection 'typed_integer_mismatch' {
  param($p)
  $s=$p.steps[2]
  $s.script_name='runner_children/compile_and_copy_result_bounded.ps1'
  $s | Add-Member -NotePropertyName parameters -NotePropertyValue ([pscustomobject]@{ProjectPath=$p.project_path;OutDir=$s.out_dir;WaitSeconds='invalid'})
  $s.arguments=@()
} 'KV_PLAN_PARAMETER_TYPE_INVALID'
# Mutate an isolated test input after the preflight snapshot, never a fixture.
$inputPath=Join-Path $OutDir 'input.tsv'
'initial' | Set-Content -LiteralPath $inputPath -Encoding UTF8
$inputHash=@([pscustomobject]@{path=$inputPath;sha256=(Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash})
Assert-KvPlanInputsUnchanged $inputHash
'changed' | Set-Content -LiteralPath $inputPath -Encoding UTF8
$caught=''
try { Assert-KvPlanInputsUnchanged $inputHash } catch { $caught=$_.Exception.Message }
if (-not $caught.StartsWith('KV_PLAN_INPUT_CHANGED')) { throw 'Changed input was accepted' }
$results.Add(@{name='changed_input';ok=$true;error_code='KV_PLAN_INPUT_CHANGED'})

# An invalid flat plan must fail before even acquiring the desktop mutex.
$bad=$planJson | ConvertFrom-Json
$bad.run_root=Join-Path $OutDir 'executor_reject'
$bad.result_path=Join-Path $bad.run_root 'workflow_result.json'
$bad.steps[2].arguments+=@('-UnknownInput','x')
$badPath=Join-Path $OutDir 'bad_plan.json'
$bad | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $badPath -Encoding UTF8
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'workflow_tools/invoke_kv_flat_execution_plan.ps1') -PlanPath $badPath
if ($LASTEXITCODE -eq 0) { throw 'Invalid executor plan returned success' }
$runLog=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $bad.run_root 'run.log')
if ($runLog -match 'step_started|ui_mutex_acquired|ui_input_session_started') { throw 'Invalid executor plan entered execution' }
$results.Add(@{name='executor_rejects_before_ui';ok=$true})

# A failed PlanOnly child must remain a failed regression, with no Kvs launch.
$scenarioPath=Join-Path $OutDir 'bad_scenario.json'
@{name='failed_plan_only';workflow='scripts/workflows/set_kv_fb_arguments.ps1';result_file='workflow/fb_declaration_workflow_result.json';arguments=@('-ProjectPath','${project}','-FbModuleName','FB_Cylinder','-ArgumentsTsv',(Join-Path $OutDir 'missing.tsv'),'-OutDir','${out}/workflow')} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'kv-interface-regression/run-workflow-test.ps1') -ScenarioPath $scenarioPath -OutRoot (Join-Path $OutDir 'harness_reject') -PlanOnly | Out-Null
if ($LASTEXITCODE -eq 0) { throw 'Failed PlanOnly child returned test success' }
$testFile=Get-ChildItem -LiteralPath (Join-Path $OutDir 'harness_reject') -Recurse -Filter 'test_result.json' | Select-Object -Last 1
$testResult=Get-Content -Raw -Encoding UTF8 -LiteralPath $testFile.FullName | ConvertFrom-Json
if ($testResult.ok -or $testResult.status -ne 'fail') { throw 'Failed PlanOnly child recorded planned success' }
$results.Add(@{name='plan_only_failure_propagated';ok=$true})
@{ok=$true;ui_started=$false;tests=@($results)} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) non-UI preflight tests."
