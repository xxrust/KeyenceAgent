param([string]$WorkRoot='')
$ErrorActionPreference='Stop'
if(-not $WorkRoot){$WorkRoot=Join-Path $env:TEMP ('nano-cpu-position-'+[guid]::NewGuid().ToString('N'))}
New-Item -ItemType Directory -Force -Path $WorkRoot|Out-Null
. (Join-Path $PSScriptRoot '../../scripts/workflow_tools/kv_nano_cpu_position_contract.ps1')
$cases=[Collections.Generic.List[object]]::new()
function Check($Name,[scriptblock]$Body){try{& $Body;$cases.Add(@{name=$Name;ok=$true})}catch{$cases.Add(@{name=$Name;ok=$false;error=$_.Exception.Message})}}
function Reject([scriptblock]$Body,$Code){try{$null=& $Body;throw 'NOT_REJECTED'}catch{if($_.Exception.Message -notlike ($Code+'*')){throw}}}
function File($Name,$Text){$p=Join-Path $WorkRoot $Name;[IO.File]::WriteAllText($p,$Text,[Text.UTF8Encoding]::new($false));return $p}
$jog="500`t500`t500`n10`t10`t10`n10`t10`t10`n5000`t5000`t5000"
$old=File 'jog_before.tsv' $jog
Check 'complete three-axis JOG table accepts four planned changes on axis one' {
  $source=File 'jog_after.tsv' "600`t500`t500`n12`t10`t10`n15`t10`t10`n6000`t5000`t5000"
  $r=Get-KvCpuPositionWrite 'JOG设定' $old $source
  if($r.changes.Count -ne 4 -or @($r.changes|Where-Object {$_.axis -ne 1}).Count){throw 'CHANGE_SET_MISMATCH'}
}
Check 'JOG start zero rejected' {Reject {Get-KvCpuPositionWrite 'JOG设定' $old (File 'zero.tsv' $jog.Replace("500`t500`t500","0`t500`t500"))} 'KV_CPU_POSITION_JOG_RANGE_INVALID'}
Check 'JOG high over hardware frequency limit rejected' {Reject {Get-KvCpuPositionWrite 'JOG设定' $old (File 'fast.tsv' $jog.Replace('5000','100001'))} 'KV_CPU_POSITION_JOG_RANGE_INVALID'}
Check 'JOG start must be below high speed' {Reject {Get-KvCpuPositionWrite 'JOG设定' $old (File 'order.tsv' $jog.Replace("500`t500`t500","6000`t500`t500"))} 'KV_CPU_POSITION_JOG_START_MUST_BE_BELOW_HIGH'}
Check 'JOG acceleration zero remains a valid explicit immediate ramp setting' {$r=Get-KvCpuPositionWrite 'JOG设定' $old (File 'instant.tsv' $jog.Replace("10`t10`t10","0`t10`t10"));if($r.changes.Count -ne 2){throw 'ZERO_RAMP_NOT_ACCEPTED'}}
Check 'hidden axis or truncated table rejected' {Reject {Get-KvCpuPositionWrite 'JOG设定' $old (File 'short.tsv' "600`t500`n12`t10`n15`t10`n6000`t5000")} 'KV_CPU_POSITION_THREE_AXIS_COPY_REQUIRED'}
$io="R000`tR002`tR004`n常开(A 接点)`t常开(A 接点)`t常开(A 接点)`nR001`tR003`tR005`n常开(A 接点)`t常开(A 接点)`t常开(A 接点)`nR007`tR008`tR009`n常开(A 接点)`t常开(A 接点)`t常开(A 接点)`nCR8012`tCR8112`tCR8212`n常开(A 接点)`t常开(A 接点)`t常开(A 接点)`nCR8013`tCR8113`tCR8213`n常开(A 接点)`t常开(A 接点)`t常开(A 接点)`n单脉冲模式`t单脉冲模式`t单脉冲模式`n正转脉冲`t正转脉冲`t正转脉冲"
$oldIo=File 'io_before.tsv' $io
Check 'I/O dual-pulse planned enumeration accepted' {$r=Get-KvCpuPositionWrite 'I/O 设定' $oldIo (File 'io_after.tsv' $io.Replace('单脉冲模式','双脉冲模式'));if($r.changes.Count -ne 3){throw 'IO_CHANGE_SET_MISMATCH'}}
Check 'fixed Z input cannot be reassigned' {Reject {Get-KvCpuPositionWrite 'I/O 设定' $oldIo (File 'z.tsv' $io.Replace('R007','R006'))} 'KV_CPU_POSITION_FIXED_INPUT_WRITE_FORBIDDEN'}
Check 'fixed control relay cannot be reassigned' {Reject {Get-KvCpuPositionWrite 'I/O 设定' $oldIo (File 'limit.tsv' $io.Replace('CR8012','R010'))} 'KV_CPU_POSITION_FIXED_INPUT_WRITE_FORBIDDEN'}
Check 'unrecognised output enumeration rejected' {Reject {Get-KvCpuPositionWrite 'I/O 设定' $oldIo (File 'unknown.tsv' $io.Replace('单脉冲模式','EtherCAT'))} 'KV_CPU_POSITION_IO_VALUE_INVALID'}
Check 'unverified page write rejected' {Reject {Get-KvCpuPositionWrite '原点复归设定' $old $old} 'KV_CPU_POSITION_WRITE_PAGE_NOT_VERIFIED'}
Check 'unchanged input is not accepted as proof of a write' {Reject {Get-KvCpuPositionWrite 'JOG设定' $old $old} 'KV_CPU_POSITION_NO_CHANGE'}
$failed=@($cases|Where-Object {-not $_.ok})
@{ok=($failed.Count -eq 0);passed=$cases.Count-$failed.Count;failed=$failed.Count;desktop_input=$false;cases=$cases.ToArray()}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
Get-Content (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
if($failed.Count){exit 41}
