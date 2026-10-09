param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'

# Deterministic contract tests for KV STUDIO installation detection.
# The real machine state is used only for the final live check, which records
# what it found instead of failing on hosts without KV STUDIO.

$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$resolver = Join-Path $RepoRoot 'keyence-plc-programmer/scripts/resolve_kvstudio_local.ps1'
$wrapper = Join-Path $RepoRoot 'kv-studio-operator/scripts/get_kvstudio_install.ps1'
foreach ($required in @($resolver, $wrapper)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing required script: $required" }
}

$scratch = Join-Path $env:TEMP ('kvstudio-detect-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$checks = [System.Collections.Generic.List[object]]::new()

function New-StubKvs([string]$Path) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  Set-Content -LiteralPath $Path -Value 'stub' -Encoding ASCII
  # normalize 8.3 forms (ADMINI~1) so expectations match the resolver's FullName
  return (Get-Item -LiteralPath $Path -Force).FullName
}

function Invoke-Resolver([hashtable]$Arguments) {
  $argv = @()
  foreach ($key in $Arguments.Keys) {
    $value = $Arguments[$key]
    if ($value -is [switch] -or $value -is [bool]) { if ($value) { $argv += "-$key" } ; continue }
    $argv += @("-$key", [string]$value)
  }
  # expected failures write to stderr; keep them as data instead of terminating the test
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver @argv 2>&1)
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousPreference
  $json = $null
  try { $json = (@($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine | ConvertFrom-Json) } catch { $json = $null }
  return [pscustomobject]@{ exit_code = $exitCode; json = $json; text = @($output | ForEach-Object { [string]$_ }) }
}

function Assert-That([string]$Name, [bool]$Condition, [string]$Detail) {
  $checks.Add([pscustomobject]@{ name = $Name; ok = $Condition; detail = $Detail })
  if (-not $Condition) { throw "KV detection check failed: $Name ($Detail)" }
}

$isolated = @{
  SkipConfig = $true
  SkipRegistry = $true
  SkipStartMenu = $true
  SkipDriveScan = $true
  SkipCache = $true
}

# 1. explicit parameter wins and is reported as such
$explicitExe = New-StubKvs (Join-Path $scratch 'explicit\KVS12\KVS\Kvs.exe')
$explicit = Invoke-Resolver ($isolated + @{ KvsExe = $explicitExe })
Assert-That 'parameter_layer' ($explicit.exit_code -eq 0 -and $explicit.json.Source -eq 'parameter' -and $explicit.json.KvsExe -eq $explicitExe) ($explicit.json | ConvertTo-Json -Compress)

# 2. a path that is not named Kvs.exe must be rejected
$wrongName = New-StubKvs (Join-Path $scratch 'wrongname\Kvs.exe.bak')
$wrong = Invoke-Resolver ($isolated + @{ KvsExe = $wrongName })
Assert-That 'rejects_non_kvs_leaf' ($wrong.exit_code -ne 0 -and -not $wrong.json) "exit=$($wrong.exit_code)"

# 3. a directory named Kvs.exe must be rejected
$dirNamedExe = Join-Path $scratch 'dirnamed\KVS12\KVS\Kvs.exe'
New-Item -ItemType Directory -Force -Path $dirNamedExe | Out-Null
$dirCheck = Invoke-Resolver ($isolated + @{ KvsExe = $dirNamedExe })
Assert-That 'rejects_directory_candidate' ($dirCheck.exit_code -ne 0) "exit=$($dirCheck.exit_code)"

# 4. search root discovery
$searchRoot = Join-Path $scratch 'installroot'
$searchExe = New-StubKvs (Join-Path $searchRoot 'KVS12\KVS\Kvs.exe')
$searched = Invoke-Resolver ($isolated + @{ SearchRoots = $searchRoot })
Assert-That 'search_root_layer' ($searched.exit_code -eq 0 -and $searched.json.Source -eq 'search_root' -and $searched.json.KvsExe -eq $searchExe) ($searched.json | ConvertTo-Json -Compress)

# 5. KvsVersionPath.txt selects the version the launcher points at
$pointerRoot = Join-Path $scratch 'pointer'
$pointerExe = New-StubKvs (Join-Path $pointerRoot 'KVS11\KVS\Kvs.exe')
$null = New-StubKvs (Join-Path $pointerRoot 'KVS12\KVS\Kvs.exe')
Set-Content -LiteralPath (Join-Path $pointerRoot 'KvsVersionPath.txt') -Value 'KVS11G' -Encoding ASCII
$pointer = Invoke-Resolver ($isolated + @{ SearchRoots = $pointerRoot })
Assert-That 'version_pointer_layer' ($pointer.exit_code -eq 0 -and $pointer.json.KvsExe -eq $pointerExe) ($pointer.json | ConvertTo-Json -Compress)

# 6. without the pointer the newest KVS<version> wins
$newestRoot = Join-Path $scratch 'newest'
$newestExe = New-StubKvs (Join-Path $newestRoot 'KVS13\KVS\Kvs.exe')
$null = New-StubKvs (Join-Path $newestRoot 'KVS11\KVS\Kvs.exe')
$newest = Invoke-Resolver ($isolated + @{ SearchRoots = $newestRoot })
Assert-That 'newest_version_preferred' ($newest.exit_code -eq 0 -and $newest.json.KvsExe -eq $newestExe) ($newest.json | ConvertTo-Json -Compress)

# 7. operator config kvs_exe layer
$configExe = New-StubKvs (Join-Path $scratch 'configinstall\KVS12\KVS\Kvs.exe')
$configPath = Join-Path $scratch 'config.json'
[pscustomobject]@{ kvs_exe = $configExe } | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
$configured = Invoke-Resolver (@{ ConfigPath = $configPath; SkipRegistry = $true; SkipStartMenu = $true; SkipDriveScan = $true; SkipCache = $true })
Assert-That 'config_layer' ($configured.exit_code -eq 0 -and $configured.json.Source -eq 'config' -and $configured.json.KvsExe -eq $configExe) ($configured.json | ConvertTo-Json -Compress)

# 8. cache hit, and a stale cache entry must not be reported
$cacheExe = New-StubKvs (Join-Path $scratch 'cacheinstall\KVS12\KVS\Kvs.exe')
$cachePath = Join-Path $scratch 'cache.json'
[pscustomobject]@{ kvs_exe = $cacheExe } | ConvertTo-Json | Set-Content -LiteralPath $cachePath -Encoding UTF8
$cacheArgs = $isolated.Clone()
$cacheArgs['SkipCache'] = $false
$cacheArgs['CachePath'] = $cachePath
$cached = Invoke-Resolver $cacheArgs
Assert-That 'cache_layer' ($cached.exit_code -eq 0 -and $cached.json.Source -eq 'cache' -and $cached.json.Cached -eq $true) ($cached.json | ConvertTo-Json -Compress)

$stalePath = Join-Path $scratch 'stale.json'
[pscustomobject]@{ kvs_exe = (Join-Path $scratch 'gone\Kvs.exe') } | ConvertTo-Json | Set-Content -LiteralPath $stalePath -Encoding UTF8
$staleArgs = $isolated.Clone()
$staleArgs['SkipCache'] = $false
$staleArgs['CachePath'] = $stalePath
$stale = Invoke-Resolver $staleArgs
Assert-That 'stale_cache_rejected' ($stale.exit_code -ne 0) "exit=$($stale.exit_code)"

# 9. Start Menu shortcut layer
$shortcutRoot = Join-Path $scratch 'startmenu'
$shortcutDir = Join-Path $shortcutRoot 'KEYENCE KV STUDIO Ver.12G'
New-Item -ItemType Directory -Force -Path $shortcutDir | Out-Null
$launcherRoot = Join-Path $scratch 'launcherinstall'
$launcher = New-StubKvs (Join-Path $launcherRoot 'KvsLauncher.exe')
$shortcutExe = New-StubKvs (Join-Path $launcherRoot 'KVS12\KVS\Kvs.exe')
$lnkPath = Join-Path $shortcutDir 'KV STUDIO Ver.12G.lnk'
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = $launcher
$lnk.Save()
$shortcut = Invoke-Resolver (@{ ShortcutRoots = $shortcutRoot; SkipConfig = $true; SkipRegistry = $true; SkipDriveScan = $true; SkipCache = $true })
Assert-That 'shortcut_layer' ($shortcut.exit_code -eq 0 -and $shortcut.json.Source -eq 'shortcut' -and $shortcut.json.KvsExe -eq $shortcutExe -and $shortcut.json.LauncherPath -eq $launcher) ($shortcut.json | ConvertTo-Json -Compress)

# 10. not-installed contract: JSON mode fails, probe mode exits 1
$emptyRoot = Join-Path $scratch 'empty'
New-Item -ItemType Directory -Force -Path $emptyRoot | Out-Null
$absent = Invoke-Resolver ($isolated + @{ SearchRoots = $emptyRoot })
Assert-That 'not_installed_fails_loud' ($absent.exit_code -ne 0 -and -not $absent.json -and (@($absent.text) -join ' ') -match 'KV STUDIO Kvs.exe not found') "exit=$($absent.exit_code)"
$absentProbe = Invoke-Resolver ($isolated + @{ SearchRoots = $emptyRoot; Probe = $true })
Assert-That 'not_installed_probe_exit_1' ($absentProbe.exit_code -eq 1) "exit=$($absentProbe.exit_code)"

# 11. live detection on this machine (recorded, not required)
$live = Invoke-Resolver @{}
$livePresent = ($live.exit_code -eq 0 -and $live.json -and (Split-Path -Leaf ([string]$live.json.KvsExe)) -ieq 'Kvs.exe')
if ($livePresent) {
  Assert-That 'live_detection_shape' ([bool]$live.json.Source -and [bool]$live.json.WorkingDirectory) ($live.json | ConvertTo-Json -Compress)
}

# 12. discoverable operator entry point agrees with the resolver
$wrapperOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapper 2>&1)
$wrapperExit = $LASTEXITCODE
$wrapperJson = $null
try { $wrapperJson = (@($wrapperOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine | ConvertFrom-Json) } catch { $wrapperJson = $null }
if ($livePresent) {
  Assert-That 'wrapper_reports_installed' ($wrapperExit -eq 0 -and $wrapperJson.installed -eq $true -and $wrapperJson.kvs_exe -eq $live.json.KvsExe) ($wrapperJson | ConvertTo-Json -Compress)
  $probeOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapper -Probe 2>$null)
  $probeExit = $LASTEXITCODE
  Assert-That 'wrapper_probe_contract' ($probeExit -eq 0 -and ([string]($probeOutput | Select-Object -First 1)).Trim() -eq [string]$live.json.KvsExe) "exit=$probeExit"
} else {
  Assert-That 'wrapper_reports_not_installed' ($wrapperExit -eq 2 -and $wrapperJson.installed -eq $false -and $wrapperJson.error_code -eq 'KV_NOT_INSTALLED') ($wrapperJson | ConvertTo-Json -Compress)
}

Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue

[pscustomobject]@{
  ok = $true
  operation = 'detect local KV STUDIO installation'
  checks = @($checks)
  check_count = $checks.Count
  live_installed = $livePresent
  live_kvs_exe = $(if ($livePresent) { [string]$live.json.KvsExe } else { '' })
  live_source = $(if ($livePresent) { [string]$live.json.Source } else { '' })
} | ConvertTo-Json -Depth 6
