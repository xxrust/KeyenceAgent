& (Join-Path $PSScriptRoot 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'validate_kv_mvp_scaffold.ps1' -TargetClasses @('customer_scaffold_tool') @args
exit $LASTEXITCODE
