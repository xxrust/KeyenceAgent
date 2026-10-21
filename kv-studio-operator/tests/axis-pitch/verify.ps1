param([Parameter(Mandatory=$true)][string]$OutDir,[Parameter(Mandatory=$true)][string]$Stage)
$ErrorActionPreference = 'Stop'
$fail = { param($m) Write-Host ('  ASSERT FAIL: ' + $m); exit 1 }
if ($Stage -eq 'result') {
    $f = Get-ChildItem $OutDir -Recurse -File -Filter 'axis_pitch_result.json' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $f) { & $fail 'axis_pitch_result.json missing' }
    $j = Get-Content $f.FullName -Encoding UTF8 -Raw | ConvertFrom-Json
    Write-Host ('  ok=' + $j.ok + ' pitch=' + $j.pitch + ' ratio=' + $j.ratio + ' page=' + $j.page_numerator + '/' + $j.page_denominator)
    if ($j.ok -ne $true) { & $fail 'result ok != true' }
    if ([string]$j.pitch -ne '25') { & $fail ('pitch != 25 (' + $j.pitch + ')') }
    if ([string]$j.ratio -notmatch '^400') { & $fail ('ratio != 400 (' + $j.ratio + ')') }
    Write-Host '  [result] PASS'
    exit 0
}
if ($Stage -eq 'reopen') {
    Add-Type -AssemblyName UIAutomationClient
    $repo = 'H:\KeyenceAgent\kv-studio-operator'
    . "$repo\scripts\kv_dialog_post.ps1"
    $p = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { & $fail 'KVS not running after reopen' }
    $main = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
    $tree = @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.Tree' })[0]
    if (-not $tree) { & $fail 'project tree not found' }
    $h = [IntPtr]0; try { $h = [IntPtr]$tree.Current.NativeWindowHandle } catch { }
    Add-Type -TypeDefinition @"
using System;using System.Runtime.InteropServices;
public class TvDbl {
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
        if ($n) { try { $n.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand() } catch { }; Start-Sleep -Milliseconds 700 }
    }
    foreach ($nm in @('轴1:Axis_1', '轴控制设定')) {
        $n = (Items) | Where-Object { [string]$_.Current.Name -eq $nm } | Select-Object -First 1
        if ($n) { try { $n.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch { }; Start-Sleep -Milliseconds 300; $r = $n.Current.BoundingRectangle; [TvDbl]::Dbl($h, [int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)); Start-Sleep -Seconds 2 }
    }
    $btn = $null
    foreach ($el in @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) { $a = ''; try { $a = [string]$el.Current.AutomationId } catch { continue }; if ($a -eq '_buttonTransformCoordinator') { $btn = $el; break } }
    if (-not $btn) { & $fail 'transform button not found' }
    $bh = [IntPtr]0; try { $bh = [IntPtr]$btn.Current.NativeWindowHandle } catch { }
    [void][KvDlgPost]::Click($bh)
    Start-Sleep -Seconds 3
    $wz = $null
    foreach ($win in (Get-KvTopWindow -ProcessId $p.Id -VisibleOnly)) { if ($win.Title -match '坐标转换计算') { $wz = $win; break } }
    if (-not $wz) { & $fail 'coordinate wizard not open' }
    $val = '(missing)'
    foreach ($el in @(([System.Windows.Automation.AutomationElement]::FromHandle($wz.Hwnd)).FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
        $a = ''; try { $a = [string]$el.Current.AutomationId } catch { continue }
        if ($a -eq '_textBoxParameter') { try { $val = [string]$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { }; break }
    }
    Write-Host ('  reopen readback pitch = ' + $val)
    if ($val -ne '25') { & $fail ('reopen pitch != 25 (' + $val + ')') }
    Write-Host '  [reopen] PASS'
    exit 0
}
& $fail ('unknown stage ' + $Stage)