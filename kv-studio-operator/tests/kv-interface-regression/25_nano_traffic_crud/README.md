# 空白 Nano 交通灯程序与增删改查

从 KV STUDIO 的“新建项目”创建 `KV-NC32` 空工程，先回读 Main 确认为空，然后写入框脚本和梯形图。测试始终串行使用同一工程；重开前先关闭原进程，结束或失败均在 `finally` 中清理本次拥有的进程。

```bat
run.bat -NoPause -OutRoot C:\kvrun\nano_traffic_acceptance
```

输出目录必须不存在。双击 `run.bat` 会自动选择临时目录，结束后暂停。可通过 `-KvsExe` 指定本机 KV STUDIO。BAT 仅含 ASCII，返回 PowerShell 的原始退出码：通过为 0，测试失败为 41。工程保留在 `<out>/projects/NanoTraffic/NanoTraffic.kpr`，窗口默认关闭。

## 程序

这是使用软元件地址的编辑接口验收夹具，点位映射固定且全部写在下表。它不通过变量表批量重写工程。

| 地址 | 含义 |
|---|---|
| CR2008 | 启动首扫描，初始化到全红 |
| CR2006 / MR10 | 1 秒时钟 / 前扫描时钟状态；MR10 在全部脚本之后由梯形图保存 |
| DM0 | 循环秒位，0～27 |
| DM1 | 全红段诊断标记，不参与灯输出控制 |
| MR100 / MR101 | 南北绿灯 / 黄灯请求 |
| MR102 / MR103 | 东西绿灯 / 黄灯请求 |
| R500 / R501 / R502 | 南北红 / 黄 / 绿灯 |
| R503 / R504 / R505 | 东西红 / 黄 / 绿灯 |
| DM10 | 诊断脚本复制当前循环秒位，用于增改删验证 |
| DM11 | 临时诊断语句的目标；删除语句后不再写入 |
| MR200 | 临时梯形图增改删目标，最终程序中不存在 |

28 秒循环：南北绿 10 秒 → 南北黄 3 秒 → 全红 1 秒 → 东西绿 10 秒 → 东西黄 3 秒 → 全红 1 秒。首扫描直接初始化到全红，并跳过该扫描的时钟计数。脚本写请求，梯形图按对向黄/绿请求互锁后驱动灯，红灯由本向黄/绿输出均关闭产生。

`phase.txt` 是 KV 脚本语法（`=`、`IF … THEN`、`ELSE IF`、`END IF`），不是 IEC ST。`ladder.txt` 是普通梯形图助记符。Nano 不使用 ST/FBD，也不尝试将带脚本的 MNM 反向导入。

知识库依据：`pdf::KvsPtcPtoNano::chunk-001#p2`（Nano 时钟与首扫描继电器）、`chm::KVSSCR--SCRIPTPROG4CHM-FC37_Script_4-3-help_topic_start6.htm::chunk-001#p1/#p2`（KV 脚本条件语句）、`chm::InstructionRef--KVSREF-FC24CM_021J-LD_LDB_AND_ANB_OR_ORB.htm::chunk-001`（梯形图接点）。

## 验收

测试覆盖框脚本新增、全文读取、修改、删除语句、旧源码不符拒绝、删除整个框及回路、重新新增；另覆盖普通梯形图回路新增、读取、修改和删除。每次写入必须编译成功。删除后核对相邻脚本和输出回路位置，保存、关闭、重开同一路径后再逐字回读两个脚本和全部 7 个梯形图回路。

查看 `test_result.json`、每个操作的 `workflow_result.json`、`artifacts/operation/nano_operation_result.json`、`artifacts/compile_result/compile_result_copied.txt` 与 `step_receipt.json`。预期旧源码不符必须令 workflow 失败，由 harness 单独判定负例通过。

`before_processes`、`after_processes`、`cleanup` 和 `leaked_owned_processes` 记录生命周期。仅按本次启动记录或完整项目命令行识别进程，并复核 PID 与启动时间；不关闭测试前已有进程。正常结束优先使用正式 Close workflow；失败窗口阻塞关闭时，有界清理本次测试进程。关闭失败会令测试失败。

真实桌面验证范围是工程编辑、转换、保存和重开回读。未连接或下载到 PLC，不能据此宣称现场交通信号运行已验收。KV-X 保持原有工作流，新接口在输入前拒绝非 Nano CPU。

`verify_logic.py --run <out>` 对本次重开回读的源码做独立离线语义检查：20 组启动初值、3 个完整周期共 8400 次扫描、16 种灯请求组合。它核对启动全红、10/3/1 秒相位、每秒只计数一次及对向互锁，结果为 `logic_verification.json`。这是受限源码解释测试，不是 KV STUDIO 仿真器或真实 PLC 运行证据。

2026-11-17 真实桌面验收通过：`C:/kvrun/nano_traffic_bat_20261117_pass/test_result.json`，32 项检查，最终转换 146 步 / 113 指令，0 错误、0 警告。测试前后 Kvs 进程快照均为空，`cleanup.method=workflow_close`，`leaked_owned_processes=[]`。实际版本为 KV STUDIO 12.41.0.0，目标 CPU 为 KV-NC32。各操作的步骤回执记录脚本指纹与输入文件 SHA256。
