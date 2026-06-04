& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'import_mnm_guarded.ps1' -TargetClasses @('runner_child_approved') @args
exit $LASTEXITCODE
