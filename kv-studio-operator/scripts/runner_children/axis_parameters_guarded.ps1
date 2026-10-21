param(
    [Parameter(Mandatory = $true)][string]$OutDir,
    [ValidateSet('Read', 'Write', 'Dump')][string]$Mode = 'Read',
    [int]$Axis = 0,
    [string]$Param = '',
    [string]$Value = '',
    [switch]$AllParams,
    [switch]$NoSave
)
# 轴参数的**地址化**读写（2026-10-21）
#   寻址：轴号 + 参数名（不是行号/像素 ✗）
#   读：选中 (row=参数, col=轴) → Ctrl+C 读当前格 → 与"期望值"比对（可发现定位错误 ✓）
#   写：定位 → 读回校验 → F2/Ctrl+A/键入/Enter → 整表 diff 必须**恰好 1 格**变化且位置正确 ✓ → 保存
#   表：轴控制设定（多轴并排）→ 列 = 轴，行 = 参数
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
public class AxGrid {
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

# ================= 参数地址表（行号 ↔ 参数名）=================
# 行序与「轴控制设定」表格自上而下一致（0 = 坐标单位，快照 copy 的 TSV 行号 ✓）
$script:ParamTable = @(
    @{ i = 0;  n = '坐标单位';                  a = 'coord_unit';            g = '单位坐标转换' }
    @{ i = 1;  n = '小数点以下运算精度';        a = 'coord_precision';       g = '单位坐标转换' }
    @{ i = 2;  n = '坐标模式';                  a = 'coord_mode';            g = '单位坐标转换' }
    @{ i = 3;  n = '坐标周期';                  a = 'coord_cycle';           g = '单位坐标转换' }
    @{ i = 4;  n = '接近控制';                  a = 'approach_control';      g = '单位坐标转换' }
    @{ i = 5;  n = '坐标转换分子';              a = 'coord_numerator';       g = '单位坐标转换' }
    @{ i = 6;  n = '坐标转换分母';              a = 'coord_denominator';     g = '单位坐标转换' }
    @{ i = 7;  n = '机械配置';                  a = 'machine_type';          g = '坐标转换计算' }
    @{ i = 8;  n = '滚珠螺杠螺距';              a = 'ball_screw_pitch';      g = '坐标转换计算' }
    @{ i = 9;  n = '皮带轮直径';                a = 'pulley_diameter';       g = '坐标转换计算' }
    @{ i = 10; n = '输出轴转1圈的移动量';       a = 'moving_amount_per_rev'; g = '坐标转换计算' }
    @{ i = 11; n = '减速比-输出轴侧';           a = 'ratio_out_side';        g = '坐标转换计算' }
    @{ i = 12; n = '减速比-电机轴侧';           a = 'ratio_motor_side';      g = '坐标转换计算' }
    @{ i = 13; n = '软限位坐标系';              a = 'soft_limit_frame';      g = '软件限位坐标' }
    @{ i = 14; n = '软限位正侧';                a = 'soft_limit_pos_enable'; g = '软件限位坐标' }
    @{ i = 15; n = '软限位正侧坐标';            a = 'soft_limit_pos';        g = '软件限位坐标' }
    @{ i = 16; n = '软限位负侧';                a = 'soft_limit_neg_enable'; g = '软件限位坐标' }
    @{ i = 17; n = '软限位负侧坐标';            a = 'soft_limit_neg';        g = '软件限位坐标' }
    @{ i = 18; n = '限位开关错误设定';          a = 'limit_switch_error';    g = '轴错误' }
    @{ i = 19; n = '绝对位置检测系统';          a = 'abs_position_system';   g = '轴错误' }
    @{ i = 20; n = 'ABS编码器保持范围上限值';   a = 'abs_range_upper';       g = '轴错误' }
    @{ i = 21; n = 'ABS编码器保持范围下限值';   a = 'abs_range_lower';       g = '轴错误' }
    @{ i = 22; n = '停止方法(动作使能OFF)';     a = 'stop_on_disable';       g = '轴控制功能' }
    @{ i = 23; n = '停止方法(软限位)';          a = 'stop_on_soft_limit';    g = '轴控制功能' }
    @{ i = 24; n = '停止方法(外部限位)';        a = 'stop_on_ext_limit';     g = '轴控制功能' }
    @{ i = 25; n = '停止方法(其它错误)';        a = 'stop_on_other_error';   g = '轴控制功能' }
    @{ i = 26; n = '电机转向';                  a = 'motor_direction';       g = '轴控制功能' }
    @{ i = 27; n = '伺服OFF时机';               a = 'servo_off_timing';      g = '轴控制功能' }
    @{ i = 28; n = '伺服结束检查时间';          a = 'servo_end_check_time';  g = '轴控制功能' }
    @{ i = 29; n = '伺服结束范围';              a = 'servo_end_range';       g = '轴控制功能' }
    @{ i = 30; n = '背隙补偿移动量';            a = 'backlash_comp';         g = '轴控制功能' }
    @{ i = 31; n = '切换位置控制模式时的速度阈值'; a = 'pos_mode_speed_threshold'; g = '轴控制功能' }
    @{ i = 32; n = '速度切换选择';              a = 'speed_switch_mode';     g = '位置控制通用' }
    @{ i = 33; n = '选择加/减速设定';           a = 'accel_decel_setting';   g = '位置控制通用' }
    @{ i = 34; n = '选择直线插补速度';          a = 'line_interp_speed';     g = '位置控制通用' }
    @{ i = 35; n = '选择螺旋插补速度';          a = 'helical_interp_speed';  g = '位置控制通用' }
    @{ i = 36; n = '停止传感器输入后寸动动作选择'; a = 'stop_sensor_jog_mode'; g = '位置控制通用' }
    @{ i = 37; n = '运转起动速度';              a = 'run_start_speed';       g = '运转速度' }
    @{ i = 38; n = '最高运转速度';              a = 'run_max_speed';         g = '运转速度' }
    @{ i = 39; n = '运转加速度/时间';           a = 'run_accel';             g = '运转速度' }
    @{ i = 40; n = '运转加速曲线';              a = 'run_accel_curve';       g = '运转速度' }
    @{ i = 41; n = '运转加速SIN斜率';           a = 'run_accel_sin_slope';   g = '运转速度' }
    @{ i = 42; n = '运转减速度/时间';           a = 'run_decel';             g = '运转速度' }
    @{ i = 43; n = '运转减速曲线';              a = 'run_decel_curve';       g = '运转速度' }
    @{ i = 44; n = '运转减速SIN斜率';           a = 'run_decel_sin_slope';   g = '运转速度' }
    @{ i = 45; n = 'JOG起动速度';               a = 'jog_start_speed';       g = 'JOG' }
    @{ i = 46; n = 'JOG高速速度';               a = 'jog_high_speed';        g = 'JOG' }
    @{ i = 47; n = 'JOG加速/减速时间';          a = 'jog_accel';             g = 'JOG' }
    @{ i = 48; n = 'JOG加速曲线';                  a = 'jog_accel_curve';            g = 'JOG' }
    @{ i = 49; n = 'JOG加速SIN斜率';               a = 'jog_accel_sin_slope';        g = 'JOG' }
    @{ i = 50; n = 'JOG减速/时间';                 a = 'jog_decel';                  g = 'JOG' }
    @{ i = 51; n = 'JOG减速曲线';                  a = 'jog_decel_curve';            g = 'JOG' }
    @{ i = 52; n = 'JOG减速SIN斜率';               a = 'jog_decel_sin_slope';        g = 'JOG' }
    @{ i = 53; n = 'JOG寸动移动量';                a = 'jog_inch';                   g = 'JOG' }
    @{ i = 54; n = '原点复归方法';                 a = 'homing_method';              g = '原点复归' }
    @{ i = 55; n = '原点复归起动速度';             a = 'homing_start_speed';         g = '原点复归' }
    @{ i = 56; n = '原点复归爬行速度';             a = 'homing_creep_speed';         g = '原点复归' }
    @{ i = 57; n = '原点复归运转速度';             a = 'homing_run_speed';           g = '原点复归' }
    @{ i = 58; n = '原点复归加速/时间';            a = 'homing_accel';               g = '原点复归' }
    @{ i = 59; n = '原点复归加速曲线';             a = 'homing_accel_curve';         g = '原点复归' }
    @{ i = 60; n = '原点复归加速SIN斜率';          a = 'homing_accel_sin_slope';     g = '原点复归' }
    @{ i = 61; n = '原点复归减速/时间';            a = 'homing_decel';               g = '原点复归' }
    @{ i = 62; n = '原点复归减速曲线';             a = 'homing_decel_curve';         g = '原点复归' }
    @{ i = 63; n = '原点复归减速SIN斜率';          a = 'homing_decel_sin_slope';     g = '原点复归' }
    @{ i = 64; n = '原点复归方向';                 a = 'homing_direction';           g = '原点复归' }
    @{ i = 65; n = '原点坐标';                     a = 'home_position';              g = '原点复归' }
    @{ i = 66; n = 'DOG ON后移动量';               a = 'dog_on_move';                g = '原点复归' }
    @{ i = 67; n = '原点复归时暂停时间';           a = 'homing_pause';               g = '原点复归' }
    @{ i = 68; n = '接触力时间';                   a = 'contact_force_time';         g = '原点复归' }
    @{ i = 69; n = '接触力阈值';                   a = 'contact_force_threshold';    g = '原点复归' }
    @{ i = 70; n = '基本位置坐标';                 a = 'base_position';              g = '原点复归' }
    @{ i = 71; n = '基本位置自动移动';             a = 'base_auto_move';             g = '原点复归' }
    @{ i = 72; n = '运转速度';                     a = 'tracking_run_speed';         g = '绝对位置跟踪控制' }
    @{ i = 73; n = '加速度/时间';                  a = 'tracking_accel';             g = '绝对位置跟踪控制' }
    @{ i = 74; n = '减速度/时间';                  a = 'tracking_decel';             g = '绝对位置跟踪控制' }
    @{ i = 75; n = '可变进给比分子';               a = 'variable_feed_num';          g = '同步型跟踪控制' }
    @{ i = 76; n = '可变进给比分母';               a = 'variable_feed_den';          g = '同步型跟踪控制' }
    @{ i = 77; n = '输出读入器';                   a = 'output_reader';              g = '同步型跟踪控制' }
)
function Find-Param([string]$name) {
    if (-not $name) { return $null }
    $k = ($name -replace '\s', '').ToLower()
    foreach ($p in $script:ParamTable) {
        if (($p.n -replace '\s', '').ToLower() -eq $k) { return $p }
        if (($p.a -replace '\s', '').ToLower() -eq $k) { return $p }
    }
    return $null
}
function Param-Names { ($script:ParamTable | ForEach-Object { $_.n }) -join ' / ' }

# ================= 上下文 =================
$p = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { throw 'KV_AXIS_PARAM_NO_KVS' }
$kvsHwnd = [IntPtr]$p.MainWindowHandle
$null = Initialize-KvUiGuard -OutDir (Join-Path $OutDir 'guard')
$main = [System.Windows.Automation.AutomationElement]::FromHandle($kvsHwnd)
W ('kvs [' + $p.MainWindowTitle + ']')

function Send-G([string]$keys, [string]$step, [int]$sleep = 110) {
    Invoke-KvGuardedSendKeys -TargetHwnd $kvsHwnd -Step $step -Keys $keys -ExpectedTitleLike 'KV STUDIO*' -SleepMs $sleep
}
# 关向导
for ($k = 1; $k -le 3; $k++) {
    $wz = $null
    foreach ($win in (Get-KvTopWindow -ProcessId $p.Id -VisibleOnly)) { if ($win.Title -match '坐标转换计算') { $wz = $win; break } }
    if (-not $wz) { break }
    foreach ($row in [KvDlgPost]::ChildButtons($wz.Hwnd)) { $parts = $row -split [char]1; if ($parts[2] -match '取消') { [void][KvDlgPost]::Click([IntPtr][long]$parts[0]); break } }
    Start-Sleep -Seconds 2
}
function Tree-Items { @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.TreeItem' }) }
function Expand-Name([string]$nm) {
    $n = (Tree-Items) | Where-Object { [string]$_.Current.Name -eq $nm } | Select-Object -First 1
    if (-not $n) { return $false }
    try { $n.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand() } catch { }
    Start-Sleep -Milliseconds 700
    return $true
}
$projTree = @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.Tree' })[0]
$th = [IntPtr]0
try { $th = [IntPtr]$projTree.Current.NativeWindowHandle } catch { }
foreach ($nm in @('单元配置', '[0]  KV-X520', '运动设定', '轴设定')) { [void](Expand-Name $nm) }
$acs = (Tree-Items) | Where-Object { [string]$_.Current.Name -eq '轴控制设定' } | Select-Object -First 1
if (-not $acs) { throw 'KV_AXIS_PARAM_PAGE_NOT_FOUND' }
try { $acs.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch { }
Start-Sleep -Milliseconds 400
$rAcs = $acs.Current.BoundingRectangle
if ($th -ne [IntPtr]0) { [AxGrid]::Dbl($th, [int]($rAcs.X + $rAcs.Width / 2), [int]($rAcs.Y + $rAcs.Height / 2)) }
Start-Sleep -Seconds 3

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
if (-not $grid) { throw 'KV_AXIS_PARAM_GRID_NOT_FOUND' }
$g = $grid.Current.BoundingRectangle
W ('grid = ' + [int]$g.X + ',' + [int]$g.Y + ' ' + [int]$g.Width + 'x' + [int]$g.Height)

function Focus-Grid { [AxGrid]::Click([int]($g.X + 300), [int]($g.Y + 60)); Start-Sleep -Milliseconds 400 }
function Read-All {
    Focus-Grid
    Send-G '^a' 'grid select all'
    Start-Sleep -Milliseconds 250
    Send-G '^c' 'grid copy all'
    Start-Sleep -Milliseconds 700
    return (Get-Clipboard -Raw)
}
function Read-Cell {
    Focus-Grid
    Send-G '^c' 'cell copy'
    Start-Sleep -Milliseconds 450
    return ((Get-Clipboard -Raw) -replace "`r?`n", '')
}
function Go-Cell([int]$row, [int]$col) {
    Focus-Grid
    Send-G '^{HOME}' 'cell home' 180
    Start-Sleep -Milliseconds 200
    for ($i = 0; $i -lt $row; $i++) { Send-G '{DOWN}' ('down ' + $i) 70 }
    Start-Sleep -Milliseconds 150
    for ($i = 1; $i -lt $col; $i++) { Send-G '{RIGHT}' ('right ' + $i) 70 }
    Start-Sleep -Milliseconds 250
}

# ================= 读整表 → 矩阵 =================
$all = Read-All
$lines = @($all -split "`r?`n" | Where-Object { $_.Trim() })
W ('table rows = ' + $lines.Count)
if ($lines.Count -lt 10) { Shot 'bad_table.png'; throw 'KV_AXIS_PARAM_NOT_AXIS_TABLE' }
$header = @(($lines[0] -replace "`r", '') -split "`t")
# 轴名：表格列序 == 轴号；从工程的 WsTreeEnv.xml 取真实轴名（表头只是"坐标单位" ✗）
$axisNames = @()
try {
    $kvsProc = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
    $cl = (Get-CimInstance Win32_Process -Filter ('ProcessId=' + $kvsProc.Id)).CommandLine
    if ($cl -match '"([^"]+\.kpr)"') {
        $treeXml = Join-Path (Split-Path -Parent $Matches[1]) 'WsTreeEnv.xml'
        if (Test-Path $treeXml) {
            [xml]$xd = Get-Content -Raw -LiteralPath $treeXml -Encoding UTF8
            $found = @{}
            foreach ($n in @($xd.SelectNodes('//value.first'))) {
                $t = ([string]$n.InnerText).Trim()
                if ($t -match '^轴(\d+)\s*[:：]') { $found[[int]$Matches[1]] = $t }
            }
            for ($k = 1; $k -le $header.Count; $k++) { if ($found.ContainsKey($k)) { $axisNames += $found[$k] } else { $axisNames += ('轴' + $k) } }
            W ('axis names loaded = ' + $axisNames.Count)
        }
    }
} catch { W ('axis name load failed: ' + $_.Exception.Message) }
if ($axisNames.Count -ne $header.Count) { $axisNames = @(); for ($k = 1; $k -le $header.Count; $k++) { $axisNames += ('轴' + $k) } }
W ('columns (axes) = ' + $header.Count)

function Cell([int]$row, [int]$col) {
    if ($row -lt 0 -or $row -ge $lines.Count) { return '' }
    $cells = @(($lines[$row] -replace "`r", '') -split "`t")
    if ($col -lt 1 -or $col -gt $cells.Count) { return '' }
    return $cells[$col - 1].Trim()
}

if ($Mode -eq 'Dump') {
    $out = Join-Path $OutDir 'axes_params.tsv'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('param_index' + "	" + 'param_name' + "	" + 'alias' + "	" + 'group' + "	" + (($axisNames) -join "	"))
    foreach ($prm in $script:ParamTable) {
        $vals = @()
        for ($c = 1; $c -le $header.Count; $c++) { $vals += (Cell $prm.i $c) }
        [void]$sb.AppendLine(([string]$prm.i) + "`t" + $prm.n + "`t" + $prm.a + "`t" + $prm.g + "`t" + ($vals -join "`t"))
    }
    [IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
    W ('dumped -> ' + $out)
    # 未在地址表里的行（用于扩展 ✓）
    $unknown = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not ($script:ParamTable | Where-Object { $_.i -eq $i })) { $unknown += $i }
    }
    W ('rows without a name mapping = ' + $unknown.Count + '  -> ' + ($unknown -join ','))
    exit 0
}

if ($Axis -lt 1 -or $Axis -gt $header.Count) { throw ('KV_AXIS_PARAM_AXIS_OUT_OF_RANGE: axis=' + $Axis + ' max=' + $header.Count) }
$targets = @()
if ($AllParams) { $targets = @($script:ParamTable) }
else {
    $prm = Find-Param $Param
    if (-not $prm) { throw ('KV_AXIS_PARAM_UNKNOWN: ' + $Param + ' | known: ' + (Param-Names)) }
    $targets = @($prm)
}

if ($Mode -eq 'Read') {
    $rowsOut = @()
    foreach ($t in $targets) {
        $v = Cell $t.i $Axis
        $rowsOut += [pscustomobject]@{ axis = $Axis; axis_label = $axisNames[$Axis - 1]; param_index = $t.i; param = $t.n; alias = $t.a; group = $t.g; value = $v }
        W ('  [' + $Axis + '] ' + $t.n + ' = ' + $v)
    }
    $rowsOut | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'axis_param_read.json') -Encoding UTF8
    W 'read done'
    exit 0
}

# ================= 写 =================
if (-not $Value) { throw 'KV_AXIS_PARAM_VALUE_REQUIRED' }
if ($targets.Count -ne 1) { throw 'KV_AXIS_PARAM_WRITE_ONE_AT_A_TIME' }
$t = $targets[0]
$before = Cell $t.i $Axis
W ('target: axis=' + $Axis + ' (' + $axisNames[$Axis - 1] + ')  param=' + $t.n + '  before=[' + $before + ']  -> value=[' + $Value + ']')
Go-Cell $t.i $Axis
$cur = Read-Cell
W ('selected cell now = [' + $cur + ']')
Shot 'w1_selected.png'
if ($cur -ne $before) { throw ('KV_AXIS_PARAM_LOCATE_MISMATCH: selected=[' + $cur + '] expected=[' + $before + ']') }

Go-Cell $t.i $Axis
Send-G '{F2}' 'cell edit' 250
Send-G '^a' 'cell select' 150
Send-G $Value 'cell type' 250
Send-G '{ENTER}' 'cell commit' 600
Shot 'w2_after_typing.png'
$afterAll = Read-All
$afterLines = @($afterAll -split "`r?`n" | Where-Object { $_.Trim() })
$diffs = @()
for ($i = 0; $i -lt [Math]::Min($lines.Count, $afterLines.Count); $i++) {
    $a = @(($lines[$i] -replace "`r", '') -split "`t")
    $b = @(($afterLines[$i] -replace "`r", '') -split "`t")
    for ($c = 0; $c -lt [Math]::Min($a.Count, $b.Count); $c++) {
        if ($a[$c] -ne $b[$c]) { $diffs += [pscustomobject]@{ row = $i; col = $c + 1; before = $a[$c]; after = $b[$c] } }
    }
}
W ('cell diffs = ' + $diffs.Count)
$diffs | ForEach-Object { W ('  diff r' + $_.row + ' c' + $_.col + ': [' + $_.before + '] -> [' + $_.after + ']') }
Shot 'w3_after_read.png'
$ok = ($diffs.Count -eq 1 -and $diffs[0].row -eq $t.i -and $diffs[0].col -eq $Axis)
W ('exactly one cell changed at target = ' + $ok)
if ($ok -and -not $NoSave) { Send-G '^s' 'save' 4000; Start-Sleep -Seconds 2; W ('title=[' + [string]$p.MainWindowTitle + ']'); Shot 'w4_saved.png' }
[ordered]@{ ok = $ok; axis = $Axis; axis_label = $axisNames[$Axis - 1]; param = $t.n; param_index = $t.i; before = $before; after = (Cell $t.i $Axis); diffs = $diffs } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'axis_param_write.json') -Encoding UTF8
W 'done'
exit 0