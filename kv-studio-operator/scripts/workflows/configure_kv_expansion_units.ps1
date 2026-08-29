param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][ValidateSet('KV-B16X','KV-C32X')][string[]]$Models,
  [string]$OutDir = '',
  [int]$PerModuleBudgetSeconds = 10
)
$ErrorActionPreference='Stop'
$scriptsRoot=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$child=Join-Path $scriptsRoot 'runner_children\configure_expansion_units_guarded.ps1'
& powershell -STA -NoProfile -ExecutionPolicy Bypass -File $child -ProjectPath $ProjectPath -Models $Models -OutDir $OutDir -PerModuleBudgetSeconds $PerModuleBudgetSeconds
exit $LASTEXITCODE
