param(
  [Parameter(Mandatory=$true)]
  [string]$MnmPath,

  [string]$ProjectRoot = (Join-Path ([IO.Path]::GetTempPath()) 'keyence-plc-programmer\local_acceptance_projects'),
  [string]$ProjectName = ('KvAccept_' + (Get-Date -Format 'HHmmss')),
  [string]$ExistingProjectPath = '',
  [string]$CpuModel = 'KV-X550',
  [string]$ExpectedModuleName = '',
  [string]$KvsExe = '',
  [string]$OutDir = (Join-Path ([IO.Path]::GetTempPath()) ('keyence-plc-programmer\local_acceptance_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))),
  [int]$BenchmarkSeconds = 300,
  [switch]$RestartKvs
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Log([string]$Message) {
  $line = (Get-Date -Format s) + ' ' + $Message
  Add-Content -LiteralPath (Join-Path $OutDir 'run.log') -Value $line -Encoding UTF8
  Write-Host $line
}

function RemainingSeconds([datetime]$Deadline) {
  $remaining = [int][Math]::Floor(($Deadline - (Get-Date)).TotalSeconds)
  if ($remaining -lt 1) { return 0 }
  return $remaining
}

function Invoke-StepProcess {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$File,
    [Parameter(Mandatory=$true)][string[]]$Arguments,
    [Parameter(Mandatory=$true)][datetime]$Deadline,
    [Parameter(Mandatory=$true)][string]$StepOutDir
  )

  $remaining = RemainingSeconds $Deadline
  if ($remaining -le 0) { throw "benchmark timeout before $Name" }
  New-Item -ItemType Directory -Force -Path $StepOutDir | Out-Null
  $stdout = Join-Path $StepOutDir 'stdout.txt'
  $stderr = Join-Path $StepOutDir 'stderr.txt'
  Log "STEP_START $Name remaining=${remaining}s"
  $childArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$File) + @($Arguments)
  $proc = Start-Process -FilePath 'powershell.exe' `
    -ArgumentList $childArgs `
    -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $exited = $proc.WaitForExit($remaining * 1000)
  if (-not $exited) {
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    throw "STEP_TIMEOUT $Name after ${remaining}s"
  }
  try { $proc.Refresh() } catch {}
  $exitCode = $proc.ExitCode
  if ($null -eq $exitCode) {
    $exitFile = Join-Path $StepOutDir 'exit_code.txt'
    if (Test-Path -LiteralPath $exitFile) {
      $exitText = (Get-Content -LiteralPath $exitFile -Raw).Trim()
      if ($exitText -match '^-?\d+$') {
        $exitCode = [int]$exitText
      }
    }
  }
  if ($null -eq $exitCode -and $Name -eq 'create_project') {
    $createResult = Join-Path $StepOutDir 'create_project_result.json'
    if (Test-Path -LiteralPath $createResult) {
      try {
        $parsed = Get-Content -LiteralPath $createResult -Raw | ConvertFrom-Json
        if ($parsed.ok -eq $true -and (Test-Path -LiteralPath $parsed.project_path)) {
          $exitCode = 0
        }
      } catch {}
    }
  }
  if ($null -eq $exitCode) {
    $exitCode = 1
  }
  Log "STEP_EXIT $Name code=$exitCode"
  if ($exitCode -ne 0) {
    $err = ''
    if (Test-Path -LiteralPath $stderr) { $err = Get-Content -LiteralPath $stderr -Raw }
    $out = ''
    if (Test-Path -LiteralPath $stdout) { $out = Get-Content -LiteralPath $stdout -Raw }
    throw "STEP_FAILED $Name code=$exitCode`nSTDOUT:`n$out`nSTDERR:`n$err"
  }
  return @{
    stdout = $stdout
    stderr = $stderr
  }
}

try {
  $startedAt = Get-Date
  $deadline = $startedAt.AddSeconds($BenchmarkSeconds)
  if (-not (Test-Path -LiteralPath $MnmPath)) { throw "MnmPath not found: $MnmPath" }
  if (-not $ExpectedModuleName) { $ExpectedModuleName = [IO.Path]::GetFileNameWithoutExtension($MnmPath) }

  if (-not $KvsExe) {
    $resolveOut = Join-Path $OutDir '00_resolve'
    New-Item -ItemType Directory -Force -Path $resolveOut | Out-Null
    $resolvedJson = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'resolve_kvstudio_local.ps1') -OutDir $resolveOut
    if ($LASTEXITCODE -ne 0) { throw 'resolve_kvstudio_local.ps1 failed' }
    $KvsExe = ($resolvedJson | ConvertFrom-Json).KvsExe
  }
  if (-not (Test-Path -LiteralPath $KvsExe)) { throw "KvsExe not found: $KvsExe" }

  Log "ACCEPTANCE_START benchmark=${BenchmarkSeconds}s MnmPath=$MnmPath KvsExe=$KvsExe"

  $projectPath = $ExistingProjectPath
  if (-not $projectPath) {
    $stepOut = Join-Path $OutDir '01_create_project'
    $createArgs = @(
      '-ProjectName', $ProjectName,
      '-ProjectRoot', $ProjectRoot,
      '-CpuModel', $CpuModel,
      '-KvsExe', $KvsExe,
      '-OutDir', $stepOut,
      '-TimeoutSeconds', [string](RemainingSeconds $deadline)
    )
    if ($RestartKvs) { $createArgs += '-RestartKvs' }
    Invoke-StepProcess -Name 'create_project' `
      -File (Join-Path $scriptRoot 'create_project_local.ps1') `
      -Arguments $createArgs `
      -Deadline $deadline `
      -StepOutDir $stepOut | Out-Null
    $createResultPath = Join-Path $stepOut 'create_project_result.json'
    if (-not (Test-Path -LiteralPath $createResultPath)) { throw 'create_project_result.json not found' }
    $projectPath = (Get-Content -LiteralPath $createResultPath -Raw | ConvertFrom-Json).project_path
  }
  if (-not (Test-Path -LiteralPath $projectPath)) { throw "ProjectPath not found after create: $projectPath" }
  Log "PROJECT_READY $projectPath"

  $roundtripOut = Join-Path $OutDir '02_roundtrip'
  $roundtripArgs = @(
    '-MnmPath', $MnmPath,
    '-ProjectPath', $projectPath,
    '-OutDir', $roundtripOut,
    '-KvsExe', $KvsExe,
    '-ExpectedModuleName', $ExpectedModuleName,
    '-RestartKvs:$true'
  )
  Invoke-StepProcess -Name 'roundtrip_mnm' `
    -File (Join-Path $scriptRoot 'roundtrip_mnm.ps1') `
    -Arguments $roundtripArgs `
    -Deadline $deadline `
    -StepOutDir $roundtripOut | Out-Null

  $convertOut = Join-Path $OutDir '03_convert'
  $convertArgs = @(
    '-ProjectPath', $projectPath,
    '-OutDir', $convertOut,
    '-KvsExe', $KvsExe,
    '-OpenWaitSeconds', '3',
    '-ConvertWaitSeconds', '20',
    '-RestartKvs'
  )
  Invoke-StepProcess -Name 'convert_collect' `
    -File (Join-Path $scriptRoot 'convert_collect.ps1') `
    -Arguments $convertArgs `
    -Deadline $deadline `
    -StepOutDir $convertOut | Out-Null

  $elapsed = [Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
  $result = [pscustomobject]@{
    ok = $true
    benchmark_seconds = $BenchmarkSeconds
    elapsed_seconds = $elapsed
    project_path = $projectPath
    mnm_path = (Resolve-Path -LiteralPath $MnmPath).Path
    kvs_exe = $KvsExe
    out_dir = (Resolve-Path -LiteralPath $OutDir).Path
  }
  $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'acceptance_result.json') -Encoding UTF8
  Log "ACCEPTANCE_PASS elapsed=${elapsed}s"
  $result | ConvertTo-Json -Depth 5
} catch {
  $elapsed = [Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
  Log "ACCEPTANCE_FAIL elapsed=${elapsed}s $($_.Exception.Message)"
  [pscustomobject]@{
    ok = $false
    elapsed_seconds = $elapsed
    error = $_.Exception.Message
    out_dir = $OutDir
  } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'acceptance_result.json') -Encoding UTF8
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  exit 1
}
