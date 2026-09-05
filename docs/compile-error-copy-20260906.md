# Compile error report extraction

Evidence root: `H:/kvOp/error_snapshot_fix_20260906`.

KV STUDIO's owner-drawn output tree exposes empty UIA names and empty native
tree text. Ctrl+C on the focused tree does not copy. Its context-menu Copy
command does export the complete report, including module, row, diagnostic
number, text and summary. The adapter locates the output tree under the target
HWND, opens its menu, invokes the unique visible Copy command in the same
process, verifies a changed clipboard sequence and an OK/NG report header.

`collector_ok2` copied a successful report including three warnings and capacity
statistics. `collector_ng` copied all five lines of the failing report, including
`Reusable[error 71]: no END instruction` (actual file contains Chinese).
`ng_pair_repeat` repeated the compile-trigger/collector chain: collector 2004 ms,
five complete lines, KV_COMPILE_RESULT_NG, error-detail test passed. Failure is
the expected result of this deliberately invalid regression fixture.

The trigger now permits a conversion modal only after proving same-process
ownership and exact success/failure text. It does not mark compilation successful;
the collector remains authoritative. Failure latching and stale-result rejection
are retained. Compile details and guarded actions share the workflow run.log.

This repairs report extraction; it does not make the invalid PLC program valid.
