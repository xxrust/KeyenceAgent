# KV ST 字符串、时间与设备接口

用于字符串处理、字节协议、时间、文件/网络 FB 和运动接口。这里的函数名、参数顺序与握手形状是 KEYENCE 专有接口；型号相关或证据不足时须查 Wiki/项目，不自行替换成其他 PLC 的同名函数。

## 字符串和字节

```st
diResult := DecStringToNum(strData);
uiResult := AsciiToBinary(uiData);
udiResult := HexStringToNum(strHex);

strData1 := LEFT(strRxData, 10);
strData2 := MID(strRxData, 10, 6);
strData3 := RIGHT(strRxData, 10);
strDisplay := REPLACE(strInitial, strReplacement, 5, 9);
nCount := SplitN(strSource, ',', astrDestination);
```

保留已见顺序：`MID(source, length, start)`，`REPLACE(source, replacement, position, length)`。协议以字节计数时，不能默认 `LEN(STRING)` 等于编码字节数；CRLF 是否计入、字节序、目标宽度和溢出策略需由协议确认。

```st
uiLength := LEN(strCommand);
strTx := INSERT(strCommand, NumToDecString(uiLength, TRUE, TRUE), 0);
strLine := 'AW,1000,2000' + AsciiToString(16#0D0A);
```

`AsciiToBinary`、`AsciiToString`、`DisperseByte`、`UniteByte`、`ByteSum`、`AryCRC` 各有不同的数据形状，不能混用；校验算法、长度单位、初值和输出字节序要按协议/KB 核实。

## 控制器时间

```st
strTimeStamp := NumToDecString((_CurrentDateTime[0] + 2000), TRUE, TRUE) + '/'
              + RIGHT(NumToDecString(_CurrentDateTime[1], FALSE, TRUE), 2) + '/'
              + RIGHT(NumToDecString(_CurrentDateTime[2], FALSE, TRUE), 2) + ' '
              + RIGHT(NumToDecString(_CurrentDateTime[3], FALSE, TRUE), 2) + ':'
              + RIGHT(NumToDecString(_CurrentDateTime[4], FALSE, TRUE), 2) + ':'
              + RIGHT(NumToDecString(_CurrentDateTime[5], FALSE, TRUE), 2);
```

年份偏移、`_CurrentDateTime` 元素定义、时区和日期计算依目标 CPU/项目。生产时间估算可见 `DtToSec(_CurrentDateTime)` / `SecToDt(...)` 形状；不能把主机语言日期 API 当作 ST 替代品。

## 文件与网络握手

```st
StorageReadLine1(
    Execute := xRead, Path := strPath, MaxReadLineNum := 1,
    MaxByteSize := 0, ReadPos := udiReadPos, Dst := strLine,
    ByteSizeRes => uiByteSize, ReadLineNum => uiLineCount,
    EOF => xEof, NoCRLF => xNoCrlf, Done => xDone,
    Busy => xBusy, Error => xError, ErrorID => uiErrorID);

Ping1(Execute := xPing, DstAddress := strAddress, Timeout := uiTimeout);
IF Ping1.Done THEN
    xConnected := TRUE;
END_IF;
```

存储/通信 FB 通常按扫描周期调用；Execute、Busy、Done、Error 和 ErrorID 应纳入显式状态/握手设计。路径、结构体容量、地址及 timeout 范围不可凭空决定。

## 运动接口边界

```st
MC_MoveAbsolute1(
    Axis := Axis1, Execute := xExecute, Position := lrPosition,
    Velocity := lrVelocity, Acceleration := lrAcceleration,
    Deceleration := lrDeceleration, Jerk := uiJerk, Direction := uiDirection,
    BufferMode := uiBufferMode, Done => xDone, Busy => xBusy,
    Active => xActive, CommandAborted => xCommandAborted,
    Error => xError, ErrorID => uiErrorID);
```

轴、伺服使能、原点/限位/报警、安全互锁和单位必须来自真实工程配置。LD 网络中的助记符或 `FUN` 不能冒充 ST 主体。型号、运动库和参数语义未知时，先用 `kv-studio-kb-programming` 查询并由 `kv-studio-operator` 实际验证。
