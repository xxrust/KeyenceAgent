# 18 ST Numeric FB

Status: actual desktop acceptance passed on the final frozen implementation.

Latest save-closure acceptance: `H:/kvOp/st_quadratic_benchmark_20260920/integration/save_closure_regression/18_st_numeric_fb_20260920_202850_537_0cc04dd7`.
First attempt passed in 148.378 seconds after adding final project-save evidence.
The export result confirms `project_saved=true` and an exact clean project title;
all previous body, declaration, placement and compiler checks also passed.

Earlier frozen run: `H:/kvOp/st_quadratic_benchmark_20260920/integration/final_regression/18_st_numeric_fb_20260920_200718_715_0c34120d`.
`test_result.json` and `workflow/workflow_result.json` are pass; six arguments,
two locals, saved group, native compilation and exact ST source were verified.
Workflow elapsed 133.823 seconds, first attempt on the final frozen version.
An earlier development attempt exceeded the 1-second module lookup gate; that
failure is preserved in the fitting benchmark. The lookup implementation was
repaired and validated without increasing the gate threshold.

Uses the ordinary sample_copy harness and a fresh KV-X520 sample copy. Creates
FB_QA_STStats in existing level2_工站 with six explicit IN/OUT/IN-OUT arguments,
REAL array input, LREAL gain/sum, REAL mean and two locals. Samples is never
written. The FB resets outputs when disabled and aggregates when enabled.

Run `run.ps1 -PlanOnly` for static validation; run
`run.ps1 -OutRoot <evidence-root>` for actual serial desktop validation.
Acceptance requires saved tree placement, argument readback after local-editor
save/reopen, exact names/directions/types/counts, native conversion success and
exact ST source comparison from fresh MNM export. The expected result is
artifacts/verify/st_module_result.json with ok=true, plus workflow_result.json.

This standalone FB regression does not prove a caller instance or PLC runtime.
The complete fitting benchmark separately exercises a declared, invoked FB.

Initial PlanOnly evidence (no UI):
`H:/kvOp/st_quadratic_benchmark_20260920/integration/st_plans_final/18_st_numeric_fb_20260920_194527_021_c1409eed`.
The complete plan negative test rejects removal of compile, verify or the
post-local argument snapshot, replacement of body/contract input, disabled
persistence and disabled compilation requirements. Exact copyback tests reject
wrong numeric precision, wrong array bounds, wrong direction and extra rows.
