# 从自然语言到完整模块

本文模板对应 BOOL 梯形图 `create_kv_complete_module`。数值 ST、数组及算法 FB 使用
operator 的 `references/st-programs.md` 和 `create_kv_st_module`，不能提交到 BOOL 契约。
ST 路线另要求 `.st` 源文件、DEVICE:60/UTF-16LE MNM 和逐行源码读回；声明共用
operator 的 `references/variable-editor.md`，类型不局限于 BOOL。

适用于用户要求在现有工程中新增完整程序或 FB。明确名称、类别、项目树分组、输入输出、
内部变量及可检查行为；未知 CPU/依赖从当前工程证据确认，不套用样例默认值。
只新增 FB 定义时无需凭空新增调用程序或真实设备绑定；用户要求运行集成时再登记调用实例和实参。

## 内容准备

- MNM：名称与目标一致；扫描程序 `;MODULE_TYPE:0`，用户 FB `;MODULE_TYPE:2`。
- 局部变量 TSV：完整本地声明，`scope=local`，`owner_program` 等于模块名。
- FB 自变量 TSV：每个输入、输出的名字、方向、BOOL 类型；外部交互不藏入全局变量。
- Wiki 依据文件：本次查询的源标识、正文依据及适用条件，来自 `kv-studio-kb-programming`。
- 目标树路径：从类别节点开始的名称数组，依据当前工程树。中文路径由 UTF-8 JSON 传递。

TSV 列顺序和可写属性使用 operator 的 `references/complete-module.md` 契约，勿照搬 UI 全列快照。
该入口要求 `status=declared`，不接受其他非空可选字段；模型渲染器的默认状态和注释不能直接用于此入口。
初值、保持、设备绑定或注释不在已验证写入范围时明确保留缺口，不能声称默认值已经读回。
可复用 FB 导入前仍运行 `validate_fb_reuse_guard.ps1`。

## 完整模块契约

通过 operator 能力发现读取 `create_kv_complete_module` 的实际参数和验证范围。
契约文件为 UTF-8 JSON；源文件路径相对于契约所在目录解析，也可以使用绝对路径：

```json
{
  "schema_version": 1,
  "module_name": "QA_StationPermit",
  "category": "function_block",
  "parent_path": ["功能块", "从当前工程读取的精确分组名"],
  "body_path": "body.mnm",
  "locals_path": "locals.tsv",
  "arguments_path": "arguments.tsv",
  "evidence_paths": ["evidence/wiki-query.txt"]
}
```

`category` 为 `scan` 或 `function_block`；FB 必须给出 `arguments_path`。
`evidence_paths` 是非空证据文件数组。路径和模块名称只是输入要求，仍须预检与当前工程匹配。
运行形状为发现所得入口的 `-ProjectPath ... -ContractPath ... -OutDir ... -PlanOnly`。

当前完整模块路线第一版静态接受 BOOL 梯形图 `LD`、`LDB`、`AND`、`ANB`、`OR`、`ORB`、`OUT`、`END`、`ENDH`。
静态接受不代表全部指令组合已完成真实桌面验收；按 operator 能力清单和本次证据报告范围。
这不是 KEYENCE 全部语言范围。ST 按本文开头的专用路线处理；其他超出相应接口已验证范围的
复杂指令或自定义类型，先查询能力清单。不要删减请求逻辑或用未经验证的替代语法获取预检通过。

## 执行与验收

先完成整套非 UI 预检，确认程序引用的变量均有声明、方向和类型一致、设备使用合规、
目标分组完整匹配，再由 operator 串行执行导入、分组归属、声明、程序体及编译步骤。
测试用样例先复制到独立目录。公开入口未发现时报告 `ROUTE_RESEARCH_REQUIRED`，不绕到内部 runner。

计划生成和预检通过不等于真实桌面验收。最终证据至少覆盖保存后的精确树路径、程序体读回、
自变量和局部变量读回及同次运行编译结果。对组合 BOOL 逻辑列出输入组合对应输出；
需要实际 PLC 执行证明时继续相应行为检查。按证据报告尚未完成项。
