# Universal Library 依赖

样例的 36 个官方/库 FB 不需要单独的"库导入"步骤。它们是 KV STUDIO 的
**Universal Library** 设备 FB，由 EtherCAT 设备配置生成。

## 结论（2026-10-24 实测）

| 工程状态 | `功能块 > UniversalLibrary` |
|---|---|
| 新建 KV-X520 工程，无 EtherCAT 节点 | **不存在**（`ScopeReuseRegressionFixed` 同样没有） |
| 同一工程配置 `SV630_1Axis_03713` 节点后 | 存在 `Motor > Inovance_SV630N_V100`，含 8 个 `MC_*_INOVA_SV630N_V100` FB |
| 含 SV630N + YAKO 节点的工程（`QA_BlankProject`） | `Inovance_SV630N_V100` 与 `YAKO_MS_MINI_E_V100` 两套 FB 都在 |

实测命令与证据：

```powershell
# 新工程（无节点）→ UniversalLibrary=False
scripts\workflows\create_kv_project.ps1 -ProjectName ULTest `
  -ProjectRoot C:\kvrun\ultest\Projects -CpuModel KV-X520 -OutDir C:\kvrun\ultest\create

# 配置一个 SV630N 节点 → 再读 WsTreeEnv.xml 出现 8 个 MC_* FB
scripts\workflows\configure_kv_ethercat_nodes.ps1 `
  -ProjectPath C:\kvrun\ultest\Projects\ULTest\ULTest.kpr `
  -NodesConfigPath C:\kvrun\ultest\ec\nodes.json -OutDir C:\kvrun\ultest\ec\workflow
```

`nodes.json`：

```json
{"schema_version":1,"nodes":[{"node_address":1,"catalog_model":"SV630_1Axis_03713"}]}
```

## 依赖顺序

1. 机器上已安装对应设备的 EtherCAT 支持文件。本机位置：
   `C:\ProgramData\KEYENCE\KVS\EtherCAT_Support\<Vendor>-<Model>_*.ecsup`；
   ESI 在 `C:\Users\Public\Documents\KEYENCE\KVS\EtherCAT\EtherCAT_esi`。
2. 用 `configure_kv_ethercat_nodes.ps1` 配置节点（节点号 + catalog_model）。
3. 配置保存后，KV STUDIO 生成 `UniversalLibrary` 树和机型固有 FB。
4. **再**导入引用这些 FB 的用户 MNM/变量；顺序反过来会得到"缺少 FB 类型"。
5. 复刻完成后用下面的断言确认依赖真的在。

## 断言工具

`scripts/workflow_tools/assert_kv_library_dependencies.ps1`（manifest：
`customer_non_ui_tool` / `published`，capability
`verify_universal_library_dependency`）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  scripts\workflow_tools\assert_kv_library_dependencies.ps1 `
  -ProjectPath <project.kpr|project-dir|WsTreeEnv.xml> `
  -RequiredLibrary Inovance_SV630N_V100 `
  -RequiredFbNamePrefix MC_ `
  -OutDir <out>
```

- 读取 `WsTreeEnv.xml`，只把"最深一层、直接拥有 FB 的目录"当作库目录，
  避免把 `Motor`/`EtherCAT` 这类分类目录也算成库。
- 失败码：`KV_LIBRARY_TREE_MISSING`（没有 UniversalLibrary 树）、
  `KV_LIBRARY_VENDOR_MISSING`（缺厂商目录）、`KV_LIBRARY_FB_MISSING`
  （没有指定前缀的 FB）。
- 输出 `library_dependency_result.json`（`ok`、库列表、FB 数、缺项、证据路径）。
- `tests\library-dependencies\run.bat`：7 例（合成树 + 真实 ULTest/新工程），全部通过。

## 边界

- 这里覆盖的是**设备随机型 FB**（Universal Library）。KV STUDIO 的
  `System\Library\SystemFB`、`DataUtilizationTemplate` 是另一套系统库，
  不在本断言的覆盖范围内；需要时按同样方式先补证据。
- 官方 FB 的 MNM 也可以离线导出，但把导出的 MNM 当普通用户 FB 重新导入
  只会得到同名用户 FB，**不会**恢复 `UniversalLibrary` 归属；不作为复刻路线。
