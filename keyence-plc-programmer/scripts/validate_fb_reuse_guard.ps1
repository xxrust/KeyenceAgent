param(
  [Parameter(Mandatory = $true)]
  [string[]]$Path,
  [string]$ContractPath = '',
  [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Read-TextFile {
  param([string]$FilePath)
  $bytes = [IO.File]::ReadAllBytes($FilePath)
  foreach ($encoding in @(
      [Text.UTF8Encoding]::new($false, $true),
      [Text.Encoding]::GetEncoding(936),
      [Text.Encoding]::Default
    )) {
    try {
      return $encoding.GetString($bytes).TrimStart([char]0xFEFF)
    } catch {
    }
  }
  return [Text.Encoding]::Default.GetString($bytes).TrimStart([char]0xFEFF)
}

function Get-MnmFiles {
  param([string[]]$InputPath)
  $files = New-Object System.Collections.Generic.List[string]
  foreach ($item in $InputPath) {
    if (-not (Test-Path -LiteralPath $item)) {
      throw "Path does not exist: $item"
    }
    $resolved = Resolve-Path -LiteralPath $item
    foreach ($r in $resolved) {
      $target = Get-Item -LiteralPath $r.Path
      if ($target.PSIsContainer) {
        Get-ChildItem -LiteralPath $target.FullName -Filter '*.mnm' -File -Recurse |
          ForEach-Object { $files.Add($_.FullName) }
      } else {
        $files.Add($target.FullName)
      }
    }
  }
  return $files | Sort-Object -Unique
}

function Normalize-AllowedDevice {
  param($Entry)
  if ($null -eq $Entry) {
    return $null
  }
  if ($Entry -is [string]) {
    return [pscustomobject]@{
      Module = '*'
      Device = $Entry.ToUpperInvariant()
      Reason = ''
      Evidence = ''
      Valid = $false
    }
  }
  $device = ''
  if ($Entry.PSObject.Properties.Name -contains 'device') {
    $device = [string]$Entry.device
  }
  $module = '*'
  if ($Entry.PSObject.Properties.Name -contains 'module') {
    $module = [string]$Entry.module
  }
  $reason = ''
  if ($Entry.PSObject.Properties.Name -contains 'reason') {
    $reason = [string]$Entry.reason
  }
  $evidence = ''
  if ($Entry.PSObject.Properties.Name -contains 'evidence') {
    $evidence = [string]$Entry.evidence
  }
  return [pscustomobject]@{
    Module = $(if ([string]::IsNullOrWhiteSpace($module)) { '*' } else { $module })
    Device = $device.ToUpperInvariant()
    Reason = $reason
    Evidence = $evidence
    Valid = ((-not [string]::IsNullOrWhiteSpace($device)) -and
      (-not [string]::IsNullOrWhiteSpace($reason)) -and
      (-not [string]::IsNullOrWhiteSpace($evidence)))
  }
}

function Load-Contract {
  param([string]$FilePath)
  $allowed = New-Object System.Collections.Generic.List[object]
  if ([string]::IsNullOrWhiteSpace($FilePath)) {
    return $allowed
  }
  if (-not (Test-Path -LiteralPath $FilePath)) {
    throw "Contract file does not exist: $FilePath"
  }
  $raw = Read-TextFile -FilePath $FilePath
  $contract = $raw | ConvertFrom-Json
  if ($contract.PSObject.Properties.Name -contains 'allowed_devices') {
    foreach ($entry in $contract.allowed_devices) {
      $normalized = Normalize-AllowedDevice -Entry $entry
      if ($null -ne $normalized) {
        $allowed.Add($normalized)
      }
    }
  }
  return $allowed
}

function Get-ModuleName {
  param([string[]]$Lines)
  foreach ($line in $Lines) {
    if ($line -match '^\s*;MODULE\s*:\s*(.+?)\s*$') {
      return $Matches[1].Trim()
    }
  }
  return '<unknown>'
}

function Is-UserFunctionBlock {
  param([string[]]$Lines)
  foreach ($line in $Lines) {
    if ($line -match '^\s*;MODULE_TYPE\s*:\s*2\s*$') {
      return $true
    }
  }
  return $false
}

function Is-AllowedDevice {
  param(
    [string]$Module,
    [string]$Device,
    [object[]]$AllowedDevices
  )
  $upperDevice = $Device.ToUpperInvariant()
  foreach ($entry in $AllowedDevices) {
    if (-not $entry.Valid) {
      continue
    }
    if ($entry.Device -ne $upperDevice) {
      continue
    }
    if ($entry.Module -eq '*' -or $entry.Module -eq $Module) {
      return $true
    }
  }
  return $false
}

$files = Get-MnmFiles -InputPath $Path
$allowedDevices = Load-Contract -FilePath $ContractPath
$devicePattern = '(?<![A-Za-z0-9_])(?:DMR|DM|EM|FM|ZF|TM|CM|MR|LR|CR|DR|R|B|W|X|Y|T|C|Z)[0-9]+(?![A-Za-z0-9_])'
$violations = New-Object System.Collections.Generic.List[object]
$checked = 0
$fbCount = 0

foreach ($file in $files) {
  $checked++
  $text = Read-TextFile -FilePath $file
  $lines = $text -split "`r?`n"
  if (-not (Is-UserFunctionBlock -Lines $lines)) {
    continue
  }
  $fbCount++
  $module = Get-ModuleName -Lines $lines
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^\s*(;|DEVICE\s*:|ENDH\s*$)') {
      continue
    }
    foreach ($match in [regex]::Matches($line, $devicePattern)) {
      $device = $match.Value.ToUpperInvariant()
      if (Is-AllowedDevice -Module $module -Device $device -AllowedDevices $allowedDevices) {
        continue
      }
      $violations.Add([pscustomobject]@{
          file = $file
          module = $module
          line = $i + 1
          device = $device
          text = $line.Trim()
          code = 'KV_FB_REUSE_DEVICE_LEAK'
        })
    }
  }
}

$result = [pscustomobject]@{
  checked_files = $checked
  function_blocks = $fbCount
  violations = $violations
  ok = ($violations.Count -eq 0)
}

if ($Json) {
  $result | ConvertTo-Json -Depth 5
} elseif ($violations.Count -eq 0) {
  "FB reuse guard passed. Checked files: $checked, user FBs: $fbCount"
} else {
  "FB reuse guard failed. Fixed device leaks: $($violations.Count)."
  foreach ($v in $violations) {
    "{0}:{1} [{2}] {3} {4} :: {5}" -f $v.file, $v.line, $v.module, $v.device, $v.code, $v.text
  }
  "If a fixed device is truly part of the FB hardware contract, list device, reason, and evidence in contract JSON allowed_devices."
}

if ($violations.Count -ne 0) {
  exit 1
}
