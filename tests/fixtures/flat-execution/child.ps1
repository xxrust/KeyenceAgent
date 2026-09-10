param([string]$OutDir, [string]$Mode, [string]$Value = '', [string]$Empty = 'not-empty', [switch]$SnapshotOnly, [string[]]$Items=@())
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$resultPath = Join-Path $OutDir 'result.json'
if ($SnapshotOnly) { $resultPath = Join-Path $OutDir 'snapshot.json' }
switch ($Mode) {
  'missing' { exit 0 }
  'malformed' { '{bad' | Set-Content -LiteralPath $resultPath; exit 0 }
  'no_ok' { '{"value":42}' | Set-Content -LiteralPath $resultPath; exit 0 }
  'string_ok' { '{"ok":"true"}' | Set-Content -LiteralPath $resultPath; exit 0 }
  'false_ok' { '{"ok":false}' | Set-Content -LiteralPath $resultPath; '{"ok":true}' | Set-Content -LiteralPath (Join-Path $OutDir 'helper_result.json'); exit 0 }
  'timeout' { Start-Sleep -Seconds 30; exit 0 }
  'quoting' {
    if ($Value -ne 'space "quote" $cash `literal \trailing\' -or $Empty -ne '') { throw "Wrong argument transport: [$Value] [$Empty]" }
  }
  'typed' { if ($Items.Count -ne 2 -or $Items[0] -ne 'model, one' -or $Items[1] -ne 'model two' -or -not $SnapshotOnly) { throw 'Typed parameter transport failed' } }
}
@{ok=$true;value=$Value} | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
if ($Mode -eq 'stale') { (Get-Item -LiteralPath $resultPath).LastWriteTimeUtc = [datetime]'2000-01-01'; exit 0 }
if ($Mode -eq 'process_fail') { '0' | Set-Content -LiteralPath (Join-Path $OutDir 'exit_code.txt'); exit 7 }
if ($Mode -eq 'sentinel_fail') { '8' | Set-Content -LiteralPath (Join-Path $OutDir 'exit_code.txt'); exit 0 }
if ($Mode -eq 'failure_file') { 'failed' | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt'); exit 0 }
if ($Mode -eq 'stderr') { [Console]::Error.WriteLine('failure'); exit 0 }
exit 0
