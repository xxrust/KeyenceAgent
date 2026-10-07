param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$MnmPath,
  [Parameter(Mandatory=$true)][string]$ModuleName,
  [ValidateSet('scan','function_block')][string]$Category='scan',
  [string[]]$ParentPath=@(),
  [string]$CreatedProjectResultPath='',
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds=180,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$MnmPath=[IO.Path]::GetFullPath($MnmPath)
$OutDir=[IO.Path]::GetFullPath($OutDir)
$inputs=@{ProjectPath=$ProjectPath;MnmPath=$MnmPath;ModuleName=$ModuleName;Category=$Category;ParentPath=$ParentPath}
& (Join-Path $root 'gates/assert_kv_module_import.ps1') @inputs -OutDir (Join-Path $OutDir 'preflight')
if ($LASTEXITCODE -ne 0) { throw 'KV_MODULE_IMPORT_PREFLIGHT_FAILED' }
$checked=Get-Content -LiteralPath (Join-Path $OutDir 'preflight/module_import_preflight_result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ParentPath=@($checked.parent_path)
$inputs.ParentPath=$ParentPath
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'import_kv_module' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
$dest=Join-Path $plan.artifact_root 'module_contract'
$parameters=$inputs.Clone();$parameters.OutDir=$dest
Add-KvWorkflowStep -Plan $plan -Name 'module_contract' -Script 'gates/assert_kv_module_import.ps1' -Class gate -OutDir $dest -Parameters $parameters
$dest=Join-Path $plan.artifact_root 'import'
Add-KvWorkflowStep -Plan $plan -Name 'import' -Script 'runner_children/import_mnm_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$ProjectPath;MnmPath=$MnmPath;ExpectedModuleName=$ModuleName;ExpectedCategory=$Category;ParentPath=$ParentPath;CreatedProjectResultPath=$CreatedProjectResultPath;OutDir=$dest;SaveAfterImport=$true;RestartKvs=$false}
$dest=Join-Path $plan.artifact_root 'placement'
Add-KvWorkflowStep -Plan $plan -Name 'placement' -Script 'workflow_tools/assert_kv_module_placement.ps1' -Class workflow_tool -OutDir $dest -Parameters @{ProjectTreePath=(Join-Path (Split-Path -Parent $ProjectPath) 'WsTreeEnv.xml');ModuleName=$ModuleName;Category=$Category;OutDir=$dest}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
