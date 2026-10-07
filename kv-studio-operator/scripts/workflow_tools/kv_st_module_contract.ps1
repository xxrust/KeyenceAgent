. (Join-Path $PSScriptRoot 'kv_complete_module_contract.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'kv_variable_definition_lib.ps1')
function Get-KvStPackTool {
  $skills=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
  $path=Join-Path $skills 'keyence-plc-programmer/scripts/new_kv_st_mnm.ps1'
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'KV_ST_PACK_TOOL_MISSING'}
  return $path
}
function Read-KvStModuleContract([string]$ContractPath,[string]$ProjectPath,[switch]$AfterCreate){
  $ContractPath=[IO.Path]::GetFullPath($ContractPath)
  $c=Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8|ConvertFrom-Json
  $allowed=@('schema_version','module_name','category','parent_path','source_path','body_path','locals_path','arguments_path','globals_path','evidence_paths','allowed_custom_data_types')
  foreach($p in $c.PSObject.Properties){if($p.Name -notin $allowed){throw "KV_ST_CONTRACT_FIELD: $($p.Name)"}}
  if($c.schema_version -ne 1){throw 'KV_ST_CONTRACT_VERSION'}
  if($c.module_name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,47}$' -or (Test-KvSoftDeviceLikeVariableName $c.module_name)){throw 'KV_ST_CONTRACT_NAME'}
  if($c.category -notin @('scan','function_block')){throw 'KV_ST_CONTRACT_CATEGORY'}
  $scan=-join([char[]]@(0x6BCF,0x6B21,0x626B,0x63CF,0x6267,0x884C,0x578B,0x6A21,0x5757))
  $fb=-join([char[]]@(0x529F,0x80FD,0x5757))
  $category=if($c.category -eq 'scan'){$scan}else{$fb}
  if($c.parent_path -isnot [array] -or $c.parent_path.Count -lt 1 -or $c.parent_path[0] -cne $category -or @($c.parent_path|Where-Object{$_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_)}).Count){throw 'KV_ST_CONTRACT_PARENT'}
  $nodes=@(Get-KvModuleTreePaths $ProjectPath)
  $cpus=@($nodes|Where-Object{$_.name -match '^\[0\]\s+KV-'})
  if($cpus.Count -ne 1 -or $cpus[0].name -notmatch '^\[0\]\s+KV-X520$'){throw 'KV_ST_CPU_NOT_VERIFIED'}
  if(@($nodes|Where-Object{Test-KvTreePathSuffix $_.path $c.parent_path}).Count -ne 1){throw 'KV_ST_PARENT_MISSING_OR_AMBIGUOUS'}
  if(-not $AfterCreate -and @($nodes|Where-Object{$_.name -ieq $c.module_name}).Count){throw 'KV_ST_MODULE_ALREADY_EXISTS'}
  if($c.PSObject.Properties.Name -contains 'allowed_custom_data_types' -and $c.allowed_custom_data_types -isnot [array]){throw 'KV_ST_CUSTOM_TYPES_SCHEMA'}
  $custom=@($c.allowed_custom_data_types|Where-Object{$_})
  foreach($type in $custom){
    if($type -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,47}$' -or @($nodes|Where-Object{$_.name -ceq $type -and $_.path -ccontains $fb}).Count -ne 1){throw 'KV_ST_CUSTOM_TYPE_NOT_EXISTING_FB'}
  }
  $required=@('source_path','body_path','locals_path')
  if($c.category -eq 'function_block'){$required+='arguments_path'}elseif($c.arguments_path){throw 'KV_ST_SCAN_ARGUMENTS_FORBIDDEN'}
  foreach($field in @($required)+@('globals_path')){
    if(-not $c.$field){if($field -in $required){throw "KV_ST_INPUT_REQUIRED: $field"};continue}
    $full=Resolve-KvCompleteModuleInputPath $ContractPath ([string]$c.$field)
    if(-not(Test-Path -LiteralPath $full -PathType Leaf) -or (Get-Item -LiteralPath $full).Length -eq 0){throw "KV_ST_INPUT_MISSING: $field"}
    $c.$field=$full
  }
  if([IO.Path]::GetExtension($c.source_path) -ine '.st' -or [IO.Path]::GetExtension($c.body_path) -ine '.mnm'){throw 'KV_ST_SOURCE_EXTENSION'}
  if($c.evidence_paths -isnot [array] -or $c.evidence_paths.Count -eq 0){throw 'KV_ST_EVIDENCE_REQUIRED'}
  $evidence=@(foreach($item in $c.evidence_paths){
    $full=Resolve-KvCompleteModuleInputPath $ContractPath ([string]$item)
    if(-not(Test-Path -LiteralPath $full -PathType Leaf) -or (Get-Item -LiteralPath $full).Length -eq 0){throw 'KV_ST_EVIDENCE_MISSING'}
    $full
  });$c.evidence_paths=$evidence
  $bytes=[IO.File]::ReadAllBytes($c.body_path)
  if($bytes.Length -lt 4 -or $bytes[0] -ne 255 -or $bytes[1] -ne 254 -or ($bytes[2] -eq 0 -and $bytes[3] -eq 0)){throw 'KV_ST_IMPORT_REQUIRES_UTF16LE'}
  $compare=& (Get-KvStPackTool) -SourcePath $c.source_path -ExportPath $c.body_path -ModuleName $c.module_name -Category $c.category -DeviceCode 60|ConvertFrom-Json
  if($compare.ok -isnot [bool] -or -not $compare.ok -or -not $compare.st_body_verified){throw 'KV_ST_SOURCE_BODY_MISMATCH'}
  $symbols=@{};$locals=@();$globals=@();$arguments=@()
  foreach($scope in @('local','global')){
    $path=if($scope -eq 'local'){$c.locals_path}else{$c.globals_path}
    if(-not $path){continue}
    $rows=@(Import-Csv -LiteralPath $path -Delimiter "`t" -Encoding UTF8)
    if($rows.Count -eq 0){throw 'KV_ST_DECLARATIONS_EMPTY'}
    foreach($row in $rows){
      if($row.scope -cne $scope -or $row.status -cne 'declared' -or $row.name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or ($scope -eq 'local' -and $row.owner_program -cne $c.module_name) -or ($scope -eq 'global' -and $row.owner_program)){throw 'KV_ST_DECLARATION_SCHEMA'}
      foreach($p in $row.PSObject.Properties){if($p.Name -notin @('scope','owner_program','name','data_type','status','evidence') -and $p.Value){throw "KV_ST_DECLARATION_FIELD_UNSUPPORTED: $($p.Name)"}}
      if($symbols.ContainsKey($row.name)){throw 'KV_ST_DUPLICATE_SYMBOL'};$symbols[$row.name]=$scope
    }
    $errors=@(Get-KvVariableDefinitionErrors -Rows $rows -Scope $scope -ExpectedOwnerProgram $c.module_name -AllowedCustomDataTypes $custom)+@(Get-KvVariableWriteCapabilityErrors -Rows $rows)
    if($errors.Count){throw "$($errors[0].code): $($errors[0].message)"}
    if($scope -eq 'local'){$locals=$rows}else{$globals=$rows}
  }
  if($c.category -eq 'function_block'){
    $arguments=@(Import-Csv -LiteralPath $c.arguments_path -Delimiter "`t" -Encoding UTF8)
    if(-not $arguments.Count){throw 'KV_ST_ARGUMENTS_EMPTY'}
    foreach($row in $arguments){
      if($row.owner_program -cne $c.module_name -or $row.status -cne 'declared' -or $row.argument_name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $row.argument_kind -cnotin @('IN','OUT','IN-OUT') -or -not(Test-KvVariableDataType $row.data_type) -or (Test-KvSoftDeviceLikeVariableName $row.argument_name)){throw 'KV_ST_ARGUMENT_SCHEMA'}
      foreach($p in $row.PSObject.Properties){
        if($p.Name -in @('constant','retain','hidden')){if($p.Value -and $p.Value -ine 'False'){throw 'KV_ST_ARGUMENT_FIELD_UNSUPPORTED'}}
        elseif($p.Name -notin @('owner_program','argument_name','argument_kind','data_type','status','evidence') -and $p.Value){throw 'KV_ST_ARGUMENT_FIELD_UNSUPPORTED'}
      }
      if($symbols.ContainsKey($row.argument_name)){throw 'KV_ST_DUPLICATE_SYMBOL'};$symbols[$row.argument_name]=$row.argument_kind
    }
  }
  return @{contract=$c;locals=$locals;globals=$globals;arguments=$arguments;custom_types=$custom;input_paths=@($ContractPath,$c.source_path,$c.body_path,$c.locals_path,(Get-KvStPackTool))+@($c.arguments_path,$c.globals_path|Where-Object{$_})+$evidence;verification_scope='KV-X520 pure AREA_ST source equality, numeric declaration schema, existing FB types, exact parent; actual compiler decides ST language correctness'}
}
