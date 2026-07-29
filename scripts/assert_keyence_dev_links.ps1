param(
  [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)),
  [string]$CodexSkillsRoot = (Join-Path $env:USERPROFILE '.codex\skills'),
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
$SkillNames = @(
  'kv-studio-kb-programming',
  'keyence-plc-programmer',
  'kv-studio-operator'
)

function Get-FullPath([string]$Path) {
  [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
}

function Resolve-LinkTarget([IO.FileSystemInfo]$Item) {
  $targetValue = [string]@($Item.Target)[0]
  if ([string]::IsNullOrWhiteSpace($targetValue)) { return '' }
  if (-not [IO.Path]::IsPathRooted($targetValue)) {
    $targetValue = Join-Path $Item.Parent.FullName $targetValue
  }
  Get-FullPath $targetValue
}

$RepoRoot = Get-FullPath $RepoRoot
$CodexSkillsRoot = Get-FullPath $CodexSkillsRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $localRoot = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
  $OutDir = Join-Path $localRoot ('KeyenceAgent\Artifacts\dev-link-check\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$OutDir = Get-FullPath $OutDir
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$checks = [System.Collections.Generic.List[object]]::new()
$repoGitRoot = (& git -C $RepoRoot rev-parse --show-toplevel 2>$null)
$repoGitRoot = if ($repoGitRoot) { Get-FullPath ([string]$repoGitRoot) } else { '' }
$checks.Add([pscustomobject]@{
  name = 'standalone_git_root'
  ok = $repoGitRoot.Equals($RepoRoot, [StringComparison]::OrdinalIgnoreCase)
  expected = $RepoRoot
  actual = $repoGitRoot
})
$skillsRootGit = Join-Path $CodexSkillsRoot '.git'
$checks.Add([pscustomobject]@{
  name = 'codex_skills_root_detached'
  ok = -not (Test-Path -LiteralPath $skillsRootGit)
  expected = 'no .git at Codex skills root'
  actual = if (Test-Path -LiteralPath $skillsRootGit) { $skillsRootGit } else { 'detached' }
})

foreach ($name in $SkillNames) {
  $source = Get-FullPath (Join-Path $RepoRoot $name)
  $target = Get-FullPath (Join-Path $CodexSkillsRoot $name)
  $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
  $isLink = $item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
  $resolved = if ($isLink) { Resolve-LinkTarget $item } else { '' }
  $checks.Add([pscustomobject]@{
    name = "dev_link_$name"
    ok = ($isLink -and $resolved.Equals($source, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath (Join-Path $target 'SKILL.md') -PathType Leaf))
    expected = $source
    actual = if ($resolved) { $resolved } elseif ($item) { 'regular_directory' } else { 'missing' }
  })
}

$manifestPath = Join-Path $RepoRoot 'kv-studio-operator\scripts\script_manifest.json'
$manifestOk = $false
try {
  $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
  $manifestOk = ($manifest.schema_version -eq 1 -and @($manifest.classes.customer_workflow).Count -gt 0)
} catch {
  $manifestOk = $false
}
$checks.Add([pscustomobject]@{
  name = 'operator_manifest_parse'
  ok = $manifestOk
  expected = 'schema_version=1 with customer_workflow entries'
  actual = $manifestPath
})

$failed = @($checks | Where-Object { -not $_.ok })
$payload = [ordered]@{
  ok = ($failed.Count -eq 0)
  error_code = if ($failed.Count -eq 0) { '' } else { 'KEYENCE_DEV_LINK_CHECK_FAILED' }
  operation = 'assert KeyenceAgent development links'
  repo_root = $RepoRoot
  codex_skills_root = $CodexSkillsRoot
  checks = @($checks)
  failed_count = $failed.Count
  git_head = (& git -C $RepoRoot rev-parse HEAD 2>$null)
}
$resultPath = Join-Path $OutDir 'dev_link_check_result.json'
$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$payload['result_path'] = $resultPath
$payload | ConvertTo-Json -Depth 8
if (-not $payload.ok) { exit 51 }
