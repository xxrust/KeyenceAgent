# KV Nano 编程摘要

写、改或移植 Nano 程序前先确认 CPU 完整型号、端子排型或连接器型、扩展单元和实际 I/O 分配。把原工艺的输入、输出、时序和验收要求还原出来，再选 Nano 的指令和软元件。熟悉其他平台时尤其要重新核对地址、边沿、首扫、定时单位和轴完成条件。 [项目本体与行为验证](project-model.md) · [官方范例索引](nano-official-samples/README.md)

## 最容易凭习惯写错的地方

| 容易带入的假设 | Nano 编程时怎么判断 | 手册和范例 |
| --- | --- | --- |
| 按熟悉的地址前缀和点号直接换算 | 基本单元与扩展 I/O 看单元配置及端子表，输入和输出都用 `R`。`R000` 和 `R500` 是范例常见的基本单元输入、输出起址。看到 `R1500` 一类地址时，先查单元分配和读写点。标号用于程序引用，软元件注释用于说明，模块内的 `@MR000` 要连同所属模块追踪。 | 端子排型手册 p139–144，连接器型查对应型号手册。 [脉冲捕获](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59074) · [计数](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59082) |
| 用同一种首扫位初始化所有模块 | `CR2008` 是 PLC 开始运转后的首扫位，`@CR2008` 在所属模块或宏开始执行后的首扫接通。后备模块由 `MDSTRT` 启动后从下一个扫描周期执行。移植时追踪初值何时写入、是否会在模块重启时再次写入，以及 `MDSTOP` 后输出怎样处理。 | `KVSPRG.pdf` p182–183，指令参考 `MDSTRT, MDSTOP`。 [脉冲捕获](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59074) · [Modbus 主站](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59106) · [后备模块](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59126) |
| 按助记符字母猜边沿，或看到一个 `OUT` 就结束分析 | 左母线 `LDP/LDF`、串联 `ANP/ANF`、并联 `ORP/ORF`，每对依次为上升沿和下降沿。先区分软元件电平变化与传感器实际动作，再追踪 `CON` 后连接的指令和分支堆栈。导出里的 `CON` 可能保持前面回路的执行条件供后续指令使用，修改时保留等效连接。 | 指令参考 `LDP, ANP, ORP, LDF, ANF, ORF`、`CON`。 [通用边沿表](keyence-basics-and-pitfalls.md#边沿接点anp-是上升沿) · [连续定位](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_56810) |
| 把裸 `DM` 当成确定的数据类型，或把双字一律当有符号数 | `DM` 每地址 16 位。对支持这些后缀的数值指令，`.U/.S` 为无符号／有符号 16 位，`.D/.L` 为无符号／有符号 32 位，`.F` 占两字，`.DF` 占四字。逐条确认后缀、常数写法和占字范围。配置 HMI 或 PC 接口时同时核对数据宽度、符号和协议字序。 | 端子排型手册 p129–132、p145–147 及数据存储器章节。 [双精度运算](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59118) |
| 把所有定时器预置值当毫秒，或把 10 μs 刻度当成现场响应精度 | `TMR` 为 100 ms，`TMH` 为 10 ms，`TMS` 为 1 ms，`TMU` 为 10 μs。`TMU #0 #100000` 使用 T0，设定时间为 1 s。普通减定时器的误差包含扫描周期。检查作用域内是否重用了同一定时器，尤其是跨模块使用全局 T 号，并核对初始化模块及中断中对定时器的使用限制。 | 指令参考 `TMR, TMH, TMS`、`TMU` 的操作说明。 [脉冲捕获](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59074) |
| 把高速输入处理当作普通扫描接点，或每次都取到最新计数 | 先核对型号支持的端子、滤波和高速通道。官方脉冲捕获范例用 `HSP` 设置输入时间常数，`INT…RETI` 捕获窄脉冲，主扫描定时复位。计数范例用 `RFSCTH` 在比较前刷新 `CTH` 当前值。手册明确指出，对不支持的输入继电器使用 `HSP`，Nano 可无转换错误但指令不执行。 | 指令参考 `HSP`、`RFSCTH`，连接器型手册 p190–193。 [脉冲捕获](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59074) · [计数](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59082) |
| 把 KV 脚本当成 IEC ST，或认为框内逻辑每扫都运行 | Nano 使用梯形图、KV 脚本。框脚本在左侧回路成立时执行，域脚本占整行，在所属模块执行时每扫经过。框脚本被跳过时，差分函数的前态可能仍是上一次执行时的状态。定时器复位、边沿检测和输出的 OFF 分支要一起设计。导出 MNM 中脚本原文和普通注释均可能以分号开头，展开的梯形图也可能同时出现。 | `ScriptUse.pdf` p51–55。 [四则运算](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59114) · [梯形图与脚本收发](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59098) · [Nano 工程格式](../../kv-studio-operator/references/nano-project-format.md) |

## 定位和串口先追握手

- **CPU 内置脉冲定位。** 先核对轴及点参数、绝对或相对方式、脉冲当量、限位和原点输入。范例用 `PSTRT #0 #1 #6` 启动 CPU 的轴 1、点 6，`ORG` 用于回原点，`JOG` 用于点动。先查当前型号的指令和控制软元件，确认轴与点参数所有权，再设计启动及停止。 [定位范例](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_56810)
- **定位完成按本次请求确认。** 轴 1 的 `CR8400` 表示脉冲输出中，`CR8401` 表示定位完成，`CR8402` 表示轴错误，`CR8405` 表示原点复归完成。按手册区分命令软元件和只读状态。连续定位样本同时判断 `CR8401` 与 `CM8835` 的执行点号。目标等于当前位置或相对位移为零时，执行 `PSTRT` 可以无脉冲输出而完成。减速停止后定位完成位不会置位。接收方要能区分成功、拒绝、停止和故障退出，并清理等待及输出。若工艺需要机械到位或驱动器就绪，另外追相应反馈。依据为端子排型手册 p335–337、连接器型手册 p312–314，以及各自定位用软元件表。 [连续定位范例](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_56810)
- **串口按端口、模式和握手写。** 先确认单元设定里的实际端口、串口模式、波特率、帧格式和对端。官方 Port0 Modbus RTU 主站范例通过 `CM` 写站号、功能码和地址，用 `CR` 发命令并核回应答、错误及清请求。改成 Port1 时同时核对对应的控制、状态和缓冲区分配。上位机重发、超时或失联时如何清理，按本项目的接口定义验证。依据为 `KvsInternalSerial.pdf` p152–154 和相应端口软元件表。 [Modbus 主站范例](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_59106)

## 写完怎么验

1. 将关键回路的触发、电平、首扫、字宽和各类完成条件与手册和实际工程交叉核对。官方范例也会有注释和操作数不一致的情况。例如 14 点简体中文定位样本的 `Positioning_highspeed` 注释写点 1，实际执行 `PSTRT #0 #1 #5`。以实际操作数核对 CPU 点参数。 [定位范例](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_56810)
2. 在适用机型的工程副本中转换，核对警告、保存回读和扫描顺序。含 KV 脚本的工程用脚本入口保留可编辑性，按该工程实际导出编码和 `DEVICE:` 码处理文本。 [Nano 工程格式](../../kv-studio-operator/references/nano-project-format.md)
3. 按涉及的接口验证首扫或模块重启、短脉冲、命令拒绝、零位移、停止故障、超时和下一次请求恢复。物理动作与串口应答用相应的现场证据确认。官方范例的离线转换数据可按 CPU 与资源编号查阅。 [逐工程验证表](nano-official-samples/verification.tsv)
