# 09 导入 FB 模块

## 操作内容

调用 `scripts/workflows/import_kv_fb_module.ps1`，把固定 MNM 作为功能块导入测试副本，目标模块名为 `FB_InterfaceProbe`。

## 测试目标

验证面向 agent 的 FB 导入接口会先检查 MNM 声明，再通过共享 MNM 导入 runner 操作真实 KV STUDIO，保存项目，并通过项目树位置检查确认模块位于功能块类别。

## 固定输入

`fixtures/FB_InterfaceProbe.mnm` 必须包含 `;MODULE_TYPE:2`，并声明或对应模块名 `FB_InterfaceProbe`。场景不请求删除已有同名模块；若副本已存在同名模块，workflow 应在发送导入输入前失败，而不是覆盖未知内容。

## 执行方法

双击 `run.bat`，或运行 `run.bat -NoPause`。调用链为公共 runner -> `import_kv_fb_module.ps1` -> 预处理 -> flat executor -> `import_mnm_guarded.ps1` -> `assert_kv_module_placement.ps1`。`-PlanOnly` 只生成 `fb_import_plan_result.json`，不代表导入成功。

## 通过标准

真实测试必须满足：`test_result.json` 和 `workflow/fb_import_result.json` 为成功；`workflow/fb_import_preflight.json` 为 `ok=true`；`workflow/artifacts/import_mnm/import_result.json` 为 `ok=true`，目标名为 `FB_InterfaceProbe` 且保存动作成功；`workflow/artifacts/module_placement/module_placement_result.json` 为 `ok=true` 并确认类别为 function block；两个步骤 receipt 成功；统一日志记录导入与位置验证。

仅文件选择成功、导入窗体关闭或项目树出现同名文本不算完整通过；必须同时满足导入 runner 结果和功能块位置门禁。本场景不自动证明 FB 自变量、局部变量或程序体语义完整，也不编译。

## 日志与结果

输出位于 `../runs/09_import_fb_<时间戳>/`。预处理与 workflow 总结果在 `workflow/`，导入证据在 `workflow/artifacts/import_mnm/`，位置证据在 `workflow/artifacts/module_placement/`，统一日志为 `workflow/run.log`。
