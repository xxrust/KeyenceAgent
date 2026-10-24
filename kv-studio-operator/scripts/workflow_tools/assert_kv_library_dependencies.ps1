param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [string[]]$RequiredLibrary = @(),
  [string[]]$RequiredFbNamePrefix = @(),
  [Parameter(Mandatory=$true)][string]$OutDir
)

$ErrorActionPreference = 'Stop'

# Universal Library device FBs are not installed by a separate "library import".
# KV STUDIO generates them from the EtherCAT device support files when the node
# is configured: a fresh project has no 功能块 > UniversalLibrary tree, and after
# configuring SV630_1Axis_03713 the tree contains
# UniversalLibrary > Motor > Inovance_SV630N_V100 > MC_*_INOVA_SV630N_V100.
#
# This tool asserts that the libraries a scaffold/program will call actually
# exist in the saved project tree, so a missing EtherCAT configuration fails
# before the user MNM import instead of surfacing as missing FB types later.
#
# Exit codes: 0 = present, 1 = missing (KV_LIBRARY_* code in the result).

function Resolve-TreePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { throw 'KV_LIBRARY_INPUT_INVALID: -ProjectPath is empty.' }
  $full = [IO.Path]::GetFullPath($Path)
  if (Test-Path -LiteralPath $full -PathType Leaf) {
    if ([IO.Path]::GetExtension($full) -ieq '.xml') { return $full }
    return (Join-Path (Split-Path -Parent $full) 'WsTreeEnv.xml')
  }
  if (Test-Path -LiteralPath $full -PathType Container) { return (Join-Path $full 'WsTreeEnv.xml') }
  throw "KV_LIBRARY_INPUT_INVALID: project path not found: $full"
}

function Get-TreeNodes([string]$XmlPath) {
  [xml]$doc = Get-Content -LiteralPath $XmlPath -Raw -Encoding UTF8
  $items = New-Object System.Collections.Generic.List[object]
  $walk = {
    param($container, $path)
    if ($null -eq $container) { return }
    foreach ($child in @($container.Child)) {
      $text = ([string]$child.'value.first').Trim()
      $current = $path
      if ($text) {
        $current = @($path) + $text
        $items.Add([pscustomobject]@{ text = $text; path = $current; path_text = ($current -join ' > ') })
      }
      # The document wrapper may carry an empty value.first; still descend so
      # its value.second children are not dropped.
      $walk.Invoke($child.'value.second', $current)
    }
  }
  $walk.Invoke($doc.Root, @())
  return $items.ToArray()
}

function Test-IsUnder([object[]]$NodePath, [object[]]$ParentPath) {
  if ($NodePath.Count -le $ParentPath.Count) { return $false }
  for ($i = 0; $i -lt $ParentPath.Count; $i++) {
    if ([string]$NodePath[$i] -ne [string]$ParentPath[$i]) { return $false }
  }
  return $true
}

function Test-FbText([string]$Text) {
  return ($Text -match '^[A-Za-z_][A-Za-z0-9_]*\s*:')
}

try {
  $treePath = Resolve-TreePath $ProjectPath
  if (-not (Test-Path -LiteralPath $treePath -PathType Leaf)) {
    throw "KV_LIBRARY_TREE_MISSING: WsTreeEnv.xml not found: $treePath"
  }
  $nodes = @(Get-TreeNodes $treePath)

  $libraryRoot = $null
  foreach ($node in $nodes) {
    if ($node.text -eq 'UniversalLibrary') { $libraryRoot = $node; break }
  }

  $libraries = New-Object System.Collections.Generic.List[object]
  $allFbNames = @()
  if ($libraryRoot) {
    $rootPath = @($libraryRoot.path)
    $fbNodes = @($nodes | Where-Object { (Test-IsUnder $_.path $rootPath) -and (Test-FbText $_.text) })
    $allFbNames = @($fbNodes | ForEach-Object { ($_.text -split ':', 2)[0].Trim() } | Select-Object -Unique)
    foreach ($node in $nodes) {
      if (-not (Test-IsUnder $node.path $rootPath)) { continue }
      if (Test-FbText $node.text) { continue }
      $childFbs = @($fbNodes | Where-Object { Test-IsUnder $_.path $node.path })
      if ($childFbs.Count -eq 0) { continue }
      # Keep only the deepest folder that owns FBs (the vendor folder), not the
      # category folder above it (Motor / EtherCAT / ...).
      $deeperLibraryCount = 0
      foreach ($inner in $nodes) {
        if (Test-FbText $inner.text) { continue }
        if (-not (Test-IsUnder $inner.path $node.path)) { continue }
        if (@($fbNodes | Where-Object { Test-IsUnder $_.path $inner.path }).Count -gt 0) { $deeperLibraryCount++ }
      }
      if ($deeperLibraryCount -gt 0) { continue }
      $names = @($childFbs | ForEach-Object { ($_.text -split ':', 2)[0].Trim() } | Select-Object -Unique)
      $libraries.Add([pscustomobject]@{
        name = $node.text
        fb_count = $names.Count
        fb_sample = @($names | Select-Object -First 8)
      })
    }
  }

  $missingLibraries = @()
  foreach ($required in @($RequiredLibrary | Where-Object { $_ })) {
    $hit = @($libraries | Where-Object { $_.name -ieq $required })
    if ($hit.Count -eq 0) { $missingLibraries += $required }
  }

  $missingPrefixes = @()
  foreach ($requiredPrefix in @($RequiredFbNamePrefix | Where-Object { $_ })) {
    $hit = @($allFbNames | Where-Object { $_.StartsWith($requiredPrefix, [StringComparison]::OrdinalIgnoreCase) })
    if ($hit.Count -eq 0) { $missingPrefixes += $requiredPrefix }
  }

  $errorCode = ''
  $message = ''
  if ($libraries.Count -eq 0 -and (@($RequiredLibrary).Count -gt 0 -or @($RequiredFbNamePrefix).Count -gt 0)) {
    $errorCode = 'KV_LIBRARY_TREE_MISSING'
    $message = "Project has no 功能块 > UniversalLibrary entries. Configure the EtherCAT device node first; the library FBs are generated from the device support files. Tree: $treePath"
  } elseif ($missingLibraries.Count -gt 0) {
    $errorCode = 'KV_LIBRARY_VENDOR_MISSING'
    $message = "UniversalLibrary vendor folder(s) not found: $($missingLibraries -join ', '). Available: $(@($libraries | ForEach-Object { $_.name }) -join ', ')."
  } elseif ($missingPrefixes.Count -gt 0) {
    $errorCode = 'KV_LIBRARY_FB_MISSING'
    $message = "No UniversalLibrary FB name starts with: $($missingPrefixes -join ', '). Available FB count: $($allFbNames.Count)."
  }

  $outRoot = [IO.Path]::GetFullPath($OutDir)
  New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
  $resultPath = Join-Path $outRoot 'library_dependency_result.json'
  $ok = [string]::IsNullOrEmpty($errorCode)
  [ordered]@{
    ok = $ok
    error_code = $errorCode
    message = $message
    project_path = [IO.Path]::GetFullPath($ProjectPath)
    tree_path = $treePath
    universal_library_present = [bool]$libraryRoot
    required_libraries = @($RequiredLibrary)
    required_fb_prefixes = @($RequiredFbNamePrefix)
    libraries = $libraries.ToArray()
    missing_libraries = $missingLibraries
    missing_prefixes = $missingPrefixes
    universal_library_fb_count = $allFbNames.Count
    evidence = @($resultPath)
    generated_at = (Get-Date).ToString('o')
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

  if (-not $ok) {
    [Console]::Error.WriteLine("$errorCode : $message")
    [Console]::Error.WriteLine("KV_LIBRARY_EVIDENCE: $resultPath")
    exit 1
  }
  [ordered]@{
    ok = $true
    universal_library_present = $true
    libraries = @($libraries | ForEach-Object { $_.name })
    fb_count = $allFbNames.Count
    result_path = $resultPath
  } | ConvertTo-Json -Depth 4
} catch {
  $message = $_.Exception.Message
  if ($message -notmatch '^(KV_[A-Z0-9_]+)') { $message = "KV_LIBRARY_INTERNAL_ERROR: $message" }
  try {
    $outRoot = [IO.Path]::GetFullPath($OutDir)
    New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
    $resultPath = Join-Path $outRoot 'library_dependency_result.json'
    [ordered]@{
      ok = $false
      error_code = if ($message -match '^(KV_[A-Z0-9_]+)') { $Matches[1] } else { 'KV_LIBRARY_INTERNAL_ERROR' }
      message = $message
      detail = $_.Exception.ToString()
      position = $_.InvocationInfo.PositionMessage
      project_path = $ProjectPath
      evidence = @($resultPath)
      generated_at = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    [Console]::Error.WriteLine($message)
    [Console]::Error.WriteLine("KV_LIBRARY_EVIDENCE: $resultPath")
  } catch {
    [Console]::Error.WriteLine($message)
  }
  exit 1
}
