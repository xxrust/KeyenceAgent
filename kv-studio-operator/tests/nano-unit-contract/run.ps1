param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force $OutDir|Out-Null
$OutDir=[IO.Path]::GetFullPath($OutDir)
$workflow=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../scripts/workflows/manage_kv_nano_units.ps1'))
New-Item -ItemType Directory -Force (Join-Path $OutDir 'project')|Out-Null
$project=Join-Path $OutDir 'project/fixture.kpr'
'offline fixture only'|Set-Content $project -Encoding ASCII
$valid=Join-Path $OutDir 'valid_rows.json'
'[["","动作模式","KV 模式（上位链路）"],["","波特率","9600bps"]]'|Set-Content $valid -Encoding UTF8
$invalid=Join-Path $OutDir 'invalid_rows.json'
'{"value":[["","动作模式","KV 模式（上位链路）"]]}'|Set-Content $invalid -Encoding UTF8
$cases=[Collections.Generic.List[object]]::new()
function Run([string]$Name,[hashtable]$Parameters,[string]$ErrorCode=''){
 $dest=Join-Path $OutDir $Name
 $args=@{ProjectPath=$project;OutDir=$dest}
 foreach($key in $Parameters.Keys){$args[$key]=$Parameters[$key]}
 $saved=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{$log=& powershell -NoProfile -ExecutionPolicy Bypass -File $workflow @args -PlanOnly 2>&1;$exit=$LASTEXITCODE}finally{$ErrorActionPreference=$saved}
 $log|Out-String|Set-Content (Join-Path $OutDir ($Name+'.log')) -Encoding UTF8
 $ok=if($ErrorCode){$exit -ne 0 -and ($log|Out-String).Contains($ErrorCode)}else{$exit -eq 0}
 $cases.Add(@{name=$Name;ok=$ok})
 if(-not $ok){throw "KV_NANO_UNIT_CONTRACT_CASE_FAILED:$Name"}
 return $dest
}
$before=@(Get-Process Kvs -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Id)
$errorText=''
try{
 $null=Run 'cpu_delete_rejected' @{Action='Delete';UnitIndex=0;ExpectedModel='KV-NC32'} 'KV_NANO_UNIT_CPU_DELETE_FORBIDDEN'
 $null=Run 'unverified_model_rejected' @{Action='Add';UnitIndex=1;ExpectedModel='KV-X520'} 'KV_NANO_UNIT_ADD_MODEL_OR_INDEX_NOT_VERIFIED'
 $null=Run 'unverified_slot_rejected' @{Action='Add';UnitIndex=7;ExpectedModel='KV-NC1EP'} 'KV_NANO_UNIT_ADD_MODEL_OR_INDEX_NOT_VERIFIED'
 $null=Run 'old_value_required' @{Action='SetParameter';UnitIndex=1;ExpectedModel='KV-NC1EP';ParameterName='IP 地址';Value='192.168.0.20'} 'KV_NANO_UNIT_PARAMETER_CONTRACT_REQUIRED'
 $mode=@{Action='SetParameter';UnitIndex=0;ExpectedModel='KV-NC32';ParameterName='动作模式';ExpectedValue='KV STUDIO 模式(＊)';Value='KV 模式（上位链路）'}
 $null=Run 'mode_full_target_required' $mode 'KV_NANO_UNIT_MODE_TARGET_ROWS_REQUIRED'
 $mode.ExpectedAfterRowsPath=$invalid
 $null=Run 'wrapped_row_object_rejected' $mode 'KV_NANO_UNIT_TARGET_ROW_SHAPE_INVALID'
 $mode.ExpectedAfterRowsPath=$valid
 $dest=Run 'valid_mode_frozen_plan' $mode
 $plan=Get-Content (Join-Path $dest 'execution_plan.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $preflight=Get-Content (Join-Path $dest 'plan_preflight_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $cases.Add(@{name='write saves and reads back';ok=(($plan.steps.name -join '|') -ceq 'assert_ui_guard_usage|assert_agent_boundary|nano_units|commit_units|read_saved_units')})
 $cases.Add(@{name='target input fingerprinted';ok=(@($preflight.inputs|Where-Object {$_.path -eq $valid -and $_.sha256 -eq (Get-FileHash $valid).Hash}).Count -eq 1)})
 $after=@(Get-Process Kvs -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Id)
 $cases.Add(@{name='no desktop process launched';ok=(($before|Sort-Object)-join '|') -ceq (($after|Sort-Object)-join '|')})
}catch{$errorText=$_.Exception.Message}
$failed=@($cases|Where-Object {-not $_.ok}).Count
$ok=(-not $errorText -and $failed -eq 0)
@{ok=$ok;passed=@($cases|Where-Object {$_.ok}).Count;failed=$failed;error=$errorText;cases=@($cases)}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $OutDir 'test_result.json') -Encoding UTF8
if(-not $ok){throw "KV_NANO_UNIT_CONTRACT_TEST_FAILED:$errorText"}
