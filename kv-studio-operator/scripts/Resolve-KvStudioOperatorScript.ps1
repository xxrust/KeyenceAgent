function Get-KvStudioOperatorScriptsRoot {
  param([string]$StartPath = $PSCommandPath)

  $dir = if ($StartPath -and (Test-Path -LiteralPath $StartPath -PathType Leaf)) {
    Split-Path -Parent $StartPath
  } elseif ($StartPath) {
    $StartPath
  } else {
    Split-Path -Parent $PSCommandPath
  }

  $dir = [IO.Path]::GetFullPath($dir)
  while ($dir) {
    if (Test-Path -LiteralPath (Join-Path $dir 'script_manifest.json') -PathType Leaf) {
      return $dir
    }
    $parent = Split-Path -Parent $dir
    if (-not $parent -or $parent -eq $dir) { break }
    $dir = $parent
  }
  throw "KV STUDIO operator scripts root not found from: $StartPath"
}

function Get-KvStudioOperatorScriptManifest {
  param([string]$ScriptRoot = '')

  if (-not $ScriptRoot) { $ScriptRoot = Get-KvStudioOperatorScriptsRoot }
  $path = Join-Path $ScriptRoot 'script_manifest.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Script manifest is required: $path" }
  Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-KvStudioOperatorManifestEntries {
  param(
    [string]$ScriptRoot = '',
    [string[]]$Classes = @()
  )

  $manifest = Get-KvStudioOperatorScriptManifest -ScriptRoot $ScriptRoot
  $entries = @()
  foreach ($prop in @($manifest.classes.PSObject.Properties)) {
    if ($Classes.Count -gt 0 -and $Classes -notcontains $prop.Name) { continue }
    foreach ($entry in @($prop.Value)) {
      $entry | Add-Member -NotePropertyName class -NotePropertyValue $prop.Name -Force
      $entries += $entry
    }
  }
  $entries
}

function Resolve-KvStudioOperatorScriptPath {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Name,
    [string]$ScriptRoot = '',
    [string[]]$Classes = @()
  )

  if (-not $ScriptRoot) { $ScriptRoot = Get-KvStudioOperatorScriptsRoot }
  $ScriptRoot = [IO.Path]::GetFullPath($ScriptRoot).TrimEnd('\', '/')
  $prefix = $ScriptRoot + [IO.Path]::DirectorySeparatorChar
  $normalized = $Name.Replace('\', '/')
  if ([IO.Path]::IsPathRooted($Name) -or $normalized.Contains('/')) {
    $candidate = if ([IO.Path]::IsPathRooted($Name)) { [IO.Path]::GetFullPath($Name) } else { [IO.Path]::GetFullPath((Join-Path $ScriptRoot $Name)) }
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "KV_SCRIPT_OUTSIDE_ROOT: $Name"
    }
    $normalized = $candidate.Substring($prefix.Length).Replace('\', '/')
  }
  $entries = @(Get-KvStudioOperatorManifestEntries -ScriptRoot $ScriptRoot -Classes $Classes)
  $matches = @($entries | Where-Object {
    $entryPath = ([string]$_.path).Replace('\', '/')
    $entryLeaf = Split-Path -Leaf $entryPath
    $entryPath -eq $normalized -or $entryLeaf -eq $normalized
  })
  if ($matches.Count -eq 0) { throw "Script is not declared in script_manifest.json: $Name" }
  if ($matches.Count -gt 1) {
    $paths = @($matches | ForEach-Object { $_.path }) -join ', '
    throw "Script name is ambiguous in script_manifest.json: $Name -> $paths"
  }

  $path = [IO.Path]::GetFullPath((Join-Path $ScriptRoot ([string]$matches[0].path)))
  if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "KV_SCRIPT_OUTSIDE_ROOT: $path" }
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Declared script is missing: $path" }
  $path
}
