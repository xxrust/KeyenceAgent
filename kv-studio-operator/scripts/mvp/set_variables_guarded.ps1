& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'set_variables_guarded.ps1' -TargetClasses @('runner_child_approved') @args
exit $LASTEXITCODE
