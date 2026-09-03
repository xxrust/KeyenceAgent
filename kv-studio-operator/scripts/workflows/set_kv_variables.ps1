param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$GlobalVariablesTsv,
  [Parameter(Mandatory=$true)][string]$LocalVariablesTsv,
  [string]$LocalProgramName = '',
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$ChecklistPath = '',
  [ValidateSet('Full','NameType')][string]$LocalPasteFormat = 'NameType',
  [ValidateSet('Replace','Append')][string]$GlobalWriteMode = 'Append',
  [string[]]$AllowedCustomDataTypes = @()
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$child = Join-Path $scriptRoot 'runner_children\set_variables_guarded.ps1'
if (-not (Test-Path -LiteralPath $child -PathType Leaf)) { throw "Variable runner child not found: $child" }

$childParams = @{
  ProjectPath = $ProjectPath
  GlobalVariablesTsv = $GlobalVariablesTsv
  LocalVariablesTsv = $LocalVariablesTsv
  LocalProgramName = $LocalProgramName
  OutDir = $OutDir
  LocalPasteFormat = $LocalPasteFormat
  AuditPersistence = $true
}
if ($ChecklistPath) { $childParams.ChecklistPath = $ChecklistPath }
if ($AllowedCustomDataTypes.Count -gt 0) { $childParams.AllowedCustomDataTypes = @($AllowedCustomDataTypes) }
# Customer API contract: successful return always includes close/reopen
# persistence evidence.  UI/debug escape hatches remain private to the child.
$childParams.AppendGlobalVariables = ($GlobalWriteMode -eq 'Append')

& $child @childParams
exit $LASTEXITCODE
