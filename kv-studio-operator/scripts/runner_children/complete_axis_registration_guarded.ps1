param(
    [Parameter(Mandatory=$true)][string]$OutDir,
    [string]$PitchCsv = '20,40',
    [int]$StepTimeoutSec = 12,
    [string]$RepoRoot = 'H:\KeyenceAgent\kv-studio-operator'
)
# 轴向导状态机 —— 全程 **不碰前台**（无 SetForegroundWindow / AttachThreadInput / keybd_event）
# 输入一律 PostMessage：按钮 BM_CLICK、输入框 WM_SETTEXT；每步硬超时，超时立刻抛错并截图。
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;using System.Collections.Generic;using System.Runtime.InteropServices;using System.Text;
public class KvPost {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, string l, uint flags, uint timeout, out IntPtr res);
  public static List<string> Top(int pid){
    var rows=new List<string>();
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p);
      if(p==(uint)pid){
        var t=new StringBuilder(512); GetWindowText(h,t,512);
        var c=new StringBuilder(256); GetClassName(h,c,256);
        rows.Add(h.ToInt64()+"\u0001"+(IsWindowVisible(h)?"1":"0")+"\u0001"+t.ToString()+"\u0001"+c.ToString());
      }
      return true; }, IntPtr.Zero);
    return rows;
  }
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
  // 返回窗口的子按钮：hwnd + 类名 + 文本（对 #32770 可靠 ✓）
  public static List<string> ChildButtons(IntPtr parent){
    var rows=new List<string>();
    EnumChildWindows(parent,(h,l)=>{
      var c=new StringBuilder(128); GetClassName(h,c,128);
      var t=new StringBuilder(256); GetWindowText(h,t,256);
      if(c.ToString().IndexOf("Button",StringComparison.OrdinalIgnoreCase) >= 0){
        rows.Add(h.ToInt64() + "\u0001" + c.ToString() + "\u0001" + t.ToString());
      }
      return true; }, IntPtr.Zero);
    return rows;
  }
  [DllImport("user32.dll")] public static extern IntPtr GetFocus();
  public static bool PostCtrlS(IntPtr hwnd){
    // 向主窗口投递 Ctrl+S（不取前台 ✓）
    PostMessage(hwnd,0x0100,(IntPtr)0x11,IntPtr.Zero);            // WM_KEYDOWN VK_CONTROL
    PostMessage(hwnd,0x0100,(IntPtr)0x53,IntPtr.Zero);            // WM_KEYDOWN 'S'
    System.Threading.Thread.Sleep(120);
    PostMessage(hwnd,0x0101,(IntPtr)0x53,IntPtr.Zero);            // WM_KEYUP 'S'
    PostMessage(hwnd,0x0101,(IntPtr)0x11,IntPtr.Zero);            // WM_KEYUP VK_CONTROL
    return true;
  }
  public static bool Click(IntPtr hwnd){ if(hwnd==IntPtr.Zero){return false;} return PostMessage(hwnd,0x00F5,IntPtr.Zero,IntPtr.Zero); } // BM_CLICK
  public static bool SetText(IntPtr hwnd, string text){
    if(hwnd==IntPtr.Zero){ return false; }
    IntPtr res;
    SendMessageTimeout(hwnd,0x000C,IntPtr.Zero,text,0x0002,2000,out res); // WM_SETTEXT (SMTO_ABORTIFHUNG)
    return true;
  }
}
"@ -ErrorAction SilentlyContinue
$Pitches = @($PitchCsv -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$null = New-Item -ItemType Directory -Force -Path $OutDir
$log = Join-Path $OutDir 'axis_postmessage.log'
function W([string]$m){ $line=(Get-Date).ToString('HH:mm:ss.fff')+'  '+$m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }
function Shot([string]$n){ try{ $b=[System.Windows.Forms.SystemInformation]::VirtualScreen; $bmp=New-Object System.Drawing.Bitmap($b.Width,$b.Height); $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X,$b.Y,0,0,$bmp.Size); $bmp.Save((Join-Path $OutDir $n),[System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose() }catch{ } }
$proc = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
if(-not $proc){ throw 'KV_POST_NO_KVS' }
W ('kvs pid=' + $proc.Id)
function Get-Windows([int]$procId){
    foreach($r in [KvPost]::Top($procId)){
        $p = $r -split [char]1
        [pscustomobject]@{ Hwnd=[IntPtr][long]$p[0]; Visible=($p[1] -eq '1'); Title=$p[2]; Class=$p[3] }
    }
}
function Get-Element([IntPtr]$hwnd){ try{ return [System.Windows.Automation.AutomationElement]::FromHandle($hwnd) }catch{ return $null } }
function Find-InWindow([IntPtr]$hwnd,[string]$controlType,[string]$namePattern,[string]$aid){
    $root=Get-Element $hwnd
    if(-not $root){ return $null }
    foreach($e in @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
        if([string]$e.Current.ControlType.ProgrammaticName -ne $controlType){ continue }
        if($aid){ $a=''; try{ $a=[string]$e.Current.AutomationId }catch{ continue }; if($a -eq $aid){ return $e } ; continue }
        $n=''; try{ $n=[string]$e.Current.Name }catch{ continue }
        if($n -match $namePattern){ return $e }
    }
    return $null
}
function Wait-DialogWin32([string]$textPattern,[string]$tag){
    # 用 Win32 子按钮文本识别（#32770 可靠 ✓），不用 UIA ✗
    $deadline=(Get-Date).AddSeconds($StepTimeoutSec)
    do {
        foreach($win in (Get-Windows $proc.Id)){
            if(-not $win.Visible){ continue }
            foreach($row in [KvPost]::ChildButtons($win.Hwnd)){
                $p=$row -split [char]1
                if($p[2] -match $textPattern){
                    W ('win32 dialog ' + $tag + ' -> [' + $win.Title + '] class=' + $win.Class + ' btn=[' + $p[2] + ']')
                    return [pscustomobject]@{ Window=$win; ButtonHwnd=[IntPtr][long]$p[0]; ButtonText=$p[2] }
                }
            }
        }
        Start-Sleep -Milliseconds 250
    } while((Get-Date) -lt $deadline)
    Shot ('timeout_' + $tag + '.png')
    Show-Windows ('timeout-' + $tag) | Out-Null
    throw ('KV_POST_TIMEOUT: ' + $tag)
}
function Post-ClickHwnd([IntPtr]$hwnd,[string]$tag){
    $ok=[KvPost]::Click($hwnd)
    W ('post BM_CLICK ' + $tag + ' hwnd=' + $hwnd + ' ok=' + $ok)
    Start-Sleep -Milliseconds 700
}
function Wait-Dialog([string]$btnPattern,[string]$tag){
    $deadline=(Get-Date).AddSeconds($StepTimeoutSec)
    do {
        foreach($win in (Get-Windows $proc.Id)){
            if(-not $win.Visible){ continue }
            $b = Find-InWindow $win.Hwnd 'ControlType.Button' $btnPattern ''
            if($b){ W ('dialog found ' + $tag + ' -> [' + $win.Title + ']'); return [pscustomobject]@{ Window=$win; Button=$b } }
        }
        Start-Sleep -Milliseconds 250
    } while((Get-Date) -lt $deadline)
    Shot ('timeout_' + $tag + '.png')
    Show-Windows $('timeout-' + $tag) | Out-Null
    throw ('KV_POST_TIMEOUT: ' + $tag)
}
function Show-Windows([string]$tag){
    $all=@(Get-Windows $proc.Id)
    W ('WINDOWSNAP ' + $tag + ': ' + (($all | ForEach-Object { '[' + $(if($_.Visible){'V'}else{'-'}) + ']' + $_.Title + '(' + $_.Class + ')' }) -join ' || '))
    $all
}
function Post-Click($btn,[string]$tag){
    $h=[IntPtr]0
    try{ $h=[IntPtr]$btn.Current.NativeWindowHandle }catch{ }
    W ('post BM_CLICK ' + $tag + ' btn=[' + [string]$btn.Current.Name + '] hwnd=' + $h)
    $ok=[KvPost]::Click($h)
    if(-not $ok){ W ('BM_CLICK post returned false for ' + $tag) }
    Start-Sleep -Milliseconds 600
}
$Pitches=@($PitchCsv -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
W ('pitches=' + ($Pitches -join '/') + '  stepTimeout=' + $StepTimeoutSec + 's')

# 状态1: 批量登录轴 → OK
$d1 = Wait-DialogWin32 '^\s*OK\s*$' 'batch-axis'
Post-ClickHwnd $d1.ButtonHwnd 'batch-axis-OK'
# 状态2: 登录完成（无标题 ✗ → 按 确定 按钮识别 ✓）
$d2 = Wait-DialogWin32 '^确定$' 'login-done'
Post-ClickHwnd $d2.ButtonHwnd 'login-done'
# 状态3: 坐标转换设定确认 → 是(Y)
$d3 = Wait-DialogWin32 '是' 'coordinate-confirm'
Post-ClickHwnd $d3.ButtonHwnd 'coordinate-confirm'
# 状态4: 向导（有标题 ✓）
$w4=$null
$deadline=(Get-Date).AddSeconds($StepTimeoutSec)
do{
    foreach($win in (Get-Windows $proc.Id)){
        if(-not $win.Visible){ continue }
        if($win.Title -match '坐标转换计算'){ $w4=$win; break }
    }
    if($w4){ break }
    Start-Sleep -Milliseconds 250
} while((Get-Date) -lt $deadline)
if(-not $w4){ Shot 'timeout_wizard.png'; Show-Windows 'timeout-wizard' | Out-Null; throw 'KV_POST_TIMEOUT: wizard' }
W ('wizard [' + $w4.Title + ']')
for($i=0; $i -lt $Pitches.Count; $i++){
    $wi=$null
    foreach($win in (Get-Windows $proc.Id)){ if($win.Visible -and $win.Title -match '坐标转换计算'){ $wi=$win; break } }
    if(-not $wi){ W ('axis ' + ($i+1) + ' wizard missing'); break }
    W ('axis ' + ($i+1) + ' [' + $wi.Title + '] pitch=' + $Pitches[$i])
    $edit = Find-InWindow $wi.Hwnd 'ControlType.Edit' '' '_textBoxParameter'
    if($edit){
        $eh=[IntPtr]0
        try{ $eh=[IntPtr]$edit.Current.NativeWindowHandle }catch{ }
        [void][KvPost]::SetText($eh,$Pitches[$i])
        Start-Sleep -Milliseconds 300
    } else { W 'parameter edit not found' }
    $calc = Find-InWindow $wi.Hwnd 'ControlType.Button' '执行计算' ''
    if($calc){ Post-Click $calc ('calc-' + ($i+1)) } else { W 'calc button not found' }
    $rd = Find-InWindow $wi.Hwnd 'ControlType.Edit' '' '_textBoxRatio'
    $rv=''; if($rd){ try{ $rv=[string]$rd.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ } }
    W ('axis ' + ($i+1) + ' ratio=' + $rv)
    if($i -lt ($Pitches.Count-1)){
        $nx = Find-InWindow $wi.Hwnd 'ControlType.Button' '下一轴' ''
        if($nx){ Post-Click $nx ('next-' + ($i+1)) } else { W 'next-axis button not found'; break }
    }
}
# 退出向导 → 确认是(Y)（不再用 Alt+Y ✓ 全程不碰前台 ✓）
$wx=$null
foreach($win in (Get-Windows $proc.Id)){ if($win.Visible -and $win.Title -match '坐标转换计算'){ $wx=$win; break } }
if($wx){
    $ex = Find-InWindow $wx.Hwnd 'ControlType.Button' '退出向导' ''
    if($ex){ Post-Click $ex 'exit-wizard' } else { W 'exit-wizard button not found' }
}
$d5 = Wait-DialogWin32 '是' 'exit-confirm'
Post-ClickHwnd $d5.ButtonHwnd 'exit-confirm-yes'
Shot 'after_exit.png'
# 断言：向导与确认都不再出现
Start-Sleep -Milliseconds 800
$left=0
foreach($win in (Get-Windows $proc.Id)){ if($win.Visible -and $win.Title -match '坐标转换计算'){ $left++ } }
W ('wizard windows left = ' + $left)
if($left -gt 0){ Shot 'wizard_still_open.png'; throw 'KV_POST_WIZARD_STILL_OPEN' }
W 'save via PostMessage Ctrl+S (no foreground)'
$mainWin=$null
foreach($win in (Get-Windows $proc.Id)){ if($win.Visible -and $win.Title -match '^KV STUDIO\s*-\s*\['){ $mainWin=$win; break } }
if(-not $mainWin){ throw 'KV_POST_MAIN_WINDOW_NOT_FOUND' }
[void][KvPost]::PostCtrlS($mainWin.Hwnd)
Start-Sleep -Seconds 2
$title=''; try{ $title=[string](Get-Process -Id $proc.Id).MainWindowTitle }catch{ }
W ('title after PostCtrlS = [' + $title + ']')
if($title -match '\*'){
    W 'first PostCtrlS did not clear the dirty marker, retry once'
    [void][KvPost]::PostCtrlS($mainWin.Hwnd)
    Start-Sleep -Seconds 2
    try{ $title=[string](Get-Process -Id $proc.Id).MainWindowTitle }catch{ }
    W ('retry title = [' + $title + ']')
}
Shot 'z_final.png'
if($title -match '\*'){
    # PostMessage 对"非活动窗口"的快捷键无效 ✗ → 这一步必须用守卫（**全程唯一一次前台** ✓）
    W 'save needs the guard once (PostMessage keystrokes are ignored when the window is not active)'
    $guardSave = Join-Path $OutDir 'guard_save.ps1'
    $mh=[long]$mainWin.Hwnd
    $body = @"
`$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Windows.Forms
. '$RepoRoot\scripts\guards\kv_ui_guard.ps1'
`$null = Initialize-KvUiGuard -OutDir '$OutDir\guard_save'
Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$mh) -Step 'final save (only foreground call)' -Keys '^s' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 3500
"@
    [IO.File]::WriteAllText($guardSave,$body,(New-Object System.Text.UTF8Encoding($false)))
    & powershell -NoProfile -ExecutionPolicy Bypass -File $guardSave 2>&1 | ForEach-Object { W ('guard-save: ' + $_) }
    Start-Sleep -Seconds 3
    try{ $title=[string](Get-Process -Id $proc.Id).MainWindowTitle }catch{ }
    W ('title after guard save = [' + $title + ']')
}
if($title -match '\*'){ throw 'KV_POST_SAVE_DIRTY' }
W 'flow finished: dialogs+wizard by PostMessage (no foreground), save by guard (1 call)'