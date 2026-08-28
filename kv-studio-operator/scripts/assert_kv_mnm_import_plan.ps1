$resolver = Join-Path $PSScriptRoot 'Resolve-KvStudioOperatorScript.ps1'; . $resolver
$root = Get-KvStudioOperatorScriptsRoot -StartPath $PSCommandPath
$target = Resolve-KvStudioOperatorScriptPath -ScriptRoot $root -Name 'assert_kv_mnm_import_plan.ps1' -Classes @('customer_scaffold_tool')
& $target @args
exit $LASTEXITCODE
