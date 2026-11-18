param(
 [Parameter(Mandatory=$true)][string]$ProjectPath,
 [Parameter(Mandatory=$true)][string]$OutDir,
 [string]$KvsExe='H:/Keyence/KVS11/KVS/Kvs.exe',
 [int]$TimeoutSeconds=900,
 [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
. (Join-Path $root 'workflow_tools/kv_mnm_text.ps1')
. (Join-Path $root 'kv_window_binding.ps1')
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$OutDir=[IO.Path]::GetFullPath($OutDir)
if(-not(Test-Path -LiteralPath $ProjectPath -PathType Leaf)){throw 'KV_PROJECT_FILE_MISSING'}
if(Test-Path -LiteralPath $OutDir){throw 'KV_NANO_SNAPSHOT_OUTPUT_MUST_BE_NEW'}
$sourceDir=Split-Path -Parent $ProjectPath
if(($OutDir+'\').StartsWith($sourceDir.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'KV_NANO_SNAPSHOT_OUTPUT_INSIDE_SOURCE_FORBIDDEN'}
New-Item -ItemType Directory -Force $OutDir|Out-Null
function Write-Json($Path,$Value){ConvertTo-Json -InputObject $Value -Depth 24|Set-Content -LiteralPath $Path -Encoding UTF8}
function Inventory-Files([string]$Directory){
 @(Get-ChildItem -LiteralPath $Directory -File -Recurse -Force|Sort-Object FullName|ForEach-Object {
  @{path=$_.FullName.Substring($Directory.TrimEnd('\').Length+1);length=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
 })
}
$snapshot=Join-Path $OutDir 'snapshot'
$raw=Join-Path $snapshot 'raw'
$mnmDir=Join-Path $raw 'mnm'
$semantic=Join-Path $snapshot 'project'
$copyDir=Join-Path $OutDir 'work/project'
New-Item -ItemType Directory -Force $raw,$semantic,$copyDir|Out-Null
$before=Inventory-Files $sourceDir
Write-Json (Join-Path $raw 'source_inventory_before.json') $before
# A complete directory copy preserves the Nano project's sibling binary banks.
Get-ChildItem -LiteralPath $sourceDir -Force|Copy-Item -Destination $copyDir -Recurse -Force
$copyPath=Join-Path $copyDir ([IO.Path]::GetFileName($ProjectPath))
$copied=Inventory-Files $copyDir
if((ConvertTo-Json -InputObject $before -Depth 6 -Compress) -cne (ConvertTo-Json -InputObject $copied -Depth 6 -Compress)){throw 'KV_NANO_SNAPSHOT_COPY_HASH_MISMATCH'}
$ownership=Join-Path $OutDir 'ownership.json'
$manifest=[ordered]@{schema_version=1;kind='nano';status='collecting';ok=$false;source_project=$ProjectPath;copy_project=$copyPath;cpu_model='';stages=@();modules=@();source_unchanged=$false;owned_process_closed=$false;limitations=@('KV-NC32 offline project settings only; no PLC connection or runtime values.','Unit main tables include built-in Port0 and NC1EP/NC16EXT. Nested <setting> dialogs are outside this snapshot scope.','MNM text includes ladder and script source; Nano MNM import cannot restore script blocks.','Device comment CSV covers global comments; complete original comment banks are archived in raw/source. No system labels or comments are written.');artifacts=@()}
$manifestPath=Join-Path $snapshot 'source_snapshot_manifest.json'
Write-Json $manifestPath $manifest
@'
# Checklist
## KV STUDIO
- Work only on a verified copy of the saved KV-NC32 project.
- Never connect to or download to a PLC; preserve existing user windows.
## Steps
- Read live module order, MNM, global and every module's local labels.
- Read complete unit main tables including serial Port0, six CPU positioning pages and global comments.
- Close the owned copy, check source hashes and materialize indexed text and raw evidence.
'@|Set-Content (Join-Path $OutDir 'CHECKLIST.md') -Encoding UTF8
function Session-Plan([string]$Action,[string]$Phase){
 $p=New-KvWorkflowPlan -ScriptsRoot $root -Operation ('nano_snapshot_'+$Action) -ProjectPath $copyPath -OutDir (Join-Path $OutDir $Phase) -TimeoutSeconds 120
 $dest=Join-Path $p.artifact_root 'session'
 Add-KvWorkflowStep -Plan $p -Name 'session' -Script 'runner_children/nano_snapshot_session_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$copyPath;OutDir=$dest;Action=$Action;KvsExe=$KvsExe;OwnershipPath=$ownership}
 return $p
}
$failure=''
try{
 $initial=Session-Plan 'Inventory' '01_inventory'
 Submit-KvWorkflowPlan -Plan $initial -ScriptsRoot $root -PlanOnly:$PlanOnly
 if($PlanOnly){$manifest.status='planned';$manifest.ok=$true;$manifest.live_verified=$false;return}
 $inventory=Get-Content (Join-Path $initial.artifact_root 'session/nano_snapshot_session_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if(-not $inventory.ok){throw 'KV_NANO_SNAPSHOT_INVENTORY_FAILED'}
 $manifest.cpu_model=$inventory.session.cpu_model;$manifest.modules=@($inventory.modules)
 $manifest.stages+=@{name='live_inventory';status='complete';receipt=(Join-Path $initial.run_root 'workflow_result.json')}
 $plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'nano_snapshot_collect' -ProjectPath $copyPath -OutDir (Join-Path $OutDir '02_collect') -TimeoutSeconds $TimeoutSeconds
 function Add-Read([string]$Name,[string]$Script,[hashtable]$Parameters){
  $dest=Join-Path $plan.artifact_root $Name
  $Parameters.ProjectPath=$copyPath;$Parameters.OutDir=$dest
  Add-KvWorkflowStep -Plan $plan -Name $Name -Script $Script -OutDir $dest -Parameters $Parameters
 }
 $mnmDir=Join-Path $raw 'mnm'
 Add-Read 'mnm' 'runner_children/export_mnm_browse_default_folder_guarded.ps1' @{ExportDir=$mnmDir;RestartKvs=$false;KvsExe=$KvsExe}
 Add-Read 'labels_global' 'runner_children/nano_box_script_guarded.ps1' @{Action='ReadLabels';LabelScope='Global'}
 $index=0
 foreach($module in $manifest.modules){Add-Read ('labels_local_'+(++$index)) 'runner_children/nano_box_script_guarded.ps1' @{Action='ReadLabels';LabelScope='Local';ProgramName=$module.name}}
 Add-Read 'units' 'runner_children/nano_unit_editor_guarded.ps1' @{Action='Query'}
 Add-Read 'units_close' 'runner_children/nano_unit_editor_guarded.ps1' @{Action='Cancel'}
 Add-Read 'position_open' 'runner_children/nano_cpu_position_guarded.ps1' @{Action='Open'}
 $pages=@('点参数','点参数通用设定','I/O 设定','原点复归设定','JOG设定','比较器设定');$index=0
 foreach($page in $pages){Add-Read ('position_'+(++$index)) 'runner_children/nano_cpu_position_guarded.ps1' @{Action='ReadPage';PageName=$page}}
 Add-Read 'position_close' 'runner_children/nano_cpu_position_guarded.ps1' @{Action='Close'}
 Add-Read 'comments_global' 'runner_children/export_device_comments_guarded.ps1' @{ExportDir=(Join-Path $raw 'comments');FileBaseName=('nano_comments_'+[guid]::NewGuid().ToString('N'));CloseProjectWhenLaunched=$false;KvsExe=$KvsExe}
 Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root
 $manifest.stages+=@{name='collection';status='complete';receipt=(Join-Path $plan.run_root 'workflow_result.json')}
 # Require exact equality between live tree modules and this run's MNM exports.
 $mnms=@(Get-ChildItem -LiteralPath $mnmDir -Filter '*.mnm' -File|ForEach-Object {Read-KvMnmFile $_.FullName})
 $expected=@($manifest.modules.name|Sort-Object);$actual=@($mnms.module_name|Sort-Object)
 if(($expected -join "`n") -cne ($actual -join "`n")){throw 'KV_NANO_SNAPSHOT_MNM_MODULE_SET_MISMATCH'}
 Write-Json (Join-Path $semantic 'modules.json') $manifest.modules
 $index=0
 foreach($module in $manifest.modules){
  $mnm=@($mnms|Where-Object {$_.module_name -ceq $module.name})[0]
  $moduleDir=Join-Path $semantic ('program_'+(++$index));New-Item -ItemType Directory -Force $moduleDir|Out-Null
  [IO.File]::WriteAllText((Join-Path $moduleDir 'program.mnm.txt'),$mnm.text,[Text.UTF8Encoding]::new($false))
  # Original script lines are exported as semicolon comments alongside compiled
  # ladder. Preserve contiguous runs after removing exactly one prefix. Ordinary
  # rung comments remain comments; do not invent a script classification.
  $blocks=[Collections.Generic.List[object]]::new();$lines=@($mnm.text -split '\r?\n');$buffer=[Collections.Generic.List[string]]::new();$startLine=0
  for($lineIndex=4;$lineIndex -le $lines.Count;$lineIndex++){
   if($lineIndex -lt $lines.Count -and $lines[$lineIndex].StartsWith(';')){
    if(-not $buffer.Count){$startLine=$lineIndex+1};$buffer.Add($lines[$lineIndex].Substring(1))
   }elseif($buffer.Count){$blocks.Add(@{mnm_start_line=$startLine;text=($buffer -join "`n")});$buffer.Clear()}
  }
  Write-Json (Join-Path $moduleDir 'mnm_comment_blocks.json') @($blocks)
  $labels=Get-Content (Join-Path $plan.artifact_root "labels_local_$index/nano_operation_result.json") -Raw -Encoding UTF8|ConvertFrom-Json
  if(-not $labels.ok -or $labels.program -cne $module.name -or $labels.label_scope -ne 'Local'){throw 'KV_NANO_SNAPSHOT_LOCAL_LABEL_SCOPE_MISMATCH'}
  [IO.File]::WriteAllText((Join-Path $moduleDir 'labels.tsv'),$labels.source,[Text.UTF8Encoding]::new($false))
  Write-Json (Join-Path $moduleDir 'metadata.json') @{name=$module.name;category=$module.category;order=$module.order;source_encoding=$mnm.encoding;mnm_sha256=$mnm.sha256;label_count=$labels.label_count}
 }
 $labels=Get-Content (Join-Path $plan.artifact_root 'labels_global/nano_operation_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
 [IO.File]::WriteAllText((Join-Path $semantic 'global_labels.tsv'),$labels.source,[Text.UTF8Encoding]::new($false))
 Copy-Item -LiteralPath (Join-Path $plan.artifact_root 'units/units.json') -Destination (Join-Path $semantic 'units.json')
 $units=Get-Content (Join-Path $semantic 'units.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $serial=@($units|Where-Object {$_.unit_index -eq 0})
 if($serial.Count -ne 1 -or -not @($serial[0].rows|Where-Object {$_[1] -eq '波特率'}).Count){throw 'KV_NANO_SNAPSHOT_PORT0_ROWS_MISSING'}
 Write-Json (Join-Path $semantic 'serial_port0.json') @{unit_index=0;model=$serial[0].model;rows=([string[][]]$serial[0].rows)}
 $positionDir=Join-Path $semantic 'cpu_position';New-Item -ItemType Directory -Force $positionDir|Out-Null
 $index=0
 foreach($page in $pages){
  $index++;$table=Join-Path $plan.artifact_root "position_$index/table.tsv"
  if(-not(Test-Path $table)){throw 'KV_NANO_SNAPSHOT_POSITION_TABLE_MISSING'}
  Copy-Item -LiteralPath $table -Destination (Join-Path $positionDir "$index.tsv")
 }
 Write-Json (Join-Path $positionDir 'pages.json') $pages
 $comments=Get-Content (Join-Path $plan.artifact_root 'comments_global/device_comments_export_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Copy-Item -LiteralPath $comments.artifact_path -Destination (Join-Path $semantic 'global_comments.csv')
 $entities=[Collections.Generic.List[object]]::new();$index=0
 foreach($module in $manifest.modules){
  $index++;$entities.Add(@{id=('program:'+$module.name);kind='program';name=$module.name;category=$module.category;order=$module.order;path="program_$index/program.mnm.txt";labels="program_$index/labels.tsv"})
 }
 $entities.Add(@{id='labels:global';kind='labels';path='global_labels.tsv'})
 $entities.Add(@{id='config:units';kind='nano_unit_parameters';path='units.json'})
 $entities.Add(@{id='config:serial_port0';kind='nano_serial_port';path='serial_port0.json'})
 $entities.Add(@{id='config:cpu_position';kind='nano_cpu_position';path='cpu_position/pages.json'})
 $entities.Add(@{id='comments:global';kind='device_comments';path='global_comments.csv'})
 $indexDir=Join-Path $semantic '_index';New-Item -ItemType Directory -Force $indexDir|Out-Null
 @($entities|ForEach-Object {$_|ConvertTo-Json -Depth 8 -Compress})|Set-Content (Join-Path $indexDir 'entities.jsonl') -Encoding UTF8
 $overview=@('# Nano project snapshot','',('CPU: '+$manifest.cpu_model),('Programs: '+$manifest.modules.Count),('Units: '+@($units).Count),'','Programs and labels: modules.json, program_N/, global_labels.tsv.','Unit and serial parameters: units.json, serial_port0.json.','Position parameters: cpu_position/pages.json and six TSV tables.','Comments: global_comments.csv; original comment banks in ../raw/source.','','Scope limits:')+$manifest.limitations
 $overview|Set-Content (Join-Path $semantic 'overview.md') -Encoding UTF8
 $manifest.stages+=@{name='semantic_validation';status='complete';module_count=$mnms.Count;local_label_tables=$manifest.modules.Count;position_pages=6;unit_count=@($units).Count}
}catch{$failure=$_.Exception.Message;$manifest.error_code=($failure -split ':')[0];$manifest.message=$failure}
finally{
 if(-not $PlanOnly -and (Test-Path $ownership)){
  try{
   $cleanup=Session-Plan 'Close' '03_close'
   Submit-KvWorkflowPlan -Plan $cleanup -ScriptsRoot $root
   $manifest.owned_process_closed=$true
  }catch{
   $manifest.cleanup_error=$_.Exception.Message;if(-not $failure){$failure=$_.Exception.Message}
   # A failed copy can be discarded. Never terminate an unowned user process.
   $owner=Get-Content $ownership -Raw -Encoding UTF8|ConvertFrom-Json
   $p=Get-Process -Id $owner.process_id -ErrorAction SilentlyContinue
   if($p -and $p.ProcessName -eq 'Kvs' -and $p.StartTime.ToUniversalTime().ToString('o') -eq $owner.process_start_utc){
    $cmd=[string](Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)").CommandLine
    if(Test-KvProjectCommandLine $cmd $copyPath){Stop-Process -Id $p.Id -Force;$null=$p.WaitForExit(8000);$manifest.owned_process_closed=$p.HasExited;$manifest.cleanup_forced=$true}
   }elseif(-not $p){$manifest.owned_process_closed=$true}
  }
 }
 $after=Inventory-Files $sourceDir
 Write-Json (Join-Path $raw 'source_inventory_after.json') $after
 $manifest.source_unchanged=(ConvertTo-Json -InputObject $before -Depth 6 -Compress) -ceq (ConvertTo-Json -InputObject $after -Depth 6 -Compress)
 if(-not $manifest.source_unchanged){$failure='KV_NANO_SNAPSHOT_SOURCE_CHANGED'}
 if(-not $PlanOnly){
  # Raw archive is the verified input, not the UI-mutated work directory.
  $archive=Join-Path $raw 'source';New-Item -ItemType Directory -Force $archive|Out-Null
  Get-ChildItem -LiteralPath $sourceDir -Force|Copy-Item -Destination $archive -Recurse -Force
  $archived=Inventory-Files $archive
  if((ConvertTo-Json -InputObject $before -Depth 6 -Compress) -cne (ConvertTo-Json -InputObject $archived -Depth 6 -Compress)){$failure='KV_NANO_SNAPSHOT_SOURCE_ARCHIVE_MISMATCH'}
  $manifest.ok=(-not $failure -and $manifest.owned_process_closed -and $manifest.stages.Count -eq 3)
  $manifest.status=if($manifest.ok){'ready'}else{'failed'}
  $manifest.artifacts=@(Get-ChildItem -LiteralPath $semantic,$raw -Recurse -File -ErrorAction SilentlyContinue|ForEach-Object {@{path=$_.FullName.Substring($snapshot.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash;length=$_.Length}})
  Write-Json (Join-Path $snapshot 'text_index.json') $manifest.artifacts
 }
 Write-Json $manifestPath $manifest
 Write-Json (Join-Path $OutDir 'workflow_result.json') @{ok=$manifest.ok;status=$manifest.status;live_verified=($manifest.status -eq 'ready');manifest=$manifestPath;source_unchanged=$manifest.source_unchanged;owned_process_closed=$manifest.owned_process_closed;error=$failure}
}
if($failure -or (-not $PlanOnly -and -not $manifest.ok)){exit 1}
