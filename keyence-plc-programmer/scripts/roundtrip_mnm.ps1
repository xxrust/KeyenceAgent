param(
  [Parameter(Mandatory=$true)]
  [string]$MnmPath,

  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [string]$OutDir = ('C:\Users\Public\KVSkillPractice\kvtool\mnm_roundtrip_' + (Get-Date -Format 'yyyyMMdd_HHmmss')),

  [string]$KvsExe = 'C:\Program Files (x86)\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe',

  [string]$ExpectedModuleName = '',

  [string]$ImportScript = '',

  [string]$ExportScript = '',

  [switch]$DeleteExistingModuleBeforeImport,

  [object]$RestartKvs = $true
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Write-RunLog {
  param([string]$Message)
  Add-Content -LiteralPath (Join-Path $OutDir 'run.log') -Value ((Get-Date -Format s) + ' ' + $Message) -Encoding UTF8
}

function ConvertTo-BoolValue([object]$Value, [bool]$Default) {
  if ($null -eq $Value) { return $Default }
  if ($Value -is [bool]) { return [bool]$Value }
  $text = ([string]$Value).Trim()
  if ($text.Length -eq 0) { return $Default }
  switch -Regex ($text) {
    '^(?i:\$?true|1|yes|y|on)$' { return $true }
    '^(?i:\$?false|0|no|n|off)$' { return $false }
    default { throw "Invalid boolean value: $Value" }
  }
}

function Get-MnmInstructionFingerprint {
  param([Parameter(Mandatory=$true)][string]$Path)
  $ops = 'LD|LDB|LDP|LDF|AND|ANB|ANI|OR|ORB|ORI|OUT|SET|RES|MOV|DMOV|CMP|TMR|CNT|END|ENDH'
  $items = New-Object System.Collections.Generic.List[string]
  foreach ($rawLine in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
    $line = ([string]$rawLine).Trim()
    if ($line.Length -eq 0) { continue }
    if ($line.StartsWith(';')) { continue }
    if ($line -match ('^(?i)(' + $ops + ')(?:\s+(.+))?$')) {
      $op = $matches[1].ToUpperInvariant()
      $arg = ''
      if ($matches.Count -ge 3 -and $matches[2]) {
        $arg = (($matches[2].Trim()) -replace '\s+', ' ').ToUpperInvariant()
      }
      if ($arg) {
        $items.Add("$op $arg")
      } else {
        $items.Add($op)
      }
    }
  }
  return @($items)
}

function Write-Fingerprint {
  param(
    [string[]]$Fingerprint,
    [string]$Path
  )
  [IO.File]::WriteAllLines($Path, $Fingerprint, [Text.UTF8Encoding]::new($false))
}

try {
  $RestartKvs = ConvertTo-BoolValue $RestartKvs $true
  if (-not (Test-Path -LiteralPath $MnmPath)) { throw "MnmPath not found: $MnmPath" }
  if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "ProjectPath not found: $ProjectPath" }
  if (-not (Test-Path -LiteralPath $KvsExe)) { throw "KvsExe not found: $KvsExe" }
  if (-not $ExpectedModuleName) {
    $ExpectedModuleName = [IO.Path]::GetFileNameWithoutExtension($MnmPath)
  }

  $scriptRoot = Split-Path -Parent $PSCommandPath
  if (-not $ImportScript) { $ImportScript = Join-Path $scriptRoot 'import_mnm.ps1' }
  if (-not $ExportScript) { $ExportScript = Join-Path $scriptRoot 'export_mnm.ps1' }
  if (-not (Test-Path -LiteralPath $ImportScript)) { throw "ImportScript not found: $ImportScript" }
  if (-not (Test-Path -LiteralPath $ExportScript)) { throw "ExportScript not found: $ExportScript" }

  Write-RunLog 'start roundtrip_mnm'
  Write-RunLog "MnmPath=$MnmPath"
  Write-RunLog "ProjectPath=$ProjectPath"
  Write-RunLog "ExpectedModuleName=$ExpectedModuleName"

  $expectedFingerprint = @(Get-MnmInstructionFingerprint -Path $MnmPath)
  Write-Fingerprint -Fingerprint $expectedFingerprint -Path (Join-Path $OutDir 'expected_fingerprint.txt')
  if ($expectedFingerprint.Count -eq 0) {
    throw "Expected MNM has no executable instruction fingerprint: $MnmPath"
  }

  $importOut = Join-Path $OutDir '01_import'
  $exportOut = Join-Path $OutDir '02_export'
  New-Item -ItemType Directory -Force -Path $importOut, $exportOut | Out-Null

  $importArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $ImportScript,
    '-MnmPath', $MnmPath,
    '-ProjectPath', $ProjectPath,
    '-OutDir', $importOut,
    '-KvsExe', $KvsExe,
    '-ExpectedModuleName', $ExpectedModuleName,
    '-SaveAfterImport',
    '-RestartKvs:' + ([string]$RestartKvs)
  )
  if($DeleteExistingModuleBeforeImport.IsPresent){
    $importArgs += '-DeleteExistingModuleBeforeImport'
  }
  & powershell @importArgs
  $importExit = $LASTEXITCODE
  if ($importExit -ne 0) {
    throw "import_mnm.ps1 failed with exit code $importExit"
  }

  & powershell -NoProfile -ExecutionPolicy Bypass -File $ExportScript `
    -ProjectPath $ProjectPath `
    -OutDir $exportOut `
    -KvsExe $KvsExe `
    -RestartKvs:$false
  $exportExit = $LASTEXITCODE
  if ($exportExit -ne 0) {
    throw "export_mnm.ps1 failed with exit code $exportExit"
  }

  $exportedCandidates = @(Get-ChildItem -LiteralPath $exportOut -Recurse -Filter '*.mnm' -File -ErrorAction SilentlyContinue)
  if ($exportedCandidates.Count -eq 0) {
    throw "No exported MNM files found under $exportOut"
  }
  $exported = $exportedCandidates |
    Where-Object { $_.BaseName -eq $ExpectedModuleName } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $exported) {
    $exported = $exportedCandidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  }

  $actualFingerprint = @(Get-MnmInstructionFingerprint -Path $exported.FullName)
  Write-Fingerprint -Fingerprint $actualFingerprint -Path (Join-Path $OutDir 'actual_fingerprint.txt')

  $expectedText = ($expectedFingerprint -join "`n")
  $actualText = ($actualFingerprint -join "`n")
  $pass = $expectedText -eq $actualText

  [pscustomobject]@{
    status = if ($pass) { 'PASS' } else { 'FAIL' }
    mnm_path = $MnmPath
    project_path = $ProjectPath
    expected_module_name = $ExpectedModuleName
    exported_mnm_path = $exported.FullName
    expected_instruction_count = $expectedFingerprint.Count
    actual_instruction_count = $actualFingerprint.Count
    import_out = $importOut
    export_out = $exportOut
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'roundtrip_report.json') -Encoding UTF8

  if (-not $pass) {
    throw "MNM roundtrip fingerprint mismatch. Expected $($expectedFingerprint.Count) instructions, got $($actualFingerprint.Count)."
  }

  '0' | Set-Content -LiteralPath (Join-Path $OutDir 'exit_code.txt') -Encoding ASCII
  Write-RunLog 'PASS roundtrip_mnm'
} catch {
  Write-RunLog ('ERROR ' + $_.Exception.ToString())
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  '1' | Set-Content -LiteralPath (Join-Path $OutDir 'exit_code.txt') -Encoding ASCII
  exit 1
}
