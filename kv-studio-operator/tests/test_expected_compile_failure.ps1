param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'kv-interface-regression/compile-error-assertions.ps1')
$expectedPath=Join-Path $PSScriptRoot 'kv-interface-regression/19_compile_error/fixtures/expected_compile_result.txt'
$expected=[IO.File]::ReadAllText($expectedPath,[Text.Encoding]::UTF8)
$records=@()
$cases=@('valid','ordinary_failure','unexpected_success','missing_text','stale_text','header_only','missing_error','wrong_module','wrong_st_line','wrong_message','wrong_warning','wrong_run_id','wrong_code_hash','wrong_project','wrong_copy_project','stale_receipt','wrong_step_order','wrong_text_path','no_compile','copy_failure','wrong_exit')
foreach($case in $cases){
  $root=Join-Path $OutDir $case
  $compileDir=Join-Path $root 'artifacts/compile';$copyDir=Join-Path $root 'artifacts/compile_result'
  $null=New-Item -ItemType Directory -Path $compileDir,$copyDir -Force
  $started=[datetime]::UtcNow.AddSeconds(-5);$stepStarted=$started.AddSeconds(1)
  $project=Join-Path $root 'Expected.kpr';$textPath=Join-Path $copyDir 'compile_result_copied.txt'
  $hash='A'*64
  $compileReceipt=@{run_id='current-run';code_sha256=$hash;step='compile';ok=$true;exit_code=0;script='compile_and_copy_result_bounded.ps1';parameters=@{ProjectPath=$project};started_utc=$stepStarted.ToString('o')}
  $copyReceipt=@{run_id='current-run';code_sha256=$hash;step='copy_compile_result';ok=$false;exit_code=1;script='copy_convert_result_from_tree_handle.ps1';parameters=@{ProjectPath=$project};started_utc=$started.AddSeconds(3).ToString('o')}
  $child=@{ok=$false;error_code='KV_COMPILE_RESULT_NG';contains_ok=$false;contains_ng=$true;compile_result_path=$textPath;line_count=9}
  $workflow=@{ok=$false;status='fail';error_code='KV_COMPILE_RESULT_NG';current_step='copy_compile_result';run_id='current-run';code_sha256=$hash;project_path=$project;compile_acceptance_required=$true;compile_result_contains_ng=$true;compile_result_contains_ok=$false;compile_result_path=$textPath;compile_result_length=$expected.Length;steps=@(@{name='assert_ui_guard_usage';exit_code=0},@{name='assert_agent_boundary';exit_code=0},@{name='compile';exit_code=0},@{name='copy_compile_result';exit_code=1})}
  $text=$expected;$exitCode=1
  switch($case){
    'ordinary_failure' {$workflow.error_code='KV_FLAT_WORKFLOW_STEP_TIMEOUT'}
    'unexpected_success' {$workflow.ok=$true;$workflow.status='pass'}
    'header_only' {$text=($expected -split '\r?\n')[0]}
    'missing_error' {$text=(@($expected -split '\r?\n')|Where-Object {$_ -notmatch 'ST.*0010'}) -join "`n"}
    'wrong_module' {$text=$text.Replace('ColdScaleCallerSaved','OtherModule')}
    'wrong_st_line' {$text=$text.Replace('0007','0008')}
    'wrong_message' {$text=$text.Replace('Sum => ScaledSum','Sum => OtherOutput')}
    'wrong_warning' {$text=$text.Replace('ENDH','END')}
    'wrong_run_id' {$copyReceipt.run_id='old-run'}
    'wrong_code_hash' {$copyReceipt.code_sha256='B'*64}
    'wrong_project' {$workflow.project_path=Join-Path $root 'Other.kpr'}
    'wrong_copy_project' {$copyReceipt.parameters.ProjectPath=Join-Path $root 'Other.kpr'}
    'stale_receipt' {$copyReceipt.started_utc=$started.AddSeconds(-1).ToString('o')}
    'wrong_step_order' {$workflow.steps=@($workflow.steps[0],$workflow.steps[1],$workflow.steps[3],$workflow.steps[2])}
    'wrong_text_path' {$child.compile_result_path=Join-Path $OutDir 'old.txt'}
    'no_compile' {$compileReceipt.ok=$false;$compileReceipt.exit_code=1}
    'copy_failure' {$child.error_code='KV_COMPILE_RESULT_READBACK_FAILED'}
    'wrong_exit' {$exitCode=2}
  }
  $workflow|ConvertTo-Json -Depth 8|Set-Content (Join-Path $root 'workflow_result.json') -Encoding UTF8
  $compileReceipt|ConvertTo-Json -Depth 5|Set-Content (Join-Path $compileDir 'step_receipt.json') -Encoding UTF8
  @{ok=$true}|ConvertTo-Json|Set-Content (Join-Path $compileDir 'result.json') -Encoding UTF8
  (Get-Item (Join-Path $compileDir 'result.json')).LastWriteTimeUtc=$started.AddSeconds(2)
  $copyReceipt|ConvertTo-Json -Depth 5|Set-Content (Join-Path $copyDir 'step_receipt.json') -Encoding UTF8
  $child|ConvertTo-Json|Set-Content (Join-Path $copyDir 'result.json') -Encoding UTF8
  if($case -ne 'missing_text'){[IO.File]::WriteAllText($textPath,$text,[Text.Encoding]::UTF8)}
  if($case -eq 'stale_text'){(Get-Item $textPath).LastWriteTimeUtc=$started.AddSeconds(-1)}
  $accepted=$false;$errorCode=''
  try{$result=Assert-KvExpectedCompileFailure $root $project $expectedPath $started $exitCode;$accepted=$result.ok}
  catch{$errorCode=$_.Exception.Message}
  if($accepted -ne ($case -eq 'valid')){throw "Incorrect negative-test acceptance: $case accepted=$accepted $errorCode"}
  $records+=@{case=$case;ok=$true;accepted=$accepted;observed_error=$errorCode}
}
@{ok=$true;ui_started=$false;tests=$records}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($records.Count) expected-compile-failure evidence checks."
