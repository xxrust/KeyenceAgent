---
name: kv-studio-operator
description: 通过稳定 workflow 操作和快照化 KEYENCE KV STUDIO 桌面项目。用于项目创建、语义项目快照、MNM 导入导出、FB 自变量与局部变量、数据类型、编译结果和单元/EtherCAT 配置；从能力清单选择接口，由脚本负责焦点、输入、验证和日志。
---

# KV STUDIO 操作

把 KV STUDIO 当作由 workflow 提供接口的编辑器。agent 准备目标、输入和预期结果，调用接口后读取本次结果；不要临时拼接键盘、窗口或剪贴板操作。

## 最小验证优先（不要为验证一步跑全流程）

完整 plan（建工程 → 结构 → 28 个模块 → 变量 → 编译 → 扫描顺序）只用于**最终验收**。
任何中间步骤先用**同一份参数**单独重放：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-root>\scripts\workflow_tools\rerun_kv_plan_step.ps1 `
  -PlanPath <plan-dir>\execution_plan.json -StepName set_variables_FB_Cylinder -OutDir <dir>\verify
```

- 单步验证只看该步的 `set_variables_result.json` / `result.json`；失败先打开
  `failure.png` 或结果里的 `failure_screenshot_path`。
- 需要复现 UI 状态时，对**同一个已打开工程**重跑该 runner，不要新建工程。
- 全流程一次 20 分钟以上，单步通常 20 秒–2 分钟；改一步验证一步。

## 写入依赖顺序（自底向上）

KV STUDIO 的编译是全局的，但 UI 写入必须按依赖顺序，**块里引用的变量必须在其它地方先定义**：

1. **数据类型（结构体/用户 DUT）**：先建；嵌套类型按成员依赖排序（标量成员在前）。
2. **FB 模块**：先导入 FB 的 MNM，再写它的自变量表和局部变量；FB 自变量用到的结构体已存在。
3. **变量定义**：程序引用的全局/局部变量所在表必须先存在；`_MC_AXIS_REF` /
   `_MC_AXIS_GROUP_REF` 等轴引用按目标工程实际配置（没有轴时 device 可先为空）。
4. **程序模块**：最后导入/写入引用这些变量和 FB 的扫描程序。MNM 导入本身不解析变量，
   但**编译前**所有被引用的变量必须已定义，否则编译报“未注册变量”。
5. **编译与扫描顺序**：全部落盘后再编译，扫描顺序用 `assert_kv_scan_order.ps1` 单独验证。

先写顶层程序、后补变量，或者跳过结构体直接写 FB 自变量，都会在粘贴/编译阶段
报“无效数据类型/未注册变量”。修改任何一步前先确认它依赖的层已经存在。

## 弹窗之后先编译（编译结果是变量问题的权威清单）

粘贴变量时若出现「粘贴数据中存在错误，已跳过部分数据粘贴。」，不要只盯着弹窗：

1. 记录并关闭弹窗（runner 已自动处理三种确认/警告框）；
2. **立即编译**（`compile_and_copy_result_bounded.ps1` + `copy_convert_result_from_tree_handle.ps1`），
   把 `compile_result_copied.txt` 交给
   `workflow_tools/parse_kv_compile_result.ps1`；
3. 用结构化输出定位问题，而不是靠猜：

```powershell
powershell -File <skill-root>\scripts\workflow_tools\parse_kv_compile_result.ps1 `
  -ResultPath <run>\artifacts\copy_result\compile_result_copied.txt -OutDir <run>\triage
```

输出 `compile_triage.json`：`state`、`errors_by_code`、`errors_by_module`、`error_symbols`、
每条错误的 `{module,line,st_line,code,symbol,message}`。

已知错误码含义（实机 2026-10-24）：

| 代码 | 含义 | 典型原因 |
|---|---|---|
| 709 | 变量编辑窗口中存在不正确的变量定义 | 粘贴后类型/分配目标被写坏（如轴引用行），该变量仍留在表里 |
| 214 | 梯形图中存在未注册变量 | 变量没写进表：局部变量未执行、或分组全局变量不在模型里 |
| 1232 | ST 里发现非法的字符串 | ST 使用的标识符未定义（同样表现为变量没写进去） |
| 602 | Pos 不在范围内 | ST 参数/点号越界 |
| 33 | 可以省略 ENDH 命令 | 仅警告 |

**经验：一个变量步骤失败会中止后续所有模块的变量写入**，所以编译里会出现大片
1232/214。先修第一个失败点，再看编译；不要用“补一点变量再试”的方式绕过。

## 模块完整性优先（控制编译噪声）

**一个模块只有“MNM 已导入 + 局部变量已写 + FB 自变量已写”才算完整**；全局变量是共享层，
要在程序模块之前整层写好。不要“先把 28 个 MNM 全部导入，再回头写变量”，否则任何一次编译
都会把每个未写完的模块都报成错误，真正的问题（例如几个轴引用）会被几千条噪声淹没。

推荐顺序（也是 plan 应有的形状）：

1. 结构体（用户 DUT）整层；
2. 全局变量整层（按组写入，见下）；
3. 逐个 FB/程序模块：导 MNM → 写局部变量 →（FB）写自变量 → 该模块标记完成；
4. 只在“已完成的模块集合”上编译检查；对未完成模块的错误视为预期噪声，不进结论；
5. 全部模块完成后做最终编译 + 扫描顺序验收。

判断“编译错误是否可信”的前置：本次编译前，被检查模块的 `locals/args` 回读必须齐全
（用 `set_variables_result.json` / `fb_snapshot_result.json`）。缺变量的模块不要纳入
错误归因。

执行器生成的每步回执可以直接汇总成完成度报告（需要在编译前跑）：

```powershell
powershell -File <skill-root>\scripts\workflow_tools\get_kv_module_completion.ps1 `
  -PlanPath <plan>\execution_plan.json -ArtifactsRoot <run>\artifacts -OutDir <run>\triage\completion
```

`module_completion.json` 给出每个模块的 `import_ok / placement_ok / fb_arguments_ok /
variables_ok / complete` 与 `reasons`；有未完成模块时退出码 41。**完成度不是 100% 时
不要依据编译结果下结论。**

编译噪声的判别口诀：**错误按模块均匀铺开 ⇒ 多半是变量没写完；集中在少数模块/符号 ⇒ 才是
该模块的真实问题**。

## 底层依赖先行（写变量之前必须回答“它凭什么存在”）

变量在 KV STUDIO 里是否成立，取决于**目标工程已有的对象**，而不是类型名是否写对：

- 自定义结构体必须已在工程里（`strCylinder` 等），成员类型递归成立；
- FB 实例类型必须已导入（用户 FB 或库 FB，如 `TON`/`MC_*`/`ModbusTCPClient_*`）；
- `_MC_AXIS_REF` / `_MC_AXIS_GROUP_REF` 及 `_MC_Axis[n]` / `_MC_AxisGroup[n]` 必须有对应**轴/轴组**（由 EtherCAT/轴配置生成，**不能靠变量粘贴创建**）；
- 写入顺序必须是：类型/轴存在 → 再写引用它们的变量。缺依赖的行**不写**，报告为 blocked。

写任何变量前先跑离线依赖规划（不碰 UI）：

```powershell
powershell -File <skill-root>\scripts\workflow_tools\plan_kv_variable_dependencies.ps1 `
  -VariablesTsv <vars.tsv> -StructureDefinitionsPath <structures.json> `
  -AxisIndexes 1,2,3 -FbTypes TON,MC_Power -OutDir <dir>\deps
```

输出 `variable_dependency_report.json`：每行 `ready/blocked`、`missing`（`missing_type:*`、`missing_axis:n`、`missing_axis_group:n`）、以及 `required_structures/required_axes/required_fb_types`。只有 `blocked_count=0` 的集合才允许进入写入步骤。

**证据标准（防止把“局部通过”说成全绿）**：说“通过”必须同时满足——目标工程完整编译 `转换结果 OK`、模块完成度 100%、扫描顺序一致。单步 runner `ok=true`、子集快照通过、结构体导入成功，都不算全绿。

## 轴变量命名（批量登录轴的坑，2026-10-25 实机）

批量登录轴会自动生成 `Axis_1..Axis_N` 全局变量，每个占用 `_MC_Axis[n]`。样例工程里的轴变量名
（`旋转轴DEMO`、`上料1拨料` 等）**不能靠变量粘贴创建**：设备已被 `Axis_N` 占用，粘贴会被判
重复分配而忽略（或留下 709 无效定义）。

已固化为脚本（2026-10-26 实机 2 轴回归通过）：

```powershell
powershell -File <skill-root>\scripts\workflow_tools\rename_kv_axes.ps1 `
  -MappingPath <轴序号<TAB>新名称.tsv> -OutDir <out>
```

脚本走“轴设定页”路径：选中树节点/双击打开该轴页 → 用 `轴No.` 与 `轴名称` 两个字段确认页面已
切到目标轴 → 改 `轴名称` → TAB 提交 → 校验树节点文字；失败逐条记入 `axis_rename_result.json`
并 exit 41。手工路径与注意点：

1. 打开“轴设定”，选中轴名称节点（如 `轴1: Axis_1`）；
2. 右键 → 按 `P`；
3. 按 `TAB`；
4. 输入新名称；
5. 按 `TAB`（焦点落到“确定”）；
6. 按 `ENTER`。

改完后轴变量名随之变化，程序里的引用才成立。**不要把“清空变量表再粘”当成改名手段**：
`-ClearGlobalRows` 会连系统轴变量一起删掉，有轴时不要用。

## 工程绑定与多 KVS 实例

多个 `Kvs.exe` 同时打开不同工程时，按命令行路径/窗口标题绑定会落到旧进程，表现为“步骤
exit=0 但工程没变”。先保证只有一个 KVS 进程，或给支持 `-CreatedProjectResultPath` 的步骤
传入创建结果。注意 `set_fb_arguments_guarded.ps1` **没有**这个参数（会报参数不存在），它只按
窗口名绑定。

## 退出码与“编译 OK”的含金量

- 不要用 `Start-Process` 的 `ExitCode` 判定成功（重定向 + `WaitForExit` 可能返回 0）；读步骤
  目录里的 `exit_code.txt`。
- 编译只看“转换结果 OK”不够，还要看总步数/模块数：**只有 2 步的 OK 是空工程**，不是通过。

## 批量轴/库对话框（WinForms，不是 #32770）

保存 EtherCAT 配置后依次可能出现（都是顶层 WinForms 窗口，按 `#32770` 扫描会漏）：

1. `EtherCAT设定完成。要批量登录轴吗？` → 是(Y)；
2. `批量登录轴` 表 → OK；
3. `轴的批量登录已经完成。` → 确定；
4. `是否进行新建轴的坐标转换设定？` → 否(N)，可勾选“之后不再启动”；
5. `已导入以下Universal Library。` → 确定。

处理方式：枚举进程所有顶层窗口，按窗口内文本匹配后点击对应按钮；不要依赖固定类名。

## 阶段顺序（当前验证过的）

```
结构体 → 轴（EtherCAT 节点 + 批量轴登录 + 改轴名）
→ 全局变量（空表写入，不覆盖、不清表）
→ 逐模块：导入 MNM → FB 自变量 → 局部变量
→ 编译（看转换结果 + 总步数）→ 完成度 100% + 扫描顺序
```

## 计划执行器（结构/模块/变量的批量写入）

原先 `C:\kvrun` 里的 `pipeline.ps1`/`vars9.ps1` 已固化为：

```powershell
powershell -File <skill-root>\scripts\workflow_tools\run_kv_execution_plan.ps1 `
  -PlanPath <execution_plan.json> -ProjectPath <project.kpr> `
  -GlobalVariablesTsv <globals.tsv> -RunRoot <out>
```

- 阶段：`structures → imports → fb_arguments → variables`（可用 `-Stages` 选择）；
- 每步用计划里的参数，自动补 `ProjectPath`/`OutDir`，从 `exit_code.txt` 取退出码；
- `variables` 阶段默认除 `set_variables_FB_Cylinder` 外都加 `SkipGlobal`，避免每模块重写全局表；
- 结果写 `plan_run_result.json`，任一步非 0 → exit 41；`-DryRun` 只打印命令，可在不碰 UI 的情况下校验计划。

## EtherNet/IP 设定读取（B00/B01… 整表）

EIP 主窗口是 MFC（`Afx` + `VSFlexGrid8L`），没有 UIA 树；但 `连接设定 - N:<设备>` 是标准
`#32770`，字段可由 UIA 读（连接名称/连接点/数据大小/RPI 等），`软元件分配设定` 的表格用
“点单元格 → Ctrl+Home → Ctrl+Shift+End → Ctrl+C”整表复制。

```powershell
powershell -File <skill-root>\scripts\workflow_tools\get_kv_eip_connection_snapshot.ps1 `
  -ConnectionTitle '连接设定' -OutDir C:\kvrun\eip\snapshots
```

输出 `<连接名>.json`（fields + assignment[] + raw_path）和 `<连接名>.tsv`，并默认关闭
`软元件分配设定`/`连接设定`。`EtherNet/IP 设定` 主窗口由调用方用“取消”关闭，读完必须让界面
只剩 KV STUDIO 主窗口。字段 AutomationId、样例实测值（NU-EP1/DL-EP1、IN_100 64/84 字、
B00/B0B0 等）见 `references/eip-settings.md`。

## 选择接口

唯一能力清单是 [scripts/script_manifest.json](scripts/script_manifest.json)。用只读查询获得实际路径、参数类型、必填参数和验证范围：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-root>\scripts\get_kv_capabilities.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-root>\scripts\get_kv_capabilities.ps1 -Capability snapshot_fb_arguments
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-root>\scripts\get_kv_capabilities.ps1 -Capability read_only_project_text_snapshot
```

确认本机 KV STUDIO 是否可用用 `-Capability detect_kvstudio_install`
（`get_kvstudio_install.ps1`，非 UI、只读；`-Probe` 只输出 `Kvs.exe` 路径并以退出码 0/1 表示有无）。
它按 缓存 → 配置 → 注册表 → 快捷方式 → 搜索根 逐层查找并校验文件真实存在，安装目录不在 C 盘
也能命中；不要用"某几个目录里没有"来判定未安装。

导出工程软元件注释表用 `-Capability snapshot_kv_device_comments`
（`export_kv_device_comments.ps1`）：以受保护的 Alt+F、K 加速键走
「文件(F) → 以 CSV/TXT 格式保存软元件注释(K)...」，校验另存为对话框的保存类型（须含 CSV）与
程序选择器（默认 `全局`），输入唯一文件名并用 `WM_GETTEXT` 读回（跨进程控件不能用 `GetWindowText` 读），
`BM_CLICK` 保存后只接受**本次运行**生成、结构合法的 CSV。注释表里型号档/系统注释占多数，
需要"他的程序用了哪些软元件"时应与 MNM 程序体交叉过滤；`.cm1` 反解只能作为后备且必须标注推断。

"程序体 ↔ 注释"对照与覆盖率用 `-Capability device_comment_coverage`
（`annotate_kv_program_with_comments.ps1`，纯非 UI 计算）：输入是上面导出的注释 CSV 与 MNM 程序体目录，
**MNM 只读不改**，join 结果单独落盘 `comments.tsv`/`usage.tsv`/`coverage.json`/`program_annotations.md`。
默认只统计用户程序体（库 FB 体另计，加 `-IncludeLibraryBodies` 才纳入）；设备键按"去前导零、保留进制"归一
（`MR013`=`MR13`、`W012`=`W12`，B/W 是十六进制），`TMR 20`、`#1`、`_MC_Axis[#1]` 不算软元件，
MNM 中以 `;` 开头的 ST 行算使用、`BOOKMARK` 标签不算。`coverage.json` 记录注释表与每个程序体的 sha256，
可据此判断报告是否已陈旧。数字含义：`used_unannotated` 是真正的文档缺口，`annotated_unused` 多为 HMI/上位机专用位。

要"一条命令拿到完整项目映射"用 `-Capability read_only_project_text_snapshot`（场景 13）：它在同一次隔离 UI 会话里
一并导出注释表并与程序体 join，产物落在 `text/comments/`，`architecture/project_map.json` 的
`extension_points.comments` 直接给出作用域、统计和未注释软元件清单；`status=ready` 且
`missing_capabilities` 为空才代表这份映射完整（缺注释层会如实报 `partial`）。

扫描一个既有工程后，按这个顺序**先给结论、不擅自改工程**：

1. `read_only_project_text_snapshot` —— 只读完整映射。
2. `summarize_kv_project`（`summarize_kv_project.ps1`，非 UI）—— 产出 `project_summary.json` 与 `项目总结.md`：
   设备构成、工站分层、每个模块的功能与执行顺序、对外接口（外部在写的位、单元 I/O、Modbus）、缺口。
3. `assert_project_standard`（`assert_kv_project_standard.ps1`，非 UI）—— 产出 `standard_report.json`，
   按 `references/project-standard.json` 报 STD-01..06（命名/分层/类型/注释/同实例复用）。
4. **把 2、3 的结论交给用户，并明确询问是否按房规调整**。报告的 `requires_user_decision=true` 时，
   必须先拿到回答，再生成迁移计划，并在工程**副本**上执行（原件不动），逐步编译验证。

房规只是本仓库从范例程序归纳的内部约定（KV STUDIO 不强制任何命名或分区），因此永远只作建议，
不得据此判定项目"错误"，也不得在未获同意时改结构。

### 语义完整性规则（每个类别都不得静默为空）

分析一个工程时按这六条做，违反任一条都算分析缺陷而不是"没查到"：

1. **类别必须报数**：类型/变量/软元件/单元/模块/FB/注释 每一类都给出"总数、收录数、排除数与原因"。
   不要因为"看起来是噪音"就整类过滤——本仓库曾经把 `(System)` 类型整类滤掉，结果运动项目里最关键的
   `_MC_POINT_PARAM`、`_MC_AXIS_*` 全部消失。
2. **产物要声明它不含什么**：`structure_definitions.json` 只含用户自定义类型，系统类型的成员清单不由该
   路由导出；任何产物都要带 `scope`/`omissions`，避免"看起来完整"。
3. **符号必须解析**：程序体里凡是带下标或成员访问的标识符（`_MC_PointParam[1].Point[1].TargetPos`、
   `轴1控制.伺服ON`），都要解析到声明（全局/局部变量、系统变量、FB 实例、软元件）；用
   `resolve_kv_symbols.ps1` 产出 `symbols.json`（含 `class`、`data_type`、成员路径与出处行号）。
4. **未解析符号是缺陷**：解析不到的符号要显式上报。作用域区分很重要：**用户程序内**未解析=缺陷；
   **库 FB 体内**未解析=预期（那些局部变量/实例的声明不在快照里）。
5. **系统类型成员双来源**：手册（Wiki 查询并记录 chunk）＋程序用法反推（标注"由用法推断"）。
   系统类型的成员清单不能靠猜，也不能因为导出缺失就说"不存在"。
6. **固化为门禁**：`assert_kv_snapshot_semantic_coverage.ps1` 检查类别完整性、系统类型是否真的被报出、
   以及用户程序内是否有未解析符号；分析结束前必须跑它并通过。

标准流程相应扩展为：快照 → `resolve_kv_symbols`（符号层）→
`assert_kv_snapshot_semantic_coverage`（门禁）→ `summarize_kv_project`（总结）→
`assert_project_standard`（房规）→ **把结论交给用户并询问是否调整**。

### 快照根目录与数据文件（默认路径）

- `-SnapshotRoot` 必须指向**直接包含 `text` 与 `project` 的那一层**，例如
  `<work>\snapshot-run\snapshot`（该层同时含 `text`、`project`、`raw`、`architecture`）。
  指错层会立刻报 `KV_SNAPSHOT_ROOT_LEVEL_WRONG`，不要靠下游的"文件找不到"去猜。
- 三份数据文件（都可被项目所有者直接编辑，改文件即改口径）：

  | 文件 | 作用 | 参数 |
  | --- | --- | --- |
  | `references/project-standard.json` | 房规本体：层次、命名、类型分层、STD-01..06 与流程 | `-StandardPath` |
  | `references/project-standard.patterns.json` | 命名分桶与 motion 模式（数据形式，脚本保持 ASCII） | `-PatternMapPath` |
  | `references/project-summary.labels.json` | 项目总结的中文标签 | `-LabelsPath` |

- `-AllowUnresolved` 只影响"**用户程序内**未解析符号"的判定（库 FB 体内的未解析本来就只记 info）。
  元素是**符号名**，例如 `-AllowUnresolved 'SocketTCP_Send_Inst','SocketTCP_Recv_Inst'`；被豁免的符号
  仍会出现在 `unresolved_symbols` 里，但不再计入 `failures`，理由是"该符号的声明不在任何快照路由中"。
- MNM 是 UTF-16LE + BOM。**PowerShell 自己的 cmdlet 通常安全**：`Get-Content`/`Select-String` 因 BOM 检测，
  即使不写 `-Encoding` 也能正确读取（实测 5.1.26100 下 ascii 与中文命中都与显式 `-Encoding Unicode` 一致）。
  **真正会"假空"的是非 PowerShell 读取路径**：`findstr` 会报 "input file … is in Unicode format" 且两种查询
  都 0 命中；Python 默认 `open()` 直接 `UnicodeDecodeError`（gbk）。这类工具请显式指定编码，或读快照提供的
  `text\mnm_utf8\`（UTF-8 无 BOM，仅供阅读；权威、可导入的副本始终是 `text\mnm\`）。
### FB 复用口径（项目所有者裁决）

- **可复用、或需要经常移植到其他机器的标准程序，一律做成功能块**（`功能块\FB_*`）；扫描程序只保留现场映射、
  时序与调用层。依据是**本仓库房规**（`project-standard.json` 的 `reuse_principle`），不是 KEYENCE 的硬性要求。
- 复用候选**分两类报告，各自标注依据**，不得混为一谈：
  - **类 A：官方 FB 可用而未用** —— 必须有 Wiki/手册证据；无证据一律写"未证实"（第二轮的严格口径只适用于这类）。
  - **类 B：应抽成用户 FB 的标准逻辑** —— 依据是房规 + 复用性证据（同一逻辑按轴/工位重复，或需移植到其他机器），
    **不需要** KEYENCE 文档。台州工程的 `Axis_FB`（三轴重复的使能/回原/JOG/复位/停止与信号映射）属类 B。
- **每个轴/工位一个实例**：可复用单位是轴或工位，跨轴共享同一实例（`MC_Power_1` 驱动三轴、`MC_Home2` 用于 #2/#3）
  是**缺陷**而非风格，与厂商手册"每轴一个 MC_Power 实例"一致。

运行查询返回的 `customer_callable=true` 入口。普通操作只需对应接口的输入，不需要构造 MVP 或复刻整个项目。需要多步时先准备完整计划；一个 workflow 内部通过同一 flat executor 调度子步骤。新建完整 FB 通常包含程序体导入、自变量写入、局部变量写入和编译；修改其中一项只调用对应接口。

查询结果的 `regression_scenarios` 给出当前仓库中的匹配测试、README、固定输入和运行命令。
首次使用接口，或执行失败需要判断是否缺少能力时，先读匹配 README 与 `scenario.json`，
核对参数、项目前提和验收边界；这些是维护中的接口契约，可以阅读，不是历史运行脚本。
新增或修改任何 `tests/kv-interface-regression/NN_*` 场景时，必须在同一变更中维护
[atomic-operation-coverage.html](tests/kv-interface-regression/atomic-operation-coverage.html)：
增加场景表项，复用已有语义操作 ID，只有出现新语义动作才新增唯一操作 ID，并更新覆盖矩阵、
统计数字和 `live/static/indirect/gap` 证据等级。不得只增加 `scenario.json` 就宣称测试覆盖已更新；
新增场景未完成真实桌面验收时必须标为 `static` 或 `indirect`，不能标为 `live`。同时运行场景发现测试，
确保 `scenario.json`、README、manifest 和 HTML 的场景集合一致：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-root>\tests\test_atomic_operation_coverage.ps1
```

`project_mode=sample_copy` 只证明在样例副本上操作，不证明空白工程创建。
从零建工程应查询 `create_project`，按 `16_create_project` 的 `new_project` 契约调用
`create_kv_project.ps1`。复用调用方式和输入 schema，任务代码仍按用户需求独立编写，
不要复制回归 fixture 充当任务解答。失败时先比较本次证据与该契约，再判断是调用、
前置状态、gate 或实现缺陷；有已发布接口不能直接改走陌生 UI 路线或宣称能力不存在。

自然语言要求新增完整扫描程序或 FB 时，先由 programmer/KB 技能准备代码、声明、Wiki 依据和
精确项目父路径，再按 [complete-module.md](references/complete-module.md) 提交
`create_kv_complete_module` 的整套契约。该入口已发布，适用于文档列出的 BOOL 梯形图新增模块，
真实验收范围和证据见同一 reference；`-PlanOnly` 执行模块契约及整套计划预检，不操作 UI，
不能据此声称真实创建、保存读回或编译验收通过。

ST、浮点、数组和数值算法 FB 先读 [st-programs.md](references/st-programs.md)：
KV 的域类型 ST 导出为 `AREA_ST`，无需发明独立 ST 模块语言选择界面，也不要向 BOOL 契约提交。
导出格式不证明能反向导入；按目标版本的真实验证结果选择文件导入或域 ST 编辑器接口。
按该文档组合程序体、声明、实例、真实编译及完整 ST 源码读回；新建工程的进程绑定证据须传给后续接口。
完整数值 ST 扫描模块或 FB 使用已发布的 `create_kv_st_module`，一次提交整套契约；
调用方实例须等 FB 创建成功后再规划，公开范围目前实测于 KV-X520。

`scaffold_tools` 与 `run_kv_mvp_*` 是可选的完整程序示例和回归工具，用于学习程序体、声明、实例、依赖与编译的关系。只有选用该示例模型时才阅读 [mvp-runner-contract.md](references/mvp-runner-contract.md)，不要把它当作所有项目编辑的前提。

查不到所需能力时报告 `ROUTE_RESEARCH_REQUIRED` 和缺失的接口。用户已经要求修复、测试或研发时，可以在该授权范围内修改并回归；陌生 UI 操作按用户要求立即停下求助，不穷举菜单或焦点路线。

## 调用与验收

1. 明确目标项目和修改范围，准备 TSV、MNM 或配置 JSON。现有内容的修改以相关快照为依据；无需为一次自变量修改导出无关硬件。
2. 使用 `powershell -STA -NoProfile -ExecutionPolicy Bypass -File <workflow>`。支持 `-PlanOnly` 的接口可先准备计划；执行前脚本统一检查入口、结果契约与参数。
3. 查看本次 workflow 结果、步骤 receipt 和同一 `run.log`。结果为失败时停止后续 UI 动作，依据错误码和证据修复。
4. 按实际验证范围报告。快照成功不代表写入成功，模块出现不代表程序体和声明完整，导入成功不代表编译成功。

## 语义项目快照

需要理解整个现有项目、复刻项目、跨模块修改或交给人审核时，优先调用能力
`read_only_project_text_snapshot`。该 workflow 在同一次运行中调用原子读取接口，并直接形成：

```text
snapshot/
├─ project/       首要语义入口
├─ text/          原子文本产物与兼容证据
├─ raw/           workflow receipt、日志和 UI 证据
└─ source_snapshot_manifest.json
```

读取顺序：

1. 先检查 `source_snapshot_manifest.json` 的 `status`、`semantic_project_status`、
   `semantic_warnings` 和项目 fingerprint。
2. 从 `project/overview.md` 和 `project/_index/entities.jsonl` 建立全局视图。
3. 按 `project/功能块`、`project/程序`、`project/配置`、`project/类型` 阅读实体；
   每个实体的 `entity.json` 是路径、产物、状态与恢复依赖的机器可读契约。
4. 自动恢复或制定恢复计划时使用 `project/_index/restore_plan.json`，不得仅按目录名
   猜测顺序。真正写回仍必须调用 manifest 中公开的原子/workflow 接口。
5. 需要追查字段来源、失败或 UI 过程时再下钻 `text/` 和 `raw/`。

`project/` 是由同次原子快照直接物化出的规范视图，不是对历史文档的二次解析。
不要从 `project/`、`text/` 或 `raw/` 中执行脚本。`semantic_project_status=complete`
只表示语义树成功生成；实体的 `failed`、`missing`、`partial`、`unresolved` 状态以及
`semantic_warnings` 仍是恢复和完整性声明的阻断项。窄范围编辑可继续只读取相关原子快照，
无需强制生成完整项目树。

### 异常归因门禁

永远不要先怀疑 KV STUDIO 自身的稳定性。出现 ASSERT、异常退出、无响应或结果与预期不一致时，首先停止后续 UI 输入，并审查 agent 侧的调度与证据链：是否发生重复 workflow/重复 `ProjectSaveAs`、跨进程并发输入、错误的 PID/HWND 绑定、前台焦点恢复、遗留菜单/弹窗、路径或状态污染。必须核对本次 workflow result、step receipt、runner result、同一次 `run.log` 以及截图/文件证据；只有在这些因素均被证据排除后，才可以把问题记录为外部软件问题，且不得直接宣称 KV STUDIO 不稳定。

ASSERT 或异常窗体出现后，不再发送键盘、鼠标或剪贴板输入，不重新调度同一 workflow。保留异常截图、`run.log`、workflow/runner 结果和错误文本；关闭异常窗体由人工确认，通常只执行其默认确认动作，不点击 Log、Backup 或其他会改变现场的按钮。重复操作历史（尤其连续 `ProjectSaveAs`）必须作为 agent 调度问题优先调查。

每次运行使用独立输出目录。执行器记录 run_id、输入和代码指纹、精确结果文件、耗时；缺失、过期、格式错误或非布尔成功值一律失败。复用目录的旧结果保存到 `_history`。项目内容验证由对应子步骤完成，receipt 的 hash 只证明证据归属，不替代语义校验。

所有通过 flat executor 的桌面 workflow 都必须先取得机器级 `Local\\KeyenceAgent.KvStudio.UI` 互斥锁；锁被其他 agent/进程占用时立即返回 `KV_UI_WORKFLOW_BUSY`，不得进入 runner 或发送键盘、鼠标、剪贴板输入。`-PlanOnly` 只生成计划，不占用桌面锁。

workflow 的已验证执行计划就是前置操作清单；不必另写只含关键词的 CHECKLIST。显式提供的旧 scaffold checklist 仍按原契约检查。全部 UI 原子动作、操作和结果追加到同次 `run.log`，不能只留独立 timing JSON。

## 桌面边界

- 保留已有窗口大小。绑定指定项目，允许目标标题带未保存标记 `*`；其他已打开项目不阻塞新建。相同目标有冲突时停止，不处理无关实例。
- 每个 runner 只允许一次前台激活：在第一步输入前由共享 guard 将目标 KV STUDIO 置前并记录 `ui_input_session_started`。会话开始后，任何原子操作只能验证前台/焦点，禁止 `SetForegroundWindow`、`BringWindowToTop`、`SetActiveWindow`、`SetFocus` 或 `AllowSingleRecovery` 抢回主窗口；弹窗、嵌入式编辑器或表格焦点异常必须立即失败并保留证据。
- 原子操作严格小于 10 秒，目标模块一次定向查找小于 1 秒；软件启动/编译运算等待另计并记录。禁止超过五层的 UI 树展开、穷举控件或无故多轮焦点探测。
- 对话框自动聚焦后按已验证路线连续完成输入，不在弹窗中恢复主窗口焦点。表格所在窗口存在不等于表格已获焦点。
- 自变量表和局部变量表共享记忆状态；Ctrl+Tab 次数由当前表和焦点决定，不能写死。此细节封装在原子实现内，agent 不需要重新推导。
- `runner_children`、`guards`、support libraries 是内部实现。新增输入动作先隔离验证，更新共享实现及真实 workflow，再做回归；不为通过当前任务加入未经验证的备用路线。
- 系统数据类型 `(System)` 不创建、不修改。嵌套用户类型先创建被引用类型。表格末尾空白新增行不计为已写入成员。

## 按任务阅读

- 编写 PLC 逻辑、MNM 和 FB 接口：使用 `keyence-plc-programmer`；KEYENCE 专有语法依据 Wiki 或导出证据。
- 新增完整扫描程序/FB 的契约、BOOL 范围及整套预检：[complete-module.md](references/complete-module.md)；只改已有单项仍走窄接口。
- 变量/结构体 schema、FB 表格状态及持久化范围：[variable-editor.md](references/variable-editor.md)。
- 硬件、EtherCAT、EtherNet/IP 和 ESI 边界：[project-configuration.md](references/project-configuration.md)。
- 复刻工程和语义快照的资产/恢复契约：[project-replication.md](references/project-replication.md)；官方/用户 FB 区分：[fb-filter.md](references/fb-filter.md)。
- 定位/遍历工程树（程序、功能块、书签）：[tree-resolution.md](references/tree-resolution.md)。**按结构解析**（父路径 + 直接子项 + `局部变量`/`书签` 指纹）；禁止 `-like` 匹配树项名（`[ ]` 是通配符），禁止全树按名搜索（`变量/HMI` 与程序 `HMI` 同名）。
- 样例项目位置和副本规则：[sample-project.md](references/sample-project.md)。修改性测试使用测试工程或独立副本。
- 维护脚本：[script-layout-checklist.md](references/script-layout-checklist.md) 与 [ui-guard-contract.md](references/ui-guard-contract.md)；验证标签含义：[capability-status.md](references/capability-status.md)。

仓库代码是维护源；本机安装链接到该源。输出目录只保存输入与运行证据，不从历史运行目录寻找或执行替代脚本。已退役实现放在仓库 archive 中，以文本保留，不再安装为 skill。

UI probe 和原子操作必须复用仓库现有的进程/HWND 绑定、窗口解析和标题谓词。禁止临时写中文项目标题字面量，禁止让控制台编码转换项目名；优先按 PID/HWND 绑定并使用稳定的 `KV STUDIO*` 谓词。无法复用现有解析助手时，必须在发送输入前停止。树解析一律用 `scripts/kv_tree_resolver.ps1`（见 [tree-resolution.md](references/tree-resolution.md)）。改动内容优先用最细层级：能改字段就不改程序体，能改程序体就不删/重建模块。

## 强制真实桌面验收

- 任何声称“已通过”“published 回归通过”或“功能已完成”的 KV STUDIO 能力，必须在真实运行的 `Kvs.exe` 桌面进程上执行；`-PlanOnly`、PowerShell 语法解析、manifest 门禁、历史快照和无进程安全失败只能算准备或负向验证，不能替代成功验收。
- 真实验收必须串行取得 `Local\KeyenceAgent.KvStudio.UI`，启动或连接实际 KV STUDIO 项目，执行 workflow 的全部 UI 原子动作，并完成该能力规定的保存、回读、复制核对、编译或其他最终验证。每一步都必须由同一运行的 `run.log`、step receipt、workflow result 和必要的快照/截图支持。
- 只有同次运行的最终结果文件明确为 `ok=true`，且证据能证明目标项目实际发生了预期修改并可重新读取，才能把能力记录为通过。仅找到窗口、打开表格、粘贴成功或生成计划都不算通过。
- 真实桌面测试失败时，立即停止后续 UI 输入，保留该次运行目录和失败窗口/错误文本；不得以静态检查、旧运行目录或“理论上应该成功”覆盖失败。除非重新完成真实桌面验收，否则不得提高 capability 状态。
- 测试项目必须使用独立副本或用户明确指定的项目；测试前记录项目路径、窗口标题、PID/HWND 和输入文件指纹，测试后记录保存/回读证据。不得并行启动或操作多个 KV STUDIO workflow。
