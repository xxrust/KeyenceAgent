# KVX 样例 1:1 复刻进展（2026-10-24）

目标：把 `KVX样例程序_v100` 的 24 个扫描程序 + 4 个用户 FB 复刻成 scaffold 模型，
用现有 new_project execution plan 在真实 KV STUDIO 上跑通。

## 已完成

### 1. 模型与校验

- 生成脚本：`C:\kvrun\sample_model\build_model.ps1`
- 数据来源：`C:\kvrun\snapshot_sample\out2\snapshot_20261024_091005`
- 产物：`C:\kvrun\sample_model\scaffold.model.json` → `scaffold\`
- 内容：28 个 MNM（24 程序 + 4 FB）、43 个可执行全局变量、293 行局部变量、
  4 张 FB 自变量表、26 个用户结构
- 校验：`validate_kv_mvp_scaffold.ps1` **ok=true**（模型重渲染逐字节一致），
  证据 `C:\kvrun\sample_model\validate7\scaffold_validation.json`

模型声明 `variables.allowed_custom_data_types`（50 个目标工程已有的类型：
用户结构 + `TON`/`TOF`/`R_TRIG`/`MC_*`/`ModbusTCPClient_*`）。
渲染器把它并入 `scaffold.json`，校验器用它覆盖局部变量与 FB 自变量检查。

### 2. 结构体（DUT）导入

- 生成脚本：`C:\kvrun\sample_model\build_structures.ps1`
- 产物：`C:\kvrun\sample_model\structure_plan.json`（26 个 create 操作，按依赖排序）
- 计划集成：`new_kv_mvp_execution_plan.ps1 -StructurePlanPath <plan>` 增加
  `import_structures` 步骤（create_project 之后、模块导入之前）

实跑证据：

- `KVStructTest4`（独立工程）：26/26 结构创建并 copy-back 校验通过
- `KVXSampleRebuild4`（完整 plan）：26/26 结构在 12:23–12:36 内创建完成

### 3. 完整 plan 跑到变量写入

`KVXSampleRebuild4` 执行顺序：

```
validate → create → import_structures（26/26）
→ 28 个模块导入（12:36–12:42）→ 删除默认 Main → 模块放置
→ set_fb_arguments ×4（12:42:54，全部成功）
→ set_variables_FB_Cylinder 失败
```

失败码：`KV_VARIABLE_REPLACE_UNEXPECTED_MODAL`。全局变量粘贴触发的是
KV 的数据错误弹窗，而不是预期的覆盖确认框。

## 当前阻塞：运动轴/单元配置

样例的 43 个全局变量里有 38 个是运动轴引用：

- `_MC_AXIS_REF`（如 `上料2拨料`，device `_MC_Axis[5]`）
- `_MC_AXIS_GROUP_REF`（如 `点胶A`，device `_MC_AxisGroup[1]`）

新建的 KV-X520 工程没有任何轴，粘贴这些 device 会被 KV 拒绝。
样例的轴来自 32 个 EtherCAT 节点（`references/sample-project-structure.json`
的 `hardware.ethercat_nodes`，26×`SV630_1Axis_03713`、`SGDXS…`、`CL3C-EC503`、
`YAKO MS-MINI3E`、3×`KV-EC01` 等）。

可行路径：

1. `configure_kv_ethercat_nodes` 按节点表重建 32 个节点（`batch_axis_registration=Yes`），
   生成轴与 `MC_*` 类型；ESI（`SV630_1Axis_03713`）需已在本机注册。
2. 或用 `complete_kv_axis_registration` / 虚轴配置先建立最小轴集，
   验证变量写入链路，再补全节点。

## 下一步

1. 从 `WsTreeEnv.xml` 提取 32 个节点的地址+模型，生成 `configure_kv_ethercat_nodes` 输入。
2. 在新建工程上配置 EtherCAT/轴，导出轴表核对 `_MC_Axis` 数量与编号。
3. 重跑完整 plan，目标：变量写入 → 编译 OK → 扫描顺序 24 项一致。
