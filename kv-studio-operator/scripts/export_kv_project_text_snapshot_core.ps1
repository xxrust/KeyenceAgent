<#!
.SYNOPSIS
  Export a KV STUDIO project into a version-control friendly, text-first snapshot.
.DESCRIPTION
  This is the composition entry point for Agent review. It keeps the existing
  source_snapshot layout and delegates UI reads to the existing read-only
  workflows: MNM export, variable snapshot, structure snapshot and project
  inventory. Every run gets an isolated directory, a project fingerprint and a
  deterministic text index. Missing UI capabilities are recorded explicitly;
  the script never invents values from binary project files.
#>
param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$SnapshotId = '',
  [int]$TimeoutSeconds = 600,
  [switch]$PlanOnly,
  # Resume: reuse completed stages recorded in <snapshot>/snapshot_state.json
  # when the project fingerprint and the stage inputs are unchanged.
  [switch]$Resume,
  # Ordinary program local tables are captured by default. Pass an explicit
  # list to limit the run, or -SkipProgramLocals for the old FB-only behavior.
  [string[]]$ProgramLocalModules = @(),
  [switch]$SkipProgramLocals,
  [switch]$KeepProjectOpen
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath

function Full([string]$Path) { [IO.Path]::GetFullPath($Path) }
function Write-Json([string]$Path,[object]$Value,[int]$Depth=20) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Rel([string]$Base,[string]$Path) {
  $b=(Full $Base).TrimEnd('\')+'\'; $p=Full $Path
  [Uri]::UnescapeDataString(([Uri]$b).MakeRelativeUri([Uri]$p).ToString()).Replace('/','\')
}
function Fingerprint([string]$Root) {
  $entries = foreach($f in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Where-Object {$_.FullName -notmatch '\\.git\\'} | Sort-Object FullName)) {
    [pscustomobject]@{path=(Rel $Root $f.FullName);length=$f.Length;sha256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
  }
  $lines = ($entries | ForEach-Object { "$($_.path)`t$($_.length)`t$($_.sha256)`n" }) -join ''
  $bytes=[Text.Encoding]::UTF8.GetBytes($lines); $hash=([Security.Cryptography.SHA256]::Create().ComputeHash($bytes) | ForEach-Object {$_.ToString('x2')}) -join ''
  [ordered]@{algorithm='sha256-of-relative-path-length-file-sha256';root=$Root;hash=$hash;file_count=$entries.Count;files=@($entries)}
}
function Get-StageInputHash([string]$Script,[string[]]$Arguments) {
  $scriptHash = if($Script -and (Test-Path -LiteralPath $Script -PathType Leaf)) { (Get-FileHash -LiteralPath $Script -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
  # Volatile arguments must not invalidate a completed stage: the MNM export uses
  # a fresh temporary WorkRoot each run, and a longer timeout does not change the
  # produced artifacts.
  $stable=New-Object System.Collections.Generic.List[string]
  $skipNext=$false
  foreach($argument in @($Arguments)){
    if($skipNext){ $skipNext=$false; continue }
    if([string]$argument -in @('-WorkRoot','-TimeoutSeconds')){ $skipNext=$true; continue }
    $stable.Add([string]$argument)
  }
  $material = @($scriptHash, [string]$fingerprint.hash, ($stable -join "`u{1}")) -join "`u{2}"
  $bytes=[Text.Encoding]::UTF8.GetBytes($material)
  (([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)) | ForEach-Object {$_.ToString('x2')}) -join ''
}
function Save-SnapshotState {
  if($PlanOnly -or -not $script:snapshotState){ return }
  $script:snapshotState.updated_at=(Get-Date).ToUniversalTime().ToString('o')
  Write-Json $script:snapshotStatePath $script:snapshotState 20
}
function Test-StageReusable([string]$Label,[string]$InputHash) {
  $script:lastResumeReason='unknown'
  if(-not $Resume){ $script:lastResumeReason='resume_disabled'; return $null }
  if($script:resumeInvalidated){ $script:lastResumeReason='fingerprint_changed'; return $null }
  $uiStages=@('mnm_export','device_comments','structure_export','variables_snapshot','program_variables')
  if(($Label -in $uiStages) -or ($Label -like 'fb_variables_*') -or ($Label -like 'fb_arguments_*')){
    $uiCopy=[string]$script:snapshotState.ui_project_path
    if(-not $uiCopy -or -not (Test-Path -LiteralPath $uiCopy -PathType Leaf)){ $script:lastResumeReason='ui_copy_missing'; return $null }
  }
  $stage=$script:snapshotState.stages[$Label]
  if(-not $stage){ $script:lastResumeReason='stage_absent'; return $null }
  if([string]$stage.input_hash -ne $InputHash){ $script:lastResumeReason='input_changed'; return $null }
  if([string]$stage.status -notin @('completed','reused','skipped')){ $script:lastResumeReason='status_not_reusable'; return $null }
  if($stage.ok -ne $true){ $script:lastResumeReason='not_ok'; return $null }
  if($stage.result_path -and -not (Test-Path -LiteralPath ([string]$stage.result_path) -PathType Leaf)){ $script:lastResumeReason='result_missing'; return $null }
  $script:lastResumeReason='reused'
  return $stage
}
function Set-StageRequiresPath([string]$Label,[string[]]$Paths) {
  if($PlanOnly){ return }
  $stage=$script:snapshotState.stages[$Label]
  if(-not $stage){ return }
  Save-SnapshotState
}
function Set-StageSkipped([string]$Label,[string]$Reason) {
  if($PlanOnly){ return }
  $stage=$script:snapshotState.stages[$Label]
  if(-not $stage){ return }
  $stage.status='skipped'; $stage.ok=$true; $stage.reason=$Reason
  Save-SnapshotState
}
function Invoke-Child([string]$Script,[string[]]$Arguments,[string]$ResultPath,[string]$Label,[string[]]$ResetPaths = @()) {
  $request=[ordered]@{label=$Label;script=$Script;arguments=$Arguments;result_path=$ResultPath;plan_only=[bool]$PlanOnly}
  Write-Json (Join-Path $rawRoot ($Label+'_request.json')) $request 10
  if($PlanOnly){ return [ordered]@{ok=$true;status='planned';label=$Label;result_path=$ResultPath} }
  $inputHash=Get-StageInputHash $Script $Arguments
  $reusable=Test-StageReusable $Label $inputHash
  try { [IO.File]::AppendAllText((Join-Path $rawRoot 'resume_decisions.jsonl'), ((@{label=$Label;reused=[bool]$reusable;reason=$script:lastResumeReason;input_hash=$inputHash} | ConvertTo-Json -Compress) + [Environment]::NewLine)) } catch {}
  if($reusable){
    $saved=$null
    if(Test-Path -LiteralPath $ResultPath -PathType Leaf){ try{$saved=Get-Content -Raw -LiteralPath $ResultPath -Encoding UTF8|ConvertFrom-Json}catch{} }
    $script:reusedStages += $Label
    return [ordered]@{ok=$true;status='reused';label=$Label;exit_code=0;result_path=$ResultPath;result=$saved;reused=$true}
  }
  foreach($resetPath in @($ResetPaths)){
    if($resetPath -and (Test-Path -LiteralPath $resetPath)){ Remove-Item -LiteralPath $resetPath -Recurse -Force -ErrorAction SilentlyContinue }
  }
  & powershell -STA -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments *> (Join-Path $rawRoot ($Label+'_stdout.txt'))
  $exit=if($LASTEXITCODE -is [int]){[int]$LASTEXITCODE}else{0}
  $result=$null
  if(Test-Path -LiteralPath $ResultPath -PathType Leaf){try{$result=Get-Content -Raw -LiteralPath $ResultPath -Encoding UTF8|ConvertFrom-Json}catch{}}
  $status=if($exit -eq 0){'completed'}else{'failed'}
  $script:snapshotState.stages[$Label]=[ordered]@{
    status=$status; ok=($exit -eq 0 -and $result -and $result.ok -eq $true); exit_code=$exit; input_hash=$inputHash
    result_path=$ResultPath; requires_paths=@(); updated_at=(Get-Date).ToUniversalTime().ToString('o')
  }
  Save-SnapshotState
  [ordered]@{ok=($exit -eq 0 -and $result -and $result.ok -eq $true);status=$status;label=$Label;exit_code=$exit;result_path=$ResultPath;result=$result}
}
function Get-KvsExe {
  $loader=Join-Path $scriptRoot 'Import-KvStudioOperatorConfig.ps1'
  # Invoke the loader in this PowerShell process, like the shared regression
  # runner does. A child PowerShell serializes the returned object to display
  # text, so `$cfg.kvs_exe` would incorrectly become empty.
  $cfg=& $loader -ScriptRoot $scriptRoot
  if($cfg -and $cfg.kvs_exe){return [IO.Path]::GetFullPath([string]$cfg.kvs_exe)}
  throw 'KV_TEST_KVS_EXE_NOT_CONFIGURED'
}
function Open-Project([string]$Path) {
  $exe=Get-KvsExe; if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw "KV_TEST_KVS_EXE_MISSING: $exe"}
  $needle=[IO.Path]::GetFileNameWithoutExtension($Path)
  $existing=@(Get-Process Kvs -ErrorAction SilentlyContinue|Where-Object {$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like "*$needle*"})
  if($existing.Count -gt 0){throw 'KV_TEST_PROJECT_ALREADY_OPEN'}
  $proc=Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -ArgumentList ('"'+$Path+'"') -PassThru
  $deadline=(Get-Date).AddSeconds(45)
  do{$p=Get-Process -Id $proc.Id -ErrorAction SilentlyContinue;if(-not $p){throw "KV_TEST_PROJECT_PROCESS_EXITED: $needle"};$w=@(Get-Process Kvs -ErrorAction SilentlyContinue|Where-Object {$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like "*$needle*"});if($w.Count -eq 1){return [pscustomobject]@{process=$p;window=$w[0]}};Start-Sleep -Milliseconds 250}while((Get-Date)-lt $deadline)
  throw "KV_TEST_PROJECT_WINDOW_TIMEOUT: $needle"
}
function Copy-SnapshotFiles([object[]]$Paths,[string]$Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $copied=@()
  foreach($pathValue in @($Paths|Where-Object {$_})){
    $source=[string]$pathValue
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){continue}
    $target=Join-Path $Destination ([IO.Path]::GetFileName($source)); Copy-Item -LiteralPath $source -Destination $target -Force; $copied+=$target
  }
  @($copied)
}

$ProjectPath=Full $ProjectPath; $OutDir=Full $OutDir
if(-not(Test-Path -LiteralPath $ProjectPath -PathType Leaf)){throw "ProjectPath not found: $ProjectPath"}
$projectRoot=Split-Path -Parent $ProjectPath
if(-not $SnapshotId){$SnapshotId='snapshot_'+(Get-Date -Format 'yyyyMMdd_HHmmss')}
$snapshotRoot=Join-Path $OutDir $SnapshotId
$rawRoot=Join-Path $snapshotRoot 'raw'; $textRoot=Join-Path $snapshotRoot 'text'; $architectureRoot=Join-Path $snapshotRoot 'architecture'
New-Item -ItemType Directory -Force -Path $rawRoot,$textRoot,$architectureRoot | Out-Null
$fingerprint=Fingerprint $projectRoot
$planPath=Join-Path $snapshotRoot 'snapshot_plan.json'
$uiProjectPath=$ProjectPath
$uiProcessId=0
$uiLifecycle=[ordered]@{
  strategy='single_isolated_project_copy';source_project_path=$ProjectPath;source_preopened=$false
  launch_owner='export_mnm_project_copy_default_folder';ui_project_path='';process_id=0
  launched_by_runner=$false;stopped_process_ids=@();reused_by=@('structure_definitions','variables','fb_arguments')
  keep_source_project_open=[bool]$KeepProjectOpen;cleanup_status='pending'
}
$mnmWorkRoot=''
$exitCode=1
$snapshotReady=$false
$snapshotStatePath=Join-Path $snapshotRoot 'snapshot_state.json'
$script:snapshotStatePath=$snapshotStatePath
$script:reusedStages=@()
$script:resumeInvalidated=$false
$script:snapshotState=[ordered]@{
  schema_version=1; snapshot_id=$SnapshotId; project_path=$ProjectPath; project_fingerprint=$fingerprint.hash
  updated_at=''; resumed=[bool]$Resume; ui_project_path=''; stages=[ordered]@{}
}
if($Resume){
  if(-not(Test-Path -LiteralPath $snapshotStatePath -PathType Leaf)){ throw "KV_SNAPSHOT_RESUME_STATE_MISSING: $snapshotStatePath" }
  $loadedState=Get-Content -Raw -LiteralPath $snapshotStatePath -Encoding UTF8 | ConvertFrom-Json
  if([string]$loadedState.project_fingerprint -ne [string]$fingerprint.hash){
    $script:resumeInvalidated=$true
    Write-Json (Join-Path $rawRoot 'resume_invalidated.json') ([ordered]@{reason='project_fingerprint_changed';previous=[string]$loadedState.project_fingerprint;current=[string]$fingerprint.hash}) 4
  } else {
    $script:snapshotState.ui_project_path=[string]$loadedState.ui_project_path
    foreach($property in $loadedState.stages.PSObject.Properties){
      $stage=[ordered]@{}
      foreach($field in $property.Value.PSObject.Properties){ $stage[$field.Name]=$field.Value }
      $script:snapshotState.stages[$property.Name]=$stage
    }
  }
}

try {
$inventoryInitial=Join-Path $rawRoot 'inventory_initial'
$inventoryInitialResult=Join-Path $inventoryInitial 'project_inventory.json'
$inventoryArgs=@('-ProjectPath',$ProjectPath,'-OutDir',$inventoryInitial)
$inventoryStep=Invoke-Child (Join-Path $scriptRoot 'export_kv_project_inventory.ps1') $inventoryArgs $inventoryInitialResult 'inventory_initial' -ResetPaths @($inventoryInitial)
$initial=$null; if(Test-Path $inventoryInitialResult){try{$initial=Get-Content -Raw $inventoryInitialResult|ConvertFrom-Json}catch{}}

$mnmOut=Join-Path $rawRoot 'mnm'; $mnmExportDir=Join-Path $rawRoot 'mnm_export'; $mnmTextDir=Join-Path $textRoot 'mnm'
$mnmWorkflow=Join-Path $scriptRoot 'workflows\export_mnm_project_copy_default_folder.ps1'
$mnmResult=Join-Path $mnmOut 'export_mnm_project_copy_result.json'
$mnmWorkRoot=Join-Path ([IO.Path]::GetTempPath()) ('kv_mnm_snapshot_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$mnmArgs=@('-ProjectPath',$ProjectPath,'-ExportDir',$mnmExportDir,'-OutDir',$mnmOut,'-WorkRoot',$mnmWorkRoot,'-AllowWorkRootOutsideExportDir','-AllowOverwrite','-TimeoutSeconds',[string]$TimeoutSeconds)
$mnmStep=Invoke-Child $mnmWorkflow $mnmArgs $mnmResult 'mnm_export' -ResetPaths @($mnmExportDir)
$mnmWorkspacePlanPath=Join-Path $mnmOut 'artifacts\export_workspace\export_workspace_plan.json'
if(Test-Path -LiteralPath $mnmWorkspacePlanPath -PathType Leaf){
  try{
    $mnmWorkspacePlan=Get-Content -Raw -LiteralPath $mnmWorkspacePlanPath -Encoding UTF8|ConvertFrom-Json
    if($mnmWorkspacePlan.project_copy_path){$uiProjectPath=Full ([string]$mnmWorkspacePlan.project_copy_path)}
    if($mnmWorkspacePlan.core_result_path -and (Test-Path -LiteralPath ([string]$mnmWorkspacePlan.core_result_path) -PathType Leaf)){
      $mnmCoreResult=Get-Content -Raw -LiteralPath ([string]$mnmWorkspacePlan.core_result_path) -Encoding UTF8|ConvertFrom-Json
      $uiProcessId=[int]$mnmCoreResult.process_id
      $uiLifecycle.launched_by_runner=[bool]$mnmCoreResult.launched_by_runner
      $uiLifecycle.stopped_process_ids=@($mnmCoreResult.stopped_process_ids)
    }
  }catch{}
}
$uiLifecycle.ui_project_path=$uiProjectPath
$uiLifecycle.process_id=$uiProcessId
$script:snapshotState.ui_project_path=$uiProjectPath
if($mnmStep.ok){ Save-SnapshotState }
if($mnmStep.ok){
  New-Item -ItemType Directory -Force -Path $mnmTextDir | Out-Null
  foreach($f in @(Get-ChildItem -LiteralPath $mnmExportDir -Filter '*.mnm' -File -Recurse -ErrorAction SilentlyContinue)){ Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $mnmTextDir $f.Name) -Force }
}

# Reading convenience: UTF-8 copies for tools that cannot be told an encoding.  The
# authoritative importable bodies remain in text/mnm (UTF-16LE + BOM).
if($mnmStep.ok){
  $mnmUtf8Dir=Join-Path $textRoot 'mnm_utf8'
  New-Item -ItemType Directory -Force -Path $mnmUtf8Dir | Out-Null
  foreach($f in @(Get-ChildItem -LiteralPath $mnmExportDir -Filter '*.mnm' -File -Recurse -ErrorAction SilentlyContinue)){
    $bytes=[IO.File]::ReadAllBytes($f.FullName)
    $bodyText=if($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE){[Text.Encoding]::Unicode.GetString($bytes,2,$bytes.Length-2)}else{[Text.Encoding]::GetEncoding(936).GetString($bytes)}
    [IO.File]::WriteAllText((Join-Path $mnmUtf8Dir $f.Name),$bodyText,(New-Object System.Text.UTF8Encoding($false)))
  }
  Set-Content -LiteralPath (Join-Path $mnmUtf8Dir 'README.txt') -Value 'Reading convenience only (UTF-8, no BOM). The authoritative importable bodies are in text/mnm (UTF-16LE + BOM).' -Encoding UTF8
}
# Device comment layer: export the comment table through the same isolated UI
# session the MNM route opened, then join it with the exported program bodies so a
# single command yields the comment map as well.  The program bodies themselves are
# only read: the join writes separate files under text/comments.
$commentsOut=Join-Path $rawRoot 'comments'
$commentsExportDir=Join-Path $rawRoot 'comments_export'
$commentsTextDir=Join-Path $textRoot 'comments'
$commentsWorkflow=Join-Path $scriptRoot 'workflows\export_kv_device_comments.ps1'
$commentsResult=Join-Path $commentsOut 'workflow_result.json'
$commentsArgs=@('-ProjectPath',$uiProjectPath,'-CommentsDir',$commentsExportDir,'-OutDir',$commentsOut,'-FileBaseName','device_comments','-KeepProjectOpenAfterExport','-TimeoutSeconds',[string]$TimeoutSeconds)
$commentsStep=Invoke-Child $commentsWorkflow $commentsArgs $commentsResult 'device_comments' -ResetPaths @($commentsExportDir)
$commentsCsv=Join-Path $commentsExportDir 'device_comments.csv'
if($commentsStep.ok -and (Test-Path -LiteralPath $commentsCsv -PathType Leaf)){
  New-Item -ItemType Directory -Force -Path $commentsTextDir | Out-Null
  Copy-Item -LiteralPath $commentsCsv -Destination (Join-Path $commentsTextDir 'device_comments.csv') -Force
}
$annotateStep=[ordered]@{ok=$true;status='skipped';label='device_comment_coverage';result_path='';reason='comment table or program bodies unavailable'}
$annotateSummary=$null
if($commentsStep.ok -and $mnmStep.ok -and (Test-Path -LiteralPath $commentsCsv -PathType Leaf)){
  $annotateScript=Join-Path $scriptRoot 'annotate_kv_program_with_comments_core.ps1'
  $annotateResult=Join-Path $commentsTextDir 'annotate_result.json'
  $annotateArgs=@('-CommentsPath',$commentsCsv,'-MnmPath',$mnmExportDir,'-OutDir',$commentsTextDir)
  $annotateStep=if($PlanOnly){[ordered]@{ok=$true;status='planned';label='device_comment_coverage';result_path=$annotateResult}}else{Invoke-Child $annotateScript $annotateArgs $annotateResult 'device_comment_coverage'}
  if($annotateStep.ok -and $annotateStep.result){$annotateSummary=$annotateStep.result}
}
$commentCoverage=$null
$annotateCoveragePath=Join-Path $commentsTextDir 'coverage.json'
if(Test-Path -LiteralPath $annotateCoveragePath -PathType Leaf){try{$commentCoverage=Get-Content -Raw -LiteralPath $annotateCoveragePath -Encoding UTF8|ConvertFrom-Json}catch{}}

# Discover FB modules before the variable snapshot so their local-variable
# tables are captured by the same read-only variables route as program modules.
$fbModules=@()
foreach($m in @(Get-ChildItem -LiteralPath $mnmExportDir -Filter '*.mnm' -File -ErrorAction SilentlyContinue)){
  $head=Get-Content -LiteralPath $m.FullName -TotalCount 40 -ErrorAction SilentlyContinue
  if(@($head|Where-Object {$_ -match '^;MODULE_TYPE:2\s*$'}).Count -gt 0){$fbModules += [IO.Path]::GetFileNameWithoutExtension($m.Name)}
}
$fbSkipped=@()
$fbReadable=@()
foreach($name in @($fbModules|Sort-Object -Unique)){
  if($name -match '^(MC_|_MC_|\[MC\]_|_\[MC\]_|ModbusTCPClient_|SocketTCP_|KV_|KL_|NU_|DL_).+'){
    $fbSkipped += [ordered]@{module_name=$name;reason='official_or_library_fb_not_project_tree_readable'}
  } else { $fbReadable += $name }
}

$structureOut=Join-Path $rawRoot 'structures'; $structureResult=Join-Path $structureOut 'workflow_result.json'
$structureWorkflow=Join-Path $scriptRoot 'workflows\export_kv_structure_definitions.ps1'
$structureArgs=@('-ProjectPath',$uiProjectPath,'-OutDir',$structureOut,'-TimeoutSeconds',[string]$TimeoutSeconds)
$structureStep=Invoke-Child $structureWorkflow $structureArgs $structureResult 'structure_export' -ResetPaths @($structureOut)
$structureJson=Join-Path $structureOut 'structure_definitions.json'
if(Test-Path $structureJson){Copy-Item $structureJson (Join-Path $textRoot 'structure_definitions.json') -Force}

$moduleNames=@()
if($initial -and $initial.program_modules){$moduleNames=@($initial.program_modules|ForEach-Object {[string]$_.module_name}|Where-Object {$_}|Sort-Object -Unique)}
$variablesOut=Join-Path $rawRoot 'variables'; $variablesResult=Join-Path $variablesOut 'global_groups_workflow_result.json'
$globalVariablesWorkflow=Join-Path $scriptRoot 'workflows\snapshot_kv_global_variables_all_groups.ps1'
$variablesArgs=@('-ProjectPath',$uiProjectPath,'-OutDir',$variablesOut)
$variablesArgs += @('-TimeoutSeconds',[string]$TimeoutSeconds)
$variablesStep=Invoke-Child $globalVariablesWorkflow $variablesArgs $variablesResult 'variables_snapshot' -ResetPaths @($variablesOut)
$allVariableSnapshots=@()
$variableSnapshotPath=Join-Path $variablesOut 'artifacts\global_variables_all_groups\variable_snapshot_result.json'
if(Test-Path $variableSnapshotPath){
  $variableSnapshot=Get-Content -Raw $variableSnapshotPath|ConvertFrom-Json
  $allVariableSnapshots+=@($variableSnapshot.snapshots)
  $globalArtifacts=@($variableSnapshot.snapshots|ForEach-Object {$_.raw_path; $_.all_groups_raw_path})
  $null=Copy-SnapshotFiles $globalArtifacts (Join-Path $textRoot 'variables')
}

# A fresh variable-editor session per FB prevents state accumulated while
# scanning ordinary program modules from contaminating larger FB local tables.
$variablesWorkflow=Join-Path $scriptRoot 'workflows\set_kv_variables.ps1'
$fbVariableSteps=@()
foreach($name in @($fbReadable|Sort-Object -Unique)){
  $safeName=$name -replace '[\\/:*?""<>|]','_'
  $fbVariablesOut=Join-Path $rawRoot ('fb_variables\'+$safeName)
  $fbVariablesResult=Join-Path $fbVariablesOut 'variable_workflow_result.json'
  $fbVariablesArgs=@('-ProjectPath',$uiProjectPath,'-OutDir',$fbVariablesOut,'-SnapshotOnly','-SkipGlobal','-SnapshotModules',$name,'-TimeoutSeconds',[string]$TimeoutSeconds)
  $fbVariableStep=Invoke-Child $variablesWorkflow $fbVariablesArgs $fbVariablesResult ('fb_variables_'+$name) -ResetPaths @($fbVariablesOut)
  $fbVariableSteps+=$fbVariableStep
  $fbVariableSnapshotPath=Join-Path $fbVariablesOut 'artifacts\variables\variable_snapshot_result.json'
  if(Test-Path $fbVariableSnapshotPath){
    $fbVariableSnapshot=Get-Content -Raw $fbVariableSnapshotPath|ConvertFrom-Json
    $allVariableSnapshots+=@($fbVariableSnapshot.snapshots)
    $null=Copy-SnapshotFiles @($fbVariableSnapshot.snapshots|ForEach-Object {$_.raw_path}) (Join-Path $textRoot 'variables')
  }
}
# Ordinary program modules keep their local declarations in the same local-tab
# grid as FBs, and the runner can walk several module names inside one editor
# session. Batch them into one child call: a per-module workflow launch pays the
# whole checklist/boundary/guard overhead again for every program (observed
# ~90s/module, which made a 24-program sample impractical). FB modules are
# excluded here because they already use their dedicated per-FB sessions above.
$programLocalCandidates=@()
if(-not $SkipProgramLocals){
  $programLocalCandidates=if($ProgramLocalModules.Count -gt 0){
    @($ProgramLocalModules|ForEach-Object{([string]$_).Trim()}|Where-Object {$_})
  } else {
    @($moduleNames|Where-Object {$fbModules -notcontains $_})
  }
  $programLocalCandidates=@($programLocalCandidates|Sort-Object -Unique)
}
$programLocalSteps=@()
if($programLocalCandidates.Count -gt 0){
  $programVariablesOut=Join-Path $rawRoot 'program_variables'
  $programVariablesResult=Join-Path $programVariablesOut 'variable_workflow_result.json'
  $programVariablesArgs=@('-ProjectPath',$uiProjectPath,'-OutDir',$programVariablesOut,'-SnapshotOnly','-SkipGlobal','-SnapshotModules',($programLocalCandidates -join ','),'-TimeoutSeconds',[string]$TimeoutSeconds)
  $programVariableStep=Invoke-Child $variablesWorkflow $programVariablesArgs $programVariablesResult 'program_variables' -ResetPaths @($programVariablesOut)
  $programLocalSteps+=$programVariableStep
  $programVariableSnapshotPath=Join-Path $programVariablesOut 'artifacts\variables\variable_snapshot_result.json'
  if(Test-Path $programVariableSnapshotPath){
    $programVariableSnapshot=Get-Content -Raw $programVariableSnapshotPath|ConvertFrom-Json
    $allVariableSnapshots+=@($programVariableSnapshot.snapshots)
    $null=Copy-SnapshotFiles @($programVariableSnapshot.snapshots|ForEach-Object {$_.raw_path}) (Join-Path $textRoot 'variables')
  }
}
$allLocalVariableSteps=@($fbVariableSteps+$programLocalSteps)
if(-not $PlanOnly){
  $globalComplete=($variableSnapshot -and $variableSnapshot.unfiltered_completeness_verified -eq $true)
  Write-Json (Join-Path $textRoot 'variables\variable_snapshot_result.json') ([ordered]@{ok=($variablesStep.ok -and @($allLocalVariableSteps|Where-Object{-not $_.ok}).Count -eq 0);read_only=$true;project_path=$uiProjectPath;snapshots=@($allVariableSnapshots);all_columns_preserved=$true;unfiltered_completeness_verified=$globalComplete;captured_program_locals=@($programLocalCandidates);program_local_step_count=@($programLocalSteps).Count}) 8
}

$ethercatOut=Join-Path $rawRoot 'ethercat_configuration'
$ethercatResult=Join-Path $ethercatOut 'ethercat_configuration_result.json'
$ethercatWorkflow=Join-Path $scriptRoot 'workflows\export_kv_ethercat_configuration.ps1'
$ethercatArgs=@('-ProjectPath',$uiProjectPath,'-OutDir',$ethercatOut,'-ProjectName',[IO.Path]::GetFileNameWithoutExtension($ProjectPath),'-TimeoutSeconds',[string]$TimeoutSeconds)
$ethercatStep=Invoke-Child $ethercatWorkflow $ethercatArgs $ethercatResult 'ethercat_configuration' -ResetPaths @($ethercatOut)
$ethercatConfigurationPath=Join-Path $ethercatOut 'ethercat_configuration.json'
$ethercatConfiguration=$null
if(Test-Path -LiteralPath $ethercatConfigurationPath -PathType Leaf){ try{$ethercatConfiguration=Get-Content -Raw -LiteralPath $ethercatConfigurationPath -Encoding UTF8|ConvertFrom-Json}catch{} }


$axisOut=Join-Path $rawRoot 'axis_parameters'
$axisResult=Join-Path $axisOut 'axis_parameters_result.json'
$axisWorkflow=Join-Path $scriptRoot 'workflows\export_kv_axis_parameters.ps1'
$axisArgs=@('-ProjectPath',$uiProjectPath,'-OutDir',$axisOut,'-TimeoutSeconds',[string]$TimeoutSeconds)
$axisStep=Invoke-Child $axisWorkflow $axisArgs $axisResult 'axis_parameters' -ResetPaths @($axisOut)
$axisTsv=Join-Path $axisOut 'axes_params.tsv'

$eipOut=Join-Path $rawRoot 'eip_configuration'
$eipResult=Join-Path $eipOut 'eip_configuration_result.json'
$eipWorkflow=Join-Path $scriptRoot 'workflows\export_kv_eip_configuration.ps1'
$eipArgs=@('-ProjectPath',$uiProjectPath,'-OutDir',$eipOut)
$eipStep=Invoke-Child $eipWorkflow $eipArgs $eipResult 'eip_configuration' -ResetPaths @($eipOut)
$eipConfigPath=Join-Path $eipOut 'eip_configuration.json'

$fbSteps=@()
foreach($name in @($fbReadable|Sort-Object -Unique)){
  $fbOut=Join-Path $rawRoot ('fb_arguments\'+($name -replace '[\\/:*?""<>|]','_')); New-Item -ItemType Directory -Force -Path $fbOut|Out-Null
  $fbResult=Join-Path $fbOut 'fb_declaration_workflow_result.json'; $fbWorkflow=Join-Path $scriptRoot 'workflows\set_kv_fb_arguments.ps1'
  $fbArgs=@('-ProjectPath',$uiProjectPath,'-FbModuleName',$name,'-OutDir',$fbOut,'-SnapshotOnly','-TimeoutSeconds',[string]$TimeoutSeconds)
  $fbStep=Invoke-Child $fbWorkflow $fbArgs $fbResult ('fb_arguments_'+$name) -ResetPaths @($fbOut)
  if(-not $fbStep.ok){
    $missingTreeEvidence=@(Get-ChildItem -LiteralPath $fbOut -Recurse -Filter 'fail.txt' -File -ErrorAction SilentlyContinue | Where-Object {(Get-Content -Raw -LiteralPath $_.FullName) -match 'KV_FB_MODULE_TREE_ITEM_MISSING'})
    if($missingTreeEvidence.Count -gt 0){
      $fbSkipped += [ordered]@{module_name=$name;reason='exported_mnm_not_exposed_as_project_tree_fb';evidence=@($missingTreeEvidence|ForEach-Object {Rel $snapshotRoot $_.FullName})}
      $fbStep=[ordered]@{ok=$true;status='skipped';label=('fb_arguments_'+$name);result_path=$fbResult;reason='exported_mnm_not_exposed_as_project_tree_fb'}
      Set-StageSkipped ('fb_arguments_'+$name) 'exported_mnm_not_exposed_as_project_tree_fb'
    }
  }
  $fbSteps += $fbStep
  $fbSnapshotPath=Join-Path $fbOut 'artifacts\fb_arguments\fb_snapshot_result.json'
  if(Test-Path $fbSnapshotPath){$fbSnapshot=Get-Content -Raw $fbSnapshotPath|ConvertFrom-Json;$fbTextDir=Join-Path $textRoot ('fb_arguments\'+($name -replace '[\\/:*?""<>|]','_'));$null=Copy-SnapshotFiles @($fbSnapshot.raw_path) $fbTextDir;Copy-Item $fbSnapshotPath (Join-Path $fbTextDir 'fb_snapshot_result.json') -Force}
}



$inventoryFinal=Join-Path $textRoot 'project_inventory.json'
$inventoryFinalArgs=@('-ProjectPath',$ProjectPath,'-MnmDir',$mnmExportDir,'-OutDir',(Join-Path $rawRoot 'inventory_final'),'-StructureDefinitionsPath',(Join-Path $textRoot 'structure_definitions.json'))
$inventoryFinalStep=Invoke-Child (Join-Path $scriptRoot 'export_kv_project_inventory.ps1') $inventoryFinalArgs (Join-Path $rawRoot 'inventory_final\project_inventory.json') 'inventory_final' -ResetPaths @((Join-Path $rawRoot 'inventory_final'))
if(Test-Path (Join-Path $rawRoot 'inventory_final\project_inventory.json')){Copy-Item (Join-Path $rawRoot 'inventory_final\project_inventory.json') $inventoryFinal -Force}

$materializationScript=Join-Path $scriptRoot 'workflow_tools\materialize_kv_project_snapshot.ps1'
$materializationResult=Join-Path $snapshotRoot 'project\_index\materialization_result.json'
$materializationArgs=@(
  '-SnapshotRoot',$snapshotRoot,
  '-InventoryPath',$inventoryFinal,
  '-MnmRoot',(Join-Path $textRoot 'mnm'),
  '-VariablesRoot',(Join-Path $textRoot 'variables'),
  '-FbArgumentsRoot',(Join-Path $textRoot 'fb_arguments'),
  '-StructureDefinitionsPath',(Join-Path $textRoot 'structure_definitions.json'),
  '-RawRoot',$rawRoot
)
$materializationStep=if($PlanOnly){[ordered]@{ok=$true;status='planned';label='materialize_semantic_project';result_path=$materializationResult}}else{Invoke-Child $materializationScript $materializationArgs $materializationResult 'materialize_semantic_project' -ResetPaths @((Join-Path $snapshotRoot 'project'))}

# The semantic tree is built from WsTreeEnv, which only carries names. Merge the
# UI-read EtherCAT settings (address / product / vendor / IDs) into it so the
# restore plan can distinguish default from configured slaves.
if($ethercatStep.ok -and $ethercatConfiguration){
  $semanticEtherCatDir=Join-Path $snapshotRoot 'project\配置\EtherCAT'
  New-Item -ItemType Directory -Force -Path $semanticEtherCatDir | Out-Null
  Copy-Item -LiteralPath $ethercatConfigurationPath -Destination (Join-Path $semanticEtherCatDir 'devices.json') -Force
  $etherCatEntityPath=Join-Path $semanticEtherCatDir 'entity.json'
  if(Test-Path -LiteralPath $etherCatEntityPath -PathType Leaf){
    try{
      $entity=Get-Content -Raw -LiteralPath $etherCatEntityPath -Encoding UTF8|ConvertFrom-Json
      $entity.artifacts | Add-Member -NotePropertyName devices -NotePropertyValue '配置/EtherCAT/devices.json' -Force
      $entity.status | Add-Member -NotePropertyName devices -NotePropertyValue 'complete' -Force
      Write-Json $etherCatEntityPath $entity 20
    }catch{}
  }
  $unitConfigPath=Join-Path $snapshotRoot 'project\配置\单元\configuration.json'
  if(Test-Path -LiteralPath $unitConfigPath -PathType Leaf){
    try{
      $unitConfig=Get-Content -Raw -LiteralPath $unitConfigPath -Encoding UTF8|ConvertFrom-Json
      $unitConfig.asset_status | Add-Member -NotePropertyName ethercat -NotePropertyValue 'ui_read_complete' -Force
      $unitConfig | Add-Member -NotePropertyName ethercat_node_count -NotePropertyValue ([int]$ethercatConfiguration.node_count) -Force
      Write-Json $unitConfigPath $unitConfig 20
    }catch{}
  }
}

# Motion axis control table is a proven read-only dump (axis_parameters_guarded
# -Mode Dump -AllParams). Merge the TSV and the axis name list into the semantic
# tree and replace the "missing" markers for motion.
if($axisStep.ok -and (Test-Path -LiteralPath $axisTsv -PathType Leaf)){
  $motionDir=Join-Path $snapshotRoot 'project\配置\运动'
  New-Item -ItemType Directory -Force -Path $motionDir | Out-Null
  Copy-Item -LiteralPath $axisTsv -Destination (Join-Path $motionDir 'axis_parameters.tsv') -Force
  $axisLines=@(Get-Content -LiteralPath $axisTsv -Encoding UTF8)
  $axisNames=@()
  if($axisLines.Count -gt 0){
    $header=$axisLines[0] -split "`t"
    if($header.Count -gt 4){ $axisNames=@($header[4..($header.Count-1)] | Where-Object { $_ }) }
  }
  Write-Json (Join-Path $motionDir 'axes.json') ([ordered]@{axis_count=$axisNames.Count;axes=$axisNames}) 6
  Write-Json (Join-Path $motionDir 'entity.json') ([ordered]@{
    id='config:运动'; kind='motion_configuration'; display_name='运动设定'; path='配置/运动'
    artifacts=[ordered]@{axis_parameters='配置/运动/axis_parameters.tsv';axes='配置/运动/axes.json'}
    status=[ordered]@{axis_parameters='complete';axes='complete'}
    restore=[ordered]@{order=30;strategy='configure_motion_axes';depends_on=@('config:单元')}
  }) 12
  $unitConfigPath2=Join-Path $snapshotRoot 'project\配置\单元\configuration.json'
  if(Test-Path -LiteralPath $unitConfigPath2 -PathType Leaf){
    try{
      $unitConfig2=Get-Content -Raw -LiteralPath $unitConfigPath2 -Encoding UTF8|ConvertFrom-Json
      $unitConfig2.asset_status | Add-Member -NotePropertyName motion_axes -NotePropertyValue 'ui_dump_complete' -Force
      $unitConfig2.asset_status | Add-Member -NotePropertyName axis_parameters -NotePropertyValue 'ui_dump_complete' -Force
      $unitConfig2 | Add-Member -NotePropertyName axis_count -NotePropertyValue $axisNames.Count -Force
      Write-Json $unitConfigPath2 $unitConfig2 20
    }catch{}
  }
}

# EtherNet/IP read-only probe: 设定列表 table (nodes, IPs, connections, RPI).
# 软元件分配 maps are a separate asset (eip_connection, not wired yet).
if($eipStep.ok -and (Test-Path -LiteralPath $eipConfigPath -PathType Leaf)){
  $eipDir=Join-Path $snapshotRoot 'project\配置\EtherNetIP'
  New-Item -ItemType Directory -Force -Path $eipDir | Out-Null
  Copy-Item -LiteralPath $eipConfigPath -Destination (Join-Path $eipDir 'devices.json') -Force
  $eipData=Get-Content -Raw -LiteralPath $eipConfigPath -Encoding UTF8|ConvertFrom-Json
  Write-Json (Join-Path $eipDir 'connections.json') ([ordered]@{connection_count=[int]$eipData.connection_count;connections=@($eipData.connections)}) 8
  Write-Json (Join-Path $eipDir 'entity.json') ([ordered]@{id='config:EtherNetIP';kind='ethernet_ip_configuration';display_name='EtherNet/IP';path='配置/EtherNetIP';artifacts=[ordered]@{devices='配置/EtherNetIP/devices.json';connections='配置/EtherNetIP/connections.json'};status=[ordered]@{ips='complete';devices='complete';connections='complete';assignment='not_wired'};restore=[ordered]@{order=25;strategy='configure_eip_devices';depends_on=@('config:单元')}}) 12
  $uc=Join-Path $snapshotRoot 'project\配置\单元\configuration.json'
  if(Test-Path -LiteralPath $uc){ try{ $u=Get-Content -Raw -LiteralPath $uc -Encoding UTF8|ConvertFrom-Json; $u.asset_status|Add-Member -NotePropertyName ethernet_ip -NotePropertyValue 'ui_read_complete' -Force; $u|Add-Member -NotePropertyName eip_ip_count -NotePropertyValue ([int]$eipData.ip_count) -Force; $u|Add-Member -NotePropertyName eip_connection_count -NotePropertyValue ([int]$eipData.connection_count) -Force; Write-Json $uc $u 20 }catch{} }
}

$index=@(); foreach($f in @(Get-ChildItem -LiteralPath $textRoot -File -Recurse | Sort-Object FullName)){
  $index += [ordered]@{path=(Rel $snapshotRoot $f.FullName);format=$f.Extension.TrimStart('.');length=$f.Length;sha256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
Write-Json (Join-Path $snapshotRoot 'text_index.json') $index 8
$statuses=@($inventoryStep,$mnmStep,$structureStep,$variablesStep,$ethercatStep,$axisStep,$eipStep)+@($allLocalVariableSteps)+@($fbSteps)+@($inventoryFinalStep,$materializationStep,$commentsStep,$annotateStep)
$missing=@(); if(-not $mnmStep.ok){$missing+='mnm'}; if(-not $variablesStep.ok -or @($allLocalVariableSteps|Where-Object {-not $_.ok}).Count -gt 0){$missing+='variables'}; if(-not $structureStep.ok){$missing+='structures'}; if($fbModules.Count -gt 0 -and @($fbSteps|Where-Object {-not $_.ok}).Count -gt 0){$missing+='fb_arguments'}; if(-not $ethercatStep.ok){$missing+='ethercat_configuration'}; if(-not $axisStep.ok){$missing+='axis_parameters'}; if(-not $eipStep.ok){$missing+='eip_configuration'}; if(-not $commentsStep.ok){$missing+='comments'}; if(-not $annotateStep.ok){$missing+='comment_coverage'}
$semanticStatus=if($materializationStep.ok){'complete'}else{'failed'}
$semanticWarnings=@()
if($materializationStep.result -and $materializationStep.result.warnings){$semanticWarnings=@($materializationStep.result.warnings)}
if(-not $materializationStep.ok){$missing+='semantic_project'}
$status=if($PlanOnly){'planned'}elseif($missing.Count -eq 0){'ready'}else{'partial'}
$snapshotReady=($status -eq 'ready')

$manifest=[ordered]@{
  schema_version=2; snapshot_schema='kv_project_text_snapshot'; status=$status; generated_at=(Get-Date).ToUniversalTime().ToString('o')
  project=[ordered]@{path=$ProjectPath;root=$projectRoot;fingerprint=$fingerprint}
  layout=[ordered]@{snapshot_root='.';project='project';text='text';raw='raw';architecture='architecture';text_index='text_index.json'}
  artifacts=[ordered]@{semantic_project='project';inventory='text/project_inventory.json';mnm='text/mnm';variables='text/variables';structures='text/structure_definitions.json';fb_arguments='text/fb_arguments';comments='text/comments';ethercat_devices='project/配置/EtherCAT/devices.json';axis_parameters='project/配置/运动/axis_parameters.tsv';eip_devices='project/配置/EtherNetIP/devices.json'}
  workflow_status=$statuses; discovered_modules=$moduleNames; discovered_fb_modules=@($fbModules|Sort-Object -Unique); discovered_program_local_modules=@($programLocalCandidates)
  semantic_project_status=$semanticStatus; semantic_warnings=$semanticWarnings; missing_capabilities=@($missing); skipped_capabilities=$fbSkipped; version_control=[ordered]@{deterministic_index='text_index.json';file_hashes='sha256';binary_project_files='referenced_by_project.fingerprint_only';generated_files='isolated_snapshot_directory'}
  resume=[ordered]@{enabled=[bool]$Resume;state_path='snapshot_state.json';invalidated_by_fingerprint=[bool]$script:resumeInvalidated;reused_stages=@($script:reusedStages|Sort-Object -Unique)}
}
Write-Json (Join-Path $snapshotRoot 'source_snapshot_manifest.json') $manifest 20
$commentLayer=@()
if($commentCoverage){
  $commentLayer=@([ordered]@{
    device_comments='text/comments/device_comments.csv'
    comments_index='text/comments/comments.tsv'
    usage_index='text/comments/usage.tsv'
    coverage='text/comments/coverage.json'
    annotated_program='text/comments/program_annotations.md'
    scope=[string]$commentCoverage.scope
    referenced_documentable=[int]$commentCoverage.summary.referenced_documentable
    used_annotated=[int]$commentCoverage.summary.used_annotated
    used_unannotated=[int]$commentCoverage.summary.used_unannotated
    unannotated_devices=@($commentCoverage.used_unannotated)
  })
}elseif($commentsStep.ok){
  $commentLayer=@([ordered]@{device_comments='text/comments/device_comments.csv';coverage='';note='program bodies were unavailable for the join'})
}
$architecture=[ordered]@{schema_version=1;project=$manifest.project;source_snapshot=[ordered]@{manifest='source_snapshot_manifest.json';text_root='text';raw_root='raw'};extension_points=[ordered]@{modules=@();variables=@();io_map=@();units=@();ethercat=@();motion=@();data_types=@();fb_instances=@();comments=$commentLayer;acceptance=@();extra_config=[ordered]@{}}}
Write-Json (Join-Path $architectureRoot 'project_map.json') $architecture 12
$readme=@"
# KV Project Text Snapshot

This directory is a read-only, Agent-oriented projection of one KV STUDIO project.

- `source_snapshot_manifest.json` binds every artifact to the source project fingerprint.
- `project/` is the canonical semantic tree: function blocks, program modules,
  configuration and data types each carry an `entity.json` plus restore payloads.
- `text/` contains UTF-8 JSON, TSV, MNM and XML that can be reviewed and versioned.
- `text/comments/` is the device comment layer: the table exported through the File
  menu (`device_comments.csv`), the join with the program bodies (`comments.tsv`,
  `usage.tsv`) and the coverage report (`coverage.json`, `program_annotations.md`).
  The program bodies under `text/mnm/` are only read; the join never edits them.
- `text_index.json` is sorted and contains a SHA-256 for every text artifact.
- `raw/` preserves same-run workflow receipts and UI evidence.
- `architecture/project_map.json` is the stable extension point for future categories.

`status=ready` means all currently implemented read-only routes completed. A `partial`
snapshot is still useful, but its `missing_capabilities` must be resolved before using
it as a complete source of truth.
"@
Set-Content -LiteralPath (Join-Path $snapshotRoot 'README.md') -Value $readme -Encoding UTF8
$manifest | ConvertTo-Json -Depth 20
$exitCode=if($PlanOnly -or $status -eq 'ready'){0}else{1}
} finally {
  if($PlanOnly){
    $uiLifecycle.cleanup_status='planned'
  }else{
    # The MNM runner is the sole owner of this UI process. Re-read its receipt
    # during exceptional exits in case the composition failed before binding it.
    if($uiProcessId -le 0 -and $mnmWorkspacePlanPath -and (Test-Path -LiteralPath $mnmWorkspacePlanPath -PathType Leaf)){
      try{
        $cleanupPlan=Get-Content -Raw -LiteralPath $mnmWorkspacePlanPath -Encoding UTF8|ConvertFrom-Json
        if($cleanupPlan.core_result_path -and (Test-Path -LiteralPath ([string]$cleanupPlan.core_result_path) -PathType Leaf)){
          $cleanupCore=Get-Content -Raw -LiteralPath ([string]$cleanupPlan.core_result_path) -Encoding UTF8|ConvertFrom-Json
          $uiProcessId=[int]$cleanupCore.process_id
          $uiLifecycle.process_id=$uiProcessId
          $uiLifecycle.launched_by_runner=[bool]$cleanupCore.launched_by_runner
        }
      }catch{}
    }
    if($uiProcessId -gt 0 -and $uiLifecycle.launched_by_runner){
      try{Stop-Process -Id $uiProcessId -Force -ErrorAction SilentlyContinue}catch{}
      $deadline=(Get-Date).AddSeconds(10)
      while((Get-Process -Id $uiProcessId -ErrorAction SilentlyContinue) -and (Get-Date)-lt $deadline){Start-Sleep -Milliseconds 200}
    }
    if($mnmWorkRoot -and (Test-Path -LiteralPath $mnmWorkRoot -PathType Container)){
      if($Resume -and -not $snapshotReady){
        # Keep the isolated project copy so the next -Resume run can continue the
        # UI stages without re-exporting MNM from scratch.
        $uiLifecycle.cleanup_status='retained_for_resume'
        $uiLifecycle.work_root=$mnmWorkRoot
      }else{
        try{[IO.Directory]::Delete($mnmWorkRoot,$true);$uiLifecycle.cleanup_status='isolated_copy_removed'}catch{$uiLifecycle.cleanup_status='isolated_copy_cleanup_failed';$uiLifecycle.cleanup_error=$_.Exception.Message}
      }
    }else{$uiLifecycle.cleanup_status='isolated_copy_absent'}
    if($KeepProjectOpen){
      try{$reopened=Open-Project $ProjectPath;$uiLifecycle.source_reopened_process_id=$reopened.process.Id}catch{$uiLifecycle.source_reopen_error=$_.Exception.Message}
    }
  }
  Write-Json (Join-Path $rawRoot 'ui_process_lifecycle.json') $uiLifecycle 8
  Save-SnapshotState
  if($uiLifecycle.cleanup_status -eq 'isolated_copy_cleanup_failed'){
    [Console]::Error.WriteLine("KV_SNAPSHOT_TEMP_CLEANUP_FAILED: $($uiLifecycle.cleanup_error)")
  }
}
exit $exitCode
