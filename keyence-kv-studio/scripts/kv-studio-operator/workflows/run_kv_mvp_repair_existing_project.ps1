param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [Parameter(Mandatory=$true)]
  [string]$ScaffoldRoot,

  [string]$OutRoot = '',
  [string]$ProjectName = '',
  [string]$KvsExe = '',
  [string]$ConfigPath = '',
  [string]$ChecklistPath = '',
  [string]$SourceSnapshotManifestPath = '',
  [int]$TimeoutSeconds = 600,
  [switch]$AuditVariablePersistence,
  [ValidateSet('Full','NameType')]
  [string]$LocalPasteFormat = 'NameType',
  [switch]$DeleteExistingModulesBeforeImport
)

$ErrorActionPreference = 'Stop'
$workflowScriptDir = Split-Path -Parent $PSCommandPath
$resolver = Join-Path (Split-Path -Parent $workflowScriptDir) 'Resolve-KvStudioOperatorScript.ps1'
if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) { throw "Script resolver not found: $resolver" }
. $resolver
$scriptRoot = Get-KvStudioOperatorScriptsRoot -StartPath $PSCommandPath

$configLoader = Join-Path $scriptRoot 'Import-KvStudioOperatorConfig.ps1'
if (Test-Path -LiteralPath $configLoader -PathType Leaf) {
  $operatorConfig = & $configLoader -ConfigPath $ConfigPath -ScriptRoot $scriptRoot
  if ($operatorConfig.found) {
    if (-not $PSBoundParameters.ContainsKey('KvsExe') -and $operatorConfig.kvs_exe) { $KvsExe = [string]$operatorConfig.kvs_exe }
    if (-not $PSBoundParameters.ContainsKey('OutRoot') -and $operatorConfig.repair_out_root) { $OutRoot = [string]$operatorConfig.repair_out_root }
    if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds') -and $null -ne $operatorConfig.timeout_seconds) { $TimeoutSeconds = [int]$operatorConfig.timeout_seconds }
    if (-not $PSBoundParameters.ContainsKey('LocalPasteFormat') -and $operatorConfig.local_paste_format) { $LocalPasteFormat = [string]$operatorConfig.local_paste_format }
  }
}
if ([string]::IsNullOrWhiteSpace($OutRoot)) {
  $OutRoot = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'kv-studio-operator') 'mvp_repair_runs'
}

$planTool = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name 'new_kv_mvp_execution_plan.ps1' -Classes @('workflow_tool')
$runnerTool = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name 'invoke_kv_flat_execution_plan.ps1' -Classes @('workflow_tool')
$planOutDir = Join-Path ([IO.Path]::GetFullPath($OutRoot)) ('_execution_plans\repair_existing_project_' + (Get-Date -Format 'yyyyMMdd_HHmmss_ffff'))
New-Item -ItemType Directory -Force -Path $planOutDir | Out-Null

$planArgs = @(
  '-NoProfile','-ExecutionPolicy','Bypass','-File',$planTool,
  '-Mode','repair_existing_project',
  '-ProjectPath',$ProjectPath,
  '-ScaffoldRoot',$ScaffoldRoot,
  '-OutRoot',$OutRoot,
  '-TimeoutSeconds',([string]$TimeoutSeconds),
  '-LocalPasteFormat',$LocalPasteFormat,
  '-OutDir',$planOutDir
)
if ($ProjectName) { $planArgs += @('-ProjectName',$ProjectName) }
if ($KvsExe) { $planArgs += @('-KvsExe',$KvsExe) }
if ($ChecklistPath) { $planArgs += @('-ChecklistPath',$ChecklistPath) }
if ($SourceSnapshotManifestPath) { $planArgs += @('-SourceSnapshotManifestPath',$SourceSnapshotManifestPath) }
if ($AuditVariablePersistence) { $planArgs += '-AuditVariablePersistence' }
if ($DeleteExistingModulesBeforeImport) { $planArgs += '-DeleteExistingModulesBeforeImport' }

& powershell @planArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$planPath = Join-Path $planOutDir 'execution_plan.json'
if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw "Execution plan was not created: $planPath" }

& powershell -NoProfile -ExecutionPolicy Bypass -File $runnerTool -PlanPath $planPath -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
