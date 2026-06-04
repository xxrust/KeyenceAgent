& (Join-Path $PSScriptRoot 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'assert_kv_mvp_ui_guard_usage.ps1' -TargetClasses @('gate') @args
exit $LASTEXITCODE
