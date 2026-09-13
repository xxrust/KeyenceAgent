# KV STUDIO Interface Regression

This directory is a human- or agent-runnable smoke/regression harness for the published `kv-studio-operator` workflows. Each child directory contains only a `scenario.json` and, where needed, fixed input fixtures. UI behavior is not duplicated here: `run-workflow-test.ps1` invokes the workflow from the skill, and the workflow invokes the shared flat executor and UI guard.

Run one scenario against the real desktop application:

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\run-workflow-test.ps1 -ScenarioPath .\05_compile\scenario.json
```

For double-click use, open the scenario directory and double-click `run.bat`. The root `run-all.bat` runs all enabled scenarios serially. Both BAT entry points pause after completion so a human can read the result. For unattended command-line use, pass `-NoPause`; additional arguments such as `-PlanOnly` are forwarded to the PowerShell runner.

Run all enabled scenarios serially:

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\run-all.ps1 -ContinueOnFailure
```

Outputs are written below `runs\`. Every run has an isolated copied project, `workflow_stdout.txt`, `workflow_stderr.txt`, the workflow's own result/receipt/log files, and `test_result.json`. A scenario is a pass only when the invoked workflow exits zero and its declared result file contains boolean `ok=true`. `-PlanOnly` checks dispatch and contracts but does not prove desktop behavior.

The harness refuses to attach to an already-open sample project window and never runs scenarios in parallel. Close KV STUDIO or use a different test session before running live tests. The executable path is read from the installed skill configuration (`kvs_exe`).

Scenarios marked `enabled=false` are intentionally excluded from the default run when the corresponding workflow is pending validation or requires a project-specific destructive fixture.
