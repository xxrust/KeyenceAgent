# Nano 单元编辑器与内置串口

能力 `nano_unit_editor_crud` 的公开入口是
`scripts/workflows/manage_kv_nano_units.ps1`。限定 KV-NC32 工程；不能套到
KV-X。工程树的型号扫描和单元编辑器主参数表扫描是不同层次。

## 已接入的对象

| 对象 | Query 读取内容 | 写入与生命周期 |
|---|---|---|
| CPU KV-NC32 | 型号、顺序、I/O 分配、输入时间常数、Port0 串口模式/波特率/数据位/起始位/停止位/校验、功能扩展适配器 | CPU 不可删除；Port0 是固有硬件，配置可修改及恢复，不能添加/删除一个物理端口 |
| KV-NC1EP | 型号、位置、R/DM 分配及主参数表 67 行，包括 IP、掩码、网关、DNS、超时、端口号、EtherNet/IP 公共参数、FTP/MC/SNTP 公共参数 | Add/Delete 作用于模块；SetParameter 修改主表参数，IP 地址已实测 |
| KV-NC16EXT* | 型号、位置、输入/输出分配、主参数表 5 行，包括输入滤波和连接器类型 | Add/Delete 作用于模块；输入滤波已实测修改及恢复 |

`KV-NC16EXT*` 是本机目录与工程中的实际显示名称，接口按原文匹配。
型号后星号与参数值的默认标记 `(＊)` 不要混为一谈。参数值按编辑器
原文比较，不能随意去掉默认标记或单位。

Query 输出 `artifacts/units/units.json`：每个对象包含 `unit_index`、
`model`、工程树的 `allocation` 和完整 `rows`。每行三个字符串，
`row[1]` 是参数名、`row[2]` 是值。原生列表读取包含滚动区之外的行；
截图仅作为辅助证据。`nano_unit_result.json` 和 `workflow_result.json`
提供进程身份、执行回执及错误码。

**范围：主参数表及内置 Port0。** NC1EP 中显示 `<设定>` 的
EtherNet/IP 连接设备表、FTP 客户端、简易 PLC 连接、邮件等子窗口
没有因读到 `<设定>` 而被扫描或验证。KV-X 的 EIP 工程树入口不能直接
用于 Nano NC1EP。该接口也不执行 PLC 传送、在线通信或 I/O 动作验证。

## 调用

```powershell
# 完整读取当前三个单元的主表。
powershell -STA -NoProfile -ExecutionPolicy Bypass -File <scripts>/workflows/manage_kv_nano_units.ps1 `
  -ProjectPath <copy.kpr> -OutDir <query> -Action Query

# 旧值不符时停止；修改后自动保存，并重开单元编辑器回读。
powershell -STA -NoProfile -ExecutionPolicy Bypass -File <scripts>/workflows/manage_kv_nano_units.ps1 `
  -ProjectPath <copy.kpr> -OutDir <write> -Action SetParameter `
  -UnitIndex 1 -ExpectedModel KV-NC1EP -ParameterName 'IP 地址' `
  -ExpectedValue 192.168.0.10 -Value 192.168.0.20

# 仅追加：UnitIndex 必须等于已保存工程的现有单元数。
powershell -STA -NoProfile -ExecutionPolicy Bypass -File <scripts>/workflows/manage_kv_nano_units.ps1 `
  -ProjectPath <copy.kpr> -OutDir <add> -Action Add `
  -UnitIndex 2 -ExpectedModel 'KV-NC16EXT*'
```

`Delete` 同样要求 `UnitIndex` 与 `ExpectedModel`；禁止删除 CPU。
Add/Delete/SetParameter 自动组合为：操作 → OK 提交 → 保存 → Query
回读。增删后核对完整型号顺序；修改后核对保存值。进程重启后的验证
由 `manage_kv_nano_program.ps1 -Action Reopen` 加 Query 完成。

`-ExpectedSnapshotPath <units.json>` 在 Query 时比较完整模块表。
切换串口模式等存在关联参数变化的操作，应提前规划完整目标 `rows`
JSON，以 `-ExpectedAfterRowsPath` 冻结；否则任何非目标行变化都会报错。
这不等于所有模式和关联参数都已获支持，新增组合要在副本中单独验证。

Query 保留单元编辑器供下一步操作。结束时调用 `Cancel` 关闭它，再用
程序接口 `Close` 关闭自己打开的工程。BAT 的 finally 会按 PID 与启动
时间清理所属进程，保留测试前的窗口。

## 编辑器特性

- MFC owner-draw 参数列表没有完整 UIA 文本；用所属进程中的
  `LVM_GETITEMTEXTW` 读主表，用控件 703 的选中单元标题交叉核对。
- 单元画布会自动水平滚动。选择时扣除实际水平滚动量；不支持屏幕外
  的单元时停止，不猜坐标。当前已验证位置 0、1、2。
- 添加单元会根据选中的槽位插入。先选末尾空槽，确认目录型号，再添加；
  不能默认 Enter 总是追加。每次添加后保存，再从工程树复核完整顺序。
- 下拉框用原生选项枚举和原生选择通知；快速组合 Home/Down/Enter
  在此控件中可能改变错误值。写入必须对照整表回读。
- 删除和放弃修改分别有不同的原生确认框，只接受实测标题、正文、
  按钮指纹，未知窗口停止。删除模块可能使相关程序引用失效，测试用
  空工程。原工程只读扫描，业务工程的最终拓扑应先规划再执行。
- 串口模式变化提交时，KV STUDIO 可能询问是否在改变后的 CR/CM
  分配区登录样例注释。接口精确识别此提示并选择“否”，保留已有系统
  注释。不要为了关闭弹窗通用点击“是”。

## 本次工程的读取结果

原工程 `Downloads/纯48/纯48.kpr` 的副本初始值：

| 单元 | 读取结果 |
|---|---|
| [0] KV-NC32 | R000/R500；输入时间常数 10 μs；Port0 为 KV 模式（上位链路）、9600 bps、8 位、1 起始位、1 停止位、偶校验；扩展适配器无 |
| [1] KV-NC1EP | R1000、DM10000；占用 DM 230、继电器 640；IP 192.168.0.10，掩码 255.255.255.0，网关 0.0.0.0；B0000/W0000 自动分配 |
| [2] KV-NC16EXT* | R5000/R5500；占用继电器数 96；输入时间常数 10 ms；MIL 连接器 |

占用继电器数是保留地址空间，不是物理端子数。NC16EXT 是 16 输入加
16 输出。Nano 手册给出的输出起始编号为输入起始编号 +500。

主表中几个容易误解的字段：

- NC1EP 的起始 R/DM 是模块控制、状态等软元件区的基址，需要与其它
  单元的保留区避让；不能把 IP 设备的 I/O 数据区与模块本身占用区等同。
  B/W 起始编号和自动分配则用于 EtherNet/IP 的数据分配。
- NC1EP 的 IP、子网掩码、网关决定模块网络地址；8500 等端口号分别
  属于表中指定的服务。这里的工程设定保存不代表模块已获得新地址。
- NC16EXT 的输入时间常数影响输入响应与抑制短脉冲的取舍。手册列有
  25 μs、300 μs、1 ms、10 ms；本次用 10 ms → 1 ms → 10 ms 验证编辑。
  连接器类型要匹配实物，不能把软件选项当作电气接口转换。
- CPU 的串口动作模式会决定协议及哪些通信参数可改。空工程默认
  “KV STUDIO 模式、自动波特率”，切到“KV 模式（上位链路）”后波特率
  变为 9600 bps；这属于关联变化，应把两行一起纳入预先冻结的目标表。

依据保存在 `C:/kvrun/nano_units_20261117/kb_{ep,ext,serial}.json`：
`pdf::KvsEtherNetIP_KVS11::chunk-038`、
`pdf::KvsHardNanoC::chunk-014`、`chunk-027#p1`、`chunk-174#p2`、
`pdf::KvsInternalSerial::chunk-010`、
`pdf::KvsHardNanoC::chunk-019#p1`。内置 Port0 为 RS-232C，使用它无需
串口扩展适配器。连接适配器是另一种硬件配置，不能把它当作 Port0 删除。

## 可重复验证

`tests/kv-interface-regression/27_nano_units_crud/run.bat -NoPause -OutRoot <new-dir>`
创建独立空 KV-NC32 工程，验证两种模块的添加、删除、重新添加，
串口模式/波特率、NC1EP IP、NC16EXT 滤波的修改及恢复，拒绝旧值
不符的写入，并在进程重启后比较全部主表，最后关闭所属进程。
以该次 `test_result.json` 为验收依据，不能把创建计划或单步成功当作
整条回归通过。

2026-11-17 / KV STUDIO 12.41：
`C:/kvrun/nano_units_bat_20261117_f/test_result.json` 为 `ok=true`，
43 项通过、0 失败。三个重开阶段分别核对修改、删除、重新添加后的
主表；cm1/cm2 哈希不变，所有所属进程正常关闭，原有三个用户进程保留。
原工程副本读取证据在 `C:/kvrun/nano_units_20261117/query_a/artifacts/units/units.json`；
原工程 33 文件哈希核对 0 变化，见同目录下 `source_integrity.json`。

读取能力已登记在 ontology 的 `nano_unit_parameters` 和
`nano_serial_port`。它们当前由公开 Query 显式读取，尚未接入通用整项目
快照 stage；不能声称已有通用快照就自动包含 Nano 详细参数。
