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
function Invoke-Child([string]$Script,[string[]]$Arguments,[string]$ResultPath,[string]$Label) {
  $request=[ordered]@{label=$Label;script=$Script;arguments=$Arguments;result_path=$ResultPath;plan_only=[bool]$PlanOnly}
  Write-Json (Join-Path $rawRoot ($Label+'_request.json')) $request 10
  if($PlanOnly){ return [ordered]@{ok=$true;status='planned';label=$Label;result_path=$ResultPath} }
  & powershell -STA -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments *> (Join-Path $rawRoot ($Label+'_stdout.txt'))
  $exit=if($LASTEXITCODE -is [int]){[int]$LASTEXITCODE}else{0}
  $result=$null
  if(Test-Path -LiteralPath $ResultPath -PathType Leaf){try{$result=Get-Content -Raw -LiteralPath $ResultPath -Encoding UTF8|ConvertFrom-Json}catch{}}
  [ordered]@{ok=($exit -eq 0 -and $result -and $result.ok -eq $true);status=if($exit -eq 0){'completed'}else{'failed'};label=$Label;exit_code=$exit;result_path=$ResultPath;result=$result}
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

try {
$inventoryInitial=Join-Path $rawRoot 'inventory_initial'
$inventoryInitialResult=Join-Path $inventoryInitial 'project_inventory.json'
$inventoryArgs=@('-ProjectPath',$ProjectPath,'-OutDir',$inventoryInitial)
$inventoryStep=Invoke-Child (Join-Path $scriptRoot 'export_kv_project_inventory.ps1') $inventoryArgs $inventoryInitialResult 'inventory_initial'
$initial=$null; if(Test-Path $inventoryInitialResult){try{$initial=Get-Content -Raw $inventoryInitialResult|ConvertFrom-Json}catch{}}

$mnmOut=Join-Path $rawRoot 'mnm'; $mnmExportDir=Join-Path $rawRoot 'mnm_export'; $mnmTextDir=Join-Path $textRoot 'mnm'
$mnmWorkflow=Join-Path $scriptRoot 'workflows\export_mnm_project_copy_default_folder.ps1'
$mnmResult=Join-Path $mnmOut 'export_mnm_project_copy_result.json'
$mnmWorkRoot=Join-Path ([IO.Path]::GetTempPath()) ('kv_mnm_snapshot_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$mnmArgs=@('-ProjectPath',$ProjectPath,'-ExportDir',$mnmExportDir,'-OutDir',$mnmOut,'-WorkRoot',$mnmWorkRoot,'-AllowWorkRootOutsideExportDir','-TimeoutSeconds',[string]$TimeoutSeconds)
$mnmStep=Invoke-Child $mnmWorkflow $mnmArgs $mnmResult 'mnm_export'
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
if($mnmStep.ok){
  New-Item -ItemType Directory -Force -Path $mnmTextDir | Out-Null
  foreach($f in @(Get-ChildItem -LiteralPath $mnmExportDir -Filter '*.mnm' -File -Recurse -ErrorAction SilentlyContinue)){ Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $mnmTextDir $f.Name) -Force }
}

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
$structureStep=Invoke-Child $structureWorkflow $structureArgs $structureResult 'structure_export'
$structureJson=Join-Path $structureOut 'structure_definitions.json'
if(Test-Path $structureJson){Copy-Item $structureJson (Join-Path $textRoot 'structure_definitions.json') -Force}

$moduleNames=@()
if($initial -and $initial.program_modules){$moduleNames=@($initial.program_modules|ForEach-Object {[string]$_.module_name}|Where-Object {$_}|Sort-Object -Unique)}
$variablesOut=Join-Path $rawRoot 'variables'; $variablesResult=Join-Path $variablesOut 'global_groups_workflow_result.json'
$globalVariablesWorkflow=Join-Path $scriptRoot 'workflows\snapshot_kv_global_variables_all_groups.ps1'
$variablesArgs=@('-ProjectPath',$uiProjectPath,'-OutDir',$variablesOut)
$variablesArgs += @('-TimeoutSeconds',[string]$TimeoutSeconds)
$variablesStep=Invoke-Child $globalVariablesWorkflow $variablesArgs $variablesResult 'variables_snapshot'
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
  $fbVariableStep=Invoke-Child $variablesWorkflow $fbVariablesArgs $fbVariablesResult ('fb_variables_'+$name)
  $fbVariableSteps+=$fbVariableStep
  $fbVariableSnapshotPath=Join-Path $fbVariablesOut 'artifacts\variables\variable_snapshot_result.json'
  if(Test-Path $fbVariableSnapshotPath){
    $fbVariableSnapshot=Get-Content -Raw $fbVariableSnapshotPath|ConvertFrom-Json
    $allVariableSnapshots+=@($fbVariableSnapshot.snapshots)
    $null=Copy-SnapshotFiles @($fbVariableSnapshot.snapshots|ForEach-Object {$_.raw_path}) (Join-Path $textRoot 'variables')
  }
}
if(-not $PlanOnly){
  $globalComplete=($variableSnapshot -and $variableSnapshot.unfiltered_completeness_verified -eq $true)
  Write-Json (Join-Path $textRoot 'variables\variable_snapshot_result.json') ([ordered]@{ok=($variablesStep.ok -and @($fbVariableSteps|Where-Object{-not $_.ok}).Count -eq 0);read_only=$true;project_path=$uiProjectPath;snapshots=@($allVariableSnapshots);all_columns_preserved=$true;unfiltered_completeness_verified=$globalComplete}) 8
}

$fbSteps=@()
foreach($name in @($fbReadable|Sort-Object -Unique)){
  $fbOut=Join-Path $rawRoot ('fb_arguments\'+($name -replace '[\\/:*?""<>|]','_')); New-Item -ItemType Directory -Force -Path $fbOut|Out-Null
  $fbResult=Join-Path $fbOut 'fb_declaration_workflow_result.json'; $fbWorkflow=Join-Path $scriptRoot 'workflows\set_kv_fb_arguments.ps1'
  $fbArgs=@('-ProjectPath',$uiProjectPath,'-FbModuleName',$name,'-OutDir',$fbOut,'-SnapshotOnly','-TimeoutSeconds',[string]$TimeoutSeconds)
  $fbStep=Invoke-Child $fbWorkflow $fbArgs $fbResult ('fb_arguments_'+$name)
  if(-not $fbStep.ok){
    $missingTreeEvidence=@(Get-ChildItem -LiteralPath $fbOut -Recurse -Filter 'fail.txt' -File -ErrorAction SilentlyContinue | Where-Object {(Get-Content -Raw -LiteralPath $_.FullName) -match 'KV_FB_MODULE_TREE_ITEM_MISSING'})
    if($missingTreeEvidence.Count -gt 0){
      $fbSkipped += [ordered]@{module_name=$name;reason='exported_mnm_not_exposed_as_project_tree_fb';evidence=@($missingTreeEvidence|ForEach-Object {Rel $snapshotRoot $_.FullName})}
      $fbStep=[ordered]@{ok=$true;status='skipped';label=('fb_arguments_'+$name);result_path=$fbResult;reason='exported_mnm_not_exposed_as_project_tree_fb'}
    }
  }
  $fbSteps += $fbStep
  $fbSnapshotPath=Join-Path $fbOut 'artifacts\fb_arguments\fb_snapshot_result.json'
  if(Test-Path $fbSnapshotPath){$fbSnapshot=Get-Content -Raw $fbSnapshotPath|ConvertFrom-Json;$fbTextDir=Join-Path $textRoot ('fb_arguments\'+($name -replace '[\\/:*?""<>|]','_'));$null=Copy-SnapshotFiles @($fbSnapshot.raw_path) $fbTextDir;Copy-Item $fbSnapshotPath (Join-Path $fbTextDir 'fb_snapshot_result.json') -Force}
}

$inventoryFinal=Join-Path $textRoot 'project_inventory.json'
$inventoryFinalArgs=@('-ProjectPath',$ProjectPath,'-MnmDir',$mnmExportDir,'-OutDir',(Join-Path $rawRoot 'inventory_final'),'-StructureDefinitionsPath',(Join-Path $textRoot 'structure_definitions.json'))
$inventoryFinalStep=Invoke-Child (Join-Path $scriptRoot 'export_kv_project_inventory.ps1') $inventoryFinalArgs (Join-Path $rawRoot 'inventory_final\project_inventory.json') 'inventory_final'
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
$materializationStep=if($PlanOnly){[ordered]@{ok=$true;status='planned';label='materialize_semantic_project';result_path=$materializationResult}}else{Invoke-Child $materializationScript $materializationArgs $materializationResult 'materialize_semantic_project'}

$index=@(); foreach($f in @(Get-ChildItem -LiteralPath $textRoot -File -Recurse | Sort-Object FullName)){
  $index += [ordered]@{path=(Rel $snapshotRoot $f.FullName);format=$f.Extension.TrimStart('.');length=$f.Length;sha256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
Write-Json (Join-Path $snapshotRoot 'text_index.json') $index 8
$statuses=@($inventoryStep,$mnmStep,$structureStep,$variablesStep)+@($fbVariableSteps)+@($fbSteps)+@($inventoryFinalStep,$materializationStep)
$missing=@(); if(-not $mnmStep.ok){$missing+='mnm'}; if(-not $variablesStep.ok -or @($fbVariableSteps|Where-Object {-not $_.ok}).Count -gt 0){$missing+='variables'}; if(-not $structureStep.ok){$missing+='structures'}; if($fbModules.Count -gt 0 -and @($fbSteps|Where-Object {-not $_.ok}).Count -gt 0){$missing+='fb_arguments'}
$semanticStatus=if($materializationStep.ok){'complete'}else{'failed'}
$semanticWarnings=@()
if($materializationStep.result -and $materializationStep.result.warnings){$semanticWarnings=@($materializationStep.result.warnings)}
if(-not $materializationStep.ok){$missing+='semantic_project'}
$status=if($PlanOnly){'planned'}elseif($missing.Count -eq 0){'ready'}else{'partial'}

$manifest=[ordered]@{
  schema_version=2; snapshot_schema='kv_project_text_snapshot'; status=$status; generated_at=(Get-Date).ToUniversalTime().ToString('o')
  project=[ordered]@{path=$ProjectPath;root=$projectRoot;fingerprint=$fingerprint}
  layout=[ordered]@{snapshot_root='.';project='project';text='text';raw='raw';architecture='architecture';text_index='text_index.json'}
  artifacts=[ordered]@{semantic_project='project';inventory='text/project_inventory.json';mnm='text/mnm';variables='text/variables';structures='text/structure_definitions.json';fb_arguments='text/fb_arguments'}
  workflow_status=$statuses; discovered_modules=$moduleNames; discovered_fb_modules=@($fbModules|Sort-Object -Unique)
  semantic_project_status=$semanticStatus; semantic_warnings=$semanticWarnings; missing_capabilities=@($missing); skipped_capabilities=$fbSkipped; version_control=[ordered]@{deterministic_index='text_index.json';file_hashes='sha256';binary_project_files='referenced_by_project.fingerprint_only';generated_files='isolated_snapshot_directory'}
}
Write-Json (Join-Path $snapshotRoot 'source_snapshot_manifest.json') $manifest 20
$architecture=[ordered]@{schema_version=1;project=$manifest.project;source_snapshot=[ordered]@{manifest='source_snapshot_manifest.json';text_root='text';raw_root='raw'};extension_points=[ordered]@{modules=@();variables=@();io_map=@();units=@();ethercat=@();motion=@();data_types=@();fb_instances=@();comments=@();acceptance=@();extra_config=[ordered]@{}}}
Write-Json (Join-Path $architectureRoot 'project_map.json') $architecture 12
$readme=@"
# KV Project Text Snapshot

This directory is a read-only, Agent-oriented projection of one KV STUDIO project.

- `source_snapshot_manifest.json` binds every artifact to the source project fingerprint.
- `project/` is the canonical semantic tree: function blocks, program modules,
  configuration and data types each carry an `entity.json` plus restore payloads.
- `text/` contains UTF-8 JSON, TSV, MNM and XML that can be reviewed and versioned.
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
      try{[IO.Directory]::Delete($mnmWorkRoot,$true);$uiLifecycle.cleanup_status='isolated_copy_removed'}catch{$uiLifecycle.cleanup_status='isolated_copy_cleanup_failed';$uiLifecycle.cleanup_error=$_.Exception.Message}
    }else{$uiLifecycle.cleanup_status='isolated_copy_absent'}
    if($KeepProjectOpen){
      try{$reopened=Open-Project $ProjectPath;$uiLifecycle.source_reopened_process_id=$reopened.process.Id}catch{$uiLifecycle.source_reopen_error=$_.Exception.Message}
    }
  }
  Write-Json (Join-Path $rawRoot 'ui_process_lifecycle.json') $uiLifecycle 8
  if($uiLifecycle.cleanup_status -eq 'isolated_copy_cleanup_failed'){
    [Console]::Error.WriteLine("KV_SNAPSHOT_TEMP_CLEANUP_FAILED: $($uiLifecycle.cleanup_error)")
  }
}
exit $exitCode
