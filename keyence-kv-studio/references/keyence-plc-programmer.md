# keyence-plc-programmer

> 本文由原 keyence-plc-programmer/SKILL.md 转为统一入口 skill 的 reference。路径按 keyence-kv-studio 包内结构解析。

# KEYENCE PLC 编程

## 职责边界

```yaml
use_for:
  - PLC_logic_design
  - ST_or_ladder_authoring
  - MNM_generation_or_repair
  - variable_manifest_design
  - official_FB_policy
  - source_snapshot_reasoning
  - compile_error_fixing
delegate_to:
  kv-studio-operator:
    - KV_STUDIO_UI_operation
    - MNM_import_export
    - variable_editor_operation
    - project_create_or_compile_runner
  kv-studio-kb-programming:
    - KEYENCE_Wiki_V2_query
```

本 skill 负责“程序和项目结构怎么写”；KV STUDIO 桌面操作由 `kv-studio-operator` 的脚本执行。

## 工程质量门限

```yaml
quality_gate:
  invariant: validation_artifacts_match_project_semantics
  required:
    - resolved_variable_and_device_manifest
    - fresh_source_snapshot_for_existing_project
    - compile_or_conversion_evidence_from_KV_STUDIO
    - acceptance_criteria_preserved_until_completion
  audit_when_gate_is_challenged:
    required:
      - written_failure_evidence
      - exact_gate_rule_under_review
      - proof_artifact_is_semantically_valid
      - independent_subagent_strict_audit_before_import_or_compile_claim
    if_subagent_unavailable: report_gate_review_blocker
  blocking_conditions:
    unresolved_mnm_variable_reference: report_and_fix_manifest
    incomplete_variable_manifest: complete_manifest_before_import
    stale_or_stub_source_snapshot: refresh_source_snapshot
```

- 官方参考项目用于确认标准结构、调用方式、变量形态和设备交互意图。
- 官方 FB 作为库依赖导入，保持官方来源、官方名称和官方行为。
- 现有项目的复刻、修复、优化或功能追加，先把当前 `.kpr` 绑定到新鲜 source snapshot。
- 新鲜 source snapshot 包含相关 MNM、变量清单、程序/模块 inventory、单元/设备证据、转换/导出证据。
- 导出受阻时记录 blocker 和界面证据，先恢复可验证导出链路。
- 用户程序、用户 FB 和业务逻辑通过 MNM、变量 manifest 和 KV STUDIO 导入链路重建。
- 变量表显式重建；MNM import 后通过变量 manifest 消解全部变量引用。
- 转换/编译通过后，当前结果进入可交付状态。
- KEYENCE 专有语法、FB 调用、设备映射、模块行为使用 Wiki V2 或当前项目导出证据确认。

## 标准流程

```yaml
workflow:
  - identify_target:
      required: [CPU_family, unit_config, protocol_or_axis, language_mode, acceptance]
  - query_wiki_v2:
      when: KEYENCE_specific_logic_or_syntax
  - export_source_snapshot:
      when: existing_project
      required:
        - fresh_MNM_for_relevant_programs
        - global_and_local_variables
        - FB_instances_and_data_types
        - program_tree_and_unit_inventory
        - compile_or_export_evidence
  - create_git_workspace:
      folders: [source_snapshot, work, validation]
  - build_logic_map:
      include: [programs, tasks, FBs, devices, variables, state_transitions]
  - edit_sources:
      files: [MNM, variable_manifest, architecture_inventory]
  - import_and_compile:
      via: kv-studio-operator
  - fix_errors:
      source: copied_KV_STUDIO_error_text
  - report:
      only_after: compile_passes
```

常用命令保留原样：

```powershell
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "exact token or user wording" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence

powershell -NoProfile -ExecutionPolicy Bypass -File <keyence-kv-studio>\scripts\keyence-plc-programmer\kvtool.ps1 list
powershell -NoProfile -ExecutionPolicy Bypass -File <keyence-kv-studio>\scripts\keyence-plc-programmer\kvtool.ps1 manifest
powershell -NoProfile -ExecutionPolicy Bypass -File <keyence-kv-studio>\scripts\keyence-plc-programmer\init_project_snapshot_workspace.ps1 -TaskRoot <task-root> -TaskName <name> -ProjectPath <original.kpr>
```

## 可复用脚本

```yaml
automation_source:
  rule: use_scripts_from_skill_path
  output_locations_are_evidence_only:
    - <configured-work-root>
    - <temp-derived-work-root>
    - <remote-task-root-from-config>
    - VM_evidence_folders
scripts:
  kvtool.ps1: central_command_surface
  resolve_kvstudio_local.ps1: resolve_Kvs_exe
  create_project_local.ps1: create_disposable_project
  local_kvstudio_acceptance.ps1: five_minute_local_acceptance
  import_mnm.ps1: MNM_import_UI_route
  export_mnm.ps1: MNM_export_UI_route
  roundtrip_mnm.ps1: hard_MNM_import_export_fingerprint_gate
  validate_fb_reuse_guard.ps1: user_FB_interface_and_device_leak_gate
  init_project_snapshot_workspace.ps1: snapshot_git_workspace
  new_mnm_smoke.ps1: minimal_MNM_smoke
  convert_collect.ps1: open_project_ctrl_f9_collect_evidence
  run_vm103_interactive_script_ssh.ps1: run_UI_script_in_logged_on_VM
```

脚本来源固定为 skill 目录；输出目录只保存证据和产物。

## KV STUDIO UI 安全

```yaml
ui_safety:
  ladder_editor: hazardous_input_surface
  required_before_input:
    - intended_dialog_proven
    - focus_proven
    - no_inline_ladder_edit_bar
  keyboard_input_requires:
    - target_dialog_identity
    - target_control_identity
    - post_action_evidence
```

出现内联梯形图编辑条、未验证文件对话框、焦点丢失或弹窗时，保存证据并恢复到可证明的目标对话框；真实项目的点击依据来自 UIA/Win32 控件身份和动作后证据。

## MNM 编写规则

- MNM 修改保持最小化，并贴近 KV STUDIO 导出格式。
- 普通用户程序使用 `;MODULE_TYPE:0`。
- 用户 FB 使用 `;MODULE_TYPE:2`。
- 含中文名称/注释的 MNM 按目标 Windows 的系统 ANSI 编码写入；中文 Windows 通常是 CP936。
- ST 程序体保持为 KV STUDIO 接受的可执行语句；变量声明由 KV STUDIO 变量表承载。
- 变量声明属于 KV STUDIO 变量表，不属于默认 ST 程序体文本。
- FB 实例名、变量名要稳定，并与变量 manifest 同步。
- 官方指令/FB 调用签名必须按 Wiki V2 或导出证据保持一致。

## FB 可复用性 Guard

Wiki V2 已确认：

- `KvsHARD8000.pdf#p225-227`：FB 自变量类型包括 `IN`、`OUT`、`IN-OUT`、`UNIT`；自变量名称可在 FB 中像局部变量一样使用。
- `KvsHARD8000.pdf#p240-243` / `KVSREF.pdf#p194-203`：FB/FBCALL/FBSTRT 调用时按自变量绑定软元件、变量、标签或常数；`OUT`、`IN-OUT` 不能绑定常数。
- `FBCALL_FBSTRT.htm#示例程序`、`FBSTRT.htm`：`DM0`、`MR000` 等固定软元件出现在调用点的自变量绑定示例中，不是 FB 内部状态模板。
- `KVSHARDX3H.pdf#p422-423`：模块、FB、功能内可使用局部变量/局部系统变量。
- `ScriptUse.pdf#p96-98`：功能块是项目内可多次反复使用、可通用的程序块。

```yaml
fb_reuse_guard:
  applies_when:
    - authoring_user_FB
    - MNM_contains: ";MODULE_TYPE:2"
  model:
    caller_owns:
      - real_device_binding
      - module_or_axis_mapping
      - FB_instance_variable
    FB_owns:
      - reusable_behavior
      - explicit_arguments
      - local_state
  required_before_body:
    - argument_table:
        columns: [name, direction, data_type, caller_binding, comment]
        directions: [IN, OUT, IN-OUT, UNIT]
    - local_variable_table:
        columns: [name, data_type, initial_value, retain, comment]
    - instance_plan:
        columns: [caller_program, instance_name, FB_type]
  caller_binding_items:
    - business_DM_R_MR_LR_CR_EM_FM_X_Y_T_C_devices
    - fixed_device_addresses
    - module_or_axis_devices
    - global_integration_variables
  allowed_inside_user_FB_body:
    - arguments
    - local_variables
    - constants
    - documented_local_system_variables
    - documented_special_devices_with_contract
  device_contract_exception:
    required:
      - device
      - reason
      - wiki_or_project_export_evidence
      - proof_reuse_boundary_is_still_valid
```

导入或声称用户 FB 有效前运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <keyence-kv-studio>\scripts\keyence-plc-programmer\validate_fb_reuse_guard.ps1 `
  -Path <mnm-file-or-folder>
```

确需在 FB 内部直接使用特殊软元件时，必须传入 contract：

```json
{
  "allowed_devices": [
    {
      "module": "FB_ModuleName",
      "device": "CR2012",
      "reason": "documented operation flag required by this FB contract",
      "evidence": "FBCALL_FBSTRT.htm#运算标志"
    }
  ]
}
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <keyence-kv-studio>\scripts\keyence-plc-programmer\validate_fb_reuse_guard.ps1 `
  -Path <mnm-file-or-folder> `
  -ContractPath <fb-device-contract.json>
```

失败码 `KV_FB_REUSE_DEVICE_LEAK` 表示 FB 体内出现固定软元件泄漏。修正方式是把真实设备移到调用方绑定，把内部状态移到局部变量，把外部交互声明为自变量或 contract。

## 变量 Manifest

```yaml
variable_manifest_required:
  global_variables: [name, data_type, device, comment]
  local_variables: [program_name, name, data_type, comment]
  FB_instances: [instance_name, FB_type, scope, owner_program]
  device_backed_items: [device_or_register, module_or_axis_basis, evidence]
  unknowns: [CPU, unit, slot, axis, user_mapping]
completion_gate:
  - all_MNM_references_resolved_by_manifest
  - each_local_variable_has_owner_program
  - each_data_type_supported_by_KV_STUDIO_or_documented_evidence
```

KV STUDIO 变量表粘贴 schema：

```yaml
global_row:
  columns: [group_name, variable_name, data_type, assignment_target, value, retain, constant, OPC_UA, file_export, comment_1]
local_row:
  columns: [variable_name, data_type, value, retain, constant, file_export, comment_1]
```

局部变量使用局部变量 schema；全局变量专用列只出现在全局变量表。遇到变量名覆盖确认时，记录当前行、目标程序和弹窗文本，并重新定位变量表行。

## 现有项目快照与版本控制

```yaml
snapshot_layout:
  source_snapshot/<timestamp>/mnm: fresh_MNM_exports
  source_snapshot/<timestamp>/variables: global_local_FB_types_arrays_devices
  source_snapshot/<timestamp>/inventory: program_tree_units_comments_sidecar_evidence
  work: generated_or_edited_sources
  validation: compile_reports_screenshots_exported_post_import_MNM
git_states:
  - baseline_original_snapshot
  - work_generated_fix
  - validation_import_compile_evidence
```

如果没有 git，创建 `BASELINE`、`WORK`、`VALIDATION` 三个时间戳目录和 `diff_report.md`，并报告回滚能力弱于真实 git 历史。

## 参考项目复刻

```yaml
reference_reproduction:
  required:
    - open_exact_source_project
    - export_fresh_MNM_variable_module_snapshot
    - put_snapshot_under_git
    - classify_elements
    - import_only_official_FBs_directly
    - recreate_user_logic_as_MNM
    - recreate_variables_from_manifest
    - compile_and_compare
  element_classification:
    official_FB: import_if_needed_keep_official
    user_program_logic: recreate_as_MNM
    variable_or_device_table: reconstruct_through_variable_editor
    unit_or_device_mapping: set_through_project_configuration
```

声明复刻有效前读取 `references/keyence-plc-programmer/reproduction-gate.md`。

## 证据优先级

```yaml
evidence_priority:
  - htmlhelp_or_chm
  - table
  - dockinghelp
  - pdf
  - official_reference_project_as_behavior_oracle
  - htmlnavi_meta_navigation_only
```

官方参考项目用于建立行为、结构、变量和设备交互的 oracle。

## 完成报告

报告必须包含：

- Wiki 查询和证据类型。
- 在 KV STUDIO 中打开的原项目路径、导出时间和 source snapshot 路径。
- git 工作目录、baseline 状态、关键 diff 或 commit。
- 检查过的官方参考路径和元素。
- 直接导入的官方 FB。
- 原项目新鲜导出的 MNM、创建/编辑/导入的 MNM。
- 变量 manifest 来源、重建状态和未解决变量。
- 模块/单元/设备 inventory 来源和变更。
- `Ctrl+F9` 转换/编译结果及错误文本。
- VM 或本机验证产物路径。
- CPU、单元、轴或设备映射的剩余歧义。
