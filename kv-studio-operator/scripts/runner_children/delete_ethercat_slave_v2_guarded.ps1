param(
    [Parameter(Mandatory = $true)][string]$OutDir,
    [int]$Index = 1,
    [switch]$NoSave
)
# 删除 EtherCAT 从站（对象级 ✓）：点进树→↑×N 到根→↓×k→DELETE→确认→保存→名单验证
$ErrorActionPreference = 'Stop'
$repo = 'H:\KeyenceAgent\kv-studio-operator'
. "$repo\scripts\kv_dialog_post.ps1"
. "$repo\scripts\guards\kv_ui_guard.ps1"
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
$null = New-Item -ItemType Directory -Force -Path $OutDir
$log = Join-Path $OutDir 'run.log'
function W([string]$m) { $line = (Get-Date).ToString('HH:mm:ss.fff') + '  ' + $m; Write-Output $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }
function Shot([string]$n) { & powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\scripts\Capture-KvFrame.ps1" -OutDir $OutDir -Name $n | Out-Null }
Add-Type -TypeDefinition @"
using System;using System.Runtime.InteropServices;
public class DelSlave2 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L; public int T; public int R; public int B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public static void Click(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(150); mouse_event(0x0002,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(90); mouse_event(0x0004,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(350); }
  public static int[] Rect(IntPtr h){ var r=new RECT(); GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R-r.L, r.B-r.T }; }
}
"@ -ErrorAction SilentlyContinue

$p = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { throw 'KV_DEL_NO_KVS' }
$kvsHwnd = [IntPtr]$p.MainWindowHandle
$null = Initialize-KvUiGuard -OutDir (Join-Path $OutDir 'guard')
$main = [System.Windows.Automation.AutomationElement]::FromHandle($kvsHwnd)

$projectDir = $null
try { $cl = (Get-CimInstance Win32_Process -Filter ('ProcessId=' + $p.Id)).CommandLine; if ($cl -match '"([^"]+\.kpr)"') { $projectDir = Split-Path -Parent $Matches[1] } } catch { }
if (-not $projectDir) { throw 'KV_DEL_PROJECT_UNKNOWN' }
$xmlPath = Join-Path $projectDir 'WsTreeEnv.xml'
if (-not (Test-Path $xmlPath)) { throw ('KV_DEL_NO_TREE_XML: ' + $xmlPath) }
function Get-Slaves {
    $c = Get-Content $xmlPath -Raw -Encoding UTF8
    @([regex]::Matches($c, '\[(\d+)\]\s*([A-Za-z0-9_\-\. ]{3,40})') | ForEach-Object {
            [pscustomobject]@{ node = [int]$_.Groups[1].Value; name = $_.Groups[2].Value.Trim() }
        } | Sort-Object node -Unique)
}
$before = @(Get-Slaves)
W ('slaves before = ' + $before.Count)
$before | ForEach-Object { W ('  [' + $_.node + '] ' + $_.name) }

$dlg = $null
foreach ($w in (Get-KvTopWindow -ProcessId $p.Id -VisibleOnly)) { if ($w.Title -match 'EtherCAT') { $dlg = $w; break } }
if (-not $dlg) {
    function Tree-Items2 { @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.TreeItem' }) }
    foreach ($nm in @('单元配置', '[0]  KV-X520')) {
        $n = (Tree-Items2) | Where-Object { [string]$_.Current.Name -eq $nm } | Select-Object -First 1
        if ($n) { try { $n.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand() } catch { }; Start-Sleep -Milliseconds 700 }
    }
    $ec = (Tree-Items2) | Where-Object { [string]$_.Current.Name -eq 'EtherCAT' } | Select-Object -First 1
    if (-not $ec) { throw 'KV_DEL_ETHERCAT_NODE_MISSING' }
    $tr = @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.Tree' })[0]
    $th = [IntPtr]0; try { $th = [IntPtr]$tr.Current.NativeWindowHandle } catch { }
    $r = $ec.Current.BoundingRectangle
    try { $ec.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch { }
    Add-Type -TypeDefinition @"
using System;using System.Runtime.InteropServices;
public class DelSlave2Dbl { [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr h, ref POINT p);
 [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
 public static IntPtr LP(int x,int y){ return (IntPtr)((y << 16) | (x & 0xFFFF)); }
 public static void Dbl(IntPtr hwnd,int sx,int sy){ var q=new POINT(); q.X=sx; q.Y=sy; ScreenToClient(hwnd, ref q); var lp=LP(q.X,q.Y);
  PostMessage(hwnd,0x0201,(IntPtr)1,lp); PostMessage(hwnd,0x0202,IntPtr.Zero,lp); PostMessage(hwnd,0x0203,(IntPtr)1,lp); PostMessage(hwnd,0x0202,IntPtr.Zero,lp); } }
"@ -ErrorAction SilentlyContinue
    [DelSlave2Dbl]::Dbl($th, [int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2))
    Start-Sleep -Seconds 4
    foreach ($w in (Get-KvTopWindow -ProcessId $p.Id -VisibleOnly)) { if ($w.Title -match 'EtherCAT') { $dlg = $w; break } }
}
if (-not $dlg) { Shot 'no_dialog.png'; throw 'KV_DEL_DIALOG_NOT_OPEN' }
$dh = [IntPtr]$dlg.Hwnd
[void][DelSlave2]::SetForegroundWindow($dh)
Start-Sleep -Milliseconds 500
$dr = [DelSlave2]::Rect($dh)
W ('dialog [' + $dlg.Title + '] rect=' + ($dr -join ','))
Shot 'd0_opened.png'

$focusX = [int]($dr[0] + $dr[2] * 0.20)
$focusY = [int]($dr[1] + $dr[3] * 0.50)
W ('click inside tree for focus at ' + $focusX + ',' + $focusY)
[DelSlave2]::Click($focusX, $focusY)
Start-Sleep -Milliseconds 500

$n = [Math]::Max(40, $before.Count + 10)
W ('UP x' + $n + ' -> root, then DOWN x' + $Index)
Invoke-KvGuardedSendKeys -TargetHwnd $dh -Step 'to root' -Keys ('{UP ' + $n + '}') -ExpectedTitleLike '*' -SleepMs 800
Invoke-KvGuardedSendKeys -TargetHwnd $dh -Step ('down ' + $Index) -Keys ('{DOWN ' + $Index + '}') -ExpectedTitleLike '*' -SleepMs 600
Shot 'd1_after_nav.png'

W 'DELETE'
try { Invoke-KvGuardedSendKeys -TargetHwnd $dh -Step 'delete slave' -Keys '{DELETE}' -ExpectedTitleLike '*' -SleepMs 1500 }
catch { W ('  guard refused postcondition (modal appeared) - ok') }
Start-Sleep -Seconds 2
Shot 'd2_after_delete.png'

for ($i = 1; $i -le 3; $i++) {
    $hit = [IntPtr]0; $txt = ''
    foreach ($w in (Get-KvTopWindow -ProcessId $p.Id -VisibleOnly)) {
        foreach ($row in [KvDlgPost]::ChildButtons($w.Hwnd)) { $parts = $row -split [char]1; if ($parts[2] -match '^(是|确定)') { $hit = [IntPtr][long]$parts[0]; $txt = $parts[2]; break } }
        if ($hit -ne [IntPtr]0) { break }
    }
    if ($hit -eq [IntPtr]0) { break }
    W ('click [' + $txt + '] #' + $i)
    [void][KvDlgPost]::Click($hit)
    Start-Sleep -Seconds 2
}
Shot 'd3_after_confirm.png'

foreach ($w in (Get-KvTopWindow -ProcessId $p.Id -VisibleOnly)) {
    if ($w.Title -match 'EtherCAT') {
        foreach ($row in [KvDlgPost]::ChildButtons($w.Hwnd)) { $parts = $row -split [char]1; if ($parts[2] -match '^OK') { [void][KvDlgPost]::Click([IntPtr][long]$parts[0]); W 'dialog OK'; break } }
    }
}
Start-Sleep -Seconds 3

if (-not $NoSave) {
    try { Invoke-KvGuardedSendKeys -TargetHwnd $kvsHwnd -Step 'save after delete' -Keys '^s' -ExpectedTitleLike '*' -SleepMs 4000 } catch { W ('  save guard: ' + $_.Exception.Message) }
    Start-Sleep -Seconds 2
    W ('title=[' + [string]$p.MainWindowTitle + ']')
}
Shot 'd4_saved.png'
$after = @(Get-Slaves)
W ('slaves after = ' + $after.Count)
$after | ForEach-Object { W ('  [' + $_.node + '] ' + $_.name) }
$beforeNodes = @($before | ForEach-Object { $_.node })
$afterNodes = @($after | ForEach-Object { $_.node })
$removed = @($before | Where-Object { $_.node -notin $afterNodes })
$ok = (($after.Count) -eq ($before.Count - 1)) -and ($removed.Count -eq 1)
W ('removed = ' + (($removed | ForEach-Object { '[' + $_.node + '] ' + $_.name }) -join ', '))
W ('ok = ' + $ok)
[ordered]@{ ok = $ok; index = $Index; before = $before; after = $after; removed = $removed } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'delete_slave_result.json') -Encoding UTF8
W 'done'
exit 0
