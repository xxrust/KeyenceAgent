# Blank Project Creation Repair

The creation blocker is fixed and verified against the real KV STUDIO desktop.
This repair proves project creation, not completion of the ST quadratic-fit benchmark.

## Confirmed Cause

Historical blank creation succeeded at
`H:/kvOp/system-reliability/create-api-live-r3/workflow_result.json`.
The failed quadratic baseline used the same public workflow and create runner.
Both used the Ctrl+N fallback. Historical guard evidence shows foreground recovery
to the main window after New Project opened; the later shared guard correctly
refused that recovery after input began. The caller's same-window postcondition
had not been adapted to this expected dialog transition.

| File | Historical success SHA256 | Failed baseline SHA256 |
| --- | --- | --- |
| create_kv_project.ps1 | A26D9A6BB4BBB818F573293294BF234D481478E76DEF000BBE05FBC4CEE7FBF6 | unchanged |
| create_project_local_guarded.ps1 | 47F43960D23E6AAA1A66205668134EE99E685D7D9CCF1BCECDC713004BE8A6C0 | unchanged |
| kv_ui_guard.ps1 | 0CAEAD1DB2021CDC20A17DF35FC25E44D09614C25A8F967E65F22432D7C34F7B | 4D036B1A8755AE3BFC5CCECD231DB1A15281A4BF23C99B6F58A814E0918F7EED |

This was a caller/guard contract and regression-assurance failure, not a missing
creation capability or an agent selecting an unsupported entry point. The shared
guard was not modified during this repair. The numbered 01-15 suite did not
exercise true blank creation; scenario 08 exercises Save As.

## Changes

- The create caller uses the registered modal-aware Ctrl+N action, then verifies
  the expected dialog, exact HWND, owning PID and controls. Every field write
  binds to that window and validates control type and enabled state. No post-input
  focus recovery is restored.
- Creation accepts only the exact requested saved project. CPU selection is read
  from the combo and independently checked in saved WsTreeEnv.xml. Results expose
  actual CPU and process ID/start time.
- An AST gate rejects literal Ctrl+N through the same-window SendKeys wrapper.
  It covers single-line, multiline and colon arguments; it does not prove arbitrary
  dynamic expressions or every possible dialog transition.
- Capability discovery returns maintained regression contracts and invocation
  inputs. Operator/programmer skills require consulting those contracts when
  selecting or diagnosing an existing capability, without substituting fixture
  code for a user's algorithm.
- Scenario 16 adds genuine blank creation. The harness supports new_project
  without sample copying or pre-opening. Fresh artifacts, exact path, CPU and
  new process identity are required; cleanup rechecks PID and start time.

## Actual Desktop Verification

| Check | Result and evidence |
| --- | --- |
| Final scenario 16 | PASS: [test_result.json](H:/kvOp/_validation/create_route_repair/final3/16_create_project_20260920_184615_794_896a1257/test_result.json). Exact QA_BlankProject, KV-X520, only new PID 1680 cleaned. |
| Independent cold agent | PASS on its first live attempt after reading only skill/discovery/maintained contract: [report](H:/kvOp/_validation/create_route_repair/cold_agent/REPORT.md). This initial test preceded final field-binding hardening. |
| Original benchmark target, final code | PASS on one live attempt: [workflow result](H:/kvOp/_validation/create_route_repair/benchmark_recovery/live/workflow_result.json). QuadraticSTBaseline saved at the requested path; saved XML confirms KV-X520. PID 10096 left open. |
| Scenario 08 compatibility | PASS: [test_result.json](H:/kvOp/_validation/create_route_repair/compatibility/08_save_as_20260920_184944_822_9410fe5e/test_result.json). Owned PID 4936 cleaned; existing processes preserved. |
| Independent final review | No remaining critical finding in reviewed scope: [review](H:/kvOp/_validation/create_route_repair/REVIEW.md). Window-binding finding closed after final live verification. |

Focused non-UI checks passed: transition gate (4 cases), exact-window field
binding, capability discovery (16 scenarios), new-project evidence/ownership
(14 cases), existing lifecycle (7 cases), successor cleanup (7 cases), skill
validation and diff whitespace checks. The entire 16-scenario suite was not
rerun for this repair; actual desktop coverage was scenarios 16 and 08 plus
the agent's direct public-workflow runs.

Development failures remain in `H:/kvOp/_validation/create_route_repair`:
`live01` exposed cross-process combo readback; `final` exposed the comment
control's Document type; `final2` exposed the initially disabled administrator
submit button. These were diagnosed and fixed before final3. The cold-agent
first-attempt result does not mean the repair itself needed no iterations.

The original benchmark's failed result and frozen source evidence are preserved.
ST import, target compilation and PLC/simulation behavior were not verified by
this repair. See the [post-repair benchmark addendum](H:/kvOp/st_quadratic_benchmark_20260920/CREATE_RECOVERY.md).
