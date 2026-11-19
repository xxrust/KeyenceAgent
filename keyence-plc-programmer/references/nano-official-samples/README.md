# KV Nano 官方范例程序

按目标 CPU 和功能打开范例文本，再按模块导航查看梯形图、KV 脚本或宏。库内共 60 份范例，定位按点型保留简体中文版，其他功能沿用官网提供的英文版。需要查看工程程序树、扫描顺序或单元参数时，从文本开头的官网下载链接获取原工程，在 KV STUDIO 中打开。 [基恩士中国样本目录](https://www.keyence.com.cn/support/user/controls/plc/software/sample-program)

## 按功能和 CPU 查看正文

| 功能 | KV-N14 | KV-N24 | KV-N40 | KV-N60 |
| --- | --- | --- | --- | --- |
| 定位（简体中文） | [14 点](source/KVN14_Pos_CN.txt) | [24 点](source/KVN24_Pos_CN.txt) | [40 点](source/KVN40_Pos_CN.txt) | [60 点](source/KVN60_Pos_CN.txt) |
| 脉冲捕获 | [14 点](source/KVN14_SignalConverter.txt) | [24 点](source/KVN24_SignalConverter.txt) | [40 点](source/KVN40_SignalConverter.txt) | [60 点](source/KVN60_SignalConverter.txt) |
| 比较器 | [14 点](source/KVN14_Comparator.txt) | [24 点](source/KVN24_Comparator.txt) | [40 点](source/KVN40_Comparator.txt) | [60 点](source/KVN60_Comparator.txt) |
| 高速计数 | [14 点](source/KVN14_Counter.txt) | [24 点](source/KVN24_Counter.txt) | [40 点](source/KVN40_Counter.txt) | [60 点](source/KVN60_Counter.txt) |
| PWM | [14 点](source/KVN14_PWM.txt) | [24 点](source/KVN24_PWM.txt) | [40 点](source/KVN40_PWM.txt) | [60 点](source/KVN60_PWM.txt) |
| 时钟脉冲停止 | [14 点](source/KVN14_Clockpulse.txt) | [24 点](source/KVN24_Clockpulse.txt) | [40 点](source/KVN40_Clockpulse.txt) | [60 点](source/KVN60_Clockpulse.txt) |
| 凸轮开关 | [14 点](source/KVN14_CamSwitch.txt) | [24 点](source/KVN24_CamSwitch.txt) | [40 点](source/KVN40_CamSwitch.txt) | [60 点](source/KVN60_CamSwitch.txt) |
| KV 文本收发 | [14 点](source/KVN14_TextSendReceive.txt) | [24 点](source/KVN24_TextSendReceive.txt) | [40 点](source/KVN40_TextSendReceive.txt) | [60 点](source/KVN60_TextSendReceive.txt) |
| 无协议串行通信 | [14 点](source/KVN14_NonProcedure.txt) | [24 点](source/KVN24_NonProcedure.txt) | [40 点](source/KVN40_NonProcedure.txt) | [60 点](source/KVN60_NonProcedure.txt) |
| Modbus RTU 主站 | [14 点](source/KVN14_ModbusMaster.txt) | [24 点](source/KVN24_ModbusMaster.txt) | [40 点](source/KVN40_ModbusMaster.txt) | [60 点](source/KVN60_ModbusMaster.txt) |
| 串行 PLC 链路 | [14 点](source/KVN14_PLClink.txt) | [24 点](source/KVN24_PLClink.txt) | [40 点](source/KVN40_PLClink.txt) | [60 点](source/KVN60_PLClink.txt) |
| 四则运算 | [14 点](source/KVN14_Calc.txt) | [24 点](source/KVN24_Calc.txt) | [40 点](source/KVN40_Calc.txt) | [60 点](source/KVN60_Calc.txt) |
| 双精度浮点运算 | [14 点](source/KVN14_Calc_DF.txt) | [24 点](source/KVN24_Calc_DF.txt) | [40 点](source/KVN40_Calc_DF.txt) | [60 点](source/KVN60_Calc_DF.txt) |
| 读保护功能 | [14 点](source/KVN14_Protect.txt) | [24 点](source/KVN24_Protect.txt) | [40 点](source/KVN40_Protect.txt) | [60 点](source/KVN60_Protect.txt) |
| 后备模块 | [14 点](source/KVN14_StandbyModule.txt) | [24 点](source/KVN24_StandbyModule.txt) | [40 点](source/KVN40_StandbyModule.txt) | [60 点](source/KVN60_StandbyModule.txt) |

## 使用范例

每个工程对应 `source/` 下的一份 UTF-8 文本，按模块和宏分节，保留助记符、KV 脚本和厂商注释。每节列出原导出 MNM 的 SHA-256。 [逐工程验证表](verification.tsv)

- 先按机型和模块导航定位程序，再读相应的助记符和注释。例如编写回原点逻辑时，查 `Origin_return` 的执行条件、原点输入、限位映射和完成反馈。
- 样本中出现的地址、轴号、点号、参数和输入有效条件属于样本工程。编写或修改实际工程时，按目标手册和工程快照核对这些条件，标明调用方需要提供的配置。 [项目本体与行为验证](../project-model.md)
- KV STUDIO 导出保留了以分号开头的 KV 脚本源行和说明。阅读时结合模块、脚本范围和实际助记符判定。简体中文定位样本的 `Positioning_start` 有一行标题注释在导出中显示为乱码，可结合该模块的执行指令和定位参数阅读。

## 定位程序导航

| 模块 | 在范例里查什么 |
| --- | --- |
| `Origin_return` | 回原点请求、限位输入、`ORG`、回原状态。范例用 `CR8401` 和 `CR8405` 组合判断。 |
| `JOG` | 正向、反向和高速选择与 `JOG` 指令的回路。 |
| `Positioning_start`、`Positioning_direct` | 启动已配置的定位点、写点参数后启动。阅读实际 `PSTRT` 操作数以确认点号。 |
| `PositioningConsecutively`、`Positioning_morethan20` | 连续定位通过 `CR8401` 和 `CM8835` 判断进度。重复使用同一个点时，先改写该点的目标坐标再启动。 |
| `Positioning_highspeed` | `HSP` 高速化输入，`INT` 中断内检查轴状态并调用 `PSTRT`。 |
| `Speedchange_relay`、`Speedchange_interrupt`、`Targetchange_function` | 运行中改速、比较器中断、改目标坐标。 |
| `Linear_Interpolation` 与插补宏 | 通过 `MCALL` 传入两轴和点参数，然后用 `PSTRT` 分别启动两轴。调用方按两轴的定位完成信号判断完成。 |

每种点型保留一份简体中文定位范例。程序文本中的 `DEVICE` 由 KV STUDIO 导出，KV-N14 为 135，KV-N24 为 134，KV-N40 为 133，KV-N60 为 132。

## 高速输入和计数导航

| 主题 | 在范例里查什么 |
| --- | --- |
| 脉冲捕获 | 首扫启用中断，`HSP` 处理输入，`INT R000` 置位输出，主扫描用 `TMU` 定时复位。厂商范例将窄脉冲延长到 1 秒。 |
| 比较器 | 首扫设置高速计数模式，以 `CTH.D` 计数、`CTC.D` 比较。范例达到比较值 1000 时置位输出，再复位比较器。 |
| 高速计数 | `INIT_CTH0` 给出相位差四倍频、滤波等初始化。主程序用 `RFSCTH` 刷新计数值，并按阈值控制软元件。 |
| PWM | `CTH1` 与 `CTC2/CTC3` 配合产生 PWM。厂商注释的例值为周期 500 μs、导通时间 200 μs。 |
| 时钟脉冲停止 | 用高速计数器和比较器中断停止输出。范例给出 2 kHz、累计 10000 脉冲后停止。 |
| 凸轮开关 | 以增量编码器作为 `CTH0` 的输入，按角度区间控制内部继电器。查相位差计数模式、分辨率和零点设定。 |

## 串行通信导航

| 主题 | 在范例里查什么 |
| --- | --- |
| KV 文本收发 | `Main` 中的调用条件，`Text_Ladder` 和 `Text_Script` 中的 Port0 发送、接收与出错处理。 |
| 无协议串行通信 | `NonProcedure_Ladder` 和 `NonProcedure_Script` 中的发送与接收配置、CR LF 结束符及错误输出。 |
| Modbus RTU 主站 | `ReadHoldingregister` 中的 Port0 请求、站号、功能码 03、起始地址和数量，以及应答、错误码和发送等待时间。 |
| 串行 PLC 链路 | 通过 Port1 改变从站号，并用系统继电器核对处理结果。查单元设置中的串行模式和初始站号。 |

## 运算与模块导航

| 主题 | 在范例里查什么 |
| --- | --- |
| 四则运算 | 用目标产量、实际产量和剩余时间计算每分钟目标值。对照脚本表达式、梯形图解法和 `WTIME` 的时间输入。 |
| 双精度浮点运算 | 用产量计算不良率 ppm。对照 KV 脚本和 `CAL-.DF`、`CAL/.DF`、`CAL*.DF` 梯形图指令。 |
| 读保护 | `Main` 中的厂商注释介绍 CPU 系统设定中的读写保护与项目加密。 |
| 后备模块 | `Main` 用 `MDSTRT` 和 `MDSTOP` 切换模块，并检查其他模块的执行状态。 |

## 验证范围

使用 KV STUDIO 12.41.0.0 打开样本工程副本、导出 MNM 并运行完整转换。每份文本的模块和宏清单与来源包核对，转换结果与编辑器机型均列入逐工程表。程序文本按模块文件名排列。硬件接线、单元设置和执行顺序以目标工程及手册为依据。 [逐工程验证表](verification.tsv)
