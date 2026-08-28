$resolver = Join-Path $PSScriptRoot 'Resolve-KvStudioOperatorScript.ps1'; . $resolver
$root = Get-KvStudioOperatorScriptsRoot -StartPath $PSCommandPath
$target = Resolve-KvStudioOperatorScriptPath -ScriptRoot $root -Name 'assert_kv_mvp_ui_guard_usage.ps1' -Classes @('gate')
& $target @args
exit $LASTEXITCODE
