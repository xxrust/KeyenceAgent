---
name: kv-studio-operator
description: 通过稳定 workflow 操作和快照化 KEYENCE KV STUDIO 桌面项目。用于项目创建、语义项目快照、MNM 导入导出、FB 自变量与局部变量、数据类型、编译结果和单元/EtherCAT 配置；从能力清单选择接口，由脚本负责焦点、输入、验证和日志。
---

# KV STUDIO 操作

把 KV STUDIO 当作由 workflow 提供接口的编辑器。agent 准备目标、输入和预期结果，调用接口后读取本次结果；不要临时拼接键盘、窗口或剪贴板操作。

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
- 样例项目位置和副本规则：[sample-project.md](references/sample-project.md)。修改性测试使用测试工程或独立副本。
- 维护脚本：[script-layout-checklist.md](references/script-layout-checklist.md) 与 [ui-guard-contract.md](references/ui-guard-contract.md)；验证标签含义：[capability-status.md](references/capability-status.md)。

仓库代码是维护源；本机安装链接到该源。输出目录只保存输入与运行证据，不从历史运行目录寻找或执行替代脚本。已退役实现放在仓库 archive 中，以文本保留，不再安装为 skill。

UI probe 和原子操作必须复用仓库现有的进程/HWND 绑定、窗口解析和标题谓词。禁止临时写中文项目标题字面量，禁止让控制台编码转换项目名；优先按 PID/HWND 绑定并使用稳定的 `KV STUDIO*` 谓词。无法复用现有解析助手时，必须在发送输入前停止。

## 强制真实桌面验收

- 任何声称“已通过”“published 回归通过”或“功能已完成”的 KV STUDIO 能力，必须在真实运行的 `Kvs.exe` 桌面进程上执行；`-PlanOnly`、PowerShell 语法解析、manifest 门禁、历史快照和无进程安全失败只能算准备或负向验证，不能替代成功验收。
- 真实验收必须串行取得 `Local\KeyenceAgent.KvStudio.UI`，启动或连接实际 KV STUDIO 项目，执行 workflow 的全部 UI 原子动作，并完成该能力规定的保存、回读、复制核对、编译或其他最终验证。每一步都必须由同一运行的 `run.log`、step receipt、workflow result 和必要的快照/截图支持。
- 只有同次运行的最终结果文件明确为 `ok=true`，且证据能证明目标项目实际发生了预期修改并可重新读取，才能把能力记录为通过。仅找到窗口、打开表格、粘贴成功或生成计划都不算通过。
- 真实桌面测试失败时，立即停止后续 UI 输入，保留该次运行目录和失败窗口/错误文本；不得以静态检查、旧运行目录或“理论上应该成功”覆盖失败。除非重新完成真实桌面验收，否则不得提高 capability 状态。
- 测试项目必须使用独立副本或用户明确指定的项目；测试前记录项目路径、窗口标题、PID/HWND 和输入文件指纹，测试后记录保存/回读证据。不得并行启动或操作多个 KV STUDIO workflow。
