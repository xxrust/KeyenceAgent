$resolver = Join-Path $PSScriptRoot 'Resolve-KvStudioOperatorScript.ps1'; . $resolver
$root = Get-KvStudioOperatorScriptsRoot -StartPath $PSCommandPath
$target = Resolve-KvStudioOperatorScriptPath -ScriptRoot $root -Name 'new_kv_mvp_multi_mnm_scaffold.ps1' -Classes @('customer_scaffold_tool')
& $target @args
exit $LASTEXITCODE
