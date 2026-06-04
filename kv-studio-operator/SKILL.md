---
name: kv-studio-operator
description: 通过脚本控制 KEYENCE KV STUDIO 桌面软件时使用。适用于创建 KV STUDIO 项目、导入/导出 MNM、编辑全局/局部变量、运行转换/编译、复制转换结果、配置 PLC 扩展单元、EtherNet/IP、EtherCAT、复刻或修复现有 `.kpr` 项目，以及运行脚手架 runner 的任务。
---

# KV STUDIO 操作

## 合同

```yaml
contract:
  rule: workflow_owns_kvstudio_ui
  agent_may:
    - edit_scaffold_files_before_KV_STUDIO_opens
    - run_published_workflow
    - run_non_ui_gate_script
    - inspect_same_run_artifacts_after_runner_exits
  agent_must_not:
    - manually_click_or_type_in_live_KV_STUDIO
    - continue_a_failed_runner_inside_existing_window
    - call_child_mvp_scripts_as_customer_operation
    - compose_unclassified_ui_scripts_as_workflow
    - edit_stable_scripts_in_operate_mode
    - use_old_artifacts_as_success_proof
  primary_paths:
    SkillRoot: this_skill_directory
    WorkRoot: C:\Users\Public\KVSkillPractice
    ScaffoldRoot: WorkRoot\scaffolds\<task-id>
    OutRoot: WorkRoot\mvp_runs
```

KV STUDIO 一旦启动，操作权属于发布 workflow；agent 只从同次运行产物判断结果。客户操作态失败后输出 evidence 和稳定错误码，进入研发态处理路线，不在现有窗口内探究、扫描或修改脚本。

## 新项目脚手架流程

```yaml
new_project_route:
  - step: create_scaffold
    command: scripts\scaffold_tools\new_kv_mvp_scaffold.ps1
    pass: scaffold.json_and_CHECKLIST_exist
  - step: edit_scaffold
    files:
      - scaffold.model.json
      - modules\<module>\*.mnm
      - scaffold.json.mnm_files[].variables.global_tsv
      - scaffold.json.mnm_files[].variables.local_tsv
      - architecture\*.json
      - TASK.md
      - VERSION.md
      - CHECKLIST.md
  - step: validate_scaffold
    command: scripts\scaffold_tools\validate_kv_mvp_scaffold.ps1
    pass: scaffold_validation.json.ok == true
  - step: run_kvstudio
    command: scripts\workflows\run_kv_mvp_scaffold.ps1
    pass: mvp_result.json.ok == true
  - step: repeat_gate
    command: scripts\workflows\run_kv_mvp_repeat.ps1
    pass: repeat_result.json.ok == true and consecutive_passes >= 3
```

结构化脚手架优先编辑 `scaffold.model.json`，再运行 `scripts\render_kv_mvp_scaffold_model.ps1`。生成的 MNM/TSV 是 KV STUDIO adapter artifact；只有诊断或旧脚手架才直接编辑。

## 现有项目修复流程

```yaml
existing_project_route:
  - create_or_update_workspace: scripts\new_kv_existing_project_update_workspace.ps1
  - verify_snapshot: scripts\assert_kv_existing_project_snapshot.ps1
  - plan_mnm_import: scripts\scaffold_tools\assert_kv_mnm_import_plan.ps1
  - edit_scaffold_from_verified_snapshot
  - run_repair: scripts\workflows\run_kv_mvp_repair_existing_project.ps1
  - verify_same_run_artifacts
required_gates:
  - source_snapshot_manifest.status == ready
  - project_fingerprint_matches
  - MNM_and_variable_manifest_exist
  - same_name_MNM_conflict_planned_or_predeleted
```

不要用旧 `.mnm`、旧 `.csv`、旧 `.lbl` 或 sidecar 文件冒充当前项目快照。项目目录 hash 变化后必须重新导出。

## 操作态 Workflow 与原子性

```yaml
operate_mode:
  entrypoint_type: published_workflow
  allowed:
    - scripts\workflows\run_kv_mvp_scaffold.ps1
    - scripts\workflows\run_kv_mvp_repair_existing_project.ps1
    - scripts\workflows\run_kv_mvp_repeat.ps1
    - scripts\workflows\export_mnm_project_copy_default_folder.ps1
    - non_ui_gate_scripts
  blocked:
    - direct_child_ui_script_chain
    - ad_hoc_UIA_scan_after_failure
    - script_patch_after_operation_failure
    - probe_script_in_customer_project
  failure_result:
    status: ROUTE_RESEARCH_REQUIRED
    required_fields: [workflow, current_step, error_code, evidence, clean_end_state]
```

workflow 是客户操作态的最小执行单位。workflow 可以串联多个已批准原子脚本，但必须由 runner 负责步骤顺序、超时、失败收口、同次运行证据和结束环境检查。agent 在客户操作态只传参、运行 workflow、读取结果。

```yaml
workflow_composition_contract:
  classification_source: scripts/script_manifest.json
  current_layout_policy: role_directories_with_legacy_wrappers
  role_layout:
    scaffold_tools: customer_callable_non_UI_preparation
    workflows: customer_callable_orchestration
    runner_children: workflow_called_UI_or_KV_STUDIO_steps
    guards: shared_UI_input_libraries
    probes: research_only
    gates: non_UI_validation
  customer_workflow:
    role: orchestration_only
    must:
      - compose_approved_internal_runner_child_scripts
      - own_parameters_workspace_timeout_result_json_and_clean_end_state
      - preserve_child_script_route_implementation
    must_not:
      - duplicate_internal_UI_steps
      - rewrite_child_script_logic_inside_workflow
      - expose_child_script_as_customer_entrypoint
  internal_runner_child:
    role: verified_UI_or_KV_STUDIO_atomic_step
    callable_by:
      - customer_workflow
      - regression_test_harness
    not_callable_by:
      - customer_operate_mode_agent_directly
```

不要仅靠目录名或脚本名判断脚本权限；读取 `scripts/script_manifest.json`。正式路径按 role 分离：`workflows` 编排，`runner_children` 执行内部 UI 原子步骤，`guards` 提供输入原语，`probes` 只用于研发态。`scripts\mvp\*.ps1` 只保留为 legacy compatibility wrapper，不作为客户态正式入口。

```yaml
atomic_operation_contract:
  precondition:
    - target_project_identity_known
    - checklist_gate_passed
    - if_KV_STUDIO_already_running: assert_kvstudio_ui_safe.ok == true
  postcondition:
    - no_KV_STUDIO_modal_dialog
    - no_unit_editor_network_editor_variable_editor_left_open
    - no_inline_ladder_edit_bar
    - project_saved_or_disposable_project_closed_by_workflow
    - result_json_written
    - evidence_dir_written
  failure_postcondition:
    - failure_json_written
    - current_step_written
    - evidence_paths_written
    - no_further_UI_action_after_failure
  clean_end_state_check:
    command: scripts\assert_kvstudio_ui_safe.ps1
    required_when: workflow_leaves_KV_STUDIO_running
```

当前脚本原子性分级：

```yaml
atomicity_audit_2026_06_04:
  tested_on_this_machine:
    assert_kvstudio_ui_safe.ps1:
      result: passed
      note: current desktop had no visible KV_STUDIO hazard
    real_KV_STUDIO_UI_workflows:
      result: partial_pass
      specimen: C:\Users\Public\KVSkillPractice\full_atomic_tests\taizhou_20260604_035218
      passed:
        - export_mnm_project_copy_default_folder.ps1 exported 12 MNM and postcheck ok
        - export_mnm_project_copy_default_folder.ps1 default resolver fresh pass on C:\Users\Public\KVSkillPractice\export_mnm_default_resolver_retest_20260604 with 12 top-level MNM files under caller ExportDir and postcheck ok
        - compile_and_copy_result_bounded.ps1 sent Ctrl+F9 and postcheck ok
        - set_variables_guarded.ps1 passed on C:\Users\Public\KVSkillPractice\full_atomic_tests\taizhou_var_20260604_123634 with 1 global variable, 2 Main local variables, close/reopen local-grid copy audit, saved-project global-name scan, and postcheck ok
        - create_project_local_guarded.ps1 default resolver fresh pass on C:\Users\Public\KVSkillPractice\script_coverage_20260604_141514\06_fresh_published_script_tests\01_create_eip_project and 03_create_ec_project
        - configure_kv_ethercat_device.ps1 fresh pass for registered Beckhoff BK1120 on C:\Users\Public\KVSkillPractice\script_coverage_20260604_141514\06_fresh_published_script_tests\04_configure_ec_bk1120
        - copy_convert_result_from_tree_handle.ps1 live watch pass after Ctrl+F9 on C:\Users\Public\KVSkillPractice\copy_convert_live_watch_20260604_1615\03_copy_convert_result with lookup_ms=133, line_count=7, contains_ok=true
      blocked:
        - configure_kv_ethernet_ip_device.ps1 fresh run selected SR-2000 and set node/IP but failed at variable setting OK enable condition; post-failure clean-state check passed
      note: compile result copy is protected atomic after Ctrl+F9 precondition creates a visible non-empty conversion result tree
  customer_workflow_entrypoints:
    - scripts\workflows\run_kv_mvp_scaffold.ps1
    - scripts\workflows\run_kv_mvp_repair_existing_project.ps1
    - scripts\workflows\run_kv_mvp_repeat.ps1
    - scripts\workflows\export_mnm_project_copy_default_folder.ps1
  runner_child_scripts:
    - scripts\runner_children\import_mnm_guarded.ps1
    - scripts\runner_children\compile_and_copy_result_bounded.ps1
    - scripts\runner_children\set_variables_guarded.ps1
    - scripts\runner_children\copy_convert_result_from_tree_handle.ps1
    - scripts\runner_children\create_project_local_guarded.ps1
    - scripts\runner_children\export_mnm_browse_default_folder_guarded.ps1
  pending_runner_child_scripts:
    - scripts\runner_children\set_fb_arguments_guarded.ps1
  protected_atomic_scripts:
    - scripts\workflows\export_mnm_project_copy_default_folder.ps1
    - scripts\runner_children\copy_convert_result_from_tree_handle.ps1
  protected_atomic_rule:
    - do_not_modify_for_new_feature_probe
    - rerun_same_route_regression_before_patch
    - preserve_precondition_CtrlF9_visible_non_empty_conversion_result_tree
  project_configuration_atomic_if_KeepWindowOpen_absent_and_postcheck_passes:
    - scripts/configure_kv_expansion_units.ps1
    - scripts/configure_kv_unit_start_addresses.ps1
    - scripts/configure_kv_ethercat_device.ps1
  project_configuration_route_lab_until_fixed:
    - scripts/configure_kv_ethernet_ip_device.ps1
  non_ui_atomic:
    - scripts/filter_kv_mnm_user_sources.ps1
    - scripts/get_kv_ethernet_ip_device_members.ps1
    - scripts/export_kv_project_inventory.ps1
    - scripts/assert_*.ps1
  non_ui_atomic_notes:
    filter_kv_mnm_user_sources.ps1: ignores _kv_export_workspace before classifying MNM
  route_lab_only:
    - scripts\probes\probe_file_menu_coordinate.ps1
```

子脚本变成客户 workflow 步骤的条件：

```yaml
promotion_to_customer_workflow_step:
  required:
    - explicit_parameters
    - result_json_schema
    - stable_error_codes
    - same_run_evidence_dir
    - timeout
    - clean_end_state_check
    - no_probe_branch
    - no_script_self_modification
    - repeat_pass_on_disposable_project >= 2
```

研发态可以使用 `ui-automation-breakthrough` 探究未知 transition；客户操作态只接收通过 promotion 的 workflow。

变量脚本门限：

```yaml
set_variables_guarded_required:
  row_collection: always_wrap_Get-DefinedVariableRows_result_with_array_before_Count
  open_variable_editor: normalize_CapsLock_or_accelerator_state_inside_Ensure-VariableEditorOpen
  persistence_audit:
    local: close_reopen_select_program_copy_grid_match_expected_names
    global: saved_project_scan_or_stronger_global_grid_copy_oracle
  customer_entry: runner_child_only_until_wrapped_by_workflow_with_project_copy_identity
```

## 硬门限

```yaml
hard_gates:
  checklist: scripts\assert_kv_operation_checklist.ps1
  variable_definitions: scripts\assert_kv_variable_definitions.ps1
  scaffold: scripts\scaffold_tools\validate_kv_mvp_scaffold.ps1
  existing_project_snapshot: scripts\assert_kv_existing_project_snapshot.ps1
  mnm_import_plan: scripts\scaffold_tools\assert_kv_mnm_import_plan.ps1
  ui_guard: scripts\gates\assert_kv_mvp_ui_guard_usage.ps1
  agent_boundary: scripts\gates\assert_kv_mvp_agent_boundary.ps1
forbidden:
  - dummy_variable_rows_to_satisfy_non_empty_tsv
  - placeholder_or_stub_snapshot_files_as_evidence
  - weakening_or_deleting_validation_rules_to_continue
  - treating_compile_after_bypassed_gate_as_valid
  - closing_modal_or_extending_timeout_as_root_cause_fix
```

只有能证明门限本身错误，并经过独立严格审核后，才允许改门限；否则必须修产物或停止。

## 脚手架文件

```yaml
editable_before_runner:
  - scaffold.model.json
  - modules\<module>\*.mnm
  - scaffold.json.mnm_files[].variables.global_tsv
  - scaffold.json.mnm_files[].variables.local_tsv
  - architecture\*.json
  - architecture\network_config.json
  - TASK.md
  - VERSION.md
  - CHECKLIST.md
forbidden:
  - hand_edit_generated_runner_artifacts
  - put_network_config_in_TASK_or_MNM_comments
```

变量文件按 MNM/module 配对，不要假设一个项目只有一个 `variables\global_variables.tsv` 或 `variables\local_variables.tsv`。

最小 TSV header：

```text
scope	owner_program	name	data_type	device	initial_value	comment	evidence	status
```

无局部变量时使用唯一 marker 行，runner 不得粘贴该 marker：

```tsv
scope	owner_program	name	data_type	device	initial_value	comment	evidence	status
local	<module>	__NO_LOCAL_VARIABLES__				Confirmed no local variables.	<source snapshot or audit evidence>	no_local_variables
```

## 变量表复制/粘贴门限

```yaml
variable_grid_gate:
  symptom_is_not_root_cause:
    - clipboard_copy_failed
    - paste_or_copy_modal
  required_before_ctrl_c_or_ctrl_v:
    - foreground_window == KvVariableForm
    - local_program_combo.value == target_program
    - variable_editor_uia_signature.stable_for_ms >= 900
    - system_clipboard.openable_for_ms >= 500
    - ctrl_chord_delivery == scripts/guards/kv_ui_guard.ps1::Invoke-KvGuardedCtrlChord
  required_after_local_paste:
    - variable_editor_uia_signature.stable == true
    - save_project
    - close_reopen_copy_audit_when_AuditVariablePersistence
  forbidden:
    - raw_SendKeys_or_keybd_event_in_business_script
    - dismiss_modal_as_success
    - skip_local_copy_audit_because_custom_or_fb_type_exists
    - treat_compile_ok_as_replacement_for_enabled_copy_audit
```

如果用户在失败界面手动 `Ctrl+A`、`Ctrl+C` 成功，结论是脚本焦点/窗口状态/发键路径不同，不是变量表不可复制。修复必须在脚本自有路径内完成，并用全新项目副本至少两次 `-AuditVariablePersistence` 验证。

## 官方/库 FB 过滤

项目复刻时，官方/库 FB 是依赖，不是用户源码。模块、EtherCAT、EtherNet/IP、Universal Library 可能自动导入官方 FB，其中很多不可编辑。导出 MNM 后必须先过滤：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\filter_kv_mnm_user_sources.ps1" `
  -InputDir '<raw-mnm-dir>' `
  -OutputDir '<filtered-mnm-dir>' `
  -ProjectPath '<project.kpr>' `
  -OutDir '<filter-report-dir>'
```

```text
if MODULE_TYPE != 2:
  copy
else if name in project WsTreeEnv official/library names:
  exclude
else if name matches ^(MC_|_MC_|\[MC\]_|_\[MC\]_|ModbusTCPClient_|SocketTCP_):
  exclude
else:
  copy as user_fb
```

禁止按单个用户 FB 名称硬编码白名单。

## PLC 扩展单元

添加已注册 KV 扩展单元使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\configure_kv_expansion_units.ps1" `
  -ProjectName '<open-project-name>' `
  -ProjectPath '<project.kpr>' `
  -UnitNamePatterns 'KV-B16X*,KV-AD40V' `
  -MaxDurationSeconds 180 `
  -OutDir (Join-Path $WorkRoot 'kv_unit_config_runs')
```

路线：

```text
单元配置 -> [0] KV-X310 -> 单元编辑器 - 编辑模式 -> Alt+1 选择单元
```

不要进入 EtherCAT、EtherNet/IP 或通信设置。`WsTreeEnv.xml` 是槽位和首地址的可读证据。

## PLC 单元首地址

编辑已导入单元首地址使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\configure_kv_unit_start_addresses.ps1" `
  -ProjectName '<open-project-name>' `
  -ProjectPath '<project.kpr>' `
  -UnitName '<unit-name>' `
  -Slot 1 `
  -FirstDm 1000 `
  -FirstRelay 1000 `
  -MaxDurationSeconds 60 `
  -OutDir (Join-Path $WorkRoot 'kv_unit_address_runs')
```

路线：

```text
单元配置 -> [<slot>] <unit> -> 单元编辑器 - 编辑模式 -> 设定单元(2)
```

`FirstDm=1000` 保存为 `DM1000`。`FirstRelay=1000` 需要输入通道值 `10`，规则为 `relay_channel = FirstRelay / 100`。

`UnitName`、`Slot`、首地址值是 workflow 参数。`KV-SSC02` 只可作为特定 benchmark 输入；通用 skill 必须先确认目标项目已存在该单元，再执行首地址修改。

## EtherNet/IP 配置

网络配置意图写入：

```text
architecture\network_config.json
```

不要把 EtherCAT 或 EtherNet/IP 配置写进 MNM、变量 TSV、`TASK.md` 或 `VERSION.md`。

调度入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\configure_kv_network_from_config.ps1" `
  -ProjectName '<open-project-name>' `
  -NetworkConfigPath '<scaffold>\architecture\network_config.json' `
  -OutDir (Join-Path $WorkRoot 'kv_network_config_runs')
```

单设备入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\configure_kv_ethernet_ip_device.ps1" `
  -ProjectName '<open-project-name>' `
  -DeviceNamePattern 'SR-1000' `
  -NodeAddress 1 `
  -IpAddress '<device-ip>' `
  -VariableNamePrefix 'eip_n001' `
  -OutDir (Join-Path $WorkRoot 'kv_network_config_runs')
```

正确路线：

```text
单元配置 -> [0] KV-X310 -> EtherNet/IP -> 手动设定
```

不要使用工具栏/菜单里的通信设置；那是 PC 连接 PLC 调试用，不是项目 EtherNet/IP scanner/device 设置。变量名弹窗不能可靠批量粘贴，脚本必须逐格输入。

注册后生成的是全局结构体变量。写 ST 前用 EDS/XML cache 查询成员：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\get_kv_ethernet_ip_device_members.ps1" `
  -DeviceNamePattern 'SR-2000' `
  -VariableNamePrefix 'eip_n008' `
  -Assembly 100,101 `
  -Json
```

`Ctrl+F9` 是本任务族的转换/编译验证。`Ctrl+F2` 可能进入模拟器/监视模式，不是有效 compile oracle。

## EtherCAT 配置

单设备入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\configure_kv_ethercat_device.ps1" `
  -ProjectName '<open-project-name>' `
  -DevicePath 'KEYENCE CORPORATION,Servo Drives,SV3' `
  -BatchAxisRegistration No `
  -OutDir (Join-Path $WorkRoot 'kv_network_config_runs')
```

正确路线：

```text
单元配置 -> [0] KV-X310 -> EtherCAT -> 手动设定
```

SV3 验证路线：

1. 进入 EtherCAT 手动设定。
2. 展开 `KEYENCE CORPORATION -> Servo Drives`。
3. 选中 `SV3`。
4. 按 `Enter` 添加设备；不要拖拽。
5. 确认 EtherCAT 设置窗口。
6. 确认 Universal Library 导入 `KEYENCE_SV3`。
7. 根据 `-BatchAxisRegistration` 处理批量轴注册；默认验证值是 `No`。
8. 保存并用 `Ctrl+F9` 验证。

`ethercat.devices[].esi_path` 目前故意拒绝并返回 `KV_ETHERCAT_ESI_REGISTRATION_UNSTABLE`。自动 ESI 注册在干净项目中未形成稳定证据前，不要声称支持。

## MNM 导出稳定路线

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\workflows\export_mnm_project_copy_default_folder.ps1" `
  -ProjectPath '<project.kpr>' `
  -ExportDir '<out>\exported_mnm' `
  -OutDir '<out>\export_mnm_project_copy' `
  -WorkRoot '<out>\exported_mnm\_kv_export_workspace'
```

路线：

```yaml
export_route:
  - keep_WorkRoot_inside_ExportDir
  - copy_source_project_directory_to_WorkRoot
  - remove_old_mnm_files_from_copy
  - open_copied_kpr
  - Alt+F
  - R
  - S
  - confirm_export_option_dialog
  - accept_Browse_Folder_default_project_directory
  - copy_same_run_mnm_files_to_ExportDir
success:
  - export_mnm_project_copy_result.json.ok == true
  - actual_kv_export_dir under ExportDir
  - same_run_mnm_files under ExportDir
  - core postcheck_kvstudio_ui_safe.json.ok == true
```

不要用 `BFFM_SETSELECTIONW` 选择任意文件夹；已验证会不稳定。通过把项目副本放进 `ExportDir` 框架并接受默认选择来控制导出位置。
下游 MNM 解析脚本必须忽略 `ExportDir\_kv_export_workspace`，只把顶层导出 MNM 当作用户源码输入。

## 1:1 项目复刻 Inventory

```yaml
source_assets_required:
  plc_units: [WsTreeEnv.xml, UnitSet_string_evidence, ui_probe_if_needed]
  ethercat: [WsTreeEnv.xml_nodes, registered_device_or_esi_origin, mapping_parameter_probe]
  ethernet_ip: [WsTreeEnv.xml_nodes, local_eds_xml, node_ip_variable_probe]
  motion_axis: [WsTreeEnv.xml_axis_names, axis_setting_probe]
  mnm: [fresh_export, official_fb_filter]
import_order:
  - create_clean_project_matching_cpu
  - configure_plc_units
  - configure_ethercat
  - configure_motion_axis
  - configure_ethernet_ip
  - let_kvstudio_generate_official_fb
  - import_filtered_user_mnm
  - ctrl_f9_and_compare_inventory
```

只做 MNM 导入不是 1:1 复刻。先导出 inventory：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\export_kv_project_inventory.ps1" `
  -ProjectPath '<source-project.kpr>' `
  -MnmDir '<top-level-raw-mnm-dir>' `
  -OutDir '<run>\source_assets'
```

如果 `project_inventory.json.clone_readiness.ready_for_full_1_to_1_import=false`，不要开始完整复刻；把缺失类别拆成小 UI 突破任务。

## 结果合同

```yaml
success_requires:
  mvp:
    - mvp_result.json.ok == true
    - mvp_result.json.compile_result_contains_ok == true
    - same_run_copy_result_exists
    - variable_sets_exact_TSV_paths_recorded
  repeat:
    - repeat_result.json.ok == true
    - consecutive_passes >= 3
  existing_project_update:
    - repair_result.json.ok == true
    - source_snapshot_gate.ok == true
    - project_fingerprint_matches_current_gate
```

失败时停止并报告：

- 稳定 error code。
- 当前 step。
- evidence path。
- 下一步具体修复动作。

常见 gate code 保持英文，例如 `KV_CHECKLIST_MISSING`、`KV_SOURCE_SNAPSHOT_STALE`、`KV_MNM_SAME_NAME_IMPORT_REQUIRES_PREDELETE`、`KV_VARIABLE_PASTE_NOT_PERSISTED`。

## 参考

```yaml
references:
  ui-guard-contract.md: 修改或诊断 guarded UI input 时读取
  mvp-runner-contract.md: 解释 runner artifact/result schema 时读取
  variable-editor.md: 修改变量 TSV schema 或诊断变量编辑器粘贴时读取
```
