param(
  [Parameter(Mandatory=$true)]
  [string]$LocalScriptPath,

  [Parameter(Mandatory=$true)]
  [string]$VmScriptPath,

  [string]$Api = 'http://127.0.0.1:8875',
  [string]$PveSsh = 'root@192.168.1.221',
  [int]$PveSshPort = 22,
  [string]$HolderId = 'codex-official-repro-103',
  [int]$TimeoutSeconds = 120
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

$resolved = Resolve-Path -LiteralPath $LocalScriptPath
$bytes = [IO.File]::ReadAllBytes($resolved)
if ($bytes.Length -gt 120KB) {
  throw "Script is $($bytes.Length) bytes. Use a staged transfer mechanism for larger files."
}

$payload = [Convert]::ToBase64String($bytes)
$escapedVmScriptPath = $VmScriptPath.Replace("'", "''")
$chunkSize = 700
$chunks = [System.Collections.Generic.List[string]]::new()
for ($offset = 0; $offset -lt $payload.Length; $offset += $chunkSize) {
  $length = [Math]::Min($chunkSize, $payload.Length - $offset)
  $chunks.Add($payload.Substring($offset, $length))
}

$tempB64Path = "$VmScriptPath.b64"
$escapedTempB64Path = $tempB64Path.Replace("'", "''")

function Invoke-VmPowerShell {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Command
  )

  $argsList = @(
    $helper,
    '--api', $Api,
    '--pve-ssh', $PveSsh,
    '--pve-ssh-port', [string]$PveSshPort,
    'ps',
    '--vmid', '103',
    '--holder-id', $HolderId,
    '--require-reserved',
    '--timeout-seconds', [string]$TimeoutSeconds,
    '--',
    $Command
  )

  & $pythonExe @argsList
  if ($LASTEXITCODE -ne 0) {
    throw "VM PowerShell command failed with exit code $LASTEXITCODE"
  }
}

$initCommand = "`$target='$escapedVmScriptPath'; `$b64='$escapedTempB64Path'; `$dir=Split-Path -Parent `$target; New-Item -ItemType Directory -Force -Path `$dir | Out-Null; Set-Content -LiteralPath `$b64 -Value '' -Encoding ASCII; Write-Output 'INIT OK'"
Invoke-VmPowerShell -Command $initCommand

for ($index = 0; $index -lt $chunks.Count; $index++) {
  $chunk = $chunks[$index]
  $appendCommand = "`$b64='$escapedTempB64Path'; Add-Content -LiteralPath `$b64 -Value '$chunk' -Encoding ASCII; Write-Output 'CHUNK $($index + 1)/$($chunks.Count)'"
  Invoke-VmPowerShell -Command $appendCommand
}

$finalCommand = "`$target='$escapedVmScriptPath'; `$b64='$escapedTempB64Path'; `$payload=(Get-Content -LiteralPath `$b64 -Raw) -replace '\s',''; `$bytes=[Convert]::FromBase64String(`$payload); [IO.File]::WriteAllBytes(`$target,`$bytes); Remove-Item -LiteralPath `$b64 -Force; Write-Output `"WROTE `$target bytes=`$(`$bytes.Length)`""
Invoke-VmPowerShell -Command $finalCommand
