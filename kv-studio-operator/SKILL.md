---
name: kv-studio-operator
description: Operate KEYENCE KV STUDIO through script-owned Windows desktop automation. Use when the task requires creating KV STUDIO projects, importing/exporting MNM mnemonic lists, editing global/local variables, compiling/converting, copying KV STUDIO result text, or running the scaffold runner workflow for a disposable PLC project.
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
| Plan MNM import | `scripts\assert_kv_mnm_import_plan.ps1` | Same-name incoming MNM conflicts are absent, or `-DeleteExistingModulesBeforeImport` is explicitly planned | `KV_MNM_SAME_NAME_IMPORT_REQUIRES_PREDELETE`, duplicate incoming module names, stale/export-required snapshot |
| Edit update scaffold | Agent edits scaffold/model files before KV STUDIO opens | Logic and variables are derived from the verified snapshot plus task request | Snapshot is stale or architecture intent is ambiguous |
| Run existing-project update | `scripts\run_kv_mvp_repair_existing_project.ps1 -SourceSnapshotManifestPath <manifest>` | `repair_result.json.ok=true` and source snapshot gate is included in result | Any child step fails |
| Verify | Read same-run artifacts | Compile text contains `转换结果 OK` and result references the snapshot manifest | Do not use old exports or old compile text |

Agent participation boundary:

- Before KV STUDIO opens, the agent may create/edit scaffold files, run validation, and start `run_kv_mvp_scaffold.ps1`, `run_kv_mvp_repair_existing_project.ps1`, or `run_kv_mvp_repeat.ps1`.
- From the first KV STUDIO launch through compile-result copy, operation is script-owned. The agent must not inspect the live UI, decide the next UI action, paste into KV STUDIO, click, type, or call child MVP scripts as a normal path.
- After the runner exits, the agent may verify only same-run artifacts such as `mvp_result.json`, `repeat_result.json`, copied compile text, variable persistence JSON, and guard checkpoints.
- If the runner fails, diagnose from result JSON and artifacts first. Any further KV STUDIO operation must start as a fresh runner command after scaffold/script repair, not as an in-window manual continuation.

Compound workflows:

```yaml
kv_compound_workflow:
  rule: mature_script_segments_first
  segment_order:
    - mature_script_to_checkpoint
    - unknown_ui_transition_probe
    - mature_script_to_next_checkpoint
  checkpoint_required:
    - same_run_result_json
    - target_window_or_artifact_identity
    - editable_mode_when_project_editing
    - selected_project_tree_object_when_relevant
  stop_conditions:
    - mature_script_checkpoint_missing
    - unexpected_window_before_unknown_probe
    - probe_attempt_starts_from_initial_ui_when_mature_prefix_exists
  classification:
    unexpected_window_before_checkpoint: route_design_error
    unexpected_window_after_checkpoint: transition_failure
    mature_script_changed_for_probe: mature_script_boundary_violation
```

For a new KV STUDIO capability inside a larger workflow, do not explore from the initial project window when an existing script can reach the nearest precondition. Run the mature script to that checkpoint, assert the checkpoint artifact/window, then probe only the new transition. After that transition is verified, turn it into a small script segment and resume the next mature script. If a run enters an unrelated or never-seen window before the checkpoint is proven, treat it as `route_design_error`, not as evidence about the new feature.

Primitive script boundary:

```yaml
primitive_scripts:
  status:
    scripts/mvp/export_mnm_guarded.ps1: probe_only_until_success_artifact
    scripts/mvp/export_mnm_browse_default_folder_guarded.ps1: internal_core_for_default_browse_folder_route
    scripts/mvp/export_mnm_project_copy_default_folder.ps1: independent_mature_for_existing_project_mnm_export
    scripts/mvp/import_mnm_guarded.ps1: immutable_during_feature_probe
    scripts/mvp/compile_and_copy_result_bounded.ps1: immutable_during_feature_probe
    scripts/filter_kv_mnm_user_sources.ps1: immutable_during_feature_probe
  maturity_states:
    independent_mature:
      requires:
        - direct_invocation_ok_artifact
        - documented_preconditions_created_by_script_itself
    wrapper_dependent:
      requires:
        - parent_runner_or_wrapper
        - upstream_preconditions
        - same_run_ok_artifact_from_parent_context
      direct_call_failure_classification: missing_or_unproven_precondition
    probe_only:
      requires:
        - no_ok_artifact_yet
  maturity_required:
    - export_mnm_result_json_ok_true
    - same_run_mnm_files
    - invocation_context_or_parent_runner
  rule: run_or_restore
  forbidden:
    - add_new_workflow_logic_to_primitive
    - replace_known_fast_path_with_unverified_ui_route
    - widen_one_primitive_to_cover_multiple_goals
  allowed_changes:
    - fix_regression_in_the_same_original_goal
    - add_observation_artifacts_without_changing_action_path
    - create_new_versioned_probe_or_wrapper
```

If a primitive script is too coarse for a task, keep it unchanged and create an orchestrator or probe script. `export_mnm_guarded.ps1` owns only "export MNM from an exact project to a directory", but it is not an independent mature segment until an `export_mnm_result.json.ok=true` artifact exists for the exact invocation context. If the only success evidence is inside a parent runner, classify it as `wrapper_dependent` and record the parent runner plus the upstream preconditions it creates, such as foreground KV STUDIO window, edit mode, project tree focus, keyboard state, and absence of modal dialogs. Project replication must call proven stable segments, then perform filtering, scaffold construction, and import through separate scripts. A failed route inside a primitive is not a reason to mutate that primitive during the task; restore it, inspect git history and caller context, then move experiments into a task-local probe.

MNM export stable route:

```yaml
script: scripts/mvp/export_mnm_project_copy_default_folder.ps1
route:
  - set_WorkRoot_to_ExportDir/_kv_export_workspace_unless_explicitly_inside_ExportDir
  - copy_source_project_directory_to_WorkRoot
  - remove_mnm_files_from_project_copy
  - open_copied_kpr
  - Alt+F
  - R
  - S
  - confirm_export_option_dialog
  - accept_browse_folder_default_selected_project_directory
  - copy_same_run_mnm_files_to_ExportDir
success:
  - export_mnm_project_copy_result.json.ok == true
  - mnm_files.count > 0
  - actual_kv_export_dir starts_with ExportDir
  - core_result_path points_to_same_run_browse_folder_export_result
rejected:
  - BFFM_SETSELECTIONW_as_custom_folder_selection
  - direct_export_mnm_guarded_as_stable_without_ok_artifact
evidence:
  - C:\Users\Public\KVSkillPractice\kv_clone_taizhou_20260531\export_mnm_browse_probe9_default_copy_yes\browse_folder_export_result.json
  - C:\Users\Public\KVSkillPractice\kv_clone_taizhou_20260531\export_mnm_browse_probe10_default_copy_repeat\browse_folder_export_result.json
  - C:\Users\Public\KVSkillPractice\kv_clone_taizhou_20260531\export_mnm_browse_probe11_default_copy_repeat\browse_folder_export_result.json
  - C:\Users\Public\KVSkillPractice\kv_clone_taizhou_20260531\stable_export_run1\out\export_mnm_project_copy_result.json
```

Do not use `BFFM_SETSELECTIONW` as the folder-selection mechanism for KV STUDIO MNM export. In verified runs it left the tree selection on the default project folder or destabilized KV STUDIO. To export into an arbitrary caller directory, control the project copy location inside `ExportDir`, accept the Browse Folder default selection inside that file framework, then copy the produced `.mnm` files to the requested `ExportDir`.

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

Configure the local KV STUDIO administrator credential once per Windows user before project creation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\set_kv_admin_credential.ps1"
```

The default credential file is `%APPDATA%\Codex\kv-studio-operator\credentials.xml`. It is a Windows DPAPI `Export-Clixml` file and must not be committed. Runners may also pass `-AdminUser/-AdminPassword` or `-AdminCredentialPath`; do not store passwords in scaffold files, skill text, README files, or git.

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

powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\assert_kv_mnm_import_plan.ps1" `
  -ScaffoldRoot $ScaffoldRoot `
  -SourceSnapshotManifestPath (Join-Path $WorkRoot 'existing_project_updates\<task-id>\source_snapshot_manifest.json') `
  -SourceSnapshotGateResultPath (Join-Path $WorkRoot 'existing_project_updates\<task-id>\validation\source_snapshot_gate\existing_project_snapshot_gate.json') `
  -OutDir (Join-Path $WorkRoot 'existing_project_updates\<task-id>\validation\mnm_import_plan_gate')

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
- `modules\<module>\*.mnm` for new structured scaffolds; `mnm\*.mnm` is a legacy-compatible layout only.
- `scaffold.json.mnm_files[].variables.global_tsv`
- `scaffold.json.mnm_files[].variables.local_tsv`
- `architecture\*.json` for open-ended project/update configuration such as source snapshot binding, IO map, unit map, safety notes, acceptance, and future categories.
- `architecture\network_config.json` for EtherCAT and EtherNet/IP unit configuration intent. Network/unit configuration belongs here, not in `TASK.md`, `VERSION.md`, MNM comments, or variable TSV files.
- `TASK.md`
- `VERSION.md`
- `CHECKLIST.md`

Do not hand-edit generated runner artifacts.

For structured scaffolds, edit `scaffold.model.json` first and then run `scripts\render_kv_mvp_scaffold_model.ps1`. Treat generated MNM and TSV files as KV STUDIO adapter artifacts. New scaffolds place each module under `modules\<module>\` with that module's MNM, global TSV, local TSV, and optional FB argument TSV together. Edit generated MNM/TSV directly only for diagnosis or for legacy scaffolds without `scaffold.model.json`.

Variable files are per MNM/module. Do not assume one project-level `variables\global_variables.tsv` or `variables\local_variables.tsv`. For each `scaffold.json.mnm_files[]` entry, edit the MNM file named by `path`, then edit that entry's paired `variables.global_tsv` and `variables.local_tsv`; in new scaffolds these files should live in the same module folder.

Minimum TSV header:

```text
scope	owner_program	name	data_type	device	initial_value	comment	evidence	status
```

Executable variable rows use `status` other than `display_name`.

MNM module type:

- `;MODULE_TYPE:0` means ordinary program MNM. It does not by itself distinguish scan-executed and standby modules.
- `;MODULE_TYPE:2` means user function block.
- `scaffold.json.mnm_files[].category` should be `scan`, `standby`, or `function_block`. If omitted, `0` maps to `scan` and `2` maps to `function_block`.
- Function-block instance variables use the FB module name as `data_type`. The variable validator allows only FB names declared by `module_type=2` in the same scaffold.
- `standby` is represented by scaffold metadata, not a unique MNM module type. During MNM import, `import_mnm_guarded.ps1` must select `后备模块` in the `选择程序种类` dialog before OK. Current proof: `C:\Users\Public\KVSkillPractice\standby_module_20260529\runs\standby_import_program_kind_fix\StandbyImportProbe\mvp_result.json`.
- `interrupt` remains gated with `KV_SCAFFOLD_MODULE_CATEGORY_SUPPORT_INCOMPLETE`: Wiki evidence says interrupt modules also require CPU system settings for fixed-cycle/user-interrupt factors plus interrupt enable, not just MNM import.
- The value in each MNM file must match `scaffold.json.mnm_files[].module_type`.

## Hard Gates

Gate integrity:

```yaml
gate_integrity:
  invariant: gate_semantics_are_correctness
  pass_condition: required_semantic_evidence_present_in_same_run
  forbidden:
    - dummy_variable_rows_to_satisfy_non_empty_tsv
    - placeholder_or_stub_snapshot_files_as_project_evidence
    - weakening_or_deleting_validation_rules_to_continue
    - treating_file_presence_as_semantic_completeness
    - continuing_after_gate_failure_by_relabeling_the_failure
  exception_only_if:
    suspected_wrong_gate:
      required:
        - written_failure_evidence
        - exact_gate_rule_under_challenge
        - why_artifact_is_valid_despite_gate_failure
        - task_local_patch_or_wrapper_only
        - independent_subagent_strict_audit_before_execution
      audit_must_answer:
        - gate_wrong_or_artifact_incomplete
        - exception_preserves_original_acceptance_semantics
        - downstream_compile_import_evidence_would_be_polluted
      if_subagent_unavailable: stop_and_report_gate_blocker
  failure_boundary:
    variable_manifest_incomplete: stop
    source_snapshot_stub: stop
    scaffold_dummy_rows: stop
    compile_after_bypassed_gate: invalid_evidence
```

- Checklist gate: every KV STUDIO operation must pass `scripts\assert_kv_operation_checklist.ps1`.
- Variable definition gate: every generated or edited variable TSV must pass `scripts\assert_kv_variable_definitions.ps1` or the equivalent shared validator before KV STUDIO opens.
- Existing-project source gate: before modifying an existing `.kpr`, `scripts\assert_kv_existing_project_snapshot.ps1` must prove that the current project fingerprint matches a ready source snapshot containing MNM files, variable manifests, inventory evidence, and an open architecture file.
- MNM import plan gate: before modifying an existing `.kpr`, `scripts\assert_kv_mnm_import_plan.ps1` compares incoming `scaffold.json.mnm_files[].module_name` values with the verified source snapshot MNM inventory. Direct import is forbidden when a same-name module already exists. If a conflict exists, the top-level runner must be invoked with `-DeleteExistingModulesBeforeImport`, and the child import step must pre-delete that module before importing its replacement. If the project fingerprint no longer matches the snapshot, export current MNM first and re-plan.
- Scaffold gate: an existing scaffold must pass `scripts\validate_kv_mvp_scaffold.ps1` before runner use. This gate requires `architecture\network_config.json` and rejects structured network payload keys such as `node_address`, `ip_address`, `device_path`, or `esi_path` in `TASK.md`, `VERSION.md`, MNM comments, or variable TSV files with `KV_SCAFFOLD_NETWORK_CONFIG_LEAK`.
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
- `scripts\assert_kv_mnm_import_plan.ps1`
- `scripts\assert_kv_variable_definitions.ps1`
- `scripts\validate_kv_mvp_scaffold.ps1`
- `scripts\filter_kv_mnm_user_sources.ps1`
- `scripts\run_kv_mvp_scaffold.ps1`
- `scripts\run_kv_mvp_repair_existing_project.ps1`
- `scripts\run_kv_mvp_repeat.ps1`
- `scripts\configure_kv_network_from_config.ps1`
- `scripts\configure_kv_expansion_units.ps1`

## 官方/库 FB 过滤

复刻项目时，官方/库 FB 是依赖，不是用户源码。

模块、EtherCAT、EtherNet/IP、Universal Library 等操作可能自动导入官方 FB；其中很多不可编辑。不要把这类 FB 当作用户 FB 导出、重命名、再导入。

导出 MNM 后必须先运行过滤器：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\filter_kv_mnm_user_sources.ps1" `
  -InputDir '<raw-mnm-dir>' `
  -OutputDir '<filtered-mnm-dir>' `
  -ProjectPath '<project.kpr>' `
  -OutDir '<filter-report-dir>'
```

过滤规则：

```text
if MODULE_TYPE != 2:
  copy
else if name in project WsTreeEnv official/library names:
  exclude
else if name matches ^(MC_|_MC_|\[MC\]_|_\[MC\]_|ModbusTCPClient_|SocketTCP_):
  exclude
else:
  copy as user_fb
```

`MC_*` / `[MC]_*` 是 KEYENCE 运动控制官方/库 FB 模式；Universal Library 与通信库 FB 以项目树证据优先。禁止按单个用户 FB 名称做白名单。

## PLC Expansion Unit Configuration

Use `scripts\configure_kv_expansion_units.ps1` only for adding registered KV expansion units through the project-tree unit configuration route:

```text
单元配置 -> [0] KV-X310 -> 单元编辑器 - 编辑模式 -> Alt+1 选择单元
```

Open `[0] KV-X310` with `Enter`; do not enter EtherCAT, EtherNet/IP, or communication settings. The script focuses the unit list with `Alt+1`, scans by reading the current selection detail fields, presses `Enter` on matched unit names, clicks the unit editor `OK`, saves the project, and reads `WsTreeEnv.xml` for slot/address evidence.

Use comma-separated patterns when invoking through `powershell -File`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\configure_kv_expansion_units.ps1" `
  -ProjectName '<open-project-name>' `
  -ProjectPath '<project.kpr>' `
  -UnitNamePatterns 'KV-B16X*,KV-AD40V' `
  -MaxDurationSeconds 180 `
  -OutDir (Join-Path $WorkRoot 'kv_unit_config_runs')
```

Stable clean-project evidence currently covers adding `KV-B16X*` and `KV-AD40V` in 29.233 seconds, then passing `Ctrl+F9` conversion with copied result text. The parsed unit tree entries were:

```text
[1] KV-B16X*  R33000  -----
[2] KV-AD40V  R34000  DM10300
```

Treat `WsTreeEnv.xml` entries as the readable project evidence for unit slot and start-address parameters. Use `UnitSet.ue2` only as auxiliary binary evidence.

## PLC Unit Start Address Configuration

Use `scripts\configure_kv_unit_start_addresses.ps1` only for editing start-address fields of an already imported PLC unit through its exact project-tree unit item:

```text
单元配置 -> [<slot>] <unit> -> 单元编辑器 - 编辑模式 -> 设定单元(2)
```

Do not open `[0] KV-X310` and then move inside the unit editor for this task. Verified evidence showed that CPU-entry editing can drift to `[0] KV-X310` while the property table still exposes similar address rows.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\configure_kv_unit_start_addresses.ps1" `
  -ProjectName '<open-project-name>' `
  -ProjectPath '<project.kpr>' `
  -UnitName 'KV-SSC02' `
  -Slot 1 `
  -FirstDm 1000 `
  -FirstRelay 1000 `
  -MaxDurationSeconds 60 `
  -OutDir (Join-Path $WorkRoot 'kv_unit_address_runs')
```

Address entry rules:

```text
首 DM 编号: input 1000 -> saved DM1000
首继电器编号(按通道设定): input 10 -> saved R1000
relay_channel = FirstRelay / 100
```

The script rejects `FirstRelay` values not divisible by `100`. It closes stale `转换结果` dialogs before opening the unit editor. It refuses to reuse an already-open unit editor, because the stable precondition is direct project-tree selection of the target unit.

Current same-run evidence:

```text
C:\Users\Public\KVSkillPractice\kv_unit_address_runs\20260531_155121_360_configure_kv_unit_start_addresses.json
[1] KV-SSC02 R1000 DM1000
elapsed 15.921s
Ctrl+F9: 转换结果 OK (错误数量:0 警告数量:0)
```

## EtherNet/IP Unit Configuration

Scaffolds generated by this skill include `architecture\network_config.json` with this route:

```json
{
  "schema_version": 1,
  "route": "project_tree_unit_configuration",
  "ethernet_ip": { "devices": [] },
  "ethercat": { "devices": [] }
}
```

This file is the scaffold-side declaration of network/unit configuration. The KV STUDIO project is still changed by the dedicated unit-configuration scripts below; do not put EtherCAT or EtherNet/IP setup instructions in MNM source or variable TSV files.

Run the network config against an already open project with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\configure_kv_network_from_config.ps1" `
  -ProjectName '<open-project-name>' `
  -NetworkConfigPath '<scaffold>\architecture\network_config.json' `
  -OutDir (Join-Path $WorkRoot 'kv_network_config_runs')
```

Supported `network_config.json` device entries:

```json
{
  "ethernet_ip": {
    "devices": [
      {
        "device_name_pattern": "SR-2000",
        "node_address": 8,
        "ip_address": "192.168.0.18",
        "variable_name_prefix": "eip_n008"
      }
    ]
  },
  "ethercat": {
    "devices": [
      {
        "device_path": ["KEYENCE CORPORATION", "Servo Drives", "SV3"],
        "batch_axis_registration": "No"
      }
    ]
  }
}
```

`ethercat.devices[].esi_path` is reserved but intentionally rejected with `KV_ETHERCAT_ESI_REGISTRATION_UNSTABLE`. The stable route currently requires ESI files to be registered before running device-add automation.

Use `scripts\configure_kv_ethernet_ip_device.ps1` only for the project-tree unit configuration route:

```text
单元配置 -> [0] KV-X310 -> EtherNet/IP -> 手动设定
```

Do not use toolbar/menu communication settings for this task; that configures PC-to-PLC debugging communication, not project EtherNet/IP scanner/device setup.

The script selects an existing EtherNet/IP device-list entry by reading the device detail fields after `Alt+1` focuses the list. It then opens the adapter initial setting dialog, writes node address and IP address, confirms the adapter dialog, confirms the main EtherNet/IP setting window, confirms the unit editor, and fills the `EtherNet/IP设备 变量设置` dialog with per-row variable names.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\configure_kv_ethernet_ip_device.ps1" `
  -ProjectName '<open-project-name>' `
  -DeviceNamePattern 'SR-1000' `
  -NodeAddress 1 `
  -IpAddress '192.168.0.11' `
  -VariableNamePrefix 'eip_n001' `
  -OutDir (Join-Path $WorkRoot 'kv_network_config_runs')
```

`DeviceNamePattern` without `*` or `?` uses prefix-boundary matching, so `SR-200` does not match `SR-2000`. Use explicit wildcards only when fuzzy matching is intentional, for example `'*Code Reader*'`.

If `-VariableNames` is omitted, the script generates two names from `-VariableNamePrefix` or from `-NodeAddress`: `<prefix>_in100` and `<prefix>_out101`. The variable-name grid does not accept bulk paste reliably; the script focuses the grid, moves to the variable-name column, and types names one cell at a time.

After registration, the generated names are global structured variables. Use `scripts\get_kv_ethernet_ip_device_members.ps1` to read the local KV STUDIO EDS/XML cache and list valid ST member references before writing code:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\get_kv_ethernet_ip_device_members.ps1" `
  -DeviceNamePattern 'SR-2000' `
  -VariableNamePrefix 'eip_n008' `
  -Assembly 100,101 `
  -Json
```

For SR-2000 local evidence, the OUT101 clear bit is `ErrClear`, not `ErrorClr`. Treat the parsed `IOComment/ENG` names in `C:\ProgramData\KEYENCE\KVS\EIP_Eds\*.xml` as the source of truth. Example ST references:

```text
eip_n008_out101.ErrClear
eip_n008_out101.ReadReq
eip_n008_out101.ReadCmpltClr
eip_n008_in100.ReadCmplt
```

For compile verification in this task family, use KV STUDIO conversion `Ctrl+F9`. `Ctrl+F2` can enter simulator/monitor mode and is not a valid compile oracle for network configuration usage validation. If KV STUDIO is already in simulator mode, return to editor mode before continuing and verify the title contains `[编辑器: <CPU>]`.

## EtherCAT Unit Configuration

Use `scripts\configure_kv_ethercat_device.ps1` only for the project-tree unit configuration route:

```text
单元配置 -> [0] KV-X310 -> EtherCAT -> 手动设定
```

The verified SV3 route is keyboard-based:

1. Open EtherCAT from the project tree unit configuration branch.
2. Choose manual setting.
3. In the device tree, expand `KEYENCE CORPORATION -> Servo Drives`.
4. Select the `SV3` leaf item.
5. Press `Enter` to add the device. Do not use drag/drop for this route.
6. Click the EtherCAT setting window `OK`.
7. Confirm the Universal Library import dialog for `KEYENCE_SV3`.
8. For the batch axis registration prompt, choose according to `-BatchAxisRegistration`; the validated default is `No`.
9. Save the project and verify with `Ctrl+F9`, then copy the conversion result with `scripts\mvp\copy_convert_result_from_tree_handle.ps1`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\configure_kv_ethercat_device.ps1" `
  -ProjectName '<open-project-name>' `
  -DevicePath 'KEYENCE CORPORATION,Servo Drives,SV3' `
  -BatchAxisRegistration No `
  -OutDir (Join-Path $WorkRoot 'kv_network_config_runs')
```

Current same-run validation evidence for this script is:

- `C:\Users\Public\KVSkillPractice\ethercat_ethernet_kvstudio_script_20260529\entry_probe\ec_enter_config_20260530_121616\20260530_121647_771_configure_kv_ethercat_device.json`
- `C:\Users\Public\KVSkillPractice\ethercat_ethernet_kvstudio_script_20260529\entry_probe\ec_enter_copy_result_20260530_121811\result.json`
- Non-SV3 registered-ESI evidence: `C:\Users\Public\KVSkillPractice\ethercat_ethernet_kvstudio_script_20260529\entry_probe\beckhoff_enter_config_20260530_122537\20260530_122608_138_configure_kv_ethercat_device.json` and `C:\Users\Public\KVSkillPractice\ethercat_ethernet_kvstudio_script_20260529\entry_probe\beckhoff_enter_copy_result_20260530_122642\result.json`
- `network_config.json` dispatcher evidence: `C:\Users\Public\KVSkillPractice\ethercat_ethernet_kvstudio_script_20260529\entry_probe\network_config_beckhoff_run_20260530_124738\configure_kv_network_from_config_result.json` and `C:\Users\Public\KVSkillPractice\ethercat_ethernet_kvstudio_script_20260529\entry_probe\network_config_beckhoff_copy_result_20260530_124850\result.json`

The script is parameterized with `-DevicePath`. Stable evidence currently covers KEYENCE SV3 and a registered Beckhoff BK1120 EtherCAT Fieldbus coupler from the Beckhoff ESI sample. Do not claim automatic ESI registration support until a clean-project run registers the ESI file, adds the device, saves, and passes `Ctrl+F9` with copied conversion text.

Stable existing-project MNM export:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\mvp\export_mnm_project_copy_default_folder.ps1" `
  -ProjectPath '<project.kpr>' `
  -ExportDir '<out>\exported_mnm' `
  -OutDir '<out>\export_mnm_project_copy' `
  -WorkRoot '<out>\exported_mnm\_kv_export_workspace'
```

Export route: keep `WorkRoot` inside `ExportDir` by default, copy the source project directory to `WorkRoot`, remove `.mnm` files from the copy, open the copied `.kpr`, guarded `Alt+F`, `R`, `S`, confirm the export option dialog, accept the Browse Folder default selected project directory inside the file framework, then copy same-run `.mnm` files from the copied project directory to `ExportDir`. Success requires `export_mnm_project_copy_result.json.ok=true`, `actual_kv_export_dir` under `ExportDir`, and same-run `.mnm` files under `ExportDir`. Do not use `export_mnm_guarded.ps1` as the stable export entry for project replication.

## Project Replication Inventory

1:1 project replication is configuration-first, not MNM-only.

```yaml
source_assets_required:
  plc_units:
    evidence: [WsTreeEnv.xml, UnitSet_string_evidence, ui_probe_if_needed]
  ethercat:
    evidence: [WsTreeEnv.xml_nodes, registered_device_or_esi_origin, mapping_parameter_probe]
  ethernet_ip:
    evidence: [WsTreeEnv.xml_nodes, local_eds_xml, node_ip_variable_probe]
  motion_axis:
    evidence: [WsTreeEnv.xml_axis_names, axis_setting_probe]
  mnm:
    evidence: [fresh_export, official_fb_filter]
import_order:
  - create_clean_project_matching_cpu
  - configure_plc_units
  - configure_ethercat
  - configure_motion_axis
  - configure_ethernet_ip
  - let_kvstudio_generate_official_fb
  - import_filtered_user_mnm
  - ctrl_f9_and_compare_inventory
```

Use the read-only extractor before attempting a clone import:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\export_kv_project_inventory.ps1" `
  -ProjectPath '<source-project.kpr>' `
  -MnmDir '<top-level-raw-mnm-dir>' `
  -OutDir '<run>\source_assets'
```

`project_inventory.json` is a checkpoint. If `clone_readiness.ready_for_full_1_to_1_import=false`, do not start a full clone import. Open missing categories as small UI breakthrough tasks. Known missing categories include detailed axis settings, EtherCAT mapping/parameters, and EtherNet/IP IP/variable details.

Do not feed recursive filters with an MNM export directory that contains `_kv_export_workspace`; use a top-level-only MNM directory or an orchestration wrapper that excludes the internal workspace.

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
- `KV_SCAFFOLD_NETWORK_CONFIG_MISSING`, `KV_SCAFFOLD_NETWORK_CONFIG_INVALID_JSON`, `KV_SCAFFOLD_NETWORK_CONFIG_LEAK`
- `KV_SCAFFOLD_MODULE_CATEGORY_UNSUPPORTED`, `KV_SCAFFOLD_MODULE_CATEGORY_MISMATCH`, `KV_SCAFFOLD_MODULE_CATEGORY_SUPPORT_INCOMPLETE`
- `KV_UIA_OPERATION_TIMEOUT`, `KV_CREATE_PROJECT_DIALOG_MISSING`
- `KV_SOURCE_SNAPSHOT_MANIFEST_MISSING`, `KV_SOURCE_SNAPSHOT_NOT_READY`, `KV_SOURCE_SNAPSHOT_STALE`, `KV_SOURCE_SNAPSHOT_MNM_EMPTY`, `KV_SOURCE_SNAPSHOT_VARIABLES_EMPTY`, `KV_UPDATE_ARCHITECTURE_FILE_MISSING`
- `KV_MNM_SAME_NAME_IMPORT_REQUIRES_PREDELETE`, `KV_MNM_INCOMING_DUPLICATE_MODULE_NAME`
- `KV_VARIABLE_DATA_TYPE_UNSUPPORTED`, `KV_VARIABLE_TSV_SCHEMA_INVALID`, `KV_VARIABLE_NAME_SOFT_DEVICE_CONFLICT`, `KV_VARIABLE_LOCAL_OWNER_MISSING`, `KV_VARIABLE_LOCAL_OWNER_MISMATCH`
- `KV_UI_GUARD_STATIC_VIOLATION`
- `KV_FOCUS_LOST`, `KV_FOCUS_LOST_TERMINAL`, `KV_MODAL_PRESENT`
- `KV_VARIABLE_PASTE_NOT_PERSISTED`

## References

- `references\ui-guard-contract.md`: read when changing or diagnosing guarded UI input.
- `references\mvp-runner-contract.md`: read when interpreting runner artifacts or result schema.
- `references\variable-editor.md`: read when changing variable TSV schema or diagnosing variable editor paste.
