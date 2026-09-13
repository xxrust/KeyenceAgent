---
name: kv-studio-operator
description: 通过稳定 workflow 操作 KEYENCE KV STUDIO 桌面项目。用于项目创建、MNM 导入导出、FB 自变量与局部变量、数据类型、编译结果和单元/EtherCAT 配置；从能力清单选择接口，由脚本负责焦点、输入、验证和日志。
---

# KV STUDIO 操作

把 KV STUDIO 当作由 workflow 提供接口的编辑器。agent 准备目标、输入和预期结果，调用接口后读取本次结果；不要临时拼接键盘、窗口或剪贴板操作。

## 选择接口

唯一能力清单是 [scripts/script_manifest.json](scripts/script_manifest.json)。用只读查询获得实际路径、参数类型、必填参数和验证范围：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-root>\scripts\get_kv_capabilities.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-root>\scripts\get_kv_capabilities.ps1 -Capability snapshot_fb_arguments
```

运行查询返回的 `customer_callable=true` 入口。普通操作只需对应接口的输入，不需要构造 MVP 或复刻整个项目。需要多步时先准备完整计划；一个 workflow 内部通过同一 flat executor 调度子步骤。新建完整 FB 通常包含程序体导入、自变量写入、局部变量写入和编译；修改其中一项只调用对应接口。

`scaffold_tools` 与 `run_kv_mvp_*` 是可选的完整程序示例和回归工具，用于学习程序体、声明、实例、依赖与编译的关系。只有选用该示例模型时才阅读 [mvp-runner-contract.md](references/mvp-runner-contract.md)，不要把它当作所有项目编辑的前提。

查不到所需能力时报告 `ROUTE_RESEARCH_REQUIRED` 和缺失的接口。用户已经要求修复、测试或研发时，可以在该授权范围内修改并回归；陌生 UI 操作按用户要求立即停下求助，不穷举菜单或焦点路线。

## 调用与验收

1. 明确目标项目和修改范围，准备 TSV、MNM 或配置 JSON。现有内容的修改以相关快照为依据；无需为一次自变量修改导出无关硬件。
2. 使用 `powershell -STA -NoProfile -ExecutionPolicy Bypass -File <workflow>`。支持 `-PlanOnly` 的接口可先准备计划；执行前脚本统一检查入口、结果契约与参数。
3. 查看本次 workflow 结果、步骤 receipt 和同一 `run.log`。结果为失败时停止后续 UI 动作，依据错误码和证据修复。
4. 按实际验证范围报告。快照成功不代表写入成功，模块出现不代表程序体和声明完整，导入成功不代表编译成功。

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
- 变量/结构体 schema、FB 表格状态及持久化范围：[variable-editor.md](references/variable-editor.md)。
- 硬件、EtherCAT、EtherNet/IP 和 ESI 边界：[project-configuration.md](references/project-configuration.md)。
- 复刻工程的资产清单：[project-replication.md](references/project-replication.md)；官方/用户 FB 区分：[fb-filter.md](references/fb-filter.md)。
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
