& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'set_fb_arguments_guarded.ps1' -TargetClasses @('runner_child_pending') @args
exit $LASTEXITCODE
