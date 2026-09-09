param([Parameter(Mandatory=$true)][string]$SourceDir,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$env:KV_WORKFLOW_RUN_LOG=Join-Path $OutDir 'run.log'
. (Join-Path $PSScriptRoot '..\guards\kv_ui_guard.ps1')
Initialize-KvUiGuard -OutDir $OutDir
$p=@(Get-Process Kvs -ErrorAction SilentlyContinue)
if($p.Count -gt 1){throw 'Multiple KVS processes'}
if($p.Count -eq 1){
 if($p[0].MainWindowTitle -notlike '*[[]ScopeReuseRegression*'){throw 'Unowned open project'}
 Invoke-KvGuardedCtrlChord -TargetHwnd $p[0].MainWindowHandle -Step 'save disposable error regression' -Vk 0x53 -ExpectedTitleLike '*ScopeReuseRegression*'
 if(-not $p[0].CloseMainWindow()){throw 'Cannot close regression window'}
 if(-not $p[0].WaitForExit(8000)){throw 'Regression close timed out; no forced termination'}
}
$copy=Join-Path $OutDir 'project'
if(Test-Path -LiteralPath $copy){throw 'Snapshot copy target already exists'}
Copy-Item -LiteralPath $SourceDir -Destination $copy -Recurse
$kpr=@(Get-ChildItem -LiteralPath $copy -Filter *.kpr)
if($kpr.Count -ne 1){throw 'Expected one source project'}
$manifest=@{source=$SourceDir;copy=$copy;project_path=$kpr[0].FullName;files=@(Get-ChildItem -LiteralPath $SourceDir -File | ForEach-Object {@{name=$_.Name;hash=(Get-FileHash -LiteralPath $_.FullName).Hash}})}
$manifest|ConvertTo-Json -Depth 5|Set-Content (Join-Path $OutDir 'copy_manifest.json') -Encoding UTF8
Start-Process -FilePath H:\Keyence\KVS12\KVS\Kvs.exe -ArgumentList ('"'+$kpr[0].FullName+'"') -WindowStyle Hidden | Out-Null
@{timestamp=(Get-Date).ToString('o');type='project_copy_launch';project_path=$kpr[0].FullName}|ConvertTo-Json -Compress|Add-Content $env:KV_WORKFLOW_RUN_LOG -Encoding UTF8
