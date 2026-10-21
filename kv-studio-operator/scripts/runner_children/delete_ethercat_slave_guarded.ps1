param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutDir,
    [Parameter(Mandatory=$true)][string]$SlaveNameLike,
    [int]$TimeoutSeconds = 120
)
# 删除一个 EtherCAT 从站 —— 全程 PostMessage（不取前台 ✓）
# 路径：项目树 单元配置→[0] KV-X520→EtherCAT 双击打开编辑器 → 网络树里选中从站 → DEL
#      （DEL 无效则右键 → 菜单「删除(D)」）→ 是(Y) → 编辑器 OK → 保存
$ErrorActionPreference = 'Stop'
$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $scriptsRoot 'kv_dialog_post.ps1')
. (Join-Path $scriptsRoot 'kv_tree_resolver.ps1')
. (Join-Path $scriptsRoot 'guards/kv_ui_guard.ps1')
$null = New-Item -ItemType Directory -Force -Path $OutDir
$null = Initialize-KvUiGuard -OutDir (Join-Path $OutDir 'guard')
$log = Join-Path $OutDir 'run.log'
function W([string]$m){ $line=(Get-Date).ToString('HH:mm:ss.fff')+'  '+$m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
function Shot([string]$n){ try{ $b=[System.Windows.Forms.SystemInformation]::VirtualScreen; $bmp=New-Object System.Drawing.Bitmap($b.Width,$b.Height); $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X,$b.Y,0,0,$bmp.Size); $bmp.Save((Join-Path $OutDir $n),[System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose() }catch{ } }
# --- PostMessage 输入（无前台）---
Add-Type -TypeDefinition @"
using System;using System.Runtime.InteropServices;using System.Text;
public class KvPostInput {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr h, ref POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  public static IntPtr LP(int x,int y){ return (IntPtr)((y << 16) | (x & 0xFFFF)); }
  public static void ClickAt(IntPtr hwnd,int sx,int sy,bool dbl,bool right){
    var p=new POINT(); p.X=sx; p.Y=sy; ScreenToClient(hwnd, ref p);
    var lp=LP(p.X,p.Y);
    if(right){
      PostMessage(hwnd,0x0204,(IntPtr)2,lp); PostMessage(hwnd,0x0205,IntPtr.Zero,lp);
    } else {
      PostMessage(hwnd,0x0201,(IntPtr)1,lp); PostMessage(hwnd,0x0202,IntPtr.Zero,lp);
      if(dbl){ PostMessage(hwnd,0x0203,(IntPtr)1,lp); PostMessage(hwnd,0x0202,IntPtr.Zero,lp); }
    }
  }
  public static void Key(IntPtr hwnd,int vk){
    PostMessage(hwnd,0x0100,(IntPtr)vk,IntPtr.Zero);
    PostMessage(hwnd,0x0101,(IntPtr)vk,IntPtr.Zero);
  }
}
"@ -ErrorAction SilentlyContinue
function Count-Slaves([string]$kpr){
    $tree = Join-Path (Split-Path -Parent $kpr) 'WsTreeEnv.xml'
    if (-not (Test-Path $tree)) { return -1 }
    return @([regex]::Matches((Get-Content $tree -Raw -Encoding UTF8), '\[\d+\]\s*(SV630|KV-EC01|SGDXS|CL3C|YAKO)')).Count
}
function Find-TreeWithItem([IntPtr]$hwnd, [string]$nameLike) {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
    if (-not $root) { return $null }
    $trees = @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.Tree' })
    foreach ($tr in $trees) {
        $its = @($tr.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.TreeItem' })
        $hit = @($its | Where-Object { [string]$_.Current.Name -like $nameLike })
        if ($hit.Count -gt 0) { return [pscustomobject]@{ Tree = $tr; Items = $its } }
    }
    return $null
}
function Get-TreeUnder([IntPtr]$hwnd){
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
    if (-not $root) { return $null }
    foreach ($el in @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
        if ([string]$el.Current.ControlType.ProgrammaticName -eq 'ControlType.Tree') { return $el }
    }
    return $null
}
$before = Count-Slaves $ProjectPath
W ('slaves before = ' + $before)
$proc = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { throw 'KV_DEL_NO_KVS' }
$main = [IntPtr]$proc.MainWindowHandle
# ---- 1) 打开 EtherCAT 编辑器：项目树选中 + 双击（PostMessage）----
$projTree = Get-TreeUnder $main
if (-not $projTree) { throw 'KV_DEL_PROJECT_TREE_NOT_FOUND' }
$ecNode = Resolve-KvTreeNodeByPath -Tree $projTree -Path @('单元配置','[0]  KV-X520','EtherCAT')
if (-not $ecNode) { throw 'KV_DEL_EC_NODE_NOT_FOUND' }
try { $ecNode.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch { }
Start-Sleep -Milliseconds 400
$r = $ecNode.Current.BoundingRectangle
$treeHwnd = [IntPtr]0
try { $treeHwnd = [IntPtr]$projTree.Current.NativeWindowHandle } catch { }
if ($treeHwnd -eq [IntPtr]0) { $treeHwnd = $main }
W ('project tree hwnd=' + $treeHwnd)
[KvPostInput]::ClickAt($treeHwnd, [int]($r.X + $r.Width/2), [int]($r.Y + $r.Height/2), $true, $false)
W 'double-clicked EtherCAT node (PostMessage)'
$ec = $null
$wait = (Get-Date).AddSeconds(20)
do {
    foreach ($win in (Get-KvTopWindow -ProcessId $proc.Id -VisibleOnly)) { if ($win.Title -match 'EtherCAT') { $ec = $win; break } }
    if ($ec) { break }
    Start-Sleep -Milliseconds 400
} while ((Get-Date) -lt $wait)
if (-not $ec) { Shot 'no_editor.png'; throw 'KV_DEL_EDITOR_NOT_FOUND' }
W ('editor [' + $ec.Title + '] hwnd=' + $ec.Hwnd)
Start-Sleep -Milliseconds 800
# ---- 2) 网络树里选中从站 ----
$found = Find-TreeWithItem $ec.Hwnd $SlaveNameLike
if (-not $found) { Shot 'no_tree.png'; throw 'KV_DEL_TREE_NOT_FOUND' }
$ecTree = $found.Tree
$items  = @($found.Items)
W ('network tree items = ' + $items.Count)
$target = $items | Where-Object { [string]$_.Current.Name -like $SlaveNameLike } | Select-Object -First 1
if (-not $target) { W ('items: ' + (($items | ForEach-Object { [string]$_.Current.Name }) -join ' | ')); Shot 'no_target.png'; throw 'KV_DEL_TARGET_NOT_FOUND' }
W ('target [' + [string]$target.Current.Name + ']')
try { $target.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch { W 'select failed' }
Start-Sleep -Milliseconds 500
$rect = $target.Current.BoundingRectangle
$tx = [int]($rect.X + $rect.Width/2); $ty = [int]($rect.Y + $rect.Height/2)
# ---- 3) 先试 DEL 键 ----
$ecTreeHwnd = [IntPtr]0
try { $ecTreeHwnd = [IntPtr]$ecTree.Current.NativeWindowHandle } catch { }
if ($ecTreeHwnd -eq [IntPtr]0) { $ecTreeHwnd = $ec.Hwnd }
W ('editor tree hwnd=' + $ecTreeHwnd)
[KvPostInput]::Key($ecTreeHwnd, 0x2E)
W 'sent VK_DELETE to editor'
Start-Sleep -Seconds 2
Shot 'after_del.png'
$confirm = $null
try { $confirm = Wait-KvDialogButton -ProcessId $proc.Id -TextPattern '是' -TimeoutSeconds 3 -Tag 'delete-confirm' } catch { }
if ($confirm) { W ('confirm dialog [' + $confirm.ButtonText + ']'); [void](Invoke-KvButtonPost -ButtonHwnd $confirm.ButtonHwnd -Tag 'delete-yes'); Start-Sleep -Seconds 2 }
# ---- 4) 检查节点是否消失 ----
$ecTree2 = Get-TreeUnder $ec.Hwnd
$stillThere = $false
if ($ecTree2) {
    $items2 = @($ecTree2.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { [string]$_.Current.ControlType.ProgrammaticName -eq 'ControlType.TreeItem' })
    $stillThere = [bool]($items2 | Where-Object { [string]$_.Current.Name -like $SlaveNameLike } | Select-Object -First 1)
    W ('items after DEL = ' + $items2.Count + '  stillThere=' + $stillThere)
}
if ($stillThere) {
    W 'DEL did not remove it -> try right-click menu'
    [KvPostInput]::ClickAt($ecTreeHwnd, $tx, $ty, $false, $true)
    Start-Sleep -Milliseconds 800
    Shot 'menu.png'
    [KvPostInput]::Key($ecTreeHwnd, 0x44)   # 'D'
    W 'sent D (删除(D))'
    Start-Sleep -Seconds 2
    try { $c2 = Wait-KvDialogButton -ProcessId $proc.Id -TextPattern '是' -TimeoutSeconds 3 -Tag 'delete-confirm-2' } catch { }
    if ($c2) { [void](Invoke-KvButtonPost -ButtonHwnd $c2.ButtonHwnd -Tag 'delete-yes-2'); Start-Sleep -Seconds 2 }
}
# ---- 5) 编辑器 OK（提交）----
$ok = Wait-KvDialogButton -ProcessId $proc.Id -TextPattern '^\s*OK\s*$' -TimeoutSeconds 3 -Tag 'editor-ok'
if ($ok) { [void](Invoke-KvButtonPost -ButtonHwnd $ok.ButtonHwnd -Tag 'editor-ok'); W 'editor OK clicked'; Start-Sleep -Seconds 2 } else { W 'editor OK not found' }
Shot 'after_ok.png'
# ---- 6) 保存（守卫一次 ✓ 兜底）----
$proc2 = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc2) {
    try {
        Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$proc2.MainWindowHandle) -Step 'save after delete' -Keys '^s' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 3000 | Out-Null
        W 'saved (guard)'
    } catch { W ('save failed: ' + $_.Exception.Message) }
    Start-Sleep -Seconds 2
    $t2 = [string](Get-Process -Id $proc2.Id).MainWindowTitle
    W ('title = [' + $t2 + ']')
}
$proc3 = Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc3) { try { Stop-Process -Id $proc3.Id -Force } catch { } }
Start-Sleep -Seconds 3
$after = Count-Slaves $ProjectPath
W ('slaves after = ' + $after)
[ordered]@{ ok=($after -lt $before); before=$before; after=$after; target=$SlaveNameLike } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutDir 'delete_result.json') -Encoding UTF8
W ('ok=' + ($after -lt $before))
exit 0