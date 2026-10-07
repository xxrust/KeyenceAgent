param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$ContractPath,[Parameter(Mandatory=$true)][string]$ArtifactsRoot,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'kv_complete_module_contract.ps1')
function Assert-KvResultTrue($Value,[string]$Code) {
  if($Value -isnot [bool] -or -not $Value){throw $Code}
}
function Assert-KvResultPath([string]$Actual,[string]$Expected,[string]$Code) {
  if(-not $Actual -or [IO.Path]::GetFullPath($Actual) -ine [IO.Path]::GetFullPath($Expected)){throw $Code}
}
function Read-KvOwnedCopyback([string]$Path,[string]$OwnerDirectory,[string]$Code) {
  if(-not $Path){throw $Code}
  $full=[IO.Path]::GetFullPath($Path)
  $owner=[IO.Path]::GetFullPath($OwnerDirectory).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
  if(-not $full.StartsWith($owner,[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $full -PathType Leaf)){throw $Code}
  return [IO.File]::ReadAllText($full,[Text.Encoding]::UTF8)
}
function Assert-KvBoolCopyback([string]$Text,[object[]]$Expected,[switch]$Arguments) {
  $prefix=if($Arguments){'KV_MODULE_ARGUMENTS'}else{'KV_MODULE_LOCALS'}
  $rows=[Collections.Generic.List[object]]::new()
  $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach($line in @($Text -split '\r?\n')) {
    $cells=$line.Split([char]9)
    # KV STUDIO keeps an all-empty insertion row; partially filled rows fail.
    if(@($cells|Where-Object{-not [string]::IsNullOrWhiteSpace($_)}).Count -eq 0){continue}
    $typeColumn=if($Arguments){3}else{1}
    if($cells.Count -le $typeColumn -or $cells[0] -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$') {throw ($prefix+'_ROW_SCHEMA')}
    if(-not $names.Add($cells[0])){throw ($prefix+'_DUPLICATE_NAME')}
    if($cells[$typeColumn] -cne 'BOOL'){throw ($prefix+'_TYPE_MISMATCH')}
    if($Arguments -and $cells[1] -cnotin @('IN','OUT','IN-OUT')){throw ($prefix+'_DIRECTION_MISMATCH')}
    $rows.Add([pscustomobject]@{name=$cells[0];data_type=$cells[$typeColumn];direction=if($Arguments){$cells[1]}else{''}})
  }
  if($rows.Count -ne $Expected.Count){throw ($prefix+'_COUNT_MISMATCH')}
  foreach($expectedRow in $Expected) {
    $name=if($Arguments){[string]$expectedRow.argument_name}else{[string]$expectedRow.name}
    $matches=@($rows|Where-Object{$_.name -ceq $name})
    if($matches.Count -ne 1){throw ($prefix+'_NAME_MISMATCH')}
    if($matches[0].data_type -cne $expectedRow.data_type){throw ($prefix+'_TYPE_MISMATCH')}
    if($Arguments -and $matches[0].direction -cne $expectedRow.argument_kind){throw ($prefix+'_DIRECTION_MISMATCH')}
  }
  return $rows.ToArray()
}
function Assert-KvExportedModuleBody([string]$Body,[string]$ModuleName,[int]$ModuleType,[string[]]$Instructions) {
  $headers=@([regex]::Matches($Body,'(?m)^;MODULE:([^\r\n]*)\r?$'))
  $types=@([regex]::Matches($Body,'(?m)^;MODULE_TYPE:([^\r\n]*)\r?$'))
  if($headers.Count -ne 1 -or $headers[0].Groups[1].Value.Trim() -cne $ModuleName -or $types.Count -ne 1 -or $types[0].Groups[1].Value.Trim() -cne [string]$ModuleType){throw 'KV_MODULE_BODY_HEADER_MISMATCH'}
  $actual=@($Body -split '\r?\n'|ForEach-Object{$_.Trim()}|Where-Object{$_ -and $_ -notmatch '^(;|DEVICE:)'})
  if(($actual -join "`n") -cne ($Instructions -join "`n")){throw 'KV_MODULE_BODY_READBACK_MISMATCH'}
}
function Assert-KvArgumentSnapshot($Snapshot,[string]$ExpectedProject,[string]$ExpectedModule,[int]$ExpectedCount) {
  foreach($flag in @('ok','read_only','focus_verified','clipboard_fresh','all_columns_preserved')) {
    Assert-KvResultTrue $Snapshot.$flag ('KV_MODULE_ARGUMENTS_SNAPSHOT_'+$flag.ToUpperInvariant())
  }
  Assert-KvResultPath $Snapshot.project_path $ExpectedProject 'KV_MODULE_ARGUMENTS_PROJECT_MISMATCH'
  if($Snapshot.module_name -cne $ExpectedModule){throw 'KV_MODULE_ARGUMENTS_OWNER_MISMATCH'}
  if(($Snapshot.row_count -isnot [int] -and $Snapshot.row_count -isnot [long]) -or $Snapshot.row_count -ne $ExpectedCount){throw 'KV_MODULE_ARGUMENTS_COUNT_MISMATCH'}
}
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
try{
  $checked=Read-KvCompleteModuleContract $ContractPath $ProjectPath -AfterCreate
  $c=$checked.contract
  $expected=@($c.parent_path)+@($c.module_name)
  $nodes=@(Get-KvModuleTreePaths $ProjectPath)
  $target=@($nodes|Where-Object{Test-KvTreePathSuffix $_.path $expected})
  if($target.Count -ne 1){throw 'KV_MODULE_PLACEMENT_MISMATCH'}
  $exported=Join-Path (Split-Path -Parent $ProjectPath) ($c.module_name+'.mnm')
  $exportResult=Get-Content -Raw -LiteralPath (Join-Path $ArtifactsRoot 'export\browse_folder_export_result.json') -Encoding UTF8|ConvertFrom-Json
  Assert-KvResultTrue $exportResult.ok 'KV_MODULE_EXPORT_FAILED'
  Assert-KvResultPath $exportResult.project_path $ProjectPath 'KV_MODULE_EXPORT_PROJECT_MISMATCH'
  $exportMatches=@($exportResult.mnm_files|Where-Object{$_.FullName -and [IO.Path]::GetFullPath($_.FullName) -ieq [IO.Path]::GetFullPath($exported)})
  if($exportMatches.Count -ne 1 -or -not(Test-Path -LiteralPath $exported -PathType Leaf)){throw 'KV_MODULE_EXPORT_TARGET_MISSING'}
  if((Get-Item -LiteralPath $exported).Length -ne $exportMatches[0].Length){throw 'KV_MODULE_EXPORT_TARGET_CHANGED'}
  $body=[IO.File]::ReadAllText($exported,[Text.Encoding]::Default)
  $moduleType=if($c.category -eq 'scan'){0}else{2}
  Assert-KvExportedModuleBody $body $c.module_name $moduleType $checked.instructions
  $localStep=Get-Content -Raw -LiteralPath (Join-Path $ArtifactsRoot 'locals\set_variables_result.json') -Encoding UTF8|ConvertFrom-Json
  Assert-KvResultTrue $localStep.Ok 'KV_MODULE_LOCALS_WRITE_FAILED'
  Assert-KvResultTrue $localStep.AuditPersistence 'KV_MODULE_LOCALS_READBACK_MISSING'
  Assert-KvResultPath $localStep.ProjectPath $ProjectPath 'KV_MODULE_LOCALS_PROJECT_MISMATCH'
  $locals=Get-Content -Raw -LiteralPath (Join-Path $ArtifactsRoot 'locals\variable_persistence_validation.json') -Encoding UTF8|ConvertFrom-Json
  Assert-KvResultTrue $locals.Ok 'KV_MODULE_LOCALS_READBACK_MISSING'
  Assert-KvResultTrue $locals.LocalReopenClipboardContainsExpectedNames 'KV_MODULE_LOCALS_READBACK_MISSING'
  $raw=Read-KvOwnedCopyback $locals.LocalReopenClipboardPath (Join-Path $ArtifactsRoot 'locals') 'KV_MODULE_LOCALS_READBACK_MISSING'
  $localRows=@(Assert-KvBoolCopyback $raw $checked.locals)
  $argumentRows=@()
  $argumentCopybackPath=$null
  $argumentReopenVerified=$false
  if($c.category -eq 'function_block'){
    $arguments=Get-Content -Raw -LiteralPath (Join-Path $ArtifactsRoot 'arguments\set_fb_arguments_result.json') -Encoding UTF8|ConvertFrom-Json
    Assert-KvResultTrue $arguments.ok 'KV_MODULE_ARGUMENTS_READBACK_MISSING'
    Assert-KvResultPath $arguments.project_path $ProjectPath 'KV_MODULE_ARGUMENTS_PROJECT_MISMATCH'
    if($arguments.fb_module_name -cne $c.module_name){throw 'KV_MODULE_ARGUMENTS_OWNER_MISMATCH'}
    Assert-KvResultPath $arguments.arguments_tsv $c.arguments_path 'KV_MODULE_ARGUMENTS_INPUT_MISMATCH'
    $readbackDir=Join-Path $ArtifactsRoot 'arguments_readback'
    $snapshotPath=Join-Path $readbackDir 'fb_snapshot_result.json'
    $snapshot=Get-Content -Raw -LiteralPath $snapshotPath -Encoding UTF8|ConvertFrom-Json
    Assert-KvArgumentSnapshot $snapshot $ProjectPath $c.module_name $checked.arguments.Count
    $argumentCopybackPath=$snapshot.raw_path
    $argumentRaw=Read-KvOwnedCopyback $argumentCopybackPath $readbackDir 'KV_MODULE_ARGUMENTS_READBACK_MISSING'
    $localsCompleted=(Get-Item -LiteralPath (Join-Path $ArtifactsRoot 'locals\set_variables_result.json')).LastWriteTimeUtc
    if((Get-Item -LiteralPath $snapshotPath).LastWriteTimeUtc -lt $localsCompleted -or (Get-Item -LiteralPath $argumentCopybackPath).LastWriteTimeUtc -lt $localsCompleted){throw 'KV_MODULE_ARGUMENTS_READBACK_STALE'}
    $argumentRows=@(Assert-KvBoolCopyback $argumentRaw $checked.arguments -Arguments)
    $argumentReopenVerified=$true
  }
  Copy-Item -LiteralPath $exported -Destination (Join-Path $OutDir 'body.mnm')
  $verification='saved tree path and current-export instructions; exact local name/type/count after editor reopen; compile checked by executor'
  if($c.category -eq 'function_block'){$verification+='; FB argument name/direction/type/count from a fresh read-only snapshot after saved local-editor reopen'}
  $result=@{ok=$true;module_name=$c.module_name;parent_path=$c.parent_path;body_equal=$true;body_sha256=(Get-FileHash -LiteralPath $exported -Algorithm SHA256).Hash;local_count=$localRows.Count;argument_count=$argumentRows.Count;local_rows=$localRows;argument_rows=$argumentRows;local_copyback_path=$locals.LocalReopenClipboardPath;argument_copyback_path=$argumentCopybackPath;tree_path=$target[0].path;local_reopen_verified=$true;argument_reopen_verified=$argumentReopenVerified;unfiltered_completeness_verified=$false;verification=$verification;unverified=@('unfiltered declaration-table completeness','initial_value/device/retain/constant/comment persistence','PLC runtime behavior')}
}catch{$result=@{ok=$false;error_code=($_.Exception.Message -split ':')[0];message=$_.Exception.Message}}
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutDir 'complete_module_result.json') -Encoding UTF8
if(-not $result.ok){[Console]::Error.WriteLine($result.message);exit 1}
exit 0
