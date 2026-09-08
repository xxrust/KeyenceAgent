param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$PlanPath,
  [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$child = Join-Path $root 'runner_children\mutate_structure_definitions_guarded.ps1'
if (-not (Test-Path -LiteralPath $child -PathType Leaf)) { throw "Structure mutation runner child not found: $child" }
& $child -ProjectPath $ProjectPath -PlanPath $PlanPath -OutDir $OutDir
exit $LASTEXITCODE
