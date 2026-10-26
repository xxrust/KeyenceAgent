# UIA 速查（语义层）

## 创建与查找

```powershell
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
$cond = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
  [System.Windows.Automation.ControlType]::Button)
$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
```

- `FromHandle` 对 **已销毁/重建** 的 hwnd 会抛 `ElementNotAvailableException`；每次重查，捕获后重试。
- `FindAll` 很慢；先缩小范围（根元素/窗口），再过滤 `Name`/`AutomationId`。
- 未知弹窗里 `Name` 可能是正文文本，按钮可能是 `Pane` 而不是 `Button`：**按名字匹配，不按类型过滤**。

## Pattern 选择

| 需求 | Pattern | 备注 |
| --- | --- | --- |
| 点按钮 | `InvokePattern` | 可能因模态/同线程等待**阻塞** |
| 写文本 | `ValuePattern.SetValue` | 对 WinForms/只读字段可能无效 |
| 选中列表/树项 | `SelectionItemPattern.Select()` | 比点击稳 |
| 展开树 | `ExpandCollapsePattern.Expand()` | 展开后等 300ms |
| 读表格 | 无 | 走剪贴板：点单元格 → Ctrl+A → Ctrl+C |

## 阻塞与替代

`Invoke()` 会同步等待目标线程处理，遇到模态对话框时可能**挂起整个脚本**（表现为超时/无输出）。

替代顺序：
1. `element.SetFocus()` + `SendKeys ' '`（对 WinForms 按钮最有效）。
2. `element.Current.BoundingRectangle` 中心点击（最后手段）。
3. `SendMessage(BM_CLICK)`（仅原生按钮）。

## 常见坑

- **ControlType 不可信**：MFC/自绘按钮常是 `Pane`/`Text`；`Button` 过滤会漏。
- **ValuePattern 值读不到**：`Current.Value` 可能为空，但界面有值；改用 Win32 `GetWindowText` 或剪贴板。
- **UIA 树缺失**：MFC 自绘（`Afx:*`）没有 UIA 节点；必须回退 Win32/坐标。
- **TabItem 缺失**：`Afx:TabWnd` 不暴露 TabItem；用菜单快捷键（`Alt+数字`）切页。
- **Invoke 后界面没变**：可能只是“计算/预览”，需要再点应用/OK；回读确认。
- **多个同名元素**：用父窗口限定 + `AutomationId`，并断言恰好 1 个。

## 最小可用模板

```powershell
function Invoke-UiButton($root, [string]$name) {
  foreach ($b in @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
    if ([string]$b.Current.Name -eq $name) {
      $b.SetFocus(); Start-Sleep -Milliseconds 200
      [System.Windows.Forms.SendKeys]::SendWait(' ')
      return $true
    }
  }
  return $false
}
```

配套：`scripts/UiProbe.ps1` 的 `Invoke-UiButton` 已包含 enable 等待与 `BM_CLICK` 兜底。
