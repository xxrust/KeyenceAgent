---
name: windows-ui-automation
description: 通用 Windows 桌面 UI 自动化与调试方法（不限具体应用）：Win32/UIA/MFC/WinForms 混合界面探测、窗口与对话框识别、焦点与前台问题、原子手势、弹窗风暴处理、截图取证、回读验证和失败分类。用于编写或修复任何 Windows GUI 自动化脚本，以及排查“点了没反应/焦点乱跳/字段不生效/弹窗挡住/成功是假的”这类问题。KEYENCE KV STUDIO 的专用流程见 kv-studio-operator 与 kv-ui-screenshot-verification。
---

# Windows 桌面 UI 自动化

面向“把任意 Windows GUI 变成可重复脚本”的通用方法论。目标不是点得快，而是**每一步都有可验证的事实**：
窗口身份、控件状态、写后回读、失败截图。

## 何时用 / 不用

用：
- 要驱动键鼠或 UIA 操作一个桌面程序，并需要可重复、可回归。
- 已有脚本偶发失败，需要判断是焦点、弹窗、控件类型还是时序问题。
- 要给团队固化“某软件的操作流程”。

不用：
- Web 页面（用浏览器自动化）。
- 有官方 API/CLI 的场景（优先 API，UI 是最后手段）。
- 单次手工操作，没有复用价值。

## 四层现实（先探测，再动手）

Windows 程序通常同时存在四种可操作面，能力从强到弱：

| 层 | 手段 | 适用 | 风险 |
| --- | --- | --- | --- |
| 1. 语义层 | UIA（AutomationElement/Pattern） | 标准 Win32/WinForms/WPF 控件 | MFC 自绘、OwnerDraw 常无节点 |
| 2. 窗口消息层 | Win32 `EnumWindows`/`EnumChildWindows` + `WM_*` | 原生控件、按钮、编辑框 | `BM_CLICK`/`WM_SETTEXT` 对 WinForms 可能无效 |
| 3. 绘制层 | 读控件文本、剪贴板、截图 OCR | VSFlexGrid、自绘表格、报表 | 只能读“当前显示”，需滚动/选中 |
| 4. 坐标层 | 鼠标点击、键盘导航 | 最后兜底 | 分辨率/缩放/窗口位置一变就失效 |

规则：**能用 1 不用 2，能用 2 不用 4**；进入第 4 层前必须先把窗口位置固定并记录。

## 铁律

1. **先探测，后动作**：先枚举窗口/子窗口/类名/文本，确认目标存在且唯一，再点。
2. **身份按“类型 + 标题 + 正文”匹配**：只按标题会撞主窗口；只按前缀会误伤；未知对话框一律报错，不猜。
3. **原子手势**：双击、组合键、菜单选择必须是一个受保护的原子动作；两次点击之间不要截图/日志/睡眠。
4. **截图是取证，不是同步手段**：关键动作前后各一张；失败必须自动存图（含窗口清单）。
5. **等待要有超时和判据**：等“窗口出现/消失/文本变化”，不要 `Start-Sleep` 猜时间。
6. **焦点是共享资源**：`SetForegroundWindow` 可能被前台锁拒绝；点击前确认目标在前台，或改用消息/UIA。
7. **句柄会失效**：窗口关闭后旧 hwnd 会让 `FromHandle` 抛错；每次重查，不要缓存跨步骤。
8. **弹窗会排队、会乱序**：关闭主窗前先把“保存确认/刷新提示/变量创建”当成一个循环处理，处理完再继续。
9. **写后必须回读**：UI 上“看起来改了”不算；要用独立回读（重开窗口、读表格、读文件、比对前后集合）证明。
10. **不许假绿**：拿不到证据就报明确错误码；不要用 `exit 0` 掩盖没生效。

## 标准流程

```
Probe → Plan → Act → Verify → Record
```

1. **Probe**：进程、主窗口、目标窗口、控件树、当前值、是否已有对话框。
2. **Plan**：选定层（UIA/消息/坐标）、坐标基准（窗口 rect + 偏移）、成功判据、失败错误码。
3. **Act**：每步一个原子函数；失败立即截图并停止，不继续“补救”。
4. **Verify**：回读目标状态（值/行数/文件/窗口标题 `*` 消失）。
5. **Record**：日志 JSONL（事件、参数、hwnd、耗时）+ 成功/失败截图 + 结果 JSON。

## 技术选型决策树

```
目标控件能用 UIA 找到吗？
├─ 能 → 用 Pattern（Invoke/Value/SelectionItem/ExpandCollapse）
│        ├─ Invoke 卡住/超时 → 改 SetFocus + 空格/回车；或点 BoundingRectangle 中心
│        └─ ValuePattern 写不进 → WM_SETTEXT，再回读确认
└─ 不能（MFC/自绘/VSFlexGrid）
   ├─ 有原生子窗口 → EnumChildWindows 找 Edit/Button/Static，用 WM_* / BM_CLICK
   │    └─ WinForms 按钮不响应 BM_CLICK → SetFocus 后发空格
   ├─ 是表格 → 点单元格 → Ctrl+A → Ctrl+C 读剪贴板（最稳的整表读取）
   └─ 只能坐标 → 固定窗口位置，用 rect+偏移，点完必须回读
```

## 常见症状 → 根因 → 修复（实战）

| 症状 | 根因 | 修复 |
| --- | --- | --- |
| 双击没打开/加不上设备 | 两次点击之间插了截图或日志，间隔过大 | 原子双击：一次函数内完成两次 click |
| 点击落到别的窗口 | 目标不在前台，`SetForegroundWindow` 被前台锁拒绝 | 先置前并校验 `GetForegroundWindow`；或改用消息/UIA |
| `FromHandle` 报“无法识别的错误” | hwnd 已销毁/已重建 | 每步重查窗口；捕获异常后重试枚举 |
| `BM_CLICK` 没反应 | 按钮是 WinForms，不处理 `BM_CLICK` | `SetFocus()` + `SendKeys ' '`；必要时点中心 |
| UIA `Invoke()` 卡住/超时 | 模态对话框/同线程等待 | 不用 Invoke，改 SetFocus+空格或坐标点击 |
| MFC 页签切不过去 | Tab 是 `Afx:TabWnd`，无 UIA TabItem | 用菜单快捷键（如 Alt+3）或 Tab 的 rect 计算点击 |
| 表格读不到 | VSFlexGrid/自绘，UIA 无单元格 | 点单元格 → Ctrl+A → Ctrl+C |
| 字段改了没生效 | 字段只读 / SetValue 对 WinForms 无效 | 走属性对话框；或 WM_SETTEXT + 回读 |
| 保存后仍有 `*` | 存在未处理的确认弹窗 | 保存后轮询弹窗并处理，直到标题无 `*` |
| 弹窗按预期顺序等不到 | 弹窗乱序/延迟出现 | 用一个“处理任意已知弹窗”的循环 + 总超时 |
| 多设备连续添加后编号不对 | 软件自动分配编号，不是配置值 | 读回实际值并记录；不要假设等于请求值 |
| 成功是假的 | 只看点击返回/退出码 | 独立回读并比对前后集合；无新增即失败 |

## 可复用代码

`scripts/UiProbe.ps1` 提供与业务无关的基础函数：

```powershell
. <skill>\scripts\UiProbe.ps1
$w = Get-UiWindow -ProcessName Kvs -TitleLike 'EtherNet/IP'
Get-UiChildList -Hwnd $w.Handle | Where-Object Class -like 'Button*'
Get-UiStaticText -Hwnd $w.Handle
Wait-UiWindow -ProcessName Kvs -TitleLike '适配器初始设定' -TimeoutSeconds 10
Invoke-UiButton -Element $el -Name '确定'
Save-UiScreenshot -Path C:\temp\shot.png
```

自检：`powershell -File scripts\Test-UiProbe.ps1`（应输出当前会话可见窗口数与自检 PASS）。

## 反模式

- 用固定坐标点“某个单元格/某一行”，而不是选中对象。
- 用 `Start-Sleep` 当同步；用截图当同步。
- 为了“让它过”而放宽窗口遍历/标题匹配。
- 在测试运行期间人工操作同一台机器（焦点被抢，结果不可信）。
- 失败后杀掉目标进程（现场丢失，无法复盘）。
- 把“日志里有 saved”当成保存成功。

## 交付物清单（每个 UI 自动化任务）

- [ ] 探测记录：进程、窗口类名、关键控件、当前值
- [ ] 原子动作函数：双击/组合键/菜单各一个
- [ ] 错误码：每个失败分支有唯一 code + 截图
- [ ] 回读断言：写后独立验证
- [ ] 结果 JSON + 日志 JSONL + 成功/失败截图
- [ ] 离线契约测试：文件/参数/错误码存在性（不需要真 UI）
- [ ] 一次真实全流程证据（日志 + 截图 + 回读）

## 与专用 skill 的关系

- KEYENCE KV STUDIO 的具体步骤、脚本入口、验证矩阵：`kv-studio-operator`。
- KV 界面的“截图优先”纪律与已踩坑清单：`kv-ui-screenshot-verification`。
- 本 skill 只保留**跨应用可复用**的方法、决策树、症状表和基础函数；具体产品的坐标、控件 id、业务顺序不放这里。

## 参考

- `references/win32-cheatsheet.md`：窗口/子窗口枚举、消息、焦点、坐标。
- `references/uia-cheatsheet.md`：Pattern 选择、阻塞与替代、常见坑。
- `references/failure-playbook.md`：按症状排查的步骤清单。
- `references/case-studies.md`：真实案例（KV EIP 写入、EtherCAT 节点、轴改名）。
