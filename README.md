# KeyenceAgent

Agent-driven automation harness for building, repairing, and validating KEYENCE KV STUDIO projects through deterministic scripts.

![KeyenceAgent harness overview](docs/images/keyenceagent-harness-overview.png)

> Images in this README were generated with GPT-image2 and stored as repository assets under `docs/images/`.

## What This Repository Provides

KeyenceAgent is a skill and script set for making KV STUDIO work repeatable under an agent. The core rule is simple: the agent thinks before KV STUDIO opens and verifies artifacts after the runner exits; scripts own every KV STUDIO UI action in between.

The repository currently focuses on:

- Scaffold-first PLC project generation with MNM files and per-module variable manifests.
- Guarded KV STUDIO operation through checklist gates, UI focus guards, and bounded runner scripts.
- Multi-MNM import with global and local variable handling.
- Compile-result collection from KV STUDIO as same-run evidence.
- Existing-project repair after a compile failure, without manual UI intervention.
- Git-managed skill evolution so script behavior, docs, and evidence contracts stay diffable.

## Operating Model

The harness separates reasoning from UI operation.

| Phase | Owner | Allowed Work | Evidence |
| --- | --- | --- | --- |
| Prepare | Agent | Create/edit `scaffold.model.json`, render scaffold files, validate checklist | `scaffold_validation.json` |
| Execute | Runner scripts | Open KV STUDIO, import MNM, paste variables, compile, copy result | runner artifacts under `artifacts/` |
| Verify | Agent | Read result JSON and copied compile text | `mvp_result.json` or `repair_result.json` |

The agent must not click, type, inspect live UI, or make step-by-step UI decisions while KV STUDIO is open. If a runner fails, the next action is to diagnose the same-run artifacts and start a fresh runner command after correcting scaffold/script inputs.

## Deterministic Repair Loop

The repair path is designed for the exact failure pattern where a generated project compiles NG, the agent reads the compile text, repairs the MNM or variables, and reruns the same script framework with changed parameters.

![Deterministic KV STUDIO repair loop](docs/images/kv-repair-loop.png)

The stable repair sequence is:

1. Generate an intentionally buggy scaffold.
2. Run `run_kv_mvp_scaffold.ps1` to create/import/define/compile.
3. Read the same-run copied compile result.
4. Repair `scaffold.model.json`, then render and validate again.
5. Run `run_kv_mvp_repair_existing_project.ps1` against the existing `.kpr`.
6. Accept success only when `repair_result.json.ok=true` and copied compile text contains `转换结果 OK`.

## Important Scripts

All paths below are relative to `kv-studio-operator/scripts/`.

| Script | Purpose |
| --- | --- |
| `render_kv_mvp_scaffold_model.ps1` | Converts structured `scaffold.model.json` into MNM and per-module variable TSV files. Supports ladder-style `mnm.instructions` and ST-style `mnm.st_lines`. |
| `validate_kv_mvp_scaffold.ps1` | Validates scaffold schema, checklist presence, MNM module type, model/render consistency, and unsafe variable names before KV STUDIO opens. |
| `run_kv_mvp_scaffold.ps1` | Creates a fresh KV STUDIO project, imports MNM files, applies variables, compiles, and copies conversion output. |
| `run_kv_mvp_repair_existing_project.ps1` | Repairs an existing erroneous `.kpr` by deleting/reimporting target modules, reapplying variables, compiling, and copying conversion output. |
| `run_kv_mvp_repeat.ps1` | Runs repeat gates and requires consecutive passing attempts. |

Runner-owned child scripts live under `kv-studio-operator/scripts/mvp/`. Agents should not call child scripts as the normal path.

## Scaffold Source Of Truth

Structured scaffolds use this source layout:

```text
scaffold.model.json
CHECKLIST.md
TASK.md
VERSION.md
mnm/
variables/<module>/global_variables.tsv
variables/<module>/local_variables.tsv
scaffold.json
```

For structured projects, edit `scaffold.model.json` first, then render:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\render_kv_mvp_scaffold_model.ps1 `
  -ModelPath C:\KV_MVP\scaffolds\<task>\scaffold.model.json
```

Then validate before any KV STUDIO operation:

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

Primary success artifact:

```text
C:\KV_MVP\mvp_runs\<ProjectName>\mvp_result.json
```

Success requires:

- `ok=true`
- `compile_result_contains_ok=true`
- copied compile result exists under `artifacts/copy_result/compile_result_copied.txt`
- all runner steps have `exit_code=0`

## Existing Project Repair

Use this when a `.kpr` already exists and contains a compile error that must be repaired by corrected MNM/variables.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kv-studio-operator\scripts\run_kv_mvp_repair_existing_project.ps1 `
  -ProjectPath C:\KV_MVP\mvp_runs\<ProjectName>\Projects\<ProjectName>\<ProjectName>.kpr `
  -ScaffoldRoot C:\KV_MVP\scaffolds\<fixed-task> `
  -OutRoot C:\KV_MVP\repair_runs `
  -DeleteExistingModulesBeforeImport `
  -TimeoutSeconds 600
```

Primary success artifact:

```text
C:\KV_MVP\repair_runs\<ProjectName>\repair_result.json
```

The repair runner deletes the existing module by exact project-tree match, imports the corrected MNM, reapplies variables, compiles, and copies conversion output. It keeps the runner framework stable; the repair is expressed by runtime parameters and scaffold content.

## Variable Name Guardrails

KV STUDIO treats names such as `X0`, `Y0`, `R100`, and `DM10` as soft-device style names. They must not be used as variable names.

The scaffold validator and variable script reject soft-device-like variable names before or during guarded operation with:

```text
KV_SCAFFOLD_VARIABLE_NAME_SOFT_DEVICE_CONFLICT
KV_VARIABLE_NAME_SOFT_DEVICE_CONFLICT
```

For coordinate data, use business names such as:

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

## Example Verified Case

The quadratic-fit ST repair case used this deliberate bug:

```text
CenterX := (0.0 - Bcoff) / (2.0 * Acoef);
```

KV STUDIO produced same-run compile evidence:

```text
转换结果 NG (错误数量:1  警告数量:0)
QuadFitMain(行:00002)(列: 01)(ST行: 0016)[错误 1232]:"Bcoff": 发现非法的字符串。
```

The corrected scaffold changed `Bcoff` to the defined local variable `Bcoef`. Both paths passed:

- Existing erroneous project repair: `repair_result.json.ok=true`
- Fresh erroneous project then repair: `repair_result.json.ok=true`
- Copied compile result: `转换结果 OK (错误数量:0  警告数量:0)`

## Repository Discipline

Every script change should be committed with the validation evidence it enables. Do not treat screenshots or old artifacts as proof. A valid result must come from the current runner output directory.

Core rules:

- Checklist exists before any KV STUDIO script runs.
- Script-owned phase starts at first KV STUDIO launch and ends after compile result copy.
- No manual UI action inside runner-owned operation.
- Every failure must preserve the first useful feedback, such as KV STUDIO paste-error dialogs or compile diagnostics.
- Route changes require explicit evidence; script guard improvements inside the same route are not route changes.

