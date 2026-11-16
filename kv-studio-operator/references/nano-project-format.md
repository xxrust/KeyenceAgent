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
## 7. 编译实测（2026-11-16，KV-NC32 / 纯48）

**结论：Nano 工程可直接用 `compile_kv_project.ps1` 编译，无需改动。**

```
compile_kv_project.ps1 -ProjectPath C:\kvrun\nano\纯48\纯48.kpr -OutDir ...\compile2
→ exit=0   转换成功。   总步数：879/32768（总指令数: 782）
```

注意：编译前**必须**让 KVS 的进程命令行绑定到同一个 `.kpr` 路径，否则会报
`KV_COMPILE_PROJECT_PROCESS_NOT_FOUND`（本次第一次失败就是这个原因：开着的实例指向
`C:\Users\Administrator\Downloads\纯48\纯48.kpr`，而命令传的是 `C:\kvrun\nano\纯48\纯48.kpr`）。
两个路径内容相同也不行——绑定是**按路径**的。

顺带观察：本机同时装有 KVS11（`H:\Keyence\KVS11`）与 KVS12（`H:\Keyence\KVS12`），Nano 工程在
KVS11 里也能打开编译；`compile_kv_project.ps1` 走的是当前绑定实例，不挑版本。
## 8. 能力矩阵与待办（2026-11-16 汇总）

| 能力 | Nano 状态 | 证据 / 阻塞点 |
|---|---|---|
| 助记符导出（MNM） | ✅ 打通 | 9 个 `.mnm`，`ok=true`；修了"默认文件夹不在 `-ExportDir`" |
| 编译 | ✅ 打通（零改动） | `转换成功。` 879 步 / 782 指令；**绑定按路径**，路径不同会 `KV_COMPILE_PROJECT_PROCESS_NOT_FOUND` |
| 软元件注释导出 | ✅ 打通 | Nano CSV 只 5 列，按"无 `WsTreeEnv.xml` 时最小 5 列"放行 |
| 软元件注释导入 | ❌ 先跳过 | 导入器要求 ≥9 列且按"第 3..10 列=8 个注释区"定位；Nano 只有 1 个注释区，需重做列→注释区映射 |
| 助记符导入（MNM） | ❌ 先跳过 | Nano `.mnm` 是 **UTF-8 无 BOM**、头 `DEVICE:128`、含 `;SCRIPT_TYPE:`；现导入器按 `DEVICE:59` + UTF-16 |
| 工程清点（inventory） | ⚠️ 待修 | 无 `WsTreeEnv.xml` → `tree.node_count=0`、`program_modules=[]`；需用 `.mod` 文件名 + `CpuMb2.inf` 推断 |
| 工程文本快照 | ⚠️ 依赖清点 | 清点修好后可通；当前 `inventory` 阶段"成功"但内容为空，属误判 |

**两个导入项统一讨论后再决定**（都要改编码/设备号/注释区映射，属于"难度较大"）。

清点的 Nano 分支设计（未实现）：遍历工程目录 `*.mod`（`Main/IO测试/正向移动/…`）作为模块名，`module_type=0`；
CPU 用 `CpuMb2.inf` 或 KVS 标题 `[编辑器: KV-NC32]`；`asset_status` 标 `partial(nano_layout)` 而不是 `not_found`，
避免下游把"没有树"当成"工程为空"。
## 9. 快照链路现状与已定位的阻塞点（2026-11-16 连续实测）

Nano 工程跑 `export_kv_project_text_snapshot.ps1` 时，逐阶段把阻塞点一个个暴露出来，按顺序修过：

| # | 阻塞现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | `mnm export` 卡 30 分钟无输出 | 采样日志与 runner 日志是两份文件，误判卡点 | 认准 runner 自己写的那份日志 |
| 2 | 导出成功却 `KV_MNM_EXPORT_NO_FILES` | KVS 把 `.mnm` 写进"上次使用的文件夹"，不是 `-ExportDir` | 新增恢复扫描（含 `KV_MNM_RECOVERY_ROOTS`） |
| 3 | `选择注释类型` 被跳过 | 8 秒探测窗口内该对话框可能还没弹出（临时副本上更慢） | 等待 8 s → 30 s |
| 4 | `KV_COMMENTS_TARGET_EXISTS` | 源工程里残留上一次的 `device_comments.csv`，被复制进每个临时副本 | 目标早于本次运行则自动删除 |
| 5 | `KV_COMMENTS_ARTIFACT_MISSING` | 导出文件名是 `device_comments.csv`，恢复扫描只匹配 `KV_DEVICE_COMMENTS_*.CSV` | 匹配放宽为 `*.csv` |
| 6 | 点击"保存"后永久挂起（20 分钟） | 弹出 **`确认另存为`** 覆盖确认框，脚本未处理 | **未修**：需在保存后增加该对话框处理（点 是/确定） |

当前阶段状态：`inventory_initial` ✅、`mnm_export` ✅、`export_device_comments` ❌（卡在第 6 项）。

**下一处代码改动**：在 `export_device_comments_guarded.ps1` 点击"保存(&S)"之后，增加与 MNM 导出同款的后处理循环——
识别标题 `确认另存为`（以及 `是否覆盖` 一类），点 `是(Y)` / `确定`，再继续等待产物出现。
## 10. 助记符导入（MNM）实测：已被 KV STUDIO 自身拒绝（2026-11-16）

导入器侧的两处 Nano 差异已修（`AssertMnmChineseEncoding`）：

1. **编码**：Nano 的 `.mnm` 是 **UTF-8 无 BOM**（KV-X 是 UTF-16LE+BOM）；旧逻辑按 ANSI 解码会毁掉中文，
   现在检测到多字节内容且严格 UTF-8 可解时按 UTF-8 读取；
2. **设备号**：允许 `DEVICE:128`（KV-NC32）；原来只接受 60/63/59。

然后在 Nano 工程副本上实跑导入 `Main.mnm`（`-DeleteExistingModuleBeforeImport -SaveAfterImport`）：

```
import exit=1  14.6s
KV STUDIO 弹窗：
  读取助记符列表失败。可能是以下原因。
    /包含非法助记符字符串。
    /PLC 的机型不同。
    /包含 ST/脚本、压缩指令。
    /选项设定的表示方式 (XYM 等) 与助记符表制作时不同。
    /超过最大行数。
```

**结论：失败发生在 KV STUDIO 读取阶段，不是我们的解析器**。原因很可能是 Nano 导出的文件带
`;SCRIPT_TYPE:` 头、或该菜单路径不接受 Nano 的助记符列表格式（与 KV-X 的"读取"入口不同）。

因此 **MNM 导入对 Nano 目前不可用**；继续做需要先确定 KV STUDIO 里"向 Nano 工程读入助记符"的正确入口
（可能是脚本程序专用的读入，而不是 `文件→助记符列表→读取`）。按约定归入"难度较大，先跳过"。
### 10.1 导入尝试矩阵（2026-11-16，全部失败）

| # | 文件形态 | 目标工程 | 结果 |
|---|---|---|---|
| 1 | 原样 Nano 导出（UTF-8 无 BOM，`DEVICE:128`，含 `;SCRIPT_TYPE:`） | Nano 副本 | `读取助记符列表失败`（KV 弹窗） |
| 2 | 去掉 `;SCRIPT_TYPE:` 行 | Nano 副本 | 同样失败 |
| 3 | 转 UTF-16LE+BOM，保留 `DEVICE:128` | Nano 副本 | 同样失败 |
| 4 | 转 UTF-16LE+BOM，`DEVICE:60` / UTF-8 `DEVICE:60` | Nano 副本 | 菜单解析失败（KVS 残留脏状态，未取得读数结论） |

`H:\Keyence\KVS11` 与 `KVS12` 的 `Kvs.exe` 版本都是 **12.41.0.0**，排除版本不一致。

结论：**编码与 DEVICE 号都不是原因**；KV STUDIO 的"助记符列表读取"入口拒绝该文件，很可能因为 Nano 的程序体是
脚本/梯形混合（`;SCRIPT_TYPE:`）或者该入口只面向脚本程序。继续需要先在 KV STUDIO 里手工确认
"向 Nano 工程读入助记符"的正确操作路径——这属于人工 UI 探索，先跳过。
## 11. 「保存助记符表失败」——两个工程的导出都卡在这里（2026-11-16）

导出流程的对话框都能点过去，但 KV STUDIO 随后弹出：

```
KV STUDIO | 确定 | 保存助记符表失败。
```

KV-X（台州 v10）与 Nano（纯48）都会出现，因此**不是 Nano 特有问题**，而是助记符导出的写盘环节失败。

已排除：

- 输出文件夹未选择：对话框是 shell 树（无路径输入框），原来直接点确定；现在会先选中 `下载/文档/桌面` 节点再确定，
  日志确认 `selected mnemonic output folder node: 下载`，仍然报同一错误；
- 运行窗口/焦点：Alt+F、R、S 与各对话框点击都有成功日志；
- 版本：KVS11 与 KVS12 的 `Kvs.exe` 均为 12.41.0.0。

下一步排查方向（未做）：确认导出是"导出当前活动程序"还是"全部程序"、当前活动标签是否影响、以及工程是否处于需要先编译/保存的状态。
### 11.1 根因确认：含 ST/脚本程序的工程无法导出助记符表（2026-11-16）

| 工程 | 内容 | 助记符导出结果 |
|---|---|---|
| `KVX样例程序_v100`（KV-X520） | **纯梯形图** | **`ok=true`，64 个 `.mnm`，32 秒**（从 `Downloads` 自动回收成功） |
| 台州 v10（KV-X310） | 含 **ST 程序**（`ST02_三轴定位` 等）+ 手工双击同路径复现 | **`保存助记符表失败。`** |
| 纯48（KV-NC32） | 纯梯形图 | 成功（9 个 `.mnm`） |

结论：**"保存助记符表失败" 是 KV STUDIO 对含 ST/脚本程序的工程的限制**，不是我们的自动化缺陷
（手工操作同样失败，纯梯形工程同样脚本成功）。这也解释了此前会话里"MNM 再导出持续失败"的现象：
当时导出的都是含 ST 的台州工程。

对快照的影响：含 ST 的 KV-X 工程，`mnm` 阶段**永远不可能通过**；编排计划时应把该阶段视为
"该工程不支持"，在 `missing_capabilities` 里明确记 `mnm_unsupported_st_program`，而不是当作偶发失败反复重试。
### 10.2 决定性证据：**手工操作同样失败**（2026-11-16 20:20）

在 KV STUDIO 里对 `纯48`（KV-NC32）手工执行：

```
文件(F) → 助记符列表(R) → 读取(R)
→ 打开对话框，文件类型自动为「助记符文件 (*.mnn)」，查找范围=纯48
→ 输入 C:\kvrun\nano\export_try3\mnm\Main.mnm（同一工程刚导出的文件）
→ 确定
```

KV STUDIO 直接弹出与自动化完全相同的信息框：

```
读取助记符列表失败。可能是以下原因。
  /包含非法助记符字符串。 /PLC 的机型不同。 /包含 ST/脚本、压缩指令。
  /选项设定的表示方式 (XYM 等) 与助记符表制作时不同。 /超过最大行数。
```

**结论：KV STUDIO 本身拒绝把 Nano 工程导出的助记符列表读回 Nano 工程**，与本仓库的导入器无关
（编码、注释、DEVICE 号、UTF-16、UTF-8 五种变体已全部排除）。Nano 的助记符导入在本版本
（KVS 12.41.0.0）上**不可用**，除非基恩士另有专用导入入口/版本。
## 12. Nano 的程序导入入口是「文件 → 导入」，不是「助记符列表 → 读取」（2026-11-17 实测）

`文件(F)` 下有独立的 **导入(I)** 子菜单：

| 子项 | 文件类型 | 用途 |
|---|---|---|
| **导入程序(M)...** | `KVS 程序文件 (*.mod; *.mcr)` | 跨工程导入程序本体（带「模块信息」面板与「导入 CPU 定位信息」选项）|
| 导入注释/标号(C)... | `KVS 注释文件 (*.cmx)` | 导入注释 / 标号 |
| 导入日志信息(L) / 导入软元件初始值(D) / 导入 CPU 设定参数(P) | 各自格式 | 其它 |

实测（`纯48` 复制为 `imp_A` / `imp_B` 两个工程）：

1. `文件 → 导入程序` 选**本工程**的 `Main.mod` → KV 回答「导入文件是当前打开项目的文件。」；
2. 在 `imp_B` 里选 `imp_A\Main.mod` → 弹「打开的项目有同名的程序，或名称不对。」，可选
   `以其它名称导入` / `覆盖`；选前者并把名字改为 `MainImp` → **「导入完成。」**，工程树出现 `MAINIMP`。

结论：**Nano 支持程序导入（`.mod`/`.mcr`，跨工程）**；`文件 → 助记符列表 → 读取` 对 Nano 的 `.mnm`
仍然失败（新建空程序后重试同样失败），说明 Nano 不走助记符列表通道。
## 13. Nano 程序导入已自动化（`import_nano_program_win32.ps1`，2026-11-17 跑通）

`文件 → 导入(I) → 导入程序(M)...` 的完整自动化链路（`ok=true`，工程树断言通过）：

1. 清残留 `KV STUDIO` 提示框（否则菜单键被吞）；
2. `Alt+F → I → Enter` 打开「导入程序」；
3. 该对话框的**文件名框是 Win32 `Edit`(id=1148)**，UIA 看不到；键盘输入路径后回车（`WM_SETTEXT` 跨进程无效，必须用键盘）；
4. 同名弹窗（普通 Win32 对话框）控件：`Static id=1652` 消息、`Edit id=1010` 名字、`Button id=1058 以其它名称导入`、`id=1653 覆盖`、`id=1 OK`、`id=2 不导入`；
   - **`BM_CLICK` 点不中单选钮，必须 `BM_SETCHECK(0xF1,1)`** 选中「覆盖」，再 `BM_CLICK` OK；
   - 改名文本框写入跨进程无效，`-Overwrite` 是可靠路径；
5. 完成弹窗（`Static` 文本为 `导入完成。`）→ 点 OK。

限制：`.mod` 的**文件名必须与内部程序名一致**（改成 ASCII 副本会被判「不正确的文件」）；同工程文件会被拒（「导入文件是当前打开项目的文件。」）。