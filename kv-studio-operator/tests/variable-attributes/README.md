# Variable write-capability tests

Offline regression for `scripts/kv_variable_definition_lib.ps1`
(`Get-KvVariableWriteCapabilityErrors`) and the `-FullGlobalAttributes` contract
used by `scripts/workflows/set_kv_variables.ps1`.

Run:

```bat
tests\variable-attributes\run.bat
```

## What it pins

- Baseline (no flag): a global row with `device` or `initial_value` is rejected
  with `KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED`.
- `-AllowGlobalAttributes` + `globals`: `device`, `initial_value` and `comment`
  are allowed; `retain`, `constant` and `group_name` still fail closed.
- A global row with both `device` and `initial_value` fails with
  `KV_VARIABLE_DEVICE_INITIAL_VALUE_CONFLICT` (KV STUDIO drops the initial value
  for a device-assigned variable).
- Local variables never receive the global attribute route.
- `-AllowDefaultInitialValues` keeps the new-project rule: `0` allowed, `5`
  rejected.

The live KV STUDIO persistence evidence for this capability (device, INT/BOOL
initial value, comment surviving editor close/reopen) is a separate manual run:
`C:\kvrun\varfull\out3\artifacts\variables\variable_persistence_validation.json`.
