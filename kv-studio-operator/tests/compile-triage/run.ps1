param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'

# Offline regression for parse_kv_compile_result.ps1.
# Synthetic conversion-result text reproduces the real NG formats:
#   module rows with (行:)/(ST行:) and [错误 N]:, stray quoted symbols,
#   variable-editor rows without a module, and warning rows.

$tool = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts\workflow_tools\parse_kv_compile_result.ps1'))
. (Join-Path $PSScriptRoot '..\_helpers\invoke_tool.ps1')
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "tool not found: $tool" }

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-compile-triage-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$fixture = Join-Path $WorkRoot 'conversion_result.txt'
$content = @(
  '转换结果 NG (错误数量:3 警告数量:1)',
  'IO输入(行:00004)(ST行:0003)[错误 1232]:"R001": 发现非法的字符串。',
  'IO输入(行:00005)(ST行:0004)[错误 1232]:"R002": 发现非法的字符串。',
  '调用真空FB(行:00003)[错误 709]：重复分配 [instFB_VacSt01]',
  '[警告 33]:变量未使用'
) -join "`r`n"
[IO.File]::WriteAllText($fixture, $content, (New-Object Text.UTF8Encoding($false)))

$outDir = Join-Path $WorkRoot 'triage'
$exit = Invoke-TestTool -ScriptPath $tool -Arguments @('-ResultPath', $fixture, '-OutDir', $outDir)
$reportPath = Join-Path $outDir 'compile_triage.json'
if (-not (Test-Path -LiteralPath $reportPath)) { throw 'KV_COMPILE_TRIAGE_REPORT_MISSING' }
$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}

Add-Case 'tool exit code is 0' ($exit -eq 0) "exit=$exit"
Add-Case 'state is NG' ($report.state -eq 'NG') "state=$($report.state)"
Add-Case 'reported error count 3' ([int]$report.reported_error_count -eq 3) "reported=$($report.reported_error_count)"
Add-Case 'parsed error rows 3' ([int]$report.parsed_error_rows -eq 3) "parsed=$($report.parsed_error_rows)"
Add-Case 'parsed warning rows 1' ([int]$report.parsed_warning_rows -eq 1) "parsed=$($report.parsed_warning_rows)"
$codes = @($report.errors_by_code | ForEach-Object { [int]$_.code })
Add-Case 'code 1232 counted twice' ((@($report.errors_by_code | Where-Object { [int]$_.code -eq 1232 })[0].count -eq 2)) ($codes -join ',')
Add-Case 'code 709 present' ($codes -contains 709) ($codes -join ',')
$modules = @($report.errors_by_module | ForEach-Object { [string]$_.module })
Add-Case 'module 调用真空FB present' ($modules -contains '调用真空FB') ($modules -join ',')
$symbols = @($report.error_symbols | ForEach-Object { [string]$_ })
Add-Case 'symbols R001/R002/instFB_VacSt01' (($symbols -contains 'R001') -and ($symbols -contains 'R002') -and ($symbols -contains 'instFB_VacSt01')) ($symbols -join ',')

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'compile-triage'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0


