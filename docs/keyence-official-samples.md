# KEYENCE 官方示例程序与编程资料

以下为基恩士官网入口和资源编号，目录及适用机型于 2026-11-18 核对。

## KV Nano

中国官网有独立的样本程序页，覆盖定位、脉冲捕获、比较器、高速计数、PWM、时钟脉冲停止、凸轮开关、串行通信、算术和其他功能。目录按 14、24、40、60 点型列出资源。 [官方样本程序目录](https://www.keyence.com.cn/support/user/controls/plc/software/sample-program/)

截至 2026-11-19，目录中的 68 个工程均已在 KV STUDIO 12.41.0.0 打开、导出并通过离线转换，共核对 248 个模块和宏。编程技能提供每个工程的导出文本、模块阅读导航和逐工程验证表。每份文本开头附原工程官网下载链接。 [Nano 范例索引](../keyence-plc-programmer/references/nano-official-samples/README.md)

| 主题 | 官方入口 |
| --- | --- |
| 简体中文定位示例 | [14 点型 AS_56810](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_56810) · [24 点型 AS_56825](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_56825) · [40 点型 AS_56840](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_56840) · [60 点型 AS_56855](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_56855) |
| 中断、高速计数器等内置功能 | [内置功能样本](https://www.keyence.com.cn/support/user/controls/plc/software/sample-program/#lineup-2) |
| KV 文本收发、无协议通信、Modbus RTU 主站、串行 PLC 链路 | [串行通信样本](https://www.keyence.com.cn/support/user/controls/plc/software/sample-program/#lineup-3) |
| 四则运算、双精度浮点运算 | [运算样本](https://www.keyence.com.cn/support/user/controls/plc/software/sample-program/#lineup-4) |

该目录没有单列 KV-NC32。基恩士规格页将 KV-NC32 列在连接器型下。引用点型示例到连接器型工程前，核对实际 CPU、端子分配与定位功能。 [Nano 规格表](https://www.keyence.co.jp/products/controls/plc-package/kv_nano/specs/#a13)

## KV-3000、KV-5000、KV-5500

已确认以下官方资料标注相关机型。本次未核实到明确标注这些 CPU 的公开、可编辑 KV STUDIO 示例工程包。日本官网的 KV 系列样本程序页当前列出的下载项标注为 KV-8000 用。 [系列下载页](https://www.keyence.co.jp/products/controls/plc-building/kv-5000_3000/downloads/?mode=so) · [日本官网样本程序页](https://www.keyence.co.jp/support/user/controls/plc/program/)

| 资料 | 官网标注与内容 |
| --- | --- |
| KV 脚本活用指南 | KV-5500／5000／3000。脚本实例包括三角函数和不合格率计算。 [中文版 AS_58033](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_58033) |
| 定位单元活用指南 | KV-5500／5000／3000。脉冲和省配线定位单元。 [中文版 AS_16293](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_16293) |
| KV-ML16V × SV 快速入门 | KV-5500／5000／3000。含设备配置和梯形图示例。 [日文版 AS_15910](https://www.keyence.co.jp/download/download/confirmation/?dlAssetId=AS_15910&dlSeriesId=WS_139713&wl=1) |
| KV-5000 ↔ KV-5000 简易 PLC 链路 | 官网列在 KV-5500／5000／3000 资料下，示例两端均为 KV-5000。 [日文版 AS_88110](https://www.keyence.co.jp/download/download/confirmation/?dlAssetId=AS_88110&dlSeriesId=WS_139713&wl=1) |
| KV-7500／5500 × DL-EP1 | 标题明确列出 KV-5500，用于确认设备和 EtherNet/IP 连接配置。 [中文版 AS_82225](https://www.keyence.com.cn/download/download/confirmation/?dlAssetId=AS_82225) |

资料全集可按机型和主题继续查阅。 [基恩士中国 PLC 技术资料库](https://www.keyence.com.cn/landing/controls/lp_controls_library_plc.jsp) · [基恩士日本 PLC 技术资料库](https://www.keyence.co.jp/landing/req/controls/library/plc_1126_01.jsp)
