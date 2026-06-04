& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'probe_file_menu_coordinate.ps1' -TargetClasses @('probe_research') @args
exit $LASTEXITCODE
