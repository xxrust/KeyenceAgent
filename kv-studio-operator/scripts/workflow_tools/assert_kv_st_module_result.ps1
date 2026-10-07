param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$ContractPath,[Parameter(Mandatory=$true)][string]$ArtifactsRoot,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'kv_st_module_contract.ps1')
function Assert-StTrue($Value,[string]$Code){if($Value -isnot [bool] -or -not $Value){throw $Code}}
function Assert-StPath($Actual,$Expected,[string]$Code){if(-not $Actual -or [IO.Path]::GetFullPath([string]$Actual) -ine [IO.Path]::GetFullPath([string]$Expected)){throw $Code}}
function Assert-StExportSaved($Result,[string]$ProjectPath){
  Assert-StTrue $Result.project_saved 'KV_ST_PROJECT_NOT_SAVED'
  $pattern='^KV STUDIO.* - \['+[regex]::Escape([IO.Path]::GetFileNameWithoutExtension($ProjectPath))+'\]$'
  if(-not $Result.final_title -or $Result.final_title -notmatch $pattern){throw 'KV_ST_SAVED_PROJECT_TITLE_MISMATCH'}
}
function Assert-StDeclarationBinding($Result,$Contract,[string]$ProjectPath){
  Assert-StPath $Result.ProjectPath $ProjectPath 'KV_ST_DECLARATION_PROJECT_MISMATCH'
  if($Result.LocalProgramName -cne $Contract.module_name){throw 'KV_ST_DECLARATION_OWNER_MISMATCH'}
  Assert-StPath $Result.LocalVariablesTsv $Contract.locals_path 'KV_ST_DECLARATION_SOURCE_MISMATCH'
  if($Contract.globals_path){Assert-StPath $Result.GlobalVariablesTsv $Contract.globals_path 'KV_ST_GLOBAL_DECLARATION_SOURCE_MISMATCH'}
  elseif($Result.GlobalVariablesTsv){throw 'KV_ST_GLOBAL_DECLARATION_SOURCE_MISMATCH'}
}
function Read-StOwnedText([string]$Path,[string]$Owner){
  $prefix=[IO.Path]::GetFullPath($Owner).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
  if(-not $Path -or -not [IO.Path]::GetFullPath($Path).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'KV_ST_COPYBACK_OWNERSHIP'}
  return [IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
}
function Assert-StRows([string]$Text,[object[]]$Expected,[ValidateSet('local','global','argument')][string]$Kind){
  $actual=@();$seen=@{}
  foreach($line in @($Text -split '\r?\n')){
    $cells=$line.Split([char]9)
    if(@($cells|Where-Object{-not [string]::IsNullOrWhiteSpace($_)}).Count -eq 0){continue}
    $nameIndex=if($Kind -eq 'global'){1}else{0};$typeIndex=if($Kind -eq 'argument'){3}else{$nameIndex+1}
    if($cells.Count -le $typeIndex -or $cells[$nameIndex] -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or [string]::IsNullOrWhiteSpace($cells[$typeIndex])){throw 'KV_ST_COPYBACK_ROW_SCHEMA'}
    $name=$cells[$nameIndex]
    if($seen.ContainsKey($name)){throw 'KV_ST_COPYBACK_DUPLICATE'};$seen[$name]=$true
    $actual+=@{name=$name;data_type=$cells[$typeIndex];direction=if($Kind -eq 'argument'){$cells[1]}else{''}}
  }
  if($Kind -ne 'global' -and $actual.Count -ne $Expected.Count){throw 'KV_ST_COPYBACK_COUNT'}
  foreach($row in $Expected){
    $name=if($Kind -eq 'argument'){$row.argument_name}else{$row.name}
    $match=@($actual|Where-Object{$_.name -ceq $name})
    if($match.Count -ne 1 -or $match[0].data_type -cne $row.data_type -or ($Kind -eq 'argument' -and $match[0].direction -cne $row.argument_kind)){throw "KV_ST_COPYBACK_MISMATCH: $name"}
  }
  return $actual
}
$null=New-Item -ItemType Directory -Force -Path $OutDir
try{
  $checked=Read-KvStModuleContract $ContractPath $ProjectPath -AfterCreate;$c=$checked.contract
  $preflightPath=Join-Path $ArtifactsRoot 'module_contract/st_module_preflight_result.json'
  $preflight=Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8|ConvertFrom-Json
  Assert-StTrue $preflight.ok 'KV_ST_CONTRACT_EVIDENCE_FAILED'
  foreach($inputPath in $checked.input_paths){
    $record=@($preflight.inputs|Where-Object{[IO.Path]::GetFullPath($_.path) -ieq [IO.Path]::GetFullPath($inputPath)})
    if($record.Count -ne 1 -or (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash -cne $record[0].sha256){throw 'KV_ST_INPUT_CHANGED'}
  }
  $target=@(Get-KvModuleTreePaths $ProjectPath|Where-Object{Test-KvTreePathSuffix $_.path (@($c.parent_path)+@($c.module_name))})
  if($target.Count -ne 1){throw 'KV_ST_SAVED_PARENT_MISMATCH'}
  $write=Get-Content -LiteralPath (Join-Path $ArtifactsRoot 'locals/set_variables_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
  Assert-StTrue $write.Ok 'KV_ST_DECLARATION_WRITE_FAILED';Assert-StTrue $write.AuditPersistence 'KV_ST_PERSISTENCE_REQUIRED';Assert-StDeclarationBinding $write $c $ProjectPath
  $localResult=Get-Content -LiteralPath (Join-Path $ArtifactsRoot 'locals/variable_persistence_validation.json') -Raw -Encoding UTF8|ConvertFrom-Json
  Assert-StTrue $localResult.Ok 'KV_ST_DECLARATION_READ_FAILED';Assert-StTrue $localResult.LocalReopenClipboardContainsExpectedNames 'KV_ST_LOCALS_NOT_REOPENED';Assert-StDeclarationBinding $localResult $c $ProjectPath
  $localRows=@(Assert-StRows (Read-StOwnedText $localResult.LocalReopenClipboardPath (Join-Path $ArtifactsRoot 'locals')) $checked.locals local)
  $globalRows=@()
  if($checked.globals.Count){
    Assert-StTrue $localResult.GlobalReopenClipboardContainsExpectedNames 'KV_ST_GLOBALS_NOT_REOPENED'
    $globalRows=@(Assert-StRows (Read-StOwnedText $localResult.GlobalReopenClipboardPath (Join-Path $ArtifactsRoot 'locals')) $checked.globals global)
  }
  $argumentRows=@()
  if($c.category -eq 'function_block'){
    $argWrite=Get-Content -LiteralPath (Join-Path $ArtifactsRoot 'arguments/set_fb_arguments_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-StTrue $argWrite.ok 'KV_ST_ARGUMENT_WRITE_FAILED';Assert-StPath $argWrite.project_path $ProjectPath 'KV_ST_ARGUMENT_PROJECT_MISMATCH';Assert-StPath $argWrite.arguments_tsv $c.arguments_path 'KV_ST_ARGUMENT_SOURCE_MISMATCH'
    if($argWrite.fb_module_name -cne $c.module_name){throw 'KV_ST_ARGUMENT_OWNER_MISMATCH'}
    $snapshotPath=Join-Path $ArtifactsRoot 'arguments_readback/fb_snapshot_result.json'
    $snapshot=Get-Content -LiteralPath $snapshotPath -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($flag in @('ok','read_only','focus_verified','clipboard_fresh','all_columns_preserved')){Assert-StTrue $snapshot.$flag ('KV_ST_ARGUMENT_SNAPSHOT_'+$flag)}
    Assert-StPath $snapshot.project_path $ProjectPath 'KV_ST_ARGUMENT_PROJECT_MISMATCH'
    if($snapshot.module_name -cne $c.module_name -or ($snapshot.row_count -isnot [int] -and $snapshot.row_count -isnot [long]) -or $snapshot.row_count -ne $checked.arguments.Count){throw 'KV_ST_ARGUMENT_SNAPSHOT_SCHEMA'}
    $raw=Read-StOwnedText $snapshot.raw_path (Join-Path $ArtifactsRoot 'arguments_readback')
    $completed=(Get-Item -LiteralPath (Join-Path $ArtifactsRoot 'locals/set_variables_result.json')).LastWriteTimeUtc
    if((Get-Item -LiteralPath $snapshotPath).LastWriteTimeUtc -lt $completed -or (Get-Item -LiteralPath $snapshot.raw_path).LastWriteTimeUtc -lt $completed){throw 'KV_ST_ARGUMENT_SNAPSHOT_STALE'}
    $argumentRows=@(Assert-StRows $raw $checked.arguments argument)
  }
  $exportResult=Get-Content -LiteralPath (Join-Path $ArtifactsRoot 'export/browse_folder_export_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
  Assert-StTrue $exportResult.ok 'KV_ST_EXPORT_FAILED';Assert-StPath $exportResult.project_path $ProjectPath 'KV_ST_EXPORT_PROJECT_MISMATCH'
  Assert-StExportSaved $exportResult $ProjectPath
  $exported=Join-Path (Split-Path -Parent $ProjectPath) ($c.module_name+'.mnm')
  $matches=@($exportResult.mnm_files|Where-Object{$_.FullName -and [IO.Path]::GetFullPath($_.FullName) -ieq [IO.Path]::GetFullPath($exported)})
  if($matches.Count -ne 1 -or -not(Test-Path -LiteralPath $exported -PathType Leaf) -or (Get-Item -LiteralPath $exported).Length -ne $matches[0].Length -or (Get-Item -LiteralPath $exported).LastWriteTimeUtc -lt (Get-Item -LiteralPath $preflightPath).LastWriteTimeUtc){throw 'KV_ST_EXPORT_FRESHNESS_OR_TARGET'}
  $comparison=& (Get-KvStPackTool) -SourcePath $c.source_path -ExportPath $exported -ModuleName $c.module_name -Category $c.category -DeviceCode 60|ConvertFrom-Json
  Assert-StTrue $comparison.ok 'KV_ST_BODY_COMPARE_FAILED';Assert-StTrue $comparison.st_body_verified 'KV_ST_BODY_NOT_VERIFIED'
  $comparison|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $OutDir 'st_body_comparison.json') -Encoding UTF8
  Copy-Item -LiteralPath $exported -Destination (Join-Path $OutDir 'body.mnm')
  $result=@{ok=$true;module_name=$c.module_name;project_path=$ProjectPath;tree_path=$target[0].path;st_body_verified=$true;source_sha256=$comparison.source_sha256;body_sha256=$comparison.export_sha256;local_rows=$localRows;argument_rows=$argumentRows;global_expected_count=$checked.globals.Count;global_rows=$globalRows;local_reopen_verified=$true;argument_reopen_verified=($c.category -eq 'function_block');unfiltered_completeness_verified=$false;compile_acceptance_required=$true;compile_verified_by_executor=$false;unverified=@('PLC runtime behavior','unfiltered table completeness','initial values, retain, device, comments','compile acceptance is checked by the enclosing executor after this step')}
}catch{$result=@{ok=$false;error_code=($_.Exception.Message -split ':')[0];message=$_.Exception.Message}}
$result|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $OutDir 'st_module_result.json') -Encoding UTF8
if(-not $result.ok){[Console]::Error.WriteLine($result.message);exit 1}
exit 0
