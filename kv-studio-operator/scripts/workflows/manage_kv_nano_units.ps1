param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [ValidateSet('Open','Inspect','Query','Select','SetParameter','Commit','Cancel','Delete','Add')][string]$Action='Query',
  [int]$UnitIndex=0,
  [string]$ExpectedModel='',
  [string]$ParameterName='',
  [string]$ExpectedValue='',
  [string]$Value='',
  [string]$ExpectedAfterRowsPath='',
  [string]$ExpectedSnapshotPath='',
  [int]$TimeoutSeconds=120,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
if($Action -eq 'Add' -and ($ExpectedModel -notin @('KV-NC1EP','KV-NC16EXT*') -or $UnitIndex -notin @(1,2))){throw 'KV_NANO_UNIT_ADD_MODEL_OR_INDEX_NOT_VERIFIED'}
if($Action -eq 'SetParameter' -and (-not $ParameterName -or -not $ExpectedValue -or -not $Value)){throw 'KV_NANO_UNIT_PARAMETER_CONTRACT_REQUIRED'}
if($Action -eq 'SetParameter' -and $ParameterName -eq '动作模式' -and -not $ExpectedAfterRowsPath){throw 'KV_NANO_UNIT_MODE_TARGET_ROWS_REQUIRED'}
foreach($path in @($ExpectedSnapshotPath,$ExpectedAfterRowsPath)){
  if($path -and -not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'KV_NANO_UNIT_EXPECTED_INPUT_MISSING'}
}
if($ExpectedAfterRowsPath){
  $rows=Get-Content $ExpectedAfterRowsPath -Raw -Encoding UTF8|ConvertFrom-Json
  if(-not ($rows -is [array]) -or @($rows|Where-Object {-not ($_ -is [array]) -or $_.Count -ne 3}).Count){throw 'KV_NANO_UNIT_TARGET_ROW_SHAPE_INVALID'}
  $matching=@($rows|Where-Object {$_[1] -ceq $ParameterName})
  if($matching.Count -ne 1 -or $matching[0][2] -cne $Value){throw 'KV_NANO_UNIT_TARGET_PARAMETER_MISMATCH'}
}
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'nano_unit_editor' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
$dest=Join-Path $plan.artifact_root 'units'
if($Action -eq 'Delete' -and $UnitIndex -eq 0){throw 'KV_NANO_UNIT_CPU_DELETE_FORBIDDEN'}
if($Action -in @('Add','Delete','SetParameter') -and -not $ExpectedModel){throw 'KV_NANO_UNIT_EXPECTED_MODEL_REQUIRED'}
Add-KvWorkflowStep -Plan $plan -Name 'nano_units' -Script 'runner_children/nano_unit_editor_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$plan.project_path;OutDir=$dest;Action=$Action;UnitIndex=$UnitIndex;ExpectedModel=$ExpectedModel;ParameterName=$ParameterName;ExpectedValue=$ExpectedValue;Value=$Value;ExpectedSnapshotPath=$ExpectedSnapshotPath;ExpectedAfterRowsPath=$ExpectedAfterRowsPath}
if($Action -in @('Add','Delete','SetParameter')){
  $commit=Join-Path $plan.artifact_root 'commit'
  Add-KvWorkflowStep -Plan $plan -Name 'commit_units' -Script 'runner_children/nano_unit_editor_guarded.ps1' -OutDir $commit -Parameters @{ProjectPath=$plan.project_path;OutDir=$commit;Action='Commit'}
  $readback=Join-Path $plan.artifact_root 'readback'
  $parameters=@{ProjectPath=$plan.project_path;OutDir=$readback;Action='Query'}
  if($Action -in @('Add','Delete')){$parameters.ExpectedLayoutPath=Join-Path $dest 'layout_expected.json'}
  if($Action -eq 'SetParameter'){
    $parameters.UnitIndex=$UnitIndex;$parameters.ExpectedModel=$ExpectedModel;$parameters.ParameterName=$ParameterName;$parameters.Value=$Value
  }
  Add-KvWorkflowStep -Plan $plan -Name 'read_saved_units' -Script 'runner_children/nano_unit_editor_guarded.ps1' -OutDir $readback -Parameters $parameters
}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
