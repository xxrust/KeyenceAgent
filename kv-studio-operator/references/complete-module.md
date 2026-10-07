# 新增完整模块

入口 `create_kv_complete_module` 已发布，支持在现有项目精确父节点下新增本文契约范围内的
BOOL 扫描模块或用户 FB。真实验收覆盖分组归属、声明保存与重新进入表格读回、导出程序体一致及
转换结果。以下四次运行的 `workflow_result.json` 均为 `ok=true`、`status=pass`：

- 场景 14，完整扫描模块：`H:/rfinal/14_complete_scan_module_20260920_023900_542_0e06e1b6/workflow`。
- 场景 15，分组 FB（3 个自变量、1 个局部变量）：`H:/c15final/15_complete_station_fb_20260920_023115_540_9db8e403/workflow`。
- 冷 agent 独立准备并执行扫描模块：`H:/kvOp/_validation/compose_round2/validation/scan-live`。
- 冷 agent 独立准备并执行分组 FB：`H:/kvOp/_validation/compose_round2/validation/fb-live`。

这些路径仅供核查发布证据，不作为新任务的输入或执行入口。新任务按下面模板准备自己的契约、
源码和依据；已通过场景不扩大静态接受的 BOOL 范围，也不替代新任务的同次运行验收。

## 从需求准备输入

由 `keyence-plc-programmer` 把自然语言转为名称、输入输出、内部状态和可检查行为；
由 `kv-studio-kb-programming` 查询实际使用的指令和声明语义，保存本次 Wiki 依据。
从当前工程证据确认 CPU、类别和完整父路径。样例测试先复制到独立目录；
不要从历史 run 复制输入或脚本，也不要用样例 CPU 或分组代替目标工程证据。

此接口只在既有父节点下新增未存在的模块，不创建父分组，不覆盖同名模块。
扫描程序 `parent_path` 从 `每次扫描执行型模块` 开始，FB 从 `功能块` 开始；
包含此后每一层分组名称。预检读取目标工程旁的 `WsTreeEnv.xml`，要求父路径唯一匹配，
并拒绝工程树中已存在的同名节点。仅给末级组名或单独模块名称不足以定位目标。
分组归属由独立的树移动和保存验证建立：先用既有原子操作完成 MNM 导入，再把新增模块移动到
契约指定的精确父节点，保存后立即核对持久化树路径。选择某个分组后发起 MNM 导入本身不证明
模块会落在该分组，后续声明写入必须等精确路径验证通过。

## 契约模板

替换所有 `<...>` 字段后，在本次任务目录创建 UTF-8 JSON。建议使用相对于契约目录的路径。
`body_path`、`locals_path` 必填；FB 必填 `arguments_path`，扫描程序删除此字段。
`evidence_paths` 至少指向一个存在且非空的依据文件。其他 JSON 字段不被接受。

```json
{
  "schema_version": 1,
  "module_name": "<ModuleName>",
  "category": "function_block",
  "parent_path": ["功能块", "<ExistingGroupName>"],
  "body_path": "body.mnm",
  "locals_path": "locals.tsv",
  "arguments_path": "arguments.tsv",
  "evidence_paths": ["evidence/wiki.txt"]
}
```

模块名称为 1 至 48 个 ASCII 字母、数字或下划线，以字母或下划线开头。
`category` 只接受 `scan`、`function_block`。证据文件应含本次查询词、源标识、正文依据及适用条件；
门禁只核验文件存在、非空并固定指纹，不自动判断 Wiki 内容是否支持所写代码。

## 程序体范围

每个 MNM 只包含一个与契约同名的 `;MODULE:`。当前扫描程序要求 `DEVICE:63`、
`;MODULE_TYPE:0`；FB 要求 `DEVICE:59`、`;MODULE_TYPE:2`。编码应能由现有 MNM 读写接口正确解析；
有中文时按 programmer 的 MNM 编码规范准备，不让控制台重编码名称。

当前静态契约接受 BOOL 梯形图指令 `LD`、`LDB`、`AND`、`ANB`、`OR`、`ORB`、`OUT`，
每行格式为大写指令、一个空格、已声明的 ASCII 变量名；最后两条为 `END`、`ENDH`。
空行和以分号开头的说明行不参与指令比较。必须有装入和至少一次输出，不能写 `IN` 自变量。
全部变量必须已声明、互不重名且被程序引用，不能使用看起来像真实软元件的变量名。

这不是通用 KEYENCE 语言支持。ST、数值类型、常量操作数、设备操作数、调用其他 FB、定时器、
复杂回路和未列出的指令均不在此路线范围。静态语法、符号和装入检查不证明所有路径均正确赋值，
也不执行真值表或 PLC 扫描；行为仍由 programmer 审核，并按用户需求验证。

## 声明 TSV

两张表均使用带表头的 UTF-8 TSV，字段间是实际制表符。`owner_program` 必须逐字等于
`module_name`，类型为 `BOOL`，`status` 必须为 `declared`。变量名使用 ASCII 字母、数字、下划线，
以字母或下划线开头。此契约至少要求一行局部变量；FB 还至少要求一行自变量。
不要为了满足门禁添加无关变量；无局部状态的模块暂不属于此完整路线。

局部变量最小表头及可替换行：

```tsv
scope	owner_program	name	data_type	status	evidence
local	<ModuleName>	<LocalName>	BOOL	declared	<SourceReference>
```

除这些列外的非空局部属性会被拒绝，包括 `device`、`initial_value`、`comment`、保持属性。
可以保留相应空列以兼容规范表头。当前写入使用 `NameType`，不能声称完整变量属性已持久化。

自变量最小表头及可替换行；每个参数独占一行，方向使用 `IN`、`OUT` 或 `IN-OUT`：

```tsv
owner_program	argument_name	argument_kind	data_type	status	evidence
<ModuleName>	<InputName>	IN	BOOL	declared	<SourceReference>
<ModuleName>	<OutputName>	OUT	BOOL	declared	<SourceReference>
```

可选 `constant`、`retain`、`hidden`、`default_value` 只允许空或 `False`；建议默认值留空。
其他属性如 `comment1` 至 `comment8` 必须空。额外源说明写在证据文件中。
通用 scaffold 的默认 `status=defined`、非空注释和初值不能直接作为本契约输入；
使用模型渲染器准备文件时仍须按上述限制检查声明表，并重新运行整套预检。

## 预检与执行

先从当前安装 skill 发现入口，再用独立输出目录运行 `-PlanOnly`。以下是可替换命令模板：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-root>\scripts\get_kv_capabilities.ps1 -Capability create_kv_complete_module
powershell -STA -NoProfile -ExecutionPolicy Bypass -File <discovered-workflow> -ProjectPath <target-project.kpr> -ContractPath <task-directory>\contract.json -OutDir <task-directory>\plan -PlanOnly
```

`ProjectPath`、`ContractPath`、`OutDir` 必填；可选 `TimeoutSeconds` 默认 600。
PlanOnly 先核验模块内容，再生成并核验整套执行计划，产物包括：

- `preflight/module_preflight_result.json`：内容、声明、父路径、输入指纹。
- `execution_plan.json`：生成的完整步骤及参数。
- `plan_preflight_result.json`：共享计划预检与输入指纹。
- `workflow_result.json`：成功规划时 `status=planned`、`ui_started=false`。

共享预检验证脚本参数类型、必填值和枚举、步骤结果契约、项目绑定、独立输出目录、前置门禁及
完整步骤顺序；创建计划不得删去声明、编译、导出或最终验证。契约、程序体、TSV 和依据文件作为
传递输入固定 SHA256，执行阶段检查变化。失败时读取明确错误码修复当前输入；不要手改生成计划
删去失败步骤或直接调用内部 runner。

内容与计划预检都通过后，在用户授权范围内用新的执行输出目录调用同一公开 workflow，去掉
`-PlanOnly`。回归 harness 在规划及静态门禁通过后才启动独立项目副本；真实 workflow 串行占用
共享桌面锁。agent 不在子步骤之间补键盘操作。执行次序为：

1. 内容及共享门禁；先导入 MNM，再将需要分组归属的新增模块移动到精确父节点，保存后立即验证路径。
2. FB 写入自变量；扫描模块跳过此步。
3. `locals` 写入局部变量，使用 `AuditPersistence=true` 保存、关闭变量编辑器并重新打开读回。
4. 仅 FB 执行 `arguments_readback`：调用 `set_fb_arguments_guarded.ps1`，指定目标项目、
   `FbModuleName`、`SnapshotOnly=true` 和本步独立 `OutDir`，不传 `ArgumentsTsv`。
   它重新进入目标 FB 自变量表，产生 `fb_snapshot_result.json` 和完整原始 TSV。
5. 转换、复制转换结果、MNM 导出和最终核对。

共享计划门禁要求 FB 的 `arguments_readback` 位于 `locals` 之后、编译之前，不能用写入步骤的
粘贴后快照代替。失败时保留本次项目、进程和证据，停止后续 UI 输入；排查当前现场后再准备新的运行。

## 完整验收

最终验收读取本次 `workflow_result.json`、`run.log`、步骤 receipt、
`artifacts/verify/complete_module_result.json` 及所引用证据。完整结果要求保存后的精确父路径与
模块名匹配，且执行器确认同次编译结果通过。MNM 导出落在目标项目目录，最终核对另保存程序体副本。
最终验收检查的字段与边界为：

- 程序体：导出结果必须属于目标项目，当前导出清单必须唯一包含目标 MNM，文件长度与清单一致；
  模块名称及类型头唯一且匹配，去除空行、说明行和 DEVICE 头后的完整指令序列逐条一致。
- 局部变量：写入结果必须属于目标项目并启用持久化审计，关闭重开后的原始 TSV 必须位于本次
  `locals` 目录。按名称列和类型列精确核对全部预期名称、`BOOL` 类型和数量，拒绝重复、额外、
  缺失或不完整行；只忽略全空新增行。
- FB 自变量：先确认写入结果属于目标项目、模块及输入表，再读取本次 `arguments_readback`
  的 `fb_snapshot_result.json`。`ok`、`read_only`、`focus_verified`、`clipboard_fresh`、
  `all_columns_preserved` 必须为布尔真，项目、模块和整数行数必须匹配。`raw_path` 必须在该步骤目录，
  快照及原始文本时间不得早于局部变量完成时间。最终按原始 TSV 的名称、方向、类型列精确核对
  名称集合、`IN`/`OUT`/`IN-OUT` 方向、`BOOL` 类型和总数，拒绝重复及额外行。

FB 的 `argument_reopen_verified=true` 只在这条保存、局部编辑器重开、重新进入 FB 表并精确核对的
实际链完成后成立。两类声明仍保留 `unfiltered_completeness_verified=false`：当前证据不保证所有
过滤条件已清除，也不保证初值、设备绑定、保持、常量或注释等属性已完整持久化。
`ok=true`、名称包含或单独行数正确都不能替代上述字段比对。
`planned`、单项导入成功、表格粘贴成功或静态门禁通过都不满足真实桌面验收。
失败则保留本次现场与错误并停止后续 UI 输入，不用既有发布证据覆盖本次失败。
需要 PLC 行为证明时，编译和保存读回之后仍须进行用户要求的行为检查。
