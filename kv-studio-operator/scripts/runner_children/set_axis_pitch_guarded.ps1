param(
    [Parameter(Mandatory=$true)][string]$OutDir,
    [string]$AxisLabel = '轴1:Axis_1',
    [double]$Pitch = 25,
    [string]$MachineType = '',
    [double]$RatioOut = 0,
    [double]$RatioMotor = 0,
    [int]$StepTimeoutSeconds = 3,
    [string]$RepoRoot = 'H:\KeyenceAgent\kv-studio-operator'
)
# 改轴参数（螺距 = 「输出轴转 1 圈的移动量」）—— 已验证路径 2026-10-20 ✓
# 轴设定 → 轴n → 轴控制设定 →「坐标转换计算(C)」→ 向导 → 写 _textBoxParameter → 执行计算 → 退出向导 → 保存
# 全程 PostMessage（弹窗/按钮）✓，仅保存用守卫一次 ✓
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'scripts/kv_dialog_post.ps1')
# 受守卫的全局输入（Invoke-KvGuardedSendKeys 等）必须 dot-source 守卫库 ✓
. (Join-Path $RepoRoot 'scripts\guards\kv_ui_guard.ps1')
$null = New-Item -ItemType Directory -Force -Path $OutDir
$log = Join-Path $OutDir 'run.log'
function W([string]$m){ $line=(Get-Date).ToString('HH:mm:ss.fff')+'  '+$m; Write-Output $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;using System.Runtime.InteropServices;
public class KvAxisClick {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr h, ref POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  public static IntPtr LP(int x,int y){ return (IntPtr)((y << 16) | (x & 0xFFFF)); }
  public static void Dbl(IntPtr hwnd,int sx,int sy){
    var q=new POINT(); q.X=sx; q.Y=sy; ScreenToClient(hwnd, ref q); var lp=LP(q.X,q.Y);
    PostMessage(hwnd,0x0201,(IntPtr)1,lp); PostMessage(hwnd,0x0202,IntPtr.Zero,lp);
    PostMessage(hwnd,0x0203,(IntPtr)1,lp); PostMessage(hwnd,0x0202,IntPtr.Zero,lp);
  }
}
"@ -ErrorAction SilentlyContinue
function Shot([string]$n){ try{ $b=[System.Windows.Forms.SystemInformation]::VirtualScreen; $bmp=New-Object System.Drawing.Bitmap($b.Width,$b.Height); $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X,$b.Y,0,0,$bmp.Size); $bmp.Save((Join-Path $OutDir $n),[System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose() }catch{ } }
function Get-Root([IntPtr]$h){ try{ return [System.Windows.Automation.AutomationElement]::FromHandle($h) }catch{ return $null } }
function AllOf([IntPtr]$hwnd,[string]$ct){ $r=Get-Root $hwnd; if(-not $r){ return @() }; return @($r.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq $ct }) }
$proc = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { throw 'KV_AXIS_NO_KVS' }
$main = [IntPtr]$proc.MainWindowHandle
$trees = @(AllOf $main 'ControlType.Tree')
if ($trees.Count -eq 0) { throw 'KV_AXIS_PROJECT_TREE_NOT_FOUND' }
$projTree = $trees[0]
function Tree-Items { @(AllOf $main 'ControlType.TreeItem') }
function Expand-Name([string]$nm){
    $n=(Tree-Items) | Where-Object { [string]$_.Current.Name -eq $nm } | Select-Object -First 1
    if(-not $n){ return $false }
    try{ $n.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep -Milliseconds 500; return $true }catch{ return $false }
}
W 'expand unit config -> motion -> axis settings'
foreach($nm in @('单元配置','[0]  KV-X520','运动设定','轴设定')){ [void](Expand-Name $nm) }
$ax=(Tree-Items) | Where-Object { [string]$_.Current.Name -eq $AxisLabel } | Select-Object -First 1
if(-not $ax){ W ('axis node not found: ' + $AxisLabel); throw 'KV_AXIS_NODE_NOT_FOUND' }
W ('axis node [' + [string]$ax.Current.Name + ']')
try { $ax.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch { }
Start-Sleep -Milliseconds 400
$th=[IntPtr]0; try{ $th=[IntPtr]$projTree.Current.NativeWindowHandle }catch{ }
$r=$ax.Current.BoundingRectangle
if($th -ne [IntPtr]0){ [KvAxisClick]::Dbl($th,[int]($r.X+$r.Width/2),[int]($r.Y+$r.Height/2)) }
# 目标窗口句柄：直接取 KVS 进程主窗口（守卫变量可能未初始化 ✗）
$kvsHwnd = [IntPtr]0
try { $kvsProbe = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1; if ($kvsProbe -and $kvsProbe.MainWindowHandle -ne 0) { $kvsHwnd = [IntPtr]$kvsProbe.MainWindowHandle } } catch { }
W ('kvs main hwnd = ' + $kvsHwnd)
Start-Sleep -Seconds 2
# ---- SELECT-AXIS-COLUMN（2026-10-21 实测）：轴控制设定 是**多轴并排表格** ✓
# 必须先在该表里选中**目标轴那一列** ✓ 再点「坐标转换计算」✓ 否则向导会跟"当前轴"（=轴1）✗
$axisNo = 1
try { if ($AxisLabel -match '^轴(\d+)') { $axisNo = [int]$Matches[1] } } catch { }
if ($axisNo -ge 1) {
    # 确保「轴控制设定」页是打开的
    $acs = (Tree-Items) | Where-Object { [string]$_.Current.Name -eq '轴控制设定' } | Select-Object -First 1
    if ($acs) {
        try { $acs.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch { }
        Start-Sleep -Milliseconds 300
        $rAcs = $acs.Current.BoundingRectangle
        if ($th -ne [IntPtr]0) { [KvAxisClick]::Dbl($th, [int]($rAcs.X + $rAcs.Width / 2), [int]($rAcs.Y + $rAcs.Height / 2)) }
        Start-Sleep -Seconds 3
    }
    # 找多轴大表格
    $gridEl = $null
    foreach ($gel in @((Get-Root $main).FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
        $gcls = ''
        try { $gcls = [string]$gel.Current.ClassName } catch { continue }
        if ($gcls -notmatch 'WindowsForms') { continue }
        $gr = $gel.Current.BoundingRectangle
        if ($gr.Width -lt 600 -or $gr.Height -lt 300) { continue }
        if ($gr.X -gt 400) { continue }
        if (-not $gridEl -or $gr.Height -gt $gridEl.Current.BoundingRectangle.Height) { $gridEl = $gel }
    }
    if ($gridEl) {
        $gr = $gridEl.Current.BoundingRectangle
        Add-Type -TypeDefinition @"
using System;using System.Runtime.InteropServices;
public class KvAxisGridClick {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,UIntPtr e);
  public static void Click(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(150); mouse_event(0x0002,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(80); mouse_event(0x0004,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(300); }
}
"@ -ErrorAction SilentlyContinue
        # 聚焦表格（点表格内部任意处即可 ✓ 位置不重要 ✓）→ Ctrl+Home → Right×(轴号-1) = **选中目标轴那一列** ✓
        [KvAxisGridClick]::Click([int]($gr.X + 300), [int]($gr.Y + 60))
        Start-Sleep -Milliseconds 400
        Add-Type -AssemblyName System.Windows.Forms
    # 守卫必须先初始化 ✓（否则写 checkpoint 会抛错 ✗）
    try { $null = Initialize-KvUiGuard -OutDir (Join-Path $OutDir 'guard_axiscol') } catch { W ('guard init: ' + $_.Exception.Message) }
        Invoke-KvGuardedSendKeys -TargetHwnd $kvsHwnd -Step 'axis table focus to home' -Keys '^{HOME}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 250
        Start-Sleep -Milliseconds 300
        for ($ci = 1; $ci -lt $axisNo; $ci++) { Invoke-KvGuardedSendKeys -TargetHwnd $kvsHwnd -Step 'axis table move right' -Keys '{RIGHT}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 120 }
        Start-Sleep -Milliseconds 400
        W ('selected axis column ' + $axisNo + ' in axis control table')
    } else { W 'axis control table not found - wizard may follow the current axis' }
}
# 找「坐标转换计算(C)」按钮
$target=$null
foreach($el in @((Get-Root $main).FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
    $aid=''; try{ $aid=[string]$el.Current.AutomationId }catch{ continue }
    if($aid -eq '_buttonTransformCoordinator'){ $target=$el; break }
}
if(-not $target){
    # 可能要先切到「轴控制设定」
    W 'transform button not visible -> open 轴控制设定 first'
    $n=(Tree-Items) | Where-Object { [string]$_.Current.Name -eq '轴控制设定' } | Select-Object -First 1
    if($n){
        try { $n.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch { }
        Start-Sleep -Milliseconds 300
        $r2=$n.Current.BoundingRectangle
        if($th -ne [IntPtr]0){ [KvAxisClick]::Dbl($th,[int]($r2.X+$r2.Width/2),[int]($r2.Y+$r2.Height/2)) }
        Start-Sleep -Seconds 2
    }
    foreach($el in @((Get-Root $main).FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
        $aid=''; try{ $aid=[string]$el.Current.AutomationId }catch{ continue }
        if($aid -eq '_buttonTransformCoordinator'){ $target=$el; break }
    }
}
for ($try = 1; $try -le 6 -and -not $target; $try++) {
    Start-Sleep -Milliseconds 800
    foreach($el in @((Get-Root $main).FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
        $aid=''; try{ $aid=[string]$el.Current.AutomationId }catch{ continue }
        if($aid -eq '_buttonTransformCoordinator'){ $target=$el; break }
    }
}
if(-not $target){ Shot 'no_transform_button.png'; throw 'KV_AXIS_TRANSFORM_BUTTON_NOT_FOUND' }
$bh=[IntPtr]0; try{ $bh=[IntPtr]$target.Current.NativeWindowHandle }catch{ }
W ('click 坐标转换计算(C) hwnd=' + $bh)
[void][KvDlgPost]::Click($bh)
Start-Sleep -Seconds 3
$wz=$null
foreach($win in (Get-KvTopWindow -ProcessId $proc.Id -VisibleOnly)){ if($win.Title -match '坐标转换计算'){ $wz=$win; break } }
if(-not $wz){ Shot 'no_wizard.png'; throw 'KV_AXIS_WIZARD_NOT_FOUND' }
W ('wizard [' + $wz.Title + ']')
# ---- 断言：向导里的轴必须就是目标轴（否则会改错轴 ✗）----
$axisShort = $AxisLabel
if ($axisShort -match ':') { $axisShort = ($axisShort -split ':', 2)[1] }
if ($wz.Title -notlike ('*' + $axisShort + '*')) {
    W ('TARGET MISMATCH: wizard=[' + $wz.Title + '] expected axis=[' + $axisShort + ']')
    foreach ($el in @(([System.Windows.Automation.AutomationElement]::FromHandle($wz.Hwnd)).FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
        $a = ''; try { $a = [string]$el.Current.AutomationId } catch { continue }
        if ($a -eq '_buttonCancel') { $h2 = [IntPtr]0; try { $h2 = [IntPtr]$el.Current.NativeWindowHandle } catch { }; [void][KvDlgPost]::Click($h2); break }
    }
    Start-Sleep -Seconds 2
    throw 'KV_AXIS_WIZARD_TARGET_MISMATCH'
}
W ('wizard target OK: [' + $axisShort + ']')
# 写螺距 + 执行计算
# ---- 可选：设置机械配置 / 减速比（实测 aid ✓）----
if ($MachineType) {
    $mCombo=$null
    foreach($el in @((Get-Root $wz.Hwnd).FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
        if([string]$el.Current.ControlType.ProgrammaticName -ne 'ControlType.ComboBox'){ continue }
        $nm=''; try{ $nm=[string]$el.Current.Name }catch{ continue }
        if($nm -match '机械配置'){ $mCombo=$el; break }
    }
    if($mCombo){
        try{ $mCombo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep -Milliseconds 600 }catch{}
        $items=@($mCombo.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.ListItem' })
        foreach($it in $items){
            if([string]$it.Current.Name -eq $MachineType){
                try{ $it.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); W ('machine type set [' + $MachineType + ']') }catch{ W 'machine type select failed' }
                Start-Sleep -Milliseconds 900
                break
            }
        }
        try{ $mCombo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() }catch{}
    } else { W 'machine combo not found' }
}
function Set-EditByAid([IntPtr]$hwnd,[string]$aid,[double]$v){
    if($v -le 0){ return }
    foreach($el in @((Get-Root $hwnd).FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
        $a=''; try{ $a=[string]$el.Current.AutomationId }catch{ continue }
        if($a -eq $aid){ try{ $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue([string]$v); W ($aid + ' = ' + $v) }catch{ W ($aid + ' set failed') }; return }
    }
}
if ($RatioOut -gt 0) { Set-EditByAid $wz.Hwnd '_textBoxOutSide' $RatioOut }
if ($RatioMotor -gt 0) { Set-EditByAid $wz.Hwnd '_textBoxMotorSide' $RatioMotor }
$edit=$null
foreach($el in @((Get-Root $wz.Hwnd).FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
    $a=''; try{ $a=[string]$el.Current.AutomationId }catch{ continue }
    if($a -eq '_textBoxParameter'){ $edit=$el; break }
    }
if(-not $edit){ Shot 'no_param_edit.png'; throw 'KV_AXIS_PITCH_EDIT_NOT_FOUND' }
$before=''; try{ $before=[string]$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ }
try{ $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue([string]$Pitch) }catch{ W 'set value failed' }
Start-Sleep -Milliseconds 300
$after=''; try{ $after=[string]$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ }
W ('pitch ' + $before + ' -> ' + $after)
$calc=$null
foreach($el in @((Get-Root $wz.Hwnd).FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
    if([string]$el.Current.ControlType.ProgrammaticName -ne 'ControlType.Button'){ continue }
    $nm=''; try{ $nm=[string]$el.Current.Name }catch{ continue }
    if($nm -match '执行计算'){ $calc=$el; break }
}
if($calc){ $ch=[IntPtr]0; try{ $ch=[IntPtr]$calc.Current.NativeWindowHandle }catch{ }; [void][KvDlgPost]::Click($ch); W 'clicked 执行计算'; Start-Sleep -Milliseconds 800 }
$ratio=''
foreach($el in @((Get-Root $wz.Hwnd).FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
    $a=''; try{ $a=[string]$el.Current.AutomationId }catch{ continue }
    if($a -eq '_textBoxRatio'){ try{ $ratio=[string]$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ }; break }
}
W ('ratio = ' + $ratio)
# 判据（用户确认 ✓）：页面上「坐标转换分子 / 分母」会变成 400 / 1
$pageNum=''; $pageDen=''
foreach($el in @((Get-Root $main).FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
    $nm=''; try{ $nm=[string]$el.Current.Name }catch{ continue }
    $ct=''; try{ $ct=[string]$el.Current.ControlType.ProgrammaticName }catch{ continue }
    $val=''; try{ $val=[string]$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ }
    if($nm -match '坐标转换分子' -and $val){ $pageNum=$val }
    if($nm -match '坐标转换分母' -and $val){ $pageDen=$val }
    if($ct -eq 'ControlType.Edit' -and -not $nm){ }
}
W ('page 坐标转换分子=' + $pageNum + '  分母=' + $pageDen)
# 退出向导 + 是(Y)
$exit=$null
foreach($el in @((Get-Root $wz.Hwnd).FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
    if([string]$el.Current.ControlType.ProgrammaticName -ne 'ControlType.Button'){ continue }
    $nm=''; try{ $nm=[string]$el.Current.Name }catch{ continue }
    if($nm -match '退出向导'){ $exit=$el; break }
}
if($exit){ $eh=[IntPtr]0; try{ $eh=[IntPtr]$exit.Current.NativeWindowHandle }catch{ }; [void][KvDlgPost]::Click($eh); W 'clicked 退出向导'; Start-Sleep -Seconds 2 }
try { $cf = Wait-KvDialogButton -ProcessId $proc.Id -TextPattern '是' -TimeoutSeconds 5 -Tag 'exit-confirm' } catch { $cf=$null }
if($cf){ [void](Invoke-KvButtonPost -ButtonHwnd $cf.ButtonHwnd -Tag 'exit-confirm'); W 'confirmed 是(Y)' ; Start-Sleep -Seconds 2 }
Shot 'after_wizard.png'
# 保存（守卫一次）
# ---- 点向导的 OK(W)：这是"应用并关闭" ✓（只点退出向导=放弃 ✗）----
$wz3=$null
foreach($win in (Get-KvTopWindow -ProcessId $proc.Id -VisibleOnly)){ if($win.Title -match '坐标转换计算'){ $wz3=$win; break } }
if($wz3){
    $okBtn=$null
    foreach($el in @((Get-Root $wz3.Hwnd).FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){
        if([string]$el.Current.ControlType.ProgrammaticName -ne 'ControlType.Button'){ continue }
        $nm=''; try{ $nm=[string]$el.Current.Name }catch{ continue }
        if($nm -match '^OK'){ $okBtn=$el; break }
    }
    if($okBtn){
        $oh=[IntPtr]0; try{ $oh=[IntPtr]$okBtn.Current.NativeWindowHandle }catch{}
        W ('click wizard OK [' + [string]$okBtn.Current.Name + '] hwnd=' + $oh)
        [void][KvDlgPost]::Click($oh)
        Start-Sleep -Seconds 2
    } else { W 'wizard OK button not found' }
} else { W 'wizard already closed' }
# ---- 点掉后续确认（「映射设定吗？」等 ✓）直到向导关闭 ✓ ----
for ($r = 1; $r -le 8; $r++) {
    $yes = [IntPtr]0
    foreach ($win in (Get-KvTopWindow -ProcessId $proc.Id -VisibleOnly)) {
        foreach ($row in [KvDlgPost]::ChildButtons($win.Hwnd)) {
            $parts = $row -split [char]1
            if ($parts[2] -match '^是') { $yes = [IntPtr][long]$parts[0]; break }
        }
        if ($yes -ne [IntPtr]0) { break }
    }
    if ($yes -ne [IntPtr]0) {
        W ('round ' + $r + ': click 是(Y)')
        [void][KvDlgPost]::Click($yes)
        Start-Sleep -Milliseconds 900
        continue
    }
    $still = $null
    foreach ($win in (Get-KvTopWindow -ProcessId $proc.Id -VisibleOnly)) { if ($win.Title -match '坐标转换计算') { $still = $win; break } }
    if (-not $still) { W ('round ' + $r + ': wizard closed'); break }
    $okEl = $null
    $rt = [System.Windows.Automation.AutomationElement]::FromHandle($still.Hwnd)
    if ($rt) {
        foreach ($el in @($rt.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
            if ([string]$el.Current.ControlType.ProgrammaticName -ne 'ControlType.Button') { continue }
            $nm = ''; try { $nm = [string]$el.Current.Name } catch { continue }
            if ($nm -match '^OK') { $okEl = $el; break }
        }
    }
    if ($okEl) {
        $oh = [IntPtr]0; try { $oh = [IntPtr]$okEl.Current.NativeWindowHandle } catch { }
        W ('round ' + $r + ': wizard still open -> click OK')
        [void][KvDlgPost]::Click($oh)
        Start-Sleep -Seconds 1
    } else { W ('round ' + $r + ': no OK button'); break }
}
# ---- 保存：只用守卫 Ctrl+S（已验证能落盘 ✓，KVS 允许前台 ✓）----
$savedOk = $false
try {
    . (Join-Path $RepoRoot 'scripts/guards/kv_ui_guard.ps1')
    $null = Initialize-KvUiGuard -OutDir (Join-Path $OutDir 'guard')
    $p4 = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p4) {
        Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$p4.MainWindowHandle) -Step 'save axis pitch' -Keys '^s' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 4000 | Out-Null
        Start-Sleep -Seconds 2
        $t4 = [string](Get-Process -Id $p4.Id).MainWindowTitle
        W ('title after guard save = [' + $t4 + ']')
        if ($t4 -notmatch '\*') { $savedOk = $true }
    }
} catch { W ('guard save failed: ' + $_.Exception.Message) }
$titleFinal = ''
$pf = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pf) { $titleFinal = [string]$pf.MainWindowTitle }
W ('final title = [' + $titleFinal + ']  savedOk=' + $savedOk)
$result = [ordered]@{
    ok = $savedOk
    axis = $AxisLabel
    pitch = $Pitch
    before = $before
    ratio = $ratio
    page_numerator = $pageNum
    page_denominator = $pageDen
    title_after_save = $titleFinal
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutDir 'axis_pitch_result.json') -Encoding UTF8
W ('ok=' + $savedOk)
exit 0