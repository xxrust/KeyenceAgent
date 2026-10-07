# 19 编译错误诊断

本项验证预期编译失败。使用用户提供的 `ColdNumericST` 故障工程，原先位于 `19_`，
现保存在 `fixtures/ColdNumericST`；不修复其故意保留的错误，也不修改原始工程。
每次运行先复制到独立 run 目录，再通过公开 `compile_kv_project.ps1` 实际编译。

## 固定输入与预期

CPU：KV-X520。本机 KVS12 中文诊断，固定预期见
[expected_compile_result.txt](fixtures/expected_compile_result.txt)。真实编译应报告 4 条错误、4 条警告：

- `ColdScaleCaller` 和 `ColdScaleCallerSaved`，ST 行 0007：错误 1318，`Sum => ScaledSum` 指定了不存在的带名称自变量。
- `FB_ColdScaleFour`，ST 行 0002、0010：错误 1232，`Sum` 为非法字符串。
- 四个模块各有一条 ENDH 警告 33。

原工程是 KV STUDIO 专有二进制；这里不根据文件名猜测其程序内容。
预期清单来自首次真实编译的完整诊断，并在正式验收前冻结。不会在每次测试时自动重新生成预期，
也不会自动修改故障工程使其编译通过。KV 版本、语言或诊断变化时，必须人工审查预期差异。

## 运行

双击 `run.bat`，或执行：

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\run.ps1
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -PlanOnly
```

支持 `-OutRoot <directory>` 和 `-KeepProjectOpen`。PlanOnly 不操作 UI、不证明编译失败可读回。
本项会由 `run-all.ps1` 在启用后自动发现。另有同名用户工程时，按独立副本的完整路径绑定，
不关闭或修改同名工程。默认仅在预期失败证据全部通过时关闭本次启动的测试进程。

## 通过条件

`test_result.json` 必须 `ok=true/status=pass/expected_failure_verified=true`，但原始
`workflow/workflow_result.json` 必须保持 `ok=false/status=fail/error_code=KV_COMPILE_RESULT_NG`，
实际 workflow 退出码为 1。测试 runner 最终退出码为 0。二者含义不同，不能改写编译失败为成功。

断言还要求：

- 前置 gate 和实际编译步骤成功，唯一失败步骤为 `copy_compile_result`；缺失步骤、超时和普通脚本错误拒绝。
- 同次 workflow、编译/复制 receipt 的 run_id、代码指纹、工程路径及时间顺序一致。
- `compile_result_copied.txt` 位于本次固定输出目录，晚于复制步骤开始时间；不能复用旧运行结果。
- NG 头的错误/警告数量与实际诊断行数一致，全部诊断与固定预期逐行相等。
  仅统一换行并去掉行首尾空白，不忽略模块、ST 行号、错误编号、消息或警告。
- 原始 fixture 文件指纹未变。测试结论记录完整错误文本及证据 SHA256。

仅有 NG 弹窗、只有 NG 标题、错误文本被截断、错误模块不符、启动失败、焦点失败、
超时或缺失错误文件均不能算通过。不要求错误提取路径每次相同，只要求诊断内容与归属完整。

## 证据

真实正式验收已通过：
`H:/kvOp/compile_error_regression_20260920/acceptance/19_compile_error_20260920_212346_389_6d658f72`。
测试 `ok=true`，原 workflow `ok=false`，4 条错误、4 条警告完整一致；独立测试进程已清理。
实际 workflow 耗时 10.627 秒；第 05 项正常编译对照也通过，耗时 13.599 秒：
`H:/kvOp/compile_error_regression_20260920/positive_control/05_compile_20260920_212504_824_2cef412b`。
两项执行代码指纹一致：`629BD2E64E77E26B4FC3952EA3FA5EBC7B8051A936AF13127FD81F34C1097FC7`。
21 项非 UI 证据正反例及 19 项能力发现检查也已通过。

首次诊断采集（不计正式通过）：
`H:/kvOp/compile_error_regression_20260920/discovery/19_compile_error_20260920_211747_621_79a721ea`。
该次诊断工程 PID 11236 在完成审查后，按原启动时间和精确命令行路径核对并清理；
保留其失败结果及诊断文件，不将其改为正式通过。

输出包括 `expected_failure_validation.json`、`fixture_fingerprints.json`、`process_lifecycle.json`、
`test_result.json`，以及 workflow 下的原始失败结果、日志、receipt 和完整编译诊断。
非 UI 反例测试：`tests/test_expected_compile_failure.ps1`；它不能代替本项真实 KV STUDIO 执行。
