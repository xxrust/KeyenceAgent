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

Project-tree context commands use the unique enabled menu item's UI Automation
`InvokePattern`; they do not send `F`, `R`, or `D`. This keeps structure create,
update, and delete independent of the active Chinese or English input method.

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

## FB Argument Snapshot Focus

The internal `runner_children/set_fb_arguments_guarded.ps1 -SnapshotOnly`
returns a raw full-column TSV and `fb_snapshot_result.json`. It is not a new
customer-callable entrypoint; use the manifest for published workflows.

- Selecting an FB in the project tree does not prove it is the active editor.
  The snapshot runner selects the exact FB, activates it with Enter, and resolves
  the argument surface within the focused editor.
- Both `_tabFBMacroParam` and `FuncBlockParamVariableControl` are observed UIA
  representations. The latter exposes `_grid` and `_usageFilterComboBox`.
- The measured route is Alt+L to the argument filter, then Shift+Tab to its grid.
  Ctrl+Tab switched to the local-variable tab in the regression; it is not an
  alternative focus route. A scrollbar alone also matches the ladder editor.
- Before Ctrl+A and Ctrl+C, prove foreground, focused grid identity, and ancestry
  under the argument surface. Require a changed clipboard sequence and valid
  argument rows. Never infer success from the presence of the pane alone.
- On a proven focus failure, recovery may close the just-activated FB once with
  Ctrl+F4 (VK_F4 = 0x73, not 0x34), reopen it and retry. Stop on any save/modal
  prompt, unknown document ownership, or a second failure.
- Snapshot success does not establish unfiltered completeness, structure-member
  definitions, variable persistence, or full project replication.

`tests/test_fb_snapshot_live.ps1` in the repository verifies two exact-reference
copies, rejection of wrong focus before clipboard input, and a third exact copy
after closing and reopening the FB. It writes one JSONL `run.log` and checks
every recorded atomic action is below 10 seconds. The close/reopen test verifies
the recovery actions, not automatic detection of every possible stuck-editor state.
