---
name: keyence-kv-studio
description: KEYENCE KV STUDIO/KV PLC 统一入口。用于基恩士 KV 项目的任务路由：本机 KEYENCE Wiki V2 查询、PLC/ST/梯形图/MNM/FB/变量设计、KV STUDIO 桌面 workflow 操作、导入导出、转换/编译验证、现有 `.kpr` 项目修复或复刻。按任务类型读取 `references/kv-studio-kb-programming.md`、`references/keyence-plc-programmer.md` 或 `references/kv-studio-operator.md`，并运行 `scripts/` 中的配套脚本。
---

# KEYENCE KV STUDIO 统一入口

## 验证范围

```yaml
validated_target:
  os: [Windows 10, Windows 11]
  kv_studio: KVS12
  note: other_versions_are_unverified
```

```yaml
role: router
load_policy:
  first: this_SKILL
  then: matched_reference_module
  details: references/routing.md
modules:
  kb:
    name: kv-studio-kb-programming
    reference: references/kv-studio-kb-programming.md
    scripts: scripts/kv-studio-kb-programming
    owns:
      - KEYENCE_Wiki_V2_query
      - instruction_FB_FUN_device_module_protocol_facts
  programmer:
    name: keyence-plc-programmer
    reference: references/keyence-plc-programmer.md
    scripts: scripts/keyence-plc-programmer
    owns:
      - ST_ladder_MNM_FB_variable_authoring
      - source_snapshot_reasoning
      - compile_error_fix_plan
  operator:
    name: kv-studio-operator
    reference: references/kv-studio-operator.md
    scripts: scripts/kv-studio-operator
    owns:
      - KV_STUDIO_customer_workflow
      - MNM_import_export
      - variable_editor_operation
      - conversion_compile_result_collection
```

## Route

```yaml
route:
  knowledge_claim:
    use: kv-studio-kb-programming
    when:
      - KEYENCE_specific_syntax
      - FB_or_FUN_signature
      - device_or_buffer_map
      - module_or_axis_behavior
      - EtherNet_IP_or_EtherCAT_or_socket_fact

  plc_source_work:
    use: keyence-plc-programmer
    when:
      - write_or_repair_ST_ladder_MNM
      - design_FB_interface_or_local_variables
      - rebuild_global_or_local_variables
      - filter_official_FB_from_user_source
      - analyze_compile_errors

  kvstudio_operation:
    use: kv-studio-operator
    gate:
      manifest: scripts/kv-studio-operator/script_manifest.json
      require:
        - customer_callable == true
        - class in [customer_workflow, customer_scaffold_tool, customer_non_ui_tool, regression_harness, gate]
    when:
      - open_create_or_repair_kpr
      - import_or_export_MNM
      - paste_global_or_local_variables
      - run_Ctrl_F9_conversion_compile
      - copy_conversion_result

  multi_stage_project:
    order:
      - kv-studio-kb-programming if KEYENCE facts are needed
      - keyence-plc-programmer builds or repairs source artifacts
      - kv-studio-operator runs published workflow
      - keyence-plc-programmer interprets compile feedback

  project_configuration:
    order:
      - kv-studio-kb-programming confirms module_protocol_or_axis_facts
      - kv-studio-operator checks manifest customer_workflow for matching requested_configuration_type
      - kv-studio-operator runs matching published customer_workflow only
    matching_rule:
      accepted_class: customer_workflow
      accepted_entry: path_or_capability_matches_requested_configuration_type
      non_ui_query_tools_are_not_configuration_workflows:
        - get_kv_ethernet_ip_device_members.ps1
    missing_operator_capability: ROUTE_RESEARCH_REQUIRED
```

## Contracts

```yaml
kvstudio_ui:
  entry_source: scripts/kv-studio-operator/script_manifest.json
  customer_mode:
    run_only:
      - customer_callable == true
      - class in [customer_workflow, customer_scaffold_tool, customer_non_ui_tool, regression_harness, gate]
  project_configuration:
    require_manifest_capability: true
    missing_capability_status: ROUTE_RESEARCH_REQUIRED
  end_state:
    require_clean_KV_STUDIO_state: true

existing_project:
  before_repair_or_replication:
    require_fresh_snapshot: true
    include:
      - MNM
      - global_variables
      - local_variables
      - FB_inventory
      - unit_or_device_inventory_when_available

FB_policy:
  official_or_library_FB: dependency
  user_FB: source
  user_FB_body:
    prefer:
      - arguments
      - local_variables
      - documented_contract_devices
    guard: scripts/keyence-plc-programmer/validate_fb_reuse_guard.ps1

evidence:
  final_claim_requires:
    - same_run_artifact
    - conversion_or_compile_result_when_applicable
    - unresolved_items_report
```

## References

```yaml
read_when_routing_is_ambiguous:
  - references/routing.md
read_when_module_details_are_needed:
  - references/kv-studio-kb-programming.md
  - references/keyence-plc-programmer.md
  - references/kv-studio-operator.md
read_when_specific_detail_is_needed:
  kv-studio-kb-programming:
    - references/kv-studio-kb-programming/retrieval-playbook.md
  keyence-plc-programmer:
    - references/keyence-plc-programmer/reproduction-gate.md
  kv-studio-operator:
    - references/kv-studio-operator/capability-status.md
    - references/kv-studio-operator/project-configuration.md
    - references/kv-studio-operator/project-replication.md
    - references/kv-studio-operator/sample-project.md
    - references/kv-studio-operator/fb-filter.md
    - references/kv-studio-operator/variable-editor.md
sample_assets:
  kvx_sample_project: assets/kv-studio-operator/KVX样例程序_v100
```
