param(
    [string]$OutRoot = '',
    [string[]]$Skip = @('24_axis_pitch'),
    [int]$IntervalMs = 300,
    [switch]$PlanOnly
)
$ErrorActionPreference = 'Continue'
$repo = 'H:\KeyenceAgent\kv-studio-operator'
$root = Join-Path $repo 'tests\kv-interface-regression'
if (-not $OutRoot) { $OutRoot = Join-Path $env:TEMP ('kv-suite-' + (Get-Date).ToString('yyyyMMdd_HHmmss')) }
$null = New-Item -ItemType Directory -Force -Path $OutRoot
$results = @()
$scenarios = @(Get-ChildItem $root -Directory | Where-Object { $_.Name -match '^\d\d_' } | Sort-Object Name)
foreach ($sc in $scenarios) {
    $sp = Join-Path $sc.FullName 'scenario.json'
    if (-not (Test-Path $sp)) { continue }
    $j = Get-Content $sp -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($j.enabled -eq $false) { Write-Host ('SKIP(disabled) ' + $sc.Name); continue }
    if ($Skip -contains $sc.Name) { Write-Host ('SKIP(requested) ' + $sc.Name); continue }
    $shotDir = Join-Path $OutRoot (Join-Path $sc.Name 'shots')
    $null = New-Item -ItemType Directory -Force -Path $shotDir
    Write-Host ('==== ' + $sc.Name + '  (shots -> ' + $shotDir + ')')
    $capArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $repo 'scripts\Capture-KvFrame.ps1'),'-OutDir',$shotDir,'-Continuous','-IntervalMs',[string]$IntervalMs,'-MaxSeconds','900')
    $cap = Start-Process -FilePath 'powershell' -ArgumentList $capArgs -PassThru -WindowStyle Hidden
    try {
        $runArgs = @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $sc.FullName 'run.ps1'),'-OutRoot',(Join-Path $OutRoot $sc.Name))
        if ($PlanOnly) { $runArgs += '-PlanOnly' }
        & powershell @runArgs *> (Join-Path $OutRoot (Join-Path $sc.Name 'run.log'))
        $exit = $LASTEXITCODE
        $tr = Get-ChildItem (Join-Path $OutRoot $sc.Name) -Recurse -File -Filter 'test_result.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $ok = $false; $status = 'no-result'
        if ($tr) { $tj = Get-Content $tr.FullName -Encoding UTF8 -Raw | ConvertFrom-Json; $ok = [bool]$tj.ok; $status = [string]$tj.status }
        $results += [pscustomobject]@{ scenario = $sc.Name; exit = $exit; ok = $ok; status = $status; shots = $shotDir }
        Write-Host ('==== ' + $sc.Name + ' exit=' + $exit + ' ok=' + $ok + ' status=' + $status)
    } finally {
        New-Item -ItemType File -Force -Path (Join-Path $shotDir 'STOP') | Out-Null
        Start-Sleep -Milliseconds 800
        try { if ($cap -and -not $cap.HasExited) { $cap.Kill() } } catch { }
        try { foreach ($pp in @(Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue)) { $pp.Kill() } } catch { }
        # 等 KVS 完全退出（否则下一个场景会 attach 到旧实例 / 看到残留对话框 ✗）
        $deadline = (Get-Date).AddSeconds(25)
        while ((Get-Date) -lt $deadline) {
            if (@(Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue).Count -eq 0) { break }
            Start-Sleep -Milliseconds 400
        }
        Start-Sleep -Seconds 2
        Start-Sleep -Seconds 3
    }
}
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutRoot 'suite_result.json') -Encoding UTF8
Write-Host ''
Write-Host '===== SUMMARY ====='
$pass = @($results | Where-Object { $_.ok }).Count
$fail = @($results | Where-Object { -not $_.ok }).Count
Write-Host ('PASS=' + $pass + '  FAIL=' + $fail + '  total=' + $results.Count)
$results | ForEach-Object { Write-Host (('{0,-32}' -f $_.scenario) + ' ok=' + $_.ok + '  exit=' + $_.exit) }
Write-Host ('out=' + $OutRoot)
exit $(if ($fail -eq 0) { 0 } else { 1 })