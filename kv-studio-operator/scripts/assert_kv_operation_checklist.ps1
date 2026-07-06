param(
  [string]$ChecklistPath = '',
  [string[]]$SearchRoots = @(),
  [string]$OperationName = 'KV STUDIO operation'
)

$ErrorActionPreference = 'Stop'

function Stop-ChecklistGuard([string]$ErrorCode, [string]$Message, [int]$ExitCode) {
  $payload = [ordered]@{
    ok = $false
    error_code = $ErrorCode
    operation = $OperationName
    message = $Message
    remediation = @(
      'Create or restore CHECKLIST.md in the scaffold/run tree.',
      'Or pass -ChecklistPath <path>.',
      'Or set KV_STUDIO_OPERATION_CHECKLIST=<path>.'
    )
  }
  $json = ($payload | ConvertTo-Json -Depth 4 -Compress)
  [Console]::Error.WriteLine("KV_CHECKLIST_GUARD_FAILED $json")
  exit $ExitCode
}

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
  Stop-ChecklistGuard `
    'KV_CHECKLIST_MISSING' `
    "KV STUDIO operation checklist is required before $OperationName." `
    23
}

$content = [IO.File]::ReadAllText($checklist, [Text.Encoding]::UTF8)
if ([string]::IsNullOrWhiteSpace($content)) {
  Stop-ChecklistGuard `
    'KV_CHECKLIST_EMPTY' `
    "KV STUDIO operation checklist is empty: $checklist" `
    24
}

$requiredTerms = @('Checklist', 'KV STUDIO', 'Steps')
$missing = @($requiredTerms | Where-Object { -not $content.Contains($_) })
if ($missing.Count -gt 0) {
  Stop-ChecklistGuard `
    'KV_CHECKLIST_INVALID' `
    "KV STUDIO operation checklist is missing required section marker(s): $($missing -join ', '). Path=$checklist" `
    25
}

[pscustomobject]@{
  ok = $true
  operation = $OperationName
  checklist_path = $checklist
} | ConvertTo-Json -Depth 3
