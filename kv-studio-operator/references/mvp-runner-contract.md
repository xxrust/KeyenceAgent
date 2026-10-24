# Scaffold Runner Contract

Read this file when diagnosing `run_kv_mvp_scaffold.ps1`, `run_kv_mvp_repair_existing_project.ps1`, interpreting result JSON, or extending the scaffold runner.

## Contents

- [Terms](#terms)
- [Agent Boundary](#agent-boundary)
- [Existing-Project MNM Import Plan](#existing-project-mnm-import-plan)
- [Scaffold Files](#scaffold-files)
- [MNM Module Type And Category](#mnm-module-type-and-category)
- [Runner Result](#runner-result)
- [Repeat Result](#repeat-result)

## Terms

- `SkillRoot`: the `kv-studio-operator` skill directory.
- `WorkRoot`: disposable working root from config, task input, or a system temp directory.
- `ScaffoldRoot`: one task's source files, created by `new_kv_mvp_scaffold.ps1`.
- `OutRoot`: parent directory for runner output.
- `RunRoot`: current run directory, currently `<OutRoot>\<ProjectName>`.
- `Same-run artifact`: a file written under the current `RunRoot` during the current runner invocation.
- `ExecutionPlan`: `workflow_tools/new_kv_mvp_execution_plan.ps1` 生成的步骤清单。
- `FlatExecutionRunner`: `workflow_tools/invoke_kv_flat_execution_plan.ps1`，执行 `ExecutionPlan.steps[]`、控制超时、收集失败、写出最终 result JSON。

Do not use artifacts from a previous `RunRoot` as proof for the current run.

## Workflow Structure

```yaml
run_kv_mvp_scaffold:
  - load_operator_config
  - generate_execution_plan:
      mode: new_project
  - invoke_flat_execution_runner

run_kv_mvp_repair_existing_project:
  - load_operator_config
  - generate_execution_plan:
      mode: repair_existing_project
  - invoke_flat_execution_runner

flat_execution_runner:
  - resolve_manifest_declared_step
  - run_step_with_timeout
  - collect_step_failure
  - verify_copied_compile_result
  - write_mvp_or_repair_result
```

`workflows/run_kv_mvp_scaffold.ps1` and `workflows/run_kv_mvp_repair_existing_project.ps1` stay as thin orchestration scripts. Shared step execution belongs to `workflow_tools/invoke_kv_flat_execution_plan.ps1`. KV STUDIO UI operations belong to `runner_children/*`.

## Agent Boundary

The agent participates in two phases only:

- Before KV STUDIO opens: create/edit scaffold files, run scaffold validation, and start the top-level runner.
- After the runner exits: read same-run artifacts and report pass/fail evidence.

The interval from first KV STUDIO launch through compile-result copy is script-owned. The agent must not inspect the live KV STUDIO UI, decide the next UI action, paste values, click/type, or continue a failed in-window state manually. If a runner step fails, repair scaffold/script inputs from artifacts and start a fresh runner command.

Before touching KV STUDIO, `run_kv_mvp_scaffold.ps1` and `run_kv_mvp_repair_existing_project.ps1` run `assert_kv_mvp_agent_boundary.ps1`. The gate writes:

```text
<RunRoot>\artifacts\agent_boundary\agent_boundary_contract.json
```

This artifact records the allowed agent phases, the script-owned phase, public entrypoints, and runner-owned scripts. `mvp_result.json.agent_boundary_contract_path` must point to this current-run file.

## Existing-Project MNM Import Plan

Existing-project repair has a hard pre-import gate:

```text
<RepairRunRoot>\artifacts\mnm_import_plan_gate\mnm_import_plan_gate.json
```

The gate reads the verified source snapshot MNM inventory and the incoming scaffold MNM list before KV STUDIO opens. If any incoming `module_name` already exists in the source snapshot, direct import is rejected with `KV_MNM_SAME_NAME_IMPORT_REQUIRES_PREDELETE` unless the runner was invoked with `-DeleteExistingModulesBeforeImport`. With that flag, the repair runner records the conflict and each affected import step must pre-delete the existing module before importing the replacement MNM. If the project fingerprint does not match the snapshot, `assert_kv_existing_project_snapshot.ps1` fails first and the current project must be exported again.

### Default `Main` replacement in a new project

KV STUDIO refuses to delete the last remaining program
("不能删除。项目必须登录 1 个以上的程序。"), so a delete-first replacement of the
fresh project's default `Main` cannot work. The runner now:

- finds scan modules by their numbered tree label (`Main [1]`), not only by an
  exact UIA name;
- fails fast with `KV_MNM_DELETE_LAST_PROGRAM_FORBIDDEN` when the target is the
  only program, before sending DELETE;
- proves delete focus as "ProjectTreeView owns focus AND the target item is
  selected" (a WinForms tree gives keyboard focus to the tree, not the item);
- confirms the delete dialog through its control id (`BM_CLICK` on `IDOK`),
  because the owner-drawn dialog does not expose InvokePattern and is not the
  foreground window;
- supports `-DeleteOnly` to remove one module and save without importing.

Verified replacement sequence (2026-10-24, `MainReplaceTest`):

1. import a staging program (`MainStage`) so the project has two programs;
2. import `Main` with `-DeleteExistingModuleBeforeImport` (delete is allowed now);
3. `-DeleteOnly -ExpectedModuleName MainStage`.

The saved tree then contains exactly `Main [1]`, and the conversion result dialog
shows `转换成功。` (0 errors, 4 steps).

The execution plan now performs the sequence automatically:
`stage_default_program` (generates `KV_Stage_Temp.mnm` and imports it after
`create_project`), then the normal imports (the Main import carries the
pre-delete flag), then `delete_staged_program` (`-DeleteOnly`). When the scaffold
does not declare `Main`, the plan instead adds `delete_default_program` so the
untouched default program does not remain. Plan metadata
`default_program_staging` records the stage/cleanup names and the generated MNM
path; `tests\scaffold-variable-attributes` asserts both steps and the file.

MVP plans must satisfy the flat executor preflight: the first two steps are
`assert_kv_mvp_ui_guard_usage` and `assert_kv_mvp_agent_boundary`, then
`validate_scaffold`. Steps that operate on a project created through Ctrl+N pass
`-CreatedProjectResultPath`, because that KVS process has no project path on its
command line; the creation evidence binds the exact process for the staging
import, module imports, cleanup delete, compile, and result collection.

## Scaffold Files

Required files:

Model-backed scaffolds are validated by re-rendering into an isolated validation
directory and comparing every MNM/variable/FB-argument artifact byte-for-byte,
plus project identity and ordered module entries. Instruction membership is not
an execution-order check. `task.acceptance[]` is preserved in generated TASK.md.
Empty, null, or omitted local variables render an explicit no-local-state marker.

A model may declare `variables.allowed_custom_data_types` for types that already
exist in the target project (user structures such as `strCylinderCtrl`, official
FB instance types such as `TON` or `MC_MoveAbsolute`). The renderer merges that
list with the model's own FB names, writes it into `scaffold.json`, and the
validator applies it to local variables and FB arguments. The validator exempts
device-bound globals and motion axis/group reference types (`_MC_AXIS_REF`,
`_MC_AXIS_GROUP_REF`) from the "referenced by the paired MNM" rule: those are
configuration objects, not code references.

### Structure (Data Type) Import

`new_kv_mvp_execution_plan.ps1 -StructurePlanPath <mutation plan>` adds an
`import_structures` step immediately after `create_project`. The plan uses the
`mutate_structure_definitions_guarded.ps1` schema: `structure_operations[]` with
`action=create`, `parent_path=["数据类型"]`, and `members[]`. Generate it from a
snapshot's `structure_definitions.json` in dependency order (types whose members
are scalars first, nested types after).

The runner retries an empty member paste once, probes the grid without writing a
failure artifact, and waits for the new tree item before opening it. Live
2026-10-24: the 26 user data types of the KVX sample imported and verified in one
flat plan run, followed by all 28 module imports and all 4 FB argument writes.

The baseline variable writer proves `name` and `data_type`. The opt-in
`-FullGlobalAttributes` route on `set_kv_variables.ps1` additionally writes and
reads back the global `device`, `initial_value` and `comment` columns (live
verification 2026-10-24: `DM9002` binding, INT `789`, BOOL `TRUE`, comment). A
global row that declares both `device` and `initial_value` is rejected with
`KV_VARIABLE_DEVICE_INITIAL_VALUE_CONFLICT`, because KV STUDIO does not preserve
an initial value for a device-assigned variable. `retain`, `constant` and
`group_name` remain unsupported and fail before UI input.

The scaffold carries the same contract in `scaffold.json`:

```json
"variables": { "schema": "per_mnm", "attributes": "full", "attribute_row_count": 3 }
```

`render_kv_mvp_scaffold_model.ps1` emits `attributes: full` when any executable
global model row has a non-empty `device`, `initial_value` or `comment`, and
`name_type` otherwise. The validator then permits those fields only for the
`full` mode (`variable_write_verified_fields` mirrors the mode), and
`new_kv_mvp_execution_plan.ps1` adds `-FullGlobalAttributes` to every
`set_variables` step. A scaffold without the declaration keeps the fail-closed
name/type behavior, and an unknown value fails with
`KV_SCAFFOLD_VARIABLE_SCHEMA_INVALID`. `tests\scaffold-variable-attributes\run.bat`
covers the render/validate/plan chain offline.

Explicit default initial values are permitted
only in a newly created project; repair/direct writes require an empty
initial_value unless the full-attribute route is enabled. Comments in the model
are written only through the full-attribute route; the name/type baseline leaves
them as source documentation.

Local names may be reused across modules. Isolation checks exclude names owned by
the selected module from other-module forbidden names; uniqueness is scoped to
the module, not to the project.

`modules[]` order controls the import schedule, but placement alone does not prove
the saved PLC scan execution order. After the project is saved, compare the saved
inventory with the intended schedule using
`scripts/workflow_tools/assert_kv_scan_order.ps1`:

- `-ExpectedInventory <source project_inventory.json> -ActualInventory <target project_inventory.json>`
  compares the relative order of the expected modules. Add `-RequireExactNumbers`
  to also require identical execution numbers.
- `-ScaffoldPath <scaffold.json> -ActualInventory <target project_inventory.json>`
  compares the declared `mnm_files[]` import order; only `module_type: 0` entries
  participate in the scan schedule, so function blocks are excluded.
- Unexpected modules fail by default; `-AllowExtraModules` records them as
  warnings while keeping the relative-order check hard.

The tool writes `scan_order_verification.json` and fails closed with
`KV_SCAN_ORDER_MODULE_MISSING`, `KV_SCAN_ORDER_MODULE_EXTRA`,
`KV_SCAN_ORDER_MISMATCH`, `KV_SCAN_ORDER_NUMBER_MISMATCH`, or
`KV_SCAN_ORDER_DUPLICATE_MODULE`. `tests\scan-order\run.bat` covers identical,
swapped, missing, extra, shifted-number, duplicate, and scaffold-order cases.

The new-project and repair execution plans append two non-UI steps after the
conversion-result copy: `export_project_inventory.ps1` reads the saved tree, then
`assert_kv_scan_order.ps1 -ScaffoldPath <scaffold.json> -AllowExtraModules`
compares the saved schedule. Extra modules are tolerated because a fresh
KV STUDIO project keeps its default `Main` until the replacement route is
verified; a missing module, a relative-order change, or a duplicate name still
fails the workflow. The plan exposes `project_inventory_path` and
`scan_order_result_path`.

Full reproduction still requires a variable/structure snapshot, library dependency
evidence, and the same-run conversion result. Universal Library FBs are generated
by the EtherCAT device configuration, not by a separate install step; use
`workflow_tools/assert_kv_library_dependencies.ps1` before importing user MNMs
that call them. See `references/library-dependencies.md` for the dependency
order, failure codes and the 2026-10-24 live evidence.

### Compile Result Contract

`copy_convert_result_from_tree_handle.ps1` writes the full conversion result to
`compile_result_copied.txt` and reports it in `result.json`. For NG results the
child `message` now carries the copied rows (the result file stays authoritative)
and `text_available=true`. Verified 2026-10-24: a module with an undefined tag
produced `转换结果 NG (错误数量:1 ...)` plus the `错误214 ... [UndefinedTag]` row,
and the flat workflow result surfaced `error_code=KV_COMPILE_RESULT_NG` and
`child_message=...` instead of a generic failure.

If the owner-drawn result rows are truly unreadable, the child reports
`text_available=false` and a message that names the failure modal and the compile
step screenshot/fail.txt, rather than an empty message.

### Step Timeouts

Steps whose children make synchronous UIA calls that cannot be cancelled carry an
explicit `timeout_seconds`, and the flat executor kills the process tree at that
budget: `copy_convert_result` 120 s, `compile_convert` 300 s, each
`import_mnm_*` 240 s, `set_variables_*` 600 s. In-child budgets (the 8 s result
lookup loop, 1 s module lookup) remain cooperative checks; they do not bound a
single blocked COM call. The step timeout is the hard outer bound.

The flat workflow creates `<RunRoot>/run.log` before its first child and passes
`KV_WORKFLOW_RUN_LOG` to children so guard actions and workflow stage results share
one JSONL audit file. Per-step stdout/stderr remain supporting evidence.

On any failed step (non-zero exit, timeout, or a hung child) the executor saves
`failure.png` into that step's `out_dir` if the child did not already, adds it to
the failure evidence, and writes its path as `failure_screenshot_path` in both the
failure summary and the final `mvp_result.json`; the failure message also ends with
`screenshot=<path>`. A failed run therefore always points at the exact screen state
to inspect without guessing that a capture exists.

- `scaffold.json`
- `CHECKLIST.md`
- `TASK.md`
- `VERSION.md`
- `modules/<module>/*.mnm` for new scaffolds; `mnm/*.mnm` remains legacy-compatible
- one `modules/<module>/global_variables.tsv` for each `scaffold.json.mnm_files[]` entry
- one `modules/<module>/local_variables.tsv` for each `scaffold.json.mnm_files[]` entry

Schema v2 stores variable files on the MNM entry:

```json
{
  "schema_version": 2,
  "variables": { "schema": "per_mnm" },
  "mnm_files": [
    {
      "path": "modules/Main_MVP/Main_MVP.mnm",
      "module_name": "Main_MVP",
      "module_type": 0,
      "variables": {
        "global_tsv": "modules/Main_MVP/global_variables.tsv",
        "local_tsv": "modules/Main_MVP/local_variables.tsv"
      }
    }
  ]
}
```

The runner does not consume top-level `variables.global_tsv` or `variables.local_tsv`. For each MNM entry, it imports that MNM, validates module placement, merges executable global rows from all entry-level `global_tsv` files into a current-run artifact, and imports each entry-level `local_tsv` into that entry's `module_name`.

Minimum TSV columns:

```text
scope	owner_program	name	data_type	device	initial_value	comment	evidence	status
```

Executable variable rows use `status` other than `display_name`.

Every executable global variable row must be referenced by its paired MNM file. The scaffold validator enforces this so the later KV STUDIO compile gate verifies global variable definitions. In the default fast path, local variables are applied by the workflow's guarded variable step and then proven by the compile gate. When close/reopen/copy evidence from the local-variable grid is required, run the manifest-resolved customer workflow with its `AuditVariablePersistence` option.

`global_tsv` may contain only the header when that MNM has no global variables. `local_tsv` must contain executable local rows whose `owner_program` equals the MNM entry's `module_name`.

## MNM Module Type And Category

The MNM file must contain:

```text
;MODULE_TYPE:0
```

Use `0` for ordinary program MNM. The `0` value does not by itself distinguish scan-executed and standby modules. Use `2` for user function-block definitions. `scaffold.json.mnm_files[].module_type` must match the MNM file.

Each MNM entry may also declare `category`:

```json
{
  "module_name": "SimpleLatchFb",
  "module_type": 2,
  "category": "function_block"
}
```

Supported categories:

- `standby`: standby module. The scaffold category drives the import-time `选择程序种类` dialog; the runner selects `后备模块` before confirming.

- `scan`: ordinary scan-executed module, expected under `每次扫描执行型模块`.
- `function_block`: function-block definition, expected under `功能块`; the variable validator allows this module name as an FB instance data type.

Known but gated categories:

- `interrupt`: concept and project-tree category are known, but same-run support is gated because Wiki evidence requires CPU system settings for fixed-cycle/user-interrupt factors and an interrupt-enable path in addition to MNM import.

The validator fails closed with `KV_SCAFFOLD_MODULE_CATEGORY_SUPPORT_INCOMPLETE` for `interrupt` until its MNM representation, CPU-system settings, interrupt-enable path, placement, and compile behavior are verified from same-run artifacts.

## Runner Result

Primary result:

```text
<RunRoot>\mvp_result.json
```

Minimum success fields:

- `ok` is `true`
- `current_step` reached completion
- `project_path` points to the created `.kpr`
- `compile_result_path` points to current-run copied conversion text
- `compile_result_contains_ok` is `true`
- `steps[]` contains zero exit codes
- `variable_sets[]` lists the per-MNM variable TSVs used by the current run
- `merged_global_variables_tsv` points to the current-run merged global TSV artifact
- `agent_boundary_contract_path` points to the current-run agent boundary contract

Required evidence directories:

- `<RunRoot>\artifacts\scaffold`
- `<RunRoot>\artifacts\agent_boundary`
- `<RunRoot>\artifacts\create_project`
- `<RunRoot>\artifacts\import_mnm_<n>`
- `<RunRoot>\artifacts\module_placement`
- `<RunRoot>\artifacts\set_variables`
- `<RunRoot>\artifacts\variables`
- `<RunRoot>\artifacts\compile_convert`
- `<RunRoot>\artifacts\copy_result`

Existing-project repair uses the same scaffold, variable, compile, and copy evidence directories, but writes:

```text
<RepairRunRoot>\repair_result.json
```

Success requires `repair_result.json.ok=true`, `compile_result_contains_ok=true`, the corrected MNM files listed under `mnm_files[]`, and the current-run copied conversion text under `artifacts\copy_result`.

For existing-project repair, success also requires `repair_result.json.mnm_import_plan_gate.ok=true`. If `mnm_import_plan_gate.delete_required=true`, the result must show `delete_existing_modules_before_import=true`; otherwise same-name replacement was not planned safely.

Failure action:

- Read `mvp_result.json.current_step`.
- Read `mvp_result.json.error_code`, `mvp_result.json.failure`, and that step's `result.json`, `*_result.json`, checkpoint, or `fail.txt`.
- Stop KV STUDIO operation after a gate failure and start a fresh workflow run after inputs are repaired.

## Repeat Result

Use the manifest `regression_harness` capability `run_kv_mvp_repeat` when the task requires repeatability.

Primary repeat result:

```text
<RepeatOutRoot>\repeat_result.json
```

Success requires:

- `ok` is `true`
- `consecutive_passes` is at least `3`
- the final three `attempts[]` entries have `pass=true`
- each passing attempt points to its own current-run `mvp_result.json`, copied compile result, and variable persistence validation

Any failed attempt resets the consecutive pass counter to `0`.
