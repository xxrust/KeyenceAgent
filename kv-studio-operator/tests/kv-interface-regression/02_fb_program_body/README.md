# 02 FB 程序体替换

## 操作内容

调用 `scripts/workflows/set_kv_fb_program_body.ps1`，使用 `fixtures/FB_Cylinder.mnm` 替换测试副本中 `FB_Cylinder` 的程序体。

## 测试目标

验证正式 workflow 能定位并打开 FB，删除原程序体，打开“编辑列表”，只提取 MNM 的程序体部分进行插入，关闭编辑列表并保存。MNM 中的 `DEVICE:`、`;MODULE:`、`;MODULE_TYPE:` 声明不会粘贴进程序区。

## 固定输入

目标模块为 `FB_Cylinder`，输入为 `fixtures/FB_Cylinder.mnm`。脚本要求 MNM 的 `;MODULE:` 与目标模块同名，且去除声明后仍有程序行。

## 执行方法

双击 `run.bat` 进行真实桌面测试；命令行使用 `run.bat -NoPause`。`-PlanOnly` 只生成并检查调度计划。

调用链为 `run.ps1` -> 公共 runner -> `set_kv_fb_program_body.ps1` -> flat executor -> `set_fb_program_body_guarded.ps1`。原子路径为选择 FB、Enter、Ctrl+End、Up、Ctrl+Shift+Home、Delete、Ctrl+D、粘贴程序体、Tab、Enter 插入、Ctrl+S。若 KV STUDIO 报助记符错误，脚本提取弹窗文本，Enter 关闭错误，再关闭编辑列表并失败退出。

## 通过标准

真实测试必须满足：`test_result.json` 为 `ok=true,status=pass`；`workflow/program_body_workflow_result.json` 为 `ok=true`；`workflow/artifacts/program_body/program_body_result.json` 为 `ok=true`；结果中的 `fb_module` 为 `FB_Cylinder`、`program_body_rows` 大于 0、`modal_closed=true`；`program_body_paste.mnm` 不含三类声明头；步骤 receipt 成功且 `workflow/run.log` 包含负载准备、编辑列表检测、插入和保存记录。

当前 runner 的成功判据是编辑列表已关闭并已保存，不包含独立的程序体重新导出或编译语义校验。因此本场景不能单独证明程序逻辑可编译；需要与编译或 MNM 导出场景组合才能扩大证明范围。

## 日志与结果

输出位于 `../runs/02_fb_program_body_<时间戳>/`。统一日志为 `workflow/run.log`；原子结果、实际粘贴文本、声明头及 receipt 位于 `workflow/artifacts/program_body/`；总结果和控制台输出位于运行目录根部。
