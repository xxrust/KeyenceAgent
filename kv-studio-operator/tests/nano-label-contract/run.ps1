param([string]$WorkRoot='')
$ErrorActionPreference='Stop'
if(-not $WorkRoot){$WorkRoot=Join-Path $env:TEMP ('nano-label-contract-'+[guid]::NewGuid().ToString('N'))}
New-Item -ItemType Directory -Force -Path $WorkRoot|Out-Null
. (Join-Path $PSScriptRoot '../../scripts/workflow_tools/kv_nano_label_contract.ps1')
$cases=[Collections.Generic.List[object]]::new()
function Check($Name,[scriptblock]$Body){try{& $Body;$cases.Add(@{name=$Name;ok=$true})}catch{$cases.Add(@{name=$Name;ok=$false;error=$_.Exception.Message})}}
function Reject([scriptblock]$Body,$Code){try{& $Body;throw 'NOT_REJECTED'}catch{if($_.Exception.Message -notlike ($Code+'*')){throw}}}
function File($Name,$Text){$p=Join-Path $WorkRoot $Name;[IO.File]::WriteAllText($p,$Text,[Text.UTF8Encoding]::new($false));return $p}
$empty=File 'empty.tsv' ''
Check 'multirow append computes complete result preserving existing row' {
  $old=File 'old.tsv' "Keep`t位`tMR000`t"
  $src=File 'append.tsv' "North`t位`tMR001`t`nSouth`t位`tMR002`t"
  $r=Get-KvNanoLabelWrite $src $old 2
  if($r.row_count -ne 2 -or $r.table_count -ne 3 -or $r.after -notlike 'Keep*'){throw 'BAD_BATCH_RESULT'}
}
Check 'blank fourth columns survive normalisation and overwrite clears old comments' {
  $old=File 'comments.tsv' "North`t位`tMR001`told detail`nSouth`t位`tMR002`tdetail"
  $src=File 'blank_comments.tsv' "North`t位`tMR001`t`nSouth`t位`tMR002`t"
  $r=Get-KvNanoLabelWrite $src $old
  if($r.after -cne (Read-KvNanoLabelText $src) -or -not $r.reset_table){throw 'EMPTY_COLUMNS_LOST'}
}
Check 'system relay label rejected before desktop' {Reject {Get-KvNanoLabelWrite (File 'cr.tsv' "System`t位`tCR2002`t") $empty} 'KV_SYSTEM_DEVICE_WRITE_FORBIDDEN'}
Check 'system memory label rejected before desktop' {Reject {Get-KvNanoLabelWrite (File 'cm.tsv' "System`t1 字无符号整数`tCM0`t") $empty} 'KV_SYSTEM_DEVICE_WRITE_FORBIDDEN'}
Check 'protected row cannot be overwritten by a business alias' {Reject {Get-KvNanoLabelWrite (File 'business.tsv' "Business`t位`tMR001`t") (File 'protected.tsv' "System`t位`tCR2002`t")} 'KV_SYSTEM_DEVICE_WRITE_FORBIDDEN'}
Check 'system comment protection covers case and bit suffix' {Reject {Assert-KvUserDeviceWrite 'cr2006.0'} 'KV_SYSTEM_DEVICE_WRITE_FORBIDDEN';Reject {Assert-KvUserDeviceWrite 'CM0.U'} 'KV_SYSTEM_DEVICE_WRITE_FORBIDDEN'}
Check 'comment CSV cannot write or clear system comments' {
  Reject {Assert-KvCommentFileSystemProtection (File 'system_comments.csv' "CR2002,,changed,,,,,,,,`nMR001,,detail,,,,,,,,")} 'KV_SYSTEM_DEVICE_WRITE_FORBIDDEN'
  Reject {Assert-KvCommentFileSystemProtection (File 'clear_system.csv' "CM0,,,,,,,,,,`nMR001,,detail,,,,,,,,")} 'KV_SYSTEM_DEVICE_WRITE_FORBIDDEN'
  Assert-KvCommentFileSystemProtection (File 'user_comments.csv' "MR001,,detail,,,,,,,,`nR500,,output,,,,,,,,")
}
Check 'duplicate label names across unchanged rows rejected' {Reject {Get-KvNanoLabelWrite (File 'duplicate.tsv' "keep`t位`tMR001`t") (File 'keep.tsv' "Keep`t位`tMR000`t") 2} 'KV_NANO_LABEL_NAME_DUPLICATE'}
Check 'comment that repeats the label is rejected' {Reject {Get-KvNanoLabelWrite (File 'redundant.tsv' "North`t位`tMR001`tNorth") $empty} 'KV_NANO_LABEL_REDUNDANT_COMMENT'}
Check 'Chinese names accept 16 fullwidth characters and reject 17' {
  $good=File 'chinese.tsv' ((('灯'*16)-join '')+"`t位`tMR001`t")
  $null=Get-KvNanoLabelWrite $good $empty
  Reject {Get-KvNanoLabelWrite (File 'long.tsv' ((('灯'*17)-join '')+"`t位`tMR001`t")) $empty} 'KV_NANO_LABEL_NAME_REQUIRED'
}
$workflows=Join-Path $PSScriptRoot '../../scripts/workflows'
foreach($device in @('CR2002','CM0')){
  Check ("public label workflow rejects $device before planning or desktop") {
    $out=Join-Path $WorkRoot ('reject_label_'+$device)
    $source=File ('public_'+$device+'.tsv') ("System`t位`t"+$device+"`t")
    Reject {& (Join-Path $workflows 'manage_kv_nano_program.ps1') -ProjectPath (Join-Path $WorkRoot 'missing.kpr') -OutDir $out -Action WriteLabels -SourcePath $source -ExpectedSourcePath $empty -PlanOnly} 'KV_SYSTEM_DEVICE_WRITE_FORBIDDEN'
    if(Test-Path $out){throw 'REJECTED_INPUT_CREATED_PLAN'}
  }
  Check ("public comment workflow rejects clearing $device before planning or desktop") {
    $out=Join-Path $WorkRoot ('reject_comment_'+$device)
    $source=File ('public_'+$device+'.csv') ($device+',,,,,,,,,,')
    Reject {& (Join-Path $workflows 'import_kv_device_comments.ps1') -ProjectPath (Join-Path $WorkRoot 'missing.kpr') -OutDir $out -CommentsPath $source -PlanOnly} 'KV_SYSTEM_DEVICE_WRITE_FORBIDDEN'
    if(Test-Path $out){throw 'REJECTED_INPUT_CREATED_PLAN'}
  }
}
$failed=@($cases|Where-Object {-not $_.ok})
@{ok=($failed.Count -eq 0);passed=$cases.Count-$failed.Count;failed=$failed.Count;cases=$cases.ToArray()}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
Get-Content (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
if($failed.Count){exit 41}
