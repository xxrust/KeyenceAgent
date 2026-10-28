param(
  [string]$OutDir = '',
  [int]$TimeoutSeconds = 600
)
# Self-contained live test for the EtherNet/IP CRUD capability:
#   1. copy references\KVX样例程序_v100 to a temp project
#   2. open it in KV STUDIO
#   3. Add a NU-EP1 node -> Modify its IP -> Delete it
#   4. assert every step's result JSON and the in-window readback
# The fixture has NU-EP1 (node 1) and DL-EP1 (node 2); the added node becomes
# node 3 (inserted right after the PLC).
$ErrorActionPreference = 'Stop'
$repo = 'H:\KeyenceAgent\kv-studio-operator'
$kvsExe = 'H:\Keyence\KVS12\KVS\Kvs.exe'
$workflow = Join-Path $repo 'scripts\workflows\configure_kv_eip_devices.ps1'
$fixture = Join-Path $repo 'references\KVX样例程序_v100'
$fixtureKpr = Join-Path $fixture 'KVX样例程序_v100.kpr'

if (-not $OutDir) { $OutDir = Join-Path $env:TEMP ('kv-eip-live-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Log([string]$m) { Write-Host ((Get-Date).ToString('HH:mm:ss') + '  ' + $m) }
function Stop-Kvs {
  Get-Process Kvs -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 3
}

Log "out_dir=$OutDir"
Stop-Kvs
$dest = Join-Path $OutDir 'project'
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Copy-Item $fixture $dest -Recurse
$kpr = Join-Path $dest 'KVX样例程序_v100.kpr'
$docInfo = Join-Path (Split-Path $kpr -Parent) 'DocumentWindowInfo.xml'
if (Test-Path $docInfo) { Remove-Item $docInfo -Force }
Log "project=$kpr"

Start-Process -FilePath $kvsExe -ArgumentList @('"' + $kpr + '"')
$deadline = (Get-Date).AddSeconds(120)
$ready = $false
while ((Get-Date) -lt $deadline -and -not $ready) {
  Start-Sleep -Seconds 2
  $p = Get-Process Kvs -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p -and $p.MainWindowTitle -like '*KVX样例程序_v100*') { $ready = $true }
}
if (-not $ready) {
  Stop-Kvs
  throw 'KV_EIP_LIVE_KVS_NOT_READY: project window did not appear in 120s'
}
Log 'kvs_ready'

$addCfg = Join-Path $OutDir 'add.json'
$modCfg = Join-Path $OutDir 'modify.json'
$delCfg = Join-Path $OutDir 'delete.json'
[IO.File]::WriteAllText($addCfg, '{"schema_version":1,"devices":[{"model":"NU-EP1","node_address":3,"ip_address":"192.168.0.3"}]}', (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($modCfg, '{"schema_version":1,"devices":[{"node_address":3,"ip_address":"192.168.0.31"}]}', (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($delCfg, '{"schema_version":1,"devices":[{"node_address":3}]}', (New-Object Text.UTF8Encoding($false)))

function Invoke-Step([string]$action, [string]$configPath, [string]$stepName) {
  $stepOut = Join-Path $OutDir $stepName
  New-Item -ItemType Directory -Force -Path $stepOut | Out-Null
  $outFile = Join-Path $stepOut 'stdout.txt'
  $errFile = Join-Path $stepOut 'stderr.txt'
  $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $workflow,
    '-Action', $action, '-ProjectPath', $kpr, '-DevicesConfigPath', $configPath,
    '-OutDir', $stepOut, '-TimeoutSeconds', "$TimeoutSeconds")
  $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Wait -PassThru `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile -WindowStyle Hidden
  $exitCode = $p.ExitCode
  $resultName = if ($action -eq 'Add') { 'eip_write_result.json' } else { 'eip_edit_result.json' }
  $resultPath = Join-Path $stepOut $resultName
  $result = $null
  if (Test-Path $resultPath) {
    try { $result = Get-Content $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
  }
  if ($exitCode -ne 0 -or -not $result) {
    $wf = Join-Path $stepOut 'workflow_result.json'
    $message = ''
    if (Test-Path $wf) {
      try { $message = (Get-Content $wf -Raw -Encoding UTF8 | ConvertFrom-Json).message } catch {}
    }
    if (-not $message) { $message = (Get-Content $errFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) }
    return [pscustomobject]@{ action = $action; ok = $false; exit_code = $exitCode; detail = $message; result = $result; out_dir = $stepOut }
  }
  return [pscustomobject]@{ action = $action; ok = [bool]$result.ok; exit_code = $exitCode; detail = $result.message; result = $result; out_dir = $stepOut }
}

$steps = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[string]

Log 'step 1/3 add'
$add = Invoke-Step 'Add' $addCfg 'add'
$steps.Add($add)
if (-not $add.ok) { $failures.Add('add: ' + $add.detail) }

Log 'step 2/3 modify'
$mod = Invoke-Step 'Modify' $modCfg 'modify'
$steps.Add($mod)
if ($mod.ok) {
  $post = @($mod.result.post_ips)
  if (-not ($post -contains '192.168.0.31')) { $failures.Add('modify: post_ips does not contain 192.168.0.31') }
} else { $failures.Add('modify: ' + $mod.detail) }

Log 'step 3/3 delete'
$del = Invoke-Step 'Delete' $delCfg 'delete'
$steps.Add($del)
if ($del.ok) {
  $pre = @($del.result.pre_ips)
  $post = @($del.result.post_ips)
  if ($post.Count -ge $pre.Count) { $failures.Add("delete: row count did not shrink ($($pre.Count) -> $($post.Count))") }
} else { $failures.Add('delete: ' + $del.detail) }

Stop-Kvs

$result = [ordered]@{
  test = 'eip-live-cycle'
  project = $kpr
  steps = @($steps | ForEach-Object {
    [ordered]@{
      action = $_.action; ok = $_.ok; exit_code = $_.exit_code; detail = $_.detail; out_dir = $_.out_dir
      pre_ips = $_.result.pre_ips; post_ips = $_.result.post_ips; readback = $_.result.readback
    }
  })
  failures = @($failures)
  ok = ($failures.Count -eq 0)
  out_dir = $OutDir
  generated_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
Write-Host ($result | ConvertTo-Json -Depth 6)
if ($failures.Count -gt 0) { exit 41 }
exit 0

