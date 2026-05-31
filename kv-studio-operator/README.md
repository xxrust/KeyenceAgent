# KV STUDIO Operator

This skill operates KEYENCE KV STUDIO through script-owned Windows desktop automation.

## Stable Scope

- Create, validate, and run disposable KV STUDIO scaffolds.
- Import MNM mnemonic-list programs; treat guarded MNM export as probe-only until same-run `export_mnm_result.json.ok=true` evidence exists for the exact invocation context.
- Edit global/local variable tables through scaffold TSV files.
- Compile/convert with KV STUDIO `Ctrl+F9` and copy same-run conversion results.
- Configure verified EtherNet/IP and EtherCAT unit settings through project-tree unit configuration scripts.
- Configure verified PLC unit start addresses through the target unit's project-tree item.

## Network Configuration

Network/unit configuration belongs in:

```text
architecture/network_config.json
```

Do not put EtherCAT or EtherNet/IP setup payload in `TASK.md`, `VERSION.md`, MNM comments, or variable TSV files.

The scaffold validator requires `architecture/network_config.json` and rejects structured network keys such as `node_address`, `ip_address`, `device_path`, and `esi_path` outside that file with:

```text
KV_SCAFFOLD_NETWORK_CONFIG_LEAK
```

Use the dispatcher for an already open project:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\configure_kv_network_from_config.ps1" `
  -ProjectName "<open-project-name>" `
  -NetworkConfigPath "<scaffold>\architecture\network_config.json" `
  -OutDir "C:\Users\Public\KVSkillPractice\kv_network_config_runs"
```

## Verified Device Routes

EtherNet/IP:

- Route: `单元配置 -> [0] KV-X310 -> EtherNet/IP -> 手动设定`.
- Verified with SR-2000, node `8`, IP `192.168.0.18`.
- Variable dialog handling is part of the stable script route.
- EDS/XML member parsing is available through `scripts\get_kv_ethernet_ip_device_members.ps1`.

EtherCAT:

- Route: `单元配置 -> [0] KV-X310 -> EtherCAT -> 手动设定`.
- Verified SV3 operation is keyboard-based: expand `KEYENCE CORPORATION -> Servo Drives`, select `SV3`, then press `Enter`.
- Verified non-SV3 route covers already registered ESI devices, including Beckhoff BK1120 from the local Beckhoff sample.
- Automatic ESI registration is not stable. `esi_path` is reserved and rejected with `KV_ETHERCAT_ESI_REGISTRATION_UNSTABLE`.

## PLC Unit Start Addresses

Use `scripts\configure_kv_unit_start_addresses.ps1` for verified start-address edits on an already imported PLC unit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\configure_kv_unit_start_addresses.ps1" `
  -ProjectName "FB测试" `
  -ProjectPath "C:\Users\liangyuhang\Documents\FB测试\FB测试.kpr" `
  -UnitName "KV-SSC02" `
  -Slot 1 `
  -FirstDm 1000 `
  -FirstRelay 1000 `
  -MaxDurationSeconds 60 `
  -OutDir "C:\Users\Public\KVSkillPractice\kv_unit_address_runs"
```

Verified route:

- Select the exact project-tree unit item, for example `[1] KV-SSC02 ...`, then press `Enter`.
- The unit editor must open with `[1] KV-SSC02` selected.
- Edit `首 DM 编号` with the bare number `1000`; KV STUDIO stores it as `DM1000`.
- Edit `首继电器编号(按通道设定)` with the channel value. `R1000` is entered as `10`, following the UI rule `R30000 -> 300`.
- Click unit-editor `OK`, save, then read `WsTreeEnv.xml`.

Current validation evidence for `KV-SSC02` in `FB测试`:

- `C:\Users\Public\KVSkillPractice\kv_unit_address_runs\20260531_155121_360_configure_kv_unit_start_addresses.json`
- Result: `[1] KV-SSC02 R1000 DM1000` in `WsTreeEnv.xml`
- Elapsed time: `15.921s`
- `Ctrl+F9` conversion copied `转换结果 OK (错误数量:0 警告数量:0)`.

## User FB Export Filter

Project replication must not export/import official or library FBs as user source. KV STUDIO can auto-add official FBs when modules, EtherCAT, EtherNet/IP, or Universal Library devices are configured; many of those FBs are not editable.

MNM export status:

- `scripts\mvp\export_mnm_guarded.ps1` is `probe_only_until_success_artifact`.
- Direct-call success requires current-run `.mnm` files under `ExportDir` and `export_mnm_result.json.ok=true`.
- If export succeeds only inside a parent runner or wrapper, classify it as `wrapper_dependent` and record the parent runner plus upstream preconditions.
- Without positive export evidence, do not start project replication from exported MNM.

After a proven raw MNM export, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\filter_kv_mnm_user_sources.ps1" `
  -InputDir "<raw-mnm-dir>" `
  -OutputDir "<filtered-mnm-dir>" `
  -ProjectPath "<project.kpr>" `
  -OutDir "<filter-report-dir>"
```

The filter copies non-FB MNM files, excludes project-tree official/library FBs and known official patterns such as `MC_*`, `_MC_*`, `[MC]_*`, `ModbusTCPClient_*`, and `SocketTCP_*`, then keeps only FBs with no official/library evidence. The report file is `mnm_user_source_filter_result.json`.

## Verification Rule

Do not claim a route is stable unless a clean KV STUDIO run configures the project and a `Ctrl+F9` conversion result is copied from the same run.
