# Win32 速查（窗口消息层）

只放跨应用通用的部分。业务坐标、控件 id 不放这里。

## 枚举

```powershell
# 顶层窗口
[UiProbeNative]::Windows($pid, $visibleOnly)   # "hwnd|class|title"

# 子窗口（所有层级一次性拍平）
[UiProbeNative]::Children($hwnd)                # "hwnd|class|text"

# 只看 Static 文本（MFC 详情面板、状态栏常用）
[UiProbeNative]::Statics($hwnd)
```

要点：
- `EnumChildWindows` 会递归；拿到的顺序是 Z 序/创建序，不要假设业务顺序。
- `GetWindowText` 对 WinForms 的 Edit **经常返回空**；UIA `ValuePattern` 或剪贴板更可靠。
- 同一标题可能有多个窗口（主窗口、无标题壳、tooltip），必须用 class 或进程二次过滤。

## 常用消息

| 消息 | 用途 | 注意 |
| --- | --- | --- |
| `WM_SETTEXT 0x000C` | 给原生 Edit 写值 | WinForms 可能不刷新内部状态；写完必须回读 |
| `BM_CLICK 0x00F5` | 点按钮 | WinForms 按钮**不响应**；改用聚焦+空格 |
| `WM_CLOSE 0x0010` | 关闭窗口/对话框 | 对“取消变量设置”这类可选弹窗最省事 |
| `WM_COMMAND 0x0111` | 菜单/工具栏命令 | 需要知道命令 id，通常拿不到 |
| `TCM_*` | Tab 控件 | MFC OwnerDraw Tab 常无效，优先菜单快捷键 |

## 焦点与前台

```powershell
[UiProbeNative]::SetForegroundWindow($hwnd)
$fg = [UiProbeNative]::GetForegroundWindow()   # 校验是否真的切过去
```

坑：
- `SetForegroundWindow` 受前台锁限制，可能**静默失败**；点击会落到别的窗口。
- 失败时不要循环硬点；改用消息/UIA，或先最小化其他窗口。
- 模态对话框存在时，主窗口的键盘输入会被吞掉。

## 坐标

```powershell
$r = Get-UiRect -Hwnd $hwnd
$pt = Click-UiPoint -Hwnd $hwnd -OffsetX 300 -OffsetY 760
```

规则：
- 坐标一律 **窗口 rect + 偏移**，不写屏幕绝对坐标。
- 点击前把窗口移到已知位置（`MoveWindow`），否则 DPI/多屏会偏。
- 坐标点击是最后手段；点完必须回读。

## 双击与组合键（原子手势）

```powershell
# 一次函数内完成，中间不截图/不写日志
[UiProbeNative]::Click($x, $y)   # 内部 120ms 间隔
# 双击：调用两次 Click，或自己写 down/up/down/up（两次间隔 60-130ms）
```

踩过的坑：两次点击之间插一次截图（~200ms），双击就被系统当成两次单击，设备/文件打不开。

## 对话框识别

```powershell
$dialogs = Get-UiDialogList -ProcessId $pid -ClassLike '#32770'
```

- `#32770` 是标准对话框壳；WinForms 弹窗也常用它。
- 必须用“标题 + 正文文本”双条件，否则会把主窗口/进度窗当成确认框。
- 未知对话框不要自动点“确定”；先枚举按钮与文本，再决定。

## 进程与窗口归属

```powershell
(Get-Process Kvs).MainWindowHandle      # 可能是 0 或过期句柄
Get-UiWindowList -ProcessId $pid        # 更可靠
```

`MainWindowTitle` 适合做“工程是否打开/是否有未保存 `*`”的粗判，不适合定位具体窗口。
