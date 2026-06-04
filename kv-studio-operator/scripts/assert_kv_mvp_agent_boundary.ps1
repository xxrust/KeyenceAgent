& (Join-Path $PSScriptRoot 'Invoke-KvStudioOperatorWrapper.ps1') -TargetName 'assert_kv_mvp_agent_boundary.ps1' -TargetClasses @('gate') @args
exit $LASTEXITCODE
