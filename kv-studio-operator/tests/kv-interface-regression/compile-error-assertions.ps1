function Read-KvCompileTestEvidence([string]$Path,[datetime]$StartedUtc) {
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).LastWriteTimeUtc -lt $StartedUtc){throw "KV_TEST_NG_EVIDENCE_MISSING_OR_STALE: $Path"}
  return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-KvCompileDiagnosticLines([string]$Text) {
  return @($Text -split '\r?\n' | ForEach-Object {$_.Trim()} | Where-Object {$_})
}

function Assert-KvCompileDiagnosticText([string]$Actual,[string]$Expected) {
  $resultLabel=-join([char[]]@(0x8F6C,0x6362,0x7ED3,0x679C))
  $errorLabel=-join([char[]]@(0x9519,0x8BEF))
  $warningLabel=-join([char[]]@(0x8B66,0x544A))
  $countLabel=-join([char[]]@(0x6570,0x91CF))
  $lines=@(Get-KvCompileDiagnosticLines $Actual)
  $expectedLines=@(Get-KvCompileDiagnosticLines $Expected)
  $header='^'+$resultLabel+' NG \('+ $errorLabel+$countLabel+':(?<errors>\d+)\s+'+$warningLabel+$countLabel+':(?<warnings>\d+)\)$'
  if(-not $lines.Count -or $lines[0] -notmatch $header){throw 'KV_TEST_NG_HEADER_INVALID'}
  $errorCount=[int]$Matches.errors;$warningCount=[int]$Matches.warnings
  $errors=@($lines | Where-Object {$_ -match ('\['+$errorLabel+'\s*\d+\]:')})
  $warnings=@($lines | Where-Object {$_ -match ('\['+$warningLabel+'\s*\d+\]:')})
  if($errorCount -lt 1 -or $errors.Count -ne $errorCount -or $warnings.Count -ne $warningCount -or $lines.Count -ne (1+$errorCount+$warningCount)){throw 'KV_TEST_NG_DIAGNOSTICS_INCOMPLETE'}
  if($lines.Count -ne $expectedLines.Count){throw 'KV_TEST_NG_EXPECTED_COUNT_MISMATCH'}
  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -cne $expectedLines[$i]){throw "KV_TEST_NG_DIAGNOSTIC_MISMATCH: line $($i+1)"}
  }
  return [pscustomobject]@{error_count=$errorCount;warning_count=$warningCount;line_count=$lines.Count;diagnostics=$lines}
}

function Assert-KvExpectedCompileFailure([string]$WorkflowDirectory,[string]$ProjectPath,[string]$ExpectedTextPath,[datetime]$StartedUtc,[int]$ExitCode) {
  if($ExitCode -ne 1){throw 'KV_TEST_NG_EXIT_CODE_MISMATCH'}
  $workflowPath=Join-Path $WorkflowDirectory 'workflow_result.json'
  $workflow=Read-KvCompileTestEvidence $workflowPath $StartedUtc
  if($workflow.ok -isnot [bool] -or $workflow.ok -or $workflow.status -ne 'fail' -or $workflow.error_code -ne 'KV_COMPILE_RESULT_NG' -or $workflow.current_step -ne 'copy_compile_result' -or -not $workflow.run_id -or $workflow.code_sha256 -notmatch '^[0-9A-Fa-f]{64}$'){throw 'KV_TEST_NG_WORKFLOW_MISMATCH'}
  if(-not $workflow.project_path -or [IO.Path]::GetFullPath($workflow.project_path) -ine [IO.Path]::GetFullPath($ProjectPath)){throw 'KV_TEST_NG_PROJECT_MISMATCH'}
  foreach($flag in @('compile_acceptance_required','compile_result_contains_ng')){if($workflow.$flag -isnot [bool] -or -not $workflow.$flag){throw 'KV_TEST_NG_WORKFLOW_FLAGS'}}
  if($workflow.compile_result_contains_ok -isnot [bool] -or $workflow.compile_result_contains_ok){throw 'KV_TEST_NG_WORKFLOW_FLAGS'}
  $steps=@($workflow.steps)
  if($steps.Count -ne 4 -or (@($steps.name) -join ',') -cne 'assert_ui_guard_usage,assert_agent_boundary,compile,copy_compile_result' -or @($steps[0..2]|Where-Object {$_.exit_code -ne 0}).Count -or $steps[3].exit_code -ne 1){throw 'KV_TEST_NG_STEP_SEQUENCE'}
  $evidencePaths=@($workflowPath)
  $compileFinishedUtc=$StartedUtc
  foreach($name in @('compile','compile_result')){
    $directory=Join-Path $WorkflowDirectory ('artifacts/'+$name)
    $receiptPath=Join-Path $directory 'step_receipt.json'
    $receipt=Read-KvCompileTestEvidence $receiptPath $StartedUtc
    $stepName=if($name -eq 'compile'){'compile'}else{'copy_compile_result'}
    $scriptName=if($name -eq 'compile'){'compile_and_copy_result_bounded.ps1'}else{'copy_convert_result_from_tree_handle.ps1'}
    $expectedOk=$name -eq 'compile'
    $expectedExit=if($expectedOk){0}else{1}
    if($receipt.run_id -cne $workflow.run_id -or $receipt.code_sha256 -cne $workflow.code_sha256 -or $receipt.step -cne $stepName -or $receipt.ok -isnot [bool] -or $receipt.ok -ne $expectedOk -or $receipt.exit_code -ne $expectedExit -or [IO.Path]::GetFileName($receipt.script) -cne $scriptName){throw 'KV_TEST_NG_RECEIPT_MISMATCH'}
    if(-not $receipt.parameters.ProjectPath -or [IO.Path]::GetFullPath($receipt.parameters.ProjectPath) -ine [IO.Path]::GetFullPath($ProjectPath)){throw 'KV_TEST_NG_RECEIPT_PROJECT_MISMATCH'}
    $stepStart=[datetime]::Parse($receipt.started_utc).ToUniversalTime()
    if($stepStart -lt $StartedUtc -or $stepStart -lt $compileFinishedUtc){throw 'KV_TEST_NG_RECEIPT_STALE'}
    $childPath=Join-Path $directory 'result.json'
    $child=Read-KvCompileTestEvidence $childPath $stepStart
    if($child.ok -isnot [bool] -or $child.ok -ne $expectedOk){throw 'KV_TEST_NG_CHILD_RESULT_MISMATCH'}
    $evidencePaths+=@($receiptPath,$childPath)
    if($expectedOk){$compileFinishedUtc=(Get-Item -LiteralPath $childPath).LastWriteTimeUtc;continue}
    if($child.error_code -cne 'KV_COMPILE_RESULT_NG' -or $child.contains_ng -isnot [bool] -or -not $child.contains_ng -or $child.contains_ok -isnot [bool] -or $child.contains_ok){throw 'KV_TEST_NG_COPY_RESULT_MISMATCH'}
    $textPath=Join-Path $directory 'compile_result_copied.txt'
    foreach($reportedPath in @($child.compile_result_path,$workflow.compile_result_path)){
      if(-not $reportedPath -or [IO.Path]::GetFullPath($reportedPath) -ine [IO.Path]::GetFullPath($textPath)){throw 'KV_TEST_NG_TEXT_OWNERSHIP'}
    }
    if(-not(Test-Path -LiteralPath $textPath -PathType Leaf) -or (Get-Item -LiteralPath $textPath).LastWriteTimeUtc -lt $stepStart){throw 'KV_TEST_NG_TEXT_MISSING_OR_STALE'}
    $actual=[IO.File]::ReadAllText($textPath,[Text.Encoding]::UTF8)
    $expected=[IO.File]::ReadAllText($ExpectedTextPath,[Text.Encoding]::UTF8)
    $diagnostics=Assert-KvCompileDiagnosticText $actual $expected
    if($child.line_count -ne $diagnostics.line_count -or $workflow.compile_result_length -ne $actual.Length){throw 'KV_TEST_NG_TEXT_LENGTH_MISMATCH'}
    $evidencePaths+=$textPath
  }
  return [pscustomobject]@{ok=$true;expected_outcome='compile_error';workflow_ok=$false;error_code='KV_COMPILE_RESULT_NG';run_id=$workflow.run_id;error_count=$diagnostics.error_count;warning_count=$diagnostics.warning_count;diagnostics=$diagnostics.diagnostics;expected_text_sha256=(Get-FileHash -LiteralPath $ExpectedTextPath -Algorithm SHA256).Hash;evidence=@($evidencePaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}})}
}
