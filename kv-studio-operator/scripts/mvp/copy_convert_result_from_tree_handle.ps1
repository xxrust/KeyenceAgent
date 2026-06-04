& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'copy_convert_result_from_tree_handle.ps1' -TargetClasses @('runner_child_approved') @args
exit $LASTEXITCODE
