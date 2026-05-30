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

- Checklist gate: every KV STUDIO operation must pass `scripts\assert_kv_operation_checklist.ps1`.
- Variable definition gate: every generated or edited variable TSV must pass `scripts\assert_kv_variable_definitions.ps1` or the equivalent shared validator before KV STUDIO opens.
- Existing-project source gate: before modifying an existing `.kpr`, `scripts\assert_kv_existing_project_snapshot.ps1` must prove that the current project fingerprint matches a ready source snapshot containing MNM files, variable manifests, inventory evidence, and an open architecture file.
- MNM import plan gate: before modifying an existing `.kpr`, `scripts\assert_kv_mnm_import_plan.ps1` compares incoming `scaffold.json.mnm_files[].module_name` values with the verified source snapshot MNM inventory. Direct import is forbidden when a same-name module already exists. If a conflict exists, the top-level runner must be invoked with `-DeleteExistingModulesBeforeImport`, and the child import step must pre-delete that module before importing its replacement. If the project fingerprint no longer matches the snapshot, export current MNM first and re-plan.
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
- `scripts\assert_kv_mnm_import_plan.ps1`
- `scripts\assert_kv_variable_definitions.ps1`
- `scripts\validate_kv_mvp_scaffold.ps1`
- `scripts\run_kv_mvp_scaffold.ps1`
- `scripts\run_kv_mvp_repair_existing_project.ps1`
- `scripts\run_kv_mvp_repeat.ps1`
- `scripts\configure_kv_network_from_config.ps1`

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

Runner-owned export probe:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SkillRoot\scripts\mvp\export_mnm_guarded.ps1" `
  -ProjectPath '<project.kpr>' `
  -ExportDir '<out>\exported_mnm' `
  -ChecklistPath '<CHECKLIST.md>' `
  -OutDir '<out>\export_mnm'
```

Export route: open the target project, guarded `Alt+F`, `R`, `S`, confirm the export option dialog, select the requested folder, then accept the folder dialog. Success requires same-run `.mnm` files under `ExportDir` and `export_mnm_result.json.ok=true`.

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
