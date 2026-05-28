# KeyenceAgent

<p align="center">
  <img src="docs/images/keyenceagent-harness-overview.png" alt="KeyenceAgent harness overview">
</p>

<p align="center">
  <a href="https://github.com/xxrust/KeyenceAgent/commits/master"><img alt="Last commit" src="https://img.shields.io/github/last-commit/xxrust/KeyenceAgent?style=flat-square&logo=git"></a>
  <a href="https://github.com/xxrust/KeyenceAgent"><img alt="Repository size" src="https://img.shields.io/github/repo-size/xxrust/KeyenceAgent?style=flat-square"></a>
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat-square&logo=powershell&logoColor=white">
  <img alt="KV STUDIO" src="https://img.shields.io/badge/KV%20STUDIO-script--owned-008C95?style=flat-square">
  <img alt="Harness status" src="https://img.shields.io/badge/harness-compile%20verified-22A06B?style=flat-square">
  <img alt="UI guard" src="https://img.shields.io/badge/UI%20guard-enabled-0B5FFF?style=flat-square">
</p>

<p align="center">
  <a href="#english"><img alt="English" src="https://img.shields.io/badge/English-0B5FFF?style=for-the-badge"></a>
  <a href="#中文"><img alt="中文" src="https://img.shields.io/badge/中文-008C95?style=for-the-badge"></a>
  <a href="#日本語"><img alt="日本語" src="https://img.shields.io/badge/日本語-22A06B?style=for-the-badge"></a>
</p>

<p align="center">
  Agent-driven automation harness for building, repairing, and validating KEYENCE KV STUDIO projects through deterministic scripts.
</p>

> Images in this README were generated with GPT-image2 and stored as repository assets under `docs/images/`.

---

## English

### Why KeyenceAgent Exists

KEYENCE KV STUDIO automation is fragile when an agent directly clicks, types, watches the UI, and decides the next operation while the IDE is open. KeyenceAgent turns that workflow into a harness:

| Phase | Owner | Rule | Evidence |
| --- | --- | --- | --- |
| Prepare | Agent | Edit scaffold files and validate gates before KV STUDIO opens. | `scaffold_validation.json` |
| Execute | Runner scripts | Scripts own all KV STUDIO UI actions. The agent does not inspect or operate live UI. | `artifacts/` |
| Verify | Agent | Read same-run result files after the runner exits. | `mvp_result.json`, `repair_result.json` |

The practical goal is repeatability: the same scaffold and runner command should produce the same project, variables, compile result, and evidence layout.

### Core Capabilities

| Capability | What It Does |
| --- | --- |
| Structured scaffold rendering | Converts `scaffold.model.json` into MNM files and per-module variable TSV files. |
| Multi-MNM import | Imports multiple scan-executed modules with isolated local variable tables. |
| Guarded variable entry | Applies global and local variables through checked focus gates and paste-error detection. |
| Compile evidence capture | Runs KV STUDIO conversion and copies the actual conversion result text. |
| Existing-project repair | Deletes/reimports target modules, reapplies variables, compiles, and writes `repair_result.json`. |
| Route discipline | Keeps agent reasoning outside the script-owned KV STUDIO operation phase. |

### Deterministic Repair Loop

<p align="center">
  <img src="docs/images/kv-repair-loop.png" alt="Deterministic KV STUDIO repair loop">
</p>

The repair loop is intentionally evidence-driven:

1. Create a buggy scaffold.
2. Run the fresh-project runner.
3. Collect the actual `转换结果 NG` text from KV STUDIO.
4. Repair the scaffold model, MNM, or variable manifest based on that text.
5. Run the existing-project repair runner with the corrected scaffold.
6. Accept success only when `repair_result.json.ok=true` and copied compile text contains `转换结果 OK`.

### Repository Layout

```text
.
├─ README.md
├─ docs/
│  └─ images/
├─ kv-studio-operator/
│  ├─ SKILL.md
│  ├─ references/
│  └─ scripts/
│     ├─ render_kv_mvp_scaffold_model.ps1
│     ├─ validate_kv_mvp_scaffold.ps1
│     ├─ run_kv_mvp_scaffold.ps1
│     ├─ run_kv_mvp_repair_existing_project.ps1
│     ├─ run_kv_mvp_repeat.ps1
│     └─ mvp/
├─ keyence-plc-programmer/
├─ kv-studio-kb-programming/
└─ route-governance/
```

### Main Scripts

| Script | Purpose |
| --- | --- |
| `kv-studio-operator/scripts/render_kv_mvp_scaffold_model.ps1` | Renders structured scaffold models into KV STUDIO adapter files. Supports ladder-style `mnm.instructions` and ST-style `mnm.st_lines`. |
| `kv-studio-operator/scripts/validate_kv_mvp_scaffold.ps1` | Validates checklist, schema, MNM module type, model/render consistency, and unsafe variable names before KV STUDIO opens. |
| `kv-studio-operator/scripts/run_kv_mvp_scaffold.ps1` | Creates a fresh project, imports MNM files, applies variables, compiles, and copies conversion output. |
| `kv-studio-operator/scripts/run_kv_mvp_repair_existing_project.ps1` | Repairs an existing erroneous `.kpr` with corrected scaffold content. |
| `kv-studio-operator/scripts/run_kv_mvp_repeat.ps1` | Runs repeat gates and requires consecutive passing attempts. |

Runner-owned child scripts live under `kv-studio-operator/scripts/mvp/`. Agents should not call child scripts as the normal path.

### Scaffold Source Of Truth

Structured projects start from `scaffold.model.json`. Generated MNM and TSV files are adapter artifacts for KV STUDIO.

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

Render:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\render_kv_mvp_scaffold_model.ps1 `
  -ModelPath C:\KV_MVP\scaffolds\<task>\scaffold.model.json
```

Validate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\validate_kv_mvp_scaffold.ps1 `
  -ScaffoldRoot C:\KV_MVP\scaffolds\<task> `
  -OutDir C:\KV_MVP\scaffolds\<task>\_validation
```

### Fresh Project Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\run_kv_mvp_scaffold.ps1 `
  -ScaffoldRoot C:\KV_MVP\scaffolds\<task> `
  -OutRoot C:\KV_MVP\mvp_runs `
  -TimeoutSeconds 600
```

Primary result:

```text
C:\KV_MVP\mvp_runs\<ProjectName>\mvp_result.json
```

Success criteria:

| Field | Required Value |
| --- | --- |
| `ok` | `true` |
| `compile_result_contains_ok` | `true` |
| `steps[].exit_code` | all `0` |
| `compile_result_path` | points to current-run copied conversion text |

### Existing Project Repair

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\run_kv_mvp_repair_existing_project.ps1 `
  -ProjectPath C:\KV_MVP\mvp_runs\<ProjectName>\Projects\<ProjectName>\<ProjectName>.kpr `
  -ScaffoldRoot C:\KV_MVP\scaffolds\<fixed-task> `
  -OutRoot C:\KV_MVP\repair_runs `
  -DeleteExistingModulesBeforeImport `
  -TimeoutSeconds 600
```

Primary result:

```text
C:\KV_MVP\repair_runs\<ProjectName>\repair_result.json
```

The repair runner keeps the framework unchanged. Only runtime parameters and scaffold content change.

### Variable Name Guardrails

KV STUDIO treats names such as `X0`, `Y0`, `R100`, and `DM10` as soft-device style names. They must not be used as variable names.

The harness rejects these names with:

```text
KV_SCAFFOLD_VARIABLE_NAME_SOFT_DEVICE_CONFLICT
KV_VARIABLE_NAME_SOFT_DEVICE_CONFLICT
```

Use business names instead:

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

### Verified Quadratic-Fit Case

The deliberate bug:

```text
CenterX := (0.0 - Bcoff) / (2.0 * Acoef);
```

Same-run KV STUDIO diagnostic:

```text
转换结果 NG (错误数量:1  警告数量:0)
QuadFitMain(行:00002)(列: 01)(ST行: 0016)[错误 1232]:"Bcoff": 发现非法的字符串。
```

The repair changed `Bcoff` to the defined local variable `Bcoef`. Both tested paths passed:

| Path | Evidence |
| --- | --- |
| Existing erroneous project repair | `repair_result.json.ok=true` |
| Fresh erroneous project then repair | `repair_result.json.ok=true` |
| Final compile result | `转换结果 OK (错误数量:0  警告数量:0)` |

### Engineering Rules

| Rule | Reason |
| --- | --- |
| Checklist before KV STUDIO operation | Prevents running uncontrolled UI scripts. |
| Script-owned KV phase | Removes agent timing/focus drift from the live IDE. |
| Same-run artifacts only | Prevents false success from stale screenshots or logs. |
| First feedback is preserved | Paste dialogs and compile diagnostics become actionable error codes. |
| Route changes require evidence | Prevents switching between UIA, keyboard, mouse, and scripts without proof. |

---

## 中文

KeyenceAgent 是一个面向 KEYENCE KV STUDIO 的 agent 自动化 harness。核心边界是：agent 只在 KV STUDIO 打开前规划和生成脚手架，在 runner 退出后读取证据；KV STUDIO 打开期间的导入、变量粘贴、编译、复制结果全部由脚本执行。

### 语言与状态

顶部按钮可跳转到 English / 中文 / 日本語。顶部 badges 显示最近提交、仓库大小、PowerShell、KV STUDIO 脚本托管、harness 验证状态和 UI guard 状态。

### 主要能力

| 能力 | 说明 |
| --- | --- |
| 结构化脚手架 | 用 `scaffold.model.json` 生成 MNM、全局变量 TSV、局部变量 TSV 和 `scaffold.json`。 |
| 多 MNM 导入 | 支持多个每次扫描执行型模块，并保持局部变量表按模块隔离。 |
| 变量粘贴保护 | 能识别“粘贴数据中存在错误，已跳过部分数据粘贴”并返回硬错误码。 |
| 编译证据采集 | 从 KV STUDIO 复制真实 `转换结果 OK/NG` 文本。 |
| 错误项目修复 | 对已有 `.kpr` 删除同名模块、导入修正 MNM、重建变量并编译。 |
| 路线治理 | 防止 agent 在 UIA、键盘、鼠标、脚本之间无证据切换。 |

### 最小流程

1. 编辑 `scaffold.model.json`。
2. 运行 `render_kv_mvp_scaffold_model.ps1` 生成 MNM 和变量 TSV。
3. 运行 `validate_kv_mvp_scaffold.ps1`，确认 checklist 和脚手架有效。
4. 新项目用 `run_kv_mvp_scaffold.ps1`。
5. 已有错误项目用 `run_kv_mvp_repair_existing_project.ps1`。
6. 只用当前 run 的 `mvp_result.json` 或 `repair_result.json` 作为成功证据。

### 常用命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\render_kv_mvp_scaffold_model.ps1 `
  -ModelPath C:\KV_MVP\scaffolds\<task>\scaffold.model.json
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\run_kv_mvp_scaffold.ps1 `
  -ScaffoldRoot C:\KV_MVP\scaffolds\<task> `
  -OutRoot C:\KV_MVP\mvp_runs `
  -TimeoutSeconds 600
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\run_kv_mvp_repair_existing_project.ps1 `
  -ProjectPath C:\KV_MVP\mvp_runs\<ProjectName>\Projects\<ProjectName>\<ProjectName>.kpr `
  -ScaffoldRoot C:\KV_MVP\scaffolds\<fixed-task> `
  -OutRoot C:\KV_MVP\repair_runs `
  -DeleteExistingModulesBeforeImport `
  -TimeoutSeconds 600
```

### 变量命名硬规则

不要把 `X0`、`Y0`、`R100`、`DM10` 这类软元件形式当变量名。坐标点应使用 `Pt0X`、`Pt0Y`、`Pt1X`、`Pt1Y`、`Pt2X`、`Pt2Y` 这类业务名。

违反规则会在脚本中直接失败：

```text
KV_SCAFFOLD_VARIABLE_NAME_SOFT_DEVICE_CONFLICT
KV_VARIABLE_NAME_SOFT_DEVICE_CONFLICT
```

### 已验证案例

二次拟合求中心坐标的 ST 程序先故意写错：

```text
CenterX := (0.0 - Bcoff) / (2.0 * Acoef);
```

KV STUDIO 返回：

```text
转换结果 NG (错误数量:1  警告数量:0)
QuadFitMain(行:00002)(列: 01)(ST行: 0016)[错误 1232]:"Bcoff": 发现非法的字符串。
```

修复为 `Bcoef` 后，已有错误项目修复和新建错误项目后修复均通过，最终结果为：

```text
转换结果 OK (错误数量:0  警告数量:0)
```

---

## 日本語

KeyenceAgent は、KEYENCE KV STUDIO のプロジェクト作成、修復、検証をスクリプト主導で再現可能にする agent harness です。agent は KV STUDIO を開く前に scaffold を準備し、runner 終了後に成果物を検証します。KV STUDIO 操作中のクリック、入力、貼り付け、コンパイル、結果コピーは runner が担当します。

### 目的

| 項目 | 説明 |
| --- | --- |
| 安定性 | UI 操作を runner に閉じ込め、agent の逐次判断を排除します。 |
| 証拠性 | 成功判定は同一 run の JSON と変換結果テキストだけで行います。 |
| 修復性 | コンパイル NG の内容から MNM と変数定義を修正します。 |
| 再現性 | 同じ scaffold と runner コマンドで同じ結果を得ることを目標にします。 |

### 基本フロー

1. `scaffold.model.json` を編集します。
2. `render_kv_mvp_scaffold_model.ps1` で MNM と変数 TSV を生成します。
3. `validate_kv_mvp_scaffold.ps1` で checklist と scaffold を検証します。
4. 新規プロジェクトは `run_kv_mvp_scaffold.ps1` を使います。
5. 既存のエラープロジェクトは `run_kv_mvp_repair_existing_project.ps1` を使います。
6. `mvp_result.json` または `repair_result.json` とコピー済み変換結果で判定します。

### 主要コマンド

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\run_kv_mvp_scaffold.ps1 `
  -ScaffoldRoot C:\KV_MVP\scaffolds\<task> `
  -OutRoot C:\KV_MVP\mvp_runs `
  -TimeoutSeconds 600
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\run_kv_mvp_repair_existing_project.ps1 `
  -ProjectPath C:\KV_MVP\mvp_runs\<ProjectName>\Projects\<ProjectName>\<ProjectName>.kpr `
  -ScaffoldRoot C:\KV_MVP\scaffolds\<fixed-task> `
  -OutRoot C:\KV_MVP\repair_runs `
  -DeleteExistingModulesBeforeImport `
  -TimeoutSeconds 600
```

### 変数名の制約

`X0`、`Y0`、`R100`、`DM10` のような名前は KV STUDIO のソフトデバイス名として扱われる可能性があります。変数名として使わず、`Pt0X`、`Pt0Y`、`CenterX` のような業務名を使います。

### 検証済み修復例

意図的な ST バグ:

```text
CenterX := (0.0 - Bcoff) / (2.0 * Acoef);
```

KV STUDIO の診断:

```text
转换结果 NG (错误数量:1  警告数量:0)
QuadFitMain(行:00002)(列: 01)(ST行: 0016)[错误 1232]:"Bcoff": 发现非法的字符串。
```

`Bcoff` を定義済みローカル変数 `Bcoef` に修正した後、既存エラープロジェクト修復と新規エラープロジェクト修復の両方で `转换结果 OK` を確認しています。

