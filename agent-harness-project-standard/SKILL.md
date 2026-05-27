---
name: agent-harness-project-standard
description: Build or revise agent-driven software, automation, UI-control, workflow, PLC, data, or integration projects as harnesses. Use when Codex is asked to create an agent-operated project, scaffold a reusable workflow, automate a fragile external tool, make an MVP repeatable, add validation gates, prevent wrong causal attribution, require artifacts/checklists, or turn a successful manual route into a durable agent-executable process.
---

# Agent Harness Project Standard

## Core Rule

Treat an agent-driven project as a harness first and an implementation second.

A harness is the executable shell around the target work. It defines the input specimen, preflight gates, deterministic execution path, artifacts, pass/fail oracle, failure taxonomy, and repeatability standard. The target feature is not complete until the harness can prove it in a fresh run.

## Required Workflow

1. Define the specimen before running the workflow.
   - Store task intent, inputs, environment assumptions, project version, and acceptance criteria as files.
   - Prefer a scaffold command that creates the file set in one step.
   - Avoid relying on chat history, UI state, clipboard state, or a previous run as the source of truth.

2. Add preflight gates before irreversible or fragile operations.
   - Check required files, credentials, checklist, tool paths, target project identity, and disposable/safe output paths.
   - Fail before opening or operating external tools if the gate is not satisfied.
   - Emit a short, machine-readable failure record with a stable error code and remediation.

3. Run through a deterministic orchestrator.
   - Use a top-level runner script for the full flow.
   - Make each step explicit: create, import, configure, execute, verify, collect result.
   - Capture exit code, elapsed time, current step, and artifact paths for every step.
   - After invoking a child process or guard, check its exit code immediately before continuing.

4. Capture same-run artifacts.
   - Write logs, screenshots when UI is involved, copied text, parsed results, generated files, and validation JSON into a run-specific output directory.
   - Copy the input scaffold/specimen into the artifact directory so later diagnosis sees exactly what was executed.
   - Use a unique run id or isolated output root when repeatability matters.

5. Define hard oracles.
   - Replace "looks done" with concrete checks: file exists, schema valid, names persisted, module placed correctly, compile result OK, API response matches, UI element state changed, exported roundtrip matches.
   - Read evidence from the current run only.
   - Treat stale output as invalid unless the runner proves it was produced in the current run.

6. Classify failures by mechanism.
   - Do not attribute failure from an old step to a later change.
   - Record where the failure occurred, what was attempted, what evidence was observed, and which condition failed.
   - Use stable error codes for common failures.

7. Prove repeatability.
   - For MVP acceptance, require a repeat runner when the user asks for repeated success.
   - If the rule is "3 consecutive passes, one failure resets to 0", implement that as a counter in the harness, not as a verbal promise.
   - For independent-agent validation, pass only the skill, scaffold, and task artifact needed for the other agent to execute the route.

## Minimum Harness Contract

Every agent-driven project should contain these parts unless the task is trivial and one-shot:

| Component | Required Artifact | Acceptance Check |
| --- | --- | --- |
| Specimen | `scaffold.json`, task file, config file, or equivalent | Runner can resolve all inputs without reading chat history |
| Version | `VERSION.md` or manifest version field | Changes to task logic, schema, or acceptance are recorded |
| Checklist | `CHECKLIST.md` or structured preflight file | Runner blocks when required checklist is missing or invalid |
| Orchestrator | `run_*.ps1`, `run_*.py`, `make`, or equivalent | Full flow can be started by one command |
| Step artifacts | `artifacts/<step>/...` | Each fragile step leaves evidence |
| Result | `result.json`, `mvp_result.json`, or equivalent | Contains ok/status/current_step/error_code/evidence paths |
| Oracle | Validation script or runner checks | Pass/fail is computed, not inferred by narration |
| Repeatability | Repeat runner or CI job | Consecutive-pass rule is enforced mechanically |

## UI And External Tool Operations

When the project controls a GUI, PLC IDE, browser, desktop app, CLI service, hardware proxy, or remote VM:

- Put a gate before launching or manipulating the tool.
- Verify the target window/project/session identity before sending keys or clicks.
- Prefer API/UIAutomation/accessibility selectors over coordinates.
- If keyboard or mouse is required, document the exact key sequence or click target and capture evidence after the action.
- Keep route changes explicit. If a selected route fails, record the failed route and reason before switching.
- Do not close, reset, delete, or overwrite state unless the harness verifies the target path/session is disposable or explicitly approved.

## Failure Feedback Standard

Agent-readable failure feedback should follow this shape:

```json
{
  "ok": false,
  "error_code": "STABLE_ERROR_CODE",
  "operation": "short operation name",
  "current_step": "step_name",
  "message": "direct cause observed in this run",
  "evidence": ["path/to/log.txt", "path/to/screenshot.png"],
  "remediation": ["concrete next action"]
}
```

Use fixed exit codes for gate failures when practical. For child scripts, the parent runner must propagate or summarize the child failure instead of continuing.

## Anti-Patterns To Reject

- Running the real external tool before creating the checklist or scaffold.
- Treating a pasted value, visible UI state, or compile result as successful without same-run verification.
- Using a previous compile/build/test error to explain the result of a later changed workflow.
- Adding retries, sleeps, fallbacks, or route changes before identifying the failing condition.
- Writing a feature-only MVP that cannot be recreated by a fresh agent from files.
- Reporting "manual route works" while no runner, artifacts, or pass/fail oracle exists.

## Completion Standard

Declare the project complete only when:

- A fresh checkout or clean workspace can create or locate the scaffold.
- One command runs the harness end to end.
- The harness blocks unsafe execution when preflight is missing.
- The harness writes same-run evidence and a machine-readable result.
- The result includes concrete pass/fail or a precise failure code.
- Required consecutive success rules are enforced by script.
