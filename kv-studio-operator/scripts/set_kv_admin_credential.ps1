param(
  [string]$UserName = '',
  [string]$Password = '',
  [string]$CredentialPath = ''
)

$ErrorActionPreference = 'Stop'

function Get-DefaultCredentialPath {
  $appData = [Environment]::GetFolderPath('ApplicationData')
  if ([string]::IsNullOrWhiteSpace($appData)) { throw 'APPDATA is empty; cannot choose a credential path.' }
  return (Join-Path $appData 'Codex\kv-studio-operator\credentials.xml')
}

if ([string]::IsNullOrWhiteSpace($CredentialPath)) {
  $CredentialPath = Get-DefaultCredentialPath
}

$parent = Split-Path -Parent $CredentialPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null

if ([string]::IsNullOrWhiteSpace($UserName) -or [string]::IsNullOrWhiteSpace($Password)) {
  $credential = Get-Credential -Message 'Enter the KV STUDIO administrator credential used during project creation.'
} else {
  $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
  $credential = [System.Management.Automation.PSCredential]::new($UserName, $securePassword)
}

if ([string]::IsNullOrWhiteSpace($credential.UserName) -or [string]::IsNullOrWhiteSpace($credential.GetNetworkCredential().Password)) {
  throw 'KV STUDIO administrator credential is empty.'
}

$credential | Export-Clixml -LiteralPath $CredentialPath

[pscustomobject]@{
  ok = $true
  credential_path = $CredentialPath
  user_name = $credential.UserName
  storage = 'Windows DPAPI Export-Clixml; decryptable by the same Windows user on this machine'
} | ConvertTo-Json -Depth 3
