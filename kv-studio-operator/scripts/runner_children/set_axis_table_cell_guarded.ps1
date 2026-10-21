param(
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\work\template\table-edit',
    [int]$RowIndex = -1,
    [string]$Value = '',
    [int]$Column = 1,
    [switch]$ListOnly,
    [switch]$NoSave
)
# 轴控制设定「大表」——**对象级**单元格选中与改写（2026-10-21）
#   导航：单元配置 → [0] KV-X520 → 运动设定 → 轴设定 → 双击 轴控制设定（缺这步会拿到别的表格 ✗）
#   原则：不使用像素定位 ✗；用表格自身的**选区导航**（Ctrl+Home → Down×行 → Right×列）✓
#   写入：F2 → Ctrl+A → 键入 → Enter
#   校验：Ctrl+A/C 整表 diff → **恰好一行变化且索引=目标行** ✓
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
public class Tbl2 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,UIntPtr e);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr h, ref POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  public static void Click(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(120); mouse_event(0x0002,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(0x0004,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(300); }
  public static IntPtr LP(int x,int y){ return (IntPtr)((y << 16) | (x & 0xFFFF)); }
  public static void Dbl(IntPtr hwnd,int sx,int sy){ var q=new POINT(); q.X=sx; q.Y=sy; ScreenToClient(hwnd, ref q); var lp=LP(q.X,q.Y);
    PostMessage(hwnd,0x0201,(IntPtr)1,lp); PostMessage(hwnd,0x0202,IntPtr.Zero,lp); PostMessage(hwnd,0x0203,(IntPtr)1,lp); PostMessage(hwnd,0x0202,IntPtr.Zero,lp); }
}
"@ -ErrorAction SilentlyContinue

$p = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { throw 'KV_TABLE_NO_KVS' }
$kvsHwnd = [IntPtr]$p.MainWindowHandle
$null = Initialize-KvUiGuard -OutDir (Join-Path $OutDir 'guard')
$main = [System.Windows.Automation.AutomationElement]::FromHandle($kvsHwnd)

# ---- 关掉向导（模态会挡住键盘导航 ✗）----
for ($k = 1; $k -le 4; $k++) {
    $wz = $null
    foreach ($win in (Get-KvTopWindow -ProcessId $p.Id -VisibleOnly)) { if ($win.Title -match '坐标转换计算') { $wz = $win; break } }
    if (-not $wz) { break }
    W ('close wizard #' + $k)
    foreach ($row in [KvDlgPost]::ChildButtons($wz.Hwnd)) { $parts = $row -split [char]1; if ($parts[2] -match '取消') { [void][KvDlgPost]::Click([IntPtr][long]$parts[0]); break } }
    Start-Sleep -Seconds 2
    for ($j = 1; $j -le 4; $j++) {
        $yes = [IntPtr]0
        foreach ($win in (Get-KvTopWindow -ProcessId $p.Id -VisibleOnly)) {
            foreach ($row in [KvDlgPost]::ChildButtons($win.Hwnd)) { $parts = $row -split [char]1; if ($parts[2] -match '^(是|确定)') { $yes = [IntPtr][long]$parts[0]; break } }
            if ($yes -ne [IntPtr]0) { break }
        }
        if ($yes -eq [IntPtr]0) { break }
        [void][KvDlgPost]::Click($yes); Start-Sleep -Seconds 1
    }
}

function Tree-Items { @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.TreeItem' }) }
function Expand-Name([string]$nm) {
    $n = (Tree-Items) | Where-Object { [string]$_.Current.Name -eq $nm } | Select-Object -First 1
    if (-not $n) { W ('  folder not found: ' + $nm); return $false }
    try { $n.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand() } catch { }
    Start-Sleep -Milliseconds 700
    return $true
}
# ---- 导航到「轴控制设定」页（这一步缺失会拿到别的表格 ✗）----
$projTree = @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.Tree' })[0]
$th = [IntPtr]0
try { $th = [IntPtr]$projTree.Current.NativeWindowHandle } catch { }
W 'navigate: 单元配置 -> [0] KV-X520 -> 运动设定 -> 轴设定'
foreach ($nm in @('单元配置', '[0]  KV-X520', '运动设定', '轴设定')) { [void](Expand-Name $nm) }
$acs = (Tree-Items) | Where-Object { [string]$_.Current.Name -eq '轴控制设定' } | Select-Object -First 1
if (-not $acs) { throw 'KV_TABLE_AXIS_PAGE_NOT_FOUND' }
try { $acs.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch { }
Start-Sleep -Milliseconds 400
$rAcs = $acs.Current.BoundingRectangle
if ($th -ne [IntPtr]0) { [Tbl2]::Dbl($th, [int]($rAcs.X + $rAcs.Width / 2), [int]($rAcs.Y + $rAcs.Height / 2)) }
Start-Sleep -Seconds 3

# ---- 找多轴大表格 ----
$grid = $null
foreach ($el in @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
    $cls = ''
    try { $cls = [string]$el.Current.ClassName } catch { continue }
    if ($cls -notmatch 'WindowsForms') { continue }
    $r = $el.Current.BoundingRectangle
    if ($r.Width -lt 600 -or $r.Height -lt 300) { continue }
    if ($r.X -gt 400) { continue }
    if (-not $grid -or $r.Height -gt $grid.Current.BoundingRectangle.Height) { $grid = $el }
}
if (-not $grid) { throw 'KV_TABLE_GRID_NOT_FOUND' }
$g = $grid.Current.BoundingRectangle
W ('grid = ' + [int]$g.X + ',' + [int]$g.Y + ' ' + [int]$g.Width + 'x' + [int]$g.Height)

# ---- 受守卫的按键（不用原始 SendKeys ✗：静态门禁会拦 & 焦点会丢）----
function Send-G([string]$keys, [string]$step, [int]$sleep = 120) {
    Invoke-KvGuardedSendKeys -TargetHwnd $kvsHwnd -Step $step -Keys $keys -ExpectedTitleLike 'KV STUDIO*' -SleepMs $sleep
}
function Focus-Grid {
    # 只是把焦点交给这个控件（位置不重要 ✓）
    [Tbl2]::Click([int]($g.X + 300), [int]($g.Y + 60))
    Start-Sleep -Milliseconds 400
}
function Read-TableAll {
    Focus-Grid
    Send-G '^a' 'table select all'
    Start-Sleep -Milliseconds 300
    Send-G '^c' 'table copy all'
    Start-Sleep -Milliseconds 700
    return (Get-Clipboard -Raw)
}
function Read-CurCell {
    Focus-Grid
    Send-G '^c' 'cell copy'
    Start-Sleep -Milliseconds 500
    return ((Get-Clipboard -Raw) -replace "`r?`n", '')
}
function Go-Cell([int]$row, [int]$col) {
    Focus-Grid
    Send-G '^{HOME}' 'cell to home' 200
    Start-Sleep -Milliseconds 250
    for ($i = 0; $i -lt $row; $i++) { Send-G '{DOWN}' ('cell down ' + $i) 80 }
    Start-Sleep -Milliseconds 200
    for ($i = 1; $i -lt $col; $i++) { Send-G '{RIGHT}' ('cell right ' + $i) 80 }
    Start-Sleep -Milliseconds 300
}

$before = Read-TableAll
$lines = @($before -split "`r?`n")
W ('rows = ' + $lines.Count)
if ($lines.Count -lt 10) { Shot 'no_table.png'; throw 'KV_TABLE_NOT_AXIS_TABLE' }
if ($ListOnly) {
    W 'index : 轴1 <TAB> 轴2 ...'
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim()) { W (('{0,3}' -f $i) + ' : ' + $lines[$i]) } }
    exit 0
}
if ($RowIndex -lt 0) { throw 'KV_TABLE_ROW_INDEX_REQUIRED' }
if ($RowIndex -ge $lines.Count) { throw 'KV_TABLE_ROW_INDEX_OUT_OF_RANGE' }
$expected = ($lines[$RowIndex] -replace "`r", '')
W ('target row ' + $RowIndex + ' = [' + $expected + ']  column=' + $Column)

Go-Cell $RowIndex $Column
$cur = Read-CurCell
W ('selected cell now = [' + $cur + ']')
Shot 'c1_selected.png'
$cells = @($expected -split "`t")
$expectCell = ''
if ($Column -le $cells.Count) { $expectCell = $cells[$Column - 1] }
W ('expected cell value = [' + $expectCell + ']')
if ($cur -ne $expectCell) { W 'WARN: selected cell value != expected (may be format diff)' }
if (-not $Value) { W 'no -Value given: selection-verify only'; exit 0 }

# ---- 写入 ----
Go-Cell $RowIndex $Column
Send-G '{F2}' 'cell edit mode' 300
Send-G '^a' 'cell select all' 200
Send-G $Value 'cell type value' 300
Send-G '{ENTER}' 'cell commit' 700
Shot 'c2_after_typing.png'
$after = Read-TableAll
$afterLines = @($after -split "`r?`n")
$diffs = @()
for ($i = 0; $i -lt [Math]::Min($lines.Count, $afterLines.Count); $i++) {
    if ($lines[$i] -ne $afterLines[$i]) { $diffs += [pscustomobject]@{ index = $i; before = ($lines[$i] -replace "`r", ''); after = ($afterLines[$i] -replace "`r", '') } }
}
W ('diff count = ' + $diffs.Count)
$diffs | ForEach-Object { W ('  diff ' + $_.index + ': [' + $_.before + '] -> [' + $_.after + ']') }
Shot 'c3_after_read.png'
$ok = ($diffs.Count -eq 1 -and $diffs[0].index -eq $RowIndex)
W ('exactly one row changed at target = ' + $ok)
if (-not $NoSave -and $ok) {
    Send-G '^s' 'save table edit' 5000
    Start-Sleep -Seconds 2
    W ('title=[' + [string]$p.MainWindowTitle + ']')
    Shot 'c4_saved.png'
}
[ordered]@{ ok = $ok; row = $RowIndex; column = $Column; expected = $expectCell; selected = $cur; diffs = $diffs } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'table_edit_result.json') -Encoding UTF8
W 'done'
exit 0
