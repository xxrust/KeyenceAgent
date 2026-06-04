& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'export_mnm_project_copy_default_folder.ps1' -TargetClasses @('customer_workflow') @args
exit $LASTEXITCODE
