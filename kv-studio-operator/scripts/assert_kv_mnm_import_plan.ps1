& (Join-Path $PSScriptRoot 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'assert_kv_mnm_import_plan.ps1' -TargetClasses @('customer_scaffold_tool') @args
exit $LASTEXITCODE
