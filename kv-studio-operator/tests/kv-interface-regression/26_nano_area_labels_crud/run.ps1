param(
  [string]$OutRoot='',
  [string]$KvsExe='H:/Keyence/KVS11/KVS/Kvs.exe',
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
if(-not $OutRoot){$OutRoot=Join-Path $env:TEMP ('kv_nano_area_labels_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))}
$OutRoot=[IO.Path]::GetFullPath($OutRoot)
if(Test-Path -LiteralPath $OutRoot){throw 'KV_TEST_OUTPUT_MUST_BE_NEW'}
New-Item -ItemType Directory -Force $OutRoot | Out-Null
$scriptsRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../scripts'))
$fixtures=Join-Path $OutRoot 'inputs'
New-Item -ItemType Directory -Path $fixtures | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../25_nano_traffic_crud/fixtures/phase.txt') -Destination (Join-Path $fixtures 'phase.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../25_nano_traffic_crud/fixtures/ladder.txt') -Destination (Join-Path $fixtures 'ladder.txt')
foreach($file in @(Get-ChildItem (Join-Path $PSScriptRoot 'fixtures') -File)){Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $fixtures $file.Name)}
$projectRoot=Join-Path $OutRoot 'projects'
$projectPath=Join-Path $projectRoot 'NanoAreaLabels/NanoAreaLabels.kpr'
$checklist=Join-Path $OutRoot 'CHECKLIST.md'
@'
# Checklist
## KV STUDIO
- New blank KV-NC32 traffic light project; offline editor only.
- Bind exact project path and process identity; never touch another project.
## Steps
- Create area script; read/update/delete/re-add; test global and local labels.
- Overwrite and directly delete labels; preserve neighbours and both scopes; verify persistence.
- Always close owned test processes, including failures.
'@ | Set-Content -LiteralPath $checklist -Encoding UTF8
$before=@(Get-Process Kvs -ErrorAction SilentlyContinue | ForEach-Object {@{id=$_.Id;start=$_.StartTime.ToUniversalTime().ToString('o')}})
$cases=[Collections.Generic.List[object]]::new()
$cleanup=[Collections.Generic.List[object]]::new()
$createdReceipt=''
$testError=''
$pass=$false
function Normalize([string]$Text){return $Text.Replace("`r`n","`n").TrimEnd("`r","`n")}
function Normalize-Ladder([string]$Text){return [regex]::Replace((Normalize $Text),'\b((?:CR|MR|LR|R|DM))0+(\d+)\b','$1$2')}
function Read-Fixture([string]$Name){return (Normalize ([IO.File]::ReadAllText((Join-Path $fixtures $Name))))}
function Invoke-Operation([string]$Name,[string]$Action,[int]$Row=1,[string]$Source='',[string]$Expected='',[switch]$Reject,[string]$Scope='Global'){
  Write-Host ('['+(Get-Date -Format 'HH:mm:ss')+'] '+$Name)
  $dest=Join-Path $OutRoot $Name
  $parameters=@{ProjectPath=$projectPath;OutDir=$dest;Action=$Action;Row=$Row;LabelScope=$Scope;ChecklistPath=$checklist;CreatedProjectResultPath=$script:createdReceipt}
  if($Source){$parameters.SourcePath=Join-Path $fixtures $Source}
  if($Expected){$parameters.ExpectedSourcePath=Join-Path $fixtures $Expected}
  $arguments=@('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $scriptsRoot 'workflows/manage_kv_nano_program.ps1'))
  foreach($key in $parameters.Keys){if([string]$parameters[$key]){$arguments+=@(('-'+$key),[string]$parameters[$key])}}
  $commandLine=($arguments | ForEach-Object {'"'+[regex]::Replace([regex]::Replace([string]$_,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'}) -join ' '
  $child=Start-Process powershell.exe -ArgumentList $commandLine -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $OutRoot ($Name+'.stdout.txt')) -RedirectStandardError (Join-Path $OutRoot ($Name+'.stderr.txt'))
  $null=$child.Handle
  $child.WaitForExit()
  $exitCode=$child.ExitCode
  $workflow=Get-Content -Raw -Encoding UTF8 (Join-Path $dest 'workflow_result.json')|ConvertFrom-Json
  $operation=Get-Content -Raw -Encoding UTF8 (Join-Path $dest 'artifacts/operation/nano_operation_result.json')|ConvertFrom-Json
  if(Test-Path -LiteralPath (Join-Path $dest 'artifacts/bind_created/nano_operation_result.json')){$script:createdReceipt=''}
  if($Reject){
    if($exitCode -eq 0 -or $workflow.ok -or $operation.error_code -ne 'KV_NANO_EXPECTED_SOURCE_MISMATCH'){throw "KV_TEST_STALE_SOURCE_NOT_REJECTED: $Name"}
  }else{
    if($exitCode -ne 0 -or -not $workflow.ok -or -not $operation.ok){throw "KV_TEST_WORKFLOW_FAILED: $Name inspect $dest"}
    if($Expected -and $Action -in @('ReadScript','ReadAreaScript','ReadLabels') -and (Normalize $operation.source) -cne (Read-Fixture $Expected)){throw "KV_TEST_SOURCE_MISMATCH: $Name"}
    if($Expected -and $Action -eq 'ReadLadder' -and (Normalize-Ladder $operation.source) -cne (Normalize-Ladder (Read-Fixture $Expected))){throw "KV_TEST_SOURCE_MISMATCH: $Name"}
  }
  if(-not $Reject -and $Source -and $Action -in @('CreateAreaScript','UpdateAreaScript') -and (Normalize $operation.source) -cne (Read-Fixture $Source)){throw ('KV_TEST_WRITTEN_SOURCE_MISMATCH: '+$Name)}
  $cases.Add(@{name=$Name;ok=$true;expected_rejection=[bool]$Reject;workflow_result=(Join-Path $dest 'workflow_result.json')})
  if($Action -eq 'Reopen'){$script:createdReceipt=''}
  return $operation
}

if($PlanOnly){
  & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'workflows/create_kv_project.ps1') -ProjectName NanoAreaLabels -ProjectRoot $projectRoot -CpuModel KV-NC32 -OutDir (Join-Path $OutRoot '00_create') -KvsExe $KvsExe -ChecklistPath $checklist -PlanOnly
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
  @{ok=$true;status='planned';live_verified=$false;project_path=$projectPath} | ConvertTo-Json | Set-Content (Join-Path $OutRoot 'test_result.json') -Encoding UTF8
  exit 0
}
function Assert-Traffic([string]$Prefix,[int]$FirstOutput){
  Invoke-Operation ($Prefix+'_phase') 'ReadScript' 1 '' 'phase.txt' | Out-Null
  $expectedRungs=@((Read-Fixture 'ladder.txt') -split '(?m)(?=^LDB? )'|Where-Object {$_})
  $readRungs=@()
  for($i=0;$i -lt $expectedRungs.Count;$i++){
    $r=Invoke-Operation ($Prefix+'_rung_'+($i+1)) 'ReadLadder' ($FirstOutput+$i)
    if((Normalize-Ladder $r.source) -cne (Normalize-Ladder $expectedRungs[$i])){throw ('KV_TEST_TRAFFIC_NEIGHBOUR_CHANGED: '+$i)}
    $readRungs+=Normalize $r.source
  }
  [IO.File]::WriteAllText((Join-Path $OutRoot ($Prefix+'_ladder.txt')),($readRungs -join "`n"),[Text.UTF8Encoding]::new($false))
}
try {
  $createOut=Join-Path $OutRoot '00_create'
  & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'workflows/create_kv_project.ps1') -ProjectName NanoAreaLabels -ProjectRoot $projectRoot -CpuModel KV-NC32 -OutDir $createOut -KvsExe $KvsExe -ChecklistPath $checklist 1>(Join-Path $OutRoot '00_create.stdout.txt') 2>(Join-Path $OutRoot '00_create.stderr.txt')
  if($LASTEXITCODE -ne 0){throw 'KV_TEST_BLANK_CREATE_FAILED'}
  $script:createdReceipt=Join-Path $createOut 'artifacts/create/create_project_result.json'
  $cases.Add(@{name='00_create_empty';ok=$true;workflow_result=(Join-Path $createOut 'workflow_result.json')})
  $empty=Invoke-Operation '01_blank_main' 'ReadLadder'
  if($empty.source){throw 'KV_TEST_MAIN_WAS_NOT_EMPTY'}
  Invoke-Operation '02_phase_box' 'CreateScript' 1 'phase.txt' | Out-Null
  Invoke-Operation '03_traffic_ladder' 'InsertLadder' 2 'ladder.txt' | Out-Null
  Invoke-Operation '04_area_create' 'CreateAreaScript' 2 'area.txt' | Out-Null
  Invoke-Operation '05_area_read' 'ReadAreaScript' 2 '' 'area.txt' | Out-Null
  Invoke-Operation '06_area_update' 'UpdateAreaScript' 2 'area_updated.txt' 'area.txt' | Out-Null
  Invoke-Operation '07_area_trim' 'UpdateAreaScript' 2 'area_trimmed.txt' 'area_updated.txt' | Out-Null
  Invoke-Operation '08_area_stale_rejected' 'UpdateAreaScript' 2 'area.txt' 'area_updated.txt' -Reject | Out-Null
  Invoke-Operation '09_area_unchanged' 'ReadAreaScript' 2 '' 'area_trimmed.txt' | Out-Null
  Invoke-Operation '10_area_reopen' 'Reopen' | Out-Null
  Invoke-Operation '11_area_persisted' 'ReadAreaScript' 2 '' 'area_trimmed.txt' | Out-Null
  Invoke-Operation '12_area_delete' 'DeleteAreaScript' 2 '' 'area_trimmed.txt' | Out-Null
  Invoke-Operation '13_area_deleted_reopen' 'Reopen' | Out-Null
  $first=Invoke-Operation '14_area_absent_neighbour' 'ReadLadder' 2
  if((Normalize-Ladder $first.source) -cne "LD MR100`nANB MR102`nANB MR103`nOUT R502"){throw 'KV_TEST_AREA_DELETE_NEIGHBOUR_CHANGED'}
  Invoke-Operation '15_area_readd' 'CreateAreaScript' 2 'area_trimmed.txt' | Out-Null
  foreach($scope in @('Global','Local')){
    $tag=$scope.ToLowerInvariant()
    Invoke-Operation ($tag+'_01_empty') 'ReadLabels' 1 '' 'empty.tsv' -Scope $scope | Out-Null
    Invoke-Operation ($tag+'_02_create') 'WriteLabels' 1 ($tag+'_one.tsv') 'empty.tsv' -Scope $scope | Out-Null
    Invoke-Operation ($tag+'_03_append') 'WriteLabels' 2 ($tag+'_sentinel.tsv') ($tag+'_one.tsv') -Scope $scope | Out-Null
    Invoke-Operation ($tag+'_04_overwrite') 'WriteLabels' 1 ($tag+'_updated_row.tsv') ($tag+'_two.tsv') -Scope $scope | Out-Null
    Invoke-Operation ($tag+'_05_read') 'ReadLabels' 1 '' ($tag+'_updated_two.tsv') -Scope $scope | Out-Null
    Invoke-Operation ($tag+'_06_stale_rejected') 'WriteLabels' 1 ($tag+'_one.tsv') ($tag+'_two.tsv') -Reject -Scope $scope | Out-Null
    Invoke-Operation ($tag+'_07_unchanged') 'ReadLabels' 1 '' ($tag+'_updated_two.tsv') -Scope $scope | Out-Null
  }
  Invoke-Operation '16_area_use_labels' 'UpdateAreaScript' 2 'area_labels.txt' 'area_trimmed.txt' | Out-Null
  Invoke-Operation '17_labels_reopen' 'Reopen' | Out-Null
  Invoke-Operation '18_label_area_persisted' 'ReadAreaScript' 2 '' 'area_labels.txt' | Out-Null
  foreach($scope in @('Global','Local')){
    $tag=$scope.ToLowerInvariant()
    Invoke-Operation ($tag+'_08_persisted') 'ReadLabels' 1 '' ($tag+'_updated_two.tsv') -Scope $scope | Out-Null
  }
  # Remove references before deleting their declarations.
  Invoke-Operation '19_area_restore_devices' 'UpdateAreaScript' 2 'area_trimmed.txt' 'area_labels.txt' | Out-Null
  foreach($scope in @('Local','Global')){
    $tag=$scope.ToLowerInvariant()
    Invoke-Operation ($tag+'_09_delete_first') 'DeleteLabel' 1 '' ($tag+'_updated_two.tsv') -Scope $scope | Out-Null
    Invoke-Operation ($tag+'_10_sentinel_preserved') 'ReadLabels' 1 '' ($tag+'_sentinel.tsv') -Scope $scope | Out-Null
    if($scope -eq 'Local'){Invoke-Operation 'global_after_local_delete' 'ReadLabels' 1 '' 'global_updated_two.tsv' -Scope Global | Out-Null}
    Invoke-Operation ($tag+'_11_delete_last') 'DeleteLabel' 1 '' ($tag+'_sentinel.tsv') -Scope $scope | Out-Null
    Invoke-Operation ($tag+'_12_empty') 'ReadLabels' 1 '' 'empty.tsv' -Scope $scope | Out-Null
  }
  Invoke-Operation '20_final_reopen' 'Reopen' | Out-Null
  Invoke-Operation '21_final_area' 'ReadAreaScript' 2 '' 'area_trimmed.txt' | Out-Null
  foreach($scope in @('Global','Local')){Invoke-Operation ($scope.ToLowerInvariant()+'_13_deleted_persisted') 'ReadLabels' 1 '' 'empty.tsv' -Scope $scope | Out-Null}
  # KV STUDIO retains a blank ladder row immediately after the area script.
  # Count that actual row instead of treating it as the first output rung.
  $separator=Invoke-Operation '22_final_area_separator' 'ReadLadder' 3
  if($separator.source){throw 'KV_TEST_AREA_SEPARATOR_NOT_EMPTY'}
  Assert-Traffic '22_final_traffic' 4
  $pass=$true
} catch {
  $testError=$_.Exception.Message
  Write-Host $testError
} finally {
  # Try a guarded save/close first. If a test failed in a modal window, terminate
  # only a fresh process owned by this test, after verifying PID and start time.
  if(Test-Path -LiteralPath $projectPath){
    try{Invoke-Operation '99_close' 'Close' | Out-Null;$cleanup.Add(@{method='workflow_close';ok=$true})}catch{$cleanup.Add(@{method='workflow_close';ok=$false;error=$_.Exception.Message});$pass=$false}
  }
  $owned=@{}
  foreach($file in @(Get-ChildItem -LiteralPath $OutRoot -Recurse -Filter 'launched_process.json' -File)){
    $record=Get-Content -Raw -Encoding UTF8 $file.FullName|ConvertFrom-Json
    $owned[[string]$record.process_id]=[string]$record.process_start_utc
  }
  # Also cover successful creation receipts from older versions of the runner.
  foreach($file in @(Get-ChildItem -LiteralPath $OutRoot -Recurse -Filter 'create_project_result.json' -File)){
    $record=Get-Content -Raw -Encoding UTF8 $file.FullName|ConvertFrom-Json
    if($record.process_id -and $record.process_start_utc){$owned[[string]$record.process_id]=[string]$record.process_start_utc}
  }
  foreach($process in @(Get-Process Kvs -ErrorAction SilentlyContinue)){
    $start=$process.StartTime.ToUniversalTime().ToString('o')
    if(@($before|Where-Object {$_.id -eq $process.Id -and $_.start -eq $start}).Count){continue}
    $record=Get-CimInstance Win32_Process -Filter ('ProcessId='+$process.Id)
    $pathPattern='(?:^|\s)(?:"'+[regex]::Escape($projectPath)+'"|'+[regex]::Escape($projectPath)+')(?=\s|$)'
    $isOwned=($owned.ContainsKey([string]$process.Id) -and $owned[[string]$process.Id] -eq $start) -or ($record.CommandLine -match $pathPattern)
    if(-not $isOwned){continue}
    try{
      $again=Get-Process -Id $process.Id -ErrorAction Stop
      if($again.ProcessName -ne 'Kvs' -or $again.StartTime.ToUniversalTime().ToString('o') -ne $start){throw 'KV_TEST_CLEANUP_IDENTITY_CHANGED'}
      $again.Kill()
      if(-not $again.WaitForExit(8000)){throw 'KV_TEST_CLEANUP_EXIT_TIMEOUT'}
      $cleanup.Add(@{method='owned_process_fallback';process_id=$process.Id;ok=$true})
    }catch{$cleanup.Add(@{method='owned_process_fallback';process_id=$process.Id;ok=$false;error=$_.Exception.Message});$pass=$false}
  }
  $after=@(Get-Process Kvs -ErrorAction SilentlyContinue|ForEach-Object {@{id=$_.Id;start=$_.StartTime.ToUniversalTime().ToString('o')}})
  $leaks=@($after|Where-Object {$owned.ContainsKey([string]$_.id) -and $owned[[string]$_.id] -eq $_.start})
  if($leaks.Count){$pass=$false;$testError+=' KV_TEST_OWNED_PROCESS_LEAK'}
  @{ok=$pass;project_path=$projectPath;cpu='KV-NC32';cases=$cases.ToArray();case_count=$cases.Count;error=$testError;cleanup=$cleanup.ToArray();before_processes=$before;after_processes=$after;leaked_owned_processes=$leaks;hardware_run_verified=$false} |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutRoot 'test_result.json') -Encoding UTF8
}
Write-Host ('Result: '+(Join-Path $OutRoot 'test_result.json'))
if(-not $pass){exit 41}
exit 0
