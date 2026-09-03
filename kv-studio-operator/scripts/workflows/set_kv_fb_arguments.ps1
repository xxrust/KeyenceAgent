param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$FbModuleName,
  [Parameter(Mandatory=$true)][string]$ArgumentsTsv,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$ChecklistPath = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$child = Join-Path $scriptRoot 'runner_children\set_fb_arguments_guarded.ps1'
if (-not (Test-Path -LiteralPath $child -PathType Leaf)) { throw "FB argument runner child not found: $child" }

$childParams = @{
  ProjectPath = $ProjectPath
  FbModuleName = $FbModuleName
  ArgumentsTsv = $ArgumentsTsv
  OutDir = $OutDir
}
if ($ChecklistPath) { $childParams.ChecklistPath = $ChecklistPath }
& $child @childParams
exit $LASTEXITCODE
