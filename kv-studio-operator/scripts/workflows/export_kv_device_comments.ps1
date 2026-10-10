param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$CommentsDir='',
  [string]$ProgramName='',
  [string]$FileBaseName='',
  [string]$CreatedProjectResultPath='',
  [int]$TimeoutSeconds=180,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'export_device_comments' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
$dest=Join-Path $plan.artifact_root 'comments'
$targetDir=if($CommentsDir){[IO.Path]::GetFullPath($CommentsDir)}else{$dest}
Add-KvWorkflowStep -Plan $plan -Name 'export_device_comments' -Script 'runner_children/export_device_comments_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$plan.project_path;ExportDir=$targetDir;OutDir=$dest;CreatedProjectResultPath=$CreatedProjectResultPath;ProgramName=$ProgramName;FileBaseName=$FileBaseName;CloseProjectWhenLaunched=$true;TimeoutSeconds=90}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
