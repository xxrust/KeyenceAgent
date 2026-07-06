& (Join-Path $PSScriptRoot 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'run_kv_mvp_scaffold.ps1' -TargetClasses @('customer_workflow') @args
exit $LASTEXITCODE
