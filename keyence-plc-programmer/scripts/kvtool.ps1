param(
  [Parameter(Mandatory=$true, Position=0)]
  [ValidateSet(
    'list',
    'doctor',
    'stage',
    'run-staged',
    'run-interactive',
    'export-mnm',
    'import-mnm',
    'convert-collect',
    'collect-visible-errors',
    'verify-names',
    'resolve-local',
    'create-project-local',
    'local-acceptance',
    'init-evidence-loop',
    'review-evidence',
    'watch-evidence',
    'manifest'
  )]
  [string]$Command,

  [string]$ProjectPath = '',
  [string]$MnmPath = '',
  [string]$ExpectedModuleName = '',
  [string]$ProjectName = '',
  [string]$ProjectRoot = '',
  [string]$CpuModel = 'KV-X550',
  [string]$KvsExe = '',
  [int]$BenchmarkSeconds = 300,
  [string]$OutDir = '',
  [string]$TaskId = '',
  [string]$EvidenceRoot = '',
  [string]$ImplementationInbox = '',
  [int]$DebounceSeconds = 2,
  [string]$ReviewerModel = '',
  [string]$LocalScriptPath = '',
  [string]$VmScriptPath = '',
  [string]$HolderId = 'codex-official-repro-103',
  [int]$Vmid = 103,
  [int]$TimeoutSeconds = 900,
  [string]$HostName = '192.168.1.26',
  [string]$UserName = 'agent',
  [string]$Password = $env:VM103_SSH_PASSWORD,
  [switch]$SaveAfterImport,
  [switch]$RestartKvs,
  [switch]$Once,
  [switch]$NoAgent
)

$ErrorActionPreference = 'Stop'
$ToolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function ToolPath {
  param([string]$Name)
  return (Join-Path $ToolRoot $Name)
}

function Invoke-ToolScript {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Script,
    [object[]]$ScriptArguments = @()
  )
  $path = ToolPath $Script
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Tool script not found: $path"
  }
  $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $path) + @($ScriptArguments)
  & powershell.exe @childArgs
  exit $LASTEXITCODE
}

function Add-Arg {
  param(
    [string[]]$Items,
    [string]$Name,
    [object]$Value
  )
  if ($null -ne $Value -and [string]$Value -ne '') {
    return @($Items + @($Name, [string]$Value))
  }
  return $Items
}

function Add-SwitchArg {
  param(
    [string[]]$Items,
    [string]$Name,
    [bool]$Enabled
  )
  if ($Enabled) {
    return @($Items + @($Name))
  }
  return $Items
}

function Show-List {
  $stable = @(
    [pscustomobject]@{Command='doctor'; Script='check_vm103_prereqs.ps1'; Purpose='host-side VM/tool preflight'},
    [pscustomobject]@{Command='stage'; Script='stage_vm103_script_encoded.ps1'; Purpose='copy a local script into VM 103'},
    [pscustomobject]@{Command='run-staged'; Script='run_vm103_staged_script.ps1'; Purpose='run a script already staged in VM 103'},
    [pscustomobject]@{Command='run-interactive'; Script='run_vm103_interactive_script_ssh.ps1'; Purpose='run a UI script in the logged-on VM desktop'},
    [pscustomobject]@{Command='export-mnm'; Script='export_mnm.ps1'; Purpose='drive KV STUDIO MNM export'},
    [pscustomobject]@{Command='import-mnm'; Script='import_mnm.ps1'; Purpose='drive KV STUDIO MNM import and persistence check'},
    [pscustomobject]@{Command='convert-collect'; Script='convert_collect.ps1'; Purpose='open project, run Ctrl+F9, collect screenshots/UI/clipboard'},
    [pscustomobject]@{Command='collect-visible-errors'; Script='collect_visible_convert_errors.ps1'; Purpose='copy visible bottom conversion tree'},
    [pscustomobject]@{Command='verify-names'; Script='verify_project_names.ps1'; Purpose='search project files for expected names'},
    [pscustomobject]@{Command='resolve-local'; Script='resolve_kvstudio_local.ps1'; Purpose='resolve local KV STUDIO shortcut/install'},
    [pscustomobject]@{Command='create-project-local'; Script='create_project_local.ps1'; Purpose='create local KV STUDIO project without image positioning'},
    [pscustomobject]@{Command='local-acceptance'; Script='local_kvstudio_acceptance.ps1'; Purpose='5-minute local create/import/roundtrip/convert benchmark'},
    [pscustomobject]@{Command='init-evidence-loop'; Script='init_evidence_loop.ps1'; Purpose='create deterministic git-backed evidence folder'},
    [pscustomobject]@{Command='review-evidence'; Script='invoke_evidence_review.ps1'; Purpose='force diff capture and reviewer-agent audit'},
    [pscustomobject]@{Command='watch-evidence'; Script='watch_evidence_loop.ps1'; Purpose='passive FileSystemWatcher trigger for evidence review'}
  )
  $stable | Format-Table -AutoSize
}

function Get-ManifestPath {
  $candidates = @(
    (ToolPath 'toolkit_manifest.json'),
    (Join-Path (Split-Path -Parent $ToolRoot) 'references\kvstudio-toolkit-manifest.json')
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }
  throw ('Toolkit manifest not found. Checked: ' + ($candidates -join '; '))
}

switch ($Command) {
  'list' {
    Show-List
    return
  }
  'manifest' {
    Get-Content -LiteralPath (Get-ManifestPath)
    return
  }
  'doctor' {
    $args = @()
    $args = Add-Arg $args '-HolderId' $HolderId
    $args = Add-Arg $args '-Vmid' $Vmid
    Invoke-ToolScript 'check_vm103_prereqs.ps1' $args
  }
  'stage' {
    if (-not $LocalScriptPath -or -not $VmScriptPath) {
      throw 'stage requires -LocalScriptPath and -VmScriptPath.'
    }
    $args = @('-LocalScriptPath', $LocalScriptPath, '-VmScriptPath', $VmScriptPath)
    $args = Add-Arg $args '-HolderId' $HolderId
    $args = Add-Arg $args '-TimeoutSeconds' $TimeoutSeconds
    Invoke-ToolScript 'stage_vm103_script_encoded.ps1' $args
  }
  'run-staged' {
    if (-not $VmScriptPath) {
      throw 'run-staged requires -VmScriptPath.'
    }
    $args = @('-VmScriptPath', $VmScriptPath)
    $args = Add-Arg $args '-HolderId' $HolderId
    $args = Add-Arg $args '-TimeoutSeconds' $TimeoutSeconds
    Invoke-ToolScript 'run_vm103_staged_script.ps1' $args
  }
  'run-interactive' {
    if (-not $LocalScriptPath) {
      throw 'run-interactive requires -LocalScriptPath.'
    }
    $args = @('-LocalScriptPath', $LocalScriptPath)
    $args = Add-Arg $args '-VmScriptPath' $VmScriptPath
    $args = Add-Arg $args '-HostName' $HostName
    $args = Add-Arg $args '-UserName' $UserName
    $args = Add-Arg $args '-Password' $Password
    $args = Add-Arg $args '-TimeoutSeconds' $TimeoutSeconds
    Invoke-ToolScript 'run_vm103_interactive_script_ssh.ps1' $args
  }
  'export-mnm' {
    $args = @()
    $args = Add-Arg $args '-ProjectPath' $ProjectPath
    $args = Add-Arg $args '-OutDir' $OutDir
    Invoke-ToolScript 'export_mnm.ps1' $args
  }
  'import-mnm' {
    if (-not $MnmPath) {
      throw 'import-mnm requires -MnmPath.'
    }
    $args = @('-MnmPath', $MnmPath)
    $args = Add-Arg $args '-ProjectPath' $ProjectPath
    $args = Add-Arg $args '-OutDir' $OutDir
    $args = Add-Arg $args '-ExpectedModuleName' $ExpectedModuleName
    $args = Add-SwitchArg $args '-SaveAfterImport' $SaveAfterImport.IsPresent
    Invoke-ToolScript 'import_mnm.ps1' $args
  }
  'convert-collect' {
    if (-not $ProjectPath) {
      throw 'convert-collect requires -ProjectPath.'
    }
    $args = @('-ProjectPath', $ProjectPath)
    $args = Add-Arg $args '-OutDir' $OutDir
    $args = Add-SwitchArg $args '-RestartKvs' $RestartKvs.IsPresent
    Invoke-ToolScript 'convert_collect.ps1' $args
  }
  'collect-visible-errors' {
    $args = @()
    $args = Add-Arg $args '-OutDir' $OutDir
    Invoke-ToolScript 'collect_visible_convert_errors.ps1' $args
  }
  'verify-names' {
    $args = @()
    $args = Add-Arg $args '-ProjectDir' $ProjectPath
    $args = Add-Arg $args '-OutDir' $OutDir
    Invoke-ToolScript 'verify_project_names.ps1' $args
  }
  'resolve-local' {
    $toolArgs = @()
    $toolArgs = Add-Arg $toolArgs '-OutDir' $OutDir
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (ToolPath 'resolve_kvstudio_local.ps1') @toolArgs
    exit $LASTEXITCODE
  }
  'create-project-local' {
    if (-not $ProjectName) { throw 'create-project-local requires -ProjectName.' }
    if (-not $ProjectRoot) { throw 'create-project-local requires -ProjectRoot.' }
    $toolArgs = @('-ProjectName', $ProjectName, '-ProjectRoot', $ProjectRoot)
    $toolArgs = Add-Arg $toolArgs '-CpuModel' $CpuModel
    $toolArgs = Add-Arg $toolArgs '-KvsExe' $KvsExe
    $toolArgs = Add-Arg $toolArgs '-OutDir' $OutDir
    $toolArgs = Add-SwitchArg $toolArgs '-RestartKvs' $RestartKvs.IsPresent
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (ToolPath 'create_project_local.ps1') @toolArgs
    exit $LASTEXITCODE
  }
  'local-acceptance' {
    if (-not $MnmPath) { throw 'local-acceptance requires -MnmPath.' }
    $toolArgs = @('-MnmPath', $MnmPath)
    $toolArgs = Add-Arg $toolArgs '-ProjectName' $ProjectName
    $toolArgs = Add-Arg $toolArgs '-ProjectRoot' $ProjectRoot
    $toolArgs = Add-Arg $toolArgs '-ExistingProjectPath' $ProjectPath
    $toolArgs = Add-Arg $toolArgs '-CpuModel' $CpuModel
    $toolArgs = Add-Arg $toolArgs '-ExpectedModuleName' $ExpectedModuleName
    $toolArgs = Add-Arg $toolArgs '-KvsExe' $KvsExe
    $toolArgs = Add-Arg $toolArgs '-OutDir' $OutDir
    $toolArgs = Add-Arg $toolArgs '-BenchmarkSeconds' $BenchmarkSeconds
    $toolArgs = Add-SwitchArg $toolArgs '-RestartKvs' $RestartKvs.IsPresent
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (ToolPath 'local_kvstudio_acceptance.ps1') @toolArgs
    exit $LASTEXITCODE
  }
  'init-evidence-loop' {
    if (-not $TaskId) { throw 'init-evidence-loop requires -TaskId.' }
    $toolArgs = @('-TaskId', $TaskId)
    $toolArgs = Add-Arg $toolArgs '-Root' $ProjectRoot
    $toolArgs = Add-Arg $toolArgs '-ImplementationInbox' $ImplementationInbox
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (ToolPath 'init_evidence_loop.ps1') @toolArgs
    exit $LASTEXITCODE
  }
  'review-evidence' {
    if (-not $EvidenceRoot) { throw 'review-evidence requires -EvidenceRoot.' }
    $toolArgs = @('-EvidenceRoot', $EvidenceRoot)
    $toolArgs = Add-Arg $toolArgs '-ReviewerModel' $ReviewerModel
    $toolArgs = Add-SwitchArg $toolArgs '-NoAgent' $NoAgent.IsPresent
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (ToolPath 'invoke_evidence_review.ps1') @toolArgs
    exit $LASTEXITCODE
  }
  'watch-evidence' {
    if (-not $EvidenceRoot) { throw 'watch-evidence requires -EvidenceRoot.' }
    $toolArgs = @('-EvidenceRoot', $EvidenceRoot, '-DebounceSeconds', $DebounceSeconds)
    $toolArgs = Add-Arg $toolArgs '-ReviewerModel' $ReviewerModel
    $toolArgs = Add-SwitchArg $toolArgs '-Once' $Once.IsPresent
    $toolArgs = Add-SwitchArg $toolArgs '-NoAgent' $NoAgent.IsPresent
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (ToolPath 'watch_evidence_loop.ps1') @toolArgs
    exit $LASTEXITCODE
  }
}
