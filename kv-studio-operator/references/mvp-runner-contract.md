# Scaffold Runner Contract

Read this file when diagnosing `run_kv_mvp_scaffold.ps1`, interpreting `mvp_result.json`, or extending the scaffold runner.

## Terms

- `SkillRoot`: the `kv-studio-operator` skill directory.
- `WorkRoot`: disposable working root chosen by the agent, normally under `C:\Users\Public\KVSkillPractice`.
- `ScaffoldRoot`: one task's source files, created by `new_kv_mvp_scaffold.ps1`.
- `OutRoot`: parent directory for runner output.
- `RunRoot`: current run directory, currently `<OutRoot>\<ProjectName>`.
- `Same-run artifact`: a file written under the current `RunRoot` during the current runner invocation.

Do not use artifacts from a previous `RunRoot` as proof for the current run.

## Agent Boundary

The agent participates in two phases only:

- Before KV STUDIO opens: create/edit scaffold files, run scaffold validation, and start the top-level runner.
- After the runner exits: read same-run artifacts and report pass/fail evidence.

The interval from first KV STUDIO launch through compile-result copy is script-owned. The agent must not inspect the live KV STUDIO UI, decide the next UI action, paste values, click/type, or continue a failed in-window state manually. If a runner step fails, repair scaffold/script inputs from artifacts and start a fresh runner command.

Before touching KV STUDIO, `run_kv_mvp_scaffold.ps1` runs `assert_kv_mvp_agent_boundary.ps1`. The gate writes:

```text
<RunRoot>\artifacts\agent_boundary\agent_boundary_contract.json
```

This artifact records the allowed agent phases, the script-owned phase, public entrypoints, and runner-owned scripts. `mvp_result.json.agent_boundary_contract_path` must point to this current-run file.

## Scaffold Files

Required files:

- `scaffold.json`
- `CHECKLIST.md`
- `TASK.md`
- `VERSION.md`
- `mnm/*.mnm`
- one `variables/<module>/global_variables.tsv` for each `scaffold.json.mnm_files[]` entry
- one `variables/<module>/local_variables.tsv` for each `scaffold.json.mnm_files[]` entry

Schema v2 stores variable files on the MNM entry:

```json
{
  "schema_version": 2,
  "variables": { "schema": "per_mnm" },
  "mnm_files": [
    {
      "path": "mnm/Main_MVP.mnm",
      "module_name": "Main_MVP",
      "module_type": 0,
      "variables": {
        "global_tsv": "variables/Main_MVP/global_variables.tsv",
        "local_tsv": "variables/Main_MVP/local_variables.tsv"
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

Every executable global variable row must be referenced by its paired MNM file. The scaffold validator enforces this so the later KV STUDIO compile gate verifies global variable definitions. Local variable definitions are verified by the variable script through guarded close/reopen/copy of the local-variable grid for the same module/program, because KV STUDIO does not persist local variable names as plaintext project-file names.

`global_tsv` may contain only the header when that MNM has no global variables. `local_tsv` must contain executable local rows whose `owner_program` equals the MNM entry's `module_name`.

## MNM Module Type

The MNM file must contain:

```text
;MODULE_TYPE:0
```

Use `0` for ordinary scan-executed modules. Use `2` only when the task explicitly needs a function block. `scaffold.json.mnm_files[].module_type` must match the MNM file.

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

Failure action:

- Read `mvp_result.json.current_step`.
- Read `mvp_result.json.error_code`, `mvp_result.json.failure`, and that step's `result.json`, `*_result.json`, checkpoint, or `fail.txt`.
- Do not continue KV STUDIO operation after a gate failure.

## Repeat Result

Use `scripts/run_kv_mvp_repeat.ps1` when the task requires repeatability.

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
