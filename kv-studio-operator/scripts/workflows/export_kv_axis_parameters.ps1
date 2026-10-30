param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 300,
  [switch]$PlanOnly
)
# Read-only dump of the motion axis control table (行列定位, 不写值, 不保存).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$runner = Resolve-KvStudioOperatorScriptPath -ScriptRoot $root -Name 'runner_children/axis_parameters_guarded.ps1' -Classes runner_child_approved
$tsv = Join-Path $OutDir 'axes_params.tsv'
$resultPath = Join-Path $OutDir 'axis_parameters_result.json'
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
  if (-not $process) { throw "KV_AXIS_PROJECT_NOT_OPEN: $ProjectPath" }
  $stdout = Join-Path $OutDir 'axis_parameters_stdout.txt'
  $stderr = Join-Path $OutDir 'axis_parameters_stderr.txt'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -OutDir $OutDir -Mode Dump -AllParams -NoSave 1> $stdout 2> $stderr
  if ($LASTEXITCODE -is [int]) { $exitCode = [int]$LASTEXITCODE }
  if ($exitCode -ne 0) { $errorText = ((Get-Content -LiteralPath $stderr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + ' ' + (Get-Content -LiteralPath $stdout -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)).Trim() }
}
$rows = 0
$axes = @()
if (Test-Path -LiteralPath $tsv -PathType Leaf) {
  $lines = @(Get-Content -LiteralPath $tsv -Encoding UTF8)
  if ($lines.Count -gt 1) {
    $rows = $lines.Count - 1
    $header = $lines[0] -split "`t"
    if ($header.Count -gt 4) { $axes = @($header[4..($header.Count - 1)] | Where-Object { $_ }) }
  }
}
# Leave no modal/window behind for the next snapshot stage.
try {
  . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'scripts\kv_dialog_post.ps1')
  $kvs = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
  if ($kvs) {
    foreach ($w in @(Get-KvTopWindow -ProcessId $kvs.Id -VisibleOnly)) {
      if ($w.Title -notlike '*单元编辑器*') { continue }
      foreach ($row in @([KvDlgPost]::ChildButtons($w.Hwnd))) {
        $parts = $row -split [char]1
        if ($parts[2] -eq '取消') { [void][KvDlgPost]::Click([IntPtr][long]$parts[0]); Start-Sleep -Milliseconds 800; break }
      }
    }
  }
} catch {}

$result = [ordered]@{
  ok = ($exitCode -eq 0 -and $rows -gt 0)
  planned = [bool]$PlanOnly
  project_path = $ProjectPath
  mode = 'Dump'
  tsv_path = $tsv
  row_count = $rows
  axes = $axes
  exit_code = $exitCode
  error = $errorText
}
if ($PlanOnly) { $result.ok = $true }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$result | ConvertTo-Json -Depth 4
if ($result.ok) { exit 0 }
exit 1
