param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$ContractPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds=600,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools\kv_workflow_plan.ps1')
. (Join-Path $root 'workflow_tools\kv_complete_module_contract.ps1')
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$ContractPath=[IO.Path]::GetFullPath($ContractPath)
$OutDir=[IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
$resultPath=Join-Path $OutDir 'workflow_result.json'
if(Test-Path -LiteralPath $resultPath){
  $history=Join-Path $OutDir ('_history\'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $history|Out-Null
  Move-Item -LiteralPath $resultPath -Destination (Join-Path $history 'workflow_result.json')
}
$executionSubmitted=$false
try {
  $gateOut=Join-Path $OutDir 'preflight'
  & (Join-Path $root 'gates\assert_kv_complete_module.ps1') -ProjectPath $ProjectPath -ContractPath $ContractPath -OutDir $gateOut
  if($LASTEXITCODE -ne 0){throw 'KV_MODULE_PREFLIGHT_FAILED'}
  $checked=Read-KvCompleteModuleContract $ContractPath $ProjectPath
  $c=$checked.contract
  $plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'create_complete_module' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
  Add-KvWorkflowStep -Plan $plan -Name 'module_contract' -Script 'gates/assert_kv_complete_module.ps1' -Class gate -Parameters @{ProjectPath=$ProjectPath;ContractPath=$ContractPath;OutDir=(Join-Path $plan.artifact_root 'module_contract')}
  $dest=Join-Path $plan.artifact_root 'import'
  Add-KvWorkflowStep -Plan $plan -Name 'import' -Script 'runner_children/import_mnm_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;MnmPath=$c.body_path;ExpectedModuleName=$c.module_name;ExpectedCategory=$c.category;ParentPath=$c.parent_path;OutDir=$dest;RestartKvs=$false;SaveAfterImport=$true}
  if($c.category -eq 'function_block'){
    $dest=Join-Path $plan.artifact_root 'arguments'
    Add-KvWorkflowStep -Plan $plan -Name 'arguments' -Script 'runner_children/set_fb_arguments_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;FbModuleName=$c.module_name;ArgumentsTsv=$c.arguments_path;OutDir=$dest}
  }
  $dest=Join-Path $plan.artifact_root 'locals'
  Add-KvWorkflowStep -Plan $plan -Name 'locals' -Script 'runner_children/set_variables_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;LocalProgramName=$c.module_name;LocalVariablesTsv=$c.locals_path;SkipGlobal=$true;AuditPersistence=$true;LocalPasteFormat='NameType';OutDir=$dest}
  if($c.category -eq 'function_block'){
    $dest=Join-Path $plan.artifact_root 'arguments_readback'
    Add-KvWorkflowStep -Plan $plan -Name 'arguments_readback' -Script 'runner_children/set_fb_arguments_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;FbModuleName=$c.module_name;SnapshotOnly=$true;OutDir=$dest}
  }
  $dest=Join-Path $plan.artifact_root 'compile'
  Add-KvWorkflowStep -Plan $plan -Name 'compile' -Script 'runner_children/compile_and_copy_result_bounded.ps1' -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;OutDir=$dest;ConvertAction='CtrlF9';WaitSeconds=40}
  $dest=Join-Path $plan.artifact_root 'compile_result'
  Add-KvWorkflowStep -Plan $plan -Name 'compile_result' -Script 'runner_children/copy_convert_result_from_tree_handle.ps1' -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;ProjectNeedle=$plan.project_name;OutDir=$dest;MaxLookupMs=8000}
  $plan.require_compile_result=$true
  $plan.compile_result_path=Join-Path $dest 'compile_result_copied.txt'
  $dest=Join-Path $plan.artifact_root 'export'
  Add-KvWorkflowStep -Plan $plan -Name 'export' -Script 'runner_children/export_mnm_browse_default_folder_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;ExportDir=(Split-Path -Parent $ProjectPath);OutDir=$dest;RestartKvs=$false;TimeoutSeconds=90}
  $dest=Join-Path $plan.artifact_root 'verify'
  Add-KvWorkflowStep -Plan $plan -Name 'verify' -Script 'workflow_tools/assert_kv_complete_module_result.ps1' -Class workflow_tool -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;ContractPath=$ContractPath;ArtifactsRoot=$plan.artifact_root;OutDir=$dest}
  $executionSubmitted=-not [bool]$PlanOnly
  Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
  if($PlanOnly){@{ok=$true;status='planned';ui_started=$false;preflight_result_path=(Join-Path $gateOut 'module_preflight_result.json');execution_plan_path=(Join-Path $OutDir 'execution_plan.json')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutDir 'workflow_result.json') -Encoding UTF8}
}catch{
  $result=Join-Path $OutDir 'workflow_result.json'
  if(-not(Test-Path $result)){
    $failure=@{ok=$false;status='fail';error_code=($_.Exception.Message -split ':')[0];message=$_.Exception.Message}
    if(-not $executionSubmitted){$failure.ui_started=$false}
    $failure|ConvertTo-Json|Set-Content -LiteralPath $result -Encoding UTF8
  }
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 1
}
