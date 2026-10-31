param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 300,
  [switch]$PlanOnly
)
# Read-only capture of the motion settings views (轴组设定 / 运动通用设定 / 点参数).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$runner = Join-Path $root 'runner_children\dump_motion_views_guarded.ps1'
$resultPath = Join-Path $OutDir 'motion_settings_result.json'
$exitCode = 0
$errorText = ''
if (-not $PlanOnly) {
  $needle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  $process = $null
  $deadline = (Get-Date).AddSeconds(5)
  do {
    $process = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$needle*" }) | Select-Object -First 1
    if ($process) { break }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  if (-not $process) {
    $byCommandLine = @()
    foreach ($candidate in @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })) {
      $commandLine = [string](Get-CimInstance Win32_Process -Filter "ProcessId=$($candidate.Id)" -ErrorAction SilentlyContinue).CommandLine
      if ($commandLine -and $commandLine -like "*$ProjectPath*") { $byCommandLine += $candidate }
    }
    if ($byCommandLine.Count -eq 1) { $process = $byCommandLine[0] }
    elseif ($byCommandLine.Count -gt 1) { throw 'KV_TARGET_PROJECT_WINDOW_AMBIGUOUS' }
  }
  if (-not $process) { throw "KV_MOTION_PROJECT_NOT_OPEN: $ProjectPath" }
  & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -OutDir $OutDir -ProjectPath $ProjectPath 1> (Join-Path $OutDir 'motion_stdout.txt') 2> (Join-Path $OutDir 'motion_stderr.txt')
  if ($LASTEXITCODE -is [int]) { $exitCode = [int]$LASTEXITCODE }
  if ($exitCode -ne 0) { $errorText = ((Get-Content -LiteralPath (Join-Path $OutDir 'motion_stderr.txt') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + ' ' + (Get-Content -LiteralPath (Join-Path $OutDir 'motion_stdout.txt') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)).Trim() }
}
$parsed = $null
if (Test-Path -LiteralPath $resultPath -PathType Leaf) { try { $parsed = Get-Content -Raw -LiteralPath $resultPath -Encoding UTF8 | ConvertFrom-Json } catch {} }
$items = if ($parsed) { @($parsed.items) } else { @() }
$result = [ordered]@{
  ok = ($exitCode -eq 0 -and @($items | Where-Object { $_.ok }).Count -gt 0)
  planned = [bool]$PlanOnly
  project_path = $ProjectPath
  item_count = @($items).Count
  ok_count = @($items | Where-Object { $_.ok }).Count
  items = $items
  exit_code = $exitCode
  error = $errorText
}
if ($PlanOnly) { $result.ok = $true }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutDir 'motion_settings_workflow_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 4
if ($result.ok) { exit 0 }
exit 1
