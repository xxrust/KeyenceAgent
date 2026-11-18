# Offline parameter table validation; no desktop input.
function ConvertTo-KvCpuPositionTable([string]$Text){return $Text.Replace("`r`n","`n").TrimEnd("`r","`n")}
function Get-KvCpuPositionWrite([string]$PageName,[string]$ExpectedTablePath,[string]$SourcePath){
  foreach($path in @($ExpectedTablePath,$SourcePath)){if(-not $path -or -not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'KV_CPU_POSITION_TABLE_FILE_REQUIRED'}}
  $before=ConvertTo-KvCpuPositionTable ([IO.File]::ReadAllText($ExpectedTablePath,[Text.UTF8Encoding]::new($false,$true)))
  $after=ConvertTo-KvCpuPositionTable ([IO.File]::ReadAllText($SourcePath,[Text.UTF8Encoding]::new($false,$true)))
  $old=@($before -split "`n");$new=@($after -split "`n")
  $count=switch($PageName){'I/O 设定'{12};'JOG设定'{4};default{throw 'KV_CPU_POSITION_WRITE_PAGE_NOT_VERIFIED'}}
  if($old.Count -ne $count -or $new.Count -ne $count){throw 'KV_CPU_POSITION_WRITE_ROW_COUNT_MISMATCH'}
  $changes=[Collections.Generic.List[object]]::new()
  for($row=0;$row -lt $count;$row++){
    $a=$old[$row].Split([char]9);$b=$new[$row].Split([char]9)
    if($a.Count -ne 3 -or $b.Count -ne 3){throw 'KV_CPU_POSITION_THREE_AXIS_COPY_REQUIRED'}
    for($axis=0;$axis -lt 3;$axis++){
      if($a[$axis] -ceq $b[$axis]){continue}
      if($PageName -eq 'I/O 设定'){
        $allowed=switch($row){
          0 {if($axis -eq 2){@('CR8214','R004','R005')}else{@(('CR'+(80+$axis)+'14'),'R000','R001','R002','R003')}}
          2 {if($axis -eq 2){@('CR8215','R004','R005')}else{@(('CR'+(80+$axis)+'15'),'R000','R001','R002','R003')}}
          {$_ -in @(1,3,5,7,9)} {@('常开(A 接点)','常闭(B 接点)')}
          10 {@('单脉冲模式','双脉冲模式')}
          11 {@('正转脉冲','反转脉冲')}
          default {throw 'KV_CPU_POSITION_FIXED_INPUT_WRITE_FORBIDDEN'}
        }
        if($b[$axis] -cnotin $allowed){throw 'KV_CPU_POSITION_IO_VALUE_INVALID'}
      }else{
        $max=if($row -eq 3){100000}else{65535};$min=if($row -in @(0,3)){1}else{0}
        if($b[$axis] -notmatch '^\d+$' -or [long]$b[$axis] -lt $min -or [long]$b[$axis] -gt $max){throw 'KV_CPU_POSITION_JOG_RANGE_INVALID'}
      }
      $changes.Add(@{row=$row;axis=($axis+1);before=$a[$axis];after=$b[$axis]})
    }
  }
  if($PageName -eq 'JOG设定'){
    for($axis=0;$axis -lt 3;$axis++){
      if([long]($new[0].Split([char]9))[$axis] -ge [long]($new[3].Split([char]9))[$axis]){throw 'KV_CPU_POSITION_JOG_START_MUST_BE_BELOW_HIGH'}
    }
  }
  if(-not $changes.Count){throw 'KV_CPU_POSITION_NO_CHANGE'}
  return [pscustomobject]@{before=$before;after=$after;changes=$changes.ToArray()}
}
