# Non-UI contract shared by preparation and final verification.
function Resolve-KvCompleteModuleInputPath([string]$ContractPath,[string]$InputPath) {
  if([IO.Path]::IsPathRooted($InputPath)){return [IO.Path]::GetFullPath($InputPath)}
  return [IO.Path]::GetFullPath([IO.Path]::Combine((Split-Path -Parent ([IO.Path]::GetFullPath($ContractPath))),$InputPath))
}
function Get-KvModuleTreePaths([string]$ProjectPath) {
  $treePath=Join-Path (Split-Path -Parent $ProjectPath) 'WsTreeEnv.xml'
  [xml]$xml=Get-Content -Raw -LiteralPath $treePath -Encoding UTF8
  $paths=[Collections.Generic.List[object]]::new()
  function Visit-KvModuleTree($Container,[string[]]$Parents) {
    foreach($child in @($Container.Child)) {
      $name=[string]$child.'value.first'
      $parts=@($Parents)
      if($name){$parts+=($name -replace '\s+\[\d+\]$','');$paths.Add(@{name=$parts[-1];path=$parts})}
      if($child.'value.second'){Visit-KvModuleTree $child.'value.second' $parts}
    }
  }
  Visit-KvModuleTree $xml.Root @()
  return $paths.ToArray()
}
function Test-KvTreePathSuffix([string[]]$Path,[string[]]$Suffix) {
  if($Suffix.Count -eq 0 -or $Path.Count -lt $Suffix.Count){return $false}
  return (($Path[($Path.Count-$Suffix.Count)..($Path.Count-1)] -join "`n") -ceq ($Suffix -join "`n"))
}
function Read-KvCompleteModuleContract([string]$ContractPath,[string]$ProjectPath,[switch]$AfterCreate) {
  $ContractPath=[IO.Path]::GetFullPath($ContractPath)
  $c=Get-Content -Raw -LiteralPath $ContractPath -Encoding UTF8|ConvertFrom-Json
  if($c.schema_version -ne 1){throw 'KV_MODULE_CONTRACT_VERSION'}
  $allowed=@('schema_version','module_name','category','parent_path','body_path','locals_path','arguments_path','evidence_paths')
  foreach($p in $c.PSObject.Properties){if($p.Name -notin $allowed){throw "KV_MODULE_CONTRACT_FIELD: $($p.Name)"}}
  if($c.module_name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,47}$'){throw 'KV_MODULE_CONTRACT_NAME'}
  if($c.category -notin @('scan','function_block')){throw 'KV_MODULE_CONTRACT_CATEGORY'}
  $categoryName=if($c.category -eq 'scan'){-join ([char[]]@(0x6BCF,0x6B21,0x626B,0x63CF,0x6267,0x884C,0x578B,0x6A21,0x5757))}else{-join ([char[]]@(0x529F,0x80FD,0x5757))}
  if($c.parent_path -isnot [array] -or @($c.parent_path).Count -lt 1 -or $c.parent_path[0] -cne $categoryName){throw 'KV_MODULE_CONTRACT_PARENT_CATEGORY'}
  $nodes=@(Get-KvModuleTreePaths $ProjectPath)
  $parent=@($nodes|Where-Object{Test-KvTreePathSuffix $_.path $c.parent_path})
  if($parent.Count -ne 1){throw 'KV_MODULE_CONTRACT_PARENT_MISSING_OR_AMBIGUOUS'}
  if(-not $AfterCreate -and @($nodes|Where-Object{$_.name -eq $c.module_name}).Count){throw 'KV_MODULE_CONTRACT_ALREADY_EXISTS'}
  foreach($field in @('body_path','locals_path')+$(if($c.category -eq 'function_block'){@('arguments_path')}else{@()})) {
    if(-not $c.$field){throw "KV_MODULE_CONTRACT_INPUT_REQUIRED: $field"}
    $resolved=Resolve-KvCompleteModuleInputPath $ContractPath ([string]$c.$field)
    if(-not(Test-Path -LiteralPath $resolved -PathType Leaf)){throw "KV_MODULE_CONTRACT_INPUT_MISSING: $field"}
    $c.$field=$resolved
  }
  if($c.category -eq 'scan' -and $c.arguments_path){throw 'KV_MODULE_CONTRACT_SCAN_ARGUMENTS'}
  if(-not @($c.evidence_paths).Count){throw 'KV_MODULE_CONTRACT_EVIDENCE_REQUIRED'}
  $evidence=@(foreach($p in $c.evidence_paths){
    if(-not $p){throw 'KV_MODULE_CONTRACT_EVIDENCE_REQUIRED'}
    $full=Resolve-KvCompleteModuleInputPath $ContractPath ([string]$p)
    if(-not(Test-Path -LiteralPath $full -PathType Leaf) -or (Get-Item -LiteralPath $full).Length -eq 0){throw 'KV_MODULE_CONTRACT_EVIDENCE_MISSING'}
    $full
  })
  $c.evidence_paths=$evidence
  $body=[IO.File]::ReadAllText($c.body_path,[Text.Encoding]::Default)
  $moduleType=if($c.category -eq 'scan'){0}else{2}
  $device=if($c.category -eq 'scan'){63}else{59}
  foreach($header in @(';MODULE',';MODULE_TYPE','DEVICE')){
    if([regex]::Matches($body,('(?im)^[ \t]*'+[regex]::Escape($header)+'[ \t]*:')).Count -ne 1){throw 'KV_MODULE_CONTRACT_MNM_HEADER'}
  }
  if(@([regex]::Matches($body,'(?m)^;MODULE:')).Count -ne 1 -or $body -notmatch ('(?m)^;MODULE:'+ [regex]::Escape($c.module_name)+'\s*$') -or $body -notmatch "(?m)^;MODULE_TYPE:$moduleType\s*$" -or $body -notmatch "(?m)^DEVICE:$device\s*$"){throw 'KV_MODULE_CONTRACT_MNM_HEADER'}
  $locals=@(Import-Csv -LiteralPath $c.locals_path -Delimiter "`t" -Encoding UTF8)
  if(-not $locals.Count){throw 'KV_MODULE_CONTRACT_LOCALS_REQUIRED'}
  $symbols=@{}
  foreach($r in $locals){
    if($r.scope -ne 'local' -or $r.owner_program -cne $c.module_name -or $r.name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $r.data_type -ne 'BOOL' -or $r.status -ne 'declared'){throw 'KV_MODULE_CONTRACT_LOCAL_SCHEMA'}
    foreach($prop in $r.PSObject.Properties){if($prop.Name -notin @('scope','owner_program','name','data_type','status','evidence') -and $prop.Value){throw "KV_MODULE_CONTRACT_LOCAL_FIELD_UNSUPPORTED: $($prop.Name)"}}
    if($symbols.ContainsKey($r.name)){throw 'KV_MODULE_CONTRACT_DUPLICATE_SYMBOL'}
    $symbols[$r.name]='local'
  }
  $arguments=@()
  if($c.category -eq 'function_block'){
    $arguments=@(Import-Csv -LiteralPath $c.arguments_path -Delimiter "`t" -Encoding UTF8)
    if(-not $arguments.Count){throw 'KV_MODULE_CONTRACT_ARGUMENTS_REQUIRED'}
    foreach($r in $arguments){
      if($r.owner_program -cne $c.module_name -or $r.argument_name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $r.argument_kind -notin @('IN','OUT','IN-OUT') -or $r.data_type -ne 'BOOL' -or $r.status -ne 'declared'){throw 'KV_MODULE_CONTRACT_ARGUMENT_SCHEMA'}
      foreach($prop in $r.PSObject.Properties){
        if($prop.Name -in @('constant','retain','hidden','default_value')){if($prop.Value -and $prop.Value -ne 'False'){throw 'KV_MODULE_CONTRACT_ARGUMENT_FIELD_UNSUPPORTED'}}
        elseif($prop.Name -notin @('owner_program','argument_name','argument_kind','data_type','status','evidence') -and $prop.Value){throw 'KV_MODULE_CONTRACT_ARGUMENT_FIELD_UNSUPPORTED'}
      }
      if($symbols.ContainsKey($r.argument_name)){throw 'KV_MODULE_CONTRACT_DUPLICATE_SYMBOL'}
      $symbols[$r.argument_name]=$r.argument_kind
    }
  }
  $instructions=@($body -split '\r?\n'|ForEach-Object{$_.Trim()}|Where-Object{$_ -and $_ -notmatch '^(;|DEVICE:)'})
  if($instructions.Count -lt 4 -or $instructions[-2] -ne 'END' -or $instructions[-1] -ne 'ENDH'){throw 'KV_MODULE_CONTRACT_BODY_TERMINATOR'}
  $haveLoad=$false;$writes=0;$used=@{}
  foreach($line in $instructions[0..($instructions.Count-3)]){
    if($line -cnotmatch '^(LD|LDB|AND|ANB|OR|ORB|OUT) ([A-Za-z_][A-Za-z0-9_]*)$'){throw "KV_MODULE_CONTRACT_INSTRUCTION_UNVERIFIED: $line"}
    $op=$matches[1];$operand=$matches[2]
    if(-not $symbols.ContainsKey($operand)){throw "KV_MODULE_CONTRACT_UNDECLARED: $operand"}
    if($operand -match '^(R|MR|DM|CR|W|B|LR|EM|FM|ZF|T|C)\d+$'){throw 'KV_MODULE_CONTRACT_DEVICE_LEAK'}
    if($op -in @('LD','LDB')){$haveLoad=$true}elseif(-not $haveLoad){throw 'KV_MODULE_CONTRACT_RUNG_LOAD_REQUIRED'}
    if($op -eq 'OUT'){if($symbols[$operand] -eq 'IN'){throw 'KV_MODULE_CONTRACT_INPUT_WRITE'};$writes++}
    $used[$operand]=$true
  }
  if(-not $writes){throw 'KV_MODULE_CONTRACT_OUTPUT_REQUIRED'}
  foreach($s in $symbols.Keys){if(-not $used.ContainsKey($s)){throw "KV_MODULE_CONTRACT_UNUSED_DECLARATION: $s"}}
  return @{contract=$c;locals=$locals;arguments=$arguments;instructions=$instructions;input_paths=@($ContractPath,$c.body_path,$c.locals_path)+@($c.arguments_path|Where-Object{$_})+$evidence}
}
