# 1:1 项目复刻

1:1 复刻不是 MNM-only。MNM 是程序源码段，必须在项目配置资产明确后导入。

## 规范快照入口

全项目复刻先调用 manifest capability `read_only_project_text_snapshot`。同次运行生成的
`snapshot/project/` 是人类审核、Agent 阅读和恢复规划的共同语义入口：

```text
project/
├─ 功能块/<分组>/<FB>/{body.mnm,arguments.tsv,locals.tsv,entity.json}
├─ 程序/<工作站>/<模块类别>/<模块>/{body.mnm,locals.tsv,entity.json}
├─ 程序/<工作站>/<模块类别>/{folder.json,entity.json}  # 即使目录为空也保留
├─ 配置/{单元,EtherCAT,全局变量}/
├─ 类型/
└─ _index/{entities.jsonl,restore_plan.json,materialization_result.json}
```

读取前检查 `source_snapshot_manifest.json` 的 fingerprint、`status`、
`semantic_project_status` 和 `semantic_warnings`。自动化使用 `entity.json` 与
`_index/restore_plan.json`；目录树服务于导航和审核。`text/` 保留原子文本产物，
`raw/` 保留同次 workflow 证据。不要再次解析这些层来另造一棵竞争性的项目树。

```yaml
source_assets_required:
  semantic_index: [project/_index/entities.jsonl, project/_index/restore_plan.json]
  plc_units: [project/配置/单元, raw_evidence_if_needed]
  ethercat: [project/配置/EtherCAT, registered_device_or_esi_origin, mapping_parameter_probe]
  ethernet_ip: [WsTreeEnv.xml_nodes, local_eds_xml, node_ip_variable_probe]
  motion_axis: [WsTreeEnv.xml_axis_names, axis_setting_probe]
  variables_and_types: [project/配置/全局变量, project/类型]
  programs_and_fbs: [project/程序, project/功能块, official_fb_filter]
```

`ui_probe_if_needed`、`mapping_parameter_probe` 等 probe evidence 只能来自已发布 workflow/gate，或来自用户明确授权后的 `research_mode`。

完整快照的全局变量必须来自 `snapshot_kv_global_variables_all_groups.ps1`。该 workflow 在变量组选择器中全选后复制整表，输出 `global_variables_all_groups.tsv`（同时提供兼容名 `global_variables_raw.tsv`）；因此 `project/配置/全局变量/variables.tsv` 包含所有变量组，而不是仅 `(Default)`。

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

复刻顺序以 `project/_index/restore_plan.json` 为准；下列仅是高层阶段约束：

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
任一 `entity.json.status` 含 `failed`、`missing`、`partial`、`unresolved`，或根 manifest
存在相关 `semantic_warnings` 时，也不得把对应资产声明为可完整恢复。
