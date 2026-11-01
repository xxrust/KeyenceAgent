param(
  [Parameter(Mandatory = $true)][int]$ProcessId,
  [Parameter(Mandatory = $true)][string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$process = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
if (-not $process) { exit 0 }
if ($process.Name -ne 'Kvs.exe' -or [string]$process.CommandLine -notlike "*$project*") {
  throw "KV_STUDIO_OWNERSHIP_MISMATCH: PID $ProcessId is not the KVS instance started for $project."
}
Stop-Process -Id $ProcessId -Force
try { Wait-Process -Id $ProcessId -Timeout 10 -ErrorAction SilentlyContinue } catch { }
