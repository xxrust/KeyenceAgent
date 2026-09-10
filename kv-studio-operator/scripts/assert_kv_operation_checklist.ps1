param(
  [string]$ChecklistPath = '',
  [string[]]$SearchRoots = @(),
  [string]$OperationName = 'KV STUDIO operation'
)

$ErrorActionPreference = 'Stop'

# A published workflow supplies its actual prevalidated plan. Keep explicit
# legacy checklists for scaffold callers, but do not require agents to create a
# second, keyword-only description of an already validated operation plan.
if (-not $ChecklistPath -and $env:KV_WORKFLOW_VALIDATED_PLAN -and $env:KV_WORKFLOW_RUN_ID) {
  $planPath=$env:KV_WORKFLOW_VALIDATED_PLAN
  if (-not (Test-Path -LiteralPath $planPath -PathType Leaf) -or (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash -ne $env:KV_WORKFLOW_PLAN_SHA256) { throw 'KV_VALIDATED_PLAN_CHANGED' }
  $plan=Get-Content -Raw -Encoding UTF8 -LiteralPath $planPath | ConvertFrom-Json
  $allowedRoots=@([string]$plan.project_path)+@($plan.steps | ForEach-Object { [string]$_.out_dir })
  $matches=@($SearchRoots | Where-Object { $_ -and [IO.Path]::GetFullPath($_) -in $allowedRoots })
  if ($plan.ok -isnot [bool] -or -not $plan.ok -or $matches.Count -eq 0) { throw 'KV_VALIDATED_PLAN_TARGET_MISMATCH' }
  @{ok=$true;operation=$OperationName;plan_path=$planPath;run_id=$env:KV_WORKFLOW_RUN_ID;basis='manifest-resolved execution plan validated before child launch'} | ConvertTo-Json
  return
}

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
