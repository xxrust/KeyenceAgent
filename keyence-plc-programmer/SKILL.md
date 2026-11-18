---
name: keyence-plc-programmer
description: 审查、编写、修改和复刻 KEYENCE PLC 程序（梯形图、ST、KV 脚本、变量和 FB）。先用现场与工程证据建立项目本体，再设计和验证行为变更。KEYENCE 专有语义查 Wiki，桌面操作交给 kv-studio-operator。
---

# KEYENCE PLC 编程

本 skill 负责程序内容和工程语义。KV STUDIO 桌面操作只使用
`kv-studio-operator` 的公开 workflow；不要使用旧 kvtool 或历史 UI 脚本。
KEYENCE 专有语法、指令/FB 调用、设备映射和模块行为，通过
`kv-studio-kb-programming` 查询本地 Wiki v3m 或依据当前项目导出证据确认。

> **机型硬约束**：KV **Nano** 系列只支持**梯形图 + KV 脚本**，**不支持 ST / FBD**。目标机型是 Nano 时不要规划 ST 模块或 ST 代码，只能出梯形图 / 脚本（依据与移植注意事项见 `references/keyence-basics-and-pitfalls.md` §12）。
## 开工前必读：基础与反直觉清单

读陌生 KEYENCE 工程、或准备改程序/变量/注释之前，先扫一遍
[keyence-basics-and-pitfalls.md](references/keyence-basics-and-pitfalls.md)。
它只收"大模型最容易按其它品牌习惯搞错"的条目，每条都标了依据类型（手册 / 实测 / 仓库）。
最常踩的六条：

- **没有 X/Y**：单元 I/O 在 **R 区**（输入继电器/输出继电器）。搜不到 `LD X` 不代表这台机没有 IO。
- **`ANP` 是串联上升沿接点（OFF→ON），`ANF` 才是串联下降沿接点（ON→OFF）**。不要把 `ANP` 中的 `N` 当成取反或下降沿；完整对应及手册依据见必读清单 §3。
- MNM 的分号行可能承载 ST、KV 脚本或注释。解析时按模块格式和脚本范围判定。
- **`.kpr` 是压缩/加密二进制**，不能离线解析；必须先在 KV STUDIO 里导出再分析。
- **注释 / 变量 / 变量注释是三套机制**，互不替代（见下节与本文第 2 节）。
- 脚本层面：含非 ASCII 的 `.ps1` 必须带 UTF-8 BOM，`.bat` 必须纯 ASCII。

## 先理解设备，再设计程序

首次接手、审核或修改实际工程，以及为实际设备新增控制功能时，按 [项目本体与行为验证](references/project-model.md) 建立与任务范围匹配的工程认知。先查器件、端子、I/O 和有效电平，再将工艺、扫描顺序、上位机握手及安全回路连成可追溯的关系。审查可以停在证据与结论。行为修改须在编写替代逻辑前明确当前行为、目标行为和验收条件。

现有快照提供程序和配置证据。接线、外部写入和安全功能需要各自的资料。记录会影响变更的未知项并暂缓依赖它的改动，继续审查或处理证据独立的部分。仅修改注释或单个局部逻辑时，追踪对应信号及受影响的路径即可。

## KV Nano 编程与官方范例

写、改或移植 Nano 程序时，先读 [KV Nano 编程摘要](references/nano-programming.md)，核对 I/O、首扫、扫描边沿、定时器、数据宽度、定位和串口握手。

查具体梯形图、KV 脚本或宏时，按功能和 CPU 选取厂商示例，结合索引中的模块导航阅读。范例覆盖 14、24、40、60 点型，移植到其他型号前核对手册中的 I/O 分配和指令适用范围。 [KV Nano 官方范例索引](references/nano-official-samples/README.md)

## 变量表 vs 软元件注释：先判断项目现状，再决定改法

"让程序可读"有三条路：**设备绑定变量**（程序里显示变量名）、**软元件注释**（`.cm1`，设备旁挂注释）、
**变量注释**（变量表的 comment 列）。改一个既有工程时，先判断它属于哪一类，再选主路线：

| 项目形态 | 判断依据 | 默认做法 |
|---|---|---|
| **新建项目或独立新模块** | 目标 CPU 与项目约定允许使用命名符号 | 按机型使用变量或 Nano 标号。只为经证实的现场接口绑定设备，内部状态优先使用合适作用域的符号 |
| **既有项目：大量裸地址 + 软元件注释** | 程序体里满是 `MR1000`、`DM2000`，变量表里几乎没有用户变量；注释表里有手写注释 | **以补软元件注释为主**。不要为了可读性把整段程序改成变量名——那会动到 MNM 显示形式，等于重写程序 |
| **既有项目：已大量命名变量** | 程序体里以变量名为主，变量表有较完整的用户变量 | **沿用变量表**：新点位建变量，说明写变量 `comment`；只有裸地址补软元件注释 |

- 从同一批程序体统计命名符号和裸设备地址的引用比例。对支持变量表的工程，可用
  `text/comments/usage.tsv` 辅助识别裸地址，以变量声明解析命名引用。Nano 以 MNM 和标号表为依据。
  已有规范时沿用项目约定，混用时按本次涉及的模块判断。
- 只在"注释优先"的项目里做**增量变量化**：一次一个工位/一个 FB 实例，改完必须编译 + 回读，
  不要批量把裸地址替换成变量名。
- 仅修改软元件注释时，导出 MNM 与改前逐字节比对，应当完全一致（`.cm1` 变了、程序体没变）。
  此检查只适用于注释修改，不限制用户要求的程序逻辑优化。

Nano 标号和系统点保护按 operator 的 [Nano 接口契约](../kv-studio-operator/references/nano-program-interface.md) 执行。完整逻辑修改使用 `nano_program_plan`，准备标号、源码、旧内容预期与保存重开后的回读预期。

## 注释以程序作者和工程师的身份编写

注释可留空。标号或代码已清楚表达的含义不再解释，例如“准备检测”无需补写“中断置位”或扩写成一段请求协议。

只在有助于理解设计时补充简短注释，例如必要的单位、限制或不直观的工艺原因；不要求每个位都说明产生、消费和复位过程。“未见置位路径”等审查发现放入报告，不能填进工程注释，也不能编造设计意图来代替未知信息。

写入的说明须符合实际回路与指令依据；`ANP 输入` 是输入上升沿，不据此推断工件进入或离开。编译成功和 TSV 回读一致不证明注释语义正确。

## 快速 ST 路径

纯语法、通用算法或独立 ST 片段按下表选参考，给出可执行主体与需要登记的接口。KEYENCE 专有语义按 `kv-studio-kb-programming` 查证。即使交付物只有代码，只要指定了现有工程或实际设备行为，仍按受影响接口建立项目本体。

| 任务内容 | 按需参考 |
| --- | --- |
| 控制流、运算、统计、几何 | [控制流与数值](references/st/control-flow-and-numeric.md) |
| 数组、FB、定时器、扫描状态 | [数组、FB 与扫描状态](references/st/arrays-fb-and-scan-state.md) |
| 字符串、时间、存储、通信、运动 | [字符串、时间与设备接口](references/st/strings-time-and-device-interfaces.md) |

用户要求读取/修改现有工程、生成导入文件或真实编译时，再按下方编辑流程进入工程路径；“写一段 ST”本身不触发该流程。

## 一个完整程序需要什么

程序体、声明、调用实例和依赖分别存在。MNM 主要承载程序模块；
导入程序体不会自动证明变量表或 FB 自变量完整。

先明确 CPU、任务/模块、输入输出、状态变化和验收条件，再按修改范围准备：

- 程序体：梯形图助记符或 ST 可执行语句。
- 声明：全局变量、每个程序/FB 的局部变量、FB 自变量。
- 依赖：用户数据类型、被调用 FB/函数、官方库。
- 集成：FB 实例、调用方实参、真实设备和单元/轴映射。
- 验证：相关表格读回、转换/编译结果，以及用户要求的行为检查。

只修改一张表时无需伪造完整 MVP。学习完整项目形态时可使用 operator
的 scaffold 示例，但保留实际项目的结构和验收范围。

## 编辑流程

1. 识别目标工程、CPU 和影响范围。取得与基线版本一致的证据。跨模块、复刻或全面审核按下节选择快照，窄范围可读取相关程序、声明和配置。
2. 建立项目本体并追踪受影响的读写方、间接引用和扫描顺序。设计前记录每项变更的触发、改前／改后行为、证据和验收用例，针对缺失资料缩小可执行范围。
3. 准备可审查的源码和声明。按依赖顺序调用公开 operator workflow，类型先于引用它的声明和模块。用回执提供的编译错误修正源文件后重试。
4. 将编译、保存重开回读和适用的行为检查绑定到最终交付版本。报告已取得的现场证据及待核事项。仅提供代码时按实际完成的检查报告。

从零建工程时，先用 operator 的 `get_kv_capabilities.ps1 -Capability create_project`
读取公开入口及 `regression_scenarios`，查看匹配的 README 和场景参数后创建目标 CPU 工程。
`sample_copy` 是已有样例副本，不能当作空白创建的依据；`new_project` 才覆盖实际新建。
接口失败时先核对标准契约和本次证据，不把尚未完成的算法/ST 集成与已有工程创建能力混为一谈。
测试契约用于学习受支持的调用方式，算法和声明仍按本次需求独立生成。

新增完整程序或 FB 时，准备程序体、声明、目标树路径和 Wiki 证据。支持该路径的机型按
[complete-module.md](references/complete-module.md) 使用 `create_kv_complete_module` 写入 BOOL 梯形图，
或按 operator 的 `references/st-programs.md` 使用 `create_kv_st_module` 写入数值 ST。Nano 的完整逻辑使用 `nano_program_plan`。单项修改走对应窄接口。

复刻整个项目才需要完整资产清单和比较，见 [reproduction-gate.md](references/reproduction-gate.md)。
不要删减逻辑、变量或硬件要求来获得通过。官方 FB 保持来源、名称和行为；
用户 FB 和业务逻辑按源文件重建。

## 从语义快照理解项目

KV-NC32 优先使用 operator 的 `nano_project_snapshot`。从 `snapshot/project/modules.json` 读扫描顺序，
从 `program_N/` 读 MNM 与局部标号，并结合全局标号、单元配置及六页 CPU 定位参数。
以 [Nano 快照](../kv-studio-operator/references/nano-snapshot.md) 的实际读取范围为准。

支持通用快照的机型使用 `read_only_project_text_snapshot`，从 `snapshot/project/` 阅读：

- `功能块/<项目树分组>/<FB>/`：`body.mnm`、`arguments.tsv`、`locals.tsv`、`entity.json`。
- `程序/<模块类别>/<模块>/`：`body.mnm`、`locals.tsv`、`entity.json`。
- `配置/单元`、`配置/EtherCAT`、`配置/全局变量` 和 `类型/`：全局依赖。
- `_index/entities.jsonl`：Agent 检索入口；`_index/restore_plan.json`：依赖和恢复顺序。

先读根 manifest 与实体状态，再据 `entity.json.tree_path`、`category`、`artifacts`、
`status` 和 `restore` 判断归属及完整性。目录位置用于人类导航，`entity.json` 用于自动化；
二者不一致时不得猜测，转入证据核查。`text/` 是原子文本证据，`raw/` 是运行审计证据。
任何 `semantic_warnings` 或实体的 `failed`、`missing`、`partial`、`unresolved` 都必须在设计、
恢复和报告中显式处理，不能因顶层快照为 `ready` 就视为内容完整。

## MNM 与声明

- 普通用户程序为 `;MODULE_TYPE:0`，用户 FB 为 `;MODULE_TYPE:2`。
- **DEVICE 码与编码按目标 CPU 系列分支**，不要跨系列套用。实测（同一台机器、KV STUDIO 12G 导出）：

  | 目标项目 | 导出 MNM 首行 | 编码 | ST 导入验证状态 |
  | --- | --- | --- | --- |
  | KV-X520（KVX 样例） | `DEVICE:60` | UTF-16LE + BOM | 已实测导入成功（`-DeviceCode 60 -OutputEncoding Utf16LE`） |
  | KV-X310（台州检测机） | `DEVICE:59`（工程自身导出） | UTF-16LE + BOM | 已实测：把 `DEVICE` 改成 `60` 导入 + 登记变量后**编译通过** |

  程序体导入通过 ≠ 能编译。实测（KV-X310 工程副本，导入改写后的 Main）补两条硬要求：
  - **FB 调用要另外登记实例变量**：程序体里的 `FBEXEC/FBEAND <FB名> <实例名>` 必须在"局部变量"里声明
    `scope=local, owner_program=<模块>, name=<实例名>, data_type=<FB名>`，否则报
    `[错误214] 梯形图中存在未注册变量`；导出程序体本身不含这些声明。
  - **改写副本与原模块共存时不得复用定时器编号**：同一 `TMR` 号出现在两个模块会报
    `[错误61] 同一定时器编号在多个 TMR/TMH/TMS/TMU 指令中使用`；正式切换时删除原模块，或把副本的
    定时器移到专用号段。
  - **比较触点不要拿 32 位字当操作数**：`AND= DM12118.L #0` 这类写法会被 KV 的助记符读取器直接拒绝，
    导入时报"读取助记符列表失败"（实测隔离：同一导出体不改动可导入，只加这一行就失败）。需要"某标志为
    真/假"时，让 ST 盒把结论写成一个位（例如心跳 ST 里同时置 `DM12119`=在线），ladder 侧用朴素位触点
    `AND DM12119.0`。
  - **`???` 是可导入的**：导出器用 `???` 表示未指定的 FB 实参，实测原样回导可编译，不需要先补齐。
  - 编译路由要求**目标工程已打开**（它只绑定现成的 `Kvs.exe` 进程，不自己启动），所以顺序是
    导入 → 声明变量 → 编译，中途不要把 KVS 关掉；两个同名工程同时在跑会报
    `KV_COMPILE_PROJECT_PROCESS_AMBIGUOUS`。

  规则：**DEVICE 码取目标工程自己的导出证据**（先导出一次目标程序体读首行），不要按本表直接假设；
  含中文的 MNM 一律用目标编码写，BOOLD 示例的 `DEVICE:63`/ANSI 组合不要用于 ST 路线。
  用 `scripts/new_kv_st_mnm.ps1 -DeviceCode <证据值> -OutputEncoding Utf16LE` 从 UTF-8 ST 封装，
  导出读回用同脚本 `-ExportPath` 精确比较全部 ST 行。
- ST 程序体只写 KV STUDIO 接受的可执行语句。变量声明位于编辑器变量表，
  不把通用 IEC 声明块直接塞进程序体。
- **读取 MNM 时按导出编码解码**。KV-NC32 样本的无 BOM 导出用 Windows-936。对 UTF-16LE + BOM（首两字节 `FF FE`）的导出，PowerShell 自己的 cmdlet
  （`Get-Content`/`Select-String`/`[IO.File]::ReadAllLines`）因 BOM 检测，**不写 `-Encoding` 也能正确读**
  （实测 5.1.26100：ascii 与中文命中都与显式 `-Encoding Unicode` 一致）；**真正会"假空"的是非 PowerShell
  路径**——`findstr` 会报 "input file … is in Unicode format" 且两种查询都 0 命中，Python 默认 `open()`
  直接 `UnicodeDecodeError`（gbk）。用这些工具时显式指定 UTF-16，或读快照提供的 `text\mnm_utf8\`
  （UTF-8 无 BOM，仅供阅读；权威、可导入的副本始终是 `text\mnm\`）。
- 普通 ST 问答只列出需要登记的变量，不因未要求工程交付而补 MNM 封装、TSV 或固定 contract。
- 数值 ST/数组/算法 FB 按 operator 的 `references/st-programs.md` 组合接口。
  官方域类型 ST 导出为 `AREA_ST`，不要求另建一种模块语言；能导出不证明能反向导入。
  使用描述性标识符并先跑声明预检；`B`、`C`、`T`、`V` 等为保留字，`C0` 等与软元件名冲突
  （STUse.pdf p302-304）。完整源码读回不能丢弃 MNM 中以分号开头的 ST 代码行。
- 名称、作用域、数据类型、数组尺寸、初值、保持属性和设备绑定保持源语义。
  当前接口未验证的字段必须明确说明，不能默认为已还原。
- TSV 的实际粘贴列和读回边界以 operator 的 variable-editor.md 及校验脚本为准；
  不在两个 skill 中分别维护 UI schema。

## 重构时评估官方实现和 FB 复用

建立项目本体后，涉及替代指令、官方 FB 或封装时读 [FB 重构判定](references/fb-first-refactor.md)。优先用目标 CPU、单元和项目版本支持且满足行为要求的官方实现。核对请求、仲裁、互锁、完成、停止和故障处理，再决定替换范围。Nano 按机型支持的原生指令与 KV 脚本评估。

## 可复用 FB

调用方拥有真实设备映射、全局集成变量、轴/模块绑定和 FB 实例。
FB 内部拥有可复用逻辑、显式自变量和局部状态，不被业务全局变量绑定。

写程序体前准备：

- 自变量：name、direction、data_type、调用方绑定、comment。
- 局部变量：name、data_type、initial_value、retain、comment。
- 实例：caller_program、instance_name、FB_type。

方向包含 `IN`、`OUT`、`IN-OUT`、`UNIT`。`OUT` 和 `IN-OUT`
不能绑定常数。外部交互用自变量，内部状态用局部变量。
固定业务软元件放在调用方；确需内部特殊软元件时记录设备、理由和证据。

依据：`KvsHARD8000.pdf#p225-227`（自变量方向）、`p240-243` /
`KVSREF.pdf#p194-203`（调用绑定）、`KVSHARDX3H.pdf#p100-101`
（用户局部变量作用域和 BOOL 类型；Wiki chunk `pdf::KVSHARDX3H::chunk-039`）、
`ScriptUse.pdf#p96-98`（FB 重用）。`KVSHARDX3H.pdf#p422-423` 讲系统局部变量，
不作为用户声明格式的依据。

导入或声称用户 FB 有效前执行非 UI 检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-root>\scripts\validate_fb_reuse_guard.ps1 -Path <mnm-file-or-folder>
```

特殊设备例外通过 `-ContractPath` 输入 JSON：

```json
{"allowed_devices":[{"module":"FB_ModuleName","device":"CR2012","reason":"documented flag required by this contract","evidence":"FBCALL_FBSTRT.htm#运算标志"}]}
```

`KV_FB_REUSE_DEVICE_LEAK` 表示设备泄漏，需要改成自变量/局部状态或提供真实设备契约。

## 工作产物与报告

在任务目录分别保存 `source_snapshot`、`work`、`validation`；完整项目快照的规范内容位于
`source_snapshot/.../snapshot/project`，代码来源固定为
已安装 skill。保留原始快照和阶段 commit；历史输出中的脚本不作为执行入口。

可复用非 UI 工具包括 `init_project_snapshot_workspace.ps1`、
`validate_fb_reuse_guard.ps1` 和 `new_mnm_smoke.ps1`。
KV STUDIO 可执行文件解析仍由 `resolve_kvstudio_local.ps1` 提供给 operator；
这不构成另一套 UI 路线。判断本机是否装了 KV STUDIO 先跑这个脚本（或 operator 的
`get_kvstudio_install.ps1 -Probe`），不要自己列几个目录去猜。

该脚本按 显式参数 → 结果缓存 → operator 配置 `kvs_exe` → 注册表（App Paths / KV STUDIO
卸载项 / KEYENCE 键）→ 开始菜单快捷方式（机器级 + 用户级）→ 搜索根（`KvsVersionPath.txt`、
`KVS<版本>` 布局、限定深度扫描）→ 旧版 C 盘路径 逐层查找；每一层都要求命中的对象真实存在
且文件名为 `Kvs.exe`。命中返回 JSON（`KvsExe`、`WorkingDirectory`、`Source`、`Version`、
`Cached`、`ElapsedMs`、`Checked`），全部落空才报 `KV STUDIO Kvs.exe not found` 并列出已检查项。

安装目录不在 C 盘、快捷方式缺失或被改名时，不要据此判定"未安装"：注册表层与搜索根层仍能命中，
缓存也会在命中后加速后续调用。`-SkipConfig/-SkipRegistry/-SkipStartMenu/-SkipDriveScan/-SkipCache`
与 `-SearchRoots/-ShortcutRoots` 只用于隔离验证；正式判断不要带这些开关。

报告修改范围、依据、声明/依赖完成度、当前编译结果、证据路径与剩余问题。
细小修改只报告相关内容，无需套用整项目复刻报告。
