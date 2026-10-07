# 17 ST Numeric Scan

Status: actual desktop acceptance passed on the final frozen implementation.

Final run: `H:/kvOp/st_quadratic_benchmark_20260920/integration/final_regression/17_st_numeric_scan_20260920_200457_763_35c7ae71`.
`test_result.json` and `workflow/workflow_result.json` are pass; source equality,
five saved/reopened declarations and native compilation were verified in that run.
Workflow elapsed 110.521 seconds. This is the first attempt on the final version,
after development validation and shared framework repairs documented separately.

Uses the ordinary sample_copy harness and a fresh KV-X520 sample copy. Creates
QA_STNumericScan under the scan category. Five locals cover REAL/LREAL arrays,
INT indexing, REAL mean and LREAL accumulation. Expected mathematical values
are 2.5 and 30, but this scenario does not claim runtime execution.

Run `run.ps1 -PlanOnly` for static complete-contract/plan validation. Run
`run.ps1 -OutRoot <evidence-root>` for actual serial desktop validation.
The maintained public workflow imports DEVICE:60 UTF16LE AREA_ST, writes and
reopens declarations, compiles, exports and compares the exact ST body.
Acceptance requires workflow_result.json ok=true and artifacts/verify/
st_module_result.json proving saved path, source and exact declarations.

Fixture source was independently written for this test. Use its input schema
as guidance; do not copy this example as the solution to a user's algorithm.

Initial PlanOnly evidence (no UI):
`H:/kvOp/st_quadratic_benchmark_20260920/integration/st_plans_final/17_st_numeric_scan_20260920_194522_180_cb494516`.
Related static checks: `tests/test_st_module_contract.ps1` and
`tests/test_st_module_copyback.ps1`; plan tampering is checked by
`tests/test_st_plan_contract.ps1 -PlanPath <execution_plan.json> -OutDir <out>`.
