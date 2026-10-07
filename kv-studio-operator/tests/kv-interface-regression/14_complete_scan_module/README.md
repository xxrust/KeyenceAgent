# 14_complete_scan_module

Create the complete ordinary scan module QA_ScanLatch in a disposable copy of the built-in KVX sample project through scripts/workflows/create_kv_complete_module.ps1.

## Inputs

fixtures/contract.json resolves its MNM, local declarations and Wiki evidence relative to its own directory. The requested tree parent is 每次扫描执行型模块. The body computes Permit = Enable AND NOT Reset and Active = Permit using native LD, ANB and OUT instructions. Enable, Reset, Permit and Active are four local BOOL variables. There are no globals, physical device bindings or non-default retained/initial values.

## Execution

Run run.ps1 or double-click run.bat. Use run.ps1 -PlanOnly for preparation without launching KV STUDIO. The shared harness copies the sample, runs the workflow's non-UI plan and gate, then opens the copy because open_project=true. Each actual run uses a new output directory. Do not run concurrently with another KV STUDIO workflow.

## Acceptance

A live pass requires test_result.json and workflow/workflow_result.json to report success for the same run. Verify exact parent/category and module name, imported program body, complete declarations after close/reopen, saved project, copied conversion result, successful step receipts and the unified run.log. A same-name module conflict must fail instead of replacing unknown content.

PlanOnly proves preparation only. A tree item, successful paste or conversion alone does not prove the complete requested module. Compile checks declaration consistency; the requested Boolean behavior is not a PLC simulation or hardware execution result.
