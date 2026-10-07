# Create a Blank Project

Create a real blank `QA_BlankProject` for CPU `KV-X520` through the public
`scripts/workflows/create_kv_project.ps1` workflow. `project_mode=new_project`
and `open_project=false` mean the harness neither copies the sample nor opens
an existing project. The create runner owns startup and the new-project dialog.

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\run.ps1
```

The fixed input is `scenario.json`; no code or project fixture is required.
The saved target is `<run>/project/QA_BlankProject/QA_BlankProject.kpr`.
The harness runs the public planner and static gates before any UI execution.
`-PlanOnly` is preparation only and must not create a `.kpr` file.

Acceptance requires a fresh successful `workflow/workflow_result.json` and
`workflow/artifacts/create/create_project_result.json`, an actual saved project
at the exact target, the runner's saved-project CPU evidence
`cpu_model_actual=KV-X520`, and the runner's process ID/start time matched to
the same run's before/after process snapshots. An existing or reused process
identity is rejected. Successful cleanup only stops that newly created identity;
failures preserve the scene. `-KeepProjectOpen` retains a successful project.

Inspect `test_result.json`, `process_lifecycle.json`, `workflow/run.log`,
the create artifact directory and workflow step receipts. This scenario proves
blank project creation and CPU selection; it does not prove ST import, algorithm
correctness, compilation of task code, or PLC runtime behavior.

Final implementation passed a real desktop run on 2026-09-20. See the
[repair report and evidence](../CREATE_ROUTE_REPAIR_20260920.md), including
independent agent verification and the Save As compatibility regression.
