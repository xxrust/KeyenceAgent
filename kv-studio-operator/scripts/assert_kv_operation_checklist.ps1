param(
  [string]$ChecklistPath = '',
  [string[]]$SearchRoots = @(),
  [string]$OperationName = 'KV STUDIO operation'
)

$ErrorActionPreference = 'Stop'

function Get-ParentChain([string]$Path) {
  $result = @()
  if (-not $Path) { return $result }
  try {
    $itemPath = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $itemPath -PathType Leaf) {
      $itemPath = Split-Path -Parent $itemPath
    }
    while ($itemPath) {
      $result += $itemPath
      $parent = Split-Path -Parent $itemPath
      if (-not $parent -or $parent -eq $itemPath) { break }
      $itemPath = $parent
    }
  } catch {
    return $result
  }
  return $result
}

$candidates = @()
if ($ChecklistPath) { $candidates += [IO.Path]::GetFullPath($ChecklistPath) }
if ($env:KV_STUDIO_OPERATION_CHECKLIST) {
  $candidates += [IO.Path]::GetFullPath($env:KV_STUDIO_OPERATION_CHECKLIST)
}

foreach ($root in $SearchRoots) {
  foreach ($dir in (Get-ParentChain $root)) {
    $candidates += (Join-Path $dir 'CHECKLIST.md')
    $candidates += (Join-Path $dir 'kv_operation_checklist.md')
  }
}

$checklist = $null
foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
  if (Test-Path -LiteralPath $candidate -PathType Leaf) {
    $checklist = (Resolve-Path -LiteralPath $candidate).Path
    break
  }
}

if (-not $checklist) {
  throw "KV STUDIO operation checklist is required before $OperationName. Provide -ChecklistPath, set KV_STUDIO_OPERATION_CHECKLIST, or place CHECKLIST.md above the run/scaffold path."
}

$content = [IO.File]::ReadAllText($checklist, [Text.Encoding]::UTF8)
if ([string]::IsNullOrWhiteSpace($content)) {
  throw "KV STUDIO operation checklist is empty: $checklist"
}

$requiredTerms = @('Checklist', 'KV STUDIO', 'Steps')
$missing = @($requiredTerms | Where-Object { -not $content.Contains($_) })
if ($missing.Count -gt 0) {
  throw "KV STUDIO operation checklist is missing required section marker(s): $($missing -join ', '). Path=$checklist"
}

[pscustomobject]@{
  ok = $true
  operation = $OperationName
  checklist_path = $checklist
} | ConvertTo-Json -Depth 3
