& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'compile_and_copy_result_bounded.ps1' -TargetClasses @('runner_child_approved') @args
exit $LASTEXITCODE
