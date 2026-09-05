# Variable and FB snapshot research (not published)

Evidence: `H:/kvOp/error_snapshot_fix_20260906/sample_snapshot`.
Source was copied to `project` before opening. `copy_manifest.json` records all
original file hashes; no source project writes were requested.

Added internal SnapshotOnly branches to the variable and FB argument children.
They copy raw TSV columns instead of reducing declarations to name/type. No
customer snapshot workflow has been published. Results explicitly retain
`unfiltered_completeness_verified=false`.

Verified:

- Test project: three global rows, one Reusable local, two IN/OUT interface rows.
- Sample: 35 FB_Cylinder locals, with comments and full clipboard columns.
- Default global group: 43 rows. After selecting all USER groups: 145 rows.
  The System group remained excluded. `all_groups/global_variables_raw.tsv`
  preserves devices, initial-value/flag columns, all comment columns and groups.
- Empty name filter and All usage filter were set and read back.

Not complete:

- Global group selection is still research-only. UIA Invoke on the group button
  blocks until the modal is closed; subsequent UIA tree queries can block too.
  Native posted BM_CLICK to the verified OK button successfully closed it.
- The source FB context menu has Open(O), NOT the writer's hardcoded Z command.
  Open exposes `_tabFBMacroParam`; the native source pane does not expose the
  new/imported FB's `FuncBlockParamVariableControl/_grid` identities.
- Selecting that tab and using filter/Shift+Tab did not prove a copyable cell.
  Copy returned the sentinel. Do not treat that as an empty FB interface.
- A later variable-editor shortcut attempt entered a ladder inline edit box.
  The unique visible Cancel button was invoked; no overwrite was submitted.
  Further input on that route was stopped and user assistance requested.
- Batch local coverage, empty-table proof, complete interface coverage, reusable
  group selector, parsed field schema and fingerprint-bound final manifest remain.

The UIA coordinate helper no longer rescales physical coordinates by the screen
size; that was an invalid maximized-frame heuristic, but removing it did NOT fix
the missing-Z route. These are separate issues.

Do not advertise these internal SnapshotOnly branches as a complete snapshot API.
