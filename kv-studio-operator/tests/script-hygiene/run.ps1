param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'

# Real check over every script in the skill: syntax parse + UTF-8 BOM encoding.
# This is the "run all scripts through the gates" suite; a single bad encoding
# fails the whole suite.

$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot '..\_helpers\invoke_tool.ps1')

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-script-hygiene-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}

$scripts = @(Get-ChildItem -LiteralPath (Join-Path $skillRoot 'scripts') -Recurse -Filter '*.ps1' -File)
Add-Case 'scripts discovered' ($scripts.Count -gt 50) "count=$($scripts.Count)"

$gate = Join-Path $skillRoot 'scripts\gates\assert_kv_script_syntax.ps1'
$outDir = Join-Path $WorkRoot 'syntax'
$exit = Invoke-TestTool -ScriptPath $gate -Arguments @('-OutDir', $outDir)
$resultPath = Join-Path $outDir 'script_syntax_result.json'
$ok = $false
$syntaxFailures = -1
$encodingFailures = -1
$checked = 0
if (Test-Path -LiteralPath $resultPath) {
  $report = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $ok = [bool]$report.ok
  $syntaxFailures = [int]$report.syntax_failure_count
  $encodingFailures = [int]$report.encoding_failure_count
  $checked = [int]$report.checked_files
}
Add-Case 'syntax gate exits 0' ($exit -eq 0) "exit=$exit"
Add-Case 'syntax gate ok' $ok "ok=$ok"
Add-Case 'no syntax failures' ($syntaxFailures -eq 0) "failures=$syntaxFailures"
Add-Case 'no encoding failures' ($encodingFailures -eq 0) "failures=$encodingFailures"
Add-Case 'checked at least every scripts-dir file' ($checked -ge $scripts.Count) "checked=$checked scripts=$($scripts.Count)"

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'script-hygiene'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0

