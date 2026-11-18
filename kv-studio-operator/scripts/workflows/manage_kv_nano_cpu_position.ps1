param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [ValidateSet('ToolsMenu','Open','Inspect','Navigate','ReadPage','ReadAll','WritePage','Apply','Close','ApplyPlan')][string]$Action='Open',
  [ValidateSet('点参数','点参数通用设定','I/O 设定','原点复归设定','JOG设定','比较器设定')][string]$PageName='I/O 设定',
  [string]$ExpectedTablePath='',
  [string]$SourcePath='',
  [string]$ContractPath='',
  [int]$TimeoutSeconds=600,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
. (Join-Path $root 'workflow_tools/kv_nano_cpu_position_contract.ps1')
if($Action -eq 'WritePage'){$null=Get-KvCpuPositionWrite $PageName $ExpectedTablePath $SourcePath}
$pages=@('点参数','点参数通用设定','I/O 设定','原点复归设定','JOG设定','比较器设定')
if($Action -eq 'ApplyPlan'){
  if(-not $ContractPath){throw 'KV_CPU_POSITION_CONTRACT_REQUIRED'}
  $ContractPath=[IO.Path]::GetFullPath($ContractPath)
  $contract=Get-Content $ContractPath -Raw -Encoding UTF8|ConvertFrom-Json
  if($contract.schema_version -ne 1 -or $contract.cpu_model -ne 'KV-NC32' -or @($contract.pages).Count -ne 6){throw 'KV_CPU_POSITION_SIX_PAGE_CONTRACT_REQUIRED'}
  $base=Split-Path -Parent $ContractPath
  $entries=@(for($i=0;$i -lt 6;$i++){
    $item=$contract.pages[$i]
    if($item.page -cne $pages[$i]){throw 'KV_CPU_POSITION_CONTRACT_PAGE_ORDER_REQUIRED'}
    $old=[IO.Path]::GetFullPath((Join-Path $base $item.expected));$new=[IO.Path]::GetFullPath((Join-Path $base $item.source))
    foreach($p in @($old,$new)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw 'KV_CPU_POSITION_TABLE_FILE_REQUIRED'}}
    $changed=(ConvertTo-KvCpuPositionTable ([IO.File]::ReadAllText($old))) -cne (ConvertTo-KvCpuPositionTable ([IO.File]::ReadAllText($new)))
    if($changed){$null=Get-KvCpuPositionWrite $item.page $old $new}
    @{page=$item.page;expected=$old;source=$new;changed=$changed}
  })
  if(-not @($entries|Where-Object {$_.changed}).Count){throw 'KV_CPU_POSITION_NO_CHANGE'}
}
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'nano_cpu_position' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
function Add-ParameterStep($Name,$StepAction,$Page='I/O 设定',$Expected='',$Source=''){
  $dest=Join-Path $plan.artifact_root $Name
  Add-KvWorkflowStep -Plan $plan -Name $Name -Script 'runner_children/nano_cpu_position_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$plan.project_path;OutDir=$dest;Action=$StepAction;PageName=$Page;ExpectedTablePath=$Expected;SourcePath=$Source;ContractPath=$ContractPath}
}
if($Action -eq 'ApplyPlan'){
  Add-ParameterStep 'open_parameters' 'Open'
  $index=0;foreach($item in $entries){Add-ParameterStep ('before_'+(++$index)) 'ReadPage' $item.page $item.expected}
  $index=0;foreach($item in $entries){if($item.changed){Add-ParameterStep ('write_'+(++$index)) 'WritePage' $item.page $item.expected $item.source}}
  $index=0;foreach($item in $entries){Add-ParameterStep ('pending_'+(++$index)) 'ReadPage' $item.page $item.source}
  Add-ParameterStep 'apply_project' 'Apply'
  Add-ParameterStep 'close_parameters' 'Close'
  $dest=Join-Path $plan.artifact_root 'save_reopen'
  Add-KvWorkflowStep -Plan $plan -Name 'save_reopen' -Script 'runner_children/nano_box_script_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$plan.project_path;OutDir=$dest;Action='Reopen'}
  Add-ParameterStep 'open_persisted' 'Open'
  $index=0;foreach($item in $entries){Add-ParameterStep ('persisted_'+(++$index)) 'ReadPage' $item.page $item.source}
  Add-ParameterStep 'close_verified_parameters' 'Close'
  $dest=Join-Path $plan.artifact_root 'close_verified_project'
  Add-KvWorkflowStep -Plan $plan -Name 'close_verified_project' -Script 'runner_children/nano_box_script_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$plan.project_path;OutDir=$dest;Action='Close'}
}elseif($Action -eq 'ReadAll'){
  $index=0
  foreach($page in $pages){
    $dest=Join-Path $plan.artifact_root ('page_'+(++$index))
    Add-KvWorkflowStep -Plan $plan -Name ('page_'+$index) -Script 'runner_children/nano_cpu_position_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$plan.project_path;OutDir=$dest;Action='ReadPage';PageName=$page}
  }
}else{
  $dest=Join-Path $plan.artifact_root 'parameters'
  Add-KvWorkflowStep -Plan $plan -Name 'cpu_position_parameters' -Script 'runner_children/nano_cpu_position_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$plan.project_path;OutDir=$dest;Action=$Action;PageName=$PageName;ExpectedTablePath=$ExpectedTablePath;SourcePath=$SourcePath}
}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
