param(
  [string]$WorkRoot = '',
  [switch]$IncludeLive,
  [string[]]$Only = @()
)

$ErrorActionPreference = 'Stop'

# Runs the offline test suites (and optionally the live ones) and aggregates the
# per-suite test_result.json. Exit 0 only when every executed suite passes; a
# skipped suite never counts as passed, and a missing/stale result is a failure.

$testsRoot = $PSScriptRoot
if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-tests-' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$offline = @(
  'compile-triage',
  'module-completion',
  'variable-dependencies',
  'plan-runner',
  'inventory-expansion',
  'clone-readiness',
  'ethercat-guard-contract',
  'script-hygiene',
  'eip-snapshot',
  'eip-write-contract',
  'variable-usage',
  'scan-order',
  'variable-attributes',
  'scaffold-variable-attributes',
  'library-dependencies',
  'system-layout'
)
$live = @(
  'axis-rename-live',
  'ethercat-node-live',
  'eip-snapshot-live',
  'eip-live-cycle'
)
$suites = @($offline)
if ($IncludeLive) { $suites += $live }
if ($Only.Count -gt 0) { $suites = @($suites | Where-Object { $Only -contains $_ }) }
if ($suites.Count -eq 0) {
  Write-Host 'KV_TESTS: no suite selected (check -Only)'
  exit 41
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($suite in $suites) {
  $runScript = Join-Path $testsRoot (Join-Path $suite 'run.ps1')
  if (-not (Test-Path -LiteralPath $runScript -PathType Leaf)) {
    $results.Add([pscustomobject]@{ suite = $suite; status = 'missing'; exit = $null; passed = 0; failed = 0; detail = $runScript })
    continue
  }
  $suiteRoot = Join-Path $WorkRoot $suite
  New-Item -ItemType Directory -Force -Path $suiteRoot | Out-Null
  $stdout = Join-Path $suiteRoot 'stdout.txt'
  $stderr = Join-Path $suiteRoot 'stderr.txt'
  $suiteStarted = Get-Date
  $process = Start-Process -FilePath 'powershell' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runScript, '-WorkRoot', $suiteRoot) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
  $exited = $process.WaitForExit(600000)
  if (-not $exited) {
    try { $process.Kill($true) } catch {}
    $results.Add([pscustomobject]@{ suite = $suite; status = 'timeout'; exit = $null; passed = 0; failed = 0; detail = 'exceeded 600s and was killed' })
    continue
  }
  $process.Refresh()
  $exitCode = [int]$process.ExitCode
  $reportPath = Join-Path $suiteRoot 'test_result.json'
  $passed = 0
  $failed = 0
  $detail = ''
  $status = 'fail'
  if (Test-Path -LiteralPath $reportPath) {
    $fresh = (Get-Item -LiteralPath $reportPath).LastWriteTime -ge $suiteStarted.AddSeconds(-2)
    if (-not $fresh) {
      $detail = 'stale-result'
    } else {
      $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $passed = [int]$report.passed
      $failed = [int]$report.failed
      $skipped = ($report.PSObject.Properties.Name -contains 'skipped') -and [bool]$report.skipped
      if ($skipped) {
        $status = 'skip'
        $passed = 0
        $detail = 'skipped'
      } elseif ($exitCode -eq 0 -and $failed -eq 0) {
        $status = 'pass'
      } else {
        $status = 'fail'
      }
    }
  } else {
    # Legacy suites print "Cases: N  Passed: N  Failed: N" instead of JSON.
    $text = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw -Encoding UTF8 } else { '' }
    $match = [regex]::Match($text, 'Passed:\s*(\d+)\s+Failed:\s*(\d+)')
    if ($match.Success) {
      $passed = [int]$match.Groups[1].Value
      $failed = [int]$match.Groups[2].Value
      $detail = 'stdout-summary'
      if ($exitCode -eq 0 -and $failed -eq 0) { $status = 'pass' } else { $status = 'fail' }
    } elseif ($exitCode -eq 0) {
      $status = 'no-evidence'
      $detail = 'no-summary'
    } else {
      $status = 'fail'
      $detail = 'no-result'
    }
  }
  $results.Add([pscustomobject]@{ suite = $suite; status = $status; exit = $exitCode; passed = $passed; failed = $failed; detail = $detail })
}

$failures = @($results | Where-Object { $_.status -in @('fail', 'timeout', 'no-evidence', 'missing') })
$skips = @($results | Where-Object { $_.status -eq 'skip' })
$summary = [ordered]@{
  ok = ($failures.Count -eq 0 -and $results.Count -gt 0)
  include_live = [bool]$IncludeLive
  suites_total = $results.Count
  suites_passed = @($results | Where-Object { $_.status -eq 'pass' }).Count
  suites_failed = $failures.Count
  suites_skipped = $skips.Count
  cases_passed = (@($results | ForEach-Object { $_.passed }) | Measure-Object -Sum).Sum
  cases_failed = (@($results | ForEach-Object { $_.failed }) | Measure-Object -Sum).Sum
  suites = $results.ToArray()
  work_root = $WorkRoot
  generated_at = (Get-Date).ToString('o')
}
$summaryPath = Join-Path $WorkRoot 'test_run_all_result.json'
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 4
Write-Host ("KV_TESTS: suites={0} passed={1} failed={2} skipped={3} cases_passed={4} cases_failed={5}" -f $summary.suites_total, $summary.suites_passed, $summary.suites_failed, $summary.suites_skipped, $summary.cases_passed, $summary.cases_failed)
if ($failures.Count -gt 0) { exit 41 }
exit 0
