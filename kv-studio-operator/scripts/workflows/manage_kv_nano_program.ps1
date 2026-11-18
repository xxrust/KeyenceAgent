param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [Parameter(Mandatory=$true)][ValidateSet('Inspect','InspectLabels','ReadLabels','WriteLabels','DeleteLabel','CreateScript','ReadScript','UpdateScript','DeleteScript','CreateAreaScript','ReadAreaScript','UpdateAreaScript','DeleteAreaScript','InsertLadder','ReadLadder','UpdateLadder','DeleteLadder','Save','Close','Reopen')][string]$Action,
  [ValidateSet('Global','Local')][string]$LabelScope='Global',
  [string]$ProgramName='Main',
  [ValidateRange(1,10000)][int]$Row=1,
  [string]$SourcePath='',
  [string]$ExpectedSourcePath='',
  [string]$Condition='CR2002',
  [string]$CreatedProjectResultPath='',
  [string]$ChecklistPath='',
  [string]$InspectMenuName='',
  [int]$TimeoutSeconds=180,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
. (Join-Path $root 'workflow_tools/kv_nano_label_contract.ps1')
foreach($inputPath in @($SourcePath,$ExpectedSourcePath)){
  if($inputPath -and -not(Test-Path -LiteralPath $inputPath -PathType Leaf)){throw 'KV_NANO_SOURCE_FILE_REQUIRED'}
}
if($Action -eq 'WriteLabels'){$null=Get-KvNanoLabelWrite -SourcePath $SourcePath -ExpectedSourcePath $ExpectedSourcePath -Row $Row}
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'manage_nano_program' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
$binding=$CreatedProjectResultPath
if($binding -and $Action -in @('WriteLabels','DeleteLabel','CreateScript','UpdateScript','DeleteScript','CreateAreaScript','UpdateAreaScript','DeleteAreaScript','InsertLadder','UpdateLadder','DeleteLadder')){
  # Establish command-line path binding once, closing the created editor first.
  # Compilation then uses full-path identity even when a tooltip or result pane
  # temporarily becomes Process.MainWindowHandle.
  $bindOut=Join-Path $plan.artifact_root 'bind_created'
  Add-KvWorkflowStep -Plan $plan -Name 'bind_created' -Script 'runner_children/nano_box_script_guarded.ps1' -OutDir $bindOut -Parameters @{ProjectPath=$plan.project_path;OutDir=$bindOut;Action='Reopen';CreatedProjectResultPath=$binding}
  $binding=''
}
$dest=Join-Path $plan.artifact_root 'operation'
Add-KvWorkflowStep -Plan $plan -Name 'nano_operation' -Script 'runner_children/nano_box_script_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$plan.project_path;OutDir=$dest;Action=$Action;LabelScope=$LabelScope;ProgramName=$ProgramName;Row=$Row;SourcePath=$SourcePath;ExpectedSourcePath=$ExpectedSourcePath;Condition=$Condition;CreatedProjectResultPath=$binding;InspectMenuName=$InspectMenuName}
if($Action -in @('WriteLabels','DeleteLabel','CreateScript','UpdateScript','DeleteScript','CreateAreaScript','UpdateAreaScript','DeleteAreaScript','InsertLadder','UpdateLadder','DeleteLadder')){
  $compileOut=Join-Path $plan.artifact_root 'compile'
  $copyOut=Join-Path $plan.artifact_root 'compile_result'
  Add-KvWorkflowStep -Plan $plan -Name 'compile' -Script 'runner_children/compile_and_copy_result_bounded.ps1' -OutDir $compileOut -Parameters @{ProjectPath=$plan.project_path;CreatedProjectResultPath=$binding;OutDir=$compileOut;ChecklistPath=$ChecklistPath;ConvertAction='CtrlF9';WaitSeconds=40}
  Add-KvWorkflowStep -Plan $plan -Name 'copy_compile_result' -Script 'runner_children/copy_convert_result_from_tree_handle.ps1' -OutDir $copyOut -Parameters @{ProjectNeedle=$plan.project_name;ProjectPath=$plan.project_path;CreatedProjectResultPath=$binding;OutDir=$copyOut;ChecklistPath=$ChecklistPath;MaxLookupMs=8000}
  $saveOut=Join-Path $plan.artifact_root 'save'
  Add-KvWorkflowStep -Plan $plan -Name 'save_compiled' -Script 'runner_children/nano_box_script_guarded.ps1' -OutDir $saveOut -Parameters @{ProjectPath=$plan.project_path;OutDir=$saveOut;Action='Save';CreatedProjectResultPath=$binding}
  $plan.require_compile_result=$true
  $plan.compile_result_path=Join-Path $copyOut 'compile_result_copied.txt'
}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
