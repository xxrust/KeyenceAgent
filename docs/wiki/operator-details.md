# KV STUDIO Operator 接口细则

## 执行链

```text
agent 输入 -> customer workflow -> UI/agent Gate -> flat executor -> runner child
                                      |                           |
                                      +------ run.log ------------+--> result.json + receipt
```

### 扩展单元

调用 `configure_kv_expansion_units.ps1 -ProjectPath <kpr> -Models <string[]>`。先用 `-PlanOnly` 检查解析后的型号数组，再执行真实 workflow。验收必须同时包含模型、槽位/首地址（若接口提供）和保存状态；仅看到项目树节点不算成功。

### EtherCAT

调用 `configure_kv_ethercat_nodes.ps1 -ProjectPath <kpr> -NodesConfigPath <json>`。JSON schema 为 `schema_version: 1`、`batch_axis_registration` 和 `nodes[{node_address,catalog_model}]`。节点号必须唯一且为 1–65535。保存后应从项目文件和 UI 读回同一地址/型号；KV STUDIO 若自行压缩拓扑，必须报告为不满足源项目复刻，而不是改写期望值。

## 证据等级

| 等级 | 含义 |
|---|---|
| PlanOnly | 参数、Gate 顺序和执行计划正确；没有改变桌面项目 |
| 契约测试 | 结果文件、陈旧证据、失败传播等机械保证 |
| 真实回归 | 对指定项目实际操作并读回语义字段 |
| 发布 | manifest 标记 `published` 且 `customer_callable=true`，并有对应回归证据 |

当前扩展单元和 EtherCAT 为“发布接口 + PlanOnly/契约证据 + 整理后真实回归待补”。
