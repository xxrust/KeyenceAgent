param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [string]$GlobalVariablesTsv = '',
  [string]$LocalVariablesTsv = '',
  [string]$LocalProgramName = '',
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$ChecklistPath = '',
  [ValidateSet('Full','NameType')][string]$LocalPasteFormat = 'NameType',
  [ValidateSet('Replace','Append')][string]$GlobalWriteMode = 'Append',
  [string[]]$AllowedCustomDataTypes = @(),
  [int]$TimeoutSeconds = 120,
  [switch]$PlanOnly,
  [switch]$SnapshotOnly,
  [string[]]$SnapshotModules = @()
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
if ($SnapshotOnly -and ($GlobalVariablesTsv -or $LocalVariablesTsv)) { throw 'KV_VARIABLE_SNAPSHOT_WRITE_INPUT_CONFLICT' }
if (-not $SnapshotOnly -and -not ($GlobalVariablesTsv -or $LocalVariablesTsv)) { throw 'KV_VARIABLE_INPUT_REQUIRED' }
foreach ($path in @($GlobalVariablesTsv,$LocalVariablesTsv) | Where-Object { $_ }) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "KV_VARIABLE_INPUT_MISSING: $path" }
}
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'set_kv_variables' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds -ResultName 'variable_workflow_result.json'
$dest=Join-Path $plan.artifact_root 'variables'
$parameters=@{ProjectPath=$plan.project_path;OutDir=$dest;ChecklistPath=$ChecklistPath;LocalProgramName=$LocalProgramName;AllowedCustomDataTypes=$AllowedCustomDataTypes}
if ($SnapshotOnly) {
  $parameters.SnapshotOnly=$true
  $parameters.SnapshotModules=$SnapshotModules
} else {
  $parameters.GlobalVariablesTsv=$GlobalVariablesTsv
  $parameters.LocalVariablesTsv=$LocalVariablesTsv
  $parameters.SkipGlobal=(-not $GlobalVariablesTsv)
  $parameters.LocalPasteFormat=$LocalPasteFormat
  $parameters.AuditPersistence=$true
  $parameters.AppendGlobalVariables=($GlobalWriteMode -eq 'Append')
}
Add-KvWorkflowStep -Plan $plan -Name 'variables' -Script 'runner_children/set_variables_guarded.ps1' -OutDir $dest -Parameters $parameters
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
