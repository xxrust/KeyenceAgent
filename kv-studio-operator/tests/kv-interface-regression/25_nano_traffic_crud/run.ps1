param(
  [string]$OutRoot='',
  [string]$KvsExe='H:/Keyence/KVS11/KVS/Kvs.exe',
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
if(-not $OutRoot){$OutRoot=Join-Path $env:TEMP ('kv_nano_traffic_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))}
$OutRoot=[IO.Path]::GetFullPath($OutRoot)
if(Test-Path -LiteralPath $OutRoot){throw 'KV_TEST_OUTPUT_MUST_BE_NEW'}
New-Item -ItemType Directory -Force $OutRoot | Out-Null
$scriptsRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../scripts'))
$fixtures=Join-Path $PSScriptRoot 'fixtures'
$projectRoot=Join-Path $OutRoot 'projects'
$projectPath=Join-Path $projectRoot 'NanoTraffic/NanoTraffic.kpr'
$checklist=Join-Path $OutRoot 'CHECKLIST.md'
@'
# Checklist
## KV STUDIO
- New blank KV-NC32 traffic light project; offline editor only.
- Bind exact project path and process identity; never touch another project.
## Steps
- Create script and ladder; read; update; reject stale source; delete; re-add.
- Compile every write; close and reopen the same project; read every final rung.
- Always close owned test processes, including failures.
'@ | Set-Content -LiteralPath $checklist -Encoding UTF8
$before=@(Get-Process Kvs -ErrorAction SilentlyContinue | ForEach-Object {@{id=$_.Id;start=$_.StartTime.ToUniversalTime().ToString('o')}})
$cases=[Collections.Generic.List[object]]::new()
$cleanup=[Collections.Generic.List[object]]::new()
$createdReceipt=''
$testError=''
$pass=$false
if($PlanOnly){
  & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'workflows/create_kv_project.ps1') -ProjectName NanoTraffic -ProjectRoot $projectRoot -CpuModel KV-NC32 -OutDir (Join-Path $OutRoot '00_create') -KvsExe $KvsExe -ChecklistPath $checklist -PlanOnly
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
  @{ok=$true;status='planned';live_verified=$false;project_path=$projectPath;source_files=@(Get-ChildItem $fixtures -File|ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash $_.FullName).Hash}})} |
    ConvertTo-Json -Depth 6 | Set-Content (Join-Path $OutRoot 'test_result.json') -Encoding UTF8
  exit 0
}
function Normalize([string]$Text){return $Text.Replace("`r`n","`n").TrimEnd("`r","`n")}
function Normalize-Ladder([string]$Text){return [regex]::Replace((Normalize $Text),'\b((?:CR|MR|LR|R|DM))0+(\d+)\b','$1$2')}
function Read-Fixture([string]$Name){return (Normalize ([IO.File]::ReadAllText((Join-Path $fixtures $Name))))}
function Invoke-Operation([string]$Name,[string]$Action,[int]$Row=1,[string]$Source='',[string]$Expected='',[switch]$Reject){
  Write-Host ('['+(Get-Date -Format 'HH:mm:ss')+'] '+$Name)
  $dest=Join-Path $OutRoot $Name
  $parameters=@{ProjectPath=$projectPath;OutDir=$dest;Action=$Action;Row=$Row;ChecklistPath=$checklist;CreatedProjectResultPath=$script:createdReceipt}
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
    if($Expected -and $Action -eq 'ReadScript' -and (Normalize $operation.source) -cne (Read-Fixture $Expected)){throw "KV_TEST_SOURCE_MISMATCH: $Name"}
    if($Expected -and $Action -eq 'ReadLadder' -and (Normalize-Ladder $operation.source) -cne (Normalize-Ladder (Read-Fixture $Expected))){throw "KV_TEST_SOURCE_MISMATCH: $Name"}
  }
  $cases.Add(@{name=$Name;ok=$true;expected_rejection=[bool]$Reject;workflow_result=(Join-Path $dest 'workflow_result.json')})
  if($Action -eq 'Reopen'){$script:createdReceipt=''}
  return $operation
}
try {
  Write-Host 'Creating an empty KV-NC32 project.'
  $createOut=Join-Path $OutRoot '00_create'
  & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'workflows/create_kv_project.ps1') -ProjectName NanoTraffic -ProjectRoot $projectRoot -CpuModel KV-NC32 -OutDir $createOut -KvsExe $KvsExe -ChecklistPath $checklist 1>(Join-Path $OutRoot '00_create.stdout.txt') 2>(Join-Path $OutRoot '00_create.stderr.txt')
  if($LASTEXITCODE -ne 0){throw 'KV_TEST_BLANK_CREATE_FAILED'}
  $script:createdReceipt=Join-Path $createOut 'artifacts/create/create_project_result.json'
  $cases.Add(@{name='00_create_empty';ok=$true;workflow_result=(Join-Path $createOut 'workflow_result.json')})
  $empty=Invoke-Operation '01_blank_main' 'ReadLadder'
  if($empty.source){throw 'KV_TEST_MAIN_WAS_NOT_EMPTY'}
  Invoke-Operation '02_phase_create' 'CreateScript' 1 'phase.txt' | Out-Null
  Invoke-Operation '03_diagnostic_create' 'CreateScript' 2 'diagnostic.txt' | Out-Null
  Invoke-Operation '04_ladder_create' 'InsertLadder' 3 'ladder.txt' | Out-Null
  Invoke-Operation '05_phase_read' 'ReadScript' 1 '' 'phase.txt' | Out-Null
  Invoke-Operation '06_diagnostic_read' 'ReadScript' 2 '' 'diagnostic.txt' | Out-Null
  Invoke-Operation '07_diagnostic_update' 'UpdateScript' 2 'diagnostic_updated.txt' 'diagnostic.txt' | Out-Null
  Invoke-Operation '08_statement_delete' 'UpdateScript' 2 'diagnostic_trimmed.txt' 'diagnostic_updated.txt' | Out-Null
  Invoke-Operation '09_stale_source_rejected' 'UpdateScript' 2 'diagnostic_updated.txt' 'diagnostic.txt' -Reject | Out-Null
  Invoke-Operation '10_unchanged_after_rejection' 'ReadScript' 2 '' 'diagnostic_trimmed.txt' | Out-Null
  Invoke-Operation '11_temporary_rung_create' 'InsertLadder' 3 'temporary_ladder.txt' | Out-Null
  Invoke-Operation '12_temporary_rung_read' 'ReadLadder' 3 '' 'temporary_ladder.txt' | Out-Null
  Invoke-Operation '13_temporary_rung_update' 'UpdateLadder' 3 'temporary_ladder_updated.txt' 'temporary_ladder.txt' | Out-Null
  Invoke-Operation '14_updated_rung_read' 'ReadLadder' 3 '' 'temporary_ladder_updated.txt' | Out-Null
  Invoke-Operation '15_temporary_rung_delete' 'DeleteLadder' 3 '' 'temporary_ladder_updated.txt' | Out-Null
  Invoke-Operation '16_script_delete' 'DeleteScript' 2 '' 'diagnostic_trimmed.txt' | Out-Null
  Invoke-Operation '17_adjacent_script_preserved' 'ReadScript' 1 '' 'phase.txt' | Out-Null
  # Deleted diagnostic and temporary rungs must be absent: first output rung moves to row 2.
  $firstRung=Invoke-Operation '18_deleted_rows_absent' 'ReadLadder' 2
  if((Normalize $firstRung.source) -cne "LD MR100`nANB MR102`nANB MR103`nOUT R502"){throw 'KV_TEST_DELETE_DID_NOT_PRESERVE_NEIGHBOR'}
  Invoke-Operation '19_script_readd' 'CreateScript' 2 'diagnostic_trimmed.txt' | Out-Null
  Invoke-Operation '20_reopen_same_project' 'Reopen' | Out-Null
  Invoke-Operation '21_persisted_phase' 'ReadScript' 1 '' 'phase.txt' | Out-Null
  Invoke-Operation '22_persisted_diagnostic' 'ReadScript' 2 '' 'diagnostic_trimmed.txt' | Out-Null
  $rungs=@((Read-Fixture 'ladder.txt') -split '(?m)(?=^LDB? )' | Where-Object {$_})
  $readRungs=@()
  for($i=0;$i -lt $rungs.Count;$i++){
    $r=Invoke-Operation ('23_persisted_ladder_'+($i+1)) 'ReadLadder' ($i+3)
    if((Normalize-Ladder $r.source) -cne (Normalize-Ladder $rungs[$i])){throw ('KV_TEST_PERSISTED_LADDER_MISMATCH: '+($i+1))}
    $readRungs+=Normalize $r.source
  }
  [IO.File]::WriteAllText((Join-Path $OutRoot 'final_ladder_readback.txt'),($readRungs -join "`n"),[Text.UTF8Encoding]::new($false))
  & python (Join-Path $PSScriptRoot 'verify_logic.py') --run $OutRoot
  if($LASTEXITCODE -ne 0){throw 'KV_TEST_TRAFFIC_SOURCE_SEMANTICS_FAILED'}
  $cases.Add(@{name='24_offline_source_semantics';ok=$true;result=(Join-Path $OutRoot 'logic_verification.json');plc_runtime_verified=$false})
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
