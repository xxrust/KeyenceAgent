# Desktop Write Acceptance: 2026-11-13

Scenario `23_import_device_comments` ran in KV STUDIO against a disposable copy of
the built-in KVX sample. The route reads a CSV/TXT device comment table through
`文件(F) → 读取 CSV/TXT 格式的软元件注释(Q)`, saves the project and then re-exports
the table to diff it. No PLC runtime, download or hardware behavior was
exercised.

| Check | Result |
| --- | --- |
| Test harness | `ok=true`, scenario status `pass` |
| Workflow | `ok=true`, status `pass`, `code_sha256=5EFC506F671C8302B25BD48FB8C09191542B0B5FB84B2E5E07B6D60C4AF314E2` |
| Cold start | `open_project:false`; the workflow launched KVS itself (pid 3728) and the harness reported `stopped_owned_process` |
| Import | `rows_in_file=3`, `saved=true`, table SHA-256 `B1B8DEF2A49D2A486E61C825DD6ADAB540C23696C0752E4E42FB49F8E854A8DA` |
| Project title after import | `KV STUDIO - [编辑器: KV-X520] - [KVX样例程序_v100 *]` (dirty, therefore the read had an effect) |
| Comment bank | `*.cm1` present and non-empty; 205,820 bytes |
| Re-export diff | `required=3`, `verified=3`, `mismatch_count=0` |
| Step timings | import 256.1 s, re-export 10.2 s, verify 0.8 s (workflow total 270.7 s) |

The independent task-scale run of the same route reached the same conclusion on
the 台州检测机 KV-X310 project through the `.bat` entry: 1,584 entries imported,
`verified=1584`, `mismatch_count=0`, and all 12 exported program bodies byte
identical to the pre-change snapshot.

Machine-local run artifacts are under
`C:\kvrun\taizhou_20260805\s23\23_import_device_comments_20261113_092753_587_0ace2455`
(primary records: `test_result.json`, `process_lifecycle.json`,
`workflow/workflow_result.json`,
`workflow/artifacts/comments_import/device_comments_import_result.json`,
`workflow/artifacts/comments_verify/comment_import_verification.json`).
The task-scale run is under `C:\kvrun\taizhou_20260805\bat_live`.

The offline suite was re-run in the same round
(`C:\kvrun\taizhou_20260805\suite_after_s23b`): 18 suites, 186 cases, 0 failures.
The three live desktop suites were **not** re-run in this round.

## Limits

- Only the device comment bank (`.cm1`) is written and verified. Variable-table
  comment columns and device-bound variable names are a different mechanism and
  are not covered here.
- The scenario proves that the entries are stored and readable again; it does not
  prove how the comments render in the ladder editor.
- Two KV STUDIO behaviours are asserted indirectly rather than by a dedicated
  negative test: the DirectUI information box (text allow-list + Enter) and the
  invisible `InterpreterC` helper window (visibility filter). An unknown dialog
  fails the run by design.
