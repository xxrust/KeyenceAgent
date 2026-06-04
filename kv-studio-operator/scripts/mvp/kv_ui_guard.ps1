$resolver = Join-Path (Split-Path -Parent $PSScriptRoot) 'Resolve-KvStudioOperatorScript.ps1'
if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) { throw "Script resolver not found: $resolver" }
. $resolver
$scriptRoot = Get-KvStudioOperatorScriptsRoot -StartPath $PSCommandPath
$target = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name 'kv_ui_guard.ps1' -Classes @('guard_library')
. $target
