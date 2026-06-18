# 路由细节

## Reference 模块

```yaml
modules:
  kv-studio-kb-programming:
    reference: references/kv-studio-kb-programming.md
    scripts: scripts/kv-studio-kb-programming
    load_for:
      - KEYENCE_Wiki_V2
      - syntax_instruction_FB_FUN
      - device_buffer_module_protocol_fact
    evidence: wiki_v2_query_result

  keyence-plc-programmer:
    reference: references/keyence-plc-programmer.md
    scripts: scripts/keyence-plc-programmer
    load_for:
      - PLC_source_authoring
      - MNM_variable_FB_design
      - existing_project_source_snapshot
      - compile_error_repair
    evidence: source_snapshot_and_compile_result

  kv-studio-operator:
    reference: references/kv-studio-operator.md
    scripts: scripts/kv-studio-operator
    load_for:
      - KV_STUDIO_UI_workflow
      - import_export_MNM
      - variable_editor
      - conversion_compile_copy_result
      - project_configuration_by_manifest
    evidence: same_run_result_json_and_evidence_dir
    manifest: scripts/kv-studio-operator/script_manifest.json
```

## 判定函数

```yaml
classify(request):
  KEYENCE_fact_triggers:
    words:
      - instruction
      - FB
      - FUN
      - device
      - buffer
      - module
      - unit
      - axis
      - EtherNet/IP
      - EtherCAT
      - socket
      - KV_STUDIO_syntax
    actions:
      - explain
      - confirm
      - map
      - choose_model_or_parameter
      - write_code_using_KEYENCE_specific_semantics

  source_change_triggers:
    artifacts:
      - ST
      - ladder
      - MNM
      - global_variables
      - local_variables
      - user_FB
      - variable_manifest
    actions:
      - create
      - edit
      - repair
      - filter
      - analyze_compile_error

  KV_STUDIO_operation_triggers:
    actions:
      - open_kpr
      - create_project
      - import_MNM
      - export_MNM
      - paste_variables
      - convert_or_compile
      - copy_convert_result

  if request matches KEYENCE_fact_triggers:
    route.append(kv-studio-kb-programming)

  if request matches source_change_triggers:
    route.append(keyence-plc-programmer)

  if request matches KV_STUDIO_operation_triggers:
    route.append(kv-studio-operator)

  if request matches configure_project:
    route.prepend_if_missing(kv-studio-kb-programming)
    route.append(kv-studio-operator)
    require(script_manifest.customer_workflow_has_matching_requested_configuration_type)
    if capability_missing:
      return ROUTE_RESEARCH_REQUIRED

  return route_in_execution_order
```

## 常见任务

```yaml
tasks:
  answer_instruction_or_FB_usage:
    route: [kv-studio-kb-programming]

  write_new_ST_or_MNM:
    route:
      - kv-studio-kb-programming: when_KEYENCE_specific_syntax_or_FB_or_device_is_used
      - keyence-plc-programmer

  create_new_project_and_compile:
    route: [keyence-plc-programmer, kv-studio-operator]

  repair_existing_kpr:
    route:
      - kv-studio-operator: export_fresh_snapshot
      - keyence-plc-programmer: analyze_and_edit_source
      - kv-studio-operator: import_and_compile
      - keyence-plc-programmer: fix_compile_errors

  replicate_existing_kpr:
    route:
      - kv-studio-operator: export_inventory_and_MNM
      - keyence-plc-programmer: classify_user_source_variables_official_FB
      - kv-studio-operator: recreate_with_customer_workflows
    gate:
      full_config_replication_requires_customer_workflows: true

  configure_EtherNet_IP_EtherCAT_or_units:
    route: [kv-studio-kb-programming, kv-studio-operator]
    gate:
      manifest_customer_workflow_required: true
      non_ui_query_tool_is_not_configuration_workflow:
        - get_kv_ethernet_ip_device_members.ps1
      missing: ROUTE_RESEARCH_REQUIRED
```

## 输出状态

```yaml
status:
  DONE:
    requires:
      - requested_artifact_created_or_updated
      - validation_evidence_when_applicable
      - unresolved_items_empty_or_reported

  ROUTE_RESEARCH_REQUIRED:
    use_when:
      - requested_KV_STUDIO_project_configuration_has_no_customer_workflow
      - customer_workflow_failure_requires_UI_route_research
    report:
      - requested_capability
      - checked_manifest_entry
      - missing_or_failed_workflow
      - evidence_path_if_any
```
