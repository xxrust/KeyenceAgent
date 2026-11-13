param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,

  # CSV/TXT comment table produced by export_kv_device_comments.ps1 and then
  # completed/extended (same shape; GBK / system ANSI code page).
  [Parameter(Mandatory=$true)][string]$CommentsPath,

  [Parameter(Mandatory=$true)][string]$OutDir,

  [int]$TimeoutSeconds = 600,
  [switch]$NoSave,
  [switch]$KeepProjectOpen,
  [switch]$PlanOnly
)

# Read a device-comment table into an existing project and prove it landed.
#
# Steps
#   1. import_device_comments  - File(F) > "read device comments in CSV/TXT format (Q)"
#                                via the guarded runner, then Ctrl+S so the comment
#                                bank reaches <project>.cm1
#   2. export_device_comments  - re-export the table from the *same* project
#   3. verify                  - non-UI diff: every device/comment that the input
#                                promised must be readable again from the project
#
# Step 3 is what makes the result trustworthy: an import that "returned 0" but
# wrote nothing is reported as a verification failure, not as success.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')

$CommentsPath = [IO.Path]::GetFullPath($CommentsPath)
$OutDir = [IO.Path]::GetFullPath($OutDir)
$plan = New-KvWorkflowPlan -ScriptsRoot $root -Operation 'import_device_comments' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds

$importOut = Join-Path $plan.artifact_root 'comments_import'
$exportOut = Join-Path $plan.artifact_root 'comments_reexport'
$verifyOut = Join-Path $plan.artifact_root 'comments_verify'
$reexportDir = Join-Path $plan.artifact_root 'comments_reexport_csv'

Add-KvWorkflowStep -Plan $plan -Name 'import_device_comments' `
  -Script 'runner_children/import_device_comments_guarded.ps1' -OutDir $importOut `
  -Parameters @{
    ProjectPath             = $plan.project_path
    CommentsPath            = $CommentsPath
    OutDir                  = $importOut
    SaveAfterImport         = (-not $NoSave)
    CloseProjectWhenLaunched = $false
    TimeoutSeconds          = 120
  }

Add-KvWorkflowStep -Plan $plan -Name 'export_device_comments' `
  -Script 'runner_children/export_device_comments_guarded.ps1' -OutDir $exportOut `
  -Parameters @{
    ProjectPath             = $plan.project_path
    ExportDir               = $reexportDir
    OutDir                  = $exportOut
    FileBaseName            = 'kv_comments_reexport'
    CloseProjectWhenLaunched = (-not $KeepProjectOpen)
    TimeoutSeconds          = 120
  }

Add-KvWorkflowStep -Plan $plan -Name 'verify_comments' -Class workflow_tool `
  -Script 'workflow_tools/verify_kv_device_comments_import.ps1' -OutDir $verifyOut `
  -Parameters @{
    ExpectedCsv = $CommentsPath
    ActualCsv   = (Join-Path $reexportDir 'kv_comments_reexport.csv')
    OutDir      = $verifyOut
  }

Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
