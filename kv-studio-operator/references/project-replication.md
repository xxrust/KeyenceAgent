# 1:1 项目复刻

1:1 复刻不是 MNM-only。MNM 是程序源码段，必须在项目配置资产明确后导入。

```yaml
source_assets_required:
  plc_units: [WsTreeEnv.xml, UnitSet_string_evidence, ui_probe_if_needed]
  ethercat: [WsTreeEnv.xml_nodes, registered_device_or_esi_origin, mapping_parameter_probe]
  ethernet_ip: [WsTreeEnv.xml_nodes, local_eds_xml, node_ip_variable_probe]
  motion_axis: [WsTreeEnv.xml_axis_names, axis_setting_probe]
  mnm: [fresh_export, official_fb_filter]
```

`ui_probe_if_needed`、`mapping_parameter_probe` 等 probe evidence 只能来自已发布 workflow/gate，或来自用户明确授权后的 `research_mode`。

导出 inventory：

```powershell
$ResolvedToolPath = '<path resolved from manifest customer_non_ui_tool export_kv_project_inventory>'
$SampleProjectPath = Join-Path $SkillRoot 'references\KVX样例程序_v100\KVX样例程序_v100.kpr'
powershell -NoProfile -ExecutionPolicy Bypass -File $ResolvedToolPath `
  -ProjectPath $SampleProjectPath `
  -MnmDir '<top-level-raw-mnm-dir>' `
  -OutDir '<run>\source_assets'
```

客户项目复刻时，将 `ProjectPath` 替换为用户提供的项目；测试和示例使用 `references\sample-project.md` 定义的内置样例。

复刻顺序：

```yaml
import_order:
  - create_clean_project_matching_cpu
  - configure_plc_units: customer_workflow_or_ROUTE_RESEARCH_REQUIRED
  - configure_ethercat: customer_workflow_or_ROUTE_RESEARCH_REQUIRED
  - configure_motion_axis: customer_workflow_or_ROUTE_RESEARCH_REQUIRED
  - configure_ethernet_ip: customer_workflow_or_ROUTE_RESEARCH_REQUIRED
  - let_kvstudio_generate_official_fb
  - import_filtered_user_mnm
  - compile_and_compare_inventory
```

`project_inventory.json.clone_readiness.ready_for_full_1_to_1_import=false` 时，复刻状态为 `ROUTE_RESEARCH_REQUIRED`。
