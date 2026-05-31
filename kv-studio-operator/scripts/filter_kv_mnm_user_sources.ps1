param(
  [Parameter(Mandatory=$true)]
  [string]$InputDir,

  [Parameter(Mandatory=$true)]
  [string]$OutputDir,

  [string]$ProjectPath = '',
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

function Get-ModuleInfo([string]$Path) {
  $lines = Get-Content -LiteralPath $Path -TotalCount 20 -ErrorAction Stop
  $moduleName = [IO.Path]::GetFileNameWithoutExtension($Path)
  $moduleType = $null
  foreach ($line in $lines) {
    if ($line -match '^;MODULE:(.+)$') { $moduleName = $Matches[1].Trim() }
    if ($line -match '^;MODULE_TYPE:(\d+)\s*$') { $moduleType = [int]$Matches[1] }
  }
  [pscustomobject]@{
    module_name = $moduleName
    module_type = $moduleType
  }
}

function Get-ProjectOfficialLibraryNames([string]$KprPath) {
  $names = New-Object 'System.Collections.Generic.HashSet[string]'
  if (-not $KprPath) { return $names }

  $projectDir = if (Test-Path -LiteralPath $KprPath -PathType Leaf) {
    Split-Path -Parent $KprPath
  } else {
    $KprPath
  }
  $treePath = Join-Path $projectDir 'WsTreeEnv.xml'
  if (-not (Test-Path -LiteralPath $treePath -PathType Leaf)) { return $names }

  $text = Get-Content -LiteralPath $treePath -Raw
  $matches = [regex]::Matches($text, '<value\.first>([^<]+)</value\.first>')
  foreach ($m in $matches) {
    $value = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value).Trim()
    if ($value -match '^([A-Za-z_][A-Za-z0-9_\[\]]+)(?::|\s+\[\d+\]$)') {
      $name = $Matches[1].Trim()
      if ($name -match '^(MC_|_MC_|\[MC\]_|_\[MC\]_|ModbusTCPClient_|SocketTCP_|UniversalLibrary$)') {
        [void]$names.Add($name)
      }
    }
  }
  return $names
}

function Get-OfficialFbReason([string]$Name, [System.Collections.Generic.HashSet[string]]$ProjectOfficialNames) {
  if ($ProjectOfficialNames.Contains($Name)) {
    return 'project WsTreeEnv.xml marks the name as an official/library item'
  }
  if ($Name -match '^(MC_|_MC_|\[MC\]_|_\[MC\]_)') {
    return 'motion-control official/library FB pattern confirmed by KEYENCE Wiki'
  }
  if ($Name -match '^(ModbusTCPClient_|SocketTCP_)') {
    return 'KEYENCE communication library FB naming pattern'
  }
  if ($Name -match '^(KV_|KL_|NU_|DL_).+_FB$') {
    return 'KEYENCE/module library FB naming pattern'
  }
  return ''
}

function Get-RelativePathCompat([string]$BasePath, [string]$ChildPath) {
  $baseFull = [IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
  $childFull = [IO.Path]::GetFullPath($ChildPath)
  $baseUri = New-Object System.Uri($baseFull)
  $childUri = New-Object System.Uri($childFull)
  return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($childUri).ToString()).Replace('/', '\')
}

if (-not (Test-Path -LiteralPath $InputDir -PathType Container)) {
  throw "InputDir not found: $InputDir"
}
if (-not $OutDir) {
  $OutDir = Join-Path $OutputDir '_filter_report'
}
New-Item -ItemType Directory -Force -Path $OutputDir, $OutDir | Out-Null

$inputRoot = [IO.Path]::GetFullPath($InputDir)
$outputRoot = [IO.Path]::GetFullPath($OutputDir)
$officialNames = Get-ProjectOfficialLibraryNames $ProjectPath
$classifications = @()

foreach ($file in Get-ChildItem -LiteralPath $inputRoot -Recurse -Filter '*.mnm' -File) {
  $info = Get-ModuleInfo $file.FullName
  $relative = Get-RelativePathCompat $inputRoot $file.FullName
  $target = Join-Path $outputRoot $relative
  $targetDir = Split-Path -Parent $target
  if ($targetDir) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }

  $classification = 'program_or_non_fb'
  $reason = 'module_type is not 2'
  $copied = $true

  if ($info.module_type -eq 2) {
    $officialReason = Get-OfficialFbReason $info.module_name $officialNames
    if ($officialReason) {
      $classification = 'official_or_library_fb'
      $reason = $officialReason
      $copied = $false
    } else {
      $classification = 'user_fb'
      $reason = 'module_type is 2 and no official/library evidence matched'
      $copied = $true
    }
  } elseif ($null -eq $info.module_type) {
    $classification = 'unknown_mnm'
    $reason = 'MODULE_TYPE header is missing; copied for review as non-FB source'
  }

  if ($copied) {
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
  }

  $classifications += [ordered]@{
    file = $file.FullName
    relative_path = $relative
    module_name = $info.module_name
    module_type = $info.module_type
    classification = $classification
    copied = $copied
    reason = $reason
  }
}

$result = [ordered]@{
  ok = $true
  input_dir = $inputRoot
  output_dir = $outputRoot
  project_path = $ProjectPath
  official_name_count = $officialNames.Count
  official_names = @($officialNames | Sort-Object)
  total_mnm = $classifications.Count
  copied_count = @($classifications | Where-Object { $_.copied }).Count
  excluded_official_fb_count = @($classifications | Where-Object { $_.classification -eq 'official_or_library_fb' }).Count
  user_fb_count = @($classifications | Where-Object { $_.classification -eq 'user_fb' }).Count
  classifications = $classifications
}

$resultPath = Join-Path $OutDir 'mnm_user_source_filter_result.json'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host "Wrote $resultPath"
