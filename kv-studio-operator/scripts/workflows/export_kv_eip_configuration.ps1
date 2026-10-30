param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$ProjectName = '',
  [switch]$PlanOnly
)
# Read-only export of the EtherNet/IP 设定列表 (device IP column + raw table).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if (-not $ProjectName) { $ProjectName = [IO.Path]::GetFileNameWithoutExtension($ProjectPath) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$runner = Join-Path $root 'runner_children\configure_eip_devices_guarded.ps1'
$configurationPath = Join-Path $OutDir 'eip_configuration.json'
$resultPath = Join-Path $OutDir 'eip_configuration_result.json'
$exitCode = 0
$errorText = ''
if (-not $PlanOnly) {
  $process = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
  $needle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  if (-not $process -or $process.MainWindowTitle -notlike "*$needle*") { throw "KV_EIP_PROJECT_NOT_OPEN: $ProjectPath" }
  & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -ProjectName $ProjectName -ProjectPath $ProjectPath -OutDir $OutDir -ReadConfigurationOnly -ConfigurationOutPath $configurationPath 1> (Join-Path $OutDir 'eip_read_stdout.txt') 2> (Join-Path $OutDir 'eip_read_stderr.txt')
  if ($LASTEXITCODE -is [int]) { $exitCode = [int]$LASTEXITCODE }
  if ($exitCode -ne 0) { $errorText = ((Get-Content -LiteralPath (Join-Path $OutDir 'eip_read_stderr.txt') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + ' ' + (Get-Content -LiteralPath (Join-Path $OutDir 'eip_read_stdout.txt') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)).Trim() }
}
$configuration = $null
if (Test-Path -LiteralPath $configurationPath -PathType Leaf) { try { $configuration = Get-Content -Raw -LiteralPath $configurationPath -Encoding UTF8 | ConvertFrom-Json } catch {} }
# Leave no modal/window behind for the next snapshot stage.
try {
  . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'scripts\kv_dialog_post.ps1')
  $kvs = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
  if ($kvs) {
    foreach ($w in @(Get-KvTopWindow -ProcessId $kvs.Id -VisibleOnly)) {
      if ($w.Title -notlike '*EtherNet/IP*') { continue }
      foreach ($row in @([KvDlgPost]::ChildButtons($w.Hwnd))) {
        $parts = $row -split [char]1
        if ($parts[2] -eq '取消') { [void][KvDlgPost]::Click([IntPtr][long]$parts[0]); Start-Sleep -Milliseconds 800; break }
      }
    }
  }
} catch {}

$result = [ordered]@{
  ok = ($exitCode -eq 0 -and $configuration -and $configuration.ok -eq $true)
  planned = [bool]$PlanOnly
  project_path = $ProjectPath
  configuration_path = $configurationPath
  row_count = if ($configuration) { [int]$configuration.row_count } else { 0 }
  ip_count = if ($configuration) { [int]$configuration.ip_count } else { 0 }
  ips = if ($configuration) { @($configuration.ips) } else { @() }
  raw_table = if ($configuration) { [string]$configuration.raw_table } else { '' }
  exit_code = $exitCode
  error = $errorText
}
if ($PlanOnly) { $result.ok = $true }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$result | ConvertTo-Json -Depth 4
if ($result.ok) { exit 0 }
exit 1
