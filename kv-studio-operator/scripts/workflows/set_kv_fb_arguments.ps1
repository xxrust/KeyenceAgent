param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$FbModuleName,
  [Parameter(Mandatory=$true)][string]$ArgumentsTsv,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$ChecklistPath = '',
  [string]$LocalVariablesTsv = '',
  [string[]]$AllowedCustomDataTypes = @(),
  [int]$TimeoutSeconds = 120,
  [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $scriptRoot 'Resolve-KvStudioOperatorScript.ps1')
$runner = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name 'invoke_kv_flat_execution_plan.ps1' -Classes @('workflow_tool')
$OutDir = [IO.Path]::GetFullPath($OutDir)
foreach ($path in @($ProjectPath, $ArgumentsTsv, $LocalVariablesTsv) | Where-Object { $_ }) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Input file not found: $path" }
}
$artifacts = Join-Path $OutDir 'artifacts'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$steps = [System.Collections.Generic.List[object]]::new()
foreach ($gate in @('ui_guard_usage', 'agent_boundary')) {
  $dest = Join-Path $artifacts $gate
  $steps.Add(@{name="assert_$gate";kind='gate';script_name="assert_kv_mvp_$gate.ps1";classes=@('gate');arguments=@('-ScriptsRoot',$scriptRoot,'-OutDir',$dest);out_dir=$dest})
}
$argOut = Join-Path $artifacts 'fb_arguments'
$steps.Add(@{name='set_fb_arguments';kind='runner_child';script_name='set_fb_arguments_guarded.ps1';classes=@('runner_child_approved');out_dir=$argOut;arguments=@('-ProjectPath',$ProjectPath,'-FbModuleName',$FbModuleName,'-ArgumentsTsv',$ArgumentsTsv,'-ChecklistPath',$ChecklistPath,'-OutDir',$argOut)})
if ($AllowedCustomDataTypes.Count) { $steps[$steps.Count-1].arguments += @('-AllowedCustomDataTypes',($AllowedCustomDataTypes -join ',')) }
if ($LocalVariablesTsv) {
  $localOut = Join-Path $artifacts 'local_variables'
  $localArgs = @('-ProjectPath',$ProjectPath,'-LocalProgramName',$FbModuleName,'-LocalVariablesTsv',$LocalVariablesTsv,'-SkipGlobal','-AuditPersistence','-ChecklistPath',$ChecklistPath,'-OutDir',$localOut)
  if ($AllowedCustomDataTypes.Count) { $localArgs += @('-AllowedCustomDataTypes',($AllowedCustomDataTypes -join ',')) }
  $steps.Add(@{name='set_fb_local_variables';kind='runner_child';script_name='set_variables_guarded.ps1';classes=@('runner_child_approved');out_dir=$localOut;arguments=$localArgs})
}
$planPath = Join-Path $OutDir 'execution_plan.json'
@{
  ok=$true;schema_version=1;operation='set_kv_fb_arguments';project_path=$ProjectPath;project_name=[IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  run_root=$OutDir;artifact_root=$artifacts;result_path=(Join-Path $OutDir 'fb_declaration_workflow_result.json');checklist_path=$ChecklistPath
  timeout_seconds=$TimeoutSeconds;require_compile_result=$false;steps=$steps.ToArray()
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $planPath -Encoding UTF8
if ($PlanOnly) { exit 0 }
& powershell -NoProfile -ExecutionPolicy Bypass -File $runner -PlanPath $planPath -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
