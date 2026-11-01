# Desktop Write Acceptance: 2026-11-01

Scenario `14_complete_scan_module` ran in KV STUDIO against a disposable copy
of the built-in KVX sample. The workflow, final harness result and compile gate
all passed. No PLC runtime or hardware behavior was exercised.

| Check | Result |
| --- | --- |
| Test harness | `ok=true`, scenario status `pass` |
| Workflow | `ok=true`, status `pass`, run ID `32d14370fead45979ab64c62d023e593` |
| Saved module | Exact requested tree path and module contract verified |
| Program body | Exported body matched the requested MNM (`body_equal=true`) |
| Local declarations | 4 BOOL locals; saved close/reopen readback passed |
| Compile | `转换成功。`; compile, copied-result, export and verify steps exited 0 |
| Owned process cleanup | Harness reported `stopped_owned_process` |

The copied conversion result SHA-256 is
`F5275268F020345C356E567D94B742C80034AE5448DBC08917B3D7C59340C605`.
The workflow code fingerprint is
`C116B964770AA8F9B2604C5C6CCA6542F98D17F3523F324CF757F267A507F270`.

Machine-local run artifacts are under
`C:\Users\Administrator\AppData\Local\Temp\kv-live-write-acceptance\14_complete_scan_module_20261101_014308_430_d00cf5a3`.
The primary records are `test_result.json`, `workflow/workflow_result.json`,
`workflow/artifacts/verify/complete_module_result.json`, and
`workflow/artifacts/compile_result/compile_result_copied.txt`.

The scenario verifies the requested saved path, body, local names/types/count
after editor reopen and compilation. It does not verify unfiltered declaration
table completeness or optional initial/device/retain/constant/comment
persistence, and compilation does not prove PLC runtime behavior.
