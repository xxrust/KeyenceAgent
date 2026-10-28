# EIP 节点 CRUD 验收契约

## 结果文件

| 操作 | 文件 | 关键字段 |
| --- | --- | --- |
| Add | `eip_write_result.json` | `ok`, `model`, `ip_address`, `readback` |
| Modify | `eip_edit_result.json` | `ok`, `verified`, `action`, `node_address`, `ip_address`, `pre_ips`, `post_ips`, `in_window_ips` |
| Delete | `eip_edit_result.json` | `ok`, `verified`, `action`, `node_address`, `pre_ips`, `post_ips`, `in_window_ips` |

`verified=true` 只表示**本次运行**的窗口内回读 + 保存后重开回读都符合判据；能力级验收记录见
`SKILL.md` 的能力矩阵（含日期与工程）。

## 判据（当前实现）

Add：

```
post_ips = 窗口内回读（写后）
success  = post_ips 中出现 pre_ips 之外的新 IP
failure  = KV_EIP_READBACK_FAILED
```

Modify：

```
in_window_ips   = 点“应用”后、保存前的回读
post_ips        = 保存后重开 EtherNet/IP 的回读
success         = in_window_ips 与 post_ips 都包含目标 IP
failure         = KV_EIP_EDIT_READBACK_FAILED / KV_EIP_PERSISTED_READBACK_MISSING
```

Delete：

```
post_ips = 保存后重开 EtherNet/IP 的回读
success  = post_ips.Count < pre_ips.Count
failure  = KV_EIP_EDIT_READBACK_FAILED / KV_EIP_PERSISTED_READBACK_MISSING
```

已知限制：判据基于“IP 集合”，不建立 node→IP 的完整映射；若目标 IP 原本已被另一设备占用，
Modify 的 `contains` 判据不足以证明改的是目标设备（见审核 R06，后续补 node 级映射）。

## 失败错误码

| 错误码 | 含义 |
| --- | --- |
| `KV_EIP_PROJECT_NOT_OPEN` | 目标工程未打开 |
| `KV_EIP_PROJECT_UNSAVED` | 标题带 `*`，拒绝操作 |
| `KV_EIP_SETTINGS_NOT_OPENED` | EIP 设定窗口没打开 |
| `KV_EIP_MANUAL_MODE_NOT_SELECTED` | 首启弹窗没处理掉 |
| `KV_EIP_DEVICE_LIST_EMPTY` | 设定列表读回为空，无法选行 |
| `KV_EIP_DEVICE_ROW_NOT_FOUND` | 节点列扫描没有找到目标节点 |
| `KV_EIP_EDIT_READBACK_FAILED` | 写后回读不符合判据 |
| `KV_EIP_PERSISTED_READBACK_MISSING` | 保存后重开没有拿到回读 |
| `KV_EIP_DELETE_CONFIRM_MISSING` | Delete 没有出现确认框（多半没选中设备） |
| `KV_EIP_PROJECT_SAVE_FAILED` | Ctrl+S 后仍有 `*` |

## 当前操作路线（2026-10-28 实机验证）

- 选设备：`设定列表` 的“节点”列可复制。逐行点节点单元格 → `Ctrl+C` 读取标签；
  纯数字行是设备行，`1-1` 这类是连接行。找到目标后 `Enter` 选中设备。
- 改 IP：`设备设定(2)` 的 IP 是四段掩码控件。点一次 IP 字段 → `Ctrl+A` →
  输入完整点分地址（如 `192.168.0.31`）→ `Tab`。逐段按 `Tab` 不会前进，会把四段都写进第一段。
- 删设备：`Delete` 只对**左侧树**的选择生效。
  1. 数出目标设备在节点列中的序号 `index`；
  2. 点 CPU 行 → `Down` 进入第一台；
  3. 重复 `index` 次：`Left`（折叠连接子行）→ `Down`；
  4. `Delete` → 确认框 `是(Y)` / `Alt+Y`。
- 保存：`应用` → `OK` → `Ctrl+S` → 清理“更新单元编辑器信息”等弹窗；
  然后**重开 EtherNet/IP** 做保存后回读。

## 验收记录（历史，非当前保证）

- 2026-10-28：样例工程副本 add/modify/delete 全部通过（`C:\kvrun\eip_live\*`）。
- 2026-10-28：真实重建工程副本（`C:\kvrun\eip_real\Proj`）add NU-EP1、add DL-EP1、
  modify 节点 2 → `.3`、delete 节点 1（index=1）通过。
- 自动化：`tests\eip-live-cycle\run.bat`（离线 fixture 循环）、`tests\eip-write-contract`（契约）。
