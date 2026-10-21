param([int]$WaitSeconds = 0)
$ErrorActionPreference = 'Stop'
$repo = 'H:\KeyenceAgent\kv-studio-operator'
. "$repo\scripts\kv_dialog_post.ps1"
Add-Type -AssemblyName UIAutomationClient
if ($WaitSeconds -gt 0) { Start-Sleep -Seconds $WaitSeconds }
$p = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Host '  ASSERT FAIL: KVS not running'; exit 1 }
$main = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
$tree = @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.Tree' })[0]
if (-not $tree) { Write-Host '  ASSERT FAIL: project tree not found'; exit 1 }
$h = [IntPtr]0
try { $h = [IntPtr]$tree.Current.NativeWindowHandle } catch { }
Add-Type -TypeDefinition @"
using System;using System.Runtime.InteropServices;
public class NavOpen {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr h, ref POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  public static IntPtr LP(int x,int y){ return (IntPtr)((y << 16) | (x & 0xFFFF)); }
  public static void Dbl(IntPtr hwnd,int sx,int sy){ var q=new POINT(); q.X=sx; q.Y=sy; ScreenToClient(hwnd, ref q); var lp=LP(q.X,q.Y);
    PostMessage(hwnd,0x0201,(IntPtr)1,lp); PostMessage(hwnd,0x0202,IntPtr.Zero,lp); PostMessage(hwnd,0x0203,(IntPtr)1,lp); PostMessage(hwnd,0x0202,IntPtr.Zero,lp); }
}
"@ -ErrorAction SilentlyContinue
function Items { @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.TreeItem' }) }
foreach ($nm in @('单元配置', '[0]  KV-X520', '运动设定', '轴设定')) {
    $n = (Items) | Where-Object { [string]$_.Current.Name -eq $nm } | Select-Object -First 1
    if (-not $n) { Write-Host ('  ASSERT FAIL: folder not found ' + $nm); exit 1 }
    try { $n.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand() } catch { }
    Start-Sleep -Milliseconds 700
}
foreach ($nm in @('轴1:Axis_1', '轴控制设定')) {
    $n = (Items) | Where-Object { [string]$_.Current.Name -eq $nm } | Select-Object -First 1
    if (-not $n) { Write-Host ('  ASSERT FAIL: node not found ' + $nm); exit 1 }
    try { $n.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch { }
    Start-Sleep -Milliseconds 300
    $r = $n.Current.BoundingRectangle
    [NavOpen]::Dbl($h, [int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2))
    Start-Sleep -Seconds 2
}
Write-Host '  axis control table page opened'
exit 0