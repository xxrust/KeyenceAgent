# Universal Library dependency tests

Offline regression for `scripts/workflow_tools/assert_kv_library_dependencies.ps1`.

The synthetic tree mirrors the saved `WsTreeEnv.xml` shape:

```
功能块 > UniversalLibrary > Motor > Inovance_SV630N_V100 > MC_*:comment
```

| Case | Expectation |
|---|---|
| `present` | vendor + `MC_` prefix found, `ok=true` |
| `vendor_missing` | unknown vendor -> `KV_LIBRARY_VENDOR_MISSING` |
| `prefix_missing` | no FB with the prefix -> `KV_LIBRARY_FB_MISSING` |
| `tree_missing` | no `UniversalLibrary` node -> `KV_LIBRARY_TREE_MISSING` |
| `no_requirements` | no requirements, no library -> `ok=true` |
| `live_ultest` | optional: the live ULTest project after one SV630N node |
| `live_fresh_project` | optional: a fresh project without EtherCAT nodes |

Run:

```bat
tests\library-dependencies\run.bat
```

The live context is in `references/library-dependencies.md`: a fresh project has
no `功能块 > UniversalLibrary`; configuring `SV630_1Axis_03713` produces
`Motor > Inovance_SV630N_V100` with 8 `MC_*_INOVA_SV630N_V100` FBs.
