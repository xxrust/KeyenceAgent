param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$path=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/workflow_tools/assert_kv_st_module_result.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Verifier parse failed'}
foreach($name in @('Assert-StPath','Assert-StDeclarationBinding')){
  $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
  . ([scriptblock]::Create($fn.Extent.Text))
}
$project=Join-Path $OutDir 'Expected.kpr'
$contract=[pscustomobject]@{module_name='NumericScan';locals_path=(Join-Path $OutDir 'locals.tsv');globals_path=''}
$cases=@('valid','wrong_project','missing_project','wrong_owner','missing_owner','wrong_local_source','missing_local_source','unexpected_global_source','valid_global','wrong_global_source','missing_global_source')
$rows=@()
foreach($case in $cases){
  $c=$contract|ConvertTo-Json|ConvertFrom-Json
  $result=[pscustomobject]@{ProjectPath=$project;LocalProgramName=$c.module_name;LocalVariablesTsv=$c.locals_path;GlobalVariablesTsv=''}
  switch($case){
    'wrong_project' {$result.ProjectPath=Join-Path $OutDir 'Other.kpr'}
    'missing_project' {$result.PSObject.Properties.Remove('ProjectPath')}
    'wrong_owner' {$result.LocalProgramName='OtherScan'}
    'missing_owner' {$result.PSObject.Properties.Remove('LocalProgramName')}
    'wrong_local_source' {$result.LocalVariablesTsv=Join-Path $OutDir 'other.tsv'}
    'missing_local_source' {$result.PSObject.Properties.Remove('LocalVariablesTsv')}
    'unexpected_global_source' {$result.GlobalVariablesTsv=Join-Path $OutDir 'other.tsv'}
    'valid_global' {$c.globals_path=Join-Path $OutDir 'globals.tsv';$result.GlobalVariablesTsv=$c.globals_path}
    'wrong_global_source' {$c.globals_path=Join-Path $OutDir 'globals.tsv';$result.GlobalVariablesTsv=Join-Path $OutDir 'other.tsv'}
    'missing_global_source' {$c.globals_path=Join-Path $OutDir 'globals.tsv';$result.PSObject.Properties.Remove('GlobalVariablesTsv')}
  }
  $failure='';try{Assert-StDeclarationBinding $result $c $project}catch{$failure=$_.Exception.Message}
  if(([string]::IsNullOrEmpty($failure)) -ne ($case -in @('valid','valid_global'))){throw "Unexpected declaration binding result: $case $failure"}
  $rows+=@{case=$case;ok=$true;observed_error=$failure}
}
$null=New-Item -ItemType Directory -Force -Path $OutDir
@{ok=$true;ui_started=$false;tests=$rows}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($rows.Count) declaration evidence binding cases"
