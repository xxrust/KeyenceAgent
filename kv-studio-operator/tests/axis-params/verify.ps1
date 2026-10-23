param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference = 'Stop'
$f = Get-ChildItem $OutDir -Recurse -File -Filter 'axis_param_batch.json' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $f) { Write-Host '  ASSERT FAIL: axis_param_batch.json missing'; exit 1 }
$j = Get-Content $f.FullName -Encoding UTF8 -Raw | ConvertFrom-Json
Write-Host ('  ok=' + $j.ok + ' jobs=' + $j.jobs + ' changed=' + $j.changed + ' diff_cells=' + $j.diff_cells)
@($j.results) | ForEach-Object { Write-Host ('    ' + $_.param + ': ' + $_.before + ' -> ' + $_.after + ' ok=' + $_.ok) }
if ($j.ok -ne $true) { Write-Host '  ASSERT FAIL: ok != true'; exit 1 }
if ([int]$j.jobs -ne 3) { Write-Host '  ASSERT FAIL: jobs != 3'; exit 1 }
if ([int]$j.changed -ne 3) { Write-Host '  ASSERT FAIL: changed != 3'; exit 1 }
if ([int]$j.diff_cells -ne 3) { Write-Host ('  ASSERT FAIL: diff_cells != 3 (' + $j.diff_cells + ')'); exit 1 }
Write-Host '  [result] PASS'
exit 0