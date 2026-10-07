param(
  [string]$CoveragePath = (Join-Path $PSScriptRoot 'kv-interface-regression/atomic-operation-coverage.html')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $CoveragePath -PathType Leaf)) { throw "Coverage page missing: $CoveragePath" }
$html = Get-Content -Raw -LiteralPath $CoveragePath -Encoding UTF8
$scenarioRoot = Join-Path $PSScriptRoot 'kv-interface-regression'
$directories = @(Get-ChildItem -LiteralPath $scenarioRoot -Directory | Where-Object { $_.Name -match '^\d\d_' })
$scenarioRows = @([regex]::Matches($html, "S\('([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$missing = @($directories | Where-Object { $_.Name -notin $scenarioRows } | ForEach-Object { $_.Name })
$extra = @($scenarioRows | Where-Object { -not (Test-Path -LiteralPath (Join-Path $scenarioRoot $_) -PathType Container) })
if ($missing.Count -or $extra.Count -or $scenarioRows.Count -ne (@($scenarioRows | Sort-Object -Unique).Count)) {
  throw "Coverage scenario mismatch: missing=$($missing -join ','); extra=$($extra -join ',')"
}
$operationIds = @([regex]::Matches($html, "O\('([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$duplicateOperations = @($operationIds | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
if ($duplicateOperations.Count) { throw "Duplicate operation IDs: $($duplicateOperations -join ',')" }
$references = @([regex]::Matches($html, "'([A-Z]+-[0-9]{2})'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$unknown = @($references | Where-Object { $_ -notin $operationIds })
if ($unknown.Count) { throw "Unknown operation references: $($unknown -join ',')" }
[ordered]@{
  ok = $true
  scenario_count = $scenarioRows.Count
  operation_count = $operationIds.Count
  coverage_path = [IO.Path]::GetFullPath($CoveragePath)
} | ConvertTo-Json -Depth 4
"Passed atomic-operation coverage consistency checks."
