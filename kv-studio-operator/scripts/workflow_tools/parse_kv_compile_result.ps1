param(
  [Parameter(Mandatory=$true)][string]$ResultPath,
  [string]$OutDir = ''
)
# Offline triage for a copied KV STUDIO conversion result. Turns the NG rows
# into structured JSON so the next fix is driven by codes/symbols instead of
# re-reading the UI.
$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $ResultPath) 'compile_triage' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not (Test-Path -LiteralPath $ResultPath -PathType Leaf)) { throw "KV_COMPILE_RESULT_MISSING: $ResultPath" }
$text = [IO.File]::ReadAllText($ResultPath, [Text.Encoding]::UTF8)

$header = [regex]::Match($text, '转换结果\s*(?<state>OK|NG)\s*(?:\(错误数量:(?<errors>\d+)\s*警告数量:(?<warnings>\d+)\))?')
$state = if ($header.Success) { $header.Groups['state'].Value } else { '' }
$errorCount = if ($header.Success -and $header.Groups['errors'].Success) { [int]$header.Groups['errors'].Value } else { 0 }
$warningCount = if ($header.Success -and $header.Groups['warnings'].Success) { [int]$header.Groups['warnings'].Value } else { 0 }

$rows = New-Object System.Collections.Generic.List[object]
foreach ($line in ($text -split "`r?`n")) {
  $trimmed = $line.Trim()
  if (-not $trimmed) { continue }
  # Module(行:00003)(ST行: 0002)[错误 1232]:"...": ...
  # Module(行:00003)[错误214]：... [Symbol]
  # Module(行:00003)[警告33]:...
  $moduleName = ''
  $lineNo = 0
  $stLine = $null
  $kindValue = ''
  $codeValue = 0
  $rest = ''
  $m = [regex]::Match($trimmed, '^(?<module>[^\(]+?)\(行:(?<line>\d+)\)(?:\(ST行:\s*(?<stline>\d+)\))?\[(?<kind>错误|警告)\s*(?<code>\d+)\](?<sep>[：:])?(?<rest>.*)$')
  if ($m.Success) {
    $moduleName = $m.Groups['module'].Value.Trim()
    $lineNo = [int]$m.Groups['line'].Value
    if ($m.Groups['stline'].Success) { $stLine = [int]$m.Groups['stline'].Value }
    $kindValue = $m.Groups['kind'].Value
    $codeValue = [int]$m.Groups['code'].Value
    $rest = $m.Groups['rest'].Value.Trim()
  } else {
    # Variable-editor errors have no module/line prefix, e.g.
    #   [错误709]：... [上料2拨料]
    $m2 = [regex]::Match($trimmed, '^\[(?<kind>错误|警告)\s*(?<code>\d+)\](?<sep>[：:])?(?<rest>.*)$')
    if (-not $m2.Success) { continue }
    $moduleName = '(variable-editor)'
    $kindValue = $m2.Groups['kind'].Value
    $codeValue = [int]$m2.Groups['code'].Value
    $rest = $m2.Groups['rest'].Value.Trim()
  }
  $symbol = ''
  $symbolMatch = [regex]::Match($rest, '\[(?<symbol>[^\]]+)\]\s*$')
  if ($symbolMatch.Success) {
    $symbol = $symbolMatch.Groups['symbol'].Value.Trim()
    $rest = $rest.Substring(0, $symbolMatch.Index).Trim()
  }
  $quoted = [regex]::Match($rest, '^"(?<token>[^"]+)"')
  if (-not $symbol -and $quoted.Success) { $symbol = $quoted.Groups['token'].Value }
  $rows.Add([pscustomobject]@{
    module = $moduleName
    line = $lineNo
    st_line = $stLine
    kind = $kindValue
    code = $codeValue
    symbol = $symbol
    message = $rest
  })
}

$errors = @($rows | Where-Object { $_.kind -eq '错误' })
$warnings = @($rows | Where-Object { $_.kind -eq '警告' })
$summary = [ordered]@{
  ok = ($state -eq 'OK' -and $errors.Count -eq 0)
  state = $state
  reported_error_count = $errorCount
  reported_warning_count = $warningCount
  parsed_error_rows = $errors.Count
  parsed_warning_rows = $warnings.Count
  errors_by_code = @($errors | Group-Object code | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ code = [int]$_.Name; count = $_.Count } })
  errors_by_module = @($errors | Group-Object module | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ module = $_.Name; count = $_.Count } })
  error_symbols = @($errors | Where-Object { $_.symbol } | ForEach-Object { [string]$_.symbol } | Select-Object -Unique)
  errors = $errors
  warnings = $warnings
  source_path = $ResultPath
  generated_at = (Get-Date).ToString('o')
}
$summaryPath = Join-Path $OutDir 'compile_triage.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8
Write-Host "KV_COMPILE_TRIAGE: state=$state errors=$($errors.Count) warnings=$($warnings.Count) report=$summaryPath"
