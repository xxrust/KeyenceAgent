# 项目配置参考

客户态配置入口以 `scripts\script_manifest.json` 中的 `customer_workflow` 为准。未出现在 manifest 客户态 workflow 中的配置能力，在客户态返回 `ROUTE_RESEARCH_REQUIRED`。

```yaml
project_configuration_policy:
  entry_source: scripts\script_manifest.json
  customer_mode_condition: manifest.classes.customer_workflow contains requested capability
  absent_customer_workflow_status: ROUTE_RESEARCH_REQUIRED
```

网络配置意图写入：

```text
architecture\network_config.json
```

EtherCAT 和 EtherNet/IP 配置数据属于项目架构配置，不写入 MNM、变量 TSV、`TASK.md` 或 `VERSION.md`。

EtherNet/IP 设备注册后会生成全局结构体变量。写 ST 前可用 EDS/XML cache 查询成员：

```powershell
$ResolvedToolPath = '<path resolved from manifest customer_non_ui_tool get_kv_ethernet_ip_device_members>'
powershell -NoProfile -ExecutionPolicy Bypass -File $ResolvedToolPath `
  -DeviceNamePattern 'SR-2000' `
  -VariableNamePrefix 'eip_n008' `
  -Assembly 100,101 `
  -Json
```

`get_kv_ethernet_ip_device_members.ps1` 是成员查询工具，不是设备配置 workflow。

```yaml
configuration_script_status:
  plc_units:
    evidence_source: references\capability-status.md
    customer_mode: configure_kv_expansion_units workflow
    supported_models: runtime catalog lookup (any model exposed by the compatible KV STUDIO catalog)
    verified_models: [KV-B16X, KV-C32X, KV-C64X, KV-B8RC, KV-B16T]
    required_success_evidence: [UnitSet.ue2 same-run readback, project-tree/UI confirmation, clean main-window end state]
  ethercat:
    evidence_source: references\capability-status.md
    customer_mode: configure_kv_ethercat_nodes workflow
    supported_models: any uniquely matching model already present in the current KV STUDIO EtherCAT catalog
    input_schema:
      schema_version: 1
      batch_axis_registration: Yes_or_No
      nodes:
        - node_address: integer_1_to_65535_unique
          catalog_model: exact_or_unique_catalog_search_text
    required_success_evidence: [node-address editor readback, exact node/model WsTreeEnv.xml readback, clean main-window end state]
    per_node_budget_seconds: 10
    idempotency: saved mappings with the same address and model are reported as already_persisted and are not inserted again; an occupied address with a different model fails with KV_ETHERCAT_NODE_ADDRESS_CONFLICT
    preconditions: ProjectPath must exist, KV STUDIO must show the matching saved project with no modal/configuration window, and the EtherCAT subtree snapshot must be available
  ethernet_ip:
    evidence_source: references\capability-status.md
    customer_mode: requires_manifest_customer_workflow
  esi_registration:
    status_code: KV_ETHERCAT_ESI_REGISTRATION_UNSTABLE
    mode: research
```

Root-level project configuration scripts are research/special-validation tools until manifest promotes a matching customer workflow.
