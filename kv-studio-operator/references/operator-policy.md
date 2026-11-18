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

For desktop acceptance, keep the same-run result, step receipts, and the
workflow's declared readback or compile evidence. Associate these with the
project version they cover. After Save As or subsequent edits, verify the final
copy and the applicability of prior evidence. PLC behavior and field
acceptance follow the programmer skill's project model and acceptance cases.

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

Use the programmer skill to assess target compatibility, equivalent behavior,
and reuse before planning changes to FBs or native instructions.
[FB refactoring](../../keyence-plc-programmer/references/fb-first-refactor.md)
