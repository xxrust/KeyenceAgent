param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$scripts=Join-Path $root 'scripts'
$OutDir=[IO.Path]::GetFullPath($OutDir)
$fixture=Join-Path $OutDir 'fixture'
$null=New-Item -ItemType Directory -Force -Path $fixture
$project=Join-Path $fixture 'Preflight.kpr'
[IO.File]::WriteAllText($project,'non-UI fixture')
$scan=-join([char[]]@(0x6BCF,0x6B21,0x626B,0x63CF,0x6267,0x884C,0x578B,0x6A21,0x5757))
$fb=-join([char[]]@(0x529F,0x80FD,0x5757))
$tree='<Root><Child><value.first>'+ $scan +'</value.first><value.second><Child><value.first>Existing</value.first><value.second /></Child></value.second></Child><Child><value.first>'+ $fb +'</value.first><value.second /></Child></Root>'
[IO.File]::WriteAllText((Join-Path $fixture 'WsTreeEnv.xml'),$tree,[Text.UTF8Encoding]::new($false))
$good="DEVICE:63`r`n;MODULE:STProbe`r`n;MODULE_TYPE:0`r`nAREA_ST`r`n;FitA := LREAL#1.0;`r`nEND`r`nENDH`r`n"
$cases=@(
  @{name='valid_st';body=$good;ok=$true;code=''},
  @{name='two_modules';body=$good+";MODULE:Other`r`n";ok=$false;code='KV_MODULE_MNM_HEADER_MISMATCH'},
  @{name='wrong_category_type';body=$good.Replace(';MODULE_TYPE:0',';MODULE_TYPE:2');ok=$false;code='KV_MODULE_MNM_HEADER_MISMATCH'},
  @{name='wrong_device';body=$good.Replace('DEVICE:63','DEVICE:59');ok=$false;code='KV_MODULE_MNM_HEADER_MISMATCH'},
  @{name='trailing_code';body=$good+"LD Unsafe`r`n";ok=$false;code=''},
  @{name='duplicate_terminator';body=$good+"ENDH`r`n";ok=$false;code=''},
  @{name='missing_end';body=$good.Replace("`r`nEND`r`n","`r`n");ok=$false;code=''},
  @{name='existing_module';body=$good.Replace('STProbe','Existing');module='Existing';ok=$false;code='KV_MODULE_ALREADY_EXISTS'},
  @{name='device60_ansi';body=$good.Replace('DEVICE:63','DEVICE:60');ok=$true;code=''},
  @{name='device60_utf16le';body=$good.Replace('DEVICE:63','DEVICE:60');encoding='utf16le';ok=$true;code=''},
  @{name='utf8_bom';body=$good;encoding='utf8bom';ok=$false;code='KV_MODULE_MNM_ENCODING_UNSUPPORTED'},
  @{name='utf16be';body=$good;encoding='utf16be';ok=$false;code='KV_MODULE_MNM_ENCODING_UNSUPPORTED'},
  @{name='utf32le';body=$good;encoding='utf32le';ok=$false;code=''}
)
$rows=@()
foreach($case in $cases){
  $mnm=Join-Path $fixture ($case.name+'.mnm')
  $encoding=switch($case.encoding){
    'utf8bom' {[Text.UTF8Encoding]::new($true)}
    'utf16le' {[Text.UnicodeEncoding]::new($false,$true)}
    'utf16be' {[Text.UnicodeEncoding]::new($true,$true)}
    'utf32le' {[Text.UTF32Encoding]::new($false,$true)}
    default {[Text.Encoding]::Default}
  }
  [IO.File]::WriteAllText($mnm,$case.body,$encoding)
  $dest=Join-Path $OutDir $case.name
  $module=if($case.module){$case.module}else{'STProbe'}
  $ErrorActionPreference='Continue'
  try{
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'gates/assert_kv_module_import.ps1') -ProjectPath $project -MnmPath $mnm -ModuleName $module -Category scan -OutDir $dest *> (Join-Path $OutDir ($case.name+'.txt'))
    $exitCode=$LASTEXITCODE
  }finally{$ErrorActionPreference='Stop'}
  $r=Get-Content -LiteralPath (Join-Path $dest 'module_import_preflight_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if([bool]$r.ok -ne $case.ok -or (($exitCode -eq 0) -ne $case.ok)){throw ('Unexpected gate result: '+$case.name)}
  if($case.code -and $r.error_code -cne $case.code){throw ('Unexpected error code: '+$case.name)}
  if($r.ui_started -ne $false){throw 'Preflight must not start UI'}
  if($case.ok -and (@($r.parent_path).Count -ne 1 -or $r.parent_path[0] -cne $scan)){throw 'Default parent not normalized'}
  $rows+=@{name=$case.name;ok=$true;observed_error_code=$r.error_code}
}
. (Join-Path $scripts 'kv_variable_definition_lib.ps1')
foreach($name in @('B','C','b','c','IF','T','V','Z','REAL')){if(-not (Test-KvSoftDeviceLikeVariableName $name)){throw ('Reserved name accepted: '+$name)}}
foreach($name in @('FitA','FitB','FitC','A','X','Y','IfReady','TimeValue','Velocity','Zone','RealValue')){if(Test-KvSoftDeviceLikeVariableName $name){throw ('Supported name rejected: '+$name)}}
foreach($type in @('LREAL','REAL','ARRAY[0..31] OF REAL','ARRAY[0..31] OF LREAL')){if(-not (Test-KvVariableDataType $type)){throw ('Numeric type rejected: '+$type)}}
$rows+=@{name='reserved_names_and_numeric_types';ok=$true}
foreach($case in @(@{name='public_numeric_plan';variable='FitB';ok=$true},@{name='public_reserved_b';variable='B';ok=$false},@{name='public_reserved_c';variable='C';ok=$false})){
  $tsv=Join-Path $fixture ($case.name+'.tsv')
  $payload="scope`towner_program`tname`tdata_type`tstatus`tevidence`r`nlocal`tExisting`t$($case.variable)`tLREAL`tdeclared`tregression`r`nlocal`tExisting`tSamples`tARRAY[0..31] OF LREAL`tdeclared`tregression`r`n"
  [IO.File]::WriteAllText($tsv,$payload,[Text.UTF8Encoding]::new($false))
  $dest=Join-Path $OutDir $case.name
  $log=Join-Path $OutDir ($case.name+'.txt')
  $ErrorActionPreference='Continue'
  try{
    & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'workflows/set_kv_variables.ps1') -ProjectPath $project -LocalVariablesTsv $tsv -LocalProgramName Existing -OutDir $dest -PlanOnly *> $log
    $exitCode=$LASTEXITCODE
  }finally{$ErrorActionPreference='Stop'}
  if(($exitCode -eq 0) -ne $case.ok){throw ('Unexpected public variable preflight result: '+$case.name)}
  if(-not $case.ok -and (Get-Content -LiteralPath $log -Raw) -notmatch 'KV_VARIABLE_NAME_SOFT_DEVICE_CONFLICT'){throw ('Missing reserved-name diagnosis: '+$case.name)}
  if(Test-Path -LiteralPath (Join-Path $dest 'run.log')){throw 'PlanOnly must not execute UI runner'}
  $rows+=@{name=$case.name;ok=$true;exit_code=$exitCode}
}
@{ok=$true;ui_started=$false;scope='ST MNM envelope and declaration non-UI preflight';tests=$rows}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
'Passed ST import preflight regressions'
