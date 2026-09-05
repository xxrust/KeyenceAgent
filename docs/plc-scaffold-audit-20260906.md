# PLC scaffold audit — KVX sample v100

## Scope and evidence

Source: installed `kv-studio-operator/references/KVX样例程序_v100`.
Original source was not edited. The published export workflow created a disposable
copy and freshly exported 64 MNM files at 2026-09-06 01:15 local time.
Evidence root: `H:/kvOp/plc_scaffold_audit_20260906`.
`source_snapshot/export_evidence/export_mnm_project_copy_result.json` records the
source/copy paths and export; `source_snapshot/filter` classifies 24 ordinary
programs, 4 user FBs, and 36 official/library FBs.

## Actual sample architecture

The saved scan schedule is: inputs (digital, high-speed counter, analog),
initialization, cylinder/vacuum/motion component calls, seven station programs,
machine status, alarms, HMI, outputs, five demonstration modules, version notes.
The four reusable FBs are Cylinder, Vacuum, Motion, McMode.
The data-type tree has 26 user structure/union names arranged into component,
station, and machine layers, plus unions; names alone are not member definitions.
Initialization MNM uses `_FirstScanOn`, per-station cylinder arrays, permission
flags, and conditional default parameter initialization. Replacing those arrays
with scalar placeholders would change the sample's semantics.

Inventory defects fixed: ASCII-only module matching dropped 22 of 24 programs;
type matching missed user structures; `SV630_1Axis_03713` produced 26 false axis
matches. The revised inventory is cross-checked against fresh MNM module names.
No axis-tree match is not proof that the project has no motion configuration.

## Gate regressions and fixes

`legacy_gate_tests2/result.json`: seven corrupted scaffolds were all accepted
(instruction reorder/extra instruction/type drift/model initial value drift/FB
direction drift/module schedule drift/module header drift).
`fixed_gate_tests/result.json`: baseline accepted and all seven corruptions rejected.

The validator now re-renders into an isolated directory and compares exact adapter
bytes and ordered module metadata. Renderer preserves task acceptance, handles
empty/null/omitted locals with an explicit marker, rejects invalid Windows module
paths, mixed ST/instruction inputs, and unsupported variable fields/type routes.
`capability_tests_closure/result.json` covers 20 positive/negative checks.

Cross-module local names are no longer automatically forbidden if they are also
declared in the selected module. Guard input and flat workflow stages now share
one run.log. Current variable write/readback scope is explicit: name and type.
Unsupported device/non-default initial values fail closed; default initial values
may be allowed only by a new-project workflow, not repair/direct writes.

## Real UI regressions and remaining gaps

`ui_regression/ScaffoldScopeAudit`: first MNM import failed because fresh KVS
already contains Main. `ui_regression2` failed deleting it; selection did not
prove keyboard focus. `ui_regression3` hit the existing click allowlist. A bounded
guard click in `ui_regression4` still did not prove tree-item keyboard focus.
Automatic new-project deletion was withdrawn. Same-name preflight now fails
before import input, and existing-project deletion lookup is HWND-scoped. This
default Main replacement route is NOT verified/fixed.

`ui_scope_regression/ScopeReuseRegression`: all three modules independently
persisted local `State` through close/reopen/copy. The FB arguments Enable/Done
were written, but the test fixture lacked END and conversion failed (error 71).
The collector found five owner-drawn result rows with empty UIA text, hiding the
actual conversion error behind a generic readback failure. Screenshot evidence:
`compile_failure_screen.png`. The exact failure dialog is now recognized using
Unicode code points, dismissed through the shared guard, and its successor
project HWND verified. This does not fix extraction of owner-drawn error rows:
readback records KV_COMPILE_RESULT_TEXT_UNAVAILABLE; when the failure modal was
observed, the primary code is KV_COMPILE_RESULT_NG and empty text remains in the
message. Observed failure is latched and cannot be overridden by later OK text.
Every invocation first invalidates old success, and caught failures overwrite
the result. Matching multiple visible projects is rejected before input.
Direct native tree text read also returned empty; that unsuccessful adapter was
removed instead of publishing it. Result lookup now has an 8-second budget,
HWND-scoped window searches, unified JSONL detail logs, and no clipboard mirror.
The 8-second lookup budget is not a hard bound on all synchronous UIA calls.

`ui_scope_fixed/ScopeReuseRegressionFixed/mvp_result.json`: corrected test FB
with END passed the complete new-project workflow and real conversion (13 steps,
11 instructions). All three module-local State declarations survived editor
close/reopen/copy. The FB reuse guard passed before this import. This is a scope
regression, not the sample reproduction. Unified run.log recorded 129 atomic
actions, maximum 2163 ms; compile was 5.765 s and result collection 1.848 s.
Each full variable persistence audit still took 60.890/64.273/64.260 s. Input
atomic timing therefore does not establish that the variable API is fast enough.
Independent review additionally tested stale-success replacement on failure.
PowerShell parse, UI guard static gate, 8 semantic cases, 20 capability checks,
and the sample inventory check passed. Python skill quick_validate was not run:
this machine's python/python3 commands resolve to unavailable Store launchers.

Full sample reconstruction is not complete. Missing: exported global/local
variables and FB interfaces, structure/union member definitions and creation,
official-library dependency installation, full variable attribute write/readback,
and saved scan-order verification. Existing compile success gates do not prove
these properties. No reduced-variable or renamed-sample workaround is accepted
as full reproduction. No PLC connection/download/run was performed.

The independent read-only audit required by the programming skill reviewed the
challenged gates and the first fixes; its findings drove default-value mode
separation, null-local tests, and HWND-scoped module lookup.
