param(
  [Parameter(Mandatory=$true)]
  [string]$EvidenceRoot,

  [int]$DebounceSeconds = 2,

  [string]$ReviewerModel = '',

  [switch]$Once,

  [switch]$NoAgent
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $EvidenceRoot)) {
  throw "EvidenceRoot not found: $EvidenceRoot"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$reviewScript = Join-Path $scriptRoot 'invoke_evidence_review.ps1'
if (-not (Test-Path -LiteralPath $reviewScript)) {
  throw "Review script not found: $reviewScript"
}

$contractPath = Join-Path $EvidenceRoot 'evidence_contract.json'
if (-not (Test-Path -LiteralPath $contractPath)) {
  throw "Missing evidence_contract.json: $contractPath"
}

$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$watchDirs = @($contract.watched_subdirs | ForEach-Object { Join-Path $EvidenceRoot ([string]$_) } | Where-Object { Test-Path -LiteralPath $_ })
if ($watchDirs.Count -eq 0) {
  throw "No watched directories exist under $EvidenceRoot"
}

$runtimeRoot = Join-Path $EvidenceRoot '.evidence_review\runtime'
New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
$watchLog = Join-Path $runtimeRoot 'watcher.log'
function Log {
  param([string]$Message)
  Add-Content -LiteralPath $watchLog -Value ((Get-Date -Format s) + ' ' + $Message) -Encoding UTF8
}

$pending = $false
$lastEventAt = Get-Date
$lastReason = ''
$watchers = New-Object System.Collections.Generic.List[System.IO.FileSystemWatcher]

function Mark-Pending {
  param([string]$Reason)
  $script:pending = $true
  $script:lastEventAt = Get-Date
  $script:lastReason = $Reason
  Log "changed $Reason"
}

foreach ($dir in $watchDirs) {
  $watcher = New-Object System.IO.FileSystemWatcher
  $watcher.Path = $dir
  $watcher.IncludeSubdirectories = $true
  $watcher.Filter = '*'
  $watcher.NotifyFilter = [IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size, CreationTime'
  Register-ObjectEvent -InputObject $watcher -EventName Changed -Action { Mark-Pending ("Changed " + $Event.SourceEventArgs.FullPath) } | Out-Null
  Register-ObjectEvent -InputObject $watcher -EventName Created -Action { Mark-Pending ("Created " + $Event.SourceEventArgs.FullPath) } | Out-Null
  Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action { Mark-Pending ("Deleted " + $Event.SourceEventArgs.FullPath) } | Out-Null
  Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action { Mark-Pending ("Renamed " + $Event.SourceEventArgs.OldFullPath + " -> " + $Event.SourceEventArgs.FullPath) } | Out-Null
  $watcher.EnableRaisingEvents = $true
  $watchers.Add($watcher) | Out-Null
  Log "watching $dir"
}

if ($Once) {
  Mark-Pending 'initial once review'
}

try {
  while ($true) {
    Start-Sleep -Milliseconds 250
    if (-not $pending) { continue }
    if (((Get-Date) - $lastEventAt).TotalSeconds -lt $DebounceSeconds) { continue }

    $reason = $lastReason
    $pending = $false
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $reviewScript, '-EvidenceRoot', $EvidenceRoot, '-Reason', $reason)
    if ($ReviewerModel) { $args += @('-ReviewerModel', $ReviewerModel) }
    if ($NoAgent) { $args += '-NoAgent' }
    Log "invoke review reason=$reason"
    & powershell.exe @args | Tee-Object -FilePath (Join-Path $runtimeRoot 'last_review_invocation.json')
    Log "review exit=$LASTEXITCODE"
    if ($Once) { break }
  }
} finally {
  foreach ($watcher in $watchers) {
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
  }
  Get-EventSubscriber | Where-Object { $_.SourceObject -is [System.IO.FileSystemWatcher] } | Unregister-Event -ErrorAction SilentlyContinue
}
