& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'export_mnm_browse_default_folder_guarded.ps1' -TargetClasses @('runner_child_approved') @args
exit $LASTEXITCODE
