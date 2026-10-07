param(
  [string]$ScriptsRoot = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)),
  [string]$ManifestPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'script_manifest.json'),
  [string]$OutDir = '',
  [string[]]$ScriptNames = @()
)

$ErrorActionPreference = 'Stop'

function Stop-GuardUsageCheck([string]$ErrorCode, [string]$Message, [object[]]$Findings, [int]$ExitCode) {
  $evidence = @()
  if ($OutDir) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $path = Join-Path $OutDir 'kv_ui_guard_usage_findings.json'
    $Findings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
    $evidence += $path
  }
  $payload = [ordered]@{
    ok = $false
    error_code = $ErrorCode
    operation = 'assert KV MVP UI guard usage'
    message = $Message
    evidence = $evidence
    finding_count = @($Findings).Count
    findings = @($Findings | Select-Object -First 25)
    remediation = @(
      'Move global UI input into scripts/guards/kv_ui_guard.ps1 guarded action functions.',
      'Replace raw SendKeys/keybd_event/mouse_event/SetCursorPos/clipboard paste paths in MVP child scripts.',
      'Do not run KV STUDIO while this check reports violations.'
    )
  }
  if ($OutDir) { $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutDir 'ui_guard_usage_result.json') -Encoding UTF8 }
  [Console]::Error.WriteLine('KV_UI_GUARD_STATIC_VIOLATION ' + (($payload | ConvertTo-Json -Depth 8 -Compress)))
  exit $ExitCode
}

$ScriptsRoot = [IO.Path]::GetFullPath($ScriptsRoot)
$ManifestPath = [IO.Path]::GetFullPath($ManifestPath)
$manifest = $null

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
  throw "Script manifest is required: $ManifestPath"
}
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$approvedAtomicActions = @($manifest.ui_atomic_actions.approved | ForEach-Object { [string]$_ } | Where-Object { $_ })
$pendingAtomicActions = @($manifest.ui_atomic_actions.pending | ForEach-Object { [string]$_ } | Where-Object { $_ })

if ($ScriptNames.Count -eq 0) {
  $ScriptNames = @(
    @($manifest.classes.runner_child_approved | Where-Object { $_.ui_guard_required } | ForEach-Object { $_.path })
    @($manifest.classes.runner_child_pending | Where-Object { $_.ui_guard_required } | ForEach-Object { $_.path })
  ) | ForEach-Object {
    $_
  }
}
$allowedFiles = @(
  [IO.Path]::GetFullPath((Join-Path $ScriptsRoot 'guards\kv_ui_guard.ps1')),
  [IO.Path]::GetFullPath($PSCommandPath)
)

$patterns = @(
  @{ name = 'SendKeys'; regex = '\[System\.Windows\.Forms\.SendKeys\]::SendWait|\[Windows\.Forms\.SendKeys\]::SendWait' },
  @{ name = 'keybd_event'; regex = '::keybd_event\(' },
  @{ name = 'mouse_event'; regex = '::mouse_event\(' },
  @{ name = 'SetCursorPos'; regex = '::SetCursorPos\(' },
  @{ name = 'ClipboardSetText'; regex = '\[System\.Windows\.Forms\.Clipboard\]::SetText|\[Windows\.Forms\.Clipboard\]::SetText' },
  @{ name = 'AppActivate'; regex = '\.AppActivate\(' }
)

$findings = @()
if ($approvedAtomicActions.Count -eq 0) {
  $findings += [pscustomobject]@{
    file = $ManifestPath
    line = 0
    pattern = 'MissingApprovedAtomicRegistry'
    text = 'ui_atomic_actions.approved must explicitly list customer-workflow atomic APIs.'
  }
}
foreach ($name in $ScriptNames) {
  $path = [IO.Path]::GetFullPath((Join-Path $ScriptsRoot $name))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    $findings += [pscustomobject]@{
      file = $path
      line = 0
      pattern = 'MissingScript'
      text = 'Required MVP child script is missing.'
    }
    continue
  }
  if ($allowedFiles -contains $path) { continue }
  $lines = @(Get-Content -LiteralPath $path)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = [string]$lines[$i]
    if ($line -match '^\s*#') { continue }
    foreach ($pattern in $patterns) {
      if ($line -match $pattern.regex) {
        $findings += [pscustomobject]@{
          file = $path
          line = $i + 1
          pattern = $pattern.name
          text = $line.Trim()
        }
      }
    }
    foreach ($match in [regex]::Matches($line, '\b(?:Assert-KvUiForegroundHwnd|Invoke-KvGuarded[A-Za-z0-9_-]+)\b')) {
      $actionName = $match.Value
      if ($approvedAtomicActions -notcontains $actionName) {
        $status = if ($pendingAtomicActions -contains $actionName) { 'pending' } else { 'unregistered' }
        $findings += [pscustomobject]@{
          file = $path
          line = $i + 1
          pattern = 'UnapprovedAtomicAction'
          text = "$actionName is $status and cannot be called by an approved runner child."
        }
      }
    }
  }
  $callerTokens=$null;$callerErrors=$null
  $callerAst=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$callerTokens,[ref]$callerErrors)
  foreach($command in @($callerAst.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-KvGuardedSendKeys'},$true))) {
    $parts=@($command.CommandElements)
    for($part=1;$part -lt $parts.Count;$part++) {
      if($parts[$part] -isnot [Management.Automation.Language.CommandParameterAst] -or $parts[$part].ParameterName -ne 'Keys'){continue}
      $argument=$parts[$part].Argument
      if(-not $argument -and $part+1 -lt $parts.Count){$argument=$parts[$part+1]}
      if($argument -is [Management.Automation.Language.StringConstantExpressionAst] -and $argument.Value -ieq '^n') {
        $findings += [pscustomobject]@{file=$path;line=$command.Extent.StartLineNumber;pattern='WrongNewProjectTransition';text='Ctrl+N opens a modal; use the approved modal-aware chord and verify the owned New Project dialog before entering data.'}
      }
    }
  }
}

$guardPath = [IO.Path]::GetFullPath((Join-Path $ScriptsRoot 'guards\kv_ui_guard.ps1'))
if (-not (Test-Path -LiteralPath $guardPath -PathType Leaf)) {
  $findings += [pscustomobject]@{ file=$guardPath; line=0; pattern='MissingGuardLibrary'; text='Guard library is required.' }
} else {
  $guardText = Get-Content -LiteralPath $guardPath -Raw
  $tokens = $null
  $parseErrors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($guardText, [ref]$tokens, [ref]$parseErrors)
  foreach ($error in @($parseErrors)) {
    $findings += [pscustomobject]@{ file=$guardPath; line=$error.Extent.StartLineNumber; pattern='GuardParseError'; text=$error.Message }
  }
  $guardFunctions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
  foreach ($fn in $guardFunctions) {
    $fnName = [string]$fn.Name
    if (($fnName -like 'Invoke-KvGuarded*' -or $fnName -eq 'Assert-KvUiForegroundHwnd') -and $approvedAtomicActions -notcontains $fnName -and $pendingAtomicActions -notcontains $fnName) {
      $findings += [pscustomobject]@{
        file = $guardPath
        line = $fn.Extent.StartLineNumber
        pattern = 'UnclassifiedAtomicAction'
        text = "$fnName must be classified as approved or pending before it can exist in the guard library."
      }
    }
  }
  foreach ($actionName in @($approvedAtomicActions + $pendingAtomicActions | Sort-Object -Unique)) {
    if (@($guardFunctions | Where-Object Name -eq $actionName).Count -ne 1) {
      $findings += [pscustomobject]@{
        file = $guardPath
        line = 0
        pattern = 'AtomicActionImplementationMissing'
        text = "$actionName must have exactly one guard-library implementation."
      }
    }
  }
}

if ($findings.Count -gt 0) {
  Stop-GuardUsageCheck `
    -ErrorCode 'KV_UI_GUARD_STATIC_VIOLATION' `
    -Message 'KV MVP scripts contain raw input or an unapproved atomic UI action.' `
    -Findings $findings `
    -ExitCode 32
}

$result = [pscustomobject]@{
  ok = $true
  operation = 'assert KV MVP UI guard usage'
  scripts_root = $ScriptsRoot
  manifest_path = $ManifestPath
  checked_scripts = $ScriptNames
  approved_atomic_actions = $approvedAtomicActions
  pending_atomic_actions = $pendingAtomicActions
}
if ($OutDir) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'ui_guard_usage_result.json') -Encoding UTF8
}
$result | ConvertTo-Json -Depth 4
