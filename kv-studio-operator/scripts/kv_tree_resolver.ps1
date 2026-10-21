# KV STUDIO 工程树 —— 结构优先解析器（不使用通配符）
#
# 为什么这样写：
#   * 树项名里带序号后缀（"HMI [17]"），'[' ']' 在 PowerShell 的 -like 里是字符类，
#     任何 -like 匹配都会静默失配或抛 WildcardPatternException。
#   * 每个程序节点内部都有 "书签" 文件夹，书签项是**孙节点**，名字又与程序名相近
#     （HMI / HMI轴控制），按名字在全树里搜必然误伤。
#   * 因此：按父路径逐级只取**直接子项**，再用结构指纹（[局部变量] + [书签]）确认。

function Get-KvTreeChildItems {
    param([Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Element)
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::TreeItem)
    @($Element.FindAll([System.Windows.Automation.TreeScope]::Children, $cond))
}

function Expand-KvTreeNode {
    param([Parameter(Mandatory)]$Element)
    try {
        $ec = $Element.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
        if ($ec.Current.ExpandCollapseState -ne [System.Windows.Automation.ExpandCollapseState]::Expanded) {
            $ec.Expand()
            Start-Sleep -Milliseconds 120
        }
    } catch { }
}

function Get-KvTreeRootElement {
    param([Parameter(Mandatory)][int]$ProcessId)
    $proc = Get-Process -Id $ProcessId -ErrorAction Stop
    $handle = [IntPtr]$proc.MainWindowHandle
    if ($handle -eq [IntPtr]::Zero) { throw 'KV_TREE_MAIN_WINDOW_MISSING' }
    [System.Windows.Automation.AutomationElement]::FromHandle($handle)
}

function Get-KvProjectTree {
    param([Parameter(Mandatory)][int]$ProcessId)
    $root = Get-KvTreeRootElement -ProcessId $ProcessId
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'ProjectTreeView')
    $tree = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if (-not $tree) { throw 'KV_PROJECT_TREE_PANEL_ABSENT' }
    $tree
}

function Test-KvProgramNodeFingerprint {
    # 真正的"程序"节点必定同时有 [局部变量] 与 [书签] 两个直接子项。
    # 书签文件夹本身没有 [局部变量]，因此不可能通过这条判据。
    param([Parameter(Mandatory)]$Element)
    $names = @(Get-KvTreeChildItems -Element $Element | ForEach-Object { [string]$_.Current.Name })
    ($names -contains '局部变量') -and ($names -contains '书签')
}

function Resolve-KvTreeNodeByPath {
    # 从工程树根开始，逐级只在"直接子项"里找名字完全匹配的节点。
    # Path[0] 允许用正则（如 '^程序\(显示执行顺序\)'），其余必须完全相等。
    param(
        [Parameter(Mandatory)]$Tree,
        [Parameter(Mandatory)][string[]]$Path
    )
    $current = $Tree
    for ($i = 0; $i -lt $Path.Count; $i++) {
        Expand-KvTreeNode -Element $current
        $step = $Path[$i]
        $match = $null
        foreach ($child in (Get-KvTreeChildItems -Element $current)) {
            $name = [string]$child.Current.Name
            if ($step.StartsWith('^')) {
                if ($name -match $step) { $match = $child; break }
            } else {
                if ($name -ceq $step) { $match = $child; break }
            }
        }
        if (-not $match) { return $null }
        $current = $match
    }
    $current
}

function Find-KvProgramContainer {
    param(
        [Parameter(Mandatory)]$Tree,
        [ValidateSet('scan', 'backup')][string]$Category = 'scan'
    )
    $programRoot = Resolve-KvTreeNodeByPath -Tree $Tree -Path @('^程序\(显示执行顺序\)')
    if (-not $programRoot) { throw 'KV_PROGRAM_ROOT_MISSING' }
    $containerName = if ($Category -eq 'backup') { '后备模块' } else { '每次扫描执行型模块' }
    Resolve-KvTreeNodeByPath -Tree $Tree -Path @('^程序\(显示执行顺序\)', $containerName)
}

function Resolve-KvProgramNode {
    # 返回扫描程序/后备模块节点；名字按 "精确名" 或 "名字 [序号]" 匹配，且必须通过结构指纹。
    param(
        [Parameter(Mandatory)]$Tree,
        [Parameter(Mandatory)][string]$ModuleName,
        [ValidateSet('scan', 'backup')][string]$Category = 'scan'
    )
    $container = Find-KvProgramContainer -Tree $Tree -Category $Category
    if (-not $container) { throw 'KV_PROGRAM_CONTAINER_MISSING' }
    Expand-KvTreeNode -Element $container
    $pattern = Get-KvModuleNamePattern -ModuleName $ModuleName
    foreach ($child in (Get-KvTreeChildItems -Element $container)) {
        $name = [string]$child.Current.Name
        if ($name -notmatch $pattern) { continue }
        if (-not (Test-KvProgramNodeFingerprint -Element $child)) { continue }
        return $child
    }
    $null
}

function Resolve-KvModuleNode {
    # 功能块等"按路径"定位：Path 里的每一级都必须完全相等；末节点必须是程序/FB 节点。
    param(
        [Parameter(Mandatory)]$Tree,
        [Parameter(Mandatory)][string[]]$Path
    )
    Resolve-KvTreeNodeByPath -Tree $Tree -Path $Path
}

function Find-KvModuleNodeBounded {
    # 有界结构搜索：从给定根出发，**只穿过文件夹型节点**，遇到模块型节点（[局部变量]+[书签] 指纹）
    # 就比较名字、且**不再进入它的子项** —— 因此程序内部的书签/局部变量永远不会被误当成模块。
    param(
        [Parameter(Mandatory)]$Tree,
        [Parameter(Mandatory)][string]$ModuleName,
        [string[]]$RootPatterns = @('^程序\(显示执行顺序\)', '^功能块'),
        [int]$MaxDepth = 4
    )
    $pattern = Get-KvModuleNamePattern -ModuleName $ModuleName
    $frontier = @()
    foreach ($rootPattern in $RootPatterns) {
        $root = Resolve-KvTreeNodeByPath -Tree $Tree -Path @($rootPattern)
        if ($root) { $frontier += $root }
    }
    if (-not $frontier) { return $null }
    for ($depth = 0; $depth -le $MaxDepth; $depth++) {
        $next = @()
        foreach ($node in $frontier) {
            Expand-KvTreeNode -Element $node
            foreach ($child in (Get-KvTreeChildItems -Element $node)) {
                $name = [string]$child.Current.Name
                $isModule = Test-KvProgramNodeFingerprint -Element $child
                if ($isModule) {
                    if ($name -match $pattern) { return $child }
                } else {
                    $next += $child
                }
            }
        }
        if (-not $next) { break }
        $frontier = $next
    }
    $null
}
function Get-KvModuleNamePattern {
    # 模块在工程树里可能带两种后缀：显示名（FB_McMode:设备模式）与执行序号（HMI [17]）。
    # 名字里的 '[' ']' 在 PowerShell 通配符里是字符类，所以这里只构造**正则**，
    # 并对模块名做 Escape —— 调用方不得改用 -like。
    param([Parameter(Mandatory)][string]$ModuleName)
    '^' + [regex]::Escape($ModuleName) + '(?::[^\[\]]*)?(?: \[\d+\])?$'
}

function Test-KvModuleNameMatch {
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][AllowEmptyString()][string]$CandidateName
    )
    if ([string]::IsNullOrEmpty($CandidateName)) { return $false }
    $pattern = Get-KvModuleNamePattern -ModuleName $ModuleName
    return [bool]($CandidateName -match $pattern)
}
function Get-KvTreeItemClickPoint {
    # 返回树项中心文字区的屏幕坐标（每次都重新读 rect，避免使用过期矩形）。
    param([Parameter(Mandatory)]$Element)
    try {
        $r = $Element.Current.BoundingRectangle
        if ($r.Width -le 0 -or $r.Height -le 0) { return $null }
        $x = [int]($r.X + [Math]::Min(60, [Math]::Max(10, $r.Width / 4)))
        $y = [int]($r.Y + ($r.Height / 2))
        return [pscustomobject]@{ x = $x; y = $y; rect = $r }
    } catch { return $null }
}

function Test-KvTreeItemKeyboardFocus {
    param([Parameter(Mandatory)]$Element)
    try { return [bool]$Element.Current.HasKeyboardFocus } catch { return $false }
}

function Select-KvTreeNode {
    # 可靠地把键盘焦点交给一个树项：
    #   ScrollIntoView → Select() → 读新鲜坐标点击 → 断言 HasKeyboardFocus
    # 调用方必须传入受守卫保护的点击脚本（$ClickScript x y），本函数不直接发送输入。
    param(
        [Parameter(Mandatory)]$Element,
        [Parameter(Mandatory)][scriptblock]$ClickScript,
        [int]$Attempts = 3
    )
    try {
        $si = $Element.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern)
        $si.ScrollIntoView()
        Start-Sleep -Milliseconds 150
    } catch { }
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $sel = $null
            if ($Element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sel)) { $sel.Select() }
        } catch { }
        try { $Element.SetFocus() } catch { }
        Start-Sleep -Milliseconds 150
        if (Test-KvTreeItemKeyboardFocus -Element $Element) { return $true }
        $pt = Get-KvTreeItemClickPoint -Element $Element
        if ($pt) {
            try { & $ClickScript $pt.x $pt.y | Out-Null } catch { }
            Start-Sleep -Milliseconds 300
        }
        if (Test-KvTreeItemKeyboardFocus -Element $Element) { return $true }
    }
    return $false
}
