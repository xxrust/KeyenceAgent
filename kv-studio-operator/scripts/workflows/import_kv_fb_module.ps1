param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$MnmPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$ExpectedModuleName = '',
  [string]$KvsExe = '',
  [string]$ChecklistPath = '',
  [int]$TimeoutSeconds = 120,
  [switch]$DeleteExistingModuleBeforeImport,
  [switch]$RestartKvs,
  [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
$workflowScriptDir = Split-Path -Parent $PSCommandPath
$resolver = Join-Path (Split-Path -Parent $workflowScriptDir) 'Resolve-KvStudioOperatorScript.ps1'
if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) { throw "Script resolver not found: $resolver" }
. $resolver
$scriptRoot = Get-KvStudioOperatorScriptsRoot -StartPath $PSCommandPath

function Read-MnmHeader([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $text = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
    [Text.Encoding]::Unicode.GetString($bytes)
  } elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    [Text.Encoding]::UTF8.GetString($bytes)
  } else {
    [Text.Encoding]::Default.GetString($bytes)
  }
  $name = ''
  $moduleType = ''
  foreach ($line in ($text -split "(`r`n|`n|`r)")) {
    $trimmed = ([string]$line).Trim()
    if ($trimmed -match '^;MODULE:(.+)$') { $name = $matches[1].Trim() }
    elseif ($trimmed -match '^;MODULE_TYPE:(\d+)$') { $moduleType = $matches[1] }
    if ($name -and $moduleType) { break }
  }
  [pscustomobject]@{ name = $name; module_type = $moduleType }
}

$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$MnmPath = [IO.Path]::GetFullPath($MnmPath)
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
function Write-ApiPreflight([bool]$Ok, [string]$ErrorCode = '', [string]$Message = '') {
  [ordered]@{
    ok = $Ok; operation = 'import_kv_fb_module preflight'; error_code = $ErrorCode; message = $Message
    project_path = $ProjectPath; mnm_path = $MnmPath; timestamp = (Get-Date).ToString('o')
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'fb_import_preflight.json') -Encoding UTF8
}
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "ProjectPath not found: $ProjectPath" }
if (-not (Test-Path -LiteralPath $MnmPath -PathType Leaf)) { throw "MnmPath not found: $MnmPath" }
$header = Read-MnmHeader $MnmPath
if ([string]$header.module_type -ne '2') {
  $message = 'KV_FB_MNM_MODULE_TYPE_REQUIRED: FB import requires ;MODULE_TYPE:2.'
  Write-ApiPreflight $false 'KV_FB_MNM_MODULE_TYPE_REQUIRED' $message
  throw $message
}
if (-not $ExpectedModuleName) { $ExpectedModuleName = [string]$header.name }
if (-not $ExpectedModuleName) { $ExpectedModuleName = [IO.Path]::GetFileNameWithoutExtension($MnmPath) }
Write-ApiPreflight $true '' ('FB MNM accepted: '+$ExpectedModuleName)

$runnerTool = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name 'invoke_kv_flat_execution_plan.ps1' -Classes @('workflow_tool')
$runRoot = $OutDir
$artifactRoot = Join-Path $runRoot 'artifacts'
$gateUiOut = Join-Path $artifactRoot 'ui_guard_usage'
$gateBoundaryOut = Join-Path $artifactRoot 'agent_boundary'
$importOut = Join-Path $artifactRoot 'import_mnm'
$resultPath = Join-Path $runRoot 'fb_import_result.json'
$planPath = Join-Path $runRoot 'execution_plan.json'
New-Item -ItemType Directory -Force -Path $runRoot, $artifactRoot | Out-Null

$steps = [System.Collections.Generic.List[object]]::new()
$steps.Add([ordered]@{
  name = 'assert_ui_guard_usage'; kind = 'gate'; script_name = 'assert_kv_mvp_ui_guard_usage.ps1'; classes = @('gate')
  arguments = @('-ScriptsRoot',$scriptRoot,'-OutDir',$gateUiOut); out_dir = $gateUiOut
})
$steps.Add([ordered]@{
  name = 'assert_agent_boundary'; kind = 'gate'; script_name = 'assert_kv_mvp_agent_boundary.ps1'; classes = @('gate')
  arguments = @('-ScriptsRoot',$scriptRoot,'-MvpScriptsRoot',(Join-Path $scriptRoot 'runner_children'),'-OutDir',$gateBoundaryOut); out_dir = $gateBoundaryOut
})
$importArgs = [System.Collections.Generic.List[string]]::new()
foreach ($pair in @(@('-MnmPath',$MnmPath),@('-ProjectPath',$ProjectPath),@('-OutDir',$importOut),@('-ExpectedModuleName',$ExpectedModuleName),@('-ExpectedCategory','function_block'),@('-ChecklistPath',$ChecklistPath))) {
  if ($pair[1]) { $importArgs.Add($pair[0]); $importArgs.Add($pair[1]) }
}
$importArgs.Add('-SaveAfterImport')
if ($KvsExe) { $importArgs.Add('-KvsExe'); $importArgs.Add($KvsExe) }
if ($DeleteExistingModuleBeforeImport) { $importArgs.Add('-DeleteExistingModuleBeforeImport') }
$importArgs.Add('-RestartKvs')
$importArgs.Add(([bool]$RestartKvs).ToString())
$steps.Add([ordered]@{
  name = 'import_fb_mnm'; kind = 'runner_child'; script_name = 'import_mnm_guarded.ps1'; classes = @('runner_child_approved')
  arguments = @($importArgs); out_dir = $importOut
})
$placementOut=Join-Path $artifactRoot 'module_placement'
$steps.Add([ordered]@{
  name='verify_fb_placement';kind='tool';script_name='workflow_tools/assert_kv_module_placement.ps1';classes=@('workflow_tool');out_dir=$placementOut
  arguments=@('-ProjectTreePath',(Join-Path (Split-Path -Parent $ProjectPath) 'WsTreeEnv.xml'),'-ModuleName',$ExpectedModuleName,'-Category','function_block','-OutDir',$placementOut)
})

$plan = [ordered]@{
  ok = $true; schema_version = 1; operation = 'import_kv_fb_module'; project_path = $ProjectPath; project_name = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  scaffold_root = ''; scaffold_manifest = ''; project_needle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  run_root = $runRoot; artifact_root = $artifactRoot; result_path = $resultPath; checklist_path = $ChecklistPath; timeout_seconds = $TimeoutSeconds
  require_compile_result = $false; compile_result_path = ''; mnm_files = @([ordered]@{ path = $MnmPath; module_name = $ExpectedModuleName; module_type = 2; category = 'function_block' }); variable_sets = @(); steps = @($steps)
}
$plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $planPath -Encoding UTF8
if ($PlanOnly) {
  [ordered]@{ ok=$true; operation='import_kv_fb_module plan'; plan_path=$planPath; project_path=$ProjectPath; mnm_path=$MnmPath; expected_module_name=$ExpectedModuleName; ui_started=$false } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runRoot 'fb_import_plan_result.json') -Encoding UTF8
  exit 0
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $runnerTool -PlanPath $planPath -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
