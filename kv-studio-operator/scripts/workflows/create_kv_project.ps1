param(
  [Parameter(Mandatory=$true)][string]$ProjectName,
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$CpuModel,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$KvsExe='',
  [string]$AdminCredentialPath='',
  [string]$ChecklistPath='',
  [int]$TimeoutSeconds=120,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
if ($ProjectName -match '[/\\]' -or $ProjectName -in @('.','..')) { throw 'KV_PROJECT_NAME_INVALID' }
$ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot)
$target=Join-Path (Join-Path $ProjectRoot $ProjectName) ($ProjectName+'.kpr')
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'create_project' -ProjectPath $target -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds -NewProject
$dest=Join-Path $plan.artifact_root 'create'
Add-KvWorkflowStep -Plan $plan -Name 'create_project' -Script 'runner_children/create_project_local_guarded.ps1' -OutDir $dest -Parameters @{ProjectName=$ProjectName;ProjectRoot=$ProjectRoot;CpuModel=$CpuModel;OutDir=$dest;KvsExe=$KvsExe;AdminCredentialPath=$AdminCredentialPath;ChecklistPath=$ChecklistPath;TimeoutSeconds=$TimeoutSeconds}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
