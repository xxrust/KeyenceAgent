# Scan-order verification tests

Offline regression for `scripts/workflow_tools/assert_kv_scan_order.ps1`.

No KV STUDIO window and no project copy are required. The case generator writes
synthetic `project_inventory.json` files, so each case runs in well under a second.

## Run

```bat
tests\scan-order\run.bat
```

`run.bat` only wraps `run.ps1`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\scan-order\run.ps1
```

`run.ps1` prints one row per case and exits non-zero if any case fails. The work
directory defaults to `%TEMP%\kv-scan-order-<random>`; pass `-WorkRoot` to keep it.

## Cases

| Case | Expectation |
|---|---|
| `same` | identical schedule passes |
| `order_drift` | swapped modules fail with `KV_SCAN_ORDER_MISMATCH` |
| `missing` | absent module fails with `KV_SCAN_ORDER_MODULE_MISSING` |
| `extra` | unexpected module fails with `KV_SCAN_ORDER_MODULE_EXTRA` |
| `extra_allowed` | the same input passes with `-AllowExtraModules` |
| `shifted_relative_ok` | numbers shifted by +10 still pass on relative order |
| `shifted_exact_fail` | the same input fails with `-RequireExactNumbers` |
| `duplicate` | duplicate module name fails with `KV_SCAN_ORDER_DUPLICATE_MODULE` |
| `scaffold_ok` | scaffold import order matches the saved schedule |
| `scaffold_order_fail` | reversed scaffold order is rejected |
| `real_sample_self` | optional: real 24-module inventory compared with itself |

Every case also checks the `scan_order_verification.json` written under its work
directory, not just the process exit code.
