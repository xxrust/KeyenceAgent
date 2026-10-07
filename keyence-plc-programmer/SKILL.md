---
name: keyence-plc-programmer
description: 编写和修改 KEYENCE PLC 程序（ST/LD）、变量、FB 接口与 MNM；用于代码生成、工程修复和样例复刻。KEYENCE 专有语义依据 Wiki/项目证据，桌面操作交给 kv-studio-operator。
---

# KEYENCE PLC 编程

本 skill 负责程序内容和工程语义。KV STUDIO 桌面操作只使用
`kv-studio-operator` 的公开 workflow；不要使用旧 kvtool 或历史 UI 脚本。
KEYENCE 专有语法、指令/FB 调用、设备映射和模块行为，通过
`kv-studio-kb-programming` 查询本地 Wiki V2 或依据当前项目导出证据确认。

## 快速 ST 路径

用户只要 ST 逻辑/代码、明确不要求改工程或操作 KV STUDIO 时，直接给程序主体和需要定义的变量/FB 接口；不生成 MNM、`MODULE_TYPE`、TSV 或工程目录，不读项目快照，也不启动协作者。只在当前问题确实涉及对应语法时，按下表读取一份 ST reference；遇到不能由这些已整理模式确定的 KEYENCE 专有行为，再转 KB 查询。

| 任务内容 | 按需参考 |
| --- | --- |
| 控制流、运算、统计、几何 | [控制流与数值](references/st/control-flow-and-numeric.md) |
| 数组、FB、定时器、扫描状态 | [数组、FB 与扫描状态](references/st/arrays-fb-and-scan-state.md) |
| 字符串、时间、存储、通信、运动 | [字符串、时间与设备接口](references/st/strings-time-and-device-interfaces.md) |

用户要求读取/修改现有工程、生成导入文件或真实编译时，再按下方编辑流程进入工程路径；“写一段 ST”本身不触发该流程。

## 一个完整程序需要什么

程序体、声明、调用实例和依赖分别存在。MNM 主要承载程序模块；
导入程序体不会自动证明变量表或 FB 自变量完整。

先明确 CPU、任务/模块、输入输出、状态变化和验收条件，再按修改范围准备：

- 程序体：梯形图助记符或 ST 可执行语句。
- 声明：全局变量、每个程序/FB 的局部变量、FB 自变量。
- 依赖：用户数据类型、被调用 FB/函数、官方库。
- 集成：FB 实例、调用方实参、真实设备和单元/轴映射。
- 验证：相关表格读回、转换/编译结果，以及用户要求的行为检查。

只修改一张表时无需伪造完整 MVP。学习完整项目形态时可使用 operator
的 scaffold 示例，但保留实际项目的结构和验收范围。

## 编辑流程

1. 对现有内容取得与修改范围匹配的新鲜证据。跨模块理解、整项目复刻或全面审核优先使用 operator 的 `read_only_project_text_snapshot`；窄范围修改可只取相关 MNM、变量/自变量或配置快照。
2. 设计或修改可审查的源文件。缺失的声明、类型、设备依据明确列出并解决。
3. 按依赖顺序调用 operator workflow；类型先于引用它的声明和模块。
4. 使用复制出的 KV STUDIO 编译错误修改源文件，再导入和转换。
5. 依据实际验证报告结果；编译通过不替代控制逻辑和设备行为验收。

从零建工程时，先用 operator 的 `get_kv_capabilities.ps1 -Capability create_project`
读取公开入口及 `regression_scenarios`，查看匹配的 README 和场景参数后创建目标 CPU 工程。
`sample_copy` 是已有样例副本，不能当作空白创建的依据；`new_project` 才覆盖实际新建。
接口失败时先核对标准契约和本次证据，不把尚未完成的算法/ST 集成与已有工程创建能力混为一谈。
测试契约用于学习受支持的调用方式，算法和声明仍按本次需求独立生成。

自然语言要求新增完整程序或 FB 时，准备程序体、声明、目标树路径和 Wiki 证据。
BOOL 梯形图按 [complete-module.md](references/complete-module.md) 使用 operator 的
`create_kv_complete_module`；数值 ST 按 operator 的 `references/st-programs.md`
使用 `create_kv_st_module`。提交整套契约预检；仅修改已有程序体或一张变量表时仍使用对应窄接口。

复刻整个项目才需要完整资产清单和比较，见 [reproduction-gate.md](references/reproduction-gate.md)。
不要删减逻辑、变量或硬件要求来获得通过。官方 FB 保持来源、名称和行为；
用户 FB 和业务逻辑按源文件重建。

## 从语义快照理解项目

完整快照以 `snapshot/project/` 为首要阅读入口，而不是把分散的原子输出重新拼成工程：

- `功能块/<项目树分组>/<FB>/`：`body.mnm`、`arguments.tsv`、`locals.tsv`、`entity.json`。
- `程序/<模块类别>/<模块>/`：`body.mnm`、`locals.tsv`、`entity.json`。
- `配置/单元`、`配置/EtherCAT`、`配置/全局变量` 和 `类型/`：全局依赖。
- `_index/entities.jsonl`：Agent 检索入口；`_index/restore_plan.json`：依赖和恢复顺序。

先读根 manifest 与实体状态，再据 `entity.json.tree_path`、`category`、`artifacts`、
`status` 和 `restore` 判断归属及完整性。目录位置用于人类导航，`entity.json` 用于自动化；
二者不一致时不得猜测，转入证据核查。`text/` 是原子文本证据，`raw/` 是运行审计证据。
任何 `semantic_warnings` 或实体的 `failed`、`missing`、`partial`、`unresolved` 都必须在设计、
恢复和报告中显式处理，不能因顶层快照为 `ready` 就视为内容完整。

## MNM 与声明

- 普通用户程序为 `;MODULE_TYPE:0`，用户 FB 为 `;MODULE_TYPE:2`。
- 保持接近 KV STUDIO 导出的格式，按目标 Windows ANSI 编码写含中文的 MNM；
  中文 Windows 通常为 CP936。
  该旧路线不适用于 KV-X520 域 ST 导入：已实测使用 `DEVICE:60` 与 UTF-16LE BOM。
  用 `scripts/new_kv_st_mnm.ps1 -DeviceCode 60 -OutputEncoding Utf16LE` 从 UTF-8 ST 封装，
  不直接复用 BOOL 示例的 DEVICE/编码；导出读回用同脚本 `-ExportPath` 精确比较全部 ST 行。
- ST 程序体只写 KV STUDIO 接受的可执行语句。变量声明位于编辑器变量表，
  不把通用 IEC 声明块直接塞进程序体。
- 普通 ST 问答只列出需要登记的变量，不因未要求工程交付而补 MNM 封装、TSV 或固定 contract。
- 数值 ST/数组/算法 FB 按 operator 的 `references/st-programs.md` 组合接口。
  官方域类型 ST 导出为 `AREA_ST`，不要求另建一种模块语言；能导出不证明能反向导入。
  使用描述性标识符并先跑声明预检；`B`、`C`、`T`、`V` 等为保留字，`C0` 等与软元件名冲突
  （STUse.pdf p302-304）。完整源码读回不能丢弃 MNM 中以分号开头的 ST 代码行。
- 名称、作用域、数据类型、数组尺寸、初值、保持属性和设备绑定保持源语义。
  当前接口未验证的字段必须明确说明，不能默认为已还原。
- TSV 的实际粘贴列和读回边界以 operator 的 variable-editor.md 及校验脚本为准；
  不在两个 skill 中分别维护 UI schema。

## 可复用 FB

调用方拥有真实设备映射、全局集成变量、轴/模块绑定和 FB 实例。
FB 内部拥有可复用逻辑、显式自变量和局部状态，不被业务全局变量绑定。

写程序体前准备：

- 自变量：name、direction、data_type、调用方绑定、comment。
- 局部变量：name、data_type、initial_value、retain、comment。
- 实例：caller_program、instance_name、FB_type。

方向包含 `IN`、`OUT`、`IN-OUT`、`UNIT`。`OUT` 和 `IN-OUT`
不能绑定常数。外部交互用自变量，内部状态用局部变量。
固定业务软元件放在调用方；确需内部特殊软元件时记录设备、理由和证据。

依据：`KvsHARD8000.pdf#p225-227`（自变量方向）、`p240-243` /
`KVSREF.pdf#p194-203`（调用绑定）、`KVSHARDX3H.pdf#p100-101`
（用户局部变量作用域和 BOOL 类型；Wiki chunk `pdf::KVSHARDX3H::chunk-039`）、
`ScriptUse.pdf#p96-98`（FB 重用）。`KVSHARDX3H.pdf#p422-423` 讲系统局部变量，
不作为用户声明格式的依据。

导入或声称用户 FB 有效前执行非 UI 检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-root>\scripts\validate_fb_reuse_guard.ps1 -Path <mnm-file-or-folder>
```

特殊设备例外通过 `-ContractPath` 输入 JSON：

```json
{"allowed_devices":[{"module":"FB_ModuleName","device":"CR2012","reason":"documented flag required by this contract","evidence":"FBCALL_FBSTRT.htm#运算标志"}]}
```

`KV_FB_REUSE_DEVICE_LEAK` 表示设备泄漏，需要改成自变量/局部状态或提供真实设备契约。

## 工作产物与报告

在任务目录分别保存 `source_snapshot`、`work`、`validation`；完整项目快照的规范内容位于
`source_snapshot/.../snapshot/project`，代码来源固定为
已安装 skill。保留原始快照和阶段 commit；历史输出中的脚本不作为执行入口。

可复用非 UI 工具包括 `init_project_snapshot_workspace.ps1`、
`validate_fb_reuse_guard.ps1` 和 `new_mnm_smoke.ps1`。
KV STUDIO 可执行文件解析仍由 `resolve_kvstudio_local.ps1` 提供给 operator；
这不构成另一套 UI 路线。

报告修改范围、依据、声明/依赖完成度、当前编译结果、证据路径与剩余问题。
细小修改只报告相关内容，无需套用整项目复刻报告。
