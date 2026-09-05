param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectName,
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,
  [Parameter(Mandatory=$true)]
  [string]$NodesConfigPath,
  [Parameter(Mandatory=$true)]
  [string]$OutDir
)

$ErrorActionPreference='Stop'
$runner=Join-Path (Split-Path -Parent $PSScriptRoot) 'runner_children\configure_ethercat_nodes_guarded.ps1'
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "KV_ETHERCAT_RUNNER_NOT_FOUND: $runner"}
& $runner -ProjectName $ProjectName -ProjectPath $ProjectPath -NodesConfigPath $NodesConfigPath -OutDir $OutDir
if($null-ne$LASTEXITCODE -and $LASTEXITCODE-ne0){exit $LASTEXITCODE}
