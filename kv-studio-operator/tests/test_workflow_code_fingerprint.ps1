param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$scripts=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
. (Join-Path $scripts 'workflow_tools/kv_step_evidence.ps1')
$null=New-Item -ItemType Directory -Force -Path $OutDir
$rows=@()
foreach($case in @('unchanged','content_same_size_timestamp','added_script','deleted_script','noncode_artifact','missing_fingerprint')){
  $fixture=Join-Path $OutDir $case
  $null=New-Item -ItemType Directory -Force -Path $fixture
  $scriptFile=Join-Path $fixture 'entry.ps1'
  [IO.File]::WriteAllText($scriptFile,'return 1')
  [IO.File]::WriteAllText((Join-Path $fixture 'manifest.json'),'{"version":1}')
  $expected=Get-KvCodeFingerprint $fixture
  switch($case){
    'content_same_size_timestamp' {$time=(Get-Item -LiteralPath $scriptFile).LastWriteTimeUtc;[IO.File]::WriteAllText($scriptFile,'return 2');(Get-Item -LiteralPath $scriptFile).LastWriteTimeUtc=$time}
    'added_script' {[IO.File]::WriteAllText((Join-Path $fixture 'extra.ps1'),'return 2')}
    'deleted_script' {Remove-Item -LiteralPath $scriptFile}
    'noncode_artifact' {[IO.File]::WriteAllText((Join-Path $fixture 'trace.txt'),'diagnostic evidence')}
    'missing_fingerprint' {$expected=$null}
  }
  $failure='';try{Assert-KvCodeUnchanged $fixture $expected}catch{$failure=$_.Exception.Message}
  $shouldPass=$case -in @('unchanged','noncode_artifact')
  if(([string]::IsNullOrEmpty($failure)) -ne $shouldPass -or (-not $shouldPass -and $failure -notlike 'KV_WORKFLOW_CODE_CHANGED:*')){throw "Unexpected fingerprint result: $case $failure"}
  $rows+=@{case=$case;ok=$true;observed_error=$failure}
}
$executor=Get-Content -LiteralPath (Join-Path $scripts 'workflow_tools/invoke_kv_flat_execution_plan.ps1') -Raw -Encoding UTF8
if([regex]::Matches($executor,'(?m)^\s+Assert-KvCodeUnchanged \$scriptRoot \$script:codeFingerprint\s*$').Count -ne 2){throw 'Executor must check code before every step and final acceptance'}
@{ok=$true;ui_started=$false;tests=$rows}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($rows.Count) live file fingerprint cases"
