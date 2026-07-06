& (Join-Path $PSScriptRoot 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'new_kv_mvp_multi_mnm_scaffold.ps1' -TargetClasses @('customer_scaffold_tool') @args
exit $LASTEXITCODE
