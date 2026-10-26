# EtherNet/IP 设定读取（KV STUDIO Ver.12G）

## 窗口结构

| 对象 | 类/形态 | 可读方式 |
|---|---|---|
| `EtherNet/IP 设定` 主窗口 | MFC `Afx`，含 `VSFlexGrid8L` | 无 UIA 树，只能读子窗口/坐标 |
| `连接设定 - N:<设备>` | 标准 `#32770` | UIA 可读，AutomationId 稳定 |
| `软元件分配设定` | `#32770`，表格是 `VSFlexGrid8L` | 表格用剪贴板复制 |

打开方式：项目树 `单元配置 → [0] KV-X520 → EtherNet/IP` 节点双击打开主窗口；主窗口左侧树里**单击**某个连接节点（如 `Monitor Data (Input Only)`）即可打开 `连接设定`。

## 连接设定字段（UIA AutomationId）

| AutomationId | 字段 |
|---|---|
| 1872 | 连接名称 |
| 1874 | IN 连接类型 |
| 1875 | IN 连接点（如 `IN_100`） |
| 1763 | IN 数据大小（字） |
| 1940 | 发送触发器 |
| 1687 | IN RPI (ms) |
| 1764 | OUT 数据大小（字） |
| 2134 | OUT RPI (ms) |
| 1600 | `软元件分配(D)...` 按钮 |

## 软元件分配表复制

表格是 VSFlexGrid，没有 UIA。做法：

1. 点击表格内任意单元格；
2. `Ctrl+Home`；
3. `Ctrl+Shift+End`；
4. `Ctrl+C`；
5. 读剪贴板，按行 `设备<TAB>名称` 解析。

样例：`IN_100` 复制出 199 行，含 `B00 NU Error Status`、`B01`（空名）、`B08 Updating Sensor Set.` … `W00 Error ID Number` 等。

## 快照脚本

```powershell
powershell -File <skill-root>\scripts\workflow_tools\get_kv_eip_connection_snapshot.ps1 `
  -ConnectionTitle '连接设定' -OutDir C:\kvrun\eip\snapshots
```

- 读取当前打开的 `连接设定` 窗口字段；
- 点 `软元件分配(D)...`，复制整表；
- 输出 `<连接名>.json`（fields + assignment[] + raw_path）和 `<连接名>.tsv`；
- 默认用“取消”关闭 `软元件分配设定` 与 `连接设定`（`-KeepDialogs` 可保留）。

**清理规则**：读完必须关闭窗口。脚本负责关闭连接/分配对话框；`EtherNet/IP 设定` 主窗口由调用方用“取消”关闭，最终只留 KV STUDIO 主窗口。

## 样例工程实测值（2026-10-26）

| 设备 | 节点/IP | 连接 | 连接点 | 数据大小 | 区域 |
|---|---|---|---|---|---|
| NU-EP1 | 1 / 192.168.0.1 | Monitor Data (Input Only) | IN_100 | 64 字 | `B00` 10字 偏移0；`W00` 43字 偏移10 |
| NU-EP1 | 1 / 192.168.0.1 | Sensor Output (Input Only) | IN_102 | 1 字 | `B0A0`~`B0A3` |
| DL-EP1 | 2 / 192.168.0.3 | Monitor Data (Input Only) | IN_100 | 84 字 | `B0B0` 18字 偏移0；`W02C` 6字 偏移20 |

CPU IP：`192.168.0.10`。连接超时 `RPI×16`，刷新优先权“一般”。

## 写配置的现状

仓库目前只有读取脚本；`EtherNet/IP 设定` 的写入（加设备/连接/分配）还没有 workflow。
如果要重建 EIP，优先确认该窗口“文件(F)”菜单是否支持设定导出/导入；不支持再实现 MFC 自动化。
