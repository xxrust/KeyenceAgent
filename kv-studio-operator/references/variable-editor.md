# Variable Editor Notes

Use this reference when MNM import causes missing variables or when reproducing a reference program.

## Required Inventory

Build a variable inventory before editing MNM:

- Global variables and devices.
- Local variables per program.
- FB instances and their data types.
- Arrays, structures, timers, counters, and retained/device-backed variables.
- External device mappings that must match unit configuration.

## Reconstruction Order

## Structure Definition Extraction

For existing projects, run `scripts\workflows\export_kv_structure_definitions.ps1`
before rebuilding variables. The workflow opens each requested user data type and
copies the complete owner-drawn grid (`Ctrl+Shift+End`, `Ctrl+C`) as TSV. The
result `structure_definitions.json` preserves member order, `data_type` text
(including `ARRAY[...] OF` and `STRING[n]`), comments, and raw columns. A missing
or empty member/type row is a hard failure; no incomplete structure is accepted.

To change user types, use the manifest entry
`scripts\workflows\mutate_kv_structure_definitions.ps1` with a JSON plan. Folder
creation uses the selected `数据类型` tree item context command `F`; data-type
creation uses `R`, the name field is filled by guarded clipboard paste, and the
kind selector is changed with `Alt+P` followed by `Up` (structure) or `Down`
(tuple). Create operations are intentionally ordered: a nested custom type must
exist before the type that references it. `(System)` is excluded. Create and
update operations are reopened and copied back before the workflow reports
success; delete operations require a confirmation dialog and a tree absence
check.

Use `fill_empty` only when the caller already knows that an existing type has
no persisted members. It opens the type, pastes from the top-left cell, and
performs the same close/reopen copy-back verification without a redundant
pre-read.

When an existing type is opened, the workflow sends `Ctrl+Home` immediately
after `Enter` to reset the member grid to its top-left cell. Update then selects
all existing rows with `Ctrl+Shift+End`, deletes them through the confirmation
dialog (`Left`, `Enter`), resets to the top-left with `Ctrl+Shift+Home`, pastes
the replacement TSV, saves, and verifies the exact row count by close/reopen
copy-back. New-type confirmation already focuses the new grid at its top-left;
that path pastes directly without an extra reset.

The selected-row deletion dialog is a separate `#32770` modal whose default
button is Cancel. The guarded route treats `Shift+Delete`, `Left`, and `Enter`
as one continuous modal transition and must never foreground-recover the main
window between those keys, because doing so removes focus from the dialog.

Project-tree context commands use UI Automation to identify one enabled menu
item, then click that item's reported bounds. They do not send `F`, `R`, or `D`
and therefore remain independent of the active Chinese or English input method.

New-type creation uses only approved atomic actions. After confirming the name
dialog, the runner explicitly selects and opens the newly created tree item,
then pastes its members from the top-left cell. It does not introduce a custom
compound Enter/paste input route. Copy-back writes a unique clipboard sentinel first and
must observe KV STUDIO replace it. The trailing all-empty row that KV STUDIO
keeps for the next member is ignored when counting persisted members.

1. Register global groups and global variables.
2. Register FB instance variables before program statements that call them.
3. Register local variables for each program through the local-variable view.
4. Re-import or refresh MNM only after variable names and data types are stable.
5. Compile once to reveal missing names, fix all missing variables, then compile again for type and scope errors.

## Error Handling

- A missing variable after MNM import usually means the program body imported but the variable table did not.
- A type mismatch usually means the variable exists in the wrong scope or has an incorrect data type.
- A missing FB type usually means the official FB was not imported or the project already has a conflicting FB name.
- Do not solve missing variables by deleting logic unless the reference logic analysis proves the logic is unnecessary.

## FB Argument Read/Write Focus

The published `workflows/set_kv_fb_arguments.ps1 -SnapshotOnly` uses the same
child as writing. It returns a raw full-column TSV and `fb_snapshot_result.json`
under `artifacts/fb_arguments`; `fb_declaration_workflow_result.json` binds that
result to the current execution. Do not supply write inputs with SnapshotOnly.

- Reading and writing share `Focus-KvFbArgumentGrid`. Resolve the requested FB
  with one name query scoped to ProjectTreeView (under 1 second), select it and
  press Enter. Then Alt+L opens the last-used declaration table. Do not require
  the argument pane to exist before Alt+L, and do not use a context-menu Z route.
- Identify the current table from the focused control's ancestry (at most five
  parent steps). Argument owners are `_tabFBMacroParam` or
  `FuncBlockParamVariableControl`; local owners are `_tabLocal` or
  `KvVariableLocalControl`. The focus control ID `_grid` alone cannot distinguish
  these tables.
- From the local table, Ctrl+Tab once reaches the argument grid. From the
  argument filter, Ctrl+Tab twice goes through locals and returns to the argument
  grid at its top-left. If Alt+L already leaves the argument grid focused, no
  tab switch is needed. Verify each expected table transition; never send a
  fixed number of Ctrl+Tab keys regardless of state.
- Before Ctrl+A and Ctrl+C, prove foreground, focused grid identity, and ancestry
  under the argument surface. Require a changed clipboard sequence and valid
  argument rows. Never infer success from the presence of the pane alone.
- Stop on an unknown table, unexpected transition, or focus failure. The runner
  does not retry alternative focus routes. Explicit recovery can close the
  known active FB with Ctrl+F4 (VK_F4 = 0x73) and reopen it; a save/modal prompt
  requires stopping, not accepting the prompt automatically.
- Writes retain the established one-row TSV paste followed by Down. Verify the
  argument-grid owner before paste, copy back names/directions/types, then save.
  Snapshot counts exclude all-empty insertion rows; an empty table has zero
  arguments. Snapshot success alone does not prove any arguments were written.
- Snapshot success does not establish unfiltered completeness, structure-member
  definitions, variable persistence, or full project replication.

`tests/test_fb_snapshot_live.ps1` verifies exact-reference copies from both
remembered tables, rejection of argument-copy input while locals are active,
and exact copying after closing and reopening the FB. It writes one JSONL
`run.log`, requires every atomic action below 10 seconds and every module lookup
below 1 second. This exercises explicit close/reopen, not automatic recovery.
