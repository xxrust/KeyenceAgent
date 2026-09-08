# KV STUDIO 能力状态

本文件记录稳定能力分类。客户态入口以 `scripts/script_manifest.json` 为准；本文件只用于理解能力状态和提升条件。

```yaml
customer_workflow:
  customer_callable: true
  entries:
    - scripts\workflows\run_kv_mvp_scaffold.ps1
    - scripts\workflows\run_kv_mvp_repair_existing_project.ps1
    - scripts\workflows\export_mnm_project_copy_default_folder.ps1
    - scripts\workflows\configure_kv_expansion_units.ps1
    - scripts\workflows\configure_kv_ethercat_nodes.ps1
    - scripts\workflows\set_kv_variables.ps1
    - scripts\workflows\set_kv_fb_arguments.ps1
    - scripts\workflows\export_kv_structure_definitions.ps1
    - scripts\workflows\mutate_kv_structure_definitions.ps1

regression_harness:
  customer_callable: true
  entries:
    - scripts\harnesses\run_kv_mvp_repeat.ps1

customer_non_ui_tool:
  customer_callable: true
  entries:
    - scripts\render_kv_mvp_scaffold_model.ps1
    - scripts\new_kv_existing_project_update_workspace.ps1
    - scripts\assert_kv_existing_project_snapshot.ps1
    - scripts\export_kv_project_inventory.ps1
    - scripts\filter_kv_mnm_user_sources.ps1
    - scripts\get_kv_ethernet_ip_device_members.ps1

internal_runner_child:
  customer_callable: false
  callable_by: [customer_workflow, regression_harness]
  entries:
    - scripts\runner_children\import_mnm_guarded.ps1
    - scripts\runner_children\compile_and_copy_result_bounded.ps1
    - scripts\runner_children\set_variables_guarded.ps1
    - scripts\runner_children\copy_convert_result_from_tree_handle.ps1
    - scripts\runner_children\create_project_local_guarded.ps1
    - scripts\runner_children\export_mnm_browse_default_folder_guarded.ps1
    - scripts\runner_children\configure_expansion_units_guarded.ps1
    - scripts\runner_children\set_fb_arguments_guarded.ps1
    - scripts\runner_children\export_structure_definitions_guarded.ps1

pending_runner_child:
  customer_callable: false
  entries: []

customer_api_contract:
  ui_payload_boundary:
    - set_kv_variables(project_path, global_variables_tsv, local_variables_tsv, local_program_name)
    - set_kv_fb_arguments(project_path, fb_module_name, arguments_tsv)
    - configure_kv_expansion_units(project_path, models)
    - export_kv_structure_definitions(project_path, structure_names?)
    - mutate_kv_structure_definitions(project_path, plan_path)
  guarantees:
    - agent supplies only named project targets and structured payload paths
    - workflow owns focus, menu, grid, clipboard, modal, persistence, and timing operations
    - variables use close_reopen_copyback verification on every successful public call
    - FB arguments use copyback verification on every successful public call
    - structure extraction returns member names, data types, array dimensions, raw columns, and comments with same-run timing evidence
    - structure mutation accepts ordered create/update/delete operations, creates folders through the project-tree context menu, excludes `(System)`, and verifies every changed structure by close/reopen copy-back

structure_mutation:
  customer_callable: true
  entry: scripts\workflows\mutate_kv_structure_definitions.ps1
  plan_schema:
    folder_operations: [{ action: create, parent_path: ["数据类型"], name: "Folder" }]
    structure_operations: [{ action: create|update|delete, parent_path: ["数据类型", "Folder"], name: "Type", kind: structure|tuple, members: [{ name: "member", data_type: "BOOL" }] }]
  rules:
    - `(System)` is read-only and is never created, updated, or deleted
    - create operations execute in plan order; custom nested member types must already exist or be created earlier in the same plan
    - every create/update is reopened and copied back before success is reported
    - a failed dialog/focus/persistence check stops the workflow and writes failure.json

known_route_limits:
  mnm_import:
    status: conditional
    fresh_project_behavior: ROUTE_RESEARCH_REQUIRED
    evidence: H:\\kvOp\\generic_replication_api_regression\\run_20260903_01\\workflow\\GenericReplica_20260903\\artifacts\\import_mnm_1\\run.log
    note: >-
      A fresh generic project reached the published import workflow with a
      valid editor foreground, but neither guarded Alt+F,R,R nor the PID-bound
      UIA File -> Mnemonic List -> Read route produced a standard file-open
      dialog. Existing-project success evidence must not be generalized to
      fresh projects until this route is independently repaired and repeated.
    policy: >-
      Keep the failure gate and stop the workflow; do not add sample-specific
      coordinates, fixed module names, direct ladder input, or relaxed
      persistence/compile checks as a workaround.

project_configuration:
  plc_units:
    customer_callable: true
    customer_workflow: scripts\workflows\configure_kv_expansion_units.ps1
    supported_models: dynamic_catalog_lookup
    verified_models: [KV-B16X, KV-C32X, KV-C64X, KV-B8RC, KV-B16T]
    lookup_method: owner-data flat catalog keyboard scan with static 698 model oracle
    dynamic_catalog_status: runtime lookup; any model currently exposed by the compatible flat catalog is eligible
    verification: UnitSet.ue2 same-run readback plus clean main-window end state
    per_module_budget_seconds: 10
  ethercat:
    customer_callable: true
    customer_workflow: scripts\workflows\configure_kv_ethercat_nodes.ps1
    supported_models: any uniquely matching catalog_model already present in the current KV STUDIO EtherCAT catalog
    required_input: nodes JSON with unique node_address and catalog_model
    verification: per-node editor readback plus exact node/model WsTreeEnv.xml readback and clean main-window end state
    per_node_budget_seconds: 10
    exclusions: [missing_ESI, ambiguous_catalog_match, unknown_catalog_model]
  ethernet_ip:
    customer_callable: false
    customer_mode_status: ROUTE_RESEARCH_REQUIRED
  esi_registration:
    customer_callable: false
    status_code: KV_ETHERCAT_ESI_REGISTRATION_UNSTABLE
```

```yaml
promotion_to_customer_workflow_step:
  required:
    - explicit_parameters
    - result_json_schema
    - stable_error_codes
    - same_run_evidence_dir
    - timeout
    - clean_end_state_check
    - deterministic_route_branch
    - external_patch_review_for_script_changes
    - repeat_pass_on_disposable_project >= 2
```
