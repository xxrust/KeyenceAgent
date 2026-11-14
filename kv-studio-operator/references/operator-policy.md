# Operator Policy

This file holds the stable policy that applies to every operator workflow. Case
notes and live-debug observations belong in the neighbouring reference files.

## Execution Boundary

Agents select a `customer_callable` capability from `scripts/script_manifest.json`.
They call its workflow or the plan-step rerun wrapper. `runner_children` and
support libraries are implementation details; direct calls bypass the desktop
mutex, plan fingerprint, input binding, and step receipts and are therefore not
an accepted execution path.

## Evidence Boundary

Planning, a dry run, and a snapshot are separate from desktop acceptance. A
successful delivery requires a fresh same-run result, step receipts, and the
workflow's declared readback or compile evidence. A skipped check means that the
claim was not verified and must not make a delivery gate green.

## FB Boundary

Use an official FB directly when it provides the required behaviour. A user FB is
allowed only when the official library lacks the capability, the logic is
repeated or must move between machines, and the delivery records the reuse
evidence. A whole-machine unit may compose official FBs when that unit is reused
on at least two stations or machines and adds fixed parameter and mapping policy;
it must not reimplement the official FB's state machine.
