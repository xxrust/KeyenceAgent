param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$ContractPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$ChecklistPath='',
  [string]$CreatedProjectResultPath='',
  [int]$TimeoutSeconds=600,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
. (Join-Path $root 'workflow_tools/kv_nano_label_contract.ps1')
$ContractPath=[IO.Path]::GetFullPath($ContractPath)
$contract=Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8|ConvertFrom-Json
if($contract.schema_version -ne 1 -or -not $contract.program -or -not $contract.labels -or -not $contract.edits -or -not $contract.ladder){throw 'KV_NANO_PROGRAM_CONTRACT_REQUIRED'}
$contractRoot=Split-Path -Parent $ContractPath
function Contract-File([string]$Value,[switch]$AllowEmpty){
  if(-not $Value){if($AllowEmpty){return ''};throw 'KV_NANO_CONTRACT_FILE_REQUIRED'}
  $path=if([IO.Path]::IsPathRooted($Value)){$Value}else{Join-Path $contractRoot $Value}
  $path=[IO.Path]::GetFullPath($path)
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('KV_NANO_CONTRACT_FILE_MISSING: '+$path)}
  return $path
}
$labels=Contract-File $contract.labels.source
$oldLabels=Contract-File $contract.labels.expected
$labelWrite=Get-KvNanoLabelWrite -SourcePath $labels -ExpectedSourcePath $oldLabels -Row 1
if($labelWrite.after -cne $labelWrite.source){throw 'KV_NANO_FULL_TABLE_SHRINK_REQUIRES_EXPLICIT_DELETE'}
$edits=@(foreach($item in @($contract.edits)){
  if($item.action -notin @('CreateScript','CreateAreaScript','UpdateScript','UpdateAreaScript','InsertLadder','UpdateLadder')){throw 'KV_NANO_CONTRACT_EDIT_UNSUPPORTED'}
  if([int]$item.row -lt 1){throw 'KV_NANO_CONTRACT_ROW_INVALID'}
  $expected=Contract-File ([string]$item.expected) -AllowEmpty
  if($item.action -like 'Update*' -and -not $expected){throw 'KV_NANO_CONTRACT_EXPECTED_REQUIRED'}
  @{action=[string]$item.action;row=[int]$item.row;source=(Contract-File $item.source);expected=$expected}
})
$ladder=@(foreach($item in @($contract.ladder)){
  if([int]$item.row -lt 1){throw 'KV_NANO_CONTRACT_ROW_INVALID'}
  @{row=[int]$item.row;source=(Contract-File $item.source)}
})
# All edits and all post-reopen expectations exist before any desktop input.
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'apply_nano_program_plan' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
function Add-Nano([string]$Name,[string]$Action,[int]$Row=1,[string]$Source='',[string]$Expected='',[string]$Receipt=''){
  $dest=Join-Path $plan.artifact_root $Name
  Add-KvWorkflowStep -Plan $plan -Name $Name -Script 'runner_children/nano_box_script_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$plan.project_path;OutDir=$dest;Action=$Action;ProgramName=[string]$contract.program;Row=$Row;SourcePath=$Source;ExpectedSourcePath=$Expected;CreatedProjectResultPath=$Receipt;ProgramContractPath=$ContractPath}
}
if($CreatedProjectResultPath){Add-Nano 'bind_created' 'Reopen' 1 '' '' $CreatedProjectResultPath}
Add-Nano 'labels_batch' 'WriteLabels' 1 $labels $oldLabels
$index=0
foreach($edit in $edits){Add-Nano ('edit_'+(++$index)) $edit.action $edit.row $edit.source $edit.expected}
$compileOut=Join-Path $plan.artifact_root 'compile'
$copyOut=Join-Path $plan.artifact_root 'compile_result'
Add-KvWorkflowStep -Plan $plan -Name 'compile' -Script 'runner_children/compile_and_copy_result_bounded.ps1' -OutDir $compileOut -Parameters @{ProjectPath=$plan.project_path;OutDir=$compileOut;ChecklistPath=$ChecklistPath;ConvertAction='CtrlF9';WaitSeconds=40}
Add-KvWorkflowStep -Plan $plan -Name 'copy_compile_result' -Script 'runner_children/copy_convert_result_from_tree_handle.ps1' -OutDir $copyOut -Parameters @{ProjectPath=$plan.project_path;ProjectNeedle=$plan.project_name;OutDir=$copyOut;ChecklistPath=$ChecklistPath;MaxLookupMs=8000}
$plan.require_compile_result=$true
$plan.compile_result_path=Join-Path $copyOut 'compile_result_copied.txt'
Add-Nano 'reopen_saved' 'Reopen'
Add-Nano 'labels_persisted' 'ReadLabels' 1 '' $labels
$index=0
foreach($edit in $edits){
  if($edit.action -notlike '*Script'){continue}
  $readAction=if($edit.action -like '*AreaScript'){'ReadAreaScript'}else{'ReadScript'}
  Add-Nano ('script_persisted_'+(++$index)) $readAction $edit.row '' $edit.source
}
$index=0
foreach($item in $ladder){Add-Nano ('ladder_persisted_'+(++$index)) 'ReadLadder' $item.row '' $item.source}
Add-Nano 'close_verified' 'Close'
# Contract is a fingerprinted input as well, not only its individual sources.
$plan.contract_path=$ContractPath
$plan.source_manifest=@{labels=$labels;expected_labels=$oldLabels;edits=$edits;ladder=$ladder;system_device_policy='no CR/CM labels or comment writes'}
$plan.source_manifest|ConvertTo-Json -Depth 8|Set-Content (Join-Path $plan.run_root 'source_manifest.json') -Encoding UTF8
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
