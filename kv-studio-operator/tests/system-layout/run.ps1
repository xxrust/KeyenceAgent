param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'

# Wrapper so run_all.ps1 can execute tests/test_system_layout.ps1 as a suite.
if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-system-layout-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$layout = Join-Path (Join-Path $repoRoot 'tests') 'test_system_layout.ps1'
$layoutOk = $false
try {
  & $layout -OutDir $WorkRoot
  $layoutOk = $true
} catch {
  $layoutOk = $false
}

$layoutResult = Join-Path $WorkRoot 'test_result.json'
$passed = 0
$failed = 1
if ($layoutOk -and (Test-Path -LiteralPath $layoutResult)) {
  try {
    $r = Get-Content -LiteralPath $layoutResult -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($r.ok) { $passed = 1; $failed = 0 }
  } catch { $passed = 0; $failed = 1 }
}
$result = [ordered]@{
  test = 'system-layout'
  passed = $passed
  failed = $failed
  work_root = $WorkRoot
}
$result | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $layoutResult -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed -gt 0) { exit 41 }
exit 0
