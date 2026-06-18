param(
  [Parameter(Mandatory=$true)]
  [string]$TargetName,

  [string[]]$TargetClasses = @()
)

$ErrorActionPreference = 'Stop'
$resolver = Join-Path $PSScriptRoot 'Resolve-KvStudioOperatorScript.ps1'
if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) { throw "Script resolver not found: $resolver" }
. $resolver

$scriptRoot = Get-KvStudioOperatorScriptsRoot -StartPath $PSCommandPath
$target = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name $TargetName -Classes $TargetClasses
& $target @args
exit $LASTEXITCODE
