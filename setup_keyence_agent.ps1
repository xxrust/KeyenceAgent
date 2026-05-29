param(
  [string]$CodexSkillsRoot = '',
  [string]$ConfigPath = '',
  [switch]$SkipSkillInstall,
  [switch]$SkipCredential
)

$ErrorActionPreference = 'Stop'

function Expand-PathText([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  return [Environment]::ExpandEnvironmentVariables($Value)
}

function Read-TextDefault([string]$Prompt, [string]$Default) {
  if ([string]::IsNullOrWhiteSpace($Default)) {
    $value = Read-Host $Prompt
  } else {
    $value = Read-Host "$Prompt [$Default]"
  }
  if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
  return $value
}

function Read-YesNoDefault([string]$Prompt, [bool]$Default) {
  $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
  $value = Read-Host "$Prompt $suffix"
  if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
  return $value.Trim().ToLowerInvariant().StartsWith('y')
}

function First-ExistingPath([string[]]$Candidates, [string]$Fallback) {
  foreach ($candidate in $Candidates) {
    $expanded = Expand-PathText $candidate
    if (-not [string]::IsNullOrWhiteSpace($expanded) -and (Test-Path -LiteralPath $expanded)) {
      return [IO.Path]::GetFullPath($expanded)
    }
  }
  return $Fallback
}

function Get-DefaultConfigPath {
  $appData = [Environment]::GetFolderPath('ApplicationData')
  if ([string]::IsNullOrWhiteSpace($appData)) { throw 'APPDATA is empty; cannot choose a config path.' }
  return (Join-Path $appData 'Codex\kv-studio-operator\config.json')
}

function Get-DefaultCredentialPath {
  $appData = [Environment]::GetFolderPath('ApplicationData')
  if ([string]::IsNullOrWhiteSpace($appData)) { throw 'APPDATA is empty; cannot choose a credential path.' }
  return (Join-Path $appData 'Codex\kv-studio-operator\credentials.xml')
}

function Copy-SkillDirectory([string]$SourceDir, [string]$TargetRoot) {
  $name = Split-Path -Leaf $SourceDir
  $target = Join-Path $TargetRoot $name
  $sourceFull = [IO.Path]::GetFullPath($SourceDir).TrimEnd('\')
  $targetFull = [IO.Path]::GetFullPath($target).TrimEnd('\')
  if ($sourceFull.Equals($targetFull, [StringComparison]::OrdinalIgnoreCase)) {
    return [pscustomobject]@{ name = $name; target = $targetFull; action = 'already_in_place' }
  }

  New-Item -ItemType Directory -Force -Path $target | Out-Null
  Copy-Item -Path (Join-Path $SourceDir '*') -Destination $target -Recurse -Force
  return [pscustomobject]@{ name = $name; target = $targetFull; action = 'copied_or_updated' }
}

function Write-DpapiCredential([string]$UserName, [securestring]$Password, [string]$Path) {
  if ([string]::IsNullOrWhiteSpace($UserName)) { throw 'Credential user name is empty.' }
  if ($null -eq $Password -or $Password.Length -le 0) { throw 'Credential password is empty.' }
  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $credential = [System.Management.Automation.PSCredential]::new($UserName, $Password)
  $credential | Export-Clixml -LiteralPath $Path
}

$repoRoot = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($CodexSkillsRoot)) {
  $CodexSkillsRoot = Join-Path $env:USERPROFILE '.codex\skills'
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Get-DefaultConfigPath
}

Write-Host 'KeyenceAgent local setup'
Write-Host 'This script installs local Codex skills, writes VM path config, and optionally stores the KV STUDIO administrator credential with Windows DPAPI.'
Write-Host ''

$CodexSkillsRoot = Read-TextDefault 'Codex skills directory' $CodexSkillsRoot
$ConfigPath = Read-TextDefault 'VM config path' $ConfigPath

$kvsExeDefault = First-ExistingPath @(
  'D:\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe',
  'D:\KEYENCE\KVS12G\KVS11\KVS\Kvs.exe',
  'C:\Program Files (x86)\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe',
  'C:\Program Files (x86)\KEYENCE\KVS12\KVS\Kvs.exe'
) 'D:\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe'

$htmlhelpCandidates = @(
  'C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052\htmlhelp',
  (Join-Path $repoRoot 'htmlhelp')
)
if (Test-Path -LiteralPath (Join-Path $repoRoot 'llm-wiki-v2-keyence')) {
  $htmlhelpCandidates += $repoRoot
}
$htmlhelpDefault = First-ExistingPath $htmlhelpCandidates 'C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052\htmlhelp'

$wikiRootDefault = First-ExistingPath @(
  (Join-Path $htmlhelpDefault 'llm-wiki-v2-keyence'),
  (Join-Path $repoRoot 'llm-wiki-v2-keyence')
) (Join-Path $htmlhelpDefault 'llm-wiki-v2-keyence')

$workRootDefault = 'C:\Users\Public\KVSkillPractice'
$credentialPathDefault = Get-DefaultCredentialPath

$kvsExe = Read-TextDefault 'KV STUDIO Kvs.exe path' $kvsExeDefault
$workRoot = Read-TextDefault 'Disposable work root' $workRootDefault
$htmlhelpRoot = Read-TextDefault 'KEYENCE htmlhelp root' $htmlhelpDefault
$wikiRoot = Read-TextDefault 'KEYENCE Wiki V2 root' $wikiRootDefault
$wikiCleanedDb = Read-TextDefault 'Wiki cleaned DB path' (Join-Path $wikiRoot 'wiki.v2.cleaned.db')
$wikiFixedDb = Read-TextDefault 'Wiki fixed DB path' (Join-Path $wikiRoot 'wiki.v2.fixed.db')
$wikiQueryScript = Read-TextDefault 'Wiki query script path' (Join-Path $wikiRoot 'scripts\wiki_query.py')
$credentialPath = Read-TextDefault 'KV STUDIO administrator credential path' $credentialPathDefault
$adminUserDefault = Read-TextDefault 'Default KV STUDIO administrator user name' 'Administrator'
$timeoutSecondsText = Read-TextDefault 'Runner timeout seconds' '600'
$localPasteFormat = Read-TextDefault 'Local variable paste format' 'NameType'

$installedSkills = @()
if (-not $SkipSkillInstall) {
  New-Item -ItemType Directory -Force -Path $CodexSkillsRoot | Out-Null
  $skillDirs = @(Get-ChildItem -LiteralPath $repoRoot -Directory | Where-Object {
      Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')
    })
  foreach ($skill in $skillDirs) {
    $installedSkills += Copy-SkillDirectory -SourceDir $skill.FullName -TargetRoot $CodexSkillsRoot
  }
}

$configObject = [ordered]@{
  kvs_exe = $kvsExe
  work_root = $workRoot
  mvp_out_root = (Join-Path $workRoot 'mvp_runs')
  repair_out_root = (Join-Path $workRoot 'mvp_repair_runs')
  repeat_out_root = (Join-Path $workRoot 'mvp_repeat_runs')
  admin_credential_path = $credentialPath
  admin_user_default = $adminUserDefault
  htmlhelp_root = $htmlhelpRoot
  wiki_root = $wikiRoot
  wiki_cleaned_db = $wikiCleanedDb
  wiki_fixed_db = $wikiFixedDb
  wiki_query_script = $wikiQueryScript
  timeout_seconds = [int]$timeoutSecondsText
  local_paste_format = $localPasteFormat
}

$configParent = Split-Path -Parent $ConfigPath
New-Item -ItemType Directory -Force -Path $configParent | Out-Null
$configObject | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
[Environment]::SetEnvironmentVariable('KEYENCE_AGENT_CONFIG', $ConfigPath, 'User')
[Environment]::SetEnvironmentVariable('KV_STUDIO_OPERATOR_CONFIG', $ConfigPath, 'User')
$env:KEYENCE_AGENT_CONFIG = $ConfigPath
$env:KV_STUDIO_OPERATOR_CONFIG = $ConfigPath

$credentialWritten = $false
if (-not $SkipCredential) {
  $storeCredential = Read-YesNoDefault 'Store KV STUDIO administrator credential now' $true
  if ($storeCredential) {
    $credentialUser = Read-TextDefault 'Credential user name' $adminUserDefault
    $credentialPassword = Read-Host 'Credential password (stored with Windows DPAPI, not written to JSON)' -AsSecureString
    Write-DpapiCredential -UserName $credentialUser -Password $credentialPassword -Path $credentialPath
    $credentialWritten = $true
  }
}

$warnings = @()
foreach ($path in @($kvsExe, $htmlhelpRoot, $wikiRoot, $wikiCleanedDb, $wikiQueryScript)) {
  if (-not (Test-Path -LiteralPath $path)) { $warnings += "Missing path: $path" }
}
if (-not $credentialWritten -and -not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
  $warnings += "Credential file not found: $credentialPath"
}

$result = [pscustomobject]@{
  ok = ($warnings.Count -eq 0)
  repo_root = $repoRoot
  codex_skills_root = $CodexSkillsRoot
  config_path = $ConfigPath
  credential_path = $credentialPath
  credential_written = $credentialWritten
  user_environment = [pscustomobject]@{
    KEYENCE_AGENT_CONFIG = $ConfigPath
    KV_STUDIO_OPERATOR_CONFIG = $ConfigPath
  }
  installed_skills = $installedSkills
  warnings = $warnings
}

$result | ConvertTo-Json -Depth 6
if ($warnings.Count -gt 0) {
  Write-Host ''
  Write-Host 'Setup completed with warnings. Fix the missing paths before running KV STUDIO automation.'
  exit 2
}

Write-Host ''
Write-Host 'Setup completed.'
