param(
  [string]$CodexSkillsRoot = '',
  [string]$ConfigPath = '',
  [switch]$SkipSkillInstall,
  [switch]$SkipCredential,
  [Alias('h')]
  [switch]$Help,
  [switch]$Status,
  [ValidateSet('auto','en','zh-CN','ja')]
  [string]$Language = 'auto',
  [ValidateSet('all','skills','config','kvs_exe','work_root','wiki_root','admin_user','credential','advanced')]
  [string[]]$Configure = @('all')
)

$ErrorActionPreference = 'Stop'

function New-HelpText {
  @(
    'Usage:',
    '  .\setup_keyence_agent.ps1',
    '  .\setup_keyence_agent.ps1 -h',
    '  .\setup_keyence_agent.ps1 -Status',
    '  .\setup_keyence_agent.ps1 -Configure credential',
    '  .\setup_keyence_agent.ps1 -Configure kvs_exe,wiki_root',
    '',
    'Configure values:',
    '  all          Full setup flow.',
    '  skills       Install/update the KEYENCE skill suite.',
    '  config       Configure normal machine paths.',
    '  kvs_exe      Configure KV STUDIO Kvs.exe path.',
    '  work_root    Configure disposable work root.',
    '  wiki_root    Configure KEYENCE Wiki V2 root.',
    '  admin_user   Configure default KV STUDIO administrator user name.',
    '  credential   Store KV STUDIO administrator credential.',
    '  advanced     Configure advanced runner defaults.',
    '',
    'Notes:',
    '  Local config accepts a file path or directory. %LOCALAPPDATA%\KeyenceAgent\Config becomes %LOCALAPPDATA%\KeyenceAgent\Config\config.json.',
    '  The credential path is automatic: %APPDATA%\Codex\kv-studio-operator\credentials.xml.',
    '  KV STUDIO administrator passwords must be 8-64 characters and use at least two character types: lowercase, uppercase, digits, or symbols.'
  ) -join [Environment]::NewLine
}

$Messages = @{
  'en' = @{
    title = 'KeyenceAgent local setup'
    intro = 'Installs the KEYENCE Codex skill suite, writes local machine config, and optionally stores the KV STUDIO administrator credential with Windows DPAPI.'
  }
  'zh-CN' = @{
    title = 'KeyenceAgent setup [zh-CN]'
    intro = 'Chinese UI language detected. This script keeps prompts ASCII-safe; Chinese instructions are in README.zh-CN.md.'
  }
  'ja' = @{
    title = 'KeyenceAgent setup [ja]'
    intro = 'Japanese UI language detected. This script keeps prompts ASCII-safe; Japanese instructions are in README.ja.md.'
  }
}

$CommonText = @{
  help = (New-HelpText)
  prompt_skills = 'Codex skills directory'
  prompt_config = 'Local config file path or directory'
  prompt_kvs = 'KV STUDIO Kvs.exe path'
  prompt_work = 'Disposable work root'
  prompt_wiki = 'KEYENCE Wiki V2 root'
  prompt_admin_user = 'KV STUDIO administrator user name'
  prompt_advanced = 'Configure advanced runner defaults'
  prompt_timeout = 'Runner timeout seconds'
  prompt_paste = 'Local variable paste format'
  prompt_store_credential = 'Store KV STUDIO administrator credential now'
  prompt_password = 'KV STUDIO administrator password for {0}, 8-64 characters and at least two types (lowercase, uppercase, digits, symbols); stored with Windows DPAPI, not written to JSON'
  config_dir_resolved = 'Local config path is a directory; using file: {0}'
  credential_auto = 'KV STUDIO administrator credential will be stored at: {0}'
  status_header = 'Configuration status'
  configured = 'configured'
  missing = 'missing'
  setup_done = 'Setup completed.'
  setup_warn = 'Setup completed with warnings. Fix the missing paths before running KV STUDIO automation.'
}

function Resolve-SetupLanguage([string]$Requested) {
  if ($Requested -and $Requested -ne 'auto') { return $Requested }
  $name = [Globalization.CultureInfo]::CurrentUICulture.Name
  if ($name -like 'zh*') { return 'zh-CN' }
  if ($name -like 'ja*') { return 'ja' }
  return 'en'
}

$script:SetupLanguage = Resolve-SetupLanguage $Language

function T([string]$Key) {
  if ($Messages[$script:SetupLanguage].ContainsKey($Key)) { return $Messages[$script:SetupLanguage][$Key] }
  if ($CommonText.ContainsKey($Key)) { return $CommonText[$Key] }
  return $Key
}

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

function Resolve-ConfigFilePath([string]$PathText) {
  if ([string]::IsNullOrWhiteSpace($PathText)) { return Get-DefaultConfigPath }
  $expanded = Expand-PathText $PathText
  $full = [IO.Path]::GetFullPath($expanded)
  $extension = [IO.Path]::GetExtension($full)
  if ((Test-Path -LiteralPath $full -PathType Container) -or [string]::IsNullOrWhiteSpace($extension)) {
    $resolved = Join-Path $full 'config.json'
    Write-Host ([string]::Format((T 'config_dir_resolved'), $resolved))
    return $resolved
  }
  return $full
}

function Read-JsonFileIfPresent([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Unblock-KeyencePowerShellFiles([string]$Root) {
  if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root -PathType Container)) {
    return 0
  }
  $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction Stop |
    Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') })
  $unblocked = 0
  foreach ($file in $files) {
    $zone = Get-Item -LiteralPath $file.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue
    if ($zone) {
      Unblock-File -LiteralPath $file.FullName
      $unblocked++
    }
  }
  return $unblocked
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

function Get-KeyenceSkillDirectories([string]$RepoRoot) {
  $names = @(
    'kv-studio-kb-programming',
    'keyence-plc-programmer',
    'kv-studio-operator'
  )
  $dirs = [System.Collections.Generic.List[object]]::new()
  foreach ($name in $names) {
    $dir = Join-Path $RepoRoot $name
    if (Test-Path -LiteralPath (Join-Path $dir 'SKILL.md') -PathType Leaf) {
      $dirs.Add([IO.DirectoryInfo]::new($dir))
    }
  }
  return @($dirs)
}

function Write-DpapiCredential([string]$UserName, [securestring]$Password, [string]$Path) {
  if ([string]::IsNullOrWhiteSpace($UserName)) { throw 'Credential user name is empty.' }
  Assert-KvStudioPassword -Password $Password
  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $credential = [System.Management.Automation.PSCredential]::new($UserName, $Password)
  $credential | Export-Clixml -LiteralPath $Path
}

function Test-KvStudioExecutable([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  $expanded = Expand-PathText $Path
  return ((Test-Path -LiteralPath $expanded -PathType Leaf) -and
    ([IO.Path]::GetFileName($expanded).Equals('Kvs.exe', [StringComparison]::OrdinalIgnoreCase)))
}

function Assert-KvStudioExecutable([string]$Path) {
  if (-not (Test-KvStudioExecutable $Path)) {
    throw "KV_STUDIO_EXE_INVALID: Kvs.exe was not found at '$Path'. Supply the full path to an existing Kvs.exe file."
  }
}

function Assert-KvStudioPassword([securestring]$Password) {
  if ($null -eq $Password -or $Password.Length -le 0) { throw 'Credential password is empty.' }

  $bstr = [IntPtr]::Zero
  try {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if ($plain.Length -lt 8 -or $plain.Length -gt 64) {
      throw 'KV STUDIO administrator password must be 8-64 characters.'
    }

    $types = 0
    if ($plain -cmatch '[a-z]') { $types++ }
    if ($plain -cmatch '[A-Z]') { $types++ }
    if ($plain -match '[0-9]') { $types++ }
    if ($plain -match '[^A-Za-z0-9]') { $types++ }
    if ($types -lt 2) {
      throw 'KV STUDIO administrator password must use at least two character types: lowercase, uppercase, digits, or symbols.'
    }
  } finally {
    if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  }
}

function Test-Selected([string]$Name) {
  return (($Configure -contains 'all') -or ($Configure -contains $Name))
}

function New-StatusItem([string]$Name, [bool]$Ok, [string]$Path, [string]$Message = '') {
  [pscustomobject]@{
    name = $Name
    ok = $Ok
    state = if ($Ok) { T 'configured' } else { T 'missing' }
    path = $Path
    message = $Message
  }
}

function Get-SetupStatus([string]$RepoRoot, [string]$SkillsRoot, [string]$ConfigFile, [object]$Config) {
  $items = [System.Collections.Generic.List[object]]::new()
  $items.Add((New-StatusItem 'config_file' (Test-Path -LiteralPath $ConfigFile -PathType Leaf) $ConfigFile))
  $items.Add((New-StatusItem 'codex_skills_root' (Test-Path -LiteralPath $SkillsRoot -PathType Container) $SkillsRoot))

  $skillDirs = Get-KeyenceSkillDirectories $RepoRoot
  $missingSkills = @()
  foreach ($skill in $skillDirs) {
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $SkillsRoot $skill.Name) 'SKILL.md') -PathType Leaf)) {
      $missingSkills += $skill.Name
    }
  }
  $items.Add((New-StatusItem 'skills_installed' ($missingSkills.Count -eq 0 -and $skillDirs.Count -gt 0) $SkillsRoot (($missingSkills -join ','))))

  $kvsPath = if ($Config -and $Config.kvs_exe) { [string]$Config.kvs_exe } else { '' }
  $items.Add((New-StatusItem 'kvs_exe' (Test-KvStudioExecutable $kvsPath) $kvsPath))

  $workRoot = if ($Config -and $Config.work_root) { [string]$Config.work_root } else { '' }
  $items.Add((New-StatusItem 'work_root' (-not [string]::IsNullOrWhiteSpace($workRoot)) $workRoot))

  $wikiRoot = if ($Config -and $Config.wiki_root) { [string]$Config.wiki_root } else { '' }
  $wikiOk = ((-not [string]::IsNullOrWhiteSpace($wikiRoot)) -and
    (Test-Path -LiteralPath $wikiRoot -PathType Container) -and
    (Test-Path -LiteralPath (Join-Path $wikiRoot 'wiki.v2.cleaned.db') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $wikiRoot 'scripts\wiki_query.py') -PathType Leaf))
  $items.Add((New-StatusItem 'wiki_root' $wikiOk $wikiRoot))

  $adminUser = if ($Config -and $Config.admin_user_default) { [string]$Config.admin_user_default } else { '' }
  $items.Add((New-StatusItem 'admin_user_default' (-not [string]::IsNullOrWhiteSpace($adminUser)) $adminUser))

  $credentialPath = if ($Config -and $Config.admin_credential_path) { [string]$Config.admin_credential_path } else { Get-DefaultCredentialPath }
  $items.Add((New-StatusItem 'admin_credential' (Test-Path -LiteralPath $credentialPath -PathType Leaf) $credentialPath))

  return @($items)
}

function Write-StatusTable([object[]]$Items) {
  Write-Host ''
  Write-Host (T 'status_header')
  foreach ($item in $Items) {
    $mark = if ($item.ok) { '[OK]' } else { '[--]' }
    $line = '{0} {1}: {2}' -f $mark, $item.name, $item.path
    if ($item.message) { $line += " $($item.message)" }
    Write-Host $line
  }
}

if ($Help) {
  Write-Host (T 'help')
  exit 0
}

$repoRoot = Split-Path -Parent $PSCommandPath
# ZIP downloads carry Zone.Identifier ADS entries. Under RemoteSigned those
# entries block every unsigned child script, even when the repository is trusted.
# Clear them once for this repository; do not weaken the machine policy.
$repoScriptsUnblocked = Unblock-KeyencePowerShellFiles $repoRoot
if ([string]::IsNullOrWhiteSpace($CodexSkillsRoot)) {
  $CodexSkillsRoot = Join-Path $env:USERPROFILE '.codex\skills'
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Get-DefaultConfigPath
}
$ConfigPath = Resolve-ConfigFilePath $ConfigPath
$existingConfig = Read-JsonFileIfPresent $ConfigPath

if ($Status) {
  $statusItems = Get-SetupStatus $repoRoot $CodexSkillsRoot $ConfigPath $existingConfig
  Write-StatusTable $statusItems
  [pscustomobject]@{
    ok = (($statusItems | Where-Object { -not $_.ok }).Count -eq 0)
    language = $script:SetupLanguage
    config_path = $ConfigPath
    status_items = $statusItems
  } | ConvertTo-Json -Depth 6
  exit 0
}

Write-Host (T 'title')
Write-Host (T 'intro')
Write-Host ''

if (Test-Selected 'skills') {
  $CodexSkillsRoot = Read-TextDefault (T 'prompt_skills') $CodexSkillsRoot
}

if (($Configure -contains 'all') -or ($Configure -contains 'config')) {
  $ConfigPath = Resolve-ConfigFilePath (Read-TextDefault (T 'prompt_config') $ConfigPath)
  $existingConfig = Read-JsonFileIfPresent $ConfigPath
}

$kvsExeDefault = First-ExistingPath @(
  'H:\Keyence\KVS12\KVS\Kvs.exe',
  'C:\Program Files (x86)\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe',
  'C:\Program Files (x86)\KEYENCE\KVS12\KVS\Kvs.exe'
) 'C:\Program Files (x86)\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe'
if ($existingConfig -and $existingConfig.kvs_exe -and (Test-KvStudioExecutable ([string]$existingConfig.kvs_exe))) {
  $kvsExeDefault = [string]$existingConfig.kvs_exe
}

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
if ($existingConfig -and $existingConfig.wiki_root) { $wikiRootDefault = [string]$existingConfig.wiki_root }

$defaultLocalAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { Join-Path $env:USERPROFILE 'AppData\Local' } else { $env:LOCALAPPDATA }
$workRootDefault = if ($existingConfig -and $existingConfig.work_root) { [string]$existingConfig.work_root } else { Join-Path $defaultLocalAppData 'KeyenceAgent\Work' }
$credentialPathDefault = if ($existingConfig -and $existingConfig.admin_credential_path) { [string]$existingConfig.admin_credential_path } else { Get-DefaultCredentialPath }
$adminUserDefault = if ($existingConfig -and $existingConfig.admin_user_default) { [string]$existingConfig.admin_user_default } else { 'Administrator' }
$timeoutSecondsText = if ($existingConfig -and $null -ne $existingConfig.timeout_seconds) { [string]$existingConfig.timeout_seconds } else { '600' }
$localPasteFormat = if ($existingConfig -and $existingConfig.local_paste_format) { [string]$existingConfig.local_paste_format } else { 'NameType' }

$kvsExe = $kvsExeDefault
$workRoot = $workRootDefault
$wikiRoot = $wikiRootDefault

if ((Test-Selected 'kvs_exe') -or (Test-Selected 'config')) { $kvsExe = Read-TextDefault (T 'prompt_kvs') $kvsExeDefault }
if ((Test-Selected 'work_root') -or (Test-Selected 'config')) { $workRoot = Read-TextDefault (T 'prompt_work') $workRootDefault }
if ((Test-Selected 'wiki_root') -or (Test-Selected 'config')) { $wikiRoot = Read-TextDefault (T 'prompt_wiki') $wikiRootDefault }

$credentialPath = $credentialPathDefault
Write-Host ([string]::Format((T 'credential_auto'), $credentialPath))
if ((Test-Selected 'admin_user') -or (Test-Selected 'credential') -or (Test-Selected 'config')) {
  $adminUserDefault = Read-TextDefault (T 'prompt_admin_user') $adminUserDefault
}

if (Test-Selected 'advanced') {
  $timeoutSecondsText = Read-TextDefault (T 'prompt_timeout') $timeoutSecondsText
  $localPasteFormat = Read-TextDefault (T 'prompt_paste') $localPasteFormat
} elseif ($Configure -contains 'all') {
  $advancedConfig = Read-YesNoDefault (T 'prompt_advanced') $false
  if ($advancedConfig) {
    $timeoutSecondsText = Read-TextDefault (T 'prompt_timeout') $timeoutSecondsText
    $localPasteFormat = Read-TextDefault (T 'prompt_paste') $localPasteFormat
  }
}

$installedSkills = @()
if ((Test-Selected 'skills') -and -not $SkipSkillInstall) {
  $repoRootFull = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\')
  $skillsRootFull = [IO.Path]::GetFullPath($CodexSkillsRoot).TrimEnd('\')
  if ($repoRootFull.Equals($skillsRootFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'KEYENCE_REPOSITORY_EQUALS_SKILLS_ROOT: Clone KeyenceAgent into a standalone directory, then run setup. Developers should use scripts\install_keyence_dev_links.ps1.'
  }
  New-Item -ItemType Directory -Force -Path $CodexSkillsRoot | Out-Null
  $skillDirs = Get-KeyenceSkillDirectories $repoRoot
  foreach ($skill in $skillDirs) {
    $installedSkills += Copy-SkillDirectory -SourceDir $skill.FullName -TargetRoot $CodexSkillsRoot
  }
  $installedSkillsUnblocked = Unblock-KeyencePowerShellFiles $CodexSkillsRoot
}

$configObject = [ordered]@{
  kvs_exe = $kvsExe
  work_root = $workRoot
  admin_credential_path = $credentialPath
  admin_user_default = $adminUserDefault
  wiki_root = $wikiRoot
}
if ((Test-Selected 'advanced') -or ($Configure -contains 'all')) {
  $configObject['timeout_seconds'] = [int]$timeoutSecondsText
  $configObject['local_paste_format'] = $localPasteFormat
}

if ((Test-Selected 'config') -or (Test-Selected 'kvs_exe') -or (Test-Selected 'work_root') -or (Test-Selected 'wiki_root') -or (Test-Selected 'admin_user') -or (Test-Selected 'advanced')) {
  Assert-KvStudioExecutable $kvsExe
  $configParent = Split-Path -Parent $ConfigPath
  New-Item -ItemType Directory -Force -Path $configParent | Out-Null
  $configObject | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
  [Environment]::SetEnvironmentVariable('KEYENCE_AGENT_CONFIG', $ConfigPath, 'User')
  [Environment]::SetEnvironmentVariable('KV_STUDIO_OPERATOR_CONFIG', $ConfigPath, 'User')
  $env:KEYENCE_AGENT_CONFIG = $ConfigPath
  $env:KV_STUDIO_OPERATOR_CONFIG = $ConfigPath
}

$credentialWritten = $false
if ((Test-Selected 'credential') -and -not $SkipCredential) {
  $storeCredential = if ($Configure -contains 'all') { Read-YesNoDefault (T 'prompt_store_credential') $true } else { $true }
  if ($storeCredential) {
    $credentialPassword = Read-Host ([string]::Format((T 'prompt_password'), $adminUserDefault)) -AsSecureString
    Write-DpapiCredential -UserName $adminUserDefault -Password $credentialPassword -Path $credentialPath
    $credentialWritten = $true
  }
}

$finalConfig = Read-JsonFileIfPresent $ConfigPath
if (-not $finalConfig) { $finalConfig = [pscustomobject]$configObject }
$statusItems = Get-SetupStatus $repoRoot $CodexSkillsRoot $ConfigPath $finalConfig
Write-StatusTable $statusItems

$warnings = @()
foreach ($item in $statusItems) {
  if (-not $item.ok) { $warnings += "$($item.name): $($item.path)" }
}

$result = [pscustomobject]@{
  ok = ($warnings.Count -eq 0)
  language = $script:SetupLanguage
  repo_root = $repoRoot
  codex_skills_root = $CodexSkillsRoot
  config_path = $ConfigPath
  credential_path = $credentialPath
  credential_written = $credentialWritten
  user_environment = [pscustomobject]@{
    KEYENCE_AGENT_CONFIG = $ConfigPath
    KV_STUDIO_OPERATOR_CONFIG = $ConfigPath
  }
  configured = $Configure
  status_items = $statusItems
  installed_skills = $installedSkills
  warnings = $warnings
}

$result | ConvertTo-Json -Depth 6
if ($warnings.Count -gt 0) {
  Write-Host ''
  Write-Host (T 'setup_warn')
  exit 2
}

Write-Host ''
Write-Host (T 'setup_done')
