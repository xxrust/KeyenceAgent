# 15_complete_station_fb

Create the complete ordinary scan program or function block FB_QAStation in a disposable copy of the built-in KVX sample project through scripts/workflows/create_kv_complete_module.ps1.

## Inputs

fixtures/contract.json resolves its MNM, local declarations, FB arguments and Wiki evidence relative to its own directory. The exact existing tree parent is 功能块 > level2_工站, confirmed from the current sample inventory. The body computes Permit = Enable AND NOT Reset and Ready = Permit using native LD, ANB and OUT instructions. Enable and Reset are IN BOOL arguments, Ready is OUT BOOL, and Permit is a local BOOL. There are no globals, physical device bindings or non-default retained/initial values.

## Execution

Run run.ps1 or double-click run.bat. Use run.ps1 -PlanOnly for preparation without launching KV STUDIO. The shared harness copies the sample, runs the workflow's non-UI plan and gate, then opens the copy because open_project=true. Each actual run uses a new output directory. Do not run concurrently with another KV STUDIO workflow.

## Acceptance

A live pass requires test_result.json and workflow/workflow_result.json to report success for the same run. Verify exact parent/category and module name, imported program body, complete declarations after close/reopen, saved project, copied conversion result, successful step receipts and the unified run.log. A same-name module conflict must fail instead of replacing unknown content.

PlanOnly proves preparation only. A tree item, successful paste or conversion alone does not prove the complete requested module. Compile checks declaration consistency; the listed truth table is the requested behavior, not a PLC simulation result. The FB is a definition and this scenario does not create a caller instance.
