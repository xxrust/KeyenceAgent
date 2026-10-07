param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'scripts'
$fixture=Join-Path ([IO.Path]::GetFullPath($OutDir)) 'fixture'
$null=New-Item -ItemType Directory -Force -Path (Join-Path $fixture 'guards'),(Join-Path $fixture 'runner_children')
Copy-Item -LiteralPath (Join-Path $source 'guards/kv_ui_guard.ps1') -Destination (Join-Path $fixture 'guards/kv_ui_guard.ps1')
$gate=Join-Path $source 'gates/assert_kv_mvp_ui_guard_usage.ps1'
$manifest=Join-Path $source 'script_manifest.json'
$rows=@()
foreach($case in @('same_window_rejected','multiline_rejected','colon_rejected','modal_transition_accepted')) {
  $code=if($case -eq 'same_window_rejected') {
    'Invoke-KvGuardedSendKeys -TargetHwnd $hwnd -Step "create" -Keys ''^n'' -ExpectedTitleLike ''KV STUDIO*'''
  } elseif($case -eq 'multiline_rejected') {
    'Invoke-KvGuardedSendKeys -TargetHwnd $hwnd `' + [Environment]::NewLine + ' -Step "create" -Keys ''^n'''
  } elseif($case -eq 'colon_rejected') {
    'Invoke-KvGuardedSendKeys -TargetHwnd $hwnd -Step "create" -Keys:''^n'''
  } else {
    'Invoke-KvGuardedCtrlChord -TargetHwnd $hwnd -Step "create" -Vk 0x4E -AllowModalAfter'
  }
  $code | Set-Content -LiteralPath (Join-Path $fixture 'runner_children/test.ps1') -Encoding UTF8
  $dest=Join-Path $OutDir $case
  $ErrorActionPreference='Continue'
  try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $gate -ScriptsRoot $fixture -ManifestPath $manifest -ScriptNames 'runner_children/test.ps1' -OutDir $dest *> (Join-Path $OutDir ($case+'.txt'))
    $exitCode=$LASTEXITCODE
  } finally { $ErrorActionPreference='Stop' }
  $r=Get-Content -LiteralPath (Join-Path $dest 'ui_guard_usage_result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($case -ne 'modal_transition_accepted') {
    if($exitCode -eq 0 -or @($r.findings|Where-Object pattern -eq 'WrongNewProjectTransition').Count -ne 1){throw 'Unsafe same-window transition accepted'}
  } elseif($exitCode -ne 0 -or !$r.ok){throw 'Registered modal-aware transition rejected'}
  $rows+=@{name=$case;ok=$true;exit_code=$exitCode}
}
@{ok=$true;ui_started=$false;scope='literal Ctrl+N caller contract regression';tests=$rows}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
'Passed create transition static regression'
