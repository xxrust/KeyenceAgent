# kv_dialog_post.ps1 —— classic-dialog 交互库（Win32 枚举 + PostMessage，全程不取前台）
#
# 为什么需要它：
#   * 经典对话框是 #32770，UIA 在这些窗口上**枚举不到按钮** ✗
#   * UIA InvokePattern.Invoke() 的 WinForms 实现会先 Control.Focus() ✗ → 焦点抖动 ✓
#   * PostMessage(BM_CLICK) 不需要前台 ✓，也不改焦点 ✓
Add-Type -TypeDefinition @"
using System;using System.Collections.Generic;using System.Runtime.InteropServices;using System.Text;
public class KvDlgPost {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, string l, uint flags, uint timeout, out IntPtr res);
  public static List<string> TopWindows(int pid){
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
  public static List<string> ChildButtons(IntPtr parent){
    var rows=new List<string>();
    EnumChildWindows(parent,(h,l)=>{
      var c=new StringBuilder(128); GetClassName(h,c,128);
      var t=new StringBuilder(256); GetWindowText(h,t,256);
      if(c.ToString().IndexOf("Button",StringComparison.OrdinalIgnoreCase)>=0){
        rows.Add(h.ToInt64()+"\u0001"+c.ToString()+"\u0001"+t.ToString());
      }
      return true; }, IntPtr.Zero);
    return rows;
  }
  public static bool Click(IntPtr hwnd){ if(hwnd==IntPtr.Zero){return false;} return PostMessage(hwnd,0x00F5,IntPtr.Zero,IntPtr.Zero); }
  public static bool SetText(IntPtr hwnd,string text){
    if(hwnd==IntPtr.Zero){ return false; }
    IntPtr res; SendMessageTimeout(hwnd,0x000C,IntPtr.Zero,text,0x0002,2000,out res); return true;
  }
}
"@ -ErrorAction SilentlyContinue

function Get-KvTopWindow {
    # 返回指定进程的顶层窗口（Z 序，第一个最上层 ✓）
    param([Parameter(Mandatory)][int]$ProcessId,[switch]$VisibleOnly)
    foreach($r in [KvDlgPost]::TopWindows($ProcessId)){
        $p = $r -split [char]1
        $vis = ($p[1] -eq '1')
        if($VisibleOnly -and -not $vis){ continue }
        [pscustomobject]@{ Hwnd=[IntPtr][long]$p[0]; Visible=$vis; Title=$p[2]; Class=$p[3] }
    }
}

function Get-KvDialogButton {
    # 在"所有可见顶层窗口"里按按钮文本找按钮（#32770 可靠 ✓）
    param([Parameter(Mandatory)][int]$ProcessId,[Parameter(Mandatory)][string]$TextPattern)
    foreach($win in (Get-KvTopWindow -ProcessId $ProcessId -VisibleOnly)){
        foreach($row in [KvDlgPost]::ChildButtons($win.Hwnd)){
            $p = $row -split [char]1
            if($p[2] -match $TextPattern){
                [pscustomobject]@{ WindowHwnd=$win.Hwnd; WindowTitle=$win.Title; WindowClass=$win.Class; ButtonHwnd=[IntPtr][long]$p[0]; ButtonText=$p[2] }
            }
        }
    }
}

function Wait-KvDialogButton {
    # 每步硬超时 ✓：超时立刻抛错（并给出当时的窗口快照 ✓）
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$TextPattern,
        [int]$TimeoutSeconds = 3,
        [string]$Tag = 'dialog'
    )
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $hit = Get-KvDialogButton -ProcessId $ProcessId -TextPattern $TextPattern
        if($hit){ return $hit }
        Start-Sleep -Milliseconds 150
    } while((Get-Date) -lt $deadline)
    $snap = @(Get-KvTopWindow -ProcessId $ProcessId -VisibleOnly | ForEach-Object { '[' + $_.Title + '(' + $_.Class + ')]' }) -join ' '
    throw ("KV_DIALOG_TIMEOUT [$Tag]: no button matching '$TextPattern' within ${TimeoutSeconds}s. visible windows: $snap")
}

function Invoke-KvButtonPost {
    # PostMessage(BM_CLICK)：不取前台 ✓ 不改焦点 ✓
    param([Parameter(Mandatory)][IntPtr]$ButtonHwnd,[string]$Tag='click')
    $ok=[KvDlgPost]::Click($ButtonHwnd)
    Start-Sleep -Milliseconds 350
    if(-not $ok){ throw "KV_DIALOG_CLICK_FAILED [$Tag]" }
    $true
}

function Set-KvEditText {
    # WM_SETTEXT：写输入框（不取前台 ✓）
    param([Parameter(Mandatory)][IntPtr]$EditHwnd,[Parameter(Mandatory)][string]$Text,[string]$Tag='edit')
    $ok=[KvDlgPost]::SetText($EditHwnd,$Text)
    Start-Sleep -Milliseconds 150
    if(-not $ok){ throw "KV_DIALOG_SETTEXT_FAILED [$Tag]" }
    $true
}