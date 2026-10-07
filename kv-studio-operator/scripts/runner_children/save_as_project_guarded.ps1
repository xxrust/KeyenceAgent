<#[
.SYNOPSIS
  Save the currently open KV STUDIO project to a new project path.
.DESCRIPTION
  Fixed one-shot route supplied by the operator: Alt+F, A; the Save As dialog
  owns focus while name/path/comment are pasted; Enter confirms. No probing or
  focus recovery is performed after the dialog is found. Error dialogs are
  copied to evidence, dismissed with Enter, and the Save As dialog is closed by
  Alt+F4.
#>
param(
  [Parameter(Mandatory=$true)][string]$SourceProjectPath,
  [Parameter(Mandatory=$true)][string]$DestinationDirectory,
  [Parameter(Mandatory=$true)][string]$DestinationProjectName,
  [string]$Comment = '',
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 30,
  [switch]$InspectOnly
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force -Path $OutDir,$DestinationDirectory | Out-Null
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'guards\kv_ui_guard.ps1')
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'save_as'
Add-Type -AssemblyName System.Windows.Forms

function Log([string]$Message){Write-KvUiGuardRunLog -Event 'save_as' -Data @{message=$Message}}
function Get-Text([IntPtr]$Hwnd){$b=[Text.StringBuilder]::new(1024);[void][SaveAsWin32]::GetWindowText($Hwnd,$b,$b.Capacity);$b.ToString()}
function Get-Class([IntPtr]$Hwnd){$b=[Text.StringBuilder]::new(256);[void][SaveAsWin32]::GetClassName($Hwnd,$b,$b.Capacity);$b.ToString()}
function Get-Foreground(){[SaveAsWin32]::GetForegroundWindow()}
function Find-ProcessByPath([string]$Path){
  $full=[IO.Path]::GetFullPath($Path)
  $matches=@(Get-CimInstance Win32_Process -Filter "Name='Kvs.exe'" -ErrorAction SilentlyContinue | ? {$_.CommandLine -and $_.CommandLine.IndexOf($full,[StringComparison]::OrdinalIgnoreCase) -ge 0} | % {Get-Process -Id ([int]$_.ProcessId) -ErrorAction SilentlyContinue} | ? {$_.MainWindowHandle -ne 0})
  if($matches.Count -eq 1){return $matches[0]}
  if($matches.Count -gt 1){throw "KV_SAVE_AS_SOURCE_WINDOW_AMBIGUOUS: expected one process for $Path, found $($matches.Count)"}
  $needle=[IO.Path]::GetFileNameWithoutExtension($Path)
  $titleMatches=@(Get-Process Kvs -ErrorAction SilentlyContinue | ? {$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like "*$needle*"})
  if($titleMatches.Count -ne 1){throw "KV_SAVE_AS_SOURCE_WINDOW_AMBIGUOUS: exact path unavailable and title match count is $($titleMatches.Count)"}
  Log "source command line did not contain project path; accepted unique title-bound window pid=$($titleMatches[0].Id)"
  return $titleMatches[0]
}
function Get-Descendants([IntPtr]$Hwnd){
  $root=[Windows.Automation.AutomationElement]::FromHandle($Hwnd)
  if(-not $root){return @()}
  $all=$root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition);$rows=@()
  for($i=0;$i -lt $all.Count;$i++){ $e=$all.Item($i);$r=$e.Current.BoundingRectangle;$rows += [ordered]@{name=[string]$e.Current.Name;automation_id=[string]$e.Current.AutomationId;class_name=[string]$e.Current.ClassName;control_type=[string]$e.Current.ControlType.ProgrammaticName;hwnd=$e.Current.NativeWindowHandle;focus=[bool]$e.Current.HasKeyboardFocus;rect=@($r.X,$r.Y,$r.Width,$r.Height)} }
  $rows
}
if(-not ('SaveAsWin32' -as [type])){Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class SaveAsWin32 {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h,StringBuilder b,int n);
}
"@}

$source=[IO.Path]::GetFullPath($SourceProjectPath);$destDir=[IO.Path]::GetFullPath($DestinationDirectory);$destName=$DestinationProjectName.Trim()
if(-not (Test-Path -LiteralPath $source -PathType Leaf)){throw "KV_SAVE_AS_SOURCE_MISSING: $source"}
if($destName -match '[\\/:*?"<>|]' -or [string]::IsNullOrWhiteSpace($destName)){throw 'KV_SAVE_AS_PROJECT_NAME_INVALID'}
$process=Find-ProcessByPath $source;$main=[IntPtr]$process.MainWindowHandle
try{
  if($InspectOnly){[ordered]@{ok=$true;inspect_only=$true;source=$source;pid=$process.Id}|ConvertTo-Json|Set-Content (Join-Path $OutDir 'save_as_result.json') -Encoding UTF8;exit 0}
  Invoke-KvGuardedOpenSaveAsModal -TargetHwnd $main -Step 'open save as modal' -ExpectedTitleLike 'KV STUDIO*'
  [ordered]@{
    foreground=Get-KvForegroundSnapshot
    focused_element=Get-KvFocusedElementSnapshot
    descendants=@(Get-Descendants $main)
  } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutDir 'save_as_modal_snapshot.json') -Encoding UTF8
  Invoke-KvGuardedModalFocusSequence -Step 'save as focused input sequence' -ProjectName $destName -Directory $destDir -Comment $Comment
  # KV STUDIO creates a project directory named after the project and places
  # the .kpr inside it: <destination directory>\<project name>\<project name>.kpr.
  $destProjectDir=Join-Path $destDir $destName
  $dest=Join-Path $destProjectDir ($destName+'.kpr')
  $deadline=(Get-Date).AddSeconds(8);while(-not (Test-Path -LiteralPath $dest -PathType Leaf) -and (Get-Date)-lt $deadline){Start-Sleep -Milliseconds 200}
  if(-not (Test-Path -LiteralPath $dest -PathType Leaf)){
    $errorHwnd=Get-Foreground
    if($errorHwnd -ne [IntPtr]::Zero){[ordered]@{hwnd=$errorHwnd.ToInt64();title=Get-Text $errorHwnd;text=((Get-Descendants $errorHwnd | % name) -join ' ')}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $OutDir 'save_as_error_dialog.json') -Encoding UTF8}
    Invoke-KvGuardedModalErrorDismissal -Step 'save as error dismissal'
    throw "KV_SAVE_AS_PROJECT_NOT_CREATED: $dest"
  }
  [ordered]@{ok=$true;source=$source;destination_directory=$destDir;destination_project_directory=$destProjectDir;destination=$dest;project_name=$destName;comment=$Comment;pid=$process.Id}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $OutDir 'save_as_result.json') -Encoding UTF8
}catch{$_.Exception.ToString()|Set-Content (Join-Path $OutDir 'fail.txt') -Encoding UTF8;[ordered]@{ok=$false;error_code='KV_SAVE_AS_FAILED';message=$_.Exception.Message;source=$source;evidence=@((Join-Path $OutDir 'run.log'),(Join-Path $OutDir 'fail.txt'))}|ConvertTo-Json|Set-Content (Join-Path $OutDir 'save_as_result.json') -Encoding UTF8;exit 1}
