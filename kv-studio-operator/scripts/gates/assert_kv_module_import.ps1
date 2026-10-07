param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$MnmPath,
  [Parameter(Mandatory=$true)][string]$ModuleName,
  [ValidateSet('scan','function_block')][string]$Category='scan',
  [string[]]$ParentPath=@(),
  [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'workflow_tools/kv_complete_module_contract.ps1')
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
try {
  if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw 'KV_MODULE_PROJECT_MISSING' }
  if (-not (Test-Path -LiteralPath $MnmPath -PathType Leaf)) { throw 'KV_MODULE_SOURCE_MISSING' }
  if ($ModuleName -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,47}$') { throw 'KV_MODULE_NAME_INVALID' }
  $bytes=[IO.File]::ReadAllBytes($MnmPath)
  if ($bytes.Length -eq 0 -or ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) -or ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255)) { throw 'KV_MODULE_MNM_ENCODING_UNSUPPORTED' }
  if ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
    $body=[Text.UnicodeEncoding]::new($false,$false,$true).GetString($bytes,2,$bytes.Length-2)
  } else { $body=[Text.Encoding]::Default.GetString($bytes) }
  $moduleType=if($Category -eq 'scan'){0}else{2}
  foreach($pair in @(@(';MODULE',$ModuleName),@(';MODULE_TYPE',[string]$moduleType))) {
    $headers=[regex]::Matches($body,('(?m)^'+[regex]::Escape($pair[0])+':([^\r\n]*)\r?$'))
    if ($headers.Count -ne 1 -or $headers[0].Groups[1].Value.Trim() -cne $pair[1]) { throw 'KV_MODULE_MNM_HEADER_MISMATCH' }
  }
  $devices=[regex]::Matches($body,'(?m)^DEVICE:([^\r\n]*)\r?$')
  $allowedDevices=if($Category -eq 'scan'){@('60','63')}else{@('60','59')}
  if ($devices.Count -ne 1 -or $devices[0].Groups[1].Value.Trim() -notin $allowedDevices) { throw 'KV_MODULE_MNM_HEADER_MISMATCH' }
  $nonempty=@($body -split '\r?\n' | Where-Object { $_.Trim() })
  if ([regex]::Matches($body,'(?m)^ENDH\s*$').Count -ne 1 -or $nonempty.Count -lt 5 -or $nonempty[-1].Trim() -cne 'ENDH' -or $nonempty[-2].Trim() -cne 'END') { throw 'KV_MODULE_MNM_TERMINATOR_MISSING' }
  $categoryName=if($Category -eq 'scan'){-join([char[]]@(0x6BCF,0x6B21,0x626B,0x63CF,0x6267,0x884C,0x578B,0x6A21,0x5757))}else{-join([char[]]@(0x529F,0x80FD,0x5757))}
  if (-not $ParentPath.Count) { $ParentPath=@($categoryName) }
  if ($ParentPath[0] -cne $categoryName) { throw 'KV_MODULE_PARENT_CATEGORY_MISMATCH' }
  $nodes=@(Get-KvModuleTreePaths $ProjectPath)
  if (@($nodes | Where-Object { Test-KvTreePathSuffix $_.path $ParentPath }).Count -ne 1) { throw 'KV_MODULE_PARENT_MISSING_OR_AMBIGUOUS' }
  if (@($nodes | Where-Object { $_.name -ieq $ModuleName }).Count) { throw 'KV_MODULE_ALREADY_EXISTS' }
  $result=@{ok=$true;ui_started=$false;project_path=[IO.Path]::GetFullPath($ProjectPath);mnm_path=[IO.Path]::GetFullPath($MnmPath);module_name=$ModuleName;category=$Category;parent_path=$ParentPath;source_sha256=(Get-FileHash -LiteralPath $MnmPath -Algorithm SHA256).Hash;verification_scope='single MNM envelope, create-only target, exact saved parent; does not prove ST syntax, declarations or compilation'}
}catch{$result=@{ok=$false;ui_started=$false;error_code=($_.Exception.Message -split ':')[0];message=$_.Exception.Message}}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutDir 'module_import_preflight_result.json') -Encoding UTF8
if (-not $result.ok) { [Console]::Error.WriteLine($result.message); exit 1 }
exit 0
