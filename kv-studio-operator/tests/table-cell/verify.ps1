param([Parameter(Mandatory=$true)][string]$OutDir,[Parameter(Mandatory=$true)][string]$Stage)
$ErrorActionPreference = 'Stop'
$f = Get-ChildItem $OutDir -Recurse -File -Filter 'table_edit_result.json' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $f) { Write-Host '  ASSERT FAIL: table_edit_result.json missing'; exit 1 }
$j = Get-Content $f.FullName -Encoding UTF8 -Raw | ConvertFrom-Json
Write-Host ('  ok=' + $j.ok + ' row=' + $j.row + ' col=' + $j.column + ' selected=[' + $j.selected + '] diffs=' + @($j.diffs).Count)
if ($j.ok -ne $true) { Write-Host '  ASSERT FAIL: ok != true'; exit 1 }
if ([int]$j.row -ne 39) { Write-Host ('  ASSERT FAIL: row != 39 (' + $j.row + ')'); exit 1 }
if (@($j.diffs).Count -ne 1) { Write-Host ('  ASSERT FAIL: diff count != 1 (' + @($j.diffs).Count + ')'); exit 1 }
if ([int]$j.diffs[0].index -ne 39) { Write-Host ('  ASSERT FAIL: diff index != 39 (' + $j.diffs[0].index + ')'); exit 1 }
Write-Host '  [result] PASS'
exit 0