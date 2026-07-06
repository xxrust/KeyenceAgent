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

## Scaffold Files

Required files:

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
