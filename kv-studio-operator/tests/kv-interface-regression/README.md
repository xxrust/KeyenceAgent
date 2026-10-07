# KV STUDIO Interface Regression

Latest actual desktop evidence: [2026-09-20 acceptance report](ACCEPTANCE_20260920.md), with a [machine-readable evidence index](ACCEPTANCE_20260920.json).

Subsequent blank-creation repair and actual scenarios 16/08 evidence:
[creation repair report](CREATE_ROUTE_REPAIR_20260920.md).

This directory is a human- or agent-runnable smoke/regression harness for the published `kv-studio-operator` workflows. Each numbered child directory contains a `README.md` defining the operation, fixed input, execution route, acceptance boundary, and exact evidence locations. UI behavior is not duplicated here: `run-workflow-test.ps1` invokes the workflow from the skill, and the workflow invokes the shared flat executor and UI guard.

Whenever a numbered scenario is added or changed, update
[atomic-operation-coverage.html](atomic-operation-coverage.html) in the same change. The page is the
deduplicated audit index: add the scenario, map it to existing semantic operation IDs, add new IDs only
for genuinely new atomic behavior, and record the evidence level. Keep `static` or `indirect` until a
same-run live desktop acceptance exists; do not infer `live` from a plan or script presence.

Run one scenario against the real desktop application:

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\run-workflow-test.ps1 -ScenarioPath .\05_compile\scenario.json
```

For double-click use, open the scenario directory and double-click `run.bat`. The root `run-all.bat` runs all enabled scenarios serially. BAT entry points pause after completion so a human can read the result. Use the PowerShell entry points for unattended execution; not every scenario BAT supports `-NoPause`.

Run all enabled scenarios serially:

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\run-all.ps1
```

Before opening KV STUDIO, the shared harness prepares an isolated run directory, invokes the public workflow with `-PlanOnly`, checks the generated plan and input fingerprints, and runs the UI-guard and agent-boundary gates. Scenarios 01-15 and 17-18 use the default `sample_copy` mode; scenario 16 uses `new_project` and neither copies nor pre-opens a sample. A failure at any of these stages prevents project launch. Inputs are checked again before execution. `-PlanOnly` completes only this preparation stage and never proves desktop behavior.

Outputs are written below `runs\` by default, or under `-OutRoot`. Each run retains its copied project, planning output and gates, workflow output, result/receipt/log files, `process_lifecycle.json`, and `test_result.json`. A live pass requires zero workflow exit, a fresh same-run result containing boolean `ok=true`, and a result that is not `planned`. The scenario's semantic acceptance checks must also hold.

Run real desktop scenarios serially. The harness refuses an already-open conflicting sample project and uses the shared desktop mutex for startup; the workflow also owns the mutex while executing. The executable path comes from the installed skill configuration (`kvs_exe`). Do not start a second scenario while a workflow or unresolved failure occupies the desktop.

On failure the harness preserves the process, project and evidence for inspection. Do not dismiss ASSERT dialogs, continue UI input, or restart the failed workflow automatically. Investigate the current run's error, bound PID/HWND, receipts and `run.log` first. On success, cleanup targets the process started by that test and newly created workflow processes whose exact project paths occur in that run's execution plans. PID and process start time must match; existing unrelated processes are preserved. `-KeepProjectOpen` skips cleanup. The default suite stops at the first failure. Avoid `-ContinueOnFailure` for live acceptance while a failed desktop remains unresolved; it is useful for collecting independent non-UI planning failures.

## Complete-Module Scenarios

| Scenario | Fixed task | Current acceptance evidence |
| --- | --- | --- |
| `14_complete_scan_module` | Create `QA_ScanLatch` under the scan category; locals Enable, Reset, Permit and Active; Permit = Enable AND NOT Reset; Active = Permit. | Final live pass: `H:/rfinal/14_complete_scan_module_20260920_023900_542_0e06e1b6`. |
| `15_complete_station_fb` | Create `FB_QAStation` under the existing `功能块 > level2_工站` group; Enable/Reset IN, Ready OUT, Permit local; same boolean logic. | One complete live pass: `H:/c15final/15_complete_station_fb_20260920_023115_540_9db8e403`. Exact group, 3 arguments, 1 local, both reopen checks, exported body equality and conversion with 0 errors were verified. |

Both invoke `create_kv_complete_module.ps1` with fixed contract, MNM, declaration TSV and Wiki evidence files. They require program-body export comparison, precise declaration readback, saved placement and same-run conversion. Grouped FB placement imports the MNM first, then moves the module to the exact tree parent, saves, and immediately verifies the saved path. The FB route additionally takes a fresh read-only argument snapshot after the saved local-variable reopen step. See each scenario README and `references/complete-module.md` for the narrow published BOOL scope. Independently generated scan and FB inputs also passed live acceptance in `H:/kvOp/_validation/compose_round2/validation/scan-live` and `fb-live`; the original inputs were not modified for execution.

Scenarios marked `enabled=false` are intentionally excluded from the default run when the corresponding workflow is pending validation or requires a project-specific destructive fixture. Scenario 20,
`20_global_variable_groups`, covers the guarded all-variable-groups selector and complete global-grid
clipboard snapshot; its README and the coverage page define the additional acceptance boundary.

Read the scenario's own `README.md` before running it. That file is the acceptance specification for the scenario; `scenario.json` is only the machine-readable dispatch configuration. A `planned` result from `-PlanOnly` is never a live KV STUDIO pass.

## Blank Project Creation

`16_create_project` creates `QA_BlankProject` with CPU `KV-X520` through the public
create workflow, using `new_project` and `open_project=false`. Acceptance checks
the saved target, actual CPU evidence and a new process identity against fresh
same-run before/after snapshots. The blank launch has no project command-line
argument, so cleanup uses only that validated create result identity. The shared
process stop helper rechecks PID and start time immediately before stopping it.
See [the scenario contract](16_create_project/README.md). `run-all.ps1` discovers
all enabled scenario files, including this one, without a separate scenario list.

`get_kv_capabilities.ps1` exposes matching `regression_scenarios` for each public
workflow, including README, fixture paths, command and explicit project mode.
This is maintained contract discovery, not permission to run scripts from old
output directories or to replace a user's task with a fixture solution.

## Expected Compile Failure

[19_compile_error](19_compile_error/README.md) compiles the user-provided broken
KV-X520 project from an isolated `fixture_copy`. It expects the workflow to
return exit code 1 and `KV_COMPILE_RESULT_NG`, while the test passes only after
same-run receipts, timestamps, project binding and all four errors plus four
warnings match the frozen diagnostic fixture. The original workflow remains
failed; `test_result.json` reports `expected_failure_verified=true`.

Missing or stale diagnostics, truncated text, a different error, startup failure,
timeout or an unexpected successful compilation fail the test. The supplied
project is fingerprinted and left unchanged. The enabled scenario is discovered
by `run-all.ps1` and the public compile capability alongside positive case 05.

## Numeric ST Scenarios

The following scenarios exercise the complete numeric ST composition on
KV-X520. Both passed actual desktop acceptance on the final frozen implementation;
each scenario README links its own live evidence. The complete ST workflow is
published. Initial PlanOnly results remain preparation evidence only.

| Scenario | Independent fixed input | Required verification |
| --- | --- | --- |
| [17_st_numeric_scan](17_st_numeric_scan/README.md) | Four-element REAL and LREAL arrays, bounded loop, mean and weighted sum. | Five exact locals, saved scan parent, native compile, exported ST line equality. |
| [18_st_numeric_fb](18_st_numeric_fb/README.md) | Gain-scaled array statistics FB under level2_工站. | Six IN/OUT/IN-OUT arguments, two locals, independent argument reopen, exact saved group, native compile and exported ST line equality. |

Both use `create_kv_st_module.ps1` and a strict contract with `source_path`
(`.st`), `body_path` (DEVICE:60 UTF16LE MNM), `locals_path`, explicit category
and full parent path, plus `arguments_path` for FB and Wiki `evidence_paths`.
Optional globals are append-only, must be new names, and are verified as an
expected subset of the existing project. Unsupported nonempty declaration
attributes are rejected before UI. Named custom FB types must already exist
under the project's FB category. Source syntax is accepted by actual native
compilation; the preflight does not pretend to implement a complete ST parser.

Non-UI regression helpers under `tests/` cover numeric contract failures
(`test_st_module_contract.ps1`), tampered complete plans
(`test_st_plan_contract.ps1`) and exact declaration readback
(`test_st_module_copyback.ps1`). These complement, not replace, actual 17/18
desktop runs. The standalone FB scenario does not prove caller invocation;
the fitting benchmark separately verifies an instantiated and invoked FB.
