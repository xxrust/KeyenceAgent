param(
  [Parameter(Mandatory=$true)]
  [string]$PlanPath,

  [switch]$AllowOverwrite
)

$ErrorActionPreference = 'Stop'

function Write-Result([object]$Plan, [bool]$Ok, [string]$Code, [string]$Message, [object[]]$MnmFiles = @()) {
  [ordered]@{
    ok = $Ok
    error_code = $Code
    operation = 'collect KV MNM export workspace result'
    project_path = [string]$Plan.project_path
    export_dir = [string]$Plan.export_dir
    out_dir = [string]$Plan.out_dir
    work_root = [string]$Plan.work_root
    actual_kv_export_dir = [string]$Plan.actual_kv_export_dir
    core_result_path = [string]$Plan.core_result_path
    message = $Message
    mnm_files = @($MnmFiles)
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path ([string]$Plan.out_dir) 'export_mnm_project_copy_result.json') -Encoding UTF8
}

try {
  $PlanPath = [IO.Path]::GetFullPath($PlanPath)
  if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "PlanPath not found: $PlanPath" }
  $plan = Get-Content -Raw -LiteralPath $PlanPath -Encoding UTF8 | ConvertFrom-Json
  if (-not $plan.ok) { throw "Export workspace plan is not ok: $PlanPath" }

  if (-not (Test-Path -LiteralPath ([string]$plan.core_result_path) -PathType Leaf)) { throw "Core result missing: $($plan.core_result_path)" }
  $coreResult = Get-Content -LiteralPath ([string]$plan.core_result_path) -Raw | ConvertFrom-Json
  if (-not $coreResult.ok) { throw "Core result not ok: $($coreResult.error_code) $($coreResult.message)" }

  $copied = @()
  foreach ($file in @(Get-ChildItem -LiteralPath ([string]$plan.project_copy_dir) -Filter '*.mnm' -File -ErrorAction Stop)) {
    $target = Join-Path ([string]$plan.export_dir) $file.Name
    if ((Test-Path -LiteralPath $target -PathType Leaf) -and -not $AllowOverwrite) {
      throw "Target MNM already exists; pass -AllowOverwrite or use an empty ExportDir: $target"
    }
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force:$AllowOverwrite
    $copied += Get-Item -LiteralPath $target | Select-Object FullName, Length, LastWriteTime
  }
  if ($copied.Count -eq 0) { throw "No MNM files copied to ExportDir: $($plan.export_dir)" }
  $copied | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path ([string]$plan.out_dir) 'mnm_files.json') -Encoding UTF8
  Write-Result $plan $true '' 'MNM export completed through project-copy default folder route.' $copied
  exit 0
} catch {
  $message = $_.Exception.ToString()
  $code = 'KV_MNM_PROJECT_COPY_EXPORT_FAILED'
  if ($message -like '*Target MNM already exists*') { $code = 'KV_MNM_EXPORT_TARGET_EXISTS' }
  if ($message -like '*Core result*') { $code = 'KV_MNM_EXPORT_CORE_FAILED' }
  if ($message -like '*No MNM files copied*') { $code = 'KV_MNM_EXPORT_NO_FILES' }
  if ($plan -and $plan.out_dir) {
    New-Item -ItemType Directory -Force -Path ([string]$plan.out_dir) | Out-Null
    $message | Set-Content -LiteralPath (Join-Path ([string]$plan.out_dir) 'fail.txt') -Encoding UTF8
    Write-Result $plan $false $code $message @()
  }
  exit 1
}
