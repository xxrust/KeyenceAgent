# Scaffold variable-attribute contract tests

Offline regression for the chain that lets a scaffold declare and execute full
global variable attributes:

```
scaffold.model.json -> renderer -> scaffold.json variables.attributes
                    -> validator -> variable_write_verified_fields
                    -> new_kv_mvp_execution_plan -> set_variables -FullGlobalAttributes
```

Run:

```bat
tests\scaffold-variable-attributes\run.bat
```

No KV STUDIO window is opened. The test writes a minimal model with one device
row, one initial-value row and one comment row, then checks:

| Case | Expectation |
|---|---|
| `render_full` | renderer exits 0 |
| `manifest_attributes_full` | `variables.attributes == full` |
| `manifest_attribute_row_count` | 3 rows triggered the mode |
| `validator_accepts_full` | validation ok with the full mode declared |
| `validator_reports_full_fields` | `variable_write_verified_fields` includes device/initial_value/comment |
| `validator_legacy_fails_closed` | no declaration -> `KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED` |
| `validator_rejects_bogus_mode` | unknown value -> `KV_SCAFFOLD_VARIABLE_SCHEMA_INVALID` |
| `validator_rejects_device_initial_conflict` | both fields -> `KV_VARIABLE_DEVICE_INITIAL_VALUE_CONFLICT` |
| `plan_includes_full_attribute_switch` | every `set_variables` step carries `-FullGlobalAttributes` |

The live counterpart of this chain was run on 2026-10-24: the scaffold-produced
merged TSV (`R_Flag/R100`, `Init_Flag/TRUE`, `Note_Flag/comment`) was written to
a real project, closed/reopened, and read back with all three attributes intact
(`C:\kvrun\varfull\out5`).
