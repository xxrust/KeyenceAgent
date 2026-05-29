---
name: route-governance
description: Govern route selection, route correction, and reflection for long-running or fragile tasks. Use when a user specifies an operation route, when Codex considers switching between keyboard shortcuts, UIA, mouse clicks, scripts, APIs, recovery actions, or fallbacks, when the same failure repeats, or when task execution needs a persistent route document with status, evidence, and anti-thrashing checks.
---

# Route Governance

Use this skill before continuing any fragile task where the route itself is part of correctness. The goal is to prevent route drift: claiming to follow one workflow while silently switching to another.

## Core Rule

Maintain a route state file for the task. Do not rely on chat memory.

Default route file:

```text
<task-root>/route-state.json
```

Use `scripts/route_guard.py` to initialize, record attempts, request route switches, record reflections, and audit the route state.

## Non-Negotiable Rules

1. Keep exactly one active route.
2. Before executing, define the route's preconditions, action surface, observation surface, and failure boundary.
3. Treat a user-specified route as locked unless the user says otherwise.
4. Do not switch from a user-specified route unless it is blocked, it failed with evidence under verified preconditions, or the user approves the switch.
5. A route is `blocked` when preconditions are false. A route is `failed` only after preconditions are true and expected observations do not appear.
6. Every attempted action must belong to the active route's allowed action surface.
7. Verification observes; fallback changes the action surface. Do not call a fallback a verification step.
8. After two similar failures, record a reflection before continuing.
9. After two route changes in one task, stop and ask the user unless the route file explicitly allows automatic fallback.
10. If a route would create a known hazardous state, prevent the state instead of creating it and recovering from it.
11. Classify every event as `probe`, `execute`, `recover`, `verify`, `route_change`, or `reflect`.
12. A `probe` must not modify the target state. If observation requires a click, import, save, close, restart, file write, compile, or other state change, record it as `execute`, `recover`, or `verify`.
13. Recovery actions are route events. Closing software, restarting, reopening a project, regenerating files, deleting caches, or resetting state requires a recovery hypothesis and post-recovery verification.
14. Do not continue after the third occurrence of the same error family without route review.
15. After context compaction or task resumption, read the route state before operating.

## Hard Prohibitions

- Do not operate on the target project before creating or loading the route state file.
- Do not switch execution channels without a recorded route change event.
- Do not describe a route change as a probe, cleanup, verification, or minor adjustment.
- Do not repeat a failed action unless the failed precondition has changed and the evidence is recorded.
- Do not use mouse clicks to complete a step in a keyboard, UIA, or script route unless mouse is listed in the active route's allowed action surface.
- Do not use direct file edits to bypass a UI route unless a route change is approved by evidence.
- Do not count an executed action as completion evidence.
- Do not perform recovery actions without a recovery hypothesis and post-recovery verification.

## Route Fields

Each route must define:

- `route_id`: stable identifier such as `kv_mnm_import_accelerator_v1`.
- `owner`: `user_specified`, `agent_selected`, or `fallback`.
- `commitment_level`: `locked`, `preferred`, or `exploratory`.
- `status`: `proposed`, `active`, `blocked`, `failed`, `suspended`, `superseded`, or `completed`.
- `preconditions`: facts that must be true before action.
- `action_surface.allowed`: permitted action types.
- `action_surface.forbidden`: disallowed action types.
- `observation_surface`: evidence that proves the action worked.
- `failure_boundary`: what counts as blocked, failed, environment failure, or user-decision-required.

Action surfaces are semantic categories, not tool names. Use names such as:

```text
keyboard_accelerator
keyboard_shortcut
uia_observation
uia_menu_click
win32_window_probe
mouse_click
coordinate_click
file_edit
process_control
recovery_action
```

Use fixed error families to prevent treating the same mechanism as a new bug:

```text
focus_missing
control_missing
timing_state
permission_lock
path_resolution
encoding_format
import_format
compile_diagnostic
verification_gap
recovery_churn
route_violation
```

## Standard Workflow

1. Initialize a route state:

```powershell
python <skill>\scripts\route_guard.py init --state <task-root>\route-state.json --task "..." --route-id "..." --owner user_specified --commitment locked --allowed keyboard_accelerator --allowed win32_window_probe --allowed uia_observation --forbidden uia_menu_click --forbidden coordinate_click
```

2. Record each attempt before or immediately after the action:

```powershell
python <skill>\scripts\route_guard.py attempt --state <task-root>\route-state.json --route-id "..." --event-type execute --surface keyboard_accelerator --action "Alt+F,R,R" --observation "standard file dialog appeared" --result success --state-change true
```

3. If failure repeats, record reflection:

```powershell
python <skill>\scripts\route_guard.py reflect --state <task-root>\route-state.json --summary "Failure was observation-path mismatch, not route failure." --classification observation_failure
```

4. Request route switch only through the script:

```powershell
python <skill>\scripts\route_guard.py switch --state <task-root>\route-state.json --to-route "..." --to-owner fallback --reason "..." --evidence "..." --approved-by user
```

5. Audit before continuing after any failure:

```powershell
python <skill>\scripts\route_guard.py audit --state <task-root>\route-state.json
```

An audit failure is a stop condition.

## Route Change Gate

A route change is allowed only when the route state records:

- current route failure evidence.
- suspected failure mechanism.
- implementation method change: the primary implementation method changes, such as keyboard shortcut to UIA, UIA to mouse, mouse to script/API, script runner to manual UI, or one automation channel to another.
- route identity change: which basic implementation method, action surface, or operation order is being replaced. Guard semantics, timeout, path length, checkpoint naming, focus recovery, and oracle strength are corrections inside the same route.
- prior route review: whether the proposed route or same mechanism has failed before, with evidence paths.
- new success evidence: what new fact, patch, preflight, or artifact makes the proposed route more likely to work than the failed historical route.
- exhausted attempts or blocker.
- proposed route.
- why the new route addresses the mechanism.
- risks created by the new route.
- verification plan.
- whether user confirmation is required.

If any field is missing, continue diagnosis inside the current route or stop.

Do not call a local harness fix a route change. If the basic implementation method stays the same, record a `reflect`, `verify`, or `execute` event inside the active route. Examples of same-route fixes:

- Shortening artifact paths.
- Raising a timeout after evidence shows a successful child step exceeded the parent budget.
- Adding a successor-window pattern to the same guarded UI action.
- Replacing a weak oracle with a stronger oracle while the runner route stays the same.
- Fixing focus checks, checkpoint naming, state-transition declarations, or validation evidence inside the same script runner.

Switching to a route that has failed before is allowed only when the switch record names the prior failure and the new evidence that removes or controls that failure mechanism. Without that evidence, the switch is route churn.

## Completion Gate

The task is complete only when:

- Declared completion criteria are all satisfied.
- Evidence is independent of the action that attempted the change.
- Last known error families are resolved or explicitly irrelevant.
- Verification artifacts are recorded in the route state.
- `route_guard.py audit` passes.

## Decision Rules

Stay on the active route when:

- The route is user-specified and its preconditions have not been disproven.
- The failure is caused by missing observation, slow tooling, or uncertain focus.
- A proposed alternative changes the action surface.

Mark the route `blocked` when:

- Required window, file, process, project, device, dialog, permission, or focus is absent.
- A modal or hazardous state prevents safe action.

Mark the route `failed` when:

- Preconditions are verified.
- The action was delivered through an allowed surface.
- The expected observation did not occur within the defined boundary.
- Evidence is recorded.

Switch routes only when:

- The current route is `blocked` or `failed`, and the state file records evidence; or
- The user approved the switch; or
- The active route explicitly allows automatic fallback.

## KV STUDIO Example

For a user-specified MNM import shortcut route:

- Allowed action surface: `keyboard_accelerator`, `win32_window_probe`, `uia_observation`, `file_dialog_valuepattern`.
- Forbidden action surface: `uia_menu_click`, `coordinate_click`, `editor_text_input`, `recovery_action` as a normal path.
- Primary action: `Alt+F,R,R`.
- Required observation: verified standard file-open dialog before setting a path.
- Failure boundary: if no verified file dialog appears, close KV STUDIO and mark route `blocked` or `failed`; do not switch to UIA menu clicking.

Read `references/kv-studio-route-example.md` when applying this skill to KV STUDIO.
