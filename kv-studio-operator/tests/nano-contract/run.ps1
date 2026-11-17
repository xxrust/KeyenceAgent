param([string]$WorkRoot='')
$ErrorActionPreference='Stop'
if(-not $WorkRoot){$WorkRoot=Join-Path $env:TEMP ('kv-nano-contract-'+[guid]::NewGuid().ToString('N'))}
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$scriptsRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../scripts'))
. (Join-Path $scriptsRoot 'workflow_tools/kv_mnm_text.ps1')
. (Join-Path $scriptsRoot 'kv_window_binding.ps1')
$cases=[Collections.Generic.List[object]]::new()
function Case([string]$Name,[scriptblock]$Check){
  try{& $Check;$cases.Add([pscustomobject]@{name=$Name;ok=$true;detail=''})}
  catch{$cases.Add([pscustomobject]@{name=$Name;ok=$false;detail=$_.Exception.Message})}
}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Code){
  $rejected=$false
  try{& $Action | Out-Null}catch{if($Code -and $_.Exception.Message -notlike ($Code+'*')){throw};$rejected=$true}
  Require $rejected 'invalid input was accepted'
}
$labelName=-join([char[]]@(0x539F,0x70B9,0x5230,0x4F4D))
$nano="DEVICE:128`r`n;MODULE:Main`r`n;MODULE_TYPE:0`r`n;SCRIPT_TYPE:`r`nLD CR2002`r`nOUT $labelName`r`nEND`r`nENDH`r`n"
Case 'legacy Chinese MNM preserves label spelling using the configured ANSI code page' {
  $p=Join-Path $WorkRoot 'legacy.mnm'
  [IO.File]::WriteAllText($p,$nano,[Text.Encoding]::Default)
  $m=Read-KvMnmFile $p
  Require ($m.module_name -ceq 'Main' -and $m.module_type -eq 0 -and $m.device_code -eq 128) 'header changed'
  Require ($m.body_lines -ccontains ('OUT '+$labelName)) 'Chinese label changed'
  Require ($m.body_lines -cnotcontains ';SCRIPT_TYPE:') 'metadata leaked into body'
}
Case 'UTF16 KV-X and UTF8 BOM produce identical Unicode bodies' {
  $a=Join-Path $WorkRoot 'utf16.mnm';$b=Join-Path $WorkRoot 'utf8.mnm'
  [IO.File]::WriteAllText($a,$nano,[Text.UnicodeEncoding]::new($false,$true,$true))
  [IO.File]::WriteAllText($b,$nano,[Text.UTF8Encoding]::new($true,$true))
  $ma=Read-KvMnmFile $a;$mb=Read-KvMnmFile $b
  Require (($ma.body_lines -join "`n") -ceq ($mb.body_lines -join "`n")) 'decoded bodies differ'
}
Case 'UTF8 without BOM requires explicit decoding when bytes are ambiguous' {
  # C2 A9 is valid UTF8 and valid in several Windows ANSI code pages.
  # A parser must not silently guess based on UTF8 validity.
  $p=Join-Path $WorkRoot 'ambiguous.mnm'
  $text=$nano.Replace($labelName,[string][char]0xA9)
  [IO.File]::WriteAllText($p,$text,[Text.UTF8Encoding]::new($false,$true))
  $explicit=Read-KvMnmFile $p -NoBomEncoding Utf8
  Require ($explicit.text -ceq $text) 'explicit UTF8 decoding changed source'
  if([Text.Encoding]::Default.CodePage -ne 65001){
    $legacy=Read-KvMnmFile $p
    Require ($legacy.encoding -eq ('windows-'+[Text.Encoding]::Default.CodePage)) 'no-BOM encoding was guessed'
  }
}
Case 'invalid UTF8 BOM cannot fall back to ANSI' {
  $p=Join-Path $WorkRoot 'invalid_utf8.mnm'
  [IO.File]::WriteAllBytes($p,[byte[]]@(239,187,191,255,255))
  Reject {Read-KvMnmFile $p} ''
}
Case 'second module header is rejected instead of merging unrelated bodies' {
  $p=Join-Path $WorkRoot 'two_modules.mnm'
  [IO.File]::WriteAllText($p,($nano+";MODULE:Other`r`nLD CR2002"),[Text.Encoding]::Default)
  Reject {Read-KvMnmFile $p} 'KV_MNM_HEADER_INVALID'
}
Case 'metadata embedded in the body is rejected' {
  $p=Join-Path $WorkRoot 'misplaced_header.mnm'
  [IO.File]::WriteAllText($p,$nano.Replace(";SCRIPT_TYPE:`r`n",'')+";SCRIPT_TYPE:`r`n",[Text.Encoding]::Default)
  Reject {Read-KvMnmFile $p} 'KV_MNM_HEADER_ORDER_INVALID'
}
Case 'complete quoted project path binds while same basename and path prefix do not' {
  $p=Join-Path $WorkRoot 'copy [2]/Main.kpr'
  $full=[IO.Path]::GetFullPath($p)
  Require (Test-KvProjectCommandLine ('Kvs.exe -r "'+$full+'"') $p) 'exact quoted argument missed'
  Require (-not(Test-KvProjectCommandLine ('Kvs.exe -r "'+$full+'.bak"') $p)) 'path prefix accepted'
  Require (-not(Test-KvProjectCommandLine 'Kvs.exe -r "C:\other\Main.kpr"' $p)) 'basename accepted'
}
Case 'unquoted path without spaces binds only as a whole argument' {
  Require (Test-KvProjectCommandLine 'Kvs.exe C:\Nano\Main.kpr -r' 'C:\Nano\Main.kpr') 'whole argument missed'
  Require (-not(Test-KvProjectCommandLine 'Kvs.exe C:\Nano\Main.kpr2' 'C:\Nano\Main.kpr')) 'argument prefix accepted'
}
$failed=@($cases|Where-Object{-not $_.ok})
$result=@{test='nano-contract';passed=$cases.Count-$failed.Count;failed=$failed.Count;cases=$cases.ToArray();work_root=$WorkRoot}
$result|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $WorkRoot 'test_result.json')
$result|ConvertTo-Json -Depth 5
if($failed.Count){exit 41}
