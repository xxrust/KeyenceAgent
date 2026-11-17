# Non-UI MNM decoding and header parsing shared by export and body verification.
function Read-KvMnmFile {
  param([Parameter(Mandatory=$true)][string]$Path,[ValidateSet('System','Utf8')][string]$NoBomEncoding='System')
  $bytes=[IO.File]::ReadAllBytes($Path)
  if($bytes.Length -lt 4){throw 'KV_MNM_FILE_EMPTY'}
  $encoding='';$offset=0;$decoder=$null
  if($bytes[0] -eq 255 -and $bytes[1] -eq 254){
    if($bytes[2] -eq 0 -and $bytes[3] -eq 0){throw 'KV_MNM_UTF32_UNSUPPORTED'}
    $encoding='utf-16le';$offset=2;$decoder=[Text.UnicodeEncoding]::new($false,$false,$true)
  } elseif($bytes[0] -eq 254 -and $bytes[1] -eq 255){
    $encoding='utf-16be';$offset=2;$decoder=[Text.UnicodeEncoding]::new($true,$false,$true)
  } else {
    if($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191){$offset=3}
    if($offset -or $NoBomEncoding -eq 'Utf8'){
      $decoder=[Text.UTF8Encoding]::new($false,$true);$encoding='utf-8'
    } else {
      # Legacy KVS exports use the Windows ANSI code page. Byte sequences can
      # be valid in both ACP and UTF-8; guessing UTF-8 can silently rename labels.
      # UTF-8 sources should carry a BOM or explicitly request Utf8 decoding.
      $cp=[Text.Encoding]::Default.CodePage
      $decoder=[Text.Encoding]::GetEncoding($cp,[Text.EncoderFallback]::ExceptionFallback,[Text.DecoderFallback]::ExceptionFallback)
      $encoding='windows-'+$cp
    }
  }
  $text=$decoder.GetString($bytes,$offset,$bytes.Length-$offset)
  $lines=@($text -split '\r?\n')
  $devices=@($lines|Where-Object{$_ -match '^DEVICE:'})
  $modules=@($lines|Where-Object{$_ -match '^;MODULE:'})
  $types=@($lines|Where-Object{$_ -match '^;MODULE_TYPE:'})
  $scripts=@($lines|Where-Object{$_ -match '^;SCRIPT_TYPE:'})
  if($devices.Count -ne 1 -or $devices[0] -notmatch '^DEVICE:\d+$' -or $modules.Count -ne 1 -or $types.Count -ne 1 -or $types[0] -notmatch '^;MODULE_TYPE:\d+$' -or $scripts.Count -gt 1){throw 'KV_MNM_HEADER_INVALID'}
  if($lines[0] -cne $devices[0] -or $lines[1] -cne $modules[0] -or $lines[2] -cne $types[0] -or -not $modules[0].Substring(8).Trim() -or ($scripts.Count -and $lines[3] -cne $scripts[0])){throw 'KV_MNM_HEADER_ORDER_INVALID'}
  $body=@($lines|Where-Object{$_ -notmatch '^(DEVICE:|;MODULE:|;MODULE_TYPE:|;SCRIPT_TYPE:)' -and $_.Length})
  [pscustomobject]@{path=[IO.Path]::GetFullPath($Path);encoding=$encoding;text=$text;device_code=[int]$devices[0].Substring(7);module_name=$modules[0].Substring(8);module_type=[int]$types[0].Substring(13);script_type=if($scripts.Count){$scripts[0].Substring(13)}else{$null};body_lines=$body;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
}
