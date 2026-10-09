<#[
.SYNOPSIS
  Copy the KVX sample project and run the fixed, serial regression stages.

.DESCRIPTION
  This is an orchestration workflow. It never implements KV STUDIO UI input
  itself; each UI stage delegates to an existing customer workflow, which owns
  the named desktop mutex and its guarded atomic route. The sample is copied as
  a complete directory before any stage is started. Every stage gets an
  isolated output directory and is merged into the parent run log afterwards.

  The default required stages are the routes with current live evidence:
    1. read-only user structure export
    2. read-only global/local variable snapshot
    3. compile and copy conversion result

  FB declaration snapshot is intentionally opt-in because module placement is
  currently project/window-state sensitive. A failed optional stage never gets
  reported as a core pass.
#>
param(
  [Parameter(Mandatory=$true)][string]$SampleProjectDirectory,
  [string]$OutRoot = '',
  [string]$KvsExe = '',
  [string]$ConfigPath = '',
  [string]$ChecklistPath = '',
  [string]$FbModuleName = 'FB_Cylinder',
  [int]$TimeoutSeconds = 240,
  [switch]$PlanOnly,
  [switch]$NoOpenReplica,
  [switch]$IncludeFbSnapshot
)

$ErrorActionPreference = 'Stop'
$workflowDir = Split-Path -Parent $PSCommandPath
$scriptRoot = Split-Path -Parent $workflowDir
. (Join-Path $scriptRoot 'Resolve-KvStudioOperatorScript.ps1')

function Write-JsonFile([string]$Path, [object]$Value) {
  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-RunLog([string]$Type, [hashtable]$Data = @{}) {
  if (-not $script:RunLogPath) { return }
  $entry = [ordered]@{ timestamp=(Get-Date).ToString('o'); run_id=$script:RunId; type=$Type }
  foreach ($key in $Data.Keys) { $entry[$key] = $Data[$key] }
  [IO.File]::AppendAllText($script:RunLogPath, (($entry | ConvertTo-Json -Compress -Depth 12) + [Environment]::NewLine), [Text.Encoding]::UTF8)
}

function Resolve-ConfiguredKvsExe {
  param([string]$ExplicitPath)
  if ($ExplicitPath) { return [IO.Path]::GetFullPath($ExplicitPath) }
  $loader = Join-Path $scriptRoot 'Import-KvStudioOperatorConfig.ps1'
  if (Test-Path -LiteralPath $loader -PathType Leaf) {
    $cfg = & $loader -ConfigPath $ConfigPath -ScriptRoot $scriptRoot
    if ($cfg.found -and $cfg.kvs_exe) { return [IO.Path]::GetFullPath([string]$cfg.kvs_exe) }
  }
  $skillsRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
  foreach ($candidate in @(
      (Join-Path $skillsRoot 'keyence-plc-programmer\scripts\resolve_kvstudio_local.ps1'),
      (Join-Path $scriptRoot 'resolve_kvstudio_local.ps1'))) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    $resolved = & powershell -NoProfile -ExecutionPolicy Bypass -File $candidate | ConvertFrom-Json
    if ($resolved.KvsExe) { return [IO.Path]::GetFullPath([string]$resolved.KvsExe) }
  }
  return ''
}

function Get-ProjectFile([string]$Directory) {
  $files = @(Get-ChildItem -LiteralPath $Directory -Filter '*.kpr' -File)
  if ($files.Count -ne 1) { throw "KV_SAMPLE_PROJECT_FILE_COUNT_INVALID: expected one .kpr in $Directory, found $($files.Count)" }
  return $files[0].FullName
}

function Get-FileInventory([string]$Directory) {
  @(Get-ChildItem -LiteralPath $Directory -Recurse -File | Sort-Object FullName | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    [ordered]@{ relative_path=$_.FullName.Substring($Directory.TrimEnd('\').Length + 1); length=$_.Length; sha256=$hash }
  })
}

function Merge-ChildLog([string]$StageName, [string]$StageLog) {
  if (-not (Test-Path -LiteralPath $StageLog -PathType Leaf)) { return }
  foreach ($line in [IO.File]::ReadAllLines($StageLog, [Text.Encoding]::UTF8)) {
    if ($line.Trim()) {
      [IO.File]::AppendAllText($script:RunLogPath, (([ordered]@{timestamp=(Get-Date).ToString('o');run_id=$script:RunId;type='child_log';stage=$StageName;child=$line} | ConvertTo-Json -Compress) + [Environment]::NewLine), [Text.Encoding]::UTF8)
    }
  }
}

function Read-StageResult([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { return Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Invoke-Stage {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Stage,
    [Parameter(Mandatory=$true)][string]$ProjectPath
  )
  $stageDir = Join-Path $script:RunRoot ([string]$Stage.name)
  New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
  $workflowPath = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name ([string]$Stage.workflow) -Classes @('customer_workflow')
  $args = @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',$workflowPath,'-ProjectPath',$ProjectPath,'-OutDir',$stageDir,'-TimeoutSeconds',([string]$TimeoutSeconds))
  # Only workflows that expose KvsExe receive it. Structure and variable
  # snapshot routes resolve the configured executable internally; passing an
  # unsupported parameter would fail before their UI guard is reached.
  if ($KvsExe -and $Stage.name -eq 'fb_snapshot') { $args += @('-KvsExe',$KvsExe) }
  if ($ChecklistPath) { $args += @('-ChecklistPath',$ChecklistPath) }
  if ($Stage.name -eq 'fb_snapshot') { $args += @('-FbModuleName',$FbModuleName,'-SnapshotOnly') }
  if ($Stage.name -eq 'variables_snapshot') { $args += '-SnapshotOnly' }
  if ($PlanOnly) { $args += '-PlanOnly' }
  $stdout = Join-Path $stageDir 'workflow_stdout.txt'
  $stderr = Join-Path $stageDir 'workflow_stderr.txt'
  $start = Get-Date
  Write-RunLog 'stage_started' @{stage=$Stage.name;workflow=$workflowPath;project_path=$ProjectPath;out_dir=$stageDir}
  if ($PlanOnly) {
    & powershell @args *> $stdout
    $exitCode = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
  } else {
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $deadline = (Get-Date).AddSeconds([math]::Max(1,$TimeoutSeconds + 15))
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
    if (-not $process.HasExited) {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      $exitCode = -2
    } else { $process.WaitForExit(); $exitCode = [int]$process.ExitCode }
  }
  $resultPath = Join-Path $stageDir ([string]$Stage.result_name)
  if ($Stage.name -eq 'compile') { $resultPath = Join-Path $stageDir 'workflow_result.json' }
  $result = Read-StageResult $resultPath
  $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds,3)
  $ok = if ($PlanOnly) { $true } else { ($exitCode -eq 0 -and $result -and [bool]$result.ok) }
  $status = if ($ok) { 'pass' } elseif ($PlanOnly) { 'planned' } else { 'fail' }
  Merge-ChildLog $Stage.name (Join-Path $stageDir 'run.log')
  $record = [ordered]@{name=$Stage.name;classification=[string]$Stage.classification;workflow=$workflowPath;result_path=$resultPath;out_dir=$stageDir;exit_code=$exitCode;ok=[bool]$ok;status=$status;elapsed_seconds=$elapsed;error_code=if($result -and $result.error_code){[string]$result.error_code}else{if($ok){''}else{'KV_SAMPLE_STAGE_FAILED'}};message=if($result -and $result.message){[string]$result.message}else{''}}
  Write-JsonFile (Join-Path $stageDir 'stage_summary.json') $record
  Write-RunLog $(if($ok){'stage_succeeded'}else{'stage_failed'}) @{stage=$Stage.name;status=$status;exit_code=$exitCode;elapsed_seconds=$elapsed;error_code=$record.error_code}
  return [pscustomobject]$record
}

$script:RunId = [guid]::NewGuid().ToString('N')
$source = [IO.Path]::GetFullPath($SampleProjectDirectory)
if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "KV_SAMPLE_DIRECTORY_MISSING: $source" }
$sourceProject = Get-ProjectFile $source
if (-not $OutRoot) { $OutRoot = Join-Path ([IO.Path]::GetTempPath()) 'kv-studio-operator\sample_regressions' }
$script:RunRoot = Join-Path ([IO.Path]::GetFullPath($OutRoot)) ($script:RunId)
New-Item -ItemType Directory -Force -Path $script:RunRoot | Out-Null
$script:RunLogPath = Join-Path $script:RunRoot 'run.log'
Write-RunLog 'workflow_started' @{source_directory=$source;source_project=$sourceProject;plan_only=[bool]$PlanOnly}

$replica = Join-Path $script:RunRoot 'replica'
New-Item -ItemType Directory -Force -Path $replica | Out-Null
$replicaDirectory = Join-Path $replica (Split-Path -Leaf $source)
New-Item -ItemType Directory -Force -Path $replicaDirectory | Out-Null
Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $replicaDirectory -Recurse -Force
$replicaProject = Get-ProjectFile $replicaDirectory
$sourceInventory = Get-FileInventory $source
$replicaInventory = Get-FileInventory $replicaDirectory
Write-JsonFile (Join-Path $script:RunRoot 'sample_replica_manifest.json') ([ordered]@{ok=$true;run_id=$script:RunId;source_directory=$source;replica_directory=$replicaDirectory;source_project=$sourceProject;replica_project=$replicaProject;file_count=$sourceInventory.Count;source_files=$sourceInventory;replica_files=$replicaInventory})
Write-RunLog 'sample_copied' @{replica_directory=$replicaDirectory;replica_project=$replicaProject;file_count=$sourceInventory.Count}

if (-not $NoOpenReplica -and -not $PlanOnly) {
  $exe = Resolve-ConfiguredKvsExe $KvsExe
  if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "KV_KVS_EXE_MISSING: $exe" }
  Write-RunLog 'replica_open_requested' @{kvs_exe=$exe;project_path=$replicaProject}
  Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -ArgumentList ('"' + $replicaProject + '"') | Out-Null
  Start-Sleep -Seconds 2
}

$stages = @(
  @{name='structures_snapshot';classification='required_readonly';workflow='workflows/export_kv_structure_definitions.ps1';result_name='workflow_result.json'},
  @{name='variables_snapshot';classification='required_readonly';workflow='workflows/set_kv_variables.ps1';result_name='variable_workflow_result.json'},
  @{name='compile';classification='required_readonly';workflow='workflows/compile_kv_project.ps1';result_name='workflow_result.json'}
)
if ($IncludeFbSnapshot) { $stages += @{name='fb_snapshot';classification='optional_unproven';workflow='workflows/set_kv_fb_arguments.ps1';result_name='fb_declaration_workflow_result.json'} }

$stageResults = @()
if ($PlanOnly) {
  foreach ($stage in $stages) { $stageResults += Invoke-Stage $stage $replicaProject }
} else {
  foreach ($stage in $stages) {
    $stageResults += Invoke-Stage $stage $replicaProject
    if ($stage.classification -eq 'required_readonly' -and -not $stageResults[-1].ok) { break }
  }
}
$required = @($stageResults | Where-Object { $_.classification -eq 'required_readonly' })
$requiredOk = ($required.Count -eq 3 -and @($required | Where-Object { -not $_.ok }).Count -eq 0)
$optionalFailures = @($stageResults | Where-Object { $_.classification -eq 'optional_unproven' -and -not $_.ok })
$status = if ($PlanOnly) { 'planned' } elseif ($requiredOk -and $optionalFailures.Count -eq 0) { 'pass' } elseif ($requiredOk) { 'pass_with_known_gaps' } else { 'fail' }
$final = [ordered]@{ok=($PlanOnly -or $status -eq 'pass' -or $status -eq 'pass_with_known_gaps');status=$status;execution_mode=if($PlanOnly){'plan_only'}else{'live_serial'};run_id=$script:RunId;source_directory=$source;replica_directory=$replicaDirectory;replica_project=$replicaProject;required_stage_count=3;required_stages_passed=@($required | Where-Object {$_.ok}).Count;stages=$stageResults;run_log_path=$script:RunLogPath;replica_manifest_path=(Join-Path $script:RunRoot 'sample_replica_manifest.json');code_fingerprint_path=(Join-Path $script:RunRoot 'code_fingerprint.json')}
$fingerprintFiles = @($scriptRoot, (Join-Path $scriptRoot 'script_manifest.json'))
$fingerprints = @()
foreach ($dir in $fingerprintFiles) {
  if (Test-Path -LiteralPath $dir -PathType Container) { $fingerprints += Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.ps1' -File | ForEach-Object { [ordered]@{path=$_.FullName.Substring($scriptRoot.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} } }
  elseif (Test-Path -LiteralPath $dir -PathType Leaf) { $fingerprints += [ordered]@{path=$dir;sha256=(Get-FileHash -LiteralPath $dir -Algorithm SHA256).Hash} }
}
Write-JsonFile $final.code_fingerprint_path $fingerprints
Write-JsonFile (Join-Path $script:RunRoot 'sample_regression_result.json') $final
Write-RunLog 'workflow_finished' @{status=$status;ok=[bool]$final.ok;required_stages_passed=$final.required_stages_passed}
$final | ConvertTo-Json -Depth 16
if ($final.ok) { exit 0 } else { exit 1 }
