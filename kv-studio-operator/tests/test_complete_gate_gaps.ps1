param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$ContractPath,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$scriptsRoot=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
. (Join-Path $scriptsRoot 'workflow_tools/kv_complete_module_contract.ps1')
. (Join-Path $scriptsRoot 'workflow_tools/kv_step_evidence.ps1')
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
$results=[Collections.Generic.List[object]]::new()
function RejectContract([string]$Name,[scriptblock]$Mutate,[string]$Code){
  $dir=Join-Path $OutDir $Name
  Copy-Item -LiteralPath (Split-Path -Parent $ContractPath) -Destination $dir -Recurse
  $path=Join-Path $dir (Split-Path -Leaf $ContractPath)
  $c=Get-Content -Raw -Encoding UTF8 -LiteralPath $path|ConvertFrom-Json
  & $Mutate $c $dir
  $c|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding UTF8
  $caught=''
  try{$null=Read-KvCompleteModuleContract $path $ProjectPath}catch{$caught=$_.Exception.Message}
  if(-not $caught.StartsWith($Code)){throw "$Name expected $Code got $caught"}
  $results.Add(@{name=$Name;ok=$true;error_code=$Code})
}
RejectContract 'wrong_group' {param($c,$d) $c.parent_path[-1]='nonexistent_station_group'} 'KV_MODULE_CONTRACT_PARENT_MISSING_OR_AMBIGUOUS'
RejectContract 'undeclared_operand' {param($c,$d) $p=Join-Path $d $c.body_path;$s=[IO.File]::ReadAllText($p,[Text.Encoding]::Default);$s=$s.Replace('LD Enable','LD MissingOperand');[IO.File]::WriteAllText($p,$s,[Text.Encoding]::Default)} 'KV_MODULE_CONTRACT_UNDECLARED'
RejectContract 'write_input' {param($c,$d) $p=Join-Path $d $c.body_path;$s=[IO.File]::ReadAllText($p,[Text.Encoding]::Default);$s=$s.Replace('OUT Ready','OUT Enable');[IO.File]::WriteAllText($p,$s,[Text.Encoding]::Default)} 'KV_MODULE_CONTRACT_INPUT_WRITE'
RejectContract 'module_name_49_chars' {param($c,$d) $c.module_name='M'*49} 'KV_MODULE_CONTRACT_NAME'
RejectContract 'evidence_not_declared' {param($c,$d) $c.evidence_paths=@()} 'KV_MODULE_CONTRACT_EVIDENCE_REQUIRED'
RejectContract 'evidence_missing' {param($c,$d) $c.evidence_paths=@('missing_evidence.md')} 'KV_MODULE_CONTRACT_EVIDENCE_MISSING'
RejectContract 'evidence_empty' {param($c,$d) [IO.File]::WriteAllText((Join-Path $d $c.evidence_paths[0]),'')} 'KV_MODULE_CONTRACT_EVIDENCE_MISSING'
$evidenceDir=Join-Path $OutDir 'stale_result'
New-Item -ItemType Directory -Force -Path $evidenceDir|Out-Null
$resultPath=Join-Path $evidenceDir 'result.json'
@{ok=$true}|ConvertTo-Json|Set-Content -LiteralPath $resultPath -Encoding UTF8
(Get-Item -LiteralPath $resultPath).LastWriteTimeUtc=[datetime]::UtcNow.AddDays(-1)
$contract=[pscustomobject]@{files=@('result.json');artifacts=@()}
$caught=''
try{$null=Test-KvStepEvidence $evidenceDir $contract ([datetime]::UtcNow)}catch{$caught=$_.Exception.Message}
if(-not $caught.StartsWith('KV_STEP_RESULT_STALE')){throw "Reused result accepted: $caught"}
$results.Add(@{name='stale_result_rejected';ok=$true;error_code='KV_STEP_RESULT_STALE'})
$runId=[guid]::NewGuid().ToString('N')
Move-KvPreviousStepEvidence $evidenceDir $contract $runId
if(-not(Test-Path -LiteralPath (Join-Path $evidenceDir "_history/$runId/result.json"))){throw 'Previous result not archived'}
$caught=''
try{$null=Test-KvStepEvidence $evidenceDir $contract ([datetime]::UtcNow)}catch{$caught=$_.Exception.Message}
if(-not $caught.StartsWith('KV_STEP_RESULT_MISSING')){throw "Archived result reused: $caught"}
$results.Add(@{name='archived_result_cannot_substitute_current_result';ok=$true;error_code='KV_STEP_RESULT_MISSING'})
@{ok=$true;ui_started=$false;tests=@($results)}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) previously uncovered gate tests."
