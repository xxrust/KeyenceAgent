param(
  [int[]]$VmIds = @(101, 102, 103),
  [string]$OperatorScript = "$env:USERPROFILE\.codex\skills\windows-vm-codex-operator\scripts\windows_vm_operator.py",
  [string]$PveSsh = $env:KV_PVE_SSH,
  [int]$PveSshPort = 22,
  [string]$HolderPrefix = 'codex-keyence-sync',
  [string]$IsolatedHomeRoot = 'C:\Users\Public\KVSkillPractice\isolated_codex_home',
  [string]$ArtifactRoot = 'C:\Users\Public\KVSkillPractice\isolated_agent',
  [string]$Python = ''
)

$ErrorActionPreference = 'Stop'

if (-not $PveSsh) {
  throw 'PveSsh was not supplied. Set KV_PVE_SSH or pass -PveSsh.'
}

if (-not (Test-Path -LiteralPath $OperatorScript)) {
  throw "windows_vm_operator.py not found: $OperatorScript"
}

if (-not $Python) {
  $pythonCandidates = @()
  $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
  if ($pythonCommand) {
    $pythonCandidates += $pythonCommand.Source
  }
  $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
  if ($pythonCommand) {
    $pythonCandidates += $pythonCommand.Source
  }
  $pythonCandidates += @(
    "$env:USERPROFILE\.pyenv\pyenv-win\versions\3.10.11\python.exe",
    "$env:USERPROFILE\.pyenv\pyenv-win\versions\3.11.9\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
  )

  $Python = $pythonCandidates |
    Where-Object { $_ -and ($_ -notmatch '\.bat$|\.cmd$') -and (Test-Path -LiteralPath $_) } |
    Select-Object -First 1

  if (-not $Python) {
    throw 'No real python.exe found. Pass -Python C:\path\to\python.exe; batch shims corrupt multiline QGA scripts.'
  }
}

if ($Python -match '\.bat$|\.cmd$' -or -not (Test-Path -LiteralPath $Python)) {
  throw "Refusing invalid Python executable: $Python"
}

function Invoke-VmPowerShell {
  param(
    [int]$VmId,
    [string]$Script
  )

  $holderId = "$HolderPrefix-$VmId"
  $args = @(
    $OperatorScript,
    '--pve-ssh', $PveSsh,
    '--pve-ssh-port', [string]$PveSshPort,
    'ps',
    '--vmid', [string]$VmId,
    '--holder-id', $holderId,
    '--require-reserved',
    '--timeout-seconds', '180',
    '--',
    $Script
  )

  $output = & $Python @args
  if ($LASTEXITCODE -ne 0) {
    throw "VM $VmId command failed with exit code $LASTEXITCODE.`n$output"
  }
  $output
}

$results = @()

foreach ($vmId in $VmIds) {
  $isolatedHome = Join-Path $IsolatedHomeRoot "vm$vmId"
  $artifactDir = Join-Path $ArtifactRoot "vm$vmId"
  $moduleName = "AgentSmoke$vmId"
  $mnmPath = Join-Path $artifactDir "$moduleName`_tool.mnm"
  $reportPath = Join-Path $artifactDir 'tool_report.md'

  $remoteScript = @"
`$ErrorActionPreference = 'Stop'
`$isolatedHome = '$isolatedHome'
`$artifactDir = '$artifactDir'
`$moduleName = '$moduleName'
`$mnmPath = '$mnmPath'
`$reportPath = '$reportPath'

New-Item -ItemType Directory -Force -Path `$artifactDir | Out-Null

`$skillRoot = Join-Path `$isolatedHome 'skills\keyence-plc-programmer'
`$skillMd = Join-Path `$skillRoot 'SKILL.md'
`$smokeScript = Join-Path `$skillRoot 'scripts\new_mnm_smoke.ps1'
`$wikiDb = Join-Path `$isolatedHome 'llm-wiki-v2-keyence\wiki.v2.cleaned.db'

if (-not (Test-Path -LiteralPath `$skillMd)) { throw "Missing skill: `$skillMd" }
if (-not (Test-Path -LiteralPath `$smokeScript)) { throw "Missing smoke script: `$smokeScript" }
if (-not (Test-Path -LiteralPath `$wikiDb)) { throw "Missing wiki db: `$wikiDb" }

`$skillText = [IO.File]::ReadAllText(`$skillMd, [Text.Encoding]::UTF8)
if (`$skillText.Length -gt 0 -and [int][char]`$skillText[0] -eq 65279) {
  `$skillText = `$skillText.Substring(1)
  [IO.File]::WriteAllText(`$skillMd, `$skillText, [Text.UTF8Encoding]::new(`$false))
}

Remove-Item -LiteralPath (Join-Path `$isolatedHome 'memories') -Recurse -Force -ErrorAction SilentlyContinue
`$memoriesBefore = Test-Path -LiteralPath (Join-Path `$isolatedHome 'memories')

& `$smokeScript -ModuleName `$moduleName -OutPath `$mnmPath | Out-Null

`$memoriesAfter = Test-Path -LiteralPath (Join-Path `$isolatedHome 'memories')
`$wikiBytes = (Get-Item -LiteralPath `$wikiDb).Length
`$skillBytes = [IO.File]::ReadAllBytes(`$skillMd)
`$skillFirst3 = [BitConverter]::ToString(`$skillBytes[0..2])
`$mnmText = Get-Content -LiteralPath `$mnmPath -Raw

`$reportLines = @(
  '# VM$vmId isolated KEYENCE PLC smoke report',
  ('skill: ' + `$skillMd),
  ('smoke_script: ' + `$smokeScript),
  ('CODEX_HOME: ' + `$isolatedHome),
  ('skill_first3: ' + `$skillFirst3),
  ('memories_before: ' + `$memoriesBefore),
  ('memories_after: ' + `$memoriesAfter),
  ('wiki_db: ' + `$wikiDb),
  ('wiki_db_bytes: ' + `$wikiBytes),
  ('mnm: ' + `$mnmPath)
)
[IO.File]::WriteAllLines(`$reportPath, `$reportLines, [Text.UTF8Encoding]::new(`$false))

[pscustomobject]@{
  vm = $vmId
  ok = `$true
  isolated_home = `$isolatedHome
  skill = `$skillMd
  skill_first3 = `$skillFirst3
  memories_before = `$memoriesBefore
  memories_after = `$memoriesAfter
  wiki_db = `$wikiDb
  wiki_db_bytes = `$wikiBytes
  mnm = `$mnmPath
  report = `$reportPath
  mnm_text = `$mnmText
} | ConvertTo-Json -Compress
"@

  $raw = Invoke-VmPowerShell -VmId $vmId -Script $remoteScript
  $jsonLine = ($raw -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
  if (-not $jsonLine) {
    throw "VM $vmId did not return JSON.`n$raw"
  }
  $results += ($jsonLine | ConvertFrom-Json)
}

$results | ConvertTo-Json -Depth 5
