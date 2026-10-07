param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$path=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/workflow_tools/assert_kv_st_module_result.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Verifier parse failed'}
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Assert-StRows'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$local=@([pscustomobject]@{name='Samples';data_type='ARRAY[0..3] OF REAL'},[pscustomobject]@{name='Total';data_type='LREAL'})
$argsExpected=@([pscustomobject]@{argument_name='Samples';data_type='ARRAY[0..3] OF REAL';argument_kind='IN-OUT'},[pscustomobject]@{argument_name='Total';data_type='LREAL';argument_kind='OUT'})
$validLocal="Samples`tARRAY[0..3] OF REAL`r`nTotal`tLREAL`r`n`t`t`r`n"
$validArgs="Samples`tIN-OUT`tFalse`tARRAY[0..3] OF REAL`r`nTotal`tOUT`tFalse`tLREAL`r`n`t`t`t`r`n"
$cases=@(
 @{name='local_exact';kind='local';text=$validLocal;expected=$local;pass=$true},
 @{name='argument_exact';kind='argument';text=$validArgs;expected=$argsExpected;pass=$true},
 @{name='wrong_array_extent';kind='local';text=$validLocal.Replace('0..3','0..4');expected=$local;pass=$false},
 @{name='wrong_numeric_precision';kind='local';text=$validLocal.Replace('LREAL','REAL');expected=$local;pass=$false},
 @{name='wrong_direction';kind='argument';text=$validArgs.Replace('IN-OUT','IN');expected=$argsExpected;pass=$false},
 @{name='extra_local';kind='local';text=$validLocal+"Unexpected`tREAL`r`n";expected=$local;pass=$false},
 @{name='duplicate_argument';kind='argument';text=$validArgs+"Total`tOUT`tFalse`tLREAL`r`n";expected=$argsExpected;pass=$false},
 @{name='missing_local';kind='local';text="Samples`tARRAY[0..3] OF REAL`r`n";expected=$local;pass=$false},
 @{name='partial_row';kind='local';text=$validLocal+"Partial`t`r`n";expected=$local;pass=$false}
)
$results=@()
foreach($case in $cases){
  $failure='';try{$null=Assert-StRows $case.text $case.expected $case.kind}catch{$failure=$_.Exception.Message}
  if(([string]::IsNullOrEmpty($failure)) -ne $case.pass){throw "Unexpected copyback result: $($case.name) $failure"}
  $results+=@{case=$case.name;ok=$true;observed_error=$failure}
}
$null=New-Item -ItemType Directory -Force -Path $OutDir
@{ok=$true;ui_started=$false;tests=$results}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) exact numeric declaration copyback cases"
