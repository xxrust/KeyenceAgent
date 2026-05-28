# KeyenceAgent

<p align="center">
  <img src="docs/images/keyenceagent-harness-overview.png" alt="KeyenceAgent 执行框架总览">
</p>

<p align="center">
  <a href="https://github.com/xxrust/KeyenceAgent/commits/master"><img alt="最近提交" src="https://img.shields.io/badge/%E6%9C%80%E8%BF%91%E6%8F%90%E4%BA%A4-%E8%A7%81GitHub-555555?style=flat-square&logo=git"></a>
  <a href="https://github.com/xxrust/KeyenceAgent"><img alt="仓库大小" src="https://img.shields.io/badge/%E4%BB%93%E5%BA%93%E5%A4%A7%E5%B0%8F-%E8%A7%81GitHub-555555?style=flat-square"></a>
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat-square&logo=powershell&logoColor=white">
  <img alt="KV STUDIO 脚本托管" src="https://img.shields.io/badge/KV%20STUDIO-%E8%84%9A%E6%9C%AC%E6%89%98%E7%AE%A1-008C95?style=flat-square">
  <img alt="执行框架已验证" src="https://img.shields.io/badge/%E6%89%A7%E8%A1%8C%E6%A1%86%E6%9E%B6-%E7%BC%96%E8%AF%91%E5%B7%B2%E9%AA%8C%E8%AF%81-22A06B?style=flat-square">
  <img alt="UI 门禁已启用" src="https://img.shields.io/badge/UI%E9%97%A8%E7%A6%81-%E5%B7%B2%E5%90%AF%E7%94%A8-0B5FFF?style=flat-square">
</p>

<p align="center">
  <a href="README.md"><img alt="英文" src="https://img.shields.io/badge/%E8%8B%B1%E6%96%87-0B5FFF?style=for-the-badge"></a>
  <a href="README.zh-CN.md"><img alt="中文" src="https://img.shields.io/badge/中文-008C95?style=for-the-badge"></a>
  <a href="README.ja.md"><img alt="日文" src="https://img.shields.io/badge/%E6%97%A5%E6%96%87-22A06B?style=for-the-badge"></a>
</p>

<p align="center">
  面向 KEYENCE KV STUDIO 的智能体驱动自动化执行框架，用确定性脚本创建、修复并验证 PLC 项目。
</p>

> 本说明文档的配图由 GPT-image2 生成，并作为仓库资产存放在 `docs/images/`。

## 为什么需要 KeyenceAgent

KV STUDIO 自动化的核心风险不是“不会点按钮”，而是智能体在 IDE 打开后边看界面、边推理、边操作，导致焦点、弹窗、等待和归因全部混在一起。KeyenceAgent 把这个过程拆成执行框架：

| 阶段 | 负责人 | 规则 | 证据 |
| --- | --- | --- | --- |
| 准备 | 智能体 | 在 KV STUDIO 打开前编辑脚手架并运行验证门禁。 | `scaffold_validation.json` |
| 执行 | 运行脚本 | KV STUDIO 中的导入、变量粘贴、编译、复制结果全部由脚本执行。 | `artifacts/` |
| 验收 | 智能体 | 运行脚本退出后只读取同次运行结果文件。 | `mvp_result.json`、`repair_result.json` |

目标是可复现：同一个脚手架和同一个运行命令应生成相同项目、变量、编译结果和证据结构。

## 主要能力

| 能力 | 说明 |
| --- | --- |
| 结构化脚手架 | 将 `scaffold.model.json` 渲染为 MNM 文件和每个模块独立的变量 TSV。 |
| 多 MNM 导入 | 支持多个每次扫描执行型模块，并保持局部变量表隔离。 |
| 变量粘贴保护 | 通过焦点门禁、弹窗识别和粘贴错误硬错误码保护变量录入。 |
| 编译证据采集 | 运行 KV STUDIO 转换并复制真实转换结果文本。 |
| 已有项目修复 | 删除/重新导入目标模块，重建变量，编译并写出 `repair_result.json`。 |
| 路线治理 | 防止智能体在 UIA、键盘、鼠标、脚本之间无证据切换。 |

## 确定性修复闭环

<p align="center">
  <img src="docs/images/kv-repair-loop.png" alt="确定性 KV STUDIO 修复闭环">
</p>

1. 创建一个故意带错误的脚手架。
2. 运行新项目脚本。
3. 收集 KV STUDIO 真实 `转换结果 NG` 文本。
4. 根据错误文本修复脚手架模型、MNM 或变量清单。
5. 用修复后的脚手架运行已有项目修复脚本。
6. 只有 `repair_result.json.ok=true` 且复制出的编译文本包含 `转换结果 OK` 才算成功。

## 仓库结构

```text
.
├─ README.md
├─ README.zh-CN.md
├─ README.ja.md
├─ docs/
│  └─ images/
├─ kv-studio-operator/
│  ├─ SKILL.md
│  ├─ references/
│  └─ scripts/
└─ route-governance/
```

## 关键脚本

| 脚本 | 用途 |
| --- | --- |
| `kv-studio-operator/scripts/render_kv_mvp_scaffold_model.ps1` | 将结构化模型渲染为 KV STUDIO 适配文件，支持 `mnm.instructions` 和 `mnm.st_lines`。 |
| `kv-studio-operator/scripts/validate_kv_mvp_scaffold.ps1` | 在打开 KV STUDIO 前验证 checklist、schema、MNM 类型、模型一致性和危险变量名。 |
| `kv-studio-operator/scripts/run_kv_mvp_scaffold.ps1` | 创建新项目、导入 MNM、写入变量、编译并复制转换结果。 |
| `kv-studio-operator/scripts/run_kv_mvp_repair_existing_project.ps1` | 用修正后的 scaffold 修复已有错误 `.kpr`。 |
| `kv-studio-operator/scripts/run_kv_mvp_repeat.ps1` | 执行连续成功门禁。 |

## 脚手架是唯一源

结构化项目从 `scaffold.model.json` 开始。生成出的 MNM 和 TSV 是给 KV STUDIO 使用的适配文件。

```text
scaffold.model.json
CHECKLIST.md
TASK.md
VERSION.md
mnm/<module>.mnm
variables/<module>/global_variables.tsv
variables/<module>/local_variables.tsv
scaffold.json
```

渲染：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\render_kv_mvp_scaffold_model.ps1 `
  -ModelPath C:\KV_MVP\scaffolds\<task>\scaffold.model.json
```

验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\validate_kv_mvp_scaffold.ps1 `
  -ScaffoldRoot C:\KV_MVP\scaffolds\<task> `
  -OutDir C:\KV_MVP\scaffolds\<task>\_validation
```

## 新项目运行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\run_kv_mvp_scaffold.ps1 `
  -ScaffoldRoot C:\KV_MVP\scaffolds\<task> `
  -OutRoot C:\KV_MVP\mvp_runs `
  -TimeoutSeconds 600
```

主要结果：

```text
C:\KV_MVP\mvp_runs\<ProjectName>\mvp_result.json
```

## 已有错误项目修复

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\run_kv_mvp_repair_existing_project.ps1 `
  -ProjectPath C:\KV_MVP\mvp_runs\<ProjectName>\Projects\<ProjectName>\<ProjectName>.kpr `
  -ScaffoldRoot C:\KV_MVP\scaffolds\<fixed-task> `
  -OutRoot C:\KV_MVP\repair_runs `
  -DeleteExistingModulesBeforeImport `
  -TimeoutSeconds 600
```

主要结果：

```text
C:\KV_MVP\repair_runs\<ProjectName>\repair_result.json
```

## 变量命名硬规则

KV STUDIO 会把 `X0`、`Y0`、`R100`、`DM10` 这类名称识别为软元件风格名称。它们不能作为变量名。

应使用业务名：

```text
Pt0X
Pt0Y
Pt1X
Pt1Y
Pt2X
Pt2Y
CenterX
CenterY
FitValid
```

## 已验证案例

故意写入的 ST 错误：

```text
CenterX := (0.0 - Bcoff) / (2.0 * Acoef);
```

KV STUDIO 同次运行诊断：

```text
转换结果 NG (错误数量:1  警告数量:0)
QuadFitMain(行:00002)(列: 01)(ST行: 0016)[错误 1232]:"Bcoff": 发现非法的字符串。
```

修复方式是把 `Bcoff` 改为已经定义的局部变量 `Bcoef`。已有错误项目修复和新建错误项目后修复均通过：

```text
转换结果 OK (错误数量:0  警告数量:0)
```

## 工程规则

| 规则 | 原因 |
| --- | --- |
| 打开 KV STUDIO 前必须有 checklist | 防止无门禁 UI 脚本运行。 |
| KV 操作阶段必须由脚本独占 | 排除智能体实时操作带来的焦点漂移和错误归因。 |
| 只接受同次运行成果物 | 防止使用旧截图、旧日志制造假成功。 |
| 保留第一现场反馈 | 粘贴错误弹窗和编译诊断必须变成可行动错误码。 |
| 路线切换必须有证据 | 防止在 UIA、键盘、鼠标、脚本之间反复横跳。 |
