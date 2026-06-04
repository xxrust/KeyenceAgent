& (Join-Path $PSScriptRoot 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'run_kv_mvp_repair_existing_project.ps1' -TargetClasses @('customer_workflow') @args
exit $LASTEXITCODE
