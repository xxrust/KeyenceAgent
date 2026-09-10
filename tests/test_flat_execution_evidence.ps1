param([string]$OutDir = (Join-Path ([IO.Path]::GetTempPath()) ('kv_flat_evidence_' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'kv-studio-operator/scripts'
$fixture = Join-Path $OutDir 'fixture scripts'
$toolDir = Join-Path $fixture 'workflow_tools'
$childDir = Join-Path $fixture 'runner_children'
New-Item -ItemType Directory -Force -Path $toolDir,$childDir | Out-Null
Copy-Item -LiteralPath (Join-Path $source 'Resolve-KvStudioOperatorScript.ps1') -Destination $fixture
foreach ($name in @('invoke_kv_flat_execution_plan.ps1','kv_step_evidence.ps1')) {
  Copy-Item -LiteralPath (Join-Path $source "workflow_tools/$name") -Destination $toolDir
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures/flat-execution/child.ps1') -Destination $childDir
$manifest = @{
  classes=@{runner_child_approved=@(@{path='runner_children/child.ps1';status='approved'});runner_child_pending=@(@{path='runner_children/pending.ps1';status='pending'})}
  step_result_contracts=@{'runner_children/child.ps1'=@{files=@('result.json');variants=@(@{switch='-SnapshotOnly';files=@('snapshot.json')})}}
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixture 'script_manifest.json') -Encoding UTF8
$executor = Join-Path $toolDir 'invoke_kv_flat_execution_plan.ps1'
$checks = @()
function Run-Case([string]$Name,[string]$Mode,[string]$ExpectedCode='', [switch]$Snapshot) {
  $runRoot = Join-Path $OutDir $Name
  $stepOut = Join-Path $runRoot 'child output'
  New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
  $argsList=@('-OutDir',$stepOut,'-Mode',$Mode)
  if ($Mode -eq 'quoting') { $argsList+=@('-Value','space "quote" $cash `literal \trailing\','-Empty','') }
  if ($Snapshot) { $argsList+='-SnapshotOnly' }
  $plan=@{
    ok=$true;operation='evidence regression';run_root=$runRoot;artifact_root=$runRoot;result_path=(Join-Path $runRoot 'workflow_result.json')
    require_compile_result=$false;timeout_seconds=15
    steps=@(@{name='fixture';kind='runner_child';script_name='child.ps1';classes=@('runner_child_approved');out_dir=$stepOut;arguments=$argsList;timeout_seconds=$(if($Mode -eq 'timeout'){1}else{10})})
  }
  if ($Mode -eq 'unregistered') { $plan.steps[0].script_name=Join-Path $source 'workflow_tools/kv_step_evidence.ps1' }
  if ($Mode -eq 'typed') {
    $plan.steps[0].Remove('arguments')
    $plan.steps[0].parameters=@{OutDir=$stepOut;Mode='typed';Items=@('model, one','model two');SnapshotOnly=$true}
  }
  $planPath=Join-Path $runRoot 'plan.json'
  $plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8
  & powershell -NoProfile -ExecutionPolicy Bypass -File $executor -PlanPath $planPath
  $exit=$LASTEXITCODE
  $result=Get-Content -Raw -Encoding UTF8 $plan.result_path | ConvertFrom-Json
  if ($ExpectedCode) {
    if ($exit -eq 0 -or $result.ok) { throw "Accepted invalid case: $Name/$Mode" }
    if ($ExpectedCode -ne '*' -and $result.error_code -ne $ExpectedCode) { throw "Wrong rejection for ${Mode}: $($result | ConvertTo-Json -Depth 8)" }
  } else {
    if ($exit -ne 0 -or -not $result.ok) { throw "Rejected valid case: $Name $($result | ConvertTo-Json -Depth 8)" }
    $receipt=Get-Content -Raw -Encoding UTF8 (Join-Path $stepOut 'step_receipt.json') | ConvertFrom-Json
    if ($receipt.run_id -ne $result.run_id -or -not $receipt.code_sha256 -or $receipt.artifacts.Count -ne 1) { throw 'Missing evidence binding' }
  }
  $script:checks+=@{case=$Name;mode=$Mode;exit_code=$exit;error_code=$result.error_code;ok=$true}
}
Run-Case 'quoted values' 'quoting'
Run-Case 'snapshot' 'pass' -Snapshot
Run-Case 'typed arrays' 'typed'
Run-Case 'reuse' 'pass'
Run-Case 'reuse' 'missing' 'KV_STEP_RESULT_MISSING'
if (@(Get-ChildItem -LiteralPath (Join-Path $OutDir 'reuse/child output/_history') -Filter result.json -Recurse).Count -ne 1) { throw 'Previous result was not preserved' }
foreach ($case in @(
  @('missing','KV_STEP_RESULT_MISSING'),@('malformed','KV_STEP_RESULT_INVALID_JSON'),
  @('no_ok','KV_STEP_RESULT_NOT_OK'),@('string_ok','KV_STEP_RESULT_NOT_OK'),@('false_ok','KV_STEP_RESULT_NOT_OK'),
  @('stale','KV_STEP_RESULT_STALE'),@('process_fail','KV_FLAT_WORKFLOW_STEP_FAILED'),
  @('sentinel_fail','KV_FLAT_WORKFLOW_STEP_FAILED'),@('failure_file','KV_STEP_FAILURE_ARTIFACT_PRESENT'),
  @('stderr','KV_FLAT_WORKFLOW_STEP_FAILED'),@('timeout','KV_FLAT_WORKFLOW_STEP_TIMEOUT'),@('unregistered','*')
)) { Run-Case $case[0] $case[0] $case[1] }
@{ok=$true;desktop_input=$false;cases=$checks;out_dir=$OutDir} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
@{ok=$true;cases=$checks.Count;out_dir=$OutDir} | ConvertTo-Json
