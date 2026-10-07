# Desktop Acceptance: 2026-09-20

All 15 listed scenarios passed actual desktop acceptance. The final scenario 13 snapshot repeat completed successfully at 2026-09-19T18:47:33Z (machine-local 2026-09-20 02:47:33), with workflow exit code 0. The earlier full snapshot also passed at H:/r13v2b/13_project_text_snapshot_20260920_021040_507_524109ca.

These are actual, serial KV STUDIO executions, not PlanOnly results. The evidence combines the full existing-suite run with targeted reruns after shared fixes; it does not claim an uninterrupted first-attempt run of all 15 cases. Machine-readable locations are in [ACCEPTANCE_20260920.json](ACCEPTANCE_20260920.json).

## New Scenarios

- 14 creates QA_ScanLatch under 每次扫描执行型模块, with its MNM body and four BOOL locals: Enable, Reset, Permit, Active. Permit = Enable AND NOT Reset; Active = Permit.
- 15 creates FB_QAStation under 功能块 > level2_工站, with its MNM body, Enable/Reset IN and Ready OUT arguments, and Permit local. Ready = Enable AND NOT Reset through Permit. The actual sample group's initial letter is lowercase.
- Both verify the saved exact tree path, exported instruction sequence, exact declaration names/types/counts after editor reopen, and successful conversion. FB additionally verifies argument directions from a fresh read-only snapshot after saved local-variable reopen.

## Real Regression Evidence

| Scenario | Result evidence |
| --- | --- |
| `01_fb_arguments` | [test_result.json](/H:/r13v2/01_fb_arguments_20260920_020154_940_aa92f106/test_result.json) |
| `02_fb_program_body` | [test_result.json](/H:/r13v2/02_fb_program_body_20260920_020209_799_e7970a28/test_result.json) |
| `03_variables_snapshot` | [test_result.json](/H:/rfinal/03_variables_snapshot_20260920_023752_937_983d5b8d/test_result.json) |
| `04_structures_snapshot` | [test_result.json](/H:/r13v2/04_structures_snapshot_20260920_020245_088_e45d0e38/test_result.json) |
| `05_compile` | [test_result.json](/H:/rfinal/05_compile_20260920_023813_073_c9319535/test_result.json) |
| `06_expansion_units` | [test_result.json](/H:/r13v2/06_expansion_units_20260920_020352_473_c83f59a3/test_result.json) |
| `07_ethercat_nodes` | [test_result.json](/H:/r13v2/07_ethercat_nodes_20260920_020410_377_854c38ea/test_result.json) |
| `08_save_as` | [test_result.json](/H:/r13v2/08_save_as_20260920_020441_568_e37de16b/test_result.json) |
| `09_import_fb` | [test_result.json](/H:/r13v2/09_import_fb_20260920_020454_453_45a69713/test_result.json) |
| `10_export_mnm` | [test_result.json](/H:/rfinal/10_export_mnm_20260920_023831_852_5548373a/test_result.json) |
| `11_structure_mutation` | [test_result.json](/H:/r13v2b/11_structure_mutation_20260920_020730_986_34787a07/test_result.json) |
| `12_structure_targets` | [test_result.json](/H:/r13v2b/12_structure_targets_20260920_021027_581_81c5d2b2/test_result.json) |
| `13_project_text_snapshot` | [test_result.json](/H:/rfinal/13_project_text_snapshot_20260920_024041_728_6ace4c4e/test_result.json) |
| `14_complete_scan_module` | [test_result.json](/H:/rfinal/14_complete_scan_module_20260920_023900_542_0e06e1b6/test_result.json) |
| `15_complete_station_fb` | [test_result.json](/H:/c15final/15_complete_station_fb_20260920_023115_540_9db8e403/test_result.json) |

Each test_result.json points to its same-run workflow result and project. New scenarios additionally retain workflow/artifacts/verify/complete_module_result.json. Planning success alone is never desktop acceptance.

## Independent Agent Rounds

Round 1 assigned separate scan/FB preparation and gate review. Their findings drove contract documentation, declaration formats, capability discovery, and shared plan validation changes.

Round 2 used a cold agent reading the installed skills, without regression fixtures or other agents' artifacts. It independently generated QA_CellReady and FB_QACell. Both first PlanOnly submissions passed, then root executed each unchanged input set once, serially; both actual workflows passed. The agent independently reviewed saved path, exported body, reopened declarations and conversion evidence. Input hashes remained unchanged. [Detailed report](/H:/kvOp/_validation/compose_round2/REPORT.md).

The cold agent exposed missing full Wiki body retrieval when deployed Markdown paths were stale. The KB wrapper now supports --evidence and --chunk-id against the same cleaned database, retaining source anchors/checksums and disclosing missing local paths. The documented retrieval route passed the agent's post-fix recheck without direct database scripting. This does not claim broad search ranking improvements.

The three skills now define requirement preparation, source evidence, exact project-parent discovery, input contract, public workflow discovery, preflight, serial execution and same-run acceptance. Both complete-module and compile capabilities are published.

## Gate And Harness Changes

Content validation rejects wrong parents, existing names, missing declarations, writes to IN parameters, duplicate headers/symbols, unsupported fields and missing evidence before UI. Shared plan validation checks allowed atomics, parameter types, project/output binding, mandatory gates, declaration/compile/export/verification order and saved FB readback. Transitive input hashes prevent execution of changed inputs.

Independent negative suites cover these contracts, stale results, changed inputs, skipped gates/readback, relative/absolute paths, desktop drag guards and process cleanup ownership; their individual evidence paths are indexed in the JSON. Counts across overlapping suites are not treated as unique tests. The cold agent also submitted undeclared Permit and OUT Enable-to-IN challenges; both were rejected with ui_started=false.

The import startup path now binds the exact project command-line argument and PID rather than launching another Kvs while its first window is still initializing. Grouped FB import is followed by a guarded move to the exact parent and immediate saved-tree verification. Variable saves retain the editor's bound foreground; compilation selects the verified owned conversion-menu command.

An early scenario 11 attempt failed because scenario 10 left an export-copy process. The harness now cleans successful runs' precisely identified new workflow project processes, checking project path, PID and start time while preserving unrelated processes. The failed result remains indexed; 11/12/13 subsequently passed and final 10 verified successor cleanup. Other investigated failures and intermediate agent reports remain available; later live evidence supersedes their historical pending statuses.

## Limits

The new complete-module contract supports the documented BOOL ladder subset and existing parents only. It is not general ST, numeric-type, device-address or arbitrary-instruction support. The FB scenario creates a definition, not a caller instance.

Evidence presence and hashing do not prove source interpretation or program behavior. Current declaration checks do not prove that every table filter was cleared or that optional initial/device/retain/constant/comment properties persisted. No PLC hardware execution or simulation was performed. Static gate, desktop persistence/conversion and PLC runtime behavior remain distinct acceptance layers.
