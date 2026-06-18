# kv-studio-operator

> 本文由原 kv-studio-operator/SKILL.md 转为统一入口 skill 的 reference。路径按 keyence-kv-studio 包内结构解析。

# 基本认知
KV STUDIO 是 KEYENCE 旗下的 PLC 编程软件，支持梯形图、功能块图、结构化文本等多种编程语言。用户通过它创建和管理 PLC 项目，编写控制逻辑，并将程序部署到 PLC 设备上。KV STUDIO 提供了丰富的功能，包括变量管理、在线监控、调试工具和项目配置选项，适用于各种工业自动化应用场景。
但是该PLC并没有对外的脚本，虽然宣传说兼容ST语言，但结构上还有许多差别，比如变量不能定义在程序块中。
所以为了创建一个完整的PLC项目，我们需要引入由多个原子操作构建的工作流，包含打开/创建项目，导入Ethercat配置，Ethernet配置，PLC模块配置，配置轴控模块，导入/导出MNM，编辑变量，编译程序等操作。

# KV STUDIO 操作

本 skill 用于让 agent 通过已发布脚本操作 KV STUDIO。agent 先读取 manifest 选择入口，再传入项目路径、脚手架路径、输出目录等参数；KV STUDIO 的窗口操作由 workflow 完成，agent 只读取同次运行产物并汇报结果。

## 快速入口

客户态入口唯一来源是 `scripts\kv-studio-operator\script_manifest.json`。先读取 manifest，再运行 `customer_callable=true` 的 `customer_workflow`、`customer_scaffold_tool`、`customer_non_ui_tool` 或 `gate`。

```yaml
quick_start:
  SkillRoot: this_skill_directory
  WorkRoot: <configured-work-root-or-temp-work-root>
  Manifest: scripts\kv-studio-operator\script_manifest.json
  BuiltInSample: assets\kv-studio-operator\KVX样例程序_v100\KVX样例程序_v100.kpr
  route_map:
    new_project: customer_scaffold_tool -> customer_workflow
    existing_project_repair: customer_non_ui_tool -> customer_scaffold_tool -> customer_workflow
    export_mnm: customer_workflow capability export_mnm_project_copy_default_folder
    non_ui_gate: manifest.classes.gate
    project_configuration: manifest.classes.customer_workflow requires matching capability
```

`runner_children`、`guards`、`probes` 是 workflow 内部实现或研发工具。客户态失败诊断读取同次 result/evidence；研发态操作需要用户明确授权。references 只提供状态、schema 和失败归因；执行入口仍由 manifest 决定。

## 术语

```yaml
terms:
  workflow: 已发布的编排脚本，负责打开/操作/收口 KV STUDIO
  runner_child: workflow 调用的内部 UI 原子步骤
  guard: runner_child 使用的输入与窗口状态保护库
  gate: 不打开 KV STUDIO 的校验脚本
  evidence: 本次运行写出的日志、截图、窗口状态、result/failure JSON
  same_run_artifact: 与当前 workflow 同一次运行生成的产物
  customer_callable: manifest 中允许客户态 agent 直接运行的标记
  clean_end_state: workflow 结束后 KV STUDIO 回到主窗口或已关闭，且无遗留配置窗口/弹窗
  customer_mode: 只运行 customer workflow、scaffold tool、non-UI tool、gate，并读取产物
  customer_non_ui_tool: 客户态可运行的不打开 KV STUDIO 的准备、读取或过滤脚本
  research_mode: 探索或修脚本的研发状态，需要用户明确授权
  research_authorization: 用户明确要求进入 research_mode 并允许运行研发脚本
  ROUTE_RESEARCH_REQUIRED: 当前客户态 workflow 无法继续，需要转研发态
  customer_scaffold_tool: 客户态可运行的脚手架或预检脚本
  customer_workflow: 客户态可运行的 KV STUDIO UI 编排脚本
  runner_child_approved: workflow 内部可调用的已验证原子步骤
  runner_child_pending: 等待验证的内部原子步骤
  flat_execution_runner: workflow_tool/invoke_kv_flat_execution_plan.ps1，执行 execution_plan 中的步骤、超时、失败收集和 result 输出
  probe_research: 研发态探针脚本
  published: 客户态可直接依 manifest 运行
  approved: workflow 或回归 harness 可调用
  pending_validation: 等待验证证据
  research_only: 研发态使用
```

## 客户态规则

```yaml
customer_mode_contract:
  agent_actions:
    - choose_entry_from_script_manifest
    - edit_scaffold_files_before_KV_STUDIO_opens
    - run_customer_workflow_scaffold_tool_non_ui_tool_or_gate
    - inspect_same_run_result_and_evidence
    - report_error_code_step_evidence_clean_state
  ui_owner: customer_workflow
  failure_transition: ROUTE_RESEARCH_REQUIRED
```

运行 customer_workflow 时，KV STUDIO 窗口控制权属于 workflow。agent 读取 workflow 写出的 result JSON、failure JSON、evidence 目录和 clean-state 检查结果来判断成败。

## 新项目

```yaml
new_project_flow:
  - create_scaffold: manifest.classes.customer_scaffold_tool capability new_kv_mvp_scaffold
  - edit_primary_model: scaffold.model.json
  - render_when_model_changed: manifest.classes.customer_non_ui_tool capability render_kv_mvp_scaffold_model
  - validate_scaffold: manifest.classes.customer_scaffold_tool capability validate_kv_mvp_scaffold
  - run_kvstudio: manifest.classes.customer_workflow capability run_kv_mvp_scaffold
    - repeat_gate: manifest.classes.regression_harness capability run_kv_mvp_repeat
internal_structure:
  workflow:
    - generate_new_project_execution_plan
    - invoke_flat_execution_runner
  flat_execution_runner:
    - execute_plan_steps
    - collect_failure
    - write_result_json
success:
  - scaffold_validation.json.ok == true
  - mvp_result.json.ok == true
  - repeat_result.json.ok == true when repeat requested
```

正常编辑入口是 `scaffold.model.json`。生成后的 MNM/TSV 是 KV STUDIO adapter artifact；诊断旧脚手架时才直接编辑生成物。

## 现有项目修复

```yaml
existing_project_flow:
  - create_or_update_workspace: manifest.classes.customer_non_ui_tool capability new_kv_existing_project_update_workspace
  - verify_snapshot: manifest.classes.customer_non_ui_tool capability assert_kv_existing_project_snapshot
  - plan_mnm_import: manifest.classes.customer_scaffold_tool capability assert_kv_mnm_import_plan
  - edit_scaffold_from_verified_snapshot
  - run_repair: manifest.classes.customer_workflow capability run_kv_mvp_repair_existing_project
internal_structure:
  workflow:
    - generate_repair_existing_project_execution_plan
    - invoke_flat_execution_runner
  flat_execution_runner:
    - execute_plan_steps
    - collect_failure
    - write_result_json
success:
  - repair_result.json.ok == true
  - source_snapshot_gate.ok == true
  - project_fingerprint_matches_current_gate
```

当前项目快照必须来自同一项目 hash 下的新导出 `.mnm`、`.csv`、`.lbl` 或 runner sidecar。项目目录 hash 变化后重新导出。

## MNM 导出

先从 manifest 解析 `customer_workflow` 中的 `export_mnm_project_copy_default_folder` 入口，再运行解析出的 path：

```powershell
$ResolvedWorkflowPath = '<path resolved from manifest customer_workflow export_mnm_project_copy_default_folder>'
powershell -NoProfile -ExecutionPolicy Bypass -File $ResolvedWorkflowPath `
  -ProjectPath '<project.kpr>' `
  -ExportDir '<out>\exported_mnm' `
  -OutDir '<out>\export_mnm_project_copy' `
  -WorkRoot '<out>\exported_mnm\_kv_export_workspace'
```

```yaml
success:
  - export_mnm_project_copy_result.json.ok == true
  - same_run_mnm_files under ExportDir
  - postcheck_kvstudio_ui_safe.json.ok == true
```

workflow 通过项目副本位置和默认导出目录控制 MNM 输出位置。下游 MNM 解析脚本只读取顶层导出 MNM，并忽略 `ExportDir\_kv_export_workspace`。

## 项目配置脚本状态

```yaml
project_configuration_policy:
  entry_source: scripts\kv-studio-operator\script_manifest.json
  customer_mode_condition: manifest.classes.customer_workflow contains requested capability
  absent_customer_workflow_status: ROUTE_RESEARCH_REQUIRED
  absent_customer_workflow_action: emit ROUTE_RESEARCH_REQUIRED with requested_capability
  evidence_reference: references\kv-studio-operator\capability-status.md
```

PLC 扩展单元、单元首地址、EtherCAT、EtherNet/IP 等配置能力以 manifest 中的客户态 workflow 为准。manifest 没有对应客户态 workflow 时，客户态结果为 `ROUTE_RESEARCH_REQUIRED`；能力状态见 `references\kv-studio-operator\capability-status.md`。

项目配置意图、EtherNet/IP 成员查询、EtherCAT ESI 状态和配置脚本成熟度见 `references\kv-studio-operator\project-configuration.md`。

## 内置样例项目

```powershell
$SampleProjectPath = Join-Path $SkillRoot 'assets\kv-studio-operator\KVX样例程序_v100\KVX样例程序_v100.kpr'
```

测试、示例和回归命令使用 `references\kv-studio-operator\sample-project.md` 中的内置样例项目。会修改项目的 workflow 先复制样例到 disposable work root；只读 inventory 或结构解析可以直接读取样例目录。

## 变量与门限

```yaml
variable_files:
  pairing: per_mnm_module
  minimum_header: "scope\towner_program\tname\tdata_type\tdevice\tinitial_value\tcomment\tevidence\tstatus"
  no_local_variables_marker:
    scope: local
    name: __NO_LOCAL_VARIABLES__
    status: no_local_variables

variable_grid_gate:
  required_before_copy_or_paste:
    - foreground_window == KvVariableForm
    - local_program_combo.value == target_program
    - variable_editor_uia_signature.stable_for_ms >= 900
    - system_clipboard.openable_for_ms >= 500
    - input_owner == scripts\guards\kv_ui_guard.ps1
  success_artifacts:
    - persisted_variable_rows
    - close_reopen_copy_audit_when_AuditVariablePersistence
    - same_run_result_json
```

无局部变量时使用唯一 marker 行；runner 识别 marker 行并跳过粘贴。用户在失败界面手动复制成功时，分类为脚本自有焦点/窗口状态/输入路径不匹配；修复在脚本自有路径内完成，并用全新项目副本至少两次 `-AuditVariablePersistence` 验证。

## 官方/库 FB 过滤

项目复刻时，官方/库 FB 属于依赖，用户 FB 属于源码。导出 MNM 后先过滤官方/库 FB；过滤命令、分类规则和报告文件见 `references\kv-studio-operator\fb-filter.md`。

## 1:1 项目复刻

```yaml
project_replication:
  first_step: export_inventory
  config_steps: require_customer_workflow_or_ROUTE_RESEARCH_REQUIRED
  program_steps: fresh_MNM_export_then_official_FB_filter
  details: references\kv-studio-operator\project-replication.md
```

`project_inventory.json.clone_readiness.ready_for_full_1_to_1_import=false` 时，状态为 `ROUTE_RESEARCH_REQUIRED`；依缺失类别拆分 UI 突破任务。

## 失败报告

```yaml
failure_report_required:
  - workflow_or_gate
  - current_step
  - stable_error_code
  - result_json_or_failure_json
  - evidence_path
  - clean_end_state
  - next_action: customer_result_or_research_authorization_request
```

常见 gate code 保持英文，例如 `KV_CHECKLIST_MISSING`、`KV_SOURCE_SNAPSHOT_STALE`、`KV_MNM_SAME_NAME_IMPORT_REQUIRES_PREDELETE`、`KV_VARIABLE_PASTE_NOT_PERSISTED`。

## 参考

```yaml
references:
  script-layout-checklist.md: 理解 workflow/runner_children/guards/probes/gates 的目录分工
  mvp-runner-contract.md: 解释 runner artifact/result schema
  ui-guard-contract.md: 修改或诊断 guarded UI input
  variable-editor.md: 修改变量 TSV schema 或诊断变量编辑器粘贴
  capability-status.md: 查看客户态能力、内部脚本和待验证能力状态
  sample-project.md: 查看内置 KVX 样例项目路径和使用规则
  project-configuration.md: 查看网络/单元/EtherCAT/EtherNet-IP 配置细节
  fb-filter.md: 查看官方/库 FB 过滤命令和分类规则
  project-replication.md: 查看 1:1 复刻 inventory 与资产清单
```
