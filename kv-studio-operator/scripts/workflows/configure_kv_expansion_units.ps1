param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][ValidateSet('KV-B16X','KV-C32X')][string[]]$Models,
  [string]$OutDir = '',
  [int]$PerModuleBudgetSeconds = 10
)
$ErrorActionPreference='Stop'
$scriptsRoot=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$child=Join-Path $scriptsRoot 'runner_children\configure_expansion_units_guarded.ps1'
$childArgs = @{
  ProjectPath = $ProjectPath
  Models = @($Models)
  PerModuleBudgetSeconds = $PerModuleBudgetSeconds
}
if (-not [string]::IsNullOrWhiteSpace($OutDir)) { $childArgs.OutDir = $OutDir }
& $child @childArgs
