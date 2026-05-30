# KV STUDIO Operator

This skill operates KEYENCE KV STUDIO through script-owned Windows desktop automation.

## Stable Scope

- Create, validate, and run disposable KV STUDIO scaffolds.
- Import/export MNM mnemonic-list programs.
- Edit global/local variable tables through scaffold TSV files.
- Compile/convert with KV STUDIO `Ctrl+F9` and copy same-run conversion results.
- Configure verified EtherNet/IP and EtherCAT unit settings through project-tree unit configuration scripts.

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

## Verification Rule

Do not claim a route is stable unless a clean KV STUDIO run configures the project and a `Ctrl+F9` conversion result is copied from the same run.
