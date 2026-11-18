# File-only validation shared by planning and the guarded Nano editor.
function Assert-KvUserDeviceWrite([string]$Device) {
  # CR/CM carry CPU system functions and system comments. User policy protects
  # the entire areas, including aliases with suffixes or member notation.
  if($Device -match '(?i)\b(?:CR|CM)\s*\d') { throw ('KV_SYSTEM_DEVICE_WRITE_FORBIDDEN: '+$Device) }
}

function Assert-KvCommentFileSystemProtection([string]$Path) {
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'KV_COMMENTS_IMPORT_FILE_MISSING'}
  # Match the existing CSV importer: system ANSI unless a BOM identifies Unicode.
  $reader=[IO.StreamReader]::new([IO.Path]::GetFullPath($Path),[Text.Encoding]::Default,$true)
  try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
  foreach($line in ($text -split '\r?\n')){
    if(-not $line.Trim()){continue}
    $device=($line -split ',',2)[0].Trim().Trim('"')
    Assert-KvUserDeviceWrite $device
  }
}

function ConvertTo-KvNanoLabelText([AllowEmptyString()][string]$Text) {
  $rows=@(foreach($line in ($Text -split '\r?\n')){
    if(-not $line.Trim()){continue}
    if($line.Split([char]9).Count -ne 4){throw 'KV_NANO_LABEL_FOUR_COLUMNS_REQUIRED'}
    $line
  })
  return ($rows -join "`n")
}

function Read-KvNanoLabelText([string]$Path) {
  if(-not $Path -or -not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'KV_NANO_LABEL_TABLE_REQUIRED'}
  return (ConvertTo-KvNanoLabelText ([IO.File]::ReadAllText([IO.Path]::GetFullPath($Path),[Text.UTF8Encoding]::new($false,$true))))
}

function Assert-KvNanoLabelRows([AllowEmptyString()][string]$Text,[switch]$Writing) {
  $seen=@{}
  foreach($line in ($Text -split "`n"|Where-Object {$_})){
    $fields=$line.Split([char]9);$name=$fields[0]
    if($fields.Count -ne 4){throw 'KV_NANO_LABEL_FOUR_COLUMNS_REQUIRED'}
    $width=0;foreach($character in $name.ToCharArray()){$width+=$(if([int]$character -gt 127){2}else{1})}
    if($name -notmatch '^[A-Za-z_\u4E00-\u9FFF][A-Za-z0-9_\u4E00-\u9FFF]*$' -or $width -gt 32){throw 'KV_NANO_LABEL_NAME_REQUIRED'}
    if($seen.ContainsKey($name)){throw ('KV_NANO_LABEL_NAME_DUPLICATE: '+$name)}
    $seen[$name]=$true
    if($Writing){
      Assert-KvUserDeviceWrite $fields[2]
      if($fields[3].Trim() -and $fields[3].Trim() -ieq $name.Trim()){throw ('KV_NANO_LABEL_REDUNDANT_COMMENT: '+$name)}
    }
  }
}

function Get-KvNanoLabelWrite([string]$SourcePath,[string]$ExpectedSourcePath,[int]$Row=1) {
  $source=Read-KvNanoLabelText $SourcePath
  $before=Read-KvNanoLabelText $ExpectedSourcePath
  if(-not $source){throw 'KV_NANO_EMPTY_SOURCE_REJECTED'}
  Assert-KvNanoLabelRows $source -Writing
  $old=@($before -split "`n"|Where-Object {$_})
  $incoming=@($source -split "`n")
  if($Row -lt 1 -or $Row -gt $old.Count+1){throw 'KV_NANO_LABEL_ROW_OUT_OF_RANGE'}
  $after=[Collections.Generic.List[string]]::new()
  $resetTable=$false
  foreach($line in $old){$after.Add($line)}
  for($i=0;$i -lt $incoming.Count;$i++){
    $index=$Row-1+$i
    if($index -lt $after.Count){
      Assert-KvUserDeviceWrite ($after[$index].Split([char]9))[2]
      $oldFields=$after[$index].Split([char]9);$newFields=$incoming[$i].Split([char]9)
      for($column=0;$column -lt 4;$column++){if(-not $newFields[$column] -and $oldFields[$column]){$resetTable=$true}}
      $after[$index]=$incoming[$i]
    }else{$after.Add($incoming[$i])}
  }
  $text=$after -join "`n"
  Assert-KvNanoLabelRows $text
  if($resetTable){foreach($line in $old){Assert-KvUserDeviceWrite ($line.Split([char]9))[2]}}
  return [pscustomobject]@{source=$source;before=$before;after=$text;row_count=$incoming.Count;table_count=$after.Count;reset_table=$resetTable}
}
