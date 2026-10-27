param(
  [ValidateSet('Both','Negative','Positive')][string]$Case = 'Both',
  [string]$OutDir = '',
  [int]$TimeoutSeconds = 300
)
# Axis-table-edit example: now a self-contained test with two cases.
#   Negative: no KV STUDIO running -> the runner must fail fast with
#             KV_TABLE_NO_KVS (the designed precondition error).
#   Positive: copy the QA_BlankProject fixture, open it, navigate to 轴控制设定,
#             edit row 39/col 1 -> 1500, then verify the result JSON
#             (ok=true, exactly one diff at row 39).
$ErrorActionPreference = 'Stop'
$repo = 'H:\KeyenceAgent\kv-studio-operator'
$kvsExe = 'H:\Keyence\KVS12\KVS\Kvs.exe'
$fixture = Join-Path $repo 'tests\table-cell\fixtures\QA_BlankProject'
$openTable = Join-Path $repo 'tests\table-cell\open-table.ps1'
$verify = Join-Path $repo 'tests\table-cell\verify.ps1'
$cellRunner = Join-Path $repo 'scripts\runner_children\set_axis_table_cell_guarded.ps1'

if (-not $OutDir) { $OutDir = Join-Path $env:TEMP ('kv-axis-table-edit-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Stop-Kvs {
  Get-Process Kvs -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 3
}

function Invoke-Ps([string]$scriptPath, [string[]]$arguments, [string]$outFile) {
  $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $arguments
  $errFile = $outFile + '.err.txt'
  $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $all -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile -WindowStyle Hidden
  return [pscustomobject]@{ ExitCode = $p.ExitCode; OutFile = $outFile; ErrFile = $errFile }
}

$results = New-Object System.Collections.Generic.List[object]

if ($Case -in @('Both', 'Negative')) {
  $negDir = Join-Path $OutDir 'negative'
  New-Item -ItemType Directory -Force -Path $negDir | Out-Null
  Stop-Kvs
  $r = Invoke-Ps $cellRunner @('-OutDir', $negDir, '-ListOnly') (Join-Path $negDir 'list.out.txt')
  $errText = if (Test-Path $r.ErrFile) { Get-Content $r.ErrFile -Raw -Encoding UTF8 } else { '' }
  $outText = if (Test-Path $r.OutFile) { Get-Content $r.OutFile -Raw -Encoding UTF8 } else { '' }
  $expectedCode = ($errText -match 'KV_TABLE_NO_KVS') -or ($outText -match 'KV_TABLE_NO_KVS')
  $ok = ($r.ExitCode -ne 0) -and $expectedCode
  $results.Add([pscustomobject]@{ case = 'negative'; ok = $ok; exit_code = $r.ExitCode; expected = 'KV_TABLE_NO_KVS'; detail = $(if ($ok) { 'failed fast with the designed error' } else { 'did not fail with KV_TABLE_NO_KVS' }) })
  Write-Host ("[negative] exit={0} expected_error={1} -> {2}" -f $r.ExitCode, $expectedCode, $(if ($ok) { 'PASS' } else { 'FAIL' }))
}

if ($Case -in @('Both', 'Positive')) {
  $posDir = Join-Path $OutDir 'positive'
  $projRoot = Join-Path $posDir 'project'
  New-Item -ItemType Directory -Force -Path $projRoot | Out-Null
  $dest = Join-Path $projRoot 'QA_BlankProject'
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  Copy-Item $fixture $dest -Recurse
  $doc = Join-Path $dest 'DocumentWindowInfo.xml'
  if (Test-Path $doc) { Remove-Item $doc -Force }
  $kpr = Join-Path $dest 'QA_BlankProject.kpr'
  Stop-Kvs
  Start-Process -FilePath $kvsExe -ArgumentList @('"' + $kpr + '"')
  Start-Sleep -Seconds 20

  $openR = Invoke-Ps $openTable @() (Join-Path $posDir 'open_table.out.txt')
  $editDir = Join-Path $posDir 'cell'
  $editR = if ($openR.ExitCode -eq 0) { Invoke-Ps $cellRunner @('-OutDir', $editDir, '-RowIndex', '39', '-Column', '1', '-Value', '1500') (Join-Path $posDir 'edit.out.txt') } else { [pscustomobject]@{ ExitCode = 999 } }
  $verifyR = if ($editR.ExitCode -eq 0) { Invoke-Ps $verify @('-OutDir', $posDir, '-Stage', 'result') (Join-Path $posDir 'verify.out.txt') } else { [pscustomobject]@{ ExitCode = 999 } }
  Stop-Kvs
  $ok = ($openR.ExitCode -eq 0) -and ($editR.ExitCode -eq 0) -and ($verifyR.ExitCode -eq 0)
  $results.Add([pscustomobject]@{ case = 'positive'; ok = $ok; open_table_exit = $openR.ExitCode; edit_exit = $editR.ExitCode; verify_exit = $verifyR.ExitCode; detail = $(if ($ok) { 'table opened, row 39 edited, diff verified' } else { 'one of open/edit/verify failed' }) })
  Write-Host ("[positive] open={0} edit={1} verify={2} -> {3}" -f $openR.ExitCode, $editR.ExitCode, $verifyR.ExitCode, $(if ($ok) { 'PASS' } else { 'FAIL' }))
}

$failed = @($results | Where-Object { -not $_.ok })
$result = [ordered]@{
  test = 'axis-table-edit'
  cases = $results.ToArray()
  passed = @($results | Where-Object { $_.ok }).Count
  failed = $failed.Count
  ok = ($failed.Count -eq 0)
  out_dir = $OutDir
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
Write-Host ($result | ConvertTo-Json -Depth 5)
if ($failed.Count -gt 0) { exit 41 }
exit 0
