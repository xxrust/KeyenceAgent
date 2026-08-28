param([Parameter(ValueFromRemainingArguments=$true)][object[]]$RemainingArgs)
& (Join-Path $PSScriptRoot 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'run_kv_mvp_repeat.ps1' -TargetClasses @('regression_harness') -RemainingArgs $RemainingArgs
exit $LASTEXITCODE
