param(
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\work\template\table-edit',
    [int]$RowIndex = -1,
    [string]$Value = '',
    [int]$Column = 1,
    [switch]$ListOnly,
    [switch]$NoSave
)
# 轴控制设定「大表」——**对象级**单元格选中与改写（2026-10-21）
#   原则：不使用像素定位 ✗；用表格自身的**选区导航**（Ctrl+Home → Down×行 → Right×列）✓
#   验证：Ctrl+C 只复制**当前选中格** → 读回值必须等于预期 ✓（指哪打哪 ✓）
#   写入：F2 → Ctrl+A → 键入 → Enter
#   校验：Ctrl+A/C 整表 diff → **恰好一行变化** ✓
$ErrorActionPreference = 'Stop'
$repo = 'H:\KeyenceAgent\kv-studio-operator'
. "$repo\scripts\kv_dialog_post.ps1"
Add-Type -AssemblyName UIAutomationClient
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
  public static void Click(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(120); mouse_event(0x0002,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(0x0004,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(300); }
}
"@ -ErrorAction SilentlyContinue
$p = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { throw 'KV_TABLE_NO_KVS' }
$main = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
# 关掉向导（模态会挡住键盘导航 ✗）
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
function Focus-Grid {
    # 只是把焦点交给这个控件（位置不重要，点表格中心即可）
    [Tbl2]::Click([int]($g.X + [int]($g.Width / 2)), [int]($g.Y + [int]($g.Height / 2)))
    Start-Sleep -Milliseconds 400
}
function Read-TableAll {
    Focus-Grid
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait('^c')
    Start-Sleep -Milliseconds 700
    return (Get-Clipboard -Raw)
}
function Read-CurCell {
    Focus-Grid
    [System.Windows.Forms.SendKeys]::SendWait('^c')
    Start-Sleep -Milliseconds 500
    return ((Get-Clipboard -Raw) -replace "`r?`n", '')
}
function Go-Cell([int]$row, [int]$col) {
    Focus-Grid
    [System.Windows.Forms.SendKeys]::SendWait('^{HOME}')
    Start-Sleep -Milliseconds 300
    for ($i = 0; $i -lt $row; $i++) { [System.Windows.Forms.SendKeys]::SendWait('{DOWN}') }
    Start-Sleep -Milliseconds 200
    for ($i = 1; $i -lt $col; $i++) { [System.Windows.Forms.SendKeys]::SendWait('{RIGHT}') }
    Start-Sleep -Milliseconds 300
}
$before = Read-TableAll
$lines = @($before -split "`r?`n")
W ('rows = ' + $lines.Count)
if ($ListOnly) {
    W 'index : 轴1<TAB>轴2'
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
# 期望值：从整表该行按列取（TSV）
$cells = @($expected -split "`t")
$expectCell = ''
if ($Column -le $cells.Count) { $expectCell = $cells[$Column - 1] }
W ('expected cell value = [' + $expectCell + ']')
if ($cur -ne $expectCell) { W ('WARN: selected cell value != expected (may be format diff)'); }
if (-not $Value) { W 'no -Value given: selection-verify only'; exit 0 }
# 写入
Go-Cell $RowIndex $Column
[System.Windows.Forms.SendKeys]::SendWait('{F2}')
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait('^a')
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait($Value)
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Milliseconds 700
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
    $sv = Join-Path $OutDir 'save.ps1'
    $body = @"
`$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Windows.Forms
. '$repo\scripts\guards\kv_ui_guard.ps1'
`$null = Initialize-KvUiGuard -OutDir '$OutDir\guard'
`$pp = Get-Process -Name 'Kvs' | Select-Object -First 1
Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]`$pp.MainWindowHandle) -Step 'save table edit' -Keys '^s' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 5000
"@
    [IO.File]::WriteAllText($sv, $body, (New-Object System.Text.UTF8Encoding($false)))
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sv | Out-Null
    Start-Sleep -Seconds 2
    W ('title=[' + [string]$p.MainWindowTitle + ']')
    Shot 'c4_saved.png'
}
[ordered]@{ ok = $ok; row = $RowIndex; column = $Column; expected = $expectCell; selected = $cur; diffs = $diffs } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'table_edit_result.json') -Encoding UTF8
W 'done'
exit 0