# 07 EtherCAT 节点批量配置

## 操作内容

调用 `scripts/workflows/configure_kv_ethercat_nodes.ps1`，按 JSON 配置向测试副本加入 EtherCAT 设备并设置节点地址。

## 测试目标

验证 workflow 能按任意给定目录型号使用筛选框快速定位可插入设备，插入到网络，设置节点号，提交配置，并从保存后的项目证据回读。每个 UI 原子动作必须小于 10 秒。

## 固定输入

`fixtures/nodes.json` 包含两个节点：地址 40 的 `YAKO MS-MINI3E`，地址 41 的 `SV630_1Axis_03713`；`batch_axis_registration` 为 `No`。这两个型号是接口回归样本，不是支持型号白名单。

## 执行方法

双击 `run.bat`，或运行 `run.bat -NoPause`。调用链为公共 runner -> `configure_kv_ethercat_nodes.ps1` -> flat executor -> `configure_ethercat_nodes_guarded.ps1`。所有节点在一个串行 workflow 中处理；桌面互斥锁禁止另一个 KV workflow 并行输入。`-PlanOnly` 只检查 JSON 和计划。

## 通过标准

真实测试必须满足：`test_result.json` 和 `workflow/workflow_result.json` 成功；`workflow/result.json` 为 `ok=true`；结果中的请求、已配置设备及持久化证据与两条 fixture 一致；所有 `atomic_action_timings`（或同等 timing 证据）小于 10000 ms；step receipt 成功；`workflow/run.log` 完整记录型号筛选、插入、节点地址和提交。

只在可插入项中搜索到设备、只在网络树看到临时节点，或 KV STUDIO 自动显示了连续编号，都不能替代保存后的地址/设备回读。

## 日志与结果

输出位于 `../runs/07_ethercat_nodes_<时间戳>/`。runner 的 `result.json`、节点/窗口快照、原子计时和 receipt 位于 `workflow/`，统一日志为 `workflow/run.log`，总结果为 `test_result.json`。
