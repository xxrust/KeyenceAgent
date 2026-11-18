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

## Labels and system comments

Prepare the complete label TSV and program sources before editing. Paste a
multirow TSV in one operation; do not loop over labels with one UI paste and
compilation per row. Prefer meaningful labels. Leave label comments empty when
they only repeat the name; add comments for units, limits, edge behaviour or
other information the name does not convey.

Never register aliases for devices with system comments, and never overwrite or
clear their built-in comments. CR and CM are protected as whole system areas in
label and device-comment write validation. Read-only snapshots may include them.
Additional devices identified as system-owned by the target CPU documentation
or project evidence must also remain untouched. A planning omission must be
resolved before input, not by trying a write in KV STUDIO.

For a complete Nano program, use `apply_kv_nano_program_plan.ps1`: the reviewed
contract names the full TSV, script sources, ladder sources and old-content
expectations. The flat executor fingerprints those inputs, then applies them,
compiles, reopens and compares the saved content. Documentation describes those
same sources and links the current verification evidence. A plan alone cannot
prove that KV STUDIO matches the documents.

## FB Boundary

Use an official FB directly when it provides the required behaviour. A user FB is
allowed only when the official library lacks the capability, the logic is
repeated or must move between machines, and the delivery records the reuse
evidence. A whole-machine unit may compose official FBs when that unit is reused
on at least two stations or machines and adds fixed parameter and mapping policy;
it must not reimplement the official FB's state machine.
