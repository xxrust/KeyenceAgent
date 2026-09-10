---
name: keyence-plc-programmer
description: 设计、修改和验证 KEYENCE PLC 的程序逻辑、MNM、变量和可复用 FB 接口。用于新程序、现有项目修复及样例复刻；专有语法依据 Wiki/导出证据，桌面操作交给 kv-studio-operator。
---

# KEYENCE PLC 编程

本 skill 负责程序内容和工程语义。KV STUDIO 桌面操作只使用
`kv-studio-operator` 的公开 workflow；不要使用旧 kvtool 或历史 UI 脚本。
KEYENCE 专有语法、指令/FB 调用、设备映射和模块行为，通过
`kv-studio-kb-programming` 查询本地 Wiki V2 或依据当前项目导出证据确认。

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

1. 对现有内容取得相关的新鲜 MNM、变量/自变量快照或配置证据，记录源项目和范围。
2. 设计或修改可审查的源文件。缺失的声明、类型、设备依据明确列出并解决。
3. 按依赖顺序调用 operator workflow；类型先于引用它的声明和模块。
4. 使用复制出的 KV STUDIO 编译错误修改源文件，再导入和转换。
5. 依据实际验证报告结果；编译通过不替代控制逻辑和设备行为验收。

复刻整个项目才需要完整资产清单和比较，见 [reproduction-gate.md](references/reproduction-gate.md)。
不要删减逻辑、变量或硬件要求来获得通过。官方 FB 保持来源、名称和行为；
用户 FB 和业务逻辑按源文件重建。

## MNM 与声明

- 普通用户程序为 `;MODULE_TYPE:0`，用户 FB 为 `;MODULE_TYPE:2`。
- 保持接近 KV STUDIO 导出的格式，按目标 Windows ANSI 编码写含中文的 MNM；
  中文 Windows 通常为 CP936。
- ST 程序体只写 KV STUDIO 接受的可执行语句。变量声明位于编辑器变量表，
  不把通用 IEC 声明块直接塞进程序体。
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
`KVSREF.pdf#p194-203`（调用绑定）、`KVSHARDX3H.pdf#p422-423`
（局部变量）、`ScriptUse.pdf#p96-98`（FB 重用）。

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

在任务目录分别保存 `source_snapshot`、`work`、`validation`，代码来源固定为
已安装 skill。保留原始快照和阶段 commit；历史输出中的脚本不作为执行入口。

可复用非 UI 工具包括 `init_project_snapshot_workspace.ps1`、
`validate_fb_reuse_guard.ps1` 和 `new_mnm_smoke.ps1`。
KV STUDIO 可执行文件解析仍由 `resolve_kvstudio_local.ps1` 提供给 operator；
这不构成另一套 UI 路线。

报告修改范围、依据、声明/依赖完成度、当前编译结果、证据路径与剩余问题。
细小修改只报告相关内容，无需套用整项目复刻报告。
