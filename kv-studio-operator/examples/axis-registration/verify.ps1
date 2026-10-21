param([Parameter(Mandatory=$true)][string]$WorkDir)
$ErrorActionPreference='Stop'
$tree = Join-Path $WorkDir 'WsTreeEnv.xml'
if (-not (Test-Path $tree)) { Write-Host '  WsTreeEnv.xml missing -> FAIL'; exit 1 }
$c = Get-Content $tree -Raw -Encoding UTF8
$ax = @([regex]::Matches($c, '轴\d+[:：]')).Count
$sl = @([regex]::Matches($c, '\[\d+\]\s*(SV630|KV-EC01|SGDXS|CL3C|YAKO)')).Count
Write-Host ('  axes   = ' + $ax + '  (expect 2)')
Write-Host ('  slaves = ' + $sl + '  (expect 2)')
if ($ax -eq 2 -and $sl -eq 2) { Write-Host '  ==> PASS'; exit 0 } else { Write-Host '  ==> FAIL'; exit 1 }