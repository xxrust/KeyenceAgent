# KV STUDIO 能力状态

本文件记录稳定能力分类。客户态入口以 `scripts/script_manifest.json` 为准；本文件只用于理解能力状态和提升条件。

```yaml
customer_workflow:
  customer_callable: true
  entries:
    - scripts\workflows\run_kv_mvp_scaffold.ps1
    - scripts\workflows\run_kv_mvp_repair_existing_project.ps1
    - scripts\workflows\export_mnm_project_copy_default_folder.ps1

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

pending_runner_child:
  customer_callable: false
  entries:
    - scripts\runner_children\set_fb_arguments_guarded.ps1

project_configuration:
  plc_units:
    customer_callable: false
    customer_mode_status: ROUTE_RESEARCH_REQUIRED
  ethercat:
    customer_callable: false
    customer_mode_status: ROUTE_RESEARCH_REQUIRED
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
