param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectName,

  [Parameter(Mandatory=$true)]
  [string]$NetworkConfigPath,

  [string]$OutDir = '',
  [switch]$SkipEthernetIp,
  [switch]$SkipEtherCat
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath
$ethernetScript = Join-Path $scriptRoot 'configure_kv_ethernet_ip_device.ps1'
$ethercatScript = Join-Path $scriptRoot 'configure_kv_ethercat_device.ps1'

if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'kv-studio-operator') 'kv_network_config_runs'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-JsonField {
  param($Object, [string[]]$Names, $Default = $null)
  if ($null -eq $Object) { return $Default }
  foreach ($name in $Names) {
    $property = $Object.PSObject.Properties[$name]
    if ($property -and $null -ne $property.Value) { return $property.Value }
  }
  $Default
}

function Write-JsonFile {
  param([string]$Path, $Value)
  $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-StepOutDir {
  param([string]$Kind, [int]$Index)
  $safeKind = $Kind -replace '[^A-Za-z0-9_.-]', '_'
  $path = Join-Path $OutDir ('{0}_{1:D2}' -f $safeKind, $Index)
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  $path
}

function ConvertTo-ProcessArgumentString {
  param([string[]]$Arguments)
  ($Arguments | ForEach-Object {
    $value = [string]$_
    if ($value -notmatch '[\s"]') { return $value }
    '"' + ($value -replace '"', '\"') + '"'
  }) -join ' '
}

function Invoke-ChildScript {
  param([string]$ScriptPath, [string[]]$Arguments, [string]$StepOutDir)
  if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Child script not found: $ScriptPath"
  }
  $stdoutPath = Join-Path $StepOutDir 'stdout.txt'
  $stderrPath = Join-Path $StepOutDir 'stderr.txt'
  $argumentList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$ScriptPath) + $Arguments
  $argumentString = ConvertTo-ProcessArgumentString -Arguments $argumentList
  $process = Start-Process -FilePath 'powershell.exe' `
    -ArgumentList $argumentString `
    -WindowStyle Hidden `
    -PassThru `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath
  if (-not $process.WaitForExit(300000)) {
    try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
    $exitCode = 124
  } else {
    $process.Refresh()
    $exitCode = $process.ExitCode
  }
  $resultJson = @(Get-ChildItem -LiteralPath $StepOutDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName })
  $resultJsonOk = $false
  if ($resultJson.Count -gt 0) {
    try {
      $parsedResult = Get-Content -LiteralPath $resultJson[0] -Raw -Encoding UTF8 | ConvertFrom-Json
      $resultJsonOk = [bool]$parsedResult.ok
    } catch {
      $resultJsonOk = $false
    }
  }
  if ($null -eq $exitCode -and $resultJsonOk) { $exitCode = 0 }
  [pscustomobject]@{
    exit_code = $exitCode
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
    stdout_length = if (Test-Path -LiteralPath $stdoutPath) { (Get-Item -LiteralPath $stdoutPath).Length } else { 0 }
    stderr_length = if (Test-Path -LiteralPath $stderrPath) { (Get-Item -LiteralPath $stderrPath).Length } else { 0 }
    result_json_ok = $resultJsonOk
    result_json = $resultJson
  }
}

function Get-DeviceArray {
  param($Parent)
  $devices = Get-JsonField -Object $Parent -Names @('devices') -Default @()
  if ($null -eq $devices) { return @() }
  @($devices)
}

try {
  $NetworkConfigPath = [IO.Path]::GetFullPath($NetworkConfigPath)
  if (-not (Test-Path -LiteralPath $NetworkConfigPath -PathType Leaf)) {
    throw "NetworkConfigPath not found: $NetworkConfigPath"
  }
  $config = Get-Content -LiteralPath $NetworkConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ([int](Get-JsonField -Object $config -Names @('schema_version','schemaVersion') -Default 0) -ne 1) {
    throw 'network_config schema_version must be 1.'
  }
  if ([string](Get-JsonField -Object $config -Names @('route') -Default '') -ne 'project_tree_unit_configuration') {
    throw 'network_config route must be project_tree_unit_configuration.'
  }

  $steps = @()
  $ok = $true
  $requestedEthernetIpCount = 0
  $requestedEtherCatCount = 0

  if (-not $SkipEthernetIp) {
    $ethernetDevices = @(Get-DeviceArray -Parent (Get-JsonField -Object $config -Names @('ethernet_ip','ethernetIp','ethernet') -Default $null))
    $requestedEthernetIpCount = $ethernetDevices.Count
    for ($i = 0; $i -lt $ethernetDevices.Count; $i++) {
      $device = $ethernetDevices[$i]
      $stepOut = New-StepOutDir -Kind 'ethernet_ip' -Index ($i + 1)
      $deviceNamePattern = [string](Get-JsonField -Object $device -Names @('device_name_pattern','deviceNamePattern','device_name','deviceName','name') -Default '')
      $nodeAddress = [string](Get-JsonField -Object $device -Names @('node_address','nodeAddress','node') -Default '')
      $ipAddress = [string](Get-JsonField -Object $device -Names @('ip_address','ipAddress','ip') -Default '')
      $variableNamePrefix = [string](Get-JsonField -Object $device -Names @('variable_name_prefix','variableNamePrefix','prefix') -Default '')
      $variableNames = @(Get-JsonField -Object $device -Names @('variable_names','variableNames') -Default @())
      if (-not $deviceNamePattern) { throw "ethernet_ip.devices[$i].device_name_pattern is required." }
      if (-not $nodeAddress) { throw "ethernet_ip.devices[$i].node_address is required." }
      if (-not $ipAddress) { throw "ethernet_ip.devices[$i].ip_address is required." }
      $args = @(
        '-ProjectName', $ProjectName,
        '-DeviceNamePattern', $deviceNamePattern,
        '-NodeAddress', $nodeAddress,
        '-IpAddress', $ipAddress,
        '-OutDir', $stepOut
      )
      if ($variableNamePrefix) { $args += @('-VariableNamePrefix', $variableNamePrefix) }
      if ($variableNames.Count -gt 0) { $args += @('-VariableNames') + @($variableNames | ForEach-Object { [string]$_ }) }
      $child = Invoke-ChildScript -ScriptPath $ethernetScript -Arguments $args -StepOutDir $stepOut
      if ($child.exit_code -ne 0) { $ok = $false }
      $steps += [pscustomobject]@{
        kind = 'ethernet_ip'
        index = $i
        request = $device
        out_dir = $stepOut
        child = $child
      }
      if (-not $ok) { break }
    }
  }

  if ($ok -and -not $SkipEtherCat) {
    $ethercatDevices = @(Get-DeviceArray -Parent (Get-JsonField -Object $config -Names @('ethercat','ether_cat') -Default $null))
    $requestedEtherCatCount = $ethercatDevices.Count
    for ($i = 0; $i -lt $ethercatDevices.Count; $i++) {
      $device = $ethercatDevices[$i]
      $stepOut = New-StepOutDir -Kind 'ethercat' -Index ($i + 1)
      $devicePath = @(Get-JsonField -Object $device -Names @('device_path','devicePath','path') -Default @())
      if ($devicePath.Count -eq 0) {
        $pathText = [string](Get-JsonField -Object $device -Names @('device_path_text','devicePathText') -Default '')
        if ($pathText) { $devicePath = @($pathText) }
      }
      if ($devicePath.Count -eq 0) { throw "ethercat.devices[$i].device_path is required." }
      $batchAxisRegistration = [string](Get-JsonField -Object $device -Names @('batch_axis_registration','batchAxisRegistration') -Default 'No')
      $esiPath = [string](Get-JsonField -Object $device -Names @('esi_path','esiPath','esi_file','esiFile') -Default '')
      if ($esiPath) {
        throw 'KV_ETHERCAT_ESI_REGISTRATION_UNSTABLE: network_config ethercat.devices[].esi_path is reserved, but ESI registration is not accepted as a stable script route yet.'
      }
      $args = @(
        '-ProjectName', $ProjectName,
        '-DevicePath', (($devicePath | ForEach-Object { [string]$_ }) -join ','),
        '-BatchAxisRegistration', $batchAxisRegistration,
        '-OutDir', $stepOut
      )
      $child = Invoke-ChildScript -ScriptPath $ethercatScript -Arguments $args -StepOutDir $stepOut
      if ($child.exit_code -ne 0) { $ok = $false }
      $steps += [pscustomobject]@{
        kind = 'ethercat'
        index = $i
        request = $device
        out_dir = $stepOut
        child = $child
      }
      if (-not $ok) { break }
    }
  }

  $result = [pscustomobject]@{
    ok = $ok
    project_name = $ProjectName
    network_config_path = $NetworkConfigPath
    out_dir = $OutDir
    requested_ethernet_ip_count = $requestedEthernetIpCount
    requested_ethercat_count = $requestedEtherCatCount
    steps = $steps
  }
  $resultPath = Join-Path $OutDir 'configure_kv_network_from_config_result.json'
  Write-JsonFile -Path $resultPath -Value $result
  $result | Add-Member -NotePropertyName result_path -NotePropertyValue $resultPath
  $result | ConvertTo-Json -Depth 16
  if (-not $ok) { exit 62 }
} catch {
  $failure = [pscustomobject]@{
    ok = $false
    project_name = $ProjectName
    network_config_path = $NetworkConfigPath
    error = $_.Exception.ToString()
  }
  $resultPath = Join-Path $OutDir 'configure_kv_network_from_config_result.json'
  Write-JsonFile -Path $resultPath -Value $failure
  $failure | ConvertTo-Json -Depth 8
  exit 1
}
