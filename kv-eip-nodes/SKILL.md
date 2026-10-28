---
name: kv-eip-nodes
description: 对 KV STUDIO 工程的 EtherNet/IP 节点做增（Add）、查（Read）、改（Modify）、删（Delete），并用写后回读证明结果。用于批量配置 EIP 扫描列表、修改节点 IP、清理测试设备，以及判断“EIP 配置到底写没写进去”。入口是 kv-studio-operator 的 workflow / bat，不要在业务脚本里手拼键鼠。
---

# KV EtherNet/IP 节点 CRUD

本 skill 只负责 EIP 扫描列表里的**设备节点**（NU-EP1、DL-EP1 等），不负责连接设定/软元件分配的内部表格；后者用 `get_kv_eip_connection_snapshot.ps1` 读取。

## 能力矩阵

| 能力 | 入口 | 状态 |
| --- | --- | --- |
| 查（连接明细） | `scripts/workflow_tools/get_kv_eip_connection_snapshot.ps1` | 已实机验证 |
| 查（节点/IP 列表） | 写/改/删 runner 内的 `设定列表` 剪贴板回读 | 已实机验证（Add 流程） |
| 增（Add） | `configure_kv_eip_devices.bat` / `configure_kv_eip_devices.ps1` | 已实机验证（2026-10-26，回读新增 IP） |
| 改（Modify） | `modify_kv_eip_device.bat` | 已实机验收（2026-10-28，节点 3 IP 192.168.0.3 → 192.168.0.31，回读确认） |
| 删（Delete） | `delete_kv_eip_device.bat` | 已实机验收（2026-10-28，删除节点 3，设定列表 5 行 → 3 行） |

验收证据：`C:\kvrun\eip_live\add4`、`modify15`、`delete9`（各含 `eip_*_result.json` + `success.png`）。

实现要点与限制：

- **Modify** 通过 `设定列表` 的“节点”列逐行 `Ctrl+C` 搜索目标节点（不假设行序），命中后 `Enter` 选中设备；IP 字段点一次后 `Ctrl+A` 输入完整点分地址，`Tab` 提交。
- **Delete** 必须让**左侧树**选中设备：`Delete` 只对树选择生效，列表行选中会落到扫描器并报“无法对扫描器执行该操作”。当前实现选中“PLC 之后的第一台设备”（Add 新节点即位于此处），删除前请确认目标就是这台。
- 两者都在窗口内回读 `设定列表` 后才保存；保存后会清掉“更新单元编辑器信息”提示。

## 配置格式

```json
{
  "schema_version": 1,
  "devices": [
    { "model": "NU-EP1", "node_address": 1, "ip_address": "192.168.0.1" }
  ]
}
```

- **Add**：`model` 必填；`node_address`/`ip_address` 可选（KV 会自动分配，配置值目前只进计划与日志）。
- **Modify**：`node_address` 必填用于选行，`ip_address` 必填为新值；`model` 可选。
- **Delete**：`node_address` 必填；其余字段忽略。

工作流在打开 UI 前校验：节点号数字且不重复、IP 为 IPv4、Modify 必须给 IP。

## 调用

```powershell
# 增
.\configure_kv_eip_devices.bat -ProjectPath <kpr> -DevicesConfigPath <json> -OutDir <dir>

# 改（IP）
.\modify_kv_eip_device.bat -ProjectPath <kpr> -DevicesConfigPath <modify.json> -OutDir <dir>

# 删
.\delete_kv_eip_device.bat -ProjectPath <kpr> -DevicesConfigPath <delete.json> -OutDir <dir>
```

通用参数：`-PlanOnly`（只生成计划）、`-PreflightOnly`（仅验证打开 EIP + 手动模式，Add 专用）、`-TimeoutSeconds`。

## 成功判据（不许假绿）

- Add：写前/写后各读一次 `设定列表` 的 IP 集合，**出现新 IP** 才算成功。
- Modify：写后集合包含目标 IP。
- Delete：写后集合数量**减少**。
- 任何一步没有拿到回读 → `KV_EIP_*_READBACK_FAILED`，不是成功。

结果 JSON：
- Add：`eip_write_result.json`
- Modify/Delete：`eip_edit_result.json`（含 `verified`；2026-10-28 起 Modify/Delete 已实机验收，`ok=true` 表示本次窗口内回读与落盘均通过）

## 关键 UI 事实（KV STUDIO 12G）

1. 首启弹窗 `未设定EtherNet/IP設定` 的 `手动(M)` 是 Pane，不是 Button；按名字匹配 + `SetFocus` + 空格。
2. `设备列表/设备设定/设备查找` 是 MFC `Afx:TabWnd`，没有 UIA TabItem；用 `Alt+1/2/3` 切页。
3. 设备目录是 `VSFlexGrid`：点网格 → `Ctrl+Home` → 逐行 `Down`，同时读窗口 `Static` 详情文本，命中机型后回车。
4. 回车后 `适配器初始设定` 由 KV 自动填节点/IP，直接 OK。
5. 主窗口 OK 后的弹窗**乱序**：`设定信息被更改`（是(Y)）→ `更新单元编辑器`（确定）→ `创建设备连接用变量`（确定）→ `EtherNet/IP设备 变量设置`（可直接 `WM_CLOSE`）。
6. 这些弹窗的“确定”不响应 `BM_CLICK`，`Invoke()` 会卡住；用 `SetFocus` + 空格。
7. 回读：重开 EIP → 点 `设定列表` 网格 → `Ctrl+A` → `Ctrl+C`，解析 IP 行。
8. KV 自动分配的编号可能不等于配置值（例如请求 `.2`，实际分配 `.6`）；以回读为准。

## 安全与边界

- 只操作**当前打开的工程**；工程标题带 `*` 时拒绝执行（先保存）。
- 不碰连接设定内部表格、不改软元件分配；这些是独立能力。
- 不杀 KVS 进程；失败必须留 `failure.png` 与窗口日志。
- 修改/删除前先记录完整 IP 集合；失败可直接据此判断是否部分生效。

## 与其它 skill 的关系

- 工程入口/工作流/验证矩阵：`kv-studio-operator`
- 通用 Windows UI 调试方法：`windows-ui-automation`
- KV 界面截图纪律：`kv-ui-screenshot-verification`

## 参考

- `references/verification-contract.md`：成功判据、结果字段、验收步骤。
