# KV Nano 工程格式与快照注意事项（2026-11-16 实测 `纯48` 工程）

样本：`C:\Users\Administrator\Downloads\纯48.zip` → 解压后 `纯48\纯48.kpr`，KV STUDIO 打开标题为
`KV STUDIO - [编辑器: KV-NC32] - [纯48]`（CPU = **KV-NC32**，Nano 系列）。

## 1. 文件形态（与 KV-X/8000 工程不同）

| 项目 | KV Nano（本样本） | KV-X / KV-8000（对比） |
|---|---|---|
| 工程指针 | `纯48.kpr`（4 KB，二进制） | `*.kpr` + `All.prgx`（1 MB 级） |
| 程序体 | **每个程序一个 `.mod`**：`Main.mod`、`IO测试.mod`、`正向移动.mod`、`反向移动.mod`、`测试.mod`、`往复测试.mod`、`增量移动.mod`、`正常运行.mod`、`采图.mod` | 单个 `All.prgx` 承载全部程序 |
| 树结构 | **没有 `WsTreeEnv.xml`** | `WsTreeEnv.xml` 是树/模块顺序的证据源 |
| 单元配置 | `UnitSet.ue2` + `UnitSet.ue2.old` + `CpuMb2.inf` | `UnitSet.ue2` + `WsTreeEnv.xml` |
| 注释/标签 | `纯48.cm1/.cm2`、`纯48.lbl` | 同名 |
| 其他 | `DevInit.dvi`、`PlcSended.dky`、`ProEnv.xml`、`SensorIOMonitor.json`、`operand-history.txt` | 类似 |

树里可见（截图确认）：`单元配置(0) KV-NC32 R00`、`软元件注释`、`标签`、`CPU 系统设定`、
`程序(纯48)` → 每次扫描执行型模块（9 个）、初始化模块、后备模块、以及 **`宏`**（子程序型宏 / 自保持型宏 / 软元件初始值）。

## 2. 对现有工具的影响（实测）

1. **tree 型清点失效**：`export_kv_project_inventory` 读 `WsTreeEnv.xml`，
   Nano 工程里该文件不存在 → `tree.node_count=0`、`program_modules=[]`、
   `topology.ethercat / ethernet_ip / motion` 全部 `not_found`。**不能据此判断"工程是空的"**。
2. **MNM 导出卡住**：`export_kv_project_text_snapshot.ps1` 在 `export_mnm` 步骤
   （`export_mnm_browse_default_folder_guarded.ps1`）启动后 **30+ 分钟无进展**，
   临时导出目录没有产出任何 `.mnm`；只能终止。症状与已知 `KV_MNM_EXPORT_NO_FILES` 同类。
3. 结论：**Nano 工程目前做不了文本快照**。要读内容只有两条路：
   - KV STUDIO 里逐程序手动导出 MNM（或 Ctrl+A/Ctrl+C 复制梯形图文本），
   - 或在 KV STUDIO 里直接看（本样本 Main 是纯梯形图）。

## 3. 机型能力提醒

Nano（KV-N14/N24/N40/N60/NC32T）只支持**梯形图 + KV 脚本**，不支持 ST/FBD。
详见 `keyence-plc-programmer/references/keyence-basics-and-pitfalls.md` §12。

## 4. 下一步建议（未做）

- 给 `export_kv_project_inventory.ps1` 增加"Nano 分支"：无 `WsTreeEnv.xml` 时用 `.mod` 文件名 + `CpuMb2.inf` 推断 CPU/程序列表，并把 `asset_status` 标成 `partial(nano_layout)` 而不是 `not_found`。
- `export_mnm_browse_default_folder_guarded.ps1` 需要查清 Nano 菜单差异（KV-NC32 的导出菜单项/快捷键是否不同），否则 MNM 导出永远超时。
