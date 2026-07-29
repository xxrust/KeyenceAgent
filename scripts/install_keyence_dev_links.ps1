[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
  [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)),
  [string]$CodexSkillsRoot = (Join-Path $env:USERPROFILE '.codex\skills'),
  [string]$BackupRoot = '',
  [string]$OutDir = '',
  [switch]$BackupExisting
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

function Write-Result([object]$Payload) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $path = Join-Path $OutDir 'dev_link_install_result.json'
  $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
  $path
}

function Stop-Install([string]$ErrorCode, [string]$Message, [object[]]$Entries = @(), [int]$ExitCode = 41) {
  $payload = [ordered]@{
    ok = $false
    error_code = $ErrorCode
    operation = 'install KeyenceAgent development links'
    message = $Message
    repo_root = $RepoRoot
    codex_skills_root = $CodexSkillsRoot
    backup_root = $BackupRoot
    entries = @($Entries)
  }
  $resultPath = Write-Result $payload
  [Console]::Error.WriteLine('KEYENCE_DEV_LINK_INSTALL_FAILED ' + (($payload | ConvertTo-Json -Depth 8 -Compress)))
  [Console]::Error.WriteLine('result=' + $resultPath)
  exit $ExitCode
}

$RepoRoot = Get-FullPath $RepoRoot
$CodexSkillsRoot = Get-FullPath $CodexSkillsRoot
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
  $localRoot = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
  $BackupRoot = Join-Path $localRoot "KeyenceAgent\DevLinkBackups\$stamp"
}
$BackupRoot = Get-FullPath $BackupRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $localRoot = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
  $OutDir = Join-Path $localRoot "KeyenceAgent\Artifacts\dev-link-install\$stamp"
}
$OutDir = Get-FullPath $OutDir

if ($RepoRoot.Equals($CodexSkillsRoot, [StringComparison]::OrdinalIgnoreCase)) {
  Stop-Install 'KEYENCE_REPOSITORY_EQUALS_SKILLS_ROOT' 'Clone KeyenceAgent into a standalone directory. The repository root cannot be the Codex skills root.'
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git') -PathType Container)) {
  Stop-Install 'KEYENCE_REPOSITORY_GIT_ROOT_MISSING' "Standalone Git metadata was not found under: $RepoRoot"
}

New-Item -ItemType Directory -Force -Path $CodexSkillsRoot | Out-Null
$entries = [System.Collections.Generic.List[object]]::new()

foreach ($name in $SkillNames) {
  $source = Get-FullPath (Join-Path $RepoRoot $name)
  $target = Get-FullPath (Join-Path $CodexSkillsRoot $name)
  if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md') -PathType Leaf)) {
    Stop-Install 'KEYENCE_DEV_SOURCE_INVALID' "Source skill is missing SKILL.md: $source" @($entries)
  }

  $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
  if ($existing -and (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
    $resolved = Resolve-LinkTarget $existing
    if ($resolved.Equals($source, [StringComparison]::OrdinalIgnoreCase)) {
      $entries.Add([pscustomobject]@{ name = $name; source = $source; target = $target; action = 'already_linked'; backup = '' })
      continue
    }
    Stop-Install 'KEYENCE_DEV_LINK_TARGET_CONFLICT' "Existing reparse point targets another location: $target -> $resolved" @($entries)
  }

  $backupPath = ''
  if ($existing) {
    if (-not $BackupExisting) {
      Stop-Install 'KEYENCE_DEV_TARGET_EXISTS' "Existing directory requires -BackupExisting before it can be replaced: $target" @($entries)
    }
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $backupPath = Get-FullPath (Join-Path $BackupRoot $name)
    if (Test-Path -LiteralPath $backupPath) {
      Stop-Install 'KEYENCE_DEV_BACKUP_COLLISION' "Backup target already exists: $backupPath" @($entries)
    }
    if ($PSCmdlet.ShouldProcess($target, "Move existing skill to $backupPath")) {
      Move-Item -LiteralPath $target -Destination $backupPath
    }
  }

  try {
    if ($PSCmdlet.ShouldProcess($target, "Create junction to $source")) {
      New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    }
  } catch {
    if ($backupPath -and (Test-Path -LiteralPath $backupPath) -and -not (Test-Path -LiteralPath $target)) {
      Move-Item -LiteralPath $backupPath -Destination $target
    }
    Stop-Install 'KEYENCE_DEV_LINK_CREATE_FAILED' $_.Exception.Message @($entries) 42
  }

  $created = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
  $resolvedCreated = if ($created) { Resolve-LinkTarget $created } else { '' }
  if (-not $created -or -not $resolvedCreated.Equals($source, [StringComparison]::OrdinalIgnoreCase)) {
    Stop-Install 'KEYENCE_DEV_LINK_POSTCHECK_FAILED' "Created link did not resolve to source: $target -> $resolvedCreated" @($entries) 43
  }
  $entries.Add([pscustomobject]@{ name = $name; source = $source; target = $target; action = 'linked'; backup = $backupPath })
}

$payload = [ordered]@{
  ok = $true
  error_code = ''
  operation = 'install KeyenceAgent development links'
  repo_root = $RepoRoot
  codex_skills_root = $CodexSkillsRoot
  backup_root = $BackupRoot
  entries = @($entries)
  next_action = 'Run scripts/assert_keyence_dev_links.ps1, then start a new Codex session so skill metadata is reloaded.'
}
$resultPath = Write-Result $payload
$payload['result_path'] = $resultPath
$payload | ConvertTo-Json -Depth 8
