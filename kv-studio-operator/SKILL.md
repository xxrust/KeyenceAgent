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

每次运行使用独立输出目录。执行器记录 run_id、输入和代码指纹、精确结果文件、耗时；缺失、过期、格式错误或非布尔成功值一律失败。复用目录的旧结果保存到 `_history`。项目内容验证由对应子步骤完成，receipt 的 hash 只证明证据归属，不替代语义校验。

所有通过 flat executor 的桌面 workflow 都必须先取得机器级 `Local\\KeyenceAgent.KvStudio.UI` 互斥锁；锁被其他 agent/进程占用时立即返回 `KV_UI_WORKFLOW_BUSY`，不得进入 runner 或发送键盘、鼠标、剪贴板输入。`-PlanOnly` 只生成计划，不占用桌面锁。

workflow 的已验证执行计划就是前置操作清单；不必另写只含关键词的 CHECKLIST。显式提供的旧 scaffold checklist 仍按原契约检查。全部 UI 原子动作、操作和结果追加到同次 `run.log`，不能只留独立 timing JSON。

## 桌面边界

- 保留已有窗口大小。绑定指定项目，允许目标标题带未保存标记 `*`；其他已打开项目不阻塞新建。相同目标有冲突时停止，不处理无关实例。
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
