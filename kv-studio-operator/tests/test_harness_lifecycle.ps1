param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$harness=Join-Path $PSScriptRoot 'kv-interface-regression/run-workflow-test.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($harness,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Harness parse failed'}
foreach($name in @('Wait-KvsProcess','Stop-OwnedKvsTestProcess')){
  $definition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
  . ([scriptblock]::Create($definition.Extent.Text))
}
# All process access and waiting below is mocked; no OS process is touched.
$script:lookupCount=0;$script:sleepCount=0;$script:killed=$false;$script:mode='ready'
$expectedStart=[datetime]::SpecifyKind([datetime]'2026-09-20T00:00:00',[DateTimeKind]::Utc)
$owned=[pscustomobject]@{Id=41;ProcessName='Kvs';StartTime=$expectedStart;MainWindowHandle=10L;MainWindowTitle='KV STUDIO sample*'}
$owned|Add-Member -MemberType ScriptMethod -Name Kill -Value {$script:killed=$true}
function Get-Process {
  param([Parameter(Mandatory=$true)][int]$Id)
  if($Id -ne 41){throw "Unexpected PID lookup: $Id"}
  $script:lookupCount++
  if($script:mode -eq 'exited'){return $null}
  if($script:mode -eq 'reused'){return [pscustomobject]@{Id=41;ProcessName='Kvs';StartTime=$expectedStart.AddSeconds(1);MainWindowHandle=10L;MainWindowTitle='KV STUDIO sample'}}
  if($script:mode -eq 'loading' -and $script:lookupCount -eq 1){return [pscustomobject]@{Id=41;ProcessName='Kvs';StartTime=$expectedStart;MainWindowHandle=0L;MainWindowTitle=''}}
  if($script:mode -eq 'wrong_title'){return [pscustomobject]@{Id=41;ProcessName='Kvs';StartTime=$expectedStart;MainWindowHandle=10L;MainWindowTitle='KV STUDIO another project'}}
  return $owned
}
function Start-Sleep {param([int]$Milliseconds) $script:sleepCount++}
$results=[Collections.Generic.List[object]]::new()
$script:mode='loading'
$bound=Wait-KvsProcess 'sample' 41 1 $expectedStart
if($bound.Id -ne 41 -or $script:lookupCount -ne 2 -or $script:sleepCount -ne 1){throw 'Wait did not keep the original PID through loading'}
$results.Add(@{name='wait_original_pid_through_loading';ok=$true})
foreach($case in @(@{mode='exited';code='KV_TEST_PROJECT_PROCESS_EXITED'},@{mode='reused';code='KV_TEST_PROJECT_PROCESS_IDENTITY_CHANGED'},@{mode='wrong_title';code='KV_TEST_PROJECT_WINDOW_TIMEOUT'})){
  $script:mode=$case.mode;$caught=''
  try{$null=Wait-KvsProcess 'sample' 41 0 $expectedStart}catch{$caught=$_.Exception.Message}
  if(-not $caught.StartsWith($case.code)){throw "Expected $($case.code), got $caught"}
  $results.Add(@{name=$case.mode;ok=$true})
}
$script:mode='ready'
$status=Stop-OwnedKvsTestProcess $owned $expectedStart
if($status -ne 'stopped_owned_process' -or -not $script:killed){throw 'Owned process cleanup failed'}
$results.Add(@{name='cleanup_original_process_only';ok=$true})
$script:mode='reused';$script:killed=$false;$caught=''
try{$null=Stop-OwnedKvsTestProcess $owned $expectedStart}catch{$caught=$_.Exception.Message}
if(-not $caught.StartsWith('KV_TEST_CLEANUP_PROCESS_IDENTITY_CHANGED') -or $script:killed){throw 'Cleanup accepted a reused PID'}
$results.Add(@{name='cleanup_rejects_reused_pid';ok=$true})
$script:mode='exited'
if((Stop-OwnedKvsTestProcess $owned $expectedStart) -ne 'already_exited' -or $script:killed){throw 'Cleanup should ignore the exited process'}
$results.Add(@{name='cleanup_ignores_exited_process';ok=$true})
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
@{ok=$true;ui_started=$false;process_operations='mocked';tests=@($results)}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) mocked harness lifecycle tests."
