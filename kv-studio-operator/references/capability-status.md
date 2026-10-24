# 能力状态与验证含义

能力、入口、参数和 runner 依赖统一来自 `scripts/script_manifest.json`；
用 `scripts/get_kv_capabilities.ps1` 查询。本文件不维护第二份脚本名单。

- `published` / `customer_callable=true`：可从公开接口调用。
- `approved` runner / atomic action：允许 workflow 使用的内部实现，
  不表示任意输入、所有字段或修改后的版本都已实测。
- `pending_validation`：新接口尚待对应验证，不冒充已发布能力。
- 同次 receipt：输入、脚本版本和输出归属证据。
- 语义验证：以子步骤明确的字段和读回内容为准。

变量默认核对名称和类型；`set_kv_variables.ps1 -FullGlobalAttributes` 额外
写入并读回全局变量的 device、initial_value、comment（2026-10-24 实测）。
device 与 initial_value 同时声明会被 `KV_VARIABLE_DEVICE_INITIAL_VALUE_CONFLICT`
拒绝；retain/constant/group_name 仍失败关闭。自变量核对名称、方向和类型。
完整源表逐列相等属于额外回归证据，不能推及所有普通写入。快照还需区别当前
筛选结果与完整清单。MNM 导入的完成、模块归属、声明完整及编译通过
是不同验收项，不能互相替代。

扩展单元按当前兼容目录查找；EtherCAT 按唯一 catalog_model 和请求节点号
写入并读回。缺失 ESI、歧义型号、未知型号应明确失败。没有已发布
EtherNet/IP 或 ESI 注册 workflow 时返回 ROUTE_RESEARCH_REQUIRED。

修改脚本后，先跑解析、manifest 分类、结果负例和计划检查，再用公开
workflow 做受影响的实测。失败必须保留，成功必须关联实际输入、代码
依赖和语义断言；旧日志不能自动认证新版本。具体覆盖和剩余工作见仓库
``work/系统缺口报告.md`（会话级证据；仓库内暂无 docs/ 目录）`，不要在此复制易过期的通过次数。

结构体 plan schema 和焦点/空白行规则统一见 variable-editor.md；
原子动作的注册与守卫规则统一见 ui-guard-contract.md。
