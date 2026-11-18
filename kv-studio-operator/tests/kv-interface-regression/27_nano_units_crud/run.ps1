param(
 [string]$OutRoot='',
 [string]$KvsExe='H:/Keyence/KVS11/KVS/Kvs.exe',
 [string]$CreatedProjectResultPath='',
 [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
if(-not $OutRoot){$OutRoot=Join-Path $env:TEMP ('kv_nano_units_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))}
$OutRoot=[IO.Path]::GetFullPath($OutRoot)
if(Test-Path -LiteralPath $OutRoot){throw 'KV_TEST_OUTPUT_MUST_BE_NEW'}
New-Item -ItemType Directory -Force $OutRoot|Out-Null
$scriptsRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../scripts'))
$cases=[Collections.Generic.List[object]]::new()
$owned=[Collections.Generic.List[object]]::new()
$before=@(Get-Process Kvs -ErrorAction SilentlyContinue|ForEach-Object {[pscustomobject]@{id=$_.Id;start=$_.StartTime.ToUniversalTime().ToString('o')}})
$projectPath='';$errorText='';$cleanup=@();$receipt=$CreatedProjectResultPath
$checklist=Join-Path $OutRoot 'CHECKLIST.md'
@'
# Checklist
## KV STUDIO
- Blank KV-NC32 project only, no PLC transfer.
- Read CPU serial Port0, KV-NC1EP and KV-NC16EXT main parameters.
## Steps
- Add both modules; modify each unit; reject stale values.
- Save, reopen and compare every parameter, restore, delete and re-add.
- Preserve all preexisting processes and close every owned process.
'@|Set-Content $checklist -Encoding UTF8
if($PlanOnly){
 & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'workflows/create_kv_project.ps1') -ProjectName NanoUnitsTest -ProjectRoot (Join-Path $OutRoot 'projects') -CpuModel KV-NC32 -KvsExe $KvsExe -ChecklistPath $checklist -OutDir (Join-Path $OutRoot '00_create') -PlanOnly
 if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
 @{ok=$true;planned=$true;live_verified=$false}|ConvertTo-Json|Set-Content (Join-Path $OutRoot 'test_result.json') -Encoding UTF8
 exit 0
}
function Check([string]$Name,[bool]$Ok){$cases.Add(@{name=$Name;ok=$Ok});if(-not $Ok){throw "KV_NANO_UNIT_TEST_FAILED:$Name"}}
function Track {
 foreach($process in @(Get-Process Kvs -ErrorAction SilentlyContinue)){
  $cmd=[string](Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)").CommandLine
  if($projectPath -and $cmd.Contains($projectPath) -and -not @($before|Where-Object {$_.id -eq $process.Id}).Count){
   $start=$process.StartTime.ToUniversalTime().ToString('o')
   if(-not @($owned|Where-Object {$_.id -eq $process.Id -and $_.start -eq $start}).Count){$owned.Add(@{id=$process.Id;start=$start})}
  }
 }
}
function Program([string]$Name,[string]$Action){
 $dest=Join-Path $OutRoot $Name
 $args=@{ProjectPath=$projectPath;OutDir=$dest;Action=$Action;CreatedProjectResultPath=$script:receipt;ChecklistPath=$checklist}
 & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'workflows/manage_kv_nano_program.ps1') @args
 Track
 if($LASTEXITCODE -ne 0){throw "KV_TEST_PROGRAM_FAILED:$Name"}
 $r=Get-Content (Join-Path $dest 'artifacts/operation/nano_operation_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Check $Name ([bool]$r.ok)
 if($Action -eq 'Reopen'){$script:receipt=''}
 return $r
}
function Unit([string]$Name,[string]$Action,[hashtable]$Parameters=@{},[switch]$Reject){
 Write-Host ('['+(Get-Date -Format 'HH:mm:ss')+'] '+$Name)
 $dest=Join-Path $OutRoot $Name
 $args=@{ProjectPath=$projectPath;OutDir=$dest;Action=$Action}
 foreach($key in $Parameters.Keys){$args[$key]=$Parameters[$key]}
 & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'workflows/manage_kv_nano_units.ps1') @args
 $exit=$LASTEXITCODE;Track
 $r=Get-Content (Join-Path $dest 'artifacts/units/nano_unit_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $workflow=Get-Content (Join-Path $dest 'workflow_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($Reject){Check $Name ($exit -ne 0 -and -not $workflow.ok -and $r.error_code -eq 'KV_NANO_UNIT_EXPECTED_VALUE_MISMATCH')}
 else{Check $Name ($exit -eq 0 -and $workflow.ok -and $r.ok)}
 return $r
}
function SnapshotPath([string]$Name){return (Join-Path (Join-Path $OutRoot $Name) 'artifacts/units/units.json')}
function EqualSnapshot([string]$Name,[string]$Actual,[string]$Expected){
 $a=Get-Content $Actual -Raw -Encoding UTF8|ConvertFrom-Json;$b=Get-Content $Expected -Raw -Encoding UTF8|ConvertFrom-Json
 Check $Name ((ConvertTo-Json -InputObject @($a) -Depth 14 -Compress) -ceq (ConvertTo-Json -InputObject @($b) -Depth 14 -Compress))
}
try{
 if(-not $receipt){
  $create=Join-Path $OutRoot '00_create'
  & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'workflows/create_kv_project.ps1') -ProjectName NanoUnitsTest -ProjectRoot (Join-Path $OutRoot 'projects') -CpuModel KV-NC32 -KvsExe $KvsExe -ChecklistPath $checklist -OutDir $create
  if($LASTEXITCODE -ne 0){throw 'KV_TEST_BLANK_CREATE_FAILED'}
  $receipt=Join-Path $create 'artifacts/create/create_project_result.json'
 }
 $created=Get-Content $receipt -Raw -Encoding UTF8|ConvertFrom-Json
 $projectPath=[IO.Path]::GetFullPath($created.project_path)
 if(-not $created.ok -or $created.cpu_model_actual -ne 'KV-NC32'){throw 'KV_TEST_EMPTY_NANO_RECEIPT_REQUIRED'}
 # A supplied receipt explicitly adopts this previously created blank project.
 $owned.Add(@{id=[int]$created.process_id;start=[string]$created.process_start_utc})
 $before=@($before|Where-Object {$_.id -ne [int]$created.process_id})
 $empty=Program '01_blank_main' 'ReadLadder'
 Check 'Main is empty' (-not $empty.source)
 $null=Program '02_bind_reopen' 'Reopen'
 $base=Unit '03_cpu_baseline' 'Query'
 Check 'only CPU in empty project' (@($base.units).Count -eq 1 -and $base.units[0].model -eq 'KV-NC32')
 $null=Unit '04_add_ep' 'Add' @{UnitIndex=1;ExpectedModel='KV-NC1EP'}
 $null=Unit '05_add_ext' 'Add' @{UnitIndex=2;ExpectedModel='KV-NC16EXT*'}
 $all=Unit '06_modules_baseline' 'Query'
 $comments=@(Get-ChildItem (Split-Path -Parent $projectPath) -File|Where-Object {$_.Extension -in @('.cm1','.cm2')}|ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash $_.FullName).Hash}})
 Check 'comment banks exist' ($comments.Count -eq 2)
 Check 'three units scanned' (@($all.units).Count -eq 3)
 Check 'all NC1EP rows captured including offscreen rows' (@($all.units[1].rows).Count -eq 67)
 [string[][]]$modeRows=$all.units[0].rows
 $modeRows[3][2]='KV 模式（上位链路）';$modeRows[4][2]='9600bps'
 $modePath=Join-Path $OutRoot 'serial_kv_mode_target.json'
 ConvertTo-Json -InputObject $modeRows -Depth 12|Set-Content $modePath -Encoding UTF8
 $restoreModePath=Join-Path $OutRoot 'serial_original_mode_target.json'
 ConvertTo-Json -InputObject ([string[][]]$all.units[0].rows) -Depth 12|Set-Content $restoreModePath -Encoding UTF8
 $null=Unit '07a_serial_mode_write' 'SetParameter' @{UnitIndex=0;ExpectedModel='KV-NC32';ParameterName='动作模式';ExpectedValue='KV STUDIO 模式(＊)';Value='KV 模式（上位链路）';ExpectedAfterRowsPath=$modePath}
 $null=Unit '07_serial_write' 'SetParameter' @{UnitIndex=0;ExpectedModel='KV-NC32';ParameterName='波特率';ExpectedValue='9600bps';Value='19200bps'}
 $null=Unit '08_ep_write' 'SetParameter' @{UnitIndex=1;ExpectedModel='KV-NC1EP';ParameterName='IP 地址';ExpectedValue='192.168.0.10';Value='192.168.0.20'}
 $null=Unit '09_ext_write' 'SetParameter' @{UnitIndex=2;ExpectedModel='KV-NC16EXT*';ParameterName='输入时间常数';ExpectedValue='10ms(＊)';Value='1ms'}
 $null=Unit '10_stale_rejected' 'SetParameter' @{UnitIndex=1;ExpectedModel='KV-NC1EP';ParameterName='IP 地址';ExpectedValue='192.168.0.10';Value='192.168.0.30'} -Reject
 $null=Unit '11_modified_snapshot' 'Query'
 $null=Unit '12_close_editor' 'Cancel'
 $null=Program '13_reopen_modified' 'Reopen'
 $null=Unit '14_saved_modified' 'Query' @{ExpectedSnapshotPath=(SnapshotPath '11_modified_snapshot')}
 EqualSnapshot 'every changed value survives process restart' (SnapshotPath '14_saved_modified') (SnapshotPath '11_modified_snapshot')
 $null=Unit '15_restore_serial' 'SetParameter' @{UnitIndex=0;ExpectedModel='KV-NC32';ParameterName='波特率';ExpectedValue='19200bps';Value='9600bps'}
 $null=Unit '16_restore_ep' 'SetParameter' @{UnitIndex=1;ExpectedModel='KV-NC1EP';ParameterName='IP 地址';ExpectedValue='192.168.0.20';Value='192.168.0.10'}
 $null=Unit '17_restore_ext' 'SetParameter' @{UnitIndex=2;ExpectedModel='KV-NC16EXT*';ParameterName='输入时间常数';ExpectedValue='1ms';Value='10ms(＊)'}
 $null=Unit '17a_restore_serial_mode' 'SetParameter' @{UnitIndex=0;ExpectedModel='KV-NC32';ParameterName='动作模式';ExpectedValue='KV 模式（上位链路）';Value='KV STUDIO 模式(＊)';ExpectedAfterRowsPath=$restoreModePath}
 $null=Unit '18_restored_snapshot' 'Query' @{ExpectedSnapshotPath=(SnapshotPath '06_modules_baseline')}
 $null=Unit '19_delete_ext' 'Delete' @{UnitIndex=2;ExpectedModel='KV-NC16EXT*'}
 $null=Unit '20_delete_ep' 'Delete' @{UnitIndex=1;ExpectedModel='KV-NC1EP'}
 $null=Unit '21_cpu_only_again' 'Query' @{ExpectedSnapshotPath=(SnapshotPath '03_cpu_baseline')}
 $null=Unit '22_close_editor' 'Cancel'
 $null=Program '23_reopen_deleted' 'Reopen'
 $null=Unit '24_saved_deletions' 'Query' @{ExpectedSnapshotPath=(SnapshotPath '03_cpu_baseline')}
 $null=Unit '25_readd_ep' 'Add' @{UnitIndex=1;ExpectedModel='KV-NC1EP'}
 $null=Unit '26_readd_ext' 'Add' @{UnitIndex=2;ExpectedModel='KV-NC16EXT*'}
 $null=Unit '27_readded_baseline' 'Query' @{ExpectedSnapshotPath=(SnapshotPath '06_modules_baseline')}
 $null=Unit '28_close_editor' 'Cancel'
 $null=Program '29_reopen_final' 'Reopen'
 $null=Unit '30_final_readback' 'Query' @{ExpectedSnapshotPath=(SnapshotPath '06_modules_baseline')}
 $null=Unit '31_close_editor' 'Cancel'
 $null=Program '32_close_project' 'Close'
 Check 'comment banks unchanged' (@($comments|Where-Object {(Get-FileHash $_.path).Hash -ne $_.sha256}).Count -eq 0)
}catch{$errorText=$_.Exception.Message}
finally{
 Track
 foreach($item in $owned){
  $p=Get-Process -Id $item.id -ErrorAction SilentlyContinue
  if($p -and $p.StartTime.ToUniversalTime().ToString('o') -eq $item.start){Stop-Process -Id $p.Id -Force;$null=$p.WaitForExit(5000);$cleanup+= $item}
 }
 $leaks=@($owned|Where-Object {$p=Get-Process -Id $_.id -ErrorAction SilentlyContinue;$p -and $p.StartTime.ToUniversalTime().ToString('o') -eq $_.start})
 $missing=@($before|Where-Object {$p=Get-Process -Id $_.id -ErrorAction SilentlyContinue;-not $p -or $p.StartTime.ToUniversalTime().ToString('o') -ne $_.start})
 $cases.Add(@{name='no owned process leaks';ok=($leaks.Count -eq 0)})
 $cases.Add(@{name='preexisting processes preserved';ok=($missing.Count -eq 0)})
 $failed=@($cases|Where-Object {-not $_.ok}).Count
 $ok=(-not $errorText -and $failed -eq 0)
 @{ok=$ok;passed=@($cases|Where-Object {$_.ok}).Count;failed=$failed;error=$errorText;project_path=$projectPath;cases=@($cases);owned=@($owned);cleanup=$cleanup;preserved=$before;scope='Offline unit main-parameter tables and built-in Port0; nested setting dialogs are not covered.'}|ConvertTo-Json -Depth 12|Set-Content (Join-Path $OutRoot 'test_result.json') -Encoding UTF8
}
if(-not $ok){throw "KV_NANO_UNITS_TEST_FAILED:$errorText"}
