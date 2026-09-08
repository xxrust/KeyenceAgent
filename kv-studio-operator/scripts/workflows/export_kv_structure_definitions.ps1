param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string[]]$StructureName = @()
)
$ErrorActionPreference='Stop'
$scriptRoot=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$child=Join-Path $scriptRoot 'runner_children\export_structure_definitions_guarded.ps1'
if(-not(Test-Path -LiteralPath $child -PathType Leaf)){throw "Structure extraction runner child not found: $child"}
& $child -ProjectPath $ProjectPath -OutDir $OutDir -StructureName $StructureName
exit $LASTEXITCODE
