param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$ContractPath,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/workflow_tools/kv_complete_module_contract.ps1')
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
$results=@()
foreach($mode in @('relative','absolute','mixed','parent_relative')){
  $directory=Join-Path $OutDir $mode
  Copy-Item -LiteralPath (Split-Path -Parent $ContractPath) -Destination $directory -Recurse
  $c=Get-Content -Raw -Encoding UTF8 -LiteralPath $ContractPath|ConvertFrom-Json
  $path=Join-Path $directory 'contract.json'
  $expected=@{}
  foreach($field in @('body_path','locals_path','arguments_path')){
    if(-not $c.$field){continue}
    $expected[$field]=[IO.Path]::GetFullPath((Join-Path $directory ([IO.Path]::GetFileName($c.$field))))
    if($mode -eq 'absolute' -or ($mode -eq 'mixed' -and $field -ne 'locals_path')){$c.$field=$expected[$field]}
  }
  $evidence=@($c.evidence_paths|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $directory ([IO.Path]::GetFileName($_))))})
  if($mode -in @('absolute','mixed')){$c.evidence_paths=$evidence}
  if($mode -eq 'parent_relative'){
    $nested=Join-Path $directory 'nested'
    New-Item -ItemType Directory -Force -Path $nested|Out-Null
    $path=Join-Path $nested 'contract.json'
    foreach($field in $expected.Keys){$c.$field=Join-Path '..' ([IO.Path]::GetFileName($expected[$field]))}
    $c.evidence_paths=@($evidence|ForEach-Object{Join-Path '..' ([IO.Path]::GetFileName($_))})
  }
  $c|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding UTF8
  $checked=Read-KvCompleteModuleContract $path $ProjectPath
  foreach($field in $expected.Keys){if($checked.contract.$field -cne $expected[$field]){throw "$mode $field resolved incorrectly"}}
  if(($checked.contract.evidence_paths -join "`n") -cne ($evidence -join "`n")){throw "$mode evidence resolved incorrectly"}
  foreach($inputFilePath in @($expected.Values)+$evidence){if(@($checked.input_paths|Where-Object{$_ -eq $inputFilePath}).Count -ne 1){throw "$mode input fingerprint scope incorrect: $inputFilePath"}}
  $results+=@{name=$mode;ok=$true;body_path=$checked.contract.body_path;locals_path=$checked.contract.locals_path;arguments_path=$checked.contract.arguments_path;evidence_paths=$checked.contract.evidence_paths}
}
$workflow=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/workflows/create_kv_complete_module.ps1'
$absoluteContract=Join-Path $OutDir 'absolute/contract.json'
$planOut=Join-Path $OutDir 'absolute_workflow_plan'
& powershell -STA -NoProfile -ExecutionPolicy Bypass -File $workflow -ProjectPath $ProjectPath -ContractPath $absoluteContract -OutDir $planOut -PlanOnly *> (Join-Path $OutDir 'absolute_workflow_stdout.txt')
if($LASTEXITCODE -ne 0){throw "Absolute-input public workflow PlanOnly failed; inspect $OutDir/absolute_workflow_stdout.txt"}
$workflowResult=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $planOut 'workflow_result.json')|ConvertFrom-Json
if($workflowResult.ok -isnot [bool] -or -not $workflowResult.ok -or $workflowResult.status -ne 'planned' -or $workflowResult.ui_started -ne $false){throw 'Absolute-input public workflow did not report planned without UI'}
$fingerprintResult=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $planOut 'plan_preflight_result.json')|ConvertFrom-Json
$absoluteChecked=Read-KvCompleteModuleContract $absoluteContract $ProjectPath
foreach($inputFilePath in $absoluteChecked.input_paths){if(@($fingerprintResult.inputs|Where-Object{$_.path -eq $inputFilePath}).Count -ne 1){throw "Absolute-input public workflow omitted fingerprint: $inputFilePath"}}
$results+=@{name='public_workflow_planonly_absolute_inputs';ok=$true;ui_started=$false;result_path=(Join-Path $planOut 'workflow_result.json')}
@{ok=$true;ui_started=$false;tests=$results}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) complete contract path tests."
