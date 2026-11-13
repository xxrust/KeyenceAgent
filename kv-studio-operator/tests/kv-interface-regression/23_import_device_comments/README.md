# 23 Import Device Comments

本场景验证「软元件注释表写回」这条路线：把一张 CSV 注释表读进工程，保存，再**导出回读逐条比对**。
验收口径是回读差异为 0，而不是导入对话框自己弹的那句「读取了 N 个软元件注释」。

## 调用链

```
run.bat / run.ps1
  └ run-workflow-test.ps1（公共 harness：复制样例工程 → 预检计划 → 真机执行 → 清理进程）
      └ scripts/workflows/import_kv_device_comments.ps1
          ├ runner_children/import_device_comments_guarded.ps1
          │    文件(F) → 读取 CSV/TXT 格式的软元件注释(Q)...  →  Ctrl+S
          ├ runner_children/export_device_comments_guarded.ps1（回读导出）
          └ workflow_tools/verify_kv_device_comments_import.ps1（逐设备 diff）
```

## 前置

- 本机 KV STUDIO 12 已安装（`get_kvstudio_install.ps1 -Probe` 可查）。
- 桌面空闲：harness 与 workflow 都会抢 `Local\KeyenceAgent.KvStudio.UI`，另一个 KV 工作流在跑时直接失败。
- `open_project: false`：由 workflow 自己启动 KVS，因此可以验证「冷启动」这条分支（快照曾经在这里踩过坑）。

## 输入

`fixtures/comments_regression.csv`（ANSI/GBK，与 KV STUDIO 导出的表同格式）：

```
,,注释 1,注释 2,注释 3,注释 4,注释 5,注释 6,注释 7,注释 8,
MR001,,回归_甲,,,,,,,,
MR002,,回归_乙,,,,,,,,
DM100,,回归_数据字,,,,,,,,
```

选中文注释是为了同时验证非 ASCII 的往返；三条足以覆盖「新增行 / 覆盖已有行 / 字软元件」。

## 判定

harness 的 `test_result.json` 之外，`run.ps1` 还做三条后置断言（失败则整体 exit 1）：

1. `comment_import_verification.json`：`ok=true`、`verified>=3`、`mismatch_count=0`；
2. `device_comments_import_result.json`：`saved=true`（导入后确实保存，否则注释只停在内存里）；
3. 工程目录下的 `*.cm1` 注释库存在且非空（注释真正落盘）。

## 已验证的 KV STUDIO 行为（改脚本前先看）

| 现象 | 处理方式 |
|---|---|
| 文件名框是 `ComboBoxEx32 > ComboBox > Edit` 共用 id 1148，`GetDlgItem` 拿到的是外层容器 | 用 `EnumChildWindows` 找内层 `Edit` |
| `WM_GETTEXT` 对该 Edit 读回空串 | 改用 UIA 读（`ClassName=Edit` + `AutomationId=1148` 的 `Current.Name`） |
| 完成提示框是 DirectUI：无 HWND 按钮，UIA 里全是 `ControlType.Pane` | 文本白名单 + `Enter`（`AllowTargetClose`），绝不盲点 |
| `InterpreterC` 是不可见常驻窗口 | `IsWindowVisible` 过滤 |
| 对话框会在「无弹窗」之后才出现 | 3 s 沉降窗口 |
| 设备名被归一化（`MR0001→MR001`、`DM0001→DM1`、`B0B` 十六进制） | diff 前做 key 归一 |

## 边界

- 只验证**软元件注释**（`.cm1`）；不涉及变量表注释列与设备绑定变量。
- 不验证注释在梯形图里的显示效果（那是 UI 渲染，肉眼/截图判断）。
- 不验证并发：同一时刻只允许一个 KV workflow。

## 跑法

```powershell
# 双击 run.bat，或：
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -OutRoot C:\kvrun\s23
# 只验证计划，不碰桌面：
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -PlanOnly
```
