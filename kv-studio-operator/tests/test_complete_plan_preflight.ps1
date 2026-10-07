param([Parameter(Mandatory=$true)][string]$PlanPath,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$scriptsRoot=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
. (Join-Path $scriptsRoot 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $scriptsRoot 'workflow_tools/kv_step_evidence.ps1')
. (Join-Path $scriptsRoot 'workflow_tools/kv_plan_preflight.ps1')
$json=Get-Content -Raw -Encoding UTF8 -LiteralPath $PlanPath
$baseline=Test-KvExecutionPlanPreflight ($json | ConvertFrom-Json) $scriptsRoot
$results=[Collections.Generic.List[object]]::new()
function Reject([string]$Name,[scriptblock]$Mutation,[string]$Code) {
  $p=$json|ConvertFrom-Json
  & $Mutation $p
  $caught=''
  try { $null=Test-KvExecutionPlanPreflight $p $scriptsRoot } catch { $caught=$_.Exception.Message }
  if (-not $caught.StartsWith($Code)) { throw "$Name expected $Code, got $caught" }
  $results.Add(@{name=$Name;ok=$true;error_code=$Code})
}
Reject 'missing_contract_gate' {param($p) $p.steps=@($p.steps|Where-Object{$_.name -ne 'module_contract'})} 'KV_COMPLETE_PLAN_CONTRACT_GATE_REQUIRED'
foreach($stepName in @('import','locals','compile','compile_result','export','verify')+@(($json|ConvertFrom-Json).steps|Where-Object{$_.name -in @('arguments','arguments_readback')}|ForEach-Object{$_.name})) {
  Reject "missing_$stepName" {param($p) $p.steps=@($p.steps|Where-Object{$_.name -ne $stepName})} 'KV_COMPLETE_PLAN_STEPS_REQUIRED'
}
Reject 'wrong_final_order' {param($p) $last=$p.steps.Count-1;$tmp=$p.steps[$last];$p.steps[$last]=$p.steps[$last-1];$p.steps[$last-1]=$tmp} 'KV_COMPLETE_PLAN_STEP_ORDER'
Reject 'compile_disabled' {param($p) $p.require_compile_result=$false} 'KV_COMPLETE_PLAN_COMPILE_REQUIRED'
Reject 'wrong_import_parent' {param($p) ($p.steps|Where-Object{$_.name -eq 'import'}).parameters.ParentPath=@('wrong')} 'KV_COMPLETE_PLAN_IMPORT_MISMATCH'
Reject 'wrong_module_identity' {param($p) ($p.steps|Where-Object{$_.name -eq 'import'}).parameters.ExpectedModuleName='other'} 'KV_COMPLETE_PLAN_IMPORT_MISMATCH'
Reject 'locals_audit_disabled' {param($p) ($p.steps|Where-Object{$_.name -eq 'locals'}).parameters.AuditPersistence=$false} 'KV_COMPLETE_PLAN_LOCALS_MISMATCH'
Reject 'locals_reopen_disabled' {param($p) ($p.steps|Where-Object{$_.name -eq 'locals'}).parameters|Add-Member -NotePropertyName KeepVariableEditorOpen -NotePropertyValue $true} 'KV_COMPLETE_PLAN_LOCALS_MISMATCH'
Reject 'wrong_compile_evidence' {param($p) $p.compile_result_path=Join-Path $p.run_root 'old_compile.txt'} 'KV_COMPLETE_PLAN_COMPILE_RESULT_MISMATCH'
Reject 'wrong_verification_root' {param($p) ($p.steps|Where-Object{$_.name -eq 'verify'}).parameters.ArtifactsRoot=$p.run_root} 'KV_COMPLETE_PLAN_VERIFY_MISMATCH'
if (@(($json|ConvertFrom-Json).steps|Where-Object{$_.name -eq 'arguments_readback'}).Count) {
  Reject 'arguments_readback_before_locals' {param($p) $i=[array]::IndexOf($p.steps,($p.steps|Where-Object{$_.name -eq 'arguments_readback'}));$tmp=$p.steps[$i];$p.steps[$i]=$p.steps[$i-1];$p.steps[$i-1]=$tmp} 'KV_COMPLETE_PLAN_STEP_ORDER'
  Reject 'arguments_readback_write_mode' {param($p) ($p.steps|Where-Object{$_.name -eq 'arguments_readback'}).parameters.SnapshotOnly=$false} 'KV_COMPLETE_PLAN_ARGUMENTS_READBACK_MISMATCH'
  Reject 'arguments_readback_mode_missing' {param($p) ($p.steps|Where-Object{$_.name -eq 'arguments_readback'}).parameters.PSObject.Properties.Remove('SnapshotOnly')} 'KV_COMPLETE_PLAN_ARGUMENTS_READBACK_MISMATCH'
  Reject 'arguments_readback_wrong_module' {param($p) ($p.steps|Where-Object{$_.name -eq 'arguments_readback'}).parameters.FbModuleName='other'} 'KV_COMPLETE_PLAN_ARGUMENTS_READBACK_MISMATCH'
  Reject 'arguments_readback_wrong_project' {param($p) ($p.steps|Where-Object{$_.name -eq 'arguments_readback'}).parameters.ProjectPath='H:\other_project.kpr'} 'KV_PLAN_STEP_PROJECT_MISMATCH'
  Reject 'arguments_readback_write_input' {param($p) ($p.steps|Where-Object{$_.name -eq 'arguments_readback'}).parameters|Add-Member -NotePropertyName ArgumentsTsv -NotePropertyValue (($p.steps|Where-Object{$_.name -eq 'arguments'}).parameters.ArgumentsTsv)} 'KV_COMPLETE_PLAN_ARGUMENTS_READBACK_MISMATCH'
  Reject 'arguments_readback_wrong_output' {param($p) $s=($p.steps|Where-Object{$_.name -eq 'arguments_readback'});$s.out_dir=Join-Path $p.run_root 'elsewhere';$s.parameters.OutDir=$s.out_dir} 'KV_COMPLETE_PLAN_ARGUMENTS_READBACK_MISMATCH'
}
$contractPath=$baseline.prepared_steps.module_contract.parameters.ContractPath
$contract=Get-Content -Raw -Encoding UTF8 -LiteralPath $contractPath|ConvertFrom-Json
foreach($evidence in $contract.evidence_paths) {
  $expected=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $contractPath) $evidence))
  if (@($baseline.inputs|Where-Object{$_.path -eq $expected}).Count -ne 1) { throw "Missing transitive fingerprint: $expected" }
}
$results.Add(@{name='transitive_evidence_frozen';ok=$true})
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
. (Join-Path $scriptsRoot 'workflow_tools/kv_complete_module_contract.ps1')
$fixtureDirectory=Join-Path $OutDir ('headers_'+[guid]::NewGuid().ToString('N'))
Copy-Item -LiteralPath (Split-Path -Parent $contractPath) -Destination $fixtureDirectory -Recurse
$copyContract=Join-Path $fixtureDirectory (Split-Path -Leaf $contractPath)
$bodyPath=Join-Path $fixtureDirectory $contract.body_path
$originalBody=[IO.File]::ReadAllText($bodyPath,[Text.Encoding]::Default)
foreach($header in @(';MODULE_TYPE:999','DEVICE:999',';module_type:999',' device:999')){
  [IO.File]::WriteAllText($bodyPath,($header+"`r`n"+$originalBody),[Text.Encoding]::Default)
  $caught=''
  try{$null=Read-KvCompleteModuleContract $copyContract ($json|ConvertFrom-Json).project_path}catch{$caught=$_.Exception.Message}
  if(-not $caught.StartsWith('KV_MODULE_CONTRACT_MNM_HEADER')){throw "Conflicting duplicate header accepted: $header; error=$caught"}
  $results.Add(@{name="reject_duplicate_header_$header";ok=$true;error_code='KV_MODULE_CONTRACT_MNM_HEADER'})
}
@{ok=$true;ui_started=$false;tests=@($results)}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) complete-plan non-UI tests."
