# EIP 节点 CRUD 验收契约

## 结果文件

| 操作 | 文件 | 关键字段 |
| --- | --- | --- |
| Add | `eip_write_result.json` | `ok`, `model`, `ip_address`, `readback` |
| Modify | `eip_edit_result.json` | `ok`, `verified`, `action`, `node_address`, `ip_address`, `pre_ips`, `post_ips` |
| Delete | `eip_edit_result.json` | `ok`, `verified`, `action`, `node_address`, `pre_ips`, `post_ips` |

`verified` 只表示“本次运行有回读证据”。能力级验收还需要人工跑通一次并记录日期/工程/截图。

## 判据

Add：

```
post_ips = readback after write
success  = post_ips 中存在 pre_ips 之外的新 IP
failure  = KV_EIP_READBACK_FAILED
```

Modify：

```
success = post_ips 包含目标 ip_address
failure = KV_EIP_EDIT_READBACK_FAILED
```

Delete：

```
success = post_ips.Count < pre_ips.Count
failure = KV_EIP_EDIT_READBACK_FAILED
```

## 失败错误码

| 错误码 | 含义 |
| --- | --- |
| `KV_EIP_PROJECT_NOT_OPEN` | 目标工程未打开 |
| `KV_EIP_PROJECT_UNSAVED` | 标题带 `*`，拒绝操作 |
| `KV_EIP_SETTINGS_NOT_OPENED` | EIP 设定窗口没打开 |
| `KV_EIP_MANUAL_MODE_NOT_SELECTED` | 首启弹窗没处理掉 |
| `KV_EIP_DEVICE_LIST_EMPTY` | 设定列表读回为空，无法选行 |
| `KV_EIP_IP_FIELDS_NOT_FOUND` | 设备设定页找不到 4 个 IP 分片输入框 |
| `KV_EIP_EDIT_READBACK_FAILED` | 写后回读不符合判据 |
| `KV_EIP_PROJECT_SAVE_FAILED` | Ctrl+S 后仍有 `*` |

## 验收步骤（人工执行一次）

1. 准备一个**已保存**的测试工程，EIP 里至少 2 个设备。
2. 跑 Add：新增一个设备；确认 `eip_write_result.json` 的 `readback` 出现新 IP。
3. 跑 Modify：把目标节点 IP 改成未占用的地址；确认 `post_ips` 含新 IP、不含旧 IP（如只改一台）。
4. 跑 Delete：删掉该节点；确认 `post_ips` 数量减少且目标 IP 消失。
5. 保存工程、重开 KV，确认设备数量与 IP 仍一致（防止只改了界面缓存）。
6. 把日志、结果 JSON、`success.png` 路径写进 `kv-studio-operator` 的验收记录。

## 已知未验证点（Modify/Delete）

- 设备行选择依赖左侧扫描树的行序（当前观测为节点号降序，行高约 24px）；分辨率/缩放变化需要重新标定。
- 设备设定页的 4 个 IP 分片输入框通过枚举 `Edit` 子窗口并按值匹配；若某版本用自定义控件，需要改实现。
- 删除确认弹窗的按钮文案未在真实环境确认（当前尝试 `是(Y)`，回退 `确定`）。
- 第一次真实验收时，先跑 **Modify**（可回读、可恢复），再跑 **Delete**。
