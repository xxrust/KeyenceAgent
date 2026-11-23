# KV STUDIO 12.41 安装示例索引

来源为 KV STUDIO 12.41.0.0 安装目录 `KVS/Language/2052`（简体中文）。以下路径均相对于该目录。宏依据安装文件内可读的厂商注释及《宏指令手册》`KvsMacro.pdf`。宏正文导出与运行验证尚未开展。

## SystemMacro｜宏包、CPU 与手册索引

`Library/SystemMacro` 有 13 类包、124 个宏名，各有 CPU 1000、3000、5000、5500、7300、7500、8000 版本。同名文件跨 CPU 的二进制有差异。此目录没有 Nano 或 KV-X 版本。以 `Library/SystemMacro/5500` 为导航：`DataCtrl`、`KL-2TFI`、`KL-2TFP`、`KL-DCLCI`、`KL-DCLCP`、`KL-WH1I`、`KL-WH1P`、`KV-AD40G`、`KV-H20G`、`KV-H20S`、`KV-H40S`、`KV-TF40`、`MV-L40`。旧 Wiki 中有 122 个宏名精确命中。两项新增入口为 `KL-2TFI/STSGET-2TFI.mcr`、`KL-2TFP/STSGET-2TFP.mcr`，用于查双通道运行、调谐、输出及 Alarm 状态的组合。I/P 版分别核对通信接口和状态位布局。

## 运动控制｜PLS-H20G、APSET1-H20G、ORG2-L40

`Library/SystemMacro/5500/KV-H20G/PLS-H20G.mcr` 的宏结束条件为运行开始请求受理。动作完成由调用方另行跟踪。`APSET1-H20G.mcr` 在启动条件不成立时可能结束且不报错，参数写入需另行确认。`Library/SystemMacro/5500/MV-L40/ORG2-L40.mcr` 区分读取参数、条件写入、参数写回和原点复归各阶段的错误码。参照这些案例设计请求受理、执行反馈、最终结果与恢复；具体反馈以目标 CPU 和单元手册为准。Nano CPU 定位示例见 `KVN14_Pos_CN.txt`，定位时序见 `KvsCpuPosNanoC.pdf`。

## 运算接口｜APRF、LIMITL、输出有效性

`Library/SystemMacro/5500/DataCtrl/APRF.mcr` 在标定表内插值、表外采用端点，点数不足时报错且保留旧输出。`LIMITL.mcr` 对正常越界作饱和，遇到上下限颠倒则报错并跳过运算。读这些宏时跟踪输入有效条件、输出更新条件与错误路径。Nano 如需定标，先核对原生 `APR` 指令及目标机型数据类型，可参考 Wiki 的 `APR.htm` 模拟电位器例程。

## 外设通信｜PROTOCOL STUDIO 设备预设与采集反馈

`DevData*/DevList.xml` 提供索引，`*.kpm` 为 PROTOCOL STUDIO 预设。`DevData_XLE` 有 49 项，LJ-X8000 的 2D/3D 分开，CV-X 有触发、配方、设定和错误清除，Modbus/TCP 预设含正常响应、异常响应及异常代码。用于核对目标设备的请求与应答。相机应按实际接口界定触发受理、采集完成或 PC 收到匹配帧的证据及超时。

## 运动单元｜KMP 流程、轨迹与采样

`KMP/motion_flow.html` 描述运动流程的并列分支、AND/OR 合并与子流程错误传播。`KMP/fain_control.html` 描述从 DXF/CSV 导入轨迹。`KMP/trace.html` 描述单元内部采样和停止触发。另有 `bezier.html`、`counter.html`、`motion_base.html`、`servo_p.html`。相关手册有 `KMPUSE.pdf` 和 `KV-ML_MC.pdf`。先确认动作时序、采样和故障由 PLC 或哪个单元负责，再确定 PLC 步序。功能与周期按目标单元核对。

## 其他安装资源

`MLS` 是 MV LINK STUDIO 参数帮助。`Settings` 内有 `kv700Sample01.lib`、`kv700Sample02.lib`、`kv2macro.lib`，具体程序内容待导出核对。`MessageTable` 和 `ResponseTable` 有结构化诊断条目，如 `AlarmCodeXhSV2.xml` 的 AlarmCode、AlarmName、AlarmContent。诊断引用需核对设备、固件与文档版本。
