<#
.SYNOPSIS
  Resolve the local KV STUDIO (Kvs.exe) installation.

.DESCRIPTION
  Detection is layered from cheap and precise to broad, and stops at the first
  verified hit. Every candidate must be an existing file whose leaf name is
  Kvs.exe, so a stale setting can never be reported as an installation.

  Layers (in order):
    1. -KvsExe explicit override
    2. result cache (re-validated on every read)
    3. operator config kvs_exe
    4. registry: App Paths, then KEYENCE KV STUDIO uninstall entries,
       then KEYENCE registry values
    5. Start Menu shortcuts (legacy exact path plus machine/per-user trees)
    6. default or supplied search roots (version file, KVS<version> layout,
       bounded recursive scan)
    7. legacy hard-coded C: paths

  A hit is reported as JSON on stdout. Consumers parse .KvsExe, which is
  unchanged from earlier versions; the extra fields are additive.

  -Probe is the fast boolean contract for other agents: stdout carries the
  Kvs.exe path and the exit code is 0 when installed, 1 when not installed.

  The -Skip* switches exist so an explicit root set can be tested
  deterministically without touching the real machine.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File resolve_kvstudio_local.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File resolve_kvstudio_local.ps1 -Probe
#>
param(
  [string]$KvsExe = '',
  [string]$ConfigPath = '',
  [string[]]$SearchRoots = @(),
  [string[]]$ShortcutRoots = @(),
  [string[]]$ShortcutPath = @(),
  [string]$CachePath = '',
  [int]$MaxScanDepth = 3,
  [switch]$SkipConfig,
  [switch]$SkipRegistry,
  [switch]$SkipStartMenu,
  [switch]$SkipDriveScan,
  [switch]$SkipCache,
  [switch]$Probe,
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
$script:Checked = New-Object System.Collections.Generic.List[string]
$script:Started = Get-Date

function Add-Checked([string]$Value) {
  if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $script:Checked.Contains($Value)) {
    $script:Checked.Add($Value) | Out-Null
  }
}

function Test-KvsCandidate([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
  $expanded = ''
  try { $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')) } catch { return '' }
  if ([string]::IsNullOrWhiteSpace($expanded)) { return '' }
  Add-Checked $expanded
  if ((Split-Path -Leaf $expanded) -ine 'Kvs.exe') { return '' }
  $item = Get-Item -LiteralPath $expanded -Force -ErrorAction SilentlyContinue
  if (-not $item -or $item.PSIsContainer) { return '' }
  return $item.FullName
}

function Get-KvsUnderRoot([string]$Root, [int]$Depth) {
  $found = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrWhiteSpace($Root)) { return $found }
  $full = ''
  try { $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Root)) } catch { return $found }
  if (-not (Test-Path -LiteralPath $full -PathType Container)) { return $found }

  # 1. explicit version pointer written next to the KEYENCE launcher
  $versionFile = Join-Path $full 'KvsVersionPath.txt'
  if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
    $marker = ''
    try { $marker = ([IO.File]::ReadAllText($versionFile)).Trim() } catch { $marker = '' }
    Add-Checked ('version-file ' + $full + ' -> ' + $marker)
    if ($marker -match '(\d+)') {
      $found.Add((Join-Path $full ('KVS{0}\KVS\Kvs.exe' -f $Matches[1]))) | Out-Null
      $found.Add((Join-Path $full ($marker + '\KVS' + $Matches[1] + '\KVS\Kvs.exe'))) | Out-Null
    }
  }

  # 2. KVS<version> layout, newest version first
  $versionDirs = @()
  try {
    $versionDirs = @(Get-ChildItem -LiteralPath $full -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^KVS(\d+)$' } |
      Sort-Object { [int]($_.Name -replace '^KVS', '') } -Descending)
  } catch { $versionDirs = @() }
  foreach ($dir in $versionDirs) {
    $found.Add((Join-Path $dir.FullName 'KVS\Kvs.exe')) | Out-Null
    $found.Add((Join-Path $dir.FullName 'Kvs.exe')) | Out-Null
  }

  # 3. bounded recursive scan
  if ($Depth -gt 0) {
    $scanned = @()
    try {
      $scanned = @(Get-ChildItem -LiteralPath $full -Filter 'Kvs.exe' -File -Recurse -Depth $Depth -ErrorAction SilentlyContinue)
    } catch { $scanned = @() }
    foreach ($item in $scanned) { $found.Add($item.FullName) | Out-Null }
  }
  return $found
}

function Get-KvsFromRoots([string[]]$Roots, [int]$Depth) {
  foreach ($root in $Roots) {
    if ([string]::IsNullOrWhiteSpace($root)) { continue }
    foreach ($candidate in (Get-KvsUnderRoot $root $Depth)) {
      $hit = Test-KvsCandidate $candidate
      if ($hit) { return $hit }
    }
  }
  return ''
}

function Get-ConfigCandidates([string]$ExplicitPath) {
  $paths = New-Object System.Collections.Generic.List[string]
  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) { $paths.Add($ExplicitPath) | Out-Null }
  if ($env:KV_STUDIO_OPERATOR_CONFIG) { $paths.Add($env:KV_STUDIO_OPERATOR_CONFIG) | Out-Null }
  if ($env:APPDATA) { $paths.Add((Join-Path $env:APPDATA 'Codex\kv-studio-operator\config.json')) | Out-Null }
  $skillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
  $skillsRoot = Split-Path -Parent $skillRoot
  $paths.Add((Join-Path $skillsRoot 'kv-studio-operator\config\kv-studio-operator.local.json')) | Out-Null
  return $paths
}

function Get-ConfigKvs([string]$ExplicitPath) {
  foreach ($path in (Get-ConfigCandidates $ExplicitPath)) {
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    Add-Checked ('config ' + $path)
    $config = $null
    try { $config = Get-Content -Raw -LiteralPath $path -Encoding UTF8 | ConvertFrom-Json } catch { $config = $null }
    if ($config -and $config.kvs_exe) {
      $hit = Test-KvsCandidate ([string]$config.kvs_exe)
      if ($hit) { return $hit }
    }
  }
  return ''
}

function Get-RegistryValuePaths([string]$KeyPath) {
  $values = @()
  try { $values = @(Get-ItemProperty -LiteralPath $KeyPath -ErrorAction SilentlyContinue) } catch { $values = @() }
  $result = New-Object System.Collections.Generic.List[string]
  foreach ($value in $values) {
    foreach ($property in $value.PSObject.Properties) {
      if ($property.Name -like 'PS*') { continue }
      $data = [string]$property.Value
      if ($data -match 'Kvs\.exe') { $result.Add($data) | Out-Null }
    }
  }
  return $result
}

function Get-RegistryKvs() {
  $appPathKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Kvs.exe',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\Kvs.exe',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Kvs.exe'
  )
  foreach ($key in $appPathKeys) {
    if (-not (Test-Path -LiteralPath $key)) { continue }
    Add-Checked ('registry ' + $key)
    $value = $null
    try { $value = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).'(default)' } catch { $value = $null }
    $hit = Test-KvsCandidate ([string]$value)
    if ($hit) { return $hit }
  }

  $uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  $installRoots = New-Object System.Collections.Generic.List[string]
  foreach ($pattern in $uninstallKeys) {
    $entries = @()
    try { $entries = @(Get-ItemProperty -Path $pattern -ErrorAction SilentlyContinue) } catch { $entries = @() }
    foreach ($entry in $entries) {
      $name = [string]$entry.DisplayName
      if ($name -notmatch 'KV\s*STUDIO') { continue }
      if ($name -match 'Documents') { continue }
      foreach ($candidateRoot in @([string]$entry.InstallLocation, [string]$entry.DisplayIcon)) {
        if ([string]::IsNullOrWhiteSpace($candidateRoot)) { continue }
        $root = $candidateRoot.Trim().Trim('"')
        if ($root -match 'Kvs\.exe') { $root = Split-Path -Parent $root }
        $installRoots.Add($root) | Out-Null
        Add-Checked ('registry uninstall ' + $name + ' -> ' + $root)
      }
    }
  }
  $hit = Get-KvsFromRoots $installRoots.ToArray() $MaxScanDepth
  if ($hit) { return $hit }

  foreach ($keyRoot in @('HKLM:\SOFTWARE\WOW6432Node\KEYENCE', 'HKLM:\SOFTWARE\KEYENCE', 'HKCU:\SOFTWARE\KEYENCE')) {
    if (-not (Test-Path -LiteralPath $keyRoot)) { continue }
    Add-Checked ('registry ' + $keyRoot)
    foreach ($value in (Get-RegistryValuePaths $keyRoot)) {
      $hit = Test-KvsCandidate $value
      if ($hit) { return $hit }
      $hit = Get-KvsFromRoots @((Split-Path -Parent $value)) $MaxScanDepth
      if ($hit) { return $hit }
    }
  }
  return ''
}

function Get-ShortcutKvs([string[]]$Roots, [string[]]$ExplicitShortcuts) {
  $shortcuts = New-Object System.Collections.Generic.List[string]
  foreach ($path in $ExplicitShortcuts) {
    if (-not [string]::IsNullOrWhiteSpace($path)) { $shortcuts.Add($path) | Out-Null }
  }

  $rootsToScan = New-Object System.Collections.Generic.List[string]
  if ($Roots.Count) {
    # explicit roots replace the machine defaults so callers can test in isolation
    foreach ($root in $Roots) {
      if (-not [string]::IsNullOrWhiteSpace($root)) { $rootsToScan.Add($root) | Out-Null }
    }
  } else {
    $shortcuts.Add('C:\ProgramData\Microsoft\Windows\Start Menu\Programs\KEYENCE KV STUDIO Ver.12G\KV STUDIO Ver.12G.lnk') | Out-Null
    if ($env:ProgramData) { $rootsToScan.Add((Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')) | Out-Null }
    if ($env:APPDATA) { $rootsToScan.Add((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')) | Out-Null }
  }

  foreach ($directory in @($rootsToScan)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
    Add-Checked ('shortcuts ' + $directory)
    try {
      $candidates = @(Get-ChildItem -LiteralPath $directory -Filter '*.lnk' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'KV\s*STUDIO' -or $_.DirectoryName -match 'KEYENCE' })
      foreach ($item in $candidates) { $shortcuts.Add($item.FullName) | Out-Null }
    } catch { }
  }

  $shell = $null
  foreach ($shortcut in ($shortcuts | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $shortcut -PathType Leaf)) { continue }
    Add-Checked ('shortcut ' + $shortcut)
    if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
    $target = ''
    try { $target = [string]$shell.CreateShortcut($shortcut).TargetPath } catch { $target = '' }
    if ([string]::IsNullOrWhiteSpace($target)) { continue }
    $hit = Test-KvsCandidate $target
    if ($hit) { return @{ Exe = $hit; Launcher = $target; Shortcut = $shortcut } }
    $hit = Get-KvsFromRoots @((Split-Path -Parent $target)) $MaxScanDepth
    if ($hit) { return @{ Exe = $hit; Launcher = $target; Shortcut = $shortcut } }
  }
  return $null
}

function Get-DefaultSearchRoots() {
  $roots = New-Object System.Collections.Generic.List[string]
  $drives = @()
  try { $drives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue) } catch { $drives = @() }
  foreach ($drive in $drives) {
    if (-not $drive.Root -or $drive.Root -notmatch '^[A-Za-z]:\\$') { continue }
    # never walk a mapped network share: the bounded scan must stay fast and local
    if ($drive.DisplayRoot -and $drive.DisplayRoot -like '\\*') { continue }
    foreach ($relative in @('Keyence', 'KEYENCE', 'KeyenceAgent', 'Program Files\KEYENCE', 'Program Files (x86)\KEYENCE')) {
      $roots.Add((Join-Path $drive.Root $relative)) | Out-Null
    }
  }
  return $roots
}

function Get-KvsVersion([string]$Path) {
  try { return (Get-Item -LiteralPath $Path).VersionInfo.FileVersion } catch { return '' }
}

function Get-CacheFile([string]$ExplicitPath) {
  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ExplicitPath))
  }
  $localRoot = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
  return (Join-Path $localRoot 'KeyenceAgent\state\kvstudio_install.json')
}

function Save-Cache([string]$Path, [string]$Exe) {
  try {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [pscustomobject]@{ kvs_exe = $Exe; detected_at = (Get-Date).ToString('o'); version = (Get-KvsVersion $Exe) } |
      ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
  } catch { }
}

function Stop-NotInstalled([string]$Mode) {
  $summary = ($script:Checked | Select-Object -First 25) -join '; '
  if ($script:Checked.Count -gt 25) { $summary = $summary + ('; (+' + ($script:Checked.Count - 25) + ' more)') }
  $message = 'KV STUDIO Kvs.exe not found. Checked: ' + $summary
  if ($Mode -eq 'probe') {
    [Console]::Error.WriteLine($message)
    exit 1
  }
  throw $message
}

# ---------------------------------------------------------------- resolution
$result = ''
$source = ''
$cached = $false
$shortcutHit = $null
$cacheFile = Get-CacheFile $CachePath

if (-not $SkipCache -and (Test-Path -LiteralPath $cacheFile -PathType Leaf)) {
  $cachedValue = ''
  try { $cachedValue = [string](Get-Content -Raw -LiteralPath $cacheFile -Encoding UTF8 | ConvertFrom-Json).kvs_exe } catch { $cachedValue = '' }
  if ($cachedValue) {
    Add-Checked ('cache ' + $cacheFile)
    $hit = Test-KvsCandidate $cachedValue
    if ($hit) { $result = $hit; $source = 'cache'; $cached = $true }
  }
}

if (-not $result -and -not [string]::IsNullOrWhiteSpace($KvsExe)) {
  $hit = Test-KvsCandidate $KvsExe
  if ($hit) { $result = $hit; $source = 'parameter' }
}

if (-not $result -and -not $SkipConfig) {
  $hit = Get-ConfigKvs $ConfigPath
  if ($hit) { $result = $hit; $source = 'config' }
}

if (-not $result -and -not $SkipRegistry) {
  $hit = Get-RegistryKvs
  if ($hit) { $result = $hit; $source = 'registry' }
}

if (-not $result -and -not $SkipStartMenu) {
  $shortcutHit = Get-ShortcutKvs $ShortcutRoots $ShortcutPath
  if ($shortcutHit) { $result = $shortcutHit.Exe; $source = 'shortcut' }
}

if (-not $result) {
  $roots = @()
  if ($SearchRoots.Count) { $roots = $SearchRoots }
  elseif (-not $SkipDriveScan) { $roots = @(Get-DefaultSearchRoots) }
  $hit = Get-KvsFromRoots $roots $MaxScanDepth
  if ($hit) { $result = $hit; $source = 'search_root' }
}

if (-not $result) {
  $legacy = @(
    'C:\Program Files (x86)\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe',
    'C:\Program Files (x86)\KEYENCE\KVS11G\KVS11\KVS\Kvs.exe',
    'C:\Program Files (x86)\KEYENCE\KVS12\KVS\Kvs.exe'
  )
  foreach ($candidate in $legacy) {
    $hit = Test-KvsCandidate $candidate
    if ($hit) { $result = $hit; $source = 'legacy_path'; break }
  }
}

if (-not $result) { Stop-NotInstalled $(if ($Probe) { 'probe' } else { 'json' }) }

if (-not $SkipCache -and -not $cached) { Save-Cache $cacheFile $result }

$payload = [pscustomobject]@{
  ok = $true
  KvsExe = $result
  WorkingDirectory = Split-Path -Parent $result
  Source = $source
  Version = Get-KvsVersion $result
  Cached = $cached
  LauncherPath = $(if ($shortcutHit) { [string]$shortcutHit.Launcher } else { '' })
  ShortcutPath = $(if ($shortcutHit) { [string]$shortcutHit.Shortcut } else { '' })
  CachePath = $cacheFile
  ElapsedMs = [int][math]::Round(((Get-Date) - $script:Started).TotalMilliseconds)
  CheckedCount = $script:Checked.Count
  Checked = @($script:Checked | Select-Object -First 25)
}

if ($OutDir) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'kvstudio_local.json') -Encoding UTF8
}

if ($Probe) {
  [Console]::Out.WriteLine($result)
  exit 0
}

$payload | ConvertTo-Json -Depth 4
