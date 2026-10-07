param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$ContractPath,[Parameter(Mandatory=$true)][string]$OutDir,[string]$CreatedProjectResultPath='',[int]$TimeoutSeconds=600,[switch]$PlanOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
. (Join-Path $root 'workflow_tools/kv_st_module_contract.ps1')
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$ContractPath=[IO.Path]::GetFullPath($ContractPath);$OutDir=[IO.Path]::GetFullPath($OutDir)
$null=New-Item -ItemType Directory -Force -Path $OutDir
$resultPath=Join-Path $OutDir 'workflow_result.json'
if(Test-Path -LiteralPath $resultPath -PathType Leaf){
  $history=Join-Path $OutDir ('_history/'+[guid]::NewGuid().ToString('N'))
  $null=New-Item -ItemType Directory -Force -Path $history
  Move-Item -LiteralPath $resultPath -Destination (Join-Path $history 'workflow_result.json')
}
$submitted=$false
try{
  & (Join-Path $root 'gates/assert_kv_st_module.ps1') -ProjectPath $ProjectPath -ContractPath $ContractPath -OutDir (Join-Path $OutDir 'preflight')
  if($LASTEXITCODE -ne 0){throw 'KV_ST_MODULE_PREFLIGHT_FAILED'}
  $checked=Read-KvStModuleContract $ContractPath $ProjectPath;$c=$checked.contract
  $plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'create_st_module' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
  $dest=Join-Path $plan.artifact_root 'module_contract'
  Add-KvWorkflowStep -Plan $plan -Name 'module_contract' -Script 'gates/assert_kv_st_module.ps1' -Class gate -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;ContractPath=$ContractPath;OutDir=$dest}
  $dest=Join-Path $plan.artifact_root 'import'
  $p=@{ProjectPath=$ProjectPath;MnmPath=$c.body_path;ExpectedModuleName=$c.module_name;ExpectedCategory=$c.category;ParentPath=$c.parent_path;OutDir=$dest;SaveAfterImport=$true;RestartKvs=$false}
  if($CreatedProjectResultPath){$p.CreatedProjectResultPath=[IO.Path]::GetFullPath($CreatedProjectResultPath)}
  Add-KvWorkflowStep -Plan $plan -Name 'import' -Script 'runner_children/import_mnm_guarded.ps1' -OutDir $dest -Parameters $p
  if($c.category -eq 'function_block'){
    $dest=Join-Path $plan.artifact_root 'arguments'
    Add-KvWorkflowStep -Plan $plan -Name 'arguments' -Script 'runner_children/set_fb_arguments_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;FbModuleName=$c.module_name;ArgumentsTsv=$c.arguments_path;OutDir=$dest}
  }
  $dest=Join-Path $plan.artifact_root 'locals'
  $p=@{ProjectPath=$ProjectPath;LocalProgramName=$c.module_name;LocalVariablesTsv=$c.locals_path;SkipGlobal=(-not $c.globals_path);AuditPersistence=$true;LocalPasteFormat='NameType';OutDir=$dest;AllowedCustomDataTypes=$checked.custom_types}
  if($c.globals_path){$p.GlobalVariablesTsv=$c.globals_path;$p.AppendGlobalVariables=$true}
  Add-KvWorkflowStep -Plan $plan -Name 'locals' -Script 'runner_children/set_variables_guarded.ps1' -OutDir $dest -Parameters $p
  if($c.category -eq 'function_block'){
    $dest=Join-Path $plan.artifact_root 'arguments_readback'
    Add-KvWorkflowStep -Plan $plan -Name 'arguments_readback' -Script 'runner_children/set_fb_arguments_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;FbModuleName=$c.module_name;SnapshotOnly=$true;OutDir=$dest}
  }
  $dest=Join-Path $plan.artifact_root 'compile'
  $p=@{ProjectPath=$ProjectPath;OutDir=$dest;ConvertAction='CtrlF9';WaitSeconds=40}
  if($CreatedProjectResultPath){$p.CreatedProjectResultPath=[IO.Path]::GetFullPath($CreatedProjectResultPath)}
  Add-KvWorkflowStep -Plan $plan -Name 'compile' -Script 'runner_children/compile_and_copy_result_bounded.ps1' -OutDir $dest -Parameters $p
  $dest=Join-Path $plan.artifact_root 'compile_result'
  $p=@{ProjectPath=$ProjectPath;ProjectNeedle=$plan.project_name;OutDir=$dest;MaxLookupMs=8000}
  if($CreatedProjectResultPath){$p.CreatedProjectResultPath=[IO.Path]::GetFullPath($CreatedProjectResultPath)}
  Add-KvWorkflowStep -Plan $plan -Name 'compile_result' -Script 'runner_children/copy_convert_result_from_tree_handle.ps1' -OutDir $dest -Parameters $p
  $plan.require_compile_result=$true;$plan.compile_result_path=Join-Path $dest 'compile_result_copied.txt'
  $dest=Join-Path $plan.artifact_root 'export'
  $p=@{ProjectPath=$ProjectPath;ExportDir=(Split-Path -Parent $ProjectPath);OutDir=$dest;RestartKvs=$false;TimeoutSeconds=90}
  if($CreatedProjectResultPath){$p.CreatedProjectResultPath=[IO.Path]::GetFullPath($CreatedProjectResultPath)}
  Add-KvWorkflowStep -Plan $plan -Name 'export' -Script 'runner_children/export_mnm_browse_default_folder_guarded.ps1' -OutDir $dest -Parameters $p
  $dest=Join-Path $plan.artifact_root 'verify'
  Add-KvWorkflowStep -Plan $plan -Name 'verify' -Script 'workflow_tools/assert_kv_st_module_result.ps1' -Class workflow_tool -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;ContractPath=$ContractPath;ArtifactsRoot=$plan.artifact_root;OutDir=$dest}
  $submitted=-not [bool]$PlanOnly
  Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
  if($PlanOnly){@{ok=$true;status='planned';ui_started=$false;execution_plan_path=(Join-Path $OutDir 'execution_plan.json')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutDir 'workflow_result.json') -Encoding UTF8}
}catch{
  if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){
    $failure=@{ok=$false;status='fail';message=$_.Exception.Message;error_code=($_.Exception.Message -split ':')[0]}
    if(-not $submitted){$failure.ui_started=$false}
    $failure|ConvertTo-Json|Set-Content -LiteralPath $resultPath -Encoding UTF8
  }
  [Console]::Error.WriteLine($_.Exception.Message);exit 1
}
