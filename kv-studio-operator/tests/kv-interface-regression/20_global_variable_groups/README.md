# 20 Global Variable Groups

This regression covers projects where the global variable editor contains more
than the `(Default)` group. The guarded atomic route opens the variable-group
selector, selects all groups, confirms with the documented keyboard sequence,
then copies the complete global grid through the clipboard.

The tested sequence is:

```text
Alt+G -> Enter -> Alt+A -> Tab -> Tab -> Tab -> Enter -> Ctrl+A -> Ctrl+C
```

The test uses a copied sample project and writes all evidence below its isolated
run directory. It does not modify the source project. The published
`set_kv_variables.ps1` workflow remains unchanged; this case exercises the new
all-groups route separately.

Run:

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\run.ps1
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -PlanOnly
```

The atomic child writes `global_variables_all_groups.tsv`, a JSON result, UI
checkpoints and the unified run log under the current workflow artifact
directory. The desktop state is preserved after the test so a visible dialog or
editor is never closed by cleanup code.
