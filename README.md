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
  <a href="README.md"><img alt="English" src="https://img.shields.io/badge/English-0B5FFF?style=for-the-badge"></a>
  <a href="README.zh-CN.md"><img alt="中文" src="https://img.shields.io/badge/中文-008C95?style=for-the-badge"></a>
  <a href="README.ja.md"><img alt="日本語" src="https://img.shields.io/badge/日本語-22A06B?style=for-the-badge"></a>
</p>

<p align="center">
  Agent-driven automation harness for building, repairing, and validating KEYENCE KV STUDIO projects through deterministic scripts.
</p>

> Images in this README were generated with GPT-image2 and stored as repository assets under `docs/images/`.

## Why KeyenceAgent Exists

KEYENCE KV STUDIO automation is fragile when an agent directly clicks, types, watches the UI, and decides the next operation while the IDE is open. KeyenceAgent turns that workflow into a harness:

| Phase | Owner | Rule | Evidence |
| --- | --- | --- | --- |
| Prepare | Agent | Edit scaffold files and validate gates before KV STUDIO opens. | `scaffold_validation.json` |
| Execute | Runner scripts | Scripts own all KV STUDIO UI actions. The agent does not inspect or operate live UI. | `artifacts/` |
| Verify | Agent | Read same-run result files after the runner exits. | `mvp_result.json`, `repair_result.json` |

The practical goal is repeatability: the same scaffold and runner command should produce the same project, variables, compile result, and evidence layout.

## Core Capabilities

| Capability | What It Does |
| --- | --- |
| Structured scaffold rendering | Converts `scaffold.model.json` into MNM files and per-module variable TSV files. |
| Multi-MNM import | Imports multiple scan-executed modules with isolated local variable tables. |
| Guarded variable entry | Applies global and local variables through checked focus gates and paste-error detection. |
| Compile evidence capture | Runs KV STUDIO conversion and copies the actual conversion result text. |
| Existing-project repair | Deletes/reimports target modules, reapplies variables, compiles, and writes `repair_result.json`. |
| Route discipline | Keeps agent reasoning outside the script-owned KV STUDIO operation phase. |

## Deterministic Repair Loop

<p align="center">
  <img src="docs/images/kv-repair-loop.png" alt="Deterministic KV STUDIO repair loop">
</p>

1. Create a buggy scaffold.
2. Run the fresh-project runner.
3. Collect the actual `转换结果 NG` text from KV STUDIO.
4. Repair the scaffold model, MNM, or variable manifest based on that text.
5. Run the existing-project repair runner with the corrected scaffold.
6. Accept success only when `repair_result.json.ok=true` and copied compile text contains `转换结果 OK`.

## Repository Layout

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

## Main Scripts

| Script | Purpose |
| --- | --- |
| `kv-studio-operator/scripts/render_kv_mvp_scaffold_model.ps1` | Renders structured scaffold models into KV STUDIO adapter files. Supports ladder-style `mnm.instructions` and ST-style `mnm.st_lines`. |
| `kv-studio-operator/scripts/validate_kv_mvp_scaffold.ps1` | Validates checklist, schema, MNM module type, model/render consistency, and unsafe variable names before KV STUDIO opens. |
| `kv-studio-operator/scripts/run_kv_mvp_scaffold.ps1` | Creates a fresh project, imports MNM files, applies variables, compiles, and copies conversion output. |
| `kv-studio-operator/scripts/run_kv_mvp_repair_existing_project.ps1` | Repairs an existing erroneous `.kpr` with corrected scaffold content. |
| `kv-studio-operator/scripts/run_kv_mvp_repeat.ps1` | Runs repeat gates and requires consecutive passing attempts. |

## Scaffold Source Of Truth

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

## Fresh Project Run

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

## Existing Project Repair

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

## Variable Name Guardrails

KV STUDIO treats names such as `X0`, `Y0`, `R100`, and `DM10` as soft-device style names. They must not be used as variable names.

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

## Verified Quadratic-Fit Case

The deliberate bug:

```text
CenterX := (0.0 - Bcoff) / (2.0 * Acoef);
```

Same-run KV STUDIO diagnostic:

```text
转换结果 NG (错误数量:1  警告数量:0)
QuadFitMain(行:00002)(列: 01)(ST行: 0016)[错误 1232]:"Bcoff": 发现非法的字符串。
```

The repair changed `Bcoff` to the defined local variable `Bcoef`. Existing-project repair and fresh-error-project repair both passed with:

```text
转换结果 OK (错误数量:0  警告数量:0)
```

## Engineering Rules

| Rule | Reason |
| --- | --- |
| Checklist before KV STUDIO operation | Prevents running uncontrolled UI scripts. |
| Script-owned KV phase | Removes agent timing/focus drift from the live IDE. |
| Same-run artifacts only | Prevents false success from stale screenshots or logs. |
| First feedback is preserved | Paste dialogs and compile diagnostics become actionable error codes. |
| Route changes require evidence | Prevents switching between UIA, keyboard, mouse, and scripts without proof. |
