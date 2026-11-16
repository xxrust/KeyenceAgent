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
## 5. 助记符导出实测（2026-11-16，KV-NC32 / 纯48）

**结论：Nano 用同一套 `Alt+F → 助记符列表(R) → 保存(S)` 可以导出，导出器只差两处。**

实测命令（有界 90s）：

```
export_mnm_browse_default_folder_guarded.ps1 -ProjectPath 纯48.kpr -ExportDir <空目录> -OutDir <日志目录> -TimeoutSeconds 90
```

日志显示全部步骤成功：

```
mnm export Alt+F → mnm export mnemonic R → mnm export save S
click OK on export option dialog title=选择注释类型
confirm current browse-folder selection
click OK on browse folder default dialog title=浏览文件夹
click post-export dialog button (KV STUDIO) ×2
```

产物：**9 个 `.mnm` 成功生成**，但落在 **KVS 记忆的默认文件夹**（本次是 `C:\Users\Administrator\Downloads\纯48\`），
不在 `-ExportDir`，于是结果被判 `KV_MNM_EXPORT_NO_FILES`。

→ 修法（未实现）：点 OK 前把目标文件夹设成 `ExportDir`，或点 OK 后读取对话框选中的路径/扫描默认文件夹，
把时间窗内的新 `.mnm` 移入 `ExportDir`。

## 6. Nano 的 MNM 文本格式（与 KV-X 不同）

| 项 | KV-X（KV-X310） | KV Nano（KV-NC32） |
|---|---|---|
| 文件编码 | UTF-16 LE + BOM | **UTF-8（无 BOM）**，`\r\n` 换行 |
| 头行 | `DEVICE:59` | **`DEVICE:128`** |
| 额外头字段 | `;MODULE:` / `;MODULE_TYPE:` | 另有 **`;SCRIPT_TYPE:`** |
| 程序体 | 梯形图为主，可含 ST | 只有梯形图 / KV 脚本 |

实测样本：`C:\kvrun\nano\export_try2\mnm\Main.mnm`（前 60 字节 = `DEVICE:128\r\n;MODULE:Main\r\n;MODULE_TYPE:0\r\n;SCRIPT_TYPE:\r\n;cm8…`），
9 个程序全部导出成功。

→ 影响 `import_mnm_guarded.ps1`：若以后要往 Nano 导入，必须支持 **`DEVICE:128` + UTF-8(无 BOM)**；
当前实现按 `DEVICE:59` + UTF-16 处理，直接导入会失败。**暂列"难度较大，先跳过"**。