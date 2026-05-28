---
name: kv-studio-operator
description: Operate KEYENCE KV STUDIO from Codex or a Windows editor VM. Use when the task requires creating KV STUDIO projects, importing/exporting MNM mnemonic lists, editing global/local variables, compiling/converting, copying KV STUDIO result text, or running the scaffold runner workflow for a disposable PLC project.
---

# KV STUDIO Operator

## Contract

Use scripts, not ad hoc UI operation.

Set these paths before running commands:

- `SkillRoot`: this skill directory.
- `WorkRoot`: disposable working directory, normally `C:\Users\Public\KVSkillPractice`.
- `ScaffoldRoot`: one task's scaffold directory under `WorkRoot\scaffolds`.
- `OutRoot`: runner output directory under `WorkRoot\mvp_runs`.

Terms:

- `Scaffold`: source files that define one KV STUDIO project task.
- `Runner`: `scripts\run_kv_mvp_scaffold.ps1` for fresh projects or `scripts\run_kv_mvp_repair_existing_project.ps1` for existing project repair; the runner owns KV STUDIO operation.
- `Same-run artifact`: evidence written under the current runner output directory during the current command.

## Route

Use this route for new simple KV STUDIO projects:

| Step | Command | Pass condition | Stop condition |
| --- | --- | --- | --- |
| Create scaffold | `scripts\new_kv_mvp_scaffold.ps1` | `scaffold.json` and `CHECKLIST.md` exist | Script exits nonzero |
| Edit scaffold | Agent edits scaffold files only | Each MNM and its paired variable TSVs, task notes, version notes reflect the task | Required files missing or ambiguous |
| Validate scaffold | `scripts\validate_kv_mvp_scaffold.ps1` | `scaffold_validation.json.ok=true` | Any `KV_SCAFFOLD_*` or checklist error |
| Run KV STUDIO | `scripts\run_kv_mvp_scaffold.ps1` | `mvp_result.json.ok=true` | Any child step fails |
| Prove repeatability | `scripts\run_kv_mvp_repeat.ps1` | `repeat_result.json.ok=true` after 3 consecutive passes | Any failed attempt resets consecutive pass count |
| Report | Read current-run artifacts | Report result path and evidence paths | Do not use old run artifacts |

Use this route for existing project updates, including user-requested feature additions to a `.kpr`:

| Step | Command | Pass condition | Stop condition |
| --- | --- | --- | --- |
| Create/update workspace | `scripts\new_kv_existing_project_update_workspace.ps1` | `source_snapshot_manifest.json.status=ready` | `KV_SOURCE_SNAPSHOT_EXPORT_REQUIRED` or script exits nonzero |
| Verify current source snapshot | `scripts\assert_kv_existing_project_snapshot.ps1` | `existing_project_snapshot_gate.json.ok=true` and project fingerprint matches | `KV_SOURCE_SNAPSHOT_STALE`, missing MNM, missing variable manifest, or missing architecture file |
| Edit update scaffold | Agent edits scaffold/model files before KV STUDIO opens | Logic and variables are derived from the verified snapshot plus task request | Snapshot is stale or architecture intent is ambiguous |
| Run existing-project update | `scripts\run_kv_mvp_repair_existing_project.ps1 -SourceSnapshotManifestPath <manifest>` | `repair_result.json.ok=true` and source snapshot gate is included in result | Any child step fails |
| Verify | Read same-run artifacts | Compile text contains `转换结果 OK` and result references the snapshot manifest | Do not use old exports or old compile text |

Agent participation boundary:

- Before KV STUDIO opens, the agent may create/edit scaffold files, run validation, and start `run_kv_mvp_scaffold.ps1`, `run_kv_mvp_repair_existing_project.ps1`, or `run_kv_mvp_repeat.ps1`.
- From the first KV STUDIO launch through compile-result copy, operation is script-owned. The agent must not inspect the live UI, decide the next UI action, paste into KV STUDIO, click, type, or call child MVP scripts as a normal path.
- After the runner exits, the agent may verify only same-run artifacts such as `mvp_result.json`, `repeat_result.json`, copied compile text, variable persistence JSON, and guard checkpoints.
- If the runner fails, diagnose from result JSON and artifacts first. Any further KV STUDIO operation must start as a fresh runner command after scaffold/script repair, not as an in-window manual continuation.

Create scaffold:

```powershell
$SkillRoot = '<path-to-kv-studio-operator-skill>'
$WorkRoot = 'C:\Users\Public\KVSkillPractice'
$ScaffoldRoot = Join-Path $WorkRoot 'scaffolds\<task-id>'

powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\new_kv_mvp_scaffold.ps1" `
  -ScaffoldRoot $ScaffoldRoot `
  -ProjectName '<project-name>' `
  -CpuModel KV-X310 `
  -ModuleName Main_MVP `
  -Template Minimal `
  -TaskSummary '<task summary>'
```

Validate scaffold:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\validate_kv_mvp_scaffold.ps1" `
  -ScaffoldRoot $ScaffoldRoot `
  -OutDir (Join-Path $ScaffoldRoot '_validation')
```

Validate variable definition files directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\assert_kv_variable_definitions.ps1" `
  -TsvPath '<module-global.tsv>','<module-local.tsv>' `
  -Scope any `
  -ExpectedOwnerProgram '<module-name>' `
  -OutPath '<out>\variable_definition_validation.json'
```

Run scaffold:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\run_kv_mvp_scaffold.ps1" `
  -ScaffoldRoot $ScaffoldRoot `
  -OutRoot (Join-Path $WorkRoot 'mvp_runs') `
  -TimeoutSeconds 600
```

Repair an existing project from a corrected scaffold:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\new_kv_existing_project_update_workspace.ps1" `
  -ProjectPath '<existing-project.kpr>' `
  -WorkspaceRoot (Join-Path $WorkRoot 'existing_project_updates') `
  -TaskId '<task-id>'

powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\assert_kv_existing_project_snapshot.ps1" `
  -ProjectPath '<existing-project.kpr>' `
  -SnapshotManifestPath (Join-Path $WorkRoot 'existing_project_updates\<task-id>\source_snapshot_manifest.json') `
  -OutDir (Join-Path $WorkRoot 'existing_project_updates\<task-id>\validation\source_snapshot_gate')

powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\run_kv_mvp_repair_existing_project.ps1" `
  -ProjectPath '<existing-project.kpr>' `
  -ScaffoldRoot $ScaffoldRoot `
  -SourceSnapshotManifestPath (Join-Path $WorkRoot 'existing_project_updates\<task-id>\source_snapshot_manifest.json') `
  -OutRoot (Join-Path $WorkRoot 'mvp_repair_runs') `
  -DeleteExistingModulesBeforeImport `
  -LocalPasteFormat NameType `
  -TimeoutSeconds 600
```

For projects not created by this skill, do not use `-SeedScaffoldRoot` as proof. Export current MNM files and variable manifests from the exact project into the workspace snapshot, record inventory evidence, then set `source_snapshot_manifest.json.status` to `ready`. If the project directory hash differs from the last parsed snapshot, the gate fails and a fresh export is required. `-SeedTrust SameRunSkillBaseline` is reserved for `run_kv_mvp_scaffold.ps1` baseline snapshots produced immediately after that same runner creates and compiles the project.

For multi-MNM stages that must prove local variables independently of compile, run the scaffold with `-AuditVariablePersistence`. The runner will close/reopen the variable editor, copy each module's local grid, and match expected local names before compile.

Multi-MNM local-variable proof requires per-module first-column isolation: the copied local grid for module A must contain A's local names with their expected data types in the first two columns, and must not contain any other module's local names in the first column. The normal local paste route is: select local tab, select the target local program, focus the local program combo, send `Tab`, send `PgDn`, then paste the full local variable rows. If an audit copy is taken before paste, the script must refocus the local program combo before sending `Tab`.

Run repeat gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\run_kv_mvp_repeat.ps1" `
  -ScaffoldRoot $ScaffoldRoot `
  -OutRoot (Join-Path $WorkRoot 'mvp_repeat_runs') `
  -AuditVariablePersistence `
  -RequiredConsecutivePasses 3 `
  -MaxAttempts 6 `
  -StopAfterSameFailureCount 3 `
  -TimeoutSeconds 600
```

## Scaffold Files

Edit only scaffold source files before running KV STUDIO:

- `scaffold.model.json` when present. This is the source of truth for structured scaffolds.
- `mnm\*.mnm`
- `scaffold.json.mnm_files[].variables.global_tsv`
- `scaffold.json.mnm_files[].variables.local_tsv`
- `architecture\*.json` for open-ended project/update configuration such as source snapshot binding, IO map, unit map, safety notes, acceptance, and future categories.
- `TASK.md`
- `VERSION.md`
- `CHECKLIST.md`

Do not hand-edit generated runner artifacts.

For structured scaffolds, edit `scaffold.model.json` first and then run `scripts\render_kv_mvp_scaffold_model.ps1`. Treat generated MNM and TSV files as KV STUDIO adapter artifacts. Edit generated MNM/TSV directly only for diagnosis or for legacy scaffolds without `scaffold.model.json`.

Variable files are per MNM/module. Do not assume one project-level `variables\global_variables.tsv` or `variables\local_variables.tsv`. For each `scaffold.json.mnm_files[]` entry, edit the MNM file named by `path`, then edit that entry's paired `variables.global_tsv` and `variables.local_tsv`.

Minimum TSV header:

```text
scope	owner_program	name	data_type	device	initial_value	comment	evidence	status
```

Executable variable rows use `status` other than `display_name`.

MNM module type:

- `;MODULE_TYPE:0` means scan-executed program/module.
- `;MODULE_TYPE:2` means function block, but the current MVP runner rejects it with `KV_SCAFFOLD_FB_SUPPORT_INCOMPLETE`.
- Function-block support requires a separate contract for FB definition, FB instance variables, call points, instance scope, import order, and compile-error classification before KV STUDIO operation.
- The value in each MNM file must match `scaffold.json.mnm_files[].module_type`; use `0` for the supported MVP path.

## Hard Gates

- Checklist gate: every KV STUDIO operation must pass `scripts\assert_kv_operation_checklist.ps1`.
- Variable definition gate: every generated or edited variable TSV must pass `scripts\assert_kv_variable_definitions.ps1` or the equivalent shared validator before KV STUDIO opens.
- Existing-project source gate: before modifying an existing `.kpr`, `scripts\assert_kv_existing_project_snapshot.ps1` must prove that the current project fingerprint matches a ready source snapshot containing MNM files, variable manifests, inventory evidence, and an open architecture file.
- Scaffold gate: an existing scaffold must pass `scripts\validate_kv_mvp_scaffold.ps1` before runner use.
- UI guard gate: the runner must pass `scripts\assert_kv_mvp_ui_guard_usage.ps1` before touching KV STUDIO.
- Agent boundary gate: the runner must pass `scripts\assert_kv_mvp_agent_boundary.ps1` before touching KV STUDIO; this rejects interactive prompts/manual decision points in runner-owned scripts.
- Program construction uses MNM files. If MNM import fails, fix the scaffold or stop; do not type program text into the ladder/editor.
- Variables are mandatory per MNM entry. `variables.local_tsv` must contain executable local rows for that module/program. `variables.global_tsv` may be header-only only when that MNM uses no global variables.
- Executable global variable rows must be referenced by their paired MNM file. The compile gate proves the variables used by the imported program. Local variable close/reopen/copy verification is an audit path, not the default fast path.
- Success must come from the current run's `mvp_result.json`, not screenshots or old compile text.

## Script Ownership

Agents normally call only:

- `scripts\new_kv_mvp_scaffold.ps1`
- `scripts\new_kv_mvp_multi_mnm_scaffold.ps1`
- `scripts\new_kv_existing_project_update_workspace.ps1`
- `scripts\assert_kv_existing_project_snapshot.ps1`
- `scripts\assert_kv_variable_definitions.ps1`
- `scripts\validate_kv_mvp_scaffold.ps1`
- `scripts\run_kv_mvp_scaffold.ps1`
- `scripts\run_kv_mvp_repair_existing_project.ps1`
- `scripts\run_kv_mvp_repeat.ps1`

Child scripts under `scripts\mvp\` are runner-owned. Call them directly only when diagnosing a failed runner step.

All global keyboard, mouse, menu accelerator, and paste operations must be implemented through `scripts\mvp\kv_ui_guard.ps1`. Read `references\ui-guard-contract.md` only when modifying or diagnosing UI guard behavior.

When KV STUDIO is open, agent reasoning is outside the control loop. The runner must carry all ordered steps, waits, focus checks, recovery hypotheses, and stop conditions. Agent verification resumes only after the runner exits and writes result artifacts.

## Result Contract

Primary result:

```text
<OutRoot>\<ProjectName>\mvp_result.json
```

Report success only when:

- `mvp_result.json.ok` is `true`.
- `mvp_result.json.compile_result_contains_ok` is `true`.
- `artifacts\module_placement\*.json` shows expected module category.
- `artifacts\set_variables\variable_persistence_validation.json` exists and reports success. In fast mode, local persistence is accepted through the variable script plus compile gate; close/reopen/copy evidence is required only when `set_variables_guarded.ps1 -AuditPersistence` is used.
- `mvp_result.json.variable_sets[]` lists each MNM entry's exact global/local TSV paths used in the run.
- `mvp_result.json.baseline_source_snapshot.source_snapshot_manifest` points to a reusable source snapshot for future updates when the project fingerprint still matches.
- `mvp_result.json.agent_boundary_contract_path` points to the same-run agent-boundary contract.
- `artifacts\copy_result\compile_result_copied.txt` was written in the current run.

Report repeatable MVP success only when `run_kv_mvp_repeat.ps1` writes `repeat_result.json.ok=true` and `repeat_result.json.consecutive_passes` is at least `3`. A failed attempt resets the consecutive pass counter to `0`; do not count non-consecutive passes. If the same failure signature appears three times, the repeat runner stops for route review.

Report existing-project update success only when `repair_result.json.ok=true`, `repair_result.json.source_snapshot_gate.ok=true`, and `repair_result.json.source_snapshot_gate.project_fingerprint.hash` matches the current project snapshot gate result. If the snapshot gate is missing from the repair result, the update is not accepted.

For artifact layout and JSON fields, read `references\mvp-runner-contract.md`.

## Failure Reporting

If a command exits nonzero, stop and report:

- Stable error code from stderr or result JSON.
- Current step.
- Evidence path.
- Next concrete repair action.

Common gate codes:

- `KV_CHECKLIST_MISSING`, `KV_CHECKLIST_EMPTY`, `KV_CHECKLIST_INVALID`
- `KV_SCAFFOLD_REQUIRED_FILE_MISSING`, `KV_SCAFFOLD_TSV_SCHEMA_INVALID`, `KV_SCAFFOLD_MNM_MODULE_TYPE_MISMATCH`
- `KV_SCAFFOLD_FB_SUPPORT_INCOMPLETE`
- `KV_SOURCE_SNAPSHOT_MANIFEST_MISSING`, `KV_SOURCE_SNAPSHOT_NOT_READY`, `KV_SOURCE_SNAPSHOT_STALE`, `KV_SOURCE_SNAPSHOT_MNM_EMPTY`, `KV_SOURCE_SNAPSHOT_VARIABLES_EMPTY`, `KV_UPDATE_ARCHITECTURE_FILE_MISSING`
- `KV_VARIABLE_DATA_TYPE_UNSUPPORTED`, `KV_VARIABLE_TSV_SCHEMA_INVALID`, `KV_VARIABLE_NAME_SOFT_DEVICE_CONFLICT`, `KV_VARIABLE_LOCAL_OWNER_MISSING`, `KV_VARIABLE_LOCAL_OWNER_MISMATCH`
- `KV_UI_GUARD_STATIC_VIOLATION`
- `KV_FOCUS_LOST`, `KV_FOCUS_LOST_TERMINAL`, `KV_MODAL_PRESENT`
- `KV_VARIABLE_PASTE_NOT_PERSISTED`

## References

- `references\ui-guard-contract.md`: read when changing or diagnosing guarded UI input.
- `references\mvp-runner-contract.md`: read when interpreting runner artifacts or result schema.
- `references\variable-editor.md`: read when changing variable TSV schema or diagnosing variable editor paste.
