param(
  [Parameter(Mandatory=$true)]
  [string]$VmScriptPath,

  [string]$HolderId = 'codex-official-repro-103',
  [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'

$helper = Join-Path $env:USERPROFILE '.codex\skills\windows-vm-codex-operator\scripts\windows_vm_operator.py'
if (-not (Test-Path -LiteralPath $helper)) {
  throw "windows_vm_operator.py not found: $helper"
}

function Resolve-PythonExe {
  $command = Get-Command python -ErrorAction Stop
  if ($command.Source -notlike '*.bat') {
    return $command.Source
  }

  $pyenvPython = (& pyenv which python 2>$null)
  if ($LASTEXITCODE -eq 0 -and $pyenvPython -and (Test-Path -LiteralPath $pyenvPython)) {
    return $pyenvPython
  }

  throw "python resolves to a batch shim and real python.exe was not found: $($command.Source)"
}

$pythonExe = Resolve-PythonExe

$escapedVmScriptPath = $VmScriptPath.Replace('"', '""')
$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$escapedVmScriptPath"""

$argsList = @(
  $helper,
  'ps',
  '--vmid', '103',
  '--holder-id', $HolderId,
  '--require-reserved',
  '--timeout-seconds', [string]$TimeoutSeconds,
  '--',
  $command
)

& $pythonExe @argsList
exit $LASTEXITCODE
