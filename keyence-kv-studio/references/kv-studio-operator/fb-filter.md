# 官方/库 FB 过滤

项目复刻时，官方/库 FB 属于依赖，用户 FB 属于源码。模块、EtherCAT、EtherNet/IP、Universal Library 可能自动导入官方 FB，其中很多不可编辑。导出 MNM 后先过滤：

```powershell
$ResolvedToolPath = '<path resolved from manifest customer_non_ui_tool filter_kv_mnm_user_sources>'
powershell -NoProfile -ExecutionPolicy Bypass -File $ResolvedToolPath `
  -InputDir '<raw-mnm-dir>' `
  -OutputDir '<filtered-mnm-dir>' `
  -ProjectPath '<project.kpr>' `
  -OutDir '<filter-report-dir>'
```

分类规则：

```text
if MODULE_TYPE != 2:
  copy
else if name in project WsTreeEnv official/library names:
  exclude
else if name matches ^(MC_|_MC_|\[MC\]_|_\[MC\]_|ModbusTCPClient_|SocketTCP_):
  exclude
else:
  copy as user_fb
```

报告文件：

```text
mnm_user_source_filter_result.json
```

FB 过滤依项目树证据、模块类型和官方/库模式分类。
